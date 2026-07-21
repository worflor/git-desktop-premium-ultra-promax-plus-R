// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';

void main() {
  group('AiUsage classification', () {
    test('empty has no tokens, no extras', () {
      expect(AiUsage.empty.isEmpty, isTrue);
      expect(AiUsage.empty.hasTokens, isFalse);
      expect(AiUsage.empty.hasExtras, isFalse);
    });

    test('tokens alone are not "extras"', () {
      const u = AiUsage(inputTokens: 100, outputTokens: 20);
      expect(u.hasTokens, isTrue);
      expect(u.hasExtras, isFalse); // inline caption already shows these
      expect(u.isEmpty, isFalse);
    });

    test('cache/duration/requestId count as extras', () {
      expect(const AiUsage(cacheReadTokens: 5).hasExtras, isTrue);
      expect(const AiUsage(cacheWriteTokens: 5).hasExtras, isTrue);
      expect(const AiUsage(duration: Duration(seconds: 1)).hasExtras, isTrue);
      expect(const AiUsage(requestId: 'abc').hasExtras, isTrue);
      expect(const AiUsage(resolvedModel: 'gpt').hasExtras, isTrue);
      expect(const AiUsage(costUsd: 0.01).hasExtras, isTrue);
    });

    test('zero cache tokens are not extras', () {
      expect(const AiUsage(cacheReadTokens: 0, cacheWriteTokens: 0).hasExtras,
          isFalse);
    });
  });

  group('AiUsage aggregation (draft + verify)', () {
    test('token counts and duration add', () {
      const a = AiUsage(
        inputTokens: 100,
        outputTokens: 20,
        cacheReadTokens: 4,
        duration: Duration(milliseconds: 500),
      );
      const b = AiUsage(
        inputTokens: 50,
        outputTokens: 10,
        cacheReadTokens: 1,
        duration: Duration(milliseconds: 250),
      );
      final sum = a + b;
      expect(sum.inputTokens, 150);
      expect(sum.outputTokens, 30);
      expect(sum.cacheReadTokens, 5);
      expect(sum.duration, const Duration(milliseconds: 750));
    });

    test('null + value keeps the value (one leg reports, other does not)', () {
      const a = AiUsage(inputTokens: 100, outputTokens: 20);
      const b = AiUsage(
        inputTokens: 50,
        outputTokens: 10,
        duration: Duration(seconds: 2),
        cacheWriteTokens: 7,
      );
      final sum = a + b;
      expect(sum.duration, const Duration(seconds: 2));
      expect(sum.cacheWriteTokens, 7);
    });

    test('identity extras: later non-null wins', () {
      const a = AiUsage(requestId: 'first', resolvedModel: 'm1');
      const b = AiUsage(requestId: 'second');
      final sum = a + b;
      expect(sum.requestId, 'second'); // later leg
      expect(sum.resolvedModel, 'm1'); // only the earlier leg had it
    });

    test('empty is an identity for token counts', () {
      const u = AiUsage(inputTokens: 42, outputTokens: 7);
      expect((u + AiUsage.empty).inputTokens, 42);
      expect((AiUsage.empty + u).outputTokens, 7);
    });
  });
}
