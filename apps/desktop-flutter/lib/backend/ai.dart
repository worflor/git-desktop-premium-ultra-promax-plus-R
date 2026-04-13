import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'ai_audit_store.dart';
import '../diagnostics/diagnostics_state.dart';
import 'commit_format.dart';
import 'dtos.dart';
import 'engram_fit.dart';
import 'file_coupling.dart' show logCommitSeparator;
import 'git.dart';
import 'git_result.dart';
import 'logos_git.dart';
import 'logos_git_calibration.dart';
import 'logos_git_diagnostics.dart';
import 'logos_git_probe.dart';
import 'logos_git_resolver.dart';
import 'logos_chunks.dart' as chunks;
import 'logos_hunks.dart' as hunks;

const _providerSpecs = <_ProviderSpec>[
  _ProviderSpec(id: 'codex', binary: 'codex', kind: _ProviderKind.codex),
  _ProviderSpec(id: 'claude', binary: 'claude', kind: _ProviderKind.claude),
  _ProviderSpec(id: 'gemini', binary: '', kind: _ProviderKind.geminiApi),
  _ProviderSpec(
    id: 'opencode',
    binary: 'opencode',
    kind: _ProviderKind.openCode,
  ),
];

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
const _providerRuntimeTimeout = Duration(seconds: 180);
const _gitCommandTimeout = Duration(seconds: 30);
const _modelDiscoveryTimeout = Duration(seconds: 8);
const _openCodeVerboseDiscoveryTimeout = Duration(seconds: 15);
const _claudeModelDiscoveryTimeout = Duration(seconds: 12);
const _maxFullDiffChars = 220000;
const _maxCondensedDiffChars = 180000;
const _maxPromptChars = 260000;

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
final _observationTagRegex = RegExp(
  r'<observation\b([^>]*)>([\s\S]*?)</observation>',
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
  // Commit format preferences. Caller (the commit composer) threads
  // these from PreferencesState; the prompt builder turns them into
  // inline instructions so the AI's output respects the user's chosen
  // structure/voice/coverage.
  CommitStructure structure = kDefaultCommitStructure,
  CommitVoice voice = kDefaultCommitVoice,
  CommitCoverage coverage = kDefaultCommitCoverage,
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

    // --- API providers: direct HTTP, no CLI ---
    if (provider.kind == _ProviderKind.geminiApi) {
      final geminiModel = modelId.startsWith('gemini ')
          ? modelId.substring('gemini '.length)
          : modelId;
      final apiResult = await _runGeminiApiRequest(prompt, geminiModel);
      if (apiResult.text == null) {
        return GitResult.err(
            apiResult.error ?? 'Gemini API returned no response.');
      }
      final message = _normalizeCommitMessage(apiResult.text!);
      if (message.isEmpty) {
        return GitResult.err('Gemini API returned an empty commit message.');
      }
      return GitResult.ok(
        AiCommitMessageData(
          providerId: provider.id,
          modelId: modelId,
          message: message,
          scopeLabel: scopeLabel,
          promptCharacters: prompt.length,
          diffCharacters: bundle.diffBundle.originalDiffCharacters,
        ),
      );
    }

    // --- CLI providers: process spawning ---
    final attempts = _buildProviderAttempts(provider.kind, modelId,
        readOnly: readOnly, resolvedCommand: availability.resolution!.command);
    String? providerOutput;
    String? lastError;
    for (final attempt in attempts) {
      final effectiveArgs =
          attempt.useStdinForPrompt ? attempt.args : [...attempt.args, prompt];
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
        promptCharacters: prompt.length,
        diffCharacters: bundle.diffBundle.originalDiffCharacters,
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
///
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

    // --- API providers: direct HTTP ---
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
      ));
    }

    // --- CLI providers: same attempt-fallback loop as generateCommitMessage ---
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
///
/// This is an HONEST-EFFORT scan — regexes are bypassable by
/// obfuscation and it only knows common token shapes. But the normal
/// failure mode (dev has `sk-abc123…` hardcoded in a .env that's
/// somehow tracked) is exactly what regexes catch.
String? detectLikelySecretInPrompt(String prompt) {
  final patterns = <(RegExp, String)>[
    (RegExp(r'AKIA[0-9A-Z]{16}'), 'AWS access key ID'),
    (RegExp(r'AIza[0-9A-Za-z_\-]{35}'), 'Google API key'),
    (RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}'), 'GitHub token'),
    (RegExp(r'sk-(?:ant-)?[A-Za-z0-9_\-]{20,}'),
        'OpenAI/Anthropic secret key'),
    (RegExp(r'xox[baprs]-[A-Za-z0-9\-]{10,}'), 'Slack token'),
    (RegExp(
          r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'),
        'JWT'),
    // Private-key block header.
    (RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
        'private key block'),
  ];
  for (final (re, label) in patterns) {
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
  if (start <= 0) return text;
  return lines.sublist(start).join('\n').trim();
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
  String commitDraft = '',
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

    // Feed cited paths from the review back into the SSE calibration
    // store. Closes the Logos self-learning loop: axes that surfaced
    // useful context get reinforced per-regime, per-repo. Fire-and-
    // forget — review results are returned regardless.
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
        modelCategoryLabel: modelCategoryLabel,
        guardrailStage: guardrailStage,
        scopeLabel: scopeLabel,
        promptCharacters: draftPrompt.length + verifyPrompt.length,
        diffCharacters: bundle.diffBundle.originalDiffCharacters,
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
    case _ProviderKind.geminiApi:
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
  final models = <String>{
    'gemini auto',
    'gemini pro',
    'gemini flash',
    'gemini flash-lite'
  };

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

  final fullDiff = _joinDiffSections(
    stagedDiff: stagedDiff.data ?? '',
    unstagedDiff: unstagedDiff.data ?? '',
    untrackedDiff: untrackedDiff,
  );
  if (fullDiff.trim().isEmpty) {
    return _CommitDiffContextResult.err(
      'No diff content is available for $scopeLabel.',
    );
  }

  final diffBundle = await _buildDiffPromptBundle(
    fullDiff,
    repositoryPath: repositoryPath,
  );

  // ── Parallel context enrichment ──────────────────────────────────────
  // Five anti-hallucination layers gathered simultaneously. Budget adapts
  // to the diff size — small diffs get rich context, large diffs get the
  // essentials. The split shifts based on file count: few files means
  // more budget for full source; many files means more for metadata.
  final changedFileCount = RegExp(r'^diff --git ', multiLine: true)
      .allMatches(fullDiff)
      .length
      .clamp(1, 999);

  // Estimate overhead from the parts of the prompt that aren't diff or
  // context: system instructions, evidence rules, schema, summaries.
  // Measured from actual prompt builds — typically 8-14K depending on
  // guardrail profile and custom prompt length.
  // System instructions + evidence rules + XML schema + summaries +
  // user custom prompt. Measured from actual prompt builds.
  const estimatedOverhead = 12000;
  final contextBudget =
      _maxPromptChars - diffBundle.promptBody.length - estimatedOverhead;

  // Adaptive split: file context is most valuable, but with 50+ files
  // the metadata summary becomes more important than trying to include
  // all source. The ratio slides smoothly between the extremes.
  //
  // A sixth slice — relevance neighborhood (Logos-inspired diffusion) —
  // surfaces files NOT in the diff but strongly coupled to it. Budget
  // ~20% of context; cut from file-context since these usually overlap
  // the same semantic space (callers, historical co-changers).
  final metadataWeight = (changedFileCount / 100).clamp(0.1, 0.3);
  const relevanceWeight = 0.20;
  final fileContextWeight =
      1.0 - metadataWeight - relevanceWeight - 0.1; // 10% headroom

  // Kick off the relevance future separately so its richer return type
  // (text + emission record) doesn't widen the Future.wait list to
  // List<Object>. Both futures still run in parallel.
  final relevanceFuture = _collectRelevanceNeighborhood(
    repositoryPath: repositoryPath,
    diffText: fullDiff,
    budgetChars: (contextBudget * relevanceWeight).round(),
  );
  final contextFutures = await Future.wait([
    _collectFileContext(
      repositoryPath: repositoryPath,
      diffText: fullDiff,
      budgetChars: (contextBudget * fileContextWeight).round(),
    ),
    _collectFileMetadata(
      repositoryPath: repositoryPath,
      diffText: fullDiff,
      budgetChars: (contextBudget * metadataWeight).round(),
    ),
    _collectChangeTypes(
      repositoryPath: repositoryPath,
      scopeArgs: scopeArgs,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
    ),
    _collectStructuralVerification(
      repositoryPath: repositoryPath,
      diffText: fullDiff,
    ),
  ]);
  final fileContext = contextFutures[0];
  final fileMetadata = contextFutures[1];
  final changeTypes = contextFutures[2];
  final structuralVerification = contextFutures[3];
  final relevance = await relevanceFuture;
  final relevanceNeighborhood = relevance.text;
  final logosEmissionRecord = relevance.record;

  // Append enrichment sections to the diff bundle.
  final enrichedParts = <String>[diffBundle.promptBody];
  if (changeTypes.isNotEmpty) {
    enrichedParts.add('<change_types>\n$changeTypes</change_types>');
  }
  if (structuralVerification.isNotEmpty) {
    enrichedParts.add(
        '<structural_verification>\n$structuralVerification</structural_verification>');
  }
  if (fileMetadata.isNotEmpty) {
    enrichedParts.add('<file_metadata>\n$fileMetadata</file_metadata>');
  }
  if (fileContext.isNotEmpty) {
    enrichedParts.add('<file_context>\n$fileContext</file_context>');
  }
  if (relevanceNeighborhood.isNotEmpty) {
    enrichedParts.add(
      '<relevance_neighborhood>\n$relevanceNeighborhood</relevance_neighborhood>',
    );
  }
  final enrichedPromptBody = enrichedParts.join('\n\n');

  final enrichedBundle = _DiffPromptBundle(
    promptBody: enrichedPromptBody,
    originalDiffCharacters: diffBundle.originalDiffCharacters,
  );

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
    _runGitCommand(
        repositoryPath, ['log', '--max-parents=0', '--format=%cr', 'HEAD']),
    _runGitCommand(repositoryPath, ['log', '--format=%an', '-50']),
  ]);

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
      branchName: (branch.data ?? 'HEAD').trim(),
      statusSummary: (status.data ?? '').trim(),
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
///
/// `git diff` and `git diff --cached` never show untracked files, but new
/// files are exactly the kind of thing an AI reviewer needs to see (or
/// it'll hallucinate that they don't exist). We read each file's content
/// and emit a synthetic `/dev/null → b/<path>` diff block so the reviewer
/// gets the full new file content as added lines.
///
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

  final pathPattern = RegExp(r'^diff --git a/.+ b/(.+)$', multiLine: true);
  final paths =
      pathPattern.allMatches(diffText).map((m) => m.group(1)!).toSet();
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

// ── Anti-hallucination: change type classification ──────────────────
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
  } catch (_) {
    return '';
  }
}

// ── Anti-hallucination: structural verification ─────────────────────
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
  } catch (_) {
    return '';
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
  final fileHeaderPattern = RegExp(r'^diff --git a/.+ b/(.+)$');

  final seen = <String>{};
  final results = StringBuffer();
  String? currentFile;

  for (final line in diffText.split('\n')) {
    // Track which file we're in so relative imports resolve correctly.
    final headerMatch = fileHeaderPattern.firstMatch(line);
    if (headerMatch != null) {
      currentFile = headerMatch.group(1);
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
///
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
  final pathPattern = RegExp(r'^diff --git a/.+ b/(.+)$', multiLine: true);
  final paths =
      pathPattern.allMatches(diffText).map((m) => m.group(1)!).toSet();
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
  try {
    final engine = await resolveLogosGit(repositoryPath);
    if (engine != null) {
      // Self-φ via heat-kernel: how much heat each source file retains
      // after t=1.0 diffusion. Files coupled to a strong neighborhood
      // bleed less; isolated files bleed most. Highest-retention files
      // are the most "anchored" parts of the change.
      final sourceWeights = {for (final p in pathList) p: 1.0};
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
    } else {
      // No engine available (early profile build, empty repo). Fall
      // back to alphabetical — better than randomized iteration order.
      orderedPaths = [...pathList]..sort();
    }
  } catch (_) {
    orderedPaths = [...pathList]..sort();
  }

  final buffer = StringBuffer();
  var remaining = budgetChars;
  for (final filePath in orderedPaths) {
    if (remaining <= 0) break;
    try {
      final file = File(p.join(repositoryPath, filePath));
      if (!await file.exists()) continue;
      final content = await file.readAsString();
      final lineCount = '\n'.allMatches(content).length + 1;
      final block = '--- $filePath ($lineCount lines) ---\n$content\n';
      if (block.length <= remaining) {
        buffer.write(block);
        remaining -= block.length;
        continue;
      }
      // Over-budget at full size — try the chunk-pack fallback. Build
      // touched line ranges from the diff so the chunk diffusion knows
      // where the heat source is.
      final touched = chunks.touchedRangesFromDiff(
        filePath: filePath,
        diffText: diffText,
      );
      final pack = chunks.packRelevantChunks(
        filePath: filePath,
        content: content,
        touchedRanges: touched,
        budgetChars: remaining,
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
///
/// Uses the Logos-inspired git engine ([LogosGit]). The diff's touched
/// paths become a heat source ρ; relevance φ is the heat-kernel
/// diffusion φ = exp(-t·L_sym)·ρ at t=1.0 (commit-review scope).
///
/// Emission follows a greedy-density knapsack with three tiers:
///   FULL       — full source; chunk-pack fallback if oversized
///   SIGNATURE  — outline (same format as [_buildFileOutline])
///   BREADCRUMB — one-liner with path + score + dominant axis
///
/// Budget-bounded. Returns an empty string on any error — this is a
/// best-effort enrichment layer; failures never poison the primary
/// context path.
/// Returns the prompt section *and* the emission record for this call,
/// so the caller can feed citations back to SSE without relying on
/// process-level globals (which would race across overlapping reviews).
Future<({String text, LogosEmissionRecord? record})>
    _collectRelevanceNeighborhood({
  required String repositoryPath,
  required String diffText,
  required int budgetChars,
  double temperature = 1.0,
}) async {
  if (budgetChars <= 500) return (text: '', record: null);
  try {
    // Resolve or build the engine through the shared resolver so that
    // UI state class + this code path share one cache and one in-flight
    // build per (repo, HEAD).
    final engine = await resolveLogosGit(repositoryPath);
    if (engine == null) return (text: '', record: null);

    // Construct the full probe: primary diff paths + M-axis pickaxe
    // enrichment (files containing added/removed identifiers) + Ab-axis
    // path mirrors (test/source pairs). Temperature adapts to the
    // diff's own coherence — see [LogosGitProbeBuilder.adaptiveTemperature].
    final probe = await buildDiffProbe(
      repoPath: repositoryPath,
      diffText: diffText,
      engine: engine,
    );
    if (probe.sourceWeights.isEmpty) return (text: '', record: null);

    // Base temperature: caller override, else the probe's coherence-
    // adaptive suggestion. Then scale by the branch orbit: converging
    // chains get a cooler diffusion (trust the core), diverging chains
    // get a hotter one (reach wider to surface the sprawl's tails).
    // Neutral when the orbit has no signal, so behaviour is backward-
    // compatible on short / insufficient histories.
    final orbit = await _probeBranchOrbit(repositoryPath);
    final baseT = temperature == 1.0
        ? probe.suggestedTemperature ?? 1.0
        : temperature;
    final resolvedT = baseT * _temperatureMultiplierFromOrbit(orbit);

    // Diffuse. Heat-kernel linearity means weighted-source diffusion
    // equals the weighted sum of single-source diffusions.
    final diffuseStart = Stopwatch()..start();
    final scores = diffuseFromProbe(
      engine: engine,
      probe: probe,
      temperatureOverride: resolvedT,
    );
    LogosGitDiagnostics.instance.recordDiffuse(
      repoPath: repositoryPath,
      sourceCount: probe.sourceWeights.length,
      duration: diffuseStart.elapsed,
      temperature: resolvedT,
    );
    if (scores.isEmpty) return (text: '', record: null);

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
    final axisByPath = <String, LogosAxis>{
      for (final item in plan) item.path: _classifyAxis(item.path, probe),
    };
    final emissionRecord = LogosEmissionRecord(
      regime: regime,
      axisByPath: axisByPath,
    );
    // Fire-and-forget emission tally — failure doesn't fail the review.
    // ignore: unawaited_futures
    LogosSseStore(repositoryPath).recordEmissions(emissionRecord);

    final buffer = StringBuffer();
    buffer.writeln(
      '(diff=${probe.stats.primaryCount} file${probe.stats.primaryCount == 1 ? '' : 's'}'
      ', M-axis=${probe.stats.mMatches} file${probe.stats.mMatches == 1 ? '' : 's'}'
      ' via ${probe.stats.mSymbols} symbol${probe.stats.mSymbols == 1 ? '' : 's'}'
      ', Ab-axis=${probe.stats.abMatches} mirror${probe.stats.abMatches == 1 ? '' : 's'}'
      ', coherence=${probe.stats.coherence.toStringAsFixed(2)}'
      ', regime=${regime.name}'
      ', t=${resolvedT.toStringAsFixed(2)}'
      '; ${plan.length} neighbors surfaced)',
    );
    var remaining = budgetChars - buffer.length;

    for (final item in plan) {
      if (remaining <= 120) break;
      final header =
          '--- ${item.path}  φ=${item.phi.toStringAsFixed(3)}  tier=${_tierName(item.tier)} ---';
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
        final lineCount = '\n'.allMatches(content).length + 1;
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
          final pack = chunks.packRelevantChunks(
            filePath: item.path,
            content: content,
            touchedRanges: const [],
            budgetChars: remaining,
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

/// Which observable put `path` on the emission list. Primary if it's
/// in the diff, M if pickaxe pulled it in, Ab if a path-mirror did.
/// Anything left is graph-diffusion surfaced (CC/SP/V/F0 collectively).
LogosAxis _classifyAxis(String path, DiffProbe probe) {
  if (probe.primaryPaths.contains(path)) return LogosAxis.primary;
  // The probe's sourceWeights map tracks explicit (M, Ab) additions.
  // We can't tell M from Ab just by path membership after-the-fact, so
  // we heuristic: if the path *looks* like a test-mirror of a primary
  // path, call it Ab; otherwise M.
  if (probe.sourceWeights.containsKey(path)) {
    final looksMirror = _pathLooksLikeMirrorOf(path, probe.primaryPaths);
    return looksMirror ? LogosAxis.ab : LogosAxis.m;
  }
  return LogosAxis.graph;
}

bool _pathLooksLikeMirrorOf(String candidate, Set<String> primary) {
  // Mirror = candidate is a test-ish path AND its basename-stem matches
  // some primary path's stem. Test-path detection routes through the
  // same classifier the probe uses so axis tags stay consistent across
  // the probe builder and this downstream citation path.
  if (!looksLikeTestPath(candidate)) return false;
  final candBase = p.basenameWithoutExtension(candidate)
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
///
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
Future<BranchOrbit?> _probeBranchOrbit(String repositoryPath) async {
  try {
    final logResult = await runGitProbe(repositoryPath, [
      'log',
      '-n', '30',
      '--no-merges',
      '--name-only',
      '--format=$logCommitSeparator%H',
    ]);
    if (logResult.exitCode != 0) return null;
    final raw = logResult.stdout.toString();
    final commitSets = <Set<String>>[];
    Set<String>? current;
    for (final line in const LineSplitter().convert(raw)) {
      if (line.startsWith(logCommitSeparator)) {
        if (current != null && current.isNotEmpty) {
          commitSets.add(current);
        }
        current = <String>{};
        continue;
      }
      final trimmed = line.trim();
      if (trimmed.isEmpty || current == null) continue;
      current.add(trimmed.replaceAll('\\', '/'));
    }
    if (current != null && current.isNotEmpty) commitSets.add(current);
    // git log returns newest-first; branch-orbit expects oldest→tip.
    return computeBranchOrbit(commitSets.reversed.toList());
  } catch (_) {
    return null;
  }
}

/// Map a branch orbit to a diffusion-temperature multiplier. A
/// converging branch — scope narrowing toward the tip — benefits
/// from a *cooler* diffusion that trusts the core touched files and
/// doesn't reach far afield. A diverging branch, scope sprawling,
/// benefits from the opposite: a hotter diffusion that casts a
/// wider net to catch the sprawl's real boundaries. Steady /
/// null / insufficient orbits get neutral (×1.0).
///
/// Values derived from the orbit's own semantics, not tuned:
///   converging → 1 − trendSlope magnitude → cooler (min 0.75)
///   diverging  → 1 + trendSlope magnitude → hotter (max 1.25)
double _temperatureMultiplierFromOrbit(BranchOrbit? orbit) {
  if (orbit == null || !orbit.hasSignal) return 1.0;
  // trendSlope magnitude bounds the departure from neutral. The
  // fit's slope already sits in a small range (empirically ≪ 0.2
  // for real repos), so we clamp to a narrow band that can't
  // overwhelm the adaptive-from-coherence temperature.
  final mag = orbit.trendSlope.abs().clamp(0.0, 0.25);
  if (orbit.isConverging) return (1.0 - mag).clamp(0.75, 1.0);
  if (orbit.isDiverging) return (1.0 + mag).clamp(1.0, 1.25);
  return 1.0;
}

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
    final axisLabels = <String, String>{
      for (final entry in probe.sourceWeights.entries)
        entry.key: _classifyAxis(entry.key, probe).name,
    };
    final attr = engine.diffuseWithAttribution(
      weightsByPath: probe.sourceWeights,
      axisLabelByPath: axisLabels,
      t: t,
      excludePaths: probe.primaryPaths,
    );

    List<RelevanceScore> missing;
    Map<String, double> axisShares = const {};
    Map<String, String> dominantByPath = const {};
    if (attr != null) {
      missing = attr.combined.take(5).toList();
      axisShares = attr.axisMassFractions();
      dominantByPath = {
        for (final s in missing)
          if (attr.dominantAxis[s.path] != null)
            s.path: attr.dominantAxis[s.path]!,
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
    // Shared probe — see [_probeBranchOrbit]. Result also gets reused
    // by `_collectRelevanceNeighborhood` to tune diffusion temperature.
    final orbit = await _probeBranchOrbit(repositoryPath);
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
      buf.writeln('  - ${entry.key}: ${(entry.value * 100).toStringAsFixed(0)}%');
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
      final axisTag = axis != null ? '  via=$axis' : '';
      buf.writeln('  - ${m.path} (φ=${m.phi.toStringAsFixed(3)}$axisTag)');
    }
  }
  buf.writeln('</logos_shape>');
  return buf.toString();
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
}) async {
  if (fullDiff.length <= _maxFullDiffChars) {
    return _DiffPromptBundle(
      promptBody: '<full_diff>\n$fullDiff\n</full_diff>',
      originalDiffCharacters: fullDiff.length,
    );
  }

  // Overflow path — hand off to logos hunk diffusion. Every hunk is a
  // node; edges via shared identifiers, parent-file coupling (factored
  // through LogosGit's file-φ), within-file proximity, add/delete
  // balance. Hunks ranked by heat-kernel φ; greedy-packed at full
  // content until the diff budget exhausts. Peripheral mass-edit hunks
  // drop off first; structurally-central hunks stay. Scales to
  // arbitrary hunk count.
  final parsed = hunks.parseDiffHunks(fullDiff);
  if (parsed.isEmpty) {
    // Malformed diff or nothing to rank — emit the head of the diff
    // truncated at the full-diff cap. Honest fallback.
    final truncated = fullDiff.substring(
      0,
      math.min(_maxFullDiffChars, fullDiff.length),
    );
    return _DiffPromptBundle(
      promptBody: '<full_diff_truncated>\n$truncated\n</full_diff_truncated>',
      originalDiffCharacters: fullDiff.length,
    );
  }

  LogosGit? engine;
  try {
    engine = await resolveLogosGit(repositoryPath);
  } catch (_) {
    engine = null;
  }

  final ranking = hunks.rankHunksByPhi(hunks: parsed, logosEngine: engine);
  final pack = hunks.packHunksUnderBudget(
    rankings: ranking.rankings,
    budgetChars: _maxCondensedDiffChars,
  );

  var promptBody = pack.body;
  if (promptBody.length > _maxPromptChars) {
    promptBody = promptBody.substring(0, _maxPromptChars);
  }
  return _DiffPromptBundle(
    promptBody: promptBody,
    originalDiffCharacters: fullDiff.length,
  );
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

  var payload = buffer.toString().trim();
  if (payload.length > _maxPromptChars) {
    payload = payload.substring(0, _maxPromptChars);
  }
  return payload;
}

// ── Commit-message format directives ────────────────────────────────────
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
    'Ground every finding in the provided evidence layers:\n'
    '  • <change_types> classifies each file as new/modified/deleted/renamed — '
    'trust it for file history context.\n'
    '  • <structural_verification> confirms import targets and symbol definitions '
    'against the live repo — trust it for existence questions.\n'
    '  • <file_metadata> provides authorship, churn, and test coverage — '
    'use it to calibrate risk and flag untested high-churn files.\n'
    '  • <file_context> provides full source of small changed files — '
    'use it to verify imports, function signatures, and surrounding code.\n'
    '  • <relevance_neighborhood> surfaces files NOT in the diff but strongly '
    'coupled to it — historical co-change, directory proximity, ownership '
    'overlap. Use it to spot hidden callers, broken invariants elsewhere, '
    'or missed update sites. Each neighbor is tagged with φ (relevance '
    'score) and tier (full / sig / bread).\n'
    'Only report findings you can cite concrete evidence for. '
    'Omit anything that requires guessing. '
    'When verification data confirms something, treat it as fact.',
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
    buffer.writeln('<commit_intent>');
    buffer.writeln(spec.commitDraft.trim());
    buffer.writeln('</commit_intent>');
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
}) async {
  // --- API providers: direct HTTP ---
  if (provider.kind == _ProviderKind.geminiApi) {
    final geminiModel = modelId.startsWith('gemini ')
        ? modelId.substring('gemini '.length)
        : modelId;
    final apiResult = await _runGeminiApiRequest(prompt, geminiModel);
    if (apiResult.text == null) {
      return _ProviderPromptResult(
        ok: false,
        error: apiResult.error ?? 'Gemini API returned no response.',
        outputPreview: apiResult.error ?? '',
      );
    }
    return _ProviderPromptResult(
      ok: true,
      output: apiResult.text,
      outputPreview: apiResult.text!.length > 200
          ? '${apiResult.text!.substring(0, 200)}...'
          : apiResult.text!,
    );
  }

  // --- CLI providers: process spawning ---
  final attempts = _buildProviderAttempts(provider.kind, modelId,
      readOnly: readOnly, resolvedCommand: resolution.command);
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
  final score = scoreDigits == null ? null : int.tryParse(scoreDigits.group(0)!);
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
    case _ProviderKind.geminiApi:
      // API provider — no CLI attempts. Handled via _runGeminiApiRequest.
      return [];
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
    case _ProviderKind.geminiApi:
      return const {}; // API provider — no process environment needed.
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
    case _ProviderKind.geminiApi:
      return lower.startsWith('gemini error:');
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
  s = s.replaceAll(
      RegExp(r'([Bb]earer\s+)[A-Za-z0-9._\-]+', multiLine: true), r'$1[redacted]');
  // Google API keys (AIza…, 39 chars)
  s = s.replaceAll(
      RegExp(r'AIza[0-9A-Za-z_\-]{35}'), '[redacted:google-api-key]');
  // GitHub personal access tokens, app tokens, etc.
  s = s.replaceAll(
      RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}'), '[redacted:gh-token]');
  // OpenAI / Anthropic / generic sk- tokens
  s = s.replaceAll(
      RegExp(r'sk-(?:ant-)?[A-Za-z0-9_\-]{20,}'), '[redacted:sk-token]');
  // AWS access keys
  s = s.replaceAll(RegExp(r'AKIA[0-9A-Z]{16}'), '[redacted:aws-akid]');
  // JWT-ish triplets (base64.base64.base64)
  s = s.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'),
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

// Shared HTTP client for all Gemini API calls (connection pooling).
final HttpClient _geminiApiHttpClient = HttpClient();

// Cached state for the Gemini API session.
String? _geminiApiAccessToken;
DateTime? _geminiApiTokenExpiry;
String? _geminiApiProjectId;

/// Map display aliases to actual API model names.
String _geminiApiModelName(String alias) {
  switch (alias.toLowerCase()) {
    case 'pro':
      return 'gemini-2.5-pro';
    case 'flash':
      return 'gemini-2.5-flash';
    case 'flash-lite':
      return 'gemini-2.5-flash-lite';
    case 'auto':
      return 'gemini-2.5-flash';
    default:
      // Already a full model name (e.g. 'gemini-2.5-pro').
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
    _runGeminiApiRequest(String prompt, String modelAlias) async {
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

  try {
    final request = await _geminiApiHttpClient.postUrl(
      Uri.parse('$_geminiApiEndpoint:generateContent'),
    );
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
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
        },
      },
    }));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

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
    case _ProviderKind.geminiApi:
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

enum _ProviderKind { codex, claude, geminiApi, openCode }

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
