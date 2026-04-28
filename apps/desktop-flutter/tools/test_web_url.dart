// One-shot diagnostic: walk a directory tree, find every git repo,
// run BOTH the current whitelist-based classifier and the proposed
// emergent (bare-host) variant against each remote URL, print a
// side-by-side comparison.
//
// Usage:
//   dart run tools/test_web_url.dart [root-dir]
//
// Default root is the parent's parent of cwd (typically the user's
// Projects folder when run from apps/desktop-flutter).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/backend/repo_web_url.dart' show resolveRepoWebInfo;

const int _maxDepth = 4;

Future<void> main(List<String> args) async {
  final root = args.isNotEmpty
      ? args[0]
      // Default: ../../  from desktop-flutter — i.e., the Projects dir.
      : Directory.current.parent.parent.path;
  stderr.writeln('Scanning $root (max depth $_maxDepth) for git repos…');
  final repos = await _findRepos(root, _maxDepth);
  stderr.writeln('Found ${repos.length} repo(s).\n');

  // Header
  print('| repo | remote URL | CURRENT | EMERGENT | web URL |');
  print('|---|---|---|---|---|');

  // Process in parallel — each row is a `git remote get-url` + two
  // classifications. Network-free; should be fast.
  final rows = await Future.wait(repos.map(_processRepo));
  for (final row in rows) {
    print(row);
  }

  stderr.writeln('\nLegend:');
  stderr.writeln('  CURRENT  = today\'s whitelist: github / gitlab / bitbucket only');
  stderr.writeln('  EMERGENT = bare host as label, any clean https URL renders');
  stderr.writeln('  "<no row>" = the row is hidden in that variant');

  // Synthetic test set — covers shapes you may not have on disk but
  // are common in the wild. Demonstrates where the variants diverge.
  print('\n## synthetic test cases\n');
  print('| remote URL | CURRENT | EMERGENT | web URL |');
  print('|---|---|---|---|');
  final synthetic = [
    // SSH-shorthand variants
    'git@github.com:owner/repo.git',
    'git@gitlab.com:group/project.git',
    'git@bitbucket.org:team/repo.git',
    // Recognized brands self-hosted (Enterprise / on-prem)
    'https://github.mycompany.com/team/internal.git',
    'https://gitlab.internal.example/group/x.git',
    // Forges currently locked out by the whitelist
    'https://codeberg.org/owner/repo.git',
    'git@codeberg.org:owner/repo.git',
    'https://git.sr.ht/~user/project',
    'https://gitea.example.com/owner/repo.git',
    'https://forgejo.example.com/owner/repo',
    // Azure DevOps — has a web view at the same URL
    'https://dev.azure.com/org/project/_git/repo',
    // Personal git server
    'https://git.mycompany.dev/owner/repo.git',
    'git@git.someone.dev:owner/repo.git',
    // ssh:// explicit form with port
    'ssh://git@git.foo.dev:2222/owner/repo.git',
    // SSH-shorthand userless form (rare but valid — direct host:path)
    'github.com:owner/repo.git',
    'codeberg.org:owner/repo.git',
    // AWS CodeCommit — no useful web at this URL (cautionary case)
    'https://git-codecommit.us-east-1.amazonaws.com/v1/repos/myrepo',
    // A non-git scheme — should be skipped by both
    'file:///tmp/local-only',
  ];
  for (final url in synthetic) {
    final current = _classifyCurrent(url);
    final emergent = _emergentResolve(url);
    final cl = current == null ? '<no row>' : 'Open on ${current.label}';
    final el =
        emergent == null ? '<no row>' : 'Open on ${emergent.host}';
    final web = emergent?.webUrl ?? current?.webUrl ?? '—';
    print('| `$url` | $cl | $el | $web |');
  }
}

/// Replica of the production whitelist classifier so we can run it
/// against synthetic URLs without touching disk. Keep in sync with
/// `lib/backend/repo_web_url.dart`.
class _CurrentInfo {
  final String label;
  final String webUrl;
  const _CurrentInfo({required this.label, required this.webUrl});
}

_CurrentInfo? _classifyCurrent(String url) {
  final host = _hostOf(url);
  if (host == null) return null;
  final lh = host.toLowerCase();
  String? label;
  if (lh.contains('github')) {
    label = 'GitHub';
  } else if (lh.contains('gitlab')) {
    label = 'GitLab';
  } else if (lh.contains('bitbucket')) {
    label = 'Bitbucket';
  }
  if (label == null) return null;
  final web = _toHttps(url, host);
  if (web == null) return null;
  return _CurrentInfo(label: label, webUrl: web);
}

/// Walk [root] up to [maxDepth] levels, returning every directory
/// that contains a `.git` subdir (real repo) or that *is* a `.git`
/// dir's parent. Skips nested node_modules / build / .pub-cache to
/// keep the walk fast.
Future<List<String>> _findRepos(String root, int maxDepth) async {
  final results = <String>[];
  final rootDir = Directory(root);
  if (!await rootDir.exists()) {
    stderr.writeln('Root does not exist: $root');
    return results;
  }
  await _walk(rootDir, 0, maxDepth, results);
  results.sort();
  return results;
}

const _skipNames = {
  'node_modules',
  'build',
  '.pub-cache',
  '.gradle',
  '.dart_tool',
  'target', // rust
  '__pycache__',
  '.venv',
  'venv',
};

Future<void> _walk(
  Directory dir,
  int depth,
  int maxDepth,
  List<String> out,
) async {
  if (depth > maxDepth) return;
  // Check if this dir itself is a repo (has .git child).
  final dotGit = Directory('${dir.path}${Platform.pathSeparator}.git');
  if (await dotGit.exists()) {
    out.add(dir.path);
    return; // Don't descend into the repo — we don't want submodules
            // double-counted under the parent's subtree. Submodules
            // are still legit independent repos but for this audit
            // we want the user-visible "projects" list.
  }
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue; // skip hidden, including .git
      if (_skipNames.contains(name)) continue;
      await _walk(entity, depth + 1, maxDepth, out);
    }
  } catch (_) {
    // permission denied / transient — skip silently
  }
}

Future<String> _processRepo(String path) async {
  final remote = await _getRemote(path);
  final repoName = path.split(Platform.pathSeparator).last;
  if (remote == null || remote.isEmpty) {
    return '| $repoName | _(no origin)_ | <no row> | <no row> | — |';
  }
  // Current whitelist-based classifier (lives in lib/).
  final current = await resolveRepoWebInfo(path);
  // Emergent variant: bare-host label, any clean https URL.
  final emergent = _emergentResolve(remote);
  final currentLabel = current == null ? '<no row>' : 'Open on ${current.label}';
  final emergentLabel =
      emergent == null ? '<no row>' : 'Open on ${emergent.host}';
  final webUrl = emergent?.webUrl ?? current?.webUrl ?? '—';
  return '| $repoName | `$remote` | $currentLabel | $emergentLabel | $webUrl |';
}

Future<String?> _getRemote(String repoPath) async {
  try {
    final r = await Process.run(
      'git',
      ['remote', 'get-url', 'origin'],
      workingDirectory: repoPath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) return null;
    return (r.stdout as String).trim();
  } catch (_) {
    return null;
  }
}

class _EmergentInfo {
  final String host;
  final String webUrl;
  const _EmergentInfo({required this.host, required this.webUrl});
}

/// Emergent variant: extract the host, normalise SSH/HTTPS to a
/// clean web URL, and use the host *itself* as the label. No
/// whitelist — any git remote with a derivable https form gets the
/// row. Mirrors the structural URL parsing in `repo_web_url.dart`
/// minus the brand check.
_EmergentInfo? _emergentResolve(String remoteUrl) {
  final host = _hostOf(remoteUrl);
  if (host == null) return null;
  final webUrl = _toHttps(remoteUrl, host);
  if (webUrl == null) return null;
  return _EmergentInfo(host: host.toLowerCase(), webUrl: webUrl);
}

String? _hostOf(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
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
  // SSH shorthand — handle both `user@host:path` and userless
  // `host:path` forms.
  var s = trimmed;
  final atIndex = s.indexOf('@');
  if (atIndex >= 0 && !s.substring(0, atIndex).contains('/')) {
    s = s.substring(atIndex + 1);
  }
  final m = RegExp(r'^([^:/]+):').firstMatch(s);
  return m?.group(1);
}

String? _toHttps(String url, String host) {
  final trimmed = url.trim();
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
    if (parsed.host.toLowerCase() != host.toLowerCase()) return null;
    return Uri(
      scheme: 'https',
      host: parsed.host,
      path: _stripDotGit(parsed.path),
    ).toString();
  }
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(trimmed)) return null;
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
  if (pathPart.isEmpty) return null;
  return Uri(
    scheme: 'https',
    host: hostPart,
    path: _stripDotGit('/$pathPart'),
  ).toString();
}

String _stripDotGit(String s) =>
    s.endsWith('.git') ? s.substring(0, s.length - 4) : s;
