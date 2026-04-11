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
