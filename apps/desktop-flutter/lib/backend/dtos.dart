/// How many commits back the app reaches by default when reading history.
/// Single source of truth shared by the History page (its limit field) and the
/// Orrery (its trajectory window), so the two stay in step instead of each
/// hard-coding its own number. Lives here because dtos.dart is dependency-free
/// and safe to import from the Orrery's background isolate.
const int kDefaultHistoryCommits = 100;

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
        branch: j['branch'] as String? ?? '',
        upstream: j['upstream'] as String?,
        ahead: j['ahead'] as int? ?? 0,
        behind: j['behind'] as int? ?? 0,
        files: (j['files'] as List? ?? [])
            .map((f) =>
                RepositoryStatusFile.fromJson(f as Map<String, dynamic>))
            .toList(),
        // Default true when the field is absent so older serialised
        // statuses don't suddenly hide affordances after this rolls in.
        hasHeadCommit: j['hasHeadCommit'] as bool? ?? true,
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
        commitHash: (j['commit_hash'] ?? j['commitHash']) as String? ?? '',
        shortHash: (j['short_hash'] ?? j['shortHash']) as String? ?? '',
        parentHashes: List<String>.from(
            (j['parent_hashes'] ?? j['parentHashes']) as List? ?? []),
        refNames: List<String>.from(
            (j['ref_names'] ?? j['refNames']) as List? ?? []),
        isMerge: (j['is_merge'] ?? j['isMerge']) as bool? ?? false,
        subject: j['subject'] as String? ?? '',
        authorName: (j['author_name'] ?? j['authorName']) as String? ?? '',
        authorEmail: (j['author_email'] ?? j['authorEmail']) as String? ?? '',
        authoredAt: (j['authored_at'] ?? j['authoredAt']) as String? ?? '',
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
          path: j['path'] as String? ?? '',
          additions: j['additions'] as int? ?? 0,
          deletions: j['deletions'] as int? ?? 0,
          changeType: j['changeType'] as String? ?? 'M');
}

/// One hunk header from a commit's diff, parsed straight from the
/// `@@ -a,b +c,d @@` line. Carries only what the seismograph needs to
/// place a band inside a large leaf bar: where the hunk lands in the
/// new file (`newStart`) and its add/del composition. The header counts
/// already encode that composition — `additions` is the new-line count
/// (d), `deletions` is the old-line count (b) — so parsing never has to
/// read a single body line.
class CommitHunk {
  final int newStart;
  final int additions;
  final int deletions;
  const CommitHunk({
    required this.newStart,
    required this.additions,
    required this.deletions,
  });

  /// Vertical extent this hunk occupies in the new file — the larger of
  /// its add/del counts, floored at 1 so a pure single-line change still
  /// paints a visible band.
  int get span {
    final m = additions > deletions ? additions : deletions;
    return m < 1 ? 1 : m;
  }
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
        commitHash: (j['commit_hash'] ?? j['commitHash']) as String? ?? '',
        shortHash: (j['short_hash'] ?? j['shortHash']) as String? ?? '',
        subject: j['subject'] as String? ?? '',
        body: j['body'] as String? ?? '',
        authorName: (j['author_name'] ?? j['authorName']) as String? ?? '',
        authorEmail: (j['author_email'] ?? j['authorEmail']) as String? ?? '',
        authoredAt: (j['authored_at'] ?? j['authoredAt']) as String? ?? '',
        filesChanged: (j['files_changed'] ?? j['filesChanged']) as int? ?? 0,
        additions: j['additions'] as int? ?? 0,
        deletions: j['deletions'] as int? ?? 0,
        files: (j['files'] as List? ?? [])
            .map((f) => CommitFileStatData.fromJson(f as Map<String, dynamic>))
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

  /// True when merging this branch into the comparison base would change
  /// nothing — its content already lives in base regardless of ancestry.
  /// The ABSORPTION LAW: `git merge-tree --write-tree <base> <branch>`
  /// yields a tree identical to base's own tree. Subsumes tree-equal
  /// squash detection and additionally catches transplants (Manifold's
  /// move-changes flow), cherry-picks and amended replays — any ceremony
  /// that lands the content without recording a parent edge. Computed via
  /// [branchAbsorption]; null when unprobed OR when git is too old
  /// (< 2.38) to answer, in which case [squashMerged] is the fallback.
  ///
  /// The law is EXISTENTIAL OVER HISTORY: some first-parent base commit
  /// since the fork absorbs the branch. Once witnessed, permanent — base
  /// evolving (even rewriting the same files) cannot revoke delivery.
  final bool? absorbed;

  /// The witness commit hash when [absorbed] is true — the exact base
  /// commit into which merging this branch changes nothing. The receipt
  /// behind the 'absorbed' whisper ("delivered in <shortHash>").
  final String? absorbedWitness;

  const BranchInfo({
    required this.name,
    required this.current,
    this.upstream,
    required this.ahead,
    required this.behind,
    this.gone = false,
    this.lastCommitAt,
    this.squashMerged,
    this.absorbed,
    this.absorbedWitness,
  });

  factory BranchInfo.fromJson(Map<String, dynamic> j) => BranchInfo(
        name: j['name'] as String? ?? '',
        current: j['current'] as bool? ?? false,
        upstream: j['upstream'] as String?,
        ahead: j['ahead'] as int? ?? 0,
        behind: j['behind'] as int? ?? 0,
        gone: j['gone'] as bool? ?? false,
        lastCommitAt: j['lastCommitAt'] is String
            ? DateTime.tryParse(j['lastCommitAt'] as String)
            : null,
        squashMerged:
            j['squashMerged'] is bool ? j['squashMerged'] as bool : null,
        absorbed: j['absorbed'] is bool ? j['absorbed'] as bool : null,
        absorbedWitness: j['absorbedWitness'] as String?,
      );

  BranchInfo copyWith({
    bool? squashMerged,
    bool? absorbed,
    String? absorbedWitness,
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
        absorbed: absorbed ?? this.absorbed,
        absorbedWitness: absorbedWitness ?? this.absorbedWitness,
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
        name: j['name'] as String? ?? '',
        tagType: (j['tag_type'] ?? j['tagType']) as String? ?? '',
        targetHash: (j['target_hash'] ?? j['targetHash']) as String?,
        createdAt: (j['created_at'] ?? j['createdAt']) as String?,
        creatorName: (j['creator_name'] ?? j['creatorName']) as String?,
        subject: j['subject'] as String?,
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
        commitHash: (j['commit_hash'] ?? j['commitHash']) as String? ?? '',
        shortHash: (j['short_hash'] ?? j['shortHash']) as String? ?? '',
        refSelector: (j['ref_selector'] ?? j['refSelector']) as String? ?? '',
        actionSummary:
            (j['action_summary'] ?? j['actionSummary']) as String? ?? '',
        authorName: (j['author_name'] ?? j['authorName']) as String? ?? '',
        authoredAt: (j['authored_at'] ?? j['authoredAt']) as String? ?? '',
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
        lineNumber: (j['line_number'] ?? j['lineNumber']) as int? ?? 0,
        commitHash: (j['commit_hash'] ?? j['commitHash']) as String? ?? '',
        shortHash: (j['short_hash'] ?? j['shortHash']) as String? ?? '',
        authorName: (j['author_name'] ?? j['authorName']) as String? ?? '',
        authoredAt: (j['authored_at'] ?? j['authoredAt']) as String? ?? '',
        lineContent: (j['line_content'] ?? j['lineContent']) as String? ?? '',
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
        commitHash: (j['commit_hash'] ?? j['commitHash']) as String? ?? '',
        shortHash: (j['short_hash'] ?? j['shortHash']) as String? ?? '',
        subject: j['subject'] as String? ?? '',
        authorName: (j['author_name'] ?? j['authorName']) as String? ?? '',
        authoredAt: (j['authored_at'] ?? j['authoredAt']) as String? ?? '',
        matchContext: (j['match_context'] ?? j['matchContext']) as String?,
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
        operation: j['operation'] as String? ?? '',
        remote: j['remote'] as String? ?? '',
        branch: j['branch'] as String?,
        output: j['output'] as String? ?? '',
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

/// The repo's structural identity — its nearest universality archetype and how
/// cleanly it fits. This is the X-ray "verdict": the one-glance answer to *what
/// kind of codebase is this*. Computed every snapshot from the spectral
/// geometry; null when the graph is too small for the classification to
/// converge (the engine needs a few hundred coupled files).
class RepositoryXrayVerdictData {
  /// crystalline / poisson / goe / tree / bulk / modular.
  final String archetype;

  /// 0..1 — how cleanly the repo fits a known archetype (1 = textbook).
  final double canonicality;

  /// 0..1 — how decisively one archetype wins over the runner-up
  /// (1 = unambiguous, 0 = sitting between two classes).
  final double decisiveness;

  const RepositoryXrayVerdictData({
    required this.archetype,
    required this.canonicality,
    required this.decisiveness,
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

enum StratumRole {
  /// The stratum containing the app's current working surface.
  current,
  /// Older half of a detected migration pair under the same root.
  legacy,
  /// Generic stratum with no special structural role.
  zone,
}

class RepositoryXrayStratumData {
  final String id;
  final StratumRole role;
  final String pathPrefix;
  final int touchCount;
  final int ownerCount;
  final String lastTouchedAt;
  final double aliveMass;

  double get aliveRatio =>
      touchCount > 0 ? aliveMass / touchCount : 0.0;

  const RepositoryXrayStratumData({
    required this.id,
    this.role = StratumRole.zone,
    required this.pathPrefix,
    required this.touchCount,
    required this.ownerCount,
    required this.lastTouchedAt,
    this.aliveMass = 0.0,
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

  /// The structural verdict — "what kind of codebase is this". Null when the
  /// graph is too small for the spectral classification.
  final RepositoryXrayVerdictData? verdict;
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
    this.verdict,
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
        id: j['id'] as String? ?? '',
        available: j['available'] as bool? ?? false,
        binary: j['binary'] as String? ?? '',
        planName: (j['plan_name'] ?? j['planName']) as String?,
        resolvedBinary: (j['resolved_binary'] ?? j['resolvedBinary']) as String?,
        detectionSource:
            (j['detection_source'] ?? j['detectionSource']) as String?,
        healthCheck: (j['health_check'] ?? j['healthCheck']) as String?,
      );
}

class AiProviderListData {
  final List<AiProviderStatus> providers;
  const AiProviderListData({required this.providers});
  factory AiProviderListData.fromJson(Map<String, dynamic> j) =>
      AiProviderListData(
        providers: (j['providers'] as List? ?? [])
            .map((provider) =>
                AiProviderStatus.fromJson(provider as Map<String, dynamic>))
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
        value: j['value'] as String? ?? '',
        modelId: (j['model_id'] ?? j['modelId']) as String? ?? '',
        providerId: (j['provider_id'] ?? j['providerId']) as String? ?? '',
        providerLabel:
            (j['provider_label'] ?? j['providerLabel']) as String? ?? '',
        planName: (j['plan_name'] ?? j['planName']) as String?,
        label: j['label'] as String? ?? '',
        description: j['description'] as String? ?? '',
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
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        description: j['description'] as String?,
        models: (j['models'] as List? ?? [])
            .map((model) => AiModelOptionData.fromJson(model as Map<String, dynamic>))
            .toList(),
      );
}

class AiModelOptionListData {
  final List<AiModelCategoryData> categories;

  const AiModelOptionListData({required this.categories});

  factory AiModelOptionListData.fromJson(Map<String, dynamic> j) =>
      AiModelOptionListData(
        categories: (j['categories'] as List? ?? [])
            .map((category) =>
                AiModelCategoryData.fromJson(category as Map<String, dynamic>))
            .toList(),
      );
}

/// One brainstorm idea from the muse's phase-1 spew.
class AiMuseIdea {
  final int index;
  final String text;

  const AiMuseIdea({
    required this.index,
    required this.text,
  });
}

/// A muse strand — the walker character that generated an idea.
///
/// The first four are the canonical ambition tiers ("a spark of
/// inspiration, a current in the water, a look over the horizon, and
/// after you wake from a fever dream"). They form the default quiver
/// and recover the original muse behavior bit-for-bit. The remaining
/// four are optional strands the user can add to a custom quiver:
///
///   • [echo] — find analogues across the canyon. Where else does
///     this pattern live? (K-space KNN walker.)
///   • [vertigo] — feel the cliff edge. What does this jeopardize?
///     (Hunk-graph adjacency walker.)
///   • [ghost] — what came before in this place. What did this
///     replace? (Commit-history backward walker.)
///   • [mirror] — reflection on still water. What's the inverse
///     question? (Post-hoc inverse of the other walkers.)
///
/// `AiMuseIdeaTier` is the historical name; the new code calls these
/// "strands" to reflect the multi-walker model. A default quiver of
/// [spark, current, horizon, fever] still tells the original four-part
/// story.
enum MuseStrandKind {
  /// Near-term, realistic — the immediately next move. Grounded
  /// walker, low temperature, short walks from diff anchors.
  spark,
  /// Mid-term, present-tense extension. Feels already in motion;
  /// names where it goes. Medium-grounded walker.
  current,
  /// Grand but reachable. The project's destiny, named. Reaching
  /// walker, medium-high temperature.
  horizon,
  /// Absurd, wildly eldritch, possibly impossible. Pure anomaly walker,
  /// hot temperature, leaves the local neighborhood.
  fever,
  /// Find analogues. Walks the symbol-overlap graph for places that
  /// resemble what's being changed. "Where else does this pattern live?"
  echo,
  /// Adjacent risks. Walks the coupling graph for things that will
  /// break if this changes. "What does this jeopardize?"
  vertigo,
  /// Historical context. Walks backward through commit history.
  /// "What does this replace, and why was that there?"
  ghost,
  /// Inversions. Coherent with the other walkers in the quiver;
  /// generates the inverse of what they generate.
  /// "What's the question you're NOT asking?"
  mirror,
}

/// The original 4-strand default quiver, in display order. Shipping a
/// quiver with exactly these strands produces output that's bit-for-bit
/// equivalent to the pre-quiver muse — same tiers, same glyphs, same
/// renderer pathway.
const List<MuseStrandKind> kDefaultMuseStrands = [
  MuseStrandKind.spark,
  MuseStrandKind.current,
  MuseStrandKind.horizon,
  MuseStrandKind.fever,
];

/// The canonical render order for muse strands. A time/attention arc
/// that interleaves the lenses (echo, vertigo, ghost, mirror) into the
/// ambition spine (spark, current, horizon, fever) at the moments they
/// belong:
///
///   ghost    — what came before (archaeology)
///   spark    — the immediately next step
///   echo     — analogues to the small idea
///   current  — present-tense extension
///   vertigo  — adjacent risks of the present
///   horizon  — reaching forward
///   mirror   — invert the gesture before going wild
///   fever    — full dream
///
/// Both the settings strand strip and the muse output panel iterate
/// this list so the reader sees the same flow in both surfaces. Update
/// in one place; the whole muse honors it.
const List<MuseStrandKind> kMuseStrandDisplayOrder = [
  MuseStrandKind.ghost,
  MuseStrandKind.spark,
  MuseStrandKind.echo,
  MuseStrandKind.current,
  MuseStrandKind.vertigo,
  MuseStrandKind.horizon,
  MuseStrandKind.mirror,
  MuseStrandKind.fever,
];

/// Complete and de-duplicate a (possibly partial or stale) strand
/// order into a canonical full ordering. Recognised entries keep the
/// caller's relative order; any strand missing from [raw] is appended
/// in [kMuseStrandDisplayOrder] order. The result always contains
/// every [MuseStrandKind] exactly once, so both the settings strand
/// strip and the muse output panel can iterate a user-reordered list
/// without membership checks — and a strand added in a future build
/// shows up automatically rather than vanishing from a stale persisted
/// order.
List<MuseStrandKind> normalizeMuseStrandOrder(Iterable<MuseStrandKind> raw) {
  final seen = <MuseStrandKind>{};
  final out = <MuseStrandKind>[];
  for (final k in raw) {
    if (seen.add(k)) out.add(k);
  }
  for (final k in kMuseStrandDisplayOrder) {
    if (seen.add(k)) out.add(k);
  }
  return out;
}

MuseStrandKind? parseMuseStrand(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'spark':
      return MuseStrandKind.spark;
    case 'current':
      return MuseStrandKind.current;
    case 'horizon':
      return MuseStrandKind.horizon;
    case 'fever':
      return MuseStrandKind.fever;
    case 'echo':
      return MuseStrandKind.echo;
    case 'vertigo':
      return MuseStrandKind.vertigo;
    case 'ghost':
      return MuseStrandKind.ghost;
    case 'mirror':
      return MuseStrandKind.mirror;
  }
  return null;
}

String museStrandLabel(MuseStrandKind strand) {
  switch (strand) {
    case MuseStrandKind.spark:
      return 'spark';
    case MuseStrandKind.current:
      return 'current';
    case MuseStrandKind.horizon:
      return 'horizon';
    case MuseStrandKind.fever:
      return 'fever';
    case MuseStrandKind.echo:
      return 'echo';
    case MuseStrandKind.vertigo:
      return 'vertigo';
    case MuseStrandKind.ghost:
      return 'ghost';
    case MuseStrandKind.mirror:
      return 'mirror';
  }
}

/// Single source of truth for strand glyphs across every surface
/// (settings strand strip, muse section headers, muse jump strip).
/// Each strand has a distinct Unicode mark — the original ambition
/// spectrum gets a star gradient (✧ open → ✦ solid → ✷ radiant)
/// instead of three identical ✦'s, so spark/current/horizon are
/// visually distinguishable wherever they appear. The lenses
/// (echo/vertigo/ghost/mirror) and fever each carry their own
/// signature mark.
String museStrandGlyph(MuseStrandKind strand) {
  switch (strand) {
    case MuseStrandKind.spark:
      return '✧'; // open four-point star — a glimmer, possibility
    case MuseStrandKind.current:
      return '✦'; // solid four-point star — present, anchored
    case MuseStrandKind.horizon:
      return '✷'; // radiant eight-point star — reaching outward
    case MuseStrandKind.fever:
      return '☽'; // waxing crescent — dream territory
    case MuseStrandKind.echo:
      return '◌'; // dotted ring — analogue, returning shape
    case MuseStrandKind.vertigo:
      return '◈'; // diamond with inset — precarious balance
    case MuseStrandKind.ghost:
      return '◐'; // half-shaded circle — partial visibility, past
    case MuseStrandKind.mirror:
      return '◯'; // open ring — reflective surface
  }
}

// Backward-compatible alias. New code should use [MuseStrandKind].
typedef AiMuseIdeaTier = MuseStrandKind;
MuseStrandKind? parseMuseIdeaTier(String raw) => parseMuseStrand(raw);
String museIdeaTierLabel(MuseStrandKind strand) => museStrandLabel(strand);

/// One-line role tag for each strand — the character's job in a
/// single phrase. Distinct from the full strand sheets used in the
/// synthesis prompt: those carry block-specific instructions
/// ("read <diff_motion>", "speak from <temporal_neighborhood>") that
/// are synthesis-specific. This compact form is for the brainstorm
/// pass where we want to tell the divergent model which characters
/// will be downstream without bloating the cheap call or constraining
/// the brainstorm to strand-tagged generation.
String museStrandShortRole(MuseStrandKind strand) {
  switch (strand) {
    case MuseStrandKind.spark:
      return 'apprentice of the smallest next move';
    case MuseStrandKind.current:
      return 'steward naming where the work is going';
    case MuseStrandKind.horizon:
      return 'visionary announcing the destiny';
    case MuseStrandKind.fever:
      return 'madwoman in the attic breaking the frame';
    case MuseStrandKind.echo:
      return 'folklorist of structural rhyme';
    case MuseStrandKind.vertigo:
      return 'sentry watching the edges';
    case MuseStrandKind.ghost:
      return 'archivist of recorded history';
    case MuseStrandKind.mirror:
      return 'trickster inverting the action';
  }
}

/// One slot in the muse's active loadout: which strand to fire.
///
/// The [count] field is **forward-compat infrastructure**, not a
/// live knob. The current muse pipeline reads only [kind] when
/// composing the synthesis ensemble — strands are binary on/off,
/// hardcoded to count=1 by the settings toggle. The field is
/// persisted and round-tripped so that a future per-strand
/// multiplicity (different walker thermals per strand, ranked
/// idea-budget per strand) can land without migrating the
/// settings format. Until then: changing count in a hand-edited
/// settings file has no effect on output.
class MuseQuiverEntry {
  final MuseStrandKind kind;
  final int count;

  const MuseQuiverEntry({required this.kind, required this.count});

  MuseQuiverEntry copyWith({MuseStrandKind? kind, int? count}) =>
      MuseQuiverEntry(kind: kind ?? this.kind, count: count ?? this.count);

  Map<String, dynamic> toJson() => {
        'kind': museStrandLabel(kind),
        'count': count,
      };

  static MuseQuiverEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    final kindStr = map['kind'];
    final countRaw = map['count'];
    if (kindStr is! String) return null;
    final kind = parseMuseStrand(kindStr);
    if (kind == null) return null;
    final count = countRaw is int
        ? countRaw
        : (countRaw is num ? countRaw.toInt() : 1);
    return MuseQuiverEntry(kind: kind, count: count.clamp(1, 5));
  }
}

/// The initial loadout shipped on first install — the original four
/// strands at count 1 each. Reproduces the pre-quiver muse exactly.
/// After first install the user freely reshapes this; there are no
/// "presets" to switch between, just the one loadout you tune.
List<MuseQuiverEntry> defaultMuseQuiver() => const [
      MuseQuiverEntry(kind: MuseStrandKind.spark, count: 1),
      MuseQuiverEntry(kind: MuseStrandKind.current, count: 1),
      MuseQuiverEntry(kind: MuseStrandKind.horizon, count: 1),
      MuseQuiverEntry(kind: MuseStrandKind.fever, count: 1),
    ];

/// A single proposal in the muse output. Unlike the old "move" shape
/// (which read as a summary of what the change rhymes with), a
/// proposal is generative: a title + a vision + a foothold that
/// anchors the idea to something real in the codebase. Tier signals
/// ambition range; the muse emits a distribution across all four.
class AiMuseProposal {
  /// The strand that generated this idea. For default-quiver runs this
  /// is one of the original four (spark/current/horizon/fever) and
  /// reads as the ambition tier; for custom quivers it identifies the
  /// walker character of origin.
  final MuseStrandKind strand;
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
    required this.strand,
    required this.title,
    required this.vision,
    required this.foothold,
    this.citations = const [],
    this.originatingIdeaIndex,
  });

  /// Historical alias — old call sites read `.tier`.
  MuseStrandKind get tier => strand;
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
  /// The synthesis model (phase 3) — the one that wrote the proposals.
  /// The muse is a two-model pipeline: a separately-configured
  /// brainstorm model (named by [brainstormProviderId]/
  /// [brainstormModelId]) produces the phase-1 spew, then this model
  /// synthesises it into proposals. They're often different (cheap
  /// brainstorm, strong synthesis), so both are recorded.
  final String providerId;
  final String modelId;
  /// The brainstorm model (phase 1). Empty when the run predates
  /// two-model tracking; consumers fall back to a single model line.
  final String brainstormProviderId;
  final String brainstormModelId;
  final String scopeLabel;
  /// Ambition-distributed proposals. Ordered in emission order from
  /// the synthesis pass; consumers can re-group by tier via
  /// [proposalsForTier] for rendering.
  final List<AiMuseProposal> proposals;
  final List<AiMuseIdea> brainstormIdeas;
  final int promptCharacters;
  final int diffCharacters;
  final int brainstormInputTokens;
  final int brainstormOutputTokens;
  final int synthesisInputTokens;
  final int synthesisOutputTokens;

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
    this.brainstormProviderId = '',
    this.brainstormModelId = '',
    required this.scopeLabel,
    this.proposals = const [],
    this.brainstormIdeas = const [],
    required this.promptCharacters,
    required this.diffCharacters,
    this.brainstormInputTokens = 0,
    this.brainstormOutputTokens = 0,
    this.synthesisInputTokens = 0,
    this.synthesisOutputTokens = 0,
    this.parseWarnings = const [],
    this.userBoostedPaths = const {},
  });

  int get totalInputTokens => brainstormInputTokens + synthesisInputTokens;
  int get totalOutputTokens => brainstormOutputTokens + synthesisOutputTokens;

  int get totalIdeaCount => brainstormIdeas.length;

  /// Proposals filtered to a single strand, preserving emission order.
  /// Used by the UI to group the display under strand headers without
  /// mutating the source list.
  List<AiMuseProposal> proposalsForStrand(MuseStrandKind strand) =>
      proposals.where((p) => p.strand == strand).toList(growable: false);

  /// Backward-compatible alias for [proposalsForStrand].
  List<AiMuseProposal> proposalsForTier(MuseStrandKind tier) =>
      proposalsForStrand(tier);
}

/// Per-transaction usage/telemetry a provider reports about ONE completed
/// request. Input/output tokens come from most providers; the rest are
/// best-effort extras a given provider may or may not surface. NOTHING here
/// ever triggers an extra call — it is all parsed from the response we already
/// received — and the UI shows only the fields that are present. The type is
/// deliberately a superset: a future CLI that reports more just fills more
/// fields, and nothing downstream needs to change.
class AiUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheReadTokens;
  final int? cacheWriteTokens;

  /// Reasoning/thinking output tokens, when the provider reports them as a
  /// distinct dimension (codex, opencode). Null when unreported.
  final int? reasoningTokens;
  final Duration? duration;
  final String? requestId;

  /// The concrete model a routing alias resolved to, when the provider reveals
  /// it. Cursor's `auto` deliberately does not, so this stays null there.
  final String? resolvedModel;

  /// Provider-reported cost in USD, when available (most CLIs: null).
  final double? costUsd;

  const AiUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens,
    this.cacheWriteTokens,
    this.reasoningTokens,
    this.duration,
    this.requestId,
    this.resolvedModel,
    this.costUsd,
  });

  static const AiUsage empty = AiUsage();

  bool get hasTokens => inputTokens > 0 || outputTokens > 0;

  /// True when there is detail beyond the plain in/out counts worth surfacing —
  /// drives whether the UI bothers rendering a hover breakdown at all.
  bool get hasExtras =>
      (cacheReadTokens ?? 0) > 0 ||
      (cacheWriteTokens ?? 0) > 0 ||
      (reasoningTokens ?? 0) > 0 ||
      duration != null ||
      requestId != null ||
      resolvedModel != null ||
      costUsd != null;

  bool get isEmpty => !hasTokens && !hasExtras;

  /// Combine two usages for multi-call flows (e.g. review draft + verify).
  /// Counts and duration add; identity extras (requestId, resolvedModel) don't
  /// combine, so the later non-null one wins.
  AiUsage operator +(AiUsage o) => AiUsage(
        inputTokens: inputTokens + o.inputTokens,
        outputTokens: outputTokens + o.outputTokens,
        cacheReadTokens: _sumInt(cacheReadTokens, o.cacheReadTokens),
        cacheWriteTokens: _sumInt(cacheWriteTokens, o.cacheWriteTokens),
        reasoningTokens: _sumInt(reasoningTokens, o.reasoningTokens),
        duration: (duration == null && o.duration == null)
            ? null
            : (duration ?? Duration.zero) + (o.duration ?? Duration.zero),
        requestId: o.requestId ?? requestId,
        resolvedModel: o.resolvedModel ?? resolvedModel,
        costUsd: _sumDouble(costUsd, o.costUsd),
      );

  static int? _sumInt(int? a, int? b) =>
      (a == null && b == null) ? null : (a ?? 0) + (b ?? 0);
  static double? _sumDouble(double? a, double? b) =>
      (a == null && b == null) ? null : (a ?? 0) + (b ?? 0);
}

class AiCommitMessageData {
  final String providerId;
  final String modelId;
  final String message;
  final String scopeLabel;
  final int promptCharacters;
  final int diffCharacters;
  final AiUsage usage;

  const AiCommitMessageData({
    required this.providerId,
    required this.modelId,
    required this.message,
    required this.scopeLabel,
    required this.promptCharacters,
    required this.diffCharacters,
    this.usage = AiUsage.empty,
  });

  // Single source of truth is [usage]; these delegate so a reader can never
  // see a count that diverges from it.
  int get inputTokens => usage.inputTokens;
  int get outputTokens => usage.outputTokens;
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
  final AiUsage usage;

  const AiPatchData({
    required this.providerId,
    required this.modelId,
    required this.patch,
    required this.promptCharacters,
    required this.patchCharacters,
    this.usage = AiUsage.empty,
  });

  int get inputTokens => usage.inputTokens;
  int get outputTokens => usage.outputTokens;
}

/// Lightweight, engine-free projection of a finding's 5-axis claim
/// grounding (see review_logos.dart). Carries only primitives so this
/// DTO file stays free of engine dependencies; the UI rebuilds a
/// ClaimShape from these fields when recording an outcome.
class ClaimGroundingData {
  final double grounding;
  final double verifiability;
  final double reach;
  final double coherence;
  final int symbolCount;
  final int textLength;
  final double composite;
  final double ratchetPrior;

  const ClaimGroundingData({
    required this.grounding,
    required this.verifiability,
    required this.reach,
    required this.coherence,
    required this.symbolCount,
    required this.textLength,
    required this.composite,
    required this.ratchetPrior,
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

  /// Spectral grounding of this finding, attached after the review pass
  /// scores it against the diff. Null when no engine was available (or
  /// after a round-trip through persistence — it is deliberately NOT
  /// serialised: a grounding score is only meaningful against the engine
  /// state that produced it, and a stale score reloaded from disk would
  /// mislead the claim-outcome ratchet. The intended consequence is that the
  /// Confirm/Dismiss vote affordance (which feeds the ratchet) lives only in
  /// the session the review ran — a re-opened/persisted review shows none.
  final ClaimGroundingData? grounding;

  const AiCommitReviewFindingData({
    required this.id,
    required this.severity,
    required this.title,
    required this.evidence,
    required this.whyItMatters,
    this.filePath,
    this.hunkLabel,
    required this.origin,
    this.grounding,
  });

  /// Return a copy with [grounding] attached.
  AiCommitReviewFindingData withGrounding(ClaimGroundingData g) =>
      AiCommitReviewFindingData(
        id: id,
        severity: severity,
        title: title,
        evidence: evidence,
        whyItMatters: whyItMatters,
        filePath: filePath,
        hunkLabel: hunkLabel,
        origin: origin,
        grounding: g,
      );
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
  final AiUsage usage;
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
    this.usage = AiUsage.empty,
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

  // Single source of truth is [usage]; these delegate so a reader can never
  // see a count that diverges from it.
  int get inputTokens => usage.inputTokens;
  int get outputTokens => usage.outputTokens;
}

class DebugEvidenceSource {
  final String path;
  final double score;
  final List<String> grounding;
  const DebugEvidenceSource({
    required this.path,
    required this.score,
    this.grounding = const [],
  });
}

class AiDebugHypothesis {
  final String statement;
  final String brokenInvariant;
  final List<String> evidenceFor;
  final List<String> evidenceAgainst;
  final double confidence;
  final String falsifier;
  final List<String> pressureQuestions;
  final List<DebugEvidenceSource> sources;

  const AiDebugHypothesis({
    required this.statement,
    this.brokenInvariant = '',
    this.evidenceFor = const [],
    this.evidenceAgainst = const [],
    required this.confidence,
    this.falsifier = '',
    this.pressureQuestions = const [],
    this.sources = const [],
  });
}

class DebugRound {
  final int roundNumber;
  final String userInput;
  final List<AiDebugHypothesis> hypotheses;
  final List<String> filesExamined;
  final DateTime timestamp;

  const DebugRound({
    required this.roundNumber,
    required this.userInput,
    required this.hypotheses,
    this.filesExamined = const [],
    required this.timestamp,
  });
}

class AiDebugData {
  final String providerId;
  final String modelId;
  final String symptom;
  final int round;
  final List<AiDebugHypothesis> hypotheses;
  final int promptCharacters;
  final AiUsage usage;
  final int candidatesConsidered;
  final int filesRead;
  final List<String> parseWarnings;
  final List<DebugRound> roundHistory;

  const AiDebugData({
    required this.providerId,
    required this.modelId,
    required this.symptom,
    required this.round,
    required this.hypotheses,
    this.promptCharacters = 0,
    this.usage = AiUsage.empty,
    this.candidatesConsidered = 0,
    this.filesRead = 0,
    this.parseWarnings = const [],
    this.roundHistory = const [],
  });

  int get inputTokens => usage.inputTokens;
  int get outputTokens => usage.outputTokens;
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
        themeId: (j['theme_id'] ?? j['themeId']) as String? ?? 'aether',
        keybindingProfile:
            (j['keybinding_profile'] ?? j['keybindingProfile']) as String? ??
                'classic',
        sidebarWidthPx:
            (j['sidebar_width_px'] ?? j['sidebarWidthPx']) as int? ?? 240,
        aiReadOnlyDefault:
            (j['ai_read_only_default'] ?? j['aiReadOnlyDefault']) as bool? ??
                true,
      );
}
