// ═════════════════════════════════════════════════════════════════════════
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
// ═════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:math' as math;

import 'file_coupling.dart';
import 'git_result.dart';
import 'logos_git.dart';

/// Window of history, in commits, used to build F0 + volatility stats.
/// Same order of magnitude as the coupling matrix's `commitLimit` so
/// all three signals reflect the same time slice.
const int _statsCommitWindow = 1000;

/// Gather the four Phase-1 statistics the engine needs from the repo.
///
/// Reuses the existing [computeFileCoupling] path so we only walk the
/// commit log twice in total — once here (for F0 + V), once there (for
/// CC). Pass [coupling] in when a cached matrix is already on hand to
/// skip the second git-log invocation.
Future<GitResult<LogosGitStats>> collectLogosGitStats(
  String repoPath, {
  FileCouplingMatrix? coupling,
  int commitWindow = _statsCommitWindow,
}) async {
  // Walk `git log --numstat` once. Each commit gives us a list of
  // (file, additions, deletions); we derive both touches (F0) and
  // per-file EWMA volatility (V).
  //
  // --no-merges: merges dominate the pair counts spuriously.
  // --numstat:   per-file +/- counts; binaries show "-\t-" (handled).
  // --format=%H: commit-hash delimiters, easy to split on.
  final log = await Process.run(
    'git',
    [
      'log',
      '-n',
      '$commitWindow',
      '--no-merges',
      '--numstat',
      '--format=%H',
    ],
    workingDirectory: repoPath,
    runInShell: false,
  );
  if (log.exitCode != 0) {
    return GitResult.err('git log failed: ${log.stderr.toString().trim()}');
  }

  final touches = <String, int>{};
  final volatility = <String, double>{};
  var totalCommits = 0;

  // EWMA half-life: 90 commits. λ = 1 - 2^(-1/90) ≈ 0.00767.
  // Recent commits outweigh old ones in the V-axis signal.
  const halfLife = 90.0;
  final lambda = 1.0 - math.pow(0.5, 1.0 / halfLife).toDouble();

  final lines = log.stdout.toString().split('\n');
  final blocks = _splitCommitBlocks(lines);

  // Process oldest → newest so the EWMA's "most recent" commits carry
  // the most weight. Git log emits newest-first, so reverse.
  for (var i = blocks.length - 1; i >= 0; i--) {
    final b = blocks[i];
    if (b.numstatLines.isEmpty) continue;
    totalCommits++;
    for (final stat in b.numstatLines) {
      final parts = stat.split('\t');
      if (parts.length < 3) continue;
      final added = int.tryParse(parts[0]);
      final deleted = int.tryParse(parts[1]);
      final path = parts[2];
      if (path.isEmpty) continue;
      // Binary files ("-\t-\tpath") still count as a touch but can't
      // contribute a churn number.
      touches[path] = (touches[path] ?? 0) + 1;
      if (added == null || deleted == null) continue;
      final churn = (added + deleted).toDouble();
      final prev = volatility[path] ?? 0.0;
      volatility[path] = (1 - lambda) * prev + lambda * churn;
    }
  }

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

  // Resolve the coupling matrix. Use caller's cache when provided.
  FileCouplingMatrix cc;
  if (coupling != null) {
    cc = coupling;
  } else {
    final ccResult = await computeFileCoupling(
      repoPath,
      commitLimit: commitWindow,
    );
    if (!ccResult.ok || ccResult.data == null) {
      return GitResult.err(
        ccResult.error ?? 'file coupling computation failed',
      );
    }
    cc = ccResult.data!;
  }

  return GitResult.ok(LogosGitStats(
    touches: touches,
    totalCommits: totalCommits,
    volatility: volatility,
    volMean: volMean,
    volStddev: volStddev,
    coupling: cc,
  ));
}

// ─── parse ───────────────────────────────────────────────────────────────

class _CommitBlock {
  final String hash;
  final List<String> numstatLines;
  const _CommitBlock(this.hash, this.numstatLines);
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
  var current = <String>[];
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    if (_isCommitHash(line)) {
      if (currentHash != null) {
        blocks.add(_CommitBlock(currentHash, current));
      }
      currentHash = line;
      current = <String>[];
    } else {
      current.add(line);
    }
  }
  if (currentHash != null) {
    blocks.add(_CommitBlock(currentHash, current));
  }
  return blocks;
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
