// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// repo_blob_walk.dart — one full-repo blob-walk pipeline that multiple
// consumers (GYAT bootstrap, harvestTextFiles) share instead of each
// doing their own ls-files + read + binary-sniff.
//
// All three consumers do identical I/O: `git ls-files` → for each path
// → stat → null-byte probe → UTF-8 decode → consume. The CONSUMER work
// (bigram counting vs identifier parsing vs text harvesting) is what
// differs; the I/O is 1:1 identical. This file is the consolidated I/O
// path. Each consumer adopts it and stops walking the repo independently.
//
// Architecture: one sync per-file read loop ([_readBlobsSync]) consumed
// by every variant. The async / null-delimited / sync entry points differ
// only in how they obtain the path list, then hand it to the same loop.

import 'dart:convert' show LineSplitter, utf8;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'git.dart' show runGit;

/// A single tracked, text-decoded, non-binary blob.
class RepoBlob {
  /// Path relative to repo root, with forward slashes (normalised).
  final String relativePath;

  /// UTF-8 decoded contents.
  final String text;

  /// Raw byte length on disk.
  final int byteSize;

  const RepoBlob({
    required this.relativePath,
    required this.text,
    required this.byteSize,
  });
}

/// Result of a repo blob walk.
class RepoBlobWalkResult {
  /// Surviving blobs (tracked, non-binary, in size band, decoded ok).
  final List<RepoBlob> blobs;

  /// Total `git ls-files` entries seen (pre-filter).
  final int trackedCount;

  /// Number of files filtered by [RepoBlobWalkOptions.fileCap] sampling.
  final int sampledOut;

  /// Skipped because size was 0 or above `maxBytes`.
  final int sizeSkipped;

  /// Skipped because the first prefix contained a null byte.
  final int binarySkipped;

  /// I/O or decode failures (file disappeared, permission error, etc.).
  final int decodeFailed;

  const RepoBlobWalkResult({
    required this.blobs,
    required this.trackedCount,
    required this.sampledOut,
    required this.sizeSkipped,
    required this.binarySkipped,
    required this.decodeFailed,
  });

  static const empty = RepoBlobWalkResult(
    blobs: [],
    trackedCount: 0,
    sampledOut: 0,
    sizeSkipped: 0,
    binarySkipped: 0,
    decodeFailed: 0,
  );
}

/// Tunables for the walk. Defaults are reasonable for an interactive
/// open-source codebase; consumers with tighter or looser requirements
/// override individually.
class RepoBlobWalkOptions {
  /// Maximum number of blobs to scan. When the repo has more tracked
  /// files than this, a uniform stride is taken (every Nth file in
  /// `ls-files` order) so the sample reflects the whole repo, not just
  /// the alphabetic head. Null = no cap.
  final int? fileCap;

  /// Maximum byte length to read per file. Larger files are skipped —
  /// generated/vendored blobs that would dominate any bigram or
  /// identifier statistic.
  final int maxBytes;

  /// Bytes to read for the binary-detection prefix. Any 0x00 in the
  /// prefix → file is treated as binary and skipped.
  final int binaryProbeBytes;

  /// Skip files smaller than this. Empties and 1-byte files contribute
  /// no useful statistics.
  final int minBytes;

  /// When true, malformed UTF-8 sequences are replaced with the Unicode
  /// replacement character (U+FFFD) instead of causing the file to be
  /// silently dropped. Useful for text-harvest consumers that prefer
  /// "show garbled text and let the downstream relevance filter decide"
  /// over "silently lose the file." GYAT and symbol-frequency consumers
  /// want strict UTF-8 (gibberish pollutes statistics); the text
  /// harvester wants lenient (don't drop a real text file just because
  /// someone pasted a smart-quote in unusual encoding).
  final bool allowMalformedUtf8;

  const RepoBlobWalkOptions({
    this.fileCap,
    this.maxBytes = 256 * 1024,
    this.binaryProbeBytes = 8192,
    this.minBytes = 16,
    this.allowMalformedUtf8 = false,
  });

  static const defaults = RepoBlobWalkOptions();
}

/// Walk `git ls-files`, read every tracked file, filter binaries and
/// out-of-band sizes, decode UTF-8, and return a list of [RepoBlob]s
/// each surviving consumer can process independently.
///
/// Runs the per-file read loop synchronously on the calling isolate.
/// Callers that need the entire walk off the main isolate (including
/// the git probe) should use [walkRepoBlobsSync] inside `Isolate.run`.
Future<RepoBlobWalkResult> walkRepoBlobs(
  String repoPath, {
  RepoBlobWalkOptions options = RepoBlobWalkOptions.defaults,
}) async {
  final lsProbe = await runGit(repoPath, ['ls-files']);
  if (lsProbe.exitCode != 0) return RepoBlobWalkResult.empty;
  final allPaths = LineSplitter.split(lsProbe.stdout.toString())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
  return _readBlobsSync(repoPath, allPaths, options);
}

/// Walk a caller-supplied path list (relative to [repoPath]) through
/// the same read/binary-filter/decode pipeline. Useful for consumers
/// that need a custom path selection — e.g. random sampling vs stride
/// sampling, or filtering to changed files only.
Future<RepoBlobWalkResult> walkRepoBlobsForPaths(
  String repoPath,
  List<String> paths, {
  RepoBlobWalkOptions options = RepoBlobWalkOptions.defaults,
}) async =>
    _readBlobsSync(repoPath, paths, options);

/// Variant that takes `ls-files -z` output and decodes UTF-8 once on the
/// whole list. Preserves the null-delimited semantics: paths with
/// embedded newlines (rare but legal on Unix filesystems) survive.
Future<RepoBlobWalkResult> walkRepoBlobsNullDelimited(
  String repoPath, {
  RepoBlobWalkOptions options = RepoBlobWalkOptions.defaults,
}) async {
  final probe = await runGit(repoPath, const ['ls-files', '-z']);
  if (probe.exitCode != 0) return RepoBlobWalkResult.empty;
  final raw = probe.stdout is List<int>
      ? utf8.decode(probe.stdout as List<int>, allowMalformed: true)
      : probe.stdout.toString();
  final allPaths = raw
      .split('\u0000')
      .where((s) => s.isNotEmpty)
      .toList()
    ..sort();
  return _readBlobsSync(repoPath, allPaths, options);
}

/// Synchronous, isolate-safe variant. Lists files via `Process.runSync`
/// (no diagnostics tap, no dedup cache — both are main-isolate state)
/// and reads/filters every blob inline. Use inside an `Isolate.run`
/// when the caller wants the entire walk + downstream synthesis off
/// the main isolate. Returns [RepoBlobWalkResult.empty] on any git
/// failure.
RepoBlobWalkResult walkRepoBlobsSync(
  String repoPath, {
  RepoBlobWalkOptions options = RepoBlobWalkOptions.defaults,
}) {
  final ls = Process.runSync('git', const ['ls-files'],
      workingDirectory: repoPath);
  if (ls.exitCode != 0) return RepoBlobWalkResult.empty;
  final allPaths = LineSplitter.split(ls.stdout.toString())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
  return _readBlobsSync(repoPath, allPaths, options);
}

/// The one and only per-file read loop. Every entry point above
/// converges here. Sampling, normalization, filtering, decode, and
/// counter accumulation live in one place — change the pipeline here
/// and every variant inherits the change.
RepoBlobWalkResult _readBlobsSync(
  String repoPath,
  List<String> allPaths,
  RepoBlobWalkOptions options,
) {
  if (allPaths.isEmpty) return RepoBlobWalkResult.empty;
  late final List<String> paths;
  var sampledOut = 0;
  final cap = options.fileCap;
  if (cap != null && allPaths.length > cap) {
    final stride = (allPaths.length / cap).ceil();
    paths = [
      for (var i = 0; i < allPaths.length; i += stride) allPaths[i],
    ];
    sampledOut = allPaths.length - paths.length;
  } else {
    paths = allPaths;
  }
  final blobs = <RepoBlob>[];
  var sizeSkipped = 0;
  var binarySkipped = 0;
  var decodeFailed = 0;
  for (final rel in paths) {
    try {
      // Normalize backslashes → forward slashes so every variant emits
      // identical `relativePath` regardless of caller-supplied
      // separators. git output uses forward slashes already; this
      // defends against Windows-path callers and keeps the contract
      // uniform.
      final normalized = rel.replaceAll('\\', '/');
      final file = File(p.join(repoPath, normalized));
      if (!file.existsSync()) {
        decodeFailed++;
        continue;
      }
      final stat = file.statSync();
      if (stat.size < options.minBytes || stat.size > options.maxBytes) {
        sizeSkipped++;
        continue;
      }
      if (_looksBinary(file, stat.size, options.binaryProbeBytes)) {
        binarySkipped++;
        continue;
      }
      final text = options.allowMalformedUtf8
          ? utf8.decode(file.readAsBytesSync(), allowMalformed: true)
          : file.readAsStringSync();
      if (text.length < options.minBytes) {
        sizeSkipped++;
        continue;
      }
      blobs.add(RepoBlob(
        relativePath: normalized,
        text: text,
        byteSize: stat.size,
      ));
    } on FileSystemException {
      decodeFailed++;
    } on FormatException {
      decodeFailed++;
    }
  }
  return RepoBlobWalkResult(
    blobs: blobs,
    trackedCount: allPaths.length,
    sampledOut: sampledOut,
    sizeSkipped: sizeSkipped,
    binarySkipped: binarySkipped,
    decodeFailed: decodeFailed,
  );
}

bool _looksBinary(File file, int size, int probeBytes) {
  final handle = file.openSync();
  try {
    final n = math.min(probeBytes, size);
    final head = handle.readSync(n);
    for (var i = 0; i < head.length; i++) {
      if (head[i] == 0) return true;
    }
    return false;
  } finally {
    handle.closeSync();
  }
}

/// Helper for `harvestTextFiles`-style consumers that need per-line
/// byte offsets. Handles LF, CRLF, and CR-only line endings.
Int32List buildLineOffsets(String text) {
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
  // `n` is the end sentinel, so `lineCount == offsets.length - 1` (see
  // repo_summary/types.dart). When the text ends ON a terminator the loop
  // already pushed `n`, and pushing it again would invent a phantom
  // zero-length final line — inflating every newline-terminated file's line
  // count by one and breaking the strict monotonicity `lineForOffset`'s
  // binary search relies on. An empty text likewise needs `[0]`, not `[0,0]`.
  if (offsets.last != n) offsets.add(n);
  return Int32List.fromList(offsets);
}
