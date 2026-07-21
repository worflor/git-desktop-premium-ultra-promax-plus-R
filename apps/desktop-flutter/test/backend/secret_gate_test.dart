// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Truth-table + property coverage for the secret-egress gate in
// `lib/backend/ai.dart` — the two functions that stop a user's own secrets
// (`.env`, private keys, API tokens) from being shipped to a third-party LLM:
//
//   * [isSensitivePath]           — never send THIS file, by path;
//   * [detectLikelySecretInPrompt] — never send THIS body, by token shape.
//
// This gate is HONEST-EFFORT (regex-bypassable, path-shape-only). These tests
// pin its *positive knowledge* — the credential shapes it does recognize —
// and, just as importantly, guard the false-positive boundary: an ordinary
// code diff, a stack trace, or a committed `.env.example` placeholder must
// sail through untouched, or the gate becomes noise the user learns to click
// past.
//
// Style: this is mostly a deterministic truth table (plain `test()` — the
// right tool for a fixed set of known shapes), with a `forAll` fuzz pass used
// only for the one genuinely probabilistic claim: random ASCII / code-like
// text does not trip the gate.
//
// NO REAL CREDENTIAL appears in this file. Every "secret-shaped" token is
// synthesized by [_alnum] / [_upperAlnum] from a fixed alphabet — the right
// PREFIX and LENGTH to satisfy a detector's regex, with a body that is
// structurally a credential but semantically nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart'
    show detectLikelySecretInPrompt, isSensitivePath;

import '../support/gen.dart';
import '../support/prop.dart';

// ---------------------------------------------------------------------------
// Fake-token synthesis — shaped like a credential, made of nothing.
// ---------------------------------------------------------------------------

const String _base62 =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const String _upper36 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// [n] base62 chars, deterministically "scrambled" from a cheap integer hash
/// so the body looks high-entropy without pasting a literal blob (and without
/// any chance of a real key sneaking into source). `salt` decorrelates the
/// several tokens a single test builds.
String _alnum(int n, [int salt = 0]) {
  final codes = List<int>.generate(n, (i) {
    final h = (i * 2654435761) ^ (salt * 40503 + 17) ^ (i * i * 31);
    return _base62.codeUnitAt(h.abs() % _base62.length);
  });
  return String.fromCharCodes(codes);
}

/// As [_alnum] but restricted to `[0-9A-Z]` — for AWS `AKIA…` bodies.
String _upperAlnum(int n, [int salt = 0]) {
  final codes = List<int>.generate(n, (i) {
    final h = (i * 2246822519) ^ (salt * 668265263 + 5) ^ (i * i * 7);
    return _upper36.codeUnitAt(h.abs() % _upper36.length);
  });
  return String.fromCharCodes(codes);
}

// ---------------------------------------------------------------------------
// isSensitivePath — POSITIVE table
// ---------------------------------------------------------------------------

/// Paths that MUST be treated as sensitive. Grouped so a failure names the
/// class it broke. Includes nested dirs, Windows backslash forms, mixed case,
/// and the newly-added shapes (id_dsa/id_ecdsa, .netrc, .npmrc/.pypirc,
/// .pgpass, .ppk, .docker/config.json, .dockercfg, .git-credentials,
/// secring.gpg).
const List<String> _sensitivePositives = <String>[
  // .env family (real values) — but NOT the .env.example placeholders.
  '.env',
  '.env.local',
  '.env.production',
  'config/.env.prod',
  'apps/web/.env.local',
  r'app\config\.env',
  // SSH private keys — all four algorithms.
  'id_rsa',
  'id_dsa',
  'id_ecdsa',
  'id_ed25519',
  'path/to/id_ed25519',
  '.ssh/id_ecdsa',
  r'C:\Users\me\.ssh\id_rsa',
  // Cloud / VCS credential files.
  'credentials',
  '.aws/credentials',
  'home/user/.aws/credentials',
  '.git-credentials',
  'home/.git-credentials',
  'auth.json',
  'client_secret.json',
  // Shell / network / registry credential stores.
  '.netrc',
  '_netrc',
  'home/.netrc',
  '.npmrc',
  'project/.npmrc',
  '.pypirc',
  '.pgpass',
  // Docker registry auth — scoped to the .docker path / .dockercfg.
  '.docker/config.json',
  'home/user/.docker/config.json',
  '.dockercfg',
  // GnuPG secret keyring.
  'secring.gpg',
  '.gnupg/secring.gpg',
  // Key/cert file extensions.
  'server.pem',
  'private.key',
  'mykey.ppk',
  r'putty\session\key.ppk',
  'cert.p12',
  'cert.pfx',
  'terraform.tfvars',
  'cluster.kubeconfig',
  'kubeconfig',
  // Directory-scoped secret stores.
  'secrets/db-password',
  '.secrets/token',
  'private/api-notes',
  'infra/secrets/prod.yaml',
  // Case-insensitivity.
  'ID_RSA',
  '.ENV',
  'SECRETS/foo',
  'Server.PEM',
];

/// Paths that MUST NOT be flagged — ordinary source, config, and the
/// deliberately-shareable `.env.example` convention (see below). A false
/// positive here is a legitimate file the user can no longer get AI help on.
const List<String> _sensitiveNegatives = <String>[
  'README.md',
  'lib/main.dart',
  'src/index.ts',
  'test/foo_test.dart',
  'package.json',
  'pubspec.yaml',
  // Plain config.json is shareable everywhere EXCEPT the .docker path.
  'config.json',
  'settings/config.json',
  'docker-compose.yml',
  // .env placeholder convention — committed on purpose, no real values.
  'env.example', // no leading dot: never even reaches the .env branch
  '.env.example',
  '.env.sample',
  '.env.template',
  '.env.dist',
  'config/.env.example',
  // Ordinary files whose names merely rhyme with a secret shape.
  'src/keyboard_service.dart', // ends .dart, not .key
  'monkey.dart',
  'notes/private_thoughts.md', // "private_" is not the "private/" dir
  'image.png',
];

// ---------------------------------------------------------------------------
// detectLikelySecretInPrompt — POSITIVE cases (fake-but-shaped tokens)
// ---------------------------------------------------------------------------

/// `(description, secret-shaped token, expected label substring)`.
///
/// The expected substring is asserted against the label the detector returns,
/// so each row also documents which detector is supposed to fire. Several
/// rows exercise shapes the ORIGINAL table did not know at all (Stripe
/// `sk_live_`, GitLab `glpat-`, npm `npm_`, Slack `xapp-`/`xoxe-`, PGP block)
/// — on the pre-hardening code these would have returned null.
List<(String, String, String)> _tokenPositives() => <(String, String, String)>[
      ('AWS access key', 'AKIA${_upperAlnum(16, 1)}', 'AWS'),
      ('Google API key', 'AIza${_alnum(35, 2)}', 'Google'),
      ('GitHub token', 'ghp_${_alnum(36, 3)}', 'GitHub'),
      ('OpenAI key', 'sk-${_alnum(32, 4)}', 'OpenAI'),
      ('Anthropic key', 'sk-ant-${_alnum(32, 5)}', 'OpenAI'),
      // Underscore Stripe keys — the dash-anchored sk- pattern misses these.
      ('Stripe sk_live_', 'sk_live_${_alnum(24, 6)}', 'Stripe'),
      ('Stripe rk_live_', 'rk_live_${_alnum(24, 7)}', 'Stripe'),
      ('GitLab PAT', 'glpat-${_alnum(20, 8)}', 'GitLab'),
      ('npm token', 'npm_${_alnum(36, 9)}', 'npm'),
      ('Slack bot token', 'xoxb-${_alnum(24, 10)}', 'Slack'),
      ('Slack app-level', 'xapp-1-${_alnum(24, 11)}', 'Slack'),
      ('Slack refresh', 'xoxe-1-${_alnum(24, 12)}', 'Slack'),
      (
        'JWT',
        'eyJ${_alnum(16, 13)}.${_alnum(24, 14)}.${_alnum(24, 15)}',
        'JWT',
      ),
      (
        'RSA private key block',
        '-----BEGIN RSA PRIVATE KEY-----',
        'private key',
      ),
      (
        'PGP private key block',
        '-----BEGIN PGP PRIVATE KEY BLOCK-----',
        'PGP',
      ),
    ];

// ---------------------------------------------------------------------------
// detectLikelySecretInPrompt — NEGATIVE bodies (must return null)
// ---------------------------------------------------------------------------

/// A realistic multi-file unified diff. Mentions secrets by *concept*, uses
/// short hex and ordinary identifiers, but contains no token-shaped string.
const String _realCodeDiff = '''diff --git a/lib/backend/auth.dart b/lib/backend/auth.dart
index 3f2a1b0..9c4d5e6 100644
--- a/lib/backend/auth.dart
+++ b/lib/backend/auth.dart
@@ -12,7 +12,9 @@ class AuthService {
   Future<Session> signIn(String user, String password) async {
-    final token = await _api.login(user, password);
+    final token = await _api.login(user, password);
+    // NOTE: never log the token; store it in the OS keychain instead.
+    await _keychain.write('session', token);
     return Session(user: user, token: token);
   }
 }
diff --git a/README.md b/README.md
index 0000001..0000002 100644
--- a/README.md
+++ b/README.md
@@ -1,3 +1,5 @@
 # MyApp
+Set your API key in a local .env (see .env.example for the shape).
+Do not commit real credentials.
''';

const String _realStackTrace = '''Unhandled exception:
StateError: Bad state: No element
#0      _List.first (dart:core-patch/growable_array.dart:343:5)
#1      AuthService.signIn (package:myapp/backend/auth.dart:14:22)
#2      main (package:myapp/main.dart:8:19)
#3      _startIsolate.<anonymous closure> (dart:isolate-patch/isolate_patch.dart:297:19)''';

const String _realCommitMessage = '''auth: move session token into the OS keychain

Previously the login token was kept in memory and occasionally logged at
debug level. Store it in the platform keychain instead and scrub it from
error output. Fixes the "secret in logs" report from QA.

Co-Authored-By: A Dev <dev@example.com>''';

/// Assorted ordinary code lines — the corpus the false-positive property
/// asserts ZERO hits against. Deliberately packed with words and fragments
/// that *rhyme* with secrets (`sk`, `token`, `key`, `secret`, `AKIA`-ish
/// prose, `bearer`) without ever forming a real token shape.
const List<String> _ordinaryCodeLines = <String>[
  'final apiKey = config.readString("api_key");',
  'const secretName = "session-token"; // just a map key',
  'if (token.isEmpty) throw ArgumentError("missing token");',
  'authorizationHeader = "Bearer \$accessToken";',
  'sk = skipList.first; // sk is a local, not a key',
  'export AWS_PROFILE=dev',
  'let npm = "node package manager";',
  'glpat = "gitlab personal access token".split(" ");',
  'final xs = [x, o, x, b]; // not a slack token',
  '# See https://example.com/docs/keys for rotation policy',
  'password = getpass("DB password: ")',
  'private final KeyStore keystore = KeyStore.getInstance("PKCS12");',
  'eyebrow.raise(); // eyJ is not present here',
  'BEGIN TRANSACTION; -- not a PEM block',
  'ghost_process_id = spawn(); // ghp not ghp_',
];

// ---------------------------------------------------------------------------

void main() {
  group('isSensitivePath — positives', () {
    for (final path in _sensitivePositives) {
      test('flags: $path', () {
        expect(isSensitivePath(path), isTrue,
            reason: '$path should be gated as sensitive');
      });
    }
  });

  group('isSensitivePath — negatives (no false positives)', () {
    for (final path in _sensitiveNegatives) {
      test('allows: $path', () {
        expect(isSensitivePath(path), isFalse,
            reason: '$path is an ordinary/shareable file and must not be '
                'blocked from AI');
      });
    }
  });

  group('isSensitivePath — .env.example call', () {
    // DECISION: `.env.example` (and `.env.sample` / `.env.template` /
    // `.env.dist`, and the dot-less `env.example`) are the documented
    // convention for a committed placeholder file that carries KEY NAMES but
    // no real values. They are meant to be shared, so the gate lets them
    // through — while every real `.env*` stays blocked. This closes a
    // pre-existing false positive (the old `name.startsWith('.env')` flagged
    // `.env.example`).
    test('.env.example is allowed but .env.local is blocked', () {
      expect(isSensitivePath('.env.example'), isFalse);
      expect(isSensitivePath('config/.env.example'), isFalse);
      expect(isSensitivePath('env.example'), isFalse);
      expect(isSensitivePath('.env.local'), isTrue);
      expect(isSensitivePath('.env'), isTrue);
    });
  });

  group('isSensitivePath — path-normalization metamorphic law', () {
    // Every path the gate flags is flagged identically under POSIX vs Windows
    // separators and under case folding — the function normalizes both, so
    // all four presentations of a sensitive path must agree.
    for (final path in _sensitivePositives) {
      test('normalization agrees for: $path', () {
        final posix = path.replaceAll(r'\', '/');
        final windows = path.replaceAll('/', r'\');
        expect(isSensitivePath(posix), isTrue, reason: 'posix form');
        expect(isSensitivePath(windows), isTrue, reason: 'windows form');
        expect(isSensitivePath(path.toUpperCase()), isTrue,
            reason: 'upper-case form');
        expect(isSensitivePath(path.toLowerCase()), isTrue,
            reason: 'lower-case form');
      });
    }
  });

  group('detectLikelySecretInPrompt — positives (fake-but-shaped)', () {
    for (final (desc, token, expectedLabel) in _tokenPositives()) {
      test('detects $desc', () {
        // Embed the token in a realistic prompt body, not bare — the gate
        // must find it in context.
        final prompt = 'Please refactor this config:\n'
            'const value = "$token";\n'
            'and keep the behavior identical.';
        final hit = detectLikelySecretInPrompt(prompt);
        expect(hit, isNotNull, reason: '$desc ($token) should trip the gate');
        expect(hit, contains(expectedLabel),
            reason: 'label should identify the credential class');
      });
    }
  });

  group('detectLikelySecretInPrompt — token position invariance', () {
    // Metamorphic law: a flagged token is flagged wherever it sits in the
    // body and regardless of the surrounding line endings — the same secret
    // knowledge, independent of framing.
    for (final (desc, token, _) in _tokenPositives()) {
      test('$desc detected in any framing', () {
        final atStart = '$token then some trailing prose';
        final atEnd = 'leading prose then $token';
        final crlf = 'first line\r\nsecond = $token\r\nthird line';
        expect(detectLikelySecretInPrompt(atStart), isNotNull);
        expect(detectLikelySecretInPrompt(atEnd), isNotNull);
        expect(detectLikelySecretInPrompt(crlf), isNotNull);
      });
    }
  });

  group('detectLikelySecretInPrompt — negatives (must return null)', () {
    test('a real multi-file code diff is clean', () {
      expect(detectLikelySecretInPrompt(_realCodeDiff), isNull);
    });
    test('a stack trace is clean', () {
      expect(detectLikelySecretInPrompt(_realStackTrace), isNull);
    });
    test('a commit message is clean', () {
      expect(detectLikelySecretInPrompt(_realCommitMessage), isNull);
    });
    test('secret-adjacent ordinary code lines are all clean', () {
      for (final line in _ordinaryCodeLines) {
        expect(detectLikelySecretInPrompt(line), isNull,
            reason: 'ordinary line must not trip the gate: $line');
      }
    });
  });

  group('detectLikelySecretInPrompt — false-positive property', () {
    // ZERO false positives on the curated realistic-code corpus (deterministic
    // — this is the load-bearing guarantee).
    test('curated code corpus: zero hits', () {
      final joined = _ordinaryCodeLines.join('\n');
      expect(detectLikelySecretInPrompt(joined), isNull);
      for (final line in _ordinaryCodeLines) {
        expect(detectLikelySecretInPrompt(line), isNull);
      }
    });

    // Random ASCII and multi-line code-like text does not trip the gate. The
    // harness is seed-deterministic, so this is a fixed (non-flaky) check that
    // deepens under MANIFOLD_FUZZ. A token shape forming by chance from
    // uniform ASCII is astronomically unlikely; a hit here is a real
    // over-broad pattern, not noise.
    test('random ASCII / code-like text: no false positive', () {
      forAll<String>(
        genOneOf<String>(<Gen<String>>[
          genAscii(maxLen: 80),
          genMultilineText(maxLines: 10),
        ]),
        describe: 'secret-gate-no-false-positive',
        count: 200 * fuzzScale(),
        check: (text) {
          expect(detectLikelySecretInPrompt(text), isNull,
              reason: 'random non-secret text tripped the gate: '
                  '${text.replaceAll("\n", "\\n")}');
        },
      );
    });
  });
}
