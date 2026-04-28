// Pins the credential-stripping + scheme-coercion + .git-stripping
// contract for repo origin → web URL classification. The motivating
// regression is documented inline next to each test that maps to a
// reviewer-flagged shape.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/repo_web_url.dart';

void main() {
  group('hostOf', () {
    test('extracts host from https URL', () {
      expect(hostOf('https://github.com/owner/repo.git'), 'github.com');
    });

    test('extracts host from https URL with userinfo', () {
      // Was previously vulnerable: the @-anchored regex could capture
      // an embedded ampersand-bearing path segment as part of the
      // host. Uri.parse handles userinfo cleanly.
      expect(
        hostOf('https://oauth2:tokensecret@github.com/owner/repo'),
        'github.com',
      );
      expect(
        hostOf('https://x-access-token:abc@gitlab.com/owner/repo.git'),
        'gitlab.com',
      );
    });

    test('extracts host from http URL with userinfo', () {
      expect(hostOf('http://user@example.com/repo'), 'example.com');
    });

    test('extracts host from explicit ssh:// URL', () {
      expect(hostOf('ssh://git@github.com:22/owner/repo.git'), 'github.com');
    });

    test('extracts host from SSH-shorthand', () {
      expect(hostOf('git@github.com:owner/repo.git'), 'github.com');
      expect(hostOf('git@codeberg.org:owner/repo.git'), 'codeberg.org');
    });

    test('does not misread @ inside URL path', () {
      // Pathological-but-legal: `?ref=user@host` style query string.
      // Anchored SSH-shorthand regex only fires when there is no
      // earlier slash, so this URL routes through Uri.parse and
      // returns the proper authority.
      expect(
        hostOf('https://github.com/owner/repo?ref=user@host'),
        'github.com',
      );
    });

    test('returns null for malformed input', () {
      expect(hostOf(''), isNull);
      expect(hostOf('   '), isNull);
      expect(hostOf('not a url at all'), isNull);
    });
  });

  group('classifyRemote — credential stripping', () {
    test('strips userinfo from https remote', () {
      // Reviewer's primary case: a token-bearing URL would previously
      // be returned to the browser as-is, persisting credentials in
      // browser history.
      final info = classifyRemote(
        'https://oauth2:tokensecret@github.com/owner/repo.git',
      );
      expect(info, isNotNull);
      expect(info!.webUrl, 'https://github.com/owner/repo');
      expect(info.webUrl, isNot(contains('oauth2')));
      expect(info.webUrl, isNot(contains('tokensecret')));
      expect(info.webUrl, isNot(contains('@')));
    });

    test('strips userinfo from http remote and coerces to https', () {
      final info = classifyRemote(
        'http://user:pass@example.com/owner/repo.git',
      );
      expect(info, isNotNull);
      expect(info!.webUrl, 'https://example.com/owner/repo');
    });

    test('strips port and userinfo from explicit ssh URL', () {
      final info = classifyRemote(
        'ssh://git@github.com:2222/owner/repo.git',
      );
      expect(info, isNotNull);
      expect(info!.webUrl, 'https://github.com/owner/repo');
      expect(info.webUrl, isNot(contains(':2222')));
    });

    test('strips user@ from SSH-shorthand', () {
      final info = classifyRemote('git@github.com:owner/repo.git');
      expect(info, isNotNull);
      expect(info!.webUrl, 'https://github.com/owner/repo');
    });

    test('strips .git suffix from path', () {
      expect(
        classifyRemote('https://github.com/owner/repo.git')!.webUrl,
        'https://github.com/owner/repo',
      );
      // .git only stripped at the end of the path — a `.git` substring
      // mid-path stays put.
      expect(
        classifyRemote('https://github.com/owner/repo.gittery.git')!.webUrl,
        'https://github.com/owner/repo.gittery',
      );
    });

    test('produces brand label for canonical hosts only', () {
      expect(classifyRemote('https://github.com/o/r')!.label, 'GitHub');
      expect(classifyRemote('https://gitlab.com/o/r')!.label, 'GitLab');
      expect(classifyRemote('https://bitbucket.org/o/r')!.label, 'Bitbucket');
      // Self-hosted instances fall through to the bare host.
      expect(
        classifyRemote('https://github.mycompany.com/o/r')!.label,
        'github.mycompany.com',
      );
      expect(
        classifyRemote('git@codeberg.org:o/r.git')!.label,
        'codeberg.org',
      );
    });

    test('returns null for un-classifiable remotes', () {
      expect(classifyRemote(''), isNull);
      expect(classifyRemote('not a url'), isNull);
      // SSH-shorthand without a colon (no path/host separator) is
      // malformed — refuse rather than guess.
      expect(classifyRemote('git@github.com'), isNull);
    });
  });
}
