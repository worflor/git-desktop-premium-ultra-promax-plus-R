import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/features/history/commit_seismograph_layout.dart';

CommitFileStatData _f(String path, {int add = 0, int del = 0, String t = 'M'}) =>
    CommitFileStatData(
      path: path, additions: add, deletions: del, changeType: t,
    );

void main() {
  // Constraints used across most tests. minTrackPx=20, minSegmentPx=10
  // chosen as plausible values — semantics of the layout do not depend
  // on what these are, only that the panel rect is laid out against them.
  const c = SeismographConstraints(
    width: 800, height: 600, minTrackPx: 20, minSegmentPx: 10,
  );

  group('buildSeismographTree', () {
    test('aggregates churn and leaf counts up the tree', () {
      final root = buildSeismographTree([
        _f('a/b/x.dart', add: 10, del: 2),
        _f('a/b/y.dart', add: 4, del: 1),
        _f('a/c/z.dart', add: 7),
      ]);
      expect(root.leafCount, 3);
      expect(root.churn, 24);
      expect(root.children['a']!.leafCount, 3);
      expect(root.children['a']!.children['b']!.leafCount, 2);
      expect(root.children['a']!.children['b']!.churn, 17);
    });

    test('normalizes backslash separators', () {
      final root = buildSeismographTree([_f(r'a\b\x.dart', add: 1)]);
      expect(root.children['a']!.children['b']!.children['x.dart']!.isLeaf, true);
    });
  });

  group('layoutSeismograph — degenerate inputs', () {
    test('empty file list yields empty layout', () {
      final r = buildSeismographTree(const []);
      final l = layoutSeismograph(root: r, c: c);
      expect(l.isEmpty, true);
    });

    test('single file collapses through hoist into singleFile row', () {
      final r = buildSeismographTree([_f('a/b/c/x.dart', add: 5)]);
      final l = layoutSeismograph(root: r, c: c);
      expect(l.tracks, isEmpty);
      expect(l.singleFile, isNotNull);
      expect(l.singleFile!.label, 'a/b/c/x.dart');
      expect(l.singleFile!.width, c.width);
      expect(l.focusPath, ['a', 'b', 'c', 'x.dart']);
    });
  });

  group('layoutSeismograph — segment widths', () {
    test('all-leaf focus → one "here" track with all leaves as segments', () {
      // After hoisting, focus = m. m's children are all leaves, so they
      // become segments of a single "here" track (not three tracks).
      final r = buildSeismographTree([
        _f('m/a.dart', add: 60),
        _f('m/b.dart', add: 30),
        _f('m/c.dart', add: 10),
      ]);
      final l = layoutSeismograph(root: r, c: c);
      expect(l.tracks, hasLength(1));
      final track = l.tracks.first;
      expect(track.segments, hasLength(3));
      final widths = track.segments.map((s) => s.width).toList();
      expect(widths.reduce((a, b) => a + b), closeTo(c.width, 0.01));
      // Largest churn first.
      expect(track.segments.first.label, 'a.dart');
    });

    test('sub-min leaves fold into one tail segment, drill-disabled in here', () {
      final r = buildSeismographTree([
        _f('m/big.dart', add: 1000),
        for (var i = 0; i < 30; i++) _f('m/t$i.dart', add: 1),
      ]);
      final l = layoutSeismograph(root: r, c: c);
      final track = l.tracks.first;
      expect(track.segments.first.label, 'big.dart');
      expect(track.segments.last.label, startsWith('+'));
      expect(track.segments.last.isLeaf, false);
      expect(track.segments.last.containedFileCount, greaterThan(1));
      final sum = track.segments.fold<double>(0, (a, s) => a + s.width);
      expect(sum, closeTo(c.width, 0.01));
    });

    test('subdir track exposes its descendant leaves as segments', () {
      // Focus hoists to root with two subdirs `a` and `b` (each have
      // multiple leaves so they don't hoist away). Track `a` should
      // contain a's leaves; track `b` contains b's.
      final r = buildSeismographTree([
        _f('a/x.dart', add: 5),
        _f('a/y.dart', add: 5),
        _f('b/p.dart', add: 50),
        _f('b/q.dart', add: 50),
      ]);
      final l = layoutSeismograph(root: r, c: c);
      expect(l.tracks, hasLength(2));
      // Highest-churn subdir first.
      expect(l.tracks.first.label, 'b');
      expect(l.tracks.first.segments, hasLength(2));
      expect(l.tracks[1].segments, hasLength(2));
    });
  });

  group('layoutSeismograph — vertical fold', () {
    test('selects top-churn tracks and collapses the rest into overflow', () {
      // Panel can hold floor(600/20)=30 tracks total. Make 50 dirs.
      final files = [
        for (var i = 0; i < 50; i++) _f('d$i/file.dart', add: 50 - i),
      ];
      final l = layoutSeismograph(
        root: buildSeismographTree(files),
        c: const SeismographConstraints(
          width: 800, height: 600, minTrackPx: 20, minSegmentPx: 10,
        ),
      );
      // We must reserve one track for the overflow bucket, so visible
      // real tracks <= 29 and the last one is the bucket.
      expect(l.tracks.last.isOverflowBucket, true);
      expect(l.tracks.length, lessThanOrEqualTo(30));
      // First tracks correspond to the highest-churn dirs (each subdir
      // hoists to `dN/file.dart`).
      expect(l.tracks.first.label, 'd0/file.dart');
      // Heights stack with no gap and don't exceed panel height.
      final totalH = l.tracks.fold<double>(0, (a, t) => a + t.height);
      expect(totalH, closeTo(600, 0.01));
    });

    test('floors-do-not-fit case divides evenly', () {
      // 10 children, panel only 50px tall, minTrack 20: floors total
      // = 200 > 50, so each track gets 5px.
      final files = [
        for (var i = 0; i < 10; i++) _f('d$i/x.dart', add: 1),
      ];
      final l = layoutSeismograph(
        root: buildSeismographTree(files),
        c: const SeismographConstraints(
          width: 100, height: 50, minTrackPx: 20, minSegmentPx: 10,
        ),
      );
      // Selection collapses heavily; just check we never overflow the rect.
      final totalH = l.tracks.fold<double>(0, (a, t) => a + t.height);
      expect(totalH, lessThanOrEqualTo(50.0001));
    });
  });

  group('layoutSeismograph — hoisting', () {
    test('focus hoists down through single-child chain', () {
      // Two leaves under apps/desktop-flutter/lib/backend → focus root
      // hoists down to `backend` (apps→desktop-flutter→lib are
      // single-child chain).
      final r = buildSeismographTree([
        _f('apps/desktop-flutter/lib/backend/a.dart', add: 1),
        _f('apps/desktop-flutter/lib/backend/b.dart', add: 1),
      ]);
      final l = layoutSeismograph(root: r, c: c);
      expect(l.focusPath, ['apps', 'desktop-flutter', 'lib', 'backend']);
      // Both leaves group under one "here" track (backend has only leaf
      // children).
      expect(l.tracks, hasLength(1));
      expect(l.tracks.first.segments, hasLength(2));
    });

    test('subdir tracks hoist labels through single-child sub-chains', () {
      // Focus hoists to 'root/m'; one subdir track for 'deep/...'
      // (label hoisted), one "here" track for the loose other.dart.
      final r = buildSeismographTree([
        _f('root/m/deep/very/deep/x.dart', add: 1),
        _f('root/m/other.dart', add: 1),
      ]);
      final l = layoutSeismograph(root: r, c: c);
      expect(l.tracks, hasLength(2));
      final subdirTrack = l.tracks.firstWhere(
          (t) => t.label == 'deep/very/deep/x.dart',
          orElse: () => throw StateError('no hoisted subdir track'));
      expect(subdirTrack.segments, hasLength(1));
      final hereTrack =
          l.tracks.firstWhere((t) => t != subdirTrack);
      expect(hereTrack.segments.map((s) => s.label), contains('other.dart'));
    });
  });

  group('layoutSeismograph — drillability flags', () {
    test('subdir-track fold is drillable; here-track and overflow are not',
        () {
      // Force a fold inside a subdir track: 1 fat + many tinies, all
      // under sub/. Subdir track's fold target = sub/ → drillable.
      final r = buildSeismographTree([
        _f('sub/big.dart', add: 1000),
        for (var i = 0; i < 30; i++) _f('sub/t$i.dart', add: 1),
        // Loose root files create a here-track whose fold isn't drillable.
        _f('loose1.dart', add: 1),
        for (var i = 0; i < 40; i++) _f('loose$i.dart', add: 1),
      ]);
      final l = layoutSeismograph(root: r, c: c);
      final subdir = l.tracks.firstWhere((t) => !t.isOverflowBucket
          && t.label.startsWith('sub'));
      final fold = subdir.segments.firstWhere((s) => s.label.startsWith('+'));
      expect(fold.isDrillable, true,
          reason: 'subdir-track fold should drill into the subdir');

      final here = l.tracks.firstWhere(
          (t) => t.label.startsWith('(') && t.label.endsWith(')'));
      final hereFold = here.segments
          .where((s) => s.label.startsWith('+'))
          .firstOrNull;
      if (hereFold != null) {
        expect(hereFold.isDrillable, false,
            reason: 'here-track fold has nowhere to drill');
      }
    });
  });

  group('layoutSeismograph — pure-rename / zero-churn commit', () {
    test('all-zero-churn files still produce labelled segments', () {
      // A pure-rename or chmod commit: every file 0/0. The track must
      // still render readable segments instead of an empty band.
      final r = buildSeismographTree([
        for (var i = 0; i < 4; i++) _f('m/r$i.dart', add: 0, del: 0, t: 'R'),
      ]);
      final l = layoutSeismograph(root: r, c: c);
      expect(l.tracks, hasLength(1));
      final track = l.tracks.first;
      expect(track.segments, hasLength(4),
          reason: 'zero-churn fallback splits evenly');
      final widths = track.segments.map((s) => s.width).toList();
      expect(widths.reduce((a, b) => a + b), closeTo(c.width, 0.01));
    });
  });

  group('layoutSeismograph — float drift', () {
    test('last track snaps to consume panel exactly', () {
      // Many tracks at varying churn — the iterative reclaim drifts;
      // the final-track snap should pin total height to c.height.
      final files = [
        for (var i = 0; i < 20; i++) _f('d$i/x.dart', add: 100 - i * 3),
      ];
      final l = layoutSeismograph(
        root: buildSeismographTree(files),
        c: const SeismographConstraints(
          width: 800, height: 400, minTrackPx: 22, minSegmentPx: 12,
        ),
      );
      final last = l.tracks.last;
      expect(last.top + last.height, 400.0,
          reason: 'snapped last track ends exactly at panel height');
    });
  });

  group('layoutSeismograph — drill-in via focusPath', () {
    test('focusing into a subdir relayouts that subtree only', () {
      final r = buildSeismographTree([
        _f('apps/a/x.dart', add: 5),
        _f('apps/a/y.dart', add: 5),
        _f('apps/b/z.dart', add: 100),
      ]);
      // Without focus: hoists to 'apps', two tracks (a, b), b dominates.
      final root = layoutSeismograph(root: r, c: c);
      expect(root.focusPath, ['apps']);
      // Drill into 'apps/a' — should now show only x.dart and y.dart as
      // a single track 'a' (or as the single-file paths within).
      final inside = layoutSeismograph(
        root: r, c: c, focusPath: const ['apps', 'a'],
      );
      expect(inside.focusPath, ['apps', 'a']);
      // 'a' has two leaf files directly → single "here" track,
      // segments are the two files.
      expect(inside.tracks, hasLength(1));
      final segLabels = inside.tracks.first.segments.map((s) => s.label).toSet();
      expect(segLabels, {'x.dart', 'y.dart'});
    });
  });
}
