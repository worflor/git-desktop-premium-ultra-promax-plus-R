// text_harvest.dart — walk tracked files, read as UTF-8, skip binaries.
//
// Thin adapter over the shared [walkRepoBlobs] pipeline that backs
// GYAT bootstrap. Sorts by path (deterministic
// ordering) and computes per-file line offsets for offset-keyed text
// queries downstream.
//
// One phase, one job. Binary detection is a null-byte sniff in the
// shared pipeline. There is NO path-based exclusion list — boilerplate,
// generated code, and platform scaffolds are filtered downstream by the
// relevance scalar.

import '../repo_blob_walk.dart';
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

const _kHarvestOptions = RepoBlobWalkOptions(
  binaryProbeBytes: _kBinarySniffBytes,
  // Match the previous behavior: no per-file size cap. The downstream
  // relevance scalar handles oversized files; the harvester just walks.
  maxBytes: 1 << 30,
  minBytes: 1,
  // Preserve the prior `utf8.decode(bytes, allowMalformed: true)`
  // semantic: files with stray malformed UTF-8 sequences are kept
  // with replacement chars, not silently dropped. The downstream
  // relevance scalar filters genuine garbage; the harvester just
  // surfaces text faithfully.
  allowMalformedUtf8: true,
);

/// Walk every tracked file in [repoRoot], read text, skip binaries.
/// Returns a [HarvestResult] sorted by path for deterministic ordering.
/// Uses the null-delimited `ls-files -z` enumeration so paths with
/// embedded newlines (rare but legal on Unix filesystems) survive.
Future<HarvestResult> harvestTextFiles(String repoRoot) async {
  final walk = await walkRepoBlobsNullDelimited(repoRoot,
      options: _kHarvestOptions);
  final files = <HarvestedFile>[
    for (final blob in walk.blobs)
      HarvestedFile(
        path: blob.relativePath,
        text: blob.text,
        lineOffsets: buildLineOffsets(blob.text),
      ),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return HarvestResult(
    files: files,
    trackedCount: walk.trackedCount,
    binarySkipped: walk.binarySkipped,
    decodeFailed: walk.decodeFailed,
  );
}
