import 'dart:convert' show LineSplitter;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'correlatedness_hunk_sort.dart'
    show CorrelatednessContext, seriateByHunkFiedler;
import 'engram_fit.dart';
import 'git.dart';
import 'git_result.dart';
import 'logos_git.dart' show LogosGit;
import 'logos_git_integrity.dart';

// Re-export so callers that only import file_coupling.dart can still
// construct the context — the changes panel and tests historically
// treat this file as the entry point for coupling-related types.
export 'correlatedness_hunk_sort.dart' show CorrelatednessContext;

/// Separator token planted into `git log` custom formats so downstream
/// parsers can identify commit boundaries without regex. Chosen to be
/// unambiguous vs filename characters (ASCII only, no whitespace, no
/// git-ref-legal character). Shared across every call site that parses
/// `--format=${logCommitSeparator}%H` output.
const String logCommitSeparator = '__C__';
const String _logMetaSep = '\u001f';

/// Co-change coupling: files appearing in the same commit over and over are
/// *semantically* related. This is the truth git already holds — we just have
/// to read it out and cluster the current change set by it.
/// Built once per repo (keyed by HEAD hash) and reused across every render.
/// The symbol axis is layered on top per change-set — same shape as the
/// jaccard storage but computed from identifier overlap in the current
/// working tree rather than from git history. See [computeSymbolCoupling].
/// ─── Storage geometry ──────────────────────────────────────────────────
/// The matrix is a sparse symmetric `nFiles × nFiles` floating-point
/// table. Two of them — historical jaccard and current symbol overlap.
/// The hot accessors are `score(a, b)` (called per edge in graph
/// builds), `coherenceFor(paths)` (called per commit during tag
/// profile builds), and row iteration (called per node in graph
/// candidate discovery).
/// **Internal storage is CSR (compressed sparse row).** Path strings
/// are interned to integer ids once at construction. Each row's
/// non-zero entries live in a contiguous `(colIdx, value)` slice
/// sorted by column id. Lookups are binary search over a small slice
/// — typically O(log 50). Memory is roughly 12 bytes per non-zero
/// (int32 colIdx + f64 value), versus ~64+ bytes per nested-map
/// entry. For a 1000-file repo with avg degree 50, the matrix
/// shrinks from ~6MB of map overhead to ~600KB of typed-array data.
/// **The public API is preserved.** `jaccard` and `symbol` are
/// available as Map getters that lazily materialise from the CSR
/// — for callers that haven't migrated to the new accessors, they
/// see the old shape unchanged. New callers should prefer
/// [containsPath], [jaccardKeysOf], and the existing
/// [score]/[coherenceFor] methods, all of which talk to the CSR
/// directly without materialising any maps.
class FileCouplingMatrix {
  /// Path at row id. Sorted alphabetically for determinism + so the
  /// CSR colIdx slices are stably ordered for binary search.
  final List<String> paths;
  final Map<String, int> _pathToId;

  /// `_jRowPtr[i+1] - _jRowPtr[i]` is the non-zero count for row i.
  final Int32List _jRowPtr;

  /// Column ids for each row's non-zero entries, sorted ascending so
  /// the per-row slice supports binary search.
  final Int32List _jColIdx;

  /// Jaccard coefficient values, parallel to [_jColIdx].
  final Float64List _jValues;

  final Int32List _sRowPtr;
  final Int32List _sColIdx;
  final Float64List _sValues;

  final String headHash;
  final int commitsAnalyzed;

  Map<String, Map<String, double>>? _jaccardMapView;
  Map<String, Map<String, double>>? _symbolMapView;

  // Lazy mirror CSR for the lower triangle of the jaccard matrix.
  // Built on first use so `fullJaccardRowOf` / `topJaccardNeighbours`
  // can yield lex-smaller neighbours in O(rowLen) time instead of
  // O(i · log k) binary-searching every smaller row. See
  // [_ensureJaccardMirrorBuilt] for the geometry.
  Int32List? _jMirrorRowPtr;
  Int32List? _jMirrorColIdx;
  Float64List? _jMirrorValues;

  FileCouplingMatrix._({
    required this.paths,
    required Map<String, int> pathToId,
    required this.headHash,
    required this.commitsAnalyzed,
    required Int32List jRowPtr,
    required Int32List jColIdx,
    required Float64List jValues,
    required Int32List sRowPtr,
    required Int32List sColIdx,
    required Float64List sValues,
  })  : _pathToId = pathToId,
        _jRowPtr = jRowPtr,
        _jColIdx = jColIdx,
        _jValues = jValues,
        _sRowPtr = sRowPtr,
        _sColIdx = sColIdx,
        _sValues = sValues;

  /// Public constructor — accepts the legacy nested-map shape and
  /// converts to CSR internally. Builders that already produce the
  /// nested map (`computeFileCoupling`) don't need to change. Tests
  /// that hand-built matrices via map literals continue to work after
  /// dropping the `const` keyword (CSR storage can't be const).
  factory FileCouplingMatrix({
    required Map<String, Map<String, double>> jaccard,
    required String headHash,
    required int commitsAnalyzed,
    Map<String, Map<String, double>> symbol = const {},
  }) {
    // Union of every path that appears in either jaccard or symbol.
    // Sorted for determinism so colIdx ordering is reproducible.
    final pathSet = <String>{};
    for (final entry in jaccard.entries) {
      pathSet.add(entry.key);
      pathSet.addAll(entry.value.keys);
    }
    for (final entry in symbol.entries) {
      pathSet.add(entry.key);
      pathSet.addAll(entry.value.keys);
    }
    final paths = pathSet.toList()..sort();
    final pathToId = <String, int>{};
    for (var i = 0; i < paths.length; i++) {
      pathToId[paths[i]] = i;
    }

    final j = _buildSymmetricCsr(jaccard, pathToId, paths.length);
    final s = _buildSymmetricCsr(symbol, pathToId, paths.length);

    return FileCouplingMatrix._(
      paths: List<String>.unmodifiable(paths),
      pathToId: pathToId,
      headHash: headHash,
      commitsAnalyzed: commitsAnalyzed,
      jRowPtr: j.rowPtr,
      jColIdx: j.colIdx,
      jValues: j.values,
      sRowPtr: s.rowPtr,
      sColIdx: s.colIdx,
      sValues: s.values,
    );
  }

  /// Coupling score for a pair — maximum of historical co-change and
  /// structural symbol overlap. The two axes are independent evidence;
  /// neither suppresses the other. New files have zero history, so symbol
  /// carries them. Old files use whichever axis is stronger.
  /// Implementation is two binary searches over the CSR row slices:
  /// O(log k) where k is the source row's degree. For typical k≈50 in
  /// real repos this is ~6 comparisons per lookup — comfortably faster
  /// than two nested-map hashmap accesses.
  /// CSR storage is upper-triangle (only `(min(i,j), max(i,j))` edges
  /// are materialised). The lookup canonicalises the pair before the
  /// binary search.
  double score(String a, String b) {
    if (a == b) return 1.0;
    final i = _pathToId[a];
    final j = _pathToId[b];
    if (i == null || j == null) return 0.0;
    final lo = i < j ? i : j;
    final hi = i < j ? j : i;
    final hist = _csrLookup(_jRowPtr, _jColIdx, _jValues, lo, hi);
    final sym = _csrLookup(_sRowPtr, _sColIdx, _sValues, lo, hi);
    return hist > sym ? hist : sym;
  }

  /// Return a copy with symbol overlap data merged in. Called once per
  /// change-set update; the rest of the pipeline consumes the merged matrix
  /// transparently through [score].
  /// The new matrix shares the jaccard CSR (immutable) but builds a
  /// fresh symbol CSR over the union of the existing path set and any
  /// new paths in [sym]. New paths get appended to the path id space.
  FileCouplingMatrix withSymbol(Map<String, Map<String, double>> sym) {
    // Fast path: no new paths in symbol → reuse the existing path id
    // space directly without rebuilding the union.
    var hasNewPaths = false;
    for (final entry in sym.entries) {
      if (!_pathToId.containsKey(entry.key)) {
        hasNewPaths = true;
        break;
      }
      for (final neighbour in entry.value.keys) {
        if (!_pathToId.containsKey(neighbour)) {
          hasNewPaths = true;
          break;
        }
      }
      if (hasNewPaths) break;
    }
    if (!hasNewPaths) {
      final newSym = _buildSymmetricCsr(sym, _pathToId, paths.length);
      return FileCouplingMatrix._(
        paths: paths,
        pathToId: _pathToId,
        headHash: headHash,
        commitsAnalyzed: commitsAnalyzed,
        jRowPtr: _jRowPtr,
        jColIdx: _jColIdx,
        jValues: _jValues,
        sRowPtr: newSym.rowPtr,
        sColIdx: newSym.colIdx,
        sValues: newSym.values,
      );
    }
    // Slow path: new paths in [sym] expand the universe. We do NOT
    // materialise `jaccard` back to a map and re-feed the constructor
    // — that's a CSR → Map → CSR round-trip, expensive enough to be
    // its own performance regression. Instead we rebuild the path id
    // space, remap the existing jaccard CSR's column indices into the
    // new id space directly (no intermediate map), and build the
    // symbol CSR fresh against the expanded path set.
    final pathSet = <String>{...paths};
    for (final entry in sym.entries) {
      pathSet.add(entry.key);
      pathSet.addAll(entry.value.keys);
    }
    final newPaths = pathSet.toList()..sort();
    final newPathToId = <String, int>{};
    for (var i = 0; i < newPaths.length; i++) {
      newPathToId[newPaths[i]] = i;
    }
    // Old-id → new-id permutation. The existing CSR holds edges keyed
    // by old ids; this maps them into the new sorted id space without
    // touching the values.
    final oldToNew = Int32List(paths.length);
    for (var i = 0; i < paths.length; i++) {
      oldToNew[i] = newPathToId[paths[i]]!;
    }
    final remappedJaccard = _remapCsr(
      _jRowPtr, _jColIdx, _jValues, oldToNew, newPaths.length,
    );
    final newSym = _buildSymmetricCsr(sym, newPathToId, newPaths.length);
    return FileCouplingMatrix._(
      paths: List<String>.unmodifiable(newPaths),
      pathToId: newPathToId,
      headHash: headHash,
      commitsAnalyzed: commitsAnalyzed,
      jRowPtr: remappedJaccard.rowPtr,
      jColIdx: remappedJaccard.colIdx,
      jValues: remappedJaccard.values,
      sRowPtr: newSym.rowPtr,
      sColIdx: newSym.colIdx,
      sValues: newSym.values,
    );
  }

  /// Coherence of a *set* of files: the mean of all pairwise scores.
  /// Returns 1.0 for ≤1 files (trivially coherent — nothing to compare).
  /// Confidence gating: a brand-new repo with a handful of commits will
  /// produce *false-confident* Jaccard scores — every pair appears
  /// together because every commit touched every file once. We gate
  /// coherence on the matrix's underlying commit count, returning the
  /// max-uncertainty prior (0.5) when there isn't enough data to trust
  /// the signal. Matches the BornMixer's confidence-gate philosophy
  /// applied at the coherence level.
  /// Threshold of 50 commits chosen so that typical refactor churn
  /// inside a feature branch (a few dozen commits) doesn't produce
  /// spurious "tight coupling" reports before the history is
  /// statistically meaningful.
  double coherenceFor(Iterable<String> paths) {
    final list = paths.toList();
    if (list.length < 2) return 1.0;
    if (commitsAnalyzed <= 0) return 0.5;
    // Resolve every input path to its row id once, so the inner
    // double-loop's lookup goes int→int instead of string→int per
    // pair (k ids vs k×k string lookups for k inputs).
    final ids = List<int>.filled(list.length, -1, growable: false);
    for (var i = 0; i < list.length; i++) {
      ids[i] = _pathToId[list[i]] ?? -1;
    }
    double sum = 0.0;
    int pairs = 0;
    for (var i = 0; i < list.length; i++) {
      final ai = ids[i];
      for (var j = i + 1; j < list.length; j++) {
        if (list[i] == list[j]) {
          sum += 1.0;
          pairs++;
          continue;
        }
        final bj = ids[j];
        double s;
        if (ai < 0 || bj < 0) {
          s = 0.0;
        } else {
          final lo = ai < bj ? ai : bj;
          final hi = ai < bj ? bj : ai;
          final hist = _csrLookup(_jRowPtr, _jColIdx, _jValues, lo, hi);
          final sym = _csrLookup(_sRowPtr, _sColIdx, _sValues, lo, hi);
          s = hist > sym ? hist : sym;
        }
        sum += s;
        pairs++;
      }
    }
    if (pairs == 0) return 1.0;
    final raw = sum / pairs;
    // Pull toward neutral (0.5) proportional to how sparse the data
    // is — replaces the old binary "< 50 commits = 0.5" gate.
    final sat = math.max(50.0, _pathToId.length * 0.4);
    final conf = math.min(1.0, commitsAnalyzed / sat);
    return 0.5 + (raw - 0.5) * conf;
  }


  /// O(1) check for whether [path] is known to the matrix — tracked
  /// OR layered in via [withSymbol] for the current change set.
  /// Replaces `matrix.jaccard.containsKey(path)`.
  ///
  /// Note: after a [withSymbol] call, untracked files also appear in
  /// the id space, so this returns `true` for them too. Callers that
  /// need the stricter "has git co-change history" check should use
  /// [hasJaccardRow].
  bool containsPath(String path) => _pathToId.containsKey(path);

  int get trackedFileCount => _pathToId.length;

  /// Stricter companion to [containsPath]: `true` iff the file has at
  /// least one historical co-change edge in the jaccard CSR.
  ///
  /// Why this exists: [withSymbol] appends untracked files to the id
  /// space so their symbol overlap can be queried, which makes
  /// [containsPath] return `true` for them too. Several call sites
  /// (clustering step-2 guard, [combinedCouplingScore]'s
  /// "both tracked → trust history" fallback) really want to ask
  /// "does this file have real co-change history?" — which is
  /// precisely "does its jaccard row have any entries?"
  bool hasJaccardRow(String path) {
    final i = _pathToId[path];
    if (i == null) return false;
    return _jRowPtr[i + 1] > _jRowPtr[i];
  }

  /// Iterate the jaccard neighbours of [path] as (path, score) entries.
  /// Replaces `matrix.jaccard[path]?.entries` / `matrix.jaccard[path]?.keys`.
  /// Skips zero entries (CSR stores them as absent rather than 0.0).
  Iterable<MapEntry<String, double>> jaccardEntriesOf(String path) sync* {
    final i = _pathToId[path];
    if (i == null) return;
    final lo = _jRowPtr[i];
    final hi = _jRowPtr[i + 1];
    for (var k = lo; k < hi; k++) {
      yield MapEntry(paths[_jColIdx[k]], _jValues[k]);
    }
  }

  /// Just the keys — a frequent shape in graph-builder loops where
  /// the score is irrelevant and only neighbour identity matters.
  Iterable<String> jaccardKeysOf(String path) sync* {
    final i = _pathToId[path];
    if (i == null) return;
    final lo = _jRowPtr[i];
    final hi = _jRowPtr[i + 1];
    for (var k = lo; k < hi; k++) {
      yield paths[_jColIdx[k]];
    }
  }

  /// Iterate the symbol-overlap neighbours of [path]. Symmetric
  /// accessor to [jaccardEntriesOf] for the symbol CSR — clustering
  /// and diffusion-graph builders that want to treat symbol edges as
  /// first-class coupling evidence (e.g. to let untracked files
  /// participate in clustering the same way tracked files do) read
  /// them through here rather than going through [score] per pair.
  Iterable<MapEntry<String, double>> symbolEntriesOf(String path) sync* {
    final i = _pathToId[path];
    if (i == null) return;
    final lo = _sRowPtr[i];
    final hi = _sRowPtr[i + 1];
    for (var k = lo; k < hi; k++) {
      yield MapEntry(paths[_sColIdx[k]], _sValues[k]);
    }
  }

  /// CSR-native lookup of the jaccard component ONLY (no symbol max).
  /// Used by callers that want to read the historical co-change
  /// component independent of the per-changeset symbol axis — e.g.
  /// the semantic manifest's coupling pair report. Same algorithmic
  /// shape as [score] but skips the symbol lookup.
  double jaccardScoreOf(String a, String b) {
    if (a == b) return 1.0;
    final i = _pathToId[a];
    final j = _pathToId[b];
    if (i == null || j == null) return 0.0;
    final lo = i < j ? i : j;
    final hi = i < j ? j : i;
    return _csrLookup(_jRowPtr, _jColIdx, _jValues, lo, hi);
  }

  /// All jaccard neighbours of [path] — upper AND lower triangle
  /// combined. Unlike [jaccardEntriesOf], which only yields the
  /// upper-triangle slice (neighbours with a lex-greater path), this
  /// returns the full neighbour set regardless of how [path] sorts.
  ///
  /// Use this any time the caller asks a **per-file** question like
  /// "what changes with this file?" Global walks that visit every
  /// edge once (matrix-wide centrality, clustering builders) should
  /// keep using [jaccardEntriesOf] to avoid double-counting.
  ///
  /// Backed by a lazy mirror CSR that materialises the lower-triangle
  /// inverse index on first call (O(nnz) one-time build) and then
  /// serves every subsequent `fullJaccardRowOf` lookup in O(rowLen)
  /// time. Before the mirror existed this method was O(i · log k)
  /// per call, which turned matrix-wide scans into quadratic traps.
  Iterable<MapEntry<String, double>> fullJaccardRowOf(String path) sync* {
    final i = _pathToId[path];
    if (i == null) return;
    _ensureJaccardMirrorBuilt();
    // Lower triangle: lex-smaller partners, read straight from the
    // mirror's contiguous row slice.
    final mRowPtr = _jMirrorRowPtr!;
    final mColIdx = _jMirrorColIdx!;
    final mValues = _jMirrorValues!;
    final mlo = mRowPtr[i];
    final mhi = mRowPtr[i + 1];
    for (var p = mlo; p < mhi; p++) {
      yield MapEntry(paths[mColIdx[p]], mValues[p]);
    }
    // Upper triangle: lex-greater partners, straight from the primary
    // CSR row.
    final lo = _jRowPtr[i];
    final hi = _jRowPtr[i + 1];
    for (var p = lo; p < hi; p++) {
      yield MapEntry(paths[_jColIdx[p]], _jValues[p]);
    }
  }

  /// Lazy construction of the lower-triangle mirror CSR for the
  /// jaccard matrix. The primary CSR stores each edge once at
  /// `(min(i,j), max(i,j))`; the mirror stores the inverse view so a
  /// per-node "what are ALL my neighbours" question becomes a linear
  /// scan of one row slice instead of `i` binary searches across
  /// lex-smaller rows.
  ///
  /// **Invariant**: `FileCouplingMatrix` is immutable after
  /// construction — `_jRowPtr`, `_jColIdx`, `_jValues` are final and
  /// no public API mutates them. The mirror is therefore safe to
  /// build once and cache for the matrix's lifetime. If anyone ever
  /// adds an incremental-update path, this assumption breaks and the
  /// mirror needs either invalidation or a version counter.
  ///
  /// Two-pass scatter: first pass counts inbound edges per path id
  /// (the rowCount histogram doubles as a prefix-sum buffer once
  /// scanned), second pass fills `mColIdx` and `mValues` using a
  /// per-row cursor. Total cost: O(nnz). Total additional memory:
  /// roughly one more copy of the jaccard CSR (Int32 + Float64 per
  /// edge plus the rowPtr), all stored as typed arrays to keep the
  /// working set cache-friendly.
  void _ensureJaccardMirrorBuilt() {
    if (_jMirrorRowPtr != null) return;
    final n = paths.length;
    // rowCount[j+1] will accumulate the number of edges whose
    // greater-endpoint is j (i.e. inbound to j's mirror row). The
    // leading 0 keeps the prefix-sum step one line shorter.
    final rowCount = Int32List(n + 1);
    for (var i = 0; i < n; i++) {
      final lo = _jRowPtr[i];
      final hi = _jRowPtr[i + 1];
      for (var p = lo; p < hi; p++) {
        rowCount[_jColIdx[p] + 1]++;
      }
    }
    for (var i = 1; i <= n; i++) {
      rowCount[i] += rowCount[i - 1];
    }
    final mirrorRowPtr = rowCount; // reuse the same buffer as prefix sums
    final total = mirrorRowPtr[n];
    final mirrorColIdx = Int32List(total);
    final mirrorValues = Float64List(total);
    // Per-row write cursor — initialised to each row's starting
    // offset so we can scatter in a single pass. We can't reuse
    // `mirrorRowPtr` here because it's the authoritative row-range
    // table; mutating it would corrupt lookups.
    final cursor = Int32List(n);
    for (var i = 0; i < n; i++) {
      cursor[i] = mirrorRowPtr[i];
    }
    for (var i = 0; i < n; i++) {
      final lo = _jRowPtr[i];
      final hi = _jRowPtr[i + 1];
      for (var p = lo; p < hi; p++) {
        final j = _jColIdx[p];
        final slot = cursor[j]++;
        mirrorColIdx[slot] = i;
        mirrorValues[slot] = _jValues[p];
      }
    }
    _jMirrorRowPtr = mirrorRowPtr;
    _jMirrorColIdx = mirrorColIdx;
    _jMirrorValues = mirrorValues;
  }

  /// Top jaccard neighbours of [path], ranked by score descending,
  /// filtered to scores `>= minScore`, capped at [limit] when set.
  /// Sees both triangles of the matrix (see [fullJaccardRowOf]),
  /// so the result is symmetric — if A lists B, B lists A.
  ///
  /// Returns an empty list when [path] is unknown or every neighbour
  /// is below [minScore].
  List<MapEntry<String, double>> topJaccardNeighbours(
    String path, {
    double minScore = 0.0,
    int? limit,
  }) {
    final entries = <MapEntry<String, double>>[];
    for (final e in fullJaccardRowOf(path)) {
      if (e.value >= minScore) entries.add(e);
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    if (limit != null && entries.length > limit) {
      entries.length = limit;
    }
    return entries;
  }

  /// Degree-weighted jaccard centrality for every known path —
  /// `Σ jaccard(path, neighbour)` over all neighbours. Files in
  /// dense co-change subgraphs score high; isolated files map to 0.
  ///
  /// Walks the upper-triangle CSR exactly once, accumulating each
  /// edge into both endpoints, so it's O(nnz) regardless of the
  /// number of paths. Use this in place of hand-rolled sum loops
  /// inside `commit_tagger.dart` and anywhere else that asks "how
  /// central is every file in the co-change graph?".
  ///
  /// **Output shape**: the returned map contains an entry for
  /// EVERY path in [paths], even disconnected ones (which map to
  /// 0.0). This differs from a hand-rolled sparse accumulator that
  /// would leave disconnected files absent from the map. Callers
  /// that iterate `.keys` / `.entries` will therefore see every
  /// known path; callers doing `map[path] ?? 0.0` are unaffected.
  Map<String, double> jaccardCentralityMap() {
    final out = <String, double>{for (final p in paths) p: 0.0};
    for (var i = 0; i < paths.length; i++) {
      final name = paths[i];
      final lo = _jRowPtr[i];
      final hi = _jRowPtr[i + 1];
      for (var p = lo; p < hi; p++) {
        final v = _jValues[p];
        final other = paths[_jColIdx[p]];
        out[name] = out[name]! + v;
        out[other] = out[other]! + v;
      }
    }
    return out;
  }

  /// Per-path **maximum** jaccard to any neighbour — `max_j J(path, j)`.
  /// Optionally [restrict]ed to a subset: when supplied, only edges
  /// where **both** endpoints lie inside [restrict] contribute. Paths
  /// outside the subset, or paths with no in-subset partner, map to
  /// 0. This matches the semantics of `for (peer in subset) if
  /// (matrix.contains(path, peer)) ...` that `_rankedByImpact` and
  /// other entanglement-style consumers expect.
  ///
  /// One pass over the upper-triangle CSR, crediting each surviving
  /// edge to both endpoints — O(nnz + n) time, O(n) scratch.
  /// Replaces the common pattern
  ///
  /// ```dart
  /// for (final p in subset) {
  ///   var m = 0.0;
  ///   for (final e in matrix.fullJaccardRowOf(p)) {
  ///     if (subset.contains(e.key) && e.value > m) m = e.value;
  ///   }
  /// }
  /// ```
  ///
  /// which was O(|subset| · i · log k) after the Phase 5 unification
  /// and quadratic inside hot paths like `_rankedByImpact`. The new
  /// method produces identical values in a single linear CSR sweep.
  Map<String, double> jaccardMaxNeighborMap({Set<String>? restrict}) {
    final n = paths.length;
    final best = Float64List(n);
    // Resolve the restriction once into id space so the hot inner
    // loop does int-set membership, not String hashing. Missing
    // paths silently drop from the subset.
    Set<int>? restrictIds;
    if (restrict != null) {
      restrictIds = <int>{};
      for (final p in restrict) {
        final id = _pathToId[p];
        if (id != null) restrictIds.add(id);
      }
    }
    for (var i = 0; i < n; i++) {
      // Skip rows whose owner isn't in the subset — every edge in
      // such a row would fail the "both endpoints in subset" gate
      // anyway, so we can save the row-walk entirely.
      if (restrictIds != null && !restrictIds.contains(i)) continue;
      final lo = _jRowPtr[i];
      final hi = _jRowPtr[i + 1];
      for (var p = lo; p < hi; p++) {
        final j = _jColIdx[p];
        if (restrictIds != null && !restrictIds.contains(j)) continue;
        final v = _jValues[p];
        if (v > best[i]) best[i] = v;
        if (v > best[j]) best[j] = v;
      }
    }
    return <String, double>{for (var i = 0; i < n; i++) paths[i]: best[i]};
  }


  /// Backward-compatible nested-map view of the jaccard CSR. **Lazy**:
  /// the first read materialises the full Map<String, Map<String, double>>
  /// once and caches it. Cold-path callers (formatting, serialisation,
  /// rare `.entries` walks) keep working unchanged. Hot-path callers
  /// should migrate to [jaccardEntriesOf] / [jaccardKeysOf] /
  /// [containsPath] to stay on the CSR fast path.
  Map<String, Map<String, double>> get jaccard =>
      _jaccardMapView ??= _materialiseMap(_jRowPtr, _jColIdx, _jValues);

  /// Backward-compatible nested-map view of the symbol CSR. Same lazy
  /// pattern as [jaccard].
  Map<String, Map<String, double>> get symbol =>
      _symbolMapView ??= _materialiseMap(_sRowPtr, _sColIdx, _sValues);

  Map<String, Map<String, double>> _materialiseMap(
    Int32List rowPtr,
    Int32List colIdx,
    Float64List values,
  ) {
    final out = <String, Map<String, double>>{};
    for (var i = 0; i < paths.length; i++) {
      final lo = rowPtr[i];
      final hi = rowPtr[i + 1];
      // Always create a row entry (even if empty) so callers that
      // probe `containsKey(path)` against the materialised map see
      // the same answer as `containsPath(path)`.
      final row = <String, double>{};
      for (var k = lo; k < hi; k++) {
        row[paths[colIdx[k]]] = values[k];
      }
      out[paths[i]] = row;
    }
    return out;
  }

  /// Cached empty matrix. Replaces the previous `const empty` field —
  /// CSR storage requires typed lists which can't be const, but this
  /// singleton is lifetime-scoped and trivially shareable.
  static final FileCouplingMatrix empty = FileCouplingMatrix(
    jaccard: const {},
    headHash: '',
    commitsAnalyzed: 0,
  );

  /// Binary-search lookup of `(i, j)` in a CSR matrix. Returns the
  /// stored value or 0.0 if absent.
  static double _csrLookup(
    Int32List rowPtr,
    Int32List colIdx,
    Float64List values,
    int i,
    int j,
  ) {
    var lo = rowPtr[i];
    var hi = rowPtr[i + 1];
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      final c = colIdx[mid];
      if (c < j) {
        lo = mid + 1;
      } else if (c > j) {
        hi = mid;
      } else {
        return values[mid];
      }
    }
    return 0.0;
  }
}

/// Translate an existing upper-triangle CSR matrix into a new path id
/// space defined by [oldToNew], without round-tripping through the
/// nested-map representation.
/// Used by [FileCouplingMatrix.withSymbol]'s slow path when a new
/// symbol overlay introduces previously-unseen paths. The path id
/// space expands and shifts (we keep paths lex-sorted), so every
/// edge `(oldI, oldJ)` needs to land at `(min(newI, newJ), max(newI,
/// newJ))` in the new CSR.
/// Cost is `O(nnz)` two-pass over the existing edges plus per-row
/// insertion sorts on the rows that grew. No string interning, no
/// hashmap lookups, no Map<String, Map<String, double>> allocation.
_CsrTriple _remapCsr(
  Int32List oldRowPtr,
  Int32List oldColIdx,
  Float64List oldValues,
  Int32List oldToNew,
  int nNewFiles,
) {
  if (nNewFiles == 0 || oldColIdx.isEmpty) {
    return _CsrTriple(
      Int32List(nNewFiles + 1),
      Int32List(0),
      Float64List(0),
    );
  }

  // Pass 1: count entries per new lo-row. Each old edge becomes a
  // new edge at `(min(newI, newJ), max(newI, newJ))` — count it on
  // the lo side only since storage is upper-triangle.
  final newRowCount = Int32List(nNewFiles);
  for (var oldI = 0; oldI < oldToNew.length; oldI++) {
    final newI = oldToNew[oldI];
    final lo = oldRowPtr[oldI];
    final hi = oldRowPtr[oldI + 1];
    for (var k = lo; k < hi; k++) {
      final newJ = oldToNew[oldColIdx[k]];
      final newLo = newI < newJ ? newI : newJ;
      newRowCount[newLo]++;
    }
  }

  // Build new rowPtr (cumulative).
  final newRowPtr = Int32List(nNewFiles + 1);
  var cum = 0;
  for (var i = 0; i < nNewFiles; i++) {
    newRowPtr[i] = cum;
    cum += newRowCount[i];
  }
  newRowPtr[nNewFiles] = cum;

  final newColIdx = Int32List(cum);
  final newValues = Float64List(cum);

  // Pass 2: scatter every edge into its new lo-row. Reuse newRowCount
  // as the per-row write cursor.
  newRowCount.fillRange(0, nNewFiles, 0);
  for (var oldI = 0; oldI < oldToNew.length; oldI++) {
    final newI = oldToNew[oldI];
    final lo = oldRowPtr[oldI];
    final hi = oldRowPtr[oldI + 1];
    for (var k = lo; k < hi; k++) {
      final newJ = oldToNew[oldColIdx[k]];
      final newLo = newI < newJ ? newI : newJ;
      final newHi = newI < newJ ? newJ : newI;
      final w = newRowPtr[newLo] + newRowCount[newLo]++;
      newColIdx[w] = newHi;
      newValues[w] = oldValues[k];
    }
  }

  // Pass 3: sort each new row by colIdx. Same insertion-sort pattern
  // as `_buildSymmetricCsr`: short rows in real repos make insertion
  // sort win on cache locality vs more general sorts.
  for (var i = 0; i < nNewFiles; i++) {
    final lo = newRowPtr[i];
    final hi = newRowPtr[i + 1];
    if (hi - lo < 2) continue;
    for (var k = lo + 1; k < hi; k++) {
      final ck = newColIdx[k];
      final vk = newValues[k];
      var m = k - 1;
      while (m >= lo && newColIdx[m] > ck) {
        newColIdx[m + 1] = newColIdx[m];
        newValues[m + 1] = newValues[m];
        m--;
      }
      newColIdx[m + 1] = ck;
      newValues[m + 1] = vk;
    }
  }

  return _CsrTriple(newRowPtr, newColIdx, newValues);
}

/// Internal CSR triple. Used only inside [FileCouplingMatrix]
/// construction; the matrix immediately decomposes the record into
/// its three named final fields.
class _CsrTriple {
  final Int32List rowPtr;
  final Int32List colIdx;
  final Float64List values;
  const _CsrTriple(this.rowPtr, this.colIdx, this.values);
}

/// Convert a nested-map sparse matrix to upper-triangle CSR storage.
/// Each logical edge is stored exactly once — at row `min(i, j)`,
/// column `max(i, j)`. Lookups canonicalise the pair via the same
/// min/max rule before doing a binary search on the row's slice.
/// This matches the legacy nested-map storage semantics: the
/// materialised view via [FileCouplingMatrix.jaccard] yields each
/// edge exactly once, indexed by the lex-smaller endpoint, so
/// callers that explicitly add both endpoints (centrality counters
/// in `commit_tagger.dart`, build-loop "iterate from both endpoints,
/// one will find the other" patterns in `logos_git.dart`) see the
/// same shape they always have.
/// Steps:
///   1. Tally each lo-row's non-zero count to build rowPtr (only
///      the smaller of each pair gets a row entry).
///   2. Allocate colIdx + values, scatter entries into their lo-row,
///      then per-row sort by colIdx so binary search works.
/// Output rowPtr has length nFiles+1; values + colIdx have length
/// equal to the unique edge count.
_CsrTriple _buildSymmetricCsr(
  Map<String, Map<String, double>> map,
  Map<String, int> pathToId,
  int nFiles,
) {
  if (map.isEmpty || nFiles == 0) {
    return _CsrTriple(
      Int32List(nFiles + 1),
      Int32List(0),
      Float64List(0),
    );
  }

  // Pass 1: count per-row entries. We only count an edge once, at
  // its lo-endpoint; (b, a, v) duplicates of (a, b, v) are detected
  // via the visited-set and skipped.
  final rowCount = Int32List(nFiles);
  final visited = <int>{}; // encoded lo * nFiles + hi
  void noteEdge(int i, int j) {
    if (i == j) return;
    final lo = i < j ? i : j;
    final hi = i < j ? j : i;
    if (!visited.add(lo * nFiles + hi)) return;
    rowCount[lo]++;
  }

  for (final entry in map.entries) {
    final i = pathToId[entry.key];
    if (i == null) continue;
    for (final inner in entry.value.entries) {
      final j = pathToId[inner.key];
      if (j == null || j == i) continue;
      if (inner.value <= 0) continue;
      noteEdge(i, j);
    }
  }

  // Build rowPtr (cumulative).
  final rowPtr = Int32List(nFiles + 1);
  var cum = 0;
  for (var i = 0; i < nFiles; i++) {
    rowPtr[i] = cum;
    cum += rowCount[i];
  }
  rowPtr[nFiles] = cum;

  final colIdx = Int32List(cum);
  final values = Float64List(cum);

  // Pass 2: scatter entries into the lo-row only.
  rowCount.fillRange(0, nFiles, 0);
  visited.clear();

  void scatter(int i, int j, double v) {
    if (i == j) return;
    final lo = i < j ? i : j;
    final hi = i < j ? j : i;
    if (!visited.add(lo * nFiles + hi)) return;
    final wi = rowPtr[lo] + rowCount[lo]++;
    colIdx[wi] = hi;
    values[wi] = v;
  }

  for (final entry in map.entries) {
    final i = pathToId[entry.key];
    if (i == null) continue;
    for (final inner in entry.value.entries) {
      final j = pathToId[inner.key];
      if (j == null || j == i) continue;
      if (inner.value <= 0) continue;
      scatter(i, j, inner.value);
    }
  }

  // Pass 3: sort each row's slice by colIdx so binary search works.
  // Per-row sort: small N; use a simple co-sort of (colIdx, values).
  for (var i = 0; i < nFiles; i++) {
    final lo = rowPtr[i];
    final hi = rowPtr[i + 1];
    final n = hi - lo;
    if (n < 2) continue;
    // Insertion sort — tight loops, friendly to short rows (typical
    // degree ≪ 64). For pathologically high-degree rows we'd want
    // quicksort, but the constant factor on insertion sort wins
    // below ~30 entries which dominates real repos.
    for (var k = lo + 1; k < hi; k++) {
      final ck = colIdx[k];
      final vk = values[k];
      var m = k - 1;
      while (m >= lo && colIdx[m] > ck) {
        colIdx[m + 1] = colIdx[m];
        values[m + 1] = values[m];
        m--;
      }
      colIdx[m + 1] = ck;
      values[m + 1] = vk;
    }
  }

  return _CsrTriple(rowPtr, colIdx, values);
}

/// Compute co-change matrix for a repo from the last [commitLimit] commits.
/// Single git-log pass — the format embeds HEAD hash in the first commit
/// separator, so we don't need a separate `rev-parse HEAD` round-trip.
/// Skips commits with > [largeCommitCutoff] files (merges/imports/vendor
/// bumps); they're noise for co-change signal and would dominate pair counts.
Future<GitResult<FileCouplingMatrix>> computeFileCoupling(
  String repo, {
  int commitLimit = 1000,
  int largeCommitCutoff = 60,
  // Exponential decay half-life measured in commits. A commit at rank
  // [halfLifeCommits] contributes half as much as the tip. Set to 0 or
  // a negative number to disable (pure count-based Jaccard, legacy
  // behaviour). Pass null to *derive* a per-repo half-life via
  // [deriveEngramHalfLife] — an AR(2) oscillator fit on the commit
  // similarity trajectory. Rationale: a 50-commit greenfield repo and
  // a 50k-commit monorepo deserve different memory depths. Null is the
  // production default; tests and regression-pinning pass a number.
  double? halfLifeCommits,
}) async {
  final logProbe = await runGitProbe(repo, [
    'log',
    '-n', '$commitLimit',
    '--no-merges',
    '--raw', '--numstat', '-M',
    '--format=$logCommitSeparator%H%x1f%an%x1f%s',
  ]);
  if (logProbe.exitCode != 0) {
    return GitResult.err(logProbe.stderr.toString().trim());
  }

  final stdout = logProbe.stdout.toString();
  String headHash = '';
  final commits = <_CouplingCommit>[];
  var currentRaw = <({String path, String oldBlob, String newBlob})>[];
  var currentNumstat = <(String, int)>[];
  String currentAuthor = '';
  String currentSubject = '';
  final sepLen = logCommitSeparator.length;

  void flushCommit() {
    if (currentRaw.isEmpty && currentNumstat.isEmpty) return;
    final numstatByPath = <String, int>{};
    for (final (p, lines) in currentNumstat) {
      numstatByPath[p] = lines;
    }
    final files = <({String path, int lines, String oldBlob, String newBlob})>[];
    for (final raw in currentRaw) {
      final lines = numstatByPath[raw.path] ?? 0;
      final mass = (raw.oldBlob == raw.newBlob) ? 0 : math.max(1, lines);
      files.add((
        path: raw.path,
        lines: mass,
        oldBlob: raw.oldBlob,
        newBlob: raw.newBlob,
      ));
    }
    if (files.isNotEmpty && files.length <= largeCommitCutoff) {
      commits.add(_CouplingCommit(
        author: currentAuthor,
        subject: currentSubject,
        files: files,
      ));
    }
    currentRaw = [];
    currentNumstat = [];
  }

  var inNumstat = false;
  for (final rawLine in const LineSplitter().convert(stdout)) {
    if (rawLine.startsWith(logCommitSeparator)) {
      flushCommit();
      inNumstat = false;
      if (headHash.isEmpty) {
        final firstSep = rawLine.indexOf(_logMetaSep, sepLen);
        headHash = firstSep == -1
            ? rawLine.substring(sepLen).trim()
            : rawLine.substring(sepLen, firstSep).trim();
      }
      final meta = rawLine.substring(sepLen).split(_logMetaSep);
      currentAuthor = meta.length >= 2 ? meta[1].trim() : '';
      currentSubject = meta.length >= 3
          ? meta.sublist(2).join(_logMetaSep).trim()
          : '';
      continue;
    }
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) {
      if (currentRaw.isNotEmpty) inNumstat = true;
      continue;
    }

    if (trimmed.startsWith(':')) {
      final parts = trimmed.split('\t');
      if (parts.length < 2) continue;
      final header = parts[0].split(' ');
      if (header.length < 5) continue;
      final oldBlob = header[2];
      final newBlob = header[3];
      final status = header[4];
      final String path;
      if (status.startsWith('R') || status.startsWith('C')) {
        path = (parts.length >= 3 ? parts[2] : parts[1]).replaceAll('\\', '/');
      } else {
        path = parts[1].replaceAll('\\', '/');
      }
      currentRaw.add((path: path, oldBlob: oldBlob, newBlob: newBlob));
    } else if (inNumstat) {
      final parts = trimmed.split('\t');
      if (parts.length >= 3) {
        final added = int.tryParse(parts[0]) ?? 0;
        final deleted = int.tryParse(parts[1]) ?? 0;
        final rawPath = parts.sublist(2).join('\t');
        final path = _extractNewPath(rawPath).replaceAll('\\', '/');
        currentNumstat.add((path, added + deleted));
      }
    }
  }
  flushCommit();

  if (commits.isEmpty) {
    return GitResult.ok(FileCouplingMatrix(
      jaccard: {},
      headHash: headHash,
      commitsAnalyzed: 0,
    ));
  }

  final double effectiveHalfLife = halfLifeCommits == null
      ? _deriveAdaptiveHalfLife([for (final c in commits) [for (final f in c.files) f.path]])
      : halfLifeCommits;
  // Commits are in reverse-chrono order — index 0 is the most recent.
  // Weight is evaluated on the semantic clock, not raw ordinal rank:
  // w(age) = 2^(-age / halfLife). This prevents long runs of ritual
  // churn from smuggling temporal structure back into the co-change
  // signal when meaningful commits are sparse.
  // Precompute the decay coefficient once outside the per-commit
  // loop. 2^(-age / T) = exp(-age · ln2 / T); collapsing the ln2/T
  // division into a single multiply inside commitWeight keeps one
  // transcendental per call instead of pow's general-case path.
  // (Grimoire Circle XXII / XXIII: the transcendental you actually
  // need is exp; pow with a non-integer exponent is a library
  // detour, not a hardware primitive.)
  final invHalfLifeLn2 =
      effectiveHalfLife > 0 ? math.ln2 / effectiveHalfLife : 0.0;
  double commitWeight(double semanticAge) {
    if (effectiveHalfLife <= 0) return 1.0;
    return math.exp(-semanticAge * invHalfLifeLn2);
  }

  // One pass: per-file weighted commit "count" + per-pair weighted co-
  // count. Only upper-triangle (a < b lexicographic) — halves inserts.
  final fileCommits = <String, double>{};
  final pairCount = <String, Map<String, double>>{};
  var semanticAge = 0.0;
  for (var rank = 0; rank < commits.length; rank++) {
    final commit = commits[rank];
    final files = commit.files;
    final pathSet = {for (final f in files) f.path};
    final commitMass = files.fold<int>(0, (s, f) => s + f.lines);
    final m = inferCommitMeaningfulness(
      author: commit.author,
      subject: commit.subject,
      paths: pathSet,
      totalLinesChanged: commitMass,
    );
    final step = m.weight.clamp(0.0, 1.0);
    final w = commitWeight(semanticAge) * step;
    semanticAge += step;
    if (w <= 0) continue;
    for (final f in files) {
      fileCommits[f.path] = (fileCommits[f.path] ?? 0) + w * f.lines;
    }
    final n = files.length;
    if (n < 2) continue;
    for (var i = 0; i < n; i++) {
      final a = files[i];
      for (var j = i + 1; j < n; j++) {
        final b = files[j];
        final cmp = a.path.compareTo(b.path);
        final lo = cmp < 0 ? a.path : b.path;
        final hi = cmp < 0 ? b.path : a.path;
        final mass = math.sqrt(a.lines.toDouble() * b.lines.toDouble());
        final row = pairCount.putIfAbsent(lo, () => {});
        row[hi] = (row[hi] ?? 0) + w * mass;
      }
    }
  }

  // Temporal lag coupling (lag 1–3): files that change in NEARBY commits
  // (not the same commit) carry delayed co-change signal that lag-0
  // counting misses. Measured at 71% of all coupling across 8 real repos.
  // Each lag is discounted by 1/(1+lag) so lag-1 contributes 50% of a
  // same-commit co-change, lag-2 contributes 33%, lag-3 contributes 25%.
  // The discount is physics-derived: transfer entropy decays roughly as
  // 1/lag in the repos we measured.
  for (var lag = 1; lag <= 3; lag++) {
    final lagDiscount = 1.0 / (1 + lag);
    for (var rank = 0; rank < commits.length - lag; rank++) {
      final here = commits[rank];
      final there = commits[rank + lag];
      if (here.files.length > largeCommitCutoff ||
          there.files.length > largeCommitCutoff) continue;
      final wHere = commitWeight(rank.toDouble());
      final wThere = commitWeight((rank + lag).toDouble());
      final w = math.sqrt(wHere * wThere) * lagDiscount;
      if (w <= 1e-9) continue;
      for (final fHere in here.files) {
        for (final fThere in there.files) {
          if (fHere.path == fThere.path) continue;
          final cmp = fHere.path.compareTo(fThere.path);
          final lo = cmp < 0 ? fHere.path : fThere.path;
          final hi = cmp < 0 ? fThere.path : fHere.path;
          final mass =
              math.sqrt(fHere.lines.toDouble() * fThere.lines.toDouble());
          final row = pairCount.putIfAbsent(lo, () => {});
          row[hi] = (row[hi] ?? 0) + w * mass;
        }
      }
    }
  }

  // Jaccard: |A ∩ B| / |A ∪ B| = co / (Na + Nb - co), with the counts
  // now being time-weighted sums instead of integers. Still in [0, 1].
  final jaccard = <String, Map<String, double>>{};
  pairCount.forEach((a, row) {
    final na = fileCommits[a] ?? 0;
    final dest = jaccard.putIfAbsent(a, () => {});
    row.forEach((b, co) {
      final union = na + (fileCommits[b] ?? 0) - co;
      if (union > 0) dest[b] = co / union;
    });
  });

  // Ensure every file that appeared in any commit has a (possibly empty) row
  // so `jaccard.containsKey(path)` reliably answers "is this tracked?".
  for (final path in fileCommits.keys) {
    jaccard.putIfAbsent(path, () => {});
  }

  return GitResult.ok(FileCouplingMatrix(
    jaccard: jaccard,
    headHash: headHash,
    commitsAnalyzed: semanticAge > 0 ? math.max(1, semanticAge.round()) : 0,
  ));
}

class _CouplingCommit {
  final String author;
  final String subject;
  final List<({String path, int lines, String oldBlob, String newBlob})> files;
  const _CouplingCommit({
    required this.author,
    required this.subject,
    required this.files,
  });
}

String _extractNewPath(String raw) {
  final arrow = raw.indexOf(' => ');
  if (arrow < 0) return raw;
  final brace = raw.indexOf('{');
  if (brace >= 0 && brace < arrow) {
    final close = raw.indexOf('}', arrow);
    if (close >= 0) {
      return '${raw.substring(0, brace)}${raw.substring(arrow + 4, close)}${raw.substring(close + 1)}';
    }
  }
  return raw.substring(arrow + 4);
}

/// Half-life clamp band. Half-life is measured in commits.
/// The floor [_halfLifeMin] is the point where the exponential kernel
/// concentrates ~99% of its mass inside the most recent ~7·halfLife
/// commits (7·ln(2) ≈ 4.85, so 2⁻⁷ ≈ 1%). Below 50 the tail becomes
/// sparse enough that a single unusual recent commit dominates the
/// Jaccard signal. Empirically the minimum sustainable window.
/// The ceiling [_halfLifeMax] is the reciprocal concern on big
/// monorepos — beyond this, files that co-changed a year ago still
/// carry near-equal weight to yesterday's edit, and the matrix
/// effectively degenerates toward count-based Jaccard.
const double _halfLifeMin = 50.0;
const double _halfLifeMax = 500.0;

/// Fraction of the analysed window the fallback half-life occupies.
/// Picking halfLife = n/[_fallbackHalfLifeDivisor] means the most
/// recent 25% of commits holds ≈ 87.5% of the weight (1 - 2⁻³).
/// That matches the "new edits should dominate but old ones still
/// count" intuition without needing a fit.
const int _fallbackHalfLifeDivisor = 4;

/// Fallback half-life when the Engram fit can't run (too few commits,
/// degenerate signal). Proportional to the analysable window so tiny
/// repos get a tighter half-life than big ones.
double _fallbackHalfLife(int commitCount) =>
    (commitCount / _fallbackHalfLifeDivisor)
        .clamp(_halfLifeMin, _halfLifeMax)
        .toDouble();

/// Derive an adaptive half-life (in commits) from the shape of the
/// history itself. Implements the Whisper Engram principle: block size
/// is a property of the data, not a parameter anyone chose.
/// Algorithm:
///   1. Build the consecutive-commit Jaccard series via the shared
///      helper [consecutiveJaccardSeries]. This is the "trajectory" of
///      how fast the working set turns over — highly correlated = slow
///      drift (monorepo), oscillating near 0 = fast topic changes.
///   2. Centre the sequence so the AR(2) fit isn't biased by the
///      baseline similarity.
///   3. Fit z[n] = K·z[n-1] − G·z[n-2]. Spectral radius |λ| is the
///      per-step decay factor; half-life = −ln(2)/ln|λ|.
///   4. Clamp to the production band; fall back to a size-proportional
///      heuristic when the fit degenerates (short / non-orbital /
///      divergent).
/// Public so the derivation can be exercised in isolation by tests.
double deriveEngramHalfLife(List<List<String>> commitFileLists) {
  final n = commitFileLists.length;
  // Fit needs at least `engramMinSamples` similarity values, and the
  // similarity series has length n-1. +1 margin for the centring pass.
  if (n < engramMinSamples + 2) return _fallbackHalfLife(n);

  // `commitFileLists` is typically `List<List<String>>` where each
  // inner list is the paths touched by one commit. We only iterate each
  // list once (inside the Jaccard computation) — materialising a
  // `List<Set<String>>` up front avoids re-scanning the same paths on
  // every pairwise comparison. Using a fixed-size typed-list factory
  // avoids growable-list overhead given `fileSets.length` is known.
  final fileSets = List<Set<String>>.generate(
    commitFileLists.length,
    (i) => commitFileLists[i].toSet(),
    growable: false,
  );
  final sims = consecutiveJaccardSeries(fileSets);

  // Centre the signal. AR(2) on a biased series fits the mean instead
  // of the dynamics. `Float64List` avoids per-element boxing on the
  // hot AR(2) iterations downstream.
  var mean = 0.0;
  for (final s in sims) {
    mean += s;
  }
  mean /= sims.length;
  final centred = Float64List(sims.length);
  for (var i = 0; i < sims.length; i++) {
    centred[i] = sims[i] - mean;
  }

  final fit = engramFit(centred);
  final hl = fit.halfLifeSamples;
  if (hl == null) return _fallbackHalfLife(n);
  return hl.clamp(_halfLifeMin, _halfLifeMax);
}

double _deriveAdaptiveHalfLife(List<List<String>> commits) =>
    deriveEngramHalfLife(commits);

/// How files are ordered in the change list once they've been clustered.
enum FileSortGuide {
  /// Files arranged so tightly-coupled pairs sit adjacent. Clusters kept
  /// together; the rail's hover visualization reads as a continuous band.
  relatedProximity,

  /// Plain A→Z by path. Cluster colors still render; position ignores them.
  alphabetical,

  /// Ranked by the weight of *this* change — hunk count + line churn in
  /// the current diff. The noisiest files rise to the top; tiny edits
  /// drop to the bottom. Where the action is, not where it might echo.
  impact,
}

/// Result of agglomerative clustering on the current change set.
/// Files with a coupling score ≥ [threshold] to any current peer end up in
/// the same cluster (single-link). Files with no qualifying peer get
/// [clusterIdIsolated] (-1) — rendered as a muted stripe so they read as
/// "standalone, no coupling signal" rather than "part of cluster N".
/// Which signal made two files cluster together. Surfaced to the UI
/// so Atlas cards can show *why* these files group — not just a
/// coherence number but the geometric reason.
///
/// Priority order when a pair scores on multiple axes: transport >
/// coChange > symbol > pathAffinity. `transport` is the most
/// semantically specific (source↔test, manifest↔lockfile are
/// unambiguous structural relations); `coChange` carries real git
/// history; `symbol` is vocabulary overlap; `pathAffinity` is the
/// weakest (mere directory siblings).
enum RelatednessAxis {
  coChange,
  symbol,
  transport,
  pathAffinity,
  hunk,
  spectral,
}

class FileClusters {
  final Map<String, int> byPath;
  final int clusterCount;

  /// Paths in render order — same cluster ids are contiguous; clusters
  /// themselves are ordered by size (largest first), with isolated at the end.
  final List<String> orderedPaths;

  /// The dominant bonding signal for each cluster id. Computed as the
  /// mode (most-frequent axis) across the cluster's Union-Find pairs.
  /// Absent when a cluster was built purely from singleton merges
  /// (shouldn't happen in practice — every cluster has ≥1 pair). The
  /// isolated cluster id is never keyed here.
  final Map<int, RelatednessAxis> dominantAxisByCluster;

  const FileClusters({
    required this.byPath,
    required this.clusterCount,
    required this.orderedPaths,
    this.dominantAxisByCluster = const {},
  });

  static const clusterIdIsolated = -1;

  static FileClusters empty(List<String> fallbackOrder) => FileClusters(
        byPath: {for (final p in fallbackOrder) p: clusterIdIsolated},
        clusterCount: 0,
        orderedPaths: fallbackOrder,
      );
}

/// Single-link clustering over the current change set.
/// Scales cleanly from 1 file to 10,000+ by:
///   * enumerating only above-threshold pairs (no O(n²) score scan),
///   * using Union-Find for merges (near-linear in pair count),
///   * bucketing untracked files by path prefix before enumerating path
///     pairs, so path-affinity lookups stay O(n·avg_bucket_size) rather
///     than O(n²) when the change set is dominated by untracked files.
FileClusters clusterFiles(
  List<String> currentPaths,
  FileCouplingMatrix matrix, {
  double? threshold,
  CouplingConstants couplingConstants = CouplingConstants.prior,
  FileSortGuide sortGuide = FileSortGuide.relatedProximity,
  // Per-path diff signal used by [FileSortGuide.impact]. The sort
  // computes effective impact from these AND the coupling matrix —
  // a file whose change is "explained" by a co-changing peer in the
  // same diff gets its impact attenuated proportionally, so
  // source+generated pairs and lockfile+manifest pairs don't double-
  // count. Missing entries score 0.
  Map<String, FileImpactSignal>? impactSignals,
  // Paths currently in a merge-conflict state. Regardless of sortGuide
  // these float to the very top of the list — unresolvable conflicts
  // block every commit, so the user must see them first.
  Set<String>? conflictedPaths,
  // Paths the user has checked for inclusion in the current commit.
  // Only consulted by [FileSortGuide.relatedProximity]: within a cluster
  // included files sort above excluded, and clusters with any included
  // files sort above fully-excluded clusters.
  Set<String>? includedPaths,
  // "Smart invert" toggle. Reverses the effective order per mode —
  // conflicts always stay pinned at the top regardless. Each mode
  // carries its own interpretation of "opposite":
  //   * related: tight clusters drop to the bottom, isolated/one-off
  //     files rise — "show me the odd ones out."
  //   * alphabetical: Z → A.
  //   * impact: smallest churn first — "quick wins on top."
  bool inverted = false,
  // Optional rich-signal context for the `relatedProximity` sort.
  // When supplied, intra-cluster ordering routes through the
  // spectrally-self-weighted seriator in `correlatedness_signals.dart`
  // — combining jaccard×authenticity, symbol overlap, transport
  // lanes, commit hyperedges, and engram K-vector cosine into one
  // Fiedler-seriated 1D order. When absent, falls back to the
  // legacy greedy nearest-neighbour chain on `combinedCouplingScore`.
  CorrelatednessContext? correlatednessContext,
  // The Logos spectral engine, when available. Its Born-mixed CsrGraph
  // fuses 5 axes (frequency, co-change, spatial proximity, volatility,
  // engram) with confidence-gated quantum mixing. When present, the
  // engine's own edge weights and spectral gap replace the statistical
  // threshold — the physics IS the gate.
  LogosGit? engine,
}) {
  final n = currentPaths.length;
  if (n == 0) {
    return const FileClusters(byPath: {}, clusterCount: 0, orderedPaths: []);
  }

  // Derive the admission threshold from the changeset's own coupling
  // distribution. Uses the mean Jaccard score across all edges touching
  // the current paths — dense repos get a higher bar, sparse repos get
  // a lower bar. Clamped to a sane band.
  if (threshold == null) {
    var sum = 0.0;
    var count = 0;
    final pathSet = currentPaths.toSet();
    for (final p in currentPaths) {
      for (final entry in matrix.jaccardEntriesOf(p)) {
        if (!pathSet.contains(entry.key)) continue;
        sum += entry.value;
        count++;
      }
    }
    final mean = count > 0 ? sum / count : 0.25;
    threshold = mean.clamp(0.15, 0.50);
  }
  final effectiveThreshold = threshold;

  // Index paths so we can refer to them by int everywhere.
  final pathIndex = <String, int>{
    for (var i = 0; i < n; i++) currentPaths[i]: i,
  };

  // Collect candidate pairs above threshold. Each pair stored at most
  // once via a lexicographic (lo, hi) int-encoded key. `candidateIndex`
  // maps the encoded key to its slot in `candidates`, so when a pair is
  // hit twice (e.g. once via jaccard, once via symbol overlap) we can
  // promote its score to the stronger of the two in O(1) instead of
  // scanning the candidates list.
  final candidates = <_PairScore>[];
  final candidateIndex = <int, int>{};

  int encode(int a, int b) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return lo * n + hi;
  }

  // -- 1. Direct coupling pairs: sparse iteration over the jaccard CSR
  //    AND the symbol-overlap CSR. For each current file, walk both
  //    neighbour rows; only add pairs where the neighbour is also in
  //    the current change set. Both axes are independent evidence, so
  //    we record whichever score is larger when both fire — matches
  //    the `score(a, b) = max(jaccard, symbol)` contract used
  //    everywhere else in the coupling API.
  //
  //    The symbol walk is what makes untracked files cluster with
  //    their structural peers: co-change history is blind to a file
  //    that has never been committed, but symbol overlap sees the
  //    identifier graph instantly, so a new test file groups with the
  //    module it tests the moment it shows up in the working tree.
  // Track ALL axes that fire per pair for corroboration gating.
  final pairAxes2 = <int, Set<RelatednessAxis>>{};

  void recordPair(int i, int j, double s, RelatednessAxis axis) {
    if (i == j) return;
    final key = encode(i, j);
    pairAxes2.putIfAbsent(key, () => {}).add(axis);
    final existing = candidateIndex[key];
    if (existing == null) {
      candidateIndex[key] = candidates.length;
      candidates.add(_PairScore(s, i, j, axis));
    } else if (s > candidates[existing].score) {
      candidates[existing] = _PairScore(s, i, j, axis);
    }
  }

  for (var i = 0; i < n; i++) {
    final a = currentPaths[i];
    for (final entry in matrix.jaccardEntriesOf(a)) {
      final s = entry.value;
      if (s < effectiveThreshold) continue;
      final j = pathIndex[entry.key];
      if (j == null) continue;
      recordPair(i, j, s, RelatednessAxis.coChange);
    }
    for (final entry in matrix.symbolEntriesOf(a)) {
      final s = entry.value;
      if (s < effectiveThreshold) continue;
      final j = pathIndex[entry.key];
      if (j == null) continue;
      recordPair(i, j, s, RelatednessAxis.symbol);
    }
  }

  // -- 1b. Transport-lane pairs: structural relations that path-based
  //    heuristics catch even on brand-new files with no history or
  //    symbol overlap (`pubspec.yaml` ↔ `pubspec.lock`, `foo.dart` ↔
  //    `foo_test.dart`, `schema.sql` ↔ migrations sharing a concept
  //    token). `logosTransportLane` returns a typed descriptor with a
  //    `strength` in [0, 0.5] we use as the pair score; every matching
  //    lane clears the default 0.25 threshold by design, so these
  //    pairs always promote their files out of `isolated`.
  //
  //    Precompute roles once per path (same trick as gatherEvidence's
  //    TransportRoles pool) so the O(n²) enumeration is role-lookup +
  //    field compare, not string-normalize + regex per pair.
  final transportRoles = [
    for (final p in currentPaths) TransportRoles.of(p),
  ];
  for (var i = 0; i < n; i++) {
    final ri = transportRoles[i];
    for (var j = i + 1; j < n; j++) {
      final rj = transportRoles[j];
      final forward = logosTransportLaneOfRoles(ri, rj, couplingConstants);
      final backward = logosTransportLaneOfRoles(rj, ri, couplingConstants);
      final strength = math.max(
        forward?.strength ?? 0.0,
        backward?.strength ?? 0.0,
      );
      // Transport-lane presence is definitive — a source file and its
      // test ARE related, a manifest and its lockfile ARE related.
      // Don't hold them to the statistical-axis threshold; admit on
      // any non-zero strength. UF still processes by score so stronger
      // lanes (manifest↔lockfile) win over weaker ones (source↔doc)
      // when both would assign a file to different clusters.
      if (strength <= 0) continue;
      recordPair(i, j, strength, RelatednessAxis.transport);
    }
  }

  // -- 1c. Hunk-graph pairs: extract ACTUAL cross-file edge weights
  //    from the hunk diffusion graph. Two files are hunk-coupled when
  //    their hunks share identifiers, engram similarity, or transport
  //    structure. We sum the raw edge weights between hunks in different
  //    files to get a per-file-pair coupling score, then self-calibrate
  //    the admission gate from the distribution of those scores.
  if (correlatednessContext != null) {
    final graph = correlatednessContext.hunkResult.graph;
    final hunks = correlatednessContext.hunks;
    if (graph != null && hunks.length == graph.n) {
      final w = graph.rawWeights.isNotEmpty ? graph.rawWeights : graph.values;
      // Sum cross-file edge weights per file pair.
      final crossFileWeights = <(String, String), double>{};
      for (var node = 0; node < graph.n; node++) {
        final fileA = hunks[node].filePath;
        if (!pathIndex.containsKey(fileA)) continue;
        final rowStart = graph.indptr[node];
        final rowEnd = graph.indptr[node + 1];
        for (var e = rowStart; e < rowEnd; e++) {
          final neighbor = graph.indices[e];
          if (neighbor <= node) continue; // upper triangle only
          if (neighbor >= hunks.length) continue;
          final fileB = hunks[neighbor].filePath;
          if (fileB == fileA) continue; // skip within-file edges
          if (!pathIndex.containsKey(fileB)) continue;
          final lo = fileA.compareTo(fileB) < 0 ? fileA : fileB;
          final hi = fileA.compareTo(fileB) < 0 ? fileB : fileA;
          final key = (lo, hi);
          crossFileWeights[key] =
              (crossFileWeights[key] ?? 0.0) + w[e].abs();
        }
      }
      if (crossFileWeights.isNotEmpty) {
        // Self-calibrate: use the distribution's own statistics to set
        // the gate. Pairs below the mean are noise; pairs above are
        // signal. This replaces any hardcoded threshold.
        final scores = crossFileWeights.values.toList()..sort();
        final median = scores[scores.length ~/ 2];
        final gate = median;
        final range = scores.last - gate;
        for (final entry in crossFileWeights.entries) {
          final raw = entry.value;
          if (raw <= gate) continue;
          final strength = range > 0
              ? ((raw - gate) / range).clamp(0.0, 1.0)
              : 0.5;
          if (strength < effectiveThreshold) continue;
          final i = pathIndex[entry.key.$1]!;
          final j = pathIndex[entry.key.$2]!;
          recordPair(i, j, strength, RelatednessAxis.hunk);
        }
      }
    }
  }

  // -- 1d. Spectral graph pairs: Born-mixed edge weights from the Logos
  //    engine. These fuse frequency, co-change, spatial proximity,
  //    volatility, and engram axes with confidence-gated quantum mixing.
  //    Self-calibrated gate from the pair distribution — the physics IS
  //    the threshold.
  if (engine != null) {
    final g = engine.graph;
    final w = g.rawWeights.isNotEmpty ? g.rawWeights : g.values;
    final spectralPairs = <(int, int, double)>[];
    for (var i = 0; i < n; i++) {
      final nodeId = engine.pathToId[currentPaths[i]];
      if (nodeId == null) continue;
      final rowStart = g.indptr[nodeId];
      final rowEnd = g.indptr[nodeId + 1];
      for (var e = rowStart; e < rowEnd; e++) {
        final neighborNode = g.indices[e];
        if (neighborNode >= engine.nodePaths.length) continue;
        final neighborPath = engine.nodePaths[neighborNode];
        final j = pathIndex[neighborPath];
        if (j == null || j <= i) continue;
        spectralPairs.add((i, j, w[e].abs()));
      }
    }
    if (spectralPairs.isNotEmpty) {
      final scores = spectralPairs.map((t) => t.$3).toList()..sort();
      final median = scores[scores.length ~/ 2];
      final range = scores.last - median;
      for (final (i, j, raw) in spectralPairs) {
        if (raw <= median) continue;
        final strength = range > 0
            ? ((raw - median) / range).clamp(0.0, 1.0)
            : 0.5;
        recordPair(i, j, strength, RelatednessAxis.spectral);
      }
    }
  }

  // -- 2. Path-affinity pairs for files with no historical co-change
  //    data (typically untracked / new files). Bucket by top-2 path
  //    segments to keep enumeration near-linear even for huge change
  //    sets.
  //
  //    The "skip if both tracked" guard uses [hasJaccardRow], NOT
  //    [containsPath]: after [withSymbol] layers untracked paths into
  //    the id space, `containsPath` would return true for them too,
  //    causing this pass to skip the exact untracked-untracked pairs
  //    it was designed to cover. `hasJaccardRow` preserves the
  //    original intent — "does this file have real git history to
  //    trust?" — regardless of symbol-layer expansion.
  final buckets = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    final p = currentPaths[i];
    final segs = p.replaceAll('\\', '/').split('/');
    final key = segs.length >= 2
        ? '${segs[0]}/${segs[1]}'
        : (segs.isNotEmpty ? segs[0] : '');
    buckets.putIfAbsent(key, () => <int>[]).add(i);
  }
  buckets.forEach((_, idxs) {
    // O(m²) within bucket, but avg bucket is tiny for typical projects.
    for (var ii = 0; ii < idxs.length; ii++) {
      for (var jj = ii + 1; jj < idxs.length; jj++) {
        final i = idxs[ii];
        final j = idxs[jj];
        final a = currentPaths[i];
        final b = currentPaths[j];
        final aHasHistory = matrix.hasJaccardRow(a);
        final bHasHistory = matrix.hasJaccardRow(b);
        if (aHasHistory && bHasHistory) continue; // history is authoritative
        final s = pathAffinity(a, b);
        if (s < effectiveThreshold) continue;
        recordPair(i, j, s, RelatednessAxis.pathAffinity);
      }
    }
  });

  // -- 3. Corroboration gate + Union-Find.
  //
  //    The Born mixing philosophy: a single noisy axis shouldn't merge
  //    files. Symbol overlap alone is cold-start IDF noise. Path affinity
  //    alone is directory coincidence. These "weak" axes need at least
  //    one "strong" corroborating axis (coChange, transport, hunk) to
  //    be trusted. Strong axes are authoritative on their own — if the
  //    history says files co-change, or the transport lane says source↔test,
  //    that's enough.
  //
  //    pairAxes2 tracks EVERY axis that fired per pair. The Union-Find
  //    only processes pairs that have at least one strong axis OR have
  //    evidence from ≥2 independent axes.
  const strongAxes = {
    RelatednessAxis.coChange,
    RelatednessAxis.transport,
    RelatednessAxis.hunk,
    RelatednessAxis.spectral,
  };
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final uf = _UnionFind(n);
  final pairAxes = <_PairScore>[];
  for (final p in candidates) {
    final key = encode(p.a, p.b);
    final axes = pairAxes2[key] ?? {};
    final hasStrong = axes.any(strongAxes.contains);
    final corroborated = axes.length >= 2;
    if (!hasStrong && !corroborated) continue; // weak uncorroborated — skip
    uf.union(p.a, p.b);
    pairAxes.add(p);
  }

  // -- 4. Build clusters from UF roots. Singletons (their own root) become
  //    isolated — they had no pair above threshold by definition.
  final byRoot = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    byRoot.putIfAbsent(uf.find(i), () => <int>[]).add(i);
  }

  // Build unsorted clusters (int index lists). Actual seriation + member
  // ordering happens inside each branch below so the related branch can
  // be include-aware without affecting the other modes.
  var realClusters = <List<int>>[];
  final isolatedIdx = <int>[];
  byRoot.forEach((root, members) {
    if (members.length <= 1) {
      isolatedIdx.addAll(members);
    } else {
      realClusters.add(members);
    }
  });

  // -- 3b. Post-merge Fiedler bisection. Union-Find is single-linkage:
  //    one bridge edge collapses two groups into one. The hunk Fiedler
  //    vector sees the CURRENT diff's structure — which hunks actually
  //    reference which — independent of historical co-change that
  //    inflates BBL committers' Jaccard scores.
  //
  //    For each cluster, compute the per-file Fiedler centroid from
  //    the hunk graph. Sort by centroid. Find the LARGEST gap between
  //    consecutive centroids. If that gap is larger than the median
  //    gap (self-calibrated), split there. Recurse on each half until
  //    no gap exceeds the median.
  //
  //    Universal: processes the OUTPUT. Doesn't care how the cluster
  //    formed or which axes contributed.
  if (correlatednessContext != null) {
    final basis = correlatednessContext.hunkResult.spectralBasis();
    final fiedler = basis?.fiedlerVector;
    if (fiedler != null && correlatednessContext.hunks.isNotEmpty) {
      // Compute per-file Fiedler centroid from hunk coordinates.
      final rankings = correlatednessContext.hunkResult.rankings;
      final phiByKey = <(String, int), double>{};
      for (final r in rankings) {
        phiByKey[(r.hunk.filePath, r.hunk.hunkIndex)] = r.phi;
      }
      final fileCentroid = <String, double>{};
      final fileWeight = <String, double>{};
      final hunks = correlatednessContext.hunks;
      for (var i = 0; i < hunks.length && i < fiedler.length; i++) {
        final h = hunks[i];
        final phi = phiByKey[(h.filePath, h.hunkIndex)] ?? 0.0;
        final w = phi > 0 ? phi : 1.0;
        fileCentroid[h.filePath] =
            (fileCentroid[h.filePath] ?? 0.0) + fiedler[i] * w;
        fileWeight[h.filePath] = (fileWeight[h.filePath] ?? 0.0) + w;
      }
      for (final path in fileCentroid.keys.toList()) {
        final w = fileWeight[path] ?? 1.0;
        fileCentroid[path] = fileCentroid[path]! / w;
      }

      List<List<int>> splitCluster(List<int> cluster) {
        // Separate files WITH Fiedler data from files WITHOUT.
        // Files without centroids (no hunks in the diff) stay attached
        // to whichever sub-cluster is larger after the split.
        final withCoord = <(int, double)>[];
        final noCoord = <int>[];
        for (final idx in cluster) {
          final c = fileCentroid[currentPaths[idx]];
          if (c != null) {
            withCoord.add((idx, c));
          } else {
            noCoord.add(idx);
          }
        }
        // Need at least 4 coordinated files to consider a split
        // (2 on each side minimum).
        if (withCoord.length < 4) return [cluster];

        withCoord.sort((a, b) => a.$2.compareTo(b.$2));

        final gaps = <double>[];
        for (var k = 1; k < withCoord.length; k++) {
          gaps.add((withCoord[k].$2 - withCoord[k - 1].$2).abs());
        }
        if (gaps.isEmpty) return [cluster];

        final sortedGaps = [...gaps]..sort();
        final medianGap = sortedGaps[sortedGaps.length ~/ 2];
        final maxGapIdx = gaps.indexOf(
            gaps.reduce((a, b) => a > b ? a : b));
        final maxGap = gaps[maxGapIdx];

        if (maxGap <= medianGap * 2 || medianGap < 1e-9) return [cluster];

        // Both sides must have at least 2 members.
        if (maxGapIdx < 1 || maxGapIdx >= withCoord.length - 2) {
          return [cluster];
        }

        final left = [for (var k = 0; k <= maxGapIdx; k++) withCoord[k].$1];
        final right = [
          for (var k = maxGapIdx + 1; k < withCoord.length; k++)
            withCoord[k].$1,
        ];
        // Files without Fiedler data join the larger sub-cluster.
        if (noCoord.isNotEmpty) {
          if (left.length >= right.length) {
            left.addAll(noCoord);
          } else {
            right.addAll(noCoord);
          }
        }
        return [...splitCluster(left), ...splitCluster(right)];
      }

      final split = <List<int>>[];
      for (final cluster in realClusters) {
        split.addAll(splitCluster(cluster));
      }
      realClusters = <List<int>>[];
      for (final sub in split) {
        if (sub.length <= 1) {
          isolatedIdx.addAll(sub);
        } else {
          realClusters.add(sub);
        }
      }
    }
  }
  bool _clusterHasIncluded(List<int> members) {
    if (includedPaths == null || includedPaths.isEmpty) return true;
    return members.any((i) => includedPaths.contains(currentPaths[i]));
  }
  // Precompute every per-cluster sort key ONCE before the comparator
  // runs. The comparator then does only integer/reference compares —
  // no string allocation, no double parsing, no map lookups in the
  // hot loop. Sort calls the comparator O(n log n) times; doing
  // O(n) upfront work turns each step into constant-time integer
  // arithmetic.
  //
  // Fields, in comparator order:
  //   hasInc  — 0 if cluster has any included file, 1 otherwise
  //   coh100  — coherence × 100, rounded to int (kills float jitter)
  //   size    — member count (used DESC via negation)
  //   minPath — lex-min path, for the final stable tiebreak
  final clusterSortKeys = <List<int>, _ClusterSortKey>{
    for (final c in realClusters)
      c: _ClusterSortKey(
        hasInc: _clusterHasIncluded(c) ? 0 : 1,
        coh100: (_meanClusterCoherence(c, currentPaths, matrix) * 100)
            .round(),
        size: c.length,
        minPath: c
            .map((i) => currentPaths[i])
            .reduce((a, b) => a.compareTo(b) < 0 ? a : b),
      ),
  };
  realClusters.sort((x, y) {
    final kx = clusterSortKeys[x]!;
    final ky = clusterSortKeys[y]!;
    // Primary: included clusters first (design choice — "the work
    // the user is doing comes first" beats "how tightly coupled
    // this unrelated cluster is").
    if (kx.hasInc != ky.hasInc) return kx.hasInc - ky.hasInc;
    // Secondary: coherence DESC via integer compare on the rounded
    // ×100 form. No allocations, no floating-point flicker.
    if (kx.coh100 != ky.coh100) return ky.coh100 - kx.coh100;
    // Tertiary: bigger clusters first.
    if (kx.size != ky.size) return ky.size - kx.size;
    // Quaternary: lex-min path for stable alphabetical tiebreak,
    // independent of Union-Find traversal.
    return kx.minPath.compareTo(ky.minPath);
  });
  isolatedIdx.sort((x, y) => currentPaths[x].compareTo(currentPaths[y]));

  // byPath — cluster membership is independent of ordering; clusters
  // are still drawn via the rail stripe regardless of sort mode.
  final byPath = <String, int>{};
  for (var ci = 0; ci < realClusters.length; ci++) {
    for (final idx in realClusters[ci]) {
      byPath[currentPaths[idx]] = ci;
    }
  }
  for (final idx in isolatedIdx) {
    byPath[currentPaths[idx]] = FileClusters.clusterIdIsolated;
  }

  // Dominant-axis tally per cluster. Each Union-Find pair contributes
  // one vote for its axis, weighted by pair score so a strong
  // transport-lane edge beats several weak pathAffinity edges. We
  // break ties by the axis priority order declared on
  // [RelatednessAxis].
  final axisVotes = <int, Map<RelatednessAxis, double>>{};
  for (final p in pairAxes) {
    final root = uf.find(p.a);
    final clusterId = byPath[currentPaths[root]];
    if (clusterId == null || clusterId == FileClusters.clusterIdIsolated) {
      continue;
    }
    final bucket = axisVotes.putIfAbsent(clusterId, () => {});
    bucket[p.axis] = (bucket[p.axis] ?? 0.0) + p.score;
  }
  final dominantAxisByCluster = <int, RelatednessAxis>{};
  axisVotes.forEach((clusterId, votes) {
    RelatednessAxis? best;
    double bestScore = -1.0;
    int bestPriority = -1;
    votes.forEach((axis, score) {
      final priority = _axisPriority(axis);
      if (score > bestScore ||
          (score == bestScore && priority > bestPriority)) {
        bestScore = score;
        bestPriority = priority;
        best = axis;
      }
    });
    if (best != null) dominantAxisByCluster[clusterId] = best!;
  });

  // orderedPaths — the actual row order. Strategy depends on sortGuide.
  final orderedPaths = <String>[];
  switch (sortGuide) {
    case FileSortGuide.relatedProximity:
      // Grouped: clusters in (included-first, coherence DESC, size DESC,
      // alpha ASC) order. Inside each cluster, split by inclusion and
      // nearest-neighbour-chain each subgroup — so the "files I'm
      // actually committing" sit above the surrounding context, each
      // sub-chain still locally tight.
      //
      // The junction between the two sub-chains (last included, first
      // excluded) is ALSO coupling-optimized: when the excluded chain
      // would be more tightly bound to the included tail by its end
      // than by its head, we reverse it so the strongest pair sits at
      // the seam. This keeps "here's the stuff I'm committing, and
      // here's the most-related context" reading as one continuous
      // gradient of coupling rather than a size-sorted list glued to
      // another size-sorted list.
      for (final cluster in realClusters) {
        final included = <int>[];
        final excluded = <int>[];
        for (final idx in cluster) {
          if (includedPaths == null ||
              includedPaths.contains(currentPaths[idx])) {
            included.add(idx);
          } else {
            excluded.add(idx);
          }
        }
        // When the caller supplied a CorrelatednessContext, route intra-
        // cluster ordering through the spectrally-self-weighted seriator
        // — it combines jaccard×authenticity, symbol overlap, transport
        // lanes, hyperedge co-membership, and engram K-cosine into a
        // single Fiedler-seriated order, with each axis's weight set by
        // its own spectral gap. Falls back to the legacy greedy NN chain
        // when no context is present.
        final incChain = _seriateClusterWith(
          included, currentPaths, matrix, correlatednessContext,
        ).toList();
        final excChain = _seriateClusterWith(
          excluded, currentPaths, matrix, correlatednessContext,
        ).toList();
        if (incChain.isNotEmpty && excChain.length >= 2) {
          final tail = incChain.last;
          final headScore = combinedCouplingScore(
              currentPaths[tail], currentPaths[excChain.first], matrix);
          final rearScore = combinedCouplingScore(
              currentPaths[tail], currentPaths[excChain.last], matrix);
          if (rearScore > headScore) {
            // In-place two-pointer reverse — no intermediate list.
            var lo = 0;
            var hi = excChain.length - 1;
            while (lo < hi) {
              final tmp = excChain[lo];
              excChain[lo] = excChain[hi];
              excChain[hi] = tmp;
              lo++;
              hi--;
            }
          }
        }
        for (final idx in incChain) {
          orderedPaths.add(currentPaths[idx]);
        }
        for (final idx in excChain) {
          orderedPaths.add(currentPaths[idx]);
        }
      }
      // Isolated-but-included files above isolated-but-excluded.
      final isolatedIncluded = <int>[];
      final isolatedExcluded = <int>[];
      for (final idx in isolatedIdx) {
        if (includedPaths == null ||
            includedPaths.contains(currentPaths[idx])) {
          isolatedIncluded.add(idx);
        } else {
          isolatedExcluded.add(idx);
        }
      }
      for (final idx in isolatedIncluded) {
        orderedPaths.add(currentPaths[idx]);
      }
      for (final idx in isolatedExcluded) {
        orderedPaths.add(currentPaths[idx]);
      }
    case FileSortGuide.alphabetical:
      // Natural, case-insensitive sort by BASENAME (the visible
      // filename column), falling back to the full path as tiebreak
      // for same-named files in different directories.
      //
      // Sorting by full path made `apps/foo/zzz.dart` land before
      // `lib/aaa.dart` because the comparison starts on the directory
      // segments — which reads as "broken alphabetical" in a list
      // that shows filenames prominently and directories as subtitle.
      orderedPaths.addAll(
        List<String>.from(currentPaths)
          ..sort((a, b) {
            final c = _naturalCompare(_basenameOf(a), _basenameOf(b));
            if (c != 0) return c;
            return _naturalCompare(a, b);
          }),
      );
    case FileSortGuide.impact:
      // Effective impact = raw line-churn × (1 − entanglement), where
      // entanglement is the maximum Jaccard between this file and any
      // other file in the CURRENT diff. Derived entirely from
      // physical signals — no hardcoded filename lists, no magic
      // suffix patterns, no language- or platform-specific rules.
      //
      // Intuition: if a file's change is fully "explained" by its
      // co-change with another file in the same diff (Jaccard → 1),
      // the pair contributes one unit of information, not two.
      // Source+generated companions and lockfile+manifest pairs
      // naturally attenuate each other without us having to know
      // what they are. A file with no peer in the diff keeps its
      // full impact — the attenuation only fires when there's
      // actually a co-change partner participating.
      //
      // Binaries contribute 0 (we don't have file-size data to
      // score them honestly; a magic baseline would lie). They
      // sink to the bottom on ties, ordered alphabetically.
      //
      // Tiebreaks in order: included-above-excluded (parity with
      // relatedProximity's "work first, context after"), then
      // natural compare by BASENAME (the visible filename column),
      // then full path as final stabilizer.
      // Precompute effectiveImpact for every path ONCE. The sort
      // comparator would otherwise re-derive entanglement on every
      // pair comparison, turning an O(n log n) sort into O(n² log n).
      //
      // `jaccardMaxNeighborMap` does the full max-peer pass in ONE
      // sweep of the CSR, crediting each edge to both endpoints —
      // O(nnz + n) total, independent of how many paths are in the
      // current change-set. Replaces the previous per-path
      // `jaccardEntriesOf` loop which only saw the upper-triangle
      // slice of each row: lex-late paths were mechanically
      // undercounted because their would-be partners sat in earlier
      // rows. This is a correctness fix as well as a perf one — the
      // entanglement score each file gets is now independent of how
      // its path happens to sort.
      final signals = impactSignals ?? const <String, FileImpactSignal>{};
      final pathSet = currentPaths.toSet();
      final maxPeerJ = matrix.jaccardMaxNeighborMap(restrict: pathSet);
      final effective = <String, double>{};
      final basenames = <String, String>{};
      for (final p in currentPaths) {
        final s = signals[p];
        final raw = (s == null || s.binary) ? 0.0 : (s.adds + s.dels).toDouble();
        final maxJ = raw > 0 ? (maxPeerJ[p] ?? 0.0) : 0.0;
        effective[p] = raw * (1 - maxJ);
        basenames[p] = _basenameOf(p);
      }
      final ranked = List<String>.from(currentPaths);
      ranked.sort((a, b) {
        final sa = effective[a] ?? 0.0;
        final sb = effective[b] ?? 0.0;
        final c = sb.compareTo(sa);
        if (c != 0) return c;
        final aIn = includedPaths == null || includedPaths.contains(a);
        final bIn = includedPaths == null || includedPaths.contains(b);
        if (aIn != bIn) return aIn ? -1 : 1;
        final bc = _naturalCompare(basenames[a]!, basenames[b]!);
        if (bc != 0) return bc;
        return _naturalCompare(a, b);
      });
      orderedPaths.addAll(ranked);
  }

  // Smart invert: reverse the mode's ordered list. Applied BEFORE the
  // conflict float so conflicts still end up at position 0 regardless.
  // Each mode's notion of "opposite" is just "flip the list" — but
  // because each mode has its own ordering logic (cluster grouping,
  // alphabetical, weight), the reversal produces the semantically
  // appropriate inverse automatically:
  //   * related reversed → isolated-excluded first, tight-cluster-
  //     included last → "odd ones out on top."
  //   * alphabetical reversed → Z → A.
  //   * impact reversed → smallest churn first.
  if (inverted) {
    orderedPaths.setAll(0, orderedPaths.reversed.toList());
  }

  // Universal float-to-top for the user's selection: files included in
  // the current commit always sit above excluded files, whatever the
  // sort mode. The mode still decides order WITHIN each group — so
  // alphabetical-mode keeps its A→Z ordering within selected, then A→Z
  // within unselected, rather than silently losing selection as a
  // tie-break. `relatedProximity` already did this within clusters; the
  // float below makes the same semantics universal. Preserves relative
  // order within each partition so the mode's work isn't undone.
  if (includedPaths != null && includedPaths.isNotEmpty) {
    final selected = <String>[];
    final unselected = <String>[];
    for (final p in orderedPaths) {
      if (includedPaths.contains(p)) {
        selected.add(p);
      } else {
        unselected.add(p);
      }
    }
    if (selected.isNotEmpty && unselected.isNotEmpty) {
      orderedPaths
        ..clear()
        ..addAll(selected)
        ..addAll(unselected);
    }
  }

  // Universal float-to-top: merge conflicts block every commit. Whatever
  // the sort mode, conflicted files belong at eye level. Preserves their
  // relative order as produced by the main sort below.
  if (conflictedPaths != null && conflictedPaths.isNotEmpty) {
    final conflicted = <String>[];
    final rest = <String>[];
    for (final p in orderedPaths) {
      if (conflictedPaths.contains(p)) {
        conflicted.add(p);
      } else {
        rest.add(p);
      }
    }
    orderedPaths
      ..clear()
      ..addAll(conflicted)
      ..addAll(rest);
  }

  return FileClusters(
    byPath: byPath,
    clusterCount: realClusters.length,
    orderedPaths: orderedPaths,
    dominantAxisByCluster: dominantAxisByCluster,
  );
}

/// Axis priority for dominant-axis tiebreaks. Higher = more
/// semantically specific. `transport` wins over `coChange` when vote
/// scores are equal because a structural lane is a stronger claim
/// than mere historical co-change; `pathAffinity` loses every tie
/// because sibling-directory is the weakest signal in the set.
int _axisPriority(RelatednessAxis a) {
  switch (a) {
    case RelatednessAxis.spectral:
      return 5;
    case RelatednessAxis.transport:
      return 4;
    case RelatednessAxis.hunk:
      return 3;
    case RelatednessAxis.coChange:
      return 2;
    case RelatednessAxis.symbol:
      return 1;
    case RelatednessAxis.pathAffinity:
      return 0;
  }
}

/// Natural, case-insensitive path comparator.
/// Walks both strings in lockstep, comparing digit runs *numerically*
/// and non-digit runs *case-insensitively*. So `migration-10.sql` sorts
/// after `migration-2.sql`, and `README.md` doesn't leapfrog `src/` just
/// because uppercase codepoints are lower in ASCII.
/// Falls back to the raw `compareTo` as a final tiebreaker so the sort
/// is deterministic even for strings that differ only in case.
int _naturalCompare(String a, String b) {
  final aLen = a.length;
  final bLen = b.length;
  var i = 0;
  var j = 0;
  while (i < aLen && j < bLen) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    final aDigit = _isDigit(ca);
    final bDigit = _isDigit(cb);
    if (aDigit && bDigit) {
      // Consume both digit runs, compare numerically by length then value.
      var aEnd = i;
      while (aEnd < aLen && _isDigit(a.codeUnitAt(aEnd))) {
        aEnd++;
      }
      var bEnd = j;
      while (bEnd < bLen && _isDigit(b.codeUnitAt(bEnd))) {
        bEnd++;
      }
      // Strip leading zeros for magnitude compare; shorter = smaller.
      final aDigits = _stripLeadingZeros(a.substring(i, aEnd));
      final bDigits = _stripLeadingZeros(b.substring(j, bEnd));
      if (aDigits.length != bDigits.length) {
        return aDigits.length - bDigits.length;
      }
      final cmp = aDigits.compareTo(bDigits);
      if (cmp != 0) return cmp;
      i = aEnd;
      j = bEnd;
    } else if (aDigit != bDigit) {
      // One side is numeric, the other textual — numeric sorts earlier
      // so "v2" < "v_alpha". Subjective but consistent with most UIs.
      return aDigit ? -1 : 1;
    } else {
      // Both non-digit — compare case-insensitively, then case-sensitively
      // on equality so 'a' and 'A' stay stable relative to each other.
      final la = _toLower(ca);
      final lb = _toLower(cb);
      if (la != lb) return la - lb;
      if (ca != cb) return ca - cb;
      i++;
      j++;
    }
  }
  if (i < aLen) return 1;
  if (j < bLen) return -1;
  return 0;
}

/// Last path segment, handling both forward and back slashes. Walks
/// from the end and bails at the first separator — zero allocation
/// when the path has no separator, single `substring` otherwise.
/// Called in tight sort comparators, so the "no `replaceAll` scan on
/// every invocation" shape matters.
String _basenameOf(String path) {
  for (var i = path.length - 1; i >= 0; i--) {
    final c = path.codeUnitAt(i);
    if (c == 0x2F /* / */ || c == 0x5C /* \ */) {
      return path.substring(i + 1);
    }
  }
  return path;
}

/// Per-path raw diff signal consumed by [FileSortGuide.impact].
/// The sort uses this + the coupling matrix to derive effective
/// impact without any hardcoded filename rules — the attenuation
/// emerges from co-change physics, not a filetype whitelist.
/// Kept minimal on purpose: `adds` and `dels` are literal numstat
/// counts, `binary` tells the scorer "we can't count lines here."
/// No language-specific fields; no platform conventions baked in.
class FileImpactSignal {
  final int adds;
  final int dels;
  final bool binary;
  const FileImpactSignal({
    required this.adds,
    required this.dels,
    this.binary = false,
  });
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

int _toLower(int codeUnit) {
  if (codeUnit >= 0x41 && codeUnit <= 0x5A) return codeUnit + 0x20;
  return codeUnit;
}

String _stripLeadingZeros(String digits) {
  var i = 0;
  while (i < digits.length - 1 && digits.codeUnitAt(i) == 0x30) {
    i++;
  }
  return i == 0 ? digits : digits.substring(i);
}

/// Seriate a cluster's members so that adjacent files in the returned
/// order have the strongest pairwise coupling possible.
/// Greedy nearest-neighbour chain:
///   1. Seed with the highest-scoring pair in the cluster.
///   2. Extend from either end by the unplaced member with the strongest
///      coupling to that endpoint.
/// O(n²) per cluster — trivial for real change sets. Ties break on lex
/// order of the path so the output stays deterministic across runs and
/// files that truly have no coupling signal degrade gracefully to
/// alphabetical.
/// Dispatcher: when the caller has already run the logos hunk pipeline
/// and bundled the result in `context`, we route the cluster's files
/// through the Fiedler vector of the engine's OWN hunk graph — the
/// most faithful 1D ordering the engine can give. When context is
/// null (cold engine, no diff cached yet), we fall back to the legacy
/// greedy nearest-neighbour chain on the file-level coupling matrix.
List<int> _seriateClusterWith(
  List<int> members,
  List<String> paths,
  FileCouplingMatrix matrix,
  CorrelatednessContext? context,
) {
  if (members.length <= 2 || context == null) {
    return _seriateCluster(members, paths, matrix);
  }
  final localPaths = [for (final i in members) paths[i]];
  final ordered = seriateByHunkFiedler(localPaths, context);
  if (ordered.length != members.length) {
    return _seriateCluster(members, paths, matrix);
  }
  final localIndexOf = <String, int>{
    for (var i = 0; i < localPaths.length; i++) localPaths[i]: i,
  };
  return [for (final p in ordered) members[localIndexOf[p]!]];
}

List<int> _seriateCluster(
  List<int> members,
  List<String> paths,
  FileCouplingMatrix matrix,
) {
  final n = members.length;
  if (n <= 2) return members;

  // One pair-score computation per pair — cache into a flat O(n²)
  // matrix. The hub-degree loop, seed-pair loop, and chain-extension
  // loop all read from this. Without caching, each phase redundantly
  // calls `combinedCouplingScore` on the same pairs. With n=20
  // typical, that's 400 cached scores vs. ~1200 redundant calls.
  //
  // Indexed by dense position within `members`, not the original
  // `paths` index — the cluster is local, the matrix is local, and
  // the symmetry `pair[i][j] == pair[j][i]` lets us walk only the
  // upper triangle.
  final pair = List<Float64List>.generate(n, (_) => Float64List(n));
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final s = combinedCouplingScore(paths[members[i]], paths[members[j]], matrix);
      pair[i][j] = s;
      pair[j][i] = s;
    }
  }

  // Precompute each member's hub degree (total coupling to the rest
  // of the cluster) in one linear pass over the cached matrix.
  final hubDegree = Float64List(n);
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    for (var j = 0; j < n; j++) {
      if (i != j) s += pair[i][j];
    }
    hubDegree[i] = s;
  }

  // Precompute each member's parent directory so the sibling-tiebreak
  // in the chain-extension loop is a cheap string equality test, not
  // a replaceAll + lastIndexOf + substring on every comparison.
  final parentDir = List<String?>.generate(n, (i) {
    final p = paths[members[i]];
    for (var k = p.length - 1; k >= 0; k--) {
      final c = p.codeUnitAt(k);
      if (c == 0x2F /* / */ || c == 0x5C /* \ */) return p.substring(0, k);
    }
    return null;
  });

  // Pick the best starting pair: `pair_score + 0.1 × min(hub)`.
  // Weighting the WEAKER endpoint prevents a single hub from dragging
  // an otherwise-weak pair to the top; both sides must pull their
  // weight. Alphabetical tiebreak for stability.
  var bestPairScore = -1.0;
  var seedA = 0;
  var seedB = 1;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final composite =
          pair[i][j] + 0.1 * math.min(hubDegree[i], hubDegree[j]);
      if (composite > bestPairScore ||
          (composite == bestPairScore &&
              _lexBefore(
                paths[members[i]],
                paths[members[j]],
                paths[members[seedA]],
                paths[members[seedB]],
              ))) {
        bestPairScore = composite;
        seedA = i;
        seedB = j;
      }
    }
  }

  // Orient the seed so the higher-degree hub lands at index 0 (the
  // "backbone" file sits at the top of the cluster). Tiebreak
  // alphabetical.
  {
    final dA = hubDegree[seedA];
    final dB = hubDegree[seedB];
    if (dB > dA ||
        (dB == dA &&
            paths[members[seedB]].compareTo(paths[members[seedA]]) < 0)) {
      final t = seedA;
      seedA = seedB;
      seedB = t;
    }
  }

  final chain = <int>[seedA, seedB];
  // Track remaining by a visited bitset so removal is O(1) and we
  // never reshuffle a growing/shrinking list.
  final visited = List<bool>.filled(n, false);
  visited[seedA] = true;
  visited[seedB] = true;

  for (var step = 2; step < n; step++) {
    final frontIdx = chain.first;
    final backIdx = chain.last;
    var bestPos = -1;
    var bestPrepend = false;
    var bestScore = -1.0;
    var bestSiblingBoost = -1;
    String? bestTiebreak;
    for (var k = 0; k < n; k++) {
      if (visited[k]) continue;
      final frontScore = pair[k][frontIdx];
      final backScore = pair[k][backIdx];
      final prepend = frontScore > backScore;
      final localScore = prepend ? frontScore : backScore;
      final anchorDir = prepend ? parentDir[frontIdx] : parentDir[backIdx];
      final sibling =
          (parentDir[k] != null && parentDir[k] == anchorDir) ? 1 : 0;
      final kPath = paths[members[k]];
      final betterScore = localScore > bestScore;
      final equalScore = localScore == bestScore;
      final betterSibling = equalScore && sibling > bestSiblingBoost;
      final lexBreak = equalScore &&
          sibling == bestSiblingBoost &&
          (bestTiebreak == null || kPath.compareTo(bestTiebreak) < 0);
      if (betterScore || betterSibling || lexBreak) {
        bestScore = localScore;
        bestPos = k;
        bestPrepend = prepend;
        bestSiblingBoost = sibling;
        bestTiebreak = kPath;
      }
    }
    visited[bestPos] = true;
    if (bestPrepend) {
      chain.insert(0, bestPos);
    } else {
      chain.add(bestPos);
    }
  }

  // Map dense indices back to the caller's path indices.
  return [for (final i in chain) members[i]];
}

/// Mean pairwise coupling among a cluster's members — used by
/// `clusterFiles` to order clusters by tightness instead of raw size.
/// Returns 0 for 0- or 1-member clusters (no pairs to average).
double _meanClusterCoherence(
  List<int> members,
  List<String> paths,
  FileCouplingMatrix matrix,
) {
  if (members.length < 2) return 0;
  var sum = 0.0;
  var pairs = 0;
  for (var i = 0; i < members.length; i++) {
    for (var j = i + 1; j < members.length; j++) {
      sum += combinedCouplingScore(paths[members[i]], paths[members[j]], matrix);
      pairs++;
    }
  }
  return pairs == 0 ? 0 : sum / pairs;
}

/// Compare two pairs of paths for a stable tiebreak when seed-pair scores
/// are equal: prefer the pair whose min-path is lex-smaller.
bool _lexBefore(String a, String b, String seedA, String seedB) {
  final candidate = a.compareTo(b) < 0 ? a : b;
  final seed = seedA.compareTo(seedB) < 0 ? seedA : seedB;
  return candidate.compareTo(seed) < 0;
}

class _PairScore {
  final double score;
  final int a;
  final int b;
  final RelatednessAxis axis;
  const _PairScore(this.score, this.a, this.b, this.axis);
}

/// Precomputed sort key for a cluster — populated once outside the
/// comparator so the actual sort step is pure integer arithmetic.
class _ClusterSortKey {
  final int hasInc;
  final int coh100;
  final int size;
  final String minPath;
  const _ClusterSortKey({
    required this.hasInc,
    required this.coh100,
    required this.size,
    required this.minPath,
  });
}

class _UnionFind {
  final List<int> parent;
  final List<int> rank;
  _UnionFind(int n)
      : parent = List<int>.generate(n, (i) => i, growable: false),
        rank = List<int>.filled(n, 0);

  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]]; // path compression (halving)
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    if (rank[ra] < rank[rb]) {
      parent[ra] = rb;
    } else if (rank[ra] > rank[rb]) {
      parent[rb] = ra;
    } else {
      parent[rb] = ra;
      rank[ra]++;
    }
  }
}

/// Language-agnostic path-structure signal. Returns 0..1 based on how much
/// of the directory path and filename stem two paths share.
/// Used as a fallback coupling signal for files with no git history yet
/// (new/untracked files). No regex matching on language-specific patterns —
/// just string overlap, so it works for any filesystem layout.
double pathAffinity(String a, String b) {
  if (a == b) return 1.0;
  final aNorm = a.replaceAll('\\', '/');
  final bNorm = b.replaceAll('\\', '/');
  final aSegs = aNorm.split('/');
  final bSegs = bNorm.split('/');

  // Shared directory prefix (excludes the filename itself).
  var sharedDirs = 0;
  final maxPrefix = math.min(aSegs.length, bSegs.length) - 1;
  for (var i = 0; i < maxPrefix; i++) {
    if (aSegs[i] != bSegs[i]) break;
    sharedDirs++;
  }
  final maxDirs = math.max(aSegs.length, bSegs.length) - 1;
  final dirScore = maxDirs > 0 ? sharedDirs / maxDirs : 0.0;

  // Basename stem similarity — longest common prefix of the bare names,
  // stripped of the rightmost extension.
  final aStem = _stripExt(aSegs.last);
  final bStem = _stripExt(bSegs.last);
  var common = 0;
  final minLen = math.min(aStem.length, bStem.length);
  for (var i = 0; i < minLen; i++) {
    if (aStem[i] != bStem[i]) break;
    common++;
  }
  // Dice coefficient: 2·common / (|a| + |b|). Symmetric and penalises
  // neither party for having a longer name — unlike common/max, which
  // under-scores pairs like `file_coupling` vs `file_constellation`
  // because the shared prefix (`file_co`) is measured against the longer
  // stem's full length rather than the combined mass.
  final totalStem = aStem.length + bStem.length;
  final stemScore = totalStem > 0 ? (2.0 * common) / totalStem : 0.0;

  // Require BOTH some dir overlap AND some name overlap to couple by path.
  // This prevents unrelated files in a flat directory from being grouped
  // (same-dir alone is too weak a signal; same-name alone is too).
  return dirScore * stemScore;
}

String _stripExt(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot > 0 ? filename.substring(0, dot) : filename;
}

// SYMBOL-OVERLAP COUPLING — structural axis for new / untracked files
//
// Co-change history is a lagging signal: it can only score files that have
// appeared together in at least one prior commit. A brand-new file has zero
// Jaccard against everything, so the historical axis is blind to it.
//
// Symbol overlap is a leading signal: it scores files by shared identifier
// usage right now, before any commit exists. A file that uses FileClusters
// and FileCouplingMatrix is structurally coupled to file_coupling.dart
// regardless of whether that relationship has ever appeared in git log.
//
//
// Scoring is IDF-weighted Jaccard over identifier sets. The IDF weights
// come from a CORPUS-WIDE document-frequency index built once per repo
// ([SymbolFrequencyIndex] — scanned from every tracked file, cached by
// HEAD hash). This makes the filter self-learning and language-agnostic:
//   • `def` appears in every Python file → df is huge → idf ≈ 0 → ignored
//   • `func` appears in every Go file → same
//   • `FileCouplingMatrix` appears in 2 files repo-wide → idf is high
//   • the repo *teaches* the filter what's noise vs signal
//
// No hardcoded language keywords. No per-language stop-word lists. The
// math is the filter. The only fallback (when the corpus index hasn't
// been built yet) is change-set-local IDF plus a tiny universal
// C-family keyword set — enough to keep cold-start sane without biasing.
//
//   idf(id) = ln(1 + N / (1 + df(id)))   [corpus available]
//   idf(id) = 1 / df_local(id)           [change-set fallback]
//
//   overlap(a, b) = Σ idf(id) for id in a∩b
//                   Σ idf(id) for id in a∪b

/// Max file size we'll read for symbol extraction. Avoids tokenising
/// multi-megabyte generated files or binary blobs with a source extension.
const int _symMaxBytes = 256 * 1024; // 256 KB

/// Hard cap on files scanned when building the corpus frequency index.
/// Beyond this, a uniform random sample is taken — at 2000 files the
/// df estimates are already well-converged for any reasonable codebase.
const int _symCorpusSampleCap = 2000;

/// Minimal, language-neutral cold-start filter. Only universal
/// C-family keywords that the IDF corpus would downweight anyway if it
/// were warm. Deliberately short — the corpus index is the real filter.
/// Single-/two-character tokens are already excluded by the identifier
/// regex (`{2,}` suffix), so nothing here is shorter than 3 chars.
const Set<String> _symColdStartFilter = {
  'for', 'while', 'return', 'class', 'struct', 'enum', 'union',
  'true', 'false', 'null', 'nil', 'None', 'undefined',
  'new', 'this', 'self', 'super', 'super_',
  'public', 'private', 'protected', 'static', 'const', 'final',
  'let', 'var', 'val', 'mut',
  'import', 'export', 'from', 'package', 'using', 'module',
  'void', 'int', 'bool', 'string', 'float',
  'def', 'fun', 'func', 'fn', 'sub', 'lambda',
  'try', 'catch', 'throw', 'throws', 'except', 'finally',
  'async', 'await', 'yield',
};

/// Extract meaningful identifier tokens from [content].
/// Language-agnostic: matches any C-family identifier (3+ chars,
/// alphanumeric + underscore). Works for Dart, Python, Go, Rust, JS,
/// TS, Java, C, C++, Kotlin, Swift, Ruby, etc.
Set<String> _extractSymbols(String content) {
  final out = <String>{};
  final pattern = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]{2,})\b');
  for (final m in pattern.allMatches(content)) {
    final id = m.group(1)!;
    if (!_symColdStartFilter.contains(id)) out.add(id);
  }
  return out;
}

/// Read [path] (relative to [repoRoot]) and extract its symbol set.
/// Returns empty on I/O error, missing file, or oversize file.
Set<String> symbolsForFile(String repoRoot, String path) {
  try {
    final file = File(p.join(repoRoot, p.joinAll(path.split('/'))));
    if (!file.existsSync()) return const {};
    if (file.lengthSync() > _symMaxBytes) return const {};
    return _extractSymbols(file.readAsStringSync());
  } catch (_) {
    return const {};
  }
}

/// Corpus-wide identifier document-frequency index.
/// Built once per repo (keyed by HEAD hash) by scanning every tracked
/// file's identifier set. Replaces hardcoded language-specific stop-word
/// lists: any identifier that appears in most of the repo's files ends up
/// with near-zero IDF weight automatically, whether that's `def` in a
/// Python project or `public` in a Java project. The repo teaches the
/// filter what's noise.
/// Computed asynchronously in the background (see
/// `computeSymbolFrequencyIndex`); change-set coupling falls back to
/// local IDF when the index isn't ready yet.
class SymbolFrequencyIndex {
  /// identifier → number of documents containing it (1 ≤ df ≤ totalDocuments).
  final Map<String, int> documentFrequency;

  /// Total distinct documents scanned (denominator for IDF).
  final int totalDocuments;

  /// HEAD hash at the time of indexing. Callers invalidate when HEAD moves.
  final String headHash;

  const SymbolFrequencyIndex({
    required this.documentFrequency,
    required this.totalDocuments,
    required this.headHash,
  });

  /// Inverse-document-frequency weight for [term].
  /// Uses the smoothed form `ln(1 + N / (1 + df))`. Bounded below by 0
  /// (terms appearing in every document) and above by `ln(1 + N)` (terms
  /// never seen in the corpus — could be new symbols in the change set).
  /// A term in 50% of the corpus gets roughly `ln(1 + 2) ≈ 1.1`; a term
  /// in 1% gets `ln(1 + 100) ≈ 4.6`. Rare terms dominate, common terms
  /// vanish — the self-learning stop-word filter.
  double idf(String term) {
    if (totalDocuments <= 0) return 1.0;
    final df = documentFrequency[term] ?? 0;
    return math.log(1 + totalDocuments / (1 + df));
  }

  bool get isEmpty => totalDocuments == 0;
  bool get isNotEmpty => totalDocuments > 0;

  static const empty = SymbolFrequencyIndex(
    documentFrequency: {},
    totalDocuments: 0,
    headHash: '',
  );
}

/// Build a [SymbolFrequencyIndex] for the repo at [repoRoot].
/// Uses `git ls-files` to enumerate tracked files. When the corpus
/// exceeds [maxFiles], a uniform random sample is taken — df estimates
/// converge fast, so 2000 files is plenty for any codebase.
/// [sampleSeed] gives deterministic sampling for tests; leave null in
/// production (wall-clock seeded).
Future<GitResult<SymbolFrequencyIndex>> computeSymbolFrequencyIndex(
  String repoRoot, {
  int maxFiles = _symCorpusSampleCap,
  int? sampleSeed,
}) async {
  final lsProbe = await runGitProbe(repoRoot, ['ls-files']);
  if (lsProbe.exitCode != 0) {
    return GitResult.err(lsProbe.stderr.toString().trim());
  }

  final headProbe = await runGitProbe(repoRoot, ['rev-parse', 'HEAD']);
  final headHash =
      headProbe.exitCode == 0 ? headProbe.stdout.toString().trim() : '';

  final allPaths = const LineSplitter()
      .convert(lsProbe.stdout.toString())
      .where((l) => l.isNotEmpty)
      .toList();

  // Uniform random sample when the repo is large. Deterministic when
  // [sampleSeed] is set. We pick files, not bytes — a tiny file counts
  // the same as a big one for df estimation, which is what we want.
  List<String> scan;
  if (allPaths.length > maxFiles) {
    final rng = math.Random(sampleSeed ?? DateTime.now().millisecondsSinceEpoch);
    final shuffled = [...allPaths]..shuffle(rng);
    scan = shuffled.take(maxFiles).toList();
  } else {
    scan = allPaths;
  }

  final df = <String, int>{};
  var totalDocs = 0;
  for (final path in scan) {
    final syms = symbolsForFile(repoRoot, path);
    if (syms.isEmpty) continue;
    totalDocs++;
    for (final sym in syms) {
      df[sym] = (df[sym] ?? 0) + 1;
    }
  }

  return GitResult.ok(
    SymbolFrequencyIndex(
      documentFrequency: df,
      totalDocuments: totalDocs,
      headHash: headHash,
    ),
  );
}

/// Compute pairwise symbol-overlap coupling for [paths].
/// Returns an upper-triangle map (same convention as [FileCouplingMatrix.jaccard])
/// of IDF-weighted Jaccard scores. Only pairs with a non-zero score are
/// stored.
/// When [corpus] is provided and non-empty, uses corpus-wide IDF (the
/// self-learning, language-agnostic filter). Otherwise falls back to
/// change-set-local IDF — the local `1 / df_local` form is a good
/// proxy when n is small but can overweight rare language keywords in
/// tiny change sets; prefer passing a warm corpus when available.
Map<String, Map<String, double>> computeSymbolCoupling(
  List<String> paths,
  String repoRoot, {
  SymbolFrequencyIndex? corpus,
}) {
  if (paths.length < 2) return const {};

  // Read identifier sets for every file in the change set.
  final symSets = <String, Set<String>>{};
  for (final path in paths) {
    final syms = symbolsForFile(repoRoot, path);
    if (syms.isNotEmpty) symSets[path] = syms;
  }
  if (symSets.length < 2) return const {};

  // Resolve an IDF function once — corpus if warm, local fallback if not.
  final bool useCorpus = corpus != null && corpus.isNotEmpty;
  double Function(String) idfOf;
  if (useCorpus) {
    idfOf = corpus.idf;
  } else {
    final localDf = <String, int>{};
    for (final syms in symSets.values) {
      for (final id in syms) {
        localDf[id] = (localDf[id] ?? 0) + 1;
      }
    }
    final localN = symSets.length;
    idfOf = (id) {
      final df = localDf[id] ?? 0;
      return math.log(1 + localN / (1 + df));
    };
  }

  // IDF-weighted Jaccard for each pair (upper triangle only).
  final result = <String, Map<String, double>>{};
  final fileList = symSets.keys.toList();
  for (var i = 0; i < fileList.length; i++) {
    for (var j = i + 1; j < fileList.length; j++) {
      final a = fileList[i];
      final b = fileList[j];
      final symsA = symSets[a]!;
      final symsB = symSets[b]!;

      var numerator = 0.0;
      var denominator = 0.0;

      // Walk the union; intersection contributes to both.
      for (final id in symsA) {
        final w = idfOf(id);
        denominator += w;
        if (symsB.contains(id)) numerator += w;
      }
      for (final id in symsB) {
        if (!symsA.contains(id)) denominator += idfOf(id);
      }

      if (numerator == 0 || denominator == 0) continue;
      final score = numerator / denominator;

      // Upper-triangle: lex order for consistency with jaccard storage.
      final lo = a.compareTo(b) < 0 ? a : b;
      final hi = a.compareTo(b) < 0 ? b : a;
      (result[lo] ??= {})[hi] = score;
    }
  }
  return result;
}


/// Coupling score used by clustering and seriation.
/// Reads the blended score from the matrix (historical Jaccard + symbol
/// overlap, whichever is stronger). Falls back to path-structure affinity
/// only when the matrix has no signal at all for the pair — typically two
/// files that are both new AND share no identifiers.
/// If BOTH files have real co-change history and the score is still 0,
/// that's meaningful: they've been tracked and they don't co-change.
/// pathAffinity must NOT fire in that case — it would manufacture
/// coupling that contradicts the historical record and corrupt
/// clustering for pairs that deliberately don't co-change.
/// The gate uses [FileCouplingMatrix.hasJaccardRow], NOT `containsPath`:
/// after `withSymbol` layers untracked files into the id space,
/// `containsPath` returns true for them too and the original "both
/// tracked → trust history" fallback would mute pathAffinity for every
/// untracked pair. Checking the jaccard row directly keeps the
/// semantic "does this file actually have git-history evidence?" stable
/// across that layering.
double combinedCouplingScore(String a, String b, FileCouplingMatrix m) {
  final s = m.score(a, b);
  if (s > 0) return s;
  // Both files have real co-change history with no co-change → trust it.
  if (m.hasJaccardRow(a) && m.hasJaccardRow(b)) return 0.0;
  return pathAffinity(a, b);
}

/// How many cluster colors we cycle through before stepping the alpha down.
/// Exposed for the color helper to stay in sync.
const int kFileClusterPaletteSize = 4;

/// Estimate how much information was used for a coupling decision.
/// Useful when rendering the header signal (low data → less confident).
double couplingConfidence(FileCouplingMatrix matrix) {
  if (matrix.commitsAnalyzed <= 0) return 0;
  // Saturation point adapts to the matrix's own density: the number
  // of tracked files is a proxy for how many commits are needed to
  // build reliable pairwise evidence. A 50-file repo saturates much
  // faster than a 5000-file repo.
  final saturation = math.max(50.0, matrix.trackedFileCount * 0.4);
  return math.min(1.0, matrix.commitsAnalyzed / saturation);
}

/// A single "you might have forgotten this" signal: an unselected changed
/// file whose coupling to the current selection is strong enough that
/// committing without it is likely a bug or a split the user didn't mean
/// to make.
class CouplingNudge {
  /// The unselected file the user is being nudged about.
  final String path;

  /// Mean `combinedCouplingScore` against the selection. 0..1.
  final double score;

  /// The selected peer with the tightest coupling — used to render the
  /// "because this file goes with X" affordance.
  final String anchor;

  const CouplingNudge({
    required this.path,
    required this.score,
    required this.anchor,
  });
}

/// Rank unselected files by how tightly they couple to the current
/// selection. The threshold scales by [couplingConfidence] so sparse
/// repos demand proportionally stronger signal instead of gating to
/// zero on an arbitrary commit count.
List<CouplingNudge> suggestMissingPeers({
  required Iterable<String> selected,
  required Iterable<String> allChanged,
  required FileCouplingMatrix matrix,
  double threshold = 0.25,
  int limit = 5,
}) {
  final selectedList = selected.toList(growable: false);
  if (selectedList.isEmpty) return const [];
  final confidence = couplingConfidence(matrix);
  if (confidence <= 0) return const [];

  final selectedSet = selectedList.toSet();
  final changedSet = allChanged.toSet();

  final nudges = <String, CouplingNudge>{};
  for (final p in changedSet) {
    if (selectedSet.contains(p)) continue;
    final (mean, anchor) = _meanCoupling(p, selectedList, matrix);
    final effective = mean * confidence;
    if (effective < threshold) continue;
    nudges[p] = CouplingNudge(path: p, score: mean, anchor: anchor);
  }

  final result = nudges.values.toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  if (result.length > limit) return result.sublist(0, limit);
  return result;
}

(double, String) _meanCoupling(
  String path,
  List<String> selected,
  FileCouplingMatrix matrix,
) {
  double sum = 0.0;
  double best = 0.0;
  String bestAnchor = selected.first;
  for (final s in selected) {
    final c = combinedCouplingScore(path, s, matrix);
    sum += c;
    if (c > best) {
      best = c;
      bestAnchor = s;
    }
  }
  return (sum / selected.length, bestAnchor);
}
