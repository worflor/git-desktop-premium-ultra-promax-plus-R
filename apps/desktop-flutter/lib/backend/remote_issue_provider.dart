// ═════════════════════════════════════════════════════════════════════════
// remote_issue_provider.dart — forge-agnostic issue sync interface
//
// The local DeskIssue layer is already forge-agnostic: issues are stored
// as orphan commit trees in refs/manifold/issues/<id> — pure git, works
// on any host or with no remote at all.
//
// This file extends that agnosticism to remote sync operations. The
// abstraction is thin: one abstract class, one factory function that
// reads `git remote get-url origin` and returns the right implementation.
//
// Adding a new forge (Gitea, Bitbucket, Forgejo, …):
//   1. Implement RemoteIssueProvider (see GhIssueProvider as a template).
//   2. Add a URL pattern in detectProvider().
//   3. Done — nothing else changes.
//
// Implementations today:
//   GhIssueProvider   — GitHub  via `gh` CLI
//   GlabIssueProvider — GitLab  via `glab` CLI (stub until wired)
//   _NullIssueProvider — local / unknown remotes — read-only no-op
// ═════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'gh.dart' as _gh;
import 'git_result.dart';

// ── Shared result types ───────────────────────────────────────────────────
//
// IssueSummary / IssueDetail are defined in gh.dart but contain no
// GitHub-specific fields — they're just the canonical DTO shape for an
// issue across all providers. We re-export them here so callers can import
// from this file alone.
//
// If a future provider needs a different wire shape, map it onto these
// types inside its implementation — keep the interface stable.

export 'gh.dart' show IssueSummary, IssueDetail;

// ── Status ────────────────────────────────────────────────────────────────

class RemoteProviderStatus {
  final bool available;

  /// Human-readable reason when [available] is false — e.g. install hint,
  /// auth instructions. Null when available.
  final String? reason;

  const RemoteProviderStatus({required this.available, this.reason});

  static const yes = RemoteProviderStatus(available: true);
}

// ── Abstract interface ────────────────────────────────────────────────────

abstract class RemoteIssueProvider {
  const RemoteIssueProvider();

  /// Check tooling availability and authentication for [repoPath].
  /// Cheap to call; cache the result on the state side.
  Future<RemoteProviderStatus> status(String repoPath);

  Future<GitResult<List<_gh.IssueSummary>>> listIssues(
    String repoPath, {
    String state = 'open',
    int limit = 100,
  });

  Future<GitResult<_gh.IssueSummary>> getIssue(String repoPath, int number);

  Future<GitResult<_gh.IssueDetail>> getIssueDetail(
      String repoPath, int number);

  /// Create a new issue on the remote. Returns the remote issue number.
  Future<GitResult<int>> createIssue(
    String repoPath, {
    required String title,
    String body = '',
    List<String> labels = const [],
    List<String> assignees = const [],
  });

  Future<GitResult<void>> editIssue(
    String repoPath,
    int number, {
    String? title,
    String? body,
    List<String> addLabels = const [],
    List<String> removeLabels = const [],
  });

  Future<GitResult<void>> closeIssue(String repoPath, int number);
  Future<GitResult<void>> reopenIssue(String repoPath, int number);
  Future<GitResult<void>> addComment(String repoPath, int number, String body);
}

// ── Detection factory ─────────────────────────────────────────────────────

/// Resolves the best [RemoteIssueProvider] for [repoPath] by inspecting
/// the `origin` remote URL's hostname.
///
/// Detection is a single `git remote get-url origin` call — cache the
/// result per repo-change to avoid repeated spawns.
///
/// Hostname matching (rather than substring on the full URL) correctly
/// handles:
///   • https://github.com/u/r           → github
///   • git@github.com:u/r.git           → github (SSH form)
///   • https://github.mycompany.com/u/r → github (Enterprise)
///   • https://my-gitlab.example.com/u  → gitlab (self-hosted)
Future<RemoteIssueProvider> detectProvider(String repoPath) async {
  try {
    final r = await Process.run(
      'git',
      ['remote', 'get-url', 'origin'],
      workingDirectory: repoPath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) return const _NullIssueProvider();
    final url = (r.stdout as String).trim().toLowerCase();
    final host = _hostOf(url);

    if (host.contains('github')) return const GhIssueProvider();
    if (host.contains('gitlab')) return const GlabIssueProvider();
    // Extend here: Gitea, Bitbucket, Forgejo, …

    return const _NullIssueProvider();
  } catch (_) {
    return const _NullIssueProvider();
  }
}

/// Extract the hostname portion of a git remote URL.
/// Handles both SSH (`git@host:path`) and HTTPS (`https://host/path`) forms.
///
/// The alternation anchors on `@` (SSH) or `//` (HTTPS) — never `^`.
/// Using `^` as an alternative would match at position 0 with zero width,
/// causing `firstMatch` to capture the URL scheme instead of the hostname.
String _hostOf(String url) {
  final m = RegExp(r'(?:@|//)([^:/]+)').firstMatch(url);
  return m?.group(1) ?? url;
}

// ── GitHub — via `gh` CLI ─────────────────────────────────────────────────

class GhIssueProvider extends RemoteIssueProvider {
  const GhIssueProvider();

  @override
  Future<RemoteProviderStatus> status(String _repoPath) async {
    final s = await _gh.ghStatus();
    if (s.usable) return RemoteProviderStatus.yes;
    if (!s.installed) {
      return const RemoteProviderStatus(
        available: false,
        reason: 'gh CLI not installed — run: winget install GitHub.cli',
      );
    }
    return RemoteProviderStatus(
      available: false,
      reason: s.authError?.isNotEmpty == true ? s.authError : 'run: gh auth login',
    );
  }

  @override
  Future<GitResult<List<_gh.IssueSummary>>> listIssues(
    String repoPath, {
    String state = 'open',
    int limit = 100,
  }) =>
      _gh.listIssues(repoPath, state: state, limit: limit);

  @override
  Future<GitResult<_gh.IssueSummary>> getIssue(
          String repoPath, int number) =>
      _gh.getIssueSummary(repoPath, number);

  @override
  Future<GitResult<_gh.IssueDetail>> getIssueDetail(
          String repoPath, int number) =>
      _gh.issueDetail(repoPath, number);

  @override
  Future<GitResult<int>> createIssue(
    String repoPath, {
    required String title,
    String body = '',
    List<String> labels = const [],
    List<String> assignees = const [],
  }) =>
      _gh.createGhIssue(repoPath,
          title: title, body: body, labels: labels, assignees: assignees);

  @override
  Future<GitResult<void>> editIssue(
    String repoPath,
    int number, {
    String? title,
    String? body,
    List<String> addLabels = const [],
    List<String> removeLabels = const [],
  }) =>
      _gh.editGhIssue(repoPath, number,
          title: title,
          body: body,
          addLabels: addLabels,
          removeLabels: removeLabels);

  @override
  Future<GitResult<void>> closeIssue(String repoPath, int number) =>
      _gh.closeIssue(repoPath, number);

  @override
  Future<GitResult<void>> reopenIssue(String repoPath, int number) =>
      _gh.reopenGhIssue(repoPath, number);

  @override
  Future<GitResult<void>> addComment(
          String repoPath, int number, String body) =>
      _gh.commentOnIssue(repoPath, number, body);
}

// ── GitLab — via `glab` CLI ───────────────────────────────────────────────
//
// Stub: returns available=false until glab wrappers are added.
// The interface is already complete — wire up when needed.

class GlabIssueProvider extends RemoteIssueProvider {
  const GlabIssueProvider();

  static const _notYet = RemoteProviderStatus(
    available: false,
    reason: 'GitLab sync not yet wired (glab CLI support coming)',
  );

  @override
  Future<RemoteProviderStatus> status(String _) async => _notYet;

  GitResult<T> _stub<T>() =>
      GitResult.err('GitLab sync not yet wired');

  @override
  Future<GitResult<List<_gh.IssueSummary>>> listIssues(String _, {String state = 'open', int limit = 100}) async =>
      _stub();

  @override Future<GitResult<_gh.IssueSummary>> getIssue(_, __) async => _stub();
  @override Future<GitResult<_gh.IssueDetail>> getIssueDetail(_, __) async => _stub();
  @override Future<GitResult<int>> createIssue(_, {required String title, String body = '', List<String> labels = const [], List<String> assignees = const []}) async => _stub();
  @override Future<GitResult<void>> editIssue(_, __, {String? title, String? body, List<String> addLabels = const [], List<String> removeLabels = const []}) async => _stub();
  @override Future<GitResult<void>> closeIssue(_, __) async => _stub();
  @override Future<GitResult<void>> reopenIssue(_, __) async => _stub();
  @override Future<GitResult<void>> addComment(_, __, ___) async => _stub();
}

// ── Null provider — local repos / unrecognised remotes ───────────────────
//
// List ops return empty (local issues still work fine).
// Write ops return an error so callers can surface a sensible message.

class _NullIssueProvider extends RemoteIssueProvider {
  const _NullIssueProvider();

  @override
  Future<RemoteProviderStatus> status(String _) async =>
      const RemoteProviderStatus(
        available: false,
        reason: 'no recognised remote issue host',
      );

  @override
  Future<GitResult<List<_gh.IssueSummary>>> listIssues(String _, {String state = 'open', int limit = 100}) async =>
      GitResult.ok(const []);

  GitResult<T> _noRemote<T>() =>
      GitResult.err('no remote issue host for this repo');

  @override Future<GitResult<_gh.IssueSummary>> getIssue(_, __) async => _noRemote();
  @override Future<GitResult<_gh.IssueDetail>> getIssueDetail(_, __) async => _noRemote();
  @override Future<GitResult<int>> createIssue(_, {required String title, String body = '', List<String> labels = const [], List<String> assignees = const []}) async => _noRemote();
  @override Future<GitResult<void>> editIssue(_, __, {String? title, String? body, List<String> addLabels = const [], List<String> removeLabels = const []}) async => _noRemote();
  @override Future<GitResult<void>> closeIssue(_, __) async => _noRemote();
  @override Future<GitResult<void>> reopenIssue(_, __) async => _noRemote();
  @override Future<GitResult<void>> addComment(_, __, ___) async => _noRemote();
}
