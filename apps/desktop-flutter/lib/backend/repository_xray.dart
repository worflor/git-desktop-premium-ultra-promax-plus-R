import 'dart:async';
import 'dart:io';

import '../diagnostics/diagnostics_state.dart';
import 'dtos.dart';
import 'git_result.dart';

typedef XrayGitProbe = Future<ProcessResult> Function(
  String workingDir,
  List<String> args,
);
typedef XrayStatusLoader = Future<GitResult<RepositoryStatus>> Function(
  String repo,
);

Future<GitResult<String>> computeRepositoryXrayFingerprint(
  String repo,
  XrayStatusLoader statusLoader,
  XrayGitProbe probe,
) async {
  try {
    final statusResult = await statusLoader(repo);
    if (!statusResult.ok || statusResult.data == null) {
      return GitResult.err(statusResult.error ?? 'Unable to read repository status.');
    }
    final headResult = await probe(repo, ['rev-parse', 'HEAD']);
    if (headResult.exitCode != 0) {
      return GitResult.err(headResult.stderr.toString().trim());
    }

    final status = statusResult.data!;
    final headHash = headResult.stdout.toString().trim();
    return GitResult.ok(
      '${repo.replaceAll('\\', '/')}|${status.branch}|$headHash|${status.files.length}',
    );
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

Future<GitResult<RepositoryXraySnapshotData>> buildRepositoryXraySnapshot(
  String repo, {
  bool forceRefresh = false,
  required XrayStatusLoader statusLoader,
  required XrayGitProbe probe,
}) async {
  final stopwatch = Stopwatch()..start();
  final cachedProbe = _SnapshotProbeCache(repo, probe);
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: 'git.repo_xray',
  );

  try {
    final statusResult = await statusLoader(repo);
    if (!statusResult.ok || statusResult.data == null) {
      return GitResult.err(statusResult.error ?? 'Unable to read repository status.');
    }
    final status = statusResult.data!;
    final headResult = await cachedProbe.run(['rev-parse', 'HEAD']);
    if (headResult.exitCode != 0) {
      return GitResult.err(headResult.stderr.toString().trim());
    }
    final headHash = headResult.stdout.toString().trim();
    final fingerprint =
        '${repo.replaceAll('\\', '/')}|${status.branch}|$headHash|${status.files.length}';

    final futures = await Future.wait([
      cachedProbe.run(
        ['for-each-ref', '--format=%(refname)\t%(objecttype)\t%(creatordate:short)\t%(subject)'],
      ),
      cachedProbe.run(['branch', '-a', '-vv']),
      cachedProbe.run(
        ['log', '--all', '--date=short', '--pretty=format:%H\t%h\t%ad\t%an\t%s'],
      ),
      cachedProbe.run(
        [
          'log',
          '--all',
          '--grep=^t3 checkpoint',
          '--invert-grep',
          '--date=short',
          '--pretty=format:%H\t%h\t%ad\t%an\t%s',
        ],
      ),
      cachedProbe.run(['log', '--all', '--name-only', '--format=']),
      cachedProbe.run(
        ['log', '--all', '--grep=^t3 checkpoint', '--invert-grep', '--name-only', '--format='],
      ),
      cachedProbe.run(
        ['log', '--all', '--shortstat', '--date=short', '--pretty=format:__C__%H\t%h\t%ad\t%an\t%s'],
      ),
      cachedProbe.run(
        [
          'log',
          '--all',
          '--grep=^t3 checkpoint',
          '--invert-grep',
          '--shortstat',
          '--date=short',
          '--pretty=format:__C__%H\t%h\t%ad\t%an\t%s',
        ],
      ),
      cachedProbe.run(['log', '--all', '--date=short', '--pretty=format:%ad']),
      cachedProbe.run(
        ['log', '--all', '--grep=^t3 checkpoint', '--invert-grep', '--date=short', '--pretty=format:%ad'],
      ),
      cachedProbe.run(['shortlog', '-sn', '--all', '--no-merges']),
      cachedProbe.run(
        ['shortlog', '-sn', '--all', '--no-merges', '--grep=^t3 checkpoint', '--invert-grep'],
      ),
      cachedProbe.run(['reflog', '-n', '120', '--date=short']),
      cachedProbe.run(['stash', 'list']),
      cachedProbe.run(['notes', 'list']),
      cachedProbe.run(['worktree', 'list', '--porcelain']),
      cachedProbe.run(['log', '--all', '--merges', '--oneline']),
      cachedProbe.run(
        ['log', '--all', '--diff-filter=R', '--summary', '--pretty=format:__C__%H'],
      ),
      cachedProbe.run(['remote', '-v']),
    ]);

    final firstFailure = futures.cast<ProcessResult?>().firstWhere(
          (result) => result != null && result.exitCode != 0,
          orElse: () => null,
        );
    if (firstFailure != null) {
      return GitResult.err(firstFailure.stderr.toString().trim());
    }

    final refs = _parseRefs(futures[0].stdout.toString());
    final rawCommits = _parseCommits(futures[2].stdout.toString());
    final filteredCommits = _parseCommits(futures[3].stdout.toString());
    final rawShortstats = _parseShortstats(futures[6].stdout.toString());
    final filteredShortstats = _parseShortstats(futures[7].stdout.toString());
    final rawDates = _countDateSeries(futures[8].stdout.toString());
    final filteredDates = _countDateSeries(futures[9].stdout.toString());
    final rawAuthors = _parseShortlog(futures[10].stdout.toString());
    final filteredAuthors = _parseShortlog(futures[11].stdout.toString());
    final reflogDates = _countReflogSeries(futures[12].stdout.toString());
    final rawPathTouches = _countPathTouches(futures[4].stdout.toString());
    final filteredPathTouches = _countPathTouches(futures[5].stdout.toString());
    final rawDirTouches = _countDirectoryTouches(futures[4].stdout.toString());
    final filteredDirTouches = _countDirectoryTouches(futures[5].stdout.toString());

    final localBranchCount = futures[1].stdout
        .toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty && !line.contains('remotes/'))
        .length;
    final remoteBranchCount = futures[1].stdout
        .toString()
        .split('\n')
        .where((line) => line.contains('remotes/') && !line.contains('->'))
        .length;
    final tagCount = refs.where((ref) => ref.refName.startsWith('refs/tags/')).length;
    final hiddenRefs = refs
        .where(
          (ref) =>
              !ref.refName.startsWith('refs/heads/') &&
              !ref.refName.startsWith('refs/remotes/') &&
              !ref.refName.startsWith('refs/tags/'),
        )
        .toList();
    final hiddenNamespaces = hiddenRefs
        .map((ref) => _hiddenNamespaceForRef(ref.refName))
        .toSet()
        .toList()
      ..sort();

    final rawHotspots =
        await _buildHotspots(rawPathTouches, rawDirTouches, true, cachedProbe.run);
    final filteredHotspots = await _buildHotspots(
      filteredPathTouches,
      filteredDirTouches,
      false,
      cachedProbe.run,
    );
    final strata = await _buildStrata(filteredDirTouches, cachedProbe.run);
    final rawPivots = _buildPivotCommits(rawShortstats);
    final filteredPivots = _buildPivotCommits(filteredShortstats);
    final migrationPair = _detectMigrationPair(strata);
    final rawCadence = _buildCadence(rawDates, reflogDates);
    final filteredCadence = _buildCadence(filteredDates, reflogDates);

    final signalIntegrity = RepositoryXraySignalIntegrityData(
      rawCommitCount: rawCommits.length,
      filteredCommitCount: filteredCommits.length,
      machineCommitCount: rawCommits.length - filteredCommits.length,
      hiddenRefCount: hiddenRefs.length,
      machineHistoryDominant:
          rawCommits.isNotEmpty && (rawCommits.length - filteredCommits.length) > filteredCommits.length,
      hasHiddenRefs: hiddenRefs.isNotEmpty,
    );

    final refSummary = RepositoryXrayRefSummaryData(
      localBranchCount: localBranchCount,
      remoteBranchCount: remoteBranchCount,
      tagCount: tagCount,
      stashCount: _nonEmptyLineCount(futures[13].stdout.toString()),
      noteCount: _nonEmptyLineCount(futures[14].stdout.toString()),
      worktreeCount: _countWorktrees(futures[15].stdout.toString()),
      mergeCommitCount: _nonEmptyLineCount(futures[16].stdout.toString()),
      renameCommitCount: _countRenameCommits(futures[17].stdout.toString()),
      hiddenNamespaces: hiddenNamespaces,
    );

    final snapshot = RepositoryXraySnapshotData(
      header: RepositoryXrayHeaderData(
        repoPath: repo,
        repoName: _repoNameFromPath(repo),
        branch: status.branch,
        headCommitHash: headHash,
        headShortHash: headHash.length >= 8 ? headHash.substring(0, 8) : headHash,
        dirtyFileCount: status.files.length,
        computedAt: DateTime.now().toIso8601String(),
        fingerprint: fingerprint,
      ),
      signalIntegrity: signalIntegrity,
      refSummary: refSummary,
      cards: _buildCards(
        signalIntegrity: signalIntegrity,
        refSummary: refSummary,
        hotspots: filteredHotspots,
        cadence: filteredCadence,
        strata: strata,
        authors: filteredAuthors,
        migrationPair: migrationPair,
        remoteCount: _remoteCount(futures[18].stdout.toString()),
        usingRawMetrics: false,
      ),
      rawCards: _buildCards(
        signalIntegrity: signalIntegrity,
        refSummary: refSummary,
        hotspots: rawHotspots,
        cadence: rawCadence,
        strata: strata,
        authors: rawAuthors,
        migrationPair: migrationPair,
        remoteCount: _remoteCount(futures[18].stdout.toString()),
        usingRawMetrics: true,
      ),
      hotspots: filteredHotspots,
      rawHotspots: rawHotspots,
      cadence: filteredCadence,
      rawCadence: rawCadence,
      strata: strata,
      pivots: filteredPivots,
      rawPivots: rawPivots,
    );

    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'success',
      command: 'git.repo_xray',
      durationMs: stopwatch.elapsedMicroseconds / 1000,
    );
    unawaited(
      DiagnosticsState.instance.recordCommandLatency(
        command: 'git.repo_xray',
        ok: true,
        scope: 'git',
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
        backendDurationMs: stopwatch.elapsedMicroseconds / 1000,
      ),
    );
    return GitResult.ok(snapshot);
  } catch (error) {
    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'failure',
      command: 'git.repo_xray',
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: 'git.repo_xray_failed',
      message: error.toString(),
    );
    unawaited(
      DiagnosticsState.instance.recordCommandLatency(
        command: 'git.repo_xray',
        ok: false,
        scope: 'git',
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
        backendDurationMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'git.repo_xray_failed',
      ),
    );
    return GitResult.err(error.toString());
  }
}

class _SnapshotProbeCache {
  final String repo;
  final XrayGitProbe probe;
  final Map<String, Future<ProcessResult>> _pending = {};

  _SnapshotProbeCache(this.repo, this.probe);

  Future<ProcessResult> run(List<String> args) {
    final key = args.join('\u0000');
    return _pending.putIfAbsent(key, () => probe(repo, args));
  }
}

class _RefRecord {
  final String refName;

  const _RefRecord(this.refName);
}

class _ShortstatRecord {
  final String hash;
  final String shortHash;
  final String date;
  final String author;
  final String subject;
  final int filesChanged;
  final int insertions;
  final int deletions;

  const _ShortstatRecord({
    required this.hash,
    required this.shortHash,
    required this.date,
    required this.author,
    required this.subject,
    required this.filesChanged,
    required this.insertions,
    required this.deletions,
  });
}

class _MigrationPair {
  final RepositoryXrayStratumData older;
  final RepositoryXrayStratumData newer;

  const _MigrationPair(this.older, this.newer);
}

List<_RefRecord> _parseRefs(String output) {
  return output
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .map((line) => _RefRecord(line.split('\t').first.trim()))
      .toList();
}

List<_ShortstatRecord> _parseShortstats(String output) {
  final records = <_ShortstatRecord>[];
  List<String>? current;
  for (final line in output.split('\n')) {
    if (line.startsWith('__C__')) {
      current = line.substring(5).split('\t');
      continue;
    }
    if (current == null || !line.contains('changed') || current.length < 5) {
      continue;
    }
    records.add(
      _ShortstatRecord(
        hash: current[0].trim(),
        shortHash: current[1].trim(),
        date: current[2].trim(),
        author: current[3].trim(),
        subject: current.sublist(4).join('\t').trim(),
        filesChanged: int.tryParse(RegExp(r'(\d+) files? changed').firstMatch(line)?.group(1) ?? '') ?? 0,
        insertions: int.tryParse(RegExp(r'(\d+) insertions?\(\+\)').firstMatch(line)?.group(1) ?? '') ?? 0,
        deletions: int.tryParse(RegExp(r'(\d+) deletions?\(-\)').firstMatch(line)?.group(1) ?? '') ?? 0,
      ),
    );
  }
  return records;
}

List<String> _parseCommits(String output) {
  return output.split('\n').where((line) => line.trim().isNotEmpty).toList();
}

Map<String, int> _countDateSeries(String output) {
  final counts = <String, int>{};
  for (final date in output.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty)) {
    counts.update(date, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

Map<String, int> _countReflogSeries(String output) {
  final counts = <String, int>{};
  for (final line in output.split('\n')) {
    final match = RegExp(r'HEAD@\{(\d{4}-\d{2}-\d{2})').firstMatch(line);
    if (match != null) {
      counts.update(match.group(1)!, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

Map<String, int> _parseShortlog(String output) {
  final counts = <String, int>{};
  for (final line in output.split('\n')) {
    final match = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
    if (match != null) {
      counts[match.group(2)!.trim()] = int.tryParse(match.group(1)!) ?? 0;
    }
  }
  return counts;
}

Map<String, int> _countPathTouches(String output) {
  final counts = <String, int>{};
  for (final path in output.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty)) {
    counts.update(path, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

Map<String, int> _countDirectoryTouches(String output) {
  final counts = <String, int>{};
  for (final path in output.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty)) {
    final prefix = _directoryPrefixForPath(path.replaceAll('\\', '/'));
    counts.update(prefix, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

Future<List<RepositoryXrayHotspotData>> _buildHotspots(
  Map<String, int> pathTouches,
  Map<String, int> dirTouches,
  bool includeMachineHistory,
  Future<ProcessResult> Function(List<String> args) probe,
) async {
  final files = pathTouches.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final dirs = dirTouches.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final hotspotFutures = [
    for (final entry in files.take(4))
      _enrichHotspot(
        entry.key,
        'file',
        entry.value,
        includeMachineHistory,
        probe,
      ),
    for (final entry in dirs.take(4))
      _enrichHotspot(
        entry.key,
        'directory',
        entry.value,
        includeMachineHistory,
        probe,
      ),
  ];
  final hotspots = await Future.wait(hotspotFutures);
  hotspots.sort((a, b) => b.touchCount.compareTo(a.touchCount));
  return hotspots;
}

Future<RepositoryXrayHotspotData> _enrichHotspot(
  String path,
  String kind,
  int touchCount,
  bool includeMachineHistory,
  Future<ProcessResult> Function(List<String> args) probe,
) async {
  final authorArgs = ['log', '--format=%an'];
  final recentArgs = ['log', '-n', '1', '--date=short', '--format=%H\t%h\t%ad'];
  if (!includeMachineHistory) {
    authorArgs.addAll(['--grep=^t3 checkpoint', '--invert-grep']);
    recentArgs.addAll(['--grep=^t3 checkpoint', '--invert-grep']);
  }

  final results = await Future.wait([
    probe([...authorArgs, '--', path]),
    probe([...recentArgs, '--', path]),
  ]);
  final authorsResult = results[0];
  final recentResult = results[1];
  final ownerCount = authorsResult.stdout
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toSet()
      .length;
  final recentParts = recentResult.stdout.toString().trim().split('\t');

  return RepositoryXrayHotspotData(
    kind: kind,
    path: path,
    touchCount: touchCount,
    ownerCount: ownerCount,
    lastTouchedAt: recentParts.length > 2 ? recentParts[2] : '',
    latestCommitHash: recentParts.isNotEmpty && recentParts[0].isNotEmpty ? recentParts[0] : null,
    latestShortHash: recentParts.length > 1 && recentParts[1].isNotEmpty ? recentParts[1] : null,
  );
}

Future<List<RepositoryXrayStratumData>> _buildStrata(
  Map<String, int> dirTouches,
  Future<ProcessResult> Function(List<String> args) probe,
) async {
  final entries = dirTouches.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Future.wait(
    [
      for (final entry in entries.take(4))
        () async {
          final results = await Future.wait([
            probe(['log', '--grep=^t3 checkpoint', '--invert-grep', '--format=%an', '--', entry.key]),
            probe([
              'log',
              '-n',
              '1',
              '--grep=^t3 checkpoint',
              '--invert-grep',
              '--date=short',
              '--format=%ad',
              '--',
              entry.key,
            ]),
          ]);
          final authorsResult = results[0];
          final recentResult = results[1];
          return RepositoryXrayStratumData(
            id: entry.key,
            label: _stratumLabelForPrefix(entry.key),
            pathPrefix: entry.key,
            touchCount: entry.value,
            ownerCount: authorsResult.stdout
                .toString()
                .split('\n')
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty)
                .toSet()
                .length,
            lastTouchedAt: recentResult.stdout.toString().trim(),
            summary: 'Touched ${entry.value} times in filtered history.',
          );
        }(),
    ],
  );
}

List<RepositoryXrayPivotCommitData> _buildPivotCommits(List<_ShortstatRecord> records) {
  final sorted = [...records]
    ..sort((a, b) {
      final byFiles = b.filesChanged.compareTo(a.filesChanged);
      if (byFiles != 0) {
        return byFiles;
      }
      return (b.insertions + b.deletions).compareTo(a.insertions + a.deletions);
    });

  return sorted.take(6).map((record) {
    return RepositoryXrayPivotCommitData(
      commitHash: record.hash,
      shortHash: record.shortHash,
      authoredAt: record.date,
      authorName: record.author,
      subject: record.subject,
      filesChanged: record.filesChanged,
      insertions: record.insertions,
      deletions: record.deletions,
    );
  }).toList();
}

List<RepositoryXrayCadenceData> _buildCadence(
  Map<String, int> commitDates,
  Map<String, int> reflogDates,
) {
  final cadence = <RepositoryXrayCadenceData>[];
  final bursts = commitDates.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in bursts.take(3)) {
    cadence.add(
      RepositoryXrayCadenceData(
        kind: 'burst',
        label: entry.key,
        count: entry.value,
        detail: '${entry.value} commits landed on ${entry.key}.',
      ),
    );
  }

  final sortedDates = commitDates.keys.toList()..sort();
  for (var i = 1; i < sortedDates.length; i++) {
    final previous = DateTime.tryParse(sortedDates[i - 1]);
    final current = DateTime.tryParse(sortedDates[i]);
    if (previous == null || current == null) {
      continue;
    }
    final gap = current.difference(previous).inDays;
    if (gap > 1) {
      cadence.add(
        RepositoryXrayCadenceData(
          kind: 'gap',
          label: '${sortedDates[i - 1]} -> ${sortedDates[i]}',
          count: gap,
          detail: '$gap day gap between commit bursts.',
        ),
      );
    }
    if (cadence.where((item) => item.kind == 'gap').length >= 2) {
      break;
    }
  }

  final reflogBursts = reflogDates.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  if (reflogBursts.isNotEmpty) {
    cadence.add(
      RepositoryXrayCadenceData(
        kind: 'reflog',
        label: reflogBursts.first.key,
        count: reflogBursts.first.value,
        detail: '${reflogBursts.first.value} local session events on ${reflogBursts.first.key}.',
      ),
    );
  }
  return cadence;
}

List<RepositoryXrayCardData> _buildCards({
  required RepositoryXraySignalIntegrityData signalIntegrity,
  required RepositoryXrayRefSummaryData refSummary,
  required List<RepositoryXrayHotspotData> hotspots,
  required List<RepositoryXrayCadenceData> cadence,
  required List<RepositoryXrayStratumData> strata,
  required Map<String, int> authors,
  required _MigrationPair? migrationPair,
  required int remoteCount,
  required bool usingRawMetrics,
}) {
  final cards = <RepositoryXrayCardData>[];
  final topHotspot = hotspots.isEmpty ? null : hotspots.first;
  final totalTouches = hotspots.fold<int>(0, (sum, hotspot) => sum + hotspot.touchCount);
  final topShare = topHotspot == null || totalTouches == 0 ? 0.0 : topHotspot.touchCount / totalTouches;
  final peakBurst = cadence.where((item) => item.kind == 'burst').fold<int>(0, (best, item) => item.count > best ? item.count : best);
  final peakReflog = cadence.where((item) => item.kind == 'reflog').fold<int>(0, (best, item) => item.count > best ? item.count : best);

  if (signalIntegrity.hasHiddenRefs) {
    cards.add(
      RepositoryXrayCardData(
        id: 'hidden-refs',
        title: 'Hidden Git namespaces',
        claim: '${signalIntegrity.hiddenRefCount} refs live outside normal branch/tag space.',
        verdict: 'hard-fact',
        confidence: 'high',
        evidence: [
          RepositoryXrayEvidenceData(
            label: 'Hidden refs',
            detail: '${signalIntegrity.hiddenRefCount} refs outside heads/remotes/tags.',
            kind: 'ref',
            count: signalIntegrity.hiddenRefCount,
          ),
          RepositoryXrayEvidenceData(
            label: 'Namespaces',
            detail: refSummary.hiddenNamespaces.join(', '),
            kind: 'ref',
          ),
        ],
      ),
    );
  }

  if (signalIntegrity.machineHistoryDominant) {
    cards.add(
      RepositoryXrayCardData(
        id: 'machine-history',
        title: 'Machine history dominates raw metrics',
        claim: 'Checkpoint-style commits materially distort naive history metrics.',
        verdict: 'strong-pattern',
        confidence: 'high',
        evidence: [
          RepositoryXrayEvidenceData(
            label: 'Raw vs filtered',
            detail: '${signalIntegrity.rawCommitCount} raw commits vs ${signalIntegrity.filteredCommitCount} filtered commits.',
            kind: 'history',
          ),
          RepositoryXrayEvidenceData(
            label: 'Machine commits',
            detail: '${signalIntegrity.machineCommitCount} commits matched machine/session patterns.',
            kind: 'history',
            count: signalIntegrity.machineCommitCount,
          ),
        ],
      ),
    );
  }

  if (migrationPair != null) {
    cards.add(
      RepositoryXrayCardData(
        id: 'migration',
        title: 'Architecture migration visible',
        claim:
            'History shifts from `${migrationPair.older.pathPrefix}` to `${migrationPair.newer.pathPrefix}`, suggesting a stack or surface transition.',
        verdict: 'strong-pattern',
        confidence: 'high',
        evidence: [
          RepositoryXrayEvidenceData(
            label: migrationPair.older.pathPrefix,
            detail: '${migrationPair.older.touchCount} touches, last active ${migrationPair.older.lastTouchedAt}.',
            kind: 'path',
            path: migrationPair.older.pathPrefix,
          ),
          RepositoryXrayEvidenceData(
            label: migrationPair.newer.pathPrefix,
            detail: '${migrationPair.newer.touchCount} touches, last active ${migrationPair.newer.lastTouchedAt}.',
            kind: 'path',
            path: migrationPair.newer.pathPrefix,
          ),
        ],
      ),
    );
  }

  if (topHotspot != null && topHotspot.ownerCount <= 1 && topHotspot.touchCount >= 8) {
    cards.add(
      RepositoryXrayCardData(
        id: 'single-owner-hotspot',
        title: 'Single-owner hotspot',
        claim:
            '`${topHotspot.path}` is a heavily touched ${topHotspot.kind} with one distinct visible author.',
        verdict: 'strong-pattern',
        confidence: 'high',
        evidence: [
          RepositoryXrayEvidenceData(
            label: 'Touch count',
            detail: '${topHotspot.touchCount} touches in ${usingRawMetrics ? 'raw' : 'filtered'} history.',
            kind: 'path',
            path: topHotspot.path,
          ),
          RepositoryXrayEvidenceData(
            label: 'Owner count',
            detail: '${topHotspot.ownerCount} distinct authors.',
            kind: 'author',
            count: topHotspot.ownerCount,
          ),
        ],
        primaryPath: topHotspot.path,
        primaryCommitHash: topHotspot.latestCommitHash,
      ),
    );
  }

  if (refSummary.tagCount == 0) {
    cards.add(
      RepositoryXrayCardData(
        id: 'no-tags',
        title: 'No formal release/tag trail',
        claim: 'Git tags are not being used as a visible release or milestone layer.',
        verdict: 'hard-fact',
        confidence: 'high',
        evidence: [
          RepositoryXrayEvidenceData(
            label: 'Tag count',
            detail: '0 tags found.',
            kind: 'ref',
          ),
          RepositoryXrayEvidenceData(
            label: 'Remote endpoints',
            detail: '$remoteCount remote endpoints configured.',
            kind: 'ref',
          ),
        ],
      ),
    );
  }

  if (peakBurst >= 8) {
    cards.add(
      RepositoryXrayCardData(
        id: 'bursty-cadence',
        title: 'Bursty development cadence',
        claim: 'Work lands in concentrated bursts rather than a flat daily rhythm.',
        verdict: 'strong-pattern',
        confidence: 'medium',
        evidence: cadence
            .where((item) => item.kind == 'burst')
            .take(2)
            .map(
              (item) => RepositoryXrayEvidenceData(
                label: item.label,
                detail: item.detail,
                kind: 'cadence',
                count: item.count,
              ),
            )
            .toList(),
      ),
    );
  }

  cards.add(
    RepositoryXrayCardData(
      id: 'branch-model',
      title: refSummary.localBranchCount + refSummary.remoteBranchCount <= 3
          ? 'Simple branch model'
          : 'Branch model has surface area',
      claim: refSummary.localBranchCount + refSummary.remoteBranchCount <= 3
          ? 'The visible branch model is narrow.'
          : 'The repository has enough branch surface to reward branch-aware navigation.',
      verdict: 'hard-fact',
      confidence: 'high',
      evidence: [
        RepositoryXrayEvidenceData(
          label: 'Local branches',
          detail: '${refSummary.localBranchCount} local branches.',
          kind: 'ref',
        ),
        RepositoryXrayEvidenceData(
          label: 'Remote branches',
          detail: '${refSummary.remoteBranchCount} remote branches.',
          kind: 'ref',
        ),
      ],
    ),
  );

  if (peakReflog >= 15) {
    cards.add(
      RepositoryXrayCardData(
        id: 'reflog-intense',
        title: 'Intense local editing sessions',
        claim: 'Reflog volume suggests concentrated local iteration beyond published commits.',
        verdict: 'strong-pattern',
        confidence: 'medium',
        evidence: [
          RepositoryXrayEvidenceData(
            label: 'Peak reflog day',
            detail: cadence.firstWhere((item) => item.kind == 'reflog').detail,
            kind: 'reflog',
            count: peakReflog,
          ),
        ],
      ),
    );
  }

  if (topHotspot != null && topShare >= 0.22) {
    cards.add(
      RepositoryXrayCardData(
        id: 'narrow-hotspot',
        title: 'Hotspot concentration is narrow',
        claim: 'A small set of files and directories absorbs a disproportionate share of changes.',
        verdict: 'strong-pattern',
        confidence: 'medium',
        evidence: [
          RepositoryXrayEvidenceData(
            label: 'Top hotspot',
            detail: '${topHotspot.path} accounts for ${(topShare * 100).toStringAsFixed(0)}% of the visible hotspot set.',
            kind: 'path',
            path: topHotspot.path,
          ),
          RepositoryXrayEvidenceData(
            label: 'Visible authors',
            detail: '${authors.length} authors in this history slice.',
            kind: 'author',
          ),
        ],
        primaryPath: topHotspot.path,
        primaryCommitHash: topHotspot.latestCommitHash,
      ),
    );
  }

  return cards.take(8).toList();
}

_MigrationPair? _detectMigrationPair(List<RepositoryXrayStratumData> strata) {
  for (final older in strata) {
    for (final newer in strata) {
      if (older.pathPrefix == newer.pathPrefix) {
        continue;
      }
      if (older.pathPrefix.split('/').first != newer.pathPrefix.split('/').first) {
        continue;
      }
      final olderDate = DateTime.tryParse(older.lastTouchedAt);
      final newerDate = DateTime.tryParse(newer.lastTouchedAt);
      if (olderDate == null || newerDate == null) {
        continue;
      }
      if (olderDate.isBefore(newerDate) && older.touchCount >= 20 && newer.touchCount >= 20) {
        return _MigrationPair(older, newer);
      }
    }
  }
  return null;
}

String _repoNameFromPath(String repoPath) {
  final parts = repoPath
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.isEmpty ? repoPath : parts.last;
}

String _hiddenNamespaceForRef(String refName) {
  final match = RegExp(r'^refs/([^/]+)/').firstMatch(refName);
  return match?.group(1) ?? 'other';
}

String _directoryPrefixForPath(String path) {
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length >= 2) {
    return '${parts[0]}/${parts[1]}';
  }
  if (parts.length == 1) {
    return parts.first;
  }
  return '[root]';
}

String _stratumLabelForPrefix(String prefix) {
  if (prefix.contains('flutter')) {
    return 'Current surface';
  }
  if (prefix.contains('desktop')) {
    return 'Architecture stratum';
  }
  return 'Repo zone';
}

int _nonEmptyLineCount(String output) {
  return output.split('\n').where((line) => line.trim().isNotEmpty).length;
}

int _countWorktrees(String output) {
  return output.split('\n').where((line) => line.trim().startsWith('worktree ')).length;
}

int _countRenameCommits(String output) {
  final commits = <String>{};
  String? currentCommit;
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('__C__')) {
      currentCommit = line.substring(5).trim();
      continue;
    }
    if (line.startsWith('rename ') && currentCommit != null) {
      commits.add(currentCommit);
    }
  }
  return commits.length;
}

int _remoteCount(String output) {
  return output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.split(RegExp(r'\s+')).first)
      .toSet()
      .length;
}
