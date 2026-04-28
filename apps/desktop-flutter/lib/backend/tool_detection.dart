import 'dart:async';
import 'dart:io';

// PATH-resolution probe for external tool executables. Used by the
// settings page to render only the preset chips for tools the user
// actually has installed — no need to guess which IDE / AI CLI is
// available, the OS already knows.
//
// Windows uses `where`, POSIX uses `which`. Both exit 0 when the
// query resolves and non-zero otherwise. We don't read stdout — the
// exit code is the answer.
//
// Failures (PATH lookup tool itself missing — extremely unlikely)
// are treated as "not installed" so the UI degrades gracefully to
// just the custom-preset escape hatch.

/// Probe PATH for [executable]. Returns true when the OS shell
/// resolves the name to a real binary, false otherwise. Cheap
/// (~5–30ms per call) but fan out via [detectAll] when probing
/// many candidates so the round-trips run in parallel.
Future<bool> isOnPath(String executable) async {
  if (executable.trim().isEmpty) return false;
  try {
    final tool = Platform.isWindows ? 'where' : 'which';
    final result = await Process.run(tool, [executable]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  } catch (_) {
    return false;
  }
}

/// Probe many executables in parallel, returning the subset that
/// resolved on PATH. Order in the input list is irrelevant — callers
/// look up by name.
Future<Set<String>> detectAll(Iterable<String> executables) async {
  final names = executables.toSet();
  if (names.isEmpty) return const {};
  final probes = await Future.wait(
    names.map((name) async => (name, await isOnPath(name))),
  );
  return {
    for (final (name, found) in probes)
      if (found) name,
  };
}
