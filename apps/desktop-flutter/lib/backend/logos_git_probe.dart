// logos_git_probe.dart — structural probe enrichment for the context builder
//
// Philosophy — Logos is an attention codec:
//
//   A compressor that predicts the next bit via multiple orthogonal
//   observables, mixed by Born-rule amplitude interference. The diff is
//   one observable, not THE observable. A good context builder queries
//   every available attention axis against the diff, not just its file
//   list.
//
// This file constructs a [DiffProbe] — the weighted source distribution
// ρ that the engine diffuses from. Three observables feed into ρ:
//
//   1. Primary (from the diff)       — touched file paths, weight 1.0
//   2. M-axis (PPM / pickaxe)         — files CURRENTLY containing the
//                                       identifiers added or removed in
//                                       the diff, weight 0.35
//   3. Ab-axis (path mirror / stride) — convention-paired test/source
//                                       files (lib/foo.dart ↔
//                                       test/foo_test.dart), weight 0.55
//
// Why these three:
//   - Primary: the literal "what changed"
//   - M: catches renames and moves that co-change history hasn't
//     learned yet (the classic "hidden caller after rename" bug)
//   - Ab: bridges the test/source gap that CC might miss if tests
//     haven't been updated in the time window
//
// The weights are the **starting priors** for the source distribution —
// they're normalised to sum to 1 before diffusion. The rest is the
// engine's multi-axis Born mix on the learned graph metric.
//
// Temperature adaptation (§`adaptiveTemperature`):
//   We use the diff's own coherence as the observation that chooses t.
//   Cohesive diff (touched files tightly coupled to each other) → tight
//   diffusion t=0.5. Scattered diff → t=2.0 — we widen the search
//   precisely because we don't know where to look. This is the
//   codec-aesthetic equivalent of "when the match state is crystal,
//   trust the predictor; when it's gas, let the prior take over."

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'git.dart' show extractDiffTouchedPaths;
import 'logos_git.dart';
import 'logos_git_calibration.dart';

final Map<String, Future<DiffProbe>> _inflightProbeBuilds = {};
final Map<String, Future<Set<String>>> _inflightPickaxeLookups = {};

/// A weighted source distribution for diffusion. Built from the diff
/// plus any structural enrichment axes (M, Ab).
class DiffProbe {
  /// path → source weight (any positive double). Normalised inside the
  /// engine before Chebyshev expansion.
  final Map<String, double> sourceWeights;

  /// The original diff's literal touched paths (post-rename 'b/' side).
  /// Kept separately so we can filter the output — users don't want to
  /// see the diff files reappear in the "related" list.
  final Set<String> primaryPaths;

  /// Suggested diffusion temperature. Populated by
  /// [LogosGitProbeBuilder.adaptiveTemperature]; null means "use default."
  final double? suggestedTemperature;

  /// Per-axis diagnostic counts for observability.
  final ProbeStats stats;

  const DiffProbe({
    required this.sourceWeights,
    required this.primaryPaths,
    required this.suggestedTemperature,
    required this.stats,
  });

  /// Empty probe — no sources. `diffuse` will return empty.
  static const empty = DiffProbe(
    sourceWeights: <String, double>{},
    primaryPaths: <String>{},
    suggestedTemperature: null,
    stats: ProbeStats(
      primaryCount: 0,
      mMatches: 0,
      abMatches: 0,
      mSymbols: 0,
      coherence: 1.0,
    ),
  );
}

class ProbeStats {
  final int primaryCount;
  final int mMatches;
  final int abMatches;
  final int mSymbols;
  final double coherence;

  /// Number of files surfaced via the symbol-overlap axis — new/untracked
  /// files whose identifier overlap with change-set peers was the signal.
  /// Tracked so SSE can calibrate symbol-axis utility per regime.
  final int symbolMatches;
  const ProbeStats({
    required this.primaryCount,
    required this.mMatches,
    required this.abMatches,
    required this.mSymbols,
    required this.coherence,
    this.symbolMatches = 0,
  });

  @override
  String toString() =>
      'primary=$primaryCount M=$mMatches/$mSymbols Ab=$abMatches '
      'sym=$symbolMatches coh=${coherence.toStringAsFixed(2)}';
}

/// SSE-learned utility scales are clamped to this band before scaling
/// the probe's axis weights. Rationale: a brand-new repo can produce
/// over- or under-confident utilities early (cold-start KT prior
/// deviations), so the clamp caps how aggressively the calibration
/// loop can push the weights away from the hand-picked defaults.
/// Upper bound 2.5× matches the cap Agent B recommended during the
/// SSE calibration design pass; lower bound 0.3× keeps an axis alive
/// even when historically uncited so it can re-earn weight if the
/// team's behaviour shifts. Shared by both the initial probe build
/// and the after-the-fact `effectiveMWeightFor` / `effectiveAbWeightFor`
/// test hooks.
const double _sseUtilityScaleMin = 0.3;
const double _sseUtilityScaleMax = 2.5;

class LogosGitProbeBuilder {
  /// Weights per observable. Exposed as a field so future learned
  /// per-repo calibration (SSE) can tune them without touching callers.
  final double primaryWeight;
  final double mWeight;
  final double abWeight;

  /// Upper bound on how many pickaxe symbols we'll grep for. Each
  /// grep is one subprocess; capping keeps total runtime bounded.
  final int mSymbolCap;

  /// Minimum identifier length to consider for M-axis. Shorter tokens
  /// produce noisy hits (a single-letter identifier matches everywhere).
  final int mSymbolMinLength;

  /// Optional SSE calibration store. When supplied, the probe reads
  /// learned per-regime utilities and SCALES the default m/ab weights
  /// accordingly. This is the closed learning loop:
  ///   emission → audit → citation matching → SSE cell update → next
  ///   probe reads utility → weight scales → better emission
  /// Null falls back to the hardcoded weights; existing tests and the
  /// cold-start path stay deterministic.
  final LogosSseStore? sseStore;

  const LogosGitProbeBuilder({
    this.primaryWeight = 1.0,
    this.mWeight = 0.35,
    this.abWeight = 0.55,
    this.mSymbolCap = 12,
    this.mSymbolMinLength = 4,
    this.sseStore,
  });

  /// Build the probe from a diff. Pure + async I/O — may shell out to
  /// git for M-axis lookups. Never throws; best-effort enrichment.
  Future<DiffProbe> build({
    required String repoPath,
    required String diffText,
    required LogosGit engine,
  }) async {
    final primaryPaths = _extractTouchedPaths(diffText);
    if (primaryPaths.isEmpty) return DiffProbe.empty;

    // Resolve self-learned per-regime axis utilities. We defer the
    // regime classification until AFTER we know the coherence, but
    // we need the utilities BEFORE applying M/Ab weights — so we
    // provisionally classify on just the file count, fetch utilities,
    // then reclassify once we have coherence. The regime only shifts
    // close to thresholds; the utility numbers are robust to that
    // minor flutter and this order keeps I/O parallel with pickaxe.
    final provisionalRegime = LogosRegime.classify(
      fileCount: primaryPaths.length,
      coherence: 0.5, // neutral prior
    );
    // Use the trend-aware projection so an axis whose utility is
    // climbing in this regime gets weighted up one half-life early
    // (the SSE store's natural memory horizon). Fresh / low-evidence
    // cells degrade gracefully to the spot utility — see
    // [LogosSseStore.projectedUtilitiesFor] for the math.
    final utilities = sseStore == null
        ? const <LogosAxis, double>{}
        : await sseStore!.projectedUtilitiesFor(provisionalRegime);
    final learnedMScale = (utilities[LogosAxis.m] ?? 1.0)
        .clamp(_sseUtilityScaleMin, _sseUtilityScaleMax);
    final learnedAbScale = (utilities[LogosAxis.ab] ?? 1.0)
        .clamp(_sseUtilityScaleMin, _sseUtilityScaleMax);
    final effectiveMWeight = mWeight * learnedMScale;
    final effectiveAbWeight = abWeight * learnedAbScale;

    // Start with the primary observation: diff's touched files.
    final weights = <String, double>{
      for (final p in primaryPaths) p: primaryWeight,
    };

    // M-axis: pickaxe. Identifiers added or removed in the diff text.
    // PER-SYMBOL parallel lookup — specificity-weighted. A symbol that
    // matches 500 files is a hub keyword ("String", "handle", "value")
    // and its matches are noise; we weight each symbol's contribution by
    //   specificity = 1 / log(1 + n_matches)
    // so rare identifiers dominate, hubs decay gracefully to near-zero.
    // The MIXER axes (F0/CC/SP/V) are already Born-gated by confidence;
    // this is the M-axis equivalent.
    final addedRemovedSymbols = _extractDiffSymbols(
      diffText,
      cap: mSymbolCap,
      minLength: mSymbolMinLength,
    );
    var mMatches = 0;
    if (addedRemovedSymbols.isNotEmpty) {
      final bySymbol = await _pickaxeLookupPerSymbol(
        repoPath: repoPath,
        symbols: addedRemovedSymbols,
      );
      // Hub downweighting: specificity = 1 / log(1 + n_matches). For the
      // ratios to stay interpretable we also cap the minimum symbols
      // count at 2 (otherwise 1-match symbols score inf-specificity).
      for (final entry in bySymbol.entries) {
        final hits = entry.value;
        if (hits.isEmpty) continue;
        final specificity = 1.0 / math.log(math.max(2, hits.length) + 1);
        for (final path in hits) {
          if (primaryPaths.contains(path)) continue;
          weights.update(
            path,
            (existing) => existing + effectiveMWeight * specificity,
            ifAbsent: () => effectiveMWeight * specificity,
          );
        }
      }
      // Count unique M-hit paths (not double-counting multi-symbol hits).
      final allHits = <String>{};
      for (final hits in bySymbol.values) {
        allHits.addAll(hits.where((h) => !primaryPaths.contains(h)));
      }
      mMatches = allHits.length;
    }

    // Ab-axis: path mirror. For each touched source file, check for
    // its test counterpart (and vice versa) using common convention
    // patterns. Language-agnostic — the patterns cover Dart, JS/TS,
    // Python, Rust, Go with minimal per-language logic.
    //
    // Existence checks run in parallel via `Future.wait`. Each
    // `_fileExists` is a real async `File.exists()` stat — serialising
    // them under an outer `await` compounded single-digit-ms syscalls
    // into hundreds of ms of blocked time on wide diffs. Candidates are
    // deduped first so we don't stat the same mirror twice when two
    // touched files point at the same counterpart (e.g. src/foo and
    // its test/foo_test both nominating the other).
    var abMatches = 0;
    final mirrors = <String>{};
    for (final touched in primaryPaths) {
      for (final mirror in _candidateMirrors(touched)) {
        if (weights.containsKey(mirror)) continue; // already in probe
        mirrors.add(mirror);
      }
    }
    if (mirrors.isNotEmpty) {
      final paths = mirrors.toList(growable: false);
      final exists = await Future.wait(
        paths.map((m) => _fileExists(repoPath, m)),
      );
      for (var i = 0; i < paths.length; i++) {
        if (exists[i]) {
          weights[paths[i]] = effectiveAbWeight;
          abMatches++;
        }
      }
    }

    // Regime signal: coherence of the primary file set. Feeds
    // [adaptiveTemperature] below.
    final coherence = engine.coherence(primaryPaths);
    final t = adaptiveTemperature(
      primaryPaths: primaryPaths,
      coherence: coherence,
    );

    // Symbol-axis diagnostic: count primary paths that are NOT graph
    // nodes but have symbol-edge neighbours — these are the files where
    // the symbol axis carries real information (new/untracked files with
    // identifier overlap against the change set). Feeds SSE regime
    // classification and the probe's toString() for observability.
    var symbolMatches = 0;
    for (final path in primaryPaths) {
      if (engine.pathToId.containsKey(path)) continue;
      if (engine.symbolEdges[path]?.isNotEmpty ?? false) symbolMatches++;
    }

    return DiffProbe(
      sourceWeights: weights,
      primaryPaths: primaryPaths,
      suggestedTemperature: t,
      stats: ProbeStats(
        primaryCount: primaryPaths.length,
        mMatches: mMatches,
        abMatches: abMatches,
        mSymbols: addedRemovedSymbols.length,
        coherence: coherence,
        symbolMatches: symbolMatches,
      ),
    );
  }

  /// Temperature selection based on the diff's own regime.
  /// Philosophy: when the diff is cohesive we already know where to
  /// look (tight t). When it's scattered, we widen the aperture until
  /// we find the common thread. This is the Logos "match-state →
  /// trust-the-predictor" move, at codebase scale.
  double adaptiveTemperature({
    required Set<String> primaryPaths,
    required double coherence,
  }) {
    // Size component: few files → default; many files → widen.
    final sizeScale = primaryPaths.length <= 3
        ? 0.0
        : primaryPaths.length <= 10
            ? 0.3
            : 0.8;

    // Coherence component: tight cluster → tighten; scattered → widen.
    // Coherence is in [0, 1]; we map to a [-0.4, 0.6] shift.
    final cohShift = (1.0 - coherence) * 1.0 - 0.4;

    // Base t=1.0 plus components. Clamp to a reasonable band so the
    // Chebyshev approximation stays accurate.
    return (1.0 + sizeScale + cohShift).clamp(0.3, 3.0);
  }

  Set<String> _extractTouchedPaths(String diffText) =>
      extractDiffTouchedPaths(diffText);

  /// Scan + and − lines for identifier tokens. Picks the N most
  /// distinctive by a simple heuristic: longer tokens first (longer =
  /// rarer = more specific), deduplicated.
  List<String> _extractDiffSymbols(
    String diffText, {
    required int cap,
    required int minLength,
  }) {
    final identifier = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]{2,})\b');
    final seen = <String>{};
    for (final line in diffText.split('\n')) {
      if (line.isEmpty) continue;
      final first = line.codeUnitAt(0);
      // Only added/removed lines ('+' / '−'), not context (' ') or
      // hunk headers ('@').
      if (first != 0x2B && first != 0x2D) continue;
      for (final m in identifier.allMatches(line)) {
        final id = m.group(1)!;
        if (id.length < minLength) continue;
        if (_isReservedOrBoring(id)) continue;
        seen.add(id);
      }
    }
    final sorted = seen.toList()..sort((a, b) => b.length.compareTo(a.length));
    return sorted.take(cap).toList(growable: false);
  }

  /// Reserved words / common tokens we don't want to grep for — too
  /// noisy. Language-agnostic "structural" keywords across popular
  /// languages, filtered by length (the minLength gate already excludes
  /// 2–3 letter tokens, so this only kicks in for 4+).
  bool _isReservedOrBoring(String id) {
    const blocklist = {
      'return',
      'function',
      'const',
      'class',
      'import',
      'export',
      'public',
      'private',
      'static',
      'final',
      'void',
      'null',
      'true',
      'false',
      'this',
      'super',
      'async',
      'await',
      'string',
      'number',
      'boolean',
      'object',
      'value',
      'result',
      'error',
      'length',
      'push',
      'pop',
      'forEach',
      'map',
      'filter',
      'reduce',
      'toString',
      'valueOf',
    };
    return blocklist.contains(id);
  }

  /// Per-symbol pickaxe. Runs ALL greps in parallel (one subprocess each
  /// but awaited as a fan-out) and returns `symbol → file set`. That
  /// lets the caller apply specificity weighting based on per-symbol
  /// match count. Total wall time ≈ single slowest grep.
  Future<Map<String, Set<String>>> _pickaxeLookupPerSymbol({
    required String repoPath,
    required List<String> symbols,
  }) async {
    if (symbols.isEmpty) return const {};
    final futures = symbols.map((sym) => _pickaxeSingle(
          repoPath: repoPath,
          symbol: sym,
        ));
    final results = await Future.wait(futures);
    final bySymbol = <String, Set<String>>{};
    for (var i = 0; i < symbols.length; i++) {
      bySymbol[symbols[i]] = results[i];
    }
    return bySymbol;
  }

  Future<Set<String>> _pickaxeSingle({
    required String repoPath,
    required String symbol,
  }) async {
    final cacheKey = '$repoPath|$symbol';
    final inflight = _inflightPickaxeLookups[cacheKey];
    if (inflight != null) return inflight;
    final future = _pickaxeSingleImpl(
      repoPath: repoPath,
      symbol: symbol,
    );
    _inflightPickaxeLookups[cacheKey] = future;
    future.whenComplete(() => _inflightPickaxeLookups.remove(cacheKey));
    return future;
  }

  Future<Set<String>> _pickaxeSingleImpl({
    required String repoPath,
    required String symbol,
  }) async {
    // Per-grep timeout. `git grep -l` is O(files containing the symbol);
    // hub identifiers (`String`, `value`, `handle`) can take multiple
    // seconds on large repos — telemetry observed p95 ≈ 4.5 s and a 6 s
    // outlier. The specificity weight `1 / log(1 + matches)` already
    // collapses hub-symbol contribution toward zero, so bailing after
    // 3 s costs essentially no signal while bounding tail latency.
    // Hard-killed processes return an empty set (identical to "no
    // matches"), which downstream Ab-axis / diffusion handle naturally.
    const grepTimeout = Duration(seconds: 3);
    Process? process;
    try {
      process = await Process.start(
        'git',
        ['grep', '-l', '-w', '-I', symbol],
        workingDirectory: repoPath,
        runInShell: false,
      );
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      // Drain stderr so a slow `git grep` can't block on pipe backpressure.
      final stderrFuture = process.stderr.drain<void>();
      final int exitCode;
      try {
        exitCode = await process.exitCode.timeout(grepTimeout);
      } on TimeoutException {
        process.kill();
        return const {};
      }
      // exit 1 = no matches; anything else = error (e.g. not a git repo).
      if (exitCode != 0 && exitCode != 1) return const {};
      final out = await stdoutFuture;
      await stderrFuture;
      return out
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  /// Convention-based path mirrors. For a source file, produce candidate
  /// test paths and vice versa. We never guarantee a match — [_fileExists]
  /// filters. Intentionally cover multiple languages with a few patterns
  /// so this stays language-agnostic.
  List<String> _candidateMirrors(String inputPath) {
    final dir = p.posix.dirname(inputPath);
    final base = p.posix.basenameWithoutExtension(inputPath);
    final ext = p.posix.extension(inputPath);
    final candidates = <String>{};

    // source → test
    // lib/foo.dart              → test/foo_test.dart
    // src/foo.ts                → test/foo.test.ts, __tests__/foo.ts
    // module/file.py            → tests/test_file.py
    // src/file.rs               → tests/file.rs (integration) or inline #[cfg(test)]
    if (!_looksLikeTest(inputPath)) {
      // Replace leading "lib" or "src" with "test" or "tests".
      for (final fromDir in ['lib', 'src']) {
        for (final toDir in ['test', 'tests']) {
          if (dir.startsWith('$fromDir/') || dir == fromDir) {
            final swapped = dir.replaceFirst(fromDir, toDir);
            candidates.add('$swapped/${base}_test$ext');
            candidates.add('$swapped/test_$base$ext');
            candidates.add('$swapped/$base.test$ext');
            candidates.add('$swapped/$base.spec$ext');
            candidates.add('$swapped/$base$ext');
          }
        }
      }
      // Sibling tests/__tests__ folder.
      candidates.add('$dir/${base}_test$ext');
      candidates.add('$dir/__tests__/$base$ext');
    } else {
      // test → source. Strip the _test / test_ / .test. / .spec. markers
      // and swap directory.
      final stripped = base
          .replaceAll(RegExp(r'(_test|_spec)$'), '')
          .replaceAll(RegExp(r'^(test_|spec_)'), '')
          .replaceAll(RegExp(r'(\.test|\.spec)$'), '');
      for (final fromDir in ['test', 'tests', '__tests__']) {
        for (final toDir in ['lib', 'src']) {
          if (dir.startsWith('$fromDir/') || dir == fromDir) {
            final swapped = dir.replaceFirst(fromDir, toDir);
            candidates.add('$swapped/$stripped$ext');
          }
        }
      }
      candidates.add('$dir/../$stripped$ext');
    }

    // Normalise (collapse "..", double slashes) in POSIX style —
    // git paths are always forward-slash regardless of host OS.
    return candidates.map((c) => p.posix.normalize(c)).toList();
  }

  bool _looksLikeTest(String path) => looksLikeTestPath(path);

  Future<bool> _fileExists(String repoPath, String relPath) async {
    try {
      return await File(p.join(repoPath, relPath)).exists();
    } catch (_) {
      return false;
    }
  }
}

/// Public, shared test-path classifier. Returns true for conventional
/// test/spec locations across the mainstream ecosystems (Dart/Flutter,
/// Go, TypeScript/JavaScript, Python). Both the Ab-axis mirror
/// derivation inside [LogosGitProbeBuilder] and the downstream
/// citation-axis classifier in `ai.dart` route through here, so a
/// file that looks like a test to the probe also looks like a test to
/// the SSE feedback loop — avoids axis-miscount drift.
bool looksLikeTestPath(String path) {
  final norm = path.toLowerCase();
  return norm.contains('/test/') ||
      norm.contains('/tests/') ||
      norm.contains('/__tests__/') ||
      norm.endsWith('_test.dart') ||
      norm.endsWith('_test.go') ||
      norm.endsWith('.test.ts') ||
      norm.endsWith('.test.js') ||
      norm.endsWith('.spec.ts') ||
      norm.endsWith('.spec.js') ||
      norm.startsWith('test_') ||
      norm.contains('/test_');
}

/// Convenience wrapper so callers can build a probe in a single
/// `await` without instantiating the builder. Resolves the per-repo
/// SSE calibration store so learned per-regime utilities feed back
/// into the next build.
Future<DiffProbe> buildDiffProbe({
  required String repoPath,
  required String diffText,
  required LogosGit engine,
}) {
  final key =
      '$repoPath|${diffText.hashCode}|${engine.stats.totalCommits}|${engine.nodePaths.length}|${engine.symbolEdges.length}';
  final inflight = _inflightProbeBuilds[key];
  if (inflight != null) return inflight;
  final future = LogosGitProbeBuilder(
    sseStore: LogosSseStore(repoPath),
  ).build(
    repoPath: repoPath,
    diffText: diffText,
    engine: engine,
  );
  _inflightProbeBuilds[key] = future;
  future.whenComplete(() => _inflightProbeBuilds.remove(key));
  return future;
}

/// Diffuse from a [DiffProbe]. Unlike the engine's `diffuse(Set<String>)`,
/// this respects per-source *weights* — M and Ab contributions land with
/// less starting mass than the primary diff.
/// Lives here (not on [LogosGit]) because probe construction is repo-aware
/// (I/O + git) but diffusion is pure math. Keeping the engine pure makes
/// the WASM port trivial later.
List<RelevanceScore> diffuseFromProbe({
  required LogosGit engine,
  required DiffProbe probe,
  double? temperatureOverride,
}) {
  if (probe.sourceWeights.isEmpty) return const [];
  final t = temperatureOverride ?? probe.suggestedTemperature ?? 1.0;
  final symbolPaths = <String>{
    for (final p in engine.symbolEdges.keys)
      if (!engine.pathToId.containsKey(p)) p,
  };
  final axisLabels = <String, String>{
    for (final entry in probe.sourceWeights.entries)
      entry.key: _classifyProbeAxis(
        entry.key,
        probe,
        symbolPaths: symbolPaths,
      ),
  };
  final evidence = engine.gatherEvidence(
    focusWeights: probe.sourceWeights,
    axisLabelByPath: axisLabels,
    t: t,
    excludePaths: probe.primaryPaths,
    includeSupportAttribution: false,
    includeSummaryDiagnostics: false,
  );
  if (evidence != null && evidence.ranked.isNotEmpty) {
    return [
      for (final e in evidence.ranked)
        RelevanceScore(
          e.path,
          e.utility > 0 ? e.utility : (e.support * e.integrity * 0.05),
        ),
    ];
  }

  // Build a weighted set via repeated application: diffuse returns a
  // single ranking from a unit source. For weighted sources we scale
  // per-file mass and rely on diffusion's linearity in ρ — which our
  // test suite pins down.
  //
  // The cleanest way is to build a basis from the union of source paths,
  // then apply a weighted recombination. Simpler for now: diffuse at
  // t using the engine's diffuse() and scale by the normalised weight
  // distribution. That preserves ordering though not raw magnitudes;
  // for a ranking surface that's what we want.
  //
  // Heat kernel is linear in ρ, so the weighted mixture diffuses in
  // one matvec pass — no per-source basis needed.
  return _weightedDiffuse(engine: engine, probe: probe, t: t);
}

String _classifyProbeAxis(
  String path,
  DiffProbe probe, {
  required Set<String> symbolPaths,
}) {
  if (probe.primaryPaths.contains(path)) return 'primary';
  if (symbolPaths.contains(path)) return LogosAxis.symbol.name;
  return 'graph';
}

List<RelevanceScore> _weightedDiffuse({
  required LogosGit engine,
  required DiffProbe probe,
  required double t,
}) {
  // One matvec pass for the whole probe — heat-kernel linearity lets
  // us diffuse the weighted mixture directly instead of summing N
  // unit-mass diffusions. For a typical probe with 8 sources this is
  // 8× the Chebyshev work saved.
  return engine.diffuseWeighted(
    probe.sourceWeights,
    t: t,
    excludePaths: probe.primaryPaths,
  );
}

// Tests reach into these private helpers via the visible-for-testing
// wrappers below. No production code should use them.
// ignore: avoid_classes_with_only_static_members

class LogosGitProbeTestAccess {
  LogosGitProbeTestAccess._();

  static List<String> extractDiffSymbols(String diffText,
      {int cap = 12, int minLength = 4}) {
    return const LogosGitProbeBuilder()
        ._extractDiffSymbols(diffText, cap: cap, minLength: minLength);
  }

  static List<String> candidateMirrors(String path) {
    return const LogosGitProbeBuilder()._candidateMirrors(path);
  }

  static double adaptiveTemperature({
    required Set<String> primaryPaths,
    required double coherence,
  }) {
    return const LogosGitProbeBuilder().adaptiveTemperature(
      primaryPaths: primaryPaths,
      coherence: coherence,
    );
  }

  /// Exposed for tests: builds a probe with an injected [sseStore] so
  /// we can verify that learned utilities actually scale m/ab weights.
  /// Skips the I/O-dependent paths (pickaxe, file-exists checks) that
  /// need a real repo.
  static double effectiveMWeightFor({
    required double baseMWeight,
    required double learnedUtility,
  }) {
    return baseMWeight *
        learnedUtility.clamp(_sseUtilityScaleMin, _sseUtilityScaleMax);
  }

  static double effectiveAbWeightFor({
    required double baseAbWeight,
    required double learnedUtility,
  }) {
    return baseAbWeight *
        learnedUtility.clamp(_sseUtilityScaleMin, _sseUtilityScaleMax);
  }
}
