// Behavior coverage for the merge-conflict editor's RESOLUTION logic — the
// code that decides the final bytes a user commits back to a conflicted file.
//
// The parser (parseConflictFile/ConflictBlock/buildResult round trip) is
// already covered by test/features/merge_conflict_parser_test.dart and the
// LAW 4/5 fuzz in test/fuzz/patch_diff_crlf_roundtrip_test.dart — this file
// does NOT retest it. What was previously untested, and is exercised here, is
// the interactive decision layer that used to live trapped inside
// _MergeConflictEditorState. It has been extracted (behavior-preserving) into
// pure, widget-free top-level functions in merge_conflict_editor.dart:
//
//   * applyConflictResolution  — accept-ours / theirs / both / bothReversed /
//                                 custom / unresolve (the State's _resolve /
//                                 _unresolve delegate here)
//   * conflictTrustDecision    — the trust-slider auto-resolve decision
//   * applyConflictTrust        — apply that decision across a block list
//   * clearAutoResolvedConflicts — revert only machine picks
//   * resolveEasyConflicts      — the one-shot "resolve easy conflicts" action
//
// The invariant that matters most: resolving must NEVER silently corrupt or
// drop content — for any choice the output is exactly the intended side(s),
// byte-for-byte, with every conflict marker removed.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/changes/merge_conflict_editor.dart';

import '../../support/gen.dart';
import '../../support/prop.dart';

ConflictBlock _block({
  String ours = 'OURS',
  String theirs = 'THEIRS',
  double? bias,
}) =>
    ConflictBlock(index: 0, oursText: ours, theirsText: theirs)
      ..coherenceBias = bias;

void main() {
  final scale = fuzzScale();

  // ─────────────────────────────────────────────────────────────────────────
  // PART B.1 — applyConflictResolution: each choice yields exactly its side
  // ─────────────────────────────────────────────────────────────────────────
  group('applyConflictResolution — the resolved bytes for each choice', () {
    test('accept-ours yields exactly the ours side, no marker leakage', () {
      final b = _block(ours: 'alpha\nbeta', theirs: 'gamma\ndelta');
      applyConflictResolution(b, ConflictSide.ours);
      expect(b.resolution, ConflictSide.ours);
      expect(b.isResolved, isTrue);
      expect(b.resolvedText, 'alpha\nbeta');
      expect(b.resolvedText, isNot(contains('<<<<<<<')));
      expect(b.resolvedText, isNot(contains('=======')));
      expect(b.resolvedText, isNot(contains('gamma')),
          reason: 'the rejected (theirs) side must not leak');
    });

    test('accept-theirs yields exactly the theirs side', () {
      final b = _block(ours: 'alpha', theirs: 'gamma\ndelta');
      applyConflictResolution(b, ConflictSide.theirs);
      expect(b.resolvedText, 'gamma\ndelta');
      expect(b.resolvedText, isNot(contains('alpha')));
    });

    test('accept-both is ours-then-theirs in that order', () {
      final b = _block(ours: 'A', theirs: 'B');
      applyConflictResolution(b, ConflictSide.both);
      expect(b.resolvedText, 'A\nB');
    });

    test('bothReversed is theirs-then-ours', () {
      final b = _block(ours: 'A', theirs: 'B');
      applyConflictResolution(b, ConflictSide.bothReversed);
      expect(b.resolvedText, 'B\nA');
    });

    test('custom stores the edited text verbatim (incl. CRLF, control chars, '
        'emoji)', () {
      // Built via String.fromCharCodes per house rules — no raw control/
      // non-ASCII literals in source.
      final rocket = String.fromCharCodes([0x1F680]); // 🚀
      final bell = String.fromCharCodes([0x07]); // BEL control char
      final edited = 'first\r\nsecond${bell}mid\r\n$rocket end';
      final b = _block(ours: 'OURS', theirs: 'THEIRS');
      applyConflictResolution(b, ConflictSide.custom, customText: edited);
      expect(b.resolution, ConflictSide.custom);
      expect(b.resolvedText, edited,
          reason: 'custom content must survive byte-for-byte');
    });

    test('custom with an explicit empty string resolves to empty, not a '
        'marker', () {
      final b = _block(ours: 'OURS', theirs: 'THEIRS');
      applyConflictResolution(b, ConflictSide.custom, customText: '');
      expect(b.resolvedText, '');
    });

    test('unresolve returns the block to its conflicted (unresolved) form', () {
      final b = _block(ours: 'A', theirs: 'B');
      applyConflictResolution(b, ConflictSide.both);
      expect(b.isResolved, isTrue);
      applyConflictResolution(b, ConflictSide.unresolved);
      expect(b.resolution, ConflictSide.unresolved);
      expect(b.isResolved, isFalse);
      expect(b.resolvedText, '',
          reason: 'an unresolved block contributes no resolved bytes');
    });

    test('empty ours side: accept-ours yields empty, accept-theirs yields '
        'theirs — never a marker', () {
      final b = _block(ours: '', theirs: 'the only content');
      applyConflictResolution(b, ConflictSide.ours);
      expect(b.resolvedText, '');
      applyConflictResolution(b, ConflictSide.theirs);
      expect(b.resolvedText, 'the only content');
    });

    test('non-custom choices never mutate customText', () {
      final b = _block(ours: 'A', theirs: 'B')..customText = 'preexisting';
      applyConflictResolution(b, ConflictSide.ours);
      expect(b.customText, 'preexisting',
          reason: 'only the custom side may write customText');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PART B.2 — conflictTrustDecision: the auto-resolve ladder
  // ─────────────────────────────────────────────────────────────────────────
  group('conflictTrustDecision — trust-level ladder', () {
    test('level 0 (manual) never decides, even for identical sides', () {
      expect(conflictTrustDecision(_block(ours: 'x', theirs: 'x'), 0), isNull);
    });

    test('level 1 (safe) resolves byte-identical sides to ours, nothing else',
        () {
      expect(conflictTrustDecision(_block(ours: 'x', theirs: 'x'), 1),
          ConflictSide.ours);
      expect(conflictTrustDecision(_block(ours: 'x ', theirs: 'x'), 1), isNull,
          reason: 'a trailing space makes them non-identical at level 1');
    });

    test('level 2 (guided) also resolves whitespace-identical sides', () {
      expect(conflictTrustDecision(_block(ours: '  x ', theirs: 'x'), 2),
          ConflictSide.ours);
      expect(conflictTrustDecision(_block(ours: 'x', theirs: 'y'), 2), isNull);
    });

    test('level 3 (assisted): empty side, and strict superset, pick the right '
        'winner', () {
      // theirs empty → keep ours.
      expect(conflictTrustDecision(_block(ours: 'keep', theirs: ''), 3),
          ConflictSide.ours);
      // ours empty → keep theirs.
      expect(conflictTrustDecision(_block(ours: '', theirs: 'keep'), 3),
          ConflictSide.theirs);
      // ours strictly contains theirs → ours is the superset.
      expect(
          conflictTrustDecision(
              _block(ours: 'line1\nline2', theirs: 'line1'), 3),
          ConflictSide.ours);
      // theirs strictly contains ours → theirs is the superset.
      expect(
          conflictTrustDecision(
              _block(ours: 'line1', theirs: 'line1\nline2'), 3),
          ConflictSide.theirs);
      // genuinely divergent → no decision at level 3.
      expect(
          conflictTrustDecision(_block(ours: 'aaa', theirs: 'bbb'), 3), isNull);
    });

    test('level 4 (full) breaks a small divergent diff by coherence bias', () {
      expect(
          conflictTrustDecision(
              _block(ours: 'aaa', theirs: 'bbb', bias: 0.2), 4),
          ConflictSide.ours,
          reason: 'positive bias favours ours');
      expect(
          conflictTrustDecision(
              _block(ours: 'aaa', theirs: 'bbb', bias: -0.2), 4),
          ConflictSide.theirs,
          reason: 'negative bias favours theirs');
      // Weak bias → no call.
      expect(
          conflictTrustDecision(
              _block(ours: 'aaa', theirs: 'bbb', bias: 0.02), 4),
          isNull);
      // Large diff (>8 lines) → engine stays out of it even at full trust.
      final big = List.generate(9, (i) => 'o$i').join('\n');
      final bigT = List.generate(9, (i) => 't$i').join('\n');
      expect(
          conflictTrustDecision(
              _block(ours: big, theirs: bigT, bias: 0.5), 4),
          isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PART B.3 — applyConflictTrust / clearAutoResolvedConflicts
  // ─────────────────────────────────────────────────────────────────────────
  group('applyConflictTrust + clearAutoResolvedConflicts', () {
    test('tags auto-resolved blocks and skips already-resolved ones', () {
      final identical = _block(ours: 'same', theirs: 'same');
      final divergent = _block(ours: 'a', theirs: 'b');
      final manual = _block(ours: 'm1', theirs: 'm2')
        ..resolution = ConflictSide.theirs
        ..customText = null; // a hand-made pick, not tagged auto
      final blocks = [identical, divergent, manual];

      applyConflictTrust(blocks, 1); // safe: only identical resolves

      expect(identical.resolution, ConflictSide.ours);
      expect(identical.customText, kAutoResolvedTag);
      expect(divergent.isResolved, isFalse,
          reason: 'safe level must leave a divergent block untouched');
      expect(manual.resolution, ConflictSide.theirs,
          reason: 'an already-resolved block is never re-decided');
      expect(manual.customText, isNull);
    });

    test('clearAutoResolvedConflicts reverts ONLY the machine picks', () {
      final auto = _block(ours: 'same', theirs: 'same');
      final manual = _block(ours: 'a', theirs: 'b');
      applyConflictTrust([auto], 1); // auto now resolved+tagged
      applyConflictResolution(manual, ConflictSide.ours); // user's own pick

      clearAutoResolvedConflicts([auto, manual]);

      expect(auto.isResolved, isFalse,
          reason: 'the auto pick must be rolled back');
      expect(auto.customText, isNull);
      expect(manual.resolution, ConflictSide.ours,
          reason: 'the user pick must be preserved across a trust change');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PART B.4 — resolveEasyConflicts: bulk "resolve easy"
  // ─────────────────────────────────────────────────────────────────────────
  group('resolveEasyConflicts — bulk resolve of cool blocks only', () {
    test('cool blocks resolve (toward the biased side), hot blocks are left',
        () {
      // Identical → heat 0 (cool), no bias → ours.
      final coolOurs = _block(ours: 'x', theirs: 'x');
      // High similarity + strong positive bias → cool → ours.
      final coolBiasOurs = _block(
          ours: 'a\nb\nc\nd', theirs: 'a\nb\nc\ne', bias: 0.3);
      // Same shape, strong NEGATIVE bias → cool → theirs.
      final coolBiasTheirs = _block(
          ours: 'a\nb\nc\nd', theirs: 'a\nb\nc\ne', bias: -0.3);
      // Wholly different, no bias → hot → untouched.
      final hot = _block(ours: 'alpha\nbeta', theirs: 'gamma\ndelta');

      final blocks = [coolOurs, coolBiasOurs, coolBiasTheirs, hot];
      // Sanity on the heat partition the function keys off.
      expect(hot.heat, greaterThanOrEqualTo(0.3));
      expect(coolBiasOurs.heat, lessThan(0.3));

      resolveEasyConflicts(blocks);

      expect(coolOurs.resolution, ConflictSide.ours);
      expect(coolOurs.customText, kEasyResolvedTag);
      expect(coolBiasOurs.resolution, ConflictSide.ours);
      expect(coolBiasTheirs.resolution, ConflictSide.theirs,
          reason: 'a strong negative bias steers "easy" toward theirs');
      expect(hot.isResolved, isFalse,
          reason: 'an uncertain (hot) block must be left for the user');
    });

    test('never overrides an already-resolved block', () {
      final b = _block(ours: 'x', theirs: 'x'); // would otherwise be cool
      applyConflictResolution(b, ConflictSide.theirs);
      resolveEasyConflicts([b]);
      expect(b.resolution, ConflictSide.theirs,
          reason: 'resolveEasy must not clobber an existing resolution');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PART B.5 — end-to-end: extracted logic → buildResult final bytes
  // ─────────────────────────────────────────────────────────────────────────
  group('resolution → buildResult produces exact, marker-free file bytes', () {
    void expectMarkerFree(String result) {
      for (final line in result.split('\n')) {
        expect(
            line.startsWith('<<<<<<<') ||
                line.startsWith('=======') ||
                line.startsWith('>>>>>>>') ||
                line.startsWith('|||||||'),
            isFalse,
            reason: 'a conflict marker survived: "$line"\n--- result ---\n'
                '$result');
      }
      expect(parseConflictFile('f', result).blocks, isEmpty,
          reason: 'resolved output must not re-parse as conflicted');
    }

    test('accept-ours reconstructs surrounding context byte-exact', () {
      final cf = parseConflictFile('a.dart',
          'before\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> x\nafter\n');
      applyConflictResolution(cf.blocks[0], ConflictSide.ours);
      final result = cf.buildResult();
      expect(result, 'before\nours\nafter\n');
      expectMarkerFree(result);
    });

    test('accept-both / bothReversed order and byte-exactness', () {
      final both = parseConflictFile(
          'a.dart', '<<<<<<< HEAD\nA\n=======\nB\n>>>>>>> x\n');
      applyConflictResolution(both.blocks[0], ConflictSide.both);
      expect(both.buildResult(), 'A\nB\n');

      final rev = parseConflictFile(
          'a.dart', '<<<<<<< HEAD\nA\n=======\nB\n>>>>>>> x\n');
      applyConflictResolution(rev.blocks[0], ConflictSide.bothReversed);
      expect(rev.buildResult(), 'B\nA\n');
    });

    test('adjacent blocks resolved differently interleave correctly', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\nA\n=======\nB\n>>>>>>> x\n<<<<<<< HEAD\nC\n=======\nD\n>>>>>>> x\n');
      applyConflictResolution(cf.blocks[0], ConflictSide.both);
      applyConflictResolution(cf.blocks[1], ConflictSide.ours);
      final result = cf.buildResult();
      expect(result, 'A\nB\nC\n');
      expectMarkerFree(result);
    });

    test('custom edit lands verbatim in the assembled file', () {
      final cf = parseConflictFile('a.dart',
          'head\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> x\ntail\n');
      applyConflictResolution(cf.blocks[0], ConflictSide.custom,
          customText: 'hand written');
      expect(cf.buildResult(), 'head\nhand written\ntail\n');
    });

    test('empty ours side, accept-ours: block collapses to nothing without '
        'corrupting neighbours', () {
      final cf = parseConflictFile('a.dart',
          'keep\n<<<<<<< HEAD\n=======\ntheirs\n>>>>>>> x\ntail\n');
      applyConflictResolution(cf.blocks[0], ConflictSide.ours); // ours is empty
      final result = cf.buildResult();
      expect(result, 'keep\ntail\n');
      expectMarkerFree(result);
    });

    test('CRLF content round-trips through resolution byte-exact', () {
      final cf = parseConflictFile('a.dart',
          'a\r\n<<<<<<< HEAD\nx\r\ny\r\n=======\nz\r\n>>>>>>> b\nc\r\n');
      applyConflictResolution(cf.blocks[0], ConflictSide.ours);
      final result = cf.buildResult();
      // The ours body carries its own literal \r; nothing may be stripped.
      expect(result.contains('x\r\ny\r'), isTrue,
          reason: 'CRLF bytes inside the chosen side must survive:\n$result');
      expectMarkerFree(result);
    });

    test('no-trailing-newline suppression honoured per resolved side', () {
      // ours side flagged as the file\'s genuine EOF with no trailing newline.
      final ours = parseConflictFile('a.dart',
          'x\n<<<<<<< HEAD\nkeep\n=======\ndrop\n>>>>>>> y\n');
      ours.blocks.last.oursNoTrailingNewline = true;
      applyConflictResolution(ours.blocks.last, ConflictSide.ours);
      expect(ours.buildResult(), 'x\nkeep',
          reason: 'accept-ours must not fabricate a trailing newline the '
              'file never had');

      // theirs side flagged instead.
      final theirs = parseConflictFile('a.dart',
          'x\n<<<<<<< HEAD\nkeep\n=======\ndrop\n>>>>>>> y\n');
      theirs.blocks.last.theirsNoTrailingNewline = true;
      applyConflictResolution(theirs.blocks.last, ConflictSide.theirs);
      expect(theirs.buildResult(), 'x\ndrop');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PART B.6 — fuzz laws over the extracted decision functions
  // ─────────────────────────────────────────────────────────────────────────
  group('fuzz — extracted resolution invariants', () {
    // Random blocks with independently fuzzed ours/theirs (and a random bias).
    Gen<List<ConflictBlock>> genBlocks({int maxBlocks = 5}) {
      final text = genMultilineText(maxLines: 4);
      return (rng) {
        final n = rng.intBetween(1, maxBlocks);
        return [
          for (var i = 0; i < n; i++)
            ConflictBlock(
                index: i, oursText: text(rng), theirsText: text(rng))
              ..coherenceBias = rng.nextBool()
                  ? (rng.nextDouble() - 0.5) * 0.8
                  : null,
        ];
      };
    }

    test('applyConflictTrust then clearAutoResolvedConflicts is a perfect '
        'round trip (every machine pick is reversible)', () {
      forAll(
        genBlocks(),
        count: 60 * scale,
        seed: 0x7A05,
        describe: 'block list',
        check: (blocks) {
          applyConflictTrust(blocks, 4); // most aggressive level
          for (final b in blocks) {
            if (b.isResolved) {
              expect(b.customText, kAutoResolvedTag,
                  reason: 'every auto-resolved block must carry the auto tag');
              expect(b.resolution, isNot(ConflictSide.unresolved));
            }
          }
          clearAutoResolvedConflicts(blocks);
          for (final b in blocks) {
            expect(b.isResolved, isFalse,
                reason: 'clear must revert every machine pick');
            expect(b.customText, isNull);
          }
        },
      );
    });

    test('resolveEasyConflicts only ever touches cool (heat < 0.3) blocks, '
        'always toward a real side', () {
      forAll(
        genBlocks(),
        count: 60 * scale,
        seed: 0x7A06,
        describe: 'block list',
        check: (blocks) {
          // Snapshot which blocks are "hot" before the action.
          final wasHot = [for (final b in blocks) b.heat >= 0.3];
          resolveEasyConflicts(blocks);
          for (var i = 0; i < blocks.length; i++) {
            if (wasHot[i]) {
              expect(blocks[i].isResolved, isFalse,
                  reason: 'a hot block must be left unresolved');
            } else {
              expect(blocks[i].resolution,
                  anyOf(ConflictSide.ours, ConflictSide.theirs),
                  reason: 'a cool block resolves to ours or theirs, never a '
                      'marker or an empty state');
              expect(blocks[i].customText, kEasyResolvedTag);
            }
          }
        },
      );
    });
  });
}
