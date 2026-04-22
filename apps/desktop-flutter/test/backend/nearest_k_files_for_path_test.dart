// Tests for the nearestKFilesForPath helper — the canonical
// "what files are semantically nearest to THIS file?" surface.
// Replaces the row-unpack dance that used to live inline in
// changes_page.dart.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/engram_file_ktable.dart';
import 'package:git_desktop/backend/engram_hunk_encoder.dart';
import 'package:git_desktop/backend/engram_text_kspace.dart';

/// Build a K-vector with the first pair set to (re, im) and the rest
/// zeroed. Keeps the test vectors easy to reason about — two rows
/// with the same phase on pair 0 are maximally similar.
HunkKVector _kv({required int pairs, required double re, required double im}) {
  final kRe = Float64List(pairs);
  final kIm = Float64List(pairs);
  kRe[0] = re;
  kIm[0] = im;
  return HunkKVector(
    kRe: kRe,
    kIm: kIm,
    gRe: Float64List(pairs),
    gIm: Float64List(pairs),
    meanRms: 0.0,
    vocabHits: 10,
    well: null,
  );
}

EngramFileKTable _table(Map<String, HunkKVector> encodings) =>
    EngramFileKTable.fromMap(
      pairs: encodings.values.first.kRe.length,
      encodings: encodings,
      wellNamesByOriginalIndex: const [],
    );

void main() {
  group('nearestKFilesForPath', () {
    test('empty table yields empty', () {
      final table = EngramFileKTable.empty(3);
      expect(nearestKFilesForPath(table, 'lib/a.dart'), isEmpty);
    });

    test('unknown source yields empty', () {
      final table = _table({
        'lib/a.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/b.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
      });
      expect(nearestKFilesForPath(table, 'missing.dart'), isEmpty);
    });

    test('excludes the source path by default', () {
      final table = _table({
        'lib/a.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/b.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/c.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
      });
      final near = nearestKFilesForPath(table, 'lib/a.dart');
      final paths = near.map((e) => e.path).toList();
      expect(paths, contains('lib/b.dart'));
      expect(paths, contains('lib/c.dart'));
      expect(paths, isNot(contains('lib/a.dart')));
    });

    test('keeps the source when excludeSource is false', () {
      final table = _table({
        'lib/a.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/b.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
      });
      final near = nearestKFilesForPath(
        table,
        'lib/a.dart',
        excludeSource: false,
      );
      final paths = near.map((e) => e.path).toSet();
      expect(paths, contains('lib/a.dart'));
    });

    test('honours topK after dropping the source', () {
      final table = _table({
        'lib/a.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/b.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/c.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/d.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
      });
      final near = nearestKFilesForPath(table, 'lib/a.dart', topK: 2);
      expect(near.length, equals(2));
    });

    test('orthogonal vectors drop below default minSimilarity', () {
      // Source points along +re; peers point along +im. Cosine = 0,
      // below the 0.35 default floor, so the result is empty.
      final table = _table({
        'lib/a.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/b.dart': _kv(pairs: 3, re: 0.0, im: 1.0),
      });
      expect(nearestKFilesForPath(table, 'lib/a.dart'), isEmpty);
    });

    test('sorts results by similarity descending', () {
      // lib/a uses re=1, im=0. lib/b matches exactly. lib/c at 45°
      // (re=im=1). lib/b should rank first.
      final table = _table({
        'lib/a.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/b.dart': _kv(pairs: 3, re: 1.0, im: 0.0),
        'lib/c.dart': _kv(pairs: 3, re: 1.0, im: 1.0),
      });
      final near = nearestKFilesForPath(table, 'lib/a.dart');
      expect(near.length, equals(2));
      expect(near[0].path, equals('lib/b.dart'));
      expect(near[1].path, equals('lib/c.dart'));
      expect(near[0].similarity, greaterThan(near[1].similarity));
    });
  });
}
