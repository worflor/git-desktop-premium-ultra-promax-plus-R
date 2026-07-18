import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';

void main() {
  group('DiffDocument', () {
    test('lazy trimLeadingMeta matches the eager rendering contract', () {
      const raw = '''diff --git a/a.txt b/a.txt
index 1111111..2222222 100644
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-old
+new
''';
      final eager = DiffDocument.fromFiles(
        files: [DiffFileDocument.fromRawContent(rawContent: raw)],
        trimLeadingMeta: true,
      );
      final lazy = DiffDocument.lazy(
        rawContent: raw,
        pathHint: 'a.txt',
        trimLeadingMeta: true,
      );

      expect(lazy.trimLeadingMeta, isTrue);
      expect(
        lazy.lines.map((line) => line.text),
        eager.lines.map((line) => line.text),
      );
      expect(lazy.lines.first.kind, LineKind.hunk);
      expect(lazy.hunks.single.lineIndex, 0);
    });

    test(
      'newFilePaths is structural on every backing (blame gate contract)',
      () async {
        // Combined diff: one brand-new file, one modified, one deleted. Only
        // the new file has no committed ancestor — blame must skip exactly it.
        const raw = '''diff --git a/fresh.txt b/fresh.txt
new file mode 100644
index 0000000..2222222
--- /dev/null
+++ b/fresh.txt
@@ -0,0 +1 @@
+hello
diff --git a/mod.txt b/mod.txt
index 1111111..3333333 100644
--- a/mod.txt
+++ b/mod.txt
@@ -1 +1 @@
-old
+new
diff --git a/gone.txt b/gone.txt
deleted file mode 100644
index 4444444..0000000
--- a/gone.txt
+++ /dev/null
@@ -1 +0,0 @@
-bye
''';

        final eager = DiffDocument.fromFiles(
          files: [
            for (final slice in sliceDiffByFile(raw).values)
              DiffFileDocument.fromRawContent(rawContent: slice),
          ],
        );
        expect(
          eager.newFilePaths,
          {'fresh.txt'},
          reason:
              'eager: only the ancestor-less file is new '
              '(a deleted file has an ancestor and stays blame-eligible)',
        );

        final lazy = DiffDocument.lazy(rawContent: raw);
        expect(
          lazy.newFilePaths,
          {'fresh.txt'},
          reason:
              'lazy: the index scan must record new-file status — '
              'file-backed documents have no raw slices to sniff',
        );
      },
    );

    test(
      'orderedPaths reflects real per-file topology on the lazy backing',
      () {
        const raw = '''diff --git a/one.txt b/one.txt
index 1111111..2222222 100644
--- a/one.txt
+++ b/one.txt
@@ -1 +1 @@
-a
+b
diff --git a/two.txt b/two.txt
index 3333333..4444444 100644
--- a/two.txt
+++ b/two.txt
@@ -1 +1 @@
-c
+d
''';
        final lazy = DiffDocument.lazy(rawContent: raw);
        expect(
          lazy.orderedPaths,
          ['one.txt', 'two.txt'],
          reason:
              'the lazy backing stores ONE combined entry in `files`; '
              'orderedPaths must come from sections or a multi-file lazy '
              'doc collapses to a single bogus path',
        );
      },
    );

    test('hunk content cannot forge new-file markers (blame stays on)', () {
      // An ordinary edited file whose CONTENT deletes the literal line
      // `-- /dev/null` and a line reading `new file mode 100644`: the
      // rendered hunk rows are `--- /dev/null` (byte-identical to the real
      // header) and `-new file mode 100644`. A whole-text contains() marks
      // this file ancestor-less and silently turns its blame off.
      const raw = '''diff --git a/notes.md b/notes.md
index 1111111..2222222 100644
--- a/notes.md
+++ b/notes.md
@@ -1,3 +1,2 @@
 keep
--- /dev/null
-new file mode 100644
''';
      final eager = DiffDocument.fromFiles(
        files: [DiffFileDocument.fromRawContent(rawContent: raw)],
      );
      expect(
        eager.newFilePaths,
        isEmpty,
        reason:
            'the markers appear only INSIDE a hunk — the header '
            'declares an ordinary edit, so the file keeps its ancestor',
      );

      final lazy = DiffDocument.lazy(rawContent: raw);
      expect(
        lazy.newFilePaths,
        isEmpty,
        reason:
            'the index scan classifies in-hunk rows as deleted, '
            'never meta — parity with the eager header-bounded sniff',
      );

      // And the genuine article still detects (guard the guard).
      const genuine = '''diff --git a/fresh.txt b/fresh.txt
new file mode 100644
index 0000000..2222222
--- /dev/null
+++ b/fresh.txt
@@ -0,0 +1 @@
+hi
''';
      expect(
        DiffDocument.fromFiles(
          files: [DiffFileDocument.fromRawContent(rawContent: genuine)],
        ).newFilePaths,
        {'fresh.txt'},
      );
    });

    test('header-less unified slices start at ---, not +++', () {
      // A bare (git-header-less) multi-file unified diff: each section's
      // true start is its `--- ` line. Recording the boundary at `+++`
      // returned slices missing their old-side header — breaking the
      // "exact per-file slice" contract for every downstream sniffer.
      const raw = '''--- a/one.txt
+++ b/one.txt
@@ -1 +1 @@
-a
+b
--- a/two.txt
+++ b/two.txt
@@ -1 +1 @@
-c
+d
''';
      final lazy = DiffDocument.lazy(rawContent: raw);
      final sliceOne = lazy.rawSliceForPath('one.txt');
      final sliceTwo = lazy.rawSliceForPath('two.txt');
      expect(sliceOne, isNotNull);
      expect(
        sliceOne,
        startsWith('--- a/one.txt\n'),
        reason: 'the slice must include its own --- header line',
      );
      expect(sliceOne, isNot(contains('two.txt')));
      expect(sliceTwo, startsWith('--- a/two.txt\n'));
      expect(sliceTwo, endsWith('+d\n'));

      // Anchors for the header-less shape: bare unified sections always
      // carry hunks, so each anchors at its first `@@` row by design.
      for (final section in lazy.sections) {
        final firstHunkRow = lazy.hunks
            .firstWhere((h) => h.filePath == section.path)
            .lineIndex;
        expect(
          section.startLine,
          firstHunkRow,
          reason: '${section.path} anchors at its first hunk row',
        );
      }
    });

    test('a multi-file lazy doc never lies about per-file raw slices', () {
      // Bug shape: modified file FIRST, brand-new file SECOND. Storing the
      // combined content under the primary path made the first file's "raw
      // slice" contain the later `new file mode` section — the blame gate
      // sniffed it and wrongly disabled blame on mod.txt.
      const raw = '''diff --git a/mod.txt b/mod.txt
index 1111111..3333333 100644
--- a/mod.txt
+++ b/mod.txt
@@ -1 +1 @@
-old
+new
diff --git a/fresh.txt b/fresh.txt
new file mode 100644
index 0000000..2222222
--- /dev/null
+++ b/fresh.txt
@@ -0,0 +1 @@
+hello
''';
      final lazy = DiffDocument.lazy(rawContent: raw);
      expect(
        lazy.rawDiffByPath,
        isEmpty,
        reason:
            'multi-file lazy docs must not park the WHOLE combined '
            'diff under the primary path — every consumer treats an entry '
            'as that file\'s own slice',
      );
      final slice = lazy.rawSliceForPath('mod.txt');
      expect(slice, contains('+++ b/mod.txt'));
      expect(
        slice,
        isNot(contains('new file mode')),
        reason:
            'the primary file\'s slice must not include later file '
            'sections',
      );
      expect(
        lazy.newFilePaths,
        {'fresh.txt'},
        reason: 'only the genuinely ancestor-less file is blame-ineligible',
      );

      // Single-file lazy docs keep the cheap direct entry (it IS the slice).
      const singleRaw = '''diff --git a/a.txt b/a.txt
index 1111111..2222222 100644
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-x
+y
''';
      final single = DiffDocument.lazy(rawContent: singleRaw);
      expect(single.rawDiffByPath['a.txt'], singleRaw);
    });

    test('a malformed repeated-path patch degrades to the FIRST occurrence '
        'uniformly across every path-keyed API', () {
      // Duplicate paths never come from this app's producers (getSelectionDiff
      // is one HEAD→worktree pass), but an EXTERNAL patch can repeat one. The
      // contract: all sections still RENDER, while path→section resolution
      // collapses to the first occurrence — and it must do so the SAME way for
      // orderedPaths, sections, filesByPath, the hunk-header list, AND
      // rawSliceForPath. The prior bug had them disagree four ways (dup hunk
      // headers, dup sections, filesByPath last-wins, slice first-wins).
      const raw = '''diff --git a/dup.txt b/dup.txt
index 1111111..2222222 100644
--- a/dup.txt
+++ b/dup.txt
@@ -1 +1 @@
-first-old
+first-new
diff --git a/other.txt b/other.txt
index 3333333..4444444 100644
--- a/other.txt
+++ b/other.txt
@@ -1 +1 @@
-mid-old
+mid-new
diff --git a/dup.txt b/dup.txt
index 5555555..6666666 100644
--- a/dup.txt
+++ b/dup.txt
@@ -9 +9 @@
-second-old
+second-new
''';
      final lazy = DiffDocument.lazy(rawContent: raw);

      // Every occurrence's ROWS render in place — nothing is dropped.
      final text = [for (final l in lazy.lines) l.text].join('\n');
      expect(text, contains('+first-new'));
      expect(text, contains('+second-new'));
      expect(text, contains('+mid-new'));

      // orderedPaths + sections: the repeated path appears exactly ONCE.
      expect(
        lazy.orderedPaths,
        ['dup.txt', 'other.txt'],
        reason: 'a repeated path collapses to one first-occurrence entry',
      );
      expect(lazy.sections.where((s) => s.path == 'dup.txt').length, 1);

      // Hunk headers: each hunk listed once (no per-section duplication).
      expect(
        lazy.hunks.where((h) => h.filePath == 'dup.txt').length,
        2,
        reason: 'both dup.txt hunks are navigable, neither duplicated',
      );

      // filesByPath resolves the FIRST occurrence (was last-wins), agreeing
      // with rawSliceForPath's first-wins byte range.
      expect(lazy.filesByPath['dup.txt'], isNotNull);
      final slice = lazy.rawSliceForPath('dup.txt')!;
      expect(
        slice,
        contains('+first-new'),
        reason: 'the slice is the FIRST dup.txt section',
      );
      expect(
        slice,
        isNot(contains('+second-new')),
        reason: 'the first slice must not bleed into the later section',
      );
      expect(
        slice,
        isNot(contains('other.txt')),
        reason: 'nor into the intervening file',
      );

      // ADJACENT repeats of the SAME path are a different, non-buggy shape:
      // the predictive index scan starts a new file entry only when the path
      // CHANGES (see predictive_diff_index's `currentFile != previousFile`),
      // so two back-to-back `diff --git a/a.txt` blocks merge into one logical
      // file. Treating that as a single-file document — whole content as its
      // slice — is correct and internally consistent (one section, one
      // filesByPath entry, one slice), so it legitimately keeps the cheap
      // rawDiffByPath shortcut.
      const adjacentDup = '''diff --git a/a.txt b/a.txt
index 1111111..2222222 100644
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-p
+q
diff --git a/a.txt b/a.txt
index 3333333..4444444 100644
--- a/a.txt
+++ b/a.txt
@@ -9 +9 @@
-r
+s
''';
      final merged = DiffDocument.lazy(rawContent: adjacentDup);
      expect(
        merged.orderedPaths,
        ['a.txt'],
        reason: 'adjacent same-path sections merge into one logical file',
      );
      final mergedSlice = merged.rawSliceForPath('a.txt')!;
      expect(mergedSlice, contains('+q'));
      expect(
        mergedSlice,
        contains('+s'),
        reason: 'the merged file legitimately spans both adjacent sections',
      );
    });

    test('a same-length in-place edit mints a NEW working-file document '
        'identity (shell rebuild trigger)', () async {
      final dir = await Directory.systemTemp.createTemp('newfile_identity');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}${Platform.pathSeparator}fixed.txt');

      await f.writeAsString('AAAA\n');
      final docA = await DiffDocument.lazyFromWorkingFile(f.path, 'fixed.txt');
      final idA = docA.documentId;
      docA.dispose();

      // Same byte length, different content, NO delay: FileStat.modified has
      // second granularity on Windows, so this deliberately lands in the
      // same mtime second as the first write — the sampled content
      // fingerprint must carry the identity change on its own.
      await f.writeAsString('BBBB\n');
      final docB = await DiffDocument.lazyFromWorkingFile(f.path, 'fixed.txt');
      final idB = docB.documentId;
      docB.dispose();

      expect(
        idB,
        isNot(idA),
        reason:
            'path+length identity is blind to same-size edits (and mtime is '
            'blind within one second) — the shell keys rebuilds on '
            'documentId, so a stale id pins the viewer to the old store',
      );

      // LARGE file, same-length edit INSIDE a sampled window (the tail):
      // the fingerprint must catch it.
      final big = File('${dir.path}${Platform.pathSeparator}big.txt');
      final base = List<int>.filled(64 * 1024, 0x61); // 64KB of 'a'
      await big.writeAsBytes(base);
      final bigA = await DiffDocument.lazyFromWorkingFile(big.path, 'big.txt');
      final bigIdA = bigA.documentId;
      bigA.dispose();
      base[base.length - 100] = 0x62; // inside the 4KB tail sample
      await big.writeAsBytes(base);
      final bigB = await DiffDocument.lazyFromWorkingFile(big.path, 'big.txt');
      expect(bigB.documentId, isNot(bigIdA));
      bigB.dispose();

      // KNOWN LIMITATION, deliberately pinned: a same-length edit OUTSIDE
      // all three 4KB sample windows, within the same mtime second, keeps
      // the id stable. Correctness does not depend on this: DiffShell
      // ADOPTS a new document instance even when the id is unchanged (the
      // old instance's store is disposed by the page), so the fresh bytes
      // always render — the id only decides whether view state resets. If
      // the fingerprint is ever strengthened to full content, flip this
      // expectation.
      base[20000] = 0x63; // between the head and middle windows
      await big.writeAsBytes(base);
      final bigC = await DiffDocument.lazyFromWorkingFile(big.path, 'big.txt');
      final sameSecond =
          bigC.documentId.split(':')[3] == bigB.documentId.split(':')[3];
      if (sameSecond) {
        expect(
          bigC.documentId,
          bigB.documentId,
          reason:
              'the sampled fingerprint cannot see this edit — the '
              'shell-side instance adoption is the load-bearing backstop',
        );
      }
      bigC.dispose();
    });

    test('rawSliceForPath refuses a working-file backing (store bytes are '
        'contents, not a diff)', () async {
      final dir = await Directory.systemTemp.createTemp('rawslice_newfile');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}${Platform.pathSeparator}fresh.txt');
      await f.writeAsString('hello\nworld\n');
      final doc = await DiffDocument.lazyFromWorkingFile(f.path, 'fresh.txt');
      try {
        // The rows render as a synthetic all-added diff...
        expect(
          doc.lines.any(
            (l) => l.kind == LineKind.added && l.text.contains('hello'),
          ),
          isTrue,
          reason: 'the working file must hydrate as added rows',
        );
        // ...but there are no raw diff BYTES to slice: the store is the
        // working file itself. Returning its bytes would hand back file
        // contents masquerading as a patch.
        expect(doc.rawSliceForPath('fresh.txt'), isNull);
      } finally {
        doc.dispose();
      }
    });

    test('trimLeadingMeta never blanks a meta-only document '
        '(untracked empty + binary files)', () async {
      final dir = await Directory.systemTemp.createTemp('metaonly_trim');
      addTearDown(() => dir.delete(recursive: true));

      // Empty untracked file: the whole synthetic diff is meta rows.
      final empty = File('${dir.path}${Platform.pathSeparator}empty.txt');
      await empty.writeAsString('');
      final emptyDoc = await DiffDocument.lazyFromWorkingFile(
        empty.path,
        'empty.txt',
        trimLeadingMeta: true,
      );
      try {
        expect(
          emptyDoc.lines,
          isNotEmpty,
          reason:
              'the meta rows ARE the change for an empty file — '
              'trimming them hides a real creation from the reviewer',
        );
        expect(
          emptyDoc.lines.any((l) => l.text.contains('new file mode')),
          isTrue,
        );
      } finally {
        emptyDoc.dispose();
      }

      // Binary untracked file (NUL in the first page): marker-only diff.
      final bin = File('${dir.path}${Platform.pathSeparator}blob.bin');
      await bin.writeAsBytes(List<int>.generate(64, (i) => i % 7 == 0 ? 0 : i));
      final binDoc = await DiffDocument.lazyFromWorkingFile(
        bin.path,
        'blob.bin',
        trimLeadingMeta: true,
      );
      try {
        expect(
          binDoc.lines,
          isNotEmpty,
          reason: 'the binary marker IS the change for a binary file',
        );
        expect(
          binDoc.lines.any((l) => l.text.startsWith('Binary files ')),
          isTrue,
        );
      } finally {
        binDoc.dispose();
      }

      // Eager symmetry: a marker-only raw diff survives the same trim.
      const raw = '''diff --git a/img.png b/img.png
new file mode 100644
index 0000000..1111111
Binary files /dev/null and b/img.png differ
''';
      final eager = DiffDocument.fromRawContent(
        rawContent: raw,
        pathHint: 'img.png',
        trimLeadingMeta: true,
      );
      expect(
        eager.lines,
        isNotEmpty,
        reason: 'eager path: same guard — meta-only documents keep rows',
      );
      expect(
        eager.lines.any((l) => l.text.startsWith('Binary files ')),
        isTrue,
      );
    });

    test('lazy topology retains binary and hunkless file sections', () {
      const raw = '''diff --git a/image.bin b/image.bin
index 1111111..2222222 100644
Binary files a/image.bin and b/image.bin differ
diff --git a/empty.txt b/empty.txt
deleted file mode 100644
index e69de29..0000000
--- a/empty.txt
+++ /dev/null
diff --git a/code.dart b/code.dart
index 3333333..4444444 100644
--- a/code.dart
+++ b/code.dart
@@ -1 +1 @@
-old
+new
''';

      final document = DiffDocument.lazy(rawContent: raw);
      expect(document.sections.map((section) => section.path), [
        'image.bin',
        'empty.txt',
        'code.dart',
      ]);
      expect(
        document.filesByPath.keys,
        containsAll(['image.bin', 'empty.txt', 'code.dart']),
      );
      expect(document.filesByPath['image.bin']!.isBinary, isTrue);
      expect(document.filesByPath['empty.txt']!.stats.hunks, 0);
      expect(
        document.sections[0].startLine,
        lessThan(document.sections[2].startLine),
      );
      // EXACT anchor contract, not just ordering. Two tiers by design:
      // hunk-ful sections anchor at their FIRST HUNK row; hunkless sections
      // (binary, empty, mode-only — which only exist in git-header diffs)
      // anchor at their first VISIBLE row. Git header lines (`diff --git`,
      // `index`) never emit display rows, so `count` at the header IS the
      // first visible row — hand-computed raw line numbers are the wrong
      // model for these anchors.
      for (final section in document.sections) {
        final hunkRows = document.hunks
            .where((h) => h.filePath == section.path)
            .map((h) => h.lineIndex);
        final expected = hunkRows.isNotEmpty
            ? hunkRows.first
            : document.lines.indexWhere((l) => l.filePath == section.path);
        expect(
          section.startLine,
          expected,
          reason:
              '${section.path} must anchor at its first hunk (or first '
              'visible row when hunkless)',
        );
      }
    });

    test('payloadBytes means UTF-8 bytes on every backing', () {
      // CJK-heavy diff: UTF-16 code units are ~1/3 of the UTF-8 bytes. The
      // in-RAM lazy path once reported the store's code-unit length as
      // payloadBytes, drifting size-branching heuristics between backings.
      const raw = '''diff --git a/cjk.txt b/cjk.txt
index 1111111..2222222 100644
--- a/cjk.txt
+++ b/cjk.txt
@@ -1 +1 @@
-古い行のテキスト
+新しい行のテキスト
''';
      final eager = DiffDocument.fromRawContent(
        rawContent: raw,
        pathHint: 'cjk.txt',
      );
      final lazy = DiffDocument.lazy(rawContent: raw, pathHint: 'cjk.txt');
      expect(
        lazy.payloadBytes,
        eager.payloadBytes,
        reason: 'the two in-RAM backings must agree on the byte metric',
      );
      expect(
        lazy.payloadBytes,
        greaterThan(raw.length),
        reason:
            'UTF-8 bytes exceed code units for CJK content — equal '
            'values would mean the code-unit length leaked back in',
      );
    });

    test(
      'builds a trimmed single-file document without losing raw diff text',
      () {
        const raw = '''diff --git a/lib/foo.dart b/lib/foo.dart
index 123..456 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,3 +1,3 @@
 line1
-  return oldValue;
+  return oldValue + 1;
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
      },
    );

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
      // Section startLine indexes into the *combined* document.lines, where
      // each file's path-meta lines (`diff --git`, `index`, `---`, `+++`)
      // are condensed into a single line. So foo's 6 raw parsed lines
      // contribute 5 lines to the merged document, and bar's section
      // begins at line 5.
      expect(document.sections.last.startLine, 5);
      expect(document.stats.adds, 2);
      expect(document.stats.dels, 2);
      expect(document.stats.hunks, 2);
      expect(document.rawDiffByPath['lib/foo.dart'], startsWith('diff --git'));
      expect(
        document.rawDiffByPath['lib/bar.dart'],
        contains('+++ b/lib/bar.dart'),
      );
    });
  });

  group('giant machine-generated diffs', () {
    // Builds a single-file diff that rewrites `changed` lines. Above
    // kLeanDiffLineThreshold this is the shape (a regenerated dataset, a
    // road-graph rewrite) that used to freeze the app for minutes: eager
    // per-line SimHash + an O(deletes·inserts) fuzzy move pass.
    String rewriteDiff(int changed) {
      final b = StringBuffer()
        ..writeln('diff --git a/data.txt b/data.txt')
        ..writeln('index 1111111..2222222 100644')
        ..writeln('--- a/data.txt')
        ..writeln('+++ b/data.txt')
        ..writeln('@@ -1,$changed +1,$changed @@');
      for (var i = 0; i < changed; i++) {
        b.writeln('-data row $i');
      }
      for (var i = 0; i < changed; i++) {
        b.writeln('+data row $i CHANGED');
      }
      return b.toString();
    }

    test('a diff past the lean threshold parses fully and fast, skipping '
        'the super-linear move-detection index', () {
      const changed = kLeanDiffLineThreshold + 50000; // comfortably over
      final raw = rewriteDiff(changed);

      final sw = Stopwatch()..start();
      final document = DiffDocument.fromRawContent(
        rawContent: raw,
        pathHint: 'data.txt',
        trimLeadingMeta: true,
      );
      sw.stop();

      // Every changed line is present and rendered (no cap, no stub).
      expect(document.stats.adds, changed);
      expect(document.stats.dels, changed);
      // The lean gate skipped edit-unit indexing entirely — this is what
      // makes the build finish instead of running an O(n²) fuzzy pass over
      // hundreds of thousands of delete/insert units.
      expect(document.unitByFastKey, isEmpty);
      expect(document.pairedAddFastKeys, isEmpty);
      // A loose ceiling: the whole build is linear now. Without the fix the
      // move pass alone would run for minutes and never reach this line.
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 20)),
        reason: 'lean build must be linear, not quadratic',
      );
    });

    test('deriving a line signature never happens at parse time, only on '
        'demand, and is still correct when it does', () {
      final lines = parseUnifiedDiff(rewriteDiff(5));
      final added = lines.firstWhere((l) => l.kind == LineKind.added);

      // Lazy fields agree exactly with an eager recompute from `text`.
      expect(added.lowerText, added.text.toLowerCase());
      expect(
        added.charBits,
        ParsedLine.queryCharBits(added.text.toLowerCase()),
      );
      expect(
        added.bigramBits,
        ParsedLine.queryBigramBits(added.text.toLowerCase()),
      );
      // simHash is stable across repeated access (the late-final cache).
      expect(added.simHash, added.simHash);
    });

    test('the FULL ingestion path (parse → document → shell copy) stays '
        'bounded-linear at a large payload — no catastrophe', () {
      // The reviewer's boundary: with the backend line-ceiling removed, a
      // large text diff flows through parse + document build + the shell's
      // `List<ParsedLine>.of(document.lines)` copy. This exercises all three
      // at ~1M changed lines (2M parsed rows, ~40MB) — CI-safe, but any
      // regression that reintroduced a super-linear pass (the old simHash
      // storm, the exact/fuzzy O(n²)) or lost content would blow the ceiling
      // or the assertions here long before GB scale.
      const changed = 1000000;
      final raw = rewriteDiff(changed);

      final sw = Stopwatch()..start();
      final doc = DiffFileDocument.fromRawContent(
        rawContent: raw,
        pathHint: 'data.txt',
      );
      // Mirror DiffShell._applyDocument's whole-list copy.
      final shellCopy = List<ParsedLine>.of(doc.lines);
      sw.stop();

      // Content is complete — nothing capped, stubbed, or dropped.
      expect(doc.stats.adds, changed);
      expect(doc.stats.dels, changed);
      // 2·changed body rows + the handful of meta/hunk header rows.
      expect(shellCopy.length, greaterThanOrEqualTo(2 * changed));
      expect(doc.unitByFastKey, isEmpty, reason: 'lean gate active');
      // Generous linear ceiling — a quadratic/OOM regression cannot meet it.
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 30)),
        reason: 'full ingestion of a large diff must stay bounded-linear',
      );
    });
  });
}
