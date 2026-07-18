import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/patch_engine.dart';

/// End-to-end round-trip witness for line staging: real repo → real
/// `git diff -U3` (the exact bytes getFileDiff produces) → parseUnifiedDiff
/// → sigil-click semantics (_setLineStaged + findReplacementPair pairing)
/// → PatchEngine.buildStagedPatch → applyFileStaging → assert the INDEX
/// via plumbing. Reproduces the field failure: staging one edited line in
/// a large file ("Partial stage failed: patch does not apply").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String repo;

  Future<ProcessResult> git(List<String> args) => Process.run(
        'git',
        args,
        workingDirectory: repo,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  File wf(String path) => File('$repo${Platform.pathSeparator}$path');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gdpu_patch_');
    repo = root.path;
    await git(['init', '-q', '-b', 'main']);
    await git(['config', 'user.email', 'a@b.c']);
    await git(['config', 'user.name', 'test']);
    await git(['config', 'core.autocrlf', 'false']);
    await git(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  /// Simulate the diff view's sigil click on [index]: stage the line and
  /// its replacement pair (diff_shell._setLineStaged with autoPair).
  void sigil(List<ParsedLine> lines, int index) {
    lines[index] = lines[index].copyWith(isStaged: true);
    final pair = findReplacementPair(lines, index);
    if (pair != null) {
      lines[pair] = lines[pair].copyWith(isStaged: true);
    }
  }

  /// Full pipeline for one staged line; returns the staged blob content
  /// of [path] read from the index (`git show :path`).
  Future<String> stageLineContaining(
      String path, String needle) async {
    final diff = await getFileDiff(repo, path);
    expect(diff.ok, isTrue, reason: diff.error ?? '');
    final lines = parseUnifiedDiff(diff.data!);
    final idx = lines.indexWhere(
        (l) => l.kind == LineKind.added && l.text.contains(needle));
    expect(idx, greaterThanOrEqualTo(0),
        reason: 'added line containing "$needle" must parse');
    sigil(lines, idx);
    final patch = PatchEngine.buildStagedPatch(path, lines);
    final r = await applyFileStaging(repo, path, patch);
    expect(r.ok, isTrue,
        reason: 'applyFileStaging failed: ${r.error}\n--- patch ---\n$patch');
    return (await git(['show', ':$path'])).stdout as String;
  }

  test(
      'field repro: single edited line deep in a large file stages cleanly',
      () async {
    // Recreate the shape of the incident: a ~1400-line file, one line
    // replaced at ~1380, nothing else changed.
    final base = StringBuffer();
    for (var i = 1; i <= 1400; i++) {
      base.writeln(i == 1380
          ? '                    "because it\'s spectral math, not a model.",'
          : '        line $i content;');
    }
    await wf('big.dart').writeAsString(base.toString());
    await git(['add', '-A']);
    await git(['commit', '-qm', 'base']);

    final edited = base
        .toString()
        .replaceFirst('"because it\'s spectral math, not a model.",',
            '"because it\'s just spectral math.",');
    await wf('big.dart').writeAsString(edited);

    final staged = await stageLineContaining('big.dart', 'just spectral');
    expect(staged, contains('just spectral math'));
    expect(staged, isNot(contains('not a model')));
    // Exactly one staged hunk, nothing else swept in.
    final cached =
        (await git(['diff', '--cached', '--name-only'])).stdout as String;
    expect(cached.trim(), 'big.dart');
  });

  test('staging only the SECOND hunk exercises cumulativeDelta math',
      () async {
    final base = StringBuffer();
    for (var i = 1; i <= 200; i++) {
      base.writeln('line $i;');
    }
    await wf('two.dart').writeAsString(base.toString());
    await git(['add', '-A']);
    await git(['commit', '-qm', 'base']);

    // Two edits far apart → two hunks. Add an extra INSERTED line in hunk
    // one so old/new numbering diverges below it — the case the second
    // hunk's recomputed header must survive.
    var edited = base.toString().replaceFirst('line 20;', 'line 20 EDITED;\nline 20b INSERTED;');
    edited = edited.replaceFirst('line 150;', 'line 150 EDITED;');
    await wf('two.dart').writeAsString(edited);

    final staged = await stageLineContaining('two.dart', 'line 150 EDITED');
    expect(staged, contains('line 150 EDITED'));
    // Hunk one was NOT staged: its lines stay worktree-only.
    expect(staged, isNot(contains('20b INSERTED')));
    expect(staged, contains('line 20;'));
  });

  test('staging only the FIRST hunk leaves later hunks unstaged', () async {
    final base = StringBuffer();
    for (var i = 1; i <= 200; i++) {
      base.writeln('line $i;');
    }
    await wf('two.dart').writeAsString(base.toString());
    await git(['add', '-A']);
    await git(['commit', '-qm', 'base']);
    var edited = base.toString().replaceFirst('line 20;', 'line 20 EDITED;');
    edited = edited.replaceFirst('line 150;', 'line 150 EDITED;');
    await wf('two.dart').writeAsString(edited);

    final staged = await stageLineContaining('two.dart', 'line 20 EDITED');
    expect(staged, contains('line 20 EDITED'));
    expect(staged, contains('line 150;'));
    expect(staged, isNot(contains('line 150 EDITED')));
  });

  test('edit on the FIRST line of the file (no leading context)', () async {
    await wf('top.dart').writeAsString('first\nsecond\nthird\nfourth\n');
    await git(['add', '-A']);
    await git(['commit', '-qm', 'base']);
    await wf('top.dart')
        .writeAsString('first EDITED\nsecond\nthird\nfourth\n');

    final staged = await stageLineContaining('top.dart', 'first EDITED');
    expect(staged, startsWith('first EDITED'));
  });

  test('edit on the LAST line with no trailing newline round-trips the '
      'no-newline marker', () async {
    await wf('eof.dart').writeAsString('one\ntwo\nlast');
    await git(['add', '-A']);
    await git(['commit', '-qm', 'base']);
    await wf('eof.dart').writeAsString('one\ntwo\nlast EDITED');

    final staged = await stageLineContaining('eof.dart', 'last EDITED');
    expect(staged, 'one\ntwo\nlast EDITED');
  });

  group('parser hunk-membership invariants (pure)', () {
    test('the trailing split artifact is never parsed at all', () {
      final lines = parseUnifiedDiff(
          'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,1 +1,1 @@\n-a\n+b\n');
      expect(lines.last.text, '+b');
      expect(lines.any((l) => l.text.isEmpty), isFalse);
    });

    test('a blank separator after a hunk claims NO hunk membership', () {
      // Shape of `git log -p` payloads: hunk body, blank line, next
      // commit's header. The blank must not join the preceding hunk —
      // that phantom is exactly what desynced the @@ header in the
      // field failure.
      final lines = parseUnifiedDiff(
          'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,1 +1,1 @@\n-a\n+b\n'
          '\ncommit 123\n');
      final blank = lines.firstWhere((l) => l.text.isEmpty);
      expect(blank.hunkIndex, -1);
      expect(blank.lineNumOld, isNull);
      expect(blank.lineNumNew, isNull);
    });

    test('blank CONTEXT (marker space) stays numbered hunk body', () {
      final lines = parseUnifiedDiff(
          'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n a\n \n-x\n+y\n');
      final blankCtx = lines.firstWhere((l) => l.text == ' ');
      expect(blankCtx.kind, LineKind.context);
      expect(blankCtx.hunkIndex, 0);
      expect(blankCtx.lineNumOld, isNotNull);
    });

    test('PatchEngine ignores hand-injected unnumbered context rows', () {
      // Tertiary defense: even if a future payload path smuggles an
      // unnumbered context row INTO a hunk group, it must not count.
      final lines = parseUnifiedDiff(
          'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,2 +1,2 @@\n ctx\n-a\n+b\n');
      final idx =
          lines.indexWhere((l) => l.kind == LineKind.added);
      lines[idx] = lines[idx].copyWith(isStaged: true);
      final pair = findReplacementPair(lines, idx);
      if (pair != null) lines[pair] = lines[pair].copyWith(isStaged: true);
      final poisoned = [
        ...lines,
        ParsedLine(text: '', kind: LineKind.context, hunkIndex: 0),
      ];
      final patch = PatchEngine.buildStagedPatch('f', poisoned);
      expect(patch, contains('@@ -1,2 +1,2 @@'));
      expect(patch.split('\n').where((l) => l == ' ').length, 0,
          reason: 'no bare-space phantom body line');
    });
  });

  test('non-ASCII content in the staged line survives the stdin pipe',
      () async {
    await wf('uni.dart').writeAsString('alpha\nnaïve — ✓ ünïcode\nomega\n');
    await git(['add', '-A']);
    await git(['commit', '-qm', 'base']);
    await wf('uni.dart')
        .writeAsString('alpha\nnaïve — ✓ ünïcode EDITÉD\nomega\n');

    final staged = await stageLineContaining('uni.dart', 'EDITÉD');
    expect(staged, contains('naïve — ✓ ünïcode EDITÉD'));
  });
}
