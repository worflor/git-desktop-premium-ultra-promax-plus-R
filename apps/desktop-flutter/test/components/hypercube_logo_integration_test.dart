import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/hyper_reactivity.dart';
import 'package:git_desktop/components/hypercube_logo.dart';
import 'package:git_desktop/ui/theme.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('dragging logo updates HyperReactivity and HyperReactive visuals',
      (tester) async {
    const probeKey = Key('hyper-reactive-probe');

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => HyperReactivity(),
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

    final animatedFinder = find.descendant(
      of: find.byKey(probeKey),
      matching: find.byType(AnimatedContainer),
    );
    final animated = tester.widget<AnimatedContainer>(animatedFinder.first);
    final decoration = animated.foregroundDecoration as BoxDecoration?;
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
