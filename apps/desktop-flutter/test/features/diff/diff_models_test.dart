import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_models.dart';

void main() {
  group('parseUnifiedDiff', () {
    test('tracks file paths for bare unified diffs without diff --git header',
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
          if (line.filePath != null && line.filePath!.isNotEmpty) line.filePath!,
      };

      expect(touchedPaths, {'lib/foo.dart'});
      expect(
        lines.where((line) => line.kind == LineKind.added).single.filePath,
        'lib/foo.dart',
      );
    });
  });

  group('sliceDiffByFile', () {
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
