// Pure decision logic for the branches lens: cross-link resolution and
// branch-delete failure classification. No Flutter/BuildContext — every
// function here takes plain data in and returns a plain (sealed, where the
// shape matters) value out, so the branches page's tests can reach the
// actual user-facing decisions without building a single widget.

import 'dart:io' show Platform;

import '../../backend/desk_pr.dart';
import '../../backend/dtos.dart';

/// Resolved cross-links for a single branch: an open desk (worktree),
/// a desk PR, and how many issues that PR links. Seeds the branch-card
/// indicator chips and the desk-aware delete error.
class BranchLinks {
  final WorktreeData? desk;
  final DeskPr? deskPr;
  final int issueCount;
  const BranchLinks({this.desk, this.deskPr, this.issueCount = 0});
  bool get hasAny => desk != null || deskPr != null || issueCount > 0;
}

/// Pure resolver: branch name → its desk / desk-PR / linked-issue count.
/// Kept free of BuildContext so it's reusable and testable in isolation.
/// Issue count folds both local and remote linkage on the PR.
BranchLinks resolveBranchLinks(
  String branch, {
  required List<WorktreeData> desks,
  required Map<String, DeskPr> deskPrsByBranch,
}) {
  WorktreeData? desk;
  for (final d in desks) {
    if (d.branch == branch && d.path.isNotEmpty) {
      desk = d;
      break;
    }
  }
  final pr = deskPrsByBranch[branch];
  final issueCount =
      pr == null ? 0 : pr.linkedIssues.length + pr.linkedRemoteIssues.length;
  return BranchLinks(desk: desk, deskPr: pr, issueCount: issueCount);
}

/// True when a branch delete bounced because a worktree (desk) still
/// holds the branch. Git's wording has shifted across versions — older
/// git says the branch is "checked out at <path>", current git (2.52,
/// verified against a real worktree in this repo's integration test)
/// says it's "used by worktree at <path>" — so both phrasings are
/// checked. Detecting either lets the UI offer a jump-to-desk instead of
/// dumping raw stderr the user can't act on.
bool isWorktreeHoldsBranchError(String rawStderr) {
  final s = rawStderr.toLowerCase();
  return s.contains('checked out at') || s.contains('used by worktree at');
}

/// Pulls the worktree path git quotes in either phrasing of the held-branch
/// error — "checked out at '<path>'" and "used by worktree at '<path>'"
/// both end in `at '<path>'`, so one pattern covers both. Null if the
/// stderr doesn't carry a quoted path (unexpected git wording, truncated
/// output, etc.) so callers can fall back cleanly.
///
/// The capture group is greedy (`.*`), not `[^']*` — verified empirically
/// (a real `git worktree add` at a path containing an apostrophe, e.g.
/// `.../o'brien desk`, followed by a real failing `git branch -d`) that git
/// does NOT shell-quote embedded apostrophes when it renders this message;
/// it just splices the raw path between two literal `'` characters:
/// `error: cannot delete branch 'x' used by worktree at 'C:/.../o'brien desk'`.
/// A non-greedy/exclusive `[^']*` stops at the first `'` inside the path
/// itself, truncating it. Greedy `.*` naturally backtracks to the LAST `'`
/// on the line instead — and because `.` never matches a line terminator
/// (verified: this message is always exactly one line, no trailing hint),
/// that backtracking can't run past a `\n`/`\r`, so a doubled stderr (e.g.
/// a `-d` attempt's message followed by a retried `-D` attempt's, each on
/// its own line) still resolves each line's own path rather than reaching
/// across into the next message.
String? _extractWorktreePathFromError(String rawStderr) {
  final m = RegExp(r"at '(.*)'").firstMatch(rawStderr);
  return m?.group(1);
}

/// Normalizes a filesystem path for cross-source comparison: backslashes
/// folded to forward slashes, trailing separators trimmed, and case folded
/// ONLY where the platform's filesystems are case-insensitive by default
/// (Windows, macOS). On Linux, two worktree paths differing only by case
/// are genuinely distinct desks — folding there could attach a delete
/// refusal to the wrong desk. Verified empirically against a real
/// `git worktree add` + failed delete on this machine: both git's stderr
/// and `worktree list --porcelain` already render Windows paths with
/// forward slashes, but desk paths reaching this function aren't
/// guaranteed to share that source, so the fold stays defensive.
/// [caseFold] overrides the platform default so both behaviours are
/// testable from a single OS. Known accepted tradeoff: macOS folds by
/// platform default, not per-volume detection — a case-sensitive APFS
/// volume with case-twin desk paths could fold them together, but this
/// comparator is only the fallback behind an exact string match (git
/// prints identical path strings in both sources), and the worst outcome
/// is a wrong jump-to-desk suggestion, never a destructive action.
String normalizeWorktreePath(String path, {bool? caseFold}) {
  final fold = caseFold ?? (Platform.isWindows || Platform.isMacOS);
  // No trim(): both sources feeding this comparison (the path git quotes
  // in stderr, and `worktree list --porcelain`) are exact — incidental
  // whitespace cannot occur, but a directory name legally CAN begin or
  // end with a space, so trimming could only ever collapse two real
  // paths into one identity, never repair a real mismatch.
  var p = path.replaceAll('\\', '/');
  if (fold) p = p.toLowerCase();
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// Strips git's `error:` prefix and `hint:` lines, leaving only the
/// human-readable first sentence.
String _humanizeDeleteError(String raw) {
  final firstLine = raw.split('\n').first.trim();
  if (firstLine.toLowerCase().startsWith('error:')) {
    return firstLine.substring(6).trim();
  }
  return firstLine.isEmpty ? 'delete failed' : firstLine;
}

/// Every way a branch delete can fail, and what the UI owes the user for
/// each. Sealed so the page's switch is exhaustive by construction — a new
/// failure shape can't silently fall through to raw stderr.
sealed class BranchDeleteOutcome {
  const BranchDeleteOutcome();
}

/// Git refused because the branch has unmerged commits (`git branch -d`'s
/// safety check). The safe path bounced; offer the user a force-confirm
/// instead of surfacing an error.
class DeleteNotMerged extends BranchDeleteOutcome {
  const DeleteNotMerged();
}

/// A desk (worktree) still has the branch checked out. Raw git stderr
/// ("... is already checked out at <path>") isn't actionable, so name the
/// desk and offer a jump to it — never auto-remove the worktree to force
/// the delete through.
class DeleteHeldByDesk extends BranchDeleteOutcome {
  final WorktreeData desk;
  const DeleteHeldByDesk(this.desk);
}

/// Anything else, humanized: git's `error:` prefix stripped, first line
/// only.
class DeleteFailed extends BranchDeleteOutcome {
  final String message;
  const DeleteFailed(this.message);
}

/// Classifies a failed `git branch -d/-D` attempt's stderr into what the
/// branches lens should offer the user. [force] mirrors whichever delete
/// was attempted — the not-fully-merged bounce only means "offer force"
/// when a safe (non-force) delete is what bounced; a failed force delete
/// falls through to the humanized message like any other failure.
/// [desks] is the live worktree list, searched for one holding [branch].
BranchDeleteOutcome classifyBranchDeleteFailure(
  String stderr, {
  required String branch,
  required List<WorktreeData> desks,
  bool force = false,
}) {
  if (!force && stderr.toLowerCase().contains('not fully merged')) {
    return const DeleteNotMerged();
  }
  if (isWorktreeHoldsBranchError(stderr)) {
    // Git's stderr quotes the exact desk path that holds the branch — trust
    // that over the branch name it also mentions. Name matching (below, as
    // fallback) can miss on quoting or rendering differences between what
    // the classifier receives and what the desk list holds; the path is
    // the ground truth git itself refused the delete over.
    WorktreeData? desk;
    final stderrPath = _extractWorktreePathFromError(stderr);
    if (stderrPath != null) {
      final target = normalizeWorktreePath(stderrPath);
      for (final d in desks) {
        if (d.path.isNotEmpty && normalizeWorktreePath(d.path) == target) {
          desk = d;
          break;
        }
      }
    }
    desk ??= resolveBranchLinks(
      branch,
      desks: desks,
      deskPrsByBranch: const {},
    ).desk;
    if (desk != null) {
      return DeleteHeldByDesk(desk);
    }
  }
  return DeleteFailed(_humanizeDeleteError(stderr));
}
