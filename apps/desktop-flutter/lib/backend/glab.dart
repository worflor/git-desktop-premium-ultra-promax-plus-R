import 'dart:convert';
import 'dart:io';

import 'gh.dart' show runForgeCli, spoolForgeCliStdout, resolveDetailDiffSpool;
import 'git.dart' as git;
import 'git_result.dart';
import 'remote_types.dart';
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
      Process.run(
        'glab',
        ['--version'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ),
      Process.run(
        'glab',
        ['auth', 'status'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ),
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
        .map(mrSummaryFromGlab)
        // Drop rows with no usable iid rather than fabricate an MR #0.
        .whereType<PullRequestSummary>()
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
  final args = [
    'mr',
    'create',
    '--title',
    title,
    '--description',
    body,
    '--source-branch',
    headRef,
    '--target-branch',
    baseRef,
    '--yes',
  ];
  if (draft) args.add('--draft');
  if (labels.isNotEmpty) args.addAll(['--label', labels.join(',')]);
  for (final a in assignees) {
    args.addAll(['--assignee', a]);
  }
  for (final r in reviewers) {
    args.addAll(['--reviewer', r]);
  }
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
  final r = await _glab(repoPath, ['mr', 'view', '$number', '-F', 'json']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    final mr = mrSummaryFromGlab(j);
    if (mr == null) {
      return const GitResult.err(
        'glab mr view returned a row with no usable iid',
      );
    }
    return GitResult.ok(mr);
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
      // The diff STREAMS to a spool during transport (see gh.dart's
      // spoolForgeCliStdout): the patch never fully materializes in memory.
      ? spoolForgeCliStdout('glab', repoPath, ['mr', 'diff', '$number'])
      : Future<GitResult<git.SpooledDiff>?>.value(null);
  final view = await viewFut;
  final diffRes = await diffFut;
  if (view.exitCode != 0) {
    await diffRes?.data?.dispose(); // don't leak the parallel fetch's spool
    return GitResult.err(view.stderr.toString().trim());
  }
  // Same contract as gh.dart: a requested-but-failed patch fetch is an
  // error, never a silently empty diff.
  if (diffRes != null && !diffRes.ok) {
    final err = (diffRes.error ?? '').trim();
    return GitResult.err(err.isEmpty ? 'glab mr diff failed' : err);
  }
  try {
    final j = jsonDecode(view.stdout.toString()) as Map<String, dynamic>;

    final changes = j['changes'] as List? ?? const [];
    final files = changes
        .whereType<Map<String, dynamic>>()
        .map(
          (f) => PrFile(
            path: (f['new_path'] as String? ?? f['old_path'] as String? ?? '')
                .trim(),
            additions: countGlabDiffLines(f['diff'] as String? ?? '', '+'),
            deletions: countGlabDiffLines(f['diff'] as String? ?? '', '-'),
          ),
        )
        .toList();

    final notes = j['notes'] as List? ?? const [];
    final comments =
        notes
            .whereType<Map<String, dynamic>>()
            .where((n) => n['system'] != true)
            .map(commentFromGlab)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // No eager ParsedLine parse (the `diffByFile` field it fed was never read
    // and a large PR would OOM); the diff renders lazily downstream. Small
    // spools materialize into the String form; large ones stay on disk.
    final resolved = diffRes?.data == null
        ? (rawDiff: '', spill: null as git.SpooledDiff?)
        : await resolveDetailDiffSpool(diffRes!.data!);
    return GitResult.ok(
      PullRequestDetail(
        body: (j['description'] as String? ?? '').trim(),
        files: files,
        comments: comments,
        diff: resolved.rawDiff,
        rawDiffByFile: resolved.spill == null
            ? sliceDiffByFileForDetail(resolved.rawDiff)
            : const {},
        diffSpool: resolved.spill,
        diffLoaded: includeDiff,
      ),
    );
  } catch (e) {
    // Parse failure after a successful diff fetch: release the spool the
    // detail object never got to own.
    await diffRes?.data?.dispose();
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
  String repoPath,
  int number,
  String body,
) async {
  if (body.trim().isEmpty) return const GitResult.ok(null);
  final r = await _glab(repoPath, ['mr', 'note', '$number', '--message', body]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<List<CheckSummary>>> listMrPipelines(
  String repoPath,
  int mrNumber,
) async {
  // Get the MR's source branch, then list CI jobs for that branch.
  final mrRes = await _glab(repoPath, [
    'mr',
    'view',
    '$mrNumber',
    '-F',
    'json',
  ]);
  if (mrRes.exitCode != 0) return GitResult.err(mrRes.stderr.toString().trim());
  try {
    final mrJson = jsonDecode(mrRes.stdout.toString()) as Map<String, dynamic>;
    final pipeline = mrJson['pipeline'] as Map<String, dynamic>?;
    if (pipeline == null) return const GitResult.ok([]);
    final pipelineId = pipeline['id'];
    if (pipelineId == null) {
      // Fallback: use the pipeline object itself as a single check.
      return GitResult.ok([checkFromGlabJob(pipeline)]);
    }
    // List jobs for this specific pipeline.
    final jobsRes = await _glab(repoPath, [
      'ci',
      'list',
      '--pipeline-id',
      '$pipelineId',
      '-F',
      'json',
    ]);
    if (jobsRes.exitCode != 0) {
      // Fallback to pipeline-level status.
      return GitResult.ok([checkFromGlabJob(pipeline)]);
    }
    final jobsList = jsonDecode(jobsRes.stdout.toString());
    if (jobsList is List && jobsList.isNotEmpty) {
      return GitResult.ok(
        jobsList
            .whereType<Map<String, dynamic>>()
            .map(checkFromGlabJob)
            .toList(),
      );
    }
    return GitResult.ok([checkFromGlabJob(pipeline)]);
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
        .map(issueSummaryFromGlab)
        // Drop rows with no usable iid rather than fabricate an issue #0.
        .whereType<IssueSummary>()
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
  final r = await _glab(repoPath, ['issue', 'view', '$number', '-F', 'json']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    final issue = issueSummaryFromGlab(j);
    if (issue == null) {
      return const GitResult.err(
        'glab issue view returned a row with no usable iid',
      );
    }
    return GitResult.ok(issue);
  } catch (e) {
    return GitResult.err('Failed to parse glab issue view: $e');
  }
}

Future<GitResult<IssueDetail>> glabIssueDetail(
  String repoPath,
  int number,
) async {
  final r = await _glab(repoPath, ['issue', 'view', '$number', '-F', 'json']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    final notes = j['notes'] as List? ?? const [];
    final comments = notes
        .whereType<Map<String, dynamic>>()
        .where((n) => n['system'] != true)
        .map(commentFromGlab)
        .toList();
    return GitResult.ok(
      IssueDetail(
        body: (j['description'] as String? ?? '').trim(),
        comments: comments,
        assignees: glabAssigneeLogins(j['assignees']),
        labels: glabLabels(j['labels']),
      ),
    );
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
  if (removeLabels.isNotEmpty) {
    args.addAll(['--unlabel', removeLabels.join(',')]);
  }
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
  String repoPath,
  int number,
  String body,
) async {
  if (body.trim().isEmpty) return const GitResult.ok(null);
  final r = await _glab(repoPath, [
    'issue',
    'note',
    '$number',
    '--message',
    body,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> assignSelfToGlabIssue(
  String repoPath,
  int number,
) async {
  final login = await glabWhoami();
  if (login.isEmpty) return const GitResult.err('not authenticated with glab');
  final r = await _glab(repoPath, [
    'issue',
    'update',
    '$number',
    '--assignee',
    login,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> addGlabIssueLabel(
  String repoPath,
  int number,
  String label,
) async {
  final r = await _glab(repoPath, [
    'issue',
    'update',
    '$number',
    '--label',
    label,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

// ---------------------------------------------------------------------------
// JSON → DTO mappers (normalize GitLab field names to shared shapes)
// ---------------------------------------------------------------------------

/// Maps one glab MR row, or `null` if it has no usable identity. The MR
/// `iid` is strict identity — it keys detail loads, checkout, and actions —
/// so an unreadable one rejects the row rather than fabricate an actionable
/// MR #0 (mirrors [PullRequestSummary.fromJson]'s strict-number rule).
PullRequestSummary? mrSummaryFromGlab(Map<String, dynamic> j) {
  final number = glabIntOrNull(j['iid']);
  if (number == null) return null;
  final authorRaw = j['author'];
  final login = authorRaw is Map<String, dynamic>
      ? (authorRaw['username'] as String? ?? '')
      : '';

  final reviewers = <String, PrReviewer>{};
  final reviewerList = j['reviewers'];
  if (reviewerList is List) {
    for (final r in reviewerList.whereType<Map<String, dynamic>>()) {
      final u = (r['username'] as String? ?? '').trim();
      if (u.isNotEmpty) reviewers[u] = PrReviewer(login: u, state: 'PENDING');
    }
  }
  final approvedBy = j['approved_by'];
  if (approvedBy is List) {
    for (final a in approvedBy.whereType<Map<String, dynamic>>()) {
      final nestedUser = a['user'];
      final u =
          (a['username'] as String? ??
                  (nestedUser is Map<String, dynamic>
                      ? nestedUser['username'] as String?
                      : null) ??
                  '')
              .trim();
      if (u.isNotEmpty) reviewers[u] = PrReviewer(login: u, state: 'APPROVED');
    }
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
    number: number,
    title: (j['title'] as String? ?? '').trim(),
    headRef: (j['source_branch'] as String? ?? '').trim(),
    baseRef: (j['target_branch'] as String? ?? '').trim(),
    state: state,
    isDraft: j['draft'] as bool? ?? false,
    authorLogin: login,
    conversationCount: glabIntOrNull(j['user_notes_count']) ?? 0,
    updatedAt: parseGlabDate(j['updated_at']),
    additions: glabIntOrNull(j['additions']) ?? 0,
    deletions: glabIntOrNull(j['deletions']) ?? 0,
    changedFiles:
        glabChangesCount(j['changes_count']) ??
        glabChangesCount(j['changed_files']) ??
        0,
    mergeable: mergeable,
    reviewDecision: j['approved'] == true ? 'APPROVED' : '',
    reviewers: reviewers.values.toList(),
    labels: glabLabels(j['labels']),
    assignees: glabAssigneeLogins(j['assignees']),
  );
}

/// GitLab's `changes_count` field on a merge request is documented as a
/// STRING (e.g. `"3"`), not a number, and can be the sentinel `"1000+"`
/// for very large diffs. A naive `as num?` cast throws a [TypeError] on
/// either real shape instead of falling through a `??` default (the cast
/// only yields null when the *source* is null), which used to fail every
/// merge request row's parse the moment GitLab populated this field.
/// Accepts num, digit strings, and the `"N+"` sentinel (parsed as N);
/// anything else yields null so the caller can fall back further.
///
/// Kept as a named alias of [glabIntOrNull] — `changes_count` is where this
/// bug class was first caught, so the name stays put as a landmark, but the
/// parsing itself now lives in the shared helper every numeric field uses.
int? glabChangesCount(Object? value) => glabIntOrNull(value);

/// Shared safe-int parser for every numeric field glab.dart reads off
/// GitLab's JSON. A plain `(j['x'] as num? ?? 0).toInt()` / bare `as num?`
/// cast is only *null*-safe, not *type*-safe: it throws an uncaught
/// [TypeError] the instant the field is present with any non-num,
/// non-null runtime type, because a cast only falls through `??` when the
/// source itself is null, never when it's merely the wrong type. GitLab is
/// documented to send at least one numeric-looking field (`changes_count`)
/// as a string; every numeric field in this file now degrades the same
/// defensive way instead of trusting each one's runtime shape.
///
/// Accepts a [num] directly, a digit string (`"12"`), or the `"N+"`
/// sentinel GitLab uses for very large diffs (`"1000+"` -> `1000`).
/// Anything else (bool, Map, List, unparseable String, null) yields null
/// so the caller can fall back via `??`.
int? glabIntOrNull(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) {
    final direct = int.tryParse(value);
    if (direct != null) return direct;
    final m = RegExp(r'^(\d+)\+?$').firstMatch(value.trim());
    if (m != null) return int.tryParse(m.group(1)!);
  }
  return null;
}

/// Maps one glab issue row, or `null` if it has no usable identity — see
/// [mrSummaryFromGlab]. Strict `iid`; display fields degrade softly.
IssueSummary? issueSummaryFromGlab(Map<String, dynamic> j) {
  final number = glabIntOrNull(j['iid']);
  if (number == null) return null;
  final authorRaw = j['author'];
  final login = authorRaw is Map<String, dynamic>
      ? (authorRaw['username'] as String? ?? '')
      : '';
  final glabState = (j['state'] as String? ?? 'opened').toLowerCase();

  return IssueSummary(
    number: number,
    title: (j['title'] as String? ?? '').trim(),
    state: glabState == 'opened' ? 'OPEN' : 'CLOSED',
    authorLogin: login,
    labels: glabLabels(j['labels']),
    assignees: glabAssigneeLogins(j['assignees']),
    commentCount: glabIntOrNull(j['user_notes_count']) ?? 0,
    updatedAt: parseGlabDate(j['updated_at']),
  );
}

RemoteComment commentFromGlab(Map<String, dynamic> j) {
  final authorRaw = j['author'];
  final login = authorRaw is Map<String, dynamic>
      ? (authorRaw['username'] as String? ?? '')
      : '';
  return RemoteComment(
    authorLogin: login,
    body: (j['body'] as String? ?? '').trim(),
    createdAt: parseGlabDate(j['created_at']),
  );
}

CheckSummary checkFromGlabJob(Map<String, dynamic> j) {
  final glabStatus = (j['status'] as String? ?? '').toLowerCase();
  final isCompleted = const {
    'success',
    'failed',
    'canceled',
    'skipped',
  }.contains(glabStatus);
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
  final durSec = glabIntOrNull(j['duration']);
  return CheckSummary(
    name: (j['name'] as String? ?? j['ref'] as String? ?? '').trim(),
    status: status,
    conclusion: conclusion,
    duration: durSec != null ? Duration(seconds: durSec) : null,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<String> glabLabels(dynamic value) {
  if (value is! List) return const [];
  // GitLab returns labels as plain strings, not objects.
  return value.whereType<String>().where((s) => s.isNotEmpty).toList();
}

List<String> glabAssigneeLogins(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((m) => (m['username'] as String? ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

DateTime parseGlabDate(dynamic value) {
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

int countGlabDiffLines(String diff, String prefix) {
  var count = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith(prefix) && !line.startsWith('$prefix$prefix$prefix')) {
      count++;
    }
  }
  return count;
}

Future<ProcessResult> _glab(String repo, List<String> args) =>
    runForgeCli('glab', repo, args);
