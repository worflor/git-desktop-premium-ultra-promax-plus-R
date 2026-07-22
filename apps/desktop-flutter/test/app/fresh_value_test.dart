// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// fresh_value_test.dart — the CLI-staleness regression guard.
//
// THE BUG THIS PINS: the CLI bridge's helpers probed the per-repo caches
// (`engineFor` / `matrixFor`) and returned whatever was warm, only
// kicking a load when the cache was EMPTY. The first CLI call's snapshot
// therefore served every subsequent call unrefreshed; only the UI's
// manual refresh button ever advanced it. The fix is the
// `freshValueFor` / `freshEngineFor` accessors, which route through
// `loadForRepo` on every call so its HEAD-staleness check runs — a
// cheap TTL-deduped rev-parse when history is unmoved, a recompute when
// it moved.
//
// CONTRACTS:
//  F1  freshValueFor with a fresh cache (HEAD unmoved) returns the
//      cached value WITHOUT recomputing.
//  F2  freshValueFor after HEAD moves recomputes and returns the new
//      value — the regression: a stale cached value must never be
//      served once history has advanced.
//  F3  freshValueFor while a concurrent load is in flight waits for it
//      (no duplicate compute) and returns its result.
//  F4  freshEngineFor reaches the resolver on EVERY call (never
//      probe-then-return), and surfaces null → caller-visible error
//      when resolution fails.
//  F5  The timeout bounds the WHOLE call, including a cold compute this
//      call itself starts — a stuck compute must return (with whatever
//      the cache holds), never hang the caller. First cut only bounded
//      the concurrent-load wait; caught by Manifold's own review.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/logos_git_state.dart';
import 'package:git_desktop/app/per_repo_head_cache_state.dart';

import '../support/scratch_repo.dart';

/// Minimal concrete cache state: the cached value IS its head hash, so
/// the base class's freshness logic can be exercised directly against a
/// real repo's moving HEAD.
class _HeadEchoState extends PerRepoHeadCacheState<String> {
  int computeCalls = 0;
  Future<String> Function(String repoPath) compute0;
  _HeadEchoState(this.compute0);

  @override
  Future<ComputeOutcome<String>> compute(String repoPath) async {
    computeCalls++;
    return ComputeOutcome.success(await compute0(repoPath));
  }

  @override
  String headHashOf(String value) => value;

  @override
  String get computeFailureLabel => 'echo failed';
}

void main() {
  late ScratchRepo repo;

  setUp(() async {
    repo = await ScratchRepo.create(name: 'fresh_value');
  });

  tearDown(() async {
    await repo.dispose();
  });

  test('F1: fresh cache (HEAD unmoved) serves cached value, no recompute',
      () async {
    final state = _HeadEchoState((r) async => (await repo.head())!);
    final first = await state.freshValueFor(repo.dir.path);
    expect(first, isNotNull);
    expect(state.computeCalls, 1);
    final second = await state.freshValueFor(repo.dir.path);
    expect(second, first);
    expect(state.computeCalls, 1,
        reason: 'HEAD unmoved → the staleness check must short-circuit');
  });

  test('F2: HEAD moved between calls → recompute (the CLI staleness bug)',
      () async {
    final state = _HeadEchoState((r) async => (await repo.head())!);
    final before = await state.freshValueFor(repo.dir.path);
    expect(state.computeCalls, 1);

    // Advance history, exactly like a user committing between two CLI
    // review runs.
    await repo.writeFile('f.txt', 'x\n');
    await repo.commitAll('advance');

    final after = await state.freshValueFor(repo.dir.path);
    expect(state.computeCalls, 2,
        reason: 'moved HEAD must trigger a recompute, never serve stale');
    expect(after, isNot(before));
    expect(after, (await repo.head())!);
  });

  test('F3: concurrent calls share one compute and both get its result',
      () async {
    final gate = Completer<void>();
    final state = _HeadEchoState((r) async {
      await gate.future;
      return (await repo.head())!;
    });
    final a = state.freshValueFor(repo.dir.path);
    final b = state.freshValueFor(repo.dir.path);
    // Let both reach the gate, then release.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.complete();
    final results = await Future.wait([a, b]);
    expect(results[0], isNotNull);
    expect(results[0], results[1]);
    expect(state.computeCalls, 1,
        reason: 'second caller must wait on the in-flight load, not fork one');
  });

  test('F5: cold stuck compute is timeout-bounded, returns cache state',
      () async {
    final never = Completer<String>();
    final state = _HeadEchoState((r) => never.future);
    final sw = Stopwatch()..start();
    final v = await state.freshValueFor(repo.dir.path,
        timeout: const Duration(milliseconds: 300));
    sw.stop();
    expect(v, isNull, reason: 'nothing was ever computed');
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
        reason: 'the cold path must be bounded by the timeout, not hang');
    expect(state.computeCalls, 1);
    // A previously cached value survives a later stuck refresh: serve it.
    never.complete('unblocked');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('F5b: stale value served when the refresh is stuck, not a hang',
      () async {
    var calls = 0;
    final stick = Completer<String>();
    final state = _HeadEchoState((r) async {
      calls++;
      if (calls == 1) return (await repo.head())!;
      return stick.future;
    });
    final first = await state.freshValueFor(repo.dir.path);
    expect(first, isNotNull);
    // Move HEAD so the next call must refresh — but the refresh sticks.
    await repo.writeFile('s.txt', 'x\n');
    await repo.commitAll('move');
    final second = await state.freshValueFor(repo.dir.path,
        timeout: const Duration(milliseconds: 300));
    expect(second, first,
        reason: 'stuck refresh degrades to the stale value, never a hang');
    stick.complete('late');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('F4: freshEngineFor consults the resolver every call; failure surfaces',
      () async {
    final state = LogosGitState();
    var resolves = 0;
    state.resolveOverride = (repoPath, {coupling}) async {
      resolves++;
      return null; // resolution fails
    };
    final first = await state.freshEngineFor(repo.dir.path);
    expect(first, isNull);
    expect(state.errorFor(repo.dir.path), isNotNull);
    final second = await state.freshEngineFor(repo.dir.path);
    expect(second, isNull);
    expect(resolves, 2,
        reason: 'every fresh call must reach the resolver — its internal '
            'HEAD probe is the staleness authority, and probe-then-return '
            'around it was the bug');
  });
}
