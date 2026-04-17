// logos_git_stats.dart — repo telemetry harvester for LogosGit
//
// Pulls the four Phase-1 statistics the engine needs (touches, total
// commits, volatility, file-coupling matrix) out of the repo using the
// cheapest git probes that produce them. Everything else in the engine
// is pure math — this file is the one "git boundary" layer.
//
// Kept separate from the engine so (a) the engine can be unit-tested
// with synthesised stats, and (b) a future sidecar / WASM port can
// replace this file without touching the numerics.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'file_coupling.dart';
import 'git_result.dart';
import 'logos_git.dart';
import 'logos_git_integrity.dart';

/// Window of history, in commits, used to build F0 + volatility stats.
/// Same order of magnitude as the coupling matrix's `commitLimit` so
/// all three signals reflect the same time slice.
const int _statsCommitWindow = 1000;
const String _commitMetaSep = '\u001f';

/// Gather the four Phase-1 statistics the engine needs from the repo.
/// We walk the commit log via two independent `git log` invocations —
/// one with `--numstat` (drives F0 + V), one with `--name-only` (drives
/// CC via [computeFileCoupling]). They are kicked off **concurrently**
/// via `Future.wait` so the wall-clock cost is one walk, not two.
/// Both share the OS page cache for the repo's pack files, so the
/// second process is materially faster than running serially. Pass
/// [coupling] in when a cached matrix is already on hand to skip the
/// CC walk entirely.
Future<GitResult<LogosGitStats>> collectLogosGitStats(
  String repoPath, {
  FileCouplingMatrix? coupling,
  int commitWindow = _statsCommitWindow,
}) async {
  // --no-merges: merges dominate the pair counts spuriously.
  // --numstat:   per-file +/- counts; binaries show "-\t-" (handled).
  // --format=%H: commit-hash delimiters, easy to split on.
  final logFuture = Process.run(
    'git',
    [
      'log',
      '-n',
      '$commitWindow',
      '--no-merges',
      '--numstat',
      '--format=%H%x1f%an%x1f%s',
    ],
    workingDirectory: repoPath,
    runInShell: false,
  );
  // Coupling walk runs in parallel with the numstat walk above. Both
  // git processes share the pack-file cache; the second one is fast.
  final couplingFuture = coupling != null
      ? Future.value(_CouplingResult.ok(coupling))
      : computeFileCoupling(repoPath, commitLimit: commitWindow)
          .then((r) => r.ok && r.data != null
              ? _CouplingResult.ok(r.data!)
              : _CouplingResult.err(
                  r.error ?? 'file coupling computation failed'));

  final results = await Future.wait([logFuture, couplingFuture]);
  final log = results[0] as ProcessResult;
  final ccResult = results[1] as _CouplingResult;
  if (log.exitCode != 0) {
    return GitResult.err('git log failed: ${log.stderr.toString().trim()}');
  }
  if (ccResult.error != null) {
    return GitResult.err(ccResult.error!);
  }
  final cc = ccResult.matrix!;

  final rawTouches = <String, int>{};
  final touchMass = <String, double>{};
  final volatility = <String, double>{};
  // Per-file commit-index series — for each file, the list of commit
  // indices (oldest=0 .. newest=totalCommits-1) where the file
  // appeared. Drives [LogosGit]'s per-file curved AR(2) metric.
  final perFileCommitIndices = <String, List<int>>{};
  final perFileCommitClock = <String, List<double>>{};
  final ritualMassByPath = <String, double>{};
  final hyperedgesByPath = <String, List<LogosCommitHyperedge>>{};
  var totalCommits = 0;
  var semanticCommitMass = 0.0;

  // EWMA half-life: 90 commits. λ = 1 - 2^(-1/90) ≈ 0.00767.
  // Recent commits outweigh old ones in the V-axis signal.
  const halfLife = 90.0;
  final lambda = 1.0 - math.pow(0.5, 1.0 / halfLife).toDouble();

  final lines = log.stdout.toString().split('\n');
  final blocks = _splitCommitBlocks(lines);

  // Process oldest → newest so the EWMA's "most recent" commits carry
  // the most weight. Git log emits newest-first, so reverse. We track
  // a monotonic `commitIndex` (incremented per non-empty block) so
  // each file's commit-index series stays in oldest→newest order
  // ready for AR(2) gap-fitting downstream.
  var commitIndex = 0;
  var semanticClock = 0.0;
  for (var i = blocks.length - 1; i >= 0; i--) {
    final b = blocks[i];
    if (b.numstatLines.isEmpty) continue;
    totalCommits++;
    final paths = <String>{};
    for (final stat in b.numstatLines) {
      final parts = stat.split('\t');
      if (parts.length < 3) continue;
      final path = parts[2];
      if (path.isNotEmpty) paths.add(path);
    }
    final meaningfulness = inferCommitMeaningfulness(
      author: b.author,
      subject: b.subject,
      paths: paths,
    );
    final step = meaningfulness.weight.clamp(0.0, 1.0);
    if (step > 0 && paths.length >= 3 && paths.length <= 8) {
      final ordered = paths.toList()..sort();
      final edge = LogosCommitHyperedge(
        paths: ordered,
        weight: step,
        summary: b.subject.isEmpty ? null : b.subject,
      );
      for (final path in ordered) {
        (hyperedgesByPath[path] ??= <LogosCommitHyperedge>[]).add(edge);
      }
    }
    semanticClock += step;
    semanticCommitMass += step;
    for (final stat in b.numstatLines) {
      final parts = stat.split('\t');
      if (parts.length < 3) continue;
      final added = int.tryParse(parts[0]);
      final deleted = int.tryParse(parts[1]);
      final path = parts[2];
      if (path.isEmpty) continue;
      // Binary files ("-\t-\tpath") still count as a touch but can't
      // contribute a churn number.
      rawTouches[path] = (rawTouches[path] ?? 0) + 1;
      touchMass[path] = (touchMass[path] ?? 0.0) + step;
      ritualMassByPath[path] = (ritualMassByPath[path] ?? 0.0) + (1.0 - step);
      (perFileCommitIndices[path] ??= <int>[]).add(commitIndex);
      if (step > 0) {
        (perFileCommitClock[path] ??= <double>[]).add(semanticClock);
      }
      if (step <= 0 || added == null || deleted == null) continue;
      final churn = (added + deleted).toDouble() * step;
      final prev = volatility[path] ?? 0.0;
      volatility[path] = (1 - lambda) * prev + lambda * churn;
    }
    commitIndex++;
  }

  final integrityProfile = buildLogosIntegrityProfile(
    rawTouches: rawTouches,
    semanticTouchMass: touchMass,
    ritualMassByPath: ritualMassByPath,
  );

  // Mean + stddev of volatility for the V-axis z-score.
  var volMean = 0.0;
  if (volatility.isNotEmpty) {
    var sum = 0.0;
    for (final v in volatility.values) {
      sum += v;
    }
    volMean = sum / volatility.length;
  }
  var volStddev = 0.0;
  if (volatility.length > 1) {
    var ss = 0.0;
    for (final v in volatility.values) {
      final d = v - volMean;
      ss += d * d;
    }
    volStddev = math.sqrt(ss / (volatility.length - 1));
  }

  // Compact the per-file commit-index lists into Int32List once the
  // shape is final — boxed `List<int>` averages 16+ bytes per element
  // on the Dart VM heap; Int32List is exactly 4. On a 10k-file × ~10-
  // touches-each repo this drops several MB of retained memory off
  // every cached engine, with zero API change (Int32List IS a
  // `List<int>`). The growable-then-typed pattern is the standard
  // build-time → query-time compaction step.
  final compactedIndices = <String, List<int>>{};
  perFileCommitIndices.forEach((path, growable) {
    compactedIndices[path] = Int32List.fromList(growable);
  });
  final compactedClock = <String, List<double>>{};
  perFileCommitClock.forEach((path, growable) {
    compactedClock[path] = Float64List.fromList(growable);
  });
  final semanticTouches = <String, int>{
    for (final entry in touchMass.entries)
      if (entry.value > 0) entry.key: math.max(1, entry.value.round()),
  };
  final semanticTotalCommits =
      semanticCommitMass > 0 ? math.max(1, semanticCommitMass.round()) : 0;
  final compactedHyperedges = <String, List<LogosCommitHyperedge>>{};
  hyperedgesByPath.forEach((path, edges) {
    edges.sort((a, b) => b.weight.compareTo(a.weight));
    compactedHyperedges[path] =
        edges.length > 24 ? edges.sublist(0, 24) : List<LogosCommitHyperedge>.from(edges);
  });

  return GitResult.ok(LogosGitStats(
    touches: semanticTouches,
    totalCommits: semanticTotalCommits,
    rawTouches: rawTouches,
    rawTotalCommits: totalCommits,
    touchMass: touchMass,
    semanticCommitMass: semanticCommitMass,
    volatility: volatility,
    volMean: volMean,
    volStddev: volStddev,
    coupling: cc,
    perFileCommitIndices: compactedIndices,
    perFileCommitClock: compactedClock,
    ritualnessByPath: integrityProfile.ritualnessByPath,
    integrityByPath: integrityProfile.integrityByPath,
    integrityReasonsByPath: integrityProfile.reasonsByPath,
    hyperedgesByPath: compactedHyperedges,
  ));
}

/// Tagged-union surrogate for the parallel coupling-walk branch — lets
/// `Future.wait` carry either the matrix or the failure reason without
/// throwing across the Future boundary.
class _CouplingResult {
  final FileCouplingMatrix? matrix;
  final String? error;
  const _CouplingResult.ok(this.matrix) : error = null;
  const _CouplingResult.err(this.error) : matrix = null;
}


class _CommitBlock {
  final String hash;
  final String author;
  final String subject;
  final List<String> numstatLines;
  const _CommitBlock(this.hash, this.author, this.subject, this.numstatLines);
}

List<_CommitBlock> _splitCommitBlocks(List<String> lines) {
  // `git log --format=%H --numstat` emits commit blocks separated by a
  // blank line:
  //   <hash>
  //   <blank>
  //   <added>\t<deleted>\t<path>
  //   ...
  //   <blank>
  //   <hash>
  //   ...
  final blocks = <_CommitBlock>[];
  String? currentHash;
  String currentAuthor = '';
  String currentSubject = '';
  var current = <String>[];
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    final header = _parseCommitHeader(line);
    if (header != null) {
      if (currentHash != null) {
        blocks.add(_CommitBlock(currentHash, currentAuthor, currentSubject, current));
      }
      currentHash = header.hash;
      currentAuthor = header.author;
      currentSubject = header.subject;
      current = <String>[];
    } else {
      current.add(line);
    }
  }
  if (currentHash != null) {
    blocks.add(_CommitBlock(currentHash, currentAuthor, currentSubject, current));
  }
  return blocks;
}

_CommitHeader? _parseCommitHeader(String line) {
  final parts = line.split(_commitMetaSep);
  if (parts.length < 3 || !_isCommitHash(parts[0])) return null;
  return _CommitHeader(
    parts[0],
    parts[1].trim(),
    parts.sublist(2).join(_commitMetaSep).trim(),
  );
}

class _CommitHeader {
  final String hash;
  final String author;
  final String subject;
  const _CommitHeader(this.hash, this.author, this.subject);
}

bool _isCommitHash(String s) {
  if (s.length != 40 && s.length != 64) return false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final isHex = (c >= 0x30 && c <= 0x39) ||
        (c >= 0x61 && c <= 0x66) ||
        (c >= 0x41 && c <= 0x46);
    if (!isHex) return false;
  }
  return true;
}
