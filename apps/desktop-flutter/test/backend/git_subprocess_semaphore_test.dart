import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';

void main() {
  test('production git subprocess cap preserves parallel probe headroom', () {
    expect(gitSubprocessMaxConcurrency, greaterThan(4));
  });

  test('squash probes leave a permit for foreground git work', () {
    expect(squashProbeMaxConcurrency, greaterThan(0));
    expect(squashProbeMaxConcurrency, lessThan(gitSubprocessMaxConcurrency));
  });

  test('GitSubprocessSemaphore reserves released permits for queued waiters',
      () async {
    final semaphore = GitSubprocessSemaphore(1);

    await semaphore.acquire();
    expect(semaphore.activeCount, 1);
    expect(semaphore.queuedCount, 0);

    var waiterStarted = false;
    final waiter = semaphore.acquire().then((_) {
      waiterStarted = true;
    });
    expect(semaphore.activeCount, 1);
    expect(semaphore.queuedCount, 1);

    semaphore.release();
    expect(semaphore.activeCount, 1);
    expect(semaphore.queuedCount, 0);

    await waiter;
    expect(waiterStarted, isTrue);
    expect(semaphore.activeCount, 1);

    semaphore.release();
    expect(semaphore.activeCount, 0);
    expect(semaphore.queuedCount, 0);
  });

  test('GitSubprocessSemaphore rejects over-release', () {
    final semaphore = GitSubprocessSemaphore(1);
    expect(semaphore.release, throwsStateError);
  });
}
