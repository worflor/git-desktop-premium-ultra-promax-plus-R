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
//   2. Add a URL pattern in detectIssueProvider().
//   3. Done — nothing else changes.
//
// Implementations today:
//   GhIssueProvider   — GitHub  via `gh` CLI
//   GlabIssueProvider — GitLab  via `glab` CLI
//   _NullIssueProvider — local / unknown remotes — read-only no-op

import 'gh.dart' as _gh;
import 'gitea_api.dart' as _gitea;
import 'glab.dart' as _glab;
import 'git_result.dart';
import 'remote_types.dart';

export 'remote_types.dart' show IssueSummary, IssueDetail;


abstract class RemoteIssueProvider {
  const RemoteIssueProvider();

  Future<RemoteProviderStatus> status(String repoPath);

  Future<GitResult<List<IssueSummary>>> listIssues(
    String repoPath, {
    String state = 'open',
    int limit = 100,
  });

  Future<GitResult<IssueSummary>> getIssue(String repoPath, int number);

  Future<GitResult<IssueDetail>> getIssueDetail(
      String repoPath, int number);

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
  Future<GitResult<void>> assignSelf(String repoPath, int number);
  Future<GitResult<void>> addLabel(String repoPath, int number, String label);
}


Future<RemoteIssueProvider> detectIssueProvider(String repoPath, {RemoteForge? forge}) async {
  forge ??= await detectForge(repoPath);
  return switch (forge) {
    RemoteForge.github => const GhIssueProvider(),
    RemoteForge.gitlab => const GlabIssueProvider(),
    RemoteForge.gitea => const GiteaIssueProvider(),
    RemoteForge.unknown => const _NullIssueProvider(),
  };
}


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
  Future<GitResult<List<IssueSummary>>> listIssues(
    String repoPath, {
    String state = 'open',
    int limit = 100,
  }) =>
      _gh.listIssues(repoPath, state: state, limit: limit);

  @override
  Future<GitResult<IssueSummary>> getIssue(
          String repoPath, int number) =>
      _gh.getIssueSummary(repoPath, number);

  @override
  Future<GitResult<IssueDetail>> getIssueDetail(
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

  @override
  Future<GitResult<void>> assignSelf(String repoPath, int number) =>
      _gh.assignSelfToIssue(repoPath, number);

  @override
  Future<GitResult<void>> addLabel(
          String repoPath, int number, String label) =>
      _gh.addIssueLabel(repoPath, number, label);
}


class GlabIssueProvider extends RemoteIssueProvider {
  const GlabIssueProvider();

  @override
  Future<RemoteProviderStatus> status(String _repoPath) async {
    final s = await _glab.glabStatus();
    if (s.usable) return RemoteProviderStatus.yes;
    if (!s.installed) {
      return const RemoteProviderStatus(
        available: false,
        reason: 'glab CLI not installed — run: winget install glab',
      );
    }
    return RemoteProviderStatus(
      available: false,
      reason: s.authError?.isNotEmpty == true ? s.authError : 'run: glab auth login',
    );
  }

  @override
  Future<GitResult<List<IssueSummary>>> listIssues(
    String repoPath, {
    String state = 'open',
    int limit = 100,
  }) =>
      _glab.listGlabIssues(repoPath,
          state: state == 'open' ? 'opened' : state, limit: limit);

  @override
  Future<GitResult<IssueSummary>> getIssue(String repoPath, int number) =>
      _glab.getGlabIssue(repoPath, number);

  @override
  Future<GitResult<IssueDetail>> getIssueDetail(String repoPath, int number) =>
      _glab.glabIssueDetail(repoPath, number);

  @override
  Future<GitResult<int>> createIssue(
    String repoPath, {
    required String title,
    String body = '',
    List<String> labels = const [],
    List<String> assignees = const [],
  }) =>
      _glab.createGlabIssue(repoPath,
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
      _glab.editGlabIssue(repoPath, number,
          title: title, body: body, addLabels: addLabels, removeLabels: removeLabels);

  @override
  Future<GitResult<void>> closeIssue(String repoPath, int number) =>
      _glab.closeGlabIssue(repoPath, number);

  @override
  Future<GitResult<void>> reopenIssue(String repoPath, int number) =>
      _glab.reopenGlabIssue(repoPath, number);

  @override
  Future<GitResult<void>> addComment(String repoPath, int number, String body) =>
      _glab.commentOnGlabIssue(repoPath, number, body);

  @override
  Future<GitResult<void>> assignSelf(String repoPath, int number) =>
      _glab.assignSelfToGlabIssue(repoPath, number);

  @override
  Future<GitResult<void>> addLabel(String repoPath, int number, String label) =>
      _glab.addGlabIssueLabel(repoPath, number, label);
}


class GiteaIssueProvider extends RemoteIssueProvider {
  const GiteaIssueProvider();

  @override
  Future<RemoteProviderStatus> status(String repoPath) async {
    final coords = await _gitea.resolveGiteaCoords(repoPath);
    if (coords == null) {
      return const RemoteProviderStatus(
        available: false,
        reason: 'could not resolve Gitea/Forgejo API URL',
      );
    }
    final s = await _gitea.giteaApiStatus(coords.apiBase);
    if (!s.reachable) {
      return RemoteProviderStatus(available: false, reason: s.reason);
    }
    return RemoteProviderStatus.yes;
  }

  @override
  Future<GitResult<List<IssueSummary>>> listIssues(
    String repoPath, {
    String state = 'open',
    int limit = 100,
  }) =>
      _gitea.listGiteaIssues(repoPath, state: state, limit: limit);

  @override
  Future<GitResult<IssueSummary>> getIssue(String repoPath, int number) =>
      _gitea.getGiteaIssue(repoPath, number);

  @override
  Future<GitResult<IssueDetail>> getIssueDetail(String repoPath, int number) =>
      _gitea.giteaIssueDetail(repoPath, number);

  @override
  Future<GitResult<int>> createIssue(
    String repoPath, {
    required String title,
    String body = '',
    List<String> labels = const [],
    List<String> assignees = const [],
  }) =>
      _gitea.createGiteaIssue(repoPath,
          title: title, body: body, labels: labels, assignees: assignees);

  @override
  Future<GitResult<void>> editIssue(
    String repoPath,
    int number, {
    String? title,
    String? body,
    List<String> addLabels = const [],
    List<String> removeLabels = const [],
  }) async {
    final r = await _gitea.editGiteaIssue(repoPath, number, title: title, body: body);
    if (!r.ok) return r;
    for (final label in addLabels) {
      await _gitea.addGiteaIssueLabel(repoPath, number, label);
    }
    return const GitResult.ok(null);
  }

  @override
  Future<GitResult<void>> closeIssue(String repoPath, int number) =>
      _gitea.closeGiteaIssue(repoPath, number);

  @override
  Future<GitResult<void>> reopenIssue(String repoPath, int number) =>
      _gitea.reopenGiteaIssue(repoPath, number);

  @override
  Future<GitResult<void>> addComment(String repoPath, int number, String body) =>
      _gitea.giteaCommentOnIssue(repoPath, number, body);

  @override
  Future<GitResult<void>> assignSelf(String repoPath, int number) =>
      _gitea.assignSelfToGiteaIssue(repoPath, number);

  @override
  Future<GitResult<void>> addLabel(String repoPath, int number, String label) =>
      _gitea.addGiteaIssueLabel(repoPath, number, label);
}


class _NullIssueProvider extends RemoteIssueProvider {
  const _NullIssueProvider();

  @override
  Future<RemoteProviderStatus> status(String _) async =>
      const RemoteProviderStatus(
        available: false,
        reason: 'no recognised remote issue host',
      );

  @override
  Future<GitResult<List<IssueSummary>>> listIssues(String _, {String state = 'open', int limit = 100}) async =>
      GitResult.ok(const []);

  GitResult<T> _noRemote<T>() =>
      GitResult.err('no remote issue host for this repo');

  @override Future<GitResult<IssueSummary>> getIssue(_, __) async => _noRemote();
  @override Future<GitResult<IssueDetail>> getIssueDetail(_, __) async => _noRemote();
  @override Future<GitResult<int>> createIssue(_, {required String title, String body = '', List<String> labels = const [], List<String> assignees = const []}) async => _noRemote();
  @override Future<GitResult<void>> editIssue(_, __, {String? title, String? body, List<String> addLabels = const [], List<String> removeLabels = const []}) async => _noRemote();
  @override Future<GitResult<void>> closeIssue(_, __) async => _noRemote();
  @override Future<GitResult<void>> reopenIssue(_, __) async => _noRemote();
  @override Future<GitResult<void>> addComment(_, __, ___) async => _noRemote();
  @override Future<GitResult<void>> assignSelf(_, __) async => _noRemote();
  @override Future<GitResult<void>> addLabel(_, __, ___) async => _noRemote();
}
