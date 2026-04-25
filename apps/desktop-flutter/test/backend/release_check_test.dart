import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/release_check.dart';

void main() {
  group('compareSemver', () {
    test('equal versions compare 0', () {
      expect(compareSemver('1.2.3', '1.2.3'), 0);
    });

    test('major version dominates', () {
      expect(compareSemver('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('minor breaks ties on major', () {
      expect(compareSemver('1.3.0', '1.2.99'), greaterThan(0));
    });

    test('patch breaks ties on minor', () {
      expect(compareSemver('1.2.3', '1.2.2'), greaterThan(0));
    });

    test('release > prerelease at same base', () {
      expect(compareSemver('1.0.0', '1.0.0-beta'), greaterThan(0));
      expect(compareSemver('1.0.0-beta', '1.0.0'), lessThan(0));
    });

    test('prerelease numeric compares numerically, not lex', () {
      expect(
        compareSemver('1.0.0-beta.10', '1.0.0-beta.2'),
        greaterThan(0),
      );
    });

    test('prerelease numeric < alpha', () {
      // semver: numeric identifiers always have lower precedence than
      // alphanumeric ones — alpha.1 > alpha.beta is false, but
      // 1.0.0-1 < 1.0.0-alpha holds.
      expect(compareSemver('1.0.0-1', '1.0.0-alpha'), lessThan(0));
    });

    test('shorter prerelease < longer prerelease when prefix matches', () {
      expect(
        compareSemver('1.0.0-alpha', '1.0.0-alpha.1'),
        lessThan(0),
      );
    });

    test('build metadata is ignored', () {
      expect(compareSemver('1.0.0+abc', '1.0.0+xyz'), 0);
      expect(compareSemver('1.0.0+abc', '1.0.0'), 0);
    });

    test('empty strings sort as oldest', () {
      expect(compareSemver('', '0.0.1'), lessThan(0));
      expect(compareSemver('0.0.1', ''), greaterThan(0));
      expect(compareSemver('', ''), 0);
    });

    test('beta-bump is detected as newer', () {
      // Concrete case for our use: a BETA build at 0.2.0-beta.1 sees
      // a published 0.2.0-beta.2 as newer.
      expect(
        compareSemver('0.2.0-beta.2', '0.2.0-beta.1'),
        greaterThan(0),
      );
    });
  });

  group('ReleaseManifest.fromJson', () {
    test('parses required fields', () {
      final m = ReleaseManifest.fromJson({
        'version': '0.2.0-beta.2',
        'channel': 'beta',
      });
      expect(m.version, '0.2.0-beta.2');
      expect(m.channel, 'beta');
      expect(m.downloadUrl, isNull);
      expect(m.notes, isNull);
      expect(m.publishedAt, isNull);
    });

    test('parses optional fields', () {
      final m = ReleaseManifest.fromJson({
        'version': '0.2.0-beta.2',
        'channel': 'beta',
        'downloadUrl': 'https://example.com/x.zip',
        'notes': 'Bug fixes.',
        'publishedAt': '2026-04-25T12:00:00Z',
      });
      expect(m.downloadUrl, 'https://example.com/x.zip');
      expect(m.notes, 'Bug fixes.');
      expect(m.publishedAt, isNotNull);
    });

    test('throws when version is missing', () {
      expect(
        () => ReleaseManifest.fromJson({'channel': 'beta'}),
        throwsFormatException,
      );
    });

    test('throws when channel is missing', () {
      expect(
        () => ReleaseManifest.fromJson({'version': '1.0.0'}),
        throwsFormatException,
      );
    });
  });

  group('ReleaseChecker.check', () {
    test('reports notConfigured when no base URL is set', () async {
      final result = await ReleaseChecker.check(
        channel: 'beta',
        currentVersion: '0.2.0-beta.1',
        overrideBaseUrl: '',
      );
      expect(result.status, ReleaseCheckStatus.notConfigured);
      expect(result.currentVersion, '0.2.0-beta.1');
      expect(result.channel, 'beta');
      expect(result.manifest, isNull);
    });

    test('rejects http base URLs as not configured', () async {
      // Defense-in-depth: an HTTP base URL lets MITM rewrite the
      // manifest body, which controls a string the user clicks. Fail
      // fast with a clear errorDetail rather than letting the request
      // proceed and hoping the response is honest.
      final result = await ReleaseChecker.check(
        channel: 'beta',
        currentVersion: '0.1.0',
        overrideBaseUrl: 'http://manifold.example.com',
      );
      expect(result.status, ReleaseCheckStatus.notConfigured);
      expect(result.errorDetail, contains('https'));
      expect(result.manifest, isNull);
    });
  });

  group('ReleaseManifest.fromJson — downloadUrl scheme allowlist', () {
    test('keeps an https downloadUrl', () {
      final m = ReleaseManifest.fromJson({
        'version': '0.2.0-beta.2',
        'channel': 'beta',
        'downloadUrl': 'https://releases.example.com/x.zip',
      });
      expect(m.downloadUrl, 'https://releases.example.com/x.zip');
    });

    test('keeps an http downloadUrl', () {
      // Browsers themselves still tolerate http for legacy sites; the
      // URL is opened in the system browser, which sandboxes the page.
      final m = ReleaseManifest.fromJson({
        'version': '0.2.0-beta.2',
        'channel': 'beta',
        'downloadUrl': 'http://legacy.example.com/x.zip',
      });
      expect(m.downloadUrl, 'http://legacy.example.com/x.zip');
    });

    test('drops file:// downloadUrl', () {
      final m = ReleaseManifest.fromJson({
        'version': '0.2.0-beta.2',
        'channel': 'beta',
        'downloadUrl': 'file:///C:/Windows/System32/calc.exe',
      });
      expect(m.downloadUrl, isNull);
    });

    test('drops UNC-style file:// downloadUrl', () {
      final m = ReleaseManifest.fromJson({
        'version': '0.2.0-beta.2',
        'channel': 'beta',
        'downloadUrl': r'file:////evil-host/share/rce.exe',
      });
      expect(m.downloadUrl, isNull);
    });

    test('drops ms-appinstaller scheme', () {
      // ms-appinstaller has been used in real RCE chains for Windows.
      final m = ReleaseManifest.fromJson({
        'version': '0.2.0-beta.2',
        'channel': 'beta',
        'downloadUrl':
            'ms-appinstaller:?source=https://attacker.example/x.appinstaller',
      });
      expect(m.downloadUrl, isNull);
    });

    test('drops javascript:, mailto:, custom schemes', () {
      for (final bad in [
        'javascript:alert(1)',
        'mailto:leaked@example.com',
        'vscode://attack/path',
        'data:text/html,<script>alert(1)</script>',
      ]) {
        final m = ReleaseManifest.fromJson({
          'version': '0.2.0-beta.2',
          'channel': 'beta',
          'downloadUrl': bad,
        });
        expect(m.downloadUrl, isNull, reason: 'should drop $bad');
      }
    });

    test('drops malformed downloadUrl', () {
      final m = ReleaseManifest.fromJson({
        'version': '0.2.0-beta.2',
        'channel': 'beta',
        'downloadUrl': 'not a real url',
      });
      expect(m.downloadUrl, isNull);
    });

    test('drops scheme-only downloadUrl with no authority', () {
      final m = ReleaseManifest.fromJson({
        'version': '0.2.0-beta.2',
        'channel': 'beta',
        'downloadUrl': 'https:',
      });
      expect(m.downloadUrl, isNull);
    });
  });
}
