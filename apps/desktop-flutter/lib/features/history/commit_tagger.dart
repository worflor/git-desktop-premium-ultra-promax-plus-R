import 'dart:math' as math;
import 'dart:typed_data';

import '../../backend/dtos.dart';
import '../../backend/engram_fit.dart';
import '../../backend/file_coupling.dart';
import '../../backend/logos_git.dart';

/// Tag kind — drives visual tone only, not the label. Labels themselves
/// always come from the repo's own data (or a small set of universal
/// descriptors for distribution extremes).
/// Three families:
///   * **Convention** — type / scope / chain / cluster. Labels are
///     learned from the repo's authors or its directory tree.
///   * **Direction** — cleanup / growth / echo / hub. Universal
///     phenomena, descriptive English.
///   * **Distribution** — hot / cold / huge / tiny / focused / sprawl
///     when the commit sits in the top/bottom 10% of the repo's own
///     distribution. Universal English for "extreme bucket".
///   * **Truth-tellers** — drift (claimed scope ≠ actual cluster).
///   * **Git facts** — merge.
enum CommitTagKind {
  type,
  scope,
  chain,
  cluster,
  echo,
  hub,
  cleanup,
  growth,
  drift,
  axisHuge,
  axisTiny,
  axisFocused,
  axisSprawl,

  /// Eldritch tag — a label borrowed from the commit's *semantic
  /// neighborhood* via diffusion. The commit's subject doesn't
  /// contain this word; its files do (through their accumulated
  /// affinity from past commits, plus 1-step propagation through the
  /// file-coupling graph). Surfaced when the borrowed signal is
  /// significantly stronger than baseline.
  borrowed,

  /// Branch trajectory — converging means file overlap across
  /// consecutive commits in this chain is *rising* toward the tip
  /// (the author is narrowing their working set, a good sign for a
  /// PR-ready branch). Derived via the Engram AR(2) oscillator fit on
  /// the chain's file-set Jaccard series.
  converging,

  /// Opposite: overlap is eroding toward the tip. The chain started
  /// focused and the commits are now sprawling into unrelated files.
  /// Truth-teller tag — it doesn't judge, but it surfaces a shape
  /// the author might want to see before merging.
  diverging,

  /// Self-comparison truth-teller: this commit sits in a chain whose
  /// orbital spectral radius deviates substantially from *this author's
  /// own* historical median across the analysed window. Not peer
  /// comparison — the author's orbit signature is their own baseline.
  /// Catches both "unusual focus" and "unusual sprawl" relative to how
  /// they normally work. Silent when we don't have enough of their
  /// history to baseline.
  unusualCadence,
  merge,

  /// Commit with one or more renames (git change-type 'R'). Label is
  /// harvested from the bucket's subjects like any other kind.
  rename,
}

/// A single tag rendered on a commit row. Label is the visible text;
/// kind gates tone; rarity drives ranking (rarer = more distinctive).
/// [confidence] is the pill's own opacity multiplier in [0,1] —
/// universal for all kinds (defaults to 1.0 = full strength). The
/// borrowed-tag path uses it to render weak whispers faintly and
/// strong borrows fully, so the visual itself communicates how much
/// the network actually agrees on this label. No hard thresholds.
class CommitTag {
  final String label;
  final CommitTagKind kind;
  final double rarity;
  final double confidence;
  const CommitTag({
    required this.label,
    required this.kind,
    this.rarity = 0.5,
    this.confidence = 1.0,
  });
}

/// Per-repo derivation profile. Built off-isolate from a history
/// window. Every field is derived from the repo's own data.
class RepositoryTagProfile {
  /// Prefix tokens the repo's authors use frequently enough to count as
  /// a shared convention. Vocabulary IS this set.
  final Set<String> prefixVocab;

  /// Distribution percentiles per numeric axis — the only "thresholds"
  /// in the system, and they're literally the repo's own 10th/90th.
  final double sizeP10;
  final double sizeP90;
  final double coherenceP10;
  final double coherenceP90;

  /// Cleanup/growth axis: deletions / (additions + 1) ratio. P90 = top
  /// 10% deletion-heavy → cleanup. P10 = bottom 10% → growth.
  final double delAddRatioP10;
  final double delAddRatioP90;

  /// Hub axis: per-commit centrality (sum of file-centrality scores
  /// across the commit's file set). Above P90 → `hub`.
  final double hubCentralityP90;

  /// Per-commit chain assignment. commitHash → label (chain's name,
  /// derived from longest common path-prefix of the chain's combined
  /// files). Commits not in any multi-commit chain are absent.
  final Map<String, String> chainLabel;

  /// Echo lookup: commit hashes that overlap ≥ [_kEchoOverlapThreshold]
  /// with a previous nearby commit's file set. Surfaces fixups,
  /// follow-ups, "fix the test I broke."
  final Set<String> echoCommits;

  /// Per-commit hub flag (true when the commit's file-centrality sum
  /// is ≥ [hubCentralityP90]). Pre-baked so per-row tagging stays
  /// allocation-free.
  final Set<String> hubCommits;

  /// Commits belonging to a chain whose file-set Jaccard series is in
  /// a rising orbit — file overlap increases toward the tip, i.e. the
  /// author is narrowing focus. Derived via the Whisper Engram AR(2)
  /// fit on the chain's consecutive-commit similarities.
  final Set<String> convergingCommits;

  /// Commits belonging to a chain whose file overlap is eroding toward
  /// the tip — scope sprawling across unrelated files. The twin of
  /// [convergingCommits], computed from the same Engram orbit fit.
  final Set<String> divergingCommits;

  /// Commits sitting in a chain whose orbital spectral radius is an
  /// outlier *for this author*. Measured against the author's own
  /// median |λ| across the analysed window, with the dispersion
  /// (median absolute deviation) as the scale. Surfaces both unusually-
  /// focused and unusually-sprawling chains — the direction is
  /// recoverable from the converging/diverging tag when one is present.
  final Set<String> unusualCadenceCommits;

  /// Label frequency across all commits. Rarity = 1 - freq/total.
  final Map<String, int> labelFrequency;

  final int commitCount;

  /// Per-bucket harvested label. The KIND defines the phenomenon (high
  /// del-ratio, etc.); the LABEL is the most distinctive word from the
  /// commit subjects in that bucket — discovered via log-odds against
  /// the corpus. If a bucket has no distinctive word (insufficient
  /// data, no signal), the entry is absent and no tag of that kind
  /// fires. This is what makes the system zero-hardcoded for
  /// universal-descriptor tags: the team's own vocabulary surfaces as
  /// the labels for `cleanup`, `growth`, `huge`, `tiny`, `focused`,
  /// `sprawl`, `echo`, `hub`, `drift`, and `merge`.
  final Map<CommitTagKind, String> bucketLabels;

  /// Borrowed-label table: commitHash → (label, score). The label
  /// comes from the commit's *semantic neighborhood* — its files'
  /// accumulated affinity to all known labels, propagated 1-step
  /// through the file-coupling graph, gated by sigma-distinctiveness.
  /// The label is NOT in the commit's own derived tags; it's borrowed
  /// from neighbors. Surfaced as `CommitTagKind.borrowed` to mark
  /// "this is what the network thinks this commit also is."
  final Map<String, ({String label, double score})> borrowedLabels;

  const RepositoryTagProfile({
    required this.prefixVocab,
    required this.sizeP10,
    required this.sizeP90,
    required this.coherenceP10,
    required this.coherenceP90,
    required this.delAddRatioP10,
    required this.delAddRatioP90,
    required this.hubCentralityP90,
    required this.chainLabel,
    required this.echoCommits,
    required this.hubCommits,
    this.convergingCommits = const {},
    this.divergingCommits = const {},
    this.unusualCadenceCommits = const {},
    required this.labelFrequency,
    required this.commitCount,
    required this.bucketLabels,
    required this.borrowedLabels,
  });

  static const empty = RepositoryTagProfile(
    prefixVocab: {},
    sizeP10: 0,
    sizeP90: 0,
    coherenceP10: 0,
    coherenceP90: 1,
    delAddRatioP10: 0,
    delAddRatioP90: 0,
    hubCentralityP90: 0,
    chainLabel: {},
    echoCommits: {},
    hubCommits: {},
    labelFrequency: {},
    commitCount: 0,
    bucketLabels: {},
    borrowedLabels: {},
  );
}

// Structural constants — pure topology, not taste.

/// Minimum chain length: two consecutive commits is the smallest
/// non-singleton. A structural definition, not a tunable.
const int _kChainMinLength = 2;

/// Z-score for outlier detection. ≈ 2 corresponds to the standard
/// 95% confidence interval bound (the precise value is 1.96; rounded
/// here for symmetry). This is a statistical convention, not a tuning
/// knob — same number used in classical outlier-rejection literature
/// and the engram codec's segmentation pass. A value below this is
/// statistically indistinguishable from the bulk; above this it's an
/// outlier worth tagging.
const double _kSigmaCutoff = 1.96;

/// Minimum chains from one author before we'll baseline their cadence.
/// Below this the median / MAD are too noisy to call anything unusual.
/// Three chains ≈ ~15–25 commits of activity depending on chain length
/// — a sprint's worth, the smallest window where "usual for them" is
/// a meaningful reference.
const int _kAuthorCadenceMinChains = 3;

/// Deviation threshold in MAD-units. 2·MAD corresponds to roughly
/// 2·σ for a near-Gaussian distribution (MAD ≈ 0.6745·σ on Gaussians
/// — Hampel identifier convention) — the classic outlier gate,
/// robust to heavy tails that inflate naive σ.
const double _kAuthorCadenceSigmas = 2.0;

/// Median of a pre-sorted list. Caller must sort. O(1).
double _medianSorted(List<double> sorted) {
  if (sorted.isEmpty) return 0;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Median absolute deviation — the robust dispersion measure. Unlike
/// standard deviation, one bad chain can't inflate MAD, which is
/// what we want when an author's occasional off-day shouldn't raise
/// the "unusual" bar for the rest of their normal work.
double _medianAbsDeviation(List<double> values, double median) {
  if (values.isEmpty) return 0;
  final deviations = values.map((v) => (v - median).abs()).toList()..sort();
  return _medianSorted(deviations);
}

// Subject parser — extracts type+scope from any of the common shapes.

final RegExp _convPattern = RegExp(
  r'^([A-Za-z][\w\-\.]*)(?:\(([^)]+)\))?!?\s*:\s*',
);
final RegExp _bracketPattern = RegExp(r'^\[([^\]\n]{1,32})\]\s*');

({String? type, String? scope}) parseSubjectPrefix(String subject) {
  final conv = _convPattern.firstMatch(subject);
  if (conv != null) {
    return (type: conv.group(1), scope: conv.group(2));
  }
  final brk = _bracketPattern.firstMatch(subject);
  if (brk != null) {
    final raw = brk.group(1)!.trim();
    final dash = raw.indexOf('-');
    if (dash > 0 && dash < raw.length - 1) {
      return (type: raw.substring(0, dash), scope: raw.substring(dash + 1));
    }
    return (type: raw, scope: null);
  }
  return (type: null, scope: null);
}

/// Longest meaningful common path-prefix of a file set, rendered as a
/// single trailing segment. Returns null when the prefix is too
/// shallow to be informative (single segment shared = `lib/` only).
String? commonPrefixLabel(Iterable<String> paths) {
  final list = paths
      .map((p) => p.replaceAll('\\', '/'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (list.isEmpty) return null;
  if (list.length == 1) {
    final parts = list.first.split('/');
    if (parts.length >= 3) return parts[parts.length - 2];
    return null;
  }
  final parts = list.map((p) => p.split('/').toList()).toList();
  final shortest = parts.map((p) => p.length).reduce((a, b) => a < b ? a : b);
  var depth = 0;
  for (var i = 0; i < shortest; i++) {
    final seg = parts[0][i];
    if (parts.every((p) => p[i] == seg)) {
      depth = i + 1;
    } else {
      break;
    }
  }
  if (depth < 2) return null;
  final segment = parts[0][depth - 1];
  return segment.isEmpty ? null : segment;
}

// Profile builder — does the heavy lifting once per history load.

// Subject corpus — tokenizes commit subjects into a global word
// frequency table and harvests the most-distinctive word for any
// commit subset via log-odds against the corpus. The harvested word
// becomes the bucket label; no seed vocabulary.

/// Matches a "Key: Value" trailer line (Unicode letters + digits).
final RegExp _kTrailerShapeRe = RegExp(
  r'^[\p{L}][\p{L}\p{N}-]*:\s+\S.*$',
  multiLine: true,
  unicode: true,
);

final RegExp _kTagWordRe = RegExp(
  r'[\p{L}][\p{L}\p{N}]+',
  unicode: true,
);

/// Drops git-style trailers: a contiguous tail block of `Key: Value`
/// lines at the end of the body. Only the last paragraph is checked,
/// so mid-body `Key:` patterns (tables, notes sections) are preserved.
String _stripGitTrailersEmergent(String body) {
  if (body.isEmpty) return body;
  final paragraphs = body.split(RegExp(r'\n\s*\n'));
  if (paragraphs.length < 2) {
    // Single paragraph — only strip if the entire body is trailers.
    final lines = body
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return body;
    final allTrailers =
        lines.every((l) => _kTrailerShapeRe.hasMatch(l));
    return allTrailers ? '' : body;
  }
  final last = paragraphs.last;
  final lines = last
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return body;
  final allTrailers =
      lines.every((l) => _kTrailerShapeRe.hasMatch(l));
  if (!allTrailers) return body;
  return paragraphs.sublist(0, paragraphs.length - 1).join('\n\n');
}

/// Shared tokeniser used by both the isolate-side [_SubjectCorpus]
/// and the main-thread projection helper. Keeping them in lockstep
/// matters — the file-token matrices are compared directly downstream.
List<String> tagTokenize(String text) {
  if (text.isEmpty) return const [];
  final scrubbed = _stripGitTrailersEmergent(text);
  final out = <String>[];
  for (final m in _kTagWordRe.allMatches(scrubbed.toLowerCase())) {
    final w = m.group(0)!;
    if (w.length >= 3) out.add(w);
  }
  return out;
}

class _SubjectCorpus {
  /// Tokens per commit, parallel to the input list. Subject always,
  /// body when a [CommitDetailData] is cached for the commit.
  final List<List<String>> subjectTokens;
  /// Token → mass across the corpus. Each commit contributes 1.0 total
  /// regardless of length, so entries are fractional (`Σ 1/|tokens|`).
  final Map<String, double> globalFreq;
  /// Sum over [globalFreq]. Equals the count of non-empty commits.
  final double totalTokens;
  /// File → (token → mass). Each commit deposits 1.0 unit across the
  /// files it touches. P(token | file) reads off this matrix directly.
  final Map<String, Map<String, double>> fileTokenCounts;

  const _SubjectCorpus({
    required this.subjectTokens,
    required this.globalFreq,
    required this.totalTokens,
    required this.fileTokenCounts,
  });

  static List<String> _tokenize(String text) => tagTokenize(text);

  /// Builds the corpus from [commits]. Prefix-matched type/scope words
  /// are stripped from each subject so they don't leak into bucket
  /// labels. Each commit contributes one unit of mass, split across
  /// its tokens, so a 100-token body doesn't outvote 100 terse commits.
  /// Commits without a cached [detailsByHash] entry contribute
  /// subject-only tokens and are skipped from the file-token matrix.
  static _SubjectCorpus build(
    List<CommitHistoryEntry> commits,
    Map<String, CommitDetailData> detailsByHash,
  ) {
    final tokens = <List<String>>[];
    final freq = <String, double>{};
    final fileTokens = <String, Map<String, double>>{};
    var total = 0.0;
    for (final c in commits) {
      final detail = detailsByHash[c.commitHash];
      // Merge-commit subjects are usually auto-generated templates;
      // skip them to keep bucket vocabularies clean. Body tokens from
      // merge PRs still flow through when a detail is cached.
      final isMerge = c.parentHashes.length > 1;
      var subject = isMerge ? '' : c.subject;
      if (!isMerge) {
        final convM = _convPattern.firstMatch(subject);
        final brkM = _bracketPattern.firstMatch(subject);
        final m = convM ?? brkM;
        if (m != null) subject = subject.substring(m.end);
      }
      final body = detail?.body ?? '';
      final text = body.isEmpty ? subject : '$subject $body';
      final t = _tokenize(text);
      tokens.add(t);
      if (t.isEmpty) continue;
      final weight = 1.0 / t.length;
      for (final w in t) {
        freq.update(w, (v) => v + weight, ifAbsent: () => weight);
        total += weight;
      }

      if (detail != null) {
        for (final f in detail.files) {
          final row =
              fileTokens.putIfAbsent(f.path, () => <String, double>{});
          for (final w in t) {
            row.update(w, (v) => v + weight, ifAbsent: () => weight);
          }
        }
      }
    }
    return _SubjectCorpus(
      subjectTokens: tokens,
      globalFreq: freq,
      totalTokens: total,
      fileTokenCounts: fileTokens,
    );
  }

  /// Returns the most distinctive token for a set of bucket commits,
  /// or null when nothing stands above the long tail.
  /// Two axes:
  ///   NPMI vs. the corpus marginal (always on).
  ///   Log-surprise vs. [expectedTokens] when provided — a distribution
  ///     from [LogosGit.projectTokenDistribution] over the bucket's
  ///     file-neighborhood. "Distinctive" then means the file graph
  ///     didn't predict this token here but it showed up anyway.
  /// The two axes compose via the Born-amplitude pattern [BornMixer]
  /// uses elsewhere. A kneedle gate filters the winner when the
  /// top-to-tail split isn't sharp.
  String? harvestLabel(
    Iterable<int> commitIndices, {
    Map<String, double>? expectedTokens,
  }) {
    final indices = commitIndices.toSet();
    if (indices.isEmpty) return null;
    // Mass is the NPMI input; commitFreq is the "seen in how many
    // distinct commits" count used for the singleton gate and the
    // evidence cap in the Born mix.
    final bucketMass = <String, double>{};
    final bucketCommitFreq = <String, int>{};
    var bucketTotal = 0.0;
    for (final idx in indices) {
      if (idx < 0 || idx >= subjectTokens.length) continue;
      final tokens = subjectTokens[idx];
      if (tokens.isEmpty) continue;
      final weight = 1.0 / tokens.length;
      final seenInCommit = <String>{};
      for (final w in tokens) {
        bucketMass.update(w, (v) => v + weight, ifAbsent: () => weight);
        bucketTotal += weight;
        if (seenInCommit.add(w)) {
          bucketCommitFreq.update(w, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }
    if (bucketMass.isEmpty || bucketTotal <= 0) return null;

    final vocabSize = globalFreq.length.toDouble();
    final priorMass = 0.5 * vocabSize;

    // Total expected mass for normalising the 8d distribution into a
    // probability. When expectedTokens is null or all-zero the 8d axis
    // contributes nothing and we fall through to pure NPMI.
    double expectedTotal = 0;
    if (expectedTokens != null) {
      for (final v in expectedTokens.values) {
        if (v > 0) expectedTotal += v;
      }
    }
    final has8d = expectedTokens != null && expectedTotal > 0;

    // Evidence-weight denominator — maximum plausible commit-frequency
    // any token in this bucket can reach. Used below to normalise the
    // 8d axis's per-token evidence weight onto [0, 1], which scale-
    // matches it against w0's [0, 0.5] range in the Born mix. Computed
    // once per bucket.
    final logMaxCommitFreq = math.log(1 + indices.length);

    final scored = <_LabelCandidate>[];
    for (final entry in bucketMass.entries) {
      // Drop tokens that appear in only one bucket commit — typo-like.
      if ((bucketCommitFreq[entry.key] ?? 0) < 2) continue;
      final pBucket = (entry.value + 0.5) / (bucketTotal + priorMass);
      final corpusCount = globalFreq[entry.key] ?? 0.0;
      final pCorpus =
          (corpusCount + 0.5) / (totalTokens + priorMass);
      final pBucketShare = bucketTotal / (totalTokens + priorMass);
      final pJoint = pBucket * pBucketShare;
      if (pJoint <= 0 || pCorpus <= 0) continue;
      final pmi = math.log(pJoint / (pCorpus * pBucketShare));
      final negLogJoint = -math.log(pJoint);
      // NPMI ∈ [-1, 1].
      final npmi = negLogJoint > 0 ? pmi / negLogJoint : 0.0;

      var score = npmi;

      if (has8d) {
        // Symmetric Jeffreys smoothing on both sides keeps pObserved
        // and pExpected on the same probability scale.
        final pObserved = pBucket;
        final expRaw = expectedTokens[entry.key] ?? 0.0;
        final pExpected =
            (expRaw + 0.5) / (expectedTotal + priorMass);
        final surpriseRaw = math.log(pObserved / pExpected);
        // Scale 0.5 keeps typical log-ratios in tanh's linear range.
        final surprise8d = _tanh(0.5 * surpriseRaw);

        // Born-rule amplitude mix: each axis's score in [-1, 1] maps
        // to a probability via (s + 1) / 2; √-amplitudes combine like
        // a two-outcome event and the mixed p collapses back to the
        // original range. Same shape as [BornMixer.mix].
        final p0 = (npmi + 1.0) * 0.5;
        final p8 = (surprise8d + 1.0) * 0.5;
        final w0 = (p0 - 0.5).abs();
        // Evidence weight scales monotonically with commit-frequency,
        // normalised by the bucket's maximum possible commit-frequency
        // so w8 ∈ [0, 0.5] — same range as w0 so the Born mix isn't
        // scale-biased. The previous form `min(log(1+commitFreq), ln2)`
        // collapsed to the constant ln2 for every candidate because the
        // singleton gate already guarantees commitFreq ≥ 2 and
        // log(3) > ln2; the cap never varied with evidence.
        final commitFreq = bucketCommitFreq[entry.key] ?? 0;
        final evidenceFrac = logMaxCommitFreq > 0
            ? math.log(1 + commitFreq) / logMaxCommitFreq
            : 0.0;
        final w8 = (p8 - 0.5).abs() * evidenceFrac;
        final aSum = w0 * math.sqrt(p0) + w8 * math.sqrt(p8);
        final bSum =
            w0 * math.sqrt(1 - p0) + w8 * math.sqrt(1 - p8);
        final a2 = aSum * aSum;
        final b2 = bSum * bSum;
        final denom = a2 + b2;
        if (denom > 0) {
          score = (a2 / denom) * 2.0 - 1.0;
        }
      }

      scored.add(_LabelCandidate(entry.key, score));
    }
    if (scored.isEmpty) return null;

    // Kneedle gate — same algorithm as the prefix and borrowed-tag
    // selectors. Requires the knee of the descending-score curve to
    // sit at index 0, so the leader stands above the tail rather than
    // sitting at the top of a flat distribution.
    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.first;
    if (top.score <= 0) return null;
    if (scored.length == 1) return top.label;
    final n = scored.length;
    final maxV = scored.first.score;
    final minV = scored.last.score;
    final spread = maxV - minV;
    if (spread <= 0) return null;
    var kneeIdx = 0;
    var bestDist = -1.0;
    for (var i = 0; i < n; i++) {
      final x = i / (n - 1);
      final y = (scored[i].score - minV) / spread;
      final d = (y + x - 1).abs();
      if (d > bestDist) {
        bestDist = d;
        kneeIdx = i;
      }
    }
    if (kneeIdx > 0) return null;
    return top.label;
  }
}

class _LabelCandidate {
  final String label;
  final double score;
  const _LabelCandidate(this.label, this.score);
}

/// dart:math has no tanh; this is the standard stable form.
double _tanh(double x) {
  if (x > 20) return 1.0;
  if (x < -20) return -1.0;
  final e2x = math.exp(2 * x);
  return (e2x - 1) / (e2x + 1);
}

// Self-discovery utilities — kneedle for prefix promotion, sigma-cutoff
// for distribution extremes, autocorrelation for natural timescales.
// All inspired by the engram codec's "let the data tell you the
// threshold" pattern.

/// Knee-of-the-curve detection (Kneedle). Sorts values descending,
/// normalizes to [0,1] on both axes, finds the index where the curve
/// bends sharpest from the diagonal connecting (0,1) and (1,0). Used
/// to promote prefix tokens to "shared convention" status: everything
/// at or above the knee is in the vocab, everything past it is the
/// long tail. No magic 5%-floor.
Set<String> _harvestPrefixVocab(Map<String, int> prefixCounts) {
  if (prefixCounts.isEmpty) return const {};
  final entries = prefixCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (entries.length == 1) {
    // Single distinct prefix: only promote if it appears more than
    // once (one-off habits don't define a convention).
    return entries.first.value >= 2 ? {entries.first.key} : const {};
  }
  final n = entries.length;
  final maxV = entries.first.value.toDouble();
  final minV = entries.last.value.toDouble();
  final spread = maxV - minV;
  if (spread < 1) {
    // Flat distribution — every prefix appears equally often. With no
    // distinguishing knee, promote any that appears ≥ 2 times.
    return {for (final e in entries) if (e.value >= 2) e.key};
  }
  // Distance from each point on the descending curve to the diagonal
  // (0,1) → (1,0): |y + x - 1| (proportional). The knee is the point
  // of maximum distance.
  var bestIdx = 0;
  var bestDist = -1.0;
  for (var i = 0; i < n; i++) {
    final x = i / (n - 1);
    final y = (entries[i].value - minV) / spread;
    final d = (y + x - 1).abs();
    if (d > bestDist) {
      bestDist = d;
      bestIdx = i;
    }
  }
  // Vocabulary = head of the distribution up to and including the knee.
  // Filter out entries that happen to have count < 2 (noise floor).
  return {for (var i = 0; i <= bestIdx; i++) if (entries[i].value >= 2) entries[i].key};
}

/// Sigma-cutoff outlier gate (engram-style). Returns (lowGate, highGate)
/// where any value below lowGate or above highGate is "extreme" against
/// this distribution. Empty input → both 0.
({double low, double high}) _sigmaGate(List<double> values) {
  if (values.length < 2) return (low: 0, high: 0);
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values
          .map((v) => (v - mean) * (v - mean))
          .reduce((a, b) => a + b) /
      values.length;
  final sigma = math.sqrt(variance);
  return (
    low: mean - _kSigmaCutoff * sigma,
    high: mean + _kSigmaCutoff * sigma,
  );
}

/// Autocorrelation length of a 1D signal (engram pattern). Returns the
/// first lag at which the centered autocorrelation function drops to
/// zero or below — the "memory" of the signal. Falls back to 4 when
/// the signal is too short or too flat to measure.
int _autocorrelationLength(List<double> signal, {int maxLag = 32}) {
  if (signal.length < 4) return 4;
  final mean = signal.reduce((a, b) => a + b) / signal.length;
  final centered = signal.map((v) => v - mean).toList();
  final variance =
      centered.map((v) => v * v).reduce((a, b) => a + b);
  if (variance < 1e-30) return 4;
  final cap = math.min(maxLag, signal.length ~/ 2);
  for (var lag = 1; lag <= cap; lag++) {
    var acf = 0.0;
    for (var i = 0; i < signal.length - lag; i++) {
      acf += centered[i] * centered[i + lag];
    }
    acf /= variance;
    if (acf <= 0.0) return math.max(2, lag);
  }
  return cap;
}

DateTime? _parseTs(String iso) {
  if (iso.isEmpty) return null;
  return DateTime.tryParse(iso);
}

RepositoryTagProfile buildTagProfile({
  required List<CommitHistoryEntry> commits,
  required Map<String, CommitDetailData> detailsByHash,
  required FileCouplingMatrix? coupling,
  /// Optional per-commit coherence override (commitHash → coherence in
  /// [0, 1]). When provided, used in preference to the raw Jaccard
  /// `coupling.coherenceFor()` — this is the hook the LogosGit engine
  /// uses to inject Born-mixed multi-axis coherence (F0+CC+SP+V), giving
  /// strictly more informative percentile splits.
  Map<String, double>? engineCoherences,
  /// Per-commit expected-token distribution from
  /// [LogosGit.projectTokenDistribution], pre-computed on the main
  /// thread (engine isn't isolate-transferable). Summed per bucket
  /// inside this function. Null when the engine is cold — the tagger
  /// falls back to the NPMI-only path.
  Map<String, Map<String, double>>? expectedTokensByHash,
}) {
  if (commits.isEmpty) return RepositoryTagProfile.empty;

  // The vocabulary is whatever appears at-or-above the natural knee
  // of the prefix-frequency curve. No fixed % floor; the data tells us
  // where shared-convention ends and long-tail begins.
  final prefixCounts = <String, int>{};
  for (final c in commits) {
    final parsed = parseSubjectPrefix(c.subject);
    if (parsed.type != null) {
      prefixCounts.update(parsed.type!, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final prefixVocab = _harvestPrefixVocab(prefixCounts);

  // Tokenizes every commit subject (post-prefix-strip) into a global
  // word frequency table. Per-bucket label discovery uses log-odds
  // against this corpus — the team's actual vocabulary becomes the
  // tag labels.
  final corpus = _SubjectCorpus.build(commits, detailsByHash);

  // Centrality = sum of jaccard scores to neighbors. Files in dense
  // subgraphs score high; isolated files score 0. Backed by the
  // canonical `FileCouplingMatrix.jaccardCentralityMap` — one CSR
  // pass, each edge visited once and accumulated into both endpoints.
  // Pure topological derivation, zero taste.
  final fileCentrality =
      coupling?.jaccardCentralityMap() ?? <String, double>{};

  // Walk in commits order; gather distributions; remember timestamps
  // and file sets per commit for the chain pass.
  final sizes = <double>[];
  final coherences = <double>[];
  final ratios = <double>[];
  final hubScores = <double>[];
  final commitFiles = <String, Set<String>>{};
  final commitHubScore = <String, double>{};
  for (final c in commits) {
    final d = detailsByHash[c.commitHash];
    if (d == null) continue;
    final files = {for (final f in d.files) f.path};
    commitFiles[c.commitHash] = files;
    sizes.add((d.additions + d.deletions).toDouble());
    ratios.add(d.deletions / (d.additions + 1));
    if (files.length >= 2) {
      // Prefer engine-supplied coherence (multi-axis Born mix) when
      // available; fall back to single-axis Jaccard from the matrix.
      final eng = engineCoherences?[c.commitHash];
      if (eng != null) {
        coherences.add(eng);
      } else if (coupling != null) {
        coherences.add(coupling.coherenceFor(files));
      }
    }
    if (fileCentrality.isNotEmpty && files.isNotEmpty) {
      var sum = 0.0;
      for (final f in files) {
        sum += fileCentrality[f] ?? 0.0;
      }
      commitHubScore[c.commitHash] = sum;
      hubScores.add(sum);
    }
  }

  // Every "extreme" gate is derived from the distribution's own mean
  // + sigma. A heavy-tailed repo will have a wider gate than a
  // tight-clustered one. Field names retain the `P10/P90` legacy
  // shape because external readers expect them, but the values are
  // sigma-derived now.
  final sizeGate = _sigmaGate(sizes);
  final coherenceGate = _sigmaGate(coherences);
  final ratioGate = _sigmaGate(ratios);
  final hubGate = _sigmaGate(hubScores);
  final sizeP10 = sizeGate.low;
  final sizeP90 = sizeGate.high;
  final coherenceP10 = coherenceGate.low;
  final coherenceP90 = coherenceGate.high;
  final delAddRatioP10 = ratioGate.low;
  final delAddRatioP90 = ratioGate.high;
  final hubCentralityP90 = hubGate.high;

  final hubCommits = <String>{
    for (final e in commitHubScore.entries)
      if (e.value >= hubCentralityP90 && hubCentralityP90 > 0) e.key,
  };

  // Walk in CHRONOLOGICAL (oldest-first) order. For each author keep
  // the open chain; new commit by same author with file overlap with
  // the chain's running file-set joins; otherwise close + start new.
  // Time-gap guard uses each author's own 90th-percentile inter-commit
  // gap so deliberate maintainers stretch farther than burst-committers.
  final chainLabel = <String, String>{};
  final chronological = [...commits];
  chronological.sort((a, b) {
    final ta = _parseTs(a.authoredAt);
    final tb = _parseTs(b.authoredAt);
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  });

  // Per-author inter-commit gap distribution (in seconds). Used to
  // derive the time-break threshold per author.
  final perAuthorGaps = <String, List<double>>{};
  DateTime? prevTs;
  String? prevAuthor;
  for (final c in chronological) {
    final ts = _parseTs(c.authoredAt);
    if (ts != null && prevTs != null && c.authorEmail == prevAuthor) {
      perAuthorGaps
          .putIfAbsent(c.authorEmail, () => <double>[])
          .add(ts.difference(prevTs).inSeconds.toDouble().abs());
    }
    prevTs = ts;
    prevAuthor = c.authorEmail;
  }
  final authorGapBreak = <String, double>{};
  for (final e in perAuthorGaps.entries) {
    // Sigma-cutoff: a chain breaks when the gap exceeds this author's
    // own (mean + 2σ). Engram pattern — outlier-by-shape, no magic
    // weeks-old constant.
    final gate = _sigmaGate(e.value);
    if (gate.high > 0) {
      authorGapBreak[e.key] = gate.high;
    }
  }

  // Chain accumulator per author.
  final activeChain = <String, _ChainBuilder>{};
  final allChains = <_ChainBuilder>[];
  for (final c in chronological) {
    final files = commitFiles[c.commitHash];
    if (files == null || files.isEmpty) continue;
    final ts = _parseTs(c.authoredAt);
    final author = c.authorEmail;
    final active = activeChain[author];
    var joined = false;
    if (active != null) {
      // Time-gap check.
      final gapOk = ts == null ||
          active.lastTs == null ||
          (authorGapBreak[author] == null) ||
          ts.difference(active.lastTs!).inSeconds.toDouble().abs() <=
              authorGapBreak[author]!;
      // Overlap check — any file in common is enough; same-author plus
      // overlap is a strong continuation signal.
      final overlap = files.intersection(active.files).length;
      if (gapOk && overlap > 0) {
        active.add(c.commitHash, files, ts, authorEmail: author);
        joined = true;
      }
    }
    if (!joined) {
      // Close out the previous active chain (it's now finalized).
      final newChain = _ChainBuilder()
        ..add(c.commitHash, files, ts, authorEmail: author);
      activeChain[author] = newChain;
      allChains.add(newChain);
    }
  }
  // Promote chains of qualifying length; derive label from union.
  final convergingCommits = <String>{};
  final divergingCommits = <String>{};
  /// Per-author record of {chain's spectral radius, chain's commit
  /// list}. Feeds the cadence-baseline pass below so each author is
  /// compared against their own historical orbit, not a repo-wide mean.
  final authorOrbits = <String, List<({double radius, List<String> hashes})>>{};
  for (final ch in allChains) {
    if (ch.commits.length < _kChainMinLength) continue;
    final label = commonPrefixLabel(ch.files);
    if (label != null) {
      for (final h in ch.commits) {
        chainLabel[h] = label;
      }
    }
    // Engram orbit per chain — fit an AR(2) on the per-commit file-set
    // Jaccard similarity series. When the series has a stable orbit AND
    // a directional trend, tag every commit in the chain. Silent when
    // the chain is too short for AR(2) to mean anything or the fit
    // degenerates.
    if (ch.commits.length >= engramMinSamples) {
      final orbit = computeBranchOrbit(ch.perCommitFiles);
      if (orbit.isConverging) {
        convergingCommits.addAll(ch.commits);
      } else if (orbit.isDiverging) {
        divergingCommits.addAll(ch.commits);
      }
      // Record every valid-signal orbit for the per-author baseline,
      // regardless of converging/diverging outcome. A steady orbit is
      // still part of the author's signature.
      if (orbit.hasSignal && ch.author.isNotEmpty) {
        authorOrbits
            .putIfAbsent(ch.author, () => [])
            .add((radius: orbit.fit.spectralRadius, hashes: ch.commits));
      }
    }
  }

  // For each author with enough chains of their own, compute their
  // median spectral radius and median absolute deviation (MAD —
  // robust to outliers, unlike stddev). Any chain whose radius is
  // more than [_kAuthorCadenceSigmas]·MAD from the median is "unusual
  // *for them*." Not peer comparison; self comparison.
  final unusualCadenceCommits = <String>{};
  for (final entry in authorOrbits.entries) {
    final readings = entry.value;
    if (readings.length < _kAuthorCadenceMinChains) continue;
    final radii = readings.map((r) => r.radius).toList()..sort();
    final median = _medianSorted(radii);
    final mad = _medianAbsDeviation(radii, median);
    if (mad <= 0) continue;
    for (final r in readings) {
      if ((r.radius - median).abs() > _kAuthorCadenceSigmas * mad) {
        unusualCadenceCommits.addAll(r.hashes);
      }
    }
  }

  // Lookback = autocorrelation length of the inter-commit file-
  // overlap signal (the series' own memory). Threshold = sigma-cutoff
  // above the mean overlap.
  final overlapSignal = <double>[];
  for (var i = 1; i < chronological.length; i++) {
    final a = commitFiles[chronological[i - 1].commitHash];
    final b = commitFiles[chronological[i].commitHash];
    if (a == null || b == null || a.isEmpty || b.isEmpty) {
      overlapSignal.add(0.0);
      continue;
    }
    final inter = a.intersection(b).length;
    final union = a.union(b).length;
    overlapSignal.add(union == 0 ? 0.0 : inter / union);
  }
  final echoLookback = _autocorrelationLength(overlapSignal);
  final overlapGate = _sigmaGate(overlapSignal);
  // Sanity bounds are golden-ratio-derived, not arbitrary: the
  // threshold must sit between 1/φ² (~0.382) and 1 - 1/φ² (~0.618).
  // Below the lower bound an "echo" would catch any overlapping pair
  // (degenerate); above the upper bound it would never fire (also
  // degenerate). The golden-ratio band is the canonical "neither
  // saturated nor degenerate" interval.
  final phiSq = math.pow((1 + math.sqrt(5)) / 2, 2).toDouble(); // φ²
  final lowerBound = 1.0 / phiSq;
  final upperBound = 1.0 - lowerBound;
  final echoThreshold =
      overlapGate.high.clamp(lowerBound, upperBound);

  final echoCommits = <String>{};
  final recentBuffer = <String>[];
  for (final c in chronological) {
    final files = commitFiles[c.commitHash];
    if (files == null || files.isEmpty) {
      recentBuffer.add(c.commitHash);
      if (recentBuffer.length > echoLookback) recentBuffer.removeAt(0);
      continue;
    }
    var matched = false;
    for (final h in recentBuffer) {
      final prevFiles = commitFiles[h];
      if (prevFiles == null || prevFiles.isEmpty) continue;
      final inter = files.intersection(prevFiles).length;
      final union = files.union(prevFiles).length;
      if (union > 0 && inter / union >= echoThreshold) {
        matched = true;
        break;
      }
    }
    if (matched) echoCommits.add(c.commitHash);
    recentBuffer.add(c.commitHash);
    if (recentBuffer.length > echoLookback) recentBuffer.removeAt(0);
  }

  // For every phenomenon kind that produces a tag from a SUBSET of
  // commits (axis extremes, direction, hub, echo, drift, merge), gather
  // the indices of the commits that fall in that bucket and harvest
  // the most-distinctive subject token via log-odds. The team's own
  // word for the phenomenon — if they have one — becomes the label.
  // No literal English in the tagger.
  final bucketHugeIdx = <int>[];
  final bucketTinyIdx = <int>[];
  final bucketCleanupIdx = <int>[];
  final bucketGrowthIdx = <int>[];
  final bucketFocusedIdx = <int>[];
  final bucketSprawlIdx = <int>[];
  final bucketHubIdx = <int>[];
  final bucketEchoIdx = <int>[];
  final bucketMergeIdx = <int>[];
  // Drift requires both a scope (from prefix) and a chain/cluster
  // identity that disagrees.
  final bucketDriftIdx = <int>[];
  // Rename: any file with git's 'R' change-type (similarity-scored
  // as R100, R85, etc.).
  final bucketRenameIdx = <int>[];

  for (var i = 0; i < commits.length; i++) {
    final c = commits[i];
    final d = detailsByHash[c.commitHash];
    if (c.parentHashes.length > 1) bucketMergeIdx.add(i);
    if (d != null &&
        d.files.any((f) =>
            f.changeType == 'R' || f.changeType.startsWith('R'))) {
      bucketRenameIdx.add(i);
    }
    if (echoCommits.contains(c.commitHash)) bucketEchoIdx.add(i);
    if (hubCommits.contains(c.commitHash)) bucketHubIdx.add(i);
    if (d != null) {
      final size = (d.additions + d.deletions).toDouble();
      final ratio = d.deletions / (d.additions + 1);
      if (sizeP90 > sizeP10) {
        if (size >= sizeP90) bucketHugeIdx.add(i);
        if (size <= sizeP10) bucketTinyIdx.add(i);
      }
      if (delAddRatioP90 > delAddRatioP10 && size > 0) {
        if (ratio >= delAddRatioP90) bucketCleanupIdx.add(i);
        if (ratio <= delAddRatioP10) bucketGrowthIdx.add(i);
      }
      if (d.files.length >= 2 && coherenceP90 > coherenceP10) {
        final coh = engineCoherences?[c.commitHash] ??
            (coupling != null
                ? coupling.coherenceFor(d.files.map((f) => f.path))
                : null);
        if (coh != null) {
          if (coh >= coherenceP90) bucketFocusedIdx.add(i);
          if (coh <= coherenceP10) bucketSprawlIdx.add(i);
        }
      }
      // Drift bucket — has scope AND identity AND they disagree.
      final parsed = parseSubjectPrefix(c.subject);
      if (parsed.scope != null && parsed.scope!.trim().isNotEmpty) {
        final scope = parsed.scope!.trim().toLowerCase();
        final chain = chainLabel[c.commitHash];
        final cluster = chain ??
            (d.files.isNotEmpty
                ? commonPrefixLabel(d.files.map((f) => f.path))
                : null);
        if (cluster != null && cluster.toLowerCase() != scope) {
          bucketDriftIdx.add(i);
        }
      }
    }
  }

  final bucketLabels = <CommitTagKind, String>{};
  void tryHarvest(CommitTagKind kind, List<int> idx) {
    // projectTokenDistribution returns unnormalised mass, so summing
    // across the bucket's commits is the right aggregation —
    // harvestLabel normalises before comparing.
    Map<String, double>? bucketExpected;
    if (expectedTokensByHash != null && expectedTokensByHash.isNotEmpty) {
      bucketExpected = <String, double>{};
      for (final i in idx) {
        if (i < 0 || i >= commits.length) continue;
        final perCommit = expectedTokensByHash[commits[i].commitHash];
        if (perCommit == null) continue;
        for (final e in perCommit.entries) {
          bucketExpected.update(
            e.key,
            (v) => v + e.value,
            ifAbsent: () => e.value,
          );
        }
      }
      if (bucketExpected.isEmpty) bucketExpected = null;
    }
    final label = corpus.harvestLabel(idx, expectedTokens: bucketExpected);
    if (label != null) bucketLabels[kind] = label;
  }
  tryHarvest(CommitTagKind.axisHuge, bucketHugeIdx);
  tryHarvest(CommitTagKind.axisTiny, bucketTinyIdx);
  tryHarvest(CommitTagKind.cleanup, bucketCleanupIdx);
  tryHarvest(CommitTagKind.growth, bucketGrowthIdx);
  tryHarvest(CommitTagKind.axisFocused, bucketFocusedIdx);
  tryHarvest(CommitTagKind.axisSprawl, bucketSprawlIdx);
  tryHarvest(CommitTagKind.hub, bucketHubIdx);
  tryHarvest(CommitTagKind.rename, bucketRenameIdx);
  // Converging/diverging are universal phenomena without a harvested
  // repo-specific word — their semantics are invariant across teams.
  // Try a harvest anyway; if no distinctive word shows, fall back to
  // the universal English descriptor so the tag still surfaces.
  final convergingIdx = <int>[
    for (var i = 0; i < commits.length; i++)
      if (convergingCommits.contains(commits[i].commitHash)) i,
  ];
  final divergingIdx = <int>[
    for (var i = 0; i < commits.length; i++)
      if (divergingCommits.contains(commits[i].commitHash)) i,
  ];
  tryHarvest(CommitTagKind.converging, convergingIdx);
  tryHarvest(CommitTagKind.diverging, divergingIdx);
  final unusualCadenceIdx = <int>[
    for (var i = 0; i < commits.length; i++)
      if (unusualCadenceCommits.contains(commits[i].commitHash)) i,
  ];
  tryHarvest(CommitTagKind.unusualCadence, unusualCadenceIdx);
  // No fallback labels: if the corpus didn't surface a word for
  // converging / diverging / unusualCadence, the tag stays silent.
  tryHarvest(CommitTagKind.echo, bucketEchoIdx);
  tryHarvest(CommitTagKind.merge, bucketMergeIdx);
  tryHarvest(CommitTagKind.drift, bucketDriftIdx);

  // For every commit we already have an in-flight set of "own labels"
  // (type, scope, chain, cluster, plus the bucket labels it qualifies
  // for). Distribute those labels across the commit's files: each
  // file accumulates a label-affinity vector reflecting the kinds of
  // changes it has historically been part of. Then a 1-step diffusion
  // through the coupling graph lets each file inherit a fraction of
  // its neighbors' affinity (logos-style, weighted by Jaccard).
  // Finally, per-commit borrowing: average the diffused affinity
  // across the commit's files, subtract corpus baseline, and keep the
  // strongest signal that ISN'T already in the commit's own labels.
  // The commit acquires a label its subject never spoke — borrowed
  // from its semantic neighborhood.
  final borrowedLabels =
      _computeBorrowedLabels(commits, detailsByHash, coupling, provisionalKinds: () {
    // Per-commit own-labels for affinity seeding. Structural labels
    // only — prefix, chain, bucket — all gated by kneedle/NPMI. We
    // tried raw subject-vocab seeding; it diffused filler verbs
    // ("tweak", "fix", "update") everywhere and polluted borrows.
    // Path-segment seeding from phase 1 carries the domain vocabulary.
    final ownTokens = <String, Set<String>>{};
    for (final c in commits) {
      final tokens = <String>{};
      final parsed = parseSubjectPrefix(c.subject);
      if (parsed.type != null && prefixVocab.contains(parsed.type!)) {
        tokens.add(parsed.type!);
        if (parsed.scope != null && parsed.scope!.trim().isNotEmpty) {
          tokens.add(parsed.scope!.trim());
        }
      }
      final chain = chainLabel[c.commitHash];
      if (chain != null) tokens.add(chain);
      for (final entry in bucketLabels.entries) {
        if (_belongsToBucket(c, detailsByHash[c.commitHash], entry.key,
            sizeP10: sizeP10, sizeP90: sizeP90,
            ratioP10: delAddRatioP10, ratioP90: delAddRatioP90,
            coherenceP10: coherenceP10, coherenceP90: coherenceP90,
            echoCommits: echoCommits, hubCommits: hubCommits,
            coupling: coupling,
            engineCoherence: engineCoherences?[c.commitHash])) {
          tokens.add(entry.value);
        }
      }
      ownTokens[c.commitHash] = tokens;
    }
    return ownTokens;
  });

  final provisional = RepositoryTagProfile(
    prefixVocab: prefixVocab,
    sizeP10: sizeP10,
    sizeP90: sizeP90,
    coherenceP10: coherenceP10,
    coherenceP90: coherenceP90,
    delAddRatioP10: delAddRatioP10,
    delAddRatioP90: delAddRatioP90,
    hubCentralityP90: hubCentralityP90,
    chainLabel: chainLabel,
    echoCommits: echoCommits,
    hubCommits: hubCommits,
    convergingCommits: convergingCommits,
    divergingCommits: divergingCommits,
    unusualCadenceCommits: unusualCadenceCommits,
    labelFrequency: const {},
    commitCount: commits.length,
    bucketLabels: bucketLabels,
    borrowedLabels: borrowedLabels,
  );
  final freq = <String, int>{};
  for (final c in commits) {
    final tags = tagCommit(
      commit: c,
      detail: detailsByHash[c.commitHash],
      profile: provisional,
      coupling: coupling,
      engineCoherence: engineCoherences?[c.commitHash],
    );
    for (final t in tags) {
      freq.update(t.label, (v) => v + 1, ifAbsent: () => 1);
    }
  }

  return RepositoryTagProfile(
    prefixVocab: prefixVocab,
    sizeP10: sizeP10,
    sizeP90: sizeP90,
    coherenceP10: coherenceP10,
    coherenceP90: coherenceP90,
    delAddRatioP10: delAddRatioP10,
    delAddRatioP90: delAddRatioP90,
    hubCentralityP90: hubCentralityP90,
    chainLabel: chainLabel,
    echoCommits: echoCommits,
    hubCommits: hubCommits,
    convergingCommits: convergingCommits,
    divergingCommits: divergingCommits,
    unusualCadenceCommits: unusualCadenceCommits,
    labelFrequency: freq,
    commitCount: commits.length,
    bucketLabels: bucketLabels,
    borrowedLabels: borrowedLabels,
  );
}

/// Tests whether a commit qualifies for a bucket. Used by the borrowed-
/// label diffusion seeding so the per-file affinity reflects exactly
/// the labels the renderer would emit. Bucket gates here MUST mirror
/// the gates inside [tagCommit].
bool _belongsToBucket(
  CommitHistoryEntry c,
  CommitDetailData? d,
  CommitTagKind kind, {
  required double sizeP10,
  required double sizeP90,
  required double ratioP10,
  required double ratioP90,
  required double coherenceP10,
  required double coherenceP90,
  required Set<String> echoCommits,
  required Set<String> hubCommits,
  required FileCouplingMatrix? coupling,
  required double? engineCoherence,
}) {
  switch (kind) {
    case CommitTagKind.merge:
      return c.parentHashes.length > 1;
    case CommitTagKind.rename:
      if (d == null) return false;
      return d.files
          .any((f) => f.changeType == 'R' || f.changeType.startsWith('R'));
    case CommitTagKind.echo:
      return echoCommits.contains(c.commitHash);
    case CommitTagKind.hub:
      return hubCommits.contains(c.commitHash);
    case CommitTagKind.axisHuge:
      if (d == null || sizeP90 <= sizeP10) return false;
      return (d.additions + d.deletions).toDouble() >= sizeP90;
    case CommitTagKind.axisTiny:
      if (d == null || sizeP90 <= sizeP10) return false;
      return (d.additions + d.deletions).toDouble() <= sizeP10;
    case CommitTagKind.cleanup:
      if (d == null || ratioP90 <= ratioP10) return false;
      return d.additions + d.deletions > 0 &&
          d.deletions / (d.additions + 1) >= ratioP90;
    case CommitTagKind.growth:
      if (d == null || ratioP90 <= ratioP10) return false;
      return d.additions + d.deletions > 0 &&
          d.deletions / (d.additions + 1) <= ratioP10;
    case CommitTagKind.axisFocused:
    case CommitTagKind.axisSprawl:
      if (d == null ||
          d.files.length < 2 ||
          coherenceP90 <= coherenceP10) return false;
      final coh = engineCoherence ??
          (coupling != null
              ? coupling.coherenceFor(d.files.map((f) => f.path))
              : null);
      if (coh == null) return false;
      return kind == CommitTagKind.axisFocused
          ? coh >= coherenceP90
          : coh <= coherenceP10;
    case CommitTagKind.drift:
    case CommitTagKind.unusualCadence:
      // Drift / unusualCadence are structural observations — not
      // buckets we accumulate file affinity for. Skip.
      return false;
    case CommitTagKind.type:
    case CommitTagKind.scope:
    case CommitTagKind.chain:
    case CommitTagKind.cluster:
    case CommitTagKind.borrowed:
    case CommitTagKind.converging:
    case CommitTagKind.diverging:
      // Identity / chain-wide kinds — not commit-local bucket-gated.
      // Converging/diverging bucketing happens once per chain in the
      // profile builder; seeding affinity back through this path would
      // double-count.
      // (unusualCadence is handled in the drift/structural arm above.)
      return false;
  }
}

/// Builds a per-file label-affinity table from each commit's own
/// labels (via [provisionalKinds]), propagates affinity one step
/// through the file-coupling graph (Jaccard-weighted), then per
/// commit averages the diffused affinity across its files, subtracts
/// the corpus baseline, and picks the strongest label not already in
/// the commit's own labels — sigma-gated.
/// Returns a sparse map: only commits with a confident borrow appear.
Map<String, ({String label, double score})> _computeBorrowedLabels(
  List<CommitHistoryEntry> commits,
  Map<String, CommitDetailData> detailsByHash,
  FileCouplingMatrix? coupling, {
  required Map<String, Set<String>> Function() provisionalKinds,
}) {
  final ownTokens = provisionalKinds();
  if (ownTokens.isEmpty) return const {};

  // Uniform-weight: every commit that touched a file deposits the
  // same fraction regardless of when — files keep their full history.
  // Also build the per-commit label-pair co-occurrence count: which
  // labels hang out together in commits. Used in phase 3 for the
  // co-occurrence rerank — borrowing `session` is more credible when
  // the commit already has `auth`, because (auth, session) co-occur
  // historically. Built once; reused for every borrow query.
  final fileAffinity = <String, Map<String, double>>{};
  final corpusBaseline = <String, double>{};
  // labelDocFreq[w] = how many commits carry label w.
  final labelDocFreq = <String, int>{};
  // pairDocFreq[(a,b)] = how many commits carry BOTH a and b.
  // Stored canonically (a < b lex) to avoid double-counting.
  final pairDocFreq = <String, int>{};
  var totalCommitsWithDetail = 0;
  String pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a\u0001$b' : '$b\u0001$a';
  for (final c in commits) {
    final d = detailsByHash[c.commitHash];
    if (d == null || d.files.isEmpty) continue;
    final tokens = ownTokens[c.commitHash];
    if (tokens == null || tokens.isEmpty) continue;
    totalCommitsWithDetail++;
    final perToken = 1.0 / tokens.length;
    for (final t in tokens) {
      corpusBaseline.update(t, (v) => v + perToken,
          ifAbsent: () => perToken);
      labelDocFreq.update(t, (v) => v + 1, ifAbsent: () => 1);
    }
    // Pair counts.
    final tList = tokens.toList();
    for (var i = 0; i < tList.length; i++) {
      for (var j = i + 1; j < tList.length; j++) {
        pairDocFreq.update(pairKey(tList[i], tList[j]), (v) => v + 1,
            ifAbsent: () => 1);
      }
    }
    final perFile = 1.0 / d.files.length;
    for (final f in d.files) {
      final fAff = fileAffinity.putIfAbsent(f.path, () => {});
      for (final t in tokens) {
        fAff.update(t, (v) => v + perToken * perFile,
            ifAbsent: () => perToken * perFile);
      }
    }
  }
  if (fileAffinity.isEmpty || totalCommitsWithDetail == 0) return const {};

  // Each file's path segments ARE domain concepts the team has
  // organized code around. A file under `lib/features/auth/` is an
  // auth thing — that's the team's own taxonomy, made permanent in
  // the directory tree. Deposit each file's path segments as base
  // affinity for that file (weight 1.0 per segment, comparable to a
  // commit-token contribution). This makes borrow vocabulary
  // domain-grounded: NPMI surfaces structural concepts, not random
  // subject filler. Universally-shared segments like "lib" appear in
  // every file's affinity → high pGlobal → ≈ 0 NPMI lift → never win.
  // Specific segments like "auth" only appear in auth files →
  // commits touching those files get strong NPMI lift for "auth".
  final segmentDocFreq = <String, int>{};
  final filePathSegments = <String, Set<String>>{};
  final segmentWordRe = RegExp(r'^[a-z][a-z0-9_]+$');
  // Splits a basename into its semantic tokens. Strips the file
  // extension, then splits on common identifier-boundary characters
  // (snake_case, kebab-case, dot-separated) AND on camelCase
  // boundaries via the lowercase→uppercase transition rule. This
  // recovers tokens like {`auth`, `helpers`} from `AuthHelpers.dart`
  // or `auth_helpers.dart` — meaningful semantics that path-
  // hierarchy alone misses, especially in flat repos.
  Iterable<String> tokenizeBasename(String name) sync* {
    // Strip extension(s).
    var stripped = name;
    final dot = stripped.indexOf('.');
    if (dot > 0) stripped = stripped.substring(0, dot);
    // Insert split-marker between lowercase→uppercase transitions.
    final spaced = stripped.replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}');
    for (final t in spaced.split(RegExp(r'[_\-\.]+'))) {
      final lower = t.toLowerCase();
      if (lower.length < 3) continue;
      if (!segmentWordRe.hasMatch(lower)) continue;
      yield lower;
    }
  }

  for (final f in fileAffinity.keys) {
    final segs = <String>{};
    final parts = f.replaceAll('\\', '/').split('/');
    // Directory segments (everything except the basename).
    for (var k = 0; k < parts.length - 1; k++) {
      final seg = parts[k].toLowerCase();
      if (seg.length < 3) continue;
      if (!segmentWordRe.hasMatch(seg)) continue;
      segs.add(seg);
    }
    // Basename tokens — tokenized to recover camelCase/snake_case.
    // Critical for flat-package repos (Python, Rust, JS) where the
    // directory tree carries less signal than file names do.
    if (parts.isNotEmpty) {
      for (final t in tokenizeBasename(parts.last)) {
        segs.add(t);
      }
    }
    filePathSegments[f] = segs;
    for (final s in segs) {
      segmentDocFreq.update(s, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  // Smoothed-IDF path seeding. Each segment's contribution is
  // log(1 + N_files / df). Compared to raw log(N/df):
  //   * Universal segments (df=N) get log(2) ≈ 0.69 instead of 0 —
  //     they still contribute SOME signal (a `widgets/` borrow can
  //     fire even when most files are widgets, if no other label is
  //     more locally concentrated).
  //   * Specific segments (df=N/10) get log(11) ≈ 2.4 — meaningfully
  //     stronger than generic ones.
  //   * Rare segments (df=2) max out around log(N/2 + 1).
  // The +1 inside log is the standard smoothed-IDF form (used by
  // BM25, scikit's TfidfVectorizer with smooth_idf=True). Avoids
  // the discontinuous "all-or-nothing" edge of raw IDF.
  final fileTotal = filePathSegments.length.toDouble();
  final segmentIdf = <String, double>{
    for (final e in segmentDocFreq.entries)
      if (e.value >= 2) e.key: math.log(1.0 + fileTotal / e.value),
  };
  filePathSegments.forEach((path, segs) {
    final fAff = fileAffinity[path]!;
    for (final s in segs) {
      final w = segmentIdf[s];
      if (w == null || w <= 0) continue;
      fAff.update(s, (v) => v + w, ifAbsent: () => w);
      corpusBaseline.update(s, (v) => v + w, ifAbsent: () => w);
    }
    // (labelDocFreq + pairDocFreq are NOT incremented here — they're
    // built in a unified per-commit pass below so commit-token and
    // path-segment doc frequencies stay on the same denominator.)
  });
  // (Intentionally NOT dividing corpusBaseline by totalCommitsWithDetail
  // — kept raw so pGlobal is a clean proportion.)

  // labelDocFreq[L] = number of COMMITS where L is "present", where
  // present means: L is in the commit's own tokens OR L is a path
  // segment of any file the commit touches. Same denominator
  // (totalCommitsWithDetail) for both layers, so pLabel = freq /
  // totalCommits is a real per-commit probability bounded by 1.
  // Earlier this was incremented per-FILE for path segs and per-COMMIT
  // for tokens, mixing scales — pLabel could exceed 1, the co-PMI
  // pair denominator inflated, pmiPair went negative, and the rerank
  // bonus collapsed to 0 for every borrow. Fixing this restores the
  // co-occurrence boost.
  labelDocFreq.clear();
  pairDocFreq.clear();
  for (final c in commits) {
    final d = detailsByHash[c.commitHash];
    if (d == null || d.files.isEmpty) continue;
    final tokens = ownTokens[c.commitHash] ?? const <String>{};
    final present = <String>{...tokens};
    for (final f in d.files) {
      final segs = filePathSegments[f.path];
      if (segs == null) continue;
      for (final s in segs) {
        if (segmentIdf.containsKey(s)) present.add(s);
      }
    }
    if (present.isEmpty) continue;
    for (final l in present) {
      labelDocFreq.update(l, (v) => v + 1, ifAbsent: () => 1);
    }
    final list = present.toList();
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        pairDocFreq.update(pairKey(list[i], list[j]),
            (v) => v + 1, ifAbsent: () => 1);
      }
    }
  }

  // Earlier this pass dosed every file in an epoch with the epoch's
  // dominant label, then the diffusion smeared that across the
  // coupling graph. Result: borrowed pills converged to "the project's
  // current era label" everywhere — boring, indistinct. Keep the
  // epoch math computed (cheap, future-useful) but DON'T fold it into
  // file affinity; file affinity stays purely structural.
  final chronologicalForEpochs = [...commits];
  chronologicalForEpochs.sort((a, b) {
    final ta = _parseTs(a.authoredAt);
    final tb = _parseTs(b.authoredAt);
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  });
  // Each commit's "vector" = its set of own-tokens (1-hot in the
  // global label space). Inter-commit error = symmetric set distance.
  final transitionErrors = <double>[];
  for (var k = 1; k < chronologicalForEpochs.length; k++) {
    final a = ownTokens[chronologicalForEpochs[k - 1].commitHash] ??
        const <String>{};
    final b =
        ownTokens[chronologicalForEpochs[k].commitHash] ?? const <String>{};
    if (a.isEmpty && b.isEmpty) {
      transitionErrors.add(0);
      continue;
    }
    final diff = a.union(b).length - a.intersection(b).length;
    final norm = a.union(b).length;
    transitionErrors.add(norm == 0 ? 0 : diff / norm);
  }
  // Engram threshold: mean + 3σ on the error sequence.
  final epochs = <List<int>>[];
  if (transitionErrors.isNotEmpty) {
    final eMean =
        transitionErrors.reduce((x, y) => x + y) / transitionErrors.length;
    final eVar = transitionErrors
            .map((e) => (e - eMean) * (e - eMean))
            .reduce((x, y) => x + y) /
        transitionErrors.length;
    final eThresh = eMean + 3.0 * math.sqrt(eVar);
    var start = 0;
    for (var k = 0; k < transitionErrors.length; k++) {
      if (transitionErrors[k] > eThresh && k - start >= 4) {
        epochs.add(List.generate(k - start + 1, (i) => start + i));
        start = k + 1;
      }
    }
    if (start < chronologicalForEpochs.length) {
      epochs.add(List.generate(
          chronologicalForEpochs.length - start, (i) => start + i));
    }
  }
  // Epoch labels are computed (cheap, future-useful) but intentionally
  // NOT folded into file affinity. Doing so dominated diffusion and
  // smeared the per-commit borrowing toward "current era label
  // everywhere" — banal. Keep the structural diffusion clean.
  for (final _ in epochs) { /* intentionally inert */ }

  // Born-mixes F0/CC/SP/V into per-pair edge probabilities, builds a
  // top-K adjacency, and runs Chebyshev heat-kernel diffusion.
  // engine.diffuse(source) returns φ for every file; we use φ as the
  // weight when aggregating fileAffinity so the borrowed score
  // reflects where the commit's heat lands across all four axes,
  // not just direct Jaccard neighbours.

  // Build LogosGitStats from the commit data we've already iterated.
  // Track per-file commit-index series alongside touches/churn so the
  // engine's per-file curved AR(2) metric has the data it needs to
  // fit each file's inter-touch-gap dynamics. Index is monotonic-by-
  // iteration; gap regularity is direction-invariant so iteration
  // order doesn't affect the AR(2) fit.
  final touches = <String, int>{};
  final fileChurn = <String, double>{};
  final perFileCommitIndices = <String, List<int>>{};
  // EWMA smoothing for volatility — ½ is the canonical "balanced
  // memory" value; no taste, just exponential decay symmetry.
  const double ewmaAlpha = 0.5;
  var commitIndex = 0;
  for (final c in commits) {
    final d = detailsByHash[c.commitHash];
    if (d == null) continue;
    for (final f in d.files) {
      touches.update(f.path, (v) => v + 1, ifAbsent: () => 1);
      (perFileCommitIndices[f.path] ??= <int>[]).add(commitIndex);
      final churn = (f.additions + f.deletions).toDouble();
      fileChurn.update(
        f.path,
        (v) => ewmaAlpha * churn + (1 - ewmaAlpha) * v,
        ifAbsent: () => churn,
      );
    }
    commitIndex++;
  }
  var volMean = 0.0;
  var volStddev = 0.0;
  if (fileChurn.isNotEmpty) {
    final vals = fileChurn.values.toList();
    volMean = vals.reduce((a, b) => a + b) / vals.length;
    final variance = vals
            .map((v) => (v - volMean) * (v - volMean))
            .reduce((a, b) => a + b) /
        vals.length;
    volStddev = math.sqrt(variance);
  }
  final logosStats = LogosGitStats(
    touches: touches,
    totalCommits: totalCommitsWithDetail,
    volatility: fileChurn,
    volMean: volMean,
    volStddev: volStddev,
    coupling: coupling ?? FileCouplingMatrix.empty,
    perFileCommitIndices: perFileCommitIndices,
  );
  final engine = LogosGit.buildFromStats(logosStats);

  // Phase 3: per-commit borrowing — NPMI + co-occurrence rerank.
  // For each candidate label, score = NPMI(label, commit-neighborhood)
  // — bounded in [-1, 1], scale-free, the proper information-theoretic
  // measure of "how much more does this label associate with this
  // neighborhood than with the corpus." Replaces the previous additive
  // lift (mean - baseline), which was unnormalized and double-counted
  // distinctness with the harvest-time log-odds.
  //
  // Then rerank: multiply by exp(mean PMI between candidate and the
  // commit's existing labels). Borrowing `session` survives when the
  // commit already has `auth` and (auth,session) co-occur historically;
  // borrowing `paint` next to `auth` gets demoted because they don't.
  // Labels with no own-labels skip this rerank gracefully.
  final out = <String, ({String label, double score})>{};
  // Total mass of all per-commit label-tokens across the corpus, for
  // normalizing affinity values into probabilities.
  final totalAffinityMass = corpusBaseline.values
      .fold<double>(0.0, (a, b) => a + b);
  // Scratch buffers for the per-commit three-temperature recombination.
  // Allocated once and reused across every commit in the loop below —
  // each `basis.recombineInto` writes into these instead of handing out
  // a fresh Float64List. With N commits and n nodes, this saves 3·N
  // allocations of 8·n bytes (≈24 MB of transient heap at N=100, n=10k).
  final phi05Vec = Float64List(engine.graph.n);
  final phi10Vec = Float64List(engine.graph.n);
  final phi20Vec = Float64List(engine.graph.n);
  for (final c in commits) {
    final d = detailsByHash[c.commitHash];
    if (d == null || d.files.isEmpty) continue;
    final ownLabels = ownTokens[c.commitHash] ?? const <String>{};

    // Multi-axis Logos diffusion — impact-weighted, multi-temperature,
    // basis-reused, retention-modulated. The full attention-codec
    // workflow.
    //
    // (1) Impact-weighted source heat. Files with more churn inject
    //     more heat. log(1 + churn) softens heavy-churn dominance so
    //     a 1000-line file doesn't outvote a 20-line one 50:1 — but
    //     it does get ~3× the heat. Floor 0.5 keeps zero-churn files
    //     weakly weighted (touched = evidence).
    //
    // (2) Basis built ONCE via `buildBasisWeighted`. The Chebyshev
    //     basis vectors are t-independent — only the recombination
    //     coefficients change with temperature. So for our 3-temp
    //     distillation we do K matvecs once + 3 cheap recombines
    //     instead of 3 × K matvecs. ~3× speedup per commit.
    //
    // (3) Multi-temperature distillation: t = 0.5 (tight neighborhood),
    //     t = 1.0 (canonical 1-hop), t = 2.0 (wide semantic). Combined
    //     via geometric mean — files CONSISTENTLY near the source
    //     across all scales win. Multi-scale robustness is the signal.
    //
    // (4) Heat retention as confidence modulator. Post-diffusion, the
    //     fraction of total heat still at source files measures how
    //     well-anchored the commit is. Focused commit (files in one
    //     cluster) → heat stays put → high retention → confident
    //     borrow. Sprawl commit → heat dissipates everywhere → low
    //     retention → cautious borrow. Multiplied into the score so
    //     the renderer's confidence transform reflects this naturally.
    final sourceFiles = <String>{for (final f in d.files) f.path};
    final sourceWeights = <String, double>{};
    for (final f in d.files) {
      final churn = (f.additions + f.deletions).toDouble();
      sourceWeights[f.path] = math.log(1.0 + churn).clamp(0.5, double.infinity);
    }
    final basis = engine.buildBasisWeighted(sourceWeights);
    if (basis == null) continue;
    basis.recombineInto(0.5, phi05Vec);
    basis.recombineInto(1.0, phi10Vec);
    basis.recombineInto(2.0, phi20Vec);
    // Geometric mean across scales. eps avoids log(0); files present
    // at only one scale contribute a small amount, files present at
    // all scales get the full geometric-mean lift.
    const eps = 1e-9;
    final phi = <String, double>{};
    var totalHeat = 0.0;
    var sourceHeat = 0.0;
    for (var i = 0; i < basis.n; i++) {
      final p05 = phi05Vec[i] > 0 ? phi05Vec[i] : 0.0;
      final p10 = phi10Vec[i] > 0 ? phi10Vec[i] : 0.0;
      final p20 = phi20Vec[i] > 0 ? phi20Vec[i] : 0.0;
      if (p05 + p10 + p20 <= 0) continue;
      final v = math.pow((p05 + eps) * (p10 + eps) * (p20 + eps), 1.0 / 3)
          .toDouble();
      final path = engine.nodePaths[i];
      phi[path] = v;
      totalHeat += v;
      if (sourceFiles.contains(path)) sourceHeat += v;
    }
    if (phi.isEmpty) continue;
    // Retention ∈ [0, 1]: fraction of heat still at source files.
    // sqrt softens — even moderate retention gives meaningful boost,
    // mathematically stabilising for proportions (variance-stabilizing
    // transform on a Bernoulli rate).
    final retentionFraction = totalHeat > 0 ? sourceHeat / totalHeat : 0.0;
    final retentionModulator = math.sqrt(retentionFraction.clamp(0.0, 1.0));

    // Aggregate fileAffinity weighted by φ. agg[label] = Σ φ × mass.
    final agg = <String, double>{};
    phi.forEach((path, w) {
      final aff = fileAffinity[path];
      if (aff == null) return;
      aff.forEach((label, mass) {
        final contribution = w * mass;
        agg.update(label, (v) => v + contribution,
            ifAbsent: () => contribution);
      });
    });
    if (agg.isEmpty) continue;
    final aggTotal = agg.values.fold<double>(0.0, (a, b) => a + b);
    if (aggTotal <= 0) continue;
    final scores = <_LabelCandidate>[];
    agg.forEach((label, sum) {
      if (ownLabels.contains(label)) return; // can't borrow what you have
      // p(label | neighborhood) — local probability inside the commit.
      final pLocal = sum / aggTotal;
      // p(label) — global label probability as a clean proportion of
      // total mass. Both numerator and denominator are raw sums on
      // the same scale, so this is a real probability — no artificial
      // denominator smoothing distorting PMI. Labels reaching this
      // loop come from `agg`, so they're guaranteed to be in
      // corpusBaseline and pGlobal can't be zero in practice.
      final globalMass = corpusBaseline[label] ?? 0.0;
      if (pLocal <= 0 || globalMass <= 0 || totalAffinityMass <= 0) return;
      final pGlobal = globalMass / totalAffinityMass;
      // Raw PMI = log(concentration ratio). PMI of 0.7 ≈ "2× more
      // concentrated than chance"; PMI of 2.3 ≈ "10×". Used PMI
      // instead of NPMI here: NPMI's normalization divides by
      // -log(p_joint) which scales with log(corpus_size), starving
      // confidence in larger repos. Raw PMI is scale-invariant in N
      // and maps cleanly to confidence via 1 - exp(-PMI) downstream.
      final pmi = math.log(pLocal / pGlobal);
      if (pmi <= 0) return; // candidate doesn't lift over baseline

      // Co-occurrence rerank: how often does this candidate co-occur
      // with the commit's own labels? Multiplicative bonus via mean
      // PMI(candidate, ownLabel). Skip when commit has no own-labels.
      var coBonus = 0.0;
      if (ownLabels.isNotEmpty && totalCommitsWithDetail > 0) {
        var co = 0.0;
        var coN = 0;
        final pLabel = (labelDocFreq[label] ?? 0) /
            totalCommitsWithDetail;
        if (pLabel > 0) {
          for (final own in ownLabels) {
            final pOwn = (labelDocFreq[own] ?? 0) /
                totalCommitsWithDetail;
            final pairCount = pairDocFreq[pairKey(own, label)] ?? 0;
            if (pOwn <= 0 || pairCount <= 0) continue;
            final pPair = pairCount / totalCommitsWithDetail;
            final pmiPair = math.log(pPair / (pOwn * pLabel));
            // Clamp to non-negative so anti-correlated pairs don't
            // veto a borrow with strong neighborhood signal.
            if (pmiPair > 0) {
              co += pmiPair;
              coN++;
            }
          }
          if (coN > 0) coBonus = co / coN;
        }
      }
      // Final score = PMI(neighborhood) + mean PMI(co-occurrence).
      // Additive in log-space — multiplicative composition of the two
      // independent concentration ratios. A label that's 5× more
      // concentrated AND co-occurs 2× more with own labels combines
      // to ~10× total — log(10) ≈ 2.3, mapping to confidence ≈ 0.90.
      // Retention modulator (sqrt of source-heat fraction) damps
      // Dampens borrows from sprawl commits where heat dissipated
      // widely — less-coherent neighborhoods produce less-confident
      // borrows.
      final finalScore = (pmi + coBonus) * retentionModulator;
      scores.add(_LabelCandidate(label, finalScore));
    });
    if (scores.isEmpty) continue;
    // Emit whenever NPMI > 0 (already enforced per-score). The
    // renderer modulates visual weight by score — weak borrows read
    // faint, strong ones read bold — so we don't need a binary gate.
    scores.sort((a, b) => b.score.compareTo(a.score));
    final top = scores.first;
    if (top.score <= 0) continue;
    out[c.commitHash] = (label: top.label, score: top.score);
  }
  return out;
}

class _ChainBuilder {
  final List<String> commits = [];
  final Set<String> files = {};
  /// Per-commit file sets, in chain order. Needed for the branch-orbit
  /// Engram fit — the consecutive Jaccard series can't be reconstructed
  /// from the union alone.
  final List<Set<String>> perCommitFiles = [];
  DateTime? lastTs;
  /// Author email — set on first add, never mutated (chains are
  /// single-author by construction). Used by the per-author cadence
  /// baseline to bucket orbit readings back to their source.
  String author = '';
  void add(String hash, Set<String> commitFiles, DateTime? ts,
      {String authorEmail = ''}) {
    commits.add(hash);
    files.addAll(commitFiles);
    perCommitFiles.add(Set<String>.from(commitFiles));
    if (ts != null) lastTs = ts;
    if (author.isEmpty && authorEmail.isNotEmpty) author = authorEmail;
  }
}

// Per-commit tagging

const List<CommitTagKind> _kindPriority = [
  // Identity first.
  CommitTagKind.type,
  CommitTagKind.scope,
  CommitTagKind.chain,
  CommitTagKind.cluster,
  // Direction next.
  CommitTagKind.cleanup,
  CommitTagKind.growth,
  CommitTagKind.echo,
  CommitTagKind.hub,
  // Truth-tellers.
  CommitTagKind.drift,
  // Distribution.
  CommitTagKind.axisFocused,
  CommitTagKind.axisSprawl,
  CommitTagKind.axisHuge,
  CommitTagKind.axisTiny,
  // Branch trajectory — where's this chain headed? Positioned with the
  // other structural observations; outranks borrowed so users see the
  // high-confidence Engram-fit result first.
  CommitTagKind.converging,
  CommitTagKind.diverging,
  // Self-comparison cadence — sits next to the other structural
  // truth-tellers. Chain-wide converging/diverging reads first when
  // both fire, since that shape describes the whole chain rather
  // than the author's individual deviation.
  CommitTagKind.unusualCadence,
  CommitTagKind.merge,
  // Borrowed last — interesting but the lowest-confidence signal,
  // shown only after the commit's own claims and observations.
  CommitTagKind.borrowed,
];

// (Universal-descriptor literals removed. Labels for axisHuge / axisTiny
// / cleanup / growth / axisFocused / axisSprawl / hub / echo / drift /
// merge are HARVESTED from the repo's own commit subjects via
// _SubjectCorpus.harvestLabel and stored in
// RepositoryTagProfile.bucketLabels. If a bucket has no distinctive
// word, the kind is silent — system never invents English the team
// doesn't use.)

List<CommitTag> tagCommit({
  required CommitHistoryEntry commit,
  required CommitDetailData? detail,
  required RepositoryTagProfile profile,
  required FileCouplingMatrix? coupling,
  /// Optional engine-derived coherence for this commit (Born-mixed
  /// multi-axis). When present, replaces the raw Jaccard fallback used
  /// for the focused/sprawl percentile gate.
  double? engineCoherence,
  int maxTags = 3,
}) {
  final out = <CommitTag>[];
  double rarityOf(String label) {
    if (profile.commitCount == 0) return 0.5;
    final f = profile.labelFrequency[label] ?? 0;
    return 1.0 - (f / profile.commitCount);
  }

  final parsed = parseSubjectPrefix(commit.subject);
  String? typeLabel;
  String? scopeLabel;
  if (parsed.type != null && profile.prefixVocab.contains(parsed.type!)) {
    typeLabel = parsed.type!;
    out.add(CommitTag(
      label: typeLabel,
      kind: CommitTagKind.type,
      rarity: rarityOf(typeLabel),
    ));
    if (parsed.scope != null && parsed.scope!.trim().isNotEmpty) {
      scopeLabel = parsed.scope!.trim();
      out.add(CommitTag(
        label: scopeLabel,
        kind: CommitTagKind.scope,
        rarity: rarityOf(scopeLabel),
      ));
    }
  }

  // Chain labels are neighbor-grounded — they survive across the
  // whole sequence. Per-commit cluster labels only run for solo
  // commits (no chain assignment).
  final chain = profile.chainLabel[commit.commitHash];
  String? identityLabel; // chain or cluster
  if (chain != null) {
    identityLabel = chain;
    if (!_dedupe(out, chain)) {
      out.add(CommitTag(
        label: chain,
        kind: CommitTagKind.chain,
        rarity: rarityOf(chain),
      ));
    }
  } else if (detail != null && detail.files.isNotEmpty) {
    final lbl = commonPrefixLabel(detail.files.map((f) => f.path));
    if (lbl != null && !_dedupe(out, lbl)) {
      identityLabel = lbl;
      out.add(CommitTag(
        label: lbl,
        kind: CommitTagKind.cluster,
        rarity: rarityOf(lbl),
      ));
    }
  }

  // Helper: emit a tag for the given kind ONLY if the profile has a
  // harvested label for it. Silent fallback when no distinctive word
  // was found for the bucket — never fabricates English the team
  // doesn't use.
  void emitIfLabeled(CommitTagKind kind) {
    if (_dedupe(out, profile.bucketLabels[kind] ?? '')) return;
    final lbl = profile.bucketLabels[kind];
    if (lbl == null) return;
    out.add(CommitTag(
      label: lbl,
      kind: kind,
      rarity: rarityOf(lbl),
    ));
  }

  // Smarter check: drift fires only when scope and identity share NO
  // path-segment AND neither is a substring of the other. Avoids false
  // positives like `feat(auth)` on a commit clustered to `auth_v2`,
  // or `fix(ui)` on a commit clustered to `ui-shell`.
  if (scopeLabel != null &&
      identityLabel != null &&
      _isDrift(scopeLabel, identityLabel, detail?.files)) {
    emitIfLabeled(CommitTagKind.drift);
  }

  if (commit.parentHashes.length > 1) {
    emitIfLabeled(CommitTagKind.merge);
  }
  if (detail != null &&
      detail.files
          .any((f) => f.changeType == 'R' || f.changeType.startsWith('R'))) {
    emitIfLabeled(CommitTagKind.rename);
  }

  if (detail != null) {
    final size = (detail.additions + detail.deletions).toDouble();
    final ratio = detail.deletions / (detail.additions + 1);

    // Cleanup / growth via repo-relative ratio sigma-gates. Subsumes
    // size axis when applicable — direction is more informative than
    // magnitude.
    var directionEmitted = false;
    if (profile.delAddRatioP90 > profile.delAddRatioP10) {
      if (ratio >= profile.delAddRatioP90 && size > 0) {
        emitIfLabeled(CommitTagKind.cleanup);
        directionEmitted = true;
      } else if (ratio <= profile.delAddRatioP10 && size > 0) {
        emitIfLabeled(CommitTagKind.growth);
        directionEmitted = true;
      }
    }

    if (profile.echoCommits.contains(commit.commitHash)) {
      emitIfLabeled(CommitTagKind.echo);
    }
    if (profile.hubCommits.contains(commit.commitHash)) {
      emitIfLabeled(CommitTagKind.hub);
    }
    // Branch trajectory — converging/diverging. Mutually exclusive; the
    // profile's Engram fit already picks at most one per chain.
    if (profile.convergingCommits.contains(commit.commitHash)) {
      emitIfLabeled(CommitTagKind.converging);
    } else if (profile.divergingCommits.contains(commit.commitHash)) {
      emitIfLabeled(CommitTagKind.diverging);
    }
    // Self-comparison: is this chain's orbit an outlier for this
    // author's own history? Independent of converging/diverging —
    // both signals can fire simultaneously (a diverging chain that's
    // diverging in a way unusual for the author gets both tags).
    if (profile.unusualCadenceCommits.contains(commit.commitHash)) {
      emitIfLabeled(CommitTagKind.unusualCadence);
    }

    if (!directionEmitted && profile.sizeP90 > profile.sizeP10) {
      if (size >= profile.sizeP90) {
        emitIfLabeled(CommitTagKind.axisHuge);
      } else if (size <= profile.sizeP10) {
        emitIfLabeled(CommitTagKind.axisTiny);
      }
    }

    if (detail.files.length >= 2 &&
        profile.coherenceP90 > profile.coherenceP10 &&
        (engineCoherence != null || coupling != null)) {
      final c = engineCoherence ??
          coupling!.coherenceFor(detail.files.map((f) => f.path));
      if (c >= profile.coherenceP90) {
        emitIfLabeled(CommitTagKind.axisFocused);
      } else if (c <= profile.coherenceP10) {
        emitIfLabeled(CommitTagKind.axisSprawl);
      }
    }
  }

  // Score (NPMI × exp(co-PMI)) maps to pill confidence: opacity and
  // weight scale with signal strength. The only gate is NPMI > 0;
  // the renderer handles the rest visually.
  final borrowed = profile.borrowedLabels[commit.commitHash];
  if (borrowed != null && !_dedupe(out, borrowed.label)) {
    // Score is raw PMI (log of concentration ratio). Map to confidence
    // in [0,1) via 1 - exp(-score) — the standard "association
    // strength" transform. PMI=0.7 (2×) → conf 0.50; PMI=1.6 (5×) →
    // conf 0.80; PMI=2.3 (10×) → conf 0.90; PMI=4.6 (100×) → conf 0.99.
    // Smooth, asymptotic, scale-invariant in corpus size.
    final score = borrowed.score;
    final confidence = score <= 0 ? 0.0 : 1.0 - math.exp(-score);
    out.add(CommitTag(
      label: borrowed.label,
      kind: CommitTagKind.borrowed,
      rarity: rarityOf(borrowed.label),
      confidence: confidence,
    ));
  }

  if (out.isEmpty) return const [];

  out.sort((a, b) {
    final rCmp = b.rarity.compareTo(a.rarity);
    if (rCmp != 0) return rCmp;
    return _kindPriority.indexOf(a.kind).compareTo(
          _kindPriority.indexOf(b.kind),
        );
  });

  return out.take(maxTags).toList(growable: false);
}

bool _dedupe(List<CommitTag> existing, String label) {
  final low = label.toLowerCase();
  for (final t in existing) {
    if (t.label.toLowerCase() == low) return true;
  }
  return false;
}

/// Returns true only when scope and identity DON'T meaningfully match.
/// Tolerates substring overlap (`auth` vs `auth_v2`) and shared path
/// components (`ui` matches a file under `lib/ui-shell/`). Drift is a
/// real disagreement, not a string-equality miss.
bool _isDrift(String scope, String identity, List<CommitFileStatData>? files) {
  final s = scope.toLowerCase();
  final i = identity.toLowerCase();
  if (s == i) return false;
  if (s.contains(i) || i.contains(s)) return false;
  if (files != null) {
    for (final f in files) {
      final segs = f.path.toLowerCase().replaceAll('\\', '/').split('/');
      for (final seg in segs) {
        if (seg.contains(s) || s.contains(seg)) return false;
      }
    }
  }
  return true;
}
