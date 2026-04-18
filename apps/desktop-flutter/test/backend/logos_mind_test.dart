// Tests for LogosMind — the AI synthesis composing the Logos engine,
// per-file engrams, semantic edges, and the generative primitives.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_mind.dart';

/// Builds a large-enough synthetic repo (≥ 260 nodes) so the spectral
/// basis materialises. Uses a tight-cluster topology inside a single
/// directory (`lib/auth/*`) so `buildFromStats`' directory-aware edge
/// scoring keeps the connections alive. The landmark paths (a, b, c, d,
/// unrelated) live inside the cluster; unrelated sits alone.
LogosGit _fixtureEngine() {
  final touches = <String, int>{};
  final volatility = <String, double>{};
  final jaccard = <String, Map<String, double>>{};

  // 260 synthetic siblings in one directory + 5 landmarks + unrelated.
  final siblings = <String>[
    for (var i = 0; i < 260; i++) 'lib/auth/f${i.toString().padLeft(3, '0')}.dart',
  ];
  final landmarks = [
    'lib/auth/a.dart',
    'lib/auth/b.dart',
    'lib/auth/c.dart',
    'lib/auth/d.dart',
  ];
  final all = [...siblings, ...landmarks, 'lib/unrelated.dart'];
  for (final p in all) {
    touches[p] = 10;
    volatility[p] = 1.0;
    jaccard[p] = <String, double>{};
  }
  // Give every sibling + landmark strong jaccard to every other
  // lib/auth/* file — they all share a parent directory so
  // buildFromStats' scoring accepts them as top-N neighbours.
  final authNodes = [...siblings, ...landmarks];
  for (var i = 0; i < authNodes.length; i++) {
    for (var j = i + 1; j < authNodes.length; j++) {
      jaccard[authNodes[i]]![authNodes[j]] = 0.8;
      jaccard[authNodes[j]]![authNodes[i]] = 0.8;
    }
  }
  // unrelated dangles off lib/auth/a.dart by a thread.
  jaccard['lib/unrelated.dart']!['lib/auth/a.dart'] = 0.03;
  jaccard['lib/auth/a.dart']!['lib/unrelated.dart'] = 0.03;

  return LogosGit.buildFromStats(LogosGitStats(
    touches: touches,
    totalCommits: 200,
    volatility: volatility,
    volMean: 1.0,
    volStddev: 0.3,
    coupling: FileCouplingMatrix(
      jaccard: jaccard,
      headHash: 'fixture',
      commitsAnalyzed: 200,
    ),
    perFileCommitIndices: const {},
  )).withSymbolEdges({
    'lib/auth/a.dart': {'getUser': 2.0, 'authToken': 1.0},
    'lib/auth/b.dart': {'getUser': 1.5, 'saveUser': 2.0},
    'lib/auth/c.dart': {'authToken': 2.5, 'validate': 1.0},
    'lib/auth/d.dart': {'saveUser': 1.0, 'validate': 1.5},
  });
}

void main() {
  group('MindQuery parsing', () {
    test('path query resolves to seed weight 1.0', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final seeds = mind.resolveQuery(const MindQuery.path('lib/auth/a.dart'));
      expect(seeds, {'lib/auth/a.dart': 1.0});
    });

    test('path query returns empty for unknown path', () {
      final mind = LogosMind(engine: _fixtureEngine());
      expect(
          mind.resolveQuery(const MindQuery.path('lib/ghost.dart')), isEmpty);
    });

    test('tokens query weights paths by symbol overlap', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final seeds = mind.resolveQuery(const MindQuery.tokens(['getUser']));
      // a.dart has getUser weight 2.0, b.dart has 1.5.
      expect(seeds.containsKey('lib/auth/a.dart'), isTrue);
      expect(seeds.containsKey('lib/auth/b.dart'), isTrue);
      expect(seeds['lib/auth/a.dart']! > seeds['lib/auth/b.dart']!, isTrue);
    });

    test('tokens query returns empty when nothing matches', () {
      final mind = LogosMind(engine: _fixtureEngine());
      expect(mind.resolveQuery(const MindQuery.tokens(['xyzzy_zzz'])),
          isEmpty);
    });

    test('text query tokenises by non-alphanumeric and drops shorties', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final seeds = mind.resolveQuery(
          const MindQuery.text('we need getUser and authToken today'));
      expect(seeds.containsKey('lib/auth/a.dart'), isTrue);
      expect(seeds.containsKey('lib/auth/c.dart'), isTrue);
    });

    test('weighted query keeps only known paths', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final seeds = mind.resolveQuery(const MindQuery.weighted({
        'lib/auth/a.dart': 0.6,
        'lib/ghost.dart': 0.4,
      }));
      expect(seeds, {'lib/auth/a.dart': 0.6});
    });
  });

  group('LogosMind.ask — retrieval-augmented inference', () {
    test('returns ranked candidates excluding the seed', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final response = mind.ask(const MindQuery.path('lib/auth/a.dart'));
      expect(response.candidates, isNotEmpty);
      for (final c in response.candidates) {
        expect(c.path, isNot('lib/auth/a.dart'));
      }
      // Top result should be a tightly-coupled neighbour in the
      // auth cluster, not the dangling `unrelated.dart`.
      final topPath = response.candidates.first.path;
      expect(topPath.startsWith('lib/auth/'), isTrue,
          reason: 'expected an auth-cluster sibling, got $topPath');
    });

    test('unrelated node is far down the rankings', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final response = mind.ask(
          const MindQuery.path('lib/auth/a.dart'),
          topN: 50);
      final unrelatedIdx =
          response.candidates.indexWhere((c) => c.path == 'lib/unrelated.dart');
      // Either not in top-50 or at the very bottom. Strong signal
      // either way: unrelated is far from auth.
      expect(unrelatedIdx, anyOf(-1, greaterThan(30)));
    });

    test('empty query yields empty response', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final response =
          mind.ask(const MindQuery.path('lib/does-not-exist.dart'));
      expect(response.candidates, isEmpty);
      expect(response.seedPaths, isEmpty);
      expect(response.topPath, isNull);
    });

    test('focus field has length n and positive mass', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final response = mind.ask(const MindQuery.path('lib/auth/a.dart'));
      expect(response.focus.length, mind.engine.graph.n);
      var s = 0.0;
      for (final v in response.focus) s += v.abs();
      expect(s, greaterThan(0),
          reason: 'propagated focus should have nonzero mass');
    });

    test('explanation mentions the top path', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final response = mind.ask(const MindQuery.path('lib/auth/a.dart'));
      final topPath = response.candidates.first.path;
      final display = topPath.split('/').last;
      expect(response.explanation.contains(display), isTrue,
          reason: 'explanation=${response.explanation} top=$topPath');
    });

  });

  group('LogosMind.dream — generative inference', () {
    test('samples are finite and length n', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final dreams = mind.dream(
        const MindQuery.path('lib/auth/a.dart'),
        samples: 4,
        rng: math.Random(1),
        mass: 0.5,
      );
      expect(dreams, hasLength(4));
      for (final d in dreams) {
        expect(d.field.length, mind.engine.graph.n);
        for (final v in d.field) {
          expect(v.isFinite, isTrue);
        }
      }
    });

    test('different rng seeds produce different dreams', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final a = mind
          .dream(const MindQuery.path('lib/auth/a.dart'),
              samples: 1, rng: math.Random(1))
          .first;
      final b = mind
          .dream(const MindQuery.path('lib/auth/a.dart'),
              samples: 1, rng: math.Random(2))
          .first;
      var differ = 0;
      for (var i = 0; i < a.field.length; i++) {
        if ((a.field[i] - b.field[i]).abs() > 1e-6) differ++;
      }
      expect(differ, greaterThan(0));
    });

    test('each dream has top contributors excluding the seed', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final dreams = mind.dream(
        const MindQuery.path('lib/auth/a.dart'),
        samples: 2,
        topN: 3,
      );
      for (final d in dreams) {
        expect(d.top, isNotEmpty);
        for (final c in d.top) {
          expect(c.path, isNot('lib/auth/a.dart'));
        }
      }
    });

    test('residual energy is non-negative', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final dreams = mind.dream(
        const MindQuery.path('lib/auth/a.dart'),
        samples: 3,
      );
      for (final d in dreams) {
        expect(d.residualEnergy, greaterThanOrEqualTo(0.0));
      }
    });

    test('empty query yields empty dream list', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final dreams =
          mind.dream(const MindQuery.path('lib/ghost.dart'), samples: 4);
      expect(dreams, isEmpty);
    });
  });

  group('LogosMind.evolve — Langevin dynamical inference', () {
    test('trajectory has steps + 1 snapshots', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final evo = mind.evolve(
        const MindQuery.path('lib/auth/a.dart'),
        steps: 20,
        dt: 0.1,
        beta: 1.0,
        mass: 0.5,
      );
      expect(evo.trajectory, hasLength(21));
    });

    test('final ranking is non-empty and excludes seeds', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final evo = mind.evolve(const MindQuery.path('lib/auth/a.dart'), steps: 30);
      expect(evo.finalRanking, isNotEmpty);
      for (final c in evo.finalRanking) {
        expect(c.path, isNot('lib/auth/a.dart'));
      }
    });

    test('empty query yields empty evolution', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final evo = mind.evolve(const MindQuery.path('lib/ghost.dart'));
      expect(evo.trajectory, isEmpty);
      expect(evo.finalRanking, isEmpty);
    });
  });

  group('MindAxisContribution', () {
    test('dominant returns the strongest axis name', () {
      const a = MindAxisContribution(f0: 0.1, cc: 0.8, m: 0.2, ab: 0.3, en: 0.1);
      expect(a.dominant, 'cc');
    });

    test('dominant returns null on zero vector', () {
      const a = MindAxisContribution();
      expect(a.dominant, isNull);
    });

    test('lerp interpolates toward the target', () {
      const a = MindAxisContribution(f0: 0.0, cc: 0.0, m: 0.0, ab: 0.0, en: 0.0);
      const b = MindAxisContribution(f0: 1.0, cc: 1.0, m: 1.0, ab: 1.0, en: 1.0);
      final mid = a.lerp(b, 0.5);
      expect(mid.f0, closeTo(0.5, 1e-12));
      expect(mid.cc, closeTo(0.5, 1e-12));
    });

    test('dot is symmetric', () {
      const a = MindAxisContribution(f0: 0.5, cc: 0.3, m: 0.1, ab: 0.2, en: 0.1);
      const b = MindAxisContribution(f0: 0.2, cc: 0.4, m: 0.5, ab: 0.1, en: 0.3);
      expect(a.dot(b), closeTo(b.dot(a), 1e-12));
    });
  });

  group('ask populates axis attribution', () {
    test('m axis lights up for same-directory siblings', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final r = mind.ask(const MindQuery.path('lib/auth/a.dart'));
      // Top candidates are all inside lib/auth/; m contribution should
      // be positive for at least one.
      final someWithM =
          r.candidates.any((c) => (c.axis?.m ?? 0) > 0.0);
      expect(someWithM, isTrue);
    });
  });

  group('MindSession', () {
    test('drill seeds the next query from previous top result', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final session = MindSession(mind: mind);
      final r1 = session.ask(const MindQuery.path('lib/auth/a.dart'));
      expect(r1.candidates, isNotEmpty);
      final r2 = session.drill();
      // The new seed is the first query's top candidate.
      expect(r2.seedPaths, contains(r1.candidates.first.path));
      expect(session.history, hasLength(2));
    });

    test('consensus attaches confidence ∈ [0, 1]', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final session = MindSession(mind: mind);
      final r = session.consensus(
        const MindQuery.path('lib/auth/a.dart'),
        dreamSamples: 4,
        rng: math.Random(0x515),
      );
      expect(r.confidence, isNotNull);
      expect(r.confidence!, greaterThanOrEqualTo(0.0));
      expect(r.confidence!, lessThanOrEqualTo(1.0));
    });

    test('reinforce moves axis bias toward accepted candidate', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final session = MindSession(mind: mind);
      final before = session.axisBias;
      final r = session.ask(const MindQuery.path('lib/auth/a.dart'));
      final accepted = r.candidates.first;
      session.reinforce(accepted.path);
      final after = session.axisBias;
      // Bias should have moved (unless the candidate's axis was
      // exactly the uniform prior, which is vanishingly unlikely on
      // our fixture).
      final delta = (after.cc - before.cc).abs() +
          (after.f0 - before.f0).abs() +
          (after.ab - before.ab).abs();
      expect(delta, greaterThan(0.0));
    });

    test('forget clears history and resets bias', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final session = MindSession(mind: mind);
      session.ask(const MindQuery.path('lib/auth/a.dart'));
      session.reinforce('lib/auth/b.dart');
      session.forget();
      expect(session.history, isEmpty);
      expect(session.axisBias.f0, MindAxisContribution.uniform.f0);
    });

    test('drill without prior asks throws', () {
      final mind = LogosMind(engine: _fixtureEngine());
      final session = MindSession(mind: mind);
      expect(() => session.drill(), throwsStateError);
    });
  });
}
