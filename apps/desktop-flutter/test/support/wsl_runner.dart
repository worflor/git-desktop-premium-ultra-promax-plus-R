// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// wsl_runner.dart — generalized WSL2 execution plumbing, extracted from
// test/fuzz/cross_os_differential_test.dart (that file is left untouched;
// this is a faithful extraction of its WSL-invocation mechanics into a
// reusable shape for other Windows->WSL2 differential harnesses).
//
// ISOLATION — WHY A LINUX-NATIVE WORKTREE, AND WHY IT MUST NEVER TOUCH /mnt/c
//   Running `flutter pub get` / `flutter test` (or any other Linux-side
//   Dart/Flutter invocation) from WSL directly against this project's
//   /mnt/c working tree rewrites `.dart_tool/package_config.json` with
//   Linux paths and silently breaks the Windows toolchain — every
//   subsequent Windows `flutter` invocation then fails to resolve packages
//   until `flutter pub get` is re-run on Windows. To make this impossible
//   instead of merely "remembered", any Linux-side Dart/Flutter run always
//   operates inside a separate linked git worktree at a Linux-native path
//   (/root/manifold-osdiff) — its own `.dart_tool` lives there, on the
//   Linux filesystem, entirely disjoint from the Windows one. Nothing in
//   this file ever invokes `flutter`/`dart`/`pub` against a `/mnt/c` path;
//   [runInWsl] itself is toolchain-agnostic (plain bash), and
//   [runLinuxTestAndSliceJson] only ever points `flutter` at
//   [syncedLinuxProjectDir]'s Linux-native return value.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Linux-native path (inside the WSL2 Ubuntu filesystem, NOT /mnt/c) for
/// the isolated worktree Linux-side Dart/Flutter runs operate in. Reused
/// across runs (checked out fresh to the current HEAD each time) so
/// repeat runs don't pay a cold `flutter pub get` every time.
const String kLinuxWorktree = '/root/manifold-osdiff';

bool? _wslAvailableCache;

/// Quick, synchronous, side-effect-free-on-failure feasibility probe for a
/// WSL2 distro with a native-Linux Flutter/Dart SDK at /root/flutter.
/// Cached after the first call for the lifetime of the process. Only ever
/// called by an already opted-in caller, so a default `flutter test` run
/// never spawns wsl.exe.
bool wslAvailable() {
  final cached = _wslAvailableCache;
  if (cached != null) return cached;
  bool result;
  try {
    final r = Process.runSync('wsl.exe', [
      '-e',
      'bash',
      '-lc',
      'ls /root/flutter/bin/dart',
    ]);
    result = r.exitCode == 0;
  } catch (_) {
    result = false;
  }
  _wslAvailableCache = result;
  return result;
}

/// Convert a Windows absolute path (as Dart/`Directory.current` sees it)
/// to its WSL `/mnt/<drive>/...` equivalent.
String windowsPathToWsl(String winPath) {
  final normalized = winPath.replaceAll('\\', '/');
  final m = RegExp(r'^([A-Za-z]):/(.*)$').firstMatch(normalized);
  if (m == null) return normalized;
  final drive = m.group(1)!.toLowerCase();
  return '/mnt/$drive/${m.group(2)}';
}

/// Quote one value for bash without relying on its contents being space-free.
String _bashQuote(String value) => "'${value.replaceAll("'", "'\\\"'\\\"'")}'";

/// Runs [bashScript] as `wsl.exe -e bash -lc <bashScript>` and returns its
/// stdout. Throws a [StateError] (with both stdout and stderr folded into
/// the message) on a nonzero exit, and a [TimeoutException] if [timeout]
/// elapses first.
Future<String> runInWsl(
  String bashScript, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final result =
      await Process.run(
        'wsl.exe',
        ['-e', 'bash', '-lc', bashScript],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'wsl.exe bash script exceeded ${timeout.inSeconds}s:\n$bashScript',
        ),
      );
  final stdout = result.stdout as String;
  final stderr = result.stderr as String;
  if (result.exitCode != 0) {
    throw StateError(
      'wsl.exe bash script failed (exit ${result.exitCode}):\n'
      '--- script ---\n$bashScript\n'
      '--- stdout ---\n$stdout\n'
      '--- stderr ---\n$stderr',
    );
  }
  return stdout;
}

/// Prunes stale worktree bookkeeping, then creates (or fast-forwards an
/// existing) linked git worktree at [kLinuxWorktree], checked out to the
/// current Windows working tree's HEAD, syncs the LIVE `lib/` and
/// `test/support/` directories into it (so uncommitted local edits are
/// exercised too, not just what's committed), and returns the Linux-native
/// path of the Flutter *project* directory inside that worktree — which is
/// the worktree root plus this project's monorepo-relative subpath,
/// computed at runtime exactly as
/// test/fuzz/cross_os_differential_test.dart does, since `git worktree add`
/// always checks out the WHOLE repository from its top level.
Future<String> syncedLinuxProjectDir() async {
  final repoPathWin = Directory.current.path;
  final repoPathWsl = windowsPathToWsl(repoPathWin);

  final headShaResult = await Process.run('git', ['rev-parse', 'HEAD']);
  if (headShaResult.exitCode != 0) {
    throw StateError('could not resolve current HEAD: ${headShaResult.stderr}');
  }
  final headSha = (headShaResult.stdout as String).trim();

  final toplevelResult = await Process.run('git', [
    'rev-parse',
    '--show-toplevel',
  ]);
  if (toplevelResult.exitCode != 0) {
    throw StateError(
      'could not resolve repo top-level: ${toplevelResult.stderr}',
    );
  }
  final topLevelWsl = windowsPathToWsl(
    (toplevelResult.stdout as String).trim(),
  );
  var relSubpath = repoPathWsl.startsWith(topLevelWsl)
      ? repoPathWsl.substring(topLevelWsl.length)
      : '';
  relSubpath = relSubpath.replaceFirst(RegExp(r'^/+'), '');
  final linuxProjectDir = relSubpath.isEmpty
      ? kLinuxWorktree
      : '$kLinuxWorktree/$relSubpath';

  final repo = _bashQuote(repoPathWsl);
  final worktree = _bashQuote(kLinuxWorktree);
  await runInWsl('git -C $repo worktree prune');

  final existsCheck = await runInWsl(
    'test -e $worktree && echo EXISTS || echo MISSING',
  );
  final exists = existsCheck.contains('EXISTS');

  var usable = false;
  if (exists) {
    final check = await runInWsl(
      'git -C $worktree rev-parse --is-inside-work-tree '
      '2>/dev/null || echo INVALID',
    );
    usable = check.split('\n').any((line) => line.trim() == 'true');
  }

  if (!usable) {
    // A cached directory can outlive (or point at) stale linked-worktree
    // metadata. Remove both halves before recreating it; merely pruning the
    // Windows-side registration cannot repair the Linux `.git` backpointer.
    await runInWsl(
      'git -C $repo worktree remove --force $worktree 2>/dev/null || true\n'
      'rm -rf -- $worktree\n'
      'git -C $repo worktree prune',
    );
    await runInWsl(
      'git -C $repo worktree add --detach -f $worktree '
      '${_bashQuote(headSha)}',
    );
  } else {
    await runInWsl(
      'git -C $worktree checkout --detach -f ${_bashQuote(headSha)}',
    );
  }

  // Read-only against /mnt/c; no `flutter`/`dart` is ever invoked against
  // /mnt/c — this only ever copies files out of it.
  await runInWsl(
    "rm -rf '$linuxProjectDir/lib' '$linuxProjectDir/test/support' && "
    "mkdir -p '$linuxProjectDir/test' && "
    "cp -r '$repoPathWsl/lib' '$linuxProjectDir/lib' && "
    "cp -r '$repoPathWsl/test/support' '$linuxProjectDir/test/support'",
  );

  return linuxProjectDir;
}

/// Runs `flutter test <testRelPath>` inside [syncedLinuxProjectDir] with
/// `PATH=/root/flutter/bin:$PATH`, then slices out and JSON-decodes the
/// payload the target test printed between [beginMarker] and [endMarker].
/// Mirrors test/fuzz/cross_os_differential_test.dart's own marker-slicing:
/// only the presence of both markers is checked, not the process exit
/// code, since a `flutter test` run can legitimately exit nonzero (a
/// failed `expect` after the marker print) while still having emitted a
/// perfectly good payload worth inspecting.
Future<Map<String, Object?>> runLinuxTestAndSliceJson(
  String testRelPath, {
  String beginMarker = 'OSPROBE_BEGIN',
  String endMarker = 'OSPROBE_END',
  Duration timeout = const Duration(minutes: 15),
}) async {
  final linuxProjectDir = await syncedLinuxProjectDir();
  final runScript =
      'export PATH=/root/flutter/bin:\$PATH\n'
      "cd '$linuxProjectDir'\n"
      'flutter pub get\n'
      'flutter test $testRelPath\n';

  final testRun =
      await Process.run(
        'wsl.exe',
        ['-e', 'bash', '-lc', runScript],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Linux test run ($testRelPath) exceeded ${timeout.inMinutes} '
          'minutes',
        ),
      );

  final stdout = testRun.stdout as String;
  final beginIdx = stdout.indexOf(beginMarker);
  final endIdx = stdout.indexOf(endMarker);
  if (beginIdx < 0 || endIdx <= beginIdx) {
    throw StateError(
      'Linux test run did not emit $beginMarker/$endMarker markers '
      '(exitCode=${testRun.exitCode}). Full stdout:\n$stdout\n'
      '--- stderr ---\n${testRun.stderr}',
    );
  }
  final jsonStr = stdout.substring(beginIdx + beginMarker.length, endIdx);
  return jsonDecode(jsonStr) as Map<String, Object?>;
}

/// Best-effort teardown: removes [kLinuxWorktree] via `git worktree
/// remove --force`. Never throws — cleanup failure must never fail a
/// suite.
Future<void> removeLinuxWorktree() async {
  try {
    final repoPathWsl = windowsPathToWsl(Directory.current.path);
    await Process.run('wsl.exe', [
      '-e',
      'bash',
      '-lc',
      "git -C '$repoPathWsl' worktree remove --force $kLinuxWorktree "
          '2>/dev/null || true',
    ]);
  } catch (_) {
    // Best-effort only — cleanup failure must never fail the suite.
  }
}
