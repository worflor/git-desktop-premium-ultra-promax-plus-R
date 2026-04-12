import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'repository_xray.dart';
import 'dtos.dart';
import 'git_result.dart';
import '../diagnostics/diagnostics_state.dart';

// ── Result type ──────────────────────────────────────────────────────────────


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

// ── Commit detail ──────────────────────────────────────────────────────────

Future<GitResult<CommitDetailData>> getCommitDetail(
    String repo, String hash) async {
  final r = await _git(repo, [
    'show',
    '--stat',
    '--format=%H%n%h%n%s%n%b%n---END-META---%n%aN%n%aE%n%aI',
    hash
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

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

  // parse stat block
  final statLines = afterMeta.skip(3).where((l) => l.contains('|')).toList();
  final files = <CommitFileStatData>[];
  for (final line in statLines) {
    final parts = line.split('|');
    if (parts.length < 2) continue;
    final filePath = parts[0].trim();
    final statPart = parts[1].trim();
    final adds = '+'.allMatches(statPart).length;
    final dels = '-'.allMatches(statPart).length;
    files.add(
        CommitFileStatData(path: filePath, additions: adds, deletions: dels));
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
