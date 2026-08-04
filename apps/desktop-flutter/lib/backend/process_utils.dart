// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:async';
import 'dart:io';

const Duration defaultProcessKillTimeout = Duration(seconds: 5);

/// Kill a process and its child tree when the platform exposes a tree-kill
/// primitive, and wait until termination is observed or [timeout] elapses.
///
/// On Unix this falls back to the direct child because Dart's [Process] API
/// does not expose the spawned process group. On Windows, `process.kill()`
/// sends SIGTERM which cmd.exe / .bat wrappers silently ignore, and it
/// does not walk the process tree; grandchild CLIs survive as orphans.
/// `taskkill /F /T /PID` force-kills the entire tree on Windows.
Future<bool> killProcessTree(
  Process process, {
  Duration timeout = defaultProcessKillTimeout,
}) async {
  if (Platform.isWindows) {
    try {
      final result = await Process.run(
        'taskkill',
        ['/F', '/T', '/PID', '${process.pid}'],
      ).timeout(timeout);
      if (result.exitCode == 0) {
        return _confirmExited(process, timeout);
      }
      // If the process exited between the timeout and taskkill, there is
      // nothing left to kill. Otherwise fall through to Dart's direct kill.
      if (!await isProcessAlive(process.pid)) {
        return true;
      }
    } catch (_) {
      // Fall back below. The caller gets a false result if exit is still
      // unobserved after the direct kill attempt.
    }
  }

  process.kill();
  return _confirmExited(process, timeout);
}

Future<bool> _confirmExited(Process process, Duration timeout) async {
  if (await _waitForExit(process, timeout)) {
    return true;
  }
  return !await isProcessAlive(process.pid);
}

Future<bool> _waitForExit(Process process, Duration timeout) async {
  try {
    await process.exitCode.timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  } catch (_) {
    return false;
  }
}

/// How long to keep trying to remove a file a just-killed child may still hold.
const Duration defaultHeldFileTimeout = Duration(seconds: 3);

/// Remove a file that a process we just terminated may still have open,
/// optionally blanking its contents first.
///
/// Windows releases handles asynchronously with respect to the exit we can
/// observe. `taskkill /F /T` returning 0, and the parent's `exitCode` future
/// completing, do not mean a grandchild that inherited a redirected handle has
/// let go of it yet. A single unlink attempt therefore fails intermittently,
/// and the usual `try { delete } catch (_) {}` converts that into a silent
/// leak: the file survives, and for a redirected stdin payload that means the
/// contents stay on disk indefinitely. Blanking has the identical race, so a
/// one-shot blank is not a safety net either.
///
/// Retries both steps until [timeout] elapses. Returns whether the file is
/// actually gone, so callers can tell a clean removal from a genuine residue
/// instead of assuming success.
Future<bool> deleteFileHeldByExitingChild(
  File file, {
  Duration timeout = defaultHeldFileTimeout,
  bool blankFirst = false,
}) async {
  final deadline = DateTime.now().add(timeout);
  var backoff = const Duration(milliseconds: 10);
  var blanked = false;
  while (true) {
    // Shrink the exposure window as soon as the handle allows it, even if the
    // unlink below has to wait another round.
    if (blankFirst && !blanked) {
      try {
        file.writeAsStringSync('', flush: true);
        blanked = true;
      } catch (_) {
        // Still held; try again on the next pass.
      }
    }
    try {
      if (!file.existsSync()) return true;
      file.deleteSync();
      return true;
    } catch (_) {
      if (!DateTime.now().isBefore(deadline)) {
        // Out of budget. Report the truth rather than pretending.
        return !file.existsSync();
      }
      await Future<void>.delayed(backoff);
      if (backoff < const Duration(milliseconds: 160)) backoff *= 2;
    }
  }
}

/// Check whether a process with [pid] is still running.
/// Windows: `tasklist /FI "PID eq ..."`. Unix: `kill -0`.
Future<bool> isProcessAlive(int pid) async {
  try {
    if (Platform.isWindows) {
      final r = await Process.run(
        'tasklist',
        ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV'],
      );
      return r.stdout.toString().contains('"$pid"');
    } else {
      final r = await Process.run('kill', ['-0', '$pid']);
      return r.exitCode == 0;
    }
  } catch (_) {
    return false;
  }
}
