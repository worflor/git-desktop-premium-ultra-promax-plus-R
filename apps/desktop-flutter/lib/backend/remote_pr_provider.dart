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

import 'dart:convert';
import 'dart:io';

import 'gh.dart' as _gh;
import 'gitea_api.dart' as _gitea;
import 'glab.dart' as _glab;
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

  /// Forge-specific refspec for fetching a remote PR/MR head.
  /// GitHub: `pull/<n>/head`, GitLab: `merge-requests/<n>/head`.
  String fetchRefspec(int number);

  Future<String> whoami();
}


Future<RemotePrProvider> detectPrProvider(String repoPath, {RemoteForge? forge}) async {
  forge ??= await detectForge(repoPath);
  return switch (forge) {
    RemoteForge.github => const GhPrProvider(),
    RemoteForge.gitlab => const GlabPrProvider(),
    RemoteForge.gitea => const GiteaPrProvider(),
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
  String fetchRefspec(int number) => 'pull/$number/head';

  @override
  Future<String> whoami() => _gh.whoami();
}


class GlabPrProvider extends RemotePrProvider {
  const GlabPrProvider();

  @override
  Future<RemoteProviderStatus> status(String repoPath) async {
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
      reason: s.authError?.isNotEmpty == true
          ? s.authError
          : 'run: glab auth login',
    );
  }

  @override
  Future<GitResult<List<PullRequestSummary>>> listPullRequests(
    String repoPath, {
    String state = 'open',
    int limit = 50,
  }) =>
      _glab.listMergeRequests(repoPath,
          state: state == 'open' ? 'opened' : state, limit: limit);

  @override
  Future<GitResult<PullRequestSummary>> getPullRequest(
          String repoPath, int number) =>
      _glab.getMergeRequest(repoPath, number);

  @override
  Future<GitResult<PullRequestDetail>> getPullRequestDetail(
    String repoPath,
    int number, {
    bool includeDiff = true,
  }) =>
      _glab.mergeRequestDetail(repoPath, number, includeDiff: includeDiff);

  @override
  Future<GitResult<List<CheckSummary>>> listChecks(
          String repoPath, int prNumber) =>
      _glab.listMrPipelines(repoPath, prNumber);

  @override
  Future<GitResult<void>> submitReview(
    String repoPath,
    int number, {
    required String event,
    String body = '',
  }) =>
      _glab.submitMrReview(repoPath, number, event: event, body: body);

  @override
  Future<GitResult<void>> merge(
    String repoPath,
    int number, {
    required String method,
    bool deleteBranch = false,
  }) =>
      _glab.mergeMr(repoPath, number,
          method: method, deleteBranch: deleteBranch);

  @override
  Future<GitResult<void>> checkout(String repoPath, int number) =>
      _glab.checkoutMr(repoPath, number);

  @override
  Future<GitResult<void>> close(String repoPath, int number) =>
      _glab.closeMr(repoPath, number);

  @override
  Future<GitResult<void>> comment(
          String repoPath, int number, String body) =>
      _glab.commentOnMr(repoPath, number, body);

  @override
  String fetchRefspec(int number) => 'merge-requests/$number/head';

  @override
  Future<String> whoami() => _glab.glabWhoami();
}


class GiteaPrProvider extends RemotePrProvider {
  const GiteaPrProvider();

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
  Future<GitResult<List<PullRequestSummary>>> listPullRequests(
    String repoPath, {
    String state = 'open',
    int limit = 50,
  }) async {
      await _ensureLogin(repoPath);
      return _gitea.listGiteaPulls(repoPath, state: state, limit: limit);
  }

  @override
  Future<GitResult<PullRequestSummary>> getPullRequest(
          String repoPath, int number) =>
      _gitea.getGiteaPull(repoPath, number);

  @override
  Future<GitResult<PullRequestDetail>> getPullRequestDetail(
    String repoPath,
    int number, {
    bool includeDiff = true,
  }) =>
      _gitea.giteaPullDetail(repoPath, number, includeDiff: includeDiff);

  @override
  Future<GitResult<List<CheckSummary>>> listChecks(
          String repoPath, int prNumber) =>
      _gitea.listGiteaCommitStatuses(repoPath, prNumber);

  @override
  Future<GitResult<void>> submitReview(
    String repoPath,
    int number, {
    required String event,
    String body = '',
  }) =>
      _gitea.giteaApprovePull(repoPath, number, event: event, body: body);

  @override
  Future<GitResult<void>> merge(
    String repoPath,
    int number, {
    required String method,
    bool deleteBranch = false,
  }) =>
      _gitea.giteaMergePull(repoPath, number,
          method: method, deleteBranch: deleteBranch);

  @override
  Future<GitResult<void>> checkout(String repoPath, int number) async {
    // Pure git — fetch the PR head and checkout locally.
    final refspec = fetchRefspec(number);
    final localRef = 'pr-$number';
    final r = await Process.run(
      'git', ['fetch', 'origin', '+$refspec:$localRef'],
      workingDirectory: repoPath,
      stdoutEncoding: utf8, stderrEncoding: utf8,
    );
    if (r.exitCode != 0) return GitResult.err((r.stderr as String).trim());
    final co = await Process.run(
      'git', ['checkout', localRef],
      workingDirectory: repoPath,
      stdoutEncoding: utf8, stderrEncoding: utf8,
    );
    if (co.exitCode != 0) return GitResult.err((co.stderr as String).trim());
    return const GitResult.ok(null);
  }

  @override
  Future<GitResult<void>> close(String repoPath, int number) =>
      _gitea.closeGiteaPull(repoPath, number);

  @override
  Future<GitResult<void>> comment(
          String repoPath, int number, String body) =>
      _gitea.giteaCommentOnIssue(repoPath, number, body);

  @override
  String fetchRefspec(int number) => 'pull/$number/head';

  @override
  Future<String> whoami() async => _cachedLogin;

  static String _cachedLogin = '';
  static String _cachedForHost = '';

  static void clearCachedLogin() {
    _cachedLogin = '';
    _cachedForHost = '';
  }

  Future<void> _ensureLogin(String repoPath) async {
    final coords = await _gitea.resolveGiteaCoords(repoPath);
    final host = coords?.apiBase ?? '';
    if (_cachedLogin.isNotEmpty && _cachedForHost == host) return;
    _cachedForHost = host;
    _cachedLogin = await _gitea.giteaWhoami(repoPath);
  }
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
  @override String fetchRefspec(int number) => '';
  @override Future<String> whoami() async => '';
}
