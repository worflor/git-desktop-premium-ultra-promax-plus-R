// First-principles laws of the diff MODEL — the parser and the derived
// per-line state — checked as pure properties with no git in the loop.
//
// "What is a diff, structurally?" A unified diff is a total, deterministic
// decoding of a byte stream into a sequence of classified lines, plus a set
// of pure functions derived from each line (its search signatures, its stable
// identity). None of that needs a repository to be true, so none of it is
// tested with one here — these run sync at full `forAll` count. The git
// *oracle* laws (reconstruction against real files, staging round-trips) live
// in diff_oracle_laws_test.dart.
//
// The laws:
//  1. Totality + determinism + idempotence: parseUnifiedDiff never throws on
//     ANY byte sequence, and is a pure function (same input -> same output),
//     including on input that is not a diff at all.
//  2. Search pre-filter SOUNDNESS: the SWAR char/bigram bloom filters that
//     gate substring search must never reject a line that genuinely contains
//     the query. A false rejection silently hides a real search hit — the
//     worst kind of search bug because nothing surfaces it.
//  3. Identity stability: a line's fastKey is invariant under staging toggles
//     (the whole reason it exists) and is a pure function of its structural
//     inputs; the lazy signature cache is idempotent.
//  4. Lean-gate content conservation: above kLeanDiffLineThreshold the viewer
//     drops ANALYSIS (move detection, the unit index) but never CONTENT — the
//     reconstructed lines are byte-identical to the source. "No arbitrary cap
//     ever eats a line."

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/edit_units.dart'
    show buildEditUnits, stripDiffLineSign, EditKind;
import 'package:git_desktop/features/diff/patch_engine.dart';

import '../../support/gen.dart';
import '../../support/prop.dart';

int get _scale => fuzzScale();

/// The file content a parsed body line carries, with its diff marker removed:
/// `+`/`-` via [stripDiffLineSign], and the leading space of a context line.
/// For a clean (space/`+`/`-`-prefixed) unified-diff body this recovers the
/// exact source line.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parser is a total, deterministic function', () {
    // Feed it things that are NOT diffs (hostile unicode, arbitrary multiline
    // text) as well as things that are. A parser is only safe to point at
    // untrusted `git`/`gh` output if it cannot throw on any of it.
    final anyText = genOneOf<String>([
      genUnicodeHostile(maxLen: 40),
      genMultilineText(maxLines: 16),
      genAscii(maxLen: 60),
    ]);

    test('never throws, and same bytes -> same classified lines', () {
      forAll<String>(
        anyText,
        count: 400 * _scale,
        seed: 0x0D1F,
        describe: 'parser totality',
        check: (text) {
          final a = parseUnifiedDiff(text);
          final b = parseUnifiedDiff(text);
          // Determinism: two parses agree line-for-line on the observable
          // model (kind + text + numbering + hunk membership).
          expect(a.length, b.length);
          for (var i = 0; i < a.length; i++) {
            expect(a[i].kind, b[i].kind);
            expect(a[i].text, b[i].text);
            expect(a[i].lineNumOld, b[i].lineNumOld);
            expect(a[i].lineNumNew, b[i].lineNumNew);
            expect(a[i].hunkIndex, b[i].hunkIndex);
          }
        },
      );
    });

    test('a NUL byte in hunk-body content is carried through, not truncated',
        () {
      // git treats a NUL-containing file as binary and never emits its
      // content as a text diff — so the ONLY way a NUL reaches this parser is
      // a hand-forged or non-git diff. It still must survive: NUL is a C-string
      // and `git diff -z` field terminator, the classic silent-truncation
      // byte. Build a diff whose added line embeds a NUL and demand the parser
      // (and the staging patch builder) preserve every byte of it.
      final nul = String.fromCharCode(0);
      final raw = 'diff --git a/f b/f\n'
          '--- a/f\n'
          '+++ b/f\n'
          '@@ -1,1 +1,1 @@\n'
          '-before${nul}old\n'
          '+after${nul}new\n';
      final lines = parseUnifiedDiff(raw);
      final added = lines.firstWhere((l) => l.kind == LineKind.added);
      final deleted = lines.firstWhere((l) => l.kind == LineKind.deleted);
      expect(added.text, '+after${nul}new');
      expect(deleted.text, '-before${nul}old');
      // The staged patch (whole line staged) must re-emit the NUL verbatim.
      final staged = [
        for (final l in lines)
          l.kind == LineKind.added || l.kind == LineKind.deleted
              ? l.copyWith(isStaged: true)
              : l,
      ];
      final patch = PatchEngine.buildStagedPatch('f', staged);
      expect(patch.contains('after${nul}new'), isTrue,
          reason: 'NUL byte dropped from the reconstructed patch');
    });
  });

  group('search pre-filter soundness (no false negatives)', () {
    // (line, query) where the query is, half the time, a genuine substring of
    // the line — so the true-match branch is exercised often, not by luck.
    final lineGen = genOneOf<String>([
      genAscii(maxLen: 48),
      genUnicodeHostile(maxLen: 24),
    ]);
    Gen<(String, String)> lineQuery() => (rng) {
          final line = lineGen(rng);
          if (line.isNotEmpty && rng.nextBool()) {
            final start = rng.intBetween(0, line.length - 1);
            final end = rng.intBetween(start + 1, line.length);
            return (line, line.substring(start, end));
          }
          return (line, genAscii(maxLen: 6)(rng));
        };

    test('char + bigram bitmaps never reject a line that contains the query',
        () {
      forAll<(String, String)>(
        lineQuery(),
        count: 400 * _scale,
        seed: 0x5EA4,
        describe: 'search filter soundness',
        requireCoverage: {'true-match': 0.15},
        check: ((String, String) pair) {
          final (line, query) = pair;
          if (query.isEmpty) return;
          final lower = line.toLowerCase();
          final q = query.toLowerCase();
          if (!lower.contains(q)) return; // soundness is about TRUE matches
          collect('true-match');

          final pl = ParsedLine(text: line, kind: LineKind.context);
          final qc = ParsedLine.queryCharBits(q);
          final qb = ParsedLine.queryBigramBits(q);

          // The pre-filter's accept condition is `(bits & q) == q`. If the
          // line really contains the query it MUST pass both stages, or the
          // search box would drop a hit that is right there in the text.
          expect(pl.charBits & qc, qc,
              reason: 'charBits filter rejected a real match\n'
                  'line=${line.codeUnits}\nquery=${query.codeUnits}');
          expect(pl.bigramBits & qb, qb,
              reason: 'bigramBits filter rejected a real match\n'
                  'line=${line.codeUnits}\nquery=${query.codeUnits}');
        },
      );
    });
  });

  group('line identity (fastKey) laws', () {
    Gen<ParsedLine> aLine() => (rng) {
          final kind = rng.pick(const [
            LineKind.added,
            LineKind.deleted,
            LineKind.context,
          ]);
          return ParsedLine(
            text: genOneOf<String>([
              genAscii(maxLen: 30),
              genUnicodeHostile(maxLen: 16),
            ])(rng),
            kind: kind,
            hunkIndex: rng.intBetween(0, 5),
            lineNumOld: kind == LineKind.added ? null : rng.intBetween(1, 5000),
            lineNumNew:
                kind == LineKind.deleted ? null : rng.intBetween(1, 5000),
          );
        };

    test('fastKey is invariant under staging toggles and is pure', () {
      forAll<ParsedLine>(
        aLine(),
        count: 300 * _scale,
        seed: 0xFA57,
        describe: 'fastKey stability',
        check: (line) {
          // Staging must not move a line's identity — it is what keeps a
          // ValueKey stable and a selection alive across a stage/unstage.
          expect(line.copyWith(isStaged: true).fastKey, line.fastKey);
          expect(line.copyWith(isStaged: false).fastKey, line.fastKey);

          // Purity: an independently constructed twin with the same
          // structural inputs hashes identically.
          final twin = ParsedLine(
            text: line.text,
            kind: line.kind,
            hunkIndex: line.hunkIndex,
            lineNumOld: line.lineNumOld,
            lineNumNew: line.lineNumNew,
          );
          expect(twin.fastKey, line.fastKey);

          // The lazy signature cache is idempotent — repeated reads are equal.
          expect(line.charBits, line.charBits);
          expect(line.bigramBits, line.bigramBits);
          expect(line.simHash, line.simHash);
          expect(line.lowerText, line.text.toLowerCase());
        },
      );
    });
  });

  group('lean gate conserves content, not just line count', () {
    // The lean gate (kLeanDiffLineThreshold) is the ONLY size-conditioned
    // branch in the pipeline. The user's contract is that it may drop
    // ANALYSIS but must never drop, truncate, or reorder a line of the diff.
    // Build a rewrite whose changed-line count straddles the threshold, then
    // reconstruct the new and old sides from the parsed model and demand they
    // equal the source byte-for-byte.
    for (final over in [false, true]) {
      final changed =
          over ? kLeanDiffLineThreshold + 5000 : kLeanDiffLineThreshold ~/ 4;
      test('${over ? 'past' : 'under'} the threshold: every line survives '
          'reconstruction', () {
        final oldLines = [for (var i = 0; i < changed; i++) 'row $i old'];
        final newLines = [for (var i = 0; i < changed; i++) 'row $i NEW'];
        final b = StringBuffer()
          ..writeln('diff --git a/f b/f')
          ..writeln('--- a/f')
          ..writeln('+++ b/f')
          ..writeln('@@ -1,$changed +1,$changed @@');
        for (final l in oldLines) {
          b.writeln('-$l');
        }
        for (final l in newLines) {
          b.writeln('+$l');
        }
        final doc = DiffDocument.fromRawContent(
          rawContent: b.toString(),
          pathHint: 'f',
          trimLeadingMeta: true,
        );

        // Analysis degrades past the threshold, is full under it — but that is
        // the ONLY difference the gate is allowed to make.
        expect(doc.unitByFastKey.isEmpty, over,
            reason: over
                ? 'lean gate must skip the unit index'
                : 'under threshold keeps full analysis');

        final reconstructedOld = [
          for (final l in doc.lines)
            if (l.kind == LineKind.deleted || l.kind == LineKind.context)
              _contentOf(l),
        ];
        final reconstructedNew = [
          for (final l in doc.lines)
            if (l.kind == LineKind.added || l.kind == LineKind.context)
              _contentOf(l),
        ];
        expect(reconstructedOld, oldLines,
            reason: 'a deleted/context line was dropped or altered');
        expect(reconstructedNew, newLines,
            reason: 'an added/context line was dropped or altered');
      });
    }
  });

  group('edit-unit derivation stays near-linear on a hostile shape', () {
    // The fuzzy move pass (edit_units.dart `_detectFuzzyMoves`) is a nested
    // scan over the delete/insert units the exact pass leaves behind, and its
    // own doc comment ASSUMES "remaining counts are modest (<100 each)". A big
    // deletion region facing a big, UNRELATED insertion region violates that
    // assumption outright — nothing matches (so exact pairing consumes none)
    // and nothing fuses (the two regions are non-adjacent) — so every delete
    // and every insert survives into the pass. It is fine today (bounded in
    // practice), and this guard keeps it that way: a future edit that lets the
    // pass become genuinely O(deletes x inserts) turns 4x the input into ~16x
    // the time, which this catches.
    String scattered(int n) {
      final b = StringBuffer()
        ..writeln('diff --git a/f b/f')
        ..writeln('--- a/f')
        ..writeln('+++ b/f')
        ..writeln('@@ -1,${n + 1} +1,1 @@');
      for (var i = 0; i < n; i++) {
        b.writeln('-deleted alpha content unique number $i here');
      }
      b
        ..writeln(' shared context anchor line')
        ..writeln('@@ -${n + 2},1 +2,${n + 1} @@')
        ..writeln(' another shared context anchor');
      for (var i = 0; i < n; i++) {
        b.writeln('+inserted omega content distinct number $i there');
      }
      return b.toString();
    }

    // Best of a few runs to shed GC/scheduler noise — we want the asymptote,
    // not a one-off pause.
    int msFor(int n) {
      final lines = parseUnifiedDiff(scattered(n));
      var best = 1 << 30;
      for (var r = 0; r < 3; r++) {
        final sw = Stopwatch()..start();
        buildEditUnits(lines, detectMoves: true);
        sw.stop();
        if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
      }
      return best;
    }

    test('4x the changes costs nothing like the 16x a quadratic pass would',
        () {
      final small = msFor(25000);
      final large = msFor(100000);
      // Linear predicts ~4x; a revived quadratic pass predicts ~16x. Allow a
      // generous 8x, with a floor so noise between two small timings on a fast
      // machine can never trip it.
      final ceiling = (small * 8).clamp(2500, 1 << 30);
      expect(large, lessThan(ceiling),
          reason: 'buildEditUnits scaled worse than linear on the hostile '
              'shape: 25k=${small}ms 100k=${large}ms — the fuzzy move pass '
              'likely regressed to O(deletes x inserts).');
      // Absolute backstop: a true quadratic pass is tens of seconds at 100k.
      expect(large, lessThan(8000),
          reason: 'buildEditUnits on 100k unrelated changes took ${large}ms');
    });

    // Regression for a real O(n²) a code review caught: a block of IDENTICAL
    // lines relocated (many candidates in one hash bucket) made the EXACT move
    // pass scan every candidate and extend each over the whole run. Measured
    // 80k identical relocated lines at ~36s before the candidate-scan cap,
    // ~140ms after. Every line here is byte-identical — the worst case.
    String identicalRelocated(int n) {
      final b = StringBuffer()
        ..writeln('diff --git a/f b/f')
        ..writeln('--- a/f')
        ..writeln('+++ b/f')
        ..writeln('@@ -1,${n + 3} +1,${n + 3} @@');
      for (var i = 0; i < n; i++) {
        b.writeln('-repeated identical payload line');
      }
      b
        ..writeln(' anchor one')
        ..writeln(' anchor two')
        ..writeln(' anchor three');
      for (var i = 0; i < n; i++) {
        b.writeln('+repeated identical payload line');
      }
      return b.toString();
    }

    test('relocating a large block of identical lines stays linear (not O(n²))',
        () {
      int build(int n) {
        final lines = parseUnifiedDiff(identicalRelocated(n));
        var best = 1 << 30;
        for (var r = 0; r < 2; r++) {
          final sw = Stopwatch()..start();
          buildEditUnits(lines, detectMoves: true);
          sw.stop();
          if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
        }
        return best;
      }

      final small = build(20000);
      final large = build(80000);
      // 4x the lines; quadratic (as it was) is ~16x AND tens of seconds.
      expect(large, lessThan((small * 8).clamp(2500, 1 << 30)),
          reason: 'identical-block move detection went super-linear: '
              '20k=${small}ms 80k=${large}ms — the exact-move candidate cap '
              'likely regressed.');
      expect(large, lessThan(4000),
          reason: 'buildEditUnits on 80k identical relocated lines took '
              '${large}ms (was ~36000ms before the scan cap)');

      // Correctness under the cap: a move is still detected, not silently
      // dropped to plain delete+insert.
      final units =
          buildEditUnits(parseUnifiedDiff(identicalRelocated(500)),
              detectMoves: true);
      expect(units.any((u) => u.kind == EditKind.move), isTrue,
          reason: 'the relocated identical block should still register as a '
              'move even though the candidate scan is capped');
    });
  });
}
