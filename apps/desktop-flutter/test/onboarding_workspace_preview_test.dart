// Verifies the redesigned onboarding mock workspace (WorkspacePreview)
// renders and behaves without exceptions: every top-bar panel switch is
// exercised (changes / history / branches / x-ray / settings), the new
// history worldline strip accepts a commit-row tap, and the branches
// strata panel surfaces its HEAD / tracking / absorbed captions.
//
//   flutter test test/onboarding_workspace_preview_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/app_identity.dart';
import 'package:git_desktop/app/hyper_reactivity.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/components/icons/app_icons.dart';
import 'package:git_desktop/features/onboarding/widgets/workspace_preview.dart';
import 'package:git_desktop/i18n/gen/strings.g.dart';
import 'package:git_desktop/ui/theme.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

// TranslationProvider mirrors main.dart's outermost wrapper — the preview's
// demo strings resolve via `context.t` and throw without it.
Widget _harness(AppTokens tokens) => TranslationProvider(
  child: MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => PreferencesState()),
      ChangeNotifierProvider(create: (_) => AppIdentityState()),
      ChangeNotifierProvider(create: (_) => HyperReactivity()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(tokens),
      home: Scaffold(
        backgroundColor: tokens.surface0,
        body: const Center(
          child: SizedBox(width: 640, height: 360, child: WorkspacePreview()),
        ),
      ),
    ),
  ),
);

/// Finds the top-bar icon button carrying the [AppIcon] named [name].
Finder _topIcon(String name) =>
    find.byWidgetPredicate((w) => w is AppIcon && w.name == name);

void main() {
  testWidgets('workspace preview renders and switches panels without '
      'exceptions', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tokens = AppTokens.fromId(AppThemeId.nightwalker);

    await tester.pumpWidget(_harness(tokens));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull, reason: 'initial render');

    // The default panel is Changes — its file rows should be present.
    // ('fox.dart' shows twice: the file-list row and the diff-panel header.)
    expect(find.text('fox.dart'), findsWidgets);

    // Walk every top-bar panel. Each icon must exist and switch cleanly.
    for (final icon in const [
      'history',
      'branches',
      'xray',
      'settings',
      'changes',
    ]) {
      final finder = _topIcon(icon);
      expect(finder, findsOneWidget, reason: 'top icon "$icon" present');
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester.takeException(),
        isNull,
        reason: 'after switching to "$icon" panel',
      );
    }

    // --- History worldline panel: tap a commit row. ---
    await tester.tap(_topIcon('history'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull, reason: 'history panel shown');

    final commitRow = find.text('thorn guards the gate');
    expect(commitRow, findsOneWidget, reason: 'history commit row present');
    await tester.tap(commitRow);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull, reason: 'after tapping commit row');

    // --- Branches strata panel: verify the redesigned captions. ---
    await tester.tap(_topIcon('branches'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull, reason: 'branches panel shown');

    expect(find.text('HEAD'), findsOneWidget);
    expect(find.text('absorbed'), findsOneWidget);
    expect(find.text('→ tracking: origin/main'), findsOneWidget);
  });
}
