// desk_issue_state.dart — provider for desk-issue metadata
//
// Mirrors DeskPrState's lifecycle: auto-refresh on
// RepositoryState.activePath change, route writes through the same
// ManifoldRefs so PRs and issues share author identity, common-dir
// resolution, and the id-counter ref.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../backend/desk_issue.dart';
import '../backend/desk_issue_store.dart';
import '../backend/remote_issue_provider.dart';
import '../backend/manifold_refs.dart';
import 'app_identity.dart';
import 'remote_issue_cache_state.dart';
import 'repository_state.dart';

class DeskIssueState extends ChangeNotifier {
  final RepositoryState _repo;
  final AppIdentityState _identity;
  Map<int, DeskIssue> _byId = const {};
  bool _loading = false;
  String? _error;
  String? _loadedForRepo;
  int _requestId = 0;

  /// Optional reference to the remote issue cache. When attached, every
  /// remote-affecting write (promote/sync/push) triggers a cache refresh
  /// so cross-cutting UI surfaces (side panel, branches page) see the
  /// new state without manual reloads.
  RemoteIssueCacheState? _remoteCache;

  /// Issue ids currently being promoted to remote. Acts as an in-memory
  /// lock so a double-click can't create two remote issues for the same
  /// local id before the first setRemoteNumber commits.
  final Set<int> _promoting = <int>{};

  /// Issue ids currently being pushed to remote. Prevents concurrent
  /// pushes from racing on label diff computation and interleaving edits.
  final Set<int> _pushing = <int>{};

  DeskIssueState(this._repo, this._identity) {
    _repo.addListener(_onRepoChanged);
    if (_repo.activePath != null) {
      refreshFor(_repo.activePath!);
    }
  }

  /// Wire the remote-issue cache so post-write refreshes propagate.
  /// Called from main.dart after both providers exist.
  void attachRemoteCache(RemoteIssueCacheState cache) {
    _remoteCache = cache;
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  Map<int, DeskIssue> get byId => _byId;
  List<DeskIssue> get all => _byId.values.toList();
  bool get loading => _loading;
  String? get error => _error;
  String? get loadedForRepo => _loadedForRepo;

  DeskIssue? issueFor(int id) => _byId[id];

  void _onRepoChanged() {
    final active = _repo.activePath;
    if (active == null) {
      _byId = const {};
      _loadedForRepo = null;
      notifyListeners();
      return;
    }
    refreshFor(active);
  }

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
      final store = DeskIssueStore(_refsFor(main));
      final r = await store.listAll();
      if (id != _requestId) return;
      _loading = false;
      if (r.ok) {
        _byId = {
          for (final issue in r.data!) issue.issueId: issue,
        };
        _loadedForRepo = main;
        _error = null;
      } else {
        _byId = const {};
        _error = r.error;
      }
    } catch (e) {
      if (id != _requestId) return;
      _loading = false;
      _byId = const {};
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<String?> create({
    required String repoPath,
    required String title,
    String body = '',
    List<String> labels = const [],
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskIssueStore(_refsFor(main));
    final r = await store.create(
      title: title,
      body: body,
      authorIdentity: _identity.identity.shortName,
      labels: labels,
    );
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  /// Create a local issue and optionally promote it to the remote forge
  /// in one call. Returns an error string on failure, null on success.
  /// If [promoteRemote] is true, the local issue is created first, then
  /// [promoteToRemote] runs — a failure there leaves the local issue intact.
  Future<String?> createMaybeRemote({
    required String repoPath,
    required String title,
    String body = '',
    List<String> labels = const [],
    bool promoteRemote = false,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskIssueStore(_refsFor(main));
    final r = await store.create(
      title: title,
      body: body,
      authorIdentity: _identity.identity.shortName,
      labels: labels,
    );
    if (!r.ok) return r.error;
    await refreshFor(main);
    if (promoteRemote && r.data != null) {
      return promoteToRemote(repoPath: main, id: r.data!.issueId);
    }
    return null;
  }

  Future<String?> addComment({
    required String repoPath,
    required int id,
    required String body,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskIssueStore(_refsFor(main));
    final r = await store.addComment(
      id: id,
      author: _identity.identity.shortName,
      body: body,
    );
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  Future<String?> setStateFor({
    required String repoPath,
    required int id,
    required String state,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskIssueStore(_refsFor(main));
    final r = await store.setState(id: id, state: state);
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  Future<String?> editMeta({
    required String repoPath,
    required int id,
    String? title,
    String? body,
    List<String>? labels,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskIssueStore(_refsFor(main));
    final r = await store.editMeta(
      id: id,
      title: title,
      body: body,
      labels: labels,
    );
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  Future<String?> toggleAddressedBy({
    required String repoPath,
    required int id,
    required String branch,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskIssueStore(_refsFor(main));
    final r = await store.toggleAddressedBy(id: id, branch: branch);
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  Future<String?> abandon({
    required String repoPath,
    required int id,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskIssueStore(_refsFor(main));
    final r = await store.abandon(id);
    if (!r.ok) return r.error;
    await refreshFor(main);
    return null;
  }

  //
  // All methods resolve the forge via detectIssueProvider() and use the
  // RemoteIssueProvider interface — no forge-specific calls here.
  // Local issues (DeskIssue git refs) are unaffected and always work.

  /// Promote a local issue to the remote forge, linking them via
  /// [DeskIssue.remoteNumber]. Works on any supported forge.
  /// Concurrent calls for the same id are rejected via [_promoting] —
  /// without this guard a double-click could create two remote issues
  /// before the first setRemoteNumber commits, orphaning one.
  /// On success, also refreshes [_remoteCache] so the new remote issue
  /// appears in side panels / lists without a manual reload.
  Future<String?> promoteToRemote({
    required String repoPath,
    required int id,
  }) async {
    if (!_promoting.add(id)) {
      return 'already promoting issue $id';
    }
    try {
      final main = await _mainRepoOf(repoPath) ?? repoPath;
      final store = DeskIssueStore(_refsFor(main));

      final r = await store.read(id);
      if (!r.ok) return r.error;
      final issue = r.data;
      if (issue == null) return 'issue $id not found';
      if (issue.remoteNumber != null) {
        return 'already linked to remote #${issue.remoteNumber}';
      }

      final provider = await detectIssueProvider(main);
      final status = await provider.status(main);
      if (!status.available) return status.reason ?? 'remote unavailable';

      final gr = await provider.createIssue(
        main,
        title: issue.title,
        body: issue.body,
        labels: issue.labels,
        assignees: issue.assignees,
      );
      if (!gr.ok) return gr.error;

      // Note: if setRemoteNumber fails here we have an orphan remote
      // issue. Local writes are extremely reliable (just a git ref
      // update), so this is a near-zero probability — but worth a clear
      // error so the user knows the remote was created.
      final sr = await store.setRemoteNumber(id, gr.data!);
      if (!sr.ok) {
        return 'remote issue #${gr.data} created but local link failed: '
            '${sr.error}';
      }

      await refreshFor(main);
      // Surface the new remote issue to other consumers (side panel etc.)
      // ignore: unawaited_futures
      _remoteCache?.refreshFor(main);
      return null;
    } finally {
      _promoting.remove(id);
    }
  }

  /// Import a remote issue into local storage, creating a [DeskIssue]
  /// that mirrors it and is bidirectionally linked via [remoteNumber].
  /// Single-commit: the local issue is born already-linked with all
  /// fields populated, so no concurrent reader can ever see a partial
  /// import (e.g. an issue without its remoteNumber set).
  Future<String?> importFromRemote({
    required String repoPath,
    required IssueSummary remote,
    IssueDetail? detail,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;

    // Guard: already imported?
    final existing = _byId.values
        .where((i) => i.remoteNumber == remote.number)
        .firstOrNull;
    if (existing != null) {
      return 'already imported as local #${existing.issueId}';
    }

    final store = DeskIssueStore(_refsFor(main));

    final cr = await store.create(
      title: remote.title,
      body: detail?.body ?? '',
      authorIdentity: remote.authorLogin,
      labels: remote.labels,
      assignees: remote.assignees,
      state: remote.state,
      remoteNumber: remote.number,
    );
    if (!cr.ok) return cr.error;

    await refreshFor(main);
    return null;
  }

  /// Pull the latest remote state into the local issue. Remote wins for
  /// all synced fields; local-only fields (comments, addressedBy) are
  /// preserved.
  Future<String?> syncFromRemote({
    required String repoPath,
    required int id,
  }) async {
    final main = await _mainRepoOf(repoPath) ?? repoPath;
    final store = DeskIssueStore(_refsFor(main));

    final r = await store.read(id);
    if (!r.ok) return r.error;
    final issue = r.data;
    if (issue == null) return 'issue $id not found';
    if (issue.remoteNumber == null) return 'issue $id has no remote link';

    final provider = await detectIssueProvider(main);
    final status = await provider.status(main);
    if (!status.available) return status.reason ?? 'remote unavailable';

    final sr = await provider.getIssue(main, issue.remoteNumber!);
    if (!sr.ok) return sr.error;
    final dr = await provider.getIssueDetail(main, issue.remoteNumber!);

    final remote = sr.data!;
    final body = dr.ok ? dr.data!.body : issue.body;

    final wr = await store.applyRemoteSnapshot(
      id: id,
      title: remote.title,
      body: body,
      state: remote.state,
      labels: remote.labels,
      assignees: remote.assignees,
    );
    if (!wr.ok) return wr.error;

    await refreshFor(main);
    return null;
  }

  /// Push local edits to the remote forge. Each field is only written
  /// if it differs from the current remote value; labels are diffed to
  /// produce add/remove sets.
  /// Concurrent calls for the same id are rejected via [_pushing] —
  /// without this guard two racing calls would fetch the same remote
  /// state, compute stale label diffs, and interleave edits on the forge.
  /// On success, refreshes [_remoteCache] so other consumers see the
  /// new remote state.
  Future<String?> pushToRemote({
    required String repoPath,
    required int id,
  }) async {
    if (!_pushing.add(id)) {
      return 'already pushing issue $id';
    }
    try {
      final main = await _mainRepoOf(repoPath) ?? repoPath;
      final store = DeskIssueStore(_refsFor(main));

      final r = await store.read(id);
      if (!r.ok) return r.error;
      final issue = r.data;
      if (issue == null) return 'issue $id not found';
      if (issue.remoteNumber == null) return 'issue $id has no remote link';

      final provider = await detectIssueProvider(main);
      final status = await provider.status(main);
      if (!status.available) return status.reason ?? 'remote unavailable';

      final n = issue.remoteNumber!;

      // Both futures start immediately (in parallel). Awaiting each in
      // turn collects results once they land; detail is usually ready by
      // the time summary resolves.
      final summaryFuture = provider.getIssue(main, n);
      final detailFuture  = provider.getIssueDetail(main, n);
      final remoteR = await summaryFuture;
      if (!remoteR.ok) return remoteR.error;
      final remote = remoteR.data!;
      final detailR = await detailFuture;
      final remoteBody = detailR.ok ? detailR.data!.body : null;

      final addLabels =
          issue.labels.toSet().difference(remote.labels.toSet()).toList();
      final removeLabels =
          remote.labels.toSet().difference(issue.labels.toSet()).toList();

      // Only push body if it differs from the remote — avoids silently
      // overwriting web edits the user made to a field they never touched
      // locally (e.g. pushing a label change clobbering a remote body edit).
      final er = await provider.editIssue(
        main,
        n,
        title: issue.title != remote.title ? issue.title : null,
        body: (remoteBody == null || issue.body != remoteBody)
            ? issue.body
            : null,
        addLabels: addLabels,
        removeLabels: removeLabels,
      );
      if (!er.ok) return er.error;

      if (issue.state != remote.state) {
        final cr = issue.state == 'CLOSED'
            ? await provider.closeIssue(main, n)
            : await provider.reopenIssue(main, n);
        if (!cr.ok) return cr.error;
      }

      // ignore: unawaited_futures
      _remoteCache?.refreshFor(main);
      return null;
    } finally {
      _pushing.remove(id);
    }
  }
}
