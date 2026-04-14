import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'repository_xray.dart';
import 'dtos.dart';
import 'git_result.dart';
import '../diagnostics/diagnostics_state.dart';

// ── Result type ──────────────────────────────────────────────────────────────


// ── Diff-header path extraction ─────────────────────────────────────────────
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
final RegExp _kDiffHeaderUnquotedLine =
    RegExp(r'^diff --git a/.+ b/(.+)$');
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

// ── Git runner ───────────────────────────────────────────────────────────────

Future<ProcessResult> _git(String workingDir, List<String> args) async {
  final commandLabel = args.isEmpty ? 'git' : 'git.${args.first}';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: commandLabel,
  );
  try {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: workingDir,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
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

// ── Repository ───────────────────────────────────────────────────────────────

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
  try {
    final branch = await _git(repo, ['rev-parse', '--abbrev-ref', 'HEAD']);
    if (branch.exitCode != 0) {
      return GitResult.err(branch.stderr.toString().trim());
    }
    final branchName = branch.stdout.toString().trim();

    final status = await _git(repo, ['status', '--porcelain=v1', '-u']);
    if (status.exitCode != 0) {
      return GitResult.err(status.stderr.toString().trim());
    }

    final files = <RepositoryStatusFile>[];
    for (final line in status.stdout.toString().split('\n')) {
      if (line.length < 3) continue;
      final staged = line[0];
      final unstaged = line[1];
      final path = line.substring(3).trim();
      if (path.isEmpty) continue;
      files.add(RepositoryStatusFile(
          path: path,
          staged: staged == ' ' ? '' : staged,
          unstaged: unstaged == ' ' ? '' : unstaged));
    }

    int ahead = 0, behind = 0;
    final upstream = await _git(
        repo, ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}']);
    String? upstreamName;
    if (upstream.exitCode == 0) {
      upstreamName = upstream.stdout.toString().trim();
      final ab = await _git(repo,
          ['rev-list', '--left-right', '--count', '$upstreamName...HEAD']);
      if (ab.exitCode == 0) {
        final parts = ab.stdout.toString().trim().split('\t');
        if (parts.length == 2) {
          behind = int.tryParse(parts[0]) ?? 0;
          ahead = int.tryParse(parts[1]) ?? 0;
        }
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

/// Format string used by both listCommitHistory and listFileHistory.
/// Shape: hash, shortHash, parents, refs, subject, author, email, date.
/// Keep in sync with `_parseCommitLogLines` below.
const String _kCommitLogFormat =
    '--format=%H%n%h%n%P%n%D%n%s%n%aN%n%aE%n%aI';

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
    final parents = lines[i + 2]
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
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
  final baseArgs = ['log', '--format=>>>%H', '-n', '$limit'];
  if (branch != null) baseArgs.add(branch);

  final results = await Future.wait([
    _git(repo, [...baseArgs, '--numstat']),
    _git(repo, [...baseArgs, '--name-status']),
  ]);

  if (results[0].exitCode != 0) {
    return GitResult.err(results[0].stderr.toString().trim());
  }

  // Parse numstat output: sentinel line ">>>hash" then tab-separated file rows
  final numstatByHash = <String, List<_BulkFileStat>>{};
  String? cur;
  for (final line in results[0].stdout.toString().split('\n')) {
    if (line.startsWith('>>>')) {
      cur = line.substring(3).trim();
      numstatByHash[cur] = [];
    } else if (cur != null) {
      final parts = line.trim().split('\t');
      if (parts.length >= 3) {
        final adds = int.tryParse(parts[0]) ?? 0;
        final dels = int.tryParse(parts[1]) ?? 0;
        final path = parts[2].trim();
        if (path.isNotEmpty) numstatByHash[cur]!.add(_BulkFileStat(path, adds, dels));
      }
    }
  }

  // Parse name-status output: sentinel line ">>>hash" then "X\tpath" rows
  final changeTypesByHash = <String, Map<String, String>>{};
  cur = null;
  if (results[1].exitCode == 0) {
    for (final line in results[1].stdout.toString().split('\n')) {
      if (line.startsWith('>>>')) {
        cur = line.substring(3).trim();
        changeTypesByHash[cur] = {};
      } else if (cur != null) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final tabIdx = trimmed.indexOf('\t');
        if (tabIdx < 0) continue;
        final type = trimmed.substring(0, 1);
        final rest = trimmed.substring(tabIdx + 1);
        // Renames: "old\tnew" — use new path
        final path = rest.contains('\t') ? rest.split('\t').last : rest;
        changeTypesByHash[cur]![path.trim()] = type;
      }
    }
  }

  // Build CommitDetailData from existing metadata + fetched file stats
  final out = <String, CommitDetailData>{};
  for (final c in commits) {
    final stats = numstatByHash[c.commitHash] ?? [];
    final types = changeTypesByHash[c.commitHash] ?? {};
    final files = stats.map((s) => CommitFileStatData(
          path: s.path,
          additions: s.additions,
          deletions: s.deletions,
          changeType: types[s.path] ?? 'M',
        )).toList();
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

// ── Paper Trail (file history) ──────────────────────────────────────────────

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
    if (hash.isEmpty) { i++; continue; }
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

// ── Commit detail ──────────────────────────────────────────────────────────

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
    _git(repo,
        ['diff-tree', '--no-commit-id', '-r', '--name-status', hash]),
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
    (file) => !_isUntrackedMarker(file.staged) && file.staged.trim().isNotEmpty,
  );
  final hasTrackedUnstaged = files.any(
    (file) =>
        !_isUntrackedMarker(file.unstaged) && file.unstaged.trim().isNotEmpty,
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

bool _isUntrackedFile(RepositoryStatusFile file) =>
    _isUntrackedMarker(file.staged) || _isUntrackedMarker(file.unstaged);

bool _isUntrackedMarker(String code) => code.trim() == '?';

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

/// One scan, two signals: who has been touching this code AND how hot
/// each file is right now (exponentially-decayed commit density).
/// Used by the PR detail surface for the PEOPLE section + per-file
/// thermal glow. Pure local git; transferable to any host.
///
/// Cost: O(paths) git log invocations, each capped at [maxPerFile]
/// commits. Cheap for typical PR file lists.
Future<GitResult<FileSignals>> scanFileSignals(
  String repo,
  List<String> paths, {
  int maxPerFile = 20,
  int sinceDays = 365,
  double thermalTauDays = 14,
}) async {
  if (paths.isEmpty) return const GitResult.ok(FileSignals.empty);
  final since = '$sinceDays.days.ago';
  final counts = <String, int>{};
  final heatByPath = <String, double>{};
  final now = DateTime.now();
  for (final p in paths) {
    final r = await _git(repo, [
      'log',
      '--no-merges',
      // Author email + commit timestamp (epoch seconds).
      '--format=%ae|%at',
      '-n',
      '$maxPerFile',
      '--since',
      since,
      '--',
      p,
    ]);
    if (r.exitCode != 0) continue;
    double heat = 0;
    for (final raw in (r.stdout as String).split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final pipe = line.indexOf('|');
      final email = pipe > 0 ? line.substring(0, pipe) : line;
      final tsStr = pipe > 0 ? line.substring(pipe + 1) : '';
      if (email.isNotEmpty) {
        counts[email] = (counts[email] ?? 0) + 1;
      }
      // Exponential decay: each commit contributes exp(-Δd/τ) to the
      // file's heat. Recent commits dominate; old ones fade. Heat is
      // capped at 1.0 for visualization (rare to exceed even in
      // active files).
      final ts = int.tryParse(tsStr);
      if (ts != null) {
        final commitAt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        final ageDays = now.difference(commitAt).inHours / 24.0;
        heat += math.exp(-ageDays / thermalTauDays);
      }
    }
    if (heat > 0) {
      heatByPath[p] = heat.clamp(0.0, 1.0).toDouble();
    }
  }
  final authors = counts.entries
      .map((e) => (email: e.key, commits: e.value))
      .toList()
    ..sort((a, b) => b.commits.compareTo(a.commits));
  return GitResult.ok(FileSignals(authors: authors, heatByPath: heatByPath));
}


Future<GitResult<void>> stagePaths(String repo, List<String> paths) async {
  final r = await _git(repo, ['add', '--', ...paths]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> unstagePaths(String repo, List<String> paths) async {
  final r = await _git(repo, ['restore', '--staged', '--', ...paths]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Discard all changes (staged AND unstaged) for a single file, matching
/// the GitHub Desktop "Discard changes" behaviour:
///
///   * **Untracked** (`?`) — nothing to restore from git's side; just
///     remove the file from disk. Git never knew about it.
///   * **Newly added in the index** (`A`, not yet in HEAD) — `git
///     checkout HEAD --` would error with "did not match any file(s)
///     known to git" because the path doesn't exist there. Unstage with
///     `git rm --cached` first, then delete the working copy.
///   * **Anything else** (modified, deleted, renamed, copied, conflict)
///     — `git checkout HEAD -- <path>` resets the path to its HEAD
///     state in one shot, wiping both staged and unstaged changes.
///
/// Irreversible. Caller is expected to confirm before invoking.
Future<GitResult<void>> discardFile(
  String repo,
  RepositoryStatusFile file,
) async {
  final isUntracked = file.staged.isEmpty && file.unstaged == '?';
  if (isUntracked) {
    return _deleteFromDisk(repo, file.path);
  }
  if (file.staged == 'A') {
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
    final needsLeadingNewline =
        existing.isNotEmpty && !existing.endsWith('\n');
    final next =
        '$existing${needsLeadingNewline ? '\n' : ''}$trimmedPattern\n';
    await f.writeAsString(next);
    return const GitResult.ok(null);
  } catch (e) {
    return GitResult.err('Failed to update .gitignore: $e');
  }
}

/// Pipes a unified diff to `git apply`. Used for line-level staging AND
/// for the patch-loop (external .patch files).
///
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
    final process =
        await Process.start('git', args, workingDirectory: repo);
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
    if (!ok) return GitResult.err(stderrText.isEmpty ? 'git apply exit $exit' : stderrText);
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
///
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

// ── Stash (Filing Cabinet) ──────────────────────────────────────────────────

Future<GitResult<List<StashEntryData>>> listStashes(String repo) async {
  // Format: index, hash, date, message
  final r = await _git(repo, [
    'stash', 'list',
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
    final index = indexMatch != null ? int.tryParse(indexMatch.group(1)!) ?? 0 : entries.length;
    entries.add(StashEntryData(
      index: index,
      hash: parts[1],
      createdAt: parts[2],
      message: parts[3],
    ));
  }
  // Enrich with file counts (fast — only stat, no diff content).
  for (var i = 0; i < entries.length && i < 20; i++) {
    final stat = await _git(repo, ['stash', 'show', '--stat', 'stash@{${entries[i].index}}']);
    if (stat.exitCode == 0) {
      final statLines = stat.stdout.toString().trim().split('\n');
      // Last line of --stat is the summary: " 3 files changed, ..."
      final summary = statLines.isNotEmpty ? statLines.last : '';
      final countMatch = RegExp(r'(\d+) files? changed').firstMatch(summary);
      final count = countMatch != null ? int.tryParse(countMatch.group(1)!) ?? 0 : 0;
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
  final r = await _git(
      repo, ['stash', 'show', '--numstat', 'stash@{$index}']);
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

// ── Parallel Desks (worktrees) ──────────────────────────────────────────────

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
      if (!existing
          .split('\n')
          .map((l) => l.trim())
          .contains('.manifold/')) {
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

// ── X-Ray ──────────────────────────────────────────────────────────────────

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
