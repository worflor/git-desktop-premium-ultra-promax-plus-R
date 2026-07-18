// diff_smoothness_lab_test.dart — steady-state frame-cost instrument for
// DiffShell.
//
// WHY THIS EXISTS: every prior diff-perf instrument (tool/diff_load_profiler,
// tool/diff_load_sweep, the parse-side lean gates) measures LOAD — parse wall
// time and peak RSS. The marble regression proved smoothness dies AFTER load:
// with a multi-hundred-k-line new-file diff mounted, hover, scroll, and
// clicks all jank, and no existing gate could see it. This lab measures the
// STEADY STATE: wall-clock per pumped frame while scripted interaction runs
// against the real DiffShell over the production spool backing, across a
// matrix of file shapes.
//
// THE LAW (universality): once the document is mounted, the cost of a frame
// must scale with the VIEWPORT (~50 rows), never with the document (line
// count, line length, file count). Each monster shape is gated against the
// small control shape by ratio, so the gate is self-calibrating on any
// machine — no absolute ms SLA that flakes on a loaded runner.
//
// Phases measured per shape:
//   mount   — pump + hydrate until the first row renders (informational; the
//             load story is already covered by the tool/ profilers).
//   idle    — pump() with no input. Catches "something rebuilds/animates
//             every frame".
//   rebuild — a parent setState forcing a full shell rebuild. This is the
//             exact cost a row-hover pays in production (_hoveredLine
//             setState rebuilds the whole shell), reproduced without
//             needing a repositoryPath/blame pipeline.
//   hover   — a real mouse pointer sweeping down the rows, pump per move.
//             Catches hit-test / MouseRegion cost across per-row regions.
//   vscroll — drag-scrolls down the list. Catches row (re)build + hydration
//             cost per frame of scrolling.
//   hscroll — drag-scrolls sideways (long-line shapes). Catches wide-layout
//             cost.
//
// Wall-clock, medians, MANIFOLD_TIMING_SCALE respected — same philosophy as
// test/ui/jank_budget_test.dart: order-of-magnitude gates, not p95 SLAs.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_shell.dart';
import 'package:git_desktop/ui/tokens.dart';

import '../../support/widget_harness.dart';

/// Marker rendered by the first row of every generated file so hydration can
/// be awaited without coupling to shape-specific content.
const String _kFirstRowMark = 'MARKFIRSTROW';

/// Same escape hatch as jank_budget_test.dart: widen every bound on a loaded
/// runner with MANIFOLD_TIMING_SCALE=N.
double _timingScale() {
  final scale = double.tryParse(
    Platform.environment['MANIFOLD_TIMING_SCALE'] ?? '',
  );
  return scale != null && scale > 0 ? scale : 1.0;
}

/// One synthetic corpus shape. [gen] emits a full unified diff (new-file
/// form — exactly what git produces for the marble road-graph corpus).
class _Shape {
  final String name;
  final String Function() gen;
  final bool measureHScroll;
  const _Shape(this.name, this.gen, {this.measureHScroll = false});
}

/// New-file unified diff: [files] files × [linesPerFile] added lines of
/// [lineBody]-shaped content. Deterministic (seeded LCG), DIMACS-flavored
/// short lines by default — the literal marble shape.
String _newFileDiff({
  required int files,
  required int linesPerFile,
  String Function(int rng)? lineBody,
}) {
  final sb = StringBuffer();
  var rng = 0x5eed;
  int next() {
    rng = (rng * 1664525 + 1013904223) & 0x7fffffff;
    return rng;
  }

  for (var f = 0; f < files; f++) {
    final name = 'graph_$f.gr';
    sb
      ..write('diff --git a/$name b/$name\n')
      ..write('new file mode 100644\n')
      ..write('index 0000000..1111111\n')
      ..write('--- /dev/null\n')
      ..write('+++ b/$name\n')
      ..write('@@ -0,0 +1,$linesPerFile @@\n');
    for (var i = 0; i < linesPerFile; i++) {
      sb.write('+');
      if (i == 0) {
        sb.write('$_kFirstRowMark ');
      }
      if (lineBody != null) {
        sb.write(lineBody(next()));
      } else {
        // DIMACS arc line: `a <tail> <head> <weight>` — mean length ~22.
        sb.write('a ${next() % 90000000 + 1000000} '
            '${next() % 90000000 + 1000000} ${next() % 900 + 100}');
      }
      sb.write('\n');
    }
  }
  return sb.toString();
}

String _longLine(int rng, int chars) {
  final unit = 'x${rng % 10} ';
  final sb = StringBuffer();
  while (sb.length < chars) {
    sb.write(unit);
  }
  return sb.toString();
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  return s.isEmpty ? 0 : s[s.length ~/ 2];
}

class _Report {
  final String shape;
  final int approxLines;
  final Map<String, double> phaseMs = {};
  _Report(this.shape, this.approxLines);
}

void main() {
  // Timing purity: leak_tracker's per-object bookkeeping inflates exactly
  // what this file measures (see jank_budget_test.dart for the precedent).
  LeakTesting.settings = LeakTesting.settings.withIgnoredAll();

  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });

  late Directory tmp;
  setUp(() async {
    await installHermeticStorageSeams();
    tmp = await Directory.systemTemp.createTemp('diff_smoothness_lab_');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
  });

  // The shape matrix. Sizes chosen to expose O(document) work while keeping
  // the suite runnable as a plain widget test (the marble corpus is 700k+
  // lines/file; 300k is comfortably past every threshold in the pipeline,
  // including kLeanDiffLineThreshold).
  final shapes = <_Shape>[
    _Shape('control', () => _newFileDiff(files: 1, linesPerFile: 300)),
    _Shape(
      'mega-lines',
      () => _newFileDiff(files: 1, linesPerFile: 300000),
    ),
    _Shape(
      'multi-mega',
      () => _newFileDiff(files: 3, linesPerFile: 120000),
    ),
    _Shape(
      'long-lines',
      () => _newFileDiff(
        files: 1,
        linesPerFile: 2000,
        lineBody: (rng) => _longLine(rng, 2000),
      ),
      measureHScroll: true,
    ),
    _Shape(
      'monster-line',
      () => _newFileDiff(
        files: 1,
        linesPerFile: 60,
        lineBody: (rng) => _longLine(rng, rng % 7 == 0 ? 500000 : 40),
      ),
      measureHScroll: true,
    ),
  ];

  testWidgets(
    'steady-state frame cost scales with the viewport, not the document',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Warm-up mount: pay the one-time provider/JIT/font cost outside any
      // measurement (same rationale as jank_budget_test.dart's warm-up).
      await pumpHarness(tester, const Scaffold(body: SizedBox.shrink()));

      final reports = <String, _Report>{};

      for (final shape in shapes) {
        // --- corpus → spool file → production lazy document ---
        final raw = shape.gen();
        final approxLines = '\n'.allMatches(raw).length;
        final spool = File(
          '${tmp.path}${Platform.pathSeparator}${shape.name}.diff',
        );
        final doc = (await tester.runAsync(() async {
          await spool.writeAsString(raw);
          return DiffDocument.lazyFromSpool(
            spool.path,
            documentId: 'lab:${shape.name}',
          );
        }))!;

        final report = _Report(shape.name, approxLines);
        reports[shape.name] = report;
        final rebuildTick = ValueNotifier<int>(0);

        // --- mount ---
        final mountSw = Stopwatch()..start();
        await pumpHarness(
          tester,
          Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: rebuildTick,
              builder: (_, tick, _) => DiffShell(
                filePath: 'graph_0.gr',
                tokens: AppTokens.fromId(AppThemeId.aether),
                document: doc,
                enableStaging: true,
                // Changing label forces a full DiffShell rebuild — the same
                // cost a production row-hover setState pays.
                toolbarLabel: 'tick $tick',
              ),
            ),
          ),
        );
        final mark = find.textContaining(_kFirstRowMark, findRichText: true);
        for (var i = 0; i < 200 && mark.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        mountSw.stop();
        expect(
          mark,
          findsWidgets,
          reason: '${shape.name}: first row must hydrate and render',
        );
        report.phaseMs['mount'] = mountSw.elapsedMicroseconds / 1000.0;

        Future<double> phase(
          int reps,
          Future<void> Function(int i) action, {
          int warmup = 2,
        }) async {
          for (var i = 0; i < warmup; i++) {
            await action(i);
          }
          final samples = <double>[];
          for (var i = 0; i < reps; i++) {
            final sw = Stopwatch()..start();
            await action(i);
            sw.stop();
            samples.add(sw.elapsedMicroseconds / 1000.0);
          }
          return _median(samples);
        }

        // --- idle ---
        report.phaseMs['idle'] = await phase(
          10,
          (_) => tester.pump(const Duration(milliseconds: 16)),
        );

        // --- rebuild (hover-setState proxy) ---
        report.phaseMs['rebuild'] = await phase(10, (_) async {
          rebuildTick.value++;
          await tester.pump();
        });

        // --- hover (real mouse sweep) ---
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: const Offset(500, 120));
        await tester.pump();
        var hoverY = 140.0;
        report.phaseMs['hover'] = await phase(10, (_) async {
          hoverY = hoverY >= 820 ? 140.0 : hoverY + 60.0;
          await gesture.moveTo(Offset(500, hoverY));
          await tester.pump();
        });
        await gesture.removePointer();
        await tester.pump();

        // --- vertical scroll ---
        final scrollable = find.byType(Scrollable).first;
        report.phaseMs['vscroll'] = await phase(8, (_) async {
          await tester.drag(
            scrollable,
            const Offset(0, -500),
            warnIfMissed: false,
          );
          await tester.pump();
        });

        // --- horizontal scroll (wide shapes only) ---
        if (shape.measureHScroll) {
          report.phaseMs['hscroll'] = await phase(8, (_) async {
            await tester.drag(
              scrollable,
              const Offset(-500, 0),
              warnIfMissed: false,
            );
            await tester.pump();
          });
        }

        expect(
          tester.takeException(),
          isNull,
          reason: '${shape.name}: interaction must not throw',
        );

        // Unmount before disposing the doc so hydration never reads a
        // closed spool store.
        await tester.pumpWidget(const SizedBox.shrink());
        rebuildTick.dispose();
        await tester.runAsync(() async => doc.dispose());
      }

      // --- report table ---
      const phases = ['mount', 'idle', 'rebuild', 'hover', 'vscroll', 'hscroll'];
      final sb = StringBuffer()
        ..writeln('')
        ..writeln('diff smoothness lab — median ms per frame '
            '(wall clock, debug VM)')
        ..writeln(
          '${'shape'.padRight(14)}${'lines'.padLeft(9)}'
          '${phases.map((p) => p.padLeft(10)).join()}',
        );
      for (final r in reports.values) {
        sb
          ..write(r.shape.padRight(14))
          ..write('${r.approxLines}'.padLeft(9));
        for (final p in phases) {
          final v = r.phaseMs[p];
          sb.write((v == null ? '-' : v.toStringAsFixed(1)).padLeft(10));
        }
        sb.writeln();
      }
      // ignore: avoid_print
      print(sb);

      // --- universality gates ---
      // Self-calibrating: each monster shape vs the control shape, ratio 10×
      // with an absolute floor so sub-ms control medians don't make the gate
      // impossibly tight. Order-of-magnitude guards, deliberately.
      final control = reports['control']!;
      final scale = _timingScale();
      for (final r in reports.values) {
        if (identical(r, control)) continue;
        for (final p in ['idle', 'rebuild', 'hover', 'vscroll']) {
          final v = r.phaseMs[p]!;
          final c = control.phaseMs[p]!;
          final limit = math.max(50.0 * scale, c * 10 + 20.0 * scale);
          expect(
            v,
            lessThan(limit),
            reason:
                '${r.shape}/$p: ${v.toStringAsFixed(1)}ms vs control '
                '${c.toStringAsFixed(1)}ms (limit ${limit.toStringAsFixed(1)}ms) '
                '— steady-state frame cost must scale with the viewport, '
                'not the document',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
