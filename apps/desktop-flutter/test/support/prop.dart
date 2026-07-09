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
// ─────────────────────────────────────────────────────────────────────────
// INTERNAL SHRINKING (the "tape")
// ─────────────────────────────────────────────────────────────────────────
//
// A generator is `T Function(Rng)`, and `Rng` is the sole entropy source.
// That means a generated value is a pure function of the sequence of random
// choices the generator made. So instead of asking each call site to hand
// us a bespoke `T -> T` shrink function (which nobody ever did — the old
// `shrink:` parameter was passed at exactly one call site in the whole
// repo, and it was this file's own self-test), we record the choices.
//
// `Rng` writes every bounded draw it makes onto a `_Tape` — a plain
// `List<int>` where entry `i` is the value returned by the `i`-th draw,
// already reduced into `[0, bound)`. Re-running the same generator against
// the same tape reproduces the same value exactly. Shrinking then becomes a
// problem about *lists of small non-negative integers*, independent of `T`:
//
//   - delete a span of the tape  -> shorter lists, fewer graph edges, fewer
//                                   lines of text, fewer repo ops;
//   - reduce an entry toward 0   -> earlier element of a `pick` pool, lower
//                                   `intBetween`, shorter `genAscii` length.
//
// Both moves are re-run through the generator, so the shrunk value is always
// a value the generator could legitimately have produced. This is the
// Hypothesis/`conjecture` design, and its decisive property here is that it
// costs **zero call-site churn**: every existing `forAll` in the repo gains
// minimization without being touched, and every future generator gets it for
// free the moment it draws from `Rng`.
//
// Two invariants make the tape robust to being edited underneath a
// generator:
//   1. `draw(bound)` clamps a replayed entry into `[0, bound)`. A mutated
//      or stale tape can never produce an out-of-range choice, so a
//      generator can never see a value it could not have generated itself.
//   2. If the generator draws past the end of the tape (because a deletion
//      shortened it, or because the generator changed since the tape was
//      recorded), the missing draws are generated fresh from SplitMix64 and
//      *appended*. A tape is a prefix, never a contract.
//
// Invariant 2 is what lets the on-disk corpus (below) survive generator
// edits instead of rotting.
//
// The search itself lives in [_TapeShrinker], a *pull-based* state machine:
// it proposes candidate tapes and is told whether each was accepted. It
// never evaluates anything itself. That is what lets [forAll] (synchronous)
// and [forAllAsync] (which awaits real git subprocesses) share one search
// algorithm instead of maintaining two copies that drift.
//
// ─────────────────────────────────────────────────────────────────────────
// CORPUS
// ─────────────────────────────────────────────────────────────────────────
//
// A printed seed is worthless if nobody types it back in. When a property
// fails, the minimized tape is appended to `test/corpus/<label>.tape`, and
// every subsequent run replays the whole corpus file *before* drawing a
// single random case. A bug found once is a regression test forever, with
// no human in the loop. Set `MANIFOLD_CORPUS=0` to disable read and write.
//
// ─────────────────────────────────────────────────────────────────────────
// COVERAGE
// ─────────────────────────────────────────────────────────────────────────
//
// A property that never generates the interesting input is a property that
// always passes. `collect('merge-conflict')` tags the current case, and
// `requireCoverage: {'merge-conflict': 0.05}` **fails the test** when fewer
// than 5% of cases were tagged. This is the guard against a generator
// silently degenerating as the code drifts under it.

import 'dart:io';

/// A generator: given a random source, produces one value of type [T].
///
/// Generators are plain functions so they compose with ordinary function
/// combinators (`map`, closures, etc.) instead of a bespoke combinator API.
/// See `gen.dart` for the shared combinator vocabulary built on top.
typedef Gen<T> = T Function(Rng rng);

// ---------------------------------------------------------------------------
// The tape
// ---------------------------------------------------------------------------

/// Hard cap on how many draws one generated value may make. A generator that
/// blows through this is looping, and would otherwise hang the shrinker.
const int _kMaxTapeLength = 1 << 20;

/// The recorded choice sequence backing one generated value.
///
/// Shared by an [Rng] and every [Rng.split] descendant of it, so a generator
/// that hands a substream to a helper still records onto one flat tape — a
/// split that recorded onto its own private tape would be invisible to the
/// shrinker, which is the whole point of recording.
class _Tape {
  final List<int> choices;
  int pos = 0;
  int _state;

  _Tape(this.choices, this._state);

  static const int _goldenGamma = 0x9E3779B97F4A7C15;

  int _nextU64() {
    _state += _goldenGamma;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    z = z ^ (z >>> 31);
    return z;
  }

  /// Draws one choice in `[0, bound)`, recording it.
  ///
  /// A `bound` of 1 carries no information, so it is deliberately *not*
  /// recorded — otherwise the tape would fill with forced zeros that the
  /// shrinker would waste evaluations trying to reduce.
  int draw(int bound) {
    if (bound <= 0) {
      throw ArgumentError.value(bound, 'bound', 'must be > 0');
    }
    if (bound == 1) return 0;

    int value;
    if (pos < choices.length) {
      // Replay. Clamp into range: a tape recorded against a different bound
      // (older generator, or a shrink step that moved an earlier draw) must
      // never hand the generator a value it could not have produced.
      value = choices[pos];
      if (value < 0) value = 0;
      if (value >= bound) value = bound - 1;
      choices[pos] = value; // normalise in place: `choices` is canonical
    } else {
      if (choices.length >= _kMaxTapeLength) {
        throw StateError(
          'generator exceeded $_kMaxTapeLength draws for a single value — '
          'it is almost certainly looping',
        );
      }
      value = (_nextU64() >>> 1) % bound;
      choices.add(value);
    }
    pos++;
    return value;
  }
}

// ---------------------------------------------------------------------------
// Rng
// ---------------------------------------------------------------------------

/// A small, deterministic, splittable pseudo-random number generator that
/// records every choice it makes onto a tape (see the file header).
///
/// Implements SplitMix64 (Steele, Lea & Flood 2014) — chosen over
/// `dart:math`'s `Random` because:
///  - `Random(seed)` on the VM does not document or guarantee a stable
///    algorithm across Dart releases, so a seed captured today is not
///    guaranteed to reproduce the same sequence tomorrow;
///  - `Random()` (no seed) is explicitly non-deterministic, which is
///    disallowed for this harness;
///  - SplitMix64 is a few lines of pure 64-bit integer arithmetic and has
///    excellent avalanche/statistical properties for test-data generation.
///
/// All arithmetic runs on the VM's native 64-bit signed `int`. Multiplication
/// and the golden-ratio increment are allowed to wrap on overflow (this is
/// normal, intentional two's-complement behavior for this class of PRNG —
/// only the bit pattern matters, never the arithmetic sign), and every shift
/// uses the unsigned triple-shift operator (`>>>`).
class Rng {
  final _Tape _tape;

  Rng(int seed) : _tape = _Tape(<int>[], seed);

  Rng._on(this._tape);

  /// Replays [tape], generating fresh choices (from [seed]) only once the
  /// tape is exhausted. [tape] is mutated in place into the canonical,
  /// clamped, fully-materialised choice sequence for whatever value the
  /// generator produces.
  factory Rng.fromTape(List<int> tape, {int seed = 0}) =>
      Rng._on(_Tape(tape, seed));

  /// The choice sequence recorded so far. Only meaningful after a generator
  /// has run against this [Rng].
  List<int> get tape => _tape.choices;

  /// A uniform integer in `[0, maxExclusive)`.
  int nextInt(int maxExclusive) {
    if (maxExclusive <= 0) {
      throw ArgumentError.value(maxExclusive, 'maxExclusive', 'must be > 0');
    }
    return _tape.draw(maxExclusive);
  }

  /// A uniform integer in `[lo, hi]` — inclusive on *both* ends.
  ///
  /// Shrinks toward [lo]. That is the right bias for the things this is
  /// usually called with — lengths, depths, counts, indices — where `lo` is
  /// the degenerate case. For a signed quantity where `0` is the simplest
  /// value rather than `lo`, use [simpleIntBetween].
  int intBetween(int lo, int hi) {
    if (hi < lo) {
      throw ArgumentError('hi ($hi) must be >= lo ($lo)');
    }
    return lo + _tape.draw(hi - lo + 1);
  }

  /// A uniform integer in `[lo, hi]` that shrinks toward **zero** (or, if
  /// zero is outside the range, toward whichever endpoint is nearest it).
  ///
  /// The draw is uniform over the range exactly as [intBetween] is; the two
  /// differ only in which value a shrunk tape entry maps to. Enumeration
  /// order is `z, z+1, z-1, z+2, z-2, …`, clipped at whichever end runs out
  /// first and then continuing straight along the other. So a minimized
  /// counterexample reports `0` rather than `-1000`.
  int simpleIntBetween(int lo, int hi) {
    if (hi < lo) {
      throw ArgumentError('hi ($hi) must be >= lo ($lo)');
    }
    final span = hi - lo + 1;
    if (span == 1) return lo;
    final k = _tape.draw(span);
    final z = _simplest(lo, hi);
    if (k == 0) return z;

    final left = z - lo; // how far we can walk down
    final right = hi - z; // how far we can walk up
    final reach = left < right ? left : right;
    final paired = 2 * reach;

    if (k <= paired) {
      final step = (k + 1) ~/ 2;
      return k.isOdd ? z + step : z - step;
    }
    final overflow = k - paired;
    return right > left ? z + reach + overflow : z - reach - overflow;
  }

  static int _simplest(int lo, int hi) {
    if (lo > 0) return lo;
    if (hi < 0) return hi;
    return 0;
  }

  /// A uniform double in `[0, 1)` at full 53-bit mantissa precision.
  /// Shrinks toward `0.0`.
  double nextDouble() => _tape.draw(_kMantissa) / _kMantissa.toDouble();

  static const int _kMantissa = 1 << 53;

  /// A uniform coin flip. Shrinks toward `false`.
  bool nextBool() => _tape.draw(2) == 1;

  /// Picks one element of [items] uniformly at random. Shrinks toward
  /// `items.first`, so pools should list their most boring element first.
  T pick<T>(List<T> items) {
    if (items.isEmpty) {
      throw ArgumentError('cannot pick from an empty list');
    }
    return items[nextInt(items.length)];
  }

  /// Picks [k] elements of [items] *without replacement* (distinct
  /// positions — if [items] itself contains duplicate values the result can
  /// still repeat a value, but never reuses the same source slot twice).
  List<T> sample<T>(List<T> items, int k) {
    if (k < 0) {
      throw ArgumentError.value(k, 'k', 'must be >= 0');
    }
    if (k > items.length) {
      throw ArgumentError('k ($k) must be <= items.length (${items.length})');
    }
    final pool = List<T>.of(items);
    final result = <T>[];
    for (var i = 0; i < k; i++) {
      result.add(pool.removeAt(nextInt(pool.length)));
    }
    return result;
  }

  /// Returns another handle onto the same recorded stream.
  ///
  /// Unlike a classical splittable PRNG this shares the tape rather than
  /// forking an independent substream — a substream with its own private
  /// tape would be invisible to the shrinker. Determinism is unaffected:
  /// parent and child interleave their draws onto one sequence, and the same
  /// program replayed against the same tape makes the same draws in the same
  /// order.
  Rng split() => Rng._on(_tape);

  /// Draws a value suitable for seeding some *other* PRNG (e.g. a helper
  /// that takes an `int` seed rather than an [Rng]). Recorded, so it shrinks
  /// toward `0` like any other choice.
  int nextSeed() => _tape.draw(_kSeedBound);

  static const int _kSeedBound = 1 << 62;
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
/// require replaying cases 0..198.
int _deriveCaseSeed(int seed, int index) {
  return _mix64(seed ^ _mix64(index * 0x9E3779B97F4A7C15));
}

// ---------------------------------------------------------------------------
// Coverage / statistics
// ---------------------------------------------------------------------------

/// Raised when a `requireCoverage` floor is not met. Distinct from an
/// ordinary property failure: the property never found a counterexample, it
/// simply never *looked* at the inputs it was supposed to.
class PropCoverageError extends Error {
  final String describe;
  final String label;
  final double observed;
  final double required;
  final int cases;

  PropCoverageError({
    required this.describe,
    required this.label,
    required this.observed,
    required this.required,
    required this.cases,
  });

  @override
  String toString() =>
      'PropCoverageError: $describe — only ${(observed * 100).toStringAsFixed(1)}% '
      'of $cases cases were tagged `$label`, below the required '
      '${(required * 100).toStringAsFixed(1)}%. The generator is not producing '
      'the input this property exists to test.';
}

/// Labels active for the case currently executing, or `null` outside a
/// `forAll`. Single-threaded by construction: `flutter test` runs one test
/// body at a time within an isolate.
Set<String>? _currentCaseLabels;

/// Tags the case currently being checked with [label].
///
/// Counted once per case no matter how many times it is called. Combine with
/// `requireCoverage: {'label': fraction}` to make a degenerate generator fail
/// loudly instead of passing vacuously, and with `printStats: true` (or
/// `MANIFOLD_PROP_STATS=1`) to see the distribution.
void collect(String label) => _currentCaseLabels?.add(label);

/// `collect(label)` iff [condition]. Sugar for the common shape.
void classify(bool condition, String label) {
  if (condition) collect(label);
}

// ---------------------------------------------------------------------------
// Candidate evaluation
// ---------------------------------------------------------------------------

/// Outcome of replaying one candidate tape.
enum _Verdict {
  /// The generator itself threw (the tape is not a legal input to it).
  invalid,

  /// The generator produced a value and `check` accepted it.
  passed,

  /// `check` threw, but with a different exception type than the original —
  /// a *different* bug. Rejected, so the shrinker stays on one target.
  failedDifferently,

  /// `check` threw the same exception type. A legitimate smaller
  /// counterexample.
  failedSame,
}

class _Candidate {
  final _Verdict verdict;
  final List<int> tape;
  final Object? value;
  const _Candidate(this.verdict, this.tape, this.value);
}

/// Lexicographic simplicity order: shorter tapes first, then smaller entries.
/// A tape that is a strict prefix of another is always simpler.
bool _isSimpler(List<int> a, List<int> b) {
  if (a.length != b.length) return a.length < b.length;
  var sumA = 0, sumB = 0;
  for (var i = 0; i < a.length; i++) {
    sumA += a[i];
    sumB += b[i];
  }
  return sumA < sumB;
}

// ---------------------------------------------------------------------------
// The shrink search — pull-based, evaluator-agnostic
// ---------------------------------------------------------------------------

/// Proposes progressively simpler candidate tapes and is told whether each
/// was accepted. It never evaluates anything, which is what lets the
/// synchronous [forAll] and the `await`-ing [forAllAsync] drive the exact
/// same search.
///
/// Four passes, repeated until a full sweep makes no progress:
///  - **A. zero each entry.** Cheap, and the single most productive move
///    here: every generator in `gen.dart` draws a *length* before it draws
///    elements, so zeroing one early entry collapses the whole value — a
///    40-token hostile-unicode blob becomes `''` in one evaluation. It also
///    shortens the tape, because a shorter value consumes fewer draws.
///  - **B. halve each entry**, repeatedly. Finds threshold entries (the `n`
///    at which the invariant actually breaks) in log steps rather than
///    linear ones.
///  - **C. delete spans**, coarse to fine. Removes *middle* elements, which
///    a length draw alone can only trim from the end.
///  - **D. decrement each entry.** Catches the off-by-one that halving steps
///    over when the failing region is a single point.
///
/// Zeroing leads deliberately. Span deletion first would spend the whole
/// budget re-drawing regenerated tails on a tape whose length is governed by
/// an entry it has not touched yet.
class _TapeShrinker {
  _TapeShrinker(List<int> initial) : _best = List<int>.of(initial);

  static const int _passZero = 0;
  static const int _passHalve = 1;
  static const int _passDeleteSpans = 2;
  static const int _passDecrement = 3;

  List<int> _best;
  int _pass = _passZero;
  int _width = 0; // delete-spans pass only
  int _cursor = 0;
  bool _progressed = false;
  bool _finished = false;

  List<int> get best => _best;
  bool get finished => _finished;

  /// The next candidate to evaluate, or `null` when the search is done.
  ///
  /// Skips candidates that would be identical to the incumbent (a no-op
  /// mutation), advancing the cursor until it finds a real proposal.
  List<int>? propose() {
    while (!_finished) {
      switch (_pass) {
        case _passZero:
          if (_cursor >= _best.length) {
            _advancePass();
            continue;
          }
          if (_best[_cursor] == 0) {
            _cursor++;
            continue;
          }
          return List<int>.of(_best)..[_cursor] = 0;
        case _passHalve:
          if (_cursor >= _best.length) {
            _advancePass();
            continue;
          }
          if (_best[_cursor] == 0) {
            _cursor++;
            continue;
          }
          return List<int>.of(_best)..[_cursor] = _best[_cursor] ~/ 2;
        case _passDeleteSpans:
          if (_width < 1) {
            _advancePass();
            continue;
          }
          if (_cursor + _width > _best.length) {
            _width ~/= 2;
            _cursor = 0;
            continue;
          }
          return List<int>.of(_best)..removeRange(_cursor, _cursor + _width);
        default:
          if (_cursor >= _best.length) {
            _advancePass();
            continue;
          }
          if (_best[_cursor] == 0) {
            _cursor++;
            continue;
          }
          return List<int>.of(_best)..[_cursor] = _best[_cursor] - 1;
      }
    }
    return null;
  }

  /// The proposal was a strictly simpler counterexample; [resultingTape] is
  /// the canonical post-run tape (which may differ from the proposal — a
  /// deletion can make the generator draw past the end and append).
  ///
  /// The cursor deliberately does **not** advance: the same offset is worth
  /// retrying against the new, shorter incumbent. Termination is still
  /// guaranteed because every accepted candidate is strictly simpler and the
  /// order is well-founded.
  void accept(List<int> resultingTape) {
    _best = resultingTape;
    _progressed = true;
    if (_width > _best.length) _width = _best.length;
  }

  /// The proposal did not reproduce the same failure, or was not simpler.
  void reject() => _cursor++;

  void _advancePass() {
    _cursor = 0;
    if (_pass < _passDecrement) {
      _pass++;
      if (_pass == _passDeleteSpans) _width = _best.length;
      return;
    }
    // A full sweep finished. Another round only helps if something moved.
    if (!_progressed) {
      _finished = true;
      return;
    }
    _progressed = false;
    _pass = _passZero;
  }
}

/// Default budget for the shrink search. Generous enough to minimize a
/// 40-token hostile-unicode blob down to a single character, bounded enough
/// that a pathological generator cannot hang the suite.
///
/// Every shrink candidate re-runs **both** the generator and `check`. For a
/// pure property that costs microseconds. For a property whose `check` spawns
/// git subprocesses or builds a scratch repo, 3000 candidates is minutes of
/// wall time — such properties must lower `shrinkEvaluations` explicitly (a
/// few dozen still buys most of the minimization). `MANIFOLD_SHRINK=0`
/// disables shrinking entirely.
const int _kDefaultShrinkEvaluations = 3000;
const Duration _kDefaultShrinkTime = Duration(seconds: 8);

/// Budget bookkeeping shared by the sync and async drivers.
class _ShrinkBudget {
  _ShrinkBudget(this.maxEvaluations, this.maxTime) {
    _clock.start();
    _disabled =
        Platform.environment['MANIFOLD_SHRINK'] == '0' || maxEvaluations <= 0;
  }

  final int maxEvaluations;
  final Duration maxTime;
  final Stopwatch _clock = Stopwatch();
  late final bool _disabled;
  int evaluations = 0;

  bool get disabled => _disabled;
  bool get exhausted =>
      _disabled || evaluations >= maxEvaluations || _clock.elapsed > maxTime;
  int get elapsedMs => _clock.elapsedMilliseconds;
}

// ---------------------------------------------------------------------------
// forAll (synchronous)
// ---------------------------------------------------------------------------

/// Runs [check] against values drawn from [gen].
///
/// Execution order:
///  1. every tape in the on-disk corpus for this property (see [corpus]),
///     oldest first — so known past counterexamples are re-checked before
///     any time is spent on fresh random cases;
///  2. `count` freshly generated cases, each from its own deterministic
///     per-case [Rng] (see [_deriveCaseSeed]).
///
/// On the first failing case the recorded choice tape is minimized (see the
/// file header), the minimized tape is appended to the corpus, a
/// reproduction line is printed, and the *original* exception is rethrown
/// with its original stack trace — never a re-derived one from a shrunk
/// candidate, and never swallowed.
///
/// Only candidates that fail with **the same exception type** are kept, so
/// the shrinker cannot wander off into a different bug.
///
/// [requireCoverage] maps a [collect] label to the minimum fraction of cases
/// that must carry it. Checked only when every case passed — a property that
/// found a real counterexample has more urgent news.
void forAll<T>(
  Gen<T> gen, {
  required void Function(T value) check,
  int count = 200,
  int seed = 0x5EED,
  String? describe,
  T Function(T value)? shrink,
  Map<String, double>? requireCoverage,
  bool printStats = false,
  String? corpus,
  int shrinkEvaluations = _kDefaultShrinkEvaluations,
  Duration shrinkTimeout = _kDefaultShrinkTime,
  bool persistCorpus = true,
}) {
  final label = persistCorpus ? (corpus ?? describe) : null;
  final stats = _Stats();

  void runOne(List<int>? replayTape, int index) {
    final caseSeed = _deriveCaseSeed(seed, index);
    stats.begin();
    try {
      final tape = _Tape(replayTape ?? <int>[], caseSeed);
      final value = gen(Rng._on(tape));
      try {
        check(value);
      } catch (error, stackTrace) {
        final budget = _ShrinkBudget(shrinkEvaluations, shrinkTimeout);
        final targetType = error.runtimeType;

        _Candidate evaluate(List<int> candidate) {
          budget.evaluations++;
          final t = _Tape(List<int>.of(candidate), caseSeed);
          final T v;
          try {
            v = gen(Rng._on(t));
          } catch (_) {
            return const _Candidate(_Verdict.invalid, [], null);
          }
          // Only the draws the generator actually CONSUMED are part of this
          // value. A shrunk tape often makes the generator take a shorter
          // path (a smaller length draw means fewer element draws), leaving
          // unread entries behind. Carrying them forward would keep every
          // candidate looking exactly as long as its parent, `_isSimpler`
          // would reject it, and the search would never make progress.
          final consumed = t.choices.sublist(0, t.pos);
          try {
            check(v);
            return _Candidate(_Verdict.passed, consumed, v);
          } catch (e) {
            return _Candidate(
              e.runtimeType == targetType
                  ? _Verdict.failedSame
                  : _Verdict.failedDifferently,
              consumed,
              v,
            );
          }
        }

        var best = List<int>.of(tape.choices);
        Object? bestValue = value;
        if (!budget.disabled) {
          final shrinker = _TapeShrinker(best);
          while (!budget.exhausted) {
            final candidate = shrinker.propose();
            if (candidate == null) break;
            if (!_isSimpler(candidate, shrinker.best)) {
              shrinker.reject();
              continue;
            }
            final result = evaluate(candidate);
            if (result.verdict == _Verdict.failedSame &&
                _isSimpler(result.tape, shrinker.best)) {
              shrinker.accept(result.tape);
              bestValue = result.value;
            } else {
              shrinker.reject();
            }
          }
          best = shrinker.best;
        }

        var reported = bestValue is T ? bestValue : null;
        if (reported != null && shrink != null) {
          reported = _shrinkValueGreedily(reported, check, shrink, targetType);
        }

        _report(
          describe: describe,
          corpusLabel: label,
          seed: seed,
          index: index,
          reported: reported ?? bestValue,
          tape: best,
          originalDraws: tape.choices.length,
          budget: budget,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      stats.end();
    }
  }

  if (label != null) {
    final saved = _corpusRead(label);
    for (var i = 0; i < saved.length; i++) {
      runOne(saved[i], -(i + 1));
    }
  }
  for (var index = 0; index < count; index++) {
    runOne(null, index);
  }

  stats.finish(
    describe: describe,
    printStats: printStats,
    requireCoverage: requireCoverage,
  );
}

// ---------------------------------------------------------------------------
// forAllAsync
// ---------------------------------------------------------------------------

/// [forAll] for properties whose `check` is asynchronous — anything driving
/// real git subprocesses, filesystem I/O, or an isolate.
///
/// Identical semantics, identical shrinking, identical corpus. The only
/// difference is the default budget: every shrink candidate re-runs `check`,
/// and when `check` spawns processes that is seconds, not microseconds. So
/// [shrinkEvaluations] defaults to 40 rather than 3000 — enough to collapse
/// a counterexample by an order of magnitude, cheap enough that a failing
/// property still reports in seconds instead of minutes. Raise it when you
/// are chasing a specific failure.
///
/// [count] likewise defaults to 20, matching what a subprocess-driving
/// property can afford, rather than [forAll]'s 200.
Future<void> forAllAsync<T>(
  Gen<T> gen, {
  required Future<void> Function(T value) check,
  int count = 20,
  int seed = 0x5EED,
  String? describe,
  Map<String, double>? requireCoverage,
  bool printStats = false,
  String? corpus,
  int shrinkEvaluations = 40,
  Duration shrinkTimeout = const Duration(seconds: 60),
  bool persistCorpus = true,
}) async {
  final label = persistCorpus ? (corpus ?? describe) : null;
  final stats = _Stats();

  Future<void> runOne(List<int>? replayTape, int index) async {
    final caseSeed = _deriveCaseSeed(seed, index);
    stats.begin();
    try {
      final tape = _Tape(replayTape ?? <int>[], caseSeed);
      final value = gen(Rng._on(tape));
      try {
        await check(value);
      } catch (error, stackTrace) {
        final budget = _ShrinkBudget(shrinkEvaluations, shrinkTimeout);
        final targetType = error.runtimeType;

        Future<_Candidate> evaluate(List<int> candidate) async {
          budget.evaluations++;
          final t = _Tape(List<int>.of(candidate), caseSeed);
          final T v;
          try {
            v = gen(Rng._on(t));
          } catch (_) {
            return const _Candidate(_Verdict.invalid, [], null);
          }
          // See the sync driver: only consumed draws belong to this value.
          final consumed = t.choices.sublist(0, t.pos);
          try {
            await check(v);
            return _Candidate(_Verdict.passed, consumed, v);
          } catch (e) {
            return _Candidate(
              e.runtimeType == targetType
                  ? _Verdict.failedSame
                  : _Verdict.failedDifferently,
              consumed,
              v,
            );
          }
        }

        var best = List<int>.of(tape.choices);
        Object? bestValue = value;
        if (!budget.disabled) {
          final shrinker = _TapeShrinker(best);
          while (!budget.exhausted) {
            final candidate = shrinker.propose();
            if (candidate == null) break;
            if (!_isSimpler(candidate, shrinker.best)) {
              shrinker.reject();
              continue;
            }
            final result = await evaluate(candidate);
            if (result.verdict == _Verdict.failedSame &&
                _isSimpler(result.tape, shrinker.best)) {
              shrinker.accept(result.tape);
              bestValue = result.value;
            } else {
              shrinker.reject();
            }
          }
          best = shrinker.best;
        }

        _report(
          describe: describe,
          corpusLabel: label,
          seed: seed,
          index: index,
          reported: bestValue,
          tape: best,
          originalDraws: tape.choices.length,
          budget: budget,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      stats.end();
    }
  }

  if (label != null) {
    final saved = _corpusRead(label);
    for (var i = 0; i < saved.length; i++) {
      await runOne(saved[i], -(i + 1));
    }
  }
  for (var index = 0; index < count; index++) {
    await runOne(null, index);
  }

  stats.finish(
    describe: describe,
    printStats: printStats,
    requireCoverage: requireCoverage,
  );
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

void _report({
  required String? describe,
  required String? corpusLabel,
  required int seed,
  required int index,
  required Object? reported,
  required List<int> tape,
  required int originalDraws,
  required _ShrinkBudget budget,
}) {
  if (corpusLabel != null) _corpusAppend(corpusLabel, tape);

  final prefix = describe == null ? '' : '$describe — ';
  final seedHex = '0x${seed.toRadixString(16)}';
  final shrinkLine = budget.disabled
      ? '[prop] shrink: disabled (MANIFOLD_SHRINK=0)\n'
      : '[prop] shrink: $originalDraws draws -> ${tape.length} draws '
          '(${budget.evaluations} evaluations, ${budget.elapsedMs}ms)\n';
  final corpusLine = corpusLabel == null
      ? ''
      : '\n[prop] saved to test/corpus/${_slug(corpusLabel)}.tape — '
          'this case now replays on every future run';

  // ignore: avoid_print
  print(
    '[prop] ${prefix}FAILED at seed=$seedHex index=$index\n'
    '[prop] value=$reported\n'
    '$shrinkLine'
    '[prop] tape=${tape.join(',')}\n'
    '[prop] reproduce: rerun with seed=$seedHex (same seed -> same failure '
    'at index $index, deterministically)$corpusLine',
  );
}

/// Legacy greedy value-level shrink, preserved for the `shrink:` parameter.
/// Only keeps candidates that fail with the same exception type.
T _shrinkValueGreedily<T>(
  T initial,
  void Function(T value) check,
  T Function(T value) shrink,
  Type targetType,
) {
  var current = initial;
  for (var step = 0; step < 200; step++) {
    final candidate = shrink(current);
    if (candidate == current) break;
    try {
      check(candidate);
      break; // candidate no longer fails -> current was already minimal
    } catch (error) {
      if (error.runtimeType != targetType) break;
      current = candidate;
    }
  }
  return current;
}

// ---------------------------------------------------------------------------
// Statistics bookkeeping
// ---------------------------------------------------------------------------

class _Stats {
  final Map<String, int> counts = {};
  int cases = 0;

  void begin() {
    cases++;
    _currentCaseLabels = <String>{};
  }

  void end() {
    final labels = _currentCaseLabels;
    _currentCaseLabels = null;
    if (labels == null) return;
    for (final l in labels) {
      counts[l] = (counts[l] ?? 0) + 1;
    }
  }

  void finish({
    required String? describe,
    required bool printStats,
    required Map<String, double>? requireCoverage,
  }) {
    if ((printStats || Platform.environment['MANIFOLD_PROP_STATS'] == '1') &&
        counts.isNotEmpty) {
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print('[prop] ${describe ?? 'property'} — $cases cases:');
      for (final e in sorted) {
        final pct = (e.value / cases * 100).toStringAsFixed(1);
        // ignore: avoid_print
        print('[prop]   ${e.key.padRight(28)} '
            '${e.value.toString().padLeft(5)}  $pct%');
      }
    }

    if (requireCoverage == null) return;
    for (final entry in requireCoverage.entries) {
      final observed = cases == 0 ? 0.0 : (counts[entry.key] ?? 0) / cases;
      if (observed < entry.value) {
        throw PropCoverageError(
          describe: describe ?? 'property',
          label: entry.key,
          observed: observed,
          required: entry.value,
          cases: cases,
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Corpus persistence
// ---------------------------------------------------------------------------

/// Where corpus files live, relative to the package root (`flutter test`
/// always runs with the package root as cwd). `null` when that directory
/// cannot be located — the harness then degrades to pure random testing
/// rather than guessing at a path or throwing.
Directory? _corpusDir() {
  if (Platform.environment['MANIFOLD_CORPUS'] == '0') return null;
  if (!Directory('test').existsSync()) return null;
  return Directory('test/corpus');
}

String _slug(String label) {
  final buffer = StringBuffer();
  for (final unit in label.toLowerCase().codeUnits) {
    final isAlnum =
        (unit >= 0x61 && unit <= 0x7A) || (unit >= 0x30 && unit <= 0x39);
    buffer.writeCharCode(isAlnum ? unit : 0x5F); // '_'
  }
  // Collapse runs of '_' so `a — b` and `a - b` don't produce different files.
  final collapsed = buffer.toString().replaceAll(RegExp('_+'), '_');
  final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
  return trimmed.isEmpty ? 'unnamed' : trimmed;
}

/// Max tapes retained per property. A property that fails a thousand
/// different ways does not need a thousand replays on every future run; the
/// oldest (first-found, usually most-minimized) are the ones worth keeping.
const int _kMaxCorpusEntries = 64;

List<List<int>> _corpusRead(String label) {
  final dir = _corpusDir();
  if (dir == null) return const [];
  final file = File('${dir.path}/${_slug(label)}.tape');
  if (!file.existsSync()) return const [];
  final tapes = <List<int>>[];
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final tape = <int>[];
    var ok = true;
    for (final part in trimmed.split(',')) {
      final value = int.tryParse(part.trim());
      if (value == null || value < 0) {
        ok = false;
        break;
      }
      tape.add(value);
    }
    // A malformed line is skipped, never fatal: a corpus file is a cache of
    // past bugs, not a source of new ones.
    if (ok) tapes.add(tape);
  }
  return tapes;
}

void _corpusAppend(String label, List<int> tape) {
  final dir = _corpusDir();
  if (dir == null) return;
  try {
    dir.createSync(recursive: true);
    final file = File('${dir.path}/${_slug(label)}.tape');
    final encoded = tape.join(',');
    // Read the existing corpus once and reuse it for both the dedup scan and
    // the cap check (was two separate _corpusRead calls).
    final existing = _corpusRead(label);
    for (final saved in existing) {
      if (saved.join(',') == encoded) return; // already known
    }
    if (existing.length >= _kMaxCorpusEntries) return;
    if (!file.existsSync()) {
      file.writeAsStringSync(
        '# Minimized failing choice-tapes for: $label\n'
        '# Replayed before every random case. One tape per line, comma-separated.\n'
        '# Written automatically by forAll(); safe to delete, safe to commit.\n',
      );
    }
    file.writeAsStringSync('$encoded\n', mode: FileMode.append);
  } on FileSystemException {
    // A read-only checkout must not turn a real property failure into a
    // confusing I/O error. Losing the corpus entry is the lesser harm.
  }
}

// ---------------------------------------------------------------------------
// Knobs
// ---------------------------------------------------------------------------

/// Reads `MANIFOLD_FUZZ` from the environment as a multiplier for how many
/// cases a "deep" run should generate (e.g. `count: 200 * fuzzScale()`).
/// Missing/unparseable/`<1` values all fall back to `1` (the normal, fast
/// run) — this knob is purely additive for local deep fuzzing sessions,
/// never required for a suite to pass.
int fuzzScale() {
  final raw = Platform.environment['MANIFOLD_FUZZ'];
  if (raw == null) return 1;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < 1) return 1;
  return parsed;
}
