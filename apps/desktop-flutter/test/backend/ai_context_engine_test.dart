// Tests for the AiContextEngine allocator. Pin the math:
//   • Variable producers softmax-normalise across their declared
//     urgencies, sharing the post-fixed budget.
//   • Fixed producers reserve exactly what they ask for before the
//     variable pool is computed.
//   • Producers always get to produce — even with zero allocation,
//     they're called (so they can emit a static header etc.).
//
// These behaviours are foundational for any caller that composes
// producers (review, commit message, Muse, future flows). Locking them
// here means a refactor that breaks budget accounting fails loud.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai_context_engine.dart';

class _StaticUrgencyProducer extends AiContextProducer {
  _StaticUrgencyProducer(
    this.id_,
    this.urgency_,
    this.fixed_, {
    this.order_ = 100,
    this.body_,
    this.tag_,
  });
  final String id_;
  final double? urgency_;
  final int fixed_;
  final int order_;
  final String? body_;
  final String? tag_;
  final List<int> received = [];

  @override
  String get id => id_;
  @override
  int get order => order_;
  @override
  String get wrapperTag => tag_ ?? id_;
  @override
  double? urgency(AiContextRequest req) => urgency_;
  @override
  int fixedRequest(AiContextRequest req) => fixed_;
  @override
  Future<AiContextSection> produce(AiContextRequest req, int budgetChars) async {
    received.add(budgetChars);
    return AiContextSection(id: id, body: body_ ?? 'b' * budgetChars);
  }
}

void main() {
  group('AiContextEngine allocation', () {
    final req = const AiContextRequest(
      repositoryPath: '/r',
      diffText: '',
    );

    test('two equal urgencies split the variable pool evenly', () async {
      final a = _StaticUrgencyProducer('a', 1.0, 0);
      final b = _StaticUrgencyProducer('b', 1.0, 0);
      final out = await AiContextEngine([a, b]).assemble(req, 1000);
      expect(a.received.single, 500);
      expect(b.received.single, 500);
      expect(out['a']!.body.length, 500);
      expect(out['b']!.body.length, 500);
    });

    test('softmax-normalised urgencies — 3:1 ratio yields 75/25 split',
        () async {
      final a = _StaticUrgencyProducer('a', 3.0, 0);
      final b = _StaticUrgencyProducer('b', 1.0, 0);
      await AiContextEngine([a, b]).assemble(req, 1000);
      expect(a.received.single, 750);
      expect(b.received.single, 250);
    });

    test('fixed requests are reserved before urgencies are normalised',
        () async {
      // Fixed asks for 200; remaining 800 splits 50/50 between two
      // equal-urgency variable producers.
      final fixed = _StaticUrgencyProducer('fixed', null, 200);
      final v1 = _StaticUrgencyProducer('v1', 1.0, 0);
      final v2 = _StaticUrgencyProducer('v2', 1.0, 0);
      await AiContextEngine([fixed, v1, v2]).assemble(req, 1000);
      expect(fixed.received.single, 200);
      expect(v1.received.single, 400);
      expect(v2.received.single, 400);
    });

    test('three-section closed form: D·y + D·(1−y) + coh = 1', () async {
      // Reproduce the original allocation identity. With coh=0.4 and
      // y=0.6:
      //   relevance   = (1-0.4) * 0.6 = 0.36
      //   metadata    = (1-0.4) * 0.4 = 0.24
      //   fileContext = 0.4
      // Sum = 1.0 exactly, so engine softmax leaves the values
      // un-modified — each producer gets exactly its urgency-share.
      const coh = 0.4;
      const y = 0.6;
      final relevance = _StaticUrgencyProducer('rel', (1 - coh) * y, 0);
      final metadata = _StaticUrgencyProducer('meta', (1 - coh) * (1 - y), 0);
      final fileContext = _StaticUrgencyProducer('file', coh, 0);
      await AiContextEngine([relevance, metadata, fileContext])
          .assemble(req, 10000);
      expect(relevance.received.single, 3600);
      expect(metadata.received.single, 2400);
      expect(fileContext.received.single, 4000);
    });

    test('zero urgency producer still gets called (with zero budget)',
        () async {
      final live = _StaticUrgencyProducer('live', 1.0, 0);
      final silent = _StaticUrgencyProducer('silent', 0.0, 0);
      await AiContextEngine([live, silent]).assemble(req, 1000);
      expect(live.received.single, 1000);
      expect(silent.received.single, 0);
    });

    test('all-zero urgencies leave every producer at zero (no NaN)',
        () async {
      final a = _StaticUrgencyProducer('a', 0.0, 0);
      final b = _StaticUrgencyProducer('b', 0.0, 0);
      final out = await AiContextEngine([a, b]).assemble(req, 1000);
      expect(a.received.single, 0);
      expect(b.received.single, 0);
      // Producers still ran and returned sections (empty).
      expect(out.keys, containsAll(<String>['a', 'b']));
    });

    test('fixed requests exceeding total → variable pool clamps to 0',
        () async {
      final fixed = _StaticUrgencyProducer('fixed', null, 2000);
      final variable = _StaticUrgencyProducer('var', 1.0, 0);
      await AiContextEngine([fixed, variable]).assemble(req, 1000);
      expect(fixed.received.single, 2000);
      // Variable pool went negative → clamped to 0.
      expect(variable.received.single, 0);
    });

    test('largest-remainder allocation: total preserved exactly', () async {
      // 1000 chars, 3 equal urgencies. Naive `(pool * urg / sum).round()`
      // gives 333+333+333 = 999 (1 lost). Hamilton's largest-remainder
      // method puts the leftover char on the producer with the largest
      // fractional remainder (or alphabetical tiebreak). Sum must equal
      // pool exactly — the budget invariant.
      final a = _StaticUrgencyProducer('a', 1.0, 0);
      final b = _StaticUrgencyProducer('b', 1.0, 0);
      final c = _StaticUrgencyProducer('c', 1.0, 0);
      await AiContextEngine([a, b, c]).assemble(req, 1000);
      final total = a.received.single + b.received.single + c.received.single;
      expect(total, 1000);
      // Each producer gets either floor(1000/3)=333 or floor+1=334.
      for (final got in [a.received.single, b.received.single, c.received.single]) {
        expect(got, anyOf(333, 334));
      }
    });

    test('largest-remainder: 100 chars across 3 producers stays exact',
        () async {
      // Stress with a smaller pool where rounding error is more visible.
      final a = _StaticUrgencyProducer('a', 1.0, 0);
      final b = _StaticUrgencyProducer('b', 1.0, 0);
      final c = _StaticUrgencyProducer('c', 1.0, 0);
      await AiContextEngine([a, b, c]).assemble(req, 100);
      expect(
        a.received.single + b.received.single + c.received.single,
        100,
      );
    });

    test('largest-remainder: skewed urgencies preserved exactly', () async {
      // 1000 chars, urgencies 0.7/0.2/0.1. Naive: 700/200/100 = 1000 ok.
      // 1003 chars: 0.7×1003=702.1, 0.2×1003=200.6, 0.1×1003=100.3
      // Naive .round() gives 702+201+100=1003. Largest-remainder must
      // also give 1003.
      final a = _StaticUrgencyProducer('a', 0.7, 0);
      final b = _StaticUrgencyProducer('b', 0.2, 0);
      final c = _StaticUrgencyProducer('c', 0.1, 0);
      await AiContextEngine([a, b, c]).assemble(req, 1003);
      expect(
        a.received.single + b.received.single + c.received.single,
        1003,
      );
    });

    test('assembleAndStitch wraps each section in its declared tag', () async {
      final a = _StaticUrgencyProducer('a', 1.0, 0, body_: 'AAA', tag_: 'alpha');
      final b = _StaticUrgencyProducer('b', 1.0, 0, body_: 'BBB', tag_: 'beta');
      final result =
          await AiContextEngine([a, b]).assembleAndStitch(req, 1000);
      expect(result.body, contains('<alpha>\nAAA</alpha>'));
      expect(result.body, contains('<beta>\nBBB</beta>'));
    });

    test('assembleAndStitch emits sections in producer-declared order',
        () async {
      // Register out-of-order; expect output sorted by `order`.
      final last = _StaticUrgencyProducer('x', 1.0, 0,
          body_: 'X', order_: 90, tag_: 'x');
      final first = _StaticUrgencyProducer('y', 1.0, 0,
          body_: 'Y', order_: 10, tag_: 'y');
      final mid = _StaticUrgencyProducer('z', 1.0, 0,
          body_: 'Z', order_: 50, tag_: 'z');
      final result = await AiContextEngine([last, first, mid])
          .assembleAndStitch(req, 1000);
      final iY = result.body.indexOf('<y>');
      final iZ = result.body.indexOf('<z>');
      final iX = result.body.indexOf('<x>');
      expect(iY < iZ, isTrue, reason: 'y (order=10) before z (order=50)');
      expect(iZ < iX, isTrue, reason: 'z (order=50) before x (order=90)');
    });

    test('assembleAndStitch silently drops empty-body producers', () async {
      final live = _StaticUrgencyProducer('live', 1.0, 0,
          body_: 'kept', tag_: 'live');
      final empty = _StaticUrgencyProducer('empty', 1.0, 0,
          body_: '', tag_: 'empty');
      final result =
          await AiContextEngine([live, empty]).assembleAndStitch(req, 1000);
      expect(result.body, contains('<live>'));
      expect(result.body, isNot(contains('<empty>')));
      // Empty producer still ran (sections map records it).
      expect(result.sections.containsKey('empty'), isTrue);
    });

    test('metadataOfType returns checked cast or null', () async {
      // Type-safe alternative to `as T?` — a producer that changes its
      // metadata type silently breaks `as`-based callers; this returns
      // null instead, which callers can react to.
      final s1 = const AiContextSection(id: 'x', body: '', metadata: 42);
      expect(s1.metadataOfType<int>(), 42);
      expect(s1.metadataOfType<String>(), isNull);
      final s2 = const AiContextSection(id: 'x', body: '');
      expect(s2.metadataOfType<int>(), isNull);
    });

    test('largest-remainder: NaN/Infinity urgencies are ignored', () async {
      // urgencySum filter keeps `u.isFinite && u > 0`. Bad values
      // shouldn't crash or skew allocation.
      final ok = _StaticUrgencyProducer('ok', 1.0, 0);
      final nanP = _StaticUrgencyProducer('nan', double.nan, 0);
      final infP = _StaticUrgencyProducer('inf', double.infinity, 0);
      final negP = _StaticUrgencyProducer('neg', -1.0, 0);
      await AiContextEngine([ok, nanP, infP, negP]).assemble(req, 1000);
      // Only 'ok' competes; gets full pool.
      expect(ok.received.single, 1000);
      expect(nanP.received.single, 0);
      expect(infP.received.single, 0);
      expect(negP.received.single, 0);
    });
  });
}
