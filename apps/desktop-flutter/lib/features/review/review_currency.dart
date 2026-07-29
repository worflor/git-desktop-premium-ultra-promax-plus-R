// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_currency.dart — may I still write this result back?
//
// Every async review path asks that one question after its await, and
// for a long time each answered it by hand: capture `_reviewEpoch`,
// await, compare. One dimension, eight call sites. When a second
// dimension appeared — a per-desk generation, because a branch rename or
// an identity change replaces ONE desk's session rather than all of them
// — six of those nine checks silently kept testing only the first. Two
// were right. The rest let stale results through, and each was found one
// review at a time.
//
// So currency is one question with one answer object. A caller CLAIMS
// before the await and asks the claim afterwards; adding a third
// dimension later changes this file rather than starting another
// call-site hunt.
//
// Deliberately free of Flutter: the page combines a claim with its own
// `mounted`, and keeping this a plain object is what lets the invalidation
// rules be tested directly instead of through a widget tree.

/// Tracks what is still wanted, at two scopes.
class ReviewCurrency {
  /// Bumped when EVERY desk's work becomes stale — a repo switch, where
  /// the controllers themselves belong to the old repository.
  int _epoch = 0;

  /// Per-desk tokens, replaced when that desk's session is swapped.
  final Map<int, Object> _generations = {};

  /// The load that currently holds each desk's slot, at most one.
  final Map<int, ReviewLoad> _loads = {};

  /// Invalidate every outstanding claim.
  void invalidateAll() {
    _epoch++;
    _generations.clear();
    // The slots go with them. A repo switch abandons every in-flight
    // load, and a slot nobody will ever release is a desk that never
    // loads again.
    _loads.clear();
  }

  /// Invalidate outstanding claims for [deskId] only.
  ///
  /// The narrow case exists because using the wide one for it was a
  /// bug: a rename on one desk discarded every other desk's in-flight
  /// reload, which loaded its data and then never re-rendered.
  void invalidateDesk(int deskId) {
    _generations[deskId] = Object();
  }

  Object _generationFor(int deskId) =>
      _generations.putIfAbsent(deskId, Object.new);

  /// Claim the right to write back one desk's async result. Take this
  /// BEFORE the await; ask [ReviewClaim.isCurrent] after it.
  ReviewClaim claim(int deskId) =>
      ReviewClaim._(this, deskId, _epoch, _generationFor(deskId));

  /// Claim work that belongs to no single desk — the row-summary sweep
  /// reads every desk at once, so only [invalidateAll] can stale it.
  /// It goes through the same object so there is one mechanism rather
  /// than a second, quietly-different counter beside it.
  ReviewClaim claimPageWide() => ReviewClaim._(this, null, _epoch, null);

  /// Begin the one load allowed to run for [deskId], or null when
  /// another already holds it.
  ///
  /// Exclusion and currency were two per-desk mechanisms — a token map
  /// for "am I the load that owns this desk" beside the generations for
  /// "may I still write back" — kept in step by hand at every site that
  /// touched either. They are one fact: the load that owns the desk is
  /// the load whose results are wanted. One object answers both, so
  /// they cannot drift apart.
  ReviewLoad? beginLoad(int deskId) {
    if (_loads.containsKey(deskId)) return null;
    final load = ReviewLoad._(this, deskId, claim(deskId));
    _loads[deskId] = load;
    return load;
  }

  /// Test-only view of how many desks are being tracked, so a test can
  /// assert that [invalidateAll] actually forgets them rather than
  /// merely making their claims stale.
  int get trackedDesks => _generations.length;

  /// Test-only view of how many desks have a load in flight.
  int get loadsInFlight => _loads.length;
}

/// One desk's in-flight load: its exclusive slot and the claim it
/// carries, which are the same thing held from two angles.
class ReviewLoad {
  ReviewLoad._(this._owner, this.deskId, this._claim);

  final ReviewCurrency _owner;
  final int deskId;
  ReviewClaim _claim;

  /// The claim to ask after each await. Replaced by [renew].
  ReviewClaim get claim => _claim;

  /// True while this load is still the desk's.
  bool get holdsSlot => identical(_owner._loads[deskId], this);

  /// Stale every OTHER claim on this desk, keeping the slot.
  ///
  /// For the load that itself replaced the desk's session: the work in
  /// flight elsewhere is now wrong, but this load is the new work and
  /// must not invalidate itself. A load that has already lost the slot
  /// changes nothing and keeps its stale claim, so its next check sends
  /// it home.
  void renew() {
    if (!holdsSlot) return;
    _owner.invalidateDesk(deskId);
    _claim = _owner.claim(deskId);
  }

  /// Free the slot, if it is still ours.
  ///
  /// Identity, not generation: a load whose claim was staled from
  /// outside still holds its slot, and refusing to let it release would
  /// leave the desk loading forever — which is exactly how the old
  /// epoch-gated release stranded every sibling desk on any swap.
  void end() {
    if (holdsSlot) _owner._loads.remove(deskId);
  }
}

/// One caller's claim on one desk's in-flight work.
class ReviewClaim {
  final ReviewCurrency _owner;

  /// The desk this claim covers, or null for a page-wide claim.
  final int? deskId;
  final int _epoch;
  final Object? _generation;

  ReviewClaim._(this._owner, this.deskId, this._epoch, this._generation);

  /// True while this result may still be written back.
  ///
  /// Both scopes, always. A claim taken before an `invalidateAll` is
  /// stale even if the desk was never touched, and a claim taken before
  /// its own desk's `invalidateDesk` is stale even though every other
  /// desk is fine.
  bool get isCurrent {
    if (_owner._epoch != _epoch) return false;
    final desk = deskId;
    if (desk == null) return true; // page-wide: only invalidateAll stales it
    return identical(_owner._generations[desk], _generation);
  }
}
