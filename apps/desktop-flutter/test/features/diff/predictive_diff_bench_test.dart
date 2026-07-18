import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/predictive_diff_index.dart';

import '../../support/gen.dart';
import '../../support/gen_diff.dart';
import '../../support/prop.dart';

// Correctness + benchmark for the predictive diff index (the "powerpuff" diff).
//
// CORRECTNESS: every hydrated row must be byte-identical to what the canonical
// parseUnifiedDiff produces — kind, text, line numbers, hunk index, filePath,
// and the \-no-newline flag. Pinned as a property over generated + hostile
// diffs so the replay state machine can never silently drift from the parser.
//
// BENCHMARK (skipped by default): opens the real 326MB road-graph diff and
// reports first-viewport / random-seek / index-build times vs the full parse.

void _expectRowEqual(ParsedLine a, ParsedLine b, String ctx) {
  expect(a.kind, b.kind, reason: 'kind @ $ctx');
  expect(a.text, b.text, reason: 'text @ $ctx');
  expect(a.lineNumOld, b.lineNumOld, reason: 'oldNum @ $ctx');
  expect(a.lineNumNew, b.lineNumNew, reason: 'newNum @ $ctx');
  expect(a.hunkIndex, b.hunkIndex, reason: 'hunk @ $ctx');
  expect(a.filePath, b.filePath, reason: 'filePath @ $ctx');
  expect(a.noNewlineAtEof, b.noNewlineAtEof, reason: 'noNewline @ $ctx');
}

/// Render a scenario to a real unified diff shape (multi-hunk, varied EOL,
/// adversarial line prefixes) for the correctness sweep.
String _diffFromScenario(DiffScenario sc) {
  // Emit a synthetic-but-valid multi-hunk diff over the scenario's lines: a few
  // hunks, each with context + adds + dels, plus the file headers.
  final b = StringBuffer()
    ..writeln('diff --git a/f.txt b/f.txt')
    ..writeln('index 1111111..2222222 100644')
    ..writeln('--- a/f.txt')
    ..writeln('+++ b/f.txt');
  final old = sc.oldLines, neu = sc.newLines;
  final n = old.length > neu.length ? old.length : neu.length;
  var i = 0, oldNo = 1, newNo = 1;
  while (i < n) {
    final take = (n - i) < 4 ? (n - i) : 4;
    final ctx = <String>[], del = <String>[], add = <String>[];
    for (var k = 0; k < take; k++) {
      final oi = i + k;
      if (oi < old.length && oi < neu.length && old[oi] == neu[oi]) {
        ctx.add(old[oi]);
      } else {
        if (oi < old.length) del.add(old[oi]);
        if (oi < neu.length) add.add(neu[oi]);
      }
    }
    final oldCount = ctx.length + del.length;
    final newCount = ctx.length + add.length;
    if (oldCount > 0 || newCount > 0) {
      b.writeln('@@ -$oldNo,$oldCount +$newNo,$newCount @@');
      for (final c in ctx) {
        b.writeln(' $c');
      }
      for (final d in del) {
        b.writeln('-$d');
      }
      for (final a in add) {
        b.writeln('+$a');
      }
    }
    oldNo += oldCount;
    newNo += newCount;
    i += take;
  }
  return b.toString();
}

void main() {
  group('predictive index == parseUnifiedDiff (correctness)', () {
    test('hydrated rows are byte-identical to the canonical parser', () {
      forAll<String>(
        (rng) => _diffFromScenario(genDiffScenario(maxLines: 40)(rng)),
        count: 300,
        seed: 0x50FA,
        describe: 'predictive index equivalence',
        check: (raw) {
          final canonical = parseUnifiedDiff(raw);
          final idx = PredictiveDiffIndex.build(raw);
          expect(
            idx.lineCount,
            canonical.length,
            reason: 'line count mismatch',
          );

          // Hydrate several windows (including anchor boundaries) and compare.
          for (final start in [
            0,
            canonical.length ~/ 2,
            (canonical.length - 5).clamp(0, canonical.length),
          ]) {
            final win = idx.hydrateRange(start, 5);
            for (var k = 0; k < win.length; k++) {
              _expectRowEqual(win[k], canonical[start + k], 'row ${start + k}');
            }
          }
          // And a full hydrate for total agreement.
          final all = idx.hydrateRange(0, canonical.length);
          expect(all.length, canonical.length);
          for (var k = 0; k < all.length; k++) {
            _expectRowEqual(all[k], canonical[k], 'full row $k');
          }
        },
      );
    });

    test('index scanners (kindAt / findMatchingLines / nextChangedLine) '
        'match the parser', () {
      forAll<String>(
        (rng) => _diffFromScenario(genDiffScenario(maxLines: 40)(rng)),
        count: 200,
        seed: 0x5CA2,
        describe: 'index scanners',
        check: (raw) {
          final canonical = parseUnifiedDiff(raw);
          final idx = PredictiveDiffIndex.build(raw);
          bool changed(ParsedLine l) =>
              l.kind == LineKind.added || l.kind == LineKind.deleted;

          for (var i = 0; i < canonical.length; i++) {
            expect(idx.kindAt(i), canonical[i].kind, reason: 'kindAt $i');
          }

          int bruteNext(int from, int dir) {
            if (dir >= 0) {
              for (var i = from; i < canonical.length; i++) {
                if (changed(canonical[i])) return i;
              }
            } else {
              for (var i = from; i >= 0; i--) {
                if (i < canonical.length && changed(canonical[i])) return i;
              }
            }
            return -1;
          }

          if (canonical.isNotEmpty) {
            for (final from in [
              0,
              canonical.length ~/ 2,
              canonical.length - 1,
            ]) {
              expect(
                idx.nextChangedLine(from, 1),
                bruteNext(from, 1),
                reason: 'nextChangedLine fwd $from',
              );
              expect(
                idx.nextChangedLine(from, -1),
                bruteNext(from, -1),
                reason: 'nextChangedLine back $from',
              );
            }
          }

          // Search folds with toLowerCase() — IDENTICAL to the eager path's
          // ParsedLine.lowerText, so results don't change with diff size.
          for (final term in ['line', 'a', '+', 'ctx', 'row', 'zzznope']) {
            final lower = term.toLowerCase();
            final expected = <int>[
              for (var i = 0; i < canonical.length; i++)
                if (canonical[i].text.toLowerCase().contains(lower)) i,
            ];
            expect(
              idx.findMatchingLines(lower),
              expected,
              reason: 'findMatchingLines "$term"',
            );
          }
        },
      );
    });

    test('search is Unicode case-insensitive, matching the eager path', () {
      // A lowercase query must match UPPERCASE non-ASCII source (accented
      // Latin, Greek, Cyrillic) exactly as ParsedLine.lowerText.contains would.
      const raw =
          'diff --git a/f b/f\n'
          '--- a/f\n'
          '+++ b/f\n'
          '@@ -1,3 +1,3 @@\n'
          '+CAFÉ ΩMEGA ПРИВЕТ\n'
          '+plain ascii row\n'
          '-lower café omega привет\n';
      final canonical = parseUnifiedDiff(raw);
      final idx = PredictiveDiffIndex.build(raw);
      for (final term in ['café', 'ωmega', 'привет', 'CAFÉ', 'ΩM']) {
        final lower = term.toLowerCase();
        final expected = <int>[
          for (var i = 0; i < canonical.length; i++)
            if (canonical[i].text.toLowerCase().contains(lower)) i,
        ];
        expect(
          idx.findMatchingLines(lower),
          expected,
          reason: 'unicode search "$term"',
        );
        // And it actually finds the uppercase row from a lowercase query.
        expect(expected, isNotEmpty, reason: 'expected a match for "$term"');
      }
    });

    test('EOF no-newline marker survives at hydration boundaries', () {
      // The reviewer's Finding 2: a `\ No newline` marker follows the row you
      // stop hydrating at, so the loop never reaches it. Build exactly that and
      // require the flag to match the eager parser at every boundary.
      const raw =
          'diff --git a/f b/f\n'
          '--- a/f\n'
          '+++ b/f\n'
          '@@ -1,2 +1,2 @@\n'
          ' ctx1\n'
          '-old last\n'
          '+new last\n'
          '\\ No newline at end of file\n';
      final canonical = parseUnifiedDiff(raw);
      final idx = PredictiveDiffIndex.build(raw);
      final addIdx = canonical.indexWhere((l) => l.kind == LineKind.added);
      // Sanity: the eager parser DOES set the flag on that row.
      expect(canonical[addIdx].noNewlineAtEof, isTrue);
      // hydrateRange ending EXACTLY at that row (the boundary) must agree.
      expect(
        idx.hydrateRange(addIdx, 1).single.noNewlineAtEof,
        isTrue,
        reason: 'lost the marker for a single-row hydrate at the boundary',
      );
      expect(
        idx.hydrateRange(addIdx - 1, 2).last.noNewlineAtEof,
        isTrue,
        reason: 'lost the marker when the window ends at the marked row',
      );
      // Via the lazy list (512-row windows) too.
      final lazy = LazyDiffLines(idx, windowSize: addIdx + 1);
      expect(
        lazy[addIdx].noNewlineAtEof,
        isTrue,
        reason: 'lost the marker at a LazyDiffLines window boundary',
      );
    });

    test('spans anchor boundaries correctly (small spacing stress)', () {
      // A long single-hunk diff that crosses many anchor boundaries.
      const changed = kAnchorSpacing * 3 + 137;
      final b = StringBuffer()
        ..writeln('diff --git a/d b/d')
        ..writeln('--- a/d')
        ..writeln('+++ b/d')
        ..writeln('@@ -1,$changed +1,$changed @@');
      for (var i = 0; i < changed; i++) {
        b.writeln('-old row $i value ${i * 7 % 97}');
      }
      for (var i = 0; i < changed; i++) {
        b.writeln('+new row $i value ${i * 7 % 97}');
      }
      final raw = b.toString();
      final canonical = parseUnifiedDiff(raw);
      final idx = PredictiveDiffIndex.build(raw);
      expect(idx.lineCount, canonical.length);
      // Random-ish windows across boundaries.
      final rng = Rng(7);
      for (var t = 0; t < 40; t++) {
        final start = rng.intBetween(0, canonical.length - 1);
        final win = idx.hydrateRange(start, 60);
        for (var k = 0; k < win.length; k++) {
          _expectRowEqual(win[k], canonical[start + k], 'row ${start + k}');
        }
      }
    });
  });

  group('DiffDocument lazy path (integration)', () {
    test('fromRawContent goes lazy past the threshold; rows/stats correct', () {
      const n = 250000; // ~10MB diff → over kLazyDiffLengthThreshold
      final b = StringBuffer()
        ..writeln('diff --git a/data.txt b/data.txt')
        ..writeln('index 1111111..2222222 100644')
        ..writeln('--- a/data.txt')
        ..writeln('+++ b/data.txt')
        ..writeln('@@ -1,$n +1,$n @@');
      for (var i = 0; i < n; i++) {
        b.writeln('-old line number $i here padding padding');
      }
      for (var i = 0; i < n; i++) {
        b.writeln('+new line number $i here padding padding');
      }
      final raw = b.toString();
      expect(raw.length, greaterThan(kLazyDiffLengthThreshold));

      final sw = Stopwatch()..start();
      final doc = DiffDocument.fromRawContent(
        rawContent: raw,
        pathHint: 'data.txt',
        trimLeadingMeta: true,
      );
      sw.stop();

      // It took the lazy path (no per-line objects, no unit index).
      expect(doc.lines, isA<LazyDiffLines>());
      expect(doc.unitByFastKey, isEmpty);
      expect(doc.stats.adds, n);
      expect(doc.stats.dels, n);
      expect(doc.hunks.length, 1);
      expect(doc.rawContent, raw);

      // Rows hydrate byte-identically to the canonical parser.
      final canonical = trimLeadingMetaLines(parseUnifiedDiff(raw));
      expect(doc.lines.length, canonical.length);
      for (final i in [
        0,
        1,
        2,
        3,
        4,
        n,
        n + 50000,
        doc.lines.length - 1,
        123457,
      ]) {
        expect(doc.lines[i].text, canonical[i].text, reason: 'text @ $i');
        expect(doc.lines[i].kind, canonical[i].kind, reason: 'kind @ $i');
        expect(
          doc.lines[i].lineNumNew,
          canonical[i].lineNumNew,
          reason: 'newNum @ $i',
        );
        expect(
          doc.lines[i].lineNumOld,
          canonical[i].lineNumOld,
          reason: 'oldNum @ $i',
        );
      }
    });
  });

  group('async chunked build', () {
    test('buildAsync yields the same index as build', () async {
      const changed = 300000; // crosses several yield chunks
      final b = StringBuffer()
        ..writeln('diff --git a/d b/d')
        ..writeln('--- a/d')
        ..writeln('+++ b/d')
        ..writeln('@@ -1,$changed +1,$changed @@');
      for (var i = 0; i < changed; i++) {
        b.writeln('-old $i');
      }
      for (var i = 0; i < changed; i++) {
        b.writeln('+new $i');
      }
      final raw = b.toString();
      final sync = PredictiveDiffIndex.build(raw);
      final async = await PredictiveDiffIndex.buildAsync(raw);
      expect(async.lineCount, sync.lineCount);
      expect(async.adds, sync.adds);
      expect(async.dels, sync.dels);
      expect(async.hunks.length, sync.hunks.length);
      // Spot-check rows across chunk boundaries.
      for (final i in [
        0,
        1,
        119999,
        120000,
        120001,
        changed,
        async.lineCount - 1,
      ]) {
        expect(
          async.hydrateRange(i, 1).single.text,
          sync.hydrateRange(i, 1).single.text,
          reason: 'row $i',
        );
      }
    });
  });

  group('lazy hunk metadata (review fixes)', () {
    test('hunk churn counts real +/- rows, NOT the @@ header counts', () {
      // Header counts (oldCount/newCount) include context; churn must not.
      const raw =
          'diff --git a/f b/f\n'
          '--- a/f\n'
          '+++ b/f\n'
          '@@ -1,4 +1,4 @@\n'
          ' ctx1\n'
          '-del1\n'
          '-del2\n'
          '+add1\n'
          '+add2\n'
          ' ctx2\n';
      final idx = PredictiveDiffIndex.build(raw);
      final h = idx.hunks.single;
      expect(h.adds, 2, reason: 'actual + rows');
      expect(h.dels, 2, reason: 'actual - rows');
      expect(h.oldCount, 4, reason: 'header count includes context');
      expect(h.newCount, 4);
      // Through the document: additions/deletions must be the real churn.
      final doc = DiffDocument.lazy(rawContent: raw, pathHint: 'f');
      final dh = doc.hunks.single;
      expect(dh.additions, 2);
      expect(dh.deletions, 2);
      expect(dh.churn, 4);
    });

    test(
      'a multi-file diff keeps per-file sections + stats (not flattened)',
      () {
        const raw =
            'diff --git a/one.txt b/one.txt\n'
            '--- a/one.txt\n'
            '+++ b/one.txt\n'
            '@@ -1,1 +1,1 @@\n'
            '-old1\n'
            '+new1\n'
            'diff --git a/two.txt b/two.txt\n'
            '--- a/two.txt\n'
            '+++ b/two.txt\n'
            '@@ -1,3 +1,3 @@\n'
            ' ctx\n'
            '-old2\n'
            '+new2a\n'
            '+new2b\n';
        final doc = DiffDocument.lazy(rawContent: raw, pathHint: 'one.txt');
        expect(doc.sections.map((s) => s.path), ['one.txt', 'two.txt']);
        expect(doc.filesByPath.keys.toSet(), {'one.txt', 'two.txt'});
        // Per-file stats are per file, not global.
        expect(doc.filesByPath['one.txt']!.stats.adds, 1);
        expect(doc.filesByPath['one.txt']!.stats.dels, 1);
        expect(doc.filesByPath['two.txt']!.stats.adds, 2);
        expect(doc.filesByPath['two.txt']!.stats.dels, 1);
        // Content is intact (single combined doc backs rawContent).
        expect(doc.rawContent, raw);
        // Each row still knows its own file.
        final rows = doc.lines;
        expect(rows[rows.length - 1].filePath, 'two.txt');
      },
    );

    test('lazy per-file entries are metadata-only — reopening never '
        'materializes the combined diff', () {
      const raw =
          'diff --git a/one.txt b/one.txt\n'
          '--- a/one.txt\n'
          '+++ b/one.txt\n'
          '@@ -1 +1 @@\n'
          '-a\n'
          '+b\n'
          'diff --git a/two.txt b/two.txt\n'
          '--- a/two.txt\n'
          '+++ b/two.txt\n'
          '@@ -1 +1,2 @@\n'
          '-c\n'
          '+d\n'
          '+e\n';
      final doc = DiffDocument.lazy(rawContent: raw, pathHint: 'one.txt');
      for (final entry in doc.filesByPath.values) {
        // The freeze this whole path avoids came from these entries sharing the
        // combined lazy row list; walking one would replay every file's rows.
        expect(
          entry.isLazyMeta,
          isTrue,
          reason: 'per-file entries must be flagged metadata-only',
        );
        expect(
          entry.lines,
          isEmpty,
          reason: 'per-file entries must carry no rows to materialize',
        );
      }
    });
  });

  group('predictive index — hostile totality', () {
    test('never throws on arbitrary bytes; count matches parser', () {
      forAll<String>(
        genUnicodeHostile(maxLen: 80),
        count: 300,
        seed: 0xB00,
        describe: 'predictive hostile',
        check: (raw) {
          final idx = PredictiveDiffIndex.build(raw);
          expect(idx.lineCount, parseUnifiedDiff(raw).length);
        },
      );
    });
  });

  // ── benchmark on the real 326MB road-graph diff ──────────────────────────
  group('powerpuff benchmark (real marble data)', () {
    const candidates = [
      r'C:\Users\mini server\Documents\Projects\marble\data\USA-road-d.W.gr',
      r'C:\Users\mini server\Documents\Projects\marble\data\USA-road-d.FLA.gr',
      r'C:\Users\mini server\Documents\Projects\marble\data\USA-road-d.BAY.gr',
    ];

    test(
      'END-TO-END open time via DiffDocument.fromRawContent',
      tags: 'manual',
      () {
        final path = candidates.firstWhere(
          (p) => File(p).existsSync(),
          orElse: () => '',
        );
        if (path.isEmpty) return;
        final content = File(path).readAsStringSync();
        final raw =
            'diff --git a/road.gr b/road.gr\n--- /dev/null\n+++ b/road.gr\n'
            '@@ -0,0 +1,N @@\n'
            '${content.split('\n').where((l) => l.isNotEmpty).map((l) => '+$l').join('\n')}\n';
        final mb = (raw.length / (1024 * 1024)).round();

        final sw = Stopwatch()..start();
        final doc = DiffDocument.fromRawContent(
          rawContent: raw,
          pathHint: 'road.gr',
          trimLeadingMeta: true,
        );
        final tOpen = sw.elapsedMilliseconds;

        // First screen the shell would render (viewport hydrate).
        sw.reset();
        sw.start();
        final firstScreen = [for (var i = 0; i < 60; i++) doc.lines[i]];
        final tFirstScreen = sw.elapsedMicroseconds;

        // ignore: avoid_print
        print(
          '\n══ END-TO-END OPEN — $mb MB, ${doc.lines.length} lines ══\n'
          '  DiffDocument.fromRawContent : $tOpen ms   (was ~18000ms eager)\n'
          '  first 60-row screen render  : $tFirstScreen µs\n'
          '  lazy=${doc.lines is LazyDiffLines}  '
          'stats=+${doc.stats.adds}/-${doc.stats.dels}\n',
        );
        expect(firstScreen.length, 60);
      },
    );

    test('first-paint / seek / build vs full parse', tags: 'manual', () {
      final path = candidates.firstWhere(
        (p) => File(p).existsSync(),
        orElse: () => '',
      );
      if (path.isEmpty) {
        // ignore: avoid_print
        print('[powerpuff] no marble file — skipping benchmark');
        return;
      }
      // Build a full-rewrite-style diff body from the file (each line added).
      final content = File(path).readAsStringSync();
      final raw =
          'diff --git a/road.gr b/road.gr\n'
          '--- /dev/null\n'
          '+++ b/road.gr\n'
          '@@ -0,0 +1,N @@\n'
          '${content.split('\n').where((l) => l.isNotEmpty).map((l) => '+$l').join('\n')}\n';
      final mb = (raw.length / (1024 * 1024)).round();

      // A) COLD OPEN — first 60 rows with NO index at all. This is what the
      //    user sees on the very first frame after clicking the file.
      var sw = Stopwatch()..start();
      final firstView = PredictiveDiffIndex.firstRows(raw, 60);
      final tFirst = sw.elapsedMicroseconds;

      // B) Build the sparse index (would run in a background isolate).
      sw = Stopwatch()..start();
      final idx = PredictiveDiffIndex.build(raw);
      final tBuild = sw.elapsedMilliseconds;

      // C) Random seek deep into the file → hydrate a viewport.
      final mid = idx.lineCount ~/ 2 + 12345;
      sw = Stopwatch()..start();
      final midView = idx.hydrateRange(mid, 60);
      final tSeek = sw.elapsedMicroseconds;

      // D) The baseline: full parse into objects.
      sw = Stopwatch()..start();
      final full = parseUnifiedDiff(raw);
      final tParse = sw.elapsedMilliseconds;

      final anchors = (idx.lineCount / kAnchorSpacing).round();
      final stateKb = (anchors * 64 / 1024).round();
      // ignore: avoid_print
      print(
        '\n══ POWERPUFF vs full parse — ${path.split(r'\').last} '
        '($mb MB, ${idx.lineCount} lines) ══\n'
        '  [baseline] full parseUnifiedDiff : $tParse ms  '
        '(${full.length} objects, ~1.6GB)\n'
        '  [predict]  COLD first 60 rows    : $tFirst µs   (no index)\n'
        '  [predict]  build sparse index    : $tBuild ms   (background)\n'
        '  [predict]  random deep seek+60   : $tSeek µs   (@ line $mid)\n'
        '  anchors=$anchors  (~$stateKb KB state)\n',
      );

      // Correctness spot-check at the deep seek.
      for (var k = 0; k < midView.length; k++) {
        expect(midView[k].text, full[mid + k].text);
      }
      expect(firstView.isNotEmpty, isTrue);
    });
  });
}
