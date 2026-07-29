// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_currency_test.dart — the two scopes, and why there are two.
//
// This mechanism existed inside the branches page as a bare int and a
// map, hand-checked at nine call sites, and it was wrong at six of them
// for a while. Every one of those bugs is a single assertion here.
//
//  N1  a fresh claim is current.
//  N2  invalidateDesk stales THAT desk and nothing else. This is the
//      one that matters: using the page-wide bump for a per-desk swap
//      discarded every other desk's in-flight reload, so an unrelated
//      pane loaded its data and never re-rendered.
//  N3  invalidateAll stales every desk, including ones never claimed.
//  N4  a page-wide claim survives desk invalidation and dies with
//      invalidateAll — the row-summary sweep reads every desk, so only
//      the wide scope can mean anything to it.
//  N5  claims are independent objects: re-claiming after invalidation
//      gives a live claim while the old one stays dead, which is what
//      lets a load that IS the new work carry the new claim.
//  N6  invalidateAll forgets its bookkeeping rather than growing a
//      per-desk entry forever.
//
// A load also HOLDS its desk, because exclusion and currency were the
// same fact tracked twice — a token map beside the generations, updated
// by hand at every site that touched either:
//
//  N7  one load per desk, and desks do not block each other.
//  N8  ending frees the slot, and a load that already lost it cannot
//      free the live one's — the steal that would let two run at once.
//  N9  renewing stales every other claim on the desk while keeping the
//      slot and handing back a live claim, because the renewing load IS
//      the new work.
//  N10 a repo switch frees every slot. A slot nobody will release is a
//      desk that never loads again.
//  N11 a load that lost its slot cannot renew its way back in.
//  N12 an outside invalidation does not strand the slot. Gating the
//      release on the generation instead of on identity is exactly how
//      the old mechanism left sibling desks loading forever.
//  N13 renewing does not open a door: a second load is still refused
//      mid-renewal, and the renewing load can still end the slot it
//      never gave up. Renewal replaces the desk's generation, which is
//      the state a second load would have to observe to slip in.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/review/review_currency.dart';

void main() {
  test('N1: a fresh claim is current', () {
    final c = ReviewCurrency();
    expect(c.claim(7).isCurrent, isTrue);
  });

  test('N2: invalidateDesk stales that desk alone', () {
    final c = ReviewCurrency();
    final seven = c.claim(7);
    final nine = c.claim(9);

    c.invalidateDesk(7);

    expect(seven.isCurrent, isFalse,
        reason: 'the swapped desk\'s in-flight work is stale');
    expect(nine.isCurrent, isTrue,
        reason: 'desk 9 was never touched — discarding its result is the '
            'bug this scope exists to prevent');
  });

  test('N3: invalidateAll stales everything', () {
    final c = ReviewCurrency();
    final seven = c.claim(7);
    final nine = c.claim(9);

    c.invalidateAll();

    expect(seven.isCurrent, isFalse);
    expect(nine.isCurrent, isFalse);
    // A desk claimed only AFTER the invalidation is live again: the
    // repo switch invalidated outstanding work, not the future.
    expect(c.claim(9).isCurrent, isTrue);
  });

  test('N4: a page-wide claim answers only to invalidateAll', () {
    final c = ReviewCurrency();
    final sweep = c.claimPageWide();

    c.invalidateDesk(7);
    expect(sweep.isCurrent, isTrue,
        reason: 'the sweep spans every desk; one desk swapping does not '
            'make its reading wrong');

    c.invalidateAll();
    expect(sweep.isCurrent, isFalse,
        reason: 'but a repo switch does');
  });

  test('N5: a re-claim is live while the old claim stays dead', () {
    final c = ReviewCurrency();
    final before = c.claim(7);
    c.invalidateDesk(7);
    final after = c.claim(7);

    expect(before.isCurrent, isFalse);
    expect(after.isCurrent, isTrue,
        reason: 'the load that CAUSED the swap is the new work and must '
            'not invalidate itself');
  });

  test('N7: one load per desk, and desks do not block each other', () {
    final c = ReviewCurrency();
    final first = c.beginLoad(7);
    expect(first, isNotNull);
    expect(c.beginLoad(7), isNull,
        reason: 'two loads publishing the same desk would race');
    expect(c.beginLoad(9), isNotNull,
        reason: 'desk 9 has nothing to do with desk 7');
  });

  test('N8: a load that lost its slot cannot free the live one', () {
    final c = ReviewCurrency();
    final stale = c.beginLoad(7)!;
    c.invalidateAll();
    final live = c.beginLoad(7)!;

    stale.end();
    expect(live.holdsSlot, isTrue,
        reason: 'the stale load must not free a slot it no longer owns');
    expect(c.beginLoad(7), isNull);

    live.end();
    expect(c.loadsInFlight, 0);
    expect(c.beginLoad(7), isNotNull, reason: 'and a proper end frees it');
  });

  test('N9: renewing keeps the slot and hands back a live claim', () {
    final c = ReviewCurrency();
    final inFlight = c.claim(7);
    final load = c.beginLoad(7)!;

    load.renew();

    expect(inFlight.isCurrent, isFalse,
        reason: 'the reload holding the OLD session is now wrong');
    expect(load.claim.isCurrent, isTrue,
        reason: 'the renewing load is the NEW work — it must not '
            'invalidate itself');
    expect(load.holdsSlot, isTrue);
  });

  test('N10: a repo switch frees every slot', () {
    final c = ReviewCurrency();
    c.beginLoad(7);
    c.beginLoad(9);
    expect(c.loadsInFlight, 2);

    c.invalidateAll();

    expect(c.loadsInFlight, 0);
    expect(c.beginLoad(7), isNotNull,
        reason: 'the new repo\'s desk 7 must be able to load');
  });

  test('N11: a load that lost its slot cannot renew its way back', () {
    final c = ReviewCurrency();
    final stale = c.beginLoad(7)!;
    c.invalidateAll();
    final live = c.beginLoad(7)!;

    stale.renew();

    expect(stale.holdsSlot, isFalse);
    expect(stale.claim.isCurrent, isFalse,
        reason: 'its next check has to send it home');
    expect(live.holdsSlot, isTrue);
    expect(live.claim.isCurrent, isTrue,
        reason: 'and the live load is untouched by the ghost');
  });

  test('N12: an outside invalidation does not strand the slot', () {
    final c = ReviewCurrency();
    final load = c.beginLoad(7)!;

    c.invalidateDesk(7);
    expect(load.claim.isCurrent, isFalse);

    load.end();
    expect(c.loadsInFlight, 0,
        reason: 'a load whose claim was staled from outside still owns '
            'its slot; refusing its release leaves the desk loading '
            'forever');
  });

  test('N13: renewing keeps others out and still ends cleanly', () {
    final c = ReviewCurrency();
    final load = c.beginLoad(7)!;

    load.renew();

    expect(c.beginLoad(7), isNull,
        reason: 'the renewal replaced the generation, not the slot');
    expect(load.holdsSlot, isTrue);

    // A second renewal is the same story: the desk stays held and the
    // load keeps a live claim to write back with.
    load.renew();
    expect(c.beginLoad(7), isNull);
    expect(load.claim.isCurrent, isTrue);

    load.end();
    expect(c.loadsInFlight, 0);
    final next = c.beginLoad(7);
    expect(next, isNotNull,
        reason: 'the load that renewed is still the one that owns the '
            'release');
    expect(next!.claim.isCurrent, isTrue);
  });

  test('N6: invalidateAll forgets its per-desk bookkeeping', () {
    final c = ReviewCurrency();
    c.claim(1);
    c.claim(2);
    c.claim(3);
    expect(c.trackedDesks, 3);

    c.invalidateAll();
    expect(c.trackedDesks, 0,
        reason: 'a repo switch discards the old repo\'s desks entirely; '
            'keeping them would grow the map for the life of the app');
  });
}
