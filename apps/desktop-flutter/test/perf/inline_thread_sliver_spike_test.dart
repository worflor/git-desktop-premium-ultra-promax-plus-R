// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// inline_thread_sliver_spike_test.dart — can the diff carry inline threads?
//
// A THROWAWAY MEASUREMENT for the margin redesign, not a gate. Delete it
// once the question is answered either way.
//
// THE QUESTION. DiffShell renders code as `SliverFixedExtentList` runs,
// which is where its scroll performance comes from. The margin design wants
// review threads mounted inline at their anchored line. Dropping
// variable-height rows INTO a fixed-extent list is not possible, but the
// shell already interleaves variable-height `SliverToBoxAdapter` segments
// between fixed-extent runs — that is how binary files render, complete
// with a size reporter that measures height after layout and feeds it back
// via setState.
//
// So the mechanism exists. What does not exist is evidence about COUNT: a
// binary segment appears once or twice per diff, whereas a contested file
// could carry forty threads, and each measured segment's first layout costs
// a setState that rebuilds the subtree. Forty of those interleaved with
// forty-one fixed runs is the case nobody has run.
//
// WHY NOT SPIKE DiffShell ITSELF. That would mean adding a thread-segment
// parameter to production code to answer a question that might say "no" —
// building the feature to find out whether to build it. This reproduces the
// shell's sliver STRUCTURE instead (fixed-extent runs + measured box
// adapters + report-on-change), so the answer transfers without the code
// having to.

@Timeout(Duration(minutes: 5))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rows of code between two threads, and the row height. Roughly a real
/// diff: threads cluster but do not sit on adjacent lines.
const double _kRowExtent = 18.0;
const int _kRowsPerRun = 60;
const int _kThreadCount = 40;

/// A collapsed thread row is one line tall; an expanded one is a paragraph.
/// Both are measured rather than assumed, which is the whole cost question.
const double _kCollapsedHeight = 22.0;
const double _kExpandedHeight = 190.0;

/// Reports its rendered height once it settles, the way the shell's binary
/// segments do. The >1px guard is the shell's, kept so the churn profile
/// matches: without it every layout pass would report and the measurement
/// would be of the guard's absence rather than of the mechanism.
class _MeasuredSegment extends StatefulWidget {
  final double height;
  final ValueChanged<double> onSize;
  const _MeasuredSegment({required this.height, required this.onSize});

  @override
  State<_MeasuredSegment> createState() => _MeasuredSegmentState();
}

class _MeasuredSegmentState extends State<_MeasuredSegment> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) widget.onSize(box.size.height);
    });
    return SizedBox(
      height: widget.height,
      child: const ColoredBox(color: Color(0xFF202020)),
    );
  }
}

class _Harness extends StatefulWidget {
  /// 0 = the baseline: one uninterrupted fixed-extent run.
  final int threads;
  final bool expanded;
  final ScrollController controller;
  const _Harness({
    super.key,
    required this.threads,
    required this.expanded,
    required this.controller,
  });

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  /// Measured heights, exactly as the shell caches `seg.renderedHeight`.
  final Map<int, double> _heights = {};
  int reports = 0;

  void _report(int i, double h) {
    final known = _heights[i];
    if (known != null && (known - h).abs() <= 1.0) return;
    reports++;
    setState(() => _heights[i] = h);
  }

  @override
  Widget build(BuildContext context) {
    final runs = widget.threads == 0 ? 1 : widget.threads + 1;
    final rows = widget.threads == 0
        ? _kRowsPerRun * (_kThreadCount + 1)
        : _kRowsPerRun;
    return CustomScrollView(
      controller: widget.controller,
      slivers: [
        for (var r = 0; r < runs; r++) ...[
          SliverFixedExtentList(
            itemExtent: _kRowExtent,
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => Text(
                'line ${r * _kRowsPerRun + i}  final lease = staged ?? zero;',
                maxLines: 1,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
              childCount: rows,
            ),
          ),
          if (r < widget.threads)
            SliverToBoxAdapter(
              child: _MeasuredSegment(
                height:
                    widget.expanded ? _kExpandedHeight : _kCollapsedHeight,
                onSize: (h) => _report(r, h),
              ),
            ),
        ],
      ],
    );
  }
}

void main() {
  Future<({double mountMs, double worstFrameMs, double meanFrameMs, int reports})>
      run(
    WidgetTester tester, {
    required int threads,
    required bool expanded,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final key = GlobalKey<_HarnessState>();

    final mount = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _Harness(
          key: key,
          threads: threads,
          expanded: expanded,
          controller: controller,
        ),
      ),
    ));
    await tester.pump();
    mount.stop();

    // Scroll the whole document in viewport-sized steps, which is what
    // forces each segment through its first layout and its one report.
    final samples = <double>[];
    for (var i = 0; i < 60; i++) {
      final sw = Stopwatch()..start();
      controller.jumpTo(i * 700.0);
      await tester.pump();
      sw.stop();
      samples.add(sw.elapsedMicroseconds / 1000.0);
    }
    samples.sort();
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    return (
      mountMs: mount.elapsedMicroseconds / 1000.0,
      worstFrameMs: samples.last,
      meanFrameMs: mean,
      reports: key.currentState!.reports,
    );
  }

  testWidgets('inline thread segments vs a pure fixed-extent diff',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Warm-up, discarded. The first run pays JIT, font and raster
    // warm-up: the initial version of this spike reported 528 / 116 / 63
    // ms in run order and the "improvement" was entirely that. Measuring
    // the order of the cases instead of the cases is exactly the class of
    // lying instrument this feature has already produced three times.
    await run(tester, threads: _kThreadCount, expanded: false);

    final base = await run(tester, threads: 0, expanded: false);
    final collapsed = await run(tester, threads: _kThreadCount, expanded: false);
    final expanded = await run(tester, threads: _kThreadCount, expanded: true);
    // Re-measure the baseline LAST. If the two baselines disagree, the
    // bench is still drifting and none of the middle rows mean anything.
    final baseAgain = await run(tester, threads: 0, expanded: false);

    String row(String name, ({
      double mountMs,
      double worstFrameMs,
      double meanFrameMs,
      int reports
    }) r) =>
        '  ${name.padRight(26)}'
        '${r.mountMs.toStringAsFixed(1).padLeft(8)}'
        '${r.meanFrameMs.toStringAsFixed(2).padLeft(10)}'
        '${r.worstFrameMs.toStringAsFixed(2).padLeft(10)}'
        '${r.reports.toString().padLeft(10)}';

    // ignore: avoid_print
    print([
      '',
      'INLINE THREAD SLIVER SPIKE '
          '($_kThreadCount threads, $_kRowsPerRun rows between)',
      '',
      '  case                        mount ms  mean frame worst frame   reports',
      row('fixed-extent only', base),
      row('+40 collapsed threads', collapsed),
      row('+40 expanded threads', expanded),
      row('fixed-extent only (again)', baseAgain),
      '',
      'reports = height callbacks that actually changed a cached value,',
      'i.e. the setState churn the mechanism costs. One per segment is the',
      'floor; per-scroll churn would be the disqualifying result.',
      '',
    ].join('\n'));

    // The only hard claim: interleaving must not turn a scroll into a
    // rebuild storm. One settling report per segment is expected and fine.
    expect(collapsed.reports, lessThanOrEqualTo(_kThreadCount * 2),
        reason: 'height reporting must settle, not repeat per scroll');
    expect(expanded.reports, lessThanOrEqualTo(_kThreadCount * 2),
        reason: 'height reporting must settle, not repeat per scroll');
    // Drift guard: the two baseline measurements bracket the others, so
    // if they disagree badly the timings are noise and must not be read.
    final drift = (base.meanFrameMs - baseAgain.meanFrameMs).abs() /
        ((base.meanFrameMs + baseAgain.meanFrameMs) / 2);
    expect(drift, lessThan(0.35),
        reason: 'baseline drifted ${(drift * 100).toStringAsFixed(0)}% '
            'between first and last measurement — timings are not readable');
  });
}
