import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../app/logos_git_state.dart';
import '../../app/repository_state.dart';
import '../../backend/git.dart' as git_backend;
import '../../backend/logos_git.dart';
import '../../backend/repo_web_url.dart';
import '../../backend/storage_paths.dart';
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
    Map<String, String> forgeByPath);

class PaletteState extends ChangeNotifier {
  final PaletteScorer _scorer = PaletteScorer();
  final PaletteGitCache _gitCache = PaletteGitCache();
  final Map<String, String> _forgeCache = {};

  List<PaletteEntry> _staticEntries = [];
  List<PaletteEntry> _asyncEntries = [];
  List<PaletteEntry> _results = [];
  String _query = '';
  int _selectedIndex = 0;
  bool _isLoading = false;
  Timer? _debounce;
  Timer? _hoverDebounce;
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

  Map<String, Map<String, int>> _allFrequency = {};
  Map<String, Map<String, DateTime>> _allRecency = {};
  Map<String, Map<String, Map<String, int>>> _allQueryFrequency = {};
  Map<String, Map<String, Map<String, int>>> _allTransitions = {};
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
    _debounce?.cancel();
    _hoverDebounce?.cancel();
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
      _forgeCache[path] = info?.label ?? 'LOCAL';
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

      final repos = raw['repos'] as Map<String, dynamic>?;
      if (repos != null) {
        for (final e in repos.entries) {
          final rd = e.value as Map<String, dynamic>;
          _allFrequency[e.key] = (rd['frequency'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, v as int)) ??
              {};
          _allRecency[e.key] = (rd['recency'] as Map<String, dynamic>?)
                  ?.map((k, v) =>
                      MapEntry(k, DateTime.parse(v as String))) ??
              {};
          _allQueryFrequency[e.key] =
              (rd['queryFrequency'] as Map<String, dynamic>?)?.map(
                    (k, v) => MapEntry(
                      k,
                      (v as Map<String, dynamic>)
                          .map((k2, v2) => MapEntry(k2, v2 as int)),
                    ),
                  ) ??
                  {};
          _allTransitions[e.key] =
              (rd['transitions'] as Map<String, dynamic>?)?.map(
                    (k, v) => MapEntry(
                      k,
                      (v as Map<String, dynamic>)
                          .map((k2, v2) => MapEntry(k2, v2 as int)),
                    ),
                  ) ??
                  {};
        }
        _lastExecutedId = raw['lastExecutedId'] as String?;
        return;
      }

      final freq = raw['frequency'] as Map<String, dynamic>?;
      final rec = raw['recency'] as Map<String, dynamic>?;
      final qf = raw['queryFrequency'] as Map<String, dynamic>?;
      if (freq != null) {
        _allFrequency[''] = freq.map((k, v) => MapEntry(k, v as int));
      }
      if (rec != null) {
        _allRecency[''] = rec.map(
          (k, v) => MapEntry(k, DateTime.parse(v as String)),
        );
      }
      if (qf != null) {
        _allQueryFrequency[''] = qf.map(
          (k, v) => MapEntry(
            k,
            (v as Map<String, dynamic>)
                .map((k2, v2) => MapEntry(k2, v2 as int)),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _persistUsage() async {
    try {
      final file = await _usageFile();
      final dir = file.parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
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
      await file.writeAsString(jsonEncode({
        'repos': repos,
        'lastExecutedId': _lastExecutedId,
      }));
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
