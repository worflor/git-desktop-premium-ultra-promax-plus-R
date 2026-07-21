// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// desk_pr.dart — "local PR" data model
//
// A worktree + metadata is a local PR. The metadata lives as an orphan
// commit history at refs/manifold/desks/<branch>; this file is just
// the in-memory shape and JSON marshalling for the latest state.
//
// Field shape mirrors PullRequestSummary / PullRequestDetail from
// gh.dart so the row renderer can adapt either form without a shared
// abstract class. See `toSummary()` and `toDetail(...)` for the
// adapters consumed by branches_page.dart.

import 'dart:convert';

import 'git.dart' as git;
import 'remote_types.dart';
import '../features/diff/diff_models.dart';

/// One entry in a desk PR's inline thread. Carries a plain comment
/// (verdict empty) or a review (verdict non-empty + body). Co-existing
/// in one list keeps the JSON simple; UI splits at render time.
class DeskThreadEntry {
  final String author;
  final String body;
  final DateTime at;

  /// '' (comment) | 'APPROVED' | 'CHANGES_REQUESTED' | 'COMMENTED'.
  final String verdict;

  const DeskThreadEntry({
    required this.author,
    required this.body,
    required this.at,
    this.verdict = '',
  });

  bool get isReview => verdict.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'author': author,
    'body': body,
    'at': at.toIso8601String(),
    'verdict': verdict,
  };

  factory DeskThreadEntry.fromJson(Map<String, dynamic> j) => DeskThreadEntry(
    author: (j['author'] as String? ?? ''),
    body: (j['body'] as String? ?? ''),
    at:
        DateTime.tryParse(j['at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    verdict: (j['verdict'] as String? ?? '').toUpperCase(),
  );

  /// Render as a `RemoteComment` so the existing comment-rendering code
  /// works unchanged. Reviews get a `[verdict]` prefix on the body.
  RemoteComment asComment() => RemoteComment(
    authorLogin: author,
    body: verdict.isEmpty ? body : '[${verdict.toLowerCase()}] $body',
    createdAt: at,
  );
}

const Object _sentinel = Object();

class DeskPr {
  /// Locally-allocated sequential ID. Plays the role of a remote PR
  /// number for adapter purposes.
  final int deskId;
  final String title;
  final String body;
  final String headRef;
  final String baseRef;

  /// 'OPEN' | 'CLOSED' | 'MERGED'.
  final String state;
  final bool isDraft;
  final String authorIdentity;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PrReviewer> reviewers;
  final List<String> labels;
  final List<String> assignees;
  final List<int> linkedIssues;

  /// Numbers of REMOTE issues this PR addresses. Mirrors
  /// [linkedIssues] for cross-system linking — when the user picks a
  /// remote issue from the unified link-picker, the id lands here so
  /// the row's "addresses #N" rendering reads from one PR-side list
  /// regardless of which kind of issue it points at.
  final List<int> linkedRemoteIssues;
  final List<DeskThreadEntry> thread;

  /// Diff metrics — computed from `git diff baseRef..headRef --numstat`
  /// at detail-load time and cached back into the in-memory shape so the
  /// row's metric line tells the truth before expansion. Persisted
  /// inside meta.json so the values are stable across restarts (and
  /// reconcilable with the actual diff via `git diff` on demand).
  final int additions;
  final int deletions;
  final int changedFiles;

  /// 'MERGEABLE' | 'CONFLICTING' | 'UNKNOWN'.
  final String mergeable;

  /// Remote PR/MR number this desk PR is linked to. Null = local-only.
  /// Non-null = bidirectionally synced with the forge.
  final int? remoteNumber;

  const DeskPr({
    required this.deskId,
    required this.title,
    required this.body,
    required this.headRef,
    required this.baseRef,
    required this.state,
    required this.isDraft,
    required this.authorIdentity,
    required this.createdAt,
    required this.updatedAt,
    this.reviewers = const [],
    this.labels = const [],
    this.assignees = const [],
    this.linkedIssues = const [],
    this.linkedRemoteIssues = const [],
    this.thread = const [],
    this.additions = 0,
    this.deletions = 0,
    this.changedFiles = 0,
    this.mergeable = 'UNKNOWN',
    this.remoteNumber,
  });

  /// Fold the thread into a single review decision using GitHub-style
  /// per-reviewer-latest semantics: each reviewer's *most recent* verdict
  /// is the only one that counts, so a stale CHANGES_REQUESTED no longer
  /// blocks forever once that same reviewer later APPROVED.
  ///
  /// Recency is the entry timestamp; when timestamps tie or are missing,
  /// later position in [thread] wins — the list is append-only, so its
  /// positional order is chronological truth.
  ///
  /// COMMENTED is the subtle case: it neither approves nor blocks and,
  /// matching GitHub, it does *not* dismiss a reviewer's prior standing
  /// decision. So only APPROVED / CHANGES_REQUESTED replace a reviewer's
  /// standing state; a later COMMENTED leaves it unchanged.
  ///
  /// Decision: any reviewer standing at CHANGES_REQUESTED wins; else any
  /// standing APPROVED; else none.
  String _deriveReviewDecision() {
    // Order entries by recency: timestamp first, original position as a
    // stable tiebreak when timestamps tie or are missing (the thread is
    // append-only, so position is chronological truth). Dart's sort isn't
    // guaranteed stable, so fold position into the comparator explicitly.
    final ordered = [for (var i = 0; i < thread.length; i++) (i, thread[i])]
      ..sort((a, b) {
        final byTime = a.$2.at.compareTo(b.$2.at);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });

    // author -> that reviewer's standing verdict ('APPROVED' |
    // 'CHANGES_REQUESTED'), only mutated by decisive verdicts. Walking in
    // recency order means the last decisive verdict we write for an author
    // is their latest.
    final standing = <String, String>{};
    for (final (_, e) in ordered) {
      if (e.verdict == 'APPROVED' || e.verdict == 'CHANGES_REQUESTED') {
        standing[e.author] = e.verdict;
      }
      // COMMENTED (and plain comments) intentionally leave standing state
      // untouched — they supersede nothing about the reviewer's decision,
      // matching GitHub: a later COMMENTED does not dismiss a prior
      // CHANGES_REQUESTED (or APPROVED) from that same reviewer.
    }

    if (standing.values.contains('CHANGES_REQUESTED')) {
      return 'CHANGES_REQUESTED';
    }
    if (standing.values.contains('APPROVED')) return 'APPROVED';
    return '';
  }

  /// Adapter — present this DeskPr as a PullRequestSummary so the
  /// existing branches-page row renderer treats it identically to a
  /// remote PR. Diff stats and mergeable status flow through directly,
  /// so the row's "+N -M, K files" metric and conflict strips read
  /// truthfully (the audit found these were lying as 0/UNKNOWN before).
  PullRequestSummary toSummary() => PullRequestSummary(
    number: deskId,
    title: title,
    headRef: headRef,
    baseRef: baseRef,
    state: state,
    isDraft: isDraft,
    authorLogin: authorIdentity,
    conversationCount: thread.length,
    updatedAt: updatedAt,
    additions: additions,
    deletions: deletions,
    changedFiles: changedFiles,
    mergeable: mergeable,
    reviewers: reviewers,
    labels: labels,
    assignees: assignees,
    reviewDecision: _deriveReviewDecision(),
  );

  /// Adapter for the expanded-row PullRequestDetail. Diff/files are
  /// supplied by the caller (computed on demand from
  /// `git diff baseRef..headRef`). The per-file raw slice is derived
  /// from the full [diff] so all three representations (full, parsed,
  /// sliced raw) stay consistent and the review UI can pick whichever
  /// it needs without re-slicing per rebuild.
  PullRequestDetail toDetail({
    required List<PrFile> files,
    required String diff,
    git.SpooledDiff? diffSpool,
    bool diffLoaded = false,
  }) => PullRequestDetail(
    body: body,
    files: files,
    comments: thread.map((e) => e.asComment()).toList(),
    diff: diff,
    rawDiffByFile: sliceDiffByFileForDetail(diff),
    diffSpool: diffSpool,
    diffLoaded: diffLoaded,
  );

  Map<String, dynamic> toJson() => {
    'deskId': deskId,
    'title': title,
    'body': body,
    'headRef': headRef,
    'baseRef': baseRef,
    'state': state,
    'isDraft': isDraft,
    'authorIdentity': authorIdentity,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'reviewers': reviewers
        .map((r) => {'login': r.login, 'state': r.state})
        .toList(),
    'labels': labels,
    'assignees': assignees,
    'linkedIssues': linkedIssues,
    'linkedRemoteIssues': linkedRemoteIssues,
    'thread': thread.map((e) => e.toJson()).toList(),
    'additions': additions,
    'deletions': deletions,
    'changedFiles': changedFiles,
    'mergeable': mergeable,
    if (remoteNumber != null) 'remoteNumber': remoteNumber,
  };

  factory DeskPr.fromJson(Map<String, dynamic> j) => DeskPr(
    deskId: (j['deskId'] as num? ?? 0).toInt(),
    title: (j['title'] as String? ?? '').trim(),
    body: (j['body'] as String? ?? ''),
    headRef: (j['headRef'] as String? ?? '').trim(),
    baseRef: (j['baseRef'] as String? ?? 'main').trim(),
    state: (j['state'] as String? ?? 'OPEN').toUpperCase(),
    isDraft: j['isDraft'] as bool? ?? false,
    authorIdentity: (j['authorIdentity'] as String? ?? '').trim(),
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    reviewers: (j['reviewers'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (r) => PrReviewer(
            login: (r['login'] as String? ?? ''),
            state: (r['state'] as String? ?? 'PENDING').toUpperCase(),
          ),
        )
        .toList(),
    labels: (j['labels'] as List? ?? const []).whereType<String>().toList(),
    assignees: (j['assignees'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    linkedIssues: (j['linkedIssues'] as List? ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList(),
    linkedRemoteIssues: (j['linkedRemoteIssues'] as List? ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList(),
    thread: (j['thread'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DeskThreadEntry.fromJson)
        .toList(),
    additions: (j['additions'] as num? ?? 0).toInt(),
    deletions: (j['deletions'] as num? ?? 0).toInt(),
    changedFiles: (j['changedFiles'] as num? ?? 0).toInt(),
    mergeable: (j['mergeable'] as String? ?? 'UNKNOWN').toUpperCase(),
    remoteNumber: (j['remoteNumber'] as num?)?.toInt(),
  );

  DeskPr copyWith({
    String? title,
    String? body,
    String? state,
    bool? isDraft,
    DateTime? updatedAt,
    List<PrReviewer>? reviewers,
    List<String>? labels,
    List<String>? assignees,
    List<int>? linkedIssues,
    List<int>? linkedRemoteIssues,
    List<DeskThreadEntry>? thread,
    int? additions,
    int? deletions,
    int? changedFiles,
    String? mergeable,
    Object? remoteNumber = _sentinel,
  }) => DeskPr(
    deskId: deskId,
    title: title ?? this.title,
    body: body ?? this.body,
    headRef: headRef,
    baseRef: baseRef,
    state: state ?? this.state,
    isDraft: isDraft ?? this.isDraft,
    authorIdentity: authorIdentity,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    reviewers: reviewers ?? this.reviewers,
    labels: labels ?? this.labels,
    assignees: assignees ?? this.assignees,
    linkedIssues: linkedIssues ?? this.linkedIssues,
    linkedRemoteIssues: linkedRemoteIssues ?? this.linkedRemoteIssues,
    thread: thread ?? this.thread,
    additions: additions ?? this.additions,
    deletions: deletions ?? this.deletions,
    changedFiles: changedFiles ?? this.changedFiles,
    mergeable: mergeable ?? this.mergeable,
    remoteNumber: remoteNumber == _sentinel
        ? this.remoteNumber
        : remoteNumber as int?,
  );

  /// Encode for `meta.json` blob with stable indentation so diffs
  /// across mutation commits read cleanly when inspected via
  /// `git log -p refs/manifold/desks/<branch>`.
  String toBlob() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory DeskPr.fromBlob(String blob) =>
      DeskPr.fromJson(jsonDecode(blob) as Map<String, dynamic>);
}
