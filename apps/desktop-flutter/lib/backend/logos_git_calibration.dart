// logos_git_calibration.dart — SSE calibration for the Logos attention codec
//
// Logos's Secondary Symbol Estimation (SSE) is a 3-dimensional grid:
//
//   (matchState, o2-disagreement, pRaw-bucket) → (hits, misses)
//
// It's how the codec learns, per-regime, when to trust the blended
// prediction vs the individual axes. For code context the analog is:
//
//   (regime, probe-axis) → (cited, emitted)
//
// Every review emission records: "file F was put in the prompt under
// regime R, primarily via axis A." Every AI response records: "paths
// P1, P2, P3 were cited in <findings>." Matching the two closes the
// loop — cited/emitted per (regime, axis) is the utility of that axis
// in that regime. Over time, `mWeight` and `abWeight` in the probe
// builder can be adjusted per-repo from these utilities.
//
// This module is storage + update + query. Integration is wired in
// two places:
//   - ai.dart `_collectRelevanceNeighborhood` stamps emissions before
//     returning the prompt block
//   - ai.dart `reviewCommit` calls `recordCitations` after parsing the
//     LLM's `<findings>` response
//
// Storage lives at:
//   <repo>/.git/logos-git/sse.json
// Per-repo, gitignored by living inside .git. Small (~4KB) so we can
// re-read on every review and write on every feedback.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'package:path/path.dart' as p;

/// A regime label — the "macrostate" of a commit. Derived from probe
/// shape: file count × coherence × symbol density. Four canonical
/// regimes cover every diff an engineer produces.
enum LogosRegime {
  /// Small, cohesive diff — one file or a tight cluster editing the
  /// same concept. Primary + M-axis dominate.
  focused,

  /// Medium diff, moderate coherence — feature work or a fix touching
  /// a few related files. CC + Ab (tests) matter.
  scoped,

  /// Large diff, low coherence — a sweep, a rename, a big refactor
  /// reaching across modules. F0 (hubs) + SP (path structure) matter.
  sweep,

  /// Anything else — unclassified. Default priors.
  uncategorised;

  static LogosRegime classify({
    required int fileCount,
    required double coherence,
  }) {
    if (fileCount <= 3 && coherence >= 0.6) return LogosRegime.focused;
    if (fileCount <= 12 && coherence >= 0.35) return LogosRegime.scoped;
    if (fileCount > 12 || coherence < 0.35) return LogosRegime.sweep;
    return LogosRegime.uncategorised;
  }
}

/// Which observable got a file emitted. Primary = the diff itself;
/// M = pickaxe pulled it in; Ab = path-mirror pulled it in; Graph =
/// none of the above (the diffusion ranked it high from graph edges
/// alone — CC / SP / V / F0 collectively). Symbol = the file had no
/// git history but was structurally coupled via identifier overlap
/// (IDF-Jaccard) — the leading-signal counterpart to CC's lagging one.
enum LogosAxis { primary, m, ab, graph, symbol }

/// The fundamental SSE cell: an (emitted, cited) counter per
/// (regime, axis), with two decay mechanisms:
///   1. **Count saturation halving** at n=256 — matches Logos's discrete
///      `evaporate()` — keeps the cell responsive when counts accumulate
///      faster than opinions shift.
///   2. **Continuous-time decay** on wall-clock age — matches Logos's
///      evaporate() at the continuous-time limit. A cell last updated
///      weeks ago contributes with an exponentially reduced weight vs
///      one updated yesterday. Half-life 30d by default.
/// The two decays work together: count-halving prevents saturation,
/// time-decay prevents stale calibrations from anchoring forever.
/// Counts are stored as doubles (not ints) because continuous decay
/// produces fractional values; JSON serialization rounds for legibility
/// but the in-memory precision is f64.
class LogosSseCell {
  double emitted;
  double cited;
  /// Epoch millis of the last increment. Used by [_decayInPlace] to
  /// age out stale observations. When absent in deserialized cells we
  /// default to half-a-half-life ago so old cells decay partially
  /// rather than disappearing entirely — soft migration.
  int lastUpdateMs;

  /// Snapshot of [utility] at the previous citation-write boundary,
  /// or null when no snapshot has been taken yet (cell never updated
  /// or cell is fresh). Drives [utilityVelocityPerDay] — the rate at
  /// which the (regime, axis) cell's per-citation utility is changing
  /// over wall-clock time. Self-tuning calibration: when the velocity
  /// is positive the axis is becoming MORE predictive in this regime,
  /// so the probe builder can project forward and weight the axis
  /// up *before* the next round of evidence accumulates.
  double? prevUtility;

  /// Epoch millis when [prevUtility] was captured. Combined with the
  /// current read time to compute Δt for the velocity. When
  /// [prevUtility] is null this field is unused.
  int? prevUtilityMs;

  /// Welford running-variance state. Each [_snapshotUtility] call
  /// updates these so [utilityVariance] tracks the spread of the
  /// cell's per-citation-round utility ratio over time. Drives the
  /// variance-modulated decay in [_decayInPlace]: when the cell's
  /// utility is bouncing (high variance) the effective half-life
  /// shortens so unstable signals melt faster; when utility is
  /// converged (low variance) the half-life stays full so the
  /// crystallised value is preserved. Whisper's "thermodynamic
  /// evaporation" applied to citation feedback.
  int utilitySampleCount;
  double utilitySampleMean;
  double utilitySampleSumSq;

  LogosSseCell({
    this.emitted = 0,
    this.cited = 0,
    int? lastUpdateMs,
    this.prevUtility,
    this.prevUtilityMs,
    this.utilitySampleCount = 0,
    this.utilitySampleMean = 0.0,
    this.utilitySampleSumSq = 0.0,
  }) : lastUpdateMs = lastUpdateMs ?? DateTime.now().millisecondsSinceEpoch;

  /// Wall-clock half-life for cell counts. 30 days matches the SSE
  /// calibration's natural cadence: reviews bursty over days, stable
  /// over weeks. Not per-cell — global so all cells age together.
  static const Duration defaultHalfLife = Duration(days: 30);
  static Duration halfLife = defaultHalfLife;

  /// Decay cell counts in-place based on wall-clock age from the last
  /// update. Pure; called lazily on read (`utility`) and on increment
  /// so both paths see correctly-aged values. Invariant: after decay,
  /// `cited ≤ emitted` remains true (both shrink by the same factor).
  /// **Variance-modulated half-life.** The base [halfLife] is the
  /// "neutral" decay; we accelerate it when [utilityVariance] is high.
  /// Whisper's thermodynamic-evaporation idea applied here: a cell
  /// whose per-round utility is bouncing in this regime carries less
  /// signal per sample, so its history should decay faster. A cell
  /// whose utility is converged is informative — let it freeze.
  ///   accelerationFactor = 1 + (variance / kBernoulliMaxVariance)
  ///   effectiveHalfLife  = halfLife / accelerationFactor
  /// `kBernoulliMaxVariance = 0.25` (the maximum possible variance of
  /// a [0,1]-bounded ratio at p=0.5) — a physical bound, not a
  /// tuning knob. So acceleration is in [1.0, 2.0]: at zero variance
  /// the half-life is unchanged; at maximum variance it halves.
  void _decayInPlace([DateTime? now]) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final deltaMs = nowMs - lastUpdateMs;
    if (deltaMs <= 0) return;
    final hl = halfLife.inMilliseconds;
    if (hl <= 0) return;
    final accelFactor = 1.0 + (utilityVariance / _bernoulliMaxVariance);
    final effectiveHl = hl / accelFactor;
    // exp(-Δt · ln(2) / T_½) = 2^(-Δt / T_½)
    final factor = math.pow(0.5, deltaMs / effectiveHl).toDouble();
    if (factor >= 0.9999) return; // nothing worth doing
    emitted *= factor;
    cited *= factor;
    // Floor at 0 and clean up near-zero residuals so the store doesn't
    // accumulate meaningless dust entries forever.
    if (emitted < 0.01) emitted = 0;
    if (cited < 0.01) cited = 0;
    lastUpdateMs = nowMs;
  }

  /// Maximum variance of a Bernoulli-distributed [0,1] ratio (achieved
  /// at p=0.5). Used as the natural denominator for the variance-
  /// modulated decay acceleration — physical bound, no tuning.
  static const double _bernoulliMaxVariance = 0.25;

  /// Minimum evidence before a cell reports a non-prior utility. Below
  /// this the Beta-distribution confidence interval around `cited /
  /// emitted` is wider than the interval around the prior itself, so
  /// returning the prior (0.5) is strictly more informative than the
  /// noisy empirical ratio. Two bits' worth of evidence (2² = 4).
  static const int _minEvidenceForUtility = 1 << 2;

  /// Soft saturation trigger — the "halve" threshold. Chosen as 2⁸ so
  /// the cell acts as a single-byte counter's worth of memory before
  /// discounting old signal.
  static const int _saturationSoft = 1 << 8;

  /// Deep saturation trigger — the √-rescue threshold. 4× the soft cap
  /// (2¹⁰). Beyond this a single halving would leave the cell still
  /// saturated; the √-rescue scales it back to the soft cap in one step
  /// regardless of how deep it went, preserving the utility ratio.
  static const int _saturationDeep = 1 << 10;

  /// Neutral Krichevsky–Trofimov (KT) prior: 0.5 is the "I have no
  /// information, both outcomes are equally likely" starting point.
  static const double _utilityPrior = 0.5;

  /// Utility in [0, 1]: of the files emitted under this (regime, axis),
  /// what fraction did the AI actually cite in findings? Returns the KT
  /// prior when evidence is below [_minEvidenceForUtility]. Decay
  /// applied before read so stale cells contribute less.
  double get utility {
    _decayInPlace();
    if (emitted < _minEvidenceForUtility) return _utilityPrior;
    return cited / emitted;
  }

  /// Per-day rate of change in [utility] since the last
  /// [_snapshotUtility] capture. Returns 0 when:
  ///   • no snapshot has been taken yet ([prevUtility] null)
  ///   • current evidence below [_minEvidenceForUtility] (utility
  ///     would just be the KT prior — no real signal to differentiate)
  ///   • Δt ≤ 0 or non-finite (clock-skew safety)
  /// Positive = axis becoming more predictive in this regime.
  /// Negative = axis becoming less predictive (its citations not
  /// keeping up with its emissions). Drives the probe builder's
  /// projection lookahead so weight scales adapt one half-life early
  /// instead of waiting for evidence to fully catch up.
  double get utilityVelocityPerDay {
    final prev = prevUtility;
    final prevMs = prevUtilityMs;
    if (prev == null || prevMs == null) return 0.0;
    if (emitted < _minEvidenceForUtility) return 0.0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final deltaMs = nowMs - prevMs;
    if (deltaMs <= 0) return 0.0;
    final deltaDays = deltaMs / Duration.millisecondsPerDay;
    if (deltaDays <= 0 || !deltaDays.isFinite) return 0.0;
    final delta = utility - prev;
    if (!delta.isFinite) return 0.0;
    return delta / deltaDays;
  }

  /// Variance of the cell's utility ratio over time, computed via
  /// Welford's online algorithm against [_snapshotUtility] samples.
  /// Bounded above by [_bernoulliMaxVariance] = 0.25. Returns 0 until
  /// at least two samples have been taken (no spread to measure).
  /// Drives the variance-modulated decay in [_decayInPlace] — high
  /// variance ⇒ axis is bouncing in this regime ⇒ shorter effective
  /// half-life ⇒ faster forget. Whisper's evaporation primitive on
  /// the citation-feedback signal.
  double get utilityVariance {
    if (utilitySampleCount < 2) return 0.0;
    return utilitySampleSumSq / (utilitySampleCount - 1);
  }

  /// Test-only access to [_snapshotUtility]. Production callers go
  /// through [LogosSseStore.recordCitations] which calls the private
  /// version; tests need to drive the snapshot loop directly.
  @visibleForTesting
  void snapshotUtilityForTesting() => _snapshotUtility();

  /// Capture the current utility into [prevUtility] / [prevUtilityMs]
  /// so subsequent reads can compute velocity vs this point. Also
  /// updates the Welford running-variance state. Called after each
  /// citation-write by [LogosSseStore.recordCitations] so the
  /// velocity AND variance reflect per-feedback-round learning, not
  /// per-read.
  void _snapshotUtility() {
    final newSample = utility;
    // Welford's online variance update.
    utilitySampleCount += 1;
    final delta = newSample - utilitySampleMean;
    utilitySampleMean += delta / utilitySampleCount;
    final delta2 = newSample - utilitySampleMean;
    utilitySampleSumSq += delta * delta2;

    prevUtility = newSample;
    prevUtilityMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Saturation cap (Logos `evaporate()`-style). At the soft trigger
  /// ([_saturationSoft]) we halve both counts — this preserves the
  /// `cited / emitted` ratio exactly and matches the discrete behaviour
  /// the calibration loop was tuned against. Past the deep trigger
  /// ([_saturationDeep]) a single halve isn't enough, so we √-pull
  /// toward the soft cap so one call fully recovers regardless of how
  /// deep we landed (possible on cold-start with persisted-ancient
  /// data, time-skip on a resumed checkout, etc.). Both branches
  /// preserve the utility ratio.
  void evaporateIfSaturated() {
    if (emitted >= _saturationDeep) {
      final scale = math.sqrt(_saturationSoft / emitted);
      emitted *= scale;
      cited *= scale;
    } else if (emitted >= _saturationSoft) {
      emitted /= 2;
      cited /= 2;
    }
  }

  Map<String, dynamic> toJson() => {
        // Round for JSON legibility — f64 round-trips to ±1 tolerance
        // which is fine for a 256-cap counter.
        'e': double.parse(emitted.toStringAsFixed(3)),
        'c': double.parse(cited.toStringAsFixed(3)),
        't': lastUpdateMs,
        // Velocity-tracking snapshot. Omitted when no snapshot has
        // been taken yet — keeps the JSON small for fresh cells.
        if (prevUtility != null) 'pu': double.parse(prevUtility!.toStringAsFixed(3)),
        if (prevUtilityMs != null) 'pt': prevUtilityMs!,
        // Welford running-variance state — only serialised after the
        // first snapshot so legacy cells stay compact. The four-tuple
        // is kept as Welford requires (count + mean + sum-sq) to
        // continue updating after a load.
        if (utilitySampleCount > 0) ...{
          'vn': utilitySampleCount,
          'vm': double.parse(utilitySampleMean.toStringAsFixed(4)),
          'vs': double.parse(utilitySampleSumSq.toStringAsFixed(6)),
        },
      };

  factory LogosSseCell.fromJson(Map<String, dynamic> j) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final persistedTs = (j['t'] as num?)?.toInt();
    // Soft migration: legacy cells without 't' get a timestamp half-a-
    // half-life in the past so they decay partially — not erased, not
    // treated as fresh.
    final ts = persistedTs ??
        nowMs - (LogosSseCell.halfLife.inMilliseconds ~/ 2);
    return LogosSseCell(
      emitted: (j['e'] as num?)?.toDouble() ?? 0,
      cited: (j['c'] as num?)?.toDouble() ?? 0,
      lastUpdateMs: ts,
      prevUtility: (j['pu'] as num?)?.toDouble(),
      prevUtilityMs: (j['pt'] as num?)?.toInt(),
      utilitySampleCount: (j['vn'] as num?)?.toInt() ?? 0,
      utilitySampleMean: (j['vm'] as num?)?.toDouble() ?? 0.0,
      utilitySampleSumSq: (j['vs'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// A completed probe-emission ready for SSE feedback. Caller keeps one
/// in memory for the duration of a review; after the AI responds,
/// passes it to `recordCitations` along with the parsed cited paths.
class LogosEmissionRecord {
  final LogosRegime regime;
  final Map<String, LogosAxis> axisByPath;

  const LogosEmissionRecord({
    required this.regime,
    required this.axisByPath,
  });

  bool get isEmpty => axisByPath.isEmpty;
}

/// The per-repo calibration store. Read-through + write-through JSON.
/// Cheap: a 3-second cache keeps repeated reads near-free without a
/// long-lived lock.
/// Concurrent-write safety: each `recordEmissions` / `recordCitations`
/// runs inside [_withRepoWriteLock], which serialises read-modify-write
/// cycles per `repoPath` *across all [LogosSseStore] instances* (the
/// lock map is static). Without this, two parallel reviews on the same
/// repo would each load → mutate locally → save, with the later writer
/// silently overwriting the earlier one's increments. The lock also
/// invalidates the per-instance cache before each locked read so a
/// store whose cache predates a sibling instance's write doesn't act
/// on stale data.
class LogosSseStore {
  final String repoPath;
  Map<LogosRegime, Map<LogosAxis, LogosSseCell>>? _cache;
  DateTime? _cacheAt;
  static const _cacheTtl = Duration(seconds: 3);

  /// Per-repoPath write-chain. Each new locked operation awaits the
  /// previous one's completion before running, then chains its own
  /// completer for the next caller. Static so it spans all
  /// [LogosSseStore] instances that target the same repo.
  static final Map<String, Future<void>> _writeChains = {};

  /// Timestamp of the most recent successful write per normalised repo key.
  /// Read by [_load] to invalidate per-instance caches in sibling stores —
  /// the lock serialises writers but each instance manages its own cache,
  /// so without this a sibling can return pre-write data for up to [_cacheTtl].
  static final Map<String, DateTime> _lastWriteAt = {};

  /// Normalise a repo path to a canonical lock key.  Converts backslashes
  /// to forward slashes and strips trailing slashes.  Lowercasing is
  /// applied only on Windows where the filesystem is case-insensitive —
  /// on macOS and Linux `/Repo` and `/repo` are distinct directories and
  /// must not share a lock entry.  [repoPath] itself is left unchanged
  /// — it is used for actual file I/O and must remain in its original form.
  static String _lockKey(String path) {
    var key = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    if (Platform.isWindows) key = key.toLowerCase();
    return key;
  }

  LogosSseStore(this.repoPath);

  /// Run [body] under the per-repo write lock. Forces a fresh disk
  /// read inside the critical section by invalidating the cache, so
  /// the body sees any sibling writes that landed before it acquired
  /// the lock.
  Future<T> _withRepoWriteLock<T>(Future<T> Function() body) async {
    final key = _lockKey(repoPath);
    final pending = _writeChains[key];
    final completer = Completer<void>();
    _writeChains[key] = completer.future;
    try {
      if (pending != null) {
        await pending;
      }
      // Drop our own cache so [_load] re-reads disk inside the lock.
      // Sibling writers may have updated the file while we were
      // waiting on `pending`.
      _cache = null;
      _cacheAt = null;
      final result = await body();
      // Stamp the write time BEFORE completing the completer so any
      // waiting sibling instances see it immediately on wake-up.
      _lastWriteAt[key] = DateTime.now();
      return result;
    } finally {
      completer.complete();
      // Only remove the chain entry if no later caller has chained
      // onto our completer. Otherwise leave it for the next waiter.
      if (identical(_writeChains[key], completer.future)) {
        _writeChains.remove(key);
      }
    }
  }

  Future<LogosSseCell> cellFor(LogosRegime regime, LogosAxis axis) async {
    final data = await _load();
    return data[regime]?[axis] ?? LogosSseCell();
  }

  /// Record that [record.axisByPath.length] files were emitted under
  /// [record.regime]. Nothing is marked cited yet — that comes later
  /// via [recordCitations].
  Future<void> recordEmissions(LogosEmissionRecord record) async {
    if (record.isEmpty) return;
    await _withRepoWriteLock(() async {
      final data = await _load();
      final tally = <LogosAxis, int>{};
      for (final a in record.axisByPath.values) {
        tally.update(a, (v) => v + 1, ifAbsent: () => 1);
      }
      for (final entry in tally.entries) {
        final cell = data
            .putIfAbsent(record.regime, () => {})
            .putIfAbsent(entry.key, () => LogosSseCell());
        // Age the cell before incrementing so recent activity is
        // weighted fairly against stale history.
        cell._decayInPlace();
        cell.emitted += entry.value;
        cell.evaporateIfSaturated();
      }
      await _save(data);
    });
  }

  /// Record which emitted paths the AI actually cited. Paths not in
  /// [record] are ignored (they weren't emitted through this system).
  Future<void> recordCitations({
    required LogosEmissionRecord record,
    required Set<String> citedPaths,
  }) async {
    if (record.isEmpty) return;
    await _withRepoWriteLock(() async {
      final data = await _load();
      final tally = <LogosAxis, int>{};
      for (final entry in record.axisByPath.entries) {
        if (!citedPaths.contains(entry.key)) continue;
        tally.update(entry.value, (v) => v + 1, ifAbsent: () => 1);
      }
      if (tally.isEmpty) {
        // No citations hit our emissions — nothing to record. Skip
        // the write entirely (no `_cacheAt` refresh, no disk touch);
        // the emission counters were already incremented at
        // recordEmission time, so the SSE state for this record is
        // already coherent.
        return;
      }
      for (final entry in tally.entries) {
        final cell = data
            .putIfAbsent(record.regime, () => {})
            .putIfAbsent(entry.key, () => LogosSseCell());
        cell._decayInPlace();
        cell.cited += entry.value;
        // Snapshot the post-update utility so the NEXT recordCitations
        // round can compute velocity = (newer_utility − this_utility) /
        // Δt. This is what closes the self-tuning feedback loop:
        // probe weights project forward by velocity × half-life so an
        // axis that's becoming more predictive gets weighted up
        // *before* it fully accumulates evidence.
        cell._snapshotUtility();
      }
      await _save(data);
    });
  }

  /// Returns utility ratios suitable for scaling probe-axis weights.
  /// `1.0` is the neutral prior; above means the axis is pulling its
  /// weight in this regime; below means it's overfiring.
  /// This is the "spot value" — current utility only. For
  /// trend-aware weighting that anticipates an axis becoming more
  /// (or less) predictive, use [projectedUtilitiesFor].
  Future<Map<LogosAxis, double>> utilitiesFor(LogosRegime regime) async {
    final data = await _load();
    final row = data[regime];
    if (row == null) return const {};
    return {
      for (final entry in row.entries) entry.key: entry.value.utility * 2,
      // ×2 because `utility` is in [0, 1] centred at 0.5; we want a
      // multiplier centred at 1.0.
    };
  }

  /// Returns trend-aware multipliers: `(utility + velocity ×
  /// lookaheadDays) × 2`. Drives the probe builder's self-tuning so
  /// axes whose utility is climbing in this regime get weighted up
  /// *before* their evidence fully accumulates, and axes whose utility
  /// is falling get downweighted before they do real damage.
  /// [lookaheadDays] is the projection horizon in days. The natural
  /// choice is the SSE store's own half-life: project as far as the
  /// store keeps memory; beyond that, decay erases the trend anyway.
  /// Defaults to `LogosSseCell.halfLife.inDays` for that reason.
  /// Cells without a velocity snapshot (fresh cells, low evidence)
  /// degrade gracefully to the spot utility — same as
  /// [utilitiesFor] would return. No NaN, no surprise.
  Future<Map<LogosAxis, double>> projectedUtilitiesFor(
    LogosRegime regime, {
    double? lookaheadDays,
  }) async {
    final data = await _load();
    final row = data[regime];
    if (row == null) return const {};
    final lookahead =
        lookaheadDays ?? LogosSseCell.halfLife.inDays.toDouble();
    return {
      for (final entry in row.entries)
        entry.key:
            (entry.value.utility + entry.value.utilityVelocityPerDay * lookahead)
                .clamp(0.0, 1.0) *
                2,
      // Clamp inside [0, 1] before the ×2 centering so the result
      // can't exceed [0, 2]. The probe still applies its own
      // _sseUtilityScaleMin/Max bound on top.
    };
  }


  Future<Map<LogosRegime, Map<LogosAxis, LogosSseCell>>> _load() async {
    // Invalidate own cache if a sibling store wrote more recently.
    // The static lock serialises writers but each instance holds its own
    // cache; without this check a sibling's write would be invisible here
    // until the 3s TTL expires.
    final key = _lockKey(repoPath);
    final lastWrite = _lastWriteAt[key];
    if (lastWrite != null) {
      if (DateTime.now().difference(lastWrite) > _cacheTtl) {
        // Entry is older than the TTL — no live cache can predate this
        // write any more.  Prune it to prevent unbounded map growth over
        // a long process lifetime.
        _lastWriteAt.remove(key);
      } else if (_cacheAt == null || lastWrite.isAfter(_cacheAt!)) {
        _cache = null;
        _cacheAt = null;
      }
    }
    if (_cache != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < _cacheTtl) {
      return _cache!;
    }
    final file = File(_sseFilePath());
    if (!await file.exists()) {
      _cache = {};
      _cacheAt = DateTime.now();
      return _cache!;
    }
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map) {
        _cache = {};
      } else {
        final out = <LogosRegime, Map<LogosAxis, LogosSseCell>>{};
        for (final regimeEntry in json.entries) {
          final regime = _regimeByName(regimeEntry.key as String);
          if (regime == null) continue;
          final inner = regimeEntry.value;
          if (inner is! Map) continue;
          final row = <LogosAxis, LogosSseCell>{};
          for (final axisEntry in inner.entries) {
            final axis = _axisByName(axisEntry.key as String);
            if (axis == null) continue;
            final cell = axisEntry.value;
            if (cell is Map<String, dynamic>) {
              row[axis] = LogosSseCell.fromJson(cell);
            } else if (cell is Map) {
              row[axis] = LogosSseCell.fromJson(
                cell.map((k, v) => MapEntry(k.toString(), v)),
              );
            }
          }
          out[regime] = row;
        }
        _cache = out;
      }
    } catch (_) {
      _cache = {};
    }
    _cacheAt = DateTime.now();
    return _cache!;
  }

  Future<void> _save(
    Map<LogosRegime, Map<LogosAxis, LogosSseCell>> data,
  ) async {
    _cache = data;
    _cacheAt = DateTime.now();
    try {
      final dir = Directory(p.dirname(_sseFilePath()));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final json = <String, Map<String, Map<String, dynamic>>>{
        for (final regime in data.entries)
          regime.key.name: {
            for (final axis in regime.value.entries)
              axis.key.name: axis.value.toJson(),
          },
      };
      final payload = const JsonEncoder.withIndent('  ').convert(json);

      // Atomic write: temp-file + rename. Guards against corruption if
      // the process crashes mid-flush — readers see either the old
      // file or the new file, never a truncated one. The temp name
      // is PID-namespaced so concurrent writers (shouldn't happen, but
      // SSE is background work) don't stomp each other's temp files.
      final finalPath = _sseFilePath();
      final tempPath = '$finalPath.tmp.${pid}.'
          '${DateTime.now().microsecondsSinceEpoch}';
      final tempFile = File(tempPath);
      try {
        await tempFile.writeAsString(payload, flush: true);
        // On all host OSes Dart's `rename` is atomic when src and dst
        // are on the same filesystem (guaranteed here — same dir).
        await tempFile.rename(finalPath);
      } catch (_) {
        // Failed mid-write: clean up the temp if it exists.
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
        rethrow;
      }
    } catch (_) {
      // Best-effort write — don't fail the review if disk is read-only.
    }
  }

  String _sseFilePath() => p.join(repoPath, '.git', 'logos-git', 'sse.json');

  static LogosRegime? _regimeByName(String n) {
    for (final r in LogosRegime.values) {
      if (r.name == n) return r;
    }
    return null;
  }

  static LogosAxis? _axisByName(String n) {
    for (final a in LogosAxis.values) {
      if (a.name == n) return a;
    }
    return null;
  }
}

/// Extract file paths that the AI cited in its `<findings>` XML
/// response. We look for `path="..."` attributes, `file=...`, and
/// bare relative paths inside finding bodies. The LLM's output is
/// loosely structured so we cast a wide net and rely on the
/// recordCitations step to filter against the known emission set.
Set<String> extractCitedPathsFromReviewOutput(String llmOutput) {
  final paths = <String>{};
  // path="..." or file="..."
  final attrRe = RegExp(r'''(?:path|file)\s*=\s*"([^"]+)"''');
  for (final m in attrRe.allMatches(llmOutput)) {
    final v = m.group(1);
    if (v != null && v.isNotEmpty) paths.add(v.trim());
  }
  // Bare paths with at least one slash and a file extension —
  // robust to models that don't use attribute syntax.
  final barePathRe = RegExp(
    r'[A-Za-z0-9_\-./]+/[A-Za-z0-9_\-./]+\.[A-Za-z0-9]{1,8}',
  );
  for (final m in barePathRe.allMatches(llmOutput)) {
    final v = m.group(0);
    if (v == null) continue;
    // Skip trivial matches like URLs (no triple-dot host), version
    // numbers that fit the pattern.
    if (v.startsWith('http') || v.startsWith('www.')) continue;
    paths.add(v.trim());
  }
  return paths;
}
