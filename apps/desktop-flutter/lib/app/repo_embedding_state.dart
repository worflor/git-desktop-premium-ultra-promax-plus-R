import '../backend/repo_native_embedding.dart';
import '../backend/repo_native_embedding_builder.dart';
import 'per_repo_head_cache_state.dart';

/// Owns the repo-native semantic embedding per repo, cached by HEAD hash.
/// Background-only: the Changes page reads the cached embedding (if ready) and
/// hands it to the spectral-coupling pass, which adds semantic file coupling
/// for the changed files. If it isn't ready yet, coupling simply falls back to
/// the co-change + eigenAddress axes; a notify on load lets it fade in.
class RepoEmbeddingState extends PerRepoHeadCacheState<RepoEmbeddingResult> {
  /// Domain-named accessor — the built embedding for this repo, or null if not
  /// loaded yet or the repo was too small to yield one.
  RepoNativeEmbedding? embeddingFor(String repoPath) =>
      valueFor(repoPath)?.embedding;

  @override
  Future<ComputeOutcome<RepoEmbeddingResult>> compute(String repoPath) async {
    // A null embedding (repo too small) is a valid, cacheable outcome — cache
    // it so we don't re-walk the repo on every changeset.
    final r = await computeRepoEmbedding(repoPath);
    return ComputeOutcome.success(r);
  }

  @override
  String headHashOf(RepoEmbeddingResult value) => value.headHash;

  @override
  String get computeFailureLabel => 'failed to compute embedding';
}
