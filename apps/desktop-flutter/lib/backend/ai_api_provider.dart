import 'dart:async';
import 'dart:convert';
import 'dart:io';

String _safeError(String provider, Object e) {
  if (e is SocketException) return '$provider: network error (${e.osError?.message ?? 'connection failed'})';
  if (e is HttpException) return '$provider: HTTP error';
  if (e is FormatException) return '$provider: invalid response format';
  if (e is TimeoutException) return '$provider: request timed out';
  return '$provider: ${e.runtimeType}';
}

class AiApiCredentials {
  final String apiKey;
  final String? baseUrl;
  const AiApiCredentials({required this.apiKey, this.baseUrl});
}

class AiApiRequest {
  final String prompt;
  final String model;
  final AiApiCredentials credentials;
  final double temperature;
  final int? maxTokens;
  final String? reasoningEffort;
  const AiApiRequest({
    required this.prompt,
    required this.model,
    required this.credentials,
    this.temperature = 0.3,
    this.maxTokens,
    this.reasoningEffort,
  });
}

class AiApiResponse {
  final String? text;
  final String? error;
  final int inputTokens;
  final int outputTokens;
  const AiApiResponse({
    this.text,
    this.error,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });
}

class AiApiModel {
  final String id;
  final String? displayName;
  final String? description;
  final double? promptPricePerToken;
  final double? completionPricePerToken;
  final Set<String> supportedParameters;
  const AiApiModel({
    required this.id,
    this.displayName,
    this.description,
    this.promptPricePerToken,
    this.completionPricePerToken,
    this.supportedParameters = const {},
  });

  bool get supportsReasoning => supportedParameters.contains('reasoning');
}

class AiApiKeyInfo {
  final double? limit;
  final double? used;
  final double? remaining;
  final bool isFreeTier;
  const AiApiKeyInfo({
    this.limit,
    this.used,
    this.remaining,
    this.isFreeTier = false,
  });
  double? get fraction =>
      limit != null && limit! > 0 && used != null ? (used! / limit!).clamp(0.0, 1.0) : null;
}

abstract class AiApiProvider {
  String get id;
  String get displayName;
  String get defaultBaseUrl;
  bool get allModelsSupportReasoning => false;

  Future<AiApiResponse> complete(AiApiRequest request);
  Future<List<AiApiModel>> listModels(AiApiCredentials creds);
  Future<AiApiKeyInfo?> fetchKeyInfo(AiApiCredentials creds) async => null;
  bool isReady(AiApiCredentials creds) => creds.apiKey.trim().isNotEmpty;

  String effectiveBaseUrl(AiApiCredentials creds) {
    final custom = creds.baseUrl?.trim() ?? '';
    if (custom.isEmpty) return defaultBaseUrl;
    if (custom.startsWith('http://') && !_isLoopback(custom)) {
      return defaultBaseUrl;
    }
    return custom;
  }
}

// ---------------------------------------------------------------------------
// OpenAI-compatible base (shared by OpenRouter, OpenAI, X-AI)
// ---------------------------------------------------------------------------

abstract class OpenAiCompatibleApiProvider extends AiApiProvider {
  Map<String, String> extraHeaders(AiApiCredentials creds) => const {};

  @override
  Future<AiApiResponse> complete(AiApiRequest request) async {
    final base = effectiveBaseUrl(request.credentials);
    final url = Uri.parse('$base/chat/completions');
    final body = <String, dynamic>{
      'model': request.model,
      'messages': [
        {'role': 'user', 'content': request.prompt},
      ],
      'temperature': request.temperature,
    };
    if (request.reasoningEffort != null) {
      body['reasoning_effort'] = request.reasoningEffort;
    }
    if (request.maxTokens != null) {
      body['max_tokens'] = request.maxTokens;
    }
    return _postJson(url, body, request.credentials);
  }

  @override
  Future<List<AiApiModel>> listModels(AiApiCredentials creds) async {
    final base = effectiveBaseUrl(creds);
    final url = Uri.parse('$base/models');
    final client = HttpClient()..idleTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(url);
      request.headers.set('Authorization', 'Bearer ${creds.apiKey}');
      for (final h in extraHeaders(creds).entries) {
        request.headers.set(h.key, h.value);
      }
      final response = await request.close().timeout(
            const Duration(seconds: 30),
          );
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(raw);
      if (json is! Map) return const [];
      final data = json['data'];
      if (data is! List) return const [];
      final models = <AiApiModel>[];
      for (final entry in data) {
        if (entry is! Map) continue;
        final entryId = entry['id'];
        if (entryId is! String || entryId.trim().isEmpty) continue;
        if (!_hasTextOutput(entry)) continue;
        final pricing = entry['pricing'];
        double? promptPrice;
        double? completionPrice;
        if (pricing is Map) {
          promptPrice = _parsePrice(pricing['prompt']);
          completionPrice = _parsePrice(pricing['completion']);
        }
        final rawParams = entry['supported_parameters'];
        final params = rawParams is List
            ? {for (final p in rawParams) if (p is String) p}
            : const <String>{};
        models.add(AiApiModel(
          id: entryId,
          displayName: entry['name'] as String?,
          description: entry['description'] as String?,
          promptPricePerToken: promptPrice,
          completionPricePerToken: completionPrice,
          supportedParameters: params,
        ));
      }
      return models;
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  Future<AiApiResponse> _postJson(
    Uri url,
    Map<String, dynamic> body,
    AiApiCredentials creds,
  ) async {
    final client = HttpClient()..idleTimeout = const Duration(seconds: 5);
    try {
      final payload = jsonEncode(body);
      HttpClientResponse? response;
      String? responseBody;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final request = await client.postUrl(url);
          request.headers.set('Authorization', 'Bearer ${creds.apiKey}');
          request.headers.contentType = ContentType.json;
          for (final h in extraHeaders(creds).entries) {
            request.headers.set(h.key, h.value);
          }
          request.persistentConnection = false;
          request.write(payload);
          response = await request.close().timeout(
                const Duration(minutes: 10),
              );
          responseBody = await response.transform(utf8.decoder).join();
          break;
        } on HttpException {
          if (attempt == 1) rethrow;
        }
      }

      if (response == null || responseBody == null) {
        return const AiApiResponse(error: 'Connection failed.');
      }
      if (response.statusCode != 200) {
        final errMsg = _extractOpenAiError(responseBody) ??
            'HTTP ${response.statusCode}';
        return AiApiResponse(error: '$displayName: $errMsg');
      }

      final json = jsonDecode(responseBody);
      if (json is! Map) {
        return AiApiResponse(error: '$displayName: invalid response.');
      }

      final choices = json['choices'] as List?;
      final text = (choices?.firstOrNull as Map?)?['message']?['content']
          as String?;
      final usage = json['usage'] as Map?;
      final inputTokens = (usage?['prompt_tokens'] as int?) ?? 0;
      final outputTokens = (usage?['completion_tokens'] as int?) ?? 0;

      if (text == null || text.trim().isEmpty) {
        return AiApiResponse(
          error: '$displayName: empty response.',
          inputTokens: inputTokens,
          outputTokens: outputTokens,
        );
      }

      return AiApiResponse(
        text: text,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
      );
    } catch (e) {
      return AiApiResponse(error: _safeError(displayName, e));
    } finally {
      client.close(force: true);
    }
  }
}

bool _hasTextOutput(Map entry) {
  final arch = entry['architecture'];
  if (arch is! Map) return true;
  final modality = arch['modality'];
  if (modality is String && modality.contains('->')) {
    final output = modality.split('->').last;
    return output.contains('text');
  }
  final outputModalities = arch['output_modalities'];
  if (outputModalities is List) {
    return outputModalities.any((m) => m == 'text');
  }
  return true;
}

double? _parsePrice(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String? _extractOpenAiError(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map) {
      final err = json['error'];
      if (err is Map) {
        final msg = err['message'];
        if (msg is String && msg.trim().isNotEmpty) return msg;
      }
    }
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// OpenRouter
// ---------------------------------------------------------------------------

class OpenRouterApiProvider extends OpenAiCompatibleApiProvider {
  @override
  String get id => 'openrouter';
  @override
  String get displayName => 'OpenRouter';
  @override
  String get defaultBaseUrl => 'https://openrouter.ai/api/v1';

  @override
  Map<String, String> extraHeaders(AiApiCredentials creds) => {
        'HTTP-Referer': 'https://github.com/gdpu-app/gdpu',
        'X-Title': 'GDPU',
      };

  @override
  Future<AiApiKeyInfo?> fetchKeyInfo(AiApiCredentials creds) async {
    final base = effectiveBaseUrl(creds);
    final url = Uri.parse('$base/auth/key');
    final client = HttpClient()
      ..idleTimeout = const Duration(seconds: 5)
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(url)
          .timeout(const Duration(seconds: 10));
      request.headers.set('Authorization', 'Bearer ${creds.apiKey}');
      final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
      final raw = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final data = json['data'];
      if (data is! Map) return null;
      return AiApiKeyInfo(
        limit: (data['limit'] as num?)?.toDouble(),
        used: (data['usage_monthly'] as num?)?.toDouble(),
        remaining: (data['limit_remaining'] as num?)?.toDouble(),
        isFreeTier: data['is_free_tier'] == true,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

// ---------------------------------------------------------------------------
// OpenAI
// ---------------------------------------------------------------------------

class OpenAiApiProvider extends OpenAiCompatibleApiProvider {
  @override
  String get id => 'openai';
  @override
  String get displayName => 'OpenAI';
  @override
  String get defaultBaseUrl => 'https://api.openai.com/v1';
}

// ---------------------------------------------------------------------------
// X-AI (Grok)
// ---------------------------------------------------------------------------

class XaiApiProvider extends OpenAiCompatibleApiProvider {
  @override
  String get id => 'xai';
  @override
  String get displayName => 'X-AI (Grok)';
  @override
  String get defaultBaseUrl => 'https://api.x.ai/v1';
}

// ---------------------------------------------------------------------------
// Anthropic — different request/response format
// ---------------------------------------------------------------------------

const double _phi = 1.6180339887498949;

/// Universal effort fraction: maps named effort levels to [0, 1]
/// on the golden-ratio power scale. Every provider's reasoning
/// mechanism maps through this — codex/claude use the string name,
/// OpenAI-compatible uses the fraction as reasoning_effort, and
/// Anthropic converts to thinking budget tokens.
double? effortFraction(String? effort) => switch (effort) {
      'low' => 1.0 / (_phi * _phi * _phi),  // ≈ 0.236
      'medium' => 1.0 / (_phi * _phi),       // ≈ 0.382
      'high' => 1.0 / _phi,                  // ≈ 0.618
      'xhigh' || 'max' => 1.0,
      _ => null,
    };

/// Canonical effort levels ordered low→max. The UI slider indexes
/// into this list; the backend looks up the fraction via [effortFraction].
const List<String> effortLevels = ['low', 'medium', 'high', 'xhigh', 'max'];

class AnthropicApiProvider extends AiApiProvider {
  @override
  String get id => 'anthropic';
  @override
  String get displayName => 'Anthropic';
  @override
  String get defaultBaseUrl => 'https://api.anthropic.com';
  @override
  bool get allModelsSupportReasoning => true;

  @override
  Future<AiApiResponse> complete(AiApiRequest request) async {
    final base = effectiveBaseUrl(request.credentials);
    final url = Uri.parse('$base/v1/messages');
    final baseMaxTokens = request.maxTokens ?? 16384;
    final fraction = effortFraction(request.reasoningEffort);
    final thinkingBudget =
        fraction != null ? (fraction * baseMaxTokens).round() : null;
    final body = <String, dynamic>{
      'model': request.model,
      'messages': [
        {'role': 'user', 'content': request.prompt},
      ],
      'temperature': thinkingBudget != null ? 1.0 : request.temperature,
      'max_tokens': thinkingBudget != null
          ? thinkingBudget + baseMaxTokens
          : baseMaxTokens,
      if (thinkingBudget != null)
        'thinking': {
          'type': 'enabled',
          'budget_tokens': thinkingBudget,
        },
    };

    final client = HttpClient()..idleTimeout = const Duration(seconds: 5);
    try {
      final payload = jsonEncode(body);
      HttpClientResponse? response;
      String? responseBody;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final httpReq = await client.postUrl(url);
          httpReq.headers.set('x-api-key', request.credentials.apiKey);
          httpReq.headers.set('anthropic-version', '2023-06-01');
          httpReq.headers.contentType = ContentType.json;
          httpReq.persistentConnection = false;
          httpReq.write(payload);
          response = await httpReq.close().timeout(
                const Duration(minutes: 10),
              );
          responseBody = await response.transform(utf8.decoder).join();
          break;
        } on HttpException {
          if (attempt == 1) rethrow;
        }
      }

      if (response == null || responseBody == null) {
        return const AiApiResponse(error: 'Anthropic: connection failed.');
      }
      if (response.statusCode != 200) {
        final errMsg = _extractAnthropicError(responseBody) ??
            'HTTP ${response.statusCode}';
        return AiApiResponse(error: 'Anthropic: $errMsg');
      }

      final json = jsonDecode(responseBody);
      if (json is! Map) {
        return const AiApiResponse(error: 'Anthropic: invalid response.');
      }

      final content = json['content'] as List?;
      String? text;
      for (final block in content ?? []) {
        if (block is Map && block['type'] == 'text') {
          text = block['text'] as String?;
          if (text != null) break;
        }
      }

      final usage = json['usage'] as Map?;
      final inputTokens = (usage?['input_tokens'] as int?) ?? 0;
      final outputTokens = (usage?['output_tokens'] as int?) ?? 0;

      if (text == null || text.trim().isEmpty) {
        return AiApiResponse(
          error: 'Anthropic: empty response.',
          inputTokens: inputTokens,
          outputTokens: outputTokens,
        );
      }

      return AiApiResponse(
        text: text,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
      );
    } catch (e) {
      return AiApiResponse(error: _safeError('Anthropic', e));
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<AiApiModel>> listModels(AiApiCredentials creds) async {
    final base = effectiveBaseUrl(creds);
    final url = Uri.parse('$base/v1/models');
    final client = HttpClient()..idleTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(url);
      request.headers.set('x-api-key', creds.apiKey);
      request.headers.set('anthropic-version', '2023-06-01');
      final response = await request.close().timeout(
            const Duration(seconds: 30),
          );
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(raw);
      if (json is! Map) return const [];
      final data = json['data'];
      if (data is! List) return const [];
      final models = <AiApiModel>[];
      for (final entry in data) {
        if (entry is! Map) continue;
        final entryId = entry['id'];
        if (entryId is! String || entryId.trim().isEmpty) continue;
        models.add(AiApiModel(
          id: entryId,
          displayName: entry['display_name'] as String?,
        ));
      }
      return models;
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }
}

String? _extractAnthropicError(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map) {
      final err = json['error'];
      if (err is Map) {
        final msg = err['message'];
        if (msg is String && msg.trim().isNotEmpty) return msg;
      }
    }
  } catch (_) {}
  return null;
}

bool _isLoopback(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

final List<AiApiProvider> aiApiProviderRegistry = List.unmodifiable([
  OpenRouterApiProvider(),
  OpenAiApiProvider(),
  AnthropicApiProvider(),
  XaiApiProvider(),
]);

AiApiProvider? aiApiProviderById(String id) {
  for (final p in aiApiProviderRegistry) {
    if (p.id == id) return p;
  }
  return null;
}
