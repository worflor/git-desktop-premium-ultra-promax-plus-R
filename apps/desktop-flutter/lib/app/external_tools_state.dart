import 'package:flutter/foundation.dart';

import '../backend/external_tools.dart';
import '../backend/settings_store.dart';

/// In-memory ChangeNotifier wrapping the persisted external-tools list.
/// Mirrors the shape of `AiSettingsState`: a `_loaded` gate, an
/// internal mutable list, an unmodifiable view exposed to widgets,
/// and per-mutation methods that persist + notify in one step.
///
/// The settings page edits via [add] / [update] / [remove] / [reorder].
/// Read-only consumers (the project context menu) just `context.watch`
/// for the list.
class ExternalToolsState extends ChangeNotifier {
  bool _loaded = false;
  List<ExternalTool> _tools = const [];
  List<ExternalTool> _toolsView = const [];

  bool get isLoaded => _loaded;

  /// Unmodifiable snapshot of the configured tools, in user-defined
  /// order. Empty when none have been added — the context menu treats
  /// this as the "Open with…" zero-state.
  List<ExternalTool> get tools => _toolsView;

  /// Convenience for the menu's zero-state branch.
  bool get isEmpty => _toolsView.isEmpty;

  Future<void> load() async {
    if (_loaded) return;
    final snapshot = await SettingsStore.load();
    _tools = List<ExternalTool>.from(snapshot.externalTools);
    _rebuildView();
    _loaded = true;
    notifyListeners();
  }

  /// Append a tool. Duplicate ids are de-duped (the most-recent entry
  /// wins) so a re-import or a buggy preset can't grow the list
  /// unboundedly.
  Future<void> add(ExternalTool tool) async {
    _tools = [
      for (final t in _tools)
        if (t.id != tool.id) t,
      tool,
    ];
    await _persist();
  }

  /// In-place mutation by id. No-op if [id] isn't in the list. Forces
  /// the id to match the original — protects against accidental id
  /// churn if the caller built [next] from a fresh constructor.
  Future<void> update(String id, ExternalTool next) async {
    var found = false;
    final out = <ExternalTool>[];
    for (final t in _tools) {
      if (t.id == id) {
        out.add(ExternalTool(
          id: id,
          label: next.label,
          executable: next.executable,
          args: next.args,
          mode: next.mode,
        ));
        found = true;
      } else {
        out.add(t);
      }
    }
    if (!found) return;
    _tools = out;
    await _persist();
  }

  /// Remove by id. No-op if [id] isn't in the list.
  Future<void> remove(String id) async {
    final next = [for (final t in _tools) if (t.id != id) t];
    if (next.length == _tools.length) return;
    _tools = next;
    await _persist();
  }

  /// Move the tool at [oldIndex] to [newIndex]. Indices are clamped
  /// to the current list length so a stale drag from a parallel
  /// rebuild can't crash.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (_tools.isEmpty) return;
    final clampedOld = oldIndex.clamp(0, _tools.length - 1);
    var clampedNew = newIndex.clamp(0, _tools.length);
    if (clampedNew > clampedOld) clampedNew -= 1;
    if (clampedOld == clampedNew) return;
    final next = List<ExternalTool>.from(_tools);
    final item = next.removeAt(clampedOld);
    next.insert(clampedNew, item);
    _tools = next;
    await _persist();
  }

  Future<void> _persist() async {
    _rebuildView();
    final snapshot = await SettingsStore.load();
    await SettingsStore.persist(
      snapshot.copyWith(externalTools: _tools),
    );
    notifyListeners();
  }

  void _rebuildView() {
    _toolsView = List<ExternalTool>.unmodifiable(_tools);
  }
}
