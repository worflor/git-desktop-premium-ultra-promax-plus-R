// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_blast_radius.dart — the change's historical blast radius.
//
// The co-change manifold knows which files historically move together.
// A file's blast radius is the set of paths that have changed alongside
// it across the repo's history. When a diff touches a file but leaves
// part of that radius untouched, the absence is a reviewable signal: a
// companion change may have been forgotten (the test that mirrors a
// source file, the lockfile that tracks a manifest), or the pair was
// deliberately decoupled. Either reading is worth surfacing — the
// channel states the coupling and lets the reviewer weigh it against
// intent. It never claims causation; co-change is symmetric history.
//
// Nothing here pattern-matches on filenames for *relevance*. Relevance
// comes from the Jaccard co-change history in [FileCouplingMatrix]. The
// only pathname classification is [logosRelationDescriptor], which
// *names* an already-surfaced relationship (source↔test, manifest↔
// lockfile, …) so the reviewer reads a label, not a raw pair.

import 'file_coupling.dart' show FileCouplingMatrix;
import 'logos_git_integrity.dart'
    show LogosRelationDescriptor, kNeutralIntegrity, logosRelationDescriptor;
import 'spectral_constants.dart' show phiDecay1;

/// One file in the change's blast radius that is absent from the diff.
class BlastRadiusFile {
  const BlastRadiusFile({
    required this.path,
    required this.anchor,
    required this.jaccard,
    required this.relation,
    required this.integrity,
    required this.anchorCount,
  });

  /// The untouched file — present in history, absent from the diff.
  final String path;

  /// The changed file whose history pulls [path] in most strongly.
  final String anchor;

  /// Co-change Jaccard between [anchor] and [path], in [0, 1].
  final double jaccard;

  /// Named structural relationship ([anchor] → [path]) when one fires
  /// (source↔test, manifest↔lockfile, …); null when the tie is purely
  /// historical with no nameable shape.
  final LogosRelationDescriptor? relation;

  /// Structural trustworthiness of [path] in [0.1, 1]. Low = vendored /
  /// generated, so its absence carries less weight.
  final double integrity;

  /// How many changed files pull [path] in. >1 means several touched
  /// files all historically co-change with this absent file.
  final int anchorCount;

  /// Ranking key: a strongly-coupled, trustworthy file outranks a
  /// weakly-coupled or generated one.
  double get weight => jaccard * integrity;
}

class _Cand {
  _Cand(this.anchor, this.jaccard, this.relation, this.integrity);
  String anchor;
  double jaccard;
  LogosRelationDescriptor? relation;
  double integrity;
  int pulls = 0;
}

/// Compute the untouched blast radius: files that historically co-change
/// with one of [changedPaths] but are not themselves in the diff.
///
/// A candidate survives when it is either (a) coupled to its anchor at
/// least as strongly as φ⁻¹ ≈ 0.618 of that anchor's *strongest* tie —
/// a per-file relative band, no absolute knob — or (b) carries a named
/// structural relation (source↔test and friends are expected pairs at
/// any strength). Results are ranked by jaccard × integrity so the
/// reviewer sees the strongest, most trustworthy omissions first.
///
/// [perAnchorLimit] / [globalLimit] are presentation caps (token
/// budget), not signal thresholds — they bound how much we show, never
/// what counts as coupled.
List<BlastRadiusFile> computeBlastRadius({
  required FileCouplingMatrix coupling,
  required Set<String> changedPaths,
  required Map<String, double> integrityByPath,
  int perAnchorLimit = 6,
  int globalLimit = 10,
}) {
  if (changedPaths.isEmpty) return const [];
  final best = <String, _Cand>{};

  for (final anchor in changedPaths) {
    // topJaccardNeighbours is symmetric (it consults the lower-triangle
    // mirror), so we must NOT gate on hasJaccardRow — that only sees a
    // file's upper-triangle row and would miss a file whose every tie
    // points to a lexicographically-smaller path. containsPath is the
    // correct "is this file known at all" guard.
    if (!coupling.containsPath(anchor)) continue;
    final neighbours =
        coupling.topJaccardNeighbours(anchor, limit: perAnchorLimit);
    if (neighbours.isEmpty) continue;
    final maxTie = neighbours.first.value;
    if (maxTie <= 0) continue;
    // φ⁻¹ band off the anchor's own strongest tie — scales per file.
    final band = maxTie * phiDecay1;

    for (final e in neighbours) {
      final cand = e.key;
      final j = e.value;
      if (changedPaths.contains(cand)) continue; // present → not missing
      final rel = logosRelationDescriptor(anchor, cand);
      if (j < band && rel == null) continue; // weak and unnameable → drop
      final integ = integrityByPath[cand] ?? kNeutralIntegrity;
      final existing = best[cand];
      if (existing == null) {
        best[cand] = _Cand(anchor, j, rel, integ)..pulls = 1;
      } else {
        existing.pulls += 1;
        if (j > existing.jaccard) {
          existing
            ..anchor = anchor
            ..jaccard = j
            ..relation = rel
            ..integrity = integ;
        }
      }
    }
  }

  final list = best.entries
      .map((e) => BlastRadiusFile(
            path: e.key,
            anchor: e.value.anchor,
            jaccard: e.value.jaccard,
            relation: e.value.relation,
            integrity: e.value.integrity,
            anchorCount: e.value.pulls,
          ))
      .toList()
    ..sort((a, b) => b.weight.compareTo(a.weight));

  if (list.length > globalLimit) return list.sublist(0, globalLimit);
  return list;
}

/// Render the `<blast_radius>` body (no wrapper tag). Returns '' when
/// there is nothing to report — the caller drops the section.
String formatBlastRadiusBlock(List<BlastRadiusFile> files) {
  if (files.isEmpty) return '';
  final n = files.length;
  final buf = StringBuffer();
  buf.writeln(
    'status: populated · $n file${n == 1 ? '' : 's'} sit in this change\'s '
    'historical blast radius — they co-change with the diff across the '
    "repo's history — yet are absent from it. A strong tie left untouched "
    'can mean a companion edit was missed; a deliberate decoupling reads '
    'the same way — weigh it against what the change is reaching for.',
  );
  for (final c in files) {
    final rel = c.relation;
    final relText = rel == null
        ? ''
        : ' ${rel.label}${rel.note != null && rel.note!.isNotEmpty ? ' (${rel.note})' : ''}';
    final multi = c.anchorCount > 1 ? ' ×${c.anchorCount}' : '';
    final lowTrust = c.integrity < phiDecay1 ? ' [low-trust/generated]' : '';
    buf.writeln(
      '${c.anchor} ↔ ${c.path}  J=${c.jaccard.toStringAsFixed(2)}'
      '$relText$multi$lowTrust',
    );
  }
  return buf.toString();
}
