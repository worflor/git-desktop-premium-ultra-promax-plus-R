// Focused tests for the curvatureCosine path added alongside the
// existing K-cosine. The hunk graph blends both axes via geometric
// mean so tightening G contributes structure to H_sym beyond the
// velocity-only channel.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/engram_hunk_encoder.dart';

HunkKVector _kv({
  required List<double> kRe,
  required List<double> kIm,
  required List<double> gRe,
  required List<double> gIm,
  int hits = 8,
}) =>
    HunkKVector(
      kRe: Float64List.fromList(kRe),
      kIm: Float64List.fromList(kIm),
      gRe: Float64List.fromList(gRe),
      gIm: Float64List.fromList(gIm),
      meanRms: 0.01,
      vocabHits: hits,
      well: null,
    );

void main() {
  group('EngramHunkEncoder.curvatureCosine', () {
    test('returns 0 on null inputs', () {
      final a = _kv(kRe: [1], kIm: [0], gRe: [1], gIm: [0]);
      expect(EngramHunkEncoder.curvatureCosine(null, a), 0.0);
      expect(EngramHunkEncoder.curvatureCosine(a, null), 0.0);
      expect(EngramHunkEncoder.curvatureCosine(null, null), 0.0);
    });

    test('returns 1 on identical G vectors', () {
      final a = _kv(
        kRe: [1, 0],
        kIm: [0, 0],
        gRe: [0.8, 0.3],
        gIm: [0.1, -0.2],
      );
      final b = _kv(
        kRe: [0, 1], // unrelated K — we're only probing the G axis
        kIm: [1, 0],
        gRe: [0.8, 0.3],
        gIm: [0.1, -0.2],
      );
      expect(EngramHunkEncoder.curvatureCosine(a, b), closeTo(1.0, 1e-9));
    });

    test('returns 0 on orthogonal G vectors', () {
      final a = _kv(kRe: [1], kIm: [0], gRe: [1], gIm: [0]);
      // b.G along the imaginary axis → orthogonal to a.G in ℝ² embedding
      final b = _kv(kRe: [1], kIm: [0], gRe: [0], gIm: [1]);
      expect(EngramHunkEncoder.curvatureCosine(a, b), 0.0);
    });

    test('distinguishes K-alike pairs with opposite G', () {
      // Two hunks with nearly-identical K but opposite G.
      // K-cosine would score them "similar" but curvatureCosine
      // should catch the curvature mismatch.
      final a = _kv(
        kRe: [0.9],
        kIm: [0.1],
        gRe: [1.0],
        gIm: [0.0],
      );
      final b = _kv(
        kRe: [0.9],
        kIm: [0.1],
        gRe: [-1.0],
        gIm: [0.0],
      );
      expect(EngramHunkEncoder.cosine(a, b), greaterThan(0.95));
      expect(EngramHunkEncoder.curvatureCosine(a, b), 0.0);
    });
  });
}
