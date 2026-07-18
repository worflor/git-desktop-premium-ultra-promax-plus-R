// Pins the ONE non-trivial change in the diff shell's display refresh: after
// making `_displayLineIndex` lazy, `_hunkDisplayRows` is built by a cheap
// O(hunks)-memory pass ([computeHunkDisplayRows]) instead of a full
// O(display-rows) map. This is a PURE equivalence property — no widget, no
// async — so it actually runs (the shell itself is too animation-heavy to
// widget-test without hanging). It asserts the new method returns exactly what
// the old `fullIndex[hunkLine.fastKey]` lookup did, across generated multi-hunk
// diffs with random display filtering (collapse/search).

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/diff_shell.dart' show computeHunkDisplayRows;

import '../../support/prop.dart';

/// The OLD implementation: materialise the full per-display-row fastKey→index
/// map, then look each hunk header up in it. This is the reference the lazy
/// rework must match byte-for-byte.
List<int> _referenceHunkRows(
  List<ParsedLine> sourceLines,
  List<int> hunkLineIndices,
  List<ParsedLine> displayLines,
) {
  final fullIndex = <int, int>{};
  for (var i = 0; i < displayLines.length; i++) {
    fullIndex[displayLines[i].fastKey] = i;
  }
  return [
    for (final hi in hunkLineIndices)
      (hi >= 0 && hi < sourceLines.length)
          ? (fullIndex[sourceLines[hi].fastKey] ?? -1)
          : -1,
  ];
}

/// A multi-hunk unified diff with distinct per-hunk headers and bodies (so
/// hunk-header fastKeys never collide — the real-world invariant).
String _multiHunkDiff(Rng rng) {
  final hunks = rng.intBetween(1, 6);
  final b = StringBuffer()
    ..writeln('diff --git a/f b/f')
    ..writeln('--- a/f')
    ..writeln('+++ b/f');
  var oldLine = 1, newLine = 1;
  for (var h = 0; h < hunks; h++) {
    final ctx = rng.intBetween(0, 3);
    final dels = rng.intBetween(0, 3);
    final adds = rng.intBetween(0, 3);
    b.writeln('@@ -$oldLine,${ctx + dels} +$newLine,${ctx + adds} @@ scope$h');
    for (var i = 0; i < ctx; i++) {
      b.writeln(' ctx h$h i$i v${rng.intBetween(0, 9999)}');
    }
    for (var i = 0; i < dels; i++) {
      b.writeln('-del h$h i$i v${rng.intBetween(0, 9999)}');
    }
    for (var i = 0; i < adds; i++) {
      b.writeln('+add h$h i$i v${rng.intBetween(0, 9999)}');
    }
    oldLine += ctx + dels + 5;
    newLine += ctx + adds + 5;
  }
  return b.toString();
}

typedef _Case = ({
  List<ParsedLine> lines,
  List<int> hunkIndices,
  List<ParsedLine> displayLines,
});

/// Generates a whole case ON THE TAPE (diff shape + filter decisions) so the
/// harness can shrink a counterexample.
_Case _genCase(Rng rng) {
  final lines = parseUnifiedDiff(_multiHunkDiff(rng));
  final hunkIndices = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].kind == LineKind.hunk) i,
  ];
  classify(hunkIndices.length >= 2, 'multi-hunk');
  // Simulate a filtered display list (collapse / search hides rows).
  final displayLines = <ParsedLine>[];
  var filteredAny = false;
  for (final l in lines) {
    if (rng.intBetween(0, 4) == 0) {
      filteredAny = true; // drop ~20%
    } else {
      displayLines.add(l);
    }
  }
  classify(filteredAny, 'some-filtered');
  return (
    lines: lines,
    hunkIndices: hunkIndices,
    displayLines: displayLines,
  );
}

void main() {
  test('computeHunkDisplayRows matches the full-map reference exactly', () {
    forAll<_Case>(
      _genCase,
      count: 500,
      seed: 0x0DDBA11,
      describe: 'hunk display rows equivalence',
      requireCoverage: {'some-filtered': 0.3, 'multi-hunk': 0.5},
      check: (c) {
        final actual =
            computeHunkDisplayRows(c.lines, c.hunkIndices, c.displayLines);
        final reference =
            _referenceHunkRows(c.lines, c.hunkIndices, c.displayLines);
        expect(actual, reference,
            reason: 'lazy-index hunk-row build diverged from the old full-map '
                'lookup');
      },
    );
  });

  test('out-of-range and empty inputs behave like the reference', () {
    final lines = parseUnifiedDiff(_multiHunkDiff(Rng(1)));
    // Out-of-range hunk indices map to -1, same as the reference.
    final hunkIndices = [-1, 0, lines.length + 5, 2];
    expect(
      computeHunkDisplayRows(lines, hunkIndices, lines),
      _referenceHunkRows(lines, hunkIndices, lines),
    );
    // Empty display list -> every hunk row is -1.
    expect(
      computeHunkDisplayRows(lines, hunkIndices, const []),
      everyElement(-1),
    );
    // No hunks -> empty rows.
    expect(computeHunkDisplayRows(lines, const [], lines), isEmpty);
  });
}
