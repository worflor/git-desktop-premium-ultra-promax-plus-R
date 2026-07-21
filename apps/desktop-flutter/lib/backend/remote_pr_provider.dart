// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

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

import 'gh.dart' as gh;
import 'git.dart' as git;
import 'gitea_api.dart' as gitea;
import 'glab.dart' as glab;
import 'git_result.dart';
import 'remote_types.dart';


/// Outcome of a unified PR-head checkout.
///
/// Sealed so the would-clobber case is a first-class, exhaustively-matched
/// state rather than a sentinel string the caller has to sniff for. A local
/// `pr-<n>` that carries commits unreachable from the freshly-fetched remote
/// head would be silently destroyed by a force-update; [PrCheckoutWouldClobber]
/// surfaces that to the UI so it can confirm before clobbering.
sealed class PrCheckoutOutcome {
  const PrCheckoutOutcome();
}

/// The PR head was fetched and `pr-<n>` is checked out at it.
final class PrCheckoutOk extends PrCheckoutOutcome {
  const PrCheckoutOk();
}

/// The checkout could not complete. [error] is a human-readable reason.
final class PrCheckoutFailed extends PrCheckoutOutcome {
  final String error;
  const PrCheckoutFailed(this.error);
}

/// A local `pr-<n>` exists with commits NOT reachable from the fetched remote
/// head, so updating it would strand those commits. On the pure-git path the
/// fetch only landed the remote objects (in FETCH_HEAD) and nothing local was
/// touched. On the CLI-fallback path the forge CLI has already switched HEAD as
/// part of its fetch+checkout, so before returning this outcome we restore the
/// original checkout (the branch/sha snapshotted before the CLI ran) — so a
/// user who cancels the confirm dialog is left exactly where they started on
/// either path. Callers may confirm with the user and re-invoke with
/// `force: true`.
final class PrCheckoutWouldClobber extends PrCheckoutOutcome {
  final String localRef;
  final String localTip;
  final String remoteTip;
  const PrCheckoutWouldClobber({
    required this.localRef,
    required this.localTip,
    required this.remoteTip,
  });
}


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

  Future<PrCheckoutOutcome> checkout(String repoPath, int number,
      {bool force = false});
  Future<GitResult<void>> close(String repoPath, int number);
  Future<GitResult<void>> comment(String repoPath, int number, String body);

  Future<GitResult<int>> createPullRequest(
    String repoPath, {
    required String title,
    String body = '',
    required String headRef,
    required String baseRef,
    bool draft = false,
    List<String> labels = const [],
    List<String> assignees = const [],
    List<String> reviewers = const [],
  });

  /// Forge-specific refspec for fetching a remote PR/MR head.
  /// GitHub: `pull/<n>/head`, GitLab: `merge-requests/<n>/head`.
  String fetchRefspec(int number);

  Future<String> whoami();
}


/// Checks out a forge PR/MR head with pure git, the CLI as a fallback.
///
/// Every provider already exposes the forge-correct wire path via
/// `fetchRefspec` (`pull/<n>/head` for GitHub/Gitea,
/// `merge-requests/<n>/head` for GitLab), so the checkout mechanics are
/// identical across forges and live here once. We land that ref on a
/// local branch named `pr-<n>` — the same convention branches_page.dart
/// and workspace_shell.dart use when they materialise a PR desk, so the
/// two entry points name the same branch and never diverge.
///
/// Clobber-safe by construction. Rather than force-fetch straight into
/// `pr-<n>` (which would strand any local commits on that branch with no
/// UI path back to them), we fetch WITHOUT a destination ref — the remote
/// head lands in FETCH_HEAD and nothing local moves. We then only update
/// `pr-<n>` when it is safe: the branch is absent, already at the remote
/// tip, or a strict ancestor of it (a fast-forward). If `pr-<n>` holds
/// commits unreachable from the remote head we stop and return
/// [PrCheckoutWouldClobber] so the caller can confirm; passing
/// `force: true` skips that guard and resets the branch to the remote tip.
///
/// Pure git runs first. If the fetch fails — most often because the
/// user's git remote lacks the auth that `gh`/`glab` carry — we fall
/// back to the forge CLI's own checkout. The CLI fetches AND checks out the
/// PR on a branch named after the PR's head ref, not `pr-<n>`, moving HEAD in
/// the process. We snapshot the pre-CLI checkout first, then re-land on
/// `pr-<n>` through the same clobber guard — the invariant that every
/// successful checkout ends on `pr-<n>` holds uniformly across both paths. If
/// the guard refuses (would-clobber) we restore that snapshot before returning
/// so a cancel leaves the user unmoved. When both paths fail the error names
/// each one so the failure is diagnosable rather than ambiguous.
Future<PrCheckoutOutcome> checkoutPrHead(
  String repoPath,
  int number,
  String refspec, {
  bool force = false,
  Future<GitResult<void>> Function()? cliFallback,
}) async {
  final localRef = 'pr-$number';

  final fetched = await _fetchPrHeadTip(repoPath, refspec);
  if (fetched.error != null) return PrCheckoutFailed(fetched.error!);
  if (fetched.fetchStderr != null) {
    final fetchErr = fetched.fetchStderr!;
    if (cliFallback != null) {
      // Snapshot where the user currently sits BEFORE the CLI moves HEAD. The
      // forge CLI fetches AND checks out the PR on its own head-ref branch in
      // one step, so if the clobber guard later refuses to land `pr-<n>` we
      // must put the user back exactly where they were rather than silently
      // strand them on the CLI's branch.
      final snapshot = await _currentCheckout(repoPath);

      final viaCli = await cliFallback();
      if (viaCli.ok) {
        // The CLI checks out the PR on its own head-ref branch name, so we
        // re-land on `pr-<n>` through the same guard to keep the invariant
        // uniform across both paths. HEAD now sits on the CLI's branch at the
        // PR tip; resolve it. We do NOT delete the CLI-created branch — it is
        // a harmless extra ref.
        final cliTip = await _revParse(repoPath, 'HEAD');
        if (cliTip == null) {
          return const PrCheckoutFailed(
              'CLI checkout succeeded but HEAD did not resolve');
        }

        // Run the shared clobber guard FIRST so we never mutate `pr-<n>` on a
        // would-clobber, and so we can restore the pre-CLI checkout before
        // returning the outcome (see PrCheckoutWouldClobber's doc).
        final clobber =
            await _clobberGuard(repoPath, localRef, cliTip, force: force);
        if (clobber != null) {
          // Compare checkout STATE to checkout state, not to the fetched
          // commit: a user who started detached at the very commit the CLI
          // checked out has snapshot == cliTip, yet HEAD still changed from
          // detached to attached-on-the-CLI-branch. Re-resolving the current
          // checkout catches that — `git checkout <sha>` re-detaches, so the
          // restore is exact for both branch and detached snapshots.
          final now = await _currentCheckout(repoPath);
          if (snapshot != null && now != snapshot) {
            final restore =
                await git.runGit(repoPath, ['checkout', snapshot]);
            if (restore.exitCode != 0) {
              // Refuse to return WouldClobber while knowingly leaving the user
              // moved off their branch — name both facts instead.
              return PrCheckoutFailed(
                'PR update would clobber local commits on $localRef, and '
                'restoring the original checkout ($snapshot) failed: '
                '${(restore.stderr as String).trim()}',
              );
            }
          }
          return clobber;
        }

        // Guard cleared — land with the final command. force:true because the
        // guard already ran; the ancestry rule stays single-sourced.
        return _landOnPrBranch(repoPath, localRef, cliTip, force: true);
      }
      return PrCheckoutFailed(
        'pure-git fetch failed ($fetchErr); CLI checkout also failed '
        '(${viaCli.error})',
      );
    }
    return PrCheckoutFailed(fetchErr);
  }

  return _landOnPrBranch(repoPath, localRef, fetched.tip!, force: force);
}

/// Fetches a forge PR head onto the local `pr-<n>` branch WITHOUT touching
/// HEAD or the working tree — the desk-opening flavour of [checkoutPrHead].
///
/// The desk flows in branches_page.dart and workspace_shell.dart open a PR
/// as a worktree (`addDesk('pr-<n>')`); they must materialise the ref but
/// must NOT switch the current checkout, so they cannot use the `checkout -B`
/// that [checkoutPrHead] runs. This lands the fetched tip with `branch -f`
/// instead: it updates or creates the ref in place, leaving HEAD and the
/// working tree exactly where they were.
///
/// Same safety rules as [checkoutPrHead] — the fetch goes to FETCH_HEAD only
/// and the shared clobber guard refuses to strand local commits unless
/// [force]. There is no CLI fallback: the desk flows never had one, so a
/// fetch failure surfaces directly as [PrCheckoutFailed]. Note `branch -f`
/// refuses to move a branch that is checked out in any worktree; that error
/// surfaces as [PrCheckoutFailed] with git's stderr, which is correct — the
/// desk flows short-circuit on an existing desk first, and `addDesk` would
/// fail anyway.
Future<PrCheckoutOutcome> fetchPrHeadToBranch(
  String repoPath,
  int number,
  String refspec, {
  bool force = false,
}) async {
  final localRef = 'pr-$number';

  final fetched = await _fetchPrHeadTip(repoPath, refspec);
  if (fetched.error != null) return PrCheckoutFailed(fetched.error!);
  if (fetched.fetchStderr != null) return PrCheckoutFailed(fetched.fetchStderr!);

  return _landPrBranchNoCheckout(repoPath, localRef, fetched.tip!, force: force);
}

/// Resolves the repo's primary remote and fetches [refspec] to FETCH_HEAD
/// only — no `+<refspec>:<localRef>`, so no local branch moves — returning
/// the fetched tip. Shared by [checkoutPrHead] and [fetchPrHeadToBranch] so
/// the remote-resolution + fetch + head-resolve logic lives in exactly one
/// place.
///
/// Fetches from the repo's primary remote, not a hardcoded `origin`: a fork
/// or upstream clone commonly names its forge remote `upstream` (or anything
/// but `origin`), and hardcoding `origin` would fetch from the wrong — or a
/// nonexistent — remote for those setups. On success `tip` holds the SHA. On
/// a fatal error (no remote / unresolvable head) `error` is set. A non-zero
/// fetch is reported separately via `fetchStderr` so [checkoutPrHead] can
/// decide whether to try its CLI fallback.
Future<({String? tip, String? fetchStderr, String? error})> _fetchPrHeadTip(
    String repoPath, String refspec) async {
  final remoteRes = await git.primaryRemoteName(repoPath);
  final remote = remoteRes.ok ? remoteRes.data : null;
  if (remote == null) {
    return (
      tip: null,
      fetchStderr: null,
      error: 'no remote configured to fetch the PR head from'
    );
  }
  final fetch = await git.runGit(repoPath, ['fetch', remote, refspec]);
  if (fetch.exitCode != 0) {
    return (tip: null, fetchStderr: (fetch.stderr as String).trim(), error: null);
  }
  final remoteTip = await _revParse(repoPath, 'FETCH_HEAD');
  if (remoteTip == null) {
    return (tip: null, fetchStderr: null, error: 'could not resolve fetched PR head');
  }
  return (tip: remoteTip, fetchStderr: null, error: null);
}

/// The shared clobber guard for landing `pr-<n>` on [tip]. Returns a
/// [PrCheckoutWouldClobber] when a local `pr-<n>` carries commits [tip]
/// cannot reach (and not [force]); returns null when it is safe to
/// create/move the branch. `merge-base --is-ancestor` treats a commit as its
/// own ancestor, so an equal tip counts as a fast-forward. Both landing
/// functions call this so the ancestry rule lives in exactly one place —
/// they differ only in the git command they run once it clears.
Future<PrCheckoutWouldClobber?> _clobberGuard(
    String repoPath, String localRef, String tip,
    {required bool force}) async {
  if (force) return null;
  final localTip = await _revParse(repoPath, localRef);
  if (localTip == null) return null;
  final fastForward = await _isAncestor(repoPath, localTip, tip);
  if (fastForward) return null;
  return PrCheckoutWouldClobber(
    localRef: localRef,
    localTip: localTip,
    remoteTip: tip,
  );
}

/// Lands [localRef] (`pr-<n>`) on [tip] and checks it out. Both the pure-git
/// and CLI-fallback paths funnel through here so the "every successful
/// checkout ends on `pr-<n>`" invariant holds in exactly one place. When the
/// clobber guard clears, `checkout -B` creates or fast-forwards the branch in
/// one step — it works even when `pr-<n>` is the branch currently checked
/// out, unlike a fetch into a checked-out ref.
Future<PrCheckoutOutcome> _landOnPrBranch(
    String repoPath, String localRef, String tip,
    {required bool force}) async {
  final clobber = await _clobberGuard(repoPath, localRef, tip, force: force);
  if (clobber != null) return clobber;

  final co = await git.runGit(repoPath, ['checkout', '-B', localRef, tip]);
  if (co.exitCode != 0) return PrCheckoutFailed((co.stderr as String).trim());
  return const PrCheckoutOk();
}

/// Lands [localRef] (`pr-<n>`) on [tip] WITHOUT checking it out — the desk
/// flavour used by [fetchPrHeadToBranch]. Shares the [_clobberGuard] with
/// [_landOnPrBranch]; the only difference is `branch -f`, which moves/creates
/// the ref without touching HEAD or the working tree.
Future<PrCheckoutOutcome> _landPrBranchNoCheckout(
    String repoPath, String localRef, String tip,
    {required bool force}) async {
  final clobber = await _clobberGuard(repoPath, localRef, tip, force: force);
  if (clobber != null) return clobber;

  final br = await git.runGit(repoPath, ['branch', '-f', localRef, tip]);
  if (br.exitCode != 0) return PrCheckoutFailed((br.stderr as String).trim());
  return const PrCheckoutOk();
}

/// The current checkout as a restorable ref: the short branch name when HEAD
/// is on a branch, else the detached HEAD sha, else null (empty repo — nothing
/// to restore). Snapshotted before the CLI fallback moves HEAD so a
/// would-clobber can put the user back exactly where they were.
Future<String?> _currentCheckout(String repoPath) async {
  final branch = await git.runGit(
      repoPath, ['symbolic-ref', '--quiet', '--short', 'HEAD']);
  if (branch.exitCode == 0) {
    final name = (branch.stdout as String).trim();
    if (name.isNotEmpty) return name;
  }
  return _revParse(repoPath, 'HEAD');
}

/// `git rev-parse --verify --quiet <rev>` → the SHA, or null when the rev
/// does not resolve (e.g. the local branch does not exist yet).
Future<String?> _revParse(String repoPath, String rev) async {
  final r = await git.runGit(repoPath, ['rev-parse', '--verify', '--quiet', rev]);
  if (r.exitCode != 0) return null;
  final sha = (r.stdout as String).trim();
  return sha.isEmpty ? null : sha;
}

/// True when [maybeAncestor] is an ancestor of (or equal to) [descendant].
Future<bool> _isAncestor(
    String repoPath, String maybeAncestor, String descendant) async {
  final r = await git.runGit(
      repoPath, ['merge-base', '--is-ancestor', maybeAncestor, descendant]);
  return r.exitCode == 0;
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
    final s = await gh.ghStatus();
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
      gh.listPullRequests(repoPath, state: state, limit: limit);

  @override
  Future<GitResult<PullRequestSummary>> getPullRequest(
          String repoPath, int number) =>
      gh.getPullRequestSummary(repoPath, number);

  @override
  Future<GitResult<PullRequestDetail>> getPullRequestDetail(
    String repoPath,
    int number, {
    bool includeDiff = true,
  }) =>
      gh.pullRequestDetail(repoPath, number, includeDiff: includeDiff);

  @override
  Future<GitResult<List<CheckSummary>>> listChecks(
          String repoPath, int prNumber) =>
      gh.listChecks(repoPath, prNumber);

  @override
  Future<GitResult<void>> submitReview(
    String repoPath,
    int number, {
    required String event,
    String body = '',
  }) =>
      gh.submitPrReview(repoPath, number, event: event, body: body);

  @override
  Future<GitResult<void>> merge(
    String repoPath,
    int number, {
    required String method,
    bool deleteBranch = false,
  }) =>
      gh.mergePullRequest(repoPath, number,
          method: method, deleteBranch: deleteBranch);

  @override
  Future<PrCheckoutOutcome> checkout(String repoPath, int number,
          {bool force = false}) =>
      checkoutPrHead(repoPath, number, fetchRefspec(number),
          force: force,
          cliFallback: () => gh.checkoutPullRequest(repoPath, number));

  @override
  Future<GitResult<void>> close(String repoPath, int number) =>
      gh.closePullRequest(repoPath, number);

  @override
  Future<GitResult<void>> comment(
          String repoPath, int number, String body) =>
      gh.commentOnPullRequest(repoPath, number, body);

  @override
  Future<GitResult<int>> createPullRequest(
    String repoPath, {
    required String title,
    String body = '',
    required String headRef,
    required String baseRef,
    bool draft = false,
    List<String> labels = const [],
    List<String> assignees = const [],
    List<String> reviewers = const [],
  }) =>
      gh.createGhPr(repoPath,
          title: title, body: body, headRef: headRef, baseRef: baseRef,
          draft: draft, labels: labels, assignees: assignees, reviewers: reviewers);

  @override
  String fetchRefspec(int number) => 'pull/$number/head';

  @override
  Future<String> whoami() => gh.whoami();
}


class GlabPrProvider extends RemotePrProvider {
  const GlabPrProvider();

  @override
  Future<RemoteProviderStatus> status(String repoPath) async {
    final s = await glab.glabStatus();
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
      glab.listMergeRequests(repoPath,
          state: state == 'open' ? 'opened' : state, limit: limit);

  @override
  Future<GitResult<PullRequestSummary>> getPullRequest(
          String repoPath, int number) =>
      glab.getMergeRequest(repoPath, number);

  @override
  Future<GitResult<PullRequestDetail>> getPullRequestDetail(
    String repoPath,
    int number, {
    bool includeDiff = true,
  }) =>
      glab.mergeRequestDetail(repoPath, number, includeDiff: includeDiff);

  @override
  Future<GitResult<List<CheckSummary>>> listChecks(
          String repoPath, int prNumber) =>
      glab.listMrPipelines(repoPath, prNumber);

  @override
  Future<GitResult<void>> submitReview(
    String repoPath,
    int number, {
    required String event,
    String body = '',
  }) =>
      glab.submitMrReview(repoPath, number, event: event, body: body);

  @override
  Future<GitResult<void>> merge(
    String repoPath,
    int number, {
    required String method,
    bool deleteBranch = false,
  }) =>
      glab.mergeMr(repoPath, number,
          method: method, deleteBranch: deleteBranch);

  @override
  Future<PrCheckoutOutcome> checkout(String repoPath, int number,
          {bool force = false}) =>
      checkoutPrHead(repoPath, number, fetchRefspec(number),
          force: force,
          cliFallback: () => glab.checkoutMr(repoPath, number));

  @override
  Future<GitResult<void>> close(String repoPath, int number) =>
      glab.closeMr(repoPath, number);

  @override
  Future<GitResult<void>> comment(
          String repoPath, int number, String body) =>
      glab.commentOnMr(repoPath, number, body);

  @override
  Future<GitResult<int>> createPullRequest(
    String repoPath, {
    required String title,
    String body = '',
    required String headRef,
    required String baseRef,
    bool draft = false,
    List<String> labels = const [],
    List<String> assignees = const [],
    List<String> reviewers = const [],
  }) =>
      glab.createGlabMr(repoPath,
          title: title, body: body, headRef: headRef, baseRef: baseRef,
          draft: draft, labels: labels, assignees: assignees, reviewers: reviewers);

  @override
  String fetchRefspec(int number) => 'merge-requests/$number/head';

  @override
  Future<String> whoami() => glab.glabWhoami();
}


class GiteaPrProvider extends RemotePrProvider {
  const GiteaPrProvider();

  @override
  Future<RemoteProviderStatus> status(String repoPath) async {
    final coords = await gitea.resolveGiteaCoords(repoPath);
    if (coords == null) {
      return const RemoteProviderStatus(
        available: false,
        reason: 'could not resolve Gitea/Forgejo API URL',
      );
    }
    final s = await gitea.giteaApiStatus(coords.apiBase);
    if (!s.reachable) {
      return RemoteProviderStatus(available: false, reason: s.reason);
    }
    // Anonymous reads hold only for *public* repos — a private repo answers
    // 404 to a tokenless caller, so host reachability alone can't promise
    // repo-scoped readability. Probe the repo itself before advertising
    // available; when readable, PR lists/detail keep working tokenless while
    // create/merge/review still need the validated token.
    if (!s.authenticated) {
      final readable = await gitea.giteaRepoReadable(coords);
      if (readable) {
        return RemoteProviderStatus(
          available: true,
          canWrite: false,
          reason: s.reason ?? 'token not validated for ${coords.apiBase}',
        );
      }
      final auth = s.reason;
      return RemoteProviderStatus(
        available: false,
        reason: auth == null
            ? 'repo not readable without a valid token (private or missing)'
            : 'repo not readable without a valid token (private or missing); $auth',
      );
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
      return gitea.listGiteaPulls(repoPath, state: state, limit: limit);
  }

  @override
  Future<GitResult<PullRequestSummary>> getPullRequest(
          String repoPath, int number) =>
      gitea.getGiteaPull(repoPath, number);

  @override
  Future<GitResult<PullRequestDetail>> getPullRequestDetail(
    String repoPath,
    int number, {
    bool includeDiff = true,
  }) =>
      gitea.giteaPullDetail(repoPath, number, includeDiff: includeDiff);

  @override
  Future<GitResult<List<CheckSummary>>> listChecks(
          String repoPath, int prNumber) =>
      gitea.listGiteaCommitStatuses(repoPath, prNumber);

  @override
  Future<GitResult<void>> submitReview(
    String repoPath,
    int number, {
    required String event,
    String body = '',
  }) =>
      gitea.giteaApprovePull(repoPath, number, event: event, body: body);

  @override
  Future<GitResult<void>> merge(
    String repoPath,
    int number, {
    required String method,
    bool deleteBranch = false,
  }) =>
      gitea.giteaMergePull(repoPath, number,
          method: method, deleteBranch: deleteBranch);

  @override
  Future<PrCheckoutOutcome> checkout(String repoPath, int number,
          {bool force = false}) =>
      // Gitea/Forgejo has no bundled CLI checkout, so pure git is the
      // only path — no fallback closure.
      checkoutPrHead(repoPath, number, fetchRefspec(number), force: force);

  @override
  Future<GitResult<void>> close(String repoPath, int number) =>
      gitea.closeGiteaPull(repoPath, number);

  @override
  Future<GitResult<void>> comment(
          String repoPath, int number, String body) =>
      gitea.giteaCommentOnIssue(repoPath, number, body);

  @override
  Future<GitResult<int>> createPullRequest(
    String repoPath, {
    required String title,
    String body = '',
    required String headRef,
    required String baseRef,
    bool draft = false,
    List<String> labels = const [],
    List<String> assignees = const [],
    List<String> reviewers = const [],
  }) =>
      gitea.createGiteaPull(repoPath,
          title: title, body: body, headRef: headRef, baseRef: baseRef,
          labels: labels, assignees: assignees, draft: draft,
          reviewers: reviewers);

  @override
  String fetchRefspec(int number) => 'pull/$number/head';

  @override
  Future<String> whoami() async => _cachedLogin;

  static String _cachedLogin = '';
  static String _cachedForHost = '';
  static String _cachedForToken = '';

  static void clearCachedLogin() {
    _cachedLogin = '';
    _cachedForHost = '';
    _cachedForToken = '';
  }

  Future<void> _ensureLogin(String repoPath) async {
    final coords = await gitea.resolveGiteaCoords(repoPath);
    final host = coords?.apiBase ?? '';
    // Identity is a function of (host, token): the token participates in the
    // cache key so editing it in settings self-heals here without any
    // cross-module invalidation call.
    final token = gitea.resolveGiteaToken(host) ?? '';
    if (_cachedLogin.isNotEmpty &&
        _cachedForHost == host &&
        _cachedForToken == token) {
      return;
    }
    _cachedForHost = host;
    _cachedForToken = token;
    _cachedLogin = await gitea.giteaWhoami(repoPath);
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
      const GitResult.ok([]);

  GitResult<T> _noRemote<T>() =>
      GitResult.err('no remote PR host for this repo');

  @override Future<GitResult<PullRequestSummary>> getPullRequest(_, __) async => _noRemote();
  @override Future<GitResult<PullRequestDetail>> getPullRequestDetail(_, __, {bool includeDiff = true}) async => _noRemote();
  @override Future<GitResult<List<CheckSummary>>> listChecks(_, __) async => _noRemote();
  @override Future<GitResult<void>> submitReview(_, __, {required String event, String body = ''}) async => _noRemote();
  @override Future<GitResult<void>> merge(_, __, {required String method, bool deleteBranch = false}) async => _noRemote();
  @override Future<PrCheckoutOutcome> checkout(_, __, {bool force = false}) async =>
      const PrCheckoutFailed('no remote PR host for this repo');
  @override Future<GitResult<void>> close(_, __) async => _noRemote();
  @override Future<GitResult<void>> comment(_, __, ___) async => _noRemote();
  @override Future<GitResult<int>> createPullRequest(_, {required String title, String body = '', required String headRef, required String baseRef, bool draft = false, List<String> labels = const [], List<String> assignees = const [], List<String> reviewers = const []}) async => _noRemote();
  @override String fetchRefspec(int number) => '';
  @override Future<String> whoami() async => '';
}
