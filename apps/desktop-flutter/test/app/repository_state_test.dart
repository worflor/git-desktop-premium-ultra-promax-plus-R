import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
          RepositoryStatus(
            branch: 'main',
            ahead: 0,
            behind: 0,
            files: [],
          ),
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

    expect(
      await pending.timeout(const Duration(seconds: 1)),
      isNull,
    );
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
}
