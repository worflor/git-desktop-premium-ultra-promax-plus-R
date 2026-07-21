// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the primary-commit-button mode — commit-only vs the repo's
/// natural action (commit & push / sync) — per working-tree path.
///
/// Keyed by `RepositoryState.activePath`, which is worktree-specific, so
/// each desk (git worktree) of a repo keeps its own choice — the same
/// granularity the commit-draft files already use. Only `true` entries are
/// stored; an absent key means *follow the repo's natural primary action*
/// (false), which keeps the persisted JSON minimal.
class CommitModeState extends ChangeNotifier {
  final Map<String, bool> _commitOnly = {};
  Future<void> _saveQueue = Future.value();

  bool commitOnlyFor(String path) => _commitOnly[path] ?? false;

  void setCommitOnly(String path, bool value) {
    if ((_commitOnly[path] ?? false) == value) return;
    if (value) {
      _commitOnly[path] = true;
    } else {
      _commitOnly.remove(path);
    }
    _save();
    notifyListeners();
  }

  void toggle(String path) => setCommitOnly(path, !commitOnlyFor(path));

  // ── Persistence ───────────────────────────────────────────────

  static const _prefsKey = 'commit_mode';

  Future<void> load() async {
    await _flushPendingSave();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          _commitOnly.clear();
          json.forEach((k, v) {
            if (k is String && v == true) _commitOnly[k] = true;
          });
        }
      } catch (e) {
        debugPrint('[CommitMode] parse error: $e');
      }
    }
    notifyListeners();
  }

  void _save() {
    final json = jsonEncode(_commitOnly);
    _saveQueue = _saveQueue.catchError((Object e) {
      debugPrint('[CommitMode] save queue error: $e');
    }).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, json);
    }).catchError((Object e) {
      debugPrint('[CommitMode] save error: $e');
    });
  }

  Future<void> _flushPendingSave() => _saveQueue;

  @visibleForTesting
  Future<void> flushPendingSaveForTesting() => _flushPendingSave();
}
