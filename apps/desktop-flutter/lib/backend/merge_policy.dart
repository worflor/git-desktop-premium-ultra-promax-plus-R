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

DateTime _ts(Object? v) =>
    DateTime.tryParse(v is String ? v : '') ??
    DateTime.fromMillisecondsSinceEpoch(0);

/// Merge two serialized records under [schema]. [aSha]/[bSha] are the
/// tips the blobs came from — the deterministic tiebreak both machines
/// share. Returns canonical JSON (sorted keys, two-space indent, same
/// shape the reconcile engine's convergence equality expects).
String mergeWithSchema(
  RecordSchema schema,
  String aBlob,
  String bBlob,
  String aSha,
  String bSha, {
  bool checkContracts = true,
}) {
  final a = jsonDecode(aBlob) as Map<String, dynamic>;
  final b = jsonDecode(bBlob) as Map<String, dynamic>;
  final ta = _ts(a[schema.tsField]);
  final tb = _ts(b[schema.tsField]);
  final cmp = ta.compareTo(tb);
  final aWins = cmp > 0 || (cmp == 0 && aSha.compareTo(bSha) >= 0);

  final merged = _mergeRecord(schema, a, b, aWins: aWins);
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
    final swapped = mergeWithSchema(schema, bBlob, aBlob, bSha, aSha,
        checkContracts: false);
    assert(out == swapped, 'mergeWithSchema is not commutative');
    return true;
  }());
  return out;
}

Map<String, dynamic> _mergeRecord(
  RecordSchema schema,
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required bool aWins,
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
        aWins: aWins);
  }
  return out;
}

Object? _mergeValue(
  FieldPolicy policy,
  Object? av,
  Object? bv, {
  required bool aWins,
}) {
  switch (policy) {
    case Lww():
      return aWins ? av : bv;

    case LwwTs(:final tsField):
      if (av is Map<String, dynamic> && bv is Map<String, dynamic>) {
        final c = _ts(av[tsField]).compareTo(_ts(bv[tsField]));
        if (c != 0) return c > 0 ? av : bv;
      }
      return aWins ? av : bv;

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
      // collision, `prior` is therefore the A-side entry and `e` the
      // B-side one, and the element winner falls back to this call's
      // record-level `aWins` on timestamp ties. That pairing is what
      // makes the swapped call (roles AND aWins both flipped) land on
      // byte-identical output — the commutativity contract asserts it
      // on every merge.
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
            // Same collideBy value, differing elsewhere → record winner.
            byKey[k] = aWins ? prior : e;
            continue;
          }
          if (element != null) {
            final eTa = _ts(prior[element.tsField]);
            final eTb = _ts(e[element.tsField]);
            final c = eTa.compareTo(eTb);
            final priorWins = c > 0 || (c == 0 && aWins);
            final mergedE =
                _mergeRecord(element, prior, e, aWins: priorWins);
            mergedE[element.tsField] =
                (eTa.isAfter(eTb) ? eTa : eTb).toIso8601String();
            byKey[k] = mergedE;
          } else {
            byKey[k] = aWins ? prior : e;
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
          out[k] = _mergeValue(value, am[k], bm[k], aWins: aWins);
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
