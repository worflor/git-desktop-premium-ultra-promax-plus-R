// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/undo_controller.dart';

void main() {
  group('UndoCoordinator ordering invariants', () {
    test('zero-window action flushes a pending action first, in order',
        () async {
      final coord = UndoCoordinator();
      final log = <String>[];

      // Arm a destructive action with a long window (never fires on its
      // own inside this test)...
      final first = coord.schedule<void>(
        kind: UndoActionKind.discard,
        label: 'discard',
        window: const Duration(minutes: 5),
        run: () async => log.add('discard'),
      );
      // schedule() arms after an internal await — yield so it lands.
      await Future<void>.delayed(Duration.zero);
      expect(coord.hasPending, isTrue);

      // ...then run a zero-window action. The pending discard must execute
      // FIRST — a zero window must never leapfrog an armed action and
      // leave it to fire later on its old timer.
      await coord.schedule<void>(
        kind: UndoActionKind.commit,
        label: 'commit',
        window: Duration.zero,
        run: () async => log.add('commit'),
      );
      await first;

      expect(log, ['discard', 'commit']);
      expect(coord.hasPending, isFalse);
      coord.dispose();
    });

    test('cancel completes the scheduled future with null and never runs',
        () async {
      final coord = UndoCoordinator();
      var ran = false;
      final result = coord.schedule<int>(
        kind: UndoActionKind.stashDrop,
        label: 'drop',
        window: const Duration(minutes: 5),
        run: () async {
          ran = true;
          return 1;
        },
      );
      // schedule() arms after an internal await — yield so it lands.
      await Future<void>.delayed(Duration.zero);
      coord.cancel();
      expect(await result, isNull);
      expect(ran, isFalse);
      expect(coord.hasPending, isFalse);
      coord.dispose();
    });

    test('scheduling replaces a settled notice; undoCompleted runs the undo',
        () async {
      final coord = UndoCoordinator();
      var undone = false;
      coord.announce(
        kind: UndoActionKind.commit,
        label: 'Committed x',
        undo: () async => undone = true,
      );
      expect(coord.hasCompleted, isTrue);
      expect(coord.completed!.canUndo, isTrue);
      expect(coord.completed!.isError, isFalse);

      await coord.undoCompleted();
      expect(undone, isTrue);
      expect(coord.hasCompleted, isFalse);

      // Error notices render as failures and carry no undo.
      coord.announce(
        kind: UndoActionKind.commit,
        label: 'Undo failed',
        isError: true,
      );
      expect(coord.completed!.isError, isTrue);
      expect(coord.completed!.canUndo, isFalse);

      // A new pending action clears the notice — you moved on.
      await coord.schedule<void>(
        kind: UndoActionKind.other,
        label: 'next',
        window: Duration.zero,
        run: () async {},
      );
      expect(coord.hasCompleted, isFalse);
      coord.dispose();
    });
  });
}
