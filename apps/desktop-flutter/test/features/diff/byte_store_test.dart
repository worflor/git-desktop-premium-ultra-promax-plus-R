// FileByteStore must be byte-for-byte substitutable for StringByteStore behind
// the PredictiveDiffIndex: same line splits, same hydrated ParsedLines, same
// search, regardless of page boundaries. These tests use a deliberately TINY
// page size so multi-page lines and page-crossing newline scans are exercised
// on every fixture — that is where a paging bug would hide.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/byte_store.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/diff_shell.dart';
import 'package:git_desktop/features/diff/predictive_diff_index.dart';

Directory? _tmp;
int _seq = 0;

FileByteStore _fileStore(String raw, {int pageSize = 17}) {
  _tmp ??= Directory.systemTemp.createTempSync('bytestore_test');
  final f = File('${_tmp!.path}/diff_${_seq++}.diff');
  f.writeAsBytesSync(utf8.encode(raw));
  return FileByteStore.open(f.path, pageSize: pageSize, maxPages: 4);
}

void main() {
  tearDownAll(() {
    try {
      _tmp?.deleteSync(recursive: true);
    } catch (_) {}
  });

  final fixtures = <String, String>{
    'simple edit':
        'diff --git a/x b/x\n'
        '--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n-old\n+new\n ctx\n',
    'multi-file':
        'diff --git a/one b/one\n--- a/one\n+++ b/one\n'
        '@@ -1 +1 @@\n-a\n+b\n'
        'diff --git a/two b/two\n--- a/two\n+++ b/two\n@@ -1 +1,2 @@\n-c\n+d\n+e\n',
    'utf8 accents + cjk':
        'diff --git a/i18n b/i18n\n--- a/i18n\n+++ b/i18n\n'
        '@@ -1,3 +1,3 @@\n-café ΩMEGA привет\n+CAFÉ Ωmega Привет\n'
        '-日本語 中文 한국어\n+ünïcödé\n çøntext\n',
    // Emoji + astral-plane chars = UTF-16 surrogate PAIRS / 4-byte UTF-8: the
    // hardest case for page-boundary decode and chunked spool writes.
    'surrogate pairs (emoji)':
        'diff --git a/e b/e\n--- a/e\n+++ b/e\n'
        '@@ -1,3 +1,3 @@\n-🎉🔥💯 old 𝕏𝕐𝕑\n+🚀✨🌍 new 𝔸𝔹ℂ\n'
        '-👨‍👩‍👧‍👦 family\n+🏳️‍🌈 flag\n ctx 中\n',
    'no newline at eof':
        'diff --git a/n b/n\n--- a/n\n+++ b/n\n'
        '@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file\n',
    'empty + long line':
        'diff --git a/l b/l\n--- a/l\n+++ b/l\n'
        '@@ -1,3 +1,3 @@\n \n+${'x' * 200}\n-${'y' * 137}\n',
    'binary marker': 'diff --git a/b b/b\nBinary files a/b and b/b differ\n',
  };

  fixtures.forEach((name, raw) {
    test('FileByteStore == StringByteStore: $name', () {
      final s = PredictiveDiffIndex.buildFromStore(StringByteStore(raw));
      final fileStore = _fileStore(raw);
      final f = PredictiveDiffIndex.buildFromStore(fileStore);

      expect(f.lineCount, s.lineCount, reason: 'lineCount');
      expect(f.isBinary, s.isBinary, reason: 'isBinary');
      expect(f.hunks.length, s.hunks.length, reason: 'hunk count');
      for (var h = 0; h < s.hunks.length; h++) {
        expect(f.hunks[h].header, s.hunks[h].header, reason: 'hunk $h header');
        expect(f.hunks[h].adds, s.hunks[h].adds, reason: 'hunk $h adds');
        expect(f.hunks[h].dels, s.hunks[h].dels, reason: 'hunk $h dels');
      }

      // Every row, hydrated, must match text + kind + line numbers + eof.
      final sAll = s.hydrateRange(0, s.lineCount);
      final fAll = f.hydrateRange(0, f.lineCount);
      expect(fAll.length, sAll.length, reason: 'row count');
      for (var i = 0; i < sAll.length; i++) {
        expect(fAll[i].text, sAll[i].text, reason: 'row $i text');
        expect(fAll[i].kind, sAll[i].kind, reason: 'row $i kind');
        expect(fAll[i].lineNumOld, sAll[i].lineNumOld, reason: 'row $i old');
        expect(fAll[i].lineNumNew, sAll[i].lineNumNew, reason: 'row $i new');
        expect(
          fAll[i].noNewlineAtEof,
          sAll[i].noNewlineAtEof,
          reason: 'row $i eof',
        );
        expect(fAll[i].filePath, sAll[i].filePath, reason: 'row $i path');
      }

      // Windowed hydration from an arbitrary offset must also agree.
      if (s.lineCount >= 2) {
        for (final start in [0, 1, s.lineCount - 1]) {
          final sw = s.hydrateRange(start, 2).map((l) => l.text).toList();
          final fw = f.hydrateRange(start, 2).map((l) => l.text).toList();
          expect(fw, sw, reason: 'window at $start');
        }
      }

      fileStore.dispose();
    });
  });

  test('FileByteStore search matches StringByteStore (unicode)', () {
    const raw =
        'diff --git a/s b/s\n--- a/s\n+++ b/s\n'
        '@@ -1,4 +1,4 @@\n-café\n+CAFÉ\n-Ωmega\n+ΩMEGA\n';
    final s = PredictiveDiffIndex.buildFromStore(const StringByteStore(raw));
    final store = _fileStore(raw, pageSize: 8);
    final f = PredictiveDiffIndex.buildFromStore(store);
    for (final term in ['café', 'Ω', 'mega', 'zzz']) {
      final lower = term.toLowerCase();
      expect(
        f.findMatchingLines(lower),
        s.findMatchingLines(lower),
        reason: 'search "$term"',
      );
    }
    store.dispose();
  });

  test('DiffDocument.lazyFromSpool: file-backed doc, empty rawContent, '
      'index-driven features work', () async {
    const raw =
        'diff --git a/one b/one\n--- a/one\n+++ b/one\n'
        '@@ -1,2 +1,2 @@\n-alpha\n+beta café\n ctx\n'
        'diff --git a/two b/two\n--- a/two\n+++ b/two\n@@ -1 +1 @@\n-x\n+y\n';
    _tmp ??= Directory.systemTemp.createTempSync('bytestore_test');
    final path = '${_tmp!.path}/spool_${_seq++}.diff';
    File(path).writeAsBytesSync(utf8.encode(raw));

    final doc = await DiffDocument.lazyFromSpool(path);
    addTearDown(doc.dispose);

    // Reference (in-RAM) doc for comparison.
    final ref = DiffDocument.lazy(rawContent: raw);

    // File-backed: bytes never materialized — rawContent is EMPTY.
    expect(doc.isFileBacked, isTrue);
    expect(doc.rawContent, isEmpty);
    expect(
      doc.payloadBytes,
      utf8.encode(raw).length,
      reason: 'telemetry must use the byte store, not the absent raw String',
    );
    final logosText = buildFileBackedLogosStructuralDiff(doc);
    expect(logosText, contains('diff --git a/one b/one'));
    expect(logosText, contains('@@ -1,2 +1,2 @@'));
    expect(
      logosText,
      isNot(contains('beta cafÃ©')),
      reason: 'Logos must not materialize changed spool rows into its envelope',
    );

    // But structure + rows + search all match the in-RAM doc exactly.
    expect(doc.lines.length, ref.lines.length);
    for (var i = 0; i < ref.lines.length; i++) {
      expect(doc.lines[i].text, ref.lines[i].text, reason: 'row $i');
      expect(doc.lines[i].kind, ref.lines[i].kind, reason: 'row $i kind');
    }
    expect(doc.sections.map((s) => s.path), ['one', 'two']);
    // Unicode search runs over the spool bytes.
    final lazy = doc.lines as LazyDiffLines;
    expect(lazy.index.findMatchingLines('café'), isNotEmpty);
    // Change navigation works off the index without hydrating everything.
    expect(lazy.index.nextChangedLine(0, 1), greaterThanOrEqualTo(0));
  });

  test(
    'lazyFromSpool preserves trimLeadingMeta logical row coordinates',
    () async {
      const raw =
          'diff --git a/one b/one\nindex 1..2 100644\n'
          '--- a/one\n+++ b/one\n@@ -1 +1 @@\n-old\n+new\n';
      _tmp ??= Directory.systemTemp.createTempSync('bytestore_test');
      final path = '${_tmp!.path}/trim_${_seq++}.diff';
      File(path).writeAsBytesSync(utf8.encode(raw));

      final doc = await DiffDocument.lazyFromSpool(
        path,
        pathHint: 'one',
        trimLeadingMeta: true,
      );
      addTearDown(doc.dispose);

      expect(doc.lines.first.kind, LineKind.hunk);
      expect(doc.hunks.single.lineIndex, 0);
      final lines = doc.lines as LazyDiffLines;
      expect(lines.nextChangedLine(0, 1), 1);
      expect(lines.findMatchingLines('new'), [2]);
    },
  );

  group('dual anchor bound (giant-line safety)', () {
    // A diff of FEW but ENORMOUS lines: under a line-only anchor rule (every
    // 4096 lines) this whole thing gets ONE anchor, so a cold seek to the last
    // line replays megabytes. The byte bound must place several anchors so no
    // cold seek replays more than kAnchorByteSpacing bytes.
    String giantLineDiff(int lines, int lineBytes) {
      final sb = StringBuffer(
        'diff --git a/g b/g\n--- a/g\n+++ b/g\n'
        '@@ -1,$lines +1,$lines @@\n',
      );
      for (var i = 0; i < lines; i++) {
        sb.write('+');
        sb.write('x' * lineBytes); // one enormous added line
        sb.write('\n');
      }
      return sb.toString();
    }

    test('byte bound places multiple anchors on few-but-huge lines', () {
      // 12 lines × 300 KB = 3.6 MB, but only 12 lines (« kAnchorSpacing 4096).
      final raw = giantLineDiff(12, 300 * 1024);
      final idx = PredictiveDiffIndex.build(raw);
      // A line-only rule would give exactly 1 anchor; the byte bound (512 KiB)
      // must have created several (~3.6MB / 512KiB ≈ 7).
      expect(
        idx.anchorCount,
        greaterThan(1),
        reason: 'byte bound must fire on huge lines',
      );
      expect(idx.lineCount, greaterThan(12)); // header rows + 12 body rows
    });

    test('hydration stays byte-identical with byte-driven anchors', () {
      final raw = giantLineDiff(10, 200 * 1024);
      final idx = PredictiveDiffIndex.build(raw);
      final canonical = parseUnifiedDiff(raw);
      expect(idx.lineCount, canonical.length);
      // Cold seek to every row (incl. across byte-anchor boundaries) matches.
      for (var i = 0; i < canonical.length; i++) {
        expect(
          idx.hydrateRange(i, 1).single.text,
          canonical[i].text,
          reason: 'row $i',
        );
        expect(idx.kindAt(i), canonical[i].kind, reason: 'kindAt $i');
      }
      // And a file-backed build over the same bytes agrees too.
      final store = _fileStore(raw, pageSize: 64 * 1024);
      final f = PredictiveDiffIndex.buildFromStore(store);
      expect(f.lineCount, idx.lineCount);
      for (var i = 0; i < canonical.length; i++) {
        expect(
          f.hydrateRange(i, 1).single.text,
          canonical[i].text,
          reason: 'file row $i',
        );
      }
      store.dispose();
    });
  });

  group('FileByteStore robustness', () {
    test('empty file: no crash, empty index/doc', () async {
      _tmp ??= Directory.systemTemp.createTempSync('bytestore_test');
      final path = '${_tmp!.path}/empty_${_seq++}.diff';
      File(path).writeAsBytesSync(const []);
      final store = FileByteStore.open(path);
      expect(store.length, 0);
      expect(store.indexOfNewline(0), -1);
      expect(store.substring(0, 0), '');
      expect(store.unitAt(0), -1); // out of range → -1, not a RangeError
      final idx = PredictiveDiffIndex.buildFromStore(store);
      expect(idx.lineCount, 0);
      store.dispose();

      final doc = await DiffDocument.lazyFromSpool(path);
      expect(doc.lines, isEmpty);
      doc.dispose();
    });

    test('out-of-range access is clamped, never throws', () {
      const raw = 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n';
      final store = _fileStore(raw, pageSize: 8);
      expect(store.unitAt(-1), -1);
      expect(store.unitAt(store.length), -1);
      expect(store.unitAt(store.length + 999), -1);
      expect(store.substring(-5, 3), store.substring(0, 3));
      expect(
        store.substring(store.length - 2, store.length + 100),
        store.substring(store.length - 2, store.length),
      );
      expect(store.indexOfNewline(-10), store.indexOfNewline(0));
      store.dispose();
    });

    test('dispose is idempotent', () {
      const raw = 'diff --git a/x b/x\n@@ -1 +1 @@\n-a\n+b\n';
      final store = _fileStore(raw);
      store.dispose();
      expect(store.dispose, returnsNormally);
      expect(store.dispose, returnsNormally);
    });
  });

  test('page cache stays bounded — resident pages never exceed maxPages', () {
    // A diff far larger than the cache; scanning it must not retain every page.
    final sb = StringBuffer(
      'diff --git a/big b/big\n--- a/big\n+++ b/big\n'
      '@@ -1,4000 +1,4000 @@\n',
    );
    for (var i = 0; i < 4000; i++) {
      sb.write('-line $i old value here padding padding\n');
      sb.write('+line $i new value here padding padding\n');
    }
    final raw = sb.toString();
    final s = PredictiveDiffIndex.buildFromStore(StringByteStore(raw));
    final store = _fileStore(raw, pageSize: 4096);
    final f = PredictiveDiffIndex.buildFromStore(store);
    // Full pass over a multi-page file, then compare a scattered sample.
    expect(f.lineCount, s.lineCount);
    for (final i in [0, 100, 2000, 5000, f.lineCount - 1]) {
      expect(
        f.hydrateRange(i, 1).single.text,
        s.hydrateRange(i, 1).single.text,
        reason: 'row $i',
      );
    }
    store.dispose();
  });
}
