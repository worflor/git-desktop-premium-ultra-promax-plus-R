// widget_harness.dart — the one place a widget test gets a real app shell.
//
// Pumping any Manifold surface means standing up its provider tree; doing
// that ad hoc per test is why there are 18 widget tests in a 240k-line app.
// Everything a real screen needs — `MaterialApp` + `AppThemeExtension` +
// the full `MultiProvider` stack `main.dart` builds before `runApp` — lives
// here once, so a new widget test is `pumpHarness(tester, MyScreen())` and
// nothing else.
//
// Excluded providers — these appear in `main.dart`'s `MultiProvider` but are
// deliberately left out of [harnessApp] because their constructors require
// arguments (another provider instance), which conflicts with "construct
// every state with its default constructor" — the harness stays a flat,
// order-independent list instead of a hand-wired dependency graph:
//   * WorktreeState(RepositoryState) — needs a RepositoryState instance.
//   * DeskPrState(RepositoryState, AppIdentityState) — needs both.
//   * DeskIssueState(RepositoryState, AppIdentityState) — needs both.
//   * RemoteIssueCacheState(RepositoryState) — needs a RepositoryState
//     instance.
// A test that specifically exercises one of these should build it directly
// (`WorktreeState(context.read<RepositoryState>())`) via [harnessApp]'s
// `wrapAboveNavigator` hook (see its doc comment) rather than wrapping
// [home] — EMPIRICALLY, a provider placed inside `home` sits BELOW
// `MaterialApp`'s Navigator, but `CommandPalette` (and anything else using
// `Navigator.of(context, rootNavigator: true).context`, a deliberate
// pattern — see command_palette.dart's `initState` comment) reads providers
// from the ROOT navigator's context, which only sees providers placed
// ABOVE the Navigator. `wrapAboveNavigator` runs in exactly that slot.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:git_desktop/app/ai_activity_state.dart';
import 'package:git_desktop/app/ai_settings_state.dart';
import 'package:git_desktop/app/alpha_math_state.dart';
import 'package:git_desktop/app/app_identity.dart';
import 'package:git_desktop/app/commit_mode_state.dart';
import 'package:git_desktop/app/external_tools_state.dart';
import 'package:git_desktop/app/file_coupling_state.dart';
import 'package:git_desktop/app/hyper_reactivity.dart';
import 'package:git_desktop/app/logos_git_state.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/app/repo_embedding_state.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/app/repository_xray_state.dart';
import 'package:git_desktop/app/settings_navigation_state.dart';
import 'package:git_desktop/app/sidebar_org_state.dart';
import 'package:git_desktop/app/theme_state.dart';
import 'package:git_desktop/app/tool_detection_state.dart';
import 'package:git_desktop/app/wick_state.dart';
import 'package:git_desktop/app/worktree_state.dart';
import 'package:git_desktop/app/desk_pr_state.dart';
import 'package:git_desktop/backend/settings_store.dart';
import 'package:git_desktop/backend/storage_paths.dart';
import 'package:git_desktop/backend/undo_controller.dart';
import 'package:git_desktop/diagnostics/diagnostics_state.dart';
import 'package:git_desktop/features/onboarding/onboarding_state.dart';
import 'package:git_desktop/features/palette/palette_state.dart';
import 'package:git_desktop/ui/tokens.dart';

/// Loads the app's real body font (`DMSans-Variable.ttf`) so widget tests
/// render actual glyph metrics instead of the tofu/placeholder boxes
/// `flutter_test` substitutes by default — load-bearing for any test that
/// measures text (contrast/tap-target guidelines, golden-ish previews).
///
/// Safe to call once in `setUpAll`. If the font asset is missing (e.g. run
/// from an unexpected working directory), this prints a warning and returns
/// rather than throwing, so a font-path problem doesn't take down every
/// widget test in the suite.
Future<void> loadTestFonts() async {
  final file = File('assets/fonts/DMSans-Variable.ttf');
  if (!file.existsSync()) {
    // ignore: avoid_print
    print('widget_harness: assets/fonts/DMSans-Variable.ttf not found '
        '(cwd=${Directory.current.path}) — skipping font load');
    return;
  }
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('DMSans')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// Installs an in-memory mock for the `shared_preferences` plugin channel.
///
/// `flutter_test` has no real platform binding, so any state class that
/// touches `SharedPreferences.getInstance()` (several do, on save paths and
/// a few on construction-adjacent loads) throws `MissingPluginException`
/// without this. Installing the mock ALSO silences the
/// "Diagnostics background IO failed: MissingPluginException" noise that
/// otherwise pollutes every test run's output.
///
/// Call once in `setUpAll`.
void installSharedPreferencesMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (call) async => call.method == 'getAll' ? <String, Object>{} : null,
  );
}

/// Installs the hermetic storage/refresh seams AND registers their reset with
/// `addTearDown` in a single call, so a widget test can never leak a
/// process-global static into a later test in the same file by forgetting to
/// undo it (the failure mode is silent: a stuck `debugSuppressDiskWrites`
/// makes a later test's settings writes vanish). Call from a test body or
/// `setUp`; the teardown fires automatically after that test.
///
/// Seals every real-I/O source that hangs under `testWidgets`' fake-async
/// clock: auto-refresh git work ([WorktreeState]/[DeskPrState]), settings
/// persistence ([SettingsStore] — seeded so `load()` never reads disk, and
/// writes kept memory-only), and the data dir ([StoragePaths] → a temp dir
/// that is deleted on teardown). Returns the temp dir for tests that want to
/// assert on-disk artifacts.
Future<Directory> installHermeticStorageSeams() async {
  WorktreeState.debugSuppressAutoRefresh = true;
  DeskPrState.debugSuppressAutoRefresh = true;
  SettingsStore.seedForTest(AppSettingsSnapshot.defaults());
  SettingsStore.debugSuppressDiskWrites = true;
  final dir = await Directory.systemTemp.createTemp('gdpu_hermetic_test_');
  StoragePaths.debugOverrideDir = dir;
  addTearDown(() async {
    WorktreeState.debugSuppressAutoRefresh = false;
    DeskPrState.debugSuppressAutoRefresh = false;
    SettingsStore.debugSuppressDiskWrites = false;
    SettingsStore.invalidateCache();
    StoragePaths.debugOverrideDir = null;
    try {
      await dir.delete(recursive: true);
    } catch (_) {/* best-effort; a lingering handle must not fail teardown */}
  });
  return dir;
}

/// Wraps [home] in the full provider tree + `MaterialApp` + themed
/// `AppThemeExtension`, mirroring the shape `main.dart` passes to `runApp`
/// (minus the four providers documented at the top of this file). Every
/// state object is built with its default (no-argument) constructor —
/// none of them do disk/plugin I/O synchronously in that constructor, so
/// this is safe to call from any widget test without `runAsync`.
///
/// [wrapAboveNavigator], if given, receives the already-built `MaterialApp`
/// plus a [BuildContext] that sees every base provider (so it can do
/// `WorktreeState(context.read<RepositoryState>())`) and returns whatever
/// wraps it — typically another `MultiProvider`. The wrap happens ABOVE
/// `MaterialApp`, i.e. above its `Navigator`, not around [home]. That
/// placement matters: see the file-level doc comment's "Excluded
/// providers" note for why a provider wrapping [home] directly is invisible
/// to code that reads via `Navigator.of(context, rootNavigator: true)`.
Widget harnessApp({
  required Widget home,
  AppThemeId theme = AppThemeId.aether,
  Widget Function(BuildContext context, Widget app)? wrapAboveNavigator,
}) {
  final tokens = AppTokens.fromId(theme);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeState>(create: (_) => ThemeState()),
      ChangeNotifierProvider<RepositoryState>(create: (_) => RepositoryState()),
      ChangeNotifierProvider<RepositoryXrayState>(
          create: (_) => RepositoryXrayState()),
      ChangeNotifierProvider<FileCouplingState>(
          create: (_) => FileCouplingState()),
      ChangeNotifierProvider<RepoEmbeddingState>(
          create: (_) => RepoEmbeddingState()),
      ChangeNotifierProvider<LogosGitState>(create: (_) => LogosGitState()),
      ChangeNotifierProvider<PreferencesState>(
          create: (_) => PreferencesState()),
      ChangeNotifierProvider<AiSettingsState>(
          create: (_) => AiSettingsState()),
      ChangeNotifierProvider<AiActivityState>(
          create: (_) => AiActivityState()),
      ChangeNotifierProvider<ExternalToolsState>(
          create: (_) => ExternalToolsState()),
      ChangeNotifierProvider<SidebarOrgState>(
          create: (_) => SidebarOrgState()),
      ChangeNotifierProvider<CommitModeState>(
          create: (_) => CommitModeState()),
      ChangeNotifierProvider<ToolDetectionState>(
          create: (_) => ToolDetectionState()),
      ChangeNotifierProvider<WickState>(create: (_) => WickState()),
      ChangeNotifierProvider<AlphaMathState>(
          create: (_) => AlphaMathState()),
      ChangeNotifierProvider<SettingsNavigationState>(
          create: (_) => SettingsNavigationState()),
      // Singleton — a fresh instance per test would defeat the point of
      // `.instance`, and other production code reads the same singleton.
      ChangeNotifierProvider<DiagnosticsState>.value(
          value: DiagnosticsState.instance),
      ChangeNotifierProvider<AppIdentityState>(
          create: (_) => AppIdentityState()),
      ChangeNotifierProvider<OnboardingState>(
          create: (_) => OnboardingState()),
      ChangeNotifierProvider<HyperReactivity>(
          create: (_) => HyperReactivity()),
      ChangeNotifierProvider<PaletteState>(create: (_) => PaletteState()),
      ChangeNotifierProvider<UndoCoordinator>(
          create: (_) => UndoCoordinator()),
    ],
    child: Builder(builder: (context) {
      final app = MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'DMSans',
          extensions: <ThemeExtension<dynamic>>[AppThemeExtension(tokens)],
        ),
        home: home,
      );
      return wrapAboveNavigator?.call(context, app) ?? app;
    }),
  );
}

/// Sets a desktop-sized view, pumps [home] inside [harnessApp], and settles
/// the first frame. Registers `addTearDown` resets for the view overrides
/// so tests don't leak size/DPR state into whichever test runs next.
/// [theme] and [wrapAboveNavigator] pass straight through to [harnessApp].
Future<void> pumpHarness(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(1400, 900),
  AppThemeId theme = AppThemeId.aether,
  Widget Function(BuildContext context, Widget app)? wrapAboveNavigator,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(harnessApp(
    home: home,
    theme: theme,
    wrapAboveNavigator: wrapAboveNavigator,
  ));
  await tester.pump();
}
