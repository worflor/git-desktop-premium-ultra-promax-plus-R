// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

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

  group('AppSettingsSnapshot — alphaMathPath', () {
    test('missing key → defaults to empty (pre-field installs)', () {
      final snap = AppSettingsSnapshot.fromJson(const <String, dynamic>{});
      expect(snap.alphaMathPath, '');
    });

    test('persisted value round-trips through toJson/fromJson', () {
      final base = AppSettingsSnapshot.defaults()
          .copyWith(alphaMathPath: r'C:\engines\alpha-math.exe');
      final reloaded = AppSettingsSnapshot.fromJson(base.toJson());
      expect(reloaded.alphaMathPath, r'C:\engines\alpha-math.exe');
    });

    test('copyWith leaves the path untouched when omitted', () {
      final base =
          AppSettingsSnapshot.defaults().copyWith(alphaMathPath: '/opt/am');
      expect(base.copyWith(themeId: 'petrichor').alphaMathPath, '/opt/am');
    });

    test('non-string value → defaults to empty, no crash', () {
      final snap = AppSettingsSnapshot.fromJson({'alphaMathPath': 42});
      expect(snap.alphaMathPath, '');
    });
  });

  group('AppSettingsSnapshot — giteaTokens', () {
    test('missing key → empty map (pre-field installs)', () {
      final snap = AppSettingsSnapshot.fromJson(const <String, dynamic>{});
      expect(snap.giteaTokens, isEmpty);
    });

    test('persisted map round-trips through toJson/fromJson', () {
      final base = AppSettingsSnapshot.defaults().copyWith(
        giteaTokens: {'codeberg.org': 'abc', 'git.acme.com:3000': 'xyz'},
      );
      final reloaded = AppSettingsSnapshot.fromJson(base.toJson());
      expect(reloaded.giteaTokens['codeberg.org'], 'abc');
      expect(reloaded.giteaTokens['git.acme.com:3000'], 'xyz');
    });

    test('host keys are lowercased and blank entries dropped', () {
      final snap = AppSettingsSnapshot.fromJson({
        'giteaTokens': {
          'Codeberg.ORG': 'tok',
          'blankhost': '   ',
          '': 'orphan',
          'numeric': 42,
        },
      });
      expect(snap.giteaTokens, {'codeberg.org': 'tok'});
    });

    test('non-map value → empty, no crash', () {
      final snap = AppSettingsSnapshot.fromJson({'giteaTokens': 'nope'});
      expect(snap.giteaTokens, isEmpty);
    });
  });

  group('AppSettingsSnapshot — diff diff-ability', () {
    test('missing keys → both default to true (pre-field installs)', () {
      final snap = AppSettingsSnapshot.fromJson(const <String, dynamic>{});
      expect(snap.diffMediaEnabled, isTrue);
      expect(snap.diffBinaryEnabled, isTrue);
    });

    test('persisted false values round-trip through toJson/fromJson', () {
      final base = AppSettingsSnapshot.defaults()
          .copyWith(diffMediaEnabled: false, diffBinaryEnabled: false);
      final reloaded = AppSettingsSnapshot.fromJson(base.toJson());
      expect(reloaded.diffMediaEnabled, isFalse);
      expect(reloaded.diffBinaryEnabled, isFalse);
    });

    test('the two flags are independent', () {
      final base = AppSettingsSnapshot.defaults()
          .copyWith(diffMediaEnabled: false);
      final reloaded = AppSettingsSnapshot.fromJson(base.toJson());
      expect(reloaded.diffMediaEnabled, isFalse);
      expect(reloaded.diffBinaryEnabled, isTrue);
    });

    test('non-bool value → falls back to default true, no crash', () {
      final snap = AppSettingsSnapshot.fromJson({'diffMediaEnabled': 'nope'});
      expect(snap.diffMediaEnabled, isTrue);
    });
  });

  group('AppSettingsSnapshot — issuesSortDescending', () {
    test('missing key → defaults to true (newest first)', () {
      final snap = AppSettingsSnapshot.fromJson(const <String, dynamic>{});
      expect(snap.issuesSortDescending, isTrue);
    });

    test('persisted false round-trips through toJson/fromJson', () {
      final base = AppSettingsSnapshot.defaults()
          .copyWith(issuesSortDescending: false);
      final reloaded = AppSettingsSnapshot.fromJson(base.toJson());
      expect(reloaded.issuesSortDescending, isFalse);
    });

    test('copyWith leaves the flag untouched when omitted', () {
      final base = AppSettingsSnapshot.defaults()
          .copyWith(issuesSortDescending: false);
      expect(base.copyWith(themeId: 'petrichor').issuesSortDescending, isFalse);
    });

    test('non-bool value → falls back to default true, no crash', () {
      final snap =
          AppSettingsSnapshot.fromJson({'issuesSortDescending': 'nope'});
      expect(snap.issuesSortDescending, isTrue);
    });
  });

  group('AppSettingsSnapshot — tagsSortDescending', () {
    test('missing key → defaults to true (newest first)', () {
      final snap = AppSettingsSnapshot.fromJson(const <String, dynamic>{});
      expect(snap.tagsSortDescending, isTrue);
    });

    test('persisted false round-trips through toJson/fromJson', () {
      final base =
          AppSettingsSnapshot.defaults().copyWith(tagsSortDescending: false);
      final reloaded = AppSettingsSnapshot.fromJson(base.toJson());
      expect(reloaded.tagsSortDescending, isFalse);
    });

    test('copyWith leaves the flag untouched when omitted', () {
      final base =
          AppSettingsSnapshot.defaults().copyWith(tagsSortDescending: false);
      expect(base.copyWith(themeId: 'petrichor').tagsSortDescending, isFalse);
    });

    test('non-bool value → falls back to default true, no crash', () {
      final snap = AppSettingsSnapshot.fromJson({'tagsSortDescending': 'nope'});
      expect(snap.tagsSortDescending, isTrue);
    });
  });
}
