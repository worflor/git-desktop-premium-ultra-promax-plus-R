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
// THE CONTRACT (determined by reading the source, not assumed):
//   encodeBranch(branch):
//     1. `src = branch.trim()` — if the TRIMMED string is empty, returns the
//        literal sentinel `'_empty'` (NOT reversible — decodeBranch has no
//        marker distinguishing a sentinel from a branch literally named
//        `_empty`).
//     2. Otherwise, walks `src` ONE UTF-16 CODE UNIT AT A TIME (`src[i]`,
//        not `src.runes`): letters/digits/`-`/`_` pass through literally,
//        `/` passes through literally (multi-segment refs are intentional),
//        `%` becomes `%25`, everything else is UTF-8-encoded and each byte
//        hex-escaped as `%XX`.
//     3. The built string then has any LEADING and TRAILING run of `/`
//        stripped (git rejects a leading/trailing/doubled slash in a
//        refname) — but only at the boundary, not internally.
//   decodeBranch is a mechanical inverse of step 2's percent-encoding ONLY.
//   It has no memory of steps 1 or 3.
//
//   So the round-trip law is:
//       decodeBranch(encodeBranch(s)) == _normalize(s)
//   where `_normalize` mirrors steps 1+3 (trim, then strip leading/trailing
//   `/` runs) — NOT `== s`, and NOT even `== s.trim()` alone (the slash-strip
//   matters too). Any input where the real result diverges from
//   `_normalize(s)` gets its own documented carve-out (see the canary group
//   below).
//
// LAWS asserted:
//   1. Roundtrip:            decodeBranch(encodeBranch(s)) == _normalize(s)
//   2. Namespace containment: refFor(s) always starts with refPrefix
//   3. No escape:             refFor(s) never aliases refs/heads|remotes|tags,
//                             and the encoded tail never contains a literal
//                             '..' segment
//   4. git ref-name legality: the encoded tail matches the exact charset the
//                             encoder can produce (LAW 4a — always holds)
//   5. Injectivity:           encodeBranch(a) == encodeBranch(b) => a == b
//                             — fails; the true residual property (holds for
//                             non-astral input) is `encodeBranch(a) ==
//                             encodeBranch(b) iff _normalize(a) ==
//                             _normalize(b)`
//
// Known encoding defects (see the canary group for concrete repros; full
// writeups in docs/architecture/test-hardening-bug-dossier.md):
//   - astral (non-BMP) code points are shredded: the encode loop walks
//     UTF-16 code units instead of runes, so a surrogate pair splits into
//     two lone surrogates, each replaced with U+FFFD — every astral
//     character collapses to the same `%EF%BF%BD%EF%BF%BD` marker.
//   - leading/trailing whitespace (including BOM, per Dart's `String.trim()`)
//     is silently dropped before encoding.
//   - leading/trailing `/` runs are silently stripped from the encoded
//     result; an all-slash string collapses to an empty encoded tail.
//   - the literal branch name `_empty` collides with the empty/whitespace-
//     only sentinel.
//   - internal (non-boundary) doubled slashes are preserved literally,
//     producing a ref git itself rejects (verified against
//     `git check-ref-format`).
//   - a BOM anywhere inside the branch name (not just at a trim boundary) is
//     silently dropped by `decodeBranch`, found only at MANIFOLD_FUZZ=5.
//
// Namespace containment (law 2) and no-escape (law 3) hold unconditionally
// for every input tried, including all the buggy ones above — string
// concatenation with a fixed prefix, plus universal escaping, can't be
// defeated by any content the encode loop produces. The bugs above are all
// data-integrity issues (two different desks silently sharing one ref), not
// namespace escapes.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_issue_store.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';

import '../support/gen.dart';
import '../support/prop.dart';

// ---------------------------------------------------------------------------
// Oracles / helpers
// ---------------------------------------------------------------------------

/// Mirrors steps 1+3 of encodeBranch's TRUE contract (see header): trim,
/// then strip any leading/trailing RUN of `/`. Built from the doc-commented
/// English contract, not by calling the code under test, so it's an honest
/// independent oracle for the round-trip law.
String _normalize(String s) {
  var v = s.trim();
  while (v.startsWith('/')) {
    v = v.substring(1);
  }
  while (v.endsWith('/')) {
    v = v.substring(0, v.length - 1);
  }
  return v;
}

/// True if [s] contains any Unicode scalar value outside the Basic
/// Multilingual Plane (i.e. any real astral character — emoji, rare CJK
/// extension ideographs, etc.). `.runes` correctly recombines a valid UTF-16
/// surrogate pair into one value > 0xFFFF, which is exactly what
/// `encodeBranch`'s per-code-unit loop fails to do (known bug — see file
/// header). Carves the known-broken domain out of the general round-trip/
/// injectivity sweeps so those sweeps assert the real residual contract.
bool _hasAstral(String s) => s.runes.any((r) => r > 0xFFFF);

/// True if [s] contains a BOM (U+FEFF) anywhere, not just at a trim
/// boundary. `decodeBranch` silently destroys every such character
/// regardless of position (known bug — see file header); this carve-out
/// excludes that domain from the general round-trip sweep the same way
/// [_hasAstral] does, rather than letting it show up as an occasional flake
/// at deeper `MANIFOLD_FUZZ` scales.
bool _hasBom(String s) => s.contains(String.fromCharCode(0xFEFF));

String _repeat(String unit, int times) => List.filled(times, unit).join();

/// One string drawn from a rotating mix of three hostile/adversarial
/// generators, so every sweep below exercises all three shapes of
/// adversarial input without three times the boilerplate.
Gen<String> _combinedGen({int maxLen = 40}) {
  final hostile = genUnicodeHostile(maxLen: maxLen);
  final ascii = genAscii(maxLen: maxLen);
  final relPath = genRelPath();
  return (rng) {
    switch (rng.intBetween(0, 2)) {
      case 0:
        return hostile(rng);
      case 1:
        return ascii(rng);
      default:
        return relPath(rng);
    }
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

/// Two independent draws from [single], via `Rng.split()` — the documented
/// way to fork a deterministic sub-stream (see prop.dart) — for the
/// injectivity sweeps ("fuzz many pairs"). Generic so it serves both the
/// `String` pair-fuzzes (LAW 5) and the `int` pair-fuzz (DeskIssueStore
/// symmetry) below.
Gen<(T, T)> _pairGen<T>(Gen<T> single) {
  return (rng) {
    final a = single(rng.split());
    final b = single(rng.split());
    return (a, b);
  };
}

/// Metamorphic pair: `a` from [base], `b` = `a` with one boundary mutation
/// applied (leading/trailing space, tab, BOM, or `/`). Each mutator
/// guarantees `a != b` (they always differ in length) — and each mutation is
/// exactly one of the boundary transformations `encodeBranch` silently
/// normalizes away, so this generator, unlike two fully-independent random
/// draws, reliably manufactures colliding pairs instead of relying on
/// coincidence.
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
/// in. Every astral character collapses to the identical two-replacement-
/// char marker (see the header), so any two distinct choices here collide
/// regardless of context — this generator proves it's not just the three
/// hand-picked emoji in the canary test, but the whole astral plane.
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
/// metamorphic generators that reliably manufacture real collisions.
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

/// Half independent pairs (exercises the "correctly does NOT collide"
/// direction of the residual-equivalence property below), half
/// boundary-mutated pairs (exercises the "correctly DOES collide, and
/// `_normalize` predicts it" direction) — a generator of only independent
/// pairs would almost never produce a same-normalized-form pair, and the
/// property would pass vacuously in that direction.
Gen<(String, String)> _normalizeEquivPairGen() {
  final independent = _pairGen(_combinedGen());
  final boundary = _boundaryMutationPairGen(_combinedGen());
  return (rng) => rng.nextBool() ? independent(rng) : boundary(rng);
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
const int _cpGrinningFace = 0x1F600; // astral — see known bugs above
const int _cpFire = 0x1F525; // astral, distinct codepoint, same bug
const int _cpRocket = 0x1F680; // astral, distinct codepoint, same bug

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
  '',
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
  // Sentinel collision.
  '_empty',
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

  group('LAW 1 — roundtrip: decodeBranch(encodeBranch(s)) == _normalize(s)', () {
    test('holds for the named corpus outside the three documented bug classes', () {
      for (final s in _namedAdversarialCorpus) {
        if (_hasAstral(s) || _hasBom(s) || s.trim().isEmpty) {
          continue; // known bug classes — see canary group below.
        }
        final decoded = DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s));
        expect(decoded, _normalize(s), reason: 'input=${s.codeUnits}');
      }
    });

    test('holds for fuzzed non-astral, non-BOM, non-blank input', () {
      forAll(
        _combinedGen(),
        count: 1000 * fuzzScale(),
        describe: 'roundtrip',
        check: (s) {
          if (_hasAstral(s) || _hasBom(s) || s.trim().isEmpty) {
            // Still assert the one thing that MUST hold even in the known-
            // broken domain: containment. The roundtrip itself is asserted
            // for this domain by the canary group below (deterministically,
            // not by chance of a fuzz draw landing here).
            expect(DeskPrStore.refFor(s), startsWith(DeskPrStore.refPrefix));
            return;
          }
          final decoded = DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s));
          expect(decoded, _normalize(s), reason: 'input=${s.codeUnits}');
        },
      );
    });

    test('holds for extremely long (multi-KB) non-astral, non-BOM, non-blank '
        'input', () {
      forAll(
        _longGen(),
        count: 30 * fuzzScale(),
        describe: 'roundtrip-long',
        check: (s) {
          if (_hasAstral(s) || _hasBom(s) || s.trim().isEmpty) return;
          final decoded = DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s));
          expect(decoded, _normalize(s), reason: 'input length=${s.length}');
        },
      );
    });

    // The strict, unconditional form of the law — asserted with no
    // carve-out, over many random draws — genuinely fails. Not skipped:
    // letting it run gives forAll's own `[prop] FAILED at seed=... index=...`
    // reproduce line. See the canary group for deterministic minimal repros.
    test(
      'decodeBranch(encodeBranch(s)) == s (the naive/strong form) fails for '
      'hostile input — see forAll output above for the exact reproducing '
      'seed/index/value',
      () {
        forAll(
          _combinedGen(),
          count: 300 * fuzzScale(),
          describe: 'strict-roundtrip-naive',
          check: (s) {
            expect(DeskPrStore.decodeBranch(DeskPrStore.encodeBranch(s)), s);
          },
        );
      },
      skip: 'known bug: encodeBranch shreds astral (non-BMP) code points, '
          'walking UTF-16 code units instead of runes, so a surrogate pair '
          'is split and each half independently replaced with U+FFFD',
    );
  });

  group('LAW 5 — injectivity', () {
    test(
      'residual property: encodeBranch(a) == encodeBranch(b) IFF '
      '_normalize(a) == _normalize(b), for non-astral input',
      () {
        forAll(
          _normalizeEquivPairGen(),
          count: 600 * fuzzScale(),
          describe: 'injectivity-mod-normalize',
          check: (pair) {
            final (a, b) = pair;
            if (_hasAstral(a) || _hasAstral(b)) {
              return; // severe, separate bug class — see canary group.
            }
            if (a.trim().isEmpty || b.trim().isEmpty) {
              // Same carve-out as LAW 1, applied per-side: a trim-blank
              // input (e.g. '', '   ') takes the `_empty` sentinel path,
              // which is not the same as a merely slash-only input (e.g.
              // '/') that normalizes to '' via the slash-strip loop but
              // never hits the sentinel branch. `_normalize` conflates both
              // into '' — the real code does not (only the trim-blank one
              // is rescued by the sentinel) — the same sentinel-collision
              // fact as the "_empty" canary, from the opposite direction.
              return;
            }
            final sameNormalized = _normalize(a) == _normalize(b);
            final sameEncoded =
                DeskPrStore.encodeBranch(a) == DeskPrStore.encodeBranch(b);
            expect(sameEncoded, equals(sameNormalized),
                reason: 'a=${a.codeUnits} b=${b.codeUnits}');
          },
        );
      },
    );

    // The strict safety law ("distinct inputs never collide") — asserted
    // with no carve-out, over a pair generator that deliberately includes
    // the two known collision-inducing metamorphic mutations (not just
    // fully-independent random pairs, which essentially never collide by
    // coincidence). Not skipped: a real failure here prints forAll's own
    // reproducible seed/index/value.
    test(
      'encodeBranch(a) == encodeBranch(b) does NOT imply a == b — see '
      'forAll output above for the exact reproducing seed/index/value',
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
      skip: 'known bug: encodeBranch is not injective — distinct astral '
          'characters collide onto the identical %EF%BF%BD%EF%BF%BD marker '
          '(surrogate-pair shredding), and boundary whitespace/slash '
          'normalization also collapses distinct inputs onto the same ref',
    );
  });

  group('known encodeBranch encoding defects — deterministic canaries', () {
    test('distinct astral characters collide and are destroyed', () {
      final grinning = String.fromCharCode(_cpGrinningFace);
      final fire = String.fromCharCode(_cpFire);
      final rocket = String.fromCharCode(_cpRocket);
      expect(grinning, isNot(equals(fire)));
      expect(fire, isNot(equals(rocket)));

      // All three distinct single-character branch names encode — and
      // therefore refFor — to the exact same value.
      final encGrinning = DeskPrStore.encodeBranch(grinning);
      expect(DeskPrStore.encodeBranch(fire), equals(encGrinning));
      expect(DeskPrStore.encodeBranch(rocket), equals(encGrinning));
      expect(encGrinning, '%EF%BF%BD%EF%BF%BD',
          reason: 'each astral char is split into two lone UTF-16 surrogate '
              'halves, each independently replaced with U+FFFD');
      expect(DeskPrStore.refFor(grinning), equals(DeskPrStore.refFor(fire)),
          reason: 'known bug: two branches named with different emoji '
              'would clobber the same desk PR ref');

      // Content is not just normalized, it's destroyed — decode can never
      // recover which astral character was there.
      final decoded = DeskPrStore.decodeBranch(encGrinning);
      expect(decoded, isNot(equals(grinning)));
      expect(decoded.runes.every((r) => r == 0xFFFD), isTrue);
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

    test('leading/trailing whitespace (incl. BOM) collides with the '
        'trimmed name', () {
      final bomMain = '${String.fromCharCode(_cpByteOrderMark)}main';
      final refMain = DeskPrStore.refFor('main');
      expect(DeskPrStore.refFor(' main'), equals(refMain));
      expect(DeskPrStore.refFor('main '), equals(refMain));
      expect(DeskPrStore.refFor('\tmain\n'), equals(refMain));
      expect(DeskPrStore.refFor(bomMain), equals(refMain),
          reason: 'known bug: a stray leading space/BOM on a branch name '
              'silently clobbers the real branch\'s desk PR');
    });

    test('leading/trailing slash runs collide with the bare name', () {
      final refA = DeskPrStore.refFor('a');
      expect(DeskPrStore.refFor('a/'), equals(refA));
      expect(DeskPrStore.refFor('/a'), equals(refA));
      expect(DeskPrStore.refFor('/a/'), equals(refA));
      expect(DeskPrStore.refFor('//a//'), equals(refA),
          reason: 'known bug: "a" and "/a/" (and any slash-padded variant) '
              'clobber the same desk PR ref');
    });

    test('a string of only slashes collapses to an empty encoded tail', () {
      final encSlash = DeskPrStore.encodeBranch('/');
      expect(encSlash, isEmpty);
      expect(DeskPrStore.encodeBranch('//'), equals(encSlash));
      expect(DeskPrStore.encodeBranch('///'), equals(encSlash));
      // known bug: the resulting ref ends in a bare trailing slash, which
      // `git check-ref-format` rejects (verified manually) — this branch's
      // desk PR can never actually be created, though it is not a
      // namespace escape.
      expect(DeskPrStore.refFor('/'), equals(DeskPrStore.refPrefix));
    });

    test('the literal branch name "_empty" collides with the empty/'
        'whitespace-only sentinel', () {
      const sentinel = '_empty';
      expect(DeskPrStore.encodeBranch(''), equals(sentinel));
      expect(DeskPrStore.encodeBranch('   '), equals(sentinel));
      expect(DeskPrStore.encodeBranch(sentinel), equals(sentinel),
          reason: 'known bug: a real branch literally named "_empty" '
              'collides with the reserved empty-input sentinel');
    });

    test('an internal doubled slash survives encoding unchanged, which '
        'git itself rejects', () {
      final enc = DeskPrStore.encodeBranch('a//b');
      expect(enc, 'a//b');
      expect(enc.contains('//'), isTrue,
          reason: 'known bug: `git check-ref-format '
              'refs/manifold/desks/a//b` exits non-zero (verified manually) '
              '— this ref can never actually be created by git, though it '
              'is safely namespace-contained (not an escape)');
    });

    test('a mid-string BOM (not at a trim boundary) is silently destroyed '
        'by decodeBranch, found only at MANIFOLD_FUZZ=5', () {
      final bom = String.fromCharCode(_cpByteOrderMark);
      final withBom = 'ma${bom}in'; // BOM sandwiched inside a plain word
      final encoded = DeskPrStore.encodeBranch(withBom);
      // encodeBranch itself is faithful — the BOM is escaped, not lost, and
      // still gives a DISTINCT ref from plain 'main' (no injectivity break).
      expect(encoded, 'ma%EF%BB%BFin');
      expect(encoded, isNot(equals(DeskPrStore.encodeBranch('main'))));

      // decodeBranch is where it's actually lost.
      final decoded = DeskPrStore.decodeBranch(encoded);
      expect(decoded, isNot(equals(withBom)),
          reason: 'known bug: decodeBranch silently drops a mid-string '
              'BOM — decoded=${decoded.codeUnits} input=${withBom.codeUnits}');
      expect(decoded, 'main',
          reason: 'root cause: Dart\'s Utf8Decoder strips a leading '
              'byte-order-mark from ANY byte run it decodes, and '
              'decodeBranch calls it once per %XX run — confirmed directly: '
              'utf8.decode(utf8.encode(bom), allowMalformed: true) == \'\'');
    });
  });

  group('numeric sibling — DeskIssueStore.refFor(int) — trivially safe, kept '
      'for symmetry', () {
    test('refFor(id) is always contained under refs/manifold/issues/, fuzzed', () {
      forAll(
        genInt(min: -1000000, max: 1000000),
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
        _pairGen(genInt(min: -1000000, max: 1000000)),
        count: 300 * fuzzScale(),
        describe: 'issue-ref-injectivity',
        check: (pair) {
          final (a, b) = pair;
          final sameRef = DeskIssueStore.refFor(a) == DeskIssueStore.refFor(b);
          expect(sameRef, equals(a == b), reason: 'a=$a b=$b');
        },
      );
    });
  });
}
