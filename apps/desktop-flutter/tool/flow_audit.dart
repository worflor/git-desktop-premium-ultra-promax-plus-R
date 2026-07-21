// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// tool/flow_audit.dart — dump the REAL flow-coherence sub-signal for a repo.
//
// Companion to axis_audit.dart in the coupling-axis audit: runs the actual
// flow engine (analyzeFlowCached) over the audited language subset and
// computes pairwise flow coherence with the same address-grouped
// flowPhaseCoherence math as file_coupling.computeFlowCoherence — replicated
// here verbatim because importing file_coupling would drag git.dart → Flutter.
//
// Usage: dart run tool/flow_audit.dart <repoPath> <out.json> <prefix|-> <ext[,ext...]>

import 'dart:convert';
import 'dart:io';

import 'package:git_desktop/backend/logos_core.dart' show flowPhaseCoherence;
import 'package:git_desktop/backend/logos_flow.dart'
    show FlowAnalysisResult, analyzeFlowCached;

const int _auditFileCap = 400;

List<String> _tracked(String repo) {
  final r = Process.runSync('git', ['-C', repo, 'ls-files']);
  if (r.exitCode != 0) return const [];
  return [
    for (final l in const LineSplitter().convert(r.stdout as String))
      if (l.trim().isNotEmpty) l.trim(),
  ];
}

/// Verbatim mirror of file_coupling.computeFlowCoherence (address-grouped
/// phase coherence, mean per pair, floor 0.1).
Map<String, Map<String, double>> _flowCoherence(
  Map<String, FlowAnalysisResult> flowResults,
) {
  if (flowResults.length < 2) return const {};
  final byAddress = <int, List<(String, double, double)>>{};
  for (final entry in flowResults.entries) {
    for (final f in entry.value.findings) {
      byAddress
          .putIfAbsent(f.address, () => [])
          .add((entry.key, f.certainty, f.phase));
    }
  }
  final pairScores = <(String, String), List<double>>{};
  for (final entry in byAddress.entries) {
    if (entry.value.length < 2) continue;
    final byFile = <String, List<(double, double)>>{};
    for (final (file, cert, phase) in entry.value) {
      byFile.putIfAbsent(file, () => []).add((cert, phase));
    }
    final files = byFile.keys.toList();
    if (files.length < 2) continue;
    for (var i = 0; i < files.length; i++) {
      for (var j = i + 1; j < files.length; j++) {
        final merged = [...byFile[files[i]]!, ...byFile[files[j]]!];
        final coh = flowPhaseCoherence(merged);
        final lo = files[i].compareTo(files[j]) < 0 ? files[i] : files[j];
        final hi = files[i].compareTo(files[j]) < 0 ? files[j] : files[i];
        pairScores.putIfAbsent((lo, hi), () => []).add(coh);
      }
    }
  }
  final result = <String, Map<String, double>>{};
  for (final entry in pairScores.entries) {
    final (lo, hi) = entry.key;
    final scores = entry.value;
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    if (mean < 0.1) continue;
    (result[lo] ??= {})[hi] = mean;
  }
  return result;
}

Future<void> main(List<String> args) async {
  if (args.length < 4) {
    stderr.writeln(
        'usage: dart run tool/flow_audit.dart <repo> <out.json> <prefix|-> <ext[,ext]>');
    exit(2);
  }
  final repo = args[0];
  final outPath = args[1];
  final prefix = args[2] == '-' ? null : args[2];
  final exts = args[3].split(',');

  final flowResults = <String, FlowAnalysisResult>{};
  var audited = 0;
  for (final rel in _tracked(repo)) {
    if (audited >= _auditFileCap) break;
    if (prefix != null && !rel.startsWith(prefix)) continue;
    if (!exts.any(rel.endsWith)) continue;
    audited++;
    final abs =
        '$repo${Platform.pathSeparator}${rel.split('/').join(Platform.pathSeparator)}';
    try {
      final r = await analyzeFlowCached(abs);
      if (r != null && r.findings.isNotEmpty) flowResults[rel] = r;
    } catch (_) {
      continue;
    }
  }
  stderr.writeln('flow results for ${flowResults.length}/$audited files');
  final coh = _flowCoherence(flowResults);
  File(outPath).writeAsStringSync(jsonEncode(coh));
  var edges = 0;
  for (final sub in coh.values) {
    edges += sub.length;
  }
  stderr.writeln('wrote $edges coherence edges -> $outPath');
}
