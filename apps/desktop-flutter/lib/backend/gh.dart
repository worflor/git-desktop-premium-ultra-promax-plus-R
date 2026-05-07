import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import 'git_result.dart';
import 'remote_types.dart';
import '../diagnostics/diagnostics_state.dart';
import '../features/diff/diff_models.dart';

export 'remote_types.dart' show
    PrReviewer, PullRequestSummary, PullRequestDetail, PrFile,
    RemoteComment, IssueSummary, IssueDetail, CheckSummary, TailEvent;

/// Thin wrapper around the GitHub CLI (`gh`). Mirrors the patterns in
/// `git.dart`: shell out, parse JSON, wrap in [GitResult]. We rely on
/// `gh` rather than rolling our own GitHub API client because it
/// already solves auth, refresh, and rate-limit handling — every user
/// that has `gh auth login` finished gets PR/issue support for free.

class GhStatus {
  final bool installed;
  final bool authenticated;
  final String? authError;

  const GhStatus({
    required this.installed,
    required this.authenticated,
    this.authError,
  });

  bool get usable => installed && authenticated;
}


Future<GhStatus> ghStatus() async {
  late ProcessResult v;
  late ProcessResult a;
  try {
    final results = await Future.wait([
      Process.run('gh', ['--version'],
          stdoutEncoding: utf8, stderrEncoding: utf8),
      Process.run('gh', ['auth', 'status'],
          stdoutEncoding: utf8, stderrEncoding: utf8),
    ]);
    v = results[0];
    a = results[1];
  } catch (_) {
    return const GhStatus(installed: false, authenticated: false);
  }
  if (v.exitCode != 0) {
    return const GhStatus(installed: false, authenticated: false);
  }
  if (a.exitCode != 0) {
    return GhStatus(
      installed: true,
      authenticated: false,
      authError: (a.stderr is String ? a.stderr as String : '').trim(),
    );
  }
  return const GhStatus(installed: true, authenticated: true);
}

Future<GitResult<List<PullRequestSummary>>> listPullRequests(
  String repoPath, {
  String state = 'open',
  int limit = 50,
}) async {
  final r = await _gh(repoPath, [
    'pr',
    'list',
    '--state',
    state,
    '--limit',
    '$limit',
    '--json',
    'number,title,headRefName,baseRefName,state,isDraft,author,comments,'
        'updatedAt,additions,deletions,changedFiles,mergeable,'
        'reviewDecision,reviewRequests,reviews,labels,assignees',
  ]);
  if (r.exitCode != 0) {
    return GitResult.err(r.stderr.toString().trim());
  }
  try {
    final parsed = jsonDecode(r.stdout.toString()) as List;
    final prs = parsed
        .whereType<Map<String, dynamic>>()
        .map(PullRequestSummary.fromJson)
        .toList();
    return GitResult.ok(prs);
  } catch (e) {
    return GitResult.err('Failed to parse gh pr list: $e');
  }
}

Future<GitResult<List<IssueSummary>>> listIssues(
  String repoPath, {
  String state = 'open',
  int limit = 50,
}) async {
  final r = await _gh(repoPath, [
    'issue',
    'list',
    '--state',
    state,
    '--limit',
    '$limit',
    '--json',
    'number,title,state,author,labels,comments,updatedAt,assignees',
  ]);
  if (r.exitCode != 0) {
    return GitResult.err(r.stderr.toString().trim());
  }
  try {
    final parsed = jsonDecode(r.stdout.toString()) as List;
    final issues = parsed
        .whereType<Map<String, dynamic>>()
        .map(IssueSummary.fromJson)
        .toList();
    return GitResult.ok(issues);
  } catch (e) {
    return GitResult.err('Failed to parse gh issue list: $e');
  }
}

Future<GitResult<PullRequestSummary>> getPullRequestSummary(
  String repoPath,
  int number,
) async {
  final r = await _gh(repoPath, [
    'pr',
    'view',
    '$number',
    '--json',
    'number,title,headRefName,baseRefName,state,isDraft,author,comments,'
        'updatedAt,additions,deletions,changedFiles,mergeable,'
        'reviewDecision,reviewRequests,reviews,labels,assignees',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    return GitResult.ok(PullRequestSummary.fromJson(j));
  } catch (e) {
    return GitResult.err('Failed to parse gh pr view: $e');
  }
}

Future<GitResult<IssueSummary>> getIssueSummary(
  String repoPath,
  int number,
) async {
  final r = await _gh(repoPath, [
    'issue',
    'view',
    '$number',
    '--json',
    'number,title,state,author,labels,comments,updatedAt,assignees',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    return GitResult.ok(IssueSummary.fromJson(j));
  } catch (e) {
    return GitResult.err('Failed to parse gh issue view: $e');
  }
}

Future<String> whoami() async {
  try {
    final r = await Process.run(
      'gh',
      ['api', 'user', '--jq', '.login'],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) return '';
    return r.stdout.toString().trim();
  } catch (_) {
    return '';
  }
}

Future<GitResult<PullRequestDetail>> pullRequestDetail(
  String repoPath,
  int number, {
  bool includeDiff = true,
}) async {
  final viewFut = _gh(repoPath, [
    'pr',
    'view',
    '$number',
    '--json',
    'body,files,comments,reviews',
  ]);
  final diffFut = includeDiff
      ? _gh(repoPath, ['pr', 'diff', '$number'])
      : Future<ProcessResult?>.value(null);
  final view = await viewFut;
  final diffRes = await diffFut;
  if (view.exitCode != 0) {
    return GitResult.err(view.stderr.toString().trim());
  }
  try {
    final j = jsonDecode(view.stdout.toString()) as Map<String, dynamic>;
    final files = (j['files'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((f) => PrFile(
              path: (f['path'] as String? ?? '').trim(),
              additions: (f['additions'] as num? ?? 0).toInt(),
              deletions: (f['deletions'] as num? ?? 0).toInt(),
            ))
        .toList();
    final comments = (j['comments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RemoteComment.fromJson)
        .toList();
    final reviews = (j['reviews'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((r) {
          final author = r['author'];
          final login = author is Map<String, dynamic>
              ? (author['login'] as String? ?? '')
              : '';
          final body = (r['body'] as String? ?? '').trim();
          final state = (r['state'] as String? ?? '').toUpperCase();
          if (body.isEmpty) return null;
          final tag = switch (state) {
            'APPROVED' => '[approved]',
            'CHANGES_REQUESTED' => '[requested changes]',
            'COMMENTED' => '[commented]',
            'DISMISSED' => '[dismissed]',
            _ => '',
          };
          return RemoteComment(
            authorLogin: login,
            body: tag.isEmpty ? body : '$tag\n\n$body',
            createdAt: parseRemoteDate(r['submittedAt']),
          );
        })
        .whereType<RemoteComment>()
        .toList();
    final mergedComments = [...comments, ...reviews]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final rawDiff = diffRes?.stdout.toString() ?? '';
    final parsedLines = rawDiff.length < 32 * 1024
        ? parseUnifiedDiff(rawDiff)
        : await compute(parseUnifiedDiff, rawDiff);
    final byFile = <String, List<ParsedLine>>{};
    for (final l in parsedLines) {
      final key = l.filePath;
      if (key == null) continue;
      (byFile[key] ??= <ParsedLine>[]).add(l);
    }
    return GitResult.ok(PullRequestDetail(
      body: (j['body'] as String? ?? '').trim(),
      files: files,
      comments: mergedComments,
      diff: rawDiff,
      diffByFile: byFile,
      rawDiffByFile: sliceDiffByFile(rawDiff),
    ));
  } catch (e) {
    return GitResult.err('Failed to parse gh pr view: $e');
  }
}

Future<GitResult<IssueDetail>> issueDetail(
  String repoPath,
  int number,
) async {
  final r = await _gh(repoPath, [
    'issue',
    'view',
    '$number',
    '--json',
    'body,comments,assignees,labels',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    return GitResult.ok(IssueDetail(
      body: (j['body'] as String? ?? '').trim(),
      comments: (j['comments'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RemoteComment.fromJson)
          .toList(),
      assignees: parseAssigneeLogins(j['assignees']),
      labels: parseLabelStrings(j['labels']),
    ));
  } catch (e) {
    return GitResult.err('Failed to parse gh issue view: $e');
  }
}

Future<GitResult<void>> submitPrReview(
  String repoPath,
  int number, {
  required String event,
  String body = '',
}) async {
  final flag = switch (event) {
    'approve' => '--approve',
    'request-changes' => '--request-changes',
    'comment' => '--comment',
    _ => '--comment',
  };
  final args = ['pr', 'review', '$number', flag, '--body', body];
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> mergePullRequest(
  String repoPath,
  int number, {
  required String method,
  bool deleteBranch = false,
}) async {
  final flag = switch (method) {
    'squash' => '--squash',
    'rebase' => '--rebase',
    _ => '--merge',
  };
  final args = [
    'pr',
    'merge',
    '$number',
    flag,
    if (deleteBranch) '--delete-branch',
  ];
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> checkoutPullRequest(
    String repoPath, int number) async {
  final r = await _gh(repoPath, ['pr', 'checkout', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> closePullRequest(
    String repoPath, int number) async {
  final r = await _gh(repoPath, ['pr', 'close', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> assignSelfToIssue(
    String repoPath, int number) async {
  final r = await _gh(
      repoPath, ['issue', 'edit', '$number', '--add-assignee', '@me']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> addIssueLabel(
    String repoPath, int number, String label) async {
  final r = await _gh(
      repoPath, ['issue', 'edit', '$number', '--add-label', label]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> closeIssue(String repoPath, int number) async {
  final r = await _gh(repoPath, ['issue', 'close', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> commentOnIssue(
    String repoPath, int number, String body) async {
  if (body.trim().isEmpty) return const GitResult.ok(null);
  final r = await _gh(
      repoPath, ['issue', 'comment', '$number', '--body', body]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<int>> createGhIssue(
  String repoPath, {
  required String title,
  String body = '',
  List<String> labels = const [],
  List<String> assignees = const [],
}) async {
  final args = ['issue', 'create', '--title', title, '--body', body];
  for (final l in labels) { args.addAll(['--label', l]); }
  for (final a in assignees) { args.addAll(['--assignee', a]); }
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final out = r.stdout.toString().trim();
  final match = RegExp(r'/issues/(\d+)').firstMatch(out);
  if (match == null) return GitResult.err('unexpected output: $out');
  return GitResult.ok(int.parse(match.group(1)!));
}

Future<GitResult<void>> editGhIssue(
  String repoPath,
  int number, {
  String? title,
  String? body,
  List<String> addLabels = const [],
  List<String> removeLabels = const [],
}) async {
  final args = ['issue', 'edit', '$number'];
  if (title != null) args.addAll(['--title', title]);
  if (body != null) args.addAll(['--body', body]);
  for (final l in addLabels) { args.addAll(['--add-label', l]); }
  for (final l in removeLabels) { args.addAll(['--remove-label', l]); }
  if (args.length == 3) return const GitResult.ok(null);
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> reopenGhIssue(String repoPath, int number) async {
  final r = await _gh(repoPath, ['issue', 'reopen', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> commentOnPullRequest(
    String repoPath, int number, String body) async {
  if (body.trim().isEmpty) return const GitResult.ok(null);
  final r = await _gh(
      repoPath, ['pr', 'comment', '$number', '--body', body]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<List<CheckSummary>>> listChecks(
  String repoPath,
  int prNumber,
) async {
  final r = await _gh(repoPath, [
    'pr',
    'checks',
    '$prNumber',
    '--json',
    'name,bucket,state,startedAt,completedAt',
  ]);
  final stdout = r.stdout.toString();
  if (stdout.trim().isEmpty) {
    return GitResult.err(r.stderr.toString().trim());
  }
  try {
    final parsed = jsonDecode(stdout) as List;
    final checks = parsed
        .whereType<Map<String, dynamic>>()
        .map(CheckSummary.fromJson)
        .toList();
    return GitResult.ok(checks);
  } catch (e) {
    return GitResult.err('Failed to parse gh pr checks: $e');
  }
}


Future<ProcessResult> _gh(String repo, List<String> args) async {
  final commandLabel = 'gh.${args.isNotEmpty ? args.first : 'unknown'}';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: commandLabel,
  );
  try {
    final result = await Process.run(
      'gh',
      args,
      workingDirectory: repo,
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'end',
      command: commandLabel,
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: result.exitCode == 0 ? null : 'exit.${result.exitCode}',
    );
    return result;
  } catch (e) {
    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'end',
      command: commandLabel,
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: 'process.exception',
    );
    rethrow;
  }
}
