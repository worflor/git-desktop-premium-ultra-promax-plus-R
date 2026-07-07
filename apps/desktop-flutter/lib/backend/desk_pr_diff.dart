// desk_pr_diff.dart — compute a DeskPr's diff/files on demand
//
// A DeskPr's metadata (title, body, comments, reviews) lives in
// refs/manifold/desks/<branch>; its actual code change is the set of
// commits the head has added *since it forked from* the base. This
// module materialises that into the same PullRequestDetail shape the
// existing renderer consumes for remote PRs, so the diff view, file
// pills, magnetic field, etc. all light up identically for local PRs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import 'desk_pr.dart';
import 'remote_types.dart';
import 'git_result.dart';
import 'git.dart' show kMaxRenderableDiffLines;
import '../features/diff/diff_models.dart';

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
/// git.dart desk-patch path documents at `_oversizedDiffStub`/merge-base
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
}) async {
  final threeDot = '${pr.baseRef}...${pr.headRef}';
  final twoDot = '${pr.baseRef}..${pr.headRef}';
  try {
    // Prefer the merge-base (three-dot) comparison. If the base and head
    // share no common ancestor, git refuses three-dot with a message
    // mentioning "no merge base"; there is genuinely no fork point to
    // scope against, so we degrade to the two-dot tree diff rather than
    // showing the user nothing. Both git passes (numstat + raw) must use
    // the *same* spec, so we resolve it once off the numstat probe.
    var spec = threeDot;
    // `-z` NUL-terminates every field, which is the only format that
    // parses renames and unusual filenames byte-exactly. Verified empirically
    // against this git: a rename emits `adds \t dels \t \0 oldpath \0 newpath \0`
    // (an empty path field after the counts, then the two NUL-delimited
    // paths); a normal/binary entry emits `adds \t dels \t path \0`. Binary
    // files still report `-` for both counts. Splitting the whole stream on
    // NUL and walking records keeps non-ASCII paths intact where the old
    // whitespace-`trim()` + TAB-`split` parser would have mangled them.
    var numstatRes = await Process.run(
      'git',
      ['diff', '--numstat', '-z', '--find-renames', spec],
      workingDirectory: repoPath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (numstatRes.exitCode != 0) {
      final err = (numstatRes.stderr as String);
      if (err.contains('no merge base')) {
        spec = twoDot;
        numstatRes = await Process.run(
          'git',
          ['diff', '--numstat', '-z', '--find-renames', spec],
          workingDirectory: repoPath,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
      }
      if (numstatRes.exitCode != 0) {
        return GitResult.err((numstatRes.stderr as String).trim());
      }
    }

    final files = _parseNumstatZ(numstatRes.stdout as String);

    // Oversized-diff guard, mirroring git.dart's `_oversizedDiffStub`
    // philosophy: sum the changed-line count from the (cheap, content-free)
    // numstat we already have, and if it exceeds the same
    // `kMaxRenderableDiffLines` ceiling the rest of the app honours, skip
    // materialising the multi-MB unified diff entirely. The file list stays
    // fully populated from numstat; only the inline patch body becomes a
    // one-block summary stub. The change itself is intact and commits whole.
    var totalLines = 0;
    for (final f in files) {
      totalLines += f.additions + f.deletions;
    }
    if (totalLines > kMaxRenderableDiffLines) {
      final thousands = (totalLines / 1000).round();
      final label = pr.headRef;
      final stub = 'diff --git a/$label b/$label\n'
          '--- a/$label\n'
          '+++ b/$label\n'
          ' Diff too large to render: ~${thousands}k changed lines. '
          'The change itself is intact and stages/commits normally.\n';
      return GitResult.ok(pr.toDetail(
        files: files,
        diff: stub,
        diffByFile: _indexByFile(parseUnifiedDiff(stub)),
      ));
    }

    final diffRes = await Process.run(
      'git',
      ['diff', '--find-renames', spec],
      workingDirectory: repoPath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final rawDiff =
        diffRes.exitCode == 0 ? (diffRes.stdout as String) : '';
    // Mirror gh.dart's isolate-hop heuristic so big diffs don't block
    // the UI thread.
    final parsedLines = rawDiff.length < 32 * 1024
        ? parseUnifiedDiff(rawDiff)
        : await compute(parseUnifiedDiff, rawDiff);

    return GitResult.ok(pr.toDetail(
      files: files,
      diff: rawDiff,
      diffByFile: _indexByFile(parsedLines),
    ));
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

/// Group parsed diff lines by their owning file path — the key the diff
/// renderer looks a file's hunks up under.
Map<String, List<ParsedLine>> _indexByFile(List<ParsedLine> lines) {
  final byFile = <String, List<ParsedLine>>{};
  for (final l in lines) {
    final key = l.filePath;
    if (key == null) continue;
    (byFile[key] ??= <ParsedLine>[]).add(l);
  }
  return byFile;
}
