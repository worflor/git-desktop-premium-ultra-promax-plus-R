import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ui/tokens.dart';

class HyperReactivity extends ChangeNotifier {
  bool _active = false;
  double _intensity = 0;
  Offset _dragOffset = Offset.zero;
  Offset _normalizedOffset = Offset.zero;
  Offset _globalPosition = Offset.zero;

  bool get active => _active;
  double get intensity => _intensity;
  Offset get dragOffset => _dragOffset;
  Offset get normalizedOffset => _normalizedOffset;
  Offset get globalPosition => _globalPosition;

  void activate(
    double intensity, {
    Offset dragOffset = Offset.zero,
    Offset normalizedOffset = Offset.zero,
    Offset globalPosition = Offset.zero,
  }) {
    final nextIntensity = intensity.clamp(0, 2.0).toDouble();
    final bool sameIntensity = (_intensity - nextIntensity).abs() < 0.01;
    final bool sameOffset = (_dragOffset - dragOffset).distance < 0.5;
    final bool sameNormalized =
        (_normalizedOffset - normalizedOffset).distance < 0.01;
    final bool sameGlobal = (_globalPosition - globalPosition).distance < 0.5;
    if (_active && sameIntensity && sameOffset && sameNormalized && sameGlobal) {
      return;
    }
    _active = true;
    _intensity = nextIntensity;
    _dragOffset = dragOffset;
    _normalizedOffset = normalizedOffset;
    _globalPosition = globalPosition;
    notifyListeners();
  }

  void deactivate() {
    if (!_active &&
        _intensity == 0 &&
        _dragOffset == Offset.zero &&
        _normalizedOffset == Offset.zero &&
        _globalPosition == Offset.zero) {
      return;
    }
    _active = false;
    _intensity = 0;
    _dragOffset = Offset.zero;
    _normalizedOffset = Offset.zero;
    _globalPosition = Offset.zero;
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
    final RenderObject? renderObject = context.findRenderObject();
    Offset localPull = Offset.zero;
    double proximity = 0;
    if (hyper.active && renderObject is RenderBox && renderObject.hasSize) {
      final Offset center = renderObject.localToGlobal(
        renderObject.size.center(Offset.zero),
      );
      final Offset delta = hyper.globalPosition - center;
      final double distance = delta.distance;
      const double influenceRadius = 180;
      proximity = math.max(0, 1 - distance / influenceRadius);
      proximity = proximity * proximity * (3 - 2 * proximity);
      if (distance > 0.001) {
        localPull = delta / distance;
      }
    }
    final double drag = hyper.active ? hyper.intensity : 0.0;
    final double pull = drag * proximity * proximity;
    final selectedGlow = selected ? 0.35 : 0.0;
    final glow = math.max(math.max(drag * 0.35, pull), selectedGlow);
    const double maxTiltRadians = 12 * math.pi / 180;
    final double translateX = localPull.dx * pull * 8;
    final double translateY = localPull.dy * pull * 8;
    final double tiltX = (-localPull.dy * pull * maxTiltRadians * 1.35) +
        (-drag * maxTiltRadians * 0.2);
    final double tiltY = (localPull.dx * pull * maxTiltRadians * 1.35) +
        (drag * maxTiltRadians * 0.2);

    final scale = 1 + drag * 0.02 + pull * 0.08;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..translate(translateX, translateY, pull * 22 + drag * 4)
      ..scaleByDouble(scale, scale, 1, 1)
      ..rotateX(tiltX)
      ..rotateY(tiltY);

    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: glow > 0
            ? <BoxShadow>[
                BoxShadow(
                  color: t.hyperChromatic1.withValues(alpha: 0.08 + glow * 0.28),
                  blurRadius: 4 + glow * 12 + pull * 4,
                  spreadRadius: glow * 0.4 + pull * 0.6,
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
