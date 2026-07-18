// disposable_slot.dart — a field that holds at most ONE disposable value and
// frees whatever it held before.
//
// WHY THIS EXISTS. "Show the new one, then free the old one" is the shape of
// every on-screen resource handoff (a spool-backed document owns a temp dir
// and a file handle; a fresh one replaces it every load). Written by hand it
// is four lines that must be written in one exact order:
//
//     final prev = _active;      // capture BEFORE overwrite, or it's lost
//     _active = next;            // install first — the old one is still
//     prev?.dispose();           // on screen until this returns
//
// Get the order wrong and you either leak the previous handle forever or
// dispose the one you just installed. Skip the capture on ONE of several
// branches and you leak on exactly that path. Both mistakes are invisible in
// review and in tests — a leaked temp dir throws nothing.
//
// So the dance lives here once, tested (test/backend/disposable_slot_test.dart),
// and the call sites become `slot.install(next)` / `slot.clear()`. Installing
// the value already held is a no-op, not a self-dispose — that guard is the
// one a hand-written swap forgets.

/// Owns at most one [T]; [install] frees the value it replaces.
class DisposableSlot<T extends Object> {
  DisposableSlot(this._dispose);

  /// How to release a value. `(v) => v.dispose()` for most; async disposal
  /// is fired and not awaited — a slot swap happens mid-frame and must not
  /// block the handoff.
  final void Function(T value) _dispose;

  T? _value;

  /// The value currently held, if any.
  T? get value => _value;

  bool get isEmpty => _value == null;

  /// Install [next] (or nothing), releasing whatever was held.
  ///
  /// Installing the value already held does nothing: it is not a leak and
  /// must not be a disposal of the live value.
  void install(T? next) {
    final prev = _value;
    if (identical(prev, next)) return;
    _value = next;
    if (prev != null) _dispose(prev);
  }

  /// Release the held value, if any.
  void clear() => install(null);
}
