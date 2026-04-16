import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'motion.dart';

/// Material-You style hover lift.
/// Wrap any surface/card and it will rise a few pixels toward the cursor
/// on hover, settling back on exit, via a true spring simulation (mass +
/// stiffness + damping). Idle = zero ticks — the controller only runs
/// during the 150-300ms spring travel, then pauses.
/// Respects the Reduce Motion preference: when enabled, hover just swaps
/// to the target value instantly with no animation.
/// Minimal API — the spring is tuned once globally; callers only pick how
/// high to lift.
class HoverLift extends StatefulWidget {
  final Widget child;

  /// Pixels to lift on hover. 3-4 feels great for rows, 6-8 for cards.
  final double liftBy;

  /// When true, skips the lift animation. Useful for disabled states.
  final bool disabled;

  const HoverLift({
    super.key,
    required this.child,
    this.liftBy = 3,
    this.disabled = false,
  });

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController.unbounded(
    vsync: this,
  );

  // Spring tuning: enough stiffness to feel responsive, enough damping to
  // avoid visible oscillation on exit. ~180-220ms round trip in practice.
  static const SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 280,
    damping: 22,
  );

  bool _hovered = false;

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  void _setHovered(bool h) {
    if (_hovered == h) return;
    _hovered = h;
    if (context.reduceMotionRead) {
      _ac.value = h ? 1 : 0;
      return;
    }
    final sim = SpringSimulation(_spring, _ac.value, h ? 1.0 : 0.0, 0);
    _ac.animateWith(sim);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.disabled) return widget.child;
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedBuilder(
        animation: _ac,
        builder: (context, child) {
          // clamp because spring overshoots; negative y = upward lift.
          final v = _ac.value.clamp(-0.2, 1.2);
          return Transform.translate(
            offset: Offset(0, -widget.liftBy * v),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
