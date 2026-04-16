// engram_file_index_cache.dart — disk-persisted K-vector cache.
//
// The file index is expensive to build from scratch (read + tokenize +
// AR(2) fit + well match per file). On a thousand-file repo this is
// 5–15 seconds of pure CPU + I/O even when parallelised.
//
// Most of those files don't change between app launches. A
// content-aware disk cache skips the encode entirely for files whose
// (mtime, size) pair still matches what we saw last time — the same
// "has it changed" check `make` has used since 1976, and the same
// thing git's index uses to skip diff scans.
//
// One cache file per repository, keyed by repo path hash. Stored in
// the shared app data directory alongside other logos caches so it
// survives app restarts and repo switches.
//
// Binary layout ("EFIX" = Engram FIle indeX):
//   magic[4]          "EFIX"
//   version u32       = 1
//   pairs u32         must match brain.pairs or the file is discarded
//   n_entries u32
//   per entry:
//     path_len   u16
//     path utf-8[path_len]
//     mtime_ms   i64   (DateTime.millisecondsSinceEpoch of file at cache time)
//     size       u64
//     vocab_hits u32
//     mean_rms   f64
//     k_re f64[pairs]
//     k_im f64[pairs]
//     has_well u8      (0 or 1)
//     if has_well:
//       well_name_len       u16
//       well_name utf-8[…]
//       well_index          u32
//       raw_distance        f64
//       weighted_distance   f64
//
// All multi-byte fields little-endian — matches the rest of the
// engram binaries for consistency.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'engram_brain.dart' show EngramWellMatch;
import 'engram_hunk_encoder.dart' show HunkKVector;
import 'storage_paths.dart';

const _kEfixMagic = [0x45, 0x46, 0x49, 0x58]; // "EFIX"
const int _kEfixVersion = 1;

/// One cached entry keyed by absolute file path plus mtime + size for
/// staleness detection. Acts like a tiny content-addressable memo —
/// if the file hasn't changed since we encoded it, the K-vector is
/// still correct and we skip re-encoding.
class EngramFileIndexCacheEntry {
  EngramFileIndexCacheEntry({
    required this.mtimeMs,
    required this.size,
    required this.kVector,
  });

  /// File mtime (millis since epoch) at the time we cached the K-vector.
  /// Used as the primary staleness signal — cheap to read via `stat`.
  final int mtimeMs;

  /// File size in bytes at cache time. Doubles with [mtimeMs] to catch
  /// filesystems with low-resolution mtimes (HFS+, some network FS)
  /// where a small change leaves mtime unchanged.
  final int size;

  /// The encoded K-vector + nearest-well data.
  final HunkKVector kVector;
}

/// Read-through cache with a lazy load + dirty-write pattern. Built to
/// be cheap to *check*, expensive only on cold-load.
class EngramFileIndexCache {
  EngramFileIndexCache._(this._entries);

  /// Path → cached entry. Lookup is O(1) on the hot gate path, where
  /// we ask "is this file's (mtime, size) still valid?" for every
  /// node-path in the engine.
  final Map<String, EngramFileIndexCacheEntry> _entries;

  int get size => _entries.length;

  EngramFileIndexCacheEntry? get(String absPath) => _entries[absPath];

  /// Empty cache — used when the on-disk file is missing or fails to
  /// parse. Callers treat this the same as "everything must be encoded"
  /// and write a fresh cache after building.
  factory EngramFileIndexCache.empty() =>
      EngramFileIndexCache._(<String, EngramFileIndexCacheEntry>{});

  /// Derive the cache file location for a given repo. We hash the repo
  /// path into a short hex key so cache files are stable across runs
  /// and safe as filenames (no slashes, no drive letters, no spaces).
  static Future<File> fileFor(String repoPath) async {
    final dir = await StoragePaths.gdpuDataDir();
    final cacheDir = Directory(p.join(dir.path, 'engram_cache'));
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    final key = _hashRepoPath(repoPath);
    return File(p.join(cacheDir.path, '$key.efix'));
  }

  /// Load the cache for [repoPath]. Returns an empty cache if the file
  /// doesn't exist, has the wrong magic, wrong version, or a pairs
  /// mismatch with the current brain (the most recent engram model).
  static Future<EngramFileIndexCache> load({
    required String repoPath,
    required int expectedPairs,
  }) async {
    final file = await fileFor(repoPath);
    if (!file.existsSync()) return EngramFileIndexCache.empty();
    try {
      final bytes = file.readAsBytesSync();
      return _parse(bytes, expectedPairs);
    } catch (_) {
      // Corrupted cache — start clean rather than crashing.
      return EngramFileIndexCache.empty();
    }
  }

  /// Write [entries] to the cache file for [repoPath]. Writes to
  /// `<cache>.tmp` first and renames on success so a crashing write
  /// never corrupts a prior good cache.
  static Future<void> save({
    required String repoPath,
    required int pairs,
    required Map<String, EngramFileIndexCacheEntry> entries,
  }) async {
    final file = await fileFor(repoPath);
    final bytes = _encode(pairs, entries);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes);
    // Atomic replace. Windows rename fails if target exists; delete first.
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }


  static EngramFileIndexCache _parse(Uint8List bytes, int expectedPairs) {
    if (bytes.length < 16) return EngramFileIndexCache.empty();
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _kEfixMagic[i]) return EngramFileIndexCache.empty();
    }
    final bd = ByteData.sublistView(bytes);
    var off = 4;
    final version = bd.getUint32(off, Endian.little); off += 4;
    if (version != _kEfixVersion) return EngramFileIndexCache.empty();
    final pairs = bd.getUint32(off, Endian.little); off += 4;
    if (pairs != expectedPairs) {
      // A different brain was trained (wrong pairs count). Discard.
      return EngramFileIndexCache.empty();
    }
    final nEntries = bd.getUint32(off, Endian.little); off += 4;

    final entries = <String, EngramFileIndexCacheEntry>{};
    for (var i = 0; i < nEntries; i++) {
      if (off + 2 > bytes.length) break;
      final pathLen = bd.getUint16(off, Endian.little); off += 2;
      if (off + pathLen > bytes.length) break;
      final path = utf8.decode(bytes.sublist(off, off + pathLen));
      off += pathLen;
      final mtimeMs = bd.getInt64(off, Endian.little); off += 8;
      final size = bd.getUint64(off, Endian.little); off += 8;
      final vocabHits = bd.getUint32(off, Endian.little); off += 4;
      final meanRms = bd.getFloat64(off, Endian.little); off += 8;

      final kRe = Float64List(pairs);
      final kIm = Float64List(pairs);
      for (var j = 0; j < pairs; j++) {
        kRe[j] = bd.getFloat64(off, Endian.little);
        off += 8;
      }
      for (var j = 0; j < pairs; j++) {
        kIm[j] = bd.getFloat64(off, Endian.little);
        off += 8;
      }

      final hasWell = bytes[off]; off += 1;
      EngramWellMatch? well;
      if (hasWell == 1) {
        final wlen = bd.getUint16(off, Endian.little); off += 2;
        final wname = utf8.decode(bytes.sublist(off, off + wlen));
        off += wlen;
        final wIdx = bd.getUint32(off, Endian.little); off += 4;
        final rawD = bd.getFloat64(off, Endian.little); off += 8;
        final wgtD = bd.getFloat64(off, Endian.little); off += 8;
        well = EngramWellMatch(
          name: wname,
          index: wIdx,
          rawDistance: rawD,
          weightedDistance: wgtD,
        );
      }

      entries[path] = EngramFileIndexCacheEntry(
        mtimeMs: mtimeMs,
        size: size,
        kVector: HunkKVector(
          kRe: kRe,
          kIm: kIm,
          meanRms: meanRms,
          vocabHits: vocabHits,
          well: well,
        ),
      );
    }
    return EngramFileIndexCache._(entries);
  }


  static Uint8List _encode(
    int pairs,
    Map<String, EngramFileIndexCacheEntry> entries,
  ) {
    final buf = BytesBuilder();
    buf.add(_kEfixMagic);
    final hdr = ByteData(12);
    hdr.setUint32(0, _kEfixVersion, Endian.little);
    hdr.setUint32(4, pairs, Endian.little);
    hdr.setUint32(8, entries.length, Endian.little);
    buf.add(hdr.buffer.asUint8List());

    for (final e in entries.entries) {
      final pathBytes = utf8.encode(e.key);
      final entry = e.value;
      final kv = entry.kVector;
      if (kv.kRe.length != pairs || kv.kIm.length != pairs) continue;

      final hdr2 = ByteData(2);
      hdr2.setUint16(0, pathBytes.length, Endian.little);
      buf.add(hdr2.buffer.asUint8List());
      buf.add(pathBytes);

      final meta = ByteData(8 + 8 + 4 + 8);
      meta.setInt64(0, entry.mtimeMs, Endian.little);
      meta.setUint64(8, entry.size, Endian.little);
      meta.setUint32(16, kv.vocabHits, Endian.little);
      meta.setFloat64(20, kv.meanRms, Endian.little);
      buf.add(meta.buffer.asUint8List());

      // K-vectors as two contiguous f64 blocks; the buffer-builder
      // concatenates typed views without intermediate allocations.
      buf.add(kv.kRe.buffer.asUint8List(
          kv.kRe.offsetInBytes, kv.kRe.lengthInBytes));
      buf.add(kv.kIm.buffer.asUint8List(
          kv.kIm.offsetInBytes, kv.kIm.lengthInBytes));

      final well = kv.well;
      if (well == null) {
        buf.addByte(0);
      } else {
        buf.addByte(1);
        final wname = utf8.encode(well.name);
        final wh = ByteData(2);
        wh.setUint16(0, wname.length, Endian.little);
        buf.add(wh.buffer.asUint8List());
        buf.add(wname);
        final wm = ByteData(4 + 8 + 8);
        wm.setUint32(0, well.index, Endian.little);
        wm.setFloat64(4, well.rawDistance, Endian.little);
        wm.setFloat64(12, well.weightedDistance, Endian.little);
        buf.add(wm.buffer.asUint8List());
      }
    }
    return buf.toBytes();
  }

  /// FNV-1a 64-bit over UTF-8 bytes, then render as 16-char hex. Gives
  /// a collision-free filename for the repo path without pulling in a
  /// full crypto dependency. Paths that differ by a single character
  /// land at distinct cache files.
  /// Uses BigInt for the arithmetic: the canonical FNV offset basis
  /// (0xcbf29ce484222325) exceeds int64_max and would be stored as a
  /// negative value in Dart's signed-int64 native representation, making
  /// the mask `& 0xFFFFFFFFFFFFFFFF` a no-op (= `& -1`) and causing
  /// `toRadixString` to emit a leading "-" for some paths.
  static String _hashRepoPath(String repoPath) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final bytes = utf8.encode(repoPath.toLowerCase());
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask  = BigInt.parse('ffffffffffffffff', radix: 16);
    for (final b in bytes) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }
}
