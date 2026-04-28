import 'package:flutter/foundation.dart';

import '../backend/dtos.dart';

/// Which AI flow a record belongs to. Drives both routing inside
/// [AiActivityState] and the icon/colour the sidebar pill draws.
enum AiActivityKind {
  /// `generateCommitMessage` — composer assist. Result lands in the
  /// commit-message draft for the originating repo + branch.
  generate,

  /// `reviewCommit` — review of the staged/included file selection.
  review,

  /// `runMuse` — three-phase oracle on the included selection.
  muse,

  /// `runAsk` — shape/ask prose answer over the working tree.
  ask,
}

/// Runtime status of an [AiActivityRecord]. `done` and `error` are
/// terminal states; transitioning out of them happens by starting a
/// fresh run (which replaces the record).
enum AiActivityStatus { running, done, error }

/// Sentinel for [AiActivityRecord.copyWith] so callers can pass an
/// explicit `null` to clear a nullable field without it colliding
/// with "argument not provided" — `??` would treat both the same and
/// silently keep the prior value. Same pattern app_identity.dart uses
/// for its `tag` field.
const Object _kSentinel = Object();

/// Sealed result payload. Each kind carries the type the caller
/// returned from its backend so consumers don't have to dynamic-cast.
sealed class AiActivityResult {
  const AiActivityResult();
}

class AiGenerateResult extends AiActivityResult {
  /// The full commit message the model produced. Applied to the
  /// composer's draft on the originating repo when the user returns.
  final String message;
  const AiGenerateResult(this.message);
}

class AiReviewResult extends AiActivityResult {
  final AiCommitReviewData data;
  const AiReviewResult(this.data);
}

class AiMuseResult extends AiActivityResult {
  final AiMuseData data;
  const AiMuseResult(this.data);
}

class AiAskResult extends AiActivityResult {
  /// The model's prose answer.
  final String answer;
  const AiAskResult(this.answer);
}

/// One slot of AI activity, scoped to a (repo, kind) pair. The state
/// here intentionally does NOT include drawer-visibility flags
/// (`_reviewActive`, `_museActive`, etc.) — those are per-render UI
/// intent and stay on the page that owns them.
@immutable
class AiActivityRecord {
  final AiActivityKind kind;
  final AiActivityStatus status;

  /// Identifier for "what selection was this run made against." The
  /// page uses it to decide whether the persisted result still matches
  /// the user's current pick (else: render a stale-result hint or
  /// hide the affordance). Format is opaque to this layer — callers
  /// generate keys that round-trip through [identical] equality.
  final String? scopeKey;

  /// Free-form label for the [generate]/[ask] flows that benefit from
  /// echoing what the user prompted. The review/muse drawers source
  /// their headers from [result] instead.
  final String? scopeLabel;

  /// Typed payload, present iff [status] is [AiActivityStatus.done].
  final AiActivityResult? result;

  /// Provider error string, present iff [status] is
  /// [AiActivityStatus.error].
  final String? error;

  /// True once the user has acknowledged a terminal state (opened the
  /// drawer, dismissed the result, etc.). The sidebar pill only
  /// surfaces records that are running OR not-yet-seen.
  final bool seen;

  final DateTime startedAt;
  final DateTime? endedAt;

  const AiActivityRecord({
    required this.kind,
    required this.status,
    required this.startedAt,
    this.scopeKey,
    this.scopeLabel,
    this.result,
    this.error,
    this.seen = false,
    this.endedAt,
  });

  bool get isRunning => status == AiActivityStatus.running;
  bool get isDone => status == AiActivityStatus.done;
  bool get isError => status == AiActivityStatus.error;
  bool get isTerminal => isDone || isError;

  /// Sentinel-defaulted copy. Each nullable field can be left
  /// untouched (omit the argument), assigned a new value (pass it),
  /// or explicitly cleared (pass `null`). Required fields ([kind],
  /// [startedAt]) carry forward unchanged.
  AiActivityRecord copyWith({
    AiActivityStatus? status,
    Object? scopeKey = _kSentinel,
    Object? scopeLabel = _kSentinel,
    Object? result = _kSentinel,
    Object? error = _kSentinel,
    bool? seen,
    Object? endedAt = _kSentinel,
  }) =>
      AiActivityRecord(
        kind: kind,
        status: status ?? this.status,
        startedAt: startedAt,
        scopeKey: identical(scopeKey, _kSentinel)
            ? this.scopeKey
            : scopeKey as String?,
        scopeLabel: identical(scopeLabel, _kSentinel)
            ? this.scopeLabel
            : scopeLabel as String?,
        result: identical(result, _kSentinel)
            ? this.result
            : result as AiActivityResult?,
        error: identical(error, _kSentinel)
            ? this.error
            : error as String?,
        seen: seen ?? this.seen,
        endedAt: identical(endedAt, _kSentinel)
            ? this.endedAt
            : endedAt as DateTime?,
      );
}

/// Workspace-level home for AI activity state. Records are keyed by
/// repo path + [AiActivityKind] so a review on repo A and a muse on
/// repo B coexist without contention. State lives in memory only —
/// session-scoped, no on-disk persistence by design — so the user's
/// reset/quit / restart flow always lands on a clean slate.
///
/// Shape:
///   - At most one record per (repo, kind). Starting a new run on the
///     same slot replaces whatever was there (running runs are
///     orphaned in the backend; their late results are dropped via
///     the scope-key check).
///   - `start` → `complete` is the happy path. `cancel`/`clear` are
///     escape hatches for explicit user actions ("dismiss this
///     result"). The session lifetime guarantees we never accumulate
///     stale records past a process restart.
class AiActivityState extends ChangeNotifier {
  final Map<String, Map<AiActivityKind, AiActivityRecord>> _records = {};

  /// Per-repo cache for [activeFor]. The list returned by `activeFor`
  /// must compare equal across calls until that repo's slice actually
  /// changes — otherwise `context.select<AiActivityState,
  /// List<AiActivityRecord>>(...)` sees a fresh List each call and
  /// rebuilds the consumer on every notification, regardless of which
  /// repo mutated. We invalidate this cache (drop the entry) inside
  /// every mutation method below before `notifyListeners`, so the
  /// next read materialises a fresh list ONLY for the affected repo.
  /// Other repos' cached lists keep referential identity, so their
  /// selectors don't fire.
  final Map<String, List<AiActivityRecord>> _activeCache = {};

  AiActivityRecord? recordFor(String repoPath, AiActivityKind kind) {
    return _records[repoPath]?[kind];
  }

  /// Snapshot of every kind's record for [repoPath]. Returns an empty
  /// (unmodifiable) map when no activity exists, so consumers can
  /// iterate without null checks.
  Map<AiActivityKind, AiActivityRecord> recordsFor(String repoPath) {
    final m = _records[repoPath];
    if (m == null) return const {};
    return Map.unmodifiable(m);
  }

  /// Records the sidebar pill should surface — running, or terminal
  /// but not yet acknowledged. Intentionally drops `seen` records so
  /// the badge area stays empty after the user has read the result.
  ///
  /// Returns the same `List` instance until this repo's slice
  /// changes. See [_activeCache] for why that matters for `select`
  /// narrowing.
  List<AiActivityRecord> activeFor(String repoPath) {
    final cached = _activeCache[repoPath];
    if (cached != null) return cached;
    final m = _records[repoPath];
    if (m == null || m.isEmpty) {
      _activeCache[repoPath] = const [];
      return const [];
    }
    final list = <AiActivityRecord>[];
    for (final r in m.values) {
      if (r.isRunning || (r.isTerminal && !r.seen)) list.add(r);
    }
    final stable = List<AiActivityRecord>.unmodifiable(list);
    _activeCache[repoPath] = stable;
    return stable;
  }

  /// Mark a (repo, kind) slot as running. Replaces any prior record
  /// — starting a new run is the user's signal to forget the old one.
  void start({
    required String repoPath,
    required AiActivityKind kind,
    String? scopeKey,
    String? scopeLabel,
  }) {
    final slot = _records.putIfAbsent(repoPath, () => {});
    slot[kind] = AiActivityRecord(
      kind: kind,
      status: AiActivityStatus.running,
      scopeKey: scopeKey,
      scopeLabel: scopeLabel,
      startedAt: DateTime.now(),
    );
    _activeCache.remove(repoPath);
    notifyListeners();
  }

  /// Land a successful run. The [scopeKey] check protects against a
  /// late result arriving after the user moved on (started a new run
  /// in the same slot, dismissed the slot, etc.) — silently dropped.
  void complete({
    required String repoPath,
    required AiActivityKind kind,
    required AiActivityResult result,
    String? scopeKey,
  }) {
    final existing = _records[repoPath]?[kind];
    if (existing == null) return;
    if (existing.scopeKey != scopeKey) return;
    if (!existing.isRunning) return;
    _records[repoPath]![kind] = existing.copyWith(
      status: AiActivityStatus.done,
      result: result,
      endedAt: DateTime.now(),
      seen: false,
    );
    _activeCache.remove(repoPath);
    notifyListeners();
  }

  /// Land a failed run. Same scope-key gate as [complete].
  void fail({
    required String repoPath,
    required AiActivityKind kind,
    required String error,
    String? scopeKey,
  }) {
    final existing = _records[repoPath]?[kind];
    if (existing == null) return;
    if (existing.scopeKey != scopeKey) return;
    if (!existing.isRunning) return;
    _records[repoPath]![kind] = existing.copyWith(
      status: AiActivityStatus.error,
      error: error,
      endedAt: DateTime.now(),
      seen: false,
    );
    _activeCache.remove(repoPath);
    notifyListeners();
  }

  /// User opened the drawer / read the result — drop the unread mark
  /// so the sidebar pill stops surfacing it.
  void markSeen({required String repoPath, required AiActivityKind kind}) {
    final r = _records[repoPath]?[kind];
    if (r == null || r.seen) return;
    _records[repoPath]![kind] = r.copyWith(seen: true);
    _activeCache.remove(repoPath);
    notifyListeners();
  }

  /// Drop the slot entirely (user explicitly dismissed). Used by the
  /// generate flow's "cancel" affordance and the drawer close-buttons
  /// when the user wants the result forgotten rather than just
  /// hidden.
  void clear({required String repoPath, required AiActivityKind kind}) {
    final slot = _records[repoPath];
    if (slot == null) return;
    if (slot.remove(kind) == null) return;
    if (slot.isEmpty) _records.remove(repoPath);
    _activeCache.remove(repoPath);
    notifyListeners();
  }

  /// Drop every record for [repoPath]. Reserved for the factory-reset
  /// flow; ordinary repo switches keep records around so the user can
  /// return to in-flight or unread runs.
  ///
  /// `notifyListeners` only fires when records actually existed —
  /// dropping a cache-only entry (the canonical empty list memoised
  /// after a no-op `activeFor` query on a record-less repo) carries
  /// no observable change for any consumer, so signalling it would
  /// be a wasted page rebuild.
  void clearRepo(String repoPath) {
    final hadRecords = _records.remove(repoPath) != null;
    _activeCache.remove(repoPath);
    if (hadRecords) notifyListeners();
  }
}
