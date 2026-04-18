// Tests for the LogosDream pipeline — phrase friendlifier, verb
// harvester, and the sync dreamCommitPhrase capstone.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_dream.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_probe.dart';
import 'package:git_desktop/backend/logos_mind.dart';

LogosGit _fixtureEngine() {
  final touches = <String, int>{};
  final volatility = <String, double>{};
  final jaccard = <String, Map<String, double>>{};

  // Enough nodes in a shared directory to get past the spectral-basis
  // minimum and to give buildFromStats' edge scoring something to work
  // with.
  final siblings = <String>[
    for (var i = 0; i < 260; i++)
      'lib/auth/f${i.toString().padLeft(3, '0')}.dart',
  ];
  final landmarks = [
    'lib/auth/spectral_ricci.dart',
    'lib/auth/AuthToken.dart',
    'lib/auth/session-manager.dart',
  ];
  final all = [...siblings, ...landmarks];
  for (final p in all) {
    touches[p] = 10;
    volatility[p] = 1.0;
    jaccard[p] = <String, double>{};
  }
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      jaccard[all[i]]![all[j]] = 0.8;
      jaccard[all[j]]![all[i]] = 0.8;
    }
  }
  return LogosGit.buildFromStats(LogosGitStats(
    touches: touches,
    totalCommits: 200,
    volatility: volatility,
    volMean: 1.0,
    volStddev: 0.3,
    coupling: FileCouplingMatrix(
      jaccard: jaccard,
      headHash: 'dream-fixture',
      commitsAnalyzed: 200,
    ),
    perFileCommitIndices: const {},
  ));
}

void main() {
  group('phraseForPath', () {
    test('snake_case to spaced lowercase', () {
      expect(phraseForPath('lib/backend/spectral_ricci.dart'),
          'spectral ricci');
    });

    test('camelCase split', () {
      expect(phraseForPath('src/AuthToken.ts'), 'auth token');
    });

    test('kebab-case to spaces', () {
      expect(phraseForPath('pages/user-profile.tsx'), 'user profile');
    });

    test('drops extension and directory chrome', () {
      // Minimum token length is 2 — single-letter stems are filtered
      // out because they rarely carry meaning. Multi-letter stems
      // survive directory chrome stripping.
      expect(phraseForPath('a/b/auth.go'), 'auth');
      expect(phraseForPath('a/b/c.go'), '');
    });

    test('rejects hex-like fragments', () {
      expect(phraseForPath('tmp/abc123def456.log'), '');
    });

    test('handles empty input', () {
      expect(phraseForPath(''), '');
      expect(phraseForPath('/'), '');
    });

    test('filters short tokens', () {
      expect(phraseForPath('a.dart'), '');
    });

    test('backslash paths (Windows)', () {
      expect(phraseForPath(r'lib\ui\manifold_pane.dart'), 'manifold pane');
    });

    test('multi-piece camelCase joins into single phrase', () {
      expect(phraseForPath('getUserProfile.dart'),
          'get user profile');
    });
  });

  group('verbFromCommitSubject', () {
    test('plain subject first word', () {
      expect(verbFromCommitSubject('refactor the auth module'), 'refactor');
    });

    test('conventional-commits prefix', () {
      expect(verbFromCommitSubject('fix(auth): handle null session'),
          'handle');
    });

    test('emoji and punctuation leader', () {
      expect(verbFromCommitSubject('✨ add login button'), 'add');
    });

    test('returns null on trivial input', () {
      expect(verbFromCommitSubject(''), isNull);
      expect(verbFromCommitSubject('!!!!'), isNull);
      expect(verbFromCommitSubject('42'), isNull);
    });

    test('rejects hex-like first words', () {
      expect(verbFromCommitSubject('abcdef123 foo bar'), isNull);
    });
  });

  group('harvestVerbTemplates', () {
    test('frequency-ranks verbs from commit subjects', () {
      final subjects = [
        'refactor auth module',
        'refactor session storage',
        'add login button',
        'fix: resolve session race',
        'refactor cookie handling',
        'add password validator',
      ];
      final verbs = harvestVerbTemplates(subjects);
      expect(verbs.first, 'refactor',
          reason: 'refactor appears 3× → most frequent');
      expect(verbs.contains('add'), isTrue);
    });

    test('filters noisy commits', () {
      final subjects = [
        'abc123 deadbeef',
        '42 the number',
        '',
        'fix typo',
      ];
      final verbs = harvestVerbTemplates(subjects);
      expect(verbs, contains('fix'));
    });

    test('respects maxVerbs cap', () {
      final subjects = List.generate(
          30, (i) => 'verb$i something');
      final verbs = harvestVerbTemplates(subjects, maxVerbs: 5);
      expect(verbs.length, 5);
    });
  });

  group('dreamCommitPhrase — sync capstone', () {
    test('returns a phrase composed from verb + subject', () {
      final engine = _fixtureEngine();
      final probe = DiffProbe(
        sourceWeights: const {
          'lib/auth/spectral_ricci.dart': 1.0,
        },
        primaryPaths: const {'lib/auth/spectral_ricci.dart'},
        suggestedTemperature: 1.0,
        stats: const ProbeStats(
          primaryCount: 1,
          mMatches: 0,
          abMatches: 0,
          mSymbols: 0,
          coherence: 1.0,
          symbolMatches: 0,
        ),
      );
      final mind = LogosMind(engine: engine);
      final phrase = dreamCommitPhrase(
        probe: probe,
        mind: mind,
        recentSubjects: const [
          'refactor spectral core',
          'refactor engram fit',
          'add new observables',
        ],
      );
      expect(phrase, isNotNull);
      expect(phrase!.startsWith('refactor '), isTrue,
          reason: 'should pick the harvested top verb; got "$phrase"');
      expect(phrase.contains('spectral ricci'), isTrue,
          reason: 'should mention the subject phrase; got "$phrase"');
    });

    test('defaults to "update" when no commits have been harvested', () {
      final engine = _fixtureEngine();
      final probe = DiffProbe(
        sourceWeights: const {
          'lib/auth/AuthToken.dart': 1.0,
        },
        primaryPaths: const {'lib/auth/AuthToken.dart'},
        suggestedTemperature: 1.0,
        stats: const ProbeStats(
          primaryCount: 1,
          mMatches: 0,
          abMatches: 0,
          mSymbols: 0,
          coherence: 1.0,
          symbolMatches: 0,
        ),
      );
      final mind = LogosMind(engine: engine);
      final phrase = dreamCommitPhrase(
        probe: probe,
        mind: mind,
        recentSubjects: const [],
      );
      expect(phrase, isNotNull);
      expect(phrase!.startsWith('update '), isTrue);
      expect(phrase.contains('auth token'), isTrue);
    });

    test('null on empty probe', () {
      final engine = _fixtureEngine();
      final probe = DiffProbe(
        sourceWeights: const {},
        primaryPaths: const {},
        suggestedTemperature: null,
        stats: const ProbeStats(
          primaryCount: 0,
          mMatches: 0,
          abMatches: 0,
          mSymbols: 0,
          coherence: 0.0,
          symbolMatches: 0,
        ),
      );
      final mind = LogosMind(engine: engine);
      expect(
          dreamCommitPhrase(probe: probe, mind: mind), isNull);
    });

    test('null on unphrase-able subject (hex-only path)', () {
      final engine = _fixtureEngine();
      final probe = DiffProbe(
        sourceWeights: const {'tmp/deadbeef1234.log': 1.0},
        primaryPaths: const {'tmp/deadbeef1234.log'},
        suggestedTemperature: 1.0,
        stats: const ProbeStats(
          primaryCount: 1,
          mMatches: 0,
          abMatches: 0,
          mSymbols: 0,
          coherence: 1.0,
          symbolMatches: 0,
        ),
      );
      final mind = LogosMind(engine: engine);
      expect(
          dreamCommitPhrase(probe: probe, mind: mind), isNull);
    });
  });
}
