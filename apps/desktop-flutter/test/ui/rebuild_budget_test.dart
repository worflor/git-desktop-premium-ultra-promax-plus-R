// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// rebuild_budget_test.dart — deterministic rebuild-scope gates.
//
// No wall clock here (see jank_budget_test.dart for the wall-clock jank
// gate); this file counts EXACTLY which widgets Flutter rebuilds for a
// given state change, using Flutter's own `debugPrintRebuildDirtyWidgets`
// instrumentation.
//
// EMPIRICAL FINDING (verified against this Flutter/flutter_test version
// before anything below was built on it): `debugPrintRebuildDirtyWidgets`
// DOES emit real "Rebuilding Foo(...)" lines through `debugPrint` under
// `flutter test` — no fallback tally widget was needed. The one wrinkle:
// the debug flag (and the `debugPrint` override) MUST be restored
// SYNCHRONOUSLY, inside the test body, before it returns — NOT via
// `addTearDown`. `TestWidgetsFlutterBinding._verifyInvariants` runs its
// `debugAssertAllFoundationVarsUnset` check immediately after the test
// body completes, before queued `addTearDown` callbacks fire, so an
// `addTearDown`-based reset throws "The value of a foundation debug
// variable was changed by the test" on the very next test. [captureRebuilds]
// resets in a `finally` block for exactly this reason.
//
// Job of this file: establish the measurement technique (test 1 is a
// sanity check on the technique itself, not on app code) and put one real
// app-provider assertion on record (test 2), so a future test can pin
// something like "toggling one checkbox rebuilds 1 FileRow, not 4000."

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:git_desktop/app/hyper_reactivity.dart';

import '../support/widget_harness.dart';

/// Runs [action] with `debugPrintRebuildDirtyWidgets` enabled and returns
/// every "Rebuilding ..." line Flutter printed during it. Debug state is
/// always restored before returning — see the file-level doc comment for
/// why that must happen synchronously rather than via `addTearDown`.
Future<List<String>> captureRebuilds(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  final captured = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) captured.add(message);
  };
  debugPrintRebuildDirtyWidgets = true;
  try {
    await action();
  } finally {
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = original;
  }
  // `debugPrintRebuildDirtyWidgets` prints "Rebuilding Foo(...)" for
  // elements pulled off the owner's dirty list, but "Building Foo(...)"
  // (same instrumentation, different prefix) for elements forced through
  // `Element.update()` during reconciliation — e.g. a StatelessWidget
  // child whose parent rebuilt and handed it a new widget instance, as
  // happens one level below a ValueListenableBuilder. Verified empirically
  // against this Flutter version; both count as "this widget rebuilt".
  return captured
      .where((l) => l.startsWith('Rebuilding ') || l.startsWith('Building '))
      .toList(growable: false);
}

/// Pulls the leading widget-type token out of a "Rebuilding Foo(...)" or
/// "Building Foo(...)" line (e.g. "Rebuilding _Leaf(dirty)" -> "_Leaf",
/// "Building _Leaf" -> "_Leaf"), so assertions can match on widget identity
/// without caring about the parenthesized debug detail Flutter appends
/// (hash codes, dependency lists, etc — all noisy/unstable) or whether a
/// detail suffix was present at all (a widget with no debug properties,
/// like a bare `Text`-wrapping `StatelessWidget`, prints with no trailing
/// "(...)").
final _rebuildLine = RegExp(r'^(?:Rebuilding|Building) ([\w<>]+)');

Set<String> _rebuiltTypeNames(List<String> lines) {
  final names = <String>{};
  for (final line in lines) {
    final m = _rebuildLine.firstMatch(line);
    if (m != null) names.add(m.group(1)!);
  }
  return names;
}

class _Leaf extends StatelessWidget {
  final int value;
  const _Leaf(this.value);
  @override
  Widget build(BuildContext context) => Text('v=$value');
}

class _StaticSibling extends StatelessWidget {
  const _StaticSibling();
  @override
  Widget build(BuildContext context) => const Text('static-sibling');
}

class _HyperWatcher extends StatelessWidget {
  const _HyperWatcher();
  @override
  Widget build(BuildContext context) {
    final active = context.watch<HyperReactivity>().active;
    return Text('hyper=$active');
  }
}

void main() {
  testWidgets(
      'sanity: a ValueListenableBuilder rebuild does not touch its static siblings',
      (tester) async {
    final notifier = ValueNotifier<int>(0);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            const _StaticSibling(),
            ValueListenableBuilder<int>(
              valueListenable: notifier,
              builder: (context, value, _) => _Leaf(value),
            ),
          ],
        ),
      ),
    );

    final lines = await captureRebuilds(tester, () async {
      notifier.value = 1;
      await tester.pump();
    });
    final names = _rebuiltTypeNames(lines);

    // The counting method is sound iff toggling the notifier rebuilds the
    // builder's own subtree and nothing else — proves debugPrint capture
    // + the regex extraction correctly isolate per-widget rebuild scope.
    expect(names, contains('_Leaf'));
    expect(names, isNot(contains('_StaticSibling')),
        reason: 'a sibling outside the ValueListenableBuilder rebuilt; '
            'the counting method is not actually scoped');
  });

  testWidgets(
      'PreferencesState-tree change does not rebuild an unrelated sibling',
      (tester) async {
    // HyperReactivity, not PreferencesState.motionRate: PreferencesState's
    // setters (setMotionRate included) persist through SettingsStore to a
    // real file on disk (see backend/settings_store.dart) with no
    // test-injectable fake — calling one from a widget test risks writing
    // to the developer's actual Manifold settings file. HyperReactivity is
    // a synchronous, disk-free ChangeNotifier in the same harness provider
    // tree and exercises the identical claim: does a Provider-driven
    // rebuild stay scoped to the widgets that actually watch it.
    await pumpHarness(
      tester,
      const Scaffold(
        body: Column(
          children: [
            _StaticSibling(),
            _HyperWatcher(),
          ],
        ),
      ),
    );

    final hyper = Provider.of<HyperReactivity>(
      tester.element(find.byType(_HyperWatcher)),
      listen: false,
    );

    final lines = await captureRebuilds(tester, () async {
      hyper.activate(1.0);
      await tester.pump();
    });
    final names = _rebuiltTypeNames(lines);

    expect(names, contains('_HyperWatcher'));
    expect(names, isNot(contains('_StaticSibling')),
        reason: 'a sibling that never reads HyperReactivity rebuilt — '
            'the provider-scoped rebuild is leaking beyond its watchers');
  });
}
