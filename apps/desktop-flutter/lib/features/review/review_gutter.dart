// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_gutter.dart — the per-line comment affordance in the diff gutter.
//
// One small cell per diff row. Quiet by design: an empty line shows
// nothing, a hovered line whispers an invite, a line with a thread
// carries a dot (count when > 1). Robot threads and dead anchors keep
// their own marks so the gutter alone tells you what kind of attention
// a line holds. Rendered OUTSIDE the diff shell's hot row path — the
// overlay layer owns these cells.

import 'package:flutter/material.dart';

import '../../ui/design_primitives.dart';
import '../../ui/tokens.dart';
import 'review_view_model.dart';

class ReviewGutterCell extends StatelessWidget {
  static const double width = 18;
  static const double height = 16;

  final ReviewGutterState state;

  /// Thread count on this line (rendered when > 1).
  final int count;

  const ReviewGutterCell({
    super.key,
    required this.state,
    this.count = 1,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: width,
      height: height,
      child: Center(child: _mark(t)),
    );
  }

  Widget _mark(AppTokens t) {
    switch (state) {
      case ReviewGutterState.none:
        return const SizedBox.shrink();
      case ReviewGutterState.invite:
        return Text(
          '+',
          style: TextStyle(
            color: t.textFaint,
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        );
      case ReviewGutterState.thread:
        if (count > 1) {
          return Text(
            '$count',
            style: TextStyle(
              color: t.accentBright,
              fontSize: 8.5,
              height: 1,
              fontFamily: AppFonts.mono,
              fontFamilyFallback: AppFonts.monoFallback,
              fontWeight: FontWeight.w700,
            ),
          );
        }
        return _dot(t.accentBright, filled: true);
      case ReviewGutterState.draft:
        return _dot(t.accentBright, filled: false);
      case ReviewGutterState.robot:
        return Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: t.stateFragile.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      case ReviewGutterState.outdated:
        return _dot(t.textFaint.withValues(alpha: 0.7), filled: true);
    }
  }

  Widget _dot(Color color, {required bool filled}) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: filled ? color : null,
          shape: BoxShape.circle,
          border: filled
              ? null
              : Border.all(color: color, width: AppBorderWidth.thin),
        ),
      );
}
