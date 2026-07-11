// A real-git scratch-repository harness: spins up an ephemeral temp
// directory, `git init`s it, and drives every subsequent git call through
// the app's OWN production wrapper — `runGit` in backend/git.dart — so a
// fuzzed sequence of operations exercises the exact non-interactive,
// semaphored, retrying subprocess path the real app uses, not a
// reimplementation of it.
//
// `runGit` is already imported directly by several backend tests (see
// test/backend/git_exec_env_test.dart, local_pr_merge_test.dart, ...), so it
// is proven importable/usable from `flutter_test` — no fallback to a raw
// `Process.run` was needed for any operation here, `git init` included
// (`runGit` only needs `workingDir` to exist as a directory; it has no
// dependency on a `.git` already being present).
//
// Every call this file makes is additionally isolated from the invoking
// machine's global/system git config (a stray `commit`/`merge`/`stash`
// alias, credential helper, or `includeIf` directive must never leak into a
// fuzz run) via `GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`
// pointed at paths inside the scratch repo's own temp dir that are never
// created — git treats a missing config file as empty, silently, exactly
// like a fresh machine with no `~/.gitconfig`. Repo-local identity
// (`user.name`/`user.email`), `commit.gpgsign`, and `core.autocrlf` are then
// set as local config on top, per the spec.

import 'dart:convert';
import 'dart:io';

import 'package:git_desktop/backend/git.dart';
import 'package:path/path.dart' as p;

/// A real, ephemeral, non-interactive git repository for exercising git
/// behaviour end-to-end. Always dispose it (`dispose()`) when done.
class ScratchRepo {
  /// The repo's working tree root.
  final Directory dir;

  /// The private parent directory [dir] lives inside. Nothing else is ever
  /// created here, which is what makes "did a git op escape the repo?"
  /// answerable by listing `dir.parent`.
  final Directory _sandbox;

  ScratchRepo._(this.dir, this._sandbox);

  /// Environment overlay applied to every git call this harness makes,
  /// layered as `runGit`'s `extraEnv` on top of its own
  /// [kNonInteractiveGitEnv] base (see backend/git.dart) — never shadows
  /// `GIT_TERMINAL_PROMPT`/`GIT_OPTIONAL_LOCKS`/`LC_ALL`, only adds the
  /// global/system config isolation described above.
  Map<String, String> get _isolationEnv => {
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': p.join(dir.path, '.scratch-no-global-gitconfig'),
        'GIT_CONFIG_SYSTEM': p.join(dir.path, '.scratch-no-system-gitconfig'),
      };

  /// Creates a fresh temp directory, `git init`s it with the default branch
  /// pinned to `main`, sets deterministic local identity + non-interactive
  /// config, and creates an initial empty commit so `HEAD` always resolves
  /// from the moment [create] returns.
  /// [objectFormat] pins `git init --object-format=<fmt>` (e.g. `'sha256'`)
  /// so a test can exercise a SHA-256 repository — 64-hex OIDs and a 64-zero
  /// null-object — through the exact isolated env every other op uses. Null
  /// (the default) leaves git's default format (SHA-1) untouched, so existing
  /// callers are byte-for-byte unaffected.
  static Future<ScratchRepo> create(
      {String? name, bool autocrlf = false, String? objectFormat}) async {
    final prefix = 'scratch_repo_${name == null ? '' : '${name}_'}';
    // The worktree lives one level DOWN, inside its own private sandbox,
    // rather than directly in the shared system temp dir. Two reasons, both
    // load-bearing:
    //  - a test asserting "a hostile ref name never created anything outside
    //    the repo" lists `dir.parent`. When that was the system temp dir the
    //    assertion was simultaneously RACY (any concurrently-running test's
    //    temp dir tripped it — `flutter test` runs files in parallel) and
    //    WEAK (it only saw escapes landing in exactly that one directory);
    //  - `dispose()` can then remove the whole sandbox, so anything a git op
    //    created as a sibling of the worktree is cleaned up too.
    final sandbox = await Directory.systemTemp.createTemp(prefix);
    final dir = Directory(p.join(sandbox.path, 'repo'));
    await dir.create();
    final repo = ScratchRepo._(dir, sandbox);
    await repo._initialize(autocrlf: autocrlf, objectFormat: objectFormat);
    return repo;
  }

  Future<void> _initialize(
      {required bool autocrlf, String? objectFormat}) async {
    final initResult = await git([
      'init',
      '-q',
      '-b',
      'main',
      if (objectFormat != null) '--object-format=$objectFormat',
    ]);
    if (initResult.exitCode != 0) {
      throw StateError('git init failed: ${initResult.stderr}');
    }
    // Was 4 `git config` subprocess spawns (one per key). `git init` always
    // writes `.git/config` as plain INI text ending in `\n` (verified against
    // the installed git — see the comment on `_writeIdentityConfig`), so the
    // same four settings can be appended with one file read + one file write
    // instead: identical end state (`git config --get <key>` returns the same
    // value either way — proved by the "identity config matches four
    // `git config` calls" group in `test/backend/repo_topology_test.dart`),
    // zero extra processes.
    await _writeIdentityConfig(autocrlf: autocrlf);
    // HEAD exists from the start — every downstream helper (`head()`,
    // `currentBranch()`, merges, the fuzzer, ...) starts from a real commit
    // rather than the unborn-branch edge case.
    await gitOk(['commit', '--allow-empty', '-m', 'root']);
  }

  /// Appends `user.name`/`user.email`/`commit.gpgsign`/`core.autocrlf` as new
  /// INI sections directly onto `.git/config`, replacing four `git config`
  /// subprocess calls with one file read + one file write.
  ///
  /// Safe because git's config parser accepts a section header appearing
  /// more than once in a file (every `[core]` block's keys are merged), and
  /// because `git config --get <key>` — the only way any caller ever reads
  /// these back — returns the *last* occurrence of a single-valued key in
  /// file order. Appending at the end therefore always wins, identically to
  /// what four separate `git config <key> <value>` calls would have produced
  /// (each of which also always rewrites-or-appends, never a first-wins
  /// merge). `git init -b main` is confirmed (empirically, on the git build
  /// this harness runs against) to already emit a trailing `[core]` block
  /// ending in `\n`, so a straight append never collides mid-line.
  Future<void> _writeIdentityConfig({required bool autocrlf}) async {
    final configFile = File(p.join(dir.path, '.git', 'config'));
    final existing = await configFile.readAsString();
    final buffer = StringBuffer(existing);
    if (!existing.endsWith('\n')) buffer.write('\n');
    buffer
      ..writeln('[user]')
      ..writeln('\tname = Scratch Repo')
      ..writeln('\temail = scratch@example.invalid')
      ..writeln('[commit]')
      ..writeln('\tgpgsign = false')
      ..writeln('[core]')
      ..writeln('\tautocrlf = ${autocrlf ? 'true' : 'false'}');
    await configFile.writeAsString(buffer.toString(), flush: true);
  }

  /// Runs `git [args]` in this repo's working tree through the app's own
  /// [runGit] — the exact non-interactive, semaphored, retrying subprocess
  /// path production code uses — overlaid with [_isolationEnv]. Never
  /// throws on a nonzero exit; callers decide what failure means.
  Future<ProcessResult> git(List<String> args) {
    return runGit(dir.path, args, extraEnv: _isolationEnv);
  }

  /// Convenience: run [args], throw (with stderr in the message) on a
  /// nonzero exit, else return trimmed stdout.
  Future<String> gitOk(List<String> args) async {
    final r = await git(args);
    if (r.exitCode != 0) {
      throw StateError(
          'git ${args.join(' ')} failed (exit ${r.exitCode}): ${r.stderr}');
    }
    return r.stdout.toString().trim();
  }

  String _absolutePath(String relPath) =>
      p.joinAll([dir.path, ...relPath.split('/')]);

  /// Writes [content] to [relPath] (creating parent directories as needed),
  /// preserving the exact bytes given — CRLF and unicode in [content] are
  /// never mangled by an implicit platform-default encoding.
  Future<void> writeFile(String relPath, String content) async {
    final file = File(_absolutePath(relPath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(utf8.encode(content), flush: true);
  }

  Future<void> deleteFile(String relPath) async {
    final file = File(_absolutePath(relPath));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> stage(List<String> paths) =>
      gitOk(['add', '--', ...paths]);

  Future<String> stageAll() => gitOk(['add', '-A']);

  Future<String> commitAll(String message) async {
    await stageAll();
    await gitOk(['commit', '-m', message]);
    return gitOk(['rev-parse', 'HEAD']);
  }

  /// Resolves `HEAD`; returns null if unborn (no commits yet).
  Future<String?> head() async {
    final r = await git(['rev-parse', '--verify', 'HEAD']);
    if (r.exitCode != 0) return null;
    final sha = r.stdout.toString().trim();
    return sha.isEmpty ? null : sha;
  }

  Future<String> currentBranch() =>
      gitOk(['rev-parse', '--abbrev-ref', 'HEAD']);

  /// `git for-each-ref --format=%(refname)` as a list — used to assert e.g.
  /// that a namespace never collides with real refs.
  Future<List<String>> allRefs() async {
    final out = await gitOk(['for-each-ref', '--format=%(refname)']);
    if (out.isEmpty) return const [];
    return out.split('\n').where((l) => l.isNotEmpty).toList();
  }

  /// True when `git status --porcelain` is empty.
  Future<bool> isClean() async {
    final r = await git(['status', '--porcelain']);
    return r.exitCode == 0 && r.stdout.toString().trim().isEmpty;
  }

  /// Recursively deletes the temp dir. Best-effort — Windows can briefly
  /// hold a file handle after a spawned git process exits, racing this
  /// delete; swallow that rather than fail teardown.
  Future<void> dispose() async {
    try {
      await _sandbox.delete(recursive: true);
    } catch (_) {
      // Ignored — see docstring.
    }
  }
}

// ---------------------------------------------------------------------------
// Fuzzer op model
// ---------------------------------------------------------------------------

/// One primitive git-repo mutation the fuzzer can apply. Each variant is a
/// small immutable value; [toString] renders a reproducible one-line repro
/// step.
sealed class RepoOp {
  const RepoOp();
}

class WriteFileOp extends RepoOp {
  final String path;
  final String content;
  const WriteFileOp(this.path, this.content);
  @override
  String toString() =>
      'WriteFileOp(${_reprString(path)}, ${_reprString(content)})';
}

class DeleteFileOp extends RepoOp {
  final String path;
  const DeleteFileOp(this.path);
  @override
  String toString() => 'DeleteFileOp(${_reprString(path)})';
}

class StageAllOp extends RepoOp {
  const StageAllOp();
  @override
  String toString() => 'StageAllOp()';
}

class CommitOp extends RepoOp {
  final String message;
  const CommitOp(this.message);
  @override
  String toString() => 'CommitOp(${_reprString(message)})';
}

class CreateBranchOp extends RepoOp {
  final String name;
  const CreateBranchOp(this.name);
  @override
  String toString() => 'CreateBranchOp(${_reprString(name)})';
}

class CheckoutOp extends RepoOp {
  final String ref;
  const CheckoutOp(this.ref);
  @override
  String toString() => 'CheckoutOp(${_reprString(ref)})';
}

class MergeOp extends RepoOp {
  final String ref;
  const MergeOp(this.ref);
  @override
  String toString() => 'MergeOp(${_reprString(ref)})';
}

class StashPushOp extends RepoOp {
  const StashPushOp();
  @override
  String toString() => 'StashPushOp()';
}

class StashPopOp extends RepoOp {
  const StashPopOp();
  @override
  String toString() => 'StashPopOp()';
}

String _reprString(String s) {
  final escaped = s
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll("'", r"\'");
  return "'$escaped'";
}

/// Outcome of [applyOp]. Individual-op failure (a merge conflict, a checkout
/// of a nonexistent ref, "nothing to commit", ...) is expected and recorded
/// here, never thrown — the fuzzer's safety invariants must hold across the
/// whole sequence regardless of any one op's success.
class RepoOpResult {
  final RepoOp op;
  final bool ok;
  final String? stderr;
  const RepoOpResult({required this.op, required this.ok, this.stderr});
  @override
  String toString() => 'RepoOpResult(op: $op, ok: $ok'
      '${stderr == null || stderr!.isEmpty ? '' : ', stderr: $stderr'})';
}

String? _stderrOf(ProcessResult r) =>
    r.exitCode == 0 ? null : r.stderr.toString().trim();

/// Applies [op] to [repo]. Never throws: any failure — git exiting nonzero,
/// or (for the filesystem ops) an IO exception — is captured into the
/// returned [RepoOpResult] instead of propagating.
Future<RepoOpResult> applyOp(ScratchRepo repo, RepoOp op) async {
  try {
    switch (op) {
      case WriteFileOp(:final path, :final content):
        await repo.writeFile(path, content);
        return RepoOpResult(op: op, ok: true);

      case DeleteFileOp(:final path):
        await repo.deleteFile(path);
        return RepoOpResult(op: op, ok: true);

      case StageAllOp():
        final r = await repo.git(['add', '-A']);
        return RepoOpResult(op: op, ok: r.exitCode == 0, stderr: _stderrOf(r));

      case CommitOp(:final message):
        final r = await repo.git(['commit', '-m', message]);
        return RepoOpResult(op: op, ok: r.exitCode == 0, stderr: _stderrOf(r));

      case CreateBranchOp(:final name):
        final r = await repo.git(['branch', name]);
        return RepoOpResult(op: op, ok: r.exitCode == 0, stderr: _stderrOf(r));

      case CheckoutOp(:final ref):
        final r = await repo.git(['checkout', ref]);
        return RepoOpResult(op: op, ok: r.exitCode == 0, stderr: _stderrOf(r));

      case MergeOp(:final ref):
        final r = await repo.git(['merge', '--no-edit', ref]);
        return RepoOpResult(op: op, ok: r.exitCode == 0, stderr: _stderrOf(r));

      case StashPushOp():
        final r =
            await repo.git(['stash', 'push', '-u', '-m', 'fuzz-stash']);
        return RepoOpResult(op: op, ok: r.exitCode == 0, stderr: _stderrOf(r));

      case StashPopOp():
        final r = await repo.git(['stash', 'pop']);
        return RepoOpResult(op: op, ok: r.exitCode == 0, stderr: _stderrOf(r));
    }
  } catch (error) {
    return RepoOpResult(op: op, ok: false, stderr: error.toString());
  }
}

// ---------------------------------------------------------------------------
// Deterministic generator
// ---------------------------------------------------------------------------

/// Minimal, dependency-free splitmix64-derived PRNG. Deterministic across
/// runs for a given seed — deliberately not `dart:math`'s `Random` (whose
/// seeded sequence is not a documented cross-version stability guarantee)
/// and deliberately standalone (no import of test/support/prop.dart, so this
/// file has no ordering dependency on whatever other harness owns that seed
/// policy).
class _SplitMix64 {
  int _state;
  _SplitMix64(int seed) : _state = seed;

  int _nextRaw() {
    _state += 0x9E3779B97F4A7C15;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// Uniform-ish integer in `[0, max)`. `max` must be > 0. Dart's `%` on
  /// `int` is Euclidean (result takes the sign of, and is smaller in
  /// magnitude than, a positive divisor), so this is safe even though
  /// `_nextRaw()` can be a negative 64-bit value.
  int nextInt(int max) => _nextRaw() % max;
}

const List<String> _kFuzzPaths = [
  'a.txt',
  'b.txt',
  'dir/c.txt',
  'dir/nested/d.md',
  'e.txt',
];

const List<String> _kFuzzBogusRefs = [
  'does-not-exist',
  'ghost-branch',
  'refs/heads/nowhere',
];

const List<String> _kFuzzMessages = [
  'wip',
  'fix stuff',
  'progress',
  'checkpoint',
  'more work',
];

// Deliberately includes a CRLF sample and a unicode sample so fuzzed commits
// exercise both.
const List<String> _kFuzzContentSamples = [
  'hello world\n',
  'line one\r\nline two\r\n',
  'unicode: café ☃ 日本語\n',
  'a\nb\nc\n',
];

String _pickRef(_SplitMix64 rng, List<String> known) {
  // 70% reference something this sequence actually created (a legitimate
  // checkout/merge target), 30% a name nothing created (exercises the
  // "ref doesn't exist" failure path).
  final useReal = rng.nextInt(10) < 7;
  if (useReal) return known[rng.nextInt(known.length)];
  return _kFuzzBogusRefs[rng.nextInt(_kFuzzBogusRefs.length)];
}

/// Deterministic pseudo-random sequence of [RepoOp]s for a given [seed] —
/// the same seed always yields the same sequence, so a fuzz failure is
/// reproducible by regenerating with that seed.
///
/// Biased toward sequences that actually build history (mostly
/// write-file/stage/commit, with occasional branch/checkout/merge/stash).
/// File paths are drawn from a small fixed pool so edits collide across
/// branches (real merge scenarios, not just parallel no-op history).
List<RepoOp> genRepoOpSequence(int seed, {int maxOps = 30}) {
  final rng = _SplitMix64(seed);
  final knownBranches = <String>['main'];
  final ops = <RepoOp>[];

  for (var i = 0; i < maxOps; i++) {
    final roll = rng.nextInt(100);
    if (roll < 45) {
      final path = _kFuzzPaths[rng.nextInt(_kFuzzPaths.length)];
      final base =
          _kFuzzContentSamples[rng.nextInt(_kFuzzContentSamples.length)];
      // Vary content per-op so repeated writes to the same path are real
      // edits, not no-op rewrites.
      final content = '$base// rev ${rng.nextInt(1 << 20)}\n';
      ops.add(WriteFileOp(path, content));
    } else if (roll < 55) {
      ops.add(DeleteFileOp(_kFuzzPaths[rng.nextInt(_kFuzzPaths.length)]));
    } else if (roll < 75) {
      ops.add(const StageAllOp());
    } else if (roll < 90) {
      final message = _kFuzzMessages[rng.nextInt(_kFuzzMessages.length)];
      ops.add(CommitOp('$message (#$i)'));
    } else if (roll < 93) {
      final name = 'branch-${knownBranches.length}-${rng.nextInt(1000)}';
      knownBranches.add(name);
      ops.add(CreateBranchOp(name));
    } else if (roll < 96) {
      ops.add(CheckoutOp(_pickRef(rng, knownBranches)));
    } else if (roll < 98) {
      ops.add(MergeOp(_pickRef(rng, knownBranches)));
    } else if (roll < 99) {
      ops.add(const StashPushOp());
    } else {
      ops.add(const StashPopOp());
    }
  }
  return ops;
}
