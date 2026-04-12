import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../backend/git.dart';
import '../backend/dtos.dart';
import 'repository_state.dart';

/// Caches the list of worktrees ("desks") for the currently-active repo.
/// Auto-refreshes when [RepositoryState.activePath] changes.
class WorktreeState extends ChangeNotifier {
  final RepositoryState _repo;
  List<WorktreeData> _desks = const [];
  bool _loading = false;
  String? _error;
  String? _loadedForPath;
  int _requestId = 0;
  DateTime _lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _minRefreshInterval = Duration(seconds: 3);

  WorktreeState(this._repo) {
    _repo.addListener(_onRepoChanged);
    // Initial load if a repo is already active.
    if (_repo.activePath != null) {
      refreshFor(_repo.activePath!);
    }
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  List<WorktreeData> get desks => _desks;
  bool get loading => _loading;
  String? get error => _error;

  /// Returns the worktree that matches [RepositoryState.activePath],
  /// or null if the active repo isn't among the known worktrees yet.
  WorktreeData? get activeDesk {
    final active = _repo.activePath;
    if (active == null) return null;
    final normalized = _normalize(active);
    for (final d in _desks) {
      if (_normalize(d.path) == normalized) return d;
    }
    return null;
  }

  void _onRepoChanged() {
    // When the active path changes, decide whether the worktree list is
    // still valid. A desk switch WITHIN the current repo's worktree set
    // keeps the list correct. A switch to any other path — a different
    // repo entirely — requires a refresh against the new repo.
    final active = _repo.activePath;
    if (active == null) {
      _desks = const [];
      _loadedForPath = null;
      notifyListeners();
      return;
    }
    final activeNorm = _normalize(active);
    final stillInKnownDesks = _desks
        .any((d) => _normalize(d.path) == activeNorm);
    if (!stillInKnownDesks) {
      // New repo — the prior repo's worktree list no longer applies.
      _desks = const [];
      _loadedForPath = null;
      refreshFor(active);
      return;
    }
    // Still within a known repo: the user's worktree set could have
    // changed out-of-band (CLI `git worktree add`/`remove`). Throttled
    // auto-refresh keeps the UI honest without hammering git. The cost
    // is one cheap `git worktree list` per interval at most.
    final now = DateTime.now();
    if (now.difference(_lastRefreshAt) >= _minRefreshInterval) {
      _lastRefreshAt = now;
      // Anchor to the main repo path so the result is consistent no
      // matter which desk we're currently on.
      final anchor = _mainRepoPathFromCache() ?? active;
      refreshFor(anchor);
    }
  }

  Future<void> refreshFor(String repoPath) async {
    final id = ++_requestId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await listWorktrees(repoPath);
      if (id != _requestId) return; // superseded
      _loading = false;
      if (result.ok) {
        _desks = result.data!;
        _loadedForPath = repoPath;
        _error = null;
      } else {
        _desks = const [];
        _error = result.error;
      }
    } catch (e) {
      if (id != _requestId) return;
      _loading = false;
      _desks = const [];
      _error = e.toString();
    }
    notifyListeners();
  }

  /// Creates a new desk for [branch] under the main repo's hidden worktrees
  /// directory, then switches to it as the active desk.
  ///
  /// When [createNewBranch] is true, also creates the branch from HEAD
  /// (uses `git worktree add -b`) — useful for "+ new desk from HEAD".
  Future<String?> addDesk(
    String branch, {
    bool createNewBranch = false,
  }) async {
    try {
      final mainRepo = await _resolveMainRepoPath();
      if (mainRepo == null) {
        return 'Could not resolve the main repository path.';
      }
      // Preserve the branch's '/' as directory hierarchy — e.g.
      // `feature/new-ui` → `worktrees/feature/new-ui`. Each segment is
      // sanitized for filesystem-illegal chars on Windows (<>:"\|?*) AND
      // rejected/neutralized if it's a path-traversal sequence. A branch
      // name like `../../pwned` must not escape the worktrees directory.
      final rawSegments = branch
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();
      final segments = <String>[];
      for (final raw in rawSegments) {
        var seg = raw.replaceAll(RegExp(r'[<>:"\\|?*]'), '_');
        // Reject path-traversal sequences: `.`, `..`, and anything that
        // normalizes to empty. Also defend against Windows drive letters
        // (e.g. `C:`) which would root the path elsewhere.
        if (seg == '.' || seg == '..' || seg.isEmpty) {
          seg = '_';
        }
        // Drive-letter prefix like "C:" sanitized above to "C_", safe.
        // Windows reserved filenames (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
        // can't exist as files or directories — including with extensions
        // (e.g. `con.txt`). Prefix those to neutralize. The check is
        // case-insensitive and applies to the stem (part before the dot).
        if (_isWindowsReserved(seg)) {
          seg = '_$seg';
        }
        segments.add(seg);
      }
      if (segments.isEmpty) {
        return 'Invalid branch name for a desk path.';
      }
      final worktreePath =
          p.joinAll([mainRepo, '.manifold', 'worktrees', ...segments]);
      // Defense in depth: after construction, verify the resolved path
      // is actually inside the intended worktrees directory.
      final worktreesRoot = p.join(mainRepo, '.manifold', 'worktrees');
      final normalizedTarget = p.normalize(worktreePath);
      final normalizedRoot = p.normalize(worktreesRoot);
      if (!p.isWithin(normalizedRoot, normalizedTarget)) {
        return 'Refusing to create a desk outside the worktrees directory.';
      }
      final result = await addWorktree(
        mainRepo, worktreePath, branch,
        createNewBranch: createNewBranch,
      );
      if (!result.ok) return result.error;
      await refreshFor(mainRepo);
      // Switch the active repo to the new desk.
      // Desk switches don't pollute the recents sidebar — only the primary
      // worktree is tracked there.
      await _repo.setActivePath(worktreePath, addToRecents: false);
      return null;
    } catch (e) {
      // State-layer methods never throw — unexpected failures (filesystem,
      // platform, etc.) are surfaced as string errors so callers don't
      // need their own exception boundary.
      return e.toString();
    }
  }

  /// Removes a desk. Optionally runs `git stash push` in that worktree first
  /// to preserve uncommitted changes.
  Future<String?> closeDesk(
    String worktreePath, {
    bool shelveFirst = false,
    bool force = false,
  }) async {
    try {
      if (shelveFirst) {
        final stash = await stashPush(
          worktreePath,
          message: 'Auto-shelved on desk close',
        );
        if (!stash.ok) return stash.error;
      }
      final mainRepo = await _resolveMainRepoPath();
      if (mainRepo == null) {
        return 'Could not resolve the main repository path.';
      }
      final result =
          await removeWorktree(mainRepo, worktreePath, force: force);
      if (!result.ok) return result.error;
      // If we just closed the active desk, switch back to the primary.
      if (_normalize(_repo.activePath ?? '') == _normalize(worktreePath)) {
        await _repo.setActivePath(mainRepo);
      }
      await refreshFor(mainRepo);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Returns the primary worktree's path (the main repo directory).
  String? _mainRepoPathFromCache() {
    for (final d in _desks) {
      if (d.isMain) return d.path;
    }
    return null;
  }

  /// Resolve the main repo path reliably, even if the worktree list hasn't
  /// been fetched yet. Falling back to `_repo.activePath` would be unsafe —
  /// if we're currently viewing a desk (worktree), that path is NOT the
  /// main repo, and creating a new desk with it as a base would nest
  /// worktrees inside each other.
  ///
  /// Uses `git rev-parse --git-common-dir` which points at the MAIN repo's
  /// `.git` directory regardless of which worktree we're in; the parent
  /// of that directory is the main repo root.
  Future<String?> _resolveMainRepoPath() async {
    final fromCache = _mainRepoPathFromCache();
    if (fromCache != null) return fromCache;
    final from = _repo.activePath;
    if (from == null) return null;
    try {
      final result = await Process.run(
        'git',
        ['rev-parse', '--path-format=absolute', '--git-common-dir'],
        workingDirectory: from,
      );
      if (result.exitCode != 0) return null;
      final gitCommonDir = (result.stdout as String).trim();
      if (gitCommonDir.isEmpty) return null;
      // The main repo root is the parent of its .git directory.
      final dir = p.dirname(gitCommonDir);
      if (dir.isEmpty) return null;
      return dir;
    } catch (_) {
      return null;
    }
  }

  String _normalize(String path) => path.replaceAll('\\', '/').toLowerCase();

  // Windows reserved device names. Case-insensitive. A filename is reserved
  // if its stem (part before the first dot) matches any of these — so
  // `con`, `CON`, `con.txt`, `COM1.log` are all reserved.
  static final RegExp _reservedRe = RegExp(
    r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])$',
    caseSensitive: false,
  );
  bool _isWindowsReserved(String segment) {
    final dot = segment.indexOf('.');
    final stem = dot < 0 ? segment : segment.substring(0, dot);
    return _reservedRe.hasMatch(stem);
  }
}
