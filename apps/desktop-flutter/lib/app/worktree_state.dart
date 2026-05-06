import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../backend/git.dart';
import '../backend/dtos.dart';
import 'repository_state.dart';

/// Lightweight per-desk activity signal — what's actually going on
/// in this worktree without having to switch into it. Drives the
/// status-aware tab chrome (ahead/behind glyphs, last-touched peek)
/// so the desk row reads as a parallelism map at a glance.
class DeskActivity {
  /// Commits this desk's HEAD is ahead of its tracking base
  /// (upstream `@{u}` if configured, else `main`/`master` if either
  /// exists, else 0).
  final int ahead;
  /// Commits behind the same base.
  final int behind;
  /// HEAD commit's author timestamp. Null if unresolvable.
  final DateTime? lastActivity;
  const DeskActivity({
    required this.ahead,
    required this.behind,
    required this.lastActivity,
  });
  static const empty =
      DeskActivity(ahead: 0, behind: 0, lastActivity: null);
}

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
  // Per-desk activity probes — populated lazily after each refresh so
  // the cheap path (worktree list) lands first and the chrome can
  // tint when the slower probes resolve.
  final Map<String, DeskActivity> _activityByPath = {};

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
  DeskActivity? activityFor(String worktreePath) =>
      _activityByPath[_normalize(worktreePath)];

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
    // Probe per-desk activity in the background — the worktree list
    // itself doesn't carry ahead/behind or HEAD timestamps, so each
    // desk gets a cheap rev-list + log probe. Notifications fire as
    // probes resolve so the chrome lights up incrementally.
    unawaited(_refreshActivityForDesks(id));
  }

  Future<void> _refreshActivityForDesks(int requestId) async {
    final snapshot = List<WorktreeData>.from(_desks);
    for (final d in snapshot) {
      if (requestId != _requestId) return;
      final probed = await _probeDeskActivity(d);
      if (requestId != _requestId) return;
      _activityByPath[_normalize(d.path)] = probed;
      notifyListeners();
    }
  }

  Future<DeskActivity> _probeDeskActivity(WorktreeData d) async {
    if (d.path.isEmpty) return DeskActivity.empty;
    // Kick off log + ahead/behind concurrently. The two probes are
    // independent — the log just reads HEAD's commit object, the
    // ahead/behind walk compares HEAD to a base ref — so overlapping
    // their wall time halves the desk-probe latency on top of the
    // individual-call collapse below.
    final logFuture = _deskLastActivity(d.path);
    final abFuture = _deskAheadBehind(d.path);
    final results = await Future.wait([logFuture, abFuture]);
    final lastActivity = results[0] as DateTime?;
    final ab = results[1] as ({int ahead, int behind});
    return DeskActivity(
      ahead: ab.ahead,
      behind: ab.behind,
      lastActivity: lastActivity,
    );
  }

  /// HEAD's author timestamp. Single git object lookup — no working
  /// tree I/O — so this stays fast even on giant repos.
  Future<DateTime?> _deskLastActivity(String path) async {
    try {
      final logRes = await Process.run(
        'git',
        ['log', '-1', '--format=%cI', 'HEAD'],
        workingDirectory: path,
      );
      if (logRes.exitCode == 0) {
        final iso = (logRes.stdout as String).trim();
        if (iso.isNotEmpty) return DateTime.tryParse(iso);
      }
    } catch (_) {}
    return null;
  }

  /// Ahead/behind counts against the most-relevant base ref. Tries
  /// `@{u}...HEAD` first — one rev-list walk, upstream resolution
  /// happens inside git without a separate rev-parse spawn. If the
  /// branch has no upstream, falls back to `main` then `master`
  /// without needing to pre-verify them: rev-list returns exit 128
  /// on an unresolvable ref, so we just try and move on. Previously
  /// this was 2-4 serial git calls per desk; the common case
  /// (upstream configured) is now exactly 1.
  Future<({int ahead, int behind})> _deskAheadBehind(String path) async {
    ({int ahead, int behind}) parse(ProcessResult r) {
      if (r.exitCode != 0) return (ahead: 0, behind: 0);
      final parts = (r.stdout as String).trim().split(RegExp(r'\s+'));
      if (parts.length != 2) return (ahead: 0, behind: 0);
      final behind = int.tryParse(parts[0]) ?? 0;
      final ahead = int.tryParse(parts[1]) ?? 0;
      return (ahead: ahead, behind: behind);
    }

    for (final baseRef in const ['@{u}', 'main', 'master']) {
      try {
        final r = await Process.run(
          'git',
          ['rev-list', '--left-right', '--count', '$baseRef...HEAD'],
          workingDirectory: path,
        );
        if (r.exitCode == 0) return parse(r);
      } catch (_) {}
    }
    return (ahead: 0, behind: 0);
  }

  /// Creates a new desk for [branch] under the main repo's hidden worktrees
  /// directory, then switches to it as the active desk.
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
          // Capture untracked too — closing a desk should preserve
          // every uncommitted artifact, not just tracked changes.
          includeUntracked: true,
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

  String _normalize(String path) {
    final p = path.replaceAll('\\', '/');
    return Platform.isLinux ? p : p.toLowerCase();
  }

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
