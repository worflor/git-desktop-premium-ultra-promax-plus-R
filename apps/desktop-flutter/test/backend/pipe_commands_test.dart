// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// pipe_commands_test.dart — the CLI bridge, exercised as the CLI exercises it.
//
// The bridge had no tests at all before this: every `manifold <cmd>` went
// through handlers whose only verification was a human running them against a
// live app. These drive the real handler functions with a real
// ManifoldBridgeContext over real scratch repositories, so the contract the
// CLI depends on — what `index` reports, what it registers, and which
// revision a flag combination selects — is pinned.
//
// The AI-calling handlers (`review`, `muse`) are deliberately not here: they
// need a configured provider and would spend money. What they DO resolve
// before calling a model is covered by review_target_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/ai_settings_state.dart';
import 'package:git_desktop/app/file_coupling_state.dart';
import 'package:git_desktop/app/logos_git_state.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/backend/ipc/bridge_context.dart';
import 'package:git_desktop/backend/ipc/pipe_commands.dart';
import 'package:git_desktop/backend/review_target.dart';
import 'package:git_desktop/backend/undo_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/scratch_repo.dart';

ManifoldBridgeContext _context(RepositoryState repoState) =>
    ManifoldBridgeContext(
      repoState: repoState,
      aiSettingsState: AiSettingsState(),
      preferencesState: PreferencesState(),
      logosGitState: LogosGitState(),
      undoCoordinator: UndoCoordinator(),
      fileCouplingState: FileCouplingState(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScratchRepo repo;
  late RepositoryState repoState;
  late ManifoldBridgeContext ctx;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = await ScratchRepo.create(name: 'bridge');
    await repo.writeFile('a.dart', 'void main() {}\n');
    await repo.commitAll('first');
    await repo.writeFile('b.dart', 'const x = 1;\n');
    await repo.commitAll('second');
    repoState = RepositoryState();
    ctx = _context(repoState);
  });

  tearDown(() async {
    repoState.dispose();
    await repo.dispose();
  });

  Future<Map<String, dynamic>> index({bool check = false}) => commands['index']!(
        {'repo': repo.dir.path, if (check) 'check': 'true'},
        ctx,
      );

  // ── index: validate, report, register ───────────────────────────

  test('B1: index validates and registers a repo Manifold never knew about',
      () async {
    expect(repoState.recentPaths, isEmpty,
        reason: 'guard: the repo starts unknown');

    final r = await index();

    expect(r['valid'], isTrue);
    // Three commits: the harness seeds an empty one so HEAD always resolves,
    // then the two written above.
    expect(r['commits'], 3);
    expect(r['trackedFiles'], 2);
    expect(r['branch'], 'main');
    expect(r['shallow'], isFalse);
    expect(r['bare'], isFalse);
    expect(r['alreadyKnown'], isFalse);
    expect(r['registered'], isTrue);
    expect(repoState.knowsRecent(r['repo'] as String), isTrue,
        reason: 'the whole point of index is that the repo shows up after');
    expect(repoState.recentPaths, hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('B2: index --check reports without registering anything', () async {
    final r = await index(check: true);

    expect(r['valid'], isTrue);
    expect(r['checkOnly'], isTrue);
    expect(r['commits'], 3);
    expect(repoState.recentPaths, isEmpty,
        reason: 'a check must have no side effects — it is the "would this '
            'work?" probe you run before spending an AI call');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('B3: index NEVER switches the active repo', () async {
    // Registering from a terminal must not yank the window the user is
    // looking at over to a different project. setActivePath would do exactly
    // that, and would also bump the analysis scope, superseding work already
    // queued for whatever they actually have open.
    expect(repoState.activePath, isNull);
    await index();
    expect(repoState.activePath, isNull,
        reason: 'the CLI hijacked the GUI to a different repository');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('B4: indexing twice reports the second as already known', () async {
    await index();
    final again = await index();
    expect(again['alreadyKnown'], isTrue);
    expect(repoState.recentPaths.where((p) => p == again['repo']).length, 1,
        reason: 'a repo must not accumulate duplicate entries');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('B4b: a repo already known under a different spelling is not '
      'added twice', () async {
    // Found by running `manifold index` against the repo the window was
    // already open on: the picker stores `C:\\Users\\...`, while the path
    // derived from `git rev-parse --git-common-dir` comes back with forward
    // slashes. String equality says those are different projects, so the
    // sidebar grew a second entry for the repo it already had.
    final first = await index();
    expect(first['registered'], isTrue);
    final stored = first['repo'] as String;

    // The same repository, spelled the way git prints it.
    final gitStyle = stored.replaceAll(r'\', '/');
    if (gitStyle == stored) {
      // POSIX already spells paths the way git prints them, so there is no
      // second spelling to collide with and nothing here to prove. Skipped
      // rather than passed vacuously — a green test that asserted nothing
      // would be worse than an absent one.
      markTestSkipped('separator spelling only diverges on Windows');
      return;
    }

    final again = await commands['index']!({'repo': gitStyle}, ctx);
    expect(again['alreadyKnown'], isTrue,
        reason: 'the same repository under two spellings is one project');
    expect(repoState.recentPaths, hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('B5: index refuses a path that is not a git repository', () async {
    final notARepo = repo.dir.parent.path;
    await expectLater(
      commands['index']!({'repo': notARepo}, ctx),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('not a usable git'))),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('B6: index reports an engine view of the history', () async {
    final r = await index();
    final engine = r['engine'] as Map<String, dynamic>;
    expect(engine['ready'], isTrue, reason: 'engine error: ${engine['error']}');
    expect(engine['commitsOnAxis'], 2,
        reason: 'the commit axis is what makes reviewing a commit possible; '
            'reporting it is how you find out the engine can locate one');
    expect(engine['graphFiles'], greaterThan(0));
    // Deliberately one FEWER than the 3 commits git reports: the harness's
    // seed commit changes no files, and a commit with no file statistics
    // never takes an axis position. The two numbers diverging is the
    // documented behaviour, not drift — which is why both are pinned.
    expect(engine['commitsOnAxis'], lessThan(r['commits'] as int));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('B7: index survives a repository with no commits yet', () async {
    final empty = await ScratchRepo.create(name: 'bridge_empty');
    try {
      // ScratchRepo seeds an initial commit; strip history back to unborn.
      await empty.git(['checkout', '--orphan', 'blank']);
      await empty.git(['reset', '--hard']);
      final r = await commands['index']!({'repo': empty.dir.path}, ctx);
      expect(r['valid'], isTrue);
      expect(r['commits'], 0);
      expect(r['head'], isNull,
          reason: 'an unborn HEAD is absent, not an empty string');
    } finally {
      await empty.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ── frozen-diff replay ──────────────────────────────────────────

  test('B12: a frozen diff is the whole subject — no dirty files needed',
      () async {
    // Found by Manifold reviewing its own change. `review-evidence` resolved
    // the working-tree scope BEFORE looking at --diff, and that resolution
    // throws on a clean checkout — so the documented clean A/B replay was
    // impossible to run from the clean tree it exists for. Reproduced here
    // against a genuinely clean repo.
    expect(await repo.isClean(), isTrue, reason: 'guard: the tree is clean');

    // OUTSIDE the repository. Writing the patch inside it would make the tree
    // dirty and the scope resolution would stop throwing — the test would
    // then pass without exercising the condition it exists for.
    final holder = Directory.systemTemp.createTempSync('frozen_diff_');
    final patch = File('${holder.path}${Platform.pathSeparator}frozen.diff');
    await patch.writeAsString(
      'diff --git a/a.dart b/a.dart\n'
      '--- a/a.dart\n'
      '+++ b/a.dart\n'
      '@@ -1 +1,2 @@\n'
      ' void main() {}\n'
      '+// added\n',
    );

    // The scope resolution is what used to throw; reaching past it is the
    // whole assertion. The gather beyond it needs a configured AI provider,
    // so a provider-shaped failure still proves the fix.
    try {
      expect(await repo.isClean(), isTrue,
          reason: 'guard: the patch must live outside the repo');
      await commands['review-evidence']!(
          {'repo': repo.dir.path, 'diff': patch.path}, ctx);
    } catch (e) {
      expect('$e', isNot(contains('No dirty files')),
          reason: 'the supplied patch IS the subject; the working tree is '
              'not consulted');
    } finally {
      try {
        holder.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('B13: a missing frozen diff is named, not silently ignored', () async {
    await expectLater(
      commands['review-evidence']!(
          {'repo': repo.dir.path, 'diff': 'no-such-file.diff'}, ctx),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('No frozen diff'))),
      reason: 'the old code fell through to the working tree when the path '
          'did not exist, silently measuring something else',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ── which revision the flags select ─────────────────────────────

  group('flag → target', () {
    test('B8: no revision flags means the working tree', () {
      expect(historyTargetFrom({}), isNull);
      expect(historyTargetFrom({'files': 'a.dart'}), isNull,
          reason: 'scoping files does not make it a history review');
    });

    test('B9: --last is the newest commit', () {
      final t = historyTargetFrom({'last': 'true'});
      expect(t, isA<CommitTarget>());
      expect((t! as CommitTarget).revspec, 'HEAD');
    });

    test('B10: --commit and --range carry their spec through', () {
      expect((historyTargetFrom({'commit': 'HEAD~3'})! as CommitTarget).revspec,
          'HEAD~3');

      final two = historyTargetFrom({'range': 'v1..v2'})! as RangeTarget;
      expect(two.mergeBase, isFalse);
      expect(two.base, 'v1');
      expect(two.tip, 'v2');

      final three = historyTargetFrom({'range': 'main...topic'})! as RangeTarget;
      expect(three.mergeBase, isTrue,
          reason: 'three dots measures from the merge base; treating it as '
              'two reviews a different set of changes entirely');
    });

    test('B11: conflicting revision flags are refused, never ranked', () {
      // This test previously pinned a PRECEDENCE rule — --last wins — and
      // Manifold's own review flagged it: a precedence rule means
      // `--last --commit abc` succeeds and prints an ordinary-looking review
      // of a revision the caller did not name, with nothing downstream able
      // to tell. Refusing makes that unrepresentable.
      expect(
        () => historyTargetFrom({'last': 'true', 'commit': 'HEAD~5'}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => historyTargetFrom({'commit': 'HEAD~5', 'range': 'a..b'}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => historyTargetFrom(
            {'last': 'true', 'commit': 'HEAD~5', 'range': 'a..b'}),
        throwsA(isA<ArgumentError>()),
      );

      // An empty flag is not a conflict — the CLI passes absent options
      // through as empty strings.
      expect((historyTargetFrom({'last': 'true', 'commit': '  '})!
              as CommitTarget)
          .revspec, 'HEAD');
    });
  });
}
