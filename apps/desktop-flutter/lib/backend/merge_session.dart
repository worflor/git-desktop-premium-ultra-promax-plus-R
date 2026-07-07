import 'dtos.dart';

/// How a reconciled merge should be recorded in history. A `MergeSession`
/// is the unifying abstraction behind every conflict-producing operation —
/// pull, branch-merge, and patch-apply are all constructors of one — and
/// the topology is the single thing that differs in how the result lands.
enum MergeTopology {
  /// The branch only moves forward; no merge commit. A behind-only pull.
  /// Finalised with `git reset --mixed <incoming>` so resolved working-tree
  /// content survives while the ref + index advance.
  fastForward,

  /// A two-parent merge commit (diverged histories). Finalised by staging
  /// the merged paths, writing `.git/MERGE_HEAD`, and committing — the same
  /// plumbing `git merge` uses internally.
  mergeCommit,

  /// Replay local commits on top of the incoming tip (`pull --rebase`).
  rebase,

  /// A squash merge collapsing the incoming commits into one.
  squash,

  /// Working-tree only — the caller stages/commits (the patch-apply preview
  /// flow). No history is written by the merge machinery itself.
  applyOnly,
}

/// The classified result of a pull / merge / sync. Replaces the flat
/// `GitResult.err(String)` that used to collapse three genuinely different
/// outcomes — "git refused because the tree was dirty", "the merge left
/// conflicts", and "something actually failed" — into one opaque string the
/// UI could only dump raw. Making the states distinct types means a caller
/// can't accidentally treat a recoverable dirty-tree abort as a hard error.
sealed class MergeOutcome {
  const MergeOutcome();
}

/// Completed cleanly. [data] mirrors the legacy [SyncData] so the existing
/// activity-log UI keeps working unchanged.
class MergeClean extends MergeOutcome {
  final SyncData data;
  const MergeClean(this.data);
}

/// The merge produced conflicts in [paths] (repo-relative). [resolved] is
/// true once the user finished the editor and history was recorded; false
/// when conflicts are still sitting in the working tree (e.g. the user
/// cancelled, or this is just a report that the landing-zone strip should
/// surface).
class MergeConflicted extends MergeOutcome {
  final List<String> paths;
  final bool resolved;
  const MergeConflicted(this.paths, {this.resolved = false});
}

/// git refused to start because uncommitted local edits to [paths] would be
/// overwritten — the dirty-tree pre-abort (the "Your local changes … would
/// be overwritten by merge" case). Nothing changed; the tree is intact. The
/// flow layer turns this into a real `git merge-file` reconcile rather than
/// a dead-end error, so it never reaches the UI as a failure.
class MergeBlockedByLocalChanges extends MergeOutcome {
  final List<String> paths;
  const MergeBlockedByLocalChanges(this.paths);
}

/// Anything else — a network/auth failure, a non-fast-forward push, or a git
/// error unrelated to merge content.
class MergeFailed extends MergeOutcome {
  final String message;
  const MergeFailed(this.message);
}

/// The operation can't proceed at the ref level and needs a worktree it
/// hasn't got — the rebase-into-base case where the base branch is checked
/// out nowhere, so there is no working tree to replay onto and we refuse to
/// conjure a hidden one. Distinct from [MergeFailed] because nothing went
/// wrong: the user simply needs to open the branch in a desk first. [message]
/// is the ready-to-show guidance; [branch] / [baseRef] name the pair so a
/// surface can offer to check one out.
class MergeNeedsCheckout extends MergeOutcome {
  final String branch;
  final String baseRef;
  final String message;
  const MergeNeedsCheckout({
    required this.branch,
    required this.baseRef,
    required this.message,
  });
}

/// One-line, user-facing summary of a [MergeOutcome] — the single source of
/// truth so the wording never drifts between the branch pill, the clean-tree
/// dashboard, and the sync panel. [op] names the action ("Pull", "Sync").
/// Conflict outcomes point at the Changes page, which always carries the
/// resolve affordance, so a deferred conflict never dead-ends in a snackbar.
String mergeOutcomeMessage(MergeOutcome outcome, {String op = 'Sync'}) =>
    switch (outcome) {
      MergeClean(:final data) =>
        data.output.isNotEmpty ? data.output : '$op complete.',
      MergeConflicted(:final paths, :final resolved) => resolved
          ? 'Resolved ${paths.length} conflict${paths.length == 1 ? '' : 's'}.'
          : paths.isEmpty
              // Discarded/cancelled before anything was written.
              ? '$op cancelled.'
              : '${paths.length} conflict${paths.length == 1 ? '' : 's'} left — '
                  'resolve them on the Changes page.',
      MergeBlockedByLocalChanges(:final paths) =>
        '${paths.length} file${paths.length == 1 ? '' : 's'} have uncommitted '
            'edits — commit them first.',
      MergeNeedsCheckout(:final message) => message,
      MergeFailed(:final message) => message,
    };

extension MergeOutcomeX on MergeOutcome {
  bool get isClean => this is MergeClean;

  /// The error string for surfaces that still want a flat message (the
  /// activity log, snackbars). Null for non-failure outcomes.
  String? get errorOrNull => switch (this) {
        MergeFailed(:final message) => message,
        _ => null,
      };

  SyncData? get cleanData => switch (this) {
        MergeClean(:final data) => data,
        _ => null,
      };
}

/// A side-effect-free plan for a pull/merge: everything the reconcile and
/// finalize steps need, computed after a `git fetch` but before any tree
/// mutation. Built by `prepareMergePull` in the git backend.
class MergePrep {
  /// True when there is nothing to pull — the tree is already up to date.
  final bool upToDate;

  /// Non-null when preparation itself failed (fetch error, no upstream).
  final String? error;

  final String repoPath;
  final String remote;

  /// The upstream ref label, e.g. `origin/main` — used for marker labels.
  final String upstream;

  /// Resolved OID of the incoming tip (the upstream) and the merge base.
  final String incomingRef;
  final String baseRef;

  /// Marker labels for the editor: `ours` = local branch, `theirs` = upstream.
  final String oursLabel;
  final String theirsLabel;

  /// Paths the incoming tip changed relative to [baseRef] — the merge's
  /// working set.
  final List<String> incomingPaths;

  /// The subset of [incomingPaths] with uncommitted local edits — the files
  /// that make `git merge` refuse. Empty ⇒ the clean-tree native path is
  /// safe; non-empty ⇒ use the dirty `merge-file` reconcile.
  final List<String> blockingPaths;

  final MergeTopology topology;

  bool get dirty => blockingPaths.isNotEmpty;

  const MergePrep({
    required this.repoPath,
    required this.remote,
    required this.upstream,
    required this.incomingRef,
    required this.baseRef,
    required this.oursLabel,
    required this.theirsLabel,
    required this.incomingPaths,
    required this.blockingPaths,
    required this.topology,
  })  : upToDate = false,
        error = null;

  const MergePrep._special({
    required this.upToDate,
    required this.error,
  })  : repoPath = '',
        remote = '',
        upstream = '',
        incomingRef = '',
        baseRef = '',
        oursLabel = 'ours',
        theirsLabel = 'theirs',
        incomingPaths = const [],
        blockingPaths = const [],
        topology = MergeTopology.mergeCommit;

  const MergePrep.upToDate()
      : this._special(upToDate: true, error: null);

  const MergePrep.failed(String message)
      : this._special(upToDate: false, error: message);
}

/// One incoming path after a blob-level 3-way merge. [mergedText] is the
/// `git merge-file` output — the full file with conflict markers when
/// [conflicted], or the clean merged content otherwise. Reconcile produces
/// these in memory and writes nothing; the editor (for conflicts) and the
/// finalize step (for clean paths) own all working-tree writes, so a
/// cancelled reconcile leaves the tree pristine.
class ReconciledFile {
  final String path;
  final String mergedText;
  final bool conflicted;

  /// True when theirs deleted the file and the local copy is unmodified —
  /// finalize should remove it rather than write [mergedText].
  final bool deleted;

  /// True when the path is binary (non-text). Binary can't be 3-way
  /// text-merged: when [conflicted] it's a true binary conflict the caller
  /// must block on; otherwise [binaryBytes] is the raw content to write
  /// (take-theirs / a clean update) — never [mergedText], which would
  /// corrupt the bytes through a UTF-8 round-trip.
  final bool binary;
  final List<int>? binaryBytes;

  const ReconciledFile({
    required this.path,
    required this.mergedText,
    required this.conflicted,
    this.deleted = false,
    this.binary = false,
    this.binaryBytes,
  });
}
