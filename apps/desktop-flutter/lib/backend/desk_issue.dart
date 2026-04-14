// ═════════════════════════════════════════════════════════════════════════
// desk_issue.dart — "local issue" data model
//
// Mirrors the local-PR pattern: an issue is metadata stored as an
// orphan commit history at refs/manifold/issues/<id>. Each commit is
// one mutation (create, comment, state change). The latest tree's
// issue.json blob holds the current state.
//
// Shape mirrors IssueSummary / IssueDetail from gh.dart so the same
// renderer adapts both. Cross-references with desk PRs are stored
// symmetrically: an issue's `addressedBy: [branch, ...]` matches a
// desk PR's `linkedIssues: [issueId, ...]`.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'gh.dart' show IssueSummary, IssueDetail, GhComment;

/// One comment on a local issue. Same shape as DeskThreadEntry minus
/// the verdict (issues don't have reviews).
class DeskIssueComment {
  final String author;
  final String body;
  final DateTime at;

  const DeskIssueComment({
    required this.author,
    required this.body,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'author': author,
        'body': body,
        'at': at.toIso8601String(),
      };

  factory DeskIssueComment.fromJson(Map<String, dynamic> j) =>
      DeskIssueComment(
        author: (j['author'] as String? ?? ''),
        body: (j['body'] as String? ?? ''),
        at: DateTime.tryParse(j['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  GhComment asComment() => GhComment(
        authorLogin: author,
        body: body,
        createdAt: at,
      );
}

class DeskIssue {
  /// Locally-allocated sequential ID. Plays the role of GitHub's
  /// issue number for adapter purposes.
  final int issueId;
  final String title;
  final String body;
  /// 'OPEN' | 'CLOSED'.
  final String state;
  final String authorIdentity;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> labels;
  final List<String> assignees;
  /// Branches of desk PRs that address this issue. Symmetric with
  /// `DeskPr.linkedIssues: [issueId, ...]`.
  final List<String> addressedBy;
  final List<DeskIssueComment> comments;

  const DeskIssue({
    required this.issueId,
    required this.title,
    required this.body,
    required this.state,
    required this.authorIdentity,
    required this.createdAt,
    required this.updatedAt,
    this.labels = const [],
    this.assignees = const [],
    this.addressedBy = const [],
    this.comments = const [],
  });

  /// Adapter — present this DeskIssue as an IssueSummary so the
  /// existing branches-page issue-row renderer treats it identically
  /// to a remote issue.
  IssueSummary toSummary() => IssueSummary(
        number: issueId,
        title: title,
        state: state,
        authorLogin: authorIdentity,
        labels: labels,
        assignees: assignees,
        commentCount: comments.length,
        updatedAt: updatedAt,
      );

  /// Adapter for the expanded-row IssueDetail.
  IssueDetail toDetail() => IssueDetail(
        body: body,
        comments: comments.map((c) => c.asComment()).toList(),
        assignees: assignees,
        labels: labels,
      );

  Map<String, dynamic> toJson() => {
        'issueId': issueId,
        'title': title,
        'body': body,
        'state': state,
        'authorIdentity': authorIdentity,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'labels': labels,
        'assignees': assignees,
        'addressedBy': addressedBy,
        'comments': comments.map((c) => c.toJson()).toList(),
      };

  factory DeskIssue.fromJson(Map<String, dynamic> j) => DeskIssue(
        issueId: (j['issueId'] as num? ?? 0).toInt(),
        title: (j['title'] as String? ?? '').trim(),
        body: (j['body'] as String? ?? ''),
        state: (j['state'] as String? ?? 'OPEN').toUpperCase(),
        authorIdentity: (j['authorIdentity'] as String? ?? '').trim(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        labels: (j['labels'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        assignees: (j['assignees'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        addressedBy: (j['addressedBy'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        comments: (j['comments'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DeskIssueComment.fromJson)
            .toList(),
      );

  DeskIssue copyWith({
    String? title,
    String? body,
    String? state,
    DateTime? updatedAt,
    List<String>? labels,
    List<String>? assignees,
    List<String>? addressedBy,
    List<DeskIssueComment>? comments,
  }) =>
      DeskIssue(
        issueId: issueId,
        title: title ?? this.title,
        body: body ?? this.body,
        state: state ?? this.state,
        authorIdentity: authorIdentity,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        labels: labels ?? this.labels,
        assignees: assignees ?? this.assignees,
        addressedBy: addressedBy ?? this.addressedBy,
        comments: comments ?? this.comments,
      );

  String toBlob() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory DeskIssue.fromBlob(String blob) =>
      DeskIssue.fromJson(jsonDecode(blob) as Map<String, dynamic>);
}
