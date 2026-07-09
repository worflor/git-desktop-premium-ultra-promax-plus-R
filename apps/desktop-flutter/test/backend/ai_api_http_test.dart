// Coverage for the HTTP request/response paths in lib/backend/ai_api_provider
// .dart — OpenAiCompatibleApiProvider.complete/listModels/_postJson and
// AnthropicApiProvider.complete/listModels — previously dark (17% coverage;
// ai_api_provider_test.dart only exercises the pure helper functions, never
// the `dart:io HttpClient` paths).
//
// ---------------------------------------------------------------------------
// INTERCEPTION STRATEGY — verified empirically, see the first test group.
// ---------------------------------------------------------------------------
//
// `dart:io`'s `HttpClient()` factory constructor checks `HttpOverrides
// .current` and, when set, delegates to `overrides.createHttpClient(...)`
// instead of constructing the real platform client. `HttpOverrides.runZoned`
// installs an override for the duration of an async body (including every
// nested await), so every `HttpClient()` call made anywhere inside
// ai_api_provider.dart's `complete`/`listModels`/`fetchKeyInfo` during that
// zone returns our fake instead of a real socket-backed client. No network
// I/O occurs.
//
// The fake ([FakeHttpClient]) implements the `HttpClient`/`HttpClientRequest`
// /`HttpClientResponse`/`HttpHeaders` interfaces just far enough to satisfy
// what ai_api_provider.dart actually calls (confirmed by reading the source):
// `idleTimeout`/`connectionTimeout` setters, `getUrl`/`postUrl`, `headers.set`
// /`.contentType`, `persistentConnection`, `write`, `close`, `statusCode`, and
// the `Stream<List<int>>` surface `response.transform(utf8.decoder).join()`
// needs (gotten for free by extending `Stream<List<int>>` and only
// implementing `listen` — every other Stream method has a default
// implementation built on it). Every other interface member is deliberately
// left unimplemented and forwarded through `noSuchMethod`, which is safe
// specifically because we've read every call site and know none of them are
// reached in the flows under test — reaching one would throw
// NoSuchMethodError and fail loudly, not silently misbehave.
//
// The empirical proof of interception: the first test group below points
// requests at `https://forge-parsing-http-test.invalid` — a host under the
// `.invalid` TLD, which RFC 2606 reserves as permanently unresolvable — and
// asserts the response carries our scripted marker text. A real network path
// would either hang (until the 10-minute request timeout) or fail DNS
// resolution and produce an `error` response, never our marker `text`. Getting
// the marker back proves the fake handler served the request, not a socket.
//
// ---------------------------------------------------------------------------
// SECURITY LAW — `_safeError` must never leak the API key into error text.
// ---------------------------------------------------------------------------
// Every error-returning scenario below re-checks this with a distinctive
// canary API key string that would be unmistakable if it leaked.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai_api_provider.dart';

// ---------------------------------------------------------------------------
// Fake HttpClient plumbing
// ---------------------------------------------------------------------------

/// What the fake observed about one request, handed to the [FakeResponder].
class FakeRequestInfo {
  final Uri uri;
  final String method;
  final Map<String, String> headers;
  final String body;
  const FakeRequestInfo({
    required this.uri,
    required this.method,
    required this.headers,
    required this.body,
  });
}

/// What the fake client should hand back for one request — either a
/// scripted (statusCode, body) response, or a thrown exception simulating a
/// transport failure ([FakeThrow]).
class FakeResult {
  final int? statusCode;
  final String? body;
  final Object? throwing;
  const FakeResult.respond(this.statusCode, this.body) : throwing = null;
  const FakeResult.throwing(this.throwing)
      : statusCode = null,
        body = null;
}

typedef FakeResponder = FutureOr<FakeResult> Function(FakeRequestInfo info);

/// Generic `noSuchMethod` fallback shared by every fake below: a *setter*
/// call to a property we haven't explicitly implemented (dart:io's
/// `HttpClient`/`HttpClientRequest`/`HttpHeaders` interfaces expose several
/// configuration knobs like `idleTimeout`, `connectionTimeout`, `contentType`,
/// `persistentConnection` whose exact declared nullability varies across SDK
/// versions and is irrelevant to the parsing logic under test) is silently
/// accepted and discarded rather than redeclared with a guessed type — ai_
/// api_provider.dart only ever WRITES these, never reads them back. Any
/// *getter* or *method* call we haven't explicitly stubbed still throws via
/// `super.noSuchMethod`, so an interface member the code under test actually
/// depends on but this fake forgot to implement fails loudly, not silently.
dynamic _fallbackNoSuchMethod(Object self, Invocation invocation) {
  if (invocation.isSetter) return null;
  // ignore: only_throw_errors
  throw NoSuchMethodError.withInvocation(self, invocation);
}

class FakeHttpHeaders implements HttpHeaders {
  final Map<String, String> stored = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    stored[name.toLowerCase()] = value.toString();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _fallbackNoSuchMethod(this, invocation);
}

class FakeHttpClientRequest implements HttpClientRequest {
  FakeHttpClientRequest(this.uri, this.method, this._responder);
  @override
  final Uri uri;
  @override
  final String method;
  final FakeResponder _responder;
  final StringBuffer _body = StringBuffer();

  @override
  final FakeHttpHeaders headers = FakeHttpHeaders();

  @override
  void write(Object? object) {
    _body.write(object);
  }

  @override
  Future<HttpClientResponse> close() async {
    final info = FakeRequestInfo(
      uri: uri,
      method: method,
      headers: Map.of(headers.stored),
      body: _body.toString(),
    );
    final result = await _responder(info);
    if (result.throwing != null) {
      // Simulate a transport-level failure the way a real HttpClient would
      // surface it — thrown out of `close()`, before any status/body exists.
      throw result.throwing!;
    }
    return FakeHttpClientResponse(result.statusCode!, result.body!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _fallbackNoSuchMethod(this, invocation);
}

class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  FakeHttpClientResponse(this.statusCode, String body)
      : _bytes = utf8.encode(body);
  @override
  final int statusCode;
  final List<int> _bytes;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _fallbackNoSuchMethod(this, invocation);
}

class FakeHttpClient implements HttpClient {
  FakeHttpClient(this._responder);
  final FakeResponder _responder;

  int requestCount = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestCount++;
    return FakeHttpClientRequest(url, 'GET', _responder);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    requestCount++;
    return FakeHttpClientRequest(url, 'POST', _responder);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _fallbackNoSuchMethod(this, invocation);
}

/// Runs [body] with every `HttpClient()` construction inside it — however
/// deeply nested — redirected to a fresh [FakeHttpClient] driven by
/// [responder]. No real socket is ever opened.
Future<T> withFakeHttp<T>(
  FakeResponder responder,
  Future<T> Function() body,
) {
  final client = FakeHttpClient(responder);
  return HttpOverrides.runZoned(
    body,
    createHttpClient: (SecurityContext? context) => client,
  );
}

/// A responder that always returns the same scripted (status, body).
FakeResponder fixedResponse(int status, String body) =>
    (info) => FakeResult.respond(status, body);

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const _canaryKey = 'sk-CANARY-DO-NOT-LEAK-9f3a7c21';

AiApiRequest _req({String? baseUrl, String prompt = 'hello'}) => AiApiRequest(
      prompt: prompt,
      model: 'test-model',
      credentials: AiApiCredentials(apiKey: _canaryKey, baseUrl: baseUrl),
    );

void main() {
  // =========================================================================
  // Interception proof — must run first and pass, or nothing below is valid.
  // =========================================================================
  group('HttpOverrides interception — empirical proof (no real network)',
      () {
    test(
      'a request to an RFC 2606 .invalid host is served by the fake, not '
      'a real socket',
      () async {
        const marker = 'INTERCEPTION-PROOF-4f1e';
        final body = jsonEncode({
          'choices': [
            {
              'message': {'content': marker}
            }
          ],
        });
        final result = await withFakeHttp(
          fixedResponse(200, body),
          () => OpenAiApiProvider().complete(
            _req(baseUrl: 'https://forge-parsing-http-test.invalid/v1'),
          ),
        );
        // A real network call to a `.invalid` host cannot possibly produce
        // our marker text — it would either fail DNS resolution (yielding
        // an `error`, never `text`) or hang until the 10-minute request
        // timeout. Getting the marker back proves the fake served this.
        expect(result.text, marker);
        expect(result.error, isNull);
      },
    );

    test('the fake client observed exactly one request and got the right '
        'method/headers/body wired through', () async {
      FakeRequestInfo? seen;
      final client = FakeHttpClient((info) {
        seen = info;
        return FakeResult.respond(200, jsonEncode({
          'choices': [
            {
              'message': {'content': 'ok'}
            }
          ],
        }));
      });
      await HttpOverrides.runZoned(
        () => OpenAiApiProvider().complete(_req()),
        createHttpClient: (context) => client,
      );
      expect(client.requestCount, 1);
      expect(seen, isNotNull);
      expect(seen!.method, 'POST');
      expect(seen!.uri.toString(),
          'https://api.openai.com/v1/chat/completions');
      expect(seen!.headers['authorization'], 'Bearer $_canaryKey');
      final sentBody = jsonDecode(seen!.body) as Map;
      expect(sentBody['model'], 'test-model');
      expect(sentBody['messages'], [
        {'role': 'user', 'content': 'hello'}
      ]);
    });
  });

  // =========================================================================
  // OpenAiCompatibleApiProvider.complete (via OpenAiApiProvider) — response
  // parsing.
  // =========================================================================
  group('OpenAiCompatibleApiProvider.complete — well-formed responses', () {
    test('chat completion -> correct text + token counts', () async {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': 'The answer is 42.'}
          }
        ],
        'usage': {'prompt_tokens': 12, 'completion_tokens': 7},
      });
      final result = await withFakeHttp(
        fixedResponse(200, body),
        () => OpenAiApiProvider().complete(_req()),
      );
      expect(result.text, 'The answer is 42.');
      expect(result.error, isNull);
      expect(result.inputTokens, 12);
      expect(result.outputTokens, 7);
    });

    test('determinism: identical scripted response -> identical parse',
        () async {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': 'stable'}
          }
        ],
        'usage': {'prompt_tokens': 1, 'completion_tokens': 2},
      });
      final a = await withFakeHttp(
          fixedResponse(200, body), () => OpenAiApiProvider().complete(_req()));
      final b = await withFakeHttp(
          fixedResponse(200, body), () => OpenAiApiProvider().complete(_req()));
      expect(a.text, b.text);
      expect(a.inputTokens, b.inputTokens);
      expect(a.outputTokens, b.outputTokens);
    });
  });

  group('OpenAiCompatibleApiProvider.complete — malformed robustness, never '
      'throws', () {
    Future<AiApiResponse> run(FakeResponder responder) => withFakeHttp(
          responder,
          () => OpenAiApiProvider().complete(_req()),
        );

    test('200 with garbage (non-JSON) body -> error, not a throw', () async {
      final result = await run(fixedResponse(200, 'not json at all {{{'));
      expect(result.text, isNull);
      expect(result.error, isNotNull);
      expect(result.error, contains('OpenAI'));
    });

    test('200 with empty body -> error, not a throw', () async {
      final result = await run(fixedResponse(200, ''));
      expect(result.text, isNull);
      expect(result.error, isNotNull);
    });

    test('200 with a top-level JSON array instead of an object -> error',
        () async {
      final result = await run(fixedResponse(200, '[]'));
      expect(result.text, isNull);
      expect(result.error, contains('invalid response'));
    });

    test('200 with missing `choices` -> empty-response error, zero tokens',
        () async {
      final result = await run(fixedResponse(200, jsonEncode({})));
      expect(result.text, isNull);
      expect(result.error, contains('empty response'));
      expect(result.inputTokens, 0);
      expect(result.outputTokens, 0);
    });

    test('200 with `choices: []` (empty array) -> empty-response error',
        () async {
      final result =
          await run(fixedResponse(200, jsonEncode({'choices': <dynamic>[]})));
      expect(result.text, isNull);
      expect(result.error, contains('empty response'));
    });

    test('200 with null message content -> empty-response error, usage '
        'still parsed', () async {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': null}
          }
        ],
        'usage': {'prompt_tokens': 3, 'completion_tokens': 0},
      });
      final result = await run(fixedResponse(200, body));
      expect(result.text, isNull);
      expect(result.error, contains('empty response'));
      expect(result.inputTokens, 3);
    });

    test('200 with whitespace-only content -> empty-response error',
        () async {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': '   '}
          }
        ],
      });
      final result = await run(fixedResponse(200, body));
      expect(result.error, contains('empty response'));
    });

    test('non-200 with an OpenAI-shaped error object -> message extracted',
        () async {
      final body = jsonEncode({
        'error': {'message': 'rate limit exceeded'}
      });
      final result = await run(fixedResponse(429, body));
      expect(result.text, isNull);
      expect(result.error, contains('rate limit exceeded'));
    });

    test('non-200 with a non-JSON body -> falls back to "HTTP <status>"',
        () async {
      final result = await run(fixedResponse(500, 'internal server error'));
      expect(result.error, contains('HTTP 500'));
    });

    test('non-200 with an empty body -> falls back to "HTTP <status>"',
        () async {
      final result = await run(fixedResponse(503, ''));
      expect(result.error, contains('HTTP 503'));
    });

    test('a thrown SocketException -> network-error message, no throw '
        'escapes', () async {
      final result = await run((info) => const FakeResult.throwing(
            SocketException('Failed host lookup',
                osError: OSError('Name or service not known', -2)),
          ));
      expect(result.error, isNotNull);
      expect(result.error, contains('network error'));
    });

    test('a thrown TimeoutException -> timeout message, no throw escapes',
        () async {
      final result = await run((info) => FakeResult.throwing(
            TimeoutException('timed out'),
          ));
      expect(result.error, contains('timed out'));
    });

    test('an HttpException on both retry attempts -> HTTP-error message, '
        'no throw escapes', () async {
      final result = await run(
        (info) => const FakeResult.throwing(HttpException('broken pipe')),
      );
      expect(result.error, isNotNull);
      expect(result.error, contains('HTTP error'));
    });
  });

  group('OpenAiCompatibleApiProvider.complete — API key never leaks into '
      'error text (security law)', () {
    Future<void> assertNoLeak(FakeResponder responder) async {
      final result =
          await withFakeHttp(responder, () => OpenAiApiProvider().complete(_req()));
      expect(result.error, isNotNull, reason: 'scenario should error');
      expect(result.error!.contains(_canaryKey), isFalse,
          reason: 'API key leaked into error text: ${result.error}');
    }

    test('non-200 error body does not leak the key', () async {
      await assertNoLeak(fixedResponse(
          401, jsonEncode({'error': {'message': 'invalid key'}})));
    });

    test('malformed JSON body does not leak the key', () async {
      await assertNoLeak(fixedResponse(200, '{not json'));
    });

    test('a SocketException does not leak the key', () async {
      await assertNoLeak((info) => const FakeResult.throwing(
            SocketException('boom'),
          ));
    });

    test('an HttpException does not leak the key', () async {
      await assertNoLeak(
          (info) => const FakeResult.throwing(HttpException('boom')));
    });

    test('a FormatException does not leak the key', () async {
      await assertNoLeak(
          (info) => const FakeResult.throwing(FormatException('boom')));
    });
  });

  // =========================================================================
  // OpenAiCompatibleApiProvider.listModels — response parsing.
  // =========================================================================
  group('OpenAiCompatibleApiProvider.listModels — well-formed responses',
      () {
    test('parses id/displayName/description/pricing/supportedParameters',
        () async {
      final body = jsonEncode({
        'data': [
          {
            'id': 'gpt-test',
            'name': 'GPT Test',
            'description': 'A test model',
            'pricing': {'prompt': '0.0000015', 'completion': 0.000002},
            'supported_parameters': ['reasoning_effort', 'temperature'],
          },
        ],
      });
      final models = await withFakeHttp(
        fixedResponse(200, body),
        () => OpenAiApiProvider().listModels(
            const AiApiCredentials(apiKey: _canaryKey)),
      );
      expect(models, hasLength(1));
      final m = models.single;
      expect(m.id, 'gpt-test');
      expect(m.displayName, 'GPT Test');
      expect(m.description, 'A test model');
      expect(m.promptPricePerToken, closeTo(0.0000015, 1e-12));
      expect(m.completionPricePerToken, closeTo(0.000002, 1e-12));
      expect(m.supportsReasoning, isTrue);
    });

    test('a model with no reasoning-related supported_parameters -> '
        'supportsReasoning false', () async {
      final body = jsonEncode({
        'data': [
          {
            'id': 'plain-model',
            'supported_parameters': ['temperature', 'top_p'],
          },
        ],
      });
      final models = await withFakeHttp(
        fixedResponse(200, body),
        () => OpenAiApiProvider()
            .listModels(const AiApiCredentials(apiKey: _canaryKey)),
      );
      expect(models.single.supportsReasoning, isFalse);
    });

    test('a model whose architecture output modality excludes text is '
        'filtered out', () async {
      final body = jsonEncode({
        'data': [
          {
            'id': 'image-only',
            'architecture': {'modality': 'text->image'},
          },
          {
            'id': 'text-model',
            'architecture': {'modality': 'text->text'},
          },
        ],
      });
      final models = await withFakeHttp(
        fixedResponse(200, body),
        () => OpenAiApiProvider()
            .listModels(const AiApiCredentials(apiKey: _canaryKey)),
      );
      expect(models.map((m) => m.id), ['text-model']);
    });
  });

  group('OpenAiCompatibleApiProvider.listModels — malformed robustness, '
      'never throws, empty list on failure', () {
    Future<List<AiApiModel>> run(FakeResponder responder) => withFakeHttp(
          responder,
          () => OpenAiApiProvider()
              .listModels(const AiApiCredentials(apiKey: _canaryKey)),
        );

    test('non-200 status -> empty list', () async {
      expect(await run(fixedResponse(401, '{}')), isEmpty);
    });

    test('200 with a non-JSON body -> empty list', () async {
      expect(await run(fixedResponse(200, 'garbage{{{')), isEmpty);
    });

    test('200 with a top-level array instead of object -> empty list',
        () async {
      expect(await run(fixedResponse(200, '[]')), isEmpty);
    });

    test('200 with missing `data` -> empty list', () async {
      expect(await run(fixedResponse(200, jsonEncode({}))), isEmpty);
    });

    test('200 with `data` as a Map instead of a List -> empty list',
        () async {
      expect(
        await run(fixedResponse(200, jsonEncode({'data': <String, dynamic>{}}))),
        isEmpty,
      );
    });

    test('entries with missing/blank/non-string id are skipped, valid '
        'entries still parsed', () async {
      final body = jsonEncode({
        'data': [
          {'name': 'no id here'},
          {'id': ''},
          {'id': 42},
          {'id': 'valid-model'},
        ],
      });
      final models = await run(fixedResponse(200, body));
      expect(models.map((m) => m.id), ['valid-model']);
    });

    test('non-Map entries in `data` are skipped without throwing', () async {
      final body = jsonEncode({
        'data': ['a-string', 42, null, true, {'id': 'ok'}]
      });
      final models = await run(fixedResponse(200, body));
      expect(models.map((m) => m.id), ['ok']);
    });

    test('a thrown exception mid-request -> empty list, no throw escapes',
        () async {
      expect(
        await run((info) => const FakeResult.throwing(SocketException('x'))),
        isEmpty,
      );
    });
  });

  // =========================================================================
  // AnthropicApiProvider.complete — different request/response shape.
  // =========================================================================
  group('AnthropicApiProvider.complete — well-formed responses', () {
    test('a text content block -> correct text + token counts', () async {
      final body = jsonEncode({
        'content': [
          {'type': 'text', 'text': 'Hello from Claude.'}
        ],
        'usage': {'input_tokens': 10, 'output_tokens': 5},
      });
      final result = await withFakeHttp(
        fixedResponse(200, body),
        () => AnthropicApiProvider().complete(_req()),
      );
      expect(result.text, 'Hello from Claude.');
      expect(result.error, isNull);
      expect(result.inputTokens, 10);
      expect(result.outputTokens, 5);
    });

    test('a non-text block (e.g. thinking) before the text block -> the '
        'text block still wins', () async {
      final body = jsonEncode({
        'content': [
          {'type': 'thinking', 'thinking': 'pondering...'},
          {'type': 'text', 'text': 'final answer'},
        ],
        'usage': {'input_tokens': 1, 'output_tokens': 1},
      });
      final result = await withFakeHttp(
        fixedResponse(200, body),
        () => AnthropicApiProvider().complete(_req()),
      );
      expect(result.text, 'final answer');
    });

    test('correct request shape: x-api-key header, anthropic-version, '
        'messages body', () async {
      FakeRequestInfo? seen;
      final client = FakeHttpClient((info) {
        seen = info;
        return FakeResult.respond(200, jsonEncode({
          'content': [
            {'type': 'text', 'text': 'ok'}
          ],
        }));
      });
      await HttpOverrides.runZoned(
        () => AnthropicApiProvider().complete(_req(prompt: 'ping')),
        createHttpClient: (context) => client,
      );
      expect(seen!.uri.toString(), 'https://api.anthropic.com/v1/messages');
      expect(seen!.headers['x-api-key'], _canaryKey);
      expect(seen!.headers['anthropic-version'], '2023-06-01');
      final sentBody = jsonDecode(seen!.body) as Map;
      expect(sentBody['messages'], [
        {'role': 'user', 'content': 'ping'}
      ]);
    });
  });

  group('AnthropicApiProvider.complete — malformed robustness, never '
      'throws', () {
    Future<AiApiResponse> run(FakeResponder responder) => withFakeHttp(
          responder,
          () => AnthropicApiProvider().complete(_req()),
        );

    test('200 with missing `content` -> empty-response error', () async {
      final result = await run(fixedResponse(200, jsonEncode({})));
      expect(result.text, isNull);
      expect(result.error, contains('empty response'));
    });

    test('200 with `content: []` -> empty-response error', () async {
      final result =
          await run(fixedResponse(200, jsonEncode({'content': <dynamic>[]})));
      expect(result.error, contains('empty response'));
    });

    test('200 with only non-text blocks -> empty-response error', () async {
      final body = jsonEncode({
        'content': [
          {'type': 'thinking', 'thinking': 'hmm'}
        ],
      });
      final result = await run(fixedResponse(200, body));
      expect(result.error, contains('empty response'));
    });

    test('200 with a non-JSON body -> invalid-response-format error',
        () async {
      final result = await run(fixedResponse(200, 'not json {{{'));
      expect(result.error, isNotNull);
      expect(result.error, contains('Anthropic'));
    });

    test('200 with a top-level array instead of object -> error', () async {
      final result = await run(fixedResponse(200, '[]'));
      expect(result.error, contains('invalid response'));
    });

    test('non-200 with an Anthropic-shaped error object -> message '
        'extracted', () async {
      final body = jsonEncode({
        'error': {'type': 'authentication_error', 'message': 'invalid x-api-key'}
      });
      final result = await run(fixedResponse(401, body));
      expect(result.error, contains('invalid x-api-key'));
    });

    test('non-200 with a non-JSON body -> falls back to "HTTP <status>"',
        () async {
      final result = await run(fixedResponse(529, 'overloaded'));
      expect(result.error, contains('HTTP 529'));
    });

    test('a thrown exception mid-request -> safe error, no throw escapes',
        () async {
      final result = await run(
          (info) => const FakeResult.throwing(SocketException('boom')));
      expect(result.error, isNotNull);
      expect(result.error, contains('network error'));
    });
  });

  group('AnthropicApiProvider.complete — API key never leaks into error '
      'text (security law)', () {
    Future<void> assertNoLeak(FakeResponder responder) async {
      final result = await withFakeHttp(
          responder, () => AnthropicApiProvider().complete(_req()));
      expect(result.error, isNotNull, reason: 'scenario should error');
      expect(result.error!.contains(_canaryKey), isFalse,
          reason: 'API key leaked into error text: ${result.error}');
    }

    test('non-200 error body does not leak the key', () async {
      await assertNoLeak(fixedResponse(
          403, jsonEncode({'error': {'message': 'forbidden'}})));
    });

    test('malformed JSON body does not leak the key', () async {
      await assertNoLeak(fixedResponse(200, '{{{'));
    });

    test('a thrown exception does not leak the key', () async {
      await assertNoLeak(
          (info) => const FakeResult.throwing(HttpException('boom')));
    });
  });

  // =========================================================================
  // AnthropicApiProvider.listModels — Anthropic's shape (`display_name`,
  // no pricing/supported_parameters).
  // =========================================================================
  group('AnthropicApiProvider.listModels — well-formed responses', () {
    test('parses id + display_name', () async {
      final body = jsonEncode({
        'data': [
          {'id': 'claude-x', 'display_name': 'Claude X'},
        ],
      });
      final models = await withFakeHttp(
        fixedResponse(200, body),
        () => AnthropicApiProvider()
            .listModels(const AiApiCredentials(apiKey: _canaryKey)),
      );
      expect(models, hasLength(1));
      expect(models.single.id, 'claude-x');
      expect(models.single.displayName, 'Claude X');
      // Anthropic models are always reasoning-capable per
      // allModelsSupportReasoning, independent of parsed fields.
      expect(AnthropicApiProvider().allModelsSupportReasoning, isTrue);
    });
  });

  group('AnthropicApiProvider.listModels — malformed robustness, never '
      'throws, empty list on failure', () {
    Future<List<AiApiModel>> run(FakeResponder responder) => withFakeHttp(
          responder,
          () => AnthropicApiProvider()
              .listModels(const AiApiCredentials(apiKey: _canaryKey)),
        );

    test('non-200 status -> empty list', () async {
      expect(await run(fixedResponse(401, '{}')), isEmpty);
    });

    test('200 with a non-JSON body -> empty list', () async {
      expect(await run(fixedResponse(200, 'not json')), isEmpty);
    });

    test('200 with missing `data` -> empty list', () async {
      expect(await run(fixedResponse(200, jsonEncode({}))), isEmpty);
    });

    test('200 with `data` as a top-level array (i.e. the whole body is a '
        'List, not the expected object) -> empty list', () async {
      expect(await run(fixedResponse(200, '[]')), isEmpty);
    });

    test('entries with missing/blank/non-string id are skipped', () async {
      final body = jsonEncode({
        'data': [
          {'display_name': 'no id'},
          {'id': ''},
          {'id': 7},
          {'id': 'claude-good'},
        ],
      });
      expect((await run(fixedResponse(200, body))).map((m) => m.id),
          ['claude-good']);
    });

    test('a thrown exception -> empty list, no throw escapes', () async {
      expect(
        await run((info) => const FakeResult.throwing(HttpException('x'))),
        isEmpty,
      );
    });
  });
}
