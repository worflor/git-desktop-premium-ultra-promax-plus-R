// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// True-concurrency chaos harness.
//
// Every other fuzz/property suite in this repo awaits git operations
// strictly sequentially — one `await` per op, never two logical operations
// racing on the same repo. That leaves the app's real concurrency contract
// (the git subprocess semaphore is a THROTTLE, not a mutex; nothing
// serializes two logical ops on one repo) entirely uncovered.
//
// This file is the missing primitive: it starts N real operations with
// seeded jitter so their subprocesses actually overlap, captures every
// per-thunk outcome independently (one failure never hides another), and
// exposes invariant oracles the caller races against.
//
// DETERMINISM CONTRACT (important, easy to get wrong): the ONLY draws made
// from [Rng] during a raced scenario happen *before* the racing thunks are
// scheduled — [raceAll] draws every jitter value up-front, sequentially, in
// thunk order. A thunk MUST NOT itself draw from the shared [Rng] once the
// race is in flight: two thunks interleaving `rng.nextInt(...)` calls would
// record a nondeterministic tape and break replay/shrinking. Callers
// pre-draw all scenario randomness (file contents, counts, …) sequentially,
// then hand the racing thunks concrete, already-decided values. Everything
// here is built to make that the path of least resistance.

import 'package:flutter_test/flutter_test.dart';

import 'prop.dart';
import 'repo_topology.dart';
import 'scratch_repo.dart';

// ---------------------------------------------------------------------------
// Outcome algebra
// ---------------------------------------------------------------------------

/// The result of one raced thunk. Sealed so a caller `switch`es exhaustively
/// and can never silently drop the error arm — a raced failure is captured
/// here, never thrown, so one thunk's exception can't hide the other N-1
/// results (the whole point of racing is to see them all).
sealed class ChaosOutcome<T> {
  const ChaosOutcome();

  /// True for [Ok], false for [Err].
  bool get isOk;

  /// The value if this is an [Ok], else null. Convenience for the common
  /// "collect the successes" reduction; prefer a `switch` when the error
  /// matters.
  T? get valueOrNull;
}

/// The thunk completed with [value].
final class Ok<T> extends ChaosOutcome<T> {
  final T value;
  const Ok(this.value);

  @override
  bool get isOk => true;

  @override
  T? get valueOrNull => value;

  @override
  String toString() => 'Ok($value)';
}

/// The thunk threw [error] (with [stack]). Captured, never rethrown by
/// [raceAll], so the other raced thunks still report.
final class Err<T> extends ChaosOutcome<T> {
  final Object error;
  final StackTrace stack;
  const Err(this.error, this.stack);

  @override
  bool get isOk => false;

  @override
  T? get valueOrNull => null;

  @override
  String toString() => 'Err($error)';
}

// ---------------------------------------------------------------------------
// The racer
// ---------------------------------------------------------------------------

/// Starts every thunk in [thunks] with a tape-drawn jitter delay, then awaits
/// them all, returning one [ChaosOutcome] per thunk in input order.
///
/// The jitter (`0..maxJitterMs` ms per thunk) is what actually diversifies
/// the interleaving: without it every thunk would start on the same
/// microtask turn and the OS scheduler would see a near-identical race every
/// time. Each jitter value is drawn from [rng] *synchronously and
/// sequentially* here, before any thunk is scheduled — so the sequence of
/// draws is deterministic and the recorded tape replays exactly (see the
/// file-header determinism contract). A thunk that throws is captured into an
/// [Err]; a thunk that completes normally into an [Ok]. One thunk failing
/// never short-circuits the others (unlike a bare `Future.wait`, which
/// surfaces only the first error).
Future<List<ChaosOutcome<T>>> raceAll<T>(
  List<Future<T> Function()> thunks,
  Rng rng, {
  int maxJitterMs = 25,
}) {
  final futures = <Future<ChaosOutcome<T>>>[];
  for (final thunk in thunks) {
    final jitterMs = maxJitterMs <= 0 ? 0 : rng.intBetween(0, maxJitterMs);
    // Invoked immediately so the future is already scheduled; the jitter
    // await happens *inside* it, after every jitter draw above has been made.
    futures.add(() async {
      if (jitterMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: jitterMs));
      }
      try {
        return Ok<T>(await thunk());
      } catch (error, stack) {
        return Err<T>(error, stack);
      }
    }());
  }
  return Future.wait(futures);
}

/// Optional scheduling noise: a burst of `0..rounds` empty event-loop turns.
/// Sprinkling this between the phases of a racy scenario diversifies which
/// microtask boundary each awaited subprocess resumes on, surfacing
/// interleavings a fixed jitter alone would miss. Draws one value from [rng]
/// (recorded on the tape like any other choice), so it stays deterministic.
Future<void> yieldStorm(Rng rng, {int rounds = 6}) async {
  final n = rng.intBetween(0, rounds);
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Reductions
// ---------------------------------------------------------------------------

/// How many of [outcomes] completed (were [Ok]) — regardless of the value.
int countOk<T>(Iterable<ChaosOutcome<T>> outcomes) =>
    outcomes.where((o) => o.isOk).length;

/// Every [Err] among [outcomes], for a caller that wants to inspect the
/// captured exceptions (e.g. to prove none leaked, or to classify them).
Iterable<Err<T>> errorsOf<T>(Iterable<ChaosOutcome<T>> outcomes) =>
    outcomes.whereType<Err<T>>();

/// The values of every [Ok] among [outcomes]. Errors are dropped — pair with
/// [errorsOf] when the failures matter too.
List<T> valuesOf<T>(Iterable<ChaosOutcome<T>> outcomes) =>
    outcomes.whereType<Ok<T>>().map((o) => o.value).toList();

/// Interleavings to sample per CASE, for a law that draws cases through
/// [forAllAsync]. One race is one sample of one interleaving, and a bug
/// that shows on a fraction of interleavings needs several draws before
/// it appears — but the case count already carries [fuzzScale], so this
/// stays CONSTANT.
///
/// It used to be `3 × fuzzScale()`, which multiplied the same knob into
/// both dimensions: at `MANIFOLD_FUZZ=8` a law ran 64× the work against
/// a deadline that grew 8×, so the deep run could not finish no matter
/// how healthy the code was. A deep run that always times out is worse
/// than no deep run — it teaches you to ignore the suite.
const int chaosReps = 3;

/// Interleavings for a law that samples no cases at all — one fixed
/// scenario, repeated. Here the fuzz knob is the only dimension there
/// is, so it carries the depth.
int chaosRepsStandalone() => 3 * fuzzScale();

// ---------------------------------------------------------------------------
// Invariant oracle
// ---------------------------------------------------------------------------

/// The always-true post-condition for any sequence (raced or not) of git
/// operations against [r]: the object store is intact, HEAD resolves, and the
/// porcelain status parses. A red [assertRepoSane] after a race is a genuine
/// corruption bug, never a flaky-timing artifact.
///
/// Reuses [assertFsckClean] from repo_topology.dart rather than duplicating
/// the fsck invocation, so there is exactly one definition of "the object
/// database is clean" across the whole test tree.
Future<void> assertRepoSane(ScratchRepo r, {String? because}) async {
  // Object database + `.git` integrity.
  await assertFsckClean(r, because: because);

  // HEAD always resolves (ScratchRepo.create seeds a root commit).
  final head = await r.head();
  expect(head, isNotNull,
      reason: 'HEAD did not resolve'
          '${because == null ? '' : ' ($because)'}.');

  // The index/worktree state is *parseable* — a torn index left behind by a
  // racing writer would make even a read-only `status` fail.
  final status = await r.git(['status', '--porcelain']);
  expect(status.exitCode, 0,
      reason: 'git status --porcelain did not parse'
          '${because == null ? '' : ' ($because)'}.\n'
          'stderr: ${status.stderr}');
}
