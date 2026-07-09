// cross_os_differential_test.dart — catches Windows-vs-Linux divergence in
// functions that LOOK OS-invariant (paths passed in explicitly, no ambient
// Platform reads) but might secretly not be: a hidden `\` assumption, a
// locale-sensitive case-fold or sort, a CRLF/LF assumption, or float drift
// in a numeric routine that happens to route through the native libm.
//
// THE APPROACH
//   1. test/support/os_probe_corpus.dart is a single pure function,
//      `computeOsProbe()`, that runs a fixed adversarial corpus through
//      every OS-sensitive pure function this app ships and returns one
//      flat JSON-serializable map.
//   2. This test calls it in-process for the WINDOWS side (this file only
//      ever runs `flutter test` on Windows).
//   3. For the LINUX side, it shells out to WSL2 (Ubuntu, with a
//      native-Linux Flutter/Dart toolchain at /root/flutter — NOT the
//      /mnt/c passthrough of the Windows toolchain) and runs the exact
//      same corpus via test/support/os_probe_main.dart.
//   4. The two flat maps are diffed key-by-key. Ordinary keys must match
//      EXACTLY across OSes — any mismatch is a genuine cross-OS bug.
//      Keys prefixed `INTENTIONAL::` read ambient Platform.isWindows by
//      design (see LogosSseStore.lockKeyFor) and are instead checked
//      against each OS's own expected value.
//
// NOTE ON THE WORKTREE'S CONTENT: `git worktree add` only materializes
// COMMITTED content, and only checks out the WHOLE repository from its
// top level (this project lives inside a monorepo, so the worktree root
// is the monorepo root, not this Flutter project's directory — the
// project's actual subpath is computed at runtime). Since the probe
// files themselves may be mid-iteration and uncommitted, this test also
// copies test/support/os_probe_corpus.dart and os_probe_main.dart
// byte-for-byte from the live Windows working tree into the worktree
// after checkout, so the Linux run always executes the exact same probe
// source this run's Windows side just ran in-process — a stronger and
// simpler guarantee than "make sure to commit first".
//
// ISOLATION — WHY A WORKTREE, AND WHY IT MUST NEVER TOUCH /mnt/c
//   Running `flutter pub get` / `flutter test` from WSL directly against
//   this /mnt/c working tree rewrites `.dart_tool/package_config.json`
//   with Linux paths and silently breaks the Windows toolchain (every
//   subsequent Windows `flutter` invocation fails to resolve packages
//   until `flutter pub get` is re-run on Windows). To make this
//   impossible instead of merely "remembered", the Linux side always
//   operates inside a separate linked git worktree at a Linux-native
//   path (/root/manifold-osdiff) — its own `.dart_tool` lives there, on
//   the Linux filesystem, entirely disjoint from the Windows one. This
//   file's Dart code never invokes `flutter` directly against
//   Directory.current; it only ever does so through `wsl.exe` against
//   that separate worktree path.
//
// RUNNING THIS TEST
//   Opt-in only (multi-minute — spins up WSL2, runs `flutter pub get` +
//   `flutter test` on a cold-ish cache the first time):
//     export MANIFOLD_CROSS_OS=1
//     "C:/flutter/flutter/bin/flutter.bat" test test/fuzz/cross_os_differential_test.dart
//   Any other invocation (plain `flutter test`, or this file targeted
//   without the env var, or run on a non-Windows host) skips instantly
//   without spawning wsl.exe or touching WSL/the worktree at all.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/os_probe_corpus.dart';

/// Linux-native path (inside the WSL2 Ubuntu filesystem, NOT /mnt/c) for
/// the isolated worktree the Linux probe run operates in. Reused across
/// runs (checked out fresh to the current HEAD each time) so repeat runs
/// don't pay a cold `flutter pub get` every time.
const String _kLinuxWorktree = '/root/manifold-osdiff';

bool get _envOptIn => Platform.environment['MANIFOLD_CROSS_OS'] == '1';

/// Convert a Windows absolute path (as Dart/`Directory.current` sees it)
/// to its WSL `/mnt/<drive>/...` equivalent.
String _windowsPathToWsl(String winPath) {
  final normalized = winPath.replaceAll('\\', '/');
  final m = RegExp(r'^([A-Za-z]):/(.*)$').firstMatch(normalized);
  if (m == null) return normalized;
  final drive = m.group(1)!.toLowerCase();
  return '/mnt/$drive/${m.group(2)}';
}

/// Quick, synchronous, side-effect-free-on-failure feasibility probe.
/// Only ever called when already opted in via env var, so a default
/// `flutter test` run (no MANIFOLD_CROSS_OS) never spawns wsl.exe.
bool _wslToolchainAvailable() {
  try {
    final r = Process.runSync(
      'wsl.exe',
      ['-e', 'bash', '-lc', 'ls /root/flutter/bin/dart'],
    );
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

bool _computeShouldRun() {
  if (!Platform.isWindows) return false;
  if (!_envOptIn) return false;
  return _wslToolchainAvailable();
}

String _computeSkipReason(bool wslProbed) {
  if (!Platform.isWindows) {
    return 'cross-OS differential only runs FROM Windows (it compares '
        'the live Windows process against a WSL2 Linux run)';
  }
  if (!_envOptIn) {
    return 'opt-in only — this run is multi-minute (spins up WSL2, runs '
        'flutter pub get + flutter test on Linux). Set MANIFOLD_CROSS_OS=1 '
        'to run it.';
  }
  return 'WSL2 Ubuntu with a Flutter/Dart SDK at /root/flutter was not '
      'reachable (`wsl.exe -e bash -lc "ls /root/flutter/bin/dart"` '
      'failed) — skipping gracefully rather than failing the suite on an '
      'unrelated machine';
}

/// Deep structural equality across the two shapes we compare:
///   - the Windows side: whatever Dart types [computeOsProbe] produced
///     directly (String, int, bool, null, List, Map).
///   - the Linux side: the same values after a JSON encode (on Linux) +
///     JSON decode (here) round-trip.
/// `Map`/`List` don't get `==` for free in Dart, so this recurses.
bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!_deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

String _renderValue(Object? v) {
  final s = jsonEncode(v);
  return s.length > 300 ? '${s.substring(0, 300)}…' : s;
}

void main() {
  final shouldRun = _computeShouldRun();
  final skipReason = shouldRun ? null : _computeSkipReason(shouldRun);

  // Guarded internally too (belt-and-suspenders): even if `skip` were
  // somehow bypassed, this never touches WSL unless we opted in AND the
  // probe run actually happened.
  var ranLinuxProbe = false;
  tearDownAll(() async {
    if (!shouldRun || !ranLinuxProbe) return;
    try {
      final repoPathWsl = _windowsPathToWsl(Directory.current.path);
      await Process.run('wsl.exe', [
        '-e',
        'bash',
        '-lc',
        "git -C '$repoPathWsl' worktree remove --force $_kLinuxWorktree "
            '2>/dev/null || true',
      ]);
    } catch (_) {
      // Best-effort only — cleanup failure must never fail the suite.
    }
  });

  test(
    'Windows and Linux agree on every OS-invariant probe key',
    () async {
      // --- 1. Windows side: in-process, no subprocess at all. ---------
      final winResult = computeOsProbe();

      // --- 2. Linux side: isolated WSL2 worktree + native Linux Flutter.
      final repoPathWin = Directory.current.path;
      final repoPathWsl = _windowsPathToWsl(repoPathWin);

      final headShaResult = await Process.run('git', ['rev-parse', 'HEAD']);
      expect(headShaResult.exitCode, 0,
          reason: 'could not resolve current HEAD: ${headShaResult.stderr}');
      final headSha = (headShaResult.stdout as String).trim();

      // `git worktree add` always checks out the WHOLE repository (from
      // its top level), not just the subdirectory `-C` pointed at — this
      // project lives inside a monorepo, so /root/manifold-osdiff is the
      // monorepo root and the actual Flutter project (pubspec.yaml etc.)
      // lands at /root/manifold-osdiff/<same relative subpath>. Compute
      // that subpath instead of assuming this file's own repo layout.
      final toplevelResult =
          await Process.run('git', ['rev-parse', '--show-toplevel']);
      expect(toplevelResult.exitCode, 0,
          reason: 'could not resolve repo top-level: '
              '${toplevelResult.stderr}');
      final topLevelWsl =
          _windowsPathToWsl((toplevelResult.stdout as String).trim());
      var relSubpath = repoPathWsl.startsWith(topLevelWsl)
          ? repoPathWsl.substring(topLevelWsl.length)
          : '';
      relSubpath = relSubpath.replaceFirst(RegExp(r'^/+'), '');
      final linuxProjectDir = relSubpath.isEmpty
          ? _kLinuxWorktree
          : '$_kLinuxWorktree/$relSubpath';

      // Prune stale worktree bookkeeping (e.g. a prior run's directory
      // was removed out from under git without `worktree remove`), then
      // create the worktree if it doesn't exist yet, or fast-forward an
      // existing one to the current HEAD if it does. Never runs `flutter`
      // against /mnt/c — only ever against this separate Linux path.
      await Process.run('wsl.exe',
          ['-e', 'bash', '-lc', "git -C '$repoPathWsl' worktree prune"]);

      final existsCheck = await Process.run('wsl.exe', [
        '-e',
        'bash',
        '-lc',
        'test -e $_kLinuxWorktree && echo EXISTS || echo MISSING',
      ]);
      final exists = (existsCheck.stdout as String).contains('EXISTS');

      if (!exists) {
        final add = await Process.run('wsl.exe', [
          '-e',
          'bash',
          '-lc',
          "git -C '$repoPathWsl' worktree add --detach -f "
              '$_kLinuxWorktree $headSha',
        ]);
        expect(add.exitCode, 0,
            reason: 'could not create isolated Linux worktree at '
                '$_kLinuxWorktree:\nstdout: ${add.stdout}\n'
                'stderr: ${add.stderr}');
      } else {
        final checkout = await Process.run('wsl.exe', [
          '-e',
          'bash',
          '-lc',
          'cd $_kLinuxWorktree && git checkout --detach -f $headSha',
        ]);
        expect(checkout.exitCode, 0,
            reason: 'could not fast-forward existing Linux worktree at '
                '$_kLinuxWorktree to $headSha:\nstdout: '
                '${checkout.stdout}\nstderr: ${checkout.stderr}');
      }

      // `git worktree add`/`checkout` only materializes COMMITTED content
      // — but this is a differential oracle over the LIVE working tree:
      // both the probe harness AND the lib code under test may be
      // mid-iteration and not yet committed. Copying only the probe files
      // (the original approach) silently pinned the Linux side's lib/ to
      // HEAD, so any uncommitted lib fix showed up as a spurious
      // "cross-OS divergence" (new code on Windows vs stale code on
      // Linux). Sync lib/ and test/support/ byte-exact from the live
      // Windows working tree instead — delete-then-copy so files removed
      // locally can't linger from the HEAD checkout. Read-only against
      // /mnt/c; no `flutter`/`dart` is ever invoked against /mnt/c.
      final syncProbe = await Process.run('wsl.exe', [
        '-e',
        'bash',
        '-lc',
        "rm -rf '$linuxProjectDir/lib' '$linuxProjectDir/test/support' && "
            "mkdir -p '$linuxProjectDir/test' && "
            "cp -r '$repoPathWsl/lib' '$linuxProjectDir/lib' && "
            "cp -r '$repoPathWsl/test/support' "
            "'$linuxProjectDir/test/support'",
      ]);
      expect(syncProbe.exitCode, 0,
          reason: 'could not sync live lib/ + probe source files into the '
              'Linux worktree:\nstdout: ${syncProbe.stdout}\n'
              'stderr: ${syncProbe.stderr}');

      // pub get + test compile on a cold cache is slow — this is the
      // multi-minute part the opt-in gate exists for.
      final runScript = 'export PATH=/root/flutter/bin:\$PATH\n'
          "cd '$linuxProjectDir'\n"
          'flutter pub get\n'
          'flutter test test/support/os_probe_main.dart\n';
      ranLinuxProbe = true;
      final testRun = await Process.run(
        'wsl.exe',
        ['-e', 'bash', '-lc', runScript],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(
        const Duration(minutes: 15),
        onTimeout: () => throw TimeoutException(
            'Linux probe run (pub get + flutter test) exceeded 15 minutes'),
      );

      final linuxStdout = testRun.stdout as String;
      const beginMarker = 'OSPROBE_BEGIN';
      const endMarker = 'OSPROBE_END';
      final beginIdx = linuxStdout.indexOf(beginMarker);
      final endIdx = linuxStdout.indexOf(endMarker);
      expect(beginIdx >= 0 && endIdx > beginIdx, isTrue,
          reason: 'Linux probe did not emit OSPROBE markers (exitCode='
              '${testRun.exitCode}). Full stdout:\n$linuxStdout\n'
              '--- stderr ---\n${testRun.stderr}');

      final jsonStr =
          linuxStdout.substring(beginIdx + beginMarker.length, endIdx);
      final linuxResult = jsonDecode(jsonStr) as Map<String, dynamic>;

      // --- 3. Diff key-by-key. -----------------------------------------
      final invariantMismatches = <String>[];
      final intentionalMismatches = <String>[];
      final allKeys = <String>{...winResult.keys, ...linuxResult.keys};

      // Independently replicate the non-Windows branch of
      // LogosSseStore._lockKey so the Linux side is checked against a
      // ground truth computed here, not against the Windows output.
      final expectedLinuxLockKey = <String, String>{
        for (final (label, path) in lockKeyForCorpus)
          'INTENTIONAL::lockKeyFor::$label':
              path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), ''),
      };

      for (final key in allKeys) {
        final winVal = winResult[key];
        final linuxVal = linuxResult[key];

        if (key.startsWith('INTENTIONAL::')) {
          final expectedLinux = expectedLinuxLockKey[key];
          if (expectedLinux == null) {
            intentionalMismatches.add(
                '$key\n  (no expected-value mapping registered for this '
                'INTENTIONAL key in the test itself)');
            continue;
          }
          final expectedWindows = expectedLinux.toLowerCase();
          if (winVal != expectedWindows) {
            intentionalMismatches.add('$key (Windows side)\n'
                '  expected (case-folded): ${_renderValue(expectedWindows)}\n'
                '  actual:                 ${_renderValue(winVal)}');
          }
          if (linuxVal != expectedLinux) {
            intentionalMismatches.add('$key (Linux side)\n'
                '  expected (not case-folded): ${_renderValue(expectedLinux)}\n'
                '  actual:                     ${_renderValue(linuxVal)}');
          }
          continue;
        }

        if (!_deepEquals(winVal, linuxVal)) {
          invariantMismatches.add('$key\n'
              '  windows: ${_renderValue(winVal)}\n'
              '  linux:   ${_renderValue(linuxVal)}');
        }
      }

      if (intentionalMismatches.isNotEmpty) {
        fail(
          'INTENTIONAL (platform-branching) key(s) did not match their '
          "OWN OS's expected value — the *contract* for how they're "
          'supposed to differ by OS is broken, not just a stray '
          'cross-OS diff:\n\n${intentionalMismatches.join('\n\n')}',
        );
      }

      if (invariantMismatches.isNotEmpty) {
        fail(
          'GENUINE CROSS-OS DIVERGENCE on ${invariantMismatches.length} '
          'key(s) that are supposed to be OS-invariant (no ambient '
          'Platform read, explicit inputs only):\n\n'
          '${invariantMismatches.join('\n\n')}',
        );
      }
    },
    skip: shouldRun ? false : skipReason,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
