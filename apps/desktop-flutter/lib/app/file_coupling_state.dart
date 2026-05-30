import '../backend/file_coupling.dart';
import 'per_repo_head_cache_state.dart';

/// Owns the co-change matrix per repo, cached by HEAD hash.
/// Background-only: UI never waits on it. If the matrix isn't ready
/// yet the changes list renders without cluster stripes; a notify on
/// load fades them in.
class FileCouplingState extends PerRepoHeadCacheState<FileCouplingMatrix> {
  /// Domain-named accessor — same as [valueFor] but reads better at
  /// the call site ("matrix for this repo" vs "value for this repo").
  FileCouplingMatrix? matrixFor(String repoPath) => valueFor(repoPath);

  @override
  Future<ComputeOutcome<FileCouplingMatrix>> compute(String repoPath) async {
    final r = await computeFileCoupling(repoPath);
    if (r.ok && r.data != null) {
      return ComputeOutcome.success(r.data!);
    }
    return ComputeOutcome.failure(r.error ?? computeFailureLabel);
  }

  @override
  String headHashOf(FileCouplingMatrix value) => value.headHash;

  @override
  String get computeFailureLabel => 'failed to compute coupling';
}
