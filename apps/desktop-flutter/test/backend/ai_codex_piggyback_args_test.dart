// Pins the pure argv builder for the codex-piggyback dispatch path
// (`_buildCodexPiggybackArgs`, exposed via `buildCodexPiggybackArgsForTesting`).
// This is the argv actually handed to `codex exec` when a review runs through
// the loopback proxy instead of a direct HTTP call — so the isolation trio and
// the manifold-provider wiring here are load-bearing for the "never worse off,
// never leaks the real key" guarantee described in ai.dart's
// `_runCodexPiggyback`.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';

void main() {
  group('buildCodexPiggybackArgsForTesting', () {
    final baseArgs = buildCodexPiggybackArgsForTesting(
      modelId: 'openrouter/some-model',
      proxyBaseUrl: 'http://127.0.0.1:54321/v1',
    );

    test('pins --sandbox read-only (load-bearing: without it codex inherits '
        'the user\'s ~/.codex trust level and can gain workspace write)', () {
      final idx = baseArgs.indexOf('--sandbox');
      expect(idx, greaterThanOrEqualTo(0));
      expect(baseArgs[idx + 1], 'read-only');
    });

    test('pins --ephemeral (load-bearing: no session files persisted to '
        'disk from this throwaway call)', () {
      expect(baseArgs, contains('--ephemeral'));
    });

    test('pins --ignore-user-config (load-bearing: the user\'s own '
        'config.toml — including any trust_level override — is never read)',
        () {
      expect(baseArgs, contains('--ignore-user-config'));
    });

    test('contains the manifold model-provider wiring', () {
      expect(baseArgs, contains('model_provider=manifold'));
      const expectedPairs = [
        'model_providers.manifold.name=Manifold',
        'model_providers.manifold.base_url=http://127.0.0.1:54321/v1',
        'model_providers.manifold.env_key=MANIFOLD_PROXY_TOKEN',
        'model_providers.manifold.request_max_retries=1',
        'model_providers.manifold.stream_max_retries=1',
        'model_providers.manifold.stream_idle_timeout_ms=900000',
      ];
      for (final pair in expectedPairs) {
        final idx = baseArgs.indexOf(pair);
        expect(idx, greaterThanOrEqualTo(0), reason: 'missing $pair');
        expect(baseArgs[idx - 1], '-c');
      }
      expect(baseArgs, contains('model_providers.manifold.wire_api=responses'));
    });

    test('ends with --json -', () {
      expect(baseArgs.length, greaterThanOrEqualTo(2));
      expect(baseArgs[baseArgs.length - 2], '--json');
      expect(baseArgs.last, '-');
    });

    test('includes model_reasoning_effort only when an effort maps', () {
      final withEffort = buildCodexPiggybackArgsForTesting(
        modelId: 'openrouter/some-model',
        proxyBaseUrl: 'http://127.0.0.1:54321/v1',
        reasoningEffort: 'high',
      );
      expect(withEffort, contains('model_reasoning_effort="high"'));

      expect(
        baseArgs.any((a) => a.startsWith('model_reasoning_effort')),
        isFalse,
      );
    });

    test('never contains token/key material', () {
      for (final arg in baseArgs) {
        expect(arg.contains('Bearer'), isFalse, reason: arg);
        // A crude API-key shape check: long unbroken alphanumeric runs are
        // what real provider keys look like (sk-..., sk-or-v1-..., etc.) —
        // none of the fixed literal args here should ever resemble one.
        expect(
          RegExp(r'^(sk-|Bearer )').hasMatch(arg),
          isFalse,
          reason: arg,
        );
      }
    });
  });
}
