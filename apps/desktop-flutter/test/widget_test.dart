import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/app_identity.dart';
import 'package:git_desktop/app/brand_lockup.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/app/titlebar_strip.dart';
import 'package:git_desktop/ui/theme.dart';
import 'package:git_desktop/ui/tokens.dart';
import 'package:provider/provider.dart';

void main() {
  test('theme registry contains every source theme', () {
    expect(themeOptions.map((option) => option.id), AppThemeId.values);
    for (final option in themeOptions) {
      final tokens = AppTokens.fromId(option.id);
      final definition = themeDefinitionFor(option.id);
      expect(tokens.id, option.id);
      expect(definition.option.label, isNotEmpty);
      expect(definition.option.description, isNotEmpty);
    }
  });

  test('theme id normalization mirrors source fallback behavior', () {
    expect(defaultThemeId, AppThemeId.aether);
    expect(normalizeThemeId(' QUANTA '), AppThemeId.quanta);
    expect(normalizeThemeId('unknown-theme'), defaultThemeId);
  });

  test('theme data is cached per static token set', () {
    final first = buildTheme(AppTokens.fromId(AppThemeId.halo));
    final second = buildTheme(AppTokens.fromId(AppThemeId.halo));
    expect(identical(first, second), isTrue);
  });

  test('crafty keeps source brown surface ramp while particles remain enabled',
      () {
    final tokens = AppTokens.fromId(AppThemeId.crafty);
    final shader = themeDefinitionFor(AppThemeId.crafty).shader;
    expect(tokens.bg2, const Color(0xFF29211C));
    expect(tokens.bg3, const Color(0xFF3F342D));
    expect(tokens.themeSparkOpacity, 0);
    expect(shader.particles, ThemeParticles.voxels);
    expect(shader.parallaxStrength, greaterThan(0));
  });

  test('default app identity matches Manifold branding', () {
    expect(defaultAppIdentity.shortName, 'Manifold');
    expect(defaultAppIdentity.fullName, 'Manifold Git Client');
    expect(defaultAppIdentity.description, 'Your Personal Git Client');
    expect(defaultAppIdentity.tag, 'DEV');
  });

  testWidgets('brand lockup shows the app name and tag',
      (WidgetTester tester) async {
    await tester.pumpWidget(_buildHarness(const BrandLockup()));

    expect(find.text('Manifold'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);
  });

  testWidgets('brand lockup hides the tag chip when unset',
      (WidgetTester tester) async {
    final identityState =
        AppIdentityState(defaultAppIdentity.copyWith(tag: null));

    await tester.pumpWidget(
      _buildHarness(
        const BrandLockup(),
        identityState: identityState,
      ),
    );

    expect(find.text('Manifold'), findsOneWidget);
    expect(find.text('DEV'), findsNothing);
  });

  testWidgets('titlebar strip falls back to the app name with no repo',
      (WidgetTester tester) async {
    await tester.pumpWidget(_buildHarness(const TitlebarStrip()));

    expect(find.text('Manifold'), findsOneWidget);
  });

  testWidgets('titlebar strip prefers the active repo name',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _buildHarness(
        const TitlebarStrip(),
        repositoryState: _FakeRepositoryState('example-repo'),
      ),
    );

    expect(find.text('example-repo'), findsOneWidget);
    expect(find.text('Manifold'), findsNothing);
  });
}

Widget _buildHarness(
  Widget child, {
  AppIdentityState? identityState,
  RepositoryState? repositoryState,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(
        value: identityState ?? AppIdentityState(),
      ),
      ChangeNotifierProvider.value(
        value: repositoryState ?? RepositoryState(),
      ),
    ],
    child: MaterialApp(
      theme: buildTheme(AppTokens.fromId(defaultThemeId)),
      home: Scaffold(body: child),
    ),
  );
}

class _FakeRepositoryState extends RepositoryState {
  _FakeRepositoryState(this._repoName);

  final String? _repoName;

  @override
  String? get activeRepoName => _repoName;
}
