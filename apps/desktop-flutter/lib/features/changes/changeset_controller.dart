// Changeset controller — owns the working-tree-dependent async sources of the
// Changes page (per-file impact weights, flow analysis, and the spectral-
// coupling overlay), the cheap fusions that depend on them (the spectral-
// augmented coupling matrix and the per-file dim opacity), and the file
// clustering itself.
//
// The old design ran the sources as independent `addPostFrameCallback` chains
// inside `build()`, each landing in its own `setState`, and re-ran `clusterFiles`
// synchronously in `build()` on every rebuild. A single repo refresh therefore
// triggered up to five full rebuilds in a row, each re-running the O(n²)
// seriation and the file-reading spectral pass on the UI isolate — the "update,
// freeze, update, freeze" jank. This controller coalesces the sources into ONE
// settled derivation per content change, runs the spectral file-reads — and the
// clustering for changesets above [_kClusterIsolateThreshold] — on a background
// isolate (the Logos engine crosses the boundary as a sendable `ClusterEngineView`
// projection, the correlatedness context as plain hunk data), content-keys the
// cluster derivation so it runs once per genuine change rather than once per
// rebuild, and hands the page stable outputs to read.
//
// Lifecycle: owned by `_ChangesPageState`. The page calls [update] with the
// inputs it already gathers from `context` each build (cheap + idempotent), adds
// itself as a listener, and reads the outputs; [notifyListeners] fires once when
// a derivation settles.

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../backend/correlatedness_hunk_sort.dart' show CorrelatednessContext;
import '../../backend/dtos.dart' show FileChangeWeight;
import '../../backend/file_coupling.dart'
    show
        ClusterEngineView,
        FileClusters,
        FileCouplingMatrix,
        FileImpactSignal,
        FileSortGuide,
        clusterFiles,
        computeFlowCoherence;
import '../../backend/git.dart' show fileChangeWeights;
import '../../backend/logos_core.dart' show CharCoupling;
import '../../backend/logos_git.dart' show LogosGit;
import '../../backend/logos_flow.dart'
    show FlowAnalysisResult, analyzeFlowCached;
import '../../backend/logos_git_integrity.dart' show CouplingConstants;
import 'changeset_derivation.dart';

/// Above this many changed files, `clusterFiles` is run in an `Isolate.run`;
/// below it the O(n²) seriation is faster than an isolate spawn + matrix copy,
/// so it runs inline (already off the build path). Tuned to the point where the
/// seriation + hunk-graph Lanczos begins to risk a dropped frame.
const int _kClusterIsolateThreshold = 96;

class ChangesetController extends ChangeNotifier {
  // ── Outputs (read by the page; stable references between derivations) ──
  Map<String, FileChangeWeight> changeWeights = const {};
  Map<String, FlowAnalysisResult> flowResults = const {};
  Map<String, double> flowFragility = const {};
  Map<String, Map<String, double>> spectralCoupling = const {};
  Map<String, double> dimOpacity = const {};
  FileCouplingMatrix? effectiveMatrix;

  /// The clustered file order + grouping. Produced by `clusterFiles` inside an
  /// `Isolate.run`, so the seriation (and its internal hunk-graph Lanczos) never
  /// blocks the UI isolate. Empty until the first derivation settles.
  FileClusters clusters = FileClusters.empty(const []);

  /// Monotonic content versions the page folds into its `ChangesetSignature` so
  /// the cluster cache invalidates exactly when these outputs change content —
  /// never on bare object-identity churn.
  int spectralVersion = 0;
  int weightsVersion = 0;
  int couplingVersion = 0;

  _Inputs? _inputs;
  String? _sourcesKey;
  bool _fuseScheduled = false;
  bool _disposed = false;

  // Cluster inputs pushed from the page (gathered from context each build).
  // The engine is held as the LogosGit itself (memoised + stable, keyed on
  // manifoldRevision) — the sendable ClusterEngineView projection is built once
  // per actual derive, NOT per build, so the cluster key can't churn.
  LogosGit? _engine;
  CorrelatednessContext? _correlatednessContext;
  Set<String> _conflictedPaths = const {};
  Set<String> _includedPaths = const {};
  FileSortGuide _sortGuide = FileSortGuide.relatedProximity;
  bool _inverted = false;
  CouplingConstants _couplingConstants = CouplingConstants.prior;
  String? _clusterKey;

  /// Feed the latest resolved inputs (gathered by the page from `context`).
  /// Cheap and idempotent — a no-op unless the working-tree source key or the
  /// coupling matrix moved. Schedules a single coalesced derivation.
  void update({
    required String repoPath,
    required List<String> paths,
    required FileCouplingMatrix? couplingMatrix,
    required CharCoupling? gyatCoupling,
    required Map<String, double>? statsVolatility,
    required Map<String, double>? statsIntegrity,
  }) {
    final prevMatrix = _inputs?.couplingMatrix;
    _inputs = _Inputs(repoPath, paths, couplingMatrix, gyatCoupling,
        statsVolatility, statsIntegrity);

    // The working-tree sources (weights/flow/spectral) re-run on a change of
    // repo, the changed-path set, or gyat availability — matching (and refining)
    // the old `files.length`-keyed trigger with a content hash of the paths.
    final key = '$repoPath|${paths.length}|${Object.hashAll(paths)}'
        '|gyat=${gyatCoupling != null}';
    final sourcesChanged = key != _sourcesKey;
    final couplingChanged = !identical(couplingMatrix, prevMatrix);
    if (sourcesChanged) {
      _sourcesKey = key;
      // Run the working-tree sources. The fusion + notify happen when they
      // settle. Keyed on [_sourcesKey], NOT a global sequence, so a coupling-
      // matrix change landing mid-flight (a repo switch) re-fuses without
      // cancelling the in-flight weights/flow/spectral pass.
      unawaited(_runSources(key));
    } else if (couplingChanged) {
      // Only the (HEAD-gated) matrix moved — re-fuse with the current sources.
      _scheduleFuse();
    }
  }

  Future<void> _runSources(String key) async {
    final inputs = _inputs;
    if (inputs == null) return;
    final paths = inputs.paths;

    // Weights + flow are independent; the spectral pass chains after flow (it
    // folds flow coherence in) and after gyat. All three replace what were three
    // separate post-frame setState chains.
    final weightsFuture = fileChangeWeights(inputs.repoPath);
    final flowFuture = _runFlow(inputs.repoPath, paths);
    final weightsResult = await weightsFuture;
    final flow = await flowFuture;
    if (_disposed || key != _sourcesKey) return; // superseded by a newer key

    if (weightsResult.ok && weightsResult.data != null) {
      changeWeights = weightsResult.data!;
      weightsVersion++;
    }
    flowResults = flow.results;
    flowFragility = flow.fragility;

    // Spectral overlay — eigenAddress histograms over every changed file. The
    // file reads run on a background isolate (the dominant old freeze).
    final gyat = inputs.gyatCoupling;
    var spec = const <String, Map<String, double>>{};
    if (gyat != null && paths.length >= 2) {
      spec = await spectralCouplingIsolated(
        paths: paths,
        repoRoot: inputs.repoPath,
        coupling: gyat,
        flowResults: flowResults.isNotEmpty ? flowResults : null,
      );
    } else if (flowResults.isNotEmpty) {
      spec = computeFlowCoherence(flowResults);
    }
    if (_disposed || key != _sourcesKey) return;
    spectralCoupling = spec;
    spectralVersion++;

    _fuse();
    if (!_disposed) notifyListeners();
  }

  void _scheduleFuse() {
    if (_fuseScheduled) return;
    _fuseScheduled = true;
    // Microtask-coalesce repeated matrix-only updates within a frame.
    scheduleMicrotask(() {
      _fuseScheduled = false;
      if (_disposed) return;
      _fuse();
      notifyListeners();
    });
  }

  /// Cheap fusions over the current sources — the spectral-augmented matrix and
  /// the dim opacity. Pure; safe to re-run whenever the matrix or spectral
  /// overlay moves, independent of the working-tree source lifecycle.
  void _fuse() {
    final inputs = _inputs;
    if (inputs == null) return;
    final matrix = inputs.couplingMatrix;
    effectiveMatrix = (matrix != null && spectralCoupling.isNotEmpty)
        ? matrix.withSpectral(spectralCoupling)
        : matrix;
    couplingVersion++;
    dimOpacity = computeFileDimOpacity(
      paths: inputs.paths,
      volatility: inputs.statsVolatility,
      integrity: inputs.statsIntegrity,
      coupling: matrix,
    );
    _maybeDeriveClusters();
  }

  /// Push the page's cluster inputs (engine projection, correlatedness context,
  /// sort prefs, included/conflicted sets). Cheap + idempotent; re-derives the
  /// clusters off-thread only when the content key moves.
  void setClusterInputs({
    required LogosGit? engine,
    required CorrelatednessContext? correlatednessContext,
    required Set<String> conflictedPaths,
    required Set<String> includedPaths,
    required FileSortGuide sortGuide,
    required bool inverted,
    required CouplingConstants couplingConstants,
  }) {
    _engine = engine;
    _correlatednessContext = correlatednessContext;
    _conflictedPaths = conflictedPaths;
    _includedPaths = includedPaths;
    _sortGuide = sortGuide;
    _inverted = inverted;
    _couplingConstants = couplingConstants;
    _maybeDeriveClusters();
  }

  void _maybeDeriveClusters() {
    final inputs = _inputs;
    if (inputs == null) return;
    final paths = inputs.paths;
    // Content key over everything clusterFiles consumes. couplingVersion tracks
    // the effective matrix; weightsVersion the impact signals; the rest hash
    // directly. Identity hashes suffice for the engine view + correlatedness
    // context — both reassigned wholesale by their producers.
    final key = '${Object.hashAll(paths)}|$couplingVersion|$weightsVersion'
        '|${_sortGuide.index}|$_inverted'
        '|${Object.hashAll(_includedPaths)}|${Object.hashAll(_conflictedPaths)}'
        '|${_couplingConstants.hashCode}'
        '|${identityHashCode(_correlatednessContext)}'
        '|${_engine?.manifoldRevision ?? -1}';
    if (key == _clusterKey) return;
    _clusterKey = key;
    // Defer so a derive triggered from a build (via setClusterInputs) never
    // calls notifyListeners() synchronously during that build.
    scheduleMicrotask(() {
      if (_disposed || key != _clusterKey) return;
      unawaited(_deriveClusters(key, paths));
    });
  }

  Future<void> _deriveClusters(String key, List<String> paths) async {
    final matrix = effectiveMatrix;
    if (matrix == null || paths.isEmpty) {
      clusters = FileClusters.empty(paths);
      if (!_disposed && key == _clusterKey) notifyListeners();
      return;
    }
    // Impact signals from the (controller-owned) change weights.
    final impactSignals = <String, FileImpactSignal>{
      for (final path in paths)
        path: FileImpactSignal(
          adds: changeWeights[path]?.adds ?? 0,
          dels: changeWeights[path]?.dels ?? 0,
          binary: changeWeights[path]?.binary ?? false,
        ),
    };
    // Every argument crosses the isolate boundary cheaply: FileCouplingMatrix is
    // CSR typed arrays, ClusterEngineView is a graph projection, and the
    // correlatedness context is plain hunk data (its Lanczos recomputes inside
    // the worker, off the UI isolate).
    final engine = _engine;
    final engineView =
        engine == null ? null : ClusterEngineView.of(engine);
    final correlatedness = _correlatednessContext;
    final conflicted = _conflictedPaths;
    final included = _includedPaths;
    final sortGuide = _sortGuide;
    final inverted = _inverted;
    final couplingConstants = _couplingConstants;
    FileClusters run() => clusterFiles(
          paths,
          matrix,
          couplingConstants: couplingConstants,
          sortGuide: sortGuide,
          impactSignals: impactSignals,
          conflictedPaths: conflicted,
          includedPaths: included,
          inverted: inverted,
          correlatednessContext: correlatedness,
          engine: engineView,
        );
    final result = paths.length < _kClusterIsolateThreshold
        ? run()
        : await Isolate.run(run);
    if (_disposed || key != _clusterKey) return;
    clusters = result;
    notifyListeners();
  }

  Future<_FlowBundle> _runFlow(String repoPath, List<String> paths) async {
    final results = <String, FlowAnalysisResult>{};
    final fragility = <String, double>{};
    const concurrency = 8;
    for (var i = 0; i < paths.length; i += concurrency) {
      if (_disposed) break;
      final batch = paths.skip(i).take(concurrency).map((fp) async {
        try {
          final r = await analyzeFlowCached(p.join(repoPath, fp));
          if (r != null) return (fp, r);
        } catch (_) {}
        return null;
      });
      for (final r in await Future.wait(batch)) {
        if (r != null) {
          if (r.$2.spectralGap > 0) fragility[r.$1] = r.$2.spectralGap;
          results[r.$1] = r.$2;
        }
      }
    }
    return _FlowBundle(results, fragility);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _Inputs {
  final String repoPath;
  final List<String> paths;
  final FileCouplingMatrix? couplingMatrix;
  final CharCoupling? gyatCoupling;
  final Map<String, double>? statsVolatility;
  final Map<String, double>? statsIntegrity;
  const _Inputs(this.repoPath, this.paths, this.couplingMatrix,
      this.gyatCoupling, this.statsVolatility, this.statsIntegrity);
}

class _FlowBundle {
  final Map<String, FlowAnalysisResult> results;
  final Map<String, double> fragility;
  const _FlowBundle(this.results, this.fragility);
}
