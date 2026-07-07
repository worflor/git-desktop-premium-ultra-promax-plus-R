import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_collapse_policy.dart';

void main() {
  group('autoCollapseFoldIndices — participation-ratio policy', () {
    test('uniform importance folds nothing (N_eff = N)', () {
      // The doc comment's promise: a uniform-importance diff collapses
      // nothing. N_eff = N, ceil(N) = N, keep everything.
      expect(autoCollapseFoldIndices([1, 1, 1, 1, 1, 1]), isEmpty);
      expect(autoCollapseFoldIndices([0.5, 0.5, 0.5]), isEmpty);
      // Near-uniform (the shape real diffs actually take) still folds
      // nothing: N_eff rounds up to N.
      expect(autoCollapseFoldIndices([1.0, 0.98, 0.97, 0.99, 0.96]), isEmpty);
    });

    test('single dominant hunk folds all but the spike', () {
      final folds = autoCollapseFoldIndices([1.0, 0, 0, 0, 0, 0]);
      // Index 0 stays expanded; every other (zero) hunk folds.
      expect(folds, {1, 2, 3, 4, 5});
      expect(folds.contains(0), isFalse);
    });

    test('two-tier distribution folds exactly the lower tier', () {
      // Three strong, three weak. N_eff ≈ 3.6 → keep the top tier, fold the
      // bottom tier.
      final folds = autoCollapseFoldIndices([1, 1, 1, 0.1, 0.1, 0.1]);
      expect(folds, {3, 4, 5});
    });

    test('ties at the fold boundary are never split', () {
      // A tie block straddling the marginal value shares one fate — the
      // policy folds on value, not index, so it can never keep one member of
      // a tie while folding an identical sibling.
      final folds = autoCollapseFoldIndices([1.0, 0.9, 0.5, 0.5, 0.2, 0.2]);
      // Whatever the boundary lands on, the two 0.5s agree and the two 0.2s
      // agree.
      expect(folds.contains(2), equals(folds.contains(3)),
          reason: 'the 0.5-tie must not be split');
      expect(folds.contains(4), equals(folds.contains(5)),
          reason: 'the 0.2-tie must not be split');
      // Sanity: the top hunk is always kept.
      expect(folds.contains(0), isFalse);
    });

    test('a whole tied tail folds together under one dominant hunk', () {
      // One spike over five identical small hunks: the tail is one tie block
      // and folds as a unit, keeping only the spike.
      final folds = autoCollapseFoldIndices([1.0, 0.05, 0.05, 0.05, 0.05, 0.05]);
      expect(folds, {1, 2, 3, 4, 5});
    });

    test('N < 3 is left untouched', () {
      expect(autoCollapseFoldIndices([]), isEmpty);
      expect(autoCollapseFoldIndices([1.0]), isEmpty);
      expect(autoCollapseFoldIndices([1.0, 0.0]), isEmpty);
    });

    test('all-zero / no-signal φ never folds everything', () {
      expect(autoCollapseFoldIndices([0, 0, 0, 0]), isEmpty);
      expect(autoCollapseFoldIndices([0.0, 0.0, 0.0]), isEmpty);
    });

    test('never throws on degenerate inputs', () {
      expect(() => autoCollapseFoldIndices([0, 0, 0]), returnsNormally);
      expect(() => autoCollapseFoldIndices([1.0]), returnsNormally);
      expect(() => autoCollapseFoldIndices([]), returnsNormally);
    });

    test('never folds a hunk that stays as important as a kept one', () {
      // Invariant: every folded hunk is strictly less important than every
      // kept hunk. Exercise it on an asymmetric distribution.
      final imp = [1.0, 0.8, 0.8, 0.3, 0.05, 0.05, 0.02];
      final folds = autoCollapseFoldIndices(imp);
      final keptMin = [
        for (var i = 0; i < imp.length; i++)
          if (!folds.contains(i)) imp[i]
      ].fold<double>(double.infinity, (m, v) => v < m ? v : m);
      for (final i in folds) {
        expect(imp[i] < keptMin, isTrue,
            reason: 'folded ${imp[i]} must be < kept-min $keptMin');
      }
    });
  });
}
