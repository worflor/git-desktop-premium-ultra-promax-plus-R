// LOGOS DIFF ATTENTION — adaptive level-of-detail hunk compactor.
//
// Replaces the binary admit/skip knapsack in [packHunksUnderBudget]
// with a single adaptive pass:
//
//   importance_i = log(1+bytes_i) × (1 + φ_i × (1 + jaccard_i))
//
//       bytes    — every hunk has intrinsic information proportional
//                  to its byte count, regardless of φ. log-concave so
//                  it doesn't overwhelm.
//       φ        — Logos heat-kernel centrality from rankHunksByPhiAsync.
//       jaccard  — token-overlap between + and − sides. Body-rewrite
//                  hunks (same symbol on both sides) rise naturally;
//                  there is no hard floor — they just have higher
//                  importance and therefore a larger budget share.
//
//   target_i = importance_i / Σ importance × budget
//   tier_i   = richest tier t such that render_size(t, hunk_i) ≤ target_i
//
// Tiers, richest → thinnest:
//
//   L4 full      — header + body (same as the old packer)
//   L3 bodyOnly  — header + +/− lines, context lines stripped
//   L2 compact   — header + add/del token sets, both sides visible
//   L1 stub      — one-liner with coords, counts, φ
//   L0 clustered — hunk has no individual rendering; folded into a
//                  single per-file aggregate line with the Logos
//                  topology digest (hunks=, +=, -=, φ_max, φ_sum,
//                  transport, residual, engram wells, union symbols).
//
// No phase-2, no fallback, no hard floors. At every scale from a
// one-line patch to a 10000-hunk migration the same one-pass
// algorithm runs. Tiny diffs give every hunk a target larger than
// the L4 cost and L4 wins. Pathological diffs give most hunks a
// target below the L1 cost and they cluster naturally.
//
// No per-file `diff --git` header overhead: every tier emits its
// own `f="path"` in metadata, so the reviewer always knows the
// parent file from the hunk itself. This removes the chicken-and-egg
// between "headers depend on tiers" and "tiers depend on budget."

import 'dart:math' as math;

import 'logos_hunks.dart'
    show DiffHunk, HunkInteractionDecomposition, HunkRanking;

/// Hunk fidelity tier. Higher index = richer content, more bytes.
enum HunkLod {
  clustered,
  stub,
  compact,
  bodyOnly,
  full,
}

class CompactedHunk {
  const CompactedHunk({
    required this.hunk,
    required this.lod,
    required this.rendered,
    required this.phi,
  });
  final DiffHunk hunk;
  final HunkLod lod;
  final String rendered;
  final double phi;
  int get bytes => rendered.length;
}

class DiffAttentionResult {
  const DiffAttentionResult({
    required this.body,
    required this.perHunk,
    required this.clustered,
    required this.budgetChars,
    required this.renderedChars,
  });
  final String body;
  final List<CompactedHunk> perHunk;
  final List<DiffHunk> clustered;
  final int budgetChars;
  final int renderedChars;

  int get admittedCount => perHunk.length;
  int get clusteredCount => clustered.length;
}

// Identifier grammar matches logos_hunks.dart conceptually, but we
// scan char-codes directly rather than using a Unicode regex — the
// `\p{L}\p{N}` regex profiled as a 10-second cost on large diffs in
// logos_hunks.dart and the same shape appears here. ASCII fast-path,
// code units ≥ 0x80 treated as identifier continuation.
bool _isIdentStart(int c) =>
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    c == 0x5F ||                // _
    c >= 0x80;                  // non-ASCII
bool _isIdentChar(int c) =>
    _isIdentStart(c) || (c >= 0x30 && c <= 0x39); // + digits

class _SideTokens {
  _SideTokens({
    required this.addCounts,
    required this.delCounts,
    required this.bodyOnlyBytes,
  });
  final Map<String, int> addCounts;
  final Map<String, int> delCounts;

  /// Sum of byte-lengths of + and − lines (excluding file-header markers
  /// `+++` / `---`), including the trailing newlines that would be
  /// emitted. Equal to the payload of the L3 bodyOnly render minus the
  /// hunk `@@` header — used to size L3 analytically without rendering.
  final int bodyOnlyBytes;
}

/// Walk a hunk body once and bucket identifier-token counts into the
/// + and − sides. Identifiers of length < 3 are dropped as ambient
/// noise (matches `logos_hunks.dart` convention). Also accumulates
/// the byte-size of the bodyOnly (+/− lines) content so L3 can be
/// sized without a second walk.
_SideTokens _extractSideTokens(DiffHunk h) {
  final adds = <String, int>{};
  final dels = <String, int>{};
  var bodyOnlyBytes = 0;
  // Char-by-char scan over the entire body. On each newline boundary
  // we peek the line-lead char to decide which bucket this line feeds.
  // Identifier runs within + and − lines get tokenised via the same
  // single-pass camelCase-split used in logos_hunks.dart `_tokensOf`.
  final body = h.body;
  final n = body.length;
  var i = 0;
  while (i < n) {
    // Position at start of line. Determine the side.
    final lineStart = i;
    final lead = body.codeUnitAt(i);
    Map<String, int>? target;
    if (lead == 0x2B) {
      // '+' line, skip file-header marker '+++'
      if (!(i + 2 < n &&
          body.codeUnitAt(i + 1) == 0x2B &&
          body.codeUnitAt(i + 2) == 0x2B)) {
        target = adds;
      }
    } else if (lead == 0x2D) {
      // '-' line, skip file-header marker '---'
      if (!(i + 2 < n &&
          body.codeUnitAt(i + 1) == 0x2D &&
          body.codeUnitAt(i + 2) == 0x2D)) {
        target = dels;
      }
    }
    // Scan to end of line.
    var j = i;
    while (j < n && body.codeUnitAt(j) != 0x0A) {
      j++;
    }
    if (target != null) {
      // bodyOnlyBytes tracks the payload length that the L3 bodyOnly
      // renderer would emit for this line, including the \n terminator.
      bodyOnlyBytes += (j - lineStart) + 1;
      // Whole-identifier extraction inside [lineStart, j). Matches the
      // original `_identRe = [\p{L}_][\p{L}\p{N}_]*` regex byte-for-byte
      // on ASCII: no camelCase splitting — refactor-jaccard compares
      // full identifier names like `paintWell` as atoms.
      var k = lineStart;
      while (k < j) {
        while (k < j && !_isIdentStart(body.codeUnitAt(k))) {
          k++;
        }
        if (k >= j) break;
        final pieceStart = k;
        k++;
        while (k < j && _isIdentChar(body.codeUnitAt(k))) {
          k++;
        }
        if (k - pieceStart >= 3) {
          final t = body.substring(pieceStart, k);
          target[t] = (target[t] ?? 0) + 1;
        }
      }
    }
    i = j + 1; // advance past '\n' (or stop at end)
  }
  return _SideTokens(
    addCounts: adds,
    delCounts: dels,
    bodyOnlyBytes: bodyOnlyBytes,
  );
}

/// Upper-bound size of the comment-metadata header emitted by every
/// per-hunk render at every tier (L1..L4). Computed analytically from
/// the ranking so we can size all tiers without string allocation.
int _metaHeaderSize(HunkRanking r, int lod, String filePath) {
  // `<!-- h lod=N f="<path>" phi=X.XXX<residuals> -->\n`
  // Plus L1 adds `o=N n=M +A -D`; L2 adds `+A -D add=... del=...`.
  var n = '<!-- h lod=$lod f="$filePath" phi='.length;
  n += r.phi.toStringAsFixed(3).length;
  if (r.wellName != null) n += ' well='.length + r.wellName!.length;
  if (r.innovationResidual > 0.0) n += ' innov=0.XXX'.length;
  if (r.transportPull > 0.0) n += ' transport=0.XXX'.length;
  if (r.witnessResidual > 0.0) n += ' witness=0.XXX'.length;
  n += ' -->\n'.length;
  return n;
}

/// Analytic size of each tier. Matches the real render byte-for-byte
/// (modulo toStringAsFixed formatting which we account for in
/// [_metaHeaderSize]). Rendering is allocated-once-at-pick-time;
/// sizing happens in a cheap O(1) / O(tokens) path.
int _sizeAtLod(HunkRanking r, HunkLod lod, _SideTokens tokens) {
  final h = r.hunk;
  switch (lod) {
    case HunkLod.full:
      return _metaHeaderSize(r, 4, h.filePath) + h.body.length;
    case HunkLod.bodyOnly:
      return _metaHeaderSize(r, 3, h.filePath) +
          h.header.length +
          1 + // trailing newline on header
          tokens.bodyOnlyBytes;
    case HunkLod.compact:
      // ` +A -B add=x,y,z del=a,b` suffix, plus header line below.
      var n = _metaHeaderSize(r, 2, h.filePath);
      n += ' +${h.additions} -${h.deletions}'.length;
      n += ' add='.length + _tokenListBytes(tokens.addCounts);
      n += ' del='.length + _tokenListBytes(tokens.delCounts);
      n += h.header.length + 1; // newline after header
      return n;
    case HunkLod.stub:
      var n = _metaHeaderSize(r, 1, h.filePath);
      n += ' o=${h.oldStart} n=${h.newStart}'.length;
      n += ' +${h.additions} -${h.deletions}'.length;
      return n;
    case HunkLod.clustered:
      return 0;
  }
}

int _tokenListBytes(Map<String, int> counts) {
  if (counts.isEmpty) return 0;
  // Sorted-desc-by-count list of keys joined by ',' — the same shape
  // `_sortedByCount(counts).join(",")` produces.
  var n = 0;
  for (final k in counts.keys) {
    n += k.length + 1; // +1 for the comma separator
  }
  return n - 1; // trailing ',' removed
}

/// Jaccard overlap of + and − side identifier sets. 0 = no shared
/// symbols; 1 = every non-trivial symbol appears on both sides
/// (pure body-replacement). Used as a smooth multiplier on hunk
/// importance — no hard threshold, no floor.
double _refactorJaccard(_SideTokens t) {
  if (t.addCounts.isEmpty || t.delCounts.isEmpty) return 0.0;
  final addSet = t.addCounts.keys.toSet();
  final delSet = t.delCounts.keys.toSet();
  final inter = addSet.intersection(delSet).length;
  final union = addSet.union(delSet).length;
  if (union == 0) return 0.0;
  return inter / union;
}

String _renderAt(HunkRanking r, HunkLod lod, _SideTokens tokens) {
  final phi = r.phi.toStringAsFixed(3);
  switch (lod) {
    case HunkLod.full:
      return _renderFull(r, phi);
    case HunkLod.bodyOnly:
      return _renderBodyOnly(r, phi);
    case HunkLod.compact:
      return _renderCompact(r, phi, tokens);
    case HunkLod.stub:
      return _renderStub(r, phi);
    case HunkLod.clustered:
      return '';
  }
}

/// Assemble the optional residual/well annotations shared by every
/// individual tier. Each entry is only emitted when the underlying
/// signal is non-trivial (non-zero for numeric channels, present for
/// the well name), so hunks with cold Logos state stay compact while
/// hunks with rich evidence carry it forward to the reviewer.
String _residualAnnotations(HunkRanking r) {
  final buf = StringBuffer();
  if (r.wellName != null) buf.write(' well=${r.wellName}');
  if (r.innovationResidual > 0.0) {
    buf.write(' innov=${r.innovationResidual.toStringAsFixed(3)}');
  }
  if (r.transportPull > 0.0) {
    buf.write(' transport=${r.transportPull.toStringAsFixed(3)}');
  }
  if (r.witnessResidual > 0.0) {
    buf.write(' witness=${r.witnessResidual.toStringAsFixed(3)}');
  }
  return buf.toString();
}

String _renderFull(HunkRanking r, String phi) {
  final h = r.hunk;
  return '<!-- h lod=4 f="${h.filePath}" phi=$phi${_residualAnnotations(r)} -->\n${h.body}';
}

String _renderBodyOnly(HunkRanking r, String phi) {
  final h = r.hunk;
  final buf = StringBuffer();
  buf.write(
      '<!-- h lod=3 f="${h.filePath}" phi=$phi${_residualAnnotations(r)} -->\n');
  buf.writeln(h.header);
  for (final line in h.body.split('\n').skip(1)) {
    if (line.isEmpty) continue;
    final c = line.codeUnitAt(0);
    if (c == 0x2B || c == 0x2D) buf.writeln(line);
  }
  return buf.toString();
}

String _renderCompact(HunkRanking r, String phi, _SideTokens tokens) {
  final h = r.hunk;
  // Include every non-trivial add/del identifier. Compact-tier size
  // grows with hunk complexity, which is what we want: token-rich
  // hunks need more importance to qualify for L2, same as token-rich
  // hunks have larger `log(1+bytes)` and thus larger targets.
  final addList = _sortedByCount(tokens.addCounts);
  final delList = _sortedByCount(tokens.delCounts);
  return '<!-- h lod=2 f="${h.filePath}" phi=$phi +${h.additions}'
      ' -${h.deletions}${_residualAnnotations(r)}'
      ' add=${addList.join(",")} del=${delList.join(",")} -->\n'
      '${h.header}\n';
}

String _renderStub(HunkRanking r, String phi) {
  final h = r.hunk;
  return '<!-- h lod=1 f="${h.filePath}" o=${h.oldStart} n=${h.newStart}'
      ' +${h.additions} -${h.deletions} phi=$phi${_residualAnnotations(r)} -->\n';
}

List<String> _sortedByCount(Map<String, int> counts) {
  if (counts.isEmpty) return const [];
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      if (c != 0) return c;
      return a.key.compareTo(b.key);
    });
  return [for (final e in entries) e.key];
}

/// Render a file-level cluster line sized to [budget] characters.
/// Emits the mandatory aggregates first (file, counts, φ extremes)
/// then progressively adds optional signals (transport, residual,
/// engram wells, top-K touched symbols) in priority order until
/// the next addition would exceed budget. Symbol lists shrink by
/// halving k until a version fits. The result always stays within
/// [budget] — or reaches its minimal form if [budget] is below the
/// mandatory-fields size.
String _renderCluster(
  String filePath,
  List<HunkRanking> members,
  List<_SideTokens> memberTokens,
  int budget,
) {
  if (members.isEmpty) return '';
  var sumAdds = 0;
  var sumDels = 0;
  var phiMax = 0.0;
  var phiSum = 0.0;
  var transportPullMax = 0.0;
  var residualMax = 0.0;
  final symCounts = <String, int>{};
  final wells = <String>{};
  for (var i = 0; i < members.length; i++) {
    final r = members[i];
    final toks = memberTokens[i];
    sumAdds += r.hunk.additions;
    sumDels += r.hunk.deletions;
    phiSum += r.phi;
    if (r.phi > phiMax) phiMax = r.phi;
    if (r.transportPull > transportPullMax) transportPullMax = r.transportPull;
    final res = r.innovationResidual > r.witnessResidual
        ? r.innovationResidual
        : r.witnessResidual;
    if (res > residualMax) residualMax = res;
    if (r.wellName != null) wells.add(r.wellName!);
    toks.addCounts.forEach((k, v) {
      symCounts[k] = (symCounts[k] ?? 0) + v;
    });
    toks.delCounts.forEach((k, v) {
      symCounts[k] = (symCounts[k] ?? 0) + v;
    });
  }

  // Mandatory signal set — always emitted even if it exceeds budget.
  // These are the minimum aggregate facts the reviewer needs to know
  // a file had clustered hunks at all.
  final accepted = <String>[
    'f="$filePath"',
    'hunks=${members.length}',
    '+=$sumAdds',
    '-=$sumDels',
    'phi_max=${phiMax.toStringAsFixed(3)}',
    'phi_sum=${phiSum.toStringAsFixed(3)}',
  ];

  String render(List<String> pieces) =>
      '<!-- cluster ${pieces.join(" ")} -->\n';

  bool tryAdd(String piece) {
    final trial = render([...accepted, piece]);
    if (trial.length > budget) return false;
    accepted.add(piece);
    return true;
  }

  if (transportPullMax > 0.0) {
    tryAdd('transport_max=${transportPullMax.toStringAsFixed(3)}');
  }
  if (residualMax > 0.0) {
    tryAdd('residual_max=${residualMax.toStringAsFixed(3)}');
  }
  if (wells.isNotEmpty) {
    tryAdd('wells=${wells.join(",")}');
  }
  // Sym list: richest version that fits. Start with every symbol and
  // halve until the budget accepts one, or fall through empty.
  if (symCounts.isNotEmpty) {
    final sorted = _sortedByCount(symCounts);
    var k = sorted.length;
    while (k > 0) {
      if (tryAdd('sym=${sorted.take(k).join(",")}')) break;
      k ~/= 2;
    }
  }
  return render(accepted);
}

/// Exact upper bound on the `<logos_diff_attention ...>` wrap tags.
/// Attribute values are unknown pre-emit, so we use the widest possible
/// values: `rendered` ≤ [budget]; `admitted` and `clustered` each ≤
/// [hunkCount]. The returned length is the worst-case skeleton, so
/// reserving it from the budget guarantees the emitted body fits.
int _wrapOverheadBound(int budget, int hunkCount) {
  final b = budget < 1 ? 1 : budget;
  final n = hunkCount < 1 ? 1 : hunkCount;
  final skeleton = '<logos_diff_attention budget="$b" rendered="$b"'
      ' admitted="$n" clustered="$n">\n</logos_diff_attention>\n';
  return skeleton.length;
}

/// Reorder files so that files whose hunks participate in the same
/// dominant Walsh interaction modes appear adjacent. When the
/// interaction decomposition is unavailable, falls back to alphabetical.
///
/// The dominant modes tell us which hunks are ENTANGLED — changing one
/// without considering the others loses information. By placing their
/// parent files next to each other in the packed diff, the reviewer
/// reads interacting hunks in sequence instead of jumping across the
/// diff. The repo's own spectral structure decides the reading order.
List<String> _interactionOrder(
  List<String> files,
  List<HunkRanking> rankings,
  HunkInteractionDecomposition? interaction,
) {
  if (interaction == null ||
      interaction.dominantModes.isEmpty ||
      files.length < 3) {
    return files..sort();
  }

  // Map hunk index → file path. The interaction decomposition's masks
  // reference the top-H hunks by their position in the φ-sorted order
  // (nodeOrder), which matches the rankings list order.
  final hunkToFile = <int, String>{};
  for (var i = 0; i < math.min(rankings.length, interaction.h); i++) {
    hunkToFile[i] = rankings[i].hunk.filePath;
  }

  // Build a per-file-pair interaction weight: sum of |coefficient| over
  // dominant modes where both files have a participating hunk.
  final pairWeight = <String, Map<String, double>>{};
  for (final mode in interaction.dominantModes) {
    // Collect which files participate in this mode.
    final participatingFiles = <String>{};
    for (var bit = 0; bit < interaction.h; bit++) {
      if (mode.mask & (1 << bit) != 0) {
        final fp = hunkToFile[bit];
        if (fp != null) participatingFiles.add(fp);
      }
    }
    // Every pair of participating files gets the mode's |coefficient|.
    final fps = participatingFiles.toList();
    for (var i = 0; i < fps.length; i++) {
      for (var j = i + 1; j < fps.length; j++) {
        final a = fps[i].compareTo(fps[j]) < 0 ? fps[i] : fps[j];
        final b = fps[i].compareTo(fps[j]) < 0 ? fps[j] : fps[i];
        pairWeight.putIfAbsent(a, () => {});
        pairWeight[a]![b] =
            (pairWeight[a]![b] ?? 0) + mode.coefficient.abs();
      }
    }
  }

  if (pairWeight.isEmpty) return files..sort();

  // Greedy nearest-neighbor chain: start from the file with the
  // highest total interaction weight (most entangled), then always
  // visit the unvisited file with the strongest interaction to the
  // current one. Files with no interaction edges sort alphabetically
  // at the end.
  final interactingFiles = <String>{};
  for (final a in pairWeight.keys) {
    interactingFiles.add(a);
    for (final b in pairWeight[a]!.keys) {
      interactingFiles.add(b);
    }
  }

  double weight(String a, String b) {
    final lo = a.compareTo(b) < 0 ? a : b;
    final hi = a.compareTo(b) < 0 ? b : a;
    return pairWeight[lo]?[hi] ?? 0.0;
  }

  // Total interaction weight per file.
  final totalWeight = <String, double>{};
  for (final f in interactingFiles) {
    var w = 0.0;
    for (final g in interactingFiles) {
      if (f != g) w += weight(f, g);
    }
    totalWeight[f] = w;
  }

  // Greedy chain from the most-interacting file.
  final ordered = <String>[];
  final visited = <String>{};
  var current = interactingFiles.reduce(
      (a, b) => (totalWeight[a] ?? 0) > (totalWeight[b] ?? 0) ? a : b);
  ordered.add(current);
  visited.add(current);

  while (visited.length < interactingFiles.length) {
    String? best;
    var bestW = -1.0;
    for (final f in interactingFiles) {
      if (visited.contains(f)) continue;
      final w = weight(current, f);
      if (w > bestW) {
        bestW = w;
        best = f;
      }
    }
    if (best == null) break;
    ordered.add(best);
    visited.add(best);
    current = best;
  }

  // Append non-interacting files alphabetically.
  final remaining = files.where((f) => !visited.contains(f)).toList()..sort();
  return [...ordered, ...remaining];
}

/// Adaptive LOD compactor — see file header for the algorithm.
DiffAttentionResult compactHunksUnderBudget({
  required List<HunkRanking> rankings,
  required int budgetChars,
  double? entanglementRatio,
  HunkInteractionDecomposition? interaction,
}) {
  if (budgetChars <= 0 || rankings.isEmpty) {
    return DiffAttentionResult(
      body: '',
      perHunk: const [],
      clustered: const [],
      budgetChars: budgetChars,
      renderedChars: 0,
    );
  }

  // Precompute identifier-token buckets once per hunk. Reused for
  // refactor-jaccard, L2 compact render, and cluster-digest sym list
  // — single source of truth.
  final tokensFor = <HunkRanking, _SideTokens>{
    for (final r in rankings) r: _extractSideTokens(r.hunk),
  };

  // Importance per hunk — fully emergent from the hunk's own signals.
  // Base term `log(1+bytes)` is strictly positive for any non-empty
  // hunk, so Σ importance > 0 unconditionally and no /zero guard is
  // needed. The multiplicative `(1 + φ × (1 + jaccard))` factor boosts
  // hunks that Logos ranked higher AND hunks where + and − sides
  // share symbols (body-rewrites) — both effects emerge smoothly.
  final importance = <HunkRanking, double>{};
  var sumImp = 0.0;
  for (final r in rankings) {
    final jaccard = _refactorJaccard(tokensFor[r]!);
    final sizeW = math.log(1 + r.hunk.bytes);
    final v = sizeW * (1 + r.phi * (1 + jaccard));
    importance[r] = v;
    sumImp += v;
  }

  // Size every tier analytically (O(1) per tier, no string alloc).
  // We materialise the render string later, only for the tier each
  // hunk actually ends up at — skipping 3 of 4 renders per hunk.
  final sizes = <HunkRanking, Map<HunkLod, int>>{};
  for (final r in rankings) {
    final toks = tokensFor[r]!;
    sizes[r] = <HunkLod, int>{
      for (final t in const [
        HunkLod.full,
        HunkLod.bodyOnly,
        HunkLod.compact,
        HunkLod.stub,
      ])
        t: _sizeAtLod(r, t, toks),
    };
  }

  // Wrap overhead is exactly `<logos_diff_attention budget="B"
  // rendered="R" admitted="A" clustered="C">\n</logos_diff_attention>\n`.
  // We use upper bounds for the still-unknown attribute values
  // (rendered ≤ budget; admitted + clustered ≤ rankings.length) to get
  // a guaranteed-safe overhead — actual emitted wrap is ≤ this, so
  // reserving it keeps the final body ≤ budget. Fully emergent from
  // the input sizes; no magic constant.
  final wrapOverhead = _wrapOverheadBound(budgetChars, rankings.length);
  final effective = math.max(0, budgetChars - wrapOverhead);

  // Target budget per hunk — proportional to importance.
  final target = <HunkRanking, int>{};
  for (final r in rankings) {
    target[r] = (importance[r]! / sumImp * effective).floor();
  }

  // Each hunk picks the richest tier whose render fits its target.
  // Below the stub tier means "cluster me" — no individual line.
  final tier = <HunkRanking, HunkLod>{};
  for (final r in rankings) {
    final s = sizes[r]!;
    HunkLod chosen = HunkLod.clustered;
    for (final t in const [
      HunkLod.full,
      HunkLod.bodyOnly,
      HunkLod.compact,
      HunkLod.stub,
    ]) {
      if (s[t]! <= target[r]!) {
        chosen = t;
        break;
      }
    }
    tier[r] = chosen;
  }

  // Emit. File-alphabetical, hunk-index within file. Each file's
  // cluster line (if any members dropped to L0) is appended after
  // the individual renders for that file.
  final byFile = <String, List<HunkRanking>>{};
  for (final r in rankings) {
    (byFile[r.hunk.filePath] ??= []).add(r);
  }

  final buf = StringBuffer();
  final perHunk = <CompactedHunk>[];
  final clustered = <DiffHunk>[];

  final files = _interactionOrder(byFile.keys.toList(), rankings, interaction);
  for (final fp in files) {
    final group = byFile[fp]!
      ..sort((a, b) => a.hunk.hunkIndex.compareTo(b.hunk.hunkIndex));
    final clusterMembers = <HunkRanking>[];
    for (final r in group) {
      if (tier[r]! == HunkLod.clustered) {
        clusterMembers.add(r);
        clustered.add(r.hunk);
      } else {
        // Render only the chosen tier — the whole point of the
        // analytic sizer above. 3× fewer string allocations per hunk
        // on mid-to-large diffs where tiers vary under budget pressure.
        final text = _renderAt(r, tier[r]!, tokensFor[r]!);
        buf.write(text);
        perHunk.add(CompactedHunk(
          hunk: r.hunk,
          lod: tier[r]!,
          rendered: text,
          phi: r.phi,
        ));
      }
    }
    if (clusterMembers.isNotEmpty) {
      // The cluster line inherits the pooled target of its members —
      // they forfeited individual rendering, so their combined share
      // of the budget underwrites the aggregate line.
      var clusterBudget = 0;
      final clusterTokens = <_SideTokens>[];
      for (final r in clusterMembers) {
        clusterBudget += target[r]!;
        clusterTokens.add(tokensFor[r]!);
      }
      buf.write(
        _renderCluster(fp, clusterMembers, clusterTokens, clusterBudget),
      );
    }
  }

  final inner = buf.toString();
  final wrapped = StringBuffer()
    ..writeln('<logos_diff_attention budget="$budgetChars"'
        ' rendered="${inner.length}"'
        ' admitted="${perHunk.length}" clustered="${clustered.length}"'
        '${entanglementRatio != null ? ' entanglement="${entanglementRatio.toStringAsFixed(2)}"' : ''}'
        '>')
    ..write(inner)
    ..writeln('</logos_diff_attention>');
  final body = wrapped.toString();

  return DiffAttentionResult(
    body: body,
    perHunk: perHunk,
    clustered: clustered,
    budgetChars: budgetChars,
    renderedChars: body.length,
  );
}
