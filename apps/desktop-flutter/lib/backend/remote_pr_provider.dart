// remote_pr_provider.dart — forge-agnostic PR sync interface
//
// Mirrors remote_issue_provider.dart for pull requests. The local
// DeskPr layer is already forge-agnostic (orphan history at
// refs/manifold/desks/<branch>). This file gives remote PR operations
// the same pluggable dispatch that issues already have.
//
// Adding a new forge:
//   1. Implement RemotePrProvider (see GhPrProvider as a template).
//   2. Add a hostname pattern in detectPrProvider().
//   3. Done — nothing else changes.
//
// Implementations:
//   GhPrProvider    — GitHub  via `gh` CLI
//   GlabPrProvider  — GitLab  via `glab` CLI (stub)
//   _NullPrProvider — local / unknown remotes — read-only no-op

import 'gh.dart' as _gh;
import 'git_result.dart';
import 'remote_types.dart';


abstract class RemotePrProvider {
  const RemotePrProvider();

  Future<RemoteProviderStatus> status(String repoPath);

  Future<GitResult<List<PullRequestSummary>>> listPullRequests(
    String repoPath, {
    String state = 'open',
    int limit = 50,
  });

  Future<GitResult<PullRequestSummary>> getPullRequest(
      String repoPath, int number);

  Future<GitResult<PullRequestDetail>> getPullRequestDetail(
    String repoPath,
    int number, {
    bool includeDiff = true,
  });

  Future<GitResult<List<CheckSummary>>> listChecks(
      String repoPath, int prNumber);

  Future<GitResult<void>> submitReview(
    String repoPath,
    int number, {
    required String event,
    String body = '',
  });

  Future<GitResult<void>> merge(
    String repoPath,
    int number, {
    required String method,
    bool deleteBranch = false,
  });

  Future<GitResult<void>> checkout(String repoPath, int number);
  Future<GitResult<void>> close(String repoPath, int number);
  Future<GitResult<void>> comment(String repoPath, int number, String body);

  Future<String> whoami();
}


Future<RemotePrProvider> detectPrProvider(String repoPath) async {
  return switch (await detectForge(repoPath)) {
    RemoteForge.github => const GhPrProvider(),
    RemoteForge.gitlab => const GlabPrProvider(),
    RemoteForge.unknown => const _NullPrProvider(),
  };
}


class GhPrProvider extends RemotePrProvider {
  const GhPrProvider();

  @override
  Future<RemoteProviderStatus> status(String repoPath) async {
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
      reason: s.authError?.isNotEmpty == true
          ? s.authError
          : 'run: gh auth login',
    );
  }

  @override
  Future<GitResult<List<PullRequestSummary>>> listPullRequests(
    String repoPath, {
    String state = 'open',
    int limit = 50,
  }) =>
      _gh.listPullRequests(repoPath, state: state, limit: limit);

  @override
  Future<GitResult<PullRequestSummary>> getPullRequest(
          String repoPath, int number) =>
      _gh.getPullRequestSummary(repoPath, number);

  @override
  Future<GitResult<PullRequestDetail>> getPullRequestDetail(
    String repoPath,
    int number, {
    bool includeDiff = true,
  }) =>
      _gh.pullRequestDetail(repoPath, number, includeDiff: includeDiff);

  @override
  Future<GitResult<List<CheckSummary>>> listChecks(
          String repoPath, int prNumber) =>
      _gh.listChecks(repoPath, prNumber);

  @override
  Future<GitResult<void>> submitReview(
    String repoPath,
    int number, {
    required String event,
    String body = '',
  }) =>
      _gh.submitPrReview(repoPath, number, event: event, body: body);

  @override
  Future<GitResult<void>> merge(
    String repoPath,
    int number, {
    required String method,
    bool deleteBranch = false,
  }) =>
      _gh.mergePullRequest(repoPath, number,
          method: method, deleteBranch: deleteBranch);

  @override
  Future<GitResult<void>> checkout(String repoPath, int number) =>
      _gh.checkoutPullRequest(repoPath, number);

  @override
  Future<GitResult<void>> close(String repoPath, int number) =>
      _gh.closePullRequest(repoPath, number);

  @override
  Future<GitResult<void>> comment(
          String repoPath, int number, String body) =>
      _gh.commentOnPullRequest(repoPath, number, body);

  @override
  Future<String> whoami() => _gh.whoami();
}


class GlabPrProvider extends RemotePrProvider {
  const GlabPrProvider();

  static const _notYet = RemoteProviderStatus(
    available: false,
    reason: 'GitLab PR sync not yet wired (glab CLI support coming)',
  );

  @override
  Future<RemoteProviderStatus> status(String _) async => _notYet;

  GitResult<T> _stub<T>() =>
      GitResult.err('GitLab PR sync not yet wired');

  @override
  Future<GitResult<List<PullRequestSummary>>> listPullRequests(
          String _, {String state = 'open', int limit = 50}) async =>
      _stub();

  @override Future<GitResult<PullRequestSummary>> getPullRequest(_, __) async => _stub();
  @override Future<GitResult<PullRequestDetail>> getPullRequestDetail(_, __, {bool includeDiff = true}) async => _stub();
  @override Future<GitResult<List<CheckSummary>>> listChecks(_, __) async => _stub();
  @override Future<GitResult<void>> submitReview(_, __, {required String event, String body = ''}) async => _stub();
  @override Future<GitResult<void>> merge(_, __, {required String method, bool deleteBranch = false}) async => _stub();
  @override Future<GitResult<void>> checkout(_, __) async => _stub();
  @override Future<GitResult<void>> close(_, __) async => _stub();
  @override Future<GitResult<void>> comment(_, __, ___) async => _stub();
  @override Future<String> whoami() async => '';
}


class _NullPrProvider extends RemotePrProvider {
  const _NullPrProvider();

  @override
  Future<RemoteProviderStatus> status(String _) async =>
      const RemoteProviderStatus(
        available: false,
        reason: 'no recognised remote PR host',
      );

  @override
  Future<GitResult<List<PullRequestSummary>>> listPullRequests(
          String _, {String state = 'open', int limit = 50}) async =>
      GitResult.ok(const []);

  GitResult<T> _noRemote<T>() =>
      GitResult.err('no remote PR host for this repo');

  @override Future<GitResult<PullRequestSummary>> getPullRequest(_, __) async => _noRemote();
  @override Future<GitResult<PullRequestDetail>> getPullRequestDetail(_, __, {bool includeDiff = true}) async => _noRemote();
  @override Future<GitResult<List<CheckSummary>>> listChecks(_, __) async => _noRemote();
  @override Future<GitResult<void>> submitReview(_, __, {required String event, String body = ''}) async => _noRemote();
  @override Future<GitResult<void>> merge(_, __, {required String method, bool deleteBranch = false}) async => _noRemote();
  @override Future<GitResult<void>> checkout(_, __) async => _noRemote();
  @override Future<GitResult<void>> close(_, __) async => _noRemote();
  @override Future<GitResult<void>> comment(_, __, ___) async => _noRemote();
  @override Future<String> whoami() async => '';
}
