import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'repository_xray.dart';
import 'dtos.dart';
import 'git_result.dart';
import '../diagnostics/diagnostics_state.dart';

// Git emits two header forms:
//   unquoted: `diff --git a/path b/path`
//   quoted:   `diff --git "a/path with spaces" "b/path with spaces"` (C-string
//             quoted when the path contains spaces or non-ASCII).
// These helpers are the single source of truth so every caller handles both;
// previous duplicated regexes covered only the unquoted form and silently
// missed renamed-with-spaces paths.

final RegExp _kDiffHeaderUnquoted =
    RegExp(r'^diff --git a/.+ b/(.+)$', multiLine: true);
final RegExp _kDiffHeaderQuoted =
    RegExp(r'^diff --git "a/[^"]+" "b/([^"]+)"$', multiLine: true);
final RegExp _kDiffHeaderUnquotedLine = RegExp(r'^diff --git a/.+ b/(.+)$');
final RegExp _kDiffHeaderQuotedLine =
    RegExp(r'^diff --git "a/[^"]+" "b/([^"]+)"$');

/// Returns every touched (b-side) path across the full unified diff text,
/// handling both unquoted and C-string-quoted forms.
Set<String> extractDiffTouchedPaths(String diffText) {
  final paths = <String>{};
  for (final m in _kDiffHeaderUnquoted.allMatches(diffText)) {
    paths.add(m.group(1)!);
  }
  for (final m in _kDiffHeaderQuoted.allMatches(diffText)) {
    paths.add(m.group(1)!);
  }
  return paths;
}

/// Parses a single line as a git diff header. Returns the b-side path
/// if it matches either form, else null. Use inside a per-line scan
/// (e.g. to track `currentFile` while walking the diff).
String? diffHeaderPath(String line) {
  final u = _kDiffHeaderUnquotedLine.firstMatch(line);
  if (u != null) return u.group(1);
  final q = _kDiffHeaderQuotedLine.firstMatch(line);
  if (q != null) return q.group(1);
  return null;
}

/// Decode outcome: the decoded text, plus whether strict UTF-8 failed
/// (bytes contained invalid sequences) and the byte offset of the first
/// malformed sequence. The flag lets callers emit a lifecycle event so
/// a lossy fallback is never silent in telemetry.
class _GitDecodeOutcome {
  final String text;
  final bool lenientFallback;
  final int? malformedAtOffset;
  const _GitDecodeOutcome(
      this.text, this.lenientFallback, this.malformedAtOffset);
}

/// Commands whose stdout is known-ASCII structured data (SHAs, ref
/// names, boolean flags). Malformed UTF-8 here doesn't mean "binary
/// patch payload" — it means real ref/config corruption, which should
/// surface as a hard failure, not a silent U+FFFD substitution that
/// lets downstream code consume garbage as though it were valid.
///
/// Deliberately narrow: only subcommands where we're confident the
/// output is purely machine-structured. Anything that can embed commit
/// messages, file content, config values, paths (when `core.quotePath`
/// is off), or user-supplied strings stays in the lenient bucket, since
/// those legitimately carry non-UTF-8 bytes in real repos.
const Set<String> _kStrictDecodeSubcommands = {
  'rev-parse',
  'rev-list',
  'symbolic-ref',
  'merge-base',
  'check-ref-format',
};

/// Git accepts global options before the subcommand (e.g. `git -C <dir>
/// rev-parse HEAD`, `git --git-dir=<path> rev-list`, `git -c foo=bar
/// status`). A naive `args.first` check would classify such a call as
/// lenient even though the real subcommand is strict-eligible. Walk
/// past every leading global option to find the subcommand token.
///
/// Global options per `man git(1)` that take values as a separate
/// argument: `-C`, `-c`, `--exec-path=` (only when given without `=`),
/// `--git-dir`, `--work-tree`, `--namespace`, `--super-prefix`,
/// `--config-env`. Attached-value forms (`--foo=bar`, `-C<path>`) are
/// a single token and are skipped by the prefix check.
String? _gitSubcommandToken(List<String> args) {
  var i = 0;
  while (i < args.length) {
    final a = args[i];
    if (!a.startsWith('-')) return a; // positional → this is the subcommand
    // Boolean-only global flags: consume one slot.
    const boolFlags = {
      '-p', '-P', '--paginate', '--no-pager',
      '--bare', '--no-replace-objects',
      '--literal-pathspecs', '--glob-pathspecs',
      '--noglob-pathspecs', '--icase-pathspecs',
      '-h', '--help', '--version',
    };
    if (boolFlags.contains(a)) {
      i++;
      continue;
    }
    // Value-taking flags when split across two args: `-C <dir>` style.
    const splitFlags = {
      '-C', '-c', '--exec-path', '--git-dir', '--work-tree',
      '--namespace', '--super-prefix', '--config-env',
    };
    if (splitFlags.contains(a)) {
      i += 2;
      continue;
    }
    // Attached-value form (`-C<dir>`, `--git-dir=<path>`, `-cfoo=bar`)
    // — single token, just advance past it.
    i++;
  }
  return null;
}

/// Decodes git stdout/stderr bytes as UTF-8. Behavior depends on
/// [strict]:
///   • strict=true  — throw `FormatException` on any malformed byte.
///     Used for structural commands where U+FFFD substitution would
///     silently corrupt a parser that expects exact bytes.
///   • strict=false — attempt strict first, fall back to lenient
///     decode on FormatException. Used for content-bearing commands
///     (diff, show, log, grep, cat-file, ls-files when paths may be
///     raw) where non-UTF-8 bytes are legitimate and blocking on them
///     would kill the flow.
_GitDecodeOutcome _decodeGitBytes(Object? raw, {required bool strict}) {
  if (raw is! List<int>) {
    return _GitDecodeOutcome(raw?.toString() ?? '', false, null);
  }
  if (strict) {
    // Propagate FormatException to caller; no fallback. The outer
    // catch turns this into a `git.invoke_failed` lifecycle event
    // with the malformed-byte offset preserved in the message.
    return _GitDecodeOutcome(utf8.decode(raw), false, null);
  }
  try {
    return _GitDecodeOutcome(utf8.decode(raw), false, null);
  } on FormatException catch (e) {
    return _GitDecodeOutcome(
        utf8.decode(raw, allowMalformed: true), true, e.offset);
  }
}

Future<ProcessResult> _git(String workingDir, List<String> args) async {
  final commandLabel = args.isEmpty ? 'git' : 'git.${args.first}';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: commandLabel,
  );
  try {
    // Raw bytes, then strict-first / lenient-fallback decode. Strict
    // utf8 would throw on the first malformed byte — and git diffs
    // routinely emit non-UTF-8 (binary file contents in patch hunks,
    // legacy-encoded source, the occasional latin-1 working tree) —
    // so a strict-only pipeline kills flows silently through async
    // onTap callbacks. But defaulting to lenient loses information we
    // actually care about elsewhere (paths come back C-quoted as
    // ASCII, and any non-ASCII in git's own output is a bug worth
    // hearing about loudly). Resolution: try strict, fall back to
    // allowMalformed only for the streams that actually need it. 99 %
    // of calls keep strict guarantees; the 1 % that would have thrown
    // now survives with U+FFFD in the unrecoverable bytes.
    final raw = await Process.run(
      'git',
      args,
      workingDirectory: workingDir,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    // Classify by subcommand. stderr is always lenient — it carries
    // human messages that may be localized to a non-UTF-8 locale on
    // exotic setups, and a lenient parse is fine for surfacing the
    // text to a user. Use `_gitSubcommandToken` so global options
    // before the subcommand (`-C`, `--git-dir`, etc.) don't silently
    // downgrade a strict-eligible command to lenient mode.
    final subcommand = _gitSubcommandToken(args);
    final strictStdout = subcommand != null &&
        _kStrictDecodeSubcommands.contains(subcommand);
    final stdoutOut = _decodeGitBytes(raw.stdout, strict: strictStdout);
    final stderrOut = _decodeGitBytes(raw.stderr, strict: false);
    // Surface any lenient-decode fallback as a diagnostic lifecycle
    // event. Without this, malformed-byte replacement (U+FFFD) is
    // invisible to ops — downstream parsers would silently consume
    // corrupted text. The event is type=warning rather than failure
    // so it doesn't poison success metrics; the errorCode + message
    // are grep-able for encoding audits.
    if (stdoutOut.lenientFallback || stderrOut.lenientFallback) {
      final streams = [
        if (stdoutOut.lenientFallback)
          'stdout@${stdoutOut.malformedAtOffset}',
        if (stderrOut.lenientFallback)
          'stderr@${stderrOut.malformedAtOffset}',
      ].join(',');
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'warning',
        command: commandLabel,
        errorCode: 'git.malformed_utf8',
        message: 'lenient UTF-8 fallback: $streams',
      );
    }
    final result = ProcessResult(
        raw.pid, raw.exitCode, stdoutOut.text, stderrOut.text);
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
    final ok = result.exitCode == 0;
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: ok ? 'success' : 'failure',
      command: commandLabel,
      durationMs: elapsedMs,
      errorCode: ok ? null : 'git.exit_${result.exitCode}',
      message: ok ? null : result.stderr.toString().trim(),
    );
    unawaited(
      DiagnosticsState.instance.recordCommandLatency(
        command: commandLabel,
        ok: ok,
        scope: 'git',
        roundTripMs: elapsedMs,
        backendDurationMs: elapsedMs,
        errorCode: ok ? null : 'git.exit_${result.exitCode}',
      ),
    );
    return result;
  } catch (error) {
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'failure',
      command: commandLabel,
      durationMs: elapsedMs,
      errorCode: 'git.invoke_failed',
      message: error.toString(),
    );
    unawaited(
      DiagnosticsState.instance.recordCommandLatency(
        command: commandLabel,
        ok: false,
        scope: 'git',
        roundTripMs: elapsedMs,
        backendDurationMs: elapsedMs,
        errorCode: 'git.invoke_failed',
      ),
    );
    rethrow;
  }
}

Future<ProcessResult> runGitProbe(String workingDir, List<String> args) {
  return _git(workingDir, args);
}

Future<GitResult<String>> openRepository(String path) async {
  try {
    final r = await _git(path, ['rev-parse', '--git-dir']);
    if (r.exitCode != 0) return GitResult.err('Not a git repository');
    return GitResult.ok(path);
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

Future<GitResult<List<String>>> listRecentRepositories() async {
  // Stored in shared_preferences — handled at app layer
  return GitResult.ok([]);
}

Future<GitResult<RepositoryStatus>> getRepositoryStatus(String repo) async {
  // Single `status --porcelain=v2 --branch` replaces the previous 4
  // serial calls (rev-parse HEAD, status v1, rev-parse @{u}, rev-list
  // --left-right --count). Porcelain v2 emits the branch name,
  // upstream name, and ahead/behind counts as header lines alongside
  // the file status entries — saves 3 subprocess spawns (~150-450ms)
  // on every refresh.
  //
  // Header format (one per line, leading `#`):
  //   # branch.oid <hash>             — HEAD sha or `(initial)`
  //   # branch.head <branch>          — branch name or `(detached)`
  //   # branch.upstream <upstream>    — only if upstream configured
  //   # branch.ab +<ahead> -<behind>  — only if upstream configured
  //
  // File entry format (leading digit / char):
  //   1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>       — tracked
  //   2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>\t<orig>
  //   u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
  //   ? <path>                                           — untracked
  //   ! <path>                                           — ignored
  try {
    final status =
        await _git(repo, ['status', '--porcelain=v2', '--branch', '-u']);
    if (status.exitCode != 0) {
      return GitResult.err(status.stderr.toString().trim());
    }

    String branchName = '';
    String? upstreamName;
    int ahead = 0;
    int behind = 0;
    final files = <RepositoryStatusFile>[];

    for (final rawLine in status.stdout.toString().split('\n')) {
      if (rawLine.isEmpty) continue;
      final first = rawLine.codeUnitAt(0);
      if (first == 0x23) {
        // '#' — header line. Match by key prefix.
        if (rawLine.startsWith('# branch.head ')) {
          final v = rawLine.substring(14).trim();
          if (v != '(detached)') branchName = v;
        } else if (rawLine.startsWith('# branch.upstream ')) {
          upstreamName = rawLine.substring(18).trim();
        } else if (rawLine.startsWith('# branch.ab ')) {
          // Format: `+<ahead> -<behind>`
          final parts = rawLine.substring(12).trim().split(' ');
          if (parts.length == 2) {
            ahead = int.tryParse(parts[0].replaceFirst('+', '')) ?? 0;
            behind = int.tryParse(parts[1].replaceFirst('-', '')) ?? 0;
          }
        }
        continue;
      }
      if (first == 0x31 /* '1' */ || first == 0x32 /* '2' */) {
        // Tracked / renamed: `<type> <XY> <sub> <mH> <mI> <mW> <hH> <hI> [<rename>] <path>`
        // The XY field is at a known position (chars 2-3). For `2`
        // entries there's an additional `<X><score>` field before the
        // path, and the path itself is followed by `\t<origPath>`.
        // We only need the XY and the final path.
        if (rawLine.length < 4) continue;
        final staged = rawLine[2];
        final unstaged = rawLine[3];
        // Path is whatever follows the 8th (tracked) or 9th (rename)
        // space-separated field. Splitting once per space is simpler
        // than counting fields — skip through the fixed-width metadata.
        final pathStart = first == 0x31
            ? _nthSpace(rawLine, 8) + 1
            : _nthSpace(rawLine, 9) + 1;
        if (pathStart <= 0 || pathStart >= rawLine.length) continue;
        var path = rawLine.substring(pathStart);
        // Rename records append `\t<origPath>` — we only want the new
        // path for RepositoryStatusFile.
        final tab = path.indexOf('\t');
        if (tab >= 0) path = path.substring(0, tab);
        if (path.isEmpty) continue;
        files.add(RepositoryStatusFile(
          path: path,
          staged: canonicalGitStatusCode(staged, stagedSlot: true),
          unstaged: canonicalGitStatusCode(unstaged, stagedSlot: false),
        ));
        continue;
      }
      if (first == 0x75 /* 'u' */) {
        // Unmerged: path starts after the 10th field.
        if (rawLine.length < 4) continue;
        final staged = rawLine[2];
        final unstaged = rawLine[3];
        final pathStart = _nthSpace(rawLine, 10) + 1;
        if (pathStart <= 0 || pathStart >= rawLine.length) continue;
        final path = rawLine.substring(pathStart);
        if (path.isEmpty) continue;
        files.add(RepositoryStatusFile(
          path: path,
          staged: canonicalGitStatusCode(staged, stagedSlot: true),
          unstaged: canonicalGitStatusCode(unstaged, stagedSlot: false),
        ));
        continue;
      }
      if (first == 0x3f /* '?' */ || first == 0x21 /* '!' */) {
        // Untracked / ignored: `? <path>` or `! <path>`.
        final path = rawLine.substring(2);
        if (path.isEmpty) continue;
        files.add(RepositoryStatusFile(
          path: path,
          staged: canonicalGitStatusCode('', stagedSlot: true),
          unstaged:
              canonicalGitStatusCode(first == 0x3f ? '?' : '!', stagedSlot: false),
        ));
      }
    }

    return GitResult.ok(RepositoryStatus(
        branch: branchName,
        upstream: upstreamName,
        ahead: ahead,
        behind: behind,
        files: files));
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

/// Return the byte-index of the [n]th space in [s], or -1 when there
/// are fewer than [n] spaces. Used to locate the path field in
/// porcelain-v2 entries without allocating a full `split(' ')` list
/// per status line.
int _nthSpace(String s, int n) {
  var count = 0;
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) == 0x20) {
      count++;
      if (count == n) return i;
    }
  }
  return -1;
}

/// Format string used by both listCommitHistory and listFileHistory.
/// Shape: hash, shortHash, parents, refs, subject, author, email, date.
/// Keep in sync with `_parseCommitLogLines` below.
const String _kCommitLogFormat = '--format=%H%n%h%n%P%n%D%n%s%n%aN%n%aE%n%aI';

/// Parses 8-line commit records from `git log --format=_kCommitLogFormat`.
/// Each commit occupies 8 consecutive non-empty lines; blank lines separate
/// them. Used by listCommitHistory and listFileHistory.
List<CommitHistoryEntry> _parseCommitLogLines(List<String> lines) {
  final entries = <CommitHistoryEntry>[];
  int i = 0;
  while (i + 7 < lines.length) {
    final hash = lines[i].trim();
    if (hash.isEmpty) {
      i++;
      continue;
    }
    final parents =
        lines[i + 2].trim().split(' ').where((s) => s.isNotEmpty).toList();
    entries.add(CommitHistoryEntry(
      commitHash: hash,
      shortHash: lines[i + 1].trim(),
      parentHashes: parents,
      refNames: lines[i + 3]
          .trim()
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      isMerge: parents.length > 1,
      subject: lines[i + 4].trim(),
      authorName: lines[i + 5].trim(),
      authorEmail: lines[i + 6].trim(),
      authoredAt: lines[i + 7].trim(),
    ));
    i += 8;
    while (i < lines.length && lines[i].trim().isEmpty) i++;
  }
  return entries;
}

Future<GitResult<List<CommitHistoryEntry>>> listCommitHistory(String repo,
    {int limit = 200, String? branch}) async {
  final args = ['log', _kCommitLogFormat, '-n', '$limit'];
  if (branch != null) args.add(branch);
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(_parseCommitLogLines(r.stdout.toString().split('\n')));
}

/// Commits reachable from [branch] that are NOT reachable from [excluding].
/// Concretely: `git log <branch> ^<excluding>` — the diverged set, oldest
/// at the end like every other history list. Used by the History page's
/// hover-preview to show what commits would land if the user merged
/// the hovered desk into the active worktree, without leaving the view.
Future<GitResult<List<CommitHistoryEntry>>> listCommitsAhead(
  String repo, {
  required String branch,
  required String excluding,
  int limit = 200,
}) async {
  final args = [
    'log',
    _kCommitLogFormat,
    '-n',
    '$limit',
    branch,
    '^$excluding',
  ];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(_parseCommitLogLines(r.stdout.toString().split('\n')));
}

/// Bulk-fetches file stats for all commits in two parallel git log passes
/// (--numstat and --name-status). Merges with already-loaded commit metadata
/// to produce a full CommitDetailData per commit — body is left empty since
/// it isn't needed for the file list view and the individual getCommitDetail
/// path fills it in on demand.
Future<GitResult<Map<String, CommitDetailData>>> bulkGetCommitDetails(
  String repo,
  List<CommitHistoryEntry> commits, {
  int limit = 200,
  String? branch,
}) async {
  if (commits.isEmpty) return GitResult.ok({});

  final meta = {for (final c in commits) c.commitHash: c};
  final args = ['log', '--format=>>>%H', '-n', '$limit'];
  if (branch != null) args.add(branch);
  // Single `git log --numstat --name-status` replaces the old two
  // parallel invocations. Git emits both blocks per commit (name-status
  // first, numstat second), distinguishable by line shape:
  //   numstat    : starts with a digit or `-` (binary)  e.g. `42\t7\tpath`
  //   name-status: starts with a letter                  e.g. `M\tpath`
  // Parsing by first-char discriminates the two streams without needing
  // a separator pass — one log walk replaces two.
  args.add('--numstat');
  args.add('--name-status');
  final r = await _git(repo, args);
  if (r.exitCode != 0) {
    return GitResult.err(r.stderr.toString().trim());
  }

  final numstatByHash = <String, List<_BulkFileStat>>{};
  final changeTypesByHash = <String, Map<String, String>>{};
  String? cur;
  for (final line in r.stdout.toString().split('\n')) {
    if (line.startsWith('>>>')) {
      cur = line.substring(3).trim();
      numstatByHash[cur] = [];
      changeTypesByHash[cur] = {};
      continue;
    }
    if (cur == null) continue;
    if (line.isEmpty) continue;
    final first = line.codeUnitAt(0);
    final isDigit = first >= 0x30 && first <= 0x39;
    final isDash = first == 0x2d; // '-' — binary file in numstat
    if (isDigit || isDash) {
      // Numstat row: <adds>\t<dels>\t<path>  (or -\t-\t<path>)
      final parts = line.split('\t');
      if (parts.length >= 3) {
        final adds = int.tryParse(parts[0]) ?? 0;
        final dels = int.tryParse(parts[1]) ?? 0;
        final path = parts[2].trim();
        if (path.isNotEmpty) {
          numstatByHash[cur]!.add(_BulkFileStat(path, adds, dels));
        }
      }
    } else if (first >= 0x41 && first <= 0x5a) {
      // Name-status row: <letter><score?>\t<path>  (rename: <letter>\t<old>\t<new>)
      final tabIdx = line.indexOf('\t');
      if (tabIdx < 0) continue;
      final type = line.substring(0, 1);
      final rest = line.substring(tabIdx + 1);
      final path = rest.contains('\t') ? rest.split('\t').last : rest;
      changeTypesByHash[cur]![path.trim()] = type;
    }
  }

  // Build CommitDetailData from existing metadata + fetched file stats
  final out = <String, CommitDetailData>{};
  for (final c in commits) {
    final stats = numstatByHash[c.commitHash] ?? [];
    final types = changeTypesByHash[c.commitHash] ?? {};
    final files = stats
        .map((s) => CommitFileStatData(
              path: s.path,
              additions: s.additions,
              deletions: s.deletions,
              changeType: types[s.path] ?? 'M',
            ))
        .toList();
    out[c.commitHash] = CommitDetailData(
      commitHash: c.commitHash,
      shortHash: c.shortHash,
      subject: c.subject,
      body: '',
      authorName: c.authorName,
      authorEmail: c.authorEmail,
      authoredAt: c.authoredAt,
      filesChanged: files.length,
      additions: files.fold(0, (s, f) => s + f.additions),
      deletions: files.fold(0, (s, f) => s + f.deletions),
      files: files,
    );
  }
  return GitResult.ok(out);
}

class _BulkFileStat {
  final String path;
  final int additions;
  final int deletions;
  const _BulkFileStat(this.path, this.additions, this.deletions);
}

/// Wraps a history entry with the file path AS IT EXISTED at that commit.
/// Critical for correctly fetching diffs/blame across renames: if the file
/// was foo.txt before being renamed to bar.txt, pre-rename commits must be
/// queried with the OLD name, not the current one.
class FileHistoryEntry {
  final CommitHistoryEntry commit;
  final String pathAtRevision;
  const FileHistoryEntry({
    required this.commit,
    required this.pathAtRevision,
  });
}

/// Returns the commit history for a file, with `--follow` tracking renames,
/// AND the path the file had at each commit (used to query diffs/blame
/// correctly for commits from before a rename).
Future<GitResult<List<FileHistoryEntry>>> listFileHistoryWithPaths(
  String repo,
  String filePath, {
  int limit = 100,
}) async {
  // --name-status emits a status line (M/A/D/R100 etc.) after each commit's
  // metadata, with the file path(s) involved. For renames, two paths:
  // old\tnew. We use these to resolve the name at each historical commit.
  final r = await _git(repo, [
    'log',
    '--follow',
    _kCommitLogFormat,
    '--name-status',
    '-n',
    '$limit',
    '--',
    filePath,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  // Separate the interleaved output into two streams:
  //   - commit metadata lines (8 per commit) → parsed by shared helper
  //   - per-commit name-status lines → resolved into pathsByHash
  // This keeps `_parseCommitLogLines` as the single source of truth for
  // the 8-line commit format.
  final raw = r.stdout.toString().split('\n');
  final metadataLines = <String>[];
  final pathsByHash = <String, String>{};
  // Rolling fallback: git log is newest→oldest, so if a commit's name-status
  // fails to parse, the last successfully-resolved path is more likely to be
  // correct than the current HEAD filePath (which would be wrong for anything
  // before a rename).
  String? lastKnownPath;
  int i = 0;
  while (i + 7 < raw.length) {
    final hash = raw[i].trim();
    if (hash.isEmpty) {
      i++;
      continue;
    }
    // Forward the 8 metadata lines + a blank separator to the shared parser.
    for (var j = 0; j < 8; j++) {
      metadataLines.add(i + j < raw.length ? raw[i + j] : '');
    }
    metadataLines.add('');
    i += 8;
    while (i < raw.length && raw[i].trim().isEmpty) i++;
    // Name-status lines: "STATUS\tpath" or "R100\told\tnew". In both cases
    // we want parts[1]: the first path (old name for renames, which is what
    // the file was called AT this commit in the file's history chain).
    String? pathAt;
    while (i < raw.length && raw[i].isNotEmpty) {
      final parts = raw[i].split('\t');
      if (parts.length >= 2) pathAt = parts[1];
      i++;
    }
    final resolved = pathAt ?? lastKnownPath ?? filePath;
    pathsByHash[hash] = resolved;
    lastKnownPath = resolved;
  }

  final commits = _parseCommitLogLines(metadataLines);
  final entries = commits
      .map((c) => FileHistoryEntry(
            commit: c,
            pathAtRevision: pathsByHash[c.commitHash] ?? filePath,
          ))
      .toList();
  return GitResult.ok(entries);
}

/// Thin wrapper returning just the commit entries (path info discarded).
/// Kept for callers that don't need rename-aware behavior.
Future<GitResult<List<CommitHistoryEntry>>> listFileHistory(
  String repo,
  String filePath, {
  int limit = 100,
}) async {
  final r = await listFileHistoryWithPaths(repo, filePath, limit: limit);
  if (!r.ok) return GitResult.err(r.error!);
  return GitResult.ok(r.data!.map((e) => e.commit).toList());
}

Future<GitResult<String>> getFileDiffAtRevision(
  String repo,
  String filePath,
  String commitHash,
) async {
  final r = await _git(repo, [
    'diff',
    '$commitHash~1..$commitHash',
    '--',
    filePath,
  ]);
  if (r.exitCode == 0) return GitResult.ok(r.stdout.toString());

  // Only fall back to `git show` when the error genuinely looks like
  // "this commit has no parent" — i.e. a root commit. Other errors
  // (invalid hash, missing file, etc.) should surface as-is instead of
  // being masked by a second command's failure.
  final primaryErr = r.stderr.toString();
  final looksLikeRootCommit = primaryErr.contains('unknown revision') ||
      primaryErr.contains('ambiguous argument') ||
      primaryErr.contains('bad revision');
  if (!looksLikeRootCommit) {
    return GitResult.err(primaryErr.trim());
  }
  final r2 = await _git(repo, ['show', commitHash, '--', filePath]);
  if (r2.exitCode != 0) {
    // Preserve the original diff error context alongside the fallback's.
    return GitResult.err(
      '${primaryErr.trim()}\n(fallback also failed: ${r2.stderr.toString().trim()})',
    );
  }
  return GitResult.ok(r2.stdout.toString());
}

/// Full multi-file diff for a commit. Same fallback as the per-file
/// Method picker for [applyBranchToBase]. Mirrors GitHub's three
/// well-known PR-merge strategies; each maps to a different `git`
/// command sequence inside the function.
enum BranchMergeMethod {
  /// `git merge --no-ff <branch>` — preserves both histories with an
  /// explicit merge commit.
  mergeCommit,

  /// `git merge --squash <branch>` then `git commit -m <subject>` —
  /// collapses every commit on the branch into one on the base.
  squash,

  /// `git rebase <base>` on the branch, then `git merge --ff-only` —
  /// linear history, no merge commit.
  rebase,
}

/// Apply [branch] onto [baseRef] inside [mainRepoPath], using the
/// chosen [method]. Optionally deletes [branch] after a successful
/// merge. The function performs only git operations (Process.run);
/// callers handle UI feedback (snackbars) + state updates
/// (DeskPrState, RepositoryState refresh) themselves.
/// On any step failure, leaves the working tree as `git` itself does
/// (rebase failures auto-`--abort`; merge conflicts leave conflict
/// markers in the tree as usual). The returned [GitResult.error]
/// carries the trimmed stderr from the failing step.
/// Shared between the branches-page PR row, the desk context menu's
/// "Apply to main", and any future caller — the engine that decides
/// which `git` commands to run lives here, not in widget state.
Future<GitResult<void>> applyBranchToBase({
  required String mainRepoPath,
  required String branch,
  required String baseRef,
  required BranchMergeMethod method,
  bool deleteBranch = true,
  String? squashSubject,
}) async {
  // Always start from the base. If we can't switch to it the rest of
  // the pipeline is meaningless.
  final checkoutBase = await _git(mainRepoPath, ['checkout', baseRef]);
  if (checkoutBase.exitCode != 0) {
    return GitResult.err(
      'Could not switch to $baseRef: ${checkoutBase.stderr.toString().trim()}',
    );
  }

  switch (method) {
    case BranchMergeMethod.rebase:
      // Step onto the branch, replay it on top of the base, step back,
      // fast-forward the base. On rebase failure: abort + restore base.
      final coBranch = await _git(mainRepoPath, ['checkout', branch]);
      if (coBranch.exitCode != 0) {
        return GitResult.err(
          'Could not switch to $branch: ${coBranch.stderr.toString().trim()}',
        );
      }
      final rebase = await _git(mainRepoPath, ['rebase', baseRef]);
      if (rebase.exitCode != 0) {
        await _git(mainRepoPath, ['rebase', '--abort']);
        await _git(mainRepoPath, ['checkout', baseRef]);
        return GitResult.err(
          'Rebase failed: ${rebase.stderr.toString().trim()}',
        );
      }
      await _git(mainRepoPath, ['checkout', baseRef]);
      final ff = await _git(mainRepoPath, ['merge', '--ff-only', branch]);
      if (ff.exitCode != 0) {
        return GitResult.err(
          'Fast-forward failed: ${ff.stderr.toString().trim()}',
        );
      }
      break;

    case BranchMergeMethod.squash:
      final sq = await _git(mainRepoPath, ['merge', '--squash', branch]);
      if (sq.exitCode != 0) {
        return GitResult.err(
          'Squash failed: ${sq.stderr.toString().trim()}',
        );
      }
      // `--squash` stages the change but leaves it uncommitted; finalise
      // with the supplied subject (or a sane default).
      final subject = (squashSubject != null && squashSubject.trim().isNotEmpty)
          ? squashSubject.trim()
          : 'Merge local PR ($branch)';
      final commit = await _git(mainRepoPath, ['commit', '-m', subject]);
      if (commit.exitCode != 0) {
        return GitResult.err(
          'Squash commit failed: ${commit.stderr.toString().trim()}',
        );
      }
      break;

    case BranchMergeMethod.mergeCommit:
      final mc = await _git(mainRepoPath, ['merge', '--no-ff', branch]);
      if (mc.exitCode != 0) {
        return GitResult.err(
          'Merge failed: ${mc.stderr.toString().trim()}',
        );
      }
      break;
  }

  if (deleteBranch) {
    // Best-effort. `-d` (not `-D`) refuses if the branch isn't merged;
    // after a successful merge it always succeeds. Surface the error
    // string but don't fail the overall operation — the merge landed.
    final del = await _git(mainRepoPath, ['branch', '-d', branch]);
    if (del.exitCode != 0) {
      return GitResult.err(
        'Merged but could not delete $branch: '
        '${del.stderr.toString().trim()}',
      );
    }
  }
  return GitResult.ok(null);
}

/// variant for root commits (`git diff <hash>~1..<hash>` fails when
/// there's no parent → fall back to `git show`).
Future<GitResult<String>> getCommitDiff(String repo, String commitHash) async {
  final r = await _git(repo, ['diff', '$commitHash~1..$commitHash']);
  if (r.exitCode == 0) return GitResult.ok(r.stdout.toString());
  final primaryErr = r.stderr.toString();
  final looksLikeRootCommit = primaryErr.contains('unknown revision') ||
      primaryErr.contains('ambiguous argument') ||
      primaryErr.contains('bad revision');
  if (!looksLikeRootCommit) {
    return GitResult.err(primaryErr.trim());
  }
  final r2 = await _git(repo, ['show', commitHash]);
  if (r2.exitCode != 0) {
    return GitResult.err(
      '${primaryErr.trim()}\n(fallback also failed: ${r2.stderr.toString().trim()})',
    );
  }
  return GitResult.ok(r2.stdout.toString());
}

Future<GitResult<CommitDetailData>> getCommitDetail(
    String repo, String hash) async {
  // Two calls: metadata + numstat, and name-status for change types
  final results = await Future.wait([
    _git(repo, [
      'show',
      '--numstat',
      '--format=%H%n%h%n%s%n%b%n---END-META---%n%aN%n%aE%n%aI',
      hash
    ]),
    _git(repo, ['diff-tree', '--no-commit-id', '-r', '--name-status', hash]),
  ]);

  final r = results[0];
  final r2 = results[1];
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  // Parse change types from name-status output
  final changeTypes = <String, String>{};
  if (r2.exitCode == 0) {
    for (final line in r2.stdout.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final tabIdx = trimmed.indexOf('\t');
      if (tabIdx < 0) continue;
      final type = trimmed.substring(0, tabIdx).trim();
      final path = trimmed.substring(tabIdx + 1).trim();
      // For renames, git outputs "old\tnew" after the type — use the new path
      final finalPath = path.contains('\t') ? path.split('\t').last : path;
      changeTypes[finalPath] = type.substring(0, 1); // first char: M/A/D/R/C
    }
  }

  final output = r.stdout.toString();
  final metaEnd = output.indexOf('---END-META---');
  if (metaEnd == -1) return GitResult.err('Unexpected git output');

  final metaLines = output.substring(0, metaEnd).split('\n');
  final fullHash = metaLines[0].trim();
  final shortHash = metaLines[1].trim();
  final subject = metaLines[2].trim();
  final bodyLines = <String>[];
  int mi = 3;
  while (mi < metaLines.length && metaLines[mi].trim() != '---END-META---') {
    bodyLines.add(metaLines[mi]);
    mi++;
  }

  final afterMeta =
      output.substring(metaEnd + '---END-META---'.length).split('\n');
  final authorName = afterMeta.isNotEmpty ? afterMeta[0].trim() : '';
  final authorEmail = afterMeta.length > 1 ? afterMeta[1].trim() : '';
  final authoredAt = afterMeta.length > 2 ? afterMeta[2].trim() : '';

  // Parse numstat lines: additions<tab>deletions<tab>path
  final files = <CommitFileStatData>[];
  for (final line in afterMeta.skip(3)) {
    final parts = line.trim().split('\t');
    if (parts.length < 3) continue;
    final adds = int.tryParse(parts[0]) ?? 0; // '-' for binaries → 0
    final dels = int.tryParse(parts[1]) ?? 0;
    final filePath = parts[2].trim();
    if (filePath.isEmpty) continue;
    files.add(CommitFileStatData(
        path: filePath,
        additions: adds,
        deletions: dels,
        changeType: changeTypes[filePath] ?? 'M'));
  }

  return GitResult.ok(CommitDetailData(
    commitHash: fullHash,
    shortHash: shortHash,
    subject: subject,
    body: bodyLines.join('\n').trim(),
    authorName: authorName,
    authorEmail: authorEmail,
    authoredAt: authoredAt,
    filesChanged: files.length,
    additions: files.fold(0, (s, f) => s + f.additions),
    deletions: files.fold(0, (s, f) => s + f.deletions),
    files: files,
  ));
}

Future<GitResult<String>> getFileDiff(String repo, String path,
    {bool staged = false, int contextLines = 3}) async {
  final args = staged
      ? ['diff', '--cached', '-U$contextLines', '--', path]
      : ['diff', '-U$contextLines', '--', path];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(r.stdout.toString());
}

/// Everything a desk has *added* relative to where it diverged from
/// [targetRef], as a single unified diff. Run from inside the desk's
/// worktree and compared against the **merge-base** of [targetRef] and
/// the desk's HEAD, this folds:
///   • commits the desk has made since branching from [targetRef],
///   • uncommitted modifications to tracked files, AND
///   • untracked files in the desk's working tree
/// into one patch that, when applied to a [targetRef] worktree, brings
/// the desk's contributions over without reverting anything [targetRef]
/// has gained in the meantime. Returns an empty string when the desk
/// has nothing beyond the divergence point (no own commits, no WIP,
/// no new files).
/// Diffing against [targetRef] directly was an earlier implementation
/// and was wrong: when the desk was behind [targetRef], the resulting
/// patch contained reversals of every [targetRef] commit the desk
/// hadn't yet picked up. Imprinting that on a clean [targetRef]
/// worktree wiped real work. Merge-base scoping is the only shape
/// that captures "the desk's contribution" symmetrically across
/// ahead / behind / diverged states.
/// `git diff` ignores untracked files by default, so a separate
/// `ls-files --others --exclude-standard` pass enumerates them and
/// each is rendered as a synthetic `/dev/null → b/<path>` block. The
/// same helper [getSelectionDiff] uses on the changes page; format is
/// what `git apply` consumes for new-file creation.
/// Count commits the worktree's HEAD is ahead and behind [targetRef].
/// Returns `(ahead, behind)` — for "is the desk behind main?" the
/// caller reads `behind > 0 && ahead == 0` as "fast-forwardable."
/// Runs `git rev-list --left-right --count targetRef...HEAD` in the
/// desk's worktree. Returns err on detached HEAD with no resolvable
/// target, empty output, or unrelated histories.
Future<GitResult<({int ahead, int behind})>> getDeskAheadBehind(
  String deskPath,
  String targetRef,
) async {
  final res = await _git(
    deskPath,
    ['rev-list', '--left-right', '--count', '$targetRef...HEAD'],
  );
  if (res.exitCode != 0) {
    return GitResult.err(res.stderr.toString().trim().isEmpty
        ? 'Could not compare with $targetRef.'
        : res.stderr.toString().trim());
  }
  final parts = res.stdout.toString().trim().split(RegExp(r'\s+'));
  if (parts.length < 2) {
    return GitResult.err('Unexpected rev-list output: "${res.stdout}"');
  }
  // left (targetRef-only) is "behind"; right (HEAD-only) is "ahead".
  final behind = int.tryParse(parts[0]) ?? 0;
  final ahead = int.tryParse(parts[1]) ?? 0;
  return GitResult.ok((ahead: ahead, behind: behind));
}

/// Fast-forward the desk's checked-out branch to [targetRef]. Fails
/// (ok=false, no side effects) if the fast-forward isn't possible —
/// i.e. the desk has diverged or has uncommitted changes that block
/// the merge. Callers should fall back to a patch / rebase flow in
/// that case. Succeeds when the desk is a strict ancestor of the
/// target and the worktree is clean: git moves HEAD + updates the
/// working tree in one atomic step.
Future<GitResult<void>> fastForwardDeskTo(
  String deskPath,
  String targetRef,
) async {
  final res = await _git(
    deskPath,
    ['merge', '--ff-only', targetRef],
  );
  if (res.exitCode != 0) {
    return GitResult.err(res.stderr.toString().trim().isEmpty
        ? 'Fast-forward from $targetRef failed.'
        : res.stderr.toString().trim());
  }
  return const GitResult.ok(null);
}

Future<GitResult<String>> getDeskDumpDiff(
  String deskPath,
  String targetRef, {
  int contextLines = 3,
}) async {
  final base = await _git(
    deskPath,
    ['merge-base', targetRef, 'HEAD'],
  );
  if (base.exitCode != 0) {
    // No common ancestor — unrelated histories. There is no meaningful
    // "desk's contribution" to extract; surface the underlying error so
    // the caller can show it instead of silently dumping a giant
    // whole-tree diff.
    return GitResult.err(base.stderr.toString().trim().isEmpty
        ? 'No common history between desk and $targetRef.'
        : base.stderr.toString().trim());
  }
  final mergeBase = base.stdout.toString().trim();

  // Tracked changes since divergence (committed + WIP modifications).
  final tracked = await _git(
    deskPath,
    ['diff', '-U$contextLines', mergeBase],
  );
  if (tracked.exitCode != 0) {
    return GitResult.err(tracked.stderr.toString().trim());
  }

  // Untracked files — enumerate then synthesize new-file diffs.
  // --exclude-standard honours .gitignore + .git/info/exclude + the
  // user's global excludes, so ignored junk doesn't leak into the dump.
  final untracked = await _git(
    deskPath,
    ['ls-files', '--others', '--exclude-standard'],
  );
  if (untracked.exitCode != 0) {
    return GitResult.err(untracked.stderr.toString().trim());
  }
  final untrackedPaths = untracked.stdout
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final parts = <String>[];
  final trackedOut = tracked.stdout.toString();
  if (trackedOut.trim().isNotEmpty) parts.add(trackedOut);
  for (final path in untrackedPaths) {
    parts.add(await _buildSyntheticUntrackedDiff(deskPath, path));
  }
  return GitResult.ok(parts.where((p) => p.trim().isNotEmpty).join('\n'));
}

Future<GitResult<String>> getSelectionDiff(
  String repo,
  List<RepositoryStatusFile> files, {
  int contextLines = 3,
}) async {
  if (files.isEmpty) {
    return const GitResult.ok('');
  }

  final parts = <String>[];
  final trackedPaths = files
      .where((file) => !_isUntrackedFile(file))
      .map((file) => file.path)
      .toList();
  final hasTrackedStaged = files.any(
    (file) => !file.isUntracked && file.hasStagedChange,
  );
  final hasTrackedUnstaged = files.any(
    (file) => !file.isUntracked && file.hasUnstagedChange,
  );

  if (trackedPaths.isNotEmpty && hasTrackedStaged) {
    final stagedResult = await _git(
      repo,
      ['diff', '--cached', '-U$contextLines', '--', ...trackedPaths],
    );
    if (stagedResult.exitCode != 0) {
      return GitResult.err(stagedResult.stderr.toString().trim());
    }
    final output = stagedResult.stdout.toString().trim();
    if (output.isNotEmpty) {
      parts.add(output);
    }
  }

  if (trackedPaths.isNotEmpty && hasTrackedUnstaged) {
    final unstagedResult = await _git(
      repo,
      ['diff', '-U$contextLines', '--', ...trackedPaths],
    );
    if (unstagedResult.exitCode != 0) {
      return GitResult.err(unstagedResult.stderr.toString().trim());
    }
    final output = unstagedResult.stdout.toString().trim();
    if (output.isNotEmpty) {
      parts.add(output);
    }
  }

  for (final file in files.where(_isUntrackedFile)) {
    parts.add(await _buildSyntheticUntrackedDiff(repo, file.path));
  }

  return GitResult.ok(parts.where((part) => part.trim().isNotEmpty).join('\n'));
}

bool _isUntrackedFile(RepositoryStatusFile file) => file.isUntracked;

Future<String> _buildSyntheticUntrackedDiff(
    String repo, String relativePath) async {
  final normalizedPath = relativePath.replaceAll('\\', '/');
  final file = File(
    '$repo${Platform.pathSeparator}${normalizedPath.replaceAll('/', Platform.pathSeparator)}',
  );

  List<String> lines;
  try {
    final bytes = await file.readAsBytes();
    final isBinary = bytes.contains(0);
    if (isBinary) {
      lines = const ['[binary content omitted]'];
    } else {
      final content = utf8.decode(bytes, allowMalformed: true);
      lines = const LineSplitter().convert(content);
      if (content.isEmpty) {
        lines = const [''];
      }
    }
  } catch (_) {
    lines = const ['[unable to read file content]'];
  }

  final buffer = StringBuffer()
    ..writeln('diff --git a/$normalizedPath b/$normalizedPath')
    ..writeln('new file mode 100644')
    ..writeln('--- /dev/null')
    ..writeln('+++ b/$normalizedPath')
    ..writeln('@@ -0,0 +1,${lines.length} @@');

  for (final line in lines) {
    buffer.writeln('+$line');
  }

  return buffer.toString().trimRight();
}

Future<GitResult<List<BranchInfo>>> listBranches(String repo) async {
  final r = await _git(repo, [
    'branch',
    '-vv',
    '--format=%(refname:short)%09%(HEAD)%09%(upstream:short)%09%(upstream:track)'
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final branches = <BranchInfo>[];
  for (final line in r.stdout.toString().split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split('\t');
    final name = parts[0].trim();
    final isCurrent = parts.length > 1 && parts[1].trim() == '*';
    final upstream =
        parts.length > 2 && parts[2].trim().isNotEmpty ? parts[2].trim() : null;
    int ahead = 0, behind = 0;
    if (parts.length > 3) {
      final track = parts[3];
      final aheadMatch = RegExp(r'ahead (\d+)').firstMatch(track);
      final behindMatch = RegExp(r'behind (\d+)').firstMatch(track);
      if (aheadMatch != null) ahead = int.tryParse(aheadMatch.group(1)!) ?? 0;
      if (behindMatch != null)
        behind = int.tryParse(behindMatch.group(1)!) ?? 0;
    }
    branches.add(BranchInfo(
        name: name,
        current: isCurrent,
        upstream: upstream,
        ahead: ahead,
        behind: behind));
  }
  return GitResult.ok(branches);
}

Future<GitResult<void>> createBranch(String repo, String name,
    {String? from}) async {
  final args =
      from != null ? ['checkout', '-b', name, from] : ['checkout', '-b', name];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> checkoutBranch(String repo, String name) async {
  final r = await _git(repo, ['checkout', name]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> deleteBranch(String repo, String name,
    {bool force = false}) async {
  final r = await _git(repo, ['branch', force ? '-D' : '-d', name]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Rename a local branch. `-M` to force-replace if [newName] already
/// exists (git rejects otherwise). Returns the git stderr on failure
/// so callers can surface the actual reason (ref collision, dirty
/// working tree, etc.).
Future<GitResult<void>> renameBranch(
    String repo, String oldName, String newName,
    {bool force = false}) async {
  final r = await _git(repo, ['branch', force ? '-M' : '-m', oldName, newName]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Cherry-pick a commit onto the current HEAD. Non-fast-forward; git
/// leaves conflicts in the working tree on failure — caller should
/// surface the stderr to the user so they can resolve or abort.
Future<GitResult<void>> cherryPickCommit(String repo, String hash) async {
  final r = await _git(repo, ['cherry-pick', hash]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Revert a commit — creates a new commit that undoes [hash] against
/// current HEAD. `--no-edit` skips the commit-message editor; the
/// default "Revert '<subject>'" message is fine for UI-driven reverts.
Future<GitResult<void>> revertCommit(String repo, String hash) async {
  final r = await _git(repo, ['revert', '--no-edit', hash]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// The primary remote's name. `origin` is the convention and wins when
/// present; otherwise we take the first remote `git remote` lists
/// (single-remote repos with non-conventional names — e.g. `upstream`
/// after a fork — are common enough to need this). Returns null only
/// when the repo has no remotes at all (fresh local-only repo).
/// Cached at the call site, not here — callers in tight loops should
/// resolve once and pass the result through, since this spawns a
/// subprocess.
Future<GitResult<String?>> primaryRemoteName(String repo) async {
  final r = await _git(repo, ['remote']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final names = <String>[
    for (final line in r.stdout.toString().split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (names.isEmpty) return const GitResult.ok(null);
  if (names.contains('origin')) return const GitResult.ok('origin');
  return GitResult.ok(names.first);
}

/// The repo's default branch name — what `git symbolic-ref
/// refs/remotes/<primary>/HEAD` points to, with a fallback scan for
/// `main` or `master` when no remote HEAD is set. Returns null when
/// the repo has no recognizable default (new repo, detached, nothing
/// configured). The History page uses this to compute trunk-vs-branch
/// lane assignment on the top timeline.
Future<GitResult<String?>> defaultBranchName(String repo) async {
  final remoteRes = await primaryRemoteName(repo);
  final remote = remoteRes.ok ? (remoteRes.data ?? 'origin') : 'origin';
  final viaRemote = await _git(
      repo, ['symbolic-ref', '--short', 'refs/remotes/$remote/HEAD']);
  if (viaRemote.exitCode == 0) {
    final raw = viaRemote.stdout.toString().trim();
    // Output form: "<remote>/main" — strip the remote prefix.
    final slash = raw.indexOf('/');
    if (slash > 0 && slash + 1 < raw.length) {
      return GitResult.ok(raw.substring(slash + 1));
    }
  }
  // Fallback: probe local + remote for conventional names. `main` wins
  // when both exist (modern convention); `master` used as legacy
  // fallback. `verify` avoids spawning a full `for-each-ref` walk.
  for (final candidate in const ['main', 'master']) {
    final check = await _git(
        repo, ['rev-parse', '--verify', '--quiet', 'refs/heads/$candidate']);
    if (check.exitCode == 0) return GitResult.ok(candidate);
    final remoteRef = await _git(repo, [
      'rev-parse',
      '--verify',
      '--quiet',
      'refs/remotes/$remote/$candidate',
    ]);
    if (remoteRef.exitCode == 0) return GitResult.ok(candidate);
  }
  return const GitResult.ok(null);
}

/// Hashes reachable from [ref], capped at [limit]. Returned as a Set
/// for O(1) membership checks in UI rendering paths. Caller matches
/// the [limit] against whatever history depth the surface is showing;
/// passing a smaller limit than the surface renders means some of the
/// on-screen commits will look "off-trunk" even when they're actually
/// deeper ancestors — so size the limit to the surface, not a default.
Future<GitResult<Set<String>>> ancestorHashes(
  String repo,
  String ref, {
  required int limit,
}) async {
  final r = await _git(repo, ['rev-list', '-n', '$limit', ref]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final hashes = <String>{
    for (final line in r.stdout.toString().split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  };
  return GitResult.ok(hashes);
}

Future<GitResult<List<TagEntryData>>> listTags(String repo) async {
  final r = await _git(repo, [
    'tag',
    '-l',
    '--format=%(refname:short)%09%(objecttype)%09%(*objectname)%09%(creatordate:iso)%09%(taggername)%09%(subject)'
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final tags = <TagEntryData>[];
  for (final line in r.stdout.toString().split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split('\t');
    tags.add(TagEntryData(
      name: parts[0].trim(),
      tagType: parts.length > 1 ? parts[1].trim() : 'lightweight',
      targetHash: parts.length > 2 && parts[2].trim().isNotEmpty
          ? parts[2].trim().substring(0, 8.clamp(0, parts[2].trim().length))
          : null,
      createdAt: parts.length > 3 && parts[3].trim().isNotEmpty
          ? parts[3].trim()
          : null,
      creatorName: parts.length > 4 && parts[4].trim().isNotEmpty
          ? parts[4].trim()
          : null,
      subject: parts.length > 5 && parts[5].trim().isNotEmpty
          ? parts[5].trim()
          : null,
    ));
  }
  return GitResult.ok(tags);
}

Future<GitResult<void>> createTag(String repo, String name, String targetRef,
    {String? message}) async {
  final args = message != null
      ? ['tag', '-a', '-m', message, name, targetRef]
      : ['tag', name, targetRef];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> deleteTag(String repo, String name) async {
  final r = await _git(repo, ['tag', '-d', name]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<List<ReflogEntryData>>> listReflog(String repo,
    {int limit = 100}) async {
  final r = await _git(repo,
      ['reflog', '--format=%H%09%h%09%gd%09%gs%09%aN%09%aI', '-n', '$limit']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final entries = <ReflogEntryData>[];
  for (final line in r.stdout.toString().split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split('\t');
    if (parts.length < 6) continue;
    entries.add(ReflogEntryData(
      commitHash: parts[0].trim(),
      shortHash: parts[1].trim(),
      refSelector: parts[2].trim(),
      actionSummary: parts[3].trim(),
      authorName: parts[4].trim(),
      authoredAt: parts[5].trim(),
    ));
  }
  return GitResult.ok(entries);
}

Future<GitResult<List<BlameLineData>>> getFileBlame(String repo, String path,
    {String? commitRef}) async {
  final args = [
    'blame',
    '--porcelain',
    if (commitRef != null) commitRef,
    '--',
    path
  ];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final lines = <BlameLineData>[];
  final commitData = <String, Map<String, String>>{};
  String currentHash = '';
  int lineNumber = 0;

  for (final line in r.stdout.toString().split('\n')) {
    if (line.isEmpty) continue;
    final hashMatch = RegExp(r'^([0-9a-f]{40}) \d+ (\d+)').firstMatch(line);
    if (hashMatch != null) {
      currentHash = hashMatch.group(1)!;
      lineNumber = int.tryParse(hashMatch.group(2)!) ?? 0;
      commitData.putIfAbsent(currentHash, () => {});
      continue;
    }
    if (line.startsWith('author '))
      commitData[currentHash]?['author'] = line.substring(7);
    if (line.startsWith('author-time '))
      commitData[currentHash]?['time'] = line.substring(12);
    if (line.startsWith('\t')) {
      final data = commitData[currentHash] ?? {};
      lines.add(BlameLineData(
        lineNumber: lineNumber,
        commitHash: currentHash,
        shortHash:
            currentHash.length >= 8 ? currentHash.substring(0, 8) : currentHash,
        authorName: data['author'] ?? '',
        authoredAt: data['time'] ?? '',
        lineContent: line.substring(1),
      ));
    }
  }
  return GitResult.ok(lines);
}

Future<GitResult<List<CommitSearchResultData>>> searchCommits(
    String repo, String query,
    {String scope = 'messages', int limit = 50}) async {
  List<String> args;
  switch (scope) {
    case 'code':
      args = [
        'log',
        '-S',
        query,
        '--format=%H%09%h%09%s%09%aN%09%aI',
        '-n',
        '$limit'
      ];
      break;
    case 'files':
      args = [
        'log',
        '--format=%H%09%h%09%s%09%aN%09%aI',
        '-n',
        '$limit',
        '--',
        query
      ];
      break;
    default:
      args = [
        'log',
        '--grep=$query',
        '-i',
        '--format=%H%09%h%09%s%09%aN%09%aI',
        '-n',
        '$limit'
      ];
  }
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final results = <CommitSearchResultData>[];
  for (final line in r.stdout.toString().split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split('\t');
    if (parts.length < 5) continue;
    results.add(CommitSearchResultData(
      commitHash: parts[0].trim(),
      shortHash: parts[1].trim(),
      subject: parts[2].trim(),
      authorName: parts[3].trim(),
      authoredAt: parts[4].trim(),
    ));
  }
  return GitResult.ok(results);
}

/// Per-file change breakdown (adds / dels / binary flag) across the
/// working tree. Combines cached and unstaged numstats from one diff
/// pass each. Binary files report `-<TAB>-` in numstat; we surface
/// `binary: true` so callers can weight them with a baseline instead
/// of the 0 they'd otherwise get from line counts.
Future<GitResult<Map<String, FileChangeWeight>>> fileChangeWeights(
    String repo) async {
  final weights = <String, FileChangeWeight>{};
  for (final cached in [false, true]) {
    final args = <String>['diff', '--numstat', if (cached) '--cached'];
    final r = await _git(repo, args);
    if (r.exitCode != 0) continue;
    for (final raw in r.stdout.toString().split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      final addsRaw = parts[0];
      final delsRaw = parts[1];
      final path = parts.sublist(2).join('\t').trim();
      if (path.isEmpty) continue;
      final isBinary = addsRaw == '-' || delsRaw == '-';
      final adds = isBinary ? 0 : (int.tryParse(addsRaw) ?? 0);
      final dels = isBinary ? 0 : (int.tryParse(delsRaw) ?? 0);
      final existing = weights[path];
      weights[path] = FileChangeWeight(
        adds: (existing?.adds ?? 0) + adds,
        dels: (existing?.dels ?? 0) + dels,
        binary: isBinary || (existing?.binary ?? false),
      );
    }
  }
  return GitResult.ok(weights);
}

/// Aggregated signals from a single `git log` scan over a set of
/// paths — reused by the PR detail view to surface "who knows this
/// code" + "how hot is this code right now" without doing two scans.
class FileSignals {
  /// Per-author commit count across the path union, sorted desc.
  final List<({String email, int commits})> authors;

  /// Per-path "heat" in 0..1 — exponentially-decayed commit density
  /// over the last [thermalWindowDays]. 0 = stone cold, 1 = on fire
  /// right now. Used to render the ember-glow on file pills.
  final Map<String, double> heatByPath;
  const FileSignals({required this.authors, required this.heatByPath});

  static const empty = FileSignals(authors: [], heatByPath: {});
}

/// Marker token prefixing each commit header in [scanFileSignals]'s
/// `git log` output. `\x01` (ASCII Start-of-Heading) is chosen over a
/// string sentinel like `__C__` because file paths can legally start
/// with double-underscore (e.g. `__generated__`, `__init__.py`) — a
/// control character cannot appear at column 0 of `--name-only` output
/// in any realistic repo, so misidentification is impossible.
const String _kFileSignalsMarker = '\x01';

/// One scan, two signals: who has been touching this code AND how hot
/// each file is right now (exponentially-decayed commit density).
/// Used by the PR detail surface for the PEOPLE section + per-file
/// thermal glow. Pure local git; transferable to any host.
///
/// Cost: one `git log` invocation total, regardless of path count.
/// Previously this was O(paths) subprocesses — 12 spawns per typical
/// PR detail × N expanded PRs dominated the branches-page latency on
/// Windows (each spawn ~50ms, plus .git I/O contention). The batched
/// form filters commits via the pathspec and then buckets per-file
/// in memory, preserving the original [maxPerFile] cap as a
/// newest-first counter per path.
Future<GitResult<FileSignals>> scanFileSignals(
  String repo,
  List<String> paths, {
  int maxPerFile = 20,
  int sinceDays = 365,
  double thermalTauDays = 14,
}) async {
  if (paths.isEmpty) return const GitResult.ok(FileSignals.empty);
  final since = '$sinceDays.days.ago';
  final r = await _git(repo, [
    'log',
    '--no-merges',
    // `--date-order` pins reverse-chronological-by-commit-date so the
    // per-path "newest-first" cap below is stable even in repos with
    // imported / rebased history whose default topo order would drift.
    '--date-order',
    '--since',
    since,
    '--name-only',
    // Marker-delimited commit header: email + timestamp (epoch).
    // Following lines list the file paths touched by that commit.
    // Note: `--name-only` with a pathspec emits the FULL changed-file
    // list per matching commit, not only the matching files — we
    // intersect with [pathSet] below to attribute correctly.
    '--format=$_kFileSignalsMarker%ae|%at',
    '--',
    ...paths,
  ]);
  // Best-effort signal: if the log fails (corrupt repo, invalid
  // pathspec on a single file) degrade to empty glow rather than
  // failing the whole PR detail surface — matches the old per-path
  // loop's tolerance (which `continue`d past individual failures).
  if (r.exitCode != 0) {
    return const GitResult.ok(FileSignals.empty);
  }

  final counts = <String, int>{};
  final heatByPath = <String, double>{};
  // Per-path newest-first cap that matches the old `-n $maxPerFile`
  // behaviour: git log default ordering is reverse-chronological, so
  // the first [maxPerFile] commits we see touching each path are the
  // most recent ones. Older touches are ignored for both heat and
  // author attribution.
  final perFileCount = <String, int>{};
  final pathSet = paths.toSet();
  final now = DateTime.now();

  String curEmail = '';
  DateTime? curAt;
  Set<String> curFiles = <String>{};

  void flushCommit() {
    if (curFiles.isEmpty) return;
    double? heatContribution;
    final at = curAt;
    if (at != null) {
      final ageDays = now.difference(at).inHours / 24.0;
      heatContribution = math.exp(-ageDays / thermalTauDays);
    }
    for (final file in curFiles) {
      if (!pathSet.contains(file)) continue;
      final seen = perFileCount[file] ?? 0;
      if (seen >= maxPerFile) continue;
      perFileCount[file] = seen + 1;
      if (curEmail.isNotEmpty) {
        counts[curEmail] = (counts[curEmail] ?? 0) + 1;
      }
      if (heatContribution != null) {
        heatByPath[file] = (heatByPath[file] ?? 0) + heatContribution;
      }
    }
  }

  for (final raw in (r.stdout as String).split('\n')) {
    final line = raw.trim();
    if (line.startsWith(_kFileSignalsMarker)) {
      flushCommit();
      final payload = line.substring(_kFileSignalsMarker.length);
      // Split on the LAST `|` — the author email side can legally
      // contain pipes (git accepts any string in `user.email`) while
      // the timestamp side is always `[0-9]+`, so the rightmost pipe
      // is the unambiguous delimiter.
      final pipe = payload.lastIndexOf('|');
      curEmail = pipe > 0 ? payload.substring(0, pipe) : payload;
      final tsStr = pipe > 0 ? payload.substring(pipe + 1) : '';
      final ts = int.tryParse(tsStr);
      curAt = ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
          : null;
      curFiles = <String>{};
      continue;
    }
    if (line.isEmpty) continue;
    curFiles.add(line.replaceAll('\\', '/'));
  }
  flushCommit();

  // Heat accumulates unclamped across a file's commits; clip once at
  // the end so visualisation stays in 0..1 while preserving ordering
  // among files whose raw heat exceeds 1.
  for (final entry in heatByPath.entries.toList()) {
    heatByPath[entry.key] = entry.value.clamp(0.0, 1.0).toDouble();
  }

  final authors = counts.entries
      .map((e) => (email: e.key, commits: e.value))
      .toList()
    ..sort((a, b) => b.commits.compareTo(a.commits));
  return GitResult.ok(FileSignals(authors: authors, heatByPath: heatByPath));
}

Future<GitResult<void>> stagePaths(String repo, List<String> paths) async {
  if (paths.isEmpty) return const GitResult.ok(null);

  // Pre-flight gitignore filter. `git add` refuses to add a path that
  // matches a .gitignore rule AND isn't already tracked — it exits 1
  // with the matching *pattern* in the error list ("paths ignored by
  // one of your .gitignore files: .claude"). That's fine when the
  // caller genuinely tried to stage a fresh ignored file, but it also
  // fires on staged-deletion paths: a file previously untracked via
  // `git rm --cached` is in the index as a deletion, in the UI's
  // "included" list as a change to commit, and on disk as an ignored
  // file. The deletion is already in the index — no `add` needed —
  // but the UI layer doesn't know that, so the blanket add breaks.
  //
  // `git check-ignore` gives us the filter: exit 0 + stdout lists
  // matching paths; exit 1 = no matches; exit 128 = fatal. We fail
  // open on errors (treat as "nothing to filter") so a broken
  // check-ignore never blocks a legitimate stage.
  final ignoreCheck = await _git(repo, ['check-ignore', '--', ...paths]);
  final ignored = <String>{};
  if (ignoreCheck.exitCode == 0) {
    for (final line in ignoreCheck.stdout.toString().split('\n')) {
      final p = line.trim();
      if (p.isNotEmpty) ignored.add(p);
    }
  }
  final toAdd = ignored.isEmpty
      ? paths
      : paths.where((p) => !ignored.contains(p)).toList();
  if (toAdd.isEmpty) return const GitResult.ok(null);

  final r = await _git(repo, ['add', '--', ...toAdd]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> unstagePaths(String repo, List<String> paths) async {
  if (paths.isEmpty) return const GitResult.ok(null);
  final stagedProbe = await _git(
      repo, ['diff', '--cached', '--name-only', '-z', '--', ...paths]);
  if (stagedProbe.exitCode != 0) {
    return GitResult.err(stagedProbe.stderr.toString().trim());
  }
  final stagedPaths = stagedProbe.stdout
      .toString()
      .split('\x00')
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toList();
  if (stagedPaths.isEmpty) return const GitResult.ok(null);

  final r = await _git(repo, ['restore', '--staged', '--', ...stagedPaths]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Discard all changes (staged AND unstaged) for a single file, matching
/// the GitHub Desktop "Discard changes" behaviour:
///   * **Untracked** (`?`) — nothing to restore from git's side; just
///     remove the file from disk. Git never knew about it.
///   * **Newly added in the index** (`A`, not yet in HEAD) — `git
///     checkout HEAD --` would error with "did not match any file(s)
///     known to git" because the path doesn't exist there. Unstage with
///     `git rm --cached` first, then delete the working copy.
///   * **Anything else** (modified, deleted, renamed, copied, conflict)
///     — `git checkout HEAD -- <path>` resets the path to its HEAD
///     state in one shot, wiping both staged and unstaged changes.
/// Irreversible. Caller is expected to confirm before invoking.
Future<GitResult<void>> discardFile(
  String repo,
  RepositoryStatusFile file,
) async {
  if (file.isUntracked) {
    return _deleteFromDisk(repo, file.path);
  }
  if (file.isStagedAddition) {
    final unstage =
        await _git(repo, ['rm', '--cached', '--force', '--', file.path]);
    if (unstage.exitCode != 0) {
      return GitResult.err(unstage.stderr.toString().trim());
    }
    return _deleteFromDisk(repo, file.path);
  }
  final r = await _git(repo, ['checkout', 'HEAD', '--', file.path]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> _deleteFromDisk(String repo, String relPath) async {
  try {
    final f = File(p.join(repo, relPath));
    if (await f.exists()) await f.delete();
    return const GitResult.ok(null);
  } catch (e) {
    return GitResult.err('Failed to delete file: $e');
  }
}

/// Append a single pattern to the repository's `.gitignore`. Creates
/// the file if it doesn't exist; ensures the existing content ends
/// with a newline before appending; no-ops if the exact pattern (after
/// trimming) is already present, so repeated invocations stay clean.
Future<GitResult<void>> addToGitignore(String repo, String pattern) async {
  try {
    final f = File(p.join(repo, '.gitignore'));
    final existing = await f.exists() ? await f.readAsString() : '';
    final trimmedPattern = pattern.trim();
    final alreadyPresent = existing
        .split('\n')
        .any((l) => l.trim() == trimmedPattern && trimmedPattern.isNotEmpty);
    if (alreadyPresent) return const GitResult.ok(null);
    final needsLeadingNewline = existing.isNotEmpty && !existing.endsWith('\n');
    final next = '$existing${needsLeadingNewline ? '\n' : ''}$trimmedPattern\n';
    await f.writeAsString(next);
    return const GitResult.ok(null);
  } catch (e) {
    return GitResult.err('Failed to update .gitignore: $e');
  }
}

/// Pipes a unified diff to `git apply`. Used for line-level staging AND
/// for the patch-loop (external .patch files).
/// - `cached` writes to the index (--cached). Mutually exclusive with the
///   patch-loop options; setting `threeWay` or `dryRun` overrides implicit
///   cached semantics per git's own rules.
/// - `reverse` inverts the patch (`-R`).
/// - `dryRun` uses `--check` — parses + simulates, never mutates.
/// - `threeWay` uses `-3` — falls back to 3-way merge on context drift.
Future<GitResult<void>> applyPatch(
  String repo,
  String patch, {
  bool cached = true,
  bool reverse = false,
  bool dryRun = false,
  bool threeWay = false,
  String? telemetryLabel,
}) async {
  if (patch.trim().isEmpty) return const GitResult.ok(null);
  final commandLabel = telemetryLabel ?? 'git.apply';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: commandLabel,
  );
  try {
    final args = <String>['apply'];
    if (cached) args.add('--cached');
    if (reverse) args.add('-R');
    if (dryRun) args.add('--check');
    if (threeWay) args.add('--3way');
    args.addAll(['--whitespace=nowarn', '-']);
    final process = await Process.start('git', args, workingDirectory: repo);
    process.stdin.write(patch);
    if (!patch.endsWith('\n')) process.stdin.writeln();
    await process.stdin.flush();
    await process.stdin.close();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exit = await process.exitCode;
    final stderrText = (await stderrFuture).trim();
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
    final ok = exit == 0;
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: ok ? 'success' : 'failure',
      command: commandLabel,
      durationMs: elapsedMs,
      errorCode: ok ? null : 'git.exit_$exit',
      message: ok ? null : stderrText,
    );
    if (!ok)
      return GitResult.err(
          stderrText.isEmpty ? 'git apply exit $exit' : stderrText);
    return const GitResult.ok(null);
  } catch (e) {
    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'failure',
      command: commandLabel,
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: 'git.invoke_failed',
      message: e.toString(),
    );
    return GitResult.err(e.toString());
  }
}

/// Atomic per-file partial staging: resets the index entry for the file to
/// HEAD, then applies the user's partial patch — so the index reflects
/// exactly the set of lines the user has marked staged in the UI.
/// Reset failures are ignored (untracked files have no HEAD entry).
/// An empty patch ends with the file fully unstaged — which is the
/// correct outcome when the user has deselected every line.
Future<GitResult<void>> applyFileStaging(
  String repo,
  String filePath,
  String patch,
) async {
  await _git(repo, ['reset', '-q', 'HEAD', '--', filePath]);
  if (patch.trim().isEmpty) return const GitResult.ok(null);
  return applyPatch(repo, patch, cached: true);
}

Future<GitResult<CommitData>> createCommit(String repo, String message,
    {bool amend = false, bool signoff = false}) async {
  final args = ['commit'];
  if (amend) args.add('--amend');
  if (signoff) args.add('-s');
  args.addAll(['-m', message]);
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  // Parse: "[branch abc1234] Subject line"
  final out = r.stdout.toString();
  final match = RegExp(r'\[(?:[^\s]+)\s+([a-f0-9]+)\]\s*(.+)').firstMatch(out);
  final hash = match?.group(1) ?? '';
  final summary = match?.group(2)?.trim() ?? message.split('\n').first;
  return GitResult.ok(
      CommitData(repositoryPath: repo, commitHash: hash, summary: summary));
}

Future<GitResult<SyncData>> fetchRemote(String repo,
    {String? remote, bool prune = false}) async {
  final r = remote ?? 'origin';
  final args = ['fetch', if (prune) '--prune', r];
  final result = await _git(repo, args);
  if (result.exitCode != 0)
    return GitResult.err(result.stderr.toString().trim());
  return GitResult.ok(SyncData(
      operation: 'fetch', remote: r, output: result.stdout.toString().trim()));
}

Future<GitResult<SyncData>> pullRemote(String repo,
    {String? remote, String? branch, bool rebase = false}) async {
  final r = remote ?? 'origin';
  final args = ['pull', if (rebase) '--rebase', r, if (branch != null) branch];
  final result = await _git(repo, args);
  if (result.exitCode != 0)
    return GitResult.err(result.stderr.toString().trim());
  return GitResult.ok(SyncData(
      operation: 'pull', remote: r, output: result.stdout.toString().trim()));
}

Future<GitResult<SyncData>> pushRemote(String repo,
    {String? remote,
    String? branch,
    bool setUpstream = false,
    bool forceWithLease = false}) async {
  final r = remote ?? 'origin';
  final args = ['push'];
  if (setUpstream) {
    args.addAll(['--set-upstream', r, branch ?? 'HEAD']);
  } else {
    args.add(r);
    if (branch != null) args.add(branch);
  }
  if (forceWithLease) args.add('--force-with-lease');
  final result = await _git(repo, args);
  if (result.exitCode != 0)
    return GitResult.err(result.stderr.toString().trim());
  return GitResult.ok(SyncData(
      operation: 'push', remote: r, output: result.stdout.toString().trim()));
}

/// Smart sync: publish if no upstream, pull if behind, push if ahead,
/// pull-then-push if both, or fetch if up to date.
Future<GitResult<SyncData>> syncRemote(
    String repo, RepositoryStatus status) async {
  final branch = status.branch;
  if (branch == 'HEAD' || branch.startsWith('(')) {
    return GitResult.err(
        'Cannot sync: detached HEAD state. Check out a branch first.');
  }

  if (status.upstream == null) {
    return pushRemote(repo, setUpstream: true);
  }

  if (status.ahead > 0 && status.behind > 0) {
    // Pull with rebase first, then push (matches original "Pull then push" action)
    final pull = await pullRemote(repo, rebase: true);
    if (!pull.ok) return pull;
    final push = await pushRemote(repo);
    if (!push.ok) return push;
    return GitResult.ok(SyncData(
      operation: 'sync',
      remote: 'origin',
      output: '${pull.data!.output}\n${push.data!.output}'.trim(),
    ));
  }

  if (status.ahead > 0) return pushRemote(repo);
  if (status.behind > 0) return pullRemote(repo);
  return fetchRemote(repo);
}

Future<GitResult<String>> cloneRepository(String url, String targetPath) async {
  try {
    final r = await Process.run('git', ['clone', url, targetPath],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
    return GitResult.ok(targetPath);
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

Future<GitResult<String>> initRepository(String path) async {
  try {
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    final r = await _git(path, ['init']);
    if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
    return GitResult.ok(path);
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

Future<GitResult<void>> startInteractiveRebase(
    String repo, List<RebaseTodoEntry> entries) async {
  // Build the todo list content
  final todo =
      entries.map((e) => '${e.action} ${e.commitHash} ${e.subject}').join('\n');

  // Write a temp file for GIT_SEQUENCE_EDITOR to inject
  final tmpFile = File(
      '${Directory.systemTemp.path}/git_rebase_todo_${DateTime.now().millisecondsSinceEpoch}.txt');
  await tmpFile.writeAsString(todo);

  // Use a sequence editor that just copies our pre-built todo
  final sequenceEditor = Platform.isWindows
      ? 'cmd /c copy /y "${tmpFile.path.replaceAll('/', '\\')}"'
      : 'cp "${tmpFile.path}"';

  final ontoRef = entries.isNotEmpty
      ? '${entries.last.commitHash}~1'
      : 'HEAD~${entries.length}';
  final r = await Process.run(
    'git',
    ['rebase', '-i', ontoRef],
    workingDirectory: repo,
    environment: {
      ...Platform.environment,
      'GIT_SEQUENCE_EDITOR': '$sequenceEditor %1',
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  await tmpFile.delete().catchError((_) => tmpFile);

  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(null);
}

Future<GitResult<List<StashEntryData>>> listStashes(String repo) async {
  // Format: index, hash, date, message
  final r = await _git(repo, [
    'stash',
    'list',
    '--format=%gd\x1f%H\x1f%ci\x1f%gs',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final lines = r.stdout
      .toString()
      .trim()
      .split('\n')
      .where((l) => l.isNotEmpty)
      .toList();
  final entries = <StashEntryData>[];
  for (final line in lines) {
    final parts = line.split('\x1f');
    if (parts.length < 4) continue;
    // stash@{0} → 0
    final indexMatch = RegExp(r'\{(\d+)\}').firstMatch(parts[0]);
    final index = indexMatch != null
        ? int.tryParse(indexMatch.group(1)!) ?? 0
        : entries.length;
    entries.add(StashEntryData(
      index: index,
      hash: parts[1],
      createdAt: parts[2],
      message: parts[3],
    ));
  }
  // Enrich with file counts (fast — only stat, no diff content).
  for (var i = 0; i < entries.length && i < 20; i++) {
    final stat = await _git(
        repo, ['stash', 'show', '--stat', 'stash@{${entries[i].index}}']);
    if (stat.exitCode == 0) {
      final statLines = stat.stdout.toString().trim().split('\n');
      // Last line of --stat is the summary: " 3 files changed, ..."
      final summary = statLines.isNotEmpty ? statLines.last : '';
      final countMatch = RegExp(r'(\d+) files? changed').firstMatch(summary);
      final count =
          countMatch != null ? int.tryParse(countMatch.group(1)!) ?? 0 : 0;
      entries[i] = StashEntryData(
        index: entries[i].index,
        hash: entries[i].hash,
        createdAt: entries[i].createdAt,
        message: entries[i].message,
        fileCount: count,
      );
    }
  }
  return GitResult.ok(entries);
}

Future<GitResult<String>> stashPush(
  String repo, {
  String? message,
  List<String>? paths,
  bool keepIndex = false,
}) async {
  final args = <String>['stash', 'push'];
  if (keepIndex) args.add('--keep-index');
  if (message != null && message.trim().isNotEmpty) {
    args.addAll(['-m', message.trim()]);
  }
  if (paths != null && paths.isNotEmpty) {
    args.add('--');
    args.addAll(paths);
  }
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(r.stdout.toString().trim());
}

Future<GitResult<void>> stashPop(String repo, {int index = 0}) async {
  final r = await _git(repo, ['stash', 'pop', 'stash@{$index}']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(null);
}

Future<GitResult<void>> stashApply(String repo, {int index = 0}) async {
  final r = await _git(repo, ['stash', 'apply', 'stash@{$index}']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(null);
}

Future<GitResult<void>> stashDrop(String repo, {int index = 0}) async {
  final r = await _git(repo, ['stash', 'drop', 'stash@{$index}']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(null);
}

Future<GitResult<String>> stashShow(String repo, {int index = 0}) async {
  final r = await _git(repo, ['stash', 'show', '-p', 'stash@{$index}']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(r.stdout.toString());
}

/// List files touched by a stash, with per-file add/del counts.
/// Uses --numstat (tab-separated `adds<TAB>dels<TAB>path`). Binary files
/// render as `-<TAB>-<TAB>path` in numstat.
Future<GitResult<List<StashFileStat>>> stashFiles(
  String repo, {
  int index = 0,
}) async {
  final r = await _git(repo, ['stash', 'show', '--numstat', 'stash@{$index}']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final out = <StashFileStat>[];
  for (final raw in r.stdout.toString().split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final addsRaw = parts[0].trim();
    final delsRaw = parts[1].trim();
    final path = parts.sublist(2).join('\t').trim();
    if (path.isEmpty) continue;
    final binary = addsRaw == '-' || delsRaw == '-';
    out.add(StashFileStat(
      path: path,
      adds: binary ? 0 : (int.tryParse(addsRaw) ?? 0),
      dels: binary ? 0 : (int.tryParse(delsRaw) ?? 0),
      binary: binary,
    ));
  }
  return GitResult.ok(out);
}

/// Parses `git worktree list --porcelain`. Each worktree is a block of
/// key-value lines separated by a blank line. Keys: worktree, HEAD, branch,
/// bare, detached, locked. Blank-only lines terminate the block.
Future<GitResult<List<WorktreeData>>> listWorktrees(String repo) async {
  final r = await _git(repo, ['worktree', 'list', '--porcelain']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final worktrees = <WorktreeData>[];
  String? curPath;
  String? curHead;
  String? curBranch;
  bool curDetached = false;
  bool curLocked = false;

  void flush() {
    if (curPath == null) return;
    worktrees.add(WorktreeData(
      path: curPath!,
      head: curHead ?? '',
      branch: curBranch,
      // First entry from `worktree list` is always the main repo.
      isMain: worktrees.isEmpty,
      isDetached: curDetached,
      isLocked: curLocked,
    ));
    curPath = null;
    curHead = null;
    curBranch = null;
    curDetached = false;
    curLocked = false;
  }

  for (final line in r.stdout.toString().split('\n')) {
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith('worktree ')) {
      curPath = line.substring('worktree '.length).trim();
    } else if (line.startsWith('HEAD ')) {
      curHead = line.substring('HEAD '.length).trim();
    } else if (line.startsWith('branch ')) {
      // refs/heads/main → main
      final ref = line.substring('branch '.length).trim();
      curBranch = ref.startsWith('refs/heads/')
          ? ref.substring('refs/heads/'.length)
          : ref;
    } else if (line == 'detached') {
      curDetached = true;
    } else if (line.startsWith('locked')) {
      curLocked = true;
    }
  }
  flush();

  // Enrich with dirty-file counts per worktree in parallel — each probe
  // is its own `git status` process, so running them concurrently keeps
  // latency flat as desk count grows.
  final statusResults = await Future.wait(worktrees.map((wt) async {
    try {
      final s = await _git(wt.path, ['status', '--porcelain']);
      if (s.exitCode != 0) return 0;
      return s.stdout
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .length;
    } catch (_) {
      return 0;
    }
  }));
  for (var i = 0; i < worktrees.length; i++) {
    final wt = worktrees[i];
    worktrees[i] = WorktreeData(
      path: wt.path,
      head: wt.head,
      branch: wt.branch,
      isMain: wt.isMain,
      isDetached: wt.isDetached,
      isLocked: wt.isLocked,
      dirtyFileCount: statusResults[i],
    );
  }

  return GitResult.ok(worktrees);
}

/// Creates a worktree at the given path for the given branch.
/// Ensures `.manifold/` is in `.git/info/exclude` so app-managed desk
/// directories are never tracked by git.
Future<GitResult<String>> addWorktree(
  String repo,
  String worktreePath,
  String branch, {
  /// When true, creates a new branch from HEAD at the given name alongside
  /// the worktree. Uses `git worktree add -b <branch> <path>`.
  bool createNewBranch = false,
}) async {
  // Append `.manifold/` to .git/info/exclude if not already present.
  try {
    // Resolve .git (handles worktree pointers + submodules).
    final gitDirResult = await Process.run(
      'git',
      ['rev-parse', '--git-common-dir'],
      workingDirectory: repo,
    );
    if (gitDirResult.exitCode == 0) {
      final gitDir = (gitDirResult.stdout as String).trim();
      // Use the path package's robust isAbsolute check — it handles
      // POSIX paths, Windows drive letters (C:\...), AND UNC paths
      // (\\server\share\...) correctly on each platform.
      final absGitDir = p.isAbsolute(gitDir) ? gitDir : p.join(repo, gitDir);
      final excludeFile = File(p.join(absGitDir, 'info', 'exclude'));
      final existing =
          await excludeFile.exists() ? await excludeFile.readAsString() : '';
      if (!existing.split('\n').map((l) => l.trim()).contains('.manifold/')) {
        await excludeFile.writeAsString(
          '${existing.trimRight()}\n.manifold/\n',
        );
      }
    }
  } catch (error) {
    // Non-fatal — worktree creation can proceed even if we couldn't edit
    // exclude — but surface it via diagnostics so a persistent failure
    // (e.g. permissions, read-only FS) gets noticed. If exclude stays
    // unwritten, users could accidentally commit .manifold/ contents.
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'failure',
      command: 'worktree.exclude_write',
      errorCode: 'exclude.write_failed',
      message: error.toString(),
    );
  }

  final args = createNewBranch
      ? ['worktree', 'add', '-b', branch, worktreePath]
      : ['worktree', 'add', worktreePath, branch];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(worktreePath);
}

Future<GitResult<void>> removeWorktree(
  String repo,
  String worktreePath, {
  bool force = false,
}) async {
  final args = ['worktree', 'remove'];
  if (force) args.add('--force');
  args.add(worktreePath);
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(null);
}

Future<GitResult<void>> pruneWorktrees(String repo) async {
  final r = await _git(repo, ['worktree', 'prune']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(null);
}

Future<GitResult<String>> getRepositoryXrayFingerprint(String repo) {
  return computeRepositoryXrayFingerprint(repo, getRepositoryStatus, _git);
}

Future<GitResult<RepositoryXraySnapshotData>> getRepositoryXray(
  String repo, {
  bool forceRefresh = false,
}) {
  return buildRepositoryXraySnapshot(
    repo,
    forceRefresh: forceRefresh,
    statusLoader: getRepositoryStatus,
    probe: _git,
  );
}
