import 'package:flutter/foundation.dart';

import '../backend/ai_settings_store.dart';
import '../backend/dtos.dart';

class AiSettingsState extends ChangeNotifier {
  bool _loaded = false;
  Map<String, String> _modelSelections = {};
  Map<String, String> _modelCategoryLabels = {
    'quality': 'Quality model',
    'fast': 'Fast model',
  };
  String _commitMessageModelCategoryId = 'quality';
  String _commitMessagePrompt = '';
  String _commitMessagePromptPath = '';

  bool get isLoaded => _loaded;
  Map<String, String> get modelSelections => Map.unmodifiable(_modelSelections);
  Map<String, String> get modelCategoryLabels =>
      Map.unmodifiable(_modelCategoryLabels);
  String get commitMessageModelCategoryId => _commitMessageModelCategoryId;
  String get commitMessagePrompt => _commitMessagePrompt;
  String get commitMessagePromptPath => _commitMessagePromptPath;

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    final snapshot = await AiSettingsStore.load();
    _modelSelections = Map<String, String>.from(snapshot.modelSelections);
    _modelCategoryLabels = {
      'quality': 'Quality model',
      'fast': 'Fast model',
      ...snapshot.modelCategoryLabels,
    };
    _commitMessageModelCategoryId = snapshot.commitMessageModelCategoryId;
    _commitMessagePrompt = await AiSettingsStore.loadCommitMessagePrompt();
    _commitMessagePromptPath = await AiSettingsStore.commitMessagePromptPath();
    _loaded = true;
    notifyListeners();
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
      final resolvedValue = allowedValues.contains(currentValue)
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

    if (!changed) {
      return;
    }

    _modelSelections = nextSelections;
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

  Future<void> _persistSnapshot() {
    return AiSettingsStore.persist(
      AiSettingsSnapshot(
        modelSelections: _modelSelections,
        modelCategoryLabels: _modelCategoryLabels,
        commitMessageModelCategoryId: _commitMessageModelCategoryId,
      ),
    );
  }
}
