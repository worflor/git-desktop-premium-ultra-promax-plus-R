// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// jank_budget_test.dart — wall-clock jank gates.
//
// The load-bearing idea: a synchronous compute inside a tap handler lands
// inside `pump()`. `WidgetTester.pump()` drives a frame on the SAME
// isolate the test runs on, so if a tap handler does blocking work instead
// of scheduling it (an Isolate, a microtask that yields, a Future that
// actually awaits I/O), that work happens synchronously between "tap" and
// "frame drawn" — exactly like it would on the real UI isolate. A stopwatch
// around `tap` + `pump` therefore catches "this handler blocks the main
// isolate": the documented filament-panel freeze was a full YAA*+dream
// search over the whole co-change graph running synchronously on
// `didChangeDependencies` when the panel opened (see
// lib/features/filament/filament_findings_panel.dart's `_scan` — now
// isolate-dispatched).
//
// Bound is wall-clock, deliberately, and generous. The failure mode this
// catches is three orders of magnitude wide (a blocking engine call is
// ~2000ms against a ~5ms healthy frame), so a 300ms bound remains far below
// the regression while tolerating a scheduler slice stolen by a concurrent
// real-Git property worker. Gate on order-of-magnitude wall clock here;
// gate on exact counters in rebuild_budget_test.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:provider/provider.dart';

import 'package:git_desktop/app/app_identity.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/app/desk_pr_state.dart';
import 'package:git_desktop/app/worktree_state.dart';
import 'package:git_desktop/features/filament/filament_findings_panel.dart';
import 'package:git_desktop/features/palette/command_palette.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../support/widget_harness.dart';

/// Wall-clock, deliberately. The failure this catches is three orders of
/// magnitude wide (a blocking engine call is ~2000ms against ~5ms), so a
/// 300ms is still a coarse sentinel, not a p95 SLA. Gate on order-of-magnitude
/// wall clock; gate on exact counters everywhere else.
Future<Duration> timePump(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  final stopwatch = Stopwatch()..start();
  await action();
  stopwatch.stop();
  return stopwatch.elapsed;
}

/// Every wall-clock bound below is passed through here so a loaded runner (a
/// busy CI box, a mid-test AV scan) can widen ALL of them in one place with
/// `MANIFOLD_TIMING_SCALE=3 flutter test …`. These gates are order-of-magnitude
/// guards, not p95 SLAs, so a global multiplier is the right escape hatch —
/// same spirit as `MANIFOLD_FUZZ`. Parsed leniently: missing/garbage/≤0 → 1×.
int budgetMs(int baseMs) {
  final scale = double.tryParse(
    Platform.environment['MANIFOLD_TIMING_SCALE'] ?? '',
  );
  return (baseMs * (scale != null && scale > 0 ? scale : 1.0)).round();
}

void main() {
  // Measurement purity: this file gates WALL-CLOCK pump times, and
  // leak_tracker's per-object bookkeeping (enabled globally in
  // flutter_test_config.dart) inflates exactly what is being measured —
  // its overhead blew the 250ms budgets when tracking first landed.
  // Timing gates exclude instrumentation; every functional suite keeps it.
  LeakTesting.settings = LeakTesting.settings.withIgnoredAll();
  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });

  // Un-timed: pays the one-time JIT/isolate warm-up cost (first-ever
  // MultiProvider mount with 21 providers, first font/shader lookups) so it
  // doesn't land inside the FIRST timed test below and produce a false
  // "jank" reading. Verified empirically: without this, the very first
  // themed-scaffold test in the file measured 372-628ms (cold-start noise),
  // while every subsequent theme measured well under 100ms in the same run
  // — a real one-time cost, not steady-state jank.
  testWidgets('warm-up: exercise the harness once before timing anything', (
    tester,
  ) async {
    await pumpHarness(tester, const Scaffold(body: SizedBox.shrink()));
  });

  group('app shell / themed scaffold', () {
    for (final theme in AppThemeId.values) {
      testWidgets('pumps under 300ms — ${theme.name}', (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final elapsed = await timePump(tester, () async {
          await tester.pumpWidget(
            harnessApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Manifold'),
                      ElevatedButton(
                        onPressed: () {},
                        child: const Text('action'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        });

        expect(
          elapsed.inMilliseconds,
          lessThan(budgetMs(300)),
          reason:
              'themed shell (${theme.name}) took '
              '${elapsed.inMilliseconds}ms to pump — order-of-magnitude '
              'jank on a first paint means something synchronous and '
              'heavy is running on the UI isolate',
        );
      });
    }
  });

  group('filament findings panel', () {
    testWidgets(
      'with a NULL activePath, pumps under 100ms and schedules no work',
      (tester) async {
        // Real-repo path is deliberately not covered here.
        // TODO: driving FilamentFindingsPanel with a real repo path (to
        // exercise the actual Scale-1/Scale-2 scan and its Isolate.run
        // dispatch) requires a ScratchRepo (test/support/scratch_repo.dart)
        // PLUS a built LogosGit engine wired through LogosGitState — that's
        // an integration-level fixture, not something a pure widget test
        // should stand up. Belongs in a future
        // test/integration/filament_scan_test.dart.
        await pumpHarness(
          tester,
          const Scaffold(body: FilamentFindingsPanel()),
        );

        final elapsed = await timePump(tester, () async {
          await tester.pump();
        });

        expect(
          elapsed.inMilliseconds,
          lessThan(budgetMs(100)),
          reason:
              'a null-activePath mount should be a cheap "no repo '
              'open" render, not a scan',
        );
        // didChangeDependencies bails out before calling _scan() when
        // activePath is null, so no git subprocess, no Isolate.run, and no
        // animation ticker should be pending after the first frame settles.
        expect(
          SchedulerBinding.instance.transientCallbackCount,
          0,
          reason: 'no work should be scheduled for a null-repo mount',
        );
        expect(find.text('No repository open.'), findsOneWidget);
      },
    );
  });

  group('command palette', () {
    testWidgets('opens, types a query, updates results within budget', (
      tester,
    ) async {
      // CommandPalette's static-entry registry (palette_registry.dart's
      // buildStaticEntries) reads WorktreeState and DeskPrState directly —
      // both excluded from harnessApp's base providers because their
      // constructors require a RepositoryState/AppIdentityState argument
      // (see widget_harness.dart's file-level doc comment). Supply them via
      // `wrapAboveNavigator`, which is spliced in above `MaterialApp`'s
      // Navigator — required because CommandPalette reads via
      // `Navigator.of(context, rootNavigator: true).context`, which cannot
      // see a provider wrapping `home` itself (confirmed empirically: that
      // placement throws ProviderNotFoundException).
      Widget wrapPalette(BuildContext context, Widget app) => MultiProvider(
        providers: [
          ChangeNotifierProvider<WorktreeState>(
            create: (_) => WorktreeState(context.read<RepositoryState>()),
          ),
          ChangeNotifierProvider<DeskPrState>(
            create: (_) => DeskPrState(
              context.read<RepositoryState>(),
              context.read<AppIdentityState>(),
            ),
          ),
        ],
        child: app,
      );

      // ARMED REGRESSION GUARD (was: a finding left failing on purpose).
      // Mounting CommandPalette used to throw
      //   "setState() or markNeedsBuild() called during build"
      // every time, regardless of mounting strategy. `PaletteState.open()`
      // — called synchronously from `CommandPalette.initState()` — calls
      // `notifyListeners()`, which marks the `PaletteState` provider (an
      // ancestor of CommandPalette, way up in main.dart's root
      // MultiProvider) dirty. `initState()` always runs inside
      // `Element.mount()`, which always runs inside an active
      // `BuildOwner.buildScope()` — so that notify was ALWAYS raised
      // "during build," by construction, no matter which frame/setState
      // triggered the mount (a second top-level `pumpWidget()` and a
      // subtree-only `ValueListenableBuilder` swap both reproduced it — the
      // latter, matching how `workspace_shell.dart`'s `AnimatedSwitcher`
      // mounts the palette in production, is the faithful reproduction kept
      // below). It was a real Flutter build-phase-safety violation, `assert()`
      // -gated (silent in release, fatal in any debug build including
      // `flutter_test`), NOT a harness artifact.
      //
      // ROOT-FIXED in lib/: `PaletteState.notifyListeners()` now detects the
      // build/layout/paint phase (`SchedulerPhase.persistentCallbacks`) and
      // defers ONLY the wake to a post-frame callback; outside a build (every
      // keystroke, every async result) it stays a plain synchronous notify
      // with no added latency. So `open()` is safe to call from anywhere —
      // including initState — and this test mounts the palette the production
      // way and asserts it pumps cleanly. If the deferral is ever removed the
      // `takeException()` check below goes red again. Behavior-level coverage
      // of the fix lives in
      // test/features/palette/palette_state_behavior_test.dart.
      final showPalette = ValueNotifier<bool>(false);
      addTearDown(showPalette.dispose);
      await pumpHarness(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: showPalette,
          builder: (context, show, _) => Scaffold(
            body: Center(
              child: SizedBox(
                width: 620,
                height: 520,
                child: show
                    ? CommandPalette(
                        currentMode: 0,
                        onClose: () {},
                        onCommitSelected: (_) {},
                        onModeChanged: (_) {},
                        onBranchCheckout: (_) {},
                        onFileSelected: (_) {},
                        onOpenXray: () {},
                        onOpenSettings: () {},
                        onRefresh: () {},
                        onUndo: () {},
                        onRepoSwitch: (_) {},
                        onDeskSwitch: (_) {},
                        onOpenBrowser: (_) {},
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        wrapAboveNavigator: wrapPalette,
      );

      showPalette.value = true;
      await tester.pump();

      // PaletteState.open() runs synchronously from initState — the
      // palette is "open" the moment it's mounted, so the pump above
      // already exercises that path. The unscored empty-query static
      // entries (Settings, X-Ray, Refresh, …) should already be showing.
      expect(find.text('Settings'), findsOneWidget);

      final elapsed = await timePump(tester, () async {
        await tester.enterText(find.byType(TextField), 'settings');
        await tester.pump();
      });

      // A looser ceiling than the app-shell pump's 250ms, on purpose. A
      // themed pump is light and warm, so 250ms there keeps a wide margin
      // over its true few-ms cost. Typing does heavier *synchronous* work
      // (buildStaticEntries + a full re-score), so its honest cost is tens of
      // ms and — measured — spikes toward ~300ms under the whole suite's
      // concurrent-isolate CPU contention, with no real regression. This gate
      // is therefore an ORDER-OF-MAGNITUDE block detector: it still catches
      // "the engine ran synchronously on the keystroke" (the ~2000ms filament
      // freeze class) while staying immune to load jitter that a tight bound
      // would flake on. Gate on order-of-magnitude wall clock; gate on exact
      // counters (rebuild_budget_test.dart) for anything finer.
      expect(
        elapsed.inMilliseconds,
        lessThan(budgetMs(1200)),
        reason:
            'typing a query took ${elapsed.inMilliseconds}ms — a '
            'keystroke must never run the engine synchronously (that would '
            'be seconds, not this); tens-to-low-hundreds of ms is the '
            'expected synchronous scoring cost',
      );

      // Let the debounced, post-frame-coalesced re-score settle, then assert
      // the palette is still a live, non-thrown tree. This is a JANK test:
      // its job is "the keystroke didn't block a frame and didn't crash the
      // panel," which the budget above plus a clean settle establish. WHICH
      // entries a given query surfaces (relevance/scoring, list
      // virtualization) is a separate concern that belongs in a palette-
      // scoring unit test, not here — asserting a specific label survives a
      // specific query would couple this frame-budget guard to the scorer's
      // ranking, which is exactly the brittleness a jank test should avoid.
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'typing into the palette must not throw (this is the '
            'regression guard for the initState-during-build assert that '
            'PaletteState.notifyListeners now defers past the frame)',
      );
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason:
            'the palette query field is still mounted and interactive '
            'after a re-score',
      );
    });
  });
}
