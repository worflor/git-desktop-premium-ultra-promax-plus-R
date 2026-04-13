// ═════════════════════════════════════════════════════════════════════════
// logos_git_resolver.dart — single source of truth for engine lifecycle
//
// BEFORE: two caches existed in parallel (LogosGitState + a static cache
// in ai.dart). Race condition: the UI warmed one, the review path
// warmed the other. Double work, stale copies.
//
// NOW: one resolver. Any caller — UI state class, AI context builder,
// tests — routes through here. Keyed by (repoPath, HEAD hash). Single
// in-flight build per key (duplicate requests await the same Future).
// ═════════════════════════════════════════════════════════════════════════

import 'file_coupling.dart';
import 'git.dart';
import 'logos_git.dart';
import 'logos_git_diagnostics.dart';
import 'logos_git_stats.dart';

class _ResolverEntry {
  final String headHash;
  final LogosGit engine;
  const _ResolverEntry(this.headHash, this.engine);
}

final Map<String, _ResolverEntry> _engines = {};
final Map<String, Future<LogosGit?>> _inflight = {};

/// Resolve the [LogosGit] engine for [repoPath]. Returns the cached
/// engine when HEAD hasn't moved; otherwise builds, caches, returns.
/// Two simultaneous callers for the same repo share a single build.
/// Pass a warm [coupling] matrix to skip one 1000-commit log walk.
Future<LogosGit?> resolveLogosGit(
  String repoPath, {
  FileCouplingMatrix? coupling,
}) {
  final pending = _inflight[repoPath];
  if (pending != null) return pending;

  final future = _resolveImpl(repoPath, coupling);
  _inflight[repoPath] = future;
  future.whenComplete(() => _inflight.remove(repoPath));
  return future;
}

/// Drop any cached engine for [repoPath]. Next [resolveLogosGit] call
/// rebuilds from scratch. Use when HEAD obviously moved and you want
/// the rebuild eager rather than next-lookup-lazy.
void invalidateLogosGit(String repoPath) {
  _engines.remove(repoPath);
}

/// Drop every cached engine. Repo closed, user cleared caches, etc.
void invalidateAllLogosGit() {
  _engines.clear();
}

Future<LogosGit?> _resolveImpl(
  String repoPath,
  FileCouplingMatrix? coupling,
) async {
  final sw = Stopwatch()..start();
  final log = LogosGitDiagnostics.instance;
  try {
    // Staleness check — cheap rev-parse, bail if HEAD unchanged.
    final head = await runGitProbe(
      repoPath,
      const ['rev-parse', 'HEAD'],
    );
    if (head.exitCode != 0) {
      log.recordFailure(repoPath, 'rev-parse HEAD failed', sw.elapsed);
      return null;
    }
    final hash = head.stdout.toString().trim();
    if (hash.isEmpty) {
      log.recordFailure(repoPath, 'empty HEAD hash', sw.elapsed);
      return null;
    }

    final cached = _engines[repoPath];
    if (cached != null && cached.headHash == hash) {
      log.recordCacheHit(repoPath, sw.elapsed);
      return cached.engine;
    }

    final statsResult =
        await collectLogosGitStats(repoPath, coupling: coupling);
    if (!statsResult.ok || statsResult.data == null) {
      log.recordFailure(
        repoPath,
        statsResult.error ?? 'stats collection failed',
        sw.elapsed,
      );
      return null;
    }

    final engine = LogosGit.buildFromStats(statsResult.data!);
    _engines[repoPath] = _ResolverEntry(hash, engine);
    log.recordBuild(
      repoPath: repoPath,
      nodes: engine.nodePaths.length,
      duration: sw.elapsed,
    );
    return engine;
  } catch (e, st) {
    log.recordFailure(repoPath, 'build threw: $e', sw.elapsed, st);
    return null;
  }
}
