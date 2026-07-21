// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

/// Pure, dependency-free logic for mapping a Cursor CLI effort/thinking/fast
/// selection onto the exact model ids that `cursor-agent models` enumerates.
///
/// Why this exists: Cursor's headless `-p` mode accepts ONLY the exact ids from
/// its catalog — the interactive `base[effort=…]` override is rejected there
/// (verified 2026-07: "Cannot use this model"). Cursor also bakes
/// effort/thinking/fast INTO the id, with an INCONSISTENT suffix order across
/// families (`…-thinking-high` vs `…-high-thinking`, and bases that literally
/// contain an effort word like `gpt-5.1-codex-max-low`). So the effort slider
/// and fast toggle can't pass a flag — they must swap to a sibling id that
/// actually exists. We parse each id into (base, thinking, effort-rank, fast),
/// group by (base, thinking), and route to the nearest EXISTING sibling.
///
/// Safety invariant: [resolveCursorModel] only ever returns an id present in
/// the supplied catalog, and falls back to the selected id verbatim on any
/// miss — so a parse quirk or unseen naming scheme can never emit an id Cursor
/// would reject; at worst the slider/toggle is a no-op for that model.
library;

/// A Cursor model id decomposed into its routable dimensions.
class CursorModelParts {
  final String base;
  final bool thinking;

  /// Effort rank 0..5; a bare id with no effort word defaults to 2 (medium).
  final int rank;
  final bool fast;

  const CursorModelParts(this.base, this.thinking, this.rank, this.fast);
}

/// Cursor's effort words → rank. `none` sits below `low`; `extra-high` (two
/// tokens) folds into the same rank as `xhigh`.
const Map<String, int> cursorEffortRank = {
  'none': 0,
  'low': 1,
  'medium': 2,
  'high': 3,
  'xhigh': 4,
  'max': 5,
};

/// The app's canonical slider levels (`effortLevels`, low→max) → cursor rank.
const Map<String, int> cursorCanonicalRank = {
  'low': 1,
  'medium': 2,
  'high': 3,
  'xhigh': 4,
  'max': 5,
};

/// Parse a Cursor model id into (base, thinking, effort-rank, fast). Robust to
/// the two observed suffix orderings and to bases that end in an effort word.
CursorModelParts parseCursorModelId(String id) {
  final tokens = id.split('-');
  var fast = false;
  var thinking = false;
  // `fast` is always the final token when present.
  if (tokens.isNotEmpty && tokens.last == 'fast') {
    fast = true;
    tokens.removeLast();
  }
  // `thinking` may TRAIL the effort (…-high-thinking) — strip that form first.
  if (tokens.isNotEmpty && tokens.last == 'thinking') {
    thinking = true;
    tokens.removeLast();
  }
  int? rank;
  if (tokens.length >= 2 &&
      tokens[tokens.length - 2] == 'extra' &&
      tokens.last == 'high') {
    rank = cursorEffortRank['xhigh'];
    tokens.removeRange(tokens.length - 2, tokens.length);
  } else if (tokens.isNotEmpty && cursorEffortRank.containsKey(tokens.last)) {
    rank = cursorEffortRank[tokens.last];
    tokens.removeLast();
  }
  // …or `thinking` may LEAD the effort (…-thinking-high) — strip the remainder.
  if (!thinking && tokens.isNotEmpty && tokens.last == 'thinking') {
    thinking = true;
    tokens.removeLast();
  }
  return CursorModelParts(tokens.join('-'), thinking, rank ?? 2, fast);
}

/// All ids sharing a (base, thinking) identity, indexed by effort rank then
/// fast-ness so a slider/toggle can look up the exact sibling to run.
class CursorFamily {
  // effort rank → fast? → exact model id.
  final Map<int, Map<bool, String>> byRank = {};

  void add(int rank, bool fast, String id) {
    (byRank[rank] ??= {}).putIfAbsent(fast, () => id);
  }

  Set<int> get ranks => byRank.keys.toSet();
}

String _familyKey(String base, bool thinking) => '$base $thinking';

/// Group a catalog of Cursor ids into (base, thinking) families.
Map<String, CursorFamily> buildCursorFamilies(Iterable<String> models) {
  final families = <String, CursorFamily>{};
  for (final id in models) {
    final p = parseCursorModelId(id);
    (families[_familyKey(p.base, p.thinking)] ??= CursorFamily())
        .add(p.rank, p.fast, id);
  }
  return families;
}

/// Ids that should show the effort slider: their family spans ≥2 effort levels
/// to slide between.
Set<String> cursorEffortCapableIds(
  Iterable<String> models,
  Map<String, CursorFamily> families,
) {
  final out = <String>{};
  for (final id in models) {
    final p = parseCursorModelId(id);
    final fam = families[_familyKey(p.base, p.thinking)];
    if (fam != null && fam.ranks.length >= 2) out.add(id);
  }
  return out;
}

/// Ids that should show the fast toggle: the plain id of a plain/`-fast` pair,
/// so the toggle upgrades to the `-fast` sibling. An already-`-fast` id gets no
/// toggle (pick the plain sibling from the list to go back), avoiding a dead
/// control.
Set<String> cursorFastCapableIds(
  Iterable<String> models,
  Map<String, CursorFamily> families,
) {
  final out = <String>{};
  for (final id in models) {
    final p = parseCursorModelId(id);
    if (p.fast) continue;
    final atRank = families[_familyKey(p.base, p.thinking)]?.byRank[p.rank];
    if (atRank != null && atRank.containsKey(true)) out.add(id);
  }
  return out;
}

/// Given a selected Cursor id + desired canonical effort/fast, return the
/// EXISTING sibling id to actually run. Falls back to [modelId] whenever there
/// is no better real match, so it can never emit an id Cursor would reject.
String resolveCursorModel(
  String modelId,
  Map<String, CursorFamily> families, {
  String? effort,
  bool fast = false,
}) {
  final parts = parseCursorModelId(modelId);
  final family = families[_familyKey(parts.base, parts.thinking)];
  if (family == null) return modelId;
  final targetRank = effort != null
      ? (cursorCanonicalRank[effort] ?? parts.rank)
      : parts.rank;
  final wantFast = fast || parts.fast;
  // Snap to the nearest effort level the family actually offers.
  var bestRank = parts.rank;
  var bestDist = 1 << 30;
  for (final r in (family.ranks.toList()..sort())) {
    final d = (r - targetRank).abs();
    if (d < bestDist) {
      bestDist = d;
      bestRank = r;
    }
  }
  final atRank = family.byRank[bestRank];
  if (atRank == null) return modelId;
  // Prefer the requested fast-ness; fall back to the other if it's absent.
  return atRank[wantFast] ?? atRank[!wantFast] ?? modelId;
}
