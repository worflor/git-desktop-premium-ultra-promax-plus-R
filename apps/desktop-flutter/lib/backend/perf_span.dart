// perf_span.dart — lightweight scope-based phase timer.
//
// Wrap a hot backend block to record its wall time into the existing
// DiagnosticsState UI-timing stream. Samples appear in telemetry as
// `compute:<name>` alongside the feature-level interactions, so the
// manifold.telemetry.v3 dashboard shows per-phase breakdown without
// needing a new transport.
//
// Motivation: the outer telemetry already tells us `diff.logos.refresh`
// is 2.6s p95 — but that's a single span covering parse → engine
// resolve → probe build → evidence gather → hunk pack. To pick a
// grimoire optimization with real leverage we need to know which
// inner phase eats the time. Adding spans is cheaper than running a
// full profiler and the cost is negligible (<1µs per span).
//
// The stopwatch reads `elapsedMicroseconds` directly to avoid the
// `Duration.inMilliseconds` truncation that hid sub-ms variations in
// the earlier ad-hoc timing scattered across call sites.
//
// **Isolate caveat**: `DiagnosticsState.instance` is an isolate-local
// singleton. If you call `perfSpan` INSIDE an `Isolate.run` body, the
// timing lands on the worker's singleton and never surfaces in the
// UI dashboard. Wrap the `Isolate.run` call from the caller side
// instead (that's what the LogosGit resolver does for
// `logos.engine.build` — the span is recorded on the main isolate
// while the body runs in the worker). Same rule for `compute()` and
// any other off-thread dispatch.

import 'dart:async';

import '../diagnostics/diagnostics_state.dart';

/// Time the async body as a compute-phase sample named [name].
///
/// Records success + duration even when the body throws, so the
/// telemetry always shows the span — a failing phase is just as
/// interesting as a slow one. Exceptions propagate; the caller sees
/// them the same way they would without instrumentation.
Future<T> perfSpan<T>(
  String name,
  Future<T> Function() body, {
  String phase = 'compute',
  String? tag,
}) async {
  final sw = Stopwatch()..start();
  var ok = true;
  String? errorCode;
  try {
    return await body();
  } catch (_) {
    ok = false;
    errorCode = 'perf_span.threw';
    rethrow;
  } finally {
    sw.stop();
    final event = tag == null ? name : '$name.$tag';
    unawaited(
      DiagnosticsState.instance.recordUiTiming(
        event: event,
        phase: phase,
        durationMs: sw.elapsedMicroseconds / 1000.0,
        ok: ok,
        errorCode: errorCode,
      ),
    );
  }
}

/// Sync variant for hot synchronous blocks (CSR builds, matrix
/// transforms, Chebyshev recurrences). Identical telemetry path; no
/// async gap if the body completes synchronously.
T perfSpanSync<T>(
  String name,
  T Function() body, {
  String phase = 'compute',
  String? tag,
}) {
  final sw = Stopwatch()..start();
  var ok = true;
  String? errorCode;
  try {
    return body();
  } catch (_) {
    ok = false;
    errorCode = 'perf_span.threw';
    rethrow;
  } finally {
    sw.stop();
    final event = tag == null ? name : '$name.$tag';
    unawaited(
      DiagnosticsState.instance.recordUiTiming(
        event: event,
        phase: phase,
        durationMs: sw.elapsedMicroseconds / 1000.0,
        ok: ok,
        errorCode: errorCode,
      ),
    );
  }
}
