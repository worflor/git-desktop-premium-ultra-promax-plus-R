// Tests for the bond handshake protocol. Two parts:
//   - BondHandshakePacket.toBytes / fromBytes roundtrip
//   - decideBondSync — pure-function cardinal-outcome coverage

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/bond_protocol.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_signature.dart';
import 'package:git_desktop/backend/spectral_kizuna.dart';

Signature _sig(int lo, [int hi = 0]) =>
    Signature(lo: lo & 0x7fffffff, hi: hi & 0x7fffffff);

Uint8List _randomBytes(int n, int seed) {
  final rng = math.Random(seed);
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}

KizunaBond25D _makeBond(int seed) {
  return KizunaBond25D.fromFingerprintPairs(
    fileFingerprints: _randomBytes(1024, seed),
    commitFingerprints: _randomBytes(1024, seed + 1),
  );
}

void main() {
  group('BondHandshakePacket roundtrip', () {
    test('produces exactly 232 bytes', () {
      final pkt = BondHandshakePacket(
        bond: _makeBond(1),
        stateSignature: _sig(0x12345678, 0x7abcdef0),
        revision: 42,
      );
      expect(pkt.toBytes().length, BondHandshakePacket.wireSize);
      expect(pkt.toBytes().length, 232);
    });

    test('roundtrip preserves all three fields', () {
      final original = BondHandshakePacket(
        bond: _makeBond(2),
        stateSignature: _sig(0x55667788, 0x19aabbcc),
        revision: 1234567,
      );
      final restored = BondHandshakePacket.fromBytes(original.toBytes());
      expect(restored.bond.signature, original.bond.signature);
      expect(restored.stateSignature, original.stateSignature);
      expect(restored.revision, original.revision);
      for (var i = 0; i < 25; i++) {
        expect(restored.bond.coefficients[i],
            original.bond.coefficients[i]);
      }
    });

    test('handles revision = 0 and large revision', () {
      for (final rev in [0, 1, 100, 1000000, 2000000000]) {
        final pkt = BondHandshakePacket(
          bond: _makeBond(rev),
          stateSignature: _sig(rev.toInt() * 7919),
          revision: rev,
        );
        final rt = BondHandshakePacket.fromBytes(pkt.toBytes());
        expect(rt.revision, rev);
      }
    });

    test('fromBytes throws on wrong length', () {
      expect(
        () => BondHandshakePacket.fromBytes(Uint8List(100)),
        throwsFormatException,
      );
    });

    test('fromBytes throws on corrupt bond payload', () {
      final pkt = BondHandshakePacket(
        bond: _makeBond(7),
        stateSignature: _sig(1),
        revision: 1,
      );
      final bytes = pkt.toBytes();
      // Corrupt the bond magic at byte 0.
      bytes[0] = 0xff;
      expect(
        () => BondHandshakePacket.fromBytes(bytes),
        throwsFormatException,
      );
    });
  });

  group('decideBondSync', () {
    test('identical bonds + identical signatures → identicalSkip', () {
      final bond = _makeBond(100);
      final decision = decideBondSync(
        localBond: bond,
        localStateSignature: _sig(0x1111),
        localRevision: 5,
        peerBond: bond,
        peerStateSignature: _sig(0x1111),
        peerRevision: 5,
      );
      expect(decision, BondSyncDecision.identicalSkip);
    });

    test('identical bonds but peer revision ahead → pullFromPeer', () {
      // Same bond coefficients ⇒ identical classification. But state
      // signatures differ (rare in practice; contrived here to exercise
      // the fallthrough path).
      final bond = _makeBond(101);
      final decision = decideBondSync(
        localBond: bond,
        localStateSignature: _sig(0x1111),
        localRevision: 5,
        peerBond: bond,
        peerStateSignature: _sig(0x2222),
        peerRevision: 10,
      );
      expect(decision, BondSyncDecision.pullFromPeer);
    });

    test('compatible bonds, peer revision ahead → pullFromPeer', () {
      // Tiny perturbation ⇒ compatible but not identical.
      final baseF = _randomBytes(2048, 200);
      final baseC = _randomBytes(2048, 201);
      final local = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: baseF,
        commitFingerprints: baseC,
      );
      // Perturb ~1% for a compatible-but-not-identical peer bond.
      final perturbF = Uint8List.fromList(baseF);
      final rng = math.Random(202);
      for (var i = 0; i < 20; i++) {
        perturbF[i] = rng.nextInt(256);
      }
      final peer = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: perturbF,
        commitFingerprints: baseC,
      );
      final decision = decideBondSync(
        localBond: local,
        localStateSignature: _sig(0xAAAA),
        localRevision: 3,
        peerBond: peer,
        peerStateSignature: _sig(0xBBBB),
        peerRevision: 7,
      );
      expect(decision, BondSyncDecision.pullFromPeer);
    });

    test('compatible bonds, local revision ahead → pushToPeer', () {
      final base = _randomBytes(2048, 300);
      final local = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: base,
        commitFingerprints: base,
      );
      // Small perturbation ⇒ compatible.
      final p = Uint8List.fromList(base);
      final rng = math.Random(301);
      for (var i = 0; i < 20; i++) {
        p[i] = rng.nextInt(256);
      }
      final peer = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: p,
        commitFingerprints: base,
      );
      final decision = decideBondSync(
        localBond: local,
        localStateSignature: _sig(0xCCCC),
        localRevision: 20,
        peerBond: peer,
        peerStateSignature: _sig(0xDDDD),
        peerRevision: 10,
      );
      expect(decision, BondSyncDecision.pushToPeer);
    });

    test('compatible bonds, revisions tied → mergeBidirectional', () {
      final base = _randomBytes(2048, 400);
      final local = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: base,
        commitFingerprints: base,
      );
      final p = Uint8List.fromList(base);
      final rng = math.Random(401);
      for (var i = 0; i < 20; i++) {
        p[i] = rng.nextInt(256);
      }
      final peer = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: p,
        commitFingerprints: base,
      );
      final decision = decideBondSync(
        localBond: local,
        localStateSignature: _sig(0xEEEE),
        localRevision: 15,
        peerBond: peer,
        peerStateSignature: _sig(0xFFFF),
        peerRevision: 15,
      );
      expect(decision, BondSyncDecision.mergeBidirectional);
    });

    test('divergent bonds → divergentSkip regardless of revisions', () {
      final local = _makeBond(500);
      final peer = _makeBond(600);
      // These are unrelated random bonds; cosine should be near 0.
      for (final (lr, pr) in [(1, 1), (5, 10), (10, 5)]) {
        final decision = decideBondSync(
          localBond: local,
          localStateSignature: _sig(0x1234),
          localRevision: lr,
          peerBond: peer,
          peerStateSignature: _sig(0x5678),
          peerRevision: pr,
        );
        expect(decision, BondSyncDecision.divergentSkip,
            reason: 'unrelated bonds with revisions ($lr, $pr) should '
                'always decline to sync');
      }
    });
  });

  group('symmetry of decision', () {
    test('swapping local and peer inverts push/pull (bidirectional invariant)',
        () {
      // If A decides pullFromPeer, the symmetric call (A and B swapped)
      // should decide pushToPeer. Critical for protocol correctness —
      // both peers running this independently must reach compatible
      // conclusions.
      final a = _makeBond(700);
      // Compatible-with-a bond via small perturbation.
      final b = _makeBond(700);
      final sigA = _sig(0x1111);
      final sigB = _sig(0x2222);
      final aDecision = decideBondSync(
        localBond: a,
        localStateSignature: sigA,
        localRevision: 3,
        peerBond: b,
        peerStateSignature: sigB,
        peerRevision: 7,
      );
      final bDecision = decideBondSync(
        localBond: b,
        localStateSignature: sigB,
        localRevision: 7,
        peerBond: a,
        peerStateSignature: sigA,
        peerRevision: 3,
      );
      expect(aDecision, BondSyncDecision.pullFromPeer);
      expect(bDecision, BondSyncDecision.pushToPeer);
    });
  });
}
