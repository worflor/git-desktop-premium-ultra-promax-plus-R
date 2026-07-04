import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/edit_units.dart';

String _render(List<WordDiffSpan> spans) => spans
    .map((s) => switch (s.role) {
          WordDiffRole.common => s.text,
          WordDiffRole.removed => '[-${s.text}-]',
          WordDiffRole.added => '[+${s.text}+]',
        })
    .join();

void main() {
  group('computeInlineWordDiff', () {
    test('one-token change emphasizes just the changed token', () {
      final spans = computeInlineWordDiff('-final x = bar;', '+final x = baz;');
      expect(spans, isNotNull);
      expect(_render(spans!), 'final x = [-bar-][+baz+];');
    });

    test('identical after sign-strip returns null', () {
      expect(computeInlineWordDiff('-same text', '+same text'), isNull);
    });

    test('blank-sided pairs refuse: no one-sided span sets', () {
      // A content line "replaced" by a blank line has no intra-line story;
      // rendering all-removed spans as the post-state row would lie about
      // the patch (the post-state is blank).
      expect(computeInlineWordDiff('-old text', '+'), isNull);
      expect(computeInlineWordDiff('-old text', '+   '), isNull);
      expect(computeInlineWordDiff('-', '+new text'), isNull);
    });

    test('over-long lines bail to null (plain fallback)', () {
      final long = '-${'a' * 3000}';
      expect(computeInlineWordDiff(long, '+short'), isNull);
    });

    test('full rewrite still yields removed-then-added runs', () {
      final spans =
          computeInlineWordDiff('-alpha beta gamma', '+delta epsilon');
      expect(spans, isNotNull);
      final roles = spans!.map((s) => s.role).toSet();
      expect(roles.contains(WordDiffRole.removed), isTrue);
      expect(roles.contains(WordDiffRole.added), isTrue);
      // Reading order: post-state must be reconstructible from common+added.
      final post = spans
          .where((s) => s.role != WordDiffRole.removed)
          .map((s) => s.text)
          .join();
      expect(post, 'delta epsilon');
    });
  });

  group('wordDiffIsCoherent', () {
    test('single-token replacement in a stable line is coherent', () {
      final spans = computeInlineWordDiff(
          '-      hunkIndex: hunkIdx));', '+      hunkIndex: -1));');
      expect(spans, isNotNull);
      expect(wordDiffIsCoherent(spans!), isTrue);
    });

    test('mostly-different prose lines are NOT coherent (word salad)', () {
      // The field specimen: scattered accidental anchors ("got") stitched
      // two unrelated sentences into unreadable interleave.
      final spans = computeInlineWordDiff(
          "-'History DAG got a minor upgrade.',",
          "+'wait. undo that, it is actually a major overhaul. (undo got "
          "upgraded too)',");
      expect(spans, isNotNull);
      expect(wordDiffIsCoherent(spans!), isFalse);
    });

    test('rewritten code line with token confetti is NOT coherent', () {
      final spans = computeInlineWordDiff(
          '-if (!patch.endsWith( )) process.stdin.writeln();',
          '+// Raw UTF-8 bytes, never IOSink.write: process stdin defaults');
      expect(spans, isNotNull);
      expect(wordDiffIsCoherent(spans!), isFalse);
    });

    test('small tail edit in a long sentence stays coherent', () {
      final spans = computeInlineWordDiff(
          '-The review verdict looks cooler now. No deeper meaning, just',
          '+The review verdict looks cooler now. No deeper meaning beyond');
      expect(spans, isNotNull);
      expect(wordDiffIsCoherent(spans!), isTrue);
    });
  });

  group('coherence-gated pairing', () {
    test('salad pairs fall back to separate delete + insert rows', () {
      final lines = parseUnifiedDiff('''
diff --git a/f.txt b/f.txt
--- a/f.txt
+++ b/f.txt
@@ -1,2 +1,2 @@
-'History DAG got a minor upgrade.',
+'wait. undo that, it is actually a major overhaul. (undo got upgraded too)',
 context
''');
      final units = buildEditUnits(lines);
      final kinds = units.map((u) => u.kind).toList();
      expect(kinds.contains(EditKind.replace), isFalse,
          reason: 'incoherent pairs must render both truths whole');
      expect(kinds.where((k) => k == EditKind.delete).length, 1);
      expect(kinds.where((k) => k == EditKind.insert).length, 1);
    });

    test('coherent small edits still fuse with spans attached', () {
      final lines = parseUnifiedDiff('''
diff --git a/f.txt b/f.txt
--- a/f.txt
+++ b/f.txt
@@ -1,2 +1,2 @@
-          hunkIndex: hunkIdx));
+          hunkIndex: -1));
 context
''');
      final units = buildEditUnits(lines);
      final replace = units.where((u) => u.kind == EditKind.replace).toList();
      expect(replace, hasLength(1));
      expect(replace.single.wordDiff, isNotNull);
    });

    test('guard-null (over-long) pairs still fuse with plain fallback', () {
      final long = 'x' * 3000;
      final lines = parseUnifiedDiff('diff --git a/f.txt b/f.txt\n'
          '--- a/f.txt\n+++ b/f.txt\n@@ -1,2 +1,2 @@\n-$long a\n+$long b\n ctx\n');
      final units = buildEditUnits(lines);
      final replace = units.where((u) => u.kind == EditKind.replace).toList();
      expect(replace, hasLength(1));
      expect(replace.single.wordDiff, isNull);
    });
  });

  group('buildEditUnits blank-sided pairing', () {
    test('content deleted, blank added stays two units (no replace fusion)',
        () {
      final lines = parseUnifiedDiff('''
diff --git a/f.txt b/f.txt
--- a/f.txt
+++ b/f.txt
@@ -1,2 +1,2 @@
-old text
+
 context
''');
      final units = buildEditUnits(lines);
      final kinds = units.map((u) => u.kind).toList();
      expect(kinds.contains(EditKind.replace), isFalse,
          reason: 'blank-sided pairs must not fuse into a replace row');
      expect(kinds.where((k) => k == EditKind.delete).length, 1);
      expect(kinds.where((k) => k == EditKind.insert).length, 1);
    });

    test('content-to-content still fuses with a word diff attached', () {
      final lines = parseUnifiedDiff('''
diff --git a/f.txt b/f.txt
--- a/f.txt
+++ b/f.txt
@@ -1,2 +1,2 @@
-final x = bar;
+final x = baz;
 context
''');
      final units = buildEditUnits(lines);
      final replace =
          units.where((u) => u.kind == EditKind.replace).toList();
      expect(replace, hasLength(1));
      expect(replace.single.wordDiff, isNotNull);
    });
  });
}
