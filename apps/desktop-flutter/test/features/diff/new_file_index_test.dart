// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// NewFileIndex renders an untracked file as an all-added new-file diff by
// reading the working file directly (zero copy). These tests pin its structure
// and prove it agrees, row-for-row, with what git --no-index emits — the ground
// truth the old whole-file synthesizer matched.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/new_file_index.dart';

Directory? _tmp;
int _seq = 0;

String _write(String content) {
  _tmp ??= Directory.systemTemp.createTempSync('newfile_test');
  final path = '${_tmp!.path}/f_${_seq++}.txt';
  File(path).writeAsBytesSync(utf8.encode(content));
  return path;
}

String _writeBytes(List<int> bytes) {
  _tmp ??= Directory.systemTemp.createTempSync('newfile_test');
  final path = '${_tmp!.path}/f_${_seq++}.bin';
  File(path).writeAsBytesSync(bytes);
  return path;
}

void main() {
  tearDownAll(() {
    try {
      _tmp?.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('basic new file: header + every line added', () async {
    final path = _write('alpha\nbeta\ngamma\n');
    final idx = await NewFileIndex.build(path, 'src/x.txt');
    expect(idx.lineCount, 5 + 3);
    expect(idx.adds, 3);
    expect(idx.dels, 0);

    final rows = idx.hydrateRange(0, idx.lineCount);
    expect(rows[0].text, 'diff --git a/src/x.txt b/src/x.txt');
    expect(rows[1].text, 'new file mode 100644');
    expect(rows[2].text, '--- /dev/null');
    expect(rows[3].text, '+++ b/src/x.txt');
    expect(rows[4].text, '@@ -0,0 +1,3 @@');
    expect(rows[4].kind, LineKind.hunk);
    expect(rows[5].text, '+alpha');
    expect(rows[5].kind, LineKind.added);
    expect(rows[5].lineNumNew, 1);
    expect(rows[6].text, '+beta');
    expect(rows[7].text, '+gamma');
    expect(rows[7].lineNumNew, 3);
    expect(rows.last.noNewlineAtEof, isFalse);
    idx.store.dispose();
  });

  test('no trailing newline → last row flagged', () async {
    final path = _write('one\ntwo'); // no final \n
    final idx = await NewFileIndex.build(path, 'n.txt');
    final rows = idx.hydrateRange(0, idx.lineCount);
    expect(rows.last.text, '+two');
    expect(rows.last.noNewlineAtEof, isTrue);
    idx.store.dispose();
  });

  test('binary file → marker only, no body scan', () async {
    final path = _writeBytes([1, 2, 0, 3, 4, 0, 5]); // NUL → binary
    final idx = await NewFileIndex.build(path, 'blob.bin');
    expect(idx.isBinary, isTrue);
    expect(idx.adds, 0);
    final rows = idx.hydrateRange(0, idx.lineCount);
    expect(rows.any((r) => r.text.contains('Binary files')), isTrue);
    idx.store.dispose();
  });

  test('empty file → header only', () async {
    final path = _write('');
    final idx = await NewFileIndex.build(path, 'empty.txt');
    expect(idx.adds, 0);
    expect(idx.lineCount, 2); // diff --git + new file mode
    idx.store.dispose();
  });

  test('utf8 + cjk content round-trips exactly', () async {
    final path = _write('café ΩMEGA\n日本語 中文\nünïcödé\n');
    final idx = await NewFileIndex.build(path, 'i18n.txt');
    final rows = idx.hydrateRange(0, idx.lineCount);
    expect(rows[5].text, '+café ΩMEGA');
    expect(rows[6].text, '+日本語 中文');
    expect(rows[7].text, '+ünïcödé');
    idx.store.dispose();
  });

  test('dual anchor + windowed hydration across byte boundaries', () async {
    // Many lines so byte-anchor + line-anchor both fire; hydrate scattered
    // windows and confirm each row's content + number are exact.
    final sb = StringBuffer();
    const n = 20000;
    for (var i = 0; i < n; i++) {
      sb.write('line number $i has some padding content here\n');
    }
    final path = _write(sb.toString());
    final idx = await NewFileIndex.build(path, 'big.txt');
    expect(idx.adds, n);
    expect(idx.anchorCount, greaterThan(1));
    for (final fileLine in [0, 1, 4095, 4096, 9999, n - 1]) {
      final row = idx.hydrateRange(5 + fileLine, 1).single;
      expect(row.text, '+line number $fileLine has some padding content here',
          reason: 'file line $fileLine');
      expect(row.kind, LineKind.added);
      expect(row.lineNumNew, fileLine + 1);
    }
    idx.store.dispose();
  });

  test('search + nav', () async {
    final path = _write('apple\nbanana\ncherry\nAPPLE pie\n');
    final idx = await NewFileIndex.build(path, 's.txt');
    expect(idx.findMatchingLines('apple'), [5, 8]); // case-insensitive
    // Every body row is a change; next-change from the header lands on row 5.
    expect(idx.nextChangedLine(0, 1), 5);
    expect(idx.nextChangedLine(idx.lineCount - 1, -1), idx.lineCount - 1);
    expect(idx.kindAt(4), LineKind.hunk);
    expect(idx.kindAt(6), LineKind.added);
    idx.store.dispose();
  });

  test('lazyFromWorkingFile: file-backed doc, empty rawContent', () async {
    final path = _write('a\nb\nc\n');
    final doc = await DiffDocument.lazyFromWorkingFile(path, 'z.txt');
    addTearDown(doc.dispose);
    expect(doc.isFileBacked, isTrue);
    expect(doc.rawContent, isEmpty);
    expect(doc.lines.length, 5 + 3);
    expect(doc.sections.map((s) => s.path), ['z.txt']);
    expect(doc.stats.adds, 3);
  });

  test('agrees with git --no-index (oracle, modulo index line)', () async {
    // Ground truth: what git itself emits for this file as a new file.
    const content = 'first\nsecond\nthird\nfourth line longer\n';
    final path = _write(content);
    final gitResult = await Process.run(
      'git',
      ['diff', '--no-index', '--no-color', '--', '/dev/null', path],
    );
    // --no-index exits 1 when differing (always, for a new file).
    expect(gitResult.exitCode == 0 || gitResult.exitCode == 1, isTrue);
    final gitDiff = (gitResult.stdout as String);
    // The ADDED rows must match git's raw `+`-prefixed lines EXACTLY —
    // ParsedLine.text carries the sigil on every backing (the universal
    // invariant stripDiffLineSign and the patch engine rely on).
    final gitAddedLines = const LineSplitter()
        .convert(gitDiff)
        .where((l) => l.startsWith('+') && !l.startsWith('+++'))
        .toList();

    final idx = await NewFileIndex.build(path, path);
    final ourAdded = idx
        .hydrateRange(0, idx.lineCount)
        .where((r) => r.kind == LineKind.added)
        .map((r) => r.text)
        .toList();
    expect(ourAdded, gitAddedLines, reason: 'added-line bodies match git');
    expect(idx.adds, gitAddedLines.length);
    idx.store.dispose();
  });
}
