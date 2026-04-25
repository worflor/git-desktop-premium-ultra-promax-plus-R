import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/system_browser.dart';

void main() {
  group('WindowsBrowserException', () {
    test('exposes the Win32 error code', () {
      final e = WindowsBrowserException(31, 'no association');
      expect(e.code, 31);
      expect(e.message, 'no association');
      expect(e.toString(), contains('31'));
      expect(e.toString(), contains('no association'));
    });
  });

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

  // Most of [openInSystemBrowser] is platform-gated and ends in either
  // an FFI call (Windows) or a Process.start (macOS/Linux), neither of
  // which is meaningful to drive from a unit test — both have side
  // effects we don't want during `flutter test`. The security contract
  // worth pinning here is that no shell metacharacter pass exists in
  // the source, which a static read of system_browser.dart confirms:
  // there is no `runInShell`, no `cmd /c`, no string concatenation
  // into a shell command line. The Windows path goes through
  // ShellExecuteW with a UTF-16 string handed directly to Win32; the
  // macOS/Linux paths use Process.start with argv, where Dart's
  // engine delivers args without re-parsing through a shell. The
  // scheme allowlist above is the second layer.
}
