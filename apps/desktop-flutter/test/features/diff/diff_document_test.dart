import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';

void main() {
  group('DiffDocument', () {
    test('builds a trimmed single-file document without losing raw diff text',
        () {
      const raw = '''diff --git a/lib/foo.dart b/lib/foo.dart
index 123..456 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,3 +1,3 @@
 line1
-oldValue
+newValue
 line3
''';

      final document = DiffDocument.fromRawContent(
        rawContent: raw,
        pathHint: 'lib/foo.dart',
        trimLeadingMeta: true,
      );

      expect(document.rawContent, raw);
      expect(document.lines.first.kind, LineKind.hunk);
      expect(document.stats.adds, 1);
      expect(document.stats.dels, 1);
      expect(document.stats.hunks, 1);
      expect(document.pairedAddFastKeys, isNotEmpty);
      expect(document.sections.single.path, 'lib/foo.dart');
      expect(document.sections.single.startLine, 0);
    });

    test('combines per-file documents in file order and preserves offsets', () {
      const raw = '''diff --git a/lib/foo.dart b/lib/foo.dart
index 123..456 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,2 +1,2 @@
-oldFoo
+newFoo
 keep
diff --git a/lib/bar.dart b/lib/bar.dart
index abc..def 100644
--- a/lib/bar.dart
+++ b/lib/bar.dart
@@ -3,2 +3,2 @@
-oldBar
+newBar
 keep
''';

      final slices = sliceDiffByFile(raw);
      final foo = DiffFileDocument.fromRawContent(
        rawContent: slices['lib/foo.dart']!,
        pathHint: 'lib/foo.dart',
        cacheKey: 'foo',
      );
      final bar = DiffFileDocument.fromRawContent(
        rawContent: slices['lib/bar.dart']!,
        pathHint: 'lib/bar.dart',
        cacheKey: 'bar',
      );

      final document = DiffDocument.fromFiles(
        files: [foo, bar],
        trimLeadingMeta: false,
      );

      expect(document.sections.map((section) => section.path), [
        'lib/foo.dart',
        'lib/bar.dart',
      ]);
      expect(document.sections.first.startLine, 0);
      expect(document.sections.last.startLine, foo.lines.length);
      expect(document.stats.adds, 2);
      expect(document.stats.dels, 2);
      expect(document.stats.hunks, 2);
      expect(document.rawDiffByPath['lib/foo.dart'], startsWith('diff --git'));
      expect(document.rawDiffByPath['lib/bar.dart'],
          contains('+++ b/lib/bar.dart'));
    });
  });
}
