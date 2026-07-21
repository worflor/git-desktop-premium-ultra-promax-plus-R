// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Design-system primitive: makes a horizontal strip scrollable with a
/// plain mouse wheel. Flutter's default only moves horizontal
/// scrollables on trackpad dx or shift+wheel — with a bare mouse, an
/// overflowing chip/pill strip is unreachable. Wrap the scrollable
/// (which must use [controller]) and vertical wheel ticks translate
/// into horizontal travel, clamped to the content extent.
///
/// Use for standalone horizontal strips (chip rows, pill rails) that
/// are NOT embedded inside a vertically scrolling flow — the wheel is
/// captured over the strip, so inside a tall scrolling page it would
/// steal the page's wheel. Scrolling is jumpTo-per-tick: wheel input
/// is already discrete, and snappy beats eased here.
class HorizontalWheelScroll extends StatelessWidget {
  final ScrollController controller;
  final Widget child;

  const HorizontalWheelScroll({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent) return;
        final delta =
            e.scrollDelta.dy != 0 ? e.scrollDelta.dy : e.scrollDelta.dx;
        if (delta == 0 || !controller.hasClients) return;
        final pos = controller.position;
        // No overflow → nothing to translate; stay wheel-transparent so a
        // short strip never reads as a dead zone under the pointer.
        if (pos.maxScrollExtent <= 0) return;
        final target =
            (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
        if (target != pos.pixels) pos.jumpTo(target);
      },
      child: child,
    );
  }
}
