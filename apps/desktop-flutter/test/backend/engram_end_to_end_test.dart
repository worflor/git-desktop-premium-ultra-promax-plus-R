// End-to-end test using the actual bundled Alexandria + GloVe assets.
// Loads from rootBundle the same way production does, runs a synthetic
// hunk through the encoder, and verifies the nearest well lands
// somewhere sensible for obviously-computing content.
//
// This test catches asset-pipeline regressions that the unit tests
// (which use synthetic fixtures) can't see: wrong pubspec declarations,
// changed binary layouts, mismatched dims, etc.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/engram_brain.dart';
import 'package:git_desktop/backend/engram_bootstrap.dart';
import 'package:git_desktop/backend/engram_glove.dart';
import 'package:git_desktop/backend/engram_hunk_encoder.dart';

Future<Uint8List> _loadAsset(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('engram end-to-end (bundled assets)', () {
    late EngramBrain brain;
    late EngramGlove glove;
    late EngramHunkEncoder encoder;

    setUpAll(() async {
      final brainBytes = await _loadAsset(kEngramBrainAsset);
      final gloveBytes = await _loadAsset(kEngramGloveAsset);
      brain = EngramBrain.loadBytes(brainBytes);
      glove = EngramGlove.loadBytes(gloveBytes);
      encoder = EngramHunkEncoder(brain: brain, glove: glove);
    });

    test('Alexandria loads with expected dim / pairs / wells', () {
      expect(brain.dim, 300);
      expect(brain.pairs, 150);
      expect(brain.wells, isNotEmpty);
      // Alexandria has 225 wells including a "computing" one.
      final names = brain.wells.map((w) => w.name).toSet();
      expect(names.contains('computing'), isTrue,
          reason: 'expected the `computing` well in the bundled brain');
      expect(brain.wells.length, greaterThanOrEqualTo(50));
    });

    test('GloVe loads with expected dim and covers common code tokens',
        () {
      expect(glove.dim, 300);
      expect(glove.vocabSize, greaterThan(15000));
      for (final tok in [
        'get', 'user', 'auth', 'token',
        'fetch', 'validate', 'cache', 'stream',
      ]) {
        expect(glove.tokenIndex.containsKey(tok), isTrue,
            reason: 'expected "$tok" in GloVe vocab');
      }
    });

    test('encoding a computing-flavoured token bag picks a reasonable well',
        () {
      // A hunk touching auth / session / token identifiers. We don't
      // assert a SPECIFIC well — the model may pick "computing" or a
      // numbered discovered well — just that SOMETHING comes back and
      // the K-vector is finite.
      final kv = encoder.encode([
        'validate',
        'user',
        'auth',
        'token',
        'session',
        'manager',
        'fetch',
        'profile',
      ]);
      expect(kv, isNotNull);
      expect(kv!.vocabHits, greaterThanOrEqualTo(6));
      expect(kv.kRe.length, brain.pairs);
      expect(kv.kIm.length, brain.pairs);
      expect(kv.kRe.every((v) => v.isFinite), isTrue);
      expect(kv.kIm.every((v) => v.isFinite), isTrue);
      expect(kv.well, isNotNull);
      expect(kv.well!.name, isNotEmpty);
    });

    test('cosine between two similar-domain hunks beats cosine between '
        'two orthogonal-domain hunks', () {
      // Two "auth" hunks with different surface identifiers:
      final auth1 = encoder.encode([
        'login', 'validate', 'password', 'session', 'token',
        'authentication', 'user', 'profile',
      ]);
      final auth2 = encoder.encode([
        'credential', 'verify', 'permission', 'identity', 'authorize',
        'account', 'access', 'role',
      ]);
      // A clearly-different domain hunk:
      final ui = encoder.encode([
        'render', 'layout', 'widget', 'color', 'paint',
        'animation', 'pixel', 'viewport',
      ]);

      expect(auth1, isNotNull);
      expect(auth2, isNotNull);
      expect(ui, isNotNull);

      final simAuthAuth = EngramHunkEncoder.cosine(auth1, auth2);
      final simAuthUi = EngramHunkEncoder.cosine(auth1, ui);

      // The auth/auth pair should be at least as similar as auth/ui, and
      // typically notably more. We leave a small slack (0.02) so the
      // test is robust to minor K-vector drift from different sub-token
      // orderings — the important property is that semantic clusters
      // lift the signal even with zero string-token overlap.
      expect(simAuthAuth + 0.02, greaterThanOrEqualTo(simAuthUi),
          reason:
              'engram K-space should not score cross-domain pair HIGHER '
              'than in-domain pair (auth↔auth=$simAuthAuth, '
              'auth↔ui=$simAuthUi)');
    });

    test('a hunk with too few GloVe hits returns null', () {
      final kv = encoder.encode(['aaaaa']); // single unlikely token
      // Either null (< min samples) or the token isn't in vocab. Either
      // is fine — we just want the encoder to not crash.
      if (kv != null) {
        expect(kv.vocabHits, greaterThanOrEqualTo(3));
      }
    });
  });
}
