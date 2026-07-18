// Generators for the raw material of a *diff*: a `(before, after)` pair of
// file contents related by a realistic edit, plus the adversarial line shapes
// that a unified-diff parser must disambiguate from structure.
//
// Why a dedicated generator instead of two independent `genMultilineText`
// draws: a diff is only interesting when `before` and `after` SHARE most of
// their lines. Two unrelated blobs produce a degenerate "delete everything,
// add everything" diff with no context lines, no line-number arithmetic, and
// nothing for move detection to chew on. Here `after` is built by walking
// `before` and applying per-line edits (keep / delete / replace / insert),
// optionally relocating a block — so the resulting `git diff` has context,
// additions, deletions, hunks with real `@@` arithmetic, and sometimes a
// verbatim move. That is the input distribution the viewer actually faces.
//
// The line pool is where the teeth are. A unified-diff body line is a marker
// char (`+`/`-`/space) followed by the file's literal content, so a line of
// SOURCE that itself begins `+`, `-`, `@@`, `\`, `diff --git`, `+++`, `---`,
// or `index ` renders byte-for-byte like a structural line. Distinguishing
// the two is the entire reason `_HunkCursor` exists (see diff_models.dart).
// Every draw mixes these shapes in, so any parser that dispatches on prefix
// alone is caught.

import 'gen.dart';
import 'prop.dart';

/// A `before`/`after` content pair related by an edit, plus the metadata a
/// law needs to make precise assertions:
///  - [oldLines]/[newLines]: the content as line lists (no terminators), the
///    ground truth a reconstruction law compares the parsed diff against;
///  - [eol]: the line terminator every line (including the last) carries in
///    [oldText]/[newText]; `''` for a file with no final newline;
///  - [movedBlock]: true when [newText] contains a verbatim relocation of a
///    contiguous run of [oldLines] — the positive case for move detection.
class DiffScenario {
  final List<String> oldLines;
  final List<String> newLines;
  final String eol;
  final bool movedBlock;

  const DiffScenario({
    required this.oldLines,
    required this.newLines,
    required this.eol,
    required this.movedBlock,
  });

  String _render(List<String> lines) {
    if (lines.isEmpty) return '';
    // Every line, INCLUDING the last, gets the terminator — except when [eol]
    // is '' (the no-trailing-newline file), where no line gets one and the
    // lines are joined by a real '\n' so the file still has structure.
    if (eol.isEmpty) return lines.join('\n');
    final b = StringBuffer();
    for (final l in lines) {
      b
        ..write(l)
        ..write(eol);
    }
    return b.toString();
  }

  String get oldText => _render(oldLines);
  String get newText => _render(newLines);

  @override
  String toString() => 'DiffScenario(eol=${_reprEol(eol)}, moved=$movedBlock, '
      'old=${oldLines.length}L, new=${newLines.length}L)';
}

String _reprEol(String eol) => switch (eol) {
      '' => '<none>',
      '\n' => r'\n',
      '\r\n' => r'\r\n',
      '\r' => r'\r',
      _ => eol.codeUnits.toString(),
    };

/// A single line of file *content* — never containing a line terminator, but
/// deliberately allowed to begin with a character that collides with unified
/// -diff structure. `'x'`-family plain lines come first so a shrunk
/// counterexample favors ordinary content; the adversarial prefixes are what
/// separate a real parser from a prefix-sniffing one.
final List<String Function(Rng)> _linePool = [
  // Ordinary content, distinct enough that diffs are clean and moves match.
  (rng) => 'line ${rng.intBetween(0, 999)}',
  (rng) => genAscii(maxLen: 24)(rng).replaceAll('\n', ' '),
  // Content that mimics unified-diff structure in column 0.
  (rng) => '+${genAscii(maxLen: 8)(rng)}', // e.g. `++i;`, `+= 1`
  (rng) => '-${genAscii(maxLen: 8)(rng)}', // e.g. `-- sql comment`, `--flag`
  (rng) => ' ${genAscii(maxLen: 8)(rng)}', // leading space == a context marker
  (rng) => '@@ ${genAscii(maxLen: 6)(rng)}', // fake hunk header
  (rng) => '@@@ combined ${rng.intBetween(0, 9)}',
  (rng) => '\\ ${genAscii(maxLen: 6)(rng)}', // mimics the no-newline marker
  (rng) => 'diff --git a/x b/x', // a literal diff header as file content
  (rng) => '--- a/${genAscii(maxLen: 6)(rng)}',
  (rng) => '+++ b/${genAscii(maxLen: 6)(rng)}',
  (rng) => 'index 0000000..1111111 100644',
  (rng) => '', // a genuinely blank line
];

/// One content line. When [allowBlank] is false the result is guaranteed
/// non-empty — the fully-blank line is the single shape that renders
/// ambiguously in a unified diff (a context blank can appear as `' '` or as a
/// truly empty line), so a law that reconstructs source byte-for-byte excludes
/// it and covers it instead via the git-apply round-trip, which lets git own
/// that ambiguity.
Gen<String> _genSourceLine({bool allowBlank = true}) => (rng) {
      final s = rng.pick(_linePool)(rng);
      if (!allowBlank && s.isEmpty) return 'x${rng.intBetween(0, 999)}';
      return s;
    };

/// A file as a list of content lines (0..[maxLines]). Length shrinks toward 0
/// (the empty file — a real edge for "create" / "delete whole file" diffs).
Gen<List<String>> _genSourceLines({int maxLines = 24, bool allowBlank = true}) {
  final line = _genSourceLine(allowBlank: allowBlank);
  return (rng) {
    final n = rng.intBetween(0, maxLines);
    return List<String>.generate(n, (_) => line(rng));
  };
}

/// The end-of-line policy for a rendered scenario. LF dominates (the common
/// case) but CRLF, a lone CR, and NO-final-newline each show up often enough
/// for a `requireCoverage` floor — they are the classic diff off-by-one traps.
String _pickEol(Rng rng) => rng.pick(const ['\n', '\n', '\n', '\r\n', '', '\r']);

/// A `before`/`after` scenario: `after` is `before` walked line by line with
/// per-line edits, so the pair shares structure and produces a realistic diff.
///
/// Roughly a third of scenarios also relocate a contiguous block of `before`
/// verbatim into a new position in `after` ([DiffScenario.movedBlock]), the
/// positive fixture for move detection. When no block is moved, `movedBlock`
/// is false and a move-detection law can assert the *negative* (no false
/// move) with confidence.
/// [genDiffScenario] with [forceEol]='\n' and no blank lines — the shape a
/// byte-exact reconstruction law needs, where every diff body line is
/// unambiguously `marker + content`.
Gen<DiffScenario> genCleanDiffScenario({int maxLines = 24}) =>
    genDiffScenario(maxLines: maxLines, allowBlank: false, forceEol: '\n');

Gen<DiffScenario> genDiffScenario({
  int maxLines = 24,
  bool allowBlank = true,
  String? forceEol,
}) {
  final sourceLines = _genSourceLines(maxLines: maxLines, allowBlank: allowBlank);
  final freshLine = _genSourceLine(allowBlank: allowBlank);
  return (rng) {
    final oldLines = sourceLines(rng);
    final eol = forceEol ?? _pickEol(rng);

    // Optionally lift a contiguous block out of `before` to reinsert verbatim.
    final canMove = oldLines.length >= 4 && rng.intBetween(0, 2) == 0;
    List<String> movedRun = const [];
    var moveFrom = -1, moveLen = 0;
    if (canMove) {
      moveLen = rng.intBetween(1, (oldLines.length ~/ 2).clamp(1, 6));
      moveFrom = rng.intBetween(0, oldLines.length - moveLen);
      movedRun = oldLines.sublist(moveFrom, moveFrom + moveLen);
    }

    final newLines = <String>[];
    for (var i = 0; i < oldLines.length; i++) {
      // Skip the lifted block at its origin; it will be reinserted elsewhere.
      if (canMove && i >= moveFrom && i < moveFrom + moveLen) continue;
      final roll = rng.intBetween(0, 9);
      if (roll < 5) {
        newLines.add(oldLines[i]); // keep -> context
      } else if (roll < 7) {
        // delete: emit nothing
      } else if (roll < 9) {
        newLines.add(freshLine(rng)); // replace
      } else {
        newLines
          ..add(freshLine(rng)) // insert before, then keep
          ..add(oldLines[i]);
      }
    }
    if (canMove) {
      // Reinsert the moved block at a fresh position in the NEW list.
      final at = newLines.isEmpty ? 0 : rng.intBetween(0, newLines.length);
      newLines.insertAll(at, movedRun);
    }

    // Coverage tags so a degenerate generator (e.g. one that stops producing
    // deletions after a refactor) fails loudly instead of passing vacuously.
    classify(oldLines.isEmpty, 'empty-old');
    classify(newLines.isEmpty, 'empty-new');
    classify(eol.isEmpty, 'no-final-eol');
    classify(eol == '\r\n', 'crlf');
    classify(canMove, 'moved-block');
    classify(oldLines.length == newLines.length, 'same-length');

    return DiffScenario(
      oldLines: oldLines,
      newLines: newLines,
      eol: eol,
      movedBlock: canMove && movedRun.isNotEmpty,
    );
  };
}
