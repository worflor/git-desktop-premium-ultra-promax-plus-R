// Fidelity proof for the Repo X-Ray card i18n boundary.
//
// `repository_xray.dart`'s card generator composes structure and
// delegates every user-facing title, claim, and evidence label/detail to
// an `XrayCardStrings`. This test drives the SLANG-backed implementation
// (the production path, `SlangXrayCardStrings`) and asserts that the
// rendered English is byte-identical to the original hardcoded prose —
// the expectations below are lifted verbatim from the pre-refactor
// literals in `_buildCards`.
//
// Two complementary checks:
//   1. The slang render equals the verbatim-English default render
//      (`EnglishXrayCardStrings`), which reproduces the old code.
//   2. Hand-derived exact strings, so both paths can't silently drift
//      together.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/repository_xray_strings.dart';
import 'package:git_desktop/ui/xray_card_text.dart';

const _en = EnglishXrayCardStrings();
const _slang = SlangXrayCardStrings();

void main() {
  // Exercises every member across each branching input (singular/plural,
  // raw/filtered, simple/broad). The single most important assertion:
  // the slang path is byte-identical to the verbatim-English path (which
  // is the old code, unchanged).
  group('slang render == verbatim-English render', () {
    void same(String Function(XrayCardStrings s) f, String label) {
      test(label, () {
        expect(
          f(_slang),
          f(_en),
          reason: 'slang templates must reproduce the English render',
        );
      });
    }

    // Hidden-refs card.
    same((s) => s.hiddenRefsTitle, 'hiddenRefsTitle');
    same((s) => s.hiddenRefsClaim(1), 'hiddenRefsClaim(1)');
    same((s) => s.hiddenRefsClaim(4), 'hiddenRefsClaim(4)');
    same((s) => s.hiddenRefsEvidenceLabel, 'hiddenRefsEvidenceLabel');
    same((s) => s.hiddenRefsEvidenceDetail(3), 'hiddenRefsEvidenceDetail(3)');
    same((s) => s.namespacesLabel, 'namespacesLabel');

    // Machine-history card.
    same((s) => s.machineHistoryTitle, 'machineHistoryTitle');
    same((s) => s.machineHistoryClaim, 'machineHistoryClaim');
    same((s) => s.rawVsFilteredLabel, 'rawVsFilteredLabel');
    same((s) => s.rawVsFilteredDetail(raw: 200, filtered: 40),
        'rawVsFilteredDetail');
    same((s) => s.machineCommitsLabel, 'machineCommitsLabel');
    same((s) => s.machineCommitsDetail(160), 'machineCommitsDetail');

    // Migration card.
    same((s) => s.migrationTitle, 'migrationTitle');
    same((s) => s.migrationClaim(older: 'apps/desktop', newer: 'apps/desktop-flutter'),
        'migrationClaim');
    same((s) => s.migrationStratumDetail(touches: 42, lastActive: '2026-04-20'),
        'migrationStratumDetail');

    // Single-owner-hotspot card.
    same((s) => s.singleOwnerTitle, 'singleOwnerTitle');
    same((s) => s.singleOwnerClaim(path: 'lib/main.dart', kind: 'file'),
        'singleOwnerClaim(file)');
    same((s) => s.singleOwnerClaim(path: 'lib/', kind: 'directory'),
        'singleOwnerClaim(directory)');
    same((s) => s.touchCountLabel, 'touchCountLabel');
    same((s) => s.singleOwnerTouchDetail(count: 12, raw: true),
        'singleOwnerTouchDetail(raw)');
    same((s) => s.singleOwnerTouchDetail(count: 12, raw: false),
        'singleOwnerTouchDetail(filtered)');
    same((s) => s.ownerCountLabel, 'ownerCountLabel');
    same((s) => s.ownerCountDetail(1), 'ownerCountDetail');

    // No-tags card.
    same((s) => s.noTagsTitle, 'noTagsTitle');
    same((s) => s.noTagsClaim, 'noTagsClaim');
    same((s) => s.tagCountLabel, 'tagCountLabel');
    same((s) => s.tagCountDetail, 'tagCountDetail');
    same((s) => s.remoteEndpointsLabel, 'remoteEndpointsLabel');
    same((s) => s.remoteEndpointsDetail(2), 'remoteEndpointsDetail');

    // Bursty-cadence card.
    same((s) => s.burstyTitle, 'burstyTitle');
    same((s) => s.burstyClaim, 'burstyClaim');

    // Branch-model card.
    same((s) => s.branchModelSimpleTitle, 'branchModelSimpleTitle');
    same((s) => s.branchModelBroadTitle, 'branchModelBroadTitle');
    same((s) => s.branchModelSimpleClaim, 'branchModelSimpleClaim');
    same((s) => s.branchModelBroadClaim, 'branchModelBroadClaim');
    same((s) => s.localBranchesLabel, 'localBranchesLabel');
    same((s) => s.localBranchesDetail(3), 'localBranchesDetail');
    same((s) => s.remoteBranchesLabel, 'remoteBranchesLabel');
    same((s) => s.remoteBranchesDetail(5), 'remoteBranchesDetail');

    // Reflog-intense card.
    same((s) => s.reflogTitle, 'reflogTitle');
    same((s) => s.reflogClaim, 'reflogClaim');
    same((s) => s.peakReflogDayLabel, 'peakReflogDayLabel');

    // Keystone-files card.
    same((s) => s.keystoneTitle(1), 'keystoneTitle(1)');
    same((s) => s.keystoneTitle(4), 'keystoneTitle(4)');
    same((s) => s.keystoneClaim(1), 'keystoneClaim(1)');
    same((s) => s.keystoneClaim(4), 'keystoneClaim(4)');
    same((s) => s.keystoneEvidenceDetail(touchCount: 1, score: '1.20'),
        'keystoneEvidenceDetail(1)');
    same((s) => s.keystoneEvidenceDetail(touchCount: 7, score: '3.14'),
        'keystoneEvidenceDetail(7)');

    // Narrow-hotspot card.
    same((s) => s.narrowHotspotTitle, 'narrowHotspotTitle');
    same((s) => s.narrowHotspotClaim, 'narrowHotspotClaim');
    same((s) => s.topHotspotLabel, 'topHotspotLabel');
    same((s) => s.topHotspotDetail(path: 'lib/main.dart', pct: '45'),
        'topHotspotDetail');
    same((s) => s.visibleAuthorsLabel, 'visibleAuthorsLabel');
    same((s) => s.visibleAuthorsDetail(6), 'visibleAuthorsDetail');
  });

  group('hand-derived exact English on the slang path', () {
    test('hidden-refs card', () {
      expect(_slang.hiddenRefsTitle, 'Hidden Git namespaces');
      expect(_slang.hiddenRefsClaim(3),
          '3 refs live outside normal branch/tag space.');
      expect(_slang.hiddenRefsEvidenceLabel, 'Hidden refs');
      expect(_slang.hiddenRefsEvidenceDetail(3),
          '3 refs outside heads/remotes/tags.');
      expect(_slang.namespacesLabel, 'Namespaces');
    });

    test('machine-history card', () {
      expect(_slang.machineHistoryTitle, 'Machine history dominates raw metrics');
      expect(_slang.machineHistoryClaim,
          'Checkpoint-style commits materially distort naive history metrics.');
      expect(_slang.rawVsFilteredLabel, 'Raw vs filtered');
      expect(_slang.rawVsFilteredDetail(raw: 200, filtered: 40),
          '200 raw commits vs 40 filtered commits.');
      expect(_slang.machineCommitsLabel, 'Machine commits');
      expect(_slang.machineCommitsDetail(160),
          '160 commits matched machine/session patterns.');
    });

    test('migration card', () {
      expect(_slang.migrationTitle, 'Architecture migration visible');
      expect(
        _slang.migrationClaim(
            older: 'apps/desktop', newer: 'apps/desktop-flutter'),
        'History shifts from `apps/desktop` to `apps/desktop-flutter`, suggesting a stack or surface transition.',
      );
      expect(
        _slang.migrationStratumDetail(touches: 42, lastActive: '2026-04-20'),
        '42 touches, last active 2026-04-20.',
      );
    });

    test('single-owner-hotspot card', () {
      expect(_slang.singleOwnerTitle, 'Single-owner hotspot');
      expect(
        _slang.singleOwnerClaim(path: 'lib/main.dart', kind: 'file'),
        '`lib/main.dart` is a heavily touched file with one distinct visible author.',
      );
      expect(_slang.touchCountLabel, 'Touch count');
      expect(_slang.singleOwnerTouchDetail(count: 12, raw: true),
          '12 touches in raw history.');
      expect(_slang.singleOwnerTouchDetail(count: 12, raw: false),
          '12 touches in filtered history.');
      expect(_slang.ownerCountLabel, 'Owner count');
      expect(_slang.ownerCountDetail(1), '1 distinct authors.');
    });

    test('no-tags card', () {
      expect(_slang.noTagsTitle, 'No formal release/tag trail');
      expect(_slang.noTagsClaim,
          'Git tags are not being used as a visible release or milestone layer.');
      expect(_slang.tagCountLabel, 'Tag count');
      expect(_slang.tagCountDetail, '0 tags found.');
      expect(_slang.remoteEndpointsLabel, 'Remote endpoints');
      expect(_slang.remoteEndpointsDetail(2),
          '2 remote endpoints configured.');
    });

    test('bursty-cadence card', () {
      expect(_slang.burstyTitle, 'Bursty development cadence');
      expect(_slang.burstyClaim,
          'Work lands in concentrated bursts rather than a flat daily rhythm.');
    });

    test('branch-model card', () {
      expect(_slang.branchModelSimpleTitle, 'Simple branch model');
      expect(_slang.branchModelBroadTitle, 'Branch model has surface area');
      expect(_slang.branchModelSimpleClaim, 'The visible branch model is narrow.');
      expect(
        _slang.branchModelBroadClaim,
        'The repository has enough branch surface to reward branch-aware navigation.',
      );
      expect(_slang.localBranchesLabel, 'Local branches');
      expect(_slang.localBranchesDetail(3), '3 local branches.');
      expect(_slang.remoteBranchesLabel, 'Remote branches');
      expect(_slang.remoteBranchesDetail(5), '5 remote branches.');
    });

    test('reflog-intense card', () {
      expect(_slang.reflogTitle, 'Intense local editing sessions');
      expect(_slang.reflogClaim,
          'Reflog volume suggests concentrated local iteration beyond published commits.');
      expect(_slang.peakReflogDayLabel, 'Peak reflog day');
    });

    test('keystone-files card: singular vs plural', () {
      expect(_slang.keystoneTitle(1), 'Keystone bridge-file');
      expect(_slang.keystoneTitle(4), '4 keystone bridge-files');
      expect(
        _slang.keystoneClaim(1),
        'One file carries disproportionate co-change weight relative to its touch count.',
      );
      expect(
        _slang.keystoneClaim(4),
        'A small set of files carry disproportionate co-change weight relative to their touch counts.',
      );
      expect(_slang.keystoneEvidenceDetail(touchCount: 1, score: '1.20'),
          '1 touch · pull φ=1.20');
      expect(_slang.keystoneEvidenceDetail(touchCount: 7, score: '3.14'),
          '7 touches · pull φ=3.14');
    });

    test('narrow-hotspot card', () {
      expect(_slang.narrowHotspotTitle, 'Hotspot concentration is narrow');
      expect(
        _slang.narrowHotspotClaim,
        'A small set of files and directories absorbs a disproportionate share of changes.',
      );
      expect(_slang.topHotspotLabel, 'Top hotspot');
      expect(
        _slang.topHotspotDetail(path: 'lib/main.dart', pct: '45'),
        'lib/main.dart accounts for 45% of the visible hotspot set.',
      );
      expect(_slang.visibleAuthorsLabel, 'Visible authors');
      expect(_slang.visibleAuthorsDetail(6), '6 authors in this history slice.');
    });
  });
}
