// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';

// Fixtures are trimmed-but-real envelopes captured 2026-07 from live
// `codex exec --json`, `claude --print --output-format json`, `opencode run
// --format json`, and `cursor-agent -p --output-format json` runs. They pin
// each provider's usage schema so a silent field rename shows up here.
void main() {
  group('codex usage (turn.completed)', () {
    const stdout = '''
{"type":"thread.started","thread_id":"t1"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"PONG"}}
{"type":"turn.completed","usage":{"input_tokens":26069,"cached_input_tokens":6528,"output_tokens":25,"reasoning_output_tokens":17}}
''';

    test('text still extracts', () {
      expect(parseCodexJsonlForTesting(stdout), 'PONG');
    });

    test('tokens, cache-read and reasoning are pulled', () {
      final u = codexUsageForTesting(stdout);
      expect(u.inputTokens, 26069);
      expect(u.outputTokens, 25);
      expect(u.cacheReadTokens, 6528);
      expect(u.reasoningTokens, 17);
      expect(u.hasExtras, isTrue);
    });
  });

  group('claude usage (result object)', () {
    const stdout =
        '{"type":"result","is_error":false,"duration_ms":3242,"result":"PONG",'
        '"session_id":"sess-abc","total_cost_usd":0.052572,'
        '"usage":{"input_tokens":3172,"cache_creation_input_tokens":2583,'
        '"cache_read_input_tokens":20314,"output_tokens":5}}';

    test('cost, duration, cache read/write and session id are pulled', () {
      final u = claudeUsageForTesting(stdout);
      expect(u.inputTokens, 3172);
      expect(u.outputTokens, 5);
      expect(u.cacheReadTokens, 20314);
      expect(u.cacheWriteTokens, 2583);
      expect(u.costUsd, closeTo(0.052572, 1e-9));
      expect(u.duration, const Duration(milliseconds: 3242));
      expect(u.requestId, 'sess-abc');
    });
  });

  group('opencode usage (step_finish)', () {
    const stdout = '''
{"type":"step_start"}
{"type":"text","part":{"text":"PONG"}}
{"type":"step_finish","part":{"tokens":{"total":10866,"input":10849,"output":3,"reasoning":14,"cache":{"write":0,"read":0}},"cost":0}}
''';

    test('text still extracts', () {
      expect(parseOpenCodeJsonlForTesting(stdout), 'PONG');
    });

    test('input/output/reasoning are pulled; zero cost stays null', () {
      final u = openCodeUsageForTesting(stdout);
      expect(u.inputTokens, 10849);
      expect(u.outputTokens, 3);
      expect(u.reasoningTokens, 14);
      expect(u.cacheReadTokens, 0);
      expect(u.costUsd, isNull); // cost 0 on a free pool -> no dollar figure
    });

    test('sums across multiple step_finish events', () {
      const twoSteps = '''
{"type":"text","part":{"text":"A"}}
{"type":"step_finish","part":{"tokens":{"input":100,"output":10,"cache":{"read":0,"write":0}},"cost":0.01}}
{"type":"text","part":{"text":"B"}}
{"type":"step_finish","part":{"tokens":{"input":50,"output":5,"cache":{"read":0,"write":0}},"cost":0.02}}
''';
      final u = openCodeUsageForTesting(twoSteps);
      expect(u.inputTokens, 150);
      expect(u.outputTokens, 15);
      expect(u.costUsd, closeTo(0.03, 1e-9));
    });
  });

  group('cursor usage (single object)', () {
    const stdout =
        '{"type":"result","is_error":false,"duration_ms":4602,"result":"PONG",'
        '"request_id":"req-1","usage":{"inputTokens":11194,"outputTokens":46,'
        '"cacheReadTokens":491,"cacheWriteTokens":0}}';

    test('camelCase tokens, duration and request id are pulled', () {
      final u = cursorUsageForTesting(stdout);
      expect(u.inputTokens, 11194);
      expect(u.outputTokens, 46);
      expect(u.cacheReadTokens, 491);
      expect(u.duration, const Duration(milliseconds: 4602));
      expect(u.requestId, 'req-1');
    });
  });

  group('no-usage inputs stay empty', () {
    test('plain / unparseable stdout yields empty usage', () {
      expect(codexUsageForTesting('not json').isEmpty, isTrue);
      expect(openCodeUsageForTesting('').isEmpty, isTrue);
      expect(claudeUsageForTesting('{}').isEmpty, isTrue);
    });
  });
}
