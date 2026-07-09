// Deterministic engine WORK budget — asserts LogosGit.buildFromStats does
// sub-quadratic work as the file count grows, using the engine's own
// work-unit counters (`_probePairsScored` / `_probeMixerCalls` /
// `_probeTransportCalls`, populated via `probeTimingsUs` — see
// logos_git.dart:2641-2896) rather than wall-clock. This is the
// deterministic net for "someone dropped a nested loop into scoreLoop":
// a real O(n^2) regression multiplies the growth ratio by roughly the same
// factor no matter what baseline structure the repo has, so even a loosely
// realistic synthetic repo catches it.
//
// docs/architecture/engine-performance-profile.md measured scoreLoop at
// ~n^1.37 and coupling-calibration at ~n^1.47 on REAL repos. This file uses
// SYNTHETIC scratch repos (deterministic, no hardcoded machine paths) with a
// deliberately bounded co-change structure — see `_buildSyntheticRepo` — so
// the measured ratio here is close to linear (~4.1x for a 4x file count),
// tighter than the real-repo exponent. That's fine: the assertion isn't
// "matches production's exact exponent," it's "stays sub-quadratic" — an
// O(n^2) bug inflates the ratio toward 16x regardless of the starting
// baseline, so a bound set just above the measured linear baseline still
// catches it with a wide margin.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_git_stats.dart';

import '../support/scratch_repo.dart';

const int _filesPerModule = 6;

/// One commit PER MODULE, touching only that module's own files.
///
/// Deliberately NOT one big `commitAll()` covering every file: a single
/// commit spanning all n files would make every pair of files co-occur in
/// that one commit, giving jaccard co-change a dense O(n^2) edge set before
/// any "real" history exists — an artifact of the generator, not of the
/// engine under test. Scoping each commit to one module bounds each file's
/// co-change degree to `_filesPerModule - 1`, the same shape real repos
/// have (a commit touches a handful of related files, not the whole tree).
Future<(ScratchRepo, List<String>)> _buildSyntheticRepo(int n) async {
  final repo = await ScratchRepo.create(name: 'engine_work_budget_$n');
  final nModules = (n / _filesPerModule).ceil();
  final paths = <String>[];

  for (var m = 0; m < nModules; m++) {
    final modPaths = <String>[];
    for (var f = 0; f < _filesPerModule; f++) {
      if (paths.length >= n) break;
      final path = 'mod$m/file$f.dart';
      paths.add(path);
      modPaths.add(path);
      await repo.writeFile(path, '// module $m file $f\n');
    }
    if (modPaths.isEmpty) continue;
    // stage() + a bare commit — 2 spawns per module, no rev-parse needed
    // (the sha is never read back).
    await repo.stage(modPaths);
    await repo.git(['commit', '-m', 'module $m']);
  }

  return (repo, paths);
}

Future<LogosGitStats> _statsFor(ScratchRepo repo) async {
  final ccRes = await computeFileCoupling(repo.dir.path);
  final cc = ccRes.data;
  if (cc == null) {
    fail('computeFileCoupling failed: ${ccRes.error}');
  }
  final statsRes = await collectLogosGitStats(repo.dir.path, coupling: cc);
  final stats = statsRes.data;
  if (stats == null) {
    fail('collectLogosGitStats failed: ${statsRes.error}');
  }
  return stats;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'buildFromStats work counters grow sub-quadratically from n=300 to '
      'n=1200 (4x files)', () async {
    final (repoSmall, pathsSmall) = await _buildSyntheticRepo(300);
    addTearDown(repoSmall.dispose);
    expect(pathsSmall.length, 300);
    final statsSmall = await _statsFor(repoSmall);

    final (repoLarge, pathsLarge) = await _buildSyntheticRepo(1200);
    addTearDown(repoLarge.dispose);
    expect(pathsLarge.length, 1200);
    final statsLarge = await _statsFor(repoLarge);

    // Warm up (JIT) before measuring, like engine_real_profile_test.dart.
    LogosGit.buildFromStats(statsSmall);
    LogosGit.buildFromStats(statsLarge);

    final probeSmall = <String, int>{};
    LogosGit.buildFromStats(statsSmall, probeTimingsUs: probeSmall);
    final probeLarge = <String, int>{};
    LogosGit.buildFromStats(statsLarge, probeTimingsUs: probeLarge);

    final pairsSmall = probeSmall['_probePairsScored']!;
    final pairsLarge = probeLarge['_probePairsScored']!;
    final mixerSmall = probeSmall['_probeMixerCalls']!;
    final mixerLarge = probeLarge['_probeMixerCalls']!;
    final transportSmall = probeSmall['_probeTransportCalls']!;
    final transportLarge = probeLarge['_probeTransportCalls']!;

    // Exact counts, measured once against this exact generator (deterministic
    // — no RNG, no wall-clock dependence, pure function of file/commit
    // structure) — pins the candidate-generation logic itself, not just its
    // asymptotic shape. A change here means scoreLoop's candidate set (CC
    // neighbours ∪ directory siblings ∪ well-siblings ∪ transport seeds —
    // logos_git.dart:2645-2720) started admitting a different number of
    // candidates for this exact repo shape.
    expect(pairsSmall, 6684,
        reason: 'measured _probePairsScored for the n=300 synthetic repo; '
            'a change means the per-node candidate set changed shape.');
    expect(pairsLarge, 27384,
        reason: 'measured _probePairsScored for the n=1200 synthetic repo.');
    expect(mixerSmall, pairsSmall,
        reason: 'every scored pair invokes the Born mixer exactly once — '
            'see logos_git.dart:2747 (probePairsScored++) and :2784 '
            '(probeMixerCalls++) in the same loop iteration.');
    expect(mixerLarge, pairsLarge);
    expect(transportSmall, pairsSmall * 2,
        reason: 'transport lane scoring does exactly 2 probe-counted calls '
            'per scored pair — logos_git.dart:2802 (probeTransportCalls '
            '+= 2).');
    expect(transportLarge, pairsLarge * 2);

    // The actual regression net: WORK (not wall-clock) growth ratio for a
    // 4x file-count increase. Measured on this exact generator: 27384 /
    // 6684 = 4.097x — essentially linear (the synthetic repo's co-change
    // degree is bounded per-module, ~11-12 candidates/node regardless of
    // n). Bound set to 4.75 — ~16% above the measured 4.097x, comfortably
    // clear of jitter but nowhere near the O(n log n)≈5x or O(n^2)=16x
    // shapes a real regression would produce. If buildFromStats regresses
    // to quadratic candidate generation (e.g. a cap removed, or a
    // dedup/Set swapped for a List that stops deduping), this ratio jumps
    // toward 16x and blows straight through 4.75x.
    const bound = 4.75;
    final pairsRatio = pairsLarge / pairsSmall;
    final mixerRatio = mixerLarge / mixerSmall;
    final transportRatio = transportLarge / transportSmall;

    expect(pairsRatio, lessThan(bound),
        reason: '_probePairsScored grew ${pairsRatio.toStringAsFixed(3)}x '
            'for a 4x file-count increase (measured baseline: 4.097x). '
            'docs/architecture/engine-performance-profile.md measured '
            'scoreLoop at ~n^1.37 on real repos (4^1.37≈6.6x) — this '
            'synthetic repo is more tightly bounded, so 4.75x is the '
            'regression bar, not a reproduction of the real exponent.');
    expect(mixerRatio, lessThan(bound),
        reason: '_probeMixerCalls tracks _probePairsScored 1:1; see above.');
    expect(transportRatio, lessThan(bound),
        reason:
            '_probeTransportCalls tracks _probePairsScored 1:1 (×2); see '
            'above.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
