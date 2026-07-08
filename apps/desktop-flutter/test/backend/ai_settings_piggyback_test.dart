// Round-trip coverage for the apiPiggybackCli field on
// AiSettingsSnapshot. Two contracts pinned here: '' is a real, distinct
// value (piggyback off) rather than "unset", and the value set is CLOSED
// over kSupportedPiggybackClis — an arbitrary persisted string (hand-edited
// JSON, a newer build's provider name after a downgrade) must degrade to
// the default instead of reaching the settings dropdown, where a value
// matching no item asserts at build time.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai_settings_store.dart';

void main() {
  group('AiSettingsSnapshot.apiPiggybackCli', () {
    test('default is codex', () {
      expect(AiSettingsSnapshot.defaults().apiPiggybackCli, 'codex');
    });

    test('fromJson clamps an unknown carrier to the default', () {
      const original = AiSettingsSnapshot(
        modelSelections: {},
        modelCategoryLabels: {'quality': 'Quality', 'fast': 'Fast'},
        commitMessageModelCategoryId: 'quality',
        reviewCommitModelCategoryId: 'quality',
        reviewCommitDoubleCheckEnabled: false,
        apiPiggybackCli: 'some-other-cli',
        museBrainstormModelCategoryId: 'fast',
        museSynthesisModelCategoryId: 'quality',
        presentModelCategoryId: 'quality',
      );
      final restored = AiSettingsSnapshot.fromJson(original.toJson());
      expect(restored.apiPiggybackCli, 'codex');
    });

    test('fromJson preserves every supported carrier', () {
      for (final cli in kSupportedPiggybackClis) {
        final snap = AiSettingsSnapshot.fromJson(
          AiSettingsSnapshot.defaults().copyWith(apiPiggybackCli: cli).toJson(),
        );
        expect(snap.apiPiggybackCli, cli);
      }
    });

    test('toJson/fromJson round-trips the off value without falling back '
        'to the default', () {
      const original = AiSettingsSnapshot(
        modelSelections: {},
        modelCategoryLabels: {'quality': 'Quality', 'fast': 'Fast'},
        commitMessageModelCategoryId: 'quality',
        reviewCommitModelCategoryId: 'quality',
        reviewCommitDoubleCheckEnabled: false,
        apiPiggybackCli: '',
        museBrainstormModelCategoryId: 'fast',
        museSynthesisModelCategoryId: 'quality',
        presentModelCategoryId: 'quality',
      );
      final restored = AiSettingsSnapshot.fromJson(original.toJson());
      expect(restored.apiPiggybackCli, '');
    });

    test('legacy JSON missing the key yields the default', () {
      final defaults = AiSettingsSnapshot.defaults();
      final legacyJson = <String, dynamic>{
        'modelSelections': defaults.modelSelections,
        'modelCategoryLabels': defaults.modelCategoryLabels,
        'reasoningEfforts': defaults.reasoningEfforts,
        'commitMessageModelCategoryId': defaults.commitMessageModelCategoryId,
        'reviewCommitModelCategoryId': defaults.reviewCommitModelCategoryId,
        'reviewCommitDoubleCheckEnabled':
            defaults.reviewCommitDoubleCheckEnabled,
        'museBrainstormModelCategoryId': defaults.museBrainstormModelCategoryId,
        'museSynthesisModelCategoryId': defaults.museSynthesisModelCategoryId,
        'presentModelCategoryId': defaults.presentModelCategoryId,
        // apiPiggybackCli intentionally omitted.
      };
      final snap = AiSettingsSnapshot.fromJson(legacyJson);
      expect(snap.apiPiggybackCli, 'codex');
    });

    test('copyWith sets apiPiggybackCli and preserves other fields', () {
      final defaults = AiSettingsSnapshot.defaults();
      final updated = defaults.copyWith(apiPiggybackCli: '');
      expect(updated.apiPiggybackCli, '');
      expect(updated.commitMessageModelCategoryId,
          defaults.commitMessageModelCategoryId);
      expect(updated.reviewCommitModelCategoryId,
          defaults.reviewCommitModelCategoryId);
      expect(updated.reviewCommitDoubleCheckEnabled,
          defaults.reviewCommitDoubleCheckEnabled);
      expect(updated.museBrainstormModelCategoryId,
          defaults.museBrainstormModelCategoryId);
      expect(updated.museSynthesisModelCategoryId,
          defaults.museSynthesisModelCategoryId);
      expect(updated.presentModelCategoryId, defaults.presentModelCategoryId);
    });

    test('copyWith with no argument preserves the existing value', () {
      final defaults = AiSettingsSnapshot.defaults();
      final withCustom = defaults.copyWith(apiPiggybackCli: 'codex');
      final untouched = withCustom.copyWith();
      expect(untouched.apiPiggybackCli, 'codex');
    });
  });
}
