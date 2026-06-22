import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../../backend/spectral_trajectory.dart';

/// View-model for the Orrery — the repo's structural history as a watchable
/// phase-space trajectory. Deliberately decoupled from [SpectralTrajectory]
/// (the engine source) so the painter can be exercised on synthetic data and
/// the mapping lives in one place ([OrreryModel.fromTrajectory], wired
/// separately).
///
/// Geometry: every position is a point in the unit Poincaré disk (‖p‖ < 1,
/// centre = structurally central file, boundary = peripheral). A file keeps a
/// stable [OrreryNode.id] across the whole history, so its positions form a
/// continuous path; `null` marks a step where the file did not yet exist.

/// One commit-snapshot: the repo's scalar state at a single step.
class OrreryStep {
  final int revision;
  final String? sha;
  final DateTime? date;

  /// Spectral gap λ₁ — connectivity. Large = one tight community, small = the
  /// graph is near-splitting into loosely-coupled halves.
  final double gap;

  /// Spectral rigidity — long-range order in the eigenvalue spectrum.
  final double rigidity;

  /// Von Neumann entropy — how many structural modes are active.
  final double vonNeumann;

  /// Nearest universality archetype name (crystalline / tree / modular / goe /
  /// bulk / poisson), or '' when the engine had no spectrum at this step.
  final String archetype;

  /// How archetypal this step is, in [0, 1] (1 = textbook example of its class).
  final double canonicality;

  /// This step is a detected regime change on the tracked curve (an inflection
  /// the codebase passed through — a reorg, a split).
  final bool regimeChange;

  /// The nearest archetype changed at this step (the repo became a different
  /// *kind* of structure).
  final bool archetypeShift;

  const OrreryStep({
    required this.revision,
    required this.sha,
    required this.date,
    required this.gap,
    required this.rigidity,
    required this.vonNeumann,
    required this.archetype,
    required this.canonicality,
    this.regimeChange = false,
    this.archetypeShift = false,
  });

  String get shortSha {
    final s = sha;
    if (s == null || s.isEmpty) return '—';
    return s.length <= 7 ? s : s.substring(0, 7);
  }
}

/// One file's path through the disk. [positions] is one entry per step (same
/// length as [OrreryModel.steps]); `null` = the file did not exist / had no
/// embedding at that step.
class OrreryNode {
  final int id;
  final String? path;
  final List<Offset?> positions;

  /// Change magnitude in [0, 1]: log-normalised count of commits that touched
  /// this file. Sizes the node — busier files read as bigger.
  final double churn;

  /// How many files this node stands for. 1 for a real file; >1 for a module
  /// super-node in the aggregated ([OrreryLod.modules]) view.
  final int memberCount;

  const OrreryNode({
    required this.id,
    required this.path,
    required this.positions,
    this.churn = 0,
    this.memberCount = 1,
  });
}

/// Level of detail for the disk: every file as its own point, or files
/// collapsed into directory super-nodes (the answer to the hairball at scale).
enum OrreryLod { files, modules }

class OrreryModel {
  final List<OrreryStep> steps;
  final List<OrreryNode> nodes;

  const OrreryModel({required this.steps, required this.nodes});

  static const OrreryModel emptyModel =
      OrreryModel(steps: <OrreryStep>[], nodes: <OrreryNode>[]);

  bool get isEmpty => steps.isEmpty;
  int get stepCount => steps.length;

  /// The maximum scrub position — `stepCount - 1`, the head of history.
  double get headPosition => steps.isEmpty ? 0 : (steps.length - 1).toDouble();

  /// Linearly-interpolated disk position of [node] at a continuous scrub
  /// position [t] in `[0, stepCount-1]`. Returns `null` when the file is absent
  /// from the bracketing steps (so it simply isn't drawn yet/anymore).
  static Offset? sampleNode(OrreryNode node, double t) {
    final n = node.positions.length;
    if (n == 0) return null;
    if (t <= 0) return node.positions.first;
    if (t >= n - 1) return node.positions.last;
    final i = t.floor();
    final f = t - i;
    final Offset? a = node.positions[i];
    final Offset? b = node.positions[i + 1];
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return Offset(a.dx + (b.dx - a.dx) * f, a.dy + (b.dy - a.dy) * f);
  }

  /// Instantaneous speed of [node] at [t] (disk-space displacement per step),
  /// used to make reorganising files glow. 0 when undefined.
  static double sampleSpeed(OrreryNode node, double t) {
    final n = node.positions.length;
    if (n < 2) return 0;
    final i = t.clamp(0, (n - 2).toDouble()).floor();
    final Offset? a = node.positions[i];
    final Offset? b = node.positions[i + 1];
    if (a == null || b == null) return 0;
    return (b - a).distance;
  }

  /// Ideal module count when aggregating — small enough to read at a glance,
  /// large enough to keep distinct subsystems apart.
  static const int _idealModules = 16;

  /// Below this many files the disk reads fine as points; above it, lead with
  /// the aggregated module view (the "don't blob at scale" prescription).
  static const int aggregationThreshold = 80;

  /// A tiny floor so quiet files still nudge a module's centroid — keeps a
  /// module of all-untouched files from collapsing to the origin.
  static const double _centroidFloor = 0.05;

  /// Collapse files into directory super-nodes so the disk stays legible at
  /// scale (a handful of components, not thousands of dots). Grouping is by
  /// directory path — the unit a developer reasons about — but each module's
  /// position is the churn-weighted centroid of its members' disk positions at
  /// every step, so the *spatial* encoding stays spectral while the *grouping*
  /// stays human. Weights are constant over time, so a module drifts only when
  /// its files genuinely move or are born/retired — never from a weight jump.
  ///
  /// Depth is **non-uniform**: a greedy balanced partition keeps splitting the
  /// largest bucket one directory level deeper until the module budget is hit,
  /// so a dense subtree (a monorepo's `lib/`) resolves into its parts while a
  /// sparse one (`docs/`) stays whole — no single super-node swallows the repo.
  /// [steps] are shared unchanged; the result has one node per module.
  static OrreryModel aggregateByModule(OrreryModel files) {
    if (files.nodes.isEmpty || files.steps.isEmpty) return files;
    final int stepCount = files.steps.length;

    // Directory segments per file (filename dropped; '' for a root file).
    final dirs = <List<String>>[
      for (final node in files.nodes)
        () {
          final p = node.path;
          if (p == null || p.isEmpty) return const <String>[];
          final segs = p.split('/');
          return segs.length <= 1
              ? const <String>[]
              : segs.sublist(0, segs.length - 1);
        }(),
    ];

    final buckets = _balancedModulePartition(dirs, files.nodes.length);

    // Aggregate (summed) churn per module, then log-normalise across modules so
    // one mega-module doesn't dwarf the rest — same heavy-tail taming as files.
    final agg = <double>[
      for (final b in buckets)
        () {
          double c = 0;
          for (final id in b.members) {
            c += files.nodes[id].churn;
          }
          return c;
        }(),
    ];
    double maxAgg = 0;
    for (final v in agg) {
      if (v > maxAgg) maxAgg = v;
    }
    final double denom = math.log(1 + maxAgg);

    final nodes = <OrreryNode>[];
    for (int mi = 0; mi < buckets.length; mi++) {
      final members = buckets[mi].members;
      final positions = List<Offset?>.filled(stepCount, null);
      for (int s = 0; s < stepCount; s++) {
        double wx = 0, wy = 0, wsum = 0;
        for (final id in members) {
          final p = files.nodes[id].positions[s];
          if (p == null) continue;
          final w = files.nodes[id].churn + _centroidFloor;
          wx += p.dx * w;
          wy += p.dy * w;
          wsum += w;
        }
        if (wsum > 0) positions[s] = Offset(wx / wsum, wy / wsum);
      }
      nodes.add(OrreryNode(
        id: mi,
        path: buckets[mi].label,
        positions: positions,
        churn: denom > 0 ? (math.log(1 + agg[mi]) / denom).clamp(0.0, 1.0) : 0.0,
        memberCount: members.length,
      ));
    }
    return OrreryModel(steps: files.steps, nodes: nodes);
  }

  /// Greedy balanced partition of files (given each file's [dirs] segments) into
  /// up to [_idealModules] directory buckets. Start with everything in one
  /// bucket; repeatedly split the largest *splittable* bucket one level deeper.
  /// Splitting a bucket sends each member to the child for its next directory
  /// segment, and any files that live *directly* in the bucket's directory form
  /// an unsplittable leaf residue.
  static List<_ModuleBucket> _balancedModulePartition(
      List<List<String>> dirs, int n) {
    final buckets = <_ModuleBucket>[
      _ModuleBucket(const <String>[], List<int>.generate(n, (i) => i)),
    ];
    bool splittable(_ModuleBucket b) {
      for (final m in b.members) {
        if (dirs[m].length > b.prefix.length) return true;
      }
      return false;
    }

    while (buckets.length < _idealModules) {
      int pick = -1, pickSize = 0;
      for (int i = 0; i < buckets.length; i++) {
        if (buckets[i].members.length > pickSize && splittable(buckets[i])) {
          pick = i;
          pickSize = buckets[i].members.length;
        }
      }
      if (pick < 0) break; // nothing left to split

      final b = buckets.removeAt(pick);
      final children = <String, List<int>>{};
      final residue = <int>[];
      for (final m in b.members) {
        final d = dirs[m];
        if (d.length > b.prefix.length) {
          (children[d[b.prefix.length]] ??= <int>[]).add(m);
        } else {
          residue.add(m); // file lives directly in this directory
        }
      }
      // Keep child order stable (largest first) so the partition is
      // deterministic regardless of map iteration order.
      final keys = children.keys.toList()
        ..sort((a, c) => children[c]!.length.compareTo(children[a]!.length));
      for (final k in keys) {
        buckets.add(_ModuleBucket(<String>[...b.prefix, k], children[k]!));
      }
      if (residue.isNotEmpty) buckets.add(_ModuleBucket(b.prefix, residue));
    }
    return buckets;
  }

  /// Map the engine's [SpectralTrajectory] into the view-model the painter
  /// consumes. Each commit-snapshot becomes an [OrreryStep]; each file becomes
  /// an [OrreryNode] whose positions are its Poincaré embedding at every step
  /// (`null` before the file existed). The widest basis across history (the
  /// head) defines the node-id space and supplies labels.
  factory OrreryModel.fromTrajectory(SpectralTrajectory traj) {
    final pts = traj.points;
    if (pts.length < 2) return emptyModel;

    final gap = traj.gapCurve();
    final rigidity = traj.rigidityCurve();
    final vn = traj.vonNeumannCurve();
    final uni = traj.universalityCurve();

    final regimeIdx = <int>{
      for (final r in traj.regimeChanges(curve: gap)) r.index,
    };
    final shiftIdx = traj.archetypeTransitions().toSet();

    final steps = <OrreryStep>[
      for (int i = 0; i < pts.length; i++)
        OrreryStep(
          revision: pts[i].revision,
          sha: pts[i].commitSha,
          date: pts[i].timestamp,
          gap: i < gap.length ? gap[i] : 0.0,
          rigidity: i < rigidity.length ? rigidity[i] : 0.0,
          vonNeumann: i < vn.length ? vn[i] : 0.0,
          archetype: i < uni.length ? (uni[i]?.nearest.name ?? '') : '',
          canonicality: i < uni.length ? (uni[i]?.canonicality ?? 0.0) : 0.0,
          regimeChange: regimeIdx.contains(i),
          archetypeShift: shiftIdx.contains(i),
        ),
    ];

    int maxN = 0;
    List<String>? paths;
    for (final p in pts) {
      final b = p.state.fileSpectrum;
      if (b != null && b.n > maxN) {
        maxN = b.n;
        paths = b.nodePaths;
      }
    }
    final churn = _normalizedChurn(traj.nodeChurn, maxN);

    final List<OrreryNode> nodes;
    final uaseFrames = traj.uaseFrames;
    if (uaseFrames != null &&
        traj.uaseDims >= 3 &&
        uaseFrames.length == pts.length) {
      // Shared-basis positions: stable by construction, so no alignment or
      // smoothing (those would only blur real motion).
      nodes = _nodesFromUase(uaseFrames, traj.uaseDims, pts.length, paths, churn);
    } else {
      final byNode = <List<Offset?>>[
        for (int id = 0; id < maxN; id++)
          () {
            final trace = traj.poincareTraceOfNode(id);
            return <Offset?>[
              for (int i = 0; i < pts.length; i++)
                if (i < trace.length && !trace[i].x.isNaN && !trace[i].y.isNaN)
                  Offset(trace[i].x, trace[i].y)
                else
                  null,
            ];
          }(),
      ];
      // Fallback only (no UASE frames): the per-snapshot embedding can
      // rotate/reflect frame-to-frame, so Procrustes-align then lightly smooth
      // the residual so the wake reads as drift rather than teleportation.
      _alignFrames(byNode, pts.length);
      _smoothFrames(byNode, pts.length, passes: 2);
      nodes = <OrreryNode>[
        for (int id = 0; id < maxN; id++)
          OrreryNode(
            id: id,
            path: (paths != null && id < paths.length) ? paths[id] : null,
            positions: byNode[id],
            churn: id < churn.length ? churn[id] : 0.0,
          ),
      ];
    }

    return OrreryModel(steps: steps, nodes: nodes);
  }

  /// Log-normalise raw per-file commit-touch counts to [0, 1]. Log because
  /// churn is heavy-tailed — a few files dominate linearly and would flatten
  /// everyone else.
  static List<double> _normalizedChurn(Float64List? raw, int n) {
    final out = List<double>.filled(n, 0.0);
    if (raw == null || raw.isEmpty) return out;
    double maxRaw = 0;
    for (final v in raw) {
      if (v > maxRaw) maxRaw = v;
    }
    final denom = math.log(1 + maxRaw);
    if (denom <= 0) return out;
    for (int i = 0; i < n && i < raw.length; i++) {
      out[i] = (math.log(1 + raw[i]) / denom).clamp(0.0, 1.0);
    }
    return out;
  }

  /// Map the shared-basis UASE frames to Poincaré-disk positions. Each axis
  /// blends several community modes (dim 0 is the all-positive centrality mode,
  /// so it's skipped) — using only dims 1 and 2 collapses near-binary
  /// eigenvectors onto two perpendicular lines (a thin cross); blending the
  /// finer modes spreads each community into a lobe. Radius comes from the
  /// blended 2D magnitude (engine-style tanh squish), so a structurally central
  /// file sits near the centre and a strongly-community-bound one toward the
  /// rim. A node with no embedding at a step (not yet born) is null.
  static List<OrreryNode> _nodesFromUase(
    List<Float64List> frames,
    int d,
    int stepCount,
    List<String>? paths,
    List<double> churn,
  ) {
    final int n = frames.isEmpty ? 0 : frames.last.length ~/ d;
    const double targetRadius = 0.92;
    // x ← dims 1,3,5 ; y ← dims 2,4,6 — decaying weights so the leading split
    // dominates and the finer structure perturbs nodes off the axes.
    const xDims = <int>[1, 3, 5];
    const yDims = <int>[2, 4, 6];
    const blend = <double>[1.0, 0.6, 0.35];

    double axis(Float64List f, int base, List<int> dims) {
      double s = 0;
      for (int k = 0; k < dims.length; k++) {
        if (dims[k] < d) s += blend[k] * f[base + dims[k]];
      }
      return s;
    }

    // Robust radial scale: the 90th percentile of the 2D magnitude, not the max
    // (a few outliers would otherwise compress everyone else into the centre).
    final mags = <double>[];
    for (final f in frames) {
      final cnt = f.length ~/ d;
      for (int i = 0; i < cnt; i++) {
        final base = i * d;
        final dx = axis(f, base, xDims);
        final dy = axis(f, base, yDims);
        final m = math.sqrt(dx * dx + dy * dy);
        if (m > 1e-9) mags.add(m);
      }
    }
    mags.sort();
    final double magMax = mags.isEmpty
        ? 1.0
        : mags[(mags.length * 0.9).floor().clamp(0, mags.length - 1)];

    final nodes = <OrreryNode>[];
    for (int id = 0; id < n; id++) {
      final positions = <Offset?>[];
      for (int t = 0; t < stepCount; t++) {
        final f = frames[t];
        final base = id * d;
        if (base + d > f.length) {
          positions.add(null);
          continue;
        }
        double total = 0;
        for (int j = 0; j < d; j++) {
          final v = f[base + j];
          total += v * v;
        }
        if (total < 1e-12) {
          positions.add(null); // not yet born
          continue;
        }
        final double dx = axis(f, base, xDims);
        final double dy = axis(f, base, yDims);
        final double mag = math.sqrt(dx * dx + dy * dy);
        final double radius = _tanh(mag / magMax * 2.5) * targetRadius;
        positions.add(mag < 1e-12
            ? Offset.zero
            : Offset(dx / mag * radius, dy / mag * radius));
      }
      nodes.add(OrreryNode(
        id: id,
        path: (paths != null && id < paths.length) ? paths[id] : null,
        positions: positions,
        churn: id < churn.length ? churn[id] : 0.0,
      ));
    }
    return nodes;
  }
}

double _tanh(double x) {
  final e2 = math.exp(2 * x);
  return (e2 - 1) / (e2 + 1);
}

/// One directory bucket during module aggregation: the shared directory
/// [prefix] and the file ids under it. See [OrreryModel.aggregateByModule].
class _ModuleBucket {
  final List<String> prefix;
  final List<int> members;
  _ModuleBucket(this.prefix, this.members);

  /// Display label: the directory path, or '(root)' for files at the repo root.
  String get label => prefix.isEmpty ? '(root)' : prefix.join('/');
}

/// 2D orthogonal Procrustes (Kabsch, reflections allowed) — rotate/reflect each
/// frame to best match the previous, cumulatively. [byNode] is `[node][step]`
/// of disk positions, mutated in place. Reflections are allowed because an
/// eigenvector sign flip *is* a reflection of the embedding.
void _alignFrames(List<List<Offset?>> byNode, int stepCount) {
  for (int s = 1; s < stepCount; s++) {
    double sxx = 0, sxy = 0, syx = 0, syy = 0;
    int count = 0;
    for (final traj in byNode) {
      final Offset? a = traj[s]; // current frame
      final Offset? b = traj[s - 1]; // previous (already aligned)
      if (a == null || b == null) continue;
      sxx += b.dx * a.dx;
      sxy += b.dx * a.dy;
      syx += b.dy * a.dx;
      syy += b.dy * a.dy;
      count++;
    }
    if (count < 3) continue; // too few shared points to trust an alignment

    // Best proper rotation vs. best reflection; keep whichever aligns better.
    final double theta = math.atan2(syx - sxy, sxx + syy);
    final double phi = math.atan2(syx + sxy, sxx - syy);
    final double ct = math.cos(theta), st = math.sin(theta);
    final double cp = math.cos(phi), sp = math.sin(phi);
    final double scoreRot = ct * (sxx + syy) + st * (syx - sxy);
    final double scoreRef = cp * (sxx - syy) + sp * (syx + sxy);
    final bool reflect = scoreRef > scoreRot;

    for (final traj in byNode) {
      final Offset? a = traj[s];
      if (a == null) continue;
      traj[s] = reflect
          ? Offset(cp * a.dx + sp * a.dy, sp * a.dx - cp * a.dy)
          : Offset(ct * a.dx - st * a.dy, st * a.dx + ct * a.dy);
    }
  }
}

/// Light 3-tap temporal smoothing (centre-weighted) over each node's path,
/// repeated [passes] times. Tames the residual single-frame jumps the rigid
/// alignment can't remove, so trails read as drift. Nulls are skipped, so a
/// file's birth/death isn't smeared.
void _smoothFrames(List<List<Offset?>> byNode, int stepCount,
    {int passes = 1}) {
  for (int pass = 0; pass < passes; pass++) {
    for (final traj in byNode) {
      final orig = List<Offset?>.of(traj);
      for (int s = 0; s < stepCount; s++) {
        final Offset? c = orig[s];
        if (c == null) continue;
        double wx = c.dx * 2, wy = c.dy * 2, w = 2;
        if (s > 0 && orig[s - 1] != null) {
          wx += orig[s - 1]!.dx;
          wy += orig[s - 1]!.dy;
          w += 1;
        }
        if (s < stepCount - 1 && orig[s + 1] != null) {
          wx += orig[s + 1]!.dx;
          wy += orig[s + 1]!.dy;
          w += 1;
        }
        traj[s] = Offset(wx / w, wy / w);
      }
    }
  }
}
