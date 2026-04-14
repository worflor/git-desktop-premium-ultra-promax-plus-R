// ═════════════════════════════════════════════════════════════════════════
// desk_issue_state.dart — provider for desk-issue metadata
//
// Mirrors DeskPrState's lifecycle: auto-refresh on
// RepositoryState.activePath change, route writes through the same
// ManifoldRefs so PRs and issues share author identity, common-dir
// resolution, and the id-counter ref.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../backend/desk_issue.dart';
import '../backend/desk_issue_store.dart';
import '../backend/manifold_refs.dart';
import 'app_identity.dart';
import 'repository_state.dart';

class DeskIssueState extends ChangeNotifier {
  final RepositoryState _repo;
  final AppIdentityState _identity;
  Map<int, DeskIssue> _byId = const {};
  bool _loading = false;
  String? _error;
  String? _loadedForRepo;
  int _requestId = 0;

  DeskIssueState(this._repo, this._identity) {
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
}
