// ═════════════════════════════════════════════════════════════════════════
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
// ═════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
/// alone — CC / SP / V / F0 collectively).
enum LogosAxis { primary, m, ab, graph }

/// The fundamental SSE cell: an (emitted, cited) counter per
/// (regime, axis), with two decay mechanisms:
///
///   1. **Count saturation halving** at n=256 — matches Logos's discrete
///      `evaporate()` — keeps the cell responsive when counts accumulate
///      faster than opinions shift.
///
///   2. **Continuous-time decay** on wall-clock age — matches Logos's
///      evaporate() at the continuous-time limit. A cell last updated
///      weeks ago contributes with an exponentially reduced weight vs
///      one updated yesterday. Half-life 30d by default.
///
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

  LogosSseCell({
    this.emitted = 0,
    this.cited = 0,
    int? lastUpdateMs,
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
  void _decayInPlace([DateTime? now]) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final deltaMs = nowMs - lastUpdateMs;
    if (deltaMs <= 0) return;
    final hl = halfLife.inMilliseconds;
    if (hl <= 0) return;
    // exp(-Δt · ln(2) / T_½) = 2^(-Δt / T_½)
    final factor = math.pow(0.5, deltaMs / hl).toDouble();
    if (factor >= 0.9999) return; // nothing worth doing
    emitted *= factor;
    cited *= factor;
    // Floor at 0 and clean up near-zero residuals so the store doesn't
    // accumulate meaningless dust entries forever.
    if (emitted < 0.01) emitted = 0;
    if (cited < 0.01) cited = 0;
    lastUpdateMs = nowMs;
  }

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
class LogosSseStore {
  final String repoPath;
  Map<LogosRegime, Map<LogosAxis, LogosSseCell>>? _cache;
  DateTime? _cacheAt;
  static const _cacheTtl = Duration(seconds: 3);

  LogosSseStore(this.repoPath);

  Future<LogosSseCell> cellFor(LogosRegime regime, LogosAxis axis) async {
    final data = await _load();
    return data[regime]?[axis] ?? LogosSseCell();
  }

  /// Record that [record.axisByPath.length] files were emitted under
  /// [record.regime]. Nothing is marked cited yet — that comes later
  /// via [recordCitations].
  Future<void> recordEmissions(LogosEmissionRecord record) async {
    if (record.isEmpty) return;
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
  }

  /// Record which emitted paths the AI actually cited. Paths not in
  /// [record] are ignored (they weren't emitted through this system).
  Future<void> recordCitations({
    required LogosEmissionRecord record,
    required Set<String> citedPaths,
  }) async {
    if (record.isEmpty) return;
    final data = await _load();
    final tally = <LogosAxis, int>{};
    for (final entry in record.axisByPath.entries) {
      if (!citedPaths.contains(entry.key)) continue;
      tally.update(entry.value, (v) => v + 1, ifAbsent: () => 1);
    }
    if (tally.isEmpty) {
      // No citations hit our emissions — nothing to record. Skip the
      // write entirely (no `_cacheAt` refresh, no disk touch); the
      // emission counters were already incremented at recordEmission
      // time, so the SSE state for this record is already coherent.
      return;
    }
    for (final entry in tally.entries) {
      final cell = data
          .putIfAbsent(record.regime, () => {})
          .putIfAbsent(entry.key, () => LogosSseCell());
      cell._decayInPlace();
      cell.cited += entry.value;
    }
    await _save(data);
  }

  /// Returns utility ratios suitable for scaling probe-axis weights.
  /// `1.0` is the neutral prior; above means the axis is pulling its
  /// weight in this regime; below means it's overfiring.
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

  // ─── persistence ─────────────────────────────────────────────────────

  Future<Map<LogosRegime, Map<LogosAxis, LogosSseCell>>> _load() async {
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
