// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Hostile-gitconfig differential harness support.
//
// Production NEVER neutralizes the user's git config: no `GIT_CONFIG_*` env,
// no `-c` overrides, no format-pinning beyond what each call already passes.
// A user's `~/.gitconfig` or a repo's `.git/config` can therefore silently
// reshape `git` stdout and break the app's line-oriented parsers. This module
// provides the machinery to prove output-invariance under hostile config — or
// to pin each divergence as a genuine finding.
//
// ─────────────────────────────────────────────────────────────────────────
// WHY ONE REPO, CONFIG-SWAPPED, RATHER THAN TWO SEPARATE REPOS
// ─────────────────────────────────────────────────────────────────────────
// Two independently-created scratch repos commit at different wall-clock
// times, so their commit/blob SHAs differ — which would make every
// hash-bearing surface (history, blame, coupling) diverge with NO hostile
// config at all, a false positive. The differential instead builds ONE seeded
// repo and swaps `.git/config` between the baseline and hostile arms. Same
// repo ⇒ identical content and SHAs ⇒ the ONLY variable between arms is the
// config under test.
//
// ─────────────────────────────────────────────────────────────────────────
// WHY THE ARMS ARE DETERMINISTIC EVEN THOUGH PRODUCTION READS ~/.gitconfig
// ─────────────────────────────────────────────────────────────────────────
// The functions under test are called directly (e.g. `getRepositoryStatus`),
// so they run through `runGit` with only `_kNonInteractiveGitEnv` — they do
// NOT get ScratchRepo's `GIT_CONFIG_GLOBAL` isolation, meaning the developer's
// real global config IS consulted. Two properties defeat that:
//   1. Repo-local `.git/config` beats global config for any key, so every arm
//      PINS every axis key explicitly (see [cleanBaselineConfig]) — global
//      values can never leak into a pinned key.
//   2. Baseline and hostile arms are byte-identical except the one axis's
//      key(s), so any UN-pinned global setting is common-mode and cancels in
//      the differential.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'scratch_repo.dart';

// ---------------------------------------------------------------------------
// Hostile filenames (codepoint-built — never a raw non-ASCII source literal)
// ---------------------------------------------------------------------------

/// `café.txt` — a non-ASCII filename whose UTF-8 encoding (`caf` + 0xC3 0xA9
/// + `.txt`) is what `core.quotePath` C-quotes to `"caf\303\251.txt"`. Built
/// from codepoints so the source file stays pure-ASCII.
final String nonAsciiFileName =
    String.fromCharCodes(const [0x63, 0x61, 0x66, 0xE9, 0x2E, 0x74, 0x78, 0x74]);

/// A filename containing an internal space. Git NEVER C-quotes a path merely
/// for a space, so it reaches the diff-header parser unquoted — the exact
/// shape `diff.noprefix` mis-splits.
const String spaceFileName = 'has space.txt';

// ---------------------------------------------------------------------------
// Config axes
// ---------------------------------------------------------------------------

/// The git-default / "clean-direction" value for EVERY axis key. Both arms of
/// the differential write this whole block first; the hostile arm then
/// overlays exactly one axis's key(s) on top. Writing all keys in both arms is
/// what makes a divergence attributable to the single overlaid axis and immune
/// to whatever the host machine's global config happens to hold.
///
/// Note `core.quotePath`'s git DEFAULT is `true` (the hostile direction); the
/// baseline deliberately pins it `false` so the differential contrasts clean
/// vs. quoted output rather than quoted vs. quoted.
const Map<String, String> cleanBaselineConfig = {
  'core.quotePath': 'false',
  'diff.noprefix': 'false',
  'diff.mnemonicPrefix': 'false',
  'color.ui': 'never',
  'color.diff': 'never',
  'diff.renames': 'false',
  'core.abbrev': '40',
  'feature.manyFiles': 'false',
};

/// One hostile-config axis: a name plus the overlay it adds on top of
/// [cleanBaselineConfig] for the hostile arm.
class ConfigAxis {
  final String name;
  final Map<String, String> settings;
  const ConfigAxis(this.name, this.settings);
}

/// The seven axes exercised by the suite. `abbrev` and `manyFiles` are
/// expected-harmless controls; the rest are the suspected reshapers.
const List<ConfigAxis> hostileConfigAxes = [
  ConfigAxis('quotePath', {'core.quotePath': 'true'}),
  ConfigAxis('noprefix', {'diff.noprefix': 'true'}),
  ConfigAxis('mnemonicPrefix', {'diff.mnemonicPrefix': 'true'}),
  ConfigAxis('colorAlways', {'color.ui': 'always', 'color.diff': 'always'}),
  ConfigAxis('renames', {'diff.renames': 'true'}),
  ConfigAxis('abbrev', {'core.abbrev': '4'}),
  ConfigAxis('manyFiles', {'feature.manyFiles': 'true'}),
];

/// The baseline arm: every axis key at its clean default.
Map<String, String> baselineArm() => Map<String, String>.of(cleanBaselineConfig);

/// The hostile arm for [axis]: clean baseline with the axis overlay applied.
Map<String, String> hostileArm(ConfigAxis axis) =>
    <String, String>{...cleanBaselineConfig, ...axis.settings};

/// Git's OWN default value for every axis key — the config a user with no
/// `~/.gitconfig` and no `.git/config` overrides gets. It differs from
/// [cleanBaselineConfig] on exactly the two axes whose default is the hostile
/// direction: `core.quotePath` (git default `true`) and `diff.renames` (git
/// default `true`). Used by the absolute ground-truth anchors as a SECOND
/// witness: under git's real defaults a non-ASCII path C-quotes and a stashed
/// rename collapses to a `{old => new}` arrow, reproducing the same findings
/// the differential pins — but as absolute parsed-content failures, not just
/// arm-vs-arm divergence.
///
/// Why this PINS the defaults explicitly rather than simply omitting the keys:
/// the production surface functions run through `runGit` WITHOUT ScratchRepo's
/// `GIT_CONFIG_GLOBAL` isolation (see this file's header), so a key left
/// unwritten would resolve against the developer's real global gitconfig — a
/// flaky, machine-dependent anchor. Writing git's documented defaults into the
/// repo-local `.git/config` makes the anchor deterministic on every machine
/// while still exercising git's default behaviour. `color.ui`/`color.diff` are
/// pinned `never` rather than git's default `auto` because `auto` already means
/// "no color" whenever stdout is a pipe (as it is under test) — the two are
/// behaviourally identical here, and `never` is leak-proof.
const Map<String, String> gitDefaultConfig = {
  'core.quotePath': 'true', // git default (the hostile direction)
  'diff.noprefix': 'false', // git default
  'diff.mnemonicPrefix': 'false', // git default
  'color.ui': 'never', // ≡ git default `auto` under a non-tty pipe
  'color.diff': 'never',
  'diff.renames': 'true', // git default (the hostile direction)
  'core.abbrev': '40',
  'feature.manyFiles': 'false',
};

/// The git-default arm: every axis key pinned to git's own default value.
Map<String, String> gitDefaultArm() => Map<String, String>.of(gitDefaultConfig);

// ---------------------------------------------------------------------------
// Config file IO — direct `.git/config` append, mirroring
// ScratchRepo._writeIdentityConfig (git merges repeated section headers and
// the last single-valued key in file order wins).
// ---------------------------------------------------------------------------

File _configFile(ScratchRepo repo) =>
    File(p.join(repo.dir.path, '.git', 'config'));

/// Reads the repo's raw `.git/config` text.
Future<String> readRepoConfig(ScratchRepo repo) =>
    _configFile(repo).readAsString();

/// Overwrites the repo's raw `.git/config` text.
Future<void> writeRepoConfig(ScratchRepo repo, String content) =>
    _configFile(repo).writeAsString(content, flush: true);

/// Renders [settings] (`section.key` → value) as an INI block, grouped by
/// section: `core.quotePath` → `[core]\n\tquotePath = ...`. Keys are split on
/// their FIRST `.` (git config is `section.key` or `section.sub.key`).
String renderConfigIni(Map<String, String> settings) {
  final bySection = <String, List<MapEntry<String, String>>>{};
  for (final entry in settings.entries) {
    final dot = entry.key.indexOf('.');
    final section = dot < 0 ? entry.key : entry.key.substring(0, dot);
    final key = dot < 0 ? entry.key : entry.key.substring(dot + 1);
    bySection.putIfAbsent(section, () => []).add(MapEntry(key, entry.value));
  }
  final buf = StringBuffer();
  bySection.forEach((section, kvs) {
    buf.writeln('[$section]');
    for (final kv in kvs) {
      buf.writeln('\t${kv.key} = ${kv.value}');
    }
  });
  return buf.toString();
}

/// Appends [settings] as a new INI block onto the repo's `.git/config`.
Future<void> applyRepoConfig(
    ScratchRepo repo, Map<String, String> settings) async {
  final existing = await readRepoConfig(repo);
  final buf = StringBuffer(existing);
  if (!existing.endsWith('\n')) buf.write('\n');
  buf.write(renderConfigIni(settings));
  await writeRepoConfig(repo, buf.toString());
}

/// Holds a seeded repo plus a snapshot of its post-seed `.git/config`, so an
/// axis arm can be applied and cleanly stripped between differential runs.
class HostileConfigFixture {
  final ScratchRepo repo;
  final String _baseConfig;
  HostileConfigFixture._(this.repo, this._baseConfig);

  static Future<HostileConfigFixture> create(ScratchRepo repo) async =>
      HostileConfigFixture._(repo, await readRepoConfig(repo));

  /// Restores the post-seed config, then overlays [settings]. Same repo,
  /// same content — only the config changes between calls.
  Future<void> applyArm(Map<String, String> settings) async {
    await writeRepoConfig(repo, _baseConfig);
    await applyRepoConfig(repo, settings);
  }

  /// Restores the post-seed config with no axis overlay (used before argv
  /// recording, where config is irrelevant but a known state is tidy).
  Future<void> restoreBase() => writeRepoConfig(repo, _baseConfig);
}

// ---------------------------------------------------------------------------
// Seeding
// ---------------------------------------------------------------------------

/// Seeds [repo] with content covering every hostile-config surface at once:
///   • a non-ASCII filename ([nonAsciiFileName]) in committed history, so
///     `core.quotePath` has something to C-quote in status/diff/log/coupling;
///   • a space-containing filename ([spaceFileName]) for the `diff.noprefix`
///     header mis-split;
///   • two commits that co-change the non-ASCII file and `a.txt`, so
///     `computeFileCoupling` produces at least one pair over the non-ASCII
///     file;
///   • a stash whose single entry is a RENAME + edit, for `stashFiles` under
///     `diff.renames`;
///   • an ASCII multi-line file (`blamefile.txt`) for `getFileBlame`;
///   • a persistent dirty working tree — the non-ASCII file modified
///     (unstaged), `a.txt` modified + staged, an untracked file — for
///     `getRepositoryStatus` and the unstaged/staged diff surfaces.
///
/// The stash is created BEFORE the persistent dirty state so `stash push`
/// (which reverts what it captures) can't disturb it.
Future<void> seedHostileRepo(ScratchRepo repo) async {
  // Commit 1 — introduce every tracked file.
  await repo.writeFile(nonAsciiFileName, 'x\ny\nz\n');
  await repo.writeFile('a.txt', '1\n2\n3\n');
  await repo.writeFile(spaceFileName, 'p\nq\nr\n');
  await repo.writeFile('blamefile.txt', 'alpha\nbeta\ngamma\n');
  await repo.writeFile('stashme.txt', 'one\ntwo\nthree\nfour\n');
  await repo.stageAll();
  await repo.gitOk(['commit', '-m', 'seed one']);

  // Commit 2 — co-change the non-ASCII file and a.txt (a coupling pair).
  await repo.writeFile(nonAsciiFileName, 'x\nY\nz\n');
  await repo.writeFile('a.txt', '1\nB\n3\n');
  await repo.stageAll();
  await repo.gitOk(['commit', '-m', 'seed two']);

  // A stash whose only entry is a staged rename + edit. `stash push` reverts
  // the rename afterward, leaving the working tree clean for the next step.
  await repo.gitOk(['mv', 'stashme.txt', 'stashme_renamed.txt']);
  await repo.writeFile('stashme_renamed.txt', 'one\ntwo\nthree\nFOUR\n');
  await repo.stageAll();
  await repo.gitOk(['stash', 'push', '-m', 'hostile-stash']);

  // Persistent dirty working tree for status + working-diff surfaces.
  await repo.writeFile(nonAsciiFileName, 'x\nY\nZZ\n'); // unstaged modify
  await repo.writeFile(spaceFileName, 'p\nQ\nr\n'); // unstaged modify
  await repo.writeFile('a.txt', '1\nB\nSTAGED\n');
  await repo.stage(['a.txt']); // staged modify
  await repo.writeFile('untracked.txt', 'new\n'); // untracked
}

// ---------------------------------------------------------------------------
// Projection comparison
// ---------------------------------------------------------------------------

/// Canonical JSON encoding of a projection (built only from Lists/Maps of
/// primitives). Two projections are equal iff their canonical encodings are.
/// Both arms build their projection through the same code path, so Map key
/// order (insertion order) matches and does not perturb the comparison.
String canonicalJson(Object? projection) => jsonEncode(projection);

// ---------------------------------------------------------------------------
// Technique C — synthetic hostile git stdout
// ---------------------------------------------------------------------------

/// One commit's worth of fields for [syntheticCommitLog]. The eight fields
/// correspond, in order, to `_kCommitLogFormat`
/// (`%H%n%h%n%P%n%D%n%s%n%aN%n%aE%n%aI`). Raw-byte overrides let a test inject
/// non-UTF-8 sequences into the author/subject fields (the shape a mismatched
/// `i18n.logOutputEncoding` produces).
class SyntheticCommit {
  final String hash;
  final String shortHash;
  final String parents;
  final String refs;
  final String subject;
  final String authorName;
  final String authorEmail;
  final String authoredAt;
  final List<int>? authorNameRawBytes;
  final List<int>? subjectRawBytes;
  const SyntheticCommit({
    required this.hash,
    required this.shortHash,
    this.parents = '',
    this.refs = '',
    this.subject = 'subject line',
    this.authorName = 'Author Name',
    this.authorEmail = 'author@example.invalid',
    this.authoredAt = '2026-01-01T00:00:00+00:00',
    this.authorNameRawBytes,
    this.subjectRawBytes,
  });
}

/// Byte-exact `git log --format=_kCommitLogFormat` stdout: eight lines per
/// commit, records back-to-back with a trailing newline and NO blank
/// separator (verified against git 2.52). With [signature] true, each commit
/// is prefixed with the `gpg:` verification lines `log.showSignature=true`
/// interleaves ahead of the format output.
List<int> syntheticCommitLog(
  List<SyntheticCommit> commits, {
  bool signature = false,
}) {
  final out = <int>[];
  void addBytes(List<int> bytes) {
    out.addAll(bytes);
    out.add(0x0A); // '\n'
  }

  void addStr(String s) => addBytes(utf8.encode(s));

  for (final c in commits) {
    if (signature) {
      addStr('gpg: Signature made Wed 01 Jan 2026 00:00:00 AM UTC');
      addStr('gpg:                using RSA key DEADBEEFCAFE0000');
      addStr('gpg: Good signature from '
          '"${c.authorName} <${c.authorEmail}>" [ultimate]');
    }
    addStr(c.hash);
    addStr(c.shortHash);
    addStr(c.parents);
    addStr(c.refs);
    if (c.subjectRawBytes != null) {
      addBytes(c.subjectRawBytes!);
    } else {
      addStr(c.subject);
    }
    if (c.authorNameRawBytes != null) {
      addBytes(c.authorNameRawBytes!);
    } else {
      addStr(c.authorName);
    }
    addStr(c.authorEmail);
    addStr(c.authoredAt);
  }
  return out;
}

/// A successful raw-bytes [ProcessResult] carrying [stdoutBytes]. Mirrors the
/// GitSpawn seam contract (`stdoutEncoding: null`) — stdout is raw bytes, not
/// a decoded String — so the real production decode path runs.
ProcessResult rawStdoutResult(List<int> stdoutBytes) =>
    ProcessResult(0, 0, stdoutBytes, const <int>[]);
