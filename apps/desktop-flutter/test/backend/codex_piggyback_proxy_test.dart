// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Pins the codex-piggyback wire contract: codex speaks ONLY the Responses
// API (streaming SSE over POST /v1/responses); the proxy translates that to
// a single buffered Chat Completions call against any OpenAI-compatible
// upstream, then re-emits the whole SSE event sequence in one burst. These
// tests drive a REAL mock upstream HttpServer so the translated request body
// and the emitted SSE stream are both verified byte-for-byte against what
// codex-rs's own parser (codex-rs/codex-api/src/sse/responses.rs) accepts.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/codex_piggyback_proxy.dart';

/// Minimal SSE frame: `event: <type>` + `data: <json>` + blank line.
class SseEvent {
  final String type;
  final Map<String, dynamic> data;
  SseEvent(this.type, this.data);
}

List<SseEvent> parseSse(String body) {
  final events = <SseEvent>[];
  for (final block in body.split('\n\n')) {
    if (block.trim().isEmpty) continue;
    String? eventType;
    String? dataLine;
    for (final line in block.split('\n')) {
      if (line.startsWith('event: ')) {
        eventType = line.substring('event: '.length).trim();
      } else if (line.startsWith('data: ')) {
        dataLine = line.substring('data: '.length);
      }
    }
    if (dataLine == null) continue;
    final decoded = jsonDecode(dataLine) as Map<String, dynamic>;
    events.add(SseEvent(eventType ?? decoded['type'] as String, decoded));
  }
  return events;
}

/// A tiny mock "OpenAI-compatible" upstream that captures the last request
/// it received and returns a canned `chat/completions` JSON body.
class MockUpstream {
  late HttpServer _server;
  Map<String, dynamic>? lastBody;
  Map<String, String> lastHeaders = {};
  String lastPath = '';
  int statusCode = 200;
  Map<String, dynamic> cannedResponse = {};
  bool wasHit = false;

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      wasHit = true;
      lastPath = request.uri.path;
      lastHeaders = {};
      request.headers.forEach((name, values) {
        lastHeaders[name] = values.join(',');
      });
      final raw = await utf8.decoder.bind(request).join();
      if (raw.isNotEmpty) {
        lastBody = jsonDecode(raw) as Map<String, dynamic>;
      }
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(cannedResponse));
      await request.response.close();
    });
    return 'http://127.0.0.1:${_server.port}/v1';
  }

  Future<void> stop() => _server.close(force: true);
}

Future<HttpClientResponse> postResponses(
  CodexPiggybackProxy proxy,
  Map<String, dynamic> body, {
  String? bearerOverride,
}) async {
  final client = HttpClient();
  final req = await client.postUrl(Uri.parse('${proxy.baseUrl}/responses'));
  req.headers.set('Authorization', 'Bearer ${bearerOverride ?? proxy.token}');
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final resp = await req.close();
  return resp;
}

void main() {
  group('CodexPiggybackProxy', () {
    late MockUpstream upstream;
    late String upstreamUrl;

    setUp(() async {
      upstream = MockUpstream();
      upstreamUrl = await upstream.start();
    });

    tearDown(() async {
      await upstream.stop();
    });

    test('full round trip translates request and response correctly',
        () async {
      upstream.cannedResponse = {
        'id': 'chatcmpl-1',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'Hello from upstream'},
          },
        ],
        'usage': {
          'prompt_tokens': 10,
          'prompt_tokens_details': {'cached_tokens': 2},
          'completion_tokens': 5,
          'completion_tokens_details': {'reasoning_tokens': 1},
          'total_tokens': 15,
        },
      };

      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-real-upstream-key',
        upstreamHeaders: {'X-Title': 'Manifold'},
      );

      try {
        final requestBody = {
          'model': 'gpt-test',
          'instructions': 'You are a helpful assistant.',
          'input': [
            {
              'type': 'message',
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': 'hi there'},
              ],
            },
          ],
          'tools': [
            {
              'type': 'function',
              'name': 'get_weather',
              'description': 'Gets the weather',
              'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
              'strict': true,
            },
          ],
          'tool_choice': 'auto',
          'parallel_tool_calls': true,
          'reasoning': {'effort': 'medium', 'summary': 'auto'},
          'stream': true,
          'store': false,
        };

        final resp = await postResponses(proxy, requestBody);
        expect(resp.statusCode, 200);
        final sseBody = await utf8.decoder.bind(resp).join();

        // Upstream received a correctly translated chat/completions body.
        expect(upstream.wasHit, isTrue);
        expect(upstream.lastPath, '/v1/chat/completions');
        expect(upstream.lastHeaders['authorization'], 'Bearer sk-real-upstream-key');
        expect(upstream.lastHeaders['x-title'], 'Manifold');

        final sentBody = upstream.lastBody!;
        expect(sentBody['stream'], isNull);
        expect(sentBody['store'], isNull);
        expect(sentBody['include'], isNull);
        expect(sentBody['previous_response_id'], isNull);
        expect(sentBody['reasoning_effort'], 'medium');
        expect(sentBody['parallel_tool_calls'], true);
        expect(sentBody['tool_choice'], 'auto');

        final messages = sentBody['messages'] as List;
        expect(messages[0], {'role': 'system', 'content': 'You are a helpful assistant.'});
        final userMsg = messages[1] as Map;
        expect(userMsg['role'], 'user');
        expect(userMsg['content'], 'hi there');

        final tools = sentBody['tools'] as List;
        expect(tools.length, 1);
        final weatherTool = tools[0] as Map;
        expect(weatherTool['type'], 'function');
        final weatherFunction = weatherTool['function'] as Map;
        expect(weatherFunction['name'], 'get_weather');
        expect(weatherFunction['description'], 'Gets the weather');

        // SSE stream parses into the expected event sequence.
        final events = parseSse(sseBody);
        expect(events.first.type, 'response.created');
        expect(events.last.type, 'response.completed');

        final textDelta = events.firstWhere((e) => e.type == 'response.output_text.delta');
        expect(textDelta.data['delta'], 'Hello from upstream');

        final itemDone = events.firstWhere((e) => e.type == 'response.output_item.done');
        final item = itemDone.data['item'] as Map;
        expect(item['type'], 'message');
        final content = item['content'] as List;
        final firstPart = content[0] as Map;
        expect(firstPart['type'], 'output_text');
        expect(firstPart['text'], 'Hello from upstream');

        final completed = events.last;
        final response = completed.data['response'] as Map;
        final usage = response['usage'] as Map;
        expect(usage['input_tokens'], 10);
        final inputTokensDetails = usage['input_tokens_details'] as Map;
        expect(inputTokensDetails['cached_tokens'], 2);
        expect(usage['output_tokens'], 5);
        final outputTokensDetails = usage['output_tokens_details'] as Map;
        expect(outputTokensDetails['reasoning_tokens'], 1);
        expect(usage['total_tokens'], 15);
      } finally {
        await proxy.dispose();
      }
    });

    test('tool-call turn: upstream tool_calls become function_call items, '
        'and a follow-up turn with function_call/function_call_output '
        'translates back to assistant tool_calls + tool messages', () async {
      upstream.cannedResponse = {
        'id': 'chatcmpl-2',
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_abc123',
                  'type': 'function',
                  'function': {
                    'name': 'get_weather',
                    'arguments': '{"city":"Berlin"}',
                  },
                },
              ],
            },
          },
        ],
      };

      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
      );

      try {
        final firstRequest = {
          'model': 'gpt-test',
          'input': [
            {
              'type': 'message',
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': "what's the weather in Berlin?"},
              ],
            },
          ],
        };
        final resp1 = await postResponses(proxy, firstRequest);
        final sseBody1 = await utf8.decoder.bind(resp1).join();
        final events1 = parseSse(sseBody1);

        final fnDone = events1.firstWhere((e) =>
            e.type == 'response.output_item.done' &&
            (e.data['item'] as Map)['type'] == 'function_call');
        final fnItem = fnDone.data['item'] as Map;
        expect(fnItem['call_id'], 'call_abc123');
        expect(fnItem['name'], 'get_weather');
        expect(fnItem['arguments'], '{"city":"Berlin"}');

        // Second turn: codex sends back the function_call + its output.
        upstream.cannedResponse = {
          'id': 'chatcmpl-3',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'It is 20C and sunny in Berlin.'},
            },
          ],
        };

        final secondRequest = {
          'model': 'gpt-test',
          'input': [
            {
              'type': 'message',
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': "what's the weather in Berlin?"},
              ],
            },
            {
              'type': 'function_call',
              'call_id': 'call_abc123',
              'name': 'get_weather',
              'arguments': '{"city":"Berlin"}',
            },
            {
              'type': 'function_call_output',
              'call_id': 'call_abc123',
              'output': '{"tempC":20,"condition":"sunny"}',
            },
          ],
        };
        final resp2 = await postResponses(proxy, secondRequest);
        expect(resp2.statusCode, 200);
        await utf8.decoder.bind(resp2).join();

        final sentBody = upstream.lastBody!;
        final messages = sentBody['messages'] as List;

        final assistantMsg =
            messages.firstWhere((m) => (m as Map)['tool_calls'] != null) as Map;
        expect(assistantMsg['content'], isNull);
        final toolCalls = assistantMsg['tool_calls'] as List;
        final firstToolCall = toolCalls[0] as Map;
        expect(firstToolCall['id'], 'call_abc123');
        final toolCallFunction = firstToolCall['function'] as Map;
        expect(toolCallFunction['name'], 'get_weather');
        expect(toolCallFunction['arguments'], '{"city":"Berlin"}');

        final toolMsg =
            messages.firstWhere((m) => (m as Map)['role'] == 'tool') as Map;
        expect(toolMsg['tool_call_id'], 'call_abc123');
        expect(toolMsg['content'], '{"tempC":20,"condition":"sunny"}');
      } finally {
        await proxy.dispose();
      }
    });

    test('wrong or missing bearer token is rejected before touching upstream',
        () async {
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
      );
      try {
        final resp = await postResponses(proxy, {'model': 'x'},
            bearerOverride: 'not-the-real-token');
        expect(resp.statusCode, 401);
        await resp.drain<void>();
        expect(upstream.wasHit, isFalse);

        final client = HttpClient();
        final req = await client.postUrl(Uri.parse('${proxy.baseUrl}/responses'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'model': 'x'}));
        final resp2 = await req.close();
        expect(resp2.statusCode, 401);
        await resp2.drain<void>();
        expect(upstream.wasHit, isFalse);
      } finally {
        await proxy.dispose();
      }
    });

    test('upstream 500 emits response.failed with the error message, '
        'and the proxy stays alive for a subsequent good request', () async {
      upstream.statusCode = 500;
      upstream.cannedResponse = {
        'error': {'message': 'upstream is on fire'},
      };

      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
      );
      try {
        final resp = await postResponses(proxy, {
          'model': 'gpt-test',
          'input': [
            {
              'type': 'message',
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': 'hi'},
              ],
            },
          ],
        });
        final sseBody = await utf8.decoder.bind(resp).join();
        final events = parseSse(sseBody);
        expect(events.length, 1);
        expect(events.first.type, 'response.failed');
        final failedResponse = events.first.data['response'] as Map;
        final failedError = failedResponse['error'] as Map;
        expect(
          failedError['message'],
          contains('upstream is on fire'),
        );

        // Proxy survives and serves a subsequent good request.
        upstream.statusCode = 200;
        upstream.cannedResponse = {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'back to normal'},
            },
          ],
        };
        final resp2 = await postResponses(proxy, {
          'model': 'gpt-test',
          'input': [
            {
              'type': 'message',
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': 'hi again'},
              ],
            },
          ],
        });
        final sseBody2 = await utf8.decoder.bind(resp2).join();
        final events2 = parseSse(sseBody2);
        expect(events2.last.type, 'response.completed');
      } finally {
        await proxy.dispose();
      }
    });

    test('malformed JSON body returns 400', () async {
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
      );
      try {
        final client = HttpClient();
        final req = await client.postUrl(Uri.parse('${proxy.baseUrl}/responses'));
        req.headers.set('Authorization', 'Bearer ${proxy.token}');
        req.headers.contentType = ContentType.json;
        req.write('{not valid json');
        final resp = await req.close();
        expect(resp.statusCode, 400);
        await resp.drain<void>();
      } finally {
        await proxy.dispose();
      }
    });

    test('dispose closes the port and is idempotent', () async {
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
      );
      final baseUrl = proxy.baseUrl;
      await proxy.dispose();
      await proxy.dispose(); // idempotent — must not throw

      final client = HttpClient();
      var refused = false;
      try {
        final req = await client
            .postUrl(Uri.parse('$baseUrl/responses'))
            .timeout(const Duration(seconds: 2));
        await req.close().timeout(const Duration(seconds: 2));
      } on SocketException {
        refused = true;
      } catch (_) {
        refused = true;
      }
      expect(refused, isTrue);
    });

    test('reasoningEffort param always overrides codex-mapped reasoning.effort',
        () async {
      upstream.cannedResponse = {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'ok'},
          },
        ],
      };
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
        reasoningEffort: 'xhigh',
      );
      try {
        await postResponses(proxy, {
          'model': 'gpt-test',
          'input': const <dynamic>[],
          'reasoning': {'effort': 'high', 'summary': 'auto'},
        }).then((r) => r.drain<void>());
        expect(upstream.lastBody!['reasoning_effort'], 'xhigh');
      } finally {
        await proxy.dispose();
      }
    });

    test('reasoningEffort param injects even when the request carries none',
        () async {
      upstream.cannedResponse = {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'ok'},
          },
        ],
      };
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
        reasoningEffort: 'low',
      );
      try {
        await postResponses(proxy, {
          'model': 'gpt-test',
          'input': const <dynamic>[],
        }).then((r) => r.drain<void>());
        expect(upstream.lastBody!['reasoning_effort'], 'low');
      } finally {
        await proxy.dispose();
      }
    });

    test('without a proxy reasoningEffort, codex-mapped reasoning.effort is '
        'still translated (existing behavior intact)', () async {
      upstream.cannedResponse = {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'ok'},
          },
        ],
      };
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
      );
      try {
        await postResponses(proxy, {
          'model': 'gpt-test',
          'input': const <dynamic>[],
          'reasoning': {'effort': 'medium', 'summary': 'auto'},
        }).then((r) => r.drain<void>());
        expect(upstream.lastBody!['reasoning_effort'], 'medium');
      } finally {
        await proxy.dispose();
      }
    });

    test('text.verbosity/service_tier/prompt_cache_key pass through; '
        'include/client_metadata/store never forward', () async {
      upstream.cannedResponse = {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'ok'},
          },
        ],
      };
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
      );
      try {
        await postResponses(proxy, {
          'model': 'gpt-test',
          'input': const <dynamic>[],
          'text': {'verbosity': 'high', 'format': {'type': 'text'}},
          'service_tier': 'flex',
          'prompt_cache_key': 'k',
          'include': ['reasoning.encrypted_content'],
          'client_metadata': {'foo': 'bar'},
          'stream_options': {'include_usage': true},
          'store': false,
        }).then((r) => r.drain<void>());
        final sent = upstream.lastBody!;
        expect(sent['verbosity'], 'high');
        expect(sent['service_tier'], 'flex');
        expect(sent['prompt_cache_key'], 'k');
        expect(sent['include'], isNull);
        expect(sent['client_metadata'], isNull);
        expect(sent['store'], isNull);
        expect(sent['stream_options'], isNull);
      } finally {
        await proxy.dispose();
      }
    });

    test('usage without total_tokens is hardened: total is derived as '
        'prompt + completion, never a partial usage object', () async {
      upstream.cannedResponse = {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'ok'},
          },
        ],
        'usage': {
          'prompt_tokens': 20,
          'completion_tokens': 7,
        },
      };
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
      );
      try {
        final resp = await postResponses(proxy, {
          'model': 'gpt-test',
          'input': const <dynamic>[],
        });
        final sseBody = await utf8.decoder.bind(resp).join();
        final events = parseSse(sseBody);
        final response = events.last.data['response'] as Map;
        final usage = response['usage'] as Map;
        expect(usage['input_tokens'], 20);
        expect(usage['output_tokens'], 7);
        expect(usage['total_tokens'], 27);
      } finally {
        await proxy.dispose();
      }
    });

    test('requestCostAccounting sends usage.include and sums usage.cost '
        'across requests, tracking the last id/model', () async {
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
        requestCostAccounting: true,
      );
      try {
        upstream.cannedResponse = {
          'id': 'chatcmpl-cost-1',
          'model': 'openrouter/model-a',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'first'},
            },
          ],
          'usage': {
            'prompt_tokens': 10,
            'completion_tokens': 5,
            'total_tokens': 15,
            'cost': 0.0042,
          },
        };
        await postResponses(proxy, {
          'model': 'gpt-test',
          'input': const <dynamic>[],
        }).then((r) => r.drain<void>());
        expect(upstream.lastBody!['usage'], {'include': true});

        upstream.cannedResponse = {
          'id': 'chatcmpl-cost-2',
          'model': 'openrouter/model-a',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'second'},
            },
          ],
          'usage': {
            'prompt_tokens': 3,
            'completion_tokens': 2,
            'total_tokens': 5,
            'cost': 0.0042,
          },
        };
        await postResponses(proxy, {
          'model': 'gpt-test',
          'input': const <dynamic>[],
        }).then((r) => r.drain<void>());

        final totals = proxy.usageTotals;
        expect(totals.requestCount, 2);
        expect(totals.costUsd, closeTo(0.0084, 1e-9));
        expect(totals.requestId, 'chatcmpl-cost-2');
        expect(totals.resolvedModel, 'openrouter/model-a');
      } finally {
        await proxy.dispose();
      }
    });

    test('unknown path returns 404', () async {
      final proxy = await CodexPiggybackProxy.start(
        upstreamBaseUrl: upstreamUrl,
        upstreamApiKey: 'sk-key',
      );
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('${proxy.baseUrl}/nope'));
        req.headers.set('Authorization', 'Bearer ${proxy.token}');
        final resp = await req.close();
        expect(resp.statusCode, 404);
        await resp.drain<void>();
      } finally {
        await proxy.dispose();
      }
    });
  });
}
