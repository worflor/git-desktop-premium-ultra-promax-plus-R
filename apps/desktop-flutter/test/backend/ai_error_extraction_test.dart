// Pins the contract that provider-error parsing surfaces the
// deepest human-readable message from arbitrarily nested payloads.
// The motivating regression is the gpt-5.5 case below — codex JSONL
// puts the API's actual sentence inside a JSON-encoded string field,
// which the previous one-level descent surfaced verbatim and looked
// like gibberish to the user.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';

void main() {
  group('extractDeepestErrorMessage', () {
    test('returns a leaf string verbatim', () {
      expect(
        extractDeepestErrorMessageForTesting('something broke'),
        'something broke',
      );
    });

    test('returns null for empty / null input', () {
      expect(extractDeepestErrorMessageForTesting(null), isNull);
      expect(extractDeepestErrorMessageForTesting(''), isNull);
      expect(extractDeepestErrorMessageForTesting('   '), isNull);
    });

    test('descends through error.message', () {
      expect(
        extractDeepestErrorMessageForTesting({
          'error': {'message': 'inner'},
        }),
        'inner',
      );
    });

    test('descends through errors[0].message', () {
      expect(
        extractDeepestErrorMessageForTesting({
          'errors': [
            {'message': 'first'},
            {'message': 'second'},
          ],
        }),
        'first',
      );
    });

    test('descends through error.data.message', () {
      expect(
        extractDeepestErrorMessageForTesting({
          'error': {
            'data': {'message': 'opencode-shape inner'},
          },
        }),
        'opencode-shape inner',
      );
    });

    test('descends through cause.message', () {
      expect(
        extractDeepestErrorMessageForTesting({
          'cause': {'message': 'caused by'},
        }),
        'caused by',
      );
    });

    test('falls back to top-level message when no nesting', () {
      expect(
        extractDeepestErrorMessageForTesting({'type': 'error', 'message': 'flat'}),
        'flat',
      );
    });

    test('unwraps a JSON-encoded string at message', () {
      // The motivating regression: codex JSONL nests the human-readable
      // sentence inside a JSON-encoded string at value.message.
      expect(
        extractDeepestErrorMessageForTesting({
          'type': 'error',
          'message':
              '{"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The \'gpt-5.5\' model requires a newer version of Codex."}}',
        }),
        "The 'gpt-5.5' model requires a newer version of Codex.",
      );
    });

    test('error key takes precedence over flat message', () {
      // When both exist, the more-specific nested error wins.
      expect(
        extractDeepestErrorMessageForTesting({
          'message': 'wrapper',
          'error': {'message': 'real'},
        }),
        'real',
      );
    });

    test('survives malformed JSON-looking strings', () {
      // A string that LOOKS like JSON but doesn't decode shouldn't
      // crash — fall back to returning it verbatim.
      expect(
        extractDeepestErrorMessageForTesting('{not actually json'),
        '{not actually json',
      );
    });

    test('bounds recursion against pathological nesting', () {
      // 50 levels of nesting — the walker has a depth cap and must
      // not stack-overflow.
      dynamic node = {'message': 'leaf'};
      for (var i = 0; i < 50; i++) {
        node = {'error': node};
      }
      // Only requirement: doesn't throw. Result may be null at depth
      // overflow, which the parser callers handle by leaving the
      // errorMessage unset.
      extractDeepestErrorMessageForTesting(node);
    });
  });

  group('parseCodexJsonl error path', () {
    test('surfaces the leaf message for the gpt-5.5 case', () {
      const stream =
          '{"type":"thread.started","thread_id":"t1"}\n'
          '{"type":"turn.started"}\n'
          '{"type":"error","message":"{\\"type\\":\\"error\\",\\"status\\":400,\\"error\\":{\\"type\\":\\"invalid_request_error\\",\\"message\\":\\"The \'gpt-5.5\' model requires a newer version of Codex.\\"}}"}\n'
          '{"type":"turn.failed","error":{"message":"{\\"type\\":\\"error\\",\\"status\\":400,\\"error\\":{\\"type\\":\\"invalid_request_error\\",\\"message\\":\\"The \'gpt-5.5\' model requires a newer version of Codex.\\"}}"}}\n';
      final out = parseCodexJsonlForTesting(stream);
      expect(out, isNotNull);
      expect(out, startsWith('Codex error:'));
      expect(out, contains("The 'gpt-5.5' model requires"));
      // The wrapper JSON must NOT leak through.
      expect(out, isNot(contains('"type":"error"')));
      expect(out, isNot(contains('"status":400')));
    });

    test('passes through a plain non-JSON message', () {
      const stream =
          '{"type":"thread.started","thread_id":"t1"}\n'
          '{"type":"turn.failed","message":"rate limit exceeded"}\n';
      expect(
        parseCodexJsonlForTesting(stream),
        'Codex error: rate limit exceeded',
      );
    });

    test('returns the response when the run succeeds', () {
      const stream =
          '{"type":"thread.started","thread_id":"t1"}\n'
          '{"type":"item.completed","item":{"text":"hello world"}}\n';
      expect(parseCodexJsonlForTesting(stream), 'hello world');
    });
  });

  group('parseOpenCodeJsonl error path', () {
    test('extracts error.data.message (provider-data shape)', () {
      const stream =
          '{"type":"error","error":{"data":{"message":"Provider model not found"}}}\n';
      final out = parseOpenCodeJsonlForTesting(stream);
      expect(out, isNotNull);
      expect(out, contains('Provider model not found'));
    });

    test('extracts a JSON-encoded message string', () {
      const stream =
          '{"type":"error","message":"{\\"error\\":{\\"message\\":\\"upstream rejected\\"}}"}\n';
      final out = parseOpenCodeJsonlForTesting(stream);
      expect(out, isNotNull);
      expect(out, contains('upstream rejected'));
    });
  });
}
