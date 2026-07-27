// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// desk_pr_state.dart — provider for desk-PR metadata
//
// Mirrors WorktreeState's lifecycle: auto-refresh on
// RepositoryState.activePath change. Reads/writes go through
// DeskPrStore (refs/manifold/desks/<branch>) so the PR list is
// always derived from git, never from a sidecar cache.

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../backend/async_utils.dart';

import '../backend/desk_pr.dart';
import '../backend/desk_pr_diff.dart';
import '../backend/desk_pr_store.dart';
import '../backend/git.dart' as git;
import '../backend/git_identity.dart';
import '../backend/manifold_refs.dart';
import '../backend/remote_pr_provider.dart' show detectPrProvider;
import '../backend/review_records.dart';
import '../backend/review_store.dart';
import 'app_identity.dart';
import 'repository_state.dart';

class DeskPrState extends ChangeNotifier {
  final RepositoryState _repo;
  final AppIdentityState _identity;
  Map<String, DeskPr> _byBranch = const {};
  bool _loading = false;
  String? _error;
  String? _loadedForRepo;
  int _requestId = 0;

  /// Test-only: when true, construction and repo-change do NOT fire the
  /// ManifoldRefs git read. Mirrors [WorktreeState.debugSuppressAutoRefresh]
  /// — lets a widget test wire this against an active-repo RepositoryState
  /// without a `Process.run` that hangs `testWidgets`' fake-async, seeding via
  /// [debugSeed] instead.
  @visibleForTesting
  static bool debugSuppressAutoRefresh = false;

  DeskPrState(this._repo, this._identity) {
    _repo.addListener(_onRepoChanged);
    if (!debugSuppressAutoRefresh && _repo.activePath != null) {
      fireAndLog(refreshFor(_repo.activePath!), 'DeskPrState');
    }
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  Map<String, DeskPr> get byBranch => _byBranch;
  List<DeskPr> get all => _byBranch.values.toList();

  /// Test-only: install [byBranch] directly, bypassing the ManifoldRefs git
  /// read. Lets a widget test exercise anything that reads [DeskPrState]
  /// (e.g. the command palette's PR entries) hermetically — no real repo, no
  /// `Process.run` that would never resolve inside `testWidgets`' fake-async.
  @visibleForTesting
  void debugSeed(Map<String, DeskPr> byBranch, {String? loadedForRepo}) {
    _byBranch = Map.unmodifiable(byBranch);
    _loadedForRepo = loadedForRepo;
    notifyListeners();
  }

  bool get loading => _loading;
  String? get error => _error;
  String? get loadedForRepo => _loadedForRepo;

  DeskPr? prFor(String branch) => _byBranch[branch];

  void _onRepoChanged() {
    if (debugSuppressAutoRefresh) return;
    final active = _repo.activePath;
    if (active == null) {
      _byBranch = const {};
      _loadedForRepo = null;
      notifyListeners();
      return;
    }
    fireAndLog(refreshFor(active), 'DeskPrState');
  }

  /// Resolve the main repo path so a desk and its sibling worktrees
  /// share the same metadata refs. A desk path's `.git` is a worktree
  /// pointer; the metadata refs live in the common dir.
  Future<String?> _mainRepoOf(String anyPath) async {
    try {
      // Through git.dart's runner, not a raw spawn: this runs on every
      // refresh and every write, so it belongs inside the app-wide
      // subprocess budget, the non-interactive environment, and the
      // read-coalescing that makes the repeat calls free (L6).
      final r = await git.runGit(anyPath, [
        'rev-parse',
        '--path-format=absolute',
        '--git-common-dir',
      ]);
      if (r.exitCode != 0) return null;
      final commonDir = (r.stdout as String).trim();
      if (commonDir.isEmpty) return null;
      return p.dirname(commonDir);
    } catch (_) {
      return null;
    }
  }

  /// Resolve the repo's default branch name for use as a desk PR's
  /// baseRef. Returns null only when the repo has no recognisable
  /// default (fresh repo with no `main`/`master` and no remote HEAD) —
  /// callers must surface a user-visible error in that case rather than
  /// inventing a name.
  Future<String?> _resolveBaseRef(String repoPath) async {
    final r = await git.defaultBranchName(repoPath);
    if (r.ok) return r.data;
    return null;
  }

  /// The one place Manifold ref plumbing gets its identity — shared
  /// with the review pane so desk-PR writes and review writes can
  /// never diverge on author. [repoPath] should be the MAIN repo path
  /// (see [_mainRepoOf]); [loadedForRepo] is that path after a load.
  ///
  /// This is the TOOL's identity, deliberately: the git author of the
  /// orphan metadata commits is Manifold-the-app, so the repo's own
  /// user.name never leaks into metadata history. Who a record is ABOUT
  /// is a different question, answered by [viewerIdentity] — see the
  /// note there for why conflating the two was a bug.
  ManifoldRefs refsFor(String repoPath) {
    final short = _identity.identity.shortName;
    // One literal, not two: this fallback and the branding default used
    // to be independently spelled ('manifold' vs 'Manifold') in two
    // files, which is a drift waiting to happen even though
    // AppIdentityState never actually lets the name go empty.
    final author = short.isEmpty ? defaultAppIdentity.shortName : short;
    return ManifoldRefs(
      repoPath: repoPath,
      authorName: author,
      authorEmail: '$author@manifold.local',
    );
  }

  /// Who git says the person at this keyboard is, for the loaded repo.
  /// Null when git has no configured identity (see [GitIdentity]).
  GitIdentity? _viewer;

  /// The repo path [_viewer] was resolved against, so a repo switch
  /// cannot serve the previous repo's identity.
  String? _viewerFor;

  /// Whether the viewer question has been ASKED yet for the loaded repo.
  ///
  /// Tri-state on purpose: "not resolved" and "resolved to nobody" look
  /// identical through a nullable identity, and conflating them would
  /// flash "set your git identity" at every correctly-configured user
  /// for the frame before the config read lands.
  bool get viewerResolved => _viewerFor != null;

  /// The person at this keyboard, as review and desk-PR records name
  /// them. Null when git has no `user.name`/`user.email` configured.
  ///
  /// This used to be [AppIdentity.shortName] — the APP's branding name,
  /// the thing onboarding asks you to pick when it says "what is this
  /// to you?". Every reviewer on every machine therefore wrote under
  /// the same default string: one attention key, no hand-off
  /// candidates, and `viewer == author` unconditionally true, which
  /// silently made the turn fold treat everyone as the author of
  /// everything. Identity in a review is the HUMAN, and git already
  /// knows who that is.
  GitIdentity? get viewerIdentity => _viewer;

  /// The display review records carry for this viewer, or `''` when git
  /// has no identity. Empty is deliberately propagated rather than
  /// papered over with a placeholder: an invented name written into a
  /// ref that SYNCS TO PEERS is worse than no name, and every derivation
  /// that compares against it simply fails to match, which is honest.
  /// Writers must gate on [viewerIdentity] being non-null instead.
  String get viewerDisplay => _viewer?.display ?? '';

  /// The identity object review records embed. Carries the git email as
  /// the format's stable [ReviewIdentity.key] — recorded from day one so
  /// it is already present when the merge engine starts interpreting it,
  /// exactly as the format promises.
  ReviewIdentity? get viewerReviewIdentity {
    final v = _viewer;
    if (v == null) return null;
    return ReviewIdentity(v.display, key: v.key);
  }

  /// Resolve (and cache) the viewer for [main]. Cheap on the hot path:
  /// two `git config --get` reads that ride the shared runner's
  /// read-coalescing, and only on a repo change.
  Future<GitIdentity?> _ensureViewer(String main) async {
    if (_viewerFor == main) return _viewer;
    final resolved = await resolveGitIdentity(main);
    _viewer = resolved;
    _viewerFor = main;
    return resolved;
  }

  /// Test-only: install a viewer without a git config read, mirroring
  /// [debugSeed]'s contract for the PR map.
  @visibleForTesting
  void debugSeedViewer(GitIdentity? viewer, {String? forRepo}) {
    _viewer = viewer;
    _viewerFor = forRepo;
    notifyListeners();
  }

  /// The refusal a write returns when git has no identity to sign it
  /// with. Stated as the fix, not the complaint: this is the same
  /// condition `git commit` refuses under, and the same remedy.
  static const String identityUnsetMessage =
      'Set your git identity before reviewing — '
      'git config --global user.name "Your Name" '
      'and user.email "you@example.com".';

  Future<void> refreshFor(String repoPath) async {
    final id = ++_requestId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final main = await _mainRepoOf(repoPath) ?? repoPath;
      // Before the list read, so anything that renders off this refresh
      // (the turn badge, the hand-off offer) already knows who you are
      // rather than deriving one frame against an empty viewer.
      await _ensureViewer(main);
      final store = DeskPrStore(refsFor(main));
      final r = await store.listAll();
      if (id != _requestId) return;
      if (r.ok) {
        _byBranch = {for (final pr in r.data!) pr.headRef: pr};
        _loadedForRepo = main;
      } else {
        _byBranch = const {};
        _error = r.error;
      }
    } catch (e) {
      if (id != _requestId) return;
      _byBranch = const {};
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  /// Promote a branch to a desk PR. Returns null on success, error
  /// message on failure.
  /// [baseRef] is optional: when omitted we resolve the repo's default
  /// branch (origin/HEAD → fallback to `main`/`master`). Hardcoding
  /// `'main'` here used to break the promote flow on `master`-style
  /// repos; callers that already know the base (because a desk PR
  /// already exists) should pass it explicitly to skip the lookup.
  Future<String?> promote({
    required String repoPath,
    required String branch,
    String? title,
    String? body,
    String? baseRef,
    bool isDraft = true,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final me = await _ensureViewer(main);
    if (me == null) return identityUnsetMessage;
    final resolvedBase = baseRef ?? await _resolveBaseRef(main);
    if (resolvedBase == null) {
      return "Couldn't determine the repository's default branch — "
          'pass a base ref explicitly.';
    }
    final store = DeskPrStore(refsFor(main));
    final r = await store.create(
      branch: branch,
      title: (title?.trim().isNotEmpty ?? false) ? title!.trim() : branch,
      body: body ?? '',
      baseRef: resolvedBase,
      authorIdentity: me.display,
      isDraft: isDraft,
    );
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  Future<String?> addComment({
    required String repoPath,
    required String branch,
    required String body,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final me = await _ensureViewer(main);
    if (me == null) return identityUnsetMessage;
    final store = DeskPrStore(refsFor(main));
    final r = await store.addComment(
      branch: branch,
      author: me.display,
      body: body,
    );
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  Future<String?> addReview({
    required String repoPath,
    required String branch,
    required String verdict,
    required String body,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final me = await _ensureViewer(main);
    if (me == null) return identityUnsetMessage;
    final store = DeskPrStore(refsFor(main));
    final r = await store.addReview(
      branch: branch,
      author: me.display,
      verdict: verdict,
      body: body,
    );
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  Future<String?> setStateFor({
    required String repoPath,
    required String branch,
    required String state,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskPrStore(refsFor(main));
    final r = await store.setState(branch: branch, state: state);
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  Future<String?> editMeta({
    required String repoPath,
    required String branch,
    String? title,
    String? body,
    bool? isDraft,
    List<String>? labels,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskPrStore(refsFor(main));
    final r = await store.editMeta(
      branch: branch,
      title: title,
      body: body,
      isDraft: isDraft,
      labels: labels,
    );
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  /// Refresh a desk PR's persisted diff stats + mergeable flag from
  /// freshly-computed numbers. Called by the local-diff fetcher after
  /// `git diff baseRef..headRef` resolves so the row metrics tell the
  /// truth on the very next rebuild.
  Future<void> refreshDiffStats({
    required String repoPath,
    required String branch,
    required int additions,
    required int deletions,
    required int changedFiles,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskPrStore(refsFor(main));
    final r = await store.refreshDiffStats(
      branch: branch,
      additions: additions,
      deletions: deletions,
      changedFiles: changedFiles,
    );
    if (r.ok) await refreshFor(main);
  }

  /// Recompute and persist diff stats for the desk PR on [branch] by
  /// fetching the current baseRef..headRef diff. No-op when the branch
  /// has no desk PR. The commit flow in the Changes page calls this on
  /// success so the Branches row metrics update immediately — without
  /// it, the row keeps painting the previous expand's cached numbers
  /// until the user collapses and re-expands.
  Future<void> recomputeDiffStats({
    required String repoPath,
    required String branch,
  }) async {
    final pr = _byBranch[branch];
    if (pr == null) return;
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    // Stats-only: the numstat file list is all this needs. Fetching the
    // patch body here would be pure waste — and a machine-scale PR's body
    // arrives as a disk spool whose temp dir this caller would orphan.
    final r = await fetchLocalDeskPrDetail(
      repoPath: main,
      pr: pr,
      includeDiff: false,
    );
    if (!r.ok || r.data == null) return;
    final files = r.data!.files;
    final adds = files.fold<int>(0, (a, f) => a + f.additions);
    final dels = files.fold<int>(0, (a, f) => a + f.deletions);
    await refreshDiffStats(
      repoPath: main,
      branch: branch,
      additions: adds,
      deletions: dels,
      changedFiles: files.length,
    );
  }

  Future<String?> abandon({
    required String repoPath,
    required String branch,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskPrStore(refsFor(main));
    final r = await store.abandon(branch);
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  /// Toggle an issue link on this PR. [isRemote] picks which list it
  /// lands in — local issues live in [DeskPr.linkedIssues], remote in
  /// [DeskPr.linkedRemoteIssues].
  Future<String?> toggleLinkedIssue({
    required String repoPath,
    required String branch,
    required int issueId,
    required bool isRemote,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskPrStore(refsFor(main));
    final r = await store.toggleLinkedIssue(
      branch: branch,
      issueId: issueId,
      isRemote: isRemote,
    );
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  final Set<String> _promoting = {};

  Future<String?> promoteToRemote({
    required String repoPath,
    required String branch,
  }) async {
    if (!_promoting.add('$repoPath:$branch')) {
      return 'promotion already in progress';
    }
    try {
      final main = await _mainRepoOf(repoPath) ?? repoPath;
      final store = DeskPrStore(refsFor(main));
      final current = await store.read(branch);
      if (!current.ok || current.data == null) {
        return current.error ?? 'desk PR not found for $branch';
      }
      final desk = current.data!;
      if (desk.remoteNumber != null) {
        return 'already linked to remote #${desk.remoteNumber}';
      }
      final provider = await detectPrProvider(main);
      final status = await provider.status(main);
      if (!status.canWrite) {
        return status.reason ?? 'remote forge not available';
      }
      // Push the branch first — forges require the head ref to exist remotely.
      final pushResult = await git.pushRemote(
        main,
        branch: desk.headRef,
        setUpstream: true,
      );
      if (!pushResult.ok) {
        return 'push failed: ${pushResult.error}';
      }
      // Check if a remote PR already exists for this head ref (idempotency
      // guard for retries after a failed local link).
      int remoteNumber;
      final existingPrs = await provider.listPullRequests(main, state: 'open');
      if (!existingPrs.ok) {
        return 'could not check for existing PRs: ${existingPrs.error}';
      }
      final match = existingPrs.data
          ?.where((pr) => pr.headRef == desk.headRef)
          .firstOrNull;
      if (match != null) {
        remoteNumber = match.number;
      } else {
        final createResult = await provider.createPullRequest(
          main,
          title: desk.title,
          body: desk.body,
          headRef: desk.headRef,
          baseRef: desk.baseRef,
          draft: desk.isDraft,
          labels: desk.labels,
          assignees: desk.assignees,
          reviewers: desk.reviewers.map((r) => r.login).toList(),
        );
        if (!createResult.ok || createResult.data == null) {
          return createResult.error ?? 'failed to create remote PR';
        }
        remoteNumber = createResult.data!;
      }
      final linkResult = await store.setRemoteNumber(branch, remoteNumber);
      if (!linkResult.ok) {
        return 'remote PR #$remoteNumber created but local link failed: '
            '${linkResult.error}';
      }
      await refreshFor(main);
      return null;
    } finally {
      _promoting.remove('$repoPath:$branch');
    }
  }

  /// Repo paths with a Manifold ref sync (fetch+push of refs/manifold/*)
  /// in flight. Guards a manual sync from stacking on an auto one.
  final Set<String> _syncing = {};

  /// Share desk PRs over the git remote: fetch peers' Manifold refs,
  /// push ours, then refresh in-memory state. Moves the whole
  /// `refs/manifold/*` namespace in one round-trip. Guarded by
  /// [_syncing]. Returns null on success, an error string otherwise.
  /// UI wiring is a later step.
  Future<String?> syncWithRemote({
    required String repoPath,
    // Null resolves via ManifoldRefs.resolveMetadataRemote (not a
    // hardcoded 'origin'), so a fork whose only remote is `upstream`
    // syncs against IT by default; pass an explicit name to override.
    String? remote,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    if (!_syncing.add(main)) return 'sync already in progress';
    try {
      final store = DeskPrStore(refsFor(main));
      final r = await store.syncWithRemote(
        remote: remote == null ? null : MetadataRemote(remote),
      );
      if (!r.ok) return r.error;
      await refreshFor(main);
      await _cutReviewRoundsAfterSync(main);
      return null;
    } finally {
      _syncing.remove(main);
    }
  }

  /// Post-sync round hygiene: for every OPEN desk PR that already HAS a
  /// review, cut a new round if its head moved — a peer's push moves
  /// heads exactly at sync time, and round pins are what keep their
  /// comments honest about which code they saw. Deliberately gated on
  /// the review existing: sync must never mint review refs for desks
  /// nobody is reviewing.
  ///
  /// ONE ref listing decides who participates, so the cost scales with
  /// the number of REVIEWS, not the number of desks — a repo full of
  /// desks and no reviews leaves sync untouched. The survivors are cut
  /// sequentially on purpose: these are CAS writes against the same
  /// namespace, and racing them would just spend retries.
  ///
  /// Best-effort by design, and safe to be: this is an EAGER convenience
  /// so a peer's new round shows up without anyone opening the pane —
  /// [ReviewPaneController.load] cuts the same round on the next look.
  /// So a failure here costs a little latency, never a lost round, and
  /// must not turn a successful sync into a reported failure.
  Future<void> _cutReviewRoundsAfterSync(String main) async {
    final store = ReviewStore(refsFor(main));
    final reviewed = await store.listReviewedDeskIds();
    if (!reviewed.ok || reviewed.data!.isEmpty) return;
    // Carry the whole record, not just the head ref: the attention flip
    // a round cut performs is computed from the PR's AUTHOR, and this
    // loop runs on whichever machine happened to sync — usually the
    // reviewer's. Handing the store a head ref and letting it guess the
    // author from `by` is what pointed the turn backwards.
    final open = {
      for (final pr in _byBranch.values)
        if (pr.state == 'OPEN' && reviewed.data!.contains(pr.deskId))
          pr.deskId: pr,
    };
    if (open.isEmpty) return;
    // Provenance only. Unattributed when git has no identity, which is
    // honest: nobody signed this cut. The attention math does not read
    // it, so an unconfigured machine still keeps rounds honest.
    final by = viewerReviewIdentity ?? const ReviewIdentity('');
    for (final entry in open.entries) {
      try {
        // Best-effort, but never SILENT: an `ok: false` used to vanish
        // here, so a review whose rounds stopped being cut looked
        // identical to one with nothing to cut. The next pane load still
        // recovers it; the log is what makes a persistent failure
        // findable instead of invisible.
        final cut = await store.cutRoundIfMoved(
          deskId: entry.key,
          branch: entry.value.headRef,
          by: by,
          authorDisplay: entry.value.authorIdentity,
        );
        if (!cut.ok) {
          debugPrint(
              'review round cut #${entry.key}: ${cut.error ?? "failed"}');
        }
      } catch (e) {
        debugPrint('review round cut #${entry.key}: $e');
      }
    }
  }

  final Set<String> _reconciling = {};

  Future<void> reconcileRemoteState(String repoPath) async {
    if (!_reconciling.add(repoPath)) return;
    try {
      await _reconcileRemoteStateImpl(repoPath);
    } catch (e) {
      debugPrint('reconcileRemoteState($repoPath): $e');
    } finally {
      _reconciling.remove(repoPath);
    }
  }

  Future<void> _reconcileRemoteStateImpl(String repoPath) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskPrStore(refsFor(main));
    final promoted = _byBranch.values
        .where((pr) => pr.remoteNumber != null && pr.state == 'OPEN')
        .toList();
    if (promoted.isEmpty) return;
    final provider = await detectPrProvider(main);
    final status = await provider.status(main);
    if (!status.available) return;
    var changed = false;
    for (final desk in promoted) {
      try {
        final r = await provider.getPullRequest(main, desk.remoteNumber!);
        if (!r.ok || r.data == null) continue;
        final remote = r.data!;
        final needsUpdate =
            desk.state != remote.state ||
            desk.mergeable != remote.mergeable ||
            desk.additions != remote.additions ||
            desk.deletions != remote.deletions ||
            desk.changedFiles != remote.changedFiles;
        if (!needsUpdate) continue;
        final updated = desk.copyWith(
          state: remote.state,
          mergeable: remote.mergeable,
          additions: remote.additions,
          deletions: remote.deletions,
          changedFiles: remote.changedFiles,
        );
        final writeResult = await store.updateFull(
          updated,
          message: 'reconcile remote #${desk.remoteNumber}',
        );
        if (writeResult.ok) changed = true;
      } catch (e) {
        debugPrint('reconcile PR #${desk.remoteNumber}: $e');
        continue;
      }
    }
    if (changed) await refreshFor(main);
  }
}
