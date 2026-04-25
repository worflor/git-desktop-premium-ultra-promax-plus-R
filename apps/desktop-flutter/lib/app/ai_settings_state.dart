import 'package:flutter/foundation.dart';

import '../backend/ai.dart';
import '../backend/ai_settings_store.dart';
import '../backend/dtos.dart';

class AiSettingsState extends ChangeNotifier {
  bool _loaded = false;
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
  String _musePrompt = '';
  String _musePromptPath = '';
  String _museBrainstormModelCategoryId = 'fast';
  String _museSynthesisModelCategoryId = 'quality';
  List<AiProviderStatus> _runtimeProviders = const [];
  String? _runtimeProvidersError;
  bool _runtimeProvidersLoading = false;
  List<AiModelCategoryData> _runtimeModelCategories = const [];
  String? _runtimeModelCategoriesError;
  bool _runtimeModelCategoriesLoading = false;
  Future<bool>? _providerRefreshFuture;
  Future<bool>? _modelCategoryRefreshFuture;

  bool get isLoaded => _loaded;
  Map<String, String> get modelSelections => _modelSelectionsView;
  Map<String, String> get modelCategoryLabels => _modelCategoryLabelsView;
  String get commitMessageModelCategoryId => _commitMessageModelCategoryId;
  String get commitMessagePrompt => _commitMessagePrompt;
  String get commitMessagePromptPath => _commitMessagePromptPath;
  String get reviewCommitModelCategoryId => _reviewCommitModelCategoryId;
  String get reviewCommitPrompt => _reviewCommitPrompt;
  String get reviewCommitPromptPath => _reviewCommitPromptPath;
  bool get reviewCommitDoubleCheckEnabled => _reviewCommitDoubleCheckEnabled;
  String get musePrompt => _musePrompt;
  String get musePromptPath => _musePromptPath;
  String get museBrainstormModelCategoryId => _museBrainstormModelCategoryId;
  String get museSynthesisModelCategoryId => _museSynthesisModelCategoryId;
  List<AiProviderStatus> get runtimeProviders => _runtimeProvidersView;
  String? get runtimeProvidersError => _runtimeProvidersError;
  bool get runtimeProvidersLoading => _runtimeProvidersLoading;
  List<AiModelCategoryData> get runtimeModelCategories =>
      _runtimeModelCategoriesView;
  String? get runtimeModelCategoriesError => _runtimeModelCategoriesError;
  bool get runtimeModelCategoriesLoading => _runtimeModelCategoriesLoading;

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

    final snapshot = await snapshotFuture;
    _modelSelections = Map<String, String>.from(snapshot.modelSelections);
    _modelCategoryLabels = {
      'quality': 'Quality',
      'fast': 'Fast',
      ...snapshot.modelCategoryLabels,
    };
    _rebuildModelViews();
    _commitMessageModelCategoryId = snapshot.commitMessageModelCategoryId;
    _reviewCommitModelCategoryId = snapshot.reviewCommitModelCategoryId;
    _reviewCommitDoubleCheckEnabled = snapshot.reviewCommitDoubleCheckEnabled;
    _museBrainstormModelCategoryId = snapshot.museBrainstormModelCategoryId;
    _museSynthesisModelCategoryId = snapshot.museSynthesisModelCategoryId;

    _commitMessagePrompt = await commitPromptFuture;
    _commitMessagePromptPath = await commitPathFuture;
    _reviewCommitPrompt = await reviewPromptFuture;
    _reviewCommitPromptPath = await reviewPathFuture;
    _musePrompt = await musePromptFuture;
    _musePromptPath = await musePathFuture;
    _loaded = true;
    notifyListeners();
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

  Future<bool> refreshProviders({bool forceRefresh = false}) {
    if (!forceRefresh && _runtimeProviders.isNotEmpty) {
      return SynchronousFuture(true);
    }
    final inFlight = _providerRefreshFuture;
    if (inFlight != null) {
      return inFlight;
    }

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

  Future<bool> refreshModelCategories({bool forceRefresh = false}) {
    if (!forceRefresh && _runtimeModelCategories.isNotEmpty) {
      return SynchronousFuture(true);
    }
    final inFlight = _modelCategoryRefreshFuture;
    if (inFlight != null) {
      return inFlight;
    }

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

  Future<void> _persistSnapshot() {
    return AiSettingsStore.persist(
      AiSettingsSnapshot(
        modelSelections: _modelSelections,
        modelCategoryLabels: _modelCategoryLabels,
        commitMessageModelCategoryId: _commitMessageModelCategoryId,
        reviewCommitModelCategoryId: _reviewCommitModelCategoryId,
        reviewCommitDoubleCheckEnabled: _reviewCommitDoubleCheckEnabled,
        museBrainstormModelCategoryId: _museBrainstormModelCategoryId,
        museSynthesisModelCategoryId: _museSynthesisModelCategoryId,
      ),
    );
  }
}
