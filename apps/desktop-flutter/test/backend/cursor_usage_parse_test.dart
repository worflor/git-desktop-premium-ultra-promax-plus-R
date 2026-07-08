// cursor-agent reports per-request usage in the SAME JSON we parse for the
// answer. The envelope is snake_case (is_error, duration_ms, request_id) but
// we have no fixture pinning the nested `usage` object's casing — so the
// parser reads each field under both snake_case and camelCase. These tests
// pin that tolerance: whichever casing cursor emits, the surfaced telemetry
// carries the real numbers instead of silently zeroing.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';

void main() {
  group('parseCursorUsage casing tolerance', () {
    test('reads a snake_case usage sub-object', () {
      final usage = parseCursorUsageForTesting({
        'is_error': false,
        'result': 'ok',
        'duration_ms': 4200,
        'request_id': 'req_snake',
        'usage': {
          'input_tokens': 1200,
          'output_tokens': 340,
          'cache_read_tokens': 900,
          'cache_write_tokens': 50,
        },
      });
      expect(usage.inputTokens, 1200);
      expect(usage.outputTokens, 340);
      expect(usage.cacheReadTokens, 900);
      expect(usage.cacheWriteTokens, 50);
      expect(usage.duration, const Duration(milliseconds: 4200));
      expect(usage.requestId, 'req_snake');
    });

    test('reads a camelCase usage sub-object', () {
      final usage = parseCursorUsageForTesting({
        'is_error': false,
        'result': 'ok',
        'durationMs': 1500,
        'requestId': 'req_camel',
        'usage': {
          'inputTokens': 42,
          'outputTokens': 7,
          'cacheReadTokens': 3,
          'cacheWriteTokens': 1,
        },
      });
      expect(usage.inputTokens, 42);
      expect(usage.outputTokens, 7);
      expect(usage.cacheReadTokens, 3);
      expect(usage.cacheWriteTokens, 1);
      expect(usage.duration, const Duration(milliseconds: 1500));
      expect(usage.requestId, 'req_camel');
    });

    test('missing usage object degrades to zero tokens, null extras', () {
      final usage = parseCursorUsageForTesting({
        'is_error': false,
        'result': 'ok',
      });
      expect(usage.inputTokens, 0);
      expect(usage.outputTokens, 0);
      expect(usage.cacheReadTokens, isNull);
      expect(usage.cacheWriteTokens, isNull);
      expect(usage.duration, isNull);
      expect(usage.requestId, isNull);
    });

    test('tolerates num-typed token counts', () {
      final usage = parseCursorUsageForTesting({
        'usage': {'input_tokens': 10.0, 'output_tokens': 2.0},
      });
      expect(usage.inputTokens, 10);
      expect(usage.outputTokens, 2);
    });
  });
}
