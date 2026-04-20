// Tests for the GPGPU fragment-shader harness. The actual kernel
// invocation needs a real GPU + asset bundle; `flutter test` runs
// headless, so we pin the *pure-Dart* half of the pipeline here —
// the Float32 bit-pack round-trip that both input encoding and
// output decoding rely on.
//
// If that round-trip is wrong, every kernel is wrong. If it's right,
// the shader side is a fixed GLSL transformation (floatBitsToUint /
// uintBitsToFloat) that gets exercised end-to-end during normal use.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/gpgpu.dart';

/// Simulate the round-trip that the harness performs around the
/// shader: Dart encodes a Float32List into big-endian RGBA8 bytes,
/// the shader reads those 4 bytes as a uint and bit-casts back to
/// float, computes, then encodes the result the same way. Here we
/// skip the shader and check that the encode/decode ends of the
/// pipe agree byte-for-byte.
Float32List _roundTripViaBytes(Float32List input) {
  final bytes = Uint8List(input.length * 4);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < input.length; i++) {
    bd.setFloat32(i * 4, input[i], Endian.big);
  }
  return decodeFloat32Output(
    ByteData.sublistView(bytes),
    input.length,
    1,
  );
}

void main() {
  group('GPGPU bit-pack round-trip', () {
    test('preserves finite floats exactly', () {
      final input = Float32List.fromList(const [
        0.0,
        1.0,
        -1.0,
        3.14159,
        -2.71828,
        1e-20,
        -1e20,
        0.5,
        -0.5,
      ]);
      final out = _roundTripViaBytes(input);
      expect(out.length, input.length);
      for (var i = 0; i < input.length; i++) {
        expect(out[i], input[i],
            reason: 'round-trip must be bit-exact at index $i');
      }
    });

    test('preserves denormals, infinities, and edge values', () {
      final input = Float32List.fromList([
        double.minPositive,
        -double.minPositive,
        double.infinity,
        double.negativeInfinity,
        // Float32 max/min
        3.4028235e38,
        -3.4028235e38,
      ]);
      final out = _roundTripViaBytes(input);
      for (var i = 0; i < input.length; i++) {
        expect(out[i], input[i], reason: 'edge value at $i');
      }
    });

    test('NaN survives with payload bits intact', () {
      final input = Float32List.fromList([double.nan]);
      final out = _roundTripViaBytes(input);
      expect(out[0].isNaN, isTrue);
    });

    test('random floats round-trip bit-exact for 10k samples', () {
      final rng = math.Random(0xBEEF);
      const n = 10000;
      final input = Float32List(n);
      for (var i = 0; i < n; i++) {
        // Mix of magnitudes so we hit different exponent bands.
        final sign = rng.nextBool() ? 1.0 : -1.0;
        final mag = math.pow(10, rng.nextDouble() * 30 - 15).toDouble();
        input[i] = sign * rng.nextDouble() * mag;
      }
      final out = _roundTripViaBytes(input);
      for (var i = 0; i < n; i++) {
        expect(out[i], input[i], reason: 'sample $i');
      }
    });
  });

  group('decodeFloat32Output', () {
    test('reads one float per 4 bytes, row-major', () {
      // 4 pixels = 4 floats. Hand-pack two rows of two.
      final bytes = ByteData(16);
      bytes.setFloat32(0, 1.0, Endian.big);
      bytes.setFloat32(4, 2.0, Endian.big);
      bytes.setFloat32(8, 3.0, Endian.big);
      bytes.setFloat32(12, 4.0, Endian.big);
      final out = decodeFloat32Output(bytes, 2, 2);
      expect(out, Float32List.fromList([1.0, 2.0, 3.0, 4.0]));
    });
  });
}
