import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/cursor_effort.dart';

// A representative slice of a real `cursor-agent models` catalog, chosen to
// exercise every parsing quirk: both suffix orderings, `-max-<effort>` bases,
// `extra-high`, `none`, bare (no-effort) ids, fast pairs, and thinking axes.
const _catalog = <String>[
  'auto',
  'composer-2.5',
  'composer-2.5-fast',
  'grok-4.3',
  // gpt-5.5: none..extra-high, one fast pair.
  'gpt-5.5-none',
  'gpt-5.5-low',
  'gpt-5.5-medium',
  'gpt-5.5-high',
  'gpt-5.5-high-fast',
  'gpt-5.5-extra-high',
  // opus-4-8 plain: low..max.
  'claude-opus-4-8-low',
  'claude-opus-4-8-medium',
  'claude-opus-4-8-high',
  'claude-opus-4-8-xhigh',
  'claude-opus-4-8-max',
  // opus-4-8 thinking: separate family (…-thinking-<effort> ordering).
  'claude-opus-4-8-thinking-low',
  'claude-opus-4-8-thinking-high',
  'claude-opus-4-8-thinking-high-fast',
  'claude-opus-4-8-thinking-max',
  // base literally contains the word "max".
  'gpt-5.1-codex-max-low',
  'gpt-5.1-codex-max-medium',
  'gpt-5.1-codex-max-high',
  'gpt-5.1-codex-max-xhigh',
  // <effort>-thinking ordering (thinking trails the effort).
  'claude-4.6-opus-high',
  'claude-4.6-opus-max',
  'claude-4.6-opus-high-thinking',
  'claude-4.6-opus-max-thinking',
  // bare thinking, no effort word.
  'claude-4.5-sonnet',
  'claude-4.5-sonnet-thinking',
  // two-level family with a gap (no low/medium).
  'glm-5.2-high',
  'glm-5.2-max',
];

void main() {
  group('parseCursorModelId', () {
    test('bare id → base, no thinking, medium rank, not fast', () {
      final p = parseCursorModelId('grok-4.3');
      expect(p.base, 'grok-4.3');
      expect(p.thinking, isFalse);
      expect(p.rank, 2);
      expect(p.fast, isFalse);
    });

    test('effort suffix', () {
      final p = parseCursorModelId('gpt-5.5-high');
      expect(p.base, 'gpt-5.5');
      expect(p.rank, cursorEffortRank['high']);
      expect(p.fast, isFalse);
    });

    test('extra-high folds to xhigh rank', () {
      final p = parseCursorModelId('gpt-5.5-extra-high');
      expect(p.base, 'gpt-5.5');
      expect(p.rank, cursorEffortRank['xhigh']);
    });

    test('none is the lowest rank', () {
      expect(parseCursorModelId('gpt-5.5-none').rank, 0);
    });

    test('thinking BEFORE effort (…-thinking-high)', () {
      final p = parseCursorModelId('claude-opus-4-8-thinking-high');
      expect(p.base, 'claude-opus-4-8');
      expect(p.thinking, isTrue);
      expect(p.rank, cursorEffortRank['high']);
    });

    test('thinking AFTER effort (…-high-thinking)', () {
      final p = parseCursorModelId('claude-4.6-opus-high-thinking');
      expect(p.base, 'claude-4.6-opus');
      expect(p.thinking, isTrue);
      expect(p.rank, cursorEffortRank['high']);
    });

    test('bare thinking, no effort word', () {
      final p = parseCursorModelId('claude-4.5-sonnet-thinking');
      expect(p.base, 'claude-4.5-sonnet');
      expect(p.thinking, isTrue);
      expect(p.rank, 2);
    });

    test('base that ends in an effort word keeps it in the base', () {
      final p = parseCursorModelId('gpt-5.1-codex-max-low');
      expect(p.base, 'gpt-5.1-codex-max');
      expect(p.rank, cursorEffortRank['low']);
    });

    test('fast is stripped and flagged', () {
      final p = parseCursorModelId('claude-opus-4-8-thinking-high-fast');
      expect(p.base, 'claude-opus-4-8');
      expect(p.thinking, isTrue);
      expect(p.rank, cursorEffortRank['high']);
      expect(p.fast, isTrue);
    });
  });

  group('families and capability marking', () {
    final families = buildCursorFamilies(_catalog);

    test('thinking splits families', () {
      final effort = cursorEffortCapableIds(_catalog, families);
      // Plain opus-4-8 spans 5 ranks → slider.
      expect(effort, contains('claude-opus-4-8-high'));
      // Thinking opus-4-8 is its own family, also multi-rank → slider.
      expect(effort, contains('claude-opus-4-8-thinking-high'));
    });

    test('single-variant models get no slider', () {
      final effort = cursorEffortCapableIds(_catalog, families);
      expect(effort, isNot(contains('auto')));
      expect(effort, isNot(contains('grok-4.3')));
      expect(effort, isNot(contains('composer-2.5')));
      // 4.5-sonnet has only one rank per (thinking) family.
      expect(effort, isNot(contains('claude-4.5-sonnet')));
      expect(effort, isNot(contains('claude-4.5-sonnet-thinking')));
    });

    test('fast toggle only on the plain half of a pair', () {
      final fast = cursorFastCapableIds(_catalog, families);
      expect(fast, contains('gpt-5.5-high')); // has -fast sibling
      expect(fast, isNot(contains('gpt-5.5-high-fast'))); // already fast
      expect(fast, contains('composer-2.5'));
      expect(fast, isNot(contains('gpt-5.5-low'))); // no -fast sibling
    });
  });

  group('resolveCursorModel', () {
    final families = buildCursorFamilies(_catalog);
    String r(String id, {String? effort, bool fast = false}) =>
        resolveCursorModel(id, families, effort: effort, fast: fast);

    test('slides effort within a family', () {
      expect(r('gpt-5.5-medium', effort: 'high'), 'gpt-5.5-high');
      expect(r('gpt-5.5-medium', effort: 'low'), 'gpt-5.5-low');
      expect(r('claude-opus-4-8-high', effort: 'max'), 'claude-opus-4-8-max');
    });

    test('max clamps to extra-high when the family tops out there', () {
      expect(r('gpt-5.5-medium', effort: 'max'), 'gpt-5.5-extra-high');
    });

    test('stays inside the thinking family', () {
      expect(r('claude-opus-4-8-thinking-low', effort: 'max'),
          'claude-opus-4-8-thinking-max');
    });

    test('snaps to nearest existing level across a gap', () {
      // glm-5.2 only has high(3) and max(5); low(1) snaps to high(3).
      expect(r('glm-5.2-high', effort: 'low'), 'glm-5.2-high');
    });

    test('base-with-effort-word routes correctly', () {
      expect(r('gpt-5.1-codex-max-low', effort: 'high'),
          'gpt-5.1-codex-max-high');
    });

    test('fast toggle swaps to the -fast sibling and back', () {
      expect(r('gpt-5.5-high', fast: true), 'gpt-5.5-high-fast');
    });

    test('no-variant models are returned verbatim', () {
      expect(r('auto', effort: 'high'), 'auto');
      expect(r('grok-4.3', effort: 'max'), 'grok-4.3');
      expect(r('claude-4.6-opus-high'), 'claude-4.6-opus-high');
    });

    test('unknown id (not in catalog) falls back to itself', () {
      expect(r('totally-made-up-9', effort: 'high'), 'totally-made-up-9');
    });

    test('empty family map never fabricates an id', () {
      expect(resolveCursorModel('gpt-5.5-medium', const {}, effort: 'max'),
          'gpt-5.5-medium');
    });
  });
}
