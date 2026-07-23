// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_anchor_fuzz_test.dart — laws of the anchor resolution ladder.
//
// Pure and fast: random files, random anchors, random edit scripts
// (inserts, deletes, replacements, block moves), then the ladder's
// honesty laws:
//  A1  SOUNDNESS — a non-outdated resolution always points at a line
//      whose content hashes identically to the anchored content. The
//      ladder may say "gone"; it may never point at the wrong code.
//  A2  COMPLETENESS — if the exact content survives anywhere in the
//      file, resolution never reports outdated.
//  A3  EXACTNESS — content still present at the anchored position
//      resolves as `anchored` at that position.
//  A4  NEAREST — among surviving duplicates, the resolved line is one
//      at minimal distance from the recorded position.
//  A5  DETERMINISM — resolving twice yields identical results.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/review_anchor.dart';

import '../support/prop.dart';

List<String> _randomFile(Random rng) {
  final n = 20 + rng.nextInt(80);
  final vocab = [
    'final x = compute();',
    'return value;',
    '}',
    '{',
    '',
    'await engine.start();',
    'if (ready) {',
    '  print(x);',
    'class Thing {',
    '// comment',
  ];
  return [
    for (var i = 0; i < n; i++)
      rng.nextInt(4) == 0
          ? vocab[rng.nextInt(vocab.length)] // deliberate duplicates
          : '${vocab[rng.nextInt(vocab.length)]} // u$i',
  ];
}

List<String> _mutate(Random rng, List<String> lines) {
  final out = [...lines];
  final ops = 1 + rng.nextInt(6);
  for (var i = 0; i < ops && out.isNotEmpty; i++) {
    switch (rng.nextInt(4)) {
      case 0:
        out.insert(rng.nextInt(out.length + 1), '// inserted ${rng.nextInt(1000)}');
      case 1:
        out.removeAt(rng.nextInt(out.length));
      case 2:
        final j = rng.nextInt(out.length);
        out[j] = '${out[j]} /* edited */';
      default:
        // Block move: lift a small run and reinsert elsewhere.
        if (out.length > 6) {
          final start = rng.nextInt(out.length - 3);
          final len = 1 + rng.nextInt(3);
          final block = out.sublist(start, start + len);
          out.removeRange(start, start + len);
          out.insertAll(rng.nextInt(out.length + 1), block);
        }
    }
  }
  return out;
}

void main() {
  test('A6: persisted hashes are canonical 16-char unsigned hex', () {
    // The interop contract: any third party implementing the format
    // writes strict unsigned hex; ours must match byte-for-byte. The
    // naive toUnsigned(64) path emitted MINUS-SIGNED strings for
    // negative hashes (VM identity — 2^64+v is unrepresentable).
    // Negative hashes are the COMMON case for FNV, not the edge.
    final canonical = RegExp(r'^[0-9a-f]{16}$');
    final rng = Random(20260722);
    for (var i = 0; i < 200; i++) {
      final line = List.generate(
          1 + rng.nextInt(80), (_) => String.fromCharCode(32 + rng.nextInt(95))).join();
      final a = captureAnchor(
          lines: [line], lineIndex: 0, round: 1, commit: 'c' * 40, path: 'f');
      expect(canonical.hasMatch(a.lineHash), isTrue,
          reason: 'non-canonical lineHash "${a.lineHash}" for "$line"');
      expect(canonical.hasMatch(a.simHash), isTrue);
      for (final c in a.ctx) {
        expect(canonical.hasMatch(c), isTrue);
      }
      // And the round-trip still resolves the identical line exactly.
      expect(resolveAnchor(a, [line]).status, AnchorStatus.anchored);
    }
  });

  test('A1-A5 hold across random files and edit scripts', () {
    final cases = 300 * fuzzScale();
    for (var c = 0; c < cases; c++) {
      final rng = Random(911 + c);
      final v1 = _randomFile(rng);
      final idx = rng.nextInt(v1.length);
      final anchor = captureAnchor(
          lines: v1,
          lineIndex: idx,
          round: 1,
          commit: 'c' * 40,
          path: 'f.dart');
      final v2 = _mutate(rng, v1);

      final r1 = resolveAnchor(anchor, v2);
      final r2 = resolveAnchor(anchor, v2);

      // A5 determinism.
      expect(r1.status, r2.status, reason: 'case $c nondeterministic');
      expect(r1.line, r2.line, reason: 'case $c nondeterministic line');

      final target = v1[idx];
      final survivors = [
        for (var i = 0; i < v2.length; i++)
          if (lineContentHash(v2[i]) == lineContentHash(target)) i + 1
      ];

      if (r1.status == AnchorStatus.outdated) {
        // A2 completeness.
        expect(survivors, isEmpty,
            reason: 'case $c: content survives at $survivors but the '
                'ladder said outdated');
      } else {
        // A1 soundness.
        expect(lineContentHash(v2[r1.line! - 1]),
            lineContentHash(target),
            reason: 'case $c: resolved to non-matching content');
        // A4 nearest.
        final dist = (r1.line! - anchor.line).abs();
        for (final s in survivors) {
          expect(dist <= (s - anchor.line).abs(), isTrue,
              reason: 'case $c: $s is nearer than resolved ${r1.line}');
        }
        // A3 exactness.
        if (anchor.line <= v2.length &&
            lineContentHash(v2[anchor.line - 1]) ==
                lineContentHash(target)) {
          expect(r1.status, AnchorStatus.anchored,
              reason: 'case $c: content at the anchored position must '
                  'resolve as anchored');
          expect(r1.line, anchor.line);
        }
      }
    }
  }, timeout: fuzzTimeout());
}
