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
