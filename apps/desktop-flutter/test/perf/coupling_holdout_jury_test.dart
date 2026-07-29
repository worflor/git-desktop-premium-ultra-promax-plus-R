// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: LicenseRef-WLCSL-1.0
// See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

// coupling_holdout_jury_test.dart — the temporal-holdout jury, aimed at the
// history axis itself.
//
// docs/architecture/coupling-axis-audit.md judges a coupling signal on one
// question: trained on the past, does it rank pairs that ACTUALLY co-change
// next above random pairs? Every signal in that dossier faced this. The
// jaccard(+lag) history baseline scored 0.672 on MANIFOLD.
//
// This runs the same trial against `computeFileCoupling` so a change to the
// score's ALGEBRA can be measured rather than argued. Train on a clone reset
// to HEAD~holdout, so the engine sees only history preceding the window it is
// judged on; test on pairs co-occurring in >= 2 commits of that window;
// report AUC with ties at half — which is what stops "score everything 0"
// from looking like a win.
//
// Manual: it clones the repo and reads real history.
//   flutter test --run-skipped -t manual test/perf/coupling_holdout_jury_test.dart
@Tags(['manual'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';

const _sep = '\u0001';

String _key(String a, String b) => a.compareTo(b) < 0 ? '$a $b' : '$b $a';

List<List<String>> _holdoutCommits(String repo, int holdout) {
  final r = Process.runSync('git', [
    '-C', repo,
    'log', '-n', '$holdout', '--no-merges', '--name-only',
    '--pretty=format:%x01',
  ]);
  if (r.exitCode != 0) throw StateError('git log failed: ${r.stderr}');
  final out = <List<String>>[];
  var current = <String>[];
  for (final line in (r.stdout as String).split(RegExp(r'\r?\n'))) {
    if (line.startsWith(_sep)) {
      if (current.isNotEmpty) out.add(current);
      current = <String>[];
    } else if (line.trim().isNotEmpty) {
      current.add(line.trim());
    }
  }
  if (current.isNotEmpty) out.add(current);
  return out;
}

void main() {
  test('history axis: held-out co-change AUC', () async {
    final repo = Platform.environment['JURY_REPO'] ??
        Directory.current.parent.parent.path;
    final holdout =
        int.tryParse(Platform.environment['JURY_HOLDOUT'] ?? '') ?? 120;
    final samples =
        int.tryParse(Platform.environment['JURY_SAMPLES'] ?? '') ?? 60000;

    final future = _holdoutCommits(repo, holdout);
    final coCount = <String, int>{};
    for (final files in future) {
      // A sweeping commit says little about any particular pair.
      if (files.length < 2 || files.length > 40) continue;
      for (var i = 0; i < files.length; i++) {
        for (var j = i + 1; j < files.length; j++) {
          final k = _key(files[i], files[j]);
          coCount[k] = (coCount[k] ?? 0) + 1;
        }
      }
    }
    final positives =
        coCount.entries.where((e) => e.value >= 2).map((e) => e.key).toList();

    final base =
        Process.runSync('git', ['-C', repo, 'rev-parse', 'HEAD~$holdout']);
    expect(base.exitCode, 0, reason: 'need at least $holdout commits');
    final baseSha = (base.stdout as String).trim();

    final tmp = Directory.systemTemp.createTempSync('coupling_jury_');
    final clone = '${tmp.path}${Platform.pathSeparator}train';
    final c = Process.runSync(
        'git', ['clone', '--quiet', '--no-checkout', '--local', repo, clone]);
    expect(c.exitCode, 0, reason: 'clone failed: ${c.stderr}');
    Process.runSync(
        'git', ['-C', clone, 'reset', '--hard', '--quiet', baseSha]);

    final matrix = await computeFileCoupling(clone, commitLimit: 1000);
    expect(matrix.ok && matrix.data != null, isTrue,
        reason: 'coupling failed: ${matrix.error}');
    final m = matrix.data!;

    final known = (Process.runSync('git', ['-C', clone, 'ls-files']).stdout
            as String)
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.trim())
        .toList();
    final knownSet = known.toSet();
    final judged = positives.where((k) {
      final p = k.split(' ');
      return knownSet.contains(p[0]) && knownSet.contains(p[1]);
    }).toList();

    double scoreOf(String k) {
      final p = k.split(' ');
      return m.jaccardScoreOf(p[0], p[1]);
    }

    final rng = math.Random(0x5EED);
    var wins = 0.0;
    var n = 0;
    for (var i = 0; i < samples && judged.isNotEmpty; i++) {
      final pos = scoreOf(judged[rng.nextInt(judged.length)]);
      final a = known[rng.nextInt(known.length)];
      final b = known[rng.nextInt(known.length)];
      if (a == b) continue;
      if (coCount[_key(a, b)] != null) continue; // not a negative
      final neg = m.jaccardScoreOf(a, b);
      if (pos > neg) {
        wins += 1;
      } else if (pos == neg) {
        wins += 0.5;
      }
      n++;
    }

    final auc = n == 0 ? double.nan : wins / n;
    // ignore: avoid_print
    print('JURY repo=$repo holdout=$holdout positives=${positives.length} '
        'judged=${judged.length} comparisons=$n '
        'AUC=${auc.toStringAsFixed(4)}');

    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}

    expect(n, greaterThan(1000), reason: 'the trial needs comparisons to mean '
        'anything');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
