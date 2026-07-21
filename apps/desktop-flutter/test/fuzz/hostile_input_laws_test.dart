// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Law-based hostile-input properties for four small, high-blast-radius
// primitives that had zero (or near-zero) property coverage: the numeric
// JSON readers, the magic-byte content sniffer, ref-name encoding, and the
// BOM-preserving UTF-8 decoder. No goldens — every check below is a
// property that must hold for EVERY input the relevant generator can draw,
// not a pinned example.
//
// One property here is left deliberately FAILING: it demonstrates a real
// bug in `lib/backend/json_safety.dart` (see the "GENUINE BUG" test below).
// Per this task's own instructions, that property is not weakened or
// worked around — the minimized counterexample it prints is the report.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/json_safety.dart';
import 'package:git_desktop/backend/magic_bytes.dart';
import 'package:git_desktop/backend/utf8_exact.dart';

import '../support/gen.dart';
import '../support/prop.dart';

/// U+FEFF (byte-order mark), named rather than pasted as a raw invisible
/// literal — matches gen.dart's own convention for zero-width/control code
/// points (see its file-level comment).
const int _cpByteOrderMarkForRoundtrip = 0xFEFF;

// ---------------------------------------------------------------------------
// Shared JSON-ish generator (int, hostile double, String, bool, null,
// List, Map) — built entirely from the combinators added to gen.dart, so
// this file doubles as their exercise.
// ---------------------------------------------------------------------------

Gen<Object?> _genJsonScalar() {
  return genOneOf<Object?>([
    genConst<Object?>(null),
    genMap<int, Object?>(genInt(min: -(1 << 40), max: 1 << 40), (v) => v),
    genMap<double, Object?>(genDoubleHostile(), (v) => v),
    genMap<bool, Object?>((rng) => rng.nextBool(), (v) => v),
    genMap<String, Object?>(genUnicodeHostile(maxLen: 16), (v) => v),
  ]);
}

Gen<Object?> _genJsonIsh() {
  final scalar = _genJsonScalar();
  return genOneOf<Object?>([
    scalar,
    genMap<List<Object?>, Object?>(genList(scalar, maxLen: 5), (v) => v),
    genFlatMap<int, Object?>(
      genInt(min: 0, max: 5),
      (n) => genMap<List<Object?>, Object?>(
        genList(scalar, maxLen: n),
        (values) => <String, Object?>{
          for (var i = 0; i < values.length; i++) 'k$i': values[i],
        },
      ),
    ),
  ]);
}

/// Approximate int64 boundary, used only to tag coverage — not part of any
/// correctness assertion, so exact rounding of the literal doesn't matter.
const double _kInt64MaxAsDouble = 9223372036854775807.0;

void main() {
  // ===========================================================================
  // json_safety.dart — lib/backend/json_safety.dart
  // ===========================================================================
  group('json_safety.dart — totality over hostile doubles + JSON-ish values',
      () {
    test(
      'asIntOrNull / asDoubleOrNull / asIntOr never throw and stay '
      'well-typed over every non-finite / extreme-magnitude double '
      'genDoubleHostile() produces',
      () {
        forAll<double>(
          genDoubleHostile(),
          count: 400 * fuzzScale(),
          describe: 'json_safety totality — hostile doubles',
          requireCoverage: const {
            'nan': 0.03,
            'infinite': 0.03,
            'out-of-int64-range': 0.03,
          },
          check: (v) {
            if (v.isNaN) collect('nan');
            if (v.isInfinite) collect('infinite');
            if (v.isFinite && v.abs() > _kInt64MaxAsDouble) {
              collect('out-of-int64-range');
            }

            expect(() => asIntOrNull(v), returnsNormally);
            final i = asIntOrNull(v);
            expect(i, anyOf(isNull, isA<int>()));

            expect(() => asDoubleOrNull(v), returnsNormally);
            final d = asDoubleOrNull(v);
            expect(
              d,
              anyOf(isNull, predicate<double>((x) => x.isFinite, 'finite')),
            );

            expect(() => asIntOr(v, 7), returnsNormally);
            expect(asIntOr(v, 7), isA<int>());

            expect(() => asMapOrNull(v), returnsNormally);
            expect(() => asListOrNull(v), returnsNormally);
            expect(() => asStringOrNull(v), returnsNormally);
            expect(() => asBoolOrNull(v), returnsNormally);
          },
        );
      },
    );

    test(
      'GENUINE BUG in lib/backend/json_safety.dart — asIntOrNull silently '
      'CLAMPS an out-of-int64-range finite integral double to int64 '
      'min/max instead of returning null. e.g. asIntOrNull(1e308) does '
      'not throw and does not return null: it returns '
      '9223372036854775807 (int64 max), a fabricated value that has '
      "nothing to do with 1e308. The class doc comment's own stated "
      'principle — "truncating would fabricate a number the sender '
      'never transmitted" — is written about fractional truncation, but '
      'the exact same fabrication happens here via magnitude clamping, '
      "silently, with no way for a caller to tell a faithfully-decoded "
      'huge int from a clamped fabrication apart. Root cause: '
      'asIntOrNull calls `v.toInt()` whenever `v` is finite and '
      'integral, with no check that `v` actually lies within the exact '
      'int64-representable double range first — Dart\'s '
      '`double.toInt()` saturates to `9223372036854775807` / '
      '`-9223372036854775808` rather than throwing for an '
      'out-of-range-but-finite-and-integral value (confirmed empirically '
      'on the Dart VM, not assumed from docs). Left FAILING ON PURPOSE '
      'per the task instructions: do not weaken this property, do not '
      'patch lib/backend/json_safety.dart (out of scope for this file '
      'set).',
      () {
        forAll<double>(
          genDoubleHostile(),
          count: 400 * fuzzScale(),
          describe: 'json_safety asIntOrNull int64-clamp fabrication bug',
          check: (v) {
            if (!v.isFinite || v != v.roundToDouble()) {
              // Non-integral or non-finite: null is the documented, correct
              // answer and is not this law's concern.
              return;
            }
            final i = asIntOrNull(v);
            if (i == null) return; // also a legitimate answer
            expect(
              i.toDouble(),
              v,
              reason: 'asIntOrNull($v) returned $i, and ($i).toDouble() == '
                  '${i.toDouble()} != $v — a fabricated int64-clamp, not '
                  'the value the sender transmitted',
            );
          },
        );
      },
    );

    test(
      'asIntOrNull / asDoubleOrNull / asIntOr / asBoolOrNull / '
      'asStringOrNull / asMapOrNull / asListOrNull never throw over '
      'arbitrary JSON-ish values (int, hostile double, String, bool, '
      'null, List, Map)',
      () {
        forAll<Object?>(
          _genJsonIsh(),
          count: 400 * fuzzScale(),
          describe: 'json_safety totality — JSON-ish values',
          check: (v) {
            expect(() => asIntOrNull(v), returnsNormally);
            expect(() => asIntOr(v, 7), returnsNormally);
            expect(asIntOr(v, 7), isA<int>());
            expect(() => asDoubleOrNull(v), returnsNormally);
            expect(() => asDoubleOr(v, 1.5), returnsNormally);
            expect(() => asBoolOrNull(v), returnsNormally);
            expect(() => asStringOrNull(v), returnsNormally);
            expect(() => asMapOrNull(v), returnsNormally);
            expect(() => asListOrNull(v), returnsNormally);
          },
        );
      },
    );
  });

  // ===========================================================================
  // magic_bytes.dart — lib/backend/magic_bytes.dart
  // ===========================================================================
  group('magic_bytes.dart — probeContentClass laws', () {
    test('never throws for any header, including empty and 1-byte', () {
      forAll<Uint8List>(
        genOneOf<Uint8List>([
          genConst<Uint8List>(Uint8List(0)),
          genMap<int, Uint8List>(
            genInt(min: 0, max: 255),
            (b) => Uint8List.fromList([b]),
          ),
          genBytes(maxLen: 1),
          genFileHeaderBytes(),
          genBytes(maxLen: 400),
        ]),
        count: 400 * fuzzScale(),
        describe: 'magic_bytes totality',
        check: (bytes) {
          expect(() => probeContentClass(bytes), returnsNormally);
        },
      );
    });

    test('is a pure function: equal bytes -> equal (cls, formatName)', () {
      forAll<Uint8List>(
        genFileHeaderBytes(),
        count: 400 * fuzzScale(),
        describe: 'magic_bytes determinism',
        check: (bytes) {
          final a = probeContentClass(bytes);
          final b = probeContentClass(Uint8List.fromList(bytes));
          expect(b.cls, a.cls);
          expect(b.formatName, a.formatName);
        },
      );
    });

    test(
      'prefix determinism: once a header matches a class, appending any '
      'tail bytes never changes the match',
      () {
        forAll<(Uint8List, Uint8List)>(
          (rng) {
            final header = genFileHeaderBytes()(rng);
            final tail = genBytes(maxLen: 64)(rng);
            final extended = Uint8List.fromList([...header, ...tail]);
            return (header, extended);
          },
          count: 400 * fuzzScale(),
          describe: 'magic_bytes prefix determinism',
          check: (pair) {
            final (header, extended) = pair;
            final matched = probeContentClass(header);
            if (matched.cls == ContentClass.unknown) {
              return; // antecedent false — the law has nothing to say here
            }
            final extendedMatch = probeContentClass(extended);
            expect(
              extendedMatch.cls,
              matched.cls,
              reason: 'header=$header extended=$extended',
            );
            expect(extendedMatch.formatName, matched.formatName);
          },
        );
      },
    );

    test(
      'truncation: every recognized signature in fileHeaderMagicSignatures '
      'resolves to unknown when truncated below its own length — no '
      'genuine prefix collision was found across the signature table '
      '(hand-checked: no two entries in magic_bytes.dart share a common '
      'byte prefix at the same probe offset, so this holds without '
      'exception here, unlike e.g. a table that mixed TIFF-little/'
      'TIFF-big with an unrelated same-prefixed format)',
      () {
        for (final (name, magic) in fileHeaderMagicSignatures) {
          final full = probeContentClass(Uint8List.fromList(magic));
          expect(
            full.cls,
            isNot(ContentClass.unknown),
            reason: 'sanity check: the full $name signature must itself '
                'match',
          );
          for (var len = 0; len < magic.length; len++) {
            final truncated =
                probeContentClass(Uint8List.fromList(magic.sublist(0, len)));
            expect(
              truncated.cls,
              ContentClass.unknown,
              reason: '$name truncated to $len/${magic.length} bytes '
                  '(${magic.sublist(0, len)}) should be unknown, got '
                  '${truncated.cls}/${truncated.formatName}',
            );
          }
        }
      },
    );
  });

  // ===========================================================================
  // DeskPrStore.encodeBranch / decodeBranch — lib/backend/desk_pr_store.dart
  // ===========================================================================
  group('DeskPrStore.encodeBranch/decodeBranch — genBadRef laws', () {
    test(
      'encodeBranch either throws ArgumentError (only the documented '
      'empty-string case) or produces an encoding that decodeBranch '
      'restores exactly',
      () {
        forAll<String>(
          genBadRef(),
          count: 400 * fuzzScale(),
          describe: 'encodeBranch roundtrip over hostile refs',
          check: (branch) {
            String encoded;
            try {
              encoded = DeskPrStore.encodeBranch(branch);
            } on ArgumentError {
              expect(
                branch,
                isEmpty,
                reason: 'encodeBranch is only documented to throw on the '
                    'empty string',
              );
              return;
            }
            expect(DeskPrStore.decodeBranch(encoded), branch);
          },
        );
      },
    );

    test('encodeBranch is injective over sets of hostile refs', () {
      forAll<List<String>>(
        genList(genBadRef(), maxLen: 6),
        count: 300 * fuzzScale(),
        describe: 'encodeBranch injectivity over hostile ref sets',
        check: (refs) {
          final byEncoding = <String, String>{}; // encoding -> first original
          for (final r in refs) {
            String encoded;
            try {
              encoded = DeskPrStore.encodeBranch(r);
            } on ArgumentError {
              continue; // empty-string case: documented, not encodable
            }
            final prior = byEncoding[encoded];
            if (prior == null) {
              byEncoding[encoded] = r;
            } else {
              expect(
                prior,
                r,
                reason: 'encodeBranch collision: "$prior" and "$r" both '
                    'encode to "$encoded"',
              );
            }
          }
        },
      );
    });
  });

  // ===========================================================================
  // utf8_exact.dart — lib/backend/utf8_exact.dart
  // ===========================================================================
  group('utf8_exact.dart — utf8DecodeExact laws', () {
    test(
      'utf8DecodeExact(bytes, allowMalformed: true) never throws over '
      'arbitrary bytes',
      () {
        forAll<Uint8List>(
          genBytes(),
          count: 400 * fuzzScale(),
          describe: 'utf8DecodeExact totality over arbitrary bytes',
          check: (bytes) {
            expect(
              () => utf8DecodeExact(bytes, allowMalformed: true),
              returnsNormally,
            );
          },
        );
      },
    );

    test(
      'utf8DecodeExact(utf8.encode(s)) == s for hostile unicode strings, '
      'including 0..3 leading BOMs',
      () {
        forAll<String>(
          genFlatMap<int, String>(
            genInt(min: 0, max: 3),
            (k) => genMap<String, String>(
              genUnicodeHostile(maxLen: 24),
              (s) =>
                  String.fromCharCode(_cpByteOrderMarkForRoundtrip) * k + s,
            ),
          ),
          count: 400 * fuzzScale(),
          describe: 'utf8DecodeExact roundtrip with leading BOMs',
          check: (s) {
            final roundtripped = utf8DecodeExact(utf8.encode(s));
            expect(roundtripped, s);
          },
        );
      },
    );
  });
}
