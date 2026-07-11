// atomic_write.dart — one crash-consistent write primitive for every
// snapshot store under lib/backend/.
//
// The bug class this closes: a store that persists a whole-file snapshot
// with a single truncating `writeAsString`/`writeAsBytes` drops the old
// contents the instant the file is opened, so a process death mid-write
// leaves a byte-prefix that no parser accepts — the torn-snapshot shape
// (historical bug B20: a torn settings.json wiped the whole snapshot to
// defaults). The fix is the temp-then-rename choreography AiApiKeysStore
// already used, factored out here so every store shares one audited path.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Atomically replace [target]'s contents with [bytes].
///
/// Choreography: write `<target>.tmp` with `flush: true`, then
/// `tmp.rename(target.path)`, then a best-effort fsync of the parent
/// directory.
///
/// Guarantees:
///   * Process-crash atomic. A reader/loader at any instant observes either
///     the complete OLD file or the complete NEW file — never a byte-prefix.
///     The rename publishes the fully-written temp in one step; a crash
///     before it leaves the prior target intact, a crash after it leaves the
///     new bytes. The temp file never has the target's name, so a torn temp
///     is never loaded. This holds unconditionally and is what the
///     crash-consistency suite (torn_write_crash_consistency_test.dart)
///     verifies.
///   * File-data durability. `flush: true` is a real fsync/FlushFileBuffers
///     on the platforms this app ships, so the temp's bytes are on stable
///     storage before the rename is issued — closing the classic "rename
///     lands, data didn't" zero-length-file window.
///   * Directory-entry durability (best-effort). After the rename, the
///     parent directory is fsync'd so the rename's own metadata reaches
///     stable storage — on filesystems that persist a rename only on a
///     directory fsync (ext4 default, etc.), a power loss right after the
///     rename could otherwise leave the target absent or stale despite the
///     flushed temp. On POSIX this is `open(dir, O_RDONLY)` → `fsync(fd)` →
///     `close(fd)` via libc through dart:ffi (dart:io exposes no directory
///     fsync). On Windows it is a documented no-op: NTFS journals rename
///     metadata, so a directory-handle FlushFileBuffers is not the mechanism
///     there. The dir fsync is strictly BEST-EFFORT — the rename already
///     succeeded, so any failure (unopenable dir, in-memory FS under test,
///     unsupported platform) is swallowed and never thrown, never corrupting
///     anything.
///
/// NO delete-target-first. Empirically verified on this machine: Dart
/// `File.rename` over an existing target on Windows replaces atomically
/// (MOVEFILE_REPLACE_EXISTING), so a delete-first step only opens a window
/// where the target is absent — harmful, never necessary.
///
/// Windows sharing caveat + retry. On Windows a rename over a target that a
/// reader (or an AV scanner) currently holds open fails with
/// [PathAccessException] (errno 5). A transiently-open reader must not be
/// able to corrupt anything, so the rename is retried a few times with a
/// short backoff. On final failure this throws — deliberately leaving the
/// prior target intact and the flushed temp behind. That is the correct
/// failure mode: no data is lost.
///
/// The temp name is unique per write (`<target>.<pid>.<seq>.tmp`): a FIXED
/// temp name races across processes — two writers of the same target both
/// write `<target>.tmp`, one renames it away, and the loser's rename fails
/// with errno 2 (observed live from parallel test processes sharing a data
/// dir). Uniqueness makes every writer publish its own complete payload;
/// last rename wins, nobody errors.
///
/// [beforeRename] runs against the fully-written temp before it is published
/// — for callers that must stamp permissions on the bytes before they become
/// visible under the target name (see AiApiKeysStore).
Future<void> writeFileAtomic(
  File target,
  List<int> bytes, {
  Future<void> Function(File tmp)? beforeRename,
}) async {
  await target.parent.create(recursive: true);
  final tmp = File('${target.path}.$pid.${_tmpSeq++}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  if (beforeRename != null) await beforeRename(tmp);
  await _renameWithRetry(tmp, target.path);
  // The rename has landed (target-data is durable via flush:true). Now make
  // the rename's directory entry durable too — best-effort, never fatal.
  fsyncParentDirBestEffort(target.parent.path);
}

int _tmpSeq = 0;

/// Best-effort fsync of directory [dirPath] so a just-completed rename's
/// metadata reaches stable storage. See [writeFileAtomic]'s "directory-entry
/// durability" note. Never throws: a failure here cannot corrupt anything —
/// the rename already succeeded — so it is logged-by-omission and swallowed.
///
/// Exposed (not private) so a test can drive it directly and confirm it runs
/// without throwing on the host OS.
void fsyncParentDirBestEffort(String dirPath) {
  // Windows: NTFS journals rename metadata; a directory-handle
  // FlushFileBuffers is not the durability mechanism. Documented no-op.
  // (DynamicLibrary.process() is also unavailable on Windows.)
  if (!parentDirectoryFsyncSupported) return;
  try {
    final open = _libc
        .lookupFunction<
          Int Function(Pointer<Utf8>, Int),
          int Function(Pointer<Utf8>, int)
        >('open');
    final fsync = _libc.lookupFunction<Int Function(Int), int Function(int)>(
      'fsync',
    );
    final close = _libc.lookupFunction<Int Function(Int), int Function(int)>(
      'close',
    );
    final cPath = dirPath.toNativeUtf8();
    try {
      // O_RDONLY == 0 on Linux and macOS; opening a directory read-only is
      // the portable way to obtain an fd to fsync.
      final fd = open(cPath, 0);
      if (fd < 0) return; // couldn't open (e.g. in-memory FS under test)
      try {
        fsync(fd); // ignore the return code — best-effort
      } finally {
        close(fd);
      }
    } finally {
      malloc.free(cPath);
    }
  } catch (_) {
    // Swallow: dir fsync is best-effort. The rename is already durable data-
    // wise; a missing symbol / unsupported platform must not fail the write.
  }
}

/// Whether this host supports the POSIX parent-directory fsync used by
/// [fsyncParentDirBestEffort]. Kept public so the intentional OS capability
/// boundary is exercised by the cross-OS differential oracle.
bool get parentDirectoryFsyncSupported => !Platform.isWindows;

/// libc for the POSIX directory fsync (see [fsyncParentDirBestEffort]). Only
/// resolved on non-Windows platforms — the getter is never reached on Windows
/// because [fsyncParentDirBestEffort] returns first. `DynamicLibrary.process()`
/// exposes libc's `open`/`fsync`/`close`, already linked into every POSIX
/// Dart/Flutter process, so no `.so`/`.dylib` name needs hardcoding.
final DynamicLibrary _libc = DynamicLibrary.process();

/// [writeFileAtomic] convenience for text payloads. Encodes [contents] with
/// [encoding] (UTF-8 by default) — byte-identical to a `writeAsString` of the
/// same string, so a store swept onto this keeps its exact on-disk format.
Future<void> writeFileAtomicString(
  File target,
  String contents, {
  Encoding encoding = utf8,
  Future<void> Function(File tmp)? beforeRename,
}) => writeFileAtomic(
  target,
  encoding.encode(contents),
  beforeRename: beforeRename,
);

Future<void> _renameWithRetry(File tmp, String targetPath) async {
  const maxAttempts = 5;
  for (var attempt = 1; ; attempt++) {
    try {
      await tmp.rename(targetPath);
      return;
    } on PathAccessException {
      // A reader/AV scanner holds the target open (Windows sharing). Back
      // off briefly and retry; the flushed temp is safe until then.
      if (attempt >= maxAttempts) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 10 * attempt));
    }
  }
}
