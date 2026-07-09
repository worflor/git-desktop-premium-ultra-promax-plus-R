// Deterministic property-based-testing runner shared by every fuzz/property
// test in this repo.
//
// Everything here is seed-driven: the *only* source of entropy is an `int`
// seed threaded through a splittable PRNG. There is no wall-clock, and
// `dart:math`'s seedless `Random()` constructor is never used, because its
// unseeded stream is a different (and platform-dependent) sequence on every
// run — the opposite of what a fuzz harness needs. A failing case must be
// reproducible from nothing but the printed `seed` + `index`, so a developer
// can paste those two numbers back in and see the exact same failure.
//
// `forAll` is intentionally simple (a for-loop + try/catch), not a shrinking
// framework with strategy combinators — the goal is "QuickCheck-flavored,
// zero dependencies, fits in one file", not feature parity with a full
// property-testing library.

import 'dart:io' show Platform;

/// A generator: given a random source, produces one value of type [T].
///
/// Generators are plain functions so they compose with ordinary function
/// combinators (`map`, closures, etc.) instead of a bespoke combinator API.
typedef Gen<T> = T Function(Rng rng);

/// A small, deterministic, splittable pseudo-random number generator.
///
/// Implements SplitMix64 (Steele, Lea & Flood 2014) — chosen over
/// `dart:math`'s `Random` because:
///  - `Random(seed)` on the VM does not document or guarantee a stable
///    algorithm across Dart releases, so a seed captured today is not
///    guaranteed to reproduce the same sequence tomorrow;
///  - `Random()` (no seed) is explicitly non-deterministic, which is
///    disallowed for this harness;
///  - SplitMix64 is a few lines of pure 64-bit integer arithmetic, has
///    excellent avalanche/statistical properties for test-data generation,
///    and — critically — is trivial to *split* into independent substreams
///    deterministically (`split()` below), which `Random` cannot do at all.
///
/// All arithmetic runs on the VM's native 64-bit signed `int`. Multiplication
/// and the golden-ratio increment are allowed to wrap on overflow (this is
/// normal, intentional two's-complement behavior for this class of PRNG —
/// only the bit pattern matters, never the arithmetic sign), and every shift
/// uses the unsigned triple-shift operator (`>>>`) so the algorithm's
/// "logical right shift over 64 bits" step is exact regardless of the sign
/// Dart happens to print the intermediate state with.
class Rng {
  int _state;

  Rng(int seed) : _state = seed;

  /// The odd, well-distributed increment SplitMix64 adds to its state each
  /// step (`2^64 / golden ratio`, rounded to an odd 64-bit integer).
  static const int _goldenGamma = 0x9E3779B97F4A7C15;

  /// Advances the internal state and returns the next raw 64-bit word.
  ///
  /// This is the SplitMix64 "finalizer" (a 3-round xor-multiply-shift mix)
  /// applied to the post-increment state. It is *the* primitive everything
  /// else in this class is built from.
  int _nextU64() {
    _state += _goldenGamma;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    z = z ^ (z >>> 31);
    return z;
  }

  /// A uniform integer in `[0, maxExclusive)`.
  ///
  /// Uses the low 63 bits of a fresh word modulo [maxExclusive]. For the
  /// small ranges test-data generators use (tens to low millions) the
  /// resulting modulo bias is negligible; this generator prioritizes
  /// simplicity/auditability over bit-perfect uniformity.
  int nextInt(int maxExclusive) {
    if (maxExclusive <= 0) {
      throw ArgumentError.value(
        maxExclusive,
        'maxExclusive',
        'must be > 0',
      );
    }
    if (maxExclusive == 1) return 0;
    final nonNegative = _nextU64() >>> 1; // clear the sign bit -> 63 bits
    return nonNegative % maxExclusive;
  }

  /// A uniform integer in `[lo, hi]` — inclusive on *both* ends.
  int intBetween(int lo, int hi) {
    if (hi < lo) {
      throw ArgumentError('hi ($hi) must be >= lo ($lo)');
    }
    final span = hi - lo + 1;
    return lo + nextInt(span);
  }

  /// A uniform double in `[0, 1)`, built from the top 53 bits of a fresh
  /// word (53 bits is the full mantissa precision of a Dart `double`).
  double nextDouble() {
    final top53 = _nextU64() >>> 11;
    return top53 / 9007199254740992.0; // 2^53
  }

  /// A uniform coin flip.
  bool nextBool() => nextInt(2) == 0;

  /// Picks one element of [items] uniformly at random.
  T pick<T>(List<T> items) {
    if (items.isEmpty) {
      throw ArgumentError('cannot pick from an empty list');
    }
    return items[nextInt(items.length)];
  }

  /// Picks [k] elements of [items] *without replacement* (distinct
  /// positions — if [items] itself contains duplicate values the result can
  /// still repeat a value, but never reuses the same source slot twice).
  ///
  /// `k` must be `<= items.length`.
  List<T> sample<T>(List<T> items, int k) {
    if (k < 0) {
      throw ArgumentError.value(k, 'k', 'must be >= 0');
    }
    if (k > items.length) {
      throw ArgumentError(
        'k ($k) must be <= items.length (${items.length})',
      );
    }
    final pool = List<T>.of(items);
    final result = <T>[];
    for (var i = 0; i < k; i++) {
      final index = nextInt(pool.length);
      result.add(pool.removeAt(index));
    }
    return result;
  }

  /// Returns an independent substream, deterministically derived from (and
  /// advancing) this generator's current state.
  ///
  /// Because the derivation is a pure function of the current state,
  /// calling `split()` at the same point in two otherwise-identical runs
  /// always yields two `Rng`s with identical future sequences — "splittable"
  /// meaning "forkable without losing determinism", not "randomized".
  Rng split() => Rng(_nextU64());

  /// Draws and returns the next raw 64-bit word, suitable for seeding a new
  /// [Rng] later (e.g. to log a reproducible seed, or to hand a fresh
  /// independent generator to a helper without exposing this one).
  int nextSeed() => _nextU64();
}

/// The SplitMix64 finalizer, exposed standalone so [_deriveCaseSeed] can mix
/// two independent integers (a run seed and a case index) into one seed
/// without constructing a throwaway [Rng].
int _mix64(int z) {
  z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
  z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
  z = z ^ (z >>> 31);
  return z;
}

/// Combines a run [seed] and a case [index] into the seed for that case's
/// [Rng], in O(1) and independent of iteration order — case 199 does not
/// require replaying cases 0..198. This is what makes "seed=S index=I"
/// alone enough to reproduce one specific failing case: rerunning `forAll`
/// with the same `seed` deterministically regenerates the same value at
/// the same `index` every time.
int _deriveCaseSeed(int seed, int index) {
  return _mix64(seed ^ _mix64(index * 0x9E3779B97F4A7C15));
}

/// Runs [check] against `count` values drawn from [gen], each from its own
/// deterministic per-case [Rng] (see [_deriveCaseSeed]).
///
/// On the first failing case:
///  1. if [shrink] is given, greedily re-applies it to the failing value —
///     each candidate is only kept if it *still* fails [check] — stopping
///     as soon as a candidate no-longer-fails, a candidate is `==` to the
///     current value (no further progress possible), or after ~200 steps;
///  2. prints one reproduction line: [describe] (if given), the run
///     `seed`, the failing `index`, and the (possibly shrunk) value's
///     `toString()`;
///  3. rethrows the *original* exception (with its original stack trace) —
///     never a re-derived one from a shrunk candidate, and never swallowed.
///
/// The surrounding `test()` block therefore still fails with the real
/// error, while stdout carries everything needed to reproduce it directly.
void forAll<T>(
  Gen<T> gen, {
  required void Function(T value) check,
  int count = 200,
  int seed = 0x5EED,
  String? describe,
  T Function(T value)? shrink,
}) {
  for (var index = 0; index < count; index++) {
    final rng = Rng(_deriveCaseSeed(seed, index));
    final value = gen(rng);
    try {
      check(value);
    } catch (error, stackTrace) {
      final reported = shrink == null
          ? value
          : _shrinkToSmallestFailure(value, check, shrink);
      final label = describe == null ? '' : '$describe — ';
      // ignore: avoid_print
      print(
        '[prop] ${label}FAILED at seed=0x${seed.toRadixString(16)} '
        'index=$index\n'
        '[prop] value=${reported.toString()}\n'
        '[prop] reproduce: rerun forAll with seed=0x${seed.toRadixString(16)} '
        '(same seed -> same failure at index $index, deterministically)',
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// Greedy shrink loop used by [forAll]: repeatedly applies [shrink] to the
/// current failing value, keeping the candidate only while it still fails
/// [check]. Stops on the first candidate that no longer fails, the first
/// candidate `==` the current value (shrink has bottomed out), or after 200
/// steps (a hard cap so a buggy `shrink` can never hang the suite).
T _shrinkToSmallestFailure<T>(
  T initial,
  void Function(T value) check,
  T Function(T value) shrink,
) {
  var current = initial;
  for (var step = 0; step < 200; step++) {
    final candidate = shrink(current);
    if (candidate == current) break;
    try {
      check(candidate);
      break; // candidate no longer fails -> current was already minimal
    } catch (_) {
      current = candidate; // still fails -> keep shrinking from here
    }
  }
  return current;
}

/// Reads `MANIFOLD_FUZZ` from the environment as a multiplier for how many
/// cases a "deep" run should generate (e.g. `count: 200 * fuzzScale()`).
/// Missing/unparseable/`<1` values all fall back to `1` (the normal,
/// fast, CI-sized run) — this knob is purely additive for local deep fuzzing
/// sessions, never required for a suite to pass.
int fuzzScale() {
  final raw = Platform.environment['MANIFOLD_FUZZ'];
  if (raw == null) return 1;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < 1) return 1;
  return parsed;
}
