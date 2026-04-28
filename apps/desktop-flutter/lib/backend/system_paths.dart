import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

/// Filesystem-path "open" operations. Companion to `system_browser.dart`,
/// which intentionally rejects non-`http(s)` URLs as a defense against
/// hostile scheme dispatch on remote-sourced strings. The functions
/// here take *trusted* local paths (entries the user has already
/// invited into their recents list) and dispatch to the OS file
/// manager / terminal.
///
/// Windows uses `ShellExecuteW` via FFI instead of `Process.start`:
/// `Process.start` quotes argv, which interferes with how some Windows
/// tools (notably `explorer.exe /select`) parse their command line.
/// Going through `ShellExecuteW` directly also matches the existing
/// reveal-in-explorer pattern in `changes_page.dart`.
///
/// Failures are swallowed silently — the user clicked a menu item and
/// either it worked or nothing happens. We don't want a popup dialog
/// blocking the workflow on what's almost always a "tool not installed"
/// error (Windows Terminal absent, no x-terminal-emulator on Linux).

/// Hand [path] to the OS for default-app dispatch. The OS picks the
/// handler based on the path's type:
///   * folder → file manager (Explorer / Finder / Nautilus / etc.)
///   * file   → the user's default app for that file's type
/// One function for both cases because every platform's "open" tool
/// (`ShellExecuteW("open", path)` / `open` / `xdg-open`) does the
/// same dispatch — the dichotomy is the OS's, not ours.
Future<void> openInDefaultApp(String path) async {
  if (Platform.isWindows) {
    _shellExec(file: path);
    return;
  }
  if (Platform.isMacOS) {
    final p = await Process.start('open', [path]);
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    return;
  }
  if (Platform.isLinux) {
    final p = await Process.start('xdg-open', [path]);
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    return;
  }
  throw UnsupportedError('openInDefaultApp: ${Platform.operatingSystem}');
}

/// Open a terminal session with its working directory set to [path].
///
/// Windows: try Windows Terminal (`wt.exe -d <path>`) first since it's
/// the default on modern installs; fall back to `cmd.exe` with the
/// directory passed as `lpDirectory` so the new console window opens
/// at [path] without needing a `cd` command in argv.
///
/// macOS: `open -a Terminal <path>`. Linux: `x-terminal-emulator` with
/// `workingDirectory` set, the conventional Debian-family wrapper that
/// most DEs alias to their preferred terminal emulator.
Future<void> openTerminalAt(String path) async {
  if (Platform.isWindows) {
    // Windows Terminal: returns >32 from ShellExecuteW on success.
    // The -d flag accepts a quoted path. NTFS forbids `"` in paths
    // so the escape isn't strictly required for correctness, but
    // applying _escapeWtArg here keeps the escaping discipline
    // consistent with runInTerminal — no caller has to remember
    // which entry points need it.
    final wtResult = _shellExecResult(
      file: 'wt.exe',
      params: '-d "${_escapeWtArg(path)}"',
    );
    if (wtResult > 32) return;
    // Fall back to cmd.exe with cwd via lpDirectory. SW_SHOWNORMAL
    // gives the user a visible console window.
    _shellExec(file: 'cmd.exe', dir: path);
    return;
  }
  if (Platform.isMacOS) {
    final p = await Process.start('open', ['-a', 'Terminal', path]);
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    return;
  }
  if (Platform.isLinux) {
    final p = await Process.start(
      'x-terminal-emulator',
      const [],
      workingDirectory: path,
    );
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    return;
  }
  throw UnsupportedError(
    'openTerminalAt: ${Platform.operatingSystem}',
  );
}

/// Run [executable] with [args] inside a fresh terminal window whose
/// cwd is set to [workingDirectory]. The terminal stays open after
/// the command exits — interactive tools (`claude`, REPL shells)
/// expect to keep accepting input, and even one-shot commands benefit
/// from a visible exit message.
///
/// Windows: prefer Windows Terminal (`wt.exe -d <path> <exe> <args…>`);
/// fall back to `cmd.exe /K <exe> <args…>` with `lpDirectory` set via
/// `ShellExecuteW`.
///
/// macOS: write a temp `.command` script (cd + exec) and `open` it.
/// `open -a Terminal --args` does not pass through positional args
/// reliably; the temp-script trampoline is the well-trodden path.
///
/// Linux: `x-terminal-emulator -e bash -c '<command>; exec bash'` —
/// the trailing `exec bash` keeps the window open after the command
/// exits.
Future<void> runInTerminal({
  required String executable,
  required List<String> args,
  required String workingDirectory,
}) async {
  if (Platform.isWindows) {
    // Try Windows Terminal first. wt.exe accepts the executable +
    // args after `-d <path>` directly. Quote every value because
    // ShellExecuteW's params string is parsed by CreateProcessW
    // which splits on whitespace — including the executable itself,
    // which may contain spaces (e.g. `C:\Program Files\foo.exe`).
    final wtParams = StringBuffer(
      '-d "$workingDirectory" "${_escapeWtArg(executable)}"',
    );
    for (final a in args) {
      wtParams.write(' "${_escapeWtArg(a)}"');
    }
    final wtResult = _shellExecResult(
      file: 'wt.exe',
      params: wtParams.toString(),
    );
    if (wtResult > 32) return;
    // Fall back to cmd.exe /K so the window stays open. lpDirectory
    // sets the cwd; the /K argument carries the actual command.
    // Same quoting rule for the executable — cmd splits on
    // whitespace before /K hands the rest to its child shell.
    final cmdParams = StringBuffer('/K "${_escapeCmdArg(executable)}"');
    for (final a in args) {
      cmdParams.write(' "${_escapeCmdArg(a)}"');
    }
    _shellExec(
      file: 'cmd.exe',
      params: cmdParams.toString(),
      dir: workingDirectory,
    );
    return;
  }
  if (Platform.isMacOS) {
    await _macRunInTerminal(executable, args, workingDirectory);
    return;
  }
  if (Platform.isLinux) {
    // Build a single-quoted bash command. Use single quotes around
    // each shell-escaped argument so metacharacters don't reparse.
    final cmd = StringBuffer();
    cmd.write(_shQuote(executable));
    for (final a in args) {
      cmd.write(' ');
      cmd.write(_shQuote(a));
    }
    cmd.write('; exec bash');
    final p = await Process.start(
      'x-terminal-emulator',
      ['-e', 'bash', '-c', cmd.toString()],
      workingDirectory: workingDirectory,
    );
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    return;
  }
  throw UnsupportedError('runInTerminal: ${Platform.operatingSystem}');
}

/// Spawn [executable] with [args] detached from the host process,
/// with cwd set to [workingDirectory]. No terminal window. Use for
/// GUI launchers (`code .`, `cursor .`) that fork their own window
/// — opening them in a terminal would just flash a useless console.
///
/// Failure (executable missing on PATH, permission denied) is
/// swallowed silently per the module-level rationale.
Future<void> runDetached({
  required String executable,
  required List<String> args,
  required String workingDirectory,
}) async {
  try {
    await Process.start(
      executable,
      args,
      mode: ProcessStartMode.detachedWithStdio,
      workingDirectory: workingDirectory,
    );
  } on ProcessException {
    // Executable not on PATH or not executable — silent fail.
  }
}

/// macOS terminal launch via temp `.command` script. Writes a small
/// shell script that `cd`s into the project and execs the command,
/// then `open`s it. The script auto-deletes itself on exit so the
/// /tmp directory stays clean across many launches.
Future<void> _macRunInTerminal(
  String executable,
  List<String> args,
  String workingDirectory,
) async {
  final tmp = Directory.systemTemp;
  final f = File(
    '${tmp.path}/manifold-tool-${DateTime.now().microsecondsSinceEpoch}.command',
  );
  final cmdLine = StringBuffer(_shQuote(executable));
  for (final a in args) {
    cmdLine.write(' ');
    cmdLine.write(_shQuote(a));
  }
  // The trailing `; exec bash` keeps the window open after the
  // command exits. The `rm -- "$0"` line removes the script after
  // launch so /tmp doesn't accumulate one file per click.
  await f.writeAsString(
    '#!/bin/bash\n'
    'cd ${_shQuote(workingDirectory)}\n'
    'rm -- "\$0"\n'
    '$cmdLine\n'
    'exec bash\n',
    flush: true,
  );
  // Make executable. The `open` call wants +x or it'll show the
  // user a "do you want to allow…" dialog every time.
  await Process.run('chmod', ['+x', f.path]);
  final p = await Process.start('open', [f.path]);
  unawaited(p.stdout.drain<void>());
  unawaited(p.stderr.drain<void>());
}

/// Single-quote-wrap [arg] for bash. Escape embedded single quotes
/// using the standard `'\''` trick so the result round-trips through
/// the shell parser unchanged.
String _shQuote(String arg) {
  final escaped = arg.replaceAll("'", r"'\''");
  return "'$escaped'";
}

/// Escape an arg for `wt.exe`'s parser. wt.exe parses its command
/// line through CreateProcessW's whitespace tokenizer; we wrap each
/// arg in double quotes upstream, so the only character we need to
/// neutralize inside is a literal double quote. wt itself does not
/// re-parse through `cmd`, so cmd metacharacters are irrelevant.
String _escapeWtArg(String arg) => arg.replaceAll('"', r'\"');

/// Escape an arg for `cmd.exe /K "..."`. Each arg is double-quoted
/// upstream, which makes `&`, `|`, `<`, `>`, `^`, `(`, `)` literal
/// to cmd's tokenizer (per the documented "characters inside
/// quotation marks are not interpreted" rule). The two characters
/// that DO retain meaning inside double quotes need explicit
/// escaping:
///
///   * `"` — closes the quoted span. Replaced with `\"` so cmd
///     reads it as a literal quote inside the arg.
///   * `%` — `%var%` expansion happens inside double quotes too
///     (this is the surprising one). A repo path or tool argument
///     containing `%` would otherwise either expand to whatever
///     environment variable matches, or get truncated/scrambled.
///     Doubling to `%%` is the standard cmd quote — when cmd
///     processes the command line it collapses `%%` back to a
///     single literal `%` before exec'ing.
///
/// `!` is also special if delayed expansion is enabled, but that's
/// off by default for `cmd /K` invocations (it requires the
/// `/V:ON` flag we don't pass), so callers don't need to worry
/// about it here.
String _escapeCmdArg(String arg) =>
    arg.replaceAll('%', '%%').replaceAll('"', r'\"');

/// Test-only handle so the cmd-escape contract is pinned without
/// driving the platform side effects of [runInTerminal].
@visibleForTesting
String escapeCmdArgForTesting(String arg) => _escapeCmdArg(arg);

@visibleForTesting
String escapeWtArgForTesting(String arg) => _escapeWtArg(arg);

/// Windows-only: thin `ShellExecuteW` wrapper. Returns the raw return
/// value (HINSTANCE-shaped int — >32 means success). Used by callers
/// that need to branch on success/failure (e.g., trying `wt.exe` then
/// falling back to `cmd.exe`).
int _shellExecResult({
  required String file,
  String? params,
  String? dir,
}) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final shellExecute = shell32.lookupFunction<
      IntPtr Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>,
          Pointer<Utf16>, Pointer<Utf16>, Int32),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>,
          Pointer<Utf16>, int)>('ShellExecuteW');
  final op = 'open'.toNativeUtf16();
  final fileN = file.toNativeUtf16();
  final paramsN = params?.toNativeUtf16();
  final dirN = dir?.toNativeUtf16();
  try {
    return shellExecute(
      0,
      op,
      fileN,
      paramsN ?? nullptr,
      dirN ?? nullptr,
      1, // SW_SHOWNORMAL
    );
  } finally {
    malloc.free(op);
    malloc.free(fileN);
    if (paramsN != null) malloc.free(paramsN);
    if (dirN != null) malloc.free(dirN);
  }
}

/// Fire-and-forget convenience. Call when the return code is irrelevant
/// (e.g., opening explorer at a folder — there's nothing useful to
/// surface if it fails).
void _shellExec({
  required String file,
  String? params,
  String? dir,
}) {
  _shellExecResult(file: file, params: params, dir: dir);
}
