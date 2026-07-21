// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// A DETERMINISTIC concurrency scheduler built on the one seam every git
// subprocess in this app passes through: `GitSpawn.runOverride` /
// `GitSpawn.startOverride` (lib/backend/git.dart). Sibling to
// test/support/git_faults.dart — that file scripts FAILURES at the seam; this
// file scripts ORDERING at the seam.
//
// WHY IT EXISTS. The chaos harness (test/support/chaos.dart) races real ops
// with random jitter, so its findings reproduce only probabilistically. But
// every git operation's ONLY yield points are its subprocess spawns, and the
// app owns that boundary. If a test can park a specific spawn *before* its
// real subprocess is created and release it on command, the interleaving is
// no longer sampled — it is CHOSEN. That turns a ~60%-repro race into a
// 100%-repro pin.
//
// CONTRACT (read before trusting a scenario):
//   * The barrier serializes at SPAWN BOUNDARIES ONLY. It parks a call just
//     before `Process.run`/`Process.start` is invoked and delegates to the
//     real binary on release. It CANNOT freeze a live child process
//     mid-execution — once real git is running, it runs to completion. When a
//     scenario needs a mid-FLIGHT condition (e.g. an `index.lock` already
//     held), combine this with git_faults' canned results
//     (`indexLockContention()`), which is what [GitStartFault] below does for
//     the `Process.start` seam that git_faults doesn't cover.
//   * Holding a `Process.start` call parks it BEFORE the real `Process.start`
//     returns, so the caller's post-spawn stdin writes have not happened yet.
//     A held `applyPatch` has therefore NOT touched the index — verified
//     against git.dart:4791 (`await _spawnStart(...)` precedes every
//     `process.stdin.add`).
//   * WHAT THE SEAM DOES NOT SEE. `ManifoldRefs.writeBlob` / `mkTree`
//     (manifold_refs.dart) call `Process.start` DIRECTLY, not through
//     `_spawnStart`, so they bypass this barrier (and git_faults) entirely.
//     Only the calls that route through `runGit`/`applyPatch` — `update-ref`,
//     `commit-tree`, `rev-parse`, `cat-file`, `for-each-ref`, `config`,
//     `apply` — are gate-able. Design every scenario around that reality.
//
// Discipline: always `dispose()` in tearDown. dispose releases every
// still-parked call (so a failed assertion can never hang the suite) and
// restores the seam via `GitSpawn.reset()`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:git_desktop/backend/git.dart';

/// Zone key an op can carry so the barrier can label which logical operation
/// each spawn belongs to (see [runTagged]). The seam override runs inside the
/// op's async continuation, which preserves the zone across `await`, so the
/// tag survives all the way down to the `Process.start`/`Process.run` call.
const Symbol gitBarrierTagKey = #gitBarrierTag;

/// Runs [body] tagged with [tag] so every git spawn it makes is attributed to
/// [tag] in the barrier's records and step scheduler. [body] typically returns
/// a `Future`; the future is returned untouched (this does NOT await it), so a
/// caller can start several tagged ops and interleave them.
T runTagged<T>(String tag, T Function() body) =>
    runZoned(body, zoneValues: {gitBarrierTagKey: tag});

/// One call the barrier saw at the seam, in arrival order. Mirrors
/// git_faults' [GitInvocation] but also records whether it came through the
/// `Process.start` seam ([isStart]) and its [tag] (see [runTagged]).
class GitInvocationLike {
  final List<String> args;
  final String? workingDirectory;

  /// True when this came through `GitSpawn.startOverride` (`Process.start` —
  /// e.g. `applyPatch`), false for `GitSpawn.runOverride` (`Process.run`).
  final bool isStart;

  /// The [runTagged] label active when the spawn was made, or null.
  final String? tag;

  const GitInvocationLike(
    this.args, {
    required this.workingDirectory,
    required this.isStart,
    required this.tag,
  });

  @override
  String toString() =>
      'GitInvocationLike($args, cwd: $workingDirectory, '
      'start: $isStart, tag: $tag)';
}

// ---------------------------------------------------------------------------
// Real-git delegation — the barrier IS the override, so reaching the real
// binary means calling Process.run/start directly (same rationale as
// git_faults._realGit). These are the ONLY spawns the barrier makes.
// ---------------------------------------------------------------------------

Future<ProcessResult> _realRun(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
    environment: environment,
    stdoutEncoding: null,
    stderrEncoding: null,
  );
}

Future<Process> _realStart(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
  ProcessStartMode mode = ProcessStartMode.normal,
}) {
  return Process.start(
    'git',
    args,
    workingDirectory: workingDirectory,
    environment: environment,
    mode: mode,
  );
}

// ---------------------------------------------------------------------------
// A parked spawn: the barrier captured it and is holding it before the real
// subprocess is created. Completing [_release] lets it proceed.
// ---------------------------------------------------------------------------

class _Parked {
  final GitInvocationLike invocation;

  /// Completed to let the parked call proceed to its real subprocess.
  final Completer<void> release = Completer<void>();

  /// Completed by the barrier once the real subprocess has FINISHED (run
  /// seam: `Process.run` returned; start seam: the child's `exitCode`
  /// resolved). This is what lets [StepGate.releaseNext] serialize schedules
  /// with zero child-process overlap even though the barrier cannot freeze a
  /// live child.
  final Completer<void> done = Completer<void>();
  _Parked(this.invocation);
}

/// A one-shot hold on the NEXT invocation matching a predicate. Returned by
/// [GitBarrier.holdWhere].
class Gate {
  Gate._(this._predicate);

  final bool Function(GitInvocationLike inv) _predicate;
  final Completer<void> _heldC = Completer<void>();
  _Parked? _parked;
  bool _released = false;

  /// Completes when the matching invocation has been captured and parked
  /// (before its real subprocess is spawned).
  Future<void> get held => _heldC.future;

  /// True once a matching invocation has been parked.
  bool get isHeld => _parked != null;

  /// Releases the parked invocation so it proceeds to the real subprocess.
  /// Idempotent and safe to call even if nothing was parked yet (the release
  /// is remembered and applied on capture).
  void release() {
    _released = true;
    final p = _parked;
    if (p != null && !p.release.isCompleted) p.release.complete();
  }

  void _capture(_Parked p) {
    _parked = p;
    if (!_heldC.isCompleted) _heldC.complete();
    // Honour a release() that arrived before the capture.
    if (_released && !p.release.isCompleted) p.release.complete();
  }
}

/// A held op plus its still-pending future. Returned by [GitBarrier.runToHold].
///
/// Dart auto-flattens nested futures, so a function returning `Future<T>`
/// cannot hand back a *pending* `T`-future without awaiting it — awaiting a
/// parked op would deadlock. This holder keeps the op future un-flattened so
/// the caller can release the gate and only then await completion.
class HeldOp<T> {
  /// The op's still-pending future — do not await until you have released the
  /// gate (directly or via [GitBarrier.dispose]).
  final Future<T> future;
  const HeldOp(this.future);
}

/// A multi-park stepping scheduler over every invocation matching a predicate.
/// Returned by [GitBarrier.holdAll]. Unlike [Gate], it captures EVERY match
/// and lets the caller release them one at a time, in any order that respects
/// each op's own program order (an op blocks at its current spawn until
/// released, so its next spawn cannot appear until you let the current one
/// through). This is the primitive that enumerates interleavings.
class StepGate {
  StepGate._();

  final List<_Parked> _parked = <_Parked>[];
  final List<void Function()> _waiters = <void Function()>[];
  bool _disposed = false;

  int get parkedCount => _parked.length;

  void _capture(_Parked p) {
    _parked.add(p);
    // Wake anyone waiting for a park; copy so a waiter re-registering mid-notify
    // is safe.
    for (final w in List<void Function()>.of(_waiters)) {
      w();
    }
  }

  /// Completes once at least one invocation tagged [tag] is currently parked.
  Future<void> awaitParked(String tag) {
    if (_hasParked(tag)) return Future<void>.value();
    final c = Completer<void>();
    void check() {
      if (_disposed || _hasParked(tag)) {
        _waiters.remove(check);
        if (!c.isCompleted) c.complete();
      }
    }

    _waiters.add(check);
    return c.future;
  }

  bool _hasParked(String tag) =>
      _parked.any((p) => p.invocation.tag == tag);

  /// Releases the OLDEST parked invocation tagged [tag] and returns a future
  /// that completes when that call's real subprocess has FINISHED — so a
  /// caller that awaits it realizes a strictly serial schedule (no two git
  /// children ever run at once, hence no `index.lock` contention). Throws
  /// [StateError] if none is parked; pair with [awaitParked] to stay
  /// deterministic.
  Future<void> releaseNext(String tag) {
    final idx = _parked.indexWhere((p) => p.invocation.tag == tag);
    if (idx < 0) {
      throw StateError('releaseNext($tag): no parked invocation for that tag');
    }
    final p = _parked.removeAt(idx);
    if (!p.release.isCompleted) p.release.complete();
    return p.done.future;
  }

  /// Releases everything still parked (teardown safety).
  void releaseAll() {
    _disposed = true;
    for (final p in _parked) {
      if (!p.release.isCompleted) p.release.complete();
    }
    _parked.clear();
    for (final w in List<void Function()>.of(_waiters)) {
      w();
    }
    _waiters.clear();
  }
}

// ---------------------------------------------------------------------------
// The barrier
// ---------------------------------------------------------------------------

/// Composes `GitSpawn.runOverride` AND `GitSpawn.startOverride`: records every
/// invocation in order, parks the ones a registered [Gate]/[StepGate] wants,
/// and delegates the rest (and released ones) to the real `git` binary.
class GitBarrier {
  GitBarrier._();

  /// Every invocation the barrier saw, in arrival order — scripted-held or
  /// delegated. Read after a scenario to assert what the seam actually saw
  /// (e.g. that `writeBlob`'s direct `Process.start` is absent).
  final List<GitInvocationLike> invocations = <GitInvocationLike>[];

  final List<Gate> _gates = <Gate>[];
  final List<_StepHold> _stepHolds = <_StepHold>[];
  bool _installed = false;

  /// Installs the barrier at the seam. Any prior overrides are cleared (the
  /// production default is null); [dispose] restores that null state.
  static GitBarrier install() {
    final b = GitBarrier._();
    b._installed = true;
    GitSpawn.runOverride = b._handleRun;
    GitSpawn.startOverride = b._handleStart;
    return b;
  }

  String? get _currentTag {
    final tag = Zone.current[gitBarrierTagKey];
    return tag is String ? tag : null;
  }

  Future<ProcessResult> _handleRun(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final inv = GitInvocationLike(args,
        workingDirectory: workingDirectory, isStart: false, tag: _currentTag);
    invocations.add(inv);
    final parked = await _maybePark(inv);
    final result = await _realRun(args,
        workingDirectory: workingDirectory, environment: environment);
    // `Process.run` returned == the subprocess has fully finished.
    if (parked != null && !parked.done.isCompleted) parked.done.complete();
    return result;
  }

  Future<Process> _handleStart(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    final inv = GitInvocationLike(args,
        workingDirectory: workingDirectory, isStart: true, tag: _currentTag);
    invocations.add(inv);
    // Park BEFORE the real Process.start, so a held start has not yet had its
    // stdin written (the index is untouched while held — see the contract).
    final parked = await _maybePark(inv);
    final proc = await _realStart(args,
        workingDirectory: workingDirectory, environment: environment, mode: mode);
    // A started child keeps running; "finished" is its exit, not the return
    // of start(). Signal completion on exit so a step schedule can serialize
    // against the child's actual work (e.g. applyPatch's index write).
    if (parked != null) {
      unawaited(proc.exitCode.whenComplete(() {
        if (!parked.done.isCompleted) parked.done.complete();
      }));
    }
    return proc;
  }

  /// If any registered hold wants [inv], park it until released and return the
  /// [_Parked] handle (so the caller can signal subprocess completion). The
  /// FIRST hold (in registration order) that claims it wins; unclaimed calls
  /// flow straight through and return null.
  Future<_Parked?> _maybePark(GitInvocationLike inv) async {
    // One-shot gates first.
    for (final g in _gates) {
      if (g._parked == null && g._predicate(inv)) {
        final parked = _Parked(inv);
        g._capture(parked);
        await parked.release.future;
        return parked;
      }
    }
    // Then the multi-park step holds.
    for (final h in _stepHolds) {
      if (h.predicate(inv)) {
        final parked = _Parked(inv);
        h.gate._capture(parked);
        await parked.release.future;
        return parked;
      }
    }
    return null;
  }

  /// Parks the NEXT invocation matching [predicate] before its real subprocess
  /// is spawned, until the returned [Gate] is released.
  Gate holdWhere(bool Function(GitInvocationLike inv) predicate) {
    final g = Gate._(predicate);
    _gates.add(g);
    return g;
  }

  /// Parks EVERY invocation matching [predicate] and returns a [StepGate] for
  /// releasing them one at a time — the interleaving-enumeration primitive.
  StepGate holdAll(bool Function(GitInvocationLike inv) predicate) {
    final gate = StepGate._();
    _stepHolds.add(_StepHold(predicate, gate));
    return gate;
  }

  /// Starts [op], waits until [gate] has parked a matching spawn, and hands
  /// back the still-pending op future in a [HeldOp]. The op is now frozen at
  /// its parked spawn; do other work, then `gate.release()` and await
  /// `heldOp.future`.
  Future<HeldOp<T>> runToHold<T>(
      Future<T> Function() op, Gate gate) async {
    final future = op();
    await gate.held;
    return HeldOp<T>(future);
  }

  /// Releases every still-parked call and restores the seam. Safe to call more
  /// than once; always call it in tearDown so a mid-scenario failure cannot
  /// leave a parked spawn hanging the suite.
  void dispose() {
    for (final g in _gates) {
      g.release();
    }
    for (final h in _stepHolds) {
      h.gate.releaseAll();
    }
    _gates.clear();
    _stepHolds.clear();
    if (_installed) {
      GitSpawn.reset();
      _installed = false;
    }
  }
}

class _StepHold {
  final bool Function(GitInvocationLike inv) predicate;
  final StepGate gate;
  _StepHold(this.predicate, this.gate);
}

// ---------------------------------------------------------------------------
// Start-seam fault injection — git_faults covers the run seam; this covers the
// Process.start seam (applyPatch) so a scenario can put a mid-flight condition
// like `index.lock` in front of a bypass that git_faults cannot reach.
// ---------------------------------------------------------------------------

/// A canned, already-exited [Process] built from a [ProcessResult] shape.
/// `applyPatch` writes to [stdin] (drained + discarded), reads [stderr] and
/// awaits [exitCode] — so a failing apply is faithfully reproduced without a
/// real subprocess.
class _CannedProcess implements Process {
  _CannedProcess(this._exitCode, this._stdout, this._stderr) {
    // Discard whatever the caller pipes in; a real failed apply would have
    // consumed (or ignored) it too.
    _stdinController.stream.drain<void>();
    _stdin = IOSink(_stdinController.sink);
  }

  final int _exitCode;
  final List<int> _stdout;
  final List<int> _stderr;
  // Closed by the caller (`applyPatch` calls `stdin.close()`), which closes
  // the IOSink and therefore this controller; the analyzer can't see that.
  // ignore: close_sinks
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  // ignore: close_sinks
  late final IOSink _stdin;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => Stream<List<int>>.value(_stdout);

  @override
  Stream<List<int>> get stderr => Stream<List<int>>.value(_stderr);

  @override
  Future<int> get exitCode => Future<int>.value(_exitCode);

  @override
  int get pid => -1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

/// Installs a `GitSpawn.startOverride` that fails the first [times] invocations
/// whose argv matches [predicate] with a canned failing [Process] built from
/// [result], delegating every other start to the real binary. [matchCount]
/// counts how many matching starts were served the fault — a test asserts
/// `matchCount == 1` to prove a bypass made exactly ONE attempt (i.e. did NOT
/// retry). Always [dispose] in tearDown.
class GitStartFault {
  GitStartFault._(this.predicate, this._result, this._times);

  final bool Function(List<String> args) predicate;
  final ProcessResult Function() _result;
  final int _times;
  bool _installed = false;

  /// How many matching starts have been served the scripted fault so far.
  int matchCount = 0;

  static GitStartFault install({
    required bool Function(List<String> args) predicate,
    required ProcessResult Function() result,
    int times = 1,
  }) {
    final f = GitStartFault._(predicate, result, times);
    f._installed = true;
    GitSpawn.startOverride = f._handle;
    return f;
  }

  Future<Process> _handle(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    if (predicate(args) && matchCount < _times) {
      matchCount++;
      final r = _result();
      final stdoutBytes = _asBytes(r.stdout);
      final stderrBytes = _asBytes(r.stderr);
      return Future<Process>.value(
          _CannedProcess(r.exitCode, stdoutBytes, stderrBytes));
    }
    return _realStart(args,
        workingDirectory: workingDirectory, environment: environment, mode: mode);
  }

  void dispose() {
    if (_installed) {
      GitSpawn.reset();
      _installed = false;
    }
  }
}

List<int> _asBytes(Object? streamField) {
  if (streamField is List<int>) return streamField;
  if (streamField is String) return utf8.encode(streamField);
  return const <int>[];
}
