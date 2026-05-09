import 'git.dart';
import 'git_result.dart';
import 'spectral_constants.dart' as sc;

enum ShadowType { revert, reset, abandonedBranch }

class ShadowCommit {
  final String hash;
  final ShadowType type;
  final List<String> files;
  final double confidence;
  final String? subject;
  const ShadowCommit({
    required this.hash,
    required this.type,
    required this.files,
    required this.confidence,
    this.subject,
  });
}

class ShadowHistoryResult {
  final List<ShadowCommit> commits;
  final DateTime discoveredAt;
  final String headHash;
  const ShadowHistoryResult({
    required this.commits,
    required this.discoveredAt,
    required this.headHash,
  });
}

const int _kMaxTotalShadowCommits = 200;
const int _kMaxCommitsPerSource = 50;
const int _kLargeCommitCutoff = 60;

final double _kRevertConfidence = sc.phiDecay1;    // 1/φ ≈ 0.618
final double _kResetConfidence = sc.phiDecay2;     // 1/φ² ≈ 0.382
final double _kAbandonedConfidence = sc.phiDecay3; // 1/φ³ ≈ 0.236

Future<ShadowHistoryResult> discoverShadowHistory(
  String repoPath, {
  int reflogLimit = 500,
}) async {
  final headResult = await runGitProbe(repoPath, ['rev-parse', '--short=7', 'HEAD']);
  final headHash = headResult.exitCode == 0
      ? (headResult.stdout as String).trim()
      : '';

  final commits = <ShadowCommit>[];
  var budget = _kMaxTotalShadowCommits;

  final reverts = await _discoverReverts(repoPath, budget);
  commits.addAll(reverts);
  budget -= reverts.length;

  if (budget > 0) {
    final resets = await _discoverResets(repoPath, budget, reflogLimit);
    commits.addAll(resets);
    budget -= resets.length;
  }

  if (budget > 0) {
    final abandoned = await _discoverAbandonedBranches(repoPath, budget);
    commits.addAll(abandoned);
  }

  return ShadowHistoryResult(
    commits: commits,
    discoveredAt: DateTime.now(),
    headHash: headHash,
  );
}

Future<List<ShadowCommit>> _discoverReverts(
    String repoPath, int budget) async {
  try {
    final result = await runGitProbe(repoPath, [
      'log',
      '--grep=^Revert',
      '-n', '${budget.clamp(0, _kMaxCommitsPerSource)}',
      '--no-merges',
      '--name-only',
      '--format=__SHADOW__%H\x1f%s',
    ]);
    if (result.exitCode != 0) return const [];
    return _parseNameOnlyLog(
      (result.stdout as String),
      ShadowType.revert,
      _kRevertConfidence,
    );
  } catch (_) {
    return const [];
  }
}

Future<List<ShadowCommit>> _discoverResets(
    String repoPath, int budget, int reflogLimit) async {
  try {
    final reflogResult = await listReflog(repoPath, limit: reflogLimit);
    if (!reflogResult.ok || reflogResult.data == null) return const [];

    final resetShas = <String>[];
    for (final entry in reflogResult.data!) {
      if (entry.actionSummary.startsWith('reset: moving to')) {
        resetShas.add(entry.commitHash);
      }
    }
    if (resetShas.isEmpty) return const [];

    final commits = <ShadowCommit>[];
    for (final sha in resetShas) {
      if (commits.length >= budget) break;
      final ahead = await _shadowCommitsFrom(
        repoPath,
        sha,
        ShadowType.reset,
        _kResetConfidence,
        budget - commits.length,
      );
      commits.addAll(ahead);
    }
    return commits;
  } catch (_) {
    return const [];
  }
}

Future<List<ShadowCommit>> _discoverAbandonedBranches(
    String repoPath, int budget) async {
  try {
    final branchResult = await listBranches(repoPath);
    if (!branchResult.ok || branchResult.data == null) return const [];
    final branches = branchResult.data!;

    final currentBranch =
        branches.where((b) => b.current).map((b) => b.name).firstOrNull;

    final candidates = <String>[];
    for (final branch in branches) {
      if (branch.current) continue;
      if (branch.name == currentBranch) continue;
      if (branch.gone || branch.upstream == null) {
        candidates.add(branch.name);
      }
    }
    if (candidates.isEmpty) return const [];

    final squashChecked = await detectSquashMergedBranches(
      repoPath, branches,
      baseRef: currentBranch ?? 'HEAD',
    );
    final squashMerged = <String>{};
    for (final b in squashChecked) {
      if (b.squashMerged == true) squashMerged.add(b.name);
    }

    final commits = <ShadowCommit>[];
    for (final branch in candidates) {
      if (commits.length >= budget) break;
      if (squashMerged.contains(branch)) continue;
      final ahead = await _shadowCommitsFrom(
        repoPath,
        branch,
        ShadowType.abandonedBranch,
        _kAbandonedConfidence,
        budget - commits.length,
      );
      commits.addAll(ahead);
    }
    return commits;
  } catch (_) {
    return const [];
  }
}

Future<List<ShadowCommit>> _shadowCommitsFrom(
  String repoPath,
  String ref,
  ShadowType type,
  double confidence,
  int limit,
) async {
  try {
    final result = await runGitProbe(repoPath, [
      'log',
      ref,
      '^HEAD',
      '-n', '${limit.clamp(0, _kMaxCommitsPerSource)}',
      '--no-merges',
      '--name-only',
      '--format=__SHADOW__%H',
    ]);
    if (result.exitCode != 0) return const [];
    return _parseNameOnlyLog(
      (result.stdout as String),
      type,
      confidence,
    );
  } catch (_) {
    return const [];
  }
}

List<ShadowCommit> _parseNameOnlyLog(
    String output, ShadowType type, double confidence) {
  final commits = <ShadowCommit>[];
  String? currentHash;
  String? currentSubject;
  final currentFiles = <String>[];

  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('__SHADOW__')) {
      if (currentHash != null && currentFiles.isNotEmpty) {
        if (currentFiles.length <= _kLargeCommitCutoff) {
          commits.add(ShadowCommit(
            hash: currentHash,
            type: type,
            files: List.unmodifiable(currentFiles),
            confidence: confidence,
            subject: currentSubject,
          ));
        }
      }
      final payload = trimmed.substring('__SHADOW__'.length);
      final sep = payload.indexOf('\x1f');
      if (sep >= 0) {
        currentHash = payload.substring(0, sep);
        currentSubject = payload.substring(sep + 1);
      } else {
        currentHash = payload;
        currentSubject = null;
      }
      currentFiles.clear();
    } else {
      currentFiles.add(trimmed);
    }
  }
  if (currentHash != null &&
      currentFiles.isNotEmpty &&
      currentFiles.length <= _kLargeCommitCutoff) {
    commits.add(ShadowCommit(
      hash: currentHash,
      type: type,
      files: List.unmodifiable(currentFiles),
      confidence: confidence,
      subject: currentSubject,
    ));
  }
  return commits;
}
