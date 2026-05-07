import 'dart:convert';
import 'dart:io';

// Resolves the web URL of a git repository from its `origin` remote
// for the project context menu's "Open on <Host>" action. Companion
// to `remote_issue_provider.dart`'s host detection (which routes
// issue-sync to gh/glab/etc.) — same hostname dispatch, but here we
// produce a browser-openable HTTPS URL instead of choosing a
// provider implementation.
//
// Design: the gating logic is *emergent* — any remote whose URL
// normalises to a clean https form gets the action. We do NOT
// enumerate "supported" forges, because doing so silently denied
// the row to legitimate Codeberg / Gitea / sourcehut / Forgejo /
// self-hosted users. The previous whitelist (substring match on
// `github` / `gitlab` / `bitbucket`) only protected against the
// rare case of a remote that has no web counterpart at the same
// path (e.g., AWS CodeCommit). The cost of that protection
// (excluding ~half the forge ecosystem) was wildly out of
// proportion to the benefit.
//
// The label gets a tiny *cosmetic* prettifier for the three forges
// that almost every developer recognises by brand name. Everything
// else falls through to the bare host — which is informative
// (tells the user where the click goes) and, for self-hosted
// instances, more honest than misleading "Open on GitHub" when
// the host is actually `github.mycompany.com`.
//
// Failure modes (no remote, malformed URL, file:// remote) are
// silent — the caller treats null as "no row to render", which is
// the truth for many local-only repos.

/// Resolved web view of a repo. [label] is what the menu row reads
/// (e.g., "GitHub" for canonical github.com, "github.mycompany.com"
/// for an Enterprise instance, "codeberg.org" for Codeberg);
/// [webUrl] is the https URL the menu opens.
class RepoWebInfo {
  final String label;
  final String webUrl;
  const RepoWebInfo({required this.label, required this.webUrl});
}

/// Resolve the repo at [repoPath]'s `origin` remote to a web URL +
/// host label. Returns null when there's no origin or the URL can't
/// be normalised to a clean https form.
Future<RepoWebInfo?> resolveRepoWebInfo(String repoPath) async {
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
    if (url.isEmpty) return null;
    return classifyRemote(url);
  } catch (_) {
    return null;
  }
}

/// Pure classification of a remote URL → host label + https web URL.
/// Public-and-named (vs file-private) so callers that already have
/// the URL string in hand (e.g., a "Copy clone URL" action) can
/// reuse the same logic without touching disk twice.
RepoWebInfo? classifyRemote(String remoteUrl) {
  final host = hostOf(remoteUrl);
  if (host == null) return null;
  final webUrl = _toHttps(remoteUrl, host);
  if (webUrl == null) return null;
  return RepoWebInfo(
    label: _prettyHostLabel(host.toLowerCase()),
    webUrl: webUrl,
  );
}

/// Extract the hostname from a git remote URL. Handles:
///   * HTTPS / HTTP            — `https://[user[:pass]@]host[:port]/path`
///   * explicit ssh://         — `ssh://git@host[:port]/path`
///   * SSH-shorthand with user — `git@host:owner/repo.git`
///   * SSH-shorthand userless  — `host:owner/repo.git` (rare but valid)
///
/// Schemed forms are routed through [Uri.parse] so userinfo, port,
/// and path components don't pollute the captured host. SSH-shorthand
/// isn't a valid URI, so it's parsed by hand: the *first* colon
/// that's followed by a non-numeric path is the host/path separator,
/// and everything before it (minus an optional `<user>@` prefix) is
/// the host.
String? hostOf(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  // Schemed URLs — let the URI parser do the work. Returns clean
  // host with no userinfo or port.
  if (trimmed.startsWith('https://') ||
      trimmed.startsWith('http://') ||
      trimmed.startsWith('ssh://')) {
    try {
      final parsed = Uri.parse(trimmed);
      if (parsed.host.isNotEmpty) return parsed.host;
    } on FormatException {
      return null;
    }
    return null;
  }

  // Reject any other `<scheme>://...` form (file://, git://, ftp://,
  // etc.). These aren't git remotes we can map to a web view; the
  // shorthand parser below would mistakenly read the scheme as the
  // host (`file:` → host "file") and produce nonsense URLs.
  if (_otherScheme.hasMatch(trimmed)) return null;

  // SSH-shorthand: `[user@]host:path`. Strip the optional `<user>@`
  // prefix first so the regex doesn't have to alternate. The head
  // anchor on `[^/]` prevents matches from sneaking in via path
  // segments — the host segment cannot itself contain a `/`.
  var s = trimmed;
  final atIndex = s.indexOf('@');
  if (atIndex >= 0 && !s.substring(0, atIndex).contains('/')) {
    // The `@` belongs to the user-prefix only when it appears before
    // any path separator. Otherwise it's path content (e.g., a query
    // string fragment) and should be ignored.
    s = s.substring(atIndex + 1);
  }
  final m = RegExp(r'^([^:/]+):').firstMatch(s);
  return m?.group(1);
}

/// Matches any URI scheme followed by `://`. Used to reject inputs
/// that look like schemed URIs but aren't one of the three forms we
/// support (http/https/ssh). Compiled once.
final RegExp _otherScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');

/// Tiny fail-open prettifier for hosts the user almost certainly
/// recognises by brand name. Keys are the canonical public domains
/// (exact match — Enterprise instances like `github.mycompany.com`
/// fall through to bare-host display, which is more honest than
/// pretending they're public GitHub).
const Map<String, String> _prettyHostLabels = {
  'github.com': 'GitHub',
  'gitlab.com': 'GitLab',
  'bitbucket.org': 'Bitbucket',
  'codeberg.org': 'Codeberg',
  'gitea.com': 'Gitea',
};

String _prettyHostLabel(String host) =>
    _prettyHostLabels[host] ?? host;

/// Normalise [url] to an HTTPS web URL using [host] as the
/// authority. The result is *always* free of userinfo (no
/// `token@host`, no `user:pass@host`) and any explicit port —
/// these belong to the transport, not the web view, and persisting
/// credentials in browser history would be a real privacy bug.
///
/// Handles:
///   * HTTPS / HTTP — parsed with [Uri.parse], userinfo/port
///     stripped, scheme coerced to https, `.git` trimmed off the
///     path.
///   * explicit ssh:// — parsed with [Uri.parse]; same treatment.
///   * SSH-shorthand — parsed by hand because it isn't a valid URI
///     (no scheme, colon as host/path separator).
String? _toHttps(String url, String host) {
  final trimmed = url.trim();

  // Schemed URLs (https://, http://, ssh://) all flow through
  // Uri.parse so userinfo and port are guaranteed to be excluded
  // from the rebuilt URL.
  if (trimmed.startsWith('https://') ||
      trimmed.startsWith('http://') ||
      trimmed.startsWith('ssh://')) {
    Uri parsed;
    try {
      parsed = Uri.parse(trimmed);
    } on FormatException {
      return null;
    }
    if (parsed.host.isEmpty) return null;
    if (parsed.host.toLowerCase() != host.toLowerCase()) {
      // Caller's [host] is the authoritative anchor; if Uri.parse
      // disagrees the input is too malformed to trust.
      return null;
    }
    return Uri(
      scheme: 'https',
      host: parsed.host,
      // No userInfo, no port. Path retains its leading slash; if
      // the original had no path Uri.parse gives us '' which we
      // still strip dotGit safely from.
      path: _stripDotGit(parsed.path),
    ).toString();
  }

  // Reject other schemed URIs (file://, git://, …). [hostOf] also
  // rejects them and returns null, so this branch is normally
  // unreachable in production — but keep the guard so a hand-built
  // call to `_toHttps` (e.g., a future test) can't slip past it.
  if (_otherScheme.hasMatch(trimmed)) return null;

  // SSH-shorthand: `[user@]host:owner/repo[.git]`. Drop user prefix,
  // split host and path on the first colon, strip dotGit. Same
  // guard as `hostOf`: only treat the `@` as a user-prefix when it
  // appears before any path separator.
  var s = trimmed;
  final atIndex = s.indexOf('@');
  if (atIndex >= 0 && !s.substring(0, atIndex).contains('/')) {
    s = s.substring(atIndex + 1);
  }
  final colonIndex = s.indexOf(':');
  if (colonIndex < 0) return null;
  final hostPart = s.substring(0, colonIndex);
  final pathPart = s.substring(colonIndex + 1);
  if (hostPart.toLowerCase() != host.toLowerCase()) return null;
  // Path must be present and not empty.
  if (pathPart.isEmpty) return null;
  return Uri(
    scheme: 'https',
    host: hostPart,
    path: _stripDotGit('/$pathPart'),
  ).toString();
}

String _stripDotGit(String s) =>
    s.endsWith('.git') ? s.substring(0, s.length - 4) : s;
