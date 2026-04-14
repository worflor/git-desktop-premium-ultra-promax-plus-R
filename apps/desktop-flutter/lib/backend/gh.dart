import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import 'git_result.dart';
import '../diagnostics/diagnostics_state.dart';
import '../features/diff/diff_models.dart';

/// Thin wrapper around the GitHub CLI (`gh`). Mirrors the patterns in
/// `git.dart`: shell out, parse JSON, wrap in [GitResult]. We rely on
/// `gh` rather than rolling our own GitHub API client because it
/// already solves auth, refresh, and rate-limit handling — every user
/// that has `gh auth login` finished gets PR/issue support for free.
///
/// Surfaces in the UI must handle the case where `gh` is missing or
/// unauthenticated: call [ghStatus] once on first lens activation and
/// branch the empty state on the result.

// ── DTOs ──────────────────────────────────────────────────────────────

/// Single reviewer-state pair on a PR. Aggregated from `reviewRequests`
/// (people who've been asked but haven't reviewed yet) and `reviews`
/// (people who have reviewed); the latter wins for any login present in
/// both — a person who reviewed is no longer "pending."
class PrReviewer {
  final String login;
  /// 'PENDING' | 'APPROVED' | 'CHANGES_REQUESTED' | 'COMMENTED' |
  /// 'DISMISSED'.
  final String state;
  const PrReviewer({required this.login, required this.state});
}

class PullRequestSummary {
  final int number;
  final String title;
  final String headRef;
  final String baseRef;
  /// 'OPEN' | 'CLOSED' | 'MERGED'.
  final String state;
  final bool isDraft;
  final String authorLogin;
  final int conversationCount;
  final DateTime updatedAt;
  final int additions;
  final int deletions;
  final int changedFiles;
  /// 'MERGEABLE' | 'CONFLICTING' | 'UNKNOWN'.
  final String mergeable;
  /// 'APPROVED' | 'CHANGES_REQUESTED' | 'REVIEW_REQUIRED' | empty.
  final String reviewDecision;
  final List<PrReviewer> reviewers;
  final List<String> labels;
  final List<String> assignees;

  const PullRequestSummary({
    required this.number,
    required this.title,
    required this.headRef,
    required this.baseRef,
    required this.state,
    required this.isDraft,
    required this.authorLogin,
    required this.conversationCount,
    required this.updatedAt,
    this.additions = 0,
    this.deletions = 0,
    this.changedFiles = 0,
    this.mergeable = 'UNKNOWN',
    this.reviewDecision = '',
    this.reviewers = const [],
    this.labels = const [],
    this.assignees = const [],
  });

  factory PullRequestSummary.fromJson(Map<String, dynamic> j) {
    final author = j['author'];
    final login = author is Map<String, dynamic>
        ? (author['login'] as String? ?? '')
        : '';

    // Merge reviewRequests (pending) with reviews (acted). Acted wins.
    final reviewers = <String, PrReviewer>{};
    final requests = j['reviewRequests'];
    if (requests is List) {
      for (final r in requests.whereType<Map<String, dynamic>>()) {
        final l = (r['login'] as String? ?? '').trim();
        if (l.isNotEmpty) reviewers[l] = PrReviewer(login: l, state: 'PENDING');
      }
    }
    final reviews = j['reviews'];
    if (reviews is List) {
      // Collapse multiple reviews per author down to the latest one.
      for (final r in reviews.whereType<Map<String, dynamic>>()) {
        final author = r['author'];
        final l = author is Map<String, dynamic>
            ? (author['login'] as String? ?? '').trim()
            : '';
        final st = (r['state'] as String? ?? '').toUpperCase();
        if (l.isNotEmpty && st.isNotEmpty) {
          reviewers[l] = PrReviewer(login: l, state: st);
        }
      }
    }

    return PullRequestSummary(
      number: (j['number'] as num).toInt(),
      title: (j['title'] as String? ?? '').trim(),
      headRef: (j['headRefName'] as String? ?? '').trim(),
      baseRef: (j['baseRefName'] as String? ?? '').trim(),
      state: (j['state'] as String? ?? 'OPEN').toUpperCase(),
      isDraft: j['isDraft'] as bool? ?? false,
      authorLogin: login,
      conversationCount: _commentCount(j['comments']),
      updatedAt: _parseDate(j['updatedAt']),
      additions: (j['additions'] as num? ?? 0).toInt(),
      deletions: (j['deletions'] as num? ?? 0).toInt(),
      changedFiles: (j['changedFiles'] as num? ?? 0).toInt(),
      mergeable: (j['mergeable'] as String? ?? 'UNKNOWN').toUpperCase(),
      reviewDecision:
          (j['reviewDecision'] as String? ?? '').toUpperCase(),
      reviewers: reviewers.values.toList(),
      labels: _labelStrings(j['labels']),
      assignees: _assigneeLogins(j['assignees']),
    );
  }
}

/// Single file in a PR's changed-files list.
class PrFile {
  final String path;
  final int additions;
  final int deletions;
  const PrFile({
    required this.path,
    required this.additions,
    required this.deletions,
  });
}

/// One comment on a PR or issue.
class GhComment {
  final String authorLogin;
  final String body;
  final DateTime createdAt;
  const GhComment({
    required this.authorLogin,
    required this.body,
    required this.createdAt,
  });
  factory GhComment.fromJson(Map<String, dynamic> j) {
    final author = j['author'];
    final login = author is Map<String, dynamic>
        ? (author['login'] as String? ?? '')
        : '';
    return GhComment(
      authorLogin: login,
      body: (j['body'] as String? ?? '').trim(),
      createdAt: _parseDate(j['createdAt']),
    );
  }
}

class PullRequestDetail {
  final String body;
  final List<PrFile> files;
  final List<GhComment> comments;
  /// Raw unified diff (full multi-file patch).
  final String diff;
  /// Pre-parsed [ParsedLine]s, sliced into per-file buckets at fetch
  /// time so the UI never re-parses a multi-hundred-KB diff on every
  /// rebuild. Key = file path (matches [PrFile.path]); value = the
  /// `ParsedLine`s that belong to that file in source order. Empty map
  /// if the diff is empty.
  ///
  /// Parsing once in the backend (when the future resolves) instead of
  /// per diff-render is the root-cause fix for the diff-view freeze:
  /// AnimatedSize tweens, prefetch progress notifications, and any
  /// sibling setState would otherwise trigger O(n) regex parsing of
  /// the full patch on the main thread per rebuild — easily 50–200 ms
  /// each, cumulating to multi-second freezes.
  final Map<String, List<ParsedLine>> diffByFile;
  /// Raw unified-diff text sliced per file, keyed identically to
  /// [diffByFile]. Lets the PR review surface hand a single file's diff
  /// straight to [DiffShell] (which accepts raw text) without having
  /// to re-slice or re-parse on every rebuild. Computed once at detail
  /// fetch alongside [diffByFile] via [sliceDiffByFile]. Empty map if
  /// [diff] is empty.
  final Map<String, String> rawDiffByFile;
  const PullRequestDetail({
    required this.body,
    required this.files,
    required this.comments,
    required this.diff,
    required this.diffByFile,
    required this.rawDiffByFile,
  });
}

class IssueDetail {
  final String body;
  final List<GhComment> comments;
  final List<String> assignees;
  final List<String> labels;
  const IssueDetail({
    required this.body,
    required this.comments,
    required this.assignees,
    required this.labels,
  });
}

class IssueSummary {
  final int number;
  final String title;
  /// 'OPEN' | 'CLOSED'.
  final String state;
  final String authorLogin;
  final List<String> labels;
  final List<String> assignees;
  final int commentCount;
  final DateTime updatedAt;

  const IssueSummary({
    required this.number,
    required this.title,
    required this.state,
    required this.authorLogin,
    required this.labels,
    required this.assignees,
    required this.commentCount,
    required this.updatedAt,
  });

  factory IssueSummary.fromJson(Map<String, dynamic> j) {
    final author = j['author'];
    final login = author is Map<String, dynamic>
        ? (author['login'] as String? ?? '')
        : '';
    return IssueSummary(
      number: (j['number'] as num).toInt(),
      title: (j['title'] as String? ?? '').trim(),
      state: (j['state'] as String? ?? 'OPEN').toUpperCase(),
      authorLogin: login,
      labels: _labelStrings(j['labels']),
      assignees: _assigneeLogins(j['assignees']),
      commentCount: _commentCount(j['comments']),
      updatedAt: _parseDate(j['updatedAt']),
    );
  }
}

class CheckSummary {
  final String name;
  /// 'queued' | 'in_progress' | 'completed' | empty.
  final String status;
  /// 'success' | 'failure' | 'neutral' | 'cancelled' | 'skipped' |
  /// 'timed_out' | 'action_required' | null while running.
  final String? conclusion;
  final Duration? duration;

  const CheckSummary({
    required this.name,
    required this.status,
    this.conclusion,
    this.duration,
  });

  factory CheckSummary.fromJson(Map<String, dynamic> j) {
    // `gh pr checks --json` reports `bucket` (success/fail/pending/cancel/skipping)
    // and a separate `state`. Bucket is the most useful single field: maps
    // cleanly to a one-glyph status indicator. Use it as the conclusion when
    // present; fall back to the raw `state`.
    final bucket = j['bucket'] as String?;
    final state = (j['state'] as String? ?? '').toLowerCase();
    final isCompleted = bucket != null && bucket != 'pending';
    return CheckSummary(
      name: (j['name'] as String? ?? '').trim(),
      status: isCompleted ? 'completed' : (state.isEmpty ? 'queued' : state),
      conclusion: bucket,
      duration: _parseDuration(j['startedAt'], j['completedAt']),
    );
  }
}

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

// ── Public API ────────────────────────────────────────────────────────

/// One-shot probe — is `gh` on PATH, and is the user logged in?
/// Cheap to call; cache the result on the lens-state side.
///
/// Both probes run in parallel because they're independent — the auth
/// check spawns even if version returns first, and we make the install
/// vs auth distinction from the two results. ~50ms saving in the
/// common case where both succeed.
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

/// One last-action event on a PR — drives the CONVERSATION TAIL
/// glyph. We synthesize this client-side from already-cached fields
/// (comments, reviews, checks, updatedAt) — no additional API call.
class TailEvent {
  /// One of: 'comment' | 'review' | 'push' | 'check' | 'open'.
  final String kind;
  /// Author of the action (login). Empty when not attributable
  /// (e.g. a check fail with no human owner).
  final String actor;
  final DateTime at;
  /// Optional sub-state (e.g. 'success'/'failure' for check, or
  /// 'approved'/'changes_requested' for review). Empty when n/a.
  final String state;
  const TailEvent({
    required this.kind,
    required this.actor,
    required this.at,
    this.state = '',
  });
}

/// Format a cached PR's diff as a `git format-patch`-style `.patch`
/// string with minimal RFC-822-ish headers so the resulting file
/// roundtrips through `git apply` cleanly AND reads as authored
/// (From / Subject / Date) when opened in any editor or email client.
/// Does NOT fetch — uses what's already cached.
String formatPrAsPatch(PullRequestSummary pr, PullRequestDetail detail) {
  final author = pr.authorLogin.isNotEmpty ? pr.authorLogin : 'unknown';
  final dateStr = pr.updatedAt.toUtc().toIso8601String();
  final body = detail.body.trim();
  return [
    'From: $author <$author@users.noreply.github.com>',
    'Date: $dateStr',
    'Subject: [PATCH] ${pr.title}',
    '',
    if (body.isNotEmpty) ...[body, ''],
    '---',
    '',
    detail.diff,
  ].join('\n');
}

/// Re-fetch a single PR's summary fields (the same shape returned by
/// [listPullRequests]). Used after an action so we can patch the
/// affected PR in place rather than re-running the full list — saves
/// ~50× on action latency for repos with many open PRs.
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

/// Logged-in user's GitHub login. Cheap; cache on the UI side. Returns
/// empty string when gh isn't authed (caller already handles that via
/// [ghStatus]).
Future<String> whoami() async {
  try {
    final r = await Process.run(
      'gh',
      ['api', 'user', '--jq', '.login'],
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) return '';
    return r.stdout.toString().trim();
  } catch (_) {
    return '';
  }
}

/// Two flavours: full ([includeDiff]=true) fires `gh pr view` + `gh pr
/// diff` in parallel; metadata-only ([includeDiff]=false) skips the
/// diff fetch + parse entirely. Prefetch uses the metadata-only path
/// to warm caches cheaply; user-clicked expand triggers a full fetch.
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
    // `reviews` carries each reviewer's submission body — the actual
    // text they wrote when approving / requesting changes / commenting.
    // Without it the REVIEWERS section shows only their state and the
    // user never sees what was actually said.
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
    // Issue comments (top-level PR conversation).
    final comments = (j['comments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GhComment.fromJson)
        .toList();
    // Review submissions: each review can have a body (the reviewer's
    // overall message when approving / requesting changes / commenting).
    // Bodies-only reviews look like a regular comment to the reader; we
    // prefix them with their state token so the conversation reads as
    // "@user [requested changes] this looks risky because…" instead of
    // detaching the message from the action it accompanied.
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
          return GhComment(
            authorLogin: login,
            body: tag.isEmpty ? body : '$tag\n\n$body',
            createdAt: _parseDate(r['submittedAt']),
          );
        })
        .whereType<GhComment>()
        .toList();
    // Merge + sort by createdAt so the conversation reads chronologically
    // — interleaving "asked a question", "approved", "replied", etc.
    final mergedComments = [...comments, ...reviews]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // `gh pr diff` writes the patch to stdout AND can exit non-zero on
    // perfectly fine PRs (warnings on stderr, color-tty heuristics,
    // etc.). Trust whatever stdout we got — empty stdout is the only
    // honest "no diff" signal.
    final rawDiff = diffRes?.stdout.toString() ?? '';
    // Parse off the main isolate for non-trivial diffs. parseUnifiedDiff
    // is regex+allocation heavy; on a real PR (50KB-MB+) a synchronous
    // call from this resolved future blocks the UI thread for hundreds
    // of ms — easily seconds when the prefetch fires several details
    // concurrently. compute() spawns a worker isolate so the UI keeps
    // painting. Below ~32KB the isolate hop costs more than the parse
    // it avoids, so do it inline.
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
          .map(GhComment.fromJson)
          .toList(),
      assignees: _assigneeLogins(j['assignees']),
      labels: _labelStrings(j['labels']),
    ));
  } catch (e) {
    return GitResult.err('Failed to parse gh issue view: $e');
  }
}

/// 'approve' | 'request-changes' | 'comment'.
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
  // gh pr review --request-changes / --comment require a body. For
  // approve we still pass an empty `--body` to satisfy the CLI's
  // expectation of explicit input.
  final args = ['pr', 'review', '$number', flag, '--body', body];
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// 'merge' | 'squash' | 'rebase'.
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

/// Run `gh pr checkout <number>` — switches the working copy onto the
/// PR's branch (creating a tracking branch if needed).
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

/// Works for both PRs and issues — gh treats them as the same numeric
/// space under the hood for assign/label/close/comment.
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
  // `gh pr checks` exits non-zero when ANY check has failed even though it
  // still emits valid JSON. Treat parsable stdout as success regardless of
  // exit code, otherwise we'd lose the data we came for.
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

// ── Internal ──────────────────────────────────────────────────────────

Future<ProcessResult> _gh(String repo, List<String> args) async {
  final commandLabel = 'gh.${args.isNotEmpty ? args.first : 'unknown'}';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: commandLabel,
  );
  try {
    // stdoutEncoding: utf8 — `gh` always emits UTF-8 (JSON spec
    // requires it; emojis, accented names, CJK identifiers all come
    // through). Without this Process.run defaults to the host's
    // system codepage (Windows-1252 on most en-US Windows installs)
    // and every multibyte sequence renders as mojibake — `💡` becomes
    // `ðŸ’¡`, which is exactly what the comment-rendering bug looked
    // like. stderr too in case `gh` writes a non-ASCII error.
    final result = await Process.run(
      'gh',
      args,
      workingDirectory: repo,
      runInShell: true,
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

DateTime _parseDate(dynamic value) {
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

List<String> _labelStrings(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((m) => (m['name'] as String? ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

List<String> _assigneeLogins(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((m) => (m['login'] as String? ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

int _commentCount(dynamic value) {
  // `gh` returns comments either as a count (when only the count was
  // requested) or as an array of comment objects (when full bodies were
  // requested). Handle both shapes so callers don't have to.
  if (value is num) return value.toInt();
  if (value is List) return value.length;
  return 0;
}

Duration? _parseDuration(dynamic startedAt, dynamic completedAt) {
  if (startedAt is! String || completedAt is! String) return null;
  final s = DateTime.tryParse(startedAt);
  final e = DateTime.tryParse(completedAt);
  if (s == null || e == null) return null;
  return e.difference(s);
}
