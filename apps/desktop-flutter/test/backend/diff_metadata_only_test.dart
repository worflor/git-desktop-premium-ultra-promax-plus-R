// Tests for `_extractMetadataOnlyChanges` — the side capture that
// preserves visibility of binary/mode-only/pure-rename file changes
// under the unified diff pipeline. The hunk parser drops these
// silently (no `@@` markers); without this capture they'd disappear
// from the AI prompt entirely under the unified-pipeline regression
// the audit caught.
//
// Function is private to ai.dart, so we test it via a same-library
// helper exported `@visibleForTesting`.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart' show extractMetadataOnlyChangesForTesting;

void main() {
  group('metadata-only diff capture', () {
    test('binary file change is captured (index line filtered as noise)', () {
      const diff = '''
diff --git a/assets/logo.png b/assets/logo.png
index abc123..def456 100644
Binary files a/assets/logo.png and b/assets/logo.png differ
''';
      final out = extractMetadataOnlyChangesForTesting(diff);
      expect(out.keys, ['assets/logo.png']);
      expect(out['assets/logo.png']!.join('\n'), contains('Binary files'));
      // `index` lines are blob SHAs — useless for AI; filtered out.
      expect(out['assets/logo.png']!.join('\n'),
          isNot(contains('index abc123..def456')));
    });

    test('mode-only change is captured', () {
      const diff = '''
diff --git a/scripts/run.sh b/scripts/run.sh
old mode 100644
new mode 100755
''';
      final out = extractMetadataOnlyChangesForTesting(diff);
      expect(out.keys, ['scripts/run.sh']);
      expect(out['scripts/run.sh']!.join('\n'), contains('old mode 100644'));
      expect(out['scripts/run.sh']!.join('\n'), contains('new mode 100755'));
    });

    test('pure rename (no content change) is captured', () {
      const diff = '''
diff --git a/old/path.dart b/new/path.dart
similarity index 100%
rename from old/path.dart
rename to new/path.dart
''';
      final out = extractMetadataOnlyChangesForTesting(diff);
      expect(out.keys, ['new/path.dart']);
      expect(out['new/path.dart']!.join('\n'), contains('rename from'));
      expect(out['new/path.dart']!.join('\n'), contains('similarity index'));
    });

    test('plain text-only edits with no notable metadata produce no entry',
        () {
      // index/---/+++ are filtered as noise; nothing meaningful left.
      const diff = '''
diff --git a/lib/foo.dart b/lib/foo.dart
index abc..def 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,3 +1,3 @@
 line1
-removed
+added
 line3
''';
      final out = extractMetadataOnlyChangesForTesting(diff);
      expect(out, isEmpty);
    });

    test('mode change + content edit: mode metadata preserved', () {
      // Regression test for the audit-found bug where files with both
      // metadata AND @@ hunks lost their mode lines.
      const diff = '''
diff --git a/scripts/run.sh b/scripts/run.sh
old mode 100644
new mode 100755
index abc..def
--- a/scripts/run.sh
+++ b/scripts/run.sh
@@ -1,3 +1,3 @@
 #!/bin/bash
-echo old
+echo new
''';
      final out = extractMetadataOnlyChangesForTesting(diff);
      expect(out.keys, ['scripts/run.sh']);
      expect(out['scripts/run.sh']!.join('\n'), contains('old mode 100644'));
      expect(out['scripts/run.sh']!.join('\n'), contains('new mode 100755'));
      // index line is filtered as noise.
      expect(out['scripts/run.sh']!.join('\n'), isNot(contains('index abc..def')));
    });

    test('quoted paths (git C-string quoting for spaces) parse correctly',
        () {
      const diff = '''
diff --git "a/path with spaces.txt" "b/path with spaces.txt"
old mode 100644
new mode 100755
''';
      final out = extractMetadataOnlyChangesForTesting(diff);
      expect(out.keys, ['path with spaces.txt']);
      expect(out['path with spaces.txt']!.join('\n'), contains('old mode'));
    });

    test('mixed diff: text-change file + binary file', () {
      // Realistic case — a single commit that touches a normal file
      // AND adds a binary asset. Hunk parser handles the text file;
      // metadata capture handles the binary one.
      const diff = '''
diff --git a/lib/foo.dart b/lib/foo.dart
index abc..def 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,3 +1,3 @@
 line1
-removed
+added
 line3
diff --git a/assets/icon.png b/assets/icon.png
new file mode 100644
index 0000000..abc123
Binary files /dev/null and b/assets/icon.png differ
''';
      final out = extractMetadataOnlyChangesForTesting(diff);
      // Only the binary file shows up — the text file is handled by hunks.
      expect(out.keys, ['assets/icon.png']);
      expect(out['assets/icon.png']!.join('\n'),
          contains('Binary files /dev/null'));
      expect(out['assets/icon.png']!.join('\n'),
          contains('new file mode 100644'));
    });

    test('empty diff produces no captures', () {
      expect(extractMetadataOnlyChangesForTesting(''), isEmpty);
    });

    test('--- and +++ markers are stripped (auto-emitted by packer anyway)',
        () {
      // For metadata-only files there are no @@ blocks, so no --- /
      // +++ should appear normally — but if the diff somehow includes
      // them without hunks (malformed), we filter for cleanliness.
      const diff = '''
diff --git a/x b/x
old mode 100644
new mode 100755
--- a/x
+++ b/x
''';
      final out = extractMetadataOnlyChangesForTesting(diff);
      final body = out['x']!.join('\n');
      expect(body, contains('old mode'));
      expect(body, isNot(contains('--- a/x')));
      expect(body, isNot(contains('+++ b/x')));
    });
  });
}
