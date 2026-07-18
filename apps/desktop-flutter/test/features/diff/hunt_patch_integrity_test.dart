// Adversarial hunt: patch-engine + staging integrity against REAL git.
//
// Pipeline exercised, end to end, exactly as production code walks it:
//   ScratchRepo (real git) -> getFileDiff (app's own diff fetch, with the
//   app's diff-family config pins) OR the same synthetic ParsedLine shape
//   NewFileIndex produces for an untracked file -> select a SUBSET of
//   ParsedLines as staged -> PatchEngine.buildStagedPatch ->
//   applyFileStaging -> verify with real git plumbing (`status --porcelain`,
//   `show :path`).
//
// A wide adversarial sweep (CRLF/LF mixing, EOF-newline changes, replace-pair
// / move pairing traps, diff-syntax-lookalike content, multi-hunk adjacency
// with cumulativeDelta math, unicode + odd filenames, and stage/restage
// toggle storms) was run against this pipeline and found correct — see the
// hunt report for the full list. The two cases kept here are CONFIRMED,
// git-verified bugs: each is a failing test whose failure was traced to a
// specific PatchEngine root cause (see the comment on each test).
//
// Plain `test()` — no widget tree needed for this layer.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/patch_engine.dart';

import '../../support/scratch_repo.dart';

void main() {
  late ScratchRepo repo;

  setUp(() async {
    repo = await ScratchRepo.create();
  });

  tearDown(() async {
    await repo.dispose();
  });

  /// Read the raw diff for [path] via the app's own [getFileDiff] and
  /// parse it via the app's own parser.
  Future<List<ParsedLine>> diffLines(String path) async {
    final diff = await getFileDiff(repo.dir.path, path);
    expect(diff.ok, isTrue, reason: diff.error ?? '');
    return parseUnifiedDiff(diff.data!);
  }

  /// Stage exactly the lines selected by [select], leaving everything else
  /// untouched.
  List<ParsedLine> stageWhere(
      List<ParsedLine> lines, bool Function(ParsedLine) select) {
    return [
      for (final l in lines)
        if (select(l)) l.copyWith(isStaged: true) else l,
    ];
  }

  group('CONFIRMED BUG: whole-file-delete header forced despite a partial '
      'line selection', () {
    test('deleting a tracked file, but staging only SOME of the deleted '
        'lines: PatchEngine forces the file fully gone anyway, silently '
        'discarding the content the user left unstaged', () async {
      await repo.writeFile('doomed.txt', 'keep me\nremove me\nalso keep\n');
      await repo.gitOk(['add', '-A']);
      await repo.gitOk(['commit', '-m', 'base']);
      await repo.deleteFile('doomed.txt');

      final lines = await diffLines('doomed.txt');
      // Sanity: this is a whole-file-delete diff (every body line deleted).
      expect(lines.any((l) => l.kind == LineKind.added), isFalse);
      expect(
          lines.any((l) =>
              l.kind == LineKind.meta &&
              l.text.startsWith('deleted file mode')),
          isTrue);

      // Stage ONLY the removal of the middle line — leave "keep me" and
      // "also keep" unstaged (i.e. NOT selected for removal). The correct
      // outcome is a MODIFIED file in the index (two lines kept, one
      // removed) — never a full deletion.
      final staged = stageWhere(lines,
          (l) => l.kind == LineKind.deleted && l.text.contains('remove me'));

      final patch = PatchEngine.buildStagedPatch('doomed.txt', staged);
      // Root cause, empirically: PatchEngine derives `isDeletedFile` purely
      // from the ORIGINAL diff's meta lines (patch_engine.dart:21-24) and
      // then unconditionally emits `+++ /dev/null` whenever that flag is
      // set (patch_engine.dart:32-34) — regardless of whether the hunk body
      // it just built still carries kept (context) content. Here the body is
      // ` keep me\n-remove me\n also keep` (2 lines survive as context) but
      // the header still declares the target /dev/null:
      //
      //   diff --git a/doomed.txt b/doomed.txt
      //   --- a/doomed.txt
      //   +++ /dev/null
      //   @@ -1,3 +0,2 @@
      //    keep me
      //   -remove me
      //    also keep
      //
      // That header/body pair is internally contradictory (a "delete to
      // /dev/null" hunk that also keeps 2 lines of "new side" content).
      // Verified directly against real git (no app code involved) that
      // `git apply --cached` accepts this WITHOUT ERROR and stages a full
      // deletion, discarding "keep me" / "also keep" — they are not staged
      // ANYWHERE (not in the index, not left pending in the worktree diff);
      // the content is simply gone from what `git show :doomed.txt` can
      // ever return once this patch lands.
      final r = await applyFileStaging(repo.dir.path, 'doomed.txt', patch);
      expect(r.ok, isTrue,
          reason: 'applyFileStaging failed: ${r.error}\n--- patch ---\n$patch');

      final statusLine =
          (await repo.git(['status', '--porcelain', '--', 'doomed.txt']))
              .stdout
              .toString();
      // FIXED contract: the INDEX column must be a modification ('M'), never
      // a full deletion ('D') — the user staged removal of the MIDDLE line
      // only. The WORKTREE column legitimately reads 'D' (the file really is
      // deleted on disk), so assert the index column specifically.
      final indexColumn = statusLine.trimLeft().isEmpty ? '' : statusLine[0];
      expect(indexColumn, 'M',
          reason: 'index status for doomed.txt: $statusLine');
      // And the kept lines must actually LIVE in the index — the whole point.
      final indexContent =
          (await repo.git(['show', ':doomed.txt'])).stdout.toString();
      expect(indexContent, contains('keep me'));
      expect(indexContent, contains('also keep'));
      expect(indexContent, isNot(contains('remove me')));
    });
  });

  group('CONFIRMED BUG: brand-new (untracked) file staging is unconditionally '
      'broken', () {
    test('untracked file staged via the SAME synthetic header shape '
        'NewFileIndex produces (new file mode 100644 + --- /dev/null): '
        'applyFileStaging fails outright, nothing ever gets staged',
        () async {
      // Mirrors lib/features/diff/new_file_index.dart's `_newFileHeader`
      // EXACTLY — the real production shape fed to PatchEngine whenever a
      // user opens a brand-new untracked file in the diff shell (DiffShell
      // with enableStaging: true, changes_page.dart ~8643/~8703) and stages
      // any subset (or even ALL) of its lines. NewFileIndex never produces
      // raw unified-diff text at all — it hydrates ParsedLines straight
      // from the working file — so this constructs that exact ParsedLine
      // shape directly rather than through a raw-text parse.
      const path = 'untracked_new.txt';
      await repo.writeFile(path, 'first\nsecond\nthird\n');
      // Deliberately NOT `git add`ed — stays untracked, exactly the state
      // NewFileIndex is used for.

      final headerLines = [
        ParsedLine(
            text: 'diff --git a/$path b/$path',
            kind: LineKind.meta,
            hunkIndex: -1,
            filePath: path),
        ParsedLine(
            text: 'new file mode 100644',
            kind: LineKind.meta,
            hunkIndex: -1,
            filePath: path),
        ParsedLine(
            text: '--- /dev/null',
            kind: LineKind.meta,
            hunkIndex: -1,
            filePath: path),
        ParsedLine(
            text: '+++ b/$path',
            kind: LineKind.meta,
            hunkIndex: -1,
            filePath: path),
        ParsedLine(
            text: '@@ -0,0 +1,3 @@',
            kind: LineKind.hunk,
            hunkIndex: 0,
            filePath: path),
      ];
      final bodyLines = [
        ParsedLine(
            text: '+first',
            kind: LineKind.added,
            lineNumNew: 1,
            hunkIndex: 0,
            filePath: path),
        ParsedLine(
            text: '+second',
            kind: LineKind.added,
            lineNumNew: 2,
            hunkIndex: 0,
            filePath: path),
        ParsedLine(
            text: '+third',
            kind: LineKind.added,
            lineNumNew: 3,
            hunkIndex: 0,
            filePath: path),
      ];
      final allLines = [...headerLines, ...bodyLines];

      // Stage ALL three lines — the simplest possible "stage this whole new
      // file" action a user takes by clicking every sigil (or a stage-all
      // control routed through the same per-line pipeline) on a brand-new
      // file.
      final staged = stageWhere(allLines, (l) => l.kind == LineKind.added);
      final patch = PatchEngine.buildStagedPatch(path, staged);
      // Root cause, empirically: PatchEngine.buildStagedPatch (patch_engine
      // .dart:29-31) reads `new file mode` from the input meta lines only to
      // decide `isNewFile` — it never RE-EMITS a `new file mode <mode>` (or
      // `index 0000000..<hash>`) line into the patch it builds. The output
      // here is exactly:
      //
      //   diff --git a/untracked_new.txt b/untracked_new.txt
      //   --- /dev/null
      //   +++ b/untracked_new.txt
      //   @@ -0,0 +1,3 @@
      //   +first
      //   +second
      //   +third
      //
      // Verified directly against real git (no app code involved) that
      // `git apply --cached` REJECTS this exact patch shape with
      // "error: dev/null: does not exist in index" (confirmed both via
      // `--check` and a real apply) — but ACCEPTS the identical patch with
      // a `new file mode 100644` line inserted after the `diff --git`
      // header. Every brand-new (never `git add`ed) file staged through
      // this pipeline — whole-file or any single line of it — fails to
      // stage at all; `_runApply` in diff_shell.dart surfaces this as a
      // hard staging error with nothing landing in the index.
      final r = await applyFileStaging(repo.dir.path, path, patch);
      expect(r.ok, isTrue,
          reason: 'applyFileStaging failed: ${r.error}\n--- patch ---\n$patch');
    });

    test('same failure reproduces from git\'s OWN --no-index new-file diff '
        'text (not just the NewFileIndex-synthesized shape)', () async {
      const path = 'newborn.txt';
      await repo.writeFile(path, 'first\nsecond\nthird\n');

      // Untracked files never appear in a plain `git diff -- path` (index
      // has no entry yet). Reproduce with git's OWN --no-index new-file
      // diff, using the app's exact diff-family config pins
      // (_kDiffCmd/_kDiffContentPins in git.dart). This input DOES carry a
      // `new file mode 100644` meta line (verified below) — proving the bug
      // is specifically that PatchEngine's OUTPUT drops a `new file mode`
      // line it HAD in its input, in every construction that reaches it,
      // not that the input was ever missing one to begin with.
      final r0 = await repo.git([
        '-c', 'diff.binary=false', 'diff', '--no-index',
        '--no-color', '--no-ext-diff', '--src-prefix=a/', '--dst-prefix=b/',
        '--', '/dev/null', path,
      ]);
      expect(r0.exitCode, anyOf(0, 1), reason: r0.stderr.toString());
      final lines = parseUnifiedDiff(r0.stdout as String);
      expect(
          lines.any((l) =>
              l.kind == LineKind.meta && l.text.startsWith('new file mode')),
          isTrue,
          reason: 'sanity: the INPUT diff must carry `new file mode` for '
              'this to demonstrate PatchEngine dropping it');

      final staged = stageWhere(
          lines, (l) => l.kind == LineKind.added && l.text.contains('second'));
      final patch = PatchEngine.buildStagedPatch(path, staged);
      final r = await applyFileStaging(repo.dir.path, path, patch);
      expect(r.ok, isTrue,
          reason: 'applyFileStaging failed: ${r.error}\n--- patch ---\n$patch');
    });
  });
}
