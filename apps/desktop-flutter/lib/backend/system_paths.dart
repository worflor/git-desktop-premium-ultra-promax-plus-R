import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

/// Filesystem-path "open" operations. Companion to `system_browser.dart`,
/// which intentionally rejects non-`http(s)` URLs as a defense against
/// hostile scheme dispatch on remote-sourced strings. The functions
/// here take *trusted* local paths (entries the user has already
/// invited into their recents list) and dispatch to the OS file
/// manager / terminal.
///
/// Failures are swallowed silently — the user clicked a menu item and
/// either it worked or nothing happens. We don't want a popup dialog
/// blocking the workflow on what's almost always a "tool not installed"
/// error (Windows Terminal absent, no x-terminal-emulator on Linux).

/// Hand [path] to the OS for default-app dispatch. The OS picks the
/// handler based on the path's type:
///   * folder → file manager (Explorer / Finder / Nautilus / etc.)
///   * file   → the user's default app for that file's type
Future<void> openInDefaultApp(String path) async {
  final Process p;
  if (Platform.isWindows) {
    p = await Process.start(
        'rundll32', ['url.dll,FileProtocolHandler', path]);
  } else if (Platform.isMacOS) {
    p = await Process.start('open', [path]);
  } else if (Platform.isLinux) {
    p = await Process.start('xdg-open', [path]);
  } else {
    throw UnsupportedError('openInDefaultApp: ${Platform.operatingSystem}');
  }
  unawaited(p.stdout.drain<void>());
  unawaited(p.stderr.drain<void>());
}

/// Open a terminal session with its working directory set to [path].
///
/// Windows: try Windows Terminal (`wt.exe -d <path>`) first since it's
/// the default on modern installs; fall back to `cmd.exe`.
///
/// macOS: `open -a Terminal <path>`. Linux: `x-terminal-emulator` with
/// `workingDirectory` set, the conventional Debian-family wrapper that
/// most DEs alias to their preferred terminal emulator.
Future<void> openTerminalAt(String path) async {
  if (Platform.isWindows) {
    try {
      final p = await Process.start('wt.exe', ['-d', path]);
      unawaited(p.stdout.drain<void>());
      unawaited(p.stderr.drain<void>());
      return;
    } on ProcessException {
      // Windows Terminal not installed — fall through to cmd.exe.
    }
    final p = await Process.start(
      'cmd.exe',
      ['/k', 'cd', '/d', path],
    );
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
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
Future<void> runInTerminal({
  required String executable,
  required List<String> args,
  required String workingDirectory,
}) async {
  if (Platform.isWindows) {
    try {
      final p = await Process.start(
        'wt.exe',
        [
          '-d', _escapeWtArg(workingDirectory),
          _escapeWtArg(executable),
          ...args.map(_escapeWtArg),
        ],
      );
      unawaited(p.stdout.drain<void>());
      unawaited(p.stderr.drain<void>());
      return;
    } on ProcessException {
      // Windows Terminal not installed — fall through to cmd.exe.
    }
    final cmdLine = StringBuffer('"${_escapeCmdArg(executable)}"');
    for (final a in args) {
      cmdLine.write(' "${_escapeCmdArg(a)}"');
    }
    final p = await Process.start(
      'cmd.exe',
      ['/K', cmdLine.toString()],
      workingDirectory: workingDirectory,
    );
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    return;
  }
  if (Platform.isMacOS) {
    await _macRunInTerminal(executable, args, workingDirectory);
    return;
  }
  if (Platform.isLinux) {
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
/// GUI launchers (`code .`, `cursor .`) that fork their own window.
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

/// Reveal [absPath] in the platform file manager with the file selected
/// (where supported). Windows: `explorer /select,<path>`. macOS:
/// `open -R <path>`. Linux: `xdg-open <parent>` (no per-file selection).
Future<void> revealInFileManager(String absPath) async {
  final Process p;
  File? cleanupFile;
  if (Platform.isWindows) {
    final script = await _writeWindowsRevealScript(absPath);
    cleanupFile = script;
    p = await Process.start('cmd.exe', _windowsRevealBatchArgs(script.path));
  } else if (Platform.isMacOS) {
    p = await Process.start('open', ['-R', absPath]);
  } else if (Platform.isLinux) {
    final idx = absPath.lastIndexOf(Platform.pathSeparator);
    final dir = idx >= 0 ? absPath.substring(0, idx) : '.';
    p = await Process.start('xdg-open', [dir]);
  } else {
    throw UnsupportedError(
      'revealInFileManager: ${Platform.operatingSystem}',
    );
  }
  unawaited(p.stdout.drain<void>());
  unawaited(p.stderr.drain<void>());
  final fileToDelete = cleanupFile;
  if (fileToDelete != null) {
    unawaited(
      p.exitCode.whenComplete(() async {
        await _cleanupWindowsRevealScript(fileToDelete);
      }),
    );
  }
}

// ---------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------

/// macOS terminal launch via temp `.command` script.
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
  await f.writeAsString(
    '#!/bin/bash\n'
    'cd ${_shQuote(workingDirectory)}\n'
    'rm -- "\$0"\n'
    '$cmdLine\n'
    'exec bash\n',
    flush: true,
  );
  await Process.run('chmod', ['+x', f.path]);
  final p = await Process.start('open', [f.path]);
  unawaited(p.stdout.drain<void>());
  unawaited(p.stderr.drain<void>());
}

Future<File> _writeWindowsRevealScript(String absPath) async {
  final tmp = await Directory.systemTemp.createTemp('manifold-reveal-');
  final f = File('${tmp.path}${Platform.pathSeparator}reveal.cmd');
  await f.writeAsString(_windowsRevealBatchScript(absPath), flush: true);
  return f;
}

Future<void> _cleanupWindowsRevealScript(File script) async {
  try {
    await script.delete();
  } on FileSystemException {
    // Best-effort cleanup only; reveal should not fail after launch.
  }
  try {
    await script.parent.delete();
  } on FileSystemException {
    // The temp directory may already be gone or contain unexpected files.
  }
}

String _windowsRevealBatchScript(String absPath) {
  final escapedPath = _escapeBatchDoubleQuotedLiteral(absPath);
  return '@echo off\r\n'
      'start "" explorer.exe /select,"$escapedPath"\r\n'
      'exit /b %ERRORLEVEL%\r\n';
}

List<String> _windowsRevealBatchArgs(String scriptPath) => [
      '/d',
      '/c',
      'call',
      scriptPath,
    ];

String _escapeBatchDoubleQuotedLiteral(String value) =>
    value.replaceAll('^', '^^').replaceAll('%', '%%').replaceAll('"', '""');

/// Single-quote-wrap [arg] for bash.
String _shQuote(String arg) {
  final escaped = arg.replaceAll("'", r"'\''");
  return "'$escaped'";
}

/// Escape an arg for `cmd.exe /K "..."`. Neutralizes `%` expansion
/// and embedded double quotes inside a double-quoted span.
String _escapeCmdArg(String arg) =>
    arg.replaceAll('%', '%%').replaceAll('"', r'\"');

/// Escape an arg for `wt.exe`'s parser (neutralize embedded `"`).
String _escapeWtArg(String arg) => arg.replaceAll('"', r'\"');

@visibleForTesting
String escapeCmdArgForTesting(String arg) => _escapeCmdArg(arg);

@visibleForTesting
String escapeWtArgForTesting(String arg) => _escapeWtArg(arg);

@visibleForTesting
String windowsRevealBatchScriptForTesting(String absPath) =>
    _windowsRevealBatchScript(absPath);

@visibleForTesting
List<String> windowsRevealBatchArgsForTesting(String scriptPath) =>
    _windowsRevealBatchArgs(scriptPath);
