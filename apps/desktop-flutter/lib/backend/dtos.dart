class RepositoryStatusFile {
  final String path;
  final String staged;
  final String unstaged;
  const RepositoryStatusFile(
      {required this.path, required this.staged, required this.unstaged});
  factory RepositoryStatusFile.fromJson(Map<String, dynamic> j) =>
      RepositoryStatusFile(
          path: j['path']?.toString() ?? '',
          staged: j['staged']?.toString() ?? '',
          unstaged: j['unstaged']?.toString() ?? '');

  String get stagedCode => canonicalGitStatusCode(staged, stagedSlot: true);
  String get unstagedCode =>
      canonicalGitStatusCode(unstaged, stagedSlot: false);

  bool get hasStagedChange => stagedCode.isNotEmpty;
  bool get hasUnstagedChange => unstagedCode.isNotEmpty;
  bool get hasAnyChange => hasStagedChange || hasUnstagedChange;
  bool get isUntracked =>
      gitStatusCodeIsUntracked(staged) || gitStatusCodeIsUntracked(unstaged);
  bool get isConflicted => stagedCode == 'U' || unstagedCode == 'U';
  bool get isStagedAddition => stagedCode == 'A';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepositoryStatusFile &&
          other.path == path &&
          other.staged == staged &&
          other.unstaged == unstaged;

  @override
  int get hashCode => Object.hash(path, staged, unstaged);
}

String canonicalGitStatusCode(
  String raw, {
  required bool stagedSlot,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == '.') {
    return '';
  }

  final lower = trimmed.toLowerCase();
  switch (lower) {
    case 'clean':
      return '';
    case '?':
    case 'untracked':
    case 'unknown':
      return stagedSlot ? '' : '?';
    case 'm':
    case 'modified':
      return 'M';
    case 'a':
    case 'added':
      return 'A';
    case 'd':
    case 'deleted':
      return 'D';
    case 'r':
    case 'renamed':
      return 'R';
    case 'c':
    case 'copied':
      return 'C';
    case 'u':
    case 'unmerged':
    case 'conflict':
    case 'conflicted':
      return 'U';
    case 't':
    case 'typechange':
    case 'type-changed':
    case 'type_changed':
      return 'T';
    default:
      if (lower.startsWith('state-') && lower.length == 7) {
        return lower.substring(6).toUpperCase();
      }
      return trimmed.length == 1 ? trimmed.toUpperCase() : trimmed;
  }
}

bool gitStatusCodeIsUntracked(String raw) {
  final lower = raw.trim().toLowerCase();
  return lower == '?' || lower == 'untracked' || lower == 'unknown';
}

/// Per-file numstat breakdown. Feeds the "by impact" sort with enough
/// granularity to apply UX-aware weighting (binaries get a baseline,
/// deletions carry more weight than additions, etc.).
class FileChangeWeight {
  final int adds;
  final int dels;
  final bool binary;
  const FileChangeWeight({
    required this.adds,
    required this.dels,
    required this.binary,
  });

  static const empty = FileChangeWeight(adds: 0, dels: 0, binary: false);
}

class RepositoryStatus {
  final String branch;
  final String? upstream;
  final int ahead;
  final int behind;
  final List<RepositoryStatusFile> files;
  /// True when HEAD points at an actual commit. False on a fresh repo
  /// before the first commit (`git status` reports `branch.oid (initial)`)
  /// — gating affordances like "Amend last commit" on this flag avoids
  /// surfacing menu items that can only ever return errors.
  final bool hasHeadCommit;
  const RepositoryStatus(
      {required this.branch,
      this.upstream,
      required this.ahead,
      required this.behind,
      required this.files,
      this.hasHeadCommit = true});
  factory RepositoryStatus.fromJson(Map<String, dynamic> j) => RepositoryStatus(
        branch: j['branch'] ?? '',
        upstream: j['upstream'],
        ahead: j['ahead'] ?? 0,
        behind: j['behind'] ?? 0,
        files: (j['files'] as List? ?? [])
            .map((f) => RepositoryStatusFile.fromJson(f))
            .toList(),
        // Default true when the field is absent so older serialised
        // statuses don't suddenly hide affordances after this rolls in.
        hasHeadCommit: j['hasHeadCommit'] ?? true,
      );

  /// Structural equality. Required so `context.select<RepositoryState,
  /// RepositoryStatus?>` actually narrows rebuilds — every
  /// `refreshStatus` parses fresh JSON and produces a new instance,
  /// and without `==` the consumer rebuild on every tick regardless
  /// of whether anything meaningfully changed.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RepositoryStatus) return false;
    if (other.branch != branch) return false;
    if (other.upstream != upstream) return false;
    if (other.ahead != ahead) return false;
    if (other.behind != behind) return false;
    if (other.hasHeadCommit != hasHeadCommit) return false;
    if (other.files.length != files.length) return false;
    for (var i = 0; i < files.length; i++) {
      if (other.files[i] != files[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        branch,
        upstream,
        ahead,
        behind,
        hasHeadCommit,
        // File-list identity collapsed via `Object.hashAll` so two
        // equally-shaped statuses hash the same without materialising
        // a new list.
        Object.hashAll(files),
      );
}

class CommitHistoryEntry {
  final String commitHash;
  final String shortHash;
  final List<String> parentHashes;
  final List<String> refNames;
  final bool isMerge;
  final String subject;
  final String authorName;
  final String authorEmail;
  final String authoredAt;
  const CommitHistoryEntry({
    required this.commitHash,
    required this.shortHash,
    required this.parentHashes,
    required this.refNames,
    required this.isMerge,
    required this.subject,
    required this.authorName,
    required this.authorEmail,
    required this.authoredAt,
  });
  factory CommitHistoryEntry.fromJson(Map<String, dynamic> j) =>
      CommitHistoryEntry(
        commitHash: j['commit_hash'] ?? j['commitHash'] ?? '',
        shortHash: j['short_hash'] ?? j['shortHash'] ?? '',
        parentHashes:
            List<String>.from(j['parent_hashes'] ?? j['parentHashes'] ?? []),
        refNames: List<String>.from(j['ref_names'] ?? j['refNames'] ?? []),
        isMerge: j['is_merge'] ?? j['isMerge'] ?? false,
        subject: j['subject'] ?? '',
        authorName: j['author_name'] ?? j['authorName'] ?? '',
        authorEmail: j['author_email'] ?? j['authorEmail'] ?? '',
        authoredAt: j['authored_at'] ?? j['authoredAt'] ?? '',
      );
}

class CommitFileStatData {
  final String path;
  final int additions;
  final int deletions;
  final String changeType; // 'M', 'A', 'D', 'R', 'C', 'T', 'U'
  const CommitFileStatData(
      {required this.path,
      required this.additions,
      required this.deletions,
      this.changeType = 'M'});
  factory CommitFileStatData.fromJson(Map<String, dynamic> j) =>
      CommitFileStatData(
          path: j['path'] ?? '',
          additions: j['additions'] ?? 0,
          deletions: j['deletions'] ?? 0,
          changeType: j['changeType'] ?? 'M');
}

class CommitDetailData {
  final String commitHash;
  final String shortHash;
  final String subject;
  final String body;
  final String authorName;
  final String authorEmail;
  final String authoredAt;
  final int filesChanged;
  final int additions;
  final int deletions;
  final List<CommitFileStatData> files;
  const CommitDetailData({
    required this.commitHash,
    required this.shortHash,
    required this.subject,
    required this.body,
    required this.authorName,
    required this.authorEmail,
    required this.authoredAt,
    required this.filesChanged,
    required this.additions,
    required this.deletions,
    required this.files,
  });
  factory CommitDetailData.fromJson(Map<String, dynamic> j) => CommitDetailData(
        commitHash: j['commit_hash'] ?? j['commitHash'] ?? '',
        shortHash: j['short_hash'] ?? j['shortHash'] ?? '',
        subject: j['subject'] ?? '',
        body: j['body'] ?? '',
        authorName: j['author_name'] ?? j['authorName'] ?? '',
        authorEmail: j['author_email'] ?? j['authorEmail'] ?? '',
        authoredAt: j['authored_at'] ?? j['authoredAt'] ?? '',
        filesChanged: j['files_changed'] ?? j['filesChanged'] ?? 0,
        additions: j['additions'] ?? 0,
        deletions: j['deletions'] ?? 0,
        files: (j['files'] as List? ?? [])
            .map((f) => CommitFileStatData.fromJson(f))
            .toList(),
      );
}

class BranchInfo {
  final String name;
  final bool current;
  final String? upstream;
  final int ahead;
  final int behind;

  /// True when the upstream tracking branch was deleted on the remote
  /// — `git for-each-ref` reports `[gone]` in the `upstream:track`
  /// field. This branch was probably the local copy of a now-merged
  /// PR; cleaning it up is generally safe.
  final bool gone;

  /// Last commit timestamp on this branch. Drives "stale" detection
  /// (branches not committed-to in 30+ days) — surfaced as a small
  /// relative-time pill in the UI without filtering anything out.
  /// Null when the format string didn't return a date (very old
  /// branches with weird metadata).
  final DateTime? lastCommitAt;

  /// True when every commit on this branch has a patch-id-equivalent
  /// commit on the comparison base (typically default branch). The
  /// killer signal that `git branch --merged` misses: GitHub/GitLab
  /// squash-merges flatten history so `--merged` reports false even
  /// though the branch's work IS in main. Computed lazily via
  /// `git cherry`. Null when detection hasn't run yet.
  final bool? squashMerged;

  const BranchInfo({
    required this.name,
    required this.current,
    this.upstream,
    required this.ahead,
    required this.behind,
    this.gone = false,
    this.lastCommitAt,
    this.squashMerged,
  });

  factory BranchInfo.fromJson(Map<String, dynamic> j) => BranchInfo(
        name: j['name'] ?? '',
        current: j['current'] ?? false,
        upstream: j['upstream'],
        ahead: j['ahead'] ?? 0,
        behind: j['behind'] ?? 0,
        gone: j['gone'] ?? false,
        lastCommitAt: j['lastCommitAt'] is String
            ? DateTime.tryParse(j['lastCommitAt'] as String)
            : null,
        squashMerged: j['squashMerged'] is bool ? j['squashMerged'] as bool : null,
      );

  BranchInfo copyWith({
    bool? squashMerged,
  }) =>
      BranchInfo(
        name: name,
        current: current,
        upstream: upstream,
        ahead: ahead,
        behind: behind,
        gone: gone,
        lastCommitAt: lastCommitAt,
        squashMerged: squashMerged ?? this.squashMerged,
      );
}

class TagEntryData {
  final String name;
  final String tagType;
  final String? targetHash;
  final String? createdAt;
  final String? creatorName;
  final String? subject;
  const TagEntryData(
      {required this.name,
      required this.tagType,
      this.targetHash,
      this.createdAt,
      this.creatorName,
      this.subject});
  factory TagEntryData.fromJson(Map<String, dynamic> j) => TagEntryData(
        name: j['name'] ?? '',
        tagType: j['tag_type'] ?? j['tagType'] ?? '',
        targetHash: j['target_hash'] ?? j['targetHash'],
        createdAt: j['created_at'] ?? j['createdAt'],
        creatorName: j['creator_name'] ?? j['creatorName'],
        subject: j['subject'],
      );
}

class ReflogEntryData {
  final String commitHash;
  final String shortHash;
  final String refSelector;
  final String actionSummary;
  final String authorName;
  final String authoredAt;
  const ReflogEntryData({
    required this.commitHash,
    required this.shortHash,
    required this.refSelector,
    required this.actionSummary,
    required this.authorName,
    required this.authoredAt,
  });
  factory ReflogEntryData.fromJson(Map<String, dynamic> j) => ReflogEntryData(
        commitHash: j['commit_hash'] ?? j['commitHash'] ?? '',
        shortHash: j['short_hash'] ?? j['shortHash'] ?? '',
        refSelector: j['ref_selector'] ?? j['refSelector'] ?? '',
        actionSummary: j['action_summary'] ?? j['actionSummary'] ?? '',
        authorName: j['author_name'] ?? j['authorName'] ?? '',
        authoredAt: j['authored_at'] ?? j['authoredAt'] ?? '',
      );
}

class BlameLineData {
  final int lineNumber;
  final String commitHash;
  final String shortHash;
  final String authorName;
  final String authoredAt;
  final String lineContent;
  const BlameLineData({
    required this.lineNumber,
    required this.commitHash,
    required this.shortHash,
    required this.authorName,
    required this.authoredAt,
    required this.lineContent,
  });
  factory BlameLineData.fromJson(Map<String, dynamic> j) => BlameLineData(
        lineNumber: j['line_number'] ?? j['lineNumber'] ?? 0,
        commitHash: j['commit_hash'] ?? j['commitHash'] ?? '',
        shortHash: j['short_hash'] ?? j['shortHash'] ?? '',
        authorName: j['author_name'] ?? j['authorName'] ?? '',
        authoredAt: j['authored_at'] ?? j['authoredAt'] ?? '',
        lineContent: j['line_content'] ?? j['lineContent'] ?? '',
      );
}

class CommitSearchResultData {
  final String commitHash;
  final String shortHash;
  final String subject;
  final String authorName;
  final String authoredAt;
  final String? matchContext;
  const CommitSearchResultData({
    required this.commitHash,
    required this.shortHash,
    required this.subject,
    required this.authorName,
    required this.authoredAt,
    this.matchContext,
  });
  factory CommitSearchResultData.fromJson(Map<String, dynamic> j) =>
      CommitSearchResultData(
        commitHash: j['commit_hash'] ?? j['commitHash'] ?? '',
        shortHash: j['short_hash'] ?? j['shortHash'] ?? '',
        subject: j['subject'] ?? '',
        authorName: j['author_name'] ?? j['authorName'] ?? '',
        authoredAt: j['authored_at'] ?? j['authoredAt'] ?? '',
        matchContext: j['match_context'] ?? j['matchContext'],
      );
}

class CommitData {
  final String repositoryPath;
  final String commitHash;
  final String summary;
  const CommitData(
      {required this.repositoryPath,
      required this.commitHash,
      required this.summary});
}

class SyncData {
  final String operation;
  final String remote;
  final String? branch;
  final String output;
  const SyncData(
      {required this.operation,
      required this.remote,
      this.branch,
      required this.output});
  factory SyncData.fromJson(Map<String, dynamic> j) => SyncData(
        operation: j['operation'] ?? '',
        remote: j['remote'] ?? '',
        branch: j['branch'],
        output: j['output'] ?? '',
      );
}

class RepositoryXrayHeaderData {
  final String repoPath;
  final String repoName;
  final String branch;
  final String headCommitHash;
  final String headShortHash;
  final int dirtyFileCount;
  final String computedAt;
  final String fingerprint;

  const RepositoryXrayHeaderData({
    required this.repoPath,
    required this.repoName,
    required this.branch,
    required this.headCommitHash,
    required this.headShortHash,
    required this.dirtyFileCount,
    required this.computedAt,
    required this.fingerprint,
  });
}

class RepositoryXrayEvidenceData {
  final String label;
  final String detail;
  final String kind;
  final String? path;
  final String? commitHash;
  final int? count;

  const RepositoryXrayEvidenceData({
    required this.label,
    required this.detail,
    required this.kind,
    this.path,
    this.commitHash,
    this.count,
  });
}

class RepositoryXrayCardData {
  final String id;
  final String title;
  final String claim;
  final String verdict;
  final String confidence;
  final List<RepositoryXrayEvidenceData> evidence;
  final String? primaryPath;
  final String? primaryCommitHash;

  const RepositoryXrayCardData({
    required this.id,
    required this.title,
    required this.claim,
    required this.verdict,
    required this.confidence,
    required this.evidence,
    this.primaryPath,
    this.primaryCommitHash,
  });
}

class RepositoryXrayHotspotData {
  final String kind;
  final String path;
  final int touchCount;
  final int ownerCount;
  final String lastTouchedAt;
  final String? latestCommitHash;
  final String? latestShortHash;

  /// Keystone score. Ecological sense: a file is "keystone" if a
  /// disproportionately large share of the repo's co-change mass
  /// flows through it, relative to how often it's actually touched.
  /// The bridge-species file — quiet on its own, but losing it
  /// collapses clusters. When a Logos engine is available this is the
  /// spectral centrality `Σⱼ uⱼ[f]²·e^{−t·λⱼ}` divided by log1p(touch)
  /// — an operator-level "how much heat localises here per unit
  /// activity"; otherwise it falls back to Jaccard-pull per touch.
  /// High pull with low touch count means many clusters depend on
  /// this file without the file itself being busy. Null when no
  /// coupling data was available at snapshot time.
  final double? keystoneScore;

  /// True when [keystoneScore] is in the top band of this repo's own
  /// distribution — pre-computed at snapshot time so renderers don't
  /// need to re-bucket. Using a relative percentile keeps the flag
  /// repo-adaptive: a 10-file project and a 10k-file monorepo can
  /// both surface their top keystones without sharing thresholds.
  final bool isKeystone;

  /// Top co-changed files for this hotspot, ranked by coupling
  /// strength. Capped to a small N for prompt-size + render-time.
  /// Drives the Map view's coupling overlay (lines from the selected
  /// tile to its strongest co-changers). When a Logos engine is
  /// available this reads directly from the weighted coupling CSR
  /// graph; otherwise it falls back to per-commit Jaccard. Empty when
  /// the file has no co-change neighbours.
  final List<String> coupledTo;

  /// Currently-alive mass = touchCount × exp(-ageDays / repoHalfLife).
  /// Half-life is the AR(2) metabolism fit when available, else the
  /// median commit age. Drives the Map view's tile sizing so legacy
  /// paths shrink in proportion to how dormant they are. Defaults to
  /// raw touchCount when alive-mass data isn't available.
  final double aliveMass;

  /// Architectural community id assigned by Shi–Malik k-way spectral
  /// clustering on the low-frequency eigenspace of the coupling
  /// graph's normalised Laplacian. Two files with the same label
  /// diffuse onto each other faster than they diffuse onto outsiders —
  /// the math's natural partitioning, independent of the directory
  /// tree. `-1` when no Logos engine / spectral basis was available
  /// (tiny repos, test fixtures).
  final int spectralCommunity;

  const RepositoryXrayHotspotData({
    required this.kind,
    required this.path,
    required this.touchCount,
    required this.ownerCount,
    required this.lastTouchedAt,
    this.latestCommitHash,
    this.latestShortHash,
    this.keystoneScore,
    this.isKeystone = false,
    this.coupledTo = const [],
    this.aliveMass = 0.0,
    this.spectralCommunity = -1,
  });
}

class RepositoryXrayCadenceData {
  final String kind;
  final String label;
  final int count;
  final String detail;

  const RepositoryXrayCadenceData({
    required this.kind,
    required this.label,
    required this.count,
    required this.detail,
  });
}

class RepositoryXrayRefSummaryData {
  final int localBranchCount;
  final int remoteBranchCount;
  final int tagCount;
  final int stashCount;
  final int noteCount;
  final int worktreeCount;
  final int mergeCommitCount;
  final int renameCommitCount;
  final List<String> hiddenNamespaces;

  const RepositoryXrayRefSummaryData({
    required this.localBranchCount,
    required this.remoteBranchCount,
    required this.tagCount,
    required this.stashCount,
    required this.noteCount,
    required this.worktreeCount,
    required this.mergeCommitCount,
    required this.renameCommitCount,
    required this.hiddenNamespaces,
  });
}

class RepositoryXrayStratumData {
  final String id;
  final String label;
  final String pathPrefix;
  final int touchCount;
  final int ownerCount;
  final String lastTouchedAt;
  final String summary;

  /// Sum of per-file [RepositoryXrayHotspotData.aliveMass] across every
  /// file under this directory prefix — not just visible hotspots.
  /// Drives the Map view's stratum tile size, replacing raw
  /// [touchCount]. Same physics as the per-file alive mass, just
  /// aggregated. Defaults to 0 so callers without alive-mass data
  /// fall back to legacy sizing via the panel.
  final double aliveMass;

  const RepositoryXrayStratumData({
    required this.id,
    required this.label,
    required this.pathPrefix,
    required this.touchCount,
    required this.ownerCount,
    required this.lastTouchedAt,
    this.aliveMass = 0.0,
    required this.summary,
  });
}

class RepositoryXrayPivotCommitData {
  final String commitHash;
  final String shortHash;
  final String authoredAt;
  final String authorName;
  final String subject;
  final int filesChanged;
  final int insertions;
  final int deletions;

  const RepositoryXrayPivotCommitData({
    required this.commitHash,
    required this.shortHash,
    required this.authoredAt,
    required this.authorName,
    required this.subject,
    required this.filesChanged,
    required this.insertions,
    required this.deletions,
  });
}

class RepositoryXraySignalIntegrityData {
  final int rawCommitCount;
  final int filteredCommitCount;
  final int machineCommitCount;
  final int hiddenRefCount;
  final bool machineHistoryDominant;
  final bool hasHiddenRefs;

  const RepositoryXraySignalIntegrityData({
    required this.rawCommitCount,
    required this.filteredCommitCount,
    required this.machineCommitCount,
    required this.hiddenRefCount,
    required this.machineHistoryDominant,
    required this.hasHiddenRefs,
  });
}

/// Repo-wide metabolism derived from a Whisper Engram AR(2) fit on
/// the daily commit-rate series. Answers "is this repo alive, steady,
/// or slowing?" as physics, not vibes.
///   [spectralRadius] — |λ| of the oscillator. ≈ 1 means the repo
///   homeostats (active-day bursts beget more active days at roughly
///   the same amplitude); < 0.5 means activity spikes decay fast
///   (maintenance mode); > 1 means unbounded growth (almost certainly
///   an anomaly or a very fresh repo).
///   [halfLifeDays] — activity memory depth in days. Short = volatile
///   ("what mattered last week doesn't matter this week"); long =
///   slow, contemplative repo.
///   [activeDays] — how many distinct days had at least one commit in
///   the window. The sample count behind the fit; low values mean the
///   radius/half-life readings are wobbly.
///   [sparkline] — normalised commits-per-day counts in chronological
///   order, clipped to the recent window used for the fit. Already-
///   normalised so renderers can plot without recomputation.
class RepositoryXrayMetabolismData {
  final double spectralRadius;
  final double? halfLifeDays;
  final bool isOrbital;
  final String trajectoryLabel;
  final int activeDays;
  final List<double> sparkline;

  const RepositoryXrayMetabolismData({
    required this.spectralRadius,
    required this.halfLifeDays,
    required this.isOrbital,
    required this.trajectoryLabel,
    required this.activeDays,
    required this.sparkline,
  });

  /// Empty snapshot — returned when the window is too short to fit.
  /// Renderers should check [activeDays] before displaying anything.
  static const empty = RepositoryXrayMetabolismData(
    spectralRadius: 0,
    halfLifeDays: null,
    isOrbital: false,
    trajectoryLabel: '',
    activeDays: 0,
    sparkline: [],
  );
}

class RepositoryXrayFlowData {
  final double gradientMass;
  final double curlMass;
  final double harmonicMass;
  final double structuralStress;
  final double confidence;

  /// Spectral participation entropy of the repo's recent-activity focus
  /// under the heat-kernel at a canonical temperature, normalised to
  /// [0, 1] by `log(k)`. 0 = the recent work sits on a single spectral
  /// mode (maximally focused — one coherent sweep); 1 = uniform across
  /// modes (maximally diffuse — scatter-shot). Reads the Logos engine's
  /// cached spectral basis; 0 when no engine/basis is available.
  final double focusEntropy;

  /// Normalised isospectral fingerprint of the coupling graph:
  /// `Z(t) = Σⱼ e^{−t·λⱼ}` divided by `k` so the value sits in [0, 1].
  /// Two repos with the same coupling shape share the same trace (Kac,
  /// "Can one hear the shape of a drum?"). A PR or refactor that shifts
  /// this materially is changing architectural shape, not just file
  /// contents. Zero when no Logos engine/basis is available.
  final double heatTrace;

  const RepositoryXrayFlowData({
    required this.gradientMass,
    required this.curlMass,
    required this.harmonicMass,
    required this.structuralStress,
    required this.confidence,
    this.focusEntropy = 0.0,
    this.heatTrace = 0.0,
  });

  static const empty = RepositoryXrayFlowData(
    gradientMass: 0,
    curlMass: 0,
    harmonicMass: 0,
    structuralStress: 0,
    confidence: 0,
  );
}

/// One reviewer's observation footprint across the codebase.
class ReviewerConstellationEntry {
  final String login;
  final int observedPathCount;
  final int observedCommitCount;
  final List<String> topPaths;
  const ReviewerConstellationEntry({
    required this.login,
    required this.observedPathCount,
    required this.observedCommitCount,
    this.topPaths = const [],
  });
}

/// Per-path observation coverage — which reviewers have seen this region.
class PathObservationData {
  final String path;
  final Set<String> observers;
  final int observedCommitCount;
  const PathObservationData({
    required this.path,
    required this.observers,
    required this.observedCommitCount,
  });
}

/// Orbital decay event — a reviewer's attention withdrew from a region.
class OrbitalDecayEvent {
  final String reviewerLogin;
  final String pathPrefix;
  final double decayMagnitude;
  const OrbitalDecayEvent({
    required this.reviewerLogin,
    required this.pathPrefix,
    required this.decayMagnitude,
  });
}

/// Reviewer constellation data for the xray surface.
class ReviewerConstellationData {
  final List<ReviewerConstellationEntry> reviewers;
  final List<PathObservationData> blindSpots;
  final List<OrbitalDecayEvent> decayEvents;
  final int totalObservedPaths;
  final int totalUnobservedPaths;
  const ReviewerConstellationData({
    this.reviewers = const [],
    this.blindSpots = const [],
    this.decayEvents = const [],
    this.totalObservedPaths = 0,
    this.totalUnobservedPaths = 0,
  });
}

class RepositoryXraySnapshotData {
  final RepositoryXrayHeaderData header;
  final RepositoryXraySignalIntegrityData signalIntegrity;
  final RepositoryXrayRefSummaryData refSummary;
  final List<RepositoryXrayCardData> cards;
  final List<RepositoryXrayCardData> rawCards;
  final List<RepositoryXrayHotspotData> hotspots;
  final List<RepositoryXrayHotspotData> rawHotspots;
  final List<RepositoryXrayCadenceData> cadence;
  final List<RepositoryXrayCadenceData> rawCadence;
  final List<RepositoryXrayStratumData> strata;
  final List<RepositoryXrayPivotCommitData> pivots;
  final List<RepositoryXrayPivotCommitData> rawPivots;
  final RepositoryXrayMetabolismData metabolism;
  final RepositoryXrayFlowData flow;
  final ReviewerConstellationData? reviewerConstellations;

  const RepositoryXraySnapshotData({
    required this.header,
    required this.signalIntegrity,
    required this.refSummary,
    required this.cards,
    required this.rawCards,
    required this.hotspots,
    required this.rawHotspots,
    required this.cadence,
    required this.rawCadence,
    required this.strata,
    required this.pivots,
    required this.rawPivots,
    this.metabolism = RepositoryXrayMetabolismData.empty,
    this.flow = RepositoryXrayFlowData.empty,
    this.reviewerConstellations,
  });
}

class AiProviderStatus {
  final String id;
  final bool available;
  final String binary;
  final String? planName;
  final String? resolvedBinary;
  final String? detectionSource;
  final String? healthCheck;
  const AiProviderStatus({
    required this.id,
    required this.available,
    required this.binary,
    this.planName,
    this.resolvedBinary,
    this.detectionSource,
    this.healthCheck,
  });
  factory AiProviderStatus.fromJson(Map<String, dynamic> j) => AiProviderStatus(
        id: j['id'] ?? '',
        available: j['available'] ?? false,
        binary: j['binary'] ?? '',
        planName: j['plan_name'] ?? j['planName'],
        resolvedBinary: j['resolved_binary'] ?? j['resolvedBinary'],
        detectionSource: j['detection_source'] ?? j['detectionSource'],
        healthCheck: j['health_check'] ?? j['healthCheck'],
      );
}

class AiProviderListData {
  final List<AiProviderStatus> providers;
  const AiProviderListData({required this.providers});
  factory AiProviderListData.fromJson(Map<String, dynamic> j) =>
      AiProviderListData(
        providers: (j['providers'] as List? ?? [])
            .map((provider) => AiProviderStatus.fromJson(provider))
            .toList(),
      );
}

class AiModelOptionData {
  final String value;
  final String modelId;
  final String providerId;
  final String providerLabel;
  final String? planName;
  final String label;
  final String description;
  final double? promptPricePer1m;
  final double? completionPricePer1m;
  final bool supportsReasoning;
  final bool hasFastTier;

  const AiModelOptionData({
    required this.value,
    required this.modelId,
    required this.providerId,
    required this.providerLabel,
    this.planName,
    required this.label,
    required this.description,
    this.promptPricePer1m,
    this.completionPricePer1m,
    this.supportsReasoning = false,
    this.hasFastTier = false,
  });

  bool get hasPricing =>
      promptPricePer1m != null || completionPricePer1m != null;

  factory AiModelOptionData.fromJson(Map<String, dynamic> j) =>
      AiModelOptionData(
        value: j['value'] ?? '',
        modelId: j['model_id'] ?? j['modelId'] ?? '',
        providerId: j['provider_id'] ?? j['providerId'] ?? '',
        providerLabel: j['provider_label'] ?? j['providerLabel'] ?? '',
        planName: j['plan_name'] ?? j['planName'],
        label: j['label'] ?? '',
        description: j['description'] ?? '',
        promptPricePer1m: (j['prompt_price_per_1m'] as num?)?.toDouble(),
        completionPricePer1m:
            (j['completion_price_per_1m'] as num?)?.toDouble(),
        supportsReasoning: j['supports_reasoning'] == true,
        hasFastTier: j['has_fast_tier'] == true,
      );
}

class AiModelCategoryData {
  final String id;
  final String label;
  final String? description;
  final List<AiModelOptionData> models;

  const AiModelCategoryData({
    required this.id,
    required this.label,
    this.description,
    required this.models,
  });

  factory AiModelCategoryData.fromJson(Map<String, dynamic> j) =>
      AiModelCategoryData(
        id: j['id'] ?? '',
        label: j['label'] ?? '',
        description: j['description'],
        models: (j['models'] as List? ?? [])
            .map((model) => AiModelOptionData.fromJson(model))
            .toList(),
      );
}

class AiModelOptionListData {
  final List<AiModelCategoryData> categories;

  const AiModelOptionListData({required this.categories});

  factory AiModelOptionListData.fromJson(Map<String, dynamic> j) =>
      AiModelOptionListData(
        categories: (j['categories'] as List? ?? [])
            .map((category) => AiModelCategoryData.fromJson(category))
            .toList(),
      );
}

/// One brainstorm idea from the muse's phase-1 spew. `kept` indicates
/// the idea found grounding in the diffused logos context and was woven
/// into a phase-3 move. UI surfaces all ideas; the kept ones are
/// highlighted and tappable.
class AiMuseIdea {
  final int index;
  final String text;
  final bool kept;

  const AiMuseIdea({
    required this.index,
    required this.text,
    required this.kept,
  });
}

/// Ambition tier for a muse proposal. The muse distributes its
/// output across these tiers so every run offers a range from "could
/// ship this week" to "genuinely unhinged." Ordered by ambition: low
/// to high, with `fever` as the wildcard final.
enum AiMuseIdeaTier {
  /// Near-term, realistic — something that could ship as a normal PR.
  spark,
  /// Mid-term, this-month. Feels already in motion; naming where it goes.
  current,
  /// Grand but reachable. The project's destiny, named.
  horizon,
  /// Absurd, wildly eldritch, possibly impossible. Permission granted
  /// to propose the unhinged; still grounded in a real foothold so
  /// the absurdity reads as "WISH this existed" rather than noise.
  fever,
}

AiMuseIdeaTier? parseMuseIdeaTier(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'spark':
      return AiMuseIdeaTier.spark;
    case 'current':
      return AiMuseIdeaTier.current;
    case 'horizon':
      return AiMuseIdeaTier.horizon;
    case 'fever':
      return AiMuseIdeaTier.fever;
  }
  return null;
}

String museIdeaTierLabel(AiMuseIdeaTier tier) {
  switch (tier) {
    case AiMuseIdeaTier.spark:
      return 'spark';
    case AiMuseIdeaTier.current:
      return 'current';
    case AiMuseIdeaTier.horizon:
      return 'horizon';
    case AiMuseIdeaTier.fever:
      return 'fever';
  }
}

/// A single proposal in the muse output. Unlike the old "move" shape
/// (which read as a summary of what the change rhymes with), a
/// proposal is generative: a title + a vision + a foothold that
/// anchors the idea to something real in the codebase. Tier signals
/// ambition range; the muse emits a distribution across all four.
class AiMuseProposal {
  final AiMuseIdeaTier tier;
  /// Short, memorable name for the idea (4-8 words). Named like a
  /// feature, not a sentence.
  final String title;
  /// 1-2 sentences of generative imagination. What the idea WOULD
  /// BE, written in the present tense of the hypothetical world.
  final String vision;
  /// One sentence anchoring the idea to a concrete point in the
  /// code — what's already there that makes this reachable.
  final String foothold;
  /// Paths or path:line references cited by this proposal. The
  /// primary foothold citation is the first entry; additional cites
  /// may appear when the idea spans multiple touch points.
  final List<String> citations;
  /// Links back to a brainstorm idea index when the synthesis wove
  /// a phase-1 spew into this proposal. Null when the idea sprang
  /// from the synthesis pass directly.
  final int? originatingIdeaIndex;

  const AiMuseProposal({
    required this.tier,
    required this.title,
    required this.vision,
    required this.foothold,
    this.citations = const [],
    this.originatingIdeaIndex,
  });
}

/// Output of the three-phase muse pipeline.
///
/// The muse's job is to PROPOSE, not to summarize. Its output is a
/// list of [AiMuseProposal]s distributed across four ambition tiers
/// (spark / current / horizon / fever). Every proposal carries its
/// own foothold citation so the ambition still reads as reachable.
/// The brainstorm phase-1 spew is preserved in [brainstormIdeas] for
/// the UI's "raw ideas" drawer.
class AiMuseData {
  final String providerId;
  final String modelId;
  final String scopeLabel;
  /// Ambition-distributed proposals. Ordered in emission order from
  /// the synthesis pass; consumers can re-group by tier via
  /// [proposalsForTier] for rendering.
  final List<AiMuseProposal> proposals;
  final List<AiMuseIdea> brainstormIdeas;
  final int promptCharacters;
  final int diffCharacters;

  /// Free-form warnings raised during parse — malformed `<idea>` tags,
  /// missing foothold citations, tiers the model invented. Rendered as
  /// a muted footnote so the user knows the synthesis wasn't clean
  /// without hiding the successful proposals behind the error.
  final List<String> parseWarnings;

  /// Paths the user explicitly pulled on during the loading canvas.
  /// These boosted the phase-2 seed map, and their presence in a
  /// proposal's foothold citation lets the UI surface "you pulled
  /// this" — closing the loop between the physical gesture and the
  /// rendered result.
  final Set<String> userBoostedPaths;

  const AiMuseData({
    required this.providerId,
    required this.modelId,
    required this.scopeLabel,
    this.proposals = const [],
    this.brainstormIdeas = const [],
    required this.promptCharacters,
    required this.diffCharacters,
    this.parseWarnings = const [],
    this.userBoostedPaths = const {},
  });

  int get keptIdeaCount => brainstormIdeas.where((idea) => idea.kept).length;
  int get totalIdeaCount => brainstormIdeas.length;

  /// Proposals filtered to a single tier, preserving emission order.
  /// Used by the UI to group the display under tier headers without
  /// mutating the source list.
  List<AiMuseProposal> proposalsForTier(AiMuseIdeaTier tier) =>
      proposals.where((p) => p.tier == tier).toList(growable: false);
}

class AiCommitMessageData {
  final String providerId;
  final String modelId;
  final String message;
  final String scopeLabel;
  final int promptCharacters;
  final int diffCharacters;

  const AiCommitMessageData({
    required this.providerId,
    required this.modelId,
    required this.message,
    required this.scopeLabel,
    required this.promptCharacters,
    required this.diffCharacters,
  });
}

/// Result of a one-shot AI call that expects a unified diff back.
/// The `patch` field is the raw text that should apply via `git apply`;
/// callers verify with `applyPatch(..., dryRun: true)` before mutating
/// the tree. When the model wraps output in code fences we strip them
/// here so callers get clean `--- a/ +++ b/` headers either way.
class AiPatchData {
  final String providerId;
  final String modelId;
  final String patch;
  final int promptCharacters;
  final int patchCharacters;

  const AiPatchData({
    required this.providerId,
    required this.modelId,
    required this.patch,
    required this.promptCharacters,
    required this.patchCharacters,
  });
}

class AiCommitReviewFindingData {
  final String id;
  final String severity;
  final String title;
  final String evidence;
  final String whyItMatters;
  final String? filePath;
  final String? hunkLabel;
  final String origin;

  const AiCommitReviewFindingData({
    required this.id,
    required this.severity,
    required this.title,
    required this.evidence,
    required this.whyItMatters,
    this.filePath,
    this.hunkLabel,
    required this.origin,
  });
}

class AiCommitReviewObservationData {
  final String id;
  final String title;
  final String detail;
  final String? filePath;

  const AiCommitReviewObservationData({
    required this.id,
    required this.title,
    required this.detail,
    this.filePath,
  });
}

class AiCommitReviewVerificationData {
  final List<String> confirmedFindingIds;
  final List<String> rejectedFindingIds;
  final List<AiCommitReviewFindingData> newFindings;
  final int scoreAdjustment;
  final String? verdictAdjustment;
  final String verificationNotes;
  final String finalSummary;
  final String finalReasoningReport;

  const AiCommitReviewVerificationData({
    required this.confirmedFindingIds,
    required this.rejectedFindingIds,
    required this.newFindings,
    required this.scoreAdjustment,
    required this.verdictAdjustment,
    required this.verificationNotes,
    required this.finalSummary,
    required this.finalReasoningReport,
  });
}

class AiCommitReviewData {
  final String providerId;
  final String modelId;
  final String modelCategoryLabel;
  final int guardrailStage;
  final String scopeLabel;
  final int promptCharacters;
  final int diffCharacters;
  final String verdict;
  final int score;
  final String summary;
  final String reasoningReport;
  final List<AiCommitReviewFindingData> findings;
  final List<AiCommitReviewObservationData> observations;
  final bool twoStepEnabled;
  final bool hasVerificationTrace;
  final bool verificationFailed;
  final String? verificationError;
  final List<AiCommitReviewFindingData> draftFindings;
  final String? draftSummary;
  final String? draftReasoningReport;
  final String? verificationNotes;

  const AiCommitReviewData({
    required this.providerId,
    required this.modelId,
    this.modelCategoryLabel = '',
    this.guardrailStage = 1,
    required this.scopeLabel,
    required this.promptCharacters,
    required this.diffCharacters,
    required this.verdict,
    required this.score,
    required this.summary,
    required this.reasoningReport,
    required this.findings,
    this.observations = const [],
    required this.twoStepEnabled,
    required this.hasVerificationTrace,
    this.verificationFailed = false,
    this.verificationError,
    this.draftFindings = const [],
    this.draftSummary,
    this.draftReasoningReport,
    this.verificationNotes,
  });
}

class StashEntryData {
  final int index;
  final String message;
  final String hash;
  final String createdAt;
  final int fileCount;

  const StashEntryData({
    required this.index,
    required this.message,
    required this.hash,
    required this.createdAt,
    this.fileCount = 0,
  });
}

/// One file entry inside a stash, for the filing-cabinet UI. Adds/dels come
/// from `git stash show --numstat`. Binary files report -/- in numstat —
/// surfaced as [binary] so the UI can render a placeholder instead of 0/0.
class StashFileStat {
  final String path;
  final int adds;
  final int dels;
  final bool binary;

  const StashFileStat({
    required this.path,
    required this.adds,
    required this.dels,
    this.binary = false,
  });
}

/// One "desk" — a git worktree. The primary worktree is the main repo
/// directory itself; additional desks live under `.manifold/worktrees/`.
class WorktreeData {
  final String path;
  final String head;
  final String? branch;
  final bool isMain;
  final bool isDetached;
  final bool isLocked;
  final int dirtyFileCount;

  const WorktreeData({
    required this.path,
    required this.head,
    this.branch,
    required this.isMain,
    required this.isDetached,
    required this.isLocked,
    this.dirtyFileCount = 0,
  });
}

class RebaseTodoEntry {
  final String action;
  final String commitHash;
  final String subject;
  const RebaseTodoEntry(
      {required this.action, required this.commitHash, required this.subject});
}

class AppSettingsData {
  final String themeId;
  final String keybindingProfile;
  final int sidebarWidthPx;
  final bool aiReadOnlyDefault;
  const AppSettingsData({
    required this.themeId,
    required this.keybindingProfile,
    required this.sidebarWidthPx,
    required this.aiReadOnlyDefault,
  });
  factory AppSettingsData.fromJson(Map<String, dynamic> j) => AppSettingsData(
        themeId: j['theme_id'] ?? j['themeId'] ?? 'aether',
        keybindingProfile:
            j['keybinding_profile'] ?? j['keybindingProfile'] ?? 'classic',
        sidebarWidthPx: j['sidebar_width_px'] ?? j['sidebarWidthPx'] ?? 240,
        aiReadOnlyDefault:
            j['ai_read_only_default'] ?? j['aiReadOnlyDefault'] ?? true,
      );
}
