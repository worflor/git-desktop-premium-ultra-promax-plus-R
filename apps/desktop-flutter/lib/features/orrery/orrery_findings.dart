// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:ui' show Offset;

import '../../i18n/gen/strings.g.dart';
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
  thrash, // a file reorganising back and forth — motion without progress
  reshuffle, // a quiet-looking commit that moved which files are central
  forecast, // where connectivity is heading — toward a split or a dense mass
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

  /// True when the finding names a specific commit moment (anchor carries a
  /// "step · sha" ref). Position and trend findings anchor to the present as a
  /// jump target, but they are properties of the repo, not events — surfaces
  /// use this to decide whether standing on [stepIndex] means anything.
  bool get isEventAnchored => anchor.contains('·');
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
  'md',
  'txt',
  'json',
  'yaml',
  'yml',
  'toml',
  'lock',
  'cfg',
  'ini',
  'properties',
  'xml',
  'csv',
  'log',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'svg',
  'ico',
  'webp',
  'ttf',
  'otf',
  'woff',
  'woff2',
};

bool _isCodeFile(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false; // LICENSE, Makefile, … — treat as non-code here
  return !_nonCodeExt.contains(path.substring(dot + 1).toLowerCase());
}

/// Public view of the source-file gate, so every surface that ranks files
/// (findings here, the compare bench's movers) draws the same line between
/// actionable code and docs/config noise.
bool isCodeFilePath(String path) => _isCodeFile(path);

/// Last two path segments, for a readable-but-located file name.
String _shortPath(String path) {
  final parts = path.split('/').where((s) => s.isNotEmpty).toList();
  return parts.length <= 2 ? path : parts.sublist(parts.length - 2).join('/');
}

List<OrreryFinding> computeFindings(OrreryModel model) {
  return <OrreryFinding>[
    ..._positionFindings(model),
    ..._thrashFinding(model),
    ..._reshuffleFinding(model),
    ..._forecastFinding(model),
    ..._regimeFindings(model),
    ..._archetypeTrendFinding(model),
  ];
}

/// The one forward-looking finding: where the codebase's connectivity is
/// *heading*. The spectral gap reads high when the graph is one tight community
/// and low as it approaches splitting into loosely-coupled halves. Fit its
/// recent trend; call out a strong, sustained slide toward a split (or toward a
/// single dense mass) while there's still time to choose. Framed on the
/// observed trend with an explicit "if this holds" — never a fabricated
/// countdown. Stays silent unless the trend is both strong and near a boundary.
List<OrreryFinding> _forecastFinding(OrreryModel model) {
  final n = model.stepCount;
  if (n < 12) return const <OrreryFinding>[];

  double gLo = double.infinity, gHi = -double.infinity;
  for (final s in model.steps) {
    if (s.gap < gLo) gLo = s.gap;
    if (s.gap > gHi) gHi = s.gap;
  }
  final range = (gHi - gLo).abs();
  if (range < 1e-6) return const <OrreryFinding>[]; // flat — nothing to call

  // Least-squares slope of gap over the recent half (the current trajectory).
  final lo = n ~/ 2;
  final m = n - lo;
  double sx = 0, sy = 0, sxx = 0, sxy = 0;
  for (int i = lo; i < n; i++) {
    final x = (i - lo).toDouble();
    final y = model.steps[i].gap;
    sx += x;
    sy += y;
    sxx += x * x;
    sxy += x * y;
  }
  final denom = m * sxx - sx * sx;
  if (denom.abs() < 1e-9) return const <OrreryFinding>[];
  final slope = (m * sxy - sx * sy) / denom;

  // Predicted change over the window, as a fraction of gap's own range.
  final trend = slope * (m - 1) / range;
  final cur = model.steps[n - 1].gap;
  final headStep = n - 1;

  // Heading toward a split: connectivity sliding and already in the low third.
  if (trend <= -0.6 && cur < gLo + 0.35 * range) {
    return <OrreryFinding>[
      OrreryFinding(
        kind: OrreryFindingKind.forecast,
        stepIndex: headStep,
        headline: t.orrery.findings.forecastSplit,
        anchor: t.orrery.anchor.trend,
      ),
    ];
  }
  // Heading toward one dense mass: connectivity climbing into the high third.
  if (trend >= 0.6 && cur > gHi - 0.35 * range) {
    return <OrreryFinding>[
      OrreryFinding(
        kind: OrreryFindingKind.forecast,
        stepIndex: headStep,
        headline: t.orrery.findings.forecastConsolidate,
        anchor: t.orrery.anchor.trend,
      ),
    ];
  }
  return const <OrreryFinding>[];
}

/// Thrashing — a file that keeps getting reorganised back and forth: it travels
/// a long way through the manifold but ends up near where it started. A net-new
/// signal CodeScene can't produce (it has no spatial embedding); here the
/// hyperbolic path length vs net displacement makes it plain. Emits at most one
/// — the worst offender — and only when the motion is real.
List<OrreryFinding> _thrashFinding(OrreryModel model) {
  if (model.stepCount < 6) return const <OrreryFinding>[];
  final headStep = model.stepCount - 1;
  OrreryNode? worst;
  double worstRatio = 0;
  for (final node in model.nodes) {
    final path = node.path;
    if (path == null || !_isCodeFile(path)) continue;
    if (node.positions.length <= headStep || node.positions[headStep] == null) {
      continue; // must still exist at the present
    }
    Offset? first, prev;
    double pathLen = 0;
    int present = 0;
    for (final p in node.positions) {
      if (p == null) continue;
      present++;
      first ??= p;
      if (prev != null) pathLen += (p - prev).distance;
      prev = p;
    }
    if (present < 5 || first == null || prev == null) continue;
    if (pathLen < 0.6) continue; // it has to actually move to be thrashing
    final net = (prev - first).distance;
    final ratio = pathLen / (net + 0.05);
    if (ratio > worstRatio) {
      worstRatio = ratio;
      worst = node;
    }
  }
  if (worst == null || worstRatio < 3.2) return const <OrreryFinding>[];
  return <OrreryFinding>[
    OrreryFinding(
      kind: OrreryFindingKind.thrash,
      stepIndex: headStep,
      nodeId: worst.id,
      headline: t.orrery.findings.thrash(name: _shortPath(worst.path!)),
      anchor: t.orrery.anchor.thrash,
    ),
  ];
}

/// A silent role-reassignment — a commit where many files changed how central
/// they are, yet the codebase's overall connectivity barely moved. It reads as
/// routine in a diff but quietly reshuffled the structure (a Berry-phase-like
/// event: big internal rotation, small global change). Net-new, and the
/// complement of a regime change (which is a *large* connectivity jump).
List<OrreryFinding> _reshuffleFinding(OrreryModel model) {
  final n = model.stepCount;
  if (n < 8) return const <OrreryFinding>[];

  // Per-step mean motion of files present on both sides of the step.
  final motion = List<double>.filled(n, 0);
  for (int s = 1; s < n; s++) {
    double sum = 0;
    int count = 0;
    for (final node in model.nodes) {
      if (s >= node.positions.length) continue;
      final a = node.positions[s - 1];
      final b = node.positions[s];
      if (a == null || b == null) continue;
      sum += (b - a).distance;
      count++;
    }
    motion[s] = count >= 8 ? sum / count : 0; // need enough files to mean much
  }

  final sorted = motion.sublist(1)..sort();
  final median = sorted.isEmpty ? 0.0 : sorted[sorted.length ~/ 2];
  if (median <= 1e-9) return const <OrreryFinding>[];

  double gLo = double.infinity, gHi = -double.infinity;
  for (final st in model.steps) {
    gLo = gLo < st.gap ? gLo : st.gap;
    gHi = gHi > st.gap ? gHi : st.gap;
  }
  final gSpan = (gHi - gLo).abs() < 1e-9 ? 1.0 : (gHi - gLo);

  int best = -1;
  double bestMotion = 0;
  for (int s = (n * 0.2).ceil(); s < n; s++) {
    final gapChange =
        (model.steps[s].gap - model.steps[s - 1].gap).abs() / gSpan;
    if (model.steps[s].regimeChange) continue; // that's the *loud* kind
    if (motion[s] < 2.4 * median) continue; // a genuine internal spike
    if (gapChange > 0.18) continue; // overall shape held still
    if (motion[s] > bestMotion) {
      bestMotion = motion[s];
      best = s;
    }
  }
  if (best < 0) return const <OrreryFinding>[];
  final s = model.steps[best];
  return <OrreryFinding>[
    OrreryFinding(
      kind: OrreryFindingKind.reshuffle,
      stepIndex: best,
      headline: t.orrery.findings.reshuffle,
      anchor: '${best + 1} · ${s.shortSha}',
    ),
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
      headline: t.orrery.findings.hub(name: _shortPath(hub.path!)),
      anchor: t.orrery.anchor.core,
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
    drifts
        .add((node: node, drift: node.positions[headStep]!.distance - birthR));
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
            headline: t.orrery.findings.driftOut(name: name),
            anchor: t.orrery.anchor.drift,
          )
        : OrreryFinding(
            kind: OrreryFindingKind.driftIn,
            stepIndex: headStep,
            nodeId: dr.node.id,
            headline: t.orrery.findings.driftIn(name: name),
            anchor: t.orrery.anchor.drift,
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
      headline: t.orrery.findings.regime,
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
        headline: t.orrery.findings.tangleTrend,
        anchor: t.orrery.anchor.trend,
      ),
    ];
  }
  if (delta < -0.8) {
    return [
      OrreryFinding(
        kind: OrreryFindingKind.clarify,
        stepIndex: headStep,
        headline: t.orrery.findings.clarifyTrend,
        anchor: t.orrery.anchor.trend,
      ),
    ];
  }
  return const <OrreryFinding>[];
}
