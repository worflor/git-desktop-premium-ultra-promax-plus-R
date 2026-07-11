// Live contract test: drives the REAL `codex` binary through
// CodexPiggybackProxy against a mock chat/completions upstream, using the
// exact argv shape the piggyback dispatch builds. This is the empirical
// proof that codex 0.128+ accepts an inline `-c model_providers.*`
// definition, authenticates via env_key without touching auth.json, and
// parses our translated Responses SSE. Skips when codex isn't on PATH.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';
import 'package:git_desktop/backend/codex_piggyback_proxy.dart';

Future<String?> _resolveCodex() async {
  final probe = Platform.isWindows ? 'where' : 'which';
  try {
    final result = await Process.run(probe, ['codex']);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    String? candidate;
    if (!Platform.isWindows) {
      candidate = lines.first;
    } else {
      // `where` lists the extensionless npm shell shim first; only
      // .cmd/.exe/.bat are launchable via Process.start on Windows.
      for (final ext in ['.cmd', '.exe', '.bat']) {
        final hit = lines.where((l) => l.toLowerCase().endsWith(ext));
        if (hit.isNotEmpty) {
          candidate = hit.first;
          break;
        }
      }
    }
    if (candidate == null) return null;
    // Presence is not runnability: under WSL, Windows PATH interop exposes
    // the WINDOWS npm `codex` shim, which `which` finds but whose `exec node`
    // dies with exit 126 (Permission denied). Gate on an actual run.
    final version = await Process.run(candidate, ['--version'])
        .timeout(const Duration(seconds: 20));
    if (version.exitCode != 0) return null;
    return candidate;
  } catch (_) {
    return null;
  }
}

void main() {
  test('real codex exec round-trips through the piggyback proxy', () async {
    final codex = await _resolveCodex();
    if (codex == null) {
      markTestSkipped('codex binary not on PATH');
      return;
    }

    // Mock upstream: captures the chat/completions request codex's prompt
    // ends up as, returns a canned completion.
    Map<String, dynamic>? upstreamBody;
    String? upstreamAuth;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      upstreamAuth = req.headers.value(HttpHeaders.authorizationHeader);
      upstreamBody =
          jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'id': 'chatcmpl-live-1',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'PIGGYBACK-OK'},
            'finish_reason': 'stop',
          }
        ],
        'usage': {'prompt_tokens': 11, 'completion_tokens': 3, 'total_tokens': 14},
      }));
      await req.response.close();
    });

    final proxy = await CodexPiggybackProxy.start(
      upstreamBaseUrl: 'http://127.0.0.1:${upstream.port}/v1',
      upstreamApiKey: 'sk-or-live-secret',
    );

    try {
      final args = <String>[
        'exec', '--model', 'openai/gpt-test',
        '--sandbox', 'read-only',
        '--ephemeral',
        '--ignore-user-config',
        '--skip-git-repo-check',
        '-c', 'model_provider=manifold',
        '-c', 'model_providers.manifold.name=Manifold',
        '-c', 'model_providers.manifold.base_url=${proxy.baseUrl}',
        '-c', 'model_providers.manifold.env_key=MANIFOLD_PROXY_TOKEN',
        '-c', 'model_providers.manifold.wire_api=responses',
        '-c', 'model_providers.manifold.request_max_retries=1',
        '-c', 'model_providers.manifold.stream_max_retries=1',
        '-c', 'model_providers.manifold.stream_idle_timeout_ms=900000',
        '--json', '-',
      ];
      final process = await Process.start(
        codex,
        args,
        environment: {'MANIFOLD_PROXY_TOKEN': proxy.token},
        workingDirectory: Directory.systemTemp.path,
      );
      process.stdin.write('Reply with exactly the canned phrase.');
      await process.stdin.close();
      final stdout = await utf8.decoder.bind(process.stdout).join();
      final stderr = await utf8.decoder.bind(process.stderr).join();
      final exitCode = await process.exitCode;

      expect(exitCode, 0, reason: 'codex exited $exitCode\nstderr: $stderr\nstdout: $stdout');
      expect(stdout, contains('PIGGYBACK-OK'),
          reason: 'final message missing\nstderr: $stderr\nstdout: $stdout');

      // The prompt must have reached the upstream as a chat message, with
      // the real key attached by the proxy (never by codex).
      expect(upstreamAuth, 'Bearer sk-or-live-secret');
      expect(upstreamBody, isNotNull);
      expect(jsonEncode(upstreamBody), contains('canned phrase'));
      expect(upstreamBody!['model'], 'openai/gpt-test');
    } finally {
      await proxy.dispose();
      await upstream.close(force: true);
    }
  });

  test('codex piggyback survives the app runner (Windows .bat stdin wrapper)',
      () async {
    final codex = await _resolveCodex();
    if (codex == null) {
      markTestSkipped('codex binary not on PATH');
      return;
    }

    Map<String, dynamic>? upstreamBody;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      upstreamBody =
          jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'id': 'chatcmpl-live-2',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'WRAPPER-OK'},
            'finish_reason': 'stop',
          }
        ],
        'usage': {'prompt_tokens': 7, 'completion_tokens': 2, 'total_tokens': 9},
      }));
      await req.response.close();
    });

    final proxy = await CodexPiggybackProxy.start(
      upstreamBaseUrl: 'http://127.0.0.1:${upstream.port}/v1',
      upstreamApiKey: 'sk-or-live-secret',
      reasoningEffort: 'low',
    );

    try {
      // The app's own arg builder + the app's own process runner (which on
      // Windows rewrites the launch into a temp .bat with stdin redirection)
      // + the app's own JSONL parser: the full production chain minus the UI.
      final args = buildCodexPiggybackArgsForTesting(
        modelId: 'openai/gpt-test',
        proxyBaseUrl: proxy.baseUrl,
        reasoningEffort: 'low',
      );
      final result = await runObservedProcessForTesting(
        codex,
        args,
        timeout: const Duration(minutes: 2),
        stdinPayload: 'Answer with the canned wrapper phrase.',
        environment: {'MANIFOLD_PROXY_TOKEN': proxy.token},
      );

      expect(result, isNotNull, reason: 'app runner timed out');
      expect(result!.exitCode, 0,
          reason: 'codex exited ${result.exitCode}\nstderr: ${result.stderr}');
      final text = parseCodexJsonlForTesting(result.stdout);
      expect(text, 'WRAPPER-OK',
          reason: 'JSONL parse mismatch\nstdout: ${result.stdout}');
      expect(upstreamBody, isNotNull);
      expect(jsonEncode(upstreamBody), contains('canned wrapper phrase'));
      // Codex only carries `reasoning: {effort}` for model slugs its own
      // catalog flags as reasoning-capable — this fake slug is unknown to
      // it, so codex itself sends nothing. But the proxy now owns effort
      // injection (`reasoningEffort` passed to `start()` above always wins
      // over whatever codex mapped), so the value must arrive regardless of
      // whether codex recognized the model family.
      expect(upstreamBody!['reasoning_effort'], 'low');
      // The agentic loop must survive translation: codex's shell tool has to
      // reach the upstream as a chat `function` tool (the proxy drops
      // non-function tool types, and `local_shell` is only used for a few
      // OpenAI models). If this fails, piggyback silently degrades to plain
      // text generation for foreign models.
      final tools = upstreamBody!['tools'];
      expect(tools, isA<List<dynamic>>());
      expect((tools as List).isNotEmpty, isTrue,
          reason: 'codex sent no translatable tools: ${jsonEncode(upstreamBody)}');
      final toolNames = tools
          .whereType<Map<String, dynamic>>()
          .where((t) => t['type'] == 'function')
          .map((t) => (t['function'] as Map<String, dynamic>?)?['name'])
          .whereType<String>()
          .toList();
      expect(
        toolNames.any((n) => RegExp('shell|exec|command').hasMatch(n)),
        isTrue,
        reason: 'no shell-like function tool among: $toolNames',
      );
    } finally {
      await proxy.dispose();
      await upstream.close(force: true);
    }
  });
}
