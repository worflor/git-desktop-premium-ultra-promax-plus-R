// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_strings_i18n.dart — the slang bridge for review surfaces.
//
// The review widgets are string-blind by design (ReviewStrings is
// injected, English defaults keep the preview lab hermetic); this is
// the ONE place the slang tree feeds them. Same injected-strings
// pattern the backend uses to stay Flutter-free.

import '../../i18n/gen/strings.g.dart';
import 'review_view_model.dart';

/// [ReviewStrings] backed by the app's active locale.
ReviewStrings reviewStringsFrom(Translations t) => _SlangReviewStrings(t);

class _SlangReviewStrings extends ReviewStrings {
  final Translations _t;

  _SlangReviewStrings(Translations t)
      : _t = t,
        super(
          unresolved: t.review.unresolved,
          done: t.review.done,
          ack: t.review.ack,
          reply: t.review.reply,
          pleaseFix: t.review.pleaseFix,
          draft: t.review.draft,
          engine: t.review.engine,
          moved: t.review.moved,
          yourTurn: t.review.yourTurn,
          drafts: t.review.drafts,
          publish: t.review.publish,
          discard: t.review.discard,
          saveDraft: t.review.saveDraft,
          cancel: t.review.cancel,
          verdictApprove: t.review.verdictApprove,
          verdictRequestChanges: t.review.verdictRequestChanges,
          verdictComment: t.review.verdictComment,
          caughtUp: t.review.caughtUp,
          sinceLastLook: t.review.sinceLastLook,
          fullDiff: t.review.fullDiff,
          commentHint: t.review.commentHint,
          reopen: t.review.reopen,
        );

  @override
  String outdatedLastSeen(int round) =>
      _t.review.outdatedLastSeen(round: round);

  @override
  String resolvedBy(String verb, String who) =>
      _t.review.resolvedByFmt(verb: verb, who: who);

  @override
  String waitingOn(String who) => _t.review.waitingOnFmt(who: who);

  @override
  String roundChip(int round) => _t.review.roundChip(round: round);

  @override
  String filesSinceLastLook(int n) => _t.review.filesSinceLastLook(n: n);

  @override
  String unresolvedCount(int n) => _t.review.unresolvedCountFmt(n: n);

  @override
  String draftCount(int n) => _t.review.draftCountFmt(n: n);
}
