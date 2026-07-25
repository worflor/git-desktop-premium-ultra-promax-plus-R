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

  const ReviewFileHeader({
    super.key,
    required this.filePath,
    this.onTap,
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
                color: t.textMuted,
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
          if (reviewed != null) ...[
            const SizedBox(width: AppSpacing.sm10),
            _ReviewedMark(
              on: reviewed!,
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

/// The per-file reviewed mark.
///
/// Present or faint, never appearing and disappearing: a mark that
/// occupies space only when set would make finishing a file nudge the
/// hairline beside it. Faint reads as "not yet", not as disabled.
class _ReviewedMark extends StatefulWidget {
  final bool on;
  final VoidCallback? onTap;

  const _ReviewedMark({required this.on, required this.onTap});

  @override
  State<_ReviewedMark> createState() => _ReviewedMarkState();
}

class _ReviewedMarkState extends State<_ReviewedMark> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = widget.on
        ? t.accentBright
        : (_hover ? t.textMuted : t.chromeBorderStrong);
    // Material's check, not a text glyph: U+2713 is absent from the
    // themes' font families, so a Text tick renders as tofu on every
    // theme — caught in the preview, and the same class of gap that
    // had the test harness rendering mono code as boxes.
    final mark = SizedBox(
      height: ReviewMetrics.lineHeight,
      width: ReviewMetrics.lineHeight,
      child: Center(
        child: Icon(
          Icons.check,
          size: ReviewType.body,
          color: color,
        ),
      ),
    );
    if (widget.onTap == null) return mark;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: mark,
      ),
    );
  }
}
