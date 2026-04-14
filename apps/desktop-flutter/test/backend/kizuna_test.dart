// Property + golden-vector tests for the kizuna 16D Möbius primitive.
// These pin the algorithm so any future optimisation (SIMD, WASM swap)
// stays bit-identical to the reference implementation.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:git_desktop/backend/bond/kizuna.dart';

void main() {
  group('PARITY16-driven Möbius residual', () {
    test('all-zero block → residual 0', () {
      final block = Uint8List(kKizunaBlockSize);
      expect(predAnti16D(block), 0);
      expect(factored16D(block).residual, 0);
      expect(handshake16D(block).residual, 0);
    });

    test('boundary-cancellation: only origin has non-zero residual', () {
      // Per the boundary theorem: any voxel with at least one coord=1
      // has anti-causal Möbius sum = its own value, so for a "single
      // hot voxel at non-origin position" the residual is exactly the
      // hot voxel's value (with parity sign).
      final block = Uint8List(kKizunaBlockSize);
      block[1] = 7; // mask=1, popcount=1, parity=1 → contributes +7
      expect(predAnti16D(block), 7);
      block[1] = 0;
      block[3] = 5; // mask=3, popcount=2, parity=0 → contributes -5
      expect(predAnti16D(block), -5);
    });

    test('factored16D == predAnti16D for arbitrary block', () {
      final block = _pseudorandomBlock(seed: 0xCAFEF00D);
      final naive = predAnti16D(block);
      final factored = factored16D(block);
      expect(factored.residual, naive,
          reason: 'μ₁₆ = μ₈ ⊗ μ₈ multiplicative identity must hold');
    });

    test('rowWitnesses[h] equals predAnti8D over its 256-byte row', () {
      final block = _pseudorandomBlock(seed: 0x1234);
      final f = factored16D(block);
      for (var h = 0; h < 256; h++) {
        final expected = block[h * 256] - predAnti8D(block, h * 256);
        expect(f.rowWitnesses[h], expected,
            reason: 'row $h sub-witness mismatch');
      }
    });
  });

  group('handshake16D output shape', () {
    test('rejects wrong block size', () {
      expect(() => handshake16D(Uint8List(0)), throwsArgumentError);
      expect(() => handshake16D(Uint8List(65535)), throwsArgumentError);
    });

    test('countsBitM is 1024 entries with Laplace prior + walk delta', () {
      final block = Uint8List(kKizunaBlockSize);
      final r = handshake16D(block);
      expect(r.countsBitM.length, kKizunaCountsBitMSize);
      // All-zero block: every observed bit is 0, so c0 increments
      // and c1 stays at the Laplace prior of 1 — for the lanes the
      // walk actually visits.
      // Sanity: total c0+c1 across all 512 contexts equals the
      // initial 2*512 + 8 increments per byte * 512 bytes = 5120.
      var total = 0;
      for (final v in r.countsBitM) {
        total += v;
      }
      expect(total, 1024 + 8 * 512,
          reason: 'each of 512 bytes contributes 8 increments');
    });

    test('determinism: same input → bit-identical output', () {
      final block = _pseudorandomBlock(seed: 0x55AA55AA);
      final a = handshake16D(Uint8List.fromList(block));
      final b = handshake16D(Uint8List.fromList(block));
      expect(a.residual, b.residual);
      expect(a.rowWitnesses8D, equals(b.rowWitnesses8D));
      expect(a.countsBitM, equals(b.countsBitM));
    });
  });

  group('residualToWitnessBytes', () {
    test('round-trips little-endian for positive and negative', () {
      // Positive
      final pos = residualToWitnessBytes(0x12345678);
      expect(pos, [0x78, 0x56, 0x34, 0x12]);
      // Negative — wraps as uint32 per the kizuna witness convention.
      final neg = residualToWitnessBytes(-1);
      expect(neg, [0xFF, 0xFF, 0xFF, 0xFF]);
    });
  });
}

/// Cheap deterministic pseudo-random byte block — xorshift32. Avoids
/// pulling in a real RNG so the test suite stays hermetic.
Uint8List _pseudorandomBlock({required int seed}) {
  final block = Uint8List(kKizunaBlockSize);
  var state = seed & 0xFFFFFFFF;
  for (var i = 0; i < block.length; i++) {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >> 17;
    state ^= (state << 5) & 0xFFFFFFFF;
    block[i] = state & 0xFF;
  }
  return block;
}
