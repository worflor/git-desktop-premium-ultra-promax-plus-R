// desk_pr_diff.dart — compute a DeskPr's diff/files on demand
//
// A DeskPr's metadata (title, body, comments, reviews) lives in
// refs/manifold/desks/<branch>; its actual code change is the set of
// commits the head has added *since it forked from* the base. This
// module materialises that into the same PullRequestDetail shape the
// existing renderer consumes for remote PRs, so the diff view, file
// pills, magnetic field, etc. all light up identically for local PRs.

import 'dart:async';

import 'desk_pr.dart';
import 'git.dart' as git;
import 'remote_types.dart';
import 'git_result.dart';

/// Build a [PullRequestDetail] for a local desk PR by diffing the base
/// against the head in [repoPath] (which should be the main repo or any
/// of its worktrees — git resolves through the common dir).
///
/// The comparison is **three-dot** (`base...head`), i.e. head against the
/// *merge base* of base and head, not two-dot (`base..head`, a raw
/// tree-to-tree diff). This is load-bearing for correctness: once the
/// base ref advances past the fork point (upstream gains commits the
/// branch hasn't picked up), a two-dot diff renders reversals of every
/// unrelated upstream commit as part of the PR — the same failure the
/// git.dart desk-patch path documents at its merge-base
/// scoping. Three-dot restricts the diff to what the branch itself
/// contributed, symmetric across ahead / behind / diverged states.
///
/// `--find-renames` is passed to both git calls so a moved file shows as
/// one rename entry rather than an add + delete pair.
///
/// Returns an err only on infrastructure failure (git missing, refs
/// unresolvable). An empty branch (no commits yet) is a legitimate
/// success with an empty file list.
Future<GitResult<PullRequestDetail>> fetchLocalDeskPrDetail({
  required String repoPath,
  required DeskPr pr,
  int spoolBytesThreshold = git.kDetailDiffSpillBytes,
  // Mirrors the remote providers' includeDiff: stats-only callers (e.g.
  // DeskPrState.recomputeDiffStats) get the numstat-derived file list
  // without the patch body ever being fetched — a spooled body handed to a
  // caller that only wanted counts would orphan its temp dir, and even the
  // String form is pure waste there.
  bool includeDiff = true,
}) async {
  final threeDot = '${pr.baseRef}...${pr.headRef}';
  final twoDot = '${pr.baseRef}..${pr.headRef}';
  try {
    // Prefer the merge-base (three-dot) comparison. If the base and head
    // share no common ancestor, git refuses three-dot with a message
    // mentioning "no merge base"; there is genuinely no fork point to
    // scope against, so we degrade to the two-dot tree diff rather than
    // showing the user nothing. Both git passes (numstat + body) must use
    // the *same* spec, so we resolve it once off the numstat probe.
    //
    // Both passes route through git.dart's gated exec layer with the
    // diff-family pins — raw `Process.run` here used to re-open the hostile
    // gitconfig class (`color.diff=always`, `diff.binary=true`, external
    // diff) that the pins made unrepresentable everywhere else.
    var spec = threeDot;
    // `-z` NUL-terminates every field, which is the only format that
    // parses renames and unusual filenames byte-exactly. Verified empirically
    // against this git: a rename emits `adds \t dels \t \0 oldpath \0 newpath \0`
    // (an empty path field after the counts, then the two NUL-delimited
    // paths); a normal/binary entry emits `adds \t dels \t path \0`. Binary
    // files still report `-` for both counts. Splitting the whole stream on
    // NUL and walking records keeps non-ASCII paths intact where the old
    // whitespace-`trim()` + TAB-`split` parser would have mangled them.
    var numstatRes = await git.getRangeNumstatZ(
      repoPath,
      spec,
      findRenames: true,
    );
    if (!numstatRes.ok) {
      final err = numstatRes.error ?? '';
      if (!err.contains('no merge base')) return GitResult.err(err);
      spec = twoDot;
      numstatRes = await git.getRangeNumstatZ(
        repoPath,
        spec,
        findRenames: true,
      );
      if (!numstatRes.ok) {
        return GitResult.err(numstatRes.error ?? 'numstat failed');
      }
    }

    final files = _parseNumstatZ(numstatRes.data ?? '');

    if (!includeDiff) {
      return GitResult.ok(pr.toDetail(files: files, diff: ''));
    }

    // The patch body ALWAYS streams to a disk spool first, then the ACTUAL
    // byte length decides the representation. Line churn was tried as the
    // gate and rejected: a diff with a few extremely long changed lines
    // reports tiny churn while weighing tens of MB, so any line-count
    // heuristic reopens the OOM class this path exists to close. Counting
    // bytes after streaming cannot be wrong, and the round trip for a small
    // diff (write + read a few KB of temp file) is noise next to the git
    // spawn itself. A machine-scale diff never exists as a Dart String.
    final spooled = await git.spoolRangeDiff(repoPath, spec, findRenames: true);
    if (!spooled.ok || spooled.data == null) {
      // The numstat probe succeeded but the patch body didn't — that is an
      // infrastructure failure, not "this PR has no diff". Returning ok with
      // an empty diff would render a valid-looking detail whose changes have
      // silently vanished, which is the one thing a review surface must
      // never do.
      return GitResult.err(spooled.error ?? 'diff fetch failed');
    }
    final spool = spooled.data!;
    if (spool.byteLength > spoolBytesThreshold) {
      return GitResult.ok(
        pr.toDetail(files: files, diff: '', diffSpool: spool, diffLoaded: true),
      );
    }
    // Small diff: materialize the String (cheap; keeps the per-file eager
    // slices) and release the spool.
    // NOTE: we deliberately DON'T parse the diff into ParsedLines here. The
    // only field that needed them (`diffByFile`) was never read, and parsing a
    // multi-GB PR into one object per row was the machine-scale OOM. The diff
    // is rendered lazily downstream (the shell indexes `rawDiff`/
    // `rawDiffByFile` on demand).
    try {
      final rawDiff = spool.byteLength == 0
          ? ''
          : await git.readSpoolStringLenient(spool.path);
      return GitResult.ok(
        pr.toDetail(files: files, diff: rawDiff, diffLoaded: true),
      );
    } finally {
      await spool.dispose();
    }
  } catch (e) {
    return GitResult.err('local diff failed: $e');
  }
}

/// Parse `git diff --numstat -z --find-renames` output into [PrFile]s.
///
/// Records are separated implicitly by NUL boundaries rather than
/// newlines. Each record begins with `adds \t dels \t`. What follows the
/// second TAB disambiguates the kind:
///   • a non-empty path → an ordinary change; the path runs to the next
///     NUL,
///   • an empty field (an immediate NUL) → a rename; the *next two*
///     NUL-delimited tokens are the old and new paths.
///
/// A rename is surfaced as its NEW path carrying the numstat counts —
/// [PrFile] has no distinct rename field, and both [parseUnifiedDiff] and
/// [sliceDiffByFile] key a rename's hunks on the `b/` (post-change) path,
/// so the new path is exactly what makes the file pill and its diff
/// section line up. Binary files report `-`/`-` and become a 0/0 entry
/// with the path preserved so callers can still name them.
List<PrFile> _parseNumstatZ(String stdout) {
  final files = <PrFile>[];
  final tokens = stdout.split('\u0000');
  var i = 0;
  while (i < tokens.length) {
    final head = tokens[i];
    if (head.isEmpty) {
      i++;
      continue;
    }
    final tab1 = head.indexOf('\t');
    final tab2 = tab1 < 0 ? -1 : head.indexOf('\t', tab1 + 1);
    if (tab2 < 0) {
      // Not a record head (malformed / stray token) — skip defensively.
      i++;
      continue;
    }
    final addsRaw = head.substring(0, tab1);
    final delsRaw = head.substring(tab1 + 1, tab2);
    final rest = head.substring(tab2 + 1);
    String path;
    if (rest.isEmpty) {
      // Rename: old path in the next token, new path in the one after.
      final oldPath = (i + 1) < tokens.length ? tokens[i + 1] : '';
      final newPath = (i + 2) < tokens.length ? tokens[i + 2] : '';
      path = newPath.isNotEmpty ? newPath : oldPath;
      i += 3;
    } else {
      path = rest;
      i += 1;
    }
    if (path.isEmpty) continue;
    final adds = addsRaw == '-' ? 0 : (int.tryParse(addsRaw) ?? 0);
    final dels = delsRaw == '-' ? 0 : (int.tryParse(delsRaw) ?? 0);
    files.add(PrFile(path: path, additions: adds, deletions: dels));
  }
  return files;
}
