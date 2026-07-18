// tool/diff_load_sweep.dart — the growth-law harness.
//
// Runs diff_load_profiler.dart across a geometric size ladder (each rung a fresh
// child process), fits a growth law per stage, and EXTRAPOLATES to marble scale
// so we characterise the crash point without ever running it. This is the
// "prediction, not information-takes-time" answer applied to the profiling
// itself: measure small safe samples, fit the curve, predict the rest.
//
// Safety: rungs run one at a time; a stage's ladder stops as soon as a measured
// peak crosses --stop-mb, and larger sizes are extrapolated instead of run.
//
// Usage:
//   dart run tool/diff_load_sweep.dart [--stages=eager,index,lazy,slice]
//     [--files=4] [--budget-mb=1536] [--stop-mb=1100] [--max-mb=128]
//     [--targets-mb=341,1024]

import 'dart:convert';
import 'dart:io';

const int _mib = 1024 * 1024;

class _Sample {
  final int inputBytes;
  final double stageDelta;
  final double peakOverBase;
  final int maxRss;
  final int wallMs;
  final String status;
  _Sample(this.inputBytes, this.stageDelta, this.peakOverBase, this.maxRss,
      this.wallMs, this.status);
}

/// Ordinary least squares on (x,y). Returns (slope, intercept, r2).
(double, double, double) _ols(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 2) return (0, ys.isEmpty ? 0 : ys.first, 0);
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
    syy += (ys[i] - my) * (ys[i] - my);
  }
  final slope = sxx == 0 ? 0.0 : sxy / sxx;
  final intercept = my - slope * mx;
  final r2 = syy == 0 ? 1.0 : (sxy * sxy) / (sxx * syy);
  return (slope, intercept, r2);
}

String _mb(num bytes) => '${(bytes / _mib).toStringAsFixed(1)}MB';
String _gb(num bytes) => '${(bytes / (1024 * _mib)).toStringAsFixed(2)}GB';

Future<_Sample?> _runRung(
    String stage, int bytes, int files, int budgetMb) async {
  final r = await Process.run(
    'dart',
    [
      'run',
      'tool/diff_load_profiler.dart',
      '--stage=$stage',
      '--bytes=$bytes',
      '--files=$files',
      '--budget-mb=$budgetMb',
    ],
    workingDirectory: Directory.current.path,
  );
  if (r.exitCode != 0) {
    stderr.writeln('  rung ${_mb(bytes)} $stage: exit ${r.exitCode} '
        '(likely OOM-killed) — recording as death point');
    return null;
  }
  final line = (r.stdout as String)
      .split('\n')
      .lastWhere((l) => l.trim().startsWith('{'), orElse: () => '');
  if (line.isEmpty) return null;
  final j = jsonDecode(line) as Map<String, Object?>;
  return _Sample(
    (j['inputBytes']! as num).toInt(),
    (j['stageDeltaBytes']! as num).toDouble(),
    (j['peakOverBaseBytes']! as num).toDouble(),
    (j['maxRss']! as num).toInt(),
    (j['wallMs']! as num).toInt(),
    j['status']! as String,
  );
}

Future<void> main(List<String> argv) async {
  final args = <String, String>{};
  for (final a in argv) {
    if (!a.startsWith('--')) continue;
    final eq = a.indexOf('=');
    args[a.substring(2, eq < 0 ? a.length : eq)] =
        eq < 0 ? 'true' : a.substring(eq + 1);
  }
  final stages = (args['stages'] ?? 'eager,index,lazy,slice').split(',');
  final files = int.parse(args['files'] ?? '4');
  final budgetMb = int.parse(args['budget-mb'] ?? '1536');
  final stopBytes = int.parse(args['stop-mb'] ?? '1100') * _mib;
  final maxMb = int.parse(args['max-mb'] ?? '128');
  final targets = (args['targets-mb'] ?? '341,1024')
      .split(',')
      .map((s) => int.parse(s) * _mib)
      .toList();

  final ladder = <int>[];
  for (var mb = 1; mb <= maxMb; mb *= 2) {
    ladder.add(mb * _mib);
  }

  stdout.writeln('=' * 78);
  stdout.writeln('DIFF LOAD GROWTH LAW  (files=$files, budget=${budgetMb}MB, '
      'stop=${_mb(stopBytes)})');
  stdout.writeln('=' * 78);

  for (final stage in stages) {
    stdout.writeln('\n### stage: $stage');
    stdout.writeln('  ${'input'.padLeft(9)}  ${'stageΔ'.padLeft(9)}  '
        '${'Δ/byte'.padLeft(7)}  ${'peak'.padLeft(9)}  ${'peak/B'.padLeft(7)}  '
        '${'wall'.padLeft(6)}');
    final samples = <_Sample>[];
    for (final bytes in ladder) {
      final s = await _runRung(stage, bytes, files, budgetMb);
      if (s == null) {
        stdout.writeln('  ${_mb(bytes).padLeft(9)}  DIED (OOM) — stopping '
            'ladder, extrapolating from here');
        break;
      }
      samples.add(s);
      stdout.writeln('  ${_mb(s.inputBytes).padLeft(9)}  '
          '${_mb(s.stageDelta).padLeft(9)}  '
          '${(s.stageDelta / s.inputBytes).toStringAsFixed(2).padLeft(7)}  '
          '${_mb(s.peakOverBase).padLeft(9)}  '
          '${(s.peakOverBase / s.inputBytes).toStringAsFixed(2).padLeft(7)}  '
          '${'${s.wallMs}ms'.padLeft(6)}');
      if (s.maxRss > stopBytes) {
        stdout.writeln('  (peak crossed stop threshold — extrapolating beyond)');
        break;
      }
    }
    // Drop warm-up rungs: the Dart VM grows its heap in ~30MB steps on first
    // use, so runs below ~8MB report that one-time headroom as "stage cost".
    // The asymptotic multiplier only reveals itself once the input dwarfs the
    // VM's fixed headroom. Fit on the clean tail (≥ 8MB), needing ≥3 points.
    const warmupCutoff = 8 * _mib;
    final fitSamples =
        samples.where((s) => s.inputBytes >= warmupCutoff).toList();
    if (fitSamples.length < 2) {
      stdout.writeln('  too few post-warmup samples to fit '
          '(need larger --max-mb)');
      continue;
    }
    final largest = fitSamples.last;
    final asymDelta = largest.stageDelta / largest.inputBytes;
    final asymPeak = largest.peakOverBase / largest.inputBytes;

    // Linear fit of the STAGE marginal (peak over the resident input): this is
    // the "objects the stage mints per input byte" — the multiplier that either
    // stays flat (bounded, safe) or climbs (the OOM). peakOverBase is monotone
    // and clean; stageDelta is the marginal but noisier, so we fit both.
    final xs = fitSamples.map((s) => s.inputBytes.toDouble()).toList();
    final ysDelta = fitSamples.map((s) => s.stageDelta).toList();
    final ysPeak = fitSamples.map((s) => s.peakOverBase).toList();
    final (slopeD, interD, r2D) = _ols(xs, ysDelta);
    final (slopeP, interP, r2P) = _ols(xs, ysPeak);

    stdout.writeln('  fit (≥8MB): stage-marginal Δ ≈ '
        '${slopeD.toStringAsFixed(2)}·B + ${_mb(interD)}  '
        '(R²=${r2D.toStringAsFixed(3)})');
    stdout.writeln('              peak-over-base  ≈ '
        '${slopeP.toStringAsFixed(2)}·B + ${_mb(interP)}  '
        '(R²=${r2P.toStringAsFixed(3)})');
    stdout.writeln('  asymptotic (largest rung ${_mb(largest.inputBytes)}): '
        'stage-marginal ${asymDelta.toStringAsFixed(2)}×/byte, '
        'peak ${asymPeak.toStringAsFixed(2)}×/byte');

    final bounded = slopeD < 0.5;
    stdout.writeln('  verdict: ${bounded ? 'BOUNDED — stage mints ≈0 objects '
        'per input byte; cost is the input buffer itself (safe at any size)' :
        'COSTLY — stage mints ≈ ${slopeD.toStringAsFixed(1)}× the input in '
        'objects (this is the OOM term)'}');

    for (final t in targets) {
      // Peak RSS at target ≈ input buffer + stage marginal. Use the peak-over-
      // base slope (includes the buffer) as the headline; note the stage term.
      final predPeak = slopeP * t + interP;
      final predStage = slopeD * t + interD;
      stdout.writeln('       → at ${_mb(t)}: peak ≈ ${_gb(predPeak)} '
          '(of which stage objects ≈ ${_gb(predStage < 0 ? 0 : predStage)})');
    }
  }
  stdout.writeln('\n${'=' * 78}');
}
