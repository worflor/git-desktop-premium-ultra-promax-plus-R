// tool/worldline_audit.dart — validation harness for "Worldline".
//
// PREMISE UNDER TEST: every commit can be assigned structural coordinates —
// the churn-weighted centroid of its touched files in the repo's spectral
// eigen-plane (the first TWO non-trivial Laplacian eigenvectors of the
// co-change graph, with ALL λ=0 equilibrium/popularity modes projected out,
// the Π₀ house law). If the premise holds, the sequence of per-commit
// centroids over time forms a "worldline" whose geometry narrates real
// history: eras of work in one subsystem form spatially-coherent runs,
// architectural pivots appear as bends/jumps, and the trajectory is NOT
// smeared onto hub files.
//
// This produces NO app UI — a terminal report + a self-contained SVG dump.
//
// It reuses the PRODUCTION spectral engine (this is where its credibility
// comes from). Exact APIs used, all from the headless-safe
// package:git_desktop/backend/logos_core.dart:
//   * CsrGraph.fromRawEdges(n:, edgesPerNode:)  — the engine's own graph
//     constructor (computes D^{-1/2}, fuses the normalised Laplacian). We
//     feed it file×file co-change edges (Jaccard over commit-sets + top-K
//     sparsify), mirroring spectral_spacetime.dart buildCommitGraph's
//     inverted-index pair walk — but for FILES, not commits.
//   * SpectralBasis.fromGraph(graph, k)         — wraps lanczosSmallEigenpairs,
//     the deflated folded-spectrum Lanczos with exact closed-form kernel
//     injection (the "spectrum honesty" work). It computes the exact zero-mode
//     count via union-find over edge-bearing components, so fragmentation is
//     handled the way the engine does.
//   * basis.firstExcitedIndex / basis.kernelDim — the Π₀ discipline: the sky
//     plane is eigenvectors [firstExcitedIndex, firstExcitedIndex+1], i.e.
//     the first two modes ABOVE the entire zero-mode subspace (not a
//     hardcoded "skip index 0", which only handles a single component).
//
// The LogosGit production path (collectLogosGitStats → LogosGit.buildFromStats)
// pulls Flutter (git.dart → diagnostics → package:flutter), so — exactly like
// tool/axis_audit.dart — we shell out to `git log` ourselves and build the
// graph via the headless CsrGraph primitive. Same math, no Flutter.
//
// Usage:
//   dart run tool/worldline_audit.dart [repoPath] [N]     (defaults: repo=., N=300)
//   dart run tool/worldline_audit.dart selftest           (synthetic sanity check)

import 'dart:io';
import 'dart:math' as math;

import 'package:git_desktop/backend/logos_core.dart'
    show CsrGraph, SpectralBasis, SpectralGroundSpace;
import 'package:git_desktop/features/history/worldline_field.dart'
    show WorldlineCommitChurn, WorldlineFieldRequest, worldlineWindowLog;

// ── COMMITTED LAWS (the only tunables besides N and repoPath) ───────────────
//
// _kTopK: top-K strongest co-change neighbours kept per file. 16 is the
//   engine's own sparsification constant (spectral_spacetime.dart
//   buildCommitGraph topK default = 16); reusing it keeps the graph density
//   identical to production and bounds clique blow-up from mega-commits.
const int _kTopK = 16;
//
// _kExcitedBuffer: extra excited modes requested beyond the two we keep.
//   Deflated Lanczos resolves the LOWEST excited modes most accurately when a
//   few extra are requested, so we ask for (components + buffer) modes and use
//   the first two above the kernel. 6 is a safe convergence margin.
const int _kExcitedBuffer = 6;
//
// (Era segmentation uses no fixed constant: the run radius is the trajectory's
//  own 1σ RMS spread — see _detectRuns. Parameter-free by construction.)

// ─────────────────────────────────────────────────────────────────────────

/// THE WALK IS SHARED, NOT DUPLICATED. The harness consumes the exact
/// production walk+parse (`worldlineWindowLog` in worldline_field.dart) so
/// the dataset it scores is BY CONSTRUCTION the dataset the app renders —
/// merge policy, binary-churn floor, rename resolution, tip pinning, all of
/// it. This file once kept its own `git log --no-merges` copy and silently
/// drifted from the runtime the day the app dropped the flag; that class of
/// drift is now unrepresentable. Chronological (oldest→newest) for the
/// trajectory math; the runtime walk returns newest-first.
List<WorldlineCommitChurn> _walkWindow(String repo, int n) {
  final rp = Process.runSync('git', ['-C', repo, 'rev-parse', 'HEAD']);
  if (rp.exitCode != 0) {
    stderr.writeln('git rev-parse HEAD failed: ${rp.stderr}');
    exit(1);
  }
  final tip = (rp.stdout as String).trim();
  final List<WorldlineCommitChurn> commits;
  try {
    commits = worldlineWindowLog(
        WorldlineFieldRequest(repoPath: repo, window: n, tip: tip));
  } on StateError catch (e) {
    stderr.writeln('shared walk failed: ${e.message}');
    exit(1);
  }
  if (commits.isEmpty) {
    stderr.writeln('git log produced no commits (repo=$repo tip=$tip)');
    exit(1);
  }
  return commits.reversed.toList();
}

/// Subsystem label. Monorepo paths are root-relative, so the FIRST segment is
/// nearly constant ("apps"). Use a fixed informative depth (4 segments) so the
/// real subsystem shows through: apps/desktop-flutter/lib/backend,
/// experiments/logos_bench, docs/architecture, … A common prefix shared by the
/// whole run set is stripped at print time for readability.
String _subsys(String path) {
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.length <= 1) return '(root)';
  final depth = math.min(4, segs.length - 1);
  return segs.take(depth).join('/');
}

/// Remove the leading path segments shared by every label in [labels].
String _stripCommon(String label, List<String> commonSegs) {
  final segs = label.split('/');
  var i = 0;
  while (i < commonSegs.length &&
      i < segs.length &&
      segs[i] == commonSegs[i]) {
    i++;
  }
  final rest = segs.skip(i).join('/');
  return rest.isEmpty ? label : rest;
}

List<String> _commonSegs(Iterable<String> labels) {
  final lists = labels.map((l) => l.split('/')).toList();
  if (lists.isEmpty) return const [];
  final common = <String>[];
  for (var i = 0;; i++) {
    String? seg;
    for (final l in lists) {
      if (i >= l.length) return common;
      seg ??= l[i];
      if (l[i] != seg) return common;
    }
    // don't strip the entire label away — stop one short if needed.
    if (lists.any((l) => l.length <= i + 1)) return common;
    common.add(seg!);
  }
}

// ── union-find (for exact component count / fragmentation, engine-style) ────
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
  _Graph(this.csr, this.paths, this.pathToId, this.degree, this.components,
      this.largestComp);
  final CsrGraph csr;
  final List<String> paths;
  final Map<String, int> pathToId;
  final List<int> degree; // combinatorial degree (# co-change neighbours)
  final int components; // # edge-bearing connected components (each = a Π₀ mode)
  final int largestComp;
}

/// Build the file×file co-change graph from a commit window.
/// Edge weight = Jaccard(commitSet_i, commitSet_j) = shared / (deg_i+deg_j-shared)
///   — the same set-overlap normalisation buildCommitGraph uses for commits;
///   it intrinsically down-weights hub files (large commit-sets → large
///   denominators). Then top-K sparsify per node (engine convention).
_Graph _buildCochangeGraph(List<WorldlineCommitChurn> commits) {
  // Assign stable ids to every file that appears (sorted for determinism,
  // exactly like LogosGit.buildFromStats).
  final fileSet = <String>{};
  for (final c in commits) {
    fileSet.addAll(c.churn.keys);
  }
  final paths = fileSet.toList()..sort();
  final id = {for (var i = 0; i < paths.length; i++) paths[i]: i};
  final n = paths.length;

  // commit-count per file (Jaccard denominator terms).
  final touches = List<int>.filled(n, 0);
  for (final c in commits) {
    for (final p in c.churn.keys) {
      touches[id[p]!]++;
    }
  }

  // shared-commit counts per unordered file pair (inverted-index pair walk).
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

  // Jaccard-weighted symmetric edges.
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

  // top-K per node by weight.
  for (var i = 0; i < n; i++) {
    if (edges[i].length <= _kTopK) continue;
    edges[i].sort((x, y) => y.$2.compareTo(x.$2));
    edges[i] = edges[i].sublist(0, _kTopK);
  }
  // Re-symmetrise: top-K may drop one direction of a pair; keep the union so
  // CsrGraph.fromRawEdges' symmetry contract holds.
  final adj = List<Map<int, double>>.generate(n, (_) => {});
  for (var i = 0; i < n; i++) {
    for (final (j, w) in edges[i]) {
      adj[i][j] = w;
      adj[j][i] = w;
    }
  }
  final finalEdges =
      List<List<(int, double)>>.generate(n, (i) => [
            for (final e in adj[i].entries) (e.key, e.value),
          ]);

  final degree = [for (var i = 0; i < n; i++) adj[i].length];

  // components over edge-bearing nodes (union-find, engine-style).
  final uf = _UF(n);
  for (var i = 0; i < n; i++) {
    for (final j in adj[i].keys) {
      uf.union(i, j);
    }
  }
  final compSize = <int, int>{};
  var edgeComps = <int>{};
  for (var i = 0; i < n; i++) {
    if (degree[i] == 0) continue;
    final r = uf.find(i);
    edgeComps.add(r);
    compSize[r] = (compSize[r] ?? 0) + 1;
  }
  final largest =
      compSize.values.isEmpty ? 0 : compSize.values.reduce(math.max);

  final csr = CsrGraph.fromRawEdges(n: n, edgesPerNode: finalEdges);
  return _Graph(csr, paths, id, degree, edgeComps.length, largest);
}

// ── centroid + trajectory ──────────────────────────────────────────────────
class _Point {
  _Point(this.x, this.y);
  double x, y;
}

class _Placed {
  _Placed(this.commit, this.pt, this.churn, this.domDir);
  final WorldlineCommitChurn commit;
  final _Point pt;
  final double churn; // total churn of placeable files
  final String domDir;
}

/// Churn-weighted centroid of a commit's placeable files in a 2-mode sky.
/// weight = sqrt(additions+deletions) — the house heavy-tail damping.
/// axisA/axisB are eigenvector row indices into basis.eigenvectors.
({_Point? pt, int placed, int skipped, double churn, String domDir})
    _centroid(WorldlineCommitChurn c, _Graph g, SpectralBasis basis, int axisA, int axisB) {
  final ev = basis.eigenvectors;
  final n = basis.n;
  var sx = 0.0, sy = 0.0, sw = 0.0, tchurn = 0.0;
  var placed = 0, skipped = 0;
  final dirMass = <String, double>{};
  c.churn.forEach((path, churn) {
    final fid = g.pathToId[path];
    if (fid == null || g.degree[fid] == 0) {
      skipped++;
      return; // absent from graph OR isolated (no structural coordinate)
    }
    final w = math.sqrt(churn.toDouble());
    if (w <= 0) {
      skipped++;
      return;
    }
    sx += w * ev[axisA * n + fid];
    sy += w * ev[axisB * n + fid];
    sw += w;
    tchurn += churn;
    placed++;
    dirMass[_subsys(path)] = (dirMass[_subsys(path)] ?? 0) + w;
  });
  if (placed == 0 || sw <= 0) {
    return (pt: null, placed: 0, skipped: skipped, churn: 0, domDir: '(none)');
  }
  final dom = dirMass.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  return (
    pt: _Point(sx / sw, sy / sw),
    placed: placed,
    skipped: skipped,
    churn: tchurn,
    domDir: dom
  );
}

double _dist(_Point a, _Point b) =>
    math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

// ── run/era detection ───────────────────────────────────────────────────────
class _Run {
  _Run(this.start);
  int start;
  int end = 0;
  final List<_Placed> members = [];
}

/// Era = a maximal run of consecutive commits that stay within radius R of the
/// run's RUNNING centroid. R = the trajectory's RMS spread (1σ) — THE
/// characteristic scale of the whole cloud, so this is parameter-free: a
/// commit landing more than one standard deviation from where the current era
/// has been sitting is, by construction, in a different neighbourhood. Using
/// the running centroid (not a fixed anchor) lets an era drift slowly without
/// spuriously splitting; a genuine architectural pivot jumps >1σ and cleaves.
List<_Run> _detectRuns(List<_Placed> traj) {
  if (traj.isEmpty) return [];
  final r = math.sqrt(_cov(traj.map((t) => t.pt).toList()).let((c) => c.vx + c.vy));
  final runs = <_Run>[];
  var cur = _Run(0)..members.add(traj[0]);
  var sx = traj[0].pt.x, sy = traj[0].pt.y;
  for (var i = 1; i < traj.length; i++) {
    final cx = sx / cur.members.length, cy = sy / cur.members.length;
    final d = _dist(traj[i].pt, _Point(cx, cy));
    if (d > r && r > 0) {
      cur.end = i - 1;
      runs.add(cur);
      cur = _Run(i);
      sx = 0;
      sy = 0;
    }
    cur.members.add(traj[i]);
    sx += traj[i].pt.x;
    sy += traj[i].pt.y;
  }
  cur.end = traj.length - 1;
  runs.add(cur);
  return runs;
}

String _runDomDir(_Run r) {
  final mass = <String, double>{};
  for (final p in r.members) {
    mass[p.domDir] = (mass[p.domDir] ?? 0) + p.churn;
  }
  if (mass.isEmpty) return '(none)';
  return mass.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

// ── variance helpers (hub-smear control) ─────────────────────────────────────
({double vx, double vy, _Point mean}) _cov(List<_Point> pts) {
  if (pts.isEmpty) return (vx: 0, vy: 0, mean: _Point(0, 0));
  var mx = 0.0, my = 0.0;
  for (final p in pts) {
    mx += p.x;
    my += p.y;
  }
  mx /= pts.length;
  my /= pts.length;
  var vx = 0.0, vy = 0.0;
  for (final p in pts) {
    vx += (p.x - mx) * (p.x - mx);
    vy += (p.y - my) * (p.y - my);
  }
  return (vx: vx / pts.length, vy: vy / pts.length, mean: _Point(mx, my));
}

void main(List<String> args) {
  if (args.isNotEmpty && args[0] == 'selftest') {
    _selftest();
    return;
  }
  final repo = args.isNotEmpty ? args[0] : Directory.current.path;
  final n = args.length > 1 ? (int.tryParse(args[1]) ?? 300) : 300;

  stderr.writeln('worldline_audit: repo=$repo N=$n');
  final commits = _walkWindow(repo, n);
  if (commits.length < 8) {
    stderr.writeln('too few commits (${commits.length}) to test premise');
    exit(1);
  }
  final g = _buildCochangeGraph(commits);
  stderr.writeln('co-change graph: ${g.csr.n} files, '
      '${g.components} edge-bearing components (each a Π₀ zero mode), '
      'largest component ${g.largestComp} files');

  // Request enough modes to clear the entire kernel + keep two excited.
  final kReq =
      math.min(g.csr.n, g.components + 2 + _kExcitedBuffer).clamp(2, g.csr.n);
  final basis = SpectralBasis.fromGraph(g.csr, kReq, nodePaths: g.paths);
  final fe = basis.firstExcitedIndex;
  stderr.writeln('eigenbasis: k=${basis.k}, kernelDim=${basis.kernelDim} '
      '(zero modes projected out), firstExcitedIndex=$fe');
  if (fe + 1 >= basis.k) {
    stderr.writeln('FATAL: not enough excited modes resolved above the kernel '
        '(fe=$fe, k=${basis.k}); the co-change graph is essentially all '
        'ground state — premise cannot even be tested here.');
    exit(1);
  }

  // Π₀-projected sky = first two modes ABOVE the whole zero-mode subspace.
  final axisA = fe, axisB = fe + 1;
  // Hub-smear control = the LITERAL "forgot to project out zero modes" sky:
  // the first two eigenvectors AS EMITTED (indices 0,1). On a connected repo
  // index 0 is the ground/popularity mode (value ∝ √degree); on a fragmented
  // repo (kernelDim≥2) BOTH are zero modes, so the un-projected trajectory can
  // carry no structural signal at all. This is the honest null.
  const rawA = 0;
  const rawB = 1;

  final traj = <_Placed>[];
  final rawPts = <_Point>[];
  var totalSkipped = 0, commitsSkipped = 0, totalFilesTouched = 0;
  for (final c in commits) {
    totalFilesTouched += c.churn.length;
    final r = _centroid(c, g, basis, axisA, axisB);
    totalSkipped += r.skipped;
    if (r.pt == null) {
      commitsSkipped++;
      continue;
    }
    traj.add(_Placed(c, r.pt!, r.churn, r.domDir));
    final rr = _centroid(c, g, basis, rawA, rawB);
    rawPts.add(rr.pt ?? _Point(0, 0));
  }

  if (traj.length < 4) {
    stderr.writeln('only ${traj.length} placeable commits — premise fails for '
        'lack of coverage.');
    exit(1);
  }

  final runs = _detectRuns(traj);

  // ── TERMINAL REPORT ───────────────────────────────────────────────────────
  final out = StringBuffer();
  out.writeln('');
  out.writeln('══════════════════════ WORLDLINE AUDIT ══════════════════════');
  out.writeln('repo: $repo');
  out.writeln('commits analysed (chronological): ${commits.length}');
  out.writeln('co-change graph: ${g.csr.n} files, ${g.components} components, '
      'largest ${g.largestComp}');
  out.writeln('eigenbasis: k=${basis.k}, kernelDim=${basis.kernelDim}, '
      'sky = modes [$axisA,$axisB] (Π₀: all zero modes projected out)');
  out.writeln('');

  // Coverage.
  out.writeln('── COVERAGE ──');
  out.writeln('placeable commits:      ${traj.length}/${commits.length}');
  out.writeln('commits skipped (no in-graph files): $commitsSkipped');
  out.writeln('file-touches skipped (absent/isolated): $totalSkipped'
      ' / $totalFilesTouched');
  out.writeln('');

  // Era report. Run law: within 1σ of the running centroid (see _detectRuns).
  final runDirs = [for (final r in runs) _runDomDir(r)];
  final common = _commonSegs(runDirs.where((d) => d != '(root)'));
  final prefixNote = common.isEmpty ? '' : ' (dirs relative to ${common.join('/')}/)';
  out.writeln('── ERAS (run = consecutive commits within 1σ of the running '
      'centroid) ──');
  out.writeln('${runs.length} eras detected across ${traj.length} commits'
      '$prefixNote');
  out.writeln('');
  for (var i = 0; i < runs.length; i++) {
    final r = runs[i];
    final cen = _cov(r.members.map((m) => m.pt).toList()).mean;
    final first = r.members.first.commit;
    final last = r.members.last.commit;
    final dir = _stripCommon(runDirs[i], common);
    out.writeln('  era ${(i + 1).toString().padLeft(2)}: '
        '${r.members.length.toString().padLeft(3)} commits  '
        'dir=${dir.padRight(22)} '
        'centroid=(${cen.x.toStringAsFixed(3)}, ${cen.y.toStringAsFixed(3)})');
    out.writeln('           ${_short(first.subject)}');
    if (r.members.length > 1) {
      out.writeln('        …→ ${_short(last.subject)}');
    }
  }
  out.writeln('');

  // ── HUB-SMEAR CONTROL ─────────────────────────────────────────────────────
  // Compare the Π₀-projected sky against the UN-projected sky (modes 0,1 as
  // emitted — the zero-mode subspace). The structural variance the projection
  // BUYS is projVar; whatever the raw sky retains is popularity/component
  // bookkeeping. Effective 1-D collapse = rawVar concentrated on one axis.
  final projCov = _cov(traj.map((t) => t.pt).toList());
  final rawCov = _cov(rawPts);
  final projVar = projCov.vx + projCov.vy;
  final rawVar = rawCov.vx + rawCov.vy;
  final rawMajor = math.max(rawCov.vx, rawCov.vy);
  final rawCollapse = rawVar > 0 ? rawMajor / rawVar : 1.0; // →1 = 1-D line

  // hub file (max combinatorial degree) and how near commits sit to it.
  var hub = 0;
  for (var i = 1; i < g.degree.length; i++) {
    if (g.degree[i] > g.degree[hub]) hub = i;
  }
  final ev = basis.eigenvectors;
  final nn = basis.n;
  final hubProj = _Point(ev[axisA * nn + hub], ev[axisB * nn + hub]);
  final hubRaw = _Point(ev[rawA * nn + hub], ev[rawB * nn + hub]);
  // normalise each sky by its own RMS spread so distances are comparable.
  final projRms = math.sqrt(projVar);
  final rawRms = math.sqrt(rawVar);
  double meanHubDist(List<_Point> pts, _Point h, double rms) {
    if (rms <= 0) return 0;
    var s = 0.0;
    for (final p in pts) {
      s += _dist(p, h) / rms;
    }
    return s / pts.length;
  }
  final projHubDist =
      meanHubDist(traj.map((t) => t.pt).toList(), hubProj, projRms);
  final rawHubDist = meanHubDist(rawPts, hubRaw, rawRms);
  final hubExpansion = rawHubDist > 0 ? projHubDist / rawHubDist : double.infinity;

  out.writeln('── HUB-SMEAR CONTROL (does Π₀ matter?) ──');
  out.writeln('hub file (max co-change degree=${g.degree[hub]}): '
      '${g.paths[hub]}');
  out.writeln('un-projected sky = eigenvectors[0,1] (the zero-mode subspace: '
      '${basis.kernelDim} ground modes).');
  out.writeln('  raw-sky variance collapse onto its major axis: '
      '${(rawCollapse * 100).toStringAsFixed(1)}%  '
      '(→100% = a 1-D popularity line, no structural plane)');
  out.writeln('mean commit→hub distance (normalised by each sky\'s RMS):');
  out.writeln('  un-projected sky : ${rawHubDist.toStringAsFixed(3)}  '
      '(smaller = centroids pulled onto the hub)');
  out.writeln('  Π₀-projected sky : ${projHubDist.toStringAsFixed(3)}');
  out.writeln('sky spread (RMS): projected ${projRms.toStringAsExponential(2)}'
      '   un-projected ${rawRms.toStringAsExponential(2)}');
  out.writeln('');

  // ── VERDICT ───────────────────────────────────────────────────────────────
  // Separation test: are the runs distinguishable eras, or one smeared blob?
  // Between-run centroid spread vs within-run spread (a Fisher-style ratio).
  final runCentroids = <_Point>[];
  var withinVar = 0.0, withinCount = 0;
  for (final r in runs) {
    final c = _cov(r.members.map((m) => m.pt).toList());
    runCentroids.add(c.mean);
    withinVar += (c.vx + c.vy) * r.members.length;
    withinCount += r.members.length;
  }
  withinVar = withinCount > 0 ? withinVar / withinCount : 0;
  final betweenVar = _cov(runCentroids).let((c) => c.vx + c.vy);
  final separation = withinVar > 0 ? betweenVar / withinVar : double.infinity;

  // How many DISTINCT dominant dirs across multi-commit eras (subsystem id)?
  final multi = runs.where((r) => r.members.length >= 2).toList();
  final distinctDirs = {for (final r in multi) _runDomDir(r)};

  out.writeln('── VERDICT ──');
  out.writeln('eras: ${runs.length} (${multi.length} multi-commit)   '
      'distinct subsystems across multi-commit eras: ${distinctDirs.length}');
  out.writeln('between-era / within-era variance ratio: '
      '${separation.toStringAsFixed(2)}  '
      '(>1 = eras occupy distinct neighbourhoods; ≤1 = smeared blob)');
  out.writeln('');

  // Premise A — the worldline narrates real, separable history.
  final worldlineHolds = separation > 1.0 &&
      distinctDirs.length >= 2 &&
      commitsSkipped < traj.length * 0.5 &&
      projRms > 0;
  // Premise B — Π₀ is load-bearing (un-projected sky collapses to popularity /
  // pulls centroids onto the hub; projection opens a real structural plane).
  final piZeroMatters = rawCollapse > 0.85 || hubExpansion > 1.5;

  out.writeln('[A] WORLDLINE GEOMETRY: ${worldlineHolds ? "HOLDS" : "FAILS"}');
  if (worldlineHolds) {
    out.writeln('    Consecutive commits form spatially-coherent runs; distinct '
        'eras occupy distinct\n    neighbourhoods (between/within ratio '
        '${separation.toStringAsFixed(1)} > 1) and ${distinctDirs.length} '
        'multi-commit eras are dominated by\n    different subsystems. The '
        'trajectory is NOT a single smeared blob.');
  } else {
    out.writeln('    ${separation <= 1.0 ? "Eras do not separate (ratio "
        "${separation.toStringAsFixed(2)} ≤ 1 — one cloud). " : ""}'
        '${distinctDirs.length < 2 ? "Eras are not subsystem-distinct. " : ""}'
        'The sky is mush.');
  }
  out.writeln('');
  out.writeln('[B] Π₀ NECESSITY: ${piZeroMatters ? "DEMONSTRATED" : "WEAK on this repo"}');
  if (piZeroMatters) {
    out.writeln('    Without projecting out the zero modes the sky collapses '
        '(${(rawCollapse * 100).toStringAsFixed(0)}% of raw variance on one '
        'axis =\n    a 1-D popularity line) and commit centroids sit right on '
        'the hub (mean hub-distance\n    ${rawHubDist.toStringAsFixed(2)}σ). '
        'Projecting the zero modes out pushes centroids '
        '${hubExpansion.toStringAsFixed(1)}× further from the\n    hub '
        '(${projHubDist.toStringAsFixed(2)}σ) and opens a genuine 2-D '
        'structural plane. Π₀ is load-bearing.');
  } else {
    out.writeln('    The un-projected sky did NOT collapse hard here '
        '(major-axis share ${(rawCollapse * 100).toStringAsFixed(0)}%, hub '
        'expansion\n    ${hubExpansion.toStringAsFixed(1)}×). Sqrt-churn '
        'centroids already average out popularity, so Π₀ is\n    correct '
        'discipline but not the dramatic difference-maker on THIS history. '
        'Honest null.');
  }
  out.writeln('');
  out.writeln(worldlineHolds
      ? 'BOTTOM LINE: Worldline earned its next phase — the trajectory tells a '
          'true story.'
      : 'BOTTOM LINE: premise not met — do NOT build Worldline on this signal.');
  out.writeln('═════════════════════════════════════════════════════════════');

  stdout.write(out.toString());

  // ── SVG DUMP ────────────────────────────────────────────────────────────────
  final svgPath = _svgSibling();
  File(svgPath).writeAsStringSync(_buildSvg(traj));
  stdout.writeln('\nSVG scatter written → $svgPath');
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

String _short(String s, [int max = 60]) {
  final t = s.replaceAll('\n', ' ').trim();
  return t.length <= max ? t : '${t.substring(0, max - 1)}…';
}

String _svgSibling() {
  final self = Platform.script.toFilePath();
  final dir = File(self).parent.path;
  return '$dir${Platform.pathSeparator}worldline_audit.svg';
}

String _buildSvg(List<_Placed> traj) {
  const w = 1200.0, h = 820.0, pad = 60.0;
  var minx = double.infinity,
      maxx = -double.infinity,
      miny = double.infinity,
      maxy = -double.infinity;
  for (final p in traj) {
    minx = math.min(minx, p.pt.x);
    maxx = math.max(maxx, p.pt.x);
    miny = math.min(miny, p.pt.y);
    maxy = math.max(maxy, p.pt.y);
  }
  final rx = (maxx - minx).abs() < 1e-12 ? 1.0 : maxx - minx;
  final ry = (maxy - miny).abs() < 1e-12 ? 1.0 : maxy - miny;
  double sx(double x) => pad + (x - minx) / rx * (w - 2 * pad);
  double sy(double y) => h - pad - (y - miny) / ry * (h - 2 * pad);

  var maxChurn = 1.0;
  for (final p in traj) {
    maxChurn = math.max(maxChurn, p.churn);
  }

  final b = StringBuffer();
  b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  b.writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${w.toInt()}" '
      'height="${h.toInt()}" viewBox="0 0 ${w.toInt()} ${h.toInt()}" '
      'font-family="monospace">');
  b.writeln('<rect width="100%" height="100%" fill="#0a0c12"/>');
  b.writeln('<text x="$pad" y="34" fill="#c8d0e0" font-size="20">Worldline — '
      'churn-weighted commit centroids in the Π₀ co-change eigen-plane'
      '</text>');
  b.writeln('<text x="$pad" y="56" fill="#5a6a8a" font-size="13">oldest (cold) '
      '→ newest (hot); dot radius = √churn; ${traj.length} commits</text>');

  // polyline (thin, faint) connecting consecutive commits.
  final pts = traj
      .map((p) => '${sx(p.pt.x).toStringAsFixed(1)},'
          '${sy(p.pt.y).toStringAsFixed(1)}')
      .join(' ');
  b.writeln('<polyline points="$pts" fill="none" stroke="#39507a" '
      'stroke-width="1.1" stroke-opacity="0.5"/>');

  // dots coloured by age (oldest cold/faint → newest hot/bright).
  final labels = <_Placed>[...traj]
    ..sort((a, c) => c.churn.compareTo(a.churn));
  final labelSet = labels.take(6).toSet();
  for (var i = 0; i < traj.length; i++) {
    final p = traj[i];
    final t = traj.length == 1 ? 1.0 : i / (traj.length - 1);
    final col = _ageColor(t);
    final r = 2.0 + 9.0 * math.sqrt(p.churn / maxChurn);
    final op = (0.35 + 0.6 * t).toStringAsFixed(2);
    b.writeln('<circle cx="${sx(p.pt.x).toStringAsFixed(1)}" '
        'cy="${sy(p.pt.y).toStringAsFixed(1)}" r="${r.toStringAsFixed(1)}" '
        'fill="$col" fill-opacity="$op"/>');
  }
  // labels for the largest dots.
  for (final p in labelSet) {
    b.writeln('<text x="${(sx(p.pt.x) + 8).toStringAsFixed(1)}" '
        'y="${(sy(p.pt.y) - 6).toStringAsFixed(1)}" fill="#e8ecf4" '
        'font-size="11">${_xml(_short(p.commit.subject, 34))}</text>');
  }
  b.writeln('</svg>');
  return b.toString();
}

String _ageColor(double t) {
  // cold indigo (old) → hot amber/white (new).
  final r = (40 + 215 * t).round().clamp(0, 255);
  final g = (70 + 130 * t).round().clamp(0, 255);
  final bl = (150 - 90 * t).round().clamp(0, 255);
  return 'rgb($r,$g,$bl)';
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

// ── SYNTHETIC SANITY CHECK (graph-physics intuitions flip; verify first) ────
void _selftest() {
  stdout.writeln('── SELFTEST: path graph ──');
  // A path 0-1-2-...-9. Fiedler vector should be monotone along the path
  // (the classic 1-D embedding). Verifies Π₀ + first-excited extraction.
  const np = 10;
  final pe = List<List<(int, double)>>.generate(np, (_) => []);
  for (var i = 0; i + 1 < np; i++) {
    pe[i].add((i + 1, 1.0));
    pe[i + 1].add((i, 1.0));
  }
  final pg = CsrGraph.fromRawEdges(n: np, edgesPerNode: pe);
  final pb = SpectralBasis.fromGraph(pg, 6, nodePaths: [
    for (var i = 0; i < np; i++) 'n$i',
  ]);
  final fe = pb.firstExcitedIndex;
  stdout.writeln('kernelDim=${pb.kernelDim} (expect 1), firstExcited=$fe');
  final f = [for (var i = 0; i < np; i++) pb.eigenvectors[fe * np + i]];
  stdout.writeln('fiedler along path: '
      '${f.map((x) => x.toStringAsFixed(3)).join(" ")}');
  // Sturm oscillation: the first excited mode of a path has exactly ONE sign
  // change (a single nodal boundary). This is the normalisation-invariant
  // "1-D ordering" property. (L_sym's Fiedler vector is D^{1/2}-weighted, so
  // it dips at the degree-1 endpoints — that is expected, NOT monotone.)
  var signChanges = 0;
  for (var i = 1; i < np; i++) {
    if (f[i].sign != f[i - 1].sign) signChanges++;
  }
  stdout.writeln('sign changes (expect 1 — the 1-D ordering): $signChanges\n');

  stdout.writeln('── SELFTEST: two clusters ──');
  // Two 5-cliques joined by a single bridge. First excited mode should
  // SEPARATE the clusters (opposite signs); this is the whole premise in
  // miniature — structure, not popularity.
  const nc = 10;
  final ce = List<List<(int, double)>>.generate(nc, (_) => []);
  void e(int a, int c) {
    ce[a].add((c, 1.0));
    ce[c].add((a, 1.0));
  }
  for (var i = 0; i < 5; i++) {
    for (var j = i + 1; j < 5; j++) {
      e(i, j);
    }
  }
  for (var i = 5; i < 10; i++) {
    for (var j = i + 1; j < 10; j++) {
      e(i, j);
    }
  }
  e(4, 5); // bridge
  final cg = CsrGraph.fromRawEdges(n: nc, edgesPerNode: ce);
  final cb = SpectralBasis.fromGraph(cg, 6);
  final cfe = cb.firstExcitedIndex;
  stdout.writeln('kernelDim=${cb.kernelDim} (expect 1), firstExcited=$cfe');
  final v = [for (var i = 0; i < nc; i++) cb.eigenvectors[cfe * nc + i]];
  stdout.writeln('first excited: '
      '${v.map((x) => x.toStringAsFixed(3)).join(" ")}');
  final clusterA = v.take(5).every((x) => x < 0);
  final clusterB = v.skip(5).every((x) => x > 0);
  final split = (clusterA && clusterB) || (!clusterA && !clusterB &&
      v.take(5).every((x) => x > 0) && v.skip(5).every((x) => x < 0));
  stdout.writeln('clusters separated by sign (expect true): $split');
  stdout.writeln('\nselftest done — if both hold, the eigenbasis + Π₀ '
      'extraction is trustworthy on the real repo.');
}
