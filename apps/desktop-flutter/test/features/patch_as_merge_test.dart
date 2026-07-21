// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/changes/patch_as_merge.dart';
import 'package:git_desktop/features/changes/merge_conflict_editor.dart';

/// Sets every block on every file to one side, then concatenates the
/// reconstructed files — lets a test assert the editor would write back
/// exactly `ours` (reject-all) or `theirs` (accept-all).
String _build(List<ConflictFile> files, ConflictSide side) {
  final buf = StringBuffer();
  for (final f in files) {
    for (final b in f.blocks) {
      b.resolution = side;
    }
    buf.write(f.buildResult());
  }
  return buf.toString();
}

void main() {
  group('reviewMergeFromPatch round-trips', () {
    test('single-line modify reproduces both sides exactly', () {
      const ours = 'alpha\nbeta\ngamma\ndelta\nepsilon\n';
      const theirs = 'alpha\nbeta\nGAMMA\ndelta\nepsilon\n';
      const patch = 'diff --git a/f.txt b/f.txt\n'
          'index 1111111..2222222 100644\n'
          '--- a/f.txt\n'
          '+++ b/f.txt\n'
          '@@ -1,5 +1,5 @@\n'
          ' alpha\n'
          ' beta\n'
          '-gamma\n'
          '+GAMMA\n'
          ' delta\n'
          ' epsilon\n';
      final files = reviewMergeFromPatch(patch, {'f.txt': ours});
      expect(files, isNotNull);
      expect(files!.length, 1);
      expect(files.first.blocks.length, 1);
      // Editor defaults to incoming.
      expect(files.first.blocks.first.resolution, ConflictSide.theirs);
      expect(_build(files, ConflictSide.theirs), theirs);
      expect(_build(files, ConflictSide.ours), ours);
    });

    test('two separate hunks in one file', () {
      const ours = 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\n';
      const theirs = 'a\nB\nc\nd\ne\nf\ng\nh\ni\nJ\nk\n';
      // Two changes far enough apart to be distinct hunks.
      const patch = 'diff --git a/f.txt b/f.txt\n'
          'index 1111111..2222222 100644\n'
          '--- a/f.txt\n'
          '+++ b/f.txt\n'
          '@@ -1,5 +1,5 @@\n'
          ' a\n'
          '-b\n'
          '+B\n'
          ' c\n'
          ' d\n'
          ' e\n'
          '@@ -7,5 +7,5 @@\n'
          ' g\n'
          ' h\n'
          ' i\n'
          '-j\n'
          '+J\n'
          ' k\n';
      final files = reviewMergeFromPatch(patch, {'f.txt': ours});
      expect(files, isNotNull);
      expect(files!.first.blocks.length, 2);
      expect(_build(files, ConflictSide.theirs), theirs);
      expect(_build(files, ConflictSide.ours), ours);
    });

    test('multi-line replace block', () {
      const ours = 'head\nx1\nx2\nx3\ntail\n';
      const theirs = 'head\ny1\ny2\ntail\n';
      const patch = 'diff --git a/f.txt b/f.txt\n'
          'index 1111111..2222222 100644\n'
          '--- a/f.txt\n'
          '+++ b/f.txt\n'
          '@@ -1,5 +1,4 @@\n'
          ' head\n'
          '-x1\n'
          '-x2\n'
          '-x3\n'
          '+y1\n'
          '+y2\n'
          ' tail\n';
      final files = reviewMergeFromPatch(patch, {'f.txt': ours});
      expect(files, isNotNull);
      expect(_build(files!, ConflictSide.theirs), theirs);
      expect(_build(files, ConflictSide.ours), ours);
    });

    test('file without trailing newline round-trips', () {
      const ours = 'one\ntwo\nthree';
      const theirs = 'one\nTWO\nthree';
      const patch = 'diff --git a/f.txt b/f.txt\n'
          'index 1111111..2222222 100644\n'
          '--- a/f.txt\n'
          '+++ b/f.txt\n'
          '@@ -1,3 +1,3 @@\n'
          ' one\n'
          '-two\n'
          '+TWO\n'
          ' three\n';
      final files = reviewMergeFromPatch(patch, {'f.txt': ours});
      expect(files, isNotNull);
      expect(_build(files!, ConflictSide.theirs), theirs);
      expect(_build(files, ConflictSide.ours), ours);
    });

    test('misaligned patch returns null (caller falls back to 3-way)', () {
      const drifted = 'ALPHA\nbeta\ngamma\ndelta\nepsilon\n';
      const patch = 'diff --git a/f.txt b/f.txt\n'
          'index 1111111..2222222 100644\n'
          '--- a/f.txt\n'
          '+++ b/f.txt\n'
          '@@ -1,5 +1,5 @@\n'
          ' alpha\n'
          ' beta\n'
          '-gamma\n'
          '+GAMMA\n'
          ' delta\n'
          ' epsilon\n';
      // Context line ' alpha' won't match drifted 'ALPHA'.
      expect(reviewMergeFromPatch(patch, {'f.txt': drifted}), isNull);
    });

    test('new file presents as one block, accept creates it', () {
      const theirs = 'line1\nline2\nline3\n';
      const patch = 'diff --git a/new.txt b/new.txt\n'
          'new file mode 100644\n'
          'index 0000000..3333333\n'
          '--- /dev/null\n'
          '+++ b/new.txt\n'
          '@@ -0,0 +1,3 @@\n'
          '+line1\n'
          '+line2\n'
          '+line3\n';
      final files = reviewMergeFromPatch(patch, const {});
      expect(files, isNotNull);
      expect(files!.length, 1);
      expect(_build(files, ConflictSide.theirs), theirs);
      // Reject-all on a brand-new file yields empty content.
      expect(_build(files, ConflictSide.ours), '');
    });
  });
}
