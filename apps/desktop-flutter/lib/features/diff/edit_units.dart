import 'diff_models.dart';

/// Semantic kinds a row of a diff can represent. Unlike [LineKind] (which is
/// a property of a single ParsedLine), EditUnit groups related lines into a
/// single semantic change — a replacement pair is one unit with two sides,
/// a detected block-move is one unit pointing at its partner, etc.
enum EditKind { context, hunk, meta, insert, delete, replace, move }

/// A semantically-meaningful row of a diff. Built by [buildEditUnits] from a
/// flat [ParsedLine] stream; used by the display / search / navigation layers
/// as the canonical unit of change. The patch engine continues to operate on
/// raw ParsedLines — EditUnit is a VIEW, not a replacement for the staging
/// authority.
///
/// Every EditUnit has a stable [id] derived from content + position that does
/// NOT depend on staged state. That makes it safe as an animation / widget
/// key across stage toggles and scroll recycling.
///
/// The id is a 64-bit integer computed via the SplitMix64 avalanche
/// (Principia Circle XVII) over the unit's structural fingerprint. This
/// replaces the older string-form id (`'rp:3:45:46:1234:5678'`), which
/// allocated a heap string per unit per rebuild and forced string hashing
/// in every `Set<String>` / `Map<String, ...>` hot path. Integer identity
/// lets animation keys, seen-unit sets, and pulse-target lookups run as
/// single-cycle comparisons with zero GC pressure. Collision risk at 64
/// bits is ~2^{-64} (Principia Circle XLV, the Birthday Bound) — sound
/// for any conceivable diff size.
class EditUnit {
  final int id;
  final EditKind kind;
  final List<ParsedLine> oldLines;
  final List<ParsedLine> newLines;
  final int hunkIndex;
  final String? filePath;

  /// For [EditKind.move]: the id of the partner unit. Zero-valued for
  /// non-moves (0 is chosen as the sentinel because a splitmix64 avalanche
  /// of non-zero structural data returns 0 with probability 2^{-64}).
  final int moveTargetId;

  /// SWAR presence bitmap — OR of all constituent lines' charBits. Used as a
  /// one-AND pre-filter for polyphonic search: a unit whose combined char
  /// set doesn't contain every character of the query can be rejected
  /// before [searchText] is ever materialized. See [ParsedLine.charBits].
  final int charBits;

  /// Bigram bitmap — OR of constituent lines' [ParsedLine.bigramBits].
  /// Bigrams DON'T cross line boundaries (would introduce false hits at
  /// line seams), so the union is a safe upper bound: if a query bigram
  /// isn't present in any constituent line, it isn't in the unit.
  final int bigramBits;

  /// First constituent line's [ParsedLine.simHash], carried for the
  /// fuzzy move-detection pass. Single-line units use that line directly;
  /// multi-line blocks (replaces) use the delete side as the reference
  /// since that's what move-from lookups key against. Zero for units
  /// with no applicable source (hunk/meta headers).
  final int simHash;

  const EditUnit({
    required this.id,
    required this.kind,
    this.oldLines = const [],
    this.newLines = const [],
    this.hunkIndex = -1,
    this.filePath,
    this.moveTargetId = 0,
    this.charBits = 0,
    this.bigramBits = 0,
    this.simHash = 0,
  });

  bool get isStageable =>
      kind == EditKind.insert ||
      kind == EditKind.delete ||
      kind == EditKind.replace ||
      kind == EditKind.move;

  /// Polyphonic search text — matches tokens on either the OLD side or the
  /// NEW side of the unit. A rename `foo()` → `bar()` matches both "foo" and
  /// "bar", fixing the blind spot where only the delete's tokens were
  /// searchable after pair fusion.
  ///
  /// Recomputed per call; callers doing tight-loop search (e.g. typed-query
  /// filtering on large diffs) should hoist the value into a local.
  String get searchText {
    final buf = StringBuffer();
    for (final l in oldLines) {
      buf.write(l.lowerText);
      buf.writeCharCode(0x0A);
    }
    for (final l in newLines) {
      buf.write(l.lowerText);
      buf.writeCharCode(0x0A);
    }
    return buf.toString();
  }
}

/// Kind tag values baked into unit ids so the avalanche input differs
/// between a context and a delete of the same line, preventing collisions
/// between structurally-adjacent-but-semantically-distinct units.
const int _tagHunk = 0x1;
const int _tagMeta = 0x2;
const int _tagContext = 0x3;
const int _tagDelete = 0x4;
const int _tagInsert = 0x5;
const int _tagReplace = 0x6;

int _idForSingleLine(int tag, ParsedLine l) =>
    splitmix64((tag << 56) ^ l.fastKey);

int _idForPair(int tag, ParsedLine a, ParsedLine b) =>
    splitmix64((tag << 56) ^ a.fastKey ^ splitmix64(b.fastKey));

String stripDiffLineSign(String text) {
  if (text.isEmpty) return text;
  final c = text.codeUnitAt(0);
  if (c == 0x2B /* + */ || c == 0x2D /* - */) {
    return text.substring(1);
  }
  return text;
}

/// Compute a rolling 64-bit content hash of a diff line's text, normalized
/// for block-move matching: strip the leading +/- sign, trim trailing
/// whitespace, then fold the remaining bytes via xorshift-style bit mixing.
///
/// This replaces the earlier `HashMap<String, int>` approach, which
/// normalized each line into a freshly allocated String (copy + trim),
/// then hashed that string through the VM's generic string hasher. With
/// diffs containing thousands of lines, the normalized-String allocations
/// alone dominated move-detection cost. The integer hash:
///   - Reads text bytes directly via codeUnitAt (no allocation).
///   - Mixes each byte via a SplitMix64-style step so single-character
///     differences produce wildly different hashes (avalanche).
///   - Collapses "trim trailing whitespace" into a pre-pass that walks
///     backwards and then hashes only the kept range.
/// The move-detection map becomes `Map<int, int>` (content hash → unit
/// index), which hashes and compares integers directly.
int _contentHashForMove(String rawLineText) {
  if (rawLineText.isEmpty) return 0;
  // Skip leading sign if present (+ / -). Context lines start with space
  // in unified diff format; we preserve the space since it's part of the
  // aligned content and influences the hash deliberately.
  int start = 0;
  final c0 = rawLineText.codeUnitAt(0);
  if (c0 == 0x2B || c0 == 0x2D) start = 1;

  // Find end after stripping trailing whitespace (space, tab, \r).
  int end = rawLineText.length;
  while (end > start) {
    final c = rawLineText.codeUnitAt(end - 1);
    if (c == 0x20 || c == 0x09 || c == 0x0D) {
      end--;
    } else {
      break;
    }
  }

  // Require at least 4 non-trivial characters — punctuation-only lines
  // like `}` or `);` would otherwise generate huge false-positive move
  // chains. Returning 0 here opts this line out of move-detection.
  if (end - start < 4) return 0;

  // Rolling hash: multiply-and-xor step per byte. FNV-1a-inspired but
  // with SplitMix64 mixing constants, so a one-character substring
  // rotation produces a hash with ~50% bit-flip distance from the
  // original (avalanche). This is the property HashMap buckets need.
  int h = 0xcbf29ce484222325; // FNV offset basis, seed
  for (int i = start; i < end; i++) {
    h = (h ^ rawLineText.codeUnitAt(i)) * 0x100000001b3; // FNV prime
    h ^= h >>> 33; // splitmix-style re-mix
  }
  // Final avalanche pass so hashCode-style truncation to Map buckets
  // doesn't concentrate collisions in the low bits.
  return splitmix64(h);
}

/// Build the canonical EditUnit stream from a flat ParsedLine list.
///
/// Contract:
///   - Every ParsedLine appears inside exactly one EditUnit (either as the
///     sole content of a singleton unit or as part of a multi-line unit).
///   - No unit is synthesized without a backing ParsedLine — the patch
///     engine sees exactly the same bytes it always did.
///   - Order is preserved: units are emitted in the order their FIRST
///     backing line appeared.
///
/// When [detectMoves] is true (default), an additional pass pairs pure
/// single-line deletes and inserts whose content matches across the file
/// into [EditKind.move] units. Only non-adjacent pairs are considered
/// (adjacent -/+ is already handled by replace detection). Content shorter
/// than a minimum length is skipped to avoid false-positive matches on
/// punctuation-only lines like `}` or `);`.
List<EditUnit> buildEditUnits(
  List<ParsedLine> lines, {
  bool detectMoves = true,
}) {
  final units = <EditUnit>[];
  final n = lines.length;
  int i = 0;
  while (i < n) {
    final l = lines[i];
    switch (l.kind) {
      case LineKind.hunk:
        // Hunk/meta/context units never reach _detectFuzzyMoves (guarded
        // at the delete/insert kind filter), so simHash on them is dead
        // data. Kept default (0) to keep the constructor lean.
        units.add(EditUnit(
          id: _idForSingleLine(_tagHunk, l),
          kind: EditKind.hunk,
          oldLines: [l],
          hunkIndex: l.hunkIndex,
          filePath: l.filePath,
          charBits: l.charBits,
          bigramBits: l.bigramBits,
        ));
        i++;
        break;
      case LineKind.meta:
        units.add(EditUnit(
          id: _idForSingleLine(_tagMeta, l),
          kind: EditKind.meta,
          oldLines: [l],
          hunkIndex: l.hunkIndex,
          filePath: l.filePath,
          charBits: l.charBits,
          bigramBits: l.bigramBits,
        ));
        i++;
        break;
      case LineKind.context:
        units.add(EditUnit(
          id: _idForSingleLine(_tagContext, l),
          kind: EditKind.context,
          oldLines: [l],
          newLines: [l],
          hunkIndex: l.hunkIndex,
          filePath: l.filePath,
          charBits: l.charBits,
          bigramBits: l.bigramBits,
          // simHash not carried — context units never participate in
          // fuzzy move detection (only delete/insert do).
        ));
        i++;
        break;
      case LineKind.deleted:
        if (i + 1 < n &&
            lines[i + 1].kind == LineKind.added &&
            lines[i + 1].hunkIndex == l.hunkIndex) {
          final a = lines[i + 1];
          units.add(EditUnit(
            id: _idForPair(_tagReplace, l, a),
            kind: EditKind.replace,
            oldLines: [l],
            newLines: [a],
            hunkIndex: l.hunkIndex,
            filePath: l.filePath,
            // Pair union — polyphonic search must see both sides' chars.
            charBits: l.charBits | a.charBits,
            bigramBits: l.bigramBits | a.bigramBits,
            // SimHash of the delete side — fuzzy move matcher keys by the
            // "from" fingerprint so a replace-in-place and a relocated
            // rename land comparably.
            simHash: l.simHash,
          ));
          i += 2;
        } else {
          units.add(EditUnit(
            id: _idForSingleLine(_tagDelete, l),
            kind: EditKind.delete,
            oldLines: [l],
            hunkIndex: l.hunkIndex,
            filePath: l.filePath,
            charBits: l.charBits,
            bigramBits: l.bigramBits,
          ));
          i++;
        }
        break;
      case LineKind.added:
        units.add(EditUnit(
          id: _idForSingleLine(_tagInsert, l),
          kind: EditKind.insert,
          newLines: [l],
          hunkIndex: l.hunkIndex,
          filePath: l.filePath,
          charBits: l.charBits,
          bigramBits: l.bigramBits,
          simHash: l.simHash,
        ));
        i++;
        break;
    }
  }

  if (detectMoves) {
    _detectMoves(units);
  }

  return units;
}

/// Pair delete units with insert units whose content matches across the
/// diff, then **extend each match into the longest contiguous block** that
/// can be shown as one moved region. Both sides become [EditKind.move]
/// units pointing at each other via [EditUnit.moveTargetId].
///
/// This is Rabin-Karp block matching over the unit stream: the content
/// hash per line (computed once via [_contentHashForMove]) acts as the
/// rolling-hash key, and for each candidate 1-line match we greedily
/// extend forward as long as the next delete's content hash equals the
/// next insert's content hash AND both sit in the same file. Verification
/// happens in hash space, so a k-line extension is O(k) of integer
/// compares — no per-line string work during extension.
///
/// Why block-level detection matters: when a reviewer moves a 10-line
/// function elsewhere in a file, git emits it as 10 deletes + 10 inserts
/// in two separated hunks. Single-line matching would mark exactly ONE
/// line as moved (whichever hashed first) and render the other 9 as plain
/// insert/delete pairs. That's structurally wrong — the reviewer sees
/// "lots of churn" instead of "this function moved." Extending to the
/// full block makes the whole relocation read as one coherent event.
///
/// Conservative guards:
///   - Normalized content ≥ 4 chars (see [_contentHashForMove]) so
///     punctuation-only lines like `}` don't anchor bogus blocks.
///   - Blocks must not overlap each other — once a delete or insert unit
///     is claimed by a move block, it can't be re-claimed by another.
///   - Blocks must not be adjacent in the unit stream (a delete block
///     directly followed by an insert block is a multi-line replace, not
///     a move — git's own heuristic, preserved here).
///   - Must be within the same file.
///   - Longest-match wins: for a given starting delete, we try every
///     candidate insert position with matching first-line hash and pick
///     the one that extends furthest. This avoids the first-match-wins
///     pathology where a trivial 1-line coincidence sunk a genuine 10-line
///     block move.
///
/// Complexity: O(N) expected. The hash index is O(N) to build; each unit
/// contributes at most O(|candidate list|) work during extension, and
/// because each unit is visited at most once (via the `claimed` bitmap)
/// the total extension work is bounded by O(N). Worst case with heavy
/// content collisions degrades toward O(N · c) where c is the hash
/// collision rate — negligible for the 64-bit FNV+splitmix hash.
void _detectMoves(List<EditUnit> units) {
  final n = units.length;
  // Per-unit content hash (0 = skip: not a pure delete/insert, or content
  // too trivial for [_contentHashForMove]). Cached here so block-extension
  // compares are integer ops instead of rehashing each time.
  final unitHash = List<int>.filled(n, 0);
  // hash → list of unit indices that carry that hash. Lists-of-positions
  // are required (not a single position) because the same line content
  // can legitimately appear multiple times — we want every candidate so
  // longest-match can actually find the longest block.
  final delByHash = <int, List<int>>{};
  final insByHash = <int, List<int>>{};

  for (int i = 0; i < n; i++) {
    final u = units[i];
    if (u.kind == EditKind.delete && u.oldLines.isNotEmpty) {
      final h = _contentHashForMove(u.oldLines.first.text);
      if (h == 0) continue;
      unitHash[i] = h;
      (delByHash[h] ??= <int>[]).add(i);
    } else if (u.kind == EditKind.insert && u.newLines.isNotEmpty) {
      final h = _contentHashForMove(u.newLines.first.text);
      if (h == 0) continue;
      unitHash[i] = h;
      (insByHash[h] ??= <int>[]).add(i);
    }
  }

  // Tracks units already claimed by a move block so we never double-mark.
  final claimed = List<bool>.filled(n, false);

  for (int delStart = 0; delStart < n; delStart++) {
    if (claimed[delStart]) continue;
    if (units[delStart].kind != EditKind.delete) continue;
    final startHash = unitHash[delStart];
    if (startHash == 0) continue;

    final candidates = insByHash[startHash];
    if (candidates == null) continue;

    int bestInsStart = -1;
    int bestLen = 0;

    for (final insStart in candidates) {
      if (claimed[insStart]) continue;
      final delU = units[delStart];
      final insU = units[insStart];
      if (delU.filePath != insU.filePath) continue;

      // Extend forward: walk both streams in lockstep, confirming each
      // pair of units is (delete, insert) with matching content hash
      // inside the same file. Runs purely on cached integers — no
      // string rehashing, no unit materialisation beyond the slot access.
      int len = 1;
      while (delStart + len < n && insStart + len < n) {
        final di = delStart + len;
        final ii = insStart + len;
        if (claimed[di] || claimed[ii]) break;
        final dU = units[di];
        final iU = units[ii];
        if (dU.kind != EditKind.delete || iU.kind != EditKind.insert) break;
        final dh = unitHash[di];
        if (dh == 0 || dh != unitHash[ii]) break;
        if (dU.filePath != iU.filePath) break;
        len++;
      }

      // Reject adjacent / overlapping blocks — those are replace blocks,
      // not moves. (block A at positions [a..a+L], block B at [b..b+L]
      // are non-overlapping + non-adjacent iff |a - b| > L.)
      if ((delStart - insStart).abs() <= len) continue;

      if (len > bestLen) {
        bestLen = len;
        bestInsStart = insStart;
      }
    }

    if (bestLen < 1 || bestInsStart < 0) continue;

    // Commit the block — mark every participating unit as EditKind.move
    // and set moveTargetId to its partner across the block. Partner is
    // the same offset within the other side, so move-from[k] links to
    // move-to[k]. Block semantics are preserved downstream because the
    // renderer simply sees a run of `move` units, each with the correct
    // ⤴ / ⤵ glyph.
    for (int k = 0; k < bestLen; k++) {
      final di = delStart + k;
      final ii = bestInsStart + k;
      claimed[di] = true;
      claimed[ii] = true;
      final delU = units[di];
      final insU = units[ii];
      units[di] = EditUnit(
        id: delU.id,
        kind: EditKind.move,
        oldLines: delU.oldLines,
        hunkIndex: delU.hunkIndex,
        filePath: delU.filePath,
        moveTargetId: insU.id,
        charBits: delU.charBits,
        bigramBits: delU.bigramBits,
        simHash: delU.simHash,
      );
      units[ii] = EditUnit(
        id: insU.id,
        kind: EditKind.move,
        oldLines: const [],
        newLines: insU.newLines,
        hunkIndex: insU.hunkIndex,
        filePath: insU.filePath,
        moveTargetId: delU.id,
        charBits: insU.charBits,
        bigramBits: insU.bigramBits,
        simHash: insU.simHash,
      );
    }
  }

  // ── Fuzzy pass ────────────────────────────────────────────────────────
  // For every unclaimed delete+insert that the exact Rabin-Karp pass left
  // behind, check if their SimHashes are within a tight Hamming distance.
  // Catches rename-in-place moves: `function foo(x)` → `function bar(x)`
  // differs by a handful of bits once trigrams overlap.
  //
  // Complexity: O(|remaining deletes| × |remaining inserts|) with a
  // popcount per compare. In practice after exact matching consumes the
  // bulk, remaining counts are modest (<100 each for typical diffs), so
  // the quadratic pass costs well under a millisecond even on large
  // refactors. Runs once per _recomputeUnits (NOT per _refreshDisplayLines).
  _detectFuzzyMoves(units, claimed);
}

/// Maximum Hamming distance (out of 64 bits) between two SimHashes to
/// still be considered a fuzzy move. Empirically: 0 = identical content,
/// 4-8 = same line with a renamed identifier, 12+ = unrelated. The
/// threshold is deliberately tight to avoid false positives — better to
/// miss a fuzzy match than to lie about an unrelated line being moved.
const int _kFuzzyMoveHammingLimit = 8;

/// Minimum bits the SimHash must have set before fuzzy matching considers
/// the line informative. A SimHash of 0 means "line too short for any
/// trigram"; values near 32 are expected (random sign per bit) but
/// pathologically empty hashes should still be skipped.
bool _simHashIsInformative(int h) => h != 0;

void _detectFuzzyMoves(List<EditUnit> units, List<bool> claimed) {
  final n = units.length;

  // Collect surviving deletes and inserts alongside their indices.
  final delIdx = <int>[];
  final insIdx = <int>[];
  for (int i = 0; i < n; i++) {
    if (claimed[i]) continue;
    final u = units[i];
    if (u.kind == EditKind.delete && _simHashIsInformative(u.simHash)) {
      delIdx.add(i);
    } else if (u.kind == EditKind.insert &&
        _simHashIsInformative(u.simHash)) {
      insIdx.add(i);
    }
  }
  if (delIdx.isEmpty || insIdx.isEmpty) return;

  // Greedy best-match pairing. For each delete, scan all unclaimed
  // candidate inserts and pick the lowest-Hamming same-file candidate
  // under threshold. Claim both sides on success so later iterations
  // don't re-pair.
  final insClaimed = List<bool>.filled(insIdx.length, false);
  for (final di in delIdx) {
    if (claimed[di]) continue;
    final delU = units[di];
    int bestK = -1;
    int bestDist = _kFuzzyMoveHammingLimit + 1;
    for (int k = 0; k < insIdx.length; k++) {
      if (insClaimed[k]) continue;
      final ii = insIdx[k];
      if (claimed[ii]) continue;
      final insU = units[ii];
      if (delU.filePath != insU.filePath) continue;
      // Block adjacent pairs — those are plain replace, not moves.
      if ((di - ii).abs() <= 1) continue;
      final d = ParsedLine.hamming64(delU.simHash, insU.simHash);
      if (d < bestDist) {
        bestDist = d;
        bestK = k;
      }
    }
    if (bestK < 0) continue;
    final ii = insIdx[bestK];
    final delU2 = units[di];
    final insU2 = units[ii];
    claimed[di] = true;
    claimed[ii] = true;
    insClaimed[bestK] = true;
    units[di] = EditUnit(
      id: delU2.id,
      kind: EditKind.move,
      oldLines: delU2.oldLines,
      hunkIndex: delU2.hunkIndex,
      filePath: delU2.filePath,
      moveTargetId: insU2.id,
      charBits: delU2.charBits,
      bigramBits: delU2.bigramBits,
      simHash: delU2.simHash,
    );
    units[ii] = EditUnit(
      id: insU2.id,
      kind: EditKind.move,
      oldLines: const [],
      newLines: insU2.newLines,
      hunkIndex: insU2.hunkIndex,
      filePath: insU2.filePath,
      moveTargetId: delU2.id,
      charBits: insU2.charBits,
      bigramBits: insU2.bigramBits,
      simHash: insU2.simHash,
    );
  }
}
