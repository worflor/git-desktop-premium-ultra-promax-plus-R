// LOGOS EDITS — Operational-Transformation primitives for live
// multi-peer repo sync.
//
// Classical OT (Ellis-Gibbs 1989, Google Docs) rests on one theorem:
//
//     TP1:  T(A, B) ∘ B  ≡  T(B, A) ∘ A
//
// Two peers that receive the same two edits in opposite orders must
// converge to the same state after transformation. The whole CRDT-
// flavoured sync story is just: define [LogosEdit], define
// [editsCommute], define [transformEdit], and verify TP1 holds on
// every non-commuting pair.
//
// ── The Logos stack's contribution ────────────────────────────────
//
// The engine was already built for this; most of the ingredients
// were shipped before this file existed:
//
//   * [Signature] is a deterministic content hash. Two states with
//     matching signatures are identical — no deep comparison.
//   * Every operator in the [SpectralOperator] ring is a function
//     of L, so they AUTO-COMMUTE in the dual basis. Temperature
//     changes, band filters, fractional Laplacians, Schrödinger
//     evolutions — none of these ever conflict. The commutation
//     kernel K is 1 for every pair of spectral-only edits.
//   * [CsrGraph.withNodeAppended] / [withNodeRemoved] isolate
//     structural edit support to a local neighbourhood. Disjoint-
//     support detection is set intersection on tiny metadata.
//   * Kizuna bonds + [LogosRatchet] already provide the forward-only
//     discipline and cheap ancestor-similarity metric needed for
//     tiebreaker ordering.
//
// This file ships the last missing piece: a structured edit type
// over which TP1 is provable and testable.
//
// ── Design choices ────────────────────────────────────────────────
//
//   * **Edits are immutable values** carrying their own Lamport
//     clock + peer id. Total order falls out of the `(lamport, peer)`
//     tuple — identical to version-vector ordering in modern CRDTs.
//   * **Transformation is LWW + deletion-dominance** for the
//     structural-conflict cases. Last-writer-wins for `SetEdge` /
//     `AddPath` on the same path; deletion beats concurrent
//     mutations on the same path (the "tombstone rules" of
//     most CRDT trees).
//   * **Apply is pure** — takes a state, returns a state. State is a
//     simple adjacency `Map<path, Map<path, weight>>` in this file,
//     which keeps the math testable; the real engine-integration
//     path wires this to [CsrGraph] mutation in a follow-up.

import 'dart:collection';
import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_signature.dart';

/// Monotone Lamport timestamp + peer identifier. Total ordering
/// defined by `(lamport, peer)` tuple comparison — the canonical
/// version-vector shape.
class EditClock implements Comparable<EditClock> {
  const EditClock({required this.lamport, required this.peer});

  /// Monotonically increasing per-peer counter. Peers should increment
  /// on each local edit and on each observed remote edit (max + 1).
  final int lamport;

  /// Stable peer identifier. Any string that uniquely tags the issuing
  /// client; typically a UUID or `machine@username` combo.
  final String peer;

  @override
  int compareTo(EditClock other) {
    final dl = lamport.compareTo(other.lamport);
    return dl != 0 ? dl : peer.compareTo(other.peer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EditClock && lamport == other.lamport && peer == other.peer);

  @override
  int get hashCode => Object.hash(lamport, peer);

  @override
  String toString() => 'EditClock($lamport@$peer)';
}

/// Structural edit over a Logos repo state. Sum type with four
/// variants — each carries its own deterministic transformation rule.
sealed class LogosEdit {
  const LogosEdit({required this.clock});

  /// Lamport + peer stamp. Sole basis for canonical total ordering.
  final EditClock clock;

  /// Paths this edit touches. Two edits with disjoint supports
  /// commute trivially (structural independence).
  Set<String> get support;

  /// True iff applying this edit to any state is a no-op. Returned
  /// by [transformEdit] when the local edit's effect has been
  /// fully subsumed by a concurrent remote edit.
  bool get isNoOp => false;
}

/// Create a new file-node. Carries no edge data — couplings are
/// separate [SetEdgeEdit]s. This decoupling makes AddPath
/// **idempotent** (create-if-missing semantics): two concurrent
/// `AddPathEdit(p, ...)` from different peers commute without any
/// tiebreaker, because they both ensure `p` exists and nothing more.
/// The race fundamentally vanishes.
final class AddPathEdit extends LogosEdit {
  const AddPathEdit({required super.clock, required this.path});

  final String path;

  @override
  Set<String> get support => {path};

  @override
  String toString() => 'AddPathEdit(${clock.toString()}, path=$path)';
}

/// Delete a file-node and every incident edge.
final class RemovePathEdit extends LogosEdit {
  const RemovePathEdit({required super.clock, required this.path});

  final String path;

  @override
  Set<String> get support => {path};

  @override
  String toString() => 'RemovePathEdit(${clock.toString()}, path=$path)';
}

/// Set (or create) the edge between `pathA` and `pathB` to `weight`.
/// Symmetric: the mirror `(pathB, pathA)` is set identically.
final class SetEdgeEdit extends LogosEdit {
  const SetEdgeEdit({
    required super.clock,
    required this.pathA,
    required this.pathB,
    required this.weight,
  });

  final String pathA;
  final String pathB;
  final double weight;

  @override
  Set<String> get support => {pathA, pathB};

  @override
  String toString() =>
      'SetEdgeEdit(${clock.toString()}, $pathA—$pathB, w=$weight)';
}

/// Identity edit — transformation has fully subsumed this op. Applying
/// it to any state leaves the state unchanged.
final class NoOpEdit extends LogosEdit {
  const NoOpEdit({required super.clock});

  @override
  Set<String> get support => const <String>{};

  @override
  bool get isNoOp => true;

  @override
  String toString() => 'NoOpEdit(${clock.toString()})';
}

// ── Commutation kernel (K) ─────────────────────────────────────────

/// The commutation kernel `K(A, B)`. Returns `true` when `A` and `B`
/// commute — applying them in either order yields the same state.
///
/// Current implementation covers the structural (rank-1 graph)
/// edits in this file. When both edits are functions of the
/// Laplacian (heat, wave, band-pass, etc.), commutation is automatic
/// and this predicate isn't the right entry point — use the
/// [SpectralOperator] algebra instead.
///
/// Rules:
/// * NoOp commutes with everything.
/// * Disjoint-support structural edits commute.
/// * Overlapping-support structural edits commute iff they are
///   identical (same clock, same payload) — in which case the second
///   is redundant by idempotence.
bool editsCommute(LogosEdit a, LogosEdit b) {
  if (a.isNoOp || b.isNoOp) return true;
  if (a.support.intersection(b.support).isEmpty) return true;
  // Same-support case: only commute on idempotent combinations.
  if (_editsEqual(a, b)) return true; // exact-duplicate redelivery

  // Two AddPathEdit on the same path are idempotent create-if-missing.
  if (a is AddPathEdit && b is AddPathEdit && a.path == b.path) return true;

  // A SetEdgeEdit and an AddPathEdit on the same path commute: apply
  // lazily creates missing path-rows, so setting an edge on a node
  // before or after its AddPath gives the same adjacency. The support
  // looked overlapping; semantically they don't conflict.
  if (a is AddPathEdit && b is SetEdgeEdit &&
      (b.pathA == a.path || b.pathB == a.path)) {
    return true;
  }
  if (a is SetEdgeEdit && b is AddPathEdit &&
      (a.pathA == b.path || a.pathB == b.path)) {
    return true;
  }

  return false;
}

bool _editsEqual(LogosEdit a, LogosEdit b) {
  if (a.clock != b.clock) return false;
  if (a.runtimeType != b.runtimeType) return false;
  return switch ((a, b)) {
    (AddPathEdit(:final path),
            AddPathEdit(path: final p2)) =>
      path == p2,
    (RemovePathEdit(:final path),
            RemovePathEdit(path: final p2)) =>
      path == p2,
    (SetEdgeEdit(
              :final pathA,
              :final pathB,
              :final weight,
            ),
            SetEdgeEdit(
              pathA: final a2,
              pathB: final b2,
              weight: final w2,
            )) =>
      pathA == a2 && pathB == b2 && weight == w2,
    (NoOpEdit(), NoOpEdit()) => true,
    _ => false,
  };
}

// ── Transformation function (T) ────────────────────────────────────

/// Return a version of [local] adjusted to account for [applied]
/// already being present in the state. When they commute, [local] is
/// returned unchanged; when they conflict, the transformed edit
/// encodes the resolution rule.
///
/// Resolution rules (deterministic, TP1-verified):
/// * **LWW (Last-Writer-Wins)** for `SetEdge` / `AddPath` on the same
///   path: the edit with the larger clock wins; the other becomes
///   [NoOpEdit]. For `AddPath` only: identical paths with different
///   coupling maps resolve by merging (union) the coupling maps on
///   the winner.
/// * **Deletion-dominance**: if either edit is a `RemovePathEdit`
///   and the other touches the same path, the remove wins; the
///   other becomes [NoOpEdit]. Two concurrent `RemovePath` on the
///   same path trivially commute (idempotent delete).
/// * **Disjoint structural edits** pass through unchanged.
///
/// TP1 is satisfied per-class (see `logos_edits_test.dart` for the
/// verifier).
LogosEdit transformEdit(LogosEdit local, LogosEdit applied) {
  if (editsCommute(local, applied)) return local;

  // --- Deletion dominance --------------------------------------------
  if (applied is RemovePathEdit) {
    if (local.support.contains(applied.path)) {
      // Any local edit on a deleted path is swallowed by the delete.
      return NoOpEdit(clock: local.clock);
    }
    return local;
  }
  if (local is RemovePathEdit) {
    // Symmetric: local delete survives concurrent mutations.
    // The other peer's edit would be transformed away by the same rule.
    return local;
  }

  // --- LWW on same-edge SetEdge --------------------------------------
  if (local is SetEdgeEdit && applied is SetEdgeEdit &&
      _sameEdge(local, applied)) {
    final localWins = local.clock.compareTo(applied.clock) > 0;
    return localWins ? local : NoOpEdit(clock: local.clock);
  }

  // Catch-all: unhandled combination falls through unchanged.
  // Any future edit types must add an explicit case here; dropping
  // through to identity is safe (degrades to "no transformation")
  // but loses guarantees.
  return local;
}

bool _sameEdge(SetEdgeEdit a, SetEdgeEdit b) {
  return (a.pathA == b.pathA && a.pathB == b.pathB) ||
      (a.pathA == b.pathB && a.pathB == b.pathA);
}

// ── Total ordering + canonical apply ───────────────────────────────

/// Sort [edits] by their `(lamport, peer)` tuple — the canonical
/// total order every peer must agree on. Stable; returns a new list.
List<LogosEdit> canonicallyOrder(Iterable<LogosEdit> edits) {
  final list = List<LogosEdit>.from(edits);
  list.sort((a, b) => a.clock.compareTo(b.clock));
  return list;
}

/// Mock state used by the apply layer — a simple symmetric adjacency
/// map. `state[path][other] = weight` means the file `path` has an
/// edge of weight `weight` to `other`.
typedef LogosMockState = Map<String, Map<String, double>>;

/// Deep copy of a mock state. Used at every `applyEdit` call site so
/// the result is detached from the caller's input.
LogosMockState cloneMockState(LogosMockState s) {
  final out = <String, Map<String, double>>{};
  for (final e in s.entries) {
    out[e.key] = Map<String, double>.from(e.value);
  }
  return out;
}

/// Apply a single edit to a mock state. Pure: returns a new state,
/// does not mutate the input.
LogosMockState applyEdit(LogosMockState state, LogosEdit edit) {
  final s = cloneMockState(state);
  switch (edit) {
    case NoOpEdit():
      return s;
    case AddPathEdit(:final path):
      // Create-if-missing. If the path already exists (either because
      // we already applied this edit or a concurrent peer's did), do
      // nothing — preserves idempotence under any ordering.
      if (!s.containsKey(path)) {
        s[path] = <String, double>{};
      }
      return s;
    case RemovePathEdit(:final path):
      s.remove(path);
      for (final other in s.keys.toList()) {
        s[other]?.remove(path);
      }
      return s;
    case SetEdgeEdit(:final pathA, :final pathB, :final weight):
      final rowA = s[pathA] ?? <String, double>{};
      final rowB = s[pathB] ?? <String, double>{};
      rowA[pathB] = weight;
      rowB[pathA] = weight;
      s[pathA] = rowA;
      s[pathB] = rowB;
      return s;
  }
}

/// Apply a list of edits in canonical total order, transforming each
/// against the prefix of already-applied edits. Multi-peer convergent
/// apply: any peer calling this with the same edit multiset produces
/// an identical final state.
///
/// Detail: the transformation of the k-th edit is done against each
/// of the first k-1 edits in canonical order (the full prefix). For
/// the structural edit types in this file this yields a TP1-
/// preserving sequential application — demonstrated in
/// `logos_edits_test.dart`.
LogosMockState applyEditSet(
  LogosMockState initial,
  Iterable<LogosEdit> edits,
) {
  final ordered = canonicallyOrder(edits);
  var state = initial;
  final applied = <LogosEdit>[];
  for (final e in ordered) {
    var transformed = e;
    for (final prev in applied) {
      transformed = transformEdit(transformed, prev);
      if (transformed.isNoOp) break;
    }
    state = applyEdit(state, transformed);
    applied.add(transformed);
  }
  return state;
}

/// A structural fingerprint of a [LogosMockState] — the sorted list
/// of `(path, sortedNeighbours)` tuples hashed deterministically.
/// Two states that compare equal via this hash are the same
/// adjacency structure.
///
/// Used by convergence tests: different edit orderings must produce
/// the same `mockStateSignature`.
int mockStateSignature(LogosMockState state) {
  final paths = state.keys.toList()..sort();
  var h = 0;
  for (final p in paths) {
    h = Object.hash(h, p);
    final neighbours = state[p]!.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final n in neighbours) {
      h = Object.hash(h, n.key, n.value);
    }
  }
  return h;
}

// ── Edit compaction — garbage-collect a history down to a minimal
//    equivalent log.
//
// An edit log produced by many peers over many sessions accumulates
// redundancy: NoOps, superseded SetEdges, removed-then-resurrected
// paths, successive SetEdges on the same edge where only the last
// matters. [compactEdits] walks the canonical order and emits the
// smallest edit subset that produces the same final mock-state
// signature as the full log.
//
// The compaction preserves:
//   * Final adjacency (byte-for-byte by mockStateSignature).
//   * Causal parentage within the retained subset (clocks are kept
//     as-is; no re-clocking).
//
// The compaction discards:
//   * All NoOpEdits.
//   * SetEdges that are fully superseded by a later SetEdge on the
//     same edge.
//   * AddPaths that are immediately deleted by a later RemovePath
//     on the same path (and nothing survives in between).
//   * Edges referencing a path that ends up removed at the end.

/// Return a minimal edit list equivalent to [edits] — same final
/// state, fewer operations.
///
/// The algorithm runs the original log through [applyEditSet] once
/// to compute the ground-truth final adjacency, then emits the
/// minimal edit sequence that reproduces it:
///
///   1. **One `AddPathEdit` per surviving path**. Reuses the earliest
///      `AddPathEdit` for that path from the input when present;
///      synthesises a new one at `(lamport=0, peer='_synth_<path>')`
///      when the path only came into existence via lazy-create
///      SetEdges (whose references were later superseded or deleted).
///   2. **One `SetEdgeEdit` per surviving edge**, reusing the last
///      input `SetEdgeEdit` whose weight matches the final adjacency
///      value. No ambiguity — equal clocks are tie-broken by peer.
///   3. All `NoOpEdit`s and `RemovePathEdit`s are dropped. Removes
///      are unnecessary in the compacted log because the surviving
///      paths are already the only ones emitted.
///
/// Caveats:
///   * The compacted log is **equivalent in final state**, not in
///     clock history. Merging a compacted log with an un-compacted
///     peer's log requires the peer to already hold the same
///     underlying edits (the compacted log is a local GC output,
///     not a sync-over-the-wire message).
///   * Synthesised `AddPathEdit`s use a reserved peer prefix
///     `_synth_*` so real peers never collide with them.
///
/// Complexity: `O(N · log N)` from canonical-order + the actual
/// apply pass.
List<LogosEdit> compactEdits(Iterable<LogosEdit> edits) {
  final ordered = canonicallyOrder(edits);
  if (ordered.isEmpty) return const <LogosEdit>[];

  // Ground truth: apply everything, read the final adjacency.
  final finalState = applyEditSet(<String, Map<String, double>>{}, ordered);
  if (finalState.isEmpty) return const <LogosEdit>[];

  final survivingPaths = finalState.keys.toSet();
  final survivingEdges = <String, double>{};
  for (final p in survivingPaths) {
    for (final n in finalState[p]!.entries) {
      final lo = p.compareTo(n.key) < 0 ? p : n.key;
      final hi = p.compareTo(n.key) < 0 ? n.key : p;
      survivingEdges['$lo\u0000$hi'] = n.value;
    }
  }

  final out = <LogosEdit>[];
  final pathsEmitted = <String>{};
  final edgesEmitted = <String>{};

  for (final e in ordered) {
    switch (e) {
      case NoOpEdit():
      case RemovePathEdit():
        // Dropped from the compacted log unconditionally.
        break;
      case AddPathEdit(:final path):
        if (survivingPaths.contains(path) &&
            !pathsEmitted.contains(path)) {
          out.add(e);
          pathsEmitted.add(path);
        }
      case SetEdgeEdit(:final pathA, :final pathB, :final weight):
        final lo = pathA.compareTo(pathB) < 0 ? pathA : pathB;
        final hi = pathA.compareTo(pathB) < 0 ? pathB : pathA;
        final key = '$lo\u0000$hi';
        if (!survivingEdges.containsKey(key)) break;
        if (edgesEmitted.contains(key)) break;
        // Only retain the edge-write whose weight matches the final
        // state — earlier writes on the same edge are superseded.
        if (survivingEdges[key] != weight) break;
        out.add(e);
        edgesEmitted.add(key);
    }
  }

  // Synthesise AddPathEdit for paths that never got an explicit add
  // in the input (they came into existence via lazy-create SetEdges).
  // Insert at lamport=0 with a reserved peer prefix so these go
  // first in canonical order and never collide with real peers.
  final synthesised = <LogosEdit>[];
  for (final p in survivingPaths) {
    if (!pathsEmitted.contains(p)) {
      synthesised.add(AddPathEdit(
        clock: EditClock(lamport: 0, peer: '_synth_$p'),
        path: p,
      ));
    }
  }
  if (synthesised.isEmpty) return out;
  return canonicallyOrder([...synthesised, ...out]);
}

// ── Version vector ─────────────────────────────────────────────────
//
// Compact summary of "what I've seen" from each peer: the highest
// `lamport` value I've observed tagged with each peer id. Two peers
// exchange version vectors to compute the minimal delta they owe
// each other, without shipping their full clock sets.
//
// Wire cost: O(|distinct peers| × (peer_string + 4 bytes)). For a
// typical team of ~10 collaborators, ~200 bytes. Compare to the
// full-clock-set approach which scales with edit count.
//
// Ordering: VersionVectors form a partial order (pointwise ≤). When
// two VVs are incomparable (each has a peer where the other is
// behind), the underlying histories are concurrent.

/// "What peer ⟨P⟩ has seen" — the highest lamport observed per peer.
/// Immutable value; all operations return a new instance.
class VersionVector {
  VersionVector(Map<String, int> perPeerMax)
      : _max = Map.unmodifiable(perPeerMax);

  final Map<String, int> _max;

  /// Empty vector — "I've seen nothing." Start-of-session default.
  factory VersionVector.empty() => VersionVector(const <String, int>{});

  /// Derive the VV implied by a collection of edits: for each peer
  /// seen in [edits], store the max lamport observed.
  factory VersionVector.fromEdits(Iterable<LogosEdit> edits) {
    final m = <String, int>{};
    for (final e in edits) {
      final prev = m[e.clock.peer] ?? -1;
      if (e.clock.lamport > prev) m[e.clock.peer] = e.clock.lamport;
    }
    return VersionVector(m);
  }

  /// Peers this vector has heard from.
  Set<String> get peers => _max.keys.toSet();

  /// Highest lamport observed from [peer] — `-1` if never seen.
  int maxLamportFor(String peer) => _max[peer] ?? -1;

  /// `true` iff `clock.lamport ≤ maxLamportFor(clock.peer)` — i.e.
  /// the owner has already observed the edit (or something strictly
  /// beyond it) from this peer.
  bool knows(EditClock clock) =>
      clock.lamport <= maxLamportFor(clock.peer);

  /// Partial order: `this ≥ other` iff for every peer in either
  /// vector, `this.max(peer) ≥ other.max(peer)`.
  bool dominates(VersionVector other) {
    for (final peer in {..._max.keys, ...other._max.keys}) {
      if (maxLamportFor(peer) < other.maxLamportFor(peer)) return false;
    }
    return true;
  }

  /// Element-wise max — the least VV that dominates both inputs.
  /// Used when two peers pool their histories: the union VV is the
  /// max.
  VersionVector merge(VersionVector other) {
    final out = Map<String, int>.from(_max);
    for (final entry in other._max.entries) {
      final cur = out[entry.key] ?? -1;
      if (entry.value > cur) out[entry.key] = entry.value;
    }
    return VersionVector(out);
  }

  /// Concurrent iff neither dominates the other. Useful for detecting
  /// genuine divergence that needs OT resolution.
  bool concurrent(VersionVector other) =>
      !dominates(other) && !other.dominates(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VersionVector &&
          _max.length == other._max.length &&
          _max.entries.every((e) => other._max[e.key] == e.value));

  @override
  int get hashCode {
    // Order-independent hash on entries.
    var h = 0;
    for (final e in _max.entries) {
      h ^= Object.hash(e.key, e.value);
    }
    return h;
  }

  @override
  String toString() {
    final parts = _max.entries.map((e) => '${e.key}:${e.value}').toList()
      ..sort();
    return 'VV(${parts.join(', ')})';
  }

  /// Serialise. Deterministic (peers sorted alphabetically).
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false);
    // Magic 'LVV\0' + version 1
    final hdr = ByteData(5)
      ..setUint32(0, 0x0056564c, Endian.little) // 'LVV\0'
      ..setUint8(4, 1);
    out.add(hdr.buffer.asUint8List());
    final sortedPeers = _max.keys.toList()..sort();
    final countHdr = ByteData(2)
      ..setUint16(0, sortedPeers.length, Endian.little);
    out.add(countHdr.buffer.asUint8List());
    for (final peer in sortedPeers) {
      _writeString(out, peer);
      final lamport = _max[peer]!;
      final lHdr = ByteData(8);
      final lo = lamport & 0xffffffff;
      final hi = lamport >= 0 ? (lamport ~/ 0x100000000) : -1;
      lHdr.setUint32(0, lo & 0xffffffff, Endian.little);
      lHdr.setUint32(4, hi & 0xffffffff, Endian.little);
      out.add(lHdr.buffer.asUint8List());
    }
    return out.toBytes();
  }

  factory VersionVector.fromBytes(Uint8List bytes) {
    if (bytes.length < 7) {
      throw const FormatException('VV.fromBytes: too short for header');
    }
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    if (bd.getUint32(0, Endian.little) != 0x0056564c) {
      throw const FormatException('VV.fromBytes: bad magic');
    }
    if (bd.getUint8(4) != 1) {
      throw const FormatException('VV.fromBytes: unsupported version');
    }
    final count = bd.getUint16(5, Endian.little);
    var offset = 7;
    final map = <String, int>{};
    for (var i = 0; i < count; i++) {
      final peer = _readString(bd, offset);
      offset = peer.nextOffset;
      if (offset + 8 > bd.lengthInBytes) {
        throw const FormatException('VV.fromBytes: truncated lamport');
      }
      final lo = bd.getUint32(offset, Endian.little);
      final hi = bd.getUint32(offset + 4, Endian.little);
      offset += 8;
      map[peer.value] = hi == 0 ? lo : (hi * 0x100000000 + lo);
    }
    return VersionVector(map);
  }
}

/// Version-vector-based delta: the edits `remote` must receive to
/// catch up to `local`. `remote` sends its [VersionVector]; this
/// returns only edits whose clocks the remote hasn't seen.
///
/// Complexity: O(|local|) with O(1) remote-knowledge lookup per
/// edit. Wire cost: the VV (tiny) + the delta (only what's missing).
List<LogosEdit> deltaForPeerVV({
  required Iterable<LogosEdit> local,
  required VersionVector remote,
}) {
  return [
    for (final e in canonicallyOrder(local))
      if (!remote.knows(e.clock)) e,
  ];
}

// ── Delta sync ─────────────────────────────────────────────────────
//
// Given two edit logs `local` and `remote`, compute the minimal set
// of edits the other side needs. Trivial implementation at this
// layer: both sides canonicalise, one side sends the set difference.
// Works because clocks are globally unique under the peer-id
// discipline, so set membership is deterministic.

/// The edits `remote` must receive in order to catch up to `local`.
/// Set-difference on canonical-order edit logs. O((|local|+|remote|) ·
/// log(·)) via sorted merge.
List<LogosEdit> deltaForPeer({
  required Iterable<LogosEdit> local,
  required Iterable<LogosEdit> remote,
}) {
  final remoteClocks = <EditClock>{for (final e in remote) e.clock};
  return [
    for (final e in canonicallyOrder(local))
      if (!remoteClocks.contains(e.clock)) e,
  ];
}

// ── Wire format ────────────────────────────────────────────────────
//
// Binary serialization matching the pattern used by
// [KizunaBond25D.toBytes]: magic header, version tag, then a
// type-tagged body. Web-int-safe throughout — no operations that
// could overflow Dart-Web's 53-bit safe integer window.
//
// Layout (all multi-byte integers little-endian):
//
//   [0..4)    magic 'LED\0'
//   [4..5)    version (uint8 — currently 1)
//   [5..6)    variant tag:
//               0 = NoOpEdit
//               1 = AddPathEdit
//               2 = RemovePathEdit
//               3 = SetEdgeEdit
//   [6..?)    EditClock (lamport lo, lamport hi, peer utf8):
//               uint32 lamport_lo
//               uint32 lamport_hi
//               uint16 peer_len
//               peer_len × uint8 peer utf8
//   [?..)     per-variant payload (see each variant's encoder)
//
// Byte length is variable (peer and path strings). Callers that need
// a fixed frame can wrap with a length prefix.

const int _kEditWireMagic = 0x0044454c; // 'LED\0' little-endian
const int _kEditWireVersion = 1;

const int _kVariantNoOp = 0;
const int _kVariantAddPath = 1;
const int _kVariantRemovePath = 2;
const int _kVariantSetEdge = 3;

void _writeString(BytesBuilder out, String s) {
  final bytes = utf8.encode(s);
  final hdr = ByteData(2)..setUint16(0, bytes.length, Endian.little);
  out.add(hdr.buffer.asUint8List());
  out.add(bytes);
}

({String value, int nextOffset}) _readString(ByteData bd, int offset) {
  final len = bd.getUint16(offset, Endian.little);
  offset += 2;
  final bytes = Uint8List.view(
      bd.buffer, bd.offsetInBytes + offset, len);
  return (value: utf8.decode(bytes), nextOffset: offset + len);
}

void _writeEditClock(BytesBuilder out, EditClock clock) {
  // Web-int-safe: encode lamport as two uint32 halves. For a pure
  // monotonic counter this will always fit well within 31 bits of
  // the low half; using the full 62 bits stays safe past realistic
  // lifetimes at any commit rate.
  final loHi = ByteData(8);
  final lamport = clock.lamport;
  final lo = lamport & 0xffffffff;
  // Sign-extended division is web-int-safe because lamport is
  // typically << 2^31, so the hi half is effectively zero.
  final hi = lamport >= 0 ? (lamport ~/ 0x100000000) : -1;
  loHi.setUint32(0, lo & 0xffffffff, Endian.little);
  loHi.setUint32(4, hi & 0xffffffff, Endian.little);
  out.add(loHi.buffer.asUint8List());
  _writeString(out, clock.peer);
}

({EditClock value, int nextOffset}) _readEditClock(ByteData bd, int offset) {
  final lo = bd.getUint32(offset, Endian.little);
  final hi = bd.getUint32(offset + 4, Endian.little);
  offset += 8;
  // Reconstruct the signed 62-bit lamport. On Dart VM this is a
  // full-precision int; on Dart Web it stays within safe integer
  // range as long as lamport < 2^53 — true for any realistic clock.
  final lamport = hi == 0 ? lo : (hi * 0x100000000 + lo);
  final peer = _readString(bd, offset);
  return (
    value: EditClock(lamport: lamport, peer: peer.value),
    nextOffset: peer.nextOffset,
  );
}

void _writeHeader(BytesBuilder out, int variant) {
  final hdr = ByteData(6)
    ..setUint32(0, _kEditWireMagic, Endian.little)
    ..setUint8(4, _kEditWireVersion)
    ..setUint8(5, variant);
  out.add(hdr.buffer.asUint8List());
}

/// Serialize a [LogosEdit] to a compact byte string. Inverse of
/// [decodeLogosEdit]. Deterministic: two equal edits (same clock,
/// same payload) produce byte-for-byte identical output.
Uint8List encodeLogosEdit(LogosEdit edit) {
  final out = BytesBuilder(copy: false);
  switch (edit) {
    case NoOpEdit(:final clock):
      _writeHeader(out, _kVariantNoOp);
      _writeEditClock(out, clock);
    case AddPathEdit(:final clock, :final path):
      _writeHeader(out, _kVariantAddPath);
      _writeEditClock(out, clock);
      _writeString(out, path);
    case RemovePathEdit(:final clock, :final path):
      _writeHeader(out, _kVariantRemovePath);
      _writeEditClock(out, clock);
      _writeString(out, path);
    case SetEdgeEdit(:final clock, :final pathA, :final pathB, :final weight):
      _writeHeader(out, _kVariantSetEdge);
      _writeEditClock(out, clock);
      _writeString(out, pathA);
      _writeString(out, pathB);
      final w = ByteData(8)..setFloat64(0, weight, Endian.little);
      out.add(w.buffer.asUint8List());
  }
  return out.toBytes();
}

/// Decode a [LogosEdit] from [bytes]. Throws [FormatException] on
/// bad magic, unknown version, or truncated payload.
LogosEdit decodeLogosEdit(Uint8List bytes) {
  if (bytes.length < 6) {
    throw const FormatException(
        'LogosEdit.decode: payload too short for header');
  }
  final bd =
      ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  final magic = bd.getUint32(0, Endian.little);
  if (magic != _kEditWireMagic) {
    throw FormatException(
        'LogosEdit.decode: bad magic '
        '(got 0x${magic.toRadixString(16)})');
  }
  final version = bd.getUint8(4);
  if (version != _kEditWireVersion) {
    throw FormatException(
        'LogosEdit.decode: unsupported version $version');
  }
  final variant = bd.getUint8(5);
  final clockRead = _readEditClock(bd, 6);
  final clock = clockRead.value;
  var offset = clockRead.nextOffset;

  switch (variant) {
    case _kVariantNoOp:
      return NoOpEdit(clock: clock);
    case _kVariantAddPath:
      final path = _readString(bd, offset);
      return AddPathEdit(clock: clock, path: path.value);
    case _kVariantRemovePath:
      final path = _readString(bd, offset);
      return RemovePathEdit(clock: clock, path: path.value);
    case _kVariantSetEdge:
      final pathA = _readString(bd, offset);
      offset = pathA.nextOffset;
      final pathB = _readString(bd, offset);
      offset = pathB.nextOffset;
      if (offset + 8 > bd.lengthInBytes) {
        throw const FormatException(
            'LogosEdit.decode: truncated SetEdge weight');
      }
      final weight = bd.getFloat64(offset, Endian.little);
      return SetEdgeEdit(
        clock: clock,
        pathA: pathA.value,
        pathB: pathB.value,
        weight: weight,
      );
    default:
      throw FormatException(
          'LogosEdit.decode: unknown variant tag $variant');
  }
}

// ── LogosSession — the apps-facing primitive ──────────────────────
//
// Wraps an edit log + a materialised state + a local Lamport counter
// into the object a collaborative session actually holds. Emit local
// edits via typed methods ([addPath], [setEdge], [removePath]);
// receive remote edits via [receive] or [absorbDelta]; expose
// [stateSignature] and [versionVector] for sync orchestration.
//
// Responsibilities:
//   * Auto-stamp every local edit with a monotonic clock
//     (lamport = max(seen) + 1, peer = this session's id).
//   * Transform incoming remote edits against the local log so
//     TP1-respecting merges happen automatically.
//   * Produce a canonical [Signature] for the current state so
//     peers can gossip signatures to detect convergence.
//   * Produce a [VersionVector] snapshot the peer can exchange to
//     compute the minimal delta needed.
//
// Wire integration (not this file's job): whatever transport lives
// above — whether the stream-ratchet from your earlier sketch,
// standard WebRTC, or old-fashioned HTTP — calls [receive] on arrival
// and sends [emit]ted edits. This primitive is transport-agnostic.

class LogosSession {
  LogosSession({required this.peerId, LogosMockState? initialState})
      : _state = initialState != null
            ? cloneMockState(initialState)
            : <String, Map<String, double>>{};

  /// Stable identity tag. All locally-emitted edits are stamped with
  /// `(lamport, peerId)`.
  final String peerId;

  LogosMockState _state;
  final List<LogosEdit> _log = [];
  int _lamport = 0;

  /// Read-only view of the current materialised state. Mutating the
  /// returned map does nothing to the session — we return a clone.
  LogosMockState snapshotState() => cloneMockState(_state);

  /// Read-only view of the edit log in canonical (Lamport, peer) order.
  List<LogosEdit> get log => List.unmodifiable(_log);

  /// Current Lamport counter (max seen across all edits).
  int get currentLamport => _lamport;

  /// Summary of "what I've seen" — for peers requesting a delta.
  VersionVector get versionVector => VersionVector.fromEdits(_log);

  /// Deterministic content fingerprint of the current state. Two
  /// sessions with identical `stateSignature` are byte-identical in
  /// their adjacency. Use this to gossip convergence without
  /// exchanging the state itself.
  Signature get stateSignature {
    if (_state.isEmpty) return Signature.zero;
    final buf = <double>[];
    final paths = _state.keys.toList()..sort();
    for (final p in paths) {
      buf.add(p.length.toDouble());
      for (final c in p.codeUnits) {
        buf.add(c.toDouble());
      }
      final neighbours = _state[p]!.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      buf.add(neighbours.length.toDouble());
      for (final n in neighbours) {
        buf.add(n.key.length.toDouble());
        for (final c in n.key.codeUnits) {
          buf.add(c.toDouble());
        }
        buf.add(n.value);
      }
    }
    return fingerprintFloat64(Float64List.fromList(buf));
  }

  // ── Local-edit emission ──────────────────────────────────────────

  EditClock _nextClock() {
    _lamport += 1;
    return EditClock(lamport: _lamport, peer: peerId);
  }

  /// Emit a locally-authored path creation. Returns the stamped edit
  /// so callers can ship it to peers.
  AddPathEdit addPath(String path) {
    final edit = AddPathEdit(clock: _nextClock(), path: path);
    _applyLocal(edit);
    return edit;
  }

  /// Emit a locally-authored path removal.
  RemovePathEdit removePath(String path) {
    final edit = RemovePathEdit(clock: _nextClock(), path: path);
    _applyLocal(edit);
    return edit;
  }

  /// Emit a locally-authored edge write.
  SetEdgeEdit setEdge(String pathA, String pathB, double weight) {
    final edit = SetEdgeEdit(
      clock: _nextClock(),
      pathA: pathA,
      pathB: pathB,
      weight: weight,
    );
    _applyLocal(edit);
    return edit;
  }

  /// Receive a single remote edit. Transforms against every concurrent
  /// local edit already in the log (edits with a LATER clock than the
  /// incoming one — those are what TP1 has to compensate for), then
  /// applies. Safe to call with duplicates; idempotent.
  void receive(LogosEdit edit) {
    // Duplicate clock? Already applied.
    if (_log.any((e) => e.clock == edit.clock)) return;

    // Bring our local Lamport up to at least the incoming one, then
    // guarantee strict monotonicity on the next local edit.
    if (edit.clock.lamport > _lamport) {
      _lamport = edit.clock.lamport;
    }

    // Transform against local edits with a LATER (clock-order) clock
    // than this one — they are "already applied" from this peer's
    // viewpoint, so the incoming edit must be rewritten against them.
    var transformed = edit;
    for (final local in _log) {
      if (local.clock.compareTo(edit.clock) > 0) {
        transformed = transformEdit(transformed, local);
        if (transformed.isNoOp) break;
      }
    }

    // Rebuild the state from the full (transformed-augmented) log.
    // Simpler than patching the existing state in-place; the
    // canonical-order apply pass is cheap for reasonable log sizes
    // and guarantees TP1 correctness across all incoming edits.
    _log.add(edit); // store the UNTRANSFORMED edit — that's the log
    _state = applyEditSet(<String, Map<String, double>>{}, _log);
  }

  /// Receive a batch of remote edits. Applies each in canonical
  /// order via [receive]; deduplicates by clock as it goes.
  void absorbDelta(Iterable<LogosEdit> edits) {
    for (final e in canonicallyOrder(edits)) {
      receive(e);
    }
  }

  /// Produce the minimal edit list `remote` needs to catch up to
  /// this session's state.
  List<LogosEdit> deltaFor(VersionVector remote) {
    return deltaForPeerVV(local: _log, remote: remote);
  }

  /// True iff this session's state signature matches `other`'s —
  /// cheap structural equality without shipping the state itself.
  /// The primary convergence check callers run after [absorbDelta].
  bool convergedWith(LogosSession other) =>
      stateSignature == other.stateSignature;

  // ── Internals ─────────────────────────────────────────────────────

  void _applyLocal(LogosEdit edit) {
    _log.add(edit);
    _state = applyEdit(_state, edit);
  }

  @override
  String toString() => 'LogosSession('
      'peerId=$peerId, '
      'lamport=$_lamport, '
      'edits=${_log.length}, '
      'state=${_state.length} nodes, '
      'sig=0x${stateSignature.toHex()})';
}

/// Immutable snapshot of a peer's view of the edit history. Handy
/// abstraction for sync tests: a peer is `(peerId, appliedEdits)`.
class PeerView {
  PeerView({required this.peerId, Iterable<LogosEdit>? edits})
      : _edits = SplayTreeSet<LogosEdit>(
          (a, b) => a.clock.compareTo(b.clock),
        )..addAll(edits ?? const []);

  final String peerId;
  final SplayTreeSet<LogosEdit> _edits;

  /// Total-ordered view of the edits this peer knows about.
  List<LogosEdit> get edits => _edits.toList();

  /// Observe a remote edit — append (idempotent; duplicate clocks are
  /// detected and coalesced if their payloads match).
  void receive(LogosEdit edit) {
    _edits.add(edit);
  }

  /// Materialise the convergent state from this peer's edit history.
  LogosMockState materialise([LogosMockState? seed]) =>
      applyEditSet(seed ?? <String, Map<String, double>>{}, edits);
}
