// Minimal pure-Dart stub of package:flutter/foundation.dart for the
// logos benchmark harness. Provides only the compile-time symbols the
// engine's buildFromStats import-closure (and the shared_preferences
// transitive dep it drags in) reference: annotations, ChangeNotifier,
// kDebugMode, and compute. None of these are exercised on the
// buildFromStats hot path — they exist so the program links under plain
// `dart` without dragging in dart:ui.
//
// NOT shipped. Does not alter engine behaviour.

import 'dart:async';

export 'dart:async';
export 'dart:typed_data';

// ---- diagnostic / annotation constants ---------------------------------
const bool kDebugMode = true;
const bool kReleaseMode = false;
const bool kProfileMode = false;
const bool kIsWeb = false;

// ---- meta-style annotations (no-op markers) ----------------------------
class _Annotation {
  const _Annotation();
}

const _Annotation immutable = _Annotation();
const _Annotation protected = _Annotation();
const _Annotation mustCallSuper = _Annotation();
const _Annotation visibleForTesting = _Annotation();
const _Annotation factory = _Annotation();
const _Annotation required = _Annotation();
const _Annotation nonVirtual = _Annotation();
const _Annotation experimental = _Annotation();
const _Annotation internal = _Annotation();

class Immutable {
  final String reason;
  const Immutable([this.reason = '']);
}

// ---- compute (off-isolate) ---------------------------------------------
// The real `compute` runs a callback on a background isolate. The engine
// build path never calls it; we provide a synchronous shim so any
// accidental reference still type-checks. If actually invoked it runs
// inline (correct result, no isolate).
Future<R> compute<M, R>(FutureOr<R> Function(M) callback, M message,
    {String? debugLabel}) async {
  return await callback(message);
}

// ---- Listenable / ChangeNotifier ---------------------------------------
typedef VoidCallback = void Function();

abstract class Listenable {
  const Listenable();
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
}

mixin class ChangeNotifier implements Listenable {
  final List<VoidCallback> _listeners = <VoidCallback>[];
  bool _disposed = false;

  bool get hasListeners => _listeners.isNotEmpty;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void notifyListeners() {
    for (final l in List<VoidCallback>.from(_listeners)) {
      l();
    }
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

class ValueNotifier<T> extends ChangeNotifier {
  T _value;
  ValueNotifier(this._value);
  T get value => _value;
  set value(T newValue) {
    if (_value == newValue) return;
    _value = newValue;
    notifyListeners();
  }
}

// ---- misc helpers occasionally referenced ------------------------------
double clampDouble(double x, double min, double max) =>
    x < min ? min : (x > max ? max : x);

void debugPrint(String? message, {int? wrapWidth}) {
  // intentionally swallowed in the harness
}
