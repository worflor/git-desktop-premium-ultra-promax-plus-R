// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter/foundation.dart';

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

  /// Test-only seam: when set, [compute] resolves through this instead
  /// of the real git-driven [computeFileCoupling], so the per-repo
  /// cache/eviction contract can be exercised headless with no
  /// subprocess. Mirrors [RepositoryState]'s injectable-loader pattern.
  @visibleForTesting
  Future<ComputeOutcome<FileCouplingMatrix>> Function(String repoPath)?
      computeOverride;

  @override
  Future<ComputeOutcome<FileCouplingMatrix>> compute(String repoPath) async {
    final override = computeOverride;
    if (override != null) return override(repoPath);
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
