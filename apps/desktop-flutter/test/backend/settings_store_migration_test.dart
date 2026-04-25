// Migration semantics for the `updateChannelExplicit` flag added to
// AppSettingsSnapshot. Pre-flag installs have no field; the loader
// infers a sensible value from what the old schema could possibly
// have stored, so a user's deliberate pin survives the upgrade
// while genuine auto-defaults still flow with their new binary.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/settings_store.dart';

void main() {
  group('AppSettingsSnapshot.fromJson — updateChannelExplicit migration', () {
    Map<String, dynamic> baseJson({
      String? updateChannel,
      bool? updateChannelExplicit,
    }) {
      // Only the channel-related keys matter for these tests; the rest
      // fall through to defaults. fromJson handles missing keys.
      return {
        if (updateChannel != null) 'updateChannel': updateChannel,
        if (updateChannelExplicit != null)
          'updateChannelExplicit': updateChannelExplicit,
      };
    }

    test('legacy "beta" with no flag → treated as explicit', () {
      // Pre-flag, "beta" could only have been written by the user
      // tapping the ribbon — the old normalizer coerced everything
      // else to "stable". Preserve their pin across the upgrade.
      final snap = AppSettingsSnapshot.fromJson(baseJson(updateChannel: 'beta'));
      expect(snap.updateChannel, 'beta');
      expect(snap.updateChannelExplicit, isTrue);
    });

    test('legacy "stable" with no flag → treated as auto-defaulted', () {
      // "stable" is ambiguous — could be the universal pre-flag default
      // or a deliberate choice. We lean toward auto-tracking so a
      // post-upgrade beta-binary user picks up the new channel rather
      // than getting stuck on a stale default.
      final snap =
          AppSettingsSnapshot.fromJson(baseJson(updateChannel: 'stable'));
      expect(snap.updateChannel, 'stable');
      expect(snap.updateChannelExplicit, isFalse);
    });

    test('legacy "dev" with no flag → treated as explicit', () {
      // The old normalizer coerced "dev" to "stable", so "dev" on disk
      // can only come from a hand-edit. Treat that as deliberate.
      final snap = AppSettingsSnapshot.fromJson(baseJson(updateChannel: 'dev'));
      expect(snap.updateChannelExplicit, isTrue);
    });

    test('explicit=true is honoured when present', () {
      final snap = AppSettingsSnapshot.fromJson(
        baseJson(updateChannel: 'stable', updateChannelExplicit: true),
      );
      expect(snap.updateChannelExplicit, isTrue);
    });

    test('explicit=false is honoured when present', () {
      // Even if the persisted channel "looks" deliberate, an explicit
      // false written by a current build wins over inference. This is
      // how the post-flag schema represents fresh installs.
      final snap = AppSettingsSnapshot.fromJson(
        baseJson(updateChannel: 'beta', updateChannelExplicit: false),
      );
      expect(snap.updateChannelExplicit, isFalse);
    });

    test('case + whitespace tolerated in legacy value', () {
      final snap = AppSettingsSnapshot.fromJson(
        baseJson(updateChannel: '  BETA  '),
      );
      expect(snap.updateChannelExplicit, isTrue);
    });

    test('missing channel + missing flag → defaults', () {
      final snap = AppSettingsSnapshot.fromJson(const <String, dynamic>{});
      expect(snap.updateChannelExplicit, isFalse);
    });

    test('non-string value at updateChannel → not explicit', () {
      // Hostile / corrupted JSON — don't crash, lean defaulted.
      final snap = AppSettingsSnapshot.fromJson({'updateChannel': 42});
      expect(snap.updateChannelExplicit, isFalse);
    });
  });
}
