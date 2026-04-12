// ── DTOs — mirrors src/lib/backend/dtos.ts exactly ──────────────────────────

class RepositoryStatusFile {
  final String path;
  final String staged;
  final String unstaged;
  const RepositoryStatusFile(
      {required this.path, required this.staged, required this.unstaged});
  factory RepositoryStatusFile.fromJson(Map<String, dynamic> j) =>
      RepositoryStatusFile(
          path: j['path'], staged: j['staged'], unstaged: j['unstaged']);
}

class RepositoryStatus {
  final String branch;
  final String? upstream;
  final int ahead;
  final int behind;
  final List<RepositoryStatusFile> files;
  const RepositoryStatus(
      {required this.branch,
      this.upstream,
      required this.ahead,
      required this.behind,
      required this.files});
  factory RepositoryStatus.fromJson(Map<String, dynamic> j) => RepositoryStatus(
        branch: j['branch'] ?? '',
        upstream: j['upstream'],
        ahead: j['ahead'] ?? 0,
        behind: j['behind'] ?? 0,
        files: (j['files'] as List? ?? [])
            .map((f) => RepositoryStatusFile.fromJson(f))
            .toList(),
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
  const CommitFileStatData(
      {required this.path, required this.additions, required this.deletions});
  factory CommitFileStatData.fromJson(Map<String, dynamic> j) =>
      CommitFileStatData(
          path: j['path'] ?? '',
          additions: j['additions'] ?? 0,
          deletions: j['deletions'] ?? 0);
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
  const BranchInfo(
      {required this.name,
      required this.current,
      this.upstream,
      required this.ahead,
      required this.behind});
  factory BranchInfo.fromJson(Map<String, dynamic> j) => BranchInfo(
        name: j['name'] ?? '',
        current: j['current'] ?? false,
        upstream: j['upstream'],
        ahead: j['ahead'] ?? 0,
        behind: j['behind'] ?? 0,
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

  const RepositoryXrayHotspotData({
    required this.kind,
    required this.path,
    required this.touchCount,
    required this.ownerCount,
    required this.lastTouchedAt,
    this.latestCommitHash,
    this.latestShortHash,
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

  const RepositoryXrayStratumData({
    required this.id,
    required this.label,
    required this.pathPrefix,
    required this.touchCount,
    required this.ownerCount,
    required this.lastTouchedAt,
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

  const AiModelOptionData({
    required this.value,
    required this.modelId,
    required this.providerId,
    required this.providerLabel,
    this.planName,
    required this.label,
    required this.description,
  });

  factory AiModelOptionData.fromJson(Map<String, dynamic> j) =>
      AiModelOptionData(
        value: j['value'] ?? '',
        modelId: j['model_id'] ?? j['modelId'] ?? '',
        providerId: j['provider_id'] ?? j['providerId'] ?? '',
        providerLabel: j['provider_label'] ?? j['providerLabel'] ?? '',
        planName: j['plan_name'] ?? j['planName'],
        label: j['label'] ?? '',
        description: j['description'] ?? '',
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

class AiCommitMessageData {
  final String providerId;
  final String modelId;
  final String message;
  final String scopeLabel;
  final bool usedCondensedDiff;
  final int promptCharacters;
  final int diffCharacters;

  const AiCommitMessageData({
    required this.providerId,
    required this.modelId,
    required this.message,
    required this.scopeLabel,
    required this.usedCondensedDiff,
    required this.promptCharacters,
    required this.diffCharacters,
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
  final bool usedCondensedDiff;
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
    required this.usedCondensedDiff,
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
