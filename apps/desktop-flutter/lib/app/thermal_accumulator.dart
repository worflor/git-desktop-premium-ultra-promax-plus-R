import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Thermal presence accumulator. Warms on spectral flux (entropy change),
/// cools passively with wall-clock time. Half-life ~5 min (lambda = ln2/300).
///
/// Owns its own cooling timer — dispose() stops it. Provided per-repo in
/// the widget tree so each repo gets its own thermal state and tests get
/// fresh instances.
class ThermalAccumulator extends ChangeNotifier {
  double? _lastEntropy;
  double _temperature = 0.0;
  DateTime _lastUpdate = DateTime.now();
  String? _repoPath;
  Timer? _coolingTimer;
  bool _disposed = false;

  ThermalAccumulator() {
    _coolingTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => cool(),
    );
  }

  double get temperature => _temperature;

  void update(double currentEntropy, String? repoPath) {
    if (_disposed) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdate).inMilliseconds / 1000.0;
    _lastUpdate = now;
    final prevTemp = _temperature;
    _temperature *= math.exp(-0.00231 * elapsed);
    if (repoPath != _repoPath) {
      _repoPath = repoPath;
      _lastEntropy = currentEntropy;
      _temperature = 0.0;
      if (prevTemp > 0.001) notifyListeners();
      return;
    }
    final prev = _lastEntropy;
    _lastEntropy = currentEntropy;
    if (prev == null) return;
    final flux = (currentEntropy - prev).abs();
    _temperature = (_temperature + flux * 0.4).clamp(0.0, 1.0);
    if ((_temperature - prevTemp).abs() > 0.001) notifyListeners();
  }

  void cool() {
    if (_disposed || _temperature < 0.001) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdate).inMilliseconds / 1000.0;
    if (elapsed < 1.0) return;
    _lastUpdate = now;
    final cooled = _temperature * math.exp(-0.00231 * elapsed);
    if (_temperature - cooled < 0.001) return;
    _temperature = cooled;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _coolingTimer?.cancel();
    _coolingTimer = null;
    super.dispose();
  }
}
