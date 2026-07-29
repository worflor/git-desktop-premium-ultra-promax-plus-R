// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_session.dart — everything one desk's open review holds.
//
// THE OBJECT NINE MAPS WERE IMPERSONATING. The branches page kept the
// controller, the loaded data, the reviewed ticks, the compose anchor,
// the lens posture, the lens diff, the lens's wanted spec, the compare
// pair and the marks memo as NINE separate collections keyed by deskId.
// Parallel maps keyed by one id are a missing object, and the bill came
// due as a family of bugs that all had the same shape — two of the maps
// disagreeing:
//
//   * first open refreshed `data` but not the ticks, so every file read
//     as unreviewed until the user happened to press something else;
//   * three verbs refreshed the collapsed row's badge and the other
//     nine did not, so the list told you it was someone else's turn;
//   * a gutter tap wrote `data` directly with no reload and no setState,
//     so the header kept rendering the pre-review state;
//   * a blob read that resolved after a repo switch seeded the compose
//     anchor of a DIFFERENT repository's desk with the same number.
//
// Each was fixed where it was found. That is symptom work: nothing
// stopped the tenth verb from forgetting the tenth map. Here the derived
// values live beside the thing they are derived from and move in ONE
// step ([reload]), so "the ticks lag the data" is not a bug to catch, it
// is a state that cannot be written down.
//
// The session owns no BuildContext, shows no errors, AND CALLS NOTHING
// BACK. It returns what happened and exposes what it holds; the page
// reads it and decides. That last part is not tidiness — it is what
// makes a whole bug class unrepresentable.
//
// This class briefly took an `onLensFiles` callback so it could tell the
// page to reconcile its active file when a lens changed the visible set.
// Desk ids are per-repo sequentials, so #7 exists in every repository: a
// lens fetch still in flight when the user switched repos would land and
// mutate the NEW repo's selection. An epoch check at the CALL SITE
// cannot stop that, because the mutation happens inside the callback
// before the caller resumes — so the guard has to be somewhere, and
// "somewhere" was a retired flag tested at six separate returns.
//
// Deleting the callback deletes the problem instead of guarding it. A
// result that lands late now writes only to a session object the page
// has already dropped, where nothing reads it. The page reconciles from
// [lens] after its own epoch check, which it was already doing.

import 'dart:async';

import '../diff/diff_models.dart' show DiffLineMark;
import 'review_adapter.dart';
import 'review_pane.dart' show buildLineMarks;
import 'review_pane_controller.dart';

/// Which lens the viewer has asked for, if any.
///
/// ONE field, not two booleans that must never both be true. "since your
/// last look" and "compare R2..R4" are alternatives, and holding them as
/// a flag plus a nullable pair made mutual exclusivity something every
/// caller had to remember — each setter clearing the other by hand, and
/// nothing catching the caller who forgot. A sealed posture makes the
/// contradictory state impossible to write down rather than merely
/// impolite.
sealed class ReviewLensPosture {
  const ReviewLensPosture();
}

/// Everything that changed since the viewer's last-look pointer.
class SinceLastLook extends ReviewLensPosture {
  const SinceLastLook();
}

/// A round-to-round snapshot comparison.
class CompareRounds extends ReviewLensPosture {
  final int from;
  final int to;
  const CompareRounds(this.from, this.to);
}

/// Why a reload did not fully succeed. The page maps these to strings;
/// the session never holds one.
enum ReviewReloadFault {
  /// The state doc could not be read (corrupt, or a peer's newer schema
  /// the store refuses to rewrite). The pane is now stale, not wrong.
  loadFailed,

  /// The lens could not be built and has been stood down.
  lensFailed,

  /// The lens was refused as too large; the full diff still stands.
  lensTooLarge,
}

/// The result of one atomic refresh.
class ReviewReloadResult {
  final ReviewReloadFault? fault;

  /// Provider/git detail for [ReviewReloadFault.loadFailed] and
  /// [ReviewReloadFault.lensFailed].
  final String? detail;

  const ReviewReloadResult.ok() : fault = null, detail = null;
  const ReviewReloadResult.failed(this.fault, [this.detail]);

  bool get isOk => fault == null;
}

/// One desk's live review: the controller, plus every value derived from
/// it, refreshed together.
class ReviewSession {
  ReviewSession({required this.controller});

  final ReviewPaneController controller;

  ReviewPaneData? data;

  /// Files the viewer has ticked AT THEIR CURRENT CONTENT. Recomputed by
  /// [reload], never remembered, which is what makes the author's next
  /// edit clear a tick on every clone with nobody clearing it.
  Set<String> reviewedFiles = const {};

  /// Where an opener composer is open: (path, oldSide, line).
  (String, bool, int)? composeAt;

  /// Which lens the viewer asked for, or null for the full diff.
  ReviewLensPosture? posture;

  /// Reading conveniences over [posture] for the surfaces, which want
  /// the two cases separately.
  bool get lensSince => posture is SinceLastLook;
  (int, int)? get compare => switch (posture) {
    CompareRounds(:final from, :final to) => (from, to),
    _ => null,
  };

  /// The materialized lens, when one is installed.
  ReviewLensDiff? lens;

  /// True while [reload] is running, so the page can refuse to stack
  /// loads on one desk.
  bool loading = false;

  /// True while a LENS fetch is in flight.
  ///
  /// Separate from [loading] on purpose: the two lens entry points
  /// (toggling "since your last look", picking a compare pair) apply a
  /// lens WITHOUT a full reload, so a busy signal derived from [loading]
  /// would go dark during exactly the fetch the user is waiting on, on
  /// exactly the large diffs where it takes long enough to notice.
  bool get lensLoading => _lensLoading;

  bool _lensLoading = false;

  /// The in-flight lens fetch, so a caller that coalesces into it awaits
  /// the real outcome instead of a courtesy "ok" for work that has not
  /// happened yet.
  Completer<ReviewReloadResult>? _lensRun;
  (ReviewViewBundle, String, bool, List<DiffLineMark>)? _marksMemo;

  /// Serializes reloads on this desk. Two verbs pressed quickly must not
  /// put two traversals over the same derived state in flight — the
  /// slower one would land last carrying the older snapshot.
  Future<void> _gate = Future<void>.value();

  bool get hasLens => lens != null;
  bool get hasLensPosture => posture != null;

  /// Take over what the viewer was DOING from a session being retired.
  ///
  /// A session is bound to the branch its rounds are cut from and the
  /// identity its writes are signed with, so a change to either replaces
  /// it — but where the viewer was reading is not part of that binding.
  /// Renaming yourself in settings closed an open composer and snapped a
  /// compare lens back to the full diff, for a swap the viewer never
  /// asked for and cannot see.
  ///
  /// Refuses across a branch change, which is the case where those
  /// values genuinely stop meaning anything: an anchor names a line in a
  /// diff that is no longer on screen, and a round pair names rounds the
  /// new branch's review may not have. Nothing DERIVED crosses either —
  /// data, ticks and the materialized lens belong to the old controller
  /// and are recomputed by the reload that follows.
  void adoptPostureFrom(ReviewSession retired) {
    if (retired.controller.headBranch != controller.headBranch) return;
    posture = retired.posture;
    composeAt = retired.composeAt;
  }

  /// Gutter marks, memoized on (bundle, path, side) identity.
  ///
  /// DiffShell caches its display-row map keyed on the marks LIST
  /// identity, so handing it a fresh list on every page rebuild would
  /// recompute an O(rows) mapping on every unrelated setState of a
  /// machine-scale diff.
  List<DiffLineMark> marksFor(
    ReviewViewBundle bundle,
    String path, {
    required bool includeOldSide,
  }) {
    final memo = _marksMemo;
    if (memo != null &&
        identical(memo.$1, bundle) &&
        memo.$2 == path &&
        memo.$3 == includeOldSide) {
      return memo.$4;
    }
    final marks = buildLineMarks(bundle, path, includeOldSide: includeOldSide);
    _marksMemo = (bundle, path, includeOldSide, marks);
    return marks;
  }

  /// Take the lens down and forget the posture that asked for it.
  void clearLens() {
    posture = null;
    lens = null;
  }

  /// Load the review AND every value derived from it, as one step.
  ///
  /// This is the whole point of the class. The page used to call load,
  /// then remember to refresh ticks, then remember to refresh the lens,
  /// then remember to refresh the row badge — and the set of verbs that
  /// remembered all four was never the set of verbs that changed all
  /// four.
  Future<ReviewReloadResult> reload() {
    final prior = _gate;
    final mine = Completer<void>();
    _gate = mine.future;
    return prior.then((_) => _reload()).whenComplete(mine.complete);
  }

  Future<ReviewReloadResult> _reload() async {
    loading = true;
    try {
      final r = await controller.load();
      if (!r.ok) {
        // The write may well have landed and only the read back failed,
        // so the pane is stale rather than wrong. Say which.
        return ReviewReloadResult.failed(ReviewReloadFault.loadFailed, r.error);
      }
      data = r.data;
      await _refreshTicks();
      // The lens is derived from review state, so it moves when that
      // state does. Publishing advances the last-look pointer, which is
      // exactly the moment "since your last look" becomes nothing — a
      // lens left standing would keep showing the old delta under a
      // label that is no longer true.
      return await refreshLens();
    } finally {
      loading = false;
    }
  }

  Future<void> _refreshTicks() async {
    final d = data;
    if (d == null) {
      reviewedFiles = const {};
      return;
    }
    final paths = {for (final g in d.bundle.groups) g.filePath};
    if (paths.isEmpty) {
      reviewedFiles = const {};
      return;
    }
    reviewedFiles = await controller.reviewedNow(paths);
  }

  /// The spec the CURRENT posture asks for, or null for the full diff.
  ///
  /// Exhaustive over the posture: a new lens kind cannot be added
  /// without the compiler pointing here.
  String? get _wantedSpec => switch (posture) {
    null => null,
    SinceLastLook() => controller.sinceLastLookSpec,
    CompareRounds(:final from, :final to) => controller.compareSpec(from, to),
  };

  /// Bring the lens in line with whatever [posture] currently says.
  ///
  /// Takes NO spec. It used to, and that was the window: a caller
  /// computed a spec from the posture, awaited, then installed it — so a
  /// `clearLens()` landing in between produced a lens with no posture,
  /// showing content the viewer had explicitly dismissed. Re-reading the
  /// posture on every pass, INCLUDING after the await, makes the lens a
  /// function of the posture rather than of whatever was true when
  /// somebody started asking.
  ///
  /// COALESCES rather than drops: a caller arriving mid-fetch awaits the
  /// fetch it joined, so a user spinning the round picker ends on the
  /// posture they last chose rather than on whichever fetch happened to
  /// finish last.
  ///
  /// Deliberately NOT behind [reload]'s gate: a reload calls this from
  /// inside that gate, so taking it again would deadlock. The coalescing
  /// here is the right guard for this job anyway — the gate exists to
  /// make each traversal run alone, which is a different need.
  Future<ReviewReloadResult> refreshLens() async {
    // A caller that arrives mid-fetch waits for the fetch it coalesced
    // into rather than being told "ok" for work that has not happened.
    // Reporting success early is how a page ends up calling setState
    // before the lens it is about to draw exists.
    final running = _lensRun;
    if (running != null) return running.future;
    final mine = Completer<ReviewReloadResult>();
    _lensRun = mine;
    _lensLoading = true;
    try {
      final r = await _refreshLensBody();
      mine.complete(r);
      return r;
    } catch (e) {
      // Complete with a FAILURE rather than an error: this method's
      // contract is a result, and an errored completer that nobody
      // awaited (the common case — coalesced callers may all have
      // returned) surfaces as an unhandled-exception warning for a
      // failure the caller already handled.
      final failed = ReviewReloadResult.failed(
        ReviewReloadFault.lensFailed,
        '$e',
      );
      mine.complete(failed);
      return failed;
    } finally {
      _lensLoading = false;
      _lensRun = null;
    }
  }

  Future<ReviewReloadResult> _refreshLensBody() async {
    while (true) {
      final want = _wantedSpec;
      if (want == null) {
        // No posture, or a posture whose pins have gone: the full diff
        // stands and any lens still installed comes down.
        if (lens != null || posture != null) clearLens();
        return const ReviewReloadResult.ok();
      }
      if (lens?.spec == want) return const ReviewReloadResult.ok();
      final r = await controller.loadLens(want);
      // Re-read the POSTURE, never a captured spec: it may have been
      // dismissed or switched while this fetch was in flight.
      if (_wantedSpec != want) continue;
      if (!r.ok) {
        clearLens();
        return ReviewReloadResult.failed(ReviewReloadFault.lensFailed, r.error);
      }
      final got = r.data;
      if (got == null) {
        // Refused as too large: say so and stay on the full diff
        // rather than pretending the toggle did nothing.
        clearLens();
        return const ReviewReloadResult.failed(ReviewReloadFault.lensTooLarge);
      }
      lens = got;
      return const ReviewReloadResult.ok();
    }
  }
}
