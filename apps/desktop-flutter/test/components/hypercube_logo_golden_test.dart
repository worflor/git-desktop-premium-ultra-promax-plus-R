import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/components/hypercube_logo.dart';
import 'package:git_desktop/components/hypercube_logo_engine.dart';
import 'package:git_desktop/ui/tokens.dart';

typedef _ScenarioSetup = void Function(HypercubeLogoEngine engine);

void main() {
  testWidgets('render signatures stay stable across scenarios and themes',
      (tester) async {
    final scenarios = <({String name, _ScenarioSetup setup})>[
      (
        name: 'idle',
        setup: (engine) {
          engine.currentIndex = 0;
          engine.targetIndex = 1;
          engine.transition = 0.45;
          engine.time = 0.9;
          engine.near = 0;
          engine.dragging = false;
          engine.tiltX = 0;
          engine.tiltY = 0;
          engine.warpX = 0;
          engine.warpY = 0;
          engine.warpVx = 0;
          engine.warpVy = 0;
        },
      ),
      (
        name: 'hover',
        setup: (engine) {
          engine.currentIndex = 2;
          engine.targetIndex = 7;
          engine.transition = 0.41;
          engine.time = 1.35;
          engine.near = 0.58;
          engine.dragging = false;
          engine.tiltX = 0.08;
          engine.tiltY = -0.06;
          engine.warpX = 0;
          engine.warpY = 0;
          engine.warpVx = 0;
          engine.warpVy = 0;
        },
      ),
      (
        name: 'dragging',
        setup: (engine) {
          engine.currentIndex = 4;
          engine.targetIndex = 10;
          engine.transition = 0.63;
          engine.time = 2.1;
          engine.near = 0.82;
          engine.dragging = true;
          engine.tiltX = 0.12;
          engine.tiltY = -0.1;
          engine.warpX = 5.2;
          engine.warpY = -3.4;
          engine.warpVx = 0;
          engine.warpVy = 0;
        },
      ),
      (
        name: 'checkpoint-1',
        setup: (engine) {
          engine.currentIndex = 6;
          engine.targetIndex = 11;
          engine.transition = 0.22;
          engine.time = 0.42;
          engine.near = 0.18;
          engine.dragging = false;
          engine.tiltX = -0.03;
          engine.tiltY = 0.05;
          engine.warpX = 0;
          engine.warpY = 0;
          engine.warpVx = 0;
          engine.warpVy = 0;
        },
      ),
      (
        name: 'checkpoint-2',
        setup: (engine) {
          engine.currentIndex = 8;
          engine.targetIndex = 12;
          engine.transition = 0.74;
          engine.time = 3.06;
          engine.near = 0.48;
          engine.dragging = false;
          engine.tiltX = -0.09;
          engine.tiltY = 0.04;
          engine.warpX = 0;
          engine.warpY = 0;
          engine.warpVx = 0;
          engine.warpVy = 0;
        },
      ),
      (
        name: 'checkpoint-3',
        setup: (engine) {
          engine.currentIndex = 9;
          engine.targetIndex = 3;
          engine.transition = 0.29;
          engine.time = 1.82;
          engine.near = 0.72;
          engine.dragging = true;
          engine.tiltX = 0.04;
          engine.tiltY = 0.11;
          engine.warpX = -4.1;
          engine.warpY = 3.2;
          engine.warpVx = 0;
          engine.warpVy = 0;
        },
      ),
    ];

    final signaturesByTheme = <AppThemeId, List<int>>{};
    for (final themeId in AppThemeId.values) {
      final tokens = AppTokens.fromId(themeId);
      final themeSignatures = <int>[];

      for (final scenario in scenarios) {
        final engine = HypercubeLogoEngine(seed: 99);
        scenario.setup(engine);
        final projected = engine.projectedData(72);
        final painter = HypercubeLogoPainter(
          projected: projected,
          near: engine.near,
          dragging: engine.dragging,
          colors: HypercubeLogoColors.fromTokens(tokens),
        );
        final signature = await _renderSignature(painter, 72);
        expect(
          signature,
          isPositive,
          reason: 'Expected non-empty render for ${themeId.name}/${scenario.name}',
        );
        themeSignatures.add(signature);
      }

      expect(
        themeSignatures.toSet().length,
        greaterThanOrEqualTo(4),
        reason: 'Expected distinct checkpoints for theme ${themeId.name}',
      );
      signaturesByTheme[themeId] = themeSignatures;
    }

    final idleSignatures = signaturesByTheme.values.map((v) => v.first).toSet();
    expect(
      idleSignatures.length,
      greaterThanOrEqualTo(7),
      reason: 'Expected strong theme-dependent rendering variance',
    );
  });
}

Future<int> _renderSignature(HypercubeLogoPainter painter, double size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, size, size),
  );
  painter.paint(canvas, ui.Size(size, size));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    return 0;
  }
  final bytes = byteData.buffer.asUint8List();
  int hash = 17;
  for (int i = 0; i < bytes.length; i += 4) {
    hash = 0x1fffffff & (hash * 37 + bytes[i]);
    hash = 0x1fffffff & (hash * 37 + bytes[i + 1]);
    hash = 0x1fffffff & (hash * 37 + bytes[i + 2]);
    hash = 0x1fffffff & (hash * 37 + bytes[i + 3]);
  }
  return hash;
}
