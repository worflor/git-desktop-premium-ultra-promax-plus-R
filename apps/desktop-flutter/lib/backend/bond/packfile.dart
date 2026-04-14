// ═════════════════════════════════════════════════════════════════════════
// bond/packfile.dart — git object transfer helpers
//
// Bond reuses standard git packfiles as its object-transfer format.
// Sender pipes `git pack-objects --stdout` with a list of wanted
// hashes; receiver pipes the bytes into `git index-pack --stdin`
// and lands the objects in its .git/objects tree.
//
// Delta compression, thin packs, and common-ancestor negotiation all
// come free from git itself. Bond only owns the envelope around these
// byte streams (see [BondPacketType.objectPack]). Chunking onto the
// wire is Whisper's job; this module hands the transport a complete
// pack blob to chunk.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Result of a packfile build.
class PackfileBuildResult {
  PackfileBuildResult({required this.bytes, required this.objectCount});

  /// The raw packfile content as produced by `git pack-objects --stdout`.
  /// Can be piped directly into a receiver's `git index-pack --stdin`.
  final Uint8List bytes;

  /// Number of objects in the pack, parsed from git's stderr
  /// progress output. Informational; transport doesn't need it.
  final int objectCount;
}

/// Runs `git pack-objects --stdout --revs` with the given set of
/// wanted commit hashes. The output packfile includes every object
/// reachable from `wanted` minus everything reachable from `have`
/// (thin-pack-style; `have` shrinks transfer on resend).
///
/// [repoPath] must be a git working directory or bare repo.
/// Throws on git process failure; caller wraps in a GitResult.
Future<PackfileBuildResult> buildPackfile({
  required String repoPath,
  required List<String> wanted,
  List<String> have = const [],
}) async {
  if (wanted.isEmpty) {
    return PackfileBuildResult(
      bytes: Uint8List(0),
      objectCount: 0,
    );
  }

  // `git pack-objects --stdout --revs`: reads a list of positive/
  // negative refs from stdin (one per line, `^hash` for negatives =
  // "I already have this, don't include its closure") and writes a
  // packfile to stdout. `--thin` would produce a delta-against-have
  // pack; omitted for v1 because it requires `--fix-thin` on receive.
  final process = await Process.start(
    'git',
    ['pack-objects', '--stdout', '--revs'],
    workingDirectory: repoPath,
    runInShell: false,
  );

  // Write wanted + ^have lines. Encoded as UTF-8 with LF terminators
  // — the format `git rev-list` accepts.
  final wantStdin = StringBuffer();
  for (final hash in wanted) {
    wantStdin.writeln(hash);
  }
  for (final hash in have) {
    wantStdin.writeln('^$hash');
  }
  process.stdin.write(wantStdin.toString());
  await process.stdin.flush();
  await process.stdin.close();

  // Collect stdout (packfile bytes) and stderr (progress / object
  // count) in parallel.
  final stdoutBytes = BytesBuilder(copy: false);
  final stdoutFuture = process.stdout.listen(stdoutBytes.add).asFuture<void>();
  final stderrBuffer = StringBuffer();
  final stderrFuture = process.stderr
      .transform(utf8.decoder)
      .listen(stderrBuffer.write)
      .asFuture<void>();

  final exitCode = await process.exitCode;
  await stdoutFuture;
  await stderrFuture;

  if (exitCode != 0) {
    throw ProcessException(
      'git',
      const ['pack-objects', '--stdout', '--revs'],
      stderrBuffer.toString().trim(),
      exitCode,
    );
  }

  // git's pack-objects writes a progress line like
  //   "Enumerating objects: 4829, done.\nCounting objects: 100% (4829/4829)..."
  // to stderr. Extract the count if we can; fall back to -1 on parse
  // failure (it's informational, not load-bearing).
  final countMatch = RegExp(r'Counting objects:\s+\d+%\s+\((\d+)/')
      .firstMatch(stderrBuffer.toString());
  final count = countMatch != null
      ? int.tryParse(countMatch.group(1)!) ?? -1
      : -1;

  return PackfileBuildResult(
    bytes: stdoutBytes.toBytes(),
    objectCount: count,
  );
}

/// Writes a received packfile into the repo's object store via
/// `git index-pack --stdin`. Optionally [fixThin] for thin-pack
/// reconstitution when the sender used `--thin` (not in v1 but
/// the flag is wired for forward compatibility).
///
/// Returns the `pack-<hash>.pack` filename git assigned, parsed from
/// stdout. Throws on process failure.
Future<String> indexPackfile({
  required String repoPath,
  required Uint8List packBytes,
  bool fixThin = false,
}) async {
  if (packBytes.isEmpty) {
    throw ArgumentError('indexPackfile called with empty pack bytes');
  }

  final args = <String>[
    'index-pack',
    '--stdin',
    if (fixThin) '--fix-thin',
  ];
  final process = await Process.start(
    'git',
    args,
    workingDirectory: repoPath,
    runInShell: false,
  );

  // Feed the pack into stdin in one shot. For large packs this
  // buffers the full blob in memory on both sides of the pipe; for
  // Bond's typical working-set transfers this is fine. Huge clones
  // should spool to a temp file between wire receive and index-pack,
  // a v2 optimisation.
  process.stdin.add(packBytes);
  await process.stdin.flush();
  await process.stdin.close();

  final stdoutBuffer = StringBuffer();
  final stdoutFuture = process.stdout
      .transform(utf8.decoder)
      .listen(stdoutBuffer.write)
      .asFuture<void>();
  final stderrBuffer = StringBuffer();
  final stderrFuture = process.stderr
      .transform(utf8.decoder)
      .listen(stderrBuffer.write)
      .asFuture<void>();

  final exitCode = await process.exitCode;
  await stdoutFuture;
  await stderrFuture;

  if (exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      stderrBuffer.toString().trim(),
      exitCode,
    );
  }

  // git index-pack emits the pack hash on stdout; filename is
  // pack-<hash>.pack. Return a sensible identifier for logging.
  final hash = stdoutBuffer.toString().trim();
  return hash.isEmpty ? '(unknown)' : 'pack-$hash.pack';
}

/// Lightweight "do I have this commit locally?" check via
/// `git cat-file -e <hash>`. Used for OBJECT_HAVE bitmap building.
Future<bool> hasObject(String repoPath, String hash) async {
  final result = await Process.run(
    'git',
    ['cat-file', '-e', hash],
    workingDirectory: repoPath,
    runInShell: false,
  );
  return result.exitCode == 0;
}

/// Returns the hashes of commits reachable from [startHash], up to
/// [limit] most-recent. Used by senders to estimate the have/want
/// delta before asking for a packfile. Returns empty on any failure.
Future<List<String>> reachableCommits({
  required String repoPath,
  required String startHash,
  int limit = 256,
}) async {
  final result = await Process.run(
    'git',
    ['rev-list', '-n', '$limit', startHash],
    workingDirectory: repoPath,
    runInShell: false,
  );
  if (result.exitCode != 0) return const [];
  return (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
}
