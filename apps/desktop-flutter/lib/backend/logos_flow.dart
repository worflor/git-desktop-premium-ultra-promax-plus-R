// Filament — execution-flow analysis on code graphs.
// AR(2) oscillator + Born mixing, language-agnostic.

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'lru_cache.dart';

// ═══════════════════════════════════════════════════════════════════
// Flow graph data structures
// ═══════════════════════════════════════════════════════════════════

class FlowNode {
  final String id;
  final int address;    // 8-bit lattice address
  final double lyapunov;
  final double kr, ki, gr; // cached K-G from address
  final int sourceLine;
  final String sourceText;

  factory FlowNode({
    required String id,
    required int address,
    double lyapunov = 0.0,
    required int sourceLine,
    String sourceText = '',
  }) {
    final (kr, ki, gr) = flowKG(address, lyapunov: lyapunov);
    return FlowNode._withKG(
      id: id, address: address, lyapunov: lyapunov,
      kr: kr, ki: ki, gr: gr,
      sourceLine: sourceLine, sourceText: sourceText,
    );
  }

  FlowNode._withKG({
    required this.id,
    required this.address,
    required this.lyapunov,
    required this.kr,
    required this.ki,
    required this.gr,
    required this.sourceLine,
    required this.sourceText,
  });

  bool hasAxis(int axis) => address & axis != 0;
}

class FlowEdge {
  final String target;
  final int hamming;
  const FlowEdge(this.target, this.hamming);
}

class FlowGraph {
  final Map<String, FlowNode> nodes = {};
  final Map<String, List<FlowEdge>> adj = {};

  void addNode(FlowNode node) {
    nodes[node.id] = node;
    adj.putIfAbsent(node.id, () => []);
  }

  void addEdge(String src, String dst) {
    final s = nodes[src], d = nodes[dst];
    if (s == null || d == null) return;
    var hd = flowHamming(s.address, d.address);
    if (s.hasAxis(kFlowRestabilizes) && d.hasAxis(kFlowResource)) {
      final cov = flowCoverage(s.address, d.address);
      hd = math.max(0, (hd * (1.0 - cov)).round());
    }
    adj.putIfAbsent(src, () => []).add(FlowEdge(dst, hd));
  }

  void chain(List<String> ids) {
    for (var i = 0; i < ids.length - 1; i++) {
      addEdge(ids[i], ids[i + 1]);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Line geometry — language-agnostic structural analysis
// ═══════════════════════════════════════════════════════════════════

int _indentation(String line) {
  var n = 0;
  for (var i = 0; i < line.length; i++) {
    if (line[i] == ' ') {
      n++;
    } else if (line[i] == '\t') {
      n += 4;
    } else {
      break;
    }
  }
  return n;
}

/// Shannon entropy of printable characters in [s], normalised to [0, 1].
/// Low entropy → repetitive/structured (code). High entropy → natural
/// language or noise (comments, docs, binary residue).
double _charEntropy(String s) {
  if (s.length < 4) return 0.0;
  final counts = <int, int>{};
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    counts[c] = (counts[c] ?? 0) + 1;
  }
  final n = s.length.toDouble();
  var h = 0.0;
  for (final c in counts.values) {
    final p = c / n;
    if (p > 0) h -= p * math.log(p);
  }
  return h / math.log(math.max(counts.length, 2));
}

/// True when a stripped line is likely non-code: high character entropy
/// AND low structural-character density (few brackets, operators, semicolons).
bool _isLikelyNonCode(String stripped) {
  if (stripped.length < 3) return true;
  var structural = 0;
  for (var i = 0; i < stripped.length; i++) {
    final c = stripped.codeUnitAt(i);
    if (c == 0x28 || c == 0x29 || // ( )
        c == 0x7B || c == 0x7D || // { }
        c == 0x5B || c == 0x5D || // [ ]
        c == 0x3B || c == 0x3D || // ; =
        c == 0x3C || c == 0x3E || // < >
        c == 0x2E || c == 0x3A || // . :
        c == 0x2C) {              // ,
      structural++;
    }
  }
  final density = structural / stripped.length;
  if (density > 0.08) return false;
  return _charEntropy(stripped) > 0.88;
}

/// Lyapunov exponent from indentation geometry.
double _lyapunovFromGeometry(
    double fiedlerEstimate, double betweennessEstimate) {
  return fiedlerEstimate * betweennessEstimate * 3.0;
}

// ═══════════════════════════════════════════════════════════════════
// Graph extraction from source text
// ═══════════════════════════════════════════════════════════════════

/// Flow graph from indentation structure with eigenfrequency address.
///
/// Phase 1: build topology from indentation geometry (language-agnostic).
/// Phase 2: compute Lanczos eigenpairs on the topology → spectral
///          fingerprint. Compute eigenfrequency on each line's character
///          coupling chain → content fingerprint. OR the two → the line's
///          lattice address encodes both WHERE it sits (topology) and
///          WHAT it looks like (character harmonics).
///
/// When [globalCoupling] is supplied, the eigenfrequency basis comes
/// from the repo-wide bigram distribution rather than this file's own
/// statistics. That makes address `0x47` mean the same thing across
/// every file in the repo, which is required for the lifelong lattice's
/// per-cell Welford accumulators to be coherent. When null, falls back
/// to per-file coupling (legacy behaviour — addresses are file-local).
FlowGraph extractFlowGraph(String source, {CharCoupling? globalCoupling}) {
  final lines = source.split('\n');
  final nodeIds = <String>[];
  final nodeLines = <int>[];
  final nodeTexts = <String>[];
  final nodeLyapunovs = <double>[];

  // ── Phase 1a: identify non-empty, non-noise lines ──────────────
  final indents =
      List<int>.generate(lines.length, (i) => _indentation(lines[i]));
  final maxIndent = indents.fold<int>(0, math.max);
  final indentCounts = <int, int>{};
  for (final ind in indents) {
    indentCounts[ind] = (indentCounts[ind] ?? 0) + 1;
  }
  final totalNonEmpty = indents.where((i) => i >= 0).length;

  for (var i = 0; i < lines.length; i++) {
    final stripped = lines[i].trim();
    if (stripped.isEmpty) continue;
    if (_isLikelyNonCode(stripped)) continue;

    final prevInd = i > 0 ? indents[i - 1] : 0;
    final nextInd = i + 1 < lines.length ? indents[i + 1] : 0;
    final indentDelta = ((indents[i] - prevInd).abs() +
            (indents[i] - nextInd).abs()) /
        (maxIndent + 1);
    final levelCount = indentCounts[indents[i]] ?? 1;
    final betweenness = 1.0 - (levelCount / totalNonEmpty);
    final ly = _lyapunovFromGeometry(
        indentDelta.clamp(0.0, 1.0), betweenness.clamp(0.0, 1.0));

    nodeIds.add('L$i');
    nodeLines.add(i);
    nodeTexts.add(stripped);
    nodeLyapunovs.add(ly);
  }

  final n = nodeIds.length;
  if (n < 2) return FlowGraph();

  // ── Phase 1b: build topology (edges from indentation geometry) ─
  //
  // Sequential edges between consecutive nodes, plus scope-exit
  // cross-edges when indentation drops. Terminal detection is purely
  // topological: a node whose out-degree is 0 after cross-edge wiring
  // is a terminal (no keyword matching needed).
  final edgesPerNode = List<List<(int, double)>>.generate(n, (_) => []);

  // sequential edges
  for (var i = 0; i < n - 1; i++) {
    edgesPerNode[i].add((i + 1, 1.0));
  }

  // scope-exit cross-edges (indentation drops)
  final indentStack = <(int, int)>[]; // (nodeIndex, indent)
  for (var i = 0; i < n; i++) {
    final indent = indents[nodeLines[i]];
    if (i > 0) {
      final prevIndent = indents[nodeLines[i - 1]];
      if (indent > prevIndent) {
        indentStack.add((i - 1, prevIndent));
      } else if (indent < prevIndent) {
        while (indentStack.isNotEmpty && indentStack.last.$2 >= indent) {
          final (scopeEntry, _) = indentStack.removeLast();
          edgesPerNode[i].add((scopeEntry, 1.0));
        }
      }
    }
  }

  // Detect terminal nodes by topology: nodes with out-degree 0 or whose
  // ONLY successor is a node at shallower indentation (scope exit) are
  // terminals — the flow ends there. Remove their forward sequential
  // edge if they look like a scope exit to shallow depth.
  for (var i = 0; i < n - 1; i++) {
    final indent = indents[nodeLines[i]];
    final prevInd = i > 0 ? indents[nodeLines[i - 1]] : 0;
    if (prevInd > indent + 4 && indent <= 4) {
      // scope exit to shallow — check if out-degree is just the
      // sequential edge (would make this a pass-through). If so,
      // remove it — this node is a terminal.
      if (edgesPerNode[i].length == 1) {
        edgesPerNode[i].clear();
      }
    }
  }

  // ── Phase 2: spectral decomposition → fingerprint addresses ────
  //
  // Build a CsrGraph from the topology, compute the Lanczos eigenpairs,
  // and derive each node's 8-bit spectral fingerprint from the sign
  // pattern of the first 8 non-trivial eigenvectors. This IS the Logos
  // spectral byte fingerprint — universal, language-agnostic, computed
  // from the graph's own Laplacian.

  // Symmetrise edges for the Laplacian (undirected graph).
  final symEdges = List<List<(int, double)>>.generate(n, (_) => []);
  for (var i = 0; i < n; i++) {
    for (final (j, w) in edgesPerNode[i]) {
      symEdges[i].add((j, w));
      symEdges[j].add((i, w));
    }
  }

  final csr = CsrGraph.fromRawEdges(n: n, edgesPerNode: symEdges);
  final kEig = n < 9 ? n : 9;
  final basis = SpectralBasis.fromGraph(csr, kEig);
  final topoFingerprints = basis.spectralFingerprintTable();

  // ── Phase 2b: eigenfrequency on character coupling chains ─────
  //
  // Each line is a vibrating string. The coupling between adjacent
  // characters is the tension. With a [globalCoupling] supplied by
  // the caller, the basis is the repo's collective bigram distribution
  // — same basis for every file → addresses with stable repo-wide
  // meaning. With no global supplied, we fall back to file-local
  // statistics (legacy path; addresses are file-local only).
  final charCoupling = globalCoupling ?? CharCoupling.fromSource(source);

  // ── Phase 3: assemble FlowGraph with hybrid addresses ─────────
  final graph = FlowGraph();
  for (var i = 0; i < n; i++) {
    final topoAddr = topoFingerprints[i];
    final eigenAddr = eigenAddress(nodeTexts[i], charCoupling);
    final highNibble = eigenAddr >= 0
        ? (eigenAddr << 4) & 0xF0
        : (nodeTexts[i].hashCode & 0x0F) << 4;
    final hybridAddr = (topoAddr & 0x0F) | highNibble;
    graph.addNode(FlowNode(
      id: nodeIds[i],
      address: hybridAddr,
      lyapunov: nodeLyapunovs[i],
      sourceLine: nodeLines[i],
      sourceText: nodeTexts[i],
    ));
  }
  for (var i = 0; i < n; i++) {
    for (final (j, _) in edgesPerNode[i]) {
      graph.addEdge(nodeIds[i], nodeIds[j]);
    }
  }
  return graph;
}

// ═══════════════════════════════════════════════════════════════════
// Preprocessing: renormalize + Cooper pair fusion
// ═══════════════════════════════════════════════════════════════════

/// Strip PURE nodes on linear chains (irrelevant operators).
FlowGraph renormalize(FlowGraph g) {
  // build in-degree map
  final inDeg = <String, int>{};
  for (final nid in g.nodes.keys) {
    inDeg[nid] = 0;
  }
  for (final edges in g.adj.values) {
    for (final e in edges) {
      inDeg[e.target] = (inDeg[e.target] ?? 0) + 1;
    }
  }

  // find removable: PURE, exactly 1 in-edge, exactly 1 out-edge
  final removable = <String>{};
  for (final nid in g.nodes.keys) {
    final node = g.nodes[nid]!;
    if (node.address != kFlowPure) continue;
    final ins = inDeg[nid] ?? 0;
    final outs = g.adj[nid]?.length ?? 0;
    if (ins == 1 && outs == 1) removable.add(nid);
  }

  if (removable.isEmpty) return g;

  final out = FlowGraph();
  for (final nid in g.nodes.keys) {
    if (!removable.contains(nid)) out.addNode(g.nodes[nid]!);
  }

  for (final src in g.adj.keys) {
    if (removable.contains(src)) continue;
    for (final e in g.adj[src]!) {
      // chase through removable chain
      var target = e.target;
      while (removable.contains(target)) {
        final chain = g.adj[target];
        if (chain != null && chain.isNotEmpty) {
          target = chain.first.target;
        } else {
          break;
        }
      }
      if (!removable.contains(target) && out.nodes.containsKey(target)) {
        out.addEdge(src, target);
      }
    }
  }

  return out;
}

/// Fuse adjacent lock+unlock (Cooper pairs) into super-nodes.
FlowGraph fuseCooperPairs(FlowGraph g) {
  final fused = <String, String>{};
  final pairs = <(String, String, String, int)>[];

  for (final nid in g.nodes.keys) {
    if (fused.containsKey(nid)) continue;
    final node = g.nodes[nid]!;
    if (node.hasAxis(kFlowMutates) && node.hasAxis(kFlowResource) &&
        !node.hasAxis(kFlowRestabilizes)) {
      final outs = g.adj[nid];
      if (outs != null && outs.length == 1) {
        final partner = g.nodes[outs.first.target];
        if (partner != null &&
            partner.hasAxis(kFlowRestabilizes) &&
            partner.hasAxis(kFlowMutates)) {
          final fusedAddr = node.address | partner.address;
          final fusedName = '${nid}+${partner.id}';
          pairs.add((nid, partner.id, fusedName, fusedAddr));
          fused[nid] = fusedName;
          fused[partner.id] = fusedName;
        }
      }
    }
  }

  if (pairs.isEmpty) return g;

  final out = FlowGraph();
  for (final nid in g.nodes.keys) {
    if (!fused.containsKey(nid)) out.addNode(g.nodes[nid]!);
  }
  for (final (firstId, _, fname, faddr) in pairs) {
    final (kr, ki, gr) = flowKG(faddr);
    out.addNode(FlowNode._withKG(
      id: fname, address: faddr, lyapunov: 0.0,
      kr: kr, ki: ki, gr: gr,
      sourceLine: g.nodes[firstId]?.sourceLine ?? 0,
      sourceText: fname,
    ));
  }

  for (final src in g.adj.keys) {
    final realSrc = fused[src] ?? src;
    if (!out.nodes.containsKey(realSrc)) continue;
    for (final e in g.adj[src]!) {
      final realDst = fused[e.target] ?? e.target;
      if (!out.nodes.containsKey(realDst)) continue;
      if (realSrc == realDst) continue;
      final existing = out.adj[realSrc]?.map((e) => e.target).toSet() ?? {};
      if (!existing.contains(realDst)) {
        out.addEdge(realSrc, realDst);
      }
    }
  }

  return out;
}

/// Apply all preprocessing.
FlowGraph optimizeGraph(FlowGraph g) => renormalize(fuseCooperPairs(g));

// ═══════════════════════════════════════════════════════════════════
// Simulation
// ═══════════════════════════════════════════════════════════════════

enum FlowBugKind {
  staleValue,
  temporalShift,
  contextInversion,
  contradictoryFlow,
}

class FlowFinding {
  final String nodeId;
  final int sourceLine;
  final String sourceText;
  final double certainty;
  final double phase;
  final FlowBugKind kind;
  final int pathCount;
  final int address;
  final double coherence;
  final double lyapunov;

  /// The dominant Walsh interaction mode driving this finding, if
  /// identified by the Möbius decomposition. The address bits name
  /// which axes participate in the irreducible interaction; the
  /// order (popcount) says how many axes are entangled.
  /// null when the finding comes from a non-Walsh code path.
  final int? walshInteraction;

  /// Signed Walsh coefficient of [walshInteraction] — the magnitude
  /// and direction of the irreducible interaction effect.
  final double? walshCoefficient;

  const FlowFinding({
    required this.nodeId,
    required this.sourceLine,
    required this.sourceText,
    required this.certainty,
    required this.phase,
    required this.kind,
    this.pathCount = 1,
    this.address = 0,
    this.coherence = 1.0,
    this.lyapunov = 0.0,
    this.walshInteraction,
    this.walshCoefficient,
  });

  /// Composite concern score: higher = worse.
  /// Uncertainty × impact × incoherence.
  double get composite =>
      (1.0 - certainty) * (1.0 + lyapunov) * (1.0 - coherence * coherence);

  String get severity {
    if (kind == FlowBugKind.contradictoryFlow) return 'joint';
    if (certainty < 0.1) return 'critical';
    if (certainty < 0.3) return 'warn';
    return 'info';
  }
}

FlowBugKind _classifyPhase(double phase) {
  final a = phase.abs();
  if (a < math.pi / 4) return FlowBugKind.staleValue;
  if (a < 3 * math.pi / 4) return FlowBugKind.temporalShift;
  return FlowBugKind.contextInversion;
}

/// Hamming impedance between two spectral fingerprints → coupling [0, 1].
double logosFingerCoupling(int fileFingerprint, int anchorFingerprint) {
  final h = flowHamming(fileFingerprint, anchorFingerprint);
  return 1.0 - (1.0 - math.cos(math.pi * h / 8)) / 2;
}

/// Majority-vote centroid of a fingerprint set.
int anchorFingerprint(List<int> fingerprints) {
  if (fingerprints.isEmpty) return 0;
  final half = fingerprints.length ~/ 2;
  var anchor = 0;
  for (var b = 0; b < 8; b++) {
    var count = 0;
    final mask = 1 << b;
    for (final fp in fingerprints) {
      if (fp & mask != 0) count++;
    }
    if (count > half) anchor |= mask;
  }
  return anchor;
}

/// YAA* (quantum walk) with AR(2) oscillator + Born mixing.
/// [logosCoupling] adds a structural arrival from the Logos graph.
/// [sseLattice] accumulates certainty observations for self-calibration.
/// [priorNovelty] maps a lattice address to a novelty score in [0, 1]
/// derived from the GYAT lifelong prior — biases walker initialization
/// toward anomaly-seeking (familiar) or certainty-seeking (novel).
List<FlowFinding> simulateFlow(
  FlowGraph graph, {
  Set<String>? entryNodes,
  double threshold = 0.3,
  int maxDepth = 30,
  double? logosCoupling,
  FlowSseLattice? sseLattice,
  double Function(int address)? priorNovelty,
}) {
  if (entryNodes == null || entryNodes.isEmpty) {
    entryNodes = graph.nodes.isNotEmpty
        ? {graph.nodes.values.first.id}
        : <String>{};
  }

  final arrivals = <String, List<(double, double)>>{};
  final edgeCount = graph.adj.values.fold<int>(0, (s, e) => s + e.length);
  final stepBudget = [graph.nodes.length * edgeCount];

  for (final start in entryNodes) {
    if (!graph.nodes.containsKey(start)) continue;
    if (stepBudget[0] <= 0) break;
    final novelty = priorNovelty != null
        ? priorNovelty(graph.nodes[start]!.address)
        : null;
    _yaaStarPropagate(graph, start, maxDepth, arrivals, stepBudget,
        sseLattice, novelty: novelty);
  }

  // Born-mix at each visited node.
  final findings = <FlowFinding>[];
  for (final entry in arrivals.entries) {
    final arrs = entry.value;
    if (arrs.isEmpty) continue;
    final mixInput = logosCoupling != null
        ? [...arrs, (logosCoupling, 0.0)]
        : arrs;
    final (mc, mp) = flowBornMix(mixInput);
    final coh = flowPhaseCoherence(mixInput);
    final contradictory = flowIsContradictory(arrs);
    final node = graph.nodes[entry.key]!;
    sseLattice?.observe(node.address, mc);
    if (mc < threshold || contradictory) {
      findings.add(FlowFinding(
        nodeId: entry.key,
        sourceLine: node.sourceLine,
        sourceText: node.sourceText,
        certainty: mc,
        phase: mp,
        kind: contradictory
            ? FlowBugKind.contradictoryFlow
            : _classifyPhase(mp),
        pathCount: arrs.length,
        address: node.address,
        coherence: coh,
        lyapunov: node.lyapunov,
      ));
    }
  }

  findings.sort((a, b) => a.certainty.compareTo(b.certainty));
  return findings;
}

/// Adaptive arrival cap: scales with graph density so small graphs
/// aren't over-capped and large graphs don't blow up.
int _adaptiveArrivalCap(FlowGraph graph) {
  final n = graph.nodes.length;
  if (n < 8) return n;
  final edgeCount = graph.adj.values.fold<int>(0, (s, e) => s + e.length);
  final avgDegree = n > 0 ? edgeCount / n : 1.0;
  return math.max(8, (3 * math.sqrt(avgDegree * n)).ceil());
}

class _PathChain {
  final String node;
  final _PathChain? parent;
  const _PathChain(this.node, this.parent);

  bool contains(String id) {
    _PathChain? c = this;
    while (c != null) {
      if (c.node == id) return true;
      c = c.parent;
    }
    return false;
  }
}

void _yaaStarPropagate(
  FlowGraph graph,
  String startId,
  int maxDepth,
  Map<String, List<(double, double)>> arrivals,
  List<int> stepBudget,
  FlowSseLattice? externalLattice, {
  double? novelty,
}) {
  if (maxDepth <= 0) return;

  final heap = BinaryHeap<(String, FlowOscillator, double, _PathChain, int, WalkerWeight, int)>(
      (a, b) => b.$3.compareTo(a.$3));

  final bestByLineage = <(String, int), double>{};
  final localLattice = FlowSseLattice();
  final arrivalCap = _adaptiveArrivalCap(graph);

  final root = _PathChain(startId, null);
  final walkers = novelty != null
      ? WalkerWeight.withPrior(novelty)
      : WalkerWeight.simplex(3);
  for (var i = 0; i < walkers.length; i++) {
    heap.push((startId, FlowOscillator(), double.infinity, root, 0, walkers[i], i));
  }

  while (heap.isNotEmpty && stepBudget[0] > 0) {
    final (nid, osc, _, path, depth, weight, lineage) = heap.pop();
    stepBudget[0]--;

    final node = graph.nodes[nid];
    if (node == null) continue;

    if (node.hasAxis(kFlowRestabilizes)) {
      var downstreamAddr = kFlowResource | kFlowLifecycle | kFlowMutates;
      for (final e in graph.adj[nid] ?? <FlowEdge>[]) {
        final dn = graph.nodes[e.target];
        if (dn != null && dn.hasAxis(kFlowResource)) {
          downstreamAddr = dn.address;
          break;
        }
      }
      osc.restabilize(flowCoverage(node.address, downstreamAddr));
    }

    localLattice.observe(node.address, osc.certainty);

    final list = arrivals.putIfAbsent(nid, () => []);
    if (list.length >= arrivalCap) continue;
    list.add((osc.certainty, osc.phase));

    if (depth >= maxDepth) continue;

    final edges = graph.adj[nid] ?? <FlowEdge>[];
    var fanout = 0;
    for (final e in edges) {
      if (!path.contains(e.target) && graph.nodes.containsKey(e.target)) {
        fanout++;
      }
    }
    final branchGain = flowBranchGain(fanout);

    for (final edge in edges) {
      if (path.contains(edge.target)) continue;
      final target = graph.nodes[edge.target];
      if (target == null) continue;

      var tKr = target.kr, tKi = target.ki, tGr = target.gr;
      if (target.hasAxis(kFlowRestabilizes)) {
        for (final e2 in graph.adj[edge.target] ?? <FlowEdge>[]) {
          final dn = graph.nodes[e2.target];
          if (dn != null && dn.hasAxis(kFlowResource)) {
            final cov = flowCoverage(target.address, dn.address);
            final (kr, ki, gr) = flowKG(
                target.address,
                lyapunov: target.lyapunov,
                restabCoverage: cov);
            tKr = kr; tKi = ki; tGr = gr;
            break;
          }
        }
      }

      final childOsc = osc.clone();
      if (branchGain > 0) childOsc.restabilize(branchGain);
      final parentPhase = childOsc.phase;
      childOsc.step(tKr, tKi, tGr, edge.hamming);

      final localZ = localLattice.zBelowForAddress(
          target.address, childOsc.certainty);
      final externalZ = externalLattice?.zBelowForAddress(
          target.address, childOsc.certainty) ?? 0.0;
      final ssePrior = math.max(localZ, externalZ);

      final phaseVelocity = (childOsc.phase - parentPhase).abs();
      final anomaly = phaseVelocity * (1.0 - childOsc.certainty);
      final structure = (1.0 + edge.hamming / 8.0)
          * math.log(math.max(2, fanout)) / math.ln2;

      final childWeight = weight.clone();
      childWeight.absorb(anomaly, structure, childOsc.certainty, maxDepth);

      final pri = flowSearchPriority(
        certainty: childOsc.certainty,
        phaseVelocity: phaseVelocity,
        spectralDistance: edge.hamming,
        fanout: fanout,
        ssePrior: ssePrior,
        depth: depth + 1,
        maxDepth: maxDepth,
        weight: childWeight,
      );

      final key = (edge.target, lineage);
      final existing = bestByLineage[key];
      if (existing != null && existing >= pri) continue;
      bestByLineage[key] = pri;

      heap.push((
          edge.target, childOsc, pri, _PathChain(edge.target, path), depth + 1,
          childWeight, lineage));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Dream — lattice self-analysis on the Boolean hypercube
// ═══════════════════════════════════════════════════════════════════

List<FlowFinding> dreamAnalysis(FlowSseLattice lattice) {
  // ── Phase 0: Walsh decomposition ──────────────────────────────────
  //
  // Before any walk, decompose the lattice into its interaction
  // spectrum. This tells us WHICH axis-combinations have anomalous
  // behavior (the walk then traces HOW).

  final warmSet = <int>{};
  for (var a = 0; a < 256; a++) {
    if (lattice.cellCount(a) >= 8) warmSet.add(a);
  }
  if (warmSet.length < 2) return const [];

  // Walsh anomaly detection — find interaction modes whose energy
  // is unexpectedly high for their order.
  final walshAnomalies = lattice.anomalousInteractions(sigma: 1.5);

  // Per-address dominant Walsh mode: for each warm address, which
  // interaction mode contributes most to its deviation from the
  // thermal equilibrium. Used to annotate findings.
  final walshSpec = lattice.walshSpectrum;
  final addressDominant = <int, (int, double)>{};
  for (final a in warmSet) {
    var bestMode = 0;
    var bestMag = 0.0;
    for (var s = 1; s < 256; s++) {
      if (a & s != s) continue;
      final mag = walshSpec[s].abs();
      if (mag > bestMag) {
        bestMag = mag;
        bestMode = s;
      }
    }
    if (bestMag > 1e-10) addressDominant[a] = (bestMode, walshSpec[bestMode]);
  }

  // ── Phase 1: K-G from cube heat kernel ────────────────────────────
  //
  // Use the exact cube heat kernel at t=1 to compute smoothed K-G
  // coefficients. This replaces raw Hamming-neighbor averaging with
  // the analytically correct diffusion on Q₈.

  final equilibrium = lattice.thermalEquilibrium(1.0);
  final intrinsic = lattice.mobiusView;

  final dKr = List<double>.filled(256, 0.0);
  final dKi = List<double>.filled(256, 0.0);
  final dGr = List<double>.filled(256, 0.0);

  for (final a in warmSet) {
    dKr[a] = equilibrium[a];
    dKi[a] = lattice.cellStddev(a);
    // G damping from intrinsic Möbius contribution: addresses with
    // large intrinsic deviation from sub-addresses have more damping
    // (the interaction is genuinely irreducible, not inherited).
    dGr[a] = (intrinsic[a] - 0.5).abs();
  }

  // ── Phase 2: Walsh-guided seed selection ──────────────────────────
  //
  // Alpha strand seeds at the address where the strongest Walsh
  // anomaly manifests. Beta strand seeds at the address farthest
  // from it in thermal-equilibrium space. This replaces the
  // stddev-based seeding with interaction-aware targeting.

  var alphaStart = warmSet.first, betaStart = warmSet.first;
  if (walshAnomalies.isNotEmpty) {
    // Find the warm address most affected by the top anomalous mode.
    final topMode = walshAnomalies.first.$1;
    var bestResonance = -1.0;
    for (final a in warmSet) {
      if (a & topMode != topMode) continue;
      final resonance = lattice.cellStddev(a) *
          (lattice.cellMean(a) - equilibrium[a]).abs();
      if (resonance > bestResonance) {
        bestResonance = resonance;
        alphaStart = a;
      }
    }
    // Beta: farthest warm address from alpha in equilibrium space.
    var maxDist = -1.0;
    for (final a in warmSet) {
      final d = (equilibrium[a] - equilibrium[alphaStart]).abs();
      if (d > maxDist) {
        maxDist = d;
        betaStart = a;
      }
    }
  } else {
    // Fallback: original stddev-based seeding.
    var maxSd = -1.0, minSd = double.infinity;
    for (final a in warmSet) {
      final sd = dKi[a];
      if (sd > maxSd) { maxSd = sd; alphaStart = a; }
      if (sd < minSd) { minSd = sd; betaStart = a; }
    }
  }

  // ── Phase 3: YAA* walk for path reconstruction ────────────────────

  final heap = BinaryHeap<(int, FlowOscillator, double, Set<int>, int, WalkerWeight)>(
      (a, b) => b.$3.compareTo(a.$3));

  final arrivals = <int, List<(double, double)>>{};
  // Certainty seed: highest thermal equilibrium — the structural spine.
  var certaintyStart = warmSet.first;
  var bestEq = -1.0;
  for (final a in warmSet) {
    if (equilibrium[a] > bestEq) { bestEq = equilibrium[a]; certaintyStart = a; }
  }

  final walkers = WalkerWeight.simplex(3);
  final seeds = [alphaStart, betaStart, certaintyStart];
  for (var i = 0; i < walkers.length; i++) {
    heap.push((seeds[i], FlowOscillator(), double.infinity,
        {seeds[i]}, 0, walkers[i]));
  }

  final dreamArrivalCap = math.max(8, warmSet.length ~/ 2);
  final h = lattice.entropy(warmSet);
  // Budget scales with the lattice's information content: high-entropy
  // lattices (many independent clusters) need more steps to cover;
  // low-entropy lattices (one dominant mode) converge fast.
  // exp(H) is the effective number of occupied cells; multiplied by
  // the warm set size gives total coverage pressure.
  var budget = math.max(warmSet.length * 4, (warmSet.length * math.exp(h)).ceil());
  const maxDepth = 8;

  while (heap.isNotEmpty && budget > 0) {
    final (addr, osc, _, path, depth, weight) = heap.pop();
    budget--;

    if (!warmSet.contains(addr)) continue;

    lattice.observe(addr, osc.certainty);

    final list = arrivals.putIfAbsent(addr, () => []);
    if (list.length >= dreamArrivalCap) continue;
    list.add((osc.certainty, osc.phase));

    if (depth >= maxDepth) continue;

    var fanout = 0;
    for (var b = 0; b < 8; b++) {
      final n = addr ^ (1 << b);
      if (warmSet.contains(n) && !path.contains(n)) fanout++;
    }
    final branchGain = flowBranchGain(fanout);

    for (var b = 0; b < 8; b++) {
      final n = addr ^ (1 << b);
      if (!warmSet.contains(n) || path.contains(n)) continue;

      final childOsc = osc.clone();
      if (branchGain > 0) childOsc.restabilize(branchGain);
      final parentPhase = childOsc.phase;
      childOsc.step(dKr[n], dKi[n], dGr[n], 1);

      final phaseVelocity = (childOsc.phase - parentPhase).abs();
      final anomaly = phaseVelocity * (1.0 - childOsc.certainty);
      final structure = (1.0 + 1 / 8.0)
          * math.log(math.max(2, fanout)) / math.ln2;

      final childWeight = weight.clone();
      childWeight.absorb(anomaly, structure, childOsc.certainty, maxDepth);

      final ssePrior = lattice.zBelowForAddress(n, childOsc.certainty);
      final pri = flowSearchPriority(
        certainty: childOsc.certainty,
        phaseVelocity: phaseVelocity,
        spectralDistance: 1,
        fanout: fanout,
        ssePrior: ssePrior,
        depth: depth + 1,
        maxDepth: maxDepth,
        weight: childWeight,
      );

      heap.push((n, childOsc, pri, {...path, n}, depth + 1, childWeight));
    }
  }

  // ── Phase 4: findings with interaction annotation ─────────────────

  final findings = <FlowFinding>[];
  for (final addr in warmSet) {
    final arrs = arrivals[addr];
    if (arrs == null || arrs.length < 2) continue;

    final (mc, mp) = flowBornMix(arrs);
    final coh = flowPhaseCoherence(arrs);
    final contradictory = flowIsContradictory(arrs);
    lattice.observe(addr, mc);

    if (lattice.isAnomalous(addr, mc) || contradictory) {
      final hex = addr.toRadixString(16).padLeft(2, '0');
      final dominant = addressDominant[addr];
      findings.add(FlowFinding(
        nodeId: 'dream:$hex',
        sourceLine: addr,
        sourceText: 'dream:$hex',
        certainty: mc,
        phase: mp,
        kind: contradictory
            ? FlowBugKind.contradictoryFlow
            : _classifyPhase(mp),
        pathCount: arrs.length,
        address: addr,
        coherence: coh,
        lyapunov: dKi[addr],
        walshInteraction: dominant?.$1,
        walshCoefficient: dominant?.$2,
      ));
    }
  }

  findings.sort((a, b) => a.certainty.compareTo(b.certainty));
  return findings;
}

// ═══════════════════════════════════════════════════════════════════
// Cross-file Born mixing
// ═══════════════════════════════════════════════════════════════════

class CrossFileInterference {
  final int address;
  final double certainty;
  final double phase;
  final double coherence;
  final bool contradictory;
  final int fileCount;
  final List<String> files;

  const CrossFileInterference({
    required this.address,
    required this.certainty,
    required this.phase,
    required this.coherence,
    required this.contradictory,
    required this.fileCount,
    required this.files,
  });
}

/// Findings at the same spectral address from different files are
/// independent measurements of the same structural role. Born-mix
/// them, compute coherence and contradiction, observe the interference
/// back into the lattice, and return the structured interference map.
List<CrossFileInterference> crossFileMix(
  Map<String, FlowAnalysisResult> rawResults,
  FlowSseLattice lattice,
) {
  final byAddress = <int, List<(String, double, double)>>{};
  for (final entry in rawResults.entries) {
    for (final f in entry.value.findings) {
      byAddress.putIfAbsent(f.address, () => [])
          .add((entry.key, f.certainty, f.phase));
    }
  }

  final results = <CrossFileInterference>[];
  for (final entry in byAddress.entries) {
    if (entry.value.length < 2) continue;
    final arrivals = entry.value.map((e) => (e.$2, e.$3)).toList();
    final (mc, mp) = flowBornMix(arrivals);
    final coh = flowPhaseCoherence(arrivals);
    final contra = flowIsContradictory(arrivals);
    lattice.observe(entry.key, mc);

    final files = entry.value.map((e) => e.$1).toSet().toList();
    if (files.length < 2) continue;

    results.add(CrossFileInterference(
      address: entry.key,
      certainty: mc,
      phase: mp,
      coherence: coh,
      contradictory: contra,
      fileCount: files.length,
      files: files,
    ));
  }

  results.sort((a, b) => a.certainty.compareTo(b.certainty));
  return results;
}

// ═══════════════════════════════════════════════════════════════════
// Top-level API
// ═══════════════════════════════════════════════════════════════════

/// Analyze source for execution-flow findings.
/// Universal mode uses indentation geometry; labeled mode takes
/// explicit (address, lyapunov) pairs per line.
List<FlowFinding> analyzeExecutionFlow(
  String source, {
  double threshold = 0.3,
  Map<int, (int, double)>? nodeLabels,
}) {
  final FlowGraph graph;
  if (nodeLabels != null) {
    graph = _buildLabeledGraph(source, nodeLabels);
  } else {
    graph = extractFlowGraph(source);
  }
  final optimized = optimizeGraph(graph);

  if (optimized.nodes.length < 2) return const [];

  return simulateFlow(optimized, threshold: threshold);
}

/// Build a flow graph from explicit per-line labels.
/// Each entry in [labels] maps line index → (latticeAddress, lyapunov).
/// Lines without labels are classified as PURE.
FlowGraph _buildLabeledGraph(String source, Map<int, (int, double)> labels) {
  final lines = source.split('\n');
  final graph = FlowGraph();
  final nodeIds = <String>[];

  for (var i = 0; i < lines.length; i++) {
    final stripped = lines[i].trim();
    if (stripped.isEmpty) continue;
    if (stripped.startsWith('//') || stripped.startsWith('#')) continue;

    final label = labels[i];
    final addr = label?.$1 ?? kFlowPure;
    final ly = label?.$2 ?? 0.0;

    final nid = 'L$i';
    graph.addNode(FlowNode(
      id: nid,
      address: addr,
      lyapunov: ly,
      sourceLine: i,
      sourceText: stripped,
    ));
    nodeIds.add(nid);
  }

  // sequential edges with early-return guard detection
  for (var i = 0; i < nodeIds.length - 1; i++) {
    final node = graph.nodes[nodeIds[i]]!;
    final text = node.sourceText.toLowerCase();
    if (node.hasAxis(kFlowRestabilizes) &&
        (text.contains('return') || text.contains('break') ||
         text.contains('continue'))) {
      continue;
    }
    graph.addEdge(nodeIds[i], nodeIds[i + 1]);
  }

  return graph;
}

/// -log(worst certainty). Higher = more fragile. Zero = clean.
/// Pass [findings] to skip redundant simulation.
double flowSpectralGap(FlowGraph graph, {
  List<FlowFinding>? findings,
  double? logosCoupling,
}) {
  findings ??= simulateFlow(graph, threshold: 1.0, logosCoupling: logosCoupling);
  if (findings.isEmpty) return 0.0;
  final worst = findings.map((f) => f.certainty).reduce(math.min);
  return -math.log(worst.clamp(1e-15, 1.0));
}

// ═══════════════════════════════════════════════════════════════════
// Scale 2 — inter-file flow graph from co-change topology
// ═══════════════════════════════════════════════════════════════════

/// Build a [FlowGraph] at the inter-file scale from a co-change graph.
/// Nodes are files, addressed by their spectral fingerprint in the
/// co-change Laplacian. K-G derives from the fingerprint via [flowKG] —
/// the dream learns the effective surface from lattice statistics.
///
/// Every node is OR'd with [kFlowResource] so arrivals are collected
/// at every file (at this scale, every file is a structural resource).
FlowGraph buildInterFileFlowGraph(
  CsrGraph csr,
  SpectralBasis basis, {
  List<String>? nodePaths,
}) {
  final n = csr.n;
  if (n < 2 || basis.k < 9) return FlowGraph();

  final fingerprints = basis.spectralFingerprintTable();
  final graph = FlowGraph();

  for (var i = 0; i < n; i++) {
    graph.addNode(FlowNode(
      id: 'f$i',
      address: fingerprints[i] | kFlowResource,
      sourceLine: i,
      sourceText: nodePaths != null && i < nodePaths.length
          ? nodePaths[i]
          : 'f$i',
    ));
  }

  for (var i = 0; i < n; i++) {
    final rowStart = csr.indptr[i];
    final rowEnd = csr.indptr[i + 1];
    for (var p = rowStart; p < rowEnd; p++) {
      final j = csr.indices[p];
      if (j > i) graph.addEdge('f$i', 'f$j');
    }
  }

  return graph;
}

/// Run the full Scale 2 pipeline: simulate on the inter-file graph,
/// dream, and return per-file certainties + structural findings.
InterFileResult? analyzeInterFile(
  CsrGraph csr,
  SpectralBasis basis, {
  List<String>? nodePaths,
  FlowSseLattice? lattice,
}) {
  final graph = buildInterFileFlowGraph(csr, basis, nodePaths: nodePaths);
  if (graph.nodes.length < 2) return null;

  final lat = lattice ?? FlowSseLattice();

  final n = csr.n;
  final degrees = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    degrees[i] = csr.indptr[i + 1] - csr.indptr[i];
  }
  final sorted = List<int>.generate(n, (i) => i)
    ..sort((a, b) => degrees[b].compareTo(degrees[a]));
  final entries = sorted.take(math.min(3, n)).map((i) => 'f$i').toSet();

  final allFindings = simulateFlow(
    graph,
    entryNodes: entries,
    threshold: 1.0,
    maxDepth: 10,
    sseLattice: lat,
  );

  for (var iter = 0; iter < 8; iter++) {
    final before = List<double>.generate(256, (a) => lat.cellMean(a));
    dreamAnalysis(lat);
    var maxShift = 0.0;
    for (var a = 0; a < 256; a++) {
      final d = (lat.cellMean(a) - before[a]).abs();
      if (d > maxShift) maxShift = d;
    }
    if (maxShift < 1.0 / 64.0) break;
  }

  final perFileCertainty = <int, double>{};
  for (final f in allFindings) {
    final idx = int.tryParse(f.nodeId.substring(1));
    if (idx == null) continue;
    final existing = perFileCertainty[idx];
    if (existing == null || f.certainty < existing) {
      perFileCertainty[idx] = f.certainty;
    }
  }

  final structural = allFindings
      .where((f) =>
          lat.isAnomalous(f.address, f.certainty) && f.composite >= 0.1)
      .toList();

  final gap = allFindings.isEmpty
      ? 0.0
      : -math.log(allFindings
          .map((f) => f.certainty)
          .reduce(math.min)
          .clamp(1e-15, 1.0));

  return InterFileResult(
    perFileCertainty: perFileCertainty,
    findings: structural,
    spectralGap: gap,
    lattice: lat,
    nodePaths: nodePaths,
  );
}

class InterFileResult {
  final Map<int, double> perFileCertainty;
  final List<FlowFinding> findings;
  final double spectralGap;
  final FlowSseLattice lattice;
  final List<String>? nodePaths;

  const InterFileResult({
    required this.perFileCertainty,
    required this.findings,
    required this.spectralGap,
    required this.lattice,
    this.nodePaths,
  });

  double? certaintyForPath(String path, Map<String, int> pathToId) {
    final idx = pathToId[path];
    return idx != null ? perFileCertainty[idx] : null;
  }
}

// ═══════════════════════════════════════════════════════════════════
// Scale 3 — temporal flow graph from lattice trajectory
// ═══════════════════════════════════════════════════════════════════

/// Build a [FlowGraph] where nodes are commits (lattice snapshots) and
/// edges are temporal adjacency. Address = [latticeFingerprint] of each
/// snapshot. Merge commits with multiple parents get multiple incoming
/// edges — Born interference at the merge.
FlowGraph buildTemporalFlowGraph(
  List<({int revision, FlowSseLattice lattice, String? commitSha})> points, {
  List<List<int>>? parentIndices,
}) {
  if (points.length < 2) return FlowGraph();

  final graph = FlowGraph();

  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final addr = latticeFingerprint(p.lattice) | kFlowResource;
    graph.addNode(FlowNode(
      id: 'c$i',
      address: addr,
      sourceLine: p.revision,
      sourceText: p.commitSha ?? 'c$i',
    ));
  }

  if (parentIndices != null) {
    for (var i = 0; i < parentIndices.length; i++) {
      for (final parent in parentIndices[i]) {
        if (parent >= 0 && parent < points.length) {
          graph.addEdge('c$parent', 'c$i');
        }
      }
    }
  } else {
    for (var i = 0; i < points.length - 1; i++) {
      graph.addEdge('c$i', 'c${i + 1}');
    }
  }

  return graph;
}

// ═══════════════════════════════════════════════════════════════════
// Memoisation cache — keyed on (absolutePath, modifiedMs)
// ═══════════════════════════════════════════════════════════════════

/// Cached result for a single file. Main-isolate-only.
class FlowAnalysisResult {
  final List<FlowFinding> findings;
  final double spectralGap;
  const FlowAnalysisResult(this.findings, this.spectralGap);

  /// Feed all findings from this result into an SSE lattice.
  void accumulateInto(FlowSseLattice lattice) {
    for (final f in findings) {
      lattice.observe(f.address, f.certainty);
    }
  }

  /// Return a copy keeping only findings that are both statistically
  /// anomalous (SSE lattice) AND structurally interesting (composite > floor).
  FlowAnalysisResult filterBy(FlowSseLattice lattice,
      {double sigma = 1.5, double minComposite = 0.1}) {
    final kept = findings
        .where((f) =>
            lattice.isAnomalous(f.address, f.certainty, sigma: sigma) &&
            f.composite >= minComposite)
        .toList();
    return FlowAnalysisResult(kept, spectralGap);
  }
}

final LruCache<(String, int), FlowAnalysisResult> _flowCache =
    LruCache(maxSize: 256);
final Map<(String, int), Future<FlowAnalysisResult?>> _inFlight = {};

/// Default walker depth — covers a full hypercube traversal (8 axes)
/// with headroom. Reduced once the lattice has reached its factored
/// fixpoint and additional depth contributes no new spectral information.
const int _kDefaultMaxDepth = 30;
const int _kLightMaxDepth = 4;

/// Memoized flow analysis. Computation runs in a worker isolate.
/// [logosCoupling] bypasses cache and adds structural context.
/// [globalCouplingWeights] is the repo-global CharCoupling matrix
/// (128*128 doubles) — when supplied, all eigenAddress computations
/// use the same basis, making lattice addresses coherent across files.
/// [priorMeans] / [priorCounts] are an optional GYAT-derived prior:
/// a 256-cell snapshot of the lifelong lattice's cell means and counts
/// used to bias walker initialisation (familiar addresses get
/// anomaly-seekers, novel addresses get certainty-seekers).
/// [lightweight] = true switches to a shallow walk (depth 4 instead of
/// 30). Use when `lattice.isFactored == true` has been observed —
/// additional depth contributes no new spectral information. Bypasses
/// the cache because shallow results would shadow deeper future calls.
Future<FlowAnalysisResult?> analyzeFlowCached(
  String absolutePath, {
  double? logosCoupling,
  Float64List? globalCouplingWeights,
  Float64List? priorMeans,
  Int32List? priorCounts,
  bool lightweight = false,
}) async {
  final maxDepth = lightweight ? _kLightMaxDepth : _kDefaultMaxDepth;
  final file = File(absolutePath);
  if (!await file.exists()) return null;
  final stat = await file.stat();
  final key = (absolutePath, stat.modified.millisecondsSinceEpoch);

  final usingExtraContext = logosCoupling != null ||
      globalCouplingWeights != null ||
      priorMeans != null ||
      maxDepth != _kDefaultMaxDepth;
  if (!usingExtraContext) {
    final cached = _flowCache.get(key);
    if (cached != null) return cached;
    final existing = _inFlight[key];
    if (existing != null) return existing;
  }

  final future = () async {
    try {
      final source = await file.readAsString();
      final coupling = logosCoupling;
      final globalW = globalCouplingWeights;
      final means = priorMeans;
      final counts = priorCounts;
      final depth = maxDepth;
      final result = await Isolate.run(() =>
          _analyzeSource(source, coupling, globalW, means, counts, depth));
      if (result != null && !usingExtraContext) _flowCache.put(key, result);
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }();

  if (!usingExtraContext) _inFlight[key] = future;
  return future;
}

FlowAnalysisResult? _analyzeSource(
  String source,
  double? logosCoupling,
  Float64List? globalCouplingWeights,
  Float64List? priorMeans,
  Int32List? priorCounts,
  int maxDepth,
) {
  final globalCoupling = globalCouplingWeights != null
      ? CharCoupling.fromWeights(globalCouplingWeights)
      : null;
  final graph = optimizeGraph(
      extractFlowGraph(source, globalCoupling: globalCoupling));
  if (graph.nodes.length < 2) return null;

  // Build a priorNovelty function from the GYAT snapshot when supplied.
  // Novelty = 1 - (cellCount / maxCount) for warmed cells; cold cells
  // are maximally novel (1.0). Familiar cells (high count) get walkers
  // biased toward anomaly-hunting; cold cells get certainty-seekers.
  double Function(int)? novelty;
  if (priorMeans != null && priorCounts != null) {
    var maxCount = 1;
    for (var i = 0; i < priorCounts.length; i++) {
      if (priorCounts[i] > maxCount) maxCount = priorCounts[i];
    }
    final inv = 1.0 / maxCount;
    novelty = (addr) {
      final a = addr & 0xFF;
      final c = priorCounts[a];
      if (c < 8) return 1.0;
      return (1.0 - c * inv).clamp(0.0, 1.0);
    };
  }

  final allFindings = simulateFlow(
    graph,
    threshold: 1.0,
    maxDepth: maxDepth,
    logosCoupling: logosCoupling,
    priorNovelty: novelty,
  );
  final gap = graph.nodes.length >= 3
      ? flowSpectralGap(graph, findings: allFindings)
      : 0.0;
  return FlowAnalysisResult(allFindings, gap);
}
