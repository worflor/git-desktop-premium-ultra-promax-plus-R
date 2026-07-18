// analysis_admission_test.dart — laws for the process-wide analysis byte
// budget. These are the invariants that make "analyze every status path,
// N at a time" memory-safe on any repository:
//   1. accounting — in-flight bytes are reserved for the work's duration and
//      released on completion AND on throw;
//   2. queueing — work that doesn't fit right now waits (FIFO) and runs when
//      budget frees, never lost, never run over budget;
//   3. declining — work whose declared size alone exceeds the whole budget
//      is refused without running (no schedule could ever admit it);
//   4. superseding — bumping a scope's epoch drops that scope's QUEUED work
//      before it does anything; running work is unaffected.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/analysis_admission.dart';

void main() {
  test('admits immediately under budget and accounts bytes', () async {
    final adm = AnalysisAdmission(totalBudget: 100);
    final release = Completer<void>();
    final done = adm.run(60, () async {
      await release.future;
      return 'a';
    });
    await Future<void>.delayed(Duration.zero);
    expect(adm.inFlightBytes, 60);
    release.complete();
    final result = await done;
    expect(result.ran, isTrue);
    expect(result.value, 'a');
    expect(adm.inFlightBytes, 0);
  });

  test('releases budget when work throws', () async {
    final adm = AnalysisAdmission(totalBudget: 100);
    await expectLater(
      adm.run<void>(80, () async => throw StateError('boom')),
      throwsStateError,
    );
    expect(adm.inFlightBytes, 0);
    // Budget is genuinely reusable afterwards.
    final ok = await adm.run(80, () async => 1);
    expect(ok.ran, isTrue);
  });

  test('queues FIFO when over budget and drains as budget frees', () async {
    final adm = AnalysisAdmission(totalBudget: 100);
    final firstRelease = Completer<void>();
    final order = <String>[];

    final first = adm.run(70, () async {
      order.add('first-start');
      await firstRelease.future;
      return 1;
    });
    // Doesn't fit (70+50 > 100) → queues.
    final second = adm.run(50, () async {
      order.add('second-start');
      return 2;
    });
    // Fits alongside first (70+20 <= 100)? No — FIFO fairness: second is
    // already queued, third (20) fits the residual budget of 30... but
    // admission is strictly FIFO through the queue, so third queues behind
    // second rather than jumping it.
    final third = adm.run(20, () async {
      order.add('third-start');
      return 3;
    });

    await Future<void>.delayed(Duration.zero);
    expect(order, ['first-start']);
    expect(adm.queuedCount, 2);

    firstRelease.complete();
    final results = await Future.wait([first, second, third]);
    expect(results.map((r) => r.value).toList(), [1, 2, 3]);
    expect(order, ['first-start', 'second-start', 'third-start']);
    expect(adm.inFlightBytes, 0);
    expect(adm.queuedCount, 0);
  });

  test('declines work larger than the entire budget without running it',
      () async {
    final adm = AnalysisAdmission(totalBudget: 100);
    var ran = false;
    final result = await adm.run(101, () async {
      ran = true;
      return 1;
    });
    expect(result.decision, AdmissionDecision.declined);
    expect(ran, isFalse);
    expect(adm.inFlightBytes, 0);
  });

  test('bumping the scope drops queued work before it runs', () async {
    final adm = AnalysisAdmission(totalBudget: 100);
    final scope = AdmissionScope();
    final blockRelease = Completer<void>();

    final blocker = adm.run(90, () async {
      await blockRelease.future;
      return 'blocker';
    }, scope: scope);

    var queuedRan = false;
    final queued = adm.run(50, () async {
      queuedRan = true;
      return 'queued';
    }, scope: scope);
    await Future<void>.delayed(Duration.zero);
    expect(adm.queuedCount, 1);

    scope.bump(); // repo switch
    blockRelease.complete();

    final blockerResult = await blocker;
    final queuedResult = await queued;
    // Already-running work drains normally; queued work is superseded.
    expect(blockerResult.ran, isTrue);
    expect(queuedResult.decision, AdmissionDecision.superseded);
    expect(queuedRan, isFalse);
    expect(adm.inFlightBytes, 0);

    // Budget remains fully usable after a supersede.
    final after = await adm.run(100, () async => 'after');
    expect(after.ran, isTrue);
  });

  test('dead scope is refused before queueing', () async {
    final adm = AnalysisAdmission(totalBudget: 100);
    final scope = AdmissionScope()..close();
    final result = await adm.run(10, () async => 1, scope: scope);
    expect(result.decision, AdmissionDecision.superseded);
  });
}
