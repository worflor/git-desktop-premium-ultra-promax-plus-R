import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ui/tokens.dart';

class HyperReactivity extends ChangeNotifier {
  bool _active = false;
  double _intensity = 0;
  Offset _dragOffset = Offset.zero;
  Offset _normalizedOffset = Offset.zero;

  bool get active => _active;
  double get intensity => _intensity;
  Offset get dragOffset => _dragOffset;
  Offset get normalizedOffset => _normalizedOffset;

  void activate(
    double intensity, {
    Offset dragOffset = Offset.zero,
    Offset normalizedOffset = Offset.zero,
  }) {
    final nextIntensity = intensity.clamp(0, 2.0).toDouble();
    final bool sameIntensity = (_intensity - nextIntensity).abs() < 0.01;
    final bool sameOffset = (_dragOffset - dragOffset).distance < 0.5;
    final bool sameNormalized =
        (_normalizedOffset - normalizedOffset).distance < 0.01;
    if (_active && sameIntensity && sameOffset && sameNormalized) return;
    _active = true;
    _intensity = nextIntensity;
    _dragOffset = dragOffset;
    _normalizedOffset = normalizedOffset;
    notifyListeners();
  }

  void deactivate() {
    if (!_active &&
        _intensity == 0 &&
        _dragOffset == Offset.zero &&
        _normalizedOffset == Offset.zero) {
      return;
    }
    _active = false;
    _intensity = 0;
    _dragOffset = Offset.zero;
    _normalizedOffset = Offset.zero;
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
    final drag = hyper.active ? hyper.intensity : 0.0;
    final selectedGlow = selected ? 0.35 : 0.0;
    final glow = math.max(drag, selectedGlow);
    const double maxTiltRadians = 12 * math.pi / 180;

    final scale = 1 + drag * 0.05;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translate(0.0, 0.0, drag * 15)
      ..rotateX(-drag * maxTiltRadians)
      ..rotateY(drag * maxTiltRadians);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: glow > 0
            ? <BoxShadow>[
                BoxShadow(
                  color: t.hyperChromatic1.withValues(alpha: 0.08 + glow * 0.28),
                  blurRadius: 4 + glow * 12,
                  spreadRadius: glow * 0.4,
                ),
              ]
            : null,
        border: glow > 0
            ? Border.all(
                color: t.hyperChromatic1.withValues(alpha: 0.2 + glow * 0.4),
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
