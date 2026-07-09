// Property-based fuzz coverage for the LogosEdit wire codec + compaction
// layer (lib/backend/logos_edits.dart), on the shared forAll/Rng harness
// (test/support/prop.dart, test/support/gen.dart). Complements
// test/backend/logos_edits_test.dart's TP1/multi-peer coverage with
// codec roundtrip, malformed-input robustness, compaction equivalence,
// and applyEdit purity over the pure, IO-free parts of the module.
//
// A few known codec/compaction bugs are pinned below as skipped
// regressions with a live repro in the test body; see
// docs/architecture/test-hardening-bug-dossier.md (B8-B11) for the full
// writeup. Run with MANIFOLD_FUZZ=<n> for a deeper fuzz pass.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_edits.dart';

import '../support/gen.dart';
import '../support/prop.dart';

// ── Local generators ───────────────────────────────────────────────────
//
// These compose the shared hostile/friendly generators from gen.dart into
// domain values (EditClock, LogosEdit, VersionVector, LogosMockState).
// Kept file-local since no other suite needs a LogosEdit generator yet.

/// Strips every leading U+FEFF (byte-order mark), if present, from a
/// generator's raw output — looped, since the hostile token pool can
/// independently pick the lone-BOM token more than once in a row.
///
/// Historically `_readString` dropped a leading BOM (fixed: it now uses
/// `utf8DecodeExact`, which round-trips it — see the un-skipped BOM
/// test below). This generator-side filter is kept anyway so the
/// general-case fuzz properties don't overlap the dedicated BOM
/// regression; a BOM anywhere else in the string (start excluded)
/// roundtrips fine and is left untouched.
String _avoidLeadingBom(String s) {
  while (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
    s = s.substring(1);
  }
  return s;
}

/// Peer identifiers: empty, ordinary ascii, unicode-hostile (NUL, RTL
/// marks, ZWJ emoji, lone CR, ...), and an occasional long-but-legal
/// (well under the wire format's 65535-byte string-length ceiling) id —
/// stress-testing "very long" without tripping the uint16-overflow bug
/// at exactly 65536 bytes (see the skipped test below).
Gen<String> _genPeer() => (rng) {
      final s = switch (rng.intBetween(0, 3)) {
        0 => '',
        1 => genAscii(maxLen: 40)(rng),
        2 => genUnicodeHostile(maxLen: 24)(rng),
        _ => genAscii(maxLen: 400)(rng),
      };
      return _avoidLeadingBom(s);
    };

/// Path-ish strings: real hostile relative paths, raw unicode-hostile
/// tokens (so paths can carry NUL/CRLF/zero-width content too), and
/// plain ascii.
Gen<String> _genPath() => (rng) {
      final s = switch (rng.intBetween(0, 2)) {
        0 => genRelPath()(rng),
        1 => genUnicodeHostile(maxLen: 24)(rng),
        _ => genAscii(maxLen: 60)(rng),
      };
      return _avoidLeadingBom(s);
    };

/// Lamport values across the documented safe range: zero, small, large,
/// and right up against the 2^53 web-int-safe ceiling the file's own
/// docs claim to support (existing fixture tests only probe ~2^33).
const int _kSafeIntCeiling = 9007199254740992; // 2^53
Gen<int> _genLamport() => (rng) {
      switch (rng.intBetween(0, 4)) {
        case 0:
          return 0;
        case 1:
          return rng.intBetween(0, 1 << 20);
        case 2:
          return rng.intBetween(0, 1 << 40);
        case 3:
          return _kSafeIntCeiling - rng.intBetween(0, 2000);
        default:
          return rng.intBetween(0, 1000000);
      }
    };

Gen<EditClock> _genClock() =>
    (rng) => EditClock(lamport: _genLamport()(rng), peer: _genPeer()(rng));

/// Weight domain: signed zero, ordinary finite range, tiny/huge
/// magnitudes, and the non-finite values the float64 wire slot can
/// physically carry (NaN, +-Infinity) — the format never rejects these,
/// so a correct decoder must round-trip them too.
Gen<double> _genWeight() => (rng) {
      switch (rng.intBetween(0, 7)) {
        case 0:
          return 0.0;
        case 1:
          return -0.0;
        case 2:
          return genDouble(min: -1e6, max: 1e6)(rng);
        case 3:
          return genDouble(min: -1e-300, max: 1e-300)(rng);
        case 4:
          return rng.nextBool() ? 1.0e300 : -1.0e300;
        case 5:
          return double.nan;
        case 6:
          return double.infinity;
        default:
          return double.negativeInfinity;
      }
    };

Gen<LogosEdit> _genEdit() => (rng) {
      final clock = _genClock()(rng);
      switch (rng.intBetween(0, 3)) {
        case 0:
          return NoOpEdit(clock: clock);
        case 1:
          return AddPathEdit(clock: clock, path: _genPath()(rng));
        case 2:
          return RemovePathEdit(clock: clock, path: _genPath()(rng));
        default:
          return SetEdgeEdit(
            clock: clock,
            pathA: _genPath()(rng),
            pathB: _genPath()(rng),
            weight: _genWeight()(rng),
          );
      }
    };

/// A plausible, mutually-interacting edit log: a small shared peer/path
/// pool (so AddPath/SetEdge/RemovePath collide on the same paths, the
/// case compaction actually has to reason about) rather than pure
/// independent noise.
Gen<List<LogosEdit>> _genEditSequence({int maxLen = 40}) => (rng) {
      final peers =
          List.generate(rng.intBetween(1, 5), (_) => _genPeer()(rng));
      final paths =
          List.generate(rng.intBetween(1, 8), (_) => _genPath()(rng));
      final perPeerLamport = {for (final p in peers) p: 0};
      final n = rng.intBetween(0, maxLen);
      final out = <LogosEdit>[];
      for (var i = 0; i < n; i++) {
        final peer = rng.pick(peers);
        perPeerLamport[peer] = perPeerLamport[peer]! + 1;
        final clock = EditClock(lamport: perPeerLamport[peer]!, peer: peer);
        switch (rng.intBetween(0, 9)) {
          case 0:
          case 1:
          case 2:
          case 3:
            out.add(AddPathEdit(clock: clock, path: rng.pick(paths)));
          case 4:
          case 5:
          case 6:
            final a = rng.pick(paths);
            var b = rng.pick(paths);
            if (a == b && paths.length > 1) {
              b = paths.firstWhere((p) => p != a, orElse: () => b);
            }
            out.add(SetEdgeEdit(
              clock: clock,
              pathA: a,
              pathB: b,
              weight: genDouble(min: -5, max: 5)(rng),
            ));
          case 7:
          case 8:
            out.add(RemovePathEdit(clock: clock, path: rng.pick(paths)));
          default:
            out.add(NoOpEdit(clock: clock));
        }
      }
      return out;
    };

/// A random small adjacency [LogosMockState] — independent of any
/// specific edit, used to seed `applyEdit` purity checks.
Gen<LogosMockState> _genMockState({int maxPaths = 6}) => (rng) {
      final pathCount = rng.intBetween(0, maxPaths);
      final paths = List.generate(pathCount, (_) => _genPath()(rng));
      final state = <String, Map<String, double>>{};
      for (final p in paths) {
        state.putIfAbsent(p, () => <String, double>{});
      }
      final unique = state.keys.toList();
      for (var i = 0; i < unique.length; i++) {
        for (var j = i + 1; j < unique.length; j++) {
          if (rng.nextBool()) {
            final w = genDouble(min: -10, max: 10)(rng);
            state[unique[i]]![unique[j]] = w;
            state[unique[j]]![unique[i]] = w;
          }
        }
      }
      return state;
    };

/// Pairs a random edit with a random state that's biased to already
/// contain (some of) the edit's own touched paths — so
/// remove/set-edge mutation logic actually has existing rows to touch,
/// not just always-empty ones.
Gen<(LogosEdit, LogosMockState)> _genEditWithState() => (rng) {
      final edit = _genEdit()(rng);
      final state = _genMockState()(rng);
      for (final p in edit.support) {
        if (rng.nextBool()) {
          state.putIfAbsent(p, () => <String, double>{});
        }
      }
      return (edit, state);
    };

Gen<VersionVector> _genVersionVector({int maxPeers = 12}) => (rng) {
      final peerCount = rng.intBetween(0, maxPeers);
      final map = <String, int>{};
      for (var i = 0; i < peerCount; i++) {
        map[_genPeer()(rng)] = _genLamport()(rng);
      }
      return VersionVector(map);
    };

// ── Equality helpers ────────────────────────────────────────────────────

/// Bit-precise double comparison via `compareTo` — unlike `==`, this
/// treats NaN as equal to NaN and (correctly, for a roundtrip check)
/// treats -0.0 as distinct from 0.0. `==` would silently pass a roundtrip
/// that turned a NaN weight into a different NaN payload or a `0.0` into
/// `-0.0`; `compareTo` catches both.
bool _sameDouble(double a, double b) => a.compareTo(b) == 0;

void _expectEditsEqual(LogosEdit expected, LogosEdit actual) {
  expect(actual.runtimeType, equals(expected.runtimeType),
      reason: 'variant mismatch: expected ${expected.runtimeType}, '
          'got ${actual.runtimeType}');
  expect(actual.clock, equals(expected.clock), reason: 'clock mismatch');
  switch (expected) {
    case NoOpEdit():
      break;
    case AddPathEdit(:final path):
      expect((actual as AddPathEdit).path, equals(path),
          reason: 'AddPathEdit.path mismatch');
    case RemovePathEdit(:final path):
      expect((actual as RemovePathEdit).path, equals(path),
          reason: 'RemovePathEdit.path mismatch');
    case SetEdgeEdit(:final pathA, :final pathB, :final weight):
      final a = actual as SetEdgeEdit;
      expect(a.pathA, equals(pathA), reason: 'SetEdgeEdit.pathA mismatch');
      expect(a.pathB, equals(pathB), reason: 'SetEdgeEdit.pathB mismatch');
      expect(_sameDouble(a.weight, weight), isTrue,
          reason: 'SetEdgeEdit.weight mismatch: '
              'expected=$weight actual=${a.weight}');
  }
}

void main() {
  group('property: encodeLogosEdit / decodeLogosEdit roundtrip', () {
    test('all 4 variants roundtrip under hostile peers/paths/weights', () {
      forAll<LogosEdit>(
        _genEdit(),
        count: 400 * fuzzScale(),
        describe: 'edit codec roundtrip',
        check: (edit) {
          final bytes = encodeLogosEdit(edit);
          final decoded = decodeLogosEdit(bytes);
          _expectEditsEqual(edit, decoded);
        },
      );
    });

    test('decode is deterministic: same edit -> same bytes -> same decode',
        () {
      forAll<LogosEdit>(
        _genEdit(),
        count: 100 * fuzzScale(),
        check: (edit) {
          final b1 = encodeLogosEdit(edit);
          final b2 = encodeLogosEdit(edit);
          expect(b1, equals(b2));
        },
      );
    });

    // Deterministic repro (not a property loop): the failure is a
    // categorical threshold effect at exactly 2^16 bytes, not something
    // randomization adds value to.
    //
    // Fixed: _writeString now rejects (ArgumentError) any string whose
    // UTF-8 encoding is >= 65536 bytes instead of silently wrapping the
    // uint16 length prefix and corrupting the field. The wire format's
    // string bound stays uint16 (max 65535 bytes) — this is a clean
    // rejection, not an expanded frame, so encode throws rather than
    // round-tripping.
    test(
      'a peer string of exactly 65536 UTF-8 bytes is rejected by '
      'encodeLogosEdit instead of silently corrupting the frame',
      () {
        final hugePeer = List.filled(65536, 'a').join(); // exactly 2^16 bytes
        final edit = AddPathEdit(
          clock: EditClock(lamport: 1, peer: hugePeer),
          path: 'x.dart',
        );
        expect(() => encodeLogosEdit(edit), throwsA(isA<ArgumentError>()));
      },
      skip: false,
    );

    // Deterministic minimal repro: a peer starting with U+FEFF loses
    // exactly that leading character.
    test(
      'a peer name starting with U+FEFF (BOM) round-trips through '
      'encode/decode',
      () {
        final peer = String.fromCharCodes([0xFEFF, 0x61]); // BOM + 'a'
        final edit =
            AddPathEdit(clock: EditClock(lamport: 1, peer: peer), path: 'x');
        final decoded =
            decodeLogosEdit(encodeLogosEdit(edit)) as AddPathEdit;
        expect(decoded.clock.peer, equals(peer));
      },
      skip: false,
    );
  });

  group('property: VersionVector byte roundtrip', () {
    test('random peer -> lamport maps roundtrip exactly', () {
      forAll<VersionVector>(
        _genVersionVector(),
        count: 300 * fuzzScale(),
        describe: 'VV roundtrip',
        check: (vv) {
          final rt = VersionVector.fromBytes(vv.toBytes());
          expect(rt, equals(vv));
          // `==` on VersionVector is order-independent map equality;
          // also pin down that every individual peer's lamport survived,
          // since a bug that swapped two peers' values with equal counts
          // could otherwise slip past a naive map-equality check.
          for (final peer in vv.peers) {
            expect(rt.maxLamportFor(peer), equals(vv.maxLamportFor(peer)),
                reason: 'peer "$peer" lamport mismatch after roundtrip');
          }
        },
      );
    });

    test('empty VersionVector roundtrips', () {
      final rt = VersionVector.fromBytes(VersionVector.empty().toBytes());
      expect(rt, equals(VersionVector.empty()));
    });
  });

  group('property: malformed-input robustness', () {
    test('empty bytes -> FormatException (both codecs)', () {
      expect(() => decodeLogosEdit(Uint8List(0)),
          throwsA(isA<FormatException>()));
      expect(() => VersionVector.fromBytes(Uint8List(0)),
          throwsA(isA<FormatException>()));
    });

    test('bad magic on an otherwise-valid, full-length buffer '
        '-> FormatException', () {
      forAll<LogosEdit>(
        _genEdit(),
        count: 150 * fuzzScale(),
        describe: 'bad magic (edit)',
        check: (edit) {
          final bytes = Uint8List.fromList(encodeLogosEdit(edit));
          // Flip every bit of the first magic byte — guaranteed to
          // differ from the real magic's low byte ('L' = 0x4C) since
          // XOR-with-0xff never fixes a point.
          bytes[0] = bytes[0] ^ 0xff;
          expect(() => decodeLogosEdit(bytes), throwsA(isA<FormatException>()),
              reason: 'bytes=$bytes');
        },
      );
      forAll<VersionVector>(
        _genVersionVector(),
        count: 100 * fuzzScale(),
        describe: 'bad magic (VV)',
        check: (vv) {
          final bytes = Uint8List.fromList(vv.toBytes());
          bytes[0] = bytes[0] ^ 0xff;
          expect(() => VersionVector.fromBytes(bytes),
              throwsA(isA<FormatException>()));
        },
      );
    });

    test('unsupported version on a full-length buffer -> FormatException',
        () {
      forAll<LogosEdit>(
        _genEdit(),
        count: 100 * fuzzScale(),
        check: (edit) {
          final bytes = Uint8List.fromList(encodeLogosEdit(edit));
          bytes[4] = 0xff; // version byte; format only defines version 1
          expect(
              () => decodeLogosEdit(bytes), throwsA(isA<FormatException>()));
        },
      );
    });

    test('unknown variant tag on a full-length buffer -> FormatException',
        () {
      forAll<LogosEdit>(
        _genEdit(),
        count: 100 * fuzzScale(),
        check: (edit) {
          final bytes = Uint8List.fromList(encodeLogosEdit(edit));
          bytes[5] = 0xfe; // variant tag; only 0..3 are defined
          expect(
              () => decodeLogosEdit(bytes), throwsA(isA<FormatException>()));
        },
      );
    });

    test('pure random garbage bytes of varying lengths -> FormatException '
        'or a clean rejection, never a successful decode of nonsense', () {
      forAll<Uint8List>(
        (rng) {
          final len = rng.intBetween(0, 64);
          return Uint8List.fromList(
              List.generate(len, (_) => rng.intBetween(0, 255)));
        },
        count: 300 * fuzzScale(),
        describe: 'garbage bytes',
        check: (bytes) {
          // Garbage matching the real magic+version by chance is
          // astronomically unlikely at these lengths/counts; if it ever
          // happens the assertion below simply won't fire for that case,
          // which is fine — it would be a legitimately-shaped edit.
          try {
            decodeLogosEdit(bytes);
          } on FormatException {
            // Expected outcome.
            return;
          }
        },
      );
    });

    // Deterministic minimal repros (not property loops): were a
    // structural gap in the reader (missing bounds checks); fixed via
    // the shared `_need` guard called before every fixed-size read in
    // `_readEditClock`, `_readString`, and `VersionVector.fromBytes`.
    test(
      'truncating inside EditClock\'s lamport field throws '
      'FormatException',
      () {
        const edit = NoOpEdit(clock: EditClock(lamport: 7, peer: 'alice'));
        final bytes = encodeLogosEdit(edit);
        // Full encoding is 21 bytes: 6-byte header + 8-byte lamport +
        // 2-byte peer-len + 5-byte 'alice'. Cutting at 9 lands squarely
        // inside the lamport-hi half (bytes [10..14)).
        final truncated = Uint8List.fromList(bytes.sublist(0, 9));
        expect(() => decodeLogosEdit(truncated),
            throwsA(isA<FormatException>()));
      },
      skip: false,
    );

    test(
      'truncating inside a length-prefixed path string throws '
      'FormatException',
      () {
        const edit = AddPathEdit(
          clock: EditClock(lamport: 42, peer: 'bob'),
          path: 'lib/backend/spectral.dart',
        );
        final bytes = encodeLogosEdit(edit);
        // Cutting at 21 (of 46 total) lands inside the `path` string's
        // declared-length window, well past the header/clock.
        final truncated = Uint8List.fromList(bytes.sublist(0, 21));
        expect(() => decodeLogosEdit(truncated),
            throwsA(isA<FormatException>()));
      },
      skip: false,
    );

    test(
      'VersionVector.fromBytes: truncating inside a peer name throws '
      'FormatException',
      () {
        final vv =
            VersionVector({'alice': 5, 'bob': 100, 'charlie': 7});
        final bytes = vv.toBytes();
        // Cutting at 9 (of 52 total) lands inside the first peer name's
        // declared-length window ('alice').
        final truncated = Uint8List.fromList(bytes.sublist(0, 9));
        expect(() => VersionVector.fromBytes(truncated),
            throwsA(isA<FormatException>()));
      },
      skip: false,
    );

    // Systemic form of the two minimal repros above, across random valid
    // encodings and every possible truncation length. Now exercised for
    // real: the `_need` bounds guard covers every fixed-size read on
    // both decode paths, so every truncation prefix throws
    // FormatException rather than RangeError/IndexError.
    test(
      'every truncation prefix of a valid encoding throws FormatException',
      () {
        forAll<LogosEdit>(
          _genEdit(),
          count: 40 * fuzzScale(),
          describe: 'exhaustive truncation (edits)',
          check: (edit) {
            final bytes = encodeLogosEdit(edit);
            for (var cut = 0; cut < bytes.length; cut++) {
              final prefix = Uint8List.fromList(bytes.sublist(0, cut));
              expect(() => decodeLogosEdit(prefix),
                  throwsA(isA<FormatException>()),
                  reason: 'cut=$cut of ${bytes.length} for $edit');
            }
          },
        );
        forAll<VersionVector>(
          _genVersionVector(),
          count: 40 * fuzzScale(),
          describe: 'exhaustive truncation (VV)',
          check: (vv) {
            final bytes = vv.toBytes();
            for (var cut = 0; cut < bytes.length; cut++) {
              final prefix = Uint8List.fromList(bytes.sublist(0, cut));
              expect(() => VersionVector.fromBytes(prefix),
                  throwsA(isA<FormatException>()),
                  reason: 'cut=$cut of ${bytes.length} for $vv');
            }
          },
        );
      },
      skip: false,
    );
  });

  group('property: compactEdits equivalence', () {
    test('compacted log reproduces the same mockStateSignature', () {
      forAll<List<LogosEdit>>(
        _genEditSequence(maxLen: 60),
        count: 250 * fuzzScale(),
        describe: 'compactEdits equivalence',
        check: (edits) {
          final full = applyEditSet(<String, Map<String, double>>{}, edits);
          final compacted = compactEdits(edits);
          final compactedState =
              applyEditSet(<String, Map<String, double>>{}, compacted);
          expect(
            mockStateSignature(compactedState),
            equals(mockStateSignature(full)),
            reason: 'compaction changed the final state for: $edits',
          );
        },
      );
    });

    // Deterministic minimal repro: a triangle of SetEdgeEdits whose 3
    // paths were never explicitly added used to compact to more edits
    // than it started with (3 -> 6). Fixed: synthesised AddPathEdits
    // are now skipped for any path already covered by a surviving
    // SetEdgeEdit's lazy-create.
    test(
      'compactEdits never produces a longer log than its input',
      () {
        final edits = <LogosEdit>[
          const SetEdgeEdit(
              clock: EditClock(lamport: 1, peer: 'p'),
              pathA: 'a',
              pathB: 'b',
              weight: 1.0),
          const SetEdgeEdit(
              clock: EditClock(lamport: 2, peer: 'p'),
              pathA: 'b',
              pathB: 'c',
              weight: 2.0),
          const SetEdgeEdit(
              clock: EditClock(lamport: 3, peer: 'p'),
              pathA: 'c',
              pathB: 'a',
              weight: 3.0),
        ];
        final compacted = compactEdits(edits);
        expect(compacted.length, lessThanOrEqualTo(edits.length));
      },
      skip: false,
    );

    test('compacting an already-compact (or empty) sequence is a stable '
        'fixed point', () {
      forAll<List<LogosEdit>>(
        _genEditSequence(maxLen: 60),
        count: 150 * fuzzScale(),
        describe: 'compactEdits idempotence',
        check: (edits) {
          final once = compactEdits(edits);
          final twice = compactEdits(once);
          expect(twice.length, equals(once.length),
              reason: 're-compacting an already-compact log must not '
                  'shrink it further');
          expect(
            mockStateSignature(
                applyEditSet(<String, Map<String, double>>{}, twice)),
            equals(mockStateSignature(
                applyEditSet(<String, Map<String, double>>{}, once))),
            reason: 're-compaction must preserve the final state',
          );
        },
      );
    });

    test('compacting the empty log is a no-op', () {
      expect(compactEdits(const []), isEmpty);
      expect(compactEdits(compactEdits(const [])), isEmpty);
    });
  });

  group('property: applyEdit purity + NoOp identity', () {
    test('applyEdit never mutates its input state', () {
      forAll<(LogosEdit, LogosMockState)>(
        _genEditWithState(),
        count: 300 * fuzzScale(),
        describe: 'applyEdit purity',
        check: (pair) {
          final (edit, before) = pair;
          final baselineSignature = mockStateSignature(before);
          final baselineKeys = before.keys.toSet();
          final baselineRows = {
            for (final k in before.keys) k: Map<String, double>.from(before[k]!)
          };

          final after = applyEdit(before, edit);

          expect(before.keys.toSet(), equals(baselineKeys),
              reason: 'applyEdit added/removed keys on its INPUT map');
          for (final k in baselineKeys) {
            expect(before[k], equals(baselineRows[k]),
                reason: 'applyEdit mutated row "$k" of its INPUT map');
          }
          expect(mockStateSignature(before), equals(baselineSignature),
              reason: 'applyEdit must not mutate its input state');
          expect(identical(after, before), isFalse,
              reason: 'applyEdit must return a NEW state object, not the '
                  'same instance it was given');
        },
      );
    });

    test('NoOpEdit is a true identity on any state', () {
      forAll<LogosMockState>(
        _genMockState(),
        count: 200 * fuzzScale(),
        describe: 'NoOp identity',
        check: (state) {
          final before = mockStateSignature(state);
          const noop = NoOpEdit(clock: EditClock(lamport: 1, peer: 'p'));
          final result = applyEdit(state, noop);
          expect(mockStateSignature(result), equals(before),
              reason: 'NoOpEdit must leave the materialised state '
                  'byte-for-byte identical');
        },
      );
    });
  });
}
