// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// io_faults.dart — a journaling IOOverrides for torn-write / crash-consistency
// testing.
//
// The one bug class this exists to attack: a store's persist() is a *sequence*
// of filesystem effects (truncate a file, write bytes, flush, rename a temp
// over the target, delete-then-rename, …). A power loss / process kill can
// land between ANY two of those effects — or partway through a single write,
// leaving a file with a byte-prefix of what should have been there. A store is
// crash-consistent iff a subsequent load() degrades safely from EVERY such
// intermediate state (returns the old value, the new value, or a documented
// fallback — never a franken-state, never a throw, never silently wiping an
// unrelated store's file).
//
// This harness makes those intermediate states enumerable and replayable:
//
//   1. [journalWrites] runs a persist body under an [IOOverrides] that records
//      every *write-effect* (truncating write, append, openWrite-sink, rename,
//      delete, create) as an ordered [Journal] of byte-level [JournalOp]s. The
//      body still executes for real, so the store's own read-modify-write
//      logic (e.g. "rename only if the temp wrote", "delete before rename")
//      runs exactly as in production.
//   2. [enumerateCrashPoints] turns a [Journal] into the finite set of points a
//      crash could occur: for each op, a byte cut at {0, 1, mid, len-1, len}
//      (deduped; plus sink chunk boundaries), and for rename/delete a
//      before/after split (rename and delete are themselves atomic — you don't
//      get half a rename — so the interesting crash is whether it happened).
//   3. [replayCrash] materialises a fresh directory from a base snapshot (the
//      pre-persist state), applies ops 0..i-1 in full, then applies op i cut at
//      the crash point — reproducing exactly what would be on disk had the
//      process died there. The store's real load() is then pointed at it.
//
// ── Two failure models ─────────────────────────────────────────────────────
//
// The crash-point sweep above is the *process-death* model: the process
// vanishes between two syscalls, so ops 0..i-1 are on disk exactly as issued,
// op i is a byte-prefix, and ops after i never ran. Every write that the
// process *thought* it completed is durable.
//
// Real power loss is strictly weaker, and catches a bug class process-death
// cannot. A write's bytes are durable only once the OS has *flushed* them to
// stable storage; an unflushed write's data can be lost even though a syscall
// the program issued LATER (a rename, say) did land. That is the classic
// "rename lands, data didn't" zero-length-file corruption: the temp file's
// bytes evaporate but the rename that published it over the target survives,
// so the target is now a torn/empty file. [enumeratePowerLossPoints] models
// exactly this: for each UNFLUSHED write op it cuts that op's payload at
// {0, 1, mid} while applying EVERY other op — including ops sequenced after
// it — in full. [replayPowerLoss] materialises the result.
//
// Durability is tracked per op. `writeAsString`/`writeAsBytes(flush: true)`
// and an `IOSink` that received an explicit `flush()` before `close()` are
// durability barriers: their bytes are treated as stable and are NEVER cut by
// the power-loss enumerator. `flush: false` (the Dart default) and a sink
// closed without an explicit flush are unflushed and are the only ops that
// generate power-loss states.
//
// Honest limits of the power-loss model: it does NOT model rename/directory
// durability itself — a rename is always applied in full, so "the rename's
// own directory entry wasn't fsync'd (dir-fsync)" is out of scope. It assumes
// Dart's `flush: true` maps to a real `fsync`/`FlushFileBuffers` (it does on
// the platforms this app ships), so a `flush: true` write is taken as fully
// durable. Both simplifications make the model *optimistic* about flushed
// writes and pessimistic only where a store genuinely skipped a flush.
//
// Everything is path-relative to the store's data dir and joined with
// package:path, so a journal captured on Windows replays byte-identically under
// WSL2 Linux and vice-versa. Journal keys are normalised to '/'-separated
// POSIX-relative form so the separator never leaks into an assertion.
//
// Interception is reliable here because every store constructs `File(...)`
// fresh per call, all persistence runs on the main isolate, and there is no
// FFI — so `IOOverrides` sees every write. Any File member a store touches that
// this harness does NOT explicitly journal trips a loud `UnsupportedError` via
// [_JournalFile.noSuchMethod] rather than silently escaping the journal.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Journal ops — byte-level write effects
// ---------------------------------------------------------------------------

/// One recorded write-effect. Paths are POSIX-relative to the journal's base
/// data dir (see [journalWrites]); [applyFull]/[applyPartial] re-root them
/// under an arbitrary target dir, which is what lets a journal replay into a
/// fresh directory on any OS.
sealed class JournalOp {
  const JournalOp();

  /// Execute the effect completely (the process survived past this op).
  Future<void> applyFull(Directory target);

  /// The distinct crash-cut parameters for this op. For a write op these are
  /// byte offsets into the payload; for an atomic op (rename/delete/create)
  /// they are `0` (crashed just before it took effect) and `1` (just after).
  List<int> crashCuts();

  /// Execute the effect as interrupted at [cut] (see [crashCuts]).
  Future<void> applyPartial(Directory target, int cut);

  /// Human-readable label used in crash-point descriptions / failure output.
  String describe();
}

List<int> _writeCuts(int len) {
  final set = <int>{0, 1, len ~/ 2, len - 1, len};
  final out = [for (final c in set) if (c >= 0 && c <= len) c]..sort();
  return out;
}

/// A truncating whole-file write (`writeAsString`/`writeAsBytes` in the
/// default `FileMode.write`). The old file contents are gone the instant the
/// file is opened, so a crash mid-write leaves a *byte-prefix* of [bytes] and
/// nothing of the prior value — the classic torn-snapshot shape.
final class TruncateWrite extends JournalOp {
  const TruncateWrite(this.relPath, this.bytes, {this.flushed = false});
  final String relPath;
  final List<int> bytes;

  /// Whether the write was issued with `flush: true` — a durability barrier
  /// the power-loss enumerator treats as stable (never cut). See the header.
  final bool flushed;

  @override
  Future<void> applyFull(Directory target) =>
      _writeBytes(target, relPath, bytes);

  @override
  List<int> crashCuts() => _writeCuts(bytes.length);

  @override
  Future<void> applyPartial(Directory target, int cut) =>
      _writeBytes(target, relPath, bytes.sublist(0, cut));

  @override
  String describe() =>
      'truncate-write $relPath (${bytes.length}B${flushed ? ', flushed' : ''})';
}

/// An append write (`writeAsString`/`writeAsBytes` in `FileMode.append`). A
/// crash mid-append leaves the prior file plus a byte-prefix of [bytes]; the
/// danger is a partial last line with no terminator swallowing the *next*
/// record on a later append.
final class AppendWrite extends JournalOp {
  const AppendWrite(this.relPath, this.bytes, {this.flushed = false});
  final String relPath;
  final List<int> bytes;

  /// See [TruncateWrite.flushed].
  final bool flushed;

  @override
  Future<void> applyFull(Directory target) =>
      _appendBytes(target, relPath, bytes);

  @override
  List<int> crashCuts() => _writeCuts(bytes.length);

  @override
  Future<void> applyPartial(Directory target, int cut) =>
      _appendBytes(target, relPath, bytes.sublist(0, cut));

  @override
  String describe() =>
      'append-write $relPath (${bytes.length}B${flushed ? ', flushed' : ''})';
}

/// An `openWrite` sink rewrite. [chunks] are the individual add/write/writeln
/// payloads in order; their cumulative boundaries are crash points on top of
/// the usual byte cuts, because a sink flush can land on any chunk boundary.
final class SinkWrite extends JournalOp {
  SinkWrite(this.relPath, this.chunks, {required this.append});
  final String relPath;
  final List<List<int>> chunks;
  final bool append;

  /// Set true iff the sink received an explicit `flush()` before `close()`.
  /// A sink closed without a flush is unflushed (see the header): its bytes
  /// are power-loss-vulnerable even though a later rename may land. Mutated
  /// by [_JournalSink] as the body runs, so it is deliberately not `final`.
  bool flushed = false;

  List<int> get _payload => [for (final c in chunks) ...c];

  @override
  Future<void> applyFull(Directory target) => append
      ? _appendBytes(target, relPath, _payload)
      : _writeBytes(target, relPath, _payload);

  @override
  List<int> crashCuts() {
    final len = _payload.length;
    final set = <int>{0, 1, len ~/ 2, len - 1, len};
    var acc = 0;
    for (final c in chunks) {
      acc += c.length;
      set.add(acc);
    }
    final out = [for (final c in set) if (c >= 0 && c <= len) c]..sort();
    return out;
  }

  @override
  Future<void> applyPartial(Directory target, int cut) {
    final prefix = _payload.sublist(0, cut);
    return append
        ? _appendBytes(target, relPath, prefix)
        : _writeBytes(target, relPath, prefix);
  }

  @override
  String describe() =>
      '${append ? 'sink-append' : 'sink-write'} $relPath '
      '(${chunks.length} chunks, ${_payload.length}B${flushed ? ', flushed' : ''})';
}

/// A `rename`. Renames are atomic — you never observe half of one — so the
/// only crash question is whether it happened (`1`) or not (`0`).
final class Rename extends JournalOp {
  const Rename(this.fromRel, this.toRel);
  final String fromRel;
  final String toRel;

  @override
  Future<void> applyFull(Directory target) =>
      _move(target, fromRel, toRel);

  @override
  List<int> crashCuts() => const [0, 1];

  @override
  Future<void> applyPartial(Directory target, int cut) =>
      cut == 0 ? Future<void>.value() : applyFull(target);

  @override
  String describe() => 'rename $fromRel -> $toRel';
}

/// A `delete`. Atomic like [Rename]: crashed-before (`0`) or after (`1`).
final class Delete extends JournalOp {
  const Delete(this.relPath);
  final String relPath;

  @override
  Future<void> applyFull(Directory target) async {
    final f = File(_platformPath(target, relPath));
    if (await f.exists()) await f.delete();
  }

  @override
  List<int> crashCuts() => const [0, 1];

  @override
  Future<void> applyPartial(Directory target, int cut) =>
      cut == 0 ? Future<void>.value() : applyFull(target);

  @override
  String describe() => 'delete $relPath';
}

/// A `File.create`. Atomic: crashed-before (`0`) or after (`1`).
final class Create extends JournalOp {
  const Create(this.relPath);
  final String relPath;

  @override
  Future<void> applyFull(Directory target) async {
    final f = File(_platformPath(target, relPath));
    await f.parent.create(recursive: true);
    if (!await f.exists()) await f.create();
  }

  @override
  List<int> crashCuts() => const [0, 1];

  @override
  Future<void> applyPartial(Directory target, int cut) =>
      cut == 0 ? Future<void>.value() : applyFull(target);

  @override
  String describe() => 'create $relPath';
}

// ---------------------------------------------------------------------------
// Journal + crash points
// ---------------------------------------------------------------------------

/// An ordered log of the write-effects a persist body performed, captured by
/// [journalWrites]. [baseDir] is the absolute data dir the ops are relative to.
class Journal {
  Journal(this.baseDir, this.ops);
  final String baseDir;
  final List<JournalOp> ops;

  @override
  String toString() =>
      'Journal(${ops.length} ops: ${ops.map((o) => o.describe()).join(' | ')})';
}

/// One point at which a crash is simulated: op [opIndex] interrupted at [cut].
class CrashPoint {
  const CrashPoint(this.opIndex, this.cut, this.opLabel);
  final int opIndex;
  final int cut;
  final String opLabel;

  @override
  String toString() => 'crash@op$opIndex[cut=$cut]: $opLabel';
}

/// Every point a crash could occur across [j]: each op's byte cuts (writes) or
/// before/after split (atomic ops). The final element — the last op cut at its
/// full length / "after" — is the fully-successful persist, so a caller that
/// replays every crash point also exercises the happy path.
List<CrashPoint> enumerateCrashPoints(Journal j) {
  final out = <CrashPoint>[];
  for (var i = 0; i < j.ops.length; i++) {
    final op = j.ops[i];
    final label = op.describe();
    for (final cut in op.crashCuts()) {
      out.add(CrashPoint(i, cut, label));
    }
  }
  return out;
}

// ── Power-loss points (see the two-failure-models note in the header) ──────

/// One power-loss / write-reordering state: UNFLUSHED write op [opIndex]'s
/// payload is cut at [cut] bytes, while every OTHER op — including ops
/// sequenced after it, and any rename that publishes the torn bytes over the
/// target — is applied in full. This is the "rename lands, data didn't" shape
/// that the process-death [CrashPoint] sweep cannot express.
class PowerLossPoint {
  const PowerLossPoint(this.opIndex, this.cut, this.opLabel);
  final int opIndex;
  final int cut;
  final String opLabel;

  @override
  String toString() => 'powerloss@op$opIndex[cut=$cut]: $opLabel';
}

/// True for a write op that was NOT flushed — the only ops the power-loss
/// model may tear. A flushed write is a durability barrier (see the header).
bool _isUnflushedWrite(JournalOp op) => switch (op) {
      TruncateWrite w => !w.flushed,
      AppendWrite w => !w.flushed,
      SinkWrite w => !w.flushed,
      _ => false,
    };

int _writePayloadLength(JournalOp op) => switch (op) {
      TruncateWrite w => w.bytes.length,
      AppendWrite w => w.bytes.length,
      SinkWrite w => w._payload.length,
      _ => 0,
    };

/// Every power-loss state across [j]: for each unflushed write op, a cut at
/// {0, 1, mid} of its payload. Flushed writes and atomic ops (rename/delete/
/// create) generate none — they are applied in full by [replayPowerLoss].
/// A journal whose every write is flushed yields the empty list, which is the
/// point: a fully-flushed persist has no power-loss surface at all.
List<PowerLossPoint> enumeratePowerLossPoints(Journal j) {
  final out = <PowerLossPoint>[];
  for (var i = 0; i < j.ops.length; i++) {
    final op = j.ops[i];
    if (!_isUnflushedWrite(op)) continue;
    final len = _writePayloadLength(op);
    final cuts = <int>{0, 1, len ~/ 2}..removeWhere((c) => c < 0 || c > len);
    final sorted = cuts.toList()..sort();
    for (final cut in sorted) {
      out.add(PowerLossPoint(i, cut, op.describe()));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Recording (the IOOverrides + wrappers)
// ---------------------------------------------------------------------------

/// Runs [body] (a store's persist choreography) with a [Journal] recording
/// every write-effect. The body executes for real against [baseDir], so its
/// own conditional logic (temp-then-rename, delete-if-exists, torn-write
/// probes) runs exactly as in production. Returns the ordered journal, with
/// paths relative to [baseDir].
Future<Journal> journalWrites(
  Directory baseDir,
  Future<void> Function() body,
) async {
  final ops = <JournalOp>[];
  final overrides = _JournalingIOOverrides(baseDir.absolute.path, ops);
  await IOOverrides.runWithIOOverrides(() => body(), overrides);
  return Journal(baseDir.absolute.path, ops);
}

final class _JournalingIOOverrides extends IOOverrides {
  _JournalingIOOverrides(this.baseDir, this.ops);
  final String baseDir;
  final List<JournalOp> ops;

  @override
  File createFile(String path) =>
      _JournalFile(super.createFile(path), this);

  String relOf(String path) => _posixRel(baseDir, path);
}

class _JournalFile implements File {
  _JournalFile(this._inner, this._ov);
  final File _inner;
  final _JournalingIOOverrides _ov;

  String get _rel => _ov.relOf(_inner.path);

  @override
  String get path => _inner.path;

  @override
  Directory get parent => _inner.parent;

  @override
  File get absolute => _inner.absolute;

  // ── writes: recorded ──────────────────────────────────────────────────

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    final bytes = encoding.encode(contents);
    _ov.ops.add(mode == FileMode.append || mode == FileMode.writeOnlyAppend
        ? AppendWrite(_rel, bytes, flushed: flush)
        : TruncateWrite(_rel, bytes, flushed: flush));
    return _inner.writeAsString(contents,
        mode: mode, encoding: encoding, flush: flush);
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    _ov.ops.add(mode == FileMode.append || mode == FileMode.writeOnlyAppend
        ? AppendWrite(_rel, List<int>.of(bytes), flushed: flush)
        : TruncateWrite(_rel, List<int>.of(bytes), flushed: flush));
    return _inner.writeAsBytes(bytes, mode: mode, flush: flush);
  }

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    final chunks = <List<int>>[];
    final op = SinkWrite(_rel, chunks,
        append: mode == FileMode.append || mode == FileMode.writeOnlyAppend);
    _ov.ops.add(op);
    return _JournalSink(
        _inner.openWrite(mode: mode, encoding: encoding), op, encoding);
  }

  @override
  Future<File> rename(String newPath) async {
    _ov.ops.add(Rename(_rel, _ov.relOf(newPath)));
    return _inner.rename(newPath);
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    _ov.ops.add(Delete(_rel));
    return _inner.delete(recursive: recursive);
  }

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    _ov.ops.add(Create(_rel));
    return _inner.create(recursive: recursive, exclusive: exclusive);
  }

  // ── reads / probes: forwarded, not recorded ───────────────────────────

  @override
  Future<bool> exists() => _inner.exists();
  @override
  bool existsSync() => _inner.existsSync();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _inner.readAsString(encoding: encoding);
  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      _inner.readAsStringSync(encoding: encoding);
  @override
  Future<Uint8List> readAsBytes() => _inner.readAsBytes();
  @override
  Uint8List readAsBytesSync() => _inner.readAsBytesSync();
  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) =>
      _inner.readAsLines(encoding: encoding);
  @override
  Future<int> length() => _inner.length();
  @override
  int lengthSync() => _inner.lengthSync();
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _inner.open(mode: mode);
  @override
  Future<FileStat> stat() => _inner.stat();
  @override
  FileStat statSync() => _inner.statSync();

  // Any File member a store reaches for that we haven't journaled must fail
  // loudly rather than escape the journal unseen.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'io_faults: unjournaled File member '
        '${invocation.memberName} on $path — add an explicit override so the '
        'write-effect is captured instead of silently escaping the journal.',
      );
}

class _JournalSink implements IOSink {
  _JournalSink(this._inner, this._op, this._encoding) : _chunks = _op.chunks;
  final IOSink _inner;
  final SinkWrite _op;
  final List<List<int>> _chunks;
  Encoding _encoding;

  @override
  Encoding get encoding => _encoding;
  @override
  set encoding(Encoding value) {
    _encoding = value;
    _inner.encoding = value;
  }

  @override
  void add(List<int> data) {
    _chunks.add(List<int>.of(data));
    _inner.add(data);
  }

  @override
  void write(Object? object) {
    final s = '$object';
    _chunks.add(_encoding.encode(s));
    _inner.write(object);
  }

  @override
  void writeln([Object? object = '']) {
    _chunks.add(_encoding.encode('$object\n'));
    _inner.writeln(object);
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    final s = objects.join(separator);
    _chunks.add(_encoding.encode(s));
    _inner.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    final s = String.fromCharCode(charCode);
    _chunks.add(_encoding.encode(s));
    _inner.writeCharCode(charCode);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);
  @override
  Future<void> flush() {
    // An explicit flush is the durability barrier the power-loss model keys
    // off (see the header): record it so [enumeratePowerLossPoints] exempts
    // this sink. close() alone does NOT set this — an unflushed close leaves
    // the bytes power-loss-vulnerable.
    _op.flushed = true;
    return _inner.flush();
  }

  @override
  Future<void> close() => _inner.close();
  @override
  Future<void> get done => _inner.done;
}

// ---------------------------------------------------------------------------
// Snapshot / restore / replay
// ---------------------------------------------------------------------------

/// Every regular file under [dir], mapped POSIX-relative-path -> bytes. The
/// pre-persist snapshot a crash replay is materialised from.
Future<Map<String, List<int>>> snapshotDir(Directory dir) async {
  final map = <String, List<int>>{};
  if (!await dir.exists()) return map;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      map[_posixRel(dir.absolute.path, entity.path)] =
          await entity.readAsBytes();
    }
  }
  return map;
}

/// Writes [snapshot] into [target] (creating parent dirs), replacing whatever
/// is there. Does NOT clear [target] first — call [clearDir] for that.
Future<void> restoreSnapshot(
  Map<String, List<int>> snapshot,
  Directory target,
) async {
  for (final entry in snapshot.entries) {
    await _writeBytes(target, entry.key, entry.value);
  }
}

/// Removes everything under [target] and recreates it empty.
Future<void> clearDir(Directory target) async {
  if (await target.exists()) await target.delete(recursive: true);
  await target.create(recursive: true);
}

/// Materialises [target] as the on-disk state produced by a crash at [p]:
/// starts from [baseSnapshot] (the pre-persist directory), applies journal ops
/// `0..p.opIndex-1` in full, then applies op `p.opIndex` interrupted at the
/// crash cut. [target] is cleared first, so it can be reused across points.
Future<void> replayCrash(
  Journal journal,
  Map<String, List<int>> baseSnapshot,
  Directory target,
  CrashPoint p,
) async {
  await clearDir(target);
  await restoreSnapshot(baseSnapshot, target);
  for (var i = 0; i < p.opIndex; i++) {
    await journal.ops[i].applyFull(target);
  }
  await journal.ops[p.opIndex].applyPartial(target, p.cut);
}

/// Materialises [target] as the on-disk state produced by a POWER LOSS at [p]:
/// starts from [baseSnapshot], applies every op in full EXCEPT the unflushed
/// write op `p.opIndex`, which is cut at `p.cut` bytes. Unlike [replayCrash],
/// ops sequenced *after* the torn write still apply — modelling a rename that
/// publishes the torn bytes over the target even though the data was never
/// flushed. [target] is cleared first, so it can be reused across points.
Future<void> replayPowerLoss(
  Journal journal,
  Map<String, List<int>> baseSnapshot,
  Directory target,
  PowerLossPoint p,
) async {
  await clearDir(target);
  await restoreSnapshot(baseSnapshot, target);
  for (var i = 0; i < journal.ops.length; i++) {
    if (i == p.opIndex) {
      await journal.ops[i].applyPartial(target, p.cut);
    } else {
      await journal.ops[i].applyFull(target);
    }
  }
}

/// Materialises [target] as the fully-successful persist: [baseSnapshot] with
/// every op applied in full. This is the S2 fixed point every crash/power-loss
/// sweep must reproduce when nothing is torn — the replay-fidelity anchor.
Future<void> replayFull(
  Journal journal,
  Map<String, List<int>> baseSnapshot,
  Directory target,
) async {
  await clearDir(target);
  await restoreSnapshot(baseSnapshot, target);
  for (final op in journal.ops) {
    await op.applyFull(target);
  }
}

// ---------------------------------------------------------------------------
// Path helpers (OS-portable)
// ---------------------------------------------------------------------------

/// POSIX-relative ('/'-joined) path of [path] under [base]. Normalising to a
/// single separator keeps journal keys stable across Windows and Linux.
String _posixRel(String base, String path) {
  final rel = p.relative(path, from: base);
  return p.split(rel).join('/');
}

/// Re-roots a POSIX-relative journal key under [target] as a native path.
String _platformPath(Directory target, String relPath) =>
    p.joinAll([target.path, ...relPath.split('/')]);

Future<void> _writeBytes(
  Directory target,
  String relPath,
  List<int> bytes,
) async {
  final file = File(_platformPath(target, relPath));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: false);
}

Future<void> _appendBytes(
  Directory target,
  String relPath,
  List<int> bytes,
) async {
  final file = File(_platformPath(target, relPath));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, mode: FileMode.append, flush: false);
}

Future<void> _move(Directory target, String fromRel, String toRel) async {
  final from = File(_platformPath(target, fromRel));
  if (!await from.exists()) return;
  final toPath = _platformPath(target, toRel);
  final toFile = File(toPath);
  await toFile.parent.create(recursive: true);
  // Windows rename fails if the target exists; match the stores that delete
  // first, so replay behaves identically on both OSes.
  if (await toFile.exists()) await toFile.delete();
  await from.rename(toPath);
}
