// Unit coverage for the typed OID layer's object-format handling
// (lib/backend/manifold_ref_types.dart). SHA-1 is 40 lowercase-hex chars;
// git also supports SHA-256 (`git init --object-format=sha256`) which yields
// 64. The validator must accept BOTH widths and reject everything else, and
// the null-object sentinel must be mintable at the correct width for each
// format (a wrong-width zero is rejected by git at the CAS/lease boundary).

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/manifold_ref_types.dart';

// Real lowercase-hex samples, built by repetition so the length is exact and
// obvious. 16-char unit → slice/repeat to the width under test.
const String _hex16 = '0123456789abcdef';
String _hex(int len) {
  final buf = StringBuffer();
  while (buf.length < len) {
    buf.write(_hex16);
  }
  return buf.toString().substring(0, len);
}

final String _sha1 = _hex(40);
final String _sha256 = _hex(64);

void main() {
  group('Oid validation accepts both object formats', () {
    test('a 40-hex (SHA-1) and a 64-hex (SHA-256) OID are accepted', () {
      expect(Oid(_sha1).toString(), _sha1);
      expect(Oid(_sha256).toString(), _sha256);
      // Kinded subtypes validate through the same check.
      expect(BlobOid(_sha1).toString(), _sha1);
      expect(BlobOid(_sha256).toString(), _sha256);
      expect(TreeOid(_sha1).toString(), _sha1);
      expect(TreeOid(_sha256).toString(), _sha256);
      expect(CommitOid(_sha1).toString(), _sha1);
      expect(CommitOid(_sha256).toString(), _sha256);
    });

    test('near-miss lengths (39/41/63/65) are rejected', () {
      for (final len in [0, 1, 39, 41, 63, 65, 80]) {
        expect(() => Oid(_hex(len)), throwsArgumentError,
            reason: 'length $len must be rejected');
      }
    });

    test('uppercase hex is rejected (git emits lowercase canonical output)',
        () {
      expect(() => Oid(_sha1.toUpperCase()), throwsArgumentError);
      expect(() => Oid(_sha256.toUpperCase()), throwsArgumentError);
      // A single uppercase char anywhere is enough.
      expect(() => Oid('A${_sha1.substring(1)}'), throwsArgumentError);
    });

    test('non-hex characters are rejected at both widths', () {
      expect(() => Oid('g${_sha1.substring(1)}'), throwsArgumentError);
      expect(() => Oid('${_sha256.substring(0, 63)}z'), throwsArgumentError);
      // 'g'..'z' are not hex even though they are lowercase letters.
      expect(() => Oid(List.filled(40, 'g').join()), throwsArgumentError);
    });

    test('the error message names both formats', () {
      try {
        Oid('nope');
        fail('expected ArgumentError');
      } on ArgumentError catch (e) {
        expect(e.message.toString(), contains('40'));
        expect(e.message.toString(), contains('64'));
      }
    });

    test('CommitOid.tryParse: 40/64 parse, invalid returns null', () {
      expect(CommitOid.tryParse(_sha1)?.toString(), _sha1);
      expect(CommitOid.tryParse(_sha256)?.toString(), _sha256);
      expect(CommitOid.tryParse('short'), isNull);
      expect(CommitOid.tryParse(_hex(63)), isNull);
      expect(CommitOid.tryParse(_sha1.toUpperCase()), isNull);
    });
  });

  group('the null-object sentinel is width-correct for each format', () {
    test('Oid.zero is the 40-zero SHA-1 marker and reads as zero', () {
      expect(Oid.zero.toString(), '0' * 40);
      expect(Oid.zero.isZero, isTrue);
    });

    test('zeroFor matches the companion OID width', () {
      final z1 = Oid.zeroFor(Oid(_sha1));
      final z256 = Oid.zeroFor(Oid(_sha256));
      expect(z1.toString(), '0' * 40);
      expect(z256.toString(), '0' * 64);
      // Both are valid OIDs (a zero OID is still lowercase-hex of legal
      // width) and both read as zero.
      expect(z1.isZero, isTrue);
      expect(z256.isZero, isTrue);
      expect(Oid(z1.toString()).toString(), z1.toString());
      expect(Oid(z256.toString()).toString(), z256.toString());
    });

    test('isZero recognises an all-zero OID at EITHER width', () {
      expect(Oid('0' * 40).isZero, isTrue);
      expect(Oid('0' * 64).isZero, isTrue);
      // A single non-zero digit anywhere flips it.
      expect(Oid('1${'0' * 39}').isZero, isFalse);
      expect(Oid('${'0' * 63}1').isZero, isFalse);
      expect(Oid(_sha1).isZero, isFalse);
      expect(Oid(_sha256).isZero, isFalse);
    });
  });
}
