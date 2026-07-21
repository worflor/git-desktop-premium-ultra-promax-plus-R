// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Coverage for lib/features/palette/palette_registry.dart's
// buildStaticEntries — the command-palette entry builder. Every one of
// its section builders (_repoEntries, _actionEntries, _gitCommandEntries,
// ...) is library-private, so the only public surface is
// buildStaticEntries(context, callbacks) itself; this suite exercises it
// through a real (but minimal) provider tree rather than pumping the
// palette UI, per the task's "prefer pure-function tests" guidance —
// buildStaticEntries's own logic (which entries exist, their labels,
// their live closures) is what's under test, not any widget rendering.
//
// buildStaticEntries unconditionally reads WorktreeState and DeskPrState
// from context — both are in widget_harness's documented "excluded
// providers" list (they need a RepositoryState instance), so every test
// here wires them itself via pumpHarness's `wrapAboveNavigator` hook,
// exactly as that file's doc comment prescribes.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:git_desktop/app/app_identity.dart';
import 'package:git_desktop/app/build_info.dart';
import 'package:git_desktop/app/desk_pr_state.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/app/worktree_state.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git_dir_watcher.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/features/palette/palette_entry.dart';
import 'package:git_desktop/features/palette/palette_registry.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

/// A GitDirWatcher whose `start` does no real filesystem work — so an
/// active-repo RepositoryState in these tests never opens a live
/// `Directory.watch` stream that would never settle under testWidgets'
/// fake-async clock (the hang the active-repo tests used to be skipped for).
/// Mirrors test/app/repository_state_test.dart's fake.
class _FakeGitDirWatcher extends GitDirWatcher {
  _FakeGitDirWatcher(super.repoPath, super.onRepoChanged);
  @override
  Future<void> start() async {}
  @override
  void dispose() {}
}

PaletteCallbacks _noopCallbacks() => (
      onModeChanged: (int mode) {},
      onOpenXray: () {},
      onOpenSettings: () {},
      onRefresh: () {},
      onUndo: () {},
      onRepoSwitch: (String path) {},
      onDeskSwitch: (String path) {},
      onOpenBrowser: (String url) {},
    );

/// Wires WorktreeState + DeskPrState against whichever RepositoryState
/// [context] resolves to at that point in the tree — the harness's own
/// default instance unless a caller also shadows RepositoryState ahead
/// of this in the same wrapAboveNavigator MultiProvider list.
Widget _wireWorktreeAndDeskPr(BuildContext context, Widget app) => MultiProvider(
      providers: [
        ChangeNotifierProvider<WorktreeState>(
          create: (c) => WorktreeState(c.read<RepositoryState>()),
        ),
        ChangeNotifierProvider<DeskPrState>(
          create: (c) =>
              DeskPrState(c.read<RepositoryState>(), c.read<AppIdentityState>()),
        ),
      ],
      child: app,
    );

/// A REAL, existing, empty (non-git) directory — never the string literal
/// '/fake/repo/path'. WorktreeState/DeskPrState (unlike RepositoryState,
/// which honors the injected openRepositoryFn/statusLoader) always spawn
/// REAL `git` subprocesses against whatever repoPath is active, and a
/// `Process.run` whose `workingDirectory` doesn't exist on disk at all is
/// an edge case Windows handles by hanging rather than failing fast — a
/// real empty directory makes every one of those background probes fail
/// quickly and cleanly ("not a git repository") instead.
Future<Directory> _realNonGitDir() async {
  final dir = await Directory.systemTemp.createTemp('palette_registry_test_');
  addTearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort — a lingering Windows file handle must not fail teardown.
    }
  });
  return dir;
}

Widget Function(BuildContext, Widget) _withRepoOverride(RepositoryState repo) =>
    (BuildContext context, Widget app) => MultiProvider(
          providers: [
            ChangeNotifierProvider<RepositoryState>.value(value: repo),
            ChangeNotifierProvider<WorktreeState>(
              create: (c) => WorktreeState(c.read<RepositoryState>()),
            ),
            ChangeNotifierProvider<DeskPrState>(
              create: (c) => DeskPrState(
                  c.read<RepositoryState>(), c.read<AppIdentityState>()),
            ),
          ],
          child: app,
        );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // These entries used to be skip-gated: wiring DeskPrState/WorktreeState
  // against an active repo fired real `git`/forge `Process.run`s that never
  // resolve under testWidgets' fake-async clock (a hang, not a fail), and
  // mutating PreferencesState wrote to the real settings.json. Both are now
  // sealed hermetically by installHermeticStorageSeams (below), so every test
  // here RUNS by default. Tests that assert a populated worktree/desk case can
  // still seed via debugSeedDesks/debugSeed.
  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });
  // Seals the auto-refresh git work + settings disk I/O and registers its OWN
  // reset via addTearDown, so there is no hand-rolled tearDown to forget (a
  // stuck debugSuppressDiskWrites would silently swallow a later test's
  // settings write). See widget_harness.installHermeticStorageSeams.
  setUp(installHermeticStorageSeams);

  group('buildStaticEntries — no active repo, no engine', () {
    testWidgets('produces exactly the expected repo-independent static entries',
        (tester) async {
      late BuildContext ctx;
      await pumpHarness(
        tester,
        Builder(builder: (context) {
          ctx = context;
          return const Scaffold(body: SizedBox());
        }),
        wrapAboveNavigator: _wireWorktreeAndDeskPr,
      );

      final entries = buildStaticEntries(ctx, _noopCallbacks());
      final ids = entries.map((e) => e.id).toList();

      // Law: no duplicate ids, ever.
      expect(ids.toSet().length, ids.length, reason: 'duplicate entry id in $ids');

      // Every repoPath-gated or engine-gated builder contributes nothing.
      for (final prefix in [
        'cmd.', 'act.', 'repo.', 'desk.', 'ai.', 'pr.', 'predict.',
        'hot.', 'keystone.', 'tool.',
      ]) {
        expect(entries.where((e) => e.id.startsWith(prefix)), isEmpty,
            reason: 'expected no "$prefix" entries with no active repo');
      }
      expect(entries.where((e) => e.id == 'debug.engine'), isEmpty);
      expect(entries.where((e) => e.id == 'debug.coupling'), isEmpty);
      expect(entries.where((e) => e.id == 'info.coherence'), isEmpty);

      final byId = {for (final e in entries) e.id: e};

      // Navigation — fixed set of 6, with their shortcuts.
      expect(byId['nav.changes']!.shortcutLabel, 'Ctrl+1');
      expect(byId['nav.history']!.shortcutLabel, 'Ctrl+2');
      expect(byId['nav.branches']!.shortcutLabel, 'Ctrl+3');
      expect(byId['nav.refresh']!.shortcutLabel, 'F5');
      expect(byId.containsKey('nav.xray'), isTrue);
      expect(byId.containsKey('nav.settings'), isTrue);

      // Theme entries — exactly one per AppThemeId, current theme marked.
      for (final id in AppThemeId.values) {
        final entry = byId['theme.${id.name}'];
        expect(entry, isNotNull, reason: 'missing theme entry for ${id.name}');
        expect(entry!.subtitle, id == defaultThemeId ? 'active' : null);
      }
      expect(
        entries.where((e) => e.id.startsWith('theme.')).length,
        AppThemeId.values.length,
      );

      // Settings toggles — exact id set (hideAiFeatures defaults false, so
      // setting.ai-read-only is present).
      final settingIds =
          entries.where((e) => e.id.startsWith('setting.')).map((e) => e.id).toList();
      expect(settingIds, [
        'setting.reduce-motion',
        'setting.logo-animates-unfocused',
        'setting.instant-blame',
        'setting.auto-select-changes',
        'setting.fetch-online-issues',
        'setting.remember-wip',
        'setting.hide-ai',
        'setting.crash-reporting',
        'setting.ai-read-only',
        'setting.stash-cabinet',
        'setting.file-sort-inverted',
      ]);

      expect(byId['info.version']!.label, 'Manifold ${BuildInfo.versionDisplay}');
      expect(byId.containsKey('debug.theme-specimen'), isTrue);

      expect(
        entries.length,
        6 /* nav */ +
            AppThemeId.values.length /* theme */ +
            settingIds.length /* settings */ +
            1 /* info.version */ +
            1 /* debug.theme-specimen */,
      );
    });

    testWidgets(
        'setting toggle readBool/writeBool are LIVE closures over PreferencesState, '
        'not a value snapshotted at build time', (tester) async {
      late BuildContext ctx;
      late PreferencesState prefs;
      await pumpHarness(
        tester,
        Builder(builder: (context) {
          ctx = context;
          prefs = context.read<PreferencesState>();
          return const Scaffold(body: SizedBox());
        }),
        wrapAboveNavigator: _wireWorktreeAndDeskPr,
      );

      final entries = buildStaticEntries(ctx, _noopCallbacks());
      final reduceMotion = entries.firstWhere((e) => e.id == 'setting.reduce-motion');

      expect(prefs.reduceMotion, isFalse);
      expect(reduceMotion.readBool!(), isFalse);

      // Mutate the state DIRECTLY (not through the entry) after the entry
      // list was already built.
      await prefs.setReduceMotion(true);
      expect(reduceMotion.readBool!(), isTrue,
          reason: 'readBool must read the live PreferencesState, not a snapshot');

      // Round-trip the other direction: writing through the entry mutates
      // the real state.
      reduceMotion.writeBool!(false);
      await tester.pump();
      expect(prefs.reduceMotion, isFalse);
    });
  });

  group('buildStaticEntries — with an active repo', () {
    testWidgets(
        'action/git-command/PR/AI entries reflect real repo status, with no duplicate ids',
        (tester) async {
      final repo = RepositoryState(
        switchDebounce: Duration.zero,
        gitWatcherFactory: (path, onChanged) =>
            _FakeGitDirWatcher(path, onChanged),
        openRepositoryFn: (path) async => GitResult.ok(path),
        statusLoader: (path) async => const GitResult.ok(
          RepositoryStatus(
            branch: 'feature/x',
            upstream: 'origin/feature/x',
            ahead: 2,
            behind: 1,
            files: [
              RepositoryStatusFile(path: 'a.dart', staged: 'M', unstaged: ''),
              RepositoryStatusFile(path: 'b.dart', staged: '', unstaged: 'M'),
            ],
          ),
        ),
      );
      addTearDown(repo.dispose);
      // createTemp + setActivePath touch the real filesystem, which blocks
      // forever on a ReceivePort under testWidgets' fake-async clock. Run
      // them in the real async zone; the resulting state is visible once
      // runAsync returns.
      late Directory repoDir;
      await tester.runAsync(() async {
        repoDir = await _realNonGitDir();
        await repo.setActivePath(repoDir.path, addToRecents: false);
      });
      expect(repo.activePath, repoDir.path);
      expect(repo.status?.branch, 'feature/x');

      late BuildContext ctx;
      await pumpHarness(
        tester,
        Builder(builder: (context) {
          ctx = context;
          return const Scaffold(body: SizedBox());
        }),
        wrapAboveNavigator: _withRepoOverride(repo),
      );

      final entries = buildStaticEntries(ctx, _noopCallbacks());
      final ids = entries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate entry id in $ids');
      final byId = {for (final e in entries) e.id: e};

      // No real git worktree exists at the plain temp dir, so desk entries
      // stay empty — confirms the builder degrades gracefully rather
      // than crashing on a failed worktree probe.
      expect(entries.where((e) => e.id.startsWith('desk.')), isEmpty);

      // _actionEntries
      expect(byId['act.copy-path']!.subtitle, repoDir.path);
      expect(byId['act.copy-branch']!.subtitle, 'feature/x');
      expect(byId.containsKey('act.open-browser'), isTrue);
      expect(byId.containsKey('act.terminal'), isTrue);
      expect(byId.containsKey('act.reveal'), isTrue);

      // _gitCommandEntries — ahead/behind-derived subtitles + chips.
      expect(byId['cmd.pull']!.subtitle, '1 behind origin/feature/x');
      expect(byId['cmd.pull']!.chipLabel, '1↓');
      expect(byId['cmd.push']!.subtitle, '2 commits to origin/feature/x');
      expect(byId['cmd.push']!.chipLabel, '2↑');
      expect(byId['cmd.force-push']!.chipTone, ChipTone.negative);
      // Every one of these entries surviving construction also proves
      // PaletteEntry's own constructor invariants held (never both
      // onExecute+onMutate; every onMutate entry declares mutatesRepoPath)
      // — buildStaticEntries not throwing IS part of this assertion.
      for (final id in [
        'cmd.fetch', 'cmd.pull', 'cmd.push', 'cmd.force-push', 'cmd.commit',
        'cmd.stage-all', 'cmd.unstage-all', 'cmd.discard-all',
        'cmd.create-branch', 'cmd.delete-branch', 'cmd.rename-branch',
        'cmd.stash-push', 'cmd.stash-pop', 'cmd.stash-apply', 'cmd.stash-drop',
        'cmd.create-tag', 'cmd.cherry-pick', 'cmd.revert',
      ]) {
        expect(byId.containsKey(id), isTrue, reason: 'missing $id');
      }

      // _prEntries — no PR recorded for this branch yet -> "Create PR" only.
      expect(byId.containsKey('pr.create'), isTrue);
      expect(byId['pr.create']!.subtitle, 'feature/x');
      expect(byId.containsKey('pr.merge'), isFalse);

      // _aiEntries — trigger entries always present when AI isn't hidden.
      for (final id in [
        'ai.trigger.generate', 'ai.trigger.review', 'ai.trigger.muse', 'ai.trigger.debug',
      ]) {
        expect(byId.containsKey(id), isTrue, reason: 'missing $id');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('hideAiFeatures removes both the setting.ai-read-only toggle '
        'and every ai.* trigger entry', (tester) async {
      final repo = RepositoryState(
        switchDebounce: Duration.zero,
        gitWatcherFactory: (path, onChanged) =>
            _FakeGitDirWatcher(path, onChanged),
        openRepositoryFn: (path) async => GitResult.ok(path),
        statusLoader: (path) async => const GitResult.ok(
          RepositoryStatus(branch: 'main', ahead: 0, behind: 0, files: []),
        ),
      );
      addTearDown(repo.dispose);
      // Real filesystem work runs in the real async zone (see the twin test
      // above) — under the fake clock createTemp never resolves.
      await tester.runAsync(() async {
        final repoDir = await _realNonGitDir();
        await repo.setActivePath(repoDir.path, addToRecents: false);
      });

      late BuildContext ctx;
      late PreferencesState prefs;
      await pumpHarness(
        tester,
        Builder(builder: (context) {
          ctx = context;
          prefs = context.read<PreferencesState>();
          return const Scaffold(body: SizedBox());
        }),
        wrapAboveNavigator: _withRepoOverride(repo),
      );

      await prefs.setHideAiFeatures(true);

      final entries = buildStaticEntries(ctx, _noopCallbacks());
      final ids = entries.map((e) => e.id).toSet();

      expect(ids.contains('setting.ai-read-only'), isFalse);
      expect(ids.where((id) => id.startsWith('ai.')), isEmpty);
      // Non-AI sections are unaffected.
      expect(ids.contains('cmd.fetch'), isTrue);
      expect(ids.contains('nav.changes'), isTrue);
    });
  });
}
