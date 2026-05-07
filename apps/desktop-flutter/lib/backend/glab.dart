import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import 'git_result.dart';
import 'remote_types.dart';
import '../diagnostics/diagnostics_state.dart';
import '../features/diff/diff_models.dart';

/// Thin wrapper around the GitLab CLI (`glab`). Same pattern as gh.dart:
/// shell out, parse JSON, wrap in [GitResult].

class GlabStatus {
  final bool installed;
  final bool authenticated;
  final String? authError;

  const GlabStatus({
    required this.installed,
    required this.authenticated,
    this.authError,
  });

  bool get usable => installed && authenticated;
}

Future<GlabStatus> glabStatus() async {
  late ProcessResult v;
  late ProcessResult a;
  try {
    final results = await Future.wait([
      Process.run('glab', ['--version'],
          stdoutEncoding: utf8, stderrEncoding: utf8),
      Process.run('glab', ['auth', 'status'],
          stdoutEncoding: utf8, stderrEncoding: utf8),
    ]);
    v = results[0];
    a = results[1];
  } catch (_) {
    return const GlabStatus(installed: false, authenticated: false);
  }
  if (v.exitCode != 0) {
    return const GlabStatus(installed: false, authenticated: false);
  }
  if (a.exitCode != 0) {
    return GlabStatus(
      installed: true,
      authenticated: false,
      authError: (a.stderr is String ? a.stderr as String : '').trim(),
    );
  }
  return const GlabStatus(installed: true, authenticated: true);
}

Future<String> glabWhoami() async {
  try {
    final r = await Process.run(
      'glab',
      ['auth', 'status'],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    // glab auth status prints "Logged in to gitlab.com as <username>" to
    // stderr (not stdout). Parse the username from that line.
    final output = '${r.stdout}${r.stderr}';
    final m = RegExp(r'Logged in to \S+ as (\S+)').firstMatch(output);
    if (m != null) return m.group(1)!;
    return '';
  } catch (_) {
    return '';
  }
}


// ---------------------------------------------------------------------------
// Merge Requests
// ---------------------------------------------------------------------------

Future<GitResult<List<PullRequestSummary>>> listMergeRequests(
  String repoPath, {
  String state = 'opened',
  int limit = 50,
}) async {
  final r = await _glab(repoPath, [
    'mr',
    'list',
    '--state',
    state,
    '--per-page',
    '$limit',
    '-F',
    'json',
  ]);
  if (r.exitCode != 0) {
    return GitResult.err(r.stderr.toString().trim());
  }
  try {
    final parsed = jsonDecode(r.stdout.toString()) as List;
    final mrs = parsed
        .whereType<Map<String, dynamic>>()
        .map(_mrSummaryFromGlab)
        .toList();
    return GitResult.ok(mrs);
  } catch (e) {
    return GitResult.err('Failed to parse glab mr list: $e');
  }
}

Future<GitResult<int>> createGlabMr(
  String repoPath, {
  required String title,
  String body = '',
  required String headRef,
  required String baseRef,
  bool draft = false,
  List<String> labels = const [],
  List<String> assignees = const [],
  List<String> reviewers = const [],
}) async {
  final args = ['mr', 'create', '--title', title, '--description', body,
      '--source-branch', headRef, '--target-branch', baseRef, '--yes'];
  if (draft) args.add('--draft');
  if (labels.isNotEmpty) args.addAll(['--label', labels.join(',')]);
  for (final a in assignees) { args.addAll(['--assignee', a]); }
  for (final r in reviewers) { args.addAll(['--reviewer', r]); }
  final r = await _glab(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final out = r.stdout.toString().trim();
  final match = RegExp(r'/merge_requests/(\d+)').firstMatch(out);
  if (match == null) return GitResult.err('unexpected output: $out');
  return GitResult.ok(int.parse(match.group(1)!));
}

Future<GitResult<PullRequestSummary>> getMergeRequest(
  String repoPath,
  int number,
) async {
  final r = await _glab(repoPath, [
    'mr',
    'view',
    '$number',
    '-F',
    'json',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    return GitResult.ok(_mrSummaryFromGlab(j));
  } catch (e) {
    return GitResult.err('Failed to parse glab mr view: $e');
  }
}

Future<GitResult<PullRequestDetail>> mergeRequestDetail(
  String repoPath,
  int number, {
  bool includeDiff = true,
}) async {
  final viewFut = _glab(repoPath, ['mr', 'view', '$number', '-F', 'json']);
  final diffFut = includeDiff
      ? _glab(repoPath, ['mr', 'diff', '$number'])
      : Future<ProcessResult?>.value(null);
  final view = await viewFut;
  final diffRes = await diffFut;
  if (view.exitCode != 0) {
    return GitResult.err(view.stderr.toString().trim());
  }
  try {
    final j = jsonDecode(view.stdout.toString()) as Map<String, dynamic>;

    final changes = j['changes'] as List? ?? const [];
    final files = changes
        .whereType<Map<String, dynamic>>()
        .map((f) => PrFile(
              path: (f['new_path'] as String? ?? f['old_path'] as String? ?? '').trim(),
              additions: _countLines(f['diff'] as String? ?? '', '+'),
              deletions: _countLines(f['diff'] as String? ?? '', '-'),
            ))
        .toList();

    final notes = j['notes'] as List? ?? const [];
    final comments = notes
        .whereType<Map<String, dynamic>>()
        .where((n) => n['system'] != true)
        .map(_commentFromGlab)
        .toList()
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
      body: (j['description'] as String? ?? '').trim(),
      files: files,
      comments: comments,
      diff: rawDiff,
      diffByFile: byFile,
      rawDiffByFile: sliceDiffByFile(rawDiff),
    ));
  } catch (e) {
    return GitResult.err('Failed to parse glab mr view: $e');
  }
}

Future<GitResult<void>> submitMrReview(
  String repoPath,
  int number, {
  required String event,
  String body = '',
}) async {
  if (event == 'approve') {
    final r = await _glab(repoPath, ['mr', 'approve', '$number']);
    if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
    return const GitResult.ok(null);
  }
  // GitLab doesn't have request-changes as a review action —
  // post a comment instead.
  if (body.isNotEmpty) {
    return commentOnMr(repoPath, number, body);
  }
  return const GitResult.ok(null);
}

Future<GitResult<void>> mergeMr(
  String repoPath,
  int number, {
  required String method,
  bool deleteBranch = false,
}) async {
  final args = ['mr', 'merge', '$number'];
  if (method == 'squash') args.add('--squash');
  if (method == 'rebase') args.add('--rebase');
  if (deleteBranch) args.add('--remove-source-branch');
  // glab mr merge prompts by default; --yes suppresses.
  args.add('--yes');
  final r = await _glab(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> checkoutMr(String repoPath, int number) async {
  final r = await _glab(repoPath, ['mr', 'checkout', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> closeMr(String repoPath, int number) async {
  final r = await _glab(repoPath, ['mr', 'close', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> commentOnMr(
    String repoPath, int number, String body) async {
  if (body.trim().isEmpty) return const GitResult.ok(null);
  final r = await _glab(
      repoPath, ['mr', 'note', '$number', '--message', body]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<List<CheckSummary>>> listMrPipelines(
  String repoPath,
  int mrNumber,
) async {
  // Get the MR's source branch, then list CI jobs for that branch.
  final mrRes = await _glab(repoPath, ['mr', 'view', '$mrNumber', '-F', 'json']);
  if (mrRes.exitCode != 0) return GitResult.err(mrRes.stderr.toString().trim());
  try {
    final mrJson = jsonDecode(mrRes.stdout.toString()) as Map<String, dynamic>;
    final pipeline = mrJson['pipeline'] as Map<String, dynamic>?;
    if (pipeline == null) return GitResult.ok(const []);
    final pipelineId = pipeline['id'];
    if (pipelineId == null) {
      // Fallback: use the pipeline object itself as a single check.
      return GitResult.ok([_checkFromGlabJob(pipeline)]);
    }
    // List jobs for this specific pipeline.
    final jobsRes = await _glab(repoPath, [
      'ci', 'list', '--pipeline-id', '$pipelineId', '-F', 'json',
    ]);
    if (jobsRes.exitCode != 0) {
      // Fallback to pipeline-level status.
      return GitResult.ok([_checkFromGlabJob(pipeline)]);
    }
    final jobsList = jsonDecode(jobsRes.stdout.toString());
    if (jobsList is List && jobsList.isNotEmpty) {
      return GitResult.ok(jobsList
          .whereType<Map<String, dynamic>>()
          .map(_checkFromGlabJob)
          .toList());
    }
    return GitResult.ok([_checkFromGlabJob(pipeline)]);
  } catch (e) {
    return GitResult.err('Failed to parse pipeline: $e');
  }
}


// ---------------------------------------------------------------------------
// Issues
// ---------------------------------------------------------------------------

Future<GitResult<List<IssueSummary>>> listGlabIssues(
  String repoPath, {
  String state = 'opened',
  int limit = 100,
}) async {
  final r = await _glab(repoPath, [
    'issue',
    'list',
    '--state',
    state,
    '--per-page',
    '$limit',
    '-F',
    'json',
  ]);
  if (r.exitCode != 0) {
    return GitResult.err(r.stderr.toString().trim());
  }
  try {
    final parsed = jsonDecode(r.stdout.toString()) as List;
    final issues = parsed
        .whereType<Map<String, dynamic>>()
        .map(_issueSummaryFromGlab)
        .toList();
    return GitResult.ok(issues);
  } catch (e) {
    return GitResult.err('Failed to parse glab issue list: $e');
  }
}

Future<GitResult<IssueSummary>> getGlabIssue(
  String repoPath,
  int number,
) async {
  final r = await _glab(repoPath, [
    'issue',
    'view',
    '$number',
    '-F',
    'json',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    return GitResult.ok(_issueSummaryFromGlab(j));
  } catch (e) {
    return GitResult.err('Failed to parse glab issue view: $e');
  }
}

Future<GitResult<IssueDetail>> glabIssueDetail(
  String repoPath,
  int number,
) async {
  final r = await _glab(repoPath, [
    'issue',
    'view',
    '$number',
    '-F',
    'json',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    final notes = j['notes'] as List? ?? const [];
    final comments = notes
        .whereType<Map<String, dynamic>>()
        .where((n) => n['system'] != true)
        .map(_commentFromGlab)
        .toList();
    return GitResult.ok(IssueDetail(
      body: (j['description'] as String? ?? '').trim(),
      comments: comments,
      assignees: _glabAssigneeLogins(j['assignees']),
      labels: _glabLabels(j['labels']),
    ));
  } catch (e) {
    return GitResult.err('Failed to parse glab issue view: $e');
  }
}

Future<GitResult<int>> createGlabIssue(
  String repoPath, {
  required String title,
  String body = '',
  List<String> labels = const [],
  List<String> assignees = const [],
}) async {
  final args = ['issue', 'create', '--title', title, '--description', body];
  if (labels.isNotEmpty) args.addAll(['--label', labels.join(',')]);
  for (final a in assignees) {
    args.addAll(['--assignee', a]);
  }
  final r = await _glab(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final out = r.stdout.toString().trim();
  final match = RegExp(r'/issues/(\d+)').firstMatch(out);
  if (match == null) return GitResult.err('unexpected output: $out');
  return GitResult.ok(int.parse(match.group(1)!));
}

Future<GitResult<void>> editGlabIssue(
  String repoPath,
  int number, {
  String? title,
  String? body,
  List<String> addLabels = const [],
  List<String> removeLabels = const [],
}) async {
  final args = ['issue', 'update', '$number'];
  if (title != null) args.addAll(['--title', title]);
  if (body != null) args.addAll(['--description', body]);
  if (addLabels.isNotEmpty) args.addAll(['--label', addLabels.join(',')]);
  if (removeLabels.isNotEmpty) args.addAll(['--unlabel', removeLabels.join(',')]);
  if (args.length == 3) return const GitResult.ok(null);
  final r = await _glab(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> closeGlabIssue(String repoPath, int number) async {
  final r = await _glab(repoPath, ['issue', 'close', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> reopenGlabIssue(String repoPath, int number) async {
  final r = await _glab(repoPath, ['issue', 'reopen', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> commentOnGlabIssue(
    String repoPath, int number, String body) async {
  if (body.trim().isEmpty) return const GitResult.ok(null);
  final r = await _glab(
      repoPath, ['issue', 'note', '$number', '--message', body]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> assignSelfToGlabIssue(
    String repoPath, int number) async {
  final login = await glabWhoami();
  if (login.isEmpty) return GitResult.err('not authenticated with glab');
  final r = await _glab(
      repoPath, ['issue', 'update', '$number', '--assignee', login]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> addGlabIssueLabel(
    String repoPath, int number, String label) async {
  final r = await _glab(
      repoPath, ['issue', 'update', '$number', '--label', label]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}


// ---------------------------------------------------------------------------
// JSON → DTO mappers (normalize GitLab field names to shared shapes)
// ---------------------------------------------------------------------------

PullRequestSummary _mrSummaryFromGlab(Map<String, dynamic> j) {
  final author = j['author'] as Map<String, dynamic>?;
  final login = author?['username'] as String? ?? '';

  final reviewers = <String, PrReviewer>{};
  final reviewerList = j['reviewers'] as List? ?? const [];
  for (final r in reviewerList.whereType<Map<String, dynamic>>()) {
    final u = (r['username'] as String? ?? '').trim();
    if (u.isNotEmpty) reviewers[u] = PrReviewer(login: u, state: 'PENDING');
  }
  final approvedBy = j['approved_by'] as List? ?? const [];
  for (final a in approvedBy.whereType<Map<String, dynamic>>()) {
    final u = (a['username'] as String? ??
        (a['user'] as Map<String, dynamic>?)?['username'] as String? ?? '').trim();
    if (u.isNotEmpty) reviewers[u] = PrReviewer(login: u, state: 'APPROVED');
  }

  final glabState = (j['state'] as String? ?? 'opened').toLowerCase();
  final state = switch (glabState) {
    'opened' => 'OPEN',
    'closed' => 'CLOSED',
    'merged' => 'MERGED',
    _ => 'OPEN',
  };

  final mergeStatus = (j['merge_status'] as String? ?? '').toLowerCase();
  final mergeable = switch (mergeStatus) {
    'can_be_merged' => 'MERGEABLE',
    'cannot_be_merged' => 'CONFLICTING',
    _ => j['has_conflicts'] == true ? 'CONFLICTING' : 'UNKNOWN',
  };

  return PullRequestSummary(
    number: (j['iid'] as num? ?? 0).toInt(),
    title: (j['title'] as String? ?? '').trim(),
    headRef: (j['source_branch'] as String? ?? '').trim(),
    baseRef: (j['target_branch'] as String? ?? '').trim(),
    state: state,
    isDraft: j['draft'] as bool? ?? false,
    authorLogin: login,
    conversationCount: (j['user_notes_count'] as num? ?? 0).toInt(),
    updatedAt: _parseDate(j['updated_at']),
    additions: (j['additions'] as num? ?? 0).toInt(),
    deletions: (j['deletions'] as num? ?? 0).toInt(),
    changedFiles: (j['changes_count'] as num? ?? j['changed_files'] as num? ?? 0).toInt(),
    mergeable: mergeable,
    reviewDecision: j['approved'] == true ? 'APPROVED' : '',
    reviewers: reviewers.values.toList(),
    labels: _glabLabels(j['labels']),
    assignees: _glabAssigneeLogins(j['assignees']),
  );
}

IssueSummary _issueSummaryFromGlab(Map<String, dynamic> j) {
  final author = j['author'] as Map<String, dynamic>?;
  final login = author?['username'] as String? ?? '';
  final glabState = (j['state'] as String? ?? 'opened').toLowerCase();

  return IssueSummary(
    number: (j['iid'] as num? ?? 0).toInt(),
    title: (j['title'] as String? ?? '').trim(),
    state: glabState == 'opened' ? 'OPEN' : 'CLOSED',
    authorLogin: login,
    labels: _glabLabels(j['labels']),
    assignees: _glabAssigneeLogins(j['assignees']),
    commentCount: (j['user_notes_count'] as num? ?? 0).toInt(),
    updatedAt: _parseDate(j['updated_at']),
  );
}

RemoteComment _commentFromGlab(Map<String, dynamic> j) {
  final author = j['author'] as Map<String, dynamic>?;
  final login = author?['username'] as String? ?? '';
  return RemoteComment(
    authorLogin: login,
    body: (j['body'] as String? ?? '').trim(),
    createdAt: _parseDate(j['created_at']),
  );
}

CheckSummary _checkFromGlabJob(Map<String, dynamic> j) {
  final glabStatus = (j['status'] as String? ?? '').toLowerCase();
  final isCompleted = const {'success', 'failed', 'canceled', 'skipped'}
      .contains(glabStatus);
  final conclusion = switch (glabStatus) {
    'success' => 'success',
    'failed' => 'failure',
    'canceled' => 'cancelled',
    'skipped' => 'skipped',
    'manual' => 'action_required',
    _ => null,
  };
  final status = switch (glabStatus) {
    'running' => 'in_progress',
    'pending' || 'created' || 'waiting_for_resource' => 'queued',
    _ => isCompleted ? 'completed' : 'queued',
  };
  final dur = j['duration'] as num?;
  return CheckSummary(
    name: (j['name'] as String? ?? j['ref'] as String? ?? '').trim(),
    status: status,
    conclusion: conclusion,
    duration: dur != null ? Duration(seconds: dur.toInt()) : null,
  );
}


// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<String> _glabLabels(dynamic value) {
  if (value is! List) return const [];
  // GitLab returns labels as plain strings, not objects.
  return value.whereType<String>().where((s) => s.isNotEmpty).toList();
}

List<String> _glabAssigneeLogins(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((m) => (m['username'] as String? ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

DateTime _parseDate(dynamic value) {
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

int _countLines(String diff, String prefix) {
  var count = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith(prefix) && !line.startsWith('$prefix$prefix$prefix')) {
      count++;
    }
  }
  return count;
}

Future<ProcessResult> _glab(String repo, List<String> args) async {
  final commandLabel = 'glab.${args.isNotEmpty ? args.first : 'unknown'}';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: commandLabel,
  );
  try {
    final result = await Process.run(
      'glab',
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
