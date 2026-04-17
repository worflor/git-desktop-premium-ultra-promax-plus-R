import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, setEquals;
import 'package:path/path.dart' as p;

import '../diagnostics/diagnostics_state.dart';
import '../features/diff/diff_models.dart';
import 'ai_context_engine.dart' show LogosDiffusionResult;
import 'dtos.dart' show BlameLineData;
import 'engram_bootstrap.dart' show EngramRuntime;
import 'engram_text_kspace.dart';
import 'file_coupling.dart' show FileCouplingMatrix;
import 'git.dart' show runGitProbe;
import 'logos_branch_orbit.dart'
    show logosTemperatureMultiplierFromOrbit, probeLogosBranchOrbit;
import 'logos_chunks.dart' as chunks;
import 'logos_core.dart' show SpectralBasis;
import 'logos_git.dart';
import 'logos_git_calibration.dart' show LogosAxis, LogosRegime;
import 'logos_git_probe.dart'
    show
        DiffProbe,
        LogosGitProbeBuilder,
        ProbeStats,
        buildDiffProbe,
        diffuseFromProbe,
        looksLikeTestPath;
import 'logos_git_resolver.dart'
    show peekResolvedLogosGitHeadHash, resolveLogosGit;
import 'logos_hunks.dart' as hunks;

enum DiffContextBand { changed, near, far }

const double _kDiffLogosUiTimingMinMs = 8.0;
const int _kLightweightDiffRefreshPathThreshold = 12;
const int _kLightweightDiffRefreshHunkThreshold = 24;
const int _kLightweightDiffRefreshBytesThreshold = 64000;

Future<void> _recordDiffLogosUiTiming({
  required String event,
  required Stopwatch stopwatch,
  String phase = 'compute',
  bool ok = true,
  String? errorCode,
  double minMs = _kDiffLogosUiTimingMinMs,
}) async {
  if (stopwatch.isRunning) {
    stopwatch.stop();
  }
  final durationMs = stopwatch.elapsedMicroseconds / 1000;
  if (!durationMs.isFinite || durationMs < minMs) {
    return;
  }
  await DiagnosticsState.instance.recordUiTiming(
    event: event,
    phase: phase,
    durationMs: durationMs,
    ok: ok,
    errorCode: ok ? null : errorCode,
  );
}

class DiffLogosParsedMetadata {
  final Set<String> touchedPaths;
  final int hunkCount;
  final List<hunks.DiffHunk>? parsedHunks;

  const DiffLogosParsedMetadata({
    required this.touchedPaths,
    required this.hunkCount,
    this.parsedHunks,
  });
}

class DiffLogosRequest {
  final String repositoryPath;
  final String diffText;
  final List<ParsedLine>? parsedLines;
  final DiffLogosParsedMetadata? parsedMetadata;
  final Map<String, Map<String, double>> symbolCoupling;
  final String? revisionRef;
  final FileCouplingMatrix? couplingMatrix;
  final LogosGit? warmEngine;

  const DiffLogosRequest({
    required this.repositoryPath,
    required this.diffText,
    this.parsedLines,
    this.parsedMetadata,
    this.symbolCoupling = const {},
    this.revisionRef,
    this.couplingMatrix,
    this.warmEngine,
  });
}

class DiffLogosShape {
  final LogosRegime regime;
  final double coherence;
  final double temperature;
  final int primaryCount;
  final int sourceCount;
  final int mMatches;
  final int abMatches;
  final int symbolMatches;
  final double? stability;
  final double? sourceAlignment;
  final double? fieldAlignment;
  final double? sourceSurprise;
  final double? fieldSurprise;

  const DiffLogosShape({
    required this.regime,
    required this.coherence,
    required this.temperature,
    required this.primaryCount,
    required this.sourceCount,
    required this.mMatches,
    required this.abMatches,
    required this.symbolMatches,
    this.stability,
    this.sourceAlignment,
    this.fieldAlignment,
    this.sourceSurprise,
    this.fieldSurprise,
  });

  String touchedSummary() {
    return '$primaryCount touched · ${math.max(0, sourceCount - primaryCount)} related';
  }
}

class DiffLogosFileSignal {
  final String path;
  final double importance;
  final bool isPrimary;
  final String? dominantAxis;
  final double? utility;
  final double? integrity;
  final double? transportPull;
  final double? transportedSupport;
  final double? innovationResidual;
  final double? witnessResidual;
  final List<String> witnesses;
  final List<String> sidecars;

  const DiffLogosFileSignal({
    required this.path,
    required this.importance,
    required this.isPrimary,
    this.dominantAxis,
    this.utility,
    this.integrity,
    this.transportPull,
    this.transportedSupport,
    this.innovationResidual,
    this.witnessResidual,
    this.witnesses = const [],
    this.sidecars = const [],
  });
}

class DiffRelatedJump {
  final String path;
  final double priority;
  final String rationale;
  final String? viaPath;
  final String? laneLabel;

  const DiffRelatedJump({
    required this.path,
    required this.priority,
    required this.rationale,
    this.viaPath,
    this.laneLabel,
  });
}

class DiffLogosHunkSignal {
  final String filePath;
  final int hunkIndex;
  final double importance;
  final String? tag;
  final String? headerHint;
  final double? transportPull;
  final double? transportedSupport;
  final double? innovationResidual;
  final double? witnessResidual;
  final List<String> witnessLabels;

  const DiffLogosHunkSignal({
    required this.filePath,
    required this.hunkIndex,
    required this.importance,
    this.tag,
    this.headerHint,
    this.transportPull,
    this.transportedSupport,
    this.innovationResidual,
    this.witnessResidual,
    this.witnessLabels = const [],
  });
}

/// Internal fan-out notifier used by [DiffLogosSession] to expose a
/// publicly-listenable channel without leaking `notifyListeners` as a
/// public API. One instance per granularity level — snapshot (heavy,
/// rare) vs per-file context (light, frequent) — so consumers can
/// subscribe to only the signal they care about. See Grimoire XV
/// (coherency granule) applied at the state-notifier layer.
class _SubNotifier extends ChangeNotifier {
  void fire() {
    if (hasListeners) notifyListeners();
  }
}

class DiffLogosSession extends ChangeNotifier {
  static const DiffLogosShape _emptyShape = DiffLogosShape(
    regime: LogosRegime.uncategorised,
    coherence: 0,
    temperature: 1,
    primaryCount: 0,
    sourceCount: 0,
    mMatches: 0,
    abMatches: 0,
    symbolMatches: 0,
  );

  final DiffLogosFacade _owner;
  final Map<String, _DiffContextEntry> _contextEntriesByPath = {};
  final Set<String> _subscribedFiles = <String>{};
  final Map<String, Future<DiffFileContextPlan>> _contextInflightByPath = {};

  /// Snapshot-level change notifier: fires when the top-level diff
  /// analysis (shape / filesByPath / hunksByKey / relatedJumps /
  /// loading state / error) changes. Rare; one fire per refresh.
  final _SubNotifier _snapshotNotifier = _SubNotifier();

  /// Per-file-context change notifier: fires when any file's
  /// [DiffFileContextPlan] is materialised or invalidated. Frequent —
  /// one fire per async file-context completion during a refresh.
  /// Consumers that only render snapshot data should listen to
  /// [snapshotListenable] instead to avoid rebuilding on every
  /// per-file arrival.
  final _SubNotifier _contextNotifier = _SubNotifier();

  /// Listenable for the snapshot channel. See [_snapshotNotifier].
  Listenable get snapshotListenable => _snapshotNotifier;

  /// Listenable for the per-file-context channel. See
  /// [_contextNotifier].
  Listenable get contextListenable => _contextNotifier;

  Future<void> _ready = Future<void>.value();
  // Per-channel debounce timers. Previously both channels shared a
  // single `_notifyTimer`; `_notifyNow` cancelling that timer would
  // silently drop any pending per-file context fire, and the shell
  // never saw the corresponding `_contextRevision` bump.
  Timer? _contextNotifyTimer;
  int _epoch = 0;
  int _snapshotVersion = 0;
  int _contextRevision = 0;
  bool _disposed = false;
  bool _loading = false;
  String? _error;
  _DiffLogosSnapshot? _snapshot;
  Map<String, String> _contextTokensByPath = const {};

  DiffLogosSession._(this._owner, DiffLogosRequest _);

  bool get loading => _loading;
  String? get error => _error;
  Future<void> get ready => _ready;
  int get snapshotVersion => _snapshotVersion;
  int get contextRevision => _contextRevision;

  String get cacheKey => _snapshot?.cacheKey ?? '';
  DiffLogosShape get shape => _snapshot?.shape ?? _emptyShape;
  Map<String, DiffLogosFileSignal> get filesByPath =>
      _snapshot?.filesByPath ?? const {};
  Map<String, DiffLogosHunkSignal> get hunksByKey =>
      _snapshot?.hunksByKey ?? const {};
  List<DiffRelatedJump> get relatedJumps => _snapshot?.relatedJumps ?? const [];
  LogosDiffusionResult? get logos => _snapshot?.logos;
  Map<String, List<hunks.DiffHunk>> get parsedHunksByFile =>
      _snapshot?.parsedHunksByFile ?? const {};

  static String hunkKey(String filePath, int hunkIndex) =>
      '$filePath#$hunkIndex';

  DiffLogosHunkSignal? hunkFor(String filePath, int hunkIndex) =>
      hunksByKey[hunkKey(filePath, hunkIndex)];

  DiffFileContextPlan? contextPlanFor(String filePath) {
    final entry = _contextEntriesByPath[filePath];
    final token = _contextTokensByPath[filePath];
    if (entry == null || token == null || entry.token != token) {
      return null;
    }
    return entry.plan;
  }

  bool isFileSubscribed(String filePath) => _subscribedFiles.contains(filePath);

  Future<void> refresh(DiffLogosRequest request) {
    final future = _refreshImpl(request);
    _ready = future;
    return future;
  }

  void replaceFileSubscriptions(Iterable<String> filePaths) {
    final next = filePaths.where((path) => path.isNotEmpty).toSet();
    if (setEquals(_subscribedFiles, next)) {
      _queueSubscribedContexts();
      return;
    }
    _subscribedFiles
      ..clear()
      ..addAll(next);
    _queueSubscribedContexts();
  }

  void subscribeFiles(Iterable<String> filePaths) {
    for (final filePath in filePaths) {
      if (filePath.isEmpty) {
        continue;
      }
      _subscribedFiles.add(filePath);
    }
    _queueSubscribedContexts();
  }

  void unsubscribeFiles(Iterable<String> filePaths) {
    for (final filePath in filePaths) {
      _subscribedFiles.remove(filePath);
    }
  }

  Future<DiffFileContextPlan?> ensureFileContext(
    String filePath, {
    String? workingTreeContent,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      await _ready;
      if (_disposed) return null;
    }
    final activeSnapshot = _snapshot;
    if (activeSnapshot == null ||
        !activeSnapshot.parsedLinesByFile.containsKey(filePath)) {
      return contextPlanFor(filePath);
    }
    final token = _contextTokensByPath[filePath];
    final existing = _contextEntriesByPath[filePath];
    if (token != null && existing != null && existing.token == token) {
      return existing.plan;
    }
    final inflight = _contextInflightByPath[filePath];
    if (inflight != null) {
      return inflight;
    }
    final currentEpoch = _epoch;
    final stopwatch = Stopwatch()..start();
    var recordedTiming = false;
    final future = _owner._analyzeFileContextImpl(
      DiffFileContextRequest(
        repositoryPath: activeSnapshot.repositoryPath,
        filePath: filePath,
        diffText: activeSnapshot.diffText,
        parsedLines: activeSnapshot.parsedLinesByFile[filePath] ??
            activeSnapshot.parsedLines,
        session: this,
        revisionRef: activeSnapshot.revisionRef,
        workingTreeContent: workingTreeContent,
      ),
    );
    _contextInflightByPath[filePath] = future;
    try {
      final plan = await future;
      if (_disposed || currentEpoch != _epoch) {
        return null;
      }
      final resolvedToken = _contextTokensByPath[filePath];
      if (resolvedToken != null) {
        _contextEntriesByPath[filePath] = _DiffContextEntry(
          token: resolvedToken,
          plan: plan,
        );
        if (_subscribedFiles.contains(filePath)) {
          _contextRevision++;
          _notifyContextReady();
        }
      }
      return plan;
    } catch (error) {
      recordedTiming = true;
      await _recordDiffLogosUiTiming(
        event: 'diff.logos.file-context',
        stopwatch: stopwatch,
        errorCode: 'diff.logos.file-context_failed',
        ok: false,
      );
      rethrow;
    } finally {
      _contextInflightByPath.remove(filePath);
      if (!_disposed && !recordedTiming) {
        unawaited(
          _recordDiffLogosUiTiming(
            event: 'diff.logos.file-context',
            stopwatch: stopwatch,
          ).catchError((_) => null),
        );
      }
    }
  }

  Future<void> _refreshImpl(DiffLogosRequest request) async {
    final stopwatch = Stopwatch()..start();
    final sameKey = _owner._requestCacheKey(request) == cacheKey;
    if (sameKey && _snapshot != null) {
      _queueSubscribedContexts();
      await _recordDiffLogosUiTiming(
        event: 'diff.logos.refresh.cache-hit',
        stopwatch: stopwatch,
        minMs: 0,
      );
      return;
    }

    final currentEpoch = ++_epoch;
    _loading = true;
    _error = null;
    if (!_disposed) {
      _notifyNow();
    }

    try {
      final snapshot = await _owner._analyzeDiffImpl(
        DiffLogosRequest(
          repositoryPath: request.repositoryPath,
          diffText: request.diffText,
          parsedLines: request.parsedLines,
          parsedMetadata: request.parsedMetadata,
          symbolCoupling: request.symbolCoupling,
          revisionRef: request.revisionRef,
          couplingMatrix: request.couplingMatrix,
          warmEngine: request.warmEngine ?? logos?.engine,
        ),
      );
      if (_disposed || currentEpoch != _epoch) {
        return;
      }
      _snapshot = snapshot;
      _snapshotVersion++;
      _contextTokensByPath = _buildContextTokens(snapshot);
      _error = null;
      _loading = false;
      _queueSubscribedContexts();
      _notifyNow();
      await _recordDiffLogosUiTiming(
        event: 'diff.logos.refresh',
        stopwatch: stopwatch,
      );
    } catch (error) {
      if (_disposed || currentEpoch != _epoch) {
        return;
      }
      _error = error.toString();
      _loading = false;
      _notifyNow();
      await _recordDiffLogosUiTiming(
        event: 'diff.logos.refresh',
        stopwatch: stopwatch,
        errorCode: 'diff.logos.refresh_failed',
        ok: false,
      );
      rethrow;
    }
  }

  Map<String, String> _buildContextTokens(_DiffLogosSnapshot snapshot) {
    final tokens = <String, String>{};
    snapshot.parsedLinesByFile.forEach((filePath, lines) {
      tokens[filePath] = _owner._fileContextToken(
        repositoryPath: snapshot.repositoryPath,
        filePath: filePath,
        parsedLines: lines,
        revisionRef: snapshot.revisionRef,
      );
    });
    return tokens;
  }

  void _queueSubscribedContexts() {
    if (_snapshot == null) {
      return;
    }
    for (final filePath in _subscribedFiles) {
      if (!_contextTokensByPath.containsKey(filePath)) {
        continue;
      }
      if (_contextEntriesByPath[filePath]?.token ==
          _contextTokensByPath[filePath]) {
        continue;
      }
      if (_contextInflightByPath.containsKey(filePath)) {
        continue;
      }
      unawaited(ensureFileContext(filePath).catchError((_) => null));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _contextNotifyTimer?.cancel();
    _contextInflightByPath.clear();
    // super.dispose() asserts `!hasListeners` in debug; attached
    // listeners belong to the shell which detaches in its own
    // dispose. We intentionally leave the sub-notifiers un-disposed
    // here to avoid racing the shell's detach during a combined
    // teardown — they are owned by this session and are GC-eligible
    // alongside it once the shell releases its listeners.
    super.dispose();
  }

  void _notifyNow() {
    if (_disposed) {
      return;
    }
    // Snapshot-level fires are always accompanied by a bump of
    // `_snapshotVersion`, so the snapshot channel is the truth; the
    // session-level `notifyListeners()` stays so any remaining
    // legacy listeners keep working. Grimoire XV: consumers that
    // only care about the snapshot attach to [snapshotListenable]
    // instead of the whole session.
    //
    // If a debounced context fire is pending, flush it eagerly as
    // part of this broadcast — the snapshot refresh always observes
    // whatever context-revision progress has already been made, and
    // losing it here (as the previous shared-timer design did) caused
    // context-only listeners to miss per-file completions that were
    // batched into a cancelled timer.
    final hadPendingContext = _contextNotifyTimer != null;
    _contextNotifyTimer?.cancel();
    _contextNotifyTimer = null;
    _snapshotNotifier.fire();
    if (hadPendingContext) _contextNotifier.fire();
    notifyListeners();
  }

  void _notifyContextReady() {
    if (_disposed || _contextNotifyTimer != null) {
      return;
    }
    _contextNotifyTimer = Timer(const Duration(milliseconds: 12), () {
      _contextNotifyTimer = null;
      if (_disposed) {
        return;
      }
      // Fire the per-file-context channel ONLY. Consumers listening
      // to [snapshotListenable] don't wake up on per-file context
      // completions — which is the whole point of the split.
      _contextNotifier.fire();
      notifyListeners();
    });
  }
}

class DiffFoldedRange {
  final int hiddenCount;
  final int? startLine;
  final int? endLine;

  const DiffFoldedRange({
    required this.hiddenCount,
    this.startLine,
    this.endLine,
  });
}

class DiffFileContextPlan {
  final Set<int> visibleFastKeys;
  final Map<int, DiffContextBand> bandByFastKey;
  final Map<String, double> importanceByHunk;
  final Map<String, String> semanticTags;
  final Map<String, String> headerHints;
  final Map<int, DiffLineResidualSignal> residualByFastKey;
  final List<DiffFoldedRange> foldedRanges;

  const DiffFileContextPlan({
    required this.visibleFastKeys,
    required this.bandByFastKey,
    required this.importanceByHunk,
    required this.semanticTags,
    required this.headerHints,
    required this.residualByFastKey,
    required this.foldedRanges,
  });
}

class DiffLineResidualSignal {
  final double importance;
  final double transportPull;
  final double transportedSupport;
  final double innovationResidual;
  final double witnessResidual;

  const DiffLineResidualSignal({
    this.importance = 0.0,
    this.transportPull = 0.0,
    this.transportedSupport = 0.0,
    this.innovationResidual = 0.0,
    this.witnessResidual = 0.0,
  });

  DiffLineResidualSignal scaled(double factor) => DiffLineResidualSignal(
        importance: (importance * factor).clamp(0.0, 1.0).toDouble(),
        transportPull: (transportPull * factor).clamp(0.0, 1.0).toDouble(),
        transportedSupport:
            (transportedSupport * factor).clamp(0.0, 1.0).toDouble(),
        innovationResidual:
            (innovationResidual * factor).clamp(0.0, 1.0).toDouble(),
        witnessResidual: (witnessResidual * factor).clamp(0.0, 1.0).toDouble(),
      );

  double get transportSignal =>
      math.max(transportPull, transportedSupport).clamp(0.0, 1.0).toDouble();

  double get residualSignal =>
      math.max(innovationResidual, witnessResidual).clamp(0.0, 1.0).toDouble();

  double get semanticSignal => math
      .max(importance, math.max(transportSignal, residualSignal))
      .clamp(0.0, 1.0)
      .toDouble();
}

class DiffFileContextRequest {
  final String repositoryPath;
  final String filePath;
  final String diffText;
  final List<ParsedLine> parsedLines;
  final DiffLogosSession? session;
  final String? revisionRef;
  final String? workingTreeContent;

  const DiffFileContextRequest({
    required this.repositoryPath,
    required this.filePath,
    required this.diffText,
    required this.parsedLines,
    this.session,
    this.revisionRef,
    this.workingTreeContent,
  });
}

class _DiffContextEntry {
  final String token;
  final DiffFileContextPlan plan;

  const _DiffContextEntry({
    required this.token,
    required this.plan,
  });
}

class _DiffLogosSnapshot {
  final String cacheKey;
  final DiffLogosShape shape;
  final Map<String, DiffLogosFileSignal> filesByPath;
  final Map<String, DiffLogosHunkSignal> hunksByKey;
  final List<DiffRelatedJump> relatedJumps;
  final LogosDiffusionResult? logos;
  final Map<String, List<hunks.DiffHunk>> parsedHunksByFile;
  final List<ParsedLine> parsedLines;
  final Map<String, List<ParsedLine>> parsedLinesByFile;
  final String repositoryPath;
  final String diffText;
  final String? revisionRef;

  const _DiffLogosSnapshot({
    required this.cacheKey,
    required this.shape,
    required this.filesByPath,
    required this.hunksByKey,
    required this.relatedJumps,
    required this.logos,
    required this.parsedHunksByFile,
    required this.parsedLines,
    required this.parsedLinesByFile,
    required this.repositoryPath,
    required this.diffText,
    required this.revisionRef,
  });
}

/// A file node's position in the engine's spectral basis, already
/// reduced to the three quantities a visualization cares about:
/// first-three non-trivial eigenmode coordinates (x, y, z) and a
/// normalized participation entropy ([reach]) measuring how many
/// modes the node occupies. All four numbers come from the SAME
/// cached `LogosGit.spectralBasis()` so every surface that renders
/// this node sees it in the same geometric frame.
///
/// Null when the engine's graph was too small for a basis
/// ([kDefaultSpectralMinNodes]); callers should have a deterministic
/// fallback.
class DiffPinnedSpectral {
  /// Mode-1 eigenvector coordinate (Fiedler). Normalized so the
  /// unit-sphere scale matches the magnitude painters expect —
  /// values land in roughly [-1, 1] for most files in a medium-
  /// sized repo.
  final double x;

  /// Mode-2 coordinate.
  final double y;

  /// Mode-3 coordinate.
  final double z;

  /// Spectral participation entropy normalized to [0, 1]. 1 = the
  /// node touches every mode equally (maximal architectural reach);
  /// 0 = mass collapses to a single mode (a tightly-localized node).
  final double reach;

  const DiffPinnedSpectral({
    required this.x,
    required this.y,
    required this.z,
    required this.reach,
  });
}

class DiffPinnedRelatedFile {
  final String path;
  final double score;
  final bool semantic;
  final bool coupled;
  /// File's position in the engine's spectral basis. Null when the
  /// repo graph is too small or the file isn't a graph node.
  final DiffPinnedSpectral? spectral;

  const DiffPinnedRelatedFile({
    required this.path,
    required this.score,
    this.semantic = false,
    this.coupled = false,
    this.spectral,
  });
}

class DiffPinnedTransportEdge {
  final String sourcePath;
  final String targetPath;
  final double pull;
  final String? laneLabel;
  /// Target file's spectral position, same basis as the anchor's.
  /// Lets the tangent pane pose each transport target in its real
  /// engine-geometric coordinates rather than a path hash.
  final DiffPinnedSpectral? targetSpectral;

  const DiffPinnedTransportEdge({
    required this.sourcePath,
    required this.targetPath,
    required this.pull,
    this.laneLabel,
    this.targetSpectral,
  });
}

class DiffPinnedRhymePreview {
  final int displayIndex;
  final String filePath;
  final String text;
  final int? lineNumber;
  // Full 64-bit simhash of the rhyme's ParsedLine. Needed by the
  // manifold's Eigenshape perspective, where PCA of the local
  // simhash cloud turns physical distance into actual code-shape
  // similarity. Defaults to 0 so legacy callers stay valid during
  // rollout; rhymes with simHash 0 just fall back to overview
  // positioning in Eigenshape.
  final int simHash;

  const DiffPinnedRhymePreview({
    required this.displayIndex,
    required this.filePath,
    required this.text,
    this.lineNumber,
    this.simHash = 0,
  });
}

class _PinnedRhymeCandidate {
  final int displayIndex;
  final ParsedLine line;
  final int hamming;

  const _PinnedRhymeCandidate({
    required this.displayIndex,
    required this.line,
    required this.hamming,
  });
}

class DiffPinnedLineRequest {
  final String? repositoryPath;
  final String filePath;
  final ParsedLine line;
  final List<ParsedLine> displayLines;
  final int displayIndex;
  final FileCouplingMatrix? couplingMatrix;
  final String? revisionRef;
  final String? queryPathOverride;
  final LogosGit? warmEngine;
  final DiffLogosSession? session;
  final BlameLineData? blame;

  const DiffPinnedLineRequest({
    required this.repositoryPath,
    required this.filePath,
    required this.line,
    required this.displayLines,
    required this.displayIndex,
    this.couplingMatrix,
    this.revisionRef,
    this.queryPathOverride,
    this.warmEngine,
    this.session,
    this.blame,
  });
}

class DiffPinnedContextModel {
  final ParsedLine line;
  final String? wellName;
  final double? wellDistance;
  final List<DiffPinnedRelatedFile> relatedFiles;
  final List<int> rhymeDisplayIdxs;
  final List<DiffPinnedRhymePreview> rhymePreviews;
  final BlameLineData? blame;
  final String? dominantAxis;
  final List<String> witnesses;
  final List<DiffPinnedTransportEdge> transportEdges;
  final List<String> integrityReasons;
  /// Anchor file's position in the engine's spectral basis. When
  /// non-null, visualizers can pose the pinned line's node in its
  /// real geometric coordinates and read its reach for a complexity
  /// signal. Null on small repos where no basis is computed.
  final DiffPinnedSpectral? anchorSpectral;

  const DiffPinnedContextModel({
    required this.line,
    required this.wellName,
    required this.wellDistance,
    required this.relatedFiles,
    required this.rhymeDisplayIdxs,
    required this.rhymePreviews,
    required this.blame,
    required this.dominantAxis,
    required this.witnesses,
    required this.transportEdges,
    required this.integrityReasons,
    this.anchorSpectral,
  });

  bool get hasAnything =>
      wellName != null ||
      relatedFiles.isNotEmpty ||
      rhymeDisplayIdxs.isNotEmpty ||
      rhymePreviews.isNotEmpty ||
      blame != null ||
      (dominantAxis?.isNotEmpty ?? false) ||
      witnesses.isNotEmpty ||
      transportEdges.isNotEmpty ||
      integrityReasons.isNotEmpty;
}

/// Project a file's graph-node id into the engine's cached spectral
/// basis. Returns the first three non-trivial modal coordinates
/// (modes 1, 2, 3 — mode 0 is near-constant on connected graphs and
/// carries no positional information) plus a normalized spectral
/// entropy of the 1-hot source distribution. All four quantities
/// come straight from the already-computed Lanczos decomposition —
/// no extra SpMVs, just O(k) work per node.
///
/// Returns null when the basis has fewer than 4 modes or the node
/// id is out of range — callers fall back to a deterministic hash.
/// Runs [LogosGit.gatherEvidence] on a background isolate so the
/// UI thread doesn't block on its diffusion pass. Falls back to a
/// sync call if the engine isn't sendable across the isolate
/// boundary.
Future<LogosEvidenceQueryResult?> _gatherEvidenceOffThread({
  required LogosGit engine,
  required Map<String, double> focusWeights,
  required Map<String, String> axisLabelByPath,
  required double t,
  required Set<String> excludePaths,
  required int detailBudget,
}) async {
  try {
    return await Isolate.run<LogosEvidenceQueryResult?>(
      () => engine.gatherEvidence(
        focusWeights: focusWeights,
        axisLabelByPath: axisLabelByPath,
        t: t,
        excludePaths: excludePaths,
        detailBudget: detailBudget,
      ),
      debugName: 'gatherEvidence',
    );
  } catch (_) {
    return engine.gatherEvidence(
      focusWeights: focusWeights,
      axisLabelByPath: axisLabelByPath,
      t: t,
      excludePaths: excludePaths,
      detailBudget: detailBudget,
    );
  }
}

DiffPinnedSpectral? _projectSpectralForNode(
  SpectralBasis basis,
  int nodeId, {
  double entropyTemperature = 1.0,
}) {
  if (nodeId < 0 || nodeId >= basis.n || basis.k < 4) return null;

  // Amplify raw eigenvector components — each one is ~1/sqrt(n) in
  // magnitude (unit-norm across n nodes). Multiplying by sqrt(n)
  // brings coords into roughly [-1, 1] for typical repos.
  final amplify = math.sqrt(basis.n.toDouble());
  final x = basis.eigenvectors[1 * basis.n + nodeId] * amplify;
  final y = basis.eigenvectors[2 * basis.n + nodeId] * amplify;
  final z = basis.eigenvectors[3 * basis.n + nodeId] * amplify;

  // Entropy on a 1-hot source — how evenly this node's mass spreads
  // across the modes after a unit of thermal decay. log(k) is the
  // maximum; normalize so callers get [0, 1].
  final rho = Float64List(basis.n);
  rho[nodeId] = 1.0;
  final s = basis.spectralEntropy(rho, entropyTemperature);
  final sMax = math.log(basis.k.toDouble());
  final reach = sMax > 0 ? (s / sMax).clamp(0.0, 1.0).toDouble() : 0.0;

  return DiffPinnedSpectral(
    x: x.clamp(-1.2, 1.2).toDouble(),
    y: y.clamp(-1.2, 1.2).toDouble(),
    z: z.clamp(-1.2, 1.2).toDouble(),
    reach: reach,
  );
}

class DiffLogosFacade {
  DiffLogosFacade._();

  static final DiffLogosFacade instance = DiffLogosFacade._();

  DiffLogosSession createSession(DiffLogosRequest request) {
    return DiffLogosSession._(this, request);
  }

  Future<DiffLogosSession> openSession(DiffLogosRequest request) async {
    final session = createSession(request);
    await session.refresh(request);
    return session;
  }

  Future<DiffPinnedContextModel> analyzePinnedLine(
      DiffPinnedLineRequest request) async {
    final line = request.line;
    final repoPath = request.repositoryPath;
    final queryPath =
        request.queryPathOverride ?? line.filePath ?? request.filePath;
    final nearest = <DiffPinnedRelatedFile>[];
    String? wellName;
    double? wellDistance;
    LogosGit? engine = request.warmEngine;
    if (engine == null && repoPath != null) {
      engine = await resolveLogosGit(repoPath);
    }
    if (line.text.trim().isNotEmpty && engine != null) {
      try {
        final encoder = await EngramRuntime.instance.mainEncoder();
        if (encoder != null) {
          final kv = encodeProse(line.text, encoder);
          if (kv != null && kv.vocabHits >= 3) {
            wellName = kv.well?.name;
            wellDistance = kv.well?.rawDistance;
            final table = engine.perFileKVectors;
            if (!table.isEmpty) {
              final top = nearestRowsInTable(
                table,
                qRe: kv.kRe,
                qIm: kv.kIm,
                topK: 6,
                minSimilarity: 0.35,
              );
              final self = queryPath;
              for (final match in top) {
                if (match.path == self) continue;
                nearest.add(
                  DiffPinnedRelatedFile(
                    path: match.path,
                    score: match.similarity,
                    semantic: true,
                  ),
                );
                if (nearest.length >= 5) break;
              }
            }
          }
        }
      } catch (_) {
        // Best-effort: pinned context should never fail the diff shell.
      }
    }

    final rhymes = <int>[];
    final rhymePreviews = <DiffPinnedRhymePreview>[];
    final srcHash = line.simHash;
    if (srcHash != 0) {
      final candidates = <_PinnedRhymeCandidate>[];
      for (var i = 0; i < request.displayLines.length; i++) {
        if (i == request.displayIndex) continue;
        final h = request.displayLines[i].simHash;
        if (h == 0) continue;
        final hamming = ParsedLine.hamming64(srcHash, h);
        if (hamming <= 8) {
          candidates.add(
            _PinnedRhymeCandidate(
              displayIndex: i,
              line: request.displayLines[i],
              hamming: hamming,
            ),
          );
        }
      }
      if (candidates.isNotEmpty) {
        const clusterRadius = 6;
        final selected = <_PinnedRhymeCandidate>[];
        candidates.sort((a, b) {
          final hammingCompare = a.hamming.compareTo(b.hamming);
          if (hammingCompare != 0) return hammingCompare;
          final sourceDistanceA = (a.displayIndex - request.displayIndex).abs();
          final sourceDistanceB = (b.displayIndex - request.displayIndex).abs();
          return sourceDistanceA.compareTo(sourceDistanceB);
        });
        for (final candidate in candidates) {
          final isNeighbour = selected.any(
            (picked) =>
                (picked.line.filePath ?? request.filePath) ==
                    (candidate.line.filePath ?? request.filePath) &&
                (picked.displayIndex - candidate.displayIndex).abs() <=
                    clusterRadius,
          );
          if (isNeighbour) continue;
          selected.add(candidate);
          if (selected.length >= 8) break;
        }
        for (final candidate in selected) {
          final target = candidate.line;
          rhymes.add(candidate.displayIndex);
          rhymePreviews.add(
            DiffPinnedRhymePreview(
              displayIndex: candidate.displayIndex,
              filePath: target.filePath ?? request.filePath,
              text: target.text.trim(),
              lineNumber: target.lineNumNew ?? target.lineNumOld,
              simHash: target.simHash,
            ),
          );
        }
      }
    }

    final related = <DiffPinnedRelatedFile>[...nearest];
    final matrix = request.couplingMatrix;
    final selfPath = queryPath;
    if (matrix != null && matrix.containsPath(selfPath)) {
      final entries = matrix.jaccardEntriesOf(selfPath).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in entries.take(5)) {
        if (entry.value <= 0) continue;
        final existingIndex = related.indexWhere((r) => r.path == entry.key);
        if (existingIndex >= 0) {
          final existing = related[existingIndex];
          related[existingIndex] = DiffPinnedRelatedFile(
            path: existing.path,
            score: math.max(existing.score, entry.value),
            semantic: existing.semantic,
            coupled: true,
          );
        } else {
          related.add(
            DiffPinnedRelatedFile(
              path: entry.key,
              score: entry.value,
              coupled: true,
            ),
          );
        }
      }
    }
    related.sort((a, b) => b.score.compareTo(a.score));

    String? dominantAxis;
    final witnesses = <String>[];
    final transportEdges = <DiffPinnedTransportEdge>[];
    final integrityReasons = <String>[];
    if (engine != null) {
      try {
        final evidence = engine.gatherEvidence(
          focusWeights: {selfPath: 1.0},
          excludePaths: const {},
          detailBudget: 12,
        );
        final selfResidual = evidence?.residualByPath[selfPath];
        dominantAxis = selfResidual?.dominantAxis ??
            request.session?.filesByPath[selfPath]?.dominantAxis;
        if (selfResidual != null) {
          witnesses.addAll([
            for (final witness in selfResidual.witnesses.take(2))
              formatLogosEvidenceWitness(
                witness,
                includeNote: true,
                includeSource: true,
              ),
          ]);
        }
        if (evidence != null) {
          for (final edge in evidence.transport.frontierEdges) {
            if (edge.sourcePath != selfPath && edge.targetPath != selfPath) {
              continue;
            }
            transportEdges.add(
              DiffPinnedTransportEdge(
                sourcePath: edge.sourcePath,
                targetPath: edge.targetPath,
                pull: edge.pull,
                laneLabel: edge.laneLabel,
              ),
            );
            if (transportEdges.length >= 2) break;
          }
        }
        integrityReasons.addAll(
          (engine.stats.integrityReasonsByPath[selfPath] ?? const <String>[])
              .take(2),
        );
      } catch (_) {
        // Best-effort.
      }
    }

    // Spectral augmentation — everything past this point is cheap
    // O(k·n) reads against the engine's already-cached Lanczos
    // basis. Each file's spectral coords land in the SAME basis as
    // the anchor's so downstream visualizations can treat them as
    // coordinates in one geometric frame.
    SpectralBasis? basis;
    if (engine != null) {
      try {
        basis = engine.spectralBasis();
      } catch (_) {
        basis = null;
      }
    }
    DiffPinnedSpectral? anchorSpectral;
    final relatedWithSpectral = <DiffPinnedRelatedFile>[];
    final transportWithSpectral = <DiffPinnedTransportEdge>[];
    if (basis != null && engine != null) {
      final selfId = engine.pathToId[selfPath];
      if (selfId != null) {
        anchorSpectral = _projectSpectralForNode(basis, selfId);
      }
      for (final r in related) {
        final id = engine.pathToId[r.path];
        final sp = id == null ? null : _projectSpectralForNode(basis, id);
        relatedWithSpectral.add(
          DiffPinnedRelatedFile(
            path: r.path,
            score: r.score,
            semantic: r.semantic,
            coupled: r.coupled,
            spectral: sp,
          ),
        );
      }
      for (final e in transportEdges) {
        final targetPath = e.targetPath == selfPath ? e.sourcePath : e.targetPath;
        final id = engine.pathToId[targetPath];
        final sp = id == null ? null : _projectSpectralForNode(basis, id);
        transportWithSpectral.add(
          DiffPinnedTransportEdge(
            sourcePath: e.sourcePath,
            targetPath: e.targetPath,
            pull: e.pull,
            laneLabel: e.laneLabel,
            targetSpectral: sp,
          ),
        );
      }
    } else {
      relatedWithSpectral.addAll(related);
      transportWithSpectral.addAll(transportEdges);
    }

    return DiffPinnedContextModel(
      line: line,
      wellName: wellName,
      wellDistance: wellDistance,
      relatedFiles: relatedWithSpectral.take(6).toList(growable: false),
      rhymeDisplayIdxs: rhymes,
      rhymePreviews: rhymePreviews,
      blame: request.blame,
      dominantAxis: dominantAxis,
      witnesses: witnesses,
      transportEdges: transportWithSpectral,
      integrityReasons: integrityReasons,
      anchorSpectral: anchorSpectral,
    );
  }

  Future<_DiffLogosSnapshot> _analyzeDiffImpl(DiffLogosRequest request) async {
    final parsed = request.parsedLines ?? parseUnifiedDiff(request.diffText);
    final touchedPaths = request.parsedMetadata?.touchedPaths ??
        {
          for (final line in parsed)
            if ((line.filePath ?? '').isNotEmpty) line.filePath!,
        };
    final parsedLinesByFile = <String, List<ParsedLine>>{};
    for (final line in parsed) {
      final filePath = line.filePath;
      if (filePath == null || filePath.isEmpty) {
        continue;
      }
      (parsedLinesByFile[filePath] ??= <ParsedLine>[]).add(line);
    }
    final parsedHunks = request.parsedMetadata?.parsedHunks ??
        hunks.parseDiffHunks(request.diffText);
    final parsedHunksByFile = <String, List<hunks.DiffHunk>>{};
    for (final hunk in parsedHunks) {
      (parsedHunksByFile[hunk.filePath] ??= <hunks.DiffHunk>[]).add(hunk);
    }
    final engineBase =
        request.warmEngine ?? await resolveLogosGit(request.repositoryPath);
    final engine = engineBase == null
        ? null
        : (request.symbolCoupling.isEmpty
            ? engineBase
            : engineBase.withSymbolEdges(request.symbolCoupling));
    final useLightweightSnapshot = engine != null &&
        _shouldUseLightweightDiffSnapshot(
          touchedPaths: touchedPaths,
          parsedHunks: parsedHunks,
          diffText: request.diffText,
        );
    final probe = engine == null
        ? DiffProbe.empty
        : useLightweightSnapshot
            ? _buildLightweightDiffProbe(
                engine: engine,
                touchedPaths: touchedPaths,
              )
            : await buildDiffProbe(
                repoPath: request.repositoryPath,
                diffText: request.diffText,
                engine: engine,
              );
    var effectiveT = probe.suggestedTemperature ?? 1.0;
    if (!useLightweightSnapshot) {
      final orbit = await probeLogosBranchOrbit(request.repositoryPath);
      effectiveT *= logosTemperatureMultiplierFromOrbit(orbit);
    }

    LogosEvidenceQueryResult? evidence;
    AxisAttribution? attribution;
    List<RelevanceScore> scores = const [];
    LogosDiffusionResult? logos;
    if (engine != null && probe.sourceWeights.isNotEmpty) {
      if (useLightweightSnapshot) {
        scores = engine.diffuse(probe.primaryPaths, t: effectiveT);
        if (scores.isNotEmpty) {
          logos = LogosDiffusionResult(
            engine: engine,
            probe: probe,
            scores: scores,
            resolvedT: effectiveT,
          );
        }
      } else {
        final symbolPaths = <String>{
          for (final path in engine.symbolEdges.keys)
            if (!engine.pathToId.containsKey(path)) path,
        };
        final axisLabels = <String, String>{
          for (final entry in probe.sourceWeights.entries)
            entry.key: _classifyAxis(
              entry.key,
              probe,
              symbolPaths: symbolPaths,
            ).name,
        };
        evidence = await _gatherEvidenceOffThread(
          engine: engine,
          focusWeights: probe.sourceWeights,
          axisLabelByPath: axisLabels,
          t: effectiveT,
          excludePaths: probe.primaryPaths,
          detailBudget: 32,
        );
        attribution = evidence?.supportAttribution;
        if (evidence != null && evidence.ranked.isNotEmpty) {
          scores = [
            for (final score in evidence.ranked)
              RelevanceScore(
                score.path,
                score.utility > 0
                    ? score.utility
                    : (score.support * score.integrity * 0.05),
              ),
          ];
        } else if (attribution != null) {
          scores = attribution.combined;
        } else {
          scores = diffuseFromProbe(
            engine: engine,
            probe: probe,
            temperatureOverride: effectiveT,
          );
        }
        if (scores.isNotEmpty) {
          logos = LogosDiffusionResult(
            engine: engine,
            probe: probe,
            scores: scores,
            resolvedT: effectiveT,
            attribution: attribution,
            evidence: evidence,
          );
        }
      }
    }

    final fileSignals = <String, DiffLogosFileSignal>{};
    final residualByPath =
        evidence?.residualByPath ?? const <String, LogosResidualView>{};
    for (final path in touchedPaths) {
      final residual = residualByPath[path];
      fileSignals[path] = DiffLogosFileSignal(
        path: path,
        importance: (residual?.utility ?? (probe.sourceWeights[path] ?? 1.0))
            .clamp(0.0, 1.0),
        isPrimary: true,
        dominantAxis: residual?.dominantAxis ?? LogosAxis.primary.name,
        utility: residual?.utility,
        integrity: residual?.integrity ?? engine?.stats.integrityByPath[path],
        transportPull: residual?.transportPull,
        transportedSupport: residual?.transportedSupport,
        innovationResidual: residual?.innovationResidual,
        witnessResidual: residual?.witnessResidual,
        witnesses: [
          for (final witness
              in residual?.witnesses.take(2) ?? const <LogosEvidenceWitness>[])
            formatLogosEvidenceWitness(
              witness,
              includeNote: true,
              includeSource: true,
            ),
        ],
        sidecars: [
          for (final sidecar
              in residual?.sidecars.take(2) ?? const <LogosMetricSidecar>[])
            formatLogosMetricSidecar(sidecar, includeNote: false),
        ],
      );
    }
    if (evidence != null) {
      for (final score in evidence.ranked.take(6)) {
        final residual = residualByPath[score.path];
        fileSignals[score.path] = DiffLogosFileSignal(
          path: score.path,
          importance: (residual?.utility ?? score.utility).clamp(0.0, 1.0),
          isPrimary: probe.primaryPaths.contains(score.path),
          dominantAxis: residual?.dominantAxis ?? score.dominantAxis,
          utility: residual?.utility ?? score.utility,
          integrity: residual?.integrity ?? score.integrity,
          transportPull: residual?.transportPull ?? score.transportPull,
          transportedSupport:
              residual?.transportedSupport ?? score.transportedSupport,
          innovationResidual:
              residual?.innovationResidual ?? score.innovationResidual,
          witnessResidual: residual?.witnessResidual ?? score.witnessResidual,
          witnesses: [
            for (final witness
                in (residual?.witnesses ?? score.witnesses).take(2))
              formatLogosEvidenceWitness(
                witness,
                includeNote: true,
                includeSource: true,
              ),
          ],
          sidecars: [
            for (final sidecar
                in (residual?.sidecars ?? score.sidecars).take(2))
              formatLogosMetricSidecar(sidecar, includeNote: false),
          ],
        );
      }
    } else if (scores.isNotEmpty) {
      final maxPhi = scores.fold<double>(
        0.0,
        (current, score) => math.max(current, score.phi),
      );
      for (final score in scores.take(6)) {
        final existing = fileSignals[score.path];
        fileSignals[score.path] = DiffLogosFileSignal(
          path: score.path,
          importance: maxPhi <= 0
              ? (existing?.importance ?? 0.0)
              : (score.phi / maxPhi).clamp(0.0, 1.0),
          isPrimary:
              existing?.isPrimary ?? probe.primaryPaths.contains(score.path),
          dominantAxis: existing?.dominantAxis,
          utility: score.phi,
          integrity: existing?.integrity,
          transportPull: existing?.transportPull,
          transportedSupport: existing?.transportedSupport,
          innovationResidual: existing?.innovationResidual,
          witnessResidual: existing?.witnessResidual,
          witnesses: existing?.witnesses ?? const <String>[],
          sidecars: existing?.sidecars ?? const <String>[],
        );
      }
    }

    final hunkSignals = <String, DiffLogosHunkSignal>{};
    if (parsedHunks.isNotEmpty && !useLightweightSnapshot) {
      final fileEvidence = evidence == null
          ? null
          : hunks.buildHunkFileEvidenceFromResiduals(
              evidence.residualByPath,
              touchedPaths: touchedPaths,
            );
      final ranked = await hunks.rankHunksByPhiAsync(
        hunks: parsedHunks,
        logosEngine: engine,
        fileEvidence: fileEvidence,
      );
      final maxPhiByFile = <String, double>{};
      for (final ranking in ranked.rankings) {
        final current = maxPhiByFile[ranking.hunk.filePath] ?? 0.0;
        if (ranking.phi > current) {
          maxPhiByFile[ranking.hunk.filePath] = ranking.phi;
        }
      }
      for (final ranking in ranked.rankings) {
        final hunk = ranking.hunk;
        final maxPhi = maxPhiByFile[hunk.filePath] ?? 1.0;
        final tag = _classifyHunkTag(hunk);
        hunkSignals[DiffLogosSession.hunkKey(hunk.filePath, hunk.hunkIndex)] =
            DiffLogosHunkSignal(
          filePath: hunk.filePath,
          hunkIndex: hunk.hunkIndex,
          importance:
              maxPhi <= 0 ? 0.0 : (ranking.phi / maxPhi).clamp(0.0, 1.0),
          tag: tag,
          headerHint: tag == null ? null : _headerHintForTag(tag),
          transportPull: ranking.transportPull,
          transportedSupport: ranking.transportedSupport,
          innovationResidual: ranking.innovationResidual,
          witnessResidual: ranking.witnessResidual,
          witnessLabels: ranking.fileWitnesses.take(2).toList(growable: false),
        );
      }
    }

    final relatedJumps = <DiffRelatedJump>[
      if (evidence != null)
        for (final step in evidence.inquiryPlan.steps.take(3))
          DiffRelatedJump(
            path: step.path,
            priority: step.priority,
            rationale: step.rationale,
            viaPath: step.viaPath,
            laneLabel: step.laneLabel,
          ),
    ];
    if (relatedJumps.isEmpty && evidence != null) {
      for (final edge in evidence.transport.frontierEdges.take(3)) {
        relatedJumps.add(
          DiffRelatedJump(
            path: edge.targetPath,
            priority: edge.pull,
            rationale: edge.note ?? 'transport frontier',
            viaPath: edge.sourcePath,
            laneLabel: edge.laneLabel,
          ),
        );
      }
    } else if (relatedJumps.isEmpty && scores.isNotEmpty) {
      for (final score in scores) {
        if (probe.primaryPaths.contains(score.path)) {
          continue;
        }
        relatedJumps.add(
          DiffRelatedJump(
            path: score.path,
            priority: score.phi,
            rationale: 'diffusion pull',
          ),
        );
        if (relatedJumps.length >= 3) {
          break;
        }
      }
    }

    final shape = DiffLogosShape(
      regime: LogosRegime.classify(
        fileCount: probe.stats.primaryCount,
        coherence: probe.stats.coherence,
      ),
      coherence: probe.stats.coherence.clamp(0.0, 1.0),
      temperature: effectiveT,
      primaryCount: probe.stats.primaryCount,
      sourceCount: probe.sourceWeights.length,
      mMatches: probe.stats.mMatches,
      abMatches: probe.stats.abMatches,
      symbolMatches: probe.stats.symbolMatches,
      stability: evidence?.stability,
      sourceAlignment: evidence?.sourceAlignment,
      fieldAlignment: evidence?.fieldAlignment,
      sourceSurprise: evidence?.sourceSurprise,
      fieldSurprise: evidence?.fieldSurprise,
    );

    return _DiffLogosSnapshot(
      cacheKey: _requestCacheKey(request),
      shape: shape,
      filesByPath: fileSignals,
      hunksByKey: hunkSignals,
      relatedJumps: relatedJumps,
      logos: logos,
      parsedHunksByFile: parsedHunksByFile,
      parsedLines: parsed,
      parsedLinesByFile: parsedLinesByFile,
      repositoryPath: request.repositoryPath,
      diffText: request.diffText,
      revisionRef: request.revisionRef,
    );
  }

  Future<DiffFileContextPlan> _analyzeFileContextImpl(
      DiffFileContextRequest request) async {
    // Pre-extract primitives before any async gap so nothing outside this
    // function's locals gets captured implicitly (historical isolate bug:
    // closure held `request`, which reached a DiffLogosSession / ChangeNotifier
    // that cannot cross isolate boundaries; also the isolate spawn cost on
    // Windows dwarfed the actual compute, so we now run on the main thread).
    final filePath = request.filePath;
    final repositoryPath = request.repositoryPath;
    final revisionRef = request.revisionRef;
    final workingTreeContent = request.workingTreeContent;
    final diffText = request.diffText;
    final session = request.session;

    final fileLines = <ParsedLine>[
      for (final line in request.parsedLines)
        if ((line.filePath ?? filePath) == filePath) line,
    ];
    if (fileLines.isEmpty) {
      return const DiffFileContextPlan(
        visibleFastKeys: <int>{},
        bandByFastKey: <int, DiffContextBand>{},
        importanceByHunk: <String, double>{},
        semanticTags: <String, String>{},
        headerHints: <String, String>{},
        residualByFastKey: <int, DiffLineResidualSignal>{},
        foldedRanges: <DiffFoldedRange>[],
      );
    }

    final content = workingTreeContent ??
        await _loadFileContent(
          repositoryPath: repositoryPath,
          filePath: filePath,
          revisionRef: revisionRef,
        );
    final sourceChunks = content == null || content.isEmpty
        ? const <chunks.SourceChunk>[]
        : chunks.chunkSourceFile(content);
    final fileHunks = session?.parsedHunksByFile[filePath] ??
        hunks.parseDiffHunksForFile(diffText, filePath);
    final sessionSignalsByHunkIndex = <int, DiffLogosHunkSignal>{};
    if (session != null) {
      for (var i = 0; i < fileHunks.length; i++) {
        final signal = session.hunkFor(filePath, i);
        if (signal != null) {
          sessionSignalsByHunkIndex[i] = signal;
        }
      }
    }
    return _buildDiffFileContextPlan(
      filePath: filePath,
      fileLines: fileLines,
      sourceChunks: sourceChunks,
      fileHunks: fileHunks,
      sessionSignalsByHunkIndex: sessionSignalsByHunkIndex,
    );
  }

  String _requestCacheKey(DiffLogosRequest request) {
    final symbolKey = _symbolCouplingKey(request.symbolCoupling);
    final revision = request.revisionRef ?? '';
    final couplingHead = request.couplingMatrix?.headHash ?? '';
    final engineKey = request.warmEngine == null
        ? (peekResolvedLogosGitHeadHash(
              request.repositoryPath,
              coupling: request.couplingMatrix,
            ) ??
            '')
        : identityHashCode(request.warmEngine).toString();
    return '${request.repositoryPath}|${request.diffText.hashCode}|$symbolKey|$revision|$couplingHead|$engineKey';
  }

  String _fileContextToken({
    required String repositoryPath,
    required String filePath,
    required List<ParsedLine> parsedLines,
    required String? revisionRef,
  }) {
    final digest = Object.hashAll([
      for (final line in parsedLines)
        Object.hash(
          line.fastKey,
          line.kind.index,
          line.lineNumOld,
          line.lineNumNew,
        ),
    ]);
    return '$repositoryPath|$filePath|${revisionRef ?? ''}|$digest|${parsedLines.length}';
  }

  String _symbolCouplingKey(Map<String, Map<String, double>> symbolCoupling) {
    if (symbolCoupling.isEmpty) return '';
    final outer = symbolCoupling.keys.toList()..sort();
    final buf = StringBuffer();
    for (final key in outer) {
      buf.write(key);
      final inner = symbolCoupling[key]!;
      final innerKeys = inner.keys.toList()..sort();
      for (final other in innerKeys) {
        buf
          ..write('>')
          ..write(other)
          ..write('=')
          ..write(inner[other]!.toStringAsFixed(3));
      }
      buf.write(';');
    }
    return buf.toString();
  }
}

bool _shouldUseLightweightDiffSnapshot({
  required Set<String> touchedPaths,
  required List<hunks.DiffHunk> parsedHunks,
  required String diffText,
}) {
  // The lightweight path exists to cap wall-time on *big* diffs where
  // gatherEvidence's O(k·n) cost actually matters. Tiny diffs were
  // previously routed here too, but that path skips gatherEvidence
  // entirely and breaks related-file surfacing on single-file edits
  // (the user's most common case), so the tiny-ceiling guard is off.
  if (touchedPaths.length >= _kLightweightDiffRefreshPathThreshold) {
    return true;
  }
  if (parsedHunks.length >= _kLightweightDiffRefreshHunkThreshold) {
    return true;
  }
  return diffText.length >= _kLightweightDiffRefreshBytesThreshold;
}

DiffProbe _buildLightweightDiffProbe({
  required LogosGit engine,
  required Set<String> touchedPaths,
}) {
  final primaryPaths = <String>{
    for (final path in touchedPaths)
      if (path.isNotEmpty) path,
  };
  if (primaryPaths.isEmpty) {
    return DiffProbe.empty;
  }
  final coherence = engine.coherence(primaryPaths);
  final suggestedTemperature = const LogosGitProbeBuilder().adaptiveTemperature(
    primaryPaths: primaryPaths,
    coherence: coherence,
  );
  var symbolMatches = 0;
  for (final path in primaryPaths) {
    if (engine.pathToId.containsKey(path)) {
      continue;
    }
    if (engine.symbolEdges[path]?.isNotEmpty ?? false) {
      symbolMatches++;
    }
  }
  return DiffProbe(
    sourceWeights: {
      for (final path in primaryPaths) path: 1.0,
    },
    primaryPaths: primaryPaths,
    suggestedTemperature: suggestedTemperature,
    stats: ProbeStats(
      primaryCount: primaryPaths.length,
      mMatches: 0,
      abMatches: 0,
      mSymbols: 0,
      coherence: coherence,
      symbolMatches: symbolMatches,
    ),
  );
}

DiffFileContextPlan _buildDiffFileContextPlan({
  required String filePath,
  required List<ParsedLine> fileLines,
  required List<chunks.SourceChunk> sourceChunks,
  required List<hunks.DiffHunk> fileHunks,
  required Map<int, DiffLogosHunkSignal> sessionSignalsByHunkIndex,
}) {
  if (fileLines.isEmpty) {
    return const DiffFileContextPlan(
      visibleFastKeys: <int>{},
      bandByFastKey: <int, DiffContextBand>{},
      importanceByHunk: <String, double>{},
      semanticTags: <String, String>{},
      headerHints: <String, String>{},
      residualByFastKey: <int, DiffLineResidualSignal>{},
      foldedRanges: <DiffFoldedRange>[],
    );
  }

  final chunkWindows = _buildChunkWindows(
    fileHunks: fileHunks,
    sourceChunks: sourceChunks,
  );
  final visible = <int>{};
  final bands = <int, DiffContextBand>{};
  final folded = <DiffFoldedRange>[];
  final importanceByHunk = <String, double>{};
  final semanticTags = <String, String>{};
  final headerHints = <String, String>{};
  final residualByFastKey = <int, DiffLineResidualSignal>{};

  final byHunk = <int, List<ParsedLine>>{};
  for (final line in fileLines) {
    byHunk.putIfAbsent(line.hunkIndex, () => <ParsedLine>[]).add(line);
    if (line.kind != LineKind.context) {
      visible.add(line.fastKey);
      bands[line.fastKey] = DiffContextBand.changed;
    }
  }

  final sortedHunkIds = byHunk.keys.toList()..sort();
  for (final hunkId in sortedHunkIds) {
    final lines = byHunk[hunkId]!;
    if (lines.isEmpty) {
      continue;
    }
    final fileHunkIndex = _fileHunkIndexFor(
      fileLines,
      hunkId: hunkId,
    );
    final sessionSignal = sessionSignalsByHunkIndex[fileHunkIndex];
    final hunk = hunks.DiffHunk(
      filePath: filePath,
      hunkIndex: fileHunkIndex,
      header: lines
          .firstWhere(
            (line) => line.kind == LineKind.hunk,
            orElse: () => lines.first,
          )
          .text
          .trim(),
      body: lines.map((line) => line.text).join('\n'),
      oldStart: lines.first.lineNumOld ?? 0,
      newStart: lines.first.lineNumNew ?? 0,
      additions: lines.where((line) => line.kind == LineKind.added).length,
      deletions: lines.where((line) => line.kind == LineKind.deleted).length,
    );
    final tag = sessionSignal?.tag ?? _classifyHunkTag(hunk);
    final spec = _contextSpecForTag(tag);
    final chunkWindow = chunkWindows[fileHunkIndex];
    final changedIdxs = <int>[
      for (var i = 0; i < lines.length; i++)
        if (lines[i].kind == LineKind.added ||
            lines[i].kind == LineKind.deleted)
          i,
    ];
    final hunkKey = DiffLogosSession.hunkKey(filePath, fileHunkIndex);
    importanceByHunk[hunkKey] = sessionSignal?.importance ?? 0.0;
    final baseResidual = sessionSignal == null
        ? null
        : DiffLineResidualSignal(
            importance: sessionSignal.importance,
            transportPull: sessionSignal.transportPull ?? 0.0,
            transportedSupport: sessionSignal.transportedSupport ?? 0.0,
            innovationResidual: sessionSignal.innovationResidual ?? 0.0,
            witnessResidual: sessionSignal.witnessResidual ?? 0.0,
          );
    if (tag != null) {
      semanticTags[hunkKey] = tag;
      headerHints[hunkKey] =
          sessionSignal?.headerHint ?? _headerHintForTag(tag);
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (baseResidual != null &&
          (line.kind == LineKind.added || line.kind == LineKind.deleted)) {
        residualByFastKey[line.fastKey] = baseResidual;
      }
      if (line.kind != LineKind.context) {
        continue;
      }
      final minDelta = changedIdxs.isEmpty
          ? 999
          : changedIdxs
              .map((idx) => (idx - i).abs())
              .reduce((a, b) => math.min(a, b));
      final withinChunk = chunkWindow == null
          ? false
          : (line.lineNumNew != null &&
              line.lineNumNew! >= chunkWindow.start &&
              line.lineNumNew! <= chunkWindow.end);
      if (minDelta <= spec.nearRadius || (spec.expandToChunk && withinChunk)) {
        visible.add(line.fastKey);
        bands[line.fastKey] = DiffContextBand.near;
        if (baseResidual != null) {
          final scale = spec.expandToChunk && withinChunk ? 0.80 : 0.68;
          residualByFastKey[line.fastKey] = baseResidual.scaled(scale);
        }
      } else if (minDelta <= spec.farRadius) {
        visible.add(line.fastKey);
        bands[line.fastKey] = DiffContextBand.far;
        if (baseResidual != null) {
          residualByFastKey[line.fastKey] = baseResidual.scaled(0.36);
        }
      }
    }
  }

  var hiddenCount = 0;
  int? hiddenStart;
  int? hiddenEnd;
  for (final line in fileLines) {
    final isVisible =
        visible.contains(line.fastKey) || line.kind != LineKind.context;
    if (isVisible) {
      if (hiddenCount > 0) {
        folded.add(
          DiffFoldedRange(
            hiddenCount: hiddenCount,
            startLine: hiddenStart,
            endLine: hiddenEnd,
          ),
        );
        hiddenCount = 0;
        hiddenStart = null;
        hiddenEnd = null;
      }
      continue;
    }
    hiddenCount++;
    hiddenStart ??= line.lineNumNew ?? line.lineNumOld;
    hiddenEnd = line.lineNumNew ?? line.lineNumOld;
  }
  if (hiddenCount > 0) {
    folded.add(
      DiffFoldedRange(
        hiddenCount: hiddenCount,
        startLine: hiddenStart,
        endLine: hiddenEnd,
      ),
    );
  }

  return DiffFileContextPlan(
    visibleFastKeys: visible,
    bandByFastKey: bands,
    importanceByHunk: importanceByHunk,
    semanticTags: semanticTags,
    headerHints: headerHints,
    residualByFastKey: residualByFastKey,
    foldedRanges: folded,
  );
}

LogosAxis _classifyAxis(
  String path,
  DiffProbe probe, {
  Set<String> symbolPaths = const {},
}) {
  if (probe.primaryPaths.contains(path)) return LogosAxis.primary;
  if (symbolPaths.contains(path)) return LogosAxis.symbol;
  if (probe.sourceWeights.containsKey(path)) {
    return _pathLooksLikeMirrorOf(path, probe.primaryPaths)
        ? LogosAxis.ab
        : LogosAxis.m;
  }
  return LogosAxis.graph;
}

bool _pathLooksLikeMirrorOf(String candidate, Set<String> primary) {
  if (!looksLikeTestPath(candidate)) return false;
  final candidateBase = p
      .basenameWithoutExtension(candidate)
      .replaceAll(RegExp(r'(_test|_spec|\.test|\.spec)$'), '');
  for (final path in primary) {
    if (candidateBase == p.basenameWithoutExtension(path)) {
      return true;
    }
  }
  return false;
}

String? _classifyHunkTag(hunks.DiffHunk hunk) {
  final body = hunk.body.toLowerCase();
  final filePath = hunk.filePath.toLowerCase();
  final categories = <String>{};

  final changedLines = body
      .split('\n')
      .where((line) => line.startsWith('+') || line.startsWith('-'))
      .where((line) => !line.startsWith('+++') && !line.startsWith('---'))
      .map((line) => line.substring(1).trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  final changedBody = changedLines.join('\n');
  final importOnly = changedLines.isNotEmpty &&
      changedLines.every((line) =>
          line.startsWith('import ') ||
          line.startsWith('export ') ||
          line.startsWith('part ') ||
          line.startsWith('// ignore') ||
          line.startsWith('@') ||
          line == '{' ||
          line == '}' ||
          line == ',' ||
          line == ';');

  if (looksLikeTestPath(filePath) ||
      RegExp(r'\b(test|expect|assert|group|describe|it)\b')
          .hasMatch(changedBody)) {
    categories.add('test');
  }
  if (RegExp(r'\b(class|enum|extension|typedef|mixin|interface)\b')
      .hasMatch(changedBody)) {
    categories.add('type');
  }
  if (RegExp(r'\b(if|else|switch|case|for|while|try|catch|throw|return)\b')
      .hasMatch(changedBody)) {
    categories.add('flow');
  }
  if (RegExp(r'\b(const|final|static)\b').hasMatch(changedBody) &&
      RegExp("[\"']|\\b\\d+(?:\\.\\d+)?\\b").hasMatch(changedBody)) {
    categories.add('const');
  }
  if (RegExp(r'\b[A-Za-z_][A-Za-z0-9_<>,? ]+\(').hasMatch(changedBody) ||
      RegExp(r'^\s*(public|private|protected)\b', multiLine: true)
          .hasMatch(changedBody) ||
      RegExp(r'^\s*(Future|Stream|void|int|double|String|bool)\b',
              multiLine: true)
          .hasMatch(changedBody)) {
    categories.add('API');
  }
  if (importOnly ||
      (changedLines.length >= 4 &&
          changedLines.every((line) =>
              line.startsWith('//') ||
              line.startsWith('import ') ||
              line.startsWith('export ') ||
              line.startsWith('@') ||
              line == '{' ||
              line == '}' ||
              RegExp(r'^[A-Za-z0-9_<>,?]+\s*[),;]?$').hasMatch(line)))) {
    categories.add('mechanical');
  }

  if (categories.isEmpty) return null;
  if (categories.length == 1) return categories.first;
  if (categories.contains('test')) return 'test';
  if (categories.contains('type')) return 'type';
  if (categories.contains('flow')) return 'flow';
  if (categories.contains('API')) return 'API';
  if (categories.contains('const')) return 'const';
  if (categories.contains('mechanical')) return 'mechanical';
  return 'mixed';
}

String _headerHintForTag(String tag) {
  switch (tag) {
    case 'API':
      return 'surface';
    case 'flow':
      return 'branch';
    case 'const':
      return 'threshold';
    case 'type':
      return 'type';
    case 'test':
      return 'test';
    case 'mechanical':
      return 'mechanical';
    case 'mixed':
      return 'mixed';
  }
  return tag;
}

class _ContextSpec {
  final int nearRadius;
  final int farRadius;
  final bool expandToChunk;

  const _ContextSpec({
    required this.nearRadius,
    required this.farRadius,
    required this.expandToChunk,
  });
}

_ContextSpec _contextSpecForTag(String? tag) {
  switch (tag) {
    case 'API':
      return const _ContextSpec(
          nearRadius: 5, farRadius: 10, expandToChunk: true);
    case 'flow':
      return const _ContextSpec(
          nearRadius: 6, farRadius: 12, expandToChunk: true);
    case 'const':
      return const _ContextSpec(
          nearRadius: 2, farRadius: 5, expandToChunk: false);
    case 'type':
      return const _ContextSpec(
          nearRadius: 5, farRadius: 11, expandToChunk: true);
    case 'test':
      return const _ContextSpec(
          nearRadius: 6, farRadius: 12, expandToChunk: true);
    case 'mechanical':
      return const _ContextSpec(
          nearRadius: 1, farRadius: 2, expandToChunk: false);
    case 'mixed':
      return const _ContextSpec(
          nearRadius: 6, farRadius: 12, expandToChunk: true);
  }
  return const _ContextSpec(nearRadius: 3, farRadius: 7, expandToChunk: false);
}

class _ChunkWindow {
  final int start;
  final int end;

  const _ChunkWindow({
    required this.start,
    required this.end,
  });
}

Map<int, _ChunkWindow> _buildChunkWindows({
  required List<hunks.DiffHunk> fileHunks,
  required List<chunks.SourceChunk> sourceChunks,
}) {
  if (sourceChunks.isEmpty) return const {};
  final result = <int, _ChunkWindow>{};
  for (final hunk in fileHunks) {
    final anchor = hunk.newStart > 0 ? hunk.newStart : hunk.oldStart;
    chunks.SourceChunk? best;
    var bestDistance = 1 << 30;
    for (final chunk in sourceChunks) {
      if (anchor >= chunk.startLine && anchor <= chunk.endLine) {
        best = chunk;
        break;
      }
      final distance = anchor < chunk.startLine
          ? chunk.startLine - anchor
          : anchor - chunk.endLine;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = chunk;
      }
    }
    if (best == null) continue;
    result[hunk.hunkIndex] = _ChunkWindow(
      start: best.startLine,
      end: best.endLine,
    );
  }
  return result;
}

int _fileHunkIndexFor(
  List<ParsedLine> fileLines, {
  required int hunkId,
}) {
  final seen = <int>{};
  var ordinal = 0;
  for (final line in fileLines) {
    if (!seen.add(line.hunkIndex)) continue;
    if (line.hunkIndex == hunkId) return ordinal;
    ordinal++;
  }
  return 0;
}

Future<String?> _loadFileContent({
  required String repositoryPath,
  required String filePath,
  String? revisionRef,
}) async {
  try {
    if (revisionRef != null && revisionRef.trim().isNotEmpty) {
      final result = await runGitProbe(
        repositoryPath,
        ['show', '${revisionRef.trim()}:${filePath.replaceAll('\\', '/')}'],
      );
      if (result.exitCode == 0) {
        return result.stdout.toString();
      }
    }
    final ioPath =
        p.join(repositoryPath, filePath.replaceAll('/', p.separator));
    final file = File(ioPath);
    if (await file.exists()) {
      return file.readAsString();
    }
  } catch (_) {
    return null;
  }
  return null;
}
