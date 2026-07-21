// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter/foundation.dart';

/// Settings-side scaffold for the alpha-math integration: an AlphaFold-for-math
/// engine that will eventually tie in as a live, repo-wide algebra validation
/// engine.
///
/// The engine itself doesn't exist yet, so this holds only the configurable
/// path and reports *not available* — the settings row stays an honest "coming
/// soon" tease rather than faking liveness. The shape deliberately mirrors
/// [WickState]'s path/detect/available surface so promotion to a live
/// integration is a small flip: implement [detect] against a real probe
/// (a future `backend/alpha_math.dart`), then layer in per-repo validation.
class AlphaMathState extends ChangeNotifier {
  bool _available = false;
  bool _detected = false;
  String _customPath = '';

  /// True only once a real engine probe confirms the configured binary works.
  /// Always false today — the engine is still being built.
  bool get available => _detected && _available;
  bool get detected => _detected;
  String get customPath => _customPath;

  void setCustomPath(String path) {
    if (path == _customPath) return;
    _customPath = path;
    _detected = false;
    _available = false;
    notifyListeners();
    detect();
  }

  /// Resolve whether the configured engine is usable.
  ///
  /// Placeholder until the engine ships: marks the probe as run and reports
  /// unavailable regardless of the configured path. When alpha-math is real,
  /// this is where the binary/version check goes (set `_available` from it).
  Future<void> detect() async {
    _available = false;
    _detected = true;
    notifyListeners();
  }
}
