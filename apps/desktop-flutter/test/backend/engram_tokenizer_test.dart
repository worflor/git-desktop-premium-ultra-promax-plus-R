// Unit tests for engram_tokenizer.dart. Handles the bag of identifier
// shapes we see in real code: camelCase, PascalCase, snake_case,
// kebab-case, SCREAMING_SNAKE, HTTPResponse-style acronyms, digits.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/engram_tokenizer.dart';

void main() {
  group('splitIdentifier', () {
    test('empty / single-char input returns empty', () {
      expect(splitIdentifier(''), isEmpty);
      expect(splitIdentifier('a'), isEmpty);
    });

    test('simple lowercase word passes through', () {
      expect(splitIdentifier('hello'), ['hello']);
    });

    test('camelCase splits on humps', () {
      expect(splitIdentifier('getUserProfile'), ['get', 'user', 'profile']);
    });

    test('PascalCase splits on humps', () {
      expect(splitIdentifier('UserAuthService'),
          ['user', 'auth', 'service']);
    });

    test('snake_case splits on underscores', () {
      expect(splitIdentifier('build_diff_hunk'), ['build', 'diff', 'hunk']);
    });

    test('kebab-case splits on hyphens', () {
      expect(splitIdentifier('user-auth-token'),
          ['user', 'auth', 'token']);
    });

    test('SCREAMING_SNAKE_CASE lowercases', () {
      expect(splitIdentifier('MAX_BUFFER_SIZE'),
          ['max', 'buffer', 'size']);
    });

    test('acronym runs split correctly (HTTPServer → http, server)', () {
      expect(splitIdentifier('HTTPServer'), ['http', 'server']);
      expect(splitIdentifier('XMLHttpRequest'),
          ['xml', 'http', 'request']);
      expect(splitIdentifier('JSONParse'), ['json', 'parse']);
    });

    test('mixed digit-letter transitions break', () {
      // "word2vec" → ["word", "vec"] (digits dropped)
      expect(splitIdentifier('word2vec'), ['word', 'vec']);
      // "latin1Encoder" → ["latin", "encoder"]
      expect(splitIdentifier('latin1Encoder'), ['latin', 'encoder']);
    });

    test('pure-digit runs are dropped', () {
      expect(splitIdentifier('1234'), isEmpty);
    });

    test('letter-then-digit transition splits and drops digit', () {
      // "v" is len=1 (below min=2, dropped), "123" is digit-only (dropped)
      expect(splitIdentifier('v123'), isEmpty);
    });

    test('short 2-char tokens retained (db, io, ui)', () {
      expect(splitIdentifier('openDb'), ['open', 'db']);
      expect(splitIdentifier('ioStream'), ['io', 'stream']);
    });

    test('punctuation boundaries work', () {
      expect(splitIdentifier('auth.handler.init'),
          ['auth', 'handler', 'init']);
      // "to" is len=2, allowed — kept in the output.
      expect(splitIdentifier('path/to/file'),
          ['path', 'to', 'file']);
    });

    test('non-ASCII passes through the character-class filter (ignored)', () {
      // Non-ASCII letters hit the "boundary" kind in our simple ASCII
      // classifier, so `émile` becomes just "mile" (length 4) — which is
      // fine behaviour; we're targeting ASCII identifiers.
      final out = splitIdentifier('émile');
      expect(out, ['mile']);
    });
  });

  group('expandIdentifiers', () {
    test('walks a bag and concatenates sub-tokens', () {
      final out = expandIdentifiers(
        ['getUserProfile', 'validateToken', 'sessionManager'],
      );
      expect(
        out,
        [
          'get',
          'user',
          'profile',
          'validate',
          'token',
          'session',
          'manager',
        ],
      );
    });

    test('preserves duplicates across identifiers', () {
      final out = expandIdentifiers(['getUser', 'setUser']);
      expect(out, ['get', 'user', 'set', 'user']);
    });
  });
}
