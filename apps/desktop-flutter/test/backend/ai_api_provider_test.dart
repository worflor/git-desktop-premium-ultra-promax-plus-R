// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Law-based coverage for the pure functions in
// lib/backend/ai_api_provider.dart, previously untested. No network I/O —
// every function exercised here is synchronous and side-effect-free.

import 'dart:math' as math show pow, sqrt;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai_api_provider.dart';

import '../support/gen.dart';
import '../support/prop.dart';

// ---------------------------------------------------------------------------
// effectiveBaseUrl — security law
// ---------------------------------------------------------------------------

/// Independent definition of "loopback", per spec: host is exactly
/// `localhost`, `127.0.0.1`, or `::1`.
bool _isLoopbackHost(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

const List<String> _hostileBaseUrls = [
  '',
  ' ',
  '   ',
  'http://127.0.0.1.evil.com',
  'http://localhost.attacker.net',
  'https://x',
  'http://[::1]:8080',
  'HTTP://LOCALHOST',
  'http://127.1',
  ' http://localhost',
  'http://localhost',
  'http://127.0.0.1',
  'http://127.0.0.1:9999/v1',
  'http://evil.com',
  'Http://evil.com',
  'hTTp://evil.com',
  'HTTP://evil.com',
  'http://LOCALHOST',
  'http://LocalHost:1234',
  'https://evil.com',
  'ftp://127.0.0.1',
  'http://0.0.0.0',
  'http://localhost:8080/v1',
  'http://user@localhost',
  'http://localhost@evil.com',
];

/// Picks a hostile base URL verbatim, or mutates one with random ASCII
/// noise so the shrinker also gets to explore the neighbourhood of the
/// fixed pool rather than only the pool itself.
Gen<String> _genHostileBaseUrl() {
  final noise = genAscii(maxLen: 8);
  return (rng) {
    final base = rng.pick(_hostileBaseUrls);
    if (rng.nextBool()) return base;
    return rng.nextBool() ? '$base${noise(rng)}' : '${noise(rng)}$base';
  };
}

// ---------------------------------------------------------------------------
// AiApiModel.supportsReasoning — iff law
// ---------------------------------------------------------------------------

const List<String> _reasoningKeywords = [
  'reasoning',
  'reasoning_effort',
  'include_reasoning',
];
const List<String> _noiseParams = [
  'temperature',
  'top_p',
  'max_tokens',
  'stop',
  'seed',
  'logprobs',
];

/// Generates a supportedParameters set alongside an independently-tracked
/// bookkeeping flag for "does it contain a reasoning keyword" — the flag is
/// computed from the generator's own choices, not by re-deriving the
/// source's `.contains(...)` logic, so the `check` below is a genuine
/// external oracle.
Gen<({Set<String> params, bool expectReasoning})> _genSupportedParams() {
  return (rng) {
    final chosen = <String>{
      for (final k in _reasoningKeywords)
        if (rng.nextBool()) k,
    };
    final noiseCount = rng.intBetween(0, 4);
    final noise = <String>{
      for (var i = 0; i < noiseCount; i++) rng.pick(_noiseParams),
    };
    return (params: {...chosen, ...noise}, expectReasoning: chosen.isNotEmpty);
  };
}

void main() {
  group('effectiveBaseUrl — loopback-only http downgrade (security law)', () {
    for (final provider in aiApiProviderRegistry) {
      test(
        '${provider.id}: result is the default, or https, or loopback http '
        '— never cleartext http to a non-loopback host',
        () {
          forAll<String>(
            _genHostileBaseUrl(),
            describe: 'effectiveBaseUrl loopback law — ${provider.id}',
            count: 300,
            check: (url) {
              final creds = AiApiCredentials(apiKey: 'k', baseUrl: url);
              final result = provider.effectiveBaseUrl(creds);

              // The law is about the URL's SCHEME, and URI schemes are
              // case-insensitive (RFC 3986 §3.1) — so parse the scheme
              // rather than prefix-matching it. A `startsWith('http://')`
              // check here would wrongly flag `HTTP://localhost`, which is
              // a perfectly safe loopback URL the app is right to pass
              // through verbatim. (Checking the literal prefix is exactly
              // the bug that this property caught in the production code.)
              final scheme = Uri.tryParse(result)?.scheme.toLowerCase();
              final isDefault = result == provider.defaultBaseUrl;
              final isHttps = scheme == 'https';
              final isLoopbackHttp = scheme == 'http' && _isLoopbackHost(result);

              expect(
                isDefault || isHttps || isLoopbackHttp,
                isTrue,
                reason:
                    'baseUrl "$url" resolved to "$result" for provider '
                    '${provider.id} — not the provider default, not https, '
                    'and not loopback http. This is a cleartext-HTTP '
                    'downgrade bypass.',
              );
            },
          );
        },
      );
    }
  });

  group('effortFraction', () {
    test('exact golden-ratio power values for low/medium/high/xhigh/max',
        () {
      // Independent oracle: derive phi from its mathematical definition
      // (1+sqrt5)/2, not from the source's literal decimal constant.
      final phi = (1 + math.sqrt(5)) / 2;
      expect(effortFraction('low'), closeTo(1 / math.pow(phi, 3), 1e-9));
      expect(effortFraction('medium'), closeTo(1 / math.pow(phi, 2), 1e-9));
      expect(effortFraction('high'), closeTo(1 / phi, 1e-9));
      expect(effortFraction('xhigh'), 1.0);
      expect(effortFraction('max'), 1.0);
    });

    test('null for anything else, including null itself', () {
      for (final v in <String?>[null, '', 'LOW', 'ultra', 'medium ', '0']) {
        expect(effortFraction(v), isNull, reason: 'effortFraction($v)');
      }
    });

    test('effortLevels is exactly the canonical low->max order', () {
      expect(effortLevels, ['low', 'medium', 'high', 'xhigh', 'max']);
    });

    test('non-decreasing across effortLevels order; xhigh and max share the '
        'ceiling by design', () {
      final fractions = [for (final lvl in effortLevels) effortFraction(lvl)!];
      for (var i = 1; i < fractions.length; i++) {
        expect(fractions[i], greaterThanOrEqualTo(fractions[i - 1]),
            reason: 'effortFraction must never decrease along '
                'effortLevels order');
      }
      // Strictly increasing through low<medium<high<xhigh, then xhigh/max
      // sit at the same 1.0 ceiling ("as much effort as the API allows") —
      // pin that plateau explicitly rather than asserting a blanket strict
      // monotonic law that the source never promised.
      expect(fractions[0] < fractions[1], isTrue);
      expect(fractions[1] < fractions[2], isTrue);
      expect(fractions[2] < fractions[3], isTrue);
      expect(fractions[3], fractions[4]);
    });
  });

  group('AiApiModel.supportsReasoning', () {
    test('true iff supportedParameters contains reasoning, '
        'reasoning_effort, or include_reasoning', () {
      forAll(
        _genSupportedParams(),
        describe: 'AiApiModel.supportsReasoning iff law',
        check: (c) {
          final model = AiApiModel(id: 'm', supportedParameters: c.params);
          expect(model.supportsReasoning, c.expectReasoning,
              reason: 'params=${c.params}');
        },
      );
    });

    test('empty supportedParameters -> false', () {
      expect(const AiApiModel(id: 'm').supportsReasoning, isFalse);
    });
  });

  group('AiApiKeyInfo.fraction', () {
    test('null when limit is null, zero, or negative, or used is null', () {
      expect(const AiApiKeyInfo().fraction, isNull);
      expect(const AiApiKeyInfo(limit: 0, used: 5).fraction, isNull);
      expect(const AiApiKeyInfo(limit: -10, used: 5).fraction, isNull);
      expect(const AiApiKeyInfo(limit: 100).fraction, isNull);
    });

    test('otherwise (used/limit).clamp(0,1)', () {
      forAll<(double, double)>(
        (rng) => (
          genDouble(min: 0.01, max: 1e4)(rng),
          genDouble(min: -1e4, max: 1e4)(rng),
        ),
        describe: 'AiApiKeyInfo.fraction clamp law',
        check: (pair) {
          final limit = pair.$1;
          final used = pair.$2;
          final info = AiApiKeyInfo(limit: limit, used: used);
          final expected = (used / limit).clamp(0.0, 1.0);
          expect(info.fraction, expected);
        },
      );
    });
  });

  group('aiApiProviderById / registry', () {
    test('null for an unknown id', () {
      expect(aiApiProviderById('does-not-exist'), isNull);
    });

    test('returns the exact registry instance for every known id, and '
        'every registry id is unique', () {
      final ids = aiApiProviderRegistry.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'registry ids must be unique: $ids');
      for (final p in aiApiProviderRegistry) {
        expect(identical(aiApiProviderById(p.id), p), isTrue);
      }
    });
  });

  group('AiApiProvider.isReady', () {
    test('false for empty or whitespace-only keys', () {
      final provider = aiApiProviderRegistry.first;
      for (final key in ['', ' ', '   ', '\t', '\n', ' \t\n ']) {
        expect(provider.isReady(AiApiCredentials(apiKey: key)), isFalse,
            reason: 'key=${key.codeUnits}');
      }
    });

    test('true for a non-blank key', () {
      final provider = aiApiProviderRegistry.first;
      expect(
        provider.isReady(const AiApiCredentials(apiKey: 'sk-real-key')),
        isTrue,
      );
    });
  });
}
