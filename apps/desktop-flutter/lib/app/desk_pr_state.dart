// desk_pr_state.dart — provider for desk-PR metadata
//
// Mirrors WorktreeState's lifecycle: auto-refresh on
// RepositoryState.activePath change. Reads/writes go through
// DeskPrStore (refs/manifold/desks/<branch>) so the PR list is
// always derived from git, never from a sidecar cache.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../backend/desk_pr.dart';
import '../backend/desk_pr_diff.dart';
import '../backend/desk_pr_store.dart';
import '../backend/git.dart' as git;
import '../backend/manifold_refs.dart';
import '../backend/remote_pr_provider.dart' show detectPrProvider;
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

  DeskPrState(this._repo, this._identity) {
    _repo.addListener(_onRepoChanged);
    if (_repo.activePath != null) {
      refreshFor(_repo.activePath!);
    }
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  Map<String, DeskPr> get byBranch => _byBranch;
  List<DeskPr> get all => _byBranch.values.toList();
  bool get loading => _loading;
  String? get error => _error;
  String? get loadedForRepo => _loadedForRepo;

  DeskPr? prFor(String branch) => _byBranch[branch];

  void _onRepoChanged() {
    final active = _repo.activePath;
    if (active == null) {
      _byBranch = const {};
      _loadedForRepo = null;
      notifyListeners();
      return;
    }
    refreshFor(active);
  }

  /// Resolve the main repo path so a desk and its sibling worktrees
  /// share the same metadata refs. A desk path's `.git` is a worktree
  /// pointer; the metadata refs live in the common dir.
  Future<String?> _mainRepoOf(String anyPath) async {
    try {
      final r = await Process.run(
        'git',
        ['rev-parse', '--path-format=absolute', '--git-common-dir'],
        workingDirectory: anyPath,
      );
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

  ManifoldRefs _refsFor(String repoPath) {
    final id = _identity.identity;
    final author = id.shortName.isEmpty ? 'manifold' : id.shortName;
    return ManifoldRefs(
      repoPath: repoPath,
      authorName: author,
      authorEmail: '$author@manifold.local',
    );
  }

  Future<void> refreshFor(String repoPath) async {
    final id = ++_requestId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final main = await _mainRepoOf(repoPath) ?? repoPath;
      final store = DeskPrStore(_refsFor(main));
      final r = await store.listAll();
      if (id != _requestId) return;
      _loading = false;
      if (r.ok) {
        _byBranch = {
          for (final pr in r.data!) pr.headRef: pr,
        };
        _loadedForRepo = main;
        _error = null;
      } else {
        _byBranch = const {};
        _error = r.error;
      }
    } catch (e) {
      if (id != _requestId) return;
      _loading = false;
      _byBranch = const {};
      _error = e.toString();
    }
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
    final resolvedBase = baseRef ?? await _resolveBaseRef(main);
    if (resolvedBase == null) {
      return "Couldn't determine the repository's default branch — "
          'pass a base ref explicitly.';
    }
    final store = DeskPrStore(_refsFor(main));
    final r = await store.create(
      branch: branch,
      title: (title?.trim().isNotEmpty ?? false) ? title!.trim() : branch,
      body: body ?? '',
      baseRef: resolvedBase,
      authorIdentity: _identity.identity.shortName,
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
    final store = DeskPrStore(_refsFor(main));
    final r = await store.addComment(
      branch: branch,
      author: _identity.identity.shortName,
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
    final store = DeskPrStore(_refsFor(main));
    final r = await store.addReview(
      branch: branch,
      author: _identity.identity.shortName,
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
    final store = DeskPrStore(_refsFor(main));
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
    final store = DeskPrStore(_refsFor(main));
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
    final store = DeskPrStore(_refsFor(main));
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
    final r = await fetchLocalDeskPrDetail(repoPath: main, pr: pr);
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
    final store = DeskPrStore(_refsFor(main));
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
    final store = DeskPrStore(_refsFor(main));
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
    if (!_promoting.add('$repoPath:$branch')) return 'promotion already in progress';
    try {
      final main = await _mainRepoOf(repoPath) ?? repoPath;
      final store = DeskPrStore(_refsFor(main));
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
      if (!status.available) {
        return status.reason ?? 'remote forge not available';
      }
      // Push the branch first — forges require the head ref to exist remotely.
      final pushResult = await git.pushRemote(main,
          branch: desk.headRef, setUpstream: true);
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
        final createResult = await provider.createPullRequest(main,
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
    final store = DeskPrStore(_refsFor(main));
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
        final needsUpdate = desk.state != remote.state ||
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
            updated, message: 'reconcile remote #${desk.remoteNumber}');
        if (writeResult.ok) changed = true;
      } catch (e) {
        debugPrint('reconcile PR #${desk.remoteNumber}: $e');
        continue;
      }
    }
    if (changed) await refreshFor(main);
  }
}
