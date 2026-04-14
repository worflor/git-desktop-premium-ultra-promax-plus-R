// Wire-format tests for objectWant / objectPack. Pin the CBOR layout
// so any future evolution is a deliberate version bump rather than a
// silent break that mis-routes packfiles between peers on different
// build vintages.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:git_desktop/backend/bond/object_xfer.dart';

void main() {
  group('ObjectWantBody round-trip', () {
    test('encode/decode preserves all fields', () {
      final id = Uint8List.fromList(List.generate(16, (i) => i * 7 & 0xFF));
      final want = ObjectWantBody(
        requestId: id,
        want: [
          'a' * 40, // SHA-1 hex
          '7' * 64, // SHA-256 hex
        ],
      );
      final bytes = want.encode();
      final decoded = ObjectWantBody.tryDecode(bytes)!;
      expect(decoded.requestId, equals(id));
      expect(decoded.want, equals(want.want));
    });

    test('rejects wrong version', () {
      // Hand-craft a CBOR map with v=2 to confirm the version gate.
      // {v:2, id:<16>, want:[]}
      final raw = Uint8List.fromList([
        0xa3, // map(3)
        0x61, 0x76, 0x02, // "v": 2
        0x62, 0x69, 0x64, 0x50, // "id": bytes(16)
        ...List.filled(16, 0),
        0x64, 0x77, 0x61, 0x6e, 0x74, 0x80, // "want": []
      ]);
      expect(ObjectWantBody.tryDecode(raw), isNull);
    });

    test('rejects malformed hash entries', () {
      final id = Uint8List.fromList(List.filled(16, 0));
      // Hand-craft to inject an invalid hash without going through encode().
      // Easiest path: use cbor and manually create the body — but
      // simpler still, exercise the negative via a too-short hex.
      final w = ObjectWantBody(requestId: id, want: ['short']);
      final bytes = w.encode();
      // tryDecode validates plausibility — should reject.
      expect(ObjectWantBody.tryDecode(bytes), isNull);
    });

    test('rejects wrong id length', () {
      // Hand-craft want with 8-byte id (should be 16).
      final raw = Uint8List.fromList([
        0xa3,
        0x61, 0x76, 0x01,
        0x62, 0x69, 0x64, 0x48, // "id": bytes(8)
        ...List.filled(8, 0),
        0x64, 0x77, 0x61, 0x6e, 0x74, 0x80,
      ]);
      expect(ObjectWantBody.tryDecode(raw), isNull);
    });

    test('empty want list is legal', () {
      final id = Uint8List.fromList(List.filled(16, 1));
      final w = ObjectWantBody(requestId: id, want: const []);
      final decoded = ObjectWantBody.tryDecode(w.encode())!;
      expect(decoded.want, isEmpty);
    });
  });

  group('ObjectPackBody round-trip', () {
    test('encode/decode preserves pack bytes + id', () {
      final id = Uint8List.fromList(List.generate(16, (i) => i));
      final pack = Uint8List.fromList(List.generate(1024, (i) => i & 0xFF));
      final body = ObjectPackBody(requestId: id, pack: pack);
      final decoded = ObjectPackBody.tryDecode(body.encode())!;
      expect(decoded.requestId, equals(id));
      expect(decoded.pack, equals(pack));
      expect(decoded.error, isNull);
    });

    test('error field round-trips', () {
      final id = Uint8List.fromList(List.filled(16, 9));
      final body = ObjectPackBody(
        requestId: id,
        pack: Uint8List(0),
        error: 'pack build failed',
      );
      final decoded = ObjectPackBody.tryDecode(body.encode())!;
      expect(decoded.error, 'pack build failed');
      expect(decoded.pack, isEmpty);
    });
  });

  group('newRequestId', () {
    test('is 16 bytes, distinct on successive calls', () {
      final a = newRequestId();
      final b = newRequestId();
      expect(a.length, 16);
      expect(b.length, 16);
      expect(requestIdEquals(a, b), isFalse);
    });
  });

  group('requestIdEquals', () {
    test('equal arrays compare equal', () {
      final a = Uint8List.fromList(List.generate(16, (i) => i));
      final b = Uint8List.fromList(List.generate(16, (i) => i));
      expect(requestIdEquals(a, b), isTrue);
    });

    test('different arrays compare unequal', () {
      final a = Uint8List(16);
      final b = Uint8List(16)..[0] = 1;
      expect(requestIdEquals(a, b), isFalse);
    });

    test('different-length arrays compare unequal', () {
      expect(requestIdEquals(Uint8List(16), Uint8List(15)), isFalse);
    });
  });
}
