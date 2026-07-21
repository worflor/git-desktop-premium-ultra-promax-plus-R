// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Behavior coverage for the history-surgery wizard's SAFETY-CRITICAL logic:
// the typed-literal confirmation gate that is the sole barrier before an
// irreversible history rewrite + force-push, the phase machine that must never
// let a caller skip that gate, and the per-branch force-push loop that must
// surface every partial failure truthfully rather than silently swallowing it.
//
// SurgeryState is a headless ChangeNotifier — every test here drives it
// directly. The gate/phase logic is exercised PURELY (no git subprocess at
// all: `dryRun: true` routes execute/verify through the in-memory simulator,
// and `selectedPaths`/`impact` are set on the object instead of going through
// `addPath`, which would shell out to git). The force-push loop is exercised
// through the [SurgeryState.forcePushOverride] test seam — the one @visible-
// ForTesting injection this file needs — which mirrors `git.pushRemote`'s
// (ok, error) surface without a live remote.
//
// NOTE ON A ROOT-FIXED BUG: `confirmationComplete` used to compare
// `typedConfirmation.trim().toUpperCase() == 'PURGE'`, which silently accepted
// "purge", "Purge", " PURGE ", "PURGE " — every near-miss a nervous user might
// type at a destructive prompt. It now requires the exact, case-sensitive,
// whitespace-free literal `'PURGE'`. The truth-table group below is the
// regression guard.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/history_surgery.dart';
import 'package:git_desktop/features/history_surgery/surgery_state.dart';

/// A SurgeryState wired for pure (git-free) testing.
SurgeryState _state() =>
    SurgeryState(repoPath: '/nonexistent/repo', dryRun: true);

/// Force the checkbox list to exactly [vals] via the public toggle API.
void _setCheckboxes(SurgeryState s, List<bool> vals) {
  expect(s.checkboxes.length, vals.length,
      reason: 'test set the wrong number of checkbox values');
  for (var i = 0; i < vals.length; i++) {
    if (s.checkboxes[i] != vals[i]) s.toggleCheckbox(i);
  }
}

SurgeryImpact _impact({
  int affectedCommits = 2,
  List<String> worktrees = const [],
  List<String> stashes = const [],
  List<String> branches = const [],
}) =>
    SurgeryImpact(
      allPaths: {'lib/secret.dart'},
      affectedCommits: affectedCommits,
      totalCommits: 10,
      affectedWorktrees: worktrees,
      affectedStashIndices: stashes,
      affectedBranches: branches,
    );

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // PART A.1 — the confirmation gate truth table
  // ─────────────────────────────────────────────────────────────────────────
  group('confirmationComplete — the irreversible-rewrite gate', () {
    // The exact literal the user is asked to type ("type PURGE"). Anything
    // else — wrong case, surrounding whitespace, a substring, a superstring —
    // must leave the gate CLOSED.
    const rejectedTexts = <String>[
      '', // nothing typed
      'purge', // all lowercase
      'Purge', // title case
      'pUrGe', // mixed case
      'PURGE ', // trailing space
      ' PURGE', // leading space
      ' PURGE ', // surrounded by spaces
      'PURGE\n', // trailing newline
      'PURG', // too short
      'PURGES', // too long
      'PURGE PURGE', // repeated
      'DELETE', // a plausible wrong word
    ];

    test('exact literal "PURGE" + all checkboxes checked → gate OPEN', () {
      final s = _state();
      s.initCheckboxes(); // impact null → 2 mandatory checkboxes
      _setCheckboxes(s, [true, true]);
      s.setConfirmationText('PURGE');
      expect(s.confirmationComplete, isTrue,
          reason: 'the one valid combination must open the gate');
    });

    test('every non-exact confirmation string is REJECTED even with all '
        'boxes checked (case-sensitive, whitespace-exact)', () {
      for (final text in rejectedTexts) {
        final s = _state();
        s.initCheckboxes();
        _setCheckboxes(s, [true, true]);
        s.setConfirmationText(text);
        expect(s.confirmationComplete, isFalse,
            reason: 'gate must stay CLOSED for confirmation text '
                '${_show(text)} — only the exact literal "PURGE" counts');
      }
    });

    test('correct literal but not every checkbox checked → gate CLOSED', () {
      // With 2 mandatory boxes: [F,F], [T,F], [F,T] must all keep it closed.
      for (final combo in <List<bool>>[
        [false, false],
        [true, false],
        [false, true],
      ]) {
        final s = _state();
        s.initCheckboxes();
        _setCheckboxes(s, combo);
        s.setConfirmationText('PURGE');
        expect(s.confirmationComplete, isFalse,
            reason: 'gate must stay CLOSED while any checkbox is unchecked '
                '(combo $combo)');
      }
    });

    test('no checkboxes at all → gate CLOSED regardless of text', () {
      final s = _state();
      // Never call initCheckboxes: checkboxes stays empty.
      expect(s.checkboxes, isEmpty);
      s.setConfirmationText('PURGE');
      expect(s.confirmationComplete, isFalse,
          reason: 'an empty checkbox list must never satisfy the gate '
              '(checkboxes.isNotEmpty guard)');
    });

    test('full truth table over (text × checkbox combos) with 2 boxes', () {
      const texts = ['PURGE', 'purge', 'PURGE ', '', 'DELETE'];
      const combos = <List<bool>>[
        [false, false],
        [true, false],
        [false, true],
        [true, true],
      ];
      for (final text in texts) {
        for (final combo in combos) {
          final s = _state();
          s.initCheckboxes();
          _setCheckboxes(s, combo);
          s.setConfirmationText(text);
          final expected = text == 'PURGE' && combo.every((c) => c);
          expect(s.confirmationComplete, expected,
              reason: 'text=${_show(text)} combo=$combo should give '
                  '$expected');
        }
      }
    });

    test('conditional checkboxes (worktrees/stashes) all count toward the '
        'gate', () {
      final s = _state();
      // worktrees present AND stashes present → 2 mandatory + 2 conditional.
      s.impact = _impact(worktrees: ['wt-1'], stashes: ['0']);
      s.initCheckboxes();
      expect(s.checkboxes.length, 4,
          reason: 'two mandatory + two conditional acknowledgements');

      s.setConfirmationText('PURGE');
      // All but the last checked → still closed.
      _setCheckboxes(s, [true, true, true, false]);
      expect(s.confirmationComplete, isFalse,
          reason: 'the stash-acknowledgement checkbox is still required');
      // All four checked → open.
      _setCheckboxes(s, [true, true, true, true]);
      expect(s.confirmationComplete, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PART A.2 — phase machine cannot skip the gate
  // ─────────────────────────────────────────────────────────────────────────
  group('phase transitions — the gate cannot be skipped', () {
    test('fresh state starts at select and cannot advance with no selection',
        () {
      final s = _state();
      expect(s.phase, SurgeryPhase.select);
      expect(s.canAdvance(), isFalse,
          reason: 'no paths selected, no impact analyzed');
    });

    test('select → understand → confirm walks forward once prerequisites '
        'are met', () {
      final s = _state();
      s.selectedPaths.add('lib/secret.dart');
      s.impact = _impact();
      expect(s.canAdvance(), isTrue);

      s.advance();
      expect(s.phase, SurgeryPhase.understand);

      s.advance(); // understand always advances
      expect(s.phase, SurgeryPhase.confirm);
      expect(s.checkboxes, isNotEmpty,
          reason: 'entering confirm must initialise the acknowledgements');
    });

    test('advance() from confirm with the gate CLOSED does nothing — execute '
        'is unreachable while unconfirmed', () {
      final s = _state();
      s.impact = _impact();
      s.goToPhase(SurgeryPhase.confirm);
      // Gate is closed (no text, unchecked boxes).
      expect(s.confirmationComplete, isFalse);
      expect(s.canAdvance(), isFalse);

      s.advance();
      expect(s.phase, SurgeryPhase.confirm,
          reason: 'a closed gate must trap the wizard on the confirm phase');

      // Half-satisfy the gate — still trapped.
      s.setConfirmationText('PURGE');
      expect(s.canAdvance(), isFalse);
      s.advance();
      expect(s.phase, SurgeryPhase.confirm);
    });

    test('advance() from confirm only proceeds once the gate is fully OPEN',
        () {
      final s = _state();
      s.impact = _impact();
      s.goToPhase(SurgeryPhase.confirm);
      _setCheckboxes(s, [true, true]);
      s.setConfirmationText('PURGE');
      expect(s.canAdvance(), isTrue);

      s.advance(); // fires execute(); phase flips to execute synchronously
      expect(s.phase, SurgeryPhase.execute);
    });

    test('goBack walks confirm → understand → select and stops at select', () {
      final s = _state();
      s.impact = _impact();
      s.goToPhase(SurgeryPhase.confirm);

      s.goBack();
      expect(s.phase, SurgeryPhase.understand);
      s.goBack();
      expect(s.phase, SurgeryPhase.select);
      s.goBack();
      expect(s.phase, SurgeryPhase.select,
          reason: 'select is the first phase — goBack is a no-op there');
    });

    test('execute (dryRun) runs to verify with a truthful success result',
        () async {
      final s = _state();
      s.impact = _impact(affectedCommits: 2, branches: ['main']);
      s.goToPhase(SurgeryPhase.confirm);
      _setCheckboxes(s, [true, true]);
      s.setConfirmationText('PURGE');

      await s.execute();
      expect(s.phase, SurgeryPhase.verify);
      expect(s.executing, isFalse);
      expect(s.result, isNotNull);
      expect(s.result!.success, isTrue);
      expect(s.executeError, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PART A.3 — per-branch force-push loop surfaces partial failure truthfully
  // ─────────────────────────────────────────────────────────────────────────
  group('force-push loop — partial failures are all attempted and surfaced',
      () {
    // Real-git state (dryRun: false) so forcePush takes the override path.
    SurgeryState pushState() =>
        SurgeryState(repoPath: '/nonexistent/repo', dryRun: false);

    test('one branch failing does NOT swallow the others — every branch is '
        'attempted, and both the successes and the failure are recorded',
        () async {
      final s = pushState();
      final attempted = <String>[];
      s.forcePushOverride = (branch) async {
        attempted.add(branch);
        if (branch == 'feature-b') {
          return (ok: false, error: 'stale info: remote moved');
        }
        return (ok: true, error: null);
      };

      // The UI drives one forcePush per affected branch.
      for (final b in ['main', 'feature-b', 'feature-c']) {
        await s.forcePush(b);
      }

      expect(attempted, ['main', 'feature-b', 'feature-c'],
          reason: 'the failure of feature-b must not abort the loop — '
              'feature-c must still be attempted afterwards');
      expect(s.pushedBranches, {'main', 'feature-c'},
          reason: 'only the branches that actually pushed are recorded as '
              'pushed');
      expect(s.pushErrors.length, 1,
          reason: 'exactly the one real failure is accumulated');
      expect(s.pushError, isNotNull,
          reason: 'a partial failure must surface to the user, not vanish');
      expect(s.pushError, contains('feature-b'));
      expect(s.pushError, contains('stale info: remote moved'));
    });

    test('a failing branch is NOT reported as pushed — no false success', () {
      final s = pushState();
      s.forcePushOverride =
          (branch) async => (ok: false, error: 'permission denied');
      return s.forcePush('protected').then((_) {
        expect(s.pushedBranches, isEmpty,
            reason: 'a branch whose push failed must never appear in '
                'pushedBranches');
        expect(s.pushError, contains('protected'));
      });
    });

    test('all branches succeeding leaves a clean, error-free state', () async {
      final s = pushState();
      s.forcePushOverride = (branch) async => (ok: true, error: null);
      for (final b in ['main', 'dev', 'release']) {
        await s.forcePush(b);
      }
      expect(s.pushedBranches, {'main', 'dev', 'release'});
      expect(s.pushErrors, isEmpty);
      expect(s.pushError, isNull,
          reason: 'no failures → nothing to surface');
    });

    test('a missing error message degrades to "unknown error", never a '
        'silent success', () async {
      final s = pushState();
      s.forcePushOverride = (branch) async => (ok: false, error: null);
      await s.forcePush('main');
      expect(s.pushedBranches, isEmpty);
      expect(s.pushError, contains('unknown error'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PART A.4 — rollback reachability and its guards
  // ─────────────────────────────────────────────────────────────────────────
  group('rollback', () {
    test('rollback (dryRun) is reachable after a partial-push execute and '
        'blocks further pushes', () async {
      final s = _state(); // dryRun
      s.impact = _impact(branches: ['main']);
      s.goToPhase(SurgeryPhase.confirm);
      _setCheckboxes(s, [true, true]);
      s.setConfirmationText('PURGE');
      await s.execute();
      expect(s.phase, SurgeryPhase.verify);

      // A push "fails" in the user's session, they choose to roll back.
      await s.rollback();
      expect(s.rolledBack, isTrue,
          reason: 'rollback must be reachable from the verify phase');

      // After rollback, force-pushing is a guarded no-op — you cannot push a
      // history you have just abandoned.
      await s.forcePush('main');
      expect(s.pushedBranches, isEmpty,
          reason: 'forcePush must short-circuit once rolledBack is set');
    });

    test('non-dryRun rollback with no backup prefix is a safe no-op (never '
        'touches git, never claims a rollback happened)', () async {
      final s = SurgeryState(repoPath: '/nonexistent/repo', dryRun: false);
      // result is null → backupPrefix guard returns early before any git call.
      expect(s.result, isNull);
      await s.rollback();
      expect(s.rolledBack, isFalse,
          reason: 'with nothing to roll back the flag must stay false — a '
              'truthful state, and no subprocess is spawned');
    });
  });
}

/// Render a string with its whitespace/control chars visible in failure
/// messages so " PURGE " and "PURGE\n" are distinguishable from "PURGE".
String _show(String s) => '"${s.replaceAll('\n', r'\n')}"';
