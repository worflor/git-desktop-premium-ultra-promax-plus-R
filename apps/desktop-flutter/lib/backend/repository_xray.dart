import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../diagnostics/diagnostics_state.dart';
import 'dtos.dart';
import 'engram_fit.dart';
import 'git_result.dart';
import 'logos_core.dart' show SpectralBasis, SpectralHeat, SpectralThermo;
import 'logos_git.dart';
import 'logos_git_resolver.dart' show resolveLogosGit;
import 'logos_spectrogeometry.dart' show SpectroGeometry;

typedef XrayGitProbe = Future<ProcessResult> Function(
  String workingDir,
  List<String> args,
);
typedef XrayStatusLoader = Future<GitResult<RepositoryStatus>> Function(
  String repo,
);

/// Sentinel token that git-log format strings in [buildRepositoryXraySnapshot]
/// inject at the start of each commit-header line.  Every `--name-status` or
/// `--shortstat` git-log call that feeds one of the parsers below MUST prefix
/// its `--format=` or `--pretty=format:` value with this constant so parsers
/// can locate commit boundaries.  Using the constant in both call sites and
/// parser guards makes the coupling explicit and keeps substring offsets
/// correct if the token is ever changed.
const _kCommitMarker = '__C__';

Future<GitResult<String>> computeRepositoryXrayFingerprint(
  String repo,
  XrayStatusLoader statusLoader,
  XrayGitProbe probe,
) async {
  try {
    final statusResult = await statusLoader(repo);
    if (!statusResult.ok || statusResult.data == null) {
      return GitResult.err(
          statusResult.error ?? 'Unable to read repository status.');
    }
    final headResult = await probe(repo, ['rev-parse', 'HEAD']);
    if (headResult.exitCode != 0) {
      return GitResult.err(headResult.stderr.toString().trim());
    }

    final status = statusResult.data!;
    final headHash = headResult.stdout.toString().trim();
    return GitResult.ok(_fingerprintFor(
      repo: repo,
      branch: status.branch,
      headHash: headHash,
      files: status.files,
    ));
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

/// Central fingerprint builder. Includes both total file count AND a
/// separate staged-count field so the cache invalidates when the user
/// stages / unstages files without changing HEAD. Previously a user
/// staging three files and running x-ray would get the pre-staging
/// snapshot because only HEAD was in the key.
String _fingerprintFor({
  required String repo,
  required String branch,
  required String headHash,
  required List<RepositoryStatusFile> files,
}) {
  var stagedCount = 0;
  var dirtyCount = 0;
  for (final f in files) {
    if (f.hasStagedChange) stagedCount++;
    if (f.hasUnstagedChange) dirtyCount++;
  }
  return '${repo.replaceAll('\\', '/')}|$branch|$headHash'
      '|${files.length}|s$stagedCount|u$dirtyCount';
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

  // Opportunistic Logos engine resolve. Runs in parallel with the git
  // log/refs fan-out below — if it's already cached (HEAD unchanged),
  // we get the spectral basis essentially for free; if it's a cold
  // build, the engine ships back before/after the git calls and we
  // still get the win. Failures (non-repo paths, test fixtures,
  // unreachable .git) return null and every spectral path falls back
  // to the legacy O(|commit|²) pair walk — nothing blocks or throws.
  final engineFuture = _tryResolveEngine(repo);

  try {
    final statusResult = await statusLoader(repo);
    if (!statusResult.ok || statusResult.data == null) {
      return GitResult.err(
          statusResult.error ?? 'Unable to read repository status.');
    }
    final status = statusResult.data!;
    final headResult = await cachedProbe.run(['rev-parse', 'HEAD']);
    if (headResult.exitCode != 0) {
      return GitResult.err(headResult.stderr.toString().trim());
    }
    final headHash = headResult.stdout.toString().trim();
    final fingerprint = _fingerprintFor(
      repo: repo,
      branch: status.branch,
      headHash: headHash,
      files: status.files,
    );

    final futures = await Future.wait([
      cachedProbe.run(
        [
          'for-each-ref',
          '--format=%(refname)\t%(objecttype)\t%(creatordate:short)\t%(subject)'
        ],
      ),
      cachedProbe.run(['branch', '-a', '-vv']),
      cachedProbe.run(
        [
          'log',
          '--all',
          '--date=short',
          '--pretty=format:%H\t%h\t%ad\t%an\t%s'
        ],
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
      // Per-commit file lists with full header metadata. The marker
      // line `__C__<hash>\t<short>\t<date>\t<author>` packs enough
      // identity for downstream consumers (co-change, alive-mass age
      // decay, hotspot/stratum enrichment) to work entirely off this
      // one pass — without it, each hotspot/stratum path would need
      // its own `git log -- <path>` subprocess. Each block starts
      // with the marker and is followed by per-file status lines.
      //
      // `--name-status -M95` emits `<status>\t<path>` per file, with
      // renames shown as `R<score>\told\tnew` when similarity ≥ 95%.
      // The parser threads those events through a union-find so
      // pre-rename history attributes to the HEAD-side name — same
      // fidelity as `git log --follow` without the per-path spawn.
      // 95% is the conservative threshold: only rename-with-minor-
      // edit counts, no false positives from coincidentally-similar
      // files.
      cachedProbe.run([
        'log',
        '--all',
        '--name-status',
        '-M95',
        '--date=short',
        '--format=${_kCommitMarker}%H\t%h\t%ad\t%an'
      ]),
      cachedProbe.run([
        'log',
        '--all',
        '--grep=^t3 checkpoint',
        '--invert-grep',
        '--name-status',
        '-M95',
        '--date=short',
        '--format=${_kCommitMarker}%H\t%h\t%ad\t%an',
      ]),
      cachedProbe.run(
        [
          'log',
          '--all',
          '--shortstat',
          '--date=short',
          '--pretty=format:${_kCommitMarker}%H\t%h\t%ad\t%an\t%s'
        ],
      ),
      cachedProbe.run(
        [
          'log',
          '--all',
          '--grep=^t3 checkpoint',
          '--invert-grep',
          '--shortstat',
          '--date=short',
          '--pretty=format:${_kCommitMarker}%H\t%h\t%ad\t%an\t%s',
        ],
      ),
      cachedProbe.run(['log', '--all', '--date=short', '--pretty=format:%ad']),
      cachedProbe.run(
        [
          'log',
          '--all',
          '--grep=^t3 checkpoint',
          '--invert-grep',
          '--date=short',
          '--pretty=format:%ad'
        ],
      ),
      cachedProbe.run(['shortlog', '-sn', '--all', '--no-merges']),
      cachedProbe.run(
        [
          'shortlog',
          '-sn',
          '--all',
          '--no-merges',
          '--grep=^t3 checkpoint',
          '--invert-grep'
        ],
      ),
      cachedProbe.run(['reflog', '-n', '120', '--date=short']),
      cachedProbe.run(['stash', 'list']),
      cachedProbe.run(['notes', 'list']),
      cachedProbe.run(['worktree', 'list', '--porcelain']),
      cachedProbe.run(['log', '--all', '--merges', '--oneline']),
      cachedProbe.run(
        [
          'log',
          '--all',
          '--diff-filter=R',
          '--summary',
          '--pretty=format:${_kCommitMarker}%H'
        ],
      ),
      cachedProbe.run(['remote', '-v']),
      // Per-path size at HEAD. Single git call, gives us byte-size for
      // every tracked file. Used as an existence filter (paths missing
      // from HEAD or 0-byte get dropped from the Map view's input set
      // — they're deleted/empty/binary stubs, not "alive code").
      cachedProbe.run(['ls-tree', '-r', '-l', 'HEAD']),
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
    // ls-tree → Map<path, bytes>. When ls-tree comes back empty (e.g.,
    // a freshly-init'd repo, or in tests without that fixture wired)
    // we fall back to "unknown bytes" mode: no path is filtered, sizes
    // are absent. Keeps both real-world and test paths working.
    final pathBytes = _parseLsTreeBytes(futures[19].stdout.toString());

    // Parse the dated-commit stream once; touch counts (line-based,
    // since a real `git log --name-status` emits each changed path on
    // its own line) + downstream co-change / alive-mass all share the
    // same rename canonicalisation map, so a file renamed at -M95
    // attributes consistently across every signal.
    final rawParsed = _parseDatedCommitFiles(futures[4].stdout.toString());
    final filteredParsed = _parseDatedCommitFiles(futures[5].stdout.toString());
    final rawDated = rawParsed.$1;
    final filteredDated = filteredParsed.$1;
    var rawPathTouches = _countPathTouches(
        futures[4].stdout.toString(), rawParsed.$2);
    var filteredPathTouches = _countPathTouches(
        futures[5].stdout.toString(), filteredParsed.$2);
    if (pathBytes.isNotEmpty) {
      // Edge filter: drop paths missing from HEAD or with 0 bytes.
      // Cheap signal-floor cleanup — deleted files, empty stubs, and
      // binary placeholders no longer pollute the Map's ranking.
      bool keep(String path) {
        final size = pathBytes[path];
        return size != null && size > 0;
      }

      rawPathTouches = {
        for (final e in rawPathTouches.entries)
          if (keep(e.key)) e.key: e.value,
      };
      filteredPathTouches = {
        for (final e in filteredPathTouches.entries)
          if (keep(e.key)) e.key: e.value,
      };
    }
    // Directory touches re-aggregate from the (now-filtered) per-path
    // counts so a stratum's touchCount can't include deleted files.
    final rawDirTouches = _aggregateDirTouchesFromPaths(rawPathTouches);
    final filteredDirTouches =
        _aggregateDirTouchesFromPaths(filteredPathTouches);

    final localBranchCount = futures[1]
        .stdout
        .toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty && !line.contains('remotes/'))
        .length;
    final remoteBranchCount = futures[1]
        .stdout
        .toString()
        .split('\n')
        .where((line) => line.contains('remotes/') && !line.contains('->'))
        .length;
    final tagCount =
        refs.where((ref) => ref.refName.startsWith('refs/tags/')).length;
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

    // Dated per-commit file lists (parsed above) also drive co-change
    // (Jaccard pair walk) and the alive-mass exponential decay.
    final rawCommitFiles = [for (final c in rawDated) c.files];
    final filteredCommitFiles = [for (final c in filteredDated) c.files];
    // Await the engine now — both the spectral co-change path and
    // the flow observables want it. If it resolved fast (cache hit)
    // we skip the pair walk entirely; if it returned null (test
    // context, non-repo path) we fall back to Jaccard-from-commits.
    final engine = await engineFuture;
    final spectral = _buildSpectralSummary(engine);
    final rawCoChange = _computeCoChange(
      rawCommitFiles,
      rawPathTouches,
      engine: engine,
      spectral: spectral,
    );
    final filteredCoChange = _computeCoChange(
      filteredCommitFiles,
      filteredPathTouches,
      engine: engine,
      spectral: spectral,
    );

    // Compute metabolism early so its halfLife seeds the alive-mass
    // decay. Metabolism is cheap (single AR(2) fit on the date series)
    // and was already computed downstream — just hoisted.
    final metabolism = _computeMetabolism(filteredDates);

    // Per-path last-touched + alive mass. Half-life self-derives from
    // the AR(2) fit when available, else from the median commit age
    // (also a half-life by definition). Reference date = newest commit
    // in the snapshot to keep the decay stable across redraws of the
    // same data (vs. wall-clock "now" which would tick).
    final rawLastTouched = _pathLastTouchedAt(rawDated);
    final filteredLastTouched = _pathLastTouchedAt(filteredDated);
    final halfLifeDays =
        _selectAliveHalfLife(metabolism.halfLifeDays, filteredDated);
    final referenceDate = filteredLastTouched.values.isEmpty
        ? DateTime.now()
        : filteredLastTouched.values.reduce((a, b) => a.isAfter(b) ? a : b);
    final rawPathAlive = _computeAliveMass(
      touches: rawPathTouches,
      lastTouched: rawLastTouched,
      halfLifeDays: halfLifeDays,
      referenceDate: referenceDate,
    );
    final filteredPathAlive = _computeAliveMass(
      touches: filteredPathTouches,
      lastTouched: filteredLastTouched,
      halfLifeDays: halfLifeDays,
      referenceDate: referenceDate,
    );
    final filteredDirAlive = _aggregateAliveMassByDirectory(filteredPathAlive);

    final rawHotspots = _buildHotspots(
      rawPathTouches,
      rawDirTouches,
      rawDated,
      rawCoChange,
      rawPathAlive,
      spectral,
    );
    final filteredHotspots = _buildHotspots(
      filteredPathTouches,
      filteredDirTouches,
      filteredDated,
      filteredCoChange,
      filteredPathAlive,
      spectral,
    );
    final strata = _buildStrata(
      filteredDirTouches,
      filteredDated,
      filteredDirAlive,
    );
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
      machineHistoryDominant: rawCommits.isNotEmpty &&
          (rawCommits.length - filteredCommits.length) > filteredCommits.length,
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
    final flow = _buildXrayFlow(
      signalIntegrity: signalIntegrity,
      refSummary: refSummary,
      hotspots: filteredHotspots,
      cadence: filteredCadence,
      strata: strata,
      metabolism: metabolism,
      migrationPair: migrationPair,
      spectral: spectral,
    );

    final snapshot = RepositoryXraySnapshotData(
      header: RepositoryXrayHeaderData(
        repoPath: repo,
        repoName: _repoNameFromPath(repo),
        branch: status.branch,
        headCommitHash: headHash,
        headShortHash:
            headHash.length >= 8 ? headHash.substring(0, 8) : headHash,
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
      // Repo metabolism from the filtered (human) commit series — see
      // hoisted computation above. Reused so the alive-mass decay and
      // the metabolism card share the same AR(2) fit (one source of
      // truth for repo time-constants).
      metabolism: metabolism,
      flow: flow,
      reviewerConstellations: _buildReviewerConstellations(
        engine,
        rawHotspots.map((h) => h.path).toSet(),
      ),
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

/// Hard ceiling on how long we'll wait for the Logos engine to resolve
/// during an xray snapshot. Cache-hit resolution is a few ms; a cold
ReviewerConstellationData? _buildReviewerConstellations(
  LogosGit? engine,
  Set<String> allPaths,
) {
  if (engine == null) return null;
  final reviewersByPath = engine.stats.reviewersByPath;
  if (reviewersByPath.isEmpty) return null;

  // Per-reviewer aggregation: how many paths and commits each reviewer covers.
  final perReviewer = <String, (int pathCount, Set<String> paths)>{};
  for (final entry in reviewersByPath.entries) {
    for (final login in entry.value) {
      final existing = perReviewer[login];
      if (existing == null) {
        perReviewer[login] = (1, {entry.key});
      } else {
        existing.$2.add(entry.key);
        perReviewer[login] = (existing.$1 + 1, existing.$2);
      }
    }
  }

  final reviewers = perReviewer.entries.map((e) {
    final topPaths = e.value.$2.toList()..sort();
    return ReviewerConstellationEntry(
      login: e.key,
      observedPathCount: e.value.$1,
      observedCommitCount: 0,
      topPaths: topPaths.take(10).toList(),
    );
  }).toList()
    ..sort((a, b) => b.observedPathCount.compareTo(a.observedPathCount));

  // Blind spots: paths with touches but zero reviewer coverage.
  final observedPaths = reviewersByPath.keys.toSet();
  final unobservedPaths = allPaths.difference(observedPaths);
  final blindSpots = unobservedPaths
      .map((p) => PathObservationData(
            path: p,
            observers: const {},
            observedCommitCount: 0,
          ))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // Orbital decay: detect reviewers who reviewed a directory heavily
  // but whose most recent observations are old (not in recent hyperedges).
  final decayEvents = <OrbitalDecayEvent>[];
  final hyperedges = engine.stats.hyperedgesByPath;
  for (final reviewer in perReviewer.entries) {
    final paths = reviewer.value.$2;
    // Group by top-level directory.
    final dirCounts = <String, int>{};
    for (final p in paths) {
      final dir = p.contains('/') ? p.substring(0, p.indexOf('/')) : '.';
      dirCounts[dir] = (dirCounts[dir] ?? 0) + 1;
    }
    for (final dir in dirCounts.entries) {
      if (dir.value < 3) continue;
      // Check if any RECENT hyperedge in this dir has this reviewer.
      var recentObservation = false;
      for (final p in paths) {
        if (!p.startsWith('${dir.key}/')) continue;
        final edges = hyperedges[p];
        if (edges == null) continue;
        // Hyperedges are sorted by weight desc; top ones are most
        // meaningful. If any of the top-3 has this reviewer, they're
        // still active.
        for (final e in edges.take(3)) {
          if (e.observers.contains(reviewer.key)) {
            recentObservation = true;
            break;
          }
        }
        if (recentObservation) break;
      }
      if (!recentObservation) {
        decayEvents.add(OrbitalDecayEvent(
          reviewerLogin: reviewer.key,
          pathPrefix: dir.key,
          decayMagnitude: dir.value.toDouble(),
        ));
      }
    }
  }

  return ReviewerConstellationData(
    reviewers: reviewers,
    blindSpots: blindSpots.take(50).toList(),
    decayEvents: decayEvents,
    totalObservedPaths: observedPaths.length,
    totalUnobservedPaths: unobservedPaths.length,
  );
}

/// build is hundreds of ms and runs on a background isolate. Past
/// this budget we give up and let the snapshot finish on the classical
/// (non-spectral) path — x-ray is a diagnostic that should never block
/// the UI on an engine rebuild.
const Duration _kEngineResolveBudget = Duration(seconds: 2);

Future<LogosGit?> _tryResolveEngine(String repo) async {
  // Pre-flight filesystem check: without this, the resolver spawns
  // `git rev-parse HEAD` on the path regardless, which both spams
  // test-context stderr and wastes a subprocess on paths we already
  // know can't host an engine. `.git` as a directory covers normal
  // working trees; as a file covers submodule worktrees (git stores
  // `gitdir: …` redirects as regular files).
  final gitEntry = FileSystemEntity.typeSync('$repo/.git');
  if (gitEntry == FileSystemEntityType.notFound) return null;
  try {
    return await resolveLogosGit(repo).timeout(
      _kEngineResolveBudget,
      onTimeout: () => null,
    );
  } catch (_) {
    return null;
  }
}

/// Packaged view over everything we read from a resolved Logos engine's
/// cached spectral basis during an xray snapshot. All the heavy lifting
/// (Lanczos eigendecomposition, k-means community labels, projection
/// of the recent-activity focus) happens once up front — every
/// downstream consumer (co-change pull, keystone flagging, flow
/// observables) reads precomputed fields instead of re-traversing
/// the graph.
///
/// Null fields indicate the engine either isn't available, or the
/// graph is below the spectral minimum (n < 256). Callers must treat
/// the whole object as optional and fall back cleanly.
class _SpectralSummary {
  _SpectralSummary({
    required this.engine,
    required this.basis,
    required this.centralityByPath,
    required this.couplingByPath,
    required this.communityByPath,
    required this.heatTraceNormalised,
    required this.focusEntropyNormalised,
    required this.spectrogeometry,
  });

  final LogosGit engine;

  /// Cached spectral basis. Null when `n < _kSpectralMinNodes` or no
  /// engine was resolvable.
  final SpectralBasis? basis;

  /// path → `Σⱼ uⱼ[f]²·e^{−t·λⱼ}` at the canonical temperature. This is
  /// the heat-kernel diagonal — "how much of the heat trace localises
  /// at file f". The spectral analog of co-change pull and our keystone
  /// signal when the engine is available. Empty when basis is null.
  final Map<String, double> centralityByPath;

  /// path → top-N coupled neighbours read directly from the engine's
  /// weighted coupling CSR. Replaces the O(|commit|²) Jaccard pair
  /// walk with a single edge-list traversal. Empty when no engine.
  final Map<String, List<String>> couplingByPath;

  /// path → Shi–Malik k-way community label on the low-frequency
  /// eigenspace. Empty when basis is null.
  final Map<String, int> communityByPath;

  /// `Z(t)/k` — the heat trace normalised to [0, 1] so consumers can
  /// treat it as a bounded pressure signal. 0 when basis is null.
  final double heatTraceNormalised;

  /// Spectral participation entropy of the recent-activity focus
  /// divided by `log(k)` — in [0, 1]. 0 = a single mode carries the
  /// activity (laser focus); 1 = uniform across modes (scattered).
  /// 0 when basis/focus is null.
  final double focusEntropyNormalised;

  /// Unified geometric fingerprint — RMT classification, persistence
  /// diagram, spectral dimension, zeta invariants, and the
  /// 6-archetype universality vector. Pulled from the engine's
  /// `spectrogeometry()` cache so downstream consumers share one
  /// authoritative read of the graph's geometry.
  ///
  /// Null when the spectral basis isn't resolvable (graph too small).
  final SpectroGeometry? spectrogeometry;
}

/// Canonical temperature for xray-level spectral observables. The heat
/// kernel's low-frequency regime dominates at `t ~ 1/λ_smallest_nonzero`;
/// we pick `t = 1.0` which the engine's own diffusion queries also use
/// as the default so our observables and the rail's observables speak
/// the same units.
const double _kXraySpectralT = 1.0;

/// Number of architectural communities to surface in hotspots. Matches
/// the stratum candidate cap (`_mapStratumCandidateCap = 12`) — roughly
/// "one community per major directory cluster" on a real repo. Empty
/// clusters are absorbed cleanly by the k-means implementation.
const int _kXraySpectralCommunityCount = 8;

/// Extract cacheable spectral observables from a resolved Logos engine.
/// Returns null when the engine is null; otherwise always returns a
/// `_SpectralSummary` — the summary's inner fields handle the
/// "engine is there but the graph is too small for Lanczos" case.
_SpectralSummary? _buildSpectralSummary(LogosGit? engine) {
  if (engine == null) return null;
  final basis = engine.spectralBasis();
  if (basis == null) {
    return _SpectralSummary(
      engine: engine,
      basis: null,
      centralityByPath: const {},
      couplingByPath: _buildCouplingFromGraph(engine),
      communityByPath: const {},
      heatTraceNormalised: 0.0,
      focusEntropyNormalised: 0.0,
      spectrogeometry: null,
    );
  }

  // Heat-kernel diagonal HKS(i, t) = Σⱼ uⱼ[i]²·e^{−t·λⱼ} via the
  // bulk spectral primitive. One O(k·n) pass; this IS the keystone
  // signal — per-file thermal retention at the chosen scale.
  final n = basis.n;
  final k = basis.k;
  final centrality = basis.heatKernelProfileTable([_kXraySpectralT]);
  final paths = engine.nodePaths;
  final centralityByPath = <String, double>{};
  for (var i = 0; i < n; i++) {
    centralityByPath[paths[i]] = centrality[i];
  }

  // Coupling neighbours — read directly from the weighted CSR. Each
  // file gets up to `_couplingNeighborCap` neighbours ranked by edge
  // weight. No pair walk, no per-commit traversal — just one CSR row
  // scan per file.
  final couplingByPath = _buildCouplingFromGraph(engine);

  // Community labels from the Shi–Malik k-way clustering on u₁..u_k.
  final labels = basis.spectralCommunityLabels(_kXraySpectralCommunityCount);
  final communityByPath = <String, int>{};
  for (var i = 0; i < n; i++) {
    communityByPath[paths[i]] = labels[i];
  }

  // Normalised heat trace: Z(t)/k ∈ [0, 1]. Equals 1 at t=0 (all modes
  // contribute 1), decays as t grows. Useful as a bounded pressure
  // signal in the flow observables.
  final heatTrace = basis.heatTrace(_kXraySpectralT);
  final heatTraceNorm = (heatTrace / k).clamp(0.0, 1.0).toDouble();

  // Focus entropy on the recent-activity field. `recentActivityWeights`
  // is cached on the engine, so this is essentially free after the
  // first query. Normalise by log(k) so the result is in [0, 1].
  var focusEntropyNorm = 0.0;
  final activity = engine.recentActivityWeights();
  if (activity.isNotEmpty && k > 1) {
    final rho = Float64List(n);
    for (final e in activity.entries) {
      final id = engine.pathToId[e.key];
      if (id != null) rho[id] = e.value;
    }
    final s = basis.spectralEntropy(rho, _kXraySpectralT);
    final sMax = math.log(k.toDouble());
    if (sMax > 0 && s.isFinite) {
      focusEntropyNorm = (s / sMax).clamp(0.0, 1.0).toDouble();
    }
  }

  return _SpectralSummary(
    engine: engine,
    basis: basis,
    centralityByPath: centralityByPath,
    couplingByPath: couplingByPath,
    communityByPath: communityByPath,
    heatTraceNormalised: heatTraceNorm,
    focusEntropyNormalised: focusEntropyNorm,
    spectrogeometry: engine.spectrogeometry(),
  );
}

/// Read the engine's weighted coupling CSR into a path → top-N
/// neighbours map. Cost: O(|E|) total across all files. Replaces the
/// Jaccard pair walk's O(Σ|commit|²) with a single edge-list scan
/// whose work is linear in the graph, not in the commit history.
Map<String, List<String>> _buildCouplingFromGraph(LogosGit engine) {
  final graph = engine.graph;
  if (graph.n == 0) return const {};
  final paths = engine.nodePaths;
  final out = <String, List<String>>{};
  for (var i = 0; i < graph.n; i++) {
    final start = graph.indptr[i];
    final end = graph.indptr[i + 1];
    if (end == start) continue;
    // Collect (neighbourId, weight) for this row and take top-N by
    // weight. Rows are already bounded by the engine's `edgeDensity`
    // (a small constant), so a full sort of the row is cheap.
    final count = end - start;
    final entries = List<_CouplingEdge>.generate(
      count,
      (k) => _CouplingEdge(graph.indices[start + k], graph.values[start + k]),
    );
    entries.sort((a, b) => b.weight.compareTo(a.weight));
    final take = math.min(_couplingNeighborCap, count);
    final neigh = <String>[];
    for (var k = 0; k < take; k++) {
      neigh.add(paths[entries[k].id]);
    }
    if (neigh.isNotEmpty) out[paths[i]] = neigh;
  }
  return out;
}

/// Tiny value type for sorting CSR edges by weight. Keeps the top-N
/// collection honest without reading the weight array twice inside
/// the comparator.
class _CouplingEdge {
  final int id;
  final double weight;
  const _CouplingEdge(this.id, this.weight);
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
    if (line.startsWith(_kCommitMarker)) {
      current = line.substring(_kCommitMarker.length).split('\t');
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
        filesChanged: int.tryParse(
                RegExp(r'(\d+) files? changed').firstMatch(line)?.group(1) ??
                    '') ??
            0,
        insertions: int.tryParse(
                RegExp(r'(\d+) insertions?\(\+\)').firstMatch(line)?.group(1) ??
                    '') ??
            0,
        deletions: int.tryParse(
                RegExp(r'(\d+) deletions?\(-\)').firstMatch(line)?.group(1) ??
                    '') ??
            0,
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
  for (final date in output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)) {
    counts.update(date, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// Parse a `git log --name-only --format=` stream into per-commit file
/// sets. With an empty format string git emits blank-metadata rows and
/// name-per-line blocks separated by blank lines.
/// One commit's file set with enough header identity for every
/// downstream consumer to work off the same parse: the date drives
/// per-file "last touched" + alive-mass decay, the author drives
/// owner-count enrichment, and the hashes drive recent-touch display.
/// Keeping the raw `%ad` string alongside the parsed DateTime avoids a
/// date→string round-trip when emitting hotspot metadata.
class _DatedCommit {
  _DatedCommit({
    required this.date,
    required this.dateStr,
    required this.hash,
    required this.shortHash,
    required this.author,
    required this.files,
  });
  final DateTime? date;
  final String dateStr;
  final String hash;
  final String shortHash;
  final String author;
  final Set<String> files;
}

/// Parse `--name-status -M95 --format=__C__%H\t%h\t%ad\t%an` output into
/// dated commit records. The marker line packs `hash, shortHash, date,
/// author` tab-separated; every line between markers is one of:
///
///   `M\t<path>`                     modify / add / delete / typechange
///   `A\t<path>`
///   `D\t<path>`
///   `T\t<path>`
///   `R<score>\t<old>\t<new>`        rename (≥95% similar under -M95)
///   `C<score>\t<old>\t<new>`        copy (only if `-C` passed; unused)
///
/// Rename events feed a union-find so any commit touching a pre-rename
/// name attributes to the HEAD-side canonical path. Recovers the
/// `--follow` semantics lost when the xray switched to one batched
/// log instead of per-path subprocesses.
///
/// Bare-path lines (no tab) are tolerated for back-compat with tests
/// that feed `--name-only`-style fixtures — they're treated as
/// modifications on the emitted path.
///
/// Tab-in-author caveat: `%an` can in theory contain a tab, which
/// would push author tokens into [4..] and silently undercount owners.
/// Matches the existing `_parseShortstats` / `_parseCommits` tolerance
/// for the same case — if this ever bites, switch the delimiter to
/// `\x1f` (ASCII Unit Separator) everywhere.
/// Returns the parsed commits plus the rename-canonicalisation map
/// (union-find parent pointers). Callers that also want to canonicalise
/// a separate line-based count — e.g. [_countPathTouches] — can thread
/// the same map through so every signal agrees on "which file".
(List<_DatedCommit>, Map<String, String>) _parseDatedCommitFiles(String raw) {
  final out = <_DatedCommit>[];
  DateTime? curDate;
  String curDateStr = '';
  String curHash = '';
  String curShortHash = '';
  String curAuthor = '';
  Set<String>? curFiles;

  // Rename union-find. Git log walks newest→oldest, so the `new` side
  // of any rename is closer to HEAD — we always union(old → new) so
  // `find(x)` resolves to the HEAD-side canonical. Non-rename paths
  // are absent from the map and canonicalise to themselves.
  final parent = <String, String>{};
  String find(String x) {
    var cur = x;
    while (true) {
      final p = parent[cur];
      if (p == null || p == cur) return cur;
      cur = p;
    }
  }

  void flush() {
    if (curFiles != null && curFiles!.isNotEmpty) {
      out.add(_DatedCommit(
        date: curDate,
        dateStr: curDateStr,
        hash: curHash,
        shortHash: curShortHash,
        author: curAuthor,
        files: curFiles!,
      ));
    }
    curFiles = null;
  }

  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith(_kCommitMarker)) {
      flush();
      final payload = trimmed.substring(_kCommitMarker.length);
      final parts = payload.split('\t');
      assert(parts.length >= 4,
          'xray commit marker must be hash\\tshort\\tdate\\tauthor; got "$payload"');
      curHash = parts.isNotEmpty ? parts[0] : '';
      curShortHash = parts.length > 1 ? parts[1] : '';
      curDateStr = parts.length > 2 ? parts[2] : '';
      curAuthor = parts.length > 3 ? parts.sublist(3).join('\t') : '';
      curDate = DateTime.tryParse(curDateStr);
      curFiles = <String>{};
      continue;
    }
    if (trimmed.isEmpty) continue;
    curFiles ??= <String>{};

    final tabIdx = trimmed.indexOf('\t');
    if (tabIdx < 0) {
      // Legacy bare path (no status prefix). Test fixtures use this.
      curFiles!.add(trimmed.replaceAll('\\', '/'));
      continue;
    }
    final status = trimmed.substring(0, tabIdx);
    final rest = trimmed.substring(tabIdx + 1);
    final restTab = rest.indexOf('\t');
    if (restTab < 0) {
      // `M\t<path>` / `A\t<path>` / `D\t<path>` / `T\t<path>`.
      curFiles!.add(rest.replaceAll('\\', '/'));
      continue;
    }
    // Two-path form: rename or copy. Only renames feed the union-find
    // — copies (`C<score>`) originate from an existing file that is
    // still live, not a rename.
    final oldPath = rest.substring(0, restTab).replaceAll('\\', '/');
    final newPath = rest.substring(restTab + 1).replaceAll('\\', '/');
    if (status.isNotEmpty && status.codeUnitAt(0) == 0x52 /* 'R' */) {
      final rOld = find(oldPath);
      final rNew = find(newPath);
      if (rOld != rNew) parent[rOld] = rNew;
    }
    // Attribute to the HEAD-side name. For a rename this is the new
    // path; for a copy, also the new path (the old still exists).
    curFiles!.add(newPath);
  }
  flush();

  // Canonicalise every commit's file list so pre-rename modifications
  // collapse onto the HEAD-side name. Skipped entirely when no rename
  // was seen (common case) — find() is a no-op on an empty map.
  if (parent.isNotEmpty) {
    for (final c in out) {
      if (c.files.isEmpty) continue;
      final canon = <String>{for (final f in c.files) find(f)};
      c.files
        ..clear()
        ..addAll(canon);
    }
  }
  return (out, parent);
}

/// Project dated commits into per-path most-recent date. Used as the
/// exponential-decay anchor in alive-mass.
Map<String, DateTime> _pathLastTouchedAt(List<_DatedCommit> commits) {
  final out = <String, DateTime>{};
  for (final c in commits) {
    final d = c.date;
    if (d == null) continue;
    for (final f in c.files) {
      final prev = out[f];
      if (prev == null || d.isAfter(prev)) out[f] = d;
    }
  }
  return out;
}

/// Selects a decay half-life for alive-mass computation.
///   1. Use the AR(2) metabolism fit's `halfLifeDays` when finite —
///      the decay constant the oscillator extracted from commit-rate
///      eigenvalues.
///   2. Otherwise fall back to the median commit age: by definition
///      half the activity is older, half newer, so it's the same
///      physical quantity derived from the cumulative distribution.
double _selectAliveHalfLife(
    double? metabolismHalfLifeDays, List<_DatedCommit> commits) {
  if (metabolismHalfLifeDays != null &&
      metabolismHalfLifeDays.isFinite &&
      metabolismHalfLifeDays > 0) {
    return metabolismHalfLifeDays;
  }
  final ages = <int>[];
  DateTime? newest;
  for (final c in commits) {
    if (c.date == null) continue;
    if (newest == null || c.date!.isAfter(newest)) newest = c.date;
  }
  if (newest == null) return double.infinity;
  for (final c in commits) {
    if (c.date == null) continue;
    ages.add(newest.difference(c.date!).inDays.abs());
  }
  if (ages.isEmpty) return double.infinity;
  ages.sort();
  final median = ages[ages.length ~/ 2].toDouble();
  return median > 0 ? median : 1.0;
}

/// Per-path alive mass = touchCount × exp(-ageDays / halfLife). The
/// exponential is the canonical decay for memoryless decay processes;
/// the half-life is repo-derived (see [_selectAliveHalfLife]). No
/// floor — physically a 10-half-life-old file is ~0.1% of its prime
/// mass, which is what we want it to read as.
Map<String, double> _computeAliveMass({
  required Map<String, int> touches,
  required Map<String, DateTime> lastTouched,
  required double halfLifeDays,
  required DateTime referenceDate,
}) {
  if (!halfLifeDays.isFinite) {
    return {for (final e in touches.entries) e.key: e.value.toDouble()};
  }
  final out = <String, double>{};
  for (final entry in touches.entries) {
    final last = lastTouched[entry.key];
    final ageDays = last == null
        ? halfLifeDays * 4 // unseen → ~6% of mass; treat as quite old
        : referenceDate.difference(last).inDays.abs().toDouble();
    final decay = math.exp(-ageDays / halfLifeDays);
    out[entry.key] = entry.value.toDouble() * decay;
  }
  return out;
}

/// Aggregate per-file alive mass into per-directory-prefix mass using
/// the same prefix scheme as [_countDirectoryTouches]. Strata sit on
/// these directory prefixes, so this becomes the stratum size.
Map<String, double> _aggregateAliveMassByDirectory(
    Map<String, double> pathAliveMass) {
  final out = <String, double>{};
  for (final entry in pathAliveMass.entries) {
    final prefix = _directoryPrefixForPath(entry.key.replaceAll('\\', '/'));
    out.update(prefix, (v) => v + entry.value, ifAbsent: () => entry.value);
  }
  return out;
}

/// Compute a keystone score per file and flag the top band. Keystone
/// semantics (ecology borrow): a file whose *pull* — sum of Jaccard
/// couplings to all co-changed files — is high while its own touch
/// count stays modest. These are the bridge species: quiet on their
/// own ledger, load-bearing across clusters.
///   pull(f)     = Σ_g J(f, g)      (Jaccard co-change with every other file)
///   keystone(f) = pull(f) / log1p(touchCount(f))
/// The log1p dampens the divisor so raw frequency doesn't dominate —
/// we want pull-per-touch to identify files whose *each touch* is
/// structurally heavy. Top 10% (or ≥3 files for tiny repos) get
/// `isKeystone = true`.
/// Result of one co-change pass over the commit history. Carries both
/// the per-file keystone score (pull-per-touch) and the per-file top-N
/// co-changers, both derived from the same Jaccard-weighted pair walk
/// — same loop, no extra git work.
class _CoChangeAnalysis {
  const _CoChangeAnalysis({
    required this.scores,
    required this.coupling,
  });

  /// Pull-per-touch keystone score, file → score.
  final Map<String, double> scores;

  /// File → top-N co-changed paths, ranked by Jaccard descending.
  /// Drives the Map view's coupling overlay.
  final Map<String, List<String>> coupling;
}

/// How many co-changed neighbours we keep per file. Five is enough to
/// draw a useful "what moves with this" overlay without crowding the
/// treemap with a hairball of lines.
const int _couplingNeighborCap = 5;

_CoChangeAnalysis _computeCoChange(
  List<Set<String>> commits,
  Map<String, int> touches, {
  LogosGit? engine,
  _SpectralSummary? spectral,
}) {
  if (commits.isEmpty || touches.isEmpty) {
    return const _CoChangeAnalysis(scores: {}, coupling: {});
  }

  // Spectral fast path: when the Logos engine has a spectral basis,
  // both the "pull per touch" score and the per-file coupling come
  // straight from cached O(k·n) data — the heat-kernel diagonal plus
  // one scan of the weighted coupling CSR. We skip the full pair walk
  // over commit history entirely; the engine already represents every
  // pair weight in the CSR's edge weights, built during engine
  // construction once per HEAD.
  if (spectral != null &&
      spectral.centralityByPath.isNotEmpty &&
      spectral.couplingByPath.isNotEmpty) {
    final scores = <String, double>{};
    spectral.centralityByPath.forEach((path, centrality) {
      final touch = touches[path];
      if (touch == null) return;
      // log1p dampens the divisor so raw touch count doesn't dominate
      // — same shape as the classical formula, just with a spectral
      // "pull" (heat-kernel diagonal) instead of a Jaccard sum.
      final divisor = math.log(1 + touch);
      scores[path] = divisor > 0 ? centrality / divisor : centrality;
    });
    // Filter coupling to paths the current touch map knows about, so
    // the raw-vs-filtered partition of history doesn't bleed coupling
    // neighbours from files absent in the current view.
    final coupling = <String, List<String>>{};
    spectral.couplingByPath.forEach((path, neigh) {
      if (!touches.containsKey(path)) return;
      final filtered = [for (final n in neigh) if (touches.containsKey(n)) n];
      if (filtered.isNotEmpty) coupling[path] = filtered;
    });
    return _CoChangeAnalysis(scores: scores, coupling: coupling);
  }

  // Per-file membership index — commitIndex → filesInCommit is given;
  // we need its transpose: file → set of commit indices.
  final fileCommits = <String, Set<int>>{};
  for (var i = 0; i < commits.length; i++) {
    for (final f in commits[i]) {
      fileCommits.putIfAbsent(f, () => <int>{}).add(i);
    }
  }

  // For each file, compute pull by walking its co-commit neighbours.
  // The double-nested pass is O(Σ_i |commits[i]|²) which is fine for
  // X-Ray-scale windows (≤ ~1500 commits, median 5 files each).
  final pairWeights = <String, Map<String, double>>{};
  for (final commit in commits) {
    final members = commit.toList();
    final n = members.length;
    if (n < 2) continue;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final a = members[i];
        final b = members[j];
        // Only count each pair once at read time — aggregate per-file
        // co-count, then convert to Jaccard below.
        pairWeights
            .putIfAbsent(a, () => <String, double>{})
            .update(b, (v) => v + 1, ifAbsent: () => 1);
        pairWeights
            .putIfAbsent(b, () => <String, double>{})
            .update(a, (v) => v + 1, ifAbsent: () => 1);
      }
    }
  }

  final scores = <String, double>{};
  final coupling = <String, List<String>>{};
  for (final entry in pairWeights.entries) {
    final f = entry.key;
    final neighbours = entry.value;
    final nf = fileCommits[f]?.length ?? 0;
    if (nf == 0) continue;
    var pull = 0.0;
    final perNeighbourJ = <MapEntry<String, double>>[];
    for (final n in neighbours.entries) {
      final ng = fileCommits[n.key]?.length ?? 0;
      if (ng == 0) continue;
      // Jaccard: co / (nf + ng - co).
      final co = n.value;
      final union = nf + ng - co;
      if (union <= 0) continue;
      final j = co / union;
      pull += j;
      perNeighbourJ.add(MapEntry(n.key, j));
    }
    final touch = touches[f] ?? nf;
    final divisor = math.log(1 + touch);
    scores[f] = divisor > 0 ? pull / divisor : pull;
    if (perNeighbourJ.isNotEmpty) {
      perNeighbourJ.sort((a, b) => b.value.compareTo(a.value));
      coupling[f] = perNeighbourJ
          .take(_couplingNeighborCap)
          .map((e) => e.key)
          .toList(growable: false);
    }
  }
  return _CoChangeAnalysis(scores: scores, coupling: coupling);
}

/// Derive the repo's metabolism from its daily commit-rate series.
/// The date map is date-string → commit-count; we need a dense,
/// gap-filled chronological series (zero-filling idle days) so the
/// AR(2) oscillator sees the actual rhythm rather than a compacted
/// timeline. Then a single Engram fit yields spectral radius,
/// half-life (in days), and the converging/diverging/steady label
/// the rest of the app already knows how to render.
/// Returns [RepositoryXrayMetabolismData.empty] for windows too short
/// for a fit, so renderers can silently omit the card.
RepositoryXrayMetabolismData _computeMetabolism(Map<String, int> dateCounts) {
  if (dateCounts.isEmpty) return RepositoryXrayMetabolismData.empty;

  // Sort keys chronologically. Dates come in as yyyy-MM-dd strings
  // (git log --date=short), so lex order == chronological order.
  final sortedDates = dateCounts.keys.toList()..sort();
  final first = DateTime.tryParse(sortedDates.first);
  final last = DateTime.tryParse(sortedDates.last);
  if (first == null || last == null) return RepositoryXrayMetabolismData.empty;

  final totalDays = last.difference(first).inDays + 1;
  if (totalDays < engramMinSamples + 2) {
    return RepositoryXrayMetabolismData.empty;
  }

  // Dense, gap-filled series — one bucket per day across the window.
  // Idle days are zeros, which is exactly what the oscillator needs
  // to see the true rhythm (otherwise 5 active days in 30 would look
  // indistinguishable from 5 consecutive days).
  final series = List<double>.filled(totalDays, 0);
  dateCounts.forEach((dateStr, count) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return;
    final idx = d.difference(first).inDays;
    if (idx >= 0 && idx < totalDays) series[idx] = count.toDouble();
  });

  // Centre the signal so AR(2) fits the dynamics, not the mean rate.
  // Typed-list output avoids per-element boxing inside the AR(2) fit.
  var mean = 0.0;
  for (final v in series) {
    mean += v;
  }
  mean /= series.length;
  final centred = Float64List(series.length);
  for (var i = 0; i < series.length; i++) {
    centred[i] = series[i] - mean;
  }

  final fit = engramFit(centred);
  final orbit = BranchOrbit(
    fit: fit,
    // Trend slope over the activity window: positive = repo heating
    // up, negative = cooling. Not a branch Jaccard slope — the same
    // BranchOrbit shape is reused because its classification logic
    // (converging/diverging/steady via slope + orbit gate) matches
    // what we want for the repo's own trajectory.
    trendSlope: _seriesTrendSlope(series),
    samples: series.length - 1,
    meanSimilarity: mean,
  );

  // Sparkline — max-normalised so renderers can draw without knowing
  // the raw count range.
  var peak = 0.0;
  for (final v in series) {
    if (v > peak) peak = v;
  }
  final sparkline = Float64List(series.length);
  if (peak > 0) {
    final invPeak = 1.0 / peak;
    for (var i = 0; i < series.length; i++) {
      sparkline[i] = series[i] * invPeak;
    }
  }

  return RepositoryXrayMetabolismData(
    spectralRadius: fit.spectralRadius,
    halfLifeDays: fit.halfLifeSamples,
    isOrbital: fit.isOrbital,
    trajectoryLabel: orbit.characterLabel ?? '',
    activeDays: dateCounts.length,
    sparkline: sparkline,
  );
}

/// Least-squares slope on (index, value). Used by the metabolism
/// classifier to judge whether the commit-rate is trending up or down
/// over the analysed window.
double _seriesTrendSlope(List<double> series) {
  final n = series.length;
  if (n < 2) return 0;
  var sumI = 0.0, sumI2 = 0.0, sumS = 0.0, sumIS = 0.0;
  for (var i = 0; i < n; i++) {
    sumI += i;
    sumI2 += i * i;
    sumS += series[i];
    sumIS += i * series[i];
  }
  final denom = n * sumI2 - sumI * sumI;
  if (denom == 0) return 0;
  return (n * sumIS - sumI * sumS) / denom;
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

/// Count per-path touches from the same `--name-status -M95` stream
/// that feeds [_parseDatedCommitFiles]. Line-based: production git
/// emits one status line per changed path per commit, so line count
/// equals commit-touch count without any per-commit dedup.
///
/// [canon] is the union-find parent map from [_parseDatedCommitFiles]
/// — passing it canonicalises pre-rename names onto the HEAD-side
/// path, matching how downstream enrichment / co-change / alive-mass
/// see the same file. Pass an empty map to skip rename collapsing.
Map<String, int> _countPathTouches(String output, Map<String, String> canon) {
  String findCanon(String x) {
    if (canon.isEmpty) return x;
    var cur = x;
    while (true) {
      final p = canon[cur];
      if (p == null || p == cur) return cur;
      cur = p;
    }
  }

  final counts = <String, int>{};
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith(_kCommitMarker)) continue;

    // Extract the HEAD-side path from the status line. Bare paths
    // (legacy `--name-only`-style test fixtures) fall through the
    // tab-less branch unchanged.
    String path;
    final tab1 = trimmed.indexOf('\t');
    if (tab1 < 0) {
      path = trimmed;
    } else {
      final rest = trimmed.substring(tab1 + 1);
      final tab2 = rest.indexOf('\t');
      // `R<score>\t<old>\t<new>` / `C<score>\t<old>\t<new>` — the
      // new path is the HEAD-side name. Single-path rows fall into
      // the else branch.
      path = tab2 < 0 ? rest : rest.substring(tab2 + 1);
    }
    path = findCanon(path.replaceAll('\\', '/'));
    counts.update(path, (v) => v + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// Re-aggregate per-directory touch counts from a (possibly filtered)
/// per-path map. Same prefix scheme as [_countDirectoryTouches], just
/// fed from already-counted data instead of the raw git-log stream.
Map<String, int> _aggregateDirTouchesFromPaths(Map<String, int> pathTouches) {
  final out = <String, int>{};
  for (final entry in pathTouches.entries) {
    final prefix = _directoryPrefixForPath(entry.key.replaceAll('\\', '/'));
    out.update(prefix, (v) => v + entry.value, ifAbsent: () => entry.value);
  }
  return out;
}

/// Parse `git ls-tree -r -l HEAD` into Map<path, bytes>. Each line is:
///   <mode> SP <type> SP <object> <pad> <size> TAB <path>
/// Exactly one TAB separates the metadata block from the path. The
/// metadata block ends in a space-padded size column, which may be
/// `-` for non-blob entries (commits in submodules) — those we skip.
@visibleForTesting
Map<String, int> parseLsTreeBytesForTesting(String output) =>
    _parseLsTreeBytes(output);

/// Test-only view over [_parseDatedCommitFiles]. Returns one entry per
/// commit — each entry is the set of HEAD-side (rename-canonical) paths
/// that commit touched. Lets tests pin the union-find logic without
/// standing up a full xray probe.
@visibleForTesting
List<Set<String>> parseDatedCommitCanonicalFilesForTesting(String output) {
  final (commits, _) = _parseDatedCommitFiles(output);
  return [for (final c in commits) c.files];
}

Map<String, int> _parseLsTreeBytes(String output) {
  final out = <String, int>{};
  for (final line in output.split('\n')) {
    if (line.isEmpty) continue;
    final tabIdx = line.indexOf('\t');
    if (tabIdx <= 0) continue;
    // Left side: mode type object size (space-separated, size is the
    // last whitespace-delimited token).
    final left = line.substring(0, tabIdx);
    final lastSpace = left.lastIndexOf(' ');
    if (lastSpace < 0) continue;
    final sizeStr = left.substring(lastSpace + 1).trim();
    final path = line.substring(tabIdx + 1).replaceAll('\\', '/');
    final size = int.tryParse(sizeStr);
    if (size == null) continue; // submodule commit ('-') or malformed
    out[path] = size;
  }
  return out;
}

List<RepositoryXrayHotspotData> _buildHotspots(
  Map<String, int> pathTouches,
  Map<String, int> dirTouches,
  List<_DatedCommit> commits,
  _CoChangeAnalysis coChange,
  Map<String, double> pathAliveMass,
  _SpectralSummary? spectral,
) {
  final keystoneScores = coChange.scores;
  final coupling = coChange.coupling;
  final files = pathTouches.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final dirs = dirTouches.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // Keystone flag is top-decile of the distribution, with a floor of
  // at least three files so tiny repos still surface their bridge
  // species. Computed from the full `keystoneScores` map — keystones
  // can be low-touch files that wouldn't qualify as hotspots on raw
  // frequency alone.
  final keystoneFlags = _flagKeystones(keystoneScores);

  // Hotspot candidate set: top-N files by raw touch count. The cap is
  // a *data-volume* bound (each enrich = 2 git probes), not a UX gate.
  // The Map view's render-time area filter decides how many actually
  // appear on screen — readable tile area derives from font metrics +
  // canvas size, not from this number.
  final picked = <String>{
    for (final entry in files.take(_mapHotspotCandidateCap)) entry.key,
  };

  // Keystone supplementation: any flagged keystone file not already
  // in the hotspot list gets pulled in, capped so the list never
  // blows past a reasonable size. Without this, keystones by
  // definition never surface — they *should* have low touch counts
  // (that's what makes the pull-per-touch ratio notable).
  final sortedKeystones = keystoneFlags
      .where((k) => !picked.contains(k))
      .toList()
    ..sort(
        (a, b) => (keystoneScores[b] ?? 0).compareTo(keystoneScores[a] ?? 0));
  for (final path in sortedKeystones.take(_keystoneHotspotCap)) {
    picked.add(path);
  }

  // Previously each hotspot candidate spawned 2 `git log -- <path>`
  // subprocesses to fetch authors and the most recent commit. With
  // ~40 file + 16 directory candidates that was ~112 subprocesses per
  // snapshot; on Windows (50ms+ spawn each, plus .git I/O contention
  // under concurrent `git log --all`) this was the dominant xray
  // cost. We already have the full `--name-only` commit stream
  // parsed into [commits], so walk that once per path in-memory.
  int communityOf(String path) =>
      spectral?.communityByPath[path] ?? -1;
  final dirPaths =
      dirs.take(_mapDirHotspotCandidateCap).map((e) => e.key).toList();
  final enriched = _enrichPathsFromCommits(
    filePaths: picked,
    dirPaths: dirPaths,
    commits: commits,
  );
  final hotspots = <RepositoryXrayHotspotData>[
    for (final path in picked)
      _hotspotFromEnrichment(
        path: path,
        kind: 'file',
        touchCount: pathTouches[path] ?? 0,
        enrichment: enriched[path],
        keystoneScore: keystoneScores[path],
        isKeystone: keystoneFlags.contains(path),
        coupledTo: coupling[path] ?? const [],
        aliveMass: pathAliveMass[path] ?? (pathTouches[path] ?? 0).toDouble(),
        spectralCommunity: communityOf(path),
      ),
    for (final entry in dirs.take(_mapDirHotspotCandidateCap))
      _hotspotFromEnrichment(
        path: entry.key,
        kind: 'directory',
        touchCount: entry.value,
        enrichment: enriched[entry.key],
        keystoneScore: null,
        isKeystone: false,
        coupledTo: const [],
        aliveMass: pathAliveMass[entry.key] ?? entry.value.toDouble(),
        spectralCommunity: -1,
      ),
  ];
  // Sort: keystones group at the top (they're the noteworthy shape),
  // then remaining by raw touch count. Within each group, touch count
  // tie-breaks so the ordering stays stable and familiar.
  hotspots.sort((a, b) {
    if (a.isKeystone != b.isKeystone) return a.isKeystone ? -1 : 1;
    return b.touchCount.compareTo(a.touchCount);
  });
  return hotspots;
}

/// Map view candidate caps. These are *data-volume* bounds — the
/// number of paths the backend surfaces to the renderer — not UX
/// limits. The renderer culls by tile area (font-derived readability
/// floor), so the visible count emerges from canvas size, not these.
/// Each cap is sized to the semantic shape it carries:
///  • Strata are top-level directory partitions; even monorepos rarely
///    have more than a handful of meaningful ones.
///  • File hotspots want diversity — the renderer should be able to
///    show many on a wide window, few on a narrow one.
///  • Directory hotspots fill the gap between strata and files.
/// Enrichment now reads the already-parsed `--name-status` commit
/// stream in-memory, so these caps are pure data-volume bounds.
const int _mapStratumCandidateCap = 12;
const int _mapHotspotCandidateCap = 40;
const int _mapDirHotspotCandidateCap = 16;

/// Fraction of the distribution that counts as "keystone". Top 10%
/// by construction — a file has to be in the best-tenth of the
/// pull-per-touch distribution to earn the label. Adaptive: computed
/// per-repo from that repo's own score distribution.
const double _keystoneTopFraction = 0.10;

/// Minimum number of files flagged regardless of distribution size.
/// Matches the AR(2) `engramMinSamples` floor in spirit — below this
/// the top-decile cut produces 0 or 1 items, which hides the bridge
/// species on tiny repos. Derived: the same six-sample threshold the
/// oscillator fit uses for meaningful signal, halved because flagging
/// is a weaker commitment than fitting.
const int _keystoneMinFlags = engramMinSamples ~/ 2;

/// Maximum additional keystones to pull into the hotspot list beyond
/// the top-N-by-touchCount candidates. Same derivation as
/// [_keystoneMinFlags] — we want the floor to fit in the visible
/// hotspot band without displacing all the frequency-ranked ones.
const int _keystoneHotspotCap = _keystoneMinFlags;

/// Evidence rows we show per signal card. Pre-existing convention in
/// `_buildCards` — the other cards already cap at five items — so the
/// keystone card matches them for visual consistency.
const int _signalCardEvidenceCap = 5;

/// Flag the files in the top fraction of keystone score, with a
/// repo-size-independent floor so tiny repos still surface their
/// bridge species instead of getting zero flags.
Set<String> _flagKeystones(Map<String, double> scores) {
  if (scores.isEmpty) return const {};
  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topFraction = (sorted.length * _keystoneTopFraction).ceil();
  final take =
      topFraction > _keystoneMinFlags ? topFraction : _keystoneMinFlags;
  return sorted.take(take.clamp(1, sorted.length)).map((e) => e.key).toSet();
}

/// Per-path enrichment derived from a single pass over the parsed
/// `--name-only` commit stream: distinct authors who touched the path
/// plus the most recent touch (hash + shortHash + raw YYYY-MM-DD).
class _PathEnrichment {
  _PathEnrichment();
  final Set<String> authors = <String>{};
  DateTime? recentDate;
  String recentDateStr = '';
  String recentHash = '';
  String recentShortHash = '';

  void observe(_DatedCommit c) {
    if (c.author.isNotEmpty) authors.add(c.author);
    // Record identity even when the commit's date failed to parse —
    // otherwise a file whose only touches had malformed dates would
    // report ownerCount > 0 but no hash/date, which renders worse than
    // "no information." Dated commits overwrite undated ones below.
    if (recentHash.isEmpty && c.hash.isNotEmpty) {
      recentHash = c.hash;
      recentShortHash = c.shortHash;
      recentDateStr = c.dateStr;
    }
    final d = c.date;
    if (d == null) return;
    if (recentDate == null || d.isAfter(recentDate!)) {
      recentDate = d;
      recentDateStr = c.dateStr;
      recentHash = c.hash;
      recentShortHash = c.shortHash;
    }
  }
}

/// Single-pass enrichment for every picked file + directory. Walks
/// [commits] once, routing each touched path either directly (files)
/// or via prefix match (directories) into its enrichment bucket.
/// Equivalent to `git log --follow -- <path>` in aggregate: the
/// commits list is canonicalised via union-find (see
/// [_parseDatedCommitFiles]) so a file's pre-rename history, when the
/// rename meets the -M95 similarity threshold, attributes to the
/// HEAD-side name.
Map<String, _PathEnrichment> _enrichPathsFromCommits({
  required Iterable<String> filePaths,
  required Iterable<String> dirPaths,
  required List<_DatedCommit> commits,
}) {
  final out = <String, _PathEnrichment>{};
  final fileSet = filePaths.toSet();
  for (final p in fileSet) {
    out[p] = _PathEnrichment();
  }
  final dirList = dirPaths.toList();
  for (final d in dirList) {
    out[d] = _PathEnrichment();
  }
  if (fileSet.isEmpty && dirList.isEmpty) return out;

  // Pre-compute `${dir}/` so prefix match is one O(n) compare per
  // file instead of an allocation per commit.
  final dirPrefixes = [for (final d in dirList) '$d/'];

  for (final commit in commits) {
    // Track which dirs already matched this commit so each dir gets
    // at most one observe() per commit. This is a perf optimisation,
    // not a correctness requirement — `authors` is a Set and
    // recent-date tracks max — but it keeps the inner loop tight.
    final dirHit = List<bool>.filled(dirList.length, false);
    for (final file in commit.files) {
      final fileBucket = out[file];
      // The fileSet check is load-bearing: if a tracked path happens
      // to equal a directory path exactly (e.g. a submodule gitlink
      // named like a dir candidate), `out[file]` resolves to the dir
      // bucket, and we'd attribute a file-observe to it. Guarding on
      // fileSet membership pins file-observes to real file candidates.
      if (fileBucket != null && fileSet.contains(file)) {
        fileBucket.observe(commit);
      }
      for (var i = 0; i < dirList.length; i++) {
        if (dirHit[i]) continue;
        final dir = dirList[i];
        if (file == dir || file.startsWith(dirPrefixes[i])) {
          dirHit[i] = true;
          out[dir]!.observe(commit);
        }
      }
    }
  }
  return out;
}

RepositoryXrayHotspotData _hotspotFromEnrichment({
  required String path,
  required String kind,
  required int touchCount,
  required _PathEnrichment? enrichment,
  required double? keystoneScore,
  required bool isKeystone,
  required List<String> coupledTo,
  required double aliveMass,
  required int spectralCommunity,
}) {
  final e = enrichment;
  return RepositoryXrayHotspotData(
    kind: kind,
    path: path,
    touchCount: touchCount,
    ownerCount: e?.authors.length ?? 0,
    lastTouchedAt: e?.recentDateStr ?? '',
    latestCommitHash:
        (e != null && e.recentHash.isNotEmpty) ? e.recentHash : null,
    latestShortHash:
        (e != null && e.recentShortHash.isNotEmpty) ? e.recentShortHash : null,
    keystoneScore: keystoneScore,
    isKeystone: isKeystone,
    coupledTo: coupledTo,
    aliveMass: aliveMass,
    spectralCommunity: spectralCommunity,
  );
}

List<RepositoryXrayStratumData> _buildStrata(
  Map<String, int> dirTouches,
  List<_DatedCommit> commits,
  Map<String, double> dirAliveMass,
) {
  final entries = dirTouches.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final picked = entries.take(_mapStratumCandidateCap).toList();
  final dirPaths = [for (final e in picked) e.key];
  final enriched = _enrichPathsFromCommits(
    filePaths: const <String>[],
    dirPaths: dirPaths,
    commits: commits,
  );
  return [
    for (final entry in picked)
      RepositoryXrayStratumData(
        id: entry.key,
        label: _stratumLabelForPrefix(entry.key),
        pathPrefix: entry.key,
        touchCount: entry.value,
        ownerCount: enriched[entry.key]?.authors.length ?? 0,
        lastTouchedAt: enriched[entry.key]?.recentDateStr ?? '',
        summary: 'Touched ${entry.value} times in filtered history.',
        aliveMass: dirAliveMass[entry.key] ?? entry.value.toDouble(),
      ),
  ];
}

List<RepositoryXrayPivotCommitData> _buildPivotCommits(
    List<_ShortstatRecord> records) {
  final sorted = [...records]..sort((a, b) {
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
  final bursts = commitDates.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
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

  final reflogBursts = reflogDates.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (reflogBursts.isNotEmpty) {
    cadence.add(
      RepositoryXrayCadenceData(
        kind: 'reflog',
        label: reflogBursts.first.key,
        count: reflogBursts.first.value,
        detail:
            '${reflogBursts.first.value} local session events on ${reflogBursts.first.key}.',
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
  final totalTouches =
      hotspots.fold<int>(0, (sum, hotspot) => sum + hotspot.touchCount);
  final topShare = topHotspot == null || totalTouches == 0
      ? 0.0
      : topHotspot.touchCount / totalTouches;
  final peakBurst = cadence
      .where((item) => item.kind == 'burst')
      .fold<int>(0, (best, item) => item.count > best ? item.count : best);
  final peakReflog = cadence
      .where((item) => item.kind == 'reflog')
      .fold<int>(0, (best, item) => item.count > best ? item.count : best);

  if (signalIntegrity.hasHiddenRefs) {
    cards.add(
      RepositoryXrayCardData(
        id: 'hidden-refs',
        title: 'Hidden Git namespaces',
        claim:
            '${signalIntegrity.hiddenRefCount} refs live outside normal branch/tag space.',
        verdict: 'hard-fact',
        confidence: 'high',
        evidence: [
          RepositoryXrayEvidenceData(
            label: 'Hidden refs',
            detail:
                '${signalIntegrity.hiddenRefCount} refs outside heads/remotes/tags.',
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
        claim:
            'Checkpoint-style commits materially distort naive history metrics.',
        verdict: 'strong-pattern',
        confidence: 'high',
        evidence: [
          RepositoryXrayEvidenceData(
            label: 'Raw vs filtered',
            detail:
                '${signalIntegrity.rawCommitCount} raw commits vs ${signalIntegrity.filteredCommitCount} filtered commits.',
            kind: 'history',
          ),
          RepositoryXrayEvidenceData(
            label: 'Machine commits',
            detail:
                '${signalIntegrity.machineCommitCount} commits matched machine/session patterns.',
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
            detail:
                '${migrationPair.older.touchCount} touches, last active ${migrationPair.older.lastTouchedAt}.',
            kind: 'path',
            path: migrationPair.older.pathPrefix,
          ),
          RepositoryXrayEvidenceData(
            label: migrationPair.newer.pathPrefix,
            detail:
                '${migrationPair.newer.touchCount} touches, last active ${migrationPair.newer.lastTouchedAt}.',
            kind: 'path',
            path: migrationPair.newer.pathPrefix,
          ),
        ],
      ),
    );
  }

  if (topHotspot != null &&
      topHotspot.ownerCount <= 1 &&
      topHotspot.touchCount >= 8) {
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
            detail:
                '${topHotspot.touchCount} touches in ${usingRawMetrics ? 'raw' : 'filtered'} history.',
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
        claim:
            'Git tags are not being used as a visible release or milestone layer.',
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
        claim:
            'Work lands in concentrated bursts rather than a flat daily rhythm.',
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
        claim:
            'Reflog volume suggests concentrated local iteration beyond published commits.',
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

  // Surfaces the ecological bridge species: files that carry a lot
  // of co-change pull for their touch count. Silent when the repo
  // has no flagged keystones (tiny repo, no coupling data).
  final keystones = hotspots.where((h) => h.isKeystone).toList();
  if (keystones.isNotEmpty) {
    // Sort keystones by their keystoneScore (descending) so the
    // evidence list leads with the most structurally heavy files.
    keystones.sort(
      (a, b) => (b.keystoneScore ?? 0).compareTo(a.keystoneScore ?? 0),
    );
    cards.add(
      RepositoryXrayCardData(
        id: 'keystone-files',
        title: keystones.length == 1
            ? 'Keystone bridge-file'
            : '${keystones.length} keystone bridge-files',
        claim: keystones.length == 1
            ? 'One file carries disproportionate co-change weight relative to its touch count.'
            : 'A small set of files carry disproportionate co-change weight relative to their touch counts.',
        verdict: 'strong-pattern',
        confidence: 'medium',
        evidence: [
          for (final k in keystones.take(_signalCardEvidenceCap))
            RepositoryXrayEvidenceData(
              label: k.path,
              detail: '${k.touchCount} touch${k.touchCount == 1 ? '' : 'es'} · '
                  'pull φ=${(k.keystoneScore ?? 0).toStringAsFixed(2)}',
              kind: 'file',
              count: k.touchCount,
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
        claim:
            'A small set of files and directories absorbs a disproportionate share of changes.',
        verdict: 'strong-pattern',
        confidence: 'medium',
        evidence: [
          RepositoryXrayEvidenceData(
            label: 'Top hotspot',
            detail:
                '${topHotspot.path} accounts for ${(topShare * 100).toStringAsFixed(0)}% of the visible hotspot set.',
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

RepositoryXrayFlowData _buildXrayFlow({
  required RepositoryXraySignalIntegrityData signalIntegrity,
  required RepositoryXrayRefSummaryData refSummary,
  required List<RepositoryXrayHotspotData> hotspots,
  required List<RepositoryXrayCadenceData> cadence,
  required List<RepositoryXrayStratumData> strata,
  required RepositoryXrayMetabolismData metabolism,
  required _MigrationPair? migrationPair,
  required _SpectralSummary? spectral,
}) {
  double clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

  final totalTouches =
      hotspots.fold<int>(0, (sum, hotspot) => sum + hotspot.touchCount);
  final topShare = hotspots.isEmpty || totalTouches == 0
      ? 0.0
      : hotspots.first.touchCount / totalTouches;
  final peakBurst = cadence
      .where((item) => item.kind == 'burst')
      .fold<int>(0, (best, item) => item.count > best ? item.count : best);
  final peakReflog = cadence
      .where((item) => item.kind == 'reflog')
      .fold<int>(0, (best, item) => item.count > best ? item.count : best);
  final machinePressure = signalIntegrity.rawCommitCount == 0
      ? 0.0
      : signalIntegrity.machineCommitCount / signalIntegrity.rawCommitCount;
  final mergePressure = signalIntegrity.filteredCommitCount == 0
      ? 0.0
      : refSummary.mergeCommitCount / signalIntegrity.filteredCommitCount;
  final hiddenPressure = signalIntegrity.hiddenRefCount == 0
      ? 0.0
      : math.min(1.0, signalIntegrity.hiddenRefCount / 3.0);
  final hotspotPressure = clamp01(topShare);
  final burstPressure = peakBurst == 0 ? 0.0 : math.min(1.0, peakBurst / 8.0);
  final reflogPressure =
      peakReflog == 0 ? 0.0 : math.min(1.0, peakReflog / 16.0);
  final migrationPressure = migrationPair == null
      ? 0.0
      : math.min(
          1.0,
          (migrationPair.older.touchCount + migrationPair.newer.touchCount) /
              24.0,
        );
  final stratumPressure =
      strata.isEmpty ? 0.0 : math.min(1.0, strata.length / 6.0);
  final orbitalLift = metabolism.activeDays == 0
      ? 0.0
      : metabolism.isOrbital
          ? 0.18
          : 0.08;

  final gradientMass = clamp01(
    0.34 * (1.0 - clamp01(mergePressure)) +
        0.20 * (1.0 - burstPressure) +
        0.16 * (1.0 - hotspotPressure) +
        0.15 * (1.0 - machinePressure) +
        0.15 * (1.0 - hiddenPressure) +
        orbitalLift,
  );
  final curlMass = clamp01(
    0.42 * clamp01(mergePressure) +
        0.28 * burstPressure +
        0.16 * reflogPressure +
        0.14 * hotspotPressure,
  );
  final harmonicMass = clamp01(
    0.33 * hiddenPressure +
        0.28 * migrationPressure +
        0.17 * stratumPressure +
        0.12 * hotspotPressure +
        0.10 * reflogPressure,
  );
  final structuralStress = clamp01(
    0.26 * machinePressure +
        0.21 * clamp01(mergePressure) +
        0.19 * hotspotPressure +
        0.14 * hiddenPressure +
        0.10 * reflogPressure +
        0.10 * migrationPressure,
  );
  final confidence = clamp01(
    0.34 +
        (hotspots.isNotEmpty ? 0.20 : 0.0) +
        (cadence.isNotEmpty ? 0.18 : 0.0) +
        (strata.isNotEmpty ? 0.14 : 0.0) +
        (metabolism.activeDays > 0 ? 0.14 : 0.0),
  );

  // Spectral observables, if we have them. These are free readouts
  // from the engine's cached basis — no extra Lanczos work, no extra
  // CSR passes. Scattered focus (high entropy) lifts confidence
  // slightly since we're seeing real structure the math can speak
  // to, even when commit cadence is thin.
  final focusEntropy = spectral?.focusEntropyNormalised ?? 0.0;
  final heatTrace = spectral?.heatTraceNormalised ?? 0.0;
  final adjustedConfidence = spectral == null || spectral.basis == null
      ? confidence
      : clamp01(confidence + 0.04 * (1.0 - focusEntropy));

  return RepositoryXrayFlowData(
    gradientMass: gradientMass,
    curlMass: curlMass,
    harmonicMass: harmonicMass,
    structuralStress: structuralStress,
    confidence: adjustedConfidence,
    focusEntropy: focusEntropy,
    heatTrace: heatTrace,
  );
}

_MigrationPair? _detectMigrationPair(List<RepositoryXrayStratumData> strata) {
  for (final older in strata) {
    for (final newer in strata) {
      if (older.pathPrefix == newer.pathPrefix) {
        continue;
      }
      if (older.pathPrefix.split('/').first !=
          newer.pathPrefix.split('/').first) {
        continue;
      }
      final olderDate = DateTime.tryParse(older.lastTouchedAt);
      final newerDate = DateTime.tryParse(newer.lastTouchedAt);
      if (olderDate == null || newerDate == null) {
        continue;
      }
      if (olderDate.isBefore(newerDate) &&
          older.touchCount >= 20 &&
          newer.touchCount >= 20) {
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
  return output
      .split('\n')
      .where((line) => line.trim().startsWith('worktree '))
      .length;
}

int _countRenameCommits(String output) {
  final commits = <String>{};
  String? currentCommit;
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith(_kCommitMarker)) {
      currentCommit = line.substring(_kCommitMarker.length).trim();
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
