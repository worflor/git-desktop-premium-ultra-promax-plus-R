// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../app/logos_git_state.dart';
import '../../app/repository_state.dart';
import '../../backend/atomic_write.dart';
import '../../backend/git.dart' as git_backend;
import '../../backend/logos_git.dart';
import '../../backend/repo_web_url.dart';
import '../../backend/storage_paths.dart';
import '../../i18n/gen/strings.g.dart';
import 'palette_async_providers.dart';
import '../../app/ai_activity_state.dart';
import '../../app/external_tools_state.dart';
import '../../app/wick_state.dart';
import '../../backend/wick.dart' show WickPosture, WickQueryResponse, WickUnit;
import 'palette_entry.dart';
import 'palette_prefix.dart';
import 'palette_registry.dart';
import 'palette_scorer.dart';

typedef _EntryRebuilder = List<PaletteEntry> Function(
    Map<String, String?> forgeByPath);

class PaletteState extends ChangeNotifier {
  PaletteState() {
    // Rebuild the open palette's entries on a live locale switch. The entry
    // labels are baked at open() into _staticEntries, so moving the forge
    // fallback to render-time isn't enough on its own — the whole list has to
    // be re-materialized. buildStaticEntries reads the global `t` (now on the
    // new locale) via the rebuilder; the forge cache is locale-invariant so it
    // carries over. No-op while the palette is closed (rebuilder is null).
    _localeSub = LocaleSettings.getLocaleStream().listen((_) {
      if (_disposed || _rebuilder == null) return;
      _staticEntries = _rebuilder!(_forgeCache);
      _reScore();
      notifyListeners();
    });
  }

  StreamSubscription<AppLocale>? _localeSub;
  final PaletteScorer _scorer = PaletteScorer();
  final PaletteGitCache _gitCache = PaletteGitCache();
  // Value is the resolved forge brand ("GitHub"/"GitLab", locale-invariant),
  // or null for a resolved-but-local repo. Keyed by path only: containsKey
  // distinguishes "resolved, no forge" (present-null) from "not yet warmed"
  // (absent). The translated "local" chip is NOT stored here — it's resolved
  // fresh at render so it tracks live locale switches.
  final Map<String, String?> _forgeCache = {};

  /// Notifies listeners, but never *during* a build/layout/paint phase.
  ///
  /// `CommandPalette.initState` calls [open] (and [updateMode]) synchronously
  /// as it mounts, and those set-then-`notifyListeners` — legitimate, because
  /// the palette is "open the moment it exists." But this notifier is an
  /// ancestor Provider the palette (and its siblings) `watch`, so a synchronous
  /// notify raised while the framework is still building throws
  /// "setState()/markNeedsBuild() called during build" — an assert that is
  /// silent in release but fires in every debug build. The fields are already
  /// set by the time we get here; only the *wake* is illegal at this instant,
  /// so defer just the wake to the end of the frame. Outside a build phase
  /// (the overwhelmingly common case — keystrokes, async results) it stays a
  /// plain synchronous notify with no added latency.
  @override
  void notifyListeners() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) super.notifyListeners();
      });
    } else {
      super.notifyListeners();
    }
  }

  bool _disposed = false;

  List<PaletteEntry> _staticEntries = [];
  List<PaletteEntry> _asyncEntries = [];
  List<PaletteEntry> _results = [];
  String _query = '';
  int _selectedIndex = 0;
  bool _isLoading = false;
  Timer? _debounce;
  Timer? _hoverDebounce;
  // Usage-persistence scheduling (see _persistUsage): a coalescing debounce +
  // single-flight drain so the frequent fire-and-forget writes never overlap
  // and never tear the file.
  static const Duration _kPersistDebounce = Duration(seconds: 1);
  Timer? _persistTimer;
  bool _persistDirty = false;
  Future<void>? _persistDraining;
  PaletteContext _context = const PaletteContext();
  LogosGit? _engine;
  bool elevated = false;

  int _generation = 0;
  PaletteCallbacks? _callbacks;
  String? _openRepoPath;
  _EntryRebuilder? _rebuilder;
  AiActivityState? _aiActivity;

  String? _pendingConfirmId;
  DateTime? _pendingConfirmAt;
  String? _warmingEntryId;
  LogosGitState? _logosState;
  ExternalToolsState? _toolsState;

  List<PalettePrefix> _prefixes = [];
  WickState? _wickState;
  List<WickUnit> _wickEntries = [];
  WickPosture? _wickPosture;

  final Map<String, Map<String, int>> _allFrequency = {};
  final Map<String, Map<String, DateTime>> _allRecency = {};
  final Map<String, Map<String, Map<String, int>>> _allQueryFrequency = {};
  final Map<String, Map<String, Map<String, int>>> _allTransitions = {};
  String? _lastExecutedId;
  bool _usageLoaded = false;

  Map<String, int> _usageFrequency = {};
  Map<String, DateTime> _recency = {};
  Map<String, Map<String, int>> _queryFrequency = {};
  Map<String, Map<String, int>> _transitions = {};

  List<PaletteEntry> get results => _results;
  String get query => _query;
  int get selectedIndex => _selectedIndex;
  bool get isLoading => _isLoading;
  PaletteEntry? get selected =>
      _selectedIndex < _results.length ? _results[_selectedIndex] : null;

  List<WickUnit> get wickEntries => _wickEntries;
  WickPosture? get wickPosture => _wickPosture;
  bool get hasWickResults => _wickEntries.isNotEmpty;
  bool _wickSearching = false;
  bool get wickSearching => _wickSearching;
  bool get wickAvailable => _wickState != null && _wickState!.available;
  bool get wickActive => wickAvailable || _wickSearching || _wickEntries.isNotEmpty;

  bool get hasPendingConfirm =>
      _pendingConfirmId != null &&
      _pendingConfirmAt != null &&
      DateTime.now().difference(_pendingConfirmAt!).inMilliseconds < 800;

  @override
  void dispose() {
    if (_disposed) return; // idempotent — safe against a double dispose
    _disposed = true;
    _localeSub?.cancel();
    _debounce?.cancel();
    _hoverDebounce?.cancel();
    _persistTimer?.cancel();
    _persistTimer = null;
    // Flush-on-dispose: persist any pending usage the debounce hadn't yet
    // written. Best-effort and fire-and-forget — at app shutdown the isolate
    // may end first, but usage stats are non-critical (the loader tolerates a
    // missing/partial file) and the atomic write keeps even this last one
    // torn-free.
    if (_persistDirty && _persistDraining == null) {
      unawaited(_writeUsageSnapshot());
    }
    super.dispose();
  }

  void open(BuildContext context, PaletteCallbacks callbacks) {
    _generation++;
    _loadUsageSync();

    final repo = context.read<RepositoryState>();
    final status = repo.status;
    final hasStagedChanges =
        status?.files.any((f) => f.hasStagedChange) ?? false;
    final hasUnstagedChanges =
        status?.files.any((f) => f.hasUnstagedChange) ?? false;

    final logosState = context.read<LogosGitState>();
    _engine = repo.activePath != null
        ? logosState.engineFor(repo.activePath!)
        : null;

    _callbacks = callbacks;
    _openRepoPath = repo.activePath;
    _aiActivity = context.read<AiActivityState>();
    _logosState = context.read<LogosGitState>();
    _toolsState = context.read<ExternalToolsState>();
    _wickState = context.read<WickState>();
    _warmingEntryId = null;
    _pendingConfirmId = null;
    _pendingConfirmAt = null;
    _prefixes = buildPrefixes(
      aiActivity: _aiActivity!,
      tools: context.read<ExternalToolsState>(),
      engine: _engine,
    );

    final rk = _openRepoPath ?? '';
    _usageFrequency = _allFrequency[rk] ?? {};
    _recency = _allRecency[rk] ?? {};
    _queryFrequency = _allQueryFrequency[rk] ?? {};
    _transitions = _allTransitions[rk] ?? {};

    _context = PaletteContext(
      usageFrequency: _usageFrequency,
      recency: _recency,
      queryFrequency: _queryFrequency,
      transitions: _transitions,
      lastExecutedId: _lastExecutedId,
      hasStagedChanges: hasStagedChanges,
      hasUnstagedChanges: hasUnstagedChanges,
      isAhead: (status?.ahead ?? 0) > 0,
      isBehind: (status?.behind ?? 0) > 0,
      aheadCount: status?.ahead ?? 0,
      behindCount: status?.behind ?? 0,
      activePath: repo.activePath,
      recentPaths: repo.recentPaths,
    );

    _rebuilder = (forgeByPath) =>
        buildStaticEntries(context, callbacks, forgeByPath: forgeByPath);
    _staticEntries = _rebuilder!(_forgeCache);
    _asyncEntries = [];
    _wickEntries = [];
    _wickPosture = null;
    _wickSearching = false;
    _query = '';
    _selectedIndex = 0;
    _isLoading = false;
    _reScore();

    final gen = _generation;
    final recentPaths = List<String>.of(repo.recentPaths);
    _warmCacheAndForges(gen, repo.activePath, recentPaths);
  }

  Future<void> _warmCacheAndForges(
    int gen,
    String? repoPath,
    List<String> recentPaths,
  ) async {
    if (repoPath != null) {
      await _gitCache.warm(repoPath);
    }

    var forgeChanged = false;
    for (final path in recentPaths) {
      if (gen != _generation) return;
      if (_forgeCache.containsKey(path)) continue;
      final info = await resolveRepoWebInfo(path);
      if (gen != _generation) return;
      // Cache the resolution (brand or null-for-local), never the translated
      // fallback — that would freeze the "local" chip in one language.
      _forgeCache[path] = info?.label;
      forgeChanged = true;
    }

    if (gen != _generation || _rebuilder == null) return;
    if (forgeChanged) {
      _staticEntries = _rebuilder!(_forgeCache);
      _reScore();
    }
  }

  void updateMode(int mode) {
    _context = PaletteContext(
      currentMode: mode,
      usageFrequency: _context.usageFrequency,
      recency: _context.recency,
      queryFrequency: _context.queryFrequency,
      hasStagedChanges: _context.hasStagedChanges,
      hasUnstagedChanges: _context.hasUnstagedChanges,
      isAhead: _context.isAhead,
      isBehind: _context.isBehind,
      aheadCount: _context.aheadCount,
      behindCount: _context.behindCount,
      stashCount: _context.stashCount,
      activePath: _context.activePath,
      recentPaths: _context.recentPaths,
    );
    _reScore();
  }

  void close() {
    _generation++;
    _debounce?.cancel();
    _debounce = null;
    _hoverDebounce?.cancel();
    _hoverDebounce = null;
    _wickState?.cancelActiveQuery();
    _staticEntries = [];
    _asyncEntries = [];
    _wickEntries = [];
    _wickPosture = null;
    _wickSearching = false;
    _results = [];
    _query = '';
    _selectedIndex = 0;
    _isLoading = false;
    _engine = null;
    _callbacks = null;
    _openRepoPath = null;
    _rebuilder = null;
    _aiActivity = null;
    _logosState = null;
    _toolsState = null;
    _warmingEntryId = null;
    _pendingConfirmId = null;
    _pendingConfirmAt = null;
    _gitCache.clear();
  }

  void setQuery(String query, {String? repoPath}) {
    _query = query;
    _pendingConfirmId = null;
    _reScore();

    final isLogPrefix = query.toLowerCase().startsWith('log:');
    final activePrefix = _prefixes.any((p) => p.matches(query) && p is! LogPrefix);

    _debounce?.cancel();
    if (!activePrefix && query.length >= 2 && repoPath != null) {
      final gen = _generation;
      final searchQuery = isLogPrefix
          ? query.substring(4).trim()
          : query;
      if (searchQuery.length >= 2) {
        _debounce = Timer(const Duration(milliseconds: 300), () {
          if (isLogPrefix) {
            _runCommitOnlySearch(repoPath, searchQuery, gen);
          } else {
            _runAsyncSearch(repoPath, searchQuery, gen);
          }
        });
      }
    } else {
      _asyncEntries = [];
      _wickEntries = [];
      _wickPosture = null;
      _reScore();
    }
  }

  Future<void> _runCommitOnlySearch(
      String repoPath, String query, int gen) async {
    if (query.length < 3) return;
    _isLoading = true;
    notifyListeners();
    final result = await git_backend.searchCommits(repoPath, query);
    if (gen != _generation) return;
    _asyncEntries = result.ok
        ? result.data!
              .take(20)
              .map(
                (c) => PaletteEntry(
                  id: 'commit.${c.commitHash}',
                  label: c.subject,
                  subtitle: '${c.shortHash} — ${c.authorName}',
                  category: PaletteCategory.commit,
                  actionType: PaletteActionType.execute,
                  refPath: c.commitHash,
                ),
              )
              .toList()
        : [];
    _isLoading = false;
    _reScore();
  }

  Future<void> _runAsyncSearch(String repoPath, String query, int gen) async {
    _isLoading = true;
    notifyListeners();

    final gitFuture = searchWithCache(repoPath, query, _gitCache);
    final willWick = query.length >= 3 && _wickState != null && _wickState!.available;
    if (willWick) {
      _wickSearching = true;
      notifyListeners();
    }
    final wickFuture = _searchWick(repoPath, query);

    final results = await gitFuture;
    if (gen != _generation) return;
    _asyncEntries = results;

    final wickResult = await wickFuture;
    if (gen != _generation) return;
    _wickSearching = false;
    if (wickResult != null && wickResult.packet.isNotEmpty) {
      _wickEntries = wickResult.packet..sort((a, b) => a.rank.compareTo(b.rank));
      _wickPosture = wickResult.posture;
    } else {
      _wickEntries = [];
      _wickPosture = null;
    }
    _isLoading = false;
    _reScore();
  }

  Future<WickQueryResponse?> _searchWick(String repoPath, String query) async {
    if (query.length < 3) return null;
    final wick = _wickState;
    if (wick == null || !wick.available) return null;
    return wick.query(repoPath, query);
  }

  bool get isWarming => _warmingEntryId != null;
  String? get warmingEntryId => _warmingEntryId;

  /// Returns true if the entry needs the Logos engine and it's not
  /// warm yet. First press enters warming state, kicks off engine
  /// load, and auto-executes when ready. Returns false if engine
  /// is already warm or entry doesn't need it.
  bool needsWarm(PaletteEntry entry) {
    if (!entry.hasTag(EntryTag.needsEngine)) return false;
    final targetPath = entry.refPath ?? _openRepoPath;
    if (targetPath == null || _logosState == null) return false;
    if (_logosState!.engineFor(targetPath) != null) return false;

    _warmingEntryId = entry.id;
    notifyListeners();

    final gen = _generation;
    final exec = entry.onExecute;
    _logosState!.loadForRepo(targetPath).then((_) {
      if (gen != _generation) return;
      _warmingEntryId = null;
      exec?.call();
      notifyListeners();
    });
    return true;
  }

  /// Returns true if the entry needs a second confirmation press
  /// (destructive action in elevated mode). Returns false if ready.
  bool needsConfirm(PaletteEntry entry) {
    if (!elevated) return false;
    if (!entry.tags.any(_isDestructiveTag)) return false;
    if (_pendingConfirmId == entry.id && hasPendingConfirm) return false;
    _pendingConfirmId = entry.id;
    _pendingConfirmAt = DateTime.now();
    notifyListeners();
    return true;
  }

  void _reScore() {
    final all = [..._staticEntries, ..._asyncEntries];

    final prefixCtx = PrefixContext(
      repoPath: _openRepoPath,
      recentPaths: _context.recentPaths,
      callbacks: _callbacks,
      engine: _engine,
      aiActivity: _aiActivity,
      tools: _toolsState,
    );
    for (final prefix in _prefixes) {
      if (prefix.matches(_query)) {
        final body = prefix.extractBody(_query);
        final entries = prefix.buildEntries(body, prefixCtx);
        all.insertAll(0, entries);
        break;
      }
    }

    _scorer.scoreAll(all, _query, _context, engine: _engine);
    all.removeWhere((e) => e.score <= 0);
    if (!elevated) {
      all.removeWhere((e) => e.tags.any(_isDestructiveTag));
    }

    _dedup(all);

    all.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      final catCmp = a.category.index.compareTo(b.category.index);
      if (catCmp != 0) return catCmp;
      return a.label.compareTo(b.label);
    });
    _results = all;
    _selectedIndex = _results.isEmpty
        ? 0
        : _selectedIndex.clamp(0, _results.length - 1);
    notifyListeners();
  }

  void _dedup(List<PaletteEntry> entries) {
    final byKey = <String, List<PaletteEntry>>{};
    for (final e in entries) {
      if (e.refPath == null) continue;
      final key = '${e.category.index}:${e.refPath}';
      byKey.putIfAbsent(key, () => []).add(e);
    }
    final toRemove = <PaletteEntry>{};
    for (final group in byKey.values) {
      if (group.length < 2) continue;
      group.sort((a, b) => b.score.compareTo(a.score));
      final winner = group.first;
      final chips = <String>{};
      if (winner.chipLabel != null) chips.add(winner.chipLabel!);
      for (var i = 1; i < group.length; i++) {
        final dup = group[i];
        if (dup.chipLabel != null) chips.add(dup.chipLabel!);
        winner.tags = {...winner.tags, ...dup.tags};
        toRemove.add(dup);
      }
      winner.chipStack = chips.toList();
    }
    if (toRemove.isNotEmpty) {
      entries.removeWhere(toRemove.contains);
    }
  }

  void moveSelection(int delta) {
    if (_results.isEmpty) return;
    _hoverDebounce?.cancel();
    _selectedIndex = (_selectedIndex + delta).clamp(0, _results.length - 1);
    notifyListeners();
  }

  void hoverSelect(int index) {
    if (index == _selectedIndex) return;
    if (index < 0 || index >= _results.length) return;
    _hoverDebounce?.cancel();
    _hoverDebounce = Timer(const Duration(milliseconds: 35), () {
      if (index >= _results.length) return;
      _selectedIndex = index;
      notifyListeners();
    });
  }

  void recordUsage(String id) {
    _usageFrequency[id] = (_usageFrequency[id] ?? 0) + 1;
    _recency[id] = DateTime.now();

    if (_query.length >= 2) {
      final prefix = _query.substring(0, 2).toLowerCase();
      _queryFrequency.putIfAbsent(prefix, () => {});
      _queryFrequency[prefix]![id] =
          (_queryFrequency[prefix]![id] ?? 0) + 1;
    }

    if (_lastExecutedId != null) {
      _transitions.putIfAbsent(_lastExecutedId!, () => {});
      _transitions[_lastExecutedId!]![id] =
          (_transitions[_lastExecutedId!]![id] ?? 0) + 1;
    }
    _lastExecutedId = id;

    final rk = _openRepoPath ?? '';
    _allFrequency[rk] = _usageFrequency;
    _allRecency[rk] = _recency;
    _allQueryFrequency[rk] = _queryFrequency;
    _allTransitions[rk] = _transitions;
    _persistUsage();
  }

  void _loadUsageSync() {
    if (_usageLoaded) return;
    _usageLoaded = true;
    try {
      final dir = StoragePaths.gdpuDataDirSync();
      if (dir == null) return;
      final file =
          File('${dir.path}${Platform.pathSeparator}palette_usage.json');
      if (!file.existsSync()) return;
      final raw =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      // Parse EVERYTHING into locals first (parsePaletteUsage throws on any
      // malformed field), then commit all four maps together. Previously each
      // map was assigned in sequence with eager casts, so a wrong-typed later
      // field threw AFTER an earlier map had already committed — a silent
      // partial (franken) load, since the enclosing catch swallowed the throw.
      // All-or-nothing makes that state unrepresentable: a bad field means we
      // commit nothing and degrade to empty.
      final parsed = parsePaletteUsage(raw);
      _allFrequency.addAll(parsed.frequency);
      _allRecency.addAll(parsed.recency);
      _allQueryFrequency.addAll(parsed.queryFrequency);
      _allTransitions.addAll(parsed.transitions);
      _lastExecutedId = parsed.lastExecutedId;
    } catch (_) {}
  }

  /// Marks usage state dirty and schedules an atomic flush. Called
  /// fire-and-forget from [recordUsage] on EVERY command execution, so it must
  /// not (a) block the UI or (b) let two writes to the same file race. It is
  /// coalesced (a burst of executions collapses to one write within
  /// [_kPersistDebounce]) and single-flighted (never two writes in flight),
  /// and the actual write goes through [writeFileAtomicString] so the file is
  /// never torn — previously each execution did a bare `writeAsString`, which
  /// two overlapping fire-and-forget calls could interleave and corrupt with
  /// no crash required. The snapshot is rebuilt from the live maps AT WRITE
  /// TIME, so a coalesced flush always persists the latest state.
  void _persistUsage() {
    _persistDirty = true;
    // Fixed-window coalesce: fire once, ~1s after the first dirtying in a
    // burst. A resetting debounce could starve under continuous use; this
    // bounds staleness to _kPersistDebounce.
    _persistTimer ??= Timer(_kPersistDebounce, () {
      _persistTimer = null;
      if (_disposed) return;
      unawaited(_drainUsageWrites());
    });
  }

  /// Single-flight drain: writes while dirty, re-capturing the latest state
  /// each pass, so at most one write is ever in flight for this file.
  Future<void> _drainUsageWrites() async {
    if (_persistDraining != null) return; // already draining
    Future<void> loop() async {
      while (_persistDirty) {
        _persistDirty = false;
        await _writeUsageSnapshot();
      }
    }

    _persistDraining = loop();
    try {
      await _persistDraining;
    } finally {
      _persistDraining = null;
    }
  }

  /// Forces any pending usage write to complete now, bypassing the debounce.
  /// Test-only: lets a test assert the persisted file deterministically
  /// without waiting on the real timer.
  @visibleForTesting
  Future<void> debugFlushUsage() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _drainUsageWrites();
  }

  Future<void> _writeUsageSnapshot() async {
    try {
      final file = await _usageFile();
      final repos = <String, dynamic>{};
      for (final rk in {
        ..._allFrequency.keys,
        ..._allRecency.keys,
        ..._allQueryFrequency.keys,
        ..._allTransitions.keys,
      }) {
        repos[rk] = {
          'frequency': _allFrequency[rk] ?? {},
          'recency': (_allRecency[rk] ?? {})
              .map((k, v) => MapEntry(k, v.toIso8601String())),
          'queryFrequency': _allQueryFrequency[rk] ?? {},
          'transitions': _allTransitions[rk] ?? {},
        };
      }
      await writeFileAtomicString(
        file,
        jsonEncode({'repos': repos, 'lastExecutedId': _lastExecutedId}),
      );
    } catch (_) {}
  }

  static bool _isDestructiveTag(EntryTag t) => switch (t) {
        EntryTag.discardAll ||
        EntryTag.branchDelete ||
        EntryTag.stashDrop ||
        EntryTag.syncForcePush ||
        EntryTag.revertCommit =>
          true,
        _ => false,
      };

  static Future<File> _usageFile() async {
    final dir = await StoragePaths.gdpuDataDir();
    return File('${dir.path}${Platform.pathSeparator}palette_usage.json');
  }
}

/// The four per-repo usage maps plus the last-executed id, parsed
/// all-or-nothing from a `palette_usage.json` payload. Exposed for the
/// franken-load law: the maps are plain data, so a headless test can parse a
/// hostile payload and assert the parse either yields a complete result or
/// throws — never a partial commit.
@visibleForTesting
class PaletteUsageParse {
  const PaletteUsageParse({
    required this.frequency,
    required this.recency,
    required this.queryFrequency,
    required this.transitions,
    required this.lastExecutedId,
  });

  final Map<String, Map<String, int>> frequency;
  final Map<String, Map<String, DateTime>> recency;
  final Map<String, Map<String, Map<String, int>>> queryFrequency;
  final Map<String, Map<String, Map<String, int>>> transitions;
  final String? lastExecutedId;
}

/// Pure, side-effect-free parse of a `palette_usage.json` [raw] payload into a
/// [PaletteUsageParse]. THROWS on any malformed field (a non-int frequency, a
/// non-parseable recency date, a wrong-shaped nested map) so the caller can
/// commit every map together or none — there is no return path that yields a
/// partially-populated result. Handles both the current per-repo `repos`
/// shape and the legacy single-repo top-level shape.
///
/// `@visibleForTesting`: [PaletteState._loadUsageSync] is the only production
/// caller, but the parse is the whole risk surface, so it is drivable
/// headless without the five-provider `open` path.
@visibleForTesting
PaletteUsageParse parsePaletteUsage(Map<String, dynamic> raw) {
  final frequency = <String, Map<String, int>>{};
  final recency = <String, Map<String, DateTime>>{};
  final queryFrequency = <String, Map<String, Map<String, int>>>{};
  final transitions = <String, Map<String, Map<String, int>>>{};

  Map<String, Map<String, int>> nested(Map<String, dynamic>? m) =>
      m?.map((k, v) => MapEntry(
            k,
            (v as Map<String, dynamic>)
                .map((k2, v2) => MapEntry(k2, v2 as int)),
          )) ??
      {};

  final repos = raw['repos'] as Map<String, dynamic>?;
  if (repos != null) {
    for (final e in repos.entries) {
      final rd = e.value as Map<String, dynamic>;
      frequency[e.key] = (rd['frequency'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {};
      recency[e.key] = (rd['recency'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, DateTime.parse(v as String))) ??
          {};
      queryFrequency[e.key] =
          nested(rd['queryFrequency'] as Map<String, dynamic>?);
      transitions[e.key] =
          nested(rd['transitions'] as Map<String, dynamic>?);
    }
    return PaletteUsageParse(
      frequency: frequency,
      recency: recency,
      queryFrequency: queryFrequency,
      transitions: transitions,
      lastExecutedId: raw['lastExecutedId'] as String?,
    );
  }

  // Legacy single-repo (top-level) shape.
  final freq = raw['frequency'] as Map<String, dynamic>?;
  final rec = raw['recency'] as Map<String, dynamic>?;
  final qf = raw['queryFrequency'] as Map<String, dynamic>?;
  if (freq != null) {
    frequency[''] = freq.map((k, v) => MapEntry(k, v as int));
  }
  if (rec != null) {
    recency[''] = rec.map((k, v) => MapEntry(k, DateTime.parse(v as String)));
  }
  if (qf != null) {
    queryFrequency[''] = nested(qf);
  }
  return PaletteUsageParse(
    frequency: frequency,
    recency: recency,
    queryFrequency: queryFrequency,
    transitions: transitions,
    lastExecutedId: null,
  );
}
