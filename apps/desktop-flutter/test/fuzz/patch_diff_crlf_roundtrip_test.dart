// Roundtrip + cross-OS (CRLF) fuzz suite for Manifold's diff/patch/merge
// text layer: parseUnifiedDiff/PatchEngine (lib/features/diff/), the hunk
// parser (lib/backend/logos_hunks.dart), and the conflict editor / patch-as-
// merge machinery (lib/features/changes/).
//
// test/features/patch_engine_roundtrip_test.dart and
// merge_conflict_parser_test.dart already cover the fixed-scenario E2E
// staging pipeline and the hand-picked conflict-parsing cases — this file
// fuzzes around them (random A/B pairs, CRLF, no-final-newline, hostile
// filenames) using real git as the oracle wherever the property crosses
// into IO.
//
// LAWS:
//   1+2. diff -> parseUnifiedDiff -> PatchEngine.buildStagedPatch -> real
//        `git apply` reproduces B byte-exact from A, including when either
//        side lacks a final newline (the `\ No newline at end of file`
//        marker must survive the round trip).
//   3.   CRLF: parseUnifiedDiff leaves a literal trailing '\r' baked into
//        ParsedLine.text (it only splits on '\n', per its own header
//        comment) — benign for the buildStagedPatch -> git-apply round
//        trip in every case tried here (content round-trips byte-exact).
//   4.   parseConflictFile <-> ConflictFile.buildResult() roundtrips a
//        resolved conflict file back to marker-free text; clean text never
//        produces spurious blocks; truncated/mid-conflict input never
//        throws.
//   5.   reviewMergeFromPatch: a patch generated from a real ours->theirs
//        edit, applied against the correct in-memory "ours", reproduces
//        "theirs" on accept-all and "ours" on reject-all; applied against
//        unrelated "ours" content it returns null gracefully (never
//        throws).
//   6.   sliceDiffByFile partitions a multi-file diff so every hunk from
//        parseDiffHunks appears in exactly one per-file slice.
//   7.   git's C-quoting of unusual (unicode/space) filenames is correctly
//        reversed by logos_hunks.dart's path extraction.
//
// Formerly-known bugs (each had a dedicated `skip:`-ed repro test, now
// fixed and unskipped — search this file for `GENUINE BUG (FIXED)` for the
// individual writeups; original writeups in
// docs/architecture/test-hardening-bug-dossier.md):
//   - patch_engine.dart: `PatchEngine.buildStagedPatch`'s `isNewFile`
//     heuristic couldn't tell "brand new file" from "an existing, already-
//     tracked, empty file gaining its first line(s)" — both diffs have
//     zero old-side lines. It emitted `--- /dev/null`, which real
//     `git apply` rejects since the target already exists. Fixed by
//     deriving new/deleted status from the diff's own meta lines.
//   - patch_as_merge.dart: `_spliceConflictMarkers` never read
//     `ParsedLine.noNewlineAtEof`, so `reviewMergeFromPatch`'s accept-all/
//     reject-all could silently gain a trailing newline the real file
//     never had, whenever the diff's last touched line has none. Fixed by
//     threading the flag through to the last ConflictBlock and having
//     ConflictFile.buildResult() honor it.
//   - logos_hunks.dart, x2, both under LAW 7: (a) non-ASCII filenames —
//     git's per-byte octal C-quoting was decoded one UTF-16 code unit per
//     escape instead of being recombined and UTF-8-decoded, producing
//     mojibake; (b) space-containing filenames — `_pathFromDiffHeader`'s
//     `line.split(' ')[3]` shattered on the filename's own internal
//     spaces. Both fixed locally in logos_hunks.dart, THEN extracted into
//     lib/backend/git_diff_paths.dart (pathFromDiffGitHeader /
//     unCQuoteGitPath / patchSidePath) once diff_models.dart's separate,
//     naive `RegExp(r'^diff --git a/(.+) b/(.+)$')` header parser was
//     found to have the SAME two defects independently — the canonical UI
//     parser (parseUnifiedDiff/sliceDiffByFile, used by PatchEngine,
//     DiffShell, reviewMergeFromPatch) now shares the one fixed
//     implementation instead of drifting from logos_hunks.dart's.
//
// Async fuzzing note: the properties here need real git subprocesses, so
// they run through `forAllAsync` (test/support/prop.dart) — the async
// sibling of `forAll`, sharing its seed/index reproducibility contract, its
// choice-tape shrinker, and its on-disk corpus. Its shrink budget defaults
// low (40 candidate evaluations) precisely because each candidate here
// re-spawns git.
//
// SCALING: every fuzz group multiplies its case count by `fuzzScale()`
// (env `MANIFOLD_FUZZ`), default 1 -> a normal, CI-sized run.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:git_desktop/backend/logos_hunks.dart'
    show parseDiffHunks, parseDiffHunksForFile;
import 'package:git_desktop/features/changes/merge_conflict_editor.dart';
import 'package:git_desktop/features/changes/patch_as_merge.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/patch_engine.dart';

import '../support/gen.dart';
import '../support/prop.dart';
import '../support/scratch_repo.dart';

// ---------------------------------------------------------------------------
// Shared repo/file helpers
// ---------------------------------------------------------------------------

/// True for the two benign git messages a no-op commit can produce: a
/// fully clean tree ("nothing to commit"), or this path's content already
/// matching HEAD while some OTHER (unrelated, never explicitly committed)
/// path in the same repo is still sitting dirty ("no changes added to
/// commit (use \"git add\" ...)") — both mean "this path's HEAD state
/// already equals what we just wrote", which is the only invariant
/// [_writeAndCommit] promises.
bool _isBenignNoCommitMessage(String combined) =>
    combined.contains('nothing to commit') ||
    combined.contains('no changes added to commit');

/// Writes [content] to [path] and commits it. Tolerant of a benign no-op
/// commit (see [_isBenignNoCommitMessage]) but surfaces any OTHER commit
/// failure loudly.
Future<void> _writeAndCommit(
  ScratchRepo repo,
  String path,
  String content, {
  String message = 'base',
}) async {
  await repo.writeFile(path, content);
  await repo.gitOk(['add', '--', path]);
  final commitResult = await repo.git(['commit', '-m', message]);
  if (commitResult.exitCode != 0) {
    final combined = '${commitResult.stdout}${commitResult.stderr}';
    expect(_isBenignNoCommitMessage(combined), isTrue,
        reason: 'unexpected `git commit` failure for "$path":\n$combined');
  }
}

Future<File> _writePatchFile(Directory dir, String name, String patch) async {
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(utf8.encode(patch), flush: true);
  return file;
}

File _repoFile(ScratchRepo repo, String relPath) =>
    File(p.join(repo.dir.path, relPath));

/// Stages every added/deleted [ParsedLine] (mirrors "select every changed
/// line" — context/meta/hunk lines pass through untouched, exactly as
/// PatchEngine expects).
List<ParsedLine> _stageAll(List<ParsedLine> lines) => [
      for (final l in lines)
        (l.kind == LineKind.deleted || l.kind == LineKind.added)
            ? l.copyWith(isStaged: true)
            : l,
    ];

// ---------------------------------------------------------------------------
// LAW 1 + 2 — diff -> parse -> rebuild roundtrip, incl. no-final-newline
// ---------------------------------------------------------------------------

Gen<(String, String)> _genABPair({int maxLines = 10}) {
  final g = genMultilineText(maxLines: maxLines);
  return (rng) => (g(rng), g(rng));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scale = fuzzScale();

  group('LAW 1+2 — diff -> parse -> rebuild roundtrip (byte-exact)', () {
    late ScratchRepo repo;
    late Directory patchDir;
    const path = 'f.txt';
    var caseId = 0;

    setUp(() async {
      repo = await ScratchRepo.create(name: 'roundtrip');
      patchDir = await Directory.systemTemp.createTemp('roundtrip_patch_');
      caseId = 0;
    });

    tearDown(() async {
      await repo.dispose();
      try {
        await patchDir.delete(recursive: true);
      } catch (_) {}
    });

    Future<void> roundtripCase(String a, String b) async {
      final id = caseId++;
      await _writeAndCommit(repo, path, a, message: 'base $id');
      await repo.writeFile(path, b);
      final diffRes = await repo.git(['diff', '--', path]);
      expect(diffRes.exitCode, 0,
          reason: 'git diff failed: ${diffRes.stderr}');
      final diffText = diffRes.stdout as String;
      if (diffText.isEmpty) {
        return; // A == B — a benign generator collision, nothing to test.
      }

      final lines = parseUnifiedDiff(diffText);
      final staged = _stageAll(lines);
      final rebuilt = PatchEngine.buildStagedPatch(path, staged);
      expect(rebuilt, isNotEmpty,
          reason: 'buildStagedPatch produced an empty patch for a '
              'non-empty diff.\n--- diff ---\n$diffText');

      // Restore A in the working tree, then apply the REBUILT patch (never
      // the app's own applyPatch — real `git apply` is the oracle here).
      await repo.gitOk(['checkout', '--', path]);
      final patchFile =
          await _writePatchFile(patchDir, 'case_$id.patch', rebuilt);
      final applyRes =
          await repo.git(['apply', '--whitespace=nowarn', patchFile.path]);
      expect(applyRes.exitCode, 0,
          reason: 'git apply rejected the rebuilt patch.\n'
              'STDERR: ${applyRes.stderr}\n'
              '--- original diff ---\n$diffText\n'
              '--- rebuilt patch ---\n$rebuilt');

      final resultBytes = await _repoFile(repo, path).readAsBytes();
      expect(resultBytes, equals(utf8.encode(b)),
          reason: 'byte mismatch after apply.\n'
              '--- original diff ---\n$diffText\n'
              '--- rebuilt patch ---\n$rebuilt\n'
              '--- expected B ---\n$b');
    }

    test('fuzz: many independent A/B pairs round-trip byte-exact', () async {
      await forAllAsync(
        _genABPair(maxLines: 10),
        count: 30 * scale,
        seed: 0x1A11,
        describe: 'A/B pair',
        check: (pair) async {
          final (a, b) = pair;
          await roundtripCase(a, b);
        },
      );
    });

    test(
        'deterministic: no trailing newline on A only — marker survives '
        'and no newline is silently added', () async {
      const a = 'one\ntwo\nthree';
      const b = 'one\ntwo\nthree EDITED';
      await _writeAndCommit(repo, path, a, message: 'nf-a');
      await repo.writeFile(path, b);
      final diffText = (await repo.git(['diff', '--', path])).stdout as String;
      expect(diffText, contains(r'\ No newline at end of file'));

      final lines = parseUnifiedDiff(diffText);
      expect(lines.any((l) => l.noNewlineAtEof), isTrue,
          reason: 'noNewlineAtEof flag never got attached\n$diffText');

      final rebuilt = PatchEngine.buildStagedPatch(path, _stageAll(lines));
      expect(rebuilt, contains(r'\ No newline at end of file'),
          reason: 'rebuilt patch dropped the no-newline marker\n$rebuilt');

      await repo.gitOk(['checkout', '--', path]);
      final patchFile = await _writePatchFile(patchDir, 'nf.patch', rebuilt);
      final applyRes =
          await repo.git(['apply', '--whitespace=nowarn', patchFile.path]);
      expect(applyRes.exitCode, 0, reason: applyRes.stderr.toString());

      final resultBytes = await _repoFile(repo, path).readAsBytes();
      expect(resultBytes, equals(utf8.encode(b)));
      expect(utf8.decode(resultBytes).endsWith('\n'), isFalse,
          reason: 'a trailing newline was silently added to a file that '
              'never had one');
    });

    test(
        'deterministic: A has no trailing newline, B gains one — the '
        'newline is correctly added, not dropped', () async {
      const a = 'one\ntwo\nthree';
      const b = 'one\ntwo\nthree EDITED\n';
      await _writeAndCommit(repo, path, a, message: 'nf2-a');
      await repo.writeFile(path, b);
      final diffText = (await repo.git(['diff', '--', path])).stdout as String;
      expect(diffText, contains(r'\ No newline at end of file'));

      final lines = parseUnifiedDiff(diffText);
      final rebuilt = PatchEngine.buildStagedPatch(path, _stageAll(lines));

      await repo.gitOk(['checkout', '--', path]);
      final patchFile = await _writePatchFile(patchDir, 'nf2.patch', rebuilt);
      final applyRes =
          await repo.git(['apply', '--whitespace=nowarn', patchFile.path]);
      expect(applyRes.exitCode, 0, reason: applyRes.stderr.toString());

      final resultBytes = await _repoFile(repo, path).readAsBytes();
      expect(resultBytes, equals(utf8.encode(b)));
      expect(utf8.decode(resultBytes).endsWith('\n'), isTrue,
          reason: 'B\'s trailing newline got dropped by the round trip');
    });

    test(
        // GENUINE BUG (FIXED): PatchEngine.buildStagedPatch's `isNewFile`
        // heuristic used to be "no line in the diff has an old-side line
        // number" — but an already-tracked empty file gaining its first
        // line(s) produces exactly that same shape (zero old-side lines)
        // as a genuinely brand-new file, so it wrongly emitted
        // `--- /dev/null`, which real git rejects because the target file
        // already exists. Fixed by deriving new/deleted status from the
        // diff's OWN `--- `/`+++ `/`new file mode` meta lines (which
        // parseUnifiedDiff already preserves per-line) instead of from
        // line-number absence. Not a CRLF issue: reproduces identically
        // with plain LF.
        'an existing (tracked, empty) file gaining its first line is '
        'staged as an edit to an existing file, not a brand-new file',
        () async {
      const emptyPath = 'was_empty.txt';
      await _writeAndCommit(repo, emptyPath, '', message: 'empty base');
      await repo.writeFile(emptyPath, 'first line\n');
      final diffText =
          (await repo.git(['diff', '--', emptyPath])).stdout as String;
      expect(diffText, isNotEmpty);

      final lines = parseUnifiedDiff(diffText);
      final rebuilt =
          PatchEngine.buildStagedPatch(emptyPath, _stageAll(lines));
      expect(rebuilt, isNot(contains('/dev/null')),
          reason: 'the file already exists — the rebuilt patch must not '
              'claim it is new.\n--- rebuilt ---\n$rebuilt');
      expect(rebuilt, contains('--- a/$emptyPath'));
      expect(rebuilt, contains('+++ b/$emptyPath'));

      await repo.gitOk(['checkout', '--', emptyPath]);
      final patchFile =
          await _writePatchFile(patchDir, 'was_empty.patch', rebuilt);
      final applyRes =
          await repo.git(['apply', '--whitespace=nowarn', patchFile.path]);
      expect(applyRes.exitCode, 0,
          reason: 'git apply rejected the rebuilt patch.\n'
              'STDERR: ${applyRes.stderr}\n--- rebuilt ---\n$rebuilt');

      final resultBytes = await _repoFile(repo, emptyPath).readAsBytes();
      expect(resultBytes, equals(utf8.encode('first line\n')));
    });
  });

  // ---------------------------------------------------------------------------
  // LAW 3 — CRLF cross-OS hunt
  // ---------------------------------------------------------------------------

  group('LAW 3 — CRLF cross-OS hunt', () {
    late ScratchRepo repo;
    late Directory patchDir;

    setUp(() async {
      repo = await ScratchRepo.create(name: 'crlf_hunt', autocrlf: false);
      patchDir = await Directory.systemTemp.createTemp('crlf_patch_');
    });

    tearDown(() async {
      await repo.dispose();
      try {
        await patchDir.delete(recursive: true);
      } catch (_) {}
    });

    test(
        'deterministic: CRLF body lines through '
        'parse -> rebuild -> git apply', () async {
      const path = 'crlf.txt';
      const a = 'alpha\r\nbeta\r\ngamma\r\ndelta\r\n';
      const b = 'alpha\r\nbeta EDITED\r\ngamma\r\ndelta\r\n';

      await _writeAndCommit(repo, path, a, message: 'crlf base');
      await repo.writeFile(path, b);
      final diffRes = await repo.git(['diff', '--', path]);
      expect(diffRes.exitCode, 0);
      final diffText = diffRes.stdout as String;
      expect(diffText, isNotEmpty,
          reason: 'expected a real diff for the CRLF edit');

      // Sanity FIRST: confirm real git accepts its OWN raw diff output,
      // so any later failure is provably the app's parser/rebuild, not a
      // malformed test fixture. The working tree is currently AT B (we
      // just wrote it to compute the diff above) — restore A first, since
      // applying an A->B patch on top of an already-B tree would fail for
      // a totally mundane reason (context mismatch), not a CRLF issue.
      await repo.gitOk(['checkout', '--', path]);
      final rawPatchFile =
          await _writePatchFile(patchDir, 'raw.patch', diffText);
      final rawApply =
          await repo.git(['apply', '--whitespace=nowarn', rawPatchFile.path]);
      expect(rawApply.exitCode, 0,
          reason: 'sanity check failed: real git rejected its OWN diff '
              'output — the test fixture is broken, not the app.\n'
              'STDERR: ${rawApply.stderr}\n$diffText');
      final rawResult = await _repoFile(repo, path).readAsBytes();
      expect(rawResult, equals(utf8.encode(b)),
          reason: 'sanity check failed: git apply of the RAW diff did not '
              'reproduce B');
      await repo.gitOk(['checkout', '--', path]); // back to A for real probe

      // Probe: does a body line carry a literal trailing '\r' in .text?
      final lines = parseUnifiedDiff(diffText);
      final bodyLines = lines
          .where((l) =>
              l.kind == LineKind.added ||
              l.kind == LineKind.deleted ||
              (l.kind == LineKind.context && l.lineNumOld != null))
          .toList();
      expect(bodyLines, isNotEmpty);
      final leaked = bodyLines.where((l) => l.text.endsWith('\r')).toList();
      // ignore: avoid_print
      print(
          '[crlf-hunt] ${leaked.length}/${bodyLines.length} body lines carry '
          'a literal trailing \\r in ParsedLine.text (diff_models.dart\'s '
          'own header comment documents this: it splits on \'\\n\' only and '
          'does NOT strip \'\\r\').');
      expect(leaked, isNotEmpty,
          reason: 'expected the documented CRLF leak to be present for '
              'this probe to mean anything');

      // Does the leak corrupt buildStagedPatch's output?
      final rebuilt = PatchEngine.buildStagedPatch(path, _stageAll(lines));
      expect(rebuilt, isNotEmpty);
      // ignore: avoid_print
      print('[crlf-hunt] rebuilt patch:\n$rebuilt');

      final rebuiltFile =
          await _writePatchFile(patchDir, 'rebuilt.patch', rebuilt);
      final applyResult =
          await repo.git(['apply', '--whitespace=nowarn', rebuiltFile.path]);

      if (applyResult.exitCode != 0) {
        // The rebuilt patch, corrupted by the leaked '\r', was rejected by
        // real git.
        fail('PatchEngine.buildStagedPatch produced a '
            'patch real git rejected after a CRLF round trip.\n'
            'STDERR: ${applyResult.stderr}\n'
            '--- original diff ---\n$diffText\n'
            '--- rebuilt patch ---\n$rebuilt');
      }

      final resultBytes = await _repoFile(repo, path).readAsBytes();
      final verdict = resultBytes.length == utf8.encode(b).length &&
          _bytesEqual(resultBytes, utf8.encode(b));
      // ignore: avoid_print
      print('[crlf-hunt] VERDICT: CRLF round trip ${verdict ? 'PRESERVED byte-exact' : 'CORRUPTED'} the content.');
      if (!verdict) {
        fail('git apply accepted the rebuilt patch but '
            'the resulting content diverged from B.\n'
            '--- original diff ---\n$diffText\n'
            '--- rebuilt patch ---\n$rebuilt\n'
            '--- expected B (${utf8.encode(b).length} bytes) ---\n$b\n'
            '--- got (${resultBytes.length} bytes) ---\n'
            '${utf8.decode(resultBytes, allowMalformed: true)}');
      }
    });

    test('fuzz: CRLF-only content (guaranteed, single-line edits)', () async {
      var caseId = 0;
      await forAllAsync(
        _genCrlfPair(maxLines: 8),
        count: 20 * scale,
        seed: 0xCE1F,
        describe: 'CRLF pair',
        check: (pair) async {
          final (a, b) = pair;
          final id = caseId++;
          const path = 'crlf_fuzz.txt';
          await _writeAndCommit(repo, path, a, message: 'crlf-fuzz base $id');
          await repo.writeFile(path, b);
          final diffRes = await repo.git(['diff', '--', path]);
          expect(diffRes.exitCode, 0);
          final diffText = diffRes.stdout as String;
          if (diffText.isEmpty) return;

          final lines = parseUnifiedDiff(diffText);
          final rebuilt = PatchEngine.buildStagedPatch(path, _stageAll(lines));
          expect(rebuilt, isNotEmpty,
              reason: 'empty rebuilt patch for a non-empty CRLF diff\n$diffText');

          await repo.gitOk(['checkout', '--', path]);
          final patchFile =
              await _writePatchFile(patchDir, 'crlf_fuzz_$id.patch', rebuilt);
          final applyRes = await repo
              .git(['apply', '--whitespace=nowarn', patchFile.path]);
          expect(applyRes.exitCode, 0,
              reason: 'git apply rejected the '
                  'rebuilt patch.\nSTDERR: ${applyRes.stderr}\n'
                  '--- original diff ---\n$diffText\n'
                  '--- rebuilt patch ---\n$rebuilt');

          final resultBytes = await _repoFile(repo, path).readAsBytes();
          expect(resultBytes, equals(utf8.encode(b)),
              reason: 'byte mismatch after '
                  'apply.\n--- original diff ---\n$diffText\n'
                  '--- rebuilt patch ---\n$rebuilt');
        },
      );
    });
  });

  // ---------------------------------------------------------------------------
  // LAW 4 — conflict roundtrip (pure, sync)
  // ---------------------------------------------------------------------------

  group('LAW 4 — conflict roundtrip (pure)', () {
    test(
        'fuzz: parse -> resolve every block -> buildResult is marker-free '
        'and matches the chosen sides', () {
      forAll(
        _genConflictScenario(),
        count: 60 * scale,
        seed: 0xC0F1,
        describe: 'conflict scenario',
        check: (s) {
          final cf = parseConflictFile('f.dart', s.doc);
          expect(cf.blocks.length, s.oursTexts.length,
              reason: 'block count mismatch.\n--- doc ---\n${s.doc}');
          for (var i = 0; i < cf.blocks.length; i++) {
            expect(cf.blocks[i].oursText, s.oursTexts[i],
                reason: 'ours mismatch at block $i\n--- doc ---\n${s.doc}');
            expect(cf.blocks[i].theirsText, s.theirsTexts[i],
                reason: 'theirs mismatch at block $i\n--- doc ---\n${s.doc}');
            cf.blocks[i].resolution =
                s.resolveOurs[i] ? ConflictSide.ours : ConflictSide.theirs;
          }

          final result = cf.buildResult();
          for (final line in result.split('\n')) {
            expect(
                line.startsWith('<<<<<<<') ||
                    line.startsWith('=======') ||
                    line.startsWith('>>>>>>>') ||
                    line.startsWith('|||||||'),
                isFalse,
                reason:
                    'a conflict marker survived resolution: "$line"\n--- result ---\n$result');
          }

          for (var i = 0; i < cf.blocks.length; i++) {
            final chosen = s.resolveOurs[i] ? s.oursTexts[i] : s.theirsTexts[i];
            final other = s.resolveOurs[i] ? s.theirsTexts[i] : s.oursTexts[i];
            if (chosen.isNotEmpty) {
              expect(result, contains(chosen),
                  reason: 'block $i resolved text missing from result\n'
                      '--- result ---\n$result');
            }
            // Only probe "the rejected side is truly absent" when `other`
            // is distinctive enough that an incidental substring match
            // elsewhere in the (multi-block, CRLF-flavored) document would
            // be astronomically unlikely — a short string (even a single
            // stray '\r') can innocuously reappear inside a WHOLLY
            // UNRELATED block's own content, which would make this a
            // false failure, not a real leak.
            if (other.length >= 8 &&
                other != chosen &&
                !chosen.contains(other)) {
              expect(result, isNot(contains(other)),
                  reason: 'block $i: the REJECTED side leaked into the '
                      'result\n--- result ---\n$result');
            }
          }

          final reparsed = parseConflictFile('f.dart', result);
          expect(reparsed.blocks, isEmpty,
              reason: 'resolved output still parses as containing '
                  'conflicts\n--- result ---\n$result');
        },
      );
    });

    test(
        'fuzz: clean (no-marker) text always yields zero blocks and is '
        'preserved verbatim', () {
      forAll(
        genMultilineText(maxLines: 15),
        count: 60 * scale,
        seed: 0xC1EA,
        describe: 'clean text',
        check: (text) {
          if (text.contains('<<<<<<<') ||
              text.contains('>>>>>>>') ||
              text.contains('|||||||')) {
            return; // astronomically rare accidental marker collision.
          }
          final cf = parseConflictFile('f.dart', text);
          expect(cf.blocks, isEmpty);
          expect(cf.segments.length, 1);
          expect(cf.segments.single, text);
          expect(cf.fullText, text);
        },
      );
    });

    test('fuzz: truncated/mid-conflict input never throws', () {
      forAll(
        _genTruncatedConflict(),
        count: 40 * scale,
        seed: 0xC2AB,
        describe: 'truncated doc',
        check: (t) {
          late final ConflictFile cf;
          expect(() {
            cf = parseConflictFile('f.dart', t.truncated);
          }, returnsNormally);
          expect(cf.segments, isNotEmpty);
          expect(() => cf.buildResult(), returnsNormally);
        },
      );
    });
  });

  // ---------------------------------------------------------------------------
  // LAW 5 — reviewMergeFromPatch
  // ---------------------------------------------------------------------------

  group('LAW 5 — reviewMergeFromPatch (accept-all/reject-all + graceful '
      'mismatch)', () {
    late ScratchRepo repo;
    const path = 'merge_review.txt';
    var caseId = 0;

    setUp(() async {
      repo = await ScratchRepo.create(name: 'review_merge');
      caseId = 0;
    });

    tearDown(() async {
      await repo.dispose();
    });

    test(
        'fuzz: correct ours reproduces theirs (accept-all) and ours '
        '(reject-all)', () async {
      await forAllAsync(
        _genABPair(maxLines: 10),
        count: 25 * scale,
        seed: 0x5E17,
        describe: 'ours/theirs pair',
        // Each candidate re-spawns git, so this is deliberately bounded.
        // 200 was measured to take the known counterexample from 151 draws
        // to 6 ("ours" and "theirs" both a single empty terminated line).
        shrinkEvaluations: 200,
        shrinkTimeout: const Duration(minutes: 2),
        check: (pair) async {
          final (a, t) = pair;
          final id = caseId++;
          await _writeAndCommit(repo, path, a, message: 'review base $id');
          await repo.writeFile(path, t);
          final diffRes = await repo.git(['diff', '--', path]);
          expect(diffRes.exitCode, 0);
          final diffText = diffRes.stdout as String;
          if (diffText.isEmpty) return;

          final result = reviewMergeFromPatch(diffText, {path: a});
          expect(result, isNotNull,
              reason: 'returned null for a self-consistent ours/theirs '
                  'pair.\n--- a (ours) ---\n$a\n--- t (theirs) ---\n$t\n'
                  '--- diff ---\n$diffText');
          final resolved = result!;
          expect(resolved.length, 1,
              reason: 'expected exactly one ConflictFile for a single '
                  'touched path');

          for (final block in resolved.single.blocks) {
            block.resolution = ConflictSide.theirs;
          }
          final acceptAll = resolved.single.buildResult();
          expect(acceptAll, t,
              reason: 'accept-all did not reproduce theirs exactly.\n'
                  '--- diff ---\n$diffText\n--- got ---\n$acceptAll');

          for (final block in resolved.single.blocks) {
            block.resolution = ConflictSide.ours;
          }
          final rejectAll = resolved.single.buildResult();
          expect(rejectAll, a,
              reason: 'reject-all did not reproduce ours exactly.\n'
                  '--- diff ---\n$diffText\n--- got ---\n$rejectAll');
        },
      );
    });

    test(
        // GENUINE BUG (FIXED): _spliceConflictMarkers (patch_as_merge.dart)
        // used to build the marker-spliced text purely from
        // ParsedLine.text substrings and never consulted
        // ParsedLine.noNewlineAtEof — unlike PatchEngine.buildStagedPatch,
        // which explicitly re-emits the `\ No newline at end of file`
        // marker. The marker-embedded document is invariant to trailing-
        // newline status (round-trips identically either way), so the
        // fix threads the real noNewlineAtEof flags through explicitly:
        // _spliceConflictMarkers now returns them alongside the text,
        // reviewMergeFromPatch stamps them onto whichever ConflictBlock
        // ends up last, and ConflictFile.buildResult() (merge_conflict_
        // editor.dart) suppresses its unconditional rejoin-newline for
        // that block when the resolved side is flagged. Plain LF content,
        // no CRLF involved.
        'reviewMergeFromPatch preserves the file\'s no-trailing-newline '
        'status on accept-all and reject-all', () async {
      const a = 'one\ntwo\nthree';
      const t = 'one\ntwo\nthree EDITED'; // theirs — no trailing newline
      await _writeAndCommit(repo, path, a, message: 'no-newline base');
      await repo.writeFile(path, t);
      final diffText = (await repo.git(['diff', '--', path])).stdout as String;
      expect(diffText, contains(r'\ No newline at end of file'));

      final result = reviewMergeFromPatch(diffText, {path: a});
      expect(result, isNotNull);
      for (final block in result!.single.blocks) {
        block.resolution = ConflictSide.theirs;
      }
      final acceptAll = result.single.buildResult();
      expect(acceptAll, t,
          reason: 'accept-all must reproduce theirs exactly, including no '
              'trailing newline.\ngot: ${acceptAll.toString()}');

      for (final block in result.single.blocks) {
        block.resolution = ConflictSide.ours;
      }
      final rejectAll = result.single.buildResult();
      expect(rejectAll, a,
          reason: 'reject-all must reproduce ours exactly, including no '
              'trailing newline.\ngot: ${rejectAll.toString()}');
    });

    test('fuzz: mismatched ours (unrelated content) returns null, never '
        'throws', () async {
      await forAllAsync(
        _genMismatchTriple(maxLines: 8),
        count: 25 * scale,
        seed: 0x5E27,
        describe: 'mismatch triple',
        check: (triple) async {
          final (a, t, c) = triple;
          final id = caseId++;
          await _writeAndCommit(repo, path, a, message: 'mismatch base $id');
          await repo.writeFile(path, t);
          final diffRes = await repo.git(['diff', '--', path]);
          expect(diffRes.exitCode, 0);
          final diffText = diffRes.stdout as String;
          if (diffText.isEmpty) return;

          // Only meaningful when the diff has context/deleted lines to
          // misalign against a DIFFERENT "ours" — a pure-addition diff
          // (e.g. from an empty `a`) never checks `c` at all, so "returns
          // null" would be vacuous there, not a real assertion.
          final touched = parseUnifiedDiff(diffText).where((l) =>
              l.kind == LineKind.deleted ||
              (l.kind == LineKind.context && l.lineNumOld != null));
          if (touched.isEmpty) return;
          // Also require every touched line to be non-trivial (non-empty)
          // content — an empty-vs-empty accidental match between two
          // independently random blobs is not astronomically rare the way
          // a real-text match is, and would make this a flaky assertion
          // rather than a meaningful one.
          if (touched.any((l) => l.text.length <= 1)) return;

          late final List<ConflictFile>? result;
          expect(() {
            result = reviewMergeFromPatch(diffText, {path: c});
          }, returnsNormally);
          expect(result, isNull,
              reason: 'expected null for unrelated "ours" content, got a '
                  'non-null result.\n--- a ---\n$a\n'
                  '--- c (supplied as ours) ---\n$c\n--- diff ---\n$diffText');
        },
      );
    });
  });

  // ---------------------------------------------------------------------------
  // LAW 6 — sliceDiffByFile partition/coverage
  // ---------------------------------------------------------------------------

  group('LAW 6 — sliceDiffByFile partition/coverage', () {
    late ScratchRepo repo;

    setUp(() async {
      repo = await ScratchRepo.create(name: 'slice_by_file');
    });

    tearDown(() async {
      await repo.dispose();
    });

    test(
        'fuzz: every hunk from a multi-file diff appears in exactly one '
        'per-file slice', () async {
      await forAllAsync(
        _genMultiFileChangeset(),
        count: 15 * scale,
        seed: 0x51CE,
        describe: 'multi-file changeset',
        check: (files) async {
          for (final entry in files) {
            await _writeAndCommit(repo, entry.$1, entry.$2, message: 'base');
          }
          for (final entry in files) {
            await repo.writeFile(entry.$1, entry.$3);
          }
          final diffRes = await repo.git(['diff']);
          expect(diffRes.exitCode, 0, reason: diffRes.stderr.toString());
          final diffText = diffRes.stdout as String;
          if (diffText.isEmpty) {
            return; // every file collided A==B this round.
          }
          try {
            final nameOnlyRaw = await repo.gitOk(['diff', '--name-only']);
            final nameOnly =
                nameOnlyRaw.split('\n').where((s) => s.isNotEmpty).toSet();
            final slices = sliceDiffByFile(diffText);
            expect(slices.keys.toSet(), equals(nameOnly),
                reason: 'sliceDiffByFile keys did not match the '
                    'changed-file set.\n--- diff ---\n$diffText');

            final fullHunks = parseDiffHunks(diffText);
            expect(fullHunks, isNotEmpty);
            for (final h in fullHunks) {
              final slice = slices[h.filePath];
              expect(slice, isNotNull,
                  reason: 'hunk for "${h.filePath}" missing from '
                      'sliceDiffByFile output.\n--- diff ---\n$diffText');
              expect(slice, contains(h.header),
                  reason: 'slice for "${h.filePath}" does not contain its '
                      'own hunk header.\n--- diff ---\n$diffText');
            }

            var sumPerSlice = 0;
            for (final path in slices.keys) {
              sumPerSlice += parseDiffHunksForFile(diffText, path).length;
            }
            expect(sumPerSlice, fullHunks.length,
                reason: 'hunk partition/coverage mismatch: '
                    'sum-of-slices=$sumPerSlice, full=${fullHunks.length}.\n'
                    '--- diff ---\n$diffText');
          } finally {
            // Settle the dirty tree — otherwise this case's uncommitted
            // files leak into the NEXT case's whole-repo `git diff` and
            // corrupt its partition/coverage assertions.
            await repo.gitOk(['add', '-A']);
            await repo.git(['commit', '-m', 'settle']);
          }
        },
      );
    },
        // Each case shells out to real git several times (write+add+commit
        // per file, plus diff/name-only/commit) across up to 4 files; at
        // MANIFOLD_FUZZ scales ≥5 (75+ cases) that reliably exceeds the
        // default 30s test timeout well before any assertion fails —
        // pre-existing IO cost, unrelated to B22-B25.
        timeout: const Timeout(Duration(minutes: 5)));
  });

  // ---------------------------------------------------------------------------
  // LAW 7 — git C-quoted paths
  // ---------------------------------------------------------------------------

  group('LAW 7 — git C-quoted paths recover the real filename', () {
    late ScratchRepo repo;

    setUp(() async {
      repo = await ScratchRepo.create(name: 'quotepath');
    });

    tearDown(() async {
      await repo.dispose();
    });

    // Two distinct bugs used to live in lib/backend/logos_hunks.dart's path
    // extraction, found by this law (both now fixed — see the GENUINE BUG
    // (FIXED) comments on the tests below):
    //  (a) non-ASCII names: git C-quotes them as octal per-byte escapes
    //      (e.g. "caf\303\251-file.txt" for the UTF-8 bytes of "café..."),
    //      and `_unCQuoteGitPath` now recombines the escaped bytes into
    //      one UTF-8 decode instead of decoding each octal escape as its
    //      own UTF-16 code unit.
    //  (b) space-containing names: git does not quote plain spaces (only
    //      backslash/doublequote/non-ASCII trigger quoting), so the
    //      header is un-quoted — `_pathFromDiffHeader` now recovers the
    //      path by exploiting that non-rename headers repeat it on both
    //      sides, instead of a naive `line.split(' ')[3]`.

    Future<void> caseFor(String name) async {
      try {
        await _writeAndCommit(repo, name, 'v1\n', message: 'add $name');
        await repo.writeFile(name, 'v1\nv2 added\n');
        final diffRes = await repo.git(['diff', '--', name]);
        expect(diffRes.exitCode, 0,
            reason: 'git diff failed for hostile name "$name": '
                '${diffRes.stderr}');
        final diffText = diffRes.stdout as String;
        expect(diffText, isNotEmpty,
            reason: 'expected a real diff for "$name"');

        final hunksForFile = parseDiffHunksForFile(diffText, name);
        final allHunks = parseDiffHunks(diffText);
        final recoveredEverywhere = hunksForFile.isNotEmpty &&
            allHunks.any((h) => h.filePath == name);
        if (!recoveredEverywhere) {
          fail('failed to recover path "$name" '
              'from its diff header via un-C-quoting.\n'
              'parseDiffHunksForFile: ${hunksForFile.length} hunks, '
              'parseDiffHunks paths: '
              '${allHunks.map((h) => h.filePath).toSet()}\n'
              '--- diff ---\n$diffText');
        }
        expect(hunksForFile.length, greaterThanOrEqualTo(1));

        // Canonical parser parity (git_diff_paths.dart): the app's other
        // diff consumer — parseUnifiedDiff/sliceDiffByFile in
        // features/diff/diff_models.dart — must decode the SAME quoted/
        // C-quoted path as logos_hunks' hunk parser above. Before the
        // git_diff_paths.dart extraction these two parsers had
        // independent (and differently buggy) header-decoding logic; this
        // is the regression guard that they can no longer drift.
        final parsedLines = parseUnifiedDiff(diffText);
        final decodedFilePaths =
            parsedLines.map((l) => l.filePath).whereType<String>().toSet();
        expect(decodedFilePaths, contains(name),
            reason: 'parseUnifiedDiff failed to decode path "$name" from '
                'its diff header.\ndecoded paths: $decodedFilePaths\n'
                '--- diff ---\n$diffText');

        final slices = sliceDiffByFile(diffText);
        expect(slices.keys, contains(name),
            reason: 'sliceDiffByFile failed to decode path "$name" from '
                'its diff header.\ndecoded keys: ${slices.keys}\n'
                '--- diff ---\n$diffText');
      } finally {
        // Settle this case's dirty file before the NEXT fuzz case (which
        // reuses the SAME repo/working tree) runs — otherwise a later
        // case's `_writeAndCommit` can find THIS file still
        // dirty-but-unstaged and get "no changes added to commit" instead
        // of a clean baseline.
        final staged = await repo.git(['add', '-A']);
        if (staged.exitCode == 0) {
          final settle = await repo.git(['commit', '-m', 'settle $name']);
          if (settle.exitCode != 0) {
            final combined = '${settle.stdout}${settle.stderr}';
            expect(_isBenignNoCommitMessage(combined), isTrue,
                reason: combined);
          }
        }
      }
    }

    test(
        // GENUINE BUG (FIXED): git C-quotes non-ASCII paths as per-byte
        // octal escapes; _unCQuoteGitPath (lib/backend/logos_hunks.dart)
        // used to decode each escaped byte as its own UTF-16 code unit
        // instead of recombining the bytes and UTF-8-decoding, recovering
        // mojibake ("cafeÃ©-file.txt") instead of the real name
        // ("café-file.txt"). Fixed by accumulating consecutive escape
        // bytes into a byte buffer and running ONE utf8DecodeExact per
        // contiguous escape run.
        'unicode filename (built via fromCharCode — no raw non-ASCII '
        'literals in source)', () async {
      final cafe = 'cafe${String.fromCharCode(0xE9)}-file.txt'; // "café-file.txt"
      await caseFor(cafe);
    });

    test(
        // GENUINE BUG (FIXED): same root cause as the café case — see
        // above.
        'CJK filename', () async {
      final cjk = '${String.fromCharCodes([0x6587, 0x4EF6])}.txt'; // "文件.txt"
      await caseFor(cjk);
    });

    test(
        // GENUINE BUG (FIXED): git does not quote a plain space, so the
        // header is un-quoted — but _pathFromDiffHeader (logos_hunks.dart)
        // used to recover the path via line.split(' ')[3], which shatters
        // on the filename's own internal spaces, recovering just "space"
        // instead of "has space in it.txt". Fixed by exploiting that
        // non-rename headers repeat the identical path on both sides:
        // find the space that splits the remainder into `a/P` and `b/P`
        // for the same P.
        'filename with a space', () async {
      await caseFor('has space in it.txt');
    });

    test(
        'fuzz: filesystem-legal hostile filenames recover their path',
        () async {
      await forAllAsync(
        _genHostileFileName(),
        count: 15 * scale,
        seed: 0x9A73,
        describe: 'hostile filename',
        check: (name) => caseFor(name),
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Generators specific to this file
// ---------------------------------------------------------------------------

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A guaranteed-CRLF A/B pair: every line (interior AND final) ends in
/// `\r\n`, and exactly one line is mutated so there's always a real,
/// localized diff — no reliance on genMultilineText's probabilistic mix to
/// land on CRLF (this generator forces it, for a stronger, more targeted
/// sweep than LAW 1's generic one). A and B share the same trailing-newline
/// shape so this generator isolates the CRLF question from the
/// no-trailing-newline question (that's LAW 2's job).
Gen<(String, String)> _genCrlfPair({int maxLines = 8}) {
  final body = genAscii(maxLen: 20);
  return (rng) {
    final lineCount = rng.intBetween(1, maxLines);
    final aLines = <String>[for (var i = 0; i < lineCount; i++) body(rng)];
    final bLines = List<String>.of(aLines);
    final mutateIdx = rng.nextInt(lineCount);
    bLines[mutateIdx] = '${bLines[mutateIdx]} EDITED';
    final hasTrailingNewline = rng.nextBool();
    String render(List<String> ls) {
      final buf = StringBuffer();
      for (var i = 0; i < ls.length; i++) {
        buf.write(ls[i]);
        if (i < ls.length - 1 || hasTrailingNewline) buf.write('\r\n');
      }
      return buf.toString();
    }

    return (render(aLines), render(bLines));
  };
}

/// Drops exactly one trailing `'\n'`, if present — NOT a `'\r\n'` pair,
/// since a trailing `'\r'` is content (see genMultilineText's own doc
/// comment) and must survive. See [_genConflictScenario] for why this
/// normalization is needed.
String _dropTrailingLf(String s) => s.endsWith('\n') ? s.substring(0, s.length - 1) : s;

/// A three-way conflict document: `n` blocks, each with independently
/// fuzzed ours/theirs (and sometimes base) text separated by simple,
/// collision-proof clean segments. Returns the constructed document plus
/// enough bookkeeping (expected per-block ours/theirs text and a resolution
/// choice) to check the parse + resolve + rebuild round trip without
/// re-deriving buildResult()'s own algorithm (which would be circular).
typedef _ConflictScenario = ({
  String doc,
  List<String> oursTexts,
  List<String> theirsTexts,
  List<bool> resolveOurs,
});

Gen<_ConflictScenario> _genConflictScenario({int maxBlocks = 4}) {
  final blockText = genMultilineText(maxLines: 4);
  final filler = genAscii(maxLen: 12);
  return (rng) {
    final n = rng.intBetween(1, maxBlocks);
    final oursTexts = <String>[];
    final theirsTexts = <String>[];
    final resolveOurs = <bool>[];
    final buf = StringBuffer();
    for (var i = 0; i < n; i++) {
      buf.write('clean seg $i: ${filler(rng)}\n');
      // A conflict block's captured text NEVER includes a trailing
      // newline — the marker format always consumes the last '\n' as the
      // separator before the next marker line (parseConflictFile has no
      // way to tell "this block's content happened to end in \n, which
      // was then reused as the separator" apart from "this block's
      // content never had one" — they produce identical bytes). Dropping
      // one trailing LF up front (rather than the generator's raw draw)
      // keeps the recorded expected value consistent with what the
      // parser can actually recover, instead of asserting an ambiguity
      // the format itself can't represent.
      final ours = _dropTrailingLf(blockText(rng));
      final theirs = _dropTrailingLf(blockText(rng));
      oursTexts.add(ours);
      theirsTexts.add(theirs);
      resolveOurs.add(rng.nextBool());

      buf.write('<<<<<<< ours\n');
      buf.write(ours);
      buf.write('\n');
      if (rng.nextBool()) {
        final base = _dropTrailingLf(blockText(rng));
        buf.write('||||||| base\n');
        buf.write(base);
        buf.write('\n');
      }
      buf.write('=======\n');
      buf.write(theirs);
      buf.write('\n');
      buf.write('>>>>>>> theirs\n');
    }
    buf.write('clean tail: ${filler(rng)}\n');
    return (
      doc: buf.toString(),
      oursTexts: oursTexts,
      theirsTexts: theirsTexts,
      resolveOurs: resolveOurs,
    );
  };
}

typedef _TruncatedScenario = ({String truncated, int originalLength});

Gen<_TruncatedScenario> _genTruncatedConflict({int maxBlocks = 3}) {
  final scenario = _genConflictScenario(maxBlocks: maxBlocks);
  return (rng) {
    final s = scenario(rng);
    final cut = s.doc.isEmpty ? 0 : rng.nextInt(s.doc.length + 1);
    return (truncated: s.doc.substring(0, cut), originalLength: s.doc.length);
  };
}

Gen<(String, String, String)> _genMismatchTriple({int maxLines = 8}) {
  final g = genMultilineText(maxLines: maxLines);
  return (rng) => (g(rng), g(rng), g(rng));
}

/// `(path, a, b)` triples for a multi-file changeset — 2 to 4 files, each
/// independently fuzzed.
Gen<List<(String, String, String)>> _genMultiFileChangeset({
  int minFiles = 2,
  int maxFiles = 4,
}) {
  final content = genMultilineText(maxLines: 6);
  return (rng) {
    final n = rng.intBetween(minFiles, maxFiles);
    return [
      for (var i = 0; i < n; i++) ('file_$i.txt', content(rng), content(rng)),
    ];
  };
}

/// Names that are safe to actually create as a single Windows filename
/// component — filters out '.', '..', reserved dotfiles, and
/// trailing-dot/space names Windows silently mangles (a real filesystem
/// quirk, not something a diff-path-recovery test should be flaky over).
bool _isSafeAsSingleFileName(String name) {
  if (name.isEmpty) return false;
  const reserved = {'.', '..', '.git', '.gitignore', 'node_modules'};
  if (reserved.contains(name)) return false;
  if (name.endsWith('.') || name.endsWith(' ')) return false;
  return true;
}

/// Filesystem-legal hostile filenames drawn from genRelPath's own curated
/// segment pool (unicode/space/dotted names already vetted as safe cross-
/// platform path segments) — collapsed to a single path component so this
/// stays a filename-quoting test, not a nested-directory test.
Gen<String> _genHostileFileName() {
  final base = genRelPath();
  return (rng) {
    for (var attempt = 0; attempt < 20; attempt++) {
      final raw = base(rng);
      final parts =
          raw.split(RegExp(r'[\\/]+')).where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) continue;
      final name = parts.last;
      if (_isSafeAsSingleFileName(name)) return name;
    }
    return 'fallback_hostile_file.txt';
  };
}
