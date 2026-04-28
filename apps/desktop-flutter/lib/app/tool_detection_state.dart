import 'package:flutter/foundation.dart';

import '../backend/tool_detection.dart';

/// In-memory cache of which preset external-tool executables resolve
/// on PATH. Drives the settings page's preset-chip row — only
/// installed tools get chips, so the user never sees a "+ Cursor"
/// suggestion for a tool they don't have.
///
/// Detection runs once on app start (fire-and-forget from main.dart,
/// like the engram pre-warm). The settings page reads [installed]
/// directly when [isLoaded] is true, or shows a brief loading hint
/// otherwise. A manual [refresh] is available for after-install
/// cases where the user added a tool with the app already open.
class ToolDetectionState extends ChangeNotifier {
  bool _isLoaded = false;
  bool _isLoading = false;
  Set<String> _installed = const {};
  // In-flight probe future — concurrent callers await this rather
  // than fanning out duplicate `where`/`which` processes. Cleared
  // when the probe finishes so the next refresh can start fresh.
  Future<void>? _inflight;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  Set<String> get installed => _installed;

  /// Probe [candidates] against PATH and cache the result. Idempotent
  /// — if a probe is already in flight, subsequent callers await the
  /// same future rather than starting a duplicate fan-out OR silently
  /// dropping the call. Critical for [refresh] correctness: a refresh
  /// that races with the startup probe used to early-return with
  /// [isLoaded] still false; now it joins the same future.
  Future<void> detect(Iterable<String> candidates) {
    final inflight = _inflight;
    if (inflight != null) return inflight;
    _isLoading = true;
    notifyListeners();
    final future = () async {
      try {
        _installed = await detectAll(candidates);
        _isLoaded = true;
      } finally {
        _isLoading = false;
        _inflight = null;
        notifyListeners();
      }
    }();
    _inflight = future;
    return future;
  }

  /// Re-probe — useful when the user adds a tool to PATH (e.g.,
  /// installs Claude or VS Code) without restarting Manifold. If a
  /// probe is already running, waits for it to finish before
  /// starting a fresh one — otherwise the await on the stale future
  /// would race with the new state mutation.
  Future<void> refresh(Iterable<String> candidates) async {
    final inflight = _inflight;
    if (inflight != null) await inflight;
    _isLoaded = false;
    return detect(candidates);
  }

  /// Cheap synchronous lookup. Returns true when [executable] was
  /// found on PATH at the most-recent probe. Returns false when
  /// either the probe hasn't completed yet or the tool isn't
  /// installed — the UI distinguishes via [isLoading] / [isLoaded].
  bool has(String executable) => _installed.contains(executable);
}
