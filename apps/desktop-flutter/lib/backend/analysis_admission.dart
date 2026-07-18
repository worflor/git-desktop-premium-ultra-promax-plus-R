// analysis_admission.dart — the single authority over how much working-tree /
// diff content Manifold's analysis pipelines may hold in memory at once.
//
// WHY THIS EXISTS. Manifold has many pipelines that ingest file or diff
// content (flow analysis, spectral embedding, correlatedness seriation, AI
// context, diff rendering). Each used to invent its own resource policy at
// its own call site — a 16KB cap here, 256KB there, 1MB elsewhere — and the
// two pipelines that forgot to invent one (flow analysis, the correlatedness
// diff fetch) read entire multi-hundred-MB data files into RAM, eight at a
// time, and took the whole machine down (the marble repo-switch OOM). The
// bug class is UNBUDGETED INGESTION; scattering more per-site caps just
// re-arms it for the next pipeline someone writes.
//
// THE MODEL. One process-wide byte budget for in-flight analysis content
// ([AnalysisAdmission.totalBudget]) and one primitive:
//
//   admission.run(expectedResidentBytes, () => work)
//
// which admits work while the in-flight sum fits, QUEUES it (FIFO) while it
// doesn't, and DECLINES it (returns [AdmissionDecision.declined]) only when
// the declared size alone exceeds the whole budget — i.e. when no schedule
// could ever make it safe. Concurrency limits stay where they are; this
// bounds BYTES, the axis that actually kills the machine. Fan-out of any
// width over any repo becomes memory-safe by construction, while a single
// legitimately large source file still analyzes — just not eight at once.
//
// DECLARE RESIDENT COST, NOT INPUT SIZE. What the budget must see is the
// peak memory the admitted work will actually hold: input × the pipeline's
// measured expansion factor (parsing, graph construction, walker state).
// Declaring bare input size was measured wrong by tool/memory_lab.dart —
// one "48MB" admission cost ~1GB resident inside flow analysis. Each caller
// owns a measured factor next to its call site (see logos_flow.dart's
// _kFlowResidentExpansion); the memory lab's lifecycle gates keep those
// factors honest.
//
// EPOCHS. Analysis is always on behalf of some scope (the active repo).
// [AdmissionScope] snapshots an epoch; bumping the epoch (repo switch) drops
// that scope's QUEUED work before it reads a byte. Work already running is
// not interrupted (it is budget-bounded, so letting it drain is safe); the
// point is that a switch stops the *pile-up*, which is exactly what stacked
// old-repo + new-repo pipelines at switch time.
//
// The budget value is physics, not preference: it bounds peak analysis
// residency to a fixed slice comfortably inside any machine Manifold
// targets, and admission-side accounting means the WORST case (every
// admitted read fully resident simultaneously, plus per-pipeline expansion
// factors) stays in the hundreds of MB, never GBs.

import 'dart:async';
import 'dart:collection';

/// Why admitted work never ran.
enum AdmissionDecision {
  /// Ran to completion (result available).
  ran,

  /// Declared size alone exceeds the entire budget — no schedule could ever
  /// admit it. The caller should degrade (skip, sample, or use a bounded
  /// representation) rather than retry.
  declined,

  /// The scope's epoch was bumped (repo switch) while the work was still
  /// queued. The caller should simply drop the task — its subject is gone.
  superseded,
}

/// Result envelope: [decision] says what happened; [value] is set iff
/// [decision] == [AdmissionDecision.ran].
class Admitted<T> {
  final AdmissionDecision decision;
  final T? value;
  const Admitted._(this.decision, this.value);
  const Admitted.declined() : this._(AdmissionDecision.declined, null);
  const Admitted.superseded() : this._(AdmissionDecision.superseded, null);
  const Admitted.ran(T v) : this._(AdmissionDecision.ran, v);
  bool get ran => decision == AdmissionDecision.ran;
}

class _Waiter {
  final int bytes;
  final int epochAtEnqueue;
  final AdmissionScope? scope;
  final Completer<void> gate = Completer<void>();
  _Waiter(this.bytes, this.epochAtEnqueue, this.scope);

  bool get superseded => scope != null && scope!.epoch != epochAtEnqueue;
}

/// Process-wide in-flight byte accountant for analysis content. See the
/// file-level comment for the model.
class AnalysisAdmission {
  /// Peak bytes of analysis content admitted simultaneously. 64MB of raw
  /// content: with per-pipeline expansion (UTF-16 strings, graphs, parsed
  /// structures measured at ~3–6× input across the codebase's pipelines)
  /// worst-case analysis residency stays a few hundred MB — a safe fixed
  /// slice of the smallest machines Manifold runs on, with no behavioral
  /// difference at all for human-scale repos (whose whole change-sets fit
  /// in one admission).
  static const int kDefaultBudgetBytes = 64 * 1024 * 1024;

  final int totalBudget;
  int _inFlight = 0;
  final Queue<_Waiter> _queue = Queue<_Waiter>();

  AnalysisAdmission({this.totalBudget = kDefaultBudgetBytes});

  /// The shared instance every pipeline routes through. Tests may construct
  /// their own to exercise queueing deterministically.
  static final AnalysisAdmission instance = AnalysisAdmission();

  /// Bytes currently admitted (visible for diagnostics/tests).
  int get inFlightBytes => _inFlight;

  /// Queued tasks (visible for diagnostics/tests).
  int get queuedCount => _queue.length;

  /// Admit [bytes] worth of content work. Runs [work] when the budget allows,
  /// queuing (FIFO) behind other admitted work when it doesn't. Declines
  /// without running when [bytes] alone can never fit. If [scope] is given
  /// and its epoch is bumped while queued, the task is dropped as
  /// superseded before doing any work.
  Future<Admitted<T>> run<T>(
    int bytes,
    Future<T> Function() work, {
    AdmissionScope? scope,
  }) async {
    if (bytes > totalBudget) return const Admitted.declined();
    if (scope != null && !scope.alive) return const Admitted.superseded();

    // Strictly FIFO: a task also queues while ANYONE is queued ahead of it,
    // even if it would fit the residual budget right now. Letting small
    // tasks lane-split past a queued large one starves it indefinitely on a
    // busy pipeline — the residual never grows while small work keeps
    // slipping through.
    if (_queue.isNotEmpty || _inFlight + bytes > totalBudget) {
      final waiter = _Waiter(bytes, scope?.epoch ?? 0, scope);
      _queue.add(waiter);
      await waiter.gate.future;
      if (waiter.superseded) {
        // Our slot was granted but the scope died while queued: release the
        // reservation the granter made on our behalf and hand it onward.
        _inFlight -= bytes;
        _drainQueue();
        return const Admitted.superseded();
      }
    } else {
      _inFlight += bytes;
    }

    try {
      return Admitted.ran(await work());
    } finally {
      _inFlight -= bytes;
      _drainQueue();
    }
  }

  void _drainQueue() {
    while (_queue.isNotEmpty) {
      final head = _queue.first;
      // Superseded waiters are granted uniformly (reserve + complete); their
      // own continuation observes the dead scope, releases the reservation
      // immediately, and re-drains — one code path, no special accounting.
      if (_inFlight + head.bytes > totalBudget) return;
      _queue.removeFirst();
      _inFlight += head.bytes;
      head.gate.complete();
    }
  }
}

/// A cancellation scope for queued admissions, bound to "the analysis
/// subject" (in practice: the active repository). Bump the epoch when the
/// subject changes; queued-but-not-started work for the old epoch is dropped.
class AdmissionScope {
  int _epoch = 0;
  bool _alive = true;

  int get epoch => _epoch;
  bool get alive => _alive;

  /// The subject changed (repo switch): everything queued under the old
  /// epoch is now pointless. Already-running work drains under the budget.
  void bump() => _epoch++;

  /// The subject is gone entirely (page/app teardown).
  void close() => _alive = false;
}

/// The one scope every repo-scoped analysis queues under. The app layer
/// bumps it from `RepositoryState.setActivePath` — switching repos drops all
/// analysis still QUEUED for the previous repo before it touches a byte,
/// which is what used to stack old-repo reads on top of the new repo's
/// pipeline spin-up at exactly the moment the machine could least afford it.
final AdmissionScope repoAnalysisScope = AdmissionScope();
