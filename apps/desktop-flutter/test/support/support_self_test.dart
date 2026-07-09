// Self-test for the property-testing foundation itself (prop.dart +
// gen.dart). Other agents build on top of these two files, so this suite
// exists to catch a broken Rng, a forAll that swallows errors, or an
// oracle that is subtly wrong before anyone builds real engine tests on
// top of them.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'gen.dart';
import 'prop.dart';

void main() {
  group('Rng determinism', () {
    test('same seed -> identical sequence', () {
      final a = Rng(12345);
      final b = Rng(12345);
      for (var i = 0; i < 50; i++) {
        expect(a.nextInt(1000000), b.nextInt(1000000));
      }
      final c = Rng(12345);
      final d = Rng(12345);
      for (var i = 0; i < 20; i++) {
        expect(c.nextDouble(), d.nextDouble());
        expect(c.nextBool(), d.nextBool());
      }
    });

    test('different seed -> diverges', () {
      final a = Rng(1);
      final b = Rng(2);
      final seqA = List<int>.generate(20, (_) => a.nextInt(1 << 30));
      final seqB = List<int>.generate(20, (_) => b.nextInt(1 << 30));
      expect(seqA, isNot(equals(seqB)));
    });

    test('intBetween stays in bounds and is deterministic', () {
      final rng = Rng(99);
      for (var i = 0; i < 500; i++) {
        final v = rng.intBetween(-5, 5);
        expect(v, inInclusiveRange(-5, 5));
      }
      final r1 = Rng(7);
      final r2 = Rng(7);
      expect(r1.intBetween(0, 100), r2.intBetween(0, 100));
    });

    test('nextDouble stays in [0, 1)', () {
      final rng = Rng(42);
      for (var i = 0; i < 500; i++) {
        final v = rng.nextDouble();
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThan(1.0));
      }
    });

    test('pick/sample respect bounds', () {
      final rng = Rng(3);
      final items = [1, 2, 3, 4, 5];
      for (var i = 0; i < 100; i++) {
        expect(items, contains(rng.pick(items)));
      }
      final sampled = rng.sample(items, 3);
      expect(sampled.length, 3);
      expect(sampled.toSet().length, 3); // distinct positions drawn
      for (final v in sampled) {
        expect(items, contains(v));
      }
    });

    test('split() produces independent, deterministic substreams', () {
      final r1 = Rng(555);
      final sub1 = r1.split();
      final r2 = Rng(555);
      final sub2 = r2.split();
      // Same seed, same point of split -> identical substream.
      for (var i = 0; i < 20; i++) {
        expect(sub1.nextInt(1 << 30), sub2.nextInt(1 << 30));
      }
    });
  });

  group('forAll reproduction/reporting', () {
    test('never swallows a failure, and prints a seed+index repro line', () {
      final prints = <String>[];
      const failingSeed = 0xC0FFEE;
      runZoned(
        () {
          expect(
            () => forAll<int>(
              genInt(min: 0, max: 10),
              check: (v) => throw StateError('deliberate failure: $v'),
              count: 5,
              seed: failingSeed,
              describe: 'self-test deliberate failure',
            ),
            throwsA(isA<StateError>()),
          );
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => prints.add(line),
        ),
      );
      expect(prints, isNotEmpty);
      final joined = prints.join('\n');
      expect(joined, contains('self-test deliberate failure'));
      expect(joined, contains('0x${failingSeed.toRadixString(16)}'));
      expect(joined, contains('index='));
    });

    test('shrink greedily reduces to a smaller reported failure', () {
      final prints = <String>[];
      runZoned(
        () {
          expect(
            () => forAll<int>(
              (rng) => 100, // constant generator; only value ever produced
              check: (v) {
                if (v > 3) throw StateError('too big: $v');
              },
              count: 1,
              seed: 1,
              describe: 'shrink test',
              shrink: (v) => v > 3 ? v - 1 : v,
            ),
            throwsA(isA<StateError>()),
          );
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => prints.add(line),
        ),
      );
      final joined = prints.join('\n');
      // Shrinks 100 -> 99 -> ... down to 4, the *smallest value that still
      // fails* (3 does not fail, so 4 is what gets reported).
      expect(joined, contains('value=4'));
    });

    test('forAll passes silently when check never throws', () {
      expect(
        () => forAll<int>(
          genInt(min: -10, max: 10),
          check: (v) => expect(v, inInclusiveRange(-10, 10)),
          count: 50,
          seed: 1,
        ),
        returnsNormally,
      );
    });
  });

  group('fuzzScale', () {
    test('defaults to 1', () {
      expect(fuzzScale(), greaterThanOrEqualTo(1));
    });
  });

  group('connectedComponents oracle', () {
    test('a tree is always exactly 1 component', () {
      forAll<TestGraph>(
        genTree(maxNodes: 30),
        check: (g) => expect(connectedComponents(g), 1),
        count: 100,
        seed: 10,
        describe: 'tree -> 1 component',
      );
    });

    test('genDisconnectedGraph always has >= 2 components', () {
      forAll<TestGraph>(
        genDisconnectedGraph(maxNodes: 30, minComponents: 2),
        check: (g) => expect(connectedComponents(g), greaterThanOrEqualTo(2)),
        count: 100,
        seed: 11,
        describe: 'disconnected -> >= 2 components',
      );
    });

    test('genConnectedGraph is always exactly 1 component', () {
      forAll<TestGraph>(
        genConnectedGraph(maxNodes: 30),
        check: (g) => expect(connectedComponents(g), 1),
        count: 100,
        seed: 12,
        describe: 'connected -> 1 component',
      );
    });

    test('n isolated nodes with no edges -> n components', () {
      for (final n in [1, 2, 5, 17]) {
        final g = TestGraph(n, const []);
        expect(connectedComponents(g), n);
      }
    });

    test('hand-built two-triangle graph -> 2 components', () {
      // Triangle {0,1,2} and triangle {3,4,5}, no edges between them.
      const g = TestGraph(6, [
        (0, 1, 1.0),
        (1, 2, 1.0),
        (0, 2, 1.0),
        (3, 4, 1.0),
        (4, 5, 1.0),
        (3, 5, 1.0),
      ]);
      expect(connectedComponents(g), 2);
    });
  });

  group('denseLaplacian oracle', () {
    test('every row sums to ~0 (Laplacian property)', () {
      forAll<TestGraph>(
        genGraph(maxNodes: 25),
        check: (g) {
          final laplacian = denseLaplacian(g);
          for (final row in laplacian) {
            final sum = row.fold(0.0, (acc, v) => acc + v);
            expect(sum, closeTo(0.0, 1e-9));
          }
        },
        count: 150,
        seed: 20,
        describe: 'Laplacian row sums to 0',
      );
    });

    test('diagonal equals weighted degree, matches denseAdjacency', () {
      forAll<TestGraph>(
        genConnectedGraph(maxNodes: 20),
        check: (g) {
          final adjacency = denseAdjacency(g);
          final laplacian = denseLaplacian(g);
          for (var i = 0; i < g.n; i++) {
            final degree = adjacency[i].fold(0.0, (acc, v) => acc + v);
            expect(laplacian[i][i], closeTo(degree, 1e-9));
          }
        },
        count: 100,
        seed: 21,
      );
    });
  });

  group('genMultilineText coverage', () {
    test('sometimes has no trailing newline, sometimes contains CRLF', () {
      var sawNoTrailingNewline = false;
      var sawCrLf = false;
      final rng = Rng(2026);
      final gen = genMultilineText(maxLines: 8);
      for (var i = 0; i < 500; i++) {
        final text = gen(rng);
        if (text.isEmpty || !text.endsWith('\n')) {
          sawNoTrailingNewline = true;
        }
        if (text.contains('\r\n')) {
          sawCrLf = true;
        }
        if (sawNoTrailingNewline && sawCrLf) break;
      }
      expect(
        sawNoTrailingNewline,
        isTrue,
        reason: 'expected at least one sample with no trailing newline',
      );
      expect(
        sawCrLf,
        isTrue,
        reason: 'expected at least one sample containing CRLF',
      );
    });
  });

  group('runGen', () {
    test('is deterministic for a fixed seed', () {
      final a = runGen(genInt(), 5);
      final b = runGen(genInt(), 5);
      expect(a, b);
    });
  });
}
