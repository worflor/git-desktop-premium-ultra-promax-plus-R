import 'dart:math' as math;

import '../../backend/logos_git.dart';
import 'palette_entry.dart';

class PaletteContext {
  const PaletteContext({
    this.currentMode = 0,
    this.isAhead = false,
    this.isBehind = false,
    this.hasStagedChanges = false,
    this.hasUnstagedChanges = false,
    this.stashCount = 0,
    this.aheadCount = 0,
    this.behindCount = 0,
    this.activePath,
    this.recentPaths = const [],
    this.usageFrequency = const {},
    this.recency = const {},
    this.queryFrequency = const {},
    this.transitions = const {},
    this.lastExecutedId,
  });

  final int currentMode;
  final bool isAhead;
  final bool isBehind;
  final bool hasStagedChanges;
  final bool hasUnstagedChanges;
  final int stashCount;
  final int aheadCount;
  final int behindCount;
  final String? activePath;
  final List<String> recentPaths;
  final Map<String, int> usageFrequency;
  final Map<String, DateTime> recency;
  final Map<String, Map<String, int>> queryFrequency;
  final Map<String, Map<String, int>> transitions;
  final String? lastExecutedId;
}

class PaletteScorer {
  static const _capMode = 2.0;
  static const _capUsage = 3.5;
  static const _capRecency = 2.5;
  static const _capRepo = 3.0;
  static const _capState = 3.5;
  static const _capMomentum = 3.0;
  static const _capDiffusion = 4.5;
  static const _capTransition = 3.5;

  Map<String, double>? _diffusionField;

  void scoreAll(
    List<PaletteEntry> entries,
    String query,
    PaletteContext ctx, {
    LogosGit? engine,
  }) {
    final q = query.toLowerCase();
    final queryPrefix = q.length >= 2 ? q.substring(0, 2) : '';

    _diffusionField = null;
    if (engine != null && q.length >= 2) {
      _diffusionField = _buildWitnessField(engine, entries, q);
    }

    for (final e in entries) {
      final fuzzy = q.isEmpty ? 1.0 : _fuzzyScore(e, q);
      if (fuzzy <= 0) {
        e.score = 0;
        e.matchRanges = null;
        continue;
      }
      final (contextProb, prov) =
          _bornMix(e, fuzzy, q, queryPrefix, ctx, engine);
      // Text match is the observation, context is the prior.
      // Observation gates the posterior multiplicatively — no amount
      // of contextual relevance rescues a poor text match.
      e.score = q.isEmpty ? contextProb : fuzzy * contextProb;
      e.provenance = prov;
    }
  }

  (double, List<String>) _bornMix(
    PaletteEntry entry,
    double fuzzy,
    String query,
    String queryPrefix,
    PaletteContext ctx,
    LogosGit? engine,
  ) {
    final axes = <_Axis>[
      _Axis(_modeAffinity(entry, ctx), 1, _capMode, 'mode'),
      _Axis(
        _usageProb(entry.id, queryPrefix, ctx),
        _usageEvidence(entry.id, queryPrefix, ctx),
        _capUsage,
        queryPrefix.isNotEmpty &&
                (ctx.queryFrequency[queryPrefix]?[entry.id] ?? 0) > 0
            ? 'prefix'
            : 'freq',
      ),
      _Axis(
        _recencyProb(entry.id, ctx.recency),
        _recencyEvidence(entry.id, ctx.recency),
        _capRecency,
        'recent',
      ),
      _Axis(_repoProb(entry, ctx), _repoEvidence(entry, ctx), _capRepo, 'repo'),
      _Axis(_stateProb(entry, ctx), _stateEvidence(entry, ctx), _capState, 'state'),
    ];

    final trans = _transitionObs(entry, ctx);
    if (trans != null) {
      axes.add(_Axis(trans.$1, trans.$2, _capTransition, 'flow'));
    }

    final momentum = _momentumObs(entry, engine);
    if (momentum != null) {
      axes.add(_Axis(momentum.$1, momentum.$2, _capMomentum, 'momentum'));
    }

    final diffusion = _diffusionObs(entry);
    if (diffusion != null) {
      axes.add(_Axis(diffusion.$1, diffusion.$2, _capDiffusion, 'spectral'));
    }

    return _mixAmplitudes(axes);
  }

  /// Born-rule mix returning (probability, provenance).
  /// Provenance = the axes whose weight exceeded the mean — the
  /// dominant contributors to the final amplitude.
  (double, List<String>) _mixAmplitudes(List<_Axis> axes) {
    var aSum = 0.0, aBarSum = 0.0, totalW = 0.0;
    final weights = <(String, double)>[];

    for (final ax in axes) {
      if (ax.n == 0) continue;
      final evidence = math.min(_log1p(ax.n), ax.cap);
      final confidence = (ax.p - 0.5).abs();
      final w = confidence * evidence;
      if (w == 0) continue;
      totalW += w;
      final p = ax.p.clamp(1e-6, 1 - 1e-6);
      aSum += w * math.sqrt(p);
      aBarSum += w * math.sqrt(1.0 - p);
      if (ax.label.isNotEmpty) weights.add((ax.label, w));
    }

    if (totalW == 0) return (0.5, const []);
    final a2 = aSum * aSum;
    final b2 = aBarSum * aBarSum;
    final denom = a2 + b2;
    if (!denom.isFinite || denom <= 0) return (0.5, const []);

    final prob = a2 / denom;

    // Provenance: axes above mean weight — the dominant contributors.
    final meanW = totalW / weights.length;
    weights.sort((a, b) => b.$2.compareTo(a.$2));
    final prov = <String>[
      for (final (label, w) in weights)
        if (w > meanW && label != 'text') label,
    ];

    return (prob, prov);
  }

  // ── Spectral diffusion witness field ───────────────────────────

  Map<String, double>? _buildWitnessField(
    LogosGit engine,
    List<PaletteEntry> entries,
    String query,
  ) {
    if (engine.graph.n == 0) return null;

    final primarySources = <String, double>{};
    final hyperedgeSources = <String, double>{};

    for (final nodePath in engine.nodePaths) {
      if (nodePath.toLowerCase().contains(query)) {
        primarySources[nodePath] = 1.0;
      }
    }

    for (final e in entries) {
      if (e.category == PaletteCategory.file && e.refPath != null) {
        if (e.label.toLowerCase().contains(query) &&
            engine.pathToId.containsKey(e.refPath)) {
          primarySources[e.refPath!] = 1.0;
        }
      }
    }

    if (primarySources.isEmpty) return null;

    for (final src in primarySources.keys.toList()) {
      final hyperedges = engine.stats.hyperedgesByPath[src];
      if (hyperedges == null) continue;
      for (final edge in hyperedges) {
        for (final peer in edge.paths) {
          if (!primarySources.containsKey(peer)) {
            final existing = hyperedgeSources[peer] ?? 0.0;
            hyperedgeSources[peer] = math.max(existing, 0.5 * edge.weight);
          }
        }
      }
    }

    final allSources = <String, double>{...primarySources};
    for (final e in hyperedgeSources.entries) {
      allSources.putIfAbsent(e.key, () => e.value);
    }
    _diffusionSourceCount = allSources.length;

    final basis = engine.spectralBasis();
    final gap = basis != null && basis.eigenvalues.length > 1
        ? (basis.eigenvalues[1] - basis.eigenvalues[0]).clamp(0.001, 2.0)
        : 0.1;
    final coherenceGate = gap.clamp(0.05, 0.4);

    final localScores = engine.diffuseWeighted(
      allSources,
      t: 0.5,
      topK: 60,
      phiThreshold: 1e-4,
      coherenceGate: coherenceGate,
    );

    final globalScores = engine.diffuseWeighted(
      allSources,
      t: 2.0,
      topK: 60,
      phiThreshold: 1e-4,
    );

    final localMax =
        localScores.isEmpty ? 1.0 : localScores.first.phi.clamp(1e-9, double.infinity);
    final globalMax =
        globalScores.isEmpty ? 1.0 : globalScores.first.phi.clamp(1e-9, double.infinity);

    final blended = <String, double>{};
    for (final s in localScores) {
      blended[s.path] = 0.7 * (s.phi / localMax);
    }
    for (final s in globalScores) {
      blended[s.path] =
          (blended[s.path] ?? 0.0) + 0.3 * (s.phi / globalMax);
    }

    final field = <String, double>{};
    for (final e in entries) {
      if (e.refPath != null) {
        final phi = blended[e.refPath];
        if (phi != null && phi > 0) field[e.id] = phi.clamp(0.0, 1.0);
      }
    }

    return field.isEmpty ? null : field;
  }

  // ── Text axis ──────────────────────────────────────────────────

  double _fuzzyScore(PaletteEntry entry, String query) {
    final label = entry.label.toLowerCase();

    final (score, ranges) = _matchSubsequence(label, query);
    if (score > 0) {
      entry.matchRanges = ranges;
      return score;
    }

    if (entry.subtitle != null) {
      final (subScore, _) = _matchSubsequence(
        entry.subtitle!.toLowerCase(),
        query,
      );
      if (subScore > 0) {
        entry.matchRanges = null;
        return subScore * 0.7;
      }
    }

    for (final kw in entry.keywords) {
      final (kwScore, _) = _matchSubsequence(kw.toLowerCase(), query);
      if (kwScore > 0) {
        entry.matchRanges = null;
        return kwScore * 0.8;
      }
    }

    entry.matchRanges = null;
    return 0;
  }

  (double, List<(int, int)>) _matchSubsequence(String text, String query) {
    if (query.isEmpty) return (1.0, []);
    if (text.isEmpty) return (0, []);

    int qi = 0;
    double score = 0;
    int consecutive = 0;
    final ranges = <(int, int)>[];
    int rangeStart = -1;

    for (int ti = 0; ti < text.length && qi < query.length; ti++) {
      if (text[ti] == query[qi]) {
        if (rangeStart == -1) rangeStart = ti;
        consecutive++;
        if (ti == 0) score += 0.15;
        if (ti > 0 && _isBoundary(text, ti)) score += 0.10;
        score += 0.1 + (consecutive - 1) * 0.15;
        qi++;
      } else {
        if (rangeStart != -1) {
          ranges.add((rangeStart, ti));
          rangeStart = -1;
        }
        consecutive = 0;
      }
    }

    if (rangeStart != -1) {
      ranges.add((rangeStart, rangeStart + consecutive));
    }
    if (qi < query.length) return (0, []);

    final lengthPenalty = 1.0 - (text.length - query.length) * 0.01;
    return (
      (score / query.length).clamp(0.0, 1.0) * lengthPenalty.clamp(0.5, 1.0),
      ranges,
    );
  }

  bool _isBoundary(String text, int index) {
    if (index == 0) return true;
    final prev = text[index - 1];
    return prev == ' ' ||
        prev == '_' ||
        prev == '-' ||
        prev == '/' ||
        prev == '\\';
  }

  // ── Mode affinity axis ─────────────────────────────────────────

  static const _modeTagAffinity = {
    0: {
      EntryTag.stageAll: 2, EntryTag.unstageAll: 2,
      EntryTag.discardAll: 2, EntryTag.doCommit: 2,
    },
    1: {
      EntryTag.cherryPick: 2, EntryTag.revertCommit: 2,
      EntryTag.tagCreate: 1,
    },
    2: {
      EntryTag.branchCreate: 2, EntryTag.branchDelete: 2,
      EntryTag.branchRename: 2, EntryTag.prAction: 2,
    },
  };

  double _modeAffinity(PaletteEntry entry, PaletteContext ctx) {
    if (entry.hasTag(EntryTag.navWithShortcut)) return _sigmoid(-1);

    final affinityMap = _modeTagAffinity[ctx.currentMode];
    if (affinityMap != null) {
      for (final tag in entry.tags) {
        final a = affinityMap[tag];
        if (a != null) return _sigmoid(a.toDouble());
      }
    }

    // Category-level affinity: files on changes, commits on history, branches on branches
    final catAffinity = switch ((ctx.currentMode, entry.category)) {
      (0, PaletteCategory.file) => 1,
      (1, PaletteCategory.commit) => 1,
      (2, PaletteCategory.branch) => 1,
      _ => 0,
    };
    return _sigmoid(catAffinity.toDouble());
  }

  // ── Usage axis ─────────────────────────────────────────────────

  double _usageProb(String id, String prefix, PaletteContext ctx) {
    if (prefix.isNotEmpty) {
      final perQuery = ctx.queryFrequency[prefix];
      if (perQuery != null) {
        final count = perQuery[id] ?? 0;
        if (count > 0) return _sigmoid(count.toDouble());
      }
    }
    final count = ctx.usageFrequency[id] ?? 0;
    if (count == 0) return 0.5;
    return _sigmoid(count.toDouble());
  }

  int _usageEvidence(String id, String prefix, PaletteContext ctx) {
    if (prefix.isNotEmpty) {
      final perQuery = ctx.queryFrequency[prefix];
      if (perQuery != null && (perQuery[id] ?? 0) > 0) {
        return perQuery[id]!;
      }
    }
    return ctx.usageFrequency[id] ?? 0;
  }

  // ── Recency axis ───────────────────────────────────────────────

  double _recencyProb(String id, Map<String, DateTime> recency) {
    final last = recency[id];
    if (last == null) return 0.5;
    final hours = DateTime.now().difference(last).inMinutes / 60.0;
    return _sigmoid(-hours);
  }

  int _recencyEvidence(String id, Map<String, DateTime> recency) {
    final last = recency[id];
    if (last == null) return 0;
    final hours = DateTime.now().difference(last).inMinutes / 60.0;
    return math.max(1, (math.exp(-hours / 6) * 5).round());
  }

  // ── Repo position axis ─────────────────────────────────────────

  double _repoProb(PaletteEntry entry, PaletteContext ctx) {
    if (!entry.hasTag(EntryTag.repoEntry) &&
        !entry.hasTag(EntryTag.deskEntry) &&
        !entry.hasTag(EntryTag.repoChild)) return 0.5;

    // repoChild entries exist only for NON-active repos. p < 0.5
    // (demoted) with evidence from the recents pool size.
    if (entry.hasTag(EntryTag.repoChild)) return _sigmoid(-1.0);

    final path = entry.refPath;
    if (path == null) return 0.5;

    if (entry.hasTag(EntryTag.deskEntry)) {
      final isActive = ctx.activePath != null && path == ctx.activePath;
      return _sigmoid(isActive ? -1.0 : 1.0);
    }

    if (path == ctx.activePath) return _sigmoid(-1.0);
    final idx = ctx.recentPaths.indexOf(path);
    if (idx < 0) return 0.5;
    final n = math.max(1, ctx.recentPaths.length);
    final rank = (n - idx).toDouble() / n;
    return _sigmoid(rank * 2 - 1);
  }

  int _repoEvidence(PaletteEntry entry, PaletteContext ctx) {
    if (!entry.hasTag(EntryTag.repoEntry) &&
        !entry.hasTag(EntryTag.deskEntry) &&
        !entry.hasTag(EntryTag.repoChild)) return 0;
    return math.max(1, ctx.recentPaths.length);
  }

  // ── State axis ─────────────────────────────────────────────────

  double _stateProb(PaletteEntry entry, PaletteContext ctx) {
    final n = _stateEvidence(entry, ctx);
    if (n == 0) return 0.5;
    return _sigmoid(n.toDouble());
  }

  int _stateEvidence(PaletteEntry entry, PaletteContext ctx) {
    if (entry.hasTag(EntryTag.syncPush)) return ctx.isAhead ? ctx.aheadCount : 0;
    if (entry.hasTag(EntryTag.syncPull)) return ctx.isBehind ? ctx.behindCount : 0;
    if (entry.hasTag(EntryTag.doCommit)) return ctx.hasStagedChanges ? 2 : 0;
    if (entry.hasTag(EntryTag.stageAll)) return ctx.hasUnstagedChanges ? 2 : 0;
    if (entry.hasTag(EntryTag.stashPop) || entry.hasTag(EntryTag.stashApply)) {
      return ctx.stashCount > 0 ? ctx.stashCount : -2;
    }
    return 0;
  }

  // ── Transition axis (Markov command flow) ───────────────────────
  //
  // P(entry | lastExecuted) from the observed transition counts.
  // n = total transitions from lastExecuted (how well we know this
  // command's successors). p = fraction of those that landed on
  // this entry. When n=0, axis is silent — no history to learn from.

  (double, int)? _transitionObs(PaletteEntry entry, PaletteContext ctx) {
    final last = ctx.lastExecutedId;
    if (last == null) return null;
    final row = ctx.transitions[last];
    if (row == null || row.isEmpty) return null;
    final total = row.values.fold(0, (s, v) => s + v);
    if (total == 0) return null;
    final count = row[entry.id] ?? 0;
    final p = count > 0 ? count / total : 0.0;
    return (p.clamp(0.0, 1.0), total);
  }

  // ── Momentum axis ──────────────────────────────────────────────
  //
  // p = probability derived from curvature × normalized volatility ×
  //     meaningfulness (1 - ritualness). n = actual touch count from
  //     the engine — the number of independent commits that generated
  //     the curvature estimate. This is the REAL evidence count.

  (double, int)? _momentumObs(PaletteEntry entry, LogosGit? engine) {
    if (engine == null) return null;
    final path = entry.refPath;
    if (path == null || entry.category != PaletteCategory.file) return null;

    final touches = engine.stats.touches[path];
    if (touches == null || touches == 0) return null;

    final curv = engine.curvature(path);
    final vol = engine.stats.volatility[path];
    if (vol == null) return null;

    final maxVol = _maxVolatility(engine);
    if (maxVol <= 0) return null;

    final volNorm = (vol / maxVol).clamp(0.0, 1.0);
    final ritual = engine.stats.ritualnessByPath[path] ?? 0.0;
    final meaningfulness = 1.0 - ritual.clamp(0.0, 1.0);

    final p = (0.5 + 0.5 * curv * volNorm * meaningfulness).clamp(0.0, 1.0);
    return (p, touches);
  }

  // ── Diffusion axis ─────────────────────────────────────────────
  //
  // p = raw diffusion phi (heat retained at this node after
  //     propagation). Free to range [0, 1] — no clamping to [0.5, 1].
  // n = number of source files that contributed to the diffusion,
  //     scaled by the phi strength at this node. A strong signal
  //     from many sources = high evidence; a weak signal = low.

  (double, int)? _diffusionObs(PaletteEntry entry) {
    final phi = _diffusionField?[entry.id];
    if (phi == null || phi <= 0) return null;
    final sourceCount = _diffusionSourceCount;
    final n = math.max(1, (sourceCount * phi).round());
    return (phi.clamp(0.0, 1.0), n);
  }

  int _diffusionSourceCount = 0;

  double _cachedMaxVol = -1;
  String? _cachedMaxVolRepo;

  double _maxVolatility(LogosGit engine) {
    final repoKey = '${engine.graph.n}';
    if (_cachedMaxVolRepo == repoKey && _cachedMaxVol > 0) {
      return _cachedMaxVol;
    }
    var maxV = 0.0;
    for (final v in engine.stats.volatility.values) {
      if (v > maxV) maxV = v;
    }
    _cachedMaxVol = maxV;
    _cachedMaxVolRepo = repoKey;
    return maxV;
  }

  // ── Math ───────────────────────────────────────────────────────

  static double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  static double _log1p(int n) {
    if (n <= 0) return 0;
    return math.log(1.0 + n);
  }
}

class _Axis {
  final double p;
  final int n;
  final double cap;
  final String label;
  const _Axis(this.p, this.n, this.cap, [this.label = '']);
}
