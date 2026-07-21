// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Edge-case stress tests for the shipped content-coupling pipeline: the
// degenerate inputs a real desktop app WILL meet — fresh repos with no
// history, one-file changesets, unicode-only files, >256KB blobs, paths with
// spaces, charge maps built from empty co-change. Every case runs the real
// code path and asserts graceful silence, never a throw.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart'
    show CouplingReceipt, computeSpectralCoupling;
import 'package:git_desktop/backend/repo_native_embedding.dart';

void main() {
  test('build: empty / tiny / all-noise corpora return null, never throw', () {
    expect(RepoNativeEmbedding.build(const {}), isNull);
    expect(
        RepoNativeEmbedding.build(const {
          'a.dart': ['alpha', 'beta', 'gamma'],
          'b.dart': ['alpha', 'beta', 'gamma'],
        }),
        isNull); // below min file count
    expect(
        RepoNativeEmbedding.build({
          for (var i = 0; i < 10; i++)
            'f$i.dart': ['the', 'for', 'and', 'if', '123', 'ab'],
        }),
        isNull); // pure noise vocabulary
  });

  test('fileVector: OOV-only and single-hit files stay silent', () {
    final emb = RepoNativeEmbedding.build({
      for (var i = 0; i < 20; i++)
        'f$i.dart': [
          for (var k = 0; k < 25; k++) 'vocabTok$k',
          'sharedTokenAlpha', 'sharedTokenBeta', 'unique$i',
        ],
    })!;
    expect(emb.fileVector(['neverSeenAnywhereZz']), isNull);
    expect(emb.fileVector(['sharedTokenAlpha']), isNull); // 1 hit < floor
    final v = emb.fileVector(['sharedTokenAlpha', 'sharedTokenBeta']);
    expect(v, isNotNull);
    var norm = 0.0;
    for (final x in v!) {
      norm += x * x;
    }
    expect(norm, closeTo(1.0, 1e-9));
  });

  test('charges: empty history → all zero; total history → all one', () {
    final emb = RepoNativeEmbedding.build({
      for (var i = 0; i < 12; i++)
        'f$i.dart': [
          for (var k = 0; k < 25; k++) 'vocabTok$k',
          'coupledToken', 'otherToken', 'filler$i',
        ],
    })!;
    final cold = emb.computeTokenCharges(coChanged: (a, b) => false);
    expect(cold.values.every((c) => c == 0.0), isTrue);
    final hot = emb.computeTokenCharges(coChanged: (a, b) => true);
    expect(hot.values.every((c) => c == 1.0), isTrue);
    // zero charges → zero score → overlay stays silent on fresh repos
    expect(
        RepoNativeEmbedding.chargeScore(
            cold, {'coupledToken'}, {'coupledToken'}),
        0.0);
    expect(RepoNativeEmbedding.chargeScore(hot, const {}, {'coupledToken'}),
        0.0);
    expect(RepoNativeEmbedding.topCharges(hot, const {}, const {}), isEmpty);
  });

  test('computeSpectralCoupling: hostile working trees stay graceful',
      () async {
    final dir = await Directory.systemTemp.createTemp('edge_overlay_');
    try {
      // real files: one normal, one with a space in its name, one >256KB
      // (must be skipped), one unicode-only (no ASCII identifiers).
      File('${dir.path}/normal.dart').writeAsStringSync(
          'engineToken couplingToken sharedThing\n' * 5);
      File('${dir.path}/with space.dart').writeAsStringSync(
          'engineToken couplingToken sharedThing\n' * 5);
      File('${dir.path}/huge.dart')
          .writeAsBytesSync(Uint8List(300 * 1024)..fillRange(0, 300 * 1024, 97));
      File('${dir.path}/uni.dart').writeAsStringSync('число значение 数値\n' * 5);
      final emb = RepoNativeEmbedding.build({
        for (var i = 0; i < 10; i++)
          'f$i.dart': [
            for (var k = 0; k < 25; k++) 'vocabTok$k',
            'engineToken', 'couplingToken', 'pad$i',
          ],
      })!;
      final charges = emb.computeTokenCharges(coChanged: (a, b) => true);
      final receipts = <String, Map<String, List<CouplingReceipt>>>{};
      final spec = computeSpectralCoupling(
        ['normal.dart', 'with space.dart', 'huge.dart', 'uni.dart', 'gone.dart'],
        dir.path,
        embedding: emb,
        tokenCharges: charges,
        receiptsOut: receipts,
      );
      // the two readable identifier-bearing files couple; nothing throws on
      // the huge/unicode/missing ones.
      final lo = 'normal.dart'.compareTo('with space.dart') < 0
          ? 'normal.dart'
          : 'with space.dart';
      expect(spec[lo], isNotNull);
      expect(receipts[lo]?.values.single, isNotEmpty);
      for (final r in receipts[lo]!.values.single) {
        expect(r.lineA, greaterThan(0));
        expect(r.lineB, greaterThan(0));
      }
      // single-path and empty calls return const {}
      expect(computeSpectralCoupling(['normal.dart'], dir.path), isEmpty);
      expect(computeSpectralCoupling(const [], dir.path), isEmpty);
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}
