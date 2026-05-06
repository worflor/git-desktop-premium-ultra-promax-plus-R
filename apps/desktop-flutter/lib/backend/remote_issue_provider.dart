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
//   GlabIssueProvider — GitLab  via `glab` CLI (stub until wired)
//   _NullIssueProvider — local / unknown remotes — read-only no-op

import 'gh.dart' as _gh;
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


Future<RemoteIssueProvider> detectIssueProvider(String repoPath) async {
  return switch (await detectForge(repoPath)) {
    RemoteForge.github => const GhIssueProvider(),
    RemoteForge.gitlab => const GlabIssueProvider(),
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

  static const _notYet = RemoteProviderStatus(
    available: false,
    reason: 'GitLab sync not yet wired (glab CLI support coming)',
  );

  @override
  Future<RemoteProviderStatus> status(String _) async => _notYet;

  GitResult<T> _stub<T>() =>
      GitResult.err('GitLab sync not yet wired');

  @override
  Future<GitResult<List<IssueSummary>>> listIssues(String _, {String state = 'open', int limit = 100}) async =>
      _stub();

  @override Future<GitResult<IssueSummary>> getIssue(_, __) async => _stub();
  @override Future<GitResult<IssueDetail>> getIssueDetail(_, __) async => _stub();
  @override Future<GitResult<int>> createIssue(_, {required String title, String body = '', List<String> labels = const [], List<String> assignees = const []}) async => _stub();
  @override Future<GitResult<void>> editIssue(_, __, {String? title, String? body, List<String> addLabels = const [], List<String> removeLabels = const []}) async => _stub();
  @override Future<GitResult<void>> closeIssue(_, __) async => _stub();
  @override Future<GitResult<void>> reopenIssue(_, __) async => _stub();
  @override Future<GitResult<void>> addComment(_, __, ___) async => _stub();
  @override Future<GitResult<void>> assignSelf(_, __) async => _stub();
  @override Future<GitResult<void>> addLabel(_, __, ___) async => _stub();
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
