// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Ephemeral loopback proxy letting `codex exec` (which speaks ONLY the
// OpenAI Responses API — streaming SSE over POST /v1/responses) drive any
// Chat-Completions-compatible upstream (OpenRouter, OpenAI, xAI). Codex
// authenticates to us with a random per-instance bearer token; the real
// upstream key never enters codex's env or argv.
//
// Wire contract confirmed against openai/codex (codex-rs), 2026-07:
//   - request shape: codex-rs/core/src/client.rs builds
//     `ResponsesApiRequest { model, instructions, input, tools, tool_choice:
//     "auto", parallel_tool_calls, reasoning: {effort, summary}, store,
//     stream: true }`.
//   - response items: codex-rs/protocol/src/models.rs `ResponseItem` is
//     `#[serde(tag = "type")]`; `Message { role, content: Vec<ContentItem> }`
//     with `ContentItem::OutputText { text }`; `FunctionCall { name,
//     arguments /* JSON-string */, call_id }`.
//   - SSE parsing: codex-rs/codex-api/src/sse/responses.rs
//     `process_responses_event` matches on the `type` field of each `data:`
//     JSON payload (the `event:` line itself is not consulted — only
//     `sse.data`'s `type`). Handled kinds include `response.created` (needs
//     a `response` key, may be `{}`), `response.output_item.added` /
//     `response.output_item.done` (both parse `item` as a `ResponseItem`;
//     `.added` is not required before `.done` — codex's own unit test
//     `parses_items_and_completed` sends only `.done` events), `response
//     .output_text.delta` (needs `delta`), `response.completed` (needs
//     `response: {id, usage?, end_turn?}`; stream ends here — codex treats
//     a closed connection before `response.completed` as an error), and
//     `response.failed` (needs `response.error.message`). We emit `.added`
//     before `.done` anyway (harmless, and matches the real server) and
//     always terminate with `response.completed`.
//
// Deviation from a fully faithful server: no delta-level streaming
// translation — the upstream Chat Completions call is a single buffered
// non-streaming POST, then we emit the whole SSE event sequence in one
// burst. One behavior, minimal contract, fully testable offline.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Running totals the proxy accumulates across every upstream chat request
/// it makes during its lifetime — the fields codex's own JSONL output can
/// never carry (cost, the raw upstream request/model ids) or that codex's
/// summary line drops precision on. Survives `dispose()` so the caller can
/// read it after tearing the proxy down.
class PiggybackUsageTotals {
  int inputTokens = 0;
  int outputTokens = 0;
  int cachedTokens = 0;
  int reasoningTokens = 0;
  int requestCount = 0;

  /// Summed across requests when upstream reports `usage.cost` (OpenRouter,
  /// with `requestCostAccounting: true`). Stays null if never reported.
  double? costUsd;

  /// Upstream response `id` of the LAST request.
  String? requestId;

  /// Upstream response `model` of the LAST request, when non-empty.
  String? resolvedModel;
}

class CodexPiggybackProxy {
  final String baseUrl;
  final String token;
  final String _upstreamBaseUrl;
  final String _upstreamApiKey;
  final Map<String, String> _upstreamHeaders;
  final String? _reasoningEffort;
  final bool _requestCostAccounting;
  final PiggybackUsageTotals _usageTotals = PiggybackUsageTotals();
  final Set<HttpClient> _activeClients = {};
  HttpServer? _server;

  CodexPiggybackProxy._(
    this.baseUrl,
    this.token,
    this._upstreamBaseUrl,
    this._upstreamApiKey,
    this._upstreamHeaders,
    this._reasoningEffort,
    this._requestCostAccounting,
    this._server,
  );

  /// Running usage totals accumulated from every successful upstream chat
  /// response so far. A live snapshot — safe to read at any time, including
  /// after [dispose] (disposal only closes the listening socket).
  PiggybackUsageTotals get usageTotals => _usageTotals;

  static Future<CodexPiggybackProxy> start({
    required String upstreamBaseUrl,
    required String upstreamApiKey,
    Map<String, String> upstreamHeaders = const {},
    String? reasoningEffort,
    bool requestCostAccounting = false,
  }) async {
    final trimmedUpstream = upstreamBaseUrl.endsWith('/')
        ? upstreamBaseUrl.substring(0, upstreamBaseUrl.length - 1)
        : upstreamBaseUrl;
    final token = _randomToken();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = CodexPiggybackProxy._(
      'http://127.0.0.1:${server.port}/v1',
      token,
      trimmedUpstream,
      upstreamApiKey,
      upstreamHeaders,
      reasoningEffort,
      requestCostAccounting,
      server,
    );
    server.listen(proxy._handleRequest);
    return proxy;
  }

  static String _randomToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  Future<void> dispose() async {
    final server = _server;
    _server = null;
    if (server == null) return;
    try {
      await server.close(force: true);
    } catch (_) {}
    // Abort any upstream POST still in flight: once the caller disposes us
    // (codex died or timed out), an abandoned upstream request would keep
    // billing the real key for up to its full timeout with nobody listening.
    for (final client in _activeClients.toList()) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
    _activeClients.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path != '/v1/responses' && path != '/responses') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final authHeader = request.headers.value(HttpHeaders.authorizationHeader);
      if (authHeader != 'Bearer $token') {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }

      final rawBody = await utf8.decoder.bind(request).join();
      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('body is not a JSON object');
        }
        body = decoded;
      } catch (_) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      await _handleResponsesRequest(request, body);
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleResponsesRequest(
    HttpRequest request,
    Map<String, dynamic> responsesBody,
  ) async {
    final chatBody = _translateRequest(responsesBody);

    request.response.headers.contentType = ContentType('text', 'event-stream');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.bufferOutput = false;

    Map<String, dynamic>? chatResponse;
    String? errorMessage;
    try {
      chatResponse = await _postChatCompletions(chatBody);
    } catch (e) {
      errorMessage = 'upstream request failed: $e';
    }

    final events = errorMessage != null
        ? _failedEvents(errorMessage)
        : _translateResponse(chatResponse!);

    for (final event in events) {
      _writeSseEvent(request.response, event);
    }
    await request.response.close();
  }

  Future<Map<String, dynamic>> _postChatCompletions(
    Map<String, dynamic> chatBody,
  ) async {
    final client = HttpClient()..idleTimeout = const Duration(seconds: 5);
    _activeClients.add(client);
    try {
      final url = Uri.parse('$_upstreamBaseUrl/chat/completions');
      // One timeout over the whole round trip (connect + write + response
      // headers), not just the response wait — a hung DNS/connect must not
      // escape the 10-minute upstream contract.
      final response = await () async {
        final httpReq = await client.postUrl(url);
        httpReq.headers.set('Authorization', 'Bearer $_upstreamApiKey');
        httpReq.headers.contentType = ContentType.json;
        for (final h in _upstreamHeaders.entries) {
          httpReq.headers.set(h.key, h.value);
        }
        httpReq.persistentConnection = false;
        httpReq.write(jsonEncode(chatBody));
        return httpReq.close();
      }()
          .timeout(const Duration(minutes: 10));
      final responseBody = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _extractErrorMessage(responseBody) ??
            'HTTP ${response.statusCode}';
        throw Exception(message);
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('invalid upstream response (not a JSON object)');
      }
      return decoded;
    } finally {
      _activeClients.remove(client);
      client.close(force: true);
    }
  }

  static String? _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (error is String) return error;
      }
    } catch (_) {}
    return null;
  }

  // ---- Request translation: Responses -> Chat Completions ----

  Map<String, dynamic> _translateRequest(Map<String, dynamic> responses) {
    final messages = <Map<String, dynamic>>[];

    final instructions = responses['instructions'];
    if (instructions is String && instructions.isNotEmpty) {
      messages.add({'role': 'system', 'content': instructions});
    }

    final input = responses['input'];
    if (input is List) {
      for (final rawItem in input) {
        if (rawItem is! Map) continue;
        final item = rawItem;
        final type = item['type'];
        switch (type) {
          case 'message':
            final role = item['role'] as String? ?? 'user';
            final content = item['content'];
            final text = _extractMessageText(content);
            messages.add({'role': role, 'content': text});
            break;
          case 'function_call':
            messages.add({
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': item['call_id'],
                  'type': 'function',
                  'function': {
                    'name': item['name'],
                    'arguments': item['arguments'],
                  },
                },
              ],
            });
            break;
          case 'function_call_output':
            final output = item['output'];
            final outputText = output is String ? output : jsonEncode(output);
            messages.add({
              'role': 'tool',
              'tool_call_id': item['call_id'],
              'content': outputText,
            });
            break;
          case 'reasoning':
            break; // dropped
          default:
            break; // unknown item types dropped
        }
      }
    }

    final chat = <String, dynamic>{
      'model': responses['model'],
      'messages': messages,
    };

    final tools = responses['tools'];
    if (tools is List) {
      final chatTools = <Map<String, dynamic>>[];
      for (final rawTool in tools) {
        if (rawTool is! Map) continue;
        if (rawTool['type'] != 'function') continue; // drop non-function tools
        chatTools.add({
          'type': 'function',
          'function': {
            'name': rawTool['name'],
            'description': rawTool['description'],
            'parameters': rawTool['parameters'],
          },
        });
      }
      if (chatTools.isNotEmpty) chat['tools'] = chatTools;
    }

    final toolChoice = responses['tool_choice'];
    if (toolChoice is String) {
      chat['tool_choice'] = toolChoice; // "auto"/"none"/"required" map cleanly
    }

    final parallelToolCalls = responses['parallel_tool_calls'];
    if (parallelToolCalls is bool) {
      chat['parallel_tool_calls'] = parallelToolCalls;
    }

    final temperature = responses['temperature'];
    if (temperature is num) {
      chat['temperature'] = temperature;
    }

    // Codex only carries `reasoning: {effort}` for model slugs its own
    // catalog flags `supports_reasoning_summaries` — most OpenRouter models
    // are unknown slugs to codex and never get it, so Manifold's thinking
    // slider would silently die for them. `_reasoningEffort` is Manifold's
    // canonical effort string (the same value the direct HTTP path sends as
    // `reasoning_effort`) and is the source of truth whenever set, ALWAYS
    // overriding whatever codex mapped — this is how the proxy makes the
    // effort slider work for every model, not just the OpenAI family codex
    // recognizes. Only when Manifold didn't supply one do we fall back to
    // translating codex's own `reasoning.effort`, if present.
    if (_reasoningEffort != null) {
      chat['reasoning_effort'] = _reasoningEffort;
    } else {
      final reasoning = responses['reasoning'];
      if (reasoning is Map && reasoning['effort'] is String) {
        chat['reasoning_effort'] = reasoning['effort'];
      }
    }

    final text = responses['text'];
    if (text is Map && text['verbosity'] is String) {
      chat['verbosity'] = text['verbosity'];
    }

    final serviceTier = responses['service_tier'];
    if (serviceTier is String) {
      chat['service_tier'] = serviceTier;
    }

    final promptCacheKey = responses['prompt_cache_key'];
    if (promptCacheKey is String) {
      chat['prompt_cache_key'] = promptCacheKey;
    }

    // Never forwarded: `include`, `client_metadata`, `stream_options`,
    // `store` — Responses-only knobs (delta-inclusion lists, opaque client
    // tags, streaming-chunk options, response-storage toggle) that have no
    // Chat Completions analogue for a single buffered upstream call.

    if (_requestCostAccounting) {
      // OpenRouter-specific: asking for `usage.include` makes the reply
      // carry a per-request `usage.cost` in USD so the proxy can accumulate
      // real spend even though codex itself never sees or reports cost.
      chat['usage'] = {'include': true};
    }

    return chat;
  }

  static String _extractMessageText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final buf = StringBuffer();
      for (final part in content) {
        if (part is Map && part['text'] is String) {
          buf.write(part['text'] as String);
        }
      }
      return buf.toString();
    }
    return '';
  }

  // ---- Response translation: Chat Completions -> Responses SSE ----

  List<Map<String, dynamic>> _translateResponse(Map<String, dynamic> chat) {
    final responseId = (chat['id'] as String?) ?? 'resp_${_randomToken().substring(0, 16)}';
    final choices = chat['choices'];
    final message = (choices is List && choices.isNotEmpty && choices.first is Map)
        ? (choices.first as Map)['message']
        : null;

    final events = <Map<String, dynamic>>[];
    final outputItems = <Map<String, dynamic>>[];
    var outputIndex = 0;

    events.add({
      'type': 'response.created',
      'response': {'id': responseId, 'status': 'in_progress'},
    });

    if (message is Map) {
      final text = message['content'];
      if (text is String && text.isNotEmpty) {
        const itemId = 'msg_1';
        final item = {
          'type': 'message',
          'id': itemId,
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': text},
          ],
        };
        events.add({
          'type': 'response.output_item.added',
          'output_index': outputIndex,
          'item': item,
        });
        events.add({
          'type': 'response.output_text.delta',
          'item_id': itemId,
          'output_index': outputIndex,
          'delta': text,
        });
        events.add({
          'type': 'response.output_item.done',
          'output_index': outputIndex,
          'item': item,
        });
        outputItems.add(item);
        outputIndex++;
      }

      final toolCalls = message['tool_calls'];
      if (toolCalls is List) {
        for (var i = 0; i < toolCalls.length; i++) {
          final call = toolCalls[i];
          if (call is! Map) continue;
          final function = call['function'];
          final callId = (call['id'] as String?) ?? 'call_${i + 1}';
          final name = (function is Map ? function['name'] : null) as String?;
          final arguments = (function is Map ? function['arguments'] : null) as String? ?? '';
          final itemId = 'fc_${i + 1}';
          final item = {
            'type': 'function_call',
            'id': itemId,
            'call_id': callId,
            'name': name,
            'arguments': arguments,
          };
          events.add({
            'type': 'response.output_item.added',
            'output_index': outputIndex,
            'item': item,
          });
          events.add({
            'type': 'response.output_item.done',
            'output_index': outputIndex,
            'item': item,
          });
          outputItems.add(item);
          outputIndex++;
        }
      }
    }

    final usage = chat['usage'];
    Map<String, dynamic>? responseUsage;
    if (usage is Map) {
      final promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
      final completionTokens = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
      final promptDetails = usage['prompt_tokens_details'];
      final completionDetails = usage['completion_tokens_details'];
      final cachedTokens =
          (promptDetails is Map ? promptDetails['cached_tokens'] as num? : null)?.toInt() ?? 0;
      final reasoningTokens =
          (completionDetails is Map ? completionDetails['reasoning_tokens'] as num? : null)
                  ?.toInt() ??
              0;
      // codex's `response.completed` usage parsing HARD-FAILS on a partial
      // usage object — `input_tokens`, `output_tokens`, `total_tokens` are
      // all required, and codex never computes `total` itself. Some
      // upstreams (and our own synthetic totals below) omit `total_tokens`,
      // so we always derive and emit all three rather than ever passing a
      // partial object through.
      final totalTokens =
          (usage['total_tokens'] as num?)?.toInt() ?? (promptTokens + completionTokens);
      responseUsage = {
        'input_tokens': promptTokens,
        'input_tokens_details': {'cached_tokens': cachedTokens},
        'output_tokens': completionTokens,
        'output_tokens_details': {'reasoning_tokens': reasoningTokens},
        'total_tokens': totalTokens,
      };

      _usageTotals.requestCount += 1;
      _usageTotals.inputTokens += promptTokens;
      _usageTotals.outputTokens += completionTokens;
      _usageTotals.cachedTokens += cachedTokens;
      _usageTotals.reasoningTokens += reasoningTokens;
      final cost = usage['cost'];
      if (cost is num) {
        _usageTotals.costUsd = (_usageTotals.costUsd ?? 0) + cost.toDouble();
      }
    }

    final id = chat['id'];
    if (id is String && id.isNotEmpty) {
      _usageTotals.requestId = id;
    }
    final model = chat['model'];
    if (model is String && model.isNotEmpty) {
      _usageTotals.resolvedModel = model;
    }

    events.add({
      'type': 'response.completed',
      'response': {
        'id': responseId,
        'status': 'completed',
        'output': outputItems,
        if (responseUsage != null) 'usage': responseUsage,
      },
    });

    return events;
  }

  List<Map<String, dynamic>> _failedEvents(String message) {
    return [
      {
        'type': 'response.failed',
        'response': {
          'status': 'failed',
          'error': {'message': message},
        },
      },
    ];
  }

  void _writeSseEvent(HttpResponse response, Map<String, dynamic> event) {
    final type = event['type'] as String;
    response.write('event: $type\n');
    response.write('data: ${jsonEncode(event)}\n\n');
  }
}
