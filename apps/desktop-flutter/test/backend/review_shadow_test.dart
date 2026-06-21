// Tests for the shadow-history (footgun) channel formatting + ranking.
// The cold git discovery path is exercised elsewhere; here we pin the
// pure rendering and severity ordering.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/review_shadow.dart';
import 'package:git_desktop/backend/shadow_history.dart' show ShadowType;

void main() {
  group('shadowRank', () {
    test('revert outranks reset outranks abandoned', () {
      expect(shadowRank({ShadowType.revert}),
          greaterThan(shadowRank({ShadowType.reset})));
      expect(shadowRank({ShadowType.reset}),
          greaterThan(shadowRank({ShadowType.abandonedBranch})));
    });

    test('combined flags accumulate', () {
      expect(
        shadowRank({ShadowType.revert, ShadowType.reset}),
        greaterThan(shadowRank({ShadowType.revert})),
      );
    });
  });

  group('formatShadowBlock', () {
    test('empty in, empty out', () {
      expect(formatShadowBlock(const {}), '');
    });

    test('labels each type and orders by severity', () {
      final block = formatShadowBlock({
        'lib/calm.dart': {ShadowType.abandonedBranch},
        'lib/hot.dart': {ShadowType.revert},
      });
      expect(block, contains('status: populated'));
      expect(block, contains('lib/hot.dart — reverted before'));
      expect(block, contains('abandoned in a dropped branch'));
      // The revert (higher rank) is listed before the abandoned one.
      expect(
        block.indexOf('lib/hot.dart'),
        lessThan(block.indexOf('lib/calm.dart')),
      );
    });

    test('joins multiple flags on one path', () {
      final block = formatShadowBlock({
        'lib/x.dart': {ShadowType.revert, ShadowType.reset},
      });
      expect(block, contains('reverted before · reset before'));
    });
  });
}
