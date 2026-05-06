// remote_types.dart — provider-neutral DTO types for remote forge sync
//
// These types describe the *shape* of issues, PRs, comments, checks,
// and reviews across any forge (GitHub, GitLab, Bitbucket, Gitea,
// Forgejo, sourcehut, …). No type here knows which forge it came
// from — that's the provider's job.
//
// History: these lived in gh.dart because GitHub was the first (and
// only) provider. They were never GitHub-specific in shape, only in
// address. Moving them here makes the intent explicit and lets new
// providers (glab, Bitbucket, Gitea) produce the same types without
// importing a file named after a competitor.
//
// The fromJson factories assume the field names that `gh` / `glab`
// emit. When a future provider uses different wire names, map them
// in that provider's implementation — keep these factories stable.

import 'dart:convert';
import 'dart:io';

import '../features/diff/diff_models.dart';

/// Single reviewer-state pair on a PR.
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
      conversationCount: parseCommentCount(j['comments']),
      updatedAt: parseRemoteDate(j['updatedAt']),
      additions: (j['additions'] as num? ?? 0).toInt(),
      deletions: (j['deletions'] as num? ?? 0).toInt(),
      changedFiles: (j['changedFiles'] as num? ?? 0).toInt(),
      mergeable: (j['mergeable'] as String? ?? 'UNKNOWN').toUpperCase(),
      reviewDecision:
          (j['reviewDecision'] as String? ?? '').toUpperCase(),
      reviewers: reviewers.values.toList(),
      labels: parseLabelStrings(j['labels']),
      assignees: parseAssigneeLogins(j['assignees']),
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
class RemoteComment {
  final String authorLogin;
  final String body;
  final DateTime createdAt;
  const RemoteComment({
    required this.authorLogin,
    required this.body,
    required this.createdAt,
  });
  factory RemoteComment.fromJson(Map<String, dynamic> j) {
    final author = j['author'];
    final login = author is Map<String, dynamic>
        ? (author['login'] as String? ?? '')
        : '';
    return RemoteComment(
      authorLogin: login,
      body: (j['body'] as String? ?? '').trim(),
      createdAt: parseRemoteDate(j['createdAt']),
    );
  }
}

class PullRequestDetail {
  final String body;
  final List<PrFile> files;
  final List<RemoteComment> comments;
  final String diff;
  final Map<String, List<ParsedLine>> diffByFile;
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
  final List<RemoteComment> comments;
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
      labels: parseLabelStrings(j['labels']),
      assignees: parseAssigneeLogins(j['assignees']),
      commentCount: parseCommentCount(j['comments']),
      updatedAt: parseRemoteDate(j['updatedAt']),
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
    final bucket = j['bucket'] as String?;
    final state = (j['state'] as String? ?? '').toLowerCase();
    final isCompleted = bucket != null && bucket != 'pending';
    return CheckSummary(
      name: (j['name'] as String? ?? '').trim(),
      status: isCompleted ? 'completed' : (state.isEmpty ? 'queued' : state),
      conclusion: bucket,
      duration: parseRemoteDuration(j['startedAt'], j['completedAt']),
    );
  }
}

/// Last-action event on a PR — drives the conversation tail glyph.
class TailEvent {
  /// 'comment' | 'review' | 'push' | 'check' | 'open'.
  final String kind;
  final String actor;
  final DateTime at;
  /// Optional sub-state (e.g. 'success'/'failure' for check).
  final String state;
  const TailEvent({
    required this.kind,
    required this.actor,
    required this.at,
    this.state = '',
  });
}

/// Status of a remote provider's CLI tooling and authentication.
class RemoteProviderStatus {
  final bool available;
  final String? reason;
  const RemoteProviderStatus({required this.available, this.reason});
  static const yes = RemoteProviderStatus(available: true);
}

// ---------------------------------------------------------------------------
// Forge detection — single-sourced so adding a new forge (Gitea,
// Bitbucket, Forgejo, …) requires one change here, not one per
// provider file.
// ---------------------------------------------------------------------------

enum RemoteForge { github, gitlab, unknown }

/// Resolve the forge hosting [repoPath] by reading `origin`.
/// Single `git remote get-url origin` spawn — cheap enough to run
/// per refresh without caching.
Future<RemoteForge> detectForge(String repoPath) async {
  try {
    final r = await Process.run(
      'git',
      ['remote', 'get-url', 'origin'],
      workingDirectory: repoPath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) return RemoteForge.unknown;
    return forgeFromUrl((r.stdout as String).trim());
  } catch (_) {
    return RemoteForge.unknown;
  }
}

/// Pure classification — no I/O.
RemoteForge forgeFromUrl(String url) {
  final host = hostOfRemote(url.toLowerCase());
  if (host.contains('github')) return RemoteForge.github;
  if (host.contains('gitlab')) return RemoteForge.gitlab;
  return RemoteForge.unknown;
}

/// Extract the hostname from a git remote URL.
/// Handles SSH (`git@host:path`) and HTTPS (`https://host/path`).
String hostOfRemote(String url) {
  final m = RegExp(r'(?:@|//)([^:/]+)').firstMatch(url);
  return m?.group(1) ?? url;
}

// ---------------------------------------------------------------------------
// Shared parse helpers — used by fromJson factories above and by
// provider implementations that produce these types.
// ---------------------------------------------------------------------------

DateTime parseRemoteDate(dynamic value) {
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

List<String> parseLabelStrings(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((m) => (m['name'] as String? ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

List<String> parseAssigneeLogins(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((m) => (m['login'] as String? ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

int parseCommentCount(dynamic value) {
  if (value is num) return value.toInt();
  if (value is List) return value.length;
  return 0;
}

Duration? parseRemoteDuration(dynamic startedAt, dynamic completedAt) {
  if (startedAt is! String || completedAt is! String) return null;
  final s = DateTime.tryParse(startedAt);
  final e = DateTime.tryParse(completedAt);
  if (s == null || e == null) return null;
  return e.difference(s);
}
