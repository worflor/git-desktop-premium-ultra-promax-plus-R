import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../ui/animated_icons.dart';
import '../../ui/context_menu.dart';
import '../../ui/control_chrome.dart';
import '../../ui/design_primitives.dart';
import '../../ui/dream_hint.dart';
import '../../ui/form_controls.dart';
import '../../ui/interaction_feedback.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/resonance_text.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import '../../backend/ai.dart';
import '../../backend/engram_text_kspace.dart' show nearestKFilesForPath;
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../backend/engram_bootstrap.dart' show EngramRuntime;
import '../../backend/file_coupling.dart';
import '../../backend/logos_hunks.dart' as hunks;
import '../../backend/file_layout.dart';
import 'logos_diffusion_canvas.dart';
import '../../backend/stash_shape.dart';
import '../../backend/logos_git.dart';
import '../../backend/logos_git_integrity.dart' show CouplingConstants;
import '../../backend/logos_dream.dart';
import '../../backend/logos_field.dart';
import '../../backend/logos_refactor.dart';
import '../../backend/logos_spaghetti.dart';
import '../../backend/system_paths.dart' show revealInFileManager;
import '../../backend/undo_controller.dart';
import '../../ui/logos_glyph_strip.dart';
import '../../app/ai_activity_state.dart';
import '../../app/ai_settings_state.dart';
import '../../app/file_coupling_state.dart';
import '../../app/symbol_frequency_state.dart';
import '../../app/logos_git_state.dart';
import '../../app/preferences_state.dart';
import '../../app/window_activity.dart';
import '../../app/desk_drop_payload.dart';
import '../../app/desk_pr_state.dart';
import '../../app/repository_state.dart';
import '../../diagnostics/diagnostics_state.dart';
import '../branches/branches_page.dart' show showPatchPreviewDialog;
import '../diff/diff_document.dart';
import '../diff/diff_shell.dart';
import '../diff/diff_models.dart';
import 'file_constellation.dart';

String _guardrailLabelForStage(int stage) {
  switch (stage.clamp(0, 3)) {
    case 0:
      return 'Loose';
    case 1:
      return 'Balanced';
    case 2:
      return 'Strict';
    default:
      return 'Paranoid';
  }
}

enum _CommitRunMode { commitOnly, commitAndSync }

/// Result of a delayed commit flow. Carries either the success
/// message + committed data (+ optional post-commit sync error) or
/// the error string from the failing step.
class _CommitOutcome {
  final bool ok;
  final CommitData? committed;
  final String? successMessage;
  final String? error;
  final String? syncError;

  const _CommitOutcome._({
    required this.ok,
    this.committed,
    this.successMessage,
    this.error,
    this.syncError,
  });

  factory _CommitOutcome.ok(
          CommitData committed, String successMessage, String? syncError) =>
      _CommitOutcome._(
        ok: true,
        committed: committed,
        successMessage: successMessage,
        syncError: syncError,
      );

  factory _CommitOutcome.err(String error) =>
      _CommitOutcome._(ok: false, error: error);
}

/// Payload produced by one dream-compute pass for the commit composer:
/// the placeholder phrase + the diff's field-character classification.
/// Paired in a single record so one DreamHintController<_CommitDream>
/// drives both slots (placeholder text + chrome accent) with one
/// debounce + one cancellation id.
typedef _CommitDream = ({
  String? phrase,
  LogosFieldCharacter? character,
});

class _PrimaryCommitAction {
  final String label;
  final String detail;
  final bool syncAfterCommit;

  const _PrimaryCommitAction({
    required this.label,
    required this.detail,
    required this.syncAfterCommit,
  });
}

class ChangesPage extends StatefulWidget {
  const ChangesPage({super.key});
  @override
  State<ChangesPage> createState() => _ChangesPageState();
}

class _ChangesPageState extends State<ChangesPage> {
  final Stopwatch _mountedAt = Stopwatch()..start();
  final Set<String> _includedPaths = {};
  final _commitMsgCtrl = TextEditingController();
  final _commitMsgFocusNode = FocusNode();
  final List<String> _commitTags = [];
  List<String> _suggestedTags = const [];

  /// Engine-dreamed commit-composer hint. The controller owns the
  /// debounce, signature short-circuit, and in-flight cancellation;
  /// the payload here carries both the phrase and the diff's field
  /// character so one compute drives both the placeholder text and
  /// any accent chrome that renders alongside it.
  final DreamHintController<_CommitDream> _commitDream = DreamHintController();

  /// Compose the composer's placeholder hint from the dream payload.
  /// Silent when nothing's resolved; phrase alone when the character
  /// is trivial; phrase ·  character otherwise.
  String _composeHint() {
    final dream = _commitDream.value;
    final hint = dream?.phrase ?? 'commit message...';
    final char = dream?.character;
    if (char == null || char == LogosFieldCharacter.silent) return hint;
    return '$hint  ·  ${char.label}';
  }

  /// Lazy cache of spaghetti reports per engine revision. Context
  /// menus open frequently; `analyzeSpaghetti` is not cheap, so we
  /// memoise per [LogosGit.manifoldRevision].
  final Map<int, SpaghettiReport?> _spaghettiReportCache = {};

  /// Lazy cache of refactor proposals per engine revision.
  final Map<int, List<RefactorProposal>?> _refactorCache = {};

  /// Look up or compute the spaghetti report for an engine.
  SpaghettiReport? _reportForEngine(LogosGit engine) {
    return _spaghettiReportCache.putIfAbsent(
      engine.manifoldRevision,
      () => analyzeSpaghetti(engine),
    );
  }

  /// Look up or compute the refactor proposals for an engine.
  List<RefactorProposal>? _proposalsForEngine(LogosGit engine) {
    return _refactorCache.putIfAbsent(
      engine.manifoldRevision,
      () => proposeRefactors(engine),
    );
  }

  /// Bundle the file's engine-derived status for the glyph strip.
  /// Returns a silent status when the engine is null.
  LogosFileStatus _fileStatus(LogosGit? engine, String path) {
    if (engine == null) return const LogosFileStatus();
    final report = _reportForEngine(engine);
    final proposals = _proposalsForEngine(engine) ?? const <RefactorProposal>[];
    final tangle = report?.tangleMap.perPath[path] ?? 0.0;
    final findings = <SpaghettiFinding>[];
    if (report != null) {
      for (final f in report.findings) {
        if (f.path == path) findings.add(f);
      }
    }
    final related = <RefactorProposal>[];
    for (final p in proposals) {
      if (p.paths.contains(path)) related.add(p);
    }
    // Normalise tangle against the max observed so the bar spans 0..1
    // even when raw contributions are small. Avoids a flat-looking bar
    // on well-behaved repos.
    var maxTangle = 0.05;
    if (report != null) {
      for (final v in report.tangleMap.perPath.values) {
        if (v > maxTangle) maxTangle = v;
      }
    }
    return LogosFileStatus(
      tangle: (tangle / maxTangle).clamp(0.0, 1.0).toDouble(),
      findings: findings,
      proposals: related,
    );
  }

  String? _draftKey;
  // Per-context (branch|upstream) snapshot of the user's file-inclusion
  // picks. Populated on context-switch departure and restored on
  // arrival so that the round-trip main-stage → desk → main-stage
  // preserves every uncheck the user made. Without this, every switch
  // re-seeded from "all files" defaults — the primary driver of the
  // "feels like a full page refresh" perception.
  final Map<String, Set<String>> _includedByContextKey = {};

  // Per-context snapshot of the paths present in the last status
  // refresh. Lets `_reconcileIncludedPaths` detect first-appearance of
  // a file (new ∈ status ∖ seen) without re-adding paths the user
  // deliberately deselected. Only consulted when the
  // `autoSelectNewChanges` pref is on; kept up-to-date regardless so
  // toggling the pref mid-session behaves as if it'd always been on.
  final Map<String, Set<String>> _seenByContextKey = {};

  /// Cached per-file dim opacity derived from the Logos engine's
  /// integrity signal. Recomputed when the engine or status changes.
  /// Files below the changeset's median integrity dim; files at or
  /// above stay vivid. Empty until the engine loads — all files
  /// render at full opacity until then.
  Map<String, double> _fileDimOpacity = const {};
  String? _selectedDiffPath;
  String? _inspectionDiffPath;
  String? _visibleDiffPath;

  /// Diff-navigation history. Pushed when the user drills into a
  /// related path from the drawer (`onOpenRelatedPath`); popped when
  /// they hit the toolbar's `<` button. Empty stack = button hidden.
  /// Purposefully simple — stores only paths, so back from a nested
  /// single-file diff restores that file in single-diff mode even
  /// if the user originally came from a multi-diff context.
  final List<String> _diffNavStack = <String>[];

  /// Scroll + keying infrastructure for the file list. A single
  /// ScrollController lets `_ensureFileVisibleInChangesList` bring
  /// any file row into view on explicit navigation events (rail
  /// click, file-tree click, related-path open, pinned line). Row
  /// keys give us a direct `Scrollable.ensureVisible` path when the
  /// target is already built; an offset-estimate fallback handles
  /// off-screen targets.
  final ScrollController _changesListCtrl = ScrollController();
  final Map<String, GlobalKey> _fileRowKeys = {};
  List<String> _changesListPaths = const [];
  DiffDocument? _diffDocument;
  bool _diffLoading = false;
  String? _diffError;
  String? _multiDiffScopeKey;
  DiffDocument? _multiDiffDocument;
  bool _multiDiffLoading = false;
  String? _multiDiffError;
  List<_CombinedDiffSection> _multiDiffSections = const [];
  final LinkedHashMap<String, _CachedMultiDiff> _multiDiffCache =
      LinkedHashMap();
  final LinkedHashMap<String, DiffFileDocument> _diffFileDocumentCache =
      LinkedHashMap();
  String? _multiDiffCurrentPath;
  int? _multiDiffJumpLineIndex;
  int _multiDiffJumpRequestId = 0;
  // True while the user is actively driving the diff scroll (drag, wheel,
  // ballistic fling). Programmatic animations (jump-to-section) do NOT set
  // this, so the timeline dot tracks user intent and never flickers back
  // to the previous section during an animated jump.
  bool _multiDiffUserDriving = false;
  bool _actionRunning = false;

  // ── AI flows: state is hoisted into AiActivityState (per-repo,
  // session-scoped). The fields below are LOCAL UI view state — drawer
  // visibility, expanders, the generate-success flash timer — kept on
  // the page because they're per-render intent, not per-run identity.
  // Anything tied to a run's identity (running flag, scope key, result,
  // error) reads through the `_reviewRecord` / `_museRecord` /
  // `_generateRecord` / `_askRecord` helpers below.
  bool _commitAiLoading = false;
  String? _commitAiError;
  List<AiModelCategoryData> _commitAiCategories = const [];
  // Single source of UI intent for "which AI drawer is currently
  // showing." Replaces the prior triple of `_reviewActive`,
  // `_museActive`, `_shapeActive` — those let the page reach states
  // where two drawers were "active" simultaneously even though the
  // panel render only ever shows one (mutually exclusive `if/else if`
  // chain), and made cross-drawer navigation a state-mismatch trap
  // rather than a clean swap. Now: one field, one render branch, one
  // mutator path. Null = no drawer (the diff view shows). Generate
  // never opens a drawer — its result lands in the composer — so this
  // field is only ever `null`, `review`, `muse`, or `ask`.
  AiActivityKind? _openDrawer;
  bool _reviewTraceExpanded = false;
  bool _reviewReasoningExpanded = false;
  // Transient flash flags for "the X just succeeded." Cleared by a
  // 1.5s timer in the respective complete branches so the affordance
  // bumps green for a beat then settles. After the flash, the button
  // falls back to the "unread terminal" half-lit visual until the
  // user opens the drawer (which fires markSeen and quiets the
  // button).
  bool _generateFlash = false;
  bool _reviewFlash = false;
  bool _museFlash = false;
  final Map<String, String> _snapshotReviewModelLabel = {};
  final Map<String, int> _snapshotReviewGuardrailStage = {};
  final Map<String, String?> _snapshotReviewEffort = {};
  final Map<String, bool> _snapshotReviewFast = {};
  final Map<String, int> _snapshotMuseGuardrailStage = {};
  final Map<String, String?> _snapshotMuseSynthEffort = {};
  final Map<String, bool> _snapshotMuseSynthFast = {};
  // Monotonic counter for commit-message generation requests, keyed
  // by repoPath so that a generate kicked off on repo B doesn't bump
  // the guard for an in-flight generate on repo A — that misfire used
  // to orphan repo A's running record (it was guard-rejected before
  // any complete/fail/clear could fire). Each call reads + bumps the
  // bucket for its own repo; cross-repo runs are now genuinely
  // independent on the cancel path too.
  final Map<String, int> _generateRequestIds = {};

  int _bumpGenerateRequestId(String repoPath) {
    final next = (_generateRequestIds[repoPath] ?? 0) + 1;
    _generateRequestIds[repoPath] = next;
    return next;
  }

  int _peekGenerateRequestId(String repoPath) =>
      _generateRequestIds[repoPath] ?? 0;
  String? _actionError;
  double _leftPanelWidth = 320.0;
  static const _minLeftPanelWidth = 220.0;
  static const _maxLeftPanelWidth = 520.0;
  static const int _kMaxMultiDiffCacheEntries = 12;
  static const int _kMaxFileDiffCacheEntries = 256;
  bool _commitOnlyMode = false;
  bool _mergeResolving = false;
  // Ask-mode question/answer/error/in-flight all live in the per-repo
  // AiActivityState now. See `_askRecord` below for the read path. The
  // shape-mode composer infrastructure (composer takeover) is what
  // _shapeMode/_shapeCtrl/_shapeFocus track — unrelated to whether a
  // run is in flight.
  // Inline shape-commit mode. When true, the composer field swaps to
  // bind the shape controller (preserving the commit draft in the
  // background) and the bottom split-button morphs into "ask with [cat]"
  // with a chevron that cycles AI categories on each click.
  /// When true, the composer field rebinds to `_shapeCtrl` so the user
  /// can type their ask question in-place of the commit draft. The ◈
  /// toolbar button toggles this.
  bool _shapeMode = false;

  // (formerly `_shapeActive`; now folded into [_openDrawer] above —
  // ask drawer visibility is `_openDrawer == AiActivityKind.ask`.)
  final TextEditingController _shapeCtrl = TextEditingController();
  final FocusNode _shapeFocus = FocusNode();
  int _shapeCategoryIndex = 0;
  Timer? _commitDraftSaveDebounce;
  String? _lastDraftRepoPath;
  String? _lastDraftBranch;

  // In-page undo for single-file discards. Replaces the OS-level
  // SnackBar (which a) layered a full-width banner across the workspace
  // and b) sometimes lingered when a follow-up snackbar got queued
  // behind it). The pill is rendered as a Positioned overlay inside
  // the page's own Stack so it's bounded by the page chrome and fades
  // out cleanly. Bulk discards intentionally don't arm undo — the
  // bytes-snapshot cost scales with file count and the affordance only
  // ever recovered the single most recent operation anyway.

  // Coupling rail — path under the mouse right now. Drives live peer
  // highlighting so moving the cursor along the rail visualizes which
  // files are most tightly coupled to the currently-hovered one.
  String? _railHoverPath;

  // Small LRU for `combinedCouplingScore` lookups along the coupling
  // rail. Hovering different rows rapidly triggers a full rebuild of
  // the change list and N score computations per rebuild. Most of
  // those are between the same file pairs across hovers — a bounded
  // cache invalidated on matrix identity change pays off even at
  // modest hover speeds. Keyed on a canonical "lo|hi" pair so A→B
  // and B→A share the same entry.
  //
  // Kept small (256) because the working-set size during a hover
  // sweep is bounded by the visible row count, not the whole repo.
  // A true LinkedHashMap LRU would be ideal; a plain Map with a
  // hard-clear when it grows past 2× is cheaper to maintain and
  // produces essentially the same hit rate for this access pattern.
  static const int _peerScoreCacheCap = 256;
  final Map<String, double> _peerScoreCache = <String, double>{};
  Object? _peerScoreCacheMatrix;

  // Diffusion-score cache for the right-click "Ripple" submenu.
  // `engine.diffuseWeighted({filePath: 1.0})` is O(K·n) Chebyshev —
  // ~12 matvecs over the coupling graph — and fires on every
  // right-click. Cache per (manifoldRevision, filePath); the whole
  // cache clears whenever the engine's manifold revision advances
  // (stats refresh, branch switch, etc.) so callers never see a
  // stale neighbour set.
  final Map<String, List<RelevanceScore>> _rippleDiffuseCache = {};
  int _rippleDiffuseCacheRevision = -1;

  List<RelevanceScore> _cachedRippleDiffuse(LogosGit engine, String filePath) {
    if (_rippleDiffuseCacheRevision != engine.manifoldRevision) {
      _rippleDiffuseCache.clear();
      _rippleDiffuseCacheRevision = engine.manifoldRevision;
    }
    return _rippleDiffuseCache.putIfAbsent(
      filePath,
      () => engine.diffuseWeighted({filePath: 1.0}),
    );
  }

  List<String> _deriveTagSuggestions(
    LogosGit engine,
    Set<String> diffPaths,
  ) {
    if (diffPaths.isEmpty) return const [];
    final seen = <String>{..._commitTags};
    final scored = <String, double>{};

    void register(String tag, double score) {
      final t = tag.toLowerCase().trim();
      if (t.isEmpty || t.length < 2 || seen.contains(t)) return;
      scored[t] = math.max(scored[t] ?? 0, score);
    }

    // Diffuse heat from the diff's source files through the coupling
    // graph. The top-phi neighbors reveal what structural region of the
    // codebase this change lives in. Extract directory and file-stem
    // tokens from those neighbors, weighted by phi, so the labels
    // reflect the graph topology — not string-matching on messages.
    final neighbors = engine.diffuse(
      diffPaths,
      t: 1.0,
      topK: 20,
      phiThreshold: 0.01,
    );
    if (neighbors.isNotEmpty) {
      final maxPhi = neighbors.first.phi;
      for (final r in neighbors) {
        final w = r.phi / maxPhi;
        final parts = p.split(r.path);
        // Directory segments — the structural context.
        for (var i = 0; i < parts.length - 1 && i < 3; i++) {
          final d = parts[i];
          if (d.length > 2 && d != 'lib' && d != 'src' && d != 'test') {
            register(d, w);
          }
        }
        // File stem — meaningful when it names a subsystem.
        final stem = p.basenameWithoutExtension(r.path);
        if (stem.length > 2 && stem.length < 20) {
          register(stem, w * 0.6);
        }
      }
    }

    // The diff's own paths — direct scope signal, full weight.
    for (final path in diffPaths) {
      final parts = p.split(path);
      for (var i = 0; i < parts.length - 1 && i < 3; i++) {
        final d = parts[i];
        if (d.length > 2 && d != 'lib' && d != 'src' && d != 'test') {
          register(d, 1.0);
        }
      }
      final stem = p.basenameWithoutExtension(path);
      if (stem.length > 2 && stem.length < 20) {
        register(stem, 0.8);
      }
    }

    final ranked = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(6).map((e) => e.key).toList();
  }

  // Single-slot cluster cache. `clusterFiles()` is O(n²) in candidate
  // pair construction and runs inside the main state's build. Before
  // caching, every hover-triggered rebuild paid the full cluster
  // build even though nothing clusterFiles consumes had changed.
  // Keyed on identity of the stable inputs plus a content hash of
  // the in-place mutable Sets (_includedPaths, conflictedPaths).
  FileClusters? _clustersCache;
  Object? _clustersCacheStatus;
  Object? _clustersCacheMatrix;
  Object? _clustersCacheChangeWeights;
  FileSortGuide? _clustersCacheSortGuide;
  bool? _clustersCacheInverted;
  int _clustersCacheIncludedHash = 0;
  int _clustersCacheConflictsHash = 0;

  // Cached hunk-pipeline result for the correlatedness sort. We feed
  // the full change-set diff through `rankHunksByPhiAsync` (the
  // engine's own hunk pipeline — 4-axis blended graph + heat-kernel
  // diffusion + Fiedler basis) once per status change, then lift
  // each hunk's Fiedler coordinate into a per-file centroid for the
  // sort. Async: the first related-sort render after a change uses
  // whichever context is currently cached (legacy fallback when
  // cold), and the next frame gets the fresh one via setState.
  //
  // Ratchet (Whisper #3). `_correlatednessContextDiffHash` is a
  // content hash of the combined diff text the engine last saw.
  // When the next status probe yields the same diff body — common
  // on panel-level marker changes, selection toggles, or stash list
  // updates that touch status identity but don't move hunks — we
  // short-circuit the rebuild and keep the existing context. This
  // saves a full parseDiffHunks + gatherEvidence + rankHunksByPhi
  // round trip (tens to hundreds of ms on churning repos).
  CorrelatednessContext? _correlatednessContext;
  Object? _correlatednessContextStatusRef;
  Object? _correlatednessContextEngineRef;
  int? _correlatednessContextDiffHash;
  Future<void>? _correlatednessContextInflight;

  // Atlas view: when true the file list is replaced with the commit
  // candidates panel from `file_constellation.dart`. Aims to flip the
  // user's job from "carve files out of a list" to "critique the
  // candidates the engine already proposed." Persisted across sessions
  // via SharedPreferences (NOT exposed in settings UI — discovered by
  // clicking the toggle button next to the file list header).
  static const _kAtlasOpenKey = 'changes.atlas_open';
  bool _constellationOpen = false;
  static const _kSelectionSnapshotPrefix = 'changes.selection_state_v1.';
  Timer? _selectionPersistDebounce;
  String? _selectionRepoPath;
  String? _selectionStorageScopeKey;
  bool _selectionStorageLoaded = false;
  int _selectionLoadRequestId = 0;
  String? _selectionPersistFingerprint;

  // PreferencesState subscription for the "remember work in progress"
  // flip-off. Need a listener rather than a context.select because we
  // want the *transition* to off, so we can wipe the current draft +
  // selection the moment the toggle flips — otherwise stale data
  // lingers until the next save-path call.
  PreferencesState? _prefsSub;
  bool _lastRememberWip = true;

  // Per-path line churn (adds + dels) feeding the "by impact" sort.
  // Refreshed whenever the status signature changes. Empty until the
  // first fetch lands; until then impact-sort tiebreaks alphabetically.
  Map<String, FileChangeWeight> _changeWeights = const {};
  String? _weightsFetchedForKey;

  // Symbol-overlap coupling for the current change set. Computed from
  // file content (identifier IDF-Jaccard) so new/untracked files get a
  // structural coupling score even before their first commit.
  Map<String, Map<String, double>> _symbolCoupling = const {};
  String? _symbolCouplingFetchedForKey;

  // Filing cabinet (stashes)
  List<StashEntryData> _stashes = const [];
  bool _stashesLoading = false;
  bool _stashesExpanded = false;
  double _dejaVuScore = 0.0;
  int _dejaVuGhostCount = 0;
  Set<String>? _lastCouplingDiffPaths;
  Object? _lastCouplingEngine;
  bool _stashExpandedInitialized = false;
  String? _stashPeekDiff;
  // Per-stash expanded state (keyed by stash.index) — the filing-cabinet
  // divider. Independent of the list-level _stashesExpanded toggle.
  final Set<int> _stashOpenIndices = {};
  // Lazy-loaded file list per stash (index → files). Populated on first
  // expand; dropped when the stash list is reloaded.
  final Map<int, List<StashFileStat>> _stashFiles = {};
  final Set<int> _stashFilesLoading = {};
  // Geometric signature per stash (keyed by stash.index). Computed lazily
  // in build() once both files and the coupling matrix are available.
  // Cleared when the stash list reloads so shapes don't go stale.
  final Map<int, StashShape> _stashShapes = {};

  // Coupling-matrix loader guard: tracks "I kicked off a compute for this
  // repo in this session" so we don't spam the provider on every rebuild.
  String? _couplingKickedOffFor;
  int? _stashPeekIndex;
  String? _appliedLogosRerankKey;
  List<String>? _appliedLogosRerankPaths;
  String? _pendingLogosRerankKey;
  int _logosRerankRequestId = 0;

  // ── AI activity bridges ────────────────────────────────────────────
  // Records live in [AiActivityState], keyed by (repoPath, kind), so a
  // running review on repo A and a running muse on repo B coexist and
  // both linger across repo / tab switches. The accessors below are
  // build-context bound — they read whatever record matches the
  // currently active repo. The page's build() narrows the rebuild
  // signal via `context.select<AiActivityState, List<AiActivityRecord>>
  // ((s) => s.activeFor(repoPath))` so only the active repo's slice
  // drives rebuilds — the bare `watch` would refire on every cross-
  // repo mutation.

  AiActivityRecord? _activityRecord(AiActivityKind kind) {
    if (!mounted) return null;
    final repoPath = context.read<RepositoryState>().activePath;
    if (repoPath == null) return null;
    return context.read<AiActivityState>().recordFor(repoPath, kind);
  }

  AiActivityRecord? get _generateRecord =>
      _activityRecord(AiActivityKind.generate);
  AiActivityRecord? get _reviewRecord => _activityRecord(AiActivityKind.review);
  AiActivityRecord? get _museRecord => _activityRecord(AiActivityKind.muse);
  AiActivityRecord? get _askRecord => _activityRecord(AiActivityKind.ask);

  bool get _generateRunning => _generateRecord?.isRunning ?? false;
  bool get _reviewRunning => _reviewRecord?.isRunning ?? false;
  bool get _museRunning => _museRecord?.isRunning ?? false;
  bool get _shaping => _askRecord?.isRunning ?? false;

  // (formerly `_reviewSuccess` / `_museSuccess` — replaced by the
  // transient `_reviewFlash` / `_museFlash` for celebration and
  // `_isUnreadFor(kind)` for the persistent half-lit visual.)

  String? get _reviewScopeKey => _reviewRecord?.scopeKey;
  String? get _museScopeKey => _museRecord?.scopeKey;

  AiCommitReviewData? get _reviewResult {
    final r = _reviewRecord;
    if (r == null || !r.isDone) return null;
    final payload = r.result;
    return payload is AiReviewResult ? payload.data : null;
  }

  AiMuseData? get _museResult {
    final r = _museRecord;
    if (r == null || !r.isDone) return null;
    final payload = r.result;
    return payload is AiMuseResult ? payload.data : null;
  }

  String? get _reviewError =>
      _reviewRecord?.isError == true ? _reviewRecord!.error : null;
  String? get _museError =>
      _museRecord?.isError == true ? _museRecord!.error : null;

  // ── Drawer accessors ──────────────────────────────────────────────
  bool get _isReviewDrawerOpen => _openDrawer == AiActivityKind.review;
  bool get _isMuseDrawerOpen => _openDrawer == AiActivityKind.muse;
  bool get _isAskDrawerOpen => _openDrawer == AiActivityKind.ask;

  /// True when the (repo, kind) record is terminal and the user
  /// hasn't acknowledged it yet — the trigger for the toolbar's
  /// "half-lit / unread" visual. Drawer-open implicitly counts as
  /// "viewing" so the half-lit state doesn't render against the
  /// drawer the user is staring at right now.
  bool _isUnreadFor(AiActivityKind kind) {
    final record = _activityRecord(kind);
    if (record == null || !record.isTerminal || record.seen) return false;
    return _openDrawer != kind;
  }

  /// Open one of the AI drawers. Generate is intentionally rejected —
  /// it never had a drawer and never will. Calling this also flips
  /// the unread flag on the record (the act of opening IS the user's
  /// "I've seen this" signal), so the sidebar pill quiets and the
  /// toolbar drops out of the half-lit state on the next build.
  void _openDrawerFor(AiActivityKind kind) {
    assert(kind != AiActivityKind.generate,
        'generate has no drawer — its result lands in the composer.');
    final site = _activitySite();
    if (site != null && _activityRecord(kind) != null) {
      site.state.markSeen(repoPath: site.repoPath, kind: kind);
    }
    setState(() => _openDrawer = kind);
  }

  /// Close whichever drawer is currently open + mark the record as
  /// seen so the sidebar badge clears. Without the markSeen, a user
  /// who dismisses the drawer mid-run would see the sidebar pill
  /// linger as "unread" even though they explicitly chose to leave.
  void _closeDrawer() {
    final kind = _openDrawer;
    if (kind == null) return;
    final site = _activitySite();
    if (site != null) {
      final record = site.state.recordFor(site.repoPath, kind);
      if (record != null && record.isError) {
        site.state.clear(repoPath: site.repoPath, kind: kind);
      } else {
        site.state.markSeen(repoPath: site.repoPath, kind: kind);
      }
    }
    setState(() => _openDrawer = null);
  }

  /// Close the drawer + reset review-pane-internal expander state.
  /// Used by the review pane's `onBack` / `onRerun` so a re-open
  /// starts with collapsed traces, and by the repo / branch switch
  /// reset so a fresh context lands clean.
  void _closeAndResetReviewDrawer() {
    if (_openDrawer == AiActivityKind.review) {
      final site = _activitySite();
      if (site != null) {
        final record =
            site.state.recordFor(site.repoPath, AiActivityKind.review);
        if (record != null && record.isError) {
          site.state
              .clear(repoPath: site.repoPath, kind: AiActivityKind.review);
        } else {
          site.state
              .markSeen(repoPath: site.repoPath, kind: AiActivityKind.review);
        }
      }
    }
    setState(() {
      if (_openDrawer == AiActivityKind.review) _openDrawer = null;
      _reviewTraceExpanded = false;
      _reviewReasoningExpanded = false;
    });
  }

  /// Per-kind clear timers for the celebratory flash bools. Stored
  /// here (vs the original fire-and-forget `Future.delayed`) so we
  /// can cancel on dispose (no closure-retained State after unmount)
  /// and on rapid re-schedule (a second completion within the 1.5 s
  /// window cancels the first timer instead of stacking — the
  /// last-scheduled clear wins, which lines up with the user's
  /// mental model of "the latest run is what's flashing").
  final Map<AiActivityKind, Timer> _flashClearTimers = {};

  /// Schedule a 1.5 s clear of the given flash bool. Used by the
  /// generate / review / muse complete paths so the toolbar button
  /// celebrates briefly, then settles into either "unread" (if the
  /// drawer wasn't open when it landed) or quiet success (if it was).
  void _scheduleFlashClear(AiActivityKind kind, void Function() clear) {
    _flashClearTimers.remove(kind)?.cancel();
    _flashClearTimers[kind] = Timer(const Duration(milliseconds: 1500), () {
      _flashClearTimers.remove(kind);
      if (mounted) setState(clear);
    });
  }

  String? get _askError =>
      _askRecord?.isError == true ? _askRecord!.error : null;

  String? get _askQuestion => _askRecord?.scopeLabel;
  String? get _askAnswer {
    final r = _askRecord;
    if (r == null || !r.isDone) return null;
    final payload = r.result;
    return payload is AiAskResult ? payload.answer : null;
  }

  /// Convenience snapshot for setState callers that need to mutate the
  /// activity state for the active repo. Returns null when there's no
  /// active repo (caller bails — the AI flows can't run there anyway).
  ({String repoPath, AiActivityState state})? _activitySite() {
    if (!mounted) return null;
    final repoPath = context.read<RepositoryState>().activePath;
    if (repoPath == null) return null;
    return (
      repoPath: repoPath,
      state: context.read<AiActivityState>(),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      DiagnosticsState.instance.recordUiTiming(
        event: 'changes.page.first-paint',
        phase: 'mount',
        durationMs: _mountedAt.elapsedMicroseconds / 1000,
      );
      final prefs = context.read<PreferencesState>();
      if (!prefs.hideAiFeatures) {
        _refreshCommitAiConfig();
        unawaited(context.read<AiSettingsState>().refreshProviders());
      }
      _lastRememberWip = prefs.rememberWorkInProgress;
      _leftPanelWidth = prefs.changesPanelWidthPx.toDouble().clamp(
            _minLeftPanelWidth, _maxLeftPanelWidth);
      prefs.addListener(_onPreferencesChanged);
      _prefsSub = prefs;
    });
    _loadAtlasOpenPref();
    // Re-dream when the composer goes empty again (user deleted their
    // draft) so the hint repopulates.
    _commitMsgCtrl.addListener(_onComposerChangedForDream);
    // Rebuild on dream resolution so the composer picks up the new
    // hint without the call site having to know anything about it.
    _commitDream.addListener(_onCommitDreamChanged);
  }

  void _onCommitDreamChanged() {
    if (mounted) setState(() {});
  }

  /// Fires whenever any preference changes. We only care about the
  /// `rememberWorkInProgress` transition from on → off: on flip-off,
  /// actively wipe the current commit draft file and the current
  /// selection scope so the toggle feels honest rather than waiting for
  /// the next save-path call to erase things.
  void _onPreferencesChanged() {
    if (!mounted) return;
    final prefs = _prefsSub;
    if (prefs == null) return;
    final nowRemember = prefs.rememberWorkInProgress;
    if (_lastRememberWip && !nowRemember) {
      unawaited(_clearCommitDraft());
      _commitMsgCtrl.clear();
      final scopeKey = _selectionStorageScopeKey;
      if (scopeKey != null) {
        unawaited(() async {
          try {
            final shared = await SharedPreferences.getInstance();
            await shared.remove(_selectionPrefsKey(scopeKey));
          } catch (_) {}
        }());
      }
    }
    _lastRememberWip = nowRemember;
  }

  /// Fires on every composer keystroke. We only care about the
  /// empty-transition boundary; when the composer is non-empty, the
  /// hint isn't visible anyway, so a pending compute would do nothing
  /// useful either way.
  void _onComposerChangedForDream() {
    if (!mounted) return;
    if (_commitMsgCtrl.text.trim().isEmpty && _commitDream.value != null) {
      // Composer just emptied. Invalidate the signature so the next
      // build's schedule call recomputes rather than short-circuits.
      _commitDream.invalidate();
    }
  }

  /// Run the dream + field-character pipeline for the current
  /// selection and return the paired payload. Closes over `repoPath`
  /// and `includedPaths` at schedule time so the controller's debounce
  /// + supersede logic can shepherd a clean lifecycle around it.
  Future<_CommitDream?> _computeCommitDream({
    required String repoPath,
    required List<String> includedPaths,
  }) async {
    final engine = context.read<LogosGitState>().engineFor(repoPath);
    if (engine == null) return null;

    // Small context (-U3) — we need the touched nodes, not the
    // surrounding function bodies.
    final diffArgs = [
      'diff',
      '-U3',
      '--no-color',
      '--patience',
      '--ignore-cr-at-eol',
      '--',
      ...includedPaths,
    ];
    final stagedArgs = [
      'diff',
      '--cached',
      '-U3',
      '--no-color',
      '--patience',
      '--ignore-cr-at-eol',
      '--',
      ...includedPaths,
    ];

    final results = await Future.wait([
      runGitProbe(repoPath, diffArgs),
      runGitProbe(repoPath, stagedArgs),
      runGitProbe(repoPath, ['log', '--format=%s', '-100']),
    ]);

    final unstaged =
        results[0].exitCode == 0 ? results[0].stdout.toString() : '';
    final staged = results[1].exitCode == 0 ? results[1].stdout.toString() : '';
    final diffText =
        [staged, unstaged].where((d) => d.trim().isNotEmpty).join('\n');
    if (diffText.isEmpty) return null;

    final subjects = results[2].exitCode == 0
        ? results[2]
            .stdout
            .toString()
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : const <String>[];

    final result = await dreamAndCharacterizeFromDiff(
      repoPath: repoPath,
      diffText: diffText,
      engine: engine,
      recentSubjects: subjects,
    );
    return (phrase: result.phrase, character: result.character);
  }

  Future<void> _loadAtlasOpenPref() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_kAtlasOpenKey) ?? false;
    if (mounted && v != _constellationOpen) {
      setState(() => _constellationOpen = v);
    }
  }

  Future<void> _recordUiTimingSample({
    required String event,
    required Stopwatch stopwatch,
    String phase = 'interaction',
    bool ok = true,
    String? errorCode,
    double minMs = 8,
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

  Future<void> _toggleAtlasOpen() async {
    final next = !_constellationOpen;
    setState(() => _constellationOpen = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAtlasOpenKey, next);
  }

  String _normalizeSelectionStoragePath(String path) {
    final normalized = p.normalize(path).replaceAll('\\', '/');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _selectionPrefsKey(String scopeKey) =>
      '$_kSelectionSnapshotPrefix$scopeKey';

  Future<String> _resolveSelectionStorageScopeKey(String repoPath) async {
    var mainRepoPath = repoPath;
    try {
      final result = await Process.run(
        'git',
        ['rev-parse', '--path-format=absolute', '--git-common-dir'],
        workingDirectory: repoPath,
      );
      if (result.exitCode == 0) {
        final commonDir = (result.stdout as String).trim();
        if (commonDir.isNotEmpty) {
          mainRepoPath = p.dirname(commonDir);
        }
      }
    } catch (_) {}
    final repoKey = _normalizeSelectionStoragePath(mainRepoPath);
    final worktreeKey = _normalizeSelectionStoragePath(repoPath);
    return '$repoKey::$worktreeKey';
  }

  Map<String, Set<String>> _selectionSnapshot() {
    final snapshot = <String, Set<String>>{
      for (final entry in _includedByContextKey.entries)
        entry.key: Set<String>.from(entry.value),
    };
    final currentKey = _draftKey;
    if (currentKey != null) {
      snapshot[currentKey] = Set<String>.from(_includedPaths);
    }
    return snapshot;
  }

  Map<String, List<String>> _selectionSnapshotJson(
    Map<String, Set<String>> snapshot,
  ) {
    final orderedKeys = snapshot.keys.toList()..sort();
    final encoded = <String, List<String>>{};
    for (final key in orderedKeys) {
      final paths = snapshot[key]!.toList()..sort();
      encoded[key] = paths;
    }
    return encoded;
  }

  String _selectionPersistenceFingerprint(String scopeKey) {
    return jsonEncode({
      'scope': scopeKey,
      'contexts': _selectionSnapshotJson(_selectionSnapshot()),
    });
  }

  Map<String, Set<String>> _decodeSelectionSnapshot(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String, Set<String>>{};
    }
    try {
      final decoded = jsonDecode(raw);
      final rawContexts = decoded is Map<String, dynamic>
          ? (decoded['contexts'] is Map ? decoded['contexts'] as Map : decoded)
          : null;
      if (rawContexts == null) {
        return const <String, Set<String>>{};
      }
      final out = <String, Set<String>>{};
      for (final entry in rawContexts.entries) {
        final value = entry.value;
        if (value is! List) continue;
        final paths = <String>{};
        for (final item in value) {
          if (item is String && item.isNotEmpty) {
            paths.add(item);
          }
        }
        out[entry.key.toString()] = paths;
      }
      return out;
    } catch (_) {
      return const <String, Set<String>>{};
    }
  }

  Future<void> _persistSelectionSnapshotForScope(
    String scopeKey,
    Map<String, Set<String>> snapshot,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefKey = _selectionPrefsKey(scopeKey);
      // Honor the "remember work in progress" pref: when off, every
      // "persist" call becomes an active clear so the on-disk footprint
      // erases as the user works, not just when they deselect everything.
      // Falls back to the cached last value so dispose-time flushes
      // (which fire via `unawaited(...)` after the widget may have
      // unmounted) still honor the pref.
      final remember = mounted
          ? context.read<PreferencesState>().rememberWorkInProgress
          : _lastRememberWip;
      if (!remember || snapshot.isEmpty) {
        await prefs.remove(prefKey);
        return;
      }
      await prefs.setString(
        prefKey,
        jsonEncode({
          'version': 1,
          'contexts': _selectionSnapshotJson(snapshot),
        }),
      );
    } catch (_) {}
  }

  Future<void> _persistSelectionStateNow() async {
    final scopeKey = _selectionStorageScopeKey;
    if (scopeKey == null) {
      return;
    }
    await _persistSelectionSnapshotForScope(scopeKey, _selectionSnapshot());
  }

  void _scheduleSelectionPersistence() {
    if (!_selectionStorageLoaded || _selectionStorageScopeKey == null) {
      return;
    }
    _selectionPersistDebounce?.cancel();
    _selectionPersistDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistSelectionStateNow());
    });
  }

  void _flushSelectionPersistenceBestEffort() {
    _selectionPersistDebounce?.cancel();
    _selectionPersistDebounce = null;
    final scopeKey = _selectionStorageScopeKey;
    if (!_selectionStorageLoaded || scopeKey == null) {
      return;
    }
    final snapshot = _selectionSnapshot();
    unawaited(_persistSelectionSnapshotForScope(scopeKey, snapshot));
  }

  void _resetSelectionScopeState() {
    _draftKey = null;
    _includedPaths.clear();
    _includedByContextKey.clear();
    _seenByContextKey.clear();
    _fileDimOpacity = const {};
    _selectedDiffPath = null;
    _inspectionDiffPath = null;
    _visibleDiffPath = null;
    _diffDocument = null;
    _diffLoading = false;
    _diffError = null;
    _multiDiffScopeKey = null;
    _multiDiffDocument = null;
    _multiDiffLoading = false;
    _multiDiffError = null;
    _multiDiffSections = const [];
    _multiDiffCurrentPath = null;
    _multiDiffJumpLineIndex = null;
    _actionError = null;
    // Repo / context switch — drawers from the previous context no
    // longer match the user's mental scope. Close everything; the
    // records persist in AiActivityState so a re-visit still finds
    // its content.
    _openDrawer = null;
    _reviewTraceExpanded = false;
    _reviewReasoningExpanded = false;
    // Drop any in-flight flash. The flash bools are page-local and
    // not keyed to a repo path; without this reset, a completion that
    // landed on the previous repo within the 1.5 s decay window would
    // bleed onto the new repo's toolbar as a phantom celebratory
    // flash. The pending Future.delayed clears are idempotent (just
    // set the bool false again later), so leaving them in flight is
    // safe.
    _generateFlash = false;
    _reviewFlash = false;
    _museFlash = false;
  }

  Future<void> _loadSelectionStateForRepo(String repoPath) async {
    final repoState = context.read<RepositoryState>();
    final requestId = ++_selectionLoadRequestId;
    final scopeKey = await _resolveSelectionStorageScopeKey(repoPath);
    final prefs = await SharedPreferences.getInstance();
    final prefKey = _selectionPrefsKey(scopeKey);
    // Honor the "remember work in progress" pref: when off, skip the
    // restore AND clear any lingering snapshot for this scope so stale
    // state gets erased on visit.
    final remember = mounted
        ? context.read<PreferencesState>().rememberWorkInProgress
        : _lastRememberWip;
    Map<String, Set<String>> restored;
    if (!remember) {
      await prefs.remove(prefKey);
      restored = const {};
    } else {
      restored = _decodeSelectionSnapshot(prefs.getString(prefKey));
    }
    if (!mounted ||
        _selectionRepoPath != repoPath ||
        requestId != _selectionLoadRequestId) {
      return;
    }
    final currentStatus = repoState.status;
    setState(() {
      _selectionStorageScopeKey = scopeKey;
      _selectionStorageLoaded = true;
      _selectionPersistFingerprint = null;
      _draftKey = null;
      _includedPaths.clear();
      _includedByContextKey
        ..clear()
        ..addAll(restored);
      _seenByContextKey.clear();
      _fileDimOpacity = const {};
      if (currentStatus != null) {
        _syncDraftFromStatus(currentStatus);
      }
    });
  }

  void _cancelPendingLogosRerank() {
    _pendingLogosRerankKey = null;
    _logosRerankRequestId++;
  }

  String _logosRerankKey({
    required LogosGit engine,
    required FileClusters clusters,
    required Set<String> sources,
    required double t,
    required double coherenceGate,
    required bool inverted,
  }) {
    final orderedDigest = Object.hashAll(clusters.orderedPaths);
    final sortedSources = sources.toList()..sort();
    final sourceDigest = Object.hashAll(sortedSources);
    final engineDigest = Object.hash(
      engine.nodePaths.length,
      engine.stats.totalCommits,
      engine.symbolEdges.length,
    );
    return [
      engineDigest,
      _symbolCouplingFetchedForKey ?? '',
      orderedDigest,
      sourceDigest,
      t.toStringAsFixed(3),
      coherenceGate.toStringAsFixed(3),
      inverted ? 1 : 0,
    ].join('|');
  }

  void _scheduleLogosRerank({
    required String requestKey,
    required FileClusters clusters,
    required LogosGit engine,
    required Set<String> sources,
    required double t,
    required double coherenceGate,
    required bool inverted,
  }) {
    if (_pendingLogosRerankKey == requestKey) {
      return;
    }
    _pendingLogosRerankKey = requestKey;
    final requestId = ++_logosRerankRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _pendingLogosRerankKey != requestKey) {
        return;
      }
      final stopwatch = Stopwatch()..start();
      final next = await _computeLogosRerankedOrder(
        clusters: clusters,
        engine: engine,
        sources: sources,
        t: t,
        coherenceGate: coherenceGate,
        inverted: inverted,
      );
      await _recordUiTimingSample(
        event: 'changes.logos.rerank.compute',
        stopwatch: stopwatch,
        phase: 'compute',
      );
      if (!mounted ||
          _logosRerankRequestId != requestId ||
          _pendingLogosRerankKey != requestKey) {
        return;
      }
      setState(() {
        _appliedLogosRerankKey = requestKey;
        _appliedLogosRerankPaths = next;
        _pendingLogosRerankKey = null;
      });
    });
  }

  /// Cached `clusterFiles()` wrapper. Returns the cached [FileClusters]
  /// when every input the clustering actually depends on matches the
  /// prior build; otherwise recomputes and stores. Hover-only rebuilds
  /// no longer repay the O(n²) pair enumeration.
  /// Ensure a fresh CorrelatednessContext is available for the
  /// current (repo, status, engine) triple. Returns the currently-
  /// cached context synchronously — may be null on first access or
  /// stale during an in-flight rebuild; the caller always falls back
  /// to the legacy nearest-neighbour chain in that case.
  ///
  /// When the inputs have changed since the last rebuild and no
  /// build is in flight, kicks off an async rebuild that:
  ///   1. runs the same `git diff` + `git diff --cached` probes the
  ///      panel already uses for other features
  ///   2. parses via `parseDiffHunks`
  ///   3. runs the engine's canonical `rankHunksByPhiAsync` — the
  ///      full 4-axis hunk graph with engram K-blend, heat-kernel
  ///      diffusion, and cached spectral basis
  ///   4. wraps the result in a `CorrelatednessContext` that
  ///      `seriateByHunkFiedler` consumes to lift per-hunk Fiedler
  ///      coordinates into per-file centroids
  /// When the rebuild completes, we setState so the next frame
  /// re-clusters with the refreshed context.
  CorrelatednessContext? _correlatednessContextFor({
    required String repoPath,
    required RepositoryStatus status,
    required LogosGit engine,
  }) {
    final statusChanged = !identical(_correlatednessContextStatusRef, status);
    final engineChanged = !identical(_correlatednessContextEngineRef, engine);
    if (!statusChanged &&
        !engineChanged &&
        _correlatednessContextInflight == null) {
      return _correlatednessContext;
    }
    if (_correlatednessContextInflight != null) {
      // Already rebuilding — return whatever's cached (may be null
      // or stale); the caller has a sensible fallback.
      return _correlatednessContext;
    }
    _correlatednessContextStatusRef = status;
    _correlatednessContextEngineRef = engine;
    _correlatednessContextInflight = _rebuildCorrelatednessContext(
      repoPath: repoPath,
      status: status,
      engine: engine,
    ).whenComplete(() {
      _correlatednessContextInflight = null;
    });
    return _correlatednessContext;
  }

  Future<void> _rebuildCorrelatednessContext({
    required String repoPath,
    required RepositoryStatus status,
    required LogosGit engine,
  }) async {
    // Fetch the full change-set diff — same probes the shape-prompt
    // pipeline already uses a few hundred lines above.
    const diffArgs = [
      'diff',
      '-U3',
      '--no-color',
      '--patience',
      '--ignore-cr-at-eol',
    ];
    const stagedArgs = [
      'diff',
      '--cached',
      '-U3',
      '--no-color',
      '--patience',
      '--ignore-cr-at-eol',
    ];
    List<ProcessResult> probes;
    try {
      probes = await Future.wait([
        runGitProbe(repoPath, diffArgs),
        runGitProbe(repoPath, stagedArgs),
      ]);
    } on Object {
      return; // git unavailable / repo broken — keep whatever's cached
    }

    final unstaged = probes[0].exitCode == 0 ? probes[0].stdout.toString() : '';
    final staged = probes[1].exitCode == 0 ? probes[1].stdout.toString() : '';

    // `git diff` / `git diff --cached` never emit blocks for untracked
    // files. Those paths are visible in the panel AND we want them
    // placed by the spectral seriator, so synthesize a unified-diff
    // "new file" block per untracked path and append — the existing
    // parser handles the result uniformly.
    final synthesized = await _synthesiseUntrackedDiffs(repoPath, status);
    final combined = [staged, unstaged, synthesized]
        .where((d) => d.trim().isNotEmpty)
        .join('\n');
    if (combined.isEmpty) {
      if (!mounted) return;
      setState(() {
        _correlatednessContext = null;
        _correlatednessContextDiffHash = null;
      });
      return;
    }

    // Ratchet short-circuit. If the combined diff body is byte-for-
    // byte what the engine last ranked, the spectral basis it
    // produced is still correct — skip the whole pipeline and keep
    // the cached context. Uses Dart's built-in hashCode on the
    // String (64-bit splay-based) which is plenty collision-safe for
    // this gate. Worst case of a collision: we skip a rebuild that
    // should have happened, and the sort lags one status cycle —
    // not a correctness bug.
    final diffHash = combined.hashCode;
    if (_correlatednessContextDiffHash == diffHash &&
        _correlatednessContext != null) {
      return;
    }

    final parsed = hunks.parseDiffHunks(combined);
    if (parsed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _correlatednessContext = null;
        _correlatednessContextDiffHash = diffHash;
      });
      return;
    }

    // Pipeline conformance with `diff_logos_facade`: pre-compute the
    // file-level evidence at detailBudget=32 so the H_file axis in the
    // hunk graph sees the same resolution the facade uses. Without
    // this, `rankHunksByPhiAsync` falls through `_resolveFileCoupling`
    // at detailBudget=4 (8× less detailed) — that was the "missing
    // files" surface. `buildHunkFileEvidenceFromResiduals` filters the
    // residuals to the touched paths and produces the coupling map
    // the hunk engine consumes directly.
    final touchedPaths = <String>{for (final h in parsed) h.filePath};
    final focusWeights = <String, double>{
      for (final path in touchedPaths) path: 1.0,
    };
    final evidence = await _gatherEvidenceOffThread(
      engine: engine,
      focusWeights: focusWeights,
      t: 1.0,
    );
    final fileEvidence = evidence == null
        ? null
        : hunks.buildHunkFileEvidenceFromResiduals(
            evidence.residualByPath,
            touchedPaths: touchedPaths,
          );

    // Wall-clock anchors per touched file for the temporal lift
    // (Whisper #2). Uses `perFileCommitClock` from the engine's own
    // stats — latest timestamp per file = the file's "era". New /
    // untracked files (no history yet) get the current wall clock so
    // they cluster with the freshest tracked files, not with ancient
    // ones.
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final ageByPath = <String, double>{};
    for (final path in touchedPaths) {
      final clock = engine.stats.perFileCommitClock[path];
      if (clock != null && clock.isNotEmpty) {
        ageByPath[path] = clock.last;
      } else {
        ageByPath[path] = now;
      }
    }

    // KEEP engram assets on top of the canonical evidence pre-compute.
    // `diff_logos_facade` drops engram for prompt-budget reasons that
    // don't apply to file-ordering — the seriator has no byte budget
    // and gets a strictly stronger H_sym from the 2-axis (Jaccard +
    // K-cosine) blend. So the pipeline here *supersets* the facade:
    // same evidence structure (detailBudget=32), same builder, plus
    // engram's structural signal where the facade omits it.
    final engramAssets = await EngramRuntime.instance.assets();
    final result = await hunks.rankHunksByPhiAsync(
      hunks: parsed,
      logosEngine: engine,
      fileEvidence: fileEvidence,
      engramAssets: engramAssets,
    );
    if (!mounted) return;
    setState(() {
      _correlatednessContext = CorrelatednessContext(
        hunks: parsed,
        hunkResult: result,
        ageByFilePath: ageByPath,
      );
      _correlatednessContextDiffHash = diffHash;
    });
  }

  /// Off-thread evidence gather. Matches the pattern in
  /// `diff_logos_facade._gatherEvidenceOffThread` — isolates the
  /// O(k·n) spectral projection so the UI stays responsive on large
  /// repos. Falls through to the on-thread call on isolate error.
  Future<LogosEvidenceQueryResult?> _gatherEvidenceOffThread({
    required LogosGit engine,
    required Map<String, double> focusWeights,
    required double t,
  }) async {
    try {
      return await Isolate.run<LogosEvidenceQueryResult?>(
        () => engine.gatherEvidence(
          focusWeights: focusWeights,
          t: t,
          detailBudget: 32,
          includeSpectrum: false,
          includeSupportAttribution: false,
          includeSummaryDiagnostics: false,
        ),
        debugName: 'changesCorrelatednessEvidence',
      );
    } catch (_) {
      return engine.gatherEvidence(
        focusWeights: focusWeights,
        t: t,
        detailBudget: 32,
        includeSpectrum: false,
        includeSupportAttribution: false,
        includeSummaryDiagnostics: false,
      );
    }
  }

  /// For each untracked file in [status], read its content and build a
  /// valid unified-diff "new file" block. Returns the blocks joined
  /// with newlines; empty string when the repo has no untracked
  /// files. Used by [_rebuildCorrelatednessContext] to make sure
  /// untracked paths participate in the hunk spectral embedding
  /// alongside tracked files — without this, `git diff` skipped them
  /// and they collapsed to a uniform fallback coordinate in the sort.
  ///
  /// Per-file content is capped to keep pathological cases (huge
  /// generated assets committed as untracked) from inflating the
  /// hunk graph. 16 KiB matches what `engram_file_index` uses for its
  /// own cap — enough to capture a file's identifier surface,
  /// bounded enough to stay cheap across dozens of untracked files.
  Future<String> _synthesiseUntrackedDiffs(
    String repoPath,
    RepositoryStatus status,
  ) async {
    const perFileCap = 16 * 1024;
    final buf = StringBuffer();
    for (final f in status.files) {
      if (!f.isUntracked) continue;
      final absPath = p.join(repoPath, f.path);
      final file = File(absPath);
      if (!await file.exists()) continue;
      Uint8List bytes;
      try {
        final raf = await file.open();
        try {
          final length = await raf.length();
          final readN = length < perFileCap ? length : perFileCap;
          bytes = await raf.read(readN);
        } finally {
          await raf.close();
        }
      } on FileSystemException {
        continue;
      }
      if (_looksLikeBinary(bytes)) continue;
      String text;
      try {
        text = utf8.decode(bytes, allowMalformed: true);
      } on FormatException {
        continue;
      }
      if (text.isEmpty) continue;
      final lines = text.split('\n');
      // `split` on a trailing newline yields an extra empty element;
      // drop it so the `@@ -0,0 +1,N @@` line count is accurate.
      if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
      if (lines.isEmpty) continue;

      // Synthetic unified-diff block. Format matches what git emits
      // for a `diff --cached` on a freshly-added file, which is what
      // `parseDiffHunks` expects:
      //
      //   diff --git a/path b/path
      //   new file mode 100644
      //   --- /dev/null
      //   +++ b/path
      //   @@ -0,0 +1,N @@
      //   +line_1
      //   +line_2
      //   ...
      final path = f.path;
      buf.writeln('diff --git a/$path b/$path');
      buf.writeln('new file mode 100644');
      buf.writeln('--- /dev/null');
      buf.writeln('+++ b/$path');
      buf.writeln('@@ -0,0 +1,${lines.length} @@');
      for (final line in lines) {
        buf.writeln('+$line');
      }
    }
    return buf.toString();
  }

  /// Null-byte sniff over [bytes]. Identical to the binary-detection
  /// heuristic used by `text_harvest.dart` and `git.dart` elsewhere —
  /// any 0x00 byte in the prefix → binary → skip. Keeps synthetic
  /// diffs from ever containing non-text content that would corrupt
  /// the unified-diff parser downstream.
  bool _looksLikeBinary(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  FileClusters _clustersFor({
    required RepositoryStatus status,
    required FileCouplingMatrix? effectiveMatrix,
    required List<String> currentPaths,
    required FileSortGuide sortGuide,
    required Map<String, FileImpactSignal> impactSignals,
    required Set<String> conflictedPaths,
    required bool inverted,
    CorrelatednessContext? correlatednessContext,
    CouplingConstants couplingConstants = CouplingConstants.prior,
  }) {
    if (effectiveMatrix == null || currentPaths.isEmpty) {
      // Empty-case short-circuit; no point caching a zero-cost answer.
      return FileClusters.empty(currentPaths);
    }
    // Stable content hashes for the mutable Sets: _includedPaths is a
    // field that's mutated in place across builds, and conflictedPaths
    // is derived fresh each build from `status`. Object.hashAll on a
    // Set is iteration-order dependent, which is fine here because Set
    // iteration in Dart is insertion order and we only need change
    // detection, not semantic equality.
    final includedHash = Object.hashAll(_includedPaths);
    final conflictsHash = Object.hashAll(conflictedPaths);

    if (identical(_clustersCacheStatus, status) &&
        identical(_clustersCacheMatrix, effectiveMatrix) &&
        identical(_clustersCacheChangeWeights, _changeWeights) &&
        _clustersCacheSortGuide == sortGuide &&
        _clustersCacheInverted == inverted &&
        _clustersCacheIncludedHash == includedHash &&
        _clustersCacheConflictsHash == conflictsHash &&
        _clustersCache != null) {
      return _clustersCache!;
    }

    final result = clusterFiles(
      currentPaths,
      effectiveMatrix,
      couplingConstants: couplingConstants,
      sortGuide: sortGuide,
      impactSignals: impactSignals,
      conflictedPaths: conflictedPaths,
      includedPaths: _includedPaths,
      inverted: inverted,
      correlatednessContext: correlatednessContext,
    );
    _clustersCache = result;
    _clustersCacheStatus = status;
    _clustersCacheMatrix = effectiveMatrix;
    _clustersCacheChangeWeights = _changeWeights;
    _clustersCacheSortGuide = sortGuide;
    _clustersCacheInverted = inverted;
    _clustersCacheIncludedHash = includedHash;
    _clustersCacheConflictsHash = conflictsHash;
    return result;
  }

  /// Cached peer-score lookup: reads [_peerScoreCache] or computes
  /// and stores on miss. Invalidates when the coupling matrix
  /// identity changes (a new FileCouplingMatrix instance implies
  /// potentially-different scores and different path→id mapping).
  double _cachedPeerScore(String a, String b, FileCouplingMatrix matrix) {
    if (!identical(_peerScoreCacheMatrix, matrix)) {
      _peerScoreCache.clear();
      _peerScoreCacheMatrix = matrix;
    }
    // Canonicalise pair so A→B and B→A share an entry.
    final key = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
    final existing = _peerScoreCache[key];
    if (existing != null) return existing;
    if (_peerScoreCache.length >= _peerScoreCacheCap * 2) {
      _peerScoreCache.clear();
    }
    final score = combinedCouplingScore(a, b, matrix);
    _peerScoreCache[key] = score;
    return score;
  }

  /// Per-session cache of resolved `.git` paths. The git dir for a
  /// given working tree is structural — it doesn't change while the
  /// app is running — so the first successful resolve can be reused
  /// on every subsequent draft save / load / flush / clear. Without
  /// this each of those paths spawns a fresh `git rev-parse --git-dir`
  /// subprocess (~50-150ms) for no reason.
  final Map<String, String> _gitDirCache = {};

  /// Resolve the git directory for a repo. Handles worktrees and submodules
  /// where `.git` may be a file rather than a directory. Cached.
  Future<String?> _resolveGitDir(String repoPath) async {
    final cached = _gitDirCache[repoPath];
    if (cached != null) return cached;
    try {
      final result = await Process.run(
        'git',
        ['rev-parse', '--git-dir'],
        workingDirectory: repoPath,
      );
      if (result.exitCode == 0) {
        final gitDir = (result.stdout as String).trim();
        // rev-parse returns relative or absolute — normalize.
        final resolved =
            p.isAbsolute(gitDir) ? gitDir : p.join(repoPath, gitDir);
        _gitDirCache[repoPath] = resolved;
        return resolved;
      }
    } catch (_) {}
    // Fallback to the common case. Don't cache the fallback — if
    // rev-parse came back broken we want to retry on the next call
    // rather than lock in a wrong answer.
    return p.join(repoPath, '.git');
  }

  File _draftFile(String gitDir, [String? branch]) {
    if (branch == null || branch.isEmpty) {
      return File(p.join(gitDir, 'MANIFOLD_COMMIT_MSG'));
    }
    // Sanitize branch name for use as a filename suffix.
    final safe = branch.replaceAll(RegExp(r'[^\w.-]'), '_');
    return File(p.join(gitDir, 'MANIFOLD_COMMIT_MSG_$safe'));
  }

  Future<void> _loadCommitDraftForRepo(String repoPath,
      {String? branch, bool force = false}) async {
    try {
      final gitDir = await _resolveGitDir(repoPath);
      if (gitDir == null) return;
      // Stale guard: _resolveGitDir spawns a git subprocess. By the
      // time it returns, the user might have switched repos/branches
      // again. If so, this load is for a scope the user has already
      // left — applying it would flash stale text in the composer
      // for one frame before the next switch clears it.
      if (_lastDraftRepoPath != repoPath || _lastDraftBranch != branch) {
        return;
      }
      final file = _draftFile(gitDir, branch);
      // Honor the "remember work in progress" pref: when off, treat any
      // lingering draft file as stale — delete it on touch and start
      // clean instead of restoring.
      final remember = mounted
          ? context.read<PreferencesState>().rememberWorkInProgress
          : _lastRememberWip;
      if (!remember) {
        if (await file.exists()) await file.delete();
        if (force && mounted) _commitMsgCtrl.clear();
        return;
      }
      if (await file.exists()) {
        final draft = await file.readAsString();
        // Second stale guard: the file read is another async gap.
        if (!mounted) return;
        if (_lastDraftRepoPath != repoPath || _lastDraftBranch != branch) {
          return;
        }
        if (force || _commitMsgCtrl.text.isEmpty) {
          _commitMsgCtrl.text = draft;
        }
      } else if (force && mounted) {
        if (_lastDraftRepoPath != repoPath || _lastDraftBranch != branch) {
          return;
        }
        _commitMsgCtrl.clear();
      }
    } catch (_) {}
  }

  void _saveCommitDraft(String value) {
    _commitDraftSaveDebounce?.cancel();
    // Capture repo path and branch NOW, not when the timer fires — prevents
    // saving to the wrong repo/branch after a switch.
    final capturedRepoPath = _lastDraftRepoPath;
    final capturedBranch = _lastDraftBranch;
    // Honor the "remember work in progress" pref: when off, any save
    // attempt becomes a delete so existing drafts don't linger on disk.
    final remember = context.read<PreferencesState>().rememberWorkInProgress;
    _commitDraftSaveDebounce =
        Timer(const Duration(milliseconds: 500), () async {
      try {
        final repoPath =
            capturedRepoPath ?? context.read<RepositoryState>().activePath;
        if (repoPath == null) return;
        final gitDir = await _resolveGitDir(repoPath);
        if (gitDir == null) return;
        final file = _draftFile(gitDir, capturedBranch);
        if (!remember || value.trim().isEmpty) {
          if (await file.exists()) await file.delete();
        } else {
          await file.writeAsString(value);
        }
      } catch (_) {}
    });
  }

  Future<void> _clearCommitDraft() async {
    try {
      final repoPath =
          _lastDraftRepoPath ?? context.read<RepositoryState>().activePath;
      if (repoPath == null) return;
      final gitDir = await _resolveGitDir(repoPath);
      if (gitDir == null) return;
      final file = _draftFile(gitDir, _lastDraftBranch);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Immediately write a draft to disk — no debounce. Used on branch/repo
  /// switch and app lifecycle transitions to avoid losing in-progress text.
  Future<void> _flushDraft(
      String repoPath, String? branch, String value) async {
    try {
      final gitDir = await _resolveGitDir(repoPath);
      if (gitDir == null) return;
      final file = _draftFile(gitDir, branch);
      // Reads `_lastRememberWip` (maintained by the preferences
      // listener) rather than `context.read` so this works correctly
      // when called during dispose, after the widget has unmounted.
      if (!_lastRememberWip || value.trim().isEmpty) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsString(value);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _commitDraftSaveDebounce?.cancel();
    // Cancel any in-flight flash-clear timers. Each timer's callback
    // captures `this`, so leaving them uncancelled would keep the
    // State alive for up to 1.5 s after unmount. The mounted guard
    // inside the callback would prevent any setState fault, but the
    // retention itself is the avoidable cost.
    for (final t in _flashClearTimers.values) {
      t.cancel();
    }
    _flashClearTimers.clear();
    _flushSelectionPersistenceBestEffort();
    // Flush on dispose so closing the app doesn't lose the draft.
    final repo = _lastDraftRepoPath;
    final branch = _lastDraftBranch;
    final text = _commitMsgCtrl.text;
    if (repo != null && text.trim().isNotEmpty) {
      _flushDraft(repo, branch, text);
    }
    _commitMsgCtrl.removeListener(_onComposerChangedForDream);
    _commitDream.removeListener(_onCommitDreamChanged);
    _prefsSub?.removeListener(_onPreferencesChanged);
    _prefsSub = null;
    _commitDream.dispose();
    _commitMsgCtrl.dispose();
    _commitMsgFocusNode.dispose();
    _shapeCtrl.dispose();
    _shapeFocus.dispose();
    _changesListCtrl.dispose();
    super.dispose();
  }

  /// Returns the AI categories the user has configured at least one
  /// model for. Used to drive the chevron-cycle on the shape ask
  /// button. Order is stable (insertion order from the prefs map).
  List<String> _shapeCategories(AiSettingsState ai) =>
      ai.modelSelections.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => e.key)
          .toList(growable: false);

  /// Fire the ask and lift the result into the side panel. The
  /// takeover happens synchronously (drawer flipped to ask) before
  /// `_runShape` awaits anything, so the user sees a loading pane
  /// instead of a silent pause while the model is contacted.
  void _askInPanel(
    String repoPath,
    RepositoryStatus status,
    String sentence,
    String categoryId,
  ) {
    setState(() => _openDrawer = AiActivityKind.ask);
    unawaited(_runShape(repoPath, status, sentence, categoryId));
  }

  /// Toggle the composer's shape-mode: flips between binding the
  /// commit draft controller and the ask-question controller. Exiting
  /// also closes any active result panel — clicking ◈ is the single
  /// gesture that walks away from the conversation entirely.
  void _toggleShapeMode() {
    setState(() {
      _shapeMode = !_shapeMode;
      if (!_shapeMode && _openDrawer == AiActivityKind.ask) {
        _openDrawer = null;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_shapeMode ? _shapeFocus : _commitMsgFocusNode).requestFocus();
    });
  }

  /// Context-identity key. Previously this hashed the full file
  /// manifest (path + staged/unstaged flags), which meant every file
  /// save, every `git add`, every desk churn inside the same branch
  /// caused [_syncDraftFromStatus] to wipe the user's selection and
  /// blow away AI review state — the "feels like a full page refresh"
  /// on every interaction. Narrow it to the things that actually
  /// define a different working context: branch and upstream. Matches
  /// the history page's `_lastRepo` gating pattern.
  String _buildDraftKey(RepositoryStatus status) =>
      '${status.branch}|${status.upstream}';

  void _syncDraftFromStatus(RepositoryStatus status) {
    final nextKey = _buildDraftKey(status);
    if (_draftKey == nextKey) {
      // Same branch/upstream, manifest churned (user saved, staged,
      // stashed something). Reconcile the selection rather than
      // resetting it — preserve everything the user touched.
      _reconcileIncludedPaths(status);
      return;
    }
    // Stash the outgoing context's selection before switching so we
    // can restore it on return. First entry into the page has no
    // outgoing key — skip the stash.
    if (_draftKey != null) {
      _includedByContextKey[_draftKey!] = Set<String>.from(_includedPaths);
    }
    _draftKey = nextKey;
    final restored = _includedByContextKey[nextKey];
    if (restored != null) {
      // Return trip to a previously-visited context — restore the
      // user's exact selection, then prune anything that's since been
      // resolved (committed, reverted, deleted).
      _includedPaths
        ..clear()
        ..addAll(restored);
      // Seed the seen-set for this context if we haven't observed it
      // this session. Without this, auto-select-new-changes would see
      // every currently-present file as "new" on the first reconcile
      // after a return trip and sweep them all into the selection.
      _seenByContextKey.putIfAbsent(
        nextKey,
        () => {for (final f in status.files) f.path},
      );
      _reconcileIncludedPaths(status);
    } else {
      // First arrival in this context: seed with the staged set if
      // anything is staged, otherwise all dirty files. Matches the
      // historical default — only kicks in on truly new contexts.
      final staged = status.files
          .where((file) => file.hasStagedChange)
          .map((file) => file.path)
          .toSet();
      _includedPaths
        ..clear()
        ..addAll(staged.isNotEmpty ? staged : status.files.map((f) => f.path));
      _seenByContextKey[nextKey] = {for (final f in status.files) f.path};
    }
    // Branch / commit-context switch — close any drawers from the
    // prior context. Records persist in AiActivityState so a same-
    // scope visit later still finds the result; surface UI state
    // (which drawer's open, expander state, transient flash) is
    // per-context and resets here. Flash reset matches the repo-
    // switch handler — see _resetSelectionScopeState for the bleed
    // rationale.
    _openDrawer = null;
    _reviewTraceExpanded = false;
    _reviewReasoningExpanded = false;
    _generateFlash = false;
    _reviewFlash = false;
    _museFlash = false;
  }

  /// Recompute per-file dim opacity from the Logos engine's integrity
  /// + volatility signals. Files whose integrity is below the
  /// changeset's adaptive threshold dim; the rest stay vivid.
  ///
  /// The threshold is the changeset's own median integrity, so a repo
  /// full of generated files doesn't dim everything — the dimming is
  /// always relative to what's in front of the user right now.
  /// Derive per-file attention weight from three Logos axes, then map
  /// the bottom half of the distribution to reduced opacity.
  ///
  /// Axes (each normalised to [0, 1] within the current changeset):
  ///
  ///  1. **Surprise** — inverse of historical volatility. A lockfile
  ///     that changes every commit scores 0; a rarely-touched config
  ///     that suddenly appears scores 1. "Is this change unusual?"
  ///
  ///  2. **Centrality** — mean coupling to the other files in the same
  ///     changeset. A tightly-coupled peer scores high; an incidental
  ///     bystander scores 0. "Does this file belong with the others?"
  ///
  ///  3. **Integrity** — Logos' semantic transmissibility score. Filters
  ///     generated code, lockfiles, vendor noise. "Is this a real
  ///     source file?"
  ///
  /// Centrality dominates because it's the one axis that's context-
  /// sensitive to *this* changeset rather than to the file's history.
  void _recomputeFileDimOpacity(
    RepositoryStatus status,
    LogosGit? engine,
    FileCouplingMatrix? coupling,
  ) {
    if (engine == null || status.files.length < 3) {
      _fileDimOpacity = const {};
      return;
    }
    final stats = engine.stats;
    final paths = status.files.map((f) => f.path).toList();

    // ── Axis 1: Surprise ──────────────────────────────────────────
    // Normalise volatility within the changeset so the score is
    // relative to what's on screen, not to the whole repo.
    double volMax = 0;
    final volRaw = <double>[];
    for (final p in paths) {
      final v = stats.volatility[p] ?? 0.0;
      volRaw.add(v);
      if (v > volMax) volMax = v;
    }
    final surprise = <String, double>{};
    for (var i = 0; i < paths.length; i++) {
      surprise[paths[i]] = volMax > 0 ? 1.0 - volRaw[i] / volMax : 1.0;
    }

    // ── Axis 2: Centrality ────────────────────────────────────────
    // Mean pairwise coupling to every other changed file. Falls back
    // to 0.5 (neutral) when the matrix isn't ready.
    final centrality = <String, double>{};
    if (coupling != null && paths.length > 1) {
      for (final p in paths) {
        double sum = 0;
        for (final q in paths) {
          if (q == p) continue;
          sum += combinedCouplingScore(p, q, coupling);
        }
        centrality[p] = sum / (paths.length - 1);
      }
    }

    // ── Axis 3: Integrity ─────────────────────────────────────────
    final integrity = stats.integrityByPath;

    // ── Blend ─────────────────────────────────────────────────────
    final weights = <String, double>{};
    for (final p in paths) {
      final s = surprise[p] ?? 1.0;
      final c = centrality[p] ?? 0.5;
      final g = integrity[p] ?? 0.85;
      weights[p] = c * 0.45 + s * 0.35 + g * 0.20;
    }

    // Adaptive threshold from the changeset's own distribution.
    final sorted = weights.values.toList()..sort();
    if (sorted.last - sorted.first < 0.04) {
      _fileDimOpacity = const {};
      return;
    }
    final median = sorted[sorted.length ~/ 2];

    final result = <String, double>{};
    for (final e in weights.entries) {
      if (e.value < median) {
        final t =
            ((median - e.value) / median.clamp(0.01, 1.0)).clamp(0.0, 1.0);
        result[e.key] = 1.0 - 0.45 * t;
      }
    }
    _fileDimOpacity = result;
  }

  double _fileDimFor(String path) => _fileDimOpacity[path] ?? 1.0;

  /// Reconcile [_includedPaths] against [status].
  ///
  /// Subtractive pass is always run: paths no longer present are
  /// dropped. Additive pass only runs when the
  /// `autoSelectNewChanges` pref is on, and only adds paths that
  /// weren't in the per-context seen set — so files the user
  /// explicitly deselected stay deselected. The seen set is updated
  /// at the end regardless of the pref, so toggling the pref mid-
  /// session behaves as if it'd always been at its new value.
  void _reconcileIncludedPaths(RepositoryStatus status) {
    final current = <String>{for (final f in status.files) f.path};
    if (_includedPaths.isNotEmpty) {
      _includedPaths.removeWhere((p) => !current.contains(p));
    }
    final key = _draftKey;
    if (key == null) return;
    final autoOn = context.read<PreferencesState>().autoSelectNewChanges;
    if (autoOn) {
      final seen = _seenByContextKey[key] ?? const <String>{};
      for (final p in current) {
        if (!seen.contains(p)) _includedPaths.add(p);
      }
    }
    _seenByContextKey[key] = current;
  }

  void _hideReviewPane() {
    if (_openDrawer == AiActivityKind.review) {
      setState(() => _openDrawer = null);
    }
  }

  /// User-driven cancel of the active review run on this repo. Drops
  /// the provider record and resets the drawer.
  void _cancelReviewRequest() {
    final site = _activitySite();
    if (site != null) {
      site.state.clear(repoPath: site.repoPath, kind: AiActivityKind.review);
    }
    _closeAndResetReviewDrawer();
  }

  int _includedDirtyCount(RepositoryStatus status) {
    return status.files
        .where((file) => _includedPaths.contains(file.path))
        .length;
  }

  List<String> _stagedExcludedPaths(RepositoryStatus status) {
    return status.files
        .where(
          (file) => !_includedPaths.contains(file.path) && file.hasStagedChange,
        )
        .map((file) => file.path)
        .toList();
  }

  _PrimaryCommitAction _primaryActionFor(RepositoryStatus status) {
    final branch = status.branch;
    if (branch == 'HEAD' || branch.startsWith('(')) {
      return const _PrimaryCommitAction(
        label: 'Commit changes',
        detail: 'Detached HEAD: commit locally without syncing.',
        syncAfterCommit: false,
      );
    }
    if (status.upstream == null) {
      return const _PrimaryCommitAction(
        label: 'Commit & publish',
        detail: 'Create the commit and publish this branch in one step.',
        syncAfterCommit: true,
      );
    }
    if (status.ahead > 0 || status.behind > 0) {
      return const _PrimaryCommitAction(
        label: 'Commit & sync',
        detail: 'Create the commit, then reconcile and ship the branch.',
        syncAfterCommit: true,
      );
    }
    return const _PrimaryCommitAction(
      label: 'Commit & push',
      detail: 'Create the commit and push it immediately.',
      syncAfterCommit: true,
    );
  }

  Future<void> _loadDiff(String repo, String path) async {
    final stopwatch = Stopwatch()..start();
    final cachedDocument = _cachedSingleDiffDocument(path);
    if (cachedDocument != null) {
      setState(() {
        _hideReviewPane();
        _selectedDiffPath = path;
        _visibleDiffPath = path;
        _diffLoading = false;
        _diffError = null;
        _diffDocument = cachedDocument;
      });
      await _recordUiTimingSample(
        event: 'changes.diff.cache-hit',
        stopwatch: stopwatch,
        phase: 'interaction',
        minMs: 0,
      );
      await DiagnosticsState.instance.recordUiTiming(
        event: 'changes.diff.load',
        phase: 'interaction',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        ok: true,
      );
      return;
    }
    setState(() {
      _hideReviewPane();
      _selectedDiffPath = path;
      _diffLoading = true;
      _diffError = null;
    });
    // Four-stage diff fetch so clicking a related file surfaced by
    // the Logos engine always lands on real content. Blank panes are
    // never a useful answer — we'd rather show the file's history or
    // its current content than tell the user "nothing here."
    //   1. unstaged working-tree changes
    //   2. staged index changes (file might be fully staged)
    //   3. last committed change (history handles renames)
    //   4. synthesize a new-file diff from the file on disk (handles
    //      untracked / newly-added / gitignored files that the engine
    //      still knows about)
    final fetchStopwatch = Stopwatch()..start();
    var r = await getFileDiff(repo, path);
    if (!mounted || _selectedDiffPath != path) {
      return;
    }
    if (r.ok && (r.data ?? '').isEmpty) {
      final staged = await getFileDiff(repo, path, staged: true);
      if (!mounted || _selectedDiffPath != path) {
        return;
      }
      if (staged.ok && (staged.data ?? '').isNotEmpty) {
        r = staged;
      } else {
        // Last committed change for this file, handling renames via
        // pathAtRevision. First entry of the history log is the most
        // recent commit touching the file.
        final history = await listFileHistoryWithPaths(repo, path, limit: 1);
        if (!mounted || _selectedDiffPath != path) {
          return;
        }
        if (history.ok && history.data != null && history.data!.isNotEmpty) {
          final entry = history.data!.first;
          final hist = await getFileDiffAtRevision(
            repo,
            entry.pathAtRevision,
            entry.commit.commitHash,
          );
          if (!mounted || _selectedDiffPath != path) {
            return;
          }
          if (hist.ok && (hist.data ?? '').isNotEmpty) {
            r = hist;
          }
        }
      }
    }

    // Final fallback — if no git-visible diff exists for this path,
    // read the file from disk and render it as a synthesized new-file
    // diff so the user sees something real.
    String? syntheticDiff;
    if (r.ok && (r.data ?? '').isEmpty) {
      syntheticDiff = await _readFileAsSyntheticDiff(repo, path);
      if (!mounted || _selectedDiffPath != path) {
        return;
      }
    }
    await _recordUiTimingSample(
      event: 'changes.diff.fetch',
      stopwatch: fetchStopwatch,
      phase: 'compute',
    );

    double? documentBuildMs;
    setState(() {
      _diffLoading = false;
      if (r.ok) {
        final data = syntheticDiff ?? (r.data ?? '');
        if (data.isEmpty) {
          // Truly nothing to show — path doesn't exist on disk, has
          // no history, and has no changes. Rare edge case (stale
          // engine reference, or a binary that couldn't be read).
          _visibleDiffPath = path;
          _diffDocument = null;
          _diffError = 'Nothing to show for $path.';
        } else {
          _visibleDiffPath = path;
          final buildStopwatch = Stopwatch()..start();
          final document = DiffDocument.fromRawContent(
            rawContent: data,
            pathHint: path,
            trimLeadingMeta: true,
            documentId: 'single:$path:${data.hashCode}',
          );
          buildStopwatch.stop();
          documentBuildMs = buildStopwatch.elapsedMicroseconds / 1000;
          _diffDocument = document;
          final statusFile = context
              .read<RepositoryState>()
              .status
              ?.files
              .where((file) => file.path == path)
              .firstOrNull;
          if (statusFile != null && document.files.isNotEmpty) {
            _rememberDiffFileDocument(
              _buildMultiDiffFileKey(statusFile),
              document.files.first,
            );
          }
        }
      } else {
        _diffDocument = null;
        _diffError = r.error;
      }
    });
    if (documentBuildMs != null && documentBuildMs! >= 8) {
      await DiagnosticsState.instance.recordUiTiming(
        event: 'changes.diff.document-build',
        phase: 'compute',
        durationMs: documentBuildMs!,
      );
    }
    stopwatch.stop();
    await DiagnosticsState.instance.recordUiTiming(
      event: 'changes.diff.load',
      phase: 'interaction',
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      ok: r.ok,
      errorCode: r.ok ? null : 'diff.load_failed',
    );
  }

  void _inspectSingleDiff(String repo, String path) {
    setState(() {
      _hideReviewPane();
      _inspectionDiffPath = path;
    });
    unawaited(_loadDiff(repo, path));
  }

  /// Capture the currently-visible diff path onto the nav stack, then
  /// delegate to [_inspectSingleDiff]. Wired into the drawer's
  /// related-path links so drilling deeper pushes a breadcrumb; the
  /// toolbar's `<` button then pops the stack. Dedupes against the
  /// target so navigating "to where you already were" is a no-op.
  void _pushAndInspectSingleDiff(String repo, String path) {
    final current = _visibleDiffPath ?? _selectedDiffPath;
    if (current != null && current != path) {
      _diffNavStack.add(current);
    }
    _inspectSingleDiff(repo, path);
  }

  void _navigateBackDiff(String repo) {
    if (_diffNavStack.isEmpty) return;
    final prev = _diffNavStack.removeLast();
    // _inspectSingleDiff rather than _pushAndInspectSingleDiff so the
    // pop doesn't immediately re-push and trap the user in a cycle.
    _inspectSingleDiff(repo, prev);
  }

  /// Bring the row for [path] into the file list's viewport. Called
  /// from explicit-navigation events only (rail click, tree click,
  /// related-path open, pinned-line focus). Passive diff scrolling
  /// deliberately does NOT trigger this — yanking the list while the
  /// user is passively reading would be aggressive.
  ///
  /// Uses [Scrollable.ensureVisible] when the target row is already
  /// laid out (variable row heights handled natively). Falls back to
  /// an index-× average-row-height estimate for off-screen rows so
  /// the list at least animates to the right neighborhood.
  void _ensureFileVisibleInChangesList(String path) {
    final key = _fileRowKeys[path];
    final rowCtx = key?.currentContext;
    const duration = Duration(milliseconds: 220);
    const curve = Curves.easeInOutCubic;
    if (rowCtx != null) {
      Scrollable.ensureVisible(
        rowCtx,
        alignment: 0.25,
        duration: duration,
        curve: curve,
      );
      return;
    }
    if (!_changesListCtrl.hasClients) return;
    final idx = _changesListPaths.indexOf(path);
    if (idx < 0) return;
    final pos = _changesListCtrl.position;
    final totalCount = _changesListPaths.length;
    if (totalCount == 0) return;
    // Average row height across the rendered list. Coarse but fine
    // for off-screen targets — once the scroll lands, the target
    // row builds and any subsequent ensureVisible call (e.g., from
    // a follow-up event) refines the position.
    final avgRowH = (pos.maxScrollExtent + pos.viewportDimension) / totalCount;
    final target = (idx * avgRowH - pos.viewportDimension * 0.25)
        .clamp(0.0, pos.maxScrollExtent);
    _changesListCtrl.animateTo(target, duration: duration, curve: curve);
  }

  /// Read the file from disk and synthesize a new-file unified diff
  /// so the user sees something real even when git has nothing to
  /// say about this path (untracked, gitignored, brand new). Returns
  /// null on any failure (missing, binary, too large) so callers can
  /// fall through to the rare "nothing to show" error state.
  Future<String?> _readFileAsSyntheticDiff(String repo, String path) async {
    try {
      final absPath = p.isAbsolute(path) ? path : p.join(repo, path);
      final file = File(absPath);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      // Cap at 1 MB — beyond that the diff viewer chokes and the user
      // probably doesn't want to scan a huge file as a "diff" anyway.
      if (stat.size > 1024 * 1024) return null;
      final content = await file.readAsString();
      if (content.isEmpty) return null;
      final hasTrailingNewline = content.endsWith('\n');
      final rawLines = content.split('\n');
      // split leaves an empty trailing element when the string ended
      // with \n; drop it so the hunk header's line count is accurate.
      final lines = hasTrailingNewline
          ? rawLines.sublist(0, rawLines.length - 1)
          : rawLines;
      final buf = StringBuffer()
        ..writeln('diff --git a/$path b/$path')
        ..writeln('new file mode 100644')
        ..writeln('--- /dev/null')
        ..writeln('+++ b/$path')
        ..writeln('@@ -0,0 +1,${lines.length} @@');
      for (final line in lines) {
        buf
          ..write('+')
          ..writeln(line);
      }
      if (!hasTrailingNewline) {
        buf.writeln('\\ No newline at end of file');
      }
      return buf.toString();
    } catch (_) {
      // Binary content, permission error, encoding failure — fall
      // through so the UI reaches the explicit "nothing to show"
      // state rather than crashing on a bad read.
      return null;
    }
  }

  String _buildMultiDiffScopeKey(List<RepositoryStatusFile> files) {
    return files
        .map((file) => '${file.path}|${file.stagedCode}|${file.unstagedCode}')
        .join('||');
  }

  String _buildMultiDiffFileKey(RepositoryStatusFile file) =>
      '${file.path}|${file.stagedCode}|${file.unstagedCode}';

  DiffDocument _singleDocumentFromFileDocument(
    DiffFileDocument fileDocument, {
    required String path,
  }) {
    return DiffDocument.fromFiles(
      files: [fileDocument],
      trimLeadingMeta: true,
      documentId: 'single:$path:${fileDocument.cacheKey}',
    );
  }

  DiffDocument? _cachedSingleDiffDocument(String path) {
    final multiFileDocument = _multiDiffDocument?.filesByPath[path];
    if (multiFileDocument != null) {
      return _singleDocumentFromFileDocument(
        multiFileDocument,
        path: path,
      );
    }
    final statusFile = context
        .read<RepositoryState>()
        .status
        ?.files
        .where((file) => file.path == path)
        .firstOrNull;
    if (statusFile == null) {
      return null;
    }
    final fileDocument =
        _diffFileDocumentCache[_buildMultiDiffFileKey(statusFile)];
    if (fileDocument == null) {
      return null;
    }
    return _singleDocumentFromFileDocument(
      fileDocument,
      path: path,
    );
  }

  void _rememberDiffFileDocument(String fileKey, DiffFileDocument document) {
    _diffFileDocumentCache.remove(fileKey);
    _diffFileDocumentCache[fileKey] = document;
    while (_diffFileDocumentCache.length > _kMaxFileDiffCacheEntries) {
      _diffFileDocumentCache.remove(_diffFileDocumentCache.keys.first);
    }
  }

  DiffDocument _documentFromFiles(
    List<RepositoryStatusFile> files, {
    required String scopeKey,
  }) {
    final documents = <DiffFileDocument>[];
    for (final file in files) {
      final fileKey = _buildMultiDiffFileKey(file);
      final document = _diffFileDocumentCache[fileKey];
      if (document != null) {
        documents.add(document);
      }
    }
    return DiffDocument.fromFiles(
      files: documents,
      trimLeadingMeta: false,
      documentId: 'multi:$scopeKey',
    );
  }

  void _rememberMultiDiff(_CachedMultiDiff entry) {
    _multiDiffCache.remove(entry.scopeKey);
    _multiDiffCache[entry.scopeKey] = entry;
    while (_multiDiffCache.length > _kMaxMultiDiffCacheEntries) {
      _multiDiffCache.remove(_multiDiffCache.keys.first);
    }
  }

  _CachedMultiDiff _cacheMultiDiffSnapshot(
    String scopeKey,
    List<RepositoryStatusFile> files,
    String content,
  ) {
    final diffByPath = sliceDiffByFile(content);
    for (final file in files) {
      final section = diffByPath[file.path];
      if (section == null) {
        continue;
      }
      final fileKey = _buildMultiDiffFileKey(file);
      _rememberDiffFileDocument(
        fileKey,
        DiffFileDocument.fromRawContent(
          rawContent: section,
          pathHint: file.path,
          cacheKey: fileKey,
        ),
      );
    }
    final document = _documentFromFiles(files, scopeKey: scopeKey);
    final entry = _CachedMultiDiff(
      scopeKey: scopeKey,
      document: document,
      fileKeyByPath: {
        for (final file in files) file.path: _buildMultiDiffFileKey(file),
      },
    );
    _rememberMultiDiff(entry);
    return entry;
  }

  _CachedMultiDiff? _cachedMultiDiffFor(
    List<RepositoryStatusFile> files, {
    String? scopeKey,
  }) {
    if (files.isEmpty) {
      return const _CachedMultiDiff(
        scopeKey: '',
        document: null,
        fileKeyByPath: <String, String>{},
      );
    }
    final resolvedScopeKey = scopeKey ?? _buildMultiDiffScopeKey(files);
    final exact = _multiDiffCache[resolvedScopeKey];
    if (exact != null) {
      _rememberMultiDiff(exact);
      return exact;
    }

    for (final candidate in _multiDiffCache.values.toList().reversed) {
      var coversAllFiles = true;
      for (final file in files) {
        final fileKey = _buildMultiDiffFileKey(file);
        if (candidate.fileKeyByPath[file.path] != fileKey) {
          coversAllFiles = false;
          break;
        }
      }
      if (!coversAllFiles) {
        continue;
      }

      for (final file in files) {
        final cachedDoc = candidate.document?.filesByPath[file.path];
        if (cachedDoc != null) {
          _rememberDiffFileDocument(_buildMultiDiffFileKey(file), cachedDoc);
          continue;
        }
        if (!_diffFileDocumentCache.containsKey(_buildMultiDiffFileKey(file))) {
          coversAllFiles = false;
          break;
        }
      }
      if (!coversAllFiles) {
        continue;
      }
      final derived = _CachedMultiDiff(
        scopeKey: resolvedScopeKey,
        document: _documentFromFiles(files, scopeKey: resolvedScopeKey),
        fileKeyByPath: {
          for (final file in files) file.path: _buildMultiDiffFileKey(file),
        },
      );
      _rememberMultiDiff(derived);
      return derived;
    }
    return null;
  }

  void _applyMultiDiffSnapshot(
    _CachedMultiDiff snapshot,
    List<RepositoryStatusFile> requestFiles,
  ) {
    final document = snapshot.document;
    final sections = document?.sections
            .map((section) => _CombinedDiffSection(
                  path: section.path,
                  displayName: section.displayName,
                  index: section.index,
                  startLine: section.startLine,
                ))
            .toList(growable: false) ??
        const <_CombinedDiffSection>[];
    final currentPath = _multiDiffCurrentPath;
    final hasCurrent = currentPath != null &&
        requestFiles.any((file) => file.path == currentPath);
    final nextPath = hasCurrent
        ? currentPath
        : (sections.isNotEmpty
            ? sections.first.path
            : (requestFiles.isEmpty ? null : requestFiles.first.path));
    final nextJumpLine = nextPath == null
        ? null
        : _currentTimelineSectionForPath(sections, nextPath)?.startLine;
    setState(() {
      _multiDiffScopeKey = snapshot.scopeKey;
      _multiDiffLoading = false;
      _multiDiffError = null;
      _multiDiffDocument = document;
      _multiDiffSections = sections;
      _multiDiffCurrentPath = nextPath;
      _multiDiffJumpLineIndex = nextJumpLine ?? 0;
      _multiDiffJumpRequestId++;
    });
  }

  Future<void> _loadMultiDiff(
    String repo,
    List<RepositoryStatusFile> files,
  ) async {
    final stopwatch = Stopwatch()..start();
    final requestFiles = List<RepositoryStatusFile>.from(files);
    final scopeKey = _buildMultiDiffScopeKey(requestFiles);
    final cached = _cachedMultiDiffFor(requestFiles, scopeKey: scopeKey);
    if (cached != null) {
      _applyMultiDiffSnapshot(cached, requestFiles);
      await _recordUiTimingSample(
        event: 'changes.multi-diff.cache-hit',
        stopwatch: stopwatch,
        phase: 'interaction',
        minMs: 0,
      );
      return;
    }
    setState(() {
      _multiDiffScopeKey = scopeKey;
      _multiDiffLoading = true;
      _multiDiffError = null;
      final currentPath = _multiDiffCurrentPath;
      _multiDiffCurrentPath = currentPath != null &&
              requestFiles.any((file) => file.path == currentPath)
          ? currentPath
          : (requestFiles.isEmpty ? null : requestFiles.first.path);
    });

    final result = await getSelectionDiff(repo, requestFiles);
    if (!mounted || _multiDiffScopeKey != scopeKey) {
      return;
    }

    setState(() {
      _multiDiffLoading = false;
      if (result.ok) {
        final snapshot =
            _cacheMultiDiffSnapshot(scopeKey, requestFiles, result.data ?? '');
        final currentPath = _multiDiffCurrentPath;
        final hasCurrent = currentPath != null &&
            requestFiles.any((file) => file.path == currentPath);
        final nextPath = hasCurrent
            ? currentPath
            : (snapshot.sections.isNotEmpty
                ? snapshot.sections.first.path
                : (requestFiles.isEmpty ? null : requestFiles.first.path));
        final nextJumpLine = nextPath == null
            ? null
            : _currentTimelineSectionForPath(snapshot.sections, nextPath)
                ?.startLine;
        _multiDiffDocument = snapshot.document;
        _multiDiffError = null;
        _multiDiffSections = snapshot.sections;
        _multiDiffCurrentPath = nextPath;
        _multiDiffJumpLineIndex = nextJumpLine ?? 0;
        _multiDiffJumpRequestId++;
      } else {
        _multiDiffDocument = null;
        _multiDiffError = result.error;
        _multiDiffSections = const [];
        _multiDiffCurrentPath = null;
        _multiDiffJumpLineIndex = null;
      }
    });
    await _recordUiTimingSample(
      event: 'changes.multi-diff.load',
      stopwatch: stopwatch,
      phase: 'interaction',
      ok: result.ok,
      errorCode: result.ok ? null : 'changes.multi-diff.load_failed',
    );
  }

  void _primeMultiDiff(
    String repo,
    List<RepositoryStatusFile> files,
  ) {
    final scopeKey = _buildMultiDiffScopeKey(files);
    if (_multiDiffLoading && _multiDiffScopeKey == scopeKey) {
      return;
    }
    if (_multiDiffScopeKey == scopeKey &&
        (_multiDiffDocument != null || _multiDiffError != null)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_loadMultiDiff(repo, files));
    });
  }

  void _handleMultiDiffScroll(ScrollMetrics metrics) {
    if (_multiDiffSections.isEmpty) {
      return;
    }
    final probeOffset = metrics.pixels + (metrics.viewportDimension * 0.2);
    final lineIndex = (probeOffset / 18).floor().clamp(0, 1 << 20);
    var current = _multiDiffSections.first;
    for (final section in _multiDiffSections) {
      if (section.startLine <= lineIndex) {
        current = section;
      } else {
        break;
      }
    }
    if (current.path == _multiDiffCurrentPath) {
      return;
    }
    setState(() {
      _multiDiffCurrentPath = current.path;
    });
  }

  void _jumpToMultiDiffPath(String path, {int? fallbackStartLine}) {
    final targetSection =
        _multiDiffSections.where((section) => section.path == path).firstOrNull;
    setState(() {
      _hideReviewPane();
      _inspectionDiffPath = null;
      _selectedDiffPath = null;
      _multiDiffCurrentPath = path;
      final jumpLine = targetSection?.startLine ?? fallbackStartLine;
      if (jumpLine != null) {
        _multiDiffJumpLineIndex = jumpLine;
        _multiDiffJumpRequestId++;
      }
    });
    // Sync the side list after the setState so layout has landed by
    // the time ensureVisible runs against a freshly-built tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureFileVisibleInChangesList(path);
    });
  }

  void _toggleIncluded(String path, bool include) {
    // File-toggle no longer force-closes the drawer. The record's
    // scopeKey check elsewhere already gates whether to surface
    // existing results; if the user wants to re-run on the new
    // selection they can hit the toolbar button. Closing wholesale
    // here was the cause of "I had a result open, toggled one file,
    // it disappeared" — surprising and unwanted.
    setState(() {
      if (include) {
        _includedPaths.add(path);
      } else {
        _includedPaths.remove(path);
      }
      _actionError = null;
    });
  }

  /// Batch include/exclude every path in [paths]. When [include] is null,
  /// toggles based on whether the group is already fully included: if any
  /// member is unincluded → include all; otherwise exclude all. Single
  /// setState so the animation plays once, not N times.
  void _toggleGroup(Iterable<String> paths, {bool? include}) {
    final list = paths.toList();
    if (list.isEmpty) return;
    final target = include ?? !list.every(_includedPaths.contains);
    setState(() {
      if (target) {
        _includedPaths.addAll(list);
      } else {
        _includedPaths.removeAll(list);
      }
      _actionError = null;
    });
  }

  /// Show the per-file right-click menu, anchored at [globalPos]. Four
  /// sections: discard, ignore, copy, reveal. Click outside or
  /// right-click elsewhere to dismiss.
  void _showFileContextMenu(
    BuildContext context,
    Offset globalPos,
    RepositoryStatusFile file,
    String repoPath,
  ) {
    final isUntracked = file.isUntracked;
    final ext = _fileExtension(file.path);
    // Name the exact file in the label so the user can't misread
    // "Discard changes…" as "discard everything". Basename only —
    // deep paths would wrap/ellipsis ugly in a menu row; the full
    // path is in the confirm dialog's body for disambiguation.
    final basename = p.basename(file.path);
    // Multi-select bridge: `_includedPaths` IS the user's selection
    // (the checkboxes next to each file). If the right-clicked file is
    // part of that selection AND more than one is selected, the menu
    // acts on the full set — with a "+N selected" suffix so the user
    // sees at a glance how much they're about to nuke. Right-clicking
    // a file OUTSIDE the selection preserves the single-file path —
    // matches the common OS convention (selection doesn't "capture"
    // an unrelated right-click).
    final inSelection = _includedPaths.contains(file.path);
    final multi = inSelection && _includedPaths.length > 1;
    final status = context.read<RepositoryState>().status;
    final selectedFiles = multi && status != null
        ? status.files.where((f) => _includedPaths.contains(f.path)).toList()
        : const <RepositoryStatusFile>[];
    final othersCount = multi ? selectedFiles.length - 1 : 0;
    final t = context.tokens;

    // Logos section. Two items, each earning its place:
    //
    //   • "Include likely co-changes" (+N) — the actionable verb
    //     when the engine's coupling × semantic intersection with
    //     the currently-modified set is non-empty. One click adds
    //     the files the engine predicts you're about to forget.
    //
    //   • Top-3 historical companions — always present when the
    //     file has known coupling partners. Each is a nav item
    //     that jumps the diff view to that file. Lets the user
    //     answer "what does touching this file usually entail?"
    //     without leaving the current pane.
    final changedPathSet =
        status == null ? <String>{} : status.files.map((f) => f.path).toSet();
    final likely = _likelyCoChangesFor(
      context,
      repoPath,
      file.path,
      changedPathSet,
      _includedPaths,
    );
    final engine = context.read<LogosGitState>().engineFor(repoPath);
    final rippleItems = engine == null
        ? const <AppContextMenuItem>[]
        : _buildRippleSubmenu(engine, repoPath, file.path);
    final rhythmCommitIndices =
        engine?.stats.perFileCommitIndices[file.path] ?? const <int>[];
    final rhythmTotalCommits = engine?.stats.totalCommits ?? 0;
    final hasRhythm = rhythmTotalCommits > 0 && rhythmCommitIndices.isNotEmpty;

    // Mutable set the submenu mutates on each checkbox toggle; the
    // parent row's click reads this at action time so the "Include"
    // verb commits exactly what's currently checked. Starts as all
    // of `likely` checked (default-in).
    final checkedLikely = Set<String>.from(likely);

    final logosSection = <AppContextMenuItem>[
      if (likely.isNotEmpty)
        AppContextMenuItem(
          icon: Icons.hub_outlined,
          label: 'Include likely co-changes',
          onTap: () {
            if (checkedLikely.isEmpty) return;
            setState(() {
              _includedPaths.addAll(checkedLikely);
            });
          },
          submenuBuilder: () => [
            for (final path in likely)
              AppContextMenuItem(
                icon: Icons.check_box_outline_blank, // fallback; unused
                leading: AppCheckbox(
                  value: checkedLikely.contains(path),
                  // onChanged fires independently of the row's tap
                  // handler — either surface (clicking the box or
                  // clicking the row) flips the checkmark.
                  onChanged: (v) {
                    if (v) {
                      checkedLikely.add(path);
                    } else {
                      checkedLikely.remove(path);
                    }
                  },
                ),
                label: p.basename(path),
                keepOpen: true,
                onTap: () {
                  if (checkedLikely.contains(path)) {
                    checkedLikely.remove(path);
                  } else {
                    checkedLikely.add(path);
                  }
                },
              ),
          ],
        ),
      // Ripple — hover opens a cascading submenu with the top 5
      // files the engine's heat-kernel diffusion predicts will need
      // attention downstream of this file. Instant computation from
      // the in-memory engine, so the submenu builder runs cheaply
      // on first hover with no spinner needed. Each submenu entry
      // carries a φ-weighted bar alongside the path so the reader
      // sees relative forecast weight at a glance.
      if (rippleItems.isNotEmpty)
        AppContextMenuItem(
          icon: Icons.waves_outlined,
          label: 'Ripple',
          onTap: () {}, // hover-only; submenu drives the action
          submenuBuilder: () => rippleItems,
        ),
      // Rhythm — inline sparkline derived from the file's commit
      // touch pattern over the engine's analysed window. Silent,
      // non-interactive; the row IS the information. Answers "is
      // this file warm or cold right now?" at a glance.
      if (hasRhythm)
        AppContextMenuItem(
          icon: Icons.graphic_eq_outlined,
          label: 'Rhythm',
          onTap: () {},
          inert: true,
          trailing: _RhythmSpark(
            commitIndices: rhythmCommitIndices,
            totalCommits: rhythmTotalCommits,
            tokens: t,
          ),
        ),
    ];

    // LogosField glyph strip — the engine's visual read of this file.
    // Silent (hidden hairline) when the engine has nothing interesting
    // to say; otherwise a tangle bar + finding / proposal glyphs.
    final fileStatus = _fileStatus(engine, file.path);
    final glyphStrip = <AppContextMenuItem>[
      AppContextMenuItem(
        icon: Icons.circle, // ignored — custom widget takes over
        label: '',
        onTap: () {},
        inert: true,
        custom: LogosGlyphStrip(tokens: t, status: fileStatus),
      ),
    ];

    final sections = <MenuSection>[
      if (!fileStatus.isSilent) ListMenuSection(glyphStrip),
      if (logosSection.isNotEmpty) ListMenuSection(logosSection),
      ListMenuSection([
        AppContextMenuItem(
          icon: isUntracked ? Icons.delete_outline : Icons.history_outlined,
          label: multi
              ? (isUntracked
                  ? 'Delete $basename  +$othersCount selected…'
                  : 'Discard changes to $basename  +$othersCount selected…')
              : (isUntracked
                  ? 'Delete $basename…'
                  : 'Discard changes to $basename…'),
          destructive: true,
          onTap: multi
              ? () => _confirmDiscardFiles(context, selectedFiles, repoPath)
              : () => _confirmDiscardFile(context, file, repoPath),
        ),
      ]),
      ListMenuSection([
        AppContextMenuItem(
          icon: Icons.block_outlined,
          label: 'Ignore file (add to .gitignore)',
          onTap: () => _ignorePattern(context, repoPath, file.path),
        ),
        if (ext != null)
          AppContextMenuItem(
            icon: Icons.block_outlined,
            label: 'Ignore all .$ext files (add to .gitignore)',
            onTap: () => _ignorePattern(context, repoPath, '*.$ext'),
          ),
      ]),
      ListMenuSection([
        AppContextMenuItem(
          icon: Icons.content_copy_outlined,
          label: 'Copy file path',
          onTap: () => _copyToClipboard(file.path),
        ),
      ]),
      ListMenuSection([
        AppContextMenuItem(
          icon: Icons.folder_open_outlined,
          label: 'Show in Explorer',
          onTap: () => _revealInExplorer(repoPath, file.path),
        ),
      ]),
    ];
    showAppContextMenu(context, globalPos, sections);
  }

  /// Compute the set of files that historically co-change with
  /// [filePath] AND are present in the current diff's changed-file
  /// set AND aren't already in the user's selection. Blends two
  /// signals the engine uniquely provides:
  ///   • Coupling (historical): jaccard entries from the matrix.
  ///     Files that keep being touched alongside this one across
  ///     commit history.
  ///   • Semantic (content): K-space nearest files from engram.
  ///     Files whose content lives near this one in Alexandria's
  ///     well-space.
  /// A union of the two, thresholded so only real signal comes
  /// through. The intersection with currently-changed files is
  /// what makes this useful as a selection-extension action: if
  /// you're staging `auth.dart` and the engine knows `auth_test.dart`
  /// co-changes 82% of the time AND it's sitting modified in your
  /// working tree, you probably forgot to stage it.
  Set<String> _likelyCoChangesFor(
    BuildContext ctx,
    String repoPath,
    String filePath,
    Set<String> changedPaths,
    Set<String> alreadyIncluded,
  ) {
    final engine = ctx.read<LogosGitState>().engineFor(repoPath);
    final matrix = ctx.read<FileCouplingState>().matrixFor(repoPath);
    if (engine == null && matrix == null) return const {};

    final out = <String>{};

    if (matrix != null && matrix.containsPath(filePath)) {
      // Coupling threshold: low enough to catch real partners on
      // small/young repos where 0.25 is hard to reach, high enough
      // that a file co-changed twice won't look like a pattern.
      // `topJaccardNeighbours` walks both triangles of the CSR, so
      // lex-late paths (e.g. `zz.dart`) see their partners the same
      // way lex-early paths do — which raw `jaccardEntriesOf` missed.
      for (final e in matrix.topJaccardNeighbours(filePath, minScore: 0.15)) {
        if (!changedPaths.contains(e.key)) continue;
        if (alreadyIncluded.contains(e.key)) continue;
        out.add(e.key);
      }
    }

    if (engine != null) {
      // Semantic threshold is tighter than the panel's lookup
      // because we're making a suggestion the user can one-click
      // accept — false positives cost them an unwanted checkbox.
      // `nearestKFilesForPath` reads the path's own K-vector row
      // and runs KNN over the engram table — one call instead of
      // the row-layout unpack that used to live here.
      final near = nearestKFilesForPath(
        engine.perFileKVectors,
        filePath,
        topK: 12,
        minSimilarity: 0.55,
      );
      for (final n in near) {
        if (!changedPaths.contains(n.path)) continue;
        if (alreadyIncluded.contains(n.path)) continue;
        out.add(n.path);
      }
    }

    return out;
  }

  /// Build the submenu items for "Ripple" — runs the engine's heat
  /// kernel from `filePath` with weight 1.0 and surfaces the top-5
  /// neighbour files the diffusion predicts will want attention when
  /// this change lands. Each row carries the neighbour's φ as an
  /// inline bar so the submenu itself visualises the weight
  /// distribution — the strongest predictions read largest.
  List<AppContextMenuItem> _buildRippleSubmenu(
    LogosGit engine,
    String repoPath,
    String filePath,
  ) {
    if (!engine.pathToId.containsKey(filePath)) return const [];
    final scores = _cachedRippleDiffuse(engine, filePath);
    if (scores.isEmpty) return const [];
    // Skip self; first entry after sorting is typically the source.
    final filtered = scores.where((s) => s.path != filePath).toList()
      ..sort((a, b) => b.phi.compareTo(a.phi));
    final top = filtered.take(5).toList();
    if (top.isEmpty) return const [];
    final maxPhi = top.first.phi.clamp(0.0001, double.infinity);
    final tokens = context.tokens;
    return [
      for (final s in top)
        AppContextMenuItem(
          icon: Icons.chevron_right,
          label: p.basename(s.path),
          // `_inspectSingleDiff` hides the review pane + clears
          // multi-diff state before loading — plain `_loadDiff`
          // would silently fill state that the multi-diff mode
          // ignores, making the click feel like a no-op.
          onTap: () => _inspectSingleDiff(repoPath, s.path),
          trailing: _PhiBar(
            relative: (s.phi / maxPhi).clamp(0.0, 1.0),
            tokens: tokens,
          ),
        ),
    ];
  }

  /// Top-N historical companions for [filePath] from the coupling
  /// File extension *without* the leading dot, or null when the path
  /// has none (e.g. `Makefile`, `.env`). Used to decide whether the
  /// "Ignore all .ext files" row is meaningful.
  String? _fileExtension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return null;
    return name.substring(i + 1);
  }

  /// Append [pattern] to the repo's `.gitignore` then refresh the
  /// changes list (an untracked file matched by the pattern will
  /// disappear immediately). Errors surface via [_actionError].
  Future<void> _ignorePattern(
    BuildContext context,
    String repoPath,
    String pattern,
  ) async {
    final repoState = context.read<RepositoryState>();
    final result = await addToGitignore(repoPath, pattern);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _actionError = result.error ?? 'Failed to update .gitignore.';
      });
      return;
    }
    await repoState.refreshStatus();
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _revealInExplorer(String repoPath, String relPath) async {
    final absPath = '$repoPath${Platform.pathSeparator}'
        '${relPath.replaceAll('/', Platform.pathSeparator)}';
    try {
      await revealInFileManager(absPath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionError = 'Failed to open file explorer: $e';
      });
    }
  }

  /// Centred confirm dialog before invoking [discardFile]. Two
  /// outcomes: cancel (no-op) or confirm (runs the git op + refreshes
  /// the status panel; surfaces errors via [_actionError]).
  Future<void> _confirmDiscardFile(
    BuildContext context,
    RepositoryStatusFile file,
    String repoPath,
  ) async {
    // Capture everything from context before any await so we
    // don't have to revisit `context` after async gaps.
    final repoState = context.read<RepositoryState>();
    final coord = context.read<UndoCoordinator>();
    final windowSec =
        context.read<PreferencesState>().undoWindowFor(UndoActionKind.discard);
    final isUntracked = file.isUntracked;
    final basename = p.basename(file.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = ctx.tokens;
        return AlertDialog(
          backgroundColor: t.surface1,
          title: Text(
            isUntracked ? 'Delete $basename?' : 'Discard changes to $basename?',
            style: TextStyle(color: t.textStrong, fontSize: 14),
          ),
          content: Text(
            isUntracked
                ? '${file.path} will be removed from disk. '
                    'This cannot be undone from inside the app.'
                : 'All changes to ${file.path} will be reverted to '
                    'their state in HEAD. This cannot be undone.',
            style: TextStyle(color: t.textNormal, fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: t.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                isUntracked ? 'Delete' : 'Discard',
                style: TextStyle(color: t.stateDeleted),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;
    // Route the discard through the undo coordinator. During the
    // undo window the file is NOT touched — its bytes are only reset
    // by `discardFile` after the timer fires. If the user cancels,
    // nothing happens at all, so we no longer need to capture bytes
    // for a bytes-replay restore. Cleaner, safer, and symmetric with
    // every other destructive action in the app.
    await coord.schedule<void>(
      kind: UndoActionKind.discard,
      label: isUntracked ? 'Deleting $basename' : 'Discarding $basename',
      window: Duration(seconds: windowSec),
      run: () async {
        final result = await discardFile(repoPath, file);
        if (!mounted) return;
        if (!result.ok) {
          setState(() {
            _actionError = result.error ?? 'Failed to discard changes.';
          });
          return;
        }
        setState(() {
          _includedPaths.remove(file.path);
          _actionError = null;
        });
        await repoState.refreshStatus();
      },
    );
  }

  /// Bulk-discard sibling of [_confirmDiscardFile]. Used when the user
  /// right-clicks a file that's part of a multi-selection (via the
  /// include-checkbox set). One confirm dialog lists every path; on
  /// confirm we loop `discardFile` per entry. No per-file undo for the
  /// multi path — a batch undo would need to snapshot every file's
  /// bytes before the op, which is a lot of I/O to hold for a snackbar
  /// window; single-file discards still get undo via their own helper.
  Future<void> _confirmDiscardFiles(
    BuildContext context,
    List<RepositoryStatusFile> files,
    String repoPath,
  ) async {
    if (files.isEmpty) return;
    final repoState = context.read<RepositoryState>();
    final coord = context.read<UndoCoordinator>();
    final windowSec =
        context.read<PreferencesState>().undoWindowFor(UndoActionKind.discard);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = ctx.tokens;
        return AlertDialog(
          backgroundColor: t.surface1,
          title: Text(
            'Discard changes to ${files.length} files?',
            style: TextStyle(color: t.textStrong, fontSize: 14),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tracked files will be reverted to their state in '
                  'HEAD; untracked files will be removed from disk. '
                  'This cannot be undone.',
                  style: TextStyle(color: t.textNormal, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final f in files)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              f.path,
                              style:
                                  TextStyle(color: t.textMuted, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: t.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Discard ${files.length}',
                style: TextStyle(color: t.stateDeleted),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;
    // Bulk discard through the coordinator — same pattern as the
    // single-file path, just one pill for the whole batch. If the
    // user cancels mid-window, nothing in the batch runs.
    await coord.schedule<void>(
      kind: UndoActionKind.discard,
      label: 'Discarding ${files.length} files',
      window: Duration(seconds: windowSec),
      run: () async {
        int failed = 0;
        String? firstErr;
        final discarded = <String>[];
        for (final f in files) {
          final r = await discardFile(repoPath, f);
          if (r.ok) {
            discarded.add(f.path);
          } else {
            failed++;
            firstErr ??= r.error;
          }
        }
        if (!mounted) return;
        setState(() {
          _includedPaths.removeAll(discarded);
          _actionError =
              failed > 0 ? (firstErr ?? 'Some discards failed.') : null;
        });
        await repoState.refreshStatus();
      },
    );
  }

  /// Drop handler: a desk dragged from the topbar strip onto this
  /// page wants to "dump" everything it has that the current branch
  /// doesn't — both ahead-of-main commits and the desk's uncommitted
  /// work — as a single patch applied to the active working tree.
  /// Routes through [showPatchPreviewDialog] so the user gets the same
  /// conflict/reconciliation surface as PR-drop-apply. Nothing touches
  /// disk until they hit Apply in the dialog.
  Future<void> _handleDeskDump(
    BuildContext ctx,
    String deskPath,
    String label,
    String repoPath,
  ) async {
    // Dropping a desk onto its own changes page is a no-op — nothing
    // to dump, and the UI would just spin. Soft-fail with a hint.
    if (p.equals(deskPath, repoPath)) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Same worktree — nothing to dump.')),
      );
      return;
    }
    // Capture context-dependent values before async gap.
    final repoState = ctx.read<RepositoryState>();
    final messenger = ScaffoldMessenger.of(ctx);
    final targetRef = repoState.status?.branch ?? 'HEAD';
    final result = await getDeskDumpDiff(deskPath, targetRef);
    if (!mounted) return;
    if (!result.ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('Diff failed: ${result.error}')),
      );
      return;
    }
    final diff = result.data ?? '';
    if (diff.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Desk has nothing ahead of you — empty dump.')),
      );
      return;
    }
    await showPatchPreviewDialog(
      context,
      repoPath: repoPath,
      rawPatch: diff,
      sourceLabel: 'desk $label',
      onApplied: () async {
        if (!mounted) return;
        await repoState.refreshStatus();
      },
    );
  }

  /// Fetch a stash's diff and route it through [showPatchPreviewDialog] —
  /// identical flow to desk dumps so the user gets the same conflict surface.
  Future<void> _handleStashDump(
    BuildContext ctx,
    int index,
    String label,
    String repoPath,
  ) async {
    // Capture context-dependent values before async gap.
    final messenger = ScaffoldMessenger.of(ctx);
    final repoState = ctx.read<RepositoryState>();
    final result = await stashShow(repoPath, index: index);
    if (!mounted) return;
    if (!result.ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('Shelf read failed: ${result.error}')),
      );
      return;
    }
    final diff = result.data ?? '';
    if (diff.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Empty shelf — nothing to dump.')),
      );
      return;
    }
    await showPatchPreviewDialog(
      context,
      repoPath: repoPath,
      rawPatch: diff,
      sourceLabel: 'shelf $label',
      onApplied: () async {
        if (!mounted) return;
        await repoState.refreshStatus();
      },
    );
  }

  void _includeAll(RepositoryStatus status) {
    setState(() {
      _includedPaths
        ..clear()
        ..addAll(status.files.map((file) => file.path));
      _actionError = null;
    });
  }

  Future<RepositoryStatus?> _refreshAndReadStatus() async {
    final repo = context.read<RepositoryState>();
    await repo.refreshStatus();
    return repo.status;
  }

  bool _hasCommitAiSelection(AiSettingsState aiSettings) {
    for (final category in _commitAiCategories) {
      if (category.models.isEmpty) {
        continue;
      }
      if (category.id == aiSettings.commitMessageModelCategoryId) {
        return true;
      }
    }
    return _commitAiCategories.any((category) => category.models.isNotEmpty);
  }

  bool _hasReviewAiSelection(AiSettingsState aiSettings) {
    for (final category in _commitAiCategories) {
      if (category.models.isEmpty) {
        continue;
      }
      if (category.id == aiSettings.reviewCommitModelCategoryId) {
        return true;
      }
    }
    return _commitAiCategories.any((category) => category.models.isNotEmpty);
  }

  String _commitAiTooltip(AiSettingsState aiSettings, int includedCount) {
    if (_generateRunning) {
      return 'Generating commit message...';
    }
    if (_commitAiLoading) {
      return 'Preparing commit-message AI...';
    }
    if (includedCount == 0) {
      return 'Select at least one file to generate a commit message.';
    }
    if (!_hasCommitAiSelection(aiSettings)) {
      return _commitAiError ??
          'Configure commit-message AI in Settings > Behavioural Dynamics > Commit Messages.';
    }
    // The second category is "Fast" — the typical default for commit gen.
    final commitLabel = aiSettings
        .labelForCategory(
          aiSettings.commitMessageModelCategoryId,
          _commitAiCategories.length > 1
              ? _commitAiCategories[1].label
              : 'fast',
        )
        .toLowerCase();
    return 'generate commit message with $commitLabel model';
  }

  String _museTooltip(AiSettingsState aiSettings, int includedCount) {
    if (_museRunning) {
      return _isMuseDrawerOpen ? 'consulting the muse...' : 'show muse';
    }
    if (includedCount == 0) return 'select at least one file for the muse.';
    if (_museResult != null) return 'show muse';
    if (_museError != null) return 'show muse error';
    // Resolve the actual slots the pipeline will use and render their
    // current display labels — if the user renamed "Fast" to "Cheapo
    // Spew", the tooltip follows. Routing keys off the tag id under the
    // hood; what we show here is the human-facing name. Fallbacks are
    // positional, not name-based, so any custom categories scale in.
    String? labelOf(String preferredId) {
      final cat = _commitAiCategories
              .where((c) => c.id == preferredId && c.models.isNotEmpty)
              .firstOrNull ??
          _commitAiCategories.where((c) => c.models.isNotEmpty).firstOrNull;
      if (cat == null) return null;
      return aiSettings.labelForCategory(cat.id, cat.label).toLowerCase();
    }

    final brainstormLabel = labelOf(aiSettings.museBrainstormModelCategoryId);
    final synthesisLabel = labelOf(aiSettings.museSynthesisModelCategoryId);
    if (brainstormLabel == null || synthesisLabel == null) {
      return 'ask the muse for direction';
    }
    return 'ask the muse for direction\n$brainstormLabel → $synthesisLabel';
  }

  String _reviewAiTooltip(
      AiSettingsState aiSettings, int includedCount, int guardrailStage) {
    final hasPersistentReview = _hasReviewStateForCurrentSelection();
    // The first category is "Quality" — the typical default for review.
    final reviewLabel = aiSettings
        .labelForCategory(
          aiSettings.reviewCommitModelCategoryId,
          _commitAiCategories.isNotEmpty
              ? _commitAiCategories.first.label
              : 'quality',
        )
        .toLowerCase();
    final guardrail = _guardrailLabelForStage(guardrailStage).toLowerCase();
    if (_reviewRunning) {
      return _isReviewDrawerOpen ? 'reviewing...' : 'show review';
    }
    if (_commitAiLoading) {
      return 'preparing commit review...';
    }
    if (includedCount == 0) {
      return 'select at least one file to review.';
    }
    if (!_hasReviewAiSelection(aiSettings)) {
      return _commitAiError ?? 'configure review AI in settings.';
    }
    if (hasPersistentReview) {
      if (_isReviewDrawerOpen) {
        final verdict = _reviewResult?.verdict;
        return verdict != null ? verdict.toLowerCase() : 'viewing review';
      }
      return 'show review';
    }
    return '$guardrail review with $reviewLabel model';
  }

  bool _hasReviewStateForCurrentSelection() {
    final scopeKey = _currentReviewScopeKey();
    if (scopeKey == null || _reviewScopeKey != scopeKey) {
      return false;
    }
    return _reviewRunning || _reviewResult != null || _reviewError != null;
  }

  /// Mirror of [_hasReviewStateForCurrentSelection] for muse — same
  /// scope-key shape (both flows scope-key off the included file
  /// set), different record. Lets the muse toolbar button stay
  /// clickable when there's an existing same-scope result waiting
  /// to be re-shown, even before the LogosGit engine has resolved
  /// (re-show doesn't need the engine; only a fresh run does).
  bool _hasMuseStateForCurrentSelection() {
    final scopeKey = _currentReviewScopeKey();
    if (scopeKey == null || _museScopeKey != scopeKey) {
      return false;
    }
    return _museRunning || _museResult != null || _museError != null;
  }

  String? _currentReviewScopeKey() {
    final repo = context.read<RepositoryState>();
    final status = repo.status;
    if (status == null) {
      return null;
    }
    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();
    if (included.isEmpty) {
      return null;
    }
    return _buildMultiDiffScopeKey(included);
  }

  void _showExistingReview() {
    if (!_hasReviewStateForCurrentSelection()) return;
    _openDrawerFor(AiActivityKind.review);
  }

  /// True when the review record exists but its scopeKey doesn't
  /// match the current file selection — i.e. the user toggled files
  /// in/out after the review landed. The drawer keeps showing the
  /// (older-scope) result; a banner inside the drawer surfaces the
  /// mismatch and offers a one-click rerun.
  bool _isReviewScopeStale() {
    final record = _reviewRecord;
    if (record == null || !record.isTerminal) return false;
    final current = _currentReviewScopeKey();
    if (current == null) return false;
    return record.scopeKey != current;
  }

  /// Mirror of [_isReviewScopeStale] for the muse drawer. Same
  /// scope-key construction since both flows feed off the same
  /// `_buildMultiDiffScopeKey` of the included file set.
  bool _isMuseScopeStale() {
    final record = _museRecord;
    if (record == null || !record.isTerminal) return false;
    final current = _currentReviewScopeKey();
    if (current == null) return false;
    return record.scopeKey != current;
  }

  String _reviewModelLabel(AiSettingsState aiSettings) {
    final selectedCategory = _commitAiCategories
            .where(
              (category) =>
                  category.id == aiSettings.reviewCommitModelCategoryId &&
                  category.models.isNotEmpty,
            )
            .firstOrNull ??
        _commitAiCategories
            .where((category) => category.models.isNotEmpty)
            .firstOrNull;
    if (selectedCategory == null) {
      return 'No model';
    }
    final selectedModel = selectedCategory.models
            .where(
              (model) =>
                  model.value ==
                  aiSettings.modelSelections[selectedCategory.id],
            )
            .firstOrNull ??
        selectedCategory.models.first;
    return '${selectedModel.providerLabel} | ${selectedModel.modelId}';
  }

  Future<void> _refreshCommitAiConfig({bool forceRefresh = false}) async {
    final aiSettings = context.read<AiSettingsState>();
    if (!forceRefresh && aiSettings.runtimeModelCategories.isNotEmpty) {
      setState(() {
        _commitAiCategories = aiSettings.runtimeModelCategories;
        _commitAiLoading = false;
        _commitAiError = aiSettings.runtimeModelCategoriesError;
      });
      return;
    }
    setState(() {
      _commitAiLoading =
          forceRefresh || aiSettings.runtimeModelCategories.isEmpty;
      _commitAiError = aiSettings.runtimeModelCategoriesError;
    });
    await aiSettings.refreshModelCategories(forceRefresh: forceRefresh);
    if (!mounted) {
      return;
    }
    setState(() {
      _commitAiLoading = false;
      if (aiSettings.runtimeModelCategories.isNotEmpty) {
        _commitAiCategories = aiSettings.runtimeModelCategories;
        _commitAiError = null;
      } else {
        _commitAiError = aiSettings.runtimeModelCategoriesError;
      }
    });
  }

  Future<List<AiModelCategoryData>?> _resolveCommitAiCategories({
    bool forceRefresh = false,
  }) async {
    final aiSettings = context.read<AiSettingsState>();
    if (!forceRefresh && aiSettings.runtimeModelCategories.isNotEmpty) {
      if (_commitAiCategories != aiSettings.runtimeModelCategories) {
        setState(() {
          _commitAiCategories = aiSettings.runtimeModelCategories;
          _commitAiError = aiSettings.runtimeModelCategoriesError;
        });
      }
      return aiSettings.runtimeModelCategories;
    }
    if (!forceRefresh &&
        _commitAiCategories.any((category) => category.models.isNotEmpty)) {
      return _commitAiCategories;
    }

    final ok =
        await aiSettings.refreshModelCategories(forceRefresh: forceRefresh);
    if (!mounted) {
      return null;
    }
    if (!ok) {
      setState(() {
        _commitAiError = aiSettings.runtimeModelCategoriesError;
      });
      return null;
    }

    setState(() {
      _commitAiCategories = aiSettings.runtimeModelCategories;
      _commitAiError = null;
    });
    return aiSettings.runtimeModelCategories;
  }

  /// Builds the merge-resolution prompt + context and invokes the AI
  /// with the chosen model category. Reads every conflicted file's
  /// current on-disk contents (markers included) so the model sees the
  /// FULL picture in one shot — resolving file A sometimes requires
  /// knowing what the resolution in file B will be (rename coherence,
  /// callsite updates). One call, one patch, verified via `apply --check`.
  /// [categoryId] picks which model slot to use ('fast' by default; the
  /// chevron lets the user override to 'quality' etc.). On success the
  /// returned patch goes straight into [showPatchPreviewDialog] — same
  /// surface as the PR lens uses for imported patches. On failure the
  /// working tree is untouched; the user sees a snackbar.
  Future<void> _resolveMergeConflicts(
    String repoPath,
    String categoryId,
  ) async {
    if (_mergeResolving) return;
    final status = context.read<RepositoryState>().status;
    if (status == null) return;
    final conflicted =
        status.files.where((f) => f.isConflicted).map((f) => f.path).toList();
    if (conflicted.isEmpty) return;

    final aiSettings = context.read<AiSettingsState>();
    final modelValue = aiSettings.modelSelections[categoryId] ?? '';
    if (modelValue.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No model configured for "${aiSettings.labelForCategory(categoryId, categoryId)}". '
              'Set one in Settings → AI.'),
        ),
      );
      return;
    }

    setState(() => _mergeResolving = true);
    try {
      final snapshots = <({String path, String content})>[];
      var skippedSensitive = 0;
      for (final p in conflicted) {
        // Hard default: never send credentials-shaped paths to a
        // provider. User still sees them as UU in the file list and
        // resolves by hand. No config, no toggle — this is a floor
        // the feature respects automatically.
        if (isSensitivePath(p)) {
          skippedSensitive++;
          continue;
        }
        try {
          final text = await File(p.startsWith('/') || p.contains(':')
                  ? p
                  : '$repoPath${Platform.pathSeparator}$p')
              .readAsString();
          snapshots.add((path: p, content: _extractConflictExcerpts(text)));
        } catch (_) {
          // Skip unreadable files; the prompt will just not include them.
        }
      }
      if (snapshots.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(skippedSensitive > 0
                  ? '$skippedSensitive sensitive file${skippedSensitive == 1 ? '' : 's'} skipped — resolve by hand.'
                  : 'Could not read any conflicted files.')),
        );
        return;
      }

      final prompt = _buildMergeResolutionPrompt(snapshots);
      // Second-pass guardrail: even if the path wasn't sensitive, the
      // contents might be (API key pasted into a normal file). Refuse
      // before the transport layer sees it.
      final secretHit = detectLikelySecretInPrompt(prompt);
      if (secretHit != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Blocked — a conflicted file looks like it contains a $secretHit. Resolve by hand.'),
          ),
        );
        return;
      }
      final r = await generatePatch(
        repositoryPath: repoPath,
        modelValue: modelValue,
        prompt: prompt,
        commandLabelPrefix: 'ai.merge_resolve',
      );
      if (!mounted) return;
      if (!r.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resolution failed: ${r.error}')),
        );
        return;
      }
      // Parse the returned patch up-front so we can reconcile against
      // the UU set the user was shown. The preview will do this too,
      // but we need the path list here to gate stagePaths correctly —
      // otherwise a partial resolution silently `git add`'s files that
      // still have markers in them. That's the #1 failure-mode flagged
      // by maintainers ("I trusted the green badge and shipped UU
      // markers").
      final resolvedLines = parseUnifiedDiff(r.data!.patch);
      final resolvedPaths = <String>{
        for (final l in resolvedLines)
          if (l.filePath != null) l.filePath!,
      };
      final expectedPaths = snapshots.map((s) => s.path).toSet();
      final intersect = expectedPaths.intersection(resolvedPaths);
      await showPatchPreviewDialog(
        context,
        repoPath: repoPath,
        rawPatch: r.data!.patch,
        sourceLabel:
            '◇ merge resolution · ${intersect.length}/${expectedPaths.length} files · ${aiSettings.labelForCategory(categoryId, categoryId)}',
        expectedPaths: expectedPaths,
        onApplied: () async {
          // Only stage the files the patch ACTUALLY touched. Any UU
          // file the AI skipped must stay UU so the user sees it on
          // the next refresh and can resolve it manually. `git add`
          // on a file with markers is the silent-drop footgun.
          if (intersect.isNotEmpty) {
            await stagePaths(repoPath, intersect.toList());
          }
          if (mounted) {
            await context.read<RepositoryState>().refreshStatus();
          }
        },
      );
    } finally {
      if (mounted) setState(() => _mergeResolving = false);
    }
  }

  /// Natural-language partial staging. Takes the user's English
  /// sentence + the full working-tree diff and asks the AI for a
  /// subset patch containing ONLY the hunks the sentence describes.
  /// That patch goes through the existing preview surface (stage
  /// mode → `git apply --cached`) so the user sees exactly what will
  /// be staged before it happens. Working tree stays untouched either
  /// way; if the AI returns garbage, `apply --check` catches it and
  /// the index is never mutated.
  Future<void> _runShape(
    String repoPath,
    RepositoryStatus status,
    String sentence,
    String categoryId,
  ) async {
    // Defense-in-depth: ask/shape is AI — skip when hidden.
    if (context.read<PreferencesState>().hideAiFeatures) return;
    if (_shaping) return;
    final trimmed = sentence.trim();
    if (trimmed.isEmpty) return;
    if (status.files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No changes to shape.')),
      );
      return;
    }

    final aiSettings = context.read<AiSettingsState>();
    final modelValue = aiSettings.modelSelections[categoryId] ?? '';
    if (modelValue.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No model configured for "${aiSettings.labelForCategory(categoryId, categoryId)}".'),
        ),
      );
      return;
    }

    final activity = context.read<AiActivityState>();
    // Use the question text as both scope key and label — the same
    // question on the same repo coalesces (existing record returns).
    activity.start(
      repoPath: repoPath,
      kind: AiActivityKind.ask,
      scopeKey: trimmed,
      scopeLabel: trimmed,
    );
    try {
      // Grab the full working-tree diff (staged + unstaged, over every
      // dirty file). The AI needs to see everything to decide what to
      // include and what to exclude.
      final diffResult = await getSelectionDiff(repoPath, status.files);
      if (!diffResult.ok) {
        activity.clear(repoPath: repoPath, kind: AiActivityKind.ask);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read diff: ${diffResult.error}')),
        );
        return;
      }
      final fullDiffRaw = (diffResult.data ?? '').trim();
      if (fullDiffRaw.isEmpty) {
        activity.clear(repoPath: repoPath, kind: AiActivityKind.ask);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to shape — diff is empty.')),
        );
        return;
      }
      // Silently drop sections for sensitive paths before the AI ever
      // sees them. If shape ends up empty after filtering, the user
      // gets a clean "only sensitive files dirty" message rather than
      // a leak. No config, no toggle.
      final fullDiff = _stripSensitivePathsFromDiff(fullDiffRaw);
      if (fullDiff.isEmpty) {
        activity.clear(repoPath: repoPath, kind: AiActivityKind.ask);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Only sensitive files are dirty — skipped, resolve by hand.')),
        );
        return;
      }

      final prompt = _buildAskPrompt(trimmed, fullDiff);
      final secretHit = detectLikelySecretInPrompt(prompt);
      if (secretHit != null) {
        activity.clear(repoPath: repoPath, kind: AiActivityKind.ask);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Blocked — dirty files look like they contain a $secretHit. Ask by hand.'),
          ),
        );
        return;
      }
      final askEffort = aiSettings.resolveEffort(categoryId, modelValue);
      final askModel = aiSettings.runtimeModelCategories
          .expand((c) => c.models)
          .where((m) => m.value == modelValue)
          .firstOrNull;
      final r = await runAsk(
        repositoryPath: repoPath,
        modelValue: modelValue,
        prompt: prompt,
        reasoningEffort: askEffort.effort,
        fastMode: askEffort.fast,
        supportsReasoning: askModel?.supportsReasoning ?? true,
        commandLabelPrefix: 'ai.ask',
      );
      if (!mounted) return;
      if (!r.ok) {
        activity.fail(
          repoPath: repoPath,
          kind: AiActivityKind.ask,
          scopeKey: trimmed,
          error: r.error ?? 'Ask failed.',
        );
        return;
      }
      // Render the answer inline under the composer. The ask-mode
      // field stays open so the user can keep asking; clearing the
      // text leaves the scaffolding but frees the field for the next
      // question. Escape or the close-chip on the answer card
      // dismisses.
      activity.complete(
        repoPath: repoPath,
        kind: AiActivityKind.ask,
        scopeKey: trimmed,
        result: AiAskResult(r.data ?? ''),
      );
      // Acknowledge immediately — the answer is rendered in-place
      // under the composer on this page, so the sidebar pill should
      // not also nag.
      activity.markSeen(repoPath: repoPath, kind: AiActivityKind.ask);
      if (mounted) setState(() => _shapeCtrl.clear());
    } catch (_) {
      // Provider record stays in 'running' on unexpected throw —
      // `cancel` clears it so the UI doesn't get stuck.
      activity.clear(repoPath: repoPath, kind: AiActivityKind.ask);
      rethrow;
    }
  }

  /// Hint shown in the ask composer — one short line that shifts
  /// character with the active guardrail. Longer instructional text
  /// (⌘↵ to send, Esc to exit) was removed; the field is in focus
  /// and the keyboard affordances are discoverable without being
  /// shouted. Tone tracks how skeptical the user has asked the
  /// model to be about itself.
  String _askHintForGuardrail(int stage) {
    switch (stage) {
      case 0:
        return 'ask whatever.';
      case 1:
        return 'what\'s on your mind?';
      case 2:
        return 'let me zoom in on it.';
      default:
        return 'i\'ll bring the receipts.';
    }
  }

  /// Ask-the-manifold prompt. Grounded prose — the model reads the
  /// user's question, the working-tree diff, and any pinned context,
  /// then answers in a few sentences. Explicitly NOT code-gen:
  /// Manifold doesn't write code, it helps users read and trust what
  /// already exists. If a fix is warranted, the answer points at
  /// what to queue (as an issue, out-of-tool) rather than scaffolding
  /// the change.
  /// Hard ceiling on the diff slice shipped to the ask backend. Codex
  /// rejects prompts over 1,048,576 chars outright with a turn/start
  /// failure; other providers also degrade badly past ~1 MiB. 900K
  /// leaves ~140K of breathing room for the system prompt, question,
  /// and XML tags.
  static const int _kAskPromptDiffBudget = 900000;

  String _buildAskPrompt(String question, String fullDiff) {
    // Clip oversized diffs at a `diff --git` boundary so the model
    // sees whole file sections, not a sliced-off hunk. Prepend a
    // visible marker so the AI knows it's looking at a slice and
    // doesn't speculate about the omitted tail.
    var clippedDiff = fullDiff;
    var truncNote = '';
    if (fullDiff.length > _kAskPromptDiffBudget) {
      final boundary =
          fullDiff.lastIndexOf('\ndiff --git', _kAskPromptDiffBudget);
      final clip = boundary > 0 ? boundary : _kAskPromptDiffBudget;
      clippedDiff = fullDiff.substring(0, clip);
      final omitted = fullDiff.length - clip;
      truncNote = '\n[diff clipped — $omitted of ${fullDiff.length} '
          'chars omitted to fit the model\'s input budget]';
    }
    final buf = StringBuffer();
    buf.writeln(
        'You are a reading assistant embedded in a git client. You help');
    buf.writeln(
        'the user understand and trust the code they are looking at. You');
    buf.writeln('never generate code, never propose edits in patch form. If a');
    buf.writeln(
        'fix is warranted, describe what to queue as an issue instead.');
    buf.writeln();
    buf.writeln('Rules:');
    buf.writeln(
        '  1. Answer in plain prose, 3-6 sentences. No code blocks unless');
    buf.writeln(
        '     quoting a short snippet from the diff to anchor an observation.');
    buf.writeln(
        '  2. Ground every claim in the supplied context. If you cannot');
    buf.writeln(
        '     ground it, say so; do not fill the gap with speculation.');
    buf.writeln(
        '  3. Name specific files, commit hashes, authors, or line numbers');
    buf.writeln('     when they are in the context. Use exact references.');
    buf.writeln(
        '  4. Match the user\'s register. If they sound frustrated, stay');
    buf.writeln('     dry and factual; no corporate empathy theatre.');
    buf.writeln(
        '  5. Never write code changes. Never scaffold diffs. Never edit');
    buf.writeln('     files. Read, reason, cite, and stop.');
    buf.writeln();
    buf.writeln('<question>');
    buf.writeln(question);
    buf.writeln('</question>');
    buf.writeln();
    buf.writeln('<working_tree_diff>');
    buf.writeln(clippedDiff);
    if (truncNote.isNotEmpty) buf.writeln(truncNote);
    buf.writeln('</working_tree_diff>');
    buf.writeln();
    buf.writeln('Answer the question.');
    return buf.toString();
  }

  /// Walks a unified diff and drops every per-file section whose path
  /// matches [isSensitivePath]. Works at the `diff --git` boundary so
  /// we never split a hunk — either a file is fully included or fully
  /// excluded. Robust against diffs that start with either `diff --git`
  /// headers (the standard) or bare `--- a/path` pairs (rare but git
  /// does emit these for some merge-base outputs).
  String _stripSensitivePathsFromDiff(String fullDiff) {
    final lines = fullDiff.split('\n');
    final out = <String>[];
    var skip = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('diff --git ')) {
        // `diff --git a/path b/path` — extract the `b/` side and check.
        final m = RegExp(r'^diff --git a/(.+) b/(.+)$').firstMatch(line);
        final path = m?.group(2) ?? '';
        skip = path.isNotEmpty && isSensitivePath(path);
      } else if (line.startsWith('--- ') &&
          i + 1 < lines.length &&
          lines[i + 1].startsWith('+++ ')) {
        // Bare `--- a/path` pair fallback (no `diff --git` header).
        final path = lines[i + 1].startsWith('+++ b/')
            ? lines[i + 1].substring('+++ b/'.length)
            : lines[i + 1].substring('+++ '.length);
        skip = path.isNotEmpty && isSensitivePath(path);
      }
      if (!skip) out.add(line);
    }
    return out.join('\n').trim();
  }

  /// Builds the merge-resolution prompt. Strict about output shape so
  /// the one-shot round-trip works: unified diff only, no prose, no
  /// fences. [_extractPatchFromModelOutput] in ai.dart also defends us
  /// if the model ignores the format instruction.
  String _buildMergeResolutionPrompt(
    List<({String path, String content})> files,
  ) {
    final buf = StringBuffer();
    buf.writeln(
        'You are resolving git merge conflicts in a working tree. For each file');
    buf.writeln(
        'below, the text contains unresolved conflict markers (<<<<<<<, =======, >>>>>>>).');
    buf.writeln();
    buf.writeln('Rules:');
    buf.writeln(
        '  1. Produce ONE unified diff that applies with `git apply` over the current tree.');
    buf.writeln(
        '  2. Every conflict marker must be removed — no <<<<<<<, =======, or >>>>>>> lines in the output.');
    buf.writeln(
        '  3. Preserve the MEANING of both sides. Rename/callsite changes on one side should propagate to the other side\'s callsites if both sides edit the same symbol.');
    buf.writeln(
        '  4. Do NOT introduce new functionality the conflict didn\'t already introduce.');
    buf.writeln(
        '  5. Output format: unified diff only. No code fences, no prose, no explanations.');
    buf.writeln();
    buf.writeln(
        'Files (shown as current conflict excerpts with surrounding context, not full files):');
    buf.writeln();
    for (final f in files) {
      buf.writeln('--- file: ${f.path} ---');
      buf.writeln(f.content);
      buf.writeln('--- end: ${f.path} ---');
      buf.writeln();
    }
    buf.writeln(
        'Output the unified diff that resolves every conflict across all files above.');
    return buf.toString();
  }

  String _extractConflictExcerpts(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final ranges = <({int start, int end})>[];
    const contextLines = 28;
    int? conflictStart;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('<<<<<<< ')) {
        conflictStart ??= i;
        continue;
      }
      if (conflictStart != null && line.startsWith('>>>>>>> ')) {
        ranges.add((
          start: math.max(0, conflictStart - contextLines),
          end: math.min(lines.length, i + contextLines + 1),
        ));
        conflictStart = null;
      }
    }

    if (conflictStart != null) {
      ranges.add((
        start: math.max(0, conflictStart - contextLines),
        end: lines.length,
      ));
    }

    if (ranges.isEmpty) {
      return normalized;
    }

    ranges.sort((a, b) => a.start.compareTo(b.start));
    final merged = <({int start, int end})>[];
    for (final range in ranges) {
      if (merged.isEmpty || range.start > merged.last.end) {
        merged.add(range);
        continue;
      }
      final last = merged.removeLast();
      merged.add((start: last.start, end: math.max(last.end, range.end)));
    }

    final buf = StringBuffer();
    var cursor = 0;
    for (final range in merged) {
      if (range.start > cursor) {
        buf.writeln('... omitted lines ${cursor + 1}-${range.start} ...');
      }
      buf.writeln(
          '@@ conflict excerpt lines ${range.start + 1}-${range.end} @@');
      buf.writeln(lines.sublist(range.start, range.end).join('\n'));
      cursor = range.end;
    }
    if (cursor < lines.length) {
      buf.writeln('... omitted lines ${cursor + 1}-${lines.length} ...');
    }
    return buf.toString().trim();
  }

  Future<void> _generateCommitMessage(
    String repoPath,
    RepositoryStatus status,
  ) async {
    // Defense-in-depth: even if a shortcut or stale state triggers
    // this while AI is hidden, bail early. The UI hides the button,
    // but the handler guards against keyboard routes or programmatic
    // invocations we haven't traced.
    if (context.read<PreferencesState>().hideAiFeatures) return;
    final activity = context.read<AiActivityState>();
    // Click while a generation is running = cancel. Bumping the counter
    // invalidates any in-flight result; the click itself doesn't wait
    // for the backend to unwind — the UI returns to idle immediately.
    // Drop the provider record too so the sidebar pill clears.
    if (_generateRunning) {
      _bumpGenerateRequestId(repoPath);
      activity.clear(repoPath: repoPath, kind: AiActivityKind.generate);
      setState(() {
        _actionError = null;
      });
      return;
    }

    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();
    if (included.isEmpty) {
      setState(() {
        _actionError = 'Choose at least one file before generating.';
      });
      return;
    }

    final requestId = _bumpGenerateRequestId(repoPath);
    final scopeKey = _buildMultiDiffScopeKey(included);
    activity.start(
      repoPath: repoPath,
      kind: AiActivityKind.generate,
      scopeKey: scopeKey,
    );
    setState(() {
      _actionError = null;
    });

    final categories = await _resolveCommitAiCategories();
    if (!mounted || requestId != _peekGenerateRequestId(repoPath)) return;
    if (categories == null) {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.generate,
        scopeKey: scopeKey,
        error: _commitAiError ?? 'Commit-message AI is not available yet.',
      );
      setState(() {
        _actionError =
            _commitAiError ?? 'Commit-message AI is not available yet.';
      });
      return;
    }

    final aiSettings = context.read<AiSettingsState>();
    final preferences = context.read<PreferencesState>();
    final selectedCategory = categories
            .where(
              (category) =>
                  category.id == aiSettings.commitMessageModelCategoryId &&
                  category.models.isNotEmpty,
            )
            .firstOrNull ??
        categories.where((category) => category.models.isNotEmpty).firstOrNull;

    if (selectedCategory == null) {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.generate,
        scopeKey: scopeKey,
        error:
            'No runtime-discovered models are available for commit messages.',
      );
      setState(() {
        _actionError =
            'No runtime-discovered models are available for commit messages.';
      });
      return;
    }

    final selectedModel = selectedCategory.models
            .where(
              (model) =>
                  model.value ==
                  aiSettings.modelSelections[selectedCategory.id],
            )
            .firstOrNull ??
        selectedCategory.models.first;

    final includeStaged = included.any((file) => file.hasStagedChange);
    final includeUnstaged = included.any((file) => file.hasUnstagedChange);
    final scopeLabel = included.length == status.files.length
        ? 'all included files'
        : '${included.length} included file${included.length == 1 ? '' : 's'}';

    // Semantic priors for the manifest that sits above the packed diff
    // in the prompt. Both are best-effort: null until the background
    // computes land, in which case the manifest simply skips the
    // IDF-ranking and coupling sections (logos φ + engram wells still
    // emit). Read from state once so the values are stable for this
    // invocation even if state notifies mid-call.
    final couplingMatrix =
        context.read<FileCouplingState>().matrixFor(repoPath);
    final symbolIndex = context.read<SymbolFrequencyState>().indexFor(repoPath);

    final genEffort =
        aiSettings.resolveEffort(selectedCategory.id, selectedModel.value);
    final result = await generateCommitMessage(
      repositoryPath: repoPath,
      modelValue: selectedModel.value,
      modelCategoryLabel: aiSettings.labelForCategory(
        selectedCategory.id,
        selectedCategory.label,
      ),
      scopeLabel: scopeLabel,
      reasoningEffort: genEffort.effort,
      fastMode: genEffort.fast,
      supportsReasoning: selectedModel.supportsReasoning,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
      scopedPaths: included.map((file) => file.path).toList(),
      customPrompt: aiSettings.commitMessagePrompt,
      existingMessage: _commitMsgCtrl.text.trim(),
      readOnly: preferences.aiReadOnlyDefault,
      structure: preferences.commitStructure,
      voice: preferences.commitVoice,
      coverage: preferences.commitCoverage,
      symbolIndex: symbolIndex,
      couplingMatrix: couplingMatrix,
    );
    if (!mounted || requestId != _peekGenerateRequestId(repoPath)) return;

    if (result.ok) {
      activity.complete(
        repoPath: repoPath,
        kind: AiActivityKind.generate,
        scopeKey: scopeKey,
        result: AiGenerateResult(result.data!.message),
      );
      // Apply the message to the composer only if we're still on the
      // originating repo (and the active record is still ours — a
      // mid-flight repo switch + new generate would have replaced it).
      // If we've moved on, the message stays in the record (the
      // sidebar badge surfaces it as an unread done-record) but
      // there's no automatic retrieval path back to the composer
      // when the user returns to the originating repo. That
      // affordance — clicking the badge to switch repos and apply
      // the saved message — is intentionally a follow-up; landing
      // it here would expand the hoist commit's scope into UI work
      // that wants its own focused pass.
      final stillHere =
          context.read<RepositoryState>().activePath == repoPath &&
              _generateRecord?.scopeKey == scopeKey;
      if (stillHere) {
        _commitMsgCtrl.text = result.data!.message;
        _commitMsgCtrl.selection = TextSelection.collapsed(
          offset: _commitMsgCtrl.text.length,
        );
        // Once the user sees the message in their composer, the
        // sidebar pill should stop nagging.
        activity.markSeen(repoPath: repoPath, kind: AiActivityKind.generate);
        setState(() {
          _generateFlash = true;
        });
        // Auto-clear success-flash after a beat — same 1.5 s rhythm
        // review/muse use, single helper so the timing stays in sync.
        _scheduleFlashClear(
            AiActivityKind.generate, () => _generateFlash = false);
      }
    } else {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.generate,
        scopeKey: scopeKey,
        error: result.error ?? 'Generate failed.',
      );
      if (context.read<RepositoryState>().activePath == repoPath) {
        setState(() => _actionError = result.error);
      }
    }
  }

  Future<void> _reviewCommit(
    String repoPath,
    RepositoryStatus status,
  ) async {
    // Defense-in-depth: review is AI — bail when hidden.
    if (context.read<PreferencesState>().hideAiFeatures) return;
    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();
    if (included.isEmpty) {
      setState(() {
        _actionError = 'Choose at least one file before reviewing.';
      });
      return;
    }

    final scopeKey = _buildMultiDiffScopeKey(included);
    final activity = context.read<AiActivityState>();
    final existingReview = _reviewRecord;
    if (existingReview != null &&
        existingReview.scopeKey == scopeKey &&
        existingReview.isError) {
      activity.clear(repoPath: repoPath, kind: AiActivityKind.review);
    } else if (existingReview != null &&
        existingReview.scopeKey == scopeKey &&
        (existingReview.isRunning || existingReview.isDone)) {
      _openDrawerFor(AiActivityKind.review);
      return;
    }

    activity.start(
      repoPath: repoPath,
      kind: AiActivityKind.review,
      scopeKey: scopeKey,
    );
    setState(() {
      _openDrawer = AiActivityKind.review;
      _reviewTraceExpanded = false;
      _reviewReasoningExpanded = false;
      _actionError = null;
    });

    final categories = await _resolveCommitAiCategories();
    if (!mounted) return;
    if (categories == null) {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.review,
        scopeKey: scopeKey,
        error: _commitAiError ?? 'Review AI is not available yet.',
      );
      return;
    }

    final aiSettings = context.read<AiSettingsState>();
    final preferences = context.read<PreferencesState>();
    final selectedCategory = categories
            .where(
              (category) =>
                  category.id == aiSettings.reviewCommitModelCategoryId &&
                  category.models.isNotEmpty,
            )
            .firstOrNull ??
        categories.where((category) => category.models.isNotEmpty).firstOrNull;

    if (selectedCategory == null) {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.review,
        scopeKey: scopeKey,
        error: 'No runtime-discovered models are available for commit review.',
      );
      return;
    }

    final selectedModel = selectedCategory.models
            .where(
              (model) =>
                  model.value ==
                  aiSettings.modelSelections[selectedCategory.id],
            )
            .firstOrNull ??
        selectedCategory.models.first;

    _snapshotReviewModelLabel[repoPath] =
        '${selectedModel.providerLabel} | ${selectedModel.modelId}';
    _snapshotReviewGuardrailStage[repoPath] = preferences.guardrailStage;

    final includeStaged = included.any((file) => file.hasStagedChange);
    final includeUnstaged = included.any((file) => file.hasUnstagedChange);
    final scopeLabel = included.length == status.files.length
        ? 'all included files'
        : '${included.length} included file${included.length == 1 ? '' : 's'}';

    final reviewCouplingMatrix =
        context.read<FileCouplingState>().matrixFor(repoPath);
    final reviewSymbolIndex =
        context.read<SymbolFrequencyState>().indexFor(repoPath);

    final revEffort =
        aiSettings.resolveEffort(selectedCategory.id, selectedModel.value);
    _snapshotReviewEffort[repoPath] = revEffort.effort;
    _snapshotReviewFast[repoPath] = revEffort.fast;
    final result = await reviewCommit(
      repositoryPath: repoPath,
      modelValue: selectedModel.value,
      modelCategoryLabel: aiSettings.labelForCategory(
        selectedCategory.id,
        selectedCategory.label,
      ),
      scopeLabel: scopeLabel,
      reasoningEffort: revEffort.effort,
      fastMode: revEffort.fast,
      supportsReasoning: selectedModel.supportsReasoning,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
      scopedPaths: included.map((file) => file.path).toList(),
      customPrompt: aiSettings.reviewCommitPrompt,
      commitDraft: _commitMsgCtrl.text.trim(),
      guardrailStage: preferences.guardrailStage,
      doubleCheckEnabled: aiSettings.reviewCommitDoubleCheckEnabled,
      readOnly: preferences.aiReadOnlyDefault,
      symbolIndex: reviewSymbolIndex,
      couplingMatrix: reviewCouplingMatrix,
    );
    if (!mounted) return;
    // The scope-key gate inside `activity.complete`/`fail` already
    // handles the "user moved on" case (provider drops the result if
    // the slot's scope doesn't match). We still need to land terminal
    // state into the provider here.
    if (result.ok) {
      activity.complete(
        repoPath: repoPath,
        kind: AiActivityKind.review,
        scopeKey: scopeKey,
        result: AiReviewResult(result.data!),
      );
      // The reasoning expander is purely a per-render UI hint about
      // the empty-findings shape; safe to set when our scope still
      // matches what landed.
      if (_reviewScopeKey == scopeKey) {
        // Only land the result on screen if the user is actively
        // viewing review's drawer. If they dismissed it or switched
        // to another drawer mid-run, the toolbar's half-lit unread
        // state surfaces the completion without yanking the view.
        final isWatching = _openDrawer == AiActivityKind.review;
        if (isWatching) {
          setState(() {
            _openDrawer = AiActivityKind.review;
            _reviewReasoningExpanded = result.data!.findings.isEmpty;
            _reviewFlash = true;
          });
          _scheduleFlashClear(
              AiActivityKind.review, () => _reviewFlash = false);
          activity.markSeen(repoPath: repoPath, kind: AiActivityKind.review);
        } else {
          // Quiet completion. Flash still fires so the toolbar
          // button celebrates briefly, then settles into half-lit
          // unread until the user navigates over.
          setState(() {
            _reviewReasoningExpanded = result.data!.findings.isEmpty;
            _reviewFlash = true;
          });
          _scheduleFlashClear(
              AiActivityKind.review, () => _reviewFlash = false);
        }
      }
    } else {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.review,
        scopeKey: scopeKey,
        error: result.error ?? 'Review failed.',
      );
      if (_reviewScopeKey == scopeKey) {
        final isWatching = _openDrawer == AiActivityKind.review;
        if (isWatching) {
          setState(() => _openDrawer = AiActivityKind.review);
          activity.markSeen(repoPath: repoPath, kind: AiActivityKind.review);
        }
        // Else: leave the drawer alone; toolbar's error-tinted
        // unread state surfaces the failure without preempting.
      }
    }
  }

  Future<void> _runMuse(
    String repoPath,
    RepositoryStatus status,
  ) async {
    // Defense-in-depth: muse is AI — bail when hidden.
    if (context.read<PreferencesState>().hideAiFeatures) return;
    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();
    if (included.isEmpty) {
      setState(() {
        _actionError = 'Choose at least one file before invoking the muse.';
      });
      return;
    }

    final scopeKey = _buildMultiDiffScopeKey(included);
    final activity = context.read<AiActivityState>();
    final existingMuse = _museRecord;
    if (existingMuse != null &&
        existingMuse.scopeKey == scopeKey &&
        existingMuse.isError) {
      activity.clear(repoPath: repoPath, kind: AiActivityKind.muse);
    } else if (existingMuse != null &&
        existingMuse.scopeKey == scopeKey &&
        (existingMuse.isRunning || existingMuse.isDone)) {
      _openDrawerFor(AiActivityKind.muse);
      return;
    }

    activity.start(
      repoPath: repoPath,
      kind: AiActivityKind.muse,
      scopeKey: scopeKey,
    );
    setState(() {
      _openDrawer = AiActivityKind.muse;
      _actionError = null;
    });

    final categories = await _resolveCommitAiCategories();
    if (!mounted) return;
    if (categories == null) {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.muse,
        scopeKey: scopeKey,
        error: _commitAiError ?? 'Muse AI is not available yet.',
      );
      return;
    }

    final aiSettings = context.read<AiSettingsState>();
    final preferences = context.read<PreferencesState>();
    _snapshotMuseGuardrailStage[repoPath] = preferences.guardrailStage;
    // Muse synthesis effort is snapshotted after model resolution below.

    // Resolve two distinct slots for the muse:
    //   - brainstorm slot = "fast" if the user has a model assigned to
    //     it (cheap, divergent, looses the wild ideas)
    //   - synthesis slot = the review category (rigorous, grounding-aware)
    // Either falls back to whichever non-empty category is available, so
    // single-slot configurations still work — both phases just route to
    // the same model.
    AiModelCategoryData? pickCategory(String preferredId) {
      return categories
              .where((c) => c.id == preferredId && c.models.isNotEmpty)
              .firstOrNull ??
          categories.where((c) => c.models.isNotEmpty).firstOrNull;
    }

    AiModelOptionData? pickModel(AiModelCategoryData category) {
      return category.models
              .where((m) => m.value == aiSettings.modelSelections[category.id])
              .firstOrNull ??
          category.models.firstOrNull;
    }

    final synthesisCategory =
        pickCategory(aiSettings.museSynthesisModelCategoryId);
    final brainstormCategory =
        pickCategory(aiSettings.museBrainstormModelCategoryId) ??
            synthesisCategory;

    if (synthesisCategory == null || brainstormCategory == null) {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.muse,
        scopeKey: scopeKey,
        error: 'No runtime-discovered models are available for the muse.',
      );
      return;
    }
    final synthesisModel = pickModel(synthesisCategory);
    final brainstormModel = pickModel(brainstormCategory);
    if (synthesisModel == null || brainstormModel == null) {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.muse,
        scopeKey: scopeKey,
        error: 'Muse needs at least one configured model.',
      );
      return;
    }

    final includeStaged = included.any((file) => file.hasStagedChange);
    final includeUnstaged = included.any((file) => file.hasUnstagedChange);
    final scopeLabel = included.length == status.files.length
        ? 'all included files'
        : '${included.length} included file${included.length == 1 ? '' : 's'}';

    final museCouplingMatrix =
        context.read<FileCouplingState>().matrixFor(repoPath);
    final museSymbolIndex =
        context.read<SymbolFrequencyState>().indexFor(repoPath);

    final brainEffort = aiSettings.resolveEffort(
        brainstormCategory.id, brainstormModel.value);
    final synthEffort = aiSettings.resolveEffort(
        synthesisCategory.id, synthesisModel.value);
    _snapshotMuseSynthEffort[repoPath] = synthEffort.effort;
    _snapshotMuseSynthFast[repoPath] = synthEffort.fast;
    final result = await runMuse(
      repositoryPath: repoPath,
      brainstormModelValue: brainstormModel.value,
      synthesisModelValue: synthesisModel.value,
      scopeLabel: scopeLabel,
      brainstormReasoningEffort: brainEffort.effort,
      brainstormFastMode: brainEffort.fast,
      brainstormSupportsReasoning: brainstormModel.supportsReasoning,
      synthesisReasoningEffort: synthEffort.effort,
      synthesisFastMode: synthEffort.fast,
      synthesisSupportsReasoning: synthesisModel.supportsReasoning,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
      scopedPaths: included.map((file) => file.path).toList(),
      customPrompt: aiSettings.musePrompt,
      commitDraft: _commitMsgCtrl.text.trim(),
      guardrailStage: preferences.guardrailStage,
      readOnly: preferences.aiReadOnlyDefault,
      symbolIndex: museSymbolIndex,
      couplingMatrix: museCouplingMatrix,
    );
    if (!mounted) return;
    final landed = result.ok;
    if (landed) {
      activity.complete(
        repoPath: repoPath,
        kind: AiActivityKind.muse,
        scopeKey: scopeKey,
        result: AiMuseResult(result.data!),
      );
    } else {
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.muse,
        scopeKey: scopeKey,
        error: result.error ?? 'Muse failed.',
      );
    }
    // Single check — `_museScopeKey` is just the getter view of
    // `_museRecord?.scopeKey`, so the prior `A || A`-style disjunction
    // collapses to one comparison.
    if (_museScopeKey == scopeKey) {
      // Only land the result if the user is actively viewing
      // muse's drawer. Otherwise the toolbar badge handles it.
      final isWatching = _openDrawer == AiActivityKind.muse;
      setState(() {
        if (isWatching) _openDrawer = AiActivityKind.muse;
        if (landed) _museFlash = true;
      });
      if (landed) {
        _scheduleFlashClear(AiActivityKind.muse, () => _museFlash = false);
      }
      if (isWatching) {
        activity.markSeen(repoPath: repoPath, kind: AiActivityKind.muse);
      }
    }
  }

  void _openReviewFinding(
    String repoPath,
    String path,
    RepositoryStatus status, {
    String? hunkLabel,
  }) {
    final startLine = _parseHunkStartLine(hunkLabel);
    final includedCount = _includedDirtyCount(status);
    if (_includedPaths.contains(path) && includedCount > 1) {
      _jumpToMultiDiffPath(path, fallbackStartLine: startLine);
      return;
    }
    _inspectSingleDiff(repoPath, path);
  }

  /// Parses a git hunk label like "@@ -14,6 +14,7 @@" and returns the
  /// new-file start line, which can be used to jump the diff viewer.
  static int? _parseHunkStartLine(String? hunkLabel) {
    if (hunkLabel == null) return null;
    final match = RegExp(r'\+(\d+)').firstMatch(hunkLabel);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  Future<void> _copyReviewReport(AiCommitReviewData review) async {
    final buffer = StringBuffer()
      ..writeln('${review.verdict} | ${review.score}')
      ..writeln(review.summary);
    // Skip the Review Report section entirely when the model didn't
    // return reasoning — avoids dumping a stray header with no body
    // into the user's clipboard.
    if (review.reasoningReport.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Review Report')
        ..writeln(review.reasoningReport);
    }
    if (review.findings.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Findings');
      for (final finding in review.findings) {
        buffer.writeln('- ${finding.title}');
        if (finding.filePath != null || finding.hunkLabel != null) {
          final meta = [
            if (finding.filePath != null) finding.filePath!,
            if (finding.hunkLabel != null) finding.hunkLabel!,
          ].join(' | ');
          buffer.writeln('  $meta');
        }
        if (finding.evidence.trim().isNotEmpty) {
          buffer.writeln('  Evidence: ${finding.evidence}');
        }
        if (finding.whyItMatters.trim().isNotEmpty) {
          buffer.writeln('  Why: ${finding.whyItMatters}');
        }
      }
    }
    if (review.observations.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Observations');
      for (final obs in review.observations) {
        buffer.writeln('- ${obs.title}');
        if (obs.detail.trim().isNotEmpty) {
          buffer.writeln('  ${obs.detail}');
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) {
      return;
    }
    setState(() {
      _actionError = null;
    });
  }

  Future<void> _copyMuseReport(AiMuseData muse,
      {List<AiMuseProposal>? subset}) async {
    final buf = StringBuffer();
    buf.writeln('Muse · ${muse.scopeLabel}');
    buf.writeln('Model: ${muse.providerId} / ${muse.modelId}');
    buf.writeln();
    void emitProposal(AiMuseProposal p) {
      buf.writeln('- ${p.title}');
      buf.writeln('    ${p.vision}');
      buf.writeln('    foothold: ${p.foothold}');
      if (p.citations.isNotEmpty) {
        buf.writeln('    cite: ${p.citations.join(", ")}');
      }
    }

    void tierBlock(AiMuseIdeaTier tier, String label) {
      final source = subset ?? muse.proposalsForTier(tier);
      final group = subset == null
          ? source
          : source.where((p) => p.tier == tier).toList(growable: false);
      if (group.isEmpty) return;
      buf.writeln(label);
      for (final p in group) {
        emitProposal(p);
      }
      buf.writeln();
    }

    tierBlock(AiMuseIdeaTier.spark, 'SPARK');
    tierBlock(AiMuseIdeaTier.current, 'CURRENT');
    tierBlock(AiMuseIdeaTier.horizon, 'HORIZON');
    tierBlock(AiMuseIdeaTier.fever, 'FEVER');
    await Clipboard.setData(ClipboardData(text: buf.toString().trim()));
    if (!mounted) return;
    setState(() {
      _actionError = null;
    });
  }

  /// Right-click on the commit button surfaces amend variants
  /// without crowding the base UI with a visible toggle. The user
  /// picks "Amend last commit" or "Amend & sync"; both run the
  /// existing commit flow with `amend: true` so the prior commit
  /// gets the staged changes folded in (and optionally a new
  /// message, if the user typed one).
  ///
  /// Hidden entirely on a fresh repo (no HEAD commit yet) — the
  /// menu would render with items that can only ever return
  /// "nothing to amend" errors, which is misleading. The right-
  /// click does nothing visible until there's at least one commit.
  void _showCommitContextMenu(
    Offset globalPos,
    String repoPath,
    RepositoryStatus status,
    _PrimaryCommitAction primaryAction,
  ) {
    if (!status.hasHeadCommit) return;
    showAppContextMenu(context, globalPos, [
      ListMenuSection([
        AppContextMenuItem(
          icon: Icons.edit_note_outlined,
          label: 'Amend last commit',
          onTap: () => _commit(
            repoPath,
            status,
            mode: _CommitRunMode.commitOnly,
            amend: true,
          ),
        ),
        if (primaryAction.syncAfterCommit)
          AppContextMenuItem(
            icon: Icons.merge_type_outlined,
            label: 'Amend & ${primaryAction.label.toLowerCase()}',
            onTap: () => _commit(
              repoPath,
              status,
              mode: _CommitRunMode.commitAndSync,
              amend: true,
            ),
          ),
      ]),
    ]);
  }

  Future<void> _commit(
    String repoPath,
    RepositoryStatus status, {
    required _CommitRunMode mode,
    bool amend = false,
  }) async {
    var message = _commitMsgCtrl.text.trim();
    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .map((file) => file.path)
        .toList();

    if (included.isEmpty) {
      setState(
          () => _actionError = 'Choose at least one file for the next commit.');
      return;
    }
    // Amend allows empty message — `git commit --amend` keeps the
    // previous commit's message when no new one is supplied. Regular
    // commits still require a message.
    if (message.isEmpty && !amend) {
      setState(() => _actionError = 'Write a commit message first.');
      return;
    }
    if (_commitTags.isNotEmpty && message.isNotEmpty) {
      message = '$message\n\nTags: ${_commitTags.join(', ')}';
    }

    setState(() {
      _actionRunning = true;
      _actionError = null;
    });

    final coord = context.read<UndoCoordinator>();
    final isSync = mode == _CommitRunMode.commitAndSync;
    final kind = isSync ? UndoActionKind.commitAndPush : UndoActionKind.commit;
    final windowSec = context.read<PreferencesState>().undoWindowFor(kind);
    final label = isSync ? 'Committing and syncing' : 'Committing';

    final outcome = await coord.schedule<_CommitOutcome>(
      kind: kind,
      label: label,
      window: Duration(seconds: windowSec),
      run: () => _runCommitFlow(repoPath, status, mode, included, message,
          amend: amend),
    );

    if (!mounted) return;

    if (outcome == null) {
      // User cancelled during the undo window — nothing was staged,
      // committed, or pushed. Just restore the button state.
      setState(() => _actionRunning = false);
      return;
    }

    setState(() {
      _actionRunning = false;
      if (outcome.ok) {
        _commitMsgCtrl.clear();
        _commitTags.clear();
        unawaited(_clearCommitDraft());
        _actionError = outcome.syncError;
      } else {
        _actionError = outcome.error;
      }
    });

    if (!outcome.ok) return;
    // Bridge to Branches: if the current branch has a desk PR, refresh
    // its persisted diff stats so the row metrics (+N -M, K files) are
    // accurate the moment the user switches to Branches. Without this
    // the row stays at the last-expand's cached numbers until the user
    // collapses and re-expands. No-op when there's no desk PR for this
    // branch, so every commit pays the lookup but only desk-branch
    // commits pay the diff fetch.
    final branchAfterCommit = status.branch;
    unawaited(context.read<DeskPrState>().recomputeDiffStats(
          repoPath: repoPath,
          branch: branchAfterCommit,
        ));
  }

  /// The actual stage+commit+optional-push sequence. Wrapped in
  /// [_commit] via [UndoCoordinator.schedule] so the entire block
  /// gets a safety window — if the user cancels, none of this runs.
  Future<_CommitOutcome> _runCommitFlow(
    String repoPath,
    RepositoryStatus status,
    _CommitRunMode mode,
    List<String> included,
    String message, {
    bool amend = false,
  }) async {
    final stageResult = await stagePaths(repoPath, included);
    if (!stageResult.ok) {
      return _CommitOutcome.err(stageResult.error ?? 'Failed to stage files.');
    }

    final stagedExcluded = _stagedExcludedPaths(status);
    if (stagedExcluded.isNotEmpty) {
      final unstageResult = await unstagePaths(repoPath, stagedExcluded);
      if (!unstageResult.ok) {
        return _CommitOutcome.err(
            unstageResult.error ?? 'Failed to unstage excluded files.');
      }
    }

    final commitResult = await createCommit(
      repoPath,
      message,
      amend: amend,
    );
    if (!commitResult.ok) {
      await _refreshAndReadStatus();
      return _CommitOutcome.err(commitResult.error ?? 'Commit failed.');
    }

    final committed = commitResult.data!;
    final shortHash = committed.commitHash.length >= 8
        ? committed.commitHash.substring(0, 8)
        : committed.commitHash;
    var successMessage = 'Committed ${committed.summary} ($shortHash).';
    String? syncError;

    final refreshed = await _refreshAndReadStatus();

    if (mode == _CommitRunMode.commitAndSync && refreshed != null) {
      final syncResult = await syncRemote(repoPath, refreshed);
      if (syncResult.ok) {
        final operation = syncResult.data!.operation;
        successMessage =
            'Committed ${committed.summary} ($shortHash) and ran $operation.';
      } else {
        syncError = 'Commit succeeded, but sync failed: ${syncResult.error}';
      }
      await _refreshAndReadStatus();
    }

    return _CommitOutcome.ok(committed, successMessage, syncError);
  }

  Future<void> _loadStashes(String repo) async {
    setState(() => _stashesLoading = true);
    final result = await listStashes(repo);
    if (!mounted) return;
    setState(() {
      _stashesLoading = false;
      _stashes = result.ok ? result.data! : const [];
      // Invalidate per-stash caches — indices and contents may have shifted
      // after pop/drop/push.
      _stashFiles.clear();
      _stashFilesLoading.clear();
      _stashShapes.clear();
      // Drop open-state entries whose index no longer exists so reopening
      // a new stash at the same slot doesn't surprise the user.
      final validIndices = _stashes.map((s) => s.index).toSet();
      _stashOpenIndices.removeWhere((i) => !validIndices.contains(i));
    });
  }

  Future<void> _loadStashFiles(String repo, int index) async {
    if (_stashFiles.containsKey(index) || _stashFilesLoading.contains(index)) {
      return;
    }
    setState(() => _stashFilesLoading.add(index));
    final r = await stashFiles(repo, index: index);
    if (!mounted) return;
    setState(() {
      _stashFilesLoading.remove(index);
      if (r.ok) {
        _stashFiles[index] = r.data!;
        _stashShapes.remove(index); // Recompute shape with real file list.
      }
    });
    if (r.ok) _maybeComputeStashShape(index);
  }

  /// Compute (or recompute) the stash shape for [index] if both the file
  /// list and the coupling matrix are available. Runs outside build so
  /// we never mutate state as a side effect of the widget tree flush.
  void _maybeComputeStashShape(int index) {
    if (!mounted) return;
    final files = _stashFiles[index];
    if (files == null) return;
    final repoPath = context.read<RepositoryState>().activePath;
    if (repoPath == null) return;
    final matrix = context.read<FileCouplingState>().matrixFor(repoPath);
    if (matrix == null) return;
    final currentPaths = context
            .read<RepositoryState>()
            .status
            ?.files
            .map((f) => f.path)
            .toList() ??
        [];
    final shape = computeStashShape(
      stashPaths: files.map((f) => f.path).toList(),
      currentPaths: currentPaths,
      matrix: matrix,
    );
    setState(() => _stashShapes[index] = shape);
  }

  void _toggleStashOpen(String repo, int index) {
    setState(() {
      if (_stashOpenIndices.contains(index)) {
        _stashOpenIndices.remove(index);
      } else {
        _stashOpenIndices.add(index);
      }
    });
    if (_stashOpenIndices.contains(index)) {
      unawaited(_loadStashFiles(repo, index));
    }
  }

  Future<void> _shelveAll(String repo, {String? label}) async {
    // "Shelve all" — capture untracked too so a fresh-cloned WIP file
    // doesn't get silently left behind. Matches the user-facing label.
    final result = await stashPush(
      repo,
      message: label,
      includeUntracked: true,
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _actionError = result.error);
      return;
    }
    await _refreshAndReadStatus();
    if (mounted) _loadStashes(repo);
  }

  Future<void> _pickUpStash(String repo, int index) async {
    final result = await stashPop(repo, index: index);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _actionError = result.error);
      return;
    }
    setState(() {
      _stashPeekDiff = null;
      _stashPeekIndex = null;
    });
    await _refreshAndReadStatus();
    if (mounted) _loadStashes(repo);
  }

  Future<void> _tossStash(String repo, int index) async {
    final result = await stashDrop(repo, index: index);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _actionError = result.error);
      return;
    }
    setState(() {
      if (_stashPeekIndex == index) {
        _stashPeekDiff = null;
        _stashPeekIndex = null;
      }
    });
    if (mounted) _loadStashes(repo);
  }

  Future<void> _peekStash(String repo, int index) async {
    if (_stashPeekIndex == index) {
      setState(() {
        _stashPeekDiff = null;
        _stashPeekIndex = null;
      });
      return;
    }
    final result = await stashShow(repo, index: index);
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _stashPeekDiff = result.data;
        _stashPeekIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final aiSettings = context.watch<AiSettingsState>();
    final preferences = context.watch<PreferencesState>();
    final repo = context.read<RepositoryState>();
    final repoPath =
        context.select<RepositoryState, String?>((state) => state.activePath);
    // Rebuild signal for AI activity, narrowed to the ACTIVE repo's
    // slice. Piggybacks on AiActivityState's `_activeCache` (see the
    // doc-comment on that field): `activeFor(repoPath)` returns the
    // same `List` instance until that repo's slice actually mutates,
    // so cross-repo notifies (e.g. a muse completing on repo B while
    // we're viewing repo A) compare equal and don't re-run the
    // 600+ line build tree. The accessors below (`_reviewRecord`,
    // `_generateRecord`, …) still read records via `recordFor`, which
    // sees terminal-but-seen records too — the select is just the
    // change-detection lever, not the data source.
    if (repoPath != null) {
      context.select<AiActivityState, List<AiActivityRecord>>(
        (s) => s.activeFor(repoPath),
      );
      // Cross-widget drawer-open intent. The sidebar AI badge writes
      // a pending kind via `AiActivityState.requestDrawerOpen`. We
      // drain it on the build that runs once the request lands. The
      // selector below is what triggers our rebuild when a pending
      // entry arrives for the same repo we're already viewing —
      // without it, the records-only `select` above wouldn't fire
      // on a `requestDrawerOpen` notify (it doesn't mutate records).
      final pendingDrawer = context.select<AiActivityState, AiActivityKind?>(
        (s) => s.peekPendingDrawerOpen(repoPath),
      );
      if (pendingDrawer != null && pendingDrawer != AiActivityKind.generate) {
        // PostFrame: don't setState during build, and re-check that
        // we're still on this repo + nothing else has consumed the
        // intent in the meantime (the record check is paranoia —
        // single consumer in practice).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (context.read<RepositoryState>().activePath != repoPath) return;
          final aiState = context.read<AiActivityState>();
          final intent = aiState.consumePendingDrawerOpen(repoPath);
          if (intent == null) return;

          if (intent.kind == AiActivityKind.ask &&
              intent.query != null &&
              intent.query!.isNotEmpty) {
            final status = context.read<RepositoryState>().status;
            if (status != null) {
              final aiSettings = context.read<AiSettingsState>();
              _askInPanel(repoPath, status, intent.query!,
                  aiSettings.commitMessageModelCategoryId);
              return;
            }
            if (intent.retries < 3) {
              aiState.requeueIntent(repoPath, intent.retry());
              return;
            }
            // Exhausted retries — fall through to open drawer without query.
          }
          _openDrawerFor(intent.kind);
        });
      }
    }
    // The Logos engine drives file-dimming and provides a fallback
    // coupling matrix when FileCouplingState is mid-reload.
    final logosForDim = context.select<LogosGitState, LogosGit?>(
      (state) => state.engineFor(repoPath ?? ''),
    );
    final couplingMatrix = repoPath == null
        ? null
        : (context.select<FileCouplingState, FileCouplingMatrix?>(
              (state) => state.matrixFor(repoPath),
            ) ??
            logosForDim?.stats.coupling);
    final corpusIndex = repoPath == null
        ? null
        : context.select<SymbolFrequencyState, SymbolFrequencyIndex?>(
            (state) => state.indexFor(repoPath),
          );
    final status = context
        .select<RepositoryState, RepositoryStatus?>((state) => state.status);
    final statusError =
        context.select<RepositoryState, String?>((state) => state.statusError);
    final statusLoading =
        context.select<RepositoryState, bool>((state) => state.statusLoading);

    // Seed the stash drawer from the user's "default expanded" preference
    // once per session, as soon as we actually have shelves to show. After
    // that the user's manual toggles take over.
    if (!_stashExpandedInitialized && _stashes.isNotEmpty) {
      _stashExpandedInitialized = true;
      if (preferences.stashCabinetDefaultExpanded && !_stashesExpanded) {
        _stashesExpanded = true;
      }
    }

    if (repoPath == null) {
      if (_selectionRepoPath != null) {
        _flushSelectionPersistenceBestEffort();
        _selectionRepoPath = null;
        _selectionStorageScopeKey = null;
        _selectionStorageLoaded = false;
        _selectionPersistFingerprint = null;
        _resetSelectionScopeState();
      }
      return const AppStatusView.noRepository();
    }

    if (_selectionRepoPath != repoPath) {
      _flushSelectionPersistenceBestEffort();
      _selectionRepoPath = repoPath;
      _selectionStorageScopeKey = null;
      _selectionStorageLoaded = false;
      _selectionPersistFingerprint = null;
      _resetSelectionScopeState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectionRepoPath != repoPath) {
          return;
        }
        _loadSelectionStateForRepo(repoPath);
      });
    }

    // Kick off a coupling-matrix compute whenever the observable repo state
    // changes (new repo, new commit, branch switch, ahead/behind moved).
    // The FileCouplingState does its own HEAD-check before recomputing, so
    // calling it on state changes is cheap. Fire-and-forget — the list
    // renders without cluster stripes until notifyListeners brings us back.
    final couplingStateKey =
        '$repoPath|${status?.branch ?? ''}|${status?.files.length ?? 0}|'
        '${status?.ahead ?? 0}|${status?.behind ?? 0}';
    if (_couplingKickedOffFor != couplingStateKey) {
      _couplingKickedOffFor = couplingStateKey;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final couplingState = context.read<FileCouplingState>();
        // ignore: use_build_context_synchronously
        final symbolFreqState = context.read<SymbolFrequencyState>();
        // Kick off BOTH in parallel — the co-change matrix reads git log,
        // the corpus frequency index reads file contents. But Logos only
        // depends on the coupling matrix, so don't hold engine warm-up
        // behind the slower corpus scan.
        final couplingFuture = couplingState.loadForRepo(repoPath);
        unawaited(symbolFreqState.loadForRepo(repoPath));
        await couplingFuture;
        if (!mounted) return;
        // Chain: once the coupling matrix is warm, immediately warm the
        // LogosGit engine too — it needs the matrix for the CC axis and
        // reusing the cached one saves a second 1000-commit log walk.
        final matrix = couplingState.matrixFor(repoPath);
        if (matrix != null) {
          // ignore: use_build_context_synchronously
          context.read<LogosGitState>().loadForRepo(repoPath, coupling: matrix);
          // Compute shapes for any stashes whose files loaded before the matrix.
          for (final idx in _stashFiles.keys) {
            if (!_stashShapes.containsKey(idx)) {
              _maybeComputeStashShape(idx);
            }
          }
        }
      });
    }
    // Refresh per-file impact weights whenever the status signature
    // changes. One numstat call per refresh; results feed the "by impact"
    // sort. Fire-and-forget — the list uses whatever's cached until the
    // new fetch lands, then rebuilds.
    if (_weightsFetchedForKey != couplingStateKey) {
      _weightsFetchedForKey = couplingStateKey;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final r = await fileChangeWeights(repoPath);
        if (!mounted || _weightsFetchedForKey != couplingStateKey) return;
        if (r.ok) {
          setState(() => _changeWeights = r.data!);
        }
      });
    }
    // Recompute symbol-overlap coupling whenever the change set changes.
    // Reads file content from disk — fast for typical change-set sizes
    // (O(n) file reads, no git subprocess). Results layer on top of the
    // historical Jaccard matrix so new/untracked files get structural scores.
    //
    // Uses the corpus frequency index (self-learning, language-agnostic
    // stop-word filter) when available; falls back to change-set-local
    // IDF until the index finishes its first-time scan.
    //
    // Also re-fires when the corpus index key changes — so the first
    // time the index finishes warming, we recompute with the better IDF.
    final symbolFetchKey =
        '$couplingStateKey|corpus=${corpusIndex?.totalDocuments ?? 0}';
    if (_symbolCouplingFetchedForKey != symbolFetchKey) {
      _symbolCouplingFetchedForKey = symbolFetchKey;
      final pathsSnapshot = status?.files.map((f) => f.path).toList() ?? [];
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final sym = await Future(
          () => computeSymbolCoupling(
            pathsSnapshot,
            repoPath,
            corpus: corpusIndex,
          ),
        );
        if (!mounted || _symbolCouplingFetchedForKey != symbolFetchKey) {
          return;
        }
        setState(() => _symbolCoupling = sym);
      });
    }
    // Detect repo or branch switch — cancel any pending saves,
    // then load the correct draft.
    final currentBranch = status?.branch;
    if (_lastDraftRepoPath != repoPath || _lastDraftBranch != currentBranch) {
      _commitDraftSaveDebounce?.cancel();
      // Flush the current draft to the OLD repo/branch before switching.
      final oldRepo = _lastDraftRepoPath;
      final oldBranch = _lastDraftBranch;
      final textToSave = _commitMsgCtrl.text;
      _commitMsgCtrl.clear();
      _lastDraftRepoPath = repoPath;
      _lastDraftBranch = currentBranch;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Save outgoing draft, then load incoming.
        if (oldRepo != null && textToSave.trim().isNotEmpty) {
          await _flushDraft(oldRepo, oldBranch, textToSave);
        }
        _loadCommitDraftForRepo(repoPath, branch: currentBranch, force: true);
        _loadStashes(repoPath);
      });
    }
    if (statusError != null) {
      return AppStatusView.error(
        title: 'Repository status unavailable',
        message: statusError,
      );
    }
    if (status == null) {
      return const AppStatusView.loading(
        title: 'Loading repository status',
        message: 'Reading the working tree.',
      );
    }

    _syncDraftFromStatus(status);

    if (_selectionStorageLoaded && _selectionStorageScopeKey != null) {
      final fingerprint =
          _selectionPersistenceFingerprint(_selectionStorageScopeKey!);
      if (_selectionPersistFingerprint != fingerprint) {
        _selectionPersistFingerprint = fingerprint;
        _scheduleSelectionPersistence();
      }
    }

    if (status.files.isEmpty && _stashes.isEmpty && !_stashesLoading) {
      // The dirty-state surface below wraps its content in a DragTarget
      // so a desk pill can be dropped to dump its diff here. The clean
      // state is actually the friendliest moment to imprint — no local
      // changes to reconcile — so the drop target lives here too,
      // mirroring the same accept policy and overlay.
      return DragTarget<DeskDropPayload>(
        onWillAcceptWithDetails: (d) =>
            d.data.isStash ||
            (d.data.isDesk && !p.equals(d.data.deskPath!, repoPath)),
        onAcceptWithDetails: (d) {
          if (d.data.isStash) {
            _handleStashDump(
                context, d.data.stashIndex!, d.data.label, repoPath);
          } else {
            _handleDeskDump(context, d.data.deskPath!, d.data.label, repoPath);
          }
        },
        builder: (ctx, candidateData, rejectedData) {
          final dragActive = candidateData.isNotEmpty;
          return Stack(
            children: [
              _CleanTreeDashboard(
                tokens: t,
                status: status,
                repoPath: repoPath,
                onRefresh: () => repo.userRefresh(),
              ),
              if (dragActive)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.accentBright.withValues(alpha: 0.06),
                        border: Border.all(
                          color: t.accentBright.withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: t.accentBright, width: 1),
                        ),
                        child: Text(
                          candidateData.isNotEmpty &&
                                  candidateData.first?.isStash == true
                              ? 'drop to bring changes from this shelf here'
                              : 'drop to bring changes from this desk here',
                          style: TextStyle(
                            color: t.textStrong,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    final stagedCount =
        status.files.where((file) => file.hasStagedChange).length;
    final includedCount = _includedDirtyCount(status);
    final includedFiles = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();

    _recomputeFileDimOpacity(status, logosForDim, couplingMatrix);

    // Coupling clusters for the current change set. Computed once per build;
    // falls back to "all isolated" when the matrix isn't ready yet.
    final currentPaths = status.files.map((f) => f.path).toList();

    // Universal: gather merge-conflict paths. Any file with 'U' on either
    // side is conflicted and must float to the top regardless of sort.
    final conflictedPaths = <String>{};
    for (final f in status.files) {
      if (f.isConflicted) {
        conflictedPaths.add(f.path);
      }
    }

    // Impact signals for the "by impact" sort. Raw diff counts flow
    // through untouched — no magic multipliers, no new-file bonuses,
    // no binary baselines. The sort itself derives effective impact
    // from these plus the coupling matrix (`raw × (1 − entanglement)`)
    // so files whose change is "explained" by a co-changing peer in
    // the same diff are attenuated on physics alone, not on
    // language-specific filename patterns.
    final impactSignals = <String, FileImpactSignal>{};
    for (final f in status.files) {
      final w = _changeWeights[f.path];
      impactSignals[f.path] = FileImpactSignal(
        adds: w?.adds ?? 0,
        dels: w?.dels ?? 0,
        binary: w?.binary ?? false,
      );
    }

    // Layer symbol-overlap scores on top of the historical Jaccard matrix.
    // withSymbol() is a shallow copy — no data is duplicated, only the
    // reference to the symbol map is updated.
    final effectiveMatrix = couplingMatrix != null && _symbolCoupling.isNotEmpty
        ? couplingMatrix.withSymbol(_symbolCoupling)
        : couplingMatrix;

    // Pull the Logos engine up-front so the clustering seriation AND
    // the downstream φ re-rank share a single fetch. The engine is
    // only relevant when the sort guide is `relatedProximity`; for
    // other modes we skip the lookup entirely.
    final logosTabActive = TickerMode.valuesOf(context).enabled;
    final logosEngineBase =
        preferences.fileSortGuide == FileSortGuide.relatedProximity
            ? (logosTabActive
                ? context.select<LogosGitState, LogosGit?>(
                    (state) => state.engineFor(repoPath),
                  )
                : context.read<LogosGitState>().engineFor(repoPath))
            : null;
    final logosEngine = (logosEngineBase != null && _symbolCoupling.isNotEmpty)
        ? logosEngineBase.withSymbolEdges(_symbolCoupling)
        : logosEngineBase;

    // Route the correlatedness sort through the engine's own hunk
    // pipeline. `_correlatednessContextFor` returns whatever context
    // is currently cached (possibly null on first access); when the
    // status or engine has moved on, it kicks off an async rebuild
    // that runs `rankHunksByPhiAsync` and setStates when done. The
    // sort falls back to the legacy nearest-neighbour chain until
    // the first rebuild completes.
    final correlatednessContext = (effectiveMatrix != null &&
            logosEngine != null &&
            preferences.fileSortGuide == FileSortGuide.relatedProximity)
        ? _correlatednessContextFor(
            repoPath: repoPath,
            status: status,
            engine: logosEngine,
          )
        : null;

    final clusters = _clustersFor(
      status: status,
      effectiveMatrix: effectiveMatrix,
      currentPaths: currentPaths,
      sortGuide: preferences.fileSortGuide,
      impactSignals: impactSignals,
      conflictedPaths: conflictedPaths,
      inverted: preferences.fileSortInverted,
      correlatednessContext: correlatednessContext,
      couplingConstants:
          logosEngine?.couplingConstants ?? CouplingConstants.prior,
    );
    // Map the Logos XY pad to diffusion controls:
    //   padY (NEAR=0 ↔ FAR=1) → temperature t = 0.5 × 4^padY ∈ [0.5, 2.0]
    //     padY=0 tight: just the staged cluster
    //     padY=0.5 balanced: 1-hop neighbourhood
    //     padY=1 wide: semantic region, blast-radius view
    //   padX (FOLDER=0 ↔ HISTORY=1) → coherence gate threshold.
    //     FOLDER end demands tight structural coherence (0.35); the user
    //     is saying "stay close to what looks like it belongs together
    //     by shape." HISTORY end relaxes the gate (0.15); the user
    //     accepts history-driven associations even when the induced
    //     subgraph is loose. Linear interpolation between the two ends.
    final logosT = 0.5 * math.pow(4.0, preferences.logosPadY).toDouble();
    final logosCoherenceGate =
        0.35 - (preferences.logosPadX.clamp(0.0, 1.0) * 0.20);

    String? logosRerankKey;
    if (logosTabActive && logosEngine != null && _includedPaths.isNotEmpty) {
      logosRerankKey = _logosRerankKey(
        engine: logosEngine,
        clusters: clusters,
        sources: _includedPaths,
        t: logosT,
        coherenceGate: logosCoherenceGate,
        inverted: preferences.fileSortInverted,
      );
      if (_appliedLogosRerankKey != logosRerankKey &&
          _pendingLogosRerankKey != logosRerankKey) {
        _scheduleLogosRerank(
          requestKey: logosRerankKey,
          clusters: clusters,
          engine: logosEngine,
          sources: _includedPaths,
          t: logosT,
          coherenceGate: logosCoherenceGate,
          inverted: preferences.fileSortInverted,
        );
      }
    } else {
      _cancelPendingLogosRerank();
    }

    final orderedPaths = logosRerankKey != null &&
            _appliedLogosRerankKey == logosRerankKey &&
            _appliedLogosRerankPaths != null
        ? _appliedLogosRerankPaths!
        : clusters.orderedPaths;

    final inspectionOverridePath = _inspectionDiffPath;
    final inspectingSingleDiff = includedFiles.length > 1 &&
        inspectionOverridePath != null &&
        !_includedPaths.contains(inspectionOverridePath);
    final showMultiDiff = includedFiles.length > 1 && !inspectingSingleDiff;
    final activeMultiDiffPath = _multiDiffCurrentPath;
    final activeDiffPath = inspectingSingleDiff
        ? inspectionOverridePath
        : showMultiDiff
            ? activeMultiDiffPath
            : (_visibleDiffPath ?? _selectedDiffPath);
    final primaryAction = _primaryActionFor(status);
    final hasCommitAiSelection = _hasCommitAiSelection(aiSettings);
    final hasReviewAiSelection = _hasReviewAiSelection(aiSettings);
    final hasPersistentReview = _hasReviewStateForCurrentSelection();
    // The LogosGit engine for this repo. Every AI flow (generate /
    // review / muse / ask) feeds the engine's coupling matrix +
    // semantic priors into its prompt, so a click before the engine
    // resolves would either crash on a null deref inside the
    // pipeline or silently produce a degraded result. Gate every AI
    // button on this AND on `hasCommitAiSelection` (which captures
    // "AI providers loaded"). Two orthogonal axes, both required.
    // Re-runs of the existing record (the same-scope path) are
    // exempt — the result is already on disk and doesn't need the
    // engine to surface it.
    final engineReady = context.select<LogosGitState, bool>(
      (s) => s.engineFor(repoPath) != null,
    );
    final diffPaths = status.files.map((f) => f.path).toSet();
    if (engineReady && status.files.isNotEmpty) {
      final engine =
          context.read<LogosGitState>().engineFor(repoPath)!;
      final sameInputs = identical(engine, _lastCouplingEngine) &&
          _lastCouplingDiffPaths != null &&
          _lastCouplingDiffPaths!.length == diffPaths.length &&
          _lastCouplingDiffPaths!.containsAll(diffPaths);
      if (!sameInputs) {
        _lastCouplingEngine = engine;
        _lastCouplingDiffPaths = diffPaths;
        _dejaVuScore = engine.dejaVuScore(diffPaths);
        _dejaVuGhostCount = _dejaVuScore > 0
            ? engine.ghostsForDiff(diffPaths, limit: 5).length
            : 0;
        _suggestedTags = _deriveTagSuggestions(engine, diffPaths);
      }
    } else {
      _lastCouplingEngine = null;
      _lastCouplingDiffPaths = null;
      _dejaVuScore = 0.0;
      _dejaVuGhostCount = 0;
      _suggestedTags = const [];
    }
    final canCommit = !_actionRunning &&
        !_generateRunning &&
        !_reviewRunning &&
        _commitMsgCtrl.text.trim().isNotEmpty &&
        includedCount > 0;
    // Each AI button gates ONLY on its own kind's running flag — generate
    // does not block review, review does not block muse, etc. The three
    // flows are independent per (repo, kind) slots in AiActivityState, so
    // the UI mirrors that. Generate intentionally stays clickable while
    // running so the in-handler "click again to cancel" branch can fire.
    final canGenerate = !_actionRunning &&
        !_commitAiLoading &&
        engineReady &&
        includedCount > 0 &&
        hasCommitAiSelection;
    // Review can be clicked while running to re-show the spinner view, or
    // when a persistent review exists to re-show the drawer. Disabled only
    // when we're already viewing the running spinner (no-op click) or
    // there's nothing to show / start. The engine-ready gate is
    // skipped on the "show existing" path — a persisted review is
    // independent of the live engine.
    final canReview = !_actionRunning &&
        !_commitAiLoading &&
        !(_reviewRunning && _isReviewDrawerOpen) &&
        includedCount > 0 &&
        (hasPersistentReview ||
            _reviewRunning ||
            (engineReady && hasReviewAiSelection));
    // Muse mirrors review: clickable while running to surface the
    // drawer, clickable when there's an existing same-scope record to
    // re-show, and otherwise gated on engine-ready + AI selection.
    final hasPersistentMuse = _hasMuseStateForCurrentSelection();
    final canMuse = !_actionRunning &&
        !_commitAiLoading &&
        !(_museRunning && _isMuseDrawerOpen) &&
        includedCount > 0 &&
        (hasPersistentMuse ||
            _museRunning ||
            (engineReady && hasCommitAiSelection));

    return DragTarget<DeskDropPayload>(
      onWillAcceptWithDetails: (d) =>
          d.data.isStash ||
          (d.data.isDesk && !p.equals(d.data.deskPath!, repoPath)),
      onAcceptWithDetails: (d) {
        if (d.data.isStash) {
          _handleStashDump(context, d.data.stashIndex!, d.data.label, repoPath);
        } else {
          _handleDeskDump(context, d.data.deskPath!, d.data.label, repoPath);
        }
      },
      builder: (ctx, candidateData, rejectedData) {
        final dragActive = candidateData.isNotEmpty;
        return Stack(
          children: [
            Row(
              children: [
                MaterialSurface(
                  tone: AppMaterialTone.surface1,
                  radius: 0,
                  border: Border(
                    right: BorderSide(
                        color: t.chromeBorder.withValues(alpha: 0.15)),
                  ),
                  elevated: false,
                  width: _leftPanelWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // (The IN FLIGHT strip used to live here as a
                      // compact chip row above the file list. It has moved
                      // to the History page where the broader "other
                      // worktrees with outgoing work" surface lives —
                      // hovering a chip there previews the desk's
                      // diverged commits in-place. One canonical home for
                      // the affordance instead of two parallel strips.)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 10, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final color = includedCount == 0
                                      ? t.textMuted.withValues(alpha: 0.55)
                                      : t.textMuted;
                                  final style = TextStyle(
                                    color: color,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  );
                                  if (includedCount == 0) {
                                    return Text('None', style: style,
                                        maxLines: 1);
                                  }
                                  final n = status.files.length;
                                  final staged = stagedCount > 0
                                      ? ' · $stagedCount staged'
                                      : '';
                                  final full = includedCount == n
                                      ? 'All $n file${n == 1 ? "" : "s"}$staged'
                                      : '$includedCount of $n$staged';
                                  final tp = TextPainter(
                                    text: TextSpan(text: full, style: style),
                                    maxLines: 1,
                                    textDirection: TextDirection.ltr,
                                  )..layout();
                                  if (tp.width <= constraints.maxWidth) {
                                    return Text(full, style: style,
                                        maxLines: 1);
                                  }
                                  final short = includedCount == n
                                      ? 'All $n$staged'
                                      : '$includedCount of $n$staged';
                                  return Text(short, style: style,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis);
                                },
                              ),
                            ),
                            _ConstellationToggleBtn(
                              tokens: t,
                              active: _constellationOpen,
                              enabled: status.files.length >= 2,
                              onToggle: _toggleAtlasOpen,
                            ),
                            const SizedBox(width: 6),
                            _SmartSelectBtn(
                              allSelected: status.files.isNotEmpty &&
                                  includedCount == status.files.length,
                              noneSelected: includedCount == 0,
                              enabled:
                                  !_actionRunning && status.files.isNotEmpty,
                              tokens: t,
                              onSelectAll: () => _includeAll(status),
                              onDeselectAll: () => setState(() {
                                _includedPaths.clear();
                                _actionError = null;
                              }),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            if (conflictedPaths.isNotEmpty)
                              _MergeResolveStrip(
                                conflictedPaths: conflictedPaths,
                                totalHunks: null,
                                busy: _mergeResolving,
                                onResolve: (categoryId) =>
                                    _resolveMergeConflicts(
                                        repoPath, categoryId),
                              ),
                            Expanded(
                              child: Stack(children: [
                                Positioned.fill(
                                  child: Builder(builder: (context) {
                                    // `clusters` hoisted at build-method scope so the
                                    // header + list share the same clustering.
                                    final fileByPath = {
                                      for (final f in status.files) f.path: f
                                    };
                                    final ordered = <RepositoryStatusFile>[
                                      for (final p in orderedPaths)
                                        if (fileByPath[p] != null)
                                          fileByPath[p]!,
                                    ];
                                    // Defensive: any file that didn't land in ordered.
                                    final orderedSet = orderedPaths.toSet();
                                    for (final f in status.files) {
                                      if (!orderedSet.contains(f.path)) {
                                        ordered.add(f);
                                      }
                                    }
                                    if (_constellationOpen &&
                                        status.files.length >= 2) {
                                      final obsEngine = context.read<LogosGitState>().engineFor(repoPath);
                                      final obsCounts = <String, int>{};
                                      if (obsEngine != null) {
                                        for (final entry in obsEngine.stats.reviewersByPath.entries) {
                                          obsCounts[entry.key] = entry.value.length;
                                        }
                                      }
                                      return FileConstellation(
                                        files: ordered,
                                        clusters: clusters,
                                        matrix: couplingMatrix,
                                        changeWeights: _changeWeights,
                                        includedPaths: _includedPaths,
                                        tokens: t,
                                        observerCounts: obsCounts,
                                        onToggleIncluded: (path, value) =>
                                            _toggleIncluded(path, value),
                                        onCarve: (paths) {
                                          // Carve / untie reshape the
                                          // selection but don't close
                                          // open drawers — the user
                                          // can re-run from the
                                          // toolbar if they want
                                          // results for the new set.
                                          setState(() {
                                            _includedPaths
                                              ..clear()
                                              ..addAll(paths);
                                            _actionError = null;
                                          });
                                        },
                                        onUntieCluster: (paths) {
                                          setState(() {
                                            _includedPaths.removeAll(paths);
                                            _actionError = null;
                                          });
                                        },
                                        onSelectDiff: (path) =>
                                            _loadDiff(repoPath, path),
                                      );
                                    }
                                    // Keep the path lookup used by
                                    // `_ensureFileVisibleInChangesList` in
                                    // sync with whatever the list is
                                    // currently rendering. Cheap — same
                                    // order the ListView is about to iterate.
                                    _changesListPaths = [
                                      for (final f in ordered) f.path,
                                    ];
                                    return ListView.builder(
                                      controller: _changesListCtrl,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      itemCount: ordered.length,
                                      itemBuilder: (ctx, i) {
                                        final file = ordered[i];
                                        final cid =
                                            clusters.byPath[file.path] ??
                                                FileClusters.clusterIdIsolated;
                                        final prevCid = i > 0
                                            ? (clusters.byPath[
                                                    ordered[i - 1].path] ??
                                                FileClusters.clusterIdIsolated)
                                            : null;
                                        final nextCid = i < ordered.length - 1
                                            ? (clusters.byPath[
                                                    ordered[i + 1].path] ??
                                                FileClusters.clusterIdIsolated)
                                            : null;
                                        final showGap =
                                            prevCid != null && prevCid != cid;
                                        final inRealCluster = cid !=
                                            FileClusters.clusterIdIsolated;
                                        // Stripe fuses with neighbour's stripe iff
                                        // same real cluster AND no gap boundary.
                                        final connectTop = inRealCluster &&
                                            prevCid == cid &&
                                            !showGap;
                                        final connectBottom = inRealCluster &&
                                            nextCid != null &&
                                            nextCid == cid;
                                        // Peer emphasis: when the mouse is on
                                        // another row's stripe in the same cluster,
                                        // look up the coupling score between this
                                        // file and the subject. Null = not in the
                                        // hovered cluster (leave row unchanged).
                                        final subjectPath = _railHoverPath;
                                        final subjectCid = subjectPath == null
                                            ? null
                                            : clusters.byPath[subjectPath];
                                        double? peerScore;
                                        bool isRailSubject = false;
                                        if (subjectPath != null &&
                                            subjectCid != null &&
                                            subjectCid ==
                                                FileClusters
                                                    .clusterIdIsolated) {
                                          // Hovered row is isolated — no peers to light up.
                                        } else if (subjectPath != null &&
                                            subjectCid == cid &&
                                            inRealCluster) {
                                          if (subjectPath == file.path) {
                                            isRailSubject = true;
                                            peerScore = 1.0;
                                          } else if (couplingMatrix != null) {
                                            peerScore = _cachedPeerScore(
                                                subjectPath,
                                                file.path,
                                                couplingMatrix);
                                          }
                                        }
                                        final row = _FileRow(
                                          file: file,
                                          tokens: t,
                                          clusterColor:
                                              t.clusterStripeColor(cid),
                                          stripeConnectTop: connectTop,
                                          stripeConnectBottom: connectBottom,
                                          isDiffSelected:
                                              activeDiffPath == file.path,
                                          included: _includedPaths
                                              .contains(file.path),
                                          inRealCluster: inRealCluster,
                                          peerScore: peerScore,
                                          isRailSubject: isRailSubject,
                                          dimOpacity: _fileDimFor(file.path),
                                          onRailEnter: inRealCluster
                                              ? () {
                                                  if (_railHoverPath !=
                                                      file.path) {
                                                    setState(() =>
                                                        _railHoverPath =
                                                            file.path);
                                                  }
                                                }
                                              : null,
                                          onRailExit: () {
                                            if (_railHoverPath == file.path) {
                                              setState(
                                                  () => _railHoverPath = null);
                                            }
                                          },
                                          onTap: includedFiles.length > 1
                                              ? () {
                                                  if (_includedPaths
                                                      .contains(file.path)) {
                                                    _jumpToMultiDiffPath(
                                                        file.path);
                                                  } else {
                                                    _inspectSingleDiff(
                                                        repoPath, file.path);
                                                  }
                                                }
                                              : () => _loadDiff(
                                                  repoPath, file.path),
                                          onIncludeChanged: (value) =>
                                              _toggleIncluded(file.path, value),
                                          onClusterToggle: inRealCluster
                                              ? () {
                                                  final groupPaths = [
                                                    for (final entry in clusters
                                                        .byPath.entries)
                                                      if (entry.value == cid)
                                                        entry.key,
                                                  ];
                                                  _toggleGroup(groupPaths);
                                                }
                                              : null,
                                          onSecondaryTap: (pos) =>
                                              _showFileContextMenu(
                                                  context, pos, file, repoPath),
                                        );
                                        // Key the row so
                                        // `_ensureFileVisibleInChangesList`
                                        // can find it for ensureVisible.
                                        // The key is keyed by file.path
                                        // (stable across rebuilds) so the
                                        // same GlobalKey follows the row
                                        // as list ordering changes.
                                        final keyed = KeyedSubtree(
                                          key: _fileRowKeys.putIfAbsent(
                                              file.path, () => GlobalKey()),
                                          child: row,
                                        );
                                        if (showGap) {
                                          return Column(children: [
                                            const SizedBox(height: 4),
                                            keyed,
                                          ]);
                                        }
                                        return keyed;
                                      },
                                    );
                                  }),
                                ),
                                if (_dejaVuScore > 0)
                                  Positioned(
                                    right: 12,
                                    top: 12,
                                    child: _DejaVuGlyph(
                                      tokens: t,
                                      score: _dejaVuScore,
                                      ghostCount: _dejaVuGhostCount,
                                    ),
                                  ),
                                Positioned(
                                  right: 12,
                                  bottom: 12,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (couplingMatrix != null &&
                                          includedCount > 0)
                                        Builder(builder: (ctx) {
                                          final nudges = suggestMissingPeers(
                                            selected: _includedPaths,
                                            allChanged:
                                                status.files.map((f) => f.path),
                                            matrix: couplingMatrix,
                                          );
                                          if (nudges.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: _CouplingNudgeBanner(
                                              tokens: t,
                                              nudges: nudges,
                                              onAdd: (path) =>
                                                  _toggleIncluded(path, true),
                                            ),
                                          );
                                        }),
                                      _ShelfControl(
                                        tokens: t,
                                        count: _stashes.length,
                                        loading: _stashesLoading,
                                        expanded: _stashesExpanded,
                                        canShelve: status.files.isNotEmpty,
                                        onShelve: status.files.isNotEmpty
                                            ? () => _shelveAll(repoPath)
                                            : null,
                                        onToggleExpanded: _stashes.isEmpty
                                            ? null
                                            : () => setState(() =>
                                                _stashesExpanded =
                                                    !_stashesExpanded),
                                      ),
                                    ],
                                  ),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),
                      MaterialSurface(
                        tone: AppMaterialTone.surface0,
                        radius: 0,
                        border: Border(
                          top: BorderSide(
                            color: t.chromeBorder.withValues(alpha: 0.15),
                          ),
                        ),
                        elevated: false,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // The shelve button itself now floats over the
                            // bottom-right of the file list (see the Stack
                            // wrapping the file-list Expanded). The drawer
                            // it controls still expands here in the
                            // commit-composer area — toggling the floating
                            // button raises this drawer.
                            if (_stashesExpanded && _stashes.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 2),
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxHeight: 360),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    itemCount: _stashes.length,
                                    itemBuilder: (ctx, i) {
                                      final stash = _stashes[i];
                                      final isPeeking =
                                          _stashPeekIndex == stash.index;
                                      final isOpen = _stashOpenIndices
                                          .contains(stash.index);
                                      final files = _stashFiles[stash.index];
                                      final shape = _stashShapes[stash.index];
                                      final label =
                                          _StashDrawerCardState._displayLabel(
                                              stash.message);
                                      return LongPressDraggable<
                                          DeskDropPayload>(
                                        data: DeskDropPayload.stash(
                                          index: stash.index,
                                          label: label,
                                        ),
                                        dragAnchorStrategy:
                                            pointerDragAnchorStrategy,
                                        feedback: _StashDragFeedback(
                                          tokens: t,
                                          label: label,
                                          shape: shape,
                                        ),
                                        child: _StashDrawerCard(
                                          tokens: t,
                                          stash: stash,
                                          isPeeking: isPeeking,
                                          isOpen: isOpen,
                                          files: files,
                                          shape: shape,
                                          currentPaths: status.files
                                              .map((f) => f.path)
                                              .toSet(),
                                          filesLoading: _stashFilesLoading
                                              .contains(stash.index),
                                          onToggleOpen: () => _toggleStashOpen(
                                              repoPath, stash.index),
                                          onPickUp: () => _pickUpStash(
                                              repoPath, stash.index),
                                          onPeek: () =>
                                              _peekStash(repoPath, stash.index),
                                          onToss: () =>
                                              _tossStash(repoPath, stash.index),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Focus(
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }
                                // Tab-to-accept the dream hint when
                                // the composer is empty and a phrase
                                // is waiting. Otherwise Tab passes
                                // through to normal focus traversal.
                                if (event.logicalKey ==
                                        LogicalKeyboardKey.tab &&
                                    !_shapeMode &&
                                    _commitMsgCtrl.text.isEmpty) {
                                  final dreamed = _commitDream.value?.phrase;
                                  if (dreamed != null && dreamed.isNotEmpty) {
                                    _commitMsgCtrl.text = dreamed;
                                    _commitMsgCtrl.selection =
                                        TextSelection.collapsed(
                                      offset: dreamed.length,
                                    );
                                    return KeyEventResult.handled;
                                  }
                                }
                                // Esc in ask-mode → exit back to the
                                // commit draft. Sentence is preserved
                                // in _shapeCtrl for next time.
                                if (event.logicalKey ==
                                        LogicalKeyboardKey.escape &&
                                    _shapeMode) {
                                  _toggleShapeMode();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey !=
                                    LogicalKeyboardKey.enter) {
                                  return KeyEventResult.ignored;
                                }
                                final ctrlOrMeta = HardwareKeyboard
                                        .instance.isControlPressed ||
                                    HardwareKeyboard.instance.isMetaPressed;
                                if (!ctrlOrMeta) return KeyEventResult.ignored;
                                // Ctrl/Cmd+Enter routing:
                                //   - shape-mode → fire the ask
                                //   - commit-mode → run the commit
                                if (_shapeMode) {
                                  final text = _shapeCtrl.text.trim();
                                  if (text.isEmpty || _shaping) {
                                    return KeyEventResult.handled;
                                  }
                                  final cats = _shapeCategories(aiSettings);
                                  if (cats.isEmpty) {
                                    return KeyEventResult.handled;
                                  }
                                  final cat = cats[_shapeCategoryIndex.clamp(
                                      0, cats.length - 1)];
                                  _askInPanel(repoPath, status, text, cat);
                                  return KeyEventResult.handled;
                                }
                                _commit(
                                  repoPath,
                                  status,
                                  mode: primaryAction.syncAfterCommit
                                      ? _CommitRunMode.commitAndSync
                                      : _CommitRunMode.commitOnly,
                                );
                                return KeyEventResult.handled;
                              },
                              child: Builder(builder: (context) {
                                // Reuse the outer-scope `engineReady`
                                // (computed once per page build above
                                // via context.select). It already
                                // triggers the rebuild on engine-ready
                                // flip, so re-subscribing here would
                                // duplicate the listener for no extra
                                // signal — the first-dream-after-cold-
                                // start landing is preserved by the
                                // outer subscription.
                                if (!_shapeMode &&
                                    _commitMsgCtrl.text.trim().isEmpty &&
                                    status.files.isNotEmpty) {
                                  // Intentionally doesn't encode the
                                  // user's file selection — the phrase
                                  // is the engine's voice, not a diff
                                  // summary, and shouldn't re-roll on
                                  // every include/exclude toggle. Diff
                                  // content is still what the engine
                                  // reads at compute time; it just
                                  // doesn't re-trigger on selection.
                                  final sig =
                                      '$repoPath|${engineReady ? 'rdy' : 'wait'}';
                                  final allPaths =
                                      status.files.map((f) => f.path).toList();
                                  _commitDream.schedule(
                                    sig,
                                    () => _computeCommitDream(
                                      repoPath: repoPath,
                                      includedPaths: allPaths,
                                    ),
                                  );
                                }
                                return _CommitComposerField(
                                  tokens: t,
                                  // Bind the active controller based on
                                  // shape-mode. Unbound controller keeps
                                  // its text so exiting ask-mode restores
                                  // the commit draft in progress.
                                  controller:
                                      _shapeMode ? _shapeCtrl : _commitMsgCtrl,
                                  focusNode: _shapeMode
                                      ? _shapeFocus
                                      : _commitMsgFocusNode,
                                  hintText: _shapeMode
                                      ? _askHintForGuardrail(
                                          preferences.guardrailStage)
                                      : _composeHint(),
                                  shapeMode: _shapeMode,
                                  dreamHint: _shapeMode
                                      ? null
                                      : _commitDream.value?.phrase,
                                  dreamThinking: _commitDream.thinking,
                                  enabled: !_actionRunning,
                                  onChanged: (value) {
                                    if (!_shapeMode) {
                                      _saveCommitDraft(value);
                                    }
                                    setState(() {});
                                  },
                                  aiEnabled: canGenerate,
                                  aiLoading:
                                      _generateRunning || _commitAiLoading,
                                  // success = transient celebration flash;
                                  // unread = persistent half-lit while a
                                  // terminal record waits with no drawer
                                  // open. Generate has no drawer, so
                                  // "unread" here is just "result waiting
                                  // to be applied by a re-click" — the
                                  // generate complete branch already
                                  // applies the message synchronously
                                  // when the user is on the originating
                                  // repo, so unread fires only for the
                                  // cross-repo "completed elsewhere" case.
                                  aiSuccess: _generateFlash,
                                  aiUnread:
                                      _isUnreadFor(AiActivityKind.generate),
                                  aiTooltip: _commitAiTooltip(
                                      aiSettings, includedCount),
                                  reviewEnabled: canReview,
                                  reviewLoading: _reviewRunning,
                                  reviewSuccess: _reviewFlash,
                                  reviewUnread:
                                      _isUnreadFor(AiActivityKind.review),
                                  reviewVerdict: _reviewResult?.verdict,
                                  reviewTooltip: _reviewAiTooltip(
                                      aiSettings,
                                      includedCount,
                                      preferences.guardrailStage),
                                  onGenerate: () => _generateCommitMessage(
                                    repoPath,
                                    status,
                                  ),
                                  onReview: () {
                                    if (hasPersistentReview) {
                                      _showExistingReview();
                                      return;
                                    }
                                    _reviewCommit(repoPath, status);
                                  },
                                  museEnabled: canMuse,
                                  museLoading: _museRunning,
                                  museSuccess: _museFlash,
                                  museUnread: _isUnreadFor(AiActivityKind.muse),
                                  museTooltip:
                                      _museTooltip(aiSettings, includedCount),
                                  onMuse: () {
                                    if (_museResult != null ||
                                        _museError != null) {
                                      _openDrawerFor(AiActivityKind.muse);
                                      return;
                                    }
                                    _runMuse(repoPath, status);
                                  },
                                  // ◈ shape: toggles the composer between
                                  // commit and ask modes. Pressing the ask
                                  // submit button opens the ask drawer.
                                  // Engine-ready gates this so the user
                                  // can't enter shape mode before the
                                  // LogosGit engine has resolved — ask's
                                  // semantic-search pipeline depends on
                                  // the engine for grounding citations,
                                  // so a click pre-engine would either
                                  // crash on null or produce a degraded
                                  // result without the diff context.
                                  // Already-in-shape-mode is exempt so a
                                  // mid-resolve repo switch doesn't trap
                                  // the user with no exit affordance.
                                  shapeEnabled: status.files.isNotEmpty &&
                                      !_actionRunning &&
                                      !_shaping &&
                                      (engineReady || _shapeMode),
                                  shapeLoading: _shaping,
                                  shapeTooltip: _shapeMode
                                      ? 'exit · restore your commit draft'
                                      : 'ask the manifold',
                                  onToggleShape: (status.files.isEmpty ||
                                          (!engineReady && !_shapeMode))
                                      ? null
                                      : _toggleShapeMode,
                                  hideAi: preferences.hideAiFeatures,
                                  tags: _commitTags,
                                  suggestedTags: _suggestedTags,
                                  onTagAdded: (tag) {
                                    if (!_commitTags.contains(tag)) {
                                      setState(() => _commitTags.add(tag));
                                    }
                                  },
                                  onTagRemoved: (tag) =>
                                      setState(() => _commitTags.remove(tag)),
                                );
                              }),
                            ),
                            const SizedBox(height: 8),
                            if (_shapeMode && !preferences.hideAiFeatures)
                              _ShapeAskButton(
                                tokens: t,
                                categories: _shapeCategories(aiSettings),
                                categoryIndex: _shapeCategoryIndex,
                                busy: _shaping,
                                // Submit gated on engine-ready too —
                                // even though the user has already
                                // entered shape mode, kicking off a
                                // run before the engine resolves would
                                // produce a citation-less answer
                                // (degraded). Letting the user wait at
                                // the disabled submit until the engine
                                // lands is honest signalling.
                                enabled: !_actionRunning &&
                                    engineReady &&
                                    _shapeCtrl.text.trim().isNotEmpty,
                                onCycle: () {
                                  final cats = _shapeCategories(aiSettings);
                                  if (cats.isEmpty) return;
                                  setState(() => _shapeCategoryIndex =
                                      (_shapeCategoryIndex + 1) % cats.length);
                                },
                                onCycleBack: () {
                                  final cats = _shapeCategories(aiSettings);
                                  if (cats.length < 2) return;
                                  setState(() => _shapeCategoryIndex =
                                      (_shapeCategoryIndex - 1 + cats.length) %
                                          cats.length);
                                },
                                onAsk: () {
                                  final text = _shapeCtrl.text.trim();
                                  if (text.isEmpty) return;
                                  final cats = _shapeCategories(aiSettings);
                                  if (cats.isEmpty) return;
                                  final cat = cats[_shapeCategoryIndex.clamp(
                                      0, cats.length - 1)];
                                  _askInPanel(repoPath, status, text, cat);
                                },
                              )
                            else
                              // Right-click on the button reveals the
                              // amend variants — no visible chip /
                              // toggle clutters the base UI. Discovery
                              // path: standard "more options" mental
                              // model on a primary action button.
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onSecondaryTapDown: (d) =>
                                    _showCommitContextMenu(
                                  d.globalPosition,
                                  repoPath,
                                  status,
                                  primaryAction,
                                ),
                                child: _SplitCommitBtn(
                                  label: _actionRunning
                                      ? 'Working…'
                                      : (_commitOnlyMode
                                          ? 'Commit only'
                                          : primaryAction.label),
                                  alternateLabel: _commitOnlyMode
                                      ? primaryAction.label
                                      : 'Commit only',
                                  commitOnlyMode: _commitOnlyMode,
                                  t: t,
                                  enabled: canCommit,
                                  aiGenerating:
                                      _generateRunning || _commitAiLoading,
                                  actionRunning: _actionRunning,
                                  onCommit: () => _commit(
                                    repoPath,
                                    status,
                                    mode: _commitOnlyMode
                                        ? _CommitRunMode.commitOnly
                                        : (primaryAction.syncAfterCommit
                                            ? _CommitRunMode.commitAndSync
                                            : _CommitRunMode.commitOnly),
                                  ),
                                  onToggleMode: () => setState(
                                      () => _commitOnlyMode = !_commitOnlyMode),
                                ),
                              ),
                            if (_actionError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxHeight: 80),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      _actionError!,
                                      style: TextStyle(
                                        color: t.stateConflicted,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _PanelDivider(
                  tokens: t,
                  onDrag: (dx) => setState(() {
                    _leftPanelWidth = (_leftPanelWidth + dx)
                        .clamp(_minLeftPanelWidth, _maxLeftPanelWidth);
                  }),
                  onDragEnd: () => context
                      .read<PreferencesState>()
                      .setChangesPanelWidth(_leftPanelWidth.round()),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      // Stash peek view
                      if (_stashPeekIndex != null && _stashPeekDiff != null) {
                        final peekStash = _stashes
                            .where((s) => s.index == _stashPeekIndex)
                            .firstOrNull;
                        final peekLabel =
                            peekStash?.message ?? 'stash@{$_stashPeekIndex}';
                        return DiffShell(
                          key: ValueKey('stash-peek-$_stashPeekIndex'),
                          filePath: 'filed: $peekLabel',
                          diffContent: _stashPeekDiff,
                          loading: false,
                          error: null,
                          tokens: t,
                          repositoryPath: repoPath,
                          couplingMatrix: context
                              .read<FileCouplingState>()
                              .matrixFor(repoPath),
                          symbolCoupling: _symbolCoupling,
                          onOpenRelatedPath: (path) =>
                              _inspectSingleDiff(repoPath, path),
                        );
                      }
                      if (_isAskDrawerOpen && !preferences.hideAiFeatures) {
                        return MaterialSurface(
                          tone: AppMaterialTone.surface0,
                          radius: 0,
                          borderAlpha: 0,
                          elevated: false,
                          child: _ShapeAskPane(
                            tokens: t,
                            loading: _shaping,
                            question: _askQuestion,
                            answer: _askAnswer,
                            error: _askError,
                            onBack: _closeDrawer,
                            onDismissAnswer: () {
                              final site = _activitySite();
                              if (site != null) {
                                site.state.clear(
                                  repoPath: site.repoPath,
                                  kind: AiActivityKind.ask,
                                );
                              }
                              setState(() {});
                            },
                            onCitationTap: (path, line) => _jumpToMultiDiffPath(
                                path,
                                fallbackStartLine: line),
                          ),
                        );
                      }
                      if (_isMuseDrawerOpen && !preferences.hideAiFeatures) {
                        return MaterialSurface(
                          tone: AppMaterialTone.surface0,
                          radius: 0,
                          borderAlpha: 0,
                          elevated: false,
                          child: _MusePane(
                            tokens: t,
                            loading: _museRunning,
                            error: _museError,
                            result: _museResult,
                            staleScope: _isMuseScopeStale(),
                            reasoningEffort:
                                _snapshotMuseSynthEffort[repoPath],
                            fastMode:
                                _snapshotMuseSynthFast[repoPath] ?? false,
                            guardrailLabel: _guardrailLabelForStage(
                                _snapshotMuseGuardrailStage[repoPath] ??
                                    preferences.guardrailStage),
                            onBack: _closeDrawer,
                            onRerun: () {
                              // Drop the existing record so _runMuse
                              // doesn't see a same-scope match and
                              // short-circuit to "show existing."
                              context.read<AiActivityState>().clear(
                                    repoPath: repoPath,
                                    kind: AiActivityKind.muse,
                                  );
                              _runMuse(repoPath, status);
                            },
                            onCopy: _museResult == null
                                ? null
                                : (subset) => _copyMuseReport(_museResult!,
                                    subset: subset),
                          ),
                        );
                      }
                      if (_isReviewDrawerOpen && !preferences.hideAiFeatures) {
                        final stats =
                            (showMultiDiff ? _multiDiffDocument : _diffDocument)
                                    ?.stats ??
                                const DiffStats();

                        return MaterialSurface(
                          tone: AppMaterialTone.surface0,
                          radius: 0,
                          borderAlpha: 0,
                          elevated: false,
                          child: _CommitReviewPane(
                            tokens: t,
                            includedCount: includedCount,
                            diffAdds: stats.adds,
                            diffDels: stats.dels,
                            diffHunks: stats.hunks,
                            modelLabel: _snapshotReviewModelLabel[repoPath] ??
                                _reviewModelLabel(aiSettings),
                            guardrailLabel: _guardrailLabelForStage(
                                _snapshotReviewGuardrailStage[repoPath] ??
                                    preferences.guardrailStage),
                            guardrailStage:
                                _snapshotReviewGuardrailStage[repoPath] ??
                                    preferences.guardrailStage,
                            reasoningEffort:
                                _snapshotReviewEffort[repoPath],
                            fastMode:
                                _snapshotReviewFast[repoPath] ?? false,
                            loading: _reviewRunning,
                            error: _reviewError,
                            result: _reviewResult,
                            staleScope: _isReviewScopeStale(),
                            traceExpanded: _reviewTraceExpanded,
                            reasoningExpanded: _reviewReasoningExpanded,
                            onToggleTrace: () => setState(
                              () =>
                                  _reviewTraceExpanded = !_reviewTraceExpanded,
                            ),
                            onToggleReasoning: () => setState(
                              () => _reviewReasoningExpanded =
                                  !_reviewReasoningExpanded,
                            ),
                            onCancel: _cancelReviewRequest,
                            onBack: _closeAndResetReviewDrawer,
                            onRerun: () {
                              // Drop the existing record so _reviewCommit
                              // doesn't see a same-scope match and
                              // short-circuit to "show existing" — same
                              // pattern muse's onRerun uses. Without
                              // this, a rerun re-displays the prior
                              // result instead of launching a fresh
                              // run, because the provider record at
                              // the same scope is still terminal.
                              context.read<AiActivityState>().clear(
                                    repoPath: repoPath,
                                    kind: AiActivityKind.review,
                                  );
                              _closeAndResetReviewDrawer();
                              _reviewCommit(repoPath, status);
                            },
                            onCopy: _reviewResult == null
                                ? null
                                : () => _copyReviewReport(_reviewResult!),
                            onOpenFinding: (path, hunkLabel) =>
                                _openReviewFinding(repoPath, path, status,
                                    hunkLabel: hunkLabel),
                          ),
                        );
                      }
                      if (showMultiDiff) {
                        _primeMultiDiff(repoPath, includedFiles);
                        final timelineSections = _buildTimelineSections(
                            includedFiles, _multiDiffSections);
                        final currentTimelineSection =
                            _currentTimelineSectionForPath(
                          timelineSections,
                          _multiDiffCurrentPath,
                        );
                        final currentTimelineIndex =
                            currentTimelineSection == null
                                ? null
                                : timelineSections.indexOf(
                                    currentTimelineSection,
                                  );
                        final multiDiffToolbarLabel = currentTimelineSection ==
                                null
                            ? '${includedFiles.length} selected files'
                            : '${currentTimelineSection.displayName} | ${currentTimelineIndex! + 1} of ${timelineSections.length}';
                        return MaterialSurface(
                          tone: AppMaterialTone.surface0,
                          radius: 0,
                          borderAlpha: 0,
                          elevated: false,
                          child: Column(
                            children: [
                              _MultiDiffTimelineStrip(
                                tokens: t,
                                sections: timelineSections,
                                currentPath: _multiDiffCurrentPath,
                                onSelectPath: (section) => _jumpToMultiDiffPath(
                                  section.path,
                                  fallbackStartLine: section.startLine,
                                ),
                              ),
                              Expanded(
                                // Track vertical scroll to sync the timeline strip.
                                // Intentionally omits depth==0: the DiffShell's ListView
                                // is nested inside a horizontal SingleChildScrollView,
                                // so its events arrive at depth>0.
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: (notification) {
                                    if (notification.metrics.axis !=
                                        Axis.vertical) {
                                      return false;
                                    }
                                    // UserScrollNotification flags the start and
                                    // end of user-initiated scrolling. Programmatic
                                    // animateTo never fires it — which is exactly
                                    // the signal we need to ignore jump-induced
                                    // intermediate offsets.
                                    if (notification
                                        is UserScrollNotification) {
                                      if (notification.direction !=
                                          ScrollDirection.idle) {
                                        _multiDiffUserDriving = true;
                                      }
                                      return false;
                                    }
                                    // On scroll end, only recompute currentPath
                                    // if the scroll was user-driven. A
                                    // programmatic jump (click in the file tree,
                                    // tap on the timeline rail) already set the
                                    // path explicitly — the probe-offset logic
                                    // would otherwise flip it to the NEXT file
                                    // when the target file is short (< viewport
                                    // probe distance).
                                    if (notification is ScrollEndNotification) {
                                      if (_multiDiffUserDriving) {
                                        _handleMultiDiffScroll(
                                          notification.metrics,
                                        );
                                      }
                                      _multiDiffUserDriving = false;
                                      return false;
                                    }
                                    // Live updates only while the user is
                                    // driving — animation frames from a jump
                                    // are skipped, eliminating the flicker.
                                    if (notification
                                            is ScrollUpdateNotification &&
                                        _multiDiffUserDriving) {
                                      _handleMultiDiffScroll(
                                        notification.metrics,
                                      );
                                    }
                                    return false;
                                  },
                                  child: DiffShell(
                                    key: const ValueKey('multi-diff-shell'),
                                    filePath:
                                        '${includedFiles.length} selected files',
                                    toolbarFilePath: currentTimelineSection
                                            ?.path ??
                                        '${includedFiles.length} selected files',
                                    toolbarLabel: multiDiffToolbarLabel,
                                    toolbarTooltip:
                                        currentTimelineSection?.path,
                                    document: _multiDiffDocument,
                                    loading: _multiDiffLoading,
                                    error: _multiDiffError,
                                    tokens: t,
                                    repositoryPath: repoPath,
                                    jumpToLineIndex: _multiDiffJumpLineIndex,
                                    jumpToLineRequestId:
                                        _multiDiffJumpRequestId,
                                    showFileHeader: false,
                                    enableStaging: true,
                                    couplingMatrix: context
                                        .read<FileCouplingState>()
                                        .matrixFor(repoPath),
                                    symbolCoupling: _symbolCoupling,
                                    onOpenRelatedPath: (path) {
                                      if (includedFiles
                                          .any((file) => file.path == path)) {
                                        _jumpToMultiDiffPath(path);
                                        return;
                                      }
                                      _pushAndInspectSingleDiff(repoPath, path);
                                    },
                                    onPinnedFileFocused:
                                        _ensureFileVisibleInChangesList,
                                    onNavigateBack: _diffNavStack.isEmpty
                                        ? null
                                        : () => _navigateBackDiff(repoPath),
                                    onStagingApplied: () {
                                      unawaited(_loadMultiDiff(
                                        repoPath,
                                        includedFiles,
                                      ));
                                      unawaited(repo.refreshStatus());
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return MaterialSurface(
                        tone: AppMaterialTone.surface0,
                        radius: 0,
                        borderAlpha: 0,
                        elevated: false,
                        child: _selectedDiffPath == null
                            ? const AppStatusView(
                                title: 'No file selected',
                                message:
                                    'Select a changed file to inspect its diff.',
                                compact: true,
                              )
                            : DiffShell(
                                filePath:
                                    _visibleDiffPath ?? _selectedDiffPath!,
                                document: _diffDocument,
                                loading: _diffLoading,
                                error: _diffError,
                                tokens: t,
                                repositoryPath: repoPath,
                                enableStaging: true,
                                couplingMatrix: context
                                    .read<FileCouplingState>()
                                    .matrixFor(repoPath),
                                symbolCoupling: _symbolCoupling,
                                onOpenRelatedPath: (path) {
                                  if (includedFiles
                                      .any((file) => file.path == path)) {
                                    _jumpToMultiDiffPath(path);
                                    return;
                                  }
                                  if (includedFiles.length > 1) {
                                    _pushAndInspectSingleDiff(repoPath, path);
                                    return;
                                  }
                                  // Single-file selection context — push the
                                  // current focus then load the next one so
                                  // back restores the previous diff.
                                  final current =
                                      _visibleDiffPath ?? _selectedDiffPath;
                                  if (current != null && current != path) {
                                    _diffNavStack.add(current);
                                  }
                                  unawaited(_loadDiff(repoPath, path));
                                },
                                onPinnedFileFocused:
                                    _ensureFileVisibleInChangesList,
                                onNavigateBack: _diffNavStack.isEmpty
                                    ? null
                                    : () => _navigateBackDiff(repoPath),
                                onStagingApplied: () {
                                  final path =
                                      _visibleDiffPath ?? _selectedDiffPath;
                                  if (path != null) {
                                    unawaited(_loadDiff(repoPath, path));
                                  }
                                  unawaited(repo.refreshStatus());
                                },
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: statusLoading ? 1 : 0,
                duration: const Duration(milliseconds: 80),
                child: TopProgressLine(color: t.accentBright),
              ),
            ),
            // (Discard undo pill now lives in the app-shell overlay via
            // `UndoCoordinator` — same visual anchor, handled globally.)
            // Drop-zone affordance: when a desk is actively being dragged
            // over us, pulse an accent border + a centered label so the
            // user knows "yes, I'll catch that." Positioned.fill with
            // IgnorePointer so it never steals the drag's hit target.
            if (dragActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.accentBright.withValues(alpha: 0.06),
                      border: Border.all(
                        color: t.accentBright.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: t.accentBright, width: 1),
                      ),
                      child: Text(
                        'drop to bring changes from this desk here',
                        style: TextStyle(
                          color: t.textStrong,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CombinedDiffSection {
  final String path;
  final String displayName;
  final int index;
  final int startLine;

  const _CombinedDiffSection({
    required this.path,
    required this.displayName,
    required this.index,
    required this.startLine,
  });
}

class _CachedMultiDiff {
  final String scopeKey;
  final DiffDocument? document;
  final Map<String, String> fileKeyByPath;

  const _CachedMultiDiff({
    required this.scopeKey,
    required this.document,
    required this.fileKeyByPath,
  });

  List<_CombinedDiffSection> get sections =>
      document?.sections
          .map((section) => _CombinedDiffSection(
                path: section.path,
                displayName: section.displayName,
                index: section.index,
                startLine: section.startLine,
              ))
          .toList(growable: false) ??
      const <_CombinedDiffSection>[];
}

/// Re-rank `clusters.orderedPaths` within each cluster by diffusion pull
/// from the currently-staged file set. Cluster boundaries are preserved
/// so the visual grouping (cluster stripes) stays intact; only the
/// member order inside each cluster changes.
/// Sources (files already included) float to the top of their cluster.
/// Remaining members sort by φ descending — the file most strongly
/// coupled to what's staged comes next.
/// Temperature t=0.5: tight, 1-hop-ish. "Files that historically move
/// with what you just staged," not the broader architectural orbit.
List<String> _logosRerankedOrder({
  required FileClusters clusters,
  required LogosGit engine,
  required Set<String> sources,
  double t = 0.5,
  // Coherence threshold for pruning the tail of diffusion results — the
  // larger this is, the tighter the induced subgraph has to stay. The
  // caller typically derives this from `logosPadX` (FOLDER↔HISTORY).
  double coherenceGate = 0.25,
  bool inverted = false,
}) {
  if (sources.isEmpty) return clusters.orderedPaths;
  final scores = engine.diffuse(sources, t: t, coherenceGate: coherenceGate);
  if (scores.isEmpty) return clusters.orderedPaths;
  final phiByPath = <String, double>{
    for (final s in scores) s.path: s.phi,
  };

  // Group cluster members in one pass. Re-scanning the full ordered list
  // for every cluster turns selection churn into quadratic work in the UI
  // path.
  final clusterOrder = <int>[];
  final membersByCluster = <int, List<String>>{};
  for (final path in clusters.orderedPaths) {
    final cid = clusters.byPath[path] ?? FileClusters.clusterIdIsolated;
    final members = membersByCluster.putIfAbsent(cid, () {
      clusterOrder.add(cid);
      return <String>[];
    });
    members.add(path);
  }

  final result = <String>[];
  for (final cid in clusterOrder) {
    final members = membersByCluster[cid]!
      ..sort((a, b) {
        final aIsSource = sources.contains(a);
        final bIsSource = sources.contains(b);
        if (aIsSource != bIsSource) return aIsSource ? -1 : 1;
        final pa = phiByPath[a] ?? 0.0;
        final pb = phiByPath[b] ?? 0.0;
        return inverted ? pa.compareTo(pb) : pb.compareTo(pa);
      });
    result.addAll(members);
  }
  return result;
}

Future<List<String>> _computeLogosRerankedOrder({
  required FileClusters clusters,
  required LogosGit engine,
  required Set<String> sources,
  required double t,
  required double coherenceGate,
  required bool inverted,
}) async {
  // Offloading rerank looked attractive on paper, but in practice it
  // copies the full Logos engine into the isolate. That transfer dwarfs
  // the actual diffuse() cost and shows up as multi-second stalls.
  return _logosRerankedOrder(
    clusters: clusters,
    engine: engine,
    sources: sources,
    t: t,
    coherenceGate: coherenceGate,
    inverted: inverted,
  );
}

List<_CombinedDiffSection> _buildTimelineSections(
  List<RepositoryStatusFile> files,
  List<_CombinedDiffSection> diffSections,
) {
  final seenPaths = <String>{};
  final sections = <_CombinedDiffSection>[];

  for (final section in diffSections) {
    if (!seenPaths.add(section.path)) {
      continue;
    }
    sections.add(
      _CombinedDiffSection(
        path: section.path,
        displayName: section.displayName,
        index: sections.length,
        startLine: section.startLine,
      ),
    );
  }

  for (final file in files) {
    if (!seenPaths.add(file.path)) {
      continue;
    }
    sections.add(
      _CombinedDiffSection(
        path: file.path,
        displayName: file.path.split('/').last,
        index: sections.length,
        startLine: sections.isEmpty ? 0 : sections.last.startLine,
      ),
    );
  }
  return sections;
}

_CombinedDiffSection? _currentTimelineSectionForPath(
  List<_CombinedDiffSection> sections,
  String? currentPath,
) {
  if (sections.isEmpty) return null;
  if (currentPath == null) return sections.first;
  return sections.firstWhere(
    (section) => section.path == currentPath,
    orElse: () => sections.first,
  );
}

class _MultiDiffTimelineStrip extends StatelessWidget {
  final AppTokens tokens;
  final List<_CombinedDiffSection> sections;
  final String? currentPath;
  final ValueChanged<_CombinedDiffSection>? onSelectPath;

  const _MultiDiffTimelineStrip({
    required this.tokens,
    required this.sections,
    required this.currentPath,
    this.onSelectPath,
  });

  @override
  Widget build(BuildContext context) {
    final currentIndex = sections.isEmpty
        ? 0
        : sections.indexWhere((section) => section.path == currentPath);
    final effectiveIndex = currentIndex < 0 ? 0 : currentIndex;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.chromeBorder.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: _MultiDiffProgressRail(
        tokens: tokens,
        sections: sections,
        currentIndex: effectiveIndex,
        onSelectPath: onSelectPath,
      ),
    );
  }
}

class _MultiDiffProgressRail extends StatelessWidget {
  final AppTokens tokens;
  final List<_CombinedDiffSection> sections;
  final int currentIndex;
  final ValueChanged<_CombinedDiffSection>? onSelectPath;

  const _MultiDiffProgressRail({
    required this.tokens,
    required this.sections,
    required this.currentIndex,
    this.onSelectPath,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return MouseRegion(
          cursor: onSelectPath == null || sections.isEmpty
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onSelectPath == null || sections.isEmpty
                ? null
                : (details) => _selectFromOffset(
                      details.localPosition.dx,
                      width,
                    ),
            onHorizontalDragStart: onSelectPath == null || sections.isEmpty
                ? null
                : (details) => _selectFromOffset(
                      details.localPosition.dx,
                      width,
                    ),
            onHorizontalDragUpdate: onSelectPath == null || sections.isEmpty
                ? null
                : (details) => _selectFromOffset(
                      details.localPosition.dx,
                      width,
                    ),
            child: SizedBox(
              width: width,
              height: 28,
              child: CustomPaint(
                size: Size(width, 28),
                painter: _MultiDiffProgressRailPainter(
                  tokens: tokens,
                  count: sections.length,
                  currentIndex: currentIndex,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int _nearestTimelineIndex({
    required double localDx,
    required double width,
    required int count,
  }) {
    if (count <= 1) {
      return 0;
    }
    const horizontalInset = 6.0;
    final clampedWidth =
        width <= horizontalInset * 2 ? horizontalInset * 2 + 1 : width;
    final usableWidth = clampedWidth - (horizontalInset * 2);
    final ratio = ((localDx - horizontalInset) / usableWidth).clamp(0.0, 1.0);
    return (ratio * (count - 1)).round();
  }

  void _selectFromOffset(double localDx, double width) {
    if (onSelectPath == null || sections.isEmpty) {
      return;
    }
    final index = _nearestTimelineIndex(
      localDx: localDx,
      width: width,
      count: sections.length,
    );
    onSelectPath!(sections[index]);
  }
}

class _MultiDiffProgressRailPainter extends CustomPainter {
  final AppTokens tokens;
  final int count;
  final int currentIndex;

  const _MultiDiffProgressRailPainter({
    required this.tokens,
    required this.count,
    required this.currentIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) {
      return;
    }

    const horizontalInset = 6.0;
    const left = horizontalInset;
    final right = size.width - horizontalInset;
    final centerY = size.height / 2;
    final usableWidth = right - left;
    final progress = count == 1 ? 1.0 : currentIndex / (count - 1);
    final markerX = left + usableWidth * progress.clamp(0.0, 1.0);

    final baseRail = Paint()
      ..color = tokens.chromeBorderStrong
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(left, centerY), Offset(right, centerY), baseRail);

    final sampleCount = count < 2
        ? 1
        : count > 44
            ? 44
            : count;

    for (var i = 0; i < sampleCount; i++) {
      final ratio = sampleCount == 1 ? 0.0 : i / (sampleCount - 1);
      final representedIndex =
          sampleCount == 1 ? currentIndex : (ratio * (count - 1)).round();
      final x = left + usableWidth * ratio;
      final isCurrent = representedIndex == currentIndex;
      final radius = isCurrent ? 4.5 : 2.4;
      final fill = Paint()
        ..color = isCurrent
            ? tokens.accentBright
            : tokens.textMuted.withValues(alpha: 0.24);
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
  bool shouldRepaint(covariant _MultiDiffProgressRailPainter oldDelegate) {
    return oldDelegate.count != count ||
        oldDelegate.currentIndex != currentIndex ||
        oldDelegate.tokens != tokens;
  }
}

class _MusePane extends StatefulWidget {
  final AppTokens tokens;
  final bool loading;
  final String? error;
  final AiMuseData? result;
  final String guardrailLabel;
  final String? reasoningEffort;
  final bool fastMode;
  final VoidCallback onBack;
  final VoidCallback onRerun;

  final bool staleScope;

  final void Function(List<AiMuseProposal>? subset)? onCopy;

  const _MusePane({
    required this.tokens,
    required this.loading,
    required this.error,
    required this.result,
    required this.guardrailLabel,
    this.reasoningEffort,
    this.fastMode = false,
    required this.onBack,
    required this.onRerun,
    this.staleScope = false,
    this.onCopy,
  });

  @override
  State<_MusePane> createState() => _MusePaneState();
}

class _MusePaneState extends State<_MusePane> {
  bool _brainstormExpanded = false;
  int? _highlightedIdeaIndex;
  // Selection keyed by object identity. AiMuseProposal doesn't override
  // hashCode/== so default identity semantics apply — two proposals
  // with the same title remain distinct entries. Identity is stable
  // across rebuilds while the result reference holds.
  final Set<AiMuseProposal> _selected = <AiMuseProposal>{};
  AiMuseProposal? _hovered;

  void _toggleSelection(AiMuseProposal p) {
    setState(() {
      if (!_selected.add(p)) _selected.remove(p);
    });
  }

  List<AiMuseProposal> _orderedSelection(AiMuseData r) {
    if (_selected.isEmpty) return const [];
    return r.proposals.where(_selected.contains).toList(growable: false);
  }

  @override
  void didUpdateWidget(covariant _MusePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Result swap (rerun finished) — drop stale references that point
    // at proposals from the previous run.
    if (!identical(oldWidget.result, widget.result)) {
      if (_selected.isNotEmpty) _selected.clear();
      _hovered = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.staleScope)
            _StaleScopeBanner(tokens: t, onRerun: widget.onRerun),
          _museHeader(t),
          const SizedBox(height: 14),
          // While loading, the logos canvas owns the pane. No
          // SingleChildScrollView here — loading screens shouldn't
          // scroll; the visual needs to sit on exactly one panel,
          // sized to fit whatever height the parent hands us.
          if (widget.loading)
            Expanded(child: _museBody(t))
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: _museBody(t),
              ),
            ),
        ],
      ),
    );
  }

  Widget _museHeader(AppTokens t) {
    final result = widget.result;
    final keptLine = result != null && result.totalIdeaCount > 0
        ? 'considered ${result.totalIdeaCount}, kept ${result.keptIdeaCount} with grounding'
        : '';
    return Row(
      children: [
        // Left cluster — wrapped in Expanded so the Flexible kept-line
        // gets all remaining space inside, not a flex-share that it
        // splits with a sibling Spacer. Prior layout used Flexible(1)
        // + Spacer(1), so both got half the remaining width and the
        // text truncated at ~half-row even when the full row had
        // hundreds of pixels of empty space past the kept line.
        Expanded(
          child: Row(
            children: [
              Icon(Icons.bubble_chart_outlined, size: 16, color: t.textFaint),
              const SizedBox(width: 8),
              Text('Muse',
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  )),
              const SizedBox(width: 8),
              Text('· ${widget.guardrailLabel.toLowerCase()}',
                  style: TextStyle(color: t.textFaint, fontSize: 11)),
              if (widget.reasoningEffort != null || widget.fastMode)
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: _ModelGlyphStrip(
                    color: t.chromeAccent,
                    accent: t.accentBright,
                    effort: widget.reasoningEffort,
                    fast: widget.fastMode,
                  ),
                ),
              if (keptLine.isNotEmpty) ...[
                const SizedBox(width: 6),
                // Flexible, not Expanded, so the text takes only what
                // it needs. Ellipsizes only when the window is truly
                // narrow (kept line exceeds available space after
                // icon + Muse + guardrail label).
                Flexible(
                  child: Text('· $keptLine',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textFaint, fontSize: 11)),
                ),
              ],
            ],
          ),
        ),
        // Chips take their intrinsic widths on the right. Mirror the
        // review-pane order: back · copy · rerun.
        const SizedBox(width: 12),
        _GhostActionChip(
            tokens: t, label: 'back to diff', onTap: widget.onBack),
        if (widget.onCopy != null) ...[
          const SizedBox(width: 6),
          _GhostActionChip(
            tokens: t,
            label: _selected.isEmpty
                ? 'copy'
                : 'copy ${_selected.length} selected',
            onTap: () {
              if (_selected.isEmpty) {
                widget.onCopy!(null);
                return;
              }
              final r = widget.result;
              if (r == null) return;
              final subset = _orderedSelection(r);
              if (subset.isEmpty) return;
              widget.onCopy!(subset);
              setState(() => _selected.clear());
            },
          ),
          if (_selected.isNotEmpty) ...[
            const SizedBox(width: 6),
            _GhostActionChip(
              tokens: t,
              label: 'clear',
              onTap: () => setState(() => _selected.clear()),
            ),
          ],
        ],
        const SizedBox(width: 6),
        _GhostActionChip(tokens: t, label: 'rerun', onTap: widget.onRerun),
      ],
    );
  }

  Widget _museBody(AppTokens t) {
    if (widget.loading) {
      // Dreaming text at top, canvas fills the remaining height. The
      // caller wraps this in an `Expanded` (not a scrollview) while
      // loading, so the whole thing fits on one panel — no scroll
      // bar disrupting the visual.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 4),
            child: Center(
              child: _DreamingText(
                text: 'the muse is dreaming...',
                style: TextStyle(color: t.textFaint, fontSize: 12),
              ),
            ),
          ),
          // RepaintBoundary isolates the canvas's 60fps raster layer
          // from the surrounding column. Without it, every ticker
          // frame would invalidate the enclosing composition and
          // force sibling layers (file list, commit message panel)
          // through the compositor even when their contents haven't
          // changed.
          Expanded(
            child: RepaintBoundary(
              child: LogosDiffusionCanvas(tokens: t),
            ),
          ),
        ],
      );
    }
    final err = widget.error;
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Text(err,
            style: const TextStyle(
              color: AppSeverityPalette.caution,
              fontSize: 12,
            )),
      );
    }
    final r = widget.result;
    if (r == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tierSection(t, r, AiMuseIdeaTier.spark, 'SPARK'),
        _tierSection(t, r, AiMuseIdeaTier.current, 'CURRENT'),
        _tierSection(t, r, AiMuseIdeaTier.horizon, 'HORIZON'),
        _tierSection(t, r, AiMuseIdeaTier.fever, 'FEVER'),
        if (r.brainstormIdeas.isNotEmpty) _brainstormReveal(t, r),
        if (r.parseWarnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final warning in r.parseWarnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      warning,
                      style: TextStyle(
                        color: t.textFaint.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Render one ambition tier as a labelled block of proposal cards.
  /// Cards within a tier share a continuous left rail so siblings read
  /// as belonging to one group rather than four loose cards. `fever`
  /// gets a distinctive glyph and accent treatment so the register
  /// reads as different at a glance.
  Widget _tierSection(
      AppTokens t, AiMuseData r, AiMuseIdeaTier tier, String label) {
    final group = r.proposalsForTier(tier);
    if (group.isEmpty) return const SizedBox.shrink();
    final isFever = tier == AiMuseIdeaTier.fever;
    final railColor = isFever
        ? t.accentBright.withValues(alpha: 0.42)
        : t.textFaint.withValues(alpha: 0.32);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isFever ? '☽' : '✦',
                style: TextStyle(
                  color: isFever
                      ? t.accentBright.withValues(alpha: 0.75)
                      : t.accentBright.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isFever
                      ? t.accentBright.withValues(alpha: 0.80)
                      : t.textFaint,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: isFever ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // The continuous rail. The ✦/☽ glyph above sits at x≈4 (icon
          // half-width); aligning the rail at left:5 makes the glyph
          // visually anchor the head of the stem.
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: railColor, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < group.length; i++)
                    _proposalCard(
                      t,
                      group[i],
                      r.brainstormIdeas,
                      r.userBoostedPaths,
                      fever: isFever,
                      isLast: i == group.length - 1,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _proposalCard(
    AppTokens t,
    AiMuseProposal p,
    List<AiMuseIdea> ideas,
    Set<String> userBoostedPaths, {
    required bool fever,
    required bool isLast,
  }) {
    // A proposal is "pulled" when at least one of its cited paths
    // matches a spoke the user yanked during the loading canvas —
    // closes the gesture loop so a physical pull becomes a marker
    // in the rendered result.
    final pulledCitations = userBoostedPaths.isEmpty
        ? const <String>{}
        : {
            for (final c in p.citations)
              if (userBoostedPaths.contains(c)) c
          };
    final isPulled = pulledCitations.isNotEmpty;
    final idea = p.originatingIdeaIndex == null
        ? null
        : ideas.where((i) => i.index == p.originatingIdeaIndex).firstOrNull;
    final highlighted = idea != null && _highlightedIdeaIndex == idea.index;
    final selected = _selected.contains(p);
    final hovered = identical(_hovered, p);

    // Dot color tier: pulled/selected take accent at full strength;
    // hover lifts the resting tone partway so the affordance reads;
    // resting tones are quiet so the rail stays calm at rest.
    final Color dotColor;
    if (isPulled || selected) {
      dotColor = t.accentBright;
    } else if (hovered) {
      dotColor = fever
          ? t.accentBright.withValues(alpha: 0.85)
          : t.textMuted.withValues(alpha: 0.85);
    } else if (fever) {
      dotColor = t.accentBright.withValues(alpha: 0.65);
    } else {
      dotColor = t.textFaint.withValues(alpha: 0.55);
    }
    final dotSize = (selected || isPulled) ? 7.0 : 5.0;

    final bgColor = selected
        ? t.accentBright.withValues(alpha: 0.06)
        : hovered
            ? t.textStrong.withValues(alpha: 0.025)
            : highlighted
                ? t.textStrong.withValues(alpha: 0.04)
                : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = p),
      onExit: (_) => setState(() {
        if (identical(_hovered, p)) _hovered = null;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleSelection(p),
        child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                curve: Curves.easeOut,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(color: bgColor),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPulled) ...[
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: t.accentBright,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('you pulled this',
                              style: TextStyle(
                                color: t.accentBright.withValues(alpha: 0.9),
                                fontSize: 10,
                                letterSpacing: 0.8,
                              )),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    // Title — the proposal's name, displayed with more
                    // weight than the body so the idea is scannable at
                    // a glance.
                    SelectableText(
                      p.title,
                      style: TextStyle(
                        color: t.textStrong,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Vision — the present-tense description of the
                    // future the muse is proposing.
                    SelectableText(
                      p.vision,
                      style: TextStyle(
                        color: t.textStrong,
                        fontSize: 12.5,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Foothold — the grounding sentence. Rendered muted
                    // so it reads as supporting footnote rather than a
                    // claim of equal weight with the vision.
                    _footholdRow(t, p, pulledCitations),
                    if (idea != null) ...[
                      const SizedBox(height: 6),
                      HoverableTap(
                        onTap: () => setState(() {
                          _highlightedIdeaIndex =
                              _highlightedIdeaIndex == idea.index
                                  ? null
                                  : idea.index;
                          _brainstormExpanded = true;
                        }),
                        builder: (context, hovered) => AnimatedDefaultTextStyle(
                          duration: AppMotion.snap,
                          curve: AppMotion.snapCurve,
                          style: TextStyle(
                            color: hovered
                                ? t.textMuted
                                : t.textFaint.withValues(alpha: 0.85),
                            fontSize: 10.5,
                            fontStyle: FontStyle.italic,
                          ),
                          child: Text('from idea: "${idea.text}"'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Node on the rail. Sits at the title baseline so each
              // entry reads as hanging off the shared stem.
              Positioned(
                left: -(dotSize / 2 + 0.5),
                top: 14 + (isPulled ? 17 : 0),
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 110),
                    curve: Curves.easeOut,
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footholdRow(
      AppTokens t, AiMuseProposal p, Set<String> pulledCitations) {
    final footholdStyle = TextStyle(
      color: t.textMuted.withValues(alpha: 0.8),
      fontSize: 11.5,
      height: 1.5,
      fontStyle: FontStyle.italic,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'foothold — ',
              style: footholdStyle.copyWith(
                color: t.textFaint.withValues(alpha: 0.7),
                fontStyle: FontStyle.normal,
                letterSpacing: 0.6,
                fontSize: 10.5,
              ),
            ),
            Expanded(
              child: SelectableText(p.foothold, style: footholdStyle),
            ),
          ],
        ),
        if (p.citations.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in p.citations)
                Text(
                  c,
                  style: TextStyle(
                    color: pulledCitations.contains(c)
                        ? t.accentBright
                        : t.textFaint,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    fontWeight: pulledCitations.contains(c)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _brainstormReveal(AppTokens t, AiMuseData r) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoverableTap(
            onTap: () =>
                setState(() => _brainstormExpanded = !_brainstormExpanded),
            builder: (context, hovered) {
              final color = hovered ? t.textMuted : t.textFaint;
              return Row(
                children: [
                  AnimatedContainer(
                    duration: AppMotion.snap,
                    curve: AppMotion.snapCurve,
                    child: Icon(
                      _brainstormExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 14,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedDefaultTextStyle(
                    duration: AppMotion.snap,
                    curve: AppMotion.snapCurve,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                    child: const Text('brainstorm spew'),
                  ),
                ],
              );
            },
          ),
          if (_brainstormExpanded) ...[
            const SizedBox(height: 8),
            for (final idea in r.brainstormIdeas)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${idea.kept ? '◉' : '·'} ${idea.text}',
                  style: TextStyle(
                    color: idea.kept
                        ? t.textStrong
                        : t.textFaint.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: idea.index == _highlightedIdeaIndex
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Side-pane result display for an ask-in-flight / ask-completed. The
/// input lives in the composer (flipped via ◈); this pane only shows
/// the loading spinner, the answer card, or the error. Matches the
/// muse / review pane shape so the three AI panes feel like siblings.
class _ShapeAskPane extends StatelessWidget {
  final AppTokens tokens;
  final bool loading;
  final String? question;
  final String? answer;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onDismissAnswer;
  final void Function(String path, int line) onCitationTap;

  const _ShapeAskPane({
    required this.tokens,
    required this.loading,
    required this.question,
    required this.answer,
    required this.error,
    required this.onBack,
    required this.onDismissAnswer,
    required this.onCitationTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final hasResult = answer != null || error != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 16, color: t.textFaint),
              const SizedBox(width: 8),
              Text('Ask',
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  )),
              const Spacer(),
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('close',
                      style: TextStyle(color: t.textMuted, fontSize: 11)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading && !hasResult)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(t.accentBright),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      question == null
                          ? 'asking…'
                          : 'asking · ${_truncate(question!, 60)}',
                      style: TextStyle(color: t.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            )
          else if (hasResult)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: _AskAnswerCard(
                  tokens: t,
                  question: question ?? '',
                  answer: answer,
                  error: error,
                  onDismiss: onDismissAnswer,
                  onCitationTap: onCitationTap,
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Text(
                  'type a question in the composer, then press ask.',
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';
}

class _CommitReviewPane extends StatelessWidget {
  final AppTokens tokens;
  final int includedCount;
  final int? diffAdds;
  final int? diffDels;
  final int? diffHunks;
  final String modelLabel;
  final String guardrailLabel;
  final int guardrailStage;
  final String? reasoningEffort;
  final bool fastMode;
  final bool loading;
  final String? error;
  final AiCommitReviewData? result;
  final bool traceExpanded;
  final bool reasoningExpanded;
  final VoidCallback onToggleTrace;
  final VoidCallback onToggleReasoning;
  final VoidCallback onCancel;
  final VoidCallback onBack;
  final VoidCallback onRerun;
  final VoidCallback? onCopy;
  final void Function(String path, String? hunkLabel) onOpenFinding;

  final bool staleScope;

  const _CommitReviewPane({
    required this.tokens,
    required this.includedCount,
    this.diffAdds,
    this.diffDels,
    this.diffHunks,
    required this.modelLabel,
    required this.guardrailLabel,
    required this.guardrailStage,
    this.reasoningEffort,
    this.fastMode = false,
    required this.loading,
    required this.error,
    required this.result,
    required this.traceExpanded,
    required this.reasoningExpanded,
    required this.onToggleTrace,
    required this.onToggleReasoning,
    required this.onCancel,
    required this.onBack,
    required this.onRerun,
    required this.onCopy,
    required this.onOpenFinding,
    this.staleScope = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _reviewShell(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: tokens.chromeBorder.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Code review',
                    style: TextStyle(
                      color: tokens.textStrong,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                            text:
                                '$includedCount included file${includedCount == 1 ? '' : 's'}'),
                        if (diffAdds != null &&
                            diffDels != null &&
                            diffHunks != null) ...[
                          const TextSpan(text: ' • '),
                          TextSpan(
                              text: '+$diffAdds',
                              style: TextStyle(
                                  color: tokens.stateAdded,
                                  fontWeight: FontWeight.w600)),
                          TextSpan(
                              text: ' -$diffDels',
                              style: TextStyle(
                                  color: tokens.stateDeleted,
                                  fontWeight: FontWeight.w600)),
                          const TextSpan(text: ' • '),
                          TextSpan(
                              text:
                                  '$diffHunks hunk${diffHunks == 1 ? '' : 's'}',
                              style: TextStyle(
                                  color: tokens.accentBright,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$guardrailLabel | $modelLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                      if (reasoningEffort != null || fastMode)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _ModelGlyphStrip(
                            color: tokens.chromeAccent,
                            accent: tokens.accentBright,
                            effort: reasoningEffort,
                            fast: fastMode,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                // Live visualisation of the logos relevance engine's
                // traversal. Subscribes to LogosVisBus events emitted
                // during `reviewCommit` and animates through the
                // pipeline's phases (engine resolving → source
                // ignition → heat-kernel diffusion → well reveal →
                // hunk ranking → transmission). Replaces the static
                // "Checking these changes..." text with a geometric
                // narration of what the engine is actually doing.
                child: RepaintBoundary(
                  child: LogosDiffusionCanvas(
                    tokens: tokens,
                    onCancel: onCancel,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (error != null && result == null) {
      return _reviewShell(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Review unavailable',
                  style: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _GhostActionChip(
                  tokens: tokens,
                  label: 'Back to diff',
                  onTap: onBack,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final review = result;
    if (review == null) {
      return _reviewShell(
        child: const SizedBox.shrink(),
      );
    }

    return _reviewShell(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: tokens.chromeBorder.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Code review',
                            style: TextStyle(
                              color: tokens.textStrong,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                    text:
                                        '$includedCount included file${includedCount == 1 ? '' : 's'}'),
                                if (diffAdds != null &&
                                    diffDels != null &&
                                    diffHunks != null) ...[
                                  const TextSpan(text: ' • '),
                                  TextSpan(
                                      text: '+$diffAdds',
                                      style: TextStyle(
                                          color: tokens.stateAdded,
                                          fontWeight: FontWeight.w600)),
                                  TextSpan(
                                      text: ' -$diffDels',
                                      style: TextStyle(
                                          color: tokens.stateDeleted,
                                          fontWeight: FontWeight.w600)),
                                  const TextSpan(text: ' • '),
                                  TextSpan(
                                      text:
                                          '$diffHunks hunk${diffHunks == 1 ? '' : 's'}',
                                      style: TextStyle(
                                          color: tokens.accentBright,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ],
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ReviewVerdictChip(tokens: tokens, verdict: review.verdict),
                    const SizedBox(width: 6),
                    _ReviewScorePill(
                      tokens: tokens,
                      score: review.score,
                      verdict: review.verdict,
                      guardrailStage: review.guardrailStage,
                    ),
                    if (review.hasVerificationTrace) ...[
                      const SizedBox(width: 6),
                      _ReviewMetaChip(
                        tokens: tokens,
                        label: 'Verified',
                        color: tokens.stateAdded,
                      ),
                    ] else if (review.twoStepEnabled &&
                        review.verificationFailed) ...[
                      const SizedBox(width: 6),
                      _ReviewMetaChip(
                        tokens: tokens,
                        label: 'Draft only',
                        color: tokens.stateModified,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10.5,
                          ),
                          children: [
                            TextSpan(
                                text: review.guardrailStage >= 0
                                    ? _guardrailLabelForStage(
                                        review.guardrailStage)
                                    : guardrailLabel),
                            TextSpan(
                              text: '  ·  ',
                              style: TextStyle(color: tokens.textFaint),
                            ),
                            TextSpan(text: modelLabel),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _GhostActionChip(
                      tokens: tokens,
                      label: 'Back to diff',
                      onTap: onBack,
                    ),
                    if (onCopy != null) ...[
                      const SizedBox(width: 8),
                      _GhostActionChip(
                        tokens: tokens,
                        label: 'Copy',
                        onTap: onCopy!,
                      ),
                    ],
                    const SizedBox(width: 8),
                    _GhostActionChip(
                      tokens: tokens,
                      label: 'Run again',
                      onTap: onRerun,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
              children: [
                if (review.verificationFailed &&
                    review.verificationError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.stateConflicted.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                          context.surfaceShader.geometry.radius),
                      border: Border.all(
                        color: tokens.stateConflicted.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${review.verificationError} Draft review is shown below.',
                            style: TextStyle(
                              color: tokens.textStrong,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _GhostActionChip(
                          tokens: tokens,
                          label: traceExpanded ? 'Hide trace' : 'Show trace',
                          onTap: onToggleTrace,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!review.verificationFailed &&
                    review.hasVerificationTrace &&
                    !traceExpanded) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _GhostActionChip(
                      tokens: tokens,
                      label: 'Show verification trace',
                      onTap: onToggleTrace,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                resonanceText(
                  review.summary,
                  tokens,
                  baseStyle: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                // Reasoning is soft-required at the parser layer (some
                // models omit `<summary_reasoning>`). Hide the whole
                // disclosure when there's nothing to disclose.
                if (review.reasoningReport.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ReviewDisclosureCard(
                    tokens: tokens,
                    label: 'Why this review landed here',
                    expanded: reasoningExpanded,
                    preview: review.reasoningReport,
                    onToggle: onToggleReasoning,
                    child: resonanceText(
                      review.reasoningReport,
                      tokens,
                      baseStyle: TextStyle(
                        color: tokens.textNormal,
                        fontSize: 11.2,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  review.findings.isEmpty ? 'No findings' : 'Findings',
                  style: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (review.findings.isEmpty)
                  Text(
                    'No evidence-backed issues were surfaced for this commit scope.',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  )
                else
                  ...review.findings.map(
                    (finding) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ReviewFindingCard(
                        tokens: tokens,
                        finding: finding,
                        onOpenDiff: finding.filePath == null
                            ? null
                            : () => onOpenFinding(
                                finding.filePath!, finding.hunkLabel),
                      ),
                    ),
                  ),
                if (review.observations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Observations',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...review.observations.map(
                    (obs) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tokens.rowBg,
                          borderRadius: BorderRadius.circular(
                              context.surfaceShader.geometry.radius),
                          border: Border.all(
                            color: tokens.chromeBorderFaint,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              obs.title,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (obs.detail.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              resonanceText(
                                obs.detail,
                                tokens,
                                baseStyle: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 10.5,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (review.twoStepEnabled &&
                    (review.hasVerificationTrace ||
                        review.verificationFailed ||
                        review.draftFindings.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  _TracePanel(
                    tokens: tokens,
                    expanded: traceExpanded,
                    onToggle: onToggleTrace,
                    verificationNotes: review.verificationNotes,
                    draftSummary: review.draftSummary,
                    draftReasoningReport: review.draftReasoningReport,
                    draftFindings: review.draftFindings,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewShell({required Widget child}) {
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 0,
      borderAlpha: 0,
      elevated: false,
      // staleScope banner sits above whatever the body is (loading
      // canvas, error message, or full review). Single Column wrap
      // here keeps the banner inside the pane's MaterialSurface so
      // it inherits the same chrome and never visually escapes the
      // drawer.
      child: staleScope
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StaleScopeBanner(tokens: tokens, onRerun: onRerun),
                Expanded(child: child),
              ],
            )
          : child,
    );
  }
}

/// Thin warning banner shown at the top of the review / muse drawer
/// when the user toggles file selection after the run lands. The
/// drawer's body still renders the original record's content; this
/// banner just signals "the result is for a different selection"
/// and offers a one-click rerun.
class _StaleScopeBanner extends StatelessWidget {
  final AppTokens tokens;
  final VoidCallback onRerun;
  const _StaleScopeBanner({required this.tokens, required this.onRerun});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.stateModified.withValues(alpha: 0.10),
        border: Border(
          bottom: BorderSide(
            color: tokens.chromeBorder.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 13, color: tokens.stateModified),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'selection changed since this ran',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 11,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRerun,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                'rerun',
                style: TextStyle(
                  color: tokens.accentBright,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewVerdictChip extends StatelessWidget {
  final AppTokens tokens;
  final String verdict;

  const _ReviewVerdictChip({
    required this.tokens,
    required this.verdict,
  });

  @override
  Widget build(BuildContext context) {
    final color = _reviewVerdictColor(verdict);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        verdict,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _reviewVerdictColor(String verdict) =>
    AppSeverityPalette.fromVerdict(verdict);

class _ReviewScorePill extends StatelessWidget {
  final AppTokens tokens;
  final int score;
  final String verdict;
  final int guardrailStage; // 0=loose, 1=balanced, 2=strict, 3=paranoid

  const _ReviewScorePill({
    required this.tokens,
    required this.score,
    required this.verdict,
    required this.guardrailStage,
  });

  @override
  Widget build(BuildContext context) {
    final verdictColor = _reviewVerdictColor(verdict);
    const size = 32.0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ScoreRingPainter(
          score: score,
          verdictColor: verdictColor,
          guardrailStage: guardrailStage,
          bgColor: tokens.chromeBorder.withValues(alpha: 0.1),
        ),
        child: Center(
          child: Text(
            '$score',
            style: TextStyle(
              color: verdictColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final int score;
  final Color verdictColor;
  final int guardrailStage;
  final Color bgColor;

  const _ScoreRingPainter({
    required this.score,
    required this.verdictColor,
    required this.guardrailStage,
    required this.bgColor,
  });

  /// Build the outline path for the guardrail shape.
  /// 0 = circle, 1 = squished diamond, 2 = shield, 3 = fortress.
  Path _shapePath(Offset center, double r) {
    final cx = center.dx;
    final cy = center.dy;
    switch (guardrailStage.clamp(0, 3)) {
      case 0:
        return Path()..addOval(Rect.fromCircle(center: center, radius: r));

      case 1:
        final rect = Rect.fromCircle(center: center, radius: r);
        final cornerR = r * 0.38;
        return Path()
          ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(cornerR)));

      case 2:
        final w = r * 0.92;
        final top = cy - r;
        return Path()
          ..moveTo(cx, top) // crown
          ..lineTo(cx + w, cy - r * 0.5) // right shoulder
          ..lineTo(cx + w, cy + r * 0.15) // right waist
          ..quadraticBezierTo(
              cx, cy + r * 1.05, cx, cy + r) // right curve → bottom point
          ..quadraticBezierTo(cx, cy + r * 1.05, cx - w,
              cy + r * 0.15) // bottom point → left curve
          ..lineTo(cx - w, cy - r * 0.5) // left shoulder
          ..close();

      default:
        // Octagon with notched battlements at the cardinal points.
        final pts = <Offset>[];
        final notchDepth = r * 0.15;
        for (int i = 0; i < 8; i++) {
          final angle = -math.pi / 2 + (i / 8) * 2 * math.pi;
          final nextAngle = -math.pi / 2 + ((i + 1) / 8) * 2 * math.pi;
          // Outer vertex
          pts.add(Offset(
            cx + r * math.cos(angle),
            cy + r * math.sin(angle),
          ));
          // Battlement notch at midpoint of each edge (inward)
          final midAngle = (angle + nextAngle) / 2;
          final notchR = r - notchDepth;
          pts.add(Offset(
            cx + notchR * math.cos(midAngle - 0.08),
            cy + notchR * math.sin(midAngle - 0.08),
          ));
          pts.add(Offset(
            cx + notchR * math.cos(midAngle + 0.08),
            cy + notchR * math.sin(midAngle + 0.08),
          ));
        }
        final path = Path()..moveTo(pts[0].dx, pts[0].dy);
        for (int i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        path.close();
        return path;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 1.5;
    const strokeWidth = 2.5;

    final shape = _shapePath(center, radius);

    // Background shape outline.
    canvas.drawPath(
      shape,
      Paint()
        ..color = bgColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );

    // Score progress — draw a portion of the shape's perimeter.
    final scoreFraction = (score / 100).clamp(0.0, 1.0);
    final metrics = shape.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final totalLength = metrics.fold<double>(0, (sum, m) => sum + m.length);
      final drawLength = totalLength * scoreFraction;

      final scorePaint = Paint()
        ..color = verdictColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      double drawn = 0;
      for (final metric in metrics) {
        if (drawn >= drawLength) break;
        final segLen = (drawLength - drawn).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(0, segLen), scorePaint);
        drawn += metric.length;
      }
    }
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.score != score ||
      old.verdictColor != verdictColor ||
      old.guardrailStage != guardrailStage;
}

class _ReviewMetaChip extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final Color color;

  const _ReviewMetaChip({
    required this.tokens,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReviewDisclosureCard extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final bool expanded;
  final String preview;
  final VoidCallback onToggle;
  final Widget child;

  const _ReviewDisclosureCard({
    required this.tokens,
    required this.label,
    required this.expanded,
    required this.preview,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.rowBg,
        borderRadius:
            BorderRadius.circular(context.surfaceShader.geometry.radius),
        border: Border.all(color: tokens.chromeBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Material(color: transparent) provides the InkController so
          // the InkWell ripple actually renders. Without it (the prior
          // shape), the InkWell was silent on the dark panel surface.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (!expanded) ...[
                            const SizedBox(height: 5),
                            Text(
                              _oneLinePreview(preview),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textNormal,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: tokens.textMuted,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: child,
            ),
        ],
      ),
    );
  }

  String _oneLinePreview(String value) {
    final normalized =
        value.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 117)}...';
  }
}

class _ReviewFindingCard extends StatelessWidget {
  final AppTokens tokens;
  final AiCommitReviewFindingData finding;
  final VoidCallback? onOpenDiff;

  const _ReviewFindingCard({
    required this.tokens,
    required this.finding,
    this.onOpenDiff,
  });

  @override
  Widget build(BuildContext context) {
    final accent = switch (finding.severity) {
      'block' => AppSeverityPalette.critical,
      'risk' => AppSeverityPalette.risk,
      'warn' => AppSeverityPalette.caution,
      'note' => AppSeverityPalette.info,
      _ => AppSeverityPalette.neutral,
    };
    final meta = [
      if (finding.filePath != null) finding.filePath!,
      if (finding.hunkLabel != null) finding.hunkLabel!,
    ].join(' | ');
    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          color: tokens.rowBg,
          borderRadius:
              BorderRadius.circular(context.surfaceShader.geometry.radius),
          border: Border.all(color: tokens.chromeBorderSubtle),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Accent left edge — communicates severity at a glance.
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            finding.title,
                            style: TextStyle(
                              color: tokens.textStrong,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (onOpenDiff != null) ...[
                          const SizedBox(width: 8),
                          _InlineActionLink(
                            tokens: tokens,
                            label: 'Open diff',
                            onTap: onOpenDiff!,
                          ),
                        ],
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 10.5,
                          fontFamily: AppFonts.mono,
                        ),
                      ),
                    ],
                    if (finding.evidence.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      resonanceText(
                        finding.evidence,
                        tokens,
                        baseStyle: TextStyle(
                          color: tokens.textNormal,
                          fontSize: 11.2,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (finding.whyItMatters.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: tokens.textMuted.withValues(alpha: 0.2),
                              width: 2,
                            ),
                          ),
                        ),
                        child: resonanceText(
                          finding.whyItMatters,
                          tokens,
                          baseStyle: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TracePanel extends StatelessWidget {
  final AppTokens tokens;
  final bool expanded;
  final VoidCallback onToggle;
  final String? verificationNotes;
  final String? draftSummary;
  final String? draftReasoningReport;
  final List<AiCommitReviewFindingData> draftFindings;

  const _TracePanel({
    required this.tokens,
    required this.expanded,
    required this.onToggle,
    required this.verificationNotes,
    required this.draftSummary,
    required this.draftReasoningReport,
    required this.draftFindings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.rowBg,
        borderRadius:
            BorderRadius.circular(context.surfaceShader.geometry.radius),
        border: Border.all(color: tokens.chromeBorderSubtle),
      ),
      child: Column(
        children: [
          // Material(color: transparent) provides the InkController so
          // the InkWell ripple actually renders. Without it the toggle
          // was silent on the dark trace surface.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Verification trace',
                        style: TextStyle(
                          color: tokens.textStrong,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: tokens.textMuted,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (verificationNotes != null &&
                      verificationNotes!.trim().isNotEmpty) ...[
                    Text(
                      verificationNotes!,
                      style: TextStyle(
                        color: tokens.textNormal,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (draftSummary != null &&
                      draftSummary!.trim().isNotEmpty) ...[
                    Text(
                      'Draft review',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      draftSummary!,
                      style: TextStyle(
                        color: tokens.textStrong,
                        fontSize: 11.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (draftReasoningReport != null &&
                      draftReasoningReport!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      draftReasoningReport!,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (draftFindings.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final finding in draftFindings.take(5))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• ${finding.title}',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10.8,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CleanTreeDashboard extends StatefulWidget {
  final AppTokens tokens;
  final RepositoryStatus status;
  final String repoPath;
  final Future<void> Function() onRefresh;

  const _CleanTreeDashboard({
    required this.tokens,
    required this.status,
    required this.repoPath,
    required this.onRefresh,
  });

  @override
  State<_CleanTreeDashboard> createState() => _CleanTreeDashboardState();
}

class _CleanTreeDashboardState extends State<_CleanTreeDashboard> {
  bool _fetching = false;

  Future<void> _fetch() async {
    if (_fetching) return;
    setState(() => _fetching = true);
    try {
      await fetchRemote(widget.repoPath, prune: true);
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _refreshOnly() async {
    if (_fetching) return;
    setState(() => _fetching = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final s = widget.status;
    final aheadColor =
        s.ahead > 0 ? AppSeverityPalette.caution : AppSeverityPalette.safe;
    final behindColor =
        s.behind > 0 ? AppSeverityPalette.caution : AppSeverityPalette.safe;
    final hasUpstream = s.upstream != null;
    final actionLabel = _fetching
        ? hasUpstream
            ? 'Syncing...'
            : 'Refreshing...'
        : hasUpstream
            ? 'Sync'
            : 'Refresh';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Working tree clean',
              style: TextStyle(
                color: t.textStrong,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'No staged or unstaged changes detected.',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            // Branch → upstream
            Text.rich(
              TextSpan(
                style: TextStyle(color: t.textMuted, fontSize: 11),
                children: [
                  TextSpan(
                    text: s.branch,
                    style: TextStyle(
                      color: t.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (s.upstream != null) ...[
                    TextSpan(
                      text: '  →  ',
                      style: TextStyle(color: t.textFaint),
                    ),
                    TextSpan(text: s.upstream),
                  ] else
                    const TextSpan(
                      text: '  ·  no upstream',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Ahead · Behind
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '↑ ${s.ahead}',
                  style: TextStyle(
                    color: aheadColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFonts.mono,
                  ),
                ),
                Text(
                  ' ahead',
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                ),
                Text(
                  '  ·  ',
                  style: TextStyle(color: t.textFaint, fontSize: 11),
                ),
                Text(
                  '↓ ${s.behind}',
                  style: TextStyle(
                    color: behindColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFonts.mono,
                  ),
                ),
                Text(
                  ' behind',
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GhostActionChip(
              tokens: t,
              label: actionLabel,
              fetching: _fetching,
              onTap: hasUpstream ? _fetch : _refreshOnly,
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostActionChip extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final bool fetching;
  final VoidCallback onTap;

  const _GhostActionChip({
    required this.tokens,
    required this.label,
    this.fetching = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChromeButton(
      onTap: onTap,
      borderRadius: AppRadii.pillAll,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      chromeBuilder: ({required hovered, required pressed}) =>
          ghostButtonChrome(
        tokens,
        hovered: hovered,
        pressed: pressed,
        enabled: true,
        baseBorderColor: tokens.chromeBorder.withValues(alpha: 0.16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InlineActionLink extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final VoidCallback onTap;

  const _InlineActionLink({
    required this.tokens,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverableTap(
      onTap: onTap,
      builder: (context, hovered) => AnimatedDefaultTextStyle(
        duration: AppMotion.snap,
        curve: AppMotion.snapCurve,
        style: TextStyle(
          color: hovered ? tokens.textStrong : tokens.accentBright,
          fontSize: 10.2,
          fontWeight: FontWeight.w700,
        ),
        child: Text(label),
      ),
    );
  }
}

/// Inline answer panel for the "ask the manifold" flow. Lives under
/// the commit composer; renders the last question + its prose answer
/// (or error) with a single dismiss affordance. Deliberately spare —
/// the CTA-button layer that ranks entity expansions by information
/// gain is planned but not shipped; for v1 the prose itself is the
/// product and the panel just holds it cleanly.
class _AskCitation {
  final String path;
  final int line;
  const _AskCitation(this.path, this.line);
}

/// Pull `path:line` tokens out of an ask-answer's prose. Matches forms
/// like `lib/foo.dart:42`, `test/bar_test.dart:100`, with typical path
/// characters (letters, digits, underscore, slash, backslash, dot,
/// hyphen). Dedupes on (path, line) and preserves order of first
/// occurrence so the chips read left-to-right in citation order.
List<_AskCitation> _extractAskCitations(String text) {
  final re = RegExp(r'([A-Za-z0-9_./\\-]+\.[A-Za-z0-9]+):(\d+)');
  final seen = <String>{};
  final out = <_AskCitation>[];
  for (final m in re.allMatches(text)) {
    final path = m.group(1)!;
    final line = int.tryParse(m.group(2)!);
    if (line == null) continue;
    // Guard: require the "path" to actually look like a file — contain
    // a slash, or be at least 4 chars with a dot before the extension.
    // Skips false positives like IP addresses with dotted decimals.
    if (!path.contains('/') && !path.contains('\\') && path.length < 4) {
      continue;
    }
    final key = '$path:$line';
    if (!seen.add(key)) continue;
    out.add(_AskCitation(path, line));
  }
  return out;
}

class _AskAnswerCard extends StatelessWidget {
  final AppTokens tokens;
  final String question;
  final String? answer;
  final String? error;
  final VoidCallback onDismiss;
  final void Function(String path, int line)? onCitationTap;

  const _AskAnswerCard({
    required this.tokens,
    required this.question,
    required this.answer,
    required this.error,
    required this.onDismiss,
    this.onCitationTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    final citations = (hasError || answer == null)
        ? const <_AskCitation>[]
        : _extractAskCitations(answer!);
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'asked · $question',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 10.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              HoverableTap(
                onTap: onDismiss,
                borderRadius: AppRadii.xsAll,
                builder: (context, hovered) => Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: hovered ? tokens.textStrong : tokens.textFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            hasError ? 'ask failed — $error' : (answer ?? ''),
            style: TextStyle(
              color: hasError ? tokens.stateConflicted : tokens.textNormal,
              fontSize: 12.5,
              height: 1.42,
            ),
          ),
          if (citations.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in citations)
                  GestureDetector(
                    onTap: onCitationTap == null
                        ? null
                        : () => onCitationTap!(c.path, c.line),
                    child: Text(
                      '${_askCitationDisplayPath(c.path)}:${c.line}',
                      style: TextStyle(
                        color: tokens.textFaint,
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _askCitationDisplayPath(String path) {
  // Strip a leading "lib/" or "test/" for readability when the repo
  // convention is flat. Full path still passes to the jump handler.
  final normalised = path.replaceAll('\\', '/');
  if (normalised.length <= 40) return normalised;
  final parts = normalised.split('/');
  if (parts.length <= 2) return normalised;
  return '…/${parts.sublist(parts.length - 2).join('/')}';
}

class _SplitCommitBtn extends StatefulWidget {
  final String label;
  final String alternateLabel;
  final bool commitOnlyMode;
  final AppTokens t;
  final bool enabled;
  final bool aiGenerating;
  final bool actionRunning;
  final VoidCallback onCommit;
  final VoidCallback onToggleMode;

  const _SplitCommitBtn({
    required this.label,
    required this.alternateLabel,
    required this.commitOnlyMode,
    required this.t,
    required this.enabled,
    required this.aiGenerating,
    this.actionRunning = false,
    required this.onCommit,
    required this.onToggleMode,
  });

  @override
  State<_SplitCommitBtn> createState() => _SplitCommitBtnState();
}

class _SplitCommitBtnState extends State<_SplitCommitBtn> {
  bool _mainHovered = false;
  bool _mainPressed = false;
  bool _chevronHovered = false;
  bool _chevronPressed = false;

  bool get _anyHovered => _mainHovered || _chevronHovered;
  bool get _anyPressed => _mainPressed && !_chevronPressed;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final chrome = primaryButtonChrome(
      t,
      hovered: _anyHovered,
      pressed: _anyPressed,
      enabled: widget.enabled,
    );

    return AnimatedOpacity(
      duration: context.motion(const Duration(milliseconds: 180)),
      opacity: widget.aiGenerating && !_anyHovered ? 0.45 : 1.0,
      child: Transform.translate(
        offset: chrome.offset,
        child: Transform.scale(
          scale: chrome.scale,
          child: SizedBox(
            height: 36,
            child: AnimatedContainer(
              duration: context.motion(const Duration(milliseconds: 100)),
              decoration: BoxDecoration(
                color: chrome.background,
                gradient: chrome.gradient,
                borderRadius: BorderRadius.circular(
                    context.surfaceShader.geometry.radius),
                border: Border.all(color: chrome.borderColor),
                boxShadow: chrome.shadows,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                    (context.surfaceShader.geometry.radius - 1)
                        .clamp(0, double.infinity)),
                child: Row(
                  children: [
                    Expanded(
                      child: MouseRegion(
                        cursor: widget.enabled
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        onEnter: (_) => setState(() => _mainHovered = true),
                        onExit: (_) => setState(() => _mainHovered = false),
                        child: GestureDetector(
                          onTap: widget.enabled ? widget.onCommit : null,
                          onTapDown: widget.enabled
                              ? (_) => setState(() => _mainPressed = true)
                              : null,
                          onTapCancel: () =>
                              setState(() => _mainPressed = false),
                          onTapUp: (_) => setState(() => _mainPressed = false),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedPushIcon(
                                  state: widget.actionRunning
                                      ? IconAnimState.loading
                                      : _mainHovered
                                          ? IconAnimState.hovered
                                          : IconAnimState.idle,
                                  color:
                                      widget.enabled ? t.btnText : t.textMuted,
                                  size: 13,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  widget.label,
                                  style: TextStyle(
                                    color: widget.enabled
                                        ? t.btnText
                                        : t.textMuted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 18,
                      color: t.chromeBorder
                          .withValues(alpha: _anyHovered ? 0.35 : 0.22),
                    ),
                    Tooltip(
                      message: 'Switch to: ${widget.alternateLabel}',
                      waitDuration: const Duration(milliseconds: 600),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _chevronHovered = true),
                        onExit: (_) => setState(() => _chevronHovered = false),
                        child: GestureDetector(
                          onTap: widget.onToggleMode,
                          onTapDown: (_) =>
                              setState(() => _chevronPressed = true),
                          onTapCancel: () =>
                              setState(() => _chevronPressed = false),
                          onTapUp: (_) =>
                              setState(() => _chevronPressed = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 80),
                            width: 32,
                            color: widget.commitOnlyMode
                                ? t.accentBright.withValues(
                                    alpha: _chevronHovered ? 0.18 : 0.10)
                                : Colors.white.withValues(
                                    alpha: _chevronHovered ? 0.10 : 0.0),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: context
                                    .motion(const Duration(milliseconds: 250)),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, anim) {
                                  return FadeTransition(
                                    opacity: anim,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.6,
                                        end: 1.0,
                                      ).animate(anim),
                                      child: child,
                                    ),
                                  );
                                },
                                child: widget.commitOnlyMode
                                    ? AnimatedSyncIcon(
                                        key: const ValueKey('sync'),
                                        state: _chevronHovered
                                            ? IconAnimState.hovered
                                            : IconAnimState.idle,
                                        color: t.accentBright
                                            .withValues(alpha: 0.80),
                                        size: 14,
                                      )
                                    : AnimatedCommitIcon(
                                        key: const ValueKey('commit'),
                                        state: _chevronHovered
                                            ? IconAnimState.hovered
                                            : IconAnimState.idle,
                                        color:
                                            t.btnText.withValues(alpha: 0.80),
                                        size: 14,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

//
// Inline replacement for `_SplitCommitBtn` while the composer is in
// shape mode. Same chrome (primaryButtonChrome, same height/radius/border)
// so the morph from commit-button to shape-ask-button reads as the SAME
// button changing identity, not a different control. Main area asks the
// AI for a subset patch; the chevron CYCLES through configured AI
// categories on each click (instead of opening a menu).
class _ShapeAskButton extends StatefulWidget {
  final AppTokens tokens;
  final List<String> categories;
  final int categoryIndex;
  final bool busy;
  final bool enabled;

  /// Forward cycle (click or Space). Chevron.
  final VoidCallback onCycle;

  /// Backward cycle (shift-click on chevron). Optional — dropped when
  /// only 1 or 2 categories are configured (backward == forward).
  final VoidCallback? onCycleBack;
  final VoidCallback onAsk;

  const _ShapeAskButton({
    required this.tokens,
    required this.categories,
    required this.categoryIndex,
    required this.busy,
    required this.enabled,
    required this.onCycle,
    this.onCycleBack,
    required this.onAsk,
  });

  @override
  State<_ShapeAskButton> createState() => _ShapeAskButtonState();
}

class _ShapeAskButtonState extends State<_ShapeAskButton> {
  bool _mainHovered = false;
  bool _mainPressed = false;
  bool _chevronHovered = false;
  bool _chevronPressed = false;

  bool get _anyHovered => _mainHovered || _chevronHovered;
  bool get _anyPressed => _mainPressed && !_chevronPressed;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final hasCats = widget.categories.isNotEmpty;
    final activeCat = hasCats
        ? widget.categories[
            widget.categoryIndex.clamp(0, widget.categories.length - 1)]
        : '';
    final chrome = primaryButtonChrome(
      t,
      hovered: _anyHovered,
      pressed: _anyPressed,
      enabled: widget.enabled && hasCats,
    );

    final mainEnabled = widget.enabled && hasCats && !widget.busy;
    final chevEnabled = hasCats && widget.categories.length > 1;

    // Two-layer split: the VISUAL sits inside Transform.translate/scale
    // so chrome (offset + scale on hover/press) reads as depth. The
    // HIT-TEST layer is a Stack sibling that stays at a fixed size so
    // MouseRegion/GestureDetector bounds never shift mid-interaction.
    // This fixes the "needs to be spammed" oscillation caused by the
    // transform moving the target out from under the pointer near edges.
    final visual = IgnorePointer(
      child: Transform.translate(
        offset: chrome.offset,
        child: Transform.scale(
          scale: chrome.scale,
          child: AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 100)),
            decoration: BoxDecoration(
              color: chrome.background,
              gradient: chrome.gradient,
              borderRadius:
                  BorderRadius.circular(context.surfaceShader.geometry.radius),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  (context.surfaceShader.geometry.radius - 1)
                      .clamp(0, double.infinity)),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '↵',
                            style: TextStyle(
                              color: mainEnabled ? t.btnText : t.textMuted,
                              fontSize: 12,
                              fontFamily: AppFonts.mono,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedSwitcher(
                            duration: context
                                .motion(const Duration(milliseconds: 140)),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: Text(
                              hasCats
                                  ? widget.busy
                                      ? 'asking with $activeCat…'
                                      : 'ask with $activeCat'
                                  : 'no AI model configured',
                              key: ValueKey('${widget.busy}|$activeCat'),
                              style: TextStyle(
                                color: mainEnabled ? t.btnText : t.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 18,
                    color: t.chromeBorder
                        .withValues(alpha: _anyHovered ? 0.35 : 0.22),
                  ),
                  SizedBox(
                    width: 32,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      color: Colors.white
                          .withValues(alpha: _chevronHovered ? 0.10 : 0.0),
                      child: Center(
                        child: Text(
                          '▾',
                          style: TextStyle(
                            color: t.btnText.withValues(alpha: 0.80),
                            fontSize: 12,
                            fontFamily: AppFonts.mono,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Hit-test layer — fixed-size, outside any transform, so bounds are
    // stable across hover/press state changes.
    final hitTest = Row(
      children: [
        Expanded(
          child: MouseRegion(
            cursor: mainEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _mainHovered = true),
            onExit: (_) => setState(() => _mainHovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: mainEnabled ? widget.onAsk : null,
              onTapDown: mainEnabled
                  ? (_) => setState(() => _mainPressed = true)
                  : null,
              onTapCancel: () => setState(() => _mainPressed = false),
              onTapUp: (_) => setState(() => _mainPressed = false),
            ),
          ),
        ),
        const SizedBox(width: 1), // divider slot — no hit target
        Tooltip(
          message: chevEnabled
              ? 'next: ${widget.categories[(widget.categoryIndex + 1) % widget.categories.length]}  ·  shift-click for previous'
              : 'only one AI category configured',
          waitDuration: const Duration(milliseconds: 600),
          child: SizedBox(
            width: 32,
            child: MouseRegion(
              cursor: chevEnabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              onEnter: (_) => setState(() => _chevronHovered = true),
              onExit: (_) => setState(() => _chevronHovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: chevEnabled
                    ? () {
                        final shift = HardwareKeyboard.instance.isShiftPressed;
                        if (shift && widget.onCycleBack != null) {
                          widget.onCycleBack!();
                        } else {
                          widget.onCycle();
                        }
                      }
                    : null,
                onTapDown: (_) => setState(() => _chevronPressed = true),
                onTapCancel: () => setState(() => _chevronPressed = false),
                onTapUp: (_) => setState(() => _chevronPressed = false),
              ),
            ),
          ),
        ),
      ],
    );

    return AnimatedOpacity(
      duration: context.motion(const Duration(milliseconds: 180)),
      opacity: widget.busy && !_anyHovered ? 0.45 : 1.0,
      child: SizedBox(
        height: 36,
        child: Stack(
          children: [
            Positioned.fill(child: visual),
            Positioned.fill(child: hitTest),
          ],
        ),
      ),
    );
  }
}

//
// One unified pill that replaces the former split "↓ shelve" vs "N shelved ▾"
// buttons. When shelves exist the pill shows both segments — left toggles the
// cabinet open/closed, right adds another shelf — with a hairline divider
// between them so the two actions read as one artifact.

class _DejaVuGlyph extends StatefulWidget {
  final AppTokens tokens;
  final double score;
  final int ghostCount;

  const _DejaVuGlyph({
    required this.tokens,
    required this.score,
    required this.ghostCount,
  });

  @override
  State<_DejaVuGlyph> createState() => _DejaVuGlyphState();
}

class _DejaVuGlyphState extends State<_DejaVuGlyph> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final pct = (widget.score * 100).round();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        opacity: _hovered ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: Tooltip(
          message: '$pct% déjà vu — ${widget.ghostCount} ghost '
              '${widget.ghostCount == 1 ? "edge" : "edges"} from '
              'discarded timelines touch this diff',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: _hovered
                  ? t.bg1.withValues(alpha: 0.95)
                  : t.bg1.withValues(alpha: 0.0),
              border: Border.all(
                color: t.chromeBorder
                    .withValues(alpha: _hovered ? 0.35 : 0.15),
              ),
              borderRadius: BorderRadius.circular(4),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: t.textFaint.withValues(
                      alpha: _hovered ? 0.8 : 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  'déjà vu',
                  style: TextStyle(
                    color: t.textMuted.withValues(
                        alpha: _hovered ? 0.9 : 0.6),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelGlyphStrip extends StatefulWidget {
  final Color color;
  final Color accent;
  final String? effort;
  final bool fast;

  const _ModelGlyphStrip({
    required this.color,
    required this.accent,
    this.effort,
    this.fast = false,
  });

  @override
  State<_ModelGlyphStrip> createState() => _ModelGlyphStripState();
}

class _ModelGlyphStripState extends State<_ModelGlyphStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.effort != null)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              size: const Size(20, 16),
              painter: _ReasoningGlyphPainter(
                color: widget.color,
                effort: widget.effort!,
                t: _ctrl.value,
              ),
            ),
          ),
        if (widget.effort != null && widget.fast)
          const SizedBox(width: 2),
        if (widget.fast)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              size: const Size(11, 14),
              painter: _FastGlyphPainter(
                color: widget.accent,
                t: _ctrl.value,
              ),
            ),
          ),
      ],
    );
  }
}

class _ReasoningGlyphPainter extends CustomPainter {
  final Color color;
  final String effort;
  final double t;

  _ReasoningGlyphPainter({
    required this.color,
    required this.effort,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.25;
    final cy = size.height * 0.5;
    final center = Offset(cx, cy);
    final int rings = switch (effort) {
      'low' => 1,
      'medium' => 2,
      'high' => 3,
      'xhigh' => 3,
      'max' => 3,
      _ => 2,
    };
    final intense = effort == 'xhigh' || effort == 'max';
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);

    // Outer halo bloom for xhigh/max — a wide soft glow that frames
    // the whole glyph and makes the intense levels pop at a glance.
    if (intense) {
      final haloR = 10.0 + 1.0 * pulse;
      canvas.drawCircle(
        center,
        haloR,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.12 + 0.06 * pulse),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(
              Rect.fromCircle(center: center, radius: haloR)),
      );
    }

    // Core glow — radial gradient fading outward. Bigger and warmer
    // at higher levels so the nucleus reads as "hotter."
    final coreRadius = switch (effort) {
      'low' => 2.0,
      'medium' => 2.5,
      'high' => 3.0,
      _ => 3.5 + 0.5 * pulse,
    };
    final coreAlpha = switch (effort) {
      'low' => 0.30,
      'medium' => 0.35,
      'high' => 0.40,
      _ => 0.50 + 0.18 * pulse,
    };
    canvas.drawCircle(
      center,
      coreRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: coreAlpha),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromCircle(center: center, radius: coreRadius)),
    );

    // Nucleus dot — scales with effort so each level has a distinct
    // center weight even before you count the rings.
    final nucR = switch (effort) {
      'low' => 0.9,
      'medium' => 1.1,
      'high' => 1.3,
      _ => 1.6 + 0.15 * pulse,
    };
    final nucAlpha = switch (effort) {
      'low' => 0.50,
      'medium' => 0.60,
      'high' => 0.70,
      _ => 0.80 + 0.12 * pulse,
    };
    canvas.drawCircle(
      center,
      nucR,
      Paint()..color = color.withValues(alpha: nucAlpha),
    );

    // Ripple rings — clipped to the right hemisphere.
    // Inner rings are more opaque, outer rings fade — creates depth
    // and makes the count instantly readable.
    canvas.save();
    canvas.clipRect(
        Rect.fromLTWH(cx - 1, 0, size.width - cx + 1, size.height));

    for (var i = 0; i < rings; i++) {
      final r = 3.6 + i * 2.8;
      final isOuter = i == rings - 1;
      final sweepAngle = math.pi * (0.72 + 0.06 * i);
      final breatheR = isOuter ? r + 0.7 * pulse : r;

      // Opacity: inner rings are solid anchors, outer ring breathes.
      final depthFade = 1.0 - (i / (rings + 1)) * 0.35;
      final baseAlpha = intense ? 0.55 * depthFade : 0.40 * depthFade;
      final ringAlpha =
          isOuter ? baseAlpha * (0.55 + 0.45 * pulse) : baseAlpha;

      // Glow halo.
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: breatheR),
        -sweepAngle * 0.5,
        sweepAngle,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = intense ? 3.0 : 2.2
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: ringAlpha * 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
      );

      // Crisp stroke.
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: breatheR),
        -sweepAngle * 0.5,
        sweepAngle,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = intense ? 1.4 : 1.1
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: ringAlpha),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReasoningGlyphPainter old) =>
      old.effort != effort ||
      old.color != color ||
      (old.t - t).abs() > 0.015;
}

class _FastGlyphPainter extends CustomPainter {
  final Color color;
  final double t;

  _FastGlyphPainter({required this.color, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;

    final bolt = Path()
      ..moveTo(w * 0.52, h * 0.0)
      ..quadraticBezierTo(w * 0.35, h * 0.22, w * 0.15, h * 0.46)
      ..lineTo(w * 0.48, h * 0.44)
      ..quadraticBezierTo(w * 0.38, h * 0.62, w * 0.28, h * 1.0)
      ..quadraticBezierTo(w * 0.65, h * 0.58, w * 0.88, h * 0.40)
      ..lineTo(w * 0.52, h * 0.42)
      ..quadraticBezierTo(w * 0.62, h * 0.22, w * 0.52, h * 0.0)
      ..close();

    // Sharper shimmer curve — spends more time bright, snaps dim.
    final raw = math.sin(t * math.pi * 2);
    final shimmer = 0.40 + 0.35 * (raw > 0 ? math.sqrt(raw) : -math.sqrt(-raw));

    // Tight glow.
    canvas.drawPath(
      bolt,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: shimmer * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    // Crisp fill with gradient top-to-bottom for taper feel.
    canvas.drawPath(
      bolt,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: shimmer),
            color.withValues(alpha: shimmer * 0.6),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(_FastGlyphPainter old) =>
      old.color != color || (old.t - t).abs() > 0.015;
}

class _ShelfControl extends StatefulWidget {
  final AppTokens tokens;
  final int count;
  final bool loading;
  final bool expanded;
  final bool canShelve;
  final VoidCallback? onShelve;
  final VoidCallback? onToggleExpanded;

  const _ShelfControl({
    required this.tokens,
    required this.count,
    required this.loading,
    required this.expanded,
    required this.canShelve,
    required this.onShelve,
    required this.onToggleExpanded,
  });

  @override
  State<_ShelfControl> createState() => _ShelfControlState();
}

class _ShelfControlState extends State<_ShelfControl> {
  int _hoverSegment = 0; // 0 none, 1 toggle, 2 shelve
  bool _isHoveringWholePill = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final hasShelves = widget.count > 0;
    final borderColor =
        t.chromeBorder.withValues(alpha: _isHoveringWholePill ? 0.35 : 0.25);
    final backgroundColor =
        t.bg1.withValues(alpha: _isHoveringWholePill ? 0.95 : 0.0);

    Widget segment({
      required String text,
      required VoidCallback? onTap,
      required int id,
      required Color baseColor,
      BorderRadius? radius,
    }) {
      final hovered = _hoverSegment == id && onTap != null;
      return MouseRegion(
        cursor:
            onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hoverSegment = id),
        onExit: (_) => setState(
            () => _hoverSegment = _hoverSegment == id ? 0 : _hoverSegment),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hovered
                  ? t.chromeAccent.withValues(alpha: 0.08)
                  : t.chromeAccent.withValues(alpha: 0),
              borderRadius: radius,
            ),
            child: Text(
              text,
              style: TextStyle(
                color: onTap == null
                    ? baseColor.withValues(alpha: 0.35)
                    : baseColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    Widget pill(Widget child) {
      return MouseRegion(
        onEnter: (_) => setState(() => _isHoveringWholePill = true),
        onExit: (_) => setState(() => _isHoveringWholePill = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: _isHoveringWholePill ? 0.12 : 0.0),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      );
    }

    if (!hasShelves && !widget.loading) {
      // Single-purpose pill: just shelve.
      return pill(
        segment(
          text: '↓ shelve',
          onTap: widget.canShelve ? widget.onShelve : null,
          id: 2,
          baseColor: t.textMuted,
          radius: BorderRadius.circular(4),
        ),
      );
    }

    // Two-segment pill with hairline divider.
    return pill(
      IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              text: widget.loading
                  ? '…'
                  : '${widget.count} shelved ${widget.expanded ? '▾' : '▸'}',
              onTap: widget.onToggleExpanded,
              id: 1,
              baseColor: t.chromeAccent.withValues(alpha: 0.85),
              radius: const BorderRadius.horizontal(left: Radius.circular(4)),
            ),
            Container(width: 1, color: borderColor),
            segment(
              text: '↓',
              onTap: widget.canShelve ? widget.onShelve : null,
              id: 2,
              baseColor: t.textMuted,
              radius: const BorderRadius.horizontal(right: Radius.circular(4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline orientation label: "bonded", "adjacent", "conflict N", etc.
/// Shown in the stash header's meta line next to the file count.
class _OrientationTag extends StatelessWidget {
  final AppTokens tokens;
  final StashShape shape;
  final Color accentColor;

  const _OrientationTag({
    required this.tokens,
    required this.shape,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    // orthogonal: no tag — the muted left strip is the signal.
    if (shape.orientation == StashOrientation.orthogonal) {
      return const SizedBox.shrink();
    }
    // bonded → ⊕   adjacent → ≈   conflicting → ! N
    final label = switch (shape.orientation) {
      StashOrientation.conflicting => '! ${shape.directOverlap.length}',
      StashOrientation.bonded => '⊕',
      StashOrientation.adjacent => '≈',
      StashOrientation.orthogonal => '',
    };
    return Text(
      label,
      style: TextStyle(
        color: accentColor.withValues(alpha: 0.85),
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// A thin horizontal fill bar between the header and the file list
/// that encodes resonance strength. Width = resonance ∈ [0, 1].
/// Only rendered when orientation is not orthogonal.
class _ResonanceBar extends StatelessWidget {
  final AppTokens tokens;
  final StashShape shape;
  final Color accentColor;

  const _ResonanceBar({
    required this.tokens,
    required this.shape,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final fill = shape.orientation == StashOrientation.conflicting
        ? 1.0
        : shape.resonance.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (ctx, constraints) => Container(
        height: 2,
        width: constraints.maxWidth,
        color: tokens.chromeBorder.withValues(alpha: 0.12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            width: constraints.maxWidth * fill,
            height: 2,
            color: accentColor.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }
}

/// Compact drag feedback chip shown under the cursor while dragging
/// a stash entry. Mirrors the desk drag feedback style.
class _StashDragFeedback extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final StashShape? shape;

  const _StashDragFeedback({
    required this.tokens,
    required this.label,
    required this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final borderColor = shape == null
        ? t.chromeBorder
        : _StashDrawerCardState._orientationColor(shape!.orientation, t);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: t.surface1,
          border:
              Border.all(color: borderColor.withValues(alpha: 0.75), width: 1),
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: t.textNormal,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

//
// Filing-cabinet divider. Header shows label + age + file count and toggles
// open/closed on click. When open, the card reveals the file list with
// per-file add/del counts and exposes the action strip (pick up, peek, toss).

class _StashDrawerCard extends StatefulWidget {
  final AppTokens tokens;
  final StashEntryData stash;
  final bool isPeeking;
  final bool isOpen;
  final List<StashFileStat>? files;
  final bool filesLoading;

  /// Geometric signature relative to the current working tree. Null while
  /// the coupling matrix or file list hasn't loaded yet.
  final StashShape? shape;

  /// File paths currently in the working tree — used to highlight overlap.
  final Set<String> currentPaths;
  final VoidCallback onToggleOpen;
  final VoidCallback onPickUp;
  final VoidCallback onPeek;
  final VoidCallback onToss;

  const _StashDrawerCard({
    required this.tokens,
    required this.stash,
    required this.isPeeking,
    required this.isOpen,
    required this.files,
    required this.filesLoading,
    required this.shape,
    required this.currentPaths,
    required this.onToggleOpen,
    required this.onPickUp,
    required this.onPeek,
    required this.onToss,
  });

  @override
  State<_StashDrawerCard> createState() => _StashDrawerCardState();
}

class _StashDrawerCardState extends State<_StashDrawerCard> {
  bool _hovered = false;

  /// Strips git's auto-generated `WIP on <branch>: <shorthash> <msg>` /
  /// `On <branch>: <msg>` prefixes, but ONLY when they match the strict
  /// autogen shape — user-supplied labels that happen to start with "WIP"
  /// are left alone.
  static String _displayLabel(String raw) {
    // Strict WIP form: branch token has no colon; hash is 7-40 hex; tail non-empty.
    final wip =
        RegExp(r'^WIP on ([^:\s]+): ([0-9a-f]{7,40}) (.+)$').firstMatch(raw);
    if (wip != null) return wip.group(3)!;
    final on = RegExp(r'^On ([^:\s]+): (.+)$').firstMatch(raw);
    if (on != null) return on.group(2)!;
    return raw;
  }

  static String _relativeAge(String iso) {
    try {
      final t = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(t);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
      return '${(diff.inDays / 365).floor()}y ago';
    } catch (_) {
      return '';
    }
  }

  // Map StashOrientation → accent color used for the resonance bar and
  // card border tint.
  static Color _orientationColor(StashOrientation o, AppTokens t) {
    return switch (o) {
      StashOrientation.conflicting => t.stateDeleted,
      StashOrientation.bonded => t.stateAdded,
      StashOrientation.adjacent => t.accentBright,
      StashOrientation.orthogonal => t.chromeBorder,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final stash = widget.stash;
    final label = _displayLabel(stash.message);
    final age = _relativeAge(stash.createdAt);
    final shape = widget.shape;
    final hasShape = shape != null;

    // Border and surface tint shift based on orientation.
    final accentColor =
        hasShape ? _orientationColor(shape.orientation, t) : t.chromeBorder;

    final Color surfaceColor = widget.isPeeking
        ? t.itemActiveBg
        : (widget.isOpen
            ? t.surface1.withValues(alpha: 0.6)
            : (_hovered
                ? t.secondaryBtnHoverBg
                : t.secondaryBtnHoverBg.withValues(alpha: 0)));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(5),
          border: widget.isPeeking
              ? Border.all(color: t.chromeAccent.withValues(alpha: 0.45))
              : (widget.isOpen || _hovered
                  ? Border.all(color: t.chromeBorder.withValues(alpha: 0.25))
                  : null),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            children: [
              // Left accent strip — 3px, colored by orientation.
              if (hasShape)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    color: accentColor.withValues(alpha: 0.75),
                  ),
                ),
              // Card body offset by the strip width when present.
              Padding(
                padding: EdgeInsets.only(left: hasShape ? 3 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onToggleOpen,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
                        child: Row(
                          children: [
                            AnimatedRotation(
                              turns: widget.isOpen ? 0.25 : 0,
                              duration: context
                                  .motion(const Duration(milliseconds: 120)),
                              child: Text(
                                '▸',
                                style: TextStyle(
                                  color: t.textMuted.withValues(alpha: 0.8),
                                  fontSize: 9,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color: t.textNormal,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        '${stash.fileCount} file${stash.fileCount == 1 ? '' : 's'}'
                                        '${age.isEmpty ? '' : ' · $age'}',
                                        style: TextStyle(
                                          color: t.textMuted,
                                          fontSize: 9,
                                        ),
                                      ),
                                      // Orientation tag — only when shape is ready.
                                      if (hasShape) ...[
                                        const SizedBox(width: 6),
                                        _OrientationTag(
                                          tokens: t,
                                          shape: shape,
                                          accentColor: accentColor,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (_hovered ||
                                widget.isPeeking ||
                                widget.isOpen) ...[
                              _StashAction(
                                icon: '↑',
                                tooltip: 'pick up',
                                color: t.accentBright,
                                onTap: widget.onPickUp,
                              ),
                              const SizedBox(width: 6),
                              _StashAction(
                                icon: widget.isPeeking ? '◉' : '◎',
                                tooltip: 'peek',
                                color: t.chromeAccent,
                                onTap: widget.onPeek,
                              ),
                              const SizedBox(width: 6),
                              _StashAction(
                                icon: '×',
                                tooltip: 'toss',
                                color: t.textMuted,
                                onTap: widget.onToss,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (hasShape &&
                        shape.orientation != StashOrientation.orthogonal)
                      _ResonanceBar(
                        tokens: t,
                        shape: shape,
                        accentColor: accentColor,
                      ),
                    if (widget.isOpen)
                      _StashDrawerContents(
                        tokens: t,
                        files: widget.files,
                        loading: widget.filesLoading,
                        overlapPaths: shape?.directOverlap ?? const {},
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StashDrawerContents extends StatelessWidget {
  final AppTokens tokens;
  final List<StashFileStat>? files;
  final bool loading;
  final Set<String> overlapPaths;

  const _StashDrawerContents({
    required this.tokens,
    required this.files,
    required this.loading,
    this.overlapPaths = const {},
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final divider = Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: t.chromeBorder.withValues(alpha: 0.18),
    );

    Widget body;
    if (loading && (files == null || files!.isEmpty)) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 10),
        child: Text(
          'reading shelf…',
          style: TextStyle(color: t.textMuted, fontSize: 10),
        ),
      );
    } else if (files == null || files!.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 10),
        child: Text(
          'empty shelf',
          style: TextStyle(color: t.textMuted, fontSize: 10),
        ),
      );
    } else {
      final maxImpact = files!.fold<int>(
        1,
        (m, f) => math.max(m, f.adds + f.dels),
      );
      // Overlap files float to the top; rest sorted by impact descending.
      final sorted = [...files!]..sort((a, b) {
          final aOver = overlapPaths.contains(a.path) ? 1 : 0;
          final bOver = overlapPaths.contains(b.path) ? 1 : 0;
          if (aOver != bOver) return bOver - aOver;
          return (b.adds + b.dels).compareTo(a.adds + a.dels);
        });
      body = Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final f in sorted)
              _StashFileRow(
                tokens: t,
                file: f,
                maxImpact: maxImpact,
                isOverlap: overlapPaths.contains(f.path),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [divider, body],
    );
  }
}

class _StashFileRow extends StatelessWidget {
  final AppTokens tokens;
  final StashFileStat file;
  final int maxImpact;
  final bool isOverlap;

  const _StashFileRow({
    required this.tokens,
    required this.file,
    this.maxImpact = 1,
    this.isOverlap = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final impact = file.binary ? 0 : (file.adds + file.dels);
    final fillFraction =
        maxImpact > 0 ? (impact / maxImpact).clamp(0.0, 1.0) : 0.0;
    final textColor = isOverlap ? t.stateDeleted : t.textNormal;
    final norm = file.path.replaceAll('\\', '/');
    final slash = norm.lastIndexOf('/');
    final basename = slash < 0 ? norm : norm.substring(slash + 1);
    final dir = slash < 0 ? '' : norm.substring(0, slash + 1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: LayoutBuilder(
        builder: (ctx, constraints) => Stack(
          children: [
            if (fillFraction > 0)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fillFraction,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isOverlap
                          ? t.stateDeleted.withValues(alpha: 0.08)
                          : t.accentBright.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                if (isOverlap)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '!',
                      style: TextStyle(
                        color: t.stateDeleted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppFonts.mono,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 4),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        if (dir.isNotEmpty)
                          TextSpan(
                            text: dir,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.42),
                              fontSize: 10,
                              fontFamily: AppFonts.mono,
                            ),
                          ),
                        TextSpan(
                          text: basename,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 10.5,
                            fontFamily: AppFonts.mono,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (file.binary)
                  Text(
                    'bin',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 9,
                      fontFamily: AppFonts.mono,
                    ),
                  )
                else ...[
                  Text(
                    '+${file.adds}',
                    style: TextStyle(
                      color: t.stateAdded,
                      fontSize: 9.5,
                      fontFamily: AppFonts.mono,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '−${file.dels}',
                    style: TextStyle(
                      color: t.stateDeleted,
                      fontSize: 9.5,
                      fontFamily: AppFonts.mono,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StashAction extends StatelessWidget {
  final String icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _StashAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      // HoverableTap supplies cursor + hover signal + per-theme tap
      // effect. Was a bare GestureDetector(child: Text) — invisible
      // as a control once the user found the stash card.
      child: HoverableTap(
        onTap: onTap,
        builder: (context, hovered) => AnimatedDefaultTextStyle(
          duration: AppMotion.snap,
          curve: AppMotion.snapCurve,
          style: TextStyle(
            color: hovered ? color : color.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          child: Text(icon),
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final RepositoryStatusFile file;
  final AppTokens tokens;
  final bool isDiffSelected;
  final bool included;
  final VoidCallback onTap;
  final ValueChanged<bool> onIncludeChanged;

  /// Cluster stripe color. Null = no coupling signal / matrix not ready.
  final Color? clusterColor;

  /// When true, stripe extends to the very top of the row (no inset, no
  /// rounded top) so it fuses with the previous row's stripe in the same
  /// cluster. Caller computes this from adjacent cluster ids.
  final bool stripeConnectTop;

  /// Same contract for the bottom edge.
  final bool stripeConnectBottom;

  /// Whether this file is part of a real coupling cluster (i.e., stripe
  /// is colored). Rail hover only activates on clustered rows.
  final bool inRealCluster;

  /// Coupling score between this row and the currently rail-hovered file.
  /// Null when nothing is hovered OR this row isn't in the hovered cluster.
  /// 1.0 iff this row IS the hover subject.
  final double? peerScore;

  /// True iff the mouse is over this row's own stripe.
  final bool isRailSubject;

  /// Called when the mouse enters this row's stripe. Null for non-clustered
  /// rows (no meaningful hover target).
  final VoidCallback? onRailEnter;

  /// Called when the mouse leaves this row's stripe.
  final VoidCallback? onRailExit;

  /// Right-click handler. Fires with the screen-space position of the
  /// pointer down event so the caller can position a context menu
  /// against it. Caller decides what menu items to show; the row is
  /// agnostic.
  final ValueChanged<Offset>? onSecondaryTap;

  /// Double-clicking the checkbox toggles the entire coupling group in
  /// one go. Null for isolated rows — nothing to batch.
  final VoidCallback? onClusterToggle;

  /// Continuous opacity for the file's content area (filename, dir,
  /// badges). 1.0 = fully vivid, < 1.0 = dimmed by the Logos engine's
  /// integrity + volatility signal. Checkbox and cluster stripe stay
  /// vivid regardless so interactive/structural signals keep full
  /// legibility.
  final double dimOpacity;

  const _FileRow({
    required this.file,
    required this.tokens,
    required this.isDiffSelected,
    required this.included,
    required this.onTap,
    required this.onIncludeChanged,
    this.clusterColor,
    this.stripeConnectTop = false,
    this.stripeConnectBottom = false,
    this.inRealCluster = false,
    this.peerScore,
    this.isRailSubject = false,
    this.onRailEnter,
    this.onRailExit,
    this.onSecondaryTap,
    this.onClusterToggle,
    this.dimOpacity = 1.0,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  List<_ChangeBadgeSpec> _buildBadges(AppTokens t, RepositoryStatusFile file) {
    // One badge max per row. Staged change wins when both states are
    // present — what's about to land in a commit is the more relevant
    // signal than what's still in the working tree. Falling back to
    // the unstaged badge only when nothing's staged keeps purely-
    // dirty files visible. Keeping it to a single badge avoids the
    // Wrap-into-two-lines case that inflates row height under
    // IntrinsicHeight and leaves dead space below the dir line.
    final staged = _describeGitChange(file.stagedCode, staged: true, tokens: t);
    if (staged != null) return [staged];
    final unstaged =
        _describeGitChange(file.unstagedCode, staged: false, tokens: t);
    if (unstaged != null) return [unstaged];
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final file = widget.file;
    final filename = file.path.split('/').last;
    final dir = file.path.contains('/')
        ? file.path.substring(0, file.path.lastIndexOf('/'))
        : '';
    final badges = _buildBadges(t, file);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onRailEnter?.call();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onRailExit?.call();
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (details) => widget.onSecondaryTap!(details.globalPosition),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cluster stripe — only rendered for files that belong to a
              // real coupling cluster. Isolated / standalone files get no
              // stripe or spacer at all, so the presence of a stripe is
              // itself the at-a-glance "coupled" signal. When consecutive
              // rows share a cluster the stripe runs edge-to-edge (no inset
              // / no rounding) so it visually fuses into one continuous
              // capsule spanning the group.
              // Stripe slot is ALWAYS reserved (3px stripe + 5px spacer)
              // so the checkbox / card column stays in the same x position
              // for every row, whether or not it's in a cluster. The
              // stripe's *color* is what changes: a theme-derived tint for
              // coupled files, transparent for isolated. Clustered rows in
              // sequence fuse edge-to-edge (no inset / no rounding) into a
              // continuous capsule spanning the group.
              // Rail — pure visual widget; hover is handled by the card's
              // outer MouseRegion so hovering anywhere on the card drives
              // the coupling visualization. Width pulses by coupling strength,
              // brightness fades by peer score.
              _RailStripe(
                tokens: t,
                clusterColor: widget.clusterColor,
                inRealCluster: widget.inRealCluster,
                peerScore: widget.peerScore,
                isRailSubject: widget.isRailSubject,
                connectTop: widget.stripeConnectTop,
                connectBottom: widget.stripeConnectBottom,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: widget.isDiffSelected
                        ? t.chromeBorder.withValues(alpha: 0.1)
                        : (widget.included
                            ? t.stateAdded.withValues(alpha: 0.05)
                            : (_hovered
                                ? t.itemHoverBg
                                : t.itemHoverBg.withValues(alpha: 0))),
                    borderRadius: BorderRadius.circular(
                        context.surfaceShader.geometry.radius),
                    border: Border.all(
                      color: widget.included
                          ? t.stateAdded.withValues(alpha: 0.18)
                          : t.stateAdded.withValues(alpha: 0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Tooltip(
                        message: widget.onClusterToggle != null
                            ? 'double-click: toggle whole group'
                            : '',
                        waitDuration: const Duration(milliseconds: 550),
                        child: GestureDetector(
                          onDoubleTap: widget.onClusterToggle,
                          child: AppCheckbox(
                            value: widget.included,
                            size: 16,
                            onChanged: widget.onIncludeChanged,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Everything RIGHT of the checkbox dims together on
                      // stale rows — filename, directory, badges. The
                      // checkbox and cluster stripe stay vivid so the
                      // row's interactive + structural signals keep full
                      // legibility; only the identifying/status content
                      // fades. AnimatedOpacity keeps the fresh↔stale
                      // transition smooth so weights-arrival flips and
                      // epoch advances don't snap.
                      Expanded(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 140),
                          opacity: widget.dimOpacity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row: filename competes with the
                              // status badge for horizontal space. The
                              // dir line below sits outside this Row so
                              // it can extend under the badge to the
                              // full card width (without this split, a
                              // long dir truncated at the same cutoff
                              // as the filename even though nothing
                              // was there to collide with).
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      filename,
                                      style: TextStyle(
                                          color: t.textNormal, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (badges.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      alignment: WrapAlignment.end,
                                      children: [
                                        for (final badge in badges)
                                          _StateBadge(
                                              label: badge.label,
                                              color: badge.color),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dir.isEmpty ? 'Repository root' : dir,
                                style: TextStyle(
                                  color: t.textMuted,
                                  fontSize: 10,
                                  fontFamily: AppFonts.mono,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeBadgeSpec {
  final String label;
  final Color color;

  const _ChangeBadgeSpec({required this.label, required this.color});
}

/// Cluster stripe color derived from the active theme. Returns null for
/// isolated / standalone files — those render with no stripe at all, so the
/// visible stripes read purely as "here is a coupled group".
/// For real clusters we cycle through four semantic accents the theme
/// already defines and step the alpha down for the 5th+ cluster so distant
/// clusters fade rather than flash.
/// One vertical segment of the coupling rail. The stripe is the *only*
/// visualization layer — its width and alpha both modulate by coupling
/// score to the hovered subject, so moving the cursor along a long rail
/// produces a live gradient of stripe thickness + glow across the cluster.
/// Nothing else shifts; no labels enter the row's layout flow.
class _RailStripe extends StatelessWidget {
  final AppTokens tokens;
  final Color? clusterColor;
  final bool inRealCluster;
  final double? peerScore;
  final bool isRailSubject;
  final bool connectTop;
  final bool connectBottom;

  const _RailStripe({
    required this.tokens,
    required this.clusterColor,
    required this.inRealCluster,
    required this.peerScore,
    required this.isRailSubject,
    required this.connectTop,
    required this.connectBottom,
  });

  @override
  Widget build(BuildContext context) {
    final shader = themeDefinitionFor(tokens.id).shader;
    final reduceMotion = context.select<PreferencesState, bool>(
      (s) => s.reduceMotion,
    );
    // Width: 3 at rest, 5 when this row is the subject, 2.5..4.5 for peers
    // proportional to score. Creates a physical "bulge" toward strong
    // peers, fading toward weak ones.
    final width = isRailSubject
        ? 5.0
        : peerScore == null
            ? 3.0
            : (2.5 + peerScore! * 2.0).clamp(2.5, 4.5);

    // Color: subject stays full cluster color; peers fade alpha by score;
    // unsubjected rails render steady.
    final base = clusterColor ?? Colors.transparent;
    final Color color;
    if (peerScore == null || isRailSubject) {
      color = base;
    } else {
      final scale = (0.15 + peerScore! * 0.95).clamp(0.15, 1.0);
      color = base.withValues(alpha: base.a * scale);
    }

    // Reserve the max rail width (5) so adjacent rows don't jitter when
    // one of them becomes the subject and widens. Stripe sizes inside
    // this slot; nothing in the row re-lays out.
    return SizedBox(
      width: 5,
      child: Padding(
        padding: EdgeInsets.only(
          top: connectTop ? 0 : 4,
          bottom: connectBottom ? 0 : 4,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : shader.duration,
            curve: shader.safeCurve,
            width: width,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.only(
                topLeft: connectTop ? Radius.zero : const Radius.circular(1.5),
                topRight: connectTop ? Radius.zero : const Radius.circular(1.5),
                bottomLeft:
                    connectBottom ? Radius.zero : const Radius.circular(1.5),
                bottomRight:
                    connectBottom ? Radius.zero : const Radius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// `_clusterStripeColor` was promoted to `AppTokens.clusterStripeColor`
// in `lib/ui/tokens.dart` so the branches lens (PR file pills) and any
// future surface visualizing coupling share the exact same palette.
// Call sites updated to `t.clusterStripeColor(cid)` directly.

_ChangeBadgeSpec? _describeGitChange(
  String code, {
  required bool staged,
  required AppTokens tokens,
}) {
  switch (code.trim()) {
    case 'M':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged edit' : 'Edited',
        color: staged ? tokens.stateStaged : tokens.stateModified,
      );
    case 'A':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged add' : 'Added',
        color: tokens.stateAdded,
      );
    case 'D':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged delete' : 'Deleted',
        color: tokens.stateDeleted,
      );
    case 'R':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged rename' : 'Renamed',
        color: tokens.accentBright,
      );
    case 'C':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged copy' : 'Copied',
        color: tokens.accentBright,
      );
    case 'U':
      return _ChangeBadgeSpec(
        label: 'Conflict',
        color: tokens.stateConflicted,
      );
    case 'T':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged type change' : 'Type changed',
        color: tokens.accentBright,
      );
    case '?':
      return _ChangeBadgeSpec(
        label: 'Untracked',
        color: tokens.stateAdded,
      );
    default:
      return null;
  }
}

class _StateBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StateBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CommitComposerField extends StatefulWidget {
  final AppTokens tokens;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;

  /// Hint shown when the bound `controller` is empty. Parent picks based
  /// on mode (commit message vs shape input).
  final String hintText;
  final bool aiEnabled;
  final bool aiLoading;

  /// Transient celebratory flash on completion (~1.5 s). Parent
  /// schedules the auto-clear; the button lights up brightly then
  /// settles into either [aiUnread] (drawer wasn't open when result
  /// landed) or quiet idle.
  final bool aiSuccess;

  /// Persistent half-lit visual: there's a terminal record the user
  /// hasn't acknowledged yet AND the corresponding drawer isn't open.
  /// Click → opens the drawer + clears unread. The kind that's
  /// "currently being viewed" reads as quiet, the others read as
  /// "you have unread results here" — exactly the multi-flow
  /// awareness the muse-vs-review interleave needs.
  final bool aiUnread;
  final String aiTooltip;
  final bool reviewEnabled;
  final bool reviewLoading;
  final bool reviewSuccess;

  /// Persistent half-lit visual; see [aiUnread] for the pattern.
  final bool reviewUnread;
  final String? reviewVerdict;
  final String reviewTooltip;
  final VoidCallback onGenerate;
  final VoidCallback onReview;
  final bool museEnabled;
  final bool museLoading;
  final bool museSuccess;

  /// Persistent half-lit visual; see [aiUnread] for the pattern.
  final bool museUnread;
  final String museTooltip;
  final VoidCallback onMuse;

  /// Inline shape-commit mode. When true, the field binds the shape
  /// controller (parent swaps which controller is passed in based on
  /// this flag) and the ◈ button reads as a "exit shape" toggle.
  final bool shapeMode;
  final bool shapeEnabled;
  final bool shapeLoading;
  final String shapeTooltip;

  /// Toggles inline shape mode. Was previously `onShape` which opened
  /// a floating popover; now the parent owns the mode flag and the
  /// composer just morphs in place.
  final VoidCallback? onToggleShape;

  /// Dreamed placeholder from the logos engine. When non-null AND the
  /// bound controller is empty, this renders in place of the plain
  /// `hintText`. Null = fall back to the static `hintText`.
  final String? dreamHint;

  /// Whether the engine is currently thinking about a new hint (debounce
  /// pending or compute in flight). Subtly fades the overlay so the
  /// user can tell the engine is working.
  final bool dreamThinking;

  /// Master AI hide — when true, the four AI toolbar buttons (ask,
  /// muse, review, generate-message) are elided from the composer
  /// toolbar entirely. Dream hint, logos pad, and every non-AI piece
  /// remain untouched.
  final bool hideAi;

  final List<String> tags;
  final List<String> suggestedTags;
  final ValueChanged<String> onTagAdded;
  final ValueChanged<String> onTagRemoved;

  const _CommitComposerField({
    required this.tokens,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    this.hintText = 'commit message...',
    required this.aiEnabled,
    required this.aiLoading,
    this.aiSuccess = false,
    this.aiUnread = false,
    required this.aiTooltip,
    required this.reviewEnabled,
    required this.reviewLoading,
    this.reviewSuccess = false,
    this.reviewUnread = false,
    this.reviewVerdict,
    required this.reviewTooltip,
    required this.onGenerate,
    required this.onReview,
    this.museEnabled = false,
    this.museLoading = false,
    this.museSuccess = false,
    this.museUnread = false,
    this.museTooltip = '',
    required this.onMuse,
    this.shapeMode = false,
    this.shapeEnabled = false,
    this.shapeLoading = false,
    this.shapeTooltip = '',
    this.onToggleShape,
    this.dreamHint,
    this.dreamThinking = false,
    this.hideAi = false,
    this.tags = const [],
    this.suggestedTags = const [],
    required this.onTagAdded,
    required this.onTagRemoved,
  });

  @override
  State<_CommitComposerField> createState() => _CommitComposerFieldState();
}

class _CommitComposerFieldState extends State<_CommitComposerField>
    with TickerProviderStateMixin, WindowAwakeMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _doneCtrl;
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _tagInputCtrl = TextEditingController();
  final FocusNode _tagInputFocus = FocusNode();
  final ScrollController _tagScrollCtrl = ScrollController();
  bool _tagFieldOpen = false;
  bool _tagTriggerHovered = false;

  /// Cached merged listenable for the AnimatedBuilder. Was being
  /// reallocated every build (string-keyed text input fires per
  /// keystroke → 60+ rebuilds/sec → 60+ Listenable.merge allocs/sec).
  /// Rebuilt only when the parent swaps the controller/focus refs
  /// (mode switch).
  Listenable? _composerSignal;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _doneCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _rebuildComposerSignal();
    _tagInputFocus.addListener(_onTagFocusChanged);
    // _pulseCtrl is gated via didChangeDependencies so Reduce Motion
    // silences the border pulse; _doneCtrl forwards only when motion is
    // allowed. Window-focus gate folds in via onWindowAwakeChanged →
    // _syncPulseAwake so a stuck AI loader pulse doesn't burn GPU while
    // tabbed out.
  }

  @override
  void onWindowAwakeChanged() => _syncPulseAwake();

  void _syncPulseAwake() {
    if (!mounted) return;
    final awake = WindowActivity.instance.awake;
    if (!awake && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    } else if (awake &&
        widget.aiLoading &&
        !_pulseCtrl.isAnimating &&
        !context.reduceMotionRead) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  void _rebuildComposerSignal() {
    _composerSignal = Listenable.merge([
      _pulseCtrl,
      _doneCtrl,
      widget.focusNode,
      widget.controller,
    ]);
  }

  static final _editorTitles = <String>[
    'your dreams, please',
    'what did you just do',
    'tell the future you',
    'name this moment',
    'leave a note',
    'say something nice',
    'the deed is done',
    'for the record',
    'posterity awaits',
    'what changed and why',
    'the short version',
    'a few words',
    'dear git log',
    'how it went',
    'in your own words',
  ];
  static int _lastTitleIndex = -1;
  static final _titleRng = math.Random();

  static String _pickEditorTitle() {
    var idx = _titleRng.nextInt(_editorTitles.length);
    if (idx == _lastTitleIndex) {
      idx = (idx + 1) % _editorTitles.length;
    }
    _lastTitleIndex = idx;
    return _editorTitles[idx];
  }

  void _openExpandedEditor(BuildContext context, AppTokens tokens) {
    final expanded = TextEditingController(text: widget.controller.text);
    final focus = FocusNode();
    final title = _pickEditorTitle();
    final shader = themeDefinitionFor(tokens.id).shader;
    final geo = shader.geometry;
    final dur = context.motion(AppMotion.fluid);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close editor',
      barrierColor: Colors.black54,
      transitionDuration: dur,
      transitionBuilder: (ctx, anim, secondAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: shader.curve,
          reverseCurve: AppMotion.fadeCurve,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0)
                .animate(curved),
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim, secondAnim) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(
                maxWidth: 600, maxHeight: 500),
            margin: const EdgeInsets.symmetric(
                horizontal: 60, vertical: 40),
            decoration: BoxDecoration(
              color: tokens.surface1,
              borderRadius: BorderRadius.circular(geo.cardRadius),
              border: Border.all(
                color: tokens.chromeBorder.withValues(alpha: 0.5),
              ),
              boxShadow: AppElev.modal,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Icon(
                            Icons.close_fullscreen,
                            size: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: tokens.inputBg,
                        borderRadius: BorderRadius.circular(
                            geo.pillRadius),
                        border: Border.all(
                          color: tokens.inputBorder,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                            math.max(0, geo.pillRadius - 1)),
                        child: TextField(
                          controller: expanded,
                          focusNode: focus,
                          maxLines: null,
                          expands: true,
                          autofocus: true,
                          textAlignVertical: TextAlignVertical.top,
                          cursorColor: tokens.accentBright,
                          style: TextStyle(
                            color: tokens.textStrong,
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            contentPadding: EdgeInsets.all(10),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) {
      if (mounted) {
        widget.controller.text = expanded.text;
        widget.onChanged?.call(expanded.text);
      }
      expanded.dispose();
      focus.dispose();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = context.reduceMotion;
    final awake = WindowActivity.instance.awake;
    if (widget.aiLoading) {
      if (reduce || !awake) {
        if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
        // Asymmetry is intentional: reduce-motion snaps value to 0
        // (no implied motion at rest), but window-blur only pauses
        // so the pulse resumes mid-phase when focus returns.
        if (reduce) _pulseCtrl.value = 0;
      } else if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(_CommitComposerField old) {
    super.didUpdateWidget(old);
    // Refresh the cached merged listenable only when the parent
    // swaps the controller or focus node (mode change). Avoids the
    // per-build reallocation of `Listenable.merge`.
    if (!identical(old.controller, widget.controller) ||
        !identical(old.focusNode, widget.focusNode)) {
      _rebuildComposerSignal();
    }
    final reduce = context.reduceMotionRead;
    if (widget.aiLoading && !old.aiLoading) {
      _doneCtrl.stop();
      if (!reduce) _pulseCtrl.repeat(reverse: true);
    } else if (!widget.aiLoading && old.aiLoading) {
      _pulseCtrl.stop();
      if (reduce) {
        _doneCtrl.value = 1; // land at the bloomed end-state without animating
      } else {
        _doneCtrl.forward(from: 0);
      }
    }
  }

  void _onTagFocusChanged() {
    if (!_tagInputFocus.hasFocus && _tagFieldOpen) {
      final text = _tagInputCtrl.text.trim();
      if (text.isNotEmpty) {
        widget.onTagAdded(text.toLowerCase());
        _tagInputCtrl.clear();
      }
      setState(() => _tagFieldOpen = false);
    }
  }

  void _submitTag() {
    final text = _tagInputCtrl.text.trim();
    if (text.isNotEmpty) {
      widget.onTagAdded(text.toLowerCase());
      _tagInputCtrl.clear();
    }
  }



  @override
  void dispose() {
    _tagInputFocus.removeListener(_onTagFocusChanged);
    _tagInputCtrl.dispose();
    _tagInputFocus.dispose();
    _tagScrollCtrl.dispose();
    _pulseCtrl.dispose();
    _doneCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final shader = themeDefinitionFor(tokens.id).shader;
    final geo = shader.geometry;
    final radius = geo.radius.clamp(0, 18).toDouble();
    final effectiveRadius = (radius * 0.75).clamp(0.0, 14.0);

    // Hoist the TextField subtree into `child:` — it depends only on
    // widget props (controller, focusNode, enabled, shapeMode,
    // onChanged, hintText), all of which are stable across animation
    // ticks. `_composerSignal` wakes this builder on pulse/bloom
    // animation frames AND on controller/focus changes; only the
    // border chrome and the hasText-driven button row actually need
    // the rebuild. The field itself — about 40 lines of decoration —
    // was being rebuilt for nothing on every pulse frame.
    final textFieldSubtree = ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          tokens.textMuted.withValues(alpha: 0.28),
        ),
        thickness: WidgetStateProperty.all(3),
        radius: const Radius.circular(2),
        // Hug the right edge — no inset margin
        crossAxisMargin: 2,
        mainAxisMargin: 4,
      ),
      child: Scrollbar(
        controller: _scrollCtrl,
        child: ScrollbarTheme(
          data: ScrollbarThemeData(
            thickness: WidgetStateProperty.all(0),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            scrollController: _scrollCtrl,
            enabled: widget.enabled,
            minLines: 5,
            maxLines: null,
            onChanged: widget.onChanged,
            cursorColor: tokens.accentBright,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              color: tokens.textStrong,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              // Dream hint piggybacks on the native `hintText`
              // mechanism so it's pixel-aligned with the TextField
              // cursor — any external overlay drifts by the InputDecorator's
              // internal leading (1-3px) which reads as "off" no matter
              // how carefully the Positioned is tuned. Italic-when-dream
              // + alpha fade on `thinking` give the same feel.
              hintText: widget.shapeMode
                  ? widget.hintText
                  : (widget.dreamHint ?? widget.hintText),
              hintStyle: TextStyle(
                color: tokens.textMuted.withValues(
                  alpha: widget.dreamHint != null &&
                          !widget.shapeMode &&
                          widget.dreamThinking
                      ? 0.32
                      : 0.55,
                ),
                fontSize: 12,
                fontStyle: (widget.dreamHint != null && !widget.shapeMode) ||
                        widget.shapeMode
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _composerSignal!,
      child: textFieldSubtree,
      builder: (context, textField) {
        final hasText = widget.controller.text.trim().isNotEmpty;
        final isFocused = widget.focusNode.hasFocus;
        final innerRadius = math.max(0.0, effectiveRadius - 1.5);

        final Color baseBorder = isFocused
            ? tokens.inputFocusBorder.withValues(alpha: 0.70)
            : tokens.inputBorder;

        Color borderColor;
        double borderWidth;

        if (widget.aiLoading) {
          // Pulse: width 1→1.5px + accent breathes 40%→100% alpha
          final pulse = _pulseCtrl.value;
          borderColor =
              tokens.accentBright.withValues(alpha: 0.40 + pulse * 0.60);
          borderWidth = 1.0 + pulse * 0.5;
        } else if (_doneCtrl.value > 0) {
          // Bloom: width 1→2→1px + accent at full alpha fading out
          final t = _doneCtrl.value;
          final sine = math.sin(math.pi * t);
          borderWidth = 1.0 + sine * 1.0;
          borderColor =
              tokens.accentBright.withValues(alpha: 0.70 + sine * 0.30);
        } else {
          borderColor = baseBorder.withValues(alpha: widget.enabled ? 1 : 0.45);
          borderWidth = 1.0;
        }

        return ConstrainedBox(
          // Grows with content from the 90px base up to 180px (2x), then
          // the TextField scrolls internally. minLines: 5 keeps the empty
          // state visually identical to the previous fixed-height field.
          constraints: const BoxConstraints(minHeight: 90, maxHeight: 180),
          child: Container(
            decoration: BoxDecoration(
              color: tokens.inputBg,
              borderRadius: BorderRadius.circular(effectiveRadius),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              child: Stack(
                children: [
                  textField!,
                  if (widget.controller.text.split('\n').length > 4 ||
                      widget.controller.text.length > 150)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _openExpandedEditor(context, tokens),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: tokens.bg1.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.open_in_full,
                              size: 11,
                              color: tokens.textMuted.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!widget.shapeMode &&
                      widget.suggestedTags.isNotEmpty)
                    Positioned(
                      left: 7,
                      right: 7,
                      bottom: 30,
                      child: IgnorePointer(
                        ignoring: !_tagFieldOpen,
                        child: AnimatedOpacity(
                          opacity: _tagFieldOpen ? 1.0 : 0.0,
                          duration: context.motion(AppMotion.fade),
                          curve: shader.safeCurve,
                          child: AnimatedSlide(
                            offset: _tagFieldOpen
                                ? Offset.zero
                                : const Offset(0, 0.35),
                            duration: context.motion(AppMotion.fade),
                            curve: shader.curve,
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 64),
                              child: SingleChildScrollView(
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    for (final tag
                                        in widget.suggestedTags)
                                      _CommitTagSuggestionChip(
                                        label: tag,
                                        tokens: tokens,
                                        shader: shader,
                                        onTap: () {
                                          widget.onTagAdded(tag);
                                          _tagInputCtrl.clear();
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 7,
                    right: 7,
                    bottom: 6,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!widget.shapeMode)
                          MouseRegion(
                            onEnter: (_) => setState(
                                () => _tagTriggerHovered = true),
                            onExit: (_) => setState(
                                () => _tagTriggerHovered = false),
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () {
                                setState(() =>
                                    _tagFieldOpen = !_tagFieldOpen);
                                if (_tagFieldOpen) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    _tagInputFocus.requestFocus();
                                  });
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: AnimatedContainer(
                                  duration: context
                                      .motion(AppMotion.snap),
                                  curve: shader.safeCurve,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: tokens.bg1.withValues(
                                        alpha: _tagTriggerHovered ||
                                                _tagFieldOpen
                                            ? 0.95
                                            : 0.0),
                                    borderRadius:
                                        BorderRadius.circular(
                                            geo.pillRadius),
                                    border: Border.all(
                                      color:
                                          tokens.chromeBorder.withValues(
                                              alpha: _tagTriggerHovered ||
                                                      _tagFieldOpen
                                                  ? 0.35
                                                  : widget.tags.isNotEmpty
                                                      ? 0.20
                                                      : 0.0),
                                      width: 0.8,
                                    ),
                                    boxShadow: _tagTriggerHovered
                                        ? AppElev.row
                                        : null,
                                  ),
                                  child: AnimatedOpacity(
                                    opacity: _tagTriggerHovered ||
                                            _tagFieldOpen ||
                                            widget.tags.isNotEmpty
                                        ? 1.0
                                        : 0.35,
                                    duration: context
                                        .motion(AppMotion.snap),
                                    curve: shader.safeCurve,
                                    child: Text(
                                      '#',
                                      style: TextStyle(
                                        color: _tagFieldOpen
                                            ? tokens.accentBright
                                            : tokens.textMuted,
                                        fontSize: 10,
                                        fontFamily: AppFonts.mono,
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!widget.shapeMode)
                          Expanded(
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 64),
                              child: SingleChildScrollView(
                                controller: _tagScrollCtrl,
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                  for (final tag in widget.tags)
                                    _CommitTagChip(
                                      label: tag,
                                      tokens: tokens,
                                      shader: shader,
                                      onRemove: () =>
                                          widget.onTagRemoved(tag),
                                    ),
                                  AnimatedContainer(
                                    duration:
                                        context.motion(AppMotion.fade),
                                    curve: shader.curve,
                                    width: _tagFieldOpen ? 84 : 0,
                                    clipBehavior: Clip.hardEdge,
                                    decoration: const BoxDecoration(),
                                    child: AnimatedOpacity(
                                      opacity: _tagFieldOpen ? 1.0 : 0.0,
                                      duration:
                                          context.motion(AppMotion.snap),
                                      curve: shader.safeCurve,
                                      child: SizedBox(
                                        width: 80,
                                        child: TextField(
                                          controller: _tagInputCtrl,
                                          focusNode: _tagInputFocus,
                                          style: TextStyle(
                                            color: tokens.textStrong,
                                            fontSize: 10,
                                            fontFamily: AppFonts.mono,
                                          ),
                                          cursorColor: tokens.accentBright,
                                          cursorHeight: 12,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            isCollapsed: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 3),
                                            hintText: 'tag...',
                                            hintStyle: TextStyle(
                                              color: tokens.textMuted
                                                  .withValues(alpha: 0.45),
                                              fontSize: 10,
                                              fontFamily: AppFonts.mono,
                                              fontStyle: FontStyle.italic,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      geo.badgeRadius),
                                              borderSide: BorderSide(
                                                color: tokens.chromeBorder
                                                    .withValues(alpha: 0.30),
                                                width: 0.8,
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      geo.badgeRadius),
                                              borderSide: BorderSide(
                                                color: tokens.chromeBorder
                                                    .withValues(alpha: 0.30),
                                                width: 0.8,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      geo.badgeRadius),
                                              borderSide: BorderSide(
                                                color: tokens.accentBright
                                                    .withValues(alpha: 0.50),
                                                width: 0.8,
                                              ),
                                            ),
                                          ),
                                          onSubmitted: (_) => _submitTag(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              ),
                              ),
                          )
                        else
                          const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!widget.hideAi) ...[
                              if (widget.onToggleShape != null) ...[
                                _CommitAiToolbarBtn(
                                  tokens: tokens,
                                  enabled:
                                      widget.shapeEnabled || widget.shapeMode,
                                  loading: widget.shapeLoading,
                                  success: widget.shapeMode,
                                  tooltip: widget.shapeTooltip,
                                  hasText: hasText,
                                  fieldRadius: effectiveRadius,
                                  iconKind: _AiToolbarIconKind.shape,
                                  onTap: widget.onToggleShape!,
                                ),
                                const SizedBox(width: 4),
                              ],
                              _CommitAiToolbarBtn(
                                tokens: tokens,
                                enabled: widget.museEnabled,
                                loading: widget.museLoading,
                                success: widget.museSuccess,
                                unread: widget.museUnread,
                                tooltip: widget.museTooltip,
                                hasText: hasText,
                                fieldRadius: effectiveRadius,
                                iconKind: _AiToolbarIconKind.oracle,
                                onTap: widget.onMuse,
                              ),
                              const SizedBox(width: 4),
                              _CommitAiToolbarBtn(
                                tokens: tokens,
                                enabled: widget.reviewEnabled,
                                loading: widget.reviewLoading,
                                success: widget.reviewSuccess,
                                unread: widget.reviewUnread,
                                verdict: widget.reviewVerdict,
                                tooltip: widget.reviewTooltip,
                                hasText: hasText,
                                fieldRadius: effectiveRadius,
                                iconKind: _AiToolbarIconKind.search,
                                onTap: widget.onReview,
                              ),
                              const SizedBox(width: 4),
                              _CommitAiToolbarBtn(
                                tokens: tokens,
                                enabled: widget.aiEnabled,
                                loading: widget.aiLoading,
                                success: widget.aiSuccess,
                                unread: widget.aiUnread,
                                tooltip: widget.aiTooltip,
                                hasText: hasText,
                                fieldRadius: effectiveRadius,
                                iconKind: _AiToolbarIconKind.sparkle,
                                onTap: widget.onGenerate,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommitTagChip extends StatefulWidget {
  final String label;
  final AppTokens tokens;
  final SurfaceMaterialShader shader;
  final VoidCallback onRemove;
  const _CommitTagChip({
    required this.label,
    required this.tokens,
    required this.shader,
    required this.onRemove,
  });
  @override
  State<_CommitTagChip> createState() => _CommitTagChipState();
}

class _CommitTagChipState extends State<_CommitTagChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final s = widget.shader;
    final r = s.geometry.badgeRadius;
    final hue = _commitTagHue(widget.label);
    final hsl = HSLColor.fromColor(t.accentBright);
    final pillColor = hsl
        .withHue(hue)
        .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
        .toColor();
    final bgLum = t.bg0.computeLuminance();
    final textL = bgLum > 0.4 ? 0.22 : 0.82;
    final textColor = hsl
        .withHue(hue)
        .withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0))
        .withLightness(textL)
        .toColor();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onRemove,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          curve: s.safeCurve,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: _hovered
                ? Color.alphaBlend(
                    pillColor.withValues(alpha: 0.15),
                    t.bg1.withValues(alpha: 0.95))
                : pillColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
              color: _hovered
                  ? pillColor.withValues(alpha: 0.50)
                  : pillColor.withValues(alpha: 0.30),
              width: 0.8,
            ),
            boxShadow: _hovered
                ? [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: context.motion(AppMotion.snap),
                curve: s.safeCurve,
                style: TextStyle(
                  color: _hovered ? textColor : textColor.withValues(alpha: 0.90),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFonts.mono,
                  letterSpacing: 0.2,
                ),
                child: Text(widget.label),
              ),
              const SizedBox(width: 2),
              AnimatedOpacity(
                opacity: _hovered ? 0.70 : 0.0,
                duration: context.motion(AppMotion.snap),
                curve: s.safeCurve,
                child: AnimatedScale(
                  scale: _hovered ? 1.0 : 0.5,
                  duration: context.motion(AppMotion.snap),
                  curve: s.curve,
                  child: Text(
                    '×',
                    style: TextStyle(
                      color: pillColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      fontFamily: AppFonts.mono,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitTagSuggestionChip extends StatefulWidget {
  final String label;
  final AppTokens tokens;
  final SurfaceMaterialShader shader;
  final VoidCallback onTap;
  const _CommitTagSuggestionChip({
    required this.label,
    required this.tokens,
    required this.shader,
    required this.onTap,
  });
  @override
  State<_CommitTagSuggestionChip> createState() =>
      _CommitTagSuggestionChipState();
}

class _CommitTagSuggestionChipState extends State<_CommitTagSuggestionChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final s = widget.shader;
    final r = s.geometry.badgeRadius;
    final hue = _commitTagHue(widget.label);
    final hsl = HSLColor.fromColor(t.accentBright);
    final pillColor = hsl
        .withHue(hue)
        .withSaturation((hsl.saturation * 0.6).clamp(0.0, 1.0))
        .toColor();
    final bgLum = t.bg0.computeLuminance();
    final textL = bgLum > 0.4 ? 0.28 : 0.78;
    final textColor = hsl
        .withHue(hue)
        .withSaturation((hsl.saturation * 0.7).clamp(0.0, 1.0))
        .withLightness(textL)
        .toColor();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          curve: s.safeCurve,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: _hovered
                ? Color.alphaBlend(
                    pillColor.withValues(alpha: 0.18),
                    t.bg1.withValues(alpha: 0.95))
                : pillColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
              color: _hovered
                  ? pillColor.withValues(alpha: 0.70)
                  : pillColor.withValues(alpha: 0.28),
              width: 0.6,
            ),
            boxShadow: _hovered
                ? [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 2))]
                : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: context.motion(AppMotion.snap),
            curve: s.safeCurve,
            style: TextStyle(
              color: _hovered ? textColor : textColor.withValues(alpha: 0.85),
              fontSize: 9,
              fontWeight: FontWeight.w500,
              fontFamily: AppFonts.mono,
              fontStyle: FontStyle.italic,
              letterSpacing: 0.2,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

double _commitTagHue(String label) {
  var hash = 0x811c9dc5;
  for (final cu in label.toLowerCase().codeUnits) {
    hash ^= cu;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return (hash % 360).toDouble();
}

enum _AiToolbarIconKind { search, sparkle, shape, oracle }

/// Shape glyph (`◈`) with state-aware motion. Idle is a still diamond.
/// Hover gently scales it up. The "active" state — used while inline
/// shape-mode is engaged — slowly rotates the diamond and emits a
/// periodic glint (a brief scale + brightness pulse) so the toolbar
/// reads as live without being noisy. Loading rotates faster, no glint
/// (the brightness-pulse would compete with the loading affordance).
class _AnimatedShapeIcon extends StatefulWidget {
  final IconAnimState state;
  final Color color;
  final double size;
  const _AnimatedShapeIcon({
    required this.state,
    required this.color,
    required this.size,
  });

  @override
  State<_AnimatedShapeIcon> createState() => _AnimatedShapeIconState();
}

class _AnimatedShapeIconState extends State<_AnimatedShapeIcon>
    with SingleTickerProviderStateMixin, WindowAwakeGuardedMixin {
  static const Duration _authoredActive = Duration(milliseconds: 3600);
  static const Duration _authoredLoading = Duration(milliseconds: 2200);
  late final AnimationController _ctrl;
  PreferencesState? _prefs;

  @override
  void initState() {
    super.initState();
    // 3.6s gives one revolution slow enough to feel ambient (not
    // distracting), with two glint pulses per cycle.
    _ctrl = AnimationController(vsync: this, duration: _authoredActive);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = context.read<PreferencesState>();
    if (!identical(_prefs, prefs)) {
      _prefs?.removeListener(_onPrefsChanged);
      _prefs = prefs;
      prefs.addListener(_onPrefsChanged);
    }
    _syncTickerToState();
  }

  @override
  void onWindowAwakeChanged() => _onPrefsChanged();

  void _onPrefsChanged() {
    if (mounted) _syncTickerToState();
  }

  @override
  void didUpdateWidget(_AnimatedShapeIcon old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncTickerToState();
  }

  void _syncTickerToState() {
    final rate = _prefs?.motionRate ?? 1.0;
    final awake = WindowActivity.instance.awake;
    final reduce = rate <= kMotionRateOff || !awake;
    final shouldAnimate = !reduce &&
        (widget.state == IconAnimState.success ||
            widget.state == IconAnimState.loading);
    if (shouldAnimate) {
      // Loading runs at 1.6× the active cadence — visibly busier,
      // not just "kinda spinning." Both cadences scale with motionRate.
      final authored = widget.state == IconAnimState.loading
          ? _authoredLoading
          : _authoredActive;
      _ctrl.duration = Duration(
        microseconds: (authored.inMicroseconds / rate).round().clamp(
              const Duration(milliseconds: 200).inMicroseconds,
              const Duration(seconds: 60).inMicroseconds,
            ),
      );
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.state == IconAnimState.success;
    final isHovered = widget.state == IconAnimState.hovered;

    // RepaintBoundary isolates the rotating glyph's per-frame paint
    // from the surrounding toolbar button — without it, the parent
    // `_CommitAiToolbarBtn` decoration repaints every animation tick.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value; // 0..1
          // Two glint pulses per revolution. `pow(sin, 6)` makes each
          // pulse a sharp brief peak rather than a smooth sine — reads
          // as a "flash" instead of a slow brightness wave.
          final glintPhase = (t * 2.0) % 1.0;
          final raw = math.sin(glintPhase * math.pi).abs();
          // `raw^6` via three multiplies. `math.pow(x, 6)` dispatches
          // through the `num` boxing path and a `log/exp` pair for the
          // generic case — runs every animation frame, so inlining the
          // square-then-cube schedule removes a transcendental from the
          // per-tick cost.
          final raw2 = raw * raw;
          final glint = isActive ? raw2 * raw2 * raw2 : 0.0;

          // Slow continuous rotation when active; faster on loading.
          final rotation = (isActive || widget.state == IconAnimState.loading)
              ? t * 2 * math.pi
              : 0.0;

          // Scale: hover bumps slightly; active glints add a brief peak
          // on top of the base; loading just rotates without scaling.
          final base = isHovered ? 1.08 : 1.0;
          final scale = base + glint * 0.18;

          // Color: brighten on glint peak. Cap alpha at 1.
          final glintColor = Color.lerp(
            widget.color,
            widget.color.withValues(alpha: 1.0),
            glint,
          )!;

          return Transform.rotate(
            angle: rotation,
            child: Transform.scale(
              scale: scale,
              child: Text(
                '◈',
                style: TextStyle(
                  color: glintColor,
                  fontSize: widget.size,
                  fontFamily: AppFonts.mono,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  shadows: glint > 0.4
                      ? [
                          Shadow(
                            color: widget.color.withValues(alpha: glint * 0.6),
                            blurRadius: 4 + glint * 4,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CommitAiToolbarBtn extends StatefulWidget {
  final AppTokens tokens;
  final bool enabled;
  final bool loading;
  final bool success;

  /// Persistent half-lit state for "you have an unread terminal
  /// record on this slot AND the corresponding drawer isn't open."
  /// Visually a softer wash than [success] (which is a transient
  /// celebration) so the user reads it as "click to view" rather
  /// than "look what just happened." Mutually exclusive with
  /// [success] in practice — the parent's flash timer expires before
  /// `unread` would be set, but the resolution order below treats
  /// success as the higher-priority state if both happen to be true.
  final bool unread;
  final String? verdict; // review verdict for search icon morph
  final String tooltip;
  final bool hasText; // de-emphasise when the user already typed something
  final double fieldRadius;
  final _AiToolbarIconKind iconKind;
  final VoidCallback onTap;

  const _CommitAiToolbarBtn({
    required this.tokens,
    required this.enabled,
    required this.loading,
    this.success = false,
    this.unread = false,
    this.verdict,
    required this.tooltip,
    required this.hasText,
    required this.fieldRadius,
    required this.iconKind,
    required this.onTap,
  });

  @override
  State<_CommitAiToolbarBtn> createState() => _CommitAiToolbarBtnState();
}

class _CommitAiToolbarBtnState extends State<_CommitAiToolbarBtn> {
  bool _hovered = false;
  bool _pressed = false;

  IconAnimState get _iconState {
    if (widget.success) return IconAnimState.success;
    if (widget.loading) return IconAnimState.loading;
    if (_hovered && widget.enabled) return IconAnimState.hovered;
    return IconAnimState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final btnRadius = (widget.fieldRadius * 0.65).clamp(5.0, 8.0);

    // Icon colour: full accent when empty & enabled, dimmed when there's
    // already text (de-emphasise without hiding), muted when disabled.
    // [unread] forces full opacity even with text-present so the
    // "you have results to read" cue isn't lost behind composer text.
    final iconOpacity = !widget.enabled
        ? 0.30
        : widget.unread
            ? 1.0
            : widget.hasText && !_hovered
                ? 0.50
                : 1.0;

    // Background: persistent half-lit wash when [unread] (no drawer
    // is open, but a terminal record waits for the user). Hover /
    // press still deepen on top so the button reads as interactive
    // even in its half-lit resting state.
    final bgAlpha = _pressed
        ? 0.16
        : _hovered
            ? 0.10
            : widget.unread
                ? 0.06
                : 0.0;

    final iconColor = t.accentBright.withValues(alpha: iconOpacity);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              widget.enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel:
              widget.enabled ? () => setState(() => _pressed = false) : null,
          onTapUp:
              widget.enabled ? (_) => setState(() => _pressed = false) : null,
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: t.accentBright.withValues(alpha: bgAlpha),
              borderRadius: BorderRadius.circular(btnRadius),
            ),
            child: Center(
              child: switch (widget.iconKind) {
                _AiToolbarIconKind.search => AnimatedSearchIcon(
                    state: _iconState,
                    color: iconColor,
                    size: 14,
                    verdict: widget.verdict,
                  ),
                _AiToolbarIconKind.sparkle => AnimatedSparkleIcon(
                    state: _iconState,
                    color: iconColor,
                    size: 14,
                  ),
                _AiToolbarIconKind.shape => _AnimatedShapeIcon(
                    state: _iconState,
                    color: iconColor,
                    size: 13,
                  ),
                _AiToolbarIconKind.oracle => AnimatedBubbleIcon(
                    state: _iconState,
                    color: iconColor,
                    size: 14,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SmartSelectBtn extends StatefulWidget {
  final bool allSelected;
  final bool noneSelected;
  final bool enabled;
  final AppTokens tokens;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;

  const _SmartSelectBtn({
    required this.allSelected,
    required this.noneSelected,
    required this.enabled,
    required this.tokens,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  bool get isPartial => !allSelected && !noneSelected;

  @override
  State<_SmartSelectBtn> createState() => _SmartSelectBtnState();
}

class _SmartSelectBtnState extends State<_SmartSelectBtn> {
  // hover state for the single-button mode
  bool _hoveredSingle = false;
  // hover state for each half of the split mode
  bool _hoveredDeselect = false;
  bool _hoveredSelectAll = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final borderColor =
        t.secondaryBtnBorder.withValues(alpha: widget.enabled ? 0.72 : 0.28);

    Widget child;
    if (widget.isPartial) {
      child = KeyedSubtree(
        key: const ValueKey('partial'),
        child: Container(
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _splitHalf(
                  t,
                  icon: Icons.check_box_outline_blank_rounded,
                  tooltip: 'Deselect all',
                  hovered: _hoveredDeselect,
                  onEnter: () => setState(() => _hoveredDeselect = true),
                  onExit: () => setState(() => _hoveredDeselect = false),
                  onTap: widget.onDeselectAll,
                ),
                Container(
                  width: 1,
                  color: borderColor,
                ),
                _splitHalf(
                  t,
                  icon: Icons.check_box_rounded,
                  tooltip: 'Select all',
                  hovered: _hoveredSelectAll,
                  onEnter: () => setState(() => _hoveredSelectAll = true),
                  onExit: () => setState(() => _hoveredSelectAll = false),
                  onTap: widget.onSelectAll,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      final isSelectAll = widget.noneSelected;
      child = KeyedSubtree(
        key: ValueKey(isSelectAll),
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hoveredSingle = true),
          onExit: (_) => setState(() => _hoveredSingle = false),
          child: GestureDetector(
            onTap: widget.enabled
                ? (isSelectAll ? widget.onSelectAll : widget.onDeselectAll)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _hoveredSingle && widget.enabled
                    ? t.secondaryBtnHoverBg
                    : t.secondaryBtnHoverBg.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelectAll
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 12,
                    color: widget.enabled
                        ? t.textNormal.withValues(alpha: 0.80)
                        : t.textMuted.withValues(alpha: 0.40),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isSelectAll ? 'Select all' : 'Deselect all',
                    style: TextStyle(
                      color: widget.enabled ? t.textNormal : t.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }

  Widget _splitHalf(
    AppTokens t, {
    required IconData icon,
    required String tooltip,
    required bool hovered,
    required VoidCallback onEnter,
    required VoidCallback onExit,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit(),
        child: GestureDetector(
          onTap: widget.enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 28,
            color: hovered && widget.enabled
                ? t.secondaryBtnHoverBg
                : t.secondaryBtnHoverBg.withValues(alpha: 0),
            child: Center(
              child: Icon(
                icon,
                size: 13,
                color: widget.enabled
                    ? t.textNormal.withValues(alpha: hovered ? 1.0 : 0.65)
                    : t.textMuted.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConstellationToggleBtn extends StatefulWidget {
  final AppTokens tokens;
  final bool active;
  final bool enabled;
  final VoidCallback onToggle;

  const _ConstellationToggleBtn({
    required this.tokens,
    required this.active,
    required this.enabled,
    required this.onToggle,
  });

  @override
  State<_ConstellationToggleBtn> createState() =>
      _ConstellationToggleBtnState();
}

class _ConstellationToggleBtnState extends State<_ConstellationToggleBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final borderColor =
        t.secondaryBtnBorder.withValues(alpha: widget.enabled ? 0.72 : 0.28);
    final iconColor = widget.active
        ? t.textNormal
        : (widget.enabled
            ? t.textNormal.withValues(alpha: 0.80)
            : t.textMuted.withValues(alpha: 0.40));
    return Tooltip(
      message: widget.active ? 'back to list' : 'atlas, see commit candidates',
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onToggle : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            height: 24,
            width: 28,
            decoration: BoxDecoration(
              color: widget.active
                  ? t.secondaryBtnHoverBg
                  : (_hovered && widget.enabled
                      ? t.secondaryBtnHoverBg
                      : t.secondaryBtnHoverBg.withValues(alpha: 0)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Icon(
                Icons.scatter_plot_rounded,
                size: 13,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

//
// Surfaces unselected files that couple tightly to the user's current
// selection. Rendered just above the commit composer so the moment
// before "I'm committing" is also the moment "wait, you probably
// meant to stage these too". Backed by [suggestMissingPeers].

class _CouplingNudgeBanner extends StatelessWidget {
  final AppTokens tokens;
  final List<CouplingNudge> nudges;
  final void Function(String path) onAdd;

  const _CouplingNudgeBanner({
    required this.tokens,
    required this.nudges,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final n in nudges)
          _CouplingNudgeChip(
            tokens: tokens,
            nudge: n,
            onAdd: () => onAdd(n.path),
          ),
      ],
    );
  }
}

/// Tint a coupling-nudge chip so its colour carries two signals:
///   • [anchor] identity → small hue rotation around the theme accent.
///     Pills coupled to the same selected peer share a tonal family.
///   • [score] (resonance) → saturation amplitude. Weak couplings sit
///     close to chrome neutral; strong couplings read as a confident
///     accent. Stays inside the theme palette either way (hue stays
///     within ±25° of the accent's own hue).
HSLColor _resonanceTint(Color base, String anchor, double score) {
  final hsl = HSLColor.fromColor(base);
  final s = score.clamp(0.0, 1.0);
  final hueShift = ((anchor.hashCode % 51) - 25).toDouble();
  return hsl
      .withHue((hsl.hue + hueShift) % 360)
      .withSaturation((hsl.saturation * (0.45 + 0.55 * s)).clamp(0.0, 1.0));
}

class _CouplingNudgeChip extends StatefulWidget {
  final AppTokens tokens;
  final CouplingNudge nudge;
  final VoidCallback onAdd;

  const _CouplingNudgeChip({
    required this.tokens,
    required this.nudge,
    required this.onAdd,
  });

  @override
  State<_CouplingNudgeChip> createState() => _CouplingNudgeChipState();
}

class _CouplingNudgeChipState extends State<_CouplingNudgeChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final name = pathBasename(widget.nudge.path);
    final score = widget.nudge.score.clamp(0.0, 1.0);
    final tint = _resonanceTint(
      t.accentBright,
      widget.nudge.anchor,
      score,
    ).toColor();
    // Background fill: faint at low resonance, more present at high.
    // Hover bumps it up another notch so the click affordance is felt.
    final fillAlpha =
        (0.06 + 0.10 * score + (_hovered ? 0.06 : 0.0)).clamp(0.0, 1.0);
    final borderAlpha =
        (0.30 + 0.45 * score + (_hovered ? 0.15 : 0.0)).clamp(0.0, 1.0);
    return Tooltip(
      message:
          '${widget.nudge.path}\ncouples with ${pathBasename(widget.nudge.anchor)} · ${(score * 100).round()}%',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onAdd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: fillAlpha),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: tint.withValues(alpha: borderAlpha),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 11,
                  color: t.textNormal.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 4),
                Text(
                  name,
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelDivider extends StatefulWidget {
  final AppTokens tokens;
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  const _PanelDivider({
    required this.tokens,
    required this.onDrag,
    this.onDragEnd,
  });

  @override
  State<_PanelDivider> createState() => _PanelDividerState();
}

class _PanelDividerState extends State<_PanelDivider> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final isActive = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        // don't clear _dragging here — pointer can leave during drag
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        onPanCancel: () => setState(() => _dragging = false),
        onPanUpdate: (details) => widget.onDrag(details.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: _dragging ? 2.0 : 1.0,
              color: isActive
                  ? t.accentBright.withValues(alpha: _dragging ? 0.55 : 0.30)
                  : t.chromeBorder.withValues(alpha: 0.18),
            ),
          ),
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// Merge resolve strip — only visible when the working tree has UU files.
// Sits above the file list. One click resolves ALL conflicts across ALL
// files in a single AI call (tokens amortized, semantic coherence
// preserved). Chevron on the button's right edge offers to override the
// default model category — default is 'fast' (low-latency resolution)
// but pros can pick 'quality' for sticky refactor-heavy conflicts.

class _MergeResolveStrip extends StatelessWidget {
  final Set<String> conflictedPaths;
  final int? totalHunks;
  final bool busy;
  final ValueChanged<String> onResolve;

  const _MergeResolveStrip({
    required this.conflictedPaths,
    required this.totalHunks,
    required this.busy,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ai = context.watch<AiSettingsState>();
    // Prefer 'fast' for resolution — low-latency, most conflicts are
    // mechanical. Fall back to any category that has a model configured.
    final defaultCategory = ai.modelSelections.containsKey('fast') &&
            ai.modelSelections['fast']!.isNotEmpty
        ? 'fast'
        : (ai.modelSelections.entries
            .firstWhere(
              (e) => e.value.isNotEmpty,
              orElse: () => const MapEntry('', ''),
            )
            .key);
    final count = conflictedPaths.length;
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 0,
      border: Border(
        top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.12)),
        bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.18)),
      ),
      elevated: false,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Text('◇',
              style: TextStyle(
                color: t.stateConflicted,
                fontSize: 14,
                fontFamily: AppFonts.mono,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              busy
                  ? 'reading $count file${count == 1 ? '' : 's'} · drafting resolution…'
                  : '$count conflict${count == 1 ? '' : 's'} across $count file${count == 1 ? '' : 's'}',
              style: TextStyle(
                color: t.textNormal,
                fontSize: 12,
                fontFamily: AppFonts.mono,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (defaultCategory.isEmpty)
            Text('no AI model configured',
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10.5,
                  fontFamily: AppFonts.mono,
                  fontStyle: FontStyle.italic,
                ))
          else
            _MergeResolveSplitButton(
              defaultCategoryId: defaultCategory,
              busy: busy,
              onResolve: onResolve,
            ),
        ],
      ),
    );
  }
}

/// Split button: main label click runs resolution with [defaultCategoryId];
/// chevron click opens a menu of the other configured categories so power
/// users can bump to 'quality' for a particularly gnarly conflict.
class _MergeResolveSplitButton extends StatefulWidget {
  final String defaultCategoryId;
  final bool busy;
  final ValueChanged<String> onResolve;

  const _MergeResolveSplitButton({
    required this.defaultCategoryId,
    required this.busy,
    required this.onResolve,
  });
  @override
  State<_MergeResolveSplitButton> createState() =>
      _MergeResolveSplitButtonState();
}

class _MergeResolveSplitButtonState extends State<_MergeResolveSplitButton> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _hoverMain = false;
  bool _hoverChev = false;

  void _openMenu() {
    final overlay = Overlay.of(context);
    final ai = context.read<AiSettingsState>();
    final t = context.tokens;
    // Categories that have a model configured AND aren't the default.
    final alt = ai.modelSelections.entries
        .where((e) => e.value.isNotEmpty && e.key != widget.defaultCategoryId)
        .toList();
    if (alt.isEmpty) return;
    _entry = OverlayEntry(builder: (ctx) {
      final menuCard = CompositedTransformFollower(
        link: _link,
        followerAnchor: Alignment.topRight,
        targetAnchor: Alignment.bottomRight,
        offset: const Offset(0, 6),
        child: MaterialSurface(
          tone: AppMaterialTone.surface1,
          radius: ctx.surfaceShader.geometry.cardRadius,
          elevated: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Text('OR WITH',
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 9,
                        letterSpacing: 1.4,
                        fontFamily: AppFonts.mono,
                        fontWeight: FontWeight.w800,
                      )),
                ),
                for (final e in alt)
                  _ModelCategoryRow(
                    label: ai.labelForCategory(e.key, e.key),
                    modelValue: e.value,
                    onTap: () {
                      _closeMenu();
                      widget.onResolve(e.key);
                    },
                  ),
              ],
            ),
          ),
        ),
      );
      return Stack(children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _closeMenu(),
          ),
        ),
        Positioned(child: menuCard),
      ]);
    });
    overlay.insert(_entry!);
  }

  void _closeMenu() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final ai = context.watch<AiSettingsState>();
    final label =
        ai.labelForCategory(widget.defaultCategoryId, widget.defaultCategoryId);
    final modelValue = ai.modelSelections[widget.defaultCategoryId] ?? '';
    final modelDisplay = _modelDisplayName(modelValue);
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main label
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hoverMain = true),
              onExit: (_) => setState(() => _hoverMain = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.busy
                    ? null
                    : () => widget.onResolve(widget.defaultCategoryId),
                child: Tooltip(
                  message: modelDisplay.isEmpty
                      ? 'resolve with $label'
                      : 'resolve with $label  ·  $modelDisplay',
                  child: AnimatedContainer(
                    duration: context.motion(shader.duration),
                    curve: shader.safeCurve,
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                    decoration: BoxDecoration(
                      color: widget.busy
                          ? t.accentBright.withValues(alpha: 0.08)
                          : (_hoverMain
                              ? t.accentBright.withValues(alpha: 0.14)
                              : t.accentBright.withValues(alpha: 0.08)),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(shader.geometry.badgeRadius),
                        bottomLeft:
                            Radius.circular(shader.geometry.badgeRadius),
                      ),
                      border: Border.all(
                        color: t.accentBright.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      widget.busy ? 'resolving…' : '↵  resolve with $label',
                      style: TextStyle(
                        color: t.accentBright,
                        fontSize: 11,
                        fontFamily: AppFonts.mono,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Chevron split
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hoverChev = true),
              onExit: (_) => setState(() => _hoverChev = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.busy ? null : _openMenu,
                child: Tooltip(
                  message: 'or with another model',
                  child: AnimatedContainer(
                    duration: context.motion(shader.duration),
                    curve: shader.safeCurve,
                    padding: const EdgeInsets.fromLTRB(6, 7, 8, 7),
                    decoration: BoxDecoration(
                      color: _hoverChev
                          ? t.accentBright.withValues(alpha: 0.16)
                          : t.accentBright.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(shader.geometry.badgeRadius),
                        bottomRight:
                            Radius.circular(shader.geometry.badgeRadius),
                      ),
                      // Uniform border — Flutter's `Border.paint` asserts
                      // on a non-uniform border combined with non-zero
                      // borderRadius (the previous left-dim-alpha was
                      // firing 600+ assertions per session). The seam
                      // between this chevron and the abutting main
                      // button now renders as a thin double-stroked
                      // vertical line at the join, which is the
                      // intended split-button look anyway.
                      border: Border.all(
                          color: t.accentBright.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      '▾',
                      style: TextStyle(
                        color: t.accentBright,
                        fontSize: 10,
                        fontFamily: AppFonts.mono,
                        fontWeight: FontWeight.w800,
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
  }
}

class _ModelCategoryRow extends StatefulWidget {
  final String label;
  final String modelValue;
  final VoidCallback onTap;
  const _ModelCategoryRow({
    required this.label,
    required this.modelValue,
    required this.onTap,
  });
  @override
  State<_ModelCategoryRow> createState() => _ModelCategoryRowState();
}

class _ModelCategoryRowState extends State<_ModelCategoryRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final modelDisplay = _modelDisplayName(widget.modelValue);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(shader.duration),
          curve: shader.safeCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hover
                ? t.accentBright.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Text(widget.label,
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 12,
                    fontFamily: AppFonts.mono,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(width: 14),
              Text(modelDisplay,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontFamily: AppFonts.mono,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Take a `provider:modelId` string (e.g. `claude:claude-3-5-sonnet`) and
/// return the human-readable model name. Empty input → empty output.
String _modelDisplayName(String modelValue) {
  if (modelValue.isEmpty) return '';
  final i = modelValue.indexOf(':');
  if (i < 0 || i >= modelValue.length - 1) return modelValue;
  return modelValue.substring(i + 1);
}

// ◈ Shape staging — natural-language partial staging. A glyph next to
// previewed in stage mode and applied via `git apply --cached`.
// Working tree never mutates — only the index shapes.

/// Floating popover anchored above the commit composer's ◈ shape
/// button. Compact card — one input, one submit split button. Lives
/// alongside the other AI toolbar buttons (review, generate) so all
/// AI affordances share the same region of the screen.

/// Ambient text animation for the muse loading state — each character
/// drifts on its own y-axis as if breathing. Two phases blend over
/// time: the first ~3s is a single soothing sine shared by every
/// character, then the field crossfades into a layered, per-character
/// pattern where each glyph carries its own seeded frequency, phase,
/// and amplitude. The second phase still rhymes (everything is sines)
/// but no two glyphs move in sync — the whole word feels like it's
/// thinking.
class _DreamingText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _DreamingText({required this.text, required this.style});

  @override
  State<_DreamingText> createState() => _DreamingTextState();
}

class _DreamingTextState extends State<_DreamingText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      setState(() => _elapsedMs = d.inMicroseconds / 1000.0);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.split('');
    final phaseMix = ((_elapsedMs - 3000) / 2000).clamp(0.0, 1.0).toDouble();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chars.length; i++) _glyph(chars[i], i, phaseMix),
      ],
    );
  }

  Widget _glyph(String c, int i, double phaseMix) {
    if (c == ' ') return Text(c, style: widget.style);
    final p1 = math.sin(_elapsedMs / 580 + i * 0.32) * 2.4;
    final seed = ((i * 73 + 19) % 100) / 100.0;
    final freq = 0.0009 + seed * 0.0014;
    final phase = seed * math.pi * 2;
    final amp = 1.6 + seed * 4.2;
    final p2 = math.sin(_elapsedMs * freq + phase) * amp;
    final yOffset = p1 * (1 - phaseMix) + p2 * phaseMix;
    final breath = 0.55 +
        0.45 * (math.sin(_elapsedMs / 950 + i * 0.27 + seed * 4) * 0.5 + 0.5);
    final col = widget.style.color ?? const Color(0xFF888888);
    return Transform.translate(
      offset: Offset(0, yOffset),
      child: Text(
        c,
        style: widget.style.copyWith(color: col.withValues(alpha: breath)),
      ),
    );
  }
}

// (Was: _OtherDesksStrip + _OtherDeskChip — the "ALSO IN FLIGHT"
// chip strip that surfaced parallel desks with uncommitted work.
// Removed in favor of the History page's IN FLIGHT strip, which is
// the single canonical "other desks at a glance" surface and adds
// hover-to-preview of the diverged commits in-place.)

/// Thin accent-colour bar rendered inside a submenu row's trailing
/// slot to visualise relative φ weight. Width is fixed (36px) so
/// rows align; fill proportion encodes score. Tiny but carries the
/// forecast distribution at a glance.
class _PhiBar extends StatelessWidget {
  final double relative;
  final AppTokens tokens;
  const _PhiBar({required this.relative, required this.tokens});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 4,
      child: CustomPaint(
        painter: _PhiBarPainter(
          relative: relative.clamp(0.0, 1.0),
          colour: tokens.accentBright,
          track: tokens.chromeBorder,
        ),
      ),
    );
  }
}

class _PhiBarPainter extends CustomPainter {
  final double relative;
  final Color colour;
  final Color track;
  const _PhiBarPainter({
    required this.relative,
    required this.colour,
    required this.track,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final trackRR =
        RRect.fromRectAndRadius(trackRect, Radius.circular(size.height / 2));
    canvas.drawRRect(trackRR, Paint()..color = track.withValues(alpha: 0.25));
    final fillRect = Rect.fromLTWH(0, 0, size.width * relative, size.height);
    final fillRR =
        RRect.fromRectAndRadius(fillRect, Radius.circular(size.height / 2));
    canvas.drawRRect(fillRR, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(covariant _PhiBarPainter old) =>
      old.relative != relative || old.colour != colour || old.track != track;
}

/// Tiny sparkline showing a file's touch-density across the engine's
/// analysed commit window. Bars are binned into 10 buckets; height
/// scales to the max-bucket touch count so the shape reads relative
/// to the file's own history (a file that was hot 3 months ago but
/// cold now shows a left-loaded silhouette). Rendered inline in the
/// file context menu as a glance-level rhythm indicator — the row
/// carries the signal, no submenu required.
class _RhythmSpark extends StatelessWidget {
  final List<int> commitIndices;
  final int totalCommits;
  final AppTokens tokens;
  const _RhythmSpark({
    required this.commitIndices,
    required this.totalCommits,
    required this.tokens,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 12,
      child: CustomPaint(
        painter: _RhythmSparkPainter(
          commitIndices: commitIndices,
          totalCommits: totalCommits,
          colour: tokens.accentBright,
          faint: tokens.textFaint,
        ),
      ),
    );
  }
}

class _RhythmSparkPainter extends CustomPainter {
  final List<int> commitIndices;
  final int totalCommits;
  final Color colour;
  final Color faint;
  const _RhythmSparkPainter({
    required this.commitIndices,
    required this.totalCommits,
    required this.colour,
    required this.faint,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (totalCommits <= 0 || commitIndices.isEmpty) {
      // Empty-state dot: a single faint mark so the row doesn't
      // read as a layout error.
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        1.2,
        Paint()..color = faint.withValues(alpha: 0.4),
      );
      return;
    }
    const buckets = 10;
    final counts = List<int>.filled(buckets, 0);
    for (final idx in commitIndices) {
      if (idx < 0 || idx >= totalCommits) continue;
      final b = ((idx / totalCommits) * buckets).floor().clamp(0, buckets - 1);
      counts[b]++;
    }
    var maxCount = 0;
    for (final c in counts) {
      if (c > maxCount) maxCount = c;
    }
    if (maxCount == 0) return;
    final barWidth = (size.width - (buckets - 1)) / buckets;
    final paint = Paint()..color = colour;
    for (var i = 0; i < buckets; i++) {
      final h = (counts[i] / maxCount) * size.height;
      if (h <= 0) continue;
      // Faintly colour older buckets, brighter for recent ones, so
      // recency reads as rightward warmth without needing a label.
      final recency = i / (buckets - 1);
      paint.color = colour.withValues(alpha: 0.35 + 0.6 * recency);
      final x = i * (barWidth + 1);
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - h, barWidth, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RhythmSparkPainter old) =>
      !identical(old.commitIndices, commitIndices) ||
      old.totalCommits != totalCommits ||
      old.colour != colour ||
      old.faint != faint;
}
