// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/ai.dart';
import '../backend/ai_api_keys_store.dart';
import '../backend/ai_settings_store.dart';
import '../backend/dtos.dart';

/// Lifecycle of opencode's background model-metadata enrichment, surfaced in the
/// model picker so the reasoning-slider delay reads as intentional rather than
/// broken.
enum OpencodeEnrichState { none, warming, unavailable }

class AiSettingsState extends ChangeNotifier {
  bool _loaded = false;
  AiApiKeysSnapshot _apiKeys = AiApiKeysSnapshot.empty();
  Map<String, String> _modelSelections = {};
  // Cached unmodifiable views. Rebuilt only when the underlying map
  // changes; previously each getter call allocated a fresh
  // `Map.unmodifiable`, which is a hot allocation on widgets that
  // rebuild every frame under `context.watch<AiSettingsState>()`.
  Map<String, String> _modelSelectionsView =
      const <String, String>{};
  Map<String, String> _modelCategoryLabelsView = const <String, String>{};
  List<AiProviderStatus> _runtimeProvidersView =
      const <AiProviderStatus>[];
  List<AiModelCategoryData> _runtimeModelCategoriesView =
      const <AiModelCategoryData>[];
  Map<String, String> _reasoningEfforts = {};
  Map<String, String> _modelCategoryLabels = {
    'quality': 'Quality',
    'fast': 'Fast',
  };
  String _commitMessageModelCategoryId = 'quality';
  String _commitMessagePrompt = '';
  String _commitMessagePromptPath = '';
  String _reviewCommitModelCategoryId = 'quality';
  String _reviewCommitPrompt = '';
  String _reviewCommitPromptPath = '';
  bool _reviewCommitDoubleCheckEnabled = false;
  String _apiPiggybackCli = 'codex';
  int _cliTimeoutSeconds = 1200;
  String _musePrompt = '';
  String _musePromptPath = '';
  String _museBrainstormModelCategoryId = 'fast';
  String _museSynthesisModelCategoryId = 'quality';
  List<MuseQuiverEntry> _museQuiver = defaultMuseQuiver();
  List<MuseQuiverEntry> _museQuiverView = List.unmodifiable(defaultMuseQuiver());
  List<MuseStrandKind> _museStrandOrder = List.of(kMuseStrandDisplayOrder);
  List<MuseStrandKind> _museStrandOrderView =
      List.unmodifiable(kMuseStrandDisplayOrder);
  String _presentModelCategoryId = 'quality';
  String _presentPrompt = '';
  String _presentPromptPath = '';
  List<AiProviderStatus> _runtimeProviders = const [];
  String? _runtimeProvidersError;
  bool _runtimeProvidersLoading = false;
  List<AiModelCategoryData> _runtimeModelCategories = const [];
  String? _runtimeModelCategoriesError;
  bool _runtimeModelCategoriesLoading = false;
  Future<bool>? _providerRefreshFuture;
  Future<bool>? _modelCategoryRefreshFuture;

  bool get isLoaded => _loaded;
  AiApiKeysSnapshot get apiKeys => _apiKeys;
  Map<String, String> get modelSelections => _modelSelectionsView;
  Map<String, String> get reasoningEfforts => _reasoningEfforts;
  Map<String, String> get modelCategoryLabels => _modelCategoryLabelsView;
  String get commitMessageModelCategoryId => _commitMessageModelCategoryId;
  String get commitMessagePrompt => _commitMessagePrompt;
  String get commitMessagePromptPath => _commitMessagePromptPath;
  String get reviewCommitModelCategoryId => _reviewCommitModelCategoryId;
  String get reviewCommitPrompt => _reviewCommitPrompt;
  String get reviewCommitPromptPath => _reviewCommitPromptPath;
  bool get reviewCommitDoubleCheckEnabled => _reviewCommitDoubleCheckEnabled;
  String get apiPiggybackCli => _apiPiggybackCli;
  /// Per-attempt wall-clock cap (seconds) for the long-running AI CLIs. The UI
  /// edits this in minutes; the backend consumes it via [configureCliTimeout].
  int get cliTimeoutSeconds => _cliTimeoutSeconds;
  String get musePrompt => _musePrompt;
  String get musePromptPath => _musePromptPath;
  String get museBrainstormModelCategoryId => _museBrainstormModelCategoryId;
  String get museSynthesisModelCategoryId => _museSynthesisModelCategoryId;
  /// The user's active muse loadout — which strands the muse will
  /// throw on its next call, and how many walkers of each. Read-only
  /// view; mutate via [setMuseQuiver].
  List<MuseQuiverEntry> get museQuiver => _museQuiverView;
  /// The order strands render in across the settings strand strip and
  /// the muse output panel. A complete ordering of every strand;
  /// reorder via [setMuseStrandOrder]. Orthogonal to [museQuiver].
  List<MuseStrandKind> get museStrandOrder => _museStrandOrderView;
  String get presentModelCategoryId => _presentModelCategoryId;
  String get presentPrompt => _presentPrompt;
  String get presentPromptPath => _presentPromptPath;
  List<AiProviderStatus> get runtimeProviders => _runtimeProvidersView;
  String? get runtimeProvidersError => _runtimeProvidersError;
  bool get runtimeProvidersLoading => _runtimeProvidersLoading;
  List<AiModelCategoryData> get runtimeModelCategories =>
      _runtimeModelCategoriesView;
  String? get runtimeModelCategoriesError => _runtimeModelCategoriesError;
  bool get runtimeModelCategoriesLoading => _runtimeModelCategoriesLoading;

  bool get hasApiProvidersWithoutModels {
    if (_apiKeys.entries.isEmpty) return false;
    final providerIdsInCategories = <String>{};
    for (final cat in _runtimeModelCategories) {
      for (final m in cat.models) {
        providerIdsInCategories.add(m.providerId);
      }
    }
    for (final providerId in _apiKeys.entries.keys) {
      if (!providerIdsInCategories.contains(providerId)) return true;
    }
    return false;
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    // Settings snapshot is a single disk read; prompts + paths are six
    // further independent awaits. Fanning them out via `Future.wait`
    // turns a 7-step serial chain into one round-trip — prompt files
    // aren't dependencies of one another.
    final snapshotFuture = AiSettingsStore.load();
    final commitPromptFuture = AiSettingsStore.loadCommitMessagePrompt();
    final commitPathFuture = AiSettingsStore.commitMessagePromptPath();
    final reviewPromptFuture = AiSettingsStore.loadReviewCommitPrompt();
    final reviewPathFuture = AiSettingsStore.reviewCommitPromptPath();
    final musePromptFuture = AiSettingsStore.loadMusePrompt();
    final musePathFuture = AiSettingsStore.musePromptPath();
    final presentPromptFuture = AiSettingsStore.loadPresentPrompt();
    final presentPathFuture = AiSettingsStore.presentPromptPath();

    final snapshot = await snapshotFuture;
    _modelSelections = Map<String, String>.from(snapshot.modelSelections);
    _reasoningEfforts = Map<String, String>.from(snapshot.reasoningEfforts);
    _modelCategoryLabels = {
      'quality': 'Quality',
      'fast': 'Fast',
      ...snapshot.modelCategoryLabels,
    };
    _rebuildModelViews();
    _commitMessageModelCategoryId = snapshot.commitMessageModelCategoryId;
    _reviewCommitModelCategoryId = snapshot.reviewCommitModelCategoryId;
    _reviewCommitDoubleCheckEnabled = snapshot.reviewCommitDoubleCheckEnabled;
    _apiPiggybackCli = snapshot.apiPiggybackCli;
    _cliTimeoutSeconds = snapshot.cliTimeoutSeconds;
    // Seed the module-level transport snapshot ai.dart consults at its
    // single dispatch seam, so every API-model call (review, muse, ask,
    // debug, patch, commit) picks up the policy without threading it.
    configurePiggybackCli(_apiPiggybackCli);
    // Same seam for the CLI runtime cap — pushed in once here, and on every
    // setter change, so _runtimeTimeoutFor picks it up without threading.
    configureCliTimeout(Duration(seconds: _cliTimeoutSeconds));
    _museBrainstormModelCategoryId = snapshot.museBrainstormModelCategoryId;
    _museSynthesisModelCategoryId = snapshot.museSynthesisModelCategoryId;
    final loadedQuiver = snapshot.museQuiver.isEmpty
        ? defaultMuseQuiver()
        : snapshot.museQuiver;
    _museQuiver = List.of(loadedQuiver);
    _museQuiverView = List.unmodifiable(_museQuiver);
    _museStrandOrder = normalizeMuseStrandOrder(snapshot.museStrandOrder);
    _museStrandOrderView = List.unmodifiable(_museStrandOrder);
    _presentModelCategoryId = snapshot.presentModelCategoryId;

    _commitMessagePrompt = await commitPromptFuture;
    _commitMessagePromptPath = await commitPathFuture;
    _reviewCommitPrompt = await reviewPromptFuture;
    _reviewCommitPromptPath = await reviewPathFuture;
    _musePrompt = await musePromptFuture;
    _musePromptPath = await musePathFuture;
    _presentPrompt = await presentPromptFuture;
    _presentPromptPath = await presentPathFuture;
    await loadApiProviderKeys();
    _apiKeys = currentApiKeys;
    _loaded = true;
    notifyListeners();

    // Force-refresh so that any prior CLI-only discovery gets replaced
    // with a full pass that includes API providers. Without forceRefresh,
    // the isNotEmpty guard would short-circuit if the settings page
    // triggered a CLI-only discovery before load() finished.
    final hasApiKeys = _apiKeys.entries.isNotEmpty;
    unawaited(refreshProviders(forceRefresh: hasApiKeys));
    unawaited(refreshModelCategories(forceRefresh: hasApiKeys));
  }

  void _rebuildModelViews() {
    _modelSelectionsView = Map<String, String>.unmodifiable(_modelSelections);
    _modelCategoryLabelsView =
        Map<String, String>.unmodifiable(_modelCategoryLabels);
  }

  String labelForCategory(String categoryId, String fallbackLabel) {
    final override = _modelCategoryLabels[categoryId]?.trim() ?? '';
    return override.isEmpty ? fallbackLabel : override;
  }

  Future<void> syncModelCategories(List<AiModelCategoryData> categories) async {
    if (categories.isEmpty) {
      return;
    }

    var changed = false;
    final nextSelections = <String, String>{};
    final activeCategoryIds = categories.map((category) => category.id).toSet();

    for (final category in categories) {
      _modelCategoryLabels.putIfAbsent(category.id, () => category.label);
      final allowedValues = category.models.map((model) => model.value).toSet();
      final currentValue = _modelSelections[category.id] ?? '';
      final providerIds = category.models.map((m) => m.providerId).toSet();
      final isCustomValue = currentValue.contains(':') &&
          providerIds.contains(currentValue.split(':').first);
      final resolvedValue = allowedValues.contains(currentValue) || isCustomValue
          ? currentValue
          : (category.models.isNotEmpty ? category.models.first.value : '');
      if (resolvedValue.isNotEmpty) {
        nextSelections[category.id] = resolvedValue;
      }
      if ((_modelSelections[category.id] ?? '') != resolvedValue) {
        changed = true;
      }
    }

    if (_modelSelections.keys.any((key) => !activeCategoryIds.contains(key))) {
      changed = true;
    }

    if (!activeCategoryIds.contains(_commitMessageModelCategoryId)) {
      _commitMessageModelCategoryId = categories.first.id;
      changed = true;
    }
    if (!activeCategoryIds.contains(_reviewCommitModelCategoryId)) {
      _reviewCommitModelCategoryId = categories.first.id;
      changed = true;
    }
    // Positional heuristic — scales with however many categories exist.
    // Synthesis takes the FIRST category (convention: primary / strongest);
    // brainstorm takes the LAST (convention: cheapest / fastest if there
    // are multiple, falls back to the same as synthesis if only one).
    if (!activeCategoryIds.contains(_museSynthesisModelCategoryId)) {
      _museSynthesisModelCategoryId = categories.first.id;
      changed = true;
    }
    if (!activeCategoryIds.contains(_museBrainstormModelCategoryId)) {
      _museBrainstormModelCategoryId = categories.last.id;
      changed = true;
    }
    if (!activeCategoryIds.contains(_presentModelCategoryId)) {
      _presentModelCategoryId = categories.last.id;
      changed = true;
    }

    if (!changed) {
      return;
    }

    _modelSelections = nextSelections;
    _rebuildModelViews();
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setModelSelection(String categoryId, String value) async {
    if ((_modelSelections[categoryId] ?? '') == value) {
      return;
    }

    _modelSelections = {
      ..._modelSelections,
      categoryId: value,
    };
    _rebuildModelViews();
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setCategoryLabel(String categoryId, String value) async {
    final normalized = value.trim();
    final current = _modelCategoryLabels[categoryId]?.trim() ?? '';
    if (current == normalized) {
      return;
    }

    _modelCategoryLabels = {
      ..._modelCategoryLabels,
      categoryId: normalized,
    };
    _rebuildModelViews();
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setCommitMessageModelCategoryId(String categoryId) async {
    if (_commitMessageModelCategoryId == categoryId) {
      return;
    }

    _commitMessageModelCategoryId = categoryId;
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setCommitMessagePrompt(String value) async {
    if (_commitMessagePrompt == value) {
      return;
    }

    _commitMessagePrompt = value;
    await AiSettingsStore.persistCommitMessagePrompt(value);
    notifyListeners();
  }

  Future<void> setReviewCommitModelCategoryId(String categoryId) async {
    if (_reviewCommitModelCategoryId == categoryId) {
      return;
    }

    _reviewCommitModelCategoryId = categoryId;
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setReviewCommitPrompt(String value) async {
    if (_reviewCommitPrompt == value) {
      return;
    }

    _reviewCommitPrompt = value;
    await AiSettingsStore.persistReviewCommitPrompt(value);
    notifyListeners();
  }

  Future<void> setReviewCommitDoubleCheckEnabled(bool value) async {
    if (_reviewCommitDoubleCheckEnabled == value) {
      return;
    }

    _reviewCommitDoubleCheckEnabled = value;
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setApiPiggybackCli(String value) async {
    var normalized = value.trim();
    // Same closed set the store enforces on load: an unknown carrier can
    // neither render in the dropdown nor dispatch, so it never gets in.
    if (normalized.isNotEmpty &&
        !kSupportedPiggybackClis.contains(normalized)) {
      normalized = 'codex';
    }
    if (_apiPiggybackCli == normalized) {
      return;
    }

    final previous = _apiPiggybackCli;
    _apiPiggybackCli = normalized;
    // Push the new policy into ai.dart's dispatch-seam snapshot so it
    // takes effect immediately, before persistence or listeners.
    configurePiggybackCli(_apiPiggybackCli);
    try {
      await _persistSnapshot();
    } catch (_) {
      // A failed save must not leave the live transport out of sync with
      // what's on disk and with what the UI reports: roll both the field
      // and the dispatch-seam snapshot back before surfacing the error.
      _apiPiggybackCli = previous;
      configurePiggybackCli(previous);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> setCliTimeoutSeconds(int value) async {
    // Same bounds the store clamps to on load (30s .. 2h).
    final clamped = value.clamp(30, 7200);
    if (_cliTimeoutSeconds == clamped) {
      return;
    }

    final previous = _cliTimeoutSeconds;
    _cliTimeoutSeconds = clamped;
    // Push into ai.dart's timeout seam immediately, before persistence, so a
    // run started right after the change already sees the new cap.
    configureCliTimeout(Duration(seconds: _cliTimeoutSeconds));
    try {
      await _persistSnapshot();
    } catch (_) {
      _cliTimeoutSeconds = previous;
      configureCliTimeout(Duration(seconds: previous));
      rethrow;
    }
    notifyListeners();
  }

  Future<void> setMusePrompt(String value) async {
    if (_musePrompt == value) return;
    _musePrompt = value;
    await AiSettingsStore.persistMusePrompt(value);
    notifyListeners();
  }

  Future<void> setMuseBrainstormModelCategoryId(String categoryId) async {
    if (_museBrainstormModelCategoryId == categoryId) return;
    _museBrainstormModelCategoryId = categoryId;
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setMuseSynthesisModelCategoryId(String categoryId) async {
    if (_museSynthesisModelCategoryId == categoryId) return;
    _museSynthesisModelCategoryId = categoryId;
    await _persistSnapshot();
    notifyListeners();
  }

  /// Replace the active muse loadout. Empty list snaps back to the
  /// default 4-strand quiver — the muse always has at least one
  /// walker to throw.
  Future<void> setMuseQuiver(List<MuseQuiverEntry> entries) async {
    final next = entries.isEmpty ? defaultMuseQuiver() : List.of(entries);
    // Skip the round-trip + notify if the new loadout is identical to
    // the old. Quivers are small (≤16 entries); element-wise compare
    // is trivial.
    if (next.length == _museQuiver.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (next[i].kind != _museQuiver[i].kind ||
            next[i].count != _museQuiver[i].count) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _museQuiver = next;
    _museQuiverView = List.unmodifiable(_museQuiver);
    await _persistSnapshot();
    notifyListeners();
  }

  /// Reorder the strands. The incoming list is normalised to a complete
  /// ordering, so callers can pass a partial reorder and trust every
  /// strand still ends up present exactly once. No-ops (and skips the
  /// disk write + notify) when the resulting order is unchanged.
  Future<void> setMuseStrandOrder(List<MuseStrandKind> order) async {
    final next = normalizeMuseStrandOrder(order);
    if (next.length == _museStrandOrder.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (next[i] != _museStrandOrder[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _museStrandOrder = next;
    _museStrandOrderView = List.unmodifiable(_museStrandOrder);
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setPresentModelCategoryId(String categoryId) async {
    if (_presentModelCategoryId == categoryId) return;
    _presentModelCategoryId = categoryId;
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setPresentPrompt(String value) async {
    if (_presentPrompt == value) return;
    _presentPrompt = value;
    await AiSettingsStore.persistPresentPrompt(value);
    notifyListeners();
  }

  /// Drop the persisted + in-memory model cache so stale entries (models a
  /// CLI no longer exposes) can't be served again. Callers should follow with
  /// a forced [refreshProviders] / [refreshModelCategories] to repopulate from
  /// live discovery — this only clears; it doesn't re-fetch.
  Future<void> clearModelCache() => clearAiModelCache();

  Future<bool> refreshProviders({bool forceRefresh = false}) {
    if (!forceRefresh && _runtimeProviders.isNotEmpty) {
      return SynchronousFuture(true);
    }
    final inFlight = _providerRefreshFuture;
    if (inFlight != null) return inFlight;

    _runtimeProvidersLoading = true;
    if (forceRefresh) {
      _runtimeProvidersError = null;
    }
    notifyListeners();

    final future = _runProviderRefresh(forceRefresh: forceRefresh);
    _providerRefreshFuture = future;
    return future;
  }

  Future<bool> _runProviderRefresh({required bool forceRefresh}) async {
    try {
      final result = await listAiProviders(forceRefresh: forceRefresh);
      if (result.ok) {
        _runtimeProviders = result.data!.providers;
        _runtimeProvidersView =
            List<AiProviderStatus>.unmodifiable(_runtimeProviders);
        _runtimeProvidersError = null;
      } else {
        _runtimeProvidersError = result.error;
      }
      return result.ok;
    } finally {
      _runtimeProvidersLoading = false;
      _providerRefreshFuture = null;
      notifyListeners();
    }
  }

  Timer? _opencodeEnrichTimer;
  int _opencodeEnrichAttempts = 0;
  bool _disposed = false;

  // Retries ~45s apart, so this covers ~6 min — comfortably past the cold
  // worst case (a 90s verbose timeout followed by a faster re-kick). Combined
  // with the warm overwriting the main discovery cache on completion, the
  // enriched data can't get frozen behind a stale plain result.
  static const _opencodeEnrichMaxAttempts = 8;

  bool get _openCodeModelsHaveReasoning => _runtimeModelCategories.any((c) => c
      .models
      .any((m) => m.providerId == 'opencode' && m.supportsReasoning));

  /// UI signal for the opencode enrichment lifecycle so the picker can show a
  /// "warming…" (or "details unavailable") note on the opencode header instead
  /// of the reasoning slider silently appearing late — or never — unexplained.
  OpencodeEnrichState get opencodeEnrichState {
    final hasOpenCode =
        _runtimeProviders.any((p) => p.id == 'opencode' && p.available);
    if (!hasOpenCode || _openCodeModelsHaveReasoning) {
      return OpencodeEnrichState.none;
    }
    return _opencodeEnrichAttempts >= _opencodeEnrichMaxAttempts
        ? OpencodeEnrichState.unavailable
        : OpencodeEnrichState.warming;
  }

  /// opencode's reasoning/context/pricing is warmed in the background (slow,
  /// network-bound), so the first category load intentionally lacks it and
  /// never blocks. Because the warm's own timeout is the same order as this
  /// delay, a single-shot timer would race it — so this RETRIES a forced
  /// refresh a few times, ~45s apart. Each forceRefresh re-kicks the background
  /// warm (which gets faster as opencode caches its model registry), so the
  /// enrichment reliably lands within a couple of attempts. Stops immediately
  /// once opencode models carry reasoning, when opencode isn't present, or
  /// after a bounded number of attempts — this method is re-entered after every
  /// category refresh (see _runModelCategoryRefresh).
  void _maybeScheduleOpenCodeEnrichRefresh() {
    if (_disposed) return;
    final hasOpenCode =
        _runtimeProviders.any((p) => p.id == 'opencode' && p.available);
    if (!hasOpenCode || _openCodeModelsHaveReasoning) {
      _opencodeEnrichTimer?.cancel();
      return;
    }
    if (_opencodeEnrichAttempts >= _opencodeEnrichMaxAttempts) return;
    if (_opencodeEnrichTimer?.isActive ?? false) return;
    _opencodeEnrichAttempts++;
    _opencodeEnrichTimer = Timer(const Duration(seconds: 45), () {
      // Re-verify relevance at fire time — opencode may have gone away or the
      // enrichment may already have landed while we waited, so don't force a
      // stale refresh onto a provider set that has moved on.
      if (_disposed ||
          !_runtimeProviders.any((p) => p.id == 'opencode' && p.available) ||
          _openCodeModelsHaveReasoning) {
        return;
      }
      unawaited(refreshModelCategories(forceRefresh: true));
    });
  }

  @override
  void dispose() {
    _opencodeEnrichTimer?.cancel();
    _disposed = true;
    super.dispose();
  }

  Future<bool> refreshModelCategories({bool forceRefresh = false}) {
    if (!forceRefresh &&
        _runtimeModelCategories.isNotEmpty &&
        !hasApiProvidersWithoutModels) {
      return SynchronousFuture(true);
    }
    final inFlight = _modelCategoryRefreshFuture;
    if (inFlight != null) return inFlight;

    _runtimeModelCategoriesLoading = true;
    if (forceRefresh) {
      _runtimeModelCategoriesError = null;
    }
    notifyListeners();

    final future = _runModelCategoryRefresh(forceRefresh: forceRefresh);
    _modelCategoryRefreshFuture = future;
    return future;
  }

  Future<bool> _runModelCategoryRefresh({required bool forceRefresh}) async {
    try {
      final result = await listAiModelOptions(forceRefresh: forceRefresh);
      if (result.ok) {
        _runtimeModelCategories = result.data!.categories;
        _runtimeModelCategoriesView =
            List<AiModelCategoryData>.unmodifiable(_runtimeModelCategories);
        _runtimeModelCategoriesError = null;
        await syncModelCategories(result.data!.categories);
        _maybeScheduleOpenCodeEnrichRefresh();
      } else {
        _runtimeModelCategoriesError = result.error;
      }
      return result.ok;
    } finally {
      _runtimeModelCategoriesLoading = false;
      _modelCategoryRefreshFuture = null;
      notifyListeners();
    }
  }

  String? reasoningEffortFor(String key) => _reasoningEfforts[key];

  ({String? effort, bool fast}) resolveEffort(
      String categoryId, String modelValue) {
    final effort = _reasoningEfforts['$categoryId:$modelValue'];
    final fast = _reasoningEfforts['fast:$categoryId:$modelValue'] == 'fast';
    return (effort: effort, fast: fast);
  }

  Future<void> setReasoningEffort(String key, String? effort) async {
    if (effort == null || effort.isEmpty) {
      if (!_reasoningEfforts.containsKey(key)) return;
      _reasoningEfforts = Map.of(_reasoningEfforts)..remove(key);
    } else {
      if (_reasoningEfforts[key] == effort) return;
      _reasoningEfforts = {..._reasoningEfforts, key: effort};
    }
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setReasoningEffortForCategory(
      String categoryId, String effort) async {
    final modelValue = _modelSelections[categoryId] ?? '';
    if (modelValue.isEmpty) return;
    final key = '$categoryId:$modelValue';
    if (_reasoningEfforts[key] == effort) return;
    _reasoningEfforts = {..._reasoningEfforts, key: effort};
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setReasoningEffortGlobal(String effort) async {
    var changed = false;
    final next = Map.of(_reasoningEfforts);
    for (final cat in _runtimeModelCategories) {
      final modelValue = _modelSelections[cat.id] ?? '';
      if (modelValue.isEmpty) continue;
      final key = '${cat.id}:$modelValue';
      if (next[key] != effort) {
        next[key] = effort;
        changed = true;
      }
    }
    if (!changed) return;
    _reasoningEfforts = next;
    await _persistSnapshot();
    notifyListeners();
  }

  Future<void> setApiKey(
    String providerId,
    String apiKey, {
    String? baseUrl,
  }) async {
    await updateApiProviderKey(
      providerId,
      AiApiKeyEntry(apiKey: apiKey, baseUrl: baseUrl),
    );
    _apiKeys = currentApiKeys;
    notifyListeners();
  }

  Future<void> clearApiKey(String providerId) async {
    await removeApiProviderKey(providerId);
    _apiKeys = currentApiKeys;
    notifyListeners();
  }

  AiApiKeyEntry? apiKeyFor(String providerId) => _apiKeys[providerId];

  Future<void> _persistSnapshot() {
    return AiSettingsStore.persist(
      AiSettingsSnapshot(
        modelSelections: _modelSelections,
        modelCategoryLabels: _modelCategoryLabels,
        reasoningEfforts: _reasoningEfforts,
        commitMessageModelCategoryId: _commitMessageModelCategoryId,
        reviewCommitModelCategoryId: _reviewCommitModelCategoryId,
        reviewCommitDoubleCheckEnabled: _reviewCommitDoubleCheckEnabled,
        apiPiggybackCli: _apiPiggybackCli,
        cliTimeoutSeconds: _cliTimeoutSeconds,
        museBrainstormModelCategoryId: _museBrainstormModelCategoryId,
        museSynthesisModelCategoryId: _museSynthesisModelCategoryId,
        presentModelCategoryId: _presentModelCategoryId,
        museQuiver: _museQuiver,
        museStrandOrder: _museStrandOrder,
      ),
    );
  }
}
