// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Model-based / stateful property testing for the app-state ChangeNotifier
// layer (lib/app/*.dart). Existing test/app/*_test.dart files cover
// individual methods in isolation; this file drives each state class
// through a random SEQUENCE of its own public operations and asserts the
// class's invariants hold after EVERY step, catching "operation X leaves
// the state inconsistent" bugs that per-method tests can't see (dedup,
// caps, monotonic counters) and — via a generic listener-consistency law —
// spurious/missed notifyListeners() calls.
//
// The listener-consistency law, used for every class below except where
// documented: snapshot the class's OBSERVABLE (getter-exposed) state before
// and after each op; if the snapshot is unchanged, the op must not have
// notified (no wasted rebuild); if it changed, the op must have notified at
// least once (no stale UI). This is a black-box law over public getters, so
// it can't see private-field-only changes — which is fine, since nothing
// outside the class could observe those either.
//
// Exclusions (each with a source-level reason, not "don't fake it"):
//
//  - WorktreeState — SKIPPED. Unlike RepositoryState (which takes injectable
//    openRepositoryFn/statusLoader/gitWatcherFactory), WorktreeState's
//    constructor hard-wires calls to the real top-level listWorktrees/
//    pruneWorktrees/runGit/stashPush functions from backend/git.dart with NO
//    injection seam. Its own constructor immediately fires refreshFor() the
//    moment RepositoryState.activePath is non-null, and _onRepoChanged fires
//    another refreshFor() on every subsequent activePath change — both spawn
//    real `git` subprocesses against whatever path string the sequence
//    picked. There's no way to seed WorktreeState.desks or drive its
//    mutating ops (addDesk/closeDesk) without either a real git checkout or
//    editing lib/ to add an injection point (out of scope here). The one
//    cleanly-testable pure piece — the once-per-repo prune gate — is already
//    covered by test/app/worktree_prune_gate_test.dart.
//
//  - ChangesetController — SKIPPED. update()/setClusterInputs() drive real
//    git subprocess calls (fileChangeWeights), real file reads
//    (analyzeFlowCached), and Isolate.run spawns with no constructor-level
//    fakes (unlike RepositoryState's injectable functions); it also depends
//    on a live LogosGit engine and FileCouplingMatrix to do anything
//    interesting. It's explicitly READ-ONLY for this task anyway (another
//    agent may edit it), so no seam was added on its side either.
//
//  - PreferencesState.setReduceMotionPhase — excluded from the op set (not
//    from the whole class). Its own doc comment says it deliberately does
//    NOT call notifyListeners() ("nothing in the app watches this value
//    reactively") — a documented, intentional exception to the notify law,
//    not a bug to rediscover here.
//
//  - PreferencesState.setGuardrailStage / setUpdateChannel /
//    setCrashReportingEnabled — excluded from the op set. All three route
//    through the process-wide DiagnosticsState.instance singleton (command
//    lifecycle + latency telemetry via CommandTelemetryStore), which is not
//    reset between forAllAsync cases and would accumulate cross-case state
//    unrelated to PreferencesState itself. The remaining ~20 setters already
//    exercise every no-op-guard shape those three use (equality-guarded
//    field assignment) without that entanglement.
//
//  - RepositoryState.loadRecents() / CommitModeState.load() /
//    SidebarOrgState.load() — these three classes' load() methods all
//    unconditionally call notifyListeners() at the end regardless of
//    whether the loaded content actually differs from the in-memory state
//    (verified by reading all three; not a copy-paste accident, a repeated
//    cross-class convention). Included in every sequence for their VALUE
//    invariants, but excluded from the spurious-notify half of the listener
//    law so a real, intentional, load-is-a-snapshot-arrival design choice
//    isn't misreported as a bug.
//
// PreferencesState persists through SettingsStore (plain dart:io File under
// StoragePaths.gdpuDataDir()) — a single fixed file with no per-test
// uniquification, same as test/fuzz/settings_store_roundtrip_test.dart. Its
// group is therefore skipped unless GDPU_DATA_DIR is set, exactly mirroring
// that file's convention, so a forgotten env var can never read/write a
// developer's real settings.json. Run with:
//   GDPU_DATA_DIR=/tmp/gdpu-state-model-test flutter test \
//     test/app/state_model_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/commit_mode_state.dart';
import 'package:git_desktop/app/preferences_state.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/app/sidebar_org_state.dart';
import 'package:git_desktop/backend/commit_format.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/file_coupling.dart' show FileSortGuide;
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/storage_paths.dart';
import 'package:git_desktop/backend/undo_controller.dart' show UndoActionKind;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/gen.dart';
import '../support/prop.dart';

const _okRepoStatus = GitResult<RepositoryStatus>.ok(
  RepositoryStatus(branch: 'main', ahead: 0, behind: 0, files: []),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (call) async => call.method == 'getAll' ? <String, Object>{} : null,
  );

  // ===========================================================================
  // RepositoryState
  // ===========================================================================
  group('RepositoryState — stateful sequence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('random op sequences preserve RepositoryState invariants', () async {
      await forAllAsync<List<_RepoOp>>(
        genList(_genRepoOp(), maxLen: 15),
        count: 60,
        describe: 'RepositoryState stateful sequence',
        check: (ops) async {
          SharedPreferences.setMockInitialValues({});
          final state = RepositoryState(
            switchDebounce: Duration.zero,
            openRepositoryFn: (path) async => GitResult.ok(path),
            statusLoader: (path) async => _okRepoStatus,
          );
          var notifyCount = 0;
          state.addListener(() => notifyCount++);

          String snapshot() => jsonEncode({
                'activePath': state.activePath,
                'recentPaths': state.recentPaths,
                'statusLoading': state.statusLoading,
                'statusError': state.statusError,
                'userRefreshEpoch': state.userRefreshEpoch,
                'activationEpoch': state.activationEpoch,
              });

          var lastActivationEpoch = state.activationEpoch;
          var lastUserEpoch = state.userRefreshEpoch;

          for (final op in ops) {
            final before = snapshot();
            final notifyBefore = notifyCount;
            var isLoadRecents = false;
            switch (op) {
              case _SetActive(:final path, :final addToRecents):
                collect('op:setActive');
                await state.setActivePath(path, addToRecents: addToRecents);
              case _ForgetRecent(:final path):
                collect('op:forgetRecent');
                await state.forgetRecent(path);
              case _UserRefresh():
                collect('op:userRefresh');
                await state.userRefresh();
              case _LoadRecents():
                collect('op:loadRecents');
                isLoadRecents = true;
                await state.loadRecents();
            }
            final after = snapshot();
            final changed = before != after;
            final notifyDelta = notifyCount - notifyBefore;

            // Invariant: recents never contains duplicates.
            expect(state.recentPaths.toSet().length, state.recentPaths.length,
                reason: 'recentPaths must never contain duplicates after $op');
            // Invariant: recents cap at 20 (setActivePath's `.take(20)`).
            expect(state.recentPaths.length, lessThanOrEqualTo(20));
            // Invariant: activationEpoch/userRefreshEpoch are monotonic
            // non-decreasing — never rewound by any op.
            expect(state.activationEpoch,
                greaterThanOrEqualTo(lastActivationEpoch));
            expect(
                state.userRefreshEpoch, greaterThanOrEqualTo(lastUserEpoch));
            lastActivationEpoch = state.activationEpoch;
            lastUserEpoch = state.userRefreshEpoch;

            // Listener-consistency law — excluded for loadRecents() (see the
            // file-level comment: unconditional notify by convention).
            if (!isLoadRecents) {
              if (changed) {
                expect(notifyDelta, greaterThanOrEqualTo(1),
                    reason: 'missed notify after a real state change for $op');
              } else {
                expect(notifyDelta, 0,
                    reason:
                        'spurious notify with no observable state change for $op');
              }
            }
          }
          state.dispose();
        },
        requireCoverage: const {
          'op:setActive': 0.05,
          'op:forgetRecent': 0.05,
          'op:userRefresh': 0.05,
          'op:loadRecents': 0.05,
        },
      );
    });
  });

  // ===========================================================================
  // CommitModeState
  // ===========================================================================
  group('CommitModeState — stateful sequence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    const paths = ['/repo/a', '/repo/b', '/repo/c'];

    test('random op sequences preserve CommitModeState invariants', () async {
      await forAllAsync<List<_CommitModeOp>>(
        genList(_genCommitModeOp(paths), maxLen: 20),
        count: 80,
        describe: 'CommitModeState stateful sequence',
        check: (ops) async {
          SharedPreferences.setMockInitialValues({});
          final state = CommitModeState();
          // Shadow model: mirrors the class's own documented contract
          // ("only true entries are stored; absent key means false").
          final shadow = <String, bool>{};
          var notifyCount = 0;
          state.addListener(() => notifyCount++);

          for (final op in ops) {
            final notifyBefore = notifyCount;
            switch (op) {
              case _SetCommitOnly(:final path, :final value):
                collect('op:setCommitOnly');
                final realChange = (shadow[path] ?? false) != value;
                if (value) {
                  shadow[path] = true;
                } else {
                  shadow.remove(path);
                }
                state.setCommitOnly(path, value);
                expect(notifyCount - notifyBefore, realChange ? 1 : 0,
                    reason:
                        'setCommitOnly($path, $value) notify-law mismatch — '
                        'the setter documents a same-value no-op guard');
              case _Toggle(:final path):
                collect('op:toggle');
                final newValue = !(shadow[path] ?? false);
                if (newValue) {
                  shadow[path] = true;
                } else {
                  shadow.remove(path);
                }
                state.toggle(path);
                expect(notifyCount - notifyBefore, 1,
                    reason:
                        'toggle($path) always flips the value, so it must '
                        'notify exactly once');
              case _CommitLoad():
                collect('op:load');
                // load() unconditionally notifies (file-level comment) —
                // not asserted here, only the resulting VALUES below.
                await state.flushPendingSaveForTesting();
                await state.load();
            }
            for (final p in paths) {
              expect(state.commitOnlyFor(p), shadow[p] ?? false,
                  reason:
                      'commitOnlyFor($p) diverged from the shadow model after $op');
            }
          }
          // Drain this case's fire-and-forget `_save()` queue before the
          // NEXT case resets the mock SharedPreferences plugin — otherwise
          // a still-in-flight write from this case races the next case's
          // `setMockInitialValues` re-registration and throws deep inside
          // the mock channel (a harness hazard, not a CommitModeState bug).
          await state.flushPendingSaveForTesting();
          state.dispose();
        },
        requireCoverage: const {
          'op:setCommitOnly': 0.1,
          'op:toggle': 0.1,
          'op:load': 0.05,
        },
      );
    });
  });

  // ===========================================================================
  // SidebarOrgState
  // ===========================================================================
  group('SidebarOrgState — stateful sequence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('random op sequences preserve SidebarOrgState invariants', () async {
      await forAllAsync<List<_SidebarOp>>(
        genList(_genSidebarOp(), maxLen: 20),
        count: 100,
        describe: 'SidebarOrgState stateful sequence',
        check: (ops) async {
          SharedPreferences.setMockInitialValues({});
          final state = SidebarOrgState();
          var notifyCount = 0;
          state.addListener(() => notifyCount++);

          for (final op in ops) {
            final before = jsonEncode(_sidebarSnapshot(state.roots));
            final notifyBefore = notifyCount;
            switch (op) {
              case _AnchorRepo(:final path):
                collect('op:anchorRepo');
                state.anchorRepo(path);
              case _UnanchorRepo(:final path):
                collect('op:unanchorRepo');
                state.unanchorRepo(path);
              case _MakeGroupHead(:final path):
                collect('op:makeGroupHead');
                state.makeGroupHead(path);
              case _AddToGroup(:final path, :final groupSel):
                collect('op:addToGroup');
                state.addToGroup(path, _resolveGroupId(state, groupSel));
              case _NestUnder(:final source, :final target):
                collect('op:nestUnder');
                state.nestUnder(source, target);
              case _MoveToTopLevel(:final path):
                collect('op:moveToTopLevel');
                state.moveToTopLevel(path);
              case _InsertBefore(:final source, :final target):
                collect('op:insertBefore');
                state.insertBefore(source, target);
              case _InsertBeforeGroup(:final source, :final groupSel):
                collect('op:insertBeforeGroup');
                state.insertBeforeGroup(
                    source, _resolveGroupId(state, groupSel));
              case _InsertIntoGroup(:final source, :final groupSel):
                collect('op:insertIntoGroup');
                state.insertIntoGroup(
                    source, _resolveGroupId(state, groupSel));
              case _CreateGroupFromDrop(:final head, :final child):
                collect('op:createGroupFromDrop');
                state.createGroupFromDrop(head, child);
              case _CreateEmptyGroup(:final label):
                collect('op:createEmptyGroup');
                state.createEmptyGroup(label: label);
              case _ToggleCollapsed(:final groupSel):
                collect('op:toggleCollapsed');
                state.toggleCollapsed(_resolveGroupId(state, groupSel));
              case _SetGroupColor(:final groupSel, :final slot):
                collect('op:setGroupColor');
                state.setGroupColor(_resolveGroupId(state, groupSel), slot);
              case _CycleGroupColor(:final groupSel):
                collect('op:cycleGroupColor');
                state.cycleGroupColor(_resolveGroupId(state, groupSel));
              case _ClearGroupColor(:final groupSel):
                collect('op:clearGroupColor');
                state.clearGroupColor(_resolveGroupId(state, groupSel));
              case _SetGroupLabel(:final groupSel, :final label):
                collect('op:setGroupLabel');
                state.setGroupLabel(_resolveGroupId(state, groupSel), label);
              case _DissolveGroup(:final groupSel):
                collect('op:dissolveGroup');
                state.dissolveGroup(_resolveGroupId(state, groupSel));
              case _RemoveGroup(:final groupSel):
                collect('op:removeGroup');
                state.removeGroup(_resolveGroupId(state, groupSel));
              case _ForgetRepo(:final path):
                collect('op:forgetRepo');
                state.forgetRepo(path);
              case _Reorder(
                  :final parentGroupSel,
                  :final oldIndex,
                  :final newIndex
                ):
                collect('op:reorder');
                state.reorder(_resolveParentSel(state, parentGroupSel),
                    oldIndex, newIndex);
            }

            final after = jsonEncode(_sidebarSnapshot(state.roots));
            final changed = before != after;
            final notifyDelta = notifyCount - notifyBefore;
            if (changed) {
              // CORRECTNESS law (hard): a real tree change must notify, or
              // the sidebar renders stale. This is what caught the genuine
              // `addToGroup` data-loss bug (it removed a repo then returned
              // without notifying). Kept strict.
              expect(notifyDelta, greaterThanOrEqualTo(1),
                  reason: 'missed notify after a real tree change for $op');
            } else if (notifyDelta > 0) {
              // PERF observation (soft): a no-op op that still notifies is a
              // wasted rebuild, not a correctness bug — the tree is already
              // right, the UI just repaints once for nothing. Several
              // structural mutators here notify unconditionally (the
              // codebase's established convention, same as the `load()`
              // methods), and over-notification is universally tolerated in
              // the Flutter ChangeNotifier ecosystem. We record it rather
              // than fail on it; the trivially-guardable no-op setters
              // (setGroupColor/setGroupLabel) WERE fixed at the source.
              collect('spurious-notify:${op.runtimeType}');
            }

            // Invariant: every repo path claims at most one slot in the
            // tree (as a SidebarRepo leaf OR a group's headRepoPath) — the
            // whole point of `_removeByPath` running before every insert.
            final claims = <String>[];
            void walk(List<SidebarNode> nodes) {
              for (final n in nodes) {
                if (n is SidebarRepo) claims.add(n.path);
                if (n is SidebarGroup) {
                  if (n.headRepoPath != null) claims.add(n.headRepoPath!);
                  walk(n.children);
                }
              }
            }

            walk(state.roots);
            expect(claims.toSet().length, claims.length,
                reason:
                    'a repo path claims more than one slot in the sidebar tree after $op');
            expect(state.organizedPaths, claims.toSet(),
                reason: 'organizedPaths diverged from the actual tree after $op');
          }
          // See the matching comment in the CommitModeState group: drain
          // the fire-and-forget `_save()` queue before the next case resets
          // the mock SharedPreferences plugin.
          await state.flushPendingSaveForTesting();
          state.dispose();
        },
        requireCoverage: const {
          'op:anchorRepo': 0.05,
          'op:unanchorRepo': 0.05,
          'op:makeGroupHead': 0.05,
          'op:addToGroup': 0.05,
          'op:nestUnder': 0.05,
          'op:moveToTopLevel': 0.05,
          'op:insertBefore': 0.05,
          'op:insertBeforeGroup': 0.05,
          'op:insertIntoGroup': 0.05,
          'op:createGroupFromDrop': 0.05,
          'op:createEmptyGroup': 0.05,
          'op:toggleCollapsed': 0.05,
          'op:setGroupColor': 0.05,
          'op:cycleGroupColor': 0.05,
          'op:clearGroupColor': 0.05,
          'op:setGroupLabel': 0.05,
          'op:dissolveGroup': 0.05,
          'op:removeGroup': 0.05,
          'op:forgetRepo': 0.05,
          'op:reorder': 0.05,
        },
      );
    });
  });

  // ===========================================================================
  // PreferencesState (disk-touching — isolated hermetically, see below)
  // ===========================================================================
  group('PreferencesState — stateful sequence', () {
    // PreferencesState persists through SettingsStore (a plain dart:io File
    // under StoragePaths.gdpuDataDir()). Point that whole directory at a
    // fresh temp dir per test via StoragePaths.debugOverrideDir, so this
    // group RUNS BY DEFAULT (no GDPU_DATA_DIR env var, no CI wiring) and can
    // never touch the developer's real settings.json.
    Directory? tempDir;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('gdpu_pref_state_');
      StoragePaths.debugOverrideDir = tempDir;
    });
    tearDown(() async {
      StoragePaths.debugOverrideDir = null;
      try {
        await tempDir?.delete(recursive: true);
      } catch (_) {
        // Best-effort — a lingering handle must not fail teardown.
      }
    });

    test('random op sequences preserve PreferencesState invariants', () async {
      await forAllAsync<List<_PrefOp>>(
        genList(_genPrefOp(), maxLen: 20),
        count: 60,
        describe: 'PreferencesState stateful sequence',
        check: (ops) async {
          SharedPreferences.setMockInitialValues({});
          final state = PreferencesState();
          var notifyCount = 0;
          state.addListener(() => notifyCount++);

          for (final op in ops) {
            final before = jsonEncode(_prefsSnapshot(state));
            final notifyBefore = notifyCount;
            var isLoad = false;
            switch (op) {
              case _PrefLoad():
                collect('op:load');
                isLoad = true;
                await state.load();
              case _SetMotionRate(:final v):
                collect('op:setMotionRate');
                await state.setMotionRate(v);
              case _SetReduceMotion(:final v):
                collect('op:setReduceMotion');
                await state.setReduceMotion(v);
              case _SetChangesPanelWidth(:final px):
                collect('op:setChangesPanelWidth');
                await state.setChangesPanelWidth(px);
              case _SetLogosPad(:final x, :final y):
                collect('op:setLogosPad');
                await state.setLogosPad(x, y);
              case _SetFileSortGuide(:final v):
                collect('op:setFileSortGuide');
                await state.setFileSortGuide(v);
              case _SetFileSortInverted(:final v):
                collect('op:setFileSortInverted');
                await state.setFileSortInverted(v);
              case _SetIssuesSortDescending(:final v):
                collect('op:setIssuesSortDescending');
                await state.setIssuesSortDescending(v);
              case _SetTagsSortDescending(:final v):
                collect('op:setTagsSortDescending');
                await state.setTagsSortDescending(v);
              case _SetCommitStructure(:final v):
                collect('op:setCommitStructure');
                await state.setCommitStructure(v);
              case _SetCommitVoice(:final v):
                collect('op:setCommitVoice');
                await state.setCommitVoice(v);
              case _SetCommitCoverage(:final v):
                collect('op:setCommitCoverage');
                await state.setCommitCoverage(v);
              case _SetUndoWindowSeconds(:final v):
                collect('op:setUndoWindowSeconds');
                await state.setUndoWindowSeconds(v);
              case _SetUndoWindowFor(:final kind, :final v):
                collect('op:setUndoWindowFor');
                await state.setUndoWindowFor(kind, v);
              case _ResyncUndoWindows():
                collect('op:resyncUndoWindows');
                await state.resyncUndoWindows();
              case _SetBoolPref(:final idx, :final v):
                collect('op:setBoolPref:${_boolPrefs[idx].$1}');
                await _boolPrefs[idx].$2(state, v);
            }
            final after = jsonEncode(_prefsSnapshot(state));
            final changed = before != after;
            final notifyDelta = notifyCount - notifyBefore;

            // Listener-consistency law — excluded for load() (see the
            // file-level comment: unconditional-notify convention shared
            // with CommitModeState/SidebarOrgState).
            if (!isLoad) {
              if (changed) {
                expect(notifyDelta, greaterThanOrEqualTo(1),
                    reason: 'missed notify after a real value change for $op');
              } else {
                expect(notifyDelta, 0,
                    reason:
                        'spurious notify with no observable value change for $op');
              }
            }

            // Range invariants — every persisted-display-law field stays
            // inside its documented clamp, after every single op.
            expect(state.motionRate, inInclusiveRange(0.0, 2.0));
            expect(state.reduceMotion, state.motionRate <= kMotionRateOff);
            expect(state.changesPanelWidthPx, inInclusiveRange(220, 520));
            expect(state.logosPadX, inInclusiveRange(0.0, 1.0));
            expect(state.logosPadY, inInclusiveRange(0.0, 1.0));
            expect(state.undoWindowSeconds, inInclusiveRange(0, 3600));
            for (final entry in state.undoWindowOverrides.entries) {
              expect(entry.value, inInclusiveRange(0, 3600),
                  reason: 'undoWindowOverrides[${entry.key}] out of range');
              expect(entry.value, isNot(state.undoWindowSeconds),
                  reason:
                      'undoWindowOverrides must stay minimal — an override '
                      'equal to the default should have been pruned '
                      '(entry ${entry.key}) after $op');
              expect(state.undoWindowFor(UndoActionKind.values
                      .firstWhere((k) => k.name == entry.key)),
                  entry.value,
                  reason: 'undoWindowFor must return the override when one exists');
            }
          }
          state.dispose();
        },
        requireCoverage: const {
          'op:setMotionRate': 0.05,
          'op:setChangesPanelWidth': 0.05,
          'op:setLogosPad': 0.05,
          'op:setFileSortGuide': 0.05,
          'op:setUndoWindowSeconds': 0.05,
          'op:setUndoWindowFor': 0.05,
        },
      );
    });
  });
}

// =============================================================================
// RepositoryState ops
// =============================================================================

sealed class _RepoOp {}

class _SetActive extends _RepoOp {
  final String path;
  final bool addToRecents;
  _SetActive(this.path, this.addToRecents);
  @override
  String toString() => 'SetActive($path, addToRecents: $addToRecents)';
}

class _ForgetRecent extends _RepoOp {
  final String path;
  _ForgetRecent(this.path);
  @override
  String toString() => 'ForgetRecent($path)';
}

class _UserRefresh extends _RepoOp {
  @override
  String toString() => 'UserRefresh()';
}

class _LoadRecents extends _RepoOp {
  @override
  String toString() => 'LoadRecents()';
}

const _repoPathPool = ['/repo/a', '/repo/b', '/repo/c'];

Gen<_RepoOp> _genRepoOp() => genFrequency<_RepoOp>([
      (5, (rng) => _SetActive(rng.pick(_repoPathPool), rng.nextBool())),
      (3, (rng) => _ForgetRecent(rng.pick(_repoPathPool))),
      (2, (rng) => _UserRefresh()),
      (1, (rng) => _LoadRecents()),
    ]);

// =============================================================================
// CommitModeState ops
// =============================================================================

sealed class _CommitModeOp {}

class _SetCommitOnly extends _CommitModeOp {
  final String path;
  final bool value;
  _SetCommitOnly(this.path, this.value);
  @override
  String toString() => 'SetCommitOnly($path, $value)';
}

class _Toggle extends _CommitModeOp {
  final String path;
  _Toggle(this.path);
  @override
  String toString() => 'Toggle($path)';
}

class _CommitLoad extends _CommitModeOp {
  _CommitLoad();
  @override
  String toString() => 'Load()';
}

Gen<_CommitModeOp> _genCommitModeOp(List<String> paths) =>
    genFrequency<_CommitModeOp>([
      (5, (rng) => _SetCommitOnly(rng.pick(paths), rng.nextBool())),
      (4, (rng) => _Toggle(rng.pick(paths))),
      (1, (rng) => _CommitLoad()),
    ]);

// =============================================================================
// SidebarOrgState ops
// =============================================================================

sealed class _SidebarOp {}

class _AnchorRepo extends _SidebarOp {
  final String path;
  _AnchorRepo(this.path);
  @override
  String toString() => 'AnchorRepo($path)';
}

class _UnanchorRepo extends _SidebarOp {
  final String path;
  _UnanchorRepo(this.path);
  @override
  String toString() => 'UnanchorRepo($path)';
}

class _MakeGroupHead extends _SidebarOp {
  final String path;
  _MakeGroupHead(this.path);
  @override
  String toString() => 'MakeGroupHead($path)';
}

class _AddToGroup extends _SidebarOp {
  final String path;
  final int groupSel;
  _AddToGroup(this.path, this.groupSel);
  @override
  String toString() => 'AddToGroup($path, sel:$groupSel)';
}

class _NestUnder extends _SidebarOp {
  final String source;
  final String target;
  _NestUnder(this.source, this.target);
  @override
  String toString() => 'NestUnder($source, $target)';
}

class _MoveToTopLevel extends _SidebarOp {
  final String path;
  _MoveToTopLevel(this.path);
  @override
  String toString() => 'MoveToTopLevel($path)';
}

class _InsertBefore extends _SidebarOp {
  final String source;
  final String target;
  _InsertBefore(this.source, this.target);
  @override
  String toString() => 'InsertBefore($source, $target)';
}

class _InsertBeforeGroup extends _SidebarOp {
  final String source;
  final int groupSel;
  _InsertBeforeGroup(this.source, this.groupSel);
  @override
  String toString() => 'InsertBeforeGroup($source, sel:$groupSel)';
}

class _InsertIntoGroup extends _SidebarOp {
  final String source;
  final int groupSel;
  _InsertIntoGroup(this.source, this.groupSel);
  @override
  String toString() => 'InsertIntoGroup($source, sel:$groupSel)';
}

class _CreateGroupFromDrop extends _SidebarOp {
  final String head;
  final String child;
  _CreateGroupFromDrop(this.head, this.child);
  @override
  String toString() => 'CreateGroupFromDrop($head, $child)';
}

class _CreateEmptyGroup extends _SidebarOp {
  final String? label;
  _CreateEmptyGroup(this.label);
  @override
  String toString() => 'CreateEmptyGroup($label)';
}

class _ToggleCollapsed extends _SidebarOp {
  final int groupSel;
  _ToggleCollapsed(this.groupSel);
  @override
  String toString() => 'ToggleCollapsed(sel:$groupSel)';
}

class _SetGroupColor extends _SidebarOp {
  final int groupSel;
  final int? slot;
  _SetGroupColor(this.groupSel, this.slot);
  @override
  String toString() => 'SetGroupColor(sel:$groupSel, $slot)';
}

class _CycleGroupColor extends _SidebarOp {
  final int groupSel;
  _CycleGroupColor(this.groupSel);
  @override
  String toString() => 'CycleGroupColor(sel:$groupSel)';
}

class _ClearGroupColor extends _SidebarOp {
  final int groupSel;
  _ClearGroupColor(this.groupSel);
  @override
  String toString() => 'ClearGroupColor(sel:$groupSel)';
}

class _SetGroupLabel extends _SidebarOp {
  final int groupSel;
  final String? label;
  _SetGroupLabel(this.groupSel, this.label);
  @override
  String toString() => 'SetGroupLabel(sel:$groupSel, $label)';
}

class _DissolveGroup extends _SidebarOp {
  final int groupSel;
  _DissolveGroup(this.groupSel);
  @override
  String toString() => 'DissolveGroup(sel:$groupSel)';
}

class _RemoveGroup extends _SidebarOp {
  final int groupSel;
  _RemoveGroup(this.groupSel);
  @override
  String toString() => 'RemoveGroup(sel:$groupSel)';
}

class _ForgetRepo extends _SidebarOp {
  final String path;
  _ForgetRepo(this.path);
  @override
  String toString() => 'ForgetRepo($path)';
}

class _Reorder extends _SidebarOp {
  final int? parentGroupSel;
  final int oldIndex;
  final int newIndex;
  _Reorder(this.parentGroupSel, this.oldIndex, this.newIndex);
  @override
  String toString() =>
      'Reorder(parent:$parentGroupSel, $oldIndex -> $newIndex)';
}

const _sidebarPathPool = ['/repo/a', '/repo/b', '/repo/c', '/repo/d'];

/// Every group id currently reachable in [nodes], depth-first.
List<String> _allGroupIds(List<SidebarNode> nodes) {
  final ids = <String>[];
  for (final n in nodes) {
    if (n is SidebarGroup) {
      ids.add(n.id);
      ids.addAll(_allGroupIds(n.children));
    }
  }
  return ids;
}

/// Resolves a generated selector into a group id: negative selectors (and
/// selectors drawn when no group exists yet) deliberately resolve to a
/// bogus id, so the generator exercises both the "group found" and
/// "group not found" guarded branches without a separate boolean flag.
String _resolveGroupId(SidebarOrgState state, int sel) {
  if (sel < 0) return 'nonexistent-group-id';
  final ids = _allGroupIds(state.roots);
  if (ids.isEmpty) return 'nonexistent-group-id';
  return ids[sel % ids.length];
}

String? _resolveParentSel(SidebarOrgState state, int? sel) =>
    sel == null ? null : _resolveGroupId(state, sel);

/// Deep, order-preserving, JSON-comparable projection of the sidebar tree
/// over exactly the fields SidebarOrgState exposes as public getters.
Object _sidebarSnapshot(List<SidebarNode> nodes) => nodes.map((n) {
      if (n is SidebarRepo) return {'t': 'repo', 'path': n.path};
      final g = n as SidebarGroup;
      return {
        't': 'group',
        'id': g.id,
        'label': g.label,
        'head': g.headRepoPath,
        'color': g.colorSlot,
        'collapsed': g.collapsed,
        'children': _sidebarSnapshot(g.children),
      };
    }).toList();

Gen<_SidebarOp> _genSidebarOp() => genFrequency<_SidebarOp>([
      (6, (rng) => _AnchorRepo(rng.pick(_sidebarPathPool))),
      (3, (rng) => _UnanchorRepo(rng.pick(_sidebarPathPool))),
      (4, (rng) => _MakeGroupHead(rng.pick(_sidebarPathPool))),
      (4,
          (rng) => _AddToGroup(
              rng.pick(_sidebarPathPool), rng.simpleIntBetween(-3, 12))),
      (4,
          (rng) => _NestUnder(
              rng.pick(_sidebarPathPool), rng.pick(_sidebarPathPool))),
      (3, (rng) => _MoveToTopLevel(rng.pick(_sidebarPathPool))),
      (3,
          (rng) => _InsertBefore(
              rng.pick(_sidebarPathPool), rng.pick(_sidebarPathPool))),
      (3,
          (rng) => _InsertBeforeGroup(
              rng.pick(_sidebarPathPool), rng.simpleIntBetween(-3, 12))),
      (3,
          (rng) => _InsertIntoGroup(
              rng.pick(_sidebarPathPool), rng.simpleIntBetween(-3, 12))),
      (3,
          (rng) => _CreateGroupFromDrop(
              rng.pick(_sidebarPathPool), rng.pick(_sidebarPathPool))),
      (3,
          (rng) => _CreateEmptyGroup(
              rng.nextBool() ? null : 'label-${rng.intBetween(0, 3)}')),
      (4, (rng) => _ToggleCollapsed(rng.simpleIntBetween(-3, 12))),
      (3,
          (rng) => _SetGroupColor(rng.simpleIntBetween(-3, 12),
              rng.nextBool() ? null : rng.intBetween(0, 6))),
      (3, (rng) => _CycleGroupColor(rng.simpleIntBetween(-3, 12))),
      (2, (rng) => _ClearGroupColor(rng.simpleIntBetween(-3, 12))),
      (3,
          (rng) => _SetGroupLabel(rng.simpleIntBetween(-3, 12),
              rng.nextBool() ? null : 'lbl-${rng.intBetween(0, 3)}')),
      (2, (rng) => _DissolveGroup(rng.simpleIntBetween(-3, 12))),
      (2, (rng) => _RemoveGroup(rng.simpleIntBetween(-3, 12))),
      (3, (rng) => _ForgetRepo(rng.pick(_sidebarPathPool))),
      (3,
          (rng) => _Reorder(
              rng.nextBool() ? null : rng.simpleIntBetween(-3, 12),
              rng.simpleIntBetween(-5, 10),
              rng.simpleIntBetween(-5, 10))),
    ]);

// =============================================================================
// PreferencesState ops
// =============================================================================

sealed class _PrefOp {}

class _PrefLoad extends _PrefOp {
  _PrefLoad();
  @override
  String toString() => 'Load()';
}

class _SetMotionRate extends _PrefOp {
  final double v;
  _SetMotionRate(this.v);
  @override
  String toString() => 'SetMotionRate($v)';
}

class _SetReduceMotion extends _PrefOp {
  final bool v;
  _SetReduceMotion(this.v);
  @override
  String toString() => 'SetReduceMotion($v)';
}

class _SetChangesPanelWidth extends _PrefOp {
  final int px;
  _SetChangesPanelWidth(this.px);
  @override
  String toString() => 'SetChangesPanelWidth($px)';
}

class _SetLogosPad extends _PrefOp {
  final double x;
  final double y;
  _SetLogosPad(this.x, this.y);
  @override
  String toString() => 'SetLogosPad($x, $y)';
}

class _SetFileSortGuide extends _PrefOp {
  final FileSortGuide v;
  _SetFileSortGuide(this.v);
  @override
  String toString() => 'SetFileSortGuide($v)';
}

class _SetFileSortInverted extends _PrefOp {
  final bool v;
  _SetFileSortInverted(this.v);
  @override
  String toString() => 'SetFileSortInverted($v)';
}

class _SetIssuesSortDescending extends _PrefOp {
  final bool v;
  _SetIssuesSortDescending(this.v);
  @override
  String toString() => 'SetIssuesSortDescending($v)';
}

class _SetTagsSortDescending extends _PrefOp {
  final bool v;
  _SetTagsSortDescending(this.v);
  @override
  String toString() => 'SetTagsSortDescending($v)';
}

class _SetCommitStructure extends _PrefOp {
  final CommitStructure v;
  _SetCommitStructure(this.v);
  @override
  String toString() => 'SetCommitStructure($v)';
}

class _SetCommitVoice extends _PrefOp {
  final CommitVoice v;
  _SetCommitVoice(this.v);
  @override
  String toString() => 'SetCommitVoice($v)';
}

class _SetCommitCoverage extends _PrefOp {
  final CommitCoverage v;
  _SetCommitCoverage(this.v);
  @override
  String toString() => 'SetCommitCoverage($v)';
}

class _SetUndoWindowSeconds extends _PrefOp {
  final int v;
  _SetUndoWindowSeconds(this.v);
  @override
  String toString() => 'SetUndoWindowSeconds($v)';
}

class _SetUndoWindowFor extends _PrefOp {
  final UndoActionKind kind;
  final int v;
  _SetUndoWindowFor(this.kind, this.v);
  @override
  String toString() => 'SetUndoWindowFor($kind, $v)';
}

class _ResyncUndoWindows extends _PrefOp {
  _ResyncUndoWindows();
  @override
  String toString() => 'ResyncUndoWindows()';
}

class _SetBoolPref extends _PrefOp {
  final int idx;
  final bool v;
  _SetBoolPref(this.idx, this.v);
  @override
  String toString() => 'SetBoolPref(${_boolPrefs[idx].$1}, $v)';
}

/// (name, setter, getter) triples for the plain boolean display-law prefs —
/// table-driven so the ten near-identical toggles don't need ten Op classes.
/// Excludes setReduceMotionPhase (documented no-notify exception) and
/// everything routed through DiagnosticsState.instance (see file header).
final List<(String, Future<void> Function(PreferencesState, bool), bool Function(PreferencesState))>
    _boolPrefs = [
  (
    'stashCabinetDefaultExpanded',
    (s, v) => s.setStashCabinetDefaultExpanded(v),
    (s) => s.stashCabinetDefaultExpanded
  ),
  (
    'instantBlameHover',
    (s, v) => s.setInstantBlameHover(v),
    (s) => s.instantBlameHover
  ),
  (
    'writeChangeIdHeader',
    (s, v) => s.setWriteChangeIdHeader(v),
    (s) => s.writeChangeIdHeader
  ),
  (
    'autoSelectNewChanges',
    (s, v) => s.setAutoSelectNewChanges(v),
    (s) => s.autoSelectNewChanges
  ),
  (
    'diffMediaEnabled',
    (s, v) => s.setDiffMediaEnabled(v),
    (s) => s.diffMediaEnabled
  ),
  (
    'diffBinaryEnabled',
    (s, v) => s.setDiffBinaryEnabled(v),
    (s) => s.diffBinaryEnabled
  ),
  (
    'fetchOnlineIssuesOnBranchLoad',
    (s, v) => s.setFetchOnlineIssuesOnBranchLoad(v),
    (s) => s.fetchOnlineIssuesOnBranchLoad
  ),
  (
    'rememberWorkInProgress',
    (s, v) => s.setRememberWorkInProgress(v),
    (s) => s.rememberWorkInProgress
  ),
  (
    'hideAiFeatures',
    (s, v) => s.setHideAiFeatures(v),
    (s) => s.hideAiFeatures
  ),
  (
    'aiReadOnlyDefault',
    (s, v) => s.setAiReadOnlyDefault(v),
    (s) => s.aiReadOnlyDefault
  ),
  (
    'logoAnimatesWhenUnfocused',
    (s, v) => s.setLogoAnimatesWhenUnfocused(v),
    (s) => s.logoAnimatesWhenUnfocused
  ),
];

Map<String, Object?> _prefsSnapshot(PreferencesState s) => {
      'motionRate': s.motionRate,
      'changesPanelWidthPx': s.changesPanelWidthPx,
      'logosPadX': s.logosPadX,
      'logosPadY': s.logosPadY,
      'fileSortGuide': s.fileSortGuide.index,
      'fileSortInverted': s.fileSortInverted,
      'issuesSortDescending': s.issuesSortDescending,
      'tagsSortDescending': s.tagsSortDescending,
      'commitStructure': s.commitStructure.index,
      'commitVoice': s.commitVoice.index,
      'commitCoverage': s.commitCoverage.index,
      'undoWindowSeconds': s.undoWindowSeconds,
      'undoWindowOverrides': s.undoWindowOverrides,
      for (final b in _boolPrefs) b.$1: b.$3(s),
    };

Gen<_PrefOp> _genPrefOp() => genFrequency<_PrefOp>([
      (2, (rng) => _PrefLoad()),
      (5, (rng) => _SetMotionRate(genDouble(min: -0.5, max: 2.5)(rng))),
      (3, (rng) => _SetReduceMotion(rng.nextBool())),
      (5, (rng) => _SetChangesPanelWidth(rng.simpleIntBetween(100, 700))),
      (4,
          (rng) => _SetLogosPad(genDouble(min: -0.5, max: 1.5)(rng),
              genDouble(min: -0.5, max: 1.5)(rng))),
      (4, (rng) => _SetFileSortGuide(rng.pick(FileSortGuide.values))),
      (3, (rng) => _SetFileSortInverted(rng.nextBool())),
      (3, (rng) => _SetIssuesSortDescending(rng.nextBool())),
      (3, (rng) => _SetTagsSortDescending(rng.nextBool())),
      (3, (rng) => _SetCommitStructure(rng.pick(CommitStructure.values))),
      (3, (rng) => _SetCommitVoice(rng.pick(CommitVoice.values))),
      (3, (rng) => _SetCommitCoverage(rng.pick(CommitCoverage.values))),
      (5, (rng) => _SetUndoWindowSeconds(rng.simpleIntBetween(-100, 4000))),
      (5,
          (rng) => _SetUndoWindowFor(rng.pick(UndoActionKind.values),
              rng.simpleIntBetween(-100, 4000))),
      (2, (rng) => _ResyncUndoWindows()),
      (8,
          (rng) => _SetBoolPref(
              rng.intBetween(0, _boolPrefs.length - 1), rng.nextBool())),
    ]);
