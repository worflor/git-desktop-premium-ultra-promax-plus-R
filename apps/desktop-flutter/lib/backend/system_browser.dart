import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

/// Thrown when [openInSystemBrowser] fails on Windows. The Win32
/// `ShellExecuteW` API returns an error code as its return value
/// (≤32 means failure); this exception preserves it for diagnostics.
class WindowsBrowserException implements Exception {
  final int code;
  final String message;
  WindowsBrowserException(this.code, this.message);

  @override
  String toString() =>
      'WindowsBrowserException(code=$code): $message';
}

/// Opens [url] in the user's default browser.
///
/// Security: the URL may originate from a remote manifest (the release
/// check pulls a JSON file off the network), so this helper avoids
/// any code path that re-parses the URL through a command shell, AND
/// rejects any scheme other than `http` / `https` before it reaches
/// the platform dispatch:
///
///   * Without the scheme guard, a Windows `ShellExecuteW("open", ...)`
///     will dispatch through whatever protocol handler is registered
///     — `file://`, UNC paths like `\\host\share\thing.exe`,
///     `ms-appinstaller:`, `javascript:`, `mailto:`, and any custom
///     scheme an installed app has claimed. A hostile or MITM'd
///     manifest could push any of those.
///   * Restricting at the chokepoint means every caller (manifest
///     download button, contact link easter egg, future surfaces)
///     gets the same defense without per-callsite plumbing.
///
/// Platform paths once the scheme is accepted:
///   * **Windows** — `ShellExecuteW` via FFI. URL handed to Win32 as
///     a UTF-16 string; no `cmd` pass, no shell metachars to escape,
///     no second argv parse.
///   * **macOS** — `open <url>`. LaunchServices CLI; argv direct.
///   * **Linux** — `xdg-open <url>`. argv direct.
///
/// Throws:
///   * [ArgumentError] if [url] is not a syntactically valid http(s)
///     URL.
///   * [WindowsBrowserException] if `ShellExecuteW` returns ≤ 32.
///   * [ProcessException] if the macOS/Linux CLI fails to spawn or
///     reports a non-zero exit code at the OS level.
///   * [UnsupportedError] on any other platform.
Future<void> openInSystemBrowser(String url) async {
  if (!isAllowedBrowserUrl(url)) {
    throw ArgumentError.value(
      url,
      'url',
      'openInSystemBrowser only accepts http(s) URLs',
    );
  }
  if (Platform.isWindows) {
    _openOnWindows(url);
    return;
  }
  if (Platform.isMacOS) {
    final p = await Process.start('open', [url]);
    // Drain so the OS can release the FDs once the browser process
    // detaches; the streams are irrelevant to us.
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    return;
  }
  if (Platform.isLinux) {
    final p = await Process.start('xdg-open', [url]);
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    return;
  }
  throw UnsupportedError(
    'openInSystemBrowser does not support ${Platform.operatingSystem}',
  );
}

/// True when [url] parses as a syntactically valid `http://` or
/// `https://` URL. Exposed for tests because the open path itself
/// has platform-dependent side effects we don't want to drive from
/// `flutter test`.
@visibleForTesting
bool isAllowedBrowserUrl(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null) return false;
  // hasAuthority filters out scheme-only / path-only oddballs like
  // `https:` (no host) which Uri.tryParse will happily accept.
  return parsed.hasAuthority &&
      (parsed.isScheme('https') || parsed.isScheme('http'));
}

/// Windows-only: dispatch [url] via `ShellExecuteW`. Synchronous —
/// `ShellExecuteW` returns as soon as the protocol handler has been
/// resolved and launched, which is fast enough that an isolate
/// hop would be more overhead than benefit.
void _openOnWindows(String url) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  // ShellExecuteW signature:
  //   HINSTANCE ShellExecuteW(
  //     HWND hwnd, LPCWSTR lpOperation, LPCWSTR lpFile,
  //     LPCWSTR lpParameters, LPCWSTR lpDirectory, INT nShowCmd);
  // Return value is an HINSTANCE-shaped error code; >32 means success.
  final shellExecute = shell32.lookupFunction<
      IntPtr Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>,
          Pointer<Utf16>, Pointer<Utf16>, Int32),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>,
          Pointer<Utf16>, int)>('ShellExecuteW');

  final op = 'open'.toNativeUtf16();
  final file = url.toNativeUtf16();
  try {
    // SW_SHOWNORMAL = 1.
    final result = shellExecute(0, op, file, nullptr, nullptr, 1);
    if (result <= 32) {
      throw WindowsBrowserException(
        result,
        _windowsShellErrorMessage(result),
      );
    }
  } finally {
    malloc.free(op);
    malloc.free(file);
  }
}

/// Maps the documented `ShellExecuteW` failure codes to short
/// human-readable strings. Unknown codes fall through to a generic
/// label so the caller still has a stable surface for diagnostics.
String _windowsShellErrorMessage(int code) {
  switch (code) {
    case 0:
      return 'out of memory or resources';
    case 2:
      return 'file not found';
    case 3:
      return 'path not found';
    case 5:
      return 'access denied';
    case 8:
      return 'out of memory';
    case 11:
      return 'invalid executable format';
    case 26:
      return 'sharing violation';
    case 27:
      return 'association incomplete';
    case 28:
      return 'DDE timeout';
    case 29:
      return 'DDE failure';
    case 30:
      return 'DDE busy';
    case 31:
      return 'no association for this protocol (no default browser?)';
    case 32:
      return 'DLL not found';
    default:
      return 'failed (code $code)';
  }
}
