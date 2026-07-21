// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// report_attribution is the single formatter for the "which model produced
// this" line shared by every LLM-output clipboard export. These tests pin
// the partial-identity edge cases the comments promise — provider-only,
// model-only, and the fully-blank fallback — so a snapshot with a missing
// half never renders a dangling ` / ` or a bare `Model:` header.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/report_attribution.dart';

void main() {
  group('modelDescriptor', () {
    test('joins provider and model with a slash', () {
      expect(modelDescriptor('anthropic', 'claude-opus-4-8'),
          'anthropic / claude-opus-4-8');
    });

    test('renders provider alone when the model is blank', () {
      expect(modelDescriptor('cursor', ''), 'cursor');
      expect(modelDescriptor('cursor', '   '), 'cursor');
    });

    test('renders model alone when the provider is blank', () {
      expect(modelDescriptor('', 'gpt-5.5-high'), 'gpt-5.5-high');
    });

    test('is empty only when both halves are blank', () {
      expect(modelDescriptor('', ''), '');
      expect(modelDescriptor('  ', '\t'), '');
    });

    test('trims surrounding whitespace on each half', () {
      expect(modelDescriptor('  anthropic ', ' claude '), 'anthropic / claude');
    });
  });

  group('modelAttributionLine', () {
    test('prefixes the descriptor with the Model label', () {
      expect(modelAttributionLine('anthropic', 'claude'),
          'Model: anthropic / claude');
    });

    test('is empty when no identity was recorded, so callers emit no header',
        () {
      expect(modelAttributionLine('', ''), '');
    });

    test('surfaces a partial identity rather than a bare header', () {
      expect(modelAttributionLine('cursor', ''), 'Model: cursor');
    });
  });
}
