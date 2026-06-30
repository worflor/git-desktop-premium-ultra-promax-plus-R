import 'git.dart';
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

const double _kRevertConfidence = sc.phiDecay1;    // 1/φ ≈ 0.618
const double _kResetConfidence = sc.phiDecay2;     // 1/φ² ≈ 0.382
const double _kAbandonedConfidence = sc.phiDecay3; // 1/φ³ ≈ 0.236

Future<ShadowHistoryResult> discoverShadowHistory(
  String repoPath, {
  int reflogLimit = 500,
}) async {
  // The head probe and the three shadow scans are independent git calls —
  // run them concurrently rather than serially threading a shrinking budget.
  // Each scan fetches up to the full budget; the priority order (reverts →
  // resets → abandoned) is preserved by the concat + trim below. In the
  // common case (total shadow commits ≤ budget) this is identical to the
  // serial version. In the saturation edge (reverts+resets+abandoned >
  // budget) the parallel scans each see the full budget instead of a
  // shrinking remainder, so they can surface a few more recent resets /
  // abandoned commits than the serial caps would before the trim — a more
  // complete result, still bounded by budget. The cost is one or two extra
  // git scans whose tail is trimmed when earlier sources already fill it.
  const budget = _kMaxTotalShadowCommits;
  final headFuture =
      runGitProbe(repoPath, ['rev-parse', '--short=7', 'HEAD']);
  final revertsFuture = _discoverReverts(repoPath, budget);
  final resetsFuture = _discoverResets(repoPath, budget, reflogLimit);
  final abandonedFuture = _discoverAbandonedBranches(repoPath, budget);

  final headResult = await headFuture;
  final headHash = headResult.exitCode == 0
      ? (headResult.stdout as String).trim()
      : '';

  final commits = <ShadowCommit>[
    ...await revertsFuture,
    ...await resetsFuture,
    ...await abandonedFuture,
  ];
  final trimmed = commits.length > _kMaxTotalShadowCommits
      ? commits.sublist(0, _kMaxTotalShadowCommits)
      : commits;

  return ShadowHistoryResult(
    commits: trimmed,
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
