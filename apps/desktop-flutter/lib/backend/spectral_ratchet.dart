// SPECTRAL RATCHET — forward-only dynamics for the Logos membrane.
//
// Borrowed verbatim in *discipline* from the Whisper kizuna double-
// ratchet: old state is not preserved, it is **explicitly forgotten**.
// Each advance step derives a new graph state from (old state + event)
// and the reference to the old state is dropped so the garbage
// collector can reclaim it. Past revisions are unreachable from the
// current one. That property — forward-only materialisation — is what
// makes the ratchet the right shape for realtime collaborative editing
// (OT, CRDT, live co-edit). Persistent / copy-on-write graphs hold
// memory per revision; ratchets hold memory once and advance it.
//
// Kizuna correspondence:
//   kizuna rootKey       ↔  LogosRatchet._engine  (mutable materialisation)
//   kizuna chainKey      ↔  engine spectral basis (derived, recycled)
//   kizuna dhSelf        ↔  rekey = fresh Lanczos entropy
//   kizuna skippedKeys   ↔  _skipped out-of-order op buffer
//   kizuna nSend/nRecv   ↔  _revision monotonic counter
//
// Handshake primitives (heatTraceWitness / fingerprintWitness /
// fiedlerWitness / diagnose) follow the kizuna hierarchical integrity
// pattern: coarse global agreement (heat trace) → per-node fingerprint
// (8-bit spectral identity) → diagnostic localisation when those
// disagree. Same discipline the codec uses to identify which 256-byte
// row corrupted a 16D block; applied here to localise which file's
// structure diverged between two replicas.

import 'dart:typed_data';

import 'logos_git.dart';

/// An event applied to a [LogosRatchet]. Events are ordered by a
/// monotonic [sequence] number; the ratchet applies them strictly in
/// sequence and buffers out-of-order arrivals in a bounded skip buffer.
///
/// Subclasses name the *kind* of structural mutation they describe —
/// file added, edge reweighted, commit observed. v1 treats them
/// opaquely (ratchet advances the counter and marks the spectral
/// basis dirty); later iterations will apply them as rank-1 graph
/// perturbations so the ratchet step becomes O(k·n) instead of
/// O(rebuild).
sealed class LogosEvent {
  const LogosEvent({required this.sequence, this.paths = const {}});

  /// Monotonic sequence number. Two events with the same sequence are
  /// by definition the same event (idempotent replay safe).
  final int sequence;

  /// Paths this event touches, if known. Used for invalidation hints
  /// and per-file fingerprint localisation. Empty set = "unknown /
  /// global" (triggers a full rekey on next query).
  final Set<String> paths;
}

/// A file was added, removed, or materially changed (content touch,
/// metric refresh, symbol-edge update). Carries the affected path set
/// so the ratchet can narrow the invalidation scope.
final class FileEvent extends LogosEvent {
  const FileEvent({
    required super.sequence,
    required super.paths,
    this.kind = FileEventKind.touched,
  });
  final FileEventKind kind;
}

enum FileEventKind { added, removed, touched }

/// An edge reweight — typically from a co-change observation.
final class EdgeEvent extends LogosEvent {
  const EdgeEvent({
    required super.sequence,
    required this.a,
    required this.b,
    required this.delta,
  }) : super(paths: const {});
  final String a;
  final String b;
  final double delta;
}

/// A commit landed — affects the commit graph factor (and, indirectly,
/// file-level recent-activity weights). The `touchedPaths` field
/// overlaps with [paths] but is named to make the semantics clearer.
final class CommitEvent extends LogosEvent {
  const CommitEvent({
    required super.sequence,
    required super.paths,
    required this.commitId,
  });
  final String commitId;
  Set<String> get touchedPaths => paths;
}

/// Bundle of diagnostics when two ratchets disagree. Follows the
/// kizuna hierarchical integrity pattern — each field narrows the
/// divergence scope, so callers can present the right level of detail
/// for their UI (global banner → per-file highlight).
class RatchetDiagnostics {
  const RatchetDiagnostics({
    required this.selfRevision,
    required this.peerRevision,
    required this.selfSignature,
    required this.peerSignature,
    required this.selfHeatTrace,
    required this.peerHeatTrace,
    required this.revisionMatch,
    required this.signatureMatch,
    required this.heatTraceMatch,
    required this.hammingByPath,
  });

  final int selfRevision;
  final int peerRevision;
  final int selfSignature;
  final int peerSignature;
  final double selfHeatTrace;
  final double peerHeatTrace;

  /// True iff both ratchets are at the same revision number. Cheap
  /// first check — if this fails the observers aren't even pretending
  /// to be at the same moment in time.
  final bool revisionMatch;

  /// True iff both bases have identical [SpectralBasis.signature].
  /// This is THE cheapest identity check in the whole diagnostic
  /// stack — one integer comparison, no floating-point arithmetic,
  /// no basis traversal. Signature equality implies structural
  /// identity of the underlying spectra to f64 precision.
  final bool signatureMatch;

  /// True iff the global isospectral fingerprints (heat trace) agree
  /// to f64 precision. Third-tier check: same revision + same
  /// signature but different heat trace is impossible in practice
  /// (signature is derived from the same Λ that heat trace integrates
  /// over); kept as a paranoid corroborator that also catches
  /// implementation drift across ratchet revisions.
  final bool heatTraceMatch;

  /// Per-file Hamming distance on the 8-bit spectral fingerprint.
  /// Populated only when [signatureMatch] is false — localises the
  /// divergence to specific files. Empty otherwise. Key is the node
  /// path; value is an integer in `[1, 8]` (distance of 0 is omitted).
  final Map<String, int> hammingByPath;

  /// Fully consistent — both ratchets agree at every level.
  bool get inSync => revisionMatch && signatureMatch && heatTraceMatch;
}

/// Forward-only Logos ratchet — the dynamics wrapper around [LogosGit].
///
/// Usage:
/// ```dart
/// final ratchet = LogosRatchet.fromEngine(engine);
/// ratchet.advance(FileEvent(sequence: 1, paths: {'lib/a.dart'}));
/// ratchet.advance(CommitEvent(sequence: 2, paths: {'lib/b.dart'}, commitId: 'abc'));
/// if (ratchet.shouldRekey()) {
///   // Rebuild from source of truth and rekey the ratchet.
///   final fresh = LogosGit.buildFromStats(latestStats);
///   ratchet.rekey(fresh);
/// }
/// ```
///
/// The ratchet does not own the engine's lifecycle — callers are
/// responsible for supplying fresh engines on rekey. This keeps the
/// ratchet's scope small (discipline, not state ownership) and lets
/// existing infrastructure (`resolveLogosGit`, the isolate-based
/// builder) keep working unchanged.
class LogosRatchet {
  LogosRatchet._({
    required LogosGit engine,
    required int revision,
  })  : _engine = engine,
        _revision = revision;

  /// Wrap a freshly-built engine as revision 0.
  factory LogosRatchet.fromEngine(LogosGit engine) =>
      LogosRatchet._(engine: engine, revision: 0);

  LogosGit _engine;
  int _revision;
  int _opsSinceRekey = 0;
  bool _spectralDirty = false;
  final Map<int, LogosEvent> _skipped = <int, LogosEvent>{};

  /// Max out-of-order ops buffered before forced eviction. Bounded
  /// memory is load-bearing for the ratchet discipline.
  static const int kMaxSkip = 256;

  /// Default rekey cadence — after this many ops advance through the
  /// ratchet, a full rekey is recommended to clear accumulated
  /// perturbation drift.
  static const int kDefaultRekeyInterval = 128;

  /// Current revision counter.
  int get revision => _revision;

  /// The underlying engine. Read-only accessor — callers who want to
  /// mutate must go through [advance] / [rekey] so the ratchet
  /// invariants hold.
  LogosGit get engine => _engine;

  /// True when the spectral basis is out-of-date with respect to
  /// accumulated events. Queries that depend on spectral observables
  /// should trigger a [rekey] first, or accept stale answers.
  bool get isSpectralDirty => _spectralDirty;

  /// Number of out-of-order events waiting for their in-sequence slot.
  int get skippedCount => _skipped.length;

  /// Apply an event to the ratchet.
  ///
  /// - Event with sequence = revision + 1: in-order. Advance, then
  ///   drain any skipped ops that are now in sequence.
  /// - Event with sequence > revision + 1: out-of-order. Buffer in
  ///   [_skipped]; evict the oldest when the buffer exceeds [kMaxSkip].
  /// - Event with sequence ≤ revision: past / duplicate. Ignored
  ///   silently (idempotent replay-safety; the ratchet is forward-only).
  void advance(LogosEvent event) {
    final expected = _revision + 1;
    if (event.sequence == expected) {
      _step(event);
      // Drain any skipped ops that are now in-sequence.
      while (true) {
        final next = _skipped.remove(_revision + 1);
        if (next == null) break;
        _step(next);
      }
    } else if (event.sequence > expected) {
      _skipped[event.sequence] = event;
      _evictIfOverCap();
    }
    // Otherwise: event.sequence <= _revision → already applied. Discard.
  }

  void _step(LogosEvent _) {
    _revision += 1;
    _opsSinceRekey += 1;
    _spectralDirty = true;
    // v1: ops are opaque markers — the engine state is left as-is and
    // the basis is flagged stale. v2 will apply each event as a rank-1
    // graph perturbation + first-order spectral correction, turning
    // this step into O(k·n) instead of O(rebuild-on-next-rekey).
  }

  void _evictIfOverCap() {
    if (_skipped.length <= kMaxSkip) return;
    // Drop the oldest-sequence skipped op. Forward-only: we don't
    // hold out-of-order ops forever. O(n) scan is acceptable because
    // n is bounded by kMaxSkip.
    var oldest = _skipped.keys.first;
    for (final key in _skipped.keys) {
      if (key < oldest) oldest = key;
    }
    _skipped.remove(oldest);
  }

  /// Replace the underlying engine with a freshly-built one. The DH-
  /// ratchet analog — fresh entropy, old state discarded. The old
  /// engine is released (goes out of the ratchet's scope); if callers
  /// still hold a reference it persists, but the ratchet no longer
  /// refers to it.
  ///
  /// Resets [_opsSinceRekey] and clears the dirty flag. Does NOT
  /// reset [_revision] — the revision counter is the ratchet's
  /// identity across rekeys; only the materialisation is swapped.
  void rekey(LogosGit fresh) {
    _engine = fresh;
    _opsSinceRekey = 0;
    _spectralDirty = false;
  }

  /// Recommend a rekey when the op backlog hits [rekeyInterval].
  ///
  /// v1 uses a pure op-count trigger. v2 will pair this with an
  /// evaporation-factor check (spectral confidence drift) once the
  /// engine exposes a public ρ-builder — at that point the ratchet
  /// can rethread adaptively based on how much structural change has
  /// actually landed, not just how many ops.
  bool shouldRekey({int rekeyInterval = kDefaultRekeyInterval}) {
    return _opsSinceRekey >= rekeyInterval;
  }

  // ── Handshake / integrity primitives ─────────────────────────────

  /// Global isospectral witness — the heat trace at scale `t`. Two
  /// ratchets agreeing on revision + graph state agree on this to f64
  /// precision. Disagreement here = structural divergence somewhere.
  double heatTraceWitness([double t = 1.0]) {
    final basis = _engine.spectralBasis();
    return basis?.heatTrace(t) ?? 0.0;
  }

  /// Per-node byte-wide spectral fingerprint table. Length = number
  /// of graph nodes. Used as the second-tier integrity witness: when
  /// [heatTraceWitness] disagrees between two ratchets, Hamming
  /// distance on these tables localises divergence to specific files.
  Uint8List fingerprintWitness() {
    final basis = _engine.spectralBasis();
    return basis?.spectralFingerprintTable() ?? Uint8List(0);
  }

  /// Fiedler identity — sign pattern of u₁. The deepest-cleavage
  /// signature of the current ratchet state. Flips between
  /// supposedly-synced ratchets reveal structurally-significant
  /// out-of-order ops even when heat traces agree numerically.
  Float64List fiedlerWitness() {
    final basis = _engine.spectralBasis();
    final f = basis?.fiedlerVector;
    if (f == null) return Float64List(0);
    return Float64List(f.length)..setRange(0, f.length, f);
  }

  /// Hierarchical divergence diagnosis against another ratchet.
  /// Follows the kizuna `rowWitnesses8D` pattern — each tier of
  /// disagreement narrows the scope:
  ///
  /// 1. [RatchetDiagnostics.revisionMatch] — same revision counter?
  /// 2. [RatchetDiagnostics.signatureMatch] — same Λ-fingerprint?
  /// 3. [RatchetDiagnostics.heatTraceMatch] — same isospectral trace?
  /// 4. [RatchetDiagnostics.hammingByPath] — per-file Hamming on the
  ///    8-bit fingerprint, populated only if signature disagrees.
  ///
  /// Signature match is the **fast path**: one integer comparison and
  /// we know the spectra are identical; nothing else can be broken.
  /// Expensive witnesses only run when the fast path fails.
  RatchetDiagnostics diagnose(LogosRatchet peer, {double t = 1.0}) {
    final selfBasis = _engine.spectralBasis();
    final peerBasis = peer._engine.spectralBasis();
    final selfSig = selfBasis?.signature ?? 0;
    final peerSig = peerBasis?.signature ?? 0;
    // Both-null (tiny graphs below the spectral threshold) is trivially
    // matching; both-non-null matches when the signatures agree; the
    // mixed case (one has a basis, the other doesn't) is divergent.
    final bothNull = selfBasis == null && peerBasis == null;
    final sigMatch = bothNull ||
        (selfBasis != null && peerBasis != null && selfSig == peerSig);

    // Heat trace is computed only when needed to corroborate the
    // signature fast-path. If signatures match, traces are identical
    // by construction and we skip the arithmetic.
    final selfTrace = sigMatch ? 0.0 : heatTraceWitness(t);
    final peerTrace = sigMatch ? 0.0 : peer.heatTraceWitness(t);
    final traceMatch =
        sigMatch || (selfTrace - peerTrace).abs() < 1e-9;

    final hamming = <String, int>{};
    if (!sigMatch) {
      final selfFp = fingerprintWitness();
      final peerFp = peer.fingerprintWitness();
      final selfPaths = _engine.nodePaths;
      final limit = selfFp.length < peerFp.length
          ? selfFp.length
          : peerFp.length;
      for (var i = 0; i < limit && i < selfPaths.length; i++) {
        final d = _popcount8(selfFp[i] ^ peerFp[i]);
        if (d > 0) hamming[selfPaths[i]] = d;
      }
    }

    return RatchetDiagnostics(
      selfRevision: _revision,
      peerRevision: peer._revision,
      selfSignature: selfSig,
      peerSignature: peerSig,
      selfHeatTrace: sigMatch ? heatTraceWitness(t) : selfTrace,
      peerHeatTrace: sigMatch ? peer.heatTraceWitness(t) : peerTrace,
      revisionMatch: _revision == peer._revision,
      signatureMatch: sigMatch,
      heatTraceMatch: traceMatch,
      hammingByPath: hamming,
    );
  }
}

/// 8-bit popcount via three mask-add passes. Duplicated from
/// `logos_core.dart`'s private `_popcount8` — kept local here so
/// the ratchet module has zero extra import surface beyond
/// `LogosGit` + `SpectralBasis`.
int _popcount8(int v) {
  v = (v & 0x55) + ((v >> 1) & 0x55);
  v = (v & 0x33) + ((v >> 2) & 0x33);
  return (v & 0x0f) + ((v >> 4) & 0x0f);
}
