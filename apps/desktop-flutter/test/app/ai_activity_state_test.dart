// Pins two load-bearing contracts on AiActivityState:
//
//   1. Records are scoped to (repoPath, kind) — a mutation on one
//      repo must not affect another repo's slice.
//   2. activeFor returns a stable list reference until the requested
//      repo's slice actually changes — otherwise `context.select`
//      consumers fan rebuilds across every notify regardless of
//      which repo mutated, defeating the per-repo narrowing the
//      sidebar pill relies on.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/ai_activity_state.dart';

void main() {
  group('AiActivityState — record scoping', () {
    test('records are isolated per repo', () {
      final s = AiActivityState();
      s.start(
        repoPath: '/a',
        kind: AiActivityKind.review,
        scopeKey: 'k1',
      );
      expect(s.recordFor('/a', AiActivityKind.review), isNotNull);
      expect(s.recordFor('/b', AiActivityKind.review), isNull);
    });

    test('records are isolated per kind on the same repo', () {
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.review, scopeKey: 'k1');
      s.start(
          repoPath: '/a', kind: AiActivityKind.muse, scopeKey: 'k2');
      expect(s.recordFor('/a', AiActivityKind.review)?.scopeKey, 'k1');
      expect(s.recordFor('/a', AiActivityKind.muse)?.scopeKey, 'k2');
      expect(s.recordFor('/a', AiActivityKind.generate), isNull);
    });

    test('start replaces a prior record on the same slot', () {
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.review, scopeKey: 'old');
      final firstStartedAt =
          s.recordFor('/a', AiActivityKind.review)!.startedAt;
      s.start(
          repoPath: '/a', kind: AiActivityKind.review, scopeKey: 'new');
      final r = s.recordFor('/a', AiActivityKind.review)!;
      expect(r.scopeKey, 'new');
      // startedAt is replaced — same slot, fresh run.
      expect(
        r.startedAt.isAtSameMomentAs(firstStartedAt) ||
            r.startedAt.isAfter(firstStartedAt),
        isTrue,
      );
    });

    test('complete drops the unread flag and lands typed payload', () {
      final s = AiActivityState();
      s.start(repoPath: '/a', kind: AiActivityKind.ask, scopeKey: 'q');
      s.complete(
        repoPath: '/a',
        kind: AiActivityKind.ask,
        scopeKey: 'q',
        result: const AiAskResult('answer'),
      );
      final r = s.recordFor('/a', AiActivityKind.ask)!;
      expect(r.isDone, isTrue);
      expect(r.seen, isFalse);
      final payload = r.result;
      expect(payload, isA<AiAskResult>());
      expect((payload as AiAskResult).answer, 'answer');
    });

    test('markSeen has no effect on a non-existent record', () {
      // Defensive: callers shouldn't have to null-check first.
      final s = AiActivityState();
      s.markSeen(repoPath: '/a', kind: AiActivityKind.review);
      expect(s.recordFor('/a', AiActivityKind.review), isNull);
    });

    test('markSeen is idempotent on an already-seen record', () {
      final s = AiActivityState();
      s.start(repoPath: '/a', kind: AiActivityKind.ask, scopeKey: 'k');
      s.complete(
        repoPath: '/a',
        kind: AiActivityKind.ask,
        scopeKey: 'k',
        result: const AiAskResult('a'),
      );
      s.markSeen(repoPath: '/a', kind: AiActivityKind.ask);
      // Second markSeen should still succeed silently — and the
      // active slice should remain empty (record stays in store but
      // is filtered out by the seen flag).
      s.markSeen(repoPath: '/a', kind: AiActivityKind.ask);
      expect(s.activeFor('/a'), isEmpty);
    });

    test('complete with a stale scopeKey is dropped silently', () {
      // Mid-flight scope change: the record's scopeKey doesn't match
      // the late completion. Caller's result is silently discarded so
      // the user's current state isn't overwritten.
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.ask, scopeKey: 'fresh');
      s.complete(
        repoPath: '/a',
        kind: AiActivityKind.ask,
        scopeKey: 'STALE',
        result: const AiAskResult('should be ignored'),
      );
      // Record is still running — the completion was rejected.
      expect(s.recordFor('/a', AiActivityKind.ask)!.isRunning, isTrue);
    });

    test('clearRepo only affects that repo', () {
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.review, scopeKey: 'k');
      s.start(
          repoPath: '/b', kind: AiActivityKind.review, scopeKey: 'k');
      s.clearRepo('/a');
      expect(s.recordFor('/a', AiActivityKind.review), isNull);
      expect(s.recordFor('/b', AiActivityKind.review), isNotNull);
    });
  });

  group('AiActivityState — activeFor cache stability', () {
    test('activeFor returns the same reference across consecutive calls',
        () {
      // The motivating regression: a fresh List on every call defeats
      // `context.select<AiActivityState, List<AiActivityRecord>>(...)`
      // narrowing because Dart compares lists by reference.
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.review, scopeKey: 'k');
      final first = s.activeFor('/a');
      final second = s.activeFor('/a');
      expect(identical(first, second), isTrue);
    });

    test('empty active list is shared across repos', () {
      // Repos with no activity should both yield the same canonical
      // empty list — both selectors stay equal-by-reference, neither
      // consumer rebuilds when an unrelated repo mutates.
      final s = AiActivityState();
      final emptyA = s.activeFor('/a');
      final emptyB = s.activeFor('/b');
      expect(emptyA, isEmpty);
      expect(identical(emptyA, emptyB), isTrue);
    });

    test('mutation on a different repo does NOT change this repo\'s reference',
        () {
      // Core narrowing claim: only this repo's selector should fire
      // when this repo changes.
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.review, scopeKey: 'k');
      final aBefore = s.activeFor('/a');
      // Mutate a DIFFERENT repo's slice.
      s.start(
          repoPath: '/b', kind: AiActivityKind.review, scopeKey: 'k');
      final aAfter = s.activeFor('/a');
      expect(identical(aBefore, aAfter), isTrue,
          reason: 'unrelated repo mutation should not invalidate /a');
    });

    test('mutation on the SAME repo invalidates the reference', () {
      // Use the ask kind since AiAskResult takes a plain String —
      // avoids pulling AiCommitReviewData / AiMuseData fixtures into
      // this test (those are large dtos with many required fields).
      // The cache invariant is kind-agnostic so this still pins it.
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.ask, scopeKey: 'k');
      final before = s.activeFor('/a');
      s.complete(
        repoPath: '/a',
        kind: AiActivityKind.ask,
        scopeKey: 'k',
        result: const AiAskResult('answer'),
      );
      final after = s.activeFor('/a');
      // Different references — the slice changed (running → done).
      expect(identical(before, after), isFalse);
    });

    test('markSeen invalidates and removes the record from active', () {
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.muse, scopeKey: 'k');
      s.complete(
        repoPath: '/a',
        kind: AiActivityKind.muse,
        scopeKey: 'k',
        result: AiAskResult('ignored'),
      );
      // Done-but-unread records appear in active.
      expect(s.activeFor('/a').length, 1);
      s.markSeen(repoPath: '/a', kind: AiActivityKind.muse);
      // After markSeen, the record is "read" — drops out of active.
      expect(s.activeFor('/a'), isEmpty);
    });

    test('clear invalidates the cache for that repo', () {
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.ask, scopeKey: 'k');
      final before = s.activeFor('/a');
      expect(before.length, 1);
      s.clear(repoPath: '/a', kind: AiActivityKind.ask);
      final after = s.activeFor('/a');
      expect(after, isEmpty);
      expect(identical(before, after), isFalse);
    });

    test('clearRepo invalidates that repo\'s cache only', () {
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.review, scopeKey: 'k');
      s.start(
          repoPath: '/b', kind: AiActivityKind.review, scopeKey: 'k');
      final aBefore = s.activeFor('/a');
      final bBefore = s.activeFor('/b');
      s.clearRepo('/a');
      expect(s.activeFor('/a'), isEmpty);
      expect(identical(s.activeFor('/b'), bBefore), isTrue);
      // Sanity: aBefore was non-empty and is now decoupled.
      expect(aBefore.isNotEmpty, isTrue);
    });

    test('clearRepo on a cache-only repo does NOT notify', () {
      // A consumer that called activeFor on a record-less repo gets
      // back the canonical empty list, which gets memoised. clearRepo
      // on that repo carries no observable change — every selector
      // sees the same empty list. Notifying would force unnecessary
      // page rebuilds.
      final s = AiActivityState();
      // Prime the cache with an empty entry — no records ever existed.
      s.activeFor('/a');
      var notified = 0;
      s.addListener(() => notified++);
      s.clearRepo('/a');
      expect(notified, 0);
    });

    test('clearRepo with real records fires notify exactly once', () {
      // Conversely, when there ARE observable records, clearRepo
      // must notify so consumers re-read.
      final s = AiActivityState();
      s.start(
          repoPath: '/a', kind: AiActivityKind.review, scopeKey: 'k');
      var notified = 0;
      s.addListener(() => notified++);
      s.clearRepo('/a');
      expect(notified, 1);
    });
  });

  group('AiActivityRecord.copyWith — sentinel semantics', () {
    // The sentinel pattern lets callers distinguish "argument
    // omitted" from "argument was null". Without it, you can't
    // null-out a previously-set field via copyWith — the `??`
    // fallback would silently keep the prior value. Same pattern
    // app_identity.dart uses for its tag.

    AiActivityRecord seed() => AiActivityRecord(
          kind: AiActivityKind.review,
          status: AiActivityStatus.done,
          startedAt: DateTime(2026, 1, 1),
          scopeKey: 'orig-scope',
          scopeLabel: 'orig-label',
          result: const AiAskResult('orig-answer'),
          error: 'orig-error',
          seen: false,
          endedAt: DateTime(2026, 1, 2),
        );

    test('omitting an argument keeps the prior value', () {
      final r = seed().copyWith(seen: true);
      expect(r.seen, isTrue);
      // Other fields untouched.
      expect(r.scopeKey, 'orig-scope');
      expect(r.scopeLabel, 'orig-label');
      expect(r.result, isA<AiAskResult>());
      expect(r.error, 'orig-error');
      expect(r.endedAt, DateTime(2026, 1, 2));
    });

    test('passing a non-null value overwrites', () {
      final r = seed().copyWith(
        scopeKey: 'new-scope',
        error: 'new-error',
      );
      expect(r.scopeKey, 'new-scope');
      expect(r.error, 'new-error');
      // Untouched fields remain.
      expect(r.scopeLabel, 'orig-label');
    });

    test('passing explicit null clears scopeKey', () {
      final r = seed().copyWith(scopeKey: null);
      expect(r.scopeKey, isNull);
      // Other nullables untouched.
      expect(r.scopeLabel, 'orig-label');
    });

    test('passing explicit null clears scopeLabel', () {
      final r = seed().copyWith(scopeLabel: null);
      expect(r.scopeLabel, isNull);
      expect(r.scopeKey, 'orig-scope');
    });

    test('passing explicit null clears result', () {
      final r = seed().copyWith(result: null);
      expect(r.result, isNull);
      expect(r.error, 'orig-error');
    });

    test('passing explicit null clears error', () {
      final r = seed().copyWith(error: null);
      expect(r.error, isNull);
      expect(r.result, isA<AiAskResult>());
    });

    test('passing explicit null clears endedAt', () {
      final r = seed().copyWith(endedAt: null);
      expect(r.endedAt, isNull);
    });
  });
}

