import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import 'git_result.dart';
import 'remote_types.dart';
import '../diagnostics/diagnostics_state.dart';
import '../features/diff/diff_models.dart';

String _sanitizeBody(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map<String, dynamic>) {
      final msg = j['message'] ?? j['error'] ?? j['errors'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg != null) return msg.toString();
    }
  } catch (_) {}
  final trimmed = body.trim();
  if (trimmed.length > 120) return '${trimmed.substring(0, 120)}…';
  return trimmed.isEmpty ? 'unknown error' : trimmed;
}

/// REST API client for Gitea / Forgejo / Codeberg instances.
/// No CLI dependency — talks HTTP directly to the forge's `/api/v1/` surface.

String? resolveGiteaToken(String apiBase) {
  final env = Platform.environment['GITEA_TOKEN'];
  if (env != null && env.isNotEmpty) return env;
  return null;
}

class GiteaApiStatus {
  final bool reachable;
  final bool authenticated;
  final String? version;
  final String? reason;

  const GiteaApiStatus({
    required this.reachable,
    required this.authenticated,
    this.version,
    this.reason,
  });

  bool get usable => reachable;
}

/// Probe the Gitea/Forgejo instance at [baseUrl].
Future<GiteaApiStatus> giteaApiStatus(String baseUrl, {String? token}) async {
  try {
    final r = await giteaGet(baseUrl, '/version', token: token);
    if (r.statusCode != 200) {
      return GiteaApiStatus(
        reachable: false,
        authenticated: false,
        reason: 'API returned ${r.statusCode}',
      );
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final ver = j['version'] as String? ?? '';
    final authed = token != null && token.isNotEmpty;
    return GiteaApiStatus(
      reachable: true,
      authenticated: authed,
      version: ver,
    );
  } catch (e) {
    return GiteaApiStatus(
      reachable: false,
      authenticated: false,
      reason: e.toString(),
    );
  }
}

/// Resolve the API base URL and owner/repo from a repo path's `origin` remote.
Future<GiteaRepoCoords?> resolveGiteaCoords(String repoPath) async {
  try {
    final r = await Process.run(
      'git',
      ['remote', 'get-url', 'origin'],
      workingDirectory: repoPath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) return null;
    final url = (r.stdout as String).trim();
    return GiteaRepoCoords.parse(url);
  } catch (_) {
    return null;
  }
}

class GiteaRepoCoords {
  final String apiBase;
  final String owner;
  final String repo;
  const GiteaRepoCoords({
    required this.apiBase,
    required this.owner,
    required this.repo,
  });

  static GiteaRepoCoords? parse(String remoteUrl) {
    final host = hostOfRemote(remoteUrl.toLowerCase());
    if (host.isEmpty) return null;

    String? path;
    final trimmed = remoteUrl.trim();
    if (trimmed.startsWith('https://') || trimmed.startsWith('http://')) {
      try {
        final uri = Uri.parse(trimmed);
        path = uri.path;
      } catch (_) {
        return null;
      }
    } else {
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx < 0) return null;
      path = '/${trimmed.substring(colonIdx + 1)}';
    }
    if (path == null) return null;
    if (path.endsWith('.git')) path = path.substring(0, path.length - 4);
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final realHost = hostOfRemote(trimmed);
    const scheme = 'https';
    return GiteaRepoCoords(
      apiBase: '$scheme://$realHost/api/v1',
      owner: segments[segments.length - 2],
      repo: segments[segments.length - 1],
    );
  }

  String get repoPath => 'repos/$owner/$repo';
}


// ---------------------------------------------------------------------------
// Pull Requests
// ---------------------------------------------------------------------------

Future<GitResult<List<PullRequestSummary>>> listGiteaPulls(
  String repoPath, {
  String state = 'open',
  int limit = 50,
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final all = <PullRequestSummary>[];
  var page = 1;
  const perPage = 50;
  while (all.length < limit) {
    final r = await giteaGet(
      coords.apiBase,
      '/${coords.repoPath}/pulls?state=${Uri.encodeComponent(state)}&limit=$perPage&page=$page',
      token: token,
    );
    if (r.statusCode != 200) {
      return all.isEmpty
          ? GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}')
          : GitResult.ok(all);
    }
    try {
      final parsed = jsonDecode(r.body) as List;
      final batch = parsed
          .whereType<Map<String, dynamic>>()
          .map(_prSummaryFromGitea)
          .toList();
      all.addAll(batch);
      if (batch.length < perPage) break;
      page++;
    } catch (e) {
      return GitResult.err('Failed to parse pulls: $e');
    }
  }
  return GitResult.ok(all.take(limit).toList());
}

Future<GitResult<int>> createGiteaPull(
  String repoPath, {
  required String title,
  String body = '',
  required String headRef,
  required String baseRef,
  bool draft = false,
  List<String> labels = const [],
  List<String> assignees = const [],
  List<String> reviewers = const [],
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final labelIds = <int>[];
  if (labels.isNotEmpty) {
    final labelsRes = await giteaGet(
      coords.apiBase, '/${coords.repoPath}/labels?limit=50', token: token);
    if (labelsRes.statusCode == 200) {
      final allLabels = jsonDecode(labelsRes.body) as List;
      for (final name in labels) {
        final match = allLabels
            .whereType<Map<String, dynamic>>()
            .where((l) => l['name'] == name)
            .firstOrNull;
        if (match != null) labelIds.add((match['id'] as num).toInt());
      }
    }
  }
  final r = await _post(
    coords.apiBase,
    '/${coords.repoPath}/pulls',
    {
      'title': title,
      if (body.isNotEmpty) 'body': body,
      'head': headRef,
      'base': baseRef,
      if (draft) 'draft': true,
      if (assignees.isNotEmpty) 'assignees': assignees,
      if (labelIds.isNotEmpty) 'labels': labelIds,
    },
    token: token,
  );
  if (r.statusCode != 201) return GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}');
  try {
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final number = (j['number'] as num).toInt();
    if (reviewers.isNotEmpty) {
      final rv = await _post(
        coords.apiBase,
        '/${coords.repoPath}/pulls/$number/requested_reviewers',
        {'reviewers': reviewers},
        token: token,
      );
      if (rv.statusCode != 201 && rv.statusCode != 200) {
        return GitResult.err(
            'PR #$number created but reviewer assignment failed: '
            'Gitea ${rv.statusCode}: ${_sanitizeBody(rv.body)}');
      }
    }
    return GitResult.ok(number);
  } catch (e) {
    return GitResult.err('Failed to parse created pull: $e');
  }
}

Future<GitResult<PullRequestSummary>> getGiteaPull(
  String repoPath,
  int number, {
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final r = await giteaGet(
    coords.apiBase,
    '/${coords.repoPath}/pulls/$number',
    token: token,
  );
  if (r.statusCode != 200) return GitResult.err('API ${r.statusCode}');
  try {
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return GitResult.ok(_prSummaryFromGitea(j));
  } catch (e) {
    return GitResult.err('Failed to parse pull: $e');
  }
}

Future<GitResult<PullRequestDetail>> giteaPullDetail(
  String repoPath,
  int number, {
  bool includeDiff = true,
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final viewFut = giteaGet(coords.apiBase, '/${coords.repoPath}/pulls/$number', token: token);
  final commentsFut = giteaGet(coords.apiBase, '/${coords.repoPath}/issues/$number/comments', token: token);
  final reviewsFut = giteaGet(coords.apiBase, '/${coords.repoPath}/pulls/$number/reviews', token: token);
  final filesFut = giteaGet(coords.apiBase, '/${coords.repoPath}/pulls/$number/files?limit=300', token: token);
  final diffFut = includeDiff
      ? _getRaw(coords.apiBase, '/${coords.repoPath}/pulls/$number.diff', token: token)
      : Future.value('');

  final view = await viewFut;
  final commentsRes = await commentsFut;
  final reviewsRes = await reviewsFut;
  final filesRes = await filesFut;
  final rawDiff = await diffFut;

  if (view.statusCode != 200) return GitResult.err('API ${view.statusCode}');
  try {
    final j = jsonDecode(view.body) as Map<String, dynamic>;

    final comments = <RemoteComment>[];
    if (commentsRes.statusCode == 200) {
      final parsed = jsonDecode(commentsRes.body) as List;
      comments.addAll(parsed.whereType<Map<String, dynamic>>().map(_commentFromGitea));
    }
    if (reviewsRes.statusCode == 200) {
      final parsed = jsonDecode(reviewsRes.body) as List;
      for (final r in parsed.whereType<Map<String, dynamic>>()) {
        final body = (r['body'] as String? ?? '').trim();
        if (body.isEmpty) continue;
        final state = (r['state'] as String? ?? '').toUpperCase();
        final tag = switch (state) {
          'APPROVED' => '[approved]',
          'REJECTED' || 'REQUEST_CHANGES' => '[requested changes]',
          'COMMENT' => '[commented]',
          _ => '',
        };
        final user = r['user'] as Map<String, dynamic>?;
        comments.add(RemoteComment(
          authorLogin: user?['login'] as String? ?? '',
          body: tag.isEmpty ? body : '$tag\n\n$body',
          createdAt: parseRemoteDate(r['submitted_at']),
        ));
      }
    }
    comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Use the /files endpoint for per-file stats (additions/deletions).
    final files = <PrFile>[];
    if (filesRes.statusCode == 200) {
      final parsed = jsonDecode(filesRes.body) as List;
      for (final f in parsed.whereType<Map<String, dynamic>>()) {
        files.add(PrFile(
          path: (f['filename'] as String? ?? '').trim(),
          additions: (f['additions'] as num? ?? 0).toInt(),
          deletions: (f['deletions'] as num? ?? 0).toInt(),
        ));
      }
    }

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
      comments: comments,
      diff: rawDiff,
      diffByFile: byFile,
      rawDiffByFile: sliceDiffByFile(rawDiff),
    ));
  } catch (e) {
    return GitResult.err('Failed to parse pull detail: $e');
  }
}

Future<GitResult<void>> giteaApprovePull(
  String repoPath, int number, {
  required String event,
  String body = '',
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final reviewBody = {
    'event': event == 'approve' ? 'APPROVED' : (event == 'request-changes' ? 'REQUEST_CHANGES' : 'COMMENT'),
    if (body.isNotEmpty) 'body': body,
  };
  final r = await _post(
    coords.apiBase,
    '/${coords.repoPath}/pulls/$number/reviews',
    reviewBody,
    token: token,
  );
  if (r.statusCode != 200 && r.statusCode != 201) {
    return GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}');
  }
  return const GitResult.ok(null);
}

Future<GitResult<void>> giteaMergePull(
  String repoPath, int number, {
  required String method,
  bool deleteBranch = false,
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final doMethod = switch (method) {
    'squash' => 'squash',
    'rebase' => 'rebase',
    _ => 'merge',
  };
  final r = await _post(
    coords.apiBase,
    '/${coords.repoPath}/pulls/$number/merge',
    {
      'Do': doMethod,
      'delete_branch_after_merge': deleteBranch,
    },
    token: token,
  );
  if (r.statusCode != 200) {
    return GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}');
  }
  return const GitResult.ok(null);
}

Future<GitResult<void>> giteaCommentOnIssue(
  String repoPath, int number, String body, {
  String? token,
}) async {
  if (body.trim().isEmpty) return const GitResult.ok(null);
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final r = await _post(
    coords.apiBase,
    '/${coords.repoPath}/issues/$number/comments',
    {'body': body},
    token: token,
  );
  if (r.statusCode != 201) {
    return GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}');
  }
  return const GitResult.ok(null);
}


// ---------------------------------------------------------------------------
// Issues
// ---------------------------------------------------------------------------

Future<GitResult<List<IssueSummary>>> listGiteaIssues(
  String repoPath, {
  String state = 'open',
  int limit = 100,
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final all = <IssueSummary>[];
  var page = 1;
  const perPage = 50;
  while (all.length < limit) {
    final r = await giteaGet(
      coords.apiBase,
      '/${coords.repoPath}/issues?state=${Uri.encodeComponent(state)}&type=issues&limit=$perPage&page=$page',
      token: token,
    );
    if (r.statusCode != 200) {
      return all.isEmpty
          ? GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}')
          : GitResult.ok(all);
    }
    try {
      final parsed = jsonDecode(r.body) as List;
      final batch = parsed
          .whereType<Map<String, dynamic>>()
          .map(_issueSummaryFromGitea)
          .toList();
      all.addAll(batch);
      if (batch.length < perPage) break;
      page++;
    } catch (e) {
      return GitResult.err('Failed to parse issues: $e');
    }
  }
  return GitResult.ok(all.take(limit).toList());
}

Future<GitResult<IssueSummary>> getGiteaIssue(
  String repoPath, int number, {
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final r = await giteaGet(
    coords.apiBase,
    '/${coords.repoPath}/issues/$number',
    token: token,
  );
  if (r.statusCode != 200) return GitResult.err('API ${r.statusCode}');
  try {
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return GitResult.ok(_issueSummaryFromGitea(j));
  } catch (e) {
    return GitResult.err('Failed to parse issue: $e');
  }
}

Future<GitResult<IssueDetail>> giteaIssueDetail(
  String repoPath, int number, {
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final issueFut = giteaGet(coords.apiBase, '/${coords.repoPath}/issues/$number', token: token);
  final commentsFut = giteaGet(coords.apiBase, '/${coords.repoPath}/issues/$number/comments', token: token);
  final issue = await issueFut;
  final commentsRes = await commentsFut;
  if (issue.statusCode != 200) return GitResult.err('API ${issue.statusCode}');
  try {
    final j = jsonDecode(issue.body) as Map<String, dynamic>;
    final comments = <RemoteComment>[];
    if (commentsRes.statusCode == 200) {
      final parsed = jsonDecode(commentsRes.body) as List;
      comments.addAll(parsed
          .whereType<Map<String, dynamic>>()
          .map(_commentFromGitea));
    }
    return GitResult.ok(IssueDetail(
      body: (j['body'] as String? ?? '').trim(),
      comments: comments,
      assignees: _loginList(j['assignees']),
      labels: _labelNames(j['labels']),
    ));
  } catch (e) {
    return GitResult.err('Failed to parse issue detail: $e');
  }
}

Future<GitResult<int>> createGiteaIssue(
  String repoPath, {
  required String title,
  String body = '',
  List<String> labels = const [],
  List<String> assignees = const [],
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final labelIds = <int>[];
  if (labels.isNotEmpty) {
    final labelsRes = await giteaGet(
      coords.apiBase, '/${coords.repoPath}/labels?limit=50', token: token);
    if (labelsRes.statusCode == 200) {
      final allLabels = jsonDecode(labelsRes.body) as List;
      for (final name in labels) {
        final match = allLabels
            .whereType<Map<String, dynamic>>()
            .where((l) => l['name'] == name)
            .firstOrNull;
        if (match != null) labelIds.add((match['id'] as num).toInt());
      }
    }
  }
  final r = await _post(
    coords.apiBase,
    '/${coords.repoPath}/issues',
    {
      'title': title,
      if (body.isNotEmpty) 'body': body,
      if (assignees.isNotEmpty) 'assignees': assignees,
      if (labelIds.isNotEmpty) 'labels': labelIds,
    },
    token: token,
  );
  if (r.statusCode != 201) return GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}');
  try {
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return GitResult.ok((j['number'] as num).toInt());
  } catch (e) {
    return GitResult.err('Failed to parse created issue: $e');
  }
}

Future<GitResult<void>> editGiteaIssue(
  String repoPath, int number, {
  String? title,
  String? body,
  String? token,
}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final patch = <String, dynamic>{};
  if (title != null) patch['title'] = title;
  if (body != null) patch['body'] = body;
  if (patch.isEmpty) return const GitResult.ok(null);
  final r = await _patch(
    coords.apiBase,
    '/${coords.repoPath}/issues/$number',
    patch,
    token: token,
  );
  if (r.statusCode != 201 && r.statusCode != 200) {
    return GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}');
  }
  return const GitResult.ok(null);
}

Future<GitResult<void>> closeGiteaIssue(
  String repoPath, int number, {String? token}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final r = await _patch(
    coords.apiBase,
    '/${coords.repoPath}/issues/$number',
    {'state': 'closed'},
    token: token,
  );
  if (r.statusCode != 201 && r.statusCode != 200) {
    return GitResult.err('API ${r.statusCode}');
  }
  return const GitResult.ok(null);
}

Future<GitResult<void>> reopenGiteaIssue(
  String repoPath, int number, {String? token}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final r = await _patch(
    coords.apiBase,
    '/${coords.repoPath}/issues/$number',
    {'state': 'open'},
    token: token,
  );
  if (r.statusCode != 201 && r.statusCode != 200) {
    return GitResult.err('API ${r.statusCode}');
  }
  return const GitResult.ok(null);
}

Future<GitResult<void>> addGiteaIssueLabel(
  String repoPath, int number, String label, {String? token}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  // Gitea label API requires label IDs, not names. Resolve first.
  final labelsRes = await giteaGet(
    coords.apiBase,
    '/${coords.repoPath}/labels?limit=50',
    token: token,
  );
  if (labelsRes.statusCode != 200) return GitResult.err('Could not fetch labels');
  final allLabels = jsonDecode(labelsRes.body) as List;
  final match = allLabels
      .whereType<Map<String, dynamic>>()
      .where((l) => l['name'] == label)
      .firstOrNull;
  if (match == null) return GitResult.err('Label "$label" not found');
  final labelId = (match['id'] as num).toInt();
  final r = await _post(
    coords.apiBase,
    '/${coords.repoPath}/issues/$number/labels',
    {'labels': [labelId]},
    token: token,
  );
  if (r.statusCode != 200) return GitResult.err('API ${r.statusCode}');
  return const GitResult.ok(null);
}


// ---------------------------------------------------------------------------
// Auth / identity
// ---------------------------------------------------------------------------

Future<String> giteaWhoami(String repoPath) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return '';
  final token = resolveGiteaToken(coords.apiBase);
  if (token == null) return '';
  final r = await giteaGet(coords.apiBase, '/user', token: token);
  if (r.statusCode != 200) return '';
  try {
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (j['login'] as String? ?? '').trim();
  } catch (_) {
    return '';
  }
}


// ---------------------------------------------------------------------------
// CI / commit statuses
// ---------------------------------------------------------------------------

Future<GitResult<List<CheckSummary>>> listGiteaCommitStatuses(
  String repoPath, int prNumber, {String? token,}
) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final prRes = await giteaGet(
    coords.apiBase,
    '/${coords.repoPath}/pulls/$prNumber',
    token: token,
  );
  if (prRes.statusCode != 200) return GitResult.ok(const []);
  final prJson = jsonDecode(prRes.body) as Map<String, dynamic>;
  final head = prJson['head'] as Map<String, dynamic>?;
  final sha = head?['sha'] as String? ?? '';
  if (sha.isEmpty) return GitResult.ok(const []);

  final r = await giteaGet(
    coords.apiBase,
    '/${coords.repoPath}/commits/$sha/statuses?limit=50',
    token: token,
  );
  if (r.statusCode != 200) return GitResult.ok(const []);
  try {
    final parsed = jsonDecode(r.body) as List;
    final checks = parsed
        .whereType<Map<String, dynamic>>()
        .map(_checkFromGiteaStatus)
        .toList();
    return GitResult.ok(checks);
  } catch (e) {
    return GitResult.err('Failed to parse commit statuses: $e');
  }
}


// ---------------------------------------------------------------------------
// PR close / PR files
// ---------------------------------------------------------------------------

Future<GitResult<void>> closeGiteaPull(
  String repoPath, int number, {String? token,}
) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final r = await _patch(
    coords.apiBase,
    '/${coords.repoPath}/pulls/$number',
    {'state': 'closed'},
    token: token,
  );
  if (r.statusCode != 200 && r.statusCode != 201) {
    return GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}');
  }
  return const GitResult.ok(null);
}

Future<GitResult<void>> assignSelfToGiteaIssue(
  String repoPath, int number, {String? token,}
) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final login = await giteaWhoami(repoPath);
  if (login.isEmpty) return GitResult.err('not authenticated');
  final r = await _patch(
    coords.apiBase,
    '/${coords.repoPath}/issues/$number',
    {'assignees': [login]},
    token: token,
  );
  if (r.statusCode != 200 && r.statusCode != 201) {
    return GitResult.err('API ${r.statusCode}');
  }
  return const GitResult.ok(null);
}


// ---------------------------------------------------------------------------
// JSON → DTO mappers
// ---------------------------------------------------------------------------

PullRequestSummary _prSummaryFromGitea(Map<String, dynamic> j) {
  final user = j['user'] as Map<String, dynamic>?;
  final login = user?['login'] as String? ?? '';
  final base = j['base'] as Map<String, dynamic>?;
  final head = j['head'] as Map<String, dynamic>?;

  final reviewers = <PrReviewer>[];
  final requested = j['requested_reviewers'] as List? ?? const [];
  for (final r in requested.whereType<Map<String, dynamic>>()) {
    final u = (r['login'] as String? ?? '').trim();
    if (u.isNotEmpty) reviewers.add(PrReviewer(login: u, state: 'PENDING'));
  }

  final mergeableBool = j['mergeable'] as bool? ?? true;

  return PullRequestSummary(
    number: (j['number'] as num).toInt(),
    title: (j['title'] as String? ?? '').trim(),
    headRef: (head?['ref'] as String? ?? '').trim(),
    baseRef: (base?['ref'] as String? ?? '').trim(),
    state: (j['state'] as String? ?? 'open').toUpperCase(),
    isDraft: j['draft'] as bool? ?? false,
    authorLogin: login,
    conversationCount: (j['comments'] as num? ?? 0).toInt(),
    updatedAt: parseRemoteDate(j['updated_at']),
    additions: (j['additions'] as num? ?? 0).toInt(),
    deletions: (j['deletions'] as num? ?? 0).toInt(),
    changedFiles: (j['changed_files'] as num? ?? 0).toInt(),
    mergeable: mergeableBool ? 'MERGEABLE' : 'CONFLICTING',
    reviewDecision: '',
    reviewers: reviewers,
    labels: _labelNames(j['labels']),
    assignees: _loginList(j['assignees']),
  );
}

IssueSummary _issueSummaryFromGitea(Map<String, dynamic> j) {
  final user = j['user'] as Map<String, dynamic>?;
  final login = user?['login'] as String? ?? '';
  return IssueSummary(
    number: (j['number'] as num).toInt(),
    title: (j['title'] as String? ?? '').trim(),
    state: (j['state'] as String? ?? 'open').toUpperCase(),
    authorLogin: login,
    labels: _labelNames(j['labels']),
    assignees: _loginList(j['assignees']),
    commentCount: (j['comments'] as num? ?? 0).toInt(),
    updatedAt: parseRemoteDate(j['updated_at']),
  );
}

RemoteComment _commentFromGitea(Map<String, dynamic> j) {
  final user = j['user'] as Map<String, dynamic>?;
  return RemoteComment(
    authorLogin: user?['login'] as String? ?? '',
    body: (j['body'] as String? ?? '').trim(),
    createdAt: parseRemoteDate(j['created_at']),
  );
}

CheckSummary _checkFromGiteaStatus(Map<String, dynamic> j) {
  final status = (j['status'] as String? ?? '').toLowerCase();
  final isCompleted = const {'success', 'failure', 'error', 'warning'}
      .contains(status);
  final conclusion = switch (status) {
    'success' => 'success',
    'failure' || 'error' => 'failure',
    'warning' => 'neutral',
    _ => null,
  };
  return CheckSummary(
    name: (j['context'] as String? ?? '').trim(),
    status: isCompleted ? 'completed' : (status == 'pending' ? 'queued' : 'in_progress'),
    conclusion: conclusion,
    duration: null,
  );
}

List<String> _labelNames(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((m) => (m['name'] as String? ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

List<String> _loginList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((m) => (m['login'] as String? ?? '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}


// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

class _HttpResult {
  final int statusCode;
  final String body;
  const _HttpResult(this.statusCode, this.body);
}

Future<_HttpResult> giteaGet(String baseUrl, String path, {String? token}) async {
  final label = 'gitea.GET $path';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(type: 'start', command: label);
  try {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl$path'));
      request.headers.set('Accept', 'application/json');
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'token $token');
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'end', command: label,
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: response.statusCode >= 400 ? 'http.${response.statusCode}' : null,
      );
      return _HttpResult(response.statusCode, body);
    } finally {
      client.close();
    }
  } catch (e) {
    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'end', command: label,
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: 'http.exception',
    );
    return _HttpResult(0, e.toString());
  }
}

Future<String> _getRaw(String baseUrl, String path, {String? token}) async {
  try {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl$path'));
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'token $token');
      }
      final response = await request.close();
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  } catch (_) {
    return '';
  }
}

Future<_HttpResult> _post(String baseUrl, String path, Map<String, dynamic> body, {String? token}) async {
  final label = 'gitea.POST $path';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(type: 'start', command: label);
  try {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'token $token');
      }
      request.write(jsonEncode(body));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'end', command: label,
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: response.statusCode >= 400 ? 'http.${response.statusCode}' : null,
      );
      return _HttpResult(response.statusCode, responseBody);
    } finally {
      client.close();
    }
  } catch (e) {
    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'end', command: label,
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: 'http.exception',
    );
    return _HttpResult(0, e.toString());
  }
}

Future<_HttpResult> _patch(String baseUrl, String path, Map<String, dynamic> body, {String? token}) async {
  final label = 'gitea.PATCH $path';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(type: 'start', command: label);
  try {
    final client = HttpClient();
    try {
      final request = await client.patchUrl(Uri.parse('$baseUrl$path'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'token $token');
      }
      request.write(jsonEncode(body));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'end', command: label,
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: response.statusCode >= 400 ? 'http.${response.statusCode}' : null,
      );
      return _HttpResult(response.statusCode, responseBody);
    } finally {
      client.close();
    }
  } catch (e) {
    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'end', command: label,
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: 'http.exception',
    );
    return _HttpResult(0, e.toString());
  }
}
