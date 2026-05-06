import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/system_browser.dart';

void main() {
  group('isAllowedBrowserUrl', () {
    test('accepts http and https URLs with authority', () {
      expect(isAllowedBrowserUrl('https://example.com'), isTrue);
      expect(isAllowedBrowserUrl('http://example.com'), isTrue);
      expect(isAllowedBrowserUrl('https://example.com/path?q=1#f'), isTrue);
      expect(isAllowedBrowserUrl('  https://example.com  '), isTrue);
    });

    test('rejects schemes that ShellExecuteW would dispatch', () {
      // The motivating attack: a hostile manifest pushes one of these
      // and the OPEN DOWNLOAD button (or any future caller) asks the
      // OS to "open" it. Each of these resolves through a registered
      // protocol handler on at least one supported platform.
      const malicious = [
        'file:///C:/Windows/System32/calc.exe',
        r'file:////host/share/payload.exe',
        'ms-appinstaller://?source=https://evil.example/x.appinstaller',
        'javascript:alert(1)',
        'mailto:leaked@example.com',
        'vscode://settings/manifold',
        'data:text/html,<script>alert(1)</script>',
        'ftp://example.com/file',
        'vbscript:msgbox(1)',
      ];
      for (final url in malicious) {
        expect(
          isAllowedBrowserUrl(url),
          isFalse,
          reason: 'URL with scheme ${Uri.tryParse(url)?.scheme} should be rejected',
        );
      }
    });

    test('rejects malformed inputs', () {
      expect(isAllowedBrowserUrl(''), isFalse);
      expect(isAllowedBrowserUrl('   '), isFalse);
      expect(isAllowedBrowserUrl('not a url'), isFalse);
      // Scheme without authority — Uri.tryParse accepts these as
      // technically-valid but they don't have a host to dispatch to.
      expect(isAllowedBrowserUrl('https:'), isFalse);
      expect(isAllowedBrowserUrl('http:/'), isFalse);
    });
  });

  // openInSystemBrowser is platform-gated and ends in Process.start
  // on all platforms, which is not meaningful to drive from a unit
  // test. The security contract pinned here is the URL scheme
  // allowlist — only http/https with a valid authority pass through.
}
