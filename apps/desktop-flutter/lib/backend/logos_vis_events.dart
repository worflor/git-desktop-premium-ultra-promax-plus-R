// logos_vis_events.dart — transparency stream for the relevance engine.
//
// The logos pipeline runs in hundreds of milliseconds and is invisible
// to the user. This file exposes a narrow event stream so the review-
// commit loading UI can narrate what's happening geometrically:
// engine resolving → diff sources igniting → heat kernel diffusing
// through the file graph → wells revealing themselves → hunks ranking
// → context packed → transmitted.
//
// The stream is **observational**. Emitters publish events; nobody
// blocks on subscribers. The bus retains the current session's event
// log so a subscriber that attaches mid-session catches up on the
// events that already fired — without it, the canvas misses the
// `EngineResolving` / `EngineReady` / early `DiffSources` events
// that fire between the parent's `setState(loading=true)` and the
// canvas's own `initState` running, and the corresponding visual
// elements (topology dots, ignition, heat rings) silently never
// appear because their `_birth` timestamps stay at -1.
//
// The retained log is bounded by session: the next session clears it
// at the first emit. Memory shape is the same as `_userSpokeBoosts`
// already on the bus — session-scoped collection cleared on the next
// run boundary.
//
// Sessions are scoped by the review request. A user can kick off
// multiple reviews; only the most-recent session's events matter.
// We identify each with an integer [sessionId] allocated on begin.
// Stale events from a superseded session are ignored by the canvas.

import 'dart:async';

/// Base class for every event the relevance pipeline publishes during
/// a review build. Sealed-ish — callers match on the concrete subtype.
abstract class LogosVisEvent {
  const LogosVisEvent(this.sessionId);

  /// Identifies which pipeline invocation this event belongs to. The
  /// canvas ignores events from stale sessions so a user spamming the
  /// Review button doesn't cross-pollute the animation.
  final int sessionId;
}

/// Engine resolution started. The canvas renders the "terrain
/// materialising" frame while this is the latest event.
class LogosVisEngineResolving extends LogosVisEvent {
  const LogosVisEngineResolving(super.sessionId, {required this.repoPath});
  final String repoPath;
}

/// Engine ready — either from cache or freshly built. The canvas
/// crystallises the topology dots at this point.
class LogosVisEngineReady extends LogosVisEvent {
  const LogosVisEngineReady(
    super.sessionId, {
    required this.nodeCount,
    required this.cached,
  });
  final int nodeCount;

  /// True when the resolver returned a cached engine (HEAD unchanged);
  /// false when it rebuilt. Canvas uses this to pick the resolution
  /// timing (cached = snap to ready, fresh = linger on "warming").
  final bool cached;
}

/// Per-file engram index progress. Fires periodically during the
/// parallel encode phase.
class LogosVisEngramIndex extends LogosVisEvent {
  const LogosVisEngramIndex(
    super.sessionId, {
    required this.cacheHits,
    required this.encoded,
    required this.totalPaths,
  });
  final int cacheHits;
  final int encoded;
  final int totalPaths;
}

/// Diff source weights computed. Canvas ignites the source files.
class LogosVisDiffSources extends LogosVisEvent {
  const LogosVisDiffSources(
    super.sessionId, {
    required this.weights,
    required this.churn,
  });

  /// path → source weight (log1p-scaled churn) from the diff probe.
  final Map<String, double> weights;

  /// Total adds + dels. Used for the header stat.
  final int churn;
}

/// Brainstorm-reshaped seed map. Fired by muse after phase 1 returns
/// and the reseeded diffusion is about to kick off. The canvas reads
/// this as a second ignition pulse — the original diff-anchored
/// sources stay lit, but a fresh wavefront rolls out carrying the
/// blended seed weights so the two phases read as one continuous
/// animation (no jump cut between the initial diffusion and the
/// reseed).
class LogosVisReseedSources extends LogosVisEvent {
  const LogosVisReseedSources(
    super.sessionId, {
    required this.weights,
    required this.brainstormIdeas,
    required this.semanticHits,
    required this.wellExpansionFiles,
  });

  /// Updated path → seed weight map after brainstorm anchors are
  /// blended in. Includes the original diff sources (still at 1.0)
  /// plus every brainstorm-surfaced path.
  final Map<String, double> weights;

  /// Total ideas from the brainstorm pass — for the footer stat line.
  final int brainstormIdeas;

  /// Number of K-space KNN hits across all ideas.
  final int semanticHits;

  /// Number of files pulled in via well expansion.
  final int wellExpansionFiles;
}

/// Heat-kernel diffusion complete. Carries the score map + dominant
/// well mapping so the canvas can paint the final state: neighbours
/// ranked, wells visible.
class LogosVisDiffusionComplete extends LogosVisEvent {
  const LogosVisDiffusionComplete(
    super.sessionId, {
    required this.phi,
    required this.wellByPath,
  });

  /// path → final φ score after 3-temperature geometric-mean blend.
  final Map<String, double> phi;

  /// path → dominant well name (from the K-table's wellOf). Only
  /// files with a K-vector appear; others are absent (no well tint).
  final Map<String, String> wellByPath;
}

/// Context plan emitted. The canvas tier-colours the top-K admitted
/// files at their φ positions.
class LogosVisContextPlan extends LogosVisEvent {
  const LogosVisContextPlan(
    super.sessionId, {
    required this.admittedFull,
    required this.admittedSignature,
    required this.admittedBreadcrumb,
  });

  /// Paths admitted at FULL tier.
  final List<String> admittedFull;

  /// Paths admitted at SIGNATURE tier.
  final List<String> admittedSignature;

  /// Paths admitted at BREADCRUMB tier.
  final List<String> admittedBreadcrumb;
}

/// Hunk ranking complete. The canvas footer fills with bars.
class LogosVisHunksRanked extends LogosVisEvent {
  const LogosVisHunksRanked(
    super.sessionId, {
    required this.rankings,
    required this.admitted,
    required this.skipped,
    required this.budgetFraction,
  });

  /// φ scores in descending order (for bar heights).
  final List<double> rankings;

  /// Number of hunks admitted to the prompt.
  final int admitted;

  /// Number of hunks that overflowed the budget.
  final int skipped;

  /// How full the prompt budget is, in [0, 1]. Feeds the packed-bar
  /// indicator at the bottom of the final frame.
  final double budgetFraction;
}

/// One iteration of the recurrent diffusion loop completed. Fires
/// between DiffSources and DiffusionComplete, once per pass. The
/// canvas pulses a heat ring per iteration so the user sees the
/// diffusion expanding outward in waves as it cools.
class LogosVisRecurrentStep extends LogosVisEvent {
  const LogosVisRecurrentStep(
    super.sessionId, {
    required this.iteration,
    required this.noveltyMass,
    required this.promotedPaths,
    required this.hfWeight,
    required this.tpWeight,
  });

  final int iteration;
  final double noveltyMass;
  final int promotedPaths;
  final double hfWeight;
  final double tpWeight;
}

/// Filament flow analysis landed. Higher gap = more fragile.
class LogosVisFlowAnalysis extends LogosVisEvent {
  const LogosVisFlowAnalysis(
    super.sessionId, {
    required this.spectralGaps,
  });
  final Map<String, double> spectralGaps;
}

/// Advection-drift transport field. Carries per-file pull scores and
/// the top directed edges so the canvas can render flowing drift arcs
/// between files where heat moves preferentially in one direction.
class LogosVisTransportField extends LogosVisEvent {
  const LogosVisTransportField(
    super.sessionId, {
    required this.pullByPath,
    required this.arcs,
  });

  /// path → transport pull strength (how strongly this file draws
  /// relevance from its neighbours via the antisymmetric transport).
  final Map<String, double> pullByPath;

  /// Top directed edges: (source, target, strength). Positive strength
  /// means heat flows preferentially from source → target.
  final List<({String from, String to, double strength})> arcs;
}

/// Poincaré disk embedding of the file hierarchy. Gives each file a
/// structurally meaningful 2D position so the canvas can place nodes
/// by directory proximity rather than arbitrary hash angles.
class LogosVisHyperbolicLayout extends LogosVisEvent {
  const LogosVisHyperbolicLayout(
    super.sessionId, {
    required this.coordinates,
  });

  /// path → (x, y) in the Poincaré disk (||(x,y)|| < 1).
  final Map<String, ({double x, double y})> coordinates;
}

/// Context sealed and sent to the model. Canvas renders the beam.
class LogosVisTransmit extends LogosVisEvent {
  const LogosVisTransmit(super.sessionId);
}

/// Pipeline completed (first token received or request finished).
/// Canvas fades out; the review body takes over.
class LogosVisComplete extends LogosVisEvent {
  const LogosVisComplete(super.sessionId);
}

/// Broadcast singleton. Publishers call `emit(event)`; subscribers
/// listen on [stream]. Broadcast so multiple UIs (tests, diagnostics,
/// the canvas) can share the feed.
/// ─── Session scoping via Zone ─────────────────────────────────────────
/// The review pipeline threads through many functions across multiple
/// files — threading a session id as a parameter to every emitter
/// would add noise everywhere. Instead callers wrap their invocation
/// in [runInSession] (which uses `runZoned`) and downstream emitters
/// read the session id from the current Zone via [currentSession].
/// Dart's Future machinery propagates Zone.current across `await`,
/// so every async leg of the pipeline inherits the session id
/// without a single parameter change. If an emitter fires outside a
/// session (e.g. tests, or code paths not wrapped), [emitInSession]
/// silently drops — no session, no subscriber confusion.
class LogosVisBus {
  LogosVisBus._();
  static final LogosVisBus instance = LogosVisBus._();

  static const Symbol _zoneSessionKey = #logosVisSession;

  final StreamController<LogosVisEvent> _controller =
      StreamController<LogosVisEvent>.broadcast(sync: false);

  /// Retained event log for the most recent session. Cleared the
  /// instant a higher session id arrives so we never carry stale
  /// state across runs. Bounded by session length (~10–20 events for
  /// a typical pipeline) and cleared on every new run, so it can't
  /// grow unboundedly. See [subscribe] for the replay path.
  final List<LogosVisEvent> _sessionLog = [];
  int? _sessionLogId;

  int _nextSessionId = 1;

  /// Out-of-band signal from the canvas back into the pipeline: when
  /// a user grabs one of the source spokes (or a neighbour) and pulls
  /// it, the peak pull magnitude is accumulated here keyed by file
  /// path. Muse's reseed diffusion reads + consumes these values
  /// before blending the brainstorm anchors, so a user yanking a
  /// file during "dreaming" actually biases which files the engine
  /// pulls into the synthesis context.
  /// The value is a unit-ish scalar (normalised pull relative to
  /// canvas size); consumers clamp + map to their own weight range.
  /// Cleared by `consumeUserSpokeBoosts()` — fresh run starts clean.
  final Map<String, double> _userSpokeBoosts = <String, double>{};

  /// Record a user-applied pull on [path]. Subsequent calls for the
  /// same path keep the *maximum* magnitude — a user who yanks then
  /// eases off still expresses their strongest intent.
  void recordUserSpokeBoost(String path, double magnitude) {
    if (magnitude <= 0) return;
    final prev = _userSpokeBoosts[path];
    if (prev == null || magnitude > prev) {
      _userSpokeBoosts[path] = magnitude;
    }
  }

  /// Drain the accumulated per-path boosts. Called by the muse
  /// pipeline right before the reseed diffuse so each run reads a
  /// clean snapshot and the next run starts empty.
  Map<String, double> consumeUserSpokeBoosts() {
    if (_userSpokeBoosts.isEmpty) return const {};
    final snapshot = Map<String, double>.from(_userSpokeBoosts);
    _userSpokeBoosts.clear();
    return snapshot;
  }

  /// Allocate a fresh session id + wrap [body] in a zone that exposes
  /// it to downstream emitters. Canvas subscribers observe events
  /// tagged with this id and ignore events from older sessions.
  /// Returns whatever [body] returned. If [body] throws the zone is
  /// closed normally.
  ///
  /// On exit, clears [_sessionLog] iff this session was the latest
  /// one to emit. Without that clear, a canvas mounting between runs
  /// (typical user flow: run completes, user clicks again) would
  /// snapshot the stale log at [subscribe] time and replay the
  /// previous run's events as if they were current — the canvas
  /// animates through the old session, then the new session's first
  /// live event triggers its [_sessionId] reset and the animation
  /// plays a second time. The latest-session check protects the
  /// overlapping-runs case (review + muse fire concurrently): only
  /// the most-recent emitter's exit is allowed to clear; an
  /// already-superseded session leaving has no log to clear.
  Future<T> runInSession<T>(Future<T> Function(int sessionId) body) async {
    final sessionId = _nextSessionId++;
    try {
      return await runZoned(
        () => body(sessionId),
        zoneValues: {_zoneSessionKey: sessionId},
      );
    } finally {
      if (_sessionLogId == sessionId) {
        _sessionLog.clear();
        _sessionLogId = null;
      }
    }
  }

  /// The active session id, or null if the caller isn't inside a
  /// [runInSession] scope. Emitters use this to decide whether to
  /// publish.
  int? get currentSession {
    final v = Zone.current[_zoneSessionKey];
    return v is int ? v : null;
  }

  /// Stream of all emitted events. Prefer [subscribe] for UI consumers
  /// — it folds in the session-log replay so a late-attaching listener
  /// catches up on events that already fired. The raw stream stays
  /// exposed for tests / non-UI consumers that don't need the replay.
  Stream<LogosVisEvent> get stream => _controller.stream;

  /// Subscribe with mid-session catch-up. Listens for live events AND
  /// replays whatever's in [_sessionLog] in original order, so a
  /// handler attaching after the pipeline has started still sees the
  /// `EngineResolving` / `EngineReady` / early `DiffSources` events
  /// it would otherwise miss. The replay runs in a microtask so it
  /// happens after the State that called us has finished initState
  /// (`mounted == true`, `setState` is safe). Live events from the
  /// broadcast stream arrive after the microtask drains, so order is
  /// preserved.
  ///
  /// The handler must be idempotent w.r.t. duplicates — the canvas's
  /// `_birth[element] < 0` checks already guarantee that.
  StreamSubscription<LogosVisEvent> subscribe(
    void Function(LogosVisEvent) handler,
  ) {
    final replay = List<LogosVisEvent>.unmodifiable(_sessionLog);
    final sub = _controller.stream.listen(handler);
    if (replay.isNotEmpty) {
      scheduleMicrotask(() {
        for (final ev in replay) {
          handler(ev);
        }
      });
    }
    return sub;
  }

  /// Emit unconditionally. Prefer [emitInSession] unless the caller
  /// has an explicit session id (e.g. an isolate helper that received
  /// it via message passing).
  void emit(LogosVisEvent event) {
    if (_controller.isClosed) return;
    // Maintain the per-session log alongside the broadcast. New
    // session id → drop the old log; same id → append. Older ids
    // (out-of-order emits, pathological) are added to the live stream
    // for any direct subscribers but skipped from the log so we don't
    // pollute a fresh session's replay.
    if (_sessionLogId == null || event.sessionId > _sessionLogId!) {
      _sessionLogId = event.sessionId;
      _sessionLog
        ..clear()
        ..add(event);
    } else if (event.sessionId == _sessionLogId) {
      _sessionLog.add(event);
    }
    _controller.add(event);
  }

  /// Construct and emit an event using the ambient session id.
  /// Silently drops if there's no active session (caller wasn't
  /// inside [runInSession]). [builder] receives the session id and
  /// returns the concrete event.
  /// Typical call site:
  ///   LogosVisBus.instance.emitInSession((sid) =>
  ///     LogosVisEngineResolving(sid, repoPath: path));
  void emitInSession(LogosVisEvent Function(int sessionId) builder) {
    final id = currentSession;
    if (id == null) return;
    emit(builder(id));
  }
}
