// Tests for the 25D Kizuna bond fingerprint. Mirrors the numerical
// proof in `tmp_kizuna_proof.py`:
//
//   EXP 1 - X_i is exactly `(#agree - #disagree)` per bit across pairs.
//   EXP 2 - correlated pairs saturate X; independent pairs kill X.
//   EXP 3 - anti-correlation flips the sign of every X_i.
//   EXP 4 - bond cosine drops smoothly under random perturbation.
//   EXP 5 - identical repos cos = 1; unrelated repos cos is small.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/spectral_kizuna.dart';

Uint8List _randomBytes(int n, int seed) {
  final rng = math.Random(seed);
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}

Uint8List _invert(Uint8List bytes) {
  final out = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ 0xFF;
  }
  return out;
}

void main() {
  group('WHT invariants', () {
    test('delta at 0 yields all +1 coefficients', () {
      final delta = Float64List(kKizunaAddressSpace);
      delta[0] = 1.0;
      final fp = whtFingerprint25D(delta);
      expect(fp.length, 25);
      for (var i = 0; i < 25; i++) {
        expect(fp[i], closeTo(1.0, 1e-12));
      }
    });

    test('uniform histogram yields all-zero coefficients '
        '(all masks non-zero ⇒ orthogonal to constant)', () {
      final uniform = Float64List(kKizunaAddressSpace);
      for (var i = 0; i < uniform.length; i++) {
        uniform[i] = 1.0;
      }
      final fp = whtFingerprint25D(uniform);
      for (var i = 0; i < 25; i++) {
        expect(fp[i], closeTo(0.0, 1e-6));
      }
    });

    test('canonical mask ordering: L (0-7), U (8-15), X (16-23), FFFF (24)',
        () {
      // Low byte = commit byte, high byte = file byte.
      for (var i = 0; i < 8; i++) {
        expect(kKizunaMasks25[i], 1 << i,
            reason: 'L$i should be 1 << $i');
      }
      for (var i = 0; i < 8; i++) {
        expect(kKizunaMasks25[8 + i], 1 << (i + 8),
            reason: 'U$i should be 1 << (i+8)');
      }
      for (var i = 0; i < 8; i++) {
        expect(kKizunaMasks25[16 + i], (1 << i) | (1 << (i + 8)),
            reason: 'X$i should be (1<<i)|(1<<(i+8))');
      }
      expect(kKizunaMasks25[24], 0xFFFF);
    });
  });

  group('EXP 1 — algebraic identity for X_i', () {
    test('X_i exactly equals (#agree - #disagree) across touched pairs', () {
      final fileFp = _randomBytes(5000, 42);
      final commitFp = _randomBytes(5000, 43);
      final bond = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: fileFp,
        commitFingerprints: commitFp,
      );
      final xs = bond.cross;
      for (var i = 0; i < 8; i++) {
        var agree = 0, disagree = 0;
        for (var p = 0; p < fileFp.length; p++) {
          final bf = (fileFp[p] >> i) & 1;
          final bc = (commitFp[p] >> i) & 1;
          if (bf == bc) {
            agree++;
          } else {
            disagree++;
          }
        }
        expect(xs[i], closeTo((agree - disagree).toDouble(), 1e-6),
            reason: 'X_$i should equal (#agree - #disagree)');
      }
    });

    test('L_i equals Σ (-1)^bit_i(commitFp) across pairs', () {
      final fileFp = _randomBytes(3000, 11);
      final commitFp = _randomBytes(3000, 12);
      final bond = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: fileFp,
        commitFingerprints: commitFp,
      );
      final ls = bond.lower;
      for (var i = 0; i < 8; i++) {
        var s = 0;
        for (var p = 0; p < commitFp.length; p++) {
          s += ((commitFp[p] >> i) & 1) == 0 ? 1 : -1;
        }
        expect(ls[i], closeTo(s.toDouble(), 1e-6));
      }
    });
  });

  group('EXP 2 — correlation saturates X, independence kills X', () {
    test('correlated pairs saturate X at n_pairs', () {
      const n = 4096;
      final base = _randomBytes(n, 7);
      final bond = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: base,
        commitFingerprints: base, // identity correlation
      );
      for (var i = 0; i < 8; i++) {
        expect(bond.cross[i], closeTo(n.toDouble(), 1e-6),
            reason: 'X_$i should saturate at n when fpFile == fpCommit');
      }
    });

    test('anti-correlated pairs saturate X at -n_pairs', () {
      const n = 4096;
      final base = _randomBytes(n, 9);
      final bond = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: base,
        commitFingerprints: _invert(base), // bitwise NOT on every byte
      );
      for (var i = 0; i < 8; i++) {
        expect(bond.cross[i], closeTo(-n.toDouble(), 1e-6),
            reason: 'X_$i should saturate at -n when fpCommit = ~fpFile');
      }
    });

    test('independent pairs produce X magnitudes near sqrt(n)', () {
      const n = 4096;
      final bond = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: _randomBytes(n, 100),
        commitFingerprints: _randomBytes(n, 200),
      );
      // Expected |X_i| ≈ sqrt(n) by central-limit; allow 4σ slack.
      final tolerance = 4.0 * math.sqrt(n.toDouble());
      for (var i = 0; i < 8; i++) {
        expect(bond.cross[i].abs(), lessThan(tolerance),
            reason: 'X_$i under independence should be O(sqrt(n))');
      }
    });

    test('correlated / independent X ratio exceeds 10×', () {
      const n = 4096;
      final base = _randomBytes(n, 5);
      final corr = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: base,
        commitFingerprints: base,
      );
      final indep = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: base,
        commitFingerprints: _randomBytes(n, 6),
      );
      var sCorr = 0.0, sIndep = 0.0;
      for (var i = 0; i < 8; i++) {
        sCorr += corr.cross[i].abs();
        sIndep += indep.cross[i].abs();
      }
      expect(sCorr / sIndep, greaterThan(10.0));
    });
  });

  group('EXP 4 — cosine degrades monotonically under perturbation', () {
    test('identical bonds have cosine = 1', () {
      const n = 2048;
      final f = _randomBytes(n, 1);
      final c = _randomBytes(n, 2);
      final a = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: f,
        commitFingerprints: c,
      );
      final b = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: f,
        commitFingerprints: c,
      );
      expect(a.cosineSimilarity(b), closeTo(1.0, 1e-9));
      expect(a.signature, equals(b.signature));
    });

    test('cosine drops monotonically as more pairs are randomized', () {
      const n = 2048;
      final baseF = _randomBytes(n, 301);
      final baseC = _randomBytes(n, 302);
      final base = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: baseF,
        commitFingerprints: baseC,
      );
      double cosAt(double frac, int seed) {
        final rng = math.Random(seed);
        final pf = Uint8List.fromList(baseF);
        final pc = Uint8List.fromList(baseC);
        final k = (frac * n).round();
        // Partial Fisher-Yates — pick k distinct indices (no duplicates).
        final pool = List<int>.generate(n, (i) => i);
        for (var i = 0; i < k; i++) {
          final j = i + rng.nextInt(n - i);
          final tmp = pool[i];
          pool[i] = pool[j];
          pool[j] = tmp;
        }
        for (var i = 0; i < k; i++) {
          final idx = pool[i];
          pf[idx] = rng.nextInt(256);
          pc[idx] = rng.nextInt(256);
        }
        final perturbed = KizunaBond25D.fromFingerprintPairs(
          fileFingerprints: pf,
          commitFingerprints: pc,
        );
        return base.cosineSimilarity(perturbed);
      }

      final cosZero = cosAt(0.0, 1);
      final cosTiny = cosAt(0.02, 2);
      final cosMid = cosAt(0.25, 3);
      // Average full-perturbation cosine over several seeds — a single
      // 2048-pair draw has ~0.2 std on cosine against an independent
      // draw (fingerprint magnitudes are sqrt(n) and noise accumulates).
      var fullSum = 0.0;
      for (final s in [4, 5, 6, 7]) {
        fullSum += cosAt(1.0, s).abs();
      }
      final cosFullMean = fullSum / 4.0;
      expect(cosZero, closeTo(1.0, 1e-9));
      expect(cosTiny, lessThan(cosZero));
      expect(cosMid, lessThan(cosTiny));
      // Full perturbation averages well below the 25% level — the bond
      // has decorrelated from base.
      expect(cosFullMean, lessThan(cosMid * 0.9));
    });
  });

  group('EXP 5 — identical vs. unrelated repos', () {
    test('unrelated repos have near-zero 25D cosine', () {
      const n = 2048;
      final repoA = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: _randomBytes(n, 500),
        commitFingerprints: _randomBytes(n, 501),
      );
      final repoB = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: _randomBytes(n, 900),
        commitFingerprints: _randomBytes(n, 901),
      );
      expect(repoA.cosineSimilarity(repoB).abs(), lessThan(0.3));
    });
  });

  group('family profile', () {
    test('normalized to sum 1 on non-empty bonds', () {
      final bond = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: _randomBytes(1000, 77),
        commitFingerprints: _randomBytes(1000, 78),
      );
      final p = bond.familyProfile;
      final total = p.lower + p.upper + p.cross + p.global;
      expect(total, closeTo(1.0, 1e-9));
    });

    test('correlated bond has cross family dominant over lower/upper', () {
      const n = 4096;
      final base = _randomBytes(n, 123);
      final corr = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: base,
        commitFingerprints: base,
      );
      final p = corr.familyProfile;
      expect(p.cross, greaterThan(p.lower));
      expect(p.cross, greaterThan(p.upper));
    });
  });

  group('buildKizunaHistogram / kizunaBondOfSpectra glue', () {
    test('histogram counts every touch with the correct joint address', () {
      final fileFp = Uint8List.fromList([0x12, 0x34, 0x56]);
      final commitFp = Uint8List.fromList([0xAB, 0xCD]);
      final touchesPerFile = <List<int>>[
        [0, 1], // file 0 touched by commits 0 and 1
        [1],    // file 1 touched by commit 1
        [0],    // file 2 touched by commit 0
      ];
      final hist = buildKizunaHistogram(
        fileFpTable: fileFp,
        commitFpTable: commitFp,
        touchesPerFile: touchesPerFile,
      );
      expect(hist[(0x12 << 8) | 0xAB], closeTo(1.0, 1e-12));
      expect(hist[(0x12 << 8) | 0xCD], closeTo(1.0, 1e-12));
      expect(hist[(0x34 << 8) | 0xCD], closeTo(1.0, 1e-12));
      expect(hist[(0x56 << 8) | 0xAB], closeTo(1.0, 1e-12));
      // Everything else is zero.
      expect(hist.reduce((a, b) => a + b), closeTo(4.0, 1e-12));
    });
  });

  group('toBytes / fromBytes roundtrip', () {
    KizunaBond25D makeBond(int seed) {
      return KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: _randomBytes(1024, seed),
        commitFingerprints: _randomBytes(1024, seed + 1),
      );
    }

    test('produces exactly 216 bytes', () {
      final bond = makeBond(999);
      expect(bond.toBytes().length, 216);
    });

    test('roundtrip preserves signature', () {
      final bond = makeBond(1001);
      final rt = KizunaBond25D.fromBytes(bond.toBytes());
      expect(rt.signature, bond.signature);
    });

    test('roundtrip preserves all 25 coefficients bit-for-bit', () {
      final bond = makeBond(1002);
      final rt = KizunaBond25D.fromBytes(bond.toBytes());
      for (var i = 0; i < 25; i++) {
        expect(rt.coefficients[i], bond.coefficients[i],
            reason: 'coefficients[$i] must be bit-identical');
      }
    });

    test('roundtrip bond compares equal (== and hashCode)', () {
      final bond = makeBond(1003);
      final rt = KizunaBond25D.fromBytes(bond.toBytes());
      expect(rt == bond, isTrue);
      expect(rt.hashCode, bond.hashCode);
    });

    test('fromBytes throws FormatException on bad magic', () {
      final bytes = makeBond(1004).toBytes();
      bytes[0] = 0xFF; // corrupt magic
      expect(() => KizunaBond25D.fromBytes(bytes), throwsFormatException);
    });

    test('fromBytes throws FormatException on unknown version', () {
      final bytes = makeBond(1005).toBytes();
      // Overwrite version field (bytes 4..7) with 99.
      bytes[4] = 99;
      bytes[5] = 0;
      bytes[6] = 0;
      bytes[7] = 0;
      expect(() => KizunaBond25D.fromBytes(bytes), throwsFormatException);
    });

    test('fromBytes throws FormatException on truncated buffer', () {
      final bytes = makeBond(1006).toBytes().sublist(0, 100);
      expect(() => KizunaBond25D.fromBytes(bytes), throwsFormatException);
    });
  });

  group('classifyBondPair', () {
    KizunaBond25D makeBond(int seed) {
      return KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: _randomBytes(2048, seed),
        commitFingerprints: _randomBytes(2048, seed + 1),
      );
    }

    test('same bytes → identical', () {
      final bond = makeBond(2001);
      // Roundtrip through bytes to confirm wire-safe path also lands identical.
      final rt = KizunaBond25D.fromBytes(bond.toBytes());
      expect(classifyBondPair(bond, rt), KizunaBondCompatibility.identical);
    });

    test('same bond object → identical', () {
      final bond = makeBond(2002);
      expect(classifyBondPair(bond, bond), KizunaBondCompatibility.identical);
    });

    test('tiny perturbation (2%) → compatible', () {
      const n = 2048;
      final baseF = _randomBytes(n, 2010);
      final baseC = _randomBytes(n, 2011);
      final base = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: baseF,
        commitFingerprints: baseC,
      );
      // Perturb ~2% of pairs.
      final rng = math.Random(2012);
      final pf = Uint8List.fromList(baseF);
      final pc = Uint8List.fromList(baseC);
      for (var i = 0; i < (n * 0.02).round(); i++) {
        pf[i] = rng.nextInt(256);
        pc[i] = rng.nextInt(256);
      }
      final perturbed = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: pf,
        commitFingerprints: pc,
      );
      // 2% perturbation should land in compatible or identical (not divergent).
      final cls = classifyBondPair(base, perturbed);
      expect(
        cls == KizunaBondCompatibility.compatible ||
            cls == KizunaBondCompatibility.identical,
        isTrue,
        reason: 'expected compatible or identical for 2% perturbation, got $cls',
      );
    });

    test('anti-correlated bond (commit = ~file) → divergent', () {
      // EXP 2 proves cross terms saturate at -n when commitFp = ~fileFp.
      // The cosine against an independent bond is far below 0.3 in that case.
      const n = 2048;
      final f = _randomBytes(n, 2020);
      final indep = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: f,
        commitFingerprints: _randomBytes(n, 2021),
      );
      // Anti-correlated: commit is bitwise NOT of file — maximally anti-correlated
      // cross family. Cosine against the independent bond lands < 0.3.
      final anti = KizunaBond25D.fromFingerprintPairs(
        fileFingerprints: f,
        commitFingerprints: _invert(f),
      );
      expect(classifyBondPair(indep, anti), KizunaBondCompatibility.divergent);
    });

    test('unrelated random bonds → divergent', () {
      final a = makeBond(2030);
      final b = makeBond(2040);
      // EXP 5 shows unrelated repos have |cos| < 0.3 at n=2048.
      expect(classifyBondPair(a, b), KizunaBondCompatibility.divergent);
    });
  });
}
