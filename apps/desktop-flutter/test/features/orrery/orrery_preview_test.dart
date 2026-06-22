// Not a pass/fail test — a render harness for the disk painter alone. Paints
// the Orrery on synthetic data and writes PNGs to .preview/ so the disk can be
// eyeballed without the page chrome. Run with:
//   flutter test test/features/orrery/orrery_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/orrery/orrery_painter.dart';
import 'package:git_desktop/ui/tokens.dart';

import 'orrery_fixture.dart';

Future<void> _renderPng(CustomPainter painter, Size size, String path) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote ${file.absolute.path}');
}

void main() {
  test('orrery disk preview frames', () async {
    final model = syntheticOrrery();
    const size = Size(900, 900);
    final frames = <String, double>{
      'early': 3,
      'reorg': 13,
      'head': model.headPosition,
    };
    for (final themeId in <AppThemeId>[
      AppThemeId.petrichor,
      AppThemeId.aether
    ]) {
      final colors = OrreryColors.fromTokens(AppTokens.fromId(themeId));
      for (final entry in frames.entries) {
        await _renderPng(
          OrreryPainter(model: model, head: entry.value, colors: colors),
          size,
          '.preview/orrery_${themeId.name}_${entry.key}.png',
        );
      }
    }
  });
}
