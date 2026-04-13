import 'package:flutter/material.dart';

import '../../../ui/design_primitives.dart';
import '../../../ui/motion.dart';
import '../../../ui/tokens.dart';

/// Diamond progress row — one dot per step in the flow. Filled = active,
/// filled-muted = completed, hollow = upcoming. The caller supplies the
/// total; this widget stays agnostic of the step list itself.
class StepIndicator extends StatelessWidget {
  final int total;
  final int current;
  final double size;

  const StepIndicator({
    super.key,
    required this.total,
    required this.current,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          _Diamond(
            size: size,
            state: i < current
                ? _DiamondState.completed
                : i == current
                    ? _DiamondState.active
                    : _DiamondState.upcoming,
            tokens: t,
          ),
        ],
      ],
    );
  }
}

enum _DiamondState { completed, active, upcoming }

class _Diamond extends StatelessWidget {
  final double size;
  final _DiamondState state;
  final AppTokens tokens;

  const _Diamond({
    required this.size,
    required this.state,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color border) = switch (state) {
      _DiamondState.active => (
          tokens.accentBright,
          tokens.accentBright,
        ),
      _DiamondState.completed => (
          tokens.textMuted.withValues(alpha: 0.55),
          tokens.textMuted.withValues(alpha: 0.55),
        ),
      _DiamondState.upcoming => (
          Colors.transparent,
          tokens.textFaint.withValues(alpha: 0.55),
        ),
    };
    return AnimatedContainer(
      duration: context.motion(AppMotion.fade),
      curve: AppMotion.fadeCurve,
      width: size,
      height: size,
      child: Transform.rotate(
        angle: 0.7853981633974483, // pi/4
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border, width: 1.2),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
