// Round-trip coverage for the museQuiver field on AiSettingsSnapshot.
// The quiver persistence path has the most tolerant decode in the
// settings store: empty/missing → defaults, malformed entries → silent
// drop, partial-entry → skip-just-that-one. These tests pin the
// fallback semantics so future schema tweaks don't quietly break
// users' saved loadouts.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai_settings_store.dart';
import 'package:git_desktop/backend/dtos.dart';

Map<String, dynamic> _baseJson({
  Object? museQuiver = const _Missing(),
  Object? museStrandOrder = const _Missing(),
}) {
  final defaults = AiSettingsSnapshot.defaults();
  final json = <String, dynamic>{
    'modelSelections': defaults.modelSelections,
    'modelCategoryLabels': defaults.modelCategoryLabels,
    'reasoningEfforts': defaults.reasoningEfforts,
    'commitMessageModelCategoryId': defaults.commitMessageModelCategoryId,
    'reviewCommitModelCategoryId': defaults.reviewCommitModelCategoryId,
    'reviewCommitDoubleCheckEnabled': defaults.reviewCommitDoubleCheckEnabled,
    'museBrainstormModelCategoryId': defaults.museBrainstormModelCategoryId,
    'museSynthesisModelCategoryId': defaults.museSynthesisModelCategoryId,
    'presentModelCategoryId': defaults.presentModelCategoryId,
  };
  if (museQuiver is! _Missing) json['museQuiver'] = museQuiver;
  if (museStrandOrder is! _Missing) json['museStrandOrder'] = museStrandOrder;
  return json;
}

class _Missing {
  const _Missing();
}

void main() {
  group('AiSettingsSnapshot.museQuiver', () {
    test('missing key → default 4-strand quiver', () {
      final snap = AiSettingsSnapshot.fromJson(_baseJson());
      expect(snap.museQuiver, isNotEmpty);
      expect(snap.museQuiver.length, defaultMuseQuiver().length);
      expect(
        snap.museQuiver.map((e) => e.kind).toList(),
        defaultMuseQuiver().map((e) => e.kind).toList(),
      );
    });

    test('empty list → default 4-strand quiver', () {
      final snap = AiSettingsSnapshot.fromJson(_baseJson(museQuiver: const []));
      expect(snap.museQuiver.length, defaultMuseQuiver().length);
    });

    test('non-list value → default 4-strand quiver', () {
      final snap = AiSettingsSnapshot.fromJson(
        _baseJson(museQuiver: 'corrupt'),
      );
      expect(snap.museQuiver.length, defaultMuseQuiver().length);
    });

    test('valid loadout survives round-trip', () {
      const original = AiSettingsSnapshot(
        modelSelections: {},
        modelCategoryLabels: {'quality': 'Quality', 'fast': 'Fast'},
        commitMessageModelCategoryId: 'quality',
        reviewCommitModelCategoryId: 'quality',
        reviewCommitDoubleCheckEnabled: false,
        museBrainstormModelCategoryId: 'fast',
        museSynthesisModelCategoryId: 'quality',
        presentModelCategoryId: 'quality',
        museQuiver: [
          MuseQuiverEntry(kind: MuseStrandKind.ghost, count: 1),
          MuseQuiverEntry(kind: MuseStrandKind.fever, count: 1),
          MuseQuiverEntry(kind: MuseStrandKind.mirror, count: 1),
        ],
      );
      final restored = AiSettingsSnapshot.fromJson(original.toJson());
      expect(restored.museQuiver.length, 3);
      expect(restored.museQuiver[0].kind, MuseStrandKind.ghost);
      expect(restored.museQuiver[1].kind, MuseStrandKind.fever);
      expect(restored.museQuiver[2].kind, MuseStrandKind.mirror);
    });

    test('malformed entry is silently dropped, siblings preserved', () {
      // A corrupted entry in the middle of the list shouldn't poison
      // the others. Decoder skips the bad one, keeps the rest.
      final snap = AiSettingsSnapshot.fromJson(_baseJson(museQuiver: [
        {'kind': 'spark', 'count': 1},
        {'kind': 'not_a_real_strand', 'count': 1},
        {'kind': 'fever', 'count': 1},
        'not an object at all',
        {'kind': 'horizon', 'count': 1},
      ]));
      // Three valid entries survive: spark, fever, horizon.
      expect(snap.museQuiver.length, 3);
      expect(snap.museQuiver.map((e) => e.kind).toList(), [
        MuseStrandKind.spark,
        MuseStrandKind.fever,
        MuseStrandKind.horizon,
      ]);
    });

    test('all entries malformed → fall back to defaults', () {
      // When nothing parses cleanly the empty result triggers the
      // same "empty → default" branch as a missing key.
      final snap = AiSettingsSnapshot.fromJson(_baseJson(museQuiver: const [
        {'kind': 'mystery'},
        'garbage',
        42,
      ]));
      expect(snap.museQuiver.length, defaultMuseQuiver().length);
    });

    test('count is clamped to [1, 5]', () {
      final snap = AiSettingsSnapshot.fromJson(_baseJson(museQuiver: [
        {'kind': 'spark', 'count': 0},
        {'kind': 'fever', 'count': 999},
        {'kind': 'echo', 'count': -3},
      ]));
      expect(snap.museQuiver.length, 3);
      expect(snap.museQuiver[0].count, 1); // 0 clamps up
      expect(snap.museQuiver[1].count, 5); // 999 clamps down
      expect(snap.museQuiver[2].count, 1); // -3 clamps up
    });

    test('non-int count → defaults to 1', () {
      final snap = AiSettingsSnapshot.fromJson(_baseJson(museQuiver: [
        {'kind': 'spark', 'count': 'two'},
        {'kind': 'fever'},
      ]));
      expect(snap.museQuiver.length, 2);
      expect(snap.museQuiver[0].count, 1);
      expect(snap.museQuiver[1].count, 1);
    });

    test('all 8 strand kinds round-trip cleanly', () {
      final all = MuseStrandKind.values
          .map((k) => MuseQuiverEntry(kind: k, count: 1))
          .toList();
      final snap = AiSettingsSnapshot.fromJson(
        AiSettingsSnapshot(
          modelSelections: const {},
          modelCategoryLabels: const {},
          commitMessageModelCategoryId: 'quality',
          reviewCommitModelCategoryId: 'quality',
          reviewCommitDoubleCheckEnabled: false,
          museBrainstormModelCategoryId: 'fast',
          museSynthesisModelCategoryId: 'quality',
          presentModelCategoryId: 'quality',
          museQuiver: all,
        ).toJson(),
      );
      expect(snap.museQuiver.length, MuseStrandKind.values.length);
      expect(
        snap.museQuiver.map((e) => e.kind).toSet(),
        MuseStrandKind.values.toSet(),
      );
    });
  });

  group('AiSettingsSnapshot.museStrandOrder', () {
    test('missing key → canonical display order', () {
      final snap = AiSettingsSnapshot.fromJson(_baseJson());
      expect(snap.museStrandOrder, kMuseStrandDisplayOrder);
    });

    test('non-list value → canonical display order', () {
      final snap =
          AiSettingsSnapshot.fromJson(_baseJson(museStrandOrder: 'corrupt'));
      expect(snap.museStrandOrder, kMuseStrandDisplayOrder);
    });

    test('valid full order round-trips verbatim', () {
      const custom = ['fever', 'mirror', 'spark', 'ghost'];
      final rest = MuseStrandKind.values
          .where((k) => !custom.contains(museStrandLabel(k)))
          .map(museStrandLabel)
          .toList();
      final full = [...custom, ...rest];
      final snap =
          AiSettingsSnapshot.fromJson(_baseJson(museStrandOrder: full));
      expect(
        snap.museStrandOrder.map(museStrandLabel).toList(),
        full,
      );
    });

    test('partial order completes with missing strands in canonical order',
        () {
      // Only two strands listed — the other six fill in behind them,
      // each exactly once, in kMuseStrandDisplayOrder sequence.
      final snap = AiSettingsSnapshot.fromJson(
        _baseJson(museStrandOrder: const ['fever', 'spark']),
      );
      expect(snap.museStrandOrder.length, MuseStrandKind.values.length);
      expect(snap.museStrandOrder[0], MuseStrandKind.fever);
      expect(snap.museStrandOrder[1], MuseStrandKind.spark);
      expect(
        snap.museStrandOrder.toSet(),
        MuseStrandKind.values.toSet(),
      );
    });

    test('unknown + duplicate labels are dropped, order still complete', () {
      final snap = AiSettingsSnapshot.fromJson(_baseJson(museStrandOrder: [
        'mirror',
        'not_a_strand',
        'mirror', // duplicate — ignored
        42, // non-string — ignored
        'ghost',
      ]));
      expect(snap.museStrandOrder.length, MuseStrandKind.values.length);
      expect(snap.museStrandOrder[0], MuseStrandKind.mirror);
      expect(snap.museStrandOrder[1], MuseStrandKind.ghost);
      expect(
        snap.museStrandOrder.toSet(),
        MuseStrandKind.values.toSet(),
      );
    });

    test('toJson emits string labels', () {
      final snap = AiSettingsSnapshot.defaults();
      final json = snap.toJson();
      expect(json['museStrandOrder'],
          kMuseStrandDisplayOrder.map(museStrandLabel).toList());
    });
  });

  group('normalizeMuseStrandOrder', () {
    test('empty input → canonical order', () {
      expect(normalizeMuseStrandOrder(const []), kMuseStrandDisplayOrder);
    });

    test('always returns every strand exactly once', () {
      final result = normalizeMuseStrandOrder(const [
        MuseStrandKind.fever,
        MuseStrandKind.fever, // duplicate
        MuseStrandKind.spark,
      ]);
      expect(result.length, MuseStrandKind.values.length);
      expect(result.toSet(), MuseStrandKind.values.toSet());
      expect(result[0], MuseStrandKind.fever);
      expect(result[1], MuseStrandKind.spark);
    });
  });
}
