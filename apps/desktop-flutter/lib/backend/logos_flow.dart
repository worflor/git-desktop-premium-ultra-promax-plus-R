// Filament — execution-flow analysis on code graphs.
// AR(2) oscillator + Born mixing, language-agnostic.

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

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
// Line classification — spectral (from graph structure)
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

/// Lattice address + Lyapunov from indentation geometry alone.
(int, double) _classifyLine(
  String line,
  int lineIndex,
  int prevIndent,
  int nextIndent,
  int maxIndent,
  int totalLines,
  double fiedlerEstimate,
  double betweennessEstimate,
) {
  final stripped = line.trimLeft();
  if (stripped.isEmpty) return (kFlowPure, 0.0);

  // skip pure comments
  if (stripped.startsWith('//') ||
      stripped.startsWith('#') ||
      stripped.startsWith('*') ||
      stripped.startsWith('/*')) {
    return (kFlowPure, 0.0);
  }

  final indent = _indentation(line);
  var addr = 0;
  var ly = 0.0;

  // structural Lyapunov: combination of Fiedler estimate and
  // betweenness estimate, scaled to [0, 3]
  ly = fiedlerEstimate * betweennessEstimate * 3.0;

  // scope entry (indentation increases significantly after this line)
  if (nextIndent > indent + 2) {
    addr |= kFlowLifecycle;
  }

  // scope transition (indentation changes significantly)
  if ((indent - prevIndent).abs() > 4 || (indent - nextIndent).abs() > 4) {
    if (ly > 0.3) {
      addr |= kFlowAsync;
    }
  }

  // deep scope (high indentation relative to max = structurally interior)
  if (maxIndent > 0 && indent > maxIndent * 0.6) {
    addr |= kFlowResource;
  }

  // scope exit returning to shallow depth after deep excursion
  if (prevIndent > indent + 4 && indent <= 4) {
    addr |= kFlowRestabilizes;
  }

  // first line
  if (lineIndex == 0) {
    addr |= kFlowLifecycle;
  }

  if (addr == 0) addr = kFlowPure;
  return (addr, ly);
}

// ═══════════════════════════════════════════════════════════════════
// Graph extraction from source text
// ═══════════════════════════════════════════════════════════════════

/// Flow graph from indentation structure.
FlowGraph extractFlowGraph(String source) {
  final lines = source.split('\n');
  final graph = FlowGraph();
  final nodeIds = <String>[];

  // pre-compute indentation array
  final indents = List<int>.generate(lines.length, (i) => _indentation(lines[i]));
  final maxIndent = indents.fold<int>(0, math.max);

  // structural estimates from indentation transitions
  final indentCounts = <int, int>{};
  for (final ind in indents) {
    indentCounts[ind] = (indentCounts[ind] ?? 0) + 1;
  }
  final totalNonEmpty = indents.where((i) => i >= 0).length;

  for (var i = 0; i < lines.length; i++) {
    final stripped = lines[i].trim();
    if (stripped.isEmpty) continue;
    if (stripped.startsWith('//') || stripped.startsWith('#') ||
        stripped.startsWith('*') || stripped.startsWith('/*')) continue;

    final prevInd = i > 0 ? indents[i - 1] : 0;
    final nextInd = i + 1 < lines.length ? indents[i + 1] : 0;

    // Fiedler estimate from indentation change magnitude
    final indentDelta = ((indents[i] - prevInd).abs() +
        (indents[i] - nextInd).abs()) / (maxIndent + 1);

    // Betweenness estimate from how common this indentation level is
    final levelCount = indentCounts[indents[i]] ?? 1;
    final betweenness = 1.0 - (levelCount / totalNonEmpty);

    final (addr, ly) = _classifyLine(
      lines[i], i, prevInd, nextInd,
      maxIndent, lines.length,
      indentDelta.clamp(0.0, 1.0),
      betweenness.clamp(0.0, 1.0),
    );

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

  for (var i = 0; i < nodeIds.length - 1; i++) {
    final node = graph.nodes[nodeIds[i]]!;
    final text = node.sourceText.toLowerCase();
    // early-return guard — skip edge, path exits here
    if (node.hasAxis(kFlowRestabilizes) &&
        (text.contains('return') || text.contains('break') ||
         text.contains('continue'))) {
      continue; // don't connect to next line
    }
    graph.addEdge(nodeIds[i], nodeIds[i + 1]);
  }

  // scope-exit edges (indentation drops create cross-edges)
  final indentStack = <(String, int)>[];
  for (var i = 0; i < nodeIds.length; i++) {
    final node = graph.nodes[nodeIds[i]]!;
    final indent = indents[node.sourceLine];

    if (i > 0) {
      final prevNode = graph.nodes[nodeIds[i - 1]]!;
      final prevIndent = indents[prevNode.sourceLine];
      if (indent > prevIndent) {
        indentStack.add((nodeIds[i - 1], prevIndent));
      } else if (indent < prevIndent) {
        while (indentStack.isNotEmpty && indentStack.last.$2 >= indent) {
          final (scopeEntry, _) = indentStack.removeLast();
          graph.addEdge(nodeIds[i], scopeEntry);
        }
      }
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

enum FlowBugKind { staleValue, temporalShift, contextInversion }

class FlowFinding {
  final String nodeId;
  final int sourceLine;
  final String sourceText;
  final double certainty;
  final double phase;
  final FlowBugKind kind;
  final int pathCount;

  const FlowFinding({
    required this.nodeId,
    required this.sourceLine,
    required this.sourceText,
    required this.certainty,
    required this.phase,
    required this.kind,
    this.pathCount = 1,
  });

  String get severity {
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

/// DFS with AR(2) oscillator + Born mixing at resource nodes.
/// [logosCoupling] adds a structural arrival from the Logos graph.
List<FlowFinding> simulateFlow(
  FlowGraph graph, {
  Set<String>? entryNodes,
  double threshold = 0.3,
  int maxDepth = 30,
  double? logosCoupling,
}) {
  entryNodes ??= {
    for (final n in graph.nodes.values)
      if (n.hasAxis(kFlowLifecycle)) n.id,
  };
  if (entryNodes.isEmpty && graph.nodes.isNotEmpty) {
    entryNodes = {graph.nodes.values.first.id};
  }

  final arrivals = <String, List<(double, double)>>{};
  final edgeCount = graph.adj.values.fold<int>(0, (s, e) => s + e.length);
  final stepBudget = [graph.nodes.length * edgeCount];

  for (final start in entryNodes) {
    if (!graph.nodes.containsKey(start)) continue;
    if (stepBudget[0] <= 0) break;
    final visited = {start};
    _dfsPropagate(
        graph, start, FlowOscillator(), 0, maxDepth, visited, arrivals,
        stepBudget);
  }

  // Born-mix at each resource node.
  final findings = <FlowFinding>[];
  for (final entry in arrivals.entries) {
    final arrs = entry.value;
    if (arrs.isEmpty) continue;
    final mixInput = logosCoupling != null
        ? [...arrs, (logosCoupling, 0.0)]
        : arrs;
    final (mc, mp) = flowBornMix(mixInput);
    if (mc < threshold) {
      final node = graph.nodes[entry.key]!;
      findings.add(FlowFinding(
        nodeId: entry.key,
        sourceLine: node.sourceLine,
        sourceText: node.sourceText,
        certainty: mc,
        phase: mp,
        kind: _classifyPhase(mp),
        pathCount: arrs.length,
      ));
    }
  }

  findings.sort((a, b) => a.certainty.compareTo(b.certainty));
  return findings;
}

const int _kMaxArrivalsPerNode = 8;

void _dfsPropagate(
  FlowGraph graph,
  String nid,
  FlowOscillator osc,
  int depth,
  int maxDepth,
  Set<String> visited,
  Map<String, List<(double, double)>> arrivals,
  List<int> stepBudget,
) {
  if (depth > maxDepth || stepBudget[0] <= 0) return;
  stepBudget[0]--;

  final node = graph.nodes[nid];
  if (node == null) return;

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

  if (node.hasAxis(kFlowResource)) {
    final list = arrivals.putIfAbsent(nid, () => []);
    if (list.length >= _kMaxArrivalsPerNode) return;
    list.add((osc.certainty, osc.phase));
  }

  for (final edge in graph.adj[nid] ?? <FlowEdge>[]) {
    if (visited.contains(edge.target)) continue;
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
    childOsc.step(tKr, tKi, tGr, edge.hamming);
    visited.add(edge.target);
    _dfsPropagate(
        graph, edge.target, childOsc, depth + 1, maxDepth, visited, arrivals,
        stepBudget);
    visited.remove(edge.target);
  }
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
// Memoisation cache — keyed on (absolutePath, modifiedMs)
// ═══════════════════════════════════════════════════════════════════

/// Cached result for a single file. Main-isolate-only.
class FlowAnalysisResult {
  final List<FlowFinding> findings;
  final double spectralGap;
  const FlowAnalysisResult(this.findings, this.spectralGap);
}

final LruCache<(String, int), FlowAnalysisResult> _flowCache =
    LruCache(maxSize: 256);
final Map<(String, int), Future<FlowAnalysisResult?>> _inFlight = {};

/// Memoized flow analysis. Computation runs in a worker isolate.
/// [logosCoupling] bypasses cache and adds structural context.
Future<FlowAnalysisResult?> analyzeFlowCached(
  String absolutePath, {
  double? logosCoupling,
}) async {
  final file = File(absolutePath);
  if (!await file.exists()) return null;
  final stat = await file.stat();
  final key = (absolutePath, stat.modified.millisecondsSinceEpoch);

  if (logosCoupling == null) {
    final cached = _flowCache.get(key);
    if (cached != null) return cached;
    final existing = _inFlight[key];
    if (existing != null) return existing;
  }

  final future = () async {
    try {
      final source = await file.readAsString();
      final coupling = logosCoupling;
      final result = await Isolate.run(() => _analyzeSource(source, coupling));
      if (result != null && logosCoupling == null) _flowCache.put(key, result);
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }();

  if (logosCoupling == null) _inFlight[key] = future;
  return future;
}

FlowAnalysisResult? _analyzeSource(String source, double? logosCoupling) {
  final graph = optimizeGraph(extractFlowGraph(source));
  if (graph.nodes.length < 2) return null;
  final allFindings = simulateFlow(
      graph, threshold: 1.0, logosCoupling: logosCoupling);
  final gap = graph.nodes.length >= 3
      ? flowSpectralGap(graph, findings: allFindings)
      : 0.0;
  return FlowAnalysisResult(allFindings, gap);
}
