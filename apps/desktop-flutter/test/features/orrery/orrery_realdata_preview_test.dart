// Real-data smoke test + render: builds the SpectralTrajectory for this actual
// repo, maps it through OrreryModel.fromTrajectory, and renders the result.
// Verifies the real path end-to-end and writes PNGs to .preview/. Run with:
//   flutter test test/features/orrery/orrery_realdata_preview_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/spectral_trajectory_builder.dart';
import 'package:git_desktop/features/orrery/orrery_findings.dart';
import 'package:git_desktop/features/orrery/orrery_model.dart';
import 'package:git_desktop/features/orrery/orrery_painter.dart';
import 'package:git_desktop/features/orrery/orrery_page.dart';
import 'package:git_desktop/ui/tokens.dart';

const _repo =
    'C:/Users/mini server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R';

Future<void> _writeImage(ui.Image image, String path) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote ${file.absolute.path}');
}

void main() {
  testWidgets('orrery on real repo history', (tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    OrreryModel? model;
    await tester.runAsync(() async {
      final traj = await trajectoryForRepo(_repo);
      model = OrreryModel.fromTrajectory(traj);
    });
    final m = model!;
    // ignore: avoid_print
    print('REAL trajectory: steps=${m.stepCount} nodes=${m.nodes.length}');
    expect(m.stepCount, greaterThan(1));

    for (final f in computeFindings(m)) {
      // ignore: avoid_print
      print('FINDING [${f.kind.name}] ${f.headline}');
    }

    // Disk-only, straight to a picture (fast, no widget tree).
    await tester.runAsync(() async {
      final colors = OrreryColors.fromTokens(AppTokens.fromId(AppThemeId.aether));
      final recorder = ui.PictureRecorder();
      const size = Size(900, 900);
      final canvas = Canvas(recorder, Offset.zero & size);
      OrreryPainter(model: m, head: m.headPosition, colors: colors)
          .paint(canvas, size);
      final image = await recorder.endRecording().toImage(900, 900);
      await _writeImage(image, '.preview/orrery_REAL_disk.png');
    });

    // Full page, aether — pin a drifting file so the drill-down trail shows.
    int? pinned;
    for (final f in computeFindings(m)) {
      if (f.nodeId != null) {
        pinned = f.nodeId;
        if (f.kind == OrreryFindingKind.driftOut) break;
      }
    }
    final key = GlobalKey();
    final tokens = AppTokens.fromId(AppThemeId.aether);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[
        AppThemeExtension(tokens),
      ]),
      home: Scaffold(
        backgroundColor: tokens.bg0,
        body: RepaintBoundary(
          key: key,
          child: OrreryView(
            model: m,
            repoLabel: 'manifold',
            initialPinned: pinned,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final boundary =
        tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      await _writeImage(image, '.preview/orrery_REAL_page.png');
    });
  });
}
