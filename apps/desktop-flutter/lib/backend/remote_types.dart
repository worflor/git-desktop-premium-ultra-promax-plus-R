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

import 'package:meta/meta.dart';

import '../features/diff/diff_models.dart';
import 'git.dart' as git;

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
  /// Whether write actions (create/promote/merge/comment) are expected to
  /// succeed. Defaults to [available]. A forge that serves anonymous reads
  /// but requires a token for writes (Gitea/Forgejo) reports
  /// available-but-not-canWrite so browsing keeps working while write
  /// affordances stay hidden; [reason] then says what's missing.
  final bool canWrite;
  final String? reason;
  const RemoteProviderStatus(
      {required this.available, bool? canWrite, this.reason})
      : canWrite = canWrite ?? available;
  static const yes = RemoteProviderStatus(available: true);
}

/// Format a PR/MR as a `git format-patch`-style `.patch` string.
String formatPrAsPatch(PullRequestSummary pr, PullRequestDetail detail) {
  final author = pr.authorLogin.isNotEmpty ? pr.authorLogin : 'unknown';
  final dateStr = pr.updatedAt.toUtc().toIso8601String();
  final body = detail.body.trim();
  return [
    'From: $author <$author@noreply.local>',
    'Date: $dateStr',
    'Subject: [PATCH] ${pr.title}',
    '',
    if (body.isNotEmpty) ...[body, ''],
    '---',
    '',
    detail.diff,
  ].join('\n');
}

// ---------------------------------------------------------------------------
// Forge detection — single-sourced so adding a new forge (Gitea,
// Bitbucket, Forgejo, …) requires one change here, not one per
// provider file.
// ---------------------------------------------------------------------------

enum RemoteForge { github, gitlab, gitea, unknown }

/// Detected forge per remote — keyed by remote name (e.g. 'origin',
/// 'upstream', 'mirror'). Enables cross-forge constellation merging.
class ForgeTopology {
  final Map<String, RemoteForge> byRemote;
  const ForgeTopology(this.byRemote);

  RemoteForge get primary => byRemote['origin'] ?? byRemote.values.firstOrNull ?? RemoteForge.unknown;
  Iterable<MapEntry<String, RemoteForge>> get known =>
      byRemote.entries.where((e) => e.value != RemoteForge.unknown);
}

/// Detect the forge for every configured remote in [repoPath].
/// Single `git remote -v` call → parse all remote URLs at once.
Future<ForgeTopology> detectAllForges(String repoPath) async {
  try {
    final r = await git.runGit(repoPath, ['remote', '-v']);
    if (r.exitCode != 0) return const ForgeTopology({});
    // Parse "name\turl (fetch|push)" lines — deduplicate by name,
    // prefer fetch URL.
    final urls = <String, String>{};
    for (final line in (r.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final name = parts[0];
      final url = parts[1];
      if (!urls.containsKey(name)) urls[name] = url;
    }
    final results = <String, RemoteForge>{};
    final probeFuts = <String, Future<RemoteForge>>{};
    for (final entry in urls.entries) {
      final byName = forgeFromUrl(entry.value);
      if (byName != RemoteForge.unknown) {
        results[entry.key] = byName;
      } else {
        probeFuts[entry.key] = _probeForForge(entry.value);
      }
    }
    if (probeFuts.isNotEmpty) {
      final probed = await Future.wait(probeFuts.values.toList());
      var i = 0;
      for (final name in probeFuts.keys) {
        results[name] = probed[i++];
      }
    }
    return ForgeTopology(results);
  } catch (_) {
    return const ForgeTopology({});
  }
}

/// Resolve the forge hosting [repoPath] by reading `origin`.
Future<RemoteForge> detectForge(String repoPath) async {
  try {
    // Read the primary remote (origin when present, else the sole/first
    // remote) rather than assuming `origin`, so a fork whose forge remote is
    // named `upstream` is still classified. Routed through [git.runGit] for
    // the shared non-interactive env + throttle.
    final remoteRes = await git.primaryRemoteName(repoPath);
    final remote = remoteRes.ok ? remoteRes.data : null;
    if (remote == null) return RemoteForge.unknown;
    final r = await git.runGit(repoPath, ['remote', 'get-url', remote]);
    if (r.exitCode != 0) return RemoteForge.unknown;
    final url = (r.stdout as String).trim();
    final byName = forgeFromUrl(url);
    if (byName != RemoteForge.unknown) return byName;
    // Unknown host — fingerprint the API. Self-hosted instances
    // (git.mycompany.com) won't match by hostname, so we ask the host
    // what it is: Gitea/Forgejo, self-hosted GitLab, or GitHub Enterprise.
    return await _probeForForge(url);
  } catch (_) {
    return RemoteForge.unknown;
  }
}

final Map<String, RemoteForge> _forgeProbeCache = {};

void clearForgeProbeCache() => _forgeProbeCache.clear();

/// Test-only entry to the host fingerprinter — exercises the real probe
/// (port carry-through, http fallback, Gitea/GitLab/GHE detection) against
/// a local fake server without needing a git repo to resolve `origin`.
@visibleForTesting
Future<RemoteForge> probeForgeForTest(String remoteUrl) =>
    _probeForForge(remoteUrl);

/// Fingerprint an unknown host by asking each forge's version/meta
/// endpoint what it is, in order Gitea → GitLab → GHE. First distinctive
/// answer wins; the result is memoised per remote URL.
///
/// Port handling: [hostOfRemote] drops the port, so an instance on
/// `host:3000` would otherwise be probed at the default 443. We carry the
/// port through from the remote URL and, for a host with an explicit
/// non-443 port, also try plain `http` as a fallback (a common shape for
/// intranet Gitea). A default-https host is never downgraded to http.
Future<RemoteForge> _probeForForge(String remoteUrl) async {
  final cached = _forgeProbeCache[remoteUrl];
  if (cached != null) return cached;
  final (:host, :port) = hostAndPortOfRemote(remoteUrl);
  if (host.isEmpty) return RemoteForge.unknown;

  final origins = <String>[];
  if (port != null && port != 443) {
    origins..add('https://$host:$port')..add('http://$host:$port');
  } else {
    origins.add('https://$host');
  }

  for (final origin in origins) {
    final forge = await _fingerprintForge(origin);
    if (forge != RemoteForge.unknown) {
      _forgeProbeCache[remoteUrl] = forge;
      return forge;
    }
  }
  _forgeProbeCache[remoteUrl] = RemoteForge.unknown;
  return RemoteForge.unknown;
}

/// Try each forge's tell at [origin] (`scheme://host[:port]`).
Future<RemoteForge> _fingerprintForge(String origin) async {
  // Gitea / Forgejo — /api/v1/version answers {"version": "..."} even
  // unauthenticated.
  final gitea = await _forgeProbeGet('$origin/api/v1/version');
  if (gitea != null &&
      gitea.status == 200 &&
      _jsonHasKey(gitea.body, 'version')) {
    return RemoteForge.gitea;
  }
  // GitLab — /api/v4/version requires a token, so an anonymous request
  // is answered with 401 and the body {"message":"401 Unauthorized"}.
  // A token-bearing environment instead gets 200 with a `version` field.
  final gitlab = await _forgeProbeGet('$origin/api/v4/version');
  if (gitlab != null) {
    if (gitlab.status == 200 && _jsonHasKey(gitlab.body, 'version')) {
      return RemoteForge.gitlab;
    }
    if (gitlab.status == 401 && gitlab.body.contains('Unauthorized')) {
      return RemoteForge.gitlab;
    }
  }
  // GitHub Enterprise — /api/v3/meta is public and carries an
  // `installed_version` field (and `verifiable_password_authentication`)
  // that github.com's own meta also exposes.
  final ghe = await _forgeProbeGet('$origin/api/v3/meta');
  if (ghe != null &&
      ghe.status == 200 &&
      (_jsonHasKey(ghe.body, 'installed_version') ||
          _jsonHasKey(ghe.body, 'verifiable_password_authentication'))) {
    return RemoteForge.github;
  }
  return RemoteForge.unknown;
}

/// A single probe GET with short timeouts. Returns null on any transport
/// failure (DNS, refused, TLS, timeout) so the caller can move to the
/// next candidate origin or forge.
Future<({int status, String body})?> _forgeProbeGet(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('Accept', 'application/json');
    final response =
        await request.close().timeout(const Duration(seconds: 5));
    final body = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: body);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

bool _jsonHasKey(String body, String key) {
  try {
    final j = jsonDecode(body);
    return j is Map<String, dynamic> && j.containsKey(key);
  } catch (_) {
    return false;
  }
}

/// Pure classification — no I/O.
RemoteForge forgeFromUrl(String url) {
  final host = hostOfRemote(url.toLowerCase());
  if (host.contains('github')) return RemoteForge.github;
  if (host.contains('gitlab')) return RemoteForge.gitlab;
  if (host.contains('gitea') ||
      host.contains('forgejo') ||
      host == 'codeberg.org') {
    return RemoteForge.gitea;
  }
  return RemoteForge.unknown;
}

/// Extract the hostname from a git remote URL.
/// Handles SSH (`git@host:path`) and HTTPS (`https://host/path`).
String hostOfRemote(String url) {
  final m = RegExp(r'(?:@|//)([^:/]+)').firstMatch(url);
  return m?.group(1) ?? url;
}

/// Host plus explicit port from a git remote URL, when one is present.
/// HTTP(S)/SSH URLs with a `://` carry a real port after the host
/// (`https://host:3000/...`, `ssh://git@host:2222/...`). The scp-style
/// `git@host:path` form has no port — its colon introduces the path, not
/// a port — so [port] is null there. Used by forge probing so a
/// self-hosted instance on a non-default port isn't probed at 443.
({String host, int? port}) hostAndPortOfRemote(String url) {
  final trimmed = url.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    try {
      final u = Uri.parse(trimmed);
      if (u.host.isNotEmpty) {
        return (host: u.host.toLowerCase(), port: u.hasPort ? u.port : null);
      }
    } catch (_) {}
  }
  if (trimmed.startsWith('ssh://')) {
    // An ssh:// port is the SSH daemon's port (git@host:2222), never the
    // forge's HTTP port — carrying it into an API/probe URL would address
    // a non-HTTP listener. Callers building HTTP URLs from an ssh remote
    // get the host only and fall back to the scheme default.
    try {
      final u = Uri.parse(trimmed);
      if (u.host.isNotEmpty) return (host: u.host.toLowerCase(), port: null);
    } catch (_) {}
  }
  return (host: hostOfRemote(trimmed).toLowerCase(), port: null);
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
