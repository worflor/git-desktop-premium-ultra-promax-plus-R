import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app/preferences_state.dart';
import '../../ui/motion.dart';
import '../../ui/material_surface.dart';
import '../../ui/form_controls.dart';
import '../../ui/status_view.dart';
import '../../ui/tokens.dart';
import '../../backend/diff_logos_facade.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../backend/file_coupling.dart' show FileCouplingMatrix;
import '../../backend/lru_cache.dart';
import '../../components/icons/app_icons.dart';
import '../../diagnostics/diagnostics_state.dart';
import 'diff_document.dart';
import 'diff_models.dart';
import 'edit_units.dart';
import 'manifold/manifold_pane.dart';
import 'motion_policy.dart';
import 'patch_engine.dart';

//
// The diff row has a fixed left-edge composition: a 2px ribbon (staged
// state / keyboard focus indicator), then a 16px stage-sigil cell. Overlays
// that float above the list — the sticky hunk header, and anything a
// future layer adds — must reserve this same width as pointer-transparent
// so the sigil below still receives paint-drag and tap events.
//
// Centralising here prevents the class of bug where changing row layout
// silently breaks overlay pass-through: any change to [_kRibbonWidth] or
// [_kStageCellWidth] propagates to every consumer automatically.

const double _kRibbonWidth = 2.0;
const double _kStageCellWidth = 16.0;
const double _kLeftReserveWidth = _kRibbonWidth + _kStageCellWidth;
const double _kLineItemExtent = 18.0;

class _AgeRange {
  final DateTime min;
  final DateTime max;
  const _AgeRange({required this.min, required this.max});
}

class _HunkHeader {
  final int lineIndex;
  final String filePath;
  final int fileHunkIndex;
  final String label;

  /// Additions + deletions, kept separate so the inline hint reads
  /// `+12 −4` rather than just a fused `16`. Total churn is their
  /// sum and drives the hot-zone strength.
  final int additions;
  final int deletions;
  int get churn => additions + deletions;
  const _HunkHeader(
    this.lineIndex,
    this.filePath,
    this.fileHunkIndex,
    this.label,
    this.additions,
    this.deletions,
  );
}

class _TrailViewState {
  final String diffContent;
  final List<ParsedLine> lines;
  final List<_HunkHeader> hunks;
  final Set<int> pairedAddFastKeys;
  final Map<int, EditUnit> unitByFastKey;
  final double maxLineWidth;

  const _TrailViewState({
    required this.diffContent,
    required this.lines,
    required this.hunks,
    required this.pairedAddFastKeys,
    required this.unitByFastKey,
    required this.maxLineWidth,
  });
}

String _formatBlameTime(String timestamp) {
  final seconds = int.tryParse(timestamp);
  if (seconds == null) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final now = DateTime.now();
  final days = now.difference(date).inDays;
  if (days < 1) return 'today';
  if (days < 30) return '${days}d';
  if (days < 365) return '${(days / 30).floor()}mo';
  return '${(days / 365).floor()}y';
}

String _diffDisplayName(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? filePath : parts.last;
}

String? _diffDisplayDirectory(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length <= 1) {
    return null;
  }
  return parts.sublist(0, parts.length - 1).join('/');
}

class DiffShell extends StatefulWidget {
  final String filePath;
  final String? diffContent;
  final DiffDocument? document;
  final bool loading;
  final String? error;
  final AppTokens tokens;
  final String? repositoryPath;
  final int? jumpToLineIndex;
  final int jumpToLineRequestId;
  final bool showFileHeader;

  /// When true, line-level staging gestures are enabled. Toggles are applied
  /// live to the index via `git apply --cached`. The parent is notified via
  /// [onStagingApplied] after a successful apply so it can refresh its diff
  /// and working-tree status.
  final bool enableStaging;

  /// Called after each successful live apply so the host can refresh its
  /// diff view and status. Not called on failure.
  final VoidCallback? onStagingApplied;

  /// Optional file coupling matrix — enables the "coupled with" row
  /// in the pinned-line context panel (click a line to pin).
  /// When null, that section is omitted; everything else in the
  /// panel still works (K-nearest, well, blame, rhymes-in-diff).
  final FileCouplingMatrix? couplingMatrix;
  final Map<String, Map<String, double>> symbolCoupling;
  final String? revisionRef;
  final DiffLogosSession? logosSession;
  final ValueChanged<String>? onOpenRelatedPath;
  /// Fires with the file path of a newly-pinned line. Parents that
  /// host a side-list of files wire this to keep their selection
  /// scrolled alongside the user's focus — pinning a line is an
  /// explicit "this is what I'm looking at" signal.
  final ValueChanged<String>? onPinnedFileFocused;
  /// When non-null, renders a `<` back button in the toolbar's
  /// leading slot (before the search toggle). Wired by parents that
  /// maintain a navigation stack — clicking it pops one layer. Null
  /// when there's nothing to go back to, so the button disappears.
  final VoidCallback? onNavigateBack;
  final String? toolbarFilePath;
  final String? toolbarLabel;
  final String? toolbarTooltip;
  final VoidCallback? toolbarOnTap;
  final bool? toolbarActive;

  const DiffShell({
    super.key,
    required this.filePath,
    required this.tokens,
    this.diffContent,
    this.document,
    this.loading = false,
    this.error,
    this.repositoryPath,
    this.jumpToLineIndex,
    this.jumpToLineRequestId = 0,
    this.showFileHeader = true,
    this.enableStaging = false,
    this.onStagingApplied,
    this.couplingMatrix,
    this.symbolCoupling = const {},
    this.revisionRef,
    this.logosSession,
    this.onOpenRelatedPath,
    this.onPinnedFileFocused,
    this.onNavigateBack,
    this.toolbarFilePath,
    this.toolbarLabel,
    this.toolbarTooltip,
    this.toolbarOnTap,
    this.toolbarActive,
  });

  @override
  State<DiffShell> createState() => _DiffShellState();
}

class _DiffShellState extends State<DiffShell> {
  static const int _kAnimatedDiffMaxChangedLines = 24;
  static const int _kAnimatedDiffMaxPayloadBytes = 4 * 1024;
  static const Duration _kInitialFrameCaptureWindow =
      Duration(milliseconds: 1500);
  static const Duration _kBlameHoverDelay = Duration(milliseconds: 180);
  static const int _kModeAMaxChangedLines = 15000;
  static const int _kModeAMaxPayloadBytes = 3 * 1024 * 1024;
  static const Duration _kScrollFrameCaptureQuietWindow =
      Duration(milliseconds: 280);

  final _searchCtrl = TextEditingController();
  String _searchTerm = '';
  bool _searchVisible = false;
  final _scrollCtrl = ScrollController();
  final _hScrollCtrl = ScrollController();
  double _maxLineWidth = 800.0;
  final Stopwatch _sessionStopwatch = Stopwatch();
  final List<double> _scrollFpsSamples = [];
  final List<double> _frameTotalSamples = [];
  final List<double> _frameBuildSamples = [];
  final List<double> _frameRasterSamples = [];
  // Blame cache keyed by file path → line number → entry.
  // Supports multi-file diffs where each file has its own blame.
  //
  // Bounded: [_kBlameCacheMaxFiles] entries. Without a cap, hovering
  // across a 50-file multi-file diff accumulated every file's line-by-
  // line blame indefinitely (≈ MB-scale for large files). Eviction is
  // LRU via re-insertion — a hovered file's entry is touched on read
  // in [_blameFor].
  static const int _kBlameCacheMaxFiles = 16;
  final Map<String, Map<int, BlameLineData>> _blameByFile = {};
  final Set<String> _blameFetchedFiles = {};
  final Set<String> _blameFetchingFiles = {};
  final Set<String> _blamePrewarmingFiles = {};
  final Set<String> _blameUnavailableFiles = {};
  /// Shared per-key in-flight futures so concurrent `_loadBlame`
  /// callers join one fetch. Without this the pinned-context
  /// refresh could resolve against an empty cache mid-fetch and
  /// commit a null blame.
  final Map<String, Future<void>> _blameLoadFutures = {};
  bool _sessionFlushed = false;
  double? _sessionFirstPaintMs;
  DateTime? _lastScrollEventAt;
  String? _sessionDiffId;
  bool _sessionSearchActivated = false;
  bool _useAnimatedTextMode = false;
  int _sessionChangedLines = 0;
  int _sessionPayloadBytes = 0;
  String? _currentDiffContent;
  DiffDocument? _currentDocument;
  List<ParsedLine> _displayLines = const [];

  /// Index map for O(1) fastKey → display index lookup. Rebuilt
  /// whenever [_displayLines] changes. Keyed on `fastKey` (integer
  /// content hash) rather than object identity because `ParsedLine`
  /// instances can be reconstructed from the same underlying bytes
  /// during a refresh (stage toggle, search edit, replacement-pair
  /// recompute) — an identity-keyed map would silently miss those
  /// reconstructed lines and the scroll-gravity snap would degrade
  /// to a no-op without throwing. Matches the same migration the
  /// rest of the shell made from stagingKey strings to fastKey ints.
  Map<int, int> _displayLineIndex = const {};

  /// Per-hunk display-row index — parallel to [_hunks], with the same
  /// length. Entry `i` is the index of `_hunks[i]`'s header line in
  /// `_displayLines` (NOT in `_lines` — paired-add filtering makes those
  /// coordinate spaces drift). Consulted by the sticky hunk header so
  /// its "topIdx vs hunk boundary" comparison stays in the display
  /// coordinate space that `_scrollCtrl.offset` actually indexes into.
  /// -1 marks "hunk's header line was filtered from display" (shouldn't
  /// happen for hunks, but defensive).
  List<int> _hunkDisplayRows = const [];

  /// Fast filter: fastKeys of `added` lines that are the new-side of a
  /// replace pair and should be hidden from display (the fused row shows
  /// at the delete position and carries the add via `unit.newLines.first`).
  /// Derived once in `_recomputeUnits`; read in the source-line filter
  /// and keyboard-cursor skip logic. A `Set<int>` is strictly faster than
  /// a unit-map-with-kind-check at the call sites, and the delete side's
  /// add partner is already reachable via `_unitByFastKey[deleteKey]`.
  Set<int> _pairedAddFastKeys = const {};

  /// Fast lookup: [ParsedLine.fastKey] → the EditUnit that contains it.
  /// The EditUnit layer is the canonical semantic view (replace, move,
  /// insert, delete, context, hunk, meta). Patch engine continues to
  /// operate on raw ParsedLines via `_lines`; units are a *view* with
  /// stable integer identity.
  Map<int, EditUnit> _unitByFastKey = const {};

  Timer? _blameHoverTimer;
  Timer? _sessionFlushTimer;
  late final TimingsCallback _frameTimingsCallback;

  // Wear map (blame heatmap)
  bool _wearMapVisible = false;

  // Paper Trail (file history)
  bool _trailVisible = false;
  List<FileHistoryEntry> _trailHistory = const [];
  bool _trailLoading = false;
  String? _trailSelectedHash;
  String? _originalDiffContent;
  _TrailViewState? _trailNowView;
  // Resolved file path AT the currently-selected trail commit. Tracks the
  // file's pre-rename name when viewing historical stops so diff/blame
  // queries use the correct path for that point in time.
  String? _trailSelectedPath;
  Timer? _trailScrubDebounce;
  int _trailLoadSeq = 0;
  final LinkedHashMap<String, _TrailViewState> _trailViewCache =
      LinkedHashMap<String, _TrailViewState>();
  int? _hoveredLine; // the lineNumNew being hovered

  // Hunk navigation
  List<_HunkHeader> _hunks = [];
  Map<int, _HunkHeader> _hunkHeaderByFastKey = const {};
  List<ParsedLine> _lines = [];

  // Preference snapshots, refreshed every build so async callbacks
  // (blame hover timer) can read them without a BuildContext.
  bool _reduceMotion = false;
  double _motionRate = 1.0;
  bool _instantBlameHover = false;

  static const Duration _kApplyDebounce = Duration(milliseconds: 250);
  static const Duration _kTrailScrubDebounce = Duration(milliseconds: 32);
  static const int _kTrailViewCacheLimit = 40;
  final FocusNode _stagingFocus = FocusNode(debugLabel: 'DiffShellStaging');
  Timer? _applyDebounce;
  bool _applying = false;
  String? _stagingError;
  int? _keyboardLineIndex; // index into _lines
  int? _lastToggledLineIndex; // for shift-range anchor (into _lines)

  // Paint-drag (press-and-drag over the stage column to paint multiple lines)
  bool _paintActive = false;
  bool _paintTargetStaged = false;
  // int-keyed — [ParsedLine.fastKey]. Paint-drag can sweep across dozens
  // of lines per frame; an integer Set skips the per-add string hash.
  final Set<int> _paintedFastKeys = {};

  // Scroll gravity — when scroll ends within this many lines of a hunk header,
  // snap to the hunk so reading never settles on a hunk boundary. Re-entrancy
  // guard prevents the snap animation from re-triggering itself.
  static const double _kGravityLineRadius = 3.0;
  bool _gravitySnapping = false;
  /// True between a programmatic `_jumpToDisplayIndex` call and the
  /// ScrollEndNotification that fires when its animation finishes.
  /// Gravity-snap is user-intent-only; the jump already landed where
  /// the caller asked, so snapping to the nearest hunk would yank it
  /// back. Consumed by the first post-jump ScrollEnd.
  bool _programmaticScrollInFlight = false;

  // Temporal marks — where the reader left off, per file. LRU-bounded so
  // long sessions can't leak unbounded state. Backed by a LinkedHashMap so
  // insertion order doubles as recency order: on every read/write we move
  // the entry to the back, and any overflow past [_kTemporalMarkCap] gets
  // evicted from the front. Survives within the app session only (not
  // persisted). When a file is reopened, scroll restores to its last-visited
  // unit and that unit briefly pulses so the reader sees "you're back."
  static const int _kTemporalMarkCap = 256;
  // Unit ids are now 64-bit SplitMix64 hashes (see EditUnit.id in
  // edit_units.dart and ParsedLine.fastKey in diff_models.dart). The value
  // type switched from String to int so reopen-lookups don't carry string
  // allocation cost, and equality is a single-cycle integer compare.
  static final LinkedHashMap<String, int> _lastVisitedByFile =
      LinkedHashMap<String, int>();

  static void _touchTemporalMark(String scopeKey, int unitId) {
    _lastVisitedByFile.remove(scopeKey);
    _lastVisitedByFile[scopeKey] = unitId;
    while (_lastVisitedByFile.length > _kTemporalMarkCap) {
      _lastVisitedByFile.remove(_lastVisitedByFile.keys.first);
    }
  }

  static int? _readTemporalMark(String scopeKey) {
    final v = _lastVisitedByFile.remove(scopeKey);
    if (v == null) return null;
    _lastVisitedByFile[scopeKey] = v; // promote on read
    return v;
  }

  int? _restoredPulseUnitId;
  Timer? _restoredPulseTimer;
  bool _temporalRestoreDone = false;

  // Adaptive motion LOD — while the viewport is actively moving, new rows
  // entering view skip peripheral/reveal animations. This keeps the
  // expressive layer's cost bounded during fast scroll and lets telemetry
  // see real diff-render frames instead of animation-storm frames. Flag is
  // a plain field (no setState) so scroll doesn't rebuild the list; it's
  // sampled at the moment itemBuilder constructs a new row.
  bool _scrolling = false;
  Timer? _scrollIdleTimer;
  static const Duration _kScrollIdleDelay = Duration(milliseconds: 180);

  // AR(2) scroll engram — Verlet kinematic ring of the last three scroll
  // offsets (x[n-2], x[n-1], x[n]). From the 2nd-order central difference
  // we reconstruct velocity and acceleration each scroll tick and project
  // the next position via symplectic Euler. When the prediction indicates
  // the reader is DECELERATING into rest (|v| small, sign(v)·sign(a)<0),
  // we kick off blame fetch ahead of the hover that's about to happen,
  // hiding the ~180ms hover-timer latency plus the git blame roundtrip.
  //
  // Direct transposition of glyph.wat's complex-plane oscillator predictor
  // (z[n] = K·z[n-1] − G·z[n-2]) to the 1D case. One ring, three doubles,
  // no allocations per scroll tick. See [_updateScrollEngram].
  final Float64List _scrollEngram = Float64List(3);
  int _scrollEngramFill = 0;
  bool _blameWarmedThisScroll = false;

  // Hot-zone anticipation: when the engram predicts the scroll will
  // settle near a high-churn hunk (our current φ proxy), we briefly
  // flag that hunk so the header row can glow as an "approaching"
  // cue. Cleared when the user scrolls past or the prediction
  // becomes stale. The state lives in three parts:
  //
  //   _hotHunkIdx            — index into `_hunks` (not `_lines`).
  //   _hotHunkStrength       — 0..1, scaled to the hunk's relative
  //                            churn among its siblings.
  //   _hotHunkSeenAt         — timestamp for decay; the halo eases
  //                            out over ~900ms so a predicted hunk
  //                            that was actually landed on doesn't
  //                            disappear the moment the user stops.
  int? _hotHunkIdx;
  double _hotHunkStrength = 0.0;
  DateTime? _hotHunkSeenAt;

  // Pinned-line context (right-click any diff row to pin it). The
  // panel at the bottom of the shell shows logos-powered context for
  // the pinned line: K-space nearest files, semantic well, simhash
  // rhymes within this diff, blame, coupling partners.
  int? _pinnedFastKey;
  int? _pinnedDisplayIdx;
  DiffPinnedContextModel? _pinnedCtx;
  // Monotonic counter so a new pin cancels in-flight async work
  // from the previous one — no "slow pin overwrites fast pin" race.
  int _pinSeq = 0;

  /// Max churn across the current file's hunks, cached at hunk
  /// extraction so the hot-zone check is O(1) per scroll tick.
  int _maxHunkChurn = 0;

  // First-appearance tracking — lineage animations. Any reveal / transition
  // animation should fire ONCE per unit per diff session, not every time a
  // row scrolls into view and gets re-mounted by ListView recycling. The set
  // gets cleared whenever the underlying diff content changes in _rebuild
  // so a fresh diff gets its one-time reveal.
  // Set<int> because EditUnit.id is now a 64-bit integer (SplitMix64
  // avalanche of the unit's structural fingerprint). Integer set ops are
  // ~5× faster than the old Set<String> and allocate zero heap strings
  // on the per-row-per-frame `add` call in itemBuilder.
  final Set<int> _seenUnitIds = <int>{};
  DiffLogosSession? _ownedLogosSession;
  DiffLogosSession? _logosSession;
  bool _logosLoading = false;
  Set<String> _subscribedLogosFiles = const {};
  int _appliedLogosSnapshotVersion = 0;
  int _appliedLogosContextRevision = 0;

  String? get _effectiveDiffContent =>
      _currentDiffContent ?? _currentDocument?.rawContent ?? widget.diffContent;

  String? get _effectiveDocumentId =>
      _currentDocument?.documentId ??
      ((_effectiveDiffContent == null || _effectiveDiffContent!.isEmpty)
          ? null
          : '${widget.filePath}:${_effectiveDiffContent.hashCode}');

  @override
  void initState() {
    super.initState();
    _frameTimingsCallback = _handleFrameTimings;
    SchedulerBinding.instance.addTimingsCallback(_frameTimingsCallback);
    _scrollCtrl.addListener(_handleScrollTelemetry);
    _scrollCtrl.addListener(_syncLogosSubscriptions);
    _scrollCtrl.addListener(_recordTemporalMark);
    _scrollCtrl.addListener(_markScrollActive);
    _rebuild();
    _scheduleTemporalRestore();
  }

  @override
  void didUpdateWidget(DiffShell old) {
    super.didUpdateWidget(old);
    final oldDocumentId = old.document?.documentId;
    final newDocumentId = widget.document?.documentId;
    final diffOrPathChanged = old.diffContent != widget.diffContent ||
        oldDocumentId != newDocumentId ||
        old.filePath != widget.filePath;
    final repositoryChanged = old.repositoryPath != widget.repositoryPath;
    final diffScopeChanged = diffOrPathChanged || repositoryChanged;
    final logosInputsChanged = diffScopeChanged ||
        old.revisionRef != widget.revisionRef ||
        !mapEquals(old.symbolCoupling, widget.symbolCoupling);
    if (diffScopeChanged) {
      _blameFetchedFiles.clear();
      _blameFetchingFiles.clear();
      _blamePrewarmingFiles.clear();
      _blameUnavailableFiles.clear();
      _blameLoadFutures.clear();
      _blameByFile.clear();
      _hoveredLine = null;
      // Reset trail state — the underlying diff changed, so any active
      // historical view is no longer meaningful.
      _trailVisible = false;
      _trailHistory = const [];
      _trailLoading = false;
      _trailSelectedHash = null;
      _trailSelectedPath = null;
      _originalDiffContent = null;
      _trailNowView = null;
      _trailScrubDebounce?.cancel();
      _trailScrubDebounce = null;
      _trailLoadSeq++;
      _trailViewCache.clear();
      _rebuild();
      if (old.filePath != widget.filePath || repositoryChanged) {
        // Arm restore for the new file; the helper jumps-to-top when the
        // file has no stored position, otherwise scrolls to the remembered
        // unit and pulses it.
        _temporalRestoreDone = false;
        _scheduleTemporalRestore();
      }
    }
    if (old.jumpToLineRequestId != widget.jumpToLineRequestId &&
        widget.jumpToLineIndex != null) {
      _jumpToLineIndex(widget.jumpToLineIndex!);
    }
    if (widget.logosSession != old.logosSession) {
      _bindLogosSession(widget.logosSession, disposeOldOwned: false);
    }
    if (!diffScopeChanged &&
        (logosInputsChanged || widget.logosSession != old.logosSession)) {
      _syncLogosRuntime(forceRefresh: logosInputsChanged);
      if (_pinnedFastKey != null) {
        _schedulePinnedContextRefresh();
      }
    }
  }

  void _rebuild() {
    _profileUiSync(
      'diff.shell.rebuild',
      () {
        final document = widget.document ??
            ((widget.diffContent != null && widget.diffContent!.isNotEmpty)
                ? DiffDocument.fromRawContent(
                    rawContent: widget.diffContent!,
                    pathHint: widget.filePath,
                    trimLeadingMeta: widget.showFileHeader,
                  )
                : null);
        if (document != null && !document.isEmpty) {
          final stagedKeys = <int>{
            for (final line in _lines)
              if (line.isStaged) line.fastKey,
          };
          _applyDocument(document, stagedKeys: stagedKeys);
          _beginTelemetrySession();
          _syncLogosRuntime(forceRefresh: true);
        } else {
          _flushRenderMetrics();
          _lines = [];
          _hunks = [];
          _hunkHeaderByFastKey = const {};
          _maxHunkChurn = 0;
          _pairedAddFastKeys = const {};
          _unitByFastKey = const {};
          _hunkDisplayRows = const [];
          _setDisplayLines(const []);
          _keyboardLineIndex = null;
          _lastToggledLineIndex = null;
          _useAnimatedTextMode = false;
          _sessionChangedLines = 0;
          _sessionPayloadBytes = 0;
          _currentDiffContent = widget.diffContent;
          _currentDocument = null;
          _maxLineWidth = 800.0;
          _logosLoading = false;
          _bindLogosSession(null, disposeOldOwned: true);
        }
      },
      errorCode: 'diff.shell.rebuild_failed',
    );
  }

  void _applyDocument(
    DiffDocument document, {
    Set<int> stagedKeys = const <int>{},
  }) {
    _profileUiSync(
      'diff.shell.apply-document',
      () {
        _currentDocument = document;
        _currentDiffContent = document.rawContent;
        _lines = stagedKeys.isEmpty
            ? List<ParsedLine>.of(document.lines)
            : document.lines.map((line) {
                if (stagedKeys.contains(line.fastKey)) {
                  return line.copyWith(isStaged: true);
                }
                return line;
              }).toList(growable: false);
        _hunks = [
          for (final hunk in document.hunks)
            _HunkHeader(
              hunk.lineIndex,
              hunk.filePath,
              hunk.fileHunkIndex,
              hunk.label,
              hunk.additions,
              hunk.deletions,
            ),
        ];
        _rebuildHunkHeaderLookup();
        _pairedAddFastKeys = document.pairedAddFastKeys;
        _unitByFastKey = document.unitByFastKey;
        _maxLineWidth = _measureMaxLineWidth(document.maxLineLength);
        _maxHunkChurn =
            _hunks.fold<int>(0, (m, h) => h.churn > m ? h.churn : m);
        _hotHunkIdx = null;
        _hotHunkStrength = 0.0;
        _hotHunkSeenAt = null;
        _clearPinnedLine();
        _seenUnitIds.clear();
        _refreshDisplayLines();
        _revalidateKeyboardCursor();
      },
      errorCode: 'diff.shell.apply-document_failed',
    );
  }

  void _beginTelemetrySession() {
    _sessionDiffId = _effectiveDocumentId;
    _sessionStopwatch
      ..reset()
      ..start();
    _scrollFpsSamples.clear();
    _frameTotalSamples.clear();
    _frameBuildSamples.clear();
    _frameRasterSamples.clear();
    _sessionFirstPaintMs = null;
    _lastScrollEventAt = null;
    _sessionFlushed = false;
    _sessionSearchActivated = _searchTerm.isNotEmpty;
    _sessionPayloadBytes = _currentDocument?.payloadBytes ??
        (_effectiveDiffContent == null
            ? 0
            : utf8.encode(_effectiveDiffContent!).length);
    _sessionChangedLines = _currentDocument?.changedLines ??
        _lines
            .where((line) =>
                line.kind == LineKind.added || line.kind == LineKind.deleted)
            .length;
    _useAnimatedTextMode = !_sessionSearchActivated &&
        _sessionChangedLines <= _kAnimatedDiffMaxChangedLines &&
        _sessionPayloadBytes <= _kAnimatedDiffMaxPayloadBytes;
    _armRenderMetricsFlush(_kInitialFrameCaptureWindow);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _effectiveDiffContent == null ||
          _effectiveDiffContent!.isEmpty ||
          _sessionFirstPaintMs != null) {
        return;
      }
      _sessionFirstPaintMs = _sessionStopwatch.elapsedMicroseconds / 1000;
    });
  }

  void _handleScrollTelemetry() {
    if (!_sessionStopwatch.isRunning) {
      return;
    }
    final now = DateTime.now();
    final previous = _lastScrollEventAt;
    _lastScrollEventAt = now;
    if (previous == null) {
      return;
    }
    final deltaMs = now.difference(previous).inMicroseconds.abs() / 1000;
    if (deltaMs <= 0) {
      return;
    }
    final fps = 1000 / deltaMs;
    if (fps.isFinite && fps > 0) {
      _scrollFpsSamples.add(fps.clamp(0, 240));
    }
    _armRenderMetricsFlush(_kScrollFrameCaptureQuietWindow);
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    if (!_sessionStopwatch.isRunning) {
      return;
    }
    for (final timing in timings) {
      final totalMs = timing.totalSpan.inMicroseconds / 1000;
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      if (totalMs.isFinite && totalMs > 0) {
        _frameTotalSamples.add(totalMs);
      }
      if (buildMs.isFinite && buildMs > 0) {
        _frameBuildSamples.add(buildMs);
      }
      if (rasterMs.isFinite && rasterMs > 0) {
        _frameRasterSamples.add(rasterMs);
      }
    }
  }

  void _armRenderMetricsFlush(Duration delay) {
    _sessionFlushTimer?.cancel();
    _sessionFlushTimer = Timer(delay, _flushRenderMetrics);
  }

  void _flushRenderMetrics() {
    if (_sessionFlushed ||
        _sessionDiffId == null ||
        _effectiveDiffContent == null ||
        _effectiveDiffContent!.isEmpty) {
      return;
    }
    _sessionFlushTimer?.cancel();
    _sessionFlushTimer = null;
    final firstPaintMs =
        _sessionFirstPaintMs ?? (_sessionStopwatch.elapsedMicroseconds / 1000);
    final sustainedScrollFps = _sessionPercentile(_scrollFpsSamples, 50);
    final rendererMode = _useAnimatedTextMode
        ? 'dom-animated'
        : (_sessionSearchActivated
            ? 'dom-search'
            : _selectRendererMode(
                _sessionChangedLines,
                _sessionPayloadBytes,
                false,
              ));
    final frameTimeP95Ms = _sessionPercentile(_frameTotalSamples, 95);
    final buildTimeP95Ms = _sessionPercentile(_frameBuildSamples, 95);
    final rasterTimeP95Ms = _sessionPercentile(_frameRasterSamples, 95);
    final jankyFrameCount =
        _frameTotalSamples.where((value) => value > 16.7).length;

    _sessionFlushed = true;
    _sessionStopwatch.stop();
    DiagnosticsState.instance.recordDiffRenderMetrics(
      diffId: _sessionDiffId!,
      path: widget.filePath,
      rendererMode: rendererMode,
      changedLines: _sessionChangedLines,
      payloadBytes: _sessionPayloadBytes,
      firstPaintMs: firstPaintMs,
      sustainedScrollFps: sustainedScrollFps,
      memoryEstimateMb: _sessionPayloadBytes / (1024 * 1024),
      frameTimeP95Ms: frameTimeP95Ms,
      buildTimeP95Ms: buildTimeP95Ms,
      rasterTimeP95Ms: rasterTimeP95Ms,
      frameCount: _frameTotalSamples.length,
      jankyFrameCount: jankyFrameCount,
      fallbackActivated: false,
    );
  }

  double _sessionPercentile(List<double> values, int percentile) {
    if (values.isEmpty) {
      return 0;
    }
    final sorted = [...values]..sort();
    final rank = ((sorted.length * percentile) / 100).ceil();
    final index = rank <= 0 ? 0 : (rank - 1).clamp(0, sorted.length - 1);
    return sorted[index];
  }

  String _selectRendererMode(
    int changedLines,
    int payloadBytes,
    bool fallbackActivated,
  ) {
    if (fallbackActivated) {
      return 'fallback';
    }
    if (changedLines < _kModeAMaxChangedLines &&
        payloadBytes < _kModeAMaxPayloadBytes) {
      return 'dom';
    }
    return 'canvas';
  }

  void _recordUiTimingIfSlow({
    required String event,
    required Stopwatch stopwatch,
    String phase = 'compute',
    bool ok = true,
    String? errorCode,
    double minMs = 8,
  }) {
    if (stopwatch.isRunning) {
      stopwatch.stop();
    }
    final durationMs = stopwatch.elapsedMicroseconds / 1000;
    if (!durationMs.isFinite || durationMs < minMs) {
      return;
    }
    unawaited(
      DiagnosticsState.instance
          .recordUiTiming(
            event: event,
            phase: phase,
            durationMs: durationMs,
            ok: ok,
            errorCode: ok ? null : errorCode,
          )
          .catchError((_) => null),
    );
  }

  T _profileUiSync<T>(
    String event,
    T Function() body, {
    String phase = 'compute',
    String? errorCode,
    double minMs = 8,
  }) {
    final stopwatch = Stopwatch()..start();
    try {
      final result = body();
      _recordUiTimingIfSlow(
        event: event,
        stopwatch: stopwatch,
        phase: phase,
        minMs: minMs,
      );
      return result;
    } catch (_) {
      _recordUiTimingIfSlow(
        event: event,
        stopwatch: stopwatch,
        phase: phase,
        ok: false,
        errorCode: errorCode,
        minMs: minMs,
      );
      rethrow;
    }
  }

  @override
  void dispose() {
    // Defer the metrics flush to a microtask: notifyListeners() inside
    // dispose() runs while the framework is in lockState, which throws
    // "widget tree was locked" on the downstream provider. The flush is
    // pure observation — DiagnosticsState only reads internal counters
    // and pushes them to listeners — so post-frame scheduling is safe
    // and preserves the metric.
    scheduleMicrotask(_flushRenderMetrics);
    _blameHoverTimer?.cancel();
    _sessionFlushTimer?.cancel();
    _applyDebounce?.cancel();
    _trailScrubDebounce?.cancel();
    _restoredPulseTimer?.cancel();
    _scrollIdleTimer?.cancel();
    // Capture the final position so closing without scrolling still records
    // a mark. Read BEFORE disposing the scroll controller.
    _recordTemporalMark();
    _logosSession?.snapshotListenable
        .removeListener(_handleLogosSnapshotChanged);
    _logosSession?.contextListenable
        .removeListener(_handleLogosContextChanged);
    if (_ownedLogosSession != null &&
        identical(_ownedLogosSession, _logosSession)) {
      _ownedLogosSession!.dispose();
      _ownedLogosSession = null;
    }
    _stagingFocus.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_frameTimingsCallback);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _hScrollCtrl.dispose();
    super.dispose();
  }

  /// Build a cache key that includes the revision — blame at HEAD and blame
  /// at a historical commit are different data sets, and both can be viewed
  /// during a single DiffShell session when the Paper Trail is active.
  String _blameKey(String filePath, String? revision) =>
      '${widget.repositoryPath ?? ''}\u0000$filePath${revision == null ? '' : '@$revision'}';

  String? get _activeRevisionRef => widget.revisionRef ?? _trailSelectedHash;

  String _normalizedDiffPath(String filePath) => filePath.replaceAll('\\', '/');

  String _effectiveBlamePathFor(String filePath) {
    final revision = _activeRevisionRef;
    final scopedPath = (revision != null && _trailSelectedPath != null)
        ? _trailSelectedPath!
        : filePath;
    return _normalizedDiffPath(scopedPath);
  }

  String _blameLookupKey(String filePath, String? revision) =>
      _blameKey(_effectiveBlamePathFor(filePath), revision);

  String _temporalMarkScopeKey(String filePath) {
    return _blameLookupKey(filePath, _activeRevisionRef);
  }

  /// Cheap "already handled" check for prewarm loops that don't
  /// need to await the result — just to avoid re-queuing.
  bool _hasQueuedOrFetchedBlame(String key) =>
      _blameFetchedFiles.contains(key) ||
      _blameFetchingFiles.contains(key) ||
      _blamePrewarmingFiles.contains(key) ||
      _blameUnavailableFiles.contains(key) ||
      _blameLoadFutures.containsKey(key);

  bool _isBlameEligiblePath(String filePath) {
    final normalizedPath = _normalizedDiffPath(filePath);
    final raw = _currentDocument?.rawDiffByPath[normalizedPath];
    if (raw == null || raw.isEmpty) {
      final diffPaths = _uniqueFilePathsInDiff();
      if (diffPaths.length > 1 && !diffPaths.contains(normalizedPath)) {
        return false;
      }
      return normalizedPath.isNotEmpty;
    }
    // Fresh files and synthetic untracked patches have no committed ancestor
    // in HEAD, so `git blame` is guaranteed to fail for this session.
    if (raw.contains('\nnew file mode ') || raw.contains('--- /dev/null')) {
      return false;
    }
    return true;
  }

  Future<void> _loadBlame(String filePath, int lineNum) async {
    if (widget.repositoryPath == null) return;
    // When viewing a historical stop via the Paper Trail, blame must be
    // computed AS OF that commit — otherwise hovering a line shows the
    // current-HEAD author instead of who last touched it at that point.
    // For renamed files, also use the path AT that commit (pre-rename).
    final revision = _activeRevisionRef;
    final queryPath = _effectiveBlamePathFor(filePath);
    final key = _blameKey(queryPath, revision);
    if (!_isBlameEligiblePath(filePath)) {
      _blameUnavailableFiles.add(key);
      return;
    }
    if (_blameFetchedFiles.contains(key) ||
        _blameUnavailableFiles.contains(key)) {
      return;
    }
    // Join an in-flight fetch for the same key if one exists.
    final inflight = _blameLoadFutures[key];
    if (inflight != null) {
      return inflight;
    }

    // First caller. Store a completer so joiners have something to
    // await; resolve it in finally no matter how we exit.
    final completer = Completer<void>();
    _blameLoadFutures[key] = completer.future;
    try {
      final shouldNotify = lineNum > 0 || _wearMapVisible;
      if (shouldNotify) {
        setState(() {
          _blameFetchingFiles.add(key);
          if (lineNum > 0) {
            _hoveredLine = lineNum;
          }
        });
      } else {
        _blamePrewarmingFiles.add(key);
      }
      List<BlameLineData>? blameData;
      var blameFailed = false;
      try {
        final r = await getFileBlame(
          widget.repositoryPath!,
          queryPath,
          commitRef: revision,
        );
        if (r.ok) {
          blameData = r.data;
        } else {
          blameFailed = true;
        }
      } catch (_) {
        blameFailed = true;
      }
      if (!mounted) return;
      void applyResult() {
        _blameFetchingFiles.remove(key);
        _blamePrewarmingFiles.remove(key);
        if (blameData != null) {
          _blameFetchedFiles.add(key);
          final map = <int, BlameLineData>{};
          for (final entry in blameData) {
            map[entry.lineNumber] = entry;
          }
          // Evict stale entries before inserting so the newest arrival
          // is always at the most-recent end of the LRU order.
          _blameByFile.remove(key);
          _blameByFile[key] = map;
          while (_blameByFile.length > _kBlameCacheMaxFiles) {
            final oldest = _blameByFile.keys.first;
            _blameByFile.remove(oldest);
            // Also drop the companion tracking-set entry so a future
            // fetch of the evicted file refreshes cleanly.
            _blameFetchedFiles.remove(oldest);
          }
        } else if (blameFailed) {
          _blameUnavailableFiles.add(key);
        }
      }

      if (shouldNotify) {
        setState(applyResult);
      } else {
        applyResult();
      }
    } finally {
      _blameLoadFutures.remove(key);
      if (!completer.isCompleted) completer.complete();
    }
  }

  BlameLineData? _blameFor(String? filePath, int lineNum) {
    if (filePath == null) return null;
    final key = _blameLookupKey(filePath, _activeRevisionRef);
    final map = _blameByFile[key];
    if (map == null) return null;
    // LRU bump: move this file to the most-recently-used end so
    // actively-hovered files don't get evicted when the cap is hit.
    if (_blameByFile.length > 1) {
      _blameByFile.remove(key);
      _blameByFile[key] = map;
    }
    return map[lineNum];
  }

  Set<String> _uniqueFilePathsInDiff() {
    final paths = <String>{};
    for (final line in _lines) {
      final p = line.filePath;
      if (p != null && p.isNotEmpty) paths.add(p);
    }
    // Fallback for single-file diffs where parser didn't see a diff --git header.
    if (paths.isEmpty) paths.add(widget.filePath);
    return paths;
  }

  void _bindLogosSession(
    DiffLogosSession? session, {
    required bool disposeOldOwned,
  }) {
    if (identical(_logosSession, session)) {
      _logosLoading = session?.loading ?? false;
      return;
    }
    final previous = _logosSession;
    // Detach from the two sub-notifiers (see `DiffLogosSession`'s
    // snapshot/context split — Grimoire XV applied at the state
    // layer). Listening to each channel separately means a per-file
    // context arrival can't wake up snapshot-only consumers.
    previous?.snapshotListenable.removeListener(_handleLogosSnapshotChanged);
    previous?.contextListenable.removeListener(_handleLogosContextChanged);
    if (disposeOldOwned &&
        _ownedLogosSession != null &&
        identical(previous, _ownedLogosSession)) {
      _ownedLogosSession!.dispose();
      _ownedLogosSession = null;
    }
    _logosSession = session;
    _logosLoading = session?.loading ?? false;
    _subscribedLogosFiles = const {};
    _appliedLogosSnapshotVersion = 0;
    _appliedLogosContextRevision = 0;
    session?.snapshotListenable.addListener(_handleLogosSnapshotChanged);
    session?.contextListenable.addListener(_handleLogosContextChanged);
  }

  void _handleLogosSnapshotChanged() {
    _applyLatestLogosState();
  }

  void _handleLogosContextChanged() {
    _applyLatestLogosState();
  }

  void _syncLogosRuntime({required bool forceRefresh}) {
    _profileUiSync(
      'diff.shell.logos-sync',
      () {
        final externalSession = widget.logosSession;
        if (externalSession != null) {
          _bindLogosSession(externalSession, disposeOldOwned: true);
          _applyLatestLogosState();
          _syncLogosSubscriptions();
          return;
        }

        final repoPath = widget.repositoryPath;
        final diffText = _effectiveDiffContent;
        if (repoPath == null || diffText == null || diffText.isEmpty) {
          _bindLogosSession(null, disposeOldOwned: true);
          if (mounted) {
            setState(() {
              _logosLoading = false;
              _refreshDisplayLines();
            });
          }
          return;
        }

        final request = DiffLogosRequest(
          repositoryPath: repoPath,
          diffText: diffText,
          parsedLines: _lines,
          parsedMetadata: DiffLogosParsedMetadata(
            touchedPaths: _uniqueFilePathsInDiff(),
            hunkCount: _hunks.length,
          ),
          symbolCoupling: widget.symbolCoupling,
          revisionRef: _activeRevisionRef,
          couplingMatrix: widget.couplingMatrix,
          warmEngine: _logosSession?.logos?.engine,
        );
        final session = _ownedLogosSession ??=
            DiffLogosFacade.instance.createSession(request);
        _bindLogosSession(session, disposeOldOwned: false);
        _applyLatestLogosState();
        if (_logosSession == session &&
            (forceRefresh || session.cacheKey.isEmpty)) {
          unawaited(session.refresh(request).catchError((_) => null));
        }
        _syncLogosSubscriptions();
      },
      errorCode: 'diff.shell.logos-sync_failed',
    );
  }

  void _applyLatestLogosState() {
    if (!mounted) {
      return;
    }
    final session = _logosSession;
    final nextLoading = session?.loading ?? false;
    final snapshotVersion = session?.snapshotVersion ?? 0;
    final contextRevision = session?.contextRevision ?? 0;
    final snapshotChanged = snapshotVersion != _appliedLogosSnapshotVersion;
    final contextChanged = contextRevision != _appliedLogosContextRevision;
    if (!snapshotChanged && !contextChanged && nextLoading == _logosLoading) {
      return;
    }
    setState(() {
      _logosLoading = nextLoading;
      if (contextChanged && _searchTerm.isEmpty) {
        _refreshDisplayLines();
      }
      _appliedLogosSnapshotVersion = snapshotVersion;
      _appliedLogosContextRevision = contextRevision;
    });
    if ((snapshotChanged || contextChanged) && _pinnedFastKey != null) {
      _schedulePinnedContextRefresh();
    }
  }

  Set<String> _desiredLogosSubscriptionPaths() {
    if (_displayLines.isEmpty) {
      return _uniqueFilePathsInDiff();
    }
    final desired = <String>{};
    final viewport =
        _scrollCtrl.hasClients ? _scrollCtrl.position.viewportDimension : 0.0;
    final start =
        ((_scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0) / _kLineItemExtent)
            .floor()
            .clamp(0, _displayLines.length - 1);
    final end = (((_scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0) +
                math.max(viewport, _kLineItemExtent * 24)) /
            _kLineItemExtent)
        .ceil()
        .clamp(0, _displayLines.length);
    for (var i = start; i < end; i++) {
      final path = _displayLines[i].filePath ?? widget.filePath;
      if (path.isNotEmpty) {
        desired.add(path);
      }
    }
    final pinnedIdx = _pinnedDisplayIdx;
    if (pinnedIdx != null &&
        pinnedIdx >= 0 &&
        pinnedIdx < _displayLines.length) {
      final pinnedPath = _displayLines[pinnedIdx].filePath ?? widget.filePath;
      if (pinnedPath.isNotEmpty) {
        desired.add(pinnedPath);
      }
    }
    if (desired.isEmpty) {
      desired.addAll(_uniqueFilePathsInDiff());
    }
    return desired;
  }

  void _syncLogosSubscriptions() {
    final session = _logosSession;
    if (session == null) {
      _subscribedLogosFiles = const {};
      return;
    }
    final next = _desiredLogosSubscriptionPaths();
    if (setEquals(_subscribedLogosFiles, next)) {
      return;
    }
    _subscribedLogosFiles = next;
    session.replaceFileSubscriptions(next);
  }

  ParsedLine _buildFoldMarkerLine({
    required String filePath,
    required int hunkIndex,
    required int hiddenCount,
    int? startLine,
    int? endLine,
  }) {
    final range = switch ((startLine, endLine)) {
      (final int start?, final int end?) when start == end => ' at $start',
      (final int start?, final int end?) => ' $start-$end',
      _ => '',
    };
    final text = '... $hiddenCount unchanged lines$range ...';
    return ParsedLine(
      text: text,
      lowerText: text.toLowerCase(),
      kind: LineKind.meta,
      filePath: filePath,
      hunkIndex: hunkIndex,
      lineNumNew: startLine,
      lineNumOld: startLine,
    );
  }

  List<ParsedLine> _applyAdaptiveContext(List<ParsedLine> source) {
    if (_logosSession == null) {
      return source;
    }
    final output = <ParsedLine>[];
    DiffFileContextPlan? currentPlan;
    String? currentPath;
    var hiddenCount = 0;
    int? hiddenStart;
    int? hiddenEnd;
    String? hiddenFilePath;
    int hiddenHunk = -1;

    void flushHidden() {
      if (hiddenCount <= 0 || hiddenFilePath == null) return;
      output.add(
        _buildFoldMarkerLine(
          filePath: hiddenFilePath!,
          hunkIndex: hiddenHunk,
          hiddenCount: hiddenCount,
          startLine: hiddenStart,
          endLine: hiddenEnd,
        ),
      );
      hiddenCount = 0;
      hiddenStart = null;
      hiddenEnd = null;
      hiddenFilePath = null;
      hiddenHunk = -1;
    }

    for (final line in source) {
      final filePath = line.filePath ?? widget.filePath;
      final plan = currentPath == filePath
          ? currentPlan
          : (() {
              currentPath = filePath;
              currentPlan = _logosSession?.contextPlanFor(filePath);
              return currentPlan;
            })();
      final hideContext = line.kind == LineKind.context &&
          plan != null &&
          !plan.visibleFastKeys.contains(line.fastKey);
      if (!hideContext) {
        flushHidden();
        output.add(line);
        continue;
      }
      if (hiddenFilePath != null &&
          (hiddenFilePath != filePath || hiddenHunk != line.hunkIndex)) {
        flushHidden();
      }
      hiddenFilePath = filePath;
      hiddenHunk = line.hunkIndex;
      hiddenCount++;
      hiddenStart ??= line.lineNumNew ?? line.lineNumOld;
      hiddenEnd = line.lineNumNew ?? line.lineNumOld;
    }
    flushHidden();
    return output;
  }

  DiffFileContextPlan? _contextPlanForLine(ParsedLine line) =>
      _logosSession?.contextPlanFor(line.filePath ?? widget.filePath);

  DiffContextBand? _contextBandForLine(ParsedLine line) {
    if (line.kind == LineKind.added || line.kind == LineKind.deleted) {
      return DiffContextBand.changed;
    }
    if (line.kind != LineKind.context) {
      return null;
    }
    return _contextPlanForLine(line)?.bandByFastKey[line.fastKey];
  }

  _HunkHeader? _headerForDisplayLine(ParsedLine line) {
    return _hunkHeaderByFastKey[line.fastKey];
  }

  DiffLogosHunkSignal? _logosSignalForHeader(_HunkHeader header) =>
      _logosSession?.hunkFor(header.filePath, header.fileHunkIndex);

  DiffLogosFileSignal? _logosFileSignalForHeader(_HunkHeader header) =>
      _logosSession?.filesByPath[header.filePath];

  DiffLineResidualSignal? _logosResidualForLine(ParsedLine line) =>
      _contextPlanForLine(line)?.residualByFastKey[line.fastKey];

  double _semanticStrength({
    required double importance,
    double transportPull = 0.0,
    double transportedSupport = 0.0,
    double innovationResidual = 0.0,
    double witnessResidual = 0.0,
  }) =>
      math
          .max(
            importance,
            math.max(
              math.max(transportPull, transportedSupport),
              math.max(innovationResidual, witnessResidual),
            ),
          )
          .clamp(0.0, 1.0)
          .toDouble();

  double _importanceForHunkIndex(int hunkIdx) {
    if (hunkIdx < 0 || hunkIdx >= _hunks.length) return 0.0;
    final header = _hunks[hunkIdx];
    final signal = _logosSignalForHeader(header);
    if (signal != null) {
      return _semanticStrength(
        importance: signal.importance,
        transportPull: signal.transportPull ?? 0.0,
        transportedSupport: signal.transportedSupport ?? 0.0,
        innovationResidual: signal.innovationResidual ?? 0.0,
        witnessResidual: signal.witnessResidual ?? 0.0,
      );
    }
    final fileSignal = _logosFileSignalForHeader(header);
    if (fileSignal != null) {
      return _semanticStrength(
        importance: fileSignal.importance,
        transportPull: fileSignal.transportPull ?? 0.0,
        transportedSupport: fileSignal.transportedSupport ?? 0.0,
        innovationResidual: fileSignal.innovationResidual ?? 0.0,
        witnessResidual: fileSignal.witnessResidual ?? 0.0,
      );
    }
    if (_maxHunkChurn <= 0) return 0.0;
    return (_hunks[hunkIdx].churn / _maxHunkChurn).clamp(0.0, 1.0);
  }

  void _toggleWearMap() {
    if (widget.repositoryPath == null) return;
    setState(() => _wearMapVisible = !_wearMapVisible);
    if (_wearMapVisible) {
      _batchLoadWearBlame();
    }
  }

  /// Parallel workers for the wear-map blame batch. Bounded so we
  /// don't spawn a subprocess storm on large diffs.
  static const int _kWearBlameConcurrency = 6;

  /// Load blame for every file in the diff at the current trail
  /// revision. Viewport files go first so colors paint where the
  /// user is looking. Bails if wear toggles off, the trail moves,
  /// or the widget unmounts.
  Future<void> _batchLoadWearBlame() async {
    final revisionAtStart = _activeRevisionRef;

    // Visible files first, rest after — viewport gets priority on
    // the worker pool.
    final allPaths = _uniqueFilePathsInDiff().toList();
    final visible = <String>{};
    if (_scrollCtrl.hasClients && _displayLines.isNotEmpty) {
      final viewport = _scrollCtrl.position.viewportDimension;
      final top = (_scrollCtrl.offset / _lineItemExtent)
          .floor()
          .clamp(0, _displayLines.length - 1);
      final bottom = ((_scrollCtrl.offset + viewport) / _lineItemExtent)
          .ceil()
          .clamp(0, _displayLines.length - 1);
      for (var i = top; i <= bottom; i++) {
        final p = _displayLines[i].filePath ?? widget.filePath;
        visible.add(p);
      }
    }
    final ordered = <String>[
      ...allPaths.where(visible.contains),
      ...allPaths.where((p) => !visible.contains(p)),
    ];

    final pending = Queue<String>.from([
      for (final path in ordered)
        if (_isBlameEligiblePath(path) &&
            !_hasQueuedOrFetchedBlame(_blameLookupKey(path, revisionAtStart)))
          path,
    ]);
    if (pending.isEmpty) return;

    Future<void> worker() async {
      while (pending.isNotEmpty) {
        if (!mounted || !_wearMapVisible) return;
        if (_activeRevisionRef != revisionAtStart) return;
        final path = pending.removeFirst();
        await _loadBlame(path, 0);
      }
    }

    final workerCount = math.min(_kWearBlameConcurrency, pending.length);
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
  }

  // Cached per-file age range: oldest and newest authoredAt per file.
  // Invalidated whenever blame changes; recomputed lazily on access.
  Map<String, _AgeRange>? _ageRangesCache;
  int _ageRangesCacheKey = 0;

  Map<String, _AgeRange> _ageRangesByFile() {
    // Invalidate when the blame cache shape changes.
    final key = _blameByFile.length * 10000 +
        _blameByFile.values.fold<int>(0, (acc, m) => acc + m.length);
    if (_ageRangesCache != null && _ageRangesCacheKey == key) {
      return _ageRangesCache!;
    }
    final result = <String, _AgeRange>{};
    _blameByFile.forEach((path, lineMap) {
      DateTime? min;
      DateTime? max;
      for (final entry in lineMap.values) {
        try {
          final d = DateTime.parse(entry.authoredAt);
          if (min == null || d.isBefore(min)) min = d;
          if (max == null || d.isAfter(max)) max = d;
        } catch (_) {}
      }
      if (min != null && max != null) {
        result[path] = _AgeRange(min: min, max: max);
      }
    });
    _ageRangesCache = result;
    _ageRangesCacheKey = key;
    return result;
  }

  /// Returns 0 (newest) to 1 (oldest) for a line's wear intensity,
  /// or null if we can't resolve an age for it.
  double? _wearIntensityFor(String? filePath, int lineNum) {
    if (filePath == null) return null;
    final entry = _blameFor(filePath, lineNum);
    if (entry == null) return null;
    // Age ranges are cached by the same (file, revision) key as blame.
    final range =
        _ageRangesByFile()[_blameLookupKey(filePath, _activeRevisionRef)];
    if (range == null) return null;
    try {
      final d = DateTime.parse(entry.authoredAt);
      final span = range.max.difference(range.min).inSeconds;
      if (span <= 0) return 0.0;
      final from = range.max.difference(d).inSeconds;
      return (from / span).clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  _PinnedPastContext? _buildPinnedPastContext(DiffPinnedContextModel? context) {
    if (context == null) return null;
    final line = context.line;
    final filePath = line.filePath ?? widget.filePath;
    final lineNum = line.lineNumNew;
    final lineBlame = context.blame;
    final blameMap =
        _blameByFile[_blameLookupKey(filePath, _activeRevisionRef)];

    String? lastTouchLabel;
    if (lineBlame != null) {
      lastTouchLabel =
          '${lineBlame.authorName} / ${_formatBlameTime(lineBlame.authoredAt)} / ${lineBlame.shortHash}';
    }
    if (lineNum == null || blameMap == null || blameMap.isEmpty) {
      if (lastTouchLabel == null) return null;
      return _PinnedPastContext(
        tempoLabel: 'history loading',
        lastTouchLabel: lastTouchLabel,
        nearbyAuthors: const [],
        lineHeatSamples: const [],
      );
    }

    final nearby = <BlameLineData>[];
    for (var candidate = lineNum - 8; candidate <= lineNum + 8; candidate++) {
      final blame = blameMap[candidate];
      if (blame != null) {
        nearby.add(blame);
      }
    }
    if (nearby.isEmpty) {
      return _PinnedPastContext(
        tempoLabel: 'history loading',
        lastTouchLabel: lastTouchLabel,
        nearbyAuthors: const [],
        lineHeatSamples: const [],
      );
    }

    final authorCounts = <String, int>{};
    DateTime? newest;
    DateTime? oldest;
    for (final blame in nearby) {
      authorCounts[blame.authorName] =
          (authorCounts[blame.authorName] ?? 0) + 1;
      try {
        final authored = DateTime.parse(blame.authoredAt);
        if (newest == null || authored.isAfter(newest)) newest = authored;
        if (oldest == null || authored.isBefore(oldest)) oldest = authored;
      } catch (_) {
        // Ignore parse failures; other signals still render.
      }
    }

    final total = nearby.length;
    final authors = authorCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    final topShare = authors.isEmpty ? 0.0 : authors.first.value / total;
    final newestAgeDays =
        newest == null ? 9999 : DateTime.now().difference(newest).inDays;
    final ageSpreadDays = newest == null || oldest == null
        ? 0
        : newest.difference(oldest).inDays.abs();
    final spanSeconds = newest == null || oldest == null
        ? 0
        : newest.difference(oldest).inSeconds.abs();
    final tempoLabel = newestAgeDays <= 21
        ? (topShare >= 0.65 ? 'hot owner lane' : 'active seam')
        : (topShare >= 0.65
            ? 'stable owner lane'
            : ageSpreadDays >= 120
                ? 'shared long-lived seam'
                : 'shared lane');
    final lineHeatSamples = <double>[];
    for (var candidate = lineNum - 8; candidate <= lineNum + 8; candidate++) {
      final blame = blameMap[candidate];
      if (blame == null) {
        lineHeatSamples.add(0.0);
        continue;
      }
      try {
        final authored = DateTime.parse(blame.authoredAt);
        if (newest == null || oldest == null || spanSeconds <= 0) {
          lineHeatSamples.add(0.65);
          continue;
        }
        final heat = authored.difference(oldest).inSeconds /
            spanSeconds.clamp(1, 1 << 30);
        lineHeatSamples.add((0.18 + 0.82 * heat).clamp(0.0, 1.0));
      } catch (_) {
        lineHeatSamples.add(0.25);
      }
    }

    return _PinnedPastContext(
      tempoLabel: tempoLabel,
      lastTouchLabel: lastTouchLabel,
      nearbyAuthors: [
        for (final author in authors.take(2))
          _PinnedAuthorShare(
            name: author.key,
            share: author.value / total,
          ),
      ],
      lineHeatSamples: lineHeatSamples,
    );
  }

  // Blame is loaded lazily per-file on hover, so the session caps
  // (intended to protect the diff renderer) don't need to gate it.
  // Only disable in animated text mode (where the diff is tiny and blame
  // hover would be weird) or when no repo path is available.
  bool get _canShowInlineBlame =>
      !_useAnimatedTextMode && widget.repositoryPath != null;

  void _scheduleBlameLoad(String filePath, int lineNum) {
    if (!_canShowInlineBlame) {
      return;
    }
    _blameHoverTimer?.cancel();
    final delay = _instantBlameHover ? Duration.zero : _kBlameHoverDelay;
    _blameHoverTimer = Timer(delay, () {
      if (!mounted || _hoveredLine != lineNum) {
        return;
      }
      _loadBlame(filePath, lineNum);
    });
  }

  bool get _stagingEnabled =>
      widget.enableStaging && widget.repositoryPath != null;

  /// The staging cell (click target) is to the LEFT of the gutter.
  /// Width chosen to feel like a comfortable target without crowding
  /// the line number. Shadows [_kStageCellWidth] so existing widget-prop
  /// plumbing (DiffLineView.stageCellWidth) doesn't have to change signature.
  static const double _stageCellWidth = _kStageCellWidth;

  /// Height of every diff row. Used for paint-drag hit-testing.
  static const double _lineItemExtent = _kLineItemExtent;

  /// Toggle staging on a single line (by its index in [_lines]). Optionally
  /// pair-aware: if [autoPair] is true and the line is part of a -/+
  /// replacement, the partner is toggled coherently to the same target
  /// state. Does NOT apply on its own — callers should schedule apply.
  void _setLineStaged(int index, bool staged, {bool autoPair = true}) {
    if (index < 0 || index >= _lines.length) return;
    final line = _lines[index];
    if (line.kind != LineKind.added && line.kind != LineKind.deleted) return;
    if (line.isStaged == staged) return;
    _lines[index] = line.copyWith(isStaged: staged);
    if (autoPair) {
      final pair = findReplacementPair(_lines, index);
      if (pair != null && _lines[pair].isStaged != staged) {
        _lines[pair] = _lines[pair].copyWith(isStaged: staged);
      }
    }
  }

  /// Click on the sigil of a single line. Supports shift-extend (range from
  /// the last toggled line) and alt (disable auto-pairing).
  void _handleSigilTap(
    ParsedLine line, {
    required bool shift,
    required bool alt,
  }) {
    final idx = _lines.indexWhere((l) => identical(l, line));
    if (idx < 0) return;
    final target = !_lines[idx].isStaged;

    setState(() {
      if (shift && _lastToggledLineIndex != null) {
        final anchor = _lastToggledLineIndex!;
        final a = math.min(anchor, idx);
        final b = math.max(anchor, idx);
        for (int i = a; i <= b; i++) {
          _setLineStaged(i, target, autoPair: !alt);
        }
      } else {
        _setLineStaged(idx, target, autoPair: !alt);
      }
      _lastToggledLineIndex = idx;
      _keyboardLineIndex = idx;
      _refreshDisplayLines();
    });
    _scheduleApply();
  }

  /// Double-click on a hunk header toggles every +/- line in that hunk.
  /// Target state = "stage all if any are unstaged, otherwise unstage all."
  void _handleHunkDoubleTap(int hunkIndex) {
    final inHunk = <int>[];
    for (int i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (l.hunkIndex != hunkIndex) continue;
      if (l.kind == LineKind.added || l.kind == LineKind.deleted) {
        inHunk.add(i);
      }
    }
    if (inHunk.isEmpty) return;
    final anyUnstaged = inHunk.any((i) => !_lines[i].isStaged);
    setState(() {
      for (final i in inHunk) {
        _setLineStaged(i, anyUnstaged, autoPair: false);
      }
      _refreshDisplayLines();
    });
    _scheduleApply();
  }

  /// Toggle every +/- line across the diff. Bound to F key.
  void _handleFileStageToggle() {
    final targetables = <int>[];
    for (int i = 0; i < _lines.length; i++) {
      final k = _lines[i].kind;
      if (k == LineKind.added || k == LineKind.deleted) targetables.add(i);
    }
    if (targetables.isEmpty) return;
    final anyUnstaged = targetables.any((i) => !_lines[i].isStaged);
    setState(() {
      for (final i in targetables) {
        _setLineStaged(i, anyUnstaged, autoPair: false);
      }
      _refreshDisplayLines();
    });
    _scheduleApply();
  }

  void _beginPaint(ParsedLine line) {
    final idx = _lines.indexWhere((l) => identical(l, line));
    if (idx < 0) return;
    _paintActive = true;
    _paintTargetStaged = !_lines[idx].isStaged;
    _paintedFastKeys
      ..clear()
      ..add(line.fastKey);
    setState(() {
      _setLineStaged(idx, _paintTargetStaged);
      _lastToggledLineIndex = idx;
      _keyboardLineIndex = idx;
      _refreshDisplayLines();
    });
  }

  /// Paint-drag continues: hit-test against the display list using the
  /// pointer's global Y position. Only fires when [_paintActive].
  void _paintUpdate(Offset globalPosition) {
    if (!_paintActive) return;
    final box = _listViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    if (local.dy < 0 || local.dy > box.size.height) return;
    final scroll = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    final displayIndex = ((local.dy + scroll) / _lineItemExtent).floor();
    if (displayIndex < 0 || displayIndex >= _displayLines.length) return;
    final line = _displayLines[displayIndex];
    if (_paintedFastKeys.contains(line.fastKey)) return;
    if (line.kind != LineKind.added && line.kind != LineKind.deleted) return;
    _paintedFastKeys.add(line.fastKey);
    final idx = _lines.indexWhere((l) => identical(l, line));
    if (idx < 0) return;
    setState(() {
      _setLineStaged(idx, _paintTargetStaged);
      _lastToggledLineIndex = idx;
      _keyboardLineIndex = idx;
      _refreshDisplayLines();
    });
  }

  void _endPaint() {
    if (!_paintActive) return;
    _paintActive = false;
    _paintedFastKeys.clear();
    _scheduleApply();
  }

  final GlobalKey _listViewKey = GlobalKey();

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.shiftRight);

    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyJ) {
      _moveKeyboardCursor(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyK) {
      _moveKeyboardCursor(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP && _keyboardLineIndex != null) {
      final displayIdx = _displayLineIndex[_lines[_keyboardLineIndex!].fastKey];
      if (displayIdx != null) {
        _togglePinLine(displayIdx);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.space && _keyboardLineIndex != null) {
      if (!_stagingEnabled) {
        return KeyEventResult.ignored;
      }
      final line = _lines[_keyboardLineIndex!];
      _handleSigilTap(line, shift: isShift, alt: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH && _keyboardLineIndex != null) {
      if (!_stagingEnabled) {
        return KeyEventResult.ignored;
      }
      _handleHunkDoubleTap(_lines[_keyboardLineIndex!].hunkIndex);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      if (!_stagingEnabled) {
        return KeyEventResult.ignored;
      }
      _handleFileStageToggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveKeyboardCursor(int delta) {
    if (_lines.isEmpty) return;
    int start = _keyboardLineIndex ?? -1;
    int cur = start;
    for (int step = 0; step < _lines.length; step++) {
      cur += delta;
      if (cur < 0 || cur >= _lines.length) return;
      final candidate = _lines[cur];
      final k = candidate.kind;
      // Skip the add half of a replacement pair — its delete is the landing.
      if (_pairedAddFastKeys.contains(candidate.fastKey)) continue;
      if (k == LineKind.added || k == LineKind.deleted) {
        setState(() => _keyboardLineIndex = cur);
        _scrollToLine(candidate);
        return;
      }
    }
  }

  /// Called when a scroll gesture ends. If the viewport came to rest near a
  /// hunk header, gently snap to that header's line. Keeps reading cadence
  /// aligned with the diff's own structure — hunks are the units of change.
  /// Mark scroll as active; schedule clearing the flag after a brief idle
  /// window. Used by the row builder to decide whether a just-mounted row
  /// should play its reveal / peripheral animations (skip during fast scroll,
  /// play when the viewport has settled). No setState — the flag is sampled
  /// at itemBuilder time; changing it does not trigger a list rebuild.
  /// Also cancels any pending blame-hover load and clears the hovered line:
  /// with whole-row hover, a stationary cursor sees every scrolled-past row
  /// fire its onEnter, which would otherwise stack blame loads for rows the
  /// user never deliberately hovered.
  void _markScrollActive() {
    final wasScrolling = _scrolling;
    _scrolling = true;
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_kScrollIdleDelay, () {
      if (!mounted) return;
      _scrolling = false;
      _scrollEngramFill = 0;
      _blameWarmedThisScroll = false;
    });
    if (!wasScrolling) {
      // Fresh scroll session — reset engram ring + the per-session warm
      // flag so the AR(2) settle prediction can fire exactly once per
      // user-initiated scroll burst.
      _scrollEngramFill = 0;
      _blameWarmedThisScroll = false;
    }
    _updateScrollEngram();
    if (_hoveredLine != null || _blameHoverTimer?.isActive == true) {
      _blameHoverTimer?.cancel();
      if (_hoveredLine != null) {
        setState(() => _hoveredLine = null);
      }
    }
  }

  /// Push the current scroll offset into the 3-sample engram ring, then
  /// run the 2nd-order central difference to extract velocity and
  /// acceleration. When the system is clearly decelerating toward rest,
  /// eagerly warm blame for the current file so the upcoming hover doesn't
  /// pay both the hover-debounce timer AND the git blame roundtrip.
  /// Verlet / symplectic Euler math (Principia Circle XXXIX — integer
  /// symplectic mechanics, real-valued variant here since scroll is 1D
  /// and we don't need eigenvalue stability):
  ///   v[n]   = x[n] − x[n-1]                 (backward difference)
  ///   a[n]   = x[n] − 2·x[n-1] + x[n-2]      (2nd-order central)
  ///   x[n+1] = x[n] + v[n] + 0.5·a[n]        (leapfrog extrapolation)
  /// Settle condition: |v| below a line-height-ish threshold AND
  /// sign(v)·sign(a) ≤ 0 (the jerk opposes motion → decelerating). The
  /// thresholds are modest — we want to err on the side of firing EARLY,
  /// since a spurious blame fetch is cheap (git blame is memoized by
  /// [_blameKey] and the request is idempotent).
  void _updateScrollEngram() {
    if (!_scrollCtrl.hasClients) return;
    final x = _scrollCtrl.offset;
    // Shift ring: [a, b, c] ← [b, c, x].
    _scrollEngram[0] = _scrollEngram[1];
    _scrollEngram[1] = _scrollEngram[2];
    _scrollEngram[2] = x;
    if (_scrollEngramFill < 3) {
      _scrollEngramFill++;
      return;
    }

    final x0 = _scrollEngram[0];
    final x1 = _scrollEngram[1];
    final x2 = _scrollEngram[2];
    final v = x2 - x1;
    final a = x2 - 2.0 * x1 + x0;

    // Thresholds in pixels. Line extent is 18px — a velocity under half
    // a line per tick and a small-magnitude acceleration opposing the
    // motion direction is a robust "approaching settle" signal.
    const double kVSettle = 9.0; // ~half a row per scroll event
    const double kAThresh = 4.0; // jerk magnitude bound
    final decelerating = v * a <= 0.0;
    final nearSettle = v.abs() < kVSettle && a.abs() < kAThresh && decelerating;

    if (nearSettle && !_blameWarmedThisScroll) {
      _blameWarmedThisScroll = true;
      _eagerlyWarmBlame();
    }

    // Hot-zone bridge. Same engram, different payoff: when the reader
    // is decelerating AND the predicted landing sits near a high-φ
    // hunk, flag that hunk so its header row can glow. Runs every
    // tick (not gated by _blameWarmedThisScroll) because the user can
    // meander through multiple hot zones during one scroll gesture.
    _updateHotHunk(v: v, a: a, currentOffset: x);
  }

  /// Predict the line index the scroll is about to settle on.
  /// Returns null when the engram isn't confident enough to call it —
  /// fast scroll (large |v|), or accelerating (|v| rising, v·a > 0).
  ///   x(t)    = x₀ + v·t + ½·a·t²
  ///   settle  when v(t) = 0   →   t* = -v / a
  ///   Δx     = -v²/(2a)   (signed; positive when v > 0 & a < 0)
  int? _predictSettleLineIdx({required double v, required double a}) {
    if (_displayLines.isEmpty) return null;
    if (!_scrollCtrl.hasClients) return null;
    final pos = _scrollCtrl.offset;
    // Near-rest case: velocity already small. The prediction is
    // wherever we are; treat "you've arrived" as the landing so the
    // halo can light on the hunk you actually stopped near.
    if (v.abs() < 4.0) {
      return (pos / _lineItemExtent).round().clamp(0, _displayLines.length - 1);
    }
    if (v * a > 0) return null; // accelerating — not approaching rest
    if (a.abs() < 0.3) {
      // Coasting with no deceleration cue — extrapolate a few rows
      // ahead on velocity alone so a steady-wheel approach still
      // lights the upcoming hunk before you arrive.
      final ahead = pos + v * 6.0;
      final lineIdx = (ahead / _lineItemExtent).round();
      if (lineIdx < 0 || lineIdx >= _displayLines.length) return null;
      return lineIdx;
    }
    final dx = -(v * v) / (2.0 * a);
    // Clamp the predicted distance: the AR(2) can over-extrapolate on
    // noisy ticks. Cap at ~30 rows of travel either way; past that we
    // don't trust the prediction for anticipatory UI.
    const maxLook = 30.0 * _lineItemExtent;
    final bounded = dx.clamp(-maxLook, maxLook);
    final predictedOffset = pos + bounded;
    final lineIdx = (predictedOffset / _lineItemExtent).round();
    if (lineIdx < 0 || lineIdx >= _displayLines.length) return null;
    return lineIdx;
  }

  /// Walk `_hunks` looking for one whose header line lands within a
  /// short window of [settleLine], scored by churn. Sets or clears
  /// [_hotHunkIdx] / [_hotHunkStrength] and schedules a rebuild when
  /// the state actually changed (to avoid extra setState churn on
  /// every scroll tick).
  void _updateHotHunk({
    required double v,
    required double a,
    required double currentOffset,
  }) {
    if (_hunks.isEmpty) {
      _clearHotHunk();
      return;
    }
    final settleLineIdx = _predictSettleLineIdx(v: v, a: a);
    if (settleLineIdx == null) {
      _clearHotHunk();
      return;
    }

    // Translate each hunk's source-index (into `_lines`) into a
    // display-line index via the existing O(1) fastKey map so the
    // distance comparison happens in the same coordinate system as
    // the prediction. Hunk headers are never filtered out, so every
    // lookup resolves — no null checks past the bounds.
    const windowLines = 6;
    int? bestHunk;
    var bestDistance = windowLines + 1;
    for (var i = 0; i < _hunks.length; i++) {
      final h = _hunks[i];
      if (h.lineIndex < 0 || h.lineIndex >= _lines.length) continue;
      final displayIdx = _displayLineIndex[_lines[h.lineIndex].fastKey];
      if (displayIdx == null) continue;
      final d = (displayIdx - settleLineIdx).abs();
      if (d < bestDistance) {
        bestDistance = d;
        bestHunk = i;
      }
    }
    if (bestHunk == null || bestDistance > windowLines) {
      _clearHotHunk();
      return;
    }
    final strength = _importanceForHunkIndex(bestHunk);
    // Relative-churn gate. 0.20 keeps single-line hunks quiet
    // (a 1-line hunk among a 30-line one scores ~0.03 and stays
    // dim) while still firing on any hunk that's plausibly in
    // the same weight class as the file's biggest.
    if (strength < 0.20) {
      _clearHotHunk();
      return;
    }
    if (_hotHunkIdx == bestHunk && (strength - _hotHunkStrength).abs() < 0.05) {
      return; // nothing visibly changed; skip rebuild
    }
    _hotHunkIdx = bestHunk;
    _hotHunkStrength = strength;
    _hotHunkSeenAt = DateTime.now();
    if (mounted) setState(() {});
  }

  void _clearHotHunk() {
    if (_hotHunkIdx == null) return;
    // Decay: keep the halo for up to 900ms after the last prediction
    // so a successfully-anticipated landing gets a moment of "yes,
    // that's where you went" before it fades. When still inside the
    // window, defer via a delayed callback — scroll events may have
    // stopped firing, so nothing else would expire the state.
    final seen = _hotHunkSeenAt;
    if (seen != null) {
      final ageMs = DateTime.now().difference(seen).inMilliseconds;
      if (ageMs < 900) {
        Future.delayed(Duration(milliseconds: 900 - ageMs), () {
          if (!mounted) return;
          _clearHotHunk();
        });
        return;
      }
    }
    _hotHunkIdx = null;
    _hotHunkStrength = 0.0;
    _hotHunkSeenAt = null;
    if (mounted) setState(() {});
  }

  /// Toggle the pinned-line state for [displayIdx]. Clicking the same
  /// row again unpins; clicking a different row swaps.
  Future<void> _togglePinLine(int displayIdx) async {
    if (displayIdx < 0 || displayIdx >= _displayLines.length) return;
    final fastKey = _displayLines[displayIdx].fastKey;
    if (_pinnedFastKey == fastKey) {
      setState(() {
        _clearPinnedLine();
      });
      return;
    }
    final seq = ++_pinSeq;
    setState(() {
      _pinnedFastKey = fastKey;
      _pinnedDisplayIdx = displayIdx;
      _pinnedCtx = null; // reset to loading state
    });
    // Explicit focus signal — pinning a line means the user is
    // actively looking at this file. Parent can use it to keep a
    // side-list of files anchored to the user's attention.
    final pinnedPath = _displayLines[displayIdx].filePath ?? widget.filePath;
    widget.onPinnedFileFocused?.call(pinnedPath);
    final ctx = await _computePinContext(displayIdx);
    if (!mounted || seq != _pinSeq) return;
    setState(() {
      _pinnedFastKey = fastKey;
      _pinnedDisplayIdx = _displayLineIndex[fastKey];
      _pinnedCtx = ctx;
    });
  }

  Future<DiffPinnedContextModel> _computePinContext(int displayIdx) async {
    final line = _displayLines[displayIdx];
    BlameLineData? blame;
    if (line.lineNumNew != null) {
      blame = _blameFor(line.filePath ?? widget.filePath, line.lineNumNew!);
      if (blame == null && widget.repositoryPath != null) {
        await _loadBlame(line.filePath ?? widget.filePath, line.lineNumNew!);
        blame = _blameFor(line.filePath ?? widget.filePath, line.lineNumNew!);
      }
    }
    return DiffLogosFacade.instance.analyzePinnedLine(
      DiffPinnedLineRequest(
        repositoryPath: widget.repositoryPath,
        filePath: widget.filePath,
        line: line,
        displayLines: _displayLines,
        displayIndex: displayIdx,
        couplingMatrix: widget.couplingMatrix,
        revisionRef: _activeRevisionRef,
        queryPathOverride:
            (_activeRevisionRef != null && _trailSelectedPath != null)
                ? _trailSelectedPath
                : (line.filePath ?? widget.filePath),
        warmEngine: _logosSession?.logos?.engine,
        session: _logosSession,
        blame: blame,
      ),
    );
  }

  void _clearPinnedLine() {
    _pinnedFastKey = null;
    _pinnedDisplayIdx = null;
    _pinnedCtx = null;
    _pinSeq++;
  }

  bool _sourceContainsFastKey(int fastKey) =>
      _lines.any((line) => line.fastKey == fastKey);

  void _reconcilePinnedLine() {
    final fastKey = _pinnedFastKey;
    if (fastKey == null) {
      _pinnedDisplayIdx = null;
      return;
    }
    final previousDisplayIdx = _pinnedDisplayIdx;
    _pinnedDisplayIdx = _displayLineIndex[fastKey];
    if (_pinnedDisplayIdx != null || _sourceContainsFastKey(fastKey)) {
      if (_pinnedDisplayIdx != null &&
          previousDisplayIdx != _pinnedDisplayIdx) {
        scheduleMicrotask(_schedulePinnedContextRefresh);
      }
      return;
    }
    _clearPinnedLine();
  }

  void _schedulePinnedContextRefresh() {
    final fastKey = _pinnedFastKey;
    if (fastKey == null) return;
    final displayIdx = _displayLineIndex[fastKey];
    if (displayIdx == null) {
      if (!_sourceContainsFastKey(fastKey) && mounted) {
        setState(_clearPinnedLine);
      }
      return;
    }
    final seq = ++_pinSeq;
    _computePinContext(displayIdx).then((ctx) {
      if (!mounted || seq != _pinSeq) return;
      final resolvedIdx = _displayLineIndex[fastKey];
      if (resolvedIdx == null && !_sourceContainsFastKey(fastKey)) {
        setState(_clearPinnedLine);
        return;
      }
      setState(() {
        _pinnedFastKey = fastKey;
        _pinnedDisplayIdx = resolvedIdx;
        _pinnedCtx = ctx;
      });
    });
  }

  List<String> _warmBlameCandidatePaths() {
    if (_displayLines.isEmpty) return const <String>[];
    final candidates = <String>[];
    final seenKeys = <String>{};

    void addCandidate(String? filePath) {
      if (filePath == null || filePath.isEmpty) return;
      if (!_isBlameEligiblePath(filePath)) return;
      final key = _blameLookupKey(filePath, _activeRevisionRef);
      if (!seenKeys.add(key)) return;
      if (_hasQueuedOrFetchedBlame(key)) return;
      candidates.add(filePath);
    }

    if (_scrollCtrl.hasClients) {
      final topIndex = (_scrollCtrl.offset / _lineItemExtent)
          .floor()
          .clamp(0, _displayLines.length - 1);
      addCandidate(_displayLines[topIndex].filePath ?? widget.filePath);
    }

    if (_hotHunkIdx != null &&
        _hotHunkIdx! >= 0 &&
        _hotHunkIdx! < _hunks.length) {
      addCandidate(_hunks[_hotHunkIdx!].filePath);
    }

    if (candidates.isEmpty) {
      addCandidate(widget.filePath);
    }

    return candidates;
  }

  /// Warm blame for the file the reader is about to land on, not the whole
  /// diff. A single-file prefetch hides hover latency; a full-file fanout
  /// on large multi-diffs just creates a process storm after settle.
  void _eagerlyWarmBlame() {
    if (!_canShowInlineBlame) return;
    final candidates = _warmBlameCandidatePaths();
    if (candidates.isEmpty) return;
    unawaited(() async {
      for (final path in candidates) {
        await _loadBlame(path, 0);
      }
    }());
  }

  /// Capture which unit is currently at the top of the viewport so a later
  /// visit to this file can restore the reader's position. Cheap — runs on
  /// every scroll listener tick but only updates the in-memory map when the
  /// unit id actually changes.
  void _recordTemporalMark() {
    if (!_scrollCtrl.hasClients || _displayLines.isEmpty) return;
    final filePath = widget.filePath;
    if (filePath.isEmpty) return;
    final scopeKey = _temporalMarkScopeKey(filePath);
    final topIdx = (_scrollCtrl.offset / _lineItemExtent)
        .floor()
        .clamp(0, _displayLines.length - 1);
    final line = _displayLines[topIdx];
    final unit = _unitByFastKey[line.fastKey];
    if (unit == null) return;
    final stored = _lastVisitedByFile[scopeKey];
    if (stored == unit.id) return;
    _touchTemporalMark(scopeKey, unit.id);
  }

  /// Schedule a post-frame scroll-to-last-visited + pulse. Idempotent per
  /// file — once the restore fires, the flag blocks subsequent restores for
  /// the same file (re-armed when filePath changes in didUpdateWidget).
  void _scheduleTemporalRestore() {
    if (_temporalRestoreDone) return;
    _temporalRestoreDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _runTemporalRestore());
  }

  void _runTemporalRestore() {
    final stopwatch = Stopwatch()..start();
    if (!mounted || !_scrollCtrl.hasClients) return;
    final filePath = widget.filePath;
    final scopeKey = _temporalMarkScopeKey(filePath);
    final savedUnitId = _readTemporalMark(scopeKey);
    if (savedUnitId == null) {
      // No memory → default to top. Matches prior behaviour for fresh files.
      _scrollCtrl.jumpTo(0);
      return;
    }
    int? targetIdx;
    for (int i = 0; i < _displayLines.length; i++) {
      final unit = _unitByFastKey[_displayLines[i].fastKey];
      if (unit != null && unit.id == savedUnitId) {
        targetIdx = i;
        break;
      }
    }
    if (targetIdx == null) {
      // Stored unit no longer present (file was rewritten) — drop the mark
      // and fall back to the top.
      _lastVisitedByFile.remove(scopeKey);
      _scrollCtrl.jumpTo(0);
      return;
    }
    // Place the target ~1/4 down the viewport for orientation context above.
    final viewH = _scrollCtrl.position.viewportDimension;
    final raw = (targetIdx * _lineItemExtent) - viewH * 0.25;
    final target = raw.clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.jumpTo(target);

    // Pulse the restored unit so the reader sees "you're back here." Clears
    // after the pulse finishes so the row returns to its normal rendering.
    setState(() => _restoredPulseUnitId = savedUnitId);
    _restoredPulseTimer?.cancel();
    _restoredPulseTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() => _restoredPulseUnitId = null);
    });
    _recordUiTimingIfSlow(
      event: 'diff.shell.temporal-restore',
      stopwatch: stopwatch,
      phase: 'interaction',
    );
  }

  bool _onScrollEnd(ScrollEndNotification n) {
    if (_gravitySnapping) return false;
    // Skip hunk-gravity snap when we just landed from a programmatic
    // jump — the jump target was explicit, snapping would yank it
    // back. Consume the flag so subsequent user scrolls snap normally.
    if (_programmaticScrollInFlight) {
      _programmaticScrollInFlight = false;
      return false;
    }
    if (!_scrollCtrl.hasClients) return false;
    if (_hunks.isEmpty) return false;
    // Only react to the vertical ListView; the outer SingleChildScrollView's
    // horizontal end notifications also reach us and would mis-snap.
    if (n.metrics.axis != Axis.vertical) return false;
    // Reduce-motion users don't want scroll kinetics overridden — respect
    // their landing, skip gravity. Intent: peripheral.
    if (_reduceMotion) return false;

    final offset = n.metrics.pixels;
    const threshold = _kGravityLineRadius * _lineItemExtent;
    double? best;
    double bestDist = double.infinity;
    for (final h in _hunks) {
      // h.lineIndex indexes into _lines; find the same ParsedLine in
      // _displayLines (hunk rows are never filtered out by pair collapse or
      // search) so the offset matches what the user actually sees.
      if (h.lineIndex < 0 || h.lineIndex >= _lines.length) continue;
      final idx = _displayLineIndex[_lines[h.lineIndex].fastKey];
      if (idx == null) continue;
      final hOffset = idx * _lineItemExtent;
      final d = (hOffset - offset).abs();
      if (d < bestDist) {
        bestDist = d;
        best = hOffset;
      }
    }
    if (best == null) return false;
    if (bestDist < 1 || bestDist > threshold) return false;

    _gravitySnapping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollCtrl.hasClients) {
        _gravitySnapping = false;
        return;
      }
      final target = best!.clamp(0.0, _scrollCtrl.position.maxScrollExtent);
      await _scrollCtrl.motionAnimateTo(
        target,
        context: context,
        duration: context.surfaceShader.duration,
        curve: context.surfaceShader.safeCurve,
      );
      if (mounted) _gravitySnapping = false;
    });
    return false;
  }

  void _scrollToLine(ParsedLine line) {
    if (!_scrollCtrl.hasClients) return;
    // Integer equality on fastKey — avoids string compare per candidate,
    // and hot on keyboard j/k navigation across large diffs.
    final targetKey = line.fastKey;
    final displayIdx = _displayLines.indexWhere(
      (l) => l.fastKey == targetKey,
    );
    if (displayIdx < 0) return;
    final targetY = displayIdx * _lineItemExtent;
    final viewH = _scrollCtrl.position.viewportDimension;
    final offset = _scrollCtrl.offset;
    if (targetY < offset) {
      _scrollCtrl.motionAnimateTo(targetY,
          context: context,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut);
    } else if (targetY > offset + viewH - _lineItemExtent) {
      _scrollCtrl.motionAnimateTo(targetY - viewH + _lineItemExtent * 2,
          context: context,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut);
    }
  }

  void _scheduleApply() {
    if (!_stagingEnabled) return;
    _applyDebounce?.cancel();
    _applyDebounce = Timer(_kApplyDebounce, _runApply);
  }

  Future<void> _runApply() async {
    if (!_stagingEnabled || _applying) {
      if (_applying) _scheduleApply();
      return;
    }
    final repo = widget.repositoryPath!;
    // Group lines by file path so multi-file diffs apply per-file.
    final byFile = <String, List<ParsedLine>>{};
    for (final line in _lines) {
      final path = line.filePath ?? widget.filePath;
      byFile.putIfAbsent(path, () => []).add(line);
    }

    // Snapshot for rollback on failure.
    final snapshot = _lines.map((l) => l.isStaged).toList(growable: false);

    _applying = true;
    String? firstError;
    for (final entry in byFile.entries) {
      final patch = PatchEngine.buildStagedPatch(entry.key, entry.value);
      final r = await applyFileStaging(repo, entry.key, patch);
      if (!r.ok) {
        firstError = r.error ?? 'git apply failed';
        break;
      }
    }
    _applying = false;
    if (!mounted) return;

    if (firstError != null) {
      // Rollback optimistic toggles.
      setState(() {
        for (int i = 0; i < _lines.length && i < snapshot.length; i++) {
          if (_lines[i].isStaged != snapshot[i]) {
            _lines[i] = _lines[i].copyWith(isStaged: snapshot[i]);
          }
        }
        _stagingError = firstError;
        _refreshDisplayLines();
      });
      return;
    }

    if (_stagingError != null) {
      setState(() => _stagingError = null);
    }
    widget.onStagingApplied?.call();
  }

  /// Called after `_lines` has been replaced. If the keyboard cursor points
  /// at an index that no longer exists, or points at what is now a
  /// non-stageable kind / a filtered paired-add, reset it so subsequent
  /// navigation starts clean rather than skipping forever.
  void _revalidateKeyboardCursor() {
    final idx = _keyboardLineIndex;
    if (idx == null) return;
    if (idx < 0 || idx >= _lines.length) {
      _keyboardLineIndex = null;
      _lastToggledLineIndex = null;
      return;
    }
    final line = _lines[idx];
    if (line.kind != LineKind.added && line.kind != LineKind.deleted) {
      _keyboardLineIndex = null;
    } else if (_pairedAddFastKeys.contains(line.fastKey)) {
      // Cursor would be sitting on a now-hidden paired-add; drop it.
      _keyboardLineIndex = null;
    }
    final last = _lastToggledLineIndex;
    if (last != null && (last < 0 || last >= _lines.length)) {
      _lastToggledLineIndex = null;
    }
  }

  void _refreshDisplayLines() {
    final stopwatch = Stopwatch()..start();
    final filtered = _pairedAddFastKeys.isEmpty
        ? _lines
        : _lines
            .where((line) => !_pairedAddFastKeys.contains(line.fastKey))
            .toList(growable: false);
    final unitMap = _unitByFastKey;

    // Un-staged lines are no longer filtered out completely. They remain in the UI
    // and visually dim, allowing users to tap/drag them again to un-stage.
    final term = _searchTerm.toLowerCase();
    if (term.isEmpty) {
      _setDisplayLines(filtered);
      _recordUiTimingIfSlow(
        event: 'diff.shell.refresh-display',
        stopwatch: stopwatch,
        errorCode: 'diff.shell.refresh-display_failed',
      );
      return;
    }
    // Polyphonic search — a fused pair matches if EITHER side contains the
    // term. Drives off EditUnit.searchText which already joins oldLines and
    // newLines for the unit, so renames ("foo" → "bar") match both "foo"
    // and "bar" regardless of which side survives in the filtered display
    // list.
    //
    // Two-stage SWAR pre-filter: compute the query's 64-bit character
    // bitmap AND its 64-bit bigram bitmap once, then reject any line/unit
    // whose bitmaps don't cover the query's. For long queries the char
    // bitmap saturates (every line contains 'f', 'u', 'n', …) but the
    // bigram bitmap carries much more entropy — lines without any of the
    // query's specific 2-grams cannot contain the query. Cumulative
    // rejection typically drops pass-through to <1% for 4+ char queries.
    // See ParsedLine.charBits / ParsedLine.bigramBits for the schemes.
    final termBits = ParsedLine.queryCharBits(term);
    final termBi = ParsedLine.queryBigramBits(term);
    _setDisplayLines(filtered.where((line) {
      if ((line.charBits & termBits) == termBits &&
          (line.bigramBits & termBi) == termBi) {
        if (line.lowerText.contains(term)) return true;
      }
      final unit = unitMap[line.fastKey];
      if (unit == null) return false;
      if ((unit.charBits & termBits) != termBits) return false;
      if ((unit.bigramBits & termBi) != termBi) return false;
      return unit.searchText.contains(term);
    }).toList());
    _recordUiTimingIfSlow(
      event: 'diff.shell.refresh-display',
      stopwatch: stopwatch,
      errorCode: 'diff.shell.refresh-display_failed',
    );
  }

  /// Assign [_displayLines] and rebuild the fastKey → display-index
  /// lookup in one shot. Every caller that used to write
  /// `_displayLines = x` should go through here so the index never
  /// goes stale.
  void _setDisplayLines(List<ParsedLine> lines) {
    _displayLines = _searchTerm.isEmpty ? _applyAdaptiveContext(lines) : lines;
    if (lines.isEmpty) {
      _displayLineIndex = const {};
      _hunkDisplayRows = const [];
      _reconcilePinnedLine();
      _syncLogosSubscriptions();
      return;
    }
    final idx = <int, int>{};
    for (var i = 0; i < _displayLines.length; i++) {
      idx[_displayLines[i].fastKey] = i;
    }
    _displayLineIndex = idx;
    if (_hunks.isEmpty) {
      _hunkDisplayRows = const [];
      return;
    }
    final rows = List<int>.filled(_hunks.length, -1);
    for (var i = 0; i < _hunks.length; i++) {
      final hi = _hunks[i].lineIndex;
      if (hi < 0 || hi >= _lines.length) continue;
      rows[i] = idx[_lines[hi].fastKey] ?? -1;
    }
    _hunkDisplayRows = rows;
    _reconcilePinnedLine();
    _syncLogosSubscriptions();
  }

  double _measureMaxLineWidth(int maxChars) {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'M',
        style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final charWidth = painter.width > 0 ? painter.width : 7.5;
    const gutterW = 56.0;
    const sidePad = 16.0;
    const minW = 400.0;
    const maxW = 12000.0;
    return (gutterW + sidePad + maxChars * charWidth).clamp(minW, maxW);
  }

  void _jumpToHunkIndex(int hunkIdx) {
    if (hunkIdx < 0 || hunkIdx >= _hunks.length) return;
    final displayIdx =
        hunkIdx < _hunkDisplayRows.length ? _hunkDisplayRows[hunkIdx] : -1;
    if (displayIdx >= 0) {
      _jumpToDisplayIndex(displayIdx);
      return;
    }
    _jumpToLineIndex(_hunks[hunkIdx].lineIndex);
  }

  void _jumpToLineIndex(int lineIdx) {
    if (lineIdx < 0 || lineIdx >= _lines.length) return;
    for (var delta = 0; delta < _lines.length; delta++) {
      final forward = lineIdx + delta;
      if (forward < _lines.length) {
        final displayIdx = _displayLineIndex[_lines[forward].fastKey];
        if (displayIdx != null) {
          _jumpToDisplayIndex(displayIdx);
          return;
        }
      }
      if (delta == 0) continue;
      final backward = lineIdx - delta;
      if (backward >= 0) {
        final displayIdx = _displayLineIndex[_lines[backward].fastKey];
        if (displayIdx != null) {
          _jumpToDisplayIndex(displayIdx);
          return;
        }
      }
    }
  }

  void _jumpToDisplayIndex(int displayIdx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) {
        return;
      }
      const lineH = 18.0;
      final targetOffset = (displayIdx * lineH).clamp(
        0.0,
        _scrollCtrl.position.maxScrollExtent,
      );
      _programmaticScrollInFlight = true;
      _scrollCtrl.motionAnimateTo(
        targetOffset,
        context: context,
        duration: context.surfaceShader.duration,
        curve: context.surfaceShader.safeCurve,
      );
    });
  }

  // Regex matches our own synthetic multi-file label: "N selected files".
  static final RegExp _multiFileLabelRe = RegExp(r'^\d+ selected files?$');

  /// Returns the single file path the trail should operate on, or null
  /// if this DiffShell is showing a multi-file diff, a synthetic label
  /// (like a stash peek), or otherwise can't unambiguously identify one file.
  String? _resolvedTrailFilePath() {
    final paths = _uniqueFilePathsInDiff();
    if (paths.length != 1) return null;
    final only = paths.first;
    // Reject known synthetic labels the app produces when there's no real
    // single file to point at. Real paths with spaces (e.g. "My Docs/file.md")
    // are valid and pass through.
    if (_multiFileLabelRe.hasMatch(only)) return null;
    if (only.startsWith('filed:')) return null;
    return only;
  }

  String _trailCacheKey(String commitHash, String pathAt) =>
      '$commitHash\u0000$pathAt';

  _TrailViewState _captureTrailView() {
    return _TrailViewState(
      diffContent: _effectiveDiffContent ?? '',
      lines: List<ParsedLine>.of(_lines),
      hunks: List<_HunkHeader>.of(_hunks),
      pairedAddFastKeys: Set<int>.of(_pairedAddFastKeys),
      unitByFastKey: Map<int, EditUnit>.of(_unitByFastKey),
      maxLineWidth: _maxLineWidth,
    );
  }

  void _restoreTrailView(_TrailViewState view) {
    _currentDiffContent = view.diffContent;
    _currentDocument = null;
    _lines = view.lines;
    _hunks = view.hunks;
    _rebuildHunkHeaderLookup();
    _pairedAddFastKeys = view.pairedAddFastKeys;
    _unitByFastKey = view.unitByFastKey;
    _seenUnitIds.clear();
    _refreshDisplayLines();
    _maxLineWidth = view.maxLineWidth;
    _revalidateKeyboardCursor();
    _syncLogosRuntime(forceRefresh: true);
  }

  void _rebuildHunkHeaderLookup() {
    if (_hunks.isEmpty || _lines.isEmpty) {
      _hunkHeaderByFastKey = const {};
      return;
    }
    final byFastKey = <int, _HunkHeader>{};
    for (final header in _hunks) {
      final lineIndex = header.lineIndex;
      if (lineIndex < 0 || lineIndex >= _lines.length) {
        continue;
      }
      byFastKey[_lines[lineIndex].fastKey] = header;
    }
    _hunkHeaderByFastKey = byFastKey;
  }

  void _rememberTrailView(String key, _TrailViewState view) {
    _trailViewCache.remove(key);
    _trailViewCache[key] = view;
    while (_trailViewCache.length > _kTrailViewCacheLimit) {
      _trailViewCache.remove(_trailViewCache.keys.first);
    }
  }

  void _scheduleTrailStopLoad({
    required String commitHash,
    required String pathAt,
    required String? previousHash,
    required String? previousPath,
  }) {
    _trailScrubDebounce?.cancel();
    final cacheKey = _trailCacheKey(commitHash, pathAt);
    final cachedView = _trailViewCache[cacheKey];
    if (cachedView != null) {
      _trailLoadSeq++;
      setState(() {
        _restoreTrailView(cachedView);
      });
      _schedulePinnedContextRefresh();
      if (_wearMapVisible) {
        _batchLoadWearBlame();
      }
      return;
    }
    _trailScrubDebounce = Timer(_kTrailScrubDebounce, () {
      _loadTrailStop(
        commitHash: commitHash,
        pathAt: pathAt,
        previousHash: previousHash,
        previousPath: previousPath,
      );
    });
  }

  Future<void> _loadTrailStop({
    required String commitHash,
    required String pathAt,
    required String? previousHash,
    required String? previousPath,
  }) async {
    _trailScrubDebounce = null;
    final repo = widget.repositoryPath;
    if (repo == null) return;
    if (_trailSelectedHash != commitHash || _trailSelectedPath != pathAt) {
      return;
    }
    final seq = ++_trailLoadSeq;
    final result = await getFileDiffAtRevision(repo, pathAt, commitHash);
    if (!mounted ||
        seq != _trailLoadSeq ||
        _trailSelectedHash != commitHash ||
        _trailSelectedPath != pathAt) {
      return;
    }
    if (result.ok) {
      final cacheKey = _trailCacheKey(commitHash, pathAt);
      setState(() {
        _reparse(result.data!);
        _rememberTrailView(cacheKey, _captureTrailView());
      });
      _schedulePinnedContextRefresh();
      if (_wearMapVisible) {
        _batchLoadWearBlame();
      }
      return;
    }
    setState(() {
      _trailSelectedHash = previousHash;
      _trailSelectedPath = previousPath;
    });
  }

  void _toggleTrail() {
    if (_trailVisible) {
      _trailScrubDebounce?.cancel();
      _trailScrubDebounce = null;
      _trailLoadSeq++;
      final original = _originalDiffContent;
      final nowView = _trailNowView;
      setState(() {
        _trailVisible = false;
        _trailHistory = const [];
        _trailSelectedHash = null;
        _trailSelectedPath = null;
        _originalDiffContent = null;
        if (nowView != null) {
          _restoreTrailView(nowView);
        } else if (original != null) {
          _reparse(original);
        }
      });
      _schedulePinnedContextRefresh();
      return;
    }
    final repo = widget.repositoryPath;
    if (repo == null) return;
    final trailPath = _resolvedTrailFilePath();
    if (trailPath == null) return;
    setState(() {
      _trailVisible = true;
      _trailLoading = true;
      _originalDiffContent = _effectiveDiffContent;
      _trailNowView = _captureTrailView();
    });
    listFileHistoryWithPaths(repo, trailPath).then((result) {
      if (!mounted) return;
      setState(() {
        _trailLoading = false;
        _trailHistory = result.ok ? result.data! : const [];
      });
    });
  }

  void _selectTrailStop(String commitHash) {
    final repo = widget.repositoryPath;
    if (repo == null) return;
    // Resolve the path AT this historical commit — critical for renames:
    // a commit from before the rename must be queried with the old name.
    final historyEntry = _trailHistory.firstWhere(
      (e) => e.commit.commitHash == commitHash,
      orElse: () => FileHistoryEntry(
        commit: CommitHistoryEntry(
          commitHash: '',
          shortHash: '',
          parentHashes: const [],
          refNames: const [],
          isMerge: false,
          subject: '',
          authorName: '',
          authorEmail: '',
          authoredAt: '',
        ),
        pathAtRevision: _resolvedTrailFilePath() ?? widget.filePath,
      ),
    );
    final pathAt = historyEntry.pathAtRevision;
    if (_trailSelectedHash == commitHash && _trailSelectedPath == pathAt) {
      return;
    }
    // Snapshot the previous selection so we can roll back on failure —
    // avoids the UI showing a selected hash whose diff never loaded.
    final previousHash = _trailSelectedHash;
    final previousPath = _trailSelectedPath;
    setState(() {
      _trailSelectedHash = commitHash;
      _trailSelectedPath = pathAt;
    });
    _scheduleTrailStopLoad(
      commitHash: commitHash,
      pathAt: pathAt,
      previousHash: previousHash,
      previousPath: previousPath,
    );
    /*
        // Wear map is keyed by revision — if it's active, kick off a
        // blame load for the new revision so the heatmap stays populated
        // instead of blanking out until the user hovers each line.
        if (_wearMapVisible) {
          _batchLoadWearBlame();
        }
      } else {
        // Fetch failed — revert the selection so the strip and diff stay
        // in sync. The diff content remains whatever was last visible.
        setState(() {
          _trailSelectedHash = previousHash;
          _trailSelectedPath = previousPath;
        });
      }
    });
    */
  }

  void _selectTrailNow() {
    if (_trailSelectedHash == null && _trailSelectedPath == null) {
      return;
    }
    _trailScrubDebounce?.cancel();
    _trailScrubDebounce = null;
    _trailLoadSeq++;
    final nowView = _trailNowView;
    setState(() {
      _trailSelectedHash = null;
      _trailSelectedPath = null;
      if (nowView != null) {
        _restoreTrailView(nowView);
      } else if (_originalDiffContent != null) {
        _reparse(_originalDiffContent!);
      }
    });
    _schedulePinnedContextRefresh();
    if (_wearMapVisible) {
      _batchLoadWearBlame();
    }
  }

  void _reparse(String content) {
    _applyDocument(
      DiffDocument.fromRawContent(
        rawContent: content,
        pathHint: widget.filePath,
        trimLeadingMeta: widget.showFileHeader,
      ),
    );
    // _lines changed → unit/pair/unitMap caches are stale. Recompute
    // before the search filter pass reads them.
    _syncLogosRuntime(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    // Diff shell only cares about three motion/hover prefs — narrow
    // the subscription so pref writes for unrelated knobs (sort guide,
    // commit voice, update channel, …) don't invalidate the entire
    // diff body. Dart records use structural equality, so the rebuild
    // fires only on a genuine value change.
    final motionPrefs = context.select<PreferencesState,
        ({bool reduceMotion, double motionRate, bool instantBlameHover})>(
      (s) => (
        reduceMotion: s.reduceMotion,
        motionRate: s.motionRate,
        instantBlameHover: s.instantBlameHover,
      ),
    );
    _reduceMotion = motionPrefs.reduceMotion;
    _motionRate = motionPrefs.motionRate;
    _instantBlameHover = motionPrefs.instantBlameHover;
    final hasContent =
        (_effectiveDiffContent != null && _effectiveDiffContent!.isNotEmpty) ||
            _lines.isNotEmpty;
    final toolbarFilePath = widget.toolbarFilePath ?? widget.filePath;
    final toolbarOnTap = widget.toolbarOnTap ??
        ((widget.repositoryPath != null && _resolvedTrailFilePath() != null)
            ? _toggleTrail
            : null);
    final toolbarActive = widget.toolbarActive ?? _trailVisible;

    if (widget.loading && !hasContent) {
      return const AppStatusView.loading(
        title: 'Loading diff',
        message: 'Reading file changes.',
        compact: true,
      );
    }
    if (widget.error != null && !hasContent) {
      return AppStatusView.error(
        title: 'Diff unavailable',
        message: widget.error!,
        compact: true,
      );
    }
    if (!hasContent) {
      return const AppStatusView(
        title: 'No changes',
        message: 'This file has no diff content to display.',
        compact: true,
      );
    }

    final displayLines = _displayLines;

    return Stack(children: [
      Column(children: [
        if (_trailVisible)
          _TrailStrip(
            tokens: t,
            history: _trailHistory,
            loading: _trailLoading,
            selectedHash: _trailSelectedHash,
            onSelectStop: _selectTrailStop,
            onSelectNow: _selectTrailNow,
          ),
        MaterialSurface(
          tone: AppMaterialTone.surface1,
          radius: 0,
          border: Border(
            bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.12)),
          ),
          elevated: false,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            // Back button — visible only when the parent has a nav
            // history to pop. Sits before the search toggle so the
            // leading cluster reads as "navigation, then find".
            if (widget.onNavigateBack != null) ...[
              _ToolbarBtn(
                icon: 'chevron-left',
                active: false,
                t: t,
                onTap: widget.onNavigateBack!,
              ),
              const SizedBox(width: 4),
            ],
            // Search toggle. Tinted with the same accent the file-status
            // dot uses so the icon visually pairs with the dot beside it
            // — the search becomes part of "this file's chrome" instead
            // of reading as a generic, muted toolbar action.
            _ToolbarBtn(
              icon: 'search',
              active: _searchVisible,
              t: t,
              iconColorOverride: t.accentBright,
              onTap: () => setState(() {
                _searchVisible = !_searchVisible;
                _sessionSearchActivated =
                    _sessionSearchActivated || _searchVisible;
                if (!_searchVisible) {
                  _searchTerm = '';
                  _searchCtrl.clear();
                  _refreshDisplayLines();
                }
              }),
            ),
            // Search input (takes over the filename slot when open)
            if (_searchVisible) ...[
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  height: 24,
                  fontSize: 12,
                  hintText: 'search diff...',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  onChanged: (v) => setState(() {
                    _searchTerm = v;
                    _sessionSearchActivated =
                        _sessionSearchActivated || v.isNotEmpty;
                    _refreshDisplayLines();
                  }),
                ),
              ),
              if (_searchTerm.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  '${displayLines.length} line${displayLines.length == 1 ? "" : "s"}',
                  style: TextStyle(color: t.textMuted, fontSize: 10),
                ),
              ],
            ] else ...[
              // Compact filename beside the search icon — the filename
              // that used to sit in the big file header row. Click
              // toggles the paper trail (same behavior as before).
              // Takes the toolbar's left region; Spacer after pushes
              // hunk nav + blame chip to the right. Hides entirely
              // when search opens so the input has the full width.
              const SizedBox(width: 10),
              Expanded(
                child: _ToolbarFileNameChip(
                  tokens: t,
                  filePath: toolbarFilePath,
                  label: widget.toolbarLabel,
                  tooltip: widget.toolbarTooltip,
                  onTap: toolbarOnTap,
                  trailActive: toolbarActive,
                ),
              ),
            ],

            // Hunk navigation
            if (_hunks.isNotEmpty && !_searchVisible) ...[
              const SizedBox(width: 6),
              _HunkDropdown(hunks: _hunks, t: t, onJump: _jumpToHunkIndex),
            ],

            // Blame / wear map indicator (click toggles wear map)
            if (_blameFetchingFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'blame...',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_canShowInlineBlame && _blameFetchingFiles.isEmpty)
              Tooltip(
                message: _wearMapVisible
                    ? 'wear map on — click to hide'
                    : 'show wear map (activity heatmap)',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _toggleWearMap,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        _wearMapVisible ? 'wear · on' : 'blame',
                        style: TextStyle(
                          color: _wearMapVisible
                              ? t.hyperChromatic1
                              : (_blameByFile.isNotEmpty
                                  ? t.hyperChromatic1.withValues(alpha: 0.7)
                                  : t.textMuted),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Focus(
                  focusNode: _stagingFocus,
                  onKeyEvent: _handleKey,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _stagingEnabled
                        ? () => _stagingFocus.requestFocus()
                        : null,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: true),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Content is at least as wide as the viewport so there's
                          // no unnecessary horizontal scroll when lines are short.
                          final contentWidth =
                              _maxLineWidth > constraints.maxWidth
                                  ? _maxLineWidth
                                  : constraints.maxWidth;
                          return SingleChildScrollView(
                            controller: _hScrollCtrl,
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            child: SizedBox(
                              width: contentWidth,
                              child:
                                  NotificationListener<ScrollEndNotification>(
                                onNotification: _onScrollEnd,
                                child: ListView.builder(
                                  key: _listViewKey,
                                  controller:
                                      _searchVisible ? null : _scrollCtrl,
                                  padding: const EdgeInsets.only(bottom: 16),
                                  itemCount: displayLines.length,
                                  itemExtent: _lineItemExtent,
                                  itemBuilder: (ctx, i) {
                                    final line = displayLines[i];
                                    final lineFile =
                                        line.filePath ?? widget.filePath;
                                    final kbFocused = _stagingEnabled &&
                                        _keyboardLineIndex != null &&
                                        _keyboardLineIndex! >= 0 &&
                                        _keyboardLineIndex! < _lines.length &&
                                        identical(
                                            _lines[_keyboardLineIndex!], line);
                                    // Hot-zone bridge: the scroll engram has
                                    // predicted we're about to land on this
                                    // hunk AND it's a high-churn one. A thin
                                    // accent wash + rail on the row renders
                                    // the anticipation.
                                    final hotHunkIdx = _hotHunkIdx;
                                    final isHotHunkRow = hotHunkIdx != null &&
                                        line.kind == LineKind.hunk &&
                                        hotHunkIdx < _hunks.length &&
                                        _hunks[hotHunkIdx].lineIndex >= 0 &&
                                        _hunks[hotHunkIdx].lineIndex <
                                            _lines.length &&
                                        identical(
                                            line,
                                            _lines[
                                                _hunks[hotHunkIdx].lineIndex]);
                                    final rowFastKey = line.fastKey;
                                    final rowUnit = _unitByFastKey[rowFastKey];
                                    final hunkHeader =
                                        line.kind == LineKind.hunk
                                            ? _headerForDisplayLine(line)
                                            : null;
                                    final hunkSignal = hunkHeader == null
                                        ? null
                                        : _logosSignalForHeader(hunkHeader);
                                    final lineResidual =
                                        _logosResidualForLine(line);
                                    final pulseActive =
                                        _restoredPulseUnitId != null &&
                                            rowUnit?.id == _restoredPulseUnitId;
                                    final isPinnedRhyme = _pinnedCtx != null &&
                                        _pinnedDisplayIdx != null &&
                                        i != _pinnedDisplayIdx &&
                                        _pinnedCtx!.rhymeDisplayIdxs
                                            .contains(i);
                                    // Lineage animation gate: play one-shot reveals
                                    // ONLY the first time a given unit id appears in
                                    // this diff session. Scroll-recycle re-mounts
                                    // don't replay anything → the diff stays static
                                    // during scroll instead of strobing.
                                    final firstAppearance = rowUnit != null &&
                                        _seenUnitIds.add(rowUnit.id);
                                    final lineView = DiffLineView(
                                      // Key on fastKey (integer content hash, stable
                                      // across stage toggles). Replaces the old
                                      // stagingKey-string key which allocated a ~40
                                      // char String per visible row per frame. Integer
                                      // ValueKey is zero-alloc and hashes in one cycle.
                                      key: ValueKey<int>(rowFastKey),
                                      line: line,
                                      editUnit: rowUnit,
                                      pulseActive: pulseActive,
                                      firstAppearance: firstAppearance,
                                      // Scroll-stress overrides the user's rate
                                      // (rows flooding into view during fast scroll
                                      // would otherwise fire a storm of temperature
                                      // sweeps / melts / ghost fades). At rest, the
                                      // user's chosen rate takes over — so a tuned
                                      // rate of 0.5 still plays reveals, just slower.
                                      //
                                      // Two const instances cover the "no motion"
                                      // (scroll or reduce) and "full" (rate=1)
                                      // cases without allocation; intermediate rates
                                      // allocate per-build but only when the user
                                      // has actually tuned the slider away from 1.0.
                                      motionPolicy: _scrolling || _reduceMotion
                                          ? MotionPolicy.reduced
                                          : (_motionRate == 1.0
                                              ? MotionPolicy.full
                                              : MotionPolicy(
                                                  rate: _motionRate)),
                                      tokens: t,
                                      blameEntry: line.lineNumNew != null
                                          ? _blameFor(
                                              lineFile, line.lineNumNew!)
                                          : null,
                                      hovered:
                                          _hoveredLine == line.lineNumNew &&
                                              line.lineNumNew != null,
                                      onGutterEnter: _canShowInlineBlame &&
                                              line.lineNumNew != null
                                          ? () {
                                              // Suppress blame trigger while
                                              // scrolling: with whole-row hover, a
                                              // stationary cursor fires onEnter on
                                              // every row that scrolls under it.
                                              // Only a deliberate hover (viewport at
                                              // rest + cursor on the row) should
                                              // load blame and show the chip.
                                              if (_scrolling) return;
                                              setState(() => _hoveredLine =
                                                  line.lineNumNew!);
                                              _scheduleBlameLoad(
                                                  lineFile, line.lineNumNew!);
                                            }
                                          : null,
                                      onGutterExit: () {
                                        _blameHoverTimer?.cancel();
                                        setState(() => _hoveredLine = null);
                                      },
                                      searchTerm: _searchTerm,
                                      useAnimatedTextMode:
                                          _useAnimatedTextMode &&
                                              !_reduceMotion,
                                      contextBand: _contextBandForLine(line),
                                      hunkImportance: math.max(
                                        hunkSignal?.importance ?? 0.0,
                                        lineResidual?.importance ?? 0.0,
                                      ),
                                      hunkTag: hunkSignal?.tag,
                                      hunkHeaderHint: hunkSignal?.headerHint,
                                      hunkTransportPull: math.max(
                                        hunkSignal?.transportPull ?? 0.0,
                                        lineResidual?.transportPull ?? 0.0,
                                      ),
                                      hunkTransportedSupport: math.max(
                                        hunkSignal?.transportedSupport ?? 0.0,
                                        lineResidual?.transportedSupport ?? 0.0,
                                      ),
                                      hunkInnovationResidual: math.max(
                                        hunkSignal?.innovationResidual ?? 0.0,
                                        lineResidual?.innovationResidual ?? 0.0,
                                      ),
                                      hunkWitnessResidual: math.max(
                                        hunkSignal?.witnessResidual ?? 0.0,
                                        lineResidual?.witnessResidual ?? 0.0,
                                      ),
                                      relatedRhyme: isPinnedRhyme,
                                      wearIntensity: _wearMapVisible &&
                                              line.lineNumNew != null
                                          ? _wearIntensityFor(
                                              lineFile, line.lineNumNew!)
                                          : null,
                                      stageCellWidth: _stageCellWidth,
                                      stagingEnabled: _stagingEnabled,
                                      keyboardFocused: kbFocused,
                                      onSigilTap: _stagingEnabled
                                          ? (shift, alt) {
                                              _stagingFocus.requestFocus();
                                              _handleSigilTap(line,
                                                  shift: shift, alt: alt);
                                            }
                                          : null,
                                      onPaintStart: _stagingEnabled
                                          ? () {
                                              _stagingFocus.requestFocus();
                                              _beginPaint(line);
                                            }
                                          : null,
                                      onPaintMove:
                                          _stagingEnabled ? _paintUpdate : null,
                                      onPaintEnd:
                                          _stagingEnabled ? _endPaint : null,
                                      onHunkDoubleTap: _stagingEnabled
                                          ? () {
                                              _stagingFocus.requestFocus();
                                              _handleHunkDoubleTap(
                                                  line.hunkIndex);
                                            }
                                          : null,
                                    );
                                    // Primary or secondary click any row →
                                    // pin it for the Logos context panel.
                                    // Listener sits at `translucent` so
                                    // text-selection drags inside
                                    // SelectableText still start; tap-down
                                    // pins on the press.
                                    final isPinned = _pinnedDisplayIdx == i;
                                    Widget wrapped = Listener(
                                      behavior: HitTestBehavior.translucent,
                                      onPointerDown: (e) {
                                        final isPrimary =
                                            (e.buttons & kPrimaryButton) != 0;
                                        final isSecondary =
                                            (e.buttons & kSecondaryButton) != 0;
                                        if (!isPrimary && !isSecondary) {
                                          return;
                                        }
                                        // Ignore the sigil column (tiny ± cell
                                        // near the left gutter) so stage
                                        // clicks still do their job without
                                        // stealing a pin.
                                        if (e.localPosition.dx <
                                            _stageCellWidth) {
                                          return;
                                        }
                                        _togglePinLine(i);
                                      },
                                      child: lineView,
                                    );
                                    if (isPinned) {
                                      wrapped = DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: t.accentBright
                                              .withValues(alpha: 0.08),
                                          border: Border(
                                            left: BorderSide(
                                              color: t.accentBright,
                                              width: 3,
                                            ),
                                          ),
                                        ),
                                        child: wrapped,
                                      );
                                    }
                                    // Inline hunk-context hint — IDE-style
                                    // inlay rendered at the right edge of
                                    // every hunk header row, showing weight
                                    // (+A −D), position in the file (3/8),
                                    // and — when the scroll engram has
                                    // predicted a landing here — a faint
                                    // "approaching" marker. The prediction
                                    // drives EMPHASIS, not a phantom halo.
                                    if (line.kind != LineKind.hunk)
                                      return wrapped;
                                    if (hunkHeader == null) return wrapped;
                                    final hunkOrdinal =
                                        _hunks.indexOf(hunkHeader) + 1;
                                    final totalHunks = _hunks.length;
                                    return Stack(
                                      children: [
                                        wrapped,
                                        Positioned(
                                          right: 14,
                                          top: 0,
                                          bottom: 0,
                                          child: IgnorePointer(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: _HunkInlineHint(
                                                additions: hunkHeader.additions,
                                                deletions: hunkHeader.deletions,
                                                ordinal: hunkOrdinal,
                                                total: totalHunks,
                                                tag: hunkSignal?.tag,
                                                hint: hunkSignal?.headerHint,
                                                tokens: t,
                                                approaching: isHotHunkRow,
                                                approachStrength:
                                                    _hotHunkStrength,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // Sticky hunk header — pins the current @@ label at the top
              // when you're scrolled deep inside a hunk. Suppressed during
              // search (results are flat; hunks aren't meaningful).
              if (_hunks.isNotEmpty && !_searchVisible && _searchTerm.isEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _StickyHunkHeader(
                    tokens: t,
                    hunks: _hunks,
                    // Parallel to [_hunks], but in DISPLAY coordinate
                    // space (paired-add filtering collapsed). The sticky
                    // header compares against scroll offset, which is in
                    // display space too, so these must match.
                    hunkDisplayRows: _hunkDisplayRows,
                    scrollCtrl: _scrollCtrl,
                    lineExtent: _lineItemExtent,
                    onJump: _jumpToHunkIndex,
                  ),
                ),
            ],
          ),
        ),
        if (_stagingError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: t.stateDeleted.withValues(alpha: 0.12),
            child: Text(
              'Partial stage failed: $_stagingError',
              style: TextStyle(
                color: t.stateDeleted,
                fontSize: 10.5,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ),
        // Pinned-line context panel. Docks at the bottom when a row
        // has been right-clicked; collapses cleanly when the pin is
        // cleared so the diff list reclaims its space.
        if (_pinnedFastKey != null && _pinnedDisplayIdx != null)
          _PinnedContextPanel(
            tokens: t,
            context: _pinnedCtx,
            past: _buildPinnedPastContext(_pinnedCtx),
            loading: _pinnedDisplayIdx != null && _pinnedCtx == null,
            onOpenRelatedPath: widget.onOpenRelatedPath,
            onClose: () {
              setState(() {
                _clearPinnedLine();
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _stagingFocus.requestFocus();
                }
              });
            },
            onRhymeTap: (targetIdx) {
              if (!_scrollCtrl.hasClients) return;
              final offset = targetIdx * _lineItemExtent;
              _scrollCtrl.animateTo(
                offset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
            },
          ),
      ]),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AnimatedOpacity(
          opacity: widget.loading ? 1 : 0,
          duration: const Duration(milliseconds: 80),
          child: LinearProgressIndicator(
            minHeight: 2,
            color: t.accentBright.withValues(alpha: 0.7),
            backgroundColor: Colors.transparent,
          ),
        ),
      ),
    ]);
  }
}

class DiffLineView extends StatefulWidget {
  final ParsedLine line;

  /// Semantic unit this line belongs to — carries move-target pointers, unit
  /// kind, constituent lines, and the stable id used for animation keys.
  /// For replace units the paired add sits at `editUnit.newLines.first`;
  /// for move units the counterpart is located via [EditUnit.moveTargetId].
  /// Optional so the line row still works if a unit couldn't be resolved
  /// (always resolves in current code, tolerance is cheap insurance).
  final EditUnit? editUnit;

  /// Temporal mark — when true, this row briefly pulses an accent overlay to
  /// signal "you're back here" after a restore. Parent owns the timer; the
  /// row just animates the fade.
  final bool pulseActive;

  /// True the first time the parent has seen this row's unit id in the
  /// current diff session. Gates one-shot lineage animations (pair melt)
  /// so they play once per unit, not every time a row scrolls back into
  /// view. Owner: [_DiffShellState._seenUnitIds].
  final bool firstAppearance;

  /// Central motion-gating policy. Every animation in this row routes through
  /// it; reduce-motion users get the final state without the ornaments, but
  /// keep confirmation/attention motion in softened form.
  final MotionPolicy motionPolicy;
  final AppTokens tokens;
  final BlameLineData? blameEntry;
  final bool hovered;
  final VoidCallback? onGutterEnter;
  final VoidCallback onGutterExit;
  final String searchTerm;
  final bool useAnimatedTextMode;
  final double? wearIntensity;
  final DiffContextBand? contextBand;
  final double hunkImportance;
  final String? hunkTag;
  final String? hunkHeaderHint;
  final double hunkTransportPull;
  final double hunkTransportedSupport;
  final double hunkInnovationResidual;
  final double hunkWitnessResidual;
  final bool relatedRhyme;

  // Staging
  final double stageCellWidth;
  final bool stagingEnabled;
  final bool keyboardFocused;

  /// Tap on the stage sigil. Booleans carry shift/alt modifier state.
  final void Function(bool shift, bool alt)? onSigilTap;

  /// Vertical drag started on the stage sigil of this line — paint mode.
  final VoidCallback? onPaintStart;
  final void Function(Offset globalPosition)? onPaintMove;
  final VoidCallback? onPaintEnd;

  /// Double-click on the hunk header row — toggles the whole hunk.
  final VoidCallback? onHunkDoubleTap;

  const DiffLineView({
    Key? key,
    required this.line,
    this.editUnit,
    this.pulseActive = false,
    this.firstAppearance = false,
    this.motionPolicy = MotionPolicy.full,
    required this.tokens,
    required this.blameEntry,
    required this.hovered,
    required this.onGutterEnter,
    required this.onGutterExit,
    required this.searchTerm,
    required this.useAnimatedTextMode,
    this.wearIntensity,
    this.contextBand,
    this.hunkImportance = 0.0,
    this.hunkTag,
    this.hunkHeaderHint,
    this.hunkTransportPull = 0.0,
    this.hunkTransportedSupport = 0.0,
    this.hunkInnovationResidual = 0.0,
    this.hunkWitnessResidual = 0.0,
    this.relatedRhyme = false,
    this.stageCellWidth = 16.0,
    this.stagingEnabled = false,
    this.keyboardFocused = false,
    this.onSigilTap,
    this.onPaintStart,
    this.onPaintMove,
    this.onPaintEnd,
    this.onHunkDoubleTap,
  }) : super(key: key);

  @override
  State<DiffLineView> createState() => _DiffLineState();
}

class _DiffLineState extends State<DiffLineView> {
  /// Hover specifically over the stage sigil cell. Drives the sigil's
  /// hover-border affordance. Hover state is intentionally narrow so the
  /// whole left margin doesn't look clickable when only the sigil is.
  bool _lineHover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final l = widget.line;
    final isMeta = l.kind == LineKind.meta;
    final isAdded = l.kind == LineKind.added;
    final isDeleted = l.kind == LineKind.deleted;
    final isHunk = l.kind == LineKind.hunk;
    final isFoldMarker = isMeta &&
        l.text.startsWith('... ') &&
        l.text.contains('unchanged lines');
    final isStageable = isAdded || isDeleted;
    // Semantic unit for this row (replace, move, insert, delete, context,
    // hunk, meta). Single source of truth for row-kind decisions — pair
    // rendering, move rendering, and animation gating all read from it.
    final EditUnit? unit = widget.editUnit;

    // Replacement pair — this delete carries its add partner at
    // `unit.newLines.first`. Row renders as a single fused transition
    // instead of two stacked ±rows. Derived from the unit directly so no
    // separate `pairedAdd` widget prop needs to be plumbed through.
    final bool isPair = isDeleted &&
        unit?.kind == EditKind.replace &&
        (unit?.newLines.isNotEmpty ?? false);
    final ParsedLine? addPart = isPair ? unit!.newLines.first : null;

    // Block-move detection — the EditUnit layer has matched this line to a
    // counterpart elsewhere in the file. Render with a distinct chromatic
    // accent so reviewers can see "this code moved" vs "this code was
    // deleted", without changing staging semantics (git still stages the
    // underlying +/− independently; moves are a presentation layer).
    final bool isMove = unit?.kind == EditKind.move;
    final bool isMoveFrom = isMove && (unit?.oldLines.isNotEmpty ?? false);
    final bool isMoveTo = isMove && (unit?.newLines.isNotEmpty ?? false);
    final transportSignal = math
        .max(
          widget.hunkTransportPull,
          widget.hunkTransportedSupport,
        )
        .clamp(0.0, 1.0);
    final residualSignal = math
        .max(
          widget.hunkInnovationResidual,
          widget.hunkWitnessResidual,
        )
        .clamp(0.0, 1.0);
    final semanticSignal = math
        .max(
          widget.hunkImportance.clamp(0.0, 1.0),
          math.max(transportSignal, residualSignal),
        )
        .clamp(0.0, 1.0);
    final Color semanticColor = widget.hunkWitnessResidual >=
            math.max(widget.hunkInnovationResidual, transportSignal)
        ? t.stateConflicted
        : widget.hunkInnovationResidual >= transportSignal
            ? t.accentBright
            : t.chromeAccent;

    // Tint strength: staged lines get a slightly stronger wash so their
    // membership is unmistakable without dimming text contrast.
    final double tintAlpha = l.isStaged ? 0.18 : 0.10;

    Color? lineBg;
    Color textColor;
    Color sigilColor = t.textMuted;

    switch (l.kind) {
      case LineKind.added:
        lineBg = t.stateAdded.withValues(alpha: tintAlpha);
        textColor = t.stateAdded;
        sigilColor = t.stateAdded;
        break;
      case LineKind.deleted:
        lineBg = t.stateDeleted.withValues(alpha: tintAlpha);
        textColor = t.stateDeleted;
        sigilColor = t.stateDeleted;
        break;
      case LineKind.hunk:
        final importance = widget.hunkImportance.clamp(0.0, 1.0);
        final semanticMix =
            math.max(importance, 0.35 * semanticSignal).clamp(0.0, 1.0);
        lineBg = Color.lerp(
          t.chromeAccent.withValues(alpha: 0.04),
          semanticColor.withValues(alpha: 0.08 + 0.08 * semanticSignal),
          semanticMix,
        );
        textColor = Color.lerp(
              t.accentBright.withValues(alpha: 0.85),
              semanticColor,
              (0.20 + 0.25 * semanticSignal).clamp(0.0, 1.0),
            ) ??
            t.accentBright;
        break;
      case LineKind.meta:
        lineBg = isFoldMarker
            ? t.surface0.withValues(alpha: 0.08)
            : t.surface0.withValues(alpha: 0.18);
        textColor = isFoldMarker
            ? t.textFaint.withValues(alpha: 0.8)
            : t.textMuted.withValues(alpha: 0.72);
        break;
      case LineKind.context:
        switch (widget.contextBand) {
          case DiffContextBand.near:
            lineBg = t.surface0.withValues(alpha: 0.05);
            textColor = t.textNormal.withValues(alpha: 0.82);
            break;
          case DiffContextBand.far:
            lineBg = t.surface0.withValues(alpha: 0.025);
            textColor = t.textMuted.withValues(alpha: 0.68);
            break;
          case DiffContextBand.changed:
          case null:
            lineBg = null;
            textColor = t.textNormal;
            break;
        }
        break;
    }

    // Pair overrides — tint blends the two states, text settles on the add
    // color so the final reading of the row is the post-state.
    if (isPair) {
      lineBg = Color.lerp(
        t.stateDeleted.withValues(alpha: tintAlpha),
        t.stateAdded.withValues(alpha: tintAlpha),
        0.5,
      );
      textColor = t.stateAdded;
      sigilColor = t.accentBright;
    }

    // Move overrides — switch off the red/green semantic for the line BG and
    // pick up the theme's accent hue so the user reads "relocated" instead
    // of "lost/gained". Text color stays legible against the new tint. The
    // sigil color picks up the move accent so the ± glyph reads as a move
    // endpoint, not a plain +/−.
    if (isMove) {
      lineBg = t.hyperChromatic1.withValues(alpha: tintAlpha * 1.1);
      textColor = t.textNormal;
      sigilColor = t.hyperChromatic1;
    } else if (!isMeta && semanticSignal > 0) {
      sigilColor = Color.lerp(
            sigilColor,
            semanticColor,
            (0.12 + 0.28 * semanticSignal).clamp(0.0, 1.0),
          ) ??
          sigilColor;
      if (lineBg != null &&
          (isAdded ||
              isDeleted ||
              isHunk ||
              widget.contextBand == DiffContextBand.near)) {
        lineBg = Color.lerp(
          lineBg,
          semanticColor.withValues(alpha: 0.04 + 0.05 * semanticSignal),
          (0.10 + 0.22 * semanticSignal).clamp(0.0, 1.0),
        );
      }
    }

    // Build gutter text (old | new line numbers or hunk marker). Move rows
    // prepend a direction glyph (⤴ for from-side, ⤵ for to-side) so the
    // reader sees at a glance this line is relocated rather than gained/lost.
    String gutterText = '';
    if (isHunk) {
      gutterText = '···';
    } else if (isPair) {
      final a = l.lineNumOld != null ? '${l.lineNumOld}' : '';
      final b = addPart!.lineNumNew != null ? '${addPart.lineNumNew}' : '';
      gutterText = '$a→$b';
    } else if (isMoveFrom) {
      final n = l.lineNumOld != null ? '${l.lineNumOld}' : '';
      gutterText = '⤴$n';
    } else if (isMoveTo) {
      final n = l.lineNumNew != null ? '${l.lineNumNew}' : '';
      gutterText = '⤵$n';
    } else if (isAdded) {
      gutterText = l.lineNumNew != null ? '${l.lineNumNew}' : '';
    } else if (isDeleted) {
      gutterText = l.lineNumOld != null ? '${l.lineNumOld}' : '';
    } else if (l.kind == LineKind.context) {
      gutterText = l.lineNumNew != null ? '${l.lineNumNew}' : '';
    }

    // Wear map: theme-chromatic gradient from hypercubePositive (newest)
    // toward hypercubeNegative (oldest). Alpha scales by intensity so ancient
    // lines fade out while recent ones glow in the theme's warm tone.
    Color? wearBg;
    if (widget.wearIntensity != null && !isMeta && !isHunk) {
      wearBg = Color.lerp(
        t.hypercubePositive.withValues(alpha: 0.32),
        t.hypercubeNegative.withValues(alpha: 0.08),
        widget.wearIntensity!,
      );
    }

    final Color gutterBg = widget.hovered
        ? t.accentBright.withValues(alpha: 0.06)
        : isMeta
            ? Colors.transparent
            : (wearBg ??
                (lineBg?.withValues(alpha: 0.6) ??
                    t.surface1.withValues(alpha: 0.5)));

    final gutterCell = Container(
      width: isMeta && !isFoldMarker ? 40 : 56,
      padding: const EdgeInsets.only(right: 8),
      alignment: Alignment.centerRight,
      color: gutterBg,
      child: Text(
        gutterText,
        style: TextStyle(
          color: widget.hovered
              ? (widget.blameEntry != null
                  ? t.hyperChromatic1.withValues(alpha: 0.9)
                  : t.textMuted)
              : t.textMuted.withValues(alpha: 0.5),
          fontSize: 10,
          fontFamily: 'JetBrainsMono',
        ),
      ),
    );
    final gutterContent = widget.onGutterEnter == null && !widget.hovered
        ? gutterCell
        : MouseRegion(
            onEnter: widget.onGutterEnter != null
                ? (_) => widget.onGutterEnter!()
                : null,
            onExit: (_) => widget.onGutterExit(),
            cursor: widget.onGutterEnter != null
                ? SystemMouseCursors.cell
                : MouseCursor.defer,
            child: gutterCell,
          );

    // The leading `+`/`-` sigil is redundant with the stage sigil column
    // and the line-bg tint, so it's stripped at render only. `l.text`
    // keeps the raw form for the patch engine / staging key. Uses the
    // shared [stripDiffLineSign] helper so renderer and unit-detection
    // layers cannot drift on what "pure content" means.
    final String displayText =
        (isAdded || isDeleted) ? stripDiffLineSign(l.text) : l.text;
    final String? pairFromText = isPair ? stripDiffLineSign(l.text) : null;
    final String? pairToText = isPair ? stripDiffLineSign(addPart!.text) : null;

    final useAnimatedText = widget.useAnimatedTextMode &&
        widget.searchTerm.isEmpty &&
        displayText.length <= 160 &&
        (isAdded || isDeleted || isHunk);
    final Widget textChild;
    if (isPair) {
      // Melting-glass pair: the row boots showing the old text in the delete
      // color, then morphs into the new text in the add color. This is a
      // LINEAGE animation — plays ONCE per unit id in the session (gated
      // by firstAppearance), never on scroll-recycle. Also suppressed under
      // reduce-motion / scroll stress via motionPolicy. When any gate is
      // open, seedFrom=null renders the post-state directly.
      final allowMelt = widget.firstAppearance &&
          widget.motionPolicy.allow(MotionIntent.transition);
      textChild = _DiffMeltText(
        text: pairToText!.isEmpty ? ' ' : pairToText,
        color: t.stateAdded,
        seedFrom:
            allowMelt ? (pairFromText!.isEmpty ? ' ' : pairFromText) : null,
        seedFromColor: allowMelt ? t.stateDeleted : null,
      );
    } else if (useAnimatedText) {
      textChild = _DiffMeltText(
        text: displayText,
        color: textColor,
      );
    } else {
      textChild = _buildPlainDiffText(
        displayText.isEmpty ? ' ' : displayText,
        textColor,
        t,
        widget.searchTerm,
        semanticTint: semanticColor,
        semanticSignal: semanticSignal,
        fontSize: isMeta ? 11 : 12,
        height: isMeta ? 1.3 : 1.5,
      );
    }

    // The sigil cell owns BOTH tap and drag — the interactive zone is the
    // sigil itself, not the wider margin. Clicking the line-number cell or
    // the line-state ribbon does nothing, by design.
    final bool sigilInteractive =
        widget.stagingEnabled && isStageable && widget.onSigilTap != null;
    final Widget rawSigil = widget.stagingEnabled && isStageable
        ? _StageSigil(
            tokens: t,
            kind: l.kind,
            staged: l.isStaged,
            hovered: _lineHover,
            color: sigilColor,
            onPaintStart: () => widget.onPaintStart?.call(),
            onPaintMove: (g) => widget.onPaintMove?.call(g),
            onPaintEnd: () => widget.onPaintEnd?.call(),
          )
        : const SizedBox.shrink();
    final Widget stageCell = widget.stagingEnabled
        ? SizedBox(
            width: widget.stageCellWidth,
            child: sigilInteractive
                ? MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _lineHover = true),
                    onExit: (_) => setState(() => _lineHover = false),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (_) {
                        final isShift = HardwareKeyboard.instance
                                .isLogicalKeyPressed(
                                    LogicalKeyboardKey.shiftLeft) ||
                            HardwareKeyboard.instance.isLogicalKeyPressed(
                                LogicalKeyboardKey.shiftRight);
                        final isAlt = HardwareKeyboard.instance
                                .isLogicalKeyPressed(
                                    LogicalKeyboardKey.altLeft) ||
                            HardwareKeyboard.instance.isLogicalKeyPressed(
                                LogicalKeyboardKey.altRight);
                        widget.onSigilTap!(isShift, isAlt);
                      },
                      child: rawSigil,
                    ),
                  )
                : rawSigil,
          )
        : const SizedBox.shrink();

    // Line content — always a plain, static container. The earlier
    // temperature-reveal sweep (L→R for add, R→L for delete) was removed:
    // ListView recycling re-mounted rows whenever they scrolled back into
    // view, so the sweep fired on every recycle and read as strobing
    // "lighting" during scroll. Scroll should be static. The pair-melt
    // transition is preserved as the only lineage animation and is gated
    // by firstAppearance + MotionPolicy so it also never replays on recycle.
    final showSemanticBorder = semanticSignal > 0 &&
        (isHunk ||
            isAdded ||
            isDeleted ||
            widget.contextBand == DiffContextBand.near);
    final Border? semanticBorder = showSemanticBorder
        ? Border(
            left: BorderSide(
              color: semanticColor.withValues(
                alpha: 0.14 + 0.46 * semanticSignal.clamp(0.0, 1.0),
              ),
              width: isHunk ? 2 : 1.5,
            ),
          )
        : widget.relatedRhyme
            ? Border(
                left: BorderSide(
                  color: t.accentBright.withValues(alpha: 0.32),
                  width: 1.5,
                ),
                right: BorderSide(
                  color: t.accentBright.withValues(alpha: 0.10),
                  width: 1,
                ),
              )
            : null;
    if (widget.relatedRhyme && !showSemanticBorder) {
      lineBg = Color.alphaBlend(
        t.accentBright.withValues(alpha: 0.05),
        lineBg ?? Colors.transparent,
      );
    }
    Widget lineContent = Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: lineBg,
          border: semanticBorder,
        ),
        padding: EdgeInsets.symmetric(horizontal: isMeta ? 12 : 8),
        alignment: Alignment.centerLeft,
        child: textChild,
      ),
    );

    // Left ribbon: a solid stripe at the very edge marking staged lines.
    // Width sourced from the shared [_kRibbonWidth] so overlays that reserve
    // pointer-transparent space on top of this column stay in lockstep.
    final bool showStageChrome = widget.stagingEnabled;
    final Color ribbonColor = l.isStaged
        ? (isAdded ? t.stateAdded : t.stateDeleted)
        : Colors.transparent;
    final Widget ribbon = showStageChrome
        ? (widget.keyboardFocused
            ? Container(
                width: _kRibbonWidth,
                decoration: BoxDecoration(
                  color: t.accentBright,
                  boxShadow: [
                    BoxShadow(
                      color: t.accentBright.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              )
            : Container(width: _kRibbonWidth, color: ribbonColor))
        : const SizedBox.shrink();

    // Left margin: ribbon + sigil + line number. Layout only — taps are
    // owned by the sigil cell above so the line-number rectangle isn't a
    // hidden click target.
    final leftZone = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 18, child: ribbon),
        stageCell,
        gutterContent,
      ],
    );

    final baseRow = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [leftZone, lineContent],
    );

    // Double-click on hunk header toggles the hunk.
    final Widget interactiveRowBase = isHunk && widget.onHunkDoubleTap != null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.onHunkDoubleTap,
            child: baseRow,
          )
        : baseRow;

    // Row-wide hover — blame load used to fire only when the mouse hit the
    // narrow line-number gutter, so readers hovering actual code never saw
    // anything. Pushing the trigger to the whole row makes blame ambient.
    // The inner gutter MouseRegion still fires (no-op on duplicate enter).
    final Widget interactiveRow = MouseRegion(
      onEnter:
          widget.onGutterEnter != null ? (_) => widget.onGutterEnter!() : null,
      onExit: (_) => widget.onGutterExit(),
      child: interactiveRowBase,
    );

    // Blame annotation overlay — shown inline left of gutter on hover.
    // Reengineered: replaces the deterministic-rainbow author hue (decoration)
    // with a metabolism bar derived from per-file wear intensity (signal).
    // The strip now answers "when, in this file's own rhythm" — not just
    // "when on the calendar".
    // Temporal-mark pulse — briefly washes an accent colour over the row when
    // the shell has just restored to this unit. One-shot fade. Applied to
    // whichever branch (blame or no-blame) we return, via _wrapWithPulse.
    if (widget.blameEntry == null) return _wrapWithPulse(interactiveRow, t);

    final b = widget.blameEntry!;
    final initial =
        b.authorName.isNotEmpty ? b.authorName[0].toUpperCase() : '?';
    final timeStr = _formatBlameTime(b.authoredAt);

    // wearIntensity: 0 = newest in file, 1 = oldest in file. Bucketed into
    // hot / warm / settled so the bar reads at a glance without forcing the
    // eye to interpolate fine alpha differences.
    final wear = widget.wearIntensity;
    final Color metaColor;
    if (wear == null) {
      metaColor = t.textFaint.withValues(alpha: 0.4);
    } else if (wear < 0.34) {
      metaColor = t.accentBright;
    } else if (wear < 0.67) {
      metaColor = t.textNormal;
    } else {
      metaColor = t.textFaint;
    }

    return _wrapWithPulse(
        Stack(clipBehavior: Clip.none, children: [
          interactiveRow,
          // (Parallax ghost plane removed — a 44pt letter clipped to an 18px
          // row rendered letters like `W` as three stroke-fragments, reading as
          // a vertical-line artifact instead of an identity. The blame chip
          // below carries the author + hash + time cleanly; no need for a
          // second plane when there isn't vertical room for it to breathe.)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedSlide(
                // Suppress the chip while the cursor is on the stage sigil —
                // that's a distinct interactive zone (click = stage, drag =
                // paint) and a chip floating over it reads as noise. Slides
                // back in the moment the cursor moves off the sigil onto
                // code text.
                offset: (widget.hovered && !_lineHover)
                    ? Offset.zero
                    : const Offset(-0.06, 0),
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: (widget.hovered && !_lineHover) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeOutCubic,
                  child: IntrinsicWidth(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 96),
                      // Tab-cut-from-the-gutter silhouette: hairline border on
                      // top/right/bottom only, no left border — the chip shares
                      // its left edge with the gutter it slid out of. Contrast
                      // is structural (defined silhouette + theme-calibrated
                      // hairline), not luminance- or glow-based.
                      decoration: BoxDecoration(
                        color: t.surface2,
                        border: Border(
                          top: BorderSide(color: t.chromeBorder, width: 1),
                          right: BorderSide(color: t.chromeBorder, width: 1),
                          bottom: BorderSide(color: t.chromeBorder, width: 1),
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        // Metabolism stripe IS the chip's leading edge — a
                        // semantic seam between gutter and chip, not a
                        // floating dot inside it.
                        Container(width: 2, color: metaColor),
                        const SizedBox(width: 8),
                        Text(initial,
                            style: TextStyle(
                                color: t.textNormal,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${b.shortHash}  $timeStr',
                            style: TextStyle(
                              color: t.hyperChromatic1,
                              fontSize: 9,
                              fontFamily: 'JetBrainsMono',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
        t);
  }

  /// One-shot accent-colour wash on a row, signalling "the shell just
  /// scrolled back to where you left off." The overlay is only added when
  /// [DiffLineView.pulseActive] is true and IgnorePointer-wraps itself so
  /// it never intercepts clicks. TweenAnimationBuilder fades alpha from its
  /// begin value down to 0 on mount — since the widget key (stagingKey) is
  /// stable, the animation plays once per restore, not on every rebuild.
  /// The pulse is MotionIntent.attention: the whole point is to break the
  /// reader's visual scan, so it plays even under reduce-motion — but its
  /// duration is scaled so the signal reads as feedback, not ornament.
  Widget _wrapWithPulse(Widget child, AppTokens t) {
    if (!widget.pulseActive) return child;
    final duration =
        widget.motionPolicy.scale(const Duration(milliseconds: 900));
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.32, end: 0.0),
              duration: duration,
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Container(
                color: t.accentBright.withValues(alpha: v),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

//
// The only staging affordance: a click target on the left of every +/- line.
// Shows a filled glyph when staged, outlined when not. Tap = toggle. Vertical
// drag = paint across multiple lines. Shift+tap = extend range from the last
// toggled line; Alt+tap = disable auto-pairing of replacement -/+ lines.

class _StageSigil extends StatelessWidget {
  final AppTokens tokens;
  final LineKind kind;
  final bool staged;
  final bool hovered;
  final Color color;
  final VoidCallback onPaintStart;
  final void Function(Offset globalPosition) onPaintMove;
  final VoidCallback onPaintEnd;

  const _StageSigil({
    required this.tokens,
    required this.kind,
    required this.staged,
    required this.hovered,
    required this.color,
    required this.onPaintStart,
    required this.onPaintMove,
    required this.onPaintEnd,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = kind == LineKind.added ? '+' : '−';
    final Color effective =
        hovered || staged ? color : color.withValues(alpha: 0.55);

    // Hover border — crisp 1px ring around the sigil glyph that says
    // "this is a button." Only when the left zone is hovered AND the line
    // isn't already staged (filled dot already carries its own weight).
    final Border? hoverBorder = (hovered && !staged)
        ? Border.all(color: color.withValues(alpha: 0.75), width: 1)
        : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => onPaintStart(),
      onVerticalDragUpdate: (d) => onPaintMove(d.globalPosition),
      onVerticalDragEnd: (_) => onPaintEnd(),
      onVerticalDragCancel: () => onPaintEnd(),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: staged ? color.withValues(alpha: 0.10) : Colors.transparent,
            border: hoverBorder,
            borderRadius: BorderRadius.circular(3),
          ),
          child: staged
              // Filled dot: unmistakable "this is in."
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: effective,
                  ),
                )
              : Text(
                  glyph,
                  style: TextStyle(
                    color: effective,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'JetBrainsMono',
                    height: 1.0,
                  ),
                ),
        ),
      ),
    );
  }
}

class _DiffMeltText extends StatefulWidget {
  final String text;
  final Color color;

  /// Optional seed: when non-null, the widget boots with `seedFrom` on screen
  /// and immediately animates to `text`. Used by replacement pairs so the
  /// delete→add transition plays once on first appearance.
  final String? seedFrom;
  final Color? seedFromColor;

  const _DiffMeltText({
    required this.text,
    required this.color,
    this.seedFrom,
    this.seedFromColor,
  });

  @override
  State<_DiffMeltText> createState() => _DiffMeltTextState();
}

class _DiffMeltTextState extends State<_DiffMeltText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late String _fromText;
  late String _toText;
  late Color _fromColor;
  late Color _toColor;

  String get _displayText => widget.text.isEmpty ? ' ' : widget.text;

  @override
  void initState() {
    super.initState();
    final seeded = widget.seedFrom != null;
    _fromText = seeded
        ? (widget.seedFrom!.isEmpty ? ' ' : widget.seedFrom!)
        : _displayText;
    _toText = _displayText;
    _fromColor = widget.seedFromColor ?? widget.color;
    _toColor = widget.color;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: seeded ? 0 : 1,
    );
    if (seeded) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _DiffMeltText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _displayText;
    if (nextText != _toText || widget.color != _toColor) {
      _fromText = _toText;
      _fromColor = _toColor;
      _toText = nextText;
      _toColor = widget.color;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _DiffMeltTextPainter(
                fromText: _fromText,
                toText: _toText,
                fromColor: _fromColor,
                toColor: _toColor,
                progress: _controller.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

Widget _buildPlainDiffText(
  String displayText,
  Color baseColor,
  AppTokens t,
  String searchTerm, {
  Color? semanticTint,
  double semanticSignal = 0.0,
  double fontSize = 12,
  double height = 1.5,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
}) {
  if (searchTerm.isNotEmpty) {
    return _buildSearchText(
      displayText,
      baseColor,
      t,
      searchTerm,
      semanticTint: semanticTint,
      semanticSignal: semanticSignal,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );
  }
  final semanticMix = semanticTint == null
      ? 0.0
      : (0.10 + 0.18 * semanticSignal).clamp(0.0, 0.24).toDouble();
  final effectiveBaseColor = semanticTint == null
      ? baseColor
      : (Color.lerp(baseColor, semanticTint, semanticMix) ?? baseColor);
  return Text(
    displayText,
    maxLines: 1,
    overflow: TextOverflow.clip,
    style: TextStyle(
      color: effectiveBaseColor,
      backgroundColor: semanticTint == null || semanticSignal < 0.14
          ? null
          : semanticTint.withValues(
              alpha: (0.015 + 0.035 * semanticSignal).clamp(0.0, 0.06)),
      fontSize: fontSize,
      fontFamily: 'JetBrainsMono',
      height: height,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    ),
  );
}

Widget _buildSearchText(
  String displayText,
  Color baseColor,
  AppTokens t,
  String searchTerm, {
  Color? semanticTint,
  double semanticSignal = 0.0,
  double fontSize = 12,
  double height = 1.5,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
}) {
  final semanticMix = semanticTint == null
      ? 0.0
      : (0.10 + 0.18 * semanticSignal).clamp(0.0, 0.24).toDouble();
  final effectiveBaseColor = semanticTint == null
      ? baseColor
      : (Color.lerp(baseColor, semanticTint, semanticMix) ?? baseColor);
  final effectiveBackground = semanticTint == null || semanticSignal < 0.14
      ? null
      : semanticTint.withValues(
          alpha: (0.015 + 0.035 * semanticSignal).clamp(0.0, 0.06));
  final lower = displayText.toLowerCase();
  final termLower = searchTerm.toLowerCase();
  final spans = <TextSpan>[];
  int start = 0;
  int idx = lower.indexOf(termLower);
  while (idx != -1) {
    if (idx > start) {
      spans.add(TextSpan(
          text: displayText.substring(start, idx),
          style: TextStyle(
            color: effectiveBaseColor,
            backgroundColor: effectiveBackground,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
          )));
    }
    spans.add(TextSpan(
      text: displayText.substring(idx, idx + termLower.length),
      style: TextStyle(
        color: semanticTint == null
            ? t.bg0
            : (Color.lerp(t.bg0, semanticTint, 0.12 * semanticSignal) ?? t.bg0),
        backgroundColor: (Color.lerp(
                  t.accentBright.withValues(alpha: 0.8),
                  semanticTint,
                  0.12 * semanticSignal,
                ) ??
                t.accentBright)
            .withValues(alpha: 0.8),
        fontWeight: fontWeight,
        fontStyle: fontStyle,
      ),
    ));
    start = idx + termLower.length;
    idx = lower.indexOf(termLower, start);
  }
  if (start < displayText.length) {
    spans.add(TextSpan(
        text: displayText.substring(start),
        style: TextStyle(
          color: effectiveBaseColor,
          backgroundColor: effectiveBackground,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
        )));
  }

  return RichText(
    text: TextSpan(
      style: TextStyle(
        fontSize: fontSize,
        fontFamily: 'JetBrainsMono',
        height: height,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
      ),
      children: spans,
    ),
    overflow: TextOverflow.clip,
    maxLines: 1,
  );
}

/// Shared TextPainter LRU across every [_DiffMeltTextPainter] instance.
///
/// Each diff row was paying for a fresh `TextPainter(...).layout()` on every
/// `paint(canvas)` — cheap in isolation, catastrophic at 60 Hz over a
/// virtualised list of thousands of lines. The layout is pure: given
/// identical (text, color, font) the resulting Paragraph is byte-identical,
/// so we cache the laid-out painter and just replay `.paint()`.
///
/// Cache is sized for multi-screenful scroll: viewport holds ~40–60 rows,
/// but rapid scroll can touch several hundred unique rows between cache
/// evictions. 384 entries ≈ 150 KB of retained state, inside L2.
///
/// Callers: use only from the REST path where (text, color) is stable
/// across frames. Animation paths with alpha-modulated colors change the
/// key every frame and would churn the LRU with zero hit rate — they
/// allocate fresh `TextPainter`s instead (see `_paintRun`).
final LruCache<int, TextPainter> _diffTextPainterCache =
    LruCache<int, TextPainter>(maxSize: 384);

TextPainter _cachedDiffLineTextPainter({
  required String text,
  required TextStyle style,
}) {
  final color = style.color;
  final key = Object.hash(
    text,
    // TextStyle itself isn't a stable hash source (color, fontSize, etc.
    // are captured explicitly).
    color == null ? 0 : color.toARGB32(),
    style.fontSize,
    style.fontFamily,
    style.height,
    style.fontWeight?.value,
  );
  final cached = _diffTextPainterCache.get(key);
  if (cached != null) return cached;
  final built = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  _diffTextPainterCache.put(key, built);
  return built;
}

class _DiffMeltTextPainter extends CustomPainter {
  static const _fontSize = 12.0;
  static const _fontFamily = 'JetBrainsMono';
  static const _lineHeight = 1.5;
  static const _maxMeltGlyphs = 180;
  static double? _cachedCharWidth;

  final String fromText;
  final String toText;
  final Color fromColor;
  final Color toColor;
  final double progress;

  const _DiffMeltTextPainter({
    required this.fromText,
    required this.toText,
    required this.fromColor,
    required this.toColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final textHeight = _fontSize * _lineHeight;
    final baselineY = (size.height - textHeight) / 2;
    final charWidth = _measureCharWidth();

    if (progress >= 0.999) {
      // Rest path — stable (text, color) tuple, so the shared
      // TextPainter cache hits reliably. Animation paths below
      // receive alpha-modulated colors that change every frame and
      // would churn the cache with near-zero hit rate, so they use
      // the direct (uncached) helper.
      _paintRunCached(canvas, toText, toColor, Offset(0, baselineY));
      canvas.restore();
      return;
    }

    final t = progress.clamp(0.0, 1.0);
    final newArrived = _smoothStep(0.08, 0.62, t);
    final relatedRows = _rowAffinity(fromText, toText) >= 0.52;
    final newAlphaFloor = relatedRows ? 0.55 : 0.78;
    final newAlpha = newAlphaFloor +
        Curves.easeOutCubic.transform(newArrived) * (1 - newAlphaFloor);
    final maxByWidth = math.max(1, (size.width / charWidth).ceil() + 2);
    final meltLimit = math.min(
      math.min(math.max(fromText.length, toText.length), maxByWidth),
      _maxMeltGlyphs,
    );

    if (relatedRows && toText.trim().isNotEmpty) {
      _paintMeltTrails(
        canvas: canvas,
        text: fromText,
        otherText: toText,
        color: fromColor,
        baselineY: baselineY,
        charWidth: charWidth,
        limit: meltLimit,
        incoming: false,
        amount: t,
        opacityScale: 1,
      );
    }

    if (relatedRows) {
      _paintMeltTrails(
        canvas: canvas,
        text: toText,
        otherText: fromText,
        color: toColor,
        baselineY: baselineY,
        charWidth: charWidth,
        limit: meltLimit,
        incoming: true,
        amount: t,
        opacityScale: 1,
      );
    }
    _paintRun(
      canvas,
      toText,
      toColor.withValues(alpha: toColor.a * newAlpha),
      Offset(0, baselineY),
    );

    canvas.restore();
  }

  double _measureCharWidth() {
    final cached = _cachedCharWidth;
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: _style(Colors.white)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return _cachedCharWidth = painter.width;
  }

  void _paintMeltTrails({
    required Canvas canvas,
    required String text,
    required String otherText,
    required Color color,
    required double baselineY,
    required double charWidth,
    required int limit,
    required bool incoming,
    required double amount,
    required double opacityScale,
  }) {
    if (text.isEmpty) return;
    for (var i = 0; i < limit; i++) {
      if (i >= text.length) break;
      final char = text[i];
      if (char.trim().isEmpty) continue;

      final otherChar = i < otherText.length ? otherText[i] : '';
      final changed =
          char != otherChar || color != (incoming ? fromColor : toColor);
      if (!changed) continue;
      if (!incoming && otherChar.trim().isEmpty) continue;

      final seed = _unitHash(i, text.length, otherText.length);
      final delay = seed * 0.18;
      final phase = ((amount - delay) / (1 - delay)).clamp(0.0, 1.0);
      final pulse = math.sin(math.pi * phase).clamp(0.0, 1.0);
      if (pulse <= 0) continue;

      final x = (i * charWidth).roundToDouble();
      final depth = 1.2 + 3.2 * seed;
      final y = incoming
          ? baselineY + depth * (1 - phase)
          : baselineY + 0.7 + depth * phase;
      final scaleY = incoming ? 1.1 - 0.08 * phase : 1 + 0.22 * phase;
      final alpha = color.a * pulse * (incoming ? 0.14 : 0.18) * opacityScale;

      _paintRunTransformed(
        canvas,
        char,
        color.withValues(alpha: alpha),
        Offset(x, y),
        scaleY,
      );
    }
  }

  double _unitHash(int index, int a, int b) {
    final value =
        math.sin((index + 1) * 12.9898 + a * 78.233 + b * 37.719) * 43758.5453;
    return value - value.floorToDouble();
  }

  double _rowAffinity(String a, String b) {
    final aTrim = a.trim();
    final bTrim = b.trim();
    if (aTrim.isEmpty || bTrim.isEmpty) return 0;
    if (aTrim == bTrim) return 1;

    final limit = math.min(a.length, b.length);
    var comparable = 0;
    var matches = 0;
    for (var i = 0; i < limit; i++) {
      final ca = a[i];
      final cb = b[i];
      if (ca.trim().isEmpty && cb.trim().isEmpty) continue;
      comparable++;
      if (ca == cb) matches++;
    }
    if (comparable == 0) return 0;

    final lengthPenalty = math.min(aTrim.length, bTrim.length) /
        math.max(aTrim.length, bTrim.length);
    return (matches / comparable) * lengthPenalty;
  }

  double _smoothStep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  void _paintRunTransformed(
    Canvas canvas,
    String text,
    Color color,
    Offset offset,
    double scaleY,
  ) {
    if (text.isEmpty || color.a <= 0) return;
    canvas.save();
    canvas.translate(offset.dx, offset.dy + (_fontSize * 0.42 * (1 - scaleY)));
    canvas.scale(1, scaleY.clamp(0.2, 2.2));
    _paintRun(canvas, text, color, Offset.zero);
    canvas.restore();
  }

  /// Cached variant: only safe when (text, color) repeats frame over
  /// frame. Used exclusively by the rest path above.
  void _paintRunCached(Canvas canvas, String text, Color color, Offset offset) {
    if (text.isEmpty || color.a <= 0) return;
    final painter =
        _cachedDiffLineTextPainter(text: text, style: _style(color));
    painter.paint(canvas, offset);
  }

  /// Animation path: alpha-modulated color produces a unique cache key
  /// every frame. Allocating fresh keeps the shared cache free of churn
  /// so the rest path's hot entries aren't evicted.
  void _paintRun(Canvas canvas, String text, Color color, Offset offset) {
    if (text.isEmpty || color.a <= 0) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _style(color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  TextStyle _style(Color color) {
    return TextStyle(
      color: color,
      fontSize: _fontSize,
      fontFamily: _fontFamily,
      height: _lineHeight,
    );
  }

  @override
  bool shouldRepaint(covariant _DiffMeltTextPainter oldDelegate) {
    return oldDelegate.fromText != fromText ||
        oldDelegate.toText != toText ||
        oldDelegate.fromColor != fromColor ||
        oldDelegate.toColor != toColor ||
        oldDelegate.progress != progress;
  }
}

/// A horizontal node-style rail for the file's commit history.
/// Mirrors the visual language of `_MultiDiffProgressRail` in changes_page —
/// a baseline with evenly-spaced dots, a halo marker on the selected stop.
/// Index 0 is "now" (current working state), then each commit newest → oldest.
class _TrailStrip extends StatelessWidget {
  final AppTokens tokens;
  final List<FileHistoryEntry> history;
  final bool loading;
  final String? selectedHash;
  final ValueChanged<String> onSelectStop;
  final VoidCallback onSelectNow;

  const _TrailStrip({
    required this.tokens,
    required this.history,
    required this.loading,
    required this.selectedHash,
    required this.onSelectStop,
    required this.onSelectNow,
  });

  String _relativeDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().difference(date);
      if (diff.inDays > 365) return '${diff.inDays ~/ 365}y';
      if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo';
      if (diff.inDays > 0) return '${diff.inDays}d';
      if (diff.inHours > 0) return '${diff.inHours}h';
      return '${diff.inMinutes}m';
    } catch (_) {
      return '';
    }
  }

  int get _currentIndex {
    if (selectedHash == null) return 0; // "now"
    final idx = history.indexWhere((e) => e.commit.commitHash == selectedHash);
    return idx < 0 ? 0 : idx + 1;
  }

  String? _currentLabel() {
    if (loading) return 'loading trail...';
    if (history.isEmpty) return 'no history found';
    if (selectedHash == null) return 'now · working copy';
    final entry = history.firstWhere(
      (e) => e.commit.commitHash == selectedHash,
      orElse: () => history.first,
    );
    final c = entry.commit;
    final rel = _relativeDate(c.authoredAt);
    return '${c.shortHash} · ${c.authorName} · $rel · ${c.subject}';
  }

  void _selectByIndex(int index) {
    if (index == _currentIndex) return;
    if (index == 0) {
      onSelectNow();
    } else {
      final i = (index - 1).clamp(0, history.length - 1);
      onSelectStop(history[i].commit.commitHash);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final total = history.length + 1; // +1 for "now"

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      decoration: BoxDecoration(
        color: t.bg0.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currentLabel() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!loading && history.isNotEmpty) ...[
            const SizedBox(height: 4),
            _TrailRail(
              tokens: t,
              total: total,
              currentIndex: _currentIndex,
              onSelectIndex: _selectByIndex,
            ),
          ],
        ],
      ),
    );
  }
}

class _TrailRail extends StatelessWidget {
  final AppTokens tokens;
  final int total;
  final int currentIndex;
  final ValueChanged<int> onSelectIndex;

  const _TrailRail({
    required this.tokens,
    required this.total,
    required this.currentIndex,
    required this.onSelectIndex,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _selectFromOffset(d.localPosition.dx, width),
            onHorizontalDragStart: (d) =>
                _selectFromOffset(d.localPosition.dx, width),
            onHorizontalDragUpdate: (d) =>
                _selectFromOffset(d.localPosition.dx, width),
            child: SizedBox(
              width: width,
              height: 22,
              child: CustomPaint(
                size: Size(width, 22),
                painter: _TrailRailPainter(
                  tokens: tokens,
                  total: total,
                  currentIndex: currentIndex,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectFromOffset(double localDx, double width) {
    if (total <= 0) return;
    const horizontalInset = 6.0;
    final usable = (width - horizontalInset * 2).clamp(1.0, double.infinity);
    final ratio = ((localDx - horizontalInset) / usable).clamp(0.0, 1.0);
    final index = total == 1 ? 0 : (ratio * (total - 1)).round();
    if (index == currentIndex) return;
    onSelectIndex(index);
  }
}

class _TrailRailPainter extends CustomPainter {
  final AppTokens tokens;
  final int total;
  final int currentIndex;

  const _TrailRailPainter({
    required this.tokens,
    required this.total,
    required this.currentIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;

    const horizontalInset = 6.0;
    final left = horizontalInset;
    final right = size.width - horizontalInset;
    final centerY = size.height / 2;
    final usableWidth = right - left;
    final progress = total == 1 ? 0.0 : currentIndex / (total - 1);
    final markerX = left + usableWidth * progress.clamp(0.0, 1.0);

    final baseRail = Paint()
      ..color = tokens.chromeBorderStrong
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, centerY), Offset(right, centerY), baseRail);

    // Cap the visible dot count so huge histories don't clutter the rail.
    final sampleCount = total < 2
        ? 1
        : total > 44
            ? 44
            : total;

    for (var i = 0; i < sampleCount; i++) {
      final ratio = sampleCount == 1 ? 0.0 : i / (sampleCount - 1);
      final representedIndex =
          sampleCount == 1 ? currentIndex : (ratio * (total - 1)).round();
      final x = left + usableWidth * ratio;
      final isCurrent = representedIndex == currentIndex;
      // "now" (index 0) gets a slightly brighter base color to distinguish it.
      final isNow = representedIndex == 0;
      final radius = isCurrent ? 4.5 : (isNow ? 3.2 : 2.4);
      final fill = Paint()
        ..color = isCurrent
            ? tokens.accentBright
            : (isNow
                ? tokens.accentBright.withValues(alpha: 0.55)
                : tokens.textMuted.withValues(alpha: 0.24));
      canvas.drawCircle(Offset(x, centerY), radius, fill);
    }

    final halo = Paint()
      ..color = tokens.accentBright.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final ring = Paint()
      ..color = tokens.accentBright.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(markerX, centerY), 7.5, halo);
    canvas.drawCircle(Offset(markerX, centerY), 6.2, ring);
  }

  @override
  bool shouldRepaint(covariant _TrailRailPainter old) {
    return old.total != total ||
        old.currentIndex != currentIndex ||
        old.tokens != tokens;
  }
}

class _ToolbarBtn extends StatefulWidget {
  final String icon;
  final bool active;
  final AppTokens t;
  final VoidCallback onTap;

  /// Optional explicit icon tint that overrides the default
  /// active/inactive coloring. Passed through verbatim — used to
  /// match the diff status dot's accent when we want the icon to
  /// read as part of that visual line.
  final Color? iconColorOverride;
  const _ToolbarBtn({
    required this.icon,
    required this.active,
    required this.t,
    required this.onTap,
    this.iconColorOverride,
  });
  @override
  State<_ToolbarBtn> createState() => _ToolbarBtnState();
}

class _ToolbarBtnState extends State<_ToolbarBtn> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: widget.active
                ? t.itemActiveBg
                : (_hov ? t.itemHoverBg : t.itemHoverBg.withValues(alpha: 0)),
            borderRadius: BorderRadius.circular(4),
            border:
                widget.active ? Border.all(color: t.itemActiveBorder) : null,
          ),
          child: Center(
              child: AppIcon(
                  name: widget.icon,
                  size: 13,
                  color: widget.iconColorOverride ??
                      (widget.active ? t.accentBright : t.textMuted))),
        ),
      ),
    );
  }
}

// Compact filename display that lives in the diff toolbar next to the
// search icon. Takes over the "big bold filename" that used to sit in
// the _DiffFileHeader. Click toggles the paper trail; hovers underline.
// Hides itself by the call site's `if (!_searchVisible)` gate so the
// search input can expand across the toolbar's full width.

class _ToolbarFileNameChip extends StatefulWidget {
  final AppTokens tokens;
  final String filePath;
  final String? label;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool trailActive;

  const _ToolbarFileNameChip({
    required this.tokens,
    required this.filePath,
    this.label,
    this.tooltip,
    required this.onTap,
    required this.trailActive,
  });

  @override
  State<_ToolbarFileNameChip> createState() => _ToolbarFileNameChipState();
}

class _ToolbarFileNameChipState extends State<_ToolbarFileNameChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final directory = _diffDisplayDirectory(widget.filePath);
    final canTap = widget.onTap != null;
    final label = widget.label ?? _diffDisplayName(widget.filePath);
    final tooltip =
        widget.tooltip ?? (directory != null ? widget.filePath : null);

    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: canTap ? (_) => setState(() => _hovered = true) : null,
      onExit: canTap ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(
              child: Tooltip(
                message: tooltip ?? '',
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.trailActive
                        ? t.accentBright
                        : (_hovered ? t.accentBright : t.textStrong),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    decoration: _hovered ? TextDecoration.underline : null,
                    decorationColor: t.accentBright.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            if (widget.trailActive) ...[
              const SizedBox(width: 6),
              Text(
                '· trail',
                style: TextStyle(
                  color: t.accentBright.withValues(alpha: 0.6),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HunkDropdown extends StatelessWidget {
  final List<_HunkHeader> hunks;
  final AppTokens t;
  final ValueChanged<int> onJump;
  const _HunkDropdown(
      {required this.hunks, required this.t, required this.onJump});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Jump to change block. Git calls these hunks.',
      offset: const Offset(0, 28),
      color: t.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: t.chromeBorder.withValues(alpha: 0.3)),
      ),
      onSelected: onJump,
      itemBuilder: (_) => hunks
          .asMap()
          .entries
          .map((e) => PopupMenuItem<int>(
                value: e.key,
                height: 28,
                child: Text(
                  e.value.label,
                  style: TextStyle(
                      color: t.accentBright,
                      fontSize: 11,
                      fontFamily: 'JetBrainsMono'),
                ),
              ))
          .toList(),
      child: Container(
        child: AppInputShell(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          fillColor: t.itemHoverBg,
          borderColor: t.secondaryBtnBorder,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${hunks.length} change${hunks.length == 1 ? "" : "s"}',
                style: TextStyle(color: t.textMuted, fontSize: 10)),
            const SizedBox(width: 4),
            AppIcon(name: 'chevron-down', size: 10, color: t.textMuted),
          ]),
        ),
      ),
    );
  }
}

//
// While scrolled deep inside a hunk, the natural `@@ ... @@` header scrolls
// away. This overlay pins the current hunk's label at the top of the viewport
// until the next hunk's natural header takes its place. Click to jump to the
// top of the hunk. Rendered as a single-line strip styled like the real
// hunk row so the transition is seamless.

class _PinnedAuthorShare {
  final String name;
  final double share;

  const _PinnedAuthorShare({
    required this.name,
    required this.share,
  });
}

class _PinnedPastContext {
  final String tempoLabel;
  final String? lastTouchLabel;
  final List<_PinnedAuthorShare> nearbyAuthors;
  final List<double> lineHeatSamples;

  const _PinnedPastContext({
    required this.tempoLabel,
    required this.lastTouchLabel,
    required this.nearbyAuthors,
    required this.lineHeatSamples,
  });
}

/// Floating panel at the bottom of DiffShell showing logos-powered
/// context for the right-click-pinned line: K-space nearest files,
/// semantic well, simhash rhymes in this diff, blame, coupling
/// siblings. Dismissable; dismisses by clicking the same line again
/// or the close button.
class _PinnedContextPanel extends StatefulWidget {
  final AppTokens tokens;
  final DiffPinnedContextModel? context;
  final _PinnedPastContext? past;
  final bool loading;
  final ValueChanged<String>? onOpenRelatedPath;
  final VoidCallback onClose;
  final void Function(int displayIdx) onRhymeTap;

  const _PinnedContextPanel({
    required this.tokens,
    required this.context,
    required this.past,
    required this.loading,
    this.onOpenRelatedPath,
    required this.onClose,
    required this.onRhymeTap,
  });

  @override
  State<_PinnedContextPanel> createState() => _PinnedContextDossierState();
}

/// Small painter for the well tightness disc. Outer ring is always
/// drawn; inner fill is a disc whose radius scales with how close the
/// line is to its well centroid. Tight = full disc, distant = just
/// the ring.
class _WellDotPainter extends CustomPainter {
  final Color colour;
  final double fill;
  const _WellDotPainter({required this.colour, required this.fill});
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final centre = Offset(r, r);
    final ringPaint = Paint()
      ..color = colour.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(centre, r - 1, ringPaint);
    if (fill > 0) {
      final fillPaint = Paint()..color = colour.withValues(alpha: 0.85);
      canvas.drawCircle(centre, (r - 1.5) * fill, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WellDotPainter old) =>
      old.colour != colour || old.fill != fill;
}

class _PinnedContextDossierState extends State<_PinnedContextPanel> {
  int _page = 0;
  int? _lastPage;
  final FocusNode _focusNode = FocusNode(debugLabel: 'PinnedContextPanel');
  Timer? _copiedFeedbackTimer;
  bool _copiedLine = false;

  @override
  void didUpdateWidget(covariant _PinnedContextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.context, widget.context)) {
      _copiedFeedbackTimer?.cancel();
      _copiedLine = false;
      final opening = oldWidget.context == null && widget.context != null;
      if (opening) {
        _page = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _copiedFeedbackTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    final t = widget.tokens;
    final c = widget.context;
    final tone = c == null ? _PinnedPanelTone.stable : _toneFor(c, widget.past);
    final future =
        c == null ? const <(String, String)>[] : _futureDestinations(c);
    return Container(
      constraints: const BoxConstraints(maxHeight: 304),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(
          top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.4)),
        ),
      ),
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.context != null,
        onKeyEvent: (_, event) => _handleKeyEvent(event, c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (c != null) ...[
                        _toneBadge(t, tone),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: c != null
                            ? _pinnedLinePreview(t, c)
                            : widget.loading
                                ? _loadingRow(t)
                                : const SizedBox.shrink(),
                      ),
                      if (c != null) ...[
                        const SizedBox(width: 10),
                        _pageSwitch(t),
                      ],
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: widget.onClose,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child:
                              Icon(Icons.close, size: 14, color: t.textFaint),
                        ),
                      ),
                    ],
                  ),
                  if (c != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _summarySentence(c, widget.past),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textStrong.withValues(alpha: 0.92),
                        fontSize: 12.2,
                        height: 1.22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _quickActionRow(t, c, future),
                  ],
                ],
              ),
            ),
            if (c != null) Flexible(child: _body(t, c)),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, DiffPinnedContextModel? c) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyM) {
      _setPage(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyE ||
        key == LogicalKeyboardKey.keyS) {
      _setPage(1);
      return KeyEventResult.handled;
    }
    if (c != null &&
        key == LogicalKeyboardKey.keyC &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      _copyPinnedLine(c);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _copyPinnedLine(DiffPinnedContextModel c) async {
    await Clipboard.setData(ClipboardData(text: _copyablePinnedLineText(c)));
    if (!mounted) return;
    setState(() {
      _copiedLine = true;
    });
    _copiedFeedbackTimer?.cancel();
    _copiedFeedbackTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _copiedLine = false;
      });
    });
  }

  Widget _pinnedLinePreview(AppTokens t, DiffPinnedContextModel c) {
    final text = c.line.text.trim().isNotEmpty ? c.line.text.trim() : '...';
    final style = TextStyle(
      color: t.textFaint.withValues(alpha: 0.74),
      fontSize: 10.5,
      fontFamily: 'monospace',
      letterSpacing: 0.08,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final child = Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return child;
        }
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: maxWidth);
        if (!painter.didExceedMaxLines) {
          return child;
        }
        return Tooltip(message: text, child: child);
      },
    );
  }

  String _copyablePinnedLineText(DiffPinnedContextModel c) {
    switch (c.line.kind) {
      case LineKind.added:
      case LineKind.deleted:
        return stripDiffLineSign(c.line.text);
      default:
        return c.line.text;
    }
  }

  Widget _loadingRow(AppTokens t) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: t.textFaint.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'loading pinned context',
          style: TextStyle(
            color: t.textFaint,
            fontSize: 11,
            letterSpacing: 0.4,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _body(AppTokens t, DiffPinnedContextModel c) {
    final future = _futureDestinations(c);
    final accent = _toneColor(t, _toneFor(c, widget.past));
    return LayoutBuilder(
      builder: (context, constraints) {
        final Widget content = switch (_page) {
          0 => ManifoldPane(
              context: c,
              tokens: t,
              onOpenRelatedPath: widget.onOpenRelatedPath,
              onRhymeTap: widget.onRhymeTap,
            ),
          _ => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _overviewPage(t, c, accent, constraints.maxWidth),
                  const SizedBox(height: 12),
                  _evidencePage(t, c, future, accent, constraints.maxWidth),
                ],
              ),
            ),
        };
        return Align(
          alignment: Alignment.topLeft,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 170),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final lastPage = _lastPage ?? _page;
              final forward = _page >= lastPage;
              final offset = Tween<Offset>(
                begin: Offset(forward ? 0.03 : -0.03, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: offset,
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey('pinned-page-$_page'),
              child: content,
            ),
          ),
        );
      },
    );
  }

  void _setPage(int nextPage) {
    final clamped = nextPage.clamp(0, 1);
    if (clamped == _page) {
      return;
    }
    setState(() {
      _lastPage = _page;
      _page = clamped;
    });
  }

  Widget _pageSwitch(AppTokens t) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.surface0.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pageChip(t, page: 0, label: 'Manifold'),
          const SizedBox(width: 2),
          _pageChip(t, page: 1, label: 'Signals'),
        ],
      ),
    );
  }

  Widget _pageChip(
    AppTokens t, {
    required int page,
    required String label,
  }) {
    final active = _page == page;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _setPage(page),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? t.accentBright.withValues(alpha: 0.24)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? t.accentBright.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: t.accentBright.withValues(alpha: 0.12),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active
                  ? t.accentBright.withValues(alpha: 0.98)
                  : t.textFaint.withValues(alpha: 0.8),
              fontSize: 10.1,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _overviewPage(
    AppTokens t,
    DiffPinnedContextModel c,
    Color accent,
    double width,
  ) {
    final compact = width < 760;
    if (c.rhymePreviews.isEmpty) {
      return Column(
        key: const ValueKey('context-page-solo'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mapHeroPane(
            t,
            c,
            accent,
            compact: compact,
          ),
        ],
      );
    }
    return Column(
      key: const ValueKey('context-page-echoes'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _mapHeroPane(t, c, accent, compact: compact),
        const SizedBox(height: 8),
        _echoTimelinePane(
          t,
          accent,
          c.rhymePreviews,
          compact: compact,
          title: 'Echoes',
        ),
      ],
    );
  }

  Widget _evidencePage(
    AppTokens t,
    DiffPinnedContextModel c,
    List<(String, String)> future,
    Color accent,
    double width,
  ) {
    final stories = _presentStories(c);
    final dense = width < 760;
    final maxLinked =
        dense ? (stories.length >= 2 ? 2 : 3) : (stories.length >= 2 ? 3 : 4);
    final linked = future.take(maxLinked).toList();
    final remainingLinked = math.max(0, future.length - linked.length);
    final hasStories = stories.isNotEmpty;
    final hasLinked = linked.isNotEmpty;
    return Column(
      key: ValueKey('signals-page-${hasStories ? 1 : 0}-${hasLinked ? 1 : 0}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasStories) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 4),
            child: _microLabel(t, 'Technical Ledger'),
          ),
          ...stories.map(
            (s) => Padding(
              padding:
                  EdgeInsets.fromLTRB(14, dense ? 3 : 4, 10, dense ? 3 : 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: dense ? 74 : 80,
                    child: Text(
                      s.$1.toUpperCase(),
                      style: TextStyle(
                        color: accent.withValues(alpha: 0.7),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textMuted, fontSize: 10.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (!hasLinked)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
            child: Text(
              'No secondary cues detected.',
              style: TextStyle(color: t.textFaint, fontSize: 10.5),
            ),
          ),
        if (hasLinked) ...[
          if (hasStories) const SizedBox(height: 10),
          _moduleShell(
            t,
            accent: accent,
            padding:
                EdgeInsets.fromLTRB(14, dense ? 8 : 10, 10, dense ? 10 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _moduleTitleRow(
                  t,
                  'Linked Paths',
                  accent: accent,
                  badge: remainingLinked > 0 ? '+$remainingLinked more' : null,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final destination in linked)
                      _linkedPathChip(
                        t,
                        destination.$1,
                        destination.$2,
                        accent,
                        compact: dense,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _mapHeroPane(
    AppTokens t,
    DiffPinnedContextModel c,
    Color accent, {
    required bool compact,
  }) {
    final concept = _conceptLabel(c) ?? 'Local seam';
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CustomPaint(
                    painter: _WellDotPainter(
                      colour: accent,
                      fill: (1.0 - ((c.wellDistance ?? 1.0) / 1.4))
                          .clamp(0.0, 1.0)
                          .toDouble(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    concept.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textStrong.withValues(alpha: 0.9),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _signalMeterRow(t, c, accent, width: compact ? 122 : 140),
              ],
            ),
            SizedBox(height: compact ? 12 : 14),
            _historyRibbon(t, accent),
          ],
        ),
      ),
    );
  }

  Widget _historyRibbon(
    AppTokens t,
    Color accent,
  ) {
    final past = widget.past;
    final owner = (past?.nearbyAuthors.isNotEmpty ?? false)
        ? past!.nearbyAuthors.first.name
        : 'shared ownership';
    final secondary = past?.lastTouchLabel != null
        ? _compactLastTouch(past!.lastTouchLabel!)
        : owner;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 100,
          height: 24,
          child: CustomPaint(
            painter: _PinnedHistorySeismographPainter(
              samples: past?.lineHeatSamples ?? const [],
              color: accent,
              faint: t.textFaint,
              chrome: t.chromeBorder,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                past == null ? 'History warming up' : _tempoTagline(past),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                secondary.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textFaint.withValues(alpha: 0.74),
                  fontSize: 9.0,
                  fontFamily: 'monospace',
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _echoTimelinePane(
    AppTokens t,
    Color accent,
    List<DiffPinnedRhymePreview> echoes, {
    required bool compact,
    required String title,
  }) {
    final visibleEchoes = echoes.take(3).toList();
    return _moduleShell(
      t,
      accent: accent,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _moduleTitleRow(
            t,
            title,
            badge: echoes.isEmpty ? null : '${echoes.length} TOTAL',
            accent: accent,
            onBadgeTap: echoes.isEmpty
                ? null
                : () => widget.onRhymeTap(echoes.first.displayIndex),
          ),
          const SizedBox(height: 10),
          if (visibleEchoes.isEmpty)
            Text('No echoes in this diff.',
                style: TextStyle(color: t.textFaint, fontSize: 10.0))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < visibleEchoes.length; i++) ...[
                  Expanded(
                    child: _echoTimelineNode(
                      t,
                      visibleEchoes[i],
                      accent,
                      prominent: i == 0,
                    ),
                  ),
                  if (i != visibleEchoes.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _echoTimelineNode(
    AppTokens t,
    DiffPinnedRhymePreview preview,
    Color accent, {
    required bool prominent,
  }) {
    final title = preview.lineNumber == null
        ? _diffDisplayName(preview.filePath)
        : '${_diffDisplayName(preview.filePath)}:${preview.lineNumber}';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => widget.onRhymeTap(preview.displayIndex),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: t.surface0.withValues(alpha: prominent ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: accent.withValues(alpha: prominent ? 0.14 : 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textStrong.withValues(alpha: prominent ? 0.96 : 0.8),
                fontSize: 9.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              preview.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textMuted,
                fontSize: 9.0,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signalMeterRow(AppTokens t, DiffPinnedContextModel c, Color accent,
      {double? width}) {
    final history = _historyStrength(widget.past);
    final novelty = _noveltyStrength(c);
    final reach = _reachStrength(c);
    final row = Row(
      children: [
        _signalMeter(t, 'T', history, accent),
        const SizedBox(width: 8),
        _signalMeter(t, 'N', novelty, accent),
        const SizedBox(width: 8),
        _signalMeter(t, 'R', reach, accent),
      ],
    );
    return width == null ? row : SizedBox(width: width, child: row);
  }

  Widget _signalMeter(
    AppTokens t,
    String label,
    double value,
    Color accent,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.textFaint.withValues(alpha: 0.75),
              fontSize: 8.0,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: t.surface0.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.4 + 0.45 * value),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _historyStrength(_PinnedPastContext? past) {
    final label = past?.tempoLabel ?? '';
    switch (label) {
      case 'hot owner lane':
        return 0.95;
      case 'active seam':
        return 0.86;
      case 'stable owner lane':
        return 0.54;
      case 'shared long-lived seam':
        return 0.48;
      case 'shared lane':
        return 0.38;
      default:
        return 0.18;
    }
  }

  double _noveltyStrength(DiffPinnedContextModel c) {
    if (c.witnesses
        .any((w) => _normalizedSignal(w).contains('high-frequency'))) {
      return 0.92;
    }
    if (c.witnesses.any((w) => _normalizedSignal(w).contains('residual'))) {
      return 0.78;
    }
    if (c.integrityReasons.any((r) => _normalizedSignal(r).contains('novel'))) {
      return 0.72;
    }
    return c.witnesses.isEmpty ? 0.22 : 0.5;
  }

  double _reachStrength(DiffPinnedContextModel c) {
    // Spectral participation entropy on the anchor is the real reach
    // signal — already normalised to [0, 1] via log(k). When the
    // spectral basis is absent (tiny repos, pre-warm-up), fall back to
    // the count-based heuristic.
    final spec = c.anchorSpectral;
    if (spec != null) return spec.reach.clamp(0.0, 1.0).toDouble();
    final raw = c.transportEdges.length * 0.34 + c.relatedFiles.length * 0.12;
    return raw.clamp(0.0, 1.0).toDouble();
  }

  Widget _microLabel(AppTokens t, String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: t.textFaint.withValues(alpha: 0.85),
        fontSize: 9.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _moduleTitleRow(
    AppTokens t,
    String label, {
    String? badge,
    Color? accent,
    VoidCallback? onBadgeTap,
    String? badgeTooltip,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _microLabel(t, label)),
        if (badge != null && badge.trim().isNotEmpty)
          _moduleBadge(
            t,
            badge,
            accent: accent,
            onTap: onBadgeTap,
            tooltip: badgeTooltip,
          ),
      ],
    );
  }

  Widget _moduleBadge(
    AppTokens t,
    String text, {
    Color? accent,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final badgeColor = accent ?? t.textFaint;
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(
          alpha: onTap != null ? 0.14 : (accent == null ? 0.06 : 0.09),
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: badgeColor.withValues(alpha: onTap != null ? 0.2 : 0.12),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: badgeColor.withValues(alpha: onTap != null ? 0.94 : 0.82),
          fontSize: 9.2,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
    if (onTap == null) {
      return tooltip == null ? child : Tooltip(message: tooltip, child: child);
    }
    final wrapped = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: child,
      ),
    );
    return tooltip == null
        ? wrapped
        : Tooltip(message: tooltip, child: wrapped);
  }

  Widget _linkedPathChip(AppTokens t, String path, String reason, Color accent,
      {bool compact = false}) {
    final basename = _diffDisplayName(path);
    final child = Container(
      constraints: BoxConstraints(
        minWidth: compact ? 92 : 96,
        maxWidth: compact ? 164 : 180,
      ),
      padding: EdgeInsets.fromLTRB(8, compact ? 5 : 6, 8, compact ? 5 : 6),
      decoration: BoxDecoration(
        color: t.surface0.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            reason.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textFaint.withValues(alpha: 0.82),
              fontSize: compact ? 8.1 : 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            basename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textMuted,
              fontSize: compact ? 9.8 : 10.2,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (widget.onOpenRelatedPath == null) {
      return child;
    }
    return Tooltip(
      message: 'Open related file ${_diffDisplayName(path)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => widget.onOpenRelatedPath?.call(path),
          child: child,
        ),
      ),
    );
  }

  String _tempoTagline(_PinnedPastContext past) {
    switch (past.tempoLabel) {
      case 'hot owner lane':
        return 'Recent movement with one strong owner nearby.';
      case 'active seam':
        return 'Recent movement from multiple hands nearby.';
      case 'stable owner lane':
        return 'Long-lived lane with one dominant owner.';
      case 'shared long-lived seam':
        return 'Shared seam that has accumulated over time.';
      case 'shared lane':
        return 'Shared lane with no single dominant owner.';
      default:
        return 'History is still resolving around this line.';
    }
  }

  String _compactLastTouch(String label) {
    final parts = label.split('/').map((part) => part.trim()).toList();
    if (parts.length >= 2) {
      return '${parts[0]} / ${parts[1]}';
    }
    return label;
  }

  Widget _quickActionRow(
    AppTokens t,
    DiffPinnedContextModel c,
    List<(String, String)> future,
  ) {
    final nextPath = future.isEmpty ? null : future.first.$1;
    final firstEcho =
        c.rhymePreviews.isEmpty ? null : c.rhymePreviews.first.displayIndex;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (nextPath != null && widget.onOpenRelatedPath != null)
          _quickActionChip(
            t,
            icon: Icons.north_east,
            label: 'inspect ${_diffDisplayName(nextPath)}',
            onTap: () => widget.onOpenRelatedPath?.call(nextPath),
          ),
        if (firstEcho != null)
          _quickActionChip(
            t,
            icon: Icons.alt_route,
            label: 'jump echo',
            onTap: () => widget.onRhymeTap(firstEcho),
          ),
        _quickActionChip(
          t,
          icon: _copiedLine ? Icons.check : Icons.content_copy_outlined,
          label: _copiedLine ? 'copied' : 'copy line',
          onTap: () => _copyPinnedLine(c),
        ),
      ],
    );
  }

  Widget _quickActionChip(
    AppTokens t, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: t.surface0.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: t.textFaint.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 9.9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: child,
      ),
    );
  }

  Widget _toneBadge(AppTokens t, _PinnedPanelTone tone) {
    final color = _toneColor(t, tone);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 7, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.86),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _toneLabel(tone),
            style: TextStyle(
              color: color.withValues(alpha: 0.88),
              fontSize: 9.4,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleShell(
    AppTokens t, {
    required Widget child,
    Color? accent,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(14, 14, 10, 14),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: (accent ?? t.chromeBorder).withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: child,
    );
  }

  _PinnedPanelTone _toneFor(
    DiffPinnedContextModel c,
    _PinnedPastContext? past,
  ) {
    final pastLabel = past?.tempoLabel ?? '';
    if (c.integrityReasons.isNotEmpty) {
      final integrity = c.integrityReasons.first.toLowerCase();
      if (integrity.contains('unstable') ||
          integrity.contains('tension') ||
          integrity.contains('contested')) {
        return _PinnedPanelTone.contested;
      }
    }
    if (pastLabel.contains('hot') || pastLabel.contains('active')) {
      return _PinnedPanelTone.hot;
    }
    if (c.witnesses.any((w) => _normalizedSignal(w).contains('residual'))) {
      return _PinnedPanelTone.novel;
    }
    if (c.transportEdges.isNotEmpty || c.relatedFiles.length >= 3) {
      return _PinnedPanelTone.spreading;
    }
    return _PinnedPanelTone.stable;
  }

  Color _toneColor(AppTokens t, _PinnedPanelTone tone) {
    switch (tone) {
      case _PinnedPanelTone.hot:
        return const Color(0xFFE2A23B);
      case _PinnedPanelTone.novel:
        return t.accentBright;
      case _PinnedPanelTone.contested:
        return const Color(0xFFDD6B6B);
      case _PinnedPanelTone.spreading:
        return const Color(0xFF72C29A);
      case _PinnedPanelTone.stable:
        return t.textMuted;
    }
  }

  String _toneLabel(_PinnedPanelTone tone) {
    switch (tone) {
      case _PinnedPanelTone.hot:
        return 'Hot';
      case _PinnedPanelTone.novel:
        return 'Novel';
      case _PinnedPanelTone.contested:
        return 'Contested';
      case _PinnedPanelTone.spreading:
        return 'Spreading';
      case _PinnedPanelTone.stable:
        return 'Stable';
    }
  }

  String _summarySentence(
    DiffPinnedContextModel c,
    _PinnedPastContext? past,
  ) {
    final concept = _conceptLabel(c);
    final owner = past != null && past.nearbyAuthors.isNotEmpty
        ? past.nearbyAuthors.first.name
        : null;
    final echoes = c.rhymePreviews.length;
    final future = _futureDestinations(c);
    final nextPath =
        future.isNotEmpty ? _diffDisplayName(future.first.$1) : null;
    final nextReason = future.isNotEmpty ? future.first.$2 : null;
    final fragments = <String>[];
    if (concept != null) {
      fragments.add('Lives in $concept');
    } else {
      fragments.add('Sits in a local seam');
    }
    if (owner != null) {
      fragments.add('worked mostly by $owner nearby');
    }
    if (echoes > 0) {
      fragments.add(
          'echoes in $echoes ${echoes == 1 ? 'other spot' : 'other spots'}');
    }
    if (nextPath != null) {
      final detail = nextReason == null ? '' : ' (${nextReason.toLowerCase()})';
      fragments.add('inspect $nextPath next$detail');
    }
    return '${fragments.join(', ')}.';
  }

  String? _conceptLabel(DiffPinnedContextModel c) {
    if (c.wellName != null && c.wellName!.trim().isNotEmpty) {
      final tightness = _wellTightnessLabel(c.wellDistance);
      final concept = _friendlySignalLabel(c.wellName!);
      return tightness == null ? concept : '$concept ($tightness)';
    }
    if (c.dominantAxis != null && c.dominantAxis!.trim().isNotEmpty) {
      return _axisStory(c.dominantAxis!);
    }
    return null;
  }

  String? _wellTightnessLabel(double? distance) {
    if (distance == null) return null;
    if (distance <= 0.35) return 'tight fit';
    if (distance <= 0.7) return 'close fit';
    return 'loose fit';
  }

  List<(String, String)> _presentStories(DiffPinnedContextModel c) {
    final stories = <(String, String)>[];
    if (c.witnesses.isNotEmpty) {
      final translated = _translateWitness(c.witnesses.first);
      if (translated.isNotEmpty) {
        stories.add(('Why this matters', translated));
      }
    }
    if (c.integrityReasons.isNotEmpty) {
      stories
          .add(('Confidence', _translateIntegrity(c.integrityReasons.first)));
    }
    if (c.witnesses.length > 1) {
      final translated = _translateWitness(c.witnesses[1]);
      if (translated.isNotEmpty) {
        stories.add(('Secondary signal', translated));
      }
    }
    if (stories.isEmpty && c.relatedFiles.isNotEmpty) {
      stories.add((
        'Neighbourhood',
        'This line sits close to ${_diffDisplayName(c.relatedFiles.first.path)} in the current codebase field.',
      ));
    }
    return stories.take(3).toList();
  }

  List<(String, String)> _futureDestinations(DiffPinnedContextModel c) {
    final currentPath = c.line.filePath ?? widget.context?.line.filePath ?? '';
    final destinations = <(String, String)>[];
    final seen = <String>{};
    for (final edge in c.transportEdges) {
      final candidate =
          edge.targetPath == currentPath ? edge.sourcePath : edge.targetPath;
      if (candidate.isEmpty ||
          candidate == currentPath ||
          !seen.add(candidate)) {
        continue;
      }
      final lane = edge.laneLabel?.trim();
      final reason = lane == null || lane.isEmpty
          ? 'Propagation lane'
          : 'Propagation lane: ${_friendlySignalLabel(lane)}';
      destinations.add((candidate, reason));
    }
    for (final related in c.relatedFiles) {
      if (!seen.add(related.path)) continue;
      destinations.add((related.path, _relatedReason(related, currentPath)));
    }
    return destinations;
  }

  String _translateWitness(String raw) {
    final normalized = _normalizedSignal(raw);
    if (normalized.contains('multiscale') && normalized.contains('support')) {
      return 'Nearby support · ${_friendlySignalLabel(raw)}';
    }
    if (normalized.contains('high-frequency') &&
        normalized.contains('residual')) {
      return 'Localized move · ${_friendlySignalLabel(raw)}';
    }
    if (normalized.contains('residual')) {
      return 'Surprising move · ${_friendlySignalLabel(raw)}';
    }
    if (normalized.contains('support')) {
      return 'Nearby support · ${_friendlySignalLabel(raw)}';
    }
    return _friendlySignalLabel(raw);
  }

  String _translateIntegrity(String raw) {
    final normalized = _normalizedSignal(raw);
    if (normalized.contains('stable')) {
      return 'Stable structure';
    }
    if (normalized.contains('contested') || normalized.contains('tension')) {
      return 'Conflicting signals';
    }
    if (normalized.contains('novel')) {
      return 'Novel shape';
    }
    return _friendlySignalLabel(raw);
  }

  String _relatedReason(DiffPinnedRelatedFile related, String currentPath) {
    final String base;
    if (_looksLikeTestPair(currentPath, related.path)) {
      base = 'Test mirror';
    } else if (related.semantic && related.coupled) {
      base = 'Semantic + history sibling';
    } else if (related.coupled) {
      base = 'Recent co-change';
    } else if (related.semantic) {
      base = 'Semantic sibling';
    } else {
      base = 'Related structure';
    }
    // Append the gravitational strength — the Wentzell-Freidlin
    // effective action V(a, b, β) = -log K / β between anchor and this
    // file. Low V ⇒ strongly bound; high V ⇒ weakly coupled. Thresholds
    // are empirical but stable across repos because V is β-normalised.
    final grav = related.gravity;
    if (grav == null || !grav.isFinite) return base;
    final String tier;
    if (grav < 1.5) {
      tier = 'tightly bound';
    } else if (grav < 4.0) {
      tier = 'orbiting';
    } else {
      tier = 'weakly coupled';
    }
    return '$base · $tier';
  }

  bool _looksLikeTestPair(String a, String b) {
    final left = a.replaceAll('\\', '/').toLowerCase();
    final right = b.replaceAll('\\', '/').toLowerCase();
    final leftStem =
        left.replaceAll('_test.dart', '.dart').replaceAll('/test/', '/lib/');
    final rightStem =
        right.replaceAll('_test.dart', '.dart').replaceAll('/test/', '/lib/');
    return leftStem == rightStem ||
        (left.contains('/test/') &&
            right.contains('/lib/') &&
            leftStem == right) ||
        (right.contains('/test/') &&
            left.contains('/lib/') &&
            rightStem == left);
  }

  String _axisStory(String raw) {
    final normalized = _normalizedSignal(raw);
    if (normalized.contains('history')) {
      return 'history trail';
    }
    if (normalized.contains('test')) {
      return 'test mirror lane';
    }
    if (normalized.contains('topology') || normalized.contains('structure')) {
      return 'structural lane';
    }
    if (normalized.contains('semantic')) {
      return 'semantic neighbourhood';
    }
    return _friendlySignalLabel(raw);
  }

  String _friendlySignalLabel(String raw) {
    final prepared = raw
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return prepared.isEmpty
        ? raw
        : prepared[0].toUpperCase() + prepared.substring(1);
  }

  String _normalizedSignal(String raw) =>
      raw.toLowerCase().replaceAll('_', '-');
}

class _PinnedHistorySeismographPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final Color faint;
  final Color chrome;

  const _PinnedHistorySeismographPainter({
    required this.samples,
    required this.color,
    required this.faint,
    required this.chrome,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      // Draw a subtle skeleton state: 3 tiny faint bars
      for (var i = 0; i < 3; i++) {
        final h = 4.0 + (i == 1 ? 3.0 : 0.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(8.0 + i * 8.0, size.height - h - 6, 4, h),
            const Radius.circular(1),
          ),
          Paint()..color = faint.withValues(alpha: 0.12),
        );
      }
      return;
    }

    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.drawRRect(
      track,
      Paint()..color = chrome.withValues(alpha: 0.08),
    );

    final count = samples.length;
    final gap = count <= 12 ? 2.0 : 1.0;
    final barWidth =
        ((size.width - gap * (count - 1)) / count).clamp(1.0, 10.0).toDouble();
    final baseY = size.height - 8;
    final points = <Offset>[];

    for (var i = 0; i < count; i++) {
      final sample = samples[i].clamp(0.0, 1.0);
      final barHeight = 8 + sample * (size.height - 18);
      final x = i * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseY - barHeight, barWidth, barHeight),
        const Radius.circular(2),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = color.withValues(alpha: 0.16 + 0.62 * sample),
      );
      points.add(Offset(x + barWidth / 2, baseY - barHeight));
    }

    final centreIndex = count ~/ 2;
    final centreX = centreIndex * (barWidth + gap) + barWidth / 2;
    canvas.drawLine(
      Offset(centreX, 2),
      Offset(centreX, size.height - 2),
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..strokeWidth = 1,
    );

    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 0; i < points.length - 1; i++) {
        final current = points[i];
        final next = points[i + 1];
        final midX = (current.dx + next.dx) / 2;
        final midY = (current.dy + next.dy) / 2;
        path.quadraticBezierTo(current.dx, current.dy, midX, midY);
      }
      path.lineTo(points.last.dx, points.last.dy);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.4);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PinnedHistorySeismographPainter old) =>
      !listEquals(old.samples, samples) ||
      old.color != color ||
      old.faint != faint ||
      old.chrome != chrome;
}

enum _PinnedPanelTone { stable, hot, novel, contested, spreading }

/// Ghost-text inlay at the right edge of a hunk header row.
/// Always shows `+adds −dels · N/total`; when the scroll engram has
/// predicted a landing on this hunk, the text steps up in weight and
/// colour (driven by [approachStrength] ∈ [0,1]) so the reader sees
/// the upcoming hunk light up before the scroll settles.
class _HunkInlineHint extends StatelessWidget {
  final int additions;
  final int deletions;
  final int ordinal;
  final int total;
  final String? tag;
  final String? hint;
  final AppTokens tokens;
  final bool approaching;
  final double approachStrength;

  const _HunkInlineHint({
    required this.additions,
    required this.deletions,
    required this.ordinal,
    required this.total,
    this.tag,
    this.hint,
    required this.tokens,
    required this.approaching,
    required this.approachStrength,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final strength = approachStrength.clamp(0.0, 1.0);
    // Base state: faint muted text at the row's right edge. On
    // approach, the text colour shifts toward accentBright and the
    // weight increases; the "landing here" marker appears.
    final baseAlpha = approaching ? 0.65 + 0.3 * strength : 0.42;
    final baseColor = approaching
        ? Color.lerp(t.textFaint, t.accentBright, 0.4 + 0.4 * strength)!
            .withValues(alpha: baseAlpha)
        : t.textFaint.withValues(alpha: baseAlpha);
    final addColor = approaching
        ? Color.lerp(t.accentBright, Colors.greenAccent, 0.4)!
            .withValues(alpha: baseAlpha)
        : t.textFaint.withValues(alpha: baseAlpha * 0.9);
    final delColor = approaching
        ? Color.lerp(t.accentBright, Colors.redAccent, 0.4)!
            .withValues(alpha: baseAlpha)
        : t.textFaint.withValues(alpha: baseAlpha * 0.9);
    final textStyle = TextStyle(
      color: baseColor,
      fontSize: 10.5,
      fontFamily: 'monospace',
      fontWeight: approaching ? FontWeight.w600 : FontWeight.w400,
      letterSpacing: 0.2,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (approaching) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: t.accentBright.withValues(alpha: baseAlpha),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text('landing', style: textStyle),
          const SizedBox(width: 8),
        ],
        if (tag != null && tag!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.surface1.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: t.chromeBorder.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              hint ?? tag!,
              style: textStyle.copyWith(
                fontSize: 9.5,
                color: baseColor.withValues(alpha: baseAlpha * 0.9),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (additions > 0) ...[
          Text('+$additions', style: textStyle.copyWith(color: addColor)),
          const SizedBox(width: 4),
        ],
        if (deletions > 0) ...[
          Text('−$deletions', style: textStyle.copyWith(color: delColor)),
          const SizedBox(width: 4),
        ],
        Text('·  $ordinal/$total', style: textStyle),
      ],
    );
  }
}

class _StickyHunkHeader extends StatelessWidget {
  final AppTokens tokens;
  final List<_HunkHeader> hunks;

  /// Parallel to [hunks]: each entry is the display-row index (into the
  /// list the scroll controller actually views) of the corresponding
  /// hunk's header line. Required because `hunks[i].lineIndex` is an
  /// index into `_lines` — paired-add filtering collapses `_displayLines`
  /// so the two coordinate spaces diverge. A value of -1 means the
  /// hunk's header was filtered out (shouldn't occur for hunks) and is
  /// treated as "skip this hunk".
  final List<int> hunkDisplayRows;
  final ScrollController scrollCtrl;
  final double lineExtent;
  final ValueChanged<int> onJump;

  const _StickyHunkHeader({
    required this.tokens,
    required this.hunks,
    required this.hunkDisplayRows,
    required this.scrollCtrl,
    required this.lineExtent,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    // Hoist everything the scroll tick *can't* change. Previously these
    // allocations happened inside the `AnimatedBuilder.builder` closure
    // and so reran on every scroll pixel — the header fires dozens of
    // build passes per second during an active scroll. Only the
    // label-bearing right region actually varies with scroll position;
    // the decoration tokens, text style, and left sigil strip do not.
    const double sigilReserveWidth = _kLeftReserveWidth;
    final bg = BoxDecoration(
      color: tokens.chromeAccent.withValues(alpha: 0.14),
      border: Border(
        bottom: BorderSide(
          color: tokens.chromeBorder.withValues(alpha: 0.25),
        ),
      ),
    );
    final labelStyle = TextStyle(
      color: tokens.accentBright,
      fontSize: 11,
      fontFamily: 'JetBrainsMono',
      height: 1.3,
    );
    final leftStrip = IgnorePointer(
      child: Container(
        width: sigilReserveWidth,
        height: lineExtent,
        decoration: bg,
      ),
    );
    return AnimatedBuilder(
      animation: scrollCtrl,
      // Pass the invariant left strip through as `child:` so
      // `AnimatedBuilder` reuses the exact same widget instance across
      // every scroll tick instead of rebuilding it.
      child: leftStrip,
      builder: (context, leftChild) {
        if (!scrollCtrl.hasClients) return const SizedBox.shrink();
        if (hunkDisplayRows.length != hunks.length) {
          return const SizedBox.shrink();
        }
        final offset = scrollCtrl.offset;
        final topIdx = (offset / lineExtent).floor();

        // Find the hunk whose natural header has scrolled out of view:
        // the largest hunk display-row strictly less than topIdx. Skip
        // any hunk whose row is -1 (filtered, shouldn't happen but safe).
        int activeHunk = -1;
        int? activeRow;
        for (int i = 0; i < hunks.length; i++) {
          final row = hunkDisplayRows[i];
          if (row < 0) continue;
          if (row < topIdx) {
            activeHunk = i;
            activeRow = row;
          } else {
            break;
          }
        }
        if (activeHunk < 0 || activeRow == null) {
          return const SizedBox.shrink();
        }

        // Fade out during the brief window where the next hunk's natural
        // header is about to replace this one — keeps the swap clean.
        int? nextRow;
        for (int i = activeHunk + 1; i < hunks.length; i++) {
          if (hunkDisplayRows[i] >= 0) {
            nextRow = hunkDisplayRows[i];
            break;
          }
        }
        double opacity = 1.0;
        if (nextRow != null) {
          final pxToNext = (nextRow * lineExtent) - offset;
          if (pxToNext < lineExtent) {
            opacity = (pxToNext / lineExtent).clamp(0.0, 1.0);
          }
        }

        final label = hunks[activeHunk].label;
        return Opacity(
          opacity: opacity,
          child: SizedBox(
            height: lineExtent,
            child: Row(
              children: [
                // Left strip (hoisted via AnimatedBuilder child:). Pointer
                // pass-through so paint-drag + sigil taps reach the row
                // beneath the sticky overlay. Reserved width tracks
                // [_kLeftReserveWidth] through the hoisted widget.
                leftChild!,
                // Right region: click to jump. IgnorePointer during the
                // 1-line handoff fade so the sticky doesn't eat a tap that
                // belongs to the next hunk's natural header.
                Expanded(
                  child: IgnorePointer(
                    ignoring: opacity < 0.5,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onJump(activeHunk),
                        child: Container(
                          height: lineExtent,
                          decoration: bg,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
