// Roundtrip + coercion-robustness fuzz coverage for AppSettingsSnapshot /
// SettingsStore (lib/backend/settings_store.dart) — the single point
// where every app setting is saved/loaded. This is NOT the migration
// test (test/backend/settings_store_migration_test.dart), which already
// covers: the updateChannelExplicit legacy-migration matrix in detail,
// plus a handful of individually-named fields (alphaMathPath, giteaTokens,
// diffMediaEnabled/diffBinaryEnabled, issuesSortDescending/
// tagsSortDescending). None of that is repeated here.
//
// This file's value-add:
//   1. LAW — full snapshot roundtrip: fromJson(toJson(x)) deep-equals x
//      for every one of the ~45 fields (enums, bools, ints, doubles,
//      strings incl. hostile unicode, the external-tools list, both
//      string-keyed maps), for a fuzzed generator that covers the whole
//      object. AppSettingsSnapshot/ExternalTool have no `==` override, so
//      equality is checked field-by-field.
//   2. LAW — coercion totality: every `_normalizeX`/`_xxxOr` coercer, fed
//      missing/null/wrong-typed/out-of-range JSON, must never throw and
//      must fall back to its documented default (or, for the clamped
//      numeric fields, clamp into range) — the untested surface a
//      corrupt or hand-edited settings.json actually exercises. A few
//      known bugs on this surface are left `skip:`-ped inline with a
//      terse repro; see docs/architecture/test-hardening-bug-dossier.md
//      for the full writeup. `_doubleOr`'s NaN-becomes-upper-bound
//      behavior (via `num.clamp`'s `compareTo` semantics) is a
//      documented quirk, not a bug — see the dedicated non-skipped test
//      below.
//   3. LAW — migration idempotence: legacy-shaped JSON (fuzzed across
//      many shapes, including the ALSO-untested reduceMotion->motionRate
//      migration) migrates correctly AND re-running
//      fromJson(toJson(migrated)) is a stable fixed point — the specific
//      idempotence angle the migration test file never checks.
//   4. LAW — persistence roundtrip through the REAL store
//      (SettingsStore.persist/load/invalidateCache — plain dart:io File
//      under StoragePaths.gdpuDataDir(); no shared_preferences anywhere
//      in this module).
//   5. LAW — empty/first-run defaults.
//
// SAFETY: SettingsStore always resolves ONE fixed file
// (`<gdpuDataDir>/settings.json`) with no per-test uniquification.
// StoragePaths.gdpuDataDir() honours a GDPU_DATA_DIR env-var override
// (lib/backend/storage_paths.dart) — the same override
// test/backend/command_telemetry_store_test.dart and
// test/backend/review_ratchet_store_test.dart already document as
// required for hermetic runs. The persistence group below is skipped
// unless GDPU_DATA_DIR is set, so a forgotten env var never causes a read
// or write of a developer's real settings.json.
//
// Run with, e.g.:
//   GDPU_DATA_DIR=/tmp/gdpu-settings-test flutter test \
//     test/fuzz/settings_store_roundtrip_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/build_info.dart';
import 'package:git_desktop/backend/external_tools.dart';
import 'package:git_desktop/backend/settings_store.dart';
import 'package:git_desktop/backend/storage_paths.dart';

import '../support/gen.dart';
import '../support/prop.dart';

// ── Local generators ────────────────────────────────────────────────────

/// Wraps [body] in non-whitespace ascii borders so `String.trim()` (used
/// by `SettingsStore._stringOr` on every plain-string field, and again by
/// several `_normalizeXxx` helpers) is a no-op regardless of what [body]
/// contains — the fixed-point guarantee the roundtrip law needs for
/// fields normalized via trimming (themeId, keybindingProfile, the
/// enum-string fields' pre-trim, ExternalTool.executable).
String _trimFixed(String body) => 'x$body' 'y';

/// A free-form string: no trim, no case-folding — used for fields with
/// zero normalization (wickExePath, alphaMathPath, ExternalTool.label,
/// ExternalTool.args entries), which is where the heaviest hostile-unicode
/// content belongs since literally nothing strips it.
Gen<String> _genFreeString({int maxLen = 24}) => (rng) {
      return rng.nextBool()
          ? genUnicodeHostile(maxLen: maxLen)(rng)
          : genAscii(maxLen: maxLen)(rng);
    };

/// A trim-normalized-only string (themeId, keybindingProfile): may carry
/// hostile unicode in its interior, never leading/trailing whitespace.
Gen<String> _genTrimFixedString({int maxLen = 20}) => (rng) {
      return _trimFixed(_genFreeString(maxLen: maxLen)(rng));
    };

const String _kSafeNonSpaceChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-';

/// appShortName fixed point: 1..24 chars, never whitespace (so
/// `_normalizeAppShortName`'s trim + length-24 truncate is a no-op
/// regardless of the truncation boundary).
Gen<String> _genAppShortNameFixed() => (rng) {
      final len = rng.intBetween(1, 24);
      final chars = List<String>.generate(
        len,
        (_) => _kSafeNonSpaceChars[rng.nextInt(_kSafeNonSpaceChars.length)],
      );
      return chars.join();
    };

Gen<ExternalTool> _genExternalTool() => (rng) {
      final id = _trimFixed(_genFreeString(maxLen: 10)(rng));
      final label = _genFreeString(maxLen: 16)(rng); // no trim at all
      final executable = _trimFixed(_genFreeString(maxLen: 10)(rng));
      final argCount = rng.intBetween(0, 3);
      final args =
          List<String>.generate(argCount, (_) => _genFreeString(maxLen: 12)(rng));
      final mode = rng.pick(ToolLaunchMode.values);
      return ExternalTool(
        id: id,
        label: label,
        executable: executable,
        args: args,
        mode: mode,
      );
    };

Gen<List<ExternalTool>> _genExternalToolsList({int maxLen = 4}) => (rng) {
      final n = rng.intBetween(0, maxLen);
      return List<ExternalTool>.generate(n, (_) => _genExternalTool()(rng));
    };

const List<String> _kUndoActionKindPool = [
  'commit', 'discard', 'stagePartial', 'amend', 'stash', 'checkout',
];

Gen<Map<String, int>> _genUndoOverrides() => (rng) {
      final keyCount = rng.intBetween(0, _kUndoActionKindPool.length);
      final keys = rng.sample(_kUndoActionKindPool, keyCount);
      return {for (final k in keys) k: rng.intBetween(0, 3600)};
    };

/// Pre-normalized gitea tokens: lowercase-ascii, unique, non-empty keys;
/// trim-fixed (but not lowercased — `_stringMapOr` never lowercases
/// values) hostile-capable values.
Gen<Map<String, String>> _genGiteaTokens({int maxEntries = 4}) => (rng) {
      final n = rng.intBetween(0, maxEntries);
      final map = <String, String>{};
      for (var i = 0; i < n; i++) {
        final hostBody =
            genAscii(maxLen: 10)(rng).toLowerCase().replaceAll(' ', '-');
        final host = 'host$i-${hostBody.isEmpty ? 'x' : hostBody}';
        final token = _trimFixed(_genFreeString(maxLen: 16)(rng));
        map[host] = token;
      }
      return map;
    };

/// The set of `updateChannel` values that are a fixed point under
/// `BuildInfo.normalizeChannelId` REGARDLESS of which channel this test
/// binary happens to be running as ('beta'/'stable' always pass through
/// verbatim; the live build's own channel id is always safe too — this
/// is what makes 'dev' safe-or-not depending on context).
List<String> _channelSafeValues() =>
    <String>{'beta', 'stable', BuildInfo.channel.id}.toList();

/// A fuzzed, fully-valid `AppSettingsSnapshot` — every field is already a
/// fixed point under its own coercer/normalizer/clamp, so
/// `fromJson(toJson(x))` must reproduce `x` exactly.
Gen<AppSettingsSnapshot> _genValidSnapshot() => (rng) {
      final channelSafe = _channelSafeValues();
      return AppSettingsSnapshot(
        guardrailValue: rng.nextDouble(),
        aiReadOnlyDefault: rng.nextBool(),
        logoAnimatesWhenUnfocused: rng.nextBool(),
        telemetryRetentionDays: rng.intBetween(1, 365),
        telemetryRetentionMb: rng.intBetween(16, 4096),
        updateChannel: rng.pick(channelSafe),
        updateChannelExplicit: rng.nextBool(),
        crashReportingEnabled: rng.nextBool(),
        themeId: _genTrimFixedString()(rng),
        keybindingProfile: _genTrimFixedString()(rng),
        sidebarWidthPx: rng.intBetween(140, 380),
        sidebarPosition: rng.pick(const ['left', 'right']),
        utilityDrawerDefaultExpanded: rng.nextBool(),
        utilityDrawerHeightPx: rng.intBetween(120, 420),
        reduceMotion: rng.nextBool(),
        motionRate: rng.nextDouble() * 2.0,
        reduceMotionPhase: rng.nextDouble(),
        stashCabinetDefaultExpanded: rng.nextBool(),
        instantBlameHover: rng.nextBool(),
        autoSelectNewChanges: rng.nextBool(),
        diffMediaEnabled: rng.nextBool(),
        diffBinaryEnabled: rng.nextBool(),
        fetchOnlineIssuesOnBranchLoad: rng.nextBool(),
        rememberWorkInProgress: rng.nextBool(),
        hideAiFeatures: rng.nextBool(),
        undoWindowSeconds: rng.intBetween(0, 3600),
        undoWindowOverrides: _genUndoOverrides()(rng),
        fileSortGuide: rng.pick(const ['related', 'alphabetical', 'impact']),
        fileSortInverted: rng.nextBool(),
        issuesSortDescending: rng.nextBool(),
        tagsSortDescending: rng.nextBool(),
        commitStructure:
            rng.pick(const ['title_body', 'title_only', 'freeform']),
        commitVoice: rng.pick(const ['verb_led', 'descriptive', 'narrative']),
        commitCoverage:
            rng.pick(const ['essentials', 'balanced', 'everything']),
        logosPadX: rng.nextDouble(),
        logosPadY: rng.nextDouble(),
        appShortName: _genAppShortNameFixed()(rng),
        onboardingComplete: rng.nextBool(),
        bondExperimentEnabled: rng.nextBool(),
        bondDockOpenedOnce: rng.nextBool(),
        externalTools: _genExternalToolsList()(rng),
        changesPanelWidthPx: rng.intBetween(220, 520),
        wickExePath: _genFreeString(maxLen: 30)(rng),
        alphaMathPath: _genFreeString(maxLen: 30)(rng),
        giteaTokens: _genGiteaTokens()(rng),
      );
    };

/// A legacy-shaped JSON map: randomly includes/omits `updateChannel`,
/// `updateChannelExplicit`, `reduceMotion`, and `motionRate` — the two
/// independent inline migrations fromJson performs — plus occasional
/// unrecognised extra top-level keys (forward-compat noise a future
/// schema version might add).
Map<String, dynamic> _genLegacyJson(Rng rng) {
  final json = <String, dynamic>{};
  const channelCandidates = [
    'beta', 'stable', 'dev', 'BETA', '  stable  ', 'Dev', 'production',
    'release', 'quantum-channel', '', '   ',
  ];
  if (rng.nextBool()) {
    json['updateChannel'] = rng.nextInt(10) == 0
        ? genUnicodeHostile(maxLen: 8)(rng)
        : rng.pick(channelCandidates);
  }
  if (rng.nextBool()) {
    json['updateChannelExplicit'] = rng.nextBool();
  }
  if (rng.nextBool()) {
    json['reduceMotion'] = rng.nextBool();
  }
  if (rng.nextBool()) {
    json['motionRate'] = rng.nextDouble() * 2.0;
  }
  if (rng.nextBool()) {
    json['futureFieldFromNextVersion'] =
        rng.pick(<dynamic>[42, 'x', true, <dynamic>[1, 2], <String, dynamic>{'a': 1}]);
  }
  if (rng.nextBool()) {
    json['schemaVersion'] = rng.intBetween(1, 99);
  }
  return json;
}

// ── Equality helpers (AppSettingsSnapshot/ExternalTool have no `==`) ────

void _expectExternalToolsEqual(
  List<ExternalTool> expected,
  List<ExternalTool> actual,
  String ctx,
) {
  expect(actual.length, equals(expected.length),
      reason: '$ctx externalTools length mismatch');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i];
    final a = actual[i];
    expect(a.id, equals(e.id), reason: '$ctx externalTools[$i].id');
    expect(a.label, equals(e.label), reason: '$ctx externalTools[$i].label');
    expect(a.executable, equals(e.executable),
        reason: '$ctx externalTools[$i].executable');
    expect(a.args, equals(e.args), reason: '$ctx externalTools[$i].args');
    expect(a.mode, equals(e.mode), reason: '$ctx externalTools[$i].mode');
  }
}

void _expectSnapshotEquals(
  AppSettingsSnapshot expected,
  AppSettingsSnapshot actual, {
  String context = '',
}) {
  final ctx = context.isEmpty ? '' : '[$context] ';
  expect(actual.guardrailValue, equals(expected.guardrailValue),
      reason: '${ctx}guardrailValue');
  expect(actual.aiReadOnlyDefault, equals(expected.aiReadOnlyDefault),
      reason: '${ctx}aiReadOnlyDefault');
  expect(actual.logoAnimatesWhenUnfocused,
      equals(expected.logoAnimatesWhenUnfocused),
      reason: '${ctx}logoAnimatesWhenUnfocused');
  expect(actual.telemetryRetentionDays, equals(expected.telemetryRetentionDays),
      reason: '${ctx}telemetryRetentionDays');
  expect(actual.telemetryRetentionMb, equals(expected.telemetryRetentionMb),
      reason: '${ctx}telemetryRetentionMb');
  expect(actual.updateChannel, equals(expected.updateChannel),
      reason: '${ctx}updateChannel');
  expect(actual.updateChannelExplicit, equals(expected.updateChannelExplicit),
      reason: '${ctx}updateChannelExplicit');
  expect(actual.crashReportingEnabled, equals(expected.crashReportingEnabled),
      reason: '${ctx}crashReportingEnabled');
  expect(actual.themeId, equals(expected.themeId), reason: '${ctx}themeId');
  expect(actual.keybindingProfile, equals(expected.keybindingProfile),
      reason: '${ctx}keybindingProfile');
  expect(actual.sidebarWidthPx, equals(expected.sidebarWidthPx),
      reason: '${ctx}sidebarWidthPx');
  expect(actual.sidebarPosition, equals(expected.sidebarPosition),
      reason: '${ctx}sidebarPosition');
  expect(actual.utilityDrawerDefaultExpanded,
      equals(expected.utilityDrawerDefaultExpanded),
      reason: '${ctx}utilityDrawerDefaultExpanded');
  expect(actual.utilityDrawerHeightPx, equals(expected.utilityDrawerHeightPx),
      reason: '${ctx}utilityDrawerHeightPx');
  expect(actual.reduceMotion, equals(expected.reduceMotion),
      reason: '${ctx}reduceMotion');
  expect(actual.motionRate, equals(expected.motionRate),
      reason: '${ctx}motionRate');
  expect(actual.reduceMotionPhase, equals(expected.reduceMotionPhase),
      reason: '${ctx}reduceMotionPhase');
  expect(actual.stashCabinetDefaultExpanded,
      equals(expected.stashCabinetDefaultExpanded),
      reason: '${ctx}stashCabinetDefaultExpanded');
  expect(actual.instantBlameHover, equals(expected.instantBlameHover),
      reason: '${ctx}instantBlameHover');
  expect(actual.autoSelectNewChanges, equals(expected.autoSelectNewChanges),
      reason: '${ctx}autoSelectNewChanges');
  expect(actual.diffMediaEnabled, equals(expected.diffMediaEnabled),
      reason: '${ctx}diffMediaEnabled');
  expect(actual.diffBinaryEnabled, equals(expected.diffBinaryEnabled),
      reason: '${ctx}diffBinaryEnabled');
  expect(actual.fetchOnlineIssuesOnBranchLoad,
      equals(expected.fetchOnlineIssuesOnBranchLoad),
      reason: '${ctx}fetchOnlineIssuesOnBranchLoad');
  expect(actual.rememberWorkInProgress, equals(expected.rememberWorkInProgress),
      reason: '${ctx}rememberWorkInProgress');
  expect(actual.hideAiFeatures, equals(expected.hideAiFeatures),
      reason: '${ctx}hideAiFeatures');
  expect(actual.undoWindowSeconds, equals(expected.undoWindowSeconds),
      reason: '${ctx}undoWindowSeconds');
  expect(actual.undoWindowOverrides, equals(expected.undoWindowOverrides),
      reason: '${ctx}undoWindowOverrides');
  expect(actual.fileSortGuide, equals(expected.fileSortGuide),
      reason: '${ctx}fileSortGuide');
  expect(actual.fileSortInverted, equals(expected.fileSortInverted),
      reason: '${ctx}fileSortInverted');
  expect(actual.issuesSortDescending, equals(expected.issuesSortDescending),
      reason: '${ctx}issuesSortDescending');
  expect(actual.tagsSortDescending, equals(expected.tagsSortDescending),
      reason: '${ctx}tagsSortDescending');
  expect(actual.commitStructure, equals(expected.commitStructure),
      reason: '${ctx}commitStructure');
  expect(actual.commitVoice, equals(expected.commitVoice),
      reason: '${ctx}commitVoice');
  expect(actual.commitCoverage, equals(expected.commitCoverage),
      reason: '${ctx}commitCoverage');
  expect(actual.logosPadX, equals(expected.logosPadX),
      reason: '${ctx}logosPadX');
  expect(actual.logosPadY, equals(expected.logosPadY),
      reason: '${ctx}logosPadY');
  expect(actual.appShortName, equals(expected.appShortName),
      reason: '${ctx}appShortName');
  expect(actual.onboardingComplete, equals(expected.onboardingComplete),
      reason: '${ctx}onboardingComplete');
  expect(actual.bondExperimentEnabled, equals(expected.bondExperimentEnabled),
      reason: '${ctx}bondExperimentEnabled');
  expect(actual.bondDockOpenedOnce, equals(expected.bondDockOpenedOnce),
      reason: '${ctx}bondDockOpenedOnce');
  _expectExternalToolsEqual(expected.externalTools, actual.externalTools, ctx);
  expect(actual.changesPanelWidthPx, equals(expected.changesPanelWidthPx),
      reason: '${ctx}changesPanelWidthPx');
  expect(actual.wickExePath, equals(expected.wickExePath),
      reason: '${ctx}wickExePath');
  expect(actual.alphaMathPath, equals(expected.alphaMathPath),
      reason: '${ctx}alphaMathPath');
  expect(actual.giteaTokens, equals(expected.giteaTokens),
      reason: '${ctx}giteaTokens');
}

/// Feeds `AppSettingsSnapshot.fromJson` a map containing ONLY [key] set to
/// each of [garbageValues], and asserts: fromJson never throws, and the
/// resulting snapshot is field-for-field IDENTICAL to
/// `AppSettingsSnapshot.defaults()` — every corrupted/missing/wrong-typed
/// value for a single field, with nothing else present in the map,
/// cleanly falls back to the FULL default snapshot.
void _expectGarbageFieldDefaults(String key, List<dynamic> garbageValues) {
  final defaults = AppSettingsSnapshot.defaults();
  for (final garbage in garbageValues) {
    late AppSettingsSnapshot snap;
    expect(
      () => snap = AppSettingsSnapshot.fromJson(<String, dynamic>{key: garbage}),
      returnsNormally,
      reason: 'fromJson threw for {"$key": $garbage}',
    );
    _expectSnapshotEquals(defaults, snap, context: '$key <- $garbage');
  }
}

/// prop.dart's `forAll` is intentionally synchronous (`void Function`
/// check). The persistence group needs real `await`ed disk I/O per case,
/// so this is a minimal async sibling: same reproducibility contract
/// (one seed -> one deterministic sequence via `Rng.split()`), just
/// awaiting the check instead of calling it bare.
Future<void> _forAllAsync<T>(
  Gen<T> gen, {
  required Future<void> Function(T value) check,
  int count = 15,
  int seed = 0x5EED,
  String? describe,
}) async {
  final master = Rng(seed);
  for (var index = 0; index < count; index++) {
    final caseRng = master.split();
    final value = gen(caseRng);
    try {
      await check(value);
    } catch (error, stackTrace) {
      final label = describe == null ? '' : '$describe — ';
      // ignore: avoid_print
      print(
        '[prop-async] ${label}FAILED at seed=0x${seed.toRadixString(16)} '
        'index=$index\n[prop-async] value=$value',
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

void main() {
  group('law 1: full snapshot roundtrip — fromJson(toJson(x)) == x', () {
    test('fuzzed snapshots across every field roundtrip exactly', () {
      forAll<AppSettingsSnapshot>(
        _genValidSnapshot(),
        count: 300 * fuzzScale(),
        describe: 'snapshot roundtrip',
        check: (snap) {
          final restored = AppSettingsSnapshot.fromJson(snap.toJson());
          _expectSnapshotEquals(snap, restored);
        },
      );
    });

    test('AppSettingsSnapshot.defaults() itself roundtrips', () {
      final defaults = AppSettingsSnapshot.defaults();
      final restored = AppSettingsSnapshot.fromJson(defaults.toJson());
      _expectSnapshotEquals(defaults, restored, context: 'defaults()');
    });

    test('hostile unicode survives byte-for-byte in un-normalized fields',
        () {
      // NUL + fire emoji + zero-width-joiner + RTL mark + lone CR run —
      // every category gen.dart's hostile pool covers, concatenated into
      // one string. Built from plain-ASCII code-point integers rather
      // than pasted as literal characters — see gen.dart's file header
      // for why raw invisible/control/joining characters never belong
      // directly in source (this repo has been bitten by exactly that:
      // see the "NUL byte in source" incident notes).
      final hostilePrefix = String.fromCharCodes([
        0x0000, // NUL
        0x1F525, // fire emoji
        0x200D, // zero-width joiner
        0x200F, // RTL mark
        0x000D, 0x000D, // lone CR, twice
      ]);
      final hostile = '$hostilePrefix' 'plain-ish-tail';
      final snap = AppSettingsSnapshot.defaults().copyWith(
        wickExePath: hostile,
        alphaMathPath: hostile,
      );
      final tool = ExternalTool(
        id: 'tool1',
        label: hostile,
        executable: 'exe',
        args: [hostile],
        mode: ToolLaunchMode.detached,
      );
      final withTool =
          AppSettingsSnapshot.fromJson(snap.toJson()).copyWith(
        externalTools: [tool],
      );
      final restored =
          AppSettingsSnapshot.fromJson(withTool.toJson());
      expect(restored.wickExePath, equals(hostile));
      expect(restored.alphaMathPath, equals(hostile));
      expect(restored.externalTools.single.label, equals(hostile));
      expect(restored.externalTools.single.args.single, equals(hostile));
    });
  });

  group('law 2: coercion totality — every field defaults cleanly on garbage',
      () {
    // NOTE: deliberately excludes literal `true`/`false` — those are the
    // CORRECT type for a bool field, so `_boolOr` legitimately returns
    // them as-is rather than falling back to a default. Feeding a bool
    // field an actual bool isn't garbage at all, so it has no place in
    // a "garbage defaults cleanly" pool used generically across fields.
    final commonGarbage = <dynamic>[
      42, -7, 3.14, <dynamic>[], <dynamic>[1, 2],
      <String, dynamic>{}, <String, dynamic>{'a': 1}, null,
    ];

    test('bool fields default cleanly on any wrong-typed value', () {
      const boolFields = [
        'aiReadOnlyDefault', 'logoAnimatesWhenUnfocused',
        'crashReportingEnabled', 'utilityDrawerDefaultExpanded',
        'stashCabinetDefaultExpanded', 'instantBlameHover',
        'autoSelectNewChanges', 'fetchOnlineIssuesOnBranchLoad',
        'rememberWorkInProgress', 'hideAiFeatures', 'fileSortInverted',
        'reduceMotion', 'onboardingComplete', 'bondExperimentEnabled',
        'bondDockOpenedOnce',
        // diffMediaEnabled/diffBinaryEnabled/issuesSortDescending/
        // tagsSortDescending are already covered by
        // settings_store_migration_test.dart — not repeated here.
      ];
      for (final field in boolFields) {
        _expectGarbageFieldDefaults(
          field,
          [...commonGarbage, 'true', 'false', '1', '0'],
        );
      }
    });

    test(
      'int fields default cleanly on any wrong-typed value '
      '(non-finite doubles are covered separately below)',
      () {
        const intFields = [
          'telemetryRetentionDays', 'telemetryRetentionMb', 'sidebarWidthPx',
          'utilityDrawerHeightPx', 'undoWindowSeconds', 'changesPanelWidthPx',
        ];
        for (final field in intFields) {
          _expectGarbageFieldDefaults(
            field,
            ['nope', true, false, <dynamic>[], <dynamic>[1, 2],
              <String, dynamic>{}, null, '42', ''],
          );
        }
      },
    );

    test('double fields default cleanly on any wrong-typed value', () {
      const doubleFields = [
        'guardrailValue', 'motionRate', 'reduceMotionPhase', 'logosPadX',
        'logosPadY',
      ];
      for (final field in doubleFields) {
        _expectGarbageFieldDefaults(
          field,
          ['nope', true, false, <dynamic>[], <String, dynamic>{}, null, '0.5'],
        );
      }
    });

    test('plain string fields (no enum constraint) default cleanly on '
        'wrong type / blank', () {
      const stringFields = ['themeId', 'keybindingProfile'];
      for (final field in stringFields) {
        _expectGarbageFieldDefaults(
          field,
          [42, true, <dynamic>[], <String, dynamic>{}, null, '', '   ',
            '\t\n'],
        );
      }
    });

    test('enum-normalized string fields default cleanly on wrong type / '
        'unknown / blank value', () {
      const enumFields = [
        'sidebarPosition', 'fileSortGuide', 'commitStructure', 'commitVoice',
        'commitCoverage',
      ];
      final garbage = <dynamic>[
        42, true, <dynamic>[], <String, dynamic>{}, null, '', '   ',
        'totally-unknown-value', 'RIGHT-ish',
        String.fromCharCodes([0x200D, 0x1F525, 0]), // hostile, matches nothing
      ];
      for (final field in enumFields) {
        _expectGarbageFieldDefaults(field, garbage);
      }
    });

    test('updateChannel defaults to the current build channel on wrong '
        'type / unknown value', () {
      _expectGarbageFieldDefaults('updateChannel', [
        42, true, <dynamic>[], <String, dynamic>{}, null, '', '   ',
        'quantum-channel',
      ]);
    });

    test('appShortName: garbage defaults to "Manifold"; an over-length '
        'valid value truncates to exactly 24 chars', () {
      _expectGarbageFieldDefaults('appShortName', [
        42, true, <dynamic>[], <String, dynamic>{}, null, '', '   ', '\t',
      ]);

      // Not garbage — a real, over-length user-typed name. Locks in the
      // truncation boundary documented on _normalizeAppShortName.
      final longName = 'A' * 40;
      final snap =
          AppSettingsSnapshot.fromJson({'appShortName': longName});
      expect(snap.appShortName, equals('A' * 24));
      expect(snap.appShortName.length, equals(24));
    });

    test('externalTools: wrong outer type defaults to an empty list', () {
      _expectGarbageFieldDefaults('externalTools', [
        42, true, 'nope', <String, dynamic>{}, null,
      ]);
    });

    test('externalTools: malformed entries inside a valid list are '
        'dropped; well-formed-enough entries survive with sane defaults',
        () {
      final json = <String, dynamic>{
        'externalTools': <dynamic>[
          {
            'id': 'a1', 'label': 'Claude', 'executable': 'claude',
            'args': ['{path}'], 'mode': 'newTerminal',
          },
          'not-a-map-entry', // dropped: not a Map
          42, // dropped: not a Map
          {'label': 'no executable at all'}, // dropped: missing executable
          {'executable': '   '}, // dropped: blank executable
          {'executable': 'code', 'args': 'not-a-list'}, // args -> []
          {'executable': 'vim', 'args': [1, 'ok', null, 'two']}, // filtered
          {'executable': 'zed', 'mode': 'bogus-mode'}, // -> newTerminal
          {'executable': 'fork', 'id': ''}, // blank id -> auto-generated
        ],
      };
      final snap = AppSettingsSnapshot.fromJson(json);
      expect(snap.externalTools.length, equals(5),
          reason: 'expected exactly the 5 well-formed-enough entries to '
              'survive, got: ${snap.externalTools.map((t) => t.executable)}');
      expect(snap.externalTools[0].id, equals('a1'));
      expect(snap.externalTools[0].executable, equals('claude'));
      expect(snap.externalTools[1].executable, equals('code'));
      expect(snap.externalTools[1].args, isEmpty);
      expect(snap.externalTools[2].executable, equals('vim'));
      expect(snap.externalTools[2].args, equals(['ok', 'two']));
      expect(snap.externalTools[3].executable, equals('zed'));
      expect(snap.externalTools[3].mode, equals(ToolLaunchMode.newTerminal));
      expect(snap.externalTools[4].executable, equals('fork'));
      expect(snap.externalTools[4].id, isNotEmpty);
    });

    test('undoWindowOverrides: wrong outer type defaults to an empty map',
        () {
      _expectGarbageFieldDefaults('undoWindowOverrides', [
        42, true, 'nope', <dynamic>[], null,
      ]);
    });

    test('undoWindowOverrides: mixed valid/invalid entries — only '
        'in-range int-valued string keys survive', () {
      final json = <String, dynamic>{
        'undoWindowOverrides': <dynamic, dynamic>{
          'commit': 10, // valid
          'discard': 3600, // valid, exactly the upper clamp bound
          'amend': 3601, // just over the bound -> dropped (not clamped)
          'stash': -1, // negative -> dropped
          'bad-type': 'nope', // non-num value -> dropped
          42: 5, // non-string key -> dropped
          'fine-double': 7.0, // whole-number double -> kept, toInt()=7
        },
      };
      final snap = AppSettingsSnapshot.fromJson(json);
      expect(
        snap.undoWindowOverrides,
        equals({'commit': 10, 'discard': 3600, 'fine-double': 7}),
      );
    });

    test('property: any finite int fed to a clamped int field always '
        'lands in-range', () {
      const intBounds = {
        'telemetryRetentionDays': (1, 365),
        'telemetryRetentionMb': (16, 4096),
        'sidebarWidthPx': (140, 380),
        'utilityDrawerHeightPx': (120, 420),
        'undoWindowSeconds': (0, 3600),
        'changesPanelWidthPx': (220, 520),
      };
      forAll<int>(
        genInt(min: -1000000, max: 1000000),
        count: 200 * fuzzScale(),
        describe: 'int clamp totality',
        check: (raw) {
          for (final entry in intBounds.entries) {
            final (lo, hi) = entry.value;
            final snap =
                AppSettingsSnapshot.fromJson({entry.key: raw});
            final value = switch (entry.key) {
              'telemetryRetentionDays' => snap.telemetryRetentionDays,
              'telemetryRetentionMb' => snap.telemetryRetentionMb,
              'sidebarWidthPx' => snap.sidebarWidthPx,
              'utilityDrawerHeightPx' => snap.utilityDrawerHeightPx,
              'undoWindowSeconds' => snap.undoWindowSeconds,
              'changesPanelWidthPx' => snap.changesPanelWidthPx,
              _ => throw StateError('unreachable'),
            };
            expect(value, inInclusiveRange(lo, hi),
                reason: '${entry.key} <- $raw produced out-of-range $value');
            expect(value, equals(raw.clamp(lo, hi)),
                reason: '${entry.key} <- $raw expected '
                    '${raw.clamp(lo, hi)} got $value');
          }
        },
      );
    });

    test('property: any finite double fed to a clamped double field '
        'always lands in-range', () {
      const doubleBounds = {
        'guardrailValue': (0.0, 1.0),
        'motionRate': (0.0, 2.0),
        'reduceMotionPhase': (0.0, 1.0),
        'logosPadX': (0.0, 1.0),
        'logosPadY': (0.0, 1.0),
      };
      forAll<double>(
        genDouble(min: -1e9, max: 1e9),
        count: 200 * fuzzScale(),
        describe: 'double clamp totality',
        check: (raw) {
          for (final entry in doubleBounds.entries) {
            final (lo, hi) = entry.value;
            final snap =
                AppSettingsSnapshot.fromJson({entry.key: raw});
            final value = switch (entry.key) {
              'guardrailValue' => snap.guardrailValue,
              'motionRate' => snap.motionRate,
              'reduceMotionPhase' => snap.reduceMotionPhase,
              'logosPadX' => snap.logosPadX,
              'logosPadY' => snap.logosPadY,
              _ => throw StateError('unreachable'),
            };
            expect(value, inInclusiveRange(lo, hi),
                reason: '${entry.key} <- $raw produced out-of-range $value');
          }
        },
      );
    });

    test('double fields: NaN never throws — num.clamp treats NaN as '
        '"greater than any bound" via compareTo, so it silently becomes '
        'the field\'s UPPER bound (a real quirk, not a crash; locked in '
        'here so a future refactor can\'t silently change it unnoticed)',
        () {
      expect(
        AppSettingsSnapshot.fromJson({'guardrailValue': double.nan})
            .guardrailValue,
        equals(1.0),
      );
      expect(
        AppSettingsSnapshot.fromJson({'motionRate': double.nan}).motionRate,
        equals(2.0),
      );
      expect(
        AppSettingsSnapshot.fromJson({'logosPadX': double.nan}).logosPadX,
        equals(1.0),
      );
    });

    test('every field simultaneously corrupted with a wrong type -> '
        'clean full-default snapshot, no throw', () {
      final kitchenSinkCorruptJson = <String, dynamic>{
        'guardrailValue': 'not-a-number',
        'aiReadOnlyDefault': 'yes',
        'logoAnimatesWhenUnfocused': 1,
        'telemetryRetentionDays': <dynamic>[1, 2, 3],
        'telemetryRetentionMb': <String, dynamic>{'x': 1},
        'updateChannel': 999,
        'updateChannelExplicit': 'true',
        'crashReportingEnabled': null,
        'themeId': 12345,
        'keybindingProfile': true,
        'sidebarWidthPx': 'wide',
        'sidebarPosition': 42,
        'utilityDrawerDefaultExpanded': 'expanded',
        'utilityDrawerHeightPx': false,
        'reduceMotion': 'off',
        'motionRate': 'fast',
        'reduceMotionPhase': <dynamic>[0.5],
        'stashCabinetDefaultExpanded': 0,
        'instantBlameHover': 'never',
        'autoSelectNewChanges': <String, dynamic>{},
        'diffMediaEnabled': 'sometimes',
        'diffBinaryEnabled': 2,
        'fetchOnlineIssuesOnBranchLoad': 'always',
        'rememberWorkInProgress': null,
        'hideAiFeatures': 'nope',
        'undoWindowSeconds': 'long',
        'undoWindowOverrides': <dynamic>[1, 2, 3],
        'fileSortGuide': false,
        'fileSortInverted': 'inverted',
        'issuesSortDescending': 'desc',
        'tagsSortDescending': 3,
        'commitStructure': 7,
        'commitVoice': <dynamic>[],
        'commitCoverage': <String, dynamic>{},
        'logosPadX': 'half',
        'logosPadY': true,
        'appShortName': 8675309,
        'onboardingComplete': 'complete',
        'bondExperimentEnabled': 'maybe',
        'bondDockOpenedOnce': 1.5,
        'externalTools': <String, dynamic>{'not': 'a list'},
        'changesPanelWidthPx': 'wide',
        // null is the ONE safe garbage value for wickExePath — see the
        // dedicated known-bug test below for the unsafe-cast case.
        'wickExePath': null,
        'alphaMathPath': 5,
        'giteaTokens': 123,
      };
      late AppSettingsSnapshot snap;
      expect(
        () => snap = AppSettingsSnapshot.fromJson(kitchenSinkCorruptJson),
        returnsNormally,
        reason: 'fromJson threw on: $kitchenSinkCorruptJson',
      );
      _expectSnapshotEquals(AppSettingsSnapshot.defaults(), snap,
          context: 'kitchen-sink corruption');
    });

    group('unguarded num.toInt() on non-finite doubles', () {
      const affectedIntFields = [
        'telemetryRetentionDays', 'telemetryRetentionMb', 'sidebarWidthPx',
        'utilityDrawerHeightPx', 'undoWindowSeconds', 'changesPanelWidthPx',
      ];
      for (final field in affectedIntFields) {
        test(
          '$field = double.infinity throws UnsupportedError instead of '
          'defaulting',
          () {
            expect(
              () => AppSettingsSnapshot.fromJson({field: double.infinity}),
              throwsA(isA<UnsupportedError>()),
            );
          },
          skip: 'known bug: SettingsStore._intOr calls value.toInt() on any '
              'num with no finiteness check; jsonDecode(\'{"x": 1e400}\') '
              'legitimately decodes to double.infinity with no parse '
              'error, so a hand-edited settings.json with an overflowing '
              'exponent crashes fromJson with UnsupportedError instead of '
              'falling back to the field default',
        );
      }

      test(
        'undoWindowOverrides entry = double.nan throws UnsupportedError',
        () {
          expect(
            () => AppSettingsSnapshot.fromJson({
              'undoWindowOverrides': {'commit': double.nan},
            }),
            throwsA(isA<UnsupportedError>()),
          );
        },
        skip: 'known bug: same root cause as the sibling _intOr bug above '
            '— SettingsStore._intMapOr also calls v.toInt() on any num '
            'entry value with no finiteness guard',
      );
    });

    test(
      'wickExePath with a non-null, non-String value throws TypeError '
      'instead of defaulting to empty (contrast: the very next field, '
      'alphaMathPath, handles the identical shape of corruption safely '
      'via an `is String` check)',
      () {
        expect(
          () => AppSettingsSnapshot.fromJson({'wickExePath': 42}),
          throwsA(isA<TypeError>()),
        );
      },
      skip: 'known bug: AppSettingsSnapshot.fromJson does '
          "json['wickExePath'] as String? ?? '' — an unsafe cast; null "
          'succeeds, but any other type throws a raw TypeError uncaught '
          'anywhere in fromJson',
    );
  });

  group('law 3: migration idempotence + stability', () {
    test('legacy-shaped JSON migrates correctly and is a stable fixed '
        'point under re-serialization', () {
      forAll<Map<String, dynamic>>(
        _genLegacyJson,
        count: 300 * fuzzScale(),
        describe: 'legacy migration idempotence',
        check: (legacyJson) {
          late AppSettingsSnapshot migrated;
          expect(
            () => migrated = AppSettingsSnapshot.fromJson(legacyJson),
            returnsNormally,
            reason: 'fromJson threw on legacy map: $legacyJson',
          );

          // updateChannelExplicit migration, re-derived independently
          // from the same legacy JSON (mirrors the production rule so a
          // regression is caught structurally, not by copy-pasted cases
          // already covered in settings_store_migration_test.dart).
          if (legacyJson.containsKey('updateChannelExplicit')) {
            final raw = legacyJson['updateChannelExplicit'];
            expect(migrated.updateChannelExplicit,
                equals(raw is bool ? raw : false),
                reason: 'explicit-flag-present branch for: $legacyJson');
          } else {
            final rawChannel = legacyJson['updateChannel'];
            final expectedExplicit = rawChannel is String &&
                (rawChannel.trim().toLowerCase() == 'beta' ||
                    rawChannel.trim().toLowerCase() == 'dev');
            expect(migrated.updateChannelExplicit, equals(expectedExplicit),
                reason: 'legacy channel inference for: $legacyJson');
          }

          // motionRate<->reduceMotion migration — untested anywhere else.
          if (legacyJson.containsKey('motionRate')) {
            final raw = (legacyJson['motionRate'] as num).toDouble();
            expect(migrated.motionRate, equals(raw.clamp(0.0, 2.0)),
                reason: 'motionRate-present branch for: $legacyJson');
          } else {
            final legacyReduceMotion =
                (legacyJson['reduceMotion'] as bool?) ?? false;
            expect(migrated.motionRate,
                equals(legacyReduceMotion ? 0.0 : 1.0),
                reason: 'legacy reduceMotion->motionRate migration for: '
                    '$legacyJson');
          }

          // Fixed point: re-parsing the migrated snapshot's own toJson()
          // output must reproduce the identical snapshot — no further
          // drift. This is the untested angle Law 3 exists for.
          final restabilized =
              AppSettingsSnapshot.fromJson(migrated.toJson());
          _expectSnapshotEquals(migrated, restabilized,
              context: 'migration idempotence for: $legacyJson');
        },
      );
    });

    test('unknown top-level keys are ignored (forward-compat), never '
        'thrown on', () {
      final json = <String, dynamic>{
        'themeId': 'aether',
        'schemaVersionFromTheFuture': 999,
        'aBrandNewFieldWeHaventShippedYet': {'nested': true},
        'anotherOne': [1, 2, 3],
      };
      late AppSettingsSnapshot snap;
      expect(() => snap = AppSettingsSnapshot.fromJson(json),
          returnsNormally);
      expect(snap.themeId, equals('aether'));
      // Every other field still falls back to its normal default since
      // nothing else recognisable was in the map.
      _expectSnapshotEquals(
        AppSettingsSnapshot.defaults().copyWith(themeId: 'aether'),
        snap,
        context: 'unknown keys ignored',
      );
    });
  });

  group('law 5 (pure half): empty/first-run defaults', () {
    test('fromJson({}) yields the full default snapshot, no throw', () {
      late AppSettingsSnapshot snap;
      expect(() => snap = AppSettingsSnapshot.fromJson(const {}),
          returnsNormally);
      _expectSnapshotEquals(AppSettingsSnapshot.defaults(), snap,
          context: 'fromJson({})');
    });
  });

  group('law 4 + law 5 (disk half): SettingsStore persist/load/'
      'invalidateCache through the real file store', () {
    late Directory dataDir;

    setUpAll(() {
      final override = Platform.environment['GDPU_DATA_DIR'];
      if (override == null || override.trim().isEmpty) {
        fail(
          'GDPU_DATA_DIR is not set. SettingsStore always persists to a '
          'SINGLE fixed file (<gdpuDataDir>/settings.json) with no '
          'per-test uniquification — running this group without '
          'redirecting gdpuDataDir would read/write the real developer '
          'settings file. Re-run with e.g.:\n'
          '  GDPU_DATA_DIR=/tmp/gdpu-settings-test flutter test '
          'test/fuzz/settings_store_roundtrip_test.dart',
        );
      }
    });

    Future<File> settingsFile() async {
      dataDir = await StoragePaths.gdpuDataDir();
      return File('${dataDir.path}${Platform.pathSeparator}settings.json');
    }

    setUp(() async {
      SettingsStore.invalidateCache();
      final file = await settingsFile();
      if (await file.exists()) await file.delete();
    });

    tearDown(() async {
      SettingsStore.invalidateCache();
      final file = await settingsFile();
      if (await file.exists()) await file.delete();
    });

    test('persist then load round-trips a fuzzed snapshot exactly through '
        'real jsonEncode/jsonDecode + disk I/O', () async {
      await _forAllAsync<AppSettingsSnapshot>(
        _genValidSnapshot(),
        count: 15 * fuzzScale(),
        describe: 'persist/load roundtrip',
        check: (snap) async {
          await SettingsStore.persist(snap);
          SettingsStore.invalidateCache(); // force a real disk re-read
          final loaded = await SettingsStore.load();
          _expectSnapshotEquals(snap, loaded, context: 'persist/load');
        },
      );
    });

    test('invalidateCache then load still returns the persisted value '
        '(cache correctness)', () async {
      final snap = _genValidSnapshot()(Rng(0xABCDEF));
      await SettingsStore.persist(snap);
      final cachedLoad = await SettingsStore.load(); // memoised fast path
      _expectSnapshotEquals(snap, cachedLoad, context: 'memoised load');

      SettingsStore.invalidateCache();
      final freshLoad = await SettingsStore.load(); // real disk re-read
      _expectSnapshotEquals(snap, freshLoad, context: 'post-invalidate load');
    });

    test('load() with no stored value yields the full default snapshot '
        'without throwing, and persists it so the next load is stable',
        () async {
      final loaded = await SettingsStore.load();
      _expectSnapshotEquals(AppSettingsSnapshot.defaults(), loaded,
          context: 'first-run load');

      final file = await settingsFile();
      expect(await file.exists(), isTrue,
          reason: 'first load() should persist the defaults so '
              'subsequent writes do not race on create');

      // Second load (still cached) must be the identical defaults too.
      final loadedAgain = await SettingsStore.load();
      _expectSnapshotEquals(AppSettingsSnapshot.defaults(), loadedAgain,
          context: 'second first-run load');
    });

    test('a malformed (non-object) settings.json on disk falls back to '
        'the full default snapshot without throwing', () async {
      final file = await settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString('not valid json at all {{{');
      SettingsStore.invalidateCache();

      final loaded = await SettingsStore.load();
      _expectSnapshotEquals(AppSettingsSnapshot.defaults(), loaded,
          context: 'malformed settings.json on disk');
    });
    // Skip (not fail) the disk-half when GDPU_DATA_DIR is unset: SettingsStore
    // persists to ONE fixed <gdpuDataDir>/settings.json, so without the
    // override these tests would touch the real developer settings file. A
    // clean default `flutter test` therefore skips this group; set
    // GDPU_DATA_DIR to a scratch dir to actually exercise disk persistence.
  }, skip: (Platform.environment['GDPU_DATA_DIR'] ?? '').trim().isEmpty
      ? 'GDPU_DATA_DIR unset — disk-persistence tests skipped to protect the '
          'real settings.json; set it to a scratch dir to run them.'
      : null);
}
