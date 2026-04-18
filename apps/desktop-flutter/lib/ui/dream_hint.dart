import 'dart:async';

import 'package:flutter/foundation.dart';

/// Reactive controller for a "dream-sourced" placeholder or prefill.
///
/// Abstracts the wiring that lets any text field display a hint
/// computed from external state (logos mind, AI, git history, …)
/// with debouncing, signature-based short-circuiting, in-flight
/// supersede, and null-safe fallback.
///
/// Not tied to commit messages — reusable for branch name prefill,
/// placeholder text in arbitrary forms, rename suggestions, anywhere
/// a field benefits from an engine-generated suggestion that should
/// fall back quietly when the engine hasn't settled.
///
/// The type parameter [T] lets a single controller carry whatever
/// payload the consumer needs — a plain `String` for simple hints,
/// a record like `({String? phrase, LogosFieldCharacter? character})`
/// for the commit composer, a custom class for richer surfaces.
/// The controller only cares about when to (re)compute; the compute
/// itself decides what to produce.
///
/// Typical use from a State's build(), after deciding what inputs
/// feed into the compute:
///
/// ```dart
/// final sig = '$repoPath|$includedHash|$engineReady';
/// _hintCtrl.schedule(sig, () => dreamFromDiff(...));
/// // render:
/// hintText: _hintCtrl.value ?? 'commit message...',
/// ```
class DreamHintController<T extends Object> extends ChangeNotifier {
  DreamHintController({
    this.debounce = const Duration(milliseconds: 320),
  });

  /// How long to wait after the last [schedule] call with a new
  /// signature before running the compute. Debouncing collapses
  /// rapid signature changes (selection flurries, save bursts) into
  /// a single compute.
  final Duration debounce;

  T? _value;
  /// Current value, or null if no compute has resolved yet or the
  /// last compute returned null.
  T? get value => _value;

  bool _thinking = false;
  /// True while a scheduled compute is either debounce-pending or
  /// in-flight. UI can bind a subtle opacity/pulse to this so the
  /// user sees the engine is working rather than a silent gap.
  /// Transitions notify listeners.
  bool get thinking => _thinking;

  Timer? _debounceTimer;
  String _lastSignature = '';
  int _requestId = 0;
  bool _disposed = false;

  /// Schedule a compute for the given [signature]. When the
  /// signature matches the last one committed, this is a no-op — so
  /// calling every build is cheap. When it differs, cancels any
  /// pending compute, waits [debounce], then runs [compute]. The
  /// result becomes the new [value] and listeners are notified iff
  /// it changed.
  ///
  /// [compute] is a fresh closure each call, so it can close over
  /// whatever state the caller needs (engine refs, diff text, etc.).
  /// Exceptions inside [compute] are swallowed — [value] stays at
  /// its previous state.
  void schedule(String signature, Future<T?> Function() compute) {
    if (_disposed) return;
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    _debounceTimer?.cancel();
    final reqId = ++_requestId;
    // Enter thinking state the moment a new compute is scheduled —
    // covers both the debounce wait and the compute itself. UI can
    // bind a pulse/fade to this signal.
    if (!_thinking) {
      _thinking = true;
      notifyListeners();
    }
    _debounceTimer = Timer(debounce, () async {
      if (_disposed || reqId != _requestId) return;
      try {
        final result = await compute();
        if (_disposed || reqId != _requestId) return;
        final valueChanged = _value != result;
        if (valueChanged) _value = result;
        if (_thinking) _thinking = false;
        if (valueChanged || !_thinking) notifyListeners();
      } catch (_) {
        if (_disposed || reqId != _requestId) return;
        if (_thinking) {
          _thinking = false;
          notifyListeners();
        }
      }
    });
  }

  /// Force the next [schedule] call to run even if its signature
  /// matches the last committed one. Use when an external source
  /// of truth that the signature doesn't capture has moved — e.g.,
  /// the user emptied a text field and you want the hint
  /// re-published on the next build.
  void invalidate() {
    _lastSignature = '';
  }

  /// Drop the current value and cancel any pending compute. Does
  /// not reset the signature, so a subsequent [schedule] call with
  /// the same signature will still short-circuit. Pair with
  /// [invalidate] for a clean slate.
  void clear() {
    _debounceTimer?.cancel();
    _requestId++;
    final changed = _value != null || _thinking;
    _value = null;
    _thinking = false;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}
