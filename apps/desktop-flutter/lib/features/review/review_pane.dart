// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_pane.dart — the assembled review section for a PR detail.
//
// Composes the lab surfaces (header strip, file groups, thread cards,
// drafts) with the two production-only pieces: the composer and the
// atomic publish bar. Everything stays data-blind — ReviewViewBundle
// in, verbs out; the page owns loading and the controller owns git.
//
// The publish bar is where the batch model becomes visible: drafts
// accumulate quietly (their cards claim no thread state, per the look
// laws) and ONE action turns them plus an optional verdict into the
// viewer's turn. Draft-only threads carry no per-card verbs by design;
// their verbs are the bar's publish/discard.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/tokens.dart';
import '../diff/diff_models.dart' show DiffLineMark, DiffLineMarkKind;
import 'review_adapter.dart';
import 'review_pane_controller.dart';
import 'review_chrome.dart';
import 'review_file_header.dart';
import 'review_header_strip.dart';
import 'review_thread_card.dart';
import 'review_view_model.dart';

/// Draft composer: one text field, save-as-draft, cancel. Used both
/// for openers (under the diff, labelled with the anchor position) and
/// for replies (under the thread being answered). Saving is always a
/// DRAFT save — nothing here publishes.
class ReviewComposer extends StatefulWidget {
  final ReviewStrings strings;

  /// Where this comment will pin — 'path:line' for openers, the
  /// thread's anchor label for replies. Rendered mono, muted.
  final String contextLabel;
  final Future<bool> Function(String body) onSave;
  final VoidCallback onCancel;
  final bool autofocus;

  const ReviewComposer({
    super.key,
    required this.strings,
    required this.contextLabel,
    required this.onSave,
    required this.onCancel,
    this.autofocus = true,
  });

  @override
  State<ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends State<ReviewComposer> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _saving) return;
    setState(() => _saving = true);
    final ok = await widget.onSave(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Draft tone: the same left rule a draft-only card carries — this
    // box IS a draft in the making.
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      borderColor: t.chromeBorder,
      borderAlpha: 0.14,
      elevated: false,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: t.accentBright.withValues(alpha: 0.35),
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: ReviewMetrics.lineHeight,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.contextLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: ReviewType.ident,
                          height: 1,
                          fontFamily: AppFonts.mono,
                          fontFamilyFallback: AppFonts.monoFallback,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ReviewChip(
                      label: widget.strings.draft,
                      color: t.accentBright,
                      variant: ReviewChipVariant.outline,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm6),
              // Enter inserts a newline (this is prose); Ctrl/Cmd+Enter
              // is the save — the shortcut every review composer has.
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter,
                      control: true): _save,
                  const SingleActivator(LogicalKeyboardKey.enter,
                      meta: true): _save,
                },
                child: TextField(
                controller: _ctrl,
                autofocus: widget.autofocus,
                minLines: 2,
                maxLines: 8,
                style: TextStyle(
                  color: t.textNormal,
                  fontSize: ReviewType.body,
                  height: 1.45,
                ),
                cursorColor: t.accentBright,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: widget.strings.commentHint,
                  hintStyle: TextStyle(
                    color: t.textFaint,
                    fontSize: ReviewType.body,
                    height: 1.45,
                  ),
                ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ReviewVerbPill(
                    label: widget.strings.cancel,
                    onTap: widget.onCancel,
                  ),
                  const SizedBox(width: AppSpacing.sm6),
                  _busyGate(
                    busy: _saving,
                    child: ReviewVerbPill(
                      label: widget.strings.saveDraft,
                      emphasis: true,
                      onTap: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _busyGate({required bool busy, required Widget child}) => busy
    ? Opacity(opacity: 0.45, child: IgnorePointer(child: child))
    : child;

/// The atomic batch bar: verdict choice + publish + discard. One
/// gesture moves every draft (and the verdict) into the shared state —
/// there is no per-comment send anywhere.
class ReviewPublishBar extends StatefulWidget {
  final ReviewStrings strings;
  final int draftCount;

  /// null verdict = comment-only publish.
  final Future<void> Function(String? verdict) onPublish;
  final VoidCallback onDiscard;

  const ReviewPublishBar({
    super.key,
    required this.strings,
    required this.draftCount,
    required this.onPublish,
    required this.onDiscard,
  });

  @override
  State<ReviewPublishBar> createState() => _ReviewPublishBarState();
}

class _ReviewPublishBarState extends State<ReviewPublishBar> {
  /// 'APPROVED' | 'CHANGES_REQUESTED' | null (comment-only).
  String? _verdict;
  bool _publishing = false;

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() => _publishing = true);
    await widget.onPublish(_verdict);
    if (!mounted) return;
    setState(() {
      _publishing = false;
      _verdict = null;
    });
  }

  Widget _verdictOption(
    AppTokens t, {
    required String label,
    required String? value,
    required Color color,
  }) {
    final selected = _verdict == value;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _verdict = value),
        child: ReviewChip(
          label: label,
          color: selected ? color : t.textMuted,
          variant:
              selected ? ReviewChipVariant.outline : ReviewChipVariant.quiet,
          weight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canPublish = widget.draftCount > 0 || _verdict != null;
    return Row(
      children: [
        _verdictOption(t,
            label: widget.strings.verdictComment,
            value: null,
            color: t.textStrong),
        const SizedBox(width: AppSpacing.sm6),
        _verdictOption(t,
            label: widget.strings.verdictApprove,
            value: 'APPROVED',
            color: t.stateAdded),
        const SizedBox(width: AppSpacing.sm6),
        _verdictOption(t,
            label: widget.strings.verdictRequestChanges,
            value: 'CHANGES_REQUESTED',
            color: t.stateDeleted),
        const Spacer(),
        if (widget.draftCount > 0) ...[
          ReviewChip(
            label: widget.strings.draftCount(widget.draftCount),
            color: t.accentBright,
            variant: ReviewChipVariant.quiet,
          ),
          const SizedBox(width: AppSpacing.sm),
          ReviewVerbPill(
            label: widget.strings.discard,
            onTap: widget.onDiscard,
          ),
          const SizedBox(width: AppSpacing.sm6),
        ],
        _busyGate(
          busy: _publishing || !canPublish,
          child: ReviewVerbPill(
            label: widget.strings.publish,
            emphasis: true,
            onTap: _publish,
          ),
        ),
      ],
    );
  }
}

/// The whole review section under a PR's diff: header strip, threads
/// grouped by file, the viewer's unpublished drafts, and the publish
/// bar. Pure composition — every verb is a callback.
class ReviewPane extends StatefulWidget {
  final ReviewViewBundle bundle;
  final ReviewStrings strings;
  final int draftCount;
  final Future<bool> Function(String threadId, String body) onSaveReply;
  final Future<void> Function(String threadId, String how) onResolve;

  /// Undo a resolution. Null leaves resolved threads final.
  final Future<void> Function(String threadId)? onReopen;

  /// Remove ONE draft: (threadId, body, when). '' threadId = an opener.
  final Future<void> Function(String threadId, String body, DateTime at)?
      onDiscardDraft;
  final Future<void> Function(String? verdict) onPublish;
  final VoidCallback onDiscardDrafts;

  /// Focus the diff on this file (file header tap).
  final ValueChanged<String>? onSelectFile;

  const ReviewPane({
    super.key,
    required this.bundle,
    required this.strings,
    required this.draftCount,
    required this.onSaveReply,
    required this.onResolve,
    this.onReopen,
    this.onDiscardDraft,
    required this.onPublish,
    required this.onDiscardDrafts,
    this.onSelectFile,
  });

  @override
  State<ReviewPane> createState() => _ReviewPaneState();
}

class _ReviewPaneState extends State<ReviewPane> {
  String? _replyThreadId;

  /// The remover for a draft-only card, or null when there is nothing
  /// single to remove (a published thread, or a draft whose identity
  /// the adapter did not stamp).
  VoidCallback? _draftRemover(ReviewThreadView thread) {
    if (widget.onDiscardDraft == null || !thread.isDraftOnly) return null;
    final draft = thread.comments.singleWhere(
      (c) => c.isDraft && c.draftAt != null,
      orElse: () => const ReviewCommentView(author: '', when: '', body: ''),
    );
    final at = draft.draftAt;
    if (at == null) return null;
    return () => widget.onDiscardDraft!(thread.threadId, draft.body, at);
  }

  Widget _threadCard(ReviewThreadView thread, {required bool showPath}) {
    final unresolved = thread.state == ReviewThreadState.unresolved;
    // Draft-only threads have no id and no published state: their verbs
    // are the batch bar's publish/discard, by design.
    //
    // Robot threads take done/ack too. The card suppresses those in
    // favour of `please fix` ONLY when a promote handler is wired, which
    // lands with the Tricorder slice — until then a machine finding is
    // resolvable like any other rather than being a dead end.
    final canVerb = unresolved && thread.threadId.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewThreadCard(
          thread: thread,
          strings: widget.strings,
          showPath: showPath,
          onDone: canVerb
              ? () => widget.onResolve(thread.threadId, 'done')
              : null,
          onAck: canVerb
              ? () => widget.onResolve(thread.threadId, 'acked')
              : null,
          onReply: canVerb
              ? () => setState(() => _replyThreadId = thread.threadId)
              : null,
          onReopen: widget.onReopen == null || thread.threadId.isEmpty
              ? null
              : () => widget.onReopen!(thread.threadId),
          onDiscardDraft: _draftRemover(thread),
        ),
        if (_replyThreadId == thread.threadId &&
            thread.threadId.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm6),
          ReviewComposer(
            strings: widget.strings,
            contextLabel: '${thread.filePath}:${thread.line}',
            onSave: (body) async {
              final id = thread.threadId;
              final ok = await widget.onSaveReply(id, body);
              // Same ownership rule as the opener composer: while this
              // save was in flight the user may have moved on to reply
              // to a DIFFERENT thread, and closing whatever happens to
              // be open now would discard text they are still writing.
              if (ok && mounted && _replyThreadId == id) {
                setState(() => _replyThreadId = null);
              }
              return ok;
            },
            onCancel: () => setState(() => _replyThreadId = null),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final b = widget.bundle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewHeaderStrip(header: b.header, strings: widget.strings),
        for (final group in b.groups) ...[
          const SizedBox(height: AppSpacing.md),
          ReviewFileHeader(
            filePath: group.filePath,
            onTap: widget.onSelectFile == null
                ? null
                : () => widget.onSelectFile!(group.filePath),
          ),
          for (final thread in group.threads) ...[
            const SizedBox(height: AppSpacing.sm6),
            _threadCard(thread, showPath: false),
          ],
        ],
        if (b.draftThreads.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: ReviewMetrics.lineHeight,
            child: Row(
              children: [
                Text(
                  widget.strings.drafts,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: ReviewType.ident,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm10),
                Expanded(
                  child: Container(
                    height: AppBorderWidth.hairline,
                    color: t.chromeBorderFaint,
                  ),
                ),
              ],
            ),
          ),
          for (final thread in b.draftThreads) ...[
            const SizedBox(height: AppSpacing.sm6),
            _threadCard(thread, showPath: true),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
        ReviewPublishBar(
          strings: widget.strings,
          draftCount: widget.draftCount,
          onPublish: widget.onPublish,
          onDiscard: widget.onDiscardDrafts,
        ),
      ],
    );
  }
}

/// Map one file's resolvable threads onto diff gutter marks. Outdated
/// anchors are deliberately absent — they have no live row to mark and
/// their honest home is the pane card with its "last seen R{n}" chip.
///
/// [includeOldSide] is false when the rendered diff's left column isn't
/// the tree old-side anchors were captured against (any lens): their
/// line numbers address the merge base, so marking rows of a different
/// tree with them would point at unrelated code.
List<DiffLineMark> buildLineMarks(
  ReviewViewBundle bundle,
  String path, {
  bool includeOldSide = true,
}) {
  DiffLineMarkKind kindOf(ReviewThreadView t) {
    if (t.isDraftOnly) return DiffLineMarkKind.draft;
    if (t.isRobot) return DiffLineMarkKind.robot;
    if (t.state != ReviewThreadState.unresolved) {
      return DiffLineMarkKind.resolved;
    }
    return DiffLineMarkKind.thread;
  }

  final marks = <DiffLineMark>[];
  for (final t in [...bundle.threads, ...bundle.draftThreads]) {
    if (t.filePath != path) continue;
    if (t.anchorState == ReviewAnchorState.outdated) continue;
    if (t.side == 'old' && !includeOldSide) continue;
    marks.add(DiffLineMark(
      oldSide: t.side == 'old',
      line: t.line,
      kind: kindOf(t),
    ));
  }
  return marks;
}

/// Everything the PR row/expanded surfaces need from the page to host
/// a review, bundled so the (deep) widget plumbing is ONE nullable
/// param. Built fresh per build from page state; all verbs route back
/// into page handlers that reload and setState.
class ReviewPrHooks {
  final ReviewPaneData data;
  final ReviewStrings strings;

  /// Gutter marks for the diff's active file.
  final List<DiffLineMark> Function(
    String activePath, {
    bool includeOldSide,
  }) marksFor;

  /// A gutter tap on the active file: open the opener composer there.
  final void Function(String path, bool oldSide, int line) onGutterTap;

  /// Active opener-composer target, or null when closed.
  final (String path, bool oldSide, int line)? composeAt;
  final Future<bool> Function(String body) onSaveOpener;
  final VoidCallback onCancelCompose;

  final Future<bool> Function(String threadId, String body) onSaveReply;
  final Future<void> Function(String threadId, String how) onResolve;
  final Future<void> Function(String threadId) onReopen;
  final Future<void> Function(String threadId, String body, DateTime at)
      onDiscardDraft;
  final Future<void> Function(String? verdict) onPublish;
  final VoidCallback onDiscardDrafts;
  final ValueChanged<String>? onSelectFile;

  /// "Since your last look" lens: available only once a last-look
  /// pointer exists and the head has moved past it.
  final bool lensAvailable;
  final bool lensSinceLastLook;
  final ValueChanged<bool>? onSetLens;

  /// True while a lens is being fetched. The posture flips optimistically
  /// so the chip answers the click at once, which means the diff under it
  /// is momentarily the OLD comparison under a label claiming the new
  /// one — hosts render their loading state instead of that lie.
  final bool lensLoading;

  /// The materialized lens diff, when one is active. Non-null replaces
  /// the file pills and the rendered patch for this PR — and ONLY those;
  /// it is never the PR's canonical detail (see the page's cache note).
  final ReviewLensDiff? lens;

  /// Advance the last-look pointer without publishing. Null when the
  /// viewer is already current — nothing to catch up on.
  final VoidCallback? onCaughtUp;

  /// Round numbers (ascending) with cut pins — the snapshot axis.
  final List<int> rounds;

  /// Active round-to-round comparison, or null. Setting it evicts and
  /// reloads the diff as `<pin(from)>..<pin(to)>`.
  final (int, int)? compare;
  final void Function((int, int)? compare)? onSetCompare;

  /// False when the rendered diff's right side is NOT the head (a
  /// compare whose `to` is an older round) — anchors resolve against
  /// head content, so markers and gutter capture stand down rather
  /// than mislabel rows.
  final bool diffShowsHead;

  const ReviewPrHooks({
    required this.data,
    required this.strings,
    required this.marksFor,
    required this.onGutterTap,
    required this.composeAt,
    required this.onSaveOpener,
    required this.onCancelCompose,
    required this.onSaveReply,
    required this.onResolve,
    required this.onReopen,
    required this.onDiscardDraft,
    required this.onPublish,
    required this.onDiscardDrafts,
    this.onSelectFile,
    this.lensAvailable = false,
    this.lensSinceLastLook = false,
    this.onSetLens,
    this.lens,
    this.lensLoading = false,
    this.onCaughtUp,
    this.rounds = const [],
    this.compare,
    this.onSetCompare,
    this.diffShowsHead = true,
  });
}
