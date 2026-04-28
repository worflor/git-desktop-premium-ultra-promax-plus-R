// Pins the round-trip contract for the External Tool args editor:
// `parse(display(args)) == args` for any list of strings, including
// arguments that contain whitespace, double quotes, and backslashes.
// The motivating regression is the reviewer's `--msg="hello world"`
// case where the prior display-only escape silently dropped quotes.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/settings/settings_page.dart';

void main() {
  group('External Tool args round-trip', () {
    void roundTrips(List<String> args, {String? reason}) {
      final rendered = argsToDisplayForRoundTrip(args);
      final reparsed = parseArgsForRoundTrip(rendered);
      expect(
        reparsed,
        args,
        reason: reason ??
            'parse(display($args)) should equal $args (rendered: $rendered)',
      );
    }

    test('plain tokens pass through', () {
      roundTrips(const []);
      roundTrips(const ['--help']);
      roundTrips(const ['-p', '4242']);
      roundTrips(const ['{path}', '--no-color']);
    });

    test('whitespace-bearing tokens are quoted', () {
      roundTrips(const ['hello world']);
      roundTrips(const ['--label', 'two words']);
      roundTrips(const ['a', 'b c d', 'e']);
      // Tab + newline are also whitespace per `\s`.
      roundTrips(const ['line\nfeed']);
    });

    test('embedded double quotes survive', () {
      // Reviewer's flagged case.
      roundTrips(const ['--msg="hello world"']);
      roundTrips(const ['say "hi"']);
      roundTrips(const ['"quoted-only"']);
    });

    test('embedded backslashes survive', () {
      // Common Windows-path arg shape.
      roundTrips(const [r'--path=C:\Users\me\dev']);
      // Backslash + space — quoted span, both escapes engage.
      roundTrips(const [r'C:\Program Files\git\bin\git.exe']);
      // Trailing backslash inside a quoted span (escape-edge).
      roundTrips(const [r'edge\']);
    });

    test('every weird combo at once', () {
      roundTrips(const [r'--cmd="C:\bin\foo.exe" /K --quiet']);
      roundTrips(const [r'has "quote" and \backslash']);
    });

    test('display form is stable for already-clean args', () {
      // No quotes added when not needed — keeps the editor visually
      // calm for the common case.
      expect(
        argsToDisplayForRoundTrip(const ['--help', '--no-color']),
        '--help --no-color',
      );
    });

    test('display quotes only the tokens that need it', () {
      expect(
        argsToDisplayForRoundTrip(const ['-p', 'hello world', '-q']),
        '-p "hello world" -q',
      );
    });

    test('parse handles unquoted backslashes verbatim', () {
      // Outside a quoted span, `\` is just a literal — the user's
      // typical Windows path doesn't need any escaping.
      expect(
        parseArgsForRoundTrip(r'C:\foo\bar'),
        const [r'C:\foo\bar'],
      );
    });

    test('parse decodes escape sequences only inside quotes', () {
      // `\"` inside a quoted span = literal `"`.
      expect(parseArgsForRoundTrip(r'"\"hi\""'), const ['"hi"']);
      // `\\` inside a quoted span = literal `\`.
      expect(parseArgsForRoundTrip(r'"a\\b"'), const [r'a\b']);
      // Other backslashes inside quotes pass through (no \n etc).
      expect(parseArgsForRoundTrip(r'"line\nbreak"'), const [r'line\nbreak']);
    });
  });
}
