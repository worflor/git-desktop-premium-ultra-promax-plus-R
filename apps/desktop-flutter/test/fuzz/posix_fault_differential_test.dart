// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// posix_fault_differential_test.dart — exercises real `git` against POSIX
// filesystem conditions that are physically impossible to construct on an
// NTFS/Windows checkout: permission-denied object writes, a disk that runs
// out of space mid-write, index.lock contention, case-sensitive filenames,
// symlink/exec-bit modes, paths longer than Windows' MAX_PATH, and
// filenames containing bytes NTFS forbids outright (`\`, newline).
//
// Unlike cross_os_differential_test.dart (which diffs a shared PURE-Dart
// corpus across both OSes), this harness has no Windows-side git run to
// diff against — the whole point is that these conditions cannot be
// constructed on Windows at all. Instead, it runs a bash+git script INSIDE
// WSL2 (no Flutter needed on the Linux side — plain `bash`+`git` is far
// faster than a `flutter pub get`+`flutter test` round trip), captures a
// JSON report of what happened, and asserts the app's documented
// contracts against that report from the Windows side:
//   - a permission-denied object write fails cleanly, never corrupts the
//     repo (`git fsck --full` stays clean);
//   - a full disk never corrupts the object store either;
//   - `lib/backend/git.dart`'s `_isIndexLockContention` retry predicate
//     actually matches the real, current git's index.lock stderr shape —
//     if it doesn't, the app's retry would silently never fire;
//   - case-sensitive filename pairs, symlink/exec-bit modes, > MAX_PATH
//     paths, and filenames containing `\`/newline are all legal on Linux
//     and never occur on a Windows checkout, so nothing here is exercised
//     by any Windows-only test.
//
// RUNNING THIS TEST
//   Opt-in only, same gating shape as cross_os_differential_test.dart:
//     export MANIFOLD_CROSS_OS=1
//     "C:/flutter/flutter/bin/flutter.bat" test \
//         test/fuzz/posix_fault_differential_test.dart
//   Any other invocation (plain `flutter test`, or run on a non-Windows
//   host, or WSL2/the Linux toolchain unreachable) skips instantly without
//   spawning wsl.exe.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/wsl_runner.dart';

bool get _envOptIn => Platform.environment['MANIFOLD_CROSS_OS'] == '1';

bool _computeShouldRun() {
  if (!Platform.isWindows) return false;
  if (!_envOptIn) return false;
  return wslAvailable();
}

String _computeSkipReason(bool envOptIn) {
  if (!Platform.isWindows) {
    return 'POSIX-fault differential only runs FROM Windows (the whole '
        'point is constructing conditions Windows cannot express, then '
        'observing real git\'s response to them under WSL2)';
  }
  if (!envOptIn) {
    return 'opt-in only — spins up WSL2 and mutates filesystem state '
        '(mounts a tmpfs, drops privileges). Set MANIFOLD_CROSS_OS=1 to '
        'run it.';
  }
  return 'WSL2 Ubuntu with a Flutter/Dart SDK at /root/flutter was not '
      'reachable (`wsl.exe -e bash -lc "ls /root/flutter/bin/dart"` '
      'failed) — skipping gracefully rather than failing the suite on an '
      'unrelated machine';
}

/// The bash+git script run inside WSL2. Entirely self-contained: every
/// case operates in its own `mktemp -d` (or tmpfs-backed) throwaway repo,
/// never touches this project's worktree, and a `trap ... EXIT` cleans up
/// the one piece of *global* state it creates (the tmpfs mount for the
/// ENOSPC case) even if the script aborts partway.
///
/// Every result is captured into shell variables (never let a case's
/// *expected* failure — a denied chmod, a full disk, a held lock — abort
/// the script; `set -e` is deliberately NOT used) and finally serialized
/// by hand into a single flat JSON object, since a from-scratch Ubuntu
/// image inside WSL2 is not guaranteed to have `jq`/`python3` installed
/// but always has bash's own string primitives.
const String _kPosixFaultScript = r'''
set -u
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export HOME="${HOME:-/root}"
# This is a throwaway WSL2 sandbox dedicated to this probe run, not the
# project checkout — touching root's own global git config here is safe
# and is needed because case 1 (EACCES) deliberately runs git as a
# different uid than the one that created the repo.
git config --global --add safe.directory '*' 2>/dev/null || true

GLOBAL_TMP_MOUNT=/mnt/manifold-tiny-fs-test
cleanup() {
  umount "$GLOBAL_TMP_MOUNT" >/dev/null 2>&1 || true
  rm -rf "$GLOBAL_TMP_MOUNT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Escapes $1 for embedding as a JSON string body (caller supplies the
# surrounding quotes).
json_str() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

str_field() {
  printf '"%s":"%s"' "$1" "$(json_str "$2")"
}

# Emits null when $2 is empty, else a quoted escaped string — used for the
# "why this case was skipped" fields, where empty means "not skipped".
opt_str_field() {
  if [ -z "$2" ]; then
    printf '"%s":null' "$1"
  else
    printf '"%s":"%s"' "$1" "$(json_str "$2")"
  fi
}

raw_field() {
  printf '"%s":%s' "$1" "$2"
}

LINUX_GIT_VERSION=$(git --version 2>&1)

# --- Case 1: EACCES — permission-denied object write -----------------------
run_case1() {
  local d
  d=$(mktemp -d)
  cd "$d"
  git init -q -b main
  git config user.name test
  git config user.email test@example.com
  printf 'hello\n' > file.txt
  git add file.txt
  git commit -q -m initial
  printf 'more\n' >> file.txt
  git add file.txt

  local runner="" chown_target="" skip_reason=""
  if [ "$(id -u)" != "0" ]; then
    runner=""
  elif command -v setpriv >/dev/null 2>&1; then
    runner="setpriv --reuid=1000 --regid=1000 --clear-groups"
    chown_target="1000:1000"
  elif command -v runuser >/dev/null 2>&1; then
    runner="runuser -u nobody --"
    chown_target="nobody:nogroup"
  else
    skip_reason="running as root inside WSL and neither setpriv nor runuser is available to drop privileges — chmod 000 is a no-op for root (DAC_OVERRIDE), so EACCES cannot be demonstrated on this machine"
  fi

  local out="" rc=0 fsck_out="" fsck_rc=0
  if [ -z "$skip_reason" ]; then
    if [ -n "$chown_target" ]; then
      chown -R "$chown_target" "$d"
    fi
    chmod 000 .git/objects
    if [ -n "$runner" ]; then
      out=$(env HOME="$d" $runner git -c user.name=test -c user.email=test@example.com commit -q -m second 2>&1); rc=$?
    else
      out=$(git commit -q -m second 2>&1); rc=$?
    fi
    # Root can always chmod back regardless of who currently owns the path.
    chmod 755 .git/objects
    fsck_out=$(git fsck --full 2>&1); fsck_rc=$?
  fi

  EACCES_SKIP="$skip_reason"
  EACCES_RC="$rc"
  EACCES_STDERR="$out"
  EACCES_FSCK_RC="$fsck_rc"
  EACCES_FSCK_OUT="$fsck_out"

  cd /
  rm -rf "$d"
}

# --- Case 2: ENOSPC — disk-full mid-write -----------------------------------
run_case2() {
  local mnt="$GLOBAL_TMP_MOUNT" skip_reason="" d out="" rc=0 fsck_out="" fsck_rc=0 status_rc=0
  mkdir -p "$mnt"
  if [ "$(id -u)" != "0" ]; then
    skip_reason="not running as root inside WSL — mounting a size-capped tmpfs requires root"
  elif ! mount -t tmpfs -o size=1M tmpfs "$mnt" 2>/tmp/manifold_mount_err; then
    skip_reason="mount -t tmpfs failed: $(cat /tmp/manifold_mount_err 2>/dev/null)"
  fi

  if [ -z "$skip_reason" ]; then
    d="$mnt/repo"
    mkdir -p "$d"
    cd "$d"
    git init -q -b main
    git config user.name test
    git config user.email test@example.com
    # Deliberately larger than the whole tmpfs — dd itself may fail with
    # ENOSPC partway (expected; ignored), leaving a file that already
    # consumes most of the remaining space before git ever touches it.
    dd if=/dev/urandom of=big bs=1M count=4 2>/dev/null || true
    out=$( (git add big && git commit -q -m big) 2>&1 ); rc=$?
    fsck_out=$(git fsck --full 2>&1); fsck_rc=$?
    git status --porcelain >/dev/null 2>&1; status_rc=$?
    cd /
    umount "$mnt" 2>/dev/null || true
  fi

  ENOSPC_SKIP="$skip_reason"
  ENOSPC_RC="$rc"
  ENOSPC_STDERR="$out"
  ENOSPC_FSCK_RC="$fsck_rc"
  ENOSPC_FSCK_OUT="$fsck_out"
  ENOSPC_STATUS_RC="$status_rc"
}

# --- Case 3: index.lock contention ------------------------------------------
run_case3() {
  local d out rc status_out status_rc
  d=$(mktemp -d)
  cd "$d"
  git init -q -b main
  git config user.name test
  git config user.email test@example.com
  printf 'hello\n' > file.txt
  git add file.txt
  git commit -q -m initial

  printf 'x\n' > file.txt
  : > .git/index.lock

  out=$(git add file.txt 2>&1); rc=$?
  rm -f .git/index.lock

  status_out=$(git status --porcelain 2>&1); status_rc=$?

  LOCK_RC="$rc"
  LOCK_STDERR="$out"
  LOCK_RECOVER_STATUS_RC="$status_rc"

  cd /
  rm -rf "$d"
}

# --- Case 4: case-sensitive filenames ---------------------------------------
run_case4() {
  local d out
  d=$(mktemp -d)
  cd "$d"
  git init -q -b main
  git config user.name test
  git config user.email test@example.com
  printf 'upper\n' > File.txt
  printf 'lower\n' > file.txt
  git add File.txt file.txt
  git commit -q -m 'case sensitive pair'
  out=$(git ls-files)
  CASE_LS_FILES="$out"
  CASE_COUNT=$(printf '%s\n' "$out" | grep -c .)
  cd /
  rm -rf "$d"
}

# --- Case 5: symlink + exec bit ---------------------------------------------
run_case5() {
  local d out
  d=$(mktemp -d)
  cd "$d"
  git init -q -b main
  git config user.name test
  git config user.email test@example.com
  printf '#!/bin/sh\necho hi\n' > run.sh
  chmod 755 run.sh
  ln -s run.sh link-to-run.sh
  git add run.sh link-to-run.sh
  git commit -q -m 'symlink + exec'
  out=$(git ls-files -s)
  MODES_LS_FILES_S="$out"
  cd /
  rm -rf "$d"
}

# --- Case 6: path longer than Windows MAX_PATH (260) ------------------------
run_case6() {
  local d out rc path="" seg="segment_of_reasonable_length_thirty_two" i=0
  d=$(mktemp -d)
  cd "$d"
  git init -q -b main
  git config user.name test
  git config user.email test@example.com

  while [ "${#path}" -le 260 ]; do
    path="${path}${seg}_${i}/"
    i=$((i + 1))
  done
  path="${path}leaf.txt"

  mkdir -p "$(dirname "$path")"
  printf 'deep content\n' > "$path"
  git add -- "$path"
  git commit -q -m 'long path'

  out=$(git fsck --full 2>&1); rc=$?
  LONGPATH_REL_LEN=${#path}
  LONGPATH_ABS_LEN=${#PWD}
  LONGPATH_FSCK_RC="$rc"
  LONGPATH_FSCK_OUT="$out"
  cd /
  rm -rf "$d"
}

# --- Case 7: filenames with embedded newline / backslash -------------------
run_case7() {
  local d nlname bsname nl_out
  d=$(mktemp -d)
  cd "$d"
  git init -q -b main
  git config user.name test
  git config user.email test@example.com

  nlname=$'weird\nname.txt'
  bsname='weird\backslash.txt'

  printf 'nl file\n' > "$nlname"
  printf 'bs file\n' > "$bsname"
  git add -- "$nlname" "$bsname"
  git commit -q -m 'newline and backslash filenames'

  nl_out=$(git ls-files)

  # `git ls-files -z` is NUL-delimited; NUL bytes can't survive inside a
  # bash *variable* (command substitution truncates at the first NUL), so
  # it's piped straight into base64 without ever landing in a bash string.
  NL_NAME_B64=$(printf '%s' "$nlname" | base64 -w0)
  BS_NAME_B64=$(printf '%s' "$bsname" | base64 -w0)
  LSFILES_Z_B64=$(git ls-files -z | base64 -w0)
  LSFILES_PLAIN="$nl_out"

  cd /
  rm -rf "$d"
}

EACCES_SKIP=""; EACCES_RC=0; EACCES_STDERR=""; EACCES_FSCK_RC=0; EACCES_FSCK_OUT=""
ENOSPC_SKIP=""; ENOSPC_RC=0; ENOSPC_STDERR=""; ENOSPC_FSCK_RC=0; ENOSPC_FSCK_OUT=""; ENOSPC_STATUS_RC=0
LOCK_RC=0; LOCK_STDERR=""; LOCK_RECOVER_STATUS_RC=0
CASE_LS_FILES=""; CASE_COUNT=0
MODES_LS_FILES_S=""
LONGPATH_REL_LEN=0; LONGPATH_ABS_LEN=0; LONGPATH_FSCK_RC=0; LONGPATH_FSCK_OUT=""
NL_NAME_B64=""; BS_NAME_B64=""; LSFILES_Z_B64=""; LSFILES_PLAIN=""

run_case1
run_case2
run_case3
run_case4
run_case5
run_case6
run_case7

fields=()
fields+=("$(str_field gitVersionLinux "$LINUX_GIT_VERSION")")
fields+=("$(opt_str_field eaccesSkipped "$EACCES_SKIP")")
fields+=("$(raw_field eaccesExitCode "$EACCES_RC")")
fields+=("$(str_field eaccesStderr "$EACCES_STDERR")")
fields+=("$(raw_field eaccesFsckExitCode "$EACCES_FSCK_RC")")
fields+=("$(str_field eaccesFsckOutput "$EACCES_FSCK_OUT")")
fields+=("$(opt_str_field enospcSkipped "$ENOSPC_SKIP")")
fields+=("$(raw_field enospcExitCode "$ENOSPC_RC")")
fields+=("$(str_field enospcStderr "$ENOSPC_STDERR")")
fields+=("$(raw_field enospcFsckExitCode "$ENOSPC_FSCK_RC")")
fields+=("$(str_field enospcFsckOutput "$ENOSPC_FSCK_OUT")")
fields+=("$(raw_field enospcStatusExitCode "$ENOSPC_STATUS_RC")")
fields+=("$(raw_field indexLockExitCode "$LOCK_RC")")
fields+=("$(str_field indexLockStderr "$LOCK_STDERR")")
fields+=("$(raw_field indexLockRecoverStatusExitCode "$LOCK_RECOVER_STATUS_RC")")
fields+=("$(str_field caseSensitiveLsFiles "$CASE_LS_FILES")")
fields+=("$(raw_field caseSensitiveCount "$CASE_COUNT")")
fields+=("$(str_field modesLsFilesS "$MODES_LS_FILES_S")")
fields+=("$(raw_field longPathRelLength "$LONGPATH_REL_LEN")")
fields+=("$(raw_field longPathAbsLength "$LONGPATH_ABS_LEN")")
fields+=("$(raw_field longPathFsckExitCode "$LONGPATH_FSCK_RC")")
fields+=("$(str_field longPathFsckOutput "$LONGPATH_FSCK_OUT")")
fields+=("$(str_field weirdNlNameB64 "$NL_NAME_B64")")
fields+=("$(str_field weirdBsNameB64 "$BS_NAME_B64")")
fields+=("$(str_field weirdLsFilesZB64 "$LSFILES_Z_B64")")
fields+=("$(str_field weirdLsFilesPlain "$LSFILES_PLAIN")")

IFS=,
json="{${fields[*]}}"
unset IFS

printf 'POSIXPROBE_BEGIN%sPOSIXPROBE_END\n' "$json"
''';

/// Decodes a base64 string exactly as the WSL side produced it
/// (`base64 -w0`, no line wrapping) back into raw UTF-8 text.
String _b64ToString(String b64) => utf8.decode(base64.decode(b64));

void main() {
  final shouldRun = _computeShouldRun();
  final skipReason = shouldRun ? null : _computeSkipReason(_envOptIn);

  test(
    'real git under WSL2 handles POSIX faults Windows cannot construct',
    () async {
      // --- Windows-side git version, for the cross-check below. ---------
      final winGitVersionResult = await Process.run('git', ['--version']);
      expect(winGitVersionResult.exitCode, 0,
          reason: 'could not resolve Windows git --version: '
              '${winGitVersionResult.stderr}');
      final winGitVersion = (winGitVersionResult.stdout as String).trim();
      expect(winGitVersion, isNotEmpty);
      // ignore: avoid_print
      print('Windows git --version: $winGitVersion');

      // --- Linux-side probe. All 7 cases run inside one bash script; no
      // Flutter/Dart toolchain needed on the Linux side for pure git
      // cases, so this goes through plain wsl.exe, not
      // runLinuxTestAndSliceJson. -----------------------------------------
      final stdout = await runInWsl(
        _kPosixFaultScript,
        timeout: const Duration(minutes: 5),
      );

      const beginMarker = 'POSIXPROBE_BEGIN';
      const endMarker = 'POSIXPROBE_END';
      final beginIdx = stdout.indexOf(beginMarker);
      final endIdx = stdout.indexOf(endMarker);
      expect(beginIdx >= 0 && endIdx > beginIdx, isTrue,
          reason: 'Linux probe did not emit POSIXPROBE markers. Full '
              'stdout:\n$stdout');
      final jsonStr =
          stdout.substring(beginIdx + beginMarker.length, endIdx);
      final report = jsonDecode(jsonStr) as Map<String, dynamic>;

      final linuxGitVersion = report['gitVersionLinux'] as String;
      expect(linuxGitVersion, isNotEmpty,
          reason: 'Linux git --version was empty — the probe script '
              'likely failed before running any git command');
      // ignore: avoid_print
      print('Linux git --version:   $linuxGitVersion');
      expect(linuxGitVersion, contains('git version'),
          reason: 'Linux "git --version" output is not parseable as a '
              'normal git version string: $linuxGitVersion');
      expect(winGitVersion, contains('git version'),
          reason: 'Windows "git --version" output is not parseable as a '
              'normal git version string: $winGitVersion');

      // --- Case 1: EACCES ---------------------------------------------
      final eaccesSkip = report['eaccesSkipped'] as String?;
      if (eaccesSkip != null) {
        // ignore: avoid_print
        print('Case 1 (EACCES) SKIPPED: $eaccesSkip');
      } else {
        final rc = report['eaccesExitCode'] as int;
        final stderrText = report['eaccesStderr'] as String;
        expect(rc, isNot(0),
            reason: 'a commit that cannot write into a chmod-000 '
                'objects/ directory should fail, not silently succeed. '
                'stderr:\n$stderrText');
        expect(stderrText.trim(), isNotEmpty,
            reason: 'an EACCES failure should surface a nonempty stderr '
                'message');
        final fsckRc = report['eaccesFsckExitCode'] as int;
        final fsckOut = report['eaccesFsckOutput'] as String;
        expect(fsckRc, 0,
            reason: 'a permission-denied object write must never '
                'corrupt the repo — `git fsck --full` should stay clean '
                'once permissions are restored. fsck output:\n$fsckOut');
      }

      // --- Case 2: ENOSPC ------------------------------------------------
      final enospcSkip = report['enospcSkipped'] as String?;
      if (enospcSkip != null) {
        // ignore: avoid_print
        print('Case 2 (ENOSPC) SKIPPED: $enospcSkip');
      } else {
        final fsckRc = report['enospcFsckExitCode'] as int;
        final fsckOut = report['enospcFsckOutput'] as String;
        expect(fsckRc, 0,
            reason: 'a full disk must never corrupt the object store — '
                '`git fsck --full` should stay clean even after an '
                'add/commit that ran out of space. fsck output:\n'
                '$fsckOut');
        final statusRc = report['enospcStatusExitCode'] as int;
        expect(statusRc, 0,
            reason: '`git status` should still work after an ENOSPC '
                'failure, proving the repo is left in a usable state');
      }

      // --- Case 3: index.lock contention ---------------------------------
      // This is the exact stderr shape `_isIndexLockContention` in
      // lib/backend/git.dart matches on. If the running git's message no
      // longer contains one of the matched fragments, the app's retry
      // predicate would never fire against this git version — report that
      // loudly rather than silently passing.
      final lockRc = report['indexLockExitCode'] as int;
      final lockStderr = report['indexLockStderr'] as String;
      expect(lockRc, isNot(0),
          reason: '`git add` while .git/index.lock exists should fail. '
              'stderr:\n$lockStderr');
      // ignore: avoid_print
      print('Real WSL git index.lock stderr:\n$lockStderr');
      final matchesIsIndexLockContention = lockStderr.contains('index.lock') &&
          (lockStderr.contains('File exists') ||
              lockStderr.contains('Unable to create') ||
              lockStderr.contains('Another git process'));
      expect(matchesIsIndexLockContention, isTrue,
          reason: 'GENUINE BUG CANDIDATE: this WSL git\'s real index.lock '
              'stderr does not match the fragments '
              '`_isIndexLockContention` in lib/backend/git.dart checks '
              'for (`index.lock` plus one of `File exists` / `Unable to '
              'create` / `Another git process`) — the app\'s index.lock '
              'retry would never fire against this git version. Actual '
              'stderr:\n$lockStderr');
      final recoverStatusRc =
          report['indexLockRecoverStatusExitCode'] as int;
      expect(recoverStatusRc, 0,
          reason: 'removing .git/index.lock should fully recover the '
              'repo — a subsequent `git status` should succeed');

      // --- Case 4: case-sensitive filenames -------------------------------
      final caseLsFiles = report['caseSensitiveLsFiles'] as String;
      final caseCount = report['caseSensitiveCount'] as int;
      expect(caseCount, 2,
          reason: '`File.txt` and `file.txt` are distinct, independently '
              'trackable paths on a case-sensitive Linux filesystem — '
              '`git ls-files` should list both. Actual listing:\n'
              '$caseLsFiles');
      final caseEntries =
          caseLsFiles.split('\n').where((l) => l.isNotEmpty).toSet();
      expect(caseEntries, {'File.txt', 'file.txt'});
      // A naive case-folding path key (e.g. Windows-style path comparison)
      // would collide these two distinct tracked files into one key.
      expect(
        caseEntries.map((e) => e.toLowerCase()).toSet().length,
        1,
        reason: 'sanity check: both paths really do case-fold to the '
            'same key, which is exactly why a case-folding path index '
            'would be wrong on this repo',
      );

      // --- Case 5: symlink + exec bit -------------------------------------
      final modes = report['modesLsFilesS'] as String;
      expect(modes, contains('120000'),
          reason: 'a committed symlink should carry git mode 120000 '
              '(never seen on a Windows checkout). Actual `git ls-files '
              '-s`:\n$modes');
      expect(modes, contains('100755'),
          reason: 'a committed executable file should carry git mode '
              '100755 (the executable bit is meaningless on NTFS). '
              'Actual `git ls-files -s`:\n$modes');

      // --- Case 6: path longer than Windows MAX_PATH ----------------------
      final longPathRelLen = report['longPathRelLength'] as int;
      final longPathFsckRc = report['longPathFsckExitCode'] as int;
      final longPathFsckOut = report['longPathFsckOutput'] as String;
      expect(longPathRelLen, greaterThan(260),
          reason: 'the generated tracked path should exceed Windows\' '
              '260-char MAX_PATH by construction');
      expect(longPathFsckRc, 0,
          reason: 'a legal (on Linux) long path must not corrupt the '
              'repo. fsck output:\n$longPathFsckOut');

      // --- Case 7: newline / backslash filenames --------------------------
      final nlName = _b64ToString(report['weirdNlNameB64'] as String);
      final bsName = _b64ToString(report['weirdBsNameB64'] as String);
      expect(nlName, contains('\n'),
          reason: 'sanity check: the "newline" filename really does '
              'contain a raw newline byte');
      expect(bsName, contains(r'\'),
          reason: 'sanity check: the "backslash" filename really does '
              'contain a raw backslash byte — illegal as a path '
              'component on NTFS');

      final zRaw = base64.decode(report['weirdLsFilesZB64'] as String);
      final zDecoded = utf8.decode(zRaw, allowMalformed: true);
      final zEntries =
          zDecoded.split('\x00').where((e) => e.isNotEmpty).toList();
      expect(zEntries.toSet(), {nlName, bsName},
          reason: 'NUL-delimited `git ls-files -z` must round-trip both '
              'weird filenames exactly, embedded newline and all');

      final plainEntries = (report['weirdLsFilesPlain'] as String)
          .split('\n')
          .where((e) => e.isNotEmpty)
          .toList();
      // Empirically (verified against this WSL git via `od -c`/`cat -A`
      // on the raw bytes): plain `git ls-files` does NOT print the
      // embedded newline or backslash raw. It always C-quotes any path
      // containing a control byte or a backslash — wrapping it in `"..."`
      // and escaping the newline as the two literal characters `\`+`n`
      // and the backslash as `\`+`\`. So the line count survives (2
      // lines, not 3) but neither line's TEXT equals the real filename —
      // a naive reader that treats each line as a literal path gets back
      // quoted/escaped garbage, not `weird<LF>name.txt` or
      // `weird\backslash.txt`. That quoting ambiguity (and the need for a
      // C-quote decoder to undo it) is exactly why
      // walkRepoBlobsNullDelimited in lib/backend/repo_blob_walk.dart
      // uses `-z` instead: `-z` output is never quoted at all.
      expect(
        plainEntries.toSet(),
        isNot({nlName, bsName}),
        reason: 'THE POINT of this case: plain (non -z) `git ls-files` '
            'C-quotes the newline- and backslash-containing paths rather '
            'than printing them raw, so a naive line reader recovers '
            'quoted escape text, not the real filenames. Naive lines: '
            '$plainEntries vs. real names: {$nlName, $bsName}',
      );
    },
    skip: shouldRun ? false : skipReason,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
