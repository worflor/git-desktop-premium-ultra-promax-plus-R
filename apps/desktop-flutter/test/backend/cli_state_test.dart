// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// cli_state_test.dart — what an agent is told about the tool it is driving.
//
// Two contracts here, and both exist because an agent cannot see the settings
// window:
//
//   * `state` (and the `settings` block every AI command echoes) reports what
//     is CONFIGURED, so a caller never has to infer which model answered.
//   * `--strands` overrides the configured loadout EXACTLY, and a name that
//     does not exist is refused rather than dropped — a silently smaller muse
//     looks identical to a successful one.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/ai_settings_state.dart';
import 'package:git_desktop/app/file_coupling_state.dart';
import 'package:git_desktop/app/logos_git_state.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/ipc/bridge_context.dart';
import 'package:git_desktop/backend/ipc/pipe_commands.dart';
import 'package:git_desktop/backend/undo_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

ManifoldBridgeContext _context() => ManifoldBridgeContext(
      repoState: RepositoryState(),
      aiSettingsState: AiSettingsState(),
      preferencesState: PreferencesState(),
      logosGitState: LogosGitState(),
      undoCoordinator: UndoCoordinator(),
      fileCouplingState: FileCouplingState(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── the settings an agent reads ─────────────────────────────────

  test('S1: the snapshot names a model slot for every AI command', () {
    final s = settingsSnapshot(_context());

    for (final key in const ['commitMessage', 'review', 'shake', 'muse']) {
      expect(s[key], isNotNull, reason: '$key is missing');
    }
    // Muse runs two models; the others run one.
    for (final key in const ['commitMessage', 'review', 'shake']) {
      final slot = s[key] as Map<String, dynamic>;
      expect(slot.containsKey('category'), isTrue, reason: key);
      expect(slot.containsKey('model'), isTrue, reason: key);
    }
    final muse = s['muse'] as Map<String, dynamic>;
    expect(muse['brainstorm'], isNotNull);
    expect(muse['synthesis'], isNotNull);
  });

  test('S2: the sweep says out loud that it shares review settings', () {
    // Otherwise a reader has to know it, and "shake uses the review model" is
    // exactly the kind of thing that stops being true quietly.
    final s = settingsSnapshot(_context());
    final shake = s['shake'] as Map<String, dynamic>;
    final review = s['review'] as Map<String, dynamic>;
    expect(shake['sharesReviewSettings'], isTrue);
    expect(shake['category'], review['category']);
    expect(shake['model'], review['model']);
  });

  test('S3: the snapshot reports commit FORMAT, not just the model', () {
    // A message generated to somebody else's structure is one the user has to
    // rewrite, so the agent gets to see the shape it will come back in.
    final cm = settingsSnapshot(_context())['commitMessage']
        as Map<String, dynamic>;
    expect(cm['structure'], isNotNull);
    expect(cm['voice'], isNotNull);
    expect(cm['coverage'], isNotNull);
  });

  test('S4: the configured muse loadout is reported, with counts', () {
    final muse = settingsSnapshot(_context())['muse'] as Map<String, dynamic>;
    final strands = muse['strands'] as List<dynamic>;
    expect(strands, isNotEmpty);
    for (final e in strands) {
      final m = e as Map<String, dynamic>;
      expect(parseMuseStrand(m['kind'] as String), isNotNull,
          reason: 'reported a strand name the parser does not accept: '
              '${m['kind']}');
      expect(m['count'], isA<int>());
    }
  });

  test('S5: reporting never forces provider discovery', () {
    // `state` sits in front of every other command; a network probe there
    // would be a poor thing to pay for on every call. It answers from the
    // user's own selections instead.
    final ctx = _context();
    expect(ctx.aiSettingsState.runtimeModelCategories, isEmpty,
        reason: 'guard: nothing has been discovered yet');
    final s = settingsSnapshot(ctx);
    expect((s['ai'] as Map<String, dynamic>)['categoriesLoaded'], isFalse,
        reason: 'and the snapshot says so rather than pretending');
    expect(s['review'], isNotNull);
  });

  // ── choosing strands ────────────────────────────────────────────

  group('strand override', () {
    test('S6: absent means "use what the user configured"', () {
      expect(parseStrandOverride(null), isNull);
      expect(parseStrandOverride(''), isNull);
      expect(parseStrandOverride('   '), isNull);
    });

    test('S7: named strands are carried exactly, in the order given', () {
      final q = parseStrandOverride('vertigo,ghost')!;
      expect([for (final e in q) museStrandLabel(e.kind)],
          ['vertigo', 'ghost']);
      expect(q.every((e) => e.count == 1), isTrue);
    });

    test('S8: name:count asks for several of one strand', () {
      final q = parseStrandOverride('spark:3,fever')!;
      expect(q.first.count, 3);
      expect(q.last.count, 1);
    });

    test('S9: an UNKNOWN strand is refused, never dropped', () {
      // The failure this prevents: a typo silently yields a smaller muse that
      // is indistinguishable from a successful one.
      expect(() => parseStrandOverride('spark,sparkle'),
          throwsA(isA<ArgumentError>()));
      expect(
        () => parseStrandOverride('nonsense'),
        throwsA(isA<ArgumentError>().having((e) => '$e', 'message',
            allOf(contains('nonsense'), contains('spark')))),
      );
    });

    test('S10: a repeated or empty-count strand is refused', () {
      expect(() => parseStrandOverride('spark,spark'),
          throwsA(isA<ArgumentError>()));
      expect(() => parseStrandOverride('spark:0'),
          throwsA(isA<ArgumentError>()));
    });

    test('S11: every strand in the vocabulary actually parses', () {
      // The list an agent is handed must be one it can use verbatim.
      for (final name in allStrandNames) {
        expect(parseStrandOverride(name), hasLength(1), reason: name);
      }
      expect(parseStrandOverride(allStrandNames.join(',')),
          hasLength(allStrandNames.length));
    });

    test('S12: whitespace around names is tolerated', () {
      final q = parseStrandOverride(' spark , fever ')!;
      expect([for (final e in q) museStrandLabel(e.kind)], ['spark', 'fever']);
    });
  });

  // ── the commands exist ──────────────────────────────────────────

  test('S13: state and commit-message are registered', () {
    expect(commands.containsKey('state'), isTrue);
    expect(commands.containsKey('commit-message'), isTrue);
  });

  test('S14: every registered command is described in `help`', () async {
    // `manifold help` is the machine-readable schema an agent reads to find
    // out what exists. A command registered but undescribed is invisible to
    // it — which is exactly how `shake`, `state`, `commit-message` and
    // `review-evidence` all shipped or nearly shipped unlisted. The registry
    // and the schema drift silently because nothing compares them; this does.
    final help = await commands['help']!(const {}, _context());
    final described = (help['commands'] as Map<String, dynamic>).keys.toSet();
    final registered = commands.keys.toSet();

    expect(registered.difference(described), isEmpty,
        reason: 'registered but absent from `help`');
    expect(described.difference(registered), isEmpty,
        reason: 'described in `help` but not registered — a schema promising '
            'a command that does not exist is worse than an absent one');
  });
}
