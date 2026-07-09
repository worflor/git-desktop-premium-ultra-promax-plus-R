// Architectural tripwire + seam contract, in the spirit of
// manifold_refs_transport_guard_test.dart: a source-grep test is unusual in
// this codebase, but it is the only mechanism that catches a NEW direct
// `Process.run('git', …)` being added and silently escaping the counter,
// the injection seam, and (for `Process.start`) the non-interactive
// environment default.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:path/path.dart' as p;

import '../support/scratch_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('source tripwire', () {
    tearDown(GitSpawn.reset);

    test(
        'git.dart has exactly the two seam-internal Process.run/Process.start '
        'call sites (_spawnRunRaw, _spawnStart) — every other git spawn must '
        'go through the seam', () {
      final file = File(p.join(
          Directory.current.path, 'lib', 'backend', 'git.dart'));
      expect(file.existsSync(), isTrue,
          reason: 'expected to find lib/backend/git.dart relative to the '
              'test runner\'s working directory (repo root)');
      final source = file.readAsStringSync();

      final directSpawnPattern = RegExp(r'Process\.(run|start)\(');
      final matches = directSpawnPattern.allMatches(source).toList();

      const seamInternalCallSites = 2; // _spawnRunRaw + _spawnStart.
      expect(matches.length, seamInternalCallSites,
          reason: 'git.dart should have exactly $seamInternalCallSites '
              'direct Process.run(/Process.start( call sites — the ones '
              'inside _spawnRunRaw and _spawnStart themselves. Found '
              '${matches.length}. A new git subprocess spawn MUST go '
              'through _spawnRunRaw / _spawnStart (see the GitSpawn seam '
              'doc comment at the top of the file) so it inherits the '
              'shared counting and fault-injection seam.');
    });

    // Codebase-wide ratchet. The seam in git.dart is the canonical path for
    // the APP's interactive git (status/diff/commit/…), but it is NOT the
    // only place git is legitimately spawned: the engine reads git INSIDE
    // `Isolate.run` (where the async, main-isolate-bound `_git` seam — its
    // semaphore + diagnostics tap — is unreachable, so it uses
    // `Process.runSync`), the AI/codex layer has its own exec path, forge
    // features shell out to `gh`/`glab`, IPC and interactive history surgery
    // stream via `Process.start` with stdin the seam can't express. A
    // "route everything through _git" invariant would therefore be false.
    //
    // What IS enforceable, and what the git.dart-local tripwire above can't
    // see: the SET of files that spawn `git` directly is a known, reviewed
    // list, and it may only shrink. A NEW file spawning `git` raw — or a
    // growing count in an existing one — fails here, forcing a conscious
    // choice: route it through `runGit` (preferred — non-interactive env,
    // throttle, index.lock retry, GitSpawn counting/injection) or, if it
    // genuinely needs raw/isolate/streaming control, add it here with a
    // reason. Measured 2026-07-09.
    test('the set of files spawning `git` directly is the known, reviewed set '
        '(and its total may only shrink)', () {
      // Each entry is a file legitimately spawning `git` outside the seam,
      // with WHY. git.dart itself is excluded — its 2 seam-internal spawns are
      // covered by the test above.
      const knownRawGitSpawners = <String, String>{
        // Engine: git reads inside Isolate.run — the async _git seam is
        // main-isolate-bound and unreachable from a worker isolate.
        'lib/backend/logos_git_stats.dart': 'engine stats walk, isolate-sync',
        'lib/backend/logos_git_probe.dart': 'engine probe, isolate-sync',
        'lib/backend/spectral_trajectory_builder.dart': 'engine, isolate-sync',
        'lib/backend/repo_blob_walk.dart': 'walkRepoBlobsSync, isolate-sync',
        'lib/features/history/worldline_field.dart': 'history viz, isolate-sync',
        'lib/backend/aperture_sweep.dart': 'engine sweep, isolate-sync',
        // Manifold refs / IPC: streaming / stdin-fed plumbing.
        'lib/backend/manifold_refs.dart': 'ref metadata commit-tree plumbing',
        'lib/backend/ipc/pipe_commands.dart': 'IPC helper',
        // Interactive / streaming history surgery — Process.start with stdin
        // and custom env, which runGit (run-and-capture) can't express.
        'lib/backend/history_surgery.dart': 'interactive rebase/filter streams',
        'lib/features/history_surgery/history_surgery_page.dart': 'surgery UI',
        // Forge + review + release surfaces.
        'lib/backend/desk_pr_diff.dart': 'PR diff fetch',
        'lib/app/desk_pr_state.dart': 'PR state',
        'lib/app/desk_issue_state.dart': 'issue state',
        'lib/backend/release_state.dart': 'release channel probe',
        // Feature pages with a local spawn.
        'lib/features/changes/changes_page.dart': 'changes page',
        'lib/features/changes/merge_conflict_editor.dart': 'conflict editor',
        'lib/features/branches/branches_page.dart': 'branches page',
        'lib/features/palette/palette_registry.dart': 'palette entries',
      };
      // Total raw `git` spawns across all of these, today. May only go DOWN.
      const baselineTotalOutsideSeam = 52;

      final rawGitSpawn =
          RegExp(r'''Process\.(run|start|runSync)\(\s*['"]git['"]''');
      final libDir = Directory(p.join(Directory.current.path, 'lib'));
      final offenders = <String, int>{};
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = p
            .relative(entity.path, from: Directory.current.path)
            .replaceAll(r'\', '/');
        if (rel == 'lib/backend/git.dart') continue; // the seam itself
        final n = rawGitSpawn.allMatches(entity.readAsStringSync()).length;
        if (n > 0) offenders[rel] = n;
      }

      final unknown = offenders.keys
          .where((f) => !knownRawGitSpawners.containsKey(f))
          .toList()
        ..sort();
      expect(unknown, isEmpty,
          reason: 'NEW file(s) spawn `git` directly, outside the git.dart '
              'seam and the reviewed allowlist: $unknown. Prefer routing '
              'through `runGit` (backend/git.dart) — it gives you the '
              'non-interactive env, the concurrency throttle, index.lock '
              'retry, and GitSpawn counting/fault-injection for free. If the '
              'call genuinely needs raw/isolate/streaming control, add the '
              'file to knownRawGitSpawners here with a one-line reason.');

      final total = offenders.values.fold(0, (a, b) => a + b);
      expect(total, lessThanOrEqualTo(baselineTotalOutsideSeam),
          reason: 'raw `git` spawns outside the seam grew from '
              '$baselineTotalOutsideSeam to $total. This ratchet only allows '
              'the count to shrink (migrate a spawn to runGit) — never grow. '
              'If a new spawn is genuinely warranted, it belongs in runGit '
              'or needs an explicit, reasoned baseline bump here.');
      // When it shrinks, tighten the baseline so the ratchet keeps its grip.
      if (total < baselineTotalOutsideSeam) {
        // ignore: avoid_print
        print('[ratchet] raw git spawns outside seam dropped to $total '
            '(was $baselineTotalOutsideSeam) — lower baselineTotalOutsideSeam.');
      }
    });
  });

  group('GitSpawn counting', () {
    tearDown(GitSpawn.reset);

    test('runGit increments GitSpawn.runCount by one per call', () async {
      final repo = await ScratchRepo.create(name: 'spawn_seam_count');
      addTearDown(repo.dispose);

      // create() itself spawns several git processes (init, config x4,
      // commit --allow-empty) — reset AFTER create() so only the call under
      // test is counted.
      GitSpawn.reset();

      final result =
          await runGit(repo.dir.path, ['rev-parse', '--git-dir']);

      expect(result.exitCode, 0);
      expect(GitSpawn.runCount, 1,
          reason: 'a single non-coalesced runGit call should spawn exactly '
              'one subprocess through _spawnRunRaw');
      expect(GitSpawn.startCount, 0);
    });
  });

  group('GitSpawn.runOverride injection', () {
    tearDown(GitSpawn.reset);

    test('runOverride intercepts the spawn instead of invoking real git',
        () async {
      final repo = await ScratchRepo.create(name: 'spawn_seam_override');
      addTearDown(repo.dispose);
      GitSpawn.reset();

      var overrideCalled = false;
      GitSpawn.runOverride = (args, {workingDirectory, environment}) async {
        overrideCalled = true;
        return ProcessResult(0, 0, const <int>[], const <int>[]);
      };

      final result =
          await runGit(repo.dir.path, ['status', '--porcelain']);

      expect(overrideCalled, isTrue,
          reason: 'GitSpawn.runOverride should have been invoked instead '
              'of the real git binary');
      expect(result.exitCode, 0);
    });
  });
}
