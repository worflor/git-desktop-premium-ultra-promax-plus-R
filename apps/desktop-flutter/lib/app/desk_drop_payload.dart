// ═════════════════════════════════════════════════════════════════════════
// desk_drop_payload.dart — drag-to-desk payload
//
// When the user drags a branch row (from the BRANCHES lens) or a PR
// row (from the PRS lens) over the desk strip in the topbar, the drag
// carries one of these. The drop target in `_DeskRow` reads the type
// and dispatches:
//   • branch  → WorktreeState.addDesk(branchName)
//   • pr      → fetch pull/<n>/head:pr-<n> + addDesk(pr-<n>)
//
// Small, sealed, serializable. No callbacks on the payload itself —
// the DragTarget owns the dispatch logic so the source widgets just
// describe "what's being dragged," not "what to do with it."
// ═════════════════════════════════════════════════════════════════════════

class DeskDropPayload {
  /// Local branch to open as a new desk. Mutually exclusive with
  /// [remotePrNumber].
  final String? branchName;

  /// Remote PR number to fetch + materialise as a worktree.
  final int? remotePrNumber;

  /// Absolute path to an existing desk (Manifold-managed worktree).
  /// When set, the drag is moving/copying the desk's current diff,
  /// not creating a new workspace. The Changes-page drop target
  /// reads this and overlays `git diff HEAD` of the source desk onto
  /// the active working tree via the existing patch-preview flow.
  final String? deskPath;

  /// Human label for the drag feedback chip. Branch name when a branch
  /// is being dragged; PR title when a PR is.
  final String label;

  const DeskDropPayload._({
    required this.label,
    this.branchName,
    this.remotePrNumber,
    this.deskPath,
  });

  /// Dragging a local branch — e.g. from the BRANCHES list.
  factory DeskDropPayload.branch(String branch) =>
      DeskDropPayload._(label: branch, branchName: branch);

  /// Dragging a remote PR — e.g. from the PRS list. Title comes along
  /// so the drag chip + drop-feedback snackbar read nicely.
  factory DeskDropPayload.remotePr({required int number, required String title}) =>
      DeskDropPayload._(
        label: '#$number $title',
        remotePrNumber: number,
      );

  /// Dragging an existing desk — e.g. from the topbar desk strip onto
  /// the Changes page to "dump" that desk's uncommitted diff here.
  /// [label] is the desk's branch name when known (falls back to its
  /// folder basename) so the drag chip reads meaningfully.
  factory DeskDropPayload.desk({required String path, required String label}) =>
      DeskDropPayload._(label: label, deskPath: path);

  bool get isBranch => branchName != null;
  bool get isRemotePr => remotePrNumber != null;
  bool get isDesk => deskPath != null;
}
