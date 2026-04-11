import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'ai_audit_store.dart';
import '../diagnostics/diagnostics_state.dart';
import 'dtos.dart';
import 'git.dart';

const _providerSpecs = <_ProviderSpec>[
  _ProviderSpec(id: 'codex', binary: 'codex', kind: _ProviderKind.codex),
  _ProviderSpec(id: 'claude', binary: 'claude', kind: _ProviderKind.claude),
  _ProviderSpec(id: 'gemini', binary: 'gemini', kind: _ProviderKind.gemini),
  _ProviderSpec(
    id: 'opencode',
    binary: 'opencode',
    kind: _ProviderKind.openCode,
  ),
];

const _defaultModelCategories = <_ModelCategoryTemplate>[
  _ModelCategoryTemplate(
    id: 'quality',
    label: 'Quality model',
    description: 'Higher quality reasoning-first models.',
    hintTokens: [
      'opus',
      'sonnet',
      'pro',
      'gpt-5',
      'o1',
      'o3',
      'reason',
      'max',
    ],
  ),
  _ModelCategoryTemplate(
    id: 'fast',
    label: 'Fast model',
    description: 'Lower-latency throughput-first models.',
    hintTokens: [
      'mini',
      'flash',
      'haiku',
      'spark',
      'nano',
      'free',
      'instant',
      'auto',
    ],
  ),
];

const _providerResolutionCacheTtl = Duration(seconds: 60);
const _providerAvailabilityCacheTtl = Duration(minutes: 2);
const _providerModelDiscoveryCacheTtl = Duration(minutes: 30);
const _binaryHealthCheckTimeout = Duration(milliseconds: 1200);
const _openCodeBinaryHealthCheckTimeout = Duration(seconds: 5);
const _windowsScriptHealthCheckTimeout = Duration(seconds: 5);
const _providerRuntimeTimeout = Duration(seconds: 180);
const _gitCommandTimeout = Duration(seconds: 30);
const _modelDiscoveryTimeout = Duration(seconds: 8);
const _openCodeVerboseDiscoveryTimeout = Duration(seconds: 15);
const _claudeModelDiscoveryTimeout = Duration(seconds: 12);
const _maxFullDiffChars = 140000;
const _maxCondensedDiffChars = 110000;
const _maxPromptChars = 180000;

final Map<String, _TimedValue<_ProviderResolution?>> _providerResolutionCache =
    {};
final Map<String, _TimedValue<_ProviderAvailability>>
    _providerAvailabilityCache = {};
final Map<String, _TimedValue<_ProviderModelDiscovery?>>
    _providerModelDiscoveryCache = {};

const _modelValueSeparator = ':';
const _diffStatWidth = 140;
const _diffTimeoutSeconds = 50;
const _maxChangedLineLength = 120;
const _previewMaxLength = 800;
const _truncationSuffix = '...';
const _findingOriginDraft = 'draft';
const _findingOriginVerification = 'verification';
const _findingIdPrefixDraft = 'F';
const _findingIdPrefixVerification = 'V';
const _unknownPlaceholder = '-';

final _modelAssignmentRegex = RegExp(r'^model\s*=');
final _migrationEntryRegex = RegExp(r'^"([^"]+)"\s*=\s*"([^"]+)"');
final _backtickContentRegex = RegExp(r'`([^`]+)`');
final _findingTagRegex = RegExp(
  r'<finding\b([^>]*)>([\s\S]*?)</finding>',
  caseSensitive: false,
);
final _xmlTagRegex = RegExp(r'<(\w+)>([\s\S]*?)</\1>', caseSensitive: false);
final _xmlAttrRegex = RegExp(r'(\w+)="([^"]*)"');

class _ModelParse {
  final _ProviderSpec provider;
  final String modelId;
  _ModelParse({required this.provider, required this.modelId});
}

GitResult<_ModelParse> _parseModelValue(String modelValue) {
  final trimmed = modelValue.trim();
  if (trimmed.isEmpty || !trimmed.contains(_modelValueSeparator)) {
    return GitResult.err('Select a valid AI model.');
  }
  final sep = trimmed.indexOf(_modelValueSeparator);
  final providerId = trimmed.substring(0, sep).trim();
  final modelId = trimmed.substring(sep + 1).trim();
  final provider = _providerSpecs.cast<_ProviderSpec?>().firstWhere(
        (p) => p!.id == providerId,
        orElse: () => null,
      );
  if (provider == null) {
    return GitResult.err('Unknown AI provider: $providerId');
  }
  if (modelId.isEmpty) {
    return GitResult.err('Selected model is missing a model id.');
  }
  return GitResult.ok(_ModelParse(provider: provider, modelId: modelId));
}

Future<GitResult<AiProviderListData>> listAiProviders({
  bool forceRefresh = false,
}) async {
  try {
    final providers = await Future.wait(
      _providerSpecs.map(
        (provider) async {
          final availability = await _inspectProviderCached(
            provider,
            forceRefresh: forceRefresh,
          );
          return AiProviderStatus(
            id: provider.id,
            available: availability.ready,
            binary: provider.binary,
            planName: availability.auth.planName,
            resolvedBinary: availability.resolution?.command,
            detectionSource: availability.resolution?.source,
            healthCheck: _formatProviderHealth(availability),
          );
        },
      ),
    );
    providers.sort((left, right) => left.id.compareTo(right.id));
    return GitResult.ok(AiProviderListData(providers: providers));
  } catch (error) {
    return GitResult.err('Provider detection failed: $error');
  }
}

Future<GitResult<AiModelOptionListData>> listAiModelOptions({
  bool forceRefresh = false,
}) async {
  try {
    final providerResults = await Future.wait(
      _providerSpecs.map((provider) async {
        final availability = await _inspectProviderCached(
          provider,
          forceRefresh: forceRefresh,
        );
        if (!availability.ready) {
          return null;
        }
        final discovery = await _discoverProviderModelsCached(
          provider,
          availability.resolution,
          forceRefresh: forceRefresh,
        );
        if (discovery == null || discovery.models.isEmpty) {
          return null;
        }
        return _ProviderModelCollection(
          providerId: provider.id,
          kind: provider.kind,
          planName: availability.auth.planName,
          models: discovery.models,
          modelDetails: discovery.modelDetails,
        );
      }),
    );
    final readyProviders =
        providerResults.whereType<_ProviderModelCollection>().toList();

    final modelDetailsByKey = <String, String>{};
    final directProviderModelKeys = <String>{};
    for (final provider in readyProviders) {
      modelDetailsByKey.addAll(provider.modelDetails);
      if (provider.kind == _ProviderKind.openCode) {
        continue;
      }
      for (final modelId in provider.models) {
        directProviderModelKeys.add(_normalizeModelKey(modelId));
      }
    }

    final categories = <AiModelCategoryData>[];
    for (final category in _defaultModelCategories) {
      final models = <AiModelOptionData>[];
      final seen = <String>{};

      for (final provider in readyProviders) {
        final providerModels = provider.kind == _ProviderKind.openCode
            ? provider.models
                .where(
                  (modelId) => !directProviderModelKeys
                      .contains(_normalizeModelKey(modelId)),
                )
                .toList()
            : provider.models;

        for (final modelId
            in _rankModelsForCategory(providerModels, category.hintTokens)) {
          final key = _normalizeModelKey(modelId);
          if (!seen.add(key)) {
            continue;
          }

          models.add(
            AiModelOptionData(
              value: '${provider.providerId}:$modelId',
              modelId: modelId,
              providerId: provider.providerId,
              providerLabel: _humanizeLabel(provider.providerId),
              planName: provider.planName,
              label: modelId,
              description: _buildModelDescription(
                providerId: provider.providerId,
                planName: provider.planName,
                detail: provider.modelDetails[key] ?? modelDetailsByKey[key],
              ),
            ),
          );
        }
      }

      categories.add(
        AiModelCategoryData(
          id: category.id,
          label: category.label,
          description: category.description,
          models: models,
        ),
      );
    }

    return GitResult.ok(AiModelOptionListData(categories: categories));
  } catch (error) {
    return GitResult.err('Model discovery failed: $error');
  }
}

Future<GitResult<AiCommitMessageData>> generateCommitMessage({
  required String repositoryPath,
  required String modelValue,
  required String modelCategoryLabel,
  required String scopeLabel,
  required bool includeStaged,
  required bool includeUnstaged,
  List<String> scopedPaths = const [],
  String customPrompt = '',
  String existingMessage = '',
  bool readOnly = true,
}) async {
  try {
    if (repositoryPath.trim().isEmpty) {
      return GitResult.err('Repository path is required.');
    }
    if (!includeStaged && !includeUnstaged) {
      return GitResult.err('No diff scope is available for generation.');
    }

    final modelParse = _parseModelValue(modelValue);
    if (!modelParse.ok) {
      return GitResult.err(modelParse.error!);
    }
    final provider = modelParse.data!.provider;
    final modelId = modelParse.data!.modelId;

    final availability = await _inspectProviderCached(provider);
    if (!availability.ready || availability.resolution == null) {
      return GitResult.err(
        'Provider ${provider.id} is not ready. ${_formatProviderHealth(availability)}',
      );
    }

    final diffContext = await _collectCommitMessageContext(
      repositoryPath: repositoryPath,
      scopeLabel: scopeLabel,
      scopedPaths: scopedPaths,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
    );

    if (!diffContext.ok) {
      return GitResult.err(diffContext.error!);
    }

    final bundle = diffContext.data!;
    final prompt = _buildCommitMessagePrompt(
      branchName: bundle.branchName,
      modelCategoryLabel: modelCategoryLabel,
      scopeLabel: scopeLabel,
      customPrompt: customPrompt,
      existingMessage: existingMessage,
      totalCommits: bundle.totalCommits,
      recentLog: bundle.recentLog,
      authorName: bundle.authorName,
      lastCommitAge: bundle.lastCommitAge,
      projectAge: bundle.projectAge,
      uniqueContributors: bundle.uniqueContributors,
      statusSummary: bundle.statusSummary,
      statSummary: bundle.statSummary,
      diffSummary: bundle.diffBundle.promptBody,
    );

    final attempts = _buildProviderAttempts(provider.kind, modelId, readOnly: readOnly, resolvedCommand: availability.resolution!.command);
    String? providerOutput;
    String? lastError;
    for (final attempt in attempts) {
      final effectiveArgs = attempt.useStdinForPrompt
          ? attempt.args
          : [...attempt.args, prompt];
      final effectiveStdin = attempt.useStdinForPrompt ? prompt : null;
      final result = await _runObservedProcess(
        commandLabel: 'ai.${provider.id}.${attempt.name}',
        scope: 'ai',
        command: availability.resolution!.command,
        args: effectiveArgs,
        timeout: _providerRuntimeTimeout,
        workingDirectory: repositoryPath,
        stdinPayload: effectiveStdin,
        environment: _providerEnvironment(provider.kind),
      );

      if (result == null) {
        lastError = 'Provider command timed out.';
        continue;
      }

      final formatted = _formatProviderOutput(
        attempt.outputMode,
        result.stdout,
        result.stderr,
      );
      if (result.exitCode == 0 &&
          formatted != null &&
          formatted.trim().isNotEmpty &&
          !_looksLikeProviderError(provider.kind, formatted)) {
        providerOutput = formatted;
        break;
      }

      lastError = formatted?.trim().isNotEmpty == true
          ? _normalizeProviderError(provider.kind, formatted!)
          : result.stderr.trim().isNotEmpty
              ? _normalizeProviderError(provider.kind, result.stderr.trim())
              : 'Provider exited with code ${result.exitCode}.';
    }

    if (providerOutput == null) {
      return GitResult.err(
          lastError ?? 'Provider did not return a commit message.');
    }

    final message = _normalizeCommitMessage(providerOutput);
    if (message.isEmpty) {
      return GitResult.err('Provider returned an empty commit message.');
    }

    return GitResult.ok(
      AiCommitMessageData(
        providerId: provider.id,
        modelId: modelId,
        message: message,
        scopeLabel: scopeLabel,
        usedCondensedDiff: bundle.diffBundle.usedCondensedDiff,
        promptCharacters: prompt.length,
        diffCharacters: bundle.diffBundle.originalDiffCharacters,
      ),
    );
  } catch (error) {
    return GitResult.err('Commit message generation failed: $error');
  }
}

Future<GitResult<AiCommitReviewData>> reviewCommit({
  required String repositoryPath,
  required String modelValue,
  required String modelCategoryLabel,
  required String scopeLabel,
  required bool includeStaged,
  required bool includeUnstaged,
  List<String> scopedPaths = const [],
  String customPrompt = '',
  required int guardrailStage,
  bool doubleCheckEnabled = false,
  bool readOnly = true,
}) async {
  try {
    if (repositoryPath.trim().isEmpty) {
      return GitResult.err('Repository path is required.');
    }
    if (!includeStaged && !includeUnstaged) {
      return GitResult.err('No diff scope is available for review.');
    }

    final modelParse = _parseModelValue(modelValue);
    if (!modelParse.ok) {
      return GitResult.err(modelParse.error!);
    }
    final provider = modelParse.data!.provider;
    final modelId = modelParse.data!.modelId;

    final availability = await _inspectProviderCached(provider);
    if (!availability.ready || availability.resolution == null) {
      return GitResult.err(
        'Provider ${provider.id} is not ready. ${_formatProviderHealth(availability)}',
      );
    }

    final diffContext = await _collectCommitMessageContext(
      repositoryPath: repositoryPath,
      scopeLabel: scopeLabel,
      scopedPaths: scopedPaths,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
    );
    if (!diffContext.ok) {
      return GitResult.err(diffContext.error!);
    }

    final bundle = diffContext.data!;
    final profile = _guardrailProfileForStage(guardrailStage);
    final draftSpec = _ReviewPromptSpec(
      branchName: bundle.branchName,
      modelCategoryLabel: modelCategoryLabel,
      scopeLabel: scopeLabel,
      customPrompt: customPrompt,
      statusSummary: bundle.statusSummary,
      statSummary: bundle.statSummary,
      diffSummary: bundle.diffBundle.promptBody,
      passMode: _ReviewPassMode.draft,
    );
    final draftPrompt = _buildCommitReviewPrompt(
      spec: draftSpec,
      profile: profile,
    );

    final providerOutput = await _runProviderPrompt(
      provider: provider,
      resolution: availability.resolution!,
      modelId: modelId,
      prompt: draftPrompt,
      repositoryPath: repositoryPath,
      readOnly: readOnly,
    );
    await _recordReviewAudit(
      event: 'review_commit_draft',
      providerId: provider.id,
      repositoryPath: repositoryPath,
      scopeLabel: scopeLabel,
      promptPreview: draftPrompt,
      outputPreview: providerOutput.outputPreview,
      ok: providerOutput.ok,
      errorCode: providerOutput.ok ? null : providerOutput.error,
    );
    if (!providerOutput.ok || providerOutput.output == null) {
      return GitResult.err(providerOutput.error ?? 'Review did not return.');
    }

    final draftReview = _parseDraftReview(providerOutput.output!);
    if (draftReview == null) {
      return GitResult.err(
        'Review output could not be parsed. Try again or use a stronger model.',
      );
    }

    if (!doubleCheckEnabled) {
      return GitResult.ok(
        AiCommitReviewData(
          providerId: provider.id,
          modelId: modelId,
          scopeLabel: scopeLabel,
          usedCondensedDiff: bundle.diffBundle.usedCondensedDiff,
          promptCharacters: draftPrompt.length,
          diffCharacters: bundle.diffBundle.originalDiffCharacters,
          verdict: draftReview.verdict,
          score: draftReview.score,
          summary: draftReview.summary,
          reasoningReport: draftReview.reasoningReport,
          findings: draftReview.findings,
          twoStepEnabled: false,
          hasVerificationTrace: false,
        ),
      );
    }

    final verifySpec = _ReviewPromptSpec(
      branchName: bundle.branchName,
      modelCategoryLabel: modelCategoryLabel,
      scopeLabel: scopeLabel,
      customPrompt: customPrompt,
      statusSummary: bundle.statusSummary,
      statSummary: bundle.statSummary,
      diffSummary: bundle.diffBundle.promptBody,
      passMode: _ReviewPassMode.verify,
      priorReview: _serializeDraftReview(draftReview),
    );
    final verifyPrompt = _buildCommitReviewPrompt(
      spec: verifySpec,
      profile: profile,
    );
    final verifyOutput = await _runProviderPrompt(
      provider: provider,
      resolution: availability.resolution!,
      modelId: modelId,
      prompt: verifyPrompt,
      repositoryPath: repositoryPath,
      readOnly: readOnly,
    );
    await _recordReviewAudit(
      event: 'review_commit_verify',
      providerId: provider.id,
      repositoryPath: repositoryPath,
      scopeLabel: scopeLabel,
      promptPreview: verifyPrompt,
      outputPreview: verifyOutput.outputPreview,
      ok: verifyOutput.ok,
      errorCode: verifyOutput.ok ? null : verifyOutput.error,
    );

    if (!verifyOutput.ok || verifyOutput.output == null) {
      final fallback = AiCommitReviewData(
        providerId: provider.id,
        modelId: modelId,
        scopeLabel: scopeLabel,
        usedCondensedDiff: bundle.diffBundle.usedCondensedDiff,
        promptCharacters: draftPrompt.length + verifyPrompt.length,
        diffCharacters: bundle.diffBundle.originalDiffCharacters,
        verdict: draftReview.verdict,
        score: draftReview.score,
        summary: draftReview.summary,
        reasoningReport: draftReview.reasoningReport,
        findings: draftReview.findings,
        twoStepEnabled: true,
        hasVerificationTrace: false,
        verificationFailed: true,
        verificationError:
            verifyOutput.error ?? 'Verification did not return a result.',
        draftFindings: draftReview.findings,
        draftSummary: draftReview.summary,
        draftReasoningReport: draftReview.reasoningReport,
      );
      return GitResult.ok(fallback);
    }

    final verification = _parseVerificationReview(verifyOutput.output!);
    if (verification == null) {
      return GitResult.ok(
        AiCommitReviewData(
          providerId: provider.id,
          modelId: modelId,
          scopeLabel: scopeLabel,
          usedCondensedDiff: bundle.diffBundle.usedCondensedDiff,
          promptCharacters: draftPrompt.length + verifyPrompt.length,
          diffCharacters: bundle.diffBundle.originalDiffCharacters,
          verdict: draftReview.verdict,
          score: draftReview.score,
          summary: draftReview.summary,
          reasoningReport: draftReview.reasoningReport,
          findings: draftReview.findings,
          twoStepEnabled: true,
          hasVerificationTrace: false,
          verificationFailed: true,
          verificationError:
              'Verification output could not be parsed. Showing draft review.',
          draftFindings: draftReview.findings,
          draftSummary: draftReview.summary,
          draftReasoningReport: draftReview.reasoningReport,
        ),
      );
    }

    final merged = _mergeVerifiedReview(
      draft: draftReview,
      verification: verification,
    );
    await _recordReviewAudit(
      event: 'review_commit_final',
      providerId: provider.id,
      repositoryPath: repositoryPath,
      scopeLabel: scopeLabel,
      promptPreview: '',
      outputPreview: _serializeFinalReview(merged),
      ok: true,
    );

    return GitResult.ok(
      AiCommitReviewData(
        providerId: provider.id,
        modelId: modelId,
        scopeLabel: scopeLabel,
        usedCondensedDiff: bundle.diffBundle.usedCondensedDiff,
        promptCharacters: draftPrompt.length + verifyPrompt.length,
        diffCharacters: bundle.diffBundle.originalDiffCharacters,
        verdict: merged.verdict,
        score: merged.score,
        summary: merged.summary,
        reasoningReport: merged.reasoningReport,
        findings: merged.findings,
        twoStepEnabled: true,
        hasVerificationTrace: true,
        draftFindings: draftReview.findings,
        draftSummary: draftReview.summary,
        draftReasoningReport: draftReview.reasoningReport,
        verificationNotes: verification.verificationNotes,
      ),
    );
  } catch (error) {
    return GitResult.err('Commit review failed: $error');
  }
}

Future<_ProviderAvailability> _inspectProviderCached(
  _ProviderSpec provider, {
  bool forceRefresh = false,
}) async {
  final cacheKey = provider.id.toLowerCase();
  final cached = _providerAvailabilityCache[cacheKey];
  if (!forceRefresh &&
      cached != null &&
      DateTime.now().difference(cached.checkedAt) <
          _providerAvailabilityCacheTtl) {
    return cached.value;
  }

  final availability = await _inspectProvider(provider);
  _providerAvailabilityCache[cacheKey] = _TimedValue(
    checkedAt: DateTime.now(),
    value: availability,
  );
  return availability;
}

Future<_ProviderAvailability> _inspectProvider(_ProviderSpec provider) async {
  _ProviderResolution? resolution = await _resolveProviderCommand(provider.binary);
  // Gemini: if the direct binary isn't installed, fall back to npx.
  if (resolution == null && provider.kind == _ProviderKind.gemini) {
    resolution = await _resolveProviderCommand('npx');
  }
  final auth = _providerAuthStatus(provider.kind);
  return _ProviderAvailability(
    ready: resolution != null && auth.ok,
    resolution: resolution,
    auth: auth,
  );
}

String _formatProviderHealth(_ProviderAvailability availability) {
  final binaryHealth =
      availability.resolution?.healthCheck ?? 'binary unavailable';
  return '$binaryHealth; auth=${availability.auth.detail}';
}

Future<_ProviderModelDiscovery?> _discoverProviderModelsCached(
  _ProviderSpec provider,
  _ProviderResolution? resolution, {
  bool forceRefresh = false,
}) async {
  final cacheKey = provider.id.toLowerCase();
  final cached = _providerModelDiscoveryCache[cacheKey];
  if (!forceRefresh &&
      cached != null &&
      DateTime.now().difference(cached.checkedAt) <
          _providerModelDiscoveryCacheTtl) {
    return cached.value;
  }

  final discovery = await _discoverProviderModels(provider, resolution);
  _providerModelDiscoveryCache[cacheKey] = _TimedValue(
    checkedAt: DateTime.now(),
    value: discovery,
  );
  return discovery;
}

Future<_ProviderModelDiscovery?> _discoverProviderModels(
  _ProviderSpec provider,
  _ProviderResolution? resolution,
) async {
  switch (provider.kind) {
    case _ProviderKind.codex:
      return _discoverCodexModels(resolution);
    case _ProviderKind.claude:
      return _discoverClaudeModels(resolution);
    case _ProviderKind.gemini:
      return _discoverGeminiModels(resolution);
    case _ProviderKind.openCode:
      return _discoverOpenCodeModels(resolution);
  }
}

_ProviderModelDiscovery? _discoverCodexModels(
  _ProviderResolution? resolution,
) {
  final models = <String>{};
  final details = <String, String>{};

  for (final model in _discoverCodexConfigModels()) {
    models.add(model);
  }

  if (models.isEmpty) {
    return null;
  }
  return _ProviderModelDiscovery(
    models: models.toList(),
    modelDetails: details,
  );
}

List<String> _discoverCodexConfigModels() {
  final models = <String>{};
  // Project-level config takes precedence over user-level.
  // Walk up from cwd to find the nearest .codex/config.toml.
  var dir = Directory.current;
  while (true) {
    try {
      final payload =
          File(p.join(dir.path, '.codex', 'config.toml')).readAsStringSync();
      _parseCodexToml(payload, models);
      break; // Use the closest project config found, then stop.
    } catch (_) {}
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // User-level / CODEX_HOME config.
  try {
    _parseCodexToml(File(_codexConfigPath()).readAsStringSync(), models);
  } catch (_) {}
  return models.where((value) => value.trim().isNotEmpty).toList();
}

void _parseCodexToml(String payload, Set<String> models) {
  var inModelMigrations = false;
  for (final line in payload.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('[')) {
      inModelMigrations = trimmed == '[notice.model_migrations]';
      continue;
    }
    // Top-level `model = "..."` key only — not model_reasoning_effort etc.
    if (!inModelMigrations && _modelAssignmentRegex.hasMatch(trimmed)) {
      final separator = trimmed.indexOf('=');
      if (separator != -1) {
        final value = trimmed
            .substring(separator + 1)
            .trim()
            .replaceAll('"', '')
            .replaceAll("'", '');
        if (value.isNotEmpty) models.add(value);
      }
    }
    if (inModelMigrations && trimmed.contains('=')) {
      final migrationMatch = _migrationEntryRegex.firstMatch(trimmed);
      if (migrationMatch != null) {
        models.add(migrationMatch.group(1)!.trim());
        models.add(migrationMatch.group(2)!.trim());
      }
    }
  }
}


Future<_ProviderModelDiscovery?> _discoverClaudeModels(
  _ProviderResolution? resolution,
) async {
  // `claude models` is not a valid subcommand — the Claude Code CLI interprets
  // it as a chat message. Use stable well-known aliases instead.
  const stableAliases = ['opus', 'sonnet', 'haiku'];
  final models = <String>{...stableAliases};

  final configured = _discoverClaudeConfiguredModel();
  if (configured != null) {
    models.add(configured);
  }
  return _ProviderModelDiscovery(
    models: models.toList(),
    modelDetails: const {},
  );
}

String? _discoverClaudeConfiguredModel() {
  final homeDir = _userHomeDir();
  if (homeDir == null) {
    return null;
  }
  final value = _readJsonFile(p.join(homeDir, '.claude', 'settings.json'));
  return _findModelValueInJson(value);
}

String? _findModelValueInJson(dynamic value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      final nestedValue = entry.value;
      if (key is String && key.toLowerCase().contains('model')) {
        if (nestedValue is String && nestedValue.trim().isNotEmpty) {
          return nestedValue.trim();
        }
      }
      final nested = _findModelValueInJson(nestedValue);
      if (nested != null) {
        return nested;
      }
    }
  }
  if (value is List) {
    for (final item in value) {
      final nested = _findModelValueInJson(item);
      if (nested != null) {
        return nested;
      }
    }
  }
  return null;
}

_ProviderModelDiscovery? _discoverGeminiModels(
  _ProviderResolution? resolution,
) {
  // Gemini CLI accepts stable shorthand aliases (--model auto/pro/flash/flash-lite).
  // Surface these plus whatever the user has explicitly configured.
  final models = <String>{'gemini auto', 'gemini pro', 'gemini flash', 'gemini flash-lite'};

  final configured = _discoverGeminiConfiguredModel();
  if (configured != null) {
    models.add(configured);
  }

  return _ProviderModelDiscovery(
    models: models.toList(),
    modelDetails: const {},
  );
}

String? _discoverGeminiConfiguredModel() {
  // Env var is highest priority (overrides all config files).
  final envModel = Platform.environment['GEMINI_MODEL'];
  if (envModel != null && envModel.trim().isNotEmpty) {
    return envModel.trim();
  }

  // Project-level settings (.gemini/settings.json in cwd).
  final projectModel = _extractGeminiModelFromJson(
    _readJsonFile(p.join(Directory.current.path, '.gemini', 'settings.json')),
  );
  if (projectModel != null) return projectModel;

  // User-level settings (~/.gemini/settings.json).
  final homeDir = _userHomeDir();
  if (homeDir != null) {
    final userModel = _extractGeminiModelFromJson(
      _readJsonFile(p.join(homeDir, '.gemini', 'settings.json')),
    );
    if (userModel != null) return userModel;
  }

  return null;
}

String? _extractGeminiModelFromJson(dynamic value) {
  if (value is! Map) return null;
  // Structured format: {"model": {"name": "gemini-2.5-pro"}}
  final modelField = value['model'];
  if (modelField is Map) {
    final name = modelField['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
  }
  // Flat format: {"model": "gemini-2.5-pro"}
  if (modelField is String && modelField.trim().isNotEmpty) {
    return modelField.trim();
  }
  return null;
}


Future<_ProviderModelDiscovery?> _discoverOpenCodeModels(
  _ProviderResolution? resolution,
) async {
  final command = resolution?.command ?? 'opencode';
  final verbose = await _discoverOpenCodeVerboseModels(command);
  if (verbose != null) {
    return verbose;
  }

  final result = await _runCommandWithTimeout(
    command,
    const ['models'],
    _modelDiscoveryTimeout,
  );
  if (result == null || result.exitCode != 0) {
    return null;
  }

  final models = <String>[];
  for (final line in result.stdout.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.contains('/')) {
      continue;
    }
    if (!models.contains(trimmed)) {
      models.add(trimmed);
    }
  }

  if (models.isEmpty) {
    return null;
  }
  return _ProviderModelDiscovery(models: models, modelDetails: const {});
}

Future<_ProviderModelDiscovery?> _discoverOpenCodeVerboseModels(
  String command,
) async {
  final result = await _runCommandWithTimeout(
    command,
    const ['models', '--verbose'],
    _openCodeVerboseDiscoveryTimeout,
  );
  if (result == null || result.exitCode != 0) {
    return null;
  }

  final lines = result.stdout.split('\n');
  final models = <String>[];
  final modelDetails = <String, String>{};
  final seen = <String>{};
  var index = 0;
  while (index < lines.length) {
    final modelId = lines[index].trim();
    index += 1;
    if (modelId.isEmpty || modelId.startsWith('{') || !modelId.contains('/')) {
      continue;
    }

    final modelKey = _normalizeModelKey(modelId);
    if (seen.add(modelKey)) {
      models.add(modelId);
    }

    while (index < lines.length && lines[index].trim().isEmpty) {
      index += 1;
    }
    if (index >= lines.length || !lines[index].trimLeft().startsWith('{')) {
      continue;
    }

    final buffer = StringBuffer();
    while (index < lines.length) {
      buffer.writeln(lines[index]);
      index += 1;
      try {
        final decoded = jsonDecode(buffer.toString());
        final detail = _extractOpenCodeModelDetail(decoded);
        if (detail != null) {
          modelDetails[modelKey] = detail;
        }
        break;
      } catch (_) {}
    }
  }

  if (models.isEmpty) {
    return null;
  }
  return _ProviderModelDiscovery(models: models, modelDetails: modelDetails);
}

String? _extractOpenCodeModelDetail(dynamic value) {
  if (value is! Map) {
    return null;
  }

  final details = <String>[];
  final limit = value['limit'];
  if (limit is Map) {
    final context = limit['context'];
    final input = limit['input'];
    final output = limit['output'];
    if (context is num) {
      details.add('ctx ${_formatTokenLimit(context.toInt())}');
    }
    if (input is num) {
      details.add('in ${_formatTokenLimit(input.toInt())}');
    }
    if (output is num) {
      details.add('out ${_formatTokenLimit(output.toInt())}');
    }
  }

  final capabilities = value['capabilities'];
  if (capabilities is Map) {
    if (capabilities['reasoning'] == true) {
      details.add('reasoning');
    }
    if (capabilities['toolcall'] == true) {
      details.add('tools');
    }
    if (capabilities['attachment'] == true) {
      details.add('attachments');
    }
  }

  final status = value['status'];
  if (status is String && status.trim().isNotEmpty) {
    details.add(status.trim());
  }
  final releaseDate = value['release_date'];
  if (releaseDate is String && releaseDate.trim().isNotEmpty) {
    details.add(releaseDate.trim());
  }

  if (details.isEmpty) {
    return null;
  }
  return details.join(' | ');
}

_ProviderModelDiscovery _parseClaudeModelsOutput(String stdout) {
  final models = <String>[];
  final modelDetails = <String, String>{};
  final seen = <String>{};
  for (final line in stdout.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|') || trimmed.contains('---')) {
      continue;
    }
    final cells = trimmed
        .split('|')
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty)
        .toList();
    if (cells.length < 2) {
      continue;
    }
    final match = _backtickContentRegex.firstMatch(cells[1]);
    final modelId = match?.group(1)?.trim();
    if (modelId == null || modelId.isEmpty || !seen.add(modelId)) {
      continue;
    }
    models.add(modelId);
    final label = cells.first;
    if (label.isNotEmpty) {
      modelDetails[modelId] = label;
    }
  }
  return _ProviderModelDiscovery(models: models, modelDetails: modelDetails);
}


String _formatTokenLimit(int tokens) {
  if (tokens >= 1000000) {
    return '${(tokens / 1000000).toStringAsFixed(1)}m';
  }
  if (tokens >= 1000) {
    return '${(tokens / 1000).round()}k';
  }
  return tokens.toString();
}

Future<_ProviderResolution?> _resolveProviderCommand(String binary) async {
  final cacheKey = binary.trim().toLowerCase();
  final cached = _providerResolutionCache[cacheKey];
  if (cached != null &&
      DateTime.now().difference(cached.checkedAt) <
          _providerResolutionCacheTtl) {
    return cached.value;
  }

  _ProviderResolution? resolution;
  for (final candidate in _knownBinaryCandidates(binary)) {
    final healthCheck = await _probeBinaryHealth(candidate.command);
    if (healthCheck == null) {
      continue;
    }
    resolution = _ProviderResolution(
      command: candidate.command,
      source: candidate.source,
      healthCheck: healthCheck,
    );
    break;
  }

  _providerResolutionCache[cacheKey] = _TimedValue(
    checkedAt: DateTime.now(),
    value: resolution,
  );
  return resolution;
}

List<_BinaryCandidate> _knownBinaryCandidates(String binary) {
  final candidates = <_BinaryCandidate>[];
  final seen = <String>{};

  void pushCandidate(String command, String source) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      candidates.add(_BinaryCandidate(command: trimmed, source: source));
    }
  }

  if (Platform.isWindows) {
    // Prefer .cmd/.exe BEFORE the bare name. When the bare name resolves
    // first, it gets cached and _buildProcessInvocation can't apply
    // node-direct optimisations (--max-old-space-size, native binary
    // resolution) because it only triggers those for .cmd/.bat suffixes.
    for (final suffix in ['.cmd', '.exe', '.bat', '.ps1', '']) {
      pushCandidate('$binary$suffix', 'PATH');
    }
  } else {
    pushCandidate(binary, 'PATH');
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      for (final suffix in ['.cmd', '.exe', '.ps1', '']) {
        pushCandidate(p.join(appData, 'npm', '$binary$suffix'), 'APPDATA/npm');
      }
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      pushCandidate(
        p.join(localAppData, 'Programs', binary, '$binary.exe'),
        'LOCALAPPDATA/Programs',
      );
    }

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      for (final suffix in ['', '.exe']) {
        pushCandidate(
          p.join(userProfile, '.local', 'bin', '$binary$suffix'),
          'USERPROFILE/.local/bin',
        );
      }
    }
  } else {
    for (final base in const [
      '/usr/local/bin',
      '/usr/bin',
      '/opt/homebrew/bin',
      '/opt/bin',
    ]) {
      pushCandidate(p.join(base, binary), 'known-path:$base');
    }
  }

  return candidates;
}

Future<String?> _probeBinaryHealth(String command) async {
  const healthChecks = [
    ['--version'],
    ['version'],
    ['-v'],
    ['--help'],
  ];
  final lowered = command.toLowerCase();
  final timeout = lowered.contains('opencode')
      ? _openCodeBinaryHealthCheckTimeout
      : Platform.isWindows &&
              (lowered.endsWith('.cmd') ||
                  lowered.endsWith('.bat') ||
                  lowered.endsWith('.ps1'))
          ? _windowsScriptHealthCheckTimeout
          : _binaryHealthCheckTimeout;

  for (final args in healthChecks) {
    final result = await _runCommandWithTimeout(command, args, timeout);
    if (result == null) {
      continue;
    }
    if (result.exitCode == 0) {
      return 'ok(${args.join(' ')})';
    }
  }

  return null;
}

Future<_CommitDiffContextResult> _collectCommitMessageContext({
  required String repositoryPath,
  required String scopeLabel,
  required List<String> scopedPaths,
  required bool includeStaged,
  required bool includeUnstaged,
}) async {
  final scopeArgs =
      scopedPaths.isEmpty ? const <String>[] : ['--', ...scopedPaths];

  final branch = await _runGitCommand(
    repositoryPath,
    const ['rev-parse', '--abbrev-ref', 'HEAD'],
  );
  if (!branch.ok) {
    return _CommitDiffContextResult.err(branch.error!);
  }

  final status = await _runGitCommand(
    repositoryPath,
    ['status', '--porcelain=v1', ...scopeArgs],
  );
  if (!status.ok) {
    return _CommitDiffContextResult.err(status.error!);
  }

  final stagedStat = includeStaged
      ? await _runGitCommand(
          repositoryPath,
          ['diff', '--cached', '--stat=$_diffStatWidth', ...scopeArgs],
        )
      : const GitResult.ok('');
  if (!stagedStat.ok) {
    return _CommitDiffContextResult.err(stagedStat.error!);
  }

  final unstagedStat = includeUnstaged
      ? await _runGitCommand(
          repositoryPath,
          ['diff', '--stat=$_diffStatWidth', ...scopeArgs],
        )
      : const GitResult.ok('');
  if (!unstagedStat.ok) {
    return _CommitDiffContextResult.err(unstagedStat.error!);
  }

  final stagedDiff = includeStaged
      ? await _runGitCommand(
          repositoryPath,
          ['diff', '--cached', '--no-color', ...scopeArgs],
          timeout: const Duration(seconds: _diffTimeoutSeconds),
        )
      : const GitResult.ok('');
  if (!stagedDiff.ok) {
    return _CommitDiffContextResult.err(stagedDiff.error!);
  }

  final unstagedDiff = includeUnstaged
      ? await _runGitCommand(
          repositoryPath,
          ['diff', '--no-color', ...scopeArgs],
          timeout: const Duration(seconds: _diffTimeoutSeconds),
        )
      : const GitResult.ok('');
  if (!unstagedDiff.ok) {
    return _CommitDiffContextResult.err(unstagedDiff.error!);
  }

  final fullDiff = _joinDiffSections(
    stagedDiff: stagedDiff.data ?? '',
    unstagedDiff: unstagedDiff.data ?? '',
  );
  if (fullDiff.trim().isEmpty) {
    return _CommitDiffContextResult.err(
      'No diff content is available for $scopeLabel.',
    );
  }

  final diffBundle = _buildDiffPromptBundle(fullDiff);
  final statSummary = _joinStatSections(
    stagedStat: stagedStat.data ?? '',
    unstagedStat: unstagedStat.data ?? '',
  );

  // ── Git telemetry — all commands in one parallel batch ──────────────────
  // Fixed caps (git returns fewer results gracefully on shallow repos).
  // rev-list runs alongside the log commands — no sequential gate.
  final telemetry = await Future.wait([
    _runGitCommand(repositoryPath, ['rev-list', '--count', 'HEAD']),
    _runGitCommand(repositoryPath, ['log', '--format=%h %s', '-10']),
    _runGitCommand(repositoryPath, ['log', '--format=%an', '-1']),
    _runGitCommand(repositoryPath, ['log', '--format=%cr', '-1']),
    _runGitCommand(repositoryPath, ['log', '--max-parents=0', '--format=%cr', 'HEAD']),
    _runGitCommand(repositoryPath, ['log', '--format=%an', '-50']),
  ]);

  final totalCommits =
      int.tryParse((telemetry[0].data ?? '').trim()) ?? 0;

  String recentLog = '';
  String authorName = '';
  String lastCommitAge = '';
  String projectAge = '';
  int uniqueContributors = 0;

  if (totalCommits > 0) {
    recentLog = (telemetry[1].data ?? '').trim();
    authorName = (telemetry[2].data ?? '').trim();
    lastCommitAge = (telemetry[3].data ?? '').trim();
    projectAge = (telemetry[4].data ?? '').trim();
    final authorLines = (telemetry[5].data ?? '')
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    uniqueContributors = authorLines.length;
  }

  return _CommitDiffContextResult.ok(
    _CommitDiffContext(
      branchName: (branch.data ?? 'HEAD').trim(),
      statusSummary: (status.data ?? '').trim(),
      statSummary: statSummary.trim(),
      diffBundle: diffBundle,
      totalCommits: totalCommits,
      recentLog: recentLog,
      authorName: authorName,
      lastCommitAge: lastCommitAge,
      projectAge: projectAge,
      uniqueContributors: uniqueContributors,
    ),
  );
}

String _joinDiffSections({
  required String stagedDiff,
  required String unstagedDiff,
}) {
  final sections = <String>[];
  if (stagedDiff.trim().isNotEmpty) {
    sections.add('=== STAGED CHANGES ===\n$stagedDiff');
  }
  if (unstagedDiff.trim().isNotEmpty) {
    sections.add('=== UNSTAGED CHANGES ===\n$unstagedDiff');
  }
  if (sections.isEmpty) {
    return '';
  }
  return sections.join('\n\n');
}

String _joinStatSections({
  required String stagedStat,
  required String unstagedStat,
}) {
  final sections = <String>[];
  if (stagedStat.trim().isNotEmpty) {
    sections.add('Staged diffstat:\n$stagedStat');
  }
  if (unstagedStat.trim().isNotEmpty) {
    sections.add('Unstaged diffstat:\n$unstagedStat');
  }
  return sections.join('\n\n');
}

_DiffPromptBundle _buildDiffPromptBundle(String fullDiff) {
  final parsedFiles = _parseDiffFiles(fullDiff);
  if (fullDiff.length <= _maxFullDiffChars) {
    return _DiffPromptBundle(
      promptBody: '<full_diff>\n$fullDiff\n</full_diff>',
      usedCondensedDiff: false,
      originalDiffCharacters: fullDiff.length,
    );
  }

  final overview = StringBuffer();
  var totalAdditions = 0;
  var totalDeletions = 0;
  for (final file in parsedFiles) {
    totalAdditions += file.additions;
    totalDeletions += file.deletions;
  }

  overview.writeln(
    'Full diff was condensed because it exceeded the inline prompt budget.',
  );
  overview.writeln(
    'Files changed: ${parsedFiles.length} | additions: $totalAdditions | deletions: $totalDeletions',
  );
  overview.writeln();
  overview.writeln('<all_files>');
  for (final file in parsedFiles) {
    overview.writeln(
      '- ${file.path} | +${file.additions} -${file.deletions} | hunks ${file.hunks.length}',
    );
  }
  overview.writeln('</all_files>');
  overview.writeln();
  overview.writeln('<file_digests>');

  final rankedFiles = [...parsedFiles]..sort(
      (left, right) => (right.additions + right.deletions)
          .compareTo(left.additions + left.deletions),
    );
  var remainingBudget = _maxCondensedDiffChars - overview.length - 40;
  for (final file in rankedFiles) {
    if (remainingBudget <= _maxChangedLineLength) {
      break;
    }
    final digest = _buildFileDigest(file);
    if (digest.length > remainingBudget) {
      final compactDigest = _buildCompactFileDigest(file);
      if (compactDigest.length > remainingBudget) {
        continue;
      }
      overview.write(compactDigest);
      remainingBudget -= compactDigest.length;
      continue;
    }
    overview.write(digest);
    remainingBudget -= digest.length;
  }
  overview.writeln('</file_digests>');

  var promptBody = overview.toString();
  if (promptBody.length > _maxPromptChars) {
    promptBody = promptBody.substring(0, _maxPromptChars);
  }
  return _DiffPromptBundle(
    promptBody: promptBody,
    usedCondensedDiff: true,
    originalDiffCharacters: fullDiff.length,
  );
}

List<_ParsedDiffFile> _parseDiffFiles(String diffText) {
  final files = <_ParsedDiffFile>[];
  _ParsedDiffFile? current;
  _ParsedDiffHunk? currentHunk;

  void closeHunk() {
    if (current != null && currentHunk != null) {
      current!.hunks.add(currentHunk!);
    }
    currentHunk = null;
  }

  void closeFile() {
    closeHunk();
    if (current != null) {
      files.add(current!);
    }
    current = null;
  }

  for (final line in diffText.split('\n')) {
    if (line.startsWith('diff --git ')) {
      closeFile();
      current = _ParsedDiffFile(path: _pathFromDiffHeader(line));
      continue;
    }
    if (current == null) {
      continue;
    }
    if (line.startsWith('@@')) {
      closeHunk();
      currentHunk = _ParsedDiffHunk(header: line.trim(), samples: []);
      continue;
    }
    if (line.startsWith('+++ ') || line.startsWith('--- ')) {
      continue;
    }
    if (line.startsWith('+')) {
      current!.additions += 1;
      currentHunk?.pushSample('+${_clipChangedLine(line.substring(1))}');
      continue;
    }
    if (line.startsWith('-')) {
      current!.deletions += 1;
      currentHunk?.pushSample('-${_clipChangedLine(line.substring(1))}');
    }
  }

  closeFile();
  return files;
}

String _buildFileDigest(_ParsedDiffFile file) {
  final buffer = StringBuffer();
  buffer.writeln(
    'FILE ${file.path} | +${file.additions} -${file.deletions} | hunks ${file.hunks.length}',
  );
  for (final hunk in file.hunks.take(6)) {
    buffer.writeln('  HUNK ${hunk.header}');
    for (final sample in hunk.samples.take(8)) {
      buffer.writeln('    $sample');
    }
  }
  buffer.writeln();
  return buffer.toString();
}

String _buildCompactFileDigest(_ParsedDiffFile file) {
  final buffer = StringBuffer();
  buffer.writeln(
    'FILE ${file.path} | +${file.additions} -${file.deletions} | hunks ${file.hunks.length}',
  );
  final firstHunk = file.hunks.firstOrNull;
  if (firstHunk != null) {
    buffer.writeln('  HUNK ${firstHunk.header}');
    for (final sample in firstHunk.samples.take(3)) {
      buffer.writeln('    $sample');
    }
  }
  buffer.writeln();
  return buffer.toString();
}

String _pathFromDiffHeader(String line) {
  final parts = line.split(' ');
  if (parts.length < 4) {
    return 'unknown';
  }
  final candidate = parts[3];
  return candidate.startsWith('b/') ? candidate.substring(2) : candidate;
}

String _clipChangedLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  const maxLength = 120;
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxLength - 3)}...';
}

String _buildCommitMessagePrompt({
  required String branchName,
  required String modelCategoryLabel,
  required String scopeLabel,
  required String customPrompt,
  required String statusSummary,
  required String statSummary,
  required String diffSummary,
  String existingMessage = '',
  int totalCommits = 0,
  String recentLog = '',
  String authorName = '',
  String lastCommitAge = '',
  String projectAge = '',
  int uniqueContributors = 0,
}) {
  final buffer = StringBuffer();
  buffer.writeln(
    'You are generating a git commit message for a desktop Git client.',
  );
  buffer.writeln(
    'Return only the commit message text. Do not add commentary, labels, quotes, or code fences.',
  );
  buffer.writeln(
    'If <user_instructions> are present, follow them exactly — they override all defaults including format, tone, length, and style.',
  );
  buffer.writeln(
    'Prefer a concise summary line. Add a blank line and body only when the diff clearly warrants extra detail.',
  );
  buffer.writeln(
    'Keep the summary specific to what changed, not just which files moved.',
  );
  buffer.writeln();
  buffer.writeln('<generation_context>');
  buffer.writeln('Branch: $branchName');
  if (authorName.isNotEmpty) buffer.writeln('Author: $authorName');
  if (totalCommits > 0) buffer.writeln('Total commits: $totalCommits');
  if (projectAge.isNotEmpty) buffer.writeln('Project started: $projectAge');
  if (lastCommitAge.isNotEmpty) buffer.writeln('Last commit: $lastCommitAge');
  if (uniqueContributors > 0) buffer.writeln('Contributors (sampled): $uniqueContributors');
  buffer.writeln('Model slot: $modelCategoryLabel');
  buffer.writeln('Scope: $scopeLabel');
  buffer.writeln('</generation_context>');
  if (recentLog.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<commit_history>');
    buffer.writeln(recentLog);
    buffer.writeln('</commit_history>');
  }
  if (existingMessage.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<existing_draft>');
    buffer.writeln(existingMessage.trim());
    buffer.writeln('</existing_draft>');
  }
  if (statusSummary.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<status_summary>');
    buffer.writeln(statusSummary.trim());
    buffer.writeln('</status_summary>');
  }
  if (statSummary.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<diffstat>');
    buffer.writeln(statSummary.trim());
    buffer.writeln('</diffstat>');
  }
  // User instructions go last before the diff — maximum recency weight,
  // acts as a final directive the model reads immediately before generating.
  if (customPrompt.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<user_instructions>');
    buffer.writeln(customPrompt.trim());
    buffer.writeln('</user_instructions>');
  }
  buffer.writeln();
  buffer.writeln('<diff_context>');
  buffer.writeln(diffSummary.trim());
  buffer.writeln('</diff_context>');

  var payload = buffer.toString().trim();
  if (payload.length > _maxPromptChars) {
    payload = payload.substring(0, _maxPromptChars);
  }
  return payload;
}

ReviewGuardrailProfile _guardrailProfileForStage(int stage) {
  switch (stage.clamp(0, 3)) {
    case 0:
      return const ReviewGuardrailProfile(
        id: 'loose',
        seat: 'restrained sanity checker',
        reviewRadius: 'Keep the review local to the changed code and obvious nearby effects.',
        primaryFear:
            'Your main job is to catch concrete logic bugs and likely breakage in the code at hand.',
        silenceRule:
            'Stay silent on cosmetic opinions, abstract architecture critiques, and weakly supported inconsistency commentary.',
        verdictBar:
            'Only downgrade the commit when the evidence supports a credible, likely problem.',
        priorityConcernClasses: [
          ReviewConcernClass.logicBug,
          ReviewConcernClass.regressionRisk,
        ],
        suppressedConcernClasses: [
          ReviewConcernClass.integrationMismatch,
          ReviewConcernClass.redundantPattern,
          ReviewConcernClass.inconsistentPattern,
          ReviewConcernClass.maintainabilityHazard,
        ],
        allowIntegrationEscalation: false,
        allowDesignSmellEscalation: false,
        requireConcreteEvidence: true,
      );
    case 1:
      return const ReviewGuardrailProfile(
        id: 'balanced',
        seat: 'practical reviewer',
        reviewRadius:
            'Review the changed code and its likely integration surface in the surrounding system.',
        primaryFear:
            'Your job is to catch correctness issues, regression risk, and meaningful inconsistency that weakens the change.',
        silenceRule:
            'Skip cosmetic nits and generic opinions. Surface only issues with practical engineering consequence.',
        verdictBar:
            'Downgrade when the evidence supports meaningful correctness, integration, or code-health risk.',
        priorityConcernClasses: [
          ReviewConcernClass.logicBug,
          ReviewConcernClass.regressionRisk,
          ReviewConcernClass.integrationMismatch,
          ReviewConcernClass.redundantPattern,
          ReviewConcernClass.inconsistentPattern,
        ],
        suppressedConcernClasses: [],
        allowIntegrationEscalation: true,
        allowDesignSmellEscalation: true,
        requireConcreteEvidence: true,
      );
    case 2:
      return const ReviewGuardrailProfile(
        id: 'strict',
        seat: 'careful maintainer',
        reviewRadius:
            'Review the changed code, nearby integration points, and hidden assumptions implied by the diff.',
        primaryFear:
            'Your job is to catch incomplete handling, hidden coupling, edge cases, and long-tail risks before commit.',
        silenceRule:
            'Do not nitpick aesthetics, but you should surface subtle risks when they are grounded in the diff.',
        verdictBar:
            'A commit is not ready when hidden assumptions or incomplete safeguards create material risk.',
        priorityConcernClasses: [
          ReviewConcernClass.logicBug,
          ReviewConcernClass.regressionRisk,
          ReviewConcernClass.integrationMismatch,
          ReviewConcernClass.redundantPattern,
          ReviewConcernClass.inconsistentPattern,
          ReviewConcernClass.hiddenAssumption,
          ReviewConcernClass.maintainabilityHazard,
        ],
        suppressedConcernClasses: [],
        allowIntegrationEscalation: true,
        allowDesignSmellEscalation: true,
        requireConcreteEvidence: true,
      );
    default:
      return const ReviewGuardrailProfile(
        id: 'paranoid',
        seat: 'final gate reviewer',
        reviewRadius:
            'Review the changed code, integration surface, and any broader operational or safety consequences supported by the diff.',
        primaryFear:
            'Your job is to prevent harmful surprises such as destructive behavior, data loss, corruption, security exposure, and silent regressions.',
        silenceRule:
            'Do not invent threats, but when the diff credibly points toward a serious risk class you should surface it clearly.',
        verdictBar:
            'Downgrade aggressively when the evidence points to a high-impact failure class, even if the bug is not fully proven.',
        priorityConcernClasses: [
          ReviewConcernClass.logicBug,
          ReviewConcernClass.regressionRisk,
          ReviewConcernClass.integrationMismatch,
          ReviewConcernClass.redundantPattern,
          ReviewConcernClass.inconsistentPattern,
          ReviewConcernClass.hiddenAssumption,
          ReviewConcernClass.maintainabilityHazard,
          ReviewConcernClass.destructiveRisk,
          ReviewConcernClass.securityRisk,
          ReviewConcernClass.stateCorruptionRisk,
        ],
        suppressedConcernClasses: [],
        allowIntegrationEscalation: true,
        allowDesignSmellEscalation: true,
        requireConcreteEvidence: true,
      );
  }
}

String _buildCommitReviewPrompt({
  required _ReviewPromptSpec spec,
  required ReviewGuardrailProfile profile,
}) {
  final buffer = StringBuffer();
  buffer.writeln(_buildReviewWakeBlock(profile, spec.passMode));
  buffer.writeln();
  buffer.writeln('<scope_and_jurisdiction>');
  buffer.writeln('Branch: ${spec.branchName}');
  buffer.writeln('Model slot: ${spec.modelCategoryLabel}');
  buffer.writeln('Requested scope: ${spec.scopeLabel}');
  buffer.writeln(profile.reviewRadius);
  buffer.writeln(
    spec.passMode == _ReviewPassMode.verify
        ? 'You are verifying a prior draft review for the same commit scope.'
        : 'You are reviewing a proposed commit immediately before it is created.',
  );
  buffer.writeln('</scope_and_jurisdiction>');
  buffer.writeln();
  buffer.writeln('<evidence_rules>');
  buffer.writeln(
    'Ground every finding in the visible diff. Prefer omission over speculation.',
  );
  if (profile.requireConcreteEvidence) {
    buffer.writeln(
      'Do not report a concern unless you can cite concrete evidence from the diff or its immediate implications.',
    );
  }
  buffer.writeln(
    'Do not edit code, rewrite the patch, or offer style-only commentary.',
  );
  buffer.writeln('</evidence_rules>');
  buffer.writeln();
  buffer.writeln('<escalation_rules>');
  buffer.writeln(profile.primaryFear);
  buffer.writeln(profile.silenceRule);
  buffer.writeln(profile.verdictBar);
  buffer.writeln(
    'Prioritize these concern classes: ${_concernClassLabels(profile.priorityConcernClasses).join(', ')}.',
  );
  if (profile.suppressedConcernClasses.isNotEmpty) {
    buffer.writeln(
      'Keep these concern classes suppressed unless they directly create real breakage: ${_concernClassLabels(profile.suppressedConcernClasses).join(', ')}.',
    );
  }
  if (profile.allowIntegrationEscalation) {
    buffer.writeln(
      'Integration mismatch can affect the verdict when it creates practical risk.',
    );
  }
  if (profile.allowDesignSmellEscalation) {
    buffer.writeln(
      'Redundancy or inconsistent patterns can affect the verdict when they weaken the change materially.',
    );
  }
  buffer.writeln('</escalation_rules>');
  buffer.writeln();
  buffer.writeln(_reviewOutputSchemaInstructions(spec.passMode));
  if (spec.customPrompt.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<user_review_guide>');
    buffer.writeln(
      'Apply this optional review guidance when it does not conflict with the required output schema.',
    );
    buffer.writeln(spec.customPrompt.trim());
    buffer.writeln('</user_review_guide>');
  }
  if (spec.priorReview != null && spec.priorReview!.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<prior_review>');
    buffer.writeln(spec.priorReview!.trim());
    buffer.writeln('</prior_review>');
  }
  if (spec.statusSummary.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<status_summary>');
    buffer.writeln(spec.statusSummary.trim());
    buffer.writeln('</status_summary>');
  }
  if (spec.statSummary.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<diffstat>');
    buffer.writeln(spec.statSummary.trim());
    buffer.writeln('</diffstat>');
  }
  buffer.writeln();
  buffer.writeln('<diff_context>');
  buffer.writeln(spec.diffSummary.trim());
  buffer.writeln('</diff_context>');

  var payload = buffer.toString().trim();
  if (payload.length > _maxPromptChars) {
    payload = payload.substring(0, _maxPromptChars);
  }
  return payload;
}

String _buildReviewWakeBlock(
  ReviewGuardrailProfile profile,
  _ReviewPassMode passMode,
) {
  final buffer = StringBuffer();
  buffer.writeln('<wake>');
  if (passMode == _ReviewPassMode.verify) {
    buffer.writeln(
      'You are the ${profile.seat} returning for a second pass.',
    );
    buffer.writeln(
      'Your responsibility is to challenge omissions, overclaims, severity mistakes, and hidden corners the first pass may have missed.',
    );
  } else {
    buffer.writeln('You are the ${profile.seat} for this commit review.');
    buffer.writeln(
      'Your responsibility is to judge whether this change is safe and coherent enough to commit.',
    );
  }
  buffer.writeln(profile.primaryFear);
  buffer.writeln(profile.silenceRule);
  buffer.writeln(profile.verdictBar);
  buffer.writeln('</wake>');
  return buffer.toString();
}

String _reviewOutputSchemaInstructions(_ReviewPassMode passMode) {
  if (passMode == _ReviewPassMode.verify) {
    return '''
<output_schema>
Return XML-like text only. Do not include prose before or after the schema.
Use exactly this shape:
<verification_result>
<confirmed_ids>F1,F2</confirmed_ids>
<rejected_ids>F3</rejected_ids>
<verification_notes>Short explanation of what changed after verification.</verification_notes>
<score_adjustment>-4</score_adjustment>
<verdict_adjustment>Needs attention</verdict_adjustment>
<final_summary>One sentence final summary.</final_summary>
<summary_reasoning>Short plain-language explanation of the reasoning.</summary_reasoning>
<new_findings>
<finding id="V1" severity="warn" file="path/or/-" hunk="@@ ... @@ or -">
<title>Short title</title>
<evidence>Concrete evidence from the diff</evidence>
<why>Why it matters</why>
</finding>
</new_findings>
</verification_result>
If there are no confirmed or rejected ids, leave the tag empty.
If there are no new findings, keep <new_findings></new_findings> empty.
</output_schema>''';
  }

  return '''
<output_schema>
Return XML-like text only. Do not include prose before or after the schema.
Use exactly this shape:
<review_result>
<verdict>Ready|Mostly ready|Needs attention|High risk|Block</verdict>
<score>0-100 integer</score>
<summary>One sentence summary.</summary>
<summary_reasoning>Short plain-language explanation of the reasoning.</summary_reasoning>
<findings>
<finding id="F1" severity="note|warn|risk|block" file="path/or/-" hunk="@@ ... @@ or -">
<title>Short title</title>
<evidence>Concrete evidence from the diff</evidence>
<why>Why it matters</why>
</finding>
</findings>
</review_result>
If there are no findings, keep <findings></findings> empty.
</output_schema>''';
}

List<String> _concernClassLabels(List<ReviewConcernClass> values) {
  return values.map((value) {
    switch (value) {
      case ReviewConcernClass.logicBug:
        return 'logic bug';
      case ReviewConcernClass.regressionRisk:
        return 'regression risk';
      case ReviewConcernClass.integrationMismatch:
        return 'integration mismatch';
      case ReviewConcernClass.redundantPattern:
        return 'redundant pattern';
      case ReviewConcernClass.inconsistentPattern:
        return 'inconsistent pattern';
      case ReviewConcernClass.hiddenAssumption:
        return 'hidden assumption';
      case ReviewConcernClass.maintainabilityHazard:
        return 'maintainability hazard';
      case ReviewConcernClass.destructiveRisk:
        return 'destructive risk';
      case ReviewConcernClass.securityRisk:
        return 'security risk';
      case ReviewConcernClass.stateCorruptionRisk:
        return 'state corruption risk';
    }
  }).toList();
}

Future<_ProviderPromptResult> _runProviderPrompt({
  required _ProviderSpec provider,
  required _ProviderResolution resolution,
  required String modelId,
  required String prompt,
  required String repositoryPath,
  bool readOnly = true,
}) async {
  final attempts = _buildProviderAttempts(provider.kind, modelId, readOnly: readOnly, resolvedCommand: resolution.command);
  String? providerOutput;
  String? lastError;
  for (final attempt in attempts) {
    final effectiveArgs = attempt.useStdinForPrompt
        ? attempt.args
        : [...attempt.args, prompt];
    final effectiveStdin = attempt.useStdinForPrompt ? prompt : null;
    final result = await _runObservedProcess(
      commandLabel: 'ai.${provider.id}.${attempt.name}',
      scope: 'ai',
      command: resolution.command,
      args: effectiveArgs,
      timeout: _providerRuntimeTimeout,
      workingDirectory: repositoryPath,
      stdinPayload: effectiveStdin,
      environment: _providerEnvironment(provider.kind),
    );

    if (result == null) {
      lastError = 'Provider command timed out.';
      continue;
    }

    final formatted = _formatProviderOutput(
      attempt.outputMode,
      result.stdout,
      result.stderr,
    );
    if (result.exitCode == 0 &&
        formatted != null &&
        formatted.trim().isNotEmpty &&
        !_looksLikeProviderError(provider.kind, formatted)) {
      providerOutput = formatted;
      break;
    }

    lastError = formatted?.trim().isNotEmpty == true
        ? formatted
        : result.stderr.trim().isNotEmpty
            ? result.stderr.trim()
            : 'Provider exited with code ${result.exitCode}.';
  }

  if (providerOutput == null) {
    return _ProviderPromptResult(
      ok: false,
      error: _normalizeProviderError(
        provider.kind,
        lastError ?? 'Provider did not return output.',
      ),
      outputPreview: lastError ?? '',
    );
  }

  return _ProviderPromptResult(
    ok: true,
    output: providerOutput,
    outputPreview: providerOutput,
  );
}

_ParsedReviewResult? _parseDraftReview(String raw) {
  final normalized = _normalizeModelMarkup(raw);
  final verdict = _extractTag(normalized, 'verdict');
  final scoreRaw = _extractTag(normalized, 'score');
  final summary = _extractTag(normalized, 'summary');
  final summaryReasoning = _extractTag(normalized, 'summary_reasoning');
  if (verdict == null || scoreRaw == null || summary == null || summaryReasoning == null) {
    return null;
  }
  final score = int.tryParse(scoreRaw.trim());
  if (score == null) {
    return null;
  }
  final findingsBlock = _extractTag(normalized, 'findings') ?? '';
  final findings = _parseFindingTags(findingsBlock, origin: 'draft');
  return _ParsedReviewResult(
    verdict: _normalizeVerdict(verdict),
    score: score.clamp(0, 100),
    summary: summary.trim(),
    reasoningReport: summaryReasoning.trim(),
    findings: findings,
  );
}

AiCommitReviewVerificationData? _parseVerificationReview(String raw) {
  final normalized = _normalizeModelMarkup(raw);
  final notes = _extractTag(normalized, 'verification_notes');
  final scoreAdjustmentRaw = _extractTag(normalized, 'score_adjustment');
  final finalSummary = _extractTag(normalized, 'final_summary');
  final summaryReasoning = _extractTag(normalized, 'summary_reasoning');
  if (notes == null ||
      scoreAdjustmentRaw == null ||
      finalSummary == null ||
      summaryReasoning == null) {
    return null;
  }
  final scoreAdjustment = int.tryParse(scoreAdjustmentRaw.trim());
  if (scoreAdjustment == null) {
    return null;
  }
  final confirmedIds =
      _splitIdList(_extractTag(normalized, 'confirmed_ids') ?? '');
  final rejectedIds =
      _splitIdList(_extractTag(normalized, 'rejected_ids') ?? '');
  final newFindings = _parseFindingTags(
    _extractTag(normalized, 'new_findings') ?? '',
    origin: 'verification',
  );
  final verdictAdjustment = _extractTag(normalized, 'verdict_adjustment');
  return AiCommitReviewVerificationData(
    confirmedFindingIds: confirmedIds,
    rejectedFindingIds: rejectedIds,
    newFindings: newFindings,
    scoreAdjustment: scoreAdjustment,
    verdictAdjustment:
        verdictAdjustment == null || verdictAdjustment.trim().isEmpty
            ? null
            : _normalizeVerdict(verdictAdjustment),
    verificationNotes: notes.trim(),
    finalSummary: finalSummary.trim(),
    finalReasoningReport: summaryReasoning.trim(),
  );
}

List<AiCommitReviewFindingData> _parseFindingTags(
  String block, {
  required String origin,
}) {
  final matches = _findingTagRegex.allMatches(block);
  final findings = <AiCommitReviewFindingData>[];
  var index = 0;
  final isDraft = origin == _findingOriginDraft;
  final idPrefix = isDraft ? _findingIdPrefixDraft : _findingIdPrefixVerification;
  for (final match in matches) {
    final attrs = _parseXmlAttributes(match.group(1) ?? '');
    final body = match.group(2) ?? '';
    index += 1;
    findings.add(
      AiCommitReviewFindingData(
        id: (attrs['id']?.trim().isNotEmpty ?? false)
            ? attrs['id']!.trim()
            : '$idPrefix$index',
        severity: _normalizeSeverity(attrs['severity']),
        title: (_extractTag(body, 'title') ?? 'Finding $index').trim(),
        evidence: (_extractTag(body, 'evidence') ?? '').trim(),
        whyItMatters: (_extractTag(body, 'why') ?? '').trim(),
        filePath: _normalizedOptionalTagAttribute(attrs['file']),
        hunkLabel: _normalizedOptionalTagAttribute(attrs['hunk']),
        origin: origin,
      ),
    );
  }
  return findings;
}

_MergedReviewResult _mergeVerifiedReview({
  required _ParsedReviewResult draft,
  required AiCommitReviewVerificationData verification,
}) {
  final active = <String, AiCommitReviewFindingData>{};
  for (final finding in draft.findings) {
    active[finding.id] = finding;
  }
  for (final id in verification.rejectedFindingIds) {
    active.remove(id);
  }
  for (final finding in verification.newFindings) {
    active[finding.id] = finding;
  }

  final mergedFindings = active.values.map((finding) {
    if (verification.confirmedFindingIds.contains(finding.id)) {
      return AiCommitReviewFindingData(
        id: finding.id,
        severity: finding.severity,
        title: finding.title,
        evidence: finding.evidence,
        whyItMatters: finding.whyItMatters,
        filePath: finding.filePath,
        hunkLabel: finding.hunkLabel,
        origin: 'merged',
      );
    }
    return finding.origin == 'verification'
        ? finding
        : AiCommitReviewFindingData(
            id: finding.id,
            severity: finding.severity,
            title: finding.title,
            evidence: finding.evidence,
            whyItMatters: finding.whyItMatters,
            filePath: finding.filePath,
            hunkLabel: finding.hunkLabel,
            origin: 'merged',
          );
  }).toList()
    ..sort((left, right) =>
        _severityWeight(right.severity).compareTo(_severityWeight(left.severity)));

  final baseScore = (draft.score + verification.scoreAdjustment).clamp(0, 100);
  final verdict = verification.verdictAdjustment ?? draft.verdict;
  return _MergedReviewResult(
    verdict: verdict,
    score: baseScore,
    summary: verification.finalSummary,
    reasoningReport: verification.finalReasoningReport,
    findings: mergedFindings,
  );
}

String _serializeDraftReview(_ParsedReviewResult draft) {
  final buffer = StringBuffer();
  buffer.writeln('<draft_review>');
  buffer.writeln('<verdict>${draft.verdict}</verdict>');
  buffer.writeln('<score>${draft.score}</score>');
  buffer.writeln('<summary>${draft.summary}</summary>');
  buffer.writeln('<summary_reasoning>${draft.reasoningReport}</summary_reasoning>');
  buffer.writeln('<findings>');
  for (final finding in draft.findings) {
    buffer.writeln(
      '<finding id="${finding.id}" severity="${finding.severity}" file="${finding.filePath ?? _unknownPlaceholder}" hunk="${finding.hunkLabel ?? _unknownPlaceholder}">',
    );
    buffer.writeln('<title>${finding.title}</title>');
    buffer.writeln('<evidence>${finding.evidence}</evidence>');
    buffer.writeln('<why>${finding.whyItMatters}</why>');
    buffer.writeln('</finding>');
  }
  buffer.writeln('</findings>');
  buffer.writeln('</draft_review>');
  return buffer.toString();
}

String _serializeFinalReview(_MergedReviewResult result) {
  final findingSummary = result.findings
      .take(6)
      .map((finding) => '[${finding.severity}] ${finding.title}')
      .join(' | ');
  return '${result.verdict} | ${result.score} | ${result.summary} | $findingSummary';
}


String _normalizeModelMarkup(String value) {
  var normalized = value.replaceAll('\r\n', '\n').trim();
  if (normalized.startsWith('```')) {
    final lines = normalized.split('\n');
    if (lines.length >= 3) {
      normalized = lines.sublist(1, lines.length - 1).join('\n').trim();
    }
  }
  return normalized;
}

String? _extractTag(String input, String tag) {
  final match = RegExp(
    '<$tag>([\\s\\S]*?)</$tag>',
    caseSensitive: false,
  ).firstMatch(input);
  return match?.group(1);
}

Map<String, String> _parseXmlAttributes(String raw) {
  final attrs = <String, String>{};
  final matches = _xmlAttrRegex.allMatches(raw);
  for (final match in matches) {
    final key = match.group(1);
    final value = match.group(2);
    if (key != null && value != null) {
      attrs[key] = value;
    }
  }
  return attrs;
}

List<String> _splitIdList(String raw) {
  return raw
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

String _normalizeVerdict(String raw) {
  final lower = raw.trim().toLowerCase();
  switch (lower) {
    case 'ready':
      return 'Ready';
    case 'mostly ready':
      return 'Mostly ready';
    case 'needs attention':
      return 'Needs attention';
    case 'high risk':
      return 'High risk';
    case 'block':
      return 'Block';
    default:
      return 'Needs attention';
  }
}

String _normalizeSeverity(String? raw) {
  final lower = (raw ?? '').trim().toLowerCase();
  switch (lower) {
    case 'note':
      return 'note';
    case 'warn':
      return 'warn';
    case 'risk':
      return 'risk';
    case 'block':
      return 'block';
    default:
      return 'warn';
  }
}

String? _normalizedOptionalTagAttribute(String? raw) {
  if (raw == null) {
    return null;
  }
  final normalized = raw.trim();
  if (normalized.isEmpty || normalized == _unknownPlaceholder) {
    return null;
  }
  return normalized;
}

int _severityWeight(String severity) {
  switch (severity) {
    case 'block':
      return 4;
    case 'risk':
      return 3;
    case 'warn':
      return 2;
    case 'note':
      return 1;
    default:
      return 0;
  }
}

Future<void> _recordReviewAudit({
  required String event,
  required String providerId,
  required String repositoryPath,
  required String scopeLabel,
  required String promptPreview,
  required String outputPreview,
  required bool ok,
  String? errorCode,
}) {
  return AiAuditStore.recordEntry(
    AiAuditEntryData(
      id: '${DateTime.now().microsecondsSinceEpoch}-$event',
      event: event,
      providerId: providerId,
      repositoryHint: p.basename(repositoryPath),
      diffScopePath: scopeLabel,
      promptPreview: _previewText(promptPreview),
      outputPreview: _previewText(outputPreview),
      ok: ok,
      errorCode: errorCode,
      createdAt: DateTime.now().toIso8601String(),
    ),
  );
}

String _previewText(String value, {int? maxLength}) {
  final limit = maxLength ?? _previewMaxLength;
  final normalized = value.replaceAll('\r\n', '\n').trim();
  if (normalized.length <= limit) {
    return normalized;
  }
  return '${normalized.substring(0, limit - _truncationSuffix.length)}$_truncationSuffix';
}

List<_ProviderAttempt> _buildProviderAttempts(
  _ProviderKind kind,
  String modelId, {
  bool readOnly = true,
  String resolvedCommand = '',
}) {
  switch (kind) {
    case _ProviderKind.codex:
      return [
        _ProviderAttempt(
          name: 'exec-json',
          args: ['exec', '--model', modelId, '--json', '-'],
          outputMode: _ProviderOutputMode.codexJsonl,
        ),
        _ProviderAttempt(
          name: 'exec',
          args: ['exec', '--model', modelId, '-'],
          outputMode: _ProviderOutputMode.plainText,
        ),
      ];
    case _ProviderKind.claude:
      return [
        _ProviderAttempt(
          name: 'prompt-json',
          args: ['-p', '--model', modelId, '--output-format', 'json'],
          outputMode: _ProviderOutputMode.claudeJson,
        ),
        _ProviderAttempt(
          name: 'prompt',
          args: ['-p', '--model', modelId],
          outputMode: _ProviderOutputMode.plainText,
        ),
      ];
    case _ProviderKind.gemini:
      // Strip the "gemini " display prefix before passing to -m flag.
      final geminiModelArg = modelId.startsWith('gemini ')
          ? modelId.substring('gemini '.length)
          : modelId;
      // When falling back to npx (gemini not installed globally), prepend the
      // package reference so npx downloads/runs @google/gemini-cli.
      final isNpx = resolvedCommand.toLowerCase().contains('npx');
      final npxPrefix = isNpx ? ['--yes', '@google/gemini-cli'] : <String>[];
      return [
        _ProviderAttempt(
          name: 'cli-json',
          args: [
            ...npxPrefix,
            '-p',
            '',
            '-o',
            'json',
            '-m',
            geminiModelArg,
            if (readOnly) ...['--approval-mode', 'plan'],
          ],
          outputMode: _ProviderOutputMode.geminiJson,
        ),
        // Fallback without --approval-mode for older CLI versions.
        _ProviderAttempt(
          name: 'cli-json-compat',
          args: [
            ...npxPrefix,
            '-p',
            '',
            '-o',
            'json',
            '-m',
            geminiModelArg,
          ],
          outputMode: _ProviderOutputMode.geminiJson,
        ),
        _ProviderAttempt(
          name: 'cli',
          args: [
            ...npxPrefix,
            '-p',
            '',
            '-m',
            geminiModelArg,
          ],
          outputMode: _ProviderOutputMode.plainText,
        ),
      ];
    case _ProviderKind.openCode:
      // OpenCode's native binary (Go) reads the message from stdin when no
      // positional args are given. We prefer stdin over positional args
      // because review prompts easily exceed Windows' 32767-char command
      // line limit. The native binary is resolved by _tryResolveNativeBinary
      // so there's no Node.js/libuv in the pipe chain — Dart→Go works fine.
      return [
        _ProviderAttempt(
          name: 'run-json',
          args: ['run', '--format', 'json', '-m', modelId],
          outputMode: _ProviderOutputMode.openCodeJsonl,
        ),
        _ProviderAttempt(
          name: 'run',
          args: ['run', '-m', modelId],
          outputMode: _ProviderOutputMode.plainText,
        ),
      ];
  }
}

Map<String, String> _providerEnvironment(_ProviderKind kind) {
  switch (kind) {
    case _ProviderKind.claude:
      return const {'CLAUDE_CODE_ENTRYPOINT': 'cli'};
    case _ProviderKind.gemini:
      return const {'CI': '1'};
    case _ProviderKind.codex:
    case _ProviderKind.openCode:
      return const {};
  }
}

String? _formatProviderOutput(
  _ProviderOutputMode mode,
  String stdout,
  String stderr,
) {
  switch (mode) {
    case _ProviderOutputMode.plainText:
      final cleanStdout = _stripAnsi(stdout.trim());
      if (cleanStdout.isNotEmpty) {
        return cleanStdout;
      }
      final cleanStderr = _stripAnsi(stderr.trim());
      return cleanStderr.isEmpty ? null : cleanStderr;
    case _ProviderOutputMode.codexJsonl:
      return _parseCodexJsonl(stdout) ?? _fallbackOutput(stderr);
    case _ProviderOutputMode.claudeJson:
      return _parseClaudeJson(stdout) ??
          _fallbackOutput(stdout) ??
          _fallbackOutput(stderr);
    case _ProviderOutputMode.geminiJson:
      return _parseGeminiJson(stdout) ??
          _fallbackOutput(stdout) ??
          _fallbackOutput(stderr);
    case _ProviderOutputMode.openCodeJsonl:
      return _parseOpenCodeJsonl(stdout) ??
          _fallbackOutput(stdout) ??
          _fallbackOutput(stderr);
  }
}

String? _parseCodexJsonl(String stdout) {
  var response = '';
  var errorMessage = '';
  for (final line in stdout.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    try {
      final value = jsonDecode(trimmed);
      if (value is! Map) {
        continue;
      }
      final type = value['type'];
      if (type == 'item.completed') {
        final item = value['item'];
        if (item is Map && item['text'] is String) {
          response = item['text'] as String;
        }
      }
      if ((type == 'error' || type == 'turn.failed') &&
          value['message'] is String) {
        errorMessage = value['message'] as String;
      }
      final error = value['error'];
      if (errorMessage.isEmpty && error is Map && error['message'] is String) {
        errorMessage = error['message'] as String;
      }
    } catch (_) {}
  }
  if (response.trim().isNotEmpty) {
    return response.trim();
  }
  if (errorMessage.trim().isNotEmpty) {
    return 'Codex error: ${_stripAnsi(errorMessage.trim())}';
  }
  return _fallbackOutput(stdout);
}

String? _parseClaudeJson(String stdout) {
  try {
    final value = jsonDecode(stdout);
    if (value is! Map) {
      return null;
    }
    if (value['is_error'] == true && value['result'] is String) {
      return 'Claude error: ${_stripAnsi((value['result'] as String).trim())}';
    }
    final result = value['result'];
    if (result is String && result.trim().isNotEmpty) {
      return result.trim();
    }
  } catch (_) {}
  return null;
}

String? _parseGeminiJson(String stdout) {
  // Gemini CLI prints lines like "Loaded cached credentials." before the JSON.
  // Scan for the first '{' to skip any prefix output.
  final jsonStart = stdout.indexOf('{');
  if (jsonStart == -1) return null;
  try {
    final value = jsonDecode(stdout.substring(jsonStart));
    if (value is! Map) {
      return null;
    }
    final error = value['error'];
    if (error is Map && error['message'] is String) {
      return 'Gemini error: ${_stripAnsi((error['message'] as String).trim())}';
    }
    final response = value['response'];
    if (response is String && response.trim().isNotEmpty) {
      return response.trim();
    }
  } catch (_) {}
  return null;
}

String? _parseOpenCodeJsonl(String stdout) {
  final buffer = StringBuffer();
  String? errorMessage;
  for (final line in stdout.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    try {
      final value = jsonDecode(trimmed);
      if (value is! Map) {
        continue;
      }
      if (value['type'] == 'error') {
        final error = value['error'];
        if (error is Map && error['message'] is String) {
          errorMessage = error['message'] as String;
        }
        if (error is Map && error['data'] is Map) {
          final data = error['data'];
          if (data is Map && data['message'] is String) {
            errorMessage = data['message'] as String;
          }
        }
        errorMessage ??=
            value['message'] is String ? value['message'] as String : null;
        continue;
      }
      if (value['type'] != 'text' &&
          value['text'] is! String &&
          value['message'] is! String) {
        continue;
      }
      final part = value['part'];
      if (part is Map && part['text'] is String) {
        buffer.write(part['text']);
        continue;
      }
      if (value['text'] is String) {
        buffer.write(value['text'] as String);
        continue;
      }
      final message = value['message'];
      if (message is Map && message['text'] is String) {
        buffer.write(message['text'] as String);
        continue;
      }
    } catch (_) {
      if (_looksLikeProviderError(_ProviderKind.openCode, trimmed)) {
        errorMessage = trimmed;
      }
    }
  }
  final response = buffer.toString().trim();
  if (response.isNotEmpty) {
    return response;
  }
  if (errorMessage != null && errorMessage!.trim().isNotEmpty) {
    return 'OpenCode error: ${_stripAnsi(errorMessage!.trim())}';
  }
  return null;
}

bool _looksLikeProviderError(_ProviderKind kind, String raw) {
  final normalized = _stripAnsi(raw.trim());
  if (normalized.isEmpty) {
    return false;
  }
  final lower = normalized.toLowerCase();
  switch (kind) {
    case _ProviderKind.openCode:
      return lower.startsWith('opencode error:') ||
          lower.contains('error: unexpected error') ||
          lower.contains('check log file at') ||
          lower.contains('uv_unknown') ||
          lower.contains('providermodelnotfounderror') ||
          lower.contains('model not found:') ||
          lower.contains('requested model is not supported') ||
          lower.contains('model_not_supported') ||
          lower.contains('token refresh failed');
    case _ProviderKind.codex:
      return lower.startsWith('codex error:');
    case _ProviderKind.claude:
      return lower.startsWith('claude error:');
    case _ProviderKind.gemini:
      return lower.startsWith('gemini error:');
  }
}

String _normalizeProviderError(_ProviderKind kind, String raw) {
  final normalized = _stripAnsi(raw.trim());
  if (normalized.isEmpty) {
    return 'The provider did not return a usable response.';
  }

  switch (kind) {
    case _ProviderKind.openCode:
      return _normalizeOpenCodeError(normalized);
    case _ProviderKind.codex:
      return _normalizeCodexError(normalized);
    case _ProviderKind.claude:
      return normalized;
    case _ProviderKind.gemini:
      return _normalizeGeminiError(normalized);
  }
}

String _normalizeOpenCodeError(String raw) {
  final cleaned = _stripAnsi(raw)
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .takeWhile(
        (line) =>
            !line.startsWith('at ') &&
            !line.startsWith('data: {') &&
            !line.startsWith('providerID:') &&
            !line.startsWith('modelID:') &&
            !line.startsWith('suggestions:') &&
            !line.startsWith('at <anonymous>'),
      )
      .join('\n')
      .trim();
  final lower = cleaned.toLowerCase();
  if (lower.contains('providermodelnotfounderror') ||
      lower.contains('model not found:')) {
    return 'OpenCode could not find that model on the current provider connection.';
  }
  if (lower.contains('token refresh failed') || lower.contains('401')) {
    return 'OpenCode could not authenticate this model provider. Reconnect that provider or choose another model.';
  }
  if (lower.contains('model_not_supported') ||
      lower.contains('requested model is not supported')) {
    return 'OpenCode reported that this model is not supported by the current provider connection.';
  }
  if (lower.contains('check log file at') || lower.contains('uv_unknown')) {
    return 'OpenCode hit a provider runtime error while starting this model. Try again, reconnect the provider, or choose another model.';
  }
  if (lower.startsWith('opencode error:')) {
    final trimmed = cleaned.substring('OpenCode error:'.length).trim();
    if (trimmed.isNotEmpty) {
      return _normalizeOpenCodeError(trimmed);
    }
  }
  if (lower.startsWith('error:')) {
    final trimmed = cleaned.substring('Error:'.length).trim();
    if (trimmed.isNotEmpty) {
      return _normalizeOpenCodeError(trimmed);
    }
  }
  return cleaned.isEmpty ? raw : cleaned;
}

// Codex dumps a session header + the echoed prompt when it exits with an error.
// Pattern:
//   OpenAI Codex v0.x.x
//   --------
//   workdir: ...
//   model: ...
//   --------
//   <echoed user prompt>
//
// We try to find the real error (rate limit message, API error, etc.) inside
// that noise. If nothing meaningful is found we return a short generic message
// rather than surfacing thousands of characters to the UI.
String _normalizeCodexError(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').split('\n');

  // Collect candidate error lines: skip the version banner, separator lines,
  // workdir/model metadata, and the echoed prompt body (which tends to be long
  // structured text). A "meaningful" error line is short-ish and contains a
  // recognisable signal word.
  final errorSignals = RegExp(
    r'(error|rate.?limit|quota|exceed|unauthorized|forbidden|invalid|failed|timeout|unavailable|429|401|403)',
    caseSensitive: false,
  );
  final sessionHeaderTokens = RegExp(
    r'^(openai codex|workdir:|model:|agent:|session:|--------)',
    caseSensitive: false,
  );

  // First pass: look for explicit error/rate-limit lines anywhere in the output.
  final errorLines = <String>[];
  for (final line in lines) {
    final t = line.trim();
    if (t.isEmpty || sessionHeaderTokens.hasMatch(t)) continue;
    if (errorSignals.hasMatch(t) && t.length < 300) {
      errorLines.add(t);
    }
  }
  if (errorLines.isNotEmpty) {
    return errorLines.take(4).join('\n');
  }

  // Second pass: if no explicit error lines, strip the session header block and
  // return at most the first 5 meaningful non-header lines (could be a plain
  // text error message).
  bool pastHeader = false;
  final candidates = <String>[];
  for (final line in lines) {
    final t = line.trim();
    if (sessionHeaderTokens.hasMatch(t)) {
      pastHeader = true;
      continue;
    }
    if (!pastHeader && t.isEmpty) continue;
    if (t.isEmpty) continue;
    candidates.add(t);
    if (candidates.length >= 5) break;
  }
  if (candidates.isNotEmpty) {
    return candidates.join('\n');
  }

  return 'Codex exited with an error. Check the Codex log for details.';
}

// Gemini CLI (Node.js) can dump a full V8 GC trace and stack on OOM.
// Detect that pattern and return a clean user-facing message.
String _normalizeGeminiError(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('javascript heap out of memory') ||
      lower.contains('allocation failed') ||
      lower.contains('fatal error') && lower.contains('mark-compact')) {
    return 'Gemini CLI ran out of memory processing this request. '
        'Try a smaller diff or fewer files.';
  }
  if (lower.contains('rate limit') || lower.contains('429')) {
    return 'Gemini API rate limit reached. Wait a moment and try again.';
  }
  if (lower.contains('quota') || lower.contains('exceeded')) {
    return 'Gemini API quota exceeded. Check your Google AI usage.';
  }
  // For other errors, cap the length to avoid overflowing the UI.
  if (raw.length > 500) {
    // Try to find a meaningful first line.
    final firstMeaningful = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('[') && !l.startsWith('<'))
        .take(3)
        .join('\n');
    return firstMeaningful.isNotEmpty ? firstMeaningful : raw.substring(0, 500);
  }
  return raw;
}

String? _fallbackOutput(String value) {
  final normalized = _stripAnsi(value.trim());
  return normalized.isEmpty ? null : normalized;
}

String _normalizeCommitMessage(String raw) {
  var value = raw.replaceAll('\r\n', '\n').trim();
  if (value.startsWith('```')) {
    final lines = value.split('\n');
    if (lines.length >= 3) {
      value = lines.sublist(1, lines.length - 1).join('\n').trim();
    }
  }

  final lower = value.toLowerCase();
  if (lower.startsWith('commit message:')) {
    value = value.substring('commit message:'.length).trim();
  } else if (lower.startsWith('summary:')) {
    value = value.substring('summary:'.length).trim();
  }

  if ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))) {
    value = value.substring(1, value.length - 1).trim();
  }

  return value;
}

Future<GitResult<String>> _runGitCommand(
  String repositoryPath,
  List<String> args, {
  Duration timeout = _gitCommandTimeout,
}) async {
  final result = await _runObservedProcess(
    commandLabel: args.isEmpty ? 'git' : 'git.${args.first}',
    scope: 'git',
    command: 'git',
    args: args,
    timeout: timeout,
    workingDirectory: repositoryPath,
  );
  if (result == null) {
    return const GitResult.err('Git command timed out.');
  }
  if (result.exitCode != 0) {
    final stderr = result.stderr.trim();
    return GitResult.err(stderr.isEmpty ? 'Git command failed.' : stderr);
  }
  return GitResult.ok(result.stdout);
}

Future<_CommandResult?> _runCommandWithTimeout(
  String command,
  List<String> args,
  Duration timeout,
) async {
  final invocation = _buildProcessInvocation(command, args);
  try {
    final process = await Process.start(
      invocation.command,
      invocation.args,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      return null;
    }

    return _CommandResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
  } on ProcessException {
    return null;
  }
}

Future<_CommandResult?> _runObservedProcess({
  required String commandLabel,
  required String scope,
  required String command,
  required List<String> args,
  required Duration timeout,
  String? workingDirectory,
  String? stdinPayload,
  Map<String, String> environment = const {},
}) async {
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: commandLabel,
  );

  final invocation = _buildProcessInvocation(command, args);

  // On Windows, Dart's named pipes are incompatible with many CLI tools
  // (Node.js/libuv UV_UNKNOWN, Go read failures on large payloads).
  // Bypass Dart's stdin pipe entirely: write payload to a temp file and use
  // cmd.exe's `<` redirection so the OS provides a regular file handle.
  File? stdinTempFile;
  if (Platform.isWindows && stdinPayload != null) {
    stdinTempFile = File(p.join(
      Directory.systemTemp.path,
      'ai_stdin_${DateTime.now().millisecondsSinceEpoch}_${commandLabel.hashCode.abs()}.tmp',
    ));
    stdinTempFile.writeAsStringSync(stdinPayload, flush: true);
  }

  try {
    final Process process;
    if (stdinTempFile != null) {
      // Write a temp .bat that runs the command with stdin redirected from
      // the temp file. This sidesteps cmd.exe's nightmarish quoting rules
      // for paths with spaces — the batch file body isn't subject to
      // command-line parsing.
      final batFile = File('${stdinTempFile.path}.bat');
      final batContent = StringBuffer('@echo off\r\n');
      batContent.write('"${invocation.command}"');
      for (final arg in invocation.args) {
        batContent.write(' ');
        if (arg.contains(' ') || arg.isEmpty) {
          batContent.write('"$arg"');
        } else {
          batContent.write(arg);
        }
      }
      batContent.write(' <"${stdinTempFile.path}"\r\n');
      // Propagate the child process exit code through cmd.exe.
      batContent.write('exit /B %ERRORLEVEL%\r\n');
      batFile.writeAsStringSync(batContent.toString());
      process = await Process.start(
        batFile.path,
        [],
        workingDirectory: workingDirectory,
        runInShell: false,
        environment: environment.isEmpty ? null : environment,
      );
      // Close Dart's stdin pipe immediately — input comes from the file.
      try { await process.stdin.close(); } catch (_) {}
    } else {
      process = await Process.start(
        invocation.command,
        invocation.args,
        workingDirectory: workingDirectory,
        runInShell: false,
        environment: environment.isEmpty ? null : environment,
      );
      // Non-Windows or no stdin payload — use pipe normally.
      try {
        if (stdinPayload != null) {
          process.stdin.write(stdinPayload);
          await process.stdin.flush();
        }
        await process.stdin.close();
      } catch (_) {}
    }

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'failure',
        command: commandLabel,
        durationMs: elapsedMs,
        errorCode: '$scope.timeout',
        message: 'Process timed out.',
      );
      unawaited(
        DiagnosticsState.instance.recordCommandLatency(
          command: commandLabel,
          ok: false,
          scope: scope,
          roundTripMs: elapsedMs,
          backendDurationMs: elapsedMs,
          errorCode: '$scope.timeout',
        ),
      );
      return null;
    }

    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
    final ok = exitCode == 0;
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: ok ? 'success' : 'failure',
      command: commandLabel,
      durationMs: elapsedMs,
      errorCode: ok ? null : '$scope.exit_$exitCode',
      message: ok ? null : stderr.trim(),
    );
    unawaited(
      DiagnosticsState.instance.recordCommandLatency(
        command: commandLabel,
        ok: ok,
        scope: scope,
        roundTripMs: elapsedMs,
        backendDurationMs: elapsedMs,
        errorCode: ok ? null : '$scope.exit_$exitCode',
      ),
    );
    return _CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr);
  } catch (error) {
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'failure',
      command: commandLabel,
      durationMs: elapsedMs,
      errorCode: '$scope.invoke_failed',
      message: error.toString(),
    );
    unawaited(
      DiagnosticsState.instance.recordCommandLatency(
        command: commandLabel,
        ok: false,
        scope: scope,
        roundTripMs: elapsedMs,
        backendDurationMs: elapsedMs,
        errorCode: '$scope.invoke_failed',
      ),
    );
    return null;
  } finally {
    // Clean up temp files.
    try { stdinTempFile?.deleteSync(); } catch (_) {}
    try { File('${stdinTempFile?.path}.bat').deleteSync(); } catch (_) {}
  }
}

_ProcessInvocation _buildProcessInvocation(String command, List<String> args) {
  if (Platform.isWindows) {
    final lowered = command.toLowerCase();
    if (lowered.endsWith('.ps1')) {
      return _ProcessInvocation(
        command: 'powershell',
        args: [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          command,
          ...args,
        ],
      );
    }
    if (lowered.endsWith('.cmd') || lowered.endsWith('.bat')) {
      // If the command is a bare name (e.g. "opencode.cmd" found via PATH),
      // resolve it to a full path so File() can actually read it.
      var resolvedCmd = command;
      if (!File(command).existsSync()) {
        try {
          final where = Process.runSync('where', [command]);
          if (where.exitCode == 0) {
            final first = (where.stdout as String)
                .split('\n')
                .map((l) => l.trim())
                .firstWhere((l) => l.isNotEmpty, orElse: () => '');
            if (first.isNotEmpty) resolvedCmd = first;
          }
        } catch (_) {}
      }
      // Try to resolve the underlying Node.js script from the .cmd wrapper.
      final nodeInvocation = _tryResolveNodeCmdScript(resolvedCmd);
      if (nodeInvocation != null) {
        final (nodeExe, nodeFlags, scriptPath) = nodeInvocation;

        // Some npm packages (e.g. opencode) ship a Node.js launcher that
        // spawnSync's a platform-native binary. Dart's pipes are incompatible
        // with libuv's stdio inheritance (UV_UNKNOWN on Windows), so try to
        // find and invoke the native binary directly — no Node.js involved.
        final nativeBinary = _tryResolveNativeBinary(scriptPath);
        if (nativeBinary != null) {
          return _ProcessInvocation(command: nativeBinary, args: args);
        }

        // Pure Node.js CLI (gemini, claude, codex, etc.) — run node directly
        // with an expanded heap limit. AI tools regularly exceed V8's default
        // ~4 GB ceiling when processing large diffs. Preserve any node flags
        // from the .cmd wrapper (e.g. --no-warnings=DEP0040 for gemini).
        return _ProcessInvocation(
          command: nodeExe,
          args: [
            '--max-old-space-size=8192',
            ...nodeFlags,
            scriptPath,
            ...args,
          ],
        );
      }
      return _ProcessInvocation(
        command: 'cmd',
        args: ['/C', command, ...args],
      );
    }
  }
  return _ProcessInvocation(command: command, args: args);
}

// Parse a Windows .cmd npm wrapper to extract (nodeExe, nodeFlags, scriptPath).
// Returns null if the file can't be parsed or doesn't look like a node wrapper.
//
// Handles standard npm wrappers like:
//   "%_prog%"  "%dp0%\node_modules\pkg\bin\script" %*
//   "%_prog%" --no-warnings=DEP0040 "%dp0%\...\gemini.js" %*
//   node  "%dp0%\node_modules\pkg\bin\script" %*
//
// Uses string parsing (not regex) to avoid Dart's regex backslash
// escaping issues on Windows.
(String, List<String>, String)? _tryResolveNodeCmdScript(String cmdPath) {
  try {
    final content = File(cmdPath).readAsStringSync();
    final dp0 = p.dirname(cmdPath);

    // Find the line that ends with %* (the actual invocation).
    final lines = content.split('\n');
    String? cmdLine;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.endsWith('%*') || trimmed.endsWith('%*\r')) {
        cmdLine = trimmed;
        break;
      }
    }
    if (cmdLine == null) return null;

    // Extract the quoted script path: the last "%dp0%\..." before %*
    final dp0Token = '%dp0%';
    final scriptStart = cmdLine.lastIndexOf('"$dp0Token');
    if (scriptStart < 0) return null;
    final scriptEnd = cmdLine.indexOf('"', scriptStart + 1);
    if (scriptEnd < 0) return null;

    final rawScript = cmdLine.substring(scriptStart + 1, scriptEnd);

    // Extract node flags: everything between the program close-quote and
    // the script open-quote, split by whitespace, excluding empty tokens.
    final nodeFlags = <String>[];
    final progEnd = cmdLine.indexOf('"$dp0Token');
    // Walk backwards from scriptStart to find the program close-quote.
    // The pattern is: "<prog>" [flags] "<script>"
    // Find the quote that closes the program name before the flags region.
    final beforeScript = cmdLine.substring(0, progEnd).trimRight();
    // Flags are between the last `"` of the program and the script start.
    final lastProgQuote = beforeScript.lastIndexOf('"');
    if (lastProgQuote >= 0 && lastProgQuote < progEnd) {
      final flagsRegion = cmdLine.substring(lastProgQuote + 1, progEnd).trim();
      if (flagsRegion.isNotEmpty) {
        nodeFlags.addAll(
          flagsRegion.split(RegExp(r'\s+')).where((s) => s.isNotEmpty),
        );
      }
    }

    // Resolve %dp0%\ → actual directory
    final scriptPath = rawScript.toLowerCase().startsWith(dp0Token.toLowerCase())
        ? '$dp0${rawScript.substring(dp0Token.length)}'
        : rawScript;

    if (!File(scriptPath).existsSync()) return null;

    // Prefer node.exe next to the .cmd, then fall back to node in PATH.
    final nodeExe = File(p.join(dp0, 'node.exe')).existsSync()
        ? p.join(dp0, 'node.exe')
        : 'node';

    return (nodeExe, nodeFlags, scriptPath);
  } catch (_) {
    return null;
  }
}

/// Given a Node.js launcher script (e.g. opencode's `bin/opencode`), try to
/// find the platform-native binary it wraps.
///
/// Many npm packages ship a small Node.js launcher that discovers and
/// `spawnSync`s a platform-native executable from a sibling `node_modules`
/// package (e.g. `opencode-windows-x64/bin/opencode.exe`). Invoking the
/// native binary directly avoids Node.js entirely, which sidesteps the
/// Dart-pipe ↔ libuv incompatibility (UV_UNKNOWN) on Windows.
String? _tryResolveNativeBinary(String launcherScript) {
  try {
    // Launcher lives at: <pkg>/bin/<name>
    // Package root:      <pkg>/
    final binDir = p.dirname(launcherScript);
    final pkgDir = p.dirname(binDir);
    final name = p.basenameWithoutExtension(launcherScript);

    // Check env override (opencode supports OPENCODE_BIN_PATH).
    final envKey = '${name.toUpperCase()}_BIN_PATH';
    final envPath = Platform.environment[envKey];
    if (envPath != null && File(envPath).existsSync()) return envPath;

    // Check cached binary next to the launcher (e.g. bin/.opencode).
    final cached = p.join(binDir, '.$name');
    if (File(cached).existsSync()) return cached;
    final cachedExe = p.join(binDir, '.$name.exe');
    if (File(cachedExe).existsSync()) return cachedExe;

    // Detect platform + arch to build candidate package names.
    final platform = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
            ? 'darwin'
            : 'linux';
    final arch = _detectArch();
    final exe = platform == 'windows' ? '$name.exe' : name;

    // Candidate names, ordered by preference (match launcher's own logic).
    final candidates = <String>[
      '$name-$platform-$arch',
      if (arch == 'x64') '$name-$platform-$arch-baseline',
    ];

    // Walk up from pkgDir looking in node_modules/ at each level.
    var current = pkgDir;
    for (var depth = 0; depth < 5; depth++) {
      final modules = p.join(current, 'node_modules');
      if (Directory(modules).existsSync()) {
        for (final candidate in candidates) {
          final binary = p.join(modules, candidate, 'bin', exe);
          if (File(binary).existsSync()) return binary;
        }
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }

    return null;
  } catch (_) {
    return null;
  }
}

String _detectArch() {
  // Dart doesn't expose CPU arch directly. Use Platform.version which
  // contains the arch on all platforms, or infer from pointer size.
  final version = Platform.version.toLowerCase();
  if (version.contains('arm64') || version.contains('aarch64')) return 'arm64';
  if (version.contains('arm')) return 'arm';
  return 'x64';
}

_ProviderAuthStatus _providerAuthStatus(_ProviderKind kind) {
  switch (kind) {
    case _ProviderKind.codex:
      return _codexAuthStatus();
    case _ProviderKind.claude:
      return _claudeAuthStatus();
    case _ProviderKind.gemini:
      return _geminiAuthStatus();
    case _ProviderKind.openCode:
      return _openCodeAuthStatus();
  }
}

_ProviderAuthStatus _codexAuthStatus() {
  final value = _readJsonFile(_codexAuthPath());
  if (value == null) {
    return const _ProviderAuthStatus(
      ok: false,
      detail: 'missing ~/.codex/auth.json',
    );
  }

  final tokens = value['tokens'];
  final idToken = tokens is Map ? tokens['id_token'] as String? : null;
  final accessToken = tokens is Map ? tokens['access_token'] as String? : null;
  final planType =
      idToken == null ? null : _extractCodexPlanFromIdToken(idToken);
  final planName = planType == null ? null : _humanizeLabel(planType);
  final hasToken = [idToken, accessToken].any(
    (token) => token != null && token.trim().isNotEmpty,
  );

  return _ProviderAuthStatus(
    ok: hasToken,
    detail: hasToken
        ? planName != null
            ? 'codex auth token found ($planName)'
            : 'codex auth token found'
        : 'codex token missing',
    planName: planName,
  );
}

_ProviderAuthStatus _claudeAuthStatus() {
  final path = _claudeCredentialsPath();
  if (path == null) {
    return const _ProviderAuthStatus(
      ok: false,
      detail: 'home directory unavailable',
    );
  }

  final credentials = _readClaudeOAuthCredentials(path);
  if (credentials == null) {
    return const _ProviderAuthStatus(
      ok: false,
      detail: 'missing ~/.claude/.credentials.json',
    );
  }

  final ok = credentials.hasAccessToken && credentials.hasInferenceScope;
  final planName = ok ? _humanizeLabel(credentials.subscriptionType) : null;
  return _ProviderAuthStatus(
    ok: ok,
    detail: ok
        ? 'claude oauth ready (${credentials.subscriptionType})'
        : 'claude oauth missing token or user:inference scope',
    planName: planName,
  );
}

_ProviderAuthStatus _geminiAuthStatus() {
  final homeDir = _userHomeDir();
  if (homeDir == null) {
    return const _ProviderAuthStatus(
      ok: false,
      detail: 'home directory unavailable',
    );
  }

  final value = _readJsonFile(p.join(homeDir, '.gemini', 'oauth_creds.json'));
  if (value == null) {
    return const _ProviderAuthStatus(
      ok: false,
      detail: 'missing ~/.gemini/oauth_creds.json',
    );
  }

  final accessToken = value['access_token'] as String?;
  final hasToken = accessToken != null && accessToken.trim().isNotEmpty;
  final planName =
      hasToken ? _geminiAccountLabel(homeDir) ?? 'Google AI' : null;
  return _ProviderAuthStatus(
    ok: hasToken,
    detail:
        hasToken ? 'gemini oauth token found' : 'gemini oauth token missing',
    planName: planName,
  );
}

_ProviderAuthStatus _openCodeAuthStatus() {
  for (final path in _openCodeAuthPaths()) {
    final value = _readJsonFile(path);
    if (value == null) {
      continue;
    }

    if (value.isNotEmpty) {
      final count = value.length;
      return _ProviderAuthStatus(
        ok: true,
        detail: 'opencode connected providers=$count',
        planName: '$count provider${count == 1 ? '' : 's'}',
      );
    }

    return const _ProviderAuthStatus(
      ok: true,
      detail: 'opencode auth file present',
      planName: 'Connected',
    );
  }

  return const _ProviderAuthStatus(
    ok: true,
    detail: 'opencode auth managed by CLI',
    planName: 'Connected',
  );
}

Map<String, dynamic>? _readJsonFile(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

_ClaudeOAuthCredentials? _readClaudeOAuthCredentials(String path) {
  final value = _readJsonFile(path);
  final oauth = value?['claudeAiOauth'];
  if (oauth is! Map) {
    return null;
  }

  final accessToken = oauth['accessToken'] as String?;
  final scopes = oauth['scopes'];
  return _ClaudeOAuthCredentials(
    hasAccessToken: accessToken != null && accessToken.trim().isNotEmpty,
    subscriptionType: (oauth['subscriptionType'] as String?) ?? 'unknown',
    hasInferenceScope: scopes is List &&
        scopes.any((scope) => scope is String && scope == 'user:inference'),
  );
}

String? _extractCodexPlanFromIdToken(String idToken) {
  try {
    final parts = idToken.split('.');
    final segment = parts.length > 1 ? parts[1] : null;
    if (segment == null || segment.isEmpty) {
      return null;
    }
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(segment)));
    final payload = jsonDecode(decoded);
    if (payload is! Map) {
      return null;
    }
    final auth = payload['https://api.openai.com/auth'];
    if (auth is! Map) {
      return null;
    }
    final plan = auth['chatgpt_plan_type'];
    return plan is String && plan.trim().isNotEmpty ? plan : null;
  } catch (_) {
    return null;
  }
}

String? _geminiAccountLabel(String homeDir) {
  final settings = _readJsonFile(p.join(homeDir, '.gemini', 'settings.json'));
  final security = settings?['security'];
  final auth = security is Map ? security['auth'] : null;
  final selectedType = auth is Map ? auth['selectedType'] as String? : null;
  switch (selectedType) {
    case 'oauth-personal':
      return 'Google AI';
    case 'oauth-adc':
      return 'Cloud ADC';
    case 'service-account':
      return 'Service Account';
    case 'api-key':
      return 'API Key';
    case null:
      return null;
    default:
      return 'Connected';
  }
}

String _buildModelDescription({
  required String providerId,
  required String? planName,
  required String? detail,
}) {
  final base =
      planName == null ? 'via $providerId' : '$planName via $providerId';
  if (detail == null || detail.trim().isEmpty) {
    return base;
  }
  return '$base | ${detail.trim()}';
}

List<String> _rankModelsForCategory(
  List<String> models,
  List<String> hintTokens,
) {
  final prioritized = <String>[];
  final remaining = <String>[];
  final seen = <String>{};

  for (final model in models) {
    final key = _normalizeModelKey(model);
    if (!seen.add(key)) {
      continue;
    }
    if (_modelMatchesAnyHint(model, hintTokens)) {
      prioritized.add(model);
    } else {
      remaining.add(model);
    }
  }

  if (prioritized.isEmpty) {
    return [...models];
  }

  return [...prioritized, ...remaining];
}

bool _modelMatchesAnyHint(String modelId, List<String> hintTokens) {
  if (hintTokens.isEmpty) {
    return true;
  }
  final normalized = modelId.toLowerCase();
  return hintTokens.any((hint) => normalized.contains(hint));
}

String _normalizeModelKey(String modelId) {
  final parts = modelId.split('/');
  final bare = parts.isNotEmpty ? parts.last : modelId;
  return bare.replaceAll('.', '-').replaceAll('_', '-').toLowerCase();
}

String _humanizeLabel(String value) {
  return value
      .split(RegExp(r'[-_ ]+'))
      .where((segment) => segment.isNotEmpty)
      .map(
        (segment) =>
            '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _stripAnsi(String value) {
  final buffer = StringBuffer();
  final iterator = value.runes.iterator;
  while (iterator.moveNext()) {
    final rune = iterator.current;
    if (rune == 0x1B) {
      if (iterator.moveNext() && iterator.current == 0x5B) {
        while (iterator.moveNext()) {
          final current = iterator.current;
          if (current >= 0x40 && current <= 0x7E) {
            break;
          }
        }
        continue;
      }
    }
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

String _codexAuthPath() {
  final codexHome = Platform.environment['CODEX_HOME'];
  if (codexHome != null && codexHome.trim().isNotEmpty) {
    return p.join(codexHome, 'auth.json');
  }
  return _codexConfigPath().replaceAll('config.toml', 'auth.json');
}

String _codexConfigPath() {
  final codexHome = Platform.environment['CODEX_HOME'];
  if (codexHome != null && codexHome.trim().isNotEmpty) {
    return p.join(codexHome, 'config.toml');
  }
  final homeDir = _userHomeDir() ?? '.';
  return p.join(homeDir, '.codex', 'config.toml');
}

String? _claudeCredentialsPath() {
  final homeDir = _userHomeDir();
  return homeDir == null
      ? null
      : p.join(homeDir, '.claude', '.credentials.json');
}

List<String> _openCodeAuthPaths() {
  final paths = <String>[];
  final homeDir = _userHomeDir();
  if (homeDir != null) {
    paths.add(p.join(homeDir, '.local', 'share', 'opencode', 'auth.json'));
  }

  final appData = Platform.environment['APPDATA'];
  if (appData != null && appData.trim().isNotEmpty) {
    paths.add(p.join(appData, 'opencode', 'auth.json'));
  }

  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData != null && localAppData.trim().isNotEmpty) {
    paths.add(p.join(localAppData, 'opencode', 'auth.json'));
  }
  return paths;
}

String? _userHomeDir() {
  final home = Platform.environment['HOME'];
  if (home != null && home.trim().isNotEmpty) {
    return home;
  }

  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile != null && userProfile.trim().isNotEmpty) {
    return userProfile;
  }

  return null;
}

class _TimedValue<T> {
  final DateTime checkedAt;
  final T value;
  const _TimedValue({required this.checkedAt, required this.value});
}

class _BinaryCandidate {
  final String command;
  final String source;
  const _BinaryCandidate({required this.command, required this.source});
}

class _ProviderResolution {
  final String command;
  final String source;
  final String healthCheck;
  const _ProviderResolution({
    required this.command,
    required this.source,
    required this.healthCheck,
  });
}

class _ProviderAvailability {
  final bool ready;
  final _ProviderResolution? resolution;
  final _ProviderAuthStatus auth;
  const _ProviderAvailability({
    required this.ready,
    required this.resolution,
    required this.auth,
  });
}

class _ProviderAuthStatus {
  final bool ok;
  final String detail;
  final String? planName;
  const _ProviderAuthStatus({
    required this.ok,
    required this.detail,
    this.planName,
  });
}

class _ProviderModelDiscovery {
  final List<String> models;
  final Map<String, String> modelDetails;
  const _ProviderModelDiscovery({
    required this.models,
    required this.modelDetails,
  });
}

class _ProviderModelCollection {
  final String providerId;
  final _ProviderKind kind;
  final String? planName;
  final List<String> models;
  final Map<String, String> modelDetails;

  const _ProviderModelCollection({
    required this.providerId,
    required this.kind,
    required this.planName,
    required this.models,
    required this.modelDetails,
  });
}

class _ModelCategoryTemplate {
  final String id;
  final String label;
  final String description;
  final List<String> hintTokens;

  const _ModelCategoryTemplate({
    required this.id,
    required this.label,
    required this.description,
    required this.hintTokens,
  });
}

class _CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const _CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

class _ProcessInvocation {
  final String command;
  final List<String> args;
  const _ProcessInvocation({required this.command, required this.args});
}

class _ProviderSpec {
  final String id;
  final String binary;
  final _ProviderKind kind;
  const _ProviderSpec({
    required this.id,
    required this.binary,
    required this.kind,
  });
}

class _ProviderAttempt {
  final String name;
  final List<String> args;
  final _ProviderOutputMode outputMode;
  final bool useStdinForPrompt;

  const _ProviderAttempt({
    required this.name,
    required this.args,
    required this.outputMode,
    this.useStdinForPrompt = true,
  });
}

class _ProviderPromptResult {
  final bool ok;
  final String? output;
  final String? error;
  final String outputPreview;

  const _ProviderPromptResult({
    required this.ok,
    this.output,
    this.error,
    required this.outputPreview,
  });
}

class _ClaudeOAuthCredentials {
  final bool hasAccessToken;
  final String subscriptionType;
  final bool hasInferenceScope;
  const _ClaudeOAuthCredentials({
    required this.hasAccessToken,
    required this.subscriptionType,
    required this.hasInferenceScope,
  });
}

class _CommitDiffContext {
  final String branchName;
  final String statusSummary;
  final String statSummary;
  final _DiffPromptBundle diffBundle;
  final int totalCommits;
  final String recentLog;
  final String authorName;
  final String lastCommitAge;
  final String projectAge;
  final int uniqueContributors;

  const _CommitDiffContext({
    required this.branchName,
    required this.statusSummary,
    required this.statSummary,
    required this.diffBundle,
    this.totalCommits = 0,
    this.recentLog = '',
    this.authorName = '',
    this.lastCommitAge = '',
    this.projectAge = '',
    this.uniqueContributors = 0,
  });
}

class _CommitDiffContextResult {
  final _CommitDiffContext? data;
  final String? error;
  bool get ok => error == null;

  const _CommitDiffContextResult.ok(this.data) : error = null;
  const _CommitDiffContextResult.err(this.error) : data = null;
}

class _ReviewPromptSpec {
  final String branchName;
  final String modelCategoryLabel;
  final String scopeLabel;
  final String customPrompt;
  final String statusSummary;
  final String statSummary;
  final String diffSummary;
  final _ReviewPassMode passMode;
  final String? priorReview;

  const _ReviewPromptSpec({
    required this.branchName,
    required this.modelCategoryLabel,
    required this.scopeLabel,
    required this.customPrompt,
    required this.statusSummary,
    required this.statSummary,
    required this.diffSummary,
    required this.passMode,
    this.priorReview,
  });
}

class _DiffPromptBundle {
  final String promptBody;
  final bool usedCondensedDiff;
  final int originalDiffCharacters;

  const _DiffPromptBundle({
    required this.promptBody,
    required this.usedCondensedDiff,
    required this.originalDiffCharacters,
  });
}

class _ParsedReviewResult {
  final String verdict;
  final int score;
  final String summary;
  final String reasoningReport;
  final List<AiCommitReviewFindingData> findings;

  const _ParsedReviewResult({
    required this.verdict,
    required this.score,
    required this.summary,
    required this.reasoningReport,
    required this.findings,
  });
}

class _MergedReviewResult {
  final String verdict;
  final int score;
  final String summary;
  final String reasoningReport;
  final List<AiCommitReviewFindingData> findings;

  const _MergedReviewResult({
    required this.verdict,
    required this.score,
    required this.summary,
    required this.reasoningReport,
    required this.findings,
  });
}

class _ParsedDiffFile {
  final String path;
  int additions = 0;
  int deletions = 0;
  final List<_ParsedDiffHunk> hunks;

  _ParsedDiffFile({
    required this.path,
    List<_ParsedDiffHunk>? hunks,
  }) : hunks = hunks ?? [];
}

class _ParsedDiffHunk {
  final String header;
  final List<String> samples;

  _ParsedDiffHunk({required this.header, required this.samples});

  void pushSample(String value) {
    if (samples.length >= 10 || value.trim().isEmpty) {
      return;
    }
    samples.add(value);
  }
}

enum _ProviderKind { codex, claude, gemini, openCode }

enum _ProviderOutputMode {
  plainText,
  codexJsonl,
  claudeJson,
  geminiJson,
  openCodeJsonl,
}

enum _ReviewPassMode { draft, verify }

enum ReviewConcernClass {
  logicBug,
  regressionRisk,
  integrationMismatch,
  redundantPattern,
  inconsistentPattern,
  hiddenAssumption,
  maintainabilityHazard,
  destructiveRisk,
  securityRisk,
  stateCorruptionRisk,
}

class ReviewGuardrailProfile {
  final String id;
  final String seat;
  final String reviewRadius;
  final String primaryFear;
  final String silenceRule;
  final String verdictBar;
  final List<ReviewConcernClass> priorityConcernClasses;
  final List<ReviewConcernClass> suppressedConcernClasses;
  final bool allowIntegrationEscalation;
  final bool allowDesignSmellEscalation;
  final bool requireConcreteEvidence;

  const ReviewGuardrailProfile({
    required this.id,
    required this.seat,
    required this.reviewRadius,
    required this.primaryFear,
    required this.silenceRule,
    required this.verdictBar,
    required this.priorityConcernClasses,
    required this.suppressedConcernClasses,
    required this.allowIntegrationEscalation,
    required this.allowDesignSmellEscalation,
    required this.requireConcreteEvidence,
  });
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
