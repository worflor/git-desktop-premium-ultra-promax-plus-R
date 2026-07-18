// ingestion_lifecycle_test.dart — WHY THIS EXISTS: the marble repo-switch
// incident took the whole developer machine down. A repo with a few
// multi-hundred-MB working-tree files got opened, the analysis pipelines
// (flow analysis, the combined diff fetch) fanned out uncapped reads of
// every status path — several concurrently — and the resulting memory
// pressure OOM-killed the process, and on some machines came close to
// pagefile death for the whole OS. lib/backend/analysis_admission.dart
// exists to make that bug class structurally impossible; this test exists
// so the machine-scale ingestion lifecycle (open -> analyze -> diff ->
// switch repos) is exercised and its memory behaviour is GATED, without
// ever risking the developer's actual machine to test it — the scenario
// runs entirely inside a spawned CHILD process
// (tool/memory_lab.dart), which is physically unable to OOM this test
// runner: the worst that child process can do is die on its own.
//
// This test only spawns that child and asserts on the JSON verdict it
// prints to stdout. It never touches the scenario repos or pipelines
// directly.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Same escape hatch as test/ui/jank_budget_test.dart's budgetMs: a loaded
/// CI box can widen every wall-clock bound here with
/// `MANIFOLD_TIMING_SCALE=3 flutter test …`. Kept for the process timeout
/// below; the memory gates themselves are not time-based.
int _scaledMs(int baseMs) {
  final scale = double.tryParse(
    Platform.environment['MANIFOLD_TIMING_SCALE'] ?? '',
  );
  return (baseMs * (scale != null && scale > 0 ? scale : 1.0)).round();
}

// `dart` on Windows resolves to a `.bat` wrapper (the plain-Dart-VM `.exe` is
// buried under bin/cache), which native `CreateProcess` won't resolve
// without going through a shell — hence `runInShell` on Windows for both the
// PATH probe and the actual scenario spawn below.
bool _onPath(String exe) {
  try {
    final r = Process.runSync(
      exe,
      ['--version'],
      runInShell: Platform.isWindows,
    );
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

String? _skipReason() {
  if (!_onPath('dart')) return '`dart` not found on PATH';
  if (!_onPath('git')) return '`git` not found on PATH';
  return null;
}

/// Spawns `dart run tool/memory_lab.dart --scenario=$scenario` and parses
/// its single JSON verdict line off stdout. The scenario repos (up to
/// ~580MB of scratch data for `heavy`/`switch`) are built AND deleted
/// entirely inside the child; this only ever sees its stdout.
Future<Map<String, dynamic>> _runScenario(String scenario) async {
  final result = await Process.run(
    'dart',
    [
      'run',
      'tool/memory_lab.dart',
      '--scenario=$scenario',
      '--budget-mb=2048',
    ],
    workingDirectory: Directory.current.path,
    runInShell: Platform.isWindows,
  ).timeout(Duration(milliseconds: _scaledMs(10 * 60 * 1000)));

  if (result.exitCode != 0) {
    fail(
      'memory_lab scenario=$scenario exited ${result.exitCode}\n'
      'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
  }

  // The tool emits exactly one JSON object; find the last non-empty line
  // (stderr notes go to stderr, but be defensive about any stray stdout).
  final lines = (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    fail('memory_lab scenario=$scenario produced no stdout output');
  }
  return jsonDecode(lines.last) as Map<String, dynamic>;
}

const int _mib = 1024 * 1024;

void main() {
  final skipReason = _skipReason();

  for (final scenario in ['normal', 'heavy', 'switch']) {
    test(
      'ingestion lifecycle ($scenario) stays inside memory laws',
      () async {
        final verdict = await _runScenario(scenario);

        // The old bug class recurring, by definition: the sandboxed run
        // itself crossed the watchdog budget.
        expect(
          verdict['status'],
          'ok',
          reason: 'scenario=$scenario verdict: $verdict',
        );

        final baseRss = (verdict['baseRss'] as num).toInt();
        final peakRss = (verdict['peakRss'] as num).toInt();
        final endRss = (verdict['endRss'] as num).toInt();
        final retainedOverBase = (verdict['retainedOverBase'] as num).toInt();

        if (scenario == 'heavy' || scenario == 'switch') {
          // Generous over the 64MB admission budget: pipeline expansion
          // (UTF-16 strings, isolate message copies, parsed structures) plus
          // VM baseline is expected to multiply that, but the OLD regime was
          // multi-GB / pagefile death, not a few hundred MB over base.
          expect(
            peakRss - baseRss,
            lessThan(1200 * _mib),
            reason:
                'scenario=$scenario peak-over-base too large: '
                '${(peakRss - baseRss) / _mib}MB. Full verdict: $verdict',
          );
        }

        // Retention law: nothing pins the working set after the lifecycle
        // completes and every reference is dropped, for ANY scenario size.
        expect(
          retainedOverBase,
          lessThan(500 * _mib),
          reason:
              'scenario=$scenario retained ${retainedOverBase / _mib}MB '
              'over base after settling. Full verdict: $verdict',
        );

        // The admission budget must fully drain — no leaked reservations,
        // no stuck queue, regardless of how much ingestion pressure the
        // scenario applied.
        expect(
          verdict['admissionEndInFlight'],
          0,
          reason: 'scenario=$scenario verdict: $verdict',
        );
        expect(
          verdict['admissionEndQueued'],
          0,
          reason: 'scenario=$scenario verdict: $verdict',
        );

        expect(endRss, greaterThan(0)); // sanity: field actually populated
      },
      timeout: Timeout(Duration(milliseconds: _scaledMs(10 * 60 * 1000))),
      skip: skipReason,
    );
  }
}
