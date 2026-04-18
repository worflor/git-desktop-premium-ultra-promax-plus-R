import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/commit_fingerprint.dart';
import 'package:git_desktop/backend/dtos.dart';

CommitDetailData _detail(List<({String path, int adds, int dels})> files) {
  return CommitDetailData(
    commitHash: 'h',
    shortHash: 'h',
    subject: '',
    body: '',
    authorName: '',
    authorEmail: '',
    authoredAt: '',
    filesChanged: files.length,
    additions: files.fold(0, (a, f) => a + f.adds),
    deletions: files.fold(0, (a, f) => a + f.dels),
    files: [
      for (final f in files)
        CommitFileStatData(
          path: f.path, additions: f.adds, deletions: f.dels,
        ),
    ],
  );
}

void main() {
  group('CommitSignature — fingerprint', () {
    test('determinism: identical inputs produce identical fingerprints', () {
      final d = _detail([
        (path: 'apps/foo.dart', adds: 10, dels: 2),
        (path: 'apps/bar.dart', adds: 5, dels: 0),
      ]);
      final a = computeCommitSignature(d);
      final b = computeCommitSignature(d);
      expect(a.fingerprint, b.fingerprint);
      expect(a.witness, b.witness);
    });

    test('output dimensionality is 25 floats + 256 bits', () {
      final d = _detail([(path: 'a.dart', adds: 1, dels: 0)]);
      final s = computeCommitSignature(d);
      expect(s.fingerprint.length, kFingerprintDim);
      expect(s.fingerprint.length, 25);
      expect(s.witness.length * 32, kWitnessBits);
      expect(s.witness.length, 8);
    });

    test('zero-churn commit produces zero fingerprint and zero witness',
        () {
      final d = _detail([
        (path: 'a.dart', adds: 0, dels: 0),
        (path: 'b.dart', adds: 0, dels: 0),
      ]);
      final s = computeCommitSignature(d);
      for (var i = 0; i < kFingerprintDim; i++) {
        expect(s.fingerprint[i], 0.0);
      }
      // Sign-projection of a zero vector → all dot products are 0,
      // and `0 > 0` is false, so witness should be all zero bits.
      for (final w in s.witness) {
        expect(w, 0);
      }
    });

    test('different file sets produce different fingerprints', () {
      final a = computeCommitSignature(
          _detail([(path: 'a.dart', adds: 100, dels: 0)]));
      final b = computeCommitSignature(
          _detail([(path: 'b.dart', adds: 100, dels: 0)]));
      // Cosine should be < 1 — the file paths hash to different
      // buckets, the WHT coefficients differ.
      expect(fingerprintCosine(a.fingerprint, b.fingerprint), lessThan(1.0));
    });

    test('global mask coefficient (idx 24) equals signed sum at parity 0', () {
      // The FFFF mask has parity-0 only when bucket popcount(b & 0xFFFF)
      // is even — half the buckets. For a one-file commit, bucket
      // contributes ±churn to W_FFFF based on its own popcount parity.
      final d = _detail([(path: 'unique', adds: 7, dels: 3)]);
      final s = computeCommitSignature(d);
      // |W_FFFF| ≤ total churn; with one bucket, |W_FFFF| = total churn.
      expect(s.fingerprint[24].abs(), 10.0);
    });
  });

  group('CommitSignature — witness Hamming', () {
    test('cosine reconstruction from Hamming is monotone in distance', () {
      // Hamming 0 → cos = 1; Hamming kWitnessBits → cos = -1.
      expect(witnessCosineFromHamming(0), closeTo(1.0, 1e-9));
      expect(witnessCosineFromHamming(kWitnessBits ~/ 2), closeTo(0.0, 1e-9));
      expect(witnessCosineFromHamming(kWitnessBits), closeTo(-1.0, 1e-9));
    });
  });

  group('fingerprintCosine', () {
    test('zero vectors → 0.0 (no NaN)', () {
      final s = computeCommitSignature(_detail(const []));
      expect(fingerprintCosine(s.fingerprint, s.fingerprint), 0.0);
    });
  });
}
