// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Fuzz coverage for the guard between an arbitrary (possibly hostile) branch
// name and an escape out of the `refs/manifold/desks/*` namespace:
// `DeskPrStore.encodeBranch` / `decodeBranch` / `refFor`
// (lib/backend/desk_pr_store.dart, ~lines 24-96).
//
// Manifold stores PR/desk metadata under `refs/manifold/*`. If a branch name
// could ever encode to something that resolves as (or collides with)
// `refs/heads/*` / `refs/remotes/*`, a Manifold write could clobber a real
// branch. This file adds a large adversarial fuzz corpus on top of the fixed
// cases in test/backend/desk_pr_store_test.dart's "bijective branch
// encoding" group (~lines 368-404).
//
// THE CONTRACT (post B12/B13/B14 fix — determined by reading the source):
//   encodeBranch(branch):
//     1. Empty input throws ArgumentError — git itself rejects an empty
//        branch name, so no caller can legitimately produce one. (No
//        sentinel: a reserved tail would need a leading-`_` escape to stay
//        unforgeable, changing every real `_`-prefixed branch's ref — and
//        forcing a namespace migration — for an input that cannot exist.)
//        No trim: whitespace (including a BOM) is payload, not noise, and
//        encodes like any other character.
//     2. Otherwise walks `branch.runes` (real Unicode scalar values, so a
//        surrogate pair recombines into ONE astral rune instead of
//        shredding): letters/digits/`-`/`_` pass through literally, `%`
//        becomes `%25`, `/` passes through literally only when it is not
//        the first rune, not the last rune, and not immediately preceded by
//        another `/` in the source (otherwise `%2F`), and everything else —
//        including `.` — is UTF-8-encoded and each byte hex-escaped as
//        `%XX`.
//   decodeBranch is the exact mechanical inverse: it merges contiguous
//   `%XX` runs and decodes them via `utf8DecodeExact` (BOM-preserving),
//   leaving unescaped characters as-is.
//
//   So the round-trip law is the STRONG one over the whole legal domain:
//       decodeBranch(encodeBranch(s)) == s   for every non-empty string s.
//   And injectivity likewise:
//       encodeBranch(a) == encodeBranch(b)  =>  a == b   (a, b non-empty).
//
//   Every tail the OLD (pre-fix) encoder could actually store is a fixed
//   point of decode-then-re-encode under this scheme, so existing
//   refs/manifold/desks/* refs need no migration.
//
// This supersedes three real bugs the OLD scheme had (see
// docs/architecture/test-hardening-bug-dossier.md and
// project_test_hardening_swarm.md for the original writeups) — all fixed
// together, not worked around:
//   - B12: the encode loop walked UTF-16 code units instead of runes, so a
//     surrogate pair split into two lone surrogates, each independently
//     replaced with U+FFFD — every astral character (most emoji) collapsed
//     onto the identical `%EF%BF%BD%EF%BF%BD` marker. Fixed by iterating
//     `.runes` and UTF-8-encoding the whole rune at once.
//   - B13: `decodeBranch` called plain `utf8.decode` once per merged %XX
//     run, and Dart's `Utf8Decoder` silently strips a leading BOM from
//     whatever it decodes — so a BOM anywhere inside a branch name vanished
//     on decode even though encode had faithfully escaped it. Fixed by
//     decoding through `utf8DecodeExact` (lib/backend/utf8_exact.dart),
//     which re-attaches a stripped BOM run.
//   - B14: `branch.trim()` up front, leading/trailing slash-run stripping,
//     and the un-escaped `_empty` sentinel all silently collided distinct
//     branch names onto the same ref. Fixed by dropping the trim/strip
//     entirely (whitespace and boundary slashes now encode instead of being
//     discarded) and rejecting empty input outright (git forbids it), so
//     no sentinel exists to collide with.
//
// Namespace containment (law 2) and no-escape (law 3) hold unconditionally
// for every input tried — string concatenation with a fixed prefix, plus
// universal escaping, can't be defeated by any content the encode loop
// produces.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_issue_store.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';

import '../support/gen.dart';
import '../support/prop.dart';

// ---------------------------------------------------------------------------
// Oracles / helpers
// ---------------------------------------------------------------------------

// Note: no `_hasAstral` carve-out oracle here anymore — the FIXED
// `encodeBranch` (rune iteration instead of UTF-16 code units; see the
// file header for the B12 writeup) makes astral input part of the general
// round-trip/injectivity sweeps below rather than a domain that needs to be
// excluded from them.

String _repeat(String unit, int times) => List.filled(times, unit).join();

/// One string drawn from a rotating mix of three hostile/adversarial
/// generators, so every sweep below exercises all three shapes of
/// adversarial input without three times the boilerplate.
Gen<String> _combinedGen({int maxLen = 40}) {
  final hostile = genUnicodeHostile(maxLen: maxLen);
  final ascii = genAscii(maxLen: maxLen);
  final relPath = genRelPath();
  return (rng) {
    final s = switch (rng.intBetween(0, 2)) {
      0 => hostile(rng),
      1 => ascii(rng),
      _ => relPath(rng),
    };
    // encodeBranch's domain is non-empty strings (empty throws, pinned by
    // its own test) — substitute a minimal stand-in for an empty draw so
    // every law sweeps the legal domain.
    return s.isEmpty ? '-' : s;
  };
}

/// A multi-KB-scale variant — same token mix, many more tokens per draw —
/// for the "extremely long names" requirement.
Gen<String> _longGen() {
  final unit = _combinedGen(maxLen: 24);
  return (rng) {
    final buf = StringBuffer();
    final targetLen = rng.intBetween(2000, 6000);
    while (buf.length < targetLen) {
      buf.write(unit(rng));
      buf.write('-');
    }
    return buf.toString();
  };
}

/// Two SEQUENTIAL draws from [single] for the injectivity sweeps ("fuzz many
/// pairs"). `Rng.split()` no longer forks an independent sub-stream — it hands
/// back another handle onto the same recorded tape (so the shrinker can reach
/// these draws; see prop.dart's split() doc). The two draws are therefore
/// consecutive positions on one tape: still distinct (what a pair needs) and
/// still fully shrinkable, just not statistically independent. Generic so it
/// serves both the `String` pair-fuzzes (LAW 5) and the `int` pair-fuzz
/// (DeskIssueStore symmetry) below.
Gen<(T, T)> _pairGen<T>(Gen<T> single) {
  return (rng) {
    final a = single(rng.split());
    final b = single(rng.split());
    return (a, b);
  };
}

/// Metamorphic pair: `a` from [base], `b` = `a` with one boundary mutation
/// applied (leading/trailing space, tab, BOM, or `/`). Under the OLD scheme
/// these reliably manufactured collisions; under the FIXED scheme every
/// mutation must now produce a genuinely DISTINCT encoding (asserted below),
/// so this generator now serves as a targeted regression check for exactly
/// the boundary cases B14 used to collide.
Gen<(String, String)> _boundaryMutationPairGen(Gen<String> base) {
  const mutators = <String Function(String)>[
    _addLeadingSpace,
    _addTrailingSpace,
    _addLeadingTab,
    _addLeadingBom,
    _addLeadingSlash,
    _addTrailingSlash,
  ];
  return (rng) {
    final a = base(rng.split());
    final mutate = rng.pick(mutators);
    return (a, mutate(a));
  };
}

String _addLeadingSpace(String s) => ' $s';
String _addTrailingSpace(String s) => '$s ';
String _addLeadingTab(String s) => '\t$s';
String _addLeadingBom(String s) => '${String.fromCharCode(_cpByteOrderMark)}$s';
String _addLeadingSlash(String s) => '/$s';
String _addTrailingSlash(String s) => '$s/';

/// Metamorphic pair stressing the astral-shredding bug specifically: the
/// same surrounding context with two different astral characters swapped
/// in. Under the OLD scheme every astral character collapsed to the
/// identical two-replacement-char marker regardless of which one; under the
/// FIXED scheme (rune iteration + real UTF-8 encoding) these must now be
/// genuinely distinct.
Gen<(String, String)> _astralSwapPairGen() {
  final context = genAscii(maxLen: 12);
  const astralPool = [0x1F600, 0x1F525, 0x1F680, 0x1F4BB, 0x1F308, 0x1F469];
  return (rng) {
    final prefix = context(rng.split());
    final suffix = context(rng.split());
    final r = rng.split();
    final cp1 = r.pick(astralPool);
    var cp2 = r.pick(astralPool);
    while (cp2 == cp1) {
      cp2 = r.pick(astralPool);
    }
    return (
      '$prefix${String.fromCharCode(cp1)}$suffix',
      '$prefix${String.fromCharCode(cp2)}$suffix',
    );
  };
}

/// The full adversarial pair mix for the strict injectivity fuzz: mostly
/// independent random pairs (demonstrating the law DOES hold for unrelated
/// content — collisions are not everywhere), interleaved with the two
/// metamorphic generators that used to reliably manufacture real collisions
/// under the old, broken scheme.
Gen<(String, String)> _injectivityStressPairGen() {
  final independent = _pairGen(_combinedGen());
  final boundary = _boundaryMutationPairGen(_combinedGen());
  final astral = _astralSwapPairGen();
  return (rng) {
    final choice = rng.intBetween(0, 9);
    if (choice <= 2) return independent(rng);
    if (choice <= 7) return boundary(rng);
    return astral(rng);
  };
}

final RegExp _safeTailCharset = RegExp(r'^(?:[A-Za-z0-9_\-]|/|%[0-9A-F]{2})*$');

// ---------------------------------------------------------------------------
// Named adversarial corpus — hand-picked cases so a change to the random
// generators can never silently stop covering them.
// Anything invisible/combining/control/astral is built via
// `String.fromCharCode`, matching test/support/gen.dart's own convention
// (see its file header) rather than pasted as a raw literal.
// ---------------------------------------------------------------------------

const int _cpNul = 0x0000;
const int _cpBel = 0x0007;
const int _cpEsc = 0x001B;
const int _cpCombiningAcute = 0x0301;
const int _cpRightToLeftMark = 0x200F;
const int _cpZeroWidthSpace = 0x200B;
const int _cpByteOrderMark = 0xFEFF;
const int _cpGrinningFace = 0x1F600; // astral
const int _cpFire = 0x1F525; // astral, distinct codepoint
const int _cpRocket = 0x1F680; // astral, distinct codepoint

final List<String> _namedAdversarialCorpus = <String>[
  // Path-traversal shapes.
  '..',
  '../../refs/heads/main',
  r'..\..\escape-attempt',
  // Real-ref-name literals — must NOT resolve as themselves.
  'refs/heads/main',
  'refs/remotes/origin/main',
  'refs/tags/v1.0.0',
  // Ordinary multi-segment / plain names.
  'feat/sub/leaf',
  'main',
  'release/1.2.3',
  // (The empty string is NOT in this corpus: encodeBranch throws on it —
  // pinned by its own dedicated test below.)
  // Whitespace: leading, trailing, embedded, tab, newline-as-whitespace.
  ' leading-space',
  'trailing-space ',
  'mid dle-space',
  '\tleading-tab',
  'trailing-tab\t',
  '   ',
  // NUL, newlines/CR, C0 control.
  'a${String.fromCharCode(_cpNul)}b',
  'a\nb',
  'a\r\nb',
  'a\rb',
  'a${String.fromCharCode(_cpBel)}b',
  'a${String.fromCharCode(_cpEsc)}b',
  // '%' signs — the escaping must not itself be confusable.
  '%',
  '%%',
  '100%',
  '%2E',
  '%252E',
  'a%2Fb',
  // Unicode: ordinary visible, combining, RTL, zero-width, BOM, astral.
  'café-☃-日本語-brânch',
  'a${String.fromCharCode(_cpCombiningAcute)}b',
  '${String.fromCharCode(_cpRightToLeftMark)}rtl-name',
  '${String.fromCharCode(_cpZeroWidthSpace)}zwsp-name',
  '${String.fromCharCode(_cpByteOrderMark)}bom-name',
  'mid${String.fromCharCode(_cpByteOrderMark)}bom', // BOM NOT at a boundary
  String.fromCharCode(_cpGrinningFace),
  // Extremely long (multi-KB) names.
  _repeat('a', 4000),
  List.generate(20, (i) => 'seg-${_repeat('x', 200)}-$i').join('/'),
  // Slash-boundary / pure-slash / internal-double-slash classes.
  '/',
  '//',
  '///',
  'a/',
  '/a',
  'a//b',
  // Former sentinel — now just an ordinary branch name.
  '_empty',
  '_leading-underscore',
];

void main() {
  group('LAW 2 — namespace containment (crown safety law)', () {
    test('refFor(s) always starts with refPrefix, for the named corpus', () {
      for (final s in _namedAdversarialCorpus) {
        final ref = DeskPrStore.refFor(s);
        expect(ref, startsWith(DeskPrStore.refPrefix),
            reason: 'input=${s.codeUnits}');
      }
    });

    test('refFor(s) always starts with refPrefix, fuzzed', () {
      forAll(
        _combinedGen(),
        count: 1000 * fuzzScale(),
        describe: 'containment',
        check: (s) {
          expect(DeskPrStore.refFor(s), startsWith(DeskPrStore.refPrefix),
              reason: 'input=${s.codeUnits}');
        },
      );
    });

    test('refFor(s) always starts with refPrefix, extremely long names', () {
      forAll(
        _longGen(),
        count: 30 * fuzzScale(),
        describe: 'containment-long',
        check: (s) {
          expect(DeskPrStore.refFor(s), startsWith(DeskPrStore.refPrefix),
              reason: 'input length=${s.length}');
        },
      );
    });
  });

  group('LAW 3 — no escape into a real ref namespace', () {
    void assertNoEscape(String s) {
      final ref = DeskPrStore.refFor(s);
      expect(ref, isNot(startsWith('refs/heads/')), reason: 'input=$s');
      expect(ref, isNot(startsWith('refs/remotes/')), reason: 'input=$s');
      expect(ref, isNot(startsWith('refs/tags/')), reason: 'input=$s');
      expect(ref, isNot(equals('refs/heads/main')), reason: 'input=$s');
      expect(ref, isNot(equals('refs/remotes/origin/main')), reason: 'input=$s');
      final tail = ref.substring(DeskPrStore.refPrefix.length);
      expect(tail.contains('..'), isFalse,
          reason: 'encoded tail contains a literal ".." segment: $tail');
    }

    test('literal refs/heads/main (and friends) as a branch NAME stay contained', () {
      for (final s in _namedAdversarialCorpus) {
        assertNoEscape(s);
      }
    });

    test('no escape, fuzzed', () {
      forAll(
        _combinedGen(),
        count: 1000 * fuzzScale(),
        describe: 'no-escape',
        check: assertNoEscape,
      );
    });
  });

  group('LAW 4a — git ref-name charset (always holds, even for buggy content)', () {
    void assertSafeCharset(String s) {
      final ref = DeskPrStore.refFor(s);
      final tail = ref.substring(DeskPrStore.refPrefix.length);
      expect(_safeTailCharset.hasMatch(tail), isTrue,
          reason: 'tail used an unexpected char outside '
              '[A-Za-z0-9_-] | / | %XX: $tail (input=${s.codeUnits})');
    }

    test('named corpus', () {
      for (final s in _namedAdversarialCorpus) {
        assertSafeCharset(s);
      }
    });

    test('fuzzed, including the astral-mangled and long domains', () {
      forAll(_combinedGen(), count: 1000 * fuzzScale(), check: assertSafeCharset);
      forAll(_longGen(), count: 30 * fuzzScale(), check: assertSafeCharset);
    });
  });

  group('LAW 4b — no illegal ref-name shapes (empty components, dot rules)', () {
    void assertLegalShape(String s) {
      final ref = DeskPrStore.refFor(s);
      final tail = ref.substring(DeskPrStore.refPrefix.length);
      expect(tail.startsWith('/'), isFalse, reason: 'leading slash: $tail');
      expect(tail.endsWith('/'), isFalse, reason: 'trailing slash: $tail');
      expect(tail.contains('//'), isFalse, reason: 'empty component: $tail');
      expect(tail.isNotEmpty, isTrue, reason: 'empty tail for input=$s');
    }

    test('named corpus', () {
      for (final s in _namedAdversarialCorpus) {
        assertLegalShape(s);
      }
    });

    test('fuzzed, including the astral-mangled and long domains', () {
      forAll(_combinedGen(), count: 1000 * fuzzScale(), check: assertLegalShape);
      forAll(_longGen(), count: 30 * fuzzScale(), check: assertLegalShape);
    });
  });

  group('LAW 1 — roundtrip: decodeBranch(encodeBranch(s)) == s', () {
    test('holds for the named corpus, unconditionally', () {
      for (final s in _namedAdversarialCorpus) {
        final decoded = DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s));
        expect(decoded, s, reason: 'input=${s.codeUnits}');
      }
    });

    test('holds for fuzzed input, unconditionally (incl. astral)', () {
      forAll(
        _combinedGen(),
        count: 1000 * fuzzScale(),
        describe: 'roundtrip',
        check: (s) {
          final decoded = DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s));
          expect(decoded, s, reason: 'input=${s.codeUnits}');
        },
      );
    });

    test('holds for extremely long (multi-KB) input, unconditionally', () {
      forAll(
        _longGen(),
        count: 30 * fuzzScale(),
        describe: 'roundtrip-long',
        check: (s) {
          final decoded = DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s));
          expect(decoded, s, reason: 'input length=${s.length}');
        },
      );
    });

    // GENUINE BUG (now FIXED): this used to be the "naive/strong form" that
    // failed for hostile input under the old code (astral shredding). The
    // fix (rune iteration, empty-input rejection, no trim, no slash-strip,
    // BOM-preserving decode) makes this the actual contract over the
    // non-empty domain — no other carve-out, and asserted with none here.
    test('decodeBranch(encodeBranch(s)) == s (the strong form) holds even '
        'for hostile input', () {
      forAll(
        _combinedGen(),
        count: 300 * fuzzScale(),
        describe: 'strict-roundtrip-naive',
        check: (s) {
          expect(DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s)), s);
        },
      );
    });
  });

  group('LAW 5 — injectivity', () {
    // GENUINE BUG (now FIXED): under the old scheme this only held modulo a
    // trim/slash-strip `_normalize`. The fix removes that normalization
    // entirely, so plain equality is now the real, unconditional residual
    // property, asserted directly by the boundary-mutation pairs folded
    // into the full adversarial mix below — no separate `_normalize`
    // oracle needed anymore.
    //
    // GENUINE BUG (now FIXED): this used to be the "strict safety law" that
    // failed under the old code — distinct astral characters and boundary-
    // whitespace/slash variants collided onto the same encoded tail. The
    // fix makes injectivity hold unconditionally, so this now runs with no
    // carve-out and no skip.
    test(
      'encodeBranch(a) == encodeBranch(b) implies a == b, for the full '
      'adversarial pair mix (independent + boundary-mutation + astral-swap)',
      () {
        forAll(
          _injectivityStressPairGen(),
          count: 600 * fuzzScale(),
          describe: 'strict-injectivity-naive',
          check: (pair) {
            final (a, b) = pair;
            if (DeskPrStore.encodeBranch(a) == DeskPrStore.encodeBranch(b)) {
              expect(a, equals(b),
                  reason: 'collision: a=${a.codeUnits} b=${b.codeUnits} both '
                      '-> ${DeskPrStore.encodeBranch(a)}');
            }
          },
        );
      },
    );
  });

  group('encodeBranch/decodeBranch — deterministic canaries (post-fix '
      'behavior)', () {
    test('distinct astral characters no longer collide — FIXED (was B12)', () {
      final grinning = String.fromCharCode(_cpGrinningFace);
      final fire = String.fromCharCode(_cpFire);
      final rocket = String.fromCharCode(_cpRocket);
      expect(grinning, isNot(equals(fire)));
      expect(fire, isNot(equals(rocket)));

      final encGrinning = DeskPrStore.encodeBranch(grinning);
      final encFire = DeskPrStore.encodeBranch(fire);
      final encRocket = DeskPrStore.encodeBranch(rocket);
      expect(encFire, isNot(equals(encGrinning)));
      expect(encRocket, isNot(equals(encGrinning)));
      expect(DeskPrStore.refFor(grinning), isNot(equals(DeskPrStore.refFor(fire))));

      // Content round-trips exactly — no U+FFFD replacement.
      expect(DeskPrStore.decodeBranch(encGrinning), grinning);
      expect(DeskPrStore.decodeBranch(encFire), fire);
      expect(DeskPrStore.decodeBranch(encRocket), rocket);
    });

    test('a lone unpaired surrogate degrades without crashing', () {
      // Not produced by any generator here (always well-formed surrogate
      // pairs), but worth confirming the same code path fails safe (no
      // exception) rather than throwing on genuinely malformed String
      // content, which IS reachable if this code ever runs on data that
      // didn't originate from validated UTF-8.
      final loneSurrogate = String.fromCharCode(0xD83D);
      expect(
          () => DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(loneSurrogate)),
          returnsNormally);
    });

    test('leading/trailing whitespace (incl. BOM) no longer collides with '
        'the bare name — FIXED (was B14)', () {
      final bomMain = '${String.fromCharCode(_cpByteOrderMark)}main';
      final refMain = DeskPrStore.refFor('main');
      expect(DeskPrStore.refFor(' main'), isNot(equals(refMain)));
      expect(DeskPrStore.refFor('main '), isNot(equals(refMain)));
      expect(DeskPrStore.refFor('\tmain\n'), isNot(equals(refMain)));
      expect(DeskPrStore.refFor(bomMain), isNot(equals(refMain)));
      // And all of them round-trip exactly.
      for (final s in [' main', 'main ', '\tmain\n', bomMain]) {
        expect(DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s)), s);
      }
    });

    test('leading/trailing slash runs no longer collide with the bare name '
        '— FIXED (was B14)', () {
      final refA = DeskPrStore.refFor('a');
      expect(DeskPrStore.refFor('a/'), isNot(equals(refA)));
      expect(DeskPrStore.refFor('/a'), isNot(equals(refA)));
      expect(DeskPrStore.refFor('/a/'), isNot(equals(refA)));
      expect(DeskPrStore.refFor('//a//'), isNot(equals(refA)));
      for (final s in ['a/', '/a', '/a/', '//a//']) {
        expect(DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s)), s);
      }
    });

    test('a string of only slashes no longer collapses to an empty encoded '
        'tail — FIXED (was B14)', () {
      final encSlash = DeskPrStore.encodeBranch('/');
      expect(encSlash, isNotEmpty);
      expect(encSlash, '%2F');
      final encDoubleSlash = DeskPrStore.encodeBranch('//');
      expect(encDoubleSlash, isNot(equals(encSlash)));
      expect(DeskPrStore.encodeBranch('///'), isNot(equals(encDoubleSlash)));
      // The ref is now always non-empty past the prefix, and legal.
      expect(DeskPrStore.refFor('/'), isNot(equals(DeskPrStore.refPrefix)));
      for (final s in ['/', '//', '///']) {
        expect(DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s)), s);
      }
    });

    test('empty input throws; "_empty" is an ordinary branch name — '
        'FIXED (was B14, sentinel dropped entirely)', () {
      // Git rejects an empty branch name, so no caller can produce one —
      // encodeBranch fails loudly instead of inventing a sentinel tail
      // (which would have needed a leading-`_` escape to stay unforgeable,
      // changing every real `_`-prefixed branch's ref and forcing a
      // namespace migration for an impossible input).
      expect(() => DeskPrStore.encodeBranch(''), throwsArgumentError);
      // A whitespace-only string is no longer trimmed away — it round-trips
      // as itself.
      expect(DeskPrStore.decodeBranch(DeskPrStore.encodeBranch('   ')), '   ');
      // '_empty' and any other leading-underscore name pass through
      // untouched — byte-identical to the pre-redesign scheme's tails, so
      // no collision AND no migration surface.
      expect(DeskPrStore.encodeBranch('_empty'), '_empty');
      expect(DeskPrStore.encodeBranch('_foo'), '_foo');
      expect(DeskPrStore.decodeBranch('_empty'), '_empty');
    });

    test('an internal doubled slash now escapes instead of surviving — '
        'FIXED (was B14)', () {
      final enc = DeskPrStore.encodeBranch('a//b');
      expect(enc, 'a/%2Fb');
      expect(enc.contains('//'), isFalse,
          reason: 'no empty ref component can be produced anymore, so '
              '`git check-ref-format` can never reject this tail');
      expect(DeskPrStore.decodeBranch(enc), 'a//b');
    });

    test('a mid-string BOM (not at a trim boundary) now round-trips exactly '
        '— FIXED (was B13)', () {
      final bom = String.fromCharCode(_cpByteOrderMark);
      final withBom = 'ma${bom}in'; // BOM sandwiched inside a plain word
      final encoded = DeskPrStore.encodeBranch(withBom);
      expect(encoded, 'ma%EF%BB%BFin');
      expect(encoded, isNot(equals(DeskPrStore.encodeBranch('main'))));

      // decodeBranch now preserves it via utf8DecodeExact.
      final decoded = DeskPrStore.decodeBranch(encoded);
      expect(decoded, withBom,
          reason: 'utf8DecodeExact re-attaches a BOM byte run instead of '
              'letting Utf8Decoder silently strip it');
    });
  });

  group('numeric sibling — DeskIssueStore.refFor(int) — trivially safe, kept '
      'for symmetry', () {
    // Issue ids start at 1 — `LiveManifoldRef.issue` makes id <= 0
    // unrepresentable by construction (rejects it), so the domain fuzzed
    // here is the real one (>= 1); the id <= 0 rejection is pinned
    // separately below.
    test('refFor(id) is always contained under refs/manifold/issues/, fuzzed', () {
      forAll(
        genInt(min: 1, max: 1000000),
        count: 300 * fuzzScale(),
        describe: 'issue-ref-containment',
        check: (id) {
          final ref = DeskIssueStore.refFor(id);
          expect(ref, startsWith(DeskIssueStore.refPrefix));
          expect(ref, isNot(startsWith('refs/heads/')));
          expect(ref, isNot(startsWith('refs/remotes/')));
          expect(ref, isNot(startsWith('refs/tags/')));
        },
      );
    });

    test('refFor is injective over distinct ints, fuzzed', () {
      forAll(
        _pairGen(genInt(min: 1, max: 1000000)),
        count: 300 * fuzzScale(),
        describe: 'issue-ref-injectivity',
        check: (pair) {
          final (a, b) = pair;
          final sameRef = DeskIssueStore.refFor(a) == DeskIssueStore.refFor(b);
          expect(sameRef, equals(a == b), reason: 'a=$a b=$b');
        },
      );
    });

    test('refFor rejects a non-positive id (issue ids start at 1)', () {
      // The tightened contract: an out-of-range id is unrepresentable, not
      // silently mapped to a namespaced ref. Pins the precondition so a
      // future loosening is a conscious change, not an accident.
      expect(() => DeskIssueStore.refFor(0), throwsArgumentError);
      expect(() => DeskIssueStore.refFor(-1), throwsArgumentError);
      expect(() => DeskIssueStore.refFor(-1000000), throwsArgumentError);
    });
  });
}
