// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_target.dart — what a review is ABOUT, and how that becomes a diff.
//
// Review used to mean exactly one thing: the working tree. The evidence
// pipeline underneath it never cared — `_runLogosDiffusion` takes diff TEXT,
// `buildDiffProbe` derives paths from it, and every producer downstream reads
// the probe. The only part that assumed a working tree was the derivation at
// the very front, and one escape hatch (`rawDiffOverride`) that let the PR
// flow inject bytes while silently losing the branch name, the status summary
// and the stat summary along the way.
//
// So this file does not add a second pipeline. It names the thing that was
// always implicit — the SUBJECT of the review — and gives it one resolver.
//
// THE TWO PIECES THAT MUST NOT BE CONFLATED
//
// A review has a diff and it has a position in history, and they are not the
// same object:
//
//   * The DIFF is a pair of trees. Working tree: index/HEAD against what is
//     on disk. A commit: its parent against itself. A range: base against
//     tip. Every one of those is a tree pair, which is why they can share a
//     single downstream.
//
//   * The POSITION is a set of commits on the engine's axis. It is a SET, not
//     an interval: `git log` linearises a DAG, so `A..B` on branchy history is
//     a scattered subset of axis indices, not a contiguous span. Building this
//     around index arithmetic would silently review the wrong commits the
//     first time it met a merge.
//
// And the diff of a range is NOT the sum of its commits' diffs — intermediate
// states cancel. Keeping the two separate is what makes that a non-issue
// rather than a bug.

import 'dart:io' show ProcessResult;

import 'admitted_git.dart' show admitGitPatchText;
import 'analysis_admission.dart' show AdmissionDecision;
import 'git.dart' show gitBlobTextBatch, runGit;
import 'git_diff_paths.dart' show unCQuoteGitPath;
import 'git_result.dart';
import 'logos_commit_axis.dart';

/// Widest diff the range resolver will enumerate commits for. Matches the
/// stats window: a commit older than the newest 1000 cannot be on the axis
/// anyway, so this bounds the `rev-list` without discarding anything that
/// could have been located.
const int kMaxRangeEnumeration = 1000;

/// Git's canonical machine-stable diff form, for any patch body this file
/// produces. `-c diff.binary=false` is a GLOBAL flag and must precede the
/// subcommand; the rest are diff options.
///
/// Same doctrine as `_kDiffCmd` / `_kDiffContentPins` in git.dart: a repo or
/// user gitconfig carrying `diff.external`, `color.diff`, `diff.noprefix` or
/// `diff.binary=true` can reshape or explode a patch body out from under the
/// code that reads it, and this body IS read — `buildDiffProbe` parses paths
/// out of it and the hunk ranker parses hunks.
const List<String> _kPatchCmd = ['-c', 'diff.binary=false', 'diff-tree'];
const List<String> _kPatchPins = [
  '--no-color',
  '--no-ext-diff',
  '--src-prefix=a/',
  '--dst-prefix=b/',
];

/// Git's empty-tree-ish sentinel in `--raw` output: an all-zero OID marks the
/// absent side of an addition or deletion. Matched by shape rather than by a
/// literal so SHA-256 repositories (64 zeros) work unchanged.
bool _isZeroOid(String oid) =>
    oid.isNotEmpty && oid.codeUnits.every((c) => c == 0x30);

// ── What a review is about ───────────────────────────────────────────

/// Where a change stands in time, which is the one thing a reviewer must not
/// be wrong about.
enum ReviewStance {
  /// Not yet committed. Advice can still change what gets written down.
  pending,

  /// Already in this repository's history. The reviewer is reading, not
  /// gatekeeping, and everything that happened afterwards is available as
  /// evidence about it.
  landed,

  /// Proposed from somewhere else and not in this history — a pull request.
  /// Advice still applies, but not to a commit that is about to be made here.
  proposed,

  /// Not a change at all: code that already exists and is being AUDITED.
  ///
  /// The distinction is not cosmetic. Every other stance hands the reviewer a
  /// change and asks whether it is right. This one hands it settled code and
  /// asks what is wrong with it — a different question, needing a different
  /// scene and different evidence. Routing a region through the change-shaped
  /// prompt produces polite commentary on a wall of "new" lines, which
  /// demonstrates well and hunts badly.
  settled,
}

/// The subject of a review.
sealed class ReviewTarget {
  const ReviewTarget();

  /// Exhaustive, so a new target kind cannot silently inherit the wrong
  /// tense. The review prompt said "you are reviewing a proposed commit
  /// immediately before it is created" unconditionally before this existed,
  /// which is simply false for a commit from last year and steers the model
  /// into advising against work that has already shipped.
  ReviewStance get stance => switch (this) {
        WorkingTreeTarget() => ReviewStance.pending,
        CommitTarget() || RangeTarget() => ReviewStance.landed,
        PreparedDiffTarget() => ReviewStance.proposed,
        RegionTarget() => ReviewStance.settled,
      };
}

/// The uncommitted work: the index, the working tree, or both.
///
/// The odd variant, and deliberately so. Every other target is a pair of
/// TREES, which git can diff with one plumbing call. This one is a two-deep
/// pending stack (HEAD → index → worktree) plus files git does not track at
/// all, so its derivation needs the index-aware, argv-chunked, untracked-file-
/// synthesising machinery that lives with the rest of the review gather. The
/// flags below are the slice of that stack under review — they predate this
/// type and are exactly what they always were.
final class WorkingTreeTarget extends ReviewTarget {
  final bool includeStaged;
  final bool includeUnstaged;
  const WorkingTreeTarget({
    required this.includeStaged,
    required this.includeUnstaged,
  });
}

/// One commit, named by any revspec git understands (`HEAD~3`, a tag, a
/// branch, an abbreviated OID).
final class CommitTarget extends ReviewTarget {
  final String revspec;
  const CommitTarget(this.revspec);
}

/// Everything between two revisions.
///
/// [mergeBase] is REQUIRED rather than inferred, because the difference is
/// the difference between `A..B` and `A...B` and getting it wrong silently
/// reviews the wrong change set. False compares the two endpoints; true
/// compares their merge base against [tip], which is what "what did this
/// branch add" means.
final class RangeTarget extends ReviewTarget {
  final String base;
  final String tip;
  final bool mergeBase;
  const RangeTarget({
    required this.base,
    required this.tip,
    required this.mergeBase,
  });

  /// What [branch] adds relative to [against] — the three-dot comparison,
  /// named for the thing people actually mean by it.
  factory RangeTarget.branchDelta(String branch, {required String against}) =>
      RangeTarget(base: against, tip: branch, mergeBase: true);
}

/// A region of the codebase AS IT EXISTS, audited rather than diffed.
///
/// The variant that makes a whole-repository sweep possible, and the only one
/// whose subject is not a change. That matters because a repository's history
/// is not its codebase: sweeping every commit covers only what was ever
/// edited, and code written once and never touched again — where unexamined
/// bugs keep best — is invisible to a history sweep by construction.
///
/// Resolution renders the region as an all-additions patch, the same shape
/// the gather already synthesizes for untracked files, so everything
/// downstream keeps working on diff text. That is a TRANSPORT decision only:
/// the prompt scene forks on [ReviewStance.settled], because a reviewer told
/// "here is a change" will critique the change, and there isn't one.
final class RegionTarget extends ReviewTarget {
  /// Files in the region, at [revision].
  final List<String> paths;

  /// Usually `HEAD`. Live bugs live at HEAD — auditing an old snapshot
  /// surfaces defects that were repaired years ago.
  final String revision;

  /// Human name for the region, e.g. `lib/backend/ipc (4 files)`.
  final String label;

  const RegionTarget({
    required this.paths,
    required this.label,
    this.revision = 'HEAD',
  });
}

/// A patch somebody else already produced.
///
/// The PR flow owns its diff spool and must keep owning it — that spool is
/// byte-gated and its ownership is load-bearing. This variant is how it says
/// so out loud. It replaces four loose override parameters
/// (`rawDiffOverride`, `branchNameOverride`, `statusSummaryOverride`,
/// `statSummaryOverride`) whose valid combinations were unstated, and with
/// them the `'(pr)'` magic branch name that used to leak into prompts.
final class PreparedDiffTarget extends ReviewTarget {
  final String diffText;
  final String label;
  final String branchName;
  final String statusSummary;
  final String statSummary;
  const PreparedDiffTarget({
    required this.diffText,
    required this.label,
    this.branchName = '',
    this.statusSummary = '',
    this.statSummary = '',
  });
}

// ── Where it sits on the engine's axis ───────────────────────────────

/// Why a commit is not on the engine's commit axis.
enum OffAxisReason {
  /// A merge. The stats walk runs `--no-merges`, so NO merge commit is ever
  /// on the axis — including `HEAD` immediately after a merge. This is the
  /// common cause, not the exotic one, which is precisely why the off-axis
  /// case is modelled explicitly instead of as a null index.
  mergeCommit,

  /// The stats walk never visited it. One reason, not three, because the
  /// three are indistinguishable without evidence nobody has here: the commit
  /// may be older than the window (1000 by default), on a branch that was not
  /// reachable from HEAD when the engine was built, or in a repository whose
  /// engine is simply older than it. Naming any one of those specifically
  /// would be a guess, and the consequence is identical either way — the axis
  /// cannot place it.
  notInWindow,

  /// No engine was available to ask. Says nothing about the commit.
  engineCold,
}

/// Where the reviewed change sits in history.
///
/// Sealed, and the index is never a nullable int, because "no index" has four
/// distinct causes with different meanings (above) and a null collapses them
/// into one. Evidence weighting switches over this exhaustively.
sealed class AxisAnchor {
  const AxisAnchor();

  /// Whether this review is looking BACKWARDS at history rather than at work
  /// in progress. The one bit the prompt has to state plainly.
  bool get isRetrospective => this is! WorkingTipAnchor;

  /// The axis position "after" is measured from, or null when there is no
  /// meaningful one. Feeds `retrospectiveFocusWeights`.
  ///
  /// Null for uncommitted work (nothing has happened after it yet) and for a
  /// commit no position could be found for. Exhaustive over the sealed set,
  /// so a new anchor kind cannot quietly default to "no hindsight".
  int? get bisectIndex => switch (this) {
        WorkingTipAnchor() => null,
        CommitAnchor(:final index) => index,
        // The NEWEST located commit in the range: everything after the range
        // ended is what counts as hindsight for all of it.
        RangeAnchor(:final indices) =>
          indices.isEmpty ? null : indices.reduce((a, b) => a > b ? a : b),
        OffAxisAnchor(:final nearestIndex) => nearestIndex,
      };
}

/// The pending commit at the tip of the axis: uncommitted work.
final class WorkingTipAnchor extends AxisAnchor {
  const WorkingTipAnchor();
}

/// A single commit, located.
final class CommitAnchor extends AxisAnchor {
  final int index;
  final String oid;
  const CommitAnchor({required this.index, required this.oid});
}

/// A set of commits. [indices] holds those that could be located on the axis
/// and is a SET because a DAG range scatters across `git log` order; [total]
/// is how many commits the range actually contains, which can exceed
/// `indices.length` when some are merges or fall outside the window.
final class RangeAnchor extends AxisAnchor {
  final Set<int> indices;
  final int total;
  final String baseOid;
  final String tipOid;
  const RangeAnchor({
    required this.indices,
    required this.total,
    required this.baseOid,
    required this.tipOid,
  });

  /// The oldest located position, or null when none of the range is on axis.
  int? get oldest => indices.isEmpty ? null : indices.reduce((a, b) => a < b ? a : b);
}

/// A real commit that the axis cannot locate. [nearestIndex] is the fallback
/// position evidence should be bisected at (a merge's first parent, say), or
/// null when even that could not be found.
final class OffAxisAnchor extends AxisAnchor {
  final String oid;
  final OffAxisReason reason;
  final int? nearestIndex;
  const OffAxisAnchor({
    required this.oid,
    required this.reason,
    this.nearestIndex,
  });
}

// ── What resolution produces ─────────────────────────────────────────

/// A review subject, resolved into everything the gather needs.
///
/// Every field is non-nullable: a resolver that cannot produce one of these
/// returns an error instead of a half-populated record. That is the whole
/// reason this type exists rather than four optional override parameters.
class ResolvedReviewScope {
  /// The unified diff under review.
  final String diffText;

  /// Per-path change summary — `git status --porcelain` for the working tree,
  /// `--name-status` for a tree pair. Same role in the prompt either way.
  final String statusSummary;

  /// `--stat` output.
  final String statSummary;

  /// Human description of the subject: `commit a1b2c3d "subject"`,
  /// `main...feature (12 commits)`, `all included files`.
  final String label;

  /// The branch name for the working tree; for history, the revision
  /// description that stands in for it.
  final String branchName;

  /// Paths the diff touches (destination side for renames).
  final List<String> paths;

  final AxisAnchor anchor;

  const ResolvedReviewScope({
    required this.diffText,
    required this.statusSummary,
    required this.statSummary,
    required this.label,
    required this.branchName,
    required this.paths,
    required this.anchor,
  });

  bool get isRetrospective => anchor.isRetrospective;
}

// ── Parsing a target off a command line ──────────────────────────────

/// Parse the CLI's revision arguments into a target.
///
/// [commit] takes precedence over [range]; both null yields null so the
/// caller can fall back to the working tree. `A..B` compares endpoints,
/// `A...B` compares from the merge base — the same two-dot/three-dot
/// distinction git itself draws, carried through rather than guessed at.
/// A bare `REV` in [range] means `REV~1..REV`.
ReviewTarget? parseReviewTargetSpec({String? commit, String? range}) {
  final c = commit?.trim() ?? '';
  if (c.isNotEmpty) return CommitTarget(c);
  final r = range?.trim() ?? '';
  if (r.isEmpty) return null;
  final triple = r.indexOf('...');
  if (triple > 0 && triple + 3 < r.length) {
    return RangeTarget(
      base: r.substring(0, triple),
      tip: r.substring(triple + 3),
      mergeBase: true,
    );
  }
  final double = r.indexOf('..');
  if (double > 0 && double + 2 < r.length) {
    return RangeTarget(
      base: r.substring(0, double),
      tip: r.substring(double + 2),
      mergeBase: false,
    );
  }
  // A bare revision in the range slot is the single commit it names — the
  // shorthand people reach for, resolved rather than rejected.
  return CommitTarget(r);
}

// ── Resolution ───────────────────────────────────────────────────────

/// Turn a history [target] into a resolved scope.
///
/// Handles [CommitTarget], [RangeTarget] and [PreparedDiffTarget].
/// [WorkingTreeTarget] is NOT handled here and returns an error if passed:
/// its derivation needs the index-aware, untracked-synthesising path that
/// lives with the rest of the review gather, and duplicating a lesser version
/// of it here is exactly the fork this file exists to prevent. The caller
/// switches over the sealed target exhaustively; the working-tree arm derives
/// in place and builds the same [ResolvedReviewScope].
///
/// [axis] locates the result in history. Passing [LogosCommitAxis.emptyAxis]
/// (the default) is legitimate — it yields an [OffAxisAnchor] with
/// [OffAxisReason.engineCold], which degrades evidence weighting and nothing
/// else. The diff itself never depends on the engine.
Future<GitResult<ResolvedReviewScope>> resolveReviewTarget({
  required String repositoryPath,
  required ReviewTarget target,
  List<String> scopedPaths = const [],
  LogosCommitAxis axis = LogosCommitAxis.emptyAxis,
}) async {
  switch (target) {
    case WorkingTreeTarget():
      return const GitResult.err(
        'The working tree is derived by the review gather, not by '
        'resolveReviewTarget.',
      );

    case PreparedDiffTarget(
        :final diffText,
        :final label,
        :final branchName,
        :final statusSummary,
        :final statSummary,
      ):
      if (diffText.trim().isEmpty) {
        return const GitResult.err('The supplied diff is empty.');
      }
      return GitResult.ok(ResolvedReviewScope(
        diffText: diffText,
        statusSummary: statusSummary,
        statSummary: statSummary,
        label: label,
        branchName: branchName,
        paths: _pathsFromNameStatus(statusSummary),
        // Bytes from elsewhere carry no revision we could locate. Not
        // "unknown position" — no position.
        anchor: const OffAxisAnchor(oid: '', reason: OffAxisReason.engineCold),
      ));

    case RegionTarget():
      return _resolveRegion(repositoryPath, target);

    case CommitTarget(:final revspec):
      return _resolveCommit(repositoryPath, revspec, scopedPaths, axis);

    case RangeTarget(:final base, :final tip, :final mergeBase):
      return _resolveRange(
          repositoryPath, base, tip, mergeBase, scopedPaths, axis);
  }
}

/// Render a region's files at a revision as an all-additions patch.
///
/// Content comes from the object store (`cat-file --batch`), not the working
/// tree, so an audit of HEAD is unaffected by whatever is currently
/// uncommitted — an audit that changed its answer because you had a file open
/// would be worthless.
Future<GitResult<ResolvedReviewScope>> _resolveRegion(
  String repositoryPath,
  RegionTarget target,
) async {
  if (target.paths.isEmpty) {
    return const GitResult.err('That region contains no files.');
  }

  // `ls-tree` for the blob OIDs: it both confirms each path exists at the
  // revision and hands over the object ids, which is what lets the read be
  // admitted at its measured size rather than a guess.
  // Line-delimited rather than `-z`: git C-quotes any path containing a
  // newline, so a line split is unambiguous and [_decodePath] undoes the
  // quoting. A NUL delimiter would need a NUL literal in this source file,
  // which the source-law suite forbids — a rule this very edit proved the
  // worth of, having silently written one here.
  final listed = await _runPathChunked(
    repositoryPath,
    const ['ls-tree', '-r', '--full-name'],
    [target.revision],
    target.paths,
  );
  if (!listed.ok) {
    return GitResult.err(
      'Could not read ${target.revision}: ${listed.error}',
    );
  }

  final oidByPath = <String, String>{};
  for (final entry in listed.data!.split('\n')) {
    final tab = entry.indexOf('\t');
    if (tab < 0) continue;
    final meta = entry.substring(0, tab).split(RegExp(r'\s+'));
    // `<mode> <type> <oid>\t<path>`; skip submodules and subtrees.
    if (meta.length < 3 || meta[1] != 'blob') continue;
    oidByPath[_decodePath(entry.substring(tab + 1))] = meta[2];
  }
  if (oidByPath.isEmpty) {
    return GitResult.err(
      'None of that region\'s files exist at ${target.revision}.',
    );
  }

  final admitted = await admitGitPatchText(
    repositoryPath,
    oidByPath.values,
    () => gitBlobTextBatch(repositoryPath, oidByPath.values.toSet()),
  );
  if (!admitted.ran) {
    return GitResult.err(
      admitted.decision == AdmissionDecision.declined
          ? 'That region is too large to audit in one pass '
              '(${oidByPath.length} files). It needs to be split.'
          : 'Reading that region was superseded by a repository switch.',
    );
  }
  final contents = admitted.value!;

  final patch = StringBuffer();
  final nameStatus = StringBuffer();
  final stat = StringBuffer();
  final covered = <String>[];
  for (final entry in oidByPath.entries) {
    final body = contents[entry.value];
    // Skipping unreadable blobs is right — there is nothing to audit — but
    // "unreadable" is NOT "decoded to an empty string". The batch reader
    // decodes leniently, so a PNG comes back as a long string of replacement
    // characters: non-empty, and rendered as thousands of nonsense `+` lines
    // for a model to read. Git's own test is the right one — a NUL byte near
    // the start means binary.
    if (body == null || body.isEmpty || _looksBinary(body)) continue;
    final lines = body.split('\n');
    // A trailing newline yields a final empty element that is not a line.
    final lineCount = lines.isNotEmpty && lines.last.isEmpty
        ? lines.length - 1
        : lines.length;
    if (lineCount <= 0) continue;

    covered.add(entry.key);
    patch.writeln('diff --git a/${entry.key} b/${entry.key}');
    patch.writeln('--- /dev/null');
    patch.writeln('+++ b/${entry.key}');
    patch.writeln('@@ -0,0 +1,$lineCount @@');
    for (var i = 0; i < lineCount; i++) {
      patch.writeln('+${lines[i]}');
    }
    nameStatus.writeln('A\t${entry.key}');
    stat.writeln(' ${entry.key} | $lineCount +');
  }

  if (covered.isEmpty) {
    return const GitResult.err(
      'That region holds no readable text — its files are binary or empty.',
    );
  }

  return GitResult.ok(ResolvedReviewScope(
    diffText: patch.toString(),
    statusSummary: nameStatus.toString(),
    statSummary: stat.toString(),
    label: target.label,
    branchName: target.revision,
    paths: covered,
    // A region is not a point in history — it is the state of some files at
    // one. There is no commit to anchor to, and inventing one would put a
    // retrospective boost on an audit that has no "after".
    anchor: const OffAxisAnchor(oid: '', reason: OffAxisReason.engineCold),
  ));
}

Future<GitResult<ResolvedReviewScope>> _resolveCommit(
  String repositoryPath,
  String revspec,
  List<String> scopedPaths,
  LogosCommitAxis axis,
) async {
  final oidResult = await _revParseCommit(repositoryPath, revspec);
  if (!oidResult.ok) return GitResult.err(oidResult.error!);
  final oid = oidResult.data!;

  final parents = await _parentsOf(repositoryPath, oid);
  if (parents == null) {
    return GitResult.err('Could not read the parents of $revspec.');
  }

  // A merge shows NOTHING by default: `git show <merge>` and
  // `git diff-tree -p <merge>` both emit an empty patch, and combined
  // (`--cc`) format is not a unified diff any parser here can read. Silently
  // reviewing an empty patch would report a clean bill on a merge — the worst
  // possible failure — so the first parent is chosen explicitly and the label
  // says which side was taken.
  final isMerge = parents.length > 1;
  final String? baseRev;
  if (parents.isEmpty) {
    // Zero parents is TWO different situations and only one of them is a root
    // commit. In a shallow clone, git hides a boundary commit's parents, so a
    // grafted commit reports none — and diffing it as a root would render
    // every file in the tree as newly added and hand the reviewer a fiction.
    //
    // The commit OBJECT is the discriminator: it records its real parents
    // whether or not they are present in the object store. A `parent` line
    // with no reachable parent means grafted, not root.
    if (await _objectRecordsAParent(repositoryPath, oid)) {
      return GitResult.err(
        '$revspec sits at the edge of a shallow clone — its parent is not '
        'present, so there is nothing to diff it against. Run '
        '`git fetch --deepen=<n>` (or `--unshallow`) and try again.',
      );
    }
    // A genuine root commit. `diff-tree --root` is git's own answer and needs
    // no empty-tree constant, so this stays correct on SHA-256 repositories
    // where that constant differs.
    baseRev = null;
  } else {
    baseRev = parents.first;
  }

  final subject = await _subjectOf(repositoryPath, oid);
  final short = oid.length >= 7 ? oid.substring(0, 7) : oid;
  final label = isMerge
      ? 'merge $short (first-parent)${subject.isEmpty ? '' : ' — $subject'}'
      : 'commit $short${subject.isEmpty ? '' : ' — $subject'}';

  final built = await _buildPatch(
    repositoryPath: repositoryPath,
    baseRev: baseRev,
    tipRev: oid,
    scopedPaths: scopedPaths,
  );
  if (!built.ok) return GitResult.err(built.error!);
  final patch = built.data!;

  return GitResult.ok(ResolvedReviewScope(
    diffText: patch.diffText,
    statusSummary: patch.nameStatus,
    statSummary: patch.stat,
    label: label,
    branchName: short,
    paths: patch.paths,
    anchor: _anchorForCommit(
      axis: axis,
      oid: oid,
      isMerge: isMerge,
      firstParent: parents.isEmpty ? null : parents.first,
    ),
  ));
}

Future<GitResult<ResolvedReviewScope>> _resolveRange(
  String repositoryPath,
  String baseSpec,
  String tipSpec,
  bool mergeBase,
  List<String> scopedPaths,
  LogosCommitAxis axis,
) async {
  final baseResult = await _revParseCommit(repositoryPath, baseSpec);
  if (!baseResult.ok) return GitResult.err(baseResult.error!);
  final tipResult = await _revParseCommit(repositoryPath, tipSpec);
  if (!tipResult.ok) return GitResult.err(tipResult.error!);

  var baseOid = baseResult.data!;
  final tipOid = tipResult.data!;

  if (mergeBase) {
    final mb = await runGit(repositoryPath, ['merge-base', baseOid, tipOid]);
    final found = (mb.stdout as String).trim();
    if (mb.exitCode != 0 || found.isEmpty) {
      return GitResult.err(
        '$baseSpec and $tipSpec have no common ancestor, so there is no '
        'three-dot range between them. Use two dots to compare them directly.',
      );
    }
    baseOid = found;
  }

  if (baseOid == tipOid) {
    return GitResult.err(
      '$baseSpec and $tipSpec resolve to the same commit — the range is '
      'empty.',
    );
  }

  // A REVERSED range still produces a perfectly well-formed patch, one that
  // presents every addition as a deletion. Reviewing it yields findings that
  // are all exactly backwards, and nothing downstream can tell. Auto-swapping
  // would be worse — it silently reviews something other than what was asked
  // for — so this rejects and says which way round it should go.
  //
  // Only meaningful for two-dot: a merge base is an ancestor of the tip by
  // construction. Divergent revisions (neither an ancestor of the other) are
  // a legitimate comparison and pass through.
  if (!mergeBase) {
    final reversed =
        await runGit(repositoryPath, ['merge-base', '--is-ancestor', tipOid, baseOid]);
    if (reversed.exitCode == 0) {
      return GitResult.err(
        'The range $baseSpec..$tipSpec runs backwards — $tipSpec is an '
        'ancestor of $baseSpec. Every change would be inverted. Did you mean '
        '$tipSpec..$baseSpec?',
      );
    }
  }

  final revList = await runGit(repositoryPath, [
    'rev-list',
    '-n',
    '$kMaxRangeEnumeration',
    '$baseOid..$tipOid',
  ]);
  final rangeOids = revList.exitCode == 0
      ? (revList.stdout as String)
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList()
      : const <String>[];

  final countResult =
      await runGit(repositoryPath, ['rev-list', '--count', '$baseOid..$tipOid']);
  final total = countResult.exitCode == 0
      ? int.tryParse((countResult.stdout as String).trim()) ?? rangeOids.length
      : rangeOids.length;

  final built = await _buildPatch(
    repositoryPath: repositoryPath,
    baseRev: baseOid,
    tipRev: tipOid,
    scopedPaths: scopedPaths,
  );
  if (!built.ok) return GitResult.err(built.error!);
  final patch = built.data!;

  final shortBase =
      baseOid.length >= 7 ? baseOid.substring(0, 7) : baseOid;
  final shortTip = tipOid.length >= 7 ? tipOid.substring(0, 7) : tipOid;
  final dots = mergeBase ? '...' : '..';
  final label = '$baseSpec$dots$tipSpec '
      '($shortBase$dots$shortTip, $total commit${total == 1 ? '' : 's'})';

  final indices = <int>{};
  for (final oid in rangeOids) {
    final i = axis.indexOf(oid);
    if (i != null) indices.add(i);
  }

  return GitResult.ok(ResolvedReviewScope(
    diffText: patch.diffText,
    statusSummary: patch.nameStatus,
    statSummary: patch.stat,
    label: label,
    branchName: '$shortBase$dots$shortTip',
    paths: patch.paths,
    anchor: RangeAnchor(
      indices: indices,
      total: total,
      baseOid: baseOid,
      tipOid: tipOid,
    ),
  ));
}

AxisAnchor _anchorForCommit({
  required LogosCommitAxis axis,
  required String oid,
  required bool isMerge,
  required String? firstParent,
}) {
  if (axis.isEmpty) {
    return OffAxisAnchor(oid: oid, reason: OffAxisReason.engineCold);
  }
  final index = axis.indexOf(oid);
  if (index != null) return CommitAnchor(index: index, oid: oid);
  return OffAxisAnchor(
    oid: oid,
    reason: isMerge ? OffAxisReason.mergeCommit : OffAxisReason.notInWindow,
    // A merge's own position is unknowable to a `--no-merges` axis, but its
    // first parent's usually is, and that is the right place to bisect
    // evidence from.
    nearestIndex: firstParent == null ? null : axis.indexOf(firstParent),
  );
}

// ── Git plumbing ─────────────────────────────────────────────────────

class _BuiltPatch {
  final String diffText;
  final String nameStatus;
  final String stat;
  final List<String> paths;
  const _BuiltPatch({
    required this.diffText,
    required this.nameStatus,
    required this.stat,
    required this.paths,
  });
}

/// The whole tree-pair → patch path, in one place.
///
/// [baseRev] null means "diff against the empty tree" (a root commit), which
/// `--root` expresses natively.
Future<GitResult<_BuiltPatch>> _buildPatch({
  required String repositoryPath,
  required String? baseRev,
  required String tipRev,
  required List<String> scopedPaths,
}) async {
  final revArgs = <String>[
    if (baseRev == null) '--root' else baseRev,
    tipRev,
  ];

  // `--raw` first: it is the cheap probe that both names the changed paths
  // and hands over the blob OIDs on each side, which is what lets the patch
  // be admitted at its measured cost rather than a guess.
  final rawResult = await _runPathChunked(
    repositoryPath,
    [..._kPatchCmd, '-r', '--raw', '--no-commit-id', '-M'],
    revArgs,
    scopedPaths,
  );
  if (!rawResult.ok) {
    return GitResult.err('Could not read the change list: ${rawResult.error}');
  }
  final rawText = rawResult.data!;
  final records = parseRawDiffRecords(rawText);
  final paths = [for (final r in records) r.path];
  if (paths.isEmpty) {
    return const GitResult.err(
      'That revision has no file changes to review.',
    );
  }

  // Context lines adapt to how many files actually changed — measured here,
  // where the number is known exactly, rather than guessed from the scope
  // list the way the working-tree path has to.
  final contextLines = paths.length <= 3 ? 15 : (paths.length <= 10 ? 10 : 6);

  final nameStatus = await _runPathChunked(
    repositoryPath,
    [..._kPatchCmd, '-r', '--name-status', '--no-commit-id', '-M'],
    revArgs,
    scopedPaths,
  );
  final stat = await _runPathChunked(
    repositoryPath,
    [..._kPatchCmd, '--stat=200', '--no-commit-id'],
    revArgs,
    scopedPaths,
  );

  // The patch body is the one unbounded thing here (`--raw`, `--name-status`
  // and `--stat` are all a line per file), so it is the one thing admitted.
  // The declaration is MEASURED — the exact size of every blob the patch
  // spans, from the `--raw` output already in hand — because the working
  // tree's stat-the-files estimate says nothing useful about a commit whose
  // files have since grown or been deleted.
  final admitted = await admitGitPatchText(
    repositoryPath,
    blobOidsOf(records),
    () => _runPathChunked(
      repositoryPath,
      [
        ..._kPatchCmd,
        '-p',
        '--no-commit-id',
        '-r',
        ..._kPatchPins,
        '-U$contextLines',
        '--patience',
        '-M',
        '--ignore-cr-at-eol',
      ],
      revArgs,
      scopedPaths,
    ),
  );
  if (!admitted.ran) {
    return GitResult.err(
      admitted.decision == AdmissionDecision.declined
          // Covers both refusals honestly: the patch may be too large for the
          // analysis budget, or its objects may not have been measurable at
          // all. The remedy is the same and the tool does not know which,
          // so it does not claim to.
          ? 'That revision could not be read in one pass (${paths.length} '
              'files) — it is either too large for the analysis budget or its '
              'objects could not be sized. Narrow it with a shorter range or '
              'scope it to specific paths.'
          : 'Reading that diff was superseded by a repository switch.',
    );
  }
  final patch = admitted.value!;
  if (!patch.ok) {
    return GitResult.err('Could not read the diff: ${patch.error}');
  }
  final diffText = patch.data!;
  // "Has text to read" is the presence of a HUNK, not a non-empty patch. A
  // commit touching only binary files still prints a header per file and the
  // line `Binary files a/x and b/x differ`, so an emptiness check passes it
  // straight through to a reviewer with nothing to read. The same is true of
  // a pure rename (`similarity index 100%`) and a mode-only change.
  if (!diffText.split('\n').any((l) => l.startsWith('@@'))) {
    return const GitResult.err(
      'That revision changes no text to review — it only touches binary '
      'files, renames, or file modes.',
    );
  }

  return GitResult.ok(_BuiltPatch(
    diffText: diffText,
    nameStatus: nameStatus.ok ? nameStatus.data! : '',
    stat: stat.ok ? stat.data! : '',
    paths: paths,
  ));
}

/// Run a `diff-tree` invocation over [paths], splitting the pathspec across
/// as many calls as the platform's argv limit requires and concatenating the
/// results.
///
/// Every output shape this is used with — `--raw`, `--name-status`, `-p` —
/// is a per-file record stream, so concatenation is the whole join. The one
/// flag that cannot survive splitting is `-M`: rename detection pairs a
/// deletion with an addition, and a pair split across two invocations is
/// invisible to both. It is dropped when there is more than one chunk, which
/// costs rename LABELLING on very large pathspecs and never correctness —
/// the same trade the working-tree gather already makes.
///
/// This replaced a flat refusal above ~24 KB of pathspec. A ceiling there
/// would have been a cap standing in for the work of chunking, on the exact
/// input — a big scoped sweep — the feature exists to serve.
Future<GitResult<String>> _runPathChunked(
  String repositoryPath,
  List<String> baseArgs,
  List<String> revArgs,
  List<String> paths,
) async {
  if (paths.isEmpty) {
    final r = await runGit(repositoryPath, [...baseArgs, ...revArgs]);
    if (r.exitCode != 0) return GitResult.err(_stderr(r));
    return GitResult.ok(r.stdout as String);
  }

  // Conservative: leaves headroom under Windows' 32767-character command
  // line for git's own path, the base args, and per-argument quoting. Matches
  // the working-tree gather's budget so the two cannot drift apart.
  const argBudget = 24000;
  final chunks = <List<String>>[];
  var current = <String>[];
  var currentLen = 0;
  for (final path in paths) {
    final cost = path.length + 3;
    if (current.isNotEmpty && currentLen + cost > argBudget) {
      chunks.add(current);
      current = <String>[];
      currentLen = 0;
    }
    current.add(path);
    currentLen += cost;
  }
  if (current.isNotEmpty) chunks.add(current);

  final effectiveArgs = chunks.length > 1
      ? [
          for (final a in baseArgs)
            if (a != '-M') a,
        ]
      : baseArgs;

  final buffer = StringBuffer();
  for (final chunk in chunks) {
    final r = await runGit(
      repositoryPath,
      [...effectiveArgs, ...revArgs, '--', ...chunk],
    );
    if (r.exitCode != 0) return GitResult.err(_stderr(r));
    buffer.write(r.stdout as String);
  }
  return GitResult.ok(buffer.toString());
}

/// Git's binary test: a NUL byte within the first 8000 characters.
///
/// Written as an escape rather than a raw byte — a literal NUL in source is
/// invisible in diffs and turns the file binary for grep, which the source-law
/// suite forbids for exactly that reason.
bool _looksBinary(String body) {
  final limit = body.length < 8000 ? body.length : 8000;
  for (var i = 0; i < limit; i++) {
    if (body.codeUnitAt(i) == 0) return true;
  }
  return false;
}

/// One `diff-tree -r --raw` record:
/// `:<srcMode> <dstMode> <srcOid> <dstOid> <status>` TAB `<path>[TAB <newPath>]`.
class RawDiffRecord {
  /// The path the change is ABOUT — the destination for a rename or copy.
  final String path;

  /// Blob OIDs on each side, excluding the all-zero sentinel that marks the
  /// absent side of an add or delete.
  final List<String> blobOids;

  const RawDiffRecord({required this.path, required this.blobOids});
}

/// Parse a `diff-tree -r --raw` body.
///
/// ONE parser. The paths and the blob OIDs used to be read by two functions
/// walking this same grammar independently — which is how a rename's
/// destination-wins rule gets applied in one and forgotten in the other, and
/// the two then disagree about which file a size belongs to, silently. A
/// single record type makes them the same answer by construction.
List<RawDiffRecord> parseRawDiffRecords(String rawText) {
  final records = <RawDiffRecord>[];
  final seen = <String>{};
  for (final line in rawText.split('\n')) {
    if (!line.startsWith(':')) continue;
    final tab = line.indexOf('\t');
    if (tab < 0) continue;
    final meta = line.substring(0, tab).split(RegExp(r'\s+'));
    if (meta.length < 5) continue;
    // A rename/copy carries `old` TAB `new`; the destination is what the
    // review is about, so the LAST field wins.
    final fields = line.substring(tab + 1).split('\t');
    final path = _decodePath(fields.last);
    if (path.isEmpty || !seen.add(path)) continue;
    records.add(RawDiffRecord(
      path: path,
      blobOids: [
        for (final oid in [meta[2], meta[3]])
          if (oid.isNotEmpty && !_isZeroOid(oid)) oid,
      ],
    ));
  }
  return records;
}

/// Every blob OID the records name, both sides.
///
/// Repeats are MEANINGFUL and deliberately kept: a blob appearing on several
/// paths is printed once per path, so admission must reserve for each.
List<String> blobOidsOf(List<RawDiffRecord> records) =>
    [for (final r in records) ...r.blobOids];

List<String> _pathsFromNameStatus(String text) {
  final paths = <String>[];
  final seen = <String>{};
  for (final line in text.split('\n')) {
    final fields = line.split('\t');
    if (fields.length < 2) continue;
    final path = _decodePath(fields.last);
    if (path.isNotEmpty && seen.add(path)) paths.add(path);
  }
  return paths;
}

/// A path as git printed it, back to the path it names.
///
/// `core.quotePath` defaults to true, so anything outside ASCII arrives
/// C-quoted — a path with an accent in it comes back as a quoted string full
/// of octal escapes rather than the name on disk. Left as-is those strings
/// reach the prompt, the reviewed-path list, and every comparison against a
/// caller's `--files` argument, none of which could ever match.
/// [unCQuoteGitPath] returns unquoted input unchanged, so this is correct for
/// every path either way.
String _decodePath(String raw) => unCQuoteGitPath(raw.trim());

/// Resolve [revspec] to a full commit OID, with errors a person can act on.
Future<GitResult<String>> _revParseCommit(
  String repositoryPath,
  String revspec,
) async {
  final r = await runGit(
      repositoryPath, ['rev-parse', '--verify', '--end-of-options', '$revspec^{commit}']);
  if (r.exitCode != 0) {
    final err = _stderr(r);
    // A shallow clone that does not contain the parent is a distinct failure
    // from a typo, and the fix is completely different. Any attempt to paper
    // over it fabricates a base tree.
    if (err.contains('shallow') || err.contains('grafted')) {
      return GitResult.err(
        '$revspec is outside this shallow clone. Run '
        '`git fetch --deepen=<n>` (or `--unshallow`) and try again.',
      );
    }
    return GitResult.err('Unknown revision: $revspec');
  }
  final oid = (r.stdout as String).trim();
  if (oid.isEmpty) return GitResult.err('Unknown revision: $revspec');
  return GitResult.ok(oid);
}

/// Parent OIDs of [oid], or null when it could not be read. Empty for a root
/// commit; more than one for a merge.
Future<List<String>?> _parentsOf(String repositoryPath, String oid) async {
  final r = await runGit(repositoryPath, ['rev-list', '--parents', '-n', '1', oid]);
  if (r.exitCode != 0) return null;
  final parts = (r.stdout as String)
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  // First token is the commit itself; the rest are its parents. A shallow
  // clone's boundary commit reports no parents here even though it has one in
  // the real history — which is why `_buildPatch` uses `--root` for the
  // no-parent case and produces a full-content diff rather than a wrong one.
  return parts.skip(1).toList();
}

/// Whether [oid]'s commit object records a parent, regardless of whether that
/// parent is reachable. True for a shallow-clone boundary commit, false for a
/// genuine root — the one question `rev-list --parents` cannot answer,
/// because grafting is exactly what it hides.
Future<bool> _objectRecordsAParent(String repositoryPath, String oid) async {
  final r = await runGit(repositoryPath, ['cat-file', 'commit', oid]);
  if (r.exitCode != 0) return false;
  for (final line in (r.stdout as String).split('\n')) {
    // Headers run until the first blank line; the message body could itself
    // contain a line starting with "parent ".
    if (line.trim().isEmpty) return false;
    if (line.startsWith('parent ')) return true;
  }
  return false;
}

Future<String> _subjectOf(String repositoryPath, String oid) async {
  final r = await runGit(repositoryPath, ['log', '-1', '--format=%s', oid]);
  if (r.exitCode != 0) return '';
  return (r.stdout as String).trim();
}

String _stderr(ProcessResult r) {
  final e = (r.stderr as String).trim();
  return e.isEmpty ? 'git exited ${r.exitCode}' : e.split('\n').first;
}
