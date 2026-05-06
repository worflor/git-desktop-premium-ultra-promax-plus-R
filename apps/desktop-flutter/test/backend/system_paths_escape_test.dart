// Pins the cmd.exe arg escape contract for runInTerminal's Windows
// fallback. cmd's `/K "..."` parser keeps `& | < > ^ ( )` literal
// inside double quotes, but `%var%` expansion still happens — that
// is the surprise the escape function has to defend against.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/system_paths.dart';

void main() {
  group('escapeCmdArg', () {
    test('passes plain text through', () {
      expect(escapeCmdArgForTesting('hello'), 'hello');
      expect(escapeCmdArgForTesting('hello world'), 'hello world');
      expect(escapeCmdArgForTesting(''), '');
    });

    test('doubles % so cmd does not expand %var%', () {
      // The case that motivates this contract: a repo path or argv
      // entry containing a literal % would otherwise either expand
      // to whatever environment variable name follows, or be
      // truncated. `%%` is collapsed back to a single `%` by cmd.
      expect(escapeCmdArgForTesting('100% complete'), '100%% complete');
      expect(escapeCmdArgForTesting('%PATH%'), '%%PATH%%');
      expect(
        escapeCmdArgForTesting(r'C:\Users\dev\project%foo%bin'),
        r'C:\Users\dev\project%%foo%%bin',
      );
    });

    test('escapes literal double quotes', () {
      expect(escapeCmdArgForTesting('a"b'), r'a\"b');
      expect(escapeCmdArgForTesting('"wrap"'), r'\"wrap\"');
    });

    test('escapes both % and quotes in the same arg', () {
      expect(
        escapeCmdArgForTesting('say "%USER% wins"'),
        r'say \"%%USER%% wins\"',
      );
    });

    test('leaves cmd metacharacters that are literal inside quotes alone', () {
      // Inside `"..."`, cmd keeps `& | < > ^ ( )` as plain chars per
      // its documented quoting rule. We rely on the upstream double-
      // quote wrap to neutralize them, so the escape function must
      // not mangle them itself.
      const samples = [
        'foo & bar',
        'one|two',
        'a < b > c',
        'caret^arg',
        'group(stuff)',
      ];
      for (final s in samples) {
        expect(
          escapeCmdArgForTesting(s),
          s,
          reason: '"$s" should pass through unchanged',
        );
      }
    });

    test('handles real-world Windows path with space + ampersand', () {
      // Windows allows `&` in file names; a project at that path must
      // launch correctly when its absolute path is templated into an
      // argv slot.
      expect(
        escapeCmdArgForTesting(r'C:\Users\me\dev\foo & bar'),
        r'C:\Users\me\dev\foo & bar',
      );
    });
  });

  group('escapeWtArg', () {
    test('escapes only literal double quotes', () {
      // wt.exe parses through CreateProcessW without going through
      // cmd, so cmd metacharacters and `%` are irrelevant — the only
      // structural character is the wrapping quote.
      expect(escapeWtArgForTesting('100% complete'), '100% complete');
      expect(escapeWtArgForTesting(r'C:\path%var%file'), r'C:\path%var%file');
      expect(escapeWtArgForTesting('a"b'), r'a\"b');
      expect(escapeWtArgForTesting('plain'), 'plain');
    });
  });

  group('windows reveal batch launcher', () {
    test('keeps explorer select path quoted after the comma', () {
      final script = windowsRevealBatchScriptForTesting(
        r'C:\Users\me\My Repo\lib\main.dart',
      );

      expect(
        script,
        contains(
          r'start "" explorer.exe /select,"C:\Users\me\My Repo\lib\main.dart"',
        ),
      );
      expect(script, isNot(contains('/select, ')));
    });

    test('escapes percent signs in embedded batch path', () {
      final script = windowsRevealBatchScriptForTesting(
        r'C:\Users\me\100% complete\%PATH%\file.dart',
      );

      expect(
        script,
        contains(r'C:\Users\me\100%% complete\%%PATH%%\file.dart'),
      );
    });

    test('passes cmd call and temporary script path as separate argv entries',
        () {
      expect(
        windowsRevealBatchArgsForTesting(
          r'C:\Users\me\AppData\Local\Temp\manifold reveal.cmd',
        ),
        [
          '/d',
          '/c',
          'call',
          r'C:\Users\me\AppData\Local\Temp\manifold reveal.cmd',
        ],
      );
    });
  });
}
