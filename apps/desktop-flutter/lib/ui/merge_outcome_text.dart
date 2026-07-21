// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import '../backend/merge_session.dart';
import '../i18n/gen/strings.g.dart';

/// One-line, user-facing summary of a [MergeOutcome] — the single source of
/// truth so the wording never drifts between the branch pill, the clean-tree
/// dashboard, and the sync panel. [op] names the action and is required:
/// pass the localized word from `t.backend.ops.*` so translators own it.
/// Conflict outcomes point at the Changes page, which always carries the
/// resolve affordance, so a deferred conflict never dead-ends in a snackbar.
///
/// Lives in the UI layer (not the pure-Dart `merge_session` backend) so the
/// localized wording is resolved via slang without dragging flutter/widgets
/// into the backend. Uses the global [t]; callers are one-shot surfaces
/// (snackbars, pills) that read the string at build time.
String mergeOutcomeMessage(MergeOutcome outcome, {required String op}) =>
    switch (outcome) {
      MergeClean(:final data) =>
        data.output.isNotEmpty ? data.output : t.backend.mergeOutcome.complete(op: op),
      MergeConflicted(:final paths, :final resolved) => resolved
          ? t.backend.mergeOutcome.resolvedConflicts(n: paths.length)
          : paths.isEmpty
              // Discarded/cancelled before anything was written.
              ? t.backend.mergeOutcome.cancelled(op: op)
              : t.backend.mergeOutcome.conflictsLeft(n: paths.length),
      MergeBlockedByLocalChanges(:final paths) =>
        t.backend.mergeOutcome.uncommittedEdits(n: paths.length),
      MergeNeedsCheckout(:final message) => message,
      MergeFailed(:final message) => message,
    };
