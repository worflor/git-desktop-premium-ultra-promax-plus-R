import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git_dir_watcher.dart';
import 'package:git_desktop/backend/git_result.dart';

/// A [GitDirWatcher] whose [start] does no real filesystem work, so the
/// wiring can be exercised without a live watch. The coalesced callback
/// is captured by the injected factory and fired by hand.
class _FakeGitDirWatcher extends GitDirWatcher {
  _FakeGitDirWatcher(super.repoPath, super.onRepoChanged);

  bool disposed = false;

  @override
  Future<void> start() async {}

  @override
  void dispose() {
    disposed = true;
  }
}

const _okStatus = GitResult<RepositoryStatus>.ok(
  RepositoryStatus(branch: 'main', ahead: 0, behind: 0, files: []),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('statusRevision advances on every status refresh — the epoch diff '
      'caches key on', () async {
    final state = RepositoryState(
      switchDebounce: Duration.zero,
      openRepositoryFn: (path) async => GitResult.ok(path),
      statusLoader: (path) async => _okStatus,
      gitWatcherFactory: (path, onChanged) =>
          _FakeGitDirWatcher(path, onChanged),
    );
    addTearDown(state.dispose);

    final r0 = state.statusRevision;
    await state.setActivePath('repo-a');
    expect(
      state.statusRevision,
      greaterThan(r0),
      reason: 'opening a repo publishes a status snapshot',
    );

    final r1 = state.statusRevision;
    await state.refreshStatus();
    expect(
      state.statusRevision,
      greaterThan(r1),
      reason:
          'a refresh publishes a NEW snapshot even when file status '
          'codes are identical — content may have changed while the '
          'status shape (path|M) did not, and diff caches keyed on the '
          'shape alone would serve the previous edit\'s parse',
    );
  });

  test('superseded repo switch does not publish stale active path', () async {
    final firstOpenStarted = Completer<void>();
    final allowFirstOpen = Completer<void>();
    final openedPaths = <String>[];
    final statusPaths = <String>[];

    final state = RepositoryState(
      switchDebounce: Duration.zero,
      openRepositoryFn: (path) async {
        openedPaths.add(path);
        if (path == 'repo-a') {
          firstOpenStarted.complete();
          await allowFirstOpen.future;
        }
        return GitResult.ok(path);
      },
      statusLoader: (path) async {
        statusPaths.add(path);
        return const GitResult.ok(
          RepositoryStatus(branch: 'main', ahead: 0, behind: 0, files: []),
        );
      },
    );
    addTearDown(state.dispose);

    final notifiedActivePaths = <String?>[];
    state.addListener(() => notifiedActivePaths.add(state.activePath));

    final first = state.setActivePath('repo-a', addToRecents: false);
    await firstOpenStarted.future;

    final second = state.setActivePath('repo-b', addToRecents: false);
    expect(await first, isNull);

    allowFirstOpen.complete();
    expect(await second, isNull);
    await Future<void>.delayed(Duration.zero);

    expect(openedPaths, ['repo-a', 'repo-b']);
    expect(state.activePath, 'repo-b');
    expect(notifiedActivePaths, everyElement('repo-b'));
    expect(statusPaths, ['repo-b']);
  });

  test('dispose completes a debounced repo switch', () async {
    final state = RepositoryState(
      switchDebounce: const Duration(days: 1),
      openRepositoryFn: (path) async => GitResult.ok(path),
      statusLoader: (path) async => const GitResult.ok(
        RepositoryStatus(branch: 'main', ahead: 0, behind: 0, files: []),
      ),
    );

    final pending = state.setActivePath('repo-a', addToRecents: false);
    state.dispose();

    expect(await pending.timeout(const Duration(seconds: 1)), isNull);
  });

  test('dispose suppresses an in-flight repo switch result', () async {
    final openStarted = Completer<void>();
    final allowOpen = Completer<void>();
    final state = RepositoryState(
      switchDebounce: Duration.zero,
      openRepositoryFn: (path) async {
        openStarted.complete();
        await allowOpen.future;
        return GitResult.ok(path);
      },
      statusLoader: (path) async => const GitResult.ok(
        RepositoryStatus(branch: 'main', ahead: 0, behind: 0, files: []),
      ),
    );

    final pending = state.setActivePath('repo-a', addToRecents: false);
    await openStarted.future;
    state.dispose();
    allowOpen.complete();

    expect(await pending, isNull);
    expect(state.activePath, isNull);
  });

  test('dispose suppresses an in-flight status refresh result', () async {
    final statusStarted = Completer<void>();
    final allowStatus = Completer<void>();
    final state = RepositoryState(
      switchDebounce: Duration.zero,
      openRepositoryFn: (path) async => GitResult.ok(path),
      statusLoader: (path) async {
        statusStarted.complete();
        await allowStatus.future;
        return const GitResult.ok(
          RepositoryStatus(branch: 'main', ahead: 0, behind: 0, files: []),
        );
      },
    );

    final pending = state.setActivePath('repo-a', addToRecents: false);
    await statusStarted.future;
    state.dispose();
    allowStatus.complete();

    expect(await pending, isNull);
  });

  test(
    'a coalesced git-dir change refreshes status without a user epoch',
    () async {
      var statusLoads = 0;
      void Function()? onRepoChanged;
      final state = RepositoryState(
        switchDebounce: Duration.zero,
        externalRefreshThrottle: const Duration(milliseconds: 20),
        openRepositoryFn: (path) async => GitResult.ok(path),
        statusLoader: (path) async {
          statusLoads++;
          return _okStatus;
        },
        gitWatcherFactory: (path, cb) {
          onRepoChanged = cb;
          return _FakeGitDirWatcher(path, cb);
        },
      );
      addTearDown(state.dispose);

      await state.setActivePath('repo-a', addToRecents: false);
      await Future<void>.delayed(Duration.zero);
      final loadsAfterOpen = statusLoads;
      expect(loadsAfterOpen, greaterThanOrEqualTo(1));
      expect(onRepoChanged, isNotNull);
      final epochBefore = state.userRefreshEpoch;

      // Simulate the watcher's coalesced "repo changed" signal.
      onRepoChanged!();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        statusLoads,
        greaterThan(loadsAfterOpen),
        reason: 'external change runs the status refresh path',
      );
      expect(
        state.userRefreshEpoch,
        epochBefore,
        reason: 'external churn is not a user-attention event',
      );
    },
  );

  test('external-change refreshes are throttled', () async {
    var statusLoads = 0;
    void Function()? onRepoChanged;
    final state = RepositoryState(
      switchDebounce: Duration.zero,
      externalRefreshThrottle: const Duration(milliseconds: 200),
      openRepositoryFn: (path) async => GitResult.ok(path),
      statusLoader: (path) async {
        statusLoads++;
        return _okStatus;
      },
      gitWatcherFactory: (path, cb) {
        onRepoChanged = cb;
        return _FakeGitDirWatcher(path, cb);
      },
    );
    addTearDown(state.dispose);

    await state.setActivePath('repo-a', addToRecents: false);
    await Future<void>.delayed(Duration.zero);
    final baseline = statusLoads;

    // Ten rapid external signals inside one throttle window: one runs on
    // the leading edge, the rest collapse into a single trailing refresh.
    for (var i = 0; i < 10; i++) {
      onRepoChanged!();
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(
      statusLoads - baseline,
      lessThanOrEqualTo(2),
      reason: 'a burst of signals must not spam the refresh path',
    );
    expect(statusLoads - baseline, greaterThanOrEqualTo(1));
  });

  test('a repo switch disposes the old watcher and builds a new one', () async {
    final built = <String>[];
    final watchers = <_FakeGitDirWatcher>[];
    final state = RepositoryState(
      switchDebounce: Duration.zero,
      openRepositoryFn: (path) async => GitResult.ok(path),
      statusLoader: (path) async => _okStatus,
      gitWatcherFactory: (path, cb) {
        built.add(path);
        final w = _FakeGitDirWatcher(path, cb);
        watchers.add(w);
        return w;
      },
    );

    await state.setActivePath('repo-a', addToRecents: false);
    await state.setActivePath('repo-b', addToRecents: false);

    expect(built, ['repo-a', 'repo-b']);
    expect(
      watchers[0].disposed,
      isTrue,
      reason: 'the previous repo\'s watcher is torn down on switch',
    );
    expect(watchers[1].disposed, isFalse);

    state.dispose();
    expect(
      watchers[1].disposed,
      isTrue,
      reason: 'dispose tears down the active watcher',
    );
  });
}
