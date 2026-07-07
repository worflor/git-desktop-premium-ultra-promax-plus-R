import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import 'git.dart' as git;
import 'git_result.dart';
import 'remote_types.dart';
import 'settings_store.dart';
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

/// Resolve the access token for the Gitea instance behind [apiBase]
/// (`https://host/api/v1`). A token stored per host in the settings
/// snapshot wins; the `GITEA_TOKEN` environment variable is the
/// fallback for any host without a stored token. Synchronous so the
/// existing `token ??= resolveGiteaToken(...)` defaulting idiom keeps
/// working — the settings snapshot is already warm by the time a forge
/// call fires (the app loads settings at startup).
String? resolveGiteaToken(String apiBase) {
  final host = _hostOfApiBase(apiBase);
  if (host.isNotEmpty) {
    final stored = SettingsStore.cachedGiteaTokens()[host];
    if (stored != null && stored.isNotEmpty) return stored;
  }
  final env = Platform.environment['GITEA_TOKEN'];
  if (env != null && env.isNotEmpty) return env;
  return null;
}

/// THE single producer of the token-map key shape: lowercase `host`, plus
/// `:port` only for a non-default port. 80 and 443 are dropped
/// unconditionally — `GiteaRepoCoords.parse` strips per-scheme defaults
/// when building the apiBase, so a `:443`/`:80` key could only ever be
/// minted from user input typed with an explicit default port, and that
/// key would then never match the apiBase-derived lookup. Every function
/// that mints or looks up a key MUST come through here; two producers with
/// their own port rules is exactly the bug this exists to prevent.
String _hostKey(String host, int? port) {
  if (host.isEmpty) return '';
  final h = host.toLowerCase();
  if (port == null || port == 80 || port == 443) return h;
  return '$h:$port';
}

/// Token-map key of an `/api/v1` base URL, via [_hostKey].
String _hostOfApiBase(String apiBase) {
  try {
    final u = Uri.parse(apiBase);
    return _hostKey(u.host, u.hasPort ? u.port : null);
  } catch (_) {
    return '';
  }
}

/// Canonicalize a user-typed forge identifier into exactly the key shape
/// that [resolveGiteaToken] looks up: [_hostKey]'s lowercase `host`, or
/// `host:port` only for an explicit NON-default HTTP(S) port (80/443 are
/// dropped — the apiBase side never carries them, so a key holding one
/// could never match at resolve time).
///
/// The token map is keyed by this shape, so the settings UI MUST route
/// everything a user might paste — a full clone URL, a scp-style remote,
/// or a bare host — through here before persisting, or the stored key
/// silently never matches at resolve time. Accepts:
///   - `scheme://…` (http/https/ssh): host (+ port via [_hostKey]); ssh
///     keeps host only, because an ssh port is the daemon's port, not the
///     HTTP API port (mirrors `hostAndPortOfRemote`). Path and userinfo
///     are ignored.
///   - scp form `git@host:path`: host between `@` and `:`, no port (the
///     colon introduces a path).
///   - bare `host`, `host:port`, or `host/some/path`: everything from the
///     first `/` is dropped; a `:tail` counts as a port only when it is
///     all digits, else discarded.
/// Returns '' for empty or unparseable input; the caller decides what to
/// do with that.
String canonicalGiteaHostKey(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';

  if (trimmed.contains('://')) {
    try {
      final u = Uri.parse(trimmed);
      if (u.host.isEmpty) return '';
      final isSsh = u.scheme.toLowerCase() == 'ssh';
      return _hostKey(u.host, !isSsh && u.hasPort ? u.port : null);
    } catch (_) {
      return '';
    }
  }

  // scp-style `git@host:path` — an `@` (with userinfo) before any `:`/`/`.
  final at = trimmed.indexOf('@');
  if (at >= 0) {
    final firstColon = trimmed.indexOf(':');
    final firstSlash = trimmed.indexOf('/');
    final sep = [
      firstColon,
      firstSlash,
    ].where((i) => i >= 0).fold<int>(-1, (a, b) => a < 0 ? b : (b < a ? b : a));
    if (sep < 0 || at < sep) {
      final host = trimmed.substring(at + 1, sep < 0 ? trimmed.length : sep);
      return _validHost(host) ? _hostKey(host, null) : '';
    }
  }

  // Bare host / host:port / host/path.
  var rest = trimmed;
  final slash = rest.indexOf('/');
  if (slash >= 0) rest = rest.substring(0, slash);
  if (rest.isEmpty) return '';
  final colon = rest.indexOf(':');
  if (colon >= 0) {
    final host = rest.substring(0, colon);
    final tail = rest.substring(colon + 1);
    if (!_validHost(host)) return '';
    // Digits only — `tryParse` alone would admit signed forms like `+3000`.
    final port =
        RegExp(r'^\d+$').hasMatch(tail) ? int.parse(tail) : null;
    return _hostKey(host, port);
  }
  return _validHost(rest) ? _hostKey(rest, null) : '';
}

/// A plausible DNS host / IP label: letters, digits, dots and hyphens only.
/// Anything with spaces or other punctuation is user garbage, not a host.
final RegExp _hostCharset = RegExp(r'^[A-Za-z0-9.-]+$');
bool _validHost(String h) => h.isNotEmpty && _hostCharset.hasMatch(h);

class GiteaApiStatus {
  final bool reachable;
  final bool authenticated;
  final String? version;
  final String? reason;
  /// Login of the validated token holder, when [authenticated]. Empty
  /// otherwise.
  final String login;

  const GiteaApiStatus({
    required this.reachable,
    required this.authenticated,
    this.version,
    this.reason,
    this.login = '',
  });

  bool get usable => reachable;
}

/// Probe the Gitea/Forgejo instance at [baseUrl]. Reachability comes
/// from the unauthenticated `/version` endpoint; authentication is only
/// ever reported after the token is *validated* against `/user`. A
/// present-but-rejected token (401) reports reachable-yet-unauthenticated
/// with a reason, never a false "authenticated".
Future<GiteaApiStatus> giteaApiStatus(String baseUrl, {String? token}) async {
  token ??= resolveGiteaToken(baseUrl);
  try {
    final r = await giteaGet(baseUrl, '/version', token: token);
    if (r.statusCode != 200) {
      // statusCode 0 means the request threw (DNS / connection refused /
      // TLS) — the body carries the exception text. Anything else is a
      // live server answering with a non-200.
      return GiteaApiStatus(
        reachable: false,
        authenticated: false,
        reason: r.statusCode == 0
            ? 'unreachable: ${r.body}'
            : 'API returned ${r.statusCode}',
      );
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final ver = j['version'] as String? ?? '';
    if (token == null || token.isEmpty) {
      return GiteaApiStatus(
        reachable: true,
        authenticated: false,
        version: ver,
        reason: 'no token for this host',
      );
    }
    // Validate the token — a 200 with a login is the only thing that
    // earns the authenticated bit.
    final who = await giteaGet(baseUrl, '/user', token: token);
    if (who.statusCode == 200) {
      String login = '';
      try {
        login = ((jsonDecode(who.body)
                as Map<String, dynamic>)['login'] as String? ??
            '')
            .trim();
      } catch (_) {}
      return GiteaApiStatus(
        reachable: true,
        authenticated: true,
        version: ver,
        login: login,
      );
    }
    return GiteaApiStatus(
      reachable: true,
      authenticated: false,
      version: ver,
      reason: who.statusCode == 401
          ? 'token rejected (401)'
          : 'token check returned ${who.statusCode}',
    );
  } catch (e) {
    return GiteaApiStatus(
      reachable: false,
      authenticated: false,
      reason: e.toString(),
    );
  }
}

/// Whether the repo behind [coords] answers a read with the given
/// credentials. GET /repos/owner/repo through [giteaGet] (which already
/// retries a token-bearing 401 anonymously), 200 = readable. Private
/// repos answer 404 to anonymous callers — Gitea hides their existence —
/// so "not readable" covers both private and nonexistent.
Future<bool> giteaRepoReadable(GiteaRepoCoords coords, {String? token}) async {
  token ??= resolveGiteaToken(coords.apiBase);
  final r = await giteaGet(coords.apiBase, '/${coords.repoPath}', token: token);
  return r.statusCode == 200;
}

/// Resolve the API base URL and owner/repo from the repo's primary remote.
/// Uses the same primary-remote rule as the rest of the app (`origin` when
/// present, otherwise the sole/first remote) rather than assuming `origin`,
/// so a fork whose Gitea/Forgejo remote is named `upstream` still resolves
/// its API coordinates. Routes through [git.runGit] so it shares the
/// non-interactive env and subprocess throttle instead of spawning raw.
Future<GiteaRepoCoords?> resolveGiteaCoords(String repoPath) async {
  try {
    final remoteRes = await git.primaryRemoteName(repoPath);
    final remote = remoteRes.ok ? remoteRes.data : null;
    if (remote == null) return null;
    final r = await git.runGit(repoPath, ['remote', 'get-url', remote]);
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
    final trimmed = remoteUrl.trim();
    final (:host, :port) = hostAndPortOfRemote(trimmed);
    if (host.isEmpty) return null;

    String? path;
    // SSH/scp remotes have no scheme; those always speak https to the API.
    // An explicit http:// remote (common for intranet Gitea on a plain
    // port) keeps http, and any explicit port is carried through so a
    // self-hosted instance on host:3000 isn't addressed at 443.
    var scheme = 'https';
    if (trimmed.startsWith('https://') || trimmed.startsWith('http://')) {
      try {
        final uri = Uri.parse(trimmed);
        path = uri.path;
        scheme = uri.scheme;
      } catch (_) {
        return null;
      }
    } else {
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx < 0) return null;
      path = '/${trimmed.substring(colonIdx + 1)}';
    }
    if (path.endsWith('.git')) path = path.substring(0, path.length - 4);
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final defaultPort = scheme == 'http' ? 80 : 443;
    final authority = (port != null && port != defaultPort) ? '$host:$port' : host;
    return GiteaRepoCoords(
      apiBase: '$scheme://$authority/api/v1',
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final labelIds = <int>[];
  if (labels.isNotEmpty) {
    final ids = await _resolveLabelIds(coords, token);
    if (ids != null) {
      for (final name in labels) {
        final id = ids[name];
        if (id != null) labelIds.add(id);
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final labelIds = <int>[];
  if (labels.isNotEmpty) {
    final ids = await _resolveLabelIds(coords, token);
    if (ids != null) {
      for (final name in labels) {
        final id = ids[name];
        if (id != null) labelIds.add(id);
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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

// The Gitea label API addresses labels by numeric ID, not name, so
// every label-touching call has to translate name → id via a
// `/labels` fetch. Label definitions rarely change within a session,
// so the name→id map is memoised per repo behind a short TTL — a burst
// of add/remove operations (or an editIssue that both adds and removes)
// then shares a single fetch instead of hammering `/labels` once per
// label.
class _LabelIdCache {
  final Map<String, int> byName;
  final DateTime at;
  const _LabelIdCache(this.byName, this.at);
}

final Map<String, _LabelIdCache> _labelIdCacheByRepo = {};
const Duration _labelIdCacheTtl = Duration(seconds: 30);

/// Drop the memoised per-repo label maps. Exposed for tests and any
/// caller that has reason to believe the label set changed underfoot.
void clearGiteaLabelCache() => _labelIdCacheByRepo.clear();

/// Resolve the repo's label name→id map, using the memo when it's still
/// warm. Returns null only when the `/labels` fetch itself fails.
Future<Map<String, int>?> _resolveLabelIds(
    GiteaRepoCoords coords, String? token) async {
  final key = '${coords.apiBase}/${coords.owner}/${coords.repo}';
  final cached = _labelIdCacheByRepo[key];
  if (cached != null &&
      DateTime.now().difference(cached.at) < _labelIdCacheTtl) {
    return cached.byName;
  }
  final res = await giteaGet(
    coords.apiBase, '/${coords.repoPath}/labels?limit=100', token: token);
  if (res.statusCode != 200) return null;
  final map = <String, int>{};
  for (final l in (jsonDecode(res.body) as List).whereType<Map<String, dynamic>>()) {
    final name = (l['name'] as String? ?? '').trim();
    if (name.isNotEmpty) map[name] = (l['id'] as num).toInt();
  }
  _labelIdCacheByRepo[key] = _LabelIdCache(map, DateTime.now());
  return map;
}

Future<GitResult<void>> addGiteaIssueLabel(
  String repoPath, int number, String label, {String? token}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final ids = await _resolveLabelIds(coords, token);
  if (ids == null) return const GitResult.err('Could not fetch labels');
  final labelId = ids[label];
  if (labelId == null) return GitResult.err('Label "$label" not found');
  final r = await _post(
    coords.apiBase,
    '/${coords.repoPath}/issues/$number/labels',
    {'labels': [labelId]},
    token: token,
  );
  if (r.statusCode != 200) return GitResult.err('API ${r.statusCode}');
  return const GitResult.ok(null);
}

Future<GitResult<void>> removeGiteaIssueLabel(
  String repoPath, int number, String label, {String? token}) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final ids = await _resolveLabelIds(coords, token);
  if (ids == null) return const GitResult.err('Could not fetch labels');
  final labelId = ids[label];
  // A label that isn't defined on the repo can't be attached either, so
  // "remove" is already satisfied — treat as a no-op success rather than
  // failing an editIssue that also did useful work.
  if (labelId == null) return const GitResult.ok(null);
  final r = await _delete(
    coords.apiBase,
    '/${coords.repoPath}/issues/$number/labels/$labelId',
    token: token,
  );
  // Gitea answers a successful label removal with 204 No Content.
  if (r.statusCode != 204 && r.statusCode != 200) {
    return GitResult.err('Gitea ${r.statusCode}: ${_sanitizeBody(r.body)}');
  }
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final prRes = await giteaGet(
    coords.apiBase,
    '/${coords.repoPath}/pulls/$prNumber',
    token: token,
  );
  if (prRes.statusCode != 200) return const GitResult.ok([]);
  final prJson = jsonDecode(prRes.body) as Map<String, dynamic>;
  final head = prJson['head'] as Map<String, dynamic>?;
  final sha = head?['sha'] as String? ?? '';
  if (sha.isEmpty) return const GitResult.ok([]);

  final checks = <CheckSummary>[];
  final seen = <String>{};

  // Combined status endpoint — dedupes to the latest state per context.
  // Modern Gitea/Forgejo Actions register each job as a commit status,
  // so this alone surfaces Actions on any current instance. On an older
  // instance that predates the combined endpoint we fall back to the
  // legacy per-status list.
  var statuses = await giteaGet(
    coords.apiBase,
    '/${coords.repoPath}/commits/$sha/status?limit=100',
    token: token,
  );
  try {
    if (statuses.statusCode == 200) {
      final j = jsonDecode(statuses.body) as Map<String, dynamic>;
      for (final s in (j['statuses'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        final c = _checkFromGiteaStatus(s);
        if (c.name.isEmpty || !seen.add(c.name)) continue;
        checks.add(c);
      }
    } else {
      statuses = await giteaGet(
        coords.apiBase,
        '/${coords.repoPath}/commits/$sha/statuses?limit=50',
        token: token,
      );
      if (statuses.statusCode == 200) {
        for (final s in (jsonDecode(statuses.body) as List)
            .whereType<Map<String, dynamic>>()) {
          final c = _checkFromGiteaStatus(s);
          if (c.name.isEmpty || !seen.add(c.name)) continue;
          checks.add(c);
        }
      }
    }
  } catch (e) {
    return GitResult.err('Failed to parse commit statuses: $e');
  }

  // Union with Actions runs for this head. On instances where Actions
  // already flow through commit statuses this adds nothing new (deduped
  // by name); on any instance where the endpoint is absent or Actions is
  // disabled the request 404s/403s and we degrade silently to statuses.
  final tasks = await giteaGet(
    coords.apiBase,
    '/${coords.repoPath}/actions/tasks?limit=50',
    token: token,
  );
  if (tasks.statusCode == 200) {
    try {
      final tj = jsonDecode(tasks.body) as Map<String, dynamic>;
      for (final run in (tj['workflow_runs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        if ((run['head_sha'] as String? ?? '') != sha) continue;
        final c = _checkFromGiteaTask(run);
        if (c.name.isEmpty || !seen.add(c.name)) continue;
        checks.add(c);
      }
    } catch (_) {
      // A malformed Actions payload never sinks the status list we
      // already built — Actions is the additive layer here.
    }
  }

  return GitResult.ok(checks);
}


// ---------------------------------------------------------------------------
// PR close / PR files
// ---------------------------------------------------------------------------

Future<GitResult<void>> closeGiteaPull(
  String repoPath, int number, {String? token,}
) async {
  final coords = await resolveGiteaCoords(repoPath);
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
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
  if (coords == null) return const GitResult.err('Could not resolve Gitea remote');
  token ??= resolveGiteaToken(coords.apiBase);
  final login = await giteaWhoami(repoPath);
  if (login.isEmpty) return const GitResult.err('not authenticated');
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

CheckSummary _checkFromGiteaTask(Map<String, dynamic> j) {
  // Gitea's ActionRunStatus surfaces as one of: unknown, waiting,
  // running, success, failure, cancelled, skipped, blocked.
  final status = (j['status'] as String? ?? '').toLowerCase();
  const done = {'success', 'failure', 'cancelled', 'skipped'};
  final conclusion = switch (status) {
    'success' => 'success',
    'failure' => 'failure',
    'cancelled' => 'cancelled',
    'skipped' => 'skipped',
    _ => null,
  };
  var name = (j['name'] as String? ?? '').trim();
  if (name.isEmpty) name = (j['display_title'] as String? ?? '').trim();
  return CheckSummary(
    name: name,
    status: done.contains(status)
        ? 'completed'
        : (status == 'running' ? 'in_progress' : 'queued'),
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

class GiteaHttpResult {
  final int statusCode;
  final String body;
  const GiteaHttpResult(this.statusCode, this.body);
}

/// Wait implied by a 429's `Retry-After` header (delta-seconds form),
/// capped so a hostile or mistaken value can't stall the UI. Accepts both
/// RFC forms — delta-seconds and an HTTP-date — since compliant servers may
/// send either; absent or unparseable falls back to a short fixed backoff.
Duration _retryAfterDelay(String? header) {
  final raw = (header ?? '').trim();
  const cap = Duration(seconds: 5);
  final secs = int.tryParse(raw);
  if (secs != null && secs > 0) {
    return secs > 5 ? cap : Duration(seconds: secs);
  }
  try {
    final until = HttpDate.parse(raw);
    final wait = until.difference(DateTime.now().toUtc());
    if (wait > Duration.zero) return wait > cap ? cap : wait;
  } catch (_) {}
  return const Duration(milliseconds: 500);
}

/// Single place every Gitea request funnels through. Issues [method] at
/// [url], optionally with a JSON [body] and bearer [token].
///
/// A 429 is retried exactly once after respecting `Retry-After` (capped),
/// never a storm — but ONLY for GET. A rate-limited mutation is returned
/// as-is: if a proxy or race applied the write before the 429 surfaced, an
/// automatic resend would double-post comments/issues or replay label and
/// state changes. Reads replay for free; writes need the caller (a human
/// retrying an explicit action) to mean it. A second 429 — or any other
/// status — is returned as-is for the caller to surface.
Future<GiteaHttpResult> _giteaSend(
  String method,
  String url, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final client = HttpClient();
  try {
    for (var attempt = 0;; attempt++) {
      final request = await client.openUrl(method, Uri.parse(url));
      request.headers.set('Accept', 'application/json');
      if (body != null) {
        request.headers.set('Content-Type', 'application/json');
      }
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'token $token');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode == 429 && attempt == 0 && method == 'GET') {
        await Future<void>.delayed(
          _retryAfterDelay(response.headers.value(HttpHeaders.retryAfterHeader)),
        );
        continue;
      }
      return GiteaHttpResult(response.statusCode, text);
    }
  } finally {
    client.close();
  }
}

/// Wrap [_giteaSend] with the command-lifecycle diagnostics every forge
/// call records, mapping a thrown request (DNS / refused / TLS) to the
/// sentinel status 0 with the exception text as the body.
Future<GiteaHttpResult> _giteaRequest(
  String verb,
  String baseUrl,
  String path, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final label = 'gitea.$verb $path';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(type: 'start', command: label);
  try {
    final r = await _giteaSend(verb, '$baseUrl$path', token: token, body: body);
    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'end', command: label,
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: r.statusCode >= 400 ? 'http.${r.statusCode}' : null,
    );
    return r;
  } catch (e) {
    stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'end', command: label,
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: 'http.exception',
    );
    return GiteaHttpResult(0, e.toString());
  }
}

/// GET with anonymous fallback. Gitea serves public reads without a
/// token, so a stale or wrongly-scoped token must not break a repo the
/// status layer already promised is browseable: a 401 carrying a token
/// retries once anonymously, and a 2xx retry wins. Anything else keeps
/// the original 401 — the clearer diagnosis for genuinely private
/// content. Writes never fall back; they need the token to mean it.
Future<GiteaHttpResult> giteaGet(String baseUrl, String path, {String? token}) async {
  final r = await _giteaRequest('GET', baseUrl, path, token: token);
  if (r.statusCode == 401 && token != null && token.isNotEmpty) {
    final anon = await _giteaRequest('GET', baseUrl, path);
    if (anon.statusCode >= 200 && anon.statusCode < 300) return anon;
  }
  return r;
}

Future<GiteaHttpResult> _post(
        String baseUrl, String path, Map<String, dynamic> body, {String? token}) =>
    _giteaRequest('POST', baseUrl, path, token: token, body: body);

Future<GiteaHttpResult> _patch(
        String baseUrl, String path, Map<String, dynamic> body, {String? token}) =>
    _giteaRequest('PATCH', baseUrl, path, token: token, body: body);

Future<GiteaHttpResult> _delete(String baseUrl, String path, {String? token}) =>
    _giteaRequest('DELETE', baseUrl, path, token: token);

Future<String> _getRaw(String baseUrl, String path, {String? token}) async {
  final r = await _giteaRequest('GET', baseUrl, path, token: token);
  return r.statusCode == 0 ? '' : r.body;
}
