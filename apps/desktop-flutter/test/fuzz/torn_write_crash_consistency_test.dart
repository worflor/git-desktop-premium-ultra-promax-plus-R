// Torn-write / crash-consistency fuzzing for every app-data store's persist
// choreography. Siblings cover *value* robustness — settings_store_roundtrip
// _test.dart fuzzes fromJson/toJson coercion, dto_serialization_fuzz_test.dart
// fuzzes DTO roundtrips, hostile_input_laws_test.dart fuzzes parsers against
// adversarial bytes. NONE of them simulate the process dying *mid-write*. This
// file adds exactly that axis: it journals a store's real persist() as an
// ordered list of byte-level filesystem effects (via test/support/io_faults
// .dart), then replays a crash at EVERY intermediate point — a byte cut at
// {0,1,mid,len-1,len} of each write, and a before/after split of each
// rename/delete — and asserts the store's real load() degrades safely from the
// resulting on-disk state.
//
// The bug class: a non-atomic write leaves a corrupt file that a later load()
// either throws on, silently wipes, or worse, re-persists defaults *over* —
// destroying user state. This is historical bug B20 (a torn settings.json
// wiped the whole snapshot to defaults) generalised to every store.
//
// Hermetic + OS-portable by construction: StoragePaths.debugOverrideDir
// (storage_paths.dart) redirects ALL store I/O to a per-case temp dir, so no
// GDPU_DATA_DIR gate is needed and no developer file is ever touched; the
// journal is path-relative and '/'-normalised, so a crash captured on Windows
// replays byte-identically under WSL2 Linux. Runs by default on both.
//
// ── LAWS ────────────────────────────────────────────────────────────────
//  1. crash-atomicity (AiApiKeysStore, ShadowCouplingCache): tmp+rename means
//     load() at every crash point yields S1 or S2 — never a torn file, never
//     null-when-the-target-exists.                                    [ARMED]
//  2. crash-atomicity (EngramFileIndexCache): tmp+rename (flush:true, no
//     delete-first) means load() at every crash point yields S1 or S2 — never
//     empty, never a torn file. The old delete-then-rename absence window is
//     GONE (was finding T5, fixed 2026-07-10).                         [ARMED]
//  3. torn-snapshot floor (SettingsStore, AiSettingsStore, ReviewRatchetStore,
//     LocalTelemetryStore): all four now persist via writeFileAtomic
//     (atomic_write.dart), so load() at every crash point yields ONLY S1 or S2
//     — never a torn prefix, never the defaults fallback. Was finding T1
//     (non-atomic snapshot wipe), fixed 2026-07-10.                    [ARMED]
//  4. no-evidence-destruction (AiSettingsStore): after loading a torn file the
//     on-disk bytes survive for forensics — load() returns defaults in memory
//     without re-persisting. Was finding T2, fixed 2026-07-10.         [ARMED]
//  5. append-isolation, guarded (CommandTelemetryStore): a crash mid-append
//     loses at most the appended record; all prior records load intact and a
//     subsequent append does not corrupt the next record.             [ARMED]
//  6. append-isolation, guarded (NudgeLedger): a torn tail with no trailing
//     newline no longer swallows the next append — the last-byte guard
//     prepends '\n'. Was finding T3, fixed 2026-07-10.                 [ARMED]
//  7. rewrite-tolerance (AiAuditStore): a crash mid-sink-rewrite yields a
//     clean prefix of the retained entries; load never throws, no franken
//     line.                                                           [ARMED]
//  8. cross-file blast radius: a torn write to store X never mutates store Y's
//     file — every other file is byte-identical at every crash point. [ARMED]
//
// ── Power-loss / crash-during-recovery upgrades ────────────────────────────
//  P. power-loss durability (io_faults' enumeratePowerLossPoints): the crash
//     model above is process-death (every write the program *issued* is
//     durable). Power loss is weaker — an UNFLUSHED write can be lost even
//     though a later rename landed ("rename lands, data didn't"). For the
//     tmp+rename stores this sweeps every power-loss state:
//       - AiApiKeysStore, ShadowCouplingCache write the tmp with flush:true,
//         so there is NO power-loss surface at all — the enumerator yields
//         zero points, and a full replay is exactly S2.        [ARMED / safe]
//       - EngramFileIndexCache now writes its tmp with flush:true, then an
//         atomic rename (no delete-first), so — like the api-keys/shadow cells
//         — the enumerator yields ZERO power-loss points and a full replay is
//         exactly S2. Was finding T5 (unflushed tmp), fixed 2026-07-10.
//                                                               [ARMED / safe]
//  R. crash-during-recovery fixpoint (SettingsStore, AiSettingsStore): one
//     crash generation is not enough — recovery can itself crash. Produce a
//     first-gen torn state, journal what load() writes (its recovery write),
//     crash THAT write at every point, then load again: must not throw, must
//     land in {S1,S2,defaults}, and a third load must equal the second
//     (idempotence / fixpoint). AiSettingsStore's recovery write is the same
//     non-atomic rewrite LAW 4 already flags; LAW R confirms the value-level
//     fixpoint still holds even though evidence is destroyed.          [ARMED]
//
// ── Additional store surfaces ──────────────────────────────────────────────
//  - SpectralBasisCache (direct flush:false writeAsBytes, content-addressed):
//    torn write AND power loss degrade read()/readSync() to null, never throw;
//    a full replay reads the exact basis back.                  [ARMED / safe]
//  - AiSettingsStore prompt files: a torn prompt .md write never throws and
//    never touches ai_settings.json (blast radius).             [ARMED / safe]
//  - PaletteState usage store: parsePaletteUsage (palette_state.dart) is a pure
//    all-or-nothing parse — throws on any malformed field, never a partial
//    (franken) commit. Armed via the @visibleForTesting seam. Was an
//    unreachable smell, made testable + fixed 2026-07-10.             [ARMED]
//  - AI model disk cache: private, no seam — documented UNREACHABLE (the save
//    path now rides writeFileAtomic by code review).
//
// Run with:
//   flutter test test/fuzz/torn_write_crash_consistency_test.dart
//   MANIFOLD_FUZZ=3 flutter test test/fuzz/torn_write_crash_consistency_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai_api_keys_store.dart';
import 'package:git_desktop/backend/ai_audit_store.dart';
import 'package:git_desktop/backend/ai_settings_store.dart';
import 'package:git_desktop/backend/command_telemetry_store.dart';
import 'package:git_desktop/backend/engram_file_index_cache.dart';
import 'package:git_desktop/backend/engram_hunk_encoder.dart' show HunkKVector;
import 'package:git_desktop/backend/local_telemetry_store.dart';
import 'package:git_desktop/backend/logos_core.dart' show SpectralBasis;
import 'package:git_desktop/backend/nudge_ledger.dart';
import 'package:git_desktop/backend/review_ratchet.dart';
import 'package:git_desktop/backend/review_ratchet_store.dart';
import 'package:git_desktop/backend/settings_store.dart';
import 'package:git_desktop/backend/shadow_coupling_cache.dart';
import 'package:git_desktop/backend/spectral_persistence.dart';
import 'package:git_desktop/backend/storage_paths.dart';
import 'package:git_desktop/features/palette/palette_state.dart'
    show parsePaletteUsage;
import 'package:path/path.dart' as p;

import '../support/gen.dart';
import '../support/io_faults.dart';
import '../support/prop.dart';

// ── Regression breadcrumbs — laws once pinned as findings, now ARMED ──────
// Each below was a genuine bug documented by a skip-pinned law; all were fixed
// at root on 2026-07-10 (dossier docs/architecture/test-hardening-crash-chaos-
// config.md) and the laws now stand as armed regression guards. The consts are
// kept (false) so the fix history stays greppable and a regression is a
// one-line flip away from reproduction.

// LAW 3 (was T1): SettingsStore/AiSettingsStore/ReviewRatchetStore/
// LocalTelemetryStore now persist via writeFileAtomic (atomic_write.dart —
// tmp+flush+rename), so a torn write can never be observed: load() at every
// crash point yields only S1 or S2, never the defaults fallback.
const bool _knownFindingTornSnapshotFloorSkip = false;

// LAW 4 (was T2): AiSettingsStore.load() no longer re-persists defaults over a
// corrupt file — on parse failure it returns defaults in memory and leaves the
// on-disk bytes untouched (ai_settings_store.dart:272-283), so a torn file's
// forensic evidence survives.
const bool _knownFindingEvidenceDestructionSkip = false;

// LAW 6 (was T3): NudgeLedger._append now carries the last-byte torn-tail guard
// (nudge_ledger.dart:169-182) its sibling CommandTelemetryStore has — a torn
// prior line keeps its own trailing '\n' so the next event is never swallowed.
const bool _knownFindingNudgeTornTailSkip = false;

// LAW 7 addendum (was T4): AiAuditStore._loadEntries reads bytes + lenient
// utf8.decode(allowMalformed: true) (ai_audit_store.dart:118-119), so a torn
// multibyte tail degrades to U+FFFD instead of throwing and bricking every
// future read AND write of the log.
const bool _knownFindingTornUtf8Skip = false;

// UPGRADE 3 — AI model disk cache (_loadApiModelCacheFromDisk /
// _saveApiModelCacheToDisk, ai.dart): UNREACHABLE without a lib seam. Both are
// library-private, reached only via _resolveProviderModelDiscovery gated behind
// a live _ProviderKind.apiProvider spec + network discovery. No public or
// @visibleForTesting entry point reaches them, so a torn-write law here would
// require adding a seam to lib/ — out of scope for a test-only harness. The save
// path now rides writeFileAtomic (ai.dart:4525) by code review, and the loader
// is fully guarded (jsonDecode in try/catch, models.isEmpty => null), matching
// the LAW 3 floor contract; left unarmed pending a seam.
const bool _aiModelCacheUnreachableSkip = true;

// How many fuzzed S1/S2 pairs per law (× MANIFOLD_FUZZ). Each pair replays
// every crash point of the journalled persist, so this stays deliberately
// small — the crash-point sweep is where the coverage is.
int _cases() => 8 * fuzzScale();

Gen<int> _seedGen() => genInt(min: 1, max: 1 << 30);

const String _kRepo = '/fuzz/crash/repo';

// ── shared driver ────────────────────────────────────────────────────────

late Directory _root;

Directory _dir(String name) => Directory(p.join(_root.path, name));

/// Replays a crash at every point of `persistS2`'s journal (with S1 already on
/// disk) and hands each resulting on-disk state to [check]. [check] receives
/// the crash point, the loaded signature, the on-disk snapshot taken BEFORE
/// load() (so a re-persisting loader can't hide the torn bytes), and the live
/// replay directory (so a check can re-snapshot after load).
Future<void> _replayAllCrashPoints({
  required Future<void> Function() persistS1,
  required Future<void> Function() persistS2,
  required Future<String> Function() loadSig,
  required void Function() invalidate,
  required Future<void> Function(
    CrashPoint pt,
    String sig,
    Map<String, List<int>> preLoadSnapshot,
    Directory replayDir,
  ) check,
}) async {
  final journalDir = _dir('journal');
  await clearDir(journalDir);
  StoragePaths.debugOverrideDir = journalDir;
  invalidate();
  await persistS1();
  final base = await snapshotDir(journalDir);

  invalidate();
  final journal = await journalWrites(journalDir, () async {
    await persistS2();
  });
  expect(journal.ops, isNotEmpty,
      reason: 'persistS2 produced no journalled write effects');

  final points = enumerateCrashPoints(journal);
  final replayDir = _dir('replay');
  for (final pt in points) {
    await replayCrash(journal, base, replayDir, pt);
    StoragePaths.debugOverrideDir = replayDir;
    invalidate();
    final preLoadSnapshot = await snapshotDir(replayDir);
    final sig = await loadSig();
    await check(pt, sig, preLoadSnapshot, replayDir);
  }
}

void _expectMember(String sig, Map<String, String> allowed, CrashPoint pt) {
  expect(
    allowed.values.contains(sig),
    isTrue,
    reason: '$pt\n  loaded signature is not S1/S2/fallback.\n'
        '  got: $sig\n  allowed: $allowed',
  );
}

// ── LAW P driver ───────────────────────────────────────────────────────────

/// Journals `persistS2` (with S1 already durable), enumerates the power-loss
/// states of that journal, and replays each. [onPoints] sees the full point
/// set (so a store can assert flush:true left it empty); [checkPoint] runs
/// with `debugOverrideDir` pointed at each torn state; [checkFullReplay] runs
/// against the fully-applied journal (the S2 replay-fidelity anchor).
Future<void> _powerLossSweep({
  required Future<void> Function() persistS1,
  required Future<void> Function() persistS2,
  required void Function() invalidate,
  required void Function(List<PowerLossPoint> points) onPoints,
  required Future<void> Function(PowerLossPoint pt) checkPoint,
  required Future<void> Function() checkFullReplay,
}) async {
  final journalDir = _dir('pl-journal');
  await clearDir(journalDir);
  StoragePaths.debugOverrideDir = journalDir;
  invalidate();
  await persistS1();
  final base = await snapshotDir(journalDir);

  invalidate();
  final journal = await journalWrites(journalDir, () async {
    await persistS2();
  });
  expect(journal.ops, isNotEmpty,
      reason: 'persistS2 produced no journalled write effects');

  final points = enumeratePowerLossPoints(journal);
  onPoints(points);

  final replayDir = _dir('pl-replay');
  for (final pt in points) {
    await replayPowerLoss(journal, base, replayDir, pt);
    StoragePaths.debugOverrideDir = replayDir;
    invalidate();
    await checkPoint(pt);
  }

  // Replay-fidelity: nothing torn ⇒ exactly S2.
  await replayFull(journal, base, replayDir);
  StoragePaths.debugOverrideDir = replayDir;
  invalidate();
  await checkFullReplay();
}

// ── LAW R driver ───────────────────────────────────────────────────────────

/// Drives crash-during-recovery for one store. Builds every first-generation
/// torn state from `persistS2` (over base S1) plus the missing-file state,
/// then for each: journals what load() writes (its recovery write), crashes
/// THAT write at every point, and asserts the reload lands in [allowed] and
/// stabilises (a third load equals the second). When load() writes nothing
/// (a store that leaves a torn file untouched) the idempotence check still
/// runs on the untouched state.
Future<void> _lawRFixpoint({
  required String label,
  required Future<void> Function() persistS1,
  required Future<void> Function() persistS2,
  required void Function() invalidate,
  required Future<String> Function() loadSig,
  required Set<String> allowed,
}) async {
  final journalDir = _dir('r-journal');
  await clearDir(journalDir);
  StoragePaths.debugOverrideDir = journalDir;
  invalidate();
  await persistS1();
  final base = await snapshotDir(journalDir);
  invalidate();
  final journal = await journalWrites(journalDir, () async {
    await persistS2();
  });

  // First-generation torn states: every crash point of the S2 persist, plus
  // the missing-file state (which forces stores that persist defaults for an
  // absent file to actually run their recovery write).
  final firstGenDir = _dir('r-firstgen');
  final tornStates = <Map<String, List<int>>>[];
  for (final pt in enumerateCrashPoints(journal)) {
    await replayCrash(journal, base, firstGenDir, pt);
    tornStates.add(await snapshotDir(firstGenDir));
  }
  tornStates.add(<String, List<int>>{}); // missing-file first-gen

  final workDir = _dir('r-work');
  final recoveryDir = _dir('r-recovery');
  for (final torn in tornStates) {
    // Journal what load() itself writes, starting from the torn state.
    await clearDir(workDir);
    await restoreSnapshot(torn, workDir);
    StoragePaths.debugOverrideDir = workDir;
    invalidate();
    var firstSig = '';
    final recovery = await journalWrites(workDir, () async {
      firstSig = await loadSig();
    });
    expect(allowed.contains(firstSig), isTrue,
        reason: '$label: first recovery load not in allowed set: $firstSig');

    if (recovery.ops.isEmpty) {
      // Store left the torn file untouched (e.g. SettingsStore's parse-fail
      // path). Idempotence must still hold across reloads.
      await clearDir(recoveryDir);
      await restoreSnapshot(torn, recoveryDir);
      StoragePaths.debugOverrideDir = recoveryDir;
      invalidate();
      final s2 = await loadSig();
      invalidate();
      final s3 = await loadSig();
      expect(allowed.contains(s2), isTrue,
          reason: '$label: untouched-state reload not allowed: $s2');
      expect(s3, s2,
          reason: '$label: load not idempotent on an untouched torn state');
      continue;
    }

    // The recovery write is itself crashable: crash it at every point and
    // require the next load to land in [allowed] and reach a fixpoint.
    for (final pt in enumerateCrashPoints(recovery)) {
      await replayCrash(recovery, torn, recoveryDir, pt);
      StoragePaths.debugOverrideDir = recoveryDir;
      invalidate();
      final s2 = await loadSig();
      expect(allowed.contains(s2), isTrue,
          reason: '$label @ crash-during-recovery $pt: not allowed: $s2');
      invalidate();
      final s3 = await loadSig();
      expect(s3, s2,
          reason: '$label @ crash-during-recovery $pt: no fixpoint '
              '(load $s3 != reload $s2)');
    }
  }
}

/// A small [SpectralBasis] with fuzzed spectra. Signature derives from the
/// eigenvalues, so the on-disk filename is content-addressed.
SpectralBasis _genBasis(Rng rng) {
  final n = rng.intBetween(1, 4);
  final k = rng.intBetween(1, 3);
  final eigenvalues = Float64List.fromList(
      List<double>.generate(k, (_) => rng.nextDouble() * 4));
  final eigenvectors = Float64List.fromList(
      List<double>.generate(k * n, (_) => rng.nextDouble() * 2 - 1));
  return SpectralBasis(
    n: n,
    k: k,
    eigenvalues: eigenvalues,
    eigenvectors: eigenvectors,
  );
}

// ── local generators ──────────────────────────────────────────────────────

/// A short string, safe as a JSON value, that may carry hostile unicode in its
/// interior (built via gen.dart — never pasted as raw control characters).
Gen<String> _gStr({int maxLen = 12}) => (rng) => rng.nextBool()
    ? 'x${genUnicodeHostile(maxLen: maxLen)(rng)}'
    : 'x${genAscii(maxLen: maxLen)(rng)}';

/// A lowercase-ascii, non-empty key (safe as a map key that survives trimming).
Gen<String> _gKey({int maxLen = 8}) => (rng) {
      final body = genAscii(maxLen: maxLen)(rng)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      return 'k$body';
    };

// AiApiKeysSnapshot ---------------------------------------------------------

AiApiKeysSnapshot _genApiKeys(Rng rng, String marker) {
  final entries = <String, AiApiKeyEntry>{};
  final n = rng.intBetween(0, 3);
  for (var i = 0; i < n; i++) {
    entries['${_gKey()(rng)}$i'] = AiApiKeyEntry(
      apiKey: 'secret-${_gStr()(rng)}', // non-empty so fromJson keeps it
      baseUrl: rng.nextBool() ? 'https://${_gKey()(rng)}.example' : null,
    );
  }
  // Marker entry guarantees S1 != S2 (and != empty).
  entries['marker_$marker'] =
      AiApiKeyEntry(apiKey: 'mk-$marker-${rng.intBetween(0, 1 << 20)}');
  return AiApiKeysSnapshot(entries: entries);
}

String _apiSig(AiApiKeysSnapshot s) =>
    jsonEncode(AiApiKeysSnapshot.fromJson(s.toJson()).toJson());

// ShadowCouplingCacheData ---------------------------------------------------

ShadowCouplingCacheData _genShadow(Rng rng, String marker) {
  final edges = <String, Map<String, double>>{};
  final n = rng.intBetween(1, 3);
  for (var i = 0; i < n; i++) {
    edges['${_gKey()(rng)}$i'] = {
      for (var j = 0; j <= rng.intBetween(0, 2); j++)
        '${_gKey()(rng)}$j': rng.nextDouble(),
    };
  }
  return ShadowCouplingCacheData(
    headHash: 'head-$marker-${rng.intBetween(0, 1 << 20)}',
    discoveredAt: DateTime.fromMillisecondsSinceEpoch(
        1600000000000 + rng.intBetween(0, 1 << 30)),
    shadowCommitCount: rng.intBetween(0, 5000),
    jaccardEdges: edges,
    edgeTypeCounts: {'shadow': rng.intBetween(0, 100)},
  );
}

String _shadowSig(ShadowCouplingCacheData s) =>
    jsonEncode(ShadowCouplingCacheData.fromJson(s.toJson()).toJson());

// EngramFileIndexCache ------------------------------------------------------

const int _kEngramPairs = 2;

Map<String, EngramFileIndexCacheEntry> _genEngram(Rng rng, String marker) {
  final out = <String, EngramFileIndexCacheEntry>{};
  final n = rng.intBetween(0, 2);
  for (var i = 0; i < n; i++) {
    out['path/${_gKey()(rng)}$i.dart'] = _engramEntry(rng);
  }
  out['path/marker_$marker.dart'] = _engramEntry(rng);
  return out;
}

EngramFileIndexCacheEntry _engramEntry(Rng rng) {
  Float64List vec() => Float64List.fromList(
      List<double>.generate(_kEngramPairs, (_) => rng.nextDouble() * 10 - 5));
  return EngramFileIndexCacheEntry(
    mtimeMs: rng.intBetween(0, 1 << 40),
    size: rng.intBetween(0, 1 << 30),
    kVector: HunkKVector(
      kRe: vec(),
      kIm: vec(),
      gRe: vec(),
      gIm: vec(),
      meanRms: rng.nextDouble(),
      vocabHits: rng.intBetween(0, 500),
      well: null,
    ),
  );
}

String _engramEntrySig(EngramFileIndexCacheEntry e) =>
    '${e.mtimeMs}/${e.size}/${e.kVector.meanRms}/${e.kVector.vocabHits}/'
    '${e.kVector.kRe.join(",")}/${e.kVector.gRe.join(",")}';

/// Signature of a loaded cache over a fixed [union] path set (absent-tolerant),
/// so S1, S2 and the empty cache produce comparable, distinct strings.
String _engramSigCache(EngramFileIndexCache c, List<String> union) {
  final parts = <String>['size=${c.size}'];
  for (final path in union) {
    final e = c.get(path);
    parts.add(e == null ? '$path=absent' : '$path=${_engramEntrySig(e)}');
  }
  return parts.join('|');
}

/// Reference signature computed directly from the intended entries — the on-
/// disk binary codec is lossless, so a full load reproduces exactly this.
String _engramSigEntries(
    Map<String, EngramFileIndexCacheEntry> m, List<String> union) {
  final parts = <String>['size=${m.length}'];
  for (final path in union) {
    final e = m[path];
    parts.add(e == null ? '$path=absent' : '$path=${_engramEntrySig(e)}');
  }
  return parts.join('|');
}

// AppSettingsSnapshot -------------------------------------------------------

AppSettingsSnapshot _genSettings(Rng rng, String marker) {
  // Start from defaults, then perturb distinctive fields so the snapshot is
  // guaranteed != defaults() (else a torn->defaults fallback would masquerade
  // as a valid S1/S2 and the aspirational finding wouldn't be red).
  return AppSettingsSnapshot.defaults().copyWith(
    themeId: 'theme-$marker-${_gStr()(rng)}',
    guardrailValue: 0.01 + rng.nextDouble() * 0.98,
    appShortName: 'nm$marker',
    sidebarWidthPx: rng.intBetween(141, 379),
    onboardingComplete: true,
    giteaTokens: {'host-$marker': 'tok-${_gKey()(rng)}'},
    wickExePath: 'C:/tools/${_gStr()(rng)}',
  );
}

String _settingsSig(AppSettingsSnapshot s) =>
    jsonEncode(AppSettingsSnapshot.fromJson(s.toJson()).toJson());

// AiSettingsSnapshot --------------------------------------------------------

AiSettingsSnapshot _genAiSettings(Rng rng, String marker) {
  return AiSettingsSnapshot.defaults().copyWith(
    commitMessageModelCategoryId: 'cat-$marker',
    reviewCommitDoubleCheckEnabled: true,
    modelSelections: {'quality': 'model-${_gKey()(rng)}-$marker'},
  );
}

String _aiSettingsSig(AiSettingsSnapshot s) =>
    jsonEncode(AiSettingsSnapshot.fromJson(s.toJson()).toJson());

// ReviewRatchet -------------------------------------------------------------

ClaimOutcomeRatchet _genRatchet(Rng rng, String marker) {
  final map = <String, dynamic>{};
  final n = rng.intBetween(0, 3);
  for (var i = 0; i < n; i++) {
    map['${rng.intBetween(1, 1 << 30)}'] = {
      'a': rng.intBetween(0, 50),
      'r': rng.intBetween(0, 50),
    };
  }
  map['${marker == 's1' ? 111111 : 222222}'] = {
    'a': marker == 's1' ? 1 : 2,
    'r': rng.intBetween(1, 9),
  };
  return ClaimOutcomeRatchet.fromJsonString(jsonEncode(map));
}

// LocalTelemetry ------------------------------------------------------------

const String _kTelemetryFile = 'fuzz_telemetry.json';

List<dynamic> _genTelemetryList(Rng rng, String marker) {
  final out = <dynamic>[
    {'marker': marker, 'seq': rng.intBetween(0, 1 << 20)},
  ];
  final n = rng.intBetween(0, 3);
  for (var i = 0; i < n; i++) {
    out.add({'k': _gKey()(rng), 'v': rng.intBetween(0, 100)});
  }
  return out;
}

// AiAuditEntryData ----------------------------------------------------------

/// ASCII-safe entry: every field is single-byte printable ASCII, so a byte-cut
/// anywhere still leaves valid UTF-8 (the armed LAW 7 isolates JSON-level line
/// tolerance from the separate torn-multibyte finding below).
AiAuditEntryData _genAuditEntry(Rng rng, String tag) => AiAuditEntryData(
      id: '$tag-${rng.intBetween(0, 1 << 30)}',
      event: 'review',
      providerId: 'prov-${_gKey()(rng)}',
      repositoryHint: 'r${genAscii(maxLen: 12)(rng)}',
      diffScopePath: rng.nextBool() ? 'd${genAscii(maxLen: 12)(rng)}' : null,
      promptPreview: 'p${genAscii(maxLen: 20)(rng)}',
      outputPreview: 'o${genAscii(maxLen: 20)(rng)}',
      ok: rng.nextBool(),
      errorCode: rng.nextBool() ? 'e-${_gKey()(rng)}' : null,
      createdAt: DateTime.now().toUtc().toIso8601String(), // recent: retained
    );

String _auditSig(AiAuditEntryData e) => jsonEncode(e.toJson());

// ── setup ─────────────────────────────────────────────────────────────────

void main() {
  setUp(() async {
    _root = await Directory.systemTemp.createTemp('gdpu-crash-fuzz-');
  });

  tearDown(() async {
    StoragePaths.debugOverrideDir = null;
    SettingsStore.invalidateCache();
    SettingsStore.debugSuppressDiskWrites = false;
    if (await _root.exists()) {
      try {
        await _root.delete(recursive: true);
      } on FileSystemException {
        // best-effort temp cleanup; a lingering handle must not fail the suite
      }
    }
  });

  // ── LAW 1 ────────────────────────────────────────────────────────────
  group('law 1: crash-atomicity (tmp+rename stores yield only S1 or S2)', () {
    test('AiApiKeysStore.persist is atomic at every crash point', () async {
      await forAllAsync<int>(
        _seedGen(),
        count: _cases(),
        describe: 'crash-atomicity api-keys',
        check: (seed) async {
          final rng = Rng(seed);
          final s1 = _genApiKeys(rng, 's1');
          final s2 = _genApiKeys(rng, 's2');
          final allowed = {'S1': _apiSig(s1), 'S2': _apiSig(s2)};
          await _replayAllCrashPoints(
            persistS1: () => AiApiKeysStore.persist(s1),
            persistS2: () => AiApiKeysStore.persist(s2),
            loadSig: () async => _apiSig(await AiApiKeysStore.load()),
            invalidate: () {},
            check: (pt, sig, _, __) async => _expectMember(sig, allowed, pt),
          );
        },
      );
    });

    test('ShadowCouplingCache.save is atomic; target never vanishes', () async {
      await forAllAsync<int>(
        _seedGen(),
        count: _cases(),
        describe: 'crash-atomicity shadow',
        check: (seed) async {
          final rng = Rng(seed);
          final s1 = _genShadow(rng, 's1');
          final s2 = _genShadow(rng, 's2');
          final allowed = {'S1': _shadowSig(s1), 'S2': _shadowSig(s2)};
          await _replayAllCrashPoints(
            persistS1: () => ShadowCouplingCache.save(_kRepo, s1),
            persistS2: () => ShadowCouplingCache.save(_kRepo, s2),
            loadSig: () async {
              final loaded = await ShadowCouplingCache.load(_kRepo);
              expect(loaded, isNotNull,
                  reason: 'tmp+rename cache must never present as absent');
              return _shadowSig(loaded!);
            },
            invalidate: () {},
            check: (pt, sig, _, __) async => _expectMember(sig, allowed, pt),
          );
        },
      );
    });
  });

  // ── LAW 2 ────────────────────────────────────────────────────────────
  // Breadcrumb: was finding T5 (delete-then-rename absence window). Fixed
  // 2026-07-10 — engram now writes tmp with flush:true then an atomic rename
  // (no delete-first), graduating it to the LAW-1 crash-atomicity tier.
  group('law 2: crash-atomicity (EngramFileIndexCache tmp+rename)', () {
    test('load yields ONLY S1/S2; the delete-then-rename window is GONE',
        () async {
      await forAllAsync<int>(
        _seedGen(),
        count: _cases(),
        describe: 'engram crash-atomicity',
        check: (seed) async {
          final rng = Rng(seed);
          final s1 = _genEngram(rng, 's1');
          final s2 = _genEngram(rng, 's2');
          final union = <String>{...s1.keys, ...s2.keys}.toList()..sort();
          final emptySig = _engramSigCache(EngramFileIndexCache.empty(), union);
          final allowed = {
            'S1': _engramSigEntries(s1, union),
            'S2': _engramSigEntries(s2, union),
          };
          await _replayAllCrashPoints(
            persistS1: () => EngramFileIndexCache.save(
                repoPath: _kRepo, pairs: _kEngramPairs, entries: s1),
            persistS2: () => EngramFileIndexCache.save(
                repoPath: _kRepo, pairs: _kEngramPairs, entries: s2),
            loadSig: () async {
              final loaded = await EngramFileIndexCache.load(
                  repoPath: _kRepo, expectedPairs: _kEngramPairs);
              return _engramSigCache(loaded, union);
            },
            invalidate: () {},
            check: (pt, sig, _, __) async {
              _expectMember(sig, allowed, pt);
              // The absence window is closed: tmp+rename (no delete-first) can
              // never present the cache as absent/empty at any crash point.
              expect(sig, isNot(emptySig),
                  reason: '$pt: a crash left the cache empty — the '
                      'delete-then-rename window has regressed');
            },
          );
        },
      );
    });
  });

  // ── LAW 3 (armed) ─────────────────────────────────────────────────────
  // Breadcrumb: was finding T1 (non-atomic snapshot wipe). Fixed 2026-07-10 —
  // all four stores persist via writeFileAtomic, so the allowed set is now the
  // strict {S1, S2} crash-atomicity floor (no defaults/empty fallback).
  group('law 3: torn-snapshot floor — only S1 or S2, never franken', () {
    Future<void> runFloor<T>({
      required String describe,
      required T Function(Rng) genS1,
      required T Function(Rng) genS2,
      required Future<void> Function(T) persist,
      required Future<String> Function() loadSig,
      required void Function() invalidate,
      required Map<String, String> Function(T s1, T s2) allowed,
    }) async {
      await forAllAsync<int>(
        _seedGen(),
        count: _cases(),
        describe: describe,
        check: (seed) async {
          final rng = Rng(seed);
          final s1 = genS1(rng);
          final s2 = genS2(rng);
          final allow = allowed(s1, s2);
          await _replayAllCrashPoints(
            persistS1: () => persist(s1),
            persistS2: () => persist(s2),
            loadSig: loadSig,
            invalidate: invalidate,
            check: (pt, sig, _, __) async => _expectMember(sig, allow, pt),
          );
        },
      );
    }

    test('SettingsStore', () async {
      await runFloor<AppSettingsSnapshot>(
        describe: 'floor settings',
        genS1: (r) => _genSettings(r, 's1'),
        genS2: (r) => _genSettings(r, 's2'),
        persist: SettingsStore.persist,
        loadSig: () async => _settingsSig(await SettingsStore.load()),
        invalidate: SettingsStore.invalidateCache,
        allowed: (s1, s2) => {
          'S1': _settingsSig(s1),
          'S2': _settingsSig(s2),
        },
      );
    });

    test('AiSettingsStore', () async {
      await runFloor<AiSettingsSnapshot>(
        describe: 'floor ai-settings',
        genS1: (r) => _genAiSettings(r, 's1'),
        genS2: (r) => _genAiSettings(r, 's2'),
        persist: AiSettingsStore.persist,
        loadSig: () async => _aiSettingsSig(await AiSettingsStore.load()),
        invalidate: () {},
        allowed: (s1, s2) => {
          'S1': _aiSettingsSig(s1),
          'S2': _aiSettingsSig(s2),
        },
      );
    });

    test('ReviewRatchetStore', () async {
      await runFloor<ClaimOutcomeRatchet>(
        describe: 'floor review-ratchet',
        genS1: (r) => _genRatchet(r, 's1'),
        genS2: (r) => _genRatchet(r, 's2'),
        persist: (rat) => ReviewRatchetStore.persist(_kRepo, rat),
        loadSig: () async =>
            (await ReviewRatchetStore.load(_kRepo)).toJsonString(),
        invalidate: () {},
        allowed: (s1, s2) => {
          'S1': s1.toJsonString(),
          'S2': s2.toJsonString(),
        },
      );
    });

    test('LocalTelemetryStore', () async {
      await runFloor<List<dynamic>>(
        describe: 'floor local-telemetry',
        genS1: (r) => _genTelemetryList(r, 's1'),
        genS2: (r) => _genTelemetryList(r, 's2'),
        persist: (list) => LocalTelemetryStore.writeList(_kTelemetryFile, list),
        loadSig: () async =>
            jsonEncode(await LocalTelemetryStore.readList(_kTelemetryFile)),
        invalidate: () {},
        allowed: (s1, s2) => {
          'S1': jsonEncode(s1),
          'S2': jsonEncode(s2),
        },
      );
    });
  });

  // ── LAW 3 (atomicity regression guard) ────────────────────────────────
  // Breadcrumb: was finding T1's aspirational sub-law (SettingsStore yields
  // ONLY S1 or S2 under a torn write). Fixed 2026-07-10 via writeFileAtomic —
  // now an armed regression guard: the allowed set has NO fallback, so a
  // mid-write crash landing on defaults would fail.
  test(
    'law 3 (armed): SettingsStore is crash-atomic — only S1 or S2',
    () async {
      final rng = Rng(0x5EED);
      final s1 = _genSettings(rng, 's1');
      final s2 = _genSettings(rng, 's2');
      final allowed = {'S1': _settingsSig(s1), 'S2': _settingsSig(s2)};
      await _replayAllCrashPoints(
        persistS1: () => SettingsStore.persist(s1),
        persistS2: () => SettingsStore.persist(s2),
        loadSig: () async => _settingsSig(await SettingsStore.load()),
        invalidate: SettingsStore.invalidateCache,
        check: (pt, sig, _, __) async => _expectMember(sig, allowed, pt),
      );
    },
    skip: _knownFindingTornSnapshotFloorSkip,
  );

  // ── LAW 4 (evidence-preservation regression guard) ────────────────────
  // Breadcrumb: was finding T2 (load re-persisted defaults over a torn file).
  // Fixed 2026-07-10 — load() returns defaults in memory without touching disk.
  test(
    'law 4 (armed): AiSettingsStore.load does not overwrite a torn file '
    '(evidence + partially-valid user data survive)',
    () async {
      final rng = Rng(0x5EED);
      final s1 = _genAiSettings(rng, 's1');
      final s2 = _genAiSettings(rng, 's2');
      await _replayAllCrashPoints(
        persistS1: () => AiSettingsStore.persist(s1),
        persistS2: () => AiSettingsStore.persist(s2),
        loadSig: () async => _aiSettingsSig(await AiSettingsStore.load()),
        invalidate: () {},
        check: (pt, sig, preLoadSnapshot, replayDir) async {
          // load() already ran (loadSig). Compare disk bytes BEFORE that load
          // with disk bytes AFTER it: they must be identical (no rewrite).
          final postLoadSnapshot = await snapshotDir(replayDir);
          expect(
            _snapEquals(preLoadSnapshot, postLoadSnapshot),
            isTrue,
            reason: '$pt\n  ai_settings.json was rewritten by load(): the torn '
                'on-disk bytes were destroyed.',
          );
        },
      );
    },
    skip: _knownFindingEvidenceDestructionSkip,
  );

  // ── LAW 5 (armed) ─────────────────────────────────────────────────────
  test('law 5: CommandTelemetryStore append is torn-tail guarded', () async {
    // Retention reads settings; seed the cache so it never touches disk.
    SettingsStore.seedForTest(AppSettingsSnapshot.defaults());
    await forAllAsync<int>(
      _seedGen(),
      count: _cases(),
      describe: 'append-isolation command-telemetry',
      check: (seed) async {
        final rng = Rng(seed);
        final priorCount = rng.intBetween(1, 3);
        final priorCommands = <String>[
          for (var i = 0; i < priorCount; i++) 'prior-cmd-$i',
        ];
        const appendedCommand = 'appended-cmd';
        const subsequentCommand = 'subsequent-cmd';

        final journalDir = _dir('ct-journal');
        await clearDir(journalDir);
        StoragePaths.debugOverrideDir = journalDir;
        for (final c in priorCommands) {
          await CommandTelemetryStore.recordSample(
              scope: 'fuzz', command: c, ok: true, durationMs: 3);
        }
        final base = await snapshotDir(journalDir);

        // Journal exactly the appended record.
        final journal = await journalWrites(journalDir, () async {
          await CommandTelemetryStore.recordSample(
              scope: 'fuzz', command: appendedCommand, ok: true, durationMs: 4);
        });

        final replayDir = _dir('ct-replay');
        for (final pt in enumerateCrashPoints(journal)) {
          await replayCrash(journal, base, replayDir, pt);
          StoragePaths.debugOverrideDir = replayDir;
          // A subsequent real append over the (possibly torn) tail.
          await CommandTelemetryStore.recordSample(
              scope: 'fuzz',
              command: subsequentCommand,
              ok: true,
              durationMs: 5);
          final snap = await CommandTelemetryStore.getSnapshot(recentLimit: 50);
          final commands = snap.recentSamples.map((s) => s.command).toList();
          for (final c in priorCommands) {
            expect(commands, contains(c),
                reason: '$pt: prior record "$c" lost');
          }
          expect(commands, contains(subsequentCommand),
              reason: '$pt: subsequent append corrupted / swallowed');
          // No franken sample: count is prior + subsequent (+1 iff the appended
          // record survived whole).
          expect(
            snap.sampleCount == priorCount + 1 ||
                snap.sampleCount == priorCount + 2,
            isTrue,
            reason: '$pt: unexpected sample count ${snap.sampleCount} '
                '(prior=$priorCount)',
          );
        }
      },
    );
  });

  // ── LAW 6 (torn-tail regression guard) ────────────────────────────────
  // Breadcrumb: was finding T3 (no torn-tail guard swallowed the next event).
  // Fixed 2026-07-10 — NudgeLedger._append prepends '\n' after a torn line.
  test(
    'law 6 (armed): NudgeLedger append survives a torn tail '
    '(the next event is never swallowed)',
    () async {
      final rng = Rng(0x5EED);
      final storageDir = _dir('nudge');
      await clearDir(storageDir);

      // A valid event line, torn mid-bytes (no trailing newline) to model a
      // crash during a prior append.
      final tornEvent = NudgeEvent(
        ts: DateTime.now().toUtc().toIso8601String(),
        kind: 'shown',
        path: 'lib/${_gKey()(rng)}.dart',
        anchor: 'lib/${_gKey()(rng)}.dart',
        score: rng.nextDouble(),
        receipts: rng.nextBool(),
      );
      final tornLine = jsonEncode(tornEvent.toJson());
      final tornPrefix = tornLine.substring(0, tornLine.length ~/ 2);

      final file = _nudgeFile(storageDir);
      await file.parent.create(recursive: true);
      await file.writeAsString(tornPrefix); // no trailing '\n'

      // A real subsequent append.
      final ledger = NudgeLedger(_kRepo, storageDirOverride: storageDir);
      ledger.recordAccepted(
        path: 'lib/accepted.dart',
        anchor: 'lib/anchor.dart',
        score: 0.99,
        receipts: true,
      );
      final events = await ledger.readAll();

      expect(
        events
            .any((e) => e.kind == 'accepted' && e.path == 'lib/accepted.dart'),
        isTrue,
        reason: 'event B was swallowed by the torn tail of event A',
      );
    },
    skip: _knownFindingNudgeTornTailSkip,
  );

  // ── LAW 7 (armed) ─────────────────────────────────────────────────────
  test('law 7: AiAuditStore mid-rewrite yields a clean entry prefix',
      () async {
    await forAllAsync<int>(
      _seedGen(),
      count: _cases(),
      describe: 'rewrite-tolerance ai-audit',
      check: (seed) async {
        final rng = Rng(seed);
        final priorCount = rng.intBetween(0, 3);
        final prior = [
          for (var i = 0; i < priorCount; i++) _genAuditEntry(rng, 'prior$i'),
        ];
        final appended = _genAuditEntry(rng, 'appended');
        final full = [...prior, appended]; // full retained set after append
        final fullSigs = [for (final e in full) _auditSig(e)];

        final journalDir = _dir('audit-journal');
        await clearDir(journalDir);
        StoragePaths.debugOverrideDir = journalDir;
        for (final e in prior) {
          await AiAuditStore.recordEntry(e);
        }
        final base = await snapshotDir(journalDir);
        final journal = await journalWrites(journalDir, () async {
          await AiAuditStore.recordEntry(appended);
        });

        final replayDir = _dir('audit-replay');
        for (final pt in enumerateCrashPoints(journal)) {
          await replayCrash(journal, base, replayDir, pt);
          StoragePaths.debugOverrideDir = replayDir;
          final list = await AiAuditStore.getEntries(limit: 1000);
          final loadedSigs = [for (final e in list.entries) _auditSig(e)];
          // Every loaded entry is a genuine entry (no franken line) and the set
          // is an in-order prefix of the intended full write.
          expect(loadedSigs.length, lessThanOrEqualTo(fullSigs.length),
              reason: '$pt: more entries than were ever written');
          for (var i = 0; i < loadedSigs.length; i++) {
            expect(loadedSigs[i], equals(fullSigs[i]),
                reason: '$pt: entry $i is not the genuine entry '
                    '(franken or reordered)');
          }
        }
      },
    );
  });

  // ── LAW 7 addendum (torn-UTF-8 regression guard) ──────────────────────
  // Breadcrumb: was finding T4 (strict readAsLines threw on a torn multibyte
  // tail + bricked the log). Fixed 2026-07-10 — lenient utf8.decode degrades
  // the torn codepoint to U+FFFD instead of throwing.
  test(
    'law 7 addendum (armed): AiAuditStore load tolerates a torn multibyte '
    'write (degrades, never throws)',
    () async {
      final rng = Rng(0x5EED);
      // A field that is a run of 4-byte code points, so many byte cuts land
      // mid-codepoint and leave an invalid UTF-8 tail. Built from an ASCII
      // integer, never pasted (see gen.dart's NUL-in-source note).
      final emojiRun = String.fromCharCodes(List<int>.filled(8, 0x1F525));
      final entry = AiAuditEntryData(
        id: 'utf8-${rng.intBetween(0, 1 << 30)}',
        event: 'review',
        providerId: 'prov',
        repositoryHint: 'repo',
        diffScopePath: null,
        promptPreview: emojiRun,
        outputPreview: emojiRun,
        ok: true,
        errorCode: null,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );

      final journalDir = _dir('utf8-journal');
      await clearDir(journalDir);
      StoragePaths.debugOverrideDir = journalDir;
      final base = await snapshotDir(journalDir);
      final journal = await journalWrites(journalDir, () async {
        await AiAuditStore.recordEntry(entry);
      });

      final replayDir = _dir('utf8-replay');
      for (final pt in enumerateCrashPoints(journal)) {
        await replayCrash(journal, base, replayDir, pt);
        StoragePaths.debugOverrideDir = replayDir;
        // A torn multibyte write must degrade, never throw: lenient decode
        // substitutes U+FFFD for the torn codepoint. A throw here (the old
        // strict readAsLines behaviour) would fail the test.
        await AiAuditStore.getEntries(limit: 1000);
      }
    },
    skip: _knownFindingTornUtf8Skip,
  );

  // ── LAW 8 (armed) ─────────────────────────────────────────────────────
  test('law 8: a torn SettingsStore write never mutates another store file',
      () async {
    await forAllAsync<int>(
      _seedGen(),
      count: _cases(),
      describe: 'cross-file blast radius',
      check: (seed) async {
        final rng = Rng(seed);
        final s1 = _genSettings(rng, 's1');
        final s2 = _genSettings(rng, 's2');

        final journalDir = _dir('blast-journal');
        await clearDir(journalDir);
        StoragePaths.debugOverrideDir = journalDir;
        SettingsStore.invalidateCache();
        await SettingsStore.persist(s1);
        // Seed sentinel files for unrelated stores.
        final sentinels = <String, String>{
          'ai/api_keys.json': '{"sentinel":"api"}',
          'command_telemetry.jsonl': '{"sentinel":"telemetry"}\n',
          'nudge_ledger/deadbeef.jsonl': '{"sentinel":"nudge"}\n',
        };
        for (final e in sentinels.entries) {
          final f = File(p.joinAll([journalDir.path, ...e.key.split('/')]));
          await f.parent.create(recursive: true);
          await f.writeAsString(e.value);
        }
        final base = await snapshotDir(journalDir);

        SettingsStore.invalidateCache();
        final journal = await journalWrites(journalDir, () async {
          await SettingsStore.persist(s2);
        });

        final replayDir = _dir('blast-replay');
        for (final pt in enumerateCrashPoints(journal)) {
          await replayCrash(journal, base, replayDir, pt);
          StoragePaths.debugOverrideDir = replayDir;
          SettingsStore.invalidateCache();
          await SettingsStore.load();
          final after = await snapshotDir(replayDir);
          for (final key in base.keys) {
            if (key == 'settings.json') continue;
            expect(after.containsKey(key), isTrue,
                reason: '$pt: unrelated file "$key" vanished');
            expect(_bytesEqual(after[key]!, base[key]!), isTrue,
                reason: '$pt: unrelated file "$key" was mutated');
          }
        }
      },
    );
  });

  // ── LAW P — power-loss / write-reordering durability ──────────────────
  group('law P: power-loss durability (unflushed writes can tear post-rename)',
      () {
    test('AiApiKeysStore flush:true tmp write has NO power-loss surface',
        () async {
      await forAllAsync<int>(
        _seedGen(),
        count: _cases(),
        describe: 'power-loss api-keys',
        check: (seed) async {
          final rng = Rng(seed);
          final s1 = _genApiKeys(rng, 's1');
          final s2 = _genApiKeys(rng, 's2');
          await _powerLossSweep(
            persistS1: () => AiApiKeysStore.persist(s1),
            persistS2: () => AiApiKeysStore.persist(s2),
            invalidate: () {},
            onPoints: (points) => expect(points, isEmpty,
                reason: 'flush:true tmp write must expose no power-loss point'),
            checkPoint: (pt) async {},
            checkFullReplay: () async =>
                expect(_apiSig(await AiApiKeysStore.load()), _apiSig(s2)),
          );
        },
      );
    });

    test('ShadowCouplingCache flush:true tmp write has NO power-loss surface',
        () async {
      await forAllAsync<int>(
        _seedGen(),
        count: _cases(),
        describe: 'power-loss shadow',
        check: (seed) async {
          final rng = Rng(seed);
          final s1 = _genShadow(rng, 's1');
          final s2 = _genShadow(rng, 's2');
          await _powerLossSweep(
            persistS1: () => ShadowCouplingCache.save(_kRepo, s1),
            persistS2: () => ShadowCouplingCache.save(_kRepo, s2),
            invalidate: () {},
            onPoints: (points) => expect(points, isEmpty,
                reason: 'flush:true tmp write must expose no power-loss point'),
            checkPoint: (pt) async {},
            checkFullReplay: () async {
              final loaded = await ShadowCouplingCache.load(_kRepo);
              expect(loaded, isNotNull);
              expect(_shadowSig(loaded!), _shadowSig(s2));
            },
          );
        },
      );
    });

    // Breadcrumb: was finding T5 (unflushed tmp tore post-rename, degrading to
    // empty). Fixed 2026-07-10 — tmp now writes flush:true, so engram joins the
    // api-keys/shadow cells with NO power-loss surface at all.
    test(
        'EngramFileIndexCache flush:true tmp write has NO power-loss surface',
        () async {
      await forAllAsync<int>(
        _seedGen(),
        count: _cases(),
        describe: 'power-loss engram',
        check: (seed) async {
          final rng = Rng(seed);
          final s1 = _genEngram(rng, 's1');
          final s2 = _genEngram(rng, 's2');
          final union = <String>{...s1.keys, ...s2.keys}.toList()..sort();
          await _powerLossSweep(
            persistS1: () => EngramFileIndexCache.save(
                repoPath: _kRepo, pairs: _kEngramPairs, entries: s1),
            persistS2: () => EngramFileIndexCache.save(
                repoPath: _kRepo, pairs: _kEngramPairs, entries: s2),
            invalidate: () {},
            onPoints: (points) => expect(points, isEmpty,
                reason: 'flush:true tmp write must expose no power-loss point '
                    '(the durability gap vs the flush:true stores is closed)'),
            checkPoint: (pt) async {},
            checkFullReplay: () async {
              final loaded = await EngramFileIndexCache.load(
                  repoPath: _kRepo, expectedPairs: _kEngramPairs);
              expect(_engramSigCache(loaded, union),
                  _engramSigEntries(s2, union),
                  reason: 'full power-loss replay must reproduce S2 exactly');
            },
          );
        },
      );
    });
  });

  // ── LAW R — crash-during-recovery fixpoint ────────────────────────────
  group('law R: recovery is itself crashable and must reach a fixpoint', () {
    test('SettingsStore load-driven recovery is idempotent', () async {
      await forAllAsync<int>(
        _seedGen(),
        count: 2 * fuzzScale(),
        describe: 'recovery-fixpoint settings',
        check: (seed) async {
          final rng = Rng(seed);
          final s1 = _genSettings(rng, 's1');
          final s2 = _genSettings(rng, 's2');
          final allowed = <String>{
            _settingsSig(s1),
            _settingsSig(s2),
            _settingsSig(AppSettingsSnapshot.defaults()),
          };
          await _lawRFixpoint(
            label: 'settings',
            persistS1: () => SettingsStore.persist(s1),
            persistS2: () => SettingsStore.persist(s2),
            invalidate: SettingsStore.invalidateCache,
            loadSig: () async => _settingsSig(await SettingsStore.load()),
            allowed: allowed,
          );
        },
      );
    });

    test(
        'AiSettingsStore recovery is atomic (does not rewrite a torn file) and '
        'reaches a value fixpoint', () async {
      await forAllAsync<int>(
        _seedGen(),
        count: 2 * fuzzScale(),
        describe: 'recovery-fixpoint ai-settings',
        check: (seed) async {
          final rng = Rng(seed);
          final s1 = _genAiSettings(rng, 's1');
          final s2 = _genAiSettings(rng, 's2');
          final allowed = <String>{
            _aiSettingsSig(s1),
            _aiSettingsSig(s2),
            _aiSettingsSig(AiSettingsSnapshot.defaults()),
          };
          await _lawRFixpoint(
            label: 'ai-settings',
            persistS1: () => AiSettingsStore.persist(s1),
            persistS2: () => AiSettingsStore.persist(s2),
            invalidate: () {},
            loadSig: () async => _aiSettingsSig(await AiSettingsStore.load()),
            allowed: allowed,
          );
        },
      );
    });
  });

  // ── UPGRADE 3 — additional store surfaces ─────────────────────────────
  group('upgrade 3: additional store surfaces', () {
    test(
        'SpectralBasisCache torn write + power loss degrade to null, never '
        'throw (confirmed-safe)', () async {
      await forAllAsync<int>(
        _seedGen(),
        count: _cases(),
        describe: 'spectral-basis-cache torn',
        check: (seed) async {
          final rng = Rng(seed);
          final basis = _genBasis(rng);
          final sig = basis.signature;
          final expectedBytes = basis.toBytes();

          final journalDir = _dir('sbc-journal');
          await clearDir(journalDir);
          final base = await snapshotDir(journalDir); // empty pre-state
          final journal = await journalWrites(journalDir, () async {
            await SpectralBasisCache(directory: journalDir).write(basis);
          });
          expect(journal.ops, isNotEmpty,
              reason: 'write produced no journalled effect');

          final replayDir = _dir('sbc-replay');

          Future<void> assertDegrades(String tag) async {
            final cache = SpectralBasisCache(directory: replayDir);
            final rAsync = await cache.read(sig); // must not throw
            final rSync = cache.readSync(sig); // must not throw
            if (rAsync != null) {
              expect(rAsync.signature, sig, reason: '$tag: async wrong sig');
            }
            if (rSync != null) {
              expect(rSync.signature, sig, reason: '$tag: sync wrong sig');
            }
          }

          for (final pt in enumerateCrashPoints(journal)) {
            await replayCrash(journal, base, replayDir, pt);
            await assertDegrades('crash $pt');
          }
          final plPoints = enumeratePowerLossPoints(journal);
          expect(plPoints, isNotEmpty,
              reason: 'flush:false write must expose a power-loss surface');
          for (final pt in plPoints) {
            await replayPowerLoss(journal, base, replayDir, pt);
            await assertDegrades('powerloss $pt');
          }
          await replayFull(journal, base, replayDir);
          final full = await SpectralBasisCache(directory: replayDir).read(sig);
          expect(full, isNotNull, reason: 'full replay must read the basis');
          expect(full!.signature, sig);
          expect(full.toBytes(), expectedBytes,
              reason: 'round-trip bytes differ from the source basis');
        },
      );
    });

    test(
        'AiSettingsStore torn prompt write never throws + never touches '
        'ai_settings.json (blast radius, confirmed-safe)', () async {
      await forAllAsync<int>(
        _seedGen(),
        count: _cases(),
        describe: 'ai-prompt blast radius',
        check: (seed) async {
          final rng = Rng(seed);
          final aiSnap = _genAiSettings(rng, 's');
          final prompt = 'You are ${_gStr(maxLen: 30)(rng)}\n\nRole: reviewer.';
          const settingsKey = 'ai/ai_settings.json';

          final journalDir = _dir('prompt-journal');
          await clearDir(journalDir);
          StoragePaths.debugOverrideDir = journalDir;
          await AiSettingsStore.persist(aiSnap);
          final base = await snapshotDir(journalDir);
          expect(base.containsKey(settingsKey), isTrue,
              reason: 'ai_settings.json was not established');

          final journal = await journalWrites(journalDir, () async {
            await AiSettingsStore.persistCommitMessagePrompt(prompt);
          });
          expect(journal.ops, isNotEmpty);

          final replayDir = _dir('prompt-replay');
          for (final pt in enumerateCrashPoints(journal)) {
            await replayCrash(journal, base, replayDir, pt);
            StoragePaths.debugOverrideDir = replayDir;
            // Loader is total: '' or a string prefix, never a throw.
            final loaded = await AiSettingsStore.loadCommitMessagePrompt();
            expect(loaded, isA<String>());
            final after = await snapshotDir(replayDir);
            expect(after.containsKey(settingsKey), isTrue,
                reason: '$pt: ai_settings.json vanished from a prompt write');
            expect(_bytesEqual(after[settingsKey]!, base[settingsKey]!), isTrue,
                reason: '$pt: ai_settings.json mutated by a prompt write');
          }
        },
      );
    });

    // Breadcrumb: was an unreachable/unobservable smell (per-repo usage maps
    // committed field-by-field into the LIVE maps, so a wrong-typed later field
    // left a franken half-load). Fixed + made testable 2026-07-10 — the parse
    // is now the pure, all-or-nothing @visibleForTesting parsePaletteUsage, and
    // _loadUsageSync stages into locals and commits together only on success.
    test(
        'PaletteState usage parse is all-or-nothing (throws on any malformed '
        'field, never a partial/franken commit)', () {
      // A wrong-typed LATER field: the same repo's frequency map parses fine,
      // then recency holds a non-date value. The pure parse must throw BEFORE
      // returning, so the caller commits nothing (degrades to empty) rather
      // than keeping the already-built frequency map — the franken state is
      // unrepresentable.
      final franken = <String, dynamic>{
        'repos': {
          'repoA': {
            'frequency': {'cmd.open': 3, 'cmd.close': 5}, // valid
            'recency': {'cmd.open': 42}, // NOT a parseable date string
            'queryFrequency': <String, dynamic>{},
            'transitions': <String, dynamic>{},
          }
        },
        'lastExecutedId': 'cmd.open',
      };
      expect(() => parsePaletteUsage(franken), throwsA(anything),
          reason: 'a malformed later field must throw so the caller commits '
              'nothing — no partial (franken) load');

      // A fully-valid payload yields a complete parse: all four maps populated
      // plus lastExecutedId.
      final valid = <String, dynamic>{
        'repos': {
          'repoA': {
            'frequency': {'cmd.open': 3, 'cmd.close': 5},
            'recency': {'cmd.open': '2026-01-02T03:04:05.000Z'},
            'queryFrequency': {
              'op': {'cmd.open': 2}
            },
            'transitions': {
              'cmd.open': {'cmd.close': 4}
            },
          }
        },
        'lastExecutedId': 'cmd.close',
      };
      final parsed = parsePaletteUsage(valid);
      expect(parsed.frequency['repoA'], {'cmd.open': 3, 'cmd.close': 5});
      expect(parsed.recency['repoA']!['cmd.open'],
          DateTime.parse('2026-01-02T03:04:05.000Z'));
      expect(parsed.queryFrequency['repoA'], {
        'op': {'cmd.open': 2}
      });
      expect(parsed.transitions['repoA'], {
        'cmd.open': {'cmd.close': 4}
      });
      expect(parsed.lastExecutedId, 'cmd.close');
    });

    test('AI model disk cache torn write (unreachable without lib seam)', () {},
        skip: _aiModelCacheUnreachableSkip);
  });
}

// ── helpers ────────────────────────────────────────────────────────────────

/// The file NudgeLedger(repoPath, storageDirOverride: [storageDir]) appends to.
/// Recomputes the store's FNV-1a(repoPath) key so a torn tail lands on the
/// exact file the ledger will later open.
File _nudgeFile(Directory storageDir) {
  var hash = 0x811c9dc5;
  for (final c in _kRepo.codeUnits) {
    hash ^= c;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final key = hash.toRadixString(16).padLeft(8, '0');
  return File(p.join(storageDir.path, '$key.jsonl'));
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _snapEquals(Map<String, List<int>> a, Map<String, List<int>> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    final bv = b[key];
    if (bv == null || !_bytesEqual(a[key]!, bv)) return false;
  }
  return true;
}
