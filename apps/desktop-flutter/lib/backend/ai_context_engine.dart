// AI CONTEXT ENGINE — Logos-allocated, producer-driven context assembly
//
// The general-purpose primitive every AI flow assembles its prompt context
// through. Replaces ad-hoc hardcoded ratios (`0.20 × relevance`,
// `60000 char brainstorm budget`, `clamp(N/100, 0.1, 0.3) metadata`) with
// a producer registry whose share of the budget is derived from Logos
// signals — coherence, neighborhood yield, per-axis attribution, regime
// utility.
//
// One axis of generality (CALLERS):
//   reviewCommit, generateCommitMessage, runMuse, and any future flow
//   instantiate the engine with their chosen producer set. The engine
//   doesn't care who's asking; the producers don't care who composed them.
//
// Other axis of generality (PRODUCERS):
//   New producers (semantic search, refactor suggestions, blame
//   explanation) plug in by implementing [AiContextProducer]. They get
//   Logos-derived budget allocation for free.
//
// Budget allocation model:
//   Each producer declares an `urgency(state) → double` (variable pool)
//   OR a `fixedRequest(state) → int` (always-on, no competition). The
//   engine sums fixed requests, subtracts from total, and softmax-
//   normalises the urgencies across the variable pool. Urgencies must be
//   composed of Logos signals (no constants beyond model-API limits).
//
// Production:
//   All producers run in parallel under their allocated budget. Each
//   returns its body plus optional metadata (e.g. emission records for
//   the SSE feedback loop).

import 'dart:async';

import 'logos_git.dart'
    show
        AxisAttribution,
        LogosEvidenceQueryResult,
        LogosGit,
        RelevanceScore;
import 'logos_git_probe.dart' show DiffProbe;

// Inputs the engine passes around

/// Result of one Logos diffusion pass: the probe (its stats drive budget
/// allocation), the engine (for the tier knapsack), and the scored
/// neighborhood (φ field). One source of truth across producers — no
/// re-diffusion per section.
/// When [attribution] is non-null the diffusion was run per-axis, so
/// callers can answer "*why* did file X surface?" by reading
/// [AxisAttribution.dominantAxis] and [AxisAttribution.shareByAxis].
/// The combined φ in [scores] equals the elementwise sum of the
/// per-axis φ vectors (heat-kernel linearity), so the two views are
/// algebraically consistent.
class LogosDiffusionResult {
  const LogosDiffusionResult({
    required this.engine,
    required this.probe,
    required this.scores,
    required this.resolvedT,
    this.attribution,
    this.evidence,
  });
  final LogosGit engine;
  final DiffProbe probe;
  final List<RelevanceScore> scores;
  final double resolvedT;

  /// Per-axis attribution of the diffusion. Optional because some
  /// callers don't need the per-axis breakdown and would rather skip
  /// the ~4× diffusion cost. When present, [scores] is sourced from
  /// [AxisAttribution.combined].
  final AxisAttribution? attribution;
  final LogosEvidenceQueryResult? evidence;
}

/// Shared state every producer sees. Carries the seed inputs (repo +
/// diff) plus the pre-computed Logos diffusion (when available — it's
/// optional so engine-cold callers still work). Producers cast or
/// query as needed; they never re-run the diffusion themselves.
class AiContextRequest {
  const AiContextRequest({
    required this.repositoryPath,
    required this.diffText,
    this.logos,
  });
  final String repositoryPath;
  final String diffText;
  final LogosDiffusionResult? logos;
}

/// One producer's contribution to the assembled context.
/// Metadata is type-erased at the engine boundary (`Object?`) because
/// producers carry heterogeneous payloads. Callers should NOT do
/// `section.metadata as MyType?` — instead use [metadataOfType] which
/// performs a checked cast and returns null on type mismatch (vs. the
/// silent-wrong-value risk of an unchecked `as` when a producer
/// changes its metadata type).
class AiContextSection {
  const AiContextSection({
    required this.id,
    required this.body,
    this.metadata,
  });

  /// Stable identifier — used as map key by callers, and (later) by the
  /// SSE store to track per-producer citation utility per regime.
  final String id;

  /// Renderable text. Empty → caller should omit the section entirely.
  final String body;

  /// Optional producer-specific payload — e.g. the
  /// [LogosEmissionRecord] for the relevance section, so the caller can
  /// feed citations back into SSE after the AI responds. Access via
  /// [metadataOfType] for safe typed retrieval.
  final Object? metadata;

  /// Checked cast for typed metadata access. Returns the metadata cast
  /// to [T] when it's actually a [T] (or a subtype), else null. Use
  /// this instead of `metadata as T?` — if a producer ever switches
  /// its metadata type, the unchecked cast would silently return a
  /// wrong-typed value; this returns null and the caller can react.
  T? metadataOfType<T>() {
    final m = metadata;
    if (m is T) return m;
    return null;
  }
}

// The producer interface

/// Abstract contributor to an assembled AI prompt context. Implementors
/// fall into two budget modes (kept exclusive to keep allocation
/// arithmetic simple):
///   • Variable-pool — return non-null [urgency]; share of the
///     post-fixed budget is `urgency / Σ urgencies` (softmax-style
///     normalisation across the registered set).
///   • Fixed-request — return null [urgency] and a positive
///     [fixedRequest]; that exact char count is reserved before the
///     variable pool is computed. Use for cheap, naturally-bounded
///     sections like change_types or structural_verification.
abstract class AiContextProducer {
  const AiContextProducer();

  /// Stable identifier — also the XML wrapper tag the caller will use
  /// when stitching ([wrapperTag] defaults to this).
  String get id;

  /// Variable-pool urgency. Non-null → competes for the variable share.
  /// Must be derivable from the request's Logos signals; a null return
  /// means "I don't compete in this allocation."
  double? urgency(AiContextRequest req);

  /// Fixed-request char count. Non-zero → reserved up front, deducted
  /// from the total before urgencies are normalised. Use this for
  /// cheap always-on sections that have a natural data-bounded size.
  int fixedRequest(AiContextRequest req) => 0;

  /// Produce the section body within the allocated budget. Producers
  /// MUST honour [budgetChars] (the engine doesn't double-check).
  Future<AiContextSection> produce(AiContextRequest req, int budgetChars);

  /// Optional override for the XML wrapper tag the caller stitches with.
  /// Defaults to [id].
  String get wrapperTag => id;

  /// Display order in the stitched prompt body. Lower = earlier.
  /// Defaults to 100. Producers can override to control where their
  /// section appears (e.g. terse "frame" sections like change_types
  /// belong before the heavy file_context block).
  int get order => 100;
}

// The engine

/// A registered set of producers + the allocator that hands them their
/// budgets. Stateless past construction; a single engine instance can
/// serve many requests concurrently.
class AiContextEngine {
  const AiContextEngine(this.producers);
  final List<AiContextProducer> producers;

  /// Allocate budget to each producer using its declared urgency
  /// (variable pool) or fixed request, then run all producers in
  /// parallel. Returns a map keyed by producer id.
  /// [totalBudgetChars] is the post-overhead, post-output-reservation
  /// budget the caller has carved out for context. The engine treats
  /// it as a hard ceiling for the variable pool *plus* the sum of
  /// fixed requests; if fixed requests exceed it, variable producers
  /// receive zero budget but still run (they may emit a header-only
  /// or no-op section).
  Future<Map<String, AiContextSection>> assemble(
    AiContextRequest req,
    int totalBudgetChars,
  ) async {
    final fixedRequests = <String, int>{};
    var fixedSum = 0;
    for (final p in producers) {
      final fb = p.fixedRequest(req);
      if (fb > 0) {
        fixedRequests[p.id] = fb;
        fixedSum += fb;
      }
    }

    final urgencies = <String, double>{};
    var urgencySum = 0.0;
    for (final p in producers) {
      final u = p.urgency(req);
      if (u != null && u.isFinite && u > 0) {
        urgencies[p.id] = u;
        urgencySum += u;
      }
    }

    // Variable pool = whatever's left after fixed reservations.
    final variablePool = (totalBudgetChars - fixedSum).clamp(0, 1 << 30);
    final budgets = <String, int>{...fixedRequests};
    if (urgencySum > 0) {
      // Largest-remainder method (Hamilton apportionment): integer
      // divide each producer's exact share, then distribute the
      // leftover one char at a time to producers with the largest
      // fractional remainder. Eliminates the rounding loss that
      // naive `(pool * urg / sum).round()` introduces — three equal
      // urgencies on a 1000-char pool now sum to exactly 1000, not
      // 999. Deterministic ordering: largest remainder wins, then
      // producer id alphabetical (stable across runs of same input).
      final exact = <String, double>{};
      var allocated = 0;
      for (final entry in urgencies.entries) {
        final share = variablePool * entry.value / urgencySum;
        final floor = share.floor();
        budgets[entry.key] = floor;
        exact[entry.key] = share - floor;
        allocated += floor;
      }
      var leftover = variablePool - allocated;
      if (leftover > 0) {
        final order = exact.entries.toList()
          ..sort((a, b) {
            final byRem = b.value.compareTo(a.value);
            if (byRem != 0) return byRem;
            return a.key.compareTo(b.key);
          });
        for (final entry in order) {
          if (leftover <= 0) break;
          budgets[entry.key] = (budgets[entry.key] ?? 0) + 1;
          leftover -= 1;
        }
      }
    }
    // Producers with no urgency and no fixed request get zero budget.
    // They still get to produce — useful for "soft" producers that
    // emit a tiny static header even with no allocation.
    for (final p in producers) {
      budgets.putIfAbsent(p.id, () => 0);
    }

    final entries = await Future.wait(
      producers.map((p) async {
        final section = await p.produce(req, budgets[p.id]!);
        return MapEntry(p.id, section);
      }),
    );
    return Map.fromEntries(entries);
  }

  /// Convenience wrapper around [assemble] that ALSO stitches the
  /// non-empty sections into a single XML-tagged body in producer-
  /// declared `order`. Returns both the body and the section map (for
  /// callers that still need per-section metadata, e.g. the
  /// relevance_neighborhood emission record for SSE feedback).
  /// Empty bodies are silently dropped — a producer that returns ''
  /// emits no wrapper. Producers control their own [wrapperTag] and
  /// [order]; the caller no longer has to know either.
  /// This is the entry point most callers should use. The bare
  /// [assemble] is for advanced flows that want to compose section
  /// bodies into something other than XML-tagged concatenation.
  Future<({String body, Map<String, AiContextSection> sections})>
      assembleAndStitch(AiContextRequest req, int totalBudgetChars) async {
    final sections = await assemble(req, totalBudgetChars);
    final ordered = [...producers]..sort((a, b) => a.order.compareTo(b.order));
    final parts = <String>[];
    for (final p in ordered) {
      final s = sections[p.id];
      if (s == null || s.body.isEmpty) continue;
      parts.add('<${p.wrapperTag}>\n${s.body}</${p.wrapperTag}>');
    }
    return (body: parts.join('\n\n'), sections: sections);
  }
}
