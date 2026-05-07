import 'package:flutter/widgets.dart';

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
    this.refPath,
  });

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
  final void Function()? onExecute;

  double score = 0;
  List<(int, int)>? matchRanges;
  List<String> provenance = const [];

  bool hasTag(EntryTag t) => tags.contains(t);
}
