import 'dart:async';

import 'package:flutter/foundation.dart';

/// Classifies pending actions so the UI can pick an appropriate icon
/// and so a future "which actions to delay" settings panel has a
/// stable key to toggle against. Coordinator itself does not branch
/// on kind — it's metadata for consumers.
enum UndoActionKind {
  commit,
  commitAndPush,
  discard,
  branchDelete,
  tagDelete,
  stashDrop,
  revert,
  other,
}

/// A single in-flight pending action managed by [UndoCoordinator].
///
/// The coordinator exposes this as a read-only view so the pill can
/// render the label + countdown without touching internal plumbing.
class PendingUndoAction {
  final UndoActionKind kind;
  final String label;
  final Duration window;
  final DateTime firesAt;
  final Future<void> Function() _onFire;
  final VoidCallback _onCancel;

  PendingUndoAction._({
    required this.kind,
    required this.label,
    required this.window,
    required this.firesAt,
    required Future<void> Function() onFire,
    required VoidCallback onCancel,
  })  : _onFire = onFire,
        _onCancel = onCancel;
}

/// Global "safety-window" coordinator.
///
/// Every destructive action that wants an undo pill calls [schedule]
/// with a window duration. The action doesn't run until the timer
/// expires — if the user cancels in the meantime, nothing happens.
/// Passing [Duration.zero] as the window bypasses the delay and
/// executes immediately, so a single codepath serves both "undo on"
/// and "undo off" configurations.
///
/// Invariant: **one pending action at a time.** Scheduling a new
/// action while one is pending *flushes* the prior action (runs it
/// immediately) before arming the new one. This matches the
/// "you moved on to the next thing" mental model — the prior action
/// is assumed settled by the time you reach for the next.
///
/// [schedule] returns `Future<T?>` — the action's return value on
/// completion, or `null` if the user cancelled.
class UndoCoordinator extends ChangeNotifier {
  PendingUndoAction? _pending;
  Timer? _timer;

  /// The currently-pending action, or null if none.
  PendingUndoAction? get pending => _pending;
  bool get hasPending => _pending != null;

  /// Milliseconds remaining until the pending action fires. 0 if no
  /// action is pending. Used by the pill to render the countdown.
  int get remainingMs {
    final p = _pending;
    if (p == null) return 0;
    final diff = p.firesAt.difference(DateTime.now()).inMilliseconds;
    return diff < 0 ? 0 : diff;
  }

  /// Schedule [run] to execute after [window]. Returns the action's
  /// result on completion, or `null` if the user cancelled.
  ///
  /// When [window] is [Duration.zero], [run] executes immediately in
  /// the same call — no pill, no delay, same result type. Callers
  /// that read the undo-window preference as zero get their
  /// "undo disabled" semantics for free.
  Future<T?> schedule<T>({
    required UndoActionKind kind,
    required String label,
    required Future<T> Function() run,
    required Duration window,
  }) async {
    if (window <= Duration.zero) {
      return await run();
    }
    // Flush any prior pending action to maintain the one-at-a-time
    // invariant. Awaiting here lets the prior action's result settle
    // before the new one starts waiting — critical for e.g. "discard
    // file, then commit" where the commit's view of the tree must
    // reflect the discard having completed.
    await flushNow();

    final completer = Completer<T?>();
    final action = PendingUndoAction._(
      kind: kind,
      label: label,
      window: window,
      firesAt: DateTime.now().add(window),
      onFire: () async {
        try {
          final result = await run();
          if (!completer.isCompleted) completer.complete(result);
        } catch (e, s) {
          if (!completer.isCompleted) completer.completeError(e, s);
        }
      },
      onCancel: () {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    _pending = action;
    _timer = Timer(window, () {
      unawaited(flushNow());
    });
    notifyListeners();
    return completer.future;
  }

  /// Run the currently-pending action immediately and clear the pill.
  /// Safe to call when nothing is pending (no-op). Callers may await
  /// to know when the underlying work completes.
  Future<void> flushNow() async {
    final p = _pending;
    if (p == null) return;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    notifyListeners();
    await p._onFire();
  }

  /// Cancel the pending action without running it. The scheduled
  /// Future completes with `null`. No-op when nothing is pending.
  void cancel() {
    final p = _pending;
    if (p == null) return;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    p._onCancel();
    notifyListeners();
  }

  @override
  void dispose() {
    // Best-effort flush on teardown — if the app is shutting down
    // while an action is pending, fire-and-forget it. Dart keeps the
    // isolate alive until pending futures settle, so short-running
    // git ops generally complete before the process exits.
    final p = _pending;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    if (p != null) {
      unawaited(p._onFire());
    }
    super.dispose();
  }
}
