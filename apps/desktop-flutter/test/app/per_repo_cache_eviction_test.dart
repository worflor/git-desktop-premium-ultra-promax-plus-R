import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/file_coupling_state.dart';
import 'package:git_desktop/app/logos_git_state.dart';
import 'package:git_desktop/app/per_repo_head_cache_state.dart';
import 'package:git_desktop/app/repo_embedding_state.dart';
import 'package:git_desktop/app/repository_xray_state.dart';
import 'package:git_desktop/app/workspace_shell.dart' show evictInactiveRepoCaches;
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/repo_native_embedding_builder.dart';

/// A trivially-constructible coupling matrix tagged with [headHash] — the
/// eviction contract only cares about presence/absence keyed by repo, not the
/// matrix contents.
FileCouplingMatrix _matrix(String headHash) => FileCouplingMatrix(
      jaccard: const {},
      headHash: headHash,
      commitsAnalyzed: 0,
    );

/// A minimal in-memory Logos engine — no git subprocess. Reused across repos;
/// eviction is keyed by repo path, the engine identity is irrelevant.
LogosGit _engine() => LogosGit.buildFromStats(
      LogosGitStats(
        touches: const {'a.dart': 1, 'b.dart': 1},
        totalCommits: 2,
        volatility: const {'a.dart': 1.0, 'b.dart': 1.0},
        volMean: 1.0,
        volStddev: 0.1,
        coupling: _matrix('engine'),
        perFileCommitIndices: const {},
      ),
    );

/// Spy that records every [invalidateAllExcept] argument so the wiring can be
/// asserted at the call level (used for the xray control, which has no headless
/// loader seam). Overriding in a test subclass leaves the production class
/// untouched.
class _SpyXray extends RepositoryXrayState {
  final List<String?> calls = [];
  @override
  void invalidateAllExcept(String? repoPath) {
    calls.add(repoPath);
    super.invalidateAllExcept(repoPath);
  }
}

class _SpyCoupling extends FileCouplingState {
  final List<String?> calls = [];
  @override
  void invalidateAllExcept(String? repoPath) {
    calls.add(repoPath);
    super.invalidateAllExcept(repoPath);
  }
}

class _SpyEmbedding extends RepoEmbeddingState {
  final List<String?> calls = [];
  @override
  void invalidateAllExcept(String? repoPath) {
    calls.add(repoPath);
    super.invalidateAllExcept(repoPath);
  }
}

class _SpyLogos extends LogosGitState {
  final List<String?> calls = [];
  @override
  void invalidateAllExcept(String? repoPath) {
    calls.add(repoPath);
    super.invalidateAllExcept(repoPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Behavioral eviction: the three states that grew unbounded ──────────
  //
  // Before the fix the workspace shell only evicted RepositoryXrayState on a
  // repo switch, so FileCouplingState / RepoEmbeddingState / LogosGitState
  // accumulated one cached artifact per repo opened, forever. This proves the
  // switch now drops every inactive repo from all three.
  test('a repo switch evicts the inactive repo from all three per-repo stores',
      () async {
    final coupling = FileCouplingState()
      ..computeOverride =
          (repo) async => ComputeOutcome.success(_matrix('$repo-head'));
    final embedding = RepoEmbeddingState()
      ..computeOverride =
          (repo) async => ComputeOutcome.success(RepoEmbeddingResult(null, '$repo-head'));
    final logos = LogosGitState()..resolveOverride = (repo, {coupling}) async => _engine();

    // Open repo A, then repo B — both land in every store.
    await coupling.loadForRepo('A');
    await embedding.loadForRepo('A');
    await logos.loadForRepo('A');
    await coupling.loadForRepo('B');
    await embedding.loadForRepo('B');
    await logos.loadForRepo('B');

    expect(coupling.matrixFor('A'), isNotNull);
    expect(embedding.valueFor('A'), isNotNull);
    expect(logos.engineFor('A'), isNotNull);
    expect(coupling.matrixFor('B'), isNotNull);
    expect(embedding.valueFor('B'), isNotNull);
    expect(logos.engineFor('B'), isNotNull);

    // The switch to B evicts every sibling and keeps only B.
    evictInactiveRepoCaches(
      activeRepoPath: 'B',
      xray: RepositoryXrayState(),
      coupling: coupling,
      embedding: embedding,
      logos: logos,
    );

    expect(coupling.matrixFor('A'), isNull, reason: 'coupling for A evicted');
    expect(embedding.valueFor('A'), isNull, reason: 'embedding for A evicted');
    expect(logos.engineFor('A'), isNull, reason: 'logos engine for A evicted');

    expect(coupling.matrixFor('B'), isNotNull, reason: 'active repo survives');
    expect(embedding.valueFor('B'), isNotNull, reason: 'active repo survives');
    expect(logos.engineFor('B'), isNotNull, reason: 'active repo survives');
  });

  // ── Parity: all four stores are wired identically on switch ────────────
  //
  // xray is the control — it already worked. This asserts the eviction helper
  // forwards the active path to all four in lock-step. RED before the fix:
  // the shell forwarded only to xray, so the other three spies recorded
  // nothing.
  test('the switch forwards the active path to all four stores in lock-step',
      () {
    final xray = _SpyXray();
    final coupling = _SpyCoupling();
    final embedding = _SpyEmbedding();
    final logos = _SpyLogos();

    evictInactiveRepoCaches(
      activeRepoPath: 'B',
      xray: xray,
      coupling: coupling,
      embedding: embedding,
      logos: logos,
    );
    evictInactiveRepoCaches(
      activeRepoPath: null,
      xray: xray,
      coupling: coupling,
      embedding: embedding,
      logos: logos,
    );

    // Every store sees the same switch sequence — no asymmetry.
    expect(xray.calls, ['B', null]);
    expect(coupling.calls, ['B', null]);
    expect(embedding.calls, ['B', null]);
    expect(logos.calls, ['B', null]);
  });

  // ── null active path clears everything ─────────────────────────────────
  test('switching to no active repo clears all cached entries', () async {
    final coupling = FileCouplingState()
      ..computeOverride =
          (repo) async => ComputeOutcome.success(_matrix('$repo-head'));
    await coupling.loadForRepo('A');
    await coupling.loadForRepo('B');
    expect(coupling.matrixFor('A'), isNotNull);
    expect(coupling.matrixFor('B'), isNotNull);

    coupling.invalidateAllExcept(null);

    expect(coupling.matrixFor('A'), isNull);
    expect(coupling.matrixFor('B'), isNull);
  });

  // ── Generation guard: an eviction that races an in-flight load for a
  //    DIFFERENT repo must not drop the active load's result ──────────────
  test('an eviction racing a sibling does not drop the active in-flight load',
      () async {
    final gateB = Completer<ComputeOutcome<FileCouplingMatrix>>();
    final coupling = FileCouplingState()
      ..computeOverride = (repo) {
        if (repo == 'B') return gateB.future;
        return Future.value(ComputeOutcome.success(_matrix('$repo-head')));
      };

    // A is fully loaded; B's load is in-flight (gated).
    await coupling.loadForRepo('A');
    final bLoad = coupling.loadForRepo('B');
    await Future<void>.delayed(Duration.zero); // let B reach its await
    expect(coupling.isLoading('B'), isTrue);
    expect(coupling.matrixFor('A'), isNotNull);

    // Switch lands on B: evict A while B is still loading.
    evictInactiveRepoCaches(
      activeRepoPath: 'B',
      xray: RepositoryXrayState(),
      coupling: coupling,
      embedding: RepoEmbeddingState(),
      logos: LogosGitState(),
    );
    expect(coupling.matrixFor('A'), isNull, reason: 'sibling A evicted');
    expect(coupling.isLoading('B'), isTrue, reason: 'active load not dropped');

    // B finishes: its result publishes — the generation guard held for the
    // kept repo, so eviction mid-load did not corrupt the active result.
    gateB.complete(ComputeOutcome.success(_matrix('B-head')));
    await bLoad;
    expect(coupling.matrixFor('B'), isNotNull, reason: 'active load published');
    expect(coupling.matrixFor('A'), isNull);
  });

  // ── LogosGit's dual loading gate survives a mid-load sibling eviction ───
  test('logos engine in-flight load survives a sibling eviction', () async {
    final gateB = Completer<LogosGit?>();
    final logos = LogosGitState()
      ..resolveOverride = (repo, {coupling}) {
        if (repo == 'B') return gateB.future;
        return Future.value(_engine());
      };

    await logos.loadForRepo('A');
    final bLoad = logos.loadForRepo('B', coupling: _matrix('B'));
    await Future<void>.delayed(Duration.zero);
    expect(logos.isLoading('B'), isTrue);
    expect(logos.engineFor('A'), isNotNull);

    evictInactiveRepoCaches(
      activeRepoPath: 'B',
      xray: RepositoryXrayState(),
      coupling: FileCouplingState(),
      embedding: RepoEmbeddingState(),
      logos: logos,
    );
    expect(logos.engineFor('A'), isNull, reason: 'sibling A evicted');
    expect(logos.isLoading('B'), isTrue, reason: 'active load not dropped');

    gateB.complete(_engine());
    await bLoad;
    expect(logos.engineFor('B'), isNotNull, reason: 'active load published');
    expect(logos.engineFor('A'), isNull);
  });
}
