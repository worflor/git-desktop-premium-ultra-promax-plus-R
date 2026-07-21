// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// WORLDLINE FIELD — per-commit structural coordinates for the history
// strip's "Worldline" posture.
//
// This is the in-app, isolate-backed port of `tool/worldline_audit.dart`
// (the Phase-1 validation harness). It assigns every commit in the
// strip's visible window a pair of sky coordinates: the churn-weighted
// centroid of its touched files in the co-change Laplacian's Π₀-projected
// eigen-plane (the first TWO modes ABOVE the entire zero-mode subspace).
//
// FIDELITY — every number here mirrors the audit exactly:
//   * graph      = file×file co-change, Jaccard(commitSet_i, commitSet_j)
//                  edge weights, top-K=16 sparsify, re-symmetrised, built
//                  with CsrGraph.fromRawEdges.
//   * Π₀ law     = SpectralBasis.fromGraph → axes [firstExcitedIndex,
//                  firstExcitedIndex+1] (union-find component count folds
//                  into kernelDim via the deflated Lanczos), so ALL λ=0
//                  popularity/component modes are projected out.
//   * centroid   = Σ w·φ / Σ w with w = √(additions+deletions) — the
//                  house heavy-tail damping.
//
// DATA-SOURCE CHOICE: the harness build path, run whole inside
// `Isolate.run` (filament-freeze house law: engine math never on the
// main isolate). The alternative — reusing `LogosGit.engineFor(repo)`'s
// cached file basis — was investigated and rejected: that engine's graph
// is built over its own HEAD-gated window (not the strip's "last N"), it
// isn't isolate-transferable, and we must shell `git log --numstat` for
// per-commit churn regardless. The numstat walk that feeds the churn IS
// the graph, so the harness path is both more faithful to the audit and
// strictly cheaper than splitting work across the isolate boundary.
//
// The whole build (git log + graph + Lanczos + centroids) runs in one
// isolate; the main thread only ever holds the finished plain-data
// [WorldlineField]. Cached per repo+window+tip through [PeekWarmCache].

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:git_desktop/backend/logos_core.dart'
    show CsrGraph, SpectralBasis, SpectralGroundSpace;
import 'package:git_desktop/backend/peek_warm_cache.dart';

// ── COMMITTED LAWS (identical to the audit) ─────────────────────────────────
/// Top-K strongest co-change neighbours kept per file — the engine's own
/// sparsification constant (spectral_spacetime.dart buildCommitGraph).
const int _kTopK = 16;

/// Extra excited modes requested beyond the two kept, so deflated Lanczos
/// resolves the lowest excited modes accurately above the kernel.
const int _kExcitedBuffer = 6;

/// ROBUST SKY SCALING LAW. Raw min-max normalisation lets ONE outlier
/// commit own the ruler: at narrow windows a single cross-cutting commit
/// flattened every era into a thin band. Instead: centre on the MEDIAN,
/// and set the unit scale so ±[_kSkySigmas]·σ_w maps to ±1, where σ_w is
/// the standard deviation of the WINSORIZED sample (values clipped to the
/// [5th, 95th] percentiles before computing σ, so the outlier can't
/// inflate the very σ that's meant to resist it). Values beyond the rim
/// clamp to ±1.
///
/// Derivation of 2.5: for near-normal spread, ±2.5σ covers ≈98.8% of the
/// mass — era structure occupies the full plane while <2% of honest
/// commits touch the rim; a genuine outlier still reads as extreme
/// (pinned at the rim) without holding the ruler hostage.
const double _kSkySigmas = 2.5;
const double _kWinsorLo = 0.05;
const double _kWinsorHi = 0.95;

/// Median + winsorized half-range (= [_kSkySigmas]·σ_w) for one axis.
/// PUBLIC pure function — the scaling law above is load-bearing (it
/// decides whether one outlier commit owns the sky's ruler), so the test
/// suite witnesses it directly instead of copying the math. halfRange is
/// floored at 1e-9: a constant-input axis divides by the floor, never by
/// zero, and maps every value to 0 (dead centre).
({double center, double halfRange}) worldlineRobustAxis(List<double> xs) {
  final sorted = [...xs]..sort();
  final n = sorted.length;
  final median = n.isOdd
      ? sorted[n ~/ 2]
      : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  // Winsorize: clip to the [5th, 95th] percentile values.
  final lo = sorted[(_kWinsorLo * (n - 1)).round()];
  final hi = sorted[(_kWinsorHi * (n - 1)).round()];
  var sum = 0.0;
  for (final x in sorted) {
    final w = x < lo ? lo : (x > hi ? hi : x);
    final d = w - median;
    sum += d * d;
  }
  final sigmaW = math.sqrt(sum / n);
  return (center: median, halfRange: math.max(_kSkySigmas * sigmaW, 1e-9));
}

/// Structural coordinate for one commit, already normalised for render.
class WorldlineCoord {
  /// Vertical sky position (mode `firstExcitedIndex`), centred and scaled
  /// to roughly [-1, 1] across the covered window. Feeds the y-opening.
  final double u;

  /// Depth (mode `firstExcitedIndex+1`), remapped to [0, 1] — 0 = front,
  /// 1 = furthest back. Feeds the perspective scale.
  final double depth;

  /// √churn normalised to [0, 1] against the window's heaviest commit.
  /// Drives the worldline dot sizing.
  final double churn;

  /// True when the commit had ≥1 file with a real structural coordinate.
  /// False commits render on the horizon axis at their time position,
  /// dimmed — absence is honest.
  final bool covered;

  const WorldlineCoord({
    required this.u,
    required this.depth,
    required this.churn,
    required this.covered,
  });

  static const WorldlineCoord absent =
      WorldlineCoord(u: 0, depth: 0, churn: 0, covered: false);
}

/// The computed field for one window. Plain data — isolate-transferable.
class WorldlineField {
  /// commit hash → structural coordinate. Commits absent from the map (or
  /// present with `covered == false`) sit on the horizon.
  final Map<String, WorldlineCoord> byHash;

  /// Number of files in the co-change graph.
  final int fileCount;

  /// Edge-bearing connected components (each one a Π₀ zero mode).
  final int components;

  /// False when the graph is essentially all ground-state (no excited
  /// modes resolved above the kernel) — the field carries no sky and
  /// every commit stays on the horizon. Honest null.
  final bool hasSky;

  const WorldlineField({
    required this.byHash,
    required this.fileCount,
    required this.components,
    required this.hasSky,
  });

  WorldlineCoord coordFor(String hash) => byHash[hash] ?? WorldlineCoord.absent;

  static const WorldlineField empty = WorldlineField(
    byHash: {},
    fileCount: 0,
    components: 0,
    hasSky: false,
  );
}

// ── cache ───────────────────────────────────────────────────────────────────
// Single-slot per-key cache. History is one repo at a time, so a lone slot
// keyed by repo+window+tip evicts naturally on repo switch, window change,
// or a new HEAD (refresh). The key carries everything the isolate needs; no
// large payload crosses the warm/peek boundary.
final PeekWarmCache<WorldlineField> _fieldCache = PeekWarmCache<WorldlineField>(
  bootstrap: (key) => Isolate.run(() => _buildFromKey(key)),
  matchesKey: (_, __) => true,
  label: 'worldline_field',
);

// Cache-key separator: NUL can't appear in paths, tips, or numbers, so
// keys can never collide. Written as the escape, NEVER a raw NUL byte —
// a raw NUL compiles fine but turns the file "binary" to grep and
// invisible to diff review (the logos_flow incident, repeated here once).
const String _kKeySep = '\u0000';

/// The one identity for a field build. This object is BOTH the cache key
/// (via [key]) and the complete build input (the isolate re-parses the
/// key back into a request via [WorldlineFieldRequest.fromKey], a total
/// round-trip of all three fields). The build reads the revision it logs
/// from [tip] — never from ambient HEAD — so a cached field can never
/// describe different history than its key claims. The original bug
/// class (key promises tip-specificity, builder logs whatever HEAD is
/// current when the isolate finally runs) has no encoding here.
class WorldlineFieldRequest {
  final String repoPath;
  final int window;

  /// The commit hash the strip is displaying as newest. Required and
  /// non-empty: there is no HEAD fallback anywhere downstream.
  final String tip;

  const WorldlineFieldRequest({
    required this.repoPath,
    required this.window,
    required this.tip,
  }) : assert(tip.length > 0, 'a field request must pin its tip');

  String get key => '$repoPath$_kKeySep$window$_kKeySep$tip';

  static WorldlineFieldRequest? fromKey(String raw) {
    final parts = raw.split(_kKeySep);
    if (parts.length != 3) return null;
    final window = int.tryParse(parts[1]);
    if (parts[0].isEmpty || window == null || parts[2].isEmpty) return null;
    return WorldlineFieldRequest(
        repoPath: parts[0], window: window, tip: parts[2]);
  }
}

String worldlineFieldKey(String repoPath, int window, String tip) =>
    WorldlineFieldRequest(repoPath: repoPath, window: window, tip: tip).key;

/// Synchronous peek — returns the field when warm for this exact
/// repo+window+tip, null otherwise. Never triggers a build.
WorldlineField? peekWorldlineField(String repoPath, int window, String tip) =>
    _fieldCache.peek(worldlineFieldKey(repoPath, window, tip));

/// Fire-and-forget warm-up. Idempotent; safe to call every build.
void warmWorldlineField(String repoPath, int window, String tip) =>
    _fieldCache.warm(worldlineFieldKey(repoPath, window, tip));

/// Awaitable load — joins an in-flight build or starts one.
Future<WorldlineField> loadWorldlineField(
        String repoPath, int window, String tip) =>
    _fieldCache.loadOrAwait(worldlineFieldKey(repoPath, window, tip));

// ── isolate entry ────────────────────────────────────────────────────────────
WorldlineField _buildFromKey(String key) {
  final req = WorldlineFieldRequest.fromKey(key);
  if (req == null) {
    throw ArgumentError('malformed worldline field key: $key');
  }
  // NO blanket catch. The distinction is load-bearing:
  //   · "observed nothing" (too few commits, no excited modes) — those are
  //     explicit WorldlineField returns inside _buildField: honest DATA,
  //     correct to cache for this key.
  //   · "failed to observe" (git failure, parse crash, isolate death) —
  //     must PROPAGATE. PeekWarmCache caches nothing on a thrown
  //     bootstrap, the strip's catchError memoizes the failure, and the
  //     next open gesture retries. A catch here converted every transient
  //     fault into an authoritative cached-empty field, silently pinning
  //     the window to the horizon and starving the retry path forever.
  return _buildField(req);
}

/// One commit of the walked window: hash, authored epoch, subject, and the
/// per-file churn map. PUBLIC because this walk is the single source of
/// truth for worldline data — the runtime field build AND the validation
/// harness (tool/worldline_audit.dart) both consume it, so the dataset the
/// audit scores is BY CONSTRUCTION the dataset the app renders. (They
/// drifted once: the audit kept --no-merges after the app dropped it.)
class WorldlineCommitChurn {
  WorldlineCommitChurn(this.hash, this.epoch, this.subject);
  final String hash;
  final int epoch;
  final String subject;

  /// file rel-path → additions + deletions for THIS commit (binary touches
  /// floored to 1 — see the parse loop).
  final Map<String, int> churn = {};
}

WorldlineField _buildField(WorldlineFieldRequest req) {
  final commits = worldlineWindowLog(req);
  if (commits.length < 4) return WorldlineField.empty;

  final built = _buildCochangeGraph(commits);
  final n = built.csr.n;
  if (n < 3) return WorldlineField.empty;

  // Request enough modes to clear the whole kernel + keep two excited.
  final kReq = math
      .min(n, built.components + 2 + _kExcitedBuffer)
      .clamp(2, n);
  final basis = SpectralBasis.fromGraph(built.csr, kReq, nodePaths: built.paths);
  final fe = basis.firstExcitedIndex;
  if (fe + 1 >= basis.k) {
    // All ground-state: no structural plane resolved. Honest null.
    return WorldlineField(
      byHash: const {},
      fileCount: n,
      components: built.components,
      hasSky: false,
    );
  }

  final axisA = fe, axisB = fe + 1;
  final ev = basis.eigenvectors;

  // First pass: raw centroids.
  final rawU = <String, double>{};
  final rawV = <String, double>{};
  final rawChurn = <String, double>{};
  for (final c in commits) {
    var sx = 0.0, sy = 0.0, sw = 0.0, tchurn = 0.0;
    var placed = 0;
    c.churn.forEach((path, churn) {
      final fid = built.pathToId[path];
      if (fid == null || built.degree[fid] == 0) return; // no structural coord
      final w = math.sqrt(churn.toDouble());
      if (w <= 0) return;
      sx += w * ev[axisA * n + fid];
      sy += w * ev[axisB * n + fid];
      sw += w;
      tchurn += churn;
      placed++;
    });
    if (placed == 0 || sw <= 0) continue;
    rawU[c.hash] = sx / sw;
    rawV[c.hash] = sy / sw;
    rawChurn[c.hash] = tchurn;
  }

  if (rawU.isEmpty) {
    return WorldlineField(
      byHash: const {},
      fileCount: n,
      components: built.components,
      hasSky: false,
    );
  }

  // Normalise for render with the robust scaling law (see
  // worldlineRobustAxis): u → median-centred, ±2.5σ_w → ±1, outliers
  // clamp to the rim; depth → the same law shifted to [0, 1] (0.5 =
  // median plane); churn → √-normalised [0, 1]. All stats over covered
  // commits only, computed ONCE here — the painter never re-derives them.
  final uAxis = worldlineRobustAxis(rawU.values.toList());
  final vAxis = worldlineRobustAxis(rawV.values.toList());
  var maxSqrtChurn = 1e-9;
  rawChurn.forEach((_, v) {
    final s = math.sqrt(v);
    if (s > maxSqrtChurn) maxSqrtChurn = s;
  });

  final byHash = <String, WorldlineCoord>{};
  for (final hash in rawU.keys) {
    byHash[hash] = WorldlineCoord(
      u: ((rawU[hash]! - uAxis.center) / uAxis.halfRange).clamp(-1.0, 1.0),
      depth: (0.5 + (rawV[hash]! - vAxis.center) / (2 * vAxis.halfRange))
          .clamp(0.0, 1.0),
      churn: (math.sqrt(rawChurn[hash]!) / maxSqrtChurn).clamp(0.0, 1.0),
      covered: true,
    );
  }

  return WorldlineField(
    byHash: byHash,
    fileCount: n,
    components: built.components,
    hasSky: true,
  );
}

/// `git log --numstat --no-merges` over the window → per-commit churn.
/// Walk the request's window: newest-first commits with per-file churn.
/// PUBLIC single source of truth (see [WorldlineCommitChurn]) — the app's
/// field build and the audit harness must never parse git separately.
List<WorldlineCommitChurn> worldlineWindowLog(WorldlineFieldRequest req) {
  // %x01 marks a commit header; fields unit-separated (%x1f).
  const fmt = 'format:%x01%H%x1f%ct%x1f%s';
  // The revision is ALWAYS the request's pinned tip — never ambient HEAD —
  // so the walked window is exactly the history the cache key names, no
  // matter when the isolate actually runs. NO --no-merges: the field's
  // window aligns commit-for-commit with the strip's visible list; merge
  // commits emit no numstat lines and therefore land as covered=false
  // (horizon dots) — honest, and the counts stay aligned.
  final r = Process.runSync('git', [
    '-C', req.repoPath, 'log', req.tip, '-n', '${req.window}', '--numstat',
    '--format=$fmt',
  ]);
  // Nonzero exit = FAILED observation (repo gone, bad tip, git broken) and
  // must throw so callers retry instead of caching a lie. Empty output on
  // exit 0 is honest data (a genuinely tiny window) and returns normally.
  if (r.exitCode != 0) {
    throw StateError(
        'git log failed (${r.exitCode}) for ${req.tip}: ${r.stderr}');
  }
  final commits = <WorldlineCommitChurn>[];
  WorldlineCommitChurn? cur;
  for (final raw in const LineSplitter().convert(r.stdout as String)) {
    if (raw.isEmpty) continue;
    if (raw.codeUnitAt(0) == 0x01) {
      final parts = raw.substring(1).split('\x1f');
      if (parts.length < 3) continue;
      cur = WorldlineCommitChurn(
          parts[0], int.tryParse(parts[1]) ?? 0, parts[2]);
      commits.add(cur);
      continue;
    }
    if (cur == null) continue;
    final f = raw.split('\t');
    if (f.length < 3) continue;
    final adds = int.tryParse(f[0]) ?? 0;
    final dels = int.tryParse(f[1]) ?? 0;
    final path = _renameTarget(f.sublist(2).join('\t'));
    if (path.isEmpty) continue;
    // Binary rows report `-  -  path`: no line counts exist, but the touch
    // is real history. Committed law: a touched file carries at least one
    // line-equivalent of churn. Without the floor, binary-only commits had
    // zero total weight and silently fell to the horizon as "absent" —
    // an asset-swap commit is a real structural event, not a non-event.
    var lineChurn = adds + dels;
    if (lineChurn == 0 && (f[0] == '-' || f[1] == '-')) lineChurn = 1;
    cur.churn[path] = (cur.churn[path] ?? 0) + lineChurn;
  }
  return commits;
}

/// numstat rename forms `old => new`, `dir/{old => new}/file` → post path.
String _renameTarget(String p) {
  if (!p.contains('=>')) return p.trim();
  final brace = RegExp(r'\{([^{}]*)=>([^{}]*)\}');
  var s = p;
  while (brace.hasMatch(s)) {
    s = s.replaceFirstMapped(brace, (m) => m.group(2)!.trim());
  }
  if (s.contains('=>')) s = s.split('=>').last;
  return s.replaceAll('//', '/').trim();
}

class _UF {
  _UF(int n) : _p = List<int>.generate(n, (i) => i);
  final List<int> _p;
  int find(int x) {
    while (_p[x] != x) {
      _p[x] = _p[_p[x]];
      x = _p[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) _p[ra] = rb;
  }
}

class _Graph {
  _Graph(this.csr, this.paths, this.pathToId, this.degree, this.components);
  final CsrGraph csr;
  final List<String> paths;
  final Map<String, int> pathToId;
  final List<int> degree;
  final int components;
}

/// File×file co-change graph — Jaccard edges, top-K=16 sparsify. Identical
/// to the audit's `_buildCochangeGraph`.
_Graph _buildCochangeGraph(List<WorldlineCommitChurn> commits) {
  final fileSet = <String>{};
  for (final c in commits) {
    fileSet.addAll(c.churn.keys);
  }
  final paths = fileSet.toList()..sort();
  final id = {for (var i = 0; i < paths.length; i++) paths[i]: i};
  final n = paths.length;
  if (n == 0) {
    return _Graph(
        CsrGraph.fromRawEdges(n: 0, edgesPerNode: const []), paths, id, const [], 0);
  }

  final touches = List<int>.filled(n, 0);
  for (final c in commits) {
    for (final p in c.churn.keys) {
      touches[id[p]!]++;
    }
  }

  final shared = <int, Map<int, int>>{};
  for (final c in commits) {
    final ids = c.churn.keys.map((p) => id[p]!).toList()..sort();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = ids[i], b = ids[j];
        (shared[a] ??= {})[b] = ((shared[a]![b]) ?? 0) + 1;
      }
    }
  }

  final edges = List<List<(int, double)>>.generate(n, (_) => []);
  shared.forEach((a, row) {
    row.forEach((b, s) {
      final denom = touches[a] + touches[b] - s;
      if (denom <= 0) return;
      final w = s / denom;
      if (w <= 0) return;
      edges[a].add((b, w));
      edges[b].add((a, w));
    });
  });

  for (var i = 0; i < n; i++) {
    if (edges[i].length <= _kTopK) continue;
    edges[i].sort((x, y) => y.$2.compareTo(x.$2));
    edges[i] = edges[i].sublist(0, _kTopK);
  }
  final adj = List<Map<int, double>>.generate(n, (_) => {});
  for (var i = 0; i < n; i++) {
    for (final (j, w) in edges[i]) {
      adj[i][j] = w;
      adj[j][i] = w;
    }
  }
  final finalEdges = List<List<(int, double)>>.generate(n, (i) => [
        for (final e in adj[i].entries) (e.key, e.value),
      ]);
  final degree = [for (var i = 0; i < n; i++) adj[i].length];

  final uf = _UF(n);
  for (var i = 0; i < n; i++) {
    for (final j in adj[i].keys) {
      uf.union(i, j);
    }
  }
  final edgeComps = <int>{};
  for (var i = 0; i < n; i++) {
    if (degree[i] == 0) continue;
    edgeComps.add(uf.find(i));
  }

  final csr = CsrGraph.fromRawEdges(n: n, edgesPerNode: finalEdges);
  return _Graph(csr, paths, id, degree, edgeComps.length);
}
