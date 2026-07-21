// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Property-based tests for DeskPr's review-decision fold
// (_deriveReviewDecision, driven through the public toSummary() adapter).
//
// These complement the hand-written cases in
// desk_pr_review_decision_test.dart with ~300 seeded-random sequences per
// property. All PRNGs are seeded with FIXED literal ints so any failure is
// perfectly reproducible, and every assertion prints the generating
// sequence on failure via the `reason:` describer.
//
// The fold is pure Dart logic (no I/O, no temp repos), so the whole suite
// runs in well under a second.
//
// Contract under test (from desk_pr.dart's doc comment + implementation):
//   * Each reviewer's LATEST decisive verdict is the only one that counts.
//     Decisive = APPROVED | CHANGES_REQUESTED. COMMENTED and plain comments
//     are non-decisive and never mutate a reviewer's standing state.
//   * Recency = entry timestamp; on a timestamp TIE, later position in the
//     list wins (the thread is append-only, so position is chronological).
//   * Decision: any standing CHANGES_REQUESTED -> 'CHANGES_REQUESTED';
//     else any standing APPROVED -> 'APPROVED'; else '' (neutral).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr.dart';

// ---------------------------------------------------------------------------
// Construction helpers (mirror the sibling hand-written test's API).
// ---------------------------------------------------------------------------

/// Base timestamp; per-entry times are offset from this by whole minutes so
/// distinct offsets give strictly-ordered, unique instants.
final DateTime _epoch = DateTime.utc(2026, 1, 1, 9);
DateTime _ts(int minute) => _epoch.add(Duration(minutes: minute));

DeskThreadEntry _entry(String author, String verdict, DateTime at) =>
    DeskThreadEntry(
      author: author,
      body: verdict.isEmpty ? 'comment from $author' : '$verdict from $author',
      at: at,
      verdict: verdict,
    );

DeskPr _prWithThread(List<DeskThreadEntry> thread) => DeskPr(
      deskId: 1,
      title: 't',
      body: 'b',
      headRef: 'feature',
      baseRef: 'main',
      state: 'OPEN',
      isDraft: false,
      authorIdentity: 'author',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      thread: thread,
    );

String _decision(List<DeskThreadEntry> thread) =>
    _prWithThread(thread).toSummary().reviewDecision;

/// Human-readable dump of a thread for failure diagnostics — shows author,
/// verdict (or `-` for a plain comment), timestamp and list position.
String _describe(String label, List<DeskThreadEntry> thread) {
  final b = StringBuffer('$label (${thread.length} entries):\n');
  for (var i = 0; i < thread.length; i++) {
    final e = thread[i];
    b.writeln('  [$i] ${e.author.padRight(8)} '
        '${(e.verdict.isEmpty ? "-" : e.verdict).padRight(18)} '
        '@ ${e.at.toIso8601String()}');
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Random sequence generation.
// ---------------------------------------------------------------------------

const List<String> _authors = ['alice', 'bob', 'carol', 'dave', 'erin'];

// Verdict alphabet with non-decisive verdicts intentionally over-represented
// so sequences routinely exercise the COMMENTED / plain-comment no-op paths.
const List<String> _verdictBag = [
  'APPROVED',
  'CHANGES_REQUESTED',
  'APPROVED',
  'CHANGES_REQUESTED',
  'COMMENTED',
  'COMMENTED',
  '', // plain comment
];

/// Fixed literal seeds. 6 seeds x 50 iterations = 300 cases per property.
const List<int> _seeds = [12345, 67890, 424242, 314159, 271828, 999983];
const int _perSeed = 50;

/// Build a random thread of [n] entries with strictly-increasing unique
/// timestamps (so list order == chronological order, matching the
/// append-only invariant the fold relies on).
List<DeskThreadEntry> _genThread(Random rng, int n) {
  final out = <DeskThreadEntry>[];
  for (var i = 0; i < n; i++) {
    final author = _authors[rng.nextInt(_authors.length)];
    final verdict = _verdictBag[rng.nextInt(_verdictBag.length)];
    out.add(_entry(author, verdict, _ts(i)));
  }
  return out;
}

bool _isDecisive(String v) => v == 'APPROVED' || v == 'CHANGES_REQUESTED';

void main() {
  // -------------------------------------------------------------------------
  // Property 1 — latest-verdict-only dependence.
  //
  // The decision depends only on each author's LATEST decisive verdict. We
  // build a base sequence, then a variant that MERGES each author's own
  // entry-stream in a random interleaving (preserving every author's
  // relative order, hence their decisive order) and reassigns fresh
  // strictly-increasing timestamps by new position. Because each author's
  // last decisive verdict is unchanged, the decision must be identical even
  // though cross-author ordering and all timestamps changed.
  // -------------------------------------------------------------------------
  group('property: latest-verdict-only dependence (order-preserving merge)',
      () {
    test('300 seeded sequences agree with their interleaved variant', () {
      var checked = 0;
      for (final seed in _seeds) {
        final rng = Random(seed);
        for (var i = 0; i < _perSeed; i++) {
          final base = _genThread(rng, rng.nextInt(11)); // 0..10 entries

          // Per-author FIFO queues preserve each author's relative order.
          final queues = <String, List<DeskThreadEntry>>{};
          for (final e in base) {
            (queues[e.author] ??= <DeskThreadEntry>[]).add(e);
          }

          // Randomly merge the streams: repeatedly drain a random non-empty
          // queue's head. This is any valid interleaving that keeps each
          // author's subsequence order intact.
          final merged = <DeskThreadEntry>[];
          var newMinute = 0;
          while (queues.values.any((q) => q.isNotEmpty)) {
            final live =
                queues.keys.where((a) => queues[a]!.isNotEmpty).toList();
            final pick = live[rng.nextInt(live.length)];
            final head = queues[pick]!.removeAt(0);
            // Fresh, strictly-increasing timestamp by new position.
            merged.add(_entry(head.author, head.verdict, _ts(newMinute++)));
          }

          final a = _decision(base);
          final b = _decision(merged);
          expect(
            b,
            a,
            reason: 'seed=$seed iter=$i decision differed after an '
                'order-preserving merge.\n'
                '${_describe("base", base)}${_describe("merged", merged)}',
          );
          checked++;
        }
      }
      expect(checked, _seeds.length * _perSeed);
    });
  });

  // -------------------------------------------------------------------------
  // Property 2 — COMMENTED is a no-op.
  //
  // Appending a COMMENTED entry (from any author, existing or brand new) at
  // any later timestamp must never change the decision.
  // -------------------------------------------------------------------------
  group('property: appending COMMENTED never changes the decision', () {
    test('300 seeded base sequences are invariant under an appended COMMENTED',
        () {
      for (final seed in _seeds) {
        final rng = Random(seed);
        for (var i = 0; i < _perSeed; i++) {
          final base = _genThread(rng, rng.nextInt(11));
          final before = _decision(base);

          // Commenter: 50/50 an existing author or a fresh newcomer.
          final String commenter;
          if (base.isNotEmpty && rng.nextBool()) {
            commenter = base[rng.nextInt(base.length)].author;
          } else {
            commenter = 'newcomer_$i';
          }
          final appended = [
            ...base,
            _entry(commenter, 'COMMENTED', _ts(base.length + 1)),
          ];
          final after = _decision(appended);

          expect(
            after,
            before,
            reason: 'seed=$seed iter=$i: appending COMMENTED from '
                '"$commenter" changed the decision.\n'
                '${_describe("base", base)}${_describe("appended", appended)}',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // Property 3 — approval flips the sole objector.
  //
  // We CONSTRUCT sequences with exactly one author (`objector`) whose latest
  // decisive verdict is CHANGES_REQUESTED and no other author standing at CR.
  // Base decision is therefore CHANGES_REQUESTED. Appending an APPROVED from
  // that same objector (latest timestamp) makes their standing APPROVED, so
  // the outcome must move away from CR. Note the objector now stands APPROVED
  // themselves, so per the return contract (any standing APPROVED -> APPROVED
  // once no CR remains) the result is exactly 'APPROVED' here — the neutral ''
  // branch is unreachable in this construction because a decisive APPROVED is
  // always present after the flip. We assert membership in {APPROVED, ''} to
  // mirror the general contract and additionally pin the exact 'APPROVED'.
  // -------------------------------------------------------------------------
  group('property: approving the sole objector flips CHANGES_REQUESTED away',
      () {
    test('300 constructed sole-objector sequences flip on the objector\'s '
        'APPROVED', () {
      for (final seed in _seeds) {
        final rng = Random(seed);
        for (var i = 0; i < _perSeed; i++) {
          const objector = 'alice';
          // Others draw from a disjoint pool so we control their standing.
          const others = ['bob', 'carol', 'dave', 'erin'];

          final entries = <DeskThreadEntry>[];
          var minute = 0;

          for (final author in others) {
            // Each other author: skip, comment-only, or a final APPROVED.
            // Never a CR-latest (that would violate "sole objector").
            final roll = rng.nextInt(3);
            if (roll == 0) {
              continue; // absent
            } else if (roll == 1) {
              // Non-decisive only: maybe an earlier CR that a COMMENTED does
              // NOT clear would break the invariant, so emit only comments.
              entries.add(_entry(
                  author, rng.nextBool() ? 'COMMENTED' : '', _ts(minute++)));
            } else {
              // Optional earlier CR, then a decisive APPROVED as their latest.
              if (rng.nextBool()) {
                entries.add(_entry(author, 'CHANGES_REQUESTED', _ts(minute++)));
              }
              entries.add(_entry(author, 'APPROVED', _ts(minute++)));
            }
          }

          // Objector: optional earlier APPROVED, then a final CR (latest).
          if (rng.nextBool()) {
            entries.add(_entry(objector, 'APPROVED', _ts(minute++)));
          }
          entries.add(_entry(objector, 'CHANGES_REQUESTED', _ts(minute++)));

          // Shuffle positions; recency is governed by the attached timestamps
          // so the standing verdicts (and thus the decision) are preserved,
          // which also exercises the fold's sort under scrambled input order.
          final scrambled = [...entries]..shuffle(rng);

          final before = _decision(scrambled);
          expect(
            before,
            'CHANGES_REQUESTED',
            reason: 'seed=$seed iter=$i: constructed sole-objector base was '
                'not CHANGES_REQUESTED.\n${_describe("scrambled", scrambled)}',
          );

          // Append the objector's APPROVED at the latest timestamp.
          final flipped = [
            ...scrambled,
            _entry(objector, 'APPROVED', _ts(minute + 1)),
          ];
          final after = _decision(flipped);
          // Contract-level assertion: result is in {APPROVED, ''} and is not
          // CHANGES_REQUESTED.
          expect(
            after,
            anyOf('APPROVED', ''),
            reason: 'seed=$seed iter=$i: outcome left the {APPROVED, \'\'} set '
                'after the sole objector approved.\n'
                '${_describe("flipped", flipped)}',
          );
          expect(
            after,
            isNot('CHANGES_REQUESTED'),
            reason: 'seed=$seed iter=$i: outcome remained CHANGES_REQUESTED '
                'after the sole objector approved.\n'
                '${_describe("flipped", flipped)}',
          );
          // Exact pin: the ex-objector now stands APPROVED, so with no CR left
          // the decision is precisely 'APPROVED'.
          expect(
            after,
            'APPROVED',
            reason: 'seed=$seed iter=$i: expected exactly APPROVED once the '
                'sole objector re-approved (their own APPROVED stands).\n'
                '${_describe("flipped", flipped)}',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // Property 4 — monotone blocking.
  //
  // Appending a fresh author's CHANGES_REQUESTED (an author not previously
  // present) at the latest timestamp must always yield CHANGES_REQUESTED,
  // regardless of how many standing approvals exist.
  // -------------------------------------------------------------------------
  group('property: a new author\'s CHANGES_REQUESTED always blocks', () {
    test('300 seeded sequences are blocked by an appended newcomer CR', () {
      for (final seed in _seeds) {
        final rng = Random(seed);
        for (var i = 0; i < _perSeed; i++) {
          final base = _genThread(rng, rng.nextInt(11));
          // Unique newcomer name guarantees "not previously present".
          final blocker = 'blocker_${seed}_$i';
          final blocked = [
            ...base,
            _entry(blocker, 'CHANGES_REQUESTED', _ts(base.length + 1)),
          ];
          expect(
            _decision(blocked),
            'CHANGES_REQUESTED',
            reason: 'seed=$seed iter=$i: newcomer "$blocker" CR failed to '
                'block.\n${_describe("blocked", blocked)}',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // Property 5 — timestamp-tie determinism.
  //
  // Explicit (not randomized) pairs sharing an identical timestamp, tested in
  // both input orders. Contract: on a tie, LATER LIST POSITION wins. So the
  // second-listed entry is the reviewer's latest standing verdict.
  // -------------------------------------------------------------------------
  group('property: timestamp ties resolve by list position (later wins)', () {
    final tie = _ts(5);

    test('same author, tied CR vs APPROVED — second position wins both ways',
        () {
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', tie),
          _entry('alice', 'APPROVED', tie),
        ]),
        'APPROVED',
        reason: 'tie: [CR, APPROVED] should resolve to the later APPROVED',
      );
      expect(
        _decision([
          _entry('alice', 'APPROVED', tie),
          _entry('alice', 'CHANGES_REQUESTED', tie),
        ]),
        'CHANGES_REQUESTED',
        reason: 'tie: [APPROVED, CR] should resolve to the later CR',
      );
    });

    test('tie between two different authors — each keeps their own verdict',
        () {
      // Distinct authors both stand; CR outranks APPROVED regardless of which
      // is listed later, so this pair is CHANGES_REQUESTED in both orders.
      expect(
        _decision([
          _entry('alice', 'APPROVED', tie),
          _entry('bob', 'CHANGES_REQUESTED', tie),
        ]),
        'CHANGES_REQUESTED',
      );
      expect(
        _decision([
          _entry('bob', 'CHANGES_REQUESTED', tie),
          _entry('alice', 'APPROVED', tie),
        ]),
        'CHANGES_REQUESTED',
      );
    });

    test('tie between a decisive and a non-decisive entry (same author)', () {
      // A COMMENTED tied with (and listed after) a decisive verdict is still
      // a no-op: it never dismisses the standing decision.
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', tie),
          _entry('alice', 'COMMENTED', tie),
        ]),
        'CHANGES_REQUESTED',
      );
      expect(
        _decision([
          _entry('alice', 'APPROVED', tie),
          _entry('alice', 'COMMENTED', tie),
        ]),
        'APPROVED',
      );
      // COMMENTED listed FIRST, decisive second — decisive still governs.
      expect(
        _decision([
          _entry('alice', 'COMMENTED', tie),
          _entry('alice', 'CHANGES_REQUESTED', tie),
        ]),
        'CHANGES_REQUESTED',
      );
    });

    test('tie at the exact moment that would flip an outcome (sole author)',
        () {
      // alice is the only reviewer. Under a tie, whichever decisive verdict is
      // listed last is her standing state — this is the flip pivot.
      expect(
        _decision([
          _entry('alice', 'CHANGES_REQUESTED', tie),
          _entry('alice', 'APPROVED', tie),
        ]),
        'APPROVED',
      );
      expect(
        _decision([
          _entry('alice', 'APPROVED', tie),
          _entry('alice', 'CHANGES_REQUESTED', tie),
        ]),
        'CHANGES_REQUESTED',
      );
    });
  });

  // A tiny sanity guard so the shared helpers can't silently rot.
  test('helper sanity: decisive classifier + empty decision', () {
    expect(_isDecisive('APPROVED'), isTrue);
    expect(_isDecisive('CHANGES_REQUESTED'), isTrue);
    expect(_isDecisive('COMMENTED'), isFalse);
    expect(_isDecisive(''), isFalse);
    expect(_decision(const []), '');
  });
}
