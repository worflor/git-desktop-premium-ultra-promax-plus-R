import 'orrery_model.dart';

/// Plain-language, commit-anchored findings derived from the trajectory — the
/// "so what" layer that turns the disk from a pretty animation into something a
/// developer would open on a Tuesday. Each finding names a real structural
/// event, anchors it to a commit, and (where there's an action) ends in an
/// imperative. The spectral machinery stays out of the wording.
///
/// v1 sources only the *scalar-curve* events (regime changes, archetype shifts)
/// — these come from per-snapshot spectral quantities that are stable today.
/// Position-based findings (a file drifting core↔periphery, a hub/God-file) wait
/// until UASE stabilises the embedding, so we never surface a claim the layout
/// can't back up.

enum OrreryFindingKind { regime, tangle, clarify, identity }

class OrreryFinding {
  final OrreryFindingKind kind;
  final int stepIndex; // jump anchor
  final String headline; // plain language, ends in an imperative where actionable
  final String anchor; // "13 · a1b2c3d"

  const OrreryFinding({
    required this.kind,
    required this.stepIndex,
    required this.headline,
    required this.anchor,
  });
}

// "Tangledness" of each structural archetype. tree / modular / crystalline are
// all clean architectures (low); poisson is random; bulk (everything dense) and
// goe (chaotic) are genuinely tangled (high). Only a move UP this scale (toward
// goe/bulk) is reported as tangling, and only a move DOWN as clarifying — so
// tree↔modular reads as a neutral identity shift, not a false alarm.
const Map<String, int> _archetypeOrder = <String, int>{
  'crystalline': 1,
  'tree': 1,
  'modular': 1,
  'poisson': 3,
  'bulk': 4,
  'goe': 5,
};

String? _previousArchetype(OrreryModel model, int i, String current) {
  for (int j = i - 1; j >= 0; j--) {
    final a = model.steps[j].archetype;
    if (a.isNotEmpty && a != current) return a;
  }
  return null;
}

List<OrreryFinding> computeFindings(OrreryModel model) {
  final out = <OrreryFinding>[];
  for (int i = 0; i < model.stepCount; i++) {
    final s = model.steps[i];
    final anchor = '${i + 1} · ${s.shortSha}';

    if (s.archetypeShift && s.archetype.isNotEmpty) {
      final prev = _previousArchetype(model, i, s.archetype);
      final cr = _archetypeOrder[s.archetype] ?? 3;
      final pr = prev == null ? 3 : (_archetypeOrder[prev] ?? 3);
      if (prev == null) {
        out.add(OrreryFinding(
          kind: OrreryFindingKind.identity,
          stepIndex: i,
          headline: 'Structure settled into a ${s.archetype} shape.',
          anchor: anchor,
        ));
      } else if (cr > pr) {
        out.add(OrreryFinding(
          kind: OrreryFindingKind.tangle,
          stepIndex: i,
          headline:
              'Structure tangled here: $prev → ${s.archetype}. Worth a look — this is where maintainability usually starts to slide.',
          anchor: anchor,
        ));
      } else if (cr < pr) {
        out.add(OrreryFinding(
          kind: OrreryFindingKind.clarify,
          stepIndex: i,
          headline:
              'Structure clarified: $prev → ${s.archetype} — a cleaner shape emerged.',
          anchor: anchor,
        ));
      } else {
        out.add(OrreryFinding(
          kind: OrreryFindingKind.identity,
          stepIndex: i,
          headline: 'Structural identity shifted ($prev → ${s.archetype}).',
          anchor: anchor,
        ));
      }
    } else if (s.regimeChange) {
      out.add(OrreryFinding(
        kind: OrreryFindingKind.regime,
        stepIndex: i,
        headline:
            'The codebase reorganized sharply here — its connectivity jumped. Review what split off or merged.',
        anchor: anchor,
      ));
    }
  }
  return out;
}
