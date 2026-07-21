// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

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

import 'orrery_test_harness.dart';

// The monorepo root, resolved portably: `flutter test` runs with
// apps/desktop-flutter as CWD on every OS (including the WSL worktree), so a
// hardcoded Windows path would fail everywhere but the machine it was written
// on — Linux included.
final _repo = Directory.current.parent.parent.path;

Future<void> _writeImage(ui.Image image, String path) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose(); // ui.Image holds native memory — release it (leak_tracker)
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
      print('FINDING [${f.kind.name}] @${f.anchor} ${f.headline}');
    }

    // Disk-only, straight to a picture (fast, no widget tree).
    await tester.runAsync(() async {
      final colors =
          OrreryColors.fromTokens(AppTokens.fromId(AppThemeId.aether));
      final recorder = ui.PictureRecorder();
      const size = Size(900, 900);
      final canvas = Canvas(recorder, Offset.zero & size);
      OrreryPainter(model: m, head: m.headPosition, colors: colors)
          .paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(900, 900);
      picture.dispose(); // Picture holds native memory too — release it
      await _writeImage(image, '.preview/orrery_REAL_disk.png');
    });

    // Aggregated module view — the legible-at-scale default. Print what it
    // collapsed to (label · member count · churn) and render it.
    final modules = OrreryModel.aggregateByModule(m);
    // ignore: avoid_print
    print('MODULES: ${modules.nodes.length} (from ${m.nodes.length} files)');
    final byChurn = [...modules.nodes]
      ..sort((a, b) => b.churn.compareTo(a.churn));
    for (final n in byChurn.take(12)) {
      // ignore: avoid_print
      print('  ${n.path}  ·  ${n.memberCount} files  ·  '
          'churn ${n.churn.toStringAsFixed(2)}');
    }
    await tester.runAsync(() async {
      final colors =
          OrreryColors.fromTokens(AppTokens.fromId(AppThemeId.aether));
      final recorder = ui.PictureRecorder();
      const size = Size(900, 900);
      final canvas = Canvas(recorder, Offset.zero & size);
      OrreryPainter(model: modules, head: modules.headPosition, colors: colors)
          .paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(900, 900);
      picture.dispose(); // Picture holds native memory too — release it
      await _writeImage(image, '.preview/orrery_REAL_modules.png');
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
    await tester.pumpWidget(orreryTestApp(
      theme: AppThemeId.aether,
      home: Scaffold(
        backgroundColor: tokens.bg0,
        body: RepaintBoundary(
          key: key,
          child: OrreryView(
            model: m,
            repoLabel: 'manifold',
            initialPinned: pinned,
            initialLod:
                OrreryLod.files, // this shot tests file-level drill-down
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

    // Drill-in: the biggest module expanded to its files, the rest collapsed.
    final biggest = (modules.nodes.toList()
          ..sort((a, b) => b.memberCount.compareTo(a.memberCount)))
        .first
        .path!;
    final xkey = GlobalKey();
    await tester.pumpWidget(orreryTestApp(
      theme: AppThemeId.aether,
      home: Scaffold(
        backgroundColor: tokens.bg0,
        body: RepaintBoundary(
          key: xkey,
          child: OrreryView(
              model: m, repoLabel: 'manifold', initialExpand: biggest),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final xboundary =
        tester.renderObject(find.byKey(xkey)) as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await xboundary.toImage(pixelRatio: 1.5);
      await _writeImage(image, '.preview/orrery_REAL_drillin.png');
    });

    // The actual default first impression: module view, scrub, nothing pinned.
    final dkey = GlobalKey();
    await tester.pumpWidget(orreryTestApp(
      theme: AppThemeId.aether,
      home: Scaffold(
        backgroundColor: tokens.bg0,
        body: RepaintBoundary(
          key: dkey,
          child: OrreryView(model: m, repoLabel: 'manifold'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final dboundary =
        tester.renderObject(find.byKey(dkey)) as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await dboundary.toImage(pixelRatio: 1.5);
      await _writeImage(image, '.preview/orrery_REAL_default.png');
    });

    // Compare mode — static small-multiples at the regime boundaries.
    final ckey = GlobalKey();
    await tester.pumpWidget(orreryTestApp(
      theme: AppThemeId.aether,
      home: Scaffold(
        backgroundColor: tokens.bg0,
        body: RepaintBoundary(
          key: ckey,
          child: OrreryView(
            model: m,
            repoLabel: 'manifold',
            initialMode: OrreryMode.compare,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final cboundary =
        tester.renderObject(find.byKey(ckey)) as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await cboundary.toImage(pixelRatio: 1.5);
      await _writeImage(image, '.preview/orrery_REAL_compare.png');
    });
  });
}
