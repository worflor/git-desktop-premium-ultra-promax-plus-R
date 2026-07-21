// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// PEEK / WARM CACHE — shared protocol for per-key isolate bootstraps.
//
// Three operations form a CPU-style prefetch pattern at the
// orchestration layer:
//
//   peek(key)         — synchronous, never blocks. Returns the cached
//                       value when warm, null otherwise.
//   warm(key)         — fire-and-forget. Kicks the bootstrap in the
//                       background if nothing matching key is cached
//                       or already warming. Idempotent.
//   loadOrAwait(key)  — async. Returns the cached value when warm or
//                       awaits the in-flight bootstrap; otherwise
//                       starts a new bootstrap and awaits it.
//
// Two consumers had this shape inline (GyatLattice, SpectralTrajectory)
// — same gating, same inflight collapse, same swallow-errors-on-warm
// semantics. Centralising removes the third-implementation-reinvents-
// the-locking risk and adds two things both inline copies missed:
//
//   1. A configurable bootstrap timeout. Without one, a hung sync
//      file read inside `Isolate.run` (symlink loop, network mount
//      stall) leaves the bootstrap future never-completing, the
//      inflight slot permanently set, and every subsequent warm or
//      loadOrAwait blocked on the dead future. The timeout forces
//      the outer state machine forward — the cache slot resets and
//      future calls can retry. The isolate may still be hung in
//      the background; we leak one isolate, not the whole consumer.
//
//   2. A documented error-on-warm policy. Warm-up errors are
//      silently swallowed; loadOrAwait errors propagate to the
//      caller. Both consumers had this behaviour; documenting it
//      means a third consumer can't accidentally choose differently.

import 'dart:async';
import 'dart:io' show stderr;

/// Generic per-key cache + inflight-collapser + warm/peek protocol.
///
/// Type parameter [T] is the bootstrapped value (e.g. GyatLattice,
/// SpectralTrajectory). The cache holds at most one entry — the
/// "current" key. Switching keys evicts the previous entry. This
/// matches the per-repo-singleton semantics both existing consumers
/// already use.
class PeekWarmCache<T> {
  /// Run the expensive bootstrap. Typically wraps `Isolate.run(...)`
  /// so the work is off the main isolate. Errors from this future
  /// propagate to [loadOrAwait] callers and are silently swallowed
  /// by [warm] callers.
  final Future<T> Function(String key) bootstrap;

  /// Predicate that decides whether a cached [T] matches a query
  /// [key]. For the GYAT cache this is `(instance, key) =>
  /// instance.repoPath == key`. Allows the cache to hold a value
  /// whose key isn't lexically identical to the lookup key (e.g.
  /// normalised paths).
  final bool Function(T cached, String key) matchesKey;

  /// Hard ceiling on a single bootstrap. When elapsed, the outer
  /// future completes with [TimeoutException] and the inflight slot
  /// resets so future calls can retry. Defaults to 60 seconds —
  /// long enough for an honest GYAT or trajectory cold-start on a
  /// large repo, short enough that a hung sync file read doesn't
  /// permanently wedge the cache. Pass null to disable timeout
  /// (only appropriate for callers that own the bootstrap surface).
  final Duration? timeout;

  /// Tag included in the default stderr log line on warm-up failure.
  /// Consumers should pass a short identifier (e.g. "gyat",
  /// "trajectory") so production logs surface which cache failed.
  /// When [onWarmError] is overridden, [label] is unused.
  final String label;

  /// Called by [warm] when the bootstrap future completes with an
  /// error. Default behavior writes a single line to stderr with the
  /// [label], the [key], and the error — keeps fire-and-forget
  /// non-blocking while still leaving a debugging trail. Consumers
  /// that want richer logging (a diagnostics bus, a telemetry sink)
  /// can override.
  final void Function(String label, String key, Object error,
      StackTrace stackTrace)? onWarmError;

  PeekWarmCache({
    required this.bootstrap,
    required this.matchesKey,
    this.timeout = const Duration(seconds: 60),
    this.label = 'peek_warm_cache',
    this.onWarmError,
  });

  T? _cached;
  String? _cachedKey;
  Future<T>? _inflight;
  String? _inflightKey;

  /// Synchronous peek. Returns the cached value when [key] matches
  /// what's currently cached; null otherwise. Never triggers
  /// bootstrap. Callers that need the value but can't block should
  /// pair this with [warm].
  T? peek(String key) {
    final cached = _cached;
    if (cached != null && _cachedKey == key && matchesKey(cached, key)) {
      return cached;
    }
    return null;
  }

  /// Fire-and-forget warm-up. Kicks [bootstrap] in the background if
  /// nothing matching [key] is cached or already warming. Idempotent
  /// — duplicate calls collapse into the single in-flight future.
  /// Errors are routed through [onWarmError] (default: stderr) so the
  /// failure is visible in production logs without making the call
  /// blocking.
  void warm(String key) {
    if (peek(key) != null) return;
    if (_inflight != null && _inflightKey == key) return;
    unawaited(_runWarmAndSwallow(key));
  }

  /// Internal helper: await the bootstrap, route any error through
  /// [onWarmError] (or the default stderr logger), and return
  /// normally. Allocates no never-completing Completer per failure —
  /// the try/catch shape lets the outer Future&lt;void&gt; resolve
  /// successfully even on bootstrap failure, with the error handled
  /// inline.
  Future<void> _runWarmAndSwallow(String key) async {
    try {
      await loadOrAwait(key);
    } catch (error, stack) {
      final hook = onWarmError ?? _defaultWarmErrorLogger;
      hook(label, key, error, stack);
    }
  }

  /// Awaitable load. Returns cached value, joins an in-flight
  /// bootstrap, or kicks a fresh one. Errors propagate to callers
  /// (caller may decide whether to swallow or surface).
  Future<T> loadOrAwait(String key) {
    final cached = _cached;
    if (cached != null && _cachedKey == key && matchesKey(cached, key)) {
      return Future.value(cached);
    }
    final inflight = _inflight;
    if (inflight != null && _inflightKey == key) {
      return inflight;
    }
    _inflightKey = key;
    Future<T> future = bootstrap(key);
    final timeoutDuration = timeout;
    if (timeoutDuration != null) {
      future = future.timeout(timeoutDuration);
    }
    _inflight = future;
    return future.then((value) {
      if (_inflightKey == key) {
        _cached = value;
        _cachedKey = key;
      }
      return value;
    }).whenComplete(() {
      if (_inflightKey == key) {
        _inflight = null;
        _inflightKey = null;
      }
    });
  }

  /// Drop the cached entry. The next [peek] returns null and the
  /// next [loadOrAwait] / [warm] kicks a fresh bootstrap. An
  /// in-flight bootstrap for the same key is NOT cancelled — its
  /// result, when it arrives, simply doesn't write to the cache
  /// (the key check at the end of [loadOrAwait]'s then-callback
  /// fails after the eviction renames the inflight slot).
  void evict() {
    _cached = null;
    _cachedKey = null;
    // Bump the inflight key so any in-progress future's then-callback
    // sees a mismatched key and skips writing to the cache.
    _inflightKey = null;
    _inflight = null;
  }
}

/// Default warm-error logger — single stderr line per failure. Keeps
/// fire-and-forget non-blocking while leaving a trail production
/// debugging can follow. Format is deliberately compact: one log
/// line per failure carries the cache identity, the key, and the
/// error message; full stack trace omitted (caller can install a
/// richer [PeekWarmCache.onWarmError] hook for that).
void _defaultWarmErrorLogger(
  String label,
  String key,
  Object error,
  StackTrace stackTrace,
) {
  stderr.writeln('[$label] warm-up failed for "$key": $error');
}
