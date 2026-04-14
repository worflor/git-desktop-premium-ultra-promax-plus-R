// ═════════════════════════════════════════════════════════════════════════
// collaboration_backend.dart — the seam
//
// Manifold's remote-collaboration surfaces (sync panel, branches panel,
// review flows) today call `git.dart` and `gh.dart` directly. That hard-
// codes a centralised, GitHub-shaped trust model into every call site.
//
// This interface is the narrow waist a future peer-to-peer backend
// plugs into without touching any UI code. Commit one in a series:
//   1. (this) Define the interface + ship `GitHubBackend` as a thin
//      wrapper so existing behaviour is reachable through the seam.
//   2. Migrate call sites from `git.fetchRemote(...)` to
//      `backend.fetch(...)` one feature at a time.
//   3. Implement `BondBackend` against the same interface using the
//      Whisper protocol for transport.
// ═════════════════════════════════════════════════════════════════════════

import 'dtos.dart';
import 'git_result.dart';

/// A source of remote collaboration for a repository.
///
/// Every method is expected to be idempotent on success and return a
/// meaningful [GitResult.err] on failure. Implementations should be
/// cheap to construct; long-lived state (auth handles, peer sessions,
/// caches) belongs in a separate service, not the backend instance.
abstract interface class CollaborationBackend {
  /// Stable identifier. `'github'` for the shipping backend; `'bond'`
  /// once the peer-to-peer implementation lands. Used by the UI to
  /// decide which surfaces to render.
  String get id;

  /// Fetch refs from a remote without integrating them into the
  /// working branch.
  Future<GitResult<SyncData>> fetch(
    String repoPath, {
    String? remote,
    bool prune,
  });

  /// Pull and integrate from a remote.
  Future<GitResult<SyncData>> pull(
    String repoPath, {
    String? remote,
    String? branch,
    bool rebase,
  });

  /// Push the given branch (or current HEAD) to a remote.
  Future<GitResult<SyncData>> push(
    String repoPath, {
    String? remote,
    String? branch,
    bool setUpstream,
    bool forceWithLease,
  });

  /// Smart sync. The exact policy is backend-specific — the existing
  /// Git/GitHub backend publishes branches without upstreams, pulls
  /// and then pushes when both ahead and behind, and otherwise moves
  /// in whichever direction has work.
  Future<GitResult<SyncData>> sync(
    String repoPath,
    RepositoryStatus status,
  );
}
