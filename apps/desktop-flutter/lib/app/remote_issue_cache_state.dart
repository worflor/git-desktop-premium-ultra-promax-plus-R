// remote_issue_cache_state.dart — forge-agnostic remote issue cache
//
// Promotes remote issues from a page-local concern (BranchesPage._issues)
// to a provider-level concern so any widget — including the branch-picker
// side panel — can read remote issues without requiring BranchesPage to
// be mounted and without knowing which forge hosts the repo.
//
// All forge-specific logic lives in RemoteIssueProvider implementations.
// This class is forge-agnostic: it calls detectIssueProvider() on each refresh
// and delegates. detectIssueProvider() is a single `git remote get-url` spawn —
// cheap enough to run per refresh without caching.
//
// available=false is a silent no-op (local repo, unknown forge, unauthed
// CLI, …). Callers branch on [available] for optional empty states.

import 'package:flutter/foundation.dart';

import '../backend/async_utils.dart';

import '../backend/remote_issue_provider.dart';
import 'repository_state.dart';

class RemoteIssueCacheState extends ChangeNotifier {
  final RepositoryState _repo;

  List<IssueSummary> _issues = const [];
  bool _loading = false;
  bool _available = false;
  String? _error;
  String? _loadedForRepo;
  int _requestId = 0;

  RemoteIssueCacheState(this._repo) {
    _repo.addListener(_onRepoChanged);
    if (_repo.activePath != null) {
      fireAndLog(refreshFor(_repo.activePath!), 'RemoteIssueCacheState');
    }
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  /// All cached open remote issues for the current repo.
  List<IssueSummary> get all => _issues;
  bool get loading => _loading;

  /// True when the detected forge provider is installed and authenticated.
  /// False for local repos, unknown remotes, or unauthenticated CLIs —
  /// remote issues simply don't appear (no error shown to the user).
  bool get available => _available;
  String? get error => _error;
  String? get loadedForRepo => _loadedForRepo;

  void _onRepoChanged() {
    final active = _repo.activePath;
    if (active == null) {
      _issues = const [];
      _loadedForRepo = null;
      _available = false;
      notifyListeners();
      return;
    }
    fireAndLog(refreshFor(active), 'RemoteIssueCacheState');
  }

  Future<void> refreshFor(String repoPath) async {
    final id = ++_requestId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final provider = await detectIssueProvider(repoPath);
      if (id != _requestId) return;

      final providerStatus = await provider.status(repoPath);
      if (id != _requestId) return;

      if (!providerStatus.available) {
        _available = false;
        _issues = const [];
        _loading = false;
        notifyListeners();
        return;
      }
      _available = true;

      final r = await provider.listIssues(repoPath, state: 'open', limit: 100);
      if (id != _requestId) return;

      if (r.ok) {
        _issues = r.data!;
        _loadedForRepo = repoPath;
      } else {
        _issues = const [];
        _error = r.error;
      }
    } catch (e) {
      if (id != _requestId) return;
      _issues = const [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  /// Patch a single issue in the cache without triggering a full refetch.
  void patchIssue(IssueSummary updated) {
    final idx = _issues.indexWhere((i) => i.number == updated.number);
    if (idx == -1) {
      _issues = [updated, ..._issues];
    } else {
      _issues = [..._issues]..[idx] = updated;
    }
    notifyListeners();
  }

  /// Remove an issue from the cache (e.g. after closing it remotely).
  void evictIssue(int number) {
    _issues = _issues.where((i) => i.number != number).toList();
    notifyListeners();
  }
}
