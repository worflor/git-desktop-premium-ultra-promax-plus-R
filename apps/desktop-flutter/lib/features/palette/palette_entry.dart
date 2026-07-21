// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter/widgets.dart';

import '../../backend/git_result.dart';

enum PaletteCategory {
  repo,
  action,
  command,
  navigation,
  setting,
  branch,
  commit,
  file,
  stash,
  tag,
}

enum PaletteActionType {
  navigate,
  execute,
  toggle,
}

enum ChipTone {
  accent,
  positive,
  negative,
  chromatic1,
  chromatic2,
  core,
  muted,
  faint,
  staged,
  modified,
  deleted,
  conflicted,
}

/// Structural role tags — the scorer operates on these, not strings.
/// Each flag is a physical property of the entry that the Born axes
/// can observe. An entry can carry multiple flags.
enum EntryTag {
  // Sync operations (state axis observes ahead/behind)
  syncPush,
  syncPull,
  syncFetch,
  syncForcePush,

  // Staging operations (state axis observes staged/unstaged)
  stageAll,
  unstageAll,
  discardAll,
  doCommit,

  // Branch mutations
  branchCreate,
  branchDelete,
  branchRename,

  // Stash operations (state axis observes stash count)
  stashPush,
  stashPop,
  stashApply,
  stashDrop,

  // History operations
  tagCreate,
  cherryPick,
  revertCommit,

  // Navigation (mode axis demotes these — keyboard shortcuts exist)
  navWithShortcut,

  // PR
  prAction,

  // Repo/desk identity
  repoEntry,
  deskEntry,
  repoChild,

  // Predictive (momentum-derived)
  predicted,

  // Needs warm Logos engine before execution
  needsEngine,
}

class PaletteEntry {
  PaletteEntry({
    required this.id,
    required this.label,
    required this.category,
    required this.actionType,
    this.tags = const {},
    this.subtitle,
    this.keywords = const [],
    this.shortcutLabel,
    this.chipLabel,
    this.chipTone,
    this.icon,
    this.readBool,
    this.writeBool,
    this.onExecute,
    this.onMutate,
    this.refPath,
    this.mutatesRepoPath,
  }) : assert(onExecute == null || onMutate == null,
            'An entry is either a plain action (onExecute) or a git mutation '
            '(onMutate) — never both.'),
        assert(onMutate == null || mutatesRepoPath != null,
            'A mutating entry must declare which repo it targets — the '
            'palette keys its post-action refresh to it.');

  final String id;
  final String label;
  final String? subtitle;
  final PaletteCategory category;
  final PaletteActionType actionType;
  Set<EntryTag> tags;
  final List<String> keywords;
  final String? shortcutLabel;
  final String? chipLabel;
  final ChipTone? chipTone;
  List<String> chipStack = const [];
  final IconData? icon;

  /// Path this entry references (file path, repo path, desk path).
  /// Used by the scorer for repo-position and momentum axes without
  /// parsing string IDs.
  final String? refPath;

  final bool Function()? readBool;
  final void Function(bool)? writeBool;

  /// Non-mutating action (navigate, open a panel, copy to clipboard). Its
  /// return value is discarded by design — that's why a git call must never
  /// live here (a `Future<GitResult>` would silently coerce to `void` and the
  /// outcome — a rejected push, a conflicted pop — would vanish).
  ///
  /// One sanctioned exception: GUIDED mutations (force-push, stash pop and
  /// apply, pull) run as async [onExecute] closures because they own an
  /// interactive middle — confirm dialogs, the conflict editor — that the
  /// fire-and-report [onMutate] channel cannot host. A guided flow accepts
  /// three invariants in exchange, all of which [onMutate] gets for free:
  ///   1. it runs against the registry's root-bound context (outlives the
  ///      palette panel),
  ///   2. every outcome — success, failure, deferral — is surfaced; nothing
  ///      returns silently,
  ///   3. state reads and the post-action refresh are keyed to the repo it
  ///      mutated (`refreshStatusIfActive` / direct git probes), never to
  ///      whatever repo is active when its awaits resolve.
  final void Function()? onExecute;

  /// Git-mutating action. Typed to hand its [GitResult] back to the palette,
  /// which awaits it, classifies any failure, toasts success/failure, and
  /// refreshes status. Making the result flow OUT of the closure is what makes
  /// dropping it structurally impossible: you cannot write `onMutate: () =>
  /// git.push()` and lose the outcome — the palette owns it.
  ///
  /// Type note: `Future<GitResult<void>>` callbacks satisfy this contract.
  /// In Dart's subtyping, `void` is a top type interchangeable with
  /// `Object?`, so `GitResult<void> <: GitResult<Object?>` — the analyzer
  /// accepts the git helpers directly; no wrapping is needed or wanted.
  final Future<GitResult<Object?>> Function()? onMutate;

  /// The repo [onMutate] targets — the SAME path baked into its closure, as a
  /// declared field so the palette's post-action refresh is keyed to the repo
  /// actually mutated rather than whatever repo is active when the Future
  /// settles. Constructor-asserted for every mutating entry, so the contract
  /// can't drift when a future entry mutates a non-active repo.
  final String? mutatesRepoPath;

  double score = 0;
  List<(int, int)>? matchRanges;
  List<String> provenance = const [];

  bool hasTag(EntryTag t) => tags.contains(t);
}
