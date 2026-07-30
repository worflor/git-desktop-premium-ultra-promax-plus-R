// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// coupling_holdout_jury_test.dart — the temporal-holdout jury, aimed at the
// history axis itself.
//
// docs/architecture/coupling-axis-audit.md judges a coupling signal on one
// question: trained on the past, does it rank pairs that ACTUALLY co-change
// next above random pairs? This runs that trial against
// `computeFileCoupling` so a change to the score's ALGEBRA can be measured
// rather than argued. Train on a clone whose tip precedes the held-out
// window; test on pairs co-occurring in >= 2 commits of that window; report
// AUC with ties at half — which is what stops "score everything 0" from
// looking like a win (an all-zero scorer lands at exactly 0.500).
//
// WHAT THE NUMBER MEANS, exactly: P(a pair that co-changes >=2 times in the
// window outranks a random never-co-changed pair). It is NOT general
// ranking quality — with hard negatives (pairs that co-changed exactly
// once) the same matrix scores ~0.68 where this reads ~0.87 — and it says
// nothing about files born inside the window (those positives are dropped
// for lacking a training-side endpoint; roughly half of them at holdout
// 120 on this repo).
//
// UNCERTAINTY, measured not assumed: the binding sample is `judged`
// (distinct positive pairs), not `comparisons` (resamples of them). At
// ~235 judged pairs the Hanley-McNeil 95% interval is about ±0.03; the
// oft-quoted seed-to-seed ±0.002 is Monte Carlo error on a FIXED positive
// set and must never be read as the uncertainty of a window's AUC. Windows
// are NESTED (a >=2-co-change pair at holdout 60 is one at 180 too), so a
// 5-window grid on one repo is one dataset resampled at five depths — the
// independent replicates are the REPOS. Quote deltas only when paired per
// window at one HEAD, and treat |delta| < 0.02 as unresolved.
//
// FINDINGS (grids of holdout 90/120/150/180 x both local repos, paired per
// window — holdout 60 is excluded: ~15 judged pairs on this repo, SE ±0.1):
//   lag window     positive in most windows, wins to +0.035 against losses
//                  at the seed-noise floor. Suggestive on 2 repos; the
//                  5-repo jury would settle it.
//   recency decay  leans positive; costs at short holdouts, pays at long
//                  ones, both repos. Modest.
//   meaningfulness indistinguishable from noise. An earlier single-window
//                  read that it "hurts on both repos" was window luck;
//                  withdrawn.
//   softKnee(60)   |effect| below this instrument's ~0.02 resolution.
//   K-norm denom   loses by 0.02-0.04 on BOTH repos, paired — the one
//                  component verdict sized above every noise source here.
//                  That rejection stands.
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

/// One spelling of a line break for every split in this file. Two of
/// these were briefly `[CRLF]+`, which COLLAPSES runs of blank lines:
/// a different parse, adopted to dodge a shell-escaping problem
/// rather than because it was right. Named once so the two spellings
/// cannot drift apart again.
final RegExp _lineBreak = RegExp(r'\r?\n');

String _key(String a, String b) => a.compareTo(b) < 0 ? '$a $b' : '$b $a';

/// The held-out window: newest [holdout] non-merge commits, each as
/// (sha, files).
List<({String sha, List<String> files})> _holdoutCommits(
    String repo, int holdout) {
  final r = Process.runSync('git', [
    '-C', repo,
    'log', '-n', '$holdout', '--no-merges', '--name-only',
    '--pretty=format:$_sep%H',
  ]);
  if (r.exitCode != 0) throw StateError('git log failed: ${r.stderr}');
  final out = <({String sha, List<String> files})>[];
  String? sha;
  var current = <String>[];
  for (final line in (r.stdout as String).split(_lineBreak)) {
    if (line.startsWith(_sep)) {
      if (sha != null) out.add((sha: sha, files: current));
      sha = line.substring(1).trim();
      current = <String>[];
    } else if (line.trim().isNotEmpty) {
      current.add(line.trim());
    }
  }
  if (sha != null) out.add((sha: sha, files: current));
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

    final window = _holdoutCommits(repo, holdout);
    expect(window.length, holdout,
        reason: 'need at least $holdout non-merge commits');

    final coCount = <String, int>{};
    for (final commit in window) {
      final files = commit.files;
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

    // The training base is the PARENT OF THE OLDEST HELD-OUT COMMIT, not
    // HEAD~holdout. The window is "newest N non-merge commits" while ~N
    // walks first-parent ancestry INCLUDING merges — two different
    // countings that agree only on merge-light history. Deriving the base
    // from the window itself makes disagreement unrepresentable; the
    // containment assert below is the belt to this suspenders.
    final base = Process.runSync(
        'git', ['-C', repo, 'rev-parse', '${window.last.sha}^']);
    expect(base.exitCode, 0,
        reason: 'oldest held-out commit has no parent — window spans the '
            'whole history');
    final baseSha = (base.stdout as String).trim();
    final tip = (Process.runSync('git', ['-C', repo, 'rev-parse', 'HEAD'])
            .stdout as String)
        .trim();

    final tmp = Directory.systemTemp.createTempSync('cj_');
    final clone = '${tmp.path}${Platform.pathSeparator}t';
    final c = Process.runSync(
        'git', ['clone', '--quiet', '--no-checkout', '--local', repo, clone]);
    expect(c.exitCode, 0, reason: 'clone failed: ${c.stderr}');

    // FAIL CLOSED. A failed reset leaves the clone at the FULL history —
    // the engine then trains on every commit it is about to be judged on
    // and the run prints a healthy-looking number. This exact failure was
    // reproduced on this machine (Windows MAX_PATH on the deep
    // Runner.xcodeproj paths, dependent on TMPDIR length), which is also
    // why the temp names above are short.
    final reset = Process.runSync(
        'git', ['-C', clone, 'reset', '--hard', '--quiet', baseSha]);
    expect(reset.exitCode, 0,
        reason: 'reset to $baseSha failed — a clone left at full history '
            'trains on the held-out window: ${reset.stderr}');

    // Strip every ref except the training branch so the future is not
    // merely un-walked but GONE from the ref space: today
    // computeFileCoupling reads a single plain `git log` from HEAD, and
    // this keeps a future `--all`, `--tags`, or a stray `log.all=true`
    // from silently training on the answer key. Old release tags sit on
    // side lineages, which is why the leak test below intersects with
    // the WINDOW rather than demanding base-ancestry of everything.
    Process.runSync('git', ['-C', clone, 'remote', 'remove', 'origin']);
    final tags = (Process.runSync('git', ['-C', clone, 'tag', '-l']).stdout
            as String)
        .split(_lineBreak)
        .where((t) => t.trim().isNotEmpty);
    for (final t in tags) {
      Process.runSync('git', ['-C', clone, 'tag', '-d', t.trim()]);
    }

    // THE leakage invariant: no ref in the training clone reaches any
    // held-out commit. Checked as a set intersection so a future ref
    // source cannot dodge it the way tags dodged a base-ancestry check.
    final reachable = (Process.runSync(
            'git', ['-C', clone, 'rev-list', '--all']).stdout as String)
        .split(_lineBreak)
        .map((l) => l.trim())
        .toSet();
    final leaked =
        window.where((c) => reachable.contains(c.sha)).length;
    expect(leaked, 0,
        reason: '$leaked held-out commits are reachable from the training '
            'clone — the AUC would be measured on its own training data');

    // Knobs, so the jury can score the COMPONENTS of the axis and not
    // just the axis. Each of these multiplies every term in the score
    // and none had ever been scored on its own.
    final knee = int.tryParse(Platform.environment['JURY_KNEE'] ?? '') ?? 60;
    final halfRaw = Platform.environment['JURY_HALFLIFE'];
    final matrix = await computeFileCoupling(
      clone,
      commitLimit: 1000,
      largeCommitSoftKnee: knee,
      halfLifeCommits: halfRaw == null ? null : double.parse(halfRaw),
    );
    expect(matrix.ok && matrix.data != null, isTrue,
        reason: 'coupling failed: ${matrix.error}');
    final m = matrix.data!;

    final known = (Process.runSync('git', ['-C', clone, 'ls-files']).stdout
            as String)
        .split(_lineBreak)
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

    final seed =
        int.tryParse(Platform.environment['JURY_SEED'] ?? '') ?? 0x5EED;
    final rng = math.Random(seed);
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
    // Tip and base printed so a recorded number can be reproduced — or
    // falsified — after the fact. A result without its HEAD is the exact
    // cross-HEAD comparison the methodology note forbids.
    // ignore: avoid_print
    print('JURY repo=$repo tip=${tip.substring(0, 12)} '
        'base=${baseSha.substring(0, 12)} holdout=$holdout '
        'positives=${positives.length} judged=${judged.length} '
        'comparisons=$n AUC=${auc.toStringAsFixed(4)}');

    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}

    // The evidence floor is DISTINCT POSITIVE PAIRS. The old guard
    // (`comparisons > 1000`) counted resamples and could not fail for
    // lack of data — holdout 60 sailed through it on 15 pairs.
    expect(judged.length, greaterThanOrEqualTo(100),
        reason: 'only ${judged.length} judged pairs — the Hanley-McNeil '
            'interval is wider than the effects being measured; use a '
            'longer holdout');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
