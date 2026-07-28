// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// merge_policy.dart — declared per-field merge for Manifold records.
//
// The generalization the reconcile engine was always headed toward:
// instead of shape-sniffing ("does this list look like comments?"),
// a record TYPE declares how each of its fields merges, and one
// generic engine folds two divergent record versions into a single
// canonical result. The engine inherits the reconcile contracts the
// legacy merge established, asserted on every merge in debug builds:
//
//  * COMMUTATIVE — merge(a, b) == merge(b, a) byte-for-byte, because
//    each peer sees the pair in the opposite order;
//  * CANONICAL FIXPOINT — re-canonicalising the output is a no-op, so
//    the anti-ping-pong equality check can never false-mismatch;
//  * deterministic total order everywhere a collection is emitted.
//
// Policies:
//  * [Lww]        — whole-value from the record-level winner (later
//                   `updatedAt`, sha-lexicographic tiebreak).
//  * [LwwTs]      — whole-value from whichever SIDE'S VALUE carries
//                   the later timestamp field (per-entry recency).
//  * [MaxNum]     — numeric max; never regresses (schema versions).
//  * [UnionList]  — union of object lists by a declared key; colliding
//                   entries either merge recursively under an element
//                   schema or resolve to the winner's entry; output
//                   sorted by a declared total order.
//  * [PerKeyMap]  — union of map keys; colliding values merge under a
//                   declared value policy (recursively composable).

import 'dart:collection';
import 'dart:convert';

/// How one field of a record merges.
sealed class FieldPolicy {
  const FieldPolicy();
}

/// Record-level last-writer-wins: the winning side's value, wholesale.
class Lww extends FieldPolicy {
  const Lww();
}

/// Value-level last-writer-wins: both values must be JSON objects
/// carrying [tsField]; the later one wins (record-level winner breaks
/// ties). A non-conforming value degrades to record-level [Lww].
class LwwTs extends FieldPolicy {
  final String tsField;
  const LwwTs(this.tsField);
}

/// Numeric maximum — monotone, never regresses.
class MaxNum extends FieldPolicy {
  const MaxNum();
}

/// Union of a list of JSON objects by [keyOf]. Entries present on both
/// sides with the same key either merge recursively under [element]
/// (when declared) or resolve to the winning side's entry. Output is
/// sorted by [compare] — a total order over entries, so both machines
/// emit identical bytes.
class UnionList extends FieldPolicy {
  final String Function(Map<String, dynamic>) keyOf;
  final RecordSchema? element;
  final int Function(Map<String, dynamic>, Map<String, dynamic>) compare;

  /// When set (and [element] is null), a same-key collision keeps the
  /// entry whose STRING value at this field is lexicographically
  /// larger — for records that must converge by the SAME rule as some
  /// EXTERNAL authority (review rounds ↔ their pin refs, which adopt
  /// the larger commit sha). Falls back to the record-level winner on
  /// a tie.
  final String? collideBy;

  const UnionList({
    required this.keyOf,
    this.element,
    required this.compare,
    this.collideBy,
  });
}

/// Union of map keys; values colliding on a key merge under [value].
class PerKeyMap extends FieldPolicy {
  final FieldPolicy value;
  const PerKeyMap(this.value);
}

/// A record type's declared merge behaviour: per-field policies (any
/// undeclared field defaults to [Lww]) and the name of its timestamp
/// field, which drives the record-level winner and is emitted as the
/// max of the two sides.
class RecordSchema {
  final Map<String, FieldPolicy> fields;
  final String tsField;
  const RecordSchema({required this.fields, this.tsField = 'updatedAt'});
}

/// Total order on VALUES, used to settle every timestamp tie.
///
/// Compares the canonical encodings, so it depends only on what the two
/// sides actually say. The tiebreak used to be `aSha.compareTo(bSha)` —
/// the commit each blob was READ FROM — which is a property of the
/// container, not the content. That is fine for a single pairwise merge
/// and wrong the moment there are three peers: the merged doc is a NEW
/// commit with an unrelated sha, so a tie settled one way while merging
/// (a,b) settles the other way when that result meets c. Two teammates
/// who saw exactly the same three writes then hold different state
/// forever, and every pairwise merge along the way looks correct.
///
/// Ordering on content makes each field a MAX over `(timestamp,
/// canonical bytes)`, and max is associative — which is precisely the
/// property three-way convergence needs. Caught by M9.
int _contentCompare(Object? a, Object? b) =>
    _canonicalEncode(a).compareTo(_canonicalEncode(b));

DateTime _ts(Object? v) =>
    DateTime.tryParse(v is String ? v : '') ??
    DateTime.fromMillisecondsSinceEpoch(0);

/// Merge two serialized records under [schema]. Returns canonical JSON
/// (sorted keys, two-space indent, same shape the reconcile engine's
/// convergence equality expects).
///
/// Takes NO commit shas. It used to take the two tips as the
/// deterministic tiebreak, which made the result depend on which
/// commits the blobs happened to be read from — see [_contentCompare]
/// for why that cannot survive a third peer. The merge is now a pure
/// function of the two documents, which is also what lets a caller
/// merge an already-merged doc without having to invent a sha for it.
String mergeWithSchema(
  RecordSchema schema,
  String aBlob,
  String bBlob, {
  bool checkContracts = true,
}) {
  final a = jsonDecode(aBlob) as Map<String, dynamic>;
  final b = jsonDecode(bBlob) as Map<String, dynamic>;
  final ta = _ts(a[schema.tsField]);
  final tb = _ts(b[schema.tsField]);
  final cmp = ta.compareTo(tb);

  final merged = _mergeRecord(schema, a, b, recordCmp: cmp);
  merged[schema.tsField] =
      (ta.isAfter(tb) ? ta : tb).toIso8601String();
  final out = _canonicalEncode(merged);

  // The reconcile contracts, live on every merge in debug/test builds
  // and compiled out in release (see the legacy engine's identical
  // guard).
  assert(() {
    if (!checkContracts) return true;
    assert(out == _canonicalEncode(jsonDecode(out)),
        'mergeWithSchema output not canonical');
    final swapped =
        mergeWithSchema(schema, bBlob, aBlob, checkContracts: false);
    assert(out == swapped, 'mergeWithSchema is not commutative');
    return true;
  }());
  return out;
}

Map<String, dynamic> _mergeRecord(
  RecordSchema schema,
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required int recordCmp,
}) {
  final out = <String, dynamic>{};
  for (final k in <String>{...a.keys, ...b.keys}) {
    if (!a.containsKey(k)) {
      out[k] = b[k];
      continue;
    }
    if (!b.containsKey(k)) {
      out[k] = a[k];
      continue;
    }
    out[k] = _mergeValue(
        schema.fields[k] ?? const Lww(), a[k], b[k],
        recordCmp: recordCmp);
  }
  return out;
}

Object? _mergeValue(
  FieldPolicy policy,
  Object? av,
  Object? bv, {
  required int recordCmp,
}) {
  switch (policy) {
    case Lww():
      // The record's own timestamp still decides when it differs — a
      // later write to the record IS later for every plain field on it.
      // Only the tie falls to content.
      if (recordCmp != 0) return recordCmp > 0 ? av : bv;
      return _contentCompare(av, bv) >= 0 ? av : bv;

    case LwwTs(:final tsField):
      if (av is Map<String, dynamic> && bv is Map<String, dynamic>) {
        final c = _ts(av[tsField]).compareTo(_ts(bv[tsField]));
        if (c != 0) return c > 0 ? av : bv;
      }
      // Element-level ties settle on element CONTENT, never on the
      // record around it: an element carried into a merged doc keeps
      // its own identity, while the doc's sha does not survive.
      return _contentCompare(av, bv) >= 0 ? av : bv;

    case MaxNum():
      final an = av is num ? av : null;
      final bn = bv is num ? bv : null;
      if (an == null) return bv;
      if (bn == null) return av;
      return an >= bn ? an : bn;

    case UnionList(
        :final keyOf,
        :final element,
        :final compare,
        :final collideBy
      ):
      // Fold this call's A side first, then B. On a cross-side key
      // collision `prior` is therefore the A-side entry and `e` the
      // B-side one — but NOTHING downstream depends on which side an
      // entry came from. Every resolution here is a max over content,
      // or a per-field merge whose own ties are maxes over content, so
      // the swapped call lands on byte-identical output no matter which
      // side folded first. That is what the commutativity contract
      // asserts on every merge, and it is also why there is no
      // record-level winner threaded through this closure any more:
      // deciding a collision by the containing record is exactly the
      // container-over-content mistake that broke three-peer
      // convergence (see [_contentCompare]).
      final byKey = <String, Map<String, dynamic>>{};
      void fold(Object? side) {
        if (side is! List) return;
        for (final e in side.whereType<Map<String, dynamic>>()) {
          final k = keyOf(e);
          final prior = byKey[k];
          if (prior == null) {
            byKey[k] = e;
            continue;
          }
          // Identical entries collapse silently; differing ones merge
          // under the element schema, or resolve to the winning side's
          // entry when the elements declare no schema.
          if (_canonicalEncode(prior) == _canonicalEncode(e)) continue;
          if (element == null && collideBy != null) {
            final pv = prior[collideBy]?.toString() ?? '';
            final ev = e[collideBy]?.toString() ?? '';
            final c = pv.compareTo(ev);
            if (c != 0) {
              byKey[k] = c > 0 ? prior : e;
              continue;
            }
            // Same collideBy value, differing elsewhere → content.
            byKey[k] = _contentCompare(prior, e) >= 0 ? prior : e;
            continue;
          }
          if (element != null) {
            final eTa = _ts(prior[element.tsField]);
            final eTb = _ts(e[element.tsField]);
            final c = eTa.compareTo(eTb);
            // Pass the element timestamps' comparison and NOTHING else.
            // Feeding a whole-element content compare in on a tie would
            // re-introduce the container problem one level down: the
            // merged element's bytes are neither side's, so a third
            // peer meeting it settles the same tie differently. Letting
            // c stay 0 lets each FIELD break its own tie by its own
            // content, which is a per-field max and therefore
            // associative.
            final mergedE = _mergeRecord(element, prior, e, recordCmp: c);
            mergedE[element.tsField] =
                (eTa.isAfter(eTb) ? eTa : eTb).toIso8601String();
            byKey[k] = mergedE;
          } else {
            byKey[k] = _contentCompare(prior, e) >= 0 ? prior : e;
          }
        }
      }

      fold(av);
      fold(bv);
      final entries = byKey.values.toList()..sort(compare);
      return entries;

    case PerKeyMap(:final value):
      final am = av is Map<String, dynamic> ? av : <String, dynamic>{};
      final bm = bv is Map<String, dynamic> ? bv : <String, dynamic>{};
      final out = <String, dynamic>{};
      for (final k in <String>{...am.keys, ...bm.keys}) {
        if (!am.containsKey(k)) {
          out[k] = bm[k];
        } else if (!bm.containsKey(k)) {
          out[k] = am[k];
        } else {
          out[k] = _mergeValue(value, am[k], bm[k], recordCmp: recordCmp);
        }
      }
      return out;
  }
}

/// Canonical JSON — recursively key-sorted, two-space indent. The same
/// canonical form the reconcile engine's anti-ping-pong equality uses,
/// so schema-merged records converge under the identical check.
String _canonicalEncode(Object? v) =>
    const JsonEncoder.withIndent('  ').convert(_canonicalize(v));

Object? _canonicalize(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return LinkedHashMap<String, Object?>.fromEntries(
        keys.map((k) => MapEntry(k, _canonicalize(v[k]))));
  }
  if (v is List) return v.map(_canonicalize).toList();
  return v;
}
