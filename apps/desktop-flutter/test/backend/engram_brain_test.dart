// Tests for engram_brain.dart / engram_glove.dart — round-trip the
// binary formats against synthetic inputs, then spot-check nearest-well
// math.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/engram_brain.dart';
import 'package:git_desktop/backend/engram_glove.dart';
import 'package:git_desktop/backend/engram_hunk_encoder.dart';

// .endb v2 flags. Keep in sync with engram_brain.dart.
const int _kFlagHasSumRaw     = 1 << 0;
const int _kFlagHasDream      = 1 << 1;
const int _kFlagHasAnnotations = 1 << 2;
const int _kFlagHasManifest   = 1 << 3;

Uint8List _buildMinimalEndb({
  required int dim,
  required int pairs,
  required List<int> pairing,
  required List<_Well> wells,
  List<_DreamEntrySpec>? dream,
  String? annotationsJson,
  String? manifestJson,
}) {
  assert(pairing.length == dim);
  assert(dim == pairs * 2);
  // Verify every well shares the same sum_raw length when present.
  int? sumRawLen;
  var anySumRaw = false;
  for (final w in wells) {
    if (w.sumRaw == null) continue;
    anySumRaw = true;
    sumRawLen ??= w.sumRaw!.length;
    if (w.sumRaw!.length != sumRawLen) {
      throw ArgumentError('sum_raw lengths must match across wells');
    }
  }
  if (anySumRaw && wells.any((w) => w.sumRaw == null)) {
    throw ArgumentError('sum_raw must be present on all wells or none');
  }

  int flags = 0;
  if (anySumRaw) flags |= _kFlagHasSumRaw;
  if (dream != null) flags |= _kFlagHasDream;
  if (annotationsJson != null) flags |= _kFlagHasAnnotations;
  if (manifestJson != null) flags |= _kFlagHasManifest;

  final buf = BytesBuilder();
  buf.add([0x45, 0x4E, 0x44, 0x42]); // ENDB
  final bd = ByteData(20);
  bd.setUint32(0, 2, Endian.little); // version
  bd.setUint32(4, dim, Endian.little);
  bd.setUint32(8, pairs, Endian.little);
  bd.setUint32(12, wells.length, Endian.little);
  bd.setUint32(16, flags, Endian.little);
  buf.add(bd.buffer.asUint8List());
  // pairing: int16[dim]
  final p = ByteData(dim * 2);
  for (var i = 0; i < dim; i++) {
    p.setInt16(i * 2, pairing[i], Endian.little);
  }
  buf.add(p.buffer.asUint8List());
  // wells
  for (final w in wells) {
    final nameBytes = w.name.codeUnits;
    final hdr = ByteData(2);
    hdr.setUint16(0, nameBytes.length, Endian.little);
    buf.add(hdr.buffer.asUint8List());
    buf.add(nameBytes);
    final cnt = ByteData(4);
    cnt.setUint32(0, w.count, Endian.little);
    buf.add(cnt.buffer.asUint8List());
    // sum_K: complex128[pairs]  (re, im)
    for (var k = 0; k < pairs; k++) {
      final v = ByteData(16);
      v.setFloat64(0, w.sumKre[k], Endian.little);
      v.setFloat64(8, w.sumKim[k], Endian.little);
      buf.add(v.buffer.asUint8List());
    }
    if (anySumRaw) {
      final raw = w.sumRaw!;
      final lenHdr = ByteData(4);
      lenHdr.setUint32(0, raw.length * 8, Endian.little);
      buf.add(lenHdr.buffer.asUint8List());
      final rawBuf = ByteData(raw.length * 8);
      for (var i = 0; i < raw.length; i++) {
        rawBuf.setFloat64(i * 8, raw[i], Endian.little);
      }
      buf.add(rawBuf.buffer.asUint8List());
    }
  }
  // Dream buffer: [n_entries u32][K f32×pairs re/im][G …][S f32×pairs]
  if (dream != null) {
    final hdr = ByteData(4);
    hdr.setUint32(0, dream.length, Endian.little);
    buf.add(hdr.buffer.asUint8List());
    for (final e in dream) {
      assert(e.kRe.length == pairs && e.kIm.length == pairs);
      assert(e.gRe.length == pairs && e.gIm.length == pairs);
      assert(e.s.length == pairs);
      final eb = ByteData(pairs * 20);
      var off = 0;
      for (var k = 0; k < pairs; k++) {
        eb.setFloat32(off, e.kRe[k], Endian.little); off += 4;
        eb.setFloat32(off, e.kIm[k], Endian.little); off += 4;
      }
      for (var k = 0; k < pairs; k++) {
        eb.setFloat32(off, e.gRe[k], Endian.little); off += 4;
        eb.setFloat32(off, e.gIm[k], Endian.little); off += 4;
      }
      for (var k = 0; k < pairs; k++) {
        eb.setFloat32(off, e.s[k], Endian.little); off += 4;
      }
      buf.add(eb.buffer.asUint8List());
    }
  }
  // Annotations JSON.
  if (annotationsJson != null) {
    final body = Uint8List.fromList(annotationsJson.codeUnits);
    final hdr = ByteData(4);
    hdr.setUint32(0, body.length, Endian.little);
    buf.add(hdr.buffer.asUint8List());
    buf.add(body);
  }
  // Manifest JSON.
  if (manifestJson != null) {
    final body = Uint8List.fromList(manifestJson.codeUnits);
    final hdr = ByteData(4);
    hdr.setUint32(0, body.length, Endian.little);
    buf.add(hdr.buffer.asUint8List());
    buf.add(body);
  }
  return buf.toBytes();
}

class _Well {
  _Well({
    required this.name,
    required this.count,
    required this.sumKre,
    required this.sumKim,
    this.sumRaw,
  });
  final String name;
  final int count;
  final List<double> sumKre;
  final List<double> sumKim;
  /// When non-null, encodes as v2 sum_raw for this well. All wells in a
  /// build must share the same length (or all be null).
  final List<double>? sumRaw;
}

class _DreamEntrySpec {
  _DreamEntrySpec({
    required this.kRe,
    required this.kIm,
    required this.gRe,
    required this.gIm,
    required this.s,
  });
  final List<double> kRe;
  final List<double> kIm;
  final List<double> gRe;
  final List<double> gIm;
  final List<double> s;
}

Uint8List _buildMinimalGloveBinary({
  required int dim,
  required double scale,
  required Map<String, List<double>> vocab,
}) {
  final buf = BytesBuilder();
  buf.add([0x47, 0x4C, 0x56, 0x31]); // GLV1
  final hdr = ByteData(16);
  hdr.setUint32(0, 1, Endian.little); // version
  hdr.setUint32(4, vocab.length, Endian.little);
  hdr.setUint32(8, dim, Endian.little);
  hdr.setFloat32(12, scale, Endian.little);
  buf.add(hdr.buffer.asUint8List());

  // tokens in insertion order (mirrors the encoder)
  final tokens = vocab.keys.toList();
  for (final tok in tokens) {
    final tb = tok.codeUnits;
    buf.addByte(tb.length);
    buf.add(tb);
  }
  // vectors: int16 quantised with scale
  final vecBytes = ByteData(tokens.length * dim * 2);
  for (var i = 0; i < tokens.length; i++) {
    final v = vocab[tokens[i]]!;
    for (var d = 0; d < dim; d++) {
      final q = (v[d] / scale * 32767).round().clamp(-32768, 32767);
      vecBytes.setInt16((i * dim + d) * 2, q, Endian.little);
    }
  }
  buf.add(vecBytes.buffer.asUint8List());
  return buf.toBytes();
}

void main() {
  group('EngramBrain.loadBytes', () {
    test('round-trips a minimal single-well brain', () {
      final bytes = _buildMinimalEndb(
        dim: 4,
        pairs: 2,
        pairing: [0, 1, 2, 3],
        wells: [
          _Well(
            name: 'test',
            count: 10,
            sumKre: [5.0, 10.0],
            sumKim: [1.0, -1.0],
          ),
        ],
      );
      final brain = EngramBrain.loadBytes(bytes);
      expect(brain.dim, 4);
      expect(brain.pairs, 2);
      expect(brain.wellCount, 1);
      expect(brain.wellName(0), 'test');
      expect(brain.wellObservationCount(0), 10);
      // Centroid = sum_K / count (accessible via zero-copy view).
      final re = brain.wellCentroidReView(0);
      final im = brain.wellCentroidImView(0);
      expect(re[0], closeTo(0.5, 1e-12));
      expect(re[1], closeTo(1.0, 1e-12));
      expect(im[0], closeTo(0.1, 1e-12));
      expect(im[1], closeTo(-0.1, 1e-12));
    });

    test('bad magic throws FormatException', () {
      final bytes = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
      expect(() => EngramBrain.loadBytes(bytes),
          throwsA(isA<FormatException>()));
    });

    test('v2 loads sum_raw when flag is set', () {
      final bytes = _buildMinimalEndb(
        dim: 4,
        pairs: 2,
        pairing: [0, 1, 2, 3],
        wells: [
          _Well(
            name: 'a',
            count: 10,
            sumKre: [5.0, 10.0],
            sumKim: [1.0, -1.0],
            sumRaw: [0.1, 0.2, 0.3, 0.4],
          ),
          _Well(
            name: 'b',
            count: 5,
            sumKre: [1.0, 2.0],
            sumKim: [0.0, 0.0],
            sumRaw: [9.0, 8.0, 7.0, 6.0],
          ),
        ],
      );
      final brain = EngramBrain.loadBytes(bytes);
      expect(brain.sumRawLen, 4);
      // Original index 0 == "a" (sum_raw views read via original index).
      final rawA = brain.wellSumRawView(0);
      expect(rawA, isNotNull);
      expect(rawA!.toList(), [0.1, 0.2, 0.3, 0.4]);
      final rawB = brain.wellSumRawView(1);
      expect(rawB!.toList(), [9.0, 8.0, 7.0, 6.0]);
    });

    test('v2 with no sum_raw flag returns null views', () {
      final bytes = _buildMinimalEndb(
        dim: 2,
        pairs: 1,
        pairing: [0, 1],
        wells: [
          _Well(name: 'only', count: 3, sumKre: [1.0], sumKim: [0.0]),
        ],
      );
      final brain = EngramBrain.loadBytes(bytes);
      expect(brain.sumRawLen, 0);
      expect(brain.wellSumRawView(0), isNull);
    });

    test('v2 decodes dream buffer entries', () {
      final bytes = _buildMinimalEndb(
        dim: 2,
        pairs: 1,
        pairing: [0, 1],
        wells: [
          _Well(name: 'w', count: 1, sumKre: [0.0], sumKim: [0.0]),
        ],
        dream: [
          _DreamEntrySpec(
            kRe: [1.0], kIm: [0.5],
            gRe: [-1.0], gIm: [-0.5],
            s: [0.25],
          ),
          _DreamEntrySpec(
            kRe: [2.0], kIm: [1.0],
            gRe: [-2.0], gIm: [-1.0],
            s: [0.5],
          ),
        ],
      );
      final brain = EngramBrain.loadBytes(bytes);
      expect(brain.dream, isNotNull);
      expect(brain.dream!.length, 2);
      final e0 = brain.dream!.entry(0);
      expect(e0.kRe[0], closeTo(1.0, 1e-6));
      expect(e0.kIm[0], closeTo(0.5, 1e-6));
      expect(e0.gRe[0], closeTo(-1.0, 1e-6));
      expect(e0.gIm[0], closeTo(-0.5, 1e-6));
      expect(e0.s[0], closeTo(0.25, 1e-6));
      final e1 = brain.dream!.entry(1);
      expect(e1.s[0], closeTo(0.5, 1e-6));
    });

    test('v2 surfaces annotations and manifest JSON', () {
      final bytes = _buildMinimalEndb(
        dim: 2,
        pairs: 1,
        pairing: [0, 1],
        wells: [
          _Well(name: 'w', count: 1, sumKre: [0.0], sumKim: [0.0]),
        ],
        annotationsJson: '{"system_card":"hi","tone":"warm"}',
        manifestJson: '{"engram":1,"identity":{"name":"T"}}',
      );
      final brain = EngramBrain.loadBytes(bytes);
      expect(brain.annotations, isNotNull);
      expect(brain.annotations!['system_card'], 'hi');
      expect(brain.annotations!['tone'], 'warm');
      expect(brain.manifest, isNotNull);
      expect(brain.manifest!['engram'], 1);
      expect((brain.manifest!['identity'] as Map)['name'], 'T');
    });

    test('rejects version other than 2', () {
      // Write a header with version=1 manually.
      final buf = BytesBuilder();
      buf.add([0x45, 0x4E, 0x44, 0x42]);
      final bd = ByteData(20);
      bd.setUint32(0, 1, Endian.little);
      bd.setUint32(4, 2, Endian.little);
      bd.setUint32(8, 1, Endian.little);
      bd.setUint32(12, 0, Endian.little);
      bd.setUint32(16, 0, Endian.little);
      buf.add(bd.buffer.asUint8List());
      expect(() => EngramBrain.loadBytes(buf.toBytes()),
          throwsA(isA<FormatException>()));
    });

    test('nearestWell picks the well at smallest mass-weighted distance',
        () {
      // Two wells: "big" with huge mass at K=(1,0) and "small" with
      // tiny mass at K=(0.5, 0). An observation at K=(0.7, 0) is
      // closer to "small" raw, but mass-weighting pulls toward "big".
      final bytes = _buildMinimalEndb(
        dim: 2,
        pairs: 1,
        pairing: [0, 1],
        wells: [
          _Well(
            name: 'big',
            count: 1000000,
            sumKre: [1.0 * 1000000],
            sumKim: [0.0],
          ),
          _Well(
            name: 'small',
            count: 5,
            sumKre: [0.5 * 5],
            sumKim: [0.0],
          ),
        ],
      );
      final brain = EngramBrain.loadBytes(bytes);
      final kRe = Float64List.fromList([0.7]);
      final kIm = Float64List.fromList([0.0]);
      final match = brain.nearestWell(kRe, kIm);
      expect(match, isNotNull);
      expect(match!.name, 'big',
          reason:
              'mass-weighting should pull toward high-count well');
    });
  });

  group('EngramGlove.loadBytes', () {
    test('round-trips a minimal vocab with 2 tokens', () {
      final bytes = _buildMinimalGloveBinary(
        dim: 3,
        scale: 6.0,
        vocab: {
          'hello': [1.0, -2.0, 0.5],
          'world': [3.0, 0.0, -1.5],
        },
      );
      final glove = EngramGlove.loadBytes(bytes);
      expect(glove.dim, 3);
      expect(glove.vocabSize, 2);
      final out = Float64List(3);
      expect(glove.lookup('hello', out), isTrue);
      // int16 quantisation with scale=6 has max err ~1e-4
      expect(out[0], closeTo(1.0, 1e-3));
      expect(out[1], closeTo(-2.0, 1e-3));
      expect(out[2], closeTo(0.5, 1e-3));

      expect(glove.lookup('notinvocab', out), isFalse);
    });

    test('encoder caps repeated tokens at 3 copies (no degenerate flat fit)',
        () {
      // Build a tiny brain with one well + 4-token vocab, then ask the
      // encoder to encode a hunk where the same identifier is repeated
      // many times. The cap kicks in after 3 copies — that's enough
      // observations to fit AR(2) without letting a single token
      // dominate the trajectory and collapse it to a constant.
      final brainBytes = _buildMinimalEndb(
        dim: 4,
        pairs: 2,
        pairing: [0, 1, 2, 3],
        wells: [
          _Well(
            name: 'general',
            count: 100,
            sumKre: [0.0, 0.0],
            sumKim: [0.0, 0.0],
          ),
        ],
      );
      final brain = EngramBrain.loadBytes(brainBytes);
      final gloveBytes = _buildMinimalGloveBinary(
        dim: 4,
        scale: 6.0,
        vocab: {
          'foo': [1.0, 2.0, -1.0, 0.5],
          'bar': [0.5, -0.5, 1.0, 0.0],
        },
      );
      final glove = EngramGlove.loadBytes(gloveBytes);
      final encoder = EngramHunkEncoder(brain: brain, glove: glove);

      // 8 copies of "foo" + 1 of "bar" should cap at 3+1 = 4 effective
      // observations — enough for AR(2). Without the cap we'd have 9
      // observations, but they'd be 8 copies of one vector (constant
      // sub-trajectory) → degenerate normal equations.
      final result = encoder.encode([
        'foo', 'foo', 'foo', 'foo', 'foo', 'foo', 'foo', 'foo', 'bar',
      ]);
      expect(result, isNotNull,
          reason: 'cap should leave enough variety to fit AR(2)');
      expect(result!.vocabHits, lessThanOrEqualTo(4),
          reason: '3·foo + 1·bar = 4 observations max');
      expect(result.vocabHits, greaterThanOrEqualTo(3));
    });

    test('accumulateMean averages vectors across in-vocab tokens', () {
      final bytes = _buildMinimalGloveBinary(
        dim: 2,
        scale: 6.0,
        vocab: {
          'a': [2.0, 0.0],
          'b': [0.0, 4.0],
        },
      );
      final glove = EngramGlove.loadBytes(bytes);
      final out = Float64List(2);
      final hits = glove.accumulateMean(['a', 'b', 'missing'], out);
      expect(hits, 2);
      expect(out[0], closeTo(1.0, 1e-3));
      expect(out[1], closeTo(2.0, 1e-3));
    });
  });
}
