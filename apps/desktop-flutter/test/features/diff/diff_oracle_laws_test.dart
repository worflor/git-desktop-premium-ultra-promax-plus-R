// First-principles laws of the diff viewer checked against the ONE oracle
// that cannot be wrong about what a diff is: real `git` itself.
//
// The in-repo `diff_parser_agreement_test.dart` cross-checks the app's two
// parsers against EACH OTHER — valuable, but blind to a bug both share. These
// laws instead pin the parser to git's own ground truth and to the file bytes
// on disk, over a generator (`genDiffScenario`) that produces `before`/`after`
// pairs related by a realistic edit, seeded with the line shapes that mimic
// diff structure (`+`/`-`/`@@`/`\`/`diff --git`/`+++`/`---`/`index ` as
// CONTENT). Each case commits `before`, writes `after`, and asks git for the
// real diff.
//
// What "diff" MEANS, made executable:
//  (b) STATS: the parser's add/delete counts equal `git diff --numstat`.
//  (a) RECONSTRUCTION: the viewer's own `DiffDocument` model decodes back to
//      the exact bytes of both file versions (old side and new side).
//  (f) COHERENCE: within each hunk the canonical parser's per-line numbering
//      starts at the `@@` header's declared start and stays contiguous.
//  (e) PARTIAL STAGING: an ARBITRARY subset of staged lines always builds a
//      patch git accepts — never "patch does not apply" (the field-bug class).
//  (i) MOVE DETECTION: a verbatim relocated block is recognized as a move,
//      and a plain insertion is never a false move.
//
// Deliberately NOT re-tested here (already covered, per the suite audit):
// full-diff staged-apply round-trip and CRLF byte-exactness live in
// test/fuzz/patch_diff_crlf_roundtrip_test.dart; this file complements them.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart' show applyFileStaging;
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/edit_units.dart'
    show buildEditUnits, EditKind, stripDiffLineSign;
import 'package:git_desktop/features/diff/patch_engine.dart';

import '../../support/gen_diff.dart';
import '../../support/prop.dart';
import '../../support/scratch_repo.dart';

int get _scale => fuzzScale();

/// The file content a parsed body line carries, marker removed.
String _contentOf(ParsedLine l) {
  switch (l.kind) {
    case LineKind.added:
    case LineKind.deleted:
      return stripDiffLineSign(l.text);
    case LineKind.context:
      return l.text.startsWith(' ') ? l.text.substring(1) : l.text;
    case LineKind.hunk:
    case LineKind.meta:
      return l.text;
  }
}

/// Commits [oldText] at [path], writes [newText], and returns `git [diffArgs]
/// -- path`. The file exists in HEAD as [oldText] afterward, which is what the
/// staging patch applies against.
Future<String> _diffAfterEdit(
  ScratchRepo repo,
  String path,
  String oldText,
  String newText, {
  List<String> diffArgs = const ['diff'],
}) async {
  await repo.writeFile(path, oldText);
  await repo.git(['add', '--', path]);
  await repo.git(['commit', '-q', '-m', 'base', '--allow-empty']);
  await repo.writeFile(path, newText);
  final r = await repo.git([...diffArgs, '--', path]);
  return r.stdout as String;
}

final _hunkHeaderRe = RegExp(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parser counts equal `git diff --numstat` (b)', () {
    test('adds/dels agree with git across realistic edits', () async {
      final repo = await ScratchRepo.create(name: 'diff_numstat');
      addTearDown(repo.dispose);
      var id = 0;
      await forAllAsync<DiffScenario>(
        genDiffScenario(maxLines: 20),
        count: 15 * _scale,
        seed: 0x0B57A75,
        describe: 'stats vs numstat',
        requireCoverage: {'nonempty': 0.4},
        check: (sc) async {
          if (sc.oldText == sc.newText) return;
          final path = 'n/f${id++}.txt';
          await repo.writeFile(path, sc.oldText);
          await repo.git(['add', '--', path]);
          await repo.git(['commit', '-q', '-m', 'base', '--allow-empty']);
          await repo.writeFile(path, sc.newText);

          final numstat =
              (await repo.git(['diff', '--numstat', '--', path])).stdout
                  as String;
          final diff = (await repo.git(['diff', '--', path])).stdout as String;
          if (diff.isEmpty) return;
          final ns = numstat.trim();
          // A numstat line git flags as binary (`-\t-\t...`) is the binary
          // path's job, not this parser's — skip it.
          if (ns.isEmpty || ns.startsWith('-')) return;
          collect('nonempty');

          final cols = ns.split('\n').first.split('\t');
          final gitAdds = int.parse(cols[0]);
          final gitDels = int.parse(cols[1]);

          final lines = parseUnifiedDiff(diff);
          final adds = lines.where((l) => l.kind == LineKind.added).length;
          final dels = lines.where((l) => l.kind == LineKind.deleted).length;
          expect((adds, dels), (gitAdds, gitDels),
              reason: 'parser add/del counts disagree with git numstat.\n'
                  'A content line that mimics diff structure '
                  '(`@@`/`\\`/`diff --git`/`+++`) was likely mis-read as a '
                  'header.\n--- diff ---\n$diff');
        },
      );
    });
  });

  group('viewer model reconstructs both file versions byte-exact (a)', () {
    test('old side == before, new side == after, from DiffDocument.lines',
        () async {
      final repo = await ScratchRepo.create(name: 'diff_reconstruct');
      addTearDown(repo.dispose);
      var id = 0;
      await forAllAsync<DiffScenario>(
        // Clean scenario (LF, no ambiguous blank lines) so every body line is
        // unambiguously `marker + content`. Full context (`-U1000000`) puts the
        // whole file in one hunk, making reconstruction total.
        genCleanDiffScenario(maxLines: 20),
        count: 15 * _scale,
        seed: 0x2EC0,
        describe: 'reconstruction',
        requireCoverage: {'nonempty': 0.4},
        check: (sc) async {
          if (sc.oldText == sc.newText) return;
          final path = 'r/f${id++}.txt';
          final diff = await _diffAfterEdit(repo, path, sc.oldText, sc.newText,
              diffArgs: const ['diff', '-U1000000']);
          if (diff.isEmpty) return;
          collect('nonempty');

          final doc = DiffDocument.fromRawContent(
            rawContent: diff,
            pathHint: path,
            trimLeadingMeta: true,
          );
          final oldSide = [
            for (final l in doc.lines)
              if (l.kind == LineKind.deleted || l.kind == LineKind.context)
                _contentOf(l),
          ];
          final newSide = [
            for (final l in doc.lines)
              if (l.kind == LineKind.added || l.kind == LineKind.context)
                _contentOf(l),
          ];
          expect(oldSide, sc.oldLines,
              reason: 'old-side reconstruction diverged from `before`.\n$diff');
          expect(newSide, sc.newLines,
              reason: 'new-side reconstruction diverged from `after`.\n$diff');
        },
      );
    });
  });

  group('per-hunk numbering starts at the @@ header and is contiguous (f)',
      () {
    test('canonical parser line numbers match the header, no skips', () async {
      final repo = await ScratchRepo.create(name: 'diff_coherence');
      addTearDown(repo.dispose);
      var id = 0;
      await forAllAsync<DiffScenario>(
        genDiffScenario(maxLines: 20),
        count: 12 * _scale,
        seed: 0xC0FE,
        describe: 'hunk coherence',
        check: (sc) async {
          if (sc.oldText == sc.newText) return;
          final path = 'h/f${id++}.txt';
          final diff = await _diffAfterEdit(repo, path, sc.oldText, sc.newText);
          if (diff.isEmpty) return;
          final lines = parseUnifiedDiff(diff);

          // Walk hunk by hunk. At each `@@` header capture the declared old/new
          // starts; then the first numbered old-side (deleted/context) line
          // must equal oldStart, the first new-side (added/context) newStart,
          // and each side's numbers must increase by exactly 1.
          int? expectOld, expectNew;
          for (final l in lines) {
            if (l.kind == LineKind.hunk) {
              final m = _hunkHeaderRe.firstMatch(l.text);
              if (m == null) continue;
              expectOld = int.parse(m.group(1)!);
              expectNew = int.parse(m.group(3)!);
              continue;
            }
            if (l.hunkIndex < 0) continue;
            if (l.lineNumOld != null) {
              expect(l.lineNumOld, expectOld,
                  reason: 'old-side number broke contiguity at ${l.text}\n'
                      '$diff');
              expectOld = expectOld! + 1;
            }
            if (l.lineNumNew != null) {
              expect(l.lineNumNew, expectNew,
                  reason: 'new-side number broke contiguity at ${l.text}\n'
                      '$diff');
              expectNew = expectNew! + 1;
            }
          }
        },
      );
    });
  });

  group('arbitrary partial staging always builds a git-acceptable patch (e)',
      () {
    test('no staged subset ever produces "patch does not apply"', () async {
      final repo = await ScratchRepo.create(name: 'diff_partial_stage');
      addTearDown(repo.dispose);
      var id = 0;
      await forAllAsync<(DiffScenario, int)>(
        // A salt drawn alongside the scenario picks WHICH changed lines are
        // staged, so the subset varies independently of the edit shape.
        (rng) => (genDiffScenario(maxLines: 16)(rng), rng.intBetween(0, 1 << 20)),
        count: 15 * _scale,
        seed: 0x5AB5E7,
        describe: 'partial staging',
        requireCoverage: {'staged-some': 0.3},
        check: (pair) async {
          final (sc, salt) = pair;
          if (sc.oldText == sc.newText) return;
          final path = 'p/f${id++}.txt';
          final diff = await _diffAfterEdit(repo, path, sc.oldText, sc.newText);
          if (diff.isEmpty) return;

          final lines = parseUnifiedDiff(diff);
          var stagedAny = false;
          final staged = [
            for (final l in lines)
              if ((l.kind == LineKind.added || l.kind == LineKind.deleted) &&
                  ((l.fastKey ^ salt) & 1) == 0)
                () {
                  stagedAny = true;
                  return l.copyWith(isStaged: true);
                }()
              else
                l,
          ];
          if (stagedAny) collect('staged-some');

          final patch = PatchEngine.buildStagedPatch(path, staged);
          final r = await applyFileStaging(repo.dir.path, path, patch);
          expect(r.ok, isTrue,
              reason: 'git rejected a partially-staged patch — the exact '
                  '"Partial stage failed: patch does not apply" incident '
                  'class.\nsalt=$salt\n--- diff ---\n$diff\n--- patch ---\n'
                  '$patch\n--- git said ---\n${r.error}');
        },
      );
    });
  });

  group('move detection (i)', () {
    // buildEditUnits(detectMoves: true) pairs a deleted block with an
    // identical inserted block elsewhere in the file as a single MOVE.
    test('a verbatim relocated block is recognized as a move', () async {
      final repo = await ScratchRepo.create(name: 'diff_move');
      addTearDown(repo.dispose);
      // A distinctive multi-line block lifted from the top to the bottom, with
      // unrelated filler in between so the endpoints are non-adjacent (the
      // fuzzy pass deliberately ignores adjacent del/insert as plain replace).
      const block = ['MOVE_ALPHA_1', 'MOVE_BETA_2', 'MOVE_GAMMA_3'];
      final filler = [for (var i = 0; i < 6; i++) 'filler line $i'];
      final oldText = '${[...block, ...filler].join('\n')}\n';
      final newText = '${[...filler, ...block].join('\n')}\n';

      final diff =
          await _diffAfterEdit(repo, 'move.txt', oldText, newText);
      expect(diff, isNotEmpty);
      final units = buildEditUnits(parseUnifiedDiff(diff), detectMoves: true);
      expect(units.any((u) => u.kind == EditKind.move), isTrue,
          reason: 'a verbatim block relocation should surface as a move '
              'unit.\n--- diff ---\n$diff');
    });

    test('a plain insertion is never reported as a move', () async {
      final repo = await ScratchRepo.create(name: 'diff_nomove');
      addTearDown(repo.dispose);
      // New lines with no matching deletion anywhere — there is nothing to
      // have "moved", so the move pass must not invent one.
      const oldText = 'keep one\nkeep two\nkeep three\n';
      const newText =
          'keep one\nBRAND_NEW_A\nkeep two\nBRAND_NEW_B\nkeep three\n';
      final diff =
          await _diffAfterEdit(repo, 'nomove.txt', oldText, newText);
      expect(diff, isNotEmpty);
      final units = buildEditUnits(parseUnifiedDiff(diff), detectMoves: true);
      expect(units.any((u) => u.kind == EditKind.move), isFalse,
          reason: 'pure insertions have no counterpart deletion; no move '
              'unit should be fabricated.\n--- diff ---\n$diff');
    });

    test('a relocated block with a minimal rename is a FUZZY move', () async {
      // Regression guard for a bug found by profiling: the fuzzy pass shipped
      // DEAD — delete units never carried a SimHash, so its delete-candidate
      // list was always empty and no rename-move was ever detected (while it
      // still burned ~330ms forcing SimHash on every insert). This pins the
      // resurrected behavior: a block moved AND lightly renamed pairs as a
      // move, not as unrelated delete+insert. If SimHash sourcing regresses,
      // this drops back to zero moves and fails.
      final repo = await ScratchRepo.create(name: 'diff_fuzzy_move');
      addTearDown(repo.dispose);
      final block = [
        for (final w in ['alpha', 'beta', 'gamma'])
          'const ${w}HandlerFunctionImplementationDetail = 100;',
      ];
      // Same block relocated below filler, last digit changed (Hamming well
      // under the fuzzy threshold — the exact block-move pass can't match it).
      final moved = [
        for (final w in ['alpha', 'beta', 'gamma'])
          'const ${w}HandlerFunctionImplementationDetail = 101;',
      ];
      final filler = [for (var i = 0; i < 6; i++) 'filler row number $i;'];
      final oldText = '${[...block, ...filler].join('\n')}\n';
      final newText = '${[...filler, ...moved].join('\n')}\n';

      final diff = await _diffAfterEdit(repo, 'fuzzy.txt', oldText, newText);
      expect(diff, isNotEmpty);
      final units = buildEditUnits(parseUnifiedDiff(diff), detectMoves: true);
      expect(units.any((u) => u.kind == EditKind.move), isTrue,
          reason: 'the renamed relocated block should be detected as a fuzzy '
              'move — if this is zero, the fuzzy pass has gone dead again.\n'
              '--- diff ---\n$diff');
    });
  });
}
