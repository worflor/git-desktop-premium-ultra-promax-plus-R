// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: LicenseRef-WLCSL-1.0
// See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

// logos_commit_axis.dart — the engine's commit coordinate
//
// The Logos engine has always been a HISTORY object: `collectLogosGitStats`
// walks a window of `git log` oldest→newest, assigns every commit a
// monotonic index, and derives every per-file series against that index
// (`perFileCommitIndices`, `perFileCommitClock`). What it never kept was the
// coordinate itself — the index→hash mapping was computed and thrown away,
// so nothing downstream could ask "where on this axis is commit X?".
//
// That gap is why reviewing a commit used to require standing a second
// pipeline next to the engine. With the axis retained, a commit is just a
// position, the working tree is the position one past the end, and evidence
// splits into past / at / future by integer comparison.
//
// WHAT THIS DELIBERATELY DOES NOT STORE
//
// A commit→paths map. It is tempting (the walk has the paths in hand) and it
// is wrong twice over: the axis is windowed and `--no-merges`, so it would be
// a partial answer that *looks* total, and the caller that wants a commit's
// paths is resolving a diff anyway — `git diff --name-status` answers exactly,
// for any commit, including merges and commits older than the window. The
// engine should not hold a lossy copy of something git answers precisely.
//
// It also does not store commit subjects. `LogosCommitHyperedge` already
// keeps the ones the graph cares about, and `git show -s` covers the single
// commit a review is actually about.
//
// COST
//
// Four index-aligned arrays plus the hash list and its inverse: on the
// standard 1000-commit window, ~110 KB per engine, ~0.5 MB across the
// resolver's 5-engine LRU. It is built inside the walk that already runs, so
// the marginal git cost is zero — no second `log`, no second cache, no second
// staleness key. That last point is the load-bearing one: a lazily-built side
// index would have been a per-site cache with its own lifetime, which is the
// shape this codebase's OOM postmortem specifically rules out.

import 'dart:typed_data';

/// The ordered commit coordinate a [LogosGitStats] was built against.
///
/// Index 0 is the OLDEST commit in the window and [length] - 1 is the
/// newest, matching the order `collectLogosGitStats` folds its statistics in
/// (oldest→newest, so the volatility EWMA weights recent commits most).
class LogosCommitAxis {
  /// Full commit OIDs, index-aligned, oldest→newest.
  ///
  /// Full-width only (40 hex for SHA-1, 64 for SHA-256). Abbreviated OIDs are
  /// never accepted by [indexOf]: resolving a prefix is git's job via
  /// `rev-parse`, and doing it here would silently pick one of several
  /// matches. Callers resolve first, then look up.
  final List<String> hashes;

  /// Commit meaningfulness at each index — `inferCommitMeaningfulness`'s
  /// weight, clamped to [0, 1]. A ritual/generated commit scores near 0.
  ///
  /// Declared as `List<double>` but populated with a [Float64List], the same
  /// widened-type/compact-storage pattern `perFileCommitIndices` uses for its
  /// `Int32List` values. The width is what lets [emptyAxis] be a genuine
  /// compile-time constant, since a typed-data list can never be one.
  final List<double> stepAt;

  /// The semantic clock *through and including* the commit at each index:
  /// `clockAt[i] == sum(stepAt[0..i])`. This is the same clock
  /// `perFileCommitClock` samples, so the two compare directly — which is
  /// why it is 64-bit rather than 32 despite the narrow range.
  final List<double> clockAt;

  /// Author of each commit, as an index into [authors], or -1 when git
  /// reported no author email. Interned because a repo's 1000 commits
  /// typically come from a handful of people.
  final List<int> authorAt;

  /// Distinct author emails, referenced by [authorAt].
  final List<String> authors;

  final Map<String, int> _byHash;

  LogosCommitAxis({
    required this.hashes,
    required this.stepAt,
    required this.clockAt,
    required this.authorAt,
    required this.authors,
  }) : _byHash = {
          for (var i = 0; i < hashes.length; i++) hashes[i]: i,
        } {
    assert(stepAt.length == hashes.length);
    assert(clockAt.length == hashes.length);
    assert(authorAt.length == hashes.length);
  }

  const LogosCommitAxis._empty()
      : hashes = const [],
        stepAt = const [],
        clockAt = const [],
        authorAt = const [],
        authors = const [],
        _byHash = const {};

  /// The axis of an engine with no located history — a repo the walk found
  /// nothing in, or stats synthesised by hand. Const so it can be the
  /// default of `LogosGitStats`'s const constructor.
  static const LogosCommitAxis emptyAxis = LogosCommitAxis._empty();

  int get length => hashes.length;
  bool get isEmpty => hashes.isEmpty;
  bool get isNotEmpty => hashes.isNotEmpty;

  /// The total semantic time the window spans.
  double get totalClock => clockAt.isEmpty ? 0.0 : clockAt[clockAt.length - 1];

  /// The newest commit on the axis, or null when empty.
  String? get tip => hashes.isEmpty ? null : hashes[hashes.length - 1];

  /// Where [fullHash] sits on the axis, or null when it is not on it.
  ///
  /// A null answer is NOT "no such commit" — it has two ordinary causes that
  /// callers must keep distinct from each other and from a bad OID:
  ///
  ///  - the commit is older than the stats window (1000 commits by default);
  ///  - the commit is a MERGE. The stats walk runs `--no-merges`, so no merge
  ///    commit is ever on the axis, including `HEAD` on a freshly-merged
  ///    branch.
  ///
  /// The second one is the trap: it makes "not on the axis" a routine
  /// condition for perfectly current commits, not an edge case for ancient
  /// ones. Callers model it with an explicit off-axis case rather than a null
  /// index — see `AxisAnchor` in review_target.dart.
  int? indexOf(String fullHash) => _byHash[fullHash];

  /// Whether [fullHash] is on the axis at all.
  bool contains(String fullHash) => _byHash.containsKey(fullHash);

  String? authorAtIndex(int index) {
    if (index < 0 || index >= authorAt.length) return null;
    final a = authorAt[index];
    return a >= 0 && a < authors.length ? authors[a] : null;
  }

  /// Semantic time elapsed between two axis positions, inclusive of [to].
  double clockBetween(int from, int to) {
    if (isEmpty) return 0.0;
    final lo = from.clamp(0, length - 1);
    final hi = to.clamp(0, length - 1);
    if (hi < lo) return 0.0;
    final before = lo == 0 ? 0.0 : clockAt[lo - 1];
    return clockAt[hi] - before;
  }
}

/// Re-weight a diff probe's source paths by what happened to them AFTER the
/// change being reviewed.
///
/// The engine is always built at HEAD, so reviewing an old commit means every
/// statistic around it — volatility, coupling, who-knows — already includes
/// that commit's future. Truncating the engine to hide that would be the
/// wrong move twice: it costs a full rebuild, and it throws away the single
/// strongest cheap prior that something in the change needed fixing. Every
/// later rewrite of these lines is somebody, at some point, disagreeing with
/// the code under review.
///
/// So the future is not hidden and not merely disclaimed — it is aimed. Each
/// source path's weight is scaled by
///
///     1 + (touches after the anchor / touches in total)
///
/// which is unit-free, bounded to [1, 2], and read entirely off the data: a
/// file rewritten at every subsequent opportunity doubles its pull on the
/// diffusion, a file never touched again keeps exactly the weight it had.
/// There is no constant here to tune.
///
/// Returns [sourceWeights] unchanged for a [WorkingTipAnchor] — there is no
/// "after" for work that has not landed — and whenever the anchor gives no
/// position to bisect at.
Map<String, double> retrospectiveFocusWeights({
  required Map<String, double> sourceWeights,
  required int? afterIndex,
  required Map<String, List<int>> perFileCommitIndices,
}) {
  if (afterIndex == null || sourceWeights.isEmpty) return sourceWeights;
  final out = <String, double>{};
  for (final entry in sourceWeights.entries) {
    final touches = perFileCommitIndices[entry.key];
    if (touches == null || touches.isEmpty) {
      out[entry.key] = entry.value;
      continue;
    }
    final future = futureTouchCount(touches, afterIndex);
    out[entry.key] = entry.value * (1.0 + future / touches.length);
  }
  return out;
}

/// One file's standing in the repository, for an audit of settled code.
class RegionFact {
  final String path;

  /// Commits that touched it inside the stats window.
  final int touches;

  /// Axis position of its most recent touch, or null when the window never
  /// saw it — which for an audit is the LOUDEST signal available: nothing in
  /// recent history has disturbed this file at all.
  final int? lastTouchIndex;

  /// Churn EWMA. Comparable across files in the same repository.
  final double volatility;

  /// 0..1; low means the file reads as generated or ritual rather than
  /// authored.
  final double integrity;

  /// Whether any reviewed pull request ever covered it. False is the single
  /// most direct "nobody has looked here" prior there is — it measures
  /// absence of examination rather than proxying for it.
  final bool humanReviewed;

  const RegionFact({
    required this.path,
    required this.touches,
    required this.lastTouchIndex,
    required this.volatility,
    required this.integrity,
    required this.humanReviewed,
  });
}

/// Assemble the per-file standing of a region under audit.
///
/// Everything here is a measurement off git and the engine's own statistics,
/// never an inference: an auditor that is told "this file was written once
/// four hundred commits ago and no review has ever covered it" is reading a
/// fact, and a model asked to guess at the same thing would invent one.
List<RegionFact> regionFacts({
  required Iterable<String> paths,
  required Map<String, int> touches,
  required Map<String, List<int>> perFileCommitIndices,
  required Map<String, double> volatility,
  required Map<String, double> integrityByPath,
  required Map<String, Set<String>> reviewersByPath,
}) {
  final facts = <RegionFact>[];
  for (final path in paths) {
    final series = perFileCommitIndices[path];
    facts.add(RegionFact(
      path: path,
      touches: touches[path] ?? 0,
      lastTouchIndex:
          series == null || series.isEmpty ? null : series[series.length - 1],
      volatility: volatility[path] ?? 0.0,
      // An unseen file has no measured integrity; 0.85 is the same neutral
      // the rest of the engine reads for absent entries.
      integrity: integrityByPath[path] ?? 0.85,
      humanReviewed: (reviewersByPath[path] ?? const <String>{}).isNotEmpty,
    ));
  }
  return facts;
}

/// How often each of [paths] was revisited after the change under review,
/// heaviest first, skipping paths nothing touched again.
///
/// The observable behind retrospective review, and deliberately an observable
/// rather than an inference: these are counts of real commits in real history.
/// "This file was rewritten seven times after the change you are reading" is
/// something a reviewer can act on; a model asked to guess at it would
/// invent.
List<MapEntry<String, int>> revisitsAfter({
  required Iterable<String> paths,
  required int? afterIndex,
  required Map<String, List<int>> perFileCommitIndices,
  int limit = 6,
}) {
  if (afterIndex == null) return const [];
  final counts = <MapEntry<String, int>>[];
  for (final path in paths) {
    final touches = perFileCommitIndices[path];
    if (touches == null || touches.isEmpty) continue;
    final n = futureTouchCount(touches, afterIndex);
    if (n > 0) counts.add(MapEntry(path, n));
  }
  counts.sort((a, b) => b.value.compareTo(a.value));
  return counts.length > limit ? counts.sublist(0, limit) : counts;
}

/// How many times [touchIndices] records a touch STRICTLY AFTER [afterIndex].
///
/// The one thing hindsight is actually for: reviewing a commit retroactively,
/// the number of times its files were rewritten afterwards is the strongest
/// cheap prior that something there needed fixing. Every later rewrite is
/// somebody, at some point, disagreeing with the code under review.
///
/// [touchIndices] is a per-file series out of `LogosGitStats.perFileCommitIndices`,
/// which the stats walk emits in ascending order — so this is a binary search,
/// not a scan, and stays cheap when applied across every path in a change.
int futureTouchCount(List<int> touchIndices, int afterIndex) {
  var lo = 0;
  var hi = touchIndices.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (touchIndices[mid] <= afterIndex) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return touchIndices.length - lo;
}
