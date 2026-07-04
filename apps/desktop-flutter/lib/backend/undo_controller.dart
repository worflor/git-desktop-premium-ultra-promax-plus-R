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

/// A completed action the user can still take back: the pill shows
/// [label] with an Undo affordance until [expiresAt]. Complements the
/// pre-execution safety window — cancel-before for destructive ops,
/// undo-after for ops whose inverse is cheap and safe (soft-reset of
/// an unpushed commit). A null [undo] renders as a plain confirmation
/// notice, which doubles as the app's success feedback surface.
class CompletedUndoAction {
  final UndoActionKind kind;
  final String label;
  final DateTime expiresAt;
  final Future<void> Function()? undo;

  /// True when this notice reports a FAILURE (an undo that couldn't run,
  /// a post-action error). The pill renders it in the destructive tier so
  /// it can't be mistaken for the green success notice.
  final bool isError;

  CompletedUndoAction._({
    required this.kind,
    required this.label,
    required this.expiresAt,
    required this.undo,
    required this.isError,
  });

  bool get canUndo => undo != null;
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
  CompletedUndoAction? _completed;
  Timer? _completedTimer;

  /// The currently-pending action, or null if none.
  PendingUndoAction? get pending => _pending;
  bool get hasPending => _pending != null;

  /// The most recent completed-but-undoable action (or plain success
  /// notice), or null. Cleared on expiry, on undo, and whenever a new
  /// pending action arms — you moved on.
  CompletedUndoAction? get completed => _completed;
  bool get hasCompleted => _completed != null;

  /// Announce a completed action. Shows the pill in its settled state:
  /// [label] plus an Undo affordance when [undo] is provided. Replaces
  /// any prior notice — one at a time, same as pending actions.
  void announce({
    required UndoActionKind kind,
    required String label,
    Duration window = const Duration(seconds: 10),
    Future<void> Function()? undo,
    bool isError = false,
  }) {
    _completedTimer?.cancel();
    _completed = CompletedUndoAction._(
      kind: kind,
      label: label,
      expiresAt: DateTime.now().add(window),
      undo: undo,
      isError: isError,
    );
    _completedTimer = Timer(window, () {
      _completed = null;
      _completedTimer = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Run the completed action's undo and clear the notice. No-op when
  /// nothing undoable is showing. The pill clears immediately; the
  /// undo work itself is awaited by the caller if it cares.
  Future<void> undoCompleted() async {
    final c = _completed;
    if (c == null || c.undo == null) return;
    _completedTimer?.cancel();
    _completedTimer = null;
    _completed = null;
    notifyListeners();
    await c.undo!();
  }

  void _clearCompleted() {
    if (_completed == null) return;
    _completedTimer?.cancel();
    _completedTimer = null;
    _completed = null;
    notifyListeners();
  }

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
    _clearCompleted();
    // Flush any prior pending action FIRST — before the zero-window fast
    // path, not after it. The one-at-a-time invariant is really an
    // ORDERING invariant: "discard file, then commit" requires the commit's
    // view of the tree to reflect the discard having completed. A caller
    // whose window is configured to zero must not leapfrog a still-armed
    // destructive action and leave it to fire afterward on its old timer.
    // No-op when nothing is pending, so the fast path stays fast.
    await flushNow();
    if (window <= Duration.zero) {
      return await run();
    }

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
    _completedTimer?.cancel();
    _completedTimer = null;
    _completed = null;
    if (p != null) {
      unawaited(p._onFire());
    }
    super.dispose();
  }
}
