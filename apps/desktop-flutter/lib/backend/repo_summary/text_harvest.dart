// text_harvest.dart — walk tracked files, read as UTF-8, skip binaries.
//
// One phase, one job. Binary detection is a null-byte sniff over the
// first prefix of the file. There is NO path-based exclusion list —
// boilerplate, generated code, and platform scaffolds are filtered
// downstream by the relevance scalar, which reads the engine's
// ritualness signal (commits with no semantic content) and temporal
// mass (recent, meaningful touches). Files that don't belong fall out
// of the active set silently; nothing here decides for them.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../git.dart';
import 'types.dart';

/// Result of a harvest pass.
class HarvestResult {
  const HarvestResult({
    required this.files,
    required this.trackedCount,
    required this.binarySkipped,
    required this.decodeFailed,
  });

  /// Text files, sorted by path.
  final List<HarvestedFile> files;

  /// Total `git ls-files` entries seen (includes skipped files).
  final int trackedCount;

  /// Number of files skipped because the first prefix contained a null
  /// byte.
  final int binarySkipped;

  /// Number of files where UTF-8 decode failed or the file disappeared
  /// between `ls-files` and read.
  final int decodeFailed;
}

/// Byte prefix size used for binary detection. Sized to match the
/// smallest alignment unit most binary formats have in their header
/// (4 KiB = one memory page); binaries with a text-like first 4 KiB
/// are rare enough to not justify a larger sniff window.
const int _kBinarySniffBytes = 4096;

/// Walk every tracked file in [repoRoot], read text, skip binaries.
/// Returns a [HarvestResult] sorted by path for deterministic ordering.
Future<HarvestResult> harvestTextFiles(String repoRoot) async {
  final probe = await runGitProbe(repoRoot, const ['ls-files', '-z']);
  if (probe.exitCode != 0) {
    return const HarvestResult(
      files: [], trackedCount: 0, binarySkipped: 0, decodeFailed: 0,
    );
  }
  final raw = probe.stdout is List<int>
      ? utf8.decode(probe.stdout as List<int>, allowMalformed: true)
      : probe.stdout.toString();
  final paths = raw
      .split('\u0000')
      .where((s) => s.isNotEmpty)
      .map((s) => s.replaceAll('\\', '/'))
      .toList()
    ..sort();

  final files = <HarvestedFile>[];
  var binarySkipped = 0;
  var decodeFailed = 0;

  for (final rel in paths) {
    final absolute = p.join(repoRoot, rel);
    try {
      final file = File(absolute);
      if (!await file.exists()) {
        decodeFailed++;
        continue;
      }
      final bytes = await file.readAsBytes();
      if (_looksBinary(bytes)) {
        binarySkipped++;
        continue;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final offsets = _buildLineOffsets(text);
      files.add(HarvestedFile(
        path: rel, text: text, lineOffsets: offsets,
      ));
    } on FileSystemException {
      decodeFailed++;
    } on FormatException {
      decodeFailed++;
    }
  }

  return HarvestResult(
    files: files,
    trackedCount: paths.length,
    binarySkipped: binarySkipped,
    decodeFailed: decodeFailed,
  );
}

/// Null-byte sniff on the first prefix bytes. Any 0x00 byte → binary.
bool _looksBinary(Uint8List bytes) {
  final n = bytes.length < _kBinarySniffBytes ? bytes.length : _kBinarySniffBytes;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// Byte-offset of each line's start + a trailing entry equal to
/// `text.length`. Handles LF, CRLF, and CR-only line endings.
Int32List _buildLineOffsets(String text) {
  final offsets = <int>[0];
  final n = text.length;
  for (var i = 0; i < n; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x0A /* \n */) {
      offsets.add(i + 1);
    } else if (c == 0x0D /* \r */) {
      if (i + 1 < n && text.codeUnitAt(i + 1) == 0x0A) {
        i++;
      }
      offsets.add(i + 1);
    }
  }
  offsets.add(n);
  return Int32List.fromList(offsets);
}
