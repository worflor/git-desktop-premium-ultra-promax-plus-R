// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// xray_card_text.dart — the localized rendering layer for the Repo
// X-Ray insight cards.
//
// The `repository_xray.dart` card generator is deliberately Flutter-free:
// it composes structure and delegates every user-facing title, claim,
// and evidence label/detail to a pure [XrayCardStrings]. This module
// supplies the slang-backed implementation so the cards read in the
// viewer's locale, without dragging flutter/slang into the backend. It
// mirrors `repo_summary_text.dart`: whole sentences resolved via the
// global [t] at snapshot-build time.

import '../backend/repository_xray_strings.dart';
import '../i18n/gen/strings.g.dart';

/// [XrayCardStrings] backed by the `xray.cards` slang section. Each member
/// returns a complete, translatable unit — the backend supplies only
/// counts, paths, and pre-formatted values, never word order.
class SlangXrayCardStrings implements XrayCardStrings {
  const SlangXrayCardStrings();

  // ── Hidden-refs card ──
  @override
  String get hiddenRefsTitle => t.xray.cards.hiddenRefs.title;
  @override
  String hiddenRefsClaim(int count) => t.xray.cards.hiddenRefs.claim(count: count);
  @override
  String get hiddenRefsEvidenceLabel => t.xray.cards.hiddenRefs.evidenceLabel;
  @override
  String hiddenRefsEvidenceDetail(int count) =>
      t.xray.cards.hiddenRefs.evidenceDetail(count: count);
  @override
  String get namespacesLabel => t.xray.cards.hiddenRefs.namespacesLabel;

  // ── Machine-history card ──
  @override
  String get machineHistoryTitle => t.xray.cards.machineHistory.title;
  @override
  String get machineHistoryClaim => t.xray.cards.machineHistory.claim;
  @override
  String get rawVsFilteredLabel => t.xray.cards.machineHistory.rawVsFilteredLabel;
  @override
  String rawVsFilteredDetail({required int raw, required int filtered}) =>
      t.xray.cards.machineHistory.rawVsFilteredDetail(raw: raw, filtered: filtered);
  @override
  String get machineCommitsLabel => t.xray.cards.machineHistory.machineCommitsLabel;
  @override
  String machineCommitsDetail(int count) =>
      t.xray.cards.machineHistory.machineCommitsDetail(count: count);

  // ── Migration card ──
  @override
  String get migrationTitle => t.xray.cards.migration.title;
  @override
  String migrationClaim({required String older, required String newer}) =>
      t.xray.cards.migration.claim(older: older, newer: newer);
  @override
  String migrationStratumDetail(
          {required int touches, required String lastActive}) =>
      t.xray.cards.migration.stratumDetail(touches: touches, lastActive: lastActive);

  // ── Single-owner-hotspot card ──
  @override
  String get singleOwnerTitle => t.xray.cards.singleOwner.title;
  @override
  String singleOwnerClaim({required String path, required String kind}) =>
      t.xray.cards.singleOwner.claim(path: path, kind: kind);
  @override
  String get touchCountLabel => t.xray.cards.singleOwner.touchCountLabel;
  @override
  String singleOwnerTouchDetail({required int count, required bool raw}) => raw
      ? t.xray.cards.singleOwner.touchDetailRaw(count: count)
      : t.xray.cards.singleOwner.touchDetailFiltered(count: count);
  @override
  String get ownerCountLabel => t.xray.cards.singleOwner.ownerCountLabel;
  @override
  String ownerCountDetail(int count) =>
      t.xray.cards.singleOwner.ownerCountDetail(count: count);

  // ── No-tags card ──
  @override
  String get noTagsTitle => t.xray.cards.noTags.title;
  @override
  String get noTagsClaim => t.xray.cards.noTags.claim;
  @override
  String get tagCountLabel => t.xray.cards.noTags.tagCountLabel;
  @override
  String get tagCountDetail => t.xray.cards.noTags.tagCountDetail;
  @override
  String get remoteEndpointsLabel => t.xray.cards.noTags.remoteEndpointsLabel;
  @override
  String remoteEndpointsDetail(int count) =>
      t.xray.cards.noTags.remoteEndpointsDetail(count: count);

  // ── Bursty-cadence card ──
  @override
  String get burstyTitle => t.xray.cards.bursty.title;
  @override
  String get burstyClaim => t.xray.cards.bursty.claim;

  // ── Branch-model card ──
  @override
  String get branchModelSimpleTitle => t.xray.cards.branchModel.simpleTitle;
  @override
  String get branchModelBroadTitle => t.xray.cards.branchModel.broadTitle;
  @override
  String get branchModelSimpleClaim => t.xray.cards.branchModel.simpleClaim;
  @override
  String get branchModelBroadClaim => t.xray.cards.branchModel.broadClaim;
  @override
  String get localBranchesLabel => t.xray.cards.branchModel.localBranchesLabel;
  @override
  String localBranchesDetail(int count) =>
      t.xray.cards.branchModel.localBranchesDetail(count: count);
  @override
  String get remoteBranchesLabel => t.xray.cards.branchModel.remoteBranchesLabel;
  @override
  String remoteBranchesDetail(int count) =>
      t.xray.cards.branchModel.remoteBranchesDetail(count: count);

  // ── Reflog-intense card ──
  @override
  String get reflogTitle => t.xray.cards.reflog.title;
  @override
  String get reflogClaim => t.xray.cards.reflog.claim;
  @override
  String get peakReflogDayLabel => t.xray.cards.reflog.peakReflogDayLabel;

  // ── Keystone-files card ──
  @override
  String keystoneTitle(int count) => t.xray.cards.keystone.title(n: count);
  @override
  String keystoneClaim(int count) => t.xray.cards.keystone.claim(n: count);
  @override
  String keystoneEvidenceDetail(
          {required int touchCount, required String score}) =>
      t.xray.cards.keystone.evidenceDetail(n: touchCount, score: score);

  // ── Narrow-hotspot card ──
  @override
  String get narrowHotspotTitle => t.xray.cards.narrowHotspot.title;
  @override
  String get narrowHotspotClaim => t.xray.cards.narrowHotspot.claim;
  @override
  String get topHotspotLabel => t.xray.cards.narrowHotspot.topHotspotLabel;
  @override
  String topHotspotDetail({required String path, required String pct}) =>
      t.xray.cards.narrowHotspot.topHotspotDetail(path: path, pct: pct);
  @override
  String get visibleAuthorsLabel => t.xray.cards.narrowHotspot.visibleAuthorsLabel;
  @override
  String visibleAuthorsDetail(int count) =>
      t.xray.cards.narrowHotspot.visibleAuthorsDetail(count: count);
}
