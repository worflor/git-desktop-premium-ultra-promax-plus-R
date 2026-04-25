import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/hyper_reactivity.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/components/hypercube_logo.dart';
import 'package:git_desktop/ui/theme.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('dragging logo updates HyperReactivity and HyperReactive visuals',
      (tester) async {
    const probeKey = Key('hyper-reactive-probe');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => HyperReactivity()),
          // HypercubeLogo reads PreferencesState in didChangeDependencies
          // for its motion/unfocused-animation gates.
          ChangeNotifierProvider(create: (_) => PreferencesState()),
        ],
        child: MaterialApp(
          theme: buildTheme(AppTokens.fromId(defaultThemeId)),
          home: Scaffold(
            body: Column(
              children: [
                const HypercubeLogo(size: 64),
                HyperReactive(
                  key: probeKey,
                  child: const SizedBox(width: 120, height: 24),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(HypercubeLogo));
    final hyper = Provider.of<HyperReactivity>(context, listen: false);
    expect(hyper.active, isFalse);
    expect(hyper.intensity, 0);

    final center = tester.getCenter(find.byType(HypercubeLogo));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveBy(const Offset(12, -8));
    await tester.pump();

    expect(hyper.active, isTrue);
    expect(hyper.intensity, greaterThan(0));
    expect(hyper.dragOffset.distance, greaterThan(0));
    expect(hyper.normalizedOffset.distance, greaterThan(0));

    final transformFinder = find.descendant(
      of: find.byKey(probeKey),
      matching: find.byType(Transform),
    );
    final transform = tester.widget<Transform>(transformFinder.first);
    expect(transform.transform.storage[0], greaterThan(1.0));

    // HyperReactive renders a plain Container (not AnimatedContainer) —
    // its foregroundDecoration is the glow/border driven by hyper state.
    final containerFinder = find.descendant(
      of: find.byKey(probeKey),
      matching: find.byType(Container),
    );
    final container = tester.widget<Container>(containerFinder.first);
    final decoration = container.foregroundDecoration as BoxDecoration?;
    expect(decoration, isNotNull);
    expect(decoration!.border, isNotNull);

    await gesture.up();
    await tester.pump();

    expect(hyper.active, isFalse);
    expect(hyper.intensity, 0);
    expect(hyper.dragOffset, Offset.zero);
    expect(hyper.normalizedOffset, Offset.zero);
  });
}
