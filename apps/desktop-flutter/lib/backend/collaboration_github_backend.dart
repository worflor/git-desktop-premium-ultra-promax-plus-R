// ═════════════════════════════════════════════════════════════════════════
// collaboration_github_backend.dart
//
// The shipping collaboration backend. Wraps the ambient `git` binary for
// ref/object transport and (in later commits) the `gh` CLI for PR and
// issue surfaces. Stateless — every call shells out fresh via git.dart.
//
// Behaviour is intentionally byte-identical to the pre-seam direct
// calls; call sites can migrate one at a time with zero regression.
// ═════════════════════════════════════════════════════════════════════════

import 'collaboration_backend.dart';
import 'dtos.dart';
import 'git.dart' as git;
import 'git_result.dart';

class GitHubBackend implements CollaborationBackend {
  const GitHubBackend();

  @override
  String get id => 'github';

  @override
  Future<GitResult<SyncData>> fetch(
    String repoPath, {
    String? remote,
    bool prune = false,
  }) =>
      git.fetchRemote(repoPath, remote: remote, prune: prune);

  @override
  Future<GitResult<SyncData>> pull(
    String repoPath, {
    String? remote,
    String? branch,
    bool rebase = false,
  }) =>
      git.pullRemote(
        repoPath,
        remote: remote,
        branch: branch,
        rebase: rebase,
      );

  @override
  Future<GitResult<SyncData>> push(
    String repoPath, {
    String? remote,
    String? branch,
    bool setUpstream = false,
    bool forceWithLease = false,
  }) =>
      git.pushRemote(
        repoPath,
        remote: remote,
        branch: branch,
        setUpstream: setUpstream,
        forceWithLease: forceWithLease,
      );

  @override
  Future<GitResult<SyncData>> sync(
    String repoPath,
    RepositoryStatus status,
  ) =>
      git.syncRemote(repoPath, status);
}
