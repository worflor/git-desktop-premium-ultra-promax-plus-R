// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Scripted `git` failures, injected at the one seam every git subprocess
// in this app passes through (`GitSpawn`). No real process is spawned, so
// a test can drive the retry/decode/recovery paths deterministically —
// including the ones a real machine would only hit under a race.

import 'dart:convert';
import 'dart:io';

import 'package:git_desktop/backend/git.dart';

/// Builds a successful raw-bytes [ProcessResult]. The seam contract
/// (`stdoutEncoding: null`) means a real `git` call hands back raw bytes,
/// not a decoded [String] — every scripted result must match that shape or
/// `_decodeGitBytes` (which special-cases non-`List<int>` input) silently
/// takes the wrong path.
ProcessResult gitOk([String stdout = '']) =>
    ProcessResult(0, 0, utf8.encode(stdout), const <int>[]);

/// Builds a failing raw-bytes [ProcessResult]. See [gitOk] for why the
/// bytes must be raw.
ProcessResult gitFail(int exitCode, String stderr) =>
    ProcessResult(0, exitCode, const <int>[], utf8.encode(stderr));

/// The exact stderr shape modern git (2.52) emits when another process — or
/// (on Windows) an antivirus scan briefly holding the file — owns
/// `index.lock`. Matches the fragments `_isIndexLockContention` in
/// lib/backend/git.dart checks for: `index.lock`, `File exists`, and
/// `Another git process`.
ProcessResult indexLockContention() => gitFail(
      128,
      "fatal: Unable to create '/repo/.git/index.lock': File exists.\n\n"
      "Another git process seems to be running in this repository. If this "
      "is not the case, ...",
    );

/// One recorded call into the fault-injection seam — every invocation a
/// [GitFaultScript] sees is appended here, in order, regardless of whether
/// it was scripted or delegated to real git.
class GitInvocation {
  final List<String> args;
  final String? workingDirectory;
  const GitInvocation(this.args, this.workingDirectory);

  @override
  String toString() => 'GitInvocation($args, cwd: $workingDirectory)';
}

/// Runs the REAL `git` binary. Used by [GitFaultScript] variants that only
/// fail some calls and delegate the rest — legitimate here specifically
/// because this code IS the override `GitSpawn.runOverride` replaces, so
/// calling `Process.run` directly is the only way to reach the real
/// subprocess once an override is installed.
Future<ProcessResult> _realGit(
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

/// A scripted, composable sequence of [GitSpawn] responses. Install with
/// [withGitFaults]. Every call the override receives — scripted or
/// delegated — is recorded to [invocations].
class GitFaultScript {
  GitFaultScript._(this._decide);

  /// [callIndex] is 1-based and counts every call this script has seen,
  /// scripted or delegated.
  final Future<ProcessResult> Function(
    List<String> args,
    String? workingDirectory,
    Map<String, String>? environment,
    int callIndex,
  ) _decide;

  final List<GitInvocation> invocations = <GitInvocation>[];
  int _callCount = 0;

  Future<ProcessResult> _handle(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    invocations.add(GitInvocation(args, workingDirectory));
    _callCount++;
    return _decide(args, workingDirectory, environment, _callCount);
  }

  /// The [n]th call (1-based, across every call this script sees) fails
  /// with [result]; every other call delegates to the real `git` binary.
  factory GitFaultScript.failNth(int n, ProcessResult Function() result) {
    return GitFaultScript._((args, workingDirectory, environment, callIndex) {
      if (callIndex == n) {
        return Future.value(result());
      }
      return _realGit(args,
          workingDirectory: workingDirectory, environment: environment);
    });
  }

  /// While [predicate] matches a call's argv AND fewer than [times]
  /// matching calls have already failed, fail with [result]. Once the
  /// budget is spent — or the predicate doesn't match — delegate to real
  /// git. Non-matching calls never consume the budget.
  factory GitFaultScript.failWhile(
    bool Function(List<String> args) predicate, {
    required int times,
    required ProcessResult Function() result,
  }) {
    var matchedFailures = 0;
    return GitFaultScript._((args, workingDirectory, environment, callIndex) {
      if (predicate(args) && matchedFailures < times) {
        matchedFailures++;
        return Future.value(result());
      }
      return _realGit(args,
          workingDirectory: workingDirectory, environment: environment);
    });
  }

  /// Every call gets [result] — never delegates to real git.
  factory GitFaultScript.always(
      ProcessResult Function(List<String> args) result) {
    return GitFaultScript._(
        (args, workingDirectory, environment, callIndex) =>
            Future.value(result(args)));
  }
}

/// Installs [script] as [GitSpawn.runOverride], runs [body], and ALWAYS
/// restores the seam afterward — even if [body] throws — via
/// [GitSpawn.reset]. Note that [GitSpawn.reset] also zeroes the spawn
/// counters, so a caller that needs to assert a spawn count must read
/// [GitSpawn.runCount] from inside [body], before it returns.
Future<T> withGitFaults<T>(
    GitFaultScript script, Future<T> Function() body) async {
  GitSpawn.runOverride = script._handle;
  try {
    return await body();
  } finally {
    GitSpawn.reset();
  }
}
