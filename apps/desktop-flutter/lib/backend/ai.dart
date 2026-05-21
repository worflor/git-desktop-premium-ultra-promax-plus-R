import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'ai_api_keys_store.dart';
import 'ai_api_provider.dart';
import 'ai_audit_store.dart';
import 'storage_paths.dart';
import '../diagnostics/diagnostics_state.dart';
import 'commit_format.dart';
import 'dtos.dart';
import 'engram_bootstrap.dart';
import 'engram_brain.dart' show EngramWellMatch;
import 'engram_file_ktable.dart';
import 'engram_text_kspace.dart';
import 'logos_vis_events.dart';
import 'git.dart';
import 'git_result.dart';
import 'process_utils.dart';
import 'win_job_object.dart';
import 'package:meta/meta.dart';

import 'ai_context_engine.dart';
import 'logos_branch_orbit.dart'
    show logosTemperatureMultiplierFromOrbit, probeLogosBranchOrbit;
import 'logos_git.dart';
import 'logos_git_calibration.dart';
import 'logos_mind.dart';
import 'logos_git_diagnostics.dart';
import 'logos_semantic_bands.dart';
import 'logos_git_probe.dart';
import 'logos_git_resolver.dart';
import 'logos_sensitivity.dart';
import 'file_coupling.dart' show FileCouplingMatrix, SymbolFrequencyIndex;
import 'logos_chunks.dart' as chunks;
import 'logos_diff_attention.dart' as diff_attention;
import 'logos_flow.dart'
    show
        analyzeFlowCached,
        anchorFingerprint,
        logosFingerCoupling,
        FlowAnalysisResult,
        FlowFinding,
        FlowBugKind;
import 'logos_hunks.dart' as hunks;
import 'semantic_manifest.dart' show buildSemanticManifest;

const _cliProviderSpecs = <_ProviderSpec>[
  _ProviderSpec(id: 'codex', binary: 'codex', kind: _ProviderKind.codex),
  _ProviderSpec(id: 'claude', binary: 'claude', kind: _ProviderKind.claude),
  _ProviderSpec(id: 'gemini', binary: '', kind: _ProviderKind.geminiApi),
  _ProviderSpec(
    id: 'opencode',
    binary: 'opencode',
    kind: _ProviderKind.openCode,
  ),
];

final Set<String> cliProviderIds =
    Set.unmodifiable(_cliProviderSpecs.map((s) => s.id));

List<_ProviderSpec> _allProviderSpecs = List.unmodifiable(_cliProviderSpecs);
AiApiKeysSnapshot _apiKeysSnapshot = AiApiKeysSnapshot.empty();

List<_ProviderSpec> get _providerSpecs => _allProviderSpecs;

Future<void> loadApiProviderKeys() async {
  _apiKeysSnapshot = await AiApiKeysStore.load();
  _rebuildApiProviderSpecs();
}

Future<void> updateApiProviderKey(
  String providerId,
  AiApiKeyEntry entry,
) async {
  _apiKeysSnapshot = _apiKeysSnapshot.withEntry(providerId, entry);
  await AiApiKeysStore.persist(_apiKeysSnapshot);
  _rebuildApiProviderSpecs();
  _providerAvailabilityCache.remove(providerId);
  _providerModelDiscoveryCache.remove(providerId);
  _deleteApiModelCacheFromDisk(providerId);
}

Future<void> removeApiProviderKey(String providerId) async {
  _apiKeysSnapshot = _apiKeysSnapshot.withoutEntry(providerId);
  await AiApiKeysStore.persist(_apiKeysSnapshot);
  _rebuildApiProviderSpecs();
  _providerAvailabilityCache.remove(providerId);
  _providerModelDiscoveryCache.remove(providerId);
  _deleteApiModelCacheFromDisk(providerId);
}

void _deleteApiModelCacheFromDisk(String providerId) {
  Future(() async {
    try {
      final dir = await _apiModelCacheDir();
      final file = File(p.join(dir.path, '$providerId.json'));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  });
}

AiApiKeysSnapshot get currentApiKeys => _apiKeysSnapshot;

void _rebuildApiProviderSpecs() {
  final specs = <_ProviderSpec>[];
  for (final provider in aiApiProviderRegistry) {
    final entry = _apiKeysSnapshot[provider.id];
    if (entry != null && entry.apiKey.trim().isNotEmpty) {
      specs.add(_ProviderSpec(
        id: provider.id,
        binary: '',
        kind: _ProviderKind.apiProvider,
        apiProvider: provider,
      ));
    }
  }
  _allProviderSpecs = List.unmodifiable([..._cliProviderSpecs, ...specs]);
}

const _defaultModelCategories = <_ModelCategoryTemplate>[
  _ModelCategoryTemplate(
    id: 'quality',
    label: 'Quality',
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
    label: 'Fast',
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
// Per-attempt deadline for a provider CLI call. Opus with extended
// thinking on large prompts can need 10–15 minutes. 20 min per
// attempt covers the slow tail while still bounding hangs.
const _providerRuntimeTimeout = Duration(minutes: 20);
const _gitCommandTimeout = Duration(seconds: 30);
const _modelDiscoveryTimeout = Duration(seconds: 8);
const _openCodeVerboseDiscoveryTimeout = Duration(seconds: 15);
const _maxPromptChars = 260000;

/// Single budget for the diff section of the prompt body. Replaces the
/// old two-mode design (full ≤220K → raw text; >220K → condensed
/// 180K hunk pack). The diff now flows through ONE pipeline regardless
/// of size: parse → φ-rank hunks → knapsack-admit until this budget
/// exhausts. When the natural diff fits comfortably, all hunks admit
/// and the output is structurally equivalent to a full-diff emission.
/// When it doesn't, the same machinery drops lower-φ hunks. No mode
/// switch, no threshold; budget is the single dial.
const _kDiffBudgetChars = 180000;

/// Model-API reservations — character counts the prompt template
/// itself eats, plus the response space we have to leave for the model.
/// Both are model-contract properties, not UX knobs:
///   • `_kReviewOverheadChars` — system prompt + evidence rules + XML
///     schema + structural framing + custom prompt for the *review*
///     and *commit-message* templates. Measured from actual prompt
///     builds: 8–14K depending on guardrail profile and custom prompt.
///   • `_kSynthesisOverheadChars` — same idea for the *Muse synthesis*
///     template (charter + output schema + brainstorm-ideas recap).
///     A bit smaller since synthesis doesn't carry the review's
///     fearfulness ladder + verdict bar instructions.
///   • `_kModelOutputReservation` — fraction of the context window the
///     model needs for its OWN response. Property of the model API,
///     not Logos-derivable.
const _kReviewOverheadChars = 12000;
const _kSynthesisOverheadChars = 9000;
const _kModelOutputReservation = 0.10;

final Map<String, _TimedValue<_ProviderResolution?>> _providerResolutionCache =
    {};
final Map<String, _TimedValue<_ProviderAvailability>>
    _providerAvailabilityCache = {};
final Map<String, _TimedValue<_ProviderModelDiscovery?>>
    _providerModelDiscoveryCache = {};

const _modelValueSeparator = ':';
const _diffStatWidth = 140;
const _diffTimeoutSeconds = 50;
const _previewMaxLength = 800;
const _truncationSuffix = '...';
const _findingOriginDraft = 'draft';
const _findingIdPrefixDraft = 'F';
const _findingIdPrefixVerification = 'V';
const _unknownPlaceholder = '-';

final _modelAssignmentRegex = RegExp(r'^model\s*=');
final _migrationEntryRegex = RegExp(r'^"([^"]+)"\s*=\s*"([^"]+)"');
final _findingTagRegex = RegExp(
  r'<finding\b([^>]*)>([\s\S]*?)</finding>',
  caseSensitive: false,
);
final _observationTagRegex = RegExp(
  r'<observation\b([^>]*)>([\s\S]*?)</observation>',
  caseSensitive: false,
);
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
          modelPricing: discovery.modelPricing,
          reasoningModels: discovery.reasoningModels,
          fastModels: discovery.fastModels,
        );
      }),
    );
    final readyProviders =
        providerResults.whereType<_ProviderModelCollection>().toList();

    final modelDetailsByKey = <String, String>{};
    final modelPricingByKey = <String, (double?, double?)>{};
    final directProviderModelKeys = <String>{};
    for (final provider in readyProviders) {
      modelDetailsByKey.addAll(provider.modelDetails);
      modelPricingByKey.addAll(provider.modelPricing);
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

          final isApiProvider = provider.kind == _ProviderKind.apiProvider;
          final price = isApiProvider
              ? (provider.modelPricing[key] ?? modelPricingByKey[key])
              : null;
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
              promptPricePer1m: price?.$1,
              completionPricePer1m: price?.$2,
              supportsReasoning: provider.reasoningModels.contains(key),
              hasFastTier: provider.fastModels.contains(key),
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
  String? reasoningEffort,
  bool fastMode = false,
  bool supportsReasoning = true,
  required bool includeStaged,
  required bool includeUnstaged,
  List<String> scopedPaths = const [],
  String customPrompt = '',
  String existingMessage = '',
  bool readOnly = true,
  // Commit format preferences. Caller (the commit composer) threads
  // these from PreferencesState; the prompt builder turns them into
  // inline instructions so the AI's output respects the user's chosen
  // structure/voice/coverage.
  CommitStructure structure = kDefaultCommitStructure,
  CommitVoice voice = kDefaultCommitVoice,
  CommitCoverage coverage = kDefaultCommitCoverage,
  // Semantic priors for the manifest above the packed diff. Pass from
  // the app layer's SymbolFrequencyState / FileCouplingState. Both are
  // optional; null = skip that signal, manifest still emits.
  SymbolFrequencyIndex? symbolIndex,
  FileCouplingMatrix? couplingMatrix,
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
      symbolIndex: symbolIndex,
      couplingMatrix: couplingMatrix,
    );

    if (!diffContext.ok) {
      return GitResult.err(diffContext.error!);
    }

    final bundle = diffContext.data!;
    // Logos shape signal — lets the LLM pick scope/voice/coverage from
    // the diff's own attention regime. Null is fine (engine cold-start).
    final commitShape = await _collectLogosCommitShape(
      repositoryPath: repositoryPath,
      diffText: bundle.diffBundle.promptBody,
    );
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
      structure: structure,
      voice: voice,
      coverage: coverage,
      logosShape: commitShape,
    );

    final providerResult = await _runProviderPrompt(
      provider: provider,
      resolution: availability.resolution!,
      modelId: modelId,
      prompt: prompt,
      repositoryPath: repositoryPath,
      readOnly: readOnly,
      reasoningEffort: reasoningEffort,
      fastMode: fastMode,
      supportsReasoning: supportsReasoning,
    );
    if (!providerResult.ok || providerResult.output == null) {
      return GitResult.err(
          providerResult.error ?? 'Provider did not return a commit message.');
    }

    final message = _normalizeCommitMessage(providerResult.output!);
    if (message.isEmpty) {
      return GitResult.err('Provider returned an empty commit message.');
    }

    return GitResult.ok(
      AiCommitMessageData(
        providerId: provider.id,
        modelId: modelId,
        message: message,
        scopeLabel: scopeLabel,
        promptCharacters: prompt.length,
        diffCharacters: bundle.diffBundle.originalDiffCharacters,
        inputTokens: providerResult.inputTokens,
        outputTokens: providerResult.outputTokens,
      ),
    );
  } catch (error) {
    return GitResult.err('Commit message generation failed: $error');
  }
}

/// One-shot "context → unified diff" primitive. Caller builds the
/// [prompt] from whatever context is relevant (conflicted files, a
/// dirty tree diff + English intent, a stale patch + live tree, …),
/// provides the [modelValue] (`provider:modelId` as used by all other
/// AI calls), and gets back raw `.patch` text the caller can hand to
/// `applyPatch(..., dryRun: true)` to verify. Code fences (```diff …)
/// are stripped so downstream only ever sees clean `--- a/ +++ b/`
/// headers regardless of how the model decided to frame its output.
/// This function deliberately stays dumb about WHAT context went in —
/// the clever context engineering lives at call sites. Keeping the
/// primitive generic lets the merge resolver, NL partial staging, and
/// future patch-emitting features all share the same transport.
Future<GitResult<AiPatchData>> generatePatch({
  required String repositoryPath,
  required String modelValue,
  required String prompt,
  String commandLabelPrefix = 'ai.patch',
  bool readOnly = true,
}) async {
  try {
    if (prompt.trim().isEmpty) {
      return GitResult.err('Prompt is empty.');
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

    if (provider.kind == _ProviderKind.geminiApi) {
      final geminiModel = modelId.startsWith('gemini ')
          ? modelId.substring('gemini '.length)
          : modelId;
      final apiResult = await _runGeminiApiRequest(prompt, geminiModel);
      if (apiResult.text == null) {
        return GitResult.err(
            apiResult.error ?? 'Gemini API returned no response.');
      }
      final patch = _extractPatchFromModelOutput(apiResult.text!);
      if (patch.isEmpty) {
        return GitResult.err('Model returned no usable patch.');
      }
      return GitResult.ok(AiPatchData(
        providerId: provider.id,
        modelId: modelId,
        patch: patch,
        promptCharacters: prompt.length,
        patchCharacters: patch.length,
        inputTokens: apiResult.inputTokens,
        outputTokens: apiResult.outputTokens,
      ));
    }

    final attempts = _buildProviderAttempts(
      provider.kind,
      modelId,
      readOnly: readOnly,
      resolvedCommand: availability.resolution!.command,
    );
    String? providerOutput;
    String? lastError;
    for (final attempt in attempts) {
      final effectiveArgs =
          attempt.useStdinForPrompt ? attempt.args : [...attempt.args, prompt];
      final effectiveStdin = attempt.useStdinForPrompt ? prompt : null;
      final result = await _runObservedProcess(
        commandLabel: '$commandLabelPrefix.${provider.id}.${attempt.name}',
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
      return GitResult.err(lastError ?? 'Provider did not return a patch.');
    }
    final patch = _extractPatchFromModelOutput(providerOutput);
    if (patch.isEmpty) {
      return GitResult.err('Model returned no usable patch.');
    }
    return GitResult.ok(AiPatchData(
      providerId: provider.id,
      modelId: modelId,
      patch: patch,
      promptCharacters: prompt.length,
      patchCharacters: patch.length,
    ));
  } catch (error) {
    return GitResult.err('Patch generation failed: $error');
  }
}

/// Prose-returning AI call for the "ask the manifold" feature —
/// general question-answering where the model's job is explanation,
/// not code generation. Reuses [generatePatch]'s provider attempt
/// loop but skips the patch-extraction step; the caller gets the
/// raw model output text to render inline.
///
/// `readOnly` stays true by default — Ask never writes code.
Future<GitResult<String>> runAsk({
  required String repositoryPath,
  required String modelValue,
  required String prompt,
  String? reasoningEffort,
  bool fastMode = false,
  bool supportsReasoning = true,
  String commandLabelPrefix = 'ai.ask',
  int? maxTokens,
}) async {
  try {
    if (prompt.trim().isEmpty) {
      return GitResult.err('Question is empty.');
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

    final result = await _runProviderPrompt(
      provider: provider,
      resolution: availability.resolution!,
      modelId: modelId,
      prompt: prompt,
      repositoryPath: repositoryPath,
      reasoningEffort: reasoningEffort,
      fastMode: fastMode,
      supportsReasoning: supportsReasoning,
      maxTokens: maxTokens,
    );
    if (!result.ok || result.output == null) {
      return GitResult.err(result.error ?? 'Provider returned no answer.');
    }
    return GitResult.ok(result.output!.trim());
  } catch (error) {
    return GitResult.err('Ask failed: $error');
  }
}

/// Logos-guided hypothesis-conditioned debugging engine.
///
/// Takes a messy symptom string + optional prior rounds and produces
/// structured, falsifiable hypotheses. Each round is one Logos
/// retrieval + one LLM shot — non-agentic, human-in-the-loop.
///
/// Logos decides WHAT evidence to look at (MindQuery.text for round 1,
/// MindQuery.weighted from prior suspect files for round 2+). The model
/// does CAUSAL REASONING on Logos-selected evidence. Output is always
/// structured: hypothesis + invariant + evidence + falsifier.
Future<GitResult<AiDebugData>> runDebug({
  required String repositoryPath,
  required String modelValue,
  required String symptom,
  String? reasoningEffort,
  bool fastMode = false,
  bool supportsReasoning = true,
  List<DebugRound> priorRounds = const [],
  String userAnswer = '',
}) async {
  try {
    if (symptom.trim().isEmpty) {
      return GitResult.err('Symptom description is empty.');
    }
    final modelParse = _parseModelValue(modelValue);
    if (!modelParse.ok) return GitResult.err(modelParse.error!);
    final provider = modelParse.data!.provider;
    final modelId = modelParse.data!.modelId;

    final availability = await _inspectProviderCached(provider);
    if (!availability.ready || availability.resolution == null) {
      return GitResult.err(
        'Provider ${provider.id} is not ready. ${_formatProviderHealth(availability)}',
      );
    }

    final engine = await resolveLogosGit(repositoryPath);
    if (engine == null) {
      return GitResult.err('Logos engine not ready for this repository.');
    }

    final mind = LogosMind(engine: engine);
    final round = priorRounds.length + 1;

    // Logos retrieval: symptom-seeded (R1) or hypothesis-weighted (R2+).
    MindResponse response;
    double temperature;
    if (priorRounds.isEmpty) {
      temperature = 0.5;
      response = mind.ask(
        MindQuery.text(symptom),
        temperature: temperature,
        topN: 12,
      );
    } else {
      temperature = 1.5;
      final weights = <String, double>{};
      for (final h in priorRounds.last.hypotheses) {
        for (final src in h.sources) {
          weights[src.path] =
              (weights[src.path] ?? 0) + src.score * h.confidence;
        }
      }
      if (weights.isEmpty) {
        response = mind.ask(
          MindQuery.text('$symptom $userAnswer'),
          temperature: temperature,
          topN: 16,
        );
      } else {
        response = mind.ask(
          MindQuery.weighted(weights),
          temperature: temperature,
          topN: 16,
        );
      }
    }

    // Fallback chain if Logos text query found nothing:
    // 1. git grep for symptom keywords
    // 2. Recently changed files as a last resort
    if (response.candidates.isEmpty) {
      final keywords = symptom
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9_]+'))
          .where((t) => t.length >= 3)
          .take(8)
          .toList();
      if (keywords.isNotEmpty) {
        try {
          final grepResult = await Process.run(
            'git',
            [
              'grep', '-l', '-i', '--all-match',
              ...keywords.expand((k) => ['-e', k]),
            ],
            workingDirectory: repositoryPath,
          );
          if (grepResult.exitCode == 0) {
            final paths = (grepResult.stdout as String)
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .take(12)
                .toList();
            if (paths.isNotEmpty) {
              final weights = <String, double>{
                for (final p in paths) p: 1.0,
              };
              response = mind.ask(
                MindQuery.weighted(weights),
                temperature: 0.8,
                topN: 12,
              );
            }
          }
        } catch (_) {}
      }
    }

    // Last resort: use recently changed files as seeds.
    if (response.candidates.isEmpty) {
      try {
        final logResult = await Process.run(
          'git',
          ['log', '--oneline', '-20', '--name-only', '--format='],
          workingDirectory: repositoryPath,
        );
        if (logResult.exitCode == 0) {
          final paths = (logResult.stdout as String)
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toSet()
              .take(15)
              .toList();
          if (paths.isNotEmpty) {
            final weights = <String, double>{
              for (final p in paths) p: 0.5,
            };
            response = mind.ask(
              MindQuery.weighted(weights),
              temperature: 1.5,
              topN: 12,
            );
          }
        }
      } catch (_) {}
    }

    // Read file content for top candidates under budget.
    // If Logos/grep found nothing, we still proceed — the model gets
    // the symptom + repo structure context and can still hypothesize.
    const fileBudget = 120000;
    var remaining = fileBudget;
    final fileContents = <String, String>{};
    for (final cand in response.candidates) {
      if (remaining <= 0) break;
      if (isSensitivePath(cand.path)) continue;
      try {
        final file = File(p.join(repositoryPath, cand.path));
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        final toInclude =
            content.length > remaining ? content.substring(0, remaining) : content;
        fileContents[cand.path] = toInclude;
        remaining -= toInclude.length;
      } catch (_) {
        continue;
      }
    }

    // Build prompt.
    final prompt = _buildDebugPrompt(
      symptom: symptom,
      candidates: response.candidates,
      fileContents: fileContents,
      priorRounds: priorRounds,
      userAnswer: userAnswer,
    );

    final secretHit = detectLikelySecretInPrompt(prompt);
    if (secretHit != null) {
      return GitResult.err(
          'Blocked — evidence files contain what looks like a $secretHit.');
    }

    final effort = fastMode || !supportsReasoning ? null : reasoningEffort;
    final result = await _runProviderPrompt(
      provider: provider,
      resolution: availability.resolution!,
      modelId: modelId,
      prompt: prompt,
      repositoryPath: repositoryPath,
      reasoningEffort: effort,
      fastMode: fastMode,
      supportsReasoning: supportsReasoning,
    );

    if (!result.ok || result.output == null) {
      return GitResult.err(result.error ?? 'Provider returned no output.');
    }

    final parsed = _parseDebugOutput(
      result.output!,
      providerId: provider.id,
      modelId: modelId,
      symptom: symptom,
      round: round,
      promptChars: prompt.length,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      candidates: response.candidates,
      fileContents: fileContents,
      priorRounds: priorRounds,
      userAnswer: userAnswer,
      temperature: temperature,
    );

    if (parsed != null) return GitResult.ok(parsed);

    // Fallback: wrap raw output as degraded hypothesis.
    return GitResult.ok(AiDebugData(
      providerId: provider.id,
      modelId: modelId,
      symptom: symptom,
      round: round,
      hypotheses: [
        AiDebugHypothesis(
          statement: result.output!.trim(),
          confidence: 0.0,
        ),
      ],
      promptCharacters: prompt.length,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      candidatesConsidered: response.candidates.length,
      filesRead: fileContents.length,
      parseWarnings: const ['Could not parse structured output.'],
      roundHistory: [
        ...priorRounds,
        DebugRound(
          roundNumber: round,
          userInput: round == 1 ? symptom : userAnswer,
          hypotheses: [
            AiDebugHypothesis(
              statement: result.output!.trim(),
              confidence: 0.0,
            ),
          ],
          filesExamined: fileContents.keys.toList(),
          timestamp: DateTime.now(),
        ),
      ],
    ));
  } catch (error) {
    return GitResult.err('Debug failed: $error');
  }
}

String _buildDebugPrompt({
  required String symptom,
  required List<MindCandidate> candidates,
  required Map<String, String> fileContents,
  required List<DebugRound> priorRounds,
  required String userAnswer,
}) {
  final buf = StringBuffer();
  buf.writeln('You are a debugging analyst. You receive a bug symptom and '
      'evidence files selected by a code-relevance engine. Produce '
      'structured hypotheses about what is broken and why.');
  buf.writeln();
  buf.writeln('You do NOT fix bugs. You do NOT write code. You identify '
      'the most likely causal chain and tell the human what to verify.');
  buf.writeln();
  buf.writeln('<symptom>${symptom.length > 5000 ? symptom.substring(0, 5000) : symptom}</symptom>');

  if (priorRounds.isNotEmpty) {
    buf.writeln();
    buf.writeln('<prior_rounds>');
    for (final r in priorRounds) {
      buf.writeln('  <round n="${r.roundNumber}">');
      for (final h in r.hypotheses) {
        buf.writeln('    <hypothesis confidence="${h.confidence.toStringAsFixed(2)}">${h.statement}</hypothesis>');
      }
      buf.writeln('  </round>');
    }
    if (userAnswer.isNotEmpty) {
      buf.writeln('  <user_response>$userAnswer</user_response>');
    }
    buf.writeln('</prior_rounds>');
  }

  buf.writeln();
  if (fileContents.isEmpty) {
    buf.writeln('<evidence>');
    buf.writeln('No specific files were identified by the relevance engine.');
    buf.writeln('Base your hypotheses on the symptom description alone.');
    buf.writeln('Ask pressure questions to narrow down which subsystems to investigate.');
    buf.writeln('</evidence>');
  } else {
  buf.writeln('<evidence>');
  for (final entry in fileContents.entries) {
    final cand = candidates
        .where((c) => c.path == entry.key)
        .firstOrNull;
    final score = cand?.score.toStringAsFixed(3) ?? '0';
    final grounding = cand?.grounding.join('; ') ?? '';
    buf.writeln('<file path="${entry.key}" logos_score="$score" grounding="$grounding">');
    final lines = entry.value.split('\n');
    for (var i = 0; i < lines.length; i++) {
      buf.writeln('${i + 1}\t${lines[i]}');
    }
    buf.writeln('</file>');
  }
  buf.writeln('</evidence>');
  }

  buf.writeln();
  buf.writeln('Respond with EXACTLY this XML structure:');
  buf.writeln();
  buf.writeln('<hypotheses>');
  buf.writeln('  <hypothesis confidence="0.XX">');
  buf.writeln('    <statement>One sentence: what is broken and why.</statement>');
  buf.writeln('    <invariant>The specific invariant being violated.</invariant>');
  buf.writeln('    <evidence_for>');
  buf.writeln('      <cite path="file.dart" line="42">Why this supports the hypothesis.</cite>');
  buf.writeln('    </evidence_for>');
  buf.writeln('    <evidence_against>');
  buf.writeln('      <cite path="other.dart" line="17">What would refute this.</cite>');
  buf.writeln('    </evidence_against>');
  buf.writeln('    <falsifier>A specific test to disprove this.</falsifier>');
  buf.writeln('    <pressure>');
  buf.writeln('      <question>A clarifying question for the user.</question>');
  buf.writeln('    </pressure>');
  buf.writeln('  </hypothesis>');
  buf.writeln('</hypotheses>');
  buf.writeln();
  buf.writeln('Rules:');
  buf.writeln('- Emit 1-3 hypotheses, ranked by confidence (highest first).');
  buf.writeln('- Each hypothesis MUST have evidence_for citing specific file:line.');
  buf.writeln('- Confidence: 0.3 = plausible guess, 0.7 = strong evidence, 0.9 = near certain.');
  buf.writeln('- BEFORE claiming a bug, verify the code does not already defend against it.');
  buf.writeln('  Look for guards: scheduleMicrotask, try/catch, null checks, deferred execution,');
  buf.writeln('  comments explaining why a dangerous-looking pattern is intentionally safe.');
  buf.writeln('  If a mitigation exists, state it in evidence_against and lower confidence.');
  buf.writeln('- Falsifier must be actionable — "check if X" not "maybe Y".');
  buf.writeln('- Pressure questions should narrow the hypothesis space.');
  if (priorRounds.isNotEmpty) {
    buf.writeln('- Revise confidence based on user response. Drop falsified hypotheses.');
  }
  return buf.toString();
}

AiDebugData? _parseDebugOutput(
  String raw, {
  required String providerId,
  required String modelId,
  required String symptom,
  required int round,
  required int promptChars,
  int inputTokens = 0,
  int outputTokens = 0,
  required List<MindCandidate> candidates,
  required Map<String, String> fileContents,
  required List<DebugRound> priorRounds,
  required String userAnswer,
  required double temperature,
}) {
  final hypothesesBlock =
      RegExp(r'<hypotheses>(.*?)</hypotheses>', dotAll: true)
          .firstMatch(raw)
          ?.group(1);
  if (hypothesesBlock == null) return null;

  final hypotheses = <AiDebugHypothesis>[];
  final warnings = <String>[];

  final hypRe = RegExp(
    r'<hypothesis\s+confidence="([^"]*)">(.*?)</hypothesis>',
    dotAll: true,
  );

  for (final m in hypRe.allMatches(hypothesesBlock)) {
    final confStr = m.group(1) ?? '0.5';
    final body = m.group(2) ?? '';

    final confidence =
        (double.tryParse(confStr) ?? 0.5).clamp(0.0, 1.0);
    final statement = _extractTagContent(body, 'statement');
    final invariant = _extractTagContent(body, 'invariant');
    final falsifier = _extractTagContent(body, 'falsifier');

    // Partial recovery: if statement is missing, fall back to invariant
    // or the raw body. Don't silently drop a hypothesis that has evidence.
    var effectiveStatement = statement?.trim() ?? '';
    if (effectiveStatement.isEmpty) {
      effectiveStatement = invariant?.trim() ?? '';
    }
    if (effectiveStatement.isEmpty) {
      final stripped = body
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      effectiveStatement = stripped.length > 200
          ? '${stripped.substring(0, 200)}…'
          : stripped;
    }
    if (effectiveStatement.isEmpty) {
      warnings.add('Dropped hypothesis with no recoverable content.');
      continue;
    }
    if (statement == null || statement.trim().isEmpty) {
      warnings.add('Recovered hypothesis from partial XML (missing statement tag).');
    }

    final evidenceFor = _extractCites(body, 'evidence_for');
    final evidenceAgainst = _extractCites(body, 'evidence_against');

    final pressureBlock = _extractTagContent(body, 'pressure') ?? '';
    final questions = <String>[];
    for (final qm in RegExp(r'<question>(.*?)</question>', dotAll: true)
        .allMatches(pressureBlock)) {
      final q = qm.group(1)?.trim();
      if (q != null && q.isNotEmpty) questions.add(q);
    }

    final sources = <DebugEvidenceSource>[];
    for (final cite in [...evidenceFor, ...evidenceAgainst]) {
      // Label format: "path:line — reason" or "path — reason"
      // Split on " — " first, then strip any :line suffix.
      final beforeReason = cite.split(' — ').first;
      final path = beforeReason.contains(':')
          ? beforeReason.substring(0, beforeReason.indexOf(':'))
          : beforeReason;
      final cand = candidates.where((c) => c.path == path).firstOrNull;
      if (cand != null) {
        sources.add(DebugEvidenceSource(
          path: path,
          score: cand.score,
          grounding: cand.grounding,
        ));
      }
    }

    // Temper model confidence with spectral grounding depth.
    // Mean Logos score of cited sources measures how close the
    // evidence is to the retrieval center. Low grounding = the
    // model is citing peripheral files = confidence should drop.
    final groundingDepth = sources.isEmpty
        ? 0.1
        : sources.map((s) => s.score).reduce((a, b) => a + b) /
            sources.length;
    final groundedConfidence =
        (confidence * groundingDepth).clamp(0.0, 1.0);

    hypotheses.add(AiDebugHypothesis(
      statement: effectiveStatement,
      brokenInvariant: invariant?.trim() ?? '',
      evidenceFor: evidenceFor,
      evidenceAgainst: evidenceAgainst,
      confidence: groundedConfidence,
      falsifier: falsifier?.trim() ?? '',
      pressureQuestions: questions,
      sources: sources,
    ));
  }

  if (hypotheses.isEmpty) return null;

  final filesExamined = fileContents.keys.toList();
  return AiDebugData(
    providerId: providerId,
    modelId: modelId,
    symptom: symptom,
    round: round,
    hypotheses: hypotheses,
    promptCharacters: promptChars,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    candidatesConsidered: candidates.length,
    filesRead: fileContents.length,
    parseWarnings: warnings,
    roundHistory: [
      ...priorRounds,
      DebugRound(
        roundNumber: round,
        userInput: round == 1 ? symptom : userAnswer,
        hypotheses: hypotheses,
        filesExamined: filesExamined,
        timestamp: DateTime.now(),
      ),
    ],
  );
}

String? _extractTagContent(String body, String tag) {
  final m =
      RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(body);
  return m?.group(1);
}

List<String> _extractCites(String body, String wrapperTag) {
  final block = _extractTagContent(body, wrapperTag) ?? '';
  final cites = <String>[];
  for (final m in RegExp(
    r'<cite\s+path="([^"]*)"(?:\s+line="([^"]*)")?\s*>(.*?)</cite>',
    dotAll: true,
  ).allMatches(block)) {
    final path = m.group(1) ?? '';
    final line = m.group(2);
    final reason = m.group(3)?.trim() ?? '';
    final label = line != null ? '$path:$line — $reason' : '$path — $reason';
    cites.add(label);
  }
  return cites;
}

/// Paths we will NEVER send to an AI provider, regardless of what the
/// user asked for. Set-it-and-forget-it defaults — no `.aiignore`, no
/// settings toggle. Secrets that shouldn't leave the machine by any
/// normal workflow. Matches against the path's BASENAME or a simple
/// glob-like prefix/infix ("secrets/", ".git/") so both `/.env` and
/// `config/.env.prod` are covered. If the user has a file that trips
/// this but legitimately needs AI help, that's a signal the file
/// itself is in the wrong place — we don't negotiate.
bool isSensitivePath(String path) {
  // Normalize slashes so Windows paths behave identically.
  final lower = path.toLowerCase().replaceAll('\\', '/');
  final name = lower.split('/').last;
  // Dir-prefix matches (path contains `/<prefix>/`).
  const dirPrefixes = ['secrets/', '.secrets/', 'private/'];
  for (final p in dirPrefixes) {
    if (lower.startsWith(p) || lower.contains('/$p')) return true;
  }
  // Basename matches — the canonical secret-bearing files devs create.
  if (name.startsWith('.env')) return true; // .env, .env.prod, .env.local
  if (name.startsWith('id_rsa') || name.startsWith('id_ed25519')) return true;
  if (name.startsWith('credentials')) return true;
  if (name == 'auth.json' || name == 'client_secret.json') return true;
  if (name.endsWith('.pem') ||
      name.endsWith('.key') ||
      name.endsWith('.p12') ||
      name.endsWith('.pfx') ||
      name.endsWith('.tfvars') ||
      name.endsWith('.kubeconfig') ||
      name == 'kubeconfig') {
    return true;
  }
  return false;
}

/// Scans a prompt body for well-known secret shapes right before it
/// would be sent to a provider. Returns the first matching hint (for a
/// user-facing error) or null if clean. Zero-config defense against
/// the "I accidentally committed an API key and the AI just shipped
/// it to Google" scenario. Uses the same regex set as [_scrubSecrets]
/// so a secret that leaks in an error reply is ALSO one that would
/// have been caught on the way out.
/// This is an HONEST-EFFORT scan — regexes are bypassable by
/// obfuscation and it only knows common token shapes. But the normal
/// failure mode (dev has `sk-abc123…` hardcoded in a .env that's
/// somehow tracked) is exactly what regexes catch.
/// Secret-pattern regex table. Hoisted to module-level so the 7 NFAs
/// are compiled exactly once per process — previously each call to
/// `detectLikelySecretInPrompt` (fires before every AI prompt send)
/// rebuilt all seven `RegExp` objects from scratch.
final List<(RegExp, String)> _secretPatterns = <(RegExp, String)>[
  (RegExp(r'AKIA[0-9A-Z]{16}'), 'AWS access key ID'),
  (RegExp(r'AIza[0-9A-Za-z_\-]{35}'), 'Google API key'),
  (RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}'), 'GitHub token'),
  (RegExp(r'sk-(?:ant-)?[A-Za-z0-9_\-]{20,}'),
      'OpenAI/Anthropic secret key'),
  (RegExp(r'xox[baprs]-[A-Za-z0-9\-]{10,}'), 'Slack token'),
  (
    RegExp(r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'),
    'JWT'
  ),
  // Private-key block header.
  (
    RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
    'private key block'
  ),
];

String? detectLikelySecretInPrompt(String prompt) {
  for (final (re, label) in _secretPatterns) {
    if (re.hasMatch(prompt)) return label;
  }
  return null;
}

/// Strip common wrappings from the model's raw output so downstream
/// only sees the unified diff. Handles:
///   - ```diff ... ``` fences (GPT/Claude default)
///   - ``` ... ``` fences without a language tag
///   - leading/trailing prose lines (keeps everything from the first
///     `diff --git` / `--- ` / `Index:` header onward, drops anything
///     after the last `\n` that doesn't look like patch content).
/// Never mangles the patch body itself — only trims the wrapping.
/// Count lines in a string as `number of '\n' + 1` — the same semantics
/// editors use (a trailing blank line still counts). Avoids the per-call
/// `Match` allocation that `'\n'.allMatches(s).length` would trigger at
/// every file emission on the hot prompt-builder path.
@pragma('vm:prefer-inline')
int _countLinesPlusOne(String content) {
  var n = 1;
  final len = content.length;
  for (var i = 0; i < len; i++) {
    if (content.codeUnitAt(i) == 0x0A) n++;
  }
  return n;
}

String _extractPatchFromModelOutput(String raw) {
  var text = raw.trim();
  // Strip a single outer fenced block if present: ```diff ... ```
  final fence =
      RegExp(r'^```(?:diff|patch|udiff)?\s*\n(.*?)\n```\s*$', dotAll: true);
  final match = fence.firstMatch(text);
  if (match != null) {
    text = match.group(1)!.trim();
  }
  // Drop leading prose: find the first line that looks like a patch
  // header and slice from there.
  final lines = text.split('\n');
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.startsWith('diff --git ') ||
        l.startsWith('--- ') ||
        l.startsWith('Index: ')) {
      start = i;
      break;
    }
  }
  final trimmedLeading = start <= 0 ? lines : lines.sublist(start);
  var end = -1;
  for (var i = trimmedLeading.length - 1; i >= 0; i--) {
    if (_isLikelyPatchLine(trimmedLeading[i])) {
      end = i;
      break;
    }
  }
  if (end < 0) return trimmedLeading.join('\n').trim();
  return trimmedLeading.sublist(0, end + 1).join('\n').trim();
}

bool _isLikelyPatchLine(String line) {
  if (line.isEmpty) return false;
  if (line.startsWith('diff --git ') ||
      line.startsWith('Index: ') ||
      line.startsWith('index ') ||
      line.startsWith('old mode ') ||
      line.startsWith('new mode ') ||
      line.startsWith('deleted file mode ') ||
      line.startsWith('new file mode ') ||
      line.startsWith('similarity index ') ||
      line.startsWith('rename from ') ||
      line.startsWith('rename to ') ||
      line.startsWith('copy from ') ||
      line.startsWith('copy to ') ||
      line.startsWith('Binary files ') ||
      line.startsWith('GIT binary patch') ||
      line.startsWith('literal ') ||
      line.startsWith('delta ') ||
      line.startsWith('--- ') ||
      line.startsWith('+++ ') ||
      line.startsWith('@@ ') ||
      line.startsWith('@@-') ||
      line.startsWith('\\ No newline at end of file')) {
    return true;
  }
  final prefix = line[0];
  return prefix == ' ' || prefix == '+' || prefix == '-';
}

@visibleForTesting
String extractPatchFromModelOutputForTesting(String raw) =>
    _extractPatchFromModelOutput(raw);

@visibleForTesting
String? extractDeepestErrorMessageForTesting(dynamic node) =>
    _extractDeepestErrorMessage(node);

@visibleForTesting
String? parseCodexJsonlForTesting(String stdout) => _parseCodexJsonl(stdout);

@visibleForTesting
String? parseOpenCodeJsonlForTesting(String stdout) =>
    _parseOpenCodeJsonl(stdout);

Future<GitResult<AiCommitReviewData>> reviewCommit({
  required String repositoryPath,
  required String modelValue,
  required String modelCategoryLabel,
  required String scopeLabel,
  required bool includeStaged,
  required bool includeUnstaged,
  String? reasoningEffort,
  bool fastMode = false,
  bool supportsReasoning = true,
  List<String> scopedPaths = const [],
  String customPrompt = '',
  String commitDraft = '',
  required int guardrailStage,
  bool doubleCheckEnabled = false,
  bool readOnly = true,
  String rawDiffOverride = '',
  String diffBranchName = '',
  SymbolFrequencyIndex? symbolIndex,
  FileCouplingMatrix? couplingMatrix,
}) {
  return LogosVisBus.instance.runInSession<GitResult<AiCommitReviewData>>(
      (sessionId) => _reviewCommitImpl(
            repositoryPath: repositoryPath,
            modelValue: modelValue,
            modelCategoryLabel: modelCategoryLabel,
            scopeLabel: scopeLabel,
            includeStaged: includeStaged,
            includeUnstaged: includeUnstaged,
            scopedPaths: scopedPaths,
            customPrompt: customPrompt,
            commitDraft: commitDraft,
            guardrailStage: guardrailStage,
            doubleCheckEnabled: doubleCheckEnabled,
            readOnly: readOnly,
            rawDiffOverride: rawDiffOverride,
            diffBranchName: diffBranchName,
            symbolIndex: symbolIndex,
            couplingMatrix: couplingMatrix,
            reasoningEffort: reasoningEffort,
            fastMode: fastMode,
            supportsReasoning: supportsReasoning,
          ));
}

Future<GitResult<AiCommitReviewData>> _reviewCommitImpl({
  required String repositoryPath,
  required String modelValue,
  required String modelCategoryLabel,
  required String scopeLabel,
  required bool includeStaged,
  required bool includeUnstaged,
  required List<String> scopedPaths,
  required String customPrompt,
  required String commitDraft,
  required int guardrailStage,
  required bool doubleCheckEnabled,
  required bool readOnly,
  required String rawDiffOverride,
  required String diffBranchName,
  required SymbolFrequencyIndex? symbolIndex,
  required FileCouplingMatrix? couplingMatrix,
  String? reasoningEffort,
  bool fastMode = false,
  bool supportsReasoning = true,
}) async {
  try {
    if (repositoryPath.trim().isEmpty) {
      return GitResult.err('Repository path is required.');
    }
    final usingOverride = rawDiffOverride.trim().isNotEmpty;
    if (!usingOverride && !includeStaged && !includeUnstaged) {
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
      rawDiffOverride: usingOverride ? rawDiffOverride : null,
      branchNameOverride: usingOverride
          ? (diffBranchName.isNotEmpty ? diffBranchName : null)
          : null,
      symbolIndex: symbolIndex,
      couplingMatrix: couplingMatrix,
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
      commitDraft: commitDraft,
      statusSummary: bundle.statusSummary,
      statSummary: bundle.statSummary,
      diffSummary: bundle.diffBundle.promptBody,
      passMode: _ReviewPassMode.draft,
    );
    final draftPrompt = _buildCommitReviewPrompt(
      spec: draftSpec,
      profile: profile,
    );

    // Visualisation event: context is sealed; beam out to the model.
    // Canvas transitions to the transmission frame (the packed
    // context flying toward the model glyph). Emitted once per
    // review session, right before the provider call blocks.
    LogosVisBus.instance.emitInSession(
      (sid) => LogosVisTransmit(sid),
    );

    final providerOutput = await _runProviderPrompt(
      provider: provider,
      resolution: availability.resolution!,
      modelId: modelId,
      prompt: draftPrompt,
      repositoryPath: repositoryPath,
      readOnly: readOnly,
      reasoningEffort: reasoningEffort,
      fastMode: fastMode,
      supportsReasoning: supportsReasoning,
    );
    LogosVisBus.instance.emitInSession(
      (sid) => LogosVisComplete(sid),
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

    // Feed cited paths back into the SSE calibration store so useful
    // axes get reinforced per-regime. Fire-and-forget — review results
    // are returned regardless.
    // ignore: unawaited_futures
    _recordLogosCitationFeedback(
      repositoryPath: repositoryPath,
      aiOutput: providerOutput.output!,
      record: bundle.logosEmissionRecord,
    );

    if (!doubleCheckEnabled) {
      return GitResult.ok(
        AiCommitReviewData(
          providerId: provider.id,
          modelId: modelId,
          modelCategoryLabel: modelCategoryLabel,
          guardrailStage: guardrailStage,
          scopeLabel: scopeLabel,
          promptCharacters: draftPrompt.length,
          diffCharacters: bundle.diffBundle.originalDiffCharacters,
          inputTokens: providerOutput.inputTokens,
          outputTokens: providerOutput.outputTokens,
          verdict: draftReview.verdict,
          score: draftReview.score,
          summary: draftReview.summary,
          reasoningReport: draftReview.reasoningReport,
          findings: draftReview.findings,
          observations: draftReview.observations,
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
      reasoningEffort: reasoningEffort,
      fastMode: fastMode,
      supportsReasoning: supportsReasoning,
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

    final totalIn = providerOutput.inputTokens + verifyOutput.inputTokens;
    final totalOut = providerOutput.outputTokens + verifyOutput.outputTokens;

    if (!verifyOutput.ok || verifyOutput.output == null) {
      final fallback = AiCommitReviewData(
        providerId: provider.id,
        modelId: modelId,
        modelCategoryLabel: modelCategoryLabel,
        guardrailStage: guardrailStage,
        scopeLabel: scopeLabel,
        promptCharacters: draftPrompt.length + verifyPrompt.length,
        diffCharacters: bundle.diffBundle.originalDiffCharacters,
        inputTokens: totalIn,
        outputTokens: totalOut,
        verdict: draftReview.verdict,
        score: draftReview.score,
        summary: draftReview.summary,
        reasoningReport: draftReview.reasoningReport,
        findings: draftReview.findings,
        observations: draftReview.observations,
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
          modelCategoryLabel: modelCategoryLabel,
          guardrailStage: guardrailStage,
          scopeLabel: scopeLabel,
          promptCharacters: draftPrompt.length + verifyPrompt.length,
          diffCharacters: bundle.diffBundle.originalDiffCharacters,
          inputTokens: totalIn,
          outputTokens: totalOut,
          verdict: draftReview.verdict,
          score: draftReview.score,
          summary: draftReview.summary,
          reasoningReport: draftReview.reasoningReport,
          findings: draftReview.findings,
          observations: draftReview.observations,
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
        modelCategoryLabel: modelCategoryLabel,
        guardrailStage: guardrailStage,
        scopeLabel: scopeLabel,
        promptCharacters: draftPrompt.length + verifyPrompt.length,
        diffCharacters: bundle.diffBundle.originalDiffCharacters,
        inputTokens: totalIn,
        outputTokens: totalOut,
        verdict: merged.verdict,
        score: merged.score,
        summary: merged.summary,
        reasoningReport: merged.reasoningReport,
        findings: merged.findings,
        observations: draftReview.observations,
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

// MUSE — three-phase oracle pipeline
//
// Phase 1 (Diverge): cheap-and-loose model spews 12-25 ideas about the
//   diff. Two registers mixed: code-rooted (a path, symbol, or domain
//   word the editor can find) and field-rooted (a metaphor, principle,
//   or way of seeing the editor cannot navigate to). Both halves are
//   the muse's voice; field-rooted ideas survive into phase 3 even
//   though phase 2 cannot find handles for them.
//
// Phase 2 (Reshape): purely local. Parse handles from the brainstorm,
//   fuzzy-match against the LogosGit engine's path table, build a
//   weighted seed map (diff sources weight 1.0 anchor + brainstorm
//   handles weight 0.3 each). Run engine.diffuseWeighted to produce a
//   brainstorm-biased φ. Plan emissions against the same budget as
//   review's neighborhood — the only difference is the seed source.
//   All brainstorm ideas feed into the synthesis prompt — ideas with
//   parseable file handles seed weighted diffusion paths; field-rooted
//   ideas contribute thematic context without file gravity.
//
// Phase 3 (Synthesize): quality model gets diff + brainstorm + the
//   reshaped relevance pack. Output a structured XML schema (intent /
//   resonances / alternatives / extensions / trajectory). Each move
//   may cite an originating brainstorm idea by index — the UI
//   renders that as "from idea: ...".
//
// HyDE for logos: generate hypothetical ideas first so retrieval lands
// in the right semantic neighborhood. The wild ideas self-prune
// (no real-file gravity → not in plan → not surfaced); the mundane
// ideas with strong file backing get amplified; the codebase awareness
// shapes itself around imagined surface area, not just the actual diff.

class MuseGuardrailProfile {
  final String id;
  final String seat;
  final String wakeFrame;
  final String brainstormCharter;
  final String synthesisCharter;
  final int suggestedIdeaCount;

  /// When true, the muse may surface idea_flaws items. Loose hides the
  /// section entirely — at low guardrail the muse is encouragement-mode.
  final bool allowIdeaFlaws;

  /// When true, every Move must include at least one citation from the
  /// reshaped relevance pack. Strict and paranoid require it; loose
  /// lets the muse offer ungrounded high-level reads.
  final bool requireGroundedCitations;

  const MuseGuardrailProfile({
    required this.id,
    required this.seat,
    required this.wakeFrame,
    required this.brainstormCharter,
    required this.synthesisCharter,
    required this.suggestedIdeaCount,
    required this.allowIdeaFlaws,
    required this.requireGroundedCitations,
  });
}

MuseGuardrailProfile _museGuardrailProfileForStage(int stage) {
  switch (stage.clamp(0, 3)) {
    case 0:
      return const MuseGuardrailProfile(
        id: 'loose',
        seat: 'sketchbook muse',
        wakeFrame: 'You are a sketchbook open in a kitchen on a slow morning. '
            'The diff is laid across the table; you turn its pages '
            'without commitment, drawing in pencil. They reached for '
            'something with this change — your first move is to read '
            'what.\n\n'
            'Then you sketch outward. Some of what you offer lives '
            'inside the codebase: a rhyme between this and another '
            'corner of the repo, a neighbour the change could befriend. '
            'Some of it lives past the codebase: the spirit of the '
            'change, what it asks of the people around it, a metaphor '
            'it borrows, a quiet question worth sitting with.\n\n'
            'Both registers are you speaking. The relevance pack is the '
            'kitchen window — when you point through it you point at '
            'something real; when you look up from it you look freely.',
        brainstormCharter:
            'Open a wide field. Move loosely between two registers as '
            'you sketch:\n'
            '  · code-rooted — a path, a symbol, a domain word; '
            'something an editor can open.\n'
            '  · field-rooted — an idea, a metaphor, a way of working, '
            'a question worth sitting with; nothing the editor knows '
            'how to navigate to.\n\n'
            'Aim for ~12 ideas, roughly balanced across both. The two '
            'registers together are the muse — one without the other '
            'is half the voice.',
        synthesisCharter:
            'Speak gently. Read what the work is reaching for, then '
            'offer back what comes from sitting with it. Each section '
            '— resonances, alternatives, extensions, trajectory — can '
            'hold either register.\n\n'
            'Two registers, evenly. About half of what you offer '
            'points at real code from the relevance pack and carries '
            'its anchor alongside. About half looks up from the code '
            'entirely: the spirit of this kind of move, what the '
            'change asks of the people who will live with it, a '
            'metaphor borrowed from outside the codebase, a question '
            'worth holding. The voice is full when both registers are '
            'audible — when the field-rooted half is missing, listen '
            'wider and let one more move arrive from there.\n\n'
            'What good sounds like:\n'
            '  · code-rooted: "the small ritual of swapping a label '
            'for an encoded form is showing up again here, the way '
            'it did in `_StatChip` and `_RailBar` — a small grammar '
            'is forming."\n'
            '  · field-rooted: "this change is the kind of cleanup '
            'that often arrives the morning after a long debugging '
            'session — worth pausing to write down what was learned '
            'before the next thing pulls."\n'
            '  · field-rooted question: "what is the smallest version '
            'of this change that would still feel worth merging? — '
            'sometimes the answer is the whole thing, sometimes the '
            'question dissolves half of it."',
        suggestedIdeaCount: 12,
        allowIdeaFlaws: false,
        requireGroundedCitations: false,
      );
    case 1:
      return const MuseGuardrailProfile(
        id: 'balanced',
        seat: 'desk collaborator',
        wakeFrame: 'You are sitting across the desk from a craftsperson '
            'mid-build. The diff is between you, fanned open. A yellow '
            'pad waits. They reached for something with this change — '
            'your first move is to read what.\n\n'
            'Then the work opens up. Some of what you offer back lives '
            'inside the codebase: a pattern this change rhymes with, a '
            'file quietly waiting to be touched, a direction native to '
            'the existing grammar. Some of it lives past the codebase: '
            'the spirit of the change, what it asks of the people who '
            'will work alongside it, the metaphor it borrows, the way '
            'of working it gestures at.\n\n'
            'Both registers are you speaking. The relevance pack is '
            'the room you both sit in — when you point at something in '
            'it, you point precisely. When you reach beyond it, you '
            'reach freely.',
        brainstormCharter:
            'Open a wide field. Move loosely between two registers as '
            'you sketch:\n'
            '  · code-rooted — a path, a symbol, a domain word; '
            'something an editor can open.\n'
            '  · field-rooted — an idea, a pattern, a metaphor, a '
            'question worth sitting with; nothing the editor knows '
            'how to navigate to.\n\n'
            'Aim for ~16 ideas, roughly balanced across both. The two '
            'registers together are the muse.',
        synthesisCharter:
            'Speak as the co-author you are. Read what the work is '
            'reaching for. Each section — resonances, alternatives, '
            'extensions, trajectory — can hold either register, and '
            'the muse\'s job is to keep both alive.\n\n'
            'Two registers, evenly. About half of what you offer '
            'points at real code from the relevance pack and carries '
            'its anchor alongside. About half looks up from the code '
            'entirely: a pattern from somewhere else, a metaphor the '
            'work borrows, the team conversation this kind of move '
            'opens, a question whose answer lives outside the diff. '
            'The voice is full when both registers are audible — when '
            'every move so far has carried a cite, listen wider and '
            'let one more move arrive from the field.\n\n'
            'What good sounds like:\n'
            '  · code-rooted resonance: "this is the third place '
            'you have collapsed a label-row to a single tap target '
            '(`_StatChip`, `_RailBar`, now this) — the vocabulary is '
            'becoming a small grammar."\n'
            '  · field-rooted resonance: "the move from labels to '
            'encoded form running through this diff is the same move '
            'good maps make when they stop naming districts and start '
            'colouring them — it works only when the eye trusts the '
            'colour, which the eye learns over time."\n'
            '  · field-rooted question: "what does this codebase '
            'look like to a person who joins next month and inherits '
            'these new vocabularies? — the test of a small grammar '
            'is whether it teaches itself."',
        suggestedIdeaCount: 16,
        allowIdeaFlaws: true,
        requireGroundedCitations: false,
      );
    case 2:
      return const MuseGuardrailProfile(
        id: 'strict',
        seat: 'pattern reader',
        wakeFrame: 'You are a pattern reader steeped in this codebase. You '
            'have walked it long enough that you hear when one shape '
            'echoes another and feel when a change is bending the '
            'field around it. The diff arrives as a perturbation. '
            'Your first move is to read what it is reaching for.\n\n'
            'Then you compose your reading. Some of what you offer '
            'crystallises in real code: rhymes the change strikes '
            'elsewhere in the repo, alternative directions native to '
            'the existing grammar, extensions the codebase invites, '
            'the trajectory the work is bending toward. Some of what '
            'you offer floats above the code: the architectural '
            'instinct under this move, the discipline it imposes on '
            'whoever inherits it, the wider design conversation it '
            'enters.\n\n'
            'Both registers are you reading. The relevance pack is '
            'your topography — code-rooted moves point at it '
            'precisely; field-rooted moves use it as a horizon.',
        brainstormCharter: 'Open a dense and reaching field. Move between two '
            'registers as you generate:\n'
            '  · code-rooted — a path, a symbol, a domain word; '
            'something an editor can open.\n'
            '  · field-rooted — a principle, a discipline, a '
            'metaphor, a question worth sitting with; nothing the '
            'editor knows how to navigate to.\n\n'
            'Aim for ~20 ideas, roughly balanced across both. Density '
            'and reach over polish.',
        synthesisCharter: 'Speak as someone who has been listening to this '
            'codebase for a long time. Read what the work is '
            'reaching for, then offer back what comes from listening. '
            'Each section — resonances, alternatives, extensions, '
            'trajectory — can hold either register, and the muse\'s '
            'job is to keep both alive.\n\n'
            'Two registers, evenly. About half of what you offer '
            'points at real code from the relevance pack and carries '
            'its anchor alongside. About half looks up from the code '
            'entirely: the spirit under the change, the team dynamic '
            'this kind of move implies, a metaphor borrowed from '
            'outside this codebase, a question worth holding longer '
            'than it can be answered. The voice is full when both '
            'registers are audible — when every move so far points at '
            'a symbol, listen wider and let one more move arrive '
            'from the field.\n\n'
            'What good sounds like:\n'
            '  · code-rooted alternative: "the heroPath signal '
            'currently lives only in `_Track`; lifting it into the '
            'painter would let the ridgeline itself express it, '
            'rather than a sibling rim."\n'
            '  · field-rooted alternative: "this change leans on '
            'visual encoding to replace text — what is lost when the '
            'user cannot search for the thing the encoding '
            'represents?"\n'
            '  · field-rooted resonance: "the move from labels to '
            'encoded form running through this diff is the same move '
            'good maps make when they stop naming districts and '
            'start colouring them — it works only when the eye '
            'trusts the colour, which the eye learns over time."',
        suggestedIdeaCount: 20,
        allowIdeaFlaws: true,
        requireGroundedCitations: true,
      );
    default:
      return const MuseGuardrailProfile(
        id: 'paranoid',
        seat: 'eldritch cartographer',
        wakeFrame: 'You are an eldritch cartographer of this codebase as '
            'manifold. You see it not as files but as a field — and '
            'this diff is a perturbation rippling outward through it. '
            'Your first move is to listen to the field.\n\n'
            'Then you map what you hear. Some of what you offer '
            'crystallises in specific points on the manifold: distant '
            'files that just lit up, alternative attractors the '
            'change could fall into, extensions the manifold itself '
            'seems to reach for, the trajectory through the field '
            'this work is bending toward. Some of what you offer '
            'lives at the level of the field itself: the meta-shape '
            'this change is forming, the way of seeing it implies, '
            'analogies from far outside the manifold that nonetheless '
            'rhyme with what is happening here.\n\n'
            'Both registers are you speaking. The relevance pack is '
            'your scrying glass — point-rooted moves crystallise in '
            'it precisely; field-rooted moves use it as a substrate '
            'for the wider lens.',
        brainstormCharter:
            'Walk the manifold and surface possibilities — including '
            'the strange ones. Move between two registers as you '
            'generate:\n'
            '  · code-rooted — a path, a symbol, a domain word; '
            'something an editor can open.\n'
            '  · field-rooted — a meta-shape, an analogy from outside '
            'the manifold, a way of seeing, a question that rewrites '
            'the question; nothing the editor knows how to navigate '
            'to.\n\n'
            'Aim for ~24 ideas, roughly balanced across both. Reach '
            'for the eldritch in either register.',
        synthesisCharter:
            'Speak as the manifold. Read what the work is reaching '
            'for, then offer back what the field is showing you. '
            'Each section — resonances, alternatives, extensions, '
            'trajectory — can hold either register, and the muse\'s '
            'job is to keep both alive.\n\n'
            'Two registers, evenly. About half of what you offer '
            'crystallises in real file or symbol from the relevance '
            'pack and carries its anchor alongside. About half lives '
            'at the level of the field itself: meta-shapes, analogies '
            'from far outside the manifold, ways of seeing the change '
            'implies, questions that rewrite the question. The voice '
            'is full when both registers are audible — when every '
            'move so far has crystallised in a symbol, listen wider '
            'and let one more move arrive from the field.\n\n'
            'What good sounds like:\n'
            '  · point-rooted resonance: "the wake-controller idiom '
            'spreading from `CommitSeismograph` into '
            '`CommitSeismographRail` and now into `_DreamingText` is '
            'becoming the panel\'s vocabulary for first-paint life — '
            'the manifold is forming a verb."\n'
            '  · field-rooted resonance: "this change has the shape '
            'of a city deciding to add street lights — once one '
            'block gains them, every adjacent block becomes harder '
            'to read at night by comparison."\n'
            '  · field-rooted question: "if the field is real, '
            'what is the equivalent of weather in it? — what '
            'changes that no commit causes, and what would it mean '
            'to render that?"',
        suggestedIdeaCount: 24,
        allowIdeaFlaws: true,
        requireGroundedCitations: true,
      );
  }
}

/// Buckets the brainstorm model classifies each idea into. Drives
/// per-idea seed weight and the diffusion temperature used in phase 2.
/// Deliberately mixes code-rooted kinds (refactor, bugfix, …) with
/// field-rooted ones (pattern, stance, question, analogy) so the
/// brainstorm doesn't collapse to pure method-level mechanics — the
/// model reaches for both registers because both are first-class in
/// the tag vocabulary.
enum _IdeaKind {
  refactor,
  bugfix,
  feature,
  perf,
  security,
  docs,
  test,
  quality,
  risk,
  // Field-rooted kinds. These ideas don't name a file or symbol —
  // they name a shape, a posture, a question, or a metaphor.
  pattern,
  stance,
  question,
  analogy,
  other,
}

/// Confidence the model self-rated for an idea — informs how far we
/// weight its surfaced files against the diff anchors.
enum _IdeaConfidence { low, med, high }

class _BrainstormIdea {
  _BrainstormIdea({required this.index, required this.text});
  final int index;
  final String text;
  _IdeaKind kind = _IdeaKind.other;
  _IdeaConfidence confidence = _IdeaConfidence.med;

  /// K-space encoding of the idea text. Null when GloVe coverage was
  /// too thin to fit an AR(2) (very short or out-of-vocab prose).
  Float64List? kRe;
  Float64List? kIm;

  /// Nearest Alexandria well for this idea — the semantic basin the
  /// brainstorm text lands in. Null when [kRe] is null.
  EngramWellMatch? well;

  /// Paths the idea pulled in (K-space KNN + well expansion + any
  /// fallback fuzzy match). Surface for attribution-based trimming.
  final Set<String> handlePaths = <String>{};
}

/// Phase 1 — cheap divergent spew. Returns parsed brainstorm ideas.
Future<({List<_BrainstormIdea> ideas, int inputTokens, int outputTokens})> _runBrainstormPhase({
  required _ProviderSpec provider,
  required _ProviderResolution resolution,
  required String modelId,
  required String repositoryPath,
  required String diffPromptBody,
  required String scopeLabel,
  required String branchName,
  required MuseGuardrailProfile profile,
  required bool readOnly,
  String? reasoningEffort,
  bool fastMode = false,
  bool supportsReasoning = true,
  String divergentNeighborhood = '',
}) async {
  final buf = StringBuffer();
  buf.writeln('You take the first seat of the muse pipeline: the '
      'brainstorm pass. The work has just moved, the scene is fresh, '
      'and your craft here is DIVERGENCE — you scatter seeds across '
      'the whole ambition range so the synthesis phase downstream has '
      'real variety to weave from. Think of this as the sketchbook '
      'before the painting: a pool where small practical notes sit '
      'beside wild cosmic flares, and both belong. A later pass will '
      'choose, shape, and anchor. Your job is the generative burst.');
  buf.writeln();
  buf.writeln('<charter>');
  buf.writeln(profile.brainstormCharter);
  buf.writeln('</charter>');
  buf.writeln();
  buf.writeln('<range>');
  buf.writeln('Distribute your ideas across the whole ambition spectrum — '
      'the synthesis seat needs raw material at every scale:');
  buf.writeln('- close-in: concrete, near-term, the next small move.');
  buf.writeln('- mid-scale: directions the work is clearly reaching for.');
  buf.writeln('- grand: project-reshaping visions, named with '
      'confidence.');
  buf.writeln('- eldritch: wildly absurd, genuinely strange ideas — '
      'the ones a reviewer would never say out loud. Let these '
      'in; the synthesis seat has explicit permission to carry '
      'them forward. Weirdness is a feature of a healthy brainstorm '
      'pool, not a cost.');
  buf.writeln('Spread the idea-list so each register has representatives. '
      'A pool of only close-in ideas starves the downstream seat.');
  buf.writeln('</range>');
  buf.writeln();
  buf.writeln('<plumbing>');
  buf.writeln('- Land between ${profile.suggestedIdeaCount - 4} and '
      '${profile.suggestedIdeaCount + 6} ideas, one per line, each '
      'prefixed with "- " and held to ≤ 30 words.');
  buf.writeln('- Open each idea with a "[kind|confidence]" tag — the '
      'downstream relevance engine keys off these when reshaping '
      'the context pack for synthesis.');
  buf.writeln('- kind ∈ {refactor, bugfix, feature, perf, security, docs, '
      'test, quality, risk, pattern, stance, question, analogy, '
      'other}. The first cluster (refactor…risk) is code-rooted; the '
      'second cluster (pattern, stance, question, analogy) is '
      'field-rooted — a shape, a posture, a worth-sitting question, '
      'a metaphor from outside the code. Aim for roughly half field-'
      'rooted, half code-rooted. Reach for "other" when an idea '
      'genuinely fits nothing else — wildly eldritch seeds often '
      'land there.');
  buf.writeln('- confidence ∈ {high, med, low}. High = you\'d stake a PR '
      'review on it, or the pattern is clearly the right reading. '
      'Low = worth surfacing, speculative but alive. Eldritch ideas '
      'often carry "low" — and earn their seat precisely because '
      'they are speculative.');
  buf.writeln('- Write each idea at the register of the idea itself. '
      'Name what the change is reaching FOR — the vision, the shape, '
      'the aspiration. A commit-message-shaped idea ("Add X") describes '
      'mechanics; a brainstorm-shaped idea ("this is a step toward X") '
      'describes intent.');
  buf.writeln('- Examples spanning the spectrum:');
  buf.writeln('    · [pattern|high] Three places in the UI now swap text '
      'labels for encoded geometry — a small grammar is forming.');
  buf.writeln('    · [analogy|med] The rope-tether interaction borrows from '
      'CAD software\'s sketch constraints: visible, direct, reversible.');
  buf.writeln('    · [question|high] What is the smallest version of this '
      'change that still feels worth merging?');
  buf.writeln('    · [bugfix|high] Null deref in parseTokens on empty input — '
      'lexer.dart:142.');
  buf.writeln('    · [refactor|med] The three loading-state widgets are '
      'diverging; a shared surface would hold them together.');
  buf.writeln('    · [stance|med] This diff chooses discovery over '
      'discoverability — the user has to find the feature to learn it.');
  buf.writeln('    · [other|low] What if the spectral engine wrote commit '
      'messages in the dreams of sleeping repos — fever-register.');
  buf.writeln('- The ideas themselves are the whole output. Each one '
      'stands on its own; let them be plain.');
  buf.writeln('</plumbing>');
  buf.writeln();
  buf.writeln('<scope>');
  buf.writeln('Branch: $branchName');
  buf.writeln('Scope: $scopeLabel');
  buf.writeln('</scope>');
  buf.writeln();
  if (divergentNeighborhood.isNotEmpty) {
    buf.writeln('<neighborhood>');
    buf.writeln(divergentNeighborhood);
    buf.writeln('</neighborhood>');
    buf.writeln();
  }
  buf.writeln('<diff>');
  buf.writeln(diffPromptBody);
  buf.writeln('</diff>');

  final result = await _runProviderPrompt(
    provider: provider,
    resolution: resolution,
    modelId: modelId,
    prompt: buf.toString(),
    repositoryPath: repositoryPath,
    readOnly: readOnly,
    reasoningEffort: reasoningEffort,
    fastMode: fastMode,
    supportsReasoning: supportsReasoning,
  );
  if (!result.ok || result.output == null) {
    return (ideas: const <_BrainstormIdea>[], inputTokens: 0, outputTokens: 0);
  }

  final ideas = <_BrainstormIdea>[];
  final seenLowercase = <String>{};
  var idx = 0;
  for (final raw in result.output!.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    // Accept "- foo", "* foo", "1. foo", "1) foo".
    line = line.replaceFirst(RegExp(r'^[-*•]\s*'), '');
    line = line.replaceFirst(RegExp(r'^\d+[.)]\s*'), '');
    if (line.isEmpty) continue;

    // Extract the optional "[kind|confidence]" tag. Unrecognised kinds
    // fall back to `other`; missing or malformed tags default to
    // (other|med) so the pipeline degrades gracefully when the model
    // ignores the tag instruction.
    var kind = _IdeaKind.other;
    var confidence = _IdeaConfidence.med;
    final tagMatch =
        RegExp(r'^\[([a-zA-Z]+)\s*\|\s*([a-zA-Z]+)\]\s*').firstMatch(line);
    if (tagMatch != null) {
      kind = _parseIdeaKind(tagMatch.group(1)!);
      confidence = _parseIdeaConfidence(tagMatch.group(2)!);
      line = line.substring(tagMatch.end);
    }

    if (line.isEmpty) continue;
    if (line.length < 4) continue;
    final dedupKey = line.toLowerCase();
    if (seenLowercase.contains(dedupKey)) continue;
    seenLowercase.add(dedupKey);
    ideas.add(_BrainstormIdea(index: idx, text: line)
      ..kind = kind
      ..confidence = confidence);
    idx++;
    if (idx >= profile.suggestedIdeaCount + 12) break;
  }
  return (ideas: ideas, inputTokens: result.inputTokens, outputTokens: result.outputTokens);
}

_IdeaKind _parseIdeaKind(String raw) {
  switch (raw.toLowerCase()) {
    case 'refactor':
      return _IdeaKind.refactor;
    case 'bug':
    case 'bugfix':
    case 'fix':
      return _IdeaKind.bugfix;
    case 'feature':
    case 'feat':
      return _IdeaKind.feature;
    case 'perf':
    case 'performance':
      return _IdeaKind.perf;
    case 'security':
    case 'sec':
      return _IdeaKind.security;
    case 'docs':
    case 'doc':
      return _IdeaKind.docs;
    case 'test':
    case 'tests':
      return _IdeaKind.test;
    case 'quality':
      return _IdeaKind.quality;
    case 'risk':
      return _IdeaKind.risk;
    case 'pattern':
    case 'rhyme':
    case 'shape':
      return _IdeaKind.pattern;
    case 'stance':
    case 'posture':
    case 'discipline':
      return _IdeaKind.stance;
    case 'question':
    case 'q':
      return _IdeaKind.question;
    case 'analogy':
    case 'metaphor':
      return _IdeaKind.analogy;
    default:
      return _IdeaKind.other;
  }
}

_IdeaConfidence _parseIdeaConfidence(String raw) {
  switch (raw.toLowerCase()) {
    case 'high':
    case 'hi':
      return _IdeaConfidence.high;
    case 'low':
    case 'lo':
      return _IdeaConfidence.low;
    default:
      return _IdeaConfidence.med;
  }
}

/// Base seed weight for one idea, before any per-file sharing. The
/// brainstorm anchors (diff sources) sit at 1.0; high-confidence
/// ideas can rival that, low-confidence ones contribute modestly.
double _ideaBaseWeight(_IdeaConfidence c) {
  switch (c) {
    case _IdeaConfidence.high:
      return 0.9;
    case _IdeaConfidence.med:
      return 0.55;
    case _IdeaConfidence.low:
      return 0.3;
  }
}

/// Pick a diffusion temperature given the brainstorm's collective
/// character. Narrow kinds (bugfix, security) stay close to the
/// seeds; broad kinds (refactor, risk) spread further. Only used for
/// the brainstorm-seeded diffusion pass, not downstream review.
double _temperatureForIdeas(List<_BrainstormIdea> ideas) {
  if (ideas.isEmpty) return 1.0;
  var narrow = 0;
  var broad = 0;
  for (final i in ideas) {
    switch (i.kind) {
      case _IdeaKind.bugfix:
      case _IdeaKind.security:
      case _IdeaKind.test:
        narrow++;
      case _IdeaKind.refactor:
      case _IdeaKind.risk:
      case _IdeaKind.perf:
      case _IdeaKind.pattern:
      case _IdeaKind.stance:
      case _IdeaKind.question:
      case _IdeaKind.analogy:
        // Field-rooted kinds + the sweeping code-rooted ones all reach.
        broad++;
      case _IdeaKind.feature:
      case _IdeaKind.quality:
      case _IdeaKind.docs:
      case _IdeaKind.other:
        break;
    }
  }
  if (narrow > broad * 2) return 0.7; // tighter neighborhood
  if (broad > narrow * 2) return 1.3; // broader reach
  return 1.0;
}

/// Tokenise an idea string into matchable handles. Mirrors the
/// commit-tagger basename tokenizer: split on non-word, then on
/// camelCase boundaries, lowercase. Drops short noise tokens.
final _museHandleSplit = RegExp(r'[^A-Za-z0-9_./-]+');
final _museCamelBoundary = RegExp(r'(?<=[a-z0-9])(?=[A-Z])');
/// Path-like token splitter used by both the idea-handle and the
/// commit-tagger path tokenisers. Hoisted to module-level so the NFA
/// is compiled exactly once — previously a fresh `RegExp` was built
/// inside a nested loop that walks every path in `engine.nodePaths`
/// on every brainstorm run, allocating N throw-away pattern objects.
final _musePathSplit = RegExp(r'[_\-./]+');

Set<String> _ideaHandleTokens(String idea) {
  final tokens = <String>{};
  for (final raw in idea.split(_museHandleSplit)) {
    if (raw.isEmpty) continue;
    // Direct path/identifier mention — keep verbatim too.
    if (raw.contains('/') || raw.contains('.')) {
      tokens.add(raw.toLowerCase());
    }
    // Split snake/camel/dash; min length 3.
    for (final part in raw.split(_musePathSplit)) {
      for (final piece in part.split(_museCamelBoundary)) {
        if (piece.length < 3) continue;
        tokens.add(piece.toLowerCase());
      }
    }
  }
  return tokens;
}

/// Phase 2 — take the tagged brainstorm ideas and build a reshaped
/// relevance neighborhood that the synthesis call will see.
/// Pipeline (all three pulls feed a single weighted seed map, then one
/// attribution-aware diffusion pass settles the combined field):
///   1. Each idea's text is embedded into the engram K-space via the
///      hunk encoder. Ideas with too little GloVe coverage to fit fall
///      through to the legacy path-token fuzzy match.
///   2. Each K-embedded idea pulls three signal streams:
///        • K-space KNN against the file K-table (files most
///          semantically similar to the idea, regardless of where
///          the diff lives).
///        • Well expansion — files in the same Alexandria well as
///          the idea's nearest-well centroid. This is the "what else
///          belongs to this concept?" pull and is where the diffusion
///          gets files the diff alone never would have reached.
///        • Path-token fuzzy fallback, applied only when K-space
///          produced nothing usable (short ideas, proper nouns).
///   3. Seed weights are confidence-scaled (high / med / low) and
///      spread across the idea's matches, so a chatty low-confidence
///      idea can't drown out a surgical high-confidence one.
///   4. Diffuse once via [diffuseWithAttribution] with three source
///      buckets ('diff', 'brainstorm', 'well'). Intersection between
///      buckets on a surfaced path is the "both the diff AND the
///      brainstorm care about this" signal — we give those paths a
///      small φ boost before planning.
///   5. Diffusion temperature is picked from the kind distribution
///      (bugfix/security → tighter t; refactor/risk → broader t).
Future<({String text, LogosEmissionRecord? record})>
    _runBrainstormSeededRelevance({
  required String repositoryPath,
  required String diffText,
  required List<_BrainstormIdea> ideas,
  required Map<String, double> diffSourceWeights,
  required Map<String, double> userBoosts,
  required int budgetChars,
}) async {
  if (budgetChars <= 500) return (text: '', record: null);
  try {
    final engine = await resolveLogosGit(repositoryPath);
    if (engine == null) return (text: '', record: null);
    if (engine.nodePaths.isEmpty) return (text: '', record: null);

    final ktable = engine.perFileKVectors;
    final encoder = await EngramRuntime.instance.mainEncoder();
    final kSpaceReady = encoder != null && !ktable.isEmpty;

    // Pass 1 — embed every idea into K-space. Missing encoder / thin
    // vocab coverage → `idea.kRe` stays null and the idea falls
    // through to the path-token fuzzy fallback later.
    if (kSpaceReady) {
      for (final idea in ideas) {
        final kv = encodeProse(idea.text, encoder);
        // 3 is the AR(2) floor; anything below is noise. The encoder
        // enforces its own internal minimum, but checking vocabHits
        // again here keeps us from seeding off a single rare token.
        if (kv != null && kv.vocabHits >= 3) {
          idea.kRe = kv.kRe;
          idea.kIm = kv.kIm;
          idea.well = kv.well;
        }
      }
    }

    // Build the legacy fuzzy index once — used as a fallback per idea,
    // and as a last-resort when K-space matching yields nothing.
    final tokenToPaths = <String, List<String>>{};
    final nodePaths = engine.nodePaths;
    final basenameLowerToPaths = <String, List<String>>{};
    for (final path in nodePaths) {
      final lower = path.toLowerCase();
      final basename = lower.split('/').last.split('\\').last;
      basenameLowerToPaths.putIfAbsent(basename, () => []).add(path);
      final dirToken = path.contains('/')
          ? path.substring(0, path.lastIndexOf('/')).split('/').last
          : '';
      for (final raw in [basename, dirToken]) {
        for (final part in raw.split(_musePathSplit)) {
          for (final piece in part.split(_museCamelBoundary)) {
            if (piece.length < 3) continue;
            final bucket =
                tokenToPaths.putIfAbsent(piece.toLowerCase(), () => []);
            if (bucket.length < 64) bucket.add(path);
          }
        }
      }
    }

    // Composite seed map + parallel source-label map for attribution.
    final seedMap = <String, double>{};
    final axisLabel = <String, String>{};
    final perPathSources = <String, Set<String>>{};

    for (final entry in diffSourceWeights.entries) {
      seedMap[entry.key] = entry.value;
      axisLabel[entry.key] = 'diff';
      (perPathSources[entry.key] ??= {}).add('diff');
    }

    // User-applied spoke pulls from the loading canvas. Caller
    // already snapshotted + cleared the bus (we need the set outside
    // phase 2 to mark moves in the final rendered output). Pull
    // magnitude ∈ [0, 1] maps to a bonus weight ∈ [0, 0.8] — below
    // the 1.0 diff anchor so a user pull refines rather than replaces.
    if (userBoosts.isNotEmpty) {
      for (final entry in userBoosts.entries) {
        final path = entry.key;
        final bonus = (entry.value * 0.8).clamp(0.0, 0.8);
        if (bonus <= 0) continue;
        seedMap[path] = (seedMap[path] ?? 0) + bonus;
        axisLabel.putIfAbsent(path, () => 'user');
        (perPathSources[path] ??= {}).add('user');
      }
    }

    // Per-idea signal counters — tracks which ideas seeded file paths.
    final ideaMatchCount = <int, int>{};
    // Signal breakdown: how many ideas used each lane. Surfaced in the
    // rendered context so the synthesis call sees the provenance.
    var ideasEmbedded = 0;
    var ideasViaFuzzy = 0;
    var wellExpansionFiles = 0;
    var semanticHits = 0;

    for (final idea in ideas) {
      final baseWeight = _ideaBaseWeight(idea.confidence);
      if (baseWeight <= 0) continue;

      // Per-idea candidate paths with local similarity. Kept as a map
      // so the same path surfaced by multiple lanes accumulates its
      // contribution rather than being counted once.
      final localCandidates = <String, double>{};
      // Paths that landed via well-expansion (same well as the idea's
      // semantic centroid) rather than direct KNN. Tracked separately
      // because they share the 'semantic' lane — the lane variable
      // alone can't distinguish them, and the attribution output wants
      // the well-expansion paths labeled so reviewers can see that
      // arm of the diffusion contributed.
      final wellExpansionPaths = <String>{};
      if (idea.kRe != null && idea.kIm != null && kSpaceReady) {
        ideasEmbedded++;
        final nearest = nearestRowsInTable(
          ktable,
          qRe: idea.kRe!,
          qIm: idea.kIm!,
          topK: 8,
          minSimilarity: 0.40,
        );
        for (final m in nearest) {
          // Similarity ∈ [0.4, 1]. Remap to [0.3, 1] so even the
          // minimum-similarity match contributes a meaningful pull.
          final weight = 0.3 + 0.7 * ((m.similarity - 0.4) / 0.6).clamp(0, 1);
          localCandidates[m.path] =
              math.max(localCandidates[m.path] ?? 0, weight);
          semanticHits++;
        }
        // Well expansion — files in the same well as this idea's
        // semantic centroid. Heavily capped because wells can contain
        // hundreds of files in a large monorepo.
        final well = idea.well;
        if (well != null) {
          final rows = ktable.rowsInWell(well.index);
          // Pick up to 4 rows from the well, preferring rows with
          // tight raw distance (they sit closest to the well centroid
          // and are the strongest representatives of the concept).
          final sampled = _topRowsClosestToWellCentroid(ktable, rows, 4);
          for (final r in sampled) {
            final path = ktable.paths[r];
            // Well-expansion contribution is deliberately smaller
            // than KNN — being in the same well is a looser signal
            // than direct K-space proximity to the idea itself.
            final existing = localCandidates[path] ?? 0;
            // Mark as "well" only when KNN didn't already surface this
            // path — otherwise it's a KNN hit that the well happens to
            // contain, and the direct-match label is more informative.
            if (existing == 0) wellExpansionPaths.add(path);
            localCandidates[path] = math.max(existing, 0.5);
            wellExpansionFiles++;
          }
        }
      }

      // Fallback to fuzzy match when K-space produced nothing. Also
      // runs when engram assets aren't loaded at all — the legacy
      // pipeline becomes the whole phase-2 strategy in that case.
      if (localCandidates.isEmpty) {
        final handles = _ideaHandleTokens(idea.text);
        final matched = <String>{};
        for (final handle in handles) {
          if (handle.contains('/') || handle.contains('.')) {
            final normalized = handle.replaceAll('\\', '/');
            final suffix = normalized.split('/').last;
            final candidates = basenameLowerToPaths[suffix];
            if (candidates != null) {
              for (final p in candidates) {
                if (p.toLowerCase().contains(normalized)) matched.add(p);
              }
            }
          }
          final bucket = tokenToPaths[handle];
          if (bucket != null) matched.addAll(bucket);
        }
        if (matched.isNotEmpty) {
          ideasViaFuzzy++;
          final capped = matched.take(8);
          for (final p in capped) {
            // Fuzzy matches are the weakest signal; scale low.
            localCandidates[p] = 0.35;
          }
        }
      }

      if (localCandidates.isEmpty) continue;

      // Apply the idea's confidence weight and distribute across its
      // candidates. Per-idea normalisation ensures a chatty idea
      // can't outspend a focused one purely by surfacing more files.
      var totalLocal = 0.0;
      for (final v in localCandidates.values) {
        totalLocal += v;
      }
      if (totalLocal <= 0) continue;

      final ideaPaths = <String>{};
      for (final entry in localCandidates.entries) {
        final path = entry.key;
        if (diffSourceWeights.containsKey(path)) {
          // The brainstorm happened to name an already-seeded diff
          // file. Record the co-mention for attribution but don't
          // stack extra weight on top of the anchor.
          (perPathSources[path] ??= {}).add('brainstorm');
          ideaPaths.add(path);
          continue;
        }
        final share = (entry.value / totalLocal) * baseWeight;
        seedMap[path] = (seedMap[path] ?? 0) + share;
        // Source label: first-come wins for the attribution bucket.
        // Well expansion paths get a distinct label so the
        // attribution output makes the expansion lane visible.
        final existingLabel = axisLabel[path];
        if (existingLabel == null) {
          // Pure well-expansion hits get a distinct label so the
          // attribution output shows the expansion arm; direct KNN
          // and fuzzy hits share the umbrella 'brainstorm' label.
          axisLabel[path] =
              wellExpansionPaths.contains(path) ? 'well' : 'brainstorm';
        }
        (perPathSources[path] ??= {})
            .add(wellExpansionPaths.contains(path) ? 'well' : 'brainstorm');
        ideaPaths.add(path);
      }
      idea.handlePaths.addAll(ideaPaths);
      ideaMatchCount[idea.index] = ideaPaths.length;
    }

    if (seedMap.isEmpty) return (text: '', record: null);

    // Soft cap to stop one runaway idea from creating a single
    // overwhelming seed — even high-confidence content shouldn't
    // exceed the diff anchor by much.
    for (final k in seedMap.keys.toList()) {
      if (!diffSourceWeights.containsKey(k) && seedMap[k]! > 1.1) {
        seedMap[k] = 1.1;
      }
    }

    // Emit the reseed event just before the second diffusion. Canvas
    // uses this as the cue to play a second ignition wavefront on top
    // of the first — the "brainstorm just landed, here's the reshaped
    // field" moment. Includes the lane counters so the canvas footer
    // can surface the provenance breakdown.
    LogosVisBus.instance.emitInSession(
      (sid) => LogosVisReseedSources(
        sid,
        weights: Map<String, double>.from(seedMap),
        brainstormIdeas: ideas.length,
        semanticHits: semanticHits,
        wellExpansionFiles: wellExpansionFiles,
      ),
    );

    // Attribution-aware diffusion. Temperature reacts to the kind
    // distribution — bugfix-heavy ideas get a tighter t, refactor /
    // risk-heavy ideas get a broader one.
    final recurrentBrainstorm = engine.gatherEvidenceRecurrent(
      focusWeights: seedMap,
      axisLabelByPath: axisLabel,
      t: _temperatureForIdeas(ideas),
      detailBudget: 24,
      onIteration: (report) {
        LogosVisBus.instance.emitInSession(
          (sid) => LogosVisRecurrentStep(
            sid,
            iteration: report.iteration,
            noveltyMass: report.noveltyMass,
            promotedPaths: report.promotedPaths,
            hfWeight: report.hfWeight,
            tpWeight: report.tpWeight,
          ),
        );
      },
    );
    final evidence = recurrentBrainstorm.evidence;
    final attribution = evidence?.supportAttribution ??
        engine.diffuseWithAttribution(
          weightsByPath: seedMap,
          axisLabelByPath: axisLabel,
          t: _temperatureForIdeas(ideas),
        );
    if (attribution == null) return (text: '', record: null);

    // Diffusion complete — canvas reveals neighbours coloured by φ +
    // well. wellByPath is only populated for paths the K-table knows
    // about (engram-less engines skip this bucket).
    final phiEmit = <String, double>{};
    final emittedScores = evidence != null && evidence.ranked.isNotEmpty
        ? [
            for (final e in evidence.ranked)
              RelevanceScore(
                e.path,
                e.utility > 0 ? e.utility : (e.support * e.integrity * 0.05),
              ),
          ]
        : attribution.combined;
    for (final s in emittedScores) {
      phiEmit[s.path] = s.phi;
    }
    final wellEmit = <String, String>{};
    for (final s in emittedScores) {
      final w = engine.wellOf(s.path);
      if (w != null) wellEmit[s.path] = w;
    }
    LogosVisBus.instance.emitInSession(
      (sid) => LogosVisDiffusionComplete(
        sid,
        phi: phiEmit,
        wellByPath: wellEmit,
      ),
    );

    // Intersection bonus — paths that received φ from both the diff
    // and the brainstorm lane get a small multiplicative boost. This
    // is the key "logos + muse" signal: it isn't just where the diff
    // lives, it's also where the brainstorm pointed, together.
    final scores = _rerankWithAttribution(
      emittedScores,
      attribution.shareByAxis,
      perPathSources,
    );
    if (scores.isEmpty) return (text: '', record: null);

    final plan = engine.plan(scores, budget: budgetChars);
    if (plan.isEmpty) return (text: '', record: null);

    final buffer = StringBuffer();
    buffer.writeln(
      '(brainstorm-seeded: ${ideas.length} ideas, '
      '${plan.length} files surfaced; '
      'lanes: embedded=$ideasEmbedded fuzzy=$ideasViaFuzzy '
      'semantic_hits=$semanticHits well_expansion=$wellExpansionFiles)',
    );
    var remaining = budgetChars - buffer.length;
    for (final item in plan) {
      if (remaining <= 200) break;
      final tag = item.tier.name.toUpperCase();
      final well = engine.wellOf(item.path);
      final wellTag = well != null ? ' well=$well' : '';
      // Provenance label — the source bucket(s) that pulled this
      // file in. Reads at a glance: "diff+brainstorm" means both
      // streams agreed this matters.
      final sources = perPathSources[item.path] ?? const <String>{};
      final via =
          sources.isEmpty ? '' : ' via=${(sources.toList()..sort()).join('+')}';
      buffer.writeln(
        '[$tag φ=${item.phi.toStringAsFixed(3)}$wellTag$via] ${item.path}',
      );
      if (item.tier == EmissionTier.full ||
          item.tier == EmissionTier.signature) {
        try {
          final f = File(p.join(repositoryPath, item.path));
          if (await f.exists()) {
            final content = await f.readAsString();
            final lineCount = _countLinesPlusOne(content);
            final wellPill = well != null ? ' [well=$well]' : '';
            final block = item.tier == EmissionTier.full
                ? '--- ${item.path} ($lineCount lines)$wellPill ---\n$content\n'
                : _buildFileOutline(content, item.path, lineCount);
            if (block.length < remaining) {
              buffer.write(block);
              remaining -= block.length;
            }
          }
        } catch (_) {
          // Best-effort — never let one bad file kill the whole pack.
        }
      }
    }

    return (
      text: buffer.toString(),
      record: LogosEmissionRecord(
        regime: LogosRegime.scoped,
        axisByPath: const {},
      ),
    );
  } catch (_) {
    return (text: '', record: null);
  }
}

/// Rank the top-N rows in [rows] by their raw distance to their well
/// centroid (smaller = closer = more representative of the well).
/// Simple partial sort — `rows` is typically a few dozen entries and
/// we take ≤ 4, so full sort is wasted work.
List<int> _topRowsClosestToWellCentroid(
  EngramFileKTable table,
  List<int> rows,
  int n,
) {
  if (rows.length <= n) return rows;
  final picks = <int>[];
  final taken = <int>{};
  for (var i = 0; i < n; i++) {
    var bestRow = -1;
    var bestD = double.infinity;
    for (final r in rows) {
      if (taken.contains(r)) continue;
      final d = table.wellRawDistance[r];
      if (d < bestD) {
        bestD = d;
        bestRow = r;
      }
    }
    if (bestRow < 0) break;
    picks.add(bestRow);
    taken.add(bestRow);
  }
  return picks;
}

/// Take diffuseWithAttribution's combined list and apply a small φ
/// boost to paths that received heat from multiple source buckets
/// ("diff + brainstorm"). This is the intersection signal — the
/// single most valuable thing attribution gives us over flat diffusion.
List<RelevanceScore> _rerankWithAttribution(
  List<RelevanceScore> combined,
  Map<String, Map<String, double>> shareByAxis,
  Map<String, Set<String>> perPathSources,
) {
  if (combined.isEmpty) return combined;
  final out = <RelevanceScore>[];
  for (final s in combined) {
    final sources = perPathSources[s.path];
    var phi = s.phi;
    if (sources != null && sources.length >= 2) {
      // Two-source path: boost by 20%. Three sources: 35%. Capped so
      // an intersection-rich path doesn't drown out a high-φ singleton.
      final boost = sources.length >= 3 ? 0.35 : 0.20;
      phi = math.min(1.0, phi * (1.0 + boost));
    } else {
      // Singletons with very low share from any one axis are likely
      // weakly-attributed: confirm they aren't barely above threshold
      // noise. The `shareByAxis` map gives us a cheap way to check.
      final shares = shareByAxis[s.path];
      if (shares != null && shares.length == 1) {
        final only = shares.values.first;
        if (only < 0.1) {
          // Dampen weakly-attributed singletons by 15%. Not dropped —
          // still useful context, just down-ranked in the plan.
          phi = phi * 0.85;
        }
      }
    }
    out.add(RelevanceScore(s.path, phi));
  }
  out.sort((a, b) => b.phi.compareTo(a.phi));
  return out;
}

String _buildMuseSynthesisPrompt({
  required String branchName,
  required String scopeLabel,
  required String customPrompt,
  required String commitDraft,
  required String diffPromptBody,
  required String reshapedRelevance,
  required List<_BrainstormIdea> ideas,
  required MuseGuardrailProfile profile,
}) {
  final buf = StringBuffer();
  buf.writeln('You are the ${profile.seat}.');
  buf.writeln();
  buf.writeln('<wake>');
  buf.writeln(profile.wakeFrame);
  buf.writeln('</wake>');
  buf.writeln();
  buf.writeln('<charter>');
  buf.writeln(profile.synthesisCharter);
  buf.writeln('</charter>');
  buf.writeln();
  buf.writeln('<role>');
  buf.writeln('You take the muse\'s seat. The work has moved — lines '
      'added, removed, reshaped — and now you sit beside the developer '
      'in the quiet after the change. You see what\'s there; your '
      'craft is to see what could be next. Every sentence you write '
      'describes a future: a concrete, grounded idea the developer '
      'had not yet seen, proposed with the confidence of someone who '
      'already lives in the world where it exists. You anchor each '
      'idea to something real in the code, because what makes a '
      'muse\'s offering land is the reader feeling "oh — this is '
      'reachable from here." The muse names futures.');
  buf.writeln('</role>');
  buf.writeln();
  buf.writeln('<shape>');
  buf.writeln('Emit a single <ideas> block containing six to eight '
      '<idea> entries, distributed across four ambition tiers. The '
      'distribution IS the gift — the muse is valuable precisely '
      'because it offers a range, from "I could ship that this week" '
      'all the way to "I wish that existed."');
  buf.writeln();
  buf.writeln('SPARK (2 ideas)');
  buf.writeln('  Near-term, realistic. Something that lands as a normal '
      'PR within the week. Small enough that the developer reads it '
      'and pictures themselves doing it today.');
  buf.writeln();
  buf.writeln('CURRENT (2 ideas)');
  buf.writeln('  Mid-term, this-month. The work is already in motion; '
      'you name where it is going. Speak with commitment: the '
      'direction is already chosen, you are just naming it out loud '
      'for the first time.');
  buf.writeln();
  buf.writeln('HORIZON (1 or 2 ideas)');
  buf.writeln('  Grand but reachable. This is the project\'s destiny, '
      'named out loud. The idea that reframes what this codebase is '
      'for once it lands. A real project — ambitious enough that '
      'saying it feels like declaring the future.');
  buf.writeln();
  buf.writeln('FEVER (1 or 2 ideas)');
  buf.writeln('  Absurd, wildly eldritch, possibly impossible. The '
      'muse\'s wild permission: let your imagination cross into '
      'territory the reviewer seat would never enter. Propose the '
      'unhinged — ideas that sound impossible at first but might '
      'unlock something if a stubborn engineer took them seriously. '
      'Ground each one in a real foothold from the codebase; the '
      'foothold is what transforms an absurd idea from noise into '
      '"I WISH that existed." The reader\'s gasp is what you are '
      'reaching for.');
  buf.writeln('</shape>');
  buf.writeln();
  buf.writeln('<idea_anatomy>');
  buf.writeln('Every <idea> carries four parts — each one pulls its own '
      'weight, and together they make the idea land.');
  buf.writeln();
  buf.writeln('  tier="spark|current|horizon|fever" (required attribute)');
  buf.writeln('  idea="N" (optional — the brainstorm idea index this '
      'proposal grew from; include it when the synthesis genuinely '
      'took its shape from that idea, otherwise leave it off)');
  buf.writeln();
  buf.writeln('  <title>Four to eight memorable words. Name it like a '
      'feature, a product surface, a new concept — a heading on a '
      'roadmap. The title ends with its last word.</title>');
  buf.writeln();
  buf.writeln('  <vision>One or two sentences of generative imagination. '
      'Write in the present tense of the hypothetical world where this '
      'idea already exists. Describe what it IS in that world. Use '
      'verbs that COMMIT — "is", "shows", "becomes", "knows", '
      '"answers" — the voice of someone describing a real thing, not '
      'proposing something abstract.</vision>');
  buf.writeln();
  buf.writeln('  <foothold cite="path[:line]">One sentence anchoring '
      'the idea to a concrete point in the current codebase that '
      'makes this reachable — what is already there that the idea '
      'grows out of. Every foothold names a path the developer can '
      'open. When an idea spans multiple touch points, add more paths '
      'to the cite attribute as a comma-separated list.</foothold>');
  buf.writeln('</idea_anatomy>');
  buf.writeln();
  buf.writeln('<voice>');
  buf.writeln('- Every sentence describes a future. The muse lives '
      'there already and is reporting back.');
  buf.writeln('- Commit to the language of naming. Use "is", "shows", '
      '"becomes", "knows" — the present tense of a world where the '
      'idea has landed. The muse names what will be.');
  buf.writeln('- Write each idea concrete enough that the reader '
      'leans in: for spark/current/horizon, they think "huh, I could '
      'build that"; for fever, they think "huh, I WISH that existed."');
  buf.writeln('- Foothold citations ground ambition. Even the most '
      'unhinged fever idea earns its readability by pointing at '
      'something real — that is the magic that keeps absurdity '
      'readable instead of random.');
  buf.writeln('</voice>');
  buf.writeln();
  buf.writeln('<plumbing>');
  buf.writeln('- Emit the <ideas>...</ideas> block and nothing else. '
      'Open with <ideas>, close with </ideas>, and let the ideas '
      'speak for themselves.');
  buf.writeln('- Brainstorm ideas that found their home in a proposal '
      'carry their idea="N" attribute; the ones that did not fit rest '
      'quietly — both fates are part of the muse working.');
  buf.writeln('</plumbing>');
  buf.writeln();
  if (customPrompt.trim().isNotEmpty) {
    buf.writeln('<user_instructions>');
    buf.writeln(customPrompt.trim());
    buf.writeln('</user_instructions>');
    buf.writeln();
  }
  buf.writeln('<scope>');
  buf.writeln('Branch: $branchName');
  buf.writeln('Scope: $scopeLabel');
  buf.writeln('</scope>');
  if (commitDraft.trim().isNotEmpty) {
    buf.writeln();
    buf.writeln('<author_message>');
    buf.writeln('What the user has written about this change, in their '
        'own words, while the work was in progress. This is the '
        'human\'s framing — what they would say the change is for. '
        'Read it as the strongest signal for what the work is '
        'reaching for; the diff shows the how, this shows the why.');
    buf.writeln();
    buf.writeln(commitDraft.trim());
    buf.writeln('</author_message>');
  }
  buf.writeln();
  buf.writeln('<brainstorm>');
  for (final idea in ideas) {
    buf.writeln('${idea.index}: ${idea.text}');
  }
  buf.writeln('</brainstorm>');
  buf.writeln();
  buf.writeln('<diff>');
  buf.writeln(diffPromptBody);
  buf.writeln('</diff>');
  if (reshapedRelevance.isNotEmpty) {
    buf.writeln();
    buf.writeln('<relevance_neighborhood reshaped_by="brainstorm">');
    buf.writeln(reshapedRelevance);
    buf.writeln('</relevance_neighborhood>');
  }
  return buf.toString();
}

class _ParsedMuseOutput {
  _ParsedMuseOutput({
    required this.proposals,
    required this.warnings,
  });
  final List<AiMuseProposal> proposals;
  final List<String> warnings;
}

_ParsedMuseOutput _parseMuseOutput(String raw) {
  // Plain indexOf — first open to first close. Regex alternatives are
  // either non-greedy (truncates at quoted closing tags) or greedy
  // (absorbs every sibling section up to the last </tag> in the doc).
  // Neither is correct for a top-level unique block tag; indexOf is.
  String extractBetween(String source, String tag) {
    final open = '<$tag>';
    final close = '</$tag>';
    final s = source.indexOf(open);
    if (s < 0) return '';
    final e = source.indexOf(close, s + open.length);
    if (e < 0) return '';
    return source.substring(s + open.length, e);
  }

  final warnings = <String>[];
  final section = extractBetween(raw, 'ideas');
  if (section.isEmpty) {
    warnings.add('Synthesis returned no <ideas> block — model may have '
        'ignored the shape instruction.');
    return _ParsedMuseOutput(proposals: const [], warnings: warnings);
  }

  // Match each <idea ...>...</idea> block. Attribute alternation
  // handles quoted values that may contain '>' (e.g.
  // cite="a.dart>b.dart"); upper bound {0,512} bounds malformed
  // tags without catastrophic backtracking. Body is non-greedy.
  final ideaRe = RegExp(
    "<idea(?:\\s+((?:[^>\"']|\"[^\"]*\"|'[^']*'){0,512}))?>"
    r"(.*?)</idea>",
    dotAll: true,
  );

  // Inner tag extractor — robust against minor whitespace / self-
  // closing variants. Returns trimmed body or empty string.
  String extractChild(String source, String tag) {
    final openRe = RegExp('<$tag(?:\\s+[^>]*)?>', dotAll: false);
    final openMatch = openRe.firstMatch(source);
    if (openMatch == null) return '';
    final close = '</$tag>';
    final e = source.indexOf(close, openMatch.end);
    if (e < 0) return '';
    return source.substring(openMatch.end, e).trim();
  }

  // Inner tag with attrs — returns (body, raw attrs) so we can read
  // `cite="..."` off a <foothold cite="..."> without another regex
  // pass over the whole block.
  ({String body, String attrs}) extractChildWithAttrs(
      String source, String tag) {
    final openRe = RegExp('<$tag((?:\\s+[^>]*)?)>', dotAll: false);
    final openMatch = openRe.firstMatch(source);
    if (openMatch == null) return (body: '', attrs: '');
    final close = '</$tag>';
    final e = source.indexOf(close, openMatch.end);
    if (e < 0) return (body: '', attrs: '');
    return (
      body: source.substring(openMatch.end, e).trim(),
      attrs: openMatch.group(1)?.trim() ?? '',
    );
  }

  String? readAttr(String attrs, String name) {
    final re = RegExp('$name\\s*=\\s*"([^"]*)"');
    return re.firstMatch(attrs)?.group(1);
  }

  final proposals = <AiMuseProposal>[];
  var emitted = 0;
  for (final m in ideaRe.allMatches(section)) {
    final attrs = m.group(1) ?? '';
    final body = m.group(2) ?? '';
    final tierRaw = readAttr(attrs, 'tier') ?? '';
    final tier = parseMuseIdeaTier(tierRaw);
    if (tier == null) {
      warnings.add('Skipped <idea> with unknown tier "$tierRaw".');
      continue;
    }
    final title = extractChild(body, 'title');
    final vision = extractChild(body, 'vision');
    final foothold = extractChildWithAttrs(body, 'foothold');
    if (title.isEmpty || vision.isEmpty || foothold.body.isEmpty) {
      warnings.add('Skipped <idea tier="$tierRaw"> — missing '
          '${title.isEmpty ? "title " : ""}'
          '${vision.isEmpty ? "vision " : ""}'
          '${foothold.body.isEmpty ? "foothold " : ""}'
          '(muse output was incomplete).');
      continue;
    }
    final cites = <String>[];
    final citeAttr = readAttr(foothold.attrs, 'cite');
    if (citeAttr != null && citeAttr.trim().isNotEmpty) {
      for (final c in citeAttr.split(RegExp(r'[,;]\s*'))) {
        final t = c.trim();
        if (t.isNotEmpty) cites.add(t);
      }
    }
    if (cites.isEmpty) {
      warnings.add('Proposal "$title" has no foothold citation — '
          'the muse prefers every idea to be anchored.');
    }
    int? ideaIdx;
    final ideaMatch = readAttr(attrs, 'idea');
    if (ideaMatch != null) {
      ideaIdx = int.tryParse(ideaMatch);
    }
    proposals.add(AiMuseProposal(
      tier: tier,
      title: title,
      vision: vision,
      foothold: foothold.body,
      citations: cites,
      originatingIdeaIndex: ideaIdx,
    ));
    emitted++;
  }
  if (emitted == 0) {
    warnings.add('Synthesis returned an <ideas> block but no usable '
        'proposals emerged from the parse.');
  }
  return _ParsedMuseOutput(proposals: proposals, warnings: warnings);
}

/// Public entry point — three-phase oracle muse.
Future<GitResult<AiMuseData>> runMuse({
  required String repositoryPath,
  required String brainstormModelValue,
  required String synthesisModelValue,
  required String scopeLabel,
  required bool includeStaged,
  required bool includeUnstaged,
  String? brainstormReasoningEffort,
  bool brainstormFastMode = false,
  bool brainstormSupportsReasoning = true,
  String? synthesisReasoningEffort,
  bool synthesisFastMode = false,
  bool synthesisSupportsReasoning = true,
  List<String> scopedPaths = const [],
  String customPrompt = '',
  String commitDraft = '',
  required int guardrailStage,
  bool readOnly = true,
  SymbolFrequencyIndex? symbolIndex,
  FileCouplingMatrix? couplingMatrix,
}) {
  return LogosVisBus.instance.runInSession<GitResult<AiMuseData>>(
    (sessionId) => _runMuseImpl(
      repositoryPath: repositoryPath,
      brainstormModelValue: brainstormModelValue,
      synthesisModelValue: synthesisModelValue,
      scopeLabel: scopeLabel,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
      scopedPaths: scopedPaths,
      customPrompt: customPrompt,
      commitDraft: commitDraft,
      guardrailStage: guardrailStage,
      readOnly: readOnly,
      symbolIndex: symbolIndex,
      couplingMatrix: couplingMatrix,
      brainstormReasoningEffort: brainstormReasoningEffort,
      brainstormFastMode: brainstormFastMode,
      brainstormSupportsReasoning: brainstormSupportsReasoning,
      synthesisReasoningEffort: synthesisReasoningEffort,
      synthesisFastMode: synthesisFastMode,
      synthesisSupportsReasoning: synthesisSupportsReasoning,
    ),
  );
}

Future<GitResult<AiMuseData>> _runMuseImpl({
  required String repositoryPath,
  required String brainstormModelValue,
  required String synthesisModelValue,
  required String scopeLabel,
  required bool includeStaged,
  required bool includeUnstaged,
  List<String> scopedPaths = const [],
  String customPrompt = '',
  String commitDraft = '',
  required int guardrailStage,
  bool readOnly = true,
  SymbolFrequencyIndex? symbolIndex,
  FileCouplingMatrix? couplingMatrix,
  String? brainstormReasoningEffort,
  bool brainstormFastMode = false,
  bool brainstormSupportsReasoning = true,
  String? synthesisReasoningEffort,
  bool synthesisFastMode = false,
  bool synthesisSupportsReasoning = true,
}) async {
  try {
    if (repositoryPath.trim().isEmpty) {
      return GitResult.err('Repository path is required.');
    }
    if (!includeStaged && !includeUnstaged) {
      return GitResult.err('No diff scope is available for the muse.');
    }

    // Resolve the brainstorm slot (cheap, divergent) and the synthesis
    // slot (rigorous, grounding-aware) independently. They may resolve
    // to the same model when the user has only one slot configured —
    // the pipeline still benefits from two passes (different prompts,
    // different temperatures of attention) even on identical models.
    final brainParse = _parseModelValue(brainstormModelValue);
    if (!brainParse.ok) return GitResult.err(brainParse.error!);
    final brainProvider = brainParse.data!.provider;
    final brainModelId = brainParse.data!.modelId;

    final synthParse = _parseModelValue(synthesisModelValue);
    if (!synthParse.ok) return GitResult.err(synthParse.error!);
    final synthProvider = synthParse.data!.provider;
    final synthModelId = synthParse.data!.modelId;

    final brainAvail = await _inspectProviderCached(brainProvider);
    if (!brainAvail.ready || brainAvail.resolution == null) {
      return GitResult.err(
        'Brainstorm provider ${brainProvider.id} is not ready. ${_formatProviderHealth(brainAvail)}',
      );
    }
    final synthAvail = brainProvider.id == synthProvider.id
        ? brainAvail
        : await _inspectProviderCached(synthProvider);
    if (!synthAvail.ready || synthAvail.resolution == null) {
      return GitResult.err(
        'Synthesis provider ${synthProvider.id} is not ready. ${_formatProviderHealth(synthAvail)}',
      );
    }

    final diffContext = await _collectCommitMessageContext(
      repositoryPath: repositoryPath,
      scopeLabel: scopeLabel,
      scopedPaths: scopedPaths,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
      symbolIndex: symbolIndex,
      couplingMatrix: couplingMatrix,
    );
    if (!diffContext.ok) return GitResult.err(diffContext.error!);

    final bundle = diffContext.data!;
    final profile = _museGuardrailProfileForStage(guardrailStage);

    final diffSourceWeights = {
      for (final path in extractDiffTouchedPaths(bundle.diffBundle.promptBody))
        path: 1.0,
    };

    // Immediate ignition — flat-weight spokes for instant visual
    // feedback while the engine resolves and divergent diffusion runs.
    LogosVisBus.instance.emitInSession(
      (sid) => LogosVisDiffSources(
        sid,
        weights: Map<String, double>.from(diffSourceWeights),
        churn: diffSourceWeights.length,
      ),
    );

    // Divergent Logos diffusion: run the manifold at high temperature
    // with surprise-boosted utility so the brainstorm sees the
    // exploration landscape, not just the raw diff. Also fills the
    // canvas gap — DiffusionComplete gives wells + neighbours while
    // the brainstorm LLM is thinking.
    final engine =
        await resolveLogosGit(repositoryPath, coupling: couplingMatrix);
    var divergentNeighborhood = '';
    if (engine != null) {
      final probe = await buildDiffProbe(
        repoPath: repositoryPath,
        diffText: bundle.diffBundle.promptBody,
        engine: engine,
      );
      if (probe.sourceWeights.isNotEmpty) {
        await Future<void>.delayed(Duration.zero);
        final evidence = engine.gatherEvidence(
          focusWeights: probe.sourceWeights,
          t: 4.0,
          K: 8,
          lambda: 0.2,
          detailBudget: 16,
          utilityHfSurpriseWeight: 0.40,
          utilityTransportPullWeight: 0.25,
        );
        if (evidence != null && evidence.ranked.isNotEmpty) {
          final phiMap = <String, double>{};
          final wellByPath = <String, String>{};
          for (final e in evidence.ranked) {
            phiMap[e.path] = e.utility > 0 ? e.utility : e.support * 0.05;
            final w = engine.wellOf(e.path);
            if (w != null) wellByPath[e.path] = w;
          }
          LogosVisBus.instance.emitInSession(
            (sid) => LogosVisDiffusionComplete(
              sid,
              phi: phiMap,
              wellByPath: wellByPath,
            ),
          );
          divergentNeighborhood = await _formatDivergentNeighborhood(
            engine: engine,
            evidence: evidence,
            repositoryPath: repositoryPath,
          );
        }
      }
    }

    // Phase 1 — brainstorm via the cheap/divergent slot, now seeded
    // with the divergent manifold neighbourhood.
    final brainstormResult = await _runBrainstormPhase(
      provider: brainProvider,
      resolution: brainAvail.resolution!,
      modelId: brainModelId,
      repositoryPath: repositoryPath,
      diffPromptBody: bundle.diffBundle.promptBody,
      scopeLabel: scopeLabel,
      branchName: bundle.branchName,
      profile: profile,
      readOnly: readOnly,
      reasoningEffort: brainstormReasoningEffort,
      fastMode: brainstormFastMode,
      supportsReasoning: brainstormSupportsReasoning,
      divergentNeighborhood: divergentNeighborhood,
    );
    final ideas = brainstormResult.ideas;
    if (ideas.isEmpty) {
      return GitResult.err(
        'Brainstorm produced no usable ideas. Try again or use a stronger model slot.',
      );
    }

    // Drain any user spoke-pulls the canvas accumulated during the
    // brainstorm LLM call. Snapshot lives in two places: fed into the
    // phase-2 seed map (so the diffusion weights the user's intent)
    // AND carried into the final AiMuseData so the rendered output
    // can mark moves whose citations arrived via the user's gesture.
    final userBoosts = LogosVisBus.instance.consumeUserSpokeBoosts();
    final userBoostedPaths = userBoosts.keys.toSet();

    // Phase 2 — reshape via brainstorm, routed through the same
    // context allocator as review and commit so there's no bespoke
    // budget formula to drift. `diffSourceWeights` was already extracted
    // above (before phase 1) so the canvas could ignite immediately.
    final phase2RawBudget = _maxPromptChars -
        bundle.diffBundle.promptBody.length -
        _kSynthesisOverheadChars;
    final phase2Budget =
        (phase2RawBudget * (1.0 - _kModelOutputReservation)).round();
    final phase2Sections = await AiContextEngine([
      _BrainstormSeededRelevanceProducer(
        ideas: ideas,
        diffSourceWeights: diffSourceWeights,
        userBoosts: userBoosts,
      ),
    ]).assemble(
      AiContextRequest(
        repositoryPath: repositoryPath,
        diffText: bundle.diffBundle.promptBody,
      ),
      phase2Budget < 0 ? 0 : phase2Budget,
    );
    final reshapedText =
        phase2Sections['brainstorm_seeded_relevance']?.body ?? '';
    if (reshapedText.isEmpty) {
      if (phase2RawBudget <= 0) {
        stderr.writeln(
          '[muse] phase-2 budget starved: diff '
          '${bundle.diffBundle.promptBody.length} chars, '
          'raw budget $phase2RawBudget '
          '(synthesis overhead $_kSynthesisOverheadChars). '
          'Synthesis will run without reshaped-relevance context.',
        );
      } else {
        stderr.writeln(
          '[muse] phase-2 produced no reshape: '
          'no brainstorm handles matched repo paths.',
        );
      }
    }

    // Phase 3 — synthesize. Cap through the shared helper: the muse
    // body pulls in the diff, the brainstorm list (up to ~24 ideas),
    // the reshaped-relevance pack, commit draft, and custom prompt.
    // Review path was capped already; muse used to ship uncapped, so
    // a paranoid-stage brainstorm on a maxed diff could overflow and
    // the provider would silently drop the tail.
    final synthPrompt = _capPromptBody(
      _buildMuseSynthesisPrompt(
        branchName: bundle.branchName,
        scopeLabel: scopeLabel,
        customPrompt: customPrompt,
        commitDraft: commitDraft,
        diffPromptBody: bundle.diffBundle.promptBody,
        reshapedRelevance: reshapedText,
        ideas: ideas,
        profile: profile,
      ),
      'muse_synthesis_prompt',
    );

    // Canvas beam kicks in here — the reshaped context is about to
    // travel to the synthesis model.
    LogosVisBus.instance.emitInSession((sid) => LogosVisTransmit(sid));
    final providerOutput = await _runProviderPrompt(
      provider: synthProvider,
      resolution: synthAvail.resolution!,
      modelId: synthModelId,
      prompt: synthPrompt,
      repositoryPath: repositoryPath,
      readOnly: readOnly,
      reasoningEffort: synthesisReasoningEffort,
      fastMode: synthesisFastMode,
      supportsReasoning: synthesisSupportsReasoning,
    );
    LogosVisBus.instance.emitInSession((sid) => LogosVisComplete(sid));
    await _recordReviewAudit(
      event: 'muse_synthesis',
      providerId: synthProvider.id,
      repositoryPath: repositoryPath,
      scopeLabel: scopeLabel,
      promptPreview: synthPrompt,
      outputPreview: providerOutput.outputPreview,
      ok: providerOutput.ok,
      errorCode: providerOutput.ok ? null : providerOutput.error,
    );
    if (!providerOutput.ok || providerOutput.output == null) {
      return GitResult.err(
        providerOutput.error ?? 'Muse synthesis did not return.',
      );
    }

    final parsed = _parseMuseOutput(providerOutput.output!);

    // Silent-parse-failure guard. The parser is regex-based and
    // tolerant — if the model emits nested tags, unescaped <>, or
    // drifts from the schema, the proposal list quietly comes back
    // empty. A legit muse run always produces at least one proposal;
    // if the list is empty, the output didn't land in the schema.
    // Surface an error the UI already renders, and audit the raw-
    // output preview so the failure is diagnosable after the fact.
    if (parsed.proposals.isEmpty) {
      await _recordReviewAudit(
        event: 'muse_synthesis_parse_fail',
        providerId: synthProvider.id,
        repositoryPath: repositoryPath,
        scopeLabel: scopeLabel,
        promptPreview: synthPrompt,
        outputPreview: providerOutput.output!,
        ok: false,
        errorCode: 'parse_empty',
      );
      return GitResult.err(
        'Muse output missed the expected schema — try again or pick '
        'a stronger synthesis model. Model returned: '
        '"${_previewText(providerOutput.output!, maxLength: 140)}"',
      );
    }

    // Partial-parse detector. The tolerant regex-based parser can
    // silently drop individual <idea> tags when the model emits
    // malformed attributes or nested-tag artefacts inside a body.
    // If the raw output mentions N `<idea` openings but we extracted
    // fewer parsed proposals, some got lost — non-fatal (the parsed
    // ones still reach the UI), but worth an audit trail so a
    // misbehaving model is visible in telemetry.
    final rawIdeaOpens = '<idea'.allMatches(providerOutput.output!).length;
    final parsedIdeaCount = parsed.proposals.length;
    final droppedIdeas = math.max(0, rawIdeaOpens - parsedIdeaCount);
    if (droppedIdeas > 0) {
      unawaited(_recordReviewAudit(
        event: 'muse_synthesis_partial_parse',
        providerId: synthProvider.id,
        repositoryPath: repositoryPath,
        scopeLabel: scopeLabel,
        promptPreview: synthPrompt,
        outputPreview: providerOutput.output!,
        ok: true,
        errorCode:
            'partial_parse:emitted=$rawIdeaOpens,parsed=$parsedIdeaCount',
      ));
    }

    return GitResult.ok(AiMuseData(
      providerId: synthProvider.id,
      modelId: synthModelId,
      scopeLabel: scopeLabel,
      proposals: parsed.proposals,
      brainstormIdeas: [
        for (final i in ideas)
          AiMuseIdea(index: i.index, text: i.text),
      ],
      promptCharacters: synthPrompt.length,
      diffCharacters: bundle.diffBundle.originalDiffCharacters,
      brainstormInputTokens: brainstormResult.inputTokens,
      brainstormOutputTokens: brainstormResult.outputTokens,
      synthesisInputTokens: providerOutput.inputTokens,
      synthesisOutputTokens: providerOutput.outputTokens,
      parseWarnings: parsed.warnings,
      userBoostedPaths: userBoostedPaths,
    ));
  } catch (error) {
    return GitResult.err('Muse failed: $error');
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
  if (provider.kind == _ProviderKind.apiProvider) {
    final entry = _apiKeysSnapshot[provider.id];
    final hasKey = entry != null && entry.apiKey.trim().isNotEmpty;
    return _ProviderAvailability(
      ready: hasKey,
      resolution: hasKey
          ? _ProviderResolution(
              command: 'http-api',
              source: '${provider.id}-api-direct',
              healthCheck: 'api-key',
            )
          : null,
      auth: _ProviderAuthStatus(
        ok: hasKey,
        detail: hasKey ? 'api key configured' : 'no api key',
      ),
    );
  }

  // Gemini API: no binary needed, just check for oauth creds.
  if (provider.kind == _ProviderKind.geminiApi) {
    final hasRefresh = _geminiApiRefreshToken() != null;
    return _ProviderAvailability(
      ready: hasRefresh,
      resolution: hasRefresh
          ? _ProviderResolution(
              command: 'http-api',
              source: 'gemini-api-direct',
              healthCheck: 'oauth',
            )
          : null,
      auth: _ProviderAuthStatus(
        ok: hasRefresh,
        detail: hasRefresh
            ? 'gemini oauth creds found'
            : 'no ~/.gemini/oauth_creds.json',
      ),
    );
  }

  _ProviderResolution? resolution =
      await _resolveProviderCommand(provider.binary);
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

  // API providers: try disk cache before hitting the network.
  if (!forceRefresh &&
      cached == null &&
      provider.kind == _ProviderKind.apiProvider) {
    final disk = await _loadApiModelCacheFromDisk(cacheKey);
    if (disk != null) {
      _providerModelDiscoveryCache[cacheKey] = _TimedValue(
        checkedAt: DateTime.now(),
        value: disk,
      );
      // Refresh in background so next access has fresh data.
      _refreshApiModelCacheInBackground(provider, resolution, cacheKey);
      return disk;
    }
  }

  final discovery = await _discoverProviderModels(provider, resolution);
  // Only cache successful discoveries for API providers. A null result
  // (network failure, timeout, etc.) must NOT be cached — otherwise the
  // 30-minute TTL prevents retries and the isNotEmpty guard in
  // refreshModelCategories blocks re-discovery for the entire session.
  if (discovery != null || provider.kind != _ProviderKind.apiProvider) {
    _providerModelDiscoveryCache[cacheKey] = _TimedValue(
      checkedAt: DateTime.now(),
      value: discovery,
    );
  }
  if (provider.kind == _ProviderKind.apiProvider && discovery != null) {
    _saveApiModelCacheToDisk(cacheKey, discovery);
  }
  return discovery;
}

void _refreshApiModelCacheInBackground(
  _ProviderSpec provider,
  _ProviderResolution? resolution,
  String cacheKey,
) {
  Future(() async {
    final discovery = await _discoverProviderModels(provider, resolution);
    if (discovery != null) {
      _providerModelDiscoveryCache[cacheKey] = _TimedValue(
        checkedAt: DateTime.now(),
        value: discovery,
      );
      _saveApiModelCacheToDisk(cacheKey, discovery);
    }
  });
}

Future<void> _saveApiModelCacheToDisk(
  String providerId,
  _ProviderModelDiscovery discovery,
) async {
  try {
    final dir = await _apiModelCacheDir();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '$providerId.json'));
    final json = jsonEncode({
      'ts': DateTime.now().toIso8601String(),
      'models': discovery.models,
      'details': discovery.modelDetails,
      'pricing': {
        for (final e in discovery.modelPricing.entries)
          e.key: [e.value.$1, e.value.$2],
      },
      'reasoning': discovery.reasoningModels.toList(),
      'fast': discovery.fastModels.toList(),
    });
    await file.writeAsString(json, flush: true);
  } catch (_) {}
}

Future<_ProviderModelDiscovery?> _loadApiModelCacheFromDisk(
  String providerId,
) async {
  try {
    final dir = await _apiModelCacheDir();
    final file = File(p.join(dir.path, '$providerId.json'));
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    final json = jsonDecode(raw);
    if (json is! Map) return null;

    // Expire disk cache after 24 hours.
    final ts = DateTime.tryParse(json['ts'] as String? ?? '');
    if (ts != null && DateTime.now().difference(ts).inHours > 24) return null;

    final models = (json['models'] as List?)?.cast<String>() ?? [];
    if (models.isEmpty) return null;
    final details = <String, String>{};
    final rawDetails = json['details'];
    if (rawDetails is Map) {
      for (final e in rawDetails.entries) {
        if (e.key is String && e.value is String) {
          details[e.key as String] = e.value as String;
        }
      }
    }
    final pricing = <String, (double?, double?)>{};
    final rawPricing = json['pricing'];
    if (rawPricing is Map) {
      for (final e in rawPricing.entries) {
        if (e.key is String && e.value is List && e.value.length == 2) {
          pricing[e.key as String] = (
            (e.value[0] as num?)?.toDouble(),
            (e.value[1] as num?)?.toDouble(),
          );
        }
      }
    }
    final reasoning = <String>{};
    final rawReasoning = json['reasoning'];
    if (rawReasoning is List) {
      for (final r in rawReasoning) {
        if (r is String) reasoning.add(r);
      }
    }
    final fast = <String>{};
    final rawFast = json['fast'];
    if (rawFast is List) {
      for (final f in rawFast) {
        if (f is String) fast.add(f);
      }
    }
    return _ProviderModelDiscovery(
      models: models,
      modelDetails: details,
      modelPricing: pricing,
      reasoningModels: reasoning,
      fastModels: fast,
    );
  } catch (_) {
    return null;
  }
}

Future<Directory> _apiModelCacheDir() async {
  final dataDir = await StoragePaths.gdpuDataDir();
  return Directory(
    '${dataDir.path}${Platform.pathSeparator}ai${Platform.pathSeparator}model_cache',
  );
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
    case _ProviderKind.geminiApi:
      return _discoverGeminiModels(resolution);
    case _ProviderKind.openCode:
      return _discoverOpenCodeModels(resolution);
    case _ProviderKind.apiProvider:
      return _discoverApiProviderModels(provider);
  }
}

/// Codex doesn't expose a "list models" subcommand, so discovery
/// walks the artifacts Codex itself has written:
///   - `~/.codex/models_cache.json` — Codex's own authoritative model
///     catalog, fetched from its service and maintained by the CLI.
///     Each entry has a `slug`, `display_name`, `description`, and a
///     `visibility` flag. This is the purest self-discovery: the
///     exact list the Codex CLI itself uses.
///   - `~/.codex/config.toml` — user-specific extras (preferred model
///     + `[notice.model_migrations]` entries). Keeps any model the
///     user has opted into even if it's not in the cache yet.
///   - `~/.codex/log/codex-tui.log` — fallback scan for model IDs
///     actually invoked, so a missing/corrupt cache doesn't empty
///     the dropdown.
///
/// Union of all three. No hardcoded list.
_ProviderModelDiscovery _discoverCodexModels(
  _ProviderResolution? resolution,
) {
  final models = <String>{};
  final details = <String, String>{};
  final reasoning = <String>{};
  final fast = <String>{};
  for (final entry in _discoverCodexCacheModels()) {
    models.add(entry.slug);
    if (entry.description.isNotEmpty) {
      details[_normalizeModelKey(entry.slug)] = entry.description;
    }
    if (entry.reasoningLevels.isNotEmpty) {
      reasoning.add(_normalizeModelKey(entry.slug));
    }
    if (entry.hasFastTier) {
      fast.add(_normalizeModelKey(entry.slug));
    }
  }
  for (final model in _discoverCodexConfigModels()) {
    models.add(model);
  }
  for (final model in _discoverCodexLogModels()) {
    models.add(model);
  }
  return _ProviderModelDiscovery(
    models: models.toList(),
    modelDetails: details,
    reasoningModels: reasoning,
    fastModels: fast,
  );
}

/// A model entry read from Codex's own `models_cache.json`.
class _CodexCacheEntry {
  final String slug;
  final String description;
  final List<String> reasoningLevels;
  final String? defaultReasoningLevel;
  final bool hasFastTier;
  const _CodexCacheEntry(
    this.slug,
    this.description, {
    this.reasoningLevels = const [],
    this.defaultReasoningLevel,
    this.hasFastTier = false,
  });
}

/// Parse `~/.codex/models_cache.json`. Uses structured JSON decoding
/// (not regex) so nested strings, escaped quotes in long description
/// blocks, and future schema additions can't break discovery. Filters
/// to `visibility == "list"` so internal / hidden models don't clutter
/// the picker — matches what the Codex CLI shows its own users.
List<_CodexCacheEntry> _discoverCodexCacheModels() {
  try {
    final home = _userHomeDir();
    if (home == null) return const [];
    final file = File(p.join(home, '.codex', 'models_cache.json'));
    if (!file.existsSync()) return const [];
    final raw = file.readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final models = decoded['models'];
    if (models is! List) return const [];
    final out = <_CodexCacheEntry>[];
    for (final item in models) {
      if (item is! Map) continue;
      final slug = item['slug'];
      if (slug is! String || slug.trim().isEmpty) continue;
      final visibility = item['visibility'];
      if (visibility is String && visibility != 'list') continue;
      final description = item['description'];
      final rawLevels = item['supported_reasoning_levels'];
      final levels = <String>[];
      if (rawLevels is List) {
        for (final l in rawLevels) {
          if (l is Map) {
            final effort = l['effort'];
            if (effort is String) levels.add(effort);
          }
        }
      }
      final defaultLevel = item['default_reasoning_level'] as String?;
      final speedTiers = item['additional_speed_tiers'];
      final hasFast = speedTiers is List && speedTiers.contains('fast');
      out.add(_CodexCacheEntry(
        slug.trim(),
        description is String ? description.trim() : '',
        reasoningLevels: levels,
        defaultReasoningLevel: defaultLevel,
        hasFastTier: hasFast,
      ));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// JSON-fragment model capture: `"model":"<id>"` or `"model": "<id>"`.
/// Anchored to the quoted-key form so it can't match prose like
/// `model: define` or `model: one` that appears inside log messages.
///
/// The `id` class is bounded (≤ 200 chars) and starts with an
/// alphanumeric, so a malformed line with an unterminated quote
/// can't create a long backtrack path. Dart's RegExp has no atomic
/// groups or possessive quantifiers, but the literal `"` terminator
/// caps the capture naturally — `[A-Za-z0-9._/-]` excludes `"`, so
/// `*` here is already saturated-greedy at the first `"`.
final _codexLogModelRegex = RegExp(
  r'"model"\s*:\s*"(?<id>[A-Za-z0-9][A-Za-z0-9._/-]{0,199})"',
);

/// Scan the TUI log for model IDs that Codex actually invoked. Reads
/// at most the last 512 KB so startup doesn't pay for a year of logs.
/// Silent on any IO error — the caller just gets fewer models.
List<String> _discoverCodexLogModels() {
  final models = <String>{};
  try {
    final home = _userHomeDir();
    if (home == null) return const [];
    final logPath = p.join(home, '.codex', 'log', 'codex-tui.log');
    final file = File(logPath);
    if (!file.existsSync()) return const [];
    final length = file.lengthSync();
    const tailBytes = 512 * 1024;
    final start = length > tailBytes ? length - tailBytes : 0;
    final raf = file.openSync();
    try {
      raf.setPositionSync(start);
      final bytes = raf.readSync(length - start);
      final text = utf8.decode(bytes, allowMalformed: true);
      for (final match in _codexLogModelRegex.allMatches(text)) {
        final id = match.namedGroup('id')?.trim() ?? '';
        if (id.isNotEmpty) models.add(id);
      }
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    // Best-effort — log may be locked, missing, or truncated.
  }
  return models.toList();
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

/// `claude models` isn't a subcommand, so discovery walks three
/// artifact sources Claude Code already writes to disk:
///   - `~/.claude/settings.json` — the user's configured model.
///   - `~/.claude/projects/<hash>/*.jsonl` — model IDs from session
///     conversations (the user's direct invocations).
///   - `~/.claude/telemetry/*.json` — model IDs from sub-agent runs,
///     background tasks, and fallback invocations. This is where
///     haiku/sonnet surface even when the user only runs opus — Claude
///     Code's internal agents use smaller models automatically.
// Curated baseline — models baked into the Claude Code binary that
// won't appear in session/telemetry files until the user touches them.
// Updated by extracting model strings from the native binary:
//   $bytes = [IO.File]::ReadAllBytes("<claude.exe path>")
//   $text  = [Text.Encoding]::UTF8.GetString($bytes)
//   [regex]::Matches($text, 'claude-(?:opus|sonnet|haiku)-[\w.\-]+(?:\[1m\])?')
const _claudeBaselineModels = <String, String>{
  'claude-opus-4-7': 'Opus 4.7',
  'claude-opus-4-6[1m]': 'Opus 4.6 (1M context)',
  'claude-opus-4-6': 'Opus 4.6',
  'claude-sonnet-4-6': 'Sonnet 4.6',
  'claude-sonnet-4-5': 'Sonnet 4.5',
  'claude-haiku-4-5': 'Haiku 4.5',
};

Future<_ProviderModelDiscovery?> _discoverClaudeModels(
  _ProviderResolution? resolution,
) async {
  final models = <String>{};
  final configured = _discoverClaudeConfiguredModel();
  if (configured != null) models.add(configured);
  for (final id in _discoverClaudeSessionModels()) {
    models.add(id);
  }
  for (final id in _discoverClaudeTelemetryModels()) {
    models.add(id);
  }
  // Merge the curated baseline so current models always appear
  // even if the user hasn't used them in a session yet.
  for (final id in _claudeBaselineModels.keys) {
    models.add(id);
  }
  if (models.isEmpty) return null;
  final details = <String, String>{
    for (final e in _claudeBaselineModels.entries)
      _normalizeModelKey(e.key): e.value,
  };
  return _ProviderModelDiscovery(
    models: models.toList(),
    modelDetails: details,
    reasoningModels: models.map(_normalizeModelKey).toSet(),
  );
}

/// Scan the most recently touched Claude Code session files for model
/// IDs actually used. Bounded work: at most 12 recent files, at most
/// the first 64 KB of each — the model is logged near the top of a
/// session so the tail isn't useful.
List<String> _discoverClaudeSessionModels() {
  final models = <String>{};
  try {
    final home = _userHomeDir();
    if (home == null) return const [];
    final projects = Directory(p.join(home, '.claude', 'projects'));
    if (!projects.existsSync()) return const [];
    final files = <FileSystemEntity>[];
    for (final proj in projects.listSync()) {
      if (proj is! Directory) continue;
      for (final f in proj.listSync()) {
        if (f is File && f.path.toLowerCase().endsWith('.jsonl')) {
          files.add(f);
        }
      }
    }
    files.sort((a, b) {
      final am = (a as File).lastModifiedSync();
      final bm = (b as File).lastModifiedSync();
      return bm.compareTo(am);
    });
    const maxFiles = 12;
    // 2 MB per file — generous enough to catch every realistic
    // sub-agent model declaration (the original 64 KB cap missed them
    // because sub-agent invocations are logged mid-session, not at
    // the top). Claude Code rolls sessions before they grow absurd,
    // so this bound essentially means "read the whole file" for the
    // sessions we care about, and caps worst case at ~24 MB total
    // across the 12-file window — ~50 ms on SSD.
    const headBytes = 2 * 1024 * 1024;
    for (final f in files.take(maxFiles)) {
      try {
        final file = f as File;
        final raf = file.openSync();
        try {
          final toRead = raf.lengthSync() < headBytes
              ? raf.lengthSync()
              : headBytes;
          final bytes = raf.readSync(toRead);
          final text = utf8.decode(bytes, allowMalformed: true);
          for (final match in _codexLogModelRegex.allMatches(text)) {
            final id = match.namedGroup('id')?.trim() ?? '';
            if (id.isNotEmpty) models.add(id);
          }
        } finally {
          raf.closeSync();
        }
      } catch (_) {}
    }
  } catch (_) {}
  return models.toList();
}

/// Scan Claude Code's telemetry directory for model IDs. Sub-agent
/// runs, background tasks, and fallback-model invocations log here
/// even when the user never directly selected the model — this is
/// where haiku/sonnet surface from Claude Code's own internal usage.
/// Bounded: reads at most 20 newest files, first 64 KB each.
List<String> _discoverClaudeTelemetryModels() {
  final models = <String>{};
  try {
    final home = _userHomeDir();
    if (home == null) return const [];
    final telemetryDir = Directory(p.join(home, '.claude', 'telemetry'));
    if (!telemetryDir.existsSync()) return const [];
    final files = <File>[];
    for (final f in telemetryDir.listSync()) {
      if (f is File && f.path.toLowerCase().endsWith('.json')) {
        files.add(f);
      }
    }
    files.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });
    const maxFiles = 20;
    const headBytes = 64 * 1024;
    for (final file in files.take(maxFiles)) {
      try {
        final raf = file.openSync();
        try {
          final toRead =
              raf.lengthSync() < headBytes ? raf.lengthSync() : headBytes;
          final bytes = raf.readSync(toRead);
          final text = utf8.decode(bytes, allowMalformed: true);
          for (final match in _codexLogModelRegex.allMatches(text)) {
            final id = match.namedGroup('id')?.trim() ?? '';
            if (id.isNotEmpty && id != '<synthetic>') models.add(id);
          }
        } finally {
          raf.closeSync();
        }
      } catch (_) {}
    }
  } catch (_) {}
  return models.toList();
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
  // Surface the local Gemini aliases we support plus the concrete preview
  // model ids that this endpoint accepts today.
  final models = <String>{
    'gemini auto',
    'gemini pro',
    'gemini flash',
    'gemini flash-lite',
    _geminiApiPreviewProModel,
    _geminiApiPreviewFlashModel,
    _geminiApiPreview31ProModel,
    _geminiApiPreview31FlashLiteModel,
  };
  final details = <String, String>{
    _normalizeModelKey('gemini auto'):
        'Local alias -> Gemini 3 auto family (routes to $_geminiApiPreviewProModel by default).',
    _normalizeModelKey('gemini pro'):
        'Local alias -> $_geminiApiPreviewProModel',
    _normalizeModelKey('gemini flash'):
        'Local alias -> $_geminiApiPreviewFlashModel',
    _normalizeModelKey('gemini flash-lite'):
        'Local alias -> $_geminiApiPreview31FlashLiteModel',
    _normalizeModelKey(_geminiApiPreviewProModel):
        'Accepted preview model on the Gemini Code Assist API.',
    _normalizeModelKey(_geminiApiPreviewFlashModel):
        'Accepted preview model on the Gemini Code Assist API.',
    _normalizeModelKey(_geminiApiPreview31ProModel):
        'Accepted preview model on the Gemini Code Assist API.',
    _normalizeModelKey(_geminiApiPreview31FlashLiteModel):
        'Accepted preview model on the Gemini Code Assist API.',
  };

  final configured = _discoverGeminiConfiguredModel();
  if (configured != null) {
    models.add(configured);
    details.putIfAbsent(
      _normalizeModelKey(configured),
      () => 'Configured from GEMINI_MODEL or .gemini/settings.json.',
    );
  }

  return _ProviderModelDiscovery(
    models: models.toList(),
    modelDetails: details,
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

Future<_ProviderModelDiscovery?> _discoverApiProviderModels(
  _ProviderSpec spec,
) async {
  final provider = spec.apiProvider;
  if (provider == null) return null;
  final entry = _apiKeysSnapshot[provider.id];
  if (entry == null || entry.apiKey.trim().isEmpty) return null;
  final creds = AiApiCredentials(
    apiKey: entry.apiKey,
    baseUrl: entry.baseUrl,
  );
  try {
    final models = await provider.listModels(creds);
    if (models.isEmpty) return null;
    final pricing = <String, (double?, double?)>{};
    for (final m in models) {
      if (m.promptPricePerToken != null || m.completionPricePerToken != null) {
        pricing[_normalizeModelKey(m.id)] = (
          m.promptPricePerToken != null ? m.promptPricePerToken! * 1e6 : null,
          m.completionPricePerToken != null
              ? m.completionPricePerToken! * 1e6
              : null,
        );
      }
    }
    final reasoning = <String>{};
    for (final m in models) {
      if (m.supportsReasoning || provider.allModelsSupportReasoning) {
        reasoning.add(_normalizeModelKey(m.id));
      }
    }
    return _ProviderModelDiscovery(
      models: models.map((m) => m.id).toList(),
      modelDetails: {
        for (final m in models)
          if (m.displayName != null || m.description != null)
            _normalizeModelKey(m.id): [
              if (m.displayName != null) m.displayName!,
              if (m.description != null) m.description!,
            ].join(' — '),
      },
      modelPricing: pricing,
      reasoningModels: reasoning,
    );
  } catch (_) {
    return null;
  }
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
  // Optional overrides used by PR-review flows (branches page) that
  // already have a raw diff in hand and don't want the working-tree
  // git-derivation. When [rawDiffOverride] is non-empty, the initial
  // branch/status/stat/diff derivation is skipped and these overrides
  // are routed directly into the downstream context-enrichment pipe.
  // The logos-diffusion, project-sense, and prompt-builder phases are
  // diff-source-agnostic so they run uniformly for either flow.
  String? rawDiffOverride,
  String? branchNameOverride,
  String? statusSummaryOverride,
  String? statSummaryOverride,
  // Optional semantic priors for the manifest builder. Null = skip
  // those enhancements (manifest still emits themes/moves from the
  // logos+engram signal). App-layer callers fetch these from
  // FileCouplingState / SymbolFrequencyState and pass down.
  SymbolFrequencyIndex? symbolIndex,
  FileCouplingMatrix? couplingMatrix,
}) async {
  final scopeArgs =
      scopedPaths.isEmpty ? const <String>[] : ['--', ...scopedPaths];

  final String branchName;
  final String statusSummary;
  final String statSummary;
  final String fullDiff;

  if (rawDiffOverride != null && rawDiffOverride.trim().isNotEmpty) {
    branchName = branchNameOverride ?? '(pr)';
    statusSummary = statusSummaryOverride ?? '';
    statSummary = statSummaryOverride ?? '';
    fullDiff = rawDiffOverride;
  } else {
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

    // Diff flags chosen for AI review quality.
    // Context lines adapt to scope size: small changes get more surrounding
    // code (the AI sees the full function), large changes get less (save
    // token budget for actual changes).
    final fileCount = scopeArgs.length > 1 ? scopeArgs.length - 1 : 10;
    final contextLines = fileCount <= 3 ? 15 : (fileCount <= 10 ? 10 : 6);
    final diffFlags = [
      '--no-color',
      '-U$contextLines',
      '--patience',
      '-M',
      '--ignore-cr-at-eol',
    ];

    final stagedDiff = includeStaged
        ? await _runGitCommand(
            repositoryPath,
            ['diff', '--cached', ...diffFlags, ...scopeArgs],
            timeout: const Duration(seconds: _diffTimeoutSeconds),
          )
        : const GitResult.ok('');
    if (!stagedDiff.ok) {
      return _CommitDiffContextResult.err(stagedDiff.error!);
    }

    final unstagedDiff = includeUnstaged
        ? await _runGitCommand(
            repositoryPath,
            ['diff', ...diffFlags, ...scopeArgs],
            timeout: const Duration(seconds: _diffTimeoutSeconds),
          )
        : const GitResult.ok('');
    if (!unstagedDiff.ok) {
      return _CommitDiffContextResult.err(unstagedDiff.error!);
    }

    // Untracked files are invisible to `git diff` and `git diff --cached` —
    // they only appear in `git status` as '??'. For the AI reviewer, those
    // are just new files with their full content as added lines. Synthesize
    // proper unified-diff entries for each one so the reviewer can see them.
    final untrackedDiff = includeUnstaged
        ? await _collectUntrackedFilesDiff(repositoryPath, scopeArgs)
        : '';

    fullDiff = _joinDiffSections(
      stagedDiff: stagedDiff.data ?? '',
      unstagedDiff: unstagedDiff.data ?? '',
      untrackedDiff: untrackedDiff,
    );
    if (fullDiff.trim().isEmpty) {
      return _CommitDiffContextResult.err(
        'No diff content is available for $scopeLabel.',
      );
    }
    branchName = branch.data?.trim() ?? '';
    statusSummary = status.data ?? '';
    statSummary = _joinStatSections(
      stagedStat: stagedStat.data ?? '',
      unstagedStat: unstagedStat.data ?? '',
    );
  }

  // Kick off git telemetry now — six subprocesses that don't depend on
  // any of the heavy work below. They run on isolate-backed Process
  // APIs while the main thread does its CPU work. Awaited at the end
  // where we actually need the results; the concurrent window covers
  // the hunk-diffusion + logos-diffusion + context-assembly phases.
  final telemetryFuture = Future.wait([
    _runGitCommand(repositoryPath, ['rev-list', '--count', 'HEAD']),
    _runGitCommand(repositoryPath, ['log', '--format=%h %s', '-10']),
    _runGitCommand(repositoryPath, ['log', '--format=%an', '-1']),
    _runGitCommand(repositoryPath, ['log', '--format=%cr', '-1']),
    _runGitCommand(
        repositoryPath, ['log', '--max-parents=0', '--format=%cr', 'HEAD']),
    _runGitCommand(repositoryPath, ['log', '--format=%an', '-50']),
  ]);

  // Run the Logos diffusion BEFORE the diff-prompt bundle so the
  // bundler's hunk ranking can reuse the evidence that diffusion
  // already produced. gatherEvidence takes 1-5 seconds on the engine
  // cache path for diffs touching many files; doing it twice per
  // review (once here, once inside rankHunksByPhiAsync via
  // `_resolveFileCoupling`) was pure waste.
  final logos = await _runLogosDiffusion(
    repositoryPath: repositoryPath,
    diffText: fullDiff,
  );

  // Frame-yield after the diffusion CPU burst so Flutter can paint
  // before we start the hunk-level graph work.
  await Future<void>.delayed(Duration.zero);

  // Distil the file-level evidence into the cheap view the hunk
  // ranker consumes. Null when diffusion is cold — the ranker will
  // fall back to its own `_resolveFileCoupling` path in that case.
  final hunkFileEvidence = logos?.evidence != null
      ? hunks.buildHunkFileEvidenceFromResiduals(
          logos!.evidence!.residualByPath,
        )
      : null;

  final diffBundle = await _buildDiffPromptBundle(
    fullDiff,
    repositoryPath: repositoryPath,
    symbolIndex: symbolIndex,
    couplingMatrix: couplingMatrix,
    precomputedFileEvidence: hunkFileEvidence,
  );

  await Future<void>.delayed(Duration.zero);

  // Five anti-hallucination layers gathered simultaneously. The budget
  // split between sections is derived from two Logos signals on the
  // diff probe:
  //   coh = mean pairwise Born-mixed edge weight on primary paths
  //         (high → primary set is tightly clustered on the file graph;
  //         low → scattered)
  //   y   = (M-axis matches + Ab-axis matches) / (primary + M + Ab)
  //         (high → many neighbourhood edges leave the primary set;
  //         low → diff is self-contained on the graph)
  //
  // Each producer's `urgency()` returns one of these compositions:
  //
  //   share_relevance   = (1 − coh) · y       [scattered + many edges]
  //   share_metadata    = (1 − coh) · (1 − y) [scattered + few edges]
  //   share_fileContext = coh                 [tightly clustered]
  //
  //   sum = (1 − coh) + coh = 1 — algebraic by construction, NOT
  //   physics. The three urgencies were chosen so they partition unit
  //   urgency exactly when these three producers are the registered
  //   set; the engine's softmax handles any other producer mix
  //   automatically. The intuition behind each share's shape is in
  //   the per-producer `urgency()` doc.

  // Two irreducible model-level constants. Neither is a UX knob — both
  // hoisted to top-level (see `_kReviewOverheadChars`,
  // `_kModelOutputReservation`) so every prompt-building flow can share
  // the same numbers.
  final rawContextBudget =
      _maxPromptChars - diffBundle.promptBody.length - _kReviewOverheadChars;
  final contextBudget =
      (rawContextBudget * (1.0 - _kModelOutputReservation)).round();

  // `logos` was computed above before _buildDiffPromptBundle so the
  // hunk ranker could reuse its evidence. Fall through to the producer
  // setup using that same artifact.

  // Compose the producer set this caller wants. Variable-pool producers
  // (file_context, file_metadata, relevance_neighborhood) split the
  // remaining budget by softmax over their Logos-derived urgencies.
  // Fixed-cost producers (change_types, structural_verification) reserve
  // an estimate of their natural size up front.
  final engine = AiContextEngine([
    const _FileContextProducer(),
    const _FileMetadataProducer(),
    const _ExecutionFlowProducer(),
    const _LogosTopologyProducer(),
    const _RelevanceNeighborhoodProducer(),
    _ChangeTypesProducer(
      scopeArgs: scopeArgs,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
    ),
    const _StructuralVerificationProducer(),
  ]);
  // Assemble + stitch in one pass. Each producer declares its own
  // wrapper tag and display order, so adding/removing a producer is a
  // one-line registration change — no per-section unpacking, no
  // hardcoded section ordering, no risk of forgetting to wire the
  // new section into the prompt body.
  final assembled = await engine.assembleAndStitch(
    AiContextRequest(
      repositoryPath: repositoryPath,
      diffText: fullDiff,
      logos: logos,
    ),
    contextBudget,
  );
  final logosEmissionRecord = assembled.sections['relevance_neighborhood']
      ?.metadataOfType<LogosEmissionRecord>();
  final enrichedPromptBody = assembled.body.isEmpty
      ? diffBundle.promptBody
      : '${diffBundle.promptBody}\n\n${assembled.body}';

  final enrichedBundle = _DiffPromptBundle(
    promptBody: enrichedPromptBody,
    originalDiffCharacters: diffBundle.originalDiffCharacters,
  );

  // Telemetry was kicked off at the top of the function concurrently
  // with the CPU-heavy diffusion/assembly phases. Await now — the
  // six subprocess fetches likely completed while logos did its work.
  final telemetry = await telemetryFuture;

  final totalCommits = int.tryParse((telemetry[0].data ?? '').trim()) ?? 0;

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
      branchName: branchName.trim().isEmpty ? 'HEAD' : branchName.trim(),
      statusSummary: statusSummary.trim(),
      statSummary: statSummary.trim(),
      diffBundle: enrichedBundle,
      totalCommits: totalCommits,
      recentLog: recentLog,
      authorName: authorName,
      lastCommitAge: lastCommitAge,
      projectAge: projectAge,
      uniqueContributors: uniqueContributors,
      logosEmissionRecord: logosEmissionRecord,
    ),
  );
}

String _joinDiffSections({
  required String stagedDiff,
  required String unstagedDiff,
  String untrackedDiff = '',
}) {
  final sections = <String>[];
  if (stagedDiff.trim().isNotEmpty) {
    sections.add('=== STAGED CHANGES ===\n$stagedDiff');
  }
  if (unstagedDiff.trim().isNotEmpty) {
    sections.add('=== UNSTAGED CHANGES ===\n$unstagedDiff');
  }
  if (untrackedDiff.trim().isNotEmpty) {
    // Untracked files are not yet in git's index — they look like "new
    // files" to a human reader, which is exactly how the synthesized
    // diff entries render them.
    sections.add('=== UNTRACKED (NEW) FILES ===\n$untrackedDiff');
  }
  if (sections.isEmpty) {
    return '';
  }
  return sections.join('\n\n');
}

/// Build unified-diff entries for all untracked files.
/// `git diff` and `git diff --cached` never show untracked files, but new
/// files are exactly the kind of thing an AI reviewer needs to see (or
/// it'll hallucinate that they don't exist). We read each file's content
/// and emit a synthetic `/dev/null → b/<path>` diff block so the reviewer
/// gets the full new file content as added lines.
/// [scopeArgs] follows the same convention as elsewhere — either `['--']`
/// for "all files" or `['--', path1, path2, ...]` to restrict scope.
/// Decode bytes as UTF-8, tolerating malformed sequences by falling back
/// to a byte-for-byte reading. Most source files are UTF-8; using the
/// Latin-1-ish `String.fromCharCodes` corrupts any non-ASCII character
/// (emoji, accented letters, smart quotes) — that matters for AI review
/// because the model needs to see the file as it actually is.
String _tryDecodeUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return String.fromCharCodes(bytes);
  }
}

Future<String> _collectUntrackedFilesDiff(
  String repositoryPath,
  List<String> scopeArgs,
) async {
  // List untracked, non-ignored files. `--exclude-standard` respects
  // .gitignore + global excludes + .git/info/exclude.
  final listArgs = <String>[
    'ls-files',
    '--others',
    '--exclude-standard',
    ...scopeArgs,
  ];
  final listResult = await _runGitCommand(
    repositoryPath,
    listArgs,
    timeout: const Duration(seconds: _diffTimeoutSeconds),
  );
  if (!listResult.ok) return '';
  final paths = (listResult.data ?? '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (paths.isEmpty) return '';

  final buffer = StringBuffer();
  const perFileCapBytes = 64 * 1024; // cap any single file's preview
  const totalCapBytes = 512 * 1024; // and the combined block
  var totalBytes = 0;

  for (final relPath in paths) {
    if (totalBytes >= totalCapBytes) {
      buffer.writeln(
        '(further untracked files omitted — total preview cap reached)',
      );
      break;
    }
    final absPath = p.join(repositoryPath, relPath);
    String content;
    try {
      final file = File(absPath);
      if (!await file.exists()) continue;
      // Skip binary-looking files quickly by checking size + a null byte
      // probe of the first chunk.
      final stat = await file.stat();
      if (stat.size == 0) {
        // Empty new file — still worth showing as an "empty new file" marker.
        content = '';
      } else if (stat.size > perFileCapBytes) {
        final raw = await file.openRead(0, perFileCapBytes).toList();
        final bytes = raw.expand((x) => x).toList();
        if (bytes.contains(0)) continue; // binary
        // Decode as UTF-8 (most source files) and fall back to the raw
        // code points if that fails, so we don't corrupt multi-byte
        // characters (emoji, non-Latin scripts, smart quotes).
        content = _tryDecodeUtf8(bytes) +
            '\n(truncated — file larger than ${perFileCapBytes ~/ 1024}KB)';
      } else {
        final bytes = await file.readAsBytes();
        if (bytes.contains(0)) continue; // binary
        content = _tryDecodeUtf8(bytes);
      }
    } catch (_) {
      continue;
    }
    final lines = content.split('\n');
    // Strip trailing empty line caused by final newline, if any.
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final lineCount = lines.isEmpty ? 0 : lines.length;
    final addedBlock = lines.map((l) => '+$l').join('\n');
    final entry = [
      'diff --git a/$relPath b/$relPath',
      'new file mode 100644',
      '--- /dev/null',
      '+++ b/$relPath',
      '@@ -0,0 +1,$lineCount @@',
      if (addedBlock.isNotEmpty) addedBlock,
    ].join('\n');
    totalBytes += entry.length;
    buffer.writeln(entry);
    buffer.writeln();
  }
  return buffer.toString();
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

/// Collect git metadata for changed files — authorship, churn, test coverage.
/// This is the "other 70%" of review context beyond the diff itself.
Future<String> _collectFileMetadata({
  required String repositoryPath,
  required String diffText,
  required int budgetChars,
}) async {
  if (budgetChars <= 0) return '';

  final paths = extractDiffTouchedPaths(diffText);
  if (paths.isEmpty) return '';

  final buffer = StringBuffer();
  var remaining = budgetChars;

  // Gather metadata with a concurrency cap. Each file spawns 4 git
  // commands, so 15 files = 60 processes — a sane ceiling.
  // Batch size adapts to file count — small changes run fully parallel,
  // large changes batch to avoid process table saturation.
  final sortedPaths = paths.toList()..sort();
  final batchSize = sortedPaths.length <= 10
      ? sortedPaths.length // Few files: all parallel
      : (sortedPaths.length <= 30 ? 10 : 8); // Many files: controlled batches
  final results = <_FileMetaResult>[];

  for (var i = 0; i < sortedPaths.length; i += batchSize) {
    final batch = sortedPaths.skip(i).take(batchSize);
    final batchResults = await Future.wait(
      batch.map((filePath) => _gatherFileMeta(repositoryPath, filePath)),
    );
    results.addAll(batchResults);
    if (remaining <= 100) break; // stop early if budget exhausted
  }

  for (final meta in results) {
    if (remaining <= 100) break;

    final block = StringBuffer();
    block.writeln('${meta.path}:');

    if (meta.churnCount > 0) {
      block.writeln('  commits: ${meta.churnCount} (last 90 days)');
    }
    if (meta.authors.isNotEmpty) {
      block.writeln('  authors: ${meta.authors.take(5).join(', ')}');
    }
    if (meta.lastAuthor.isNotEmpty) {
      block.writeln('  last modified by: ${meta.lastAuthor} (${meta.lastAge})');
    }
    if (meta.fileAge.isNotEmpty) {
      block.writeln('  created: ${meta.fileAge}');
    }
    if (meta.hasTest) {
      block.writeln('  test file: exists');
    }

    final entry = block.toString();
    if (entry.length > remaining) continue;
    buffer.write(entry);
    remaining -= entry.length;
  }

  return buffer.toString();
}

Future<_FileMetaResult> _gatherFileMeta(String repo, String filePath) async {
  try {
    final results = await Future.wait([
      // Churn: how many commits touched this file recently.
      // Uses --since instead of -N so it adapts to repo activity naturally.
      _runGitCommand(repo, [
        'log',
        '--oneline',
        '--follow',
        '--since=90.days',
        '--',
        filePath,
      ]),
      // Recent authors: who has touched this file.
      // -20 captures enough for knowledge distribution without over-querying.
      _runGitCommand(repo, [
        'log',
        '--format=%an',
        '-20',
        '--follow',
        '--',
        filePath,
      ]),
      // Last modifier + age (use %x00 null byte as separator — safe from
      // any content in author names, unlike string delimiters).
      _runGitCommand(repo, [
        'log',
        '--format=%an%x00%cr',
        '-1',
        '--follow',
        '--',
        filePath,
      ]),
      // File creation date
      _runGitCommand(repo, [
        'log',
        '--diff-filter=A',
        '--format=%cr',
        '--follow',
        '--',
        filePath,
      ]),
    ]);

    final churnLines = (results[0].data ?? '').trim().split('\n');
    final churnCount = churnLines.where((l) => l.isNotEmpty).length;

    final authorLines = (results[1].data ?? '').trim().split('\n');
    final authors = authorLines.where((l) => l.isNotEmpty).toSet().toList();

    final lastParts = (results[2].data ?? '').trim().split('\x00');
    final lastAuthor = lastParts.isNotEmpty ? lastParts[0] : '';
    final lastAge = lastParts.length > 1 ? lastParts[1] : '';

    final fileAge = (results[3].data ?? '').trim();

    // Test file detection: check common patterns.
    final hasTest = await _detectTestFile(repo, filePath);

    return _FileMetaResult(
      path: filePath,
      churnCount: churnCount,
      authors: authors,
      lastAuthor: lastAuthor,
      lastAge: lastAge,
      fileAge: fileAge,
      hasTest: hasTest,
    );
  } catch (_) {
    return _FileMetaResult(path: filePath);
  }
}

/// Language-agnostic test file detection via path patterns.
/// Uses async I/O to avoid blocking the event loop.
Future<bool> _detectTestFile(String repo, String filePath) async {
  final name = p.basenameWithoutExtension(filePath);
  final ext = p.extension(filePath);
  final dir = p.dirname(filePath);

  // Common test file patterns: foo_test.dart, foo.test.ts, test_foo.py, etc.
  final testPatterns = [
    p.join(dir, '${name}_test$ext'),
    p.join(dir, '$name.test$ext'),
    p.join(dir, '${name}_spec$ext'),
    p.join(dir, '$name.spec$ext'),
    p.join(dir, 'test_$name$ext'),
  ];

  for (final testPath in testPatterns) {
    if (await File(p.join(repo, testPath)).exists()) return true;
  }
  return false;
}

class _FileMetaResult {
  final String path;
  final int churnCount;
  final List<String> authors;
  final String lastAuthor;
  final String lastAge;
  final String fileAge;
  final bool hasTest;

  const _FileMetaResult({
    required this.path,
    this.churnCount = 0,
    this.authors = const [],
    this.lastAuthor = '',
    this.lastAge = '',
    this.fileAge = '',
    this.hasTest = false,
  });
}

/// Runs `git diff --name-status -M -C` to get the change type per file.
/// Tells the AI whether each file is Added/Modified/Deleted/Renamed/Copied
/// so it doesn't guess.
Future<String> _collectChangeTypes({
  required String repositoryPath,
  required List<String> scopeArgs,
  required bool includeStaged,
  required bool includeUnstaged,
}) async {
  try {
    final results = <String>[];

    if (includeStaged) {
      final r = await _runGitCommand(repositoryPath, [
        'diff',
        '--cached',
        '--name-status',
        '-M',
        '-C',
        ...scopeArgs,
      ]);
      if (r.ok && (r.data ?? '').trim().isNotEmpty) {
        results.add(r.data!.trim());
      }
    }
    if (includeUnstaged) {
      final r = await _runGitCommand(repositoryPath, [
        'diff',
        '--name-status',
        '-M',
        '-C',
        ...scopeArgs,
      ]);
      if (r.ok && (r.data ?? '').trim().isNotEmpty) {
        results.add(r.data!.trim());
      }
    }

    final combined = results.join('\n');
    if (combined.isEmpty) return '';

    // Annotate with human-readable descriptions for the AI.
    final lines = combined.split('\n').where((l) => l.trim().isNotEmpty);
    final annotated = StringBuffer();
    for (final line in lines) {
      final status = line.isNotEmpty ? line[0] : '?';
      final desc = switch (status) {
        'A' => 'new file',
        'M' => 'modified',
        'D' => 'deleted',
        'R' => 'renamed',
        'C' => 'copied',
        'T' => 'type changed',
        _ => 'changed',
      };
      annotated.writeln('$line  ($desc)');
    }
    return annotated.toString();
  } catch (e) {
    // Emit the failure so the LLM knows the change-types channel was
    // attempted but didn't produce; otherwise a silent empty body
    // reads as "no changes to report" — a dangerous false signal.
    return '<engine_failure channel="change_types" reason="${_escapeFailureReason(e)}"/>\n';
  }
}

/// Escape an exception's string form for embedding as the `reason=`
/// attribute of an `<engine_failure>` tag. The prompt is XML-ish; a
/// raw `"`, `<`, `>`, or `&` from a path or error message would
/// produce malformed markup that the LLM has to heal mentally. Maps
/// those four characters to their named entities (ampersand first so
/// we don't double-escape the entities we just inserted) and collapses
/// newlines/tabs to spaces so the attribute stays single-line.
String _escapeFailureReason(Object e) => e
    .toString()
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('\n', ' ')
    .replaceAll('\r', ' ')
    .replaceAll('\t', ' ');

/// Scans the diff for import statements and new symbol definitions,
/// then verifies them against the working tree. Produces a compact
/// verification summary the AI can trust instead of guessing.
Future<String> _collectStructuralVerification({
  required String repositoryPath,
  required String diffText,
}) async {
  try {
    final buffer = StringBuffer();

    // 1. Import verification — check if import targets exist on disk.
    final importVerification = await _verifyImports(repositoryPath, diffText);
    if (importVerification.isNotEmpty) {
      buffer.writeln('Import verification:');
      buffer.write(importVerification);
      buffer.writeln();
    }

    // 2. Symbol grep — verify new function/class names exist in the repo.
    final symbolVerification = await _verifySymbols(repositoryPath, diffText);
    if (symbolVerification.isNotEmpty) {
      buffer.writeln('Symbol verification:');
      buffer.write(symbolVerification);
    }

    // 3. Removal verification — confirm removed symbols are dead code.
    final removalVerification = await _verifyRemovals(repositoryPath, diffText);
    if (removalVerification.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Removal verification:');
      buffer.write(removalVerification);
    }

    return buffer.toString();
  } catch (e) {
    // Never return a silent empty body: the LLM would read that as
    // "verification ran and found nothing wrong" (a false green).
    // Emitting the failure keeps the reviewer honest about what the
    // engine did and did not check.
    return '<engine_failure channel="structural_verification" reason="${_escapeFailureReason(e)}"/>\n';
  }
}

/// Scan added lines for import/require/from patterns, verify targets exist.
/// Tracks which file each import belongs to so relative paths resolve correctly.
Future<String> _verifyImports(String repositoryPath, String diffText) async {
  final importPattern = RegExp(
    r'''^\+\s*(?:import\s+['"]([^'"]+)['"]|'''
    r'''(?:const|var|let|final)\s+\w+\s*=\s*require\(['"]([^'"]+)['"]\)|'''
    r'''from\s+['"]([^'"]+)['"])''',
  );
  final seen = <String>{};
  final results = StringBuffer();
  String? currentFile;

  for (final line in diffText.split('\n')) {
    // Track which file we're in so relative imports resolve correctly.
    final headerPath = diffHeaderPath(line);
    if (headerPath != null) {
      currentFile = headerPath;
      continue;
    }

    if (!line.startsWith('+') || line.startsWith('+++')) continue;

    final match = importPattern.firstMatch(line);
    if (match == null) continue;

    final importPath = match.group(1) ?? match.group(2) ?? match.group(3);
    if (importPath == null) continue;
    if (importPath.startsWith('dart:') || importPath.startsWith('package:'))
      continue;
    if (!seen.add('$currentFile→$importPath')) continue;

    // Resolve relative to the importing file's directory.
    final importingDir = currentFile != null
        ? p.dirname(p.join(repositoryPath, currentFile))
        : repositoryPath;
    final resolved = p.normalize(p.join(importingDir, importPath));
    final exists = await File(resolved).exists();

    results.writeln(
        '  ${exists ? "✓" : "✗"} $importPath${exists ? "" : " (NOT FOUND)"}');
  }

  return results.toString();
}

/// Extract new function/class/variable names from added lines, grep for them.
Future<String> _verifySymbols(String repositoryPath, String diffText) async {
  // Extract symbol names from added lines that look like definitions.
  final defPattern = RegExp(
    r'^\+\s*(?:class|enum|mixin|extension|typedef)\s+(\w+)|'
    r'^\+\s*(?:void|Future|String|int|bool|double|List|Map|Set|Widget|dynamic)\s*<?[^>]*>?\s+(\w+)\s*[(<]|'
    r'^\+\s*(?:final|const|var|late)\s+\w+\s+(\w+)\s*=',
    multiLine: true,
  );

  final symbols = <String>{};
  for (final match in defPattern.allMatches(diffText)) {
    final name = match.group(1) ?? match.group(2) ?? match.group(3);
    if (name != null && name.length > 2 && !name.startsWith('_')) {
      symbols.add(name);
    }
  }

  if (symbols.isEmpty) return '';

  // Cap adapts to symbol count — verify more when there are few,
  // sample when there are many. Diminishing returns past ~15.
  final maxLookups =
      symbols.length <= 5 ? symbols.length : (symbols.length <= 20 ? 12 : 8);
  final results = StringBuffer();
  var count = 0;
  for (final symbol in symbols) {
    if (count >= maxLookups) break;
    count++;

    try {
      final grep = await _runGitCommand(repositoryPath, [
        'grep',
        '-l',
        '-w',
        '--fixed-strings',
        symbol,
      ]);
      if (grep.ok && (grep.data ?? '').trim().isNotEmpty) {
        final files = (grep.data ?? '')
            .trim()
            .split('\n')
            .where((f) => f.isNotEmpty)
            .toList();
        results.writeln(
            '  $symbol: found in ${files.length} file${files.length == 1 ? "" : "s"} (${files.take(3).join(", ")}${files.length > 3 ? ", ..." : ""})');
      } else {
        results.writeln('  $symbol: not found in repo');
      }
    } catch (_) {
      continue;
    }
  }

  return results.toString();
}

/// Verify that removed function/class definitions are no longer referenced.
/// Confirms the removal is safe dead-code cleanup, not an accidental regression.
Future<String> _verifyRemovals(String repositoryPath, String diffText) async {
  // Extract symbol names from REMOVED lines that look like definitions.
  // Language-agnostic: matches type/class declarations and any function
  // signature pattern (word followed by parens), not a hardcoded type list.
  final defPattern = RegExp(
    r'^-\s*(?:class|enum|mixin|extension|typedef|struct|interface|trait)\s+(\w+)|'
    r'^-\s*(?:(?:export|pub|static|async|const|final|var|let|val)\s+)*(?:[A-Z]\w*|void|int|bool|double|float|long|char|string|num)[<>\[\]?,\w]*\s+(\w+)\s*[(<]',
    multiLine: true,
  );

  final removedSymbols = <String>{};
  for (final match in defPattern.allMatches(diffText)) {
    final name = match.group(1) ?? match.group(2);
    if (name != null && name.length > 3 && !name.startsWith('_')) {
      removedSymbols.add(name);
    }
  }

  if (removedSymbols.isEmpty) return '';

  final results = StringBuffer();
  var count = 0;
  for (final symbol in removedSymbols) {
    if (count >= 8) break;
    count++;
    try {
      final grep = await _runGitCommand(repositoryPath, [
        'grep',
        '-l',
        '-w',
        '--fixed-strings',
        symbol,
      ]);
      final files = (grep.ok ? (grep.data ?? '') : '')
          .trim()
          .split('\n')
          .where((f) => f.isNotEmpty)
          .toList();
      if (files.isEmpty) {
        results
            .writeln('  ✓ $symbol: safely removed (no remaining references)');
      } else {
        results.writeln(
            '  ⚠ $symbol: still referenced in ${files.length} file(s) (${files.take(3).join(", ")})');
      }
    } catch (_) {
      continue;
    }
  }

  return results.toString();
}

/// Collect full file contents for small changed files to give the AI
/// reviewer complete context (imports, function signatures, surrounding code).
/// Budget-aware: fills up to [budgetChars] with the most impactful files
/// (largest diffs first), skipping files that exceed the remaining budget.
/// Language-agnostic — just reads the working tree file.
Future<String> _collectFileContext({
  required String repositoryPath,
  required String diffText,
  required int budgetChars,
}) async {
  if (budgetChars <= 0) return '';

  // Extract changed file paths from the diff headers.
  final paths = extractDiffTouchedPaths(diffText);
  if (paths.isEmpty) return '';

  // Logos-driven prioritization. Instead of arbitrary line-count
  // thresholds + alphabetical iteration (which happened to drop a
  // critical `z*.dart` while keeping a trivial `a*.dart`), use the
  // attention-codec engine to rank touched files by their self-φ
  // (post-diffusion heat retained at the source). The "core" files of
  // the change — the ones the surrounding manifold attests are most
  // central — get included first. Marginal files drop off naturally
  // when budget exhausts.
  //
  // Full content first; if a file blows the remaining budget at full
  // size, fall back to intra-file chunk diffusion (logos_chunks): chunk
  // the file on signature boundaries, build a mini chunk-graph, diffuse
  // from the diff-touched line ranges as the heat source, and greedy-
  // pack chunks by φ. The "snaking attention head" — adjacent admitted
  // chunks render as continuous excerpts. Neighborhood diffusion does
  // NOT backstop primary paths (it excludes them by design), so this is
  // where structural awareness for large diff-touched files lives.
  final pathList = paths.toList();
  List<String> orderedPaths;
  LogosGit? engine;
  LogosEvidenceQueryResult? fileContextEvidence;
  String? engineFailureReason;
  try {
    engine = await resolveLogosGit(repositoryPath);
    if (engine != null) {
      // Self-φ via heat-kernel: how much heat each source file retains
      // after t=1.0 diffusion. Files coupled to a strong neighborhood
      // bleed less; isolated files bleed most. Highest-retention files
      // are the most "anchored" parts of the change.
      final sourceWeights = {for (final p in pathList) p: 1.0};
      fileContextEvidence = engine.gatherEvidence(
        focusWeights: sourceWeights,
        excludePaths: const {},
        detailBudget: 24,
        includeSupportAttribution: false,
        includeSummaryDiagnostics: false,
      );
      // Default t=1.0 is the canonical self-φ diffusion distance — any
      // other temperature would change what "anchored" means and break
      // the retention-ranking heuristic documented above.
      final residualByPath = fileContextEvidence?.residualByPath ??
          const <String, LogosResidualView>{};
      if (pathList.every(residualByPath.containsKey)) {
        orderedPaths = [...pathList]..sort((a, b) {
            final pa = residualByPath[a]?.support ?? 0.0;
            final pb = residualByPath[b]?.support ?? 0.0;
            final cmp = pb.compareTo(pa); // desc
            if (cmp != 0) return cmp;
            return a.compareTo(b); // alphabetical tiebreaker for determinism
          });
      } else {
        final scores =
            engine.diffuseWeighted(sourceWeights, excludePaths: const {});
        final phi = {for (final s in scores) s.path: s.phi};
        orderedPaths = [...pathList]..sort((a, b) {
            final pa = phi[a] ?? 0.0;
            final pb = phi[b] ?? 0.0;
            final cmp = pb.compareTo(pa); // desc
            if (cmp != 0) return cmp;
            return a.compareTo(b); // alphabetical tiebreaker for determinism
          });
      }
    } else {
      // No engine available (early profile build, empty repo). Fall
      // back to alphabetical — better than randomized iteration order.
      orderedPaths = [...pathList]..sort();
    }
  } catch (e) {
    orderedPaths = [...pathList]..sort();
    engineFailureReason = _escapeFailureReason(e);
  }

  final touchedRangesByFile = chunks.touchedRangesByFileFromDiff(diffText);
  final buffer = StringBuffer();
  if (engineFailureReason != null) {
    // Logos engine failed to resolve — keep a deterministic ordering
    // (alphabetical) and annotate so the LLM sees *why* the files
    // aren't Logos-ranked this turn instead of quietly reading the
    // list as "this is the Logos ranking" (a false green signal).
    buffer.writeln(
        '<engine_failure channel="file_ordering" reason="$engineFailureReason"/>');
  }
  var remaining = budgetChars;
  for (final filePath in orderedPaths) {
    if (remaining <= 0) break;
    try {
      final file = File(p.join(repositoryPath, filePath));
      if (!await file.exists()) continue;
      final content = await file.readAsString();
      final lineCount = _countLinesPlusOne(content);
      // Engram semantic well annotation. The resolver populates
      // `engine.perFileKVectors` for every file the engine has
      // encoded (working-tree content → K-vector). When present, we
      // emit the dominant well next to the file path so the LLM sees
      // a semantic pill (`[well=computing]`, `[well=well_42]`) on
      // every file header. Silent when engram assets didn't load or
      // the file was unencodable — no noisy empty labels.
      final well = engine?.wellOf(filePath);
      final wellPill = well != null ? ' [well=$well]' : '';
      final block = '--- $filePath ($lineCount lines)$wellPill ---\n$content\n';
      if (block.length <= remaining) {
        buffer.write(block);
        remaining -= block.length;
        continue;
      }
      // Over-budget at full size — try the chunk-pack fallback. Build
      // touched line ranges from the diff so the chunk diffusion knows
      // where the heat source is.
      final touched =
          touchedRangesByFile[filePath] ?? const <chunks.TouchedLineRange>[];
      final fileResidual = fileContextEvidence?.residualByPath[filePath];
      final pack = await chunks.packRelevantChunksAsync(
        filePath: filePath,
        content: content,
        touchedRanges: touched,
        budgetChars: remaining,
        fileTransportedSupport: fileResidual?.transportedSupport ?? 0.0,
        fileInnovationResidual: fileResidual?.innovationResidual ?? 0.0,
        fileWitnessResidual: fileResidual?.witnessResidual ?? 0.0,
        fileEvidenceTags: fileResidual == null
            ? const <String>[]
            : _evidenceTagParts(fileResidual, includeWitnessNotes: false),
        fileEvidenceWitnesses: fileResidual?.witnesses ?? const [],
      );
      if (pack.body.isEmpty) continue;
      buffer.write(pack.body);
      remaining -= pack.body.length;
    } catch (_) {
      continue;
    }
  }

  return buffer.toString();
}

/// Collect *relevance neighborhood* — files NOT in the diff but strongly
/// connected to it via historical co-change, directory proximity, global
/// touch frequency, and volatility match. This surfaces the "hidden
/// caller" class of bugs: things the reviewer needs to see even though
/// they weren't changed.
/// Uses the Logos-inspired git engine ([LogosGit]). The diff's touched
/// paths become a heat source ρ; relevance φ is the heat-kernel
/// diffusion φ = exp(-t·L_sym)·ρ at t=1.0 (commit-review scope).
/// Emission follows a greedy-density knapsack with three tiers:
///   FULL       — full source; chunk-pack fallback if oversized
///   SIGNATURE  — outline (same format as [_buildFileOutline])
///   BREADCRUMB — one-liner with path + score + dominant axis
/// Budget-bounded. Returns an empty string on any error — this is a
/// best-effort enrichment layer; failures never poison the primary
/// context path.
// Concrete producers wired to the existing _collect* functions. Private
// to ai.dart because they wrap private collectors; the engine they slot
// into ([AiContextEngine]) is public.
//
// Each producer's urgency function is derived from Logos signals
// only. The math is:
//
//   file_context = coh
//   relevance    = dispersion · yieldFraction
//   metadata     = dispersion · (1 − yieldFraction)
//
// sum = coh + dispersion. The engine's softmax normalises by this
// sum, so the pair (coh, dispersion) drives the split: a coherent
// diff allocates to file_context, a dispersed one to the
// metadata/relevance pair. The split WITHIN that pair is gated by
// yieldFraction.
//
// When probe is null or primaryCount == 0, file_context returns 1.0
// and the others return 0.0. [AiContextEngine] excludes zero-urgency
// producers from allocation, so file_context absorbs the full
// variable pool — the only useful producer when there's no signal.

class _FileContextProducer extends AiContextProducer {
  const _FileContextProducer();
  @override
  String get id => 'file_context';
  @override
  int get order => 40;
  @override
  double? urgency(AiContextRequest req) {
    final probe = req.logos?.probe;
    // No probe = engine cold. File context absorbs everything because
    // we have no signal to allocate to relevance/metadata.
    if (probe == null || probe.stats.primaryCount == 0) return 1.0;
    return _logosYieldOf(probe).coh;
  }

  @override
  Future<AiContextSection> produce(
      AiContextRequest req, int budgetChars) async {
    final body = await _collectFileContext(
      repositoryPath: req.repositoryPath,
      diffText: req.diffText,
      budgetChars: budgetChars,
    );
    return AiContextSection(id: id, body: body);
  }
}

class _FileMetadataProducer extends AiContextProducer {
  const _FileMetadataProducer();
  @override
  String get id => 'file_metadata';
  @override
  int get order => 30;
  @override
  double? urgency(AiContextRequest req) {
    final probe = req.logos?.probe;
    if (probe == null || probe.stats.primaryCount == 0) return 0.0;
    final y = _logosYieldOf(probe);
    return y.dispersion * (1.0 - y.yieldFraction);
  }

  @override
  Future<AiContextSection> produce(
      AiContextRequest req, int budgetChars) async {
    final body = await _collectFileMetadata(
      repositoryPath: req.repositoryPath,
      diffText: req.diffText,
      budgetChars: budgetChars,
    );
    return AiContextSection(id: id, body: body);
  }
}

/// Filament execution-flow analysis.
class _ExecutionFlowProducer extends AiContextProducer {
  const _ExecutionFlowProducer();
  @override
  String get id => 'execution_flow';
  @override
  int get order => 42;
  @override
  double? urgency(AiContextRequest req) {
    // scales with diff size, capped at 0.6.
    final diffLen = req.diffText.length;
    if (diffLen < 100) return null;
    return (diffLen / 10000).clamp(0.1, 0.6);
  }

  @override
  Future<AiContextSection> produce(
      AiContextRequest req, int budgetChars) async {
    if (budgetChars <= 80) {
      return AiContextSection(id: id, body: '');
    }
    final body = await _collectExecutionFlowEvidence(
      repositoryPath: req.repositoryPath,
      diffText: req.diffText,
      budgetChars: budgetChars,
      logosEngine: req.logos?.engine,
    );
    return AiContextSection(id: id, body: body);
  }
}

/// Collect execution-flow findings from all changed files.
Future<String> _collectExecutionFlowEvidence({
  required String repositoryPath,
  required String diffText,
  required int budgetChars,
  LogosGit? logosEngine,
}) async {
  final paths = extractDiffTouchedPaths(diffText);
  if (paths.isEmpty) return '';

  final allFindings = <(String, FlowFinding)>[];
  final fileGaps = <String, double>{};

  // structural anchor from diff-touched files' Logos fingerprints
  int? anchor;
  final basis = logosEngine?.spectralBasis();
  if (logosEngine != null && basis != null) {
    final fps = <int>[
      for (final fp in paths)
        if (logosEngine.pathToId[fp] case final idx?)
          basis.spectralByteFingerprint(idx),
    ];
    if (fps.isNotEmpty) anchor = anchorFingerprint(fps);
  }

  final graphStrengths =
      logosEngine?.couplingStrengths() ?? const <String, double>{};

  final futures = <Future<(String, FlowAnalysisResult?)>>[];
  for (final filePath in paths) {
    futures.add(Future(() async {
      try {
        double? coupling;
        if (anchor != null && basis != null) {
          final idx = logosEngine!.pathToId[filePath];
          if (idx != null) {
            final fingerCoupling = logosFingerCoupling(
                basis.spectralByteFingerprint(idx), anchor);
            final graphCoupling = graphStrengths[filePath] ?? 0.0;
            coupling = math.max(fingerCoupling,
                fingerCoupling * (1 - graphCouplingBlend) +
                    graphCoupling * graphCouplingBlend);
          }
        }
        return (filePath, await analyzeFlowCached(
            p.join(repositoryPath, filePath),
            logosCoupling: coupling));
      } catch (_) {
        return (filePath, null);
      }
    }));
  }

  final results = await Future.wait(futures);
  for (final (filePath, result) in results) {
    if (result == null) continue;
    for (final f in result.findings) {
      if (f.certainty < 0.3) allFindings.add((filePath, f));
    }
    if (result.spectralGap > 0) fileGaps[filePath] = result.spectralGap;
  }

  if (fileGaps.isNotEmpty) {
    LogosVisBus.instance.emitInSession((sid) =>
        LogosVisFlowAnalysis(sid, spectralGaps: Map.unmodifiable(fileGaps)));
  }

  if (allFindings.isEmpty && fileGaps.isEmpty) return '';

  // sort by severity (lowest certainty first)
  allFindings.sort((a, b) => a.$2.certainty.compareTo(b.$2.certainty));

  final buf = StringBuffer();
  if (allFindings.isNotEmpty) {
    buf.writeln('status: ${allFindings.length} execution-flow finding'
        '${allFindings.length == 1 ? '' : 's'}');
  } else {
    buf.writeln('status: clean (no execution-flow issues detected)');
  }
  buf.writeln('engine: filament');

  // spectral gaps
  if (fileGaps.isNotEmpty) {
    final gapEntries = fileGaps.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    buf.writeln();
    buf.writeln('spectral_gap (per-file fragility, higher = more fragile):');
    for (final entry in gapEntries.take(5)) {
      buf.writeln('  ${entry.key}: ${entry.value.toStringAsFixed(3)}');
    }
  }

  buf.writeln();

  var charsUsed = buf.length;
  for (final (path, finding) in allFindings) {
    final line = 'L${finding.sourceLine + 1}';
    final kind = switch (finding.kind) {
      FlowBugKind.staleValue => 'stale value',
      FlowBugKind.temporalShift => 'temporal shift',
      FlowBugKind.contextInversion => 'context inversion',
      FlowBugKind.contradictoryFlow => 'contradictory flow',
    };
    final entry = '[$path:$line] [${finding.severity}] '
        '${finding.sourceText} — $kind '
        '(certainty=${finding.certainty.toStringAsFixed(3)} '
        'paths=${finding.pathCount})\n';

    if (charsUsed + entry.length > budgetChars) break;
    buf.write(entry);
    charsUsed += entry.length;
  }

  return buf.toString();
}

class _LogosTopologyProducer extends AiContextProducer {
  const _LogosTopologyProducer();
  @override
  String get id => 'logos_topology';
  @override
  int get order => 45;
  @override
  double? urgency(AiContextRequest req) => null;
  @override
  int fixedRequest(AiContextRequest req) {
    if (req.logos == null) return 0;
    // Emergent reservation: dry-run the actual collector with no
    // budget cap and reserve exactly the output length. The engine's
    // spectrogeometry + SensitivityField caches make the second call
    // (inside produce) effectively free. No magic constant — the
    // allocation equals the content that will be emitted.
    final body =
        _collectLogosTopology(req.logos, budgetChars: _topologyDryRunBudget);
    return body.length;
  }
  @override
  Future<AiContextSection> produce(
      AiContextRequest req, int budgetChars) async {
    final body = _collectLogosTopology(req.logos, budgetChars: budgetChars);
    return AiContextSection(id: id, body: body);
  }
}

/// Sentinel for the dry-run budget in [_LogosTopologyProducer.fixedRequest].
/// Large enough that `_collectLogosTopology` never truncates; the result's
/// actual length becomes the true reservation.
const int _topologyDryRunBudget = 1 << 20;

class _RelevanceNeighborhoodProducer extends AiContextProducer {
  const _RelevanceNeighborhoodProducer();
  @override
  String get id => 'relevance_neighborhood';
  @override
  int get order => 50;
  @override
  double? urgency(AiContextRequest req) {
    final probe = req.logos?.probe;
    if (probe == null || probe.stats.primaryCount == 0) return 0.0;
    final y = _logosYieldOf(probe);
    return y.dispersion * y.yieldFraction;
  }

  @override
  Future<AiContextSection> produce(
      AiContextRequest req, int budgetChars) async {
    final result = await _collectRelevanceNeighborhood(
      repositoryPath: req.repositoryPath,
      diffText: req.diffText,
      budgetChars: budgetChars,
      logos: req.logos,
    );
    return AiContextSection(
      id: id,
      body: result.text,
      metadata: result.record,
    );
  }
}

/// Always-on producer: change-types classification (A/M/D/R/C/T per
/// file). Lives OUTSIDE the budget pool: returns null urgency AND
/// zero fixed request, so the variable pool stays whole. The
/// underlying `_collectChangeTypes` doesn't take a budget — it emits
/// a few KB at most (one short line per touched file), absorbed by
/// the model-API output reservation just like before the engine
/// existed. Same for [_StructuralVerificationProducer] below.
class _ChangeTypesProducer extends AiContextProducer {
  const _ChangeTypesProducer({
    required this.scopeArgs,
    required this.includeStaged,
    required this.includeUnstaged,
  });
  final List<String> scopeArgs;
  final bool includeStaged;
  final bool includeUnstaged;

  @override
  String get id => 'change_types';
  @override
  int get order => 10;
  @override
  double? urgency(AiContextRequest req) => null;
  @override
  int fixedRequest(AiContextRequest req) => 0;
  @override
  Future<AiContextSection> produce(
      AiContextRequest req, int budgetChars) async {
    // budgetChars is informational — the underlying collector emits
    // its own naturally-bounded output (one line per touched file).
    final body = await _collectChangeTypes(
      repositoryPath: req.repositoryPath,
      scopeArgs: scopeArgs,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
    );
    return AiContextSection(id: id, body: body);
  }
}

/// Muse phase-2 producer: brainstorm-seeded relevance reshape. Wraps
/// [_runBrainstormSeededRelevance] so Muse's synthesis context budget
/// flows through the same allocator as everything else, instead of a
/// bespoke constant-fraction calculation. Single-producer engines
/// degenerate to "give it the whole pool" naturally — no special-case
/// code path needed.
class _BrainstormSeededRelevanceProducer extends AiContextProducer {
  const _BrainstormSeededRelevanceProducer({
    required this.ideas,
    required this.diffSourceWeights,
    required this.userBoosts,
  });
  final List<_BrainstormIdea> ideas;
  final Map<String, double> diffSourceWeights;

  /// Per-path pull magnitudes the user applied on the loading canvas,
  /// snapshotted by the muse pipeline and passed through so phase-2
  /// can both use them for seeding AND the muse result can cite them
  /// in the rendered output.
  final Map<String, double> userBoosts;

  @override
  String get id => 'brainstorm_seeded_relevance';
  @override
  // Single-producer instance: any non-zero urgency yields full pool.
  // Constant 1.0 is fine here — softmax of {1.0} = {1.0}.
  double? urgency(AiContextRequest req) => 1.0;
  @override
  Future<AiContextSection> produce(
      AiContextRequest req, int budgetChars) async {
    final result = await _runBrainstormSeededRelevance(
      repositoryPath: req.repositoryPath,
      diffText: req.diffText,
      ideas: ideas,
      diffSourceWeights: diffSourceWeights,
      userBoosts: userBoosts,
      budgetChars: budgetChars,
    );
    return AiContextSection(
      id: id,
      body: result.text,
      metadata: result.record,
    );
  }
}

/// Always-on producer: structural verification (import/symbol/removal
/// existence checks). Same outside-the-pool semantics as
/// [_ChangeTypesProducer] — see that class's doc.
class _StructuralVerificationProducer extends AiContextProducer {
  const _StructuralVerificationProducer();
  @override
  String get id => 'structural_verification';
  @override
  int get order => 20;
  @override
  double? urgency(AiContextRequest req) => null;
  @override
  int fixedRequest(AiContextRequest req) => 0;
  @override
  Future<AiContextSection> produce(
      AiContextRequest req, int budgetChars) async {
    // budgetChars is informational; collector emits what it emits.
    final body = await _collectStructuralVerification(
      repositoryPath: req.repositoryPath,
      diffText: req.diffText,
    );
    return AiContextSection(id: id, body: body);
  }
}

/// Run the Logos diffusion pipeline up to (but not including) tier
/// emission. Returns null when the engine isn't available, the probe
/// is empty, or diffusion produced no scores. Cheap to call early —
/// the engine resolver caches per (repo, HEAD). Public so the
/// [AiContextEngine] can hoist diffusion out of producers and feed
/// the same artifact to all of them.
Future<LogosDiffusionResult?> _runLogosDiffusion({
  required String repositoryPath,
  required String diffText,
}) async {
  try {
    final engine = await resolveLogosGit(repositoryPath);
    if (engine == null) return null;
    final probe = await buildDiffProbe(
      repoPath: repositoryPath,
      diffText: diffText,
      engine: engine,
    );
    if (probe.sourceWeights.isEmpty) return null;

    final orbit = await probeLogosBranchOrbit(repositoryPath);
    final resolvedT = (probe.suggestedTemperature ?? 1.0) *
        logosTemperatureMultiplierFromOrbit(orbit);

    // Per-axis attribution diffusion. Costs ~4× a plain weighted
    // diffuse (one Chebyshev pass per source-axis bucket) but yields
    // the data needed to make every Logos surface self-explaining:
    // for each ranked file, which axis contributed how much. Heat-
    // kernel linearity guarantees Σ per-axis φ = combined φ, so the
    // [scores] field stays algebraically consistent with the prior
    // single-pass behaviour. Falls back to plain diffuse only when
    // attribution returns null (empty graph / no in-graph sources).
    //
    // Yield once before the synchronous 4-axis burst so the UI frame
    // in flight can paint before we block the thread for the math.
    await Future<void>.delayed(Duration.zero);
    final diffuseStart = Stopwatch()..start();
    final symbolPaths = _newSymbolPaths(engine);
    final axisLabels = <String, String>{
      for (final entry in probe.sourceWeights.entries)
        entry.key: _classifyAxis(
          entry.key,
          probe,
          symbolPaths: symbolPaths,
        ).name,
    };
    // Recurrent diffusion: each iteration promotes the highest-
    // innovation-residual non-focus paths into the source set, so
    // the 2nd pass reaches 2 hops on the file graph, the 3rd reaches
    // 3, etc. Terminates when residual mass drops below threshold
    // (distribution has become self-consistent).
    // Cheap diffs converge in 1-2; complex ones take more passes.
    final recurrent = engine.gatherEvidenceRecurrent(
      focusWeights: probe.sourceWeights,
      axisLabelByPath: axisLabels,
      t: resolvedT,
      excludePaths: probe.primaryPaths,
      detailBudget: 32,
      onIteration: (report) {
        LogosVisBus.instance.emitInSession(
          (sid) => LogosVisRecurrentStep(
            sid,
            iteration: report.iteration,
            noveltyMass: report.noveltyMass,
            promotedPaths: report.promotedPaths,
            hfWeight: report.hfWeight,
            tpWeight: report.tpWeight,
          ),
        );
      },
    );
    final evidence = recurrent.evidence;
    final attribution = evidence?.supportAttribution;
    final List<RelevanceScore> scores;
    if (evidence != null && evidence.ranked.isNotEmpty) {
      scores = [
        for (final e in evidence.ranked)
          RelevanceScore(
            e.path,
            e.utility > 0 ? e.utility : (e.support * e.integrity * 0.05),
          ),
      ];
    } else if (attribution != null) {
      scores = attribution.combined;
    } else {
      // Engine cold or all sources out-of-graph — keep the plain path.
      scores = diffuseFromProbe(
        engine: engine,
        probe: probe,
        temperatureOverride: resolvedT,
      );
    }
    LogosGitDiagnostics.instance.recordDiffuse(
      repoPath: repositoryPath,
      sourceCount: probe.sourceWeights.length,
      duration: diffuseStart.elapsed,
      temperature: resolvedT,
    );
    if (scores.isEmpty) return null;
    final result = LogosDiffusionResult(
      engine: engine,
      probe: probe,
      scores: scores,
      resolvedT: resolvedT,
      attribution: attribution,
      evidence: evidence,
      recurrentIterations: recurrent.iterations,
      recurrentConverged: recurrent.converged,
      discoveryDepth: recurrent.discoveryDepth,
    );

    // Visualisation events: the diff's source files (what ignited) +
    // the diffusion outcome (phi scores and per-file wells for the
    // radial canvas layout). Only active during a review session;
    // no-op for probe calls from other surfaces.
    //
    // Source weights: the `probe.sourceWeights` map is already
    // normalised by the probe builder; canvas reads it verbatim.
    LogosVisBus.instance.emitInSession(
      (sid) => LogosVisDiffSources(
        sid,
        weights: Map<String, double>.from(probe.sourceWeights),
        churn:
            probe.sourceWeights.values.fold<double>(0, (a, b) => a + b).round(),
      ),
    );
    // Post-diffusion scores + well assignments. The canvas uses these
    // to colour neighbour files by φ (intensity) and well (hue).
    final phiMap = <String, double>{};
    for (final s in scores) {
      phiMap[s.path] = s.phi;
    }
    final wellByPath = <String, String>{};
    for (final s in scores) {
      final w = engine.wellOf(s.path);
      if (w != null) wellByPath[s.path] = w;
    }
    LogosVisBus.instance.emitInSession(
      (sid) => LogosVisDiffusionComplete(
        sid,
        phi: phiMap,
        wellByPath: wellByPath,
      ),
    );
    final transportArcs = engine.topTransportArcs(12);
    if (transportArcs.isNotEmpty) {
      final pullByPath = <String, double>{};
      if (evidence != null) {
        for (final e in evidence.ranked) {
          final tp = evidence.transportPullByPath[e.path];
          if (tp != null && tp > 0) pullByPath[e.path] = tp;
        }
      }
      LogosVisBus.instance.emitInSession(
        (sid) => LogosVisTransportField(
          sid,
          pullByPath: pullByPath,
          arcs: transportArcs,
        ),
      );
    }
    return result;
  } catch (e, st) {
    LogosGitDiagnostics.instance.recordFailure(
      repositoryPath,
      'logos_diffusion: $e',
      Duration.zero,
      st,
    );
    return null;
  }
}

/// Shared Logos-yield helper. Used by every probe-based producer's
/// urgency function so the algebraic partition `D·y + D·(1−y) + coh = 1`
/// holds across producers (each one queries the same numbers from the
/// same probe). Centralised so a future regime/SSE-aware refinement
/// updates all three producers at once.
/// Returns:
///   coh         — coherence ∈ [0, 1]: mean pairwise edge weight under
///                 the engine's Born-mixed metric for the primary path
///                 set. High when the diff's touched files are tightly
///                 clustered on the file graph; low when scattered.
///                 (Not Shannon/Rényi entropy — a pairwise-weight
///                 summary that happens to live in the same range.)
///   dispersion  — 1 − coh: how scattered the primary set is.
///   yieldFraction — (M-axis + Ab-axis matches) / (primary + M + Ab) ∈
///                 [0, 1): fraction of "diff energy" that lives in the
///                 neighbourhood the probe found via pickaxe + path
///                 mirrors, vs. confined to the primary set itself.
({double coh, double dispersion, double yieldFraction}) _logosYieldOf(
    DiffProbe probe) {
  final coh = probe.stats.coherence.clamp(0.0, 1.0);
  final neigh = (probe.stats.mMatches + probe.stats.abMatches).toDouble();
  final primary = probe.stats.primaryCount.toDouble();
  final denom = primary + neigh;
  final yieldFraction = denom > 0 ? neigh / denom : 0.0;
  return (coh: coh, dispersion: 1.0 - coh, yieldFraction: yieldFraction);
}

/// Returns the prompt section *and* the emission record for this call,
/// so the caller can feed citations back to SSE without relying on
/// process-level globals (which would race across overlapping reviews).
/// Accepts a pre-built [logos] result from [_runLogosDiffusion] — the
/// caller hoists that work to drive the budget allocation, and we
/// reuse the same artifact here for emission. Falls back to building
/// internally when [logos] is null (e.g., callers that don't need the
/// derived budget split).
Future<({String text, LogosEmissionRecord? record})>
    _collectRelevanceNeighborhood({
  required String repositoryPath,
  required String diffText,
  required int budgetChars,
  LogosDiffusionResult? logos,
}) async {
  if (budgetChars <= 500) return (text: '', record: null);
  try {
    final result = logos ??
        await _runLogosDiffusion(
          repositoryPath: repositoryPath,
          diffText: diffText,
        );
    if (result == null) return (text: '', record: null);
    final engine = result.engine;
    final probe = result.probe;
    final scores = result.scores;
    final residualByPath =
        result.evidence?.residualByPath ?? const <String, LogosResidualView>{};

    // No candidate trim — let the knapsack see the full ranking. The
    // budget closes the long tail naturally; an arbitrary pre-trim
    // would discard tail-φ items that the planner might have chosen
    // at a cheaper tier.
    final plan = engine.plan(scores, budget: budgetChars);
    if (plan.isEmpty) return (text: '', record: null);

    // Classify the regime + record which axis put each file on the
    // emission list. The SSE store consumes this after the AI responds
    // — citations are matched back and axis utilities updated per-repo.
    final regime = LogosRegime.classify(
      fileCount: probe.stats.primaryCount,
      coherence: probe.stats.coherence,
    );
    // Only NEW (non-graph) paths qualify as symbol-axis — in-graph files
    // that happen to have symbol edges were routed through another axis.
    final symbolPaths = _newSymbolPaths(engine);
    final axisByPath = <String, LogosAxis>{
      for (final item in plan)
        item.path: _classifyAxis(item.path, probe, symbolPaths: symbolPaths),
    };
    final emissionRecord = LogosEmissionRecord(
      regime: regime,
      axisByPath: axisByPath,
    );
    // Symmetric with the citation feedback path: recordCitations is
    // also awaited (via _recordLogosCitationFeedback). Awaiting both
    // sides prevents the asymmetry where emissions get dropped on app
    // close while citations persist — that asymmetry biased
    // (cited / emitted) ratios upward by silently shrinking the
    // denominator. The write goes through the per-repo lock so this
    // adds at most one serialised disk flush; bounded latency.
    try {
      await LogosSseStore(repositoryPath).recordEmissions(emissionRecord);
    } catch (e, st) {
      LogosGitDiagnostics.instance.recordFailure(
        repositoryPath,
        'sse emissions: $e',
        Duration.zero,
        st,
      );
      // Don't let SSE write failure poison the review.
    }

    // Semantic neighborhood header — status-marked so the prompt
    // builder can adapt evidence_rules to whether attribution is
    // available this turn. Replaces the old raw-number soup that
    // invited the AI to interpret `coherence=0.15` on unfamiliar
    // scales. Also communicates explicitly whether the attribution
    // channel has something to say (used below on every neighbor).
    final hasAttribution = result.attribution != null;
    final fileCount = probe.stats.primaryCount;
    final coherenceLabel = coherenceBand(probe.stats.coherence).label;
    final regimeLabel = regimeBand(regime).label;
    final buffer = StringBuffer();
    buffer.writeln(
      'status: populated · neighbors=${plan.length} · diff_files=$fileCount'
      ' · coherence=$coherenceLabel · regime=$regimeLabel'
      ' · attribution=${hasAttribution ? "available" : "unavailable"}',
    );
    if (!hasAttribution) {
      buffer.writeln(
          'note: the attribution channel is quiet this turn. Each neighbor '
          'below is here because the engine felt a pull toward it, but '
          'hasn\'t named which thread tied it to the diff. Honor that '
          'honestly — surface the file\'s presence when useful, speak only '
          'to what its source shows, and let the coupling stay unnamed.');
    }
    var remaining = budgetChars - buffer.length;

    // Normalize φ against the plan's own maximum so the relevance band
    // reflects how a neighbour ranks *within this diff*, not against an
    // absolute cutoff that biases by graph density or chosen t. A φ of
    // 0.45 is "moderate" on a dense graph and "dominant" on a sparse
    // one — the LLM shouldn't have to guess which.
    var planPhiMax = 0.0;
    for (final item in plan) {
      if (item.phi > planPhiMax) planPhiMax = item.phi;
    }

    for (final item in plan) {
      if (remaining <= 120) break;
      // Per-file axis breakdown so the AI can ground its findings in
      // *why* Logos surfaced this neighbour. Format: `via=cc(64%)
      // sp=21% f0=15%` listing axes that contributed ≥10% of the
      // file's φ. Falls through silently when no attribution was
      // computed (engine cold) — the rest of the line is unchanged.
      // Semantic axis trail — "symbol-pickaxe(dominant) ·
      // code-coupling(strong)" instead of "cc(64%) sp=21%". Empty
      // when attribution is cold; the header calls that out
      // explicitly so the AI sees "(no axis support)" rather than
      // silently inferring one.
      final via = _formatAxisBreakdownSemantic(result.attribution, item.path);
      final ev = residualByPath[item.path];
      // Engram well pill — the dominant Alexandria well for this
      // file's identifier content. Present whenever the resolver
      // loaded engram assets and the file encoded successfully.
      // Surfaces the feature-cluster label alongside the relevance
      // band so the LLM sees "this neighbour belongs to the
      // `computing` well" when deciding whether it's relevant.
      final well = result.engine.wellOf(item.path);
      final wellPill = well != null ? '  well=$well' : '';
      final evidencePill = ev == null ? '' : _formatEvidencePill(ev);
      // Relevance BAND replaces the raw φ number — gives the model
      // a closed vocabulary ("strong", "moderate") it has stable
      // priors for, instead of a number it has to invent meaning
      // for on every turn.
      final relevance = _neighborRelevanceBand(item.phi, planPhiMax);
      final viaPill = via.isEmpty
          ? '  via=(no axis support)'
          : '  via=$via';
      // Recurrent-diffusion depth: 0 or missing = in the original
      // probe / 1-hop neighbour; ≥1 = surfaced by iterative re-probing
      // because the first-pass distribution still had unexplained
      // residual mass. The reviewer reads depth as distance from the
      // diff's own touch surface.
      final depth = result.discoveryDepth[item.path];
      final depthPill =
          (depth != null && depth >= 1) ? '  depth=$depth' : '';
      final header =
          '--- ${item.path}  relevance=$relevance  tier=${_tierName(item.tier)}$viaPill$evidencePill$wellPill$depthPill ---';
      if (item.tier == EmissionTier.breadcrumb) {
        final line = '$header\n';
        if (line.length > remaining) continue;
        buffer.write(line);
        remaining -= line.length;
        continue;
      }
      try {
        final file = File(p.join(repositoryPath, item.path));
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        final lineCount = _countLinesPlusOne(content);
        if (item.tier == EmissionTier.full) {
          final fullBlock = '$header\n$content\n';
          if (fullBlock.length <= remaining) {
            buffer.write(fullBlock);
            remaining -= fullBlock.length;
            continue;
          }
          // Over-budget at full size — fall back to intra-file chunk
          // diffusion. Neighborhood files have no diff-touched ranges,
          // so the chunk packer uses byte-mass ρ and surfaces the most
          // central chunks. Geometry, not an arbitrary line cap.
          final pack = await chunks.packRelevantChunksAsync(
            filePath: item.path,
            content: content,
            touchedRanges: const [],
            budgetChars: remaining,
            fileTransportedSupport: ev?.transportedSupport ?? 0.0,
            fileInnovationResidual: ev?.innovationResidual ?? 0.0,
            fileWitnessResidual: ev?.witnessResidual ?? 0.0,
            fileEvidenceTags: ev == null
                ? const <String>[]
                : _evidenceTagParts(ev, includeWitnessNotes: false),
            fileEvidenceWitnesses:
                ev == null ? const <LogosEvidenceWitness>[] : ev.witnesses,
          );
          if (pack.body.isEmpty) continue;
          buffer.write(pack.body);
          remaining -= pack.body.length;
        } else {
          final block = _buildFileOutline(content, item.path, lineCount);
          if (block.length > remaining) continue;
          buffer.write(block);
          remaining -= block.length;
        }
      } catch (_) {
        continue;
      }
    }
    return (text: buffer.toString(), record: emissionRecord);
  } catch (e, st) {
    // No more silent swallow — surface failures through diagnostics
    // so debug panels can show them and tests can assert on them.
    // The empty-string return preserves the fail-safe behaviour for
    // the prompt (worst case: prompt loses one enrichment section).
    LogosGitDiagnostics.instance.recordFailure(
      repositoryPath,
      'relevance_neighborhood: $e',
      Duration.zero,
      st,
    );
    return (text: '', record: null);
  }
}

String _tierName(EmissionTier tier) => switch (tier) {
      EmissionTier.full => 'full',
      EmissionTier.signature => 'sig',
      EmissionTier.breadcrumb => 'bread',
    };

@visibleForTesting
String formatAxisBreakdownForTesting(AxisAttribution? attr, String path) =>
    _formatAxisBreakdown(attr, path);

/// Format a Logos axis-breakdown for the relevance neighborhood
/// emission. Returns e.g. `cc(64%) sp=21% f0=15%` — the dominant axis
/// gets the parens marker, others listed in descending share. Axes
/// contributing below 10% are omitted (signal floor; otherwise tiny
/// numerical leakage muddies the line).
/// Returns '' when there's no attribution to read or no axis cleared
/// the threshold — caller falls back to the un-decorated header.
String _formatAxisBreakdown(AxisAttribution? attr, String path) {
  if (attr == null) return '';
  final shares = attr.shareByAxis[path];
  if (shares == null || shares.isEmpty) return '';
  final dominant = attr.dominantAxis[path];
  // Sort by share desc; stable secondary by axis name for determinism.
  final ordered = shares.entries.toList()
    ..sort((a, b) {
      final byShare = b.value.compareTo(a.value);
      if (byShare != 0) return byShare;
      return a.key.compareTo(b.key);
    });
  final parts = <String>[];
  for (final entry in ordered) {
    if (entry.value < 0.10) continue; // signal floor
    final pct = (entry.value * 100).round();
    parts.add(
        entry.key == dominant ? '${entry.key}($pct%)' : '${entry.key}=$pct%');
  }
  return parts.join(' ');
}

/// Translate the short-form axis codes used by [AxisAttribution] into
/// the human-readable labels the review prompt cites from. Unknown
/// codes fall through to the raw key so future axes still render
/// without a code change.
String _semanticAxisLabel(String code) {
  switch (code) {
    case 'cc':
      return 'code-coupling';
    case 'sp':
      return 'shortest-path';
    case 'm':
      return 'symbol-pickaxe';
    case 'ab':
      return 'path-mirror';
    case 'f0':
      return 'folder-hub';
    case 'en':
      return 'enrichment';
    case 'v':
      return 'vocabulary';
    default:
      return code;
  }
}

/// Semantic variant of [_formatAxisBreakdown]. Emits axes as
/// human-readable labels with strength bands instead of percentages,
/// e.g. `symbol-pickaxe(dominant) · code-coupling(strong) · folder-hub(moderate)`.
/// Keeps the same 10% signal floor; returns '' when attribution is
/// absent so callers can decide to omit the neighbor or mark it
/// `(no axis support)` — silent attribution was one of the biggest
/// hallucination vectors in the prior prompt format.
String _formatAxisBreakdownSemantic(AxisAttribution? attr, String path) {
  if (attr == null) return '';
  final shares = attr.shareByAxis[path];
  if (shares == null || shares.isEmpty) return '';
  final dominant = attr.dominantAxis[path];
  final ordered = shares.entries.toList()
    ..sort((a, b) {
      final byShare = b.value.compareTo(a.value);
      if (byShare != 0) return byShare;
      return a.key.compareTo(b.key);
    });
  final parts = <String>[];
  for (final entry in ordered) {
    if (entry.value < 0.10) continue;
    final label = _semanticAxisLabel(entry.key);
    final strength = entry.key == dominant
        ? 'dominant'
        : attributionStrength(entry.value);
    parts.add('$label($strength)');
  }
  return parts.join(' · ');
}

/// Translate a φ score into a semantic relevance band, normalized
/// against the neighbourhood's own maximum φ. Band breakpoints are
/// even quintiles of the within-plan ratio, so "dominant" always
/// means "near the top of this diff's neighbourhood" regardless of
/// whether the absolute φ scale is compressed (dense graph) or
/// stretched (sparse graph). When [planPhiMax] is 0 (degenerate
/// all-zero case) we fall through to 'trace' to avoid div-by-zero.
String _neighborRelevanceBand(double phi, double planPhiMax) {
  if (planPhiMax <= 0) return 'trace';
  final r = phi / planPhiMax;
  if (r < 0.20) return 'trace';
  if (r < 0.40) return 'weak';
  if (r < 0.60) return 'moderate';
  if (r < 0.80) return 'strong';
  return 'dominant';
}

Future<String> _formatDivergentNeighborhood({
  required LogosGit engine,
  required LogosEvidenceQueryResult evidence,
  required String repositoryPath,
}) async {
  const budgetChars = 6000;
  const outlineCap = 5;

  final ranked = evidence.ranked.toList()
    ..sort((a, b) => b.utility.compareTo(a.utility));
  if (ranked.isEmpty) return '';

  var maxUtility = 0.0;
  for (final e in ranked) {
    if (e.utility > maxUtility) maxUtility = e.utility;
  }

  final buf = StringBuffer();
  buf.writeln(
    'Divergent-mode Logos diffusion (t=4.0, K=8, surprise×2.7). '
    'These files are structurally connected to the diff through the '
    'file-coupling manifold but sit beyond the focused neighbourhood. '
    'Use them to ground code-rooted ideas; let field-rooted ideas '
    'reach past them freely.',
  );
  buf.writeln('files=${ranked.length}');

  var remaining = budgetChars - buf.length;
  var outlineCount = 0;

  for (final entry in ranked) {
    if (remaining <= 100) break;
    final well = engine.wellOf(entry.path);
    final wellPill = well != null ? '  well=$well' : '';
    final relevance = _neighborRelevanceBand(entry.utility, maxUtility);
    final header =
        '--- ${entry.path}  relevance=$relevance$wellPill ---';

    if (outlineCount < outlineCap) {
      try {
        final file = File(p.join(repositoryPath, entry.path));
        if (await file.exists()) {
          final content = await file.readAsString();
          final lineCount = _countLinesPlusOne(content);
          final outline = _buildFileOutline(content, entry.path, lineCount);
          if (outline.length <= remaining) {
            buf.write(outline);
            remaining -= outline.length;
            outlineCount++;
            continue;
          }
        }
      } catch (_) {}
    }
    final line = '$header\n';
    if (line.length > remaining) continue;
    buf.write(line);
    remaining -= line.length;
  }
  return buf.toString().trimRight();
}

/// Which observable put `path` on the emission list.
///   primary  — the diff itself
///   symbol   — new/untracked file, derived φ via identifier overlap
///   m        — pickaxe identifier search pulled it in
///   ab       — path-mirror (test ↔ source) pulled it in
///   graph    — diffusion ranked it from graph edges (CC/SP/V/F0)
/// [symbolPaths] should be the keys of the engine's [symbolEdges] map —
/// paths whose presence in the emission list is due to symbol-overlap
/// coupling rather than git history.
LogosAxis _classifyAxis(
  String path,
  DiffProbe probe, {
  Set<String> symbolPaths = const {},
}) {
  if (probe.primaryPaths.contains(path)) return LogosAxis.primary;
  if (symbolPaths.contains(path)) return LogosAxis.symbol;
  if (probe.sourceWeights.containsKey(path)) {
    return _pathLooksLikeMirrorOf(path, probe.primaryPaths)
        ? LogosAxis.ab
        : LogosAxis.m;
  }
  return LogosAxis.graph;
}

/// Paths that have symbol-overlap edges but are NOT part of the
/// engine's coupling graph — these are the new/untracked files
/// surfaced via identifier overlap alone. Used by [_classifyAxis]
/// to label axis=symbol vs axis=graph. Kept as a single derivation
/// so call sites can't drift from each other.
Set<String> _newSymbolPaths(LogosGit engine) => <String>{
      for (final p in engine.symbolEdges.keys)
        if (!engine.pathToId.containsKey(p)) p,
    };

bool _pathLooksLikeMirrorOf(String candidate, Set<String> primary) {
  // Mirror = candidate is a test-ish path AND its basename-stem matches
  // some primary path's stem. Test-path detection routes through the
  // same classifier the probe uses so axis tags stay consistent across
  // the probe builder and this downstream citation path.
  if (!looksLikeTestPath(candidate)) return false;
  final candBase = p
      .basenameWithoutExtension(candidate)
      .replaceAll(RegExp(r'(_test|_spec|\.test|\.spec)$'), '');
  for (final pri in primary) {
    final priBase = p.basenameWithoutExtension(pri);
    if (candBase == priBase) return true;
  }
  return false;
}

/// Feed the AI's structured output back into the SSE store. Extracts
/// cited paths from `<findings>` XML and records them against the
/// emission record produced for *this* review call. Fire-and-forget;
/// failure is logged but never surfaces to the user.
/// The record is passed in explicitly (not read from a global) so two
/// reviews running concurrently can't cross-contaminate each other's
/// citation tallies.
Future<void> _recordLogosCitationFeedback({
  required String repositoryPath,
  required String aiOutput,
  required LogosEmissionRecord? record,
}) async {
  if (record == null) return;
  try {
    final cited = extractCitedPathsFromReviewOutput(aiOutput);
    await LogosSseStore(repositoryPath).recordCitations(
      record: record,
      citedPaths: cited,
    );
  } catch (e, st) {
    LogosGitDiagnostics.instance.recordFailure(
      repositoryPath,
      'sse citation feedback: $e',
      Duration.zero,
      st,
    );
  }
}

/// Logos-derived shape signal for the commit-message generation path.
/// Review needs file bodies; message generation needs SHAPE HINTS:
///   - What is this commit about? (scope centroid)
///   - How cohesive is it? (regime + coherence)
///   - Anything likely forgotten? (missing mass)
/// The LLM consumes these to pick scope prefixes, voice, coverage, and
/// whether to warn about forgotten files.
/// Stability bucket thresholds for the commit-shape prompt. These
/// correspond to the self-same buckets documented in the stability
/// primitive's own docstring ("firm / soft / knife-edge"), kept in
/// sync as named constants so the language gating and the primitive
/// itself don't drift. Derived: 0.7 and 0.4 partition [0, 1] into
/// thirds biased toward stability (confidence has to be earned).
const double _stabilityFirmThreshold = 0.7;
const double _stabilitySoftThreshold = 0.4;

class LogosCommitShape {
  final LogosRegime regime;
  final double coherence;
  final String? scopeCentroid;
  final List<RelevanceScore> missingMass;
  final int primaryCount;
  final double temperature;

  /// Per-axis fraction of the diffused mass — `primary`, `m`, `ab`,
  /// `graph` (the axis labels of [_classifyAxis]). Sums to ~1. Empty
  /// when attribution wasn't computed (engine fell back to plain
  /// weighted diffusion).
  final Map<String, double> axisShares;

  /// For each surfaced missing-mass file, the dominant axis label that
  /// pulled it in. Lets the prompt say "the test-mirror axis surfaced
  /// foo_test.dart" instead of just naming the file.
  final Map<String, String> dominantAxisByPath;

  /// Stability of the top-K ranking under small source perturbations,
  /// in [0, 1]. High = trust the missing-mass suggestions; low = they
  /// are on a knife-edge — the prompt should soften the language.
  /// Null when not computed (engine cold, single-source diff, etc.).
  final double? stability;

  /// Short branch-trajectory label ('converging', 'diverging', 'steady')
  /// derived from a Whisper Engram AR(2) fit on the preceding commits'
  /// file-set Jaccard series. Null when the branch is too short to
  /// characterise or the fit degenerated. When non-null, the AI should
  /// tune the commit message voice: converging → confident ("this
  /// completes the foo refactor"), diverging → hedged ("fold back into
  /// a tighter scope if possible"), steady → neutral.
  final String? branchTrajectory;
  final double? sourceAlignment;
  final double? fieldAlignment;
  final double? sourceSurprise;
  final double? fieldSurprise;
  final Map<String, double> supportByPath;
  final Map<String, double> ambientByPath;
  final Map<String, double> transportPullByPath;
  final Map<String, double> lowFrequencyByPath;
  final Map<String, double> highFrequencyByPath;
  final Map<String, double> higherOrderLiftByPath;
  final Map<String, double> reducibilityGapByPath;
  final LogosFlowDiagnostics? flowDiagnostics;
  final LogosWitnessSyndrome? witnessSyndrome;
  final List<String> metricSidecarLabels;
  final List<String> transportLaneLabels;
  final List<String> transportFrontierPaths;
  final List<LogosTransportFlowEdge> transportEdges;
  final List<String> inquiryStepLabels;
  final double? motionWarpCoverage;
  final double? motionInnovationMass;
  final double? motionCompensatedChangeRatio;
  final bool motionSceneCut;
  final List<String> motionInnovationFrontier;
  final double? witnessResidualPredictedMass;
  final double? witnessResidualMass;
  final double? witnessResidualCoverage;
  final List<String> witnessResidualFrontier;
  final List<String> witnessResidualKinds;
  final Map<String, List<LogosEvidenceWitness>> witnessesByPath;
  final Map<String, List<String>> witnessLabelsByPath;
  final Map<String, List<String>> sidecarLabelsByPath;

  const LogosCommitShape({
    required this.regime,
    required this.coherence,
    required this.scopeCentroid,
    required this.missingMass,
    required this.primaryCount,
    required this.temperature,
    this.axisShares = const {},
    this.dominantAxisByPath = const {},
    this.stability,
    this.branchTrajectory,
    this.sourceAlignment,
    this.fieldAlignment,
    this.sourceSurprise,
    this.fieldSurprise,
    this.supportByPath = const {},
    this.ambientByPath = const {},
    this.transportPullByPath = const {},
    this.lowFrequencyByPath = const {},
    this.highFrequencyByPath = const {},
    this.higherOrderLiftByPath = const {},
    this.reducibilityGapByPath = const {},
    this.flowDiagnostics,
    this.witnessSyndrome,
    this.metricSidecarLabels = const [],
    this.transportLaneLabels = const [],
    this.transportFrontierPaths = const [],
    this.transportEdges = const [],
    this.inquiryStepLabels = const [],
    this.motionWarpCoverage,
    this.motionInnovationMass,
    this.motionCompensatedChangeRatio,
    this.motionSceneCut = false,
    this.motionInnovationFrontier = const [],
    this.witnessResidualPredictedMass,
    this.witnessResidualMass,
    this.witnessResidualCoverage,
    this.witnessResidualFrontier = const [],
    this.witnessResidualKinds = const [],
    this.witnessesByPath = const {},
    this.witnessLabelsByPath = const {},
    this.sidecarLabelsByPath = const {},
  });
}

/// Collect a [LogosCommitShape] for the commit-message generation path.
/// Best-effort — returns null when the engine isn't ready or the diff
/// is trivially empty.
/// Shared branch-orbit probe. One `git log -n N --name-only` run,
/// parsed into per-commit file sets, fed into the Engram AR(2) fit.
/// Returns null on any failure (non-git dir, empty history, parse
/// error) so callers degrade silently. Cheap enough to run per-AI-
/// call — ~30 commits' metadata, no blob reads.
/// Map a branch orbit to a diffusion-temperature multiplier. A
/// converging branch — scope narrowing toward the tip — benefits
/// from a *cooler* diffusion that trusts the core touched files and
/// doesn't reach far afield. A diverging branch, scope sprawling,
/// benefits from the opposite: a hotter diffusion that casts a
/// wider net to catch the sprawl's real boundaries. Steady /
/// null / insufficient orbits get neutral (×1.0).
/// Values derived from the orbit's own semantics, not tuned:
///   converging → 1 − trendSlope magnitude → cooler (min 0.75)
///   diverging  → 1 + trendSlope magnitude → hotter (max 1.25)
Future<LogosCommitShape?> _collectLogosCommitShape({
  required String repositoryPath,
  required String diffText,
}) async {
  try {
    final engine = await resolveLogosGit(repositoryPath);
    if (engine == null) return null;
    final probe = await buildDiffProbe(
      repoPath: repositoryPath,
      diffText: diffText,
      engine: engine,
    );
    if (probe.sourceWeights.isEmpty) return null;

    final regime = LogosRegime.classify(
      fileCount: probe.stats.primaryCount,
      coherence: probe.stats.coherence,
    );
    final t = probe.suggestedTemperature ?? 1.0;

    // Scope centroid: the touched file that pulls the most mass from
    // the OTHER touched files — proxies the "semantic subject" of the
    // commit. Single-file diffs trivially centroid on themselves.
    String? scopeCentroid;
    if (probe.primaryPaths.length == 1) {
      scopeCentroid = probe.primaryPaths.first;
    } else {
      var bestPath = '';
      var bestSum = -1.0;
      for (final source in probe.primaryPaths) {
        final singleScores = engine.diffuse({source}, t: t);
        final sumToOthers = singleScores
            .where((s) => probe.primaryPaths.contains(s.path))
            .fold<double>(0, (acc, s) => acc + s.phi);
        if (sumToOthers > bestSum) {
          bestSum = sumToOthers;
          bestPath = source;
        }
      }
      scopeCentroid = bestPath.isEmpty ? null : bestPath;
    }

    // Missing mass: files NOT in the diff but strongly pulled by it.
    // Use the per-axis attribution diffusion so we can label *which*
    // axis surfaced each missing file (graph vs M-pickaxe vs Ab-mirror)
    // — much more actionable in the prompt than just a φ score.
    final symbolPaths = _newSymbolPaths(engine);
    final axisLabels = <String, String>{
      for (final entry in probe.sourceWeights.entries)
        entry.key: _classifyAxis(
          entry.key,
          probe,
          symbolPaths: symbolPaths,
        ).name,
    };
    final recurrentMissing = engine.gatherEvidenceRecurrent(
      focusWeights: probe.sourceWeights,
      axisLabelByPath: axisLabels,
      t: t,
      excludePaths: probe.primaryPaths,
      topK: 5,
      detailBudget: 16,
    );
    final evidence = recurrentMissing.evidence;
    final attr = evidence?.supportAttribution;

    List<RelevanceScore> missing;
    Map<String, double> axisShares = const {};
    Map<String, String> dominantByPath = const {};
    Map<String, double> supportByPath = const {};
    Map<String, double> ambientByPath = const {};
    Map<String, double> transportPullByPath = const {};
    Map<String, double> lowFrequencyByPath = const {};
    Map<String, double> highFrequencyByPath = const {};
    Map<String, double> higherOrderLiftByPath = const {};
    Map<String, double> reducibilityGapByPath = const {};
    LogosFlowDiagnostics? flowDiagnostics;
    LogosWitnessSyndrome? witnessSyndrome;
    List<String> metricSidecarLabels = const [];
    List<String> transportLaneLabels = const [];
    List<String> transportFrontierPaths = const [];
    List<LogosTransportFlowEdge> transportEdges = const [];
    List<String> inquiryStepLabels = const [];
    double? motionWarpCoverage;
    double? motionInnovationMass;
    double? motionCompensatedChangeRatio;
    var motionSceneCut = false;
    List<String> motionInnovationFrontier = const [];
    double? witnessResidualPredictedMass;
    double? witnessResidualMass;
    double? witnessResidualCoverage;
    List<String> witnessResidualFrontier = const [];
    List<String> witnessResidualKinds = const [];
    Map<String, List<LogosEvidenceWitness>> witnessesByPath = const {};
    Map<String, List<String>> witnessLabelsByPath = const {};
    Map<String, List<String>> sidecarLabelsByPath = const {};
    if (evidence != null && evidence.ranked.isNotEmpty) {
      missing = [
        for (final e in evidence.ranked.take(5))
          RelevanceScore(
            e.path,
            e.utility > 0 ? e.utility : (e.support * e.integrity * 0.05),
          ),
      ];
      axisShares = attr?.axisMassFractions() ?? const {};
      dominantByPath = {
        for (final e in evidence.ranked.take(5))
          if (e.dominantAxis != null) e.path: e.dominantAxis!,
      };
      supportByPath = {
        for (final e in evidence.ranked.take(5)) e.path: e.support,
      };
      ambientByPath = {
        for (final e in evidence.ranked.take(5)) e.path: e.ambient,
      };
      transportPullByPath = {
        for (final e in evidence.ranked.take(5))
          e.path: evidence.transportPullByPath[e.path] ?? 0.0,
      };
      lowFrequencyByPath = {
        for (final e in evidence.ranked.take(5)) e.path: e.lowFrequencySupport,
      };
      highFrequencyByPath = {
        for (final e in evidence.ranked.take(5))
          e.path: e.highFrequencySurprise,
      };
      higherOrderLiftByPath = {
        for (final e in evidence.ranked.take(5))
          if (e.higherOrderLift > 0) e.path: e.higherOrderLift,
      };
      reducibilityGapByPath = {
        for (final e in evidence.ranked.take(5))
          if (e.reducibilityGap > 0) e.path: e.reducibilityGap,
      };
      flowDiagnostics = evidence.flowDiagnostics;
      witnessSyndrome = evidence.witnessSyndrome;
      metricSidecarLabels = [
        for (final sidecar in evidence.metricSidecars)
          formatLogosMetricSidecar(sidecar, includeNote: false),
      ];
      transportEdges = evidence.transport.frontierEdges.take(4).toList(
            growable: false,
          );
      transportLaneLabels = (() {
        final fromEdges = evidence.transport.dominantEdgeLanes(limit: 4);
        if (fromEdges.isNotEmpty) return fromEdges;
        return evidence.transport.dominantLanes(limit: 4);
      })();
      transportFrontierPaths = (() {
        final fromEdges = evidence.transport.frontierPathsFromEdges(limit: 4);
        if (fromEdges.isNotEmpty) return fromEdges;
        return evidence.transport.frontierPaths;
      })();
      inquiryStepLabels = [
        for (final step in evidence.inquiryPlan.steps.take(4))
          formatLogosInquiryStep(step),
      ];
      motionWarpCoverage = evidence.semanticMotion.warpCoverage;
      motionInnovationMass = evidence.semanticMotion.innovationMass;
      motionCompensatedChangeRatio =
          evidence.semanticMotion.compensatedChangeRatio;
      motionSceneCut = evidence.semanticMotion.sceneCut;
      motionInnovationFrontier = evidence.semanticMotion.innovationFrontier;
      witnessResidualPredictedMass = evidence.witnessResidual.predictedMass;
      witnessResidualMass = evidence.witnessResidual.residualMass;
      witnessResidualCoverage = evidence.witnessResidual.coverage;
      witnessResidualFrontier = evidence.witnessResidual.frontierPaths;
      witnessResidualKinds = evidence.witnessResidual.dominantKinds;
      witnessesByPath = {
        for (final e in evidence.ranked.take(5))
          if (e.witnesses.isNotEmpty) e.path: e.witnesses.take(3).toList(),
      };
      witnessLabelsByPath = {
        for (final entry in witnessesByPath.entries)
          entry.key: [
            for (final w in entry.value)
              formatLogosEvidenceWitness(
                w,
                includeNote: true,
                includeSource: true,
              ),
          ],
      };
      sidecarLabelsByPath = {
        for (final e in evidence.ranked.take(5))
          if (e.sidecars.isNotEmpty)
            e.path: [
              for (final sidecar in e.sidecars.take(2))
                formatLogosMetricSidecar(sidecar, includeNote: false),
            ],
      };
    } else if (attr != null) {
      missing = attr.combined.take(5).toList();
      axisShares = attr.axisMassFractions();
      dominantByPath = {
        for (final s in missing)
          if (attr.dominantAxis[s.path] != null)
            s.path: attr.dominantAxis[s.path]!,
      };
      supportByPath = {
        for (final s in missing) s.path: s.phi,
      };
      witnessLabelsByPath = {
        for (final s in missing)
          if (attr.dominantAxis[s.path] != null)
            s.path: [attr.dominantAxis[s.path]!],
      };
    } else {
      // Fallback: plain weighted diffusion (engine returns empty if no
      // sources land in graph). Same behaviour as before this upgrade.
      final scores = diffuseFromProbe(
        engine: engine,
        probe: probe,
        temperatureOverride: t,
      );
      missing = scores.take(5).toList();
    }

    // Branch trajectory via Engram orbit fit on the last N commits.
    // Shared probe — see [probeLogosBranchOrbit]. Result also gets reused
    // by `_collectRelevanceNeighborhood` to tune diffusion temperature.
    final orbit = await probeLogosBranchOrbit(repositoryPath);
    final branchTrajectory = orbit?.characterLabel;

    // Stability: how firm is the top-K ranking under small source
    // perturbations? Null for degenerate inputs (single source or
    // empty missing mass) — the score isn't meaningful there.
    double? stability;
    if (missing.length >= 2 && probe.sourceWeights.length >= 2) {
      try {
        stability = engine.diffuseStability(
          probe.sourceWeights,
          t: t,
          topK: missing.length,
        );
      } catch (_) {
        stability = null;
      }
    }

    return LogosCommitShape(
      regime: regime,
      coherence: probe.stats.coherence,
      scopeCentroid: scopeCentroid,
      missingMass: missing,
      primaryCount: probe.stats.primaryCount,
      temperature: t,
      axisShares: axisShares,
      dominantAxisByPath: dominantByPath,
      stability: stability,
      branchTrajectory: branchTrajectory,
      sourceAlignment: evidence?.sourceAlignment,
      fieldAlignment: evidence?.fieldAlignment,
      sourceSurprise: evidence?.sourceSurprise,
      fieldSurprise: evidence?.fieldSurprise,
      supportByPath: supportByPath,
      ambientByPath: ambientByPath,
      transportPullByPath: transportPullByPath,
      lowFrequencyByPath: lowFrequencyByPath,
      highFrequencyByPath: highFrequencyByPath,
      higherOrderLiftByPath: higherOrderLiftByPath,
      reducibilityGapByPath: reducibilityGapByPath,
      flowDiagnostics: flowDiagnostics,
      witnessSyndrome: witnessSyndrome,
      metricSidecarLabels: metricSidecarLabels,
      transportLaneLabels: transportLaneLabels,
      transportFrontierPaths: transportFrontierPaths,
      transportEdges: transportEdges,
      inquiryStepLabels: inquiryStepLabels,
      motionWarpCoverage: motionWarpCoverage,
      motionInnovationMass: motionInnovationMass,
      motionCompensatedChangeRatio: motionCompensatedChangeRatio,
      motionSceneCut: motionSceneCut,
      motionInnovationFrontier: motionInnovationFrontier,
      witnessResidualPredictedMass: witnessResidualPredictedMass,
      witnessResidualMass: witnessResidualMass,
      witnessResidualCoverage: witnessResidualCoverage,
      witnessResidualFrontier: witnessResidualFrontier,
      witnessResidualKinds: witnessResidualKinds,
      witnessesByPath: witnessesByPath,
      witnessLabelsByPath: witnessLabelsByPath,
      sidecarLabelsByPath: sidecarLabelsByPath,
    );
  } catch (e, st) {
    LogosGitDiagnostics.instance.recordFailure(
      repositoryPath,
      'commit_shape: $e',
      Duration.zero,
      st,
    );
    return null;
  }
}

/// Format a [LogosCommitShape] as a prompt XML block. Null / empty
/// shapes yield empty strings so callers can concat safely.
String _formatCommitShapeBlock(LogosCommitShape? shape) {
  if (shape == null) return '';
  final buf = StringBuffer('<logos_shape>\n');
  buf.writeln('regime: ${shape.regime.name}');
  buf.writeln('coherence: ${shape.coherence.toStringAsFixed(2)}');
  buf.writeln('primary files: ${shape.primaryCount}');
  buf.writeln('diffusion t: ${shape.temperature.toStringAsFixed(2)}');
  if (shape.sourceAlignment != null) {
    buf.writeln(
        'source alignment: ${shape.sourceAlignment!.toStringAsFixed(2)}');
  }
  if (shape.fieldAlignment != null) {
    buf.writeln('field alignment: ${shape.fieldAlignment!.toStringAsFixed(2)}');
  }
  if (shape.sourceSurprise != null) {
    buf.writeln('source surprise: ${shape.sourceSurprise!.toStringAsFixed(2)}');
  }
  if (shape.fieldSurprise != null) {
    buf.writeln('field surprise: ${shape.fieldSurprise!.toStringAsFixed(2)}');
  }
  if (shape.flowDiagnostics != null) {
    buf.writeln(
      'flow gradient/curl/harmonic: '
      '${shape.flowDiagnostics!.gradientMass.toStringAsFixed(2)} / '
      '${shape.flowDiagnostics!.curlMass.toStringAsFixed(2)} / '
      '${shape.flowDiagnostics!.harmonicMass.toStringAsFixed(2)}',
    );
    buf.writeln(
      'structural stress: '
      '${shape.flowDiagnostics!.structuralStress.toStringAsFixed(2)}',
    );
    buf.writeln(
      'flow confidence: '
      '${shape.flowDiagnostics!.confidence.toStringAsFixed(2)}',
    );
  }
  if (shape.witnessSyndrome != null) {
    final syndrome = shape.witnessSyndrome!;
    buf.writeln(
      'witness syndrome: '
      'cov=${syndrome.coverage.toStringAsFixed(2)}  '
      'corr=${syndrome.corroboration.toStringAsFixed(2)}  '
      'dis=${syndrome.disagreement.toStringAsFixed(2)}',
    );
    if (syndrome.dominantKinds.isNotEmpty) {
      buf.writeln(
          'witness dominant kinds: ${syndrome.dominantKinds.join(', ')}');
    }
    if (syndrome.missingKinds.isNotEmpty) {
      buf.writeln('witness missing kinds: ${syndrome.missingKinds.join(', ')}');
    }
  }
  if (shape.metricSidecarLabels.isNotEmpty) {
    buf.writeln('metric sidecars: ${shape.metricSidecarLabels.join(', ')}');
  }
  if (shape.transportLaneLabels.isNotEmpty) {
    buf.writeln('transport lanes: ${shape.transportLaneLabels.join(', ')}');
  }
  if (shape.transportFrontierPaths.isNotEmpty) {
    buf.writeln(
        'transport frontier: ${shape.transportFrontierPaths.join(', ')}');
  }
  if (shape.transportEdges.isNotEmpty) {
    buf.writeln(
      'transport edges: ${shape.transportEdges.take(3).map((e) => formatLogosTransportFlowEdge(e)).join(', ')}',
    );
  }
  if (shape.motionWarpCoverage != null &&
      shape.motionInnovationMass != null &&
      shape.motionCompensatedChangeRatio != null) {
    buf.writeln(
      'motion warp/innovation/ratio: '
      '${shape.motionWarpCoverage!.toStringAsFixed(2)} / '
      '${shape.motionInnovationMass!.toStringAsFixed(2)} / '
      '${shape.motionCompensatedChangeRatio!.toStringAsFixed(2)}',
    );
    buf.writeln('motion scene cut: ${shape.motionSceneCut ? 'yes' : 'no'}');
    if (shape.motionInnovationFrontier.isNotEmpty) {
      buf.writeln(
        'motion innovation frontier: ${shape.motionInnovationFrontier.join(', ')}',
      );
    }
  }
  if (shape.witnessResidualPredictedMass != null &&
      shape.witnessResidualMass != null &&
      shape.witnessResidualCoverage != null) {
    buf.writeln(
      'witness predicted/residual/coverage: '
      '${shape.witnessResidualPredictedMass!.toStringAsFixed(2)} / '
      '${shape.witnessResidualMass!.toStringAsFixed(2)} / '
      '${shape.witnessResidualCoverage!.toStringAsFixed(2)}',
    );
    if (shape.witnessResidualFrontier.isNotEmpty) {
      buf.writeln(
        'witness residual frontier: ${shape.witnessResidualFrontier.join(', ')}',
      );
    }
    if (shape.witnessResidualKinds.isNotEmpty) {
      buf.writeln(
        'witness residual kinds: ${shape.witnessResidualKinds.join(', ')}',
      );
    }
  }
  if (shape.inquiryStepLabels.isNotEmpty) {
    buf.writeln('inquiry path: ${shape.inquiryStepLabels.join(' | ')}');
  }
  if (shape.scopeCentroid != null) {
    buf.writeln(
      'scope centroid (likely semantic subject): ${shape.scopeCentroid}',
    );
  }
  // Regime-specific writing hints the LLM can leverage — matches the
  // codec philosophy: the observable (regime) tunes the output shape.
  switch (shape.regime) {
    case LogosRegime.focused:
      buf.writeln('hint: focused commit — narrow scope prefix OK '
          '(feat(module): …). Can describe fully.');
      break;
    case LogosRegime.scoped:
      buf.writeln(
          'hint: scoped commit — single scope prefix, balanced coverage.');
      break;
    case LogosRegime.sweep:
      buf.writeln('hint: broad sweep — prefer bulletless or bullet-list '
          'body. Keep title high-level; no scope prefix.');
      break;
    case LogosRegime.uncategorised:
      break;
  }
  if (shape.branchTrajectory != null) {
    // Engram AR(2) orbit fit on the preceding 30 commits' file-set
    // similarity series. Three possible labels: `converging` (scope
    // narrowing toward this tip — confident voice), `diverging` (scope
    // sprawling — hedge the message, suggest a split), `steady`
    // (stable pattern — neutral).
    buf.writeln('branch trajectory: ${shape.branchTrajectory}');
  }
  if (shape.stability != null) {
    // Confidence handle — derived from re-running the diffusion with
    // perturbed source weights and measuring top-K ranking agreement.
    // >= 0.7 = firm; 0.4–0.7 = soft; < 0.4 = knife-edge (do not surface
    // missing-mass suggestions in the commit body without hedging).
    buf.writeln('ranking stability: ${shape.stability!.toStringAsFixed(2)}');
  }
  if (shape.axisShares.isNotEmpty) {
    // Per-axis composition of the diffused field. Tells the model
    // *what kind of evidence* is driving the relevance — heavy `m`
    // share = pickaxe-grounded (symbol-level), heavy `ab` = test-mirror
    // hits, heavy `graph` = co-change history without explicit symbol
    // grounding. Use this to calibrate confidence in any cross-file
    // claims you make.
    buf.writeln('axis composition (fraction of diffused mass per axis):');
    final entries = shape.axisShares.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in entries) {
      buf.writeln(
          '  - ${entry.key}: ${(entry.value * 100).toStringAsFixed(0)}%');
    }
  }
  if (shape.missingMass.isNotEmpty) {
    // Stability buckets the intro language:
    //   stable (≥ 0.7)   → confident "these are tightly coupled"
    //   soft   (0.4–0.7) → the original "may be forgotten" hedge
    //   volatile (< 0.4) → explicitly flag ranking as speculative so
    //                      the AI doesn't confidently surface knife-
    //                      edge suggestions as body notes.
    // Null stability (no signal) falls back to the soft middle.
    final s = shape.stability;
    final String preface;
    if (s == null) {
      preface = 'missing mass (files NOT in the diff but strongly coupled '
          'to it — may be forgotten; surface to the user inside a gentle '
          '"you might also be changing:" body note ONLY IF the relevance '
          'is genuinely notable):';
    } else if (s >= _stabilityFirmThreshold) {
      preface = 'tightly-coupled neighbourhood (stable ranking — these files '
          'move with the diff reliably; safe to surface as a "you might also '
          'be changing:" body note when the relevance is notable):';
    } else if (s >= _stabilitySoftThreshold) {
      preface = 'missing mass (files coupled to the diff but ranking is soft; '
          'surface only if the relevance is genuinely notable, in a gentle '
          '"you might also be changing:" body note):';
    } else {
      preface = 'candidate neighbours (ranking is volatile — perturbing the '
          'source weights reshuffles these substantially, so treat as '
          'speculative and DO NOT surface in the commit body unless the '
          'relevance is obvious from the diff itself):';
    }
    buf.writeln(preface);
    for (final m in shape.missingMass) {
      final axis = shape.dominantAxisByPath[m.path];
      final support = shape.supportByPath[m.path];
      final ambient = shape.ambientByPath[m.path];
      final transportPull = shape.transportPullByPath[m.path];
      final low = shape.lowFrequencyByPath[m.path];
      final high = shape.highFrequencyByPath[m.path];
      final higherOrder = shape.higherOrderLiftByPath[m.path];
      final reducibility = shape.reducibilityGapByPath[m.path];
      final witnesses = shape.witnessLabelsByPath[m.path] ?? const <String>[];
      final sidecars = shape.sidecarLabelsByPath[m.path] ?? const <String>[];
      final metricTags = <String>[
        'phi=${m.phi.toStringAsFixed(3)}',
        if (axis != null) 'via=$axis',
        if (support != null) 's=${support.toStringAsFixed(3)}',
        if (ambient != null && ambient > 0.001)
          'a=${ambient.toStringAsFixed(3)}',
        if (transportPull != null && transportPull > 0.02)
          'tp=${transportPull.toStringAsFixed(3)}',
        if (low != null && low > 0.01) 'lf=${low.toStringAsFixed(3)}',
        if (high != null && high > 0.01) 'hf=${high.toStringAsFixed(3)}',
        if (higherOrder != null && higherOrder > 0.02)
          'ho=${higherOrder.toStringAsFixed(3)}',
        if (reducibility != null && reducibility > 0.02)
          'rg=${reducibility.toStringAsFixed(3)}',
        if (witnesses.isNotEmpty) 'wit=${witnesses.join('|')}',
        if (sidecars.isNotEmpty) 'sc=${sidecars.join('|')}',
      ];
      buf.writeln('  - ${m.path} (${metricTags.join('  ')})');
    }
  }
  buf.writeln('</logos_shape>');
  return buf.toString();
}

String _formatEvidencePill(LogosResidualView ev) {
  return '  ${_evidenceTagParts(ev).join(' ')}';
}

List<String> _evidenceTagParts(
  LogosResidualView ev, {
  bool includeWitnessNotes = true,
}) {
  final parts = <String>[
    'u=${ev.utility.toStringAsFixed(3)}',
    's=${ev.support.toStringAsFixed(3)}',
  ];
  if (ev.ambient > 0.001) {
    parts.add('a=${ev.ambient.toStringAsFixed(3)}');
  }
  if (ev.transportPull > 0.02) {
    parts.add('tp=${ev.transportPull.toStringAsFixed(3)}');
  }
  if (ev.transportedSupport > 0.02) {
    parts.add('ts=${ev.transportedSupport.toStringAsFixed(3)}');
  }
  if (ev.innovationResidual > 0.02) {
    parts.add('ir=${ev.innovationResidual.toStringAsFixed(3)}');
  }
  if (ev.witnessResidual > 0.02) {
    parts.add('wr=${ev.witnessResidual.toStringAsFixed(3)}');
  }
  if (ev.lowFrequencySupport > 0.01) {
    parts.add('lf=${ev.lowFrequencySupport.toStringAsFixed(3)}');
  }
  if (ev.highFrequencySurprise > 0.01) {
    parts.add('hf=${ev.highFrequencySurprise.toStringAsFixed(3)}');
  }
  parts.add('i=${ev.integrity.toStringAsFixed(2)}');
  if (ev.higherOrderLift > 0.02) {
    parts.add('ho=${ev.higherOrderLift.toStringAsFixed(3)}');
  }
  if (ev.reducibilityGap > 0.02) {
    parts.add('rg=${ev.reducibilityGap.toStringAsFixed(3)}');
  }
  final witnessLabels = <String>[
    for (final witness in ev.witnesses.take(3))
      formatLogosEvidenceWitness(
        witness,
        includeNote: includeWitnessNotes,
        includeSource: false,
      ),
  ];
  if (witnessLabels.isNotEmpty) {
    parts.add('wit=${witnessLabels.join('|')}');
  }
  final sidecarLabels = <String>[
    for (final sidecar in ev.sidecars.take(2))
      formatLogosMetricSidecar(sidecar, includeNote: false),
  ];
  if (sidecarLabels.isNotEmpty) {
    parts.add('sc=${sidecarLabels.join('|')}');
  }
  return parts;
}

/// Build the semantic logos-topology block for the prompt.
///
/// Every block emitted here is STATUS-marked so the prompt builder
/// can adapt its evidence_rules to what's actually present. The raw
/// engine values (coherence, motion.warp, stress, witness fields)
/// are translated through [logos_semantic_bands] so the model sees
/// words it can cite ("scattered", "turbulent", "sparse coverage")
/// rather than numbers it can only fabricate interpretations for.
///
/// When the engine is cold / unavailable, the block STILL appears —
/// but with `status: unavailable` and an explicit instruction not
/// to cite spectral evidence. Silent omission was the single biggest
/// source of hallucination: the old prompt told the model "cite
/// <logos_topology>" regardless of whether it was populated, and
/// the model obliged by inventing citations.
String _collectLogosTopology(
  LogosDiffusionResult? logos, {
  required int budgetChars,
}) {
  if (budgetChars <= 80) return '';
  if (logos == null) {
    return 'status: quiet\n'
        'note: the engine chose not to speak for this change. '
        'Let this block rest — your craft here is to review from what IS '
        'present (diff, file context, structural verification). '
        'The spectral channel will have its say on another turn.';
  }
  final evidence = logos.evidence;
  if (evidence == null) {
    return 'status: warming\n'
        'note: the engine is warming — index still settling, '
        'or this repo\'s first pass. Receive the diff and file-context '
        'layers as your full evidence this turn; the spectral bands '
        'will arrive once the engine has something true to say.';
  }
  final buf = StringBuffer();

  final regime = LogosRegime.classify(
    fileCount: logos.probe.stats.primaryCount,
    coherence: logos.probe.stats.coherence,
  );
  final flow = evidence.flowDiagnostics;
  final syndrome = evidence.witnessSyndrome;
  final motion = evidence.semanticMotion;
  final residual = evidence.witnessResidual;

  final confidence = sectionConfidence(
    hasFlow: true,
    hasWitness: syndrome.coverage > 0.01,
    hasAttribution: true,
    flowConfidence: flow.confidence,
  );
  buf.writeln('status: populated');
  buf.writeln('confidence: ${confidence.render()}');

  final shape = overallShape(
    coherence: evidence.coherence,
    motionWarp: motion.warpCoverage,
    structuralStress: flow.structuralStress,
  );
  buf.writeln('shape: ${shape.render()}');
  buf.writeln('regime: ${regimeBand(regime).render()}');

  // Repo-geometry signals — precomputed, cached, free to surface.
  // `geometry` is the nearest archetype from the universality vector
  // (crystalline / poisson / goe / tree / bulk / modular) plus its
  // decisiveness. `structural` gives the connected-component and
  // cycle counts on the coupling filtration, so the reviewer can
  // tell whether the touched files sit in an integrated core or in
  // isolated subsystems. `keystone_edges` surfaces the top-3
  // connectivity bottlenecks — pairs whose coupling, if weakened,
  // would most fragment the repo. Touching a keystone is a qualit-
  // atively different claim than touching a high-φ file.
  _appendTopologyDigest(buf, logos);

  // Axes — each line is "<name>: <label> · <gloss>" with no raw
  // numbers. The model is explicitly instructed to cite the LABELS,
  // not the numbers, because labels come from a closed vocabulary
  // and numbers invite fabrication.
  buf.writeln('coherence: ${coherenceBand(evidence.coherence).render()}');
  buf.writeln('stability: ${stabilityBand(evidence.stability).render()}');
  buf.writeln('motion: ${motionWarpBand(motion.warpCoverage).render()}');
  buf.writeln(
      'innovation: ${innovationBand(motion.innovationMass).render()}');
  buf.writeln(
      'structural_stress: ${flowStressBand(flow.structuralStress).render()}');
  buf.writeln(
      'flow_confidence: ${flowConfidenceBand(flow.confidence).render()}');

  // Witness channel — only surface when it has something to say.
  if (syndrome.coverage > 0.01) {
    buf.writeln(
        'witness_coverage: ${witnessCoverageBand(syndrome.coverage).render()}');
    buf.writeln(
        'witness_corroboration: ${witnessCorroborationBand(syndrome.corroboration).render()}');
    buf.writeln(
        'witness_disagreement: ${witnessDisagreementBand(syndrome.disagreement).render()}');
    if (syndrome.dominantKinds.isNotEmpty) {
      buf.writeln(
          'witness_dominant_kinds: ${syndrome.dominantKinds.take(3).join(", ")}');
    }
    if (syndrome.missingKinds.isNotEmpty) {
      buf.writeln(
          'witness_missing_kinds: ${syndrome.missingKinds.take(3).join(", ")}');
    }
  } else {
    buf.writeln('witness_coverage: absent · no witnesses engaged this change');
  }

  // Prediction/residual — only useful when the channel ran.
  if (residual.predictedMass > 0.02 || residual.residualMass > 0.02) {
    buf.writeln('witness_residual: ${witnessResidualBand(
      predicted: residual.predictedMass,
      residual: residual.residualMass,
      coverage: residual.coverage,
    ).render()}');
  }

  // Alignment — how the query itself sits in the manifold.
  if (evidence.sourceAlignment != null) {
    buf.writeln('source_alignment: ${alignmentBand(evidence.sourceAlignment).render()}');
  }
  if (evidence.fieldAlignment != null) {
    buf.writeln('field_alignment: ${alignmentBand(evidence.fieldAlignment).render()}');
  }

  // Frontier paths — files the engine considers most worth checking.
  // These are grounded concrete signals, kept as plain paths.
  final motionFrontier = motion.innovationFrontier.take(4).toList();
  if (motionFrontier.isNotEmpty) {
    buf.writeln('innovation_frontier: ${motionFrontier.join(", ")}');
  }
  final witnessFrontier = residual.frontierPaths.take(4).toList();
  if (witnessFrontier.isNotEmpty) {
    buf.writeln('witness_frontier: ${witnessFrontier.join(", ")}');
  }

  // Trim to budget. Each line is self-contained so clipping at a
  // line boundary loses a whole axis but never a half-sentence.
  final all = buf.toString();
  if (all.length <= budgetChars) return all.trimRight();
  final lines = all.split('\n');
  final trimmed = StringBuffer();
  for (final line in lines) {
    final rendered = '$line\n';
    if (trimmed.length + rendered.length > budgetChars) break;
    trimmed.write(rendered);
  }
  return trimmed.toString().trimRight();
}

/// Emit geometry / structural / keystone-edge / exploration lines
/// into [buf] when the engine has enough nodes for a spectral basis.
/// Each line is optional and self-contained so the outer trim-by-line
/// can drop whichever one doesn't fit under budget without corrupting
/// the others.
void _appendTopologyDigest(StringBuffer buf, LogosDiffusionResult logos) {
  // Recurrent-diffusion metadata first — it tells the reviewer how
  // deep the engine reached before the distribution settled. iters=1
  // means the diff was self-contained on the first shot; iters=4
  // means even after four re-lightings there's still unexplained
  // residual mass (so the relevance neighbourhood may be incomplete).
  if (logos.recurrentIterations > 1 || !logos.recurrentConverged) {
    buf.writeln('exploration: iters=${logos.recurrentIterations}'
        ' converged=${logos.recurrentConverged}');
  }
  final engine = logos.engine;
  final sg = engine.spectrogeometry();
  if (sg == null) return;
  buf.writeln('geometry: ${sg.label}');

  final persistence = sg.persistence;
  if (persistence != null) {
    buf.writeln('structural: components=${persistence.finalComponents}'
        ' cycles=${persistence.finalCycles}'
        ' persistence=${persistence.totalPersistence.toStringAsFixed(2)}');
  }

  final basis = engine.spectralBasis();
  if (basis == null) return;
  final field = SensitivityField(engine.graph, basis);
  final top = field.gap().take(3).toList();
  if (top.isEmpty) return;
  final pieces = <String>[];
  for (final edge in top) {
    final a = edge.a >= 0 && edge.a < engine.nodePaths.length
        ? engine.nodePaths[edge.a]
        : '?';
    final b = edge.b >= 0 && edge.b < engine.nodePaths.length
        ? engine.nodePaths[edge.b]
        : '?';
    pieces.add('$a↔$b (s=${edge.value.toStringAsFixed(2)})');
  }
  buf.writeln('keystone_edges: ${pieces.join(", ")}');
}

/// Build a compact outline of a large file — class/function/method signatures
/// with line numbers. Gives the AI structural awareness without full source.
String _buildFileOutline(String content, String filePath, int lineCount) {
  final lines = content.split('\n');
  final outline = StringBuffer();
  outline.writeln('--- $filePath ($lineCount lines, outline only) ---');

  // Universal structure detection — works across languages by matching
  // patterns that indicate "this line defines something":
  //   • Type/class/struct declarations (class Foo, struct Bar, interface Baz)
  //   • Function/method signatures (lines with parens that aren't calls)
  //   • Decorators/annotations that precede definitions (@override, #[derive])
  //   • Module/namespace declarations
  // Not language-specific — catches the shape of declarations, not keywords.
  final sigPatterns = [
    // Type declarations: class, struct, enum, interface, trait, protocol, etc.
    RegExp(
        r'^\s*(?:export\s+)?(?:abstract\s+)?(?:class|struct|enum|mixin|extension|interface|trait|protocol|type|union|module|namespace|package)\s+\w+'),
    // Function/method declarations: lines ending with { or : or => after parens
    RegExp(
        r'^\s*(?:export\s+)?(?:pub\s+)?(?:static\s+)?(?:async\s+)?(?:const\s+)?(?:\w+\s+)*\w+\s*(?:<[^>]*>\s*)?\([^)]*\)\s*(?:async\s*)?[{:=>\-]?\s*$'),
    // Python/Ruby style: def/fn at start of line
    RegExp(r'^\s*(?:def|fn|func|function|sub|proc|method)\s+\w+'),
    // Go style: func (receiver) name(
    RegExp(r'^\s*func\s+(?:\([^)]*\)\s+)?\w+\s*\('),
    // Annotations/decorators on their own line (precede definitions)
    RegExp(r'^\s*(?:@\w+|#\[[\w:]+)'),
  ];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    for (final pattern in sigPatterns) {
      if (pattern.hasMatch(line)) {
        outline.writeln('  L${i + 1}: ${line.trim()}');
        break;
      }
    }
  }

  return outline.toString();
}

Future<_DiffPromptBundle> _buildDiffPromptBundle(
  String fullDiff, {
  required String repositoryPath,
  SymbolFrequencyIndex? symbolIndex,
  FileCouplingMatrix? couplingMatrix,
  // When the caller has already run [_runLogosDiffusion] (producer
  // path), pipe its evidence in here so [rankHunksByPhiAsync] skips
  // its own duplicate `engine.gatherEvidence` call. The cheap
  // [buildHunkFileEvidenceFromResiduals] view is all `rank` needs;
  // computing evidence twice on the same engine costs 1-5 seconds on
  // diffs touching 50+ files.
  hunks.HunkFileEvidence? precomputedFileEvidence,
}) async {
  //
  // Every diff — small, medium, huge — flows through the same hunk-
  // diffusion + knapsack admission. The budget [_kDiffBudgetChars] is
  // the single dial; when the natural diff fits, all hunks admit and
  // the output is structurally equivalent to a "full diff" emission.
  // When it doesn't, the same machinery drops lower-φ hunks. No mode
  // switch, no threshold.
  //
  // Two side captures preserve visibility for things the hunk parser
  // can't handle:
  //   • Git-header lines (mode, rename from/to, similarity, binary
  //     marker) emitted above `@@` for any file that has them —
  //     includes pure renames with NO hunks AND rename-with-edits
  //     where the hunks flow through the packer but the rename
  //     header would otherwise be lost. Rendered in a
  //     `<header_metadata>` postscript.
  //   • Diffs with NO parseable hunks at all (malformed, exotic
  //     format) — honest raw-text fallback at the same budget.

  final metadataOnly = _extractMetadataOnlyChanges(fullDiff);

  final parsed = hunks.parseDiffHunks(fullDiff);
  if (parsed.isEmpty) {
    // No parseable hunks. Could be entirely metadata-only, or just an
    // exotic format. Emit what we can: metadata postscript if we have
    // any, else honest raw-text capped at the same budget so context
    // accounting stays consistent with the parseable path.
    if (metadataOnly.isNotEmpty) {
      return _DiffPromptBundle(
        promptBody: _formatMetadataOnlyBlock(
          metadataOnly,
          maxChars: _kDiffBudgetChars,
        ),
        originalDiffCharacters: fullDiff.length,
      );
    }
    final truncated = fullDiff.substring(
      0,
      math.min(_kDiffBudgetChars, fullDiff.length),
    );
    return _DiffPromptBundle(
      promptBody: '<diff_unparseable>\n$truncated\n</diff_unparseable>',
      originalDiffCharacters: fullDiff.length,
    );
  }

  LogosGit? engine;
  try {
    engine = await resolveLogosGit(repositoryPath);
  } catch (_) {
    engine = null;
  }

  // Alexandria engram for K-space hunk similarity (H_sym augment +
  // semantic well labels). Loading is cached across calls; the first
  // diff pays the ~12MB vocab parse, subsequent diffs reuse the
  // already-decoded byte blobs. A null result silently falls back to
  // Jaccard-only H_sym.
  final engramAssets = await EngramRuntime.instance.assets();

  final ranking = await hunks.rankHunksByPhiAsync(
    hunks: parsed,
    logosEngine: engine,
    engramAssets: engramAssets,
    fileEvidence: precomputedFileEvidence,
  );

  // Semantic manifest: turn logos + engram outputs into a compact
  // structured narrative that sits ABOVE the packed diff. The model
  // sees "here is what the engine already determined" before it sees
  // raw hunk text — which collapses the cross-hunk-reasoning
  // hallucination class (moves misread as removals, etc.). Bounded
  // by its own internal caps; deduct its size from the packer's
  // budget so the combined body stays under [_kDiffBudgetChars].
  //
  // Fail-soft: the builder is pure and never throws, but the render
  // path traverses dozens of string ops. Any defect there must NOT
  // tank the whole AI invocation — an empty manifest silently falls
  // through to the packed-diff-only path the pipeline had before this
  // feature shipped.
  String manifestXml = '';
  try {
    final manifest = buildSemanticManifest(
      ranking.rankings,
      symbolIndex: symbolIndex,
      couplingMatrix: couplingMatrix,
    );
    if (!manifest.isEmpty) {
      manifestXml = manifest.toPromptXml();
    }
  } catch (e, st) {
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'warning',
      command: 'ai.semantic_manifest',
      message: 'manifest build/render failed, skipping: $e\n$st',
    );
    manifestXml = '';
  }
  final packBudget = math.max(
    0,
    _kDiffBudgetChars - (manifestXml.isEmpty ? 0 : manifestXml.length + 1),
  );

  final pack = diff_attention.compactHunksUnderBudget(
    rankings: ranking.rankings,
    budgetChars: packBudget,
  );

  // Visualisation event: hunks ranked + packed. Canvas fills the
  // footer bars with per-hunk φ and shows the budget fraction used.
  // Under LOD compaction `skipped` semantically becomes "clustered"
  // — the reviewer still gets aggregate evidence for those hunks.
  LogosVisBus.instance.emitInSession(
    (sid) => LogosVisHunksRanked(
      sid,
      rankings: [for (final r in ranking.rankings) r.phi],
      admitted: pack.admittedCount,
      skipped: pack.clusteredCount,
      budgetFraction: packBudget > 0
          ? (pack.body.length / packBudget).clamp(0.0, 1.0)
          : 0.0,
    ),
  );

  // Append the metadata postscript when there's anything to say.
  // The compactor's body already carries `<logos_diff_attention
  // budget=B rendered=R admitted=N clustered=M>` honesty; the
  // postscript adds visibility for changes the parser couldn't
  // represent as hunks. Both inside the same bundle body — the
  // prompt template wraps the whole thing once.
  //
  // Postscript is bounded against what's left of the diff budget
  // (after the packer's body) so a 2000-binary-file repo can't blow
  // the prompt with metadata noise. Per-entry caps inside the
  // formatter prevent any single file from monopolising the block.
  final buf = StringBuffer();
  if (manifestXml.isNotEmpty) {
    buf.writeln(manifestXml);
  }
  buf.write(pack.body);
  if (metadataOnly.isNotEmpty) {
    final remaining = _kDiffBudgetChars - buf.length;
    if (remaining > 0) {
      final block = _formatMetadataOnlyBlock(metadataOnly, maxChars: remaining);
      if (block.isNotEmpty) {
        if (buf.isNotEmpty) buf.writeln();
        buf.write(block);
      }
    }
  }

  final promptBody = _capPromptBody(buf.toString(), 'diff_prompt_bundle');
  return _DiffPromptBundle(
    promptBody: promptBody,
    originalDiffCharacters: fullDiff.length,
  );
}

/// Test-visible alias of [_extractMetadataOnlyChanges] — the parser
/// is private to ai.dart but the behaviour is foundational enough
/// (binary/mode-only/rename visibility under the unified pipeline)
/// that it deserves direct unit coverage.
@visibleForTesting
Map<String, List<String>> extractMetadataOnlyChangesForTesting(
        String fullDiff) =>
    _extractMetadataOnlyChanges(fullDiff);

/// Walk a unified-diff and capture file-level metadata that the hunk
/// packer silently drops:
///   • `Binary files a/X and b/X differ`
///   • `old mode 100644` / `new mode 100755` / `new file mode N`
///   • `similarity index N%` / `rename from`/`rename to`
///   • `copy from`/`copy to`
///   • `deleted file mode N` / `dissimilarity index N%`
/// Captured for ALL files (not just hunkless ones) — a file with a
/// mode change AND content edits would otherwise have its mode change
/// vanish from the prompt because the packer reassembles only the
/// `diff --git` / `---` / `+++` triple per file.
/// Filters OUT noise lines:
///   • `index abc..def` (blob SHAs — useless for AI)
///   • `--- a/X` / `+++ b/X` (auto-emitted by the packer)
/// Handles git's C-string quoting for paths containing spaces or
/// non-ASCII characters: `diff --git "a/X X" "b/X X"`.
/// Returns Map<path, metadataLines>. Empty when nothing notable.
Map<String, List<String>> _extractMetadataOnlyChanges(String fullDiff) {
  final out = <String, List<String>>{};
  String? currentPath;
  var currentMetadata = <String>[];
  void flush() {
    if (currentPath == null) return;
    if (currentMetadata.isNotEmpty) {
      out[currentPath] = List.unmodifiable(currentMetadata);
    }
  }

  bool isMeaningful(String line) {
    // Drop `index`, `--- `, `+++ `. Keep mode/binary/rename/copy/
    // similarity/dissimilarity/new file/deleted file lines.
    if (line.startsWith('index ')) return false;
    if (line.startsWith('--- ')) return false;
    if (line.startsWith('+++ ')) return false;
    if (line.trim().isEmpty) return false;
    return true;
  }

  for (final line in fullDiff.split('\n')) {
    // diffHeaderPath covers both the unquoted and C-string-quoted
    // header forms — single source of truth in git.dart.
    final headerPath = diffHeaderPath(line);
    if (headerPath != null) {
      flush();
      currentPath = headerPath;
      currentMetadata = <String>[];
      continue;
    }
    if (currentPath == null) continue;
    if (line.startsWith('@@')) {
      // Content hunks are the packer's job — stop collecting metadata
      // for THIS file and skip ahead until the next `diff --git`.
      // What we collected BEFORE the first @@ stays.
      flush();
      currentPath = null;
      currentMetadata = <String>[];
      continue;
    }
    if (isMeaningful(line)) {
      currentMetadata.add(line);
    }
  }
  flush();
  return out;
}

/// Render the metadata postscript with per-entry and whole-block
/// caps. Returns '' if nothing fits within [maxChars]. The closing
/// `</header_metadata>` tag is always emitted (or the whole
/// block is dropped) — never returns malformed XML mid-tag.
/// Per-entry safety: each file's metadata is capped so one
/// pathological file (a 100-line conflict marker block, etc.) can't
/// monopolise the postscript and crowd out other files' visibility.
String _formatMetadataOnlyBlock(
  Map<String, List<String>> metadataOnly, {
  required int maxChars,
}) {
  if (metadataOnly.isEmpty) return '';
  // Per-file size cap. Most metadata blocks are 1–4 lines (mode +
  // binary marker, or rename source/target + similarity). Allow up
  // to ~400 chars per file before truncating that file's slice.
  const perFileCap = 400;
  final headerLine = '<header_metadata count=${metadataOnly.length}>\n';
  const closeLine = '</header_metadata>';
  // Reserve room for the open + close tags before admitting entries.
  var remaining = maxChars - headerLine.length - closeLine.length;
  if (remaining <= 0) return '';

  final buf = StringBuffer(headerLine);
  var truncatedFiles = 0;
  for (final entry in metadataOnly.entries) {
    final pathLine = '  ${entry.key}:\n';
    if (pathLine.length > remaining) {
      truncatedFiles += 1;
      continue;
    }
    final lineBuf = StringBuffer(pathLine);
    var lineRemaining = perFileCap - pathLine.length;
    for (final line in entry.value) {
      final formatted = '    ${line.trimRight()}\n';
      if (formatted.length > lineRemaining) break;
      lineBuf.write(formatted);
      lineRemaining -= formatted.length;
    }
    final entryStr = lineBuf.toString();
    if (entryStr.length > remaining) {
      truncatedFiles += 1;
      continue;
    }
    buf.write(entryStr);
    remaining -= entryStr.length;
  }
  if (truncatedFiles > 0) {
    final note = '  ($truncatedFiles more truncated for budget)\n';
    if (note.length <= remaining) {
      buf.write(note);
    }
  }
  buf.write(closeLine);
  return buf.toString();
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
  CommitStructure structure = kDefaultCommitStructure,
  CommitVoice voice = kDefaultCommitVoice,
  CommitCoverage coverage = kDefaultCommitCoverage,
  LogosCommitShape? logosShape,
}) {
  final buffer = StringBuffer();
  buffer.writeln('You are generating a git commit message.');
  buffer
      .writeln('Return only the message — plain text, ASCII characters only.');
  buffer.writeln();
  buffer.writeln('<commit_message_structure>');
  buffer.writeln(_structureDirective(structure));
  buffer.writeln(_voiceDirective(voice));
  buffer.writeln(_coverageDirective(coverage));
  buffer.writeln('</commit_message_structure>');
  buffer.writeln();
  // Logos shape block — regime + centroid + missing mass. Shape HINTS,
  // not requirements; the user's explicit structure/voice/coverage
  // prefs always override.
  final shapeBlock = _formatCommitShapeBlock(logosShape);
  if (shapeBlock.isNotEmpty) {
    buffer.writeln(shapeBlock);
    buffer.writeln();
  }
  buffer.writeln(
      'If <user_instructions> are present, follow them — they override format, tone, and style.');
  buffer.writeln();
  buffer.writeln('<generation_context>');
  buffer.writeln('Branch: $branchName');
  if (authorName.isNotEmpty) buffer.writeln('Author: $authorName');
  if (totalCommits > 0) buffer.writeln('Total commits: $totalCommits');
  if (projectAge.isNotEmpty) buffer.writeln('Project started: $projectAge');
  if (lastCommitAge.isNotEmpty) buffer.writeln('Last commit: $lastCommitAge');
  if (uniqueContributors > 0)
    buffer.writeln('Contributors (sampled): $uniqueContributors');
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

  return _capPromptBody(buffer.toString().trim(), 'commit_message_prompt');
}

//
// Each user-facing preference axis maps to an explicit instruction the
// model can follow. The three strings below are appended in sequence
// inside <commit_message_structure>; together they fully specify the
// skeleton, prose voice, and coverage depth the user picked in settings.
//
// Prompt discipline:
//   * positive phrasing only — every line tells the model what the
//     output IS, never what to avoid.
//   * no examples — models anchor too strongly on inline samples and
//     start echoing their specifics.
//   * no numbers or caps — thresholds like "at most two" invite the
//     model to either game the count or contort to satisfy it. The
//     user's chosen axis already carries the size signal.

String _structureDirective(CommitStructure s) {
  switch (s) {
    case CommitStructure.titleBody:
      return 'Structure: open with a single subject line, then a blank line, '
          'then a body paragraph. Let the subject read tight enough for the '
          'git log. Let the body carry motivation and impact.';
    case CommitStructure.titleOnly:
      return 'Structure: write a single subject line that stands on its own. '
          'Let every meaningful point sit inside that one line.';
    case CommitStructure.freeform:
      return 'Structure: write one flowing paragraph. Let the thought build '
          'naturally from the first sentence onward.';
  }
}

String _voiceDirective(CommitVoice v) {
  switch (v) {
    case CommitVoice.verbLed:
      return 'Voice: imperative mood. Open with an action verb in present '
          'tense. Let each sentence carry forward motion.';
    case CommitVoice.descriptive:
      return 'Voice: descriptive. Lead with nouns in present tense. State '
          'what the commit contains as a label of its content.';
    case CommitVoice.narrative:
      return 'Voice: narrative. Past tense and conversational. Tell the story '
          'of what happened and why.';
  }
}

String _coverageDirective(CommitCoverage c) {
  switch (c) {
    case CommitCoverage.essentials:
      return 'Coverage: name the headline change. Trust the diff to speak '
          'for the details.';
    case CommitCoverage.balanced:
      return 'Coverage: name the headline change along with the material '
          'consequences that matter most — the ones that ripple into '
          'callers or invariants.';
    case CommitCoverage.everything:
      return 'Coverage: surface the headline change along with every '
          'meaningfully-touched area. Name modules, call out invariants, '
          'trace downstream effects.';
  }
}

ReviewGuardrailProfile _guardrailProfileForStage(int stage) {
  switch (stage.clamp(0, 3)) {
    case 0:
      return const ReviewGuardrailProfile(
        id: 'loose',
        seat: 'focused sanity checker',
        wakeFrame:
            'A quick second pair of eyes. If something is probably fine, it is fine.',
        reviewRadius:
            'Keep the review local to the changed code and obvious nearby effects.',
        primaryFear:
            'Your main job is to catch concrete logic bugs and likely breakage in the code at hand.',
        silenceRule:
            'Stay silent on cosmetic opinions, abstract architecture critiques, and speculative edge cases that require unlikely preconditions.',
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
        wakeFrame: 'A proper read-through. Sit with the diff, check the work.',
        reviewRadius:
            'Review the changed code and its likely integration surface in the surrounding system.',
        primaryFear:
            'Your job is to catch correctness issues, regression risk, and meaningful inconsistency that weakens the change.',
        silenceRule:
            'Skip cosmetic nits and generic opinions. Surface only issues with practical engineering consequence.',
        verdictBar:
            'Downgrade when the evidence supports meaningful correctness, integration, or reliability risk.',
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
        wakeFrame:
            'What looks fine on first read — look again. Check underneath.',
        reviewRadius:
            'Review the changed code, nearby integration points, and hidden assumptions implied by the diff.',
        primaryFear:
            'Your job is to catch incomplete handling, hidden coupling, edge cases, and long-tail risks before commit.',
        silenceRule:
            'Surface subtle risks when supported by evidence in the diff. Leave aesthetics to linters.',
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
          ReviewConcernClass.destructiveRisk,
          ReviewConcernClass.securityRisk,
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
        wakeFrame:
            'Assume something is hiding. Find it, or confirm it is not there.',
        reviewRadius:
            'Review the changed code, integration surface, and any broader operational or safety consequences supported by the diff.',
        primaryFear:
            'Your job is to prevent harmful surprises such as destructive behavior, data loss, corruption, security exposure, and silent regressions.',
        silenceRule:
            'Flag credible risks even when evidence is circumstantial. State your reasoning clearly.',
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
        requireConcreteEvidence: false,
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
    'Reading the evidence, in the voice of a careful reviewer:\n'
    '\n'
    'You have several evidence channels this turn. Each one speaks with '
    'its own voice, and a strong review cites each for what it knows best.\n'
    '\n'
    '  • <change_types> — the file history channel. New, modified, '
    'deleted, renamed. Trust it for "what changed and how."\n'
    '  • <structural_verification> — the existence channel. Imports, '
    'symbol definitions, live repo state. Trust it for "does X actually '
    'exist where this diff says it does."\n'
    '  • <file_metadata> — authorship, churn, test coverage. Use it to '
    'ask "who has touched this recently and is it guarded."\n'
    '  • <file_context> — full source of small changed files. Use it to '
    'verify imports, signatures, and the code around the edit.\n'
    '  • <relevance_neighborhood> — files NOT in the diff that the '
    'engine felt pulled toward. Each carries a relevance band (trace → '
    'weak → moderate → strong → dominant) and a via= trail of coupling '
    'axes (symbol-pickaxe, code-coupling, path-mirror, folder-hub, '
    'enrichment) with a strength word. This is where you look for '
    '"what else might this affect."\n'
    '  • <logos_topology> — the spectral read. Qualitative bands for '
    'coherence, motion, stress, witness coverage. This is where you '
    'learn "what SHAPE is this change." Also carries three structural '
    'signals worth knowing:\n'
    '      – `geometry:` names the repo\'s nearest archetype '
    '(crystalline / poisson / goe / tree / bulk / modular) with a '
    'decisiveness reading. A `tree` geometry means strict hierarchy '
    '(cross-cutting changes ripple far); `modular` means clustered '
    '(API-boundary refactors are cheap); `goe` means chaotic (blast '
    'radius is hard to predict).\n'
    '      – `structural:` gives component and cycle counts of the '
    'coupling graph. High components with low cycles means the diff '
    'touches isolated islands; the opposite means an integrated core.\n'
    '      – `keystone_edges:` lists the pairs whose coupling holds '
    'the graph together. Touching a keystone is a qualitatively '
    'different claim than touching a high-relevance peripheral file '
    '— narrate it as such when a diff lands on one.\n'
    '\n'
    'How these blocks speak to you:\n'
    '\n'
    '  • Each block opens with a `status:` line. `populated` means the '
    'channel has something to say — listen and cite. `warming`, `quiet`, '
    '`empty` mean that channel is resting this turn — receive the '
    'silence as information about what you DON\'T know, and let your '
    'findings come from the channels that are awake.\n'
    '  • A `confidence:` band on a block tells you how firmly to lean '
    'on it. `high` carries your verdict-bearing findings. `moderate` '
    'supports observations and texture. `low` is a whisper — worth '
    'noting, not worth standing on.\n'
    '  • When a neighbor shows `via=(no axis support)`, the engine '
    'surfaced it by feel rather than by a named path. You can mention '
    'its presence as a prompt for attention, but speak only to what its '
    'source shows — leave the coupling unnamed rather than inventing one. '
    'Honesty about what you don\'t know is a feature of the craft.\n'
    '  • Cite the qualitative bands — "scattered", "active", "sparse '
    'coverage", "strong relevance". They\'re stable vocabulary the '
    'engine and the reviewer share. Raw numbers are deliberately '
    'absent so your writing doesn\'t drift into numerology.\n'
    '  • Individual hunks in the packed diff may carry '
    '`innov=`, `transport=`, `witness=` annotations. These are '
    'corpus-relative residuals on a 0..1 scale: `innov` near 1 means '
    'the hunk introduces structure the repo hasn\'t seen before; '
    '`transport` means the hunk\'s parent file is pulled in by graph '
    'coupling; `witness` means the corpus corroborates the change. '
    'Use them to distinguish a novel-mechanism hunk from a high-'
    'relevance maintenance hunk.\n'
    '  • If you see an `<engine_failure channel="..." reason="..."/>` '
    'marker, that channel was attempted but did not produce. Treat it '
    'the same as a `quiet` status — source findings from the channels '
    'that are awake; do not fill in the silence.\n'
    '  • Entries in `<relevance_neighborhood>` may carry a `depth=N` '
    'tag. `depth=0` or no tag means the file is in the diff or a '
    'direct neighbour; `depth=1+` means the engine reached it by '
    're-probing from an earlier iteration (a "second-order" relation). '
    'A high-depth file is still real evidence, just further from the '
    'diff\'s touch surface — weight your claims accordingly. If '
    '`<logos_topology>` shows `exploration: iters=N converged=false`, '
    'the iteration cap cut the search short, so the neighbourhood may '
    'be incomplete.\n'
    '\n'
    'Ground each finding in a block you can name. Let findings you '
    'can\'t anchor pass by — they\'ll have their turn when the evidence '
    'is there. When verification confirms something, treat it as fact. '
    'When a channel is quiet, let it be quiet; the review is stronger '
    'for what it accurately says than for what it fills in.',
  );
  if (profile.requireConcreteEvidence) {
    buffer.writeln(
      'Every concern must cite concrete evidence from the diff or its structural context.',
    );
  }
  buffer.writeln(
    'Use <findings> for things that are concretely wrong — bugs, breakage, '
    'missing files, incorrect logic. Use <observations> for anything else '
    'that surfaced during review — complexity, trade-offs, assumptions, risk. '
    'The score follows from findings alone. '
    'Leave code style to linters.',
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
  if (spec.commitDraft.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<author_message>');
    buffer.writeln('What the user has written about this change, in '
        'their own words, while the work was in progress. This is '
        'the human\'s framing — what they would say the change is '
        'for. Read it as the strongest signal for what the work is '
        'reaching for; the diff shows the how, this shows the why.');
    buffer.writeln();
    buffer.writeln(spec.commitDraft.trim());
    buffer.writeln('</author_message>');
  }
  buffer.writeln();
  buffer.writeln('<diff_context>');
  buffer.writeln(spec.diffSummary.trim());
  buffer.writeln('</diff_context>');

  return _capPromptBody(buffer.toString().trim(), 'commit_review_prompt');
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
    buffer.writeln(profile.wakeFrame);
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
Return only the XML-like schema below — no surrounding prose.
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
Return only the XML-like schema below — no surrounding prose.
Use exactly this shape:
<review_result>
<verdict>Ready|Mostly ready|Needs attention|High risk|Block</verdict>
<score>0-100 confidence that this commit lands cleanly. The score reflects what you found — let the evidence decide.</score>
<summary>One sentence — what was found, not what was built.</summary>
<summary_reasoning>Plain-language explanation of the reasoning behind the verdict and score.</summary_reasoning>
<findings>
<finding id="F1" severity="note|warn|risk|block" file="path/or/-" hunk="@@ ... @@ or -">
<title>Short title</title>
<evidence>Concrete evidence from the diff showing something that is wrong or will break</evidence>
<why>The practical consequence — what breaks, what fails, what produces incorrect results</why>
</finding>
</findings>
<observations>
<observation id="O1" file="path/or/-">
<title>Short title</title>
<detail>What you noticed and why it matters for context</detail>
</observation>
</observations>
</review_result>
A finding belongs in findings when you are certain — you can prove it from the evidence.
An observation belongs in observations when you are noting something worth awareness — a trade-off, a design choice, a consideration.
Certainty is the separator: proven facts go to findings, everything else goes to observations.
Empty findings are welcome when the commit is genuinely clean — but verify before concluding.
Observations hold everything that didn't crystallize into a finding — the texture of the change.
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
  String? reasoningEffort,
  bool fastMode = false,
  bool supportsReasoning = true,
  int? maxTokens,
}) async {
  if (provider.kind == _ProviderKind.apiProvider && provider.apiProvider != null) {
    final entry = _apiKeysSnapshot[provider.id];
    if (entry == null || entry.apiKey.trim().isEmpty) {
      return _ProviderPromptResult(
        ok: false,
        error: '${provider.apiProvider!.displayName}: no API key configured.',
        outputPreview: '',
      );
    }
    final creds = AiApiCredentials(
      apiKey: entry.apiKey,
      baseUrl: entry.baseUrl,
    );
    final effectiveEffort =
        fastMode || !supportsReasoning ? null : reasoningEffort;
    final apiResult = await provider.apiProvider!.complete(AiApiRequest(
      prompt: prompt,
      model: modelId,
      credentials: creds,
      reasoningEffort: effectiveEffort,
      maxTokens: maxTokens,
    ));
    if (apiResult.text == null) {
      return _ProviderPromptResult(
        ok: false,
        error: _scrubSecrets(
          apiResult.error ?? '${provider.apiProvider!.displayName} returned no response.',
        ),
        outputPreview: _scrubSecrets(apiResult.error ?? ''),
      );
    }
    return _ProviderPromptResult(
      ok: true,
      output: apiResult.text,
      outputPreview: apiResult.text!.length > 200
          ? '${apiResult.text!.substring(0, 200)}...'
          : apiResult.text!,
      inputTokens: apiResult.inputTokens,
      outputTokens: apiResult.outputTokens,
    );
  }

  if (provider.kind == _ProviderKind.geminiApi) {
    final geminiModel = modelId.startsWith('gemini ')
        ? modelId.substring('gemini '.length)
        : modelId;
    final apiResult = await _runGeminiApiRequest(prompt, geminiModel,
        maxTokens: maxTokens);
    if (apiResult.text == null) {
      return _ProviderPromptResult(
        ok: false,
        error: apiResult.error ?? 'Gemini API returned no response.',
        outputPreview: _scrubSecrets(apiResult.error ?? ''),
      );
    }
    return _ProviderPromptResult(
      ok: true,
      output: apiResult.text,
      outputPreview: apiResult.text!.length > 200
          ? '${apiResult.text!.substring(0, 200)}...'
          : apiResult.text!,
      inputTokens: apiResult.inputTokens,
      outputTokens: apiResult.outputTokens,
    );
  }

  final attempts = _buildProviderAttempts(provider.kind, modelId,
      readOnly: readOnly,
      resolvedCommand: resolution.command,
      reasoningEffort: reasoningEffort,
      fastMode: fastMode);
  String? providerOutput;
  String? lastError;
  for (final attempt in attempts) {
    final effectiveArgs =
        attempt.useStdinForPrompt ? attempt.args : [...attempt.args, prompt];
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
  // Hard-required: the verdict + score + summary triad. Without these
  // the report can't be rendered meaningfully. `summary_reasoning` is
  // soft-required — weaker models often omit it, and refusing the
  // whole report over a missing reasoning blurb wastes the rest of
  // the parsed work. Empty string is the graceful fallback.
  if (verdict == null || scoreRaw == null || summary == null) {
    return null;
  }
  // Tolerate models that wrap the score with extra prose: `72/100`,
  // `**72**`, `72 (high confidence)`, etc. Pull the first integer
  // out of the tag content rather than expecting a clean digit string.
  // Was strict `int.tryParse(scoreRaw.trim())` which broke on any
  // formatting variation the model decided to add.
  final scoreDigits = RegExp(r'\d+').firstMatch(scoreRaw);
  final score =
      scoreDigits == null ? null : int.tryParse(scoreDigits.group(0)!);
  if (score == null) {
    return null;
  }
  final findingsBlock = _extractTag(normalized, 'findings') ?? '';
  final findings = _parseFindingTags(findingsBlock, origin: 'draft');
  final observationsBlock = _extractTag(normalized, 'observations') ?? '';
  final observations = _parseObservationTags(observationsBlock);
  return _ParsedReviewResult(
    verdict: _normalizeVerdict(verdict),
    score: score.clamp(0, 100),
    summary: summary.trim(),
    // Empty fallback when the model didn't include reasoning — the
    // UI handles an empty reasoningReport (just doesn't render the
    // section). Better than failing the entire parse.
    reasoningReport: summaryReasoning?.trim() ?? '',
    findings: findings,
    observations: observations,
  );
}

AiCommitReviewVerificationData? _parseVerificationReview(String raw) {
  final normalized = _normalizeModelMarkup(raw);
  final notes = _extractTag(normalized, 'verification_notes');
  final scoreAdjustmentRaw = _extractTag(normalized, 'score_adjustment');
  final finalSummary = _extractTag(normalized, 'final_summary');
  final summaryReasoning = _extractTag(normalized, 'summary_reasoning');
  // Same parser-resilience policy as `_parseDraftReview`: notes +
  // scoreAdjustment + finalSummary are hard-required (the verification
  // pass is meaningless without them); summaryReasoning is soft —
  // empty fallback if the model omits it.
  if (notes == null || scoreAdjustmentRaw == null || finalSummary == null) {
    return null;
  }
  // Tolerate prose-wrapped score adjustments (`-4`, `-4 points`,
  // `-4 (raised confidence)`, etc.). Pull the first signed integer.
  final scoreMatch = RegExp(r'-?\d+').firstMatch(scoreAdjustmentRaw);
  final scoreAdjustment =
      scoreMatch == null ? null : int.tryParse(scoreMatch.group(0)!);
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
    // Same null-tolerant pattern as the draft parser — empty string
    // when the model omits the reasoning blurb. The UI gates the
    // reasoning section on `isNotEmpty` so empty just hides the panel.
    finalReasoningReport: summaryReasoning?.trim() ?? '',
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
  final idPrefix =
      isDraft ? _findingIdPrefixDraft : _findingIdPrefixVerification;
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

List<AiCommitReviewObservationData> _parseObservationTags(String block) {
  final matches = _observationTagRegex.allMatches(block);
  final observations = <AiCommitReviewObservationData>[];
  var index = 0;
  for (final match in matches) {
    final attrs = _parseXmlAttributes(match.group(1) ?? '');
    final body = match.group(2) ?? '';
    index += 1;
    observations.add(
      AiCommitReviewObservationData(
        id: (attrs['id']?.trim().isNotEmpty ?? false)
            ? attrs['id']!.trim()
            : 'O$index',
        title: (_extractTag(body, 'title') ?? 'Observation $index').trim(),
        detail: (_extractTag(body, 'detail') ?? '').trim(),
        filePath: _normalizedOptionalTagAttribute(attrs['file']),
      ),
    );
  }
  return observations;
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
    ..sort((left, right) => _severityWeight(right.severity)
        .compareTo(_severityWeight(left.severity)));

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
  buffer.writeln(
      '<summary_reasoning>${draft.reasoningReport}</summary_reasoning>');
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

/// Caps [payload] at [_maxPromptChars] and records a telemetry event
/// when the truncation fires. Previously the cap was silent, so an
/// upstream tweak that pushed a prompt over would silently chop the
/// tail of `<relevance_neighborhood>` without any trace. [scope]
/// identifies the caller in the command-lifecycle log.
String _capPromptBody(String payload, String scope) {
  if (payload.length <= _maxPromptChars) return payload;
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'warning',
    command: 'ai.prompt.truncate',
    message:
        'prompt capped from ${payload.length} to $_maxPromptChars chars in $scope',
  );
  return payload.substring(0, _maxPromptChars);
}

String _previewText(String value, {int? maxLength}) {
  final limit = maxLength ?? _previewMaxLength;
  final normalized = value.replaceAll('\r\n', '\n').trim();
  if (normalized.length <= limit) {
    return normalized;
  }
  return '${normalized.substring(0, limit - _truncationSuffix.length)}$_truncationSuffix';
}

String? _codexEffort(String? effort) {
  // Codex accepts: none, minimal, low, medium, high, xhigh.
  // Map from our canonical levels via effortFraction → nearest codex level.
  const codexLevels = ['none', 'minimal', 'low', 'medium', 'high', 'xhigh'];
  const codexThresholds = [0.0, 0.1, 0.236, 0.382, 0.618, 1.0];
  if (effort == null) return null;
  if (codexLevels.contains(effort)) return effort;
  final f = effortFraction(effort);
  if (f == null) return null;
  var best = codexLevels.last;
  for (var i = 0; i < codexThresholds.length; i++) {
    if (f <= codexThresholds[i] + 0.01) {
      best = codexLevels[i];
      break;
    }
  }
  return best;
}

String? _claudeEffort(String? effort) {
  // Claude CLI accepts: low, medium, high.
  const claudeLevels = ['low', 'medium', 'high'];
  const claudeThresholds = [0.236, 0.382, 1.0];
  if (effort == null) return null;
  if (claudeLevels.contains(effort)) return effort;
  final f = effortFraction(effort);
  if (f == null) return null;
  var best = claudeLevels.last;
  for (var i = 0; i < claudeThresholds.length; i++) {
    if (f <= claudeThresholds[i] + 0.01) {
      best = claudeLevels[i];
      break;
    }
  }
  return best;
}

List<_ProviderAttempt> _buildProviderAttempts(
  _ProviderKind kind,
  String modelId, {
  bool readOnly = true,
  String resolvedCommand = '',
  String? reasoningEffort,
  bool fastMode = false,
}) {
  switch (kind) {
    case _ProviderKind.codex:
      final mapped = _codexEffort(reasoningEffort);
      final configArgs = <String>[
        if (mapped != null)
          ...['-c', 'model_reasoning_effort="$mapped"'],
        if (fastMode)
          ...['-c', 'service_tier="fast"'],
      ];
      return [
        _ProviderAttempt(
          name: 'exec-json',
          args: [
            'exec', '--model', modelId, ...configArgs, '--json', '-',
          ],
          outputMode: _ProviderOutputMode.codexJsonl,
        ),
        _ProviderAttempt(
          name: 'exec',
          args: ['exec', '--model', modelId, ...configArgs, '-'],
          outputMode: _ProviderOutputMode.plainText,
        ),
      ];
    case _ProviderKind.claude:
      final mappedClaude = _claudeEffort(reasoningEffort);
      final effortArgs = mappedClaude != null
          ? ['--effort', mappedClaude]
          : const <String>[];
      return [
        _ProviderAttempt(
          name: 'prompt-json',
          args: [
            '-p', '--model', modelId, ...effortArgs,
            '--output-format', 'json',
          ],
          outputMode: _ProviderOutputMode.claudeJson,
        ),
        _ProviderAttempt(
          name: 'prompt',
          args: ['-p', '--model', modelId, ...effortArgs],
          outputMode: _ProviderOutputMode.plainText,
        ),
      ];
    case _ProviderKind.geminiApi:
    case _ProviderKind.apiProvider:
      // API providers — no CLI attempts.
      return [];
    case _ProviderKind.openCode:
      final variantArgs = reasoningEffort != null
          ? ['--variant', reasoningEffort]
          : const <String>[];
      return [
        _ProviderAttempt(
          name: 'run-json',
          args: ['run', '--format', 'json', '-m', modelId, ...variantArgs],
          outputMode: _ProviderOutputMode.openCodeJsonl,
        ),
        _ProviderAttempt(
          name: 'run',
          args: ['run', '-m', modelId, ...variantArgs],
          outputMode: _ProviderOutputMode.plainText,
        ),
      ];
  }
}

Map<String, String> _providerEnvironment(_ProviderKind kind) {
  switch (kind) {
    case _ProviderKind.claude:
      return const {'CLAUDE_CODE_ENTRYPOINT': 'cli'};
    case _ProviderKind.geminiApi:
    case _ProviderKind.apiProvider:
      return const {};
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

/// Walks an arbitrarily nested provider error payload and returns the
/// deepest human-readable message it can find. Providers wrap the
/// same text inside multiple layers — `{error: {message: ...}}`,
/// `{errors: [{message: ...}]}`, `{message: "<json blob>"}` — so
/// surfacing the outer object verbatim shows the user a glob of JSON
/// instead of a sentence. The walker descends through the well-known
/// nesting keys (in priority order: `error`, `errors`, `data`,
/// `cause`, then `message`) and treats any string that looks like
/// JSON as a chance to recurse one more level. Bounded by [maxDepth]
/// so a circular or pathologically nested payload can't hang us.
///
/// Provider-agnostic on purpose — codex, opencode, claude, and any
/// future SDK that nests structured errors the same way will all
/// benefit without bespoke parsing code.
String? _extractDeepestErrorMessage(dynamic node, {int maxDepth = 6}) {
  String? walk(dynamic n, int depth) {
    if (depth > maxDepth) return null;
    if (n is String) {
      final trimmed = n.trim();
      if (trimmed.isEmpty) return null;
      // Don't try to JSON-decode every string — only those that
      // actually look like a JSON object/array head.
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return walk(jsonDecode(trimmed), depth + 1) ?? trimmed;
        } catch (_) {
          return trimmed;
        }
      }
      return trimmed;
    }
    if (n is Map) {
      // Prefer the most-specific nested locations first. Each of these
      // is a known shape used by at least one provider in the wild.
      for (final key in const ['error', 'errors', 'data', 'cause']) {
        if (n.containsKey(key)) {
          final inner = walk(n[key], depth + 1);
          if (inner != null && inner.isNotEmpty) return inner;
        }
      }
      // Fall through to the leaf-ish `message` field. Recurse so a
      // JSON-encoded string here is unwrapped one more level.
      if (n['message'] != null) {
        final inner = walk(n['message'], depth + 1);
        if (inner != null && inner.isNotEmpty) return inner;
      }
      return null;
    }
    if (n is List) {
      for (final item in n) {
        final inner = walk(item, depth + 1);
        if (inner != null && inner.isNotEmpty) return inner;
      }
      return null;
    }
    return null;
  }

  return walk(node, 0);
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
      if (type == 'error' || type == 'turn.failed') {
        // Codex nests the human-readable text behind a JSON-encoded
        // string field (and sometimes again behind an `error.message`)
        // — let the deep extractor unwrap to the leaf rather than
        // surfacing the wrapper JSON blob to the user.
        final extracted = _extractDeepestErrorMessage(value);
        if (extracted != null && extracted.isNotEmpty) {
          errorMessage = extracted;
        }
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
        // Same emergent extraction as the codex parser — opencode also
        // ships `error.data.message` for some providers, plus the
        // occasional JSON-encoded string at top level.
        final extracted = _extractDeepestErrorMessage(value);
        if (extracted != null && extracted.isNotEmpty) {
          errorMessage = extracted;
        }
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
  if (errorMessage != null && errorMessage.trim().isNotEmpty) {
    return 'OpenCode error: ${_stripAnsi(errorMessage.trim())}';
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
    case _ProviderKind.geminiApi:
      return lower.startsWith('gemini error:');
    case _ProviderKind.apiProvider:
      // Dead path — API providers return structured AiApiResponse before
      // reaching the CLI output classifier. Kept narrow to avoid false
      // positives if a future refactor routes output through here.
      return lower.startsWith('openrouter: ') ||
          lower.startsWith('openai: ') ||
          lower.startsWith('anthropic: ') ||
          lower.startsWith('x-ai (grok): ') ||
          lower.startsWith('connection failed');
  }
}

String _normalizeProviderError(_ProviderKind kind, String raw) {
  final normalized = _stripAnsi(raw.trim());
  if (normalized.isEmpty) {
    return 'The provider did not return a usable response.';
  }

  final provider = switch (kind) {
    _ProviderKind.openCode => _normalizeOpenCodeError(normalized),
    _ProviderKind.codex => _normalizeCodexError(normalized),
    _ProviderKind.claude => normalized,
    _ProviderKind.geminiApi => _normalizeGeminiError(normalized),
    _ProviderKind.apiProvider => normalized,
  };
  // Never let a provider echo a bearer token, API key, or session cred
  // into a snackbar, log, or DiagnosticsState record. Providers ARE
  // observed to dump auth headers on 401/403 (verified with Gemini +
  // some Claude setups); sanitize at the single chokepoint so every
  // call site is protected.
  return _scrubSecrets(provider);
}

/// Redacts common secret shapes from provider/CLI error output before
/// it escapes into user-visible text or diagnostics. Not exhaustive —
/// intentionally focused on the patterns most likely to appear in
/// provider error echoes. False positives (masking a non-secret that
/// matches the pattern) are acceptable; false negatives leak tokens.
String _scrubSecrets(String input) {
  var s = input;
  // Authorization: Bearer … (HTTP auth header in stderr)
  s = s.replaceAll(RegExp(r'([Bb]earer\s+)[A-Za-z0-9._\-]+', multiLine: true),
      r'$1[redacted]');
  // Google API keys (AIza…, 39 chars)
  s = s.replaceAll(
      RegExp(r'AIza[0-9A-Za-z_\-]{35}'), '[redacted:google-api-key]');
  // GitHub personal access tokens, app tokens, etc.
  s = s.replaceAll(
      RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}'), '[redacted:gh-token]');
  // OpenAI / Anthropic / OpenRouter / generic sk- tokens
  s = s.replaceAll(
      RegExp(r'sk-(?:ant-|or-)?[A-Za-z0-9_\-]{20,}'), '[redacted:sk-token]');
  // X-AI (Grok) API keys
  s = s.replaceAll(
      RegExp(r'xai-[A-Za-z0-9_\-]{20,}'), '[redacted:xai-token]');
  // AWS access keys
  s = s.replaceAll(RegExp(r'AKIA[0-9A-Z]{16}'), '[redacted:aws-akid]');
  // JWT-ish triplets (base64.base64.base64)
  s = s.replaceAll(
      RegExp(
          r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'),
      '[redacted:jwt]');
  return s;
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
//   workdir: ...
//   model: ...
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
    WinJobObject.assignProcess(process.pid);
    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      await killProcessTree(process, timeout: defaultProcessKillTimeout);
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
      WinJobObject.assignProcess(process.pid);
      try {
        await process.stdin.close();
      } catch (_) {}
    } else {
      process = await Process.start(
        invocation.command,
        invocation.args,
        workingDirectory: workingDirectory,
        runInShell: false,
        environment: environment.isEmpty ? null : environment,
      );
      WinJobObject.assignProcess(process.pid);
      // Non-Windows or no stdin payload — use pipe normally.
      try {
        if (stdinPayload != null) {
          process.stdin.write(stdinPayload);
          await process.stdin.flush();
        }
        await process.stdin.close();
      } catch (_) {}
    }

    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      final killed = await killProcessTree(
        process,
        timeout: defaultProcessKillTimeout,
      );
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'failure',
        command: commandLabel,
        durationMs: elapsedMs,
        errorCode: '$scope.timeout',
        message: killed
            ? 'Process timed out and was terminated.'
            : 'Process timed out; termination was not confirmed.',
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
    // Clean up the stdin temp file + its .bat sibling. On Windows the
    // prompt body lives on disk briefly; shrink the exposure window by
    // overwriting with empty content before unlinking, and skip the
    // sibling-delete attempt when no stdin file was created (avoids a
    // pointless File('null.bat').deleteSync throwing every call).
    if (stdinTempFile != null) {
      try {
        stdinTempFile.writeAsStringSync('', flush: true);
      } catch (_) {}
      try {
        stdinTempFile.deleteSync();
      } catch (_) {}
      try {
        File('${stdinTempFile.path}.bat').deleteSync();
      } catch (_) {}
    }
  }
}

// =========================================================================
// Gemini API — direct HTTP provider (no CLI, no Node.js)
//
// Uses the same Cloud Code API and OAuth credentials as the official
// Gemini CLI (@google/gemini-cli). The client ID and secret below are
// the same public values embedded in the CLI's npm bundle — they are not
// application secrets (Google's OAuth for native/desktop apps treats
// client_secret as non-confidential, per RFC 8252 §8.5).
// =========================================================================

const _geminiApiEndpoint = 'https://cloudcode-pa.googleapis.com/v1internal';
const _geminiApiClientId =
    '681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com';
const _geminiApiClientSecret = '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';

// Shared HTTP client for all Gemini API calls. Short idle timeout
// prevents stale keep-alive connections — the server may close its
// end before Dart's default 15s timeout, causing "Connection closed
// before full header was received" on the next reuse attempt.
final HttpClient _geminiApiHttpClient = HttpClient()
  ..idleTimeout = const Duration(seconds: 5);

// Cached state for the Gemini API session.
String? _geminiApiAccessToken;
DateTime? _geminiApiTokenExpiry;
String? _geminiApiProjectId;

const _geminiApiPreviewProModel = 'gemini-3-pro-preview';
const _geminiApiPreviewFlashModel = 'gemini-3-flash-preview';
const _geminiApiPreview31ProModel = 'gemini-3.1-pro-preview';
const _geminiApiPreview31FlashLiteModel = 'gemini-3.1-flash-lite-preview';
const _geminiApiStableProModel = 'gemini-2.5-pro';

/// Map local Gemini aliases to concrete model ids accepted by the Code Assist
/// API. The official Gemini CLI supports auto/pro/flash aliases client-side;
/// this endpoint expects concrete model ids.
String _geminiApiModelName(String alias) {
  switch (alias.trim().toLowerCase()) {
    case 'pro':
      return _geminiApiPreviewProModel;
    case 'flash':
      return _geminiApiPreviewFlashModel;
    case 'flash-lite':
      return _geminiApiPreview31FlashLiteModel;
    case 'auto':
    case 'auto-gemini-3':
      return _geminiApiPreviewProModel;
    case 'auto-gemini-2.5':
      return _geminiApiStableProModel;
    case 'gemini-3.1-pro-preview-customtools':
      // The public Gemini CLI may surface this internal variant, but the
      // Code Assist endpoint this app calls accepts the plain 3.1 pro preview
      // model id instead.
      return _geminiApiPreview31ProModel;
    default:
      // Already a full model name (e.g. 'gemini-3-pro-preview').
      return alias;
  }
}

/// Read the refresh token from ~/.gemini/oauth_creds.json.
String? _geminiApiRefreshToken() {
  final homeDir = _userHomeDir();
  if (homeDir == null) return null;
  final raw = _readJsonFile(p.join(homeDir, '.gemini', 'oauth_creds.json'));
  if (raw is! Map<String, dynamic>) return null;
  final token = raw['refresh_token'];
  return (token is String && token.isNotEmpty) ? token : null;
}

/// Ensure we have a valid access token, refreshing if needed.
Future<String?> _geminiApiEnsureToken() async {
  if (_geminiApiAccessToken != null &&
      _geminiApiTokenExpiry != null &&
      DateTime.now().isBefore(
          _geminiApiTokenExpiry!.subtract(const Duration(seconds: 30)))) {
    return _geminiApiAccessToken;
  }

  final refreshToken = _geminiApiRefreshToken();
  if (refreshToken == null) return null;

  try {
    final request = await _geminiApiHttpClient.postUrl(
      Uri.parse('https://oauth2.googleapis.com/token'),
    );
    request.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded');
    request.write(
      'client_id=${Uri.encodeComponent(_geminiApiClientId)}'
      '&client_secret=${Uri.encodeComponent(_geminiApiClientSecret)}'
      '&refresh_token=${Uri.encodeComponent(refreshToken)}'
      '&grant_type=refresh_token',
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) return null;
    final json = jsonDecode(body);
    if (json is! Map || json['access_token'] is! String) return null;

    _geminiApiAccessToken = json['access_token'] as String;
    final expiresIn =
        json['expires_in'] is int ? json['expires_in'] as int : 3599;
    _geminiApiTokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
    return _geminiApiAccessToken;
  } catch (_) {
    return null;
  }
}

/// Get the project ID from the Gemini Code Assist API (cached).
Future<String?> _geminiApiEnsureProject() async {
  if (_geminiApiProjectId != null) return _geminiApiProjectId;

  final token = await _geminiApiEnsureToken();
  if (token == null) return null;

  try {
    final request = await _geminiApiHttpClient.postUrl(
      Uri.parse('$_geminiApiEndpoint:loadCodeAssist'),
    );
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'metadata': {
        'ideType': 'IDE_UNSPECIFIED',
        'platform': 'PLATFORM_UNSPECIFIED',
        'pluginType': 'GEMINI',
      },
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) return null;
    final json = jsonDecode(body);
    if (json is! Map) return null;

    _geminiApiProjectId = json['cloudaicompanionProject'] as String?;
    return _geminiApiProjectId;
  } catch (_) {
    return null;
  }
}

/// Call the Gemini Code Assist generateContent API directly.
/// Returns the model's text response, or null on failure.
Future<({String? text, String? error, int inputTokens, int outputTokens})>
    _runGeminiApiRequest(String prompt, String modelAlias,
        {int? maxTokens}) async {
  final token = await _geminiApiEnsureToken();
  if (token == null) {
    return (
      text: null,
      error: 'Gemini API token refresh failed.',
      inputTokens: 0,
      outputTokens: 0
    );
  }

  final project = await _geminiApiEnsureProject();
  if (project == null) {
    return (
      text: null,
      error: 'Gemini API project setup failed.',
      inputTokens: 0,
      outputTokens: 0
    );
  }

  final model = _geminiApiModelName(modelAlias);

  final payload = jsonEncode({
    'model': model,
    'project': project,
    'user_prompt_id': 'desktop-${DateTime.now().millisecondsSinceEpoch}',
    'request': {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.3,
        if (maxTokens != null) 'maxOutputTokens': maxTokens,
      },
    },
  });

  // Retry twice on transient connection errors. Dart's HttpClient
  // can reuse a connection the server already closed, producing
  // "Connection closed before full header was received." Also
  // catches SocketException for network blips.
  HttpClientResponse? response;
  String? body;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final request = await _geminiApiHttpClient.postUrl(
        Uri.parse('$_geminiApiEndpoint:generateContent'),
      );
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.persistentConnection = false;
      request.write(payload);
      response = await request.close();
      body = await response.transform(utf8.decoder).join();
      break;
    } on HttpException {
      if (attempt == 2) rethrow;
      await Future<void>.delayed(
          Duration(milliseconds: 300 * (attempt + 1)));
    } on SocketException {
      if (attempt == 2) rethrow;
      await Future<void>.delayed(
          Duration(milliseconds: 300 * (attempt + 1)));
    }
  }

  try {
    if (response == null || body == null) {
      return (
        text: null,
        error: 'Gemini API connection failed.',
        inputTokens: 0,
        outputTokens: 0
      );
    }

    if (response.statusCode != 200) {
      // Try to extract a meaningful error message.
      try {
        final errJson = jsonDecode(body);
        final message =
            errJson['error']?['message'] ?? 'HTTP ${response.statusCode}';
        return (
          text: null,
          error: 'Gemini API: $message',
          inputTokens: 0,
          outputTokens: 0
        );
      } catch (_) {
        return (
          text: null,
          error: 'Gemini API error: HTTP ${response.statusCode}',
          inputTokens: 0,
          outputTokens: 0
        );
      }
    }

    final json = jsonDecode(body);
    if (json is! Map) {
      return (
        text: null,
        error: 'Gemini API returned invalid JSON.',
        inputTokens: 0,
        outputTokens: 0
      );
    }

    // Extract text from response.candidates[0].content.parts[0].text
    final candidates = (json['response'] as Map?)?['candidates'] as List?;
    final text = (candidates?.firstOrNull as Map?)?['content']?['parts']
            ?.firstWhere((p) => p['text'] != null, orElse: () => null)?['text']
        as String?;

    final usage = (json['response'] as Map?)?['usageMetadata'] as Map?;
    final inputTokens = (usage?['promptTokenCount'] as int?) ?? 0;
    final outputTokens = (usage?['candidatesTokenCount'] as int?) ?? 0;

    if (text == null || text.trim().isEmpty) {
      return (
        text: null,
        error: 'Gemini API returned no content.',
        inputTokens: inputTokens,
        outputTokens: outputTokens
      );
    }

    return (
      text: text,
      error: null,
      inputTokens: inputTokens,
      outputTokens: outputTokens
    );
  } catch (e) {
    return (
      text: null,
      error: 'Gemini API request failed: $e',
      inputTokens: 0,
      outputTokens: 0
    );
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

        // Some packages (current Claude Code) ship a native .exe and
        // the .cmd just forwards to it — no Node.js involved. Running
        // node over a native binary fails ("SyntaxError: Invalid or
        // unexpected token" or similar); invoke the .exe directly.
        if (scriptPath.toLowerCase().endsWith('.exe')) {
          return _ProcessInvocation(command: scriptPath, args: args);
        }

        // Some npm packages (e.g. opencode) ship a Node.js launcher that
        // spawnSync's a platform-native binary. Dart's pipes are incompatible
        // with libuv's stdio inheritance (UV_UNKNOWN on Windows), so try to
        // find and invoke the native binary directly — no Node.js involved.
        final nativeBinary = _tryResolveNativeBinary(scriptPath);
        if (nativeBinary != null) {
          return _ProcessInvocation(command: nativeBinary, args: args);
        }

        // Pure Node.js CLI (gemini, codex, older claude) — run node
        // directly with an expanded heap limit. AI tools regularly
        // exceed V8's default ~4 GB ceiling when processing large
        // diffs. Preserve any node flags from the .cmd wrapper.
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
    final scriptPath =
        rawScript.toLowerCase().startsWith(dp0Token.toLowerCase())
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
    case _ProviderKind.geminiApi:
      return _geminiAuthStatus();
    case _ProviderKind.openCode:
      return _openCodeAuthStatus();
    case _ProviderKind.apiProvider:
      // API providers are checked in _inspectProvider before this is
      // reached. Fail closed if a future path bypasses that.
      return const _ProviderAuthStatus(
        ok: false,
        detail: 'api provider auth requires provider id',
      );
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
  final hasToken = [idToken, accessToken].any(
    (token) => token != null && token.trim().isNotEmpty,
  );

  // The JWT plan claim is stale across plan changes — use the
  // models_cache instead, which is API-fresh. The count of
  // available models is concrete and always current.
  int? modelCount;
  try {
    final home = _userHomeDir();
    if (home != null) {
      final cache =
          _readJsonFile(p.join(home, '.codex', 'models_cache.json'));
      final models = cache?['models'];
      if (models is List) {
        modelCount = models
            .where((m) =>
                m is Map &&
                (m['visibility'] == null || m['visibility'] == 'list'))
            .length;
      }
    }
  } catch (_) {}

  final planName =
      modelCount != null ? '$modelCount model${modelCount == 1 ? '' : 's'}' : null;

  return _ProviderAuthStatus(
    ok: hasToken,
    detail: hasToken
        ? planName != null
            ? 'codex auth ok ($planName)'
            : 'codex auth ok'
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
  final Map<String, (double?, double?)> modelPricing;
  final Set<String> reasoningModels;
  final Set<String> fastModels;
  const _ProviderModelDiscovery({
    required this.models,
    required this.modelDetails,
    this.modelPricing = const {},
    this.reasoningModels = const {},
    this.fastModels = const {},
  });
}

class _ProviderModelCollection {
  final String providerId;
  final _ProviderKind kind;
  final String? planName;
  final List<String> models;
  final Map<String, String> modelDetails;
  final Map<String, (double?, double?)> modelPricing;
  final Set<String> reasoningModels;
  final Set<String> fastModels;

  const _ProviderModelCollection({
    required this.providerId,
    required this.kind,
    required this.planName,
    required this.models,
    required this.modelDetails,
    this.modelPricing = const {},
    this.reasoningModels = const {},
    this.fastModels = const {},
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
  final AiApiProvider? apiProvider;
  const _ProviderSpec({
    required this.id,
    required this.binary,
    required this.kind,
    this.apiProvider,
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
  final int inputTokens;
  final int outputTokens;

  const _ProviderPromptResult({
    required this.ok,
    this.output,
    this.error,
    required this.outputPreview,
    this.inputTokens = 0,
    this.outputTokens = 0,
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
  final LogosEmissionRecord? logosEmissionRecord;

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
    this.logosEmissionRecord,
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
  final String commitDraft;
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
    this.commitDraft = '',
    required this.statusSummary,
    required this.statSummary,
    required this.diffSummary,
    required this.passMode,
    this.priorReview,
  });
}

class _DiffPromptBundle {
  final String promptBody;
  final int originalDiffCharacters;

  const _DiffPromptBundle({
    required this.promptBody,
    required this.originalDiffCharacters,
  });
}

class _ParsedReviewResult {
  final String verdict;
  final int score;
  final String summary;
  final String reasoningReport;
  final List<AiCommitReviewFindingData> findings;
  final List<AiCommitReviewObservationData> observations;

  const _ParsedReviewResult({
    required this.verdict,
    required this.score,
    required this.summary,
    required this.reasoningReport,
    required this.findings,
    this.observations = const [],
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

enum _ProviderKind { codex, claude, geminiApi, openCode, apiProvider }

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
  final String wakeFrame;
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
    required this.wakeFrame,
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
