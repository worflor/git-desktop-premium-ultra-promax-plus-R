// json_safety.dart — total, type-safe readers for untrusted JSON.
//
// `j['x'] as T?` is null-safe but not type-safe: a present-but-wrong-typed
// field throws `TypeError` instead of yielding the parser's documented
// default. Wire parsers consuming external process output (git, gh, glab,
// gitea, AI CLIs) and hand-editable on-disk files must degrade per-field,
// never crash the whole parse. Every reader here is total over `Object?`.
//
// Numeric readers additionally reject non-finite values: `jsonDecode`
// happily turns `1e400` into `double.infinity` with no parse error, and a
// downstream `.toInt()` on a non-finite double throws `UnsupportedError`.

/// An integer, or null when [v] isn't one.
///
/// Accepts an `int`, and a `double` whose value is exactly integral — a
/// JSON serializer may legitimately emit `3.0` for an integer field, and
/// that unambiguously means `3`.
///
/// Rejects a FRACTIONAL double (`3.7`) rather than truncating it. A
/// fractional value in an integer field is malformed wire data, and
/// truncating would fabricate a number the sender never transmitted;
/// returning null lets the caller apply its own documented default,
/// which is the honest answer. (Non-finite is likewise rejected — see
/// the header note.)
///
/// Rejects an OUT-OF-RANGE double (`1e308`) for exactly the same reason.
/// `1e308` is finite and integral, so it passes both tests above — but
/// `(1e308).toInt()` does not throw and does not overflow: on the Dart VM
/// it silently *saturates* to `9223372036854775807`, a number the sender
/// never transmitted and that the caller cannot tell apart from a
/// faithfully-decoded int64 max. Same fabrication, different axis.
const double _int64MinAsDouble = -9223372036854775808.0; // -2^63, exact
const double _int64ExclusiveMaxAsDouble = 9223372036854775808.0; // 2^63, exact

int? asIntOrNull(Object? v) {
  if (v is int) return v;
  if (v is double &&
      v.isFinite &&
      v == v.roundToDouble() &&
      v >= _int64MinAsDouble &&
      v < _int64ExclusiveMaxAsDouble) {
    return v.toInt();
  }
  return null;
}

int asIntOr(Object? v, int fallback) => asIntOrNull(v) ?? fallback;

double? asDoubleOrNull(Object? v) =>
    v is num && v.isFinite ? v.toDouble() : null;

double asDoubleOr(Object? v, double fallback) => asDoubleOrNull(v) ?? fallback;

bool? asBoolOrNull(Object? v) => v is bool ? v : null;

bool asBoolOr(Object? v, bool fallback) => v is bool ? v : fallback;

String? asStringOrNull(Object? v) => v is String ? v : null;

String asStringOr(Object? v, String fallback) => v is String ? v : fallback;

/// A JSON object, or null. Accepts any `Map` whose keys are all strings
/// (hand-built `Map<dynamic, dynamic>` included); the key check makes the
/// lazy `cast` view safe to read.
Map<String, Object?>? asMapOrNull(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map && v.keys.every((k) => k is String)) {
    return v.cast<String, Object?>();
  }
  return null;
}

List<Object?>? asListOrNull(Object? v) => v is List ? v : null;
