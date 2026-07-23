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

  const ReviewFileHeader({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
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
        ],
      ),
    );
  }
}
