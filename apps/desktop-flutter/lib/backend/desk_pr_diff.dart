// ═════════════════════════════════════════════════════════════════════════
// desk_pr_diff.dart — compute a DeskPr's diff/files on demand
//
// A DeskPr's metadata (title, body, comments, reviews) lives in
// refs/manifold/desks/<branch>; its actual code change is just `git
// diff baseRef..headRef`. This module materialises that into the same
// PullRequestDetail shape the existing renderer consumes for remote
// PRs, so the diff view, file pills, magnetic field, etc. all light
// up identically for local PRs.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import 'desk_pr.dart';
import 'gh.dart';
import 'git_result.dart';
import '../features/diff/diff_models.dart';

/// Build a [PullRequestDetail] for a local desk PR by diffing
/// `pr.baseRef..pr.headRef` in [repoPath] (which should be the main
/// repo or any of its worktrees — git resolves through the common dir).
///
/// Returns `ok(null)` when the diff is empty (legitimate: no commits
/// on the branch yet). Returns an err only on infrastructure failure
/// (git missing, baseRef unresolvable).
Future<GitResult<PullRequestDetail>> fetchLocalDeskPrDetail({
  required String repoPath,
  required DeskPr pr,
}) async {
  final spec = '${pr.baseRef}..${pr.headRef}';
  try {
    // numstat + raw diff in two passes — same shape as gh.dart's
    // remote PR fetch path so downstream code reads them identically.
    final numstatRes = await Process.run(
      'git',
      ['diff', '--numstat', spec],
      workingDirectory: repoPath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (numstatRes.exitCode != 0) {
      return GitResult.err((numstatRes.stderr as String).trim());
    }
    final files = <PrFile>[];
    for (final raw in (numstatRes.stdout as String).split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      final addsRaw = parts[0];
      final delsRaw = parts[1];
      final path = parts.sublist(2).join('\t').trim();
      if (path.isEmpty) continue;
      // Binary files report "-\t-" — treat as 0/0 with the path
      // surfaced so callers can still name them.
      final adds = addsRaw == '-' ? 0 : (int.tryParse(addsRaw) ?? 0);
      final dels = delsRaw == '-' ? 0 : (int.tryParse(delsRaw) ?? 0);
      files.add(PrFile(path: path, additions: adds, deletions: dels));
    }

    final diffRes = await Process.run(
      'git',
      ['diff', spec],
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
    final byFile = <String, List<ParsedLine>>{};
    for (final l in parsedLines) {
      final key = l.filePath;
      if (key == null) continue;
      (byFile[key] ??= <ParsedLine>[]).add(l);
    }

    return GitResult.ok(pr.toDetail(
      files: files,
      diff: rawDiff,
      diffByFile: byFile,
    ));
  } catch (e) {
    return GitResult.err('local diff failed: $e');
  }
}
