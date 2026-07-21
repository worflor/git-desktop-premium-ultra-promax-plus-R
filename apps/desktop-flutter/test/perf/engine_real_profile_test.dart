// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

@Tags(['manual'])
library;

// engine_real_profile_test.dart — REAL profiling of the core Manifold engine on
// REAL repos on this disk. Not a unit test: it runs the production cold-build
// pipeline (git log → computeFileCoupling → collectLogosGitStats → buildFromStats
// → queries) on actual repositories and prints a per-phase wall-clock breakdown,
// separating I/O (git subprocess) from compute (buildFromStats internal phases,
// via the engine's own probeTimingsUs) from interactive queries.
//
//   run:  flutter test --run-skipped -t manual --no-pub \
//           test/perf/engine_real_profile_test.dart
//         (tagged `manual` in dart_test.yaml; skipped by default)
//
// Profiles the CORE 4-axis build (no engram K-vectors — the EN axis needs asset
// bundles unavailable in `flutter test`; scoreLoop / calibration / spectral are
// the core and run identically). Engram is a separate subsystem.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_stats.dart';

const _projects = r'C:\Users\mini server\Documents\Projects';

final _repos = <(String, String)>[
  ('git-desktop  (613f/193c)', '$_projects\\git-desktop-premium-ultra-promax-plus-R'),
  ('worflor.io   (203f/531c)', '$_projects\\worflor.github.io'),
  ('wdym-mod     (163f/228c)', '$_projects\\Fabric Modding\\what-do-you-mean-mod-1.21'),
  ('woflo-mod    (203f/37c)', '$_projects\\Fabric Modding\\woflo-interwoven-mod-1.21'),
  ('alpha-math   (220f/7c)', '$_projects\\alpha-math'),
  ('AgentBox     (163f/64c)', '$_projects\\_old\\AgentBox'),
  ('seance       (212f/11c)', '$_projects\\seance'),
];

double _med(List<int> us) {
  us.sort();
  return us[us.length ~/ 2] / 1000.0;
}

void _p(String s) => print(s); // surfaced by `flutter test`

Future<void> _profile(String label, String path) async {
  if (!Directory(path).existsSync()) {
    _p('\n========== $label ==========\n  SKIP — not found at $path');
    return;
  }
  _p('\n========== $label ==========');

  // ── Phase A: coupling (git log #1 + co-change accumulation) ──
  final swCc = Stopwatch()..start();
  final ccRes = await computeFileCoupling(path);
  swCc.stop();
  final cc = ccRes.data;
  if (cc == null) {
    _p('  coupling FAILED: ${ccRes.error}');
    return;
  }

  // ── Phase B: stats (git log #2 + parse + integrity), coupling passed in ──
  final swStats = Stopwatch()..start();
  final statsRes = await collectLogosGitStats(path, coupling: cc);
  swStats.stop();
  final stats = statsRes.data;
  if (stats == null) {
    _p('  stats FAILED: ${statsRes.error}');
    return;
  }

  // ── Phase C: buildFromStats (pure compute, per-phase via probeTimingsUs) ──
  final probe = <String, int>{};
  LogosGit engine = LogosGit.buildFromStats(stats); // warmup (JIT)
  final buildUs = <int>[];
  for (var t = 0; t < 7; t++) {
    probe.clear();
    final sw = Stopwatch()..start();
    engine = LogosGit.buildFromStats(stats, probeTimingsUs: probe);
    sw.stop();
    buildUs.add(sw.elapsedMicroseconds);
  }
  final buildMed = _med(buildUs);

  // ── Phase D: interactive queries on real seeds ──
  final nodes = engine.nodePaths;
  final n = nodes.length;
  double diffuseMed = 0, evMed = 0, scoreMs = 0;
  double evMin = 0, evSpec = 0, evDiag = 0, evAttr = 0, evFull = 0;
  if (n > 0) {
    final seeds = <String>{for (var i = 0; i < n && i < 3; i++) nodes[(i * 7 + 1) % n]};
    engine.diffuse(seeds, topK: 20); // warmup
    final dUs = <int>[];
    for (var t = 0; t < 12; t++) {
      final sw = Stopwatch()..start();
      engine.diffuse(seeds, topK: 20);
      sw.stop();
      dUs.add(sw.elapsedMicroseconds);
    }
    diffuseMed = _med(dUs);

    final focus = {for (final s in seeds) s: 1.0};
    engine.gatherEvidenceRecurrent(focusWeights: focus, topK: 20); // warmup
    final eUs = <int>[];
    for (var t = 0; t < 6; t++) {
      final sw = Stopwatch()..start();
      engine.gatherEvidenceRecurrent(focusWeights: focus, topK: 20);
      sw.stop();
      eUs.add(sw.elapsedMicroseconds);
    }
    evMed = _med(eUs);

    final swS = Stopwatch()..start();
    var acc = 0.0;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n && j < i + 24; j++) {
        acc += stats.coupling.jaccardScoreOf(nodes[i], nodes[j]);
      }
    }
    swS.stop();
    scoreMs = swS.elapsedMicroseconds / 1000.0 + (acc.isNaN ? 1 : 0);

    // ── component attribution of the 100–500ms gatherEvidence query ──
    double evG(bool spec, bool attr, bool diag, Map<String, String> axes) {
      engine.gatherEvidence(
          focusWeights: focus, includeSpectrum: spec, includeSupportAttribution: attr,
          includeSummaryDiagnostics: diag, axisLabelByPath: axes, topK: 20); // warmup
      final us = <int>[];
      for (var t = 0; t < 8; t++) {
        final sw = Stopwatch()..start();
        engine.gatherEvidence(
            focusWeights: focus, includeSpectrum: spec, includeSupportAttribution: attr,
            includeSummaryDiagnostics: diag, axisLabelByPath: axes, topK: 20);
        sw.stop();
        us.add(sw.elapsedMicroseconds);
      }
      return _med(us);
    }

    final axes = {for (var i = 0; i < n; i++) nodes[i]: (i % 3 == 0 ? 'M' : i % 3 == 1 ? 'Ab' : 'P')};
    evMin = evG(false, false, false, const {});
    evSpec = evG(true, false, false, const {});
    evDiag = evG(false, false, true, const {});
    evAttr = evG(false, true, false, axes);
    evFull = evG(true, true, true, axes);
  }

  // ── report ──
  final ingA = swCc.elapsedMicroseconds / 1000.0;
  final ingB = swStats.elapsedMicroseconds / 1000.0;
  // production runs the two git logs in PARALLEL, so real ingest ≈ max(A,B) + parse;
  // report both, and use max for the cold-build estimate.
  final ingest = ingA > ingB ? ingA : ingB;
  final coldTotal = ingest + buildMed;
  _p('  nodes(coupled files)=$n   coupling rows=${cc.paths.length}');
  _p('  [INGEST  A] computeFileCoupling  : ${ingA.toStringAsFixed(1)} ms   (git log + co-change accumulate)');
  _p('  [INGEST  B] collectLogosGitStats : ${ingB.toStringAsFixed(1)} ms   (git log + numstat parse + integrity)');
  _p('  [COMPUTE C] buildFromStats       : ${buildMed.toStringAsFixed(2)} ms   (median of 7, no-engram core)');
  final ph = probe.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in ph) {
    final ms = e.value / 1000.0;
    if (ms < 0.005) continue;
    _p('         └ ${e.key.padRight(22)} ${ms.toStringAsFixed(3)} ms   ${(ms / buildMed * 100).toStringAsFixed(0)}%');
  }
  _p('  [QUERY] diffuse(3 seeds, topK20) : ${diffuseMed.toStringAsFixed(3)} ms   (median of 12)');
  _p('  [QUERY] gatherEvidenceRecurrent  : ${evMed.toStringAsFixed(2)} ms   (median of 6, ~6 iters)');
  _p('  [QUERY] gatherEvidence component attribution (per single call, median of 8):');
  _p('         · minimal (no spec/attr/diag) : ${evMin.toStringAsFixed(2)} ms   ← base diffusions + ranking');
  _p('         · +spectrum                   : ${evSpec.toStringAsFixed(2)} ms   (Δ ${(evSpec - evMin).toStringAsFixed(2)})');
  _p('         · +diagnostics                : ${evDiag.toStringAsFixed(2)} ms   (Δ ${(evDiag - evMin).toStringAsFixed(2)})');
  _p('         · +attribution (w/ axes)      : ${evAttr.toStringAsFixed(2)} ms   (Δ ${(evAttr - evMin).toStringAsFixed(2)})');
  _p('         · FULL (spec+attr+diag)       : ${evFull.toStringAsFixed(2)} ms');
  _p('  [QUERY] $n×24 score lookups      : ${scoreMs.toStringAsFixed(3)} ms');
  _p('  RSS=${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(0)} MB');
  _p('  >>> COLD BUILD ≈ ${coldTotal.toStringAsFixed(1)} ms  |  ingest(∥) ${(ingest / coldTotal * 100).toStringAsFixed(0)}%   compute ${(buildMed / coldTotal * 100).toStringAsFixed(0)}%');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PROFILE core engine on real repos', () async {
    _p('\n################ REAL-REPO ENGINE PROFILE ################');
    _p('dart ${Platform.version.split(' ').first}  cores=${Platform.numberOfProcessors}');
    for (final (label, path) in _repos) {
      await _profile(label, path);
    }
    _p('\n################ END PROFILE ################\n');
    expect(true, isTrue);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
