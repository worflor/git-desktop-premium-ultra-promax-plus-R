// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_file_header.dart — one file's header in the review pane.
//
// The path prints ONCE here; the thread cards beneath anchor by line
// alone. This is what breaks the repeated-chiclet monotony: the pane
// reads as "files containing conversations", not "a list of identical
// cards whose headers you have to diff by eye". Deliberately the
// quietest structural element on the page — mono path plus a hairline
// that carries the eye across, nothing else.

import 'package:flutter/material.dart';

import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart' show AppTokenSurfaceTones;
import '../../ui/tokens.dart';
import 'review_chrome.dart';
import 'review_view_model.dart';

class ReviewFileHeader extends StatelessWidget {
  final String filePath;

  /// Ticked at THIS file's current content. Null when the host does not
  /// offer the mark at all (the preview lab, a read-only surface).
  final bool? reviewed;

  /// Toggle the mark. The tick is deliberately not a checkbox: it sits
  /// on the header you are already reading when you finish a file, and
  /// it occupies the same width ticked or not, so completing a file
  /// never re-measures the row under the pointer.
  final ValueChanged<bool>? onToggleReviewed;

  /// Optional: the header becomes a quiet navigation target (the page
  /// wires this to focus the diff on this file). No chrome change
  /// beyond the cursor — the pane stays the quietest layer.
  final VoidCallback? onTap;

  /// Words for the two glyphs on this row. Injected like every other
  /// string a review surface renders.
  final ReviewStrings strings;

  /// True when this file holds a comment the viewer has not been shown.
  ///
  /// The path takes the accent. Nothing is added to the row: the file
  /// header is already the navigational unit — it is what you tap to
  /// focus the diff — so the eye that is scanning for "where did the
  /// conversation move" is looking at exactly these rows anyway.
  ///
  /// Without it the header's "3 new" was a number with no direction: the
  /// only other unread signal is an accent on an individual comment's
  /// timestamp, which you have to already be reading the card to see.
  final bool hasUnseen;

  /// Start a comment about this file as a whole. Null hides the verb.
  ///
  /// It belongs here rather than in the diff gutter because it is not
  /// about a line — and because a file over the byte gate, or a binary
  /// one, has no gutter to tap while still being exactly the kind of
  /// file somebody wants to say "this should not be in this change"
  /// about.
  final VoidCallback? onComment;

  const ReviewFileHeader({
    super.key,
    required this.filePath,
    this.strings = const ReviewStrings(),
    this.hasUnseen = false,
    this.onTap,
    this.onComment,
    this.reviewed,
    this.onToggleReviewed,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final row = SizedBox(
      height: ReviewMetrics.lineHeight,
      child: Row(
        children: [
          Flexible(
            child: Text(
              filePath,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnseen ? t.accentBright : t.textMuted,
                fontSize: ReviewType.ident,
                height: 1,
                fontFamily: AppFonts.mono,
                fontFamilyFallback: AppFonts.monoFallback,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm10),
          Expanded(
            child: Container(
              height: AppBorderWidth.hairline,
              color: t.chromeBorderFaint,
            ),
          ),
          if (onComment != null) ...[
            const SizedBox(width: AppSpacing.sm10),
            ReviewQuietGlyph(
              icon: Icons.mode_comment_outlined,
              label: strings.commentOnFile,
              onTap: onComment,
            ),
          ],
          if (reviewed != null) ...[
            const SizedBox(width: AppSpacing.sm10),
            // The reviewed mark IS a quiet glyph — it is what the shared
            // one was extracted from. Leaving the original beside the
            // extraction is how two implementations of one affordance
            // start drifting apart.
            ReviewQuietGlyph(
              icon: Icons.check,
              label: strings.markReviewed,
              active: reviewed!,
              onTap: onToggleReviewed == null
                  ? null
                  : () => onToggleReviewed!(!reviewed!),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}
