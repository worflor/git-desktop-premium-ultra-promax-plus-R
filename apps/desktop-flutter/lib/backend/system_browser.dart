import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

/// Opens [url] in the user's default browser.
///
/// Security: rejects any scheme other than `http` / `https` before
/// reaching the platform dispatch. Without the guard, protocol
/// handlers for `file://`, UNC paths, `ms-appinstaller:`, etc.
/// could be invoked by a hostile URL. Restricting at the chokepoint
/// means every caller gets the same defense.
///
/// Platform paths:
///   * **Windows** — `rundll32 url.dll,FileProtocolHandler <url>`.
///     Dispatches directly to the registered handler without cmd.exe
///     shell interpretation, so URL metacharacters (`&`, `|`, etc.)
///     cannot be parsed as command separators.
///   * **macOS** — `open <url>`.
///   * **Linux** — `xdg-open <url>`.
///
/// Throws:
///   * [ArgumentError] if [url] is not a syntactically valid http(s)
///     URL.
///   * [ProcessException] if the platform CLI fails to spawn.
///   * [UnsupportedError] on any other platform.
Future<void> openInSystemBrowser(String url) async {
  if (!isAllowedBrowserUrl(url)) {
    throw ArgumentError.value(
      url,
      'url',
      'openInSystemBrowser only accepts http(s) URLs',
    );
  }
  final Process p;
  if (Platform.isWindows) {
    p = await Process.start(
        'rundll32', ['url.dll,FileProtocolHandler', url]);
  } else if (Platform.isMacOS) {
    p = await Process.start('open', [url]);
  } else if (Platform.isLinux) {
    p = await Process.start('xdg-open', [url]);
  } else {
    throw UnsupportedError(
      'openInSystemBrowser does not support ${Platform.operatingSystem}',
    );
  }
  unawaited(p.stdout.drain<void>());
  unawaited(p.stderr.drain<void>());
}

/// True when [url] parses as a syntactically valid `http://` or
/// `https://` URL. Exposed for tests because the open path itself
/// has platform-dependent side effects we don't want to drive from
/// `flutter test`.
@visibleForTesting
bool isAllowedBrowserUrl(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null) return false;
  return parsed.hasAuthority &&
      (parsed.isScheme('https') || parsed.isScheme('http'));
}
