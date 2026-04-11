import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostics_state.dart';
import 'dtos.dart';
import 'git.dart';

const _providerSpecs = <_ProviderSpec>[
  _ProviderSpec(id: 'codex', binary: 'codex', kind: _ProviderKind.codex),
  _ProviderSpec(id: 'claude', binary: 'claude', kind: _ProviderKind.claude),
  _ProviderSpec(id: 'gemini', binary: 'npx', kind: _ProviderKind.gemini),
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
const _providerModelDiscoveryCacheTtl = Duration(minutes: 5);
const _binaryHealthCheckTimeout = Duration(milliseconds: 1200);
const _openCodeBinaryHealthCheckTimeout = Duration(seconds: 5);
const _windowsScriptHealthCheckTimeout = Duration(seconds: 5);
const _providerRuntimeTimeout = Duration(seconds: 90);
const _gitCommandTimeout = Duration(seconds: 30);
const _modelDiscoveryTimeout = Duration(seconds: 8);
const _openCodeVerboseDiscoveryTimeout = Duration(seconds: 15);
const _maxFullDiffChars = 140000;
const _maxCondensedDiffChars = 110000;
const _maxPromptChars = 180000;

final Map<String, _TimedValue<_ProviderResolution?>> _providerResolutionCache =
    {};
final Map<String, _TimedValue<_ProviderAvailability>>
    _providerAvailabilityCache = {};
final Map<String, _TimedValue<_ProviderModelDiscovery?>>
    _providerModelDiscoveryCache = {};

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
    final readyProviders = <_ProviderModelCollection>[];
    for (final provider in _providerSpecs) {
      final availability = await _inspectProviderCached(
        provider,
        forceRefresh: forceRefresh,
      );
      if (!availability.ready) {
        continue;
      }

      final discovery = await _discoverProviderModelsCached(
        provider,
        availability.resolution,
        forceRefresh: forceRefresh,
      );
      if (discovery == null || discovery.models.isEmpty) {
        continue;
      }

      readyProviders.add(
        _ProviderModelCollection(
          providerId: provider.id,
          kind: provider.kind,
          planName: availability.auth.planName,
          models: discovery.models,
          modelDetails: discovery.modelDetails,
        ),
      );
    }

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
}) async {
  try {
    if (repositoryPath.trim().isEmpty) {
      return GitResult.err('Repository path is required.');
    }
    if (modelValue.trim().isEmpty || !modelValue.contains(':')) {
      return GitResult.err('Select a valid AI model before generating.');
    }
    if (!includeStaged && !includeUnstaged) {
      return GitResult.err('No diff scope is available for generation.');
    }

    final separator = modelValue.indexOf(':');
    final providerId = modelValue.substring(0, separator).trim();
    final modelId = modelValue.substring(separator + 1).trim();
    final provider =
        _providerSpecs.where((item) => item.id == providerId).firstOrNull;
    if (provider == null) {
      return GitResult.err('Unknown AI provider: $providerId');
    }
    if (modelId.isEmpty) {
      return GitResult.err('Selected model is missing a model id.');
    }

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
      statusSummary: bundle.statusSummary,
      statSummary: bundle.statSummary,
      diffSummary: bundle.diffBundle.promptBody,
    );

    final attempts = _buildProviderAttempts(provider.kind, modelId);
    String? providerOutput;
    String? lastError;
    for (final attempt in attempts) {
      final result = await _runObservedProcess(
        commandLabel: 'ai.${provider.id}.${attempt.name}',
        scope: 'ai',
        command: availability.resolution!.command,
        args: attempt.args,
        timeout: _providerRuntimeTimeout,
        workingDirectory: repositoryPath,
        stdinPayload: prompt,
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
          formatted.trim().isNotEmpty) {
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
  final resolution = await _resolveProviderCommand(provider.binary);
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
      return _discoverCodexModels();
    case _ProviderKind.claude:
      return _discoverClaudeModels();
    case _ProviderKind.gemini:
      return _discoverGeminiModels();
    case _ProviderKind.openCode:
      return _discoverOpenCodeModels(resolution);
  }
}

_ProviderModelDiscovery? _discoverCodexModels() {
  final configured = _discoverCodexConfigModel();
  if (configured == null) {
    return null;
  }
  return _ProviderModelDiscovery(
    models: [configured],
    modelDetails: const {},
  );
}

String? _discoverCodexConfigModel() {
  final configPath = _codexConfigPath();
  try {
    final payload = File(configPath).readAsStringSync();
    for (final line in payload.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[')) {
        break;
      }
      if (!trimmed.startsWith('model')) {
        continue;
      }
      final separator = trimmed.indexOf('=');
      if (separator == -1) {
        continue;
      }
      final value = trimmed
          .substring(separator + 1)
          .trim()
          .replaceAll('"', '')
          .replaceAll("'", '');
      if (value.isNotEmpty) {
        return value;
      }
    }
  } catch (_) {}
  return null;
}

_ProviderModelDiscovery? _discoverClaudeModels() {
  final configured = _discoverClaudeConfiguredModel();
  if (configured == null) {
    return null;
  }
  return _ProviderModelDiscovery(
    models: [configured],
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

_ProviderModelDiscovery? _discoverGeminiModels() {
  final configured = _discoverGeminiConfiguredModel();
  if (configured == null) {
    return null;
  }
  return _ProviderModelDiscovery(
    models: [configured],
    modelDetails: const {},
  );
}

String? _discoverGeminiConfiguredModel() {
  final homeDir = _userHomeDir();
  if (homeDir == null) {
    return null;
  }
  final value = _readJsonFile(p.join(homeDir, '.gemini', 'settings.json'));
  return _findModelValueInJson(value);
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
    for (final suffix in ['', '.cmd', '.exe', '.bat', '.ps1']) {
      pushCandidate('$binary$suffix', 'PATH');
    }
  } else {
    pushCandidate(binary, 'PATH');
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      for (final suffix in ['', '.cmd', '.exe', '.ps1']) {
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
          ['diff', '--cached', '--stat=140', ...scopeArgs],
        )
      : const GitResult.ok('');
  if (!stagedStat.ok) {
    return _CommitDiffContextResult.err(stagedStat.error!);
  }

  final unstagedStat = includeUnstaged
      ? await _runGitCommand(
          repositoryPath,
          ['diff', '--stat=140', ...scopeArgs],
        )
      : const GitResult.ok('');
  if (!unstagedStat.ok) {
    return _CommitDiffContextResult.err(unstagedStat.error!);
  }

  final stagedDiff = includeStaged
      ? await _runGitCommand(
          repositoryPath,
          ['diff', '--cached', '--no-color', ...scopeArgs],
          timeout: const Duration(seconds: 50),
        )
      : const GitResult.ok('');
  if (!stagedDiff.ok) {
    return _CommitDiffContextResult.err(stagedDiff.error!);
  }

  final unstagedDiff = includeUnstaged
      ? await _runGitCommand(
          repositoryPath,
          ['diff', '--no-color', ...scopeArgs],
          timeout: const Duration(seconds: 50),
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

  return _CommitDiffContextResult.ok(
    _CommitDiffContext(
      branchName: (branch.data ?? 'HEAD').trim(),
      statusSummary: (status.data ?? '').trim(),
      statSummary: statSummary.trim(),
      diffBundle: diffBundle,
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
    if (remainingBudget <= 120) {
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
}) {
  final buffer = StringBuffer();
  buffer.writeln(
    'You are generating a git commit message for a desktop Git client.',
  );
  buffer.writeln(
    'Return only the commit message text. Do not add commentary, labels, quotes, or code fences.',
  );
  buffer.writeln(
    'Respect the user'
    's natural tone and structure preferences when they are provided, but do not invent facts or generic corporate phrasing.',
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
  buffer.writeln('Model slot: $modelCategoryLabel');
  buffer.writeln('Requested scope: $scopeLabel');
  buffer.writeln('</generation_context>');
  if (customPrompt.trim().isNotEmpty) {
    buffer.writeln();
    buffer.writeln('<user_preferences>');
    buffer.writeln(customPrompt.trim());
    buffer.writeln('</user_preferences>');
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

List<_ProviderAttempt> _buildProviderAttempts(
  _ProviderKind kind,
  String modelId,
) {
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
      return [
        _ProviderAttempt(
          name: 'cli-json',
          args: [
            '--yes',
            '@google/gemini-cli',
            '-p',
            '',
            '-o',
            'json',
            '-m',
            modelId,
          ],
          outputMode: _ProviderOutputMode.geminiJson,
        ),
        _ProviderAttempt(
          name: 'cli',
          args: [
            '--yes',
            '@google/gemini-cli',
            '-p',
            '',
            '-m',
            modelId,
          ],
          outputMode: _ProviderOutputMode.plainText,
        ),
      ];
    case _ProviderKind.openCode:
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
  try {
    final value = jsonDecode(stdout);
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
  for (final line in stdout.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    try {
      final value = jsonDecode(trimmed);
      if (value is! Map || value['type'] != 'text') {
        continue;
      }
      final part = value['part'];
      if (part is Map && part['text'] is String) {
        buffer.write(part['text']);
      }
    } catch (_) {}
  }
  final response = buffer.toString().trim();
  return response.isEmpty ? null : response;
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
  try {
    final process = await Process.start(
      invocation.command,
      invocation.args,
      workingDirectory: workingDirectory,
      runInShell: false,
      environment: environment.isEmpty ? null : environment,
    );

    if (stdinPayload != null) {
      process.stdin.write(stdinPayload);
      await process.stdin.flush();
      await process.stdin.close();
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
      return _ProcessInvocation(
        command: 'cmd',
        args: ['/C', command, ...args],
      );
    }
  }
  return _ProcessInvocation(command: command, args: args);
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

  const _ProviderAttempt({
    required this.name,
    required this.args,
    required this.outputMode,
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

  const _CommitDiffContext({
    required this.branchName,
    required this.statusSummary,
    required this.statSummary,
    required this.diffBundle,
  });
}

class _CommitDiffContextResult {
  final _CommitDiffContext? data;
  final String? error;
  bool get ok => error == null;

  const _CommitDiffContextResult.ok(this.data) : error = null;
  const _CommitDiffContextResult.err(this.error) : data = null;
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
