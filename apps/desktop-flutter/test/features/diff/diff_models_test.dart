import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_models.dart';

void main() {
  group('parseUnifiedDiff', () {
    test(
      'tracks file paths for bare unified diffs without diff --git header',
      () {
        const raw = '''--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,3 +1,3 @@
 line1
-oldValue
+newValue
 line3
''';

        final lines = parseUnifiedDiff(raw);
        final touchedPaths = {
          for (final line in lines)
            if (line.filePath != null && line.filePath!.isNotEmpty)
              line.filePath!,
        };

        expect(touchedPaths, {'lib/foo.dart'});
        expect(
          lines.where((line) => line.kind == LineKind.added).single.filePath,
          'lib/foo.dart',
        );
      },
    );
  });

  group('sliceDiffByFile', () {
    test('extracts one section without treating hunk content as a header', () {
      const raw = '''diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-old
+diff --git is content
diff --git a/b.txt b/b.txt
--- a/b.txt
+++ b/b.txt
@@ -1 +1 @@
-before
+after
''';
      final slice = sliceSingleDiffByFile(raw, 'a.txt');
      expect(slice, contains('+diff --git is content'));
      expect(slice, isNot(contains('a/b.txt')));
      expect(
        sliceDiffByFileForDetail('x' * (kEagerDiffSliceThreshold + 1)),
        isEmpty,
      );
    });

    test('splits bare unified diff payloads by file', () {
      const raw = '''--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,2 +1,2 @@
-oldFoo
+newFoo
 keep
--- a/lib/bar.dart
+++ b/lib/bar.dart
@@ -3,2 +3,2 @@
-oldBar
+newBar
 keep
''';

      final slices = sliceDiffByFile(raw);

      expect(slices.keys, ['lib/foo.dart', 'lib/bar.dart']);
      expect(slices['lib/foo.dart'], startsWith('--- a/lib/foo.dart'));
      expect(slices['lib/bar.dart'], contains('+++ b/lib/bar.dart'));
    });
  });
}
