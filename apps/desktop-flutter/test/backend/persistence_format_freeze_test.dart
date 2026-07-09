// persistence_format_freeze_test.dart — the upgrade-safety net.
//
// WHY THIS FILE EXISTS
//   Every persisted/wire type in lib/backend/ is already roundtrip-fuzzed
//   (test/fuzz/dto_serialization_fuzz_test.dart,
//   test/fuzz/settings_store_roundtrip_test.dart,
//   test/fuzz/logos_edits_codec_test.dart): `fromX(toX(v)) == v`. That law
//   is necessary but NOT sufficient for upgrade safety — it holds for ANY
//   bijective format, including a refactor that silently renames a JSON
//   key, flips a field's default, or reorders a binary layout. Such a
//   refactor passes every roundtrip test in this repo (today's writer and
//   today's reader agree with each other) while corrupting every byte a
//   USER'S PREVIOUS INSTALL already wrote to disk or to a git ref — those
//   bytes are frozen the moment they're written; only today's code is free
//   to change.
//
//   This file breaks that blind spot: it commits the actual serialized
//   output of representative, non-default instances as fixtures, then
//   asserts CURRENT code still decodes them to the right values and still
//   re-encodes them byte-for-byte. A fixture that stops decoding, or
//   decodes to the wrong field values, is a real backward-compatibility
//   break — fix the code, not the fixture (unless the format change is
//   deliberate, in which case regenerate — see below — and treat the
//   fixture diff as the migration story owed to users on the release notes).
//
// REGENERATING FIXTURES
//   Only for an INTENTIONAL format change. Read the resulting fixture diff
//   before committing it — it IS the compatibility break you're shipping,
//   and (unless a migration path already handles the old shape) every user
//   upgrading across it needs to be told.
//
//     MANIFOLD_REGEN_FIXTURES=1 flutter test test/backend/persistence_format_freeze_test.dart --no-pub
//
//   Exception: test/fixtures/persistence/app_settings_snapshot_legacy.json
//   is HAND-AUTHORED, not code-generated — it represents a real pre-
//   `updateChannelExplicit`/pre-`motionRate` settings.json shape from an
//   old release. Regenerating it from current code would defeat its
//   purpose (there would be nothing left to migrate FROM). Never touch it
//   except to add another genuinely-old hand-authored shape.
//
// FIXTURE LAYOUT
//   test/fixtures/persistence/<type>.json — JSON formats, pretty-printed
//     (2-space indent) regardless of whether the production writer itself
//     indents — DeskPr/DeskIssue/AppSettingsSnapshot/ShadowCouplingCache/
//     AiApiKeysSnapshot's real on-disk form IS `JsonEncoder.withIndent('  ')`
//     so those fixtures are byte-identical to a real file; AiAuditEntryData
//     (jsonl, one compact line per entry) and ClaimOutcomeRatchet (compact
//     `json.encode`) are pretty-printed here only for diffability — the
//     freeze assertion for those two is decode-and-compare-fields plus a
//     stable-under-our-own-pretty-encoding check, not literal production
//     byte equality (documented per-group below).
//   test/fixtures/persistence/<type>.b64 — binary codecs (SpectralBasis,
//     VersionVector, LogosEdit variants), base64 of the raw bytes.
//
// See test/fuzz/dto_serialization_fuzz_test.dart,
// test/fuzz/settings_store_roundtrip_test.dart and
// test/fuzz/logos_edits_codec_test.dart for the roundtrip-identity laws
// this file deliberately does not repeat.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:git_desktop/backend/ai_api_keys_store.dart';
import 'package:git_desktop/backend/ai_audit_store.dart';
import 'package:git_desktop/backend/desk_issue.dart';
import 'package:git_desktop/backend/desk_pr.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/external_tools.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/logos_edits.dart';
import 'package:git_desktop/backend/remote_types.dart' show PrReviewer;
import 'package:git_desktop/backend/review_logos.dart' show ClaimShape;
import 'package:git_desktop/backend/review_ratchet.dart';
import 'package:git_desktop/backend/settings_store.dart';
import 'package:git_desktop/backend/shadow_coupling_cache.dart';

// ── Fixture I/O ─────────────────────────────────────────────────────────

Directory get _fixturesDir => Directory(
      p.join(Directory.current.path, 'test', 'fixtures', 'persistence'),
    );

File _jsonFixture(String name) =>
    File(p.join(_fixturesDir.path, '$name.json'));
File _b64Fixture(String name) => File(p.join(_fixturesDir.path, '$name.b64'));

const JsonEncoder _kIndent = JsonEncoder.withIndent('  ');

/// The fixture's own canonical encoding — 2-space-indented JSON, trailing
/// newline. Every JSON fixture in this suite is written and re-checked
/// through this exact function, so "re-encode equals the fixture" is a
/// meaningful stability check regardless of what encoder production code
/// happens to use for that type (documented per-group where it diverges).
String _pretty(Object? value) => '${_kIndent.convert(value)}\n';

void _writeJsonFixture(String name, Object? value) {
  _fixturesDir.createSync(recursive: true);
  _jsonFixture(name).writeAsStringSync(_pretty(value));
}

String _readJsonFixtureRaw(String name) =>
    _jsonFixture(name).readAsStringSync();

// Return type is `dynamic` (not `Object?`) to match `jsonDecode`'s own
// return type — callers cast the result to the expected shape, and a
// `dynamic` source (unlike a statically nullable `Object?`) doesn't trip
// `cast_nullable_to_non_nullable`, matching the pattern every `fromBlob`/
// `fromJson` factory in lib/backend/ already uses for the same cast.
dynamic _readJsonFixture(String name) =>
    jsonDecode(_readJsonFixtureRaw(name));

void _writeB64Fixture(String name, Uint8List bytes) {
  _fixturesDir.createSync(recursive: true);
  _b64Fixture(name).writeAsStringSync('${base64.encode(bytes)}\n');
}

Uint8List _readB64Fixture(String name) =>
    base64.decode(_b64Fixture(name).readAsStringSync().trim());

bool get _regen => Platform.environment['MANIFOLD_REGEN_FIXTURES'] == '1';

// ── Sample instances (non-default, distinctive, deterministic) ──────────
// Every sample below deliberately carries: a unicode string, an edge-case
// number (0, a large int, or an int32-boundary value), at least one empty
// collection, and at least one populated collection, distributed across
// the suite. Timestamps are fixed `DateTime.utc(...)` — never wall-clock.

DeskPr _sampleDeskPr() => DeskPr(
      deskId: 424242,
      title: 'Unicode✧ fix: 修复 空指针 bug',
      body: 'Multi-line body.\nSecond line with emoji 🔥 and a tab\tchar.',
      headRef: 'feature/ünïcode-branch',
      baseRef: 'main',
      state: 'OPEN',
      isDraft: true,
      authorIdentity: 'Jane Doe <jane@example.com>',
      createdAt: DateTime.utc(2024, 1, 2, 3, 4, 5),
      updatedAt: DateTime.utc(2024, 6, 15, 12, 30),
      reviewers: const [
        PrReviewer(login: 'ünïcode_reviewer', state: 'CHANGES_REQUESTED'),
        PrReviewer(login: 'bob', state: 'APPROVED'),
      ],
      labels: const ['bug', 'p0-urgent'],
      assignees: const [], // empty collection
      linkedIssues: const [7, 2147483647], // edge number: int32 max
      linkedRemoteIssues: const [0], // edge number: zero
      thread: [
        DeskThreadEntry(
          author: 'jane',
          body: 'plain comment 👋',
          at: DateTime.utc(2024, 1, 3),
        ),
        DeskThreadEntry(
          author: 'bob',
          body: 'LGTM ✓',
          at: DateTime.utc(2024, 1, 4, 8, 15, 30),
          verdict: 'APPROVED',
        ),
      ],
      additions: 2147483647,
      deletions: 0,
      changedFiles: 12,
      mergeable: 'CONFLICTING',
      remoteNumber: 99,
    );

void _expectDeskPrEquals(DeskPr a, DeskPr b) {
  expect(b.deskId, a.deskId);
  expect(b.title, a.title);
  expect(b.body, a.body);
  expect(b.headRef, a.headRef);
  expect(b.baseRef, a.baseRef);
  expect(b.state, a.state);
  expect(b.isDraft, a.isDraft);
  expect(b.authorIdentity, a.authorIdentity);
  expect(b.createdAt, a.createdAt);
  expect(b.updatedAt, a.updatedAt);
  expect(b.reviewers.length, a.reviewers.length);
  for (var i = 0; i < a.reviewers.length; i++) {
    expect(b.reviewers[i].login, a.reviewers[i].login);
    expect(b.reviewers[i].state, a.reviewers[i].state);
  }
  expect(b.labels, equals(a.labels));
  expect(b.assignees, equals(a.assignees));
  expect(b.linkedIssues, equals(a.linkedIssues));
  expect(b.linkedRemoteIssues, equals(a.linkedRemoteIssues));
  expect(b.thread.length, a.thread.length);
  for (var i = 0; i < a.thread.length; i++) {
    expect(b.thread[i].author, a.thread[i].author);
    expect(b.thread[i].body, a.thread[i].body);
    expect(b.thread[i].at, a.thread[i].at);
    expect(b.thread[i].verdict, a.thread[i].verdict);
  }
  expect(b.additions, a.additions);
  expect(b.deletions, a.deletions);
  expect(b.changedFiles, a.changedFiles);
  expect(b.mergeable, a.mergeable);
  expect(b.remoteNumber, a.remoteNumber);
}

DeskIssue _sampleDeskIssue() => DeskIssue(
      issueId: 314159,
      title: 'Crash on unicode path 🔥',
      body: 'Steps to reproduce:\n1. Open a file named 日本語.txt\n2. Boom.',
      state: 'CLOSED',
      authorIdentity: 'reporter@example.com',
      createdAt: DateTime.utc(2023, 12, 25, 9),
      updatedAt: DateTime.utc(2024, 2, 14, 16, 45),
      labels: const [], // empty collection
      assignees: const ['alice', 'ünïcode_dev'], // populated collection
      addressedBy: const ['fix/unicode-path'],
      comments: [
        DeskIssueComment(
          author: 'alice',
          body: 'confirmed ✓',
          at: DateTime.utc(2024, 1, 1, 1, 1, 1),
        ),
      ],
      remoteNumber: 555,
    );

void _expectDeskIssueEquals(DeskIssue a, DeskIssue b) {
  expect(b.issueId, a.issueId);
  expect(b.title, a.title);
  expect(b.body, a.body);
  expect(b.state, a.state);
  expect(b.authorIdentity, a.authorIdentity);
  expect(b.createdAt, a.createdAt);
  expect(b.updatedAt, a.updatedAt);
  expect(b.labels, equals(a.labels));
  expect(b.assignees, equals(a.assignees));
  expect(b.addressedBy, equals(a.addressedBy));
  expect(b.comments.length, a.comments.length);
  for (var i = 0; i < a.comments.length; i++) {
    expect(b.comments[i].author, a.comments[i].author);
    expect(b.comments[i].body, a.comments[i].body);
    expect(b.comments[i].at, a.comments[i].at);
  }
  expect(b.remoteNumber, a.remoteNumber);
}

AppSettingsSnapshot _sampleAppSettingsSnapshot() =>
    AppSettingsSnapshot.defaults().copyWith(
      guardrailValue: 0.125,
      aiReadOnlyDefault: false,
      logoAnimatesWhenUnfocused: false,
      telemetryRetentionDays: 365, // edge: clamp upper bound
      telemetryRetentionMb: 16, // edge: clamp lower bound
      updateChannel: 'beta',
      updateChannelExplicit: true,
      crashReportingEnabled: true,
      themeId: 'phosphor',
      keybindingProfile: 'vim',
      sidebarWidthPx: 220,
      sidebarPosition: 'right',
      utilityDrawerDefaultExpanded: true,
      utilityDrawerHeightPx: 300,
      reduceMotion: false,
      motionRate: 1.75,
      reduceMotionPhase: 0.42,
      stashCabinetDefaultExpanded: true,
      instantBlameHover: true,
      autoSelectNewChanges: true,
      diffMediaEnabled: false,
      diffBinaryEnabled: false,
      fetchOnlineIssuesOnBranchLoad: false,
      rememberWorkInProgress: false,
      hideAiFeatures: true,
      undoWindowSeconds: 3600, // edge: clamp upper bound
      undoWindowOverrides: const {}, // empty collection
      fileSortGuide: 'impact',
      fileSortInverted: true,
      issuesSortDescending: false,
      tagsSortDescending: false,
      commitStructure: 'freeform',
      commitVoice: 'narrative',
      commitCoverage: 'everything',
      logosPadX: 0.0, // edge
      logosPadY: 1.0, // edge
      appShortName: 'Ünïcode™ App',
      onboardingComplete: true,
      bondExperimentEnabled: true,
      bondDockOpenedOnce: true,
      externalTools: [
        // populated collection
        const ExternalTool(
          id: 'tool_frozen_1',
          label: 'Ünïcode Tool 🔥',
          executable: 'my-tool',
          args: ['{path}', '--flag=1'],
          mode: ToolLaunchMode.detached,
        ),
      ],
      changesPanelWidthPx: 520, // edge: clamp upper bound
      wickExePath: 'C:\\tools\\wick ünïcode.exe',
      alphaMathPath: '',
      giteaTokens: const {'codeberg.org': 'tok_ünïcode_123'},
    );

void _expectAppSettingsSnapshotEquals(
  AppSettingsSnapshot a,
  AppSettingsSnapshot b,
) {
  expect(b.guardrailValue, a.guardrailValue);
  expect(b.aiReadOnlyDefault, a.aiReadOnlyDefault);
  expect(b.logoAnimatesWhenUnfocused, a.logoAnimatesWhenUnfocused);
  expect(b.telemetryRetentionDays, a.telemetryRetentionDays);
  expect(b.telemetryRetentionMb, a.telemetryRetentionMb);
  expect(b.updateChannel, a.updateChannel);
  expect(b.updateChannelExplicit, a.updateChannelExplicit);
  expect(b.crashReportingEnabled, a.crashReportingEnabled);
  expect(b.themeId, a.themeId);
  expect(b.keybindingProfile, a.keybindingProfile);
  expect(b.sidebarWidthPx, a.sidebarWidthPx);
  expect(b.sidebarPosition, a.sidebarPosition);
  expect(b.utilityDrawerDefaultExpanded, a.utilityDrawerDefaultExpanded);
  expect(b.utilityDrawerHeightPx, a.utilityDrawerHeightPx);
  expect(b.reduceMotion, a.reduceMotion);
  expect(b.motionRate, a.motionRate);
  expect(b.reduceMotionPhase, a.reduceMotionPhase);
  expect(b.stashCabinetDefaultExpanded, a.stashCabinetDefaultExpanded);
  expect(b.instantBlameHover, a.instantBlameHover);
  expect(b.autoSelectNewChanges, a.autoSelectNewChanges);
  expect(b.diffMediaEnabled, a.diffMediaEnabled);
  expect(b.diffBinaryEnabled, a.diffBinaryEnabled);
  expect(b.fetchOnlineIssuesOnBranchLoad, a.fetchOnlineIssuesOnBranchLoad);
  expect(b.rememberWorkInProgress, a.rememberWorkInProgress);
  expect(b.hideAiFeatures, a.hideAiFeatures);
  expect(b.undoWindowSeconds, a.undoWindowSeconds);
  expect(b.undoWindowOverrides, equals(a.undoWindowOverrides));
  expect(b.fileSortGuide, a.fileSortGuide);
  expect(b.fileSortInverted, a.fileSortInverted);
  expect(b.issuesSortDescending, a.issuesSortDescending);
  expect(b.tagsSortDescending, a.tagsSortDescending);
  expect(b.commitStructure, a.commitStructure);
  expect(b.commitVoice, a.commitVoice);
  expect(b.commitCoverage, a.commitCoverage);
  expect(b.logosPadX, a.logosPadX);
  expect(b.logosPadY, a.logosPadY);
  expect(b.appShortName, a.appShortName);
  expect(b.onboardingComplete, a.onboardingComplete);
  expect(b.bondExperimentEnabled, a.bondExperimentEnabled);
  expect(b.bondDockOpenedOnce, a.bondDockOpenedOnce);
  expect(b.externalTools.length, a.externalTools.length);
  for (var i = 0; i < a.externalTools.length; i++) {
    expect(b.externalTools[i].id, a.externalTools[i].id);
    expect(b.externalTools[i].label, a.externalTools[i].label);
    expect(b.externalTools[i].executable, a.externalTools[i].executable);
    expect(b.externalTools[i].args, equals(a.externalTools[i].args));
    expect(b.externalTools[i].mode, a.externalTools[i].mode);
  }
  expect(b.changesPanelWidthPx, a.changesPanelWidthPx);
  expect(b.wickExePath, a.wickExePath);
  expect(b.alphaMathPath, a.alphaMathPath);
  expect(b.giteaTokens, equals(a.giteaTokens));
}

ShadowCouplingCacheData _sampleShadowCouplingCacheData() =>
    ShadowCouplingCacheData(
      headHash: 'abc123ünïcode',
      discoveredAt: DateTime.utc(2024, 3, 10, 5, 6, 7),
      shadowCommitCount: 987654321, // edge: large int
      jaccardEdges: {
        // populated collection
        'lib/a.dart': {'lib/b.dart': 0.75, 'lib/c🔥.dart': 1.0},
        'lib/d.dart': {'lib/a.dart': 0.0}, // edge: zero weight
      },
      edgeTypeCounts: const {}, // empty collection
    );

void _expectShadowCouplingCacheDataEquals(
  ShadowCouplingCacheData a,
  ShadowCouplingCacheData b,
) {
  expect(b.headHash, a.headHash);
  expect(b.discoveredAt, a.discoveredAt);
  expect(b.shadowCommitCount, a.shadowCommitCount);
  expect(b.jaccardEdges, equals(a.jaccardEdges));
  expect(b.edgeTypeCounts, equals(a.edgeTypeCounts));
}

AiApiKeysSnapshot _sampleAiApiKeysSnapshot() =>
    const AiApiKeysSnapshot(entries: {
      'openai': AiApiKeyEntry(
        apiKey: 'sk-ünïcode-1234567890',
        baseUrl: 'https://api.openai.com/v1',
      ),
      'custom': AiApiKeyEntry(apiKey: 'edge-key-0'), // baseUrl absent
    });

void _expectAiApiKeysSnapshotEquals(
  AiApiKeysSnapshot a,
  AiApiKeysSnapshot b,
) {
  expect(b.entries.keys.toSet(), equals(a.entries.keys.toSet()));
  for (final key in a.entries.keys) {
    expect(b.entries[key]!.apiKey, a.entries[key]!.apiKey);
    expect(b.entries[key]!.baseUrl, a.entries[key]!.baseUrl);
  }
}

AiAuditEntryData _sampleAiAuditEntryData() => AiAuditEntryData(
      id: 'audit-ünïcode-001',
      event: 'review.completed',
      providerId: 'anthropic',
      repositoryHint: 'git-desktop 🔥',
      diffScopePath: null, // absent optional field
      promptPreview: 'Review this diff for correctness...',
      outputPreview: 'Looks good ✓ no issues found.',
      ok: true,
      errorCode: null,
      createdAt: DateTime.utc(2024, 5, 5, 5, 5, 5).toIso8601String(),
    );

void _expectAiAuditEntryDataEquals(AiAuditEntryData a, AiAuditEntryData b) {
  expect(b.id, a.id);
  expect(b.event, a.event);
  expect(b.providerId, a.providerId);
  expect(b.repositoryHint, a.repositoryHint);
  expect(b.diffScopePath, a.diffScopePath);
  expect(b.promptPreview, a.promptPreview);
  expect(b.outputPreview, a.outputPreview);
  expect(b.ok, a.ok);
  expect(b.errorCode, a.errorCode);
  expect(b.createdAt, a.createdAt);
}

// ── SpectralBasis (binary) ────────────────────────────────────────────

SpectralBasis _sampleSpectralBasis() => SpectralBasis(
      n: 4,
      k: 3,
      eigenvalues: Float64List.fromList([0.0, 1.5, 3.25]),
      eigenvectors: Float64List.fromList([
        0.1, 0.2, 0.3, 0.4, //
        0.5, 0.6, 0.7, 0.8, //
        0.9, 1.0, 1.1, 1.2, //
      ]),
      nodePaths: const [
        'lib/a🔥.dart',
        'lib/b.dart',
        '', // edge: empty path label
        'lib/d日本語.dart',
      ],
    );

// ── VersionVector (binary) ────────────────────────────────────────────

VersionVector _sampleVersionVector() => VersionVector(const {
      'peer-ünïcode-🔥': 42,
      'a': 0, // edge: zero lamport
      'zzz': 9007199254740991, // edge: 2^53 - 1 (max safe web int)
    });

// ── LogosEdit variants (binary) ───────────────────────────────────────

const EditClock _sampleClock =
    EditClock(lamport: 123456789, peer: 'peer-ünïcode-🔥');

LogosEdit _sampleNoOpEdit() => const NoOpEdit(clock: _sampleClock);
LogosEdit _sampleAddPathEdit() =>
    const AddPathEdit(clock: _sampleClock, path: 'lib/added🔥.dart');
LogosEdit _sampleRemovePathEdit() =>
    const RemovePathEdit(clock: _sampleClock, path: '');
LogosEdit _sampleSetEdgeEdit() => const SetEdgeEdit(
      clock: _sampleClock,
      pathA: 'lib/a.dart',
      pathB: 'lib/日本語.dart',
      weight: -0.0, // edge: negative zero
    );

// ── encodeBranch / decodeBranch (desk_pr_store.dart) ─────────────────

const List<String> _sampleBranchNames = [
  'feature/simple',
  'feature/ünïcode-branch-🔥',
  'has%percent',
  'trailing-dot.',
  '.leading-dot',
  'double//slash',
  '/leading-slash',
  'trailing-slash/',
  'plain_underscore-dash123',
  '..dotdot..',
];

// ── Fixture (re)generation ────────────────────────────────────────────

void _regenerateAllFixtures() {
  _writeJsonFixture('desk_pr', _sampleDeskPr().toJson());
  _writeJsonFixture('desk_issue', _sampleDeskIssue().toJson());
  _writeJsonFixture(
    'app_settings_snapshot',
    _sampleAppSettingsSnapshot().toJson(),
  );
  // app_settings_snapshot_legacy.json is intentionally NOT regenerated
  // here — see the file header.
  _writeJsonFixture(
    'shadow_coupling_cache',
    _sampleShadowCouplingCacheData().toJson(),
  );
  _writeJsonFixture(
    'ai_api_keys_snapshot',
    _sampleAiApiKeysSnapshot().toJson(),
  );
  _writeJsonFixture('ai_audit_entry', _sampleAiAuditEntryData().toJson());

  final ratchet = ClaimOutcomeRatchet();
  for (final shape in _ratchetShapes) {
    for (var i = 0; i < shape.$2; i++) {
      ratchet.observe(shape: shape.$1, verified: true);
    }
    for (var i = 0; i < shape.$3; i++) {
      ratchet.observe(shape: shape.$1, verified: false);
    }
  }
  _writeJsonFixture(
    'claim_outcome_ratchet',
    jsonDecode(ratchet.toJsonString()),
  );

  _writeB64Fixture('spectral_basis', _sampleSpectralBasis().toBytes());
  _writeB64Fixture('version_vector', _sampleVersionVector().toBytes());
  _writeB64Fixture('logos_edit_noop', encodeLogosEdit(_sampleNoOpEdit()));
  _writeB64Fixture(
      'logos_edit_add_path', encodeLogosEdit(_sampleAddPathEdit()));
  _writeB64Fixture(
      'logos_edit_remove_path', encodeLogosEdit(_sampleRemovePathEdit()));
  _writeB64Fixture(
      'logos_edit_set_edge', encodeLogosEdit(_sampleSetEdgeEdit()));

  _writeJsonFixture('desk_pr_store_encode_branch', [
    for (final branch in _sampleBranchNames)
      {'branch': branch, 'encoded': DeskPrStore.encodeBranch(branch)},
  ]);

  // ignore: avoid_print
  print('Regenerated fixtures under ${_fixturesDir.path}');
}

// shapeA: 2 accepts, 1 reject. shapeB: 0 accepts, 1 reject (edge values).
const ClaimShape _shapeA = ClaimShape(
  grounding: 0.82,
  verifiability: 0.5,
  reach: 0.33,
  coherence: 0.91,
  symbolCount: 4,
  textLength: 120,
);
const ClaimShape _shapeB = ClaimShape(
  grounding: 0.0,
  verifiability: 1.0,
  reach: 1.0,
  coherence: 0.0,
  symbolCount: 0,
  textLength: 0,
);
final List<(ClaimShape, int, int)> _ratchetShapes = [
  (_shapeA, 2, 1),
  (_shapeB, 0, 1),
];

// ── Tests ───────────────────────────────────────────────────────────────

void main() {
  if (_regen) {
    test('regenerate fixtures (MANIFOLD_REGEN_FIXTURES=1)', () {
      _regenerateAllFixtures();
    });
    return;
  }

  group('DeskPr — desk_pr.dart toBlob/fromBlob (git-ref persisted form)', () {
    test('frozen fixture decodes to the exact expected fields', () {
      final expected = _sampleDeskPr();
      final decoded =
          DeskPr.fromJson(_readJsonFixture('desk_pr') as Map<String, dynamic>);
      _expectDeskPrEquals(expected, decoded);
    });

    test('re-encoding the decoded object reproduces the fixture bytes '
        'exactly (no key reordering, no field drift)', () {
      final decoded =
          DeskPr.fromJson(_readJsonFixture('desk_pr') as Map<String, dynamic>);
      expect(_pretty(decoded.toJson()), equals(_readJsonFixtureRaw('desk_pr')));
    });
  });

  group('DeskIssue — desk_issue.dart toBlob/fromBlob', () {
    test('frozen fixture decodes to the exact expected fields', () {
      final expected = _sampleDeskIssue();
      final decoded = DeskIssue.fromJson(
          _readJsonFixture('desk_issue') as Map<String, dynamic>);
      _expectDeskIssueEquals(expected, decoded);
    });

    test('re-encoding the decoded object reproduces the fixture bytes '
        'exactly', () {
      final decoded = DeskIssue.fromJson(
          _readJsonFixture('desk_issue') as Map<String, dynamic>);
      expect(
          _pretty(decoded.toJson()), equals(_readJsonFixtureRaw('desk_issue')));
    });
  });

  group('AppSettingsSnapshot — settings_store.dart toJson/fromJson', () {
    test('frozen fixture decodes to the exact expected fields', () {
      final expected = _sampleAppSettingsSnapshot();
      final decoded = AppSettingsSnapshot.fromJson(
          _readJsonFixture('app_settings_snapshot') as Map<String, dynamic>);
      _expectAppSettingsSnapshotEquals(expected, decoded);
    });

    test('re-encoding the decoded object reproduces the fixture bytes '
        'exactly', () {
      final decoded = AppSettingsSnapshot.fromJson(
          _readJsonFixture('app_settings_snapshot') as Map<String, dynamic>);
      expect(_pretty(decoded.toJson()),
          equals(_readJsonFixtureRaw('app_settings_snapshot')));
    });

    test(
      'LEGACY migration: a hand-authored pre-updateChannelExplicit/'
      'pre-motionRate settings.json (app_settings_snapshot_legacy.json) '
      'still migrates correctly under current code',
      () {
        final legacyJson = _readJsonFixture('app_settings_snapshot_legacy')
            as Map<String, dynamic>;
        // Sanity on the fixture itself — if these ever fail, the fixture
        // stopped representing the legacy shape it's meant to pin.
        expect(legacyJson.containsKey('updateChannelExplicit'), isFalse);
        expect(legacyJson.containsKey('motionRate'), isFalse);

        final migrated = AppSettingsSnapshot.fromJson(legacyJson);

        // updateChannel='beta' with no explicit flag pre-dates the flag —
        // _inferLegacyChannelExplicit treats a persisted 'beta' as having
        // been an explicit user choice (see settings_store.dart).
        expect(migrated.updateChannel, 'beta');
        expect(migrated.updateChannelExplicit, isTrue);
        // reduceMotion=true with no motionRate migrates to rate 0.0.
        expect(migrated.reduceMotion, isTrue);
        expect(migrated.motionRate, 0.0);
        // Untouched legacy fields carry through unchanged.
        expect(migrated.themeId, 'aether');
        expect(migrated.keybindingProfile, 'classic');
        expect(migrated.sidebarWidthPx, 188);
        expect(migrated.sidebarPosition, 'left');
        expect(migrated.onboardingComplete, isTrue);
        expect(migrated.guardrailValue, 0.5);

        // Idempotence: re-serializing the migrated snapshot and re-parsing
        // it is a stable fixed point (no further drift on a second load).
        final restabilized =
            AppSettingsSnapshot.fromJson(migrated.toJson());
        _expectAppSettingsSnapshotEquals(migrated, restabilized);
      },
    );
  });

  group('ShadowCouplingCacheData — shadow_coupling_cache.dart', () {
    test('frozen fixture decodes to the exact expected fields', () {
      final expected = _sampleShadowCouplingCacheData();
      final decoded = ShadowCouplingCacheData.fromJson(
          _readJsonFixture('shadow_coupling_cache') as Map<String, dynamic>);
      _expectShadowCouplingCacheDataEquals(expected, decoded);
    });

    test('re-encoding the decoded object reproduces the fixture bytes '
        'exactly', () {
      final decoded = ShadowCouplingCacheData.fromJson(
          _readJsonFixture('shadow_coupling_cache') as Map<String, dynamic>);
      expect(_pretty(decoded.toJson()),
          equals(_readJsonFixtureRaw('shadow_coupling_cache')));
    });
  });

  group('AiApiKeysSnapshot — ai_api_keys_store.dart', () {
    test('frozen fixture decodes to the exact expected fields', () {
      final expected = _sampleAiApiKeysSnapshot();
      final decoded = AiApiKeysSnapshot.fromJson(
          _readJsonFixture('ai_api_keys_snapshot') as Map<String, dynamic>);
      _expectAiApiKeysSnapshotEquals(expected, decoded);
    });

    test('re-encoding the decoded object reproduces the fixture bytes '
        'exactly', () {
      final decoded = AiApiKeysSnapshot.fromJson(
          _readJsonFixture('ai_api_keys_snapshot') as Map<String, dynamic>);
      expect(_pretty(decoded.toJson()),
          equals(_readJsonFixtureRaw('ai_api_keys_snapshot')));
    });
  });

  group('AiAuditEntryData — ai_audit_store.dart (real on-disk form is a '
      'compact jsonl line; fixture is pretty-printed for diffability, see '
      'file header)', () {
    test('frozen fixture decodes to the exact expected fields', () {
      final expected = _sampleAiAuditEntryData();
      final decoded = AiAuditEntryData.fromJson(
          _readJsonFixture('ai_audit_entry') as Map<String, dynamic>);
      _expectAiAuditEntryDataEquals(expected, decoded);
    });

    test('re-encoding the decoded object reproduces the fixture\'s own '
        'pretty encoding exactly (key order stability)', () {
      final decoded = AiAuditEntryData.fromJson(
          _readJsonFixture('ai_audit_entry') as Map<String, dynamic>);
      expect(_pretty(decoded.toJson()),
          equals(_readJsonFixtureRaw('ai_audit_entry')));
    });
  });

  group('ClaimOutcomeRatchet — review_ratchet.dart toJsonString/'
      'fromJsonString (real on-disk form is compact `json.encode`; fixture '
      'is pretty-printed for diffability, see file header)', () {
    test('frozen fixture decodes to the exact expected posterior/counts',
        () {
      final decoded = ClaimOutcomeRatchet.fromJsonString(
          _readJsonFixtureRaw('claim_outcome_ratchet'));
      expect(decoded.bucketCount, 2);
      expect(decoded.totalObservations, 4);
      // shapeA: 2 accepts, 1 reject -> (2+1)/(3+2) = 0.6.
      expect(decoded.priorFor(_shapeA), closeTo(0.6, 1e-12));
      expect(decoded.observationCountFor(_shapeA), 3);
      // shapeB: 0 accepts, 1 reject -> (0+1)/(1+2) = 1/3.
      expect(decoded.priorFor(_shapeB), closeTo(1 / 3, 1e-12));
      expect(decoded.observationCountFor(_shapeB), 1);
    });

    test('re-encoding the decoded ratchet reproduces the fixture\'s own '
        'pretty encoding exactly (bucket keys, counter fields stable)', () {
      final decoded = ClaimOutcomeRatchet.fromJsonString(
          _readJsonFixtureRaw('claim_outcome_ratchet'));
      final reEncoded = _pretty(jsonDecode(decoded.toJsonString()));
      expect(reEncoded, equals(_readJsonFixtureRaw('claim_outcome_ratchet')));
    });
  });

  group('SpectralBasis — logos_core.dart toBytes/fromBytes (binary)', () {
    test('frozen fixture decodes to the exact expected fields', () {
      final expected = _sampleSpectralBasis();
      final decoded = SpectralBasis.fromBytes(_readB64Fixture('spectral_basis'));
      expect(decoded.n, expected.n);
      expect(decoded.k, expected.k);
      expect(decoded.eigenvalues, equals(expected.eigenvalues));
      expect(decoded.eigenvectors, equals(expected.eigenvectors));
      expect(decoded.nodePaths, equals(expected.nodePaths));
      expect(decoded.signature, equals(expected.signature));
    });

    test('re-encoding the decoded basis reproduces the fixture bytes '
        'exactly', () {
      final decoded = SpectralBasis.fromBytes(_readB64Fixture('spectral_basis'));
      expect(
        base64.encode(decoded.toBytes()),
        equals(base64.encode(_readB64Fixture('spectral_basis'))),
      );
    });
  });

  group('VersionVector — logos_edits.dart toBytes/fromBytes (binary)', () {
    test('frozen fixture decodes to the exact expected peer map', () {
      final expected = _sampleVersionVector();
      final decoded = VersionVector.fromBytes(_readB64Fixture('version_vector'));
      expect(decoded, equals(expected));
      for (final peer in expected.peers) {
        expect(decoded.maxLamportFor(peer), expected.maxLamportFor(peer));
      }
    });

    test('re-encoding the decoded vector reproduces the fixture bytes '
        'exactly', () {
      final decoded = VersionVector.fromBytes(_readB64Fixture('version_vector'));
      expect(
        base64.encode(decoded.toBytes()),
        equals(base64.encode(_readB64Fixture('version_vector'))),
      );
    });
  });

  group('LogosEdit — logos_edits.dart encodeLogosEdit/decodeLogosEdit '
      '(binary, one fixture per variant)', () {
    void checkVariant(
      String fixtureName,
      LogosEdit Function() sample,
      void Function(LogosEdit decoded) checkFields,
    ) {
      test('$fixtureName: frozen fixture decodes to the exact expected edit',
          () {
        final decoded = decodeLogosEdit(_readB64Fixture(fixtureName));
        expect(decoded.clock, equals(sample().clock));
        checkFields(decoded);
      });
      test('$fixtureName: re-encoding reproduces the fixture bytes exactly',
          () {
        final decoded = decodeLogosEdit(_readB64Fixture(fixtureName));
        expect(
          base64.encode(encodeLogosEdit(decoded)),
          equals(base64.encode(_readB64Fixture(fixtureName))),
        );
      });
    }

    checkVariant('logos_edit_noop', _sampleNoOpEdit, (decoded) {
      expect(decoded, isA<NoOpEdit>());
    });
    checkVariant('logos_edit_add_path', _sampleAddPathEdit, (decoded) {
      expect(decoded, isA<AddPathEdit>());
      expect((decoded as AddPathEdit).path, 'lib/added🔥.dart');
    });
    checkVariant('logos_edit_remove_path', _sampleRemovePathEdit, (decoded) {
      expect(decoded, isA<RemovePathEdit>());
      expect((decoded as RemovePathEdit).path, '');
    });
    checkVariant('logos_edit_set_edge', _sampleSetEdgeEdit, (decoded) {
      expect(decoded, isA<SetEdgeEdit>());
      final e = decoded as SetEdgeEdit;
      expect(e.pathA, 'lib/a.dart');
      expect(e.pathB, 'lib/日本語.dart');
      expect(e.weight, -0.0);
    });
  });

  group('DeskPrStore.encodeBranch / decodeBranch — desk_pr_store.dart '
      '(ref-tail format used for refs/manifold/desks/<encoded-branch>; no '
      'separate legacy-migration function exists in the current codebase — '
      'see report)', () {
    test('frozen encodings still decode back to the exact original branch '
        'names, and the current encoder still produces the exact frozen '
        'bytes', () {
      final fixture = _readJsonFixture('desk_pr_store_encode_branch') as List;
      expect(fixture, isNotEmpty);
      for (final entry in fixture) {
        final map = entry as Map<String, dynamic>;
        final branch = map['branch'] as String;
        final encoded = map['encoded'] as String;
        expect(DeskPrStore.encodeBranch(branch), equals(encoded),
            reason: 'encodeBranch($branch) drifted from the frozen ref tail');
        expect(DeskPrStore.decodeBranch(encoded), equals(branch),
            reason: 'decodeBranch($encoded) no longer recovers $branch');
      }
    });
  });
}
