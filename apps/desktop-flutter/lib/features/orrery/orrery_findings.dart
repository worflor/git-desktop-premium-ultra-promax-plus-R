import 'orrery_model.dart';

/// Plain-language, commit-anchored findings derived from the trajectory — the
/// "so what" layer that turns the disk from a pretty animation into something a
/// developer would open on a Tuesday. Each finding names a real structural
/// event or property, anchors it to a commit or file, and (where there's an
/// action) ends in an imperative. The spectral machinery stays out of the
/// wording, and we'd rather emit nothing than a finding we can't stand behind.
///
/// Sources, most-actionable first:
///   * Position-based (a structural hub, a file drifting core↔periphery) —
///     trustworthy only because the embedding is UASE-stabilised (a shared
///     basis, no per-frame teleport). Restricted to source files.
///   * Regime changes — sharp connectivity jumps in history.
///   * Archetype TREND — one robust early-vs-late summary, not the noisy
///     per-snapshot flips (the classifier oscillates near boundaries).
enum OrreryFindingKind {
  hub,
  driftOut,
  driftIn,
  regime,
  tangle,
  clarify,
  identity,
}

class OrreryFinding {
  final OrreryFindingKind kind;
  final int stepIndex; // jump anchor
  final int? nodeId; // file this finding is about, if any (for highlight)
  final String headline; // plain language, ends in an imperative where useful
  final String anchor; // "13 · a1b2c3d" or "core"

  const OrreryFinding({
    required this.kind,
    required this.stepIndex,
    required this.headline,
    required this.anchor,
    this.nodeId,
  });
}

// "Tangledness" of each structural archetype. tree / modular / crystalline are
// clean architectures (low); poisson is random; bulk and goe are tangled.
const Map<String, int> _archetypeOrder = <String, int>{
  'crystalline': 1,
  'tree': 1,
  'modular': 1,
  'poisson': 3,
  'bulk': 4,
  'goe': 5,
};

// Extensions that aren't source — docs/config co-change with everything and
// would dominate the "hub"/"drift" findings without being actionable code.
const Set<String> _nonCodeExt = <String>{
  'md', 'txt', 'json', 'yaml', 'yml', 'toml', 'lock', 'cfg', 'ini',
  'properties', 'xml', 'csv', 'log', 'png', 'jpg', 'jpeg', 'gif', 'svg',
  'ico', 'webp', 'ttf', 'otf', 'woff', 'woff2',
};

bool _isCodeFile(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false; // LICENSE, Makefile, … — treat as non-code here
  return !_nonCodeExt.contains(path.substring(dot + 1).toLowerCase());
}

/// Last two path segments, for a readable-but-located file name.
String _shortPath(String path) {
  final parts = path.split('/').where((s) => s.isNotEmpty).toList();
  return parts.length <= 2 ? path : parts.sublist(parts.length - 2).join('/');
}

List<OrreryFinding> computeFindings(OrreryModel model) {
  return <OrreryFinding>[
    ..._positionFindings(model),
    ..._regimeFindings(model),
    ..._archetypeTrendFinding(model),
  ];
}

/// Hub + drift — actionable, file-level, source-only, de-duplicated.
List<OrreryFinding> _positionFindings(OrreryModel model) {
  final out = <OrreryFinding>[];
  if (model.stepCount < 2) return out;
  final headStep = model.stepCount - 1;

  bool present(OrreryNode node) =>
      node.path != null &&
      _isCodeFile(node.path!) &&
      node.positions.length > headStep &&
      node.positions[headStep] != null;

  // The structural centre of gravity at the present.
  OrreryNode? hub;
  double hubRadius = 2.0;
  for (final node in model.nodes) {
    if (!present(node)) continue;
    final r = node.positions[headStep]!.distance;
    if (r < hubRadius) {
      hubRadius = r;
      hub = node;
    }
  }
  if (hub != null) {
    out.add(OrreryFinding(
      kind: OrreryFindingKind.hub,
      stepIndex: headStep,
      nodeId: hub.id,
      headline:
          '${_shortPath(hub.path!)} sits at the structural core — the system reorganises around it. Treat changes here as high blast-radius.',
      anchor: 'core',
    ));
  }

  // Files that travelled furthest between core and rim over their lifetime.
  final drifts = <({OrreryNode node, double drift})>[];
  for (final node in model.nodes) {
    if (!present(node) || node.id == hub?.id) continue; // don't double-report
    double? birthR;
    for (final p in node.positions) {
      if (p != null) {
        birthR = p.distance;
        break;
      }
    }
    if (birthR == null) continue;
    drifts.add((node: node, drift: node.positions[headStep]!.distance - birthR));
  }
  drifts.sort((a, b) => b.drift.abs().compareTo(a.drift.abs()));
  var emitted = 0;
  for (final dr in drifts) {
    if (emitted >= 2 || dr.drift.abs() < 0.28) break;
    final name = _shortPath(dr.node.path!);
    out.add(dr.drift > 0
        ? OrreryFinding(
            kind: OrreryFindingKind.driftOut,
            stepIndex: headStep,
            nodeId: dr.node.id,
            headline:
                '$name has drifted from the core toward the edge — it’s decoupling from the system. Either it’s being retired, or it’s quietly rotting.',
            anchor: 'drift',
          )
        : OrreryFinding(
            kind: OrreryFindingKind.driftIn,
            stepIndex: headStep,
            nodeId: dr.node.id,
            headline:
                '$name has migrated toward the core — it’s becoming load-bearing. Make sure it’s well-tested before more depends on it.',
            anchor: 'drift',
          ));
    emitted++;
  }
  return out;
}

/// Sharp connectivity jumps — the "something reorganised here" events.
List<OrreryFinding> _regimeFindings(OrreryModel model) {
  final out = <OrreryFinding>[];
  for (int i = 0; i < model.stepCount; i++) {
    final s = model.steps[i];
    if (!s.regimeChange) continue;
    out.add(OrreryFinding(
      kind: OrreryFindingKind.regime,
      stepIndex: i,
      headline:
          'The codebase reorganized sharply here — its connectivity jumped. Review what split off or merged.',
      anchor: '${i + 1} · ${s.shortSha}',
    ));
  }
  return out;
}

/// One robust archetype finding from the early-vs-late trend — averages over
/// thirds so the per-snapshot oscillation (the classifier sitting near
/// archetype boundaries) can't manufacture a dozen false "tangled here" flips.
List<OrreryFinding> _archetypeTrendFinding(OrreryModel model) {
  final n = model.stepCount;
  final third = n ~/ 3;
  if (third < 2) return const <OrreryFinding>[];

  double avgTangle(int lo, int hi) {
    double sum = 0;
    int count = 0;
    for (int i = lo; i < hi; i++) {
      final r = _archetypeOrder[model.steps[i].archetype];
      if (r != null) {
        sum += r;
        count++;
      }
    }
    return count == 0 ? double.nan : sum / count;
  }

  final early = avgTangle(0, third);
  final late = avgTangle(n - third, n);
  if (early.isNaN || late.isNaN) return const <OrreryFinding>[];
  final delta = late - early;
  final headStep = n - 1;
  if (delta > 0.8) {
    return [
      OrreryFinding(
        kind: OrreryFindingKind.tangle,
        stepIndex: headStep,
        headline:
            'Over its history the codebase has trended toward a more tangled structure — its connectivity is getting denser and less modular.',
        anchor: 'trend',
      ),
    ];
  }
  if (delta < -0.8) {
    return [
      OrreryFinding(
        kind: OrreryFindingKind.clarify,
        stepIndex: headStep,
        headline:
            'Over its history the codebase has trended toward a cleaner structure — it’s separating into clearer modules.',
        anchor: 'trend',
      ),
    ];
  }
  return const <OrreryFinding>[];
}
