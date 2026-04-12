import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ui/tokens.dart';

class HyperReactivity extends ChangeNotifier {
  bool _active = false;
  double _intensity = 0;

  bool get active => _active;
  double get intensity => _intensity;

  void activate(double intensity) {
    final nextIntensity = intensity.clamp(0, 1.4).toDouble();
    if (_active == true && (_intensity - nextIntensity).abs() < 0.01) return;
    _active = true;
    _intensity = nextIntensity;
    notifyListeners();
  }

  void deactivate() {
    if (!_active && _intensity == 0) return;
    _active = false;
    _intensity = 0;
    notifyListeners();
  }
}

class HyperReactive extends StatelessWidget {
  final Widget child;
  final bool selected;
  final double borderRadius;

  const HyperReactive({
    super.key,
    required this.child,
    this.selected = false,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hyper = context.watch<HyperReactivity>();
    final drag = hyper.active ? hyper.intensity.clamp(0, 1).toDouble() : 0.0;
    final selectedGlow = selected ? 0.35 : 0.0;
    final glow = math.max(drag, selectedGlow);

    final scale = 1 + drag * 0.035;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..scaleByDouble(scale, scale, 1, 1)
      ..rotateX(-drag * 0.08)
      ..rotateY(drag * 0.08);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: glow > 0
            ? Border.all(
                color: t.chromeAccent.withValues(alpha: 0.18 + glow * 0.32),
              )
            : null,
      ),
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: child,
      ),
    );
  }
}
