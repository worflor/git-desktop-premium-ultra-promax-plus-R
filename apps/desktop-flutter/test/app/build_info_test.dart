import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/build_info.dart';

void main() {
  group('BuildChannel.badge', () {
    test('dev shows DEV', () {
      expect(BuildChannel.dev.badge, 'DEV');
    });
    test('beta shows BETA', () {
      expect(BuildChannel.beta.badge, 'BETA');
    });
    test('stable hides the tag', () {
      expect(BuildChannel.stable.badge, isNull);
    });
  });

  group('BuildInfo defaults', () {
    test('falls back to dev under flutter test (debug)', () {
      // Tests run in debug mode without dart-defines, so BuildInfo
      // should treat the binary as a dev build. This pins the contract
      // that an un-tagged debug build never masquerades as beta/stable.
      expect(BuildInfo.channel, BuildChannel.dev);
      expect(BuildInfo.tag, 'DEV');
    });

    test('versionDisplay falls back to "dev" when version is empty', () {
      expect(BuildInfo.versionDisplay, anyOf('dev', startsWith('dev')));
    });
  });

  group('BuildInfo.normalizeChannelId', () {
    // Tests run as dev (no MANIFOLD_CHANNEL define + kDebugMode), so the
    // build's own channel is dev. dev → dev passes through; on a real beta
    // or stable binary the dev case would migrate to that binary's channel.
    test('passes valid ids through verbatim', () {
      expect(BuildInfo.normalizeChannelId('dev'), 'dev');
      expect(BuildInfo.normalizeChannelId('beta'), 'beta');
      expect(BuildInfo.normalizeChannelId('stable'), 'stable');
    });

    test('is case-insensitive and trims whitespace', () {
      expect(BuildInfo.normalizeChannelId('  BETA  '), 'beta');
      expect(BuildInfo.normalizeChannelId('Stable'), 'stable');
    });

    test('unknown values fall back to the build channel', () {
      // In tests the build is dev, so unknown should fall to 'dev'.
      expect(BuildInfo.normalizeChannelId(''), 'dev');
      expect(BuildInfo.normalizeChannelId('canary'), 'dev');
      expect(BuildInfo.normalizeChannelId('release-candidate'), 'dev');
    });

    test('dev passes through on a dev build', () {
      // Sanity check: in this test environment BuildInfo.channel is dev,
      // and 'dev' should be preserved end-to-end.
      expect(BuildInfo.channel, BuildChannel.dev);
      expect(BuildInfo.normalizeChannelId('dev'), 'dev');
    });
  });

  group('normalizeChannelIdFor (parametric)', () {
    test('passes valid ids through, on every build channel', () {
      for (final build in BuildChannel.values) {
        expect(normalizeChannelIdFor('beta', build), 'beta');
        expect(normalizeChannelIdFor('stable', build), 'stable');
      }
    });

    test('dev is preserved only on a dev build', () {
      expect(normalizeChannelIdFor('dev', BuildChannel.dev), 'dev');
    });

    test('dev migrates to the build channel on a beta build', () {
      // Persisted state: user previously ran a dev build and chose 'dev'.
      // They've now installed the beta — there's no dev feed they can
      // reach, so the pref snaps to 'beta' to keep them on a real path.
      expect(normalizeChannelIdFor('dev', BuildChannel.beta), 'beta');
    });

    test('dev migrates to the build channel on a stable build', () {
      expect(normalizeChannelIdFor('dev', BuildChannel.stable), 'stable');
    });

    test('unknown values fall back to the build channel', () {
      expect(normalizeChannelIdFor('', BuildChannel.beta), 'beta');
      expect(normalizeChannelIdFor('canary', BuildChannel.stable), 'stable');
      expect(normalizeChannelIdFor('release', BuildChannel.dev), 'dev');
    });

    test('case + whitespace are tolerated on every build', () {
      expect(normalizeChannelIdFor('  BETA  ', BuildChannel.stable), 'beta');
      expect(normalizeChannelIdFor('Stable', BuildChannel.beta), 'stable');
      expect(normalizeChannelIdFor(' DEV ', BuildChannel.beta), 'beta');
    });
  });
}
