// Shared harness for OrreryView widget/render tests. Since the Orrery now uses
// the app's house controls (ChromeButton / InteractionFeedback) and motion
// engine, its widget tree needs a PreferencesState in scope — exactly as the
// real app provides one. Wrap the [home] with this so context.motion /
// reduceMotion / the per-theme tap feedback all resolve.

import 'package:flutter/material.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

Widget orreryTestApp({required AppThemeId theme, required Widget home}) {
  final tokens = AppTokens.fromId(theme);
  return ChangeNotifierProvider<PreferencesState>(
    create: (_) => PreferencesState(),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[
        AppThemeExtension(tokens),
      ]),
      home: home,
    ),
  );
}
