// Throwaway R&D test.
// Run: flutter test test/coupling_research_test.dart
//
// Measures empirical co-change frequency per transport role pair
// and compares to hand-authored _kCoupling* constants.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git_integrity.dart';
import 'package:git_desktop/backend/shadow_history.dart';
import 'package:git_desktop/backend/shadow_coupling.dart';
import 'package:git_desktop/backend/spectral_constants.dart' as sc;

const _handAuthored = <String, double>{
  'manifest↔lockfile': 0.80,
  'source↔test': 0.42,
  'source↔generated': 0.72,
  'source↔doc': 0.30,
  'source↔migration': 0.48,
  'fixture↔source': 0.36,
  'ci-config↔source': 0.36,
};

void main() {
  test('empirical coupling vs hand-authored constants', () async {
    // Point at the repo root — two levels up from apps/desktop-flutter
    final repoPath = '${Directory.current.path}';
    // Walk up if we're inside apps/desktop-flutter
    final effectivePath = repoPath.contains('desktop-flutter')
        ? repoPath.substring(
            0, repoPath.indexOf('apps') > 0 ? repoPath.indexOf('apps') - 1 : repoPath.length)
        : repoPath;

    print('repo: $effectivePath');
    print('computing coupling matrix...\n');

    final result = await computeFileCoupling(effectivePath, halfLifeCommits: 200);
    expect(result.ok, isTrue, reason: 'coupling matrix build failed: ${result.error}');
    final matrix = result.data!;

    final paths = matrix.paths;
    print('files: ${paths.length}');
    print('commits analyzed: ${matrix.commitsAnalyzed}\n');

    // classify every file
    final roles = <String, TransportRoles>{};
    final roleCounts = <String, int>{};
    for (final p in paths) {
      final r = TransportRoles.of(p);
      roles[p] = r;
      final label = _roleLabel(r);
      roleCounts[label] = (roleCounts[label] ?? 0) + 1;
    }

    print('--- role distribution ---');
    final sortedRoles = roleCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sortedRoles) {
      print('  ${e.key.padRight(14)} ${e.value}');
    }
    print('');

    // bucket co-change pairs by role pair type
    final buckets = <String, List<double>>{
      for (final k in _handAuthored.keys) k: [],
    };
    final uncategorized = <String, List<double>>{};

    for (final a in paths) {
      final ra = roles[a]!;
      if (!matrix.hasJaccardRow(a)) continue;
      for (final entry in matrix.jaccardEntriesOf(a)) {
        final b = entry.key;
        final rb = roles[b];
        if (rb == null) continue;
        final score = entry.value;
        if (score <= 0) continue;
        final bucket = _classifyPair(ra, rb);
        if (bucket != null) {
          buckets[bucket]!.add(score);
        } else {
          final pairLabel = '${_roleLabel(ra)}↔${_roleLabel(rb)}';
          uncategorized.putIfAbsent(pairLabel, () => []).add(score);
        }
      }
    }

    // report
    print('=== COUPLING CONSTANTS: HAND-AUTHORED vs EMPIRICAL ===\n');
    print('${"pair".padRight(24)} ${"hand".padRight(8)} ${"empir".padRight(8)} '
        '${"delta".padRight(8)} ${"n".padRight(6)} '
        '${"p25".padRight(8)} ${"med".padRight(8)} ${"p75".padRight(8)}');
    print('-' * 88);

    final sorted = _handAuthored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final e in sorted) {
      final samples = buckets[e.key]!;
      if (samples.isEmpty) {
        print('${e.key.padRight(24)} ${e.value.toStringAsFixed(2).padRight(8)} '
            '${"---".padRight(8)} ${"---".padRight(8)} 0');
        continue;
      }
      samples.sort();
      final mean = samples.reduce((a, b) => a + b) / samples.length;
      final delta = mean - e.value;
      print('${e.key.padRight(24)} '
          '${e.value.toStringAsFixed(2).padRight(8)} '
          '${mean.toStringAsFixed(3).padRight(8)} '
          '${(delta >= 0 ? "+" : "")}'
          '${delta.toStringAsFixed(3).padRight(7)} '
          '${samples.length.toString().padRight(6)} '
          '${_pct(samples, 0.25).toStringAsFixed(3).padRight(8)} '
          '${_pct(samples, 0.50).toStringAsFixed(3).padRight(8)} '
          '${_pct(samples, 0.75).toStringAsFixed(3).padRight(8)}');
    }

    // show uncategorized pairs for lane discovery
    print('\n--- top uncategorized role pairs (potential new lanes) ---');
    final uncatSorted = uncategorized.entries
        .where((e) => e.value.length >= 3)
        .toList()
      ..sort((a, b) {
        final meanA = a.value.reduce((x, y) => x + y) / a.value.length;
        final meanB = b.value.reduce((x, y) => x + y) / b.value.length;
        return meanB.compareTo(meanA);
      });
    for (final e in uncatSorted.take(15)) {
      final mean = e.value.reduce((a, b) => a + b) / e.value.length;
      print('  ${e.key.padRight(24)} '
          'mean=${mean.toStringAsFixed(3)}  '
          'n=${e.value.length}');
    }

    // calibrated constants via Bayesian shrinkage
    final calibrated = calibrateCouplingConstants(
      paths,
      (a, b) => matrix.jaccardScoreOf(a, b),
      jaccardEdges: (p) => matrix.jaccardEntriesOf(p),
    );
    print('\n=== CALIBRATED CONSTANTS (prior weight=20) ===');
    print('  manifest↔lockfile  ${calibrated.manifestLockfile.toStringAsFixed(3)}  (prior: 0.80)');
    print('  source↔generated   ${calibrated.sourceGenerated.toStringAsFixed(3)}  (prior: 0.72)');
    print('  source↔migration   ${calibrated.sourceMigration.toStringAsFixed(3)}  (prior: 0.48)');
    print('  source↔test        ${calibrated.sourceTest.toStringAsFixed(3)}  (prior: 0.42)');
    print('  fixture↔source     ${calibrated.fixture.toStringAsFixed(3)}  (prior: 0.36)');
    print('  ci-config↔source   ${calibrated.ciConfig.toStringAsFixed(3)}  (prior: 0.36)');
    print('  source↔doc         ${calibrated.sourceDoc.toStringAsFixed(3)}  (prior: 0.30)');

    // shadow history discovery
    print('\n=== SHADOW HISTORY (counterfactual dreaming) ===');
    final shadows = await discoverShadowHistory(effectivePath);
    print('shadow commits: ${shadows.commits.length}');
    final typeCounts = <String, int>{};
    for (final c in shadows.commits) {
      typeCounts[c.type.name] = (typeCounts[c.type.name] ?? 0) + 1;
    }
    for (final e in typeCounts.entries) {
      print('  ${e.key.padRight(20)} ${e.value}');
    }

    if (shadows.commits.isNotEmpty) {
      final shadowMatrix = computeShadowCoupling(shadows);
      if (shadowMatrix != null) {
        print('shadow coupling pairs: ${shadowMatrix.paths.length} files');

        // ghost couplings: pairs with shadow co-change but no real co-change
        final ghosts = <({String a, String b, double score})>[];
        for (final a in shadowMatrix.paths) {
          for (final entry in shadowMatrix.jaccardEntriesOf(a)) {
            if (matrix.jaccardScoreOf(a, entry.key) > 0) continue;
            ghosts.add((a: a, b: entry.key, score: entry.value));
          }
        }
        ghosts.sort((x, y) => y.score.compareTo(x.score));
        print('\ntop ghost couplings (shadow-only, no real co-change):');
        for (final g in ghosts.take(15)) {
          print('  ${g.score.toStringAsFixed(3)}  ${g.a} ↔ ${g.b}');
        }

        // blended calibration
        final blended = calibrateCouplingConstants(
          paths,
          (a, b) => matrix.jaccardScoreOf(a, b),
          jaccardEdges: (p) sync* {
            final seen = <String>{};
            for (final e in matrix.jaccardEntriesOf(p)) {
              seen.add(e.key);
              yield e;
            }
            for (final e in shadowMatrix.jaccardEntriesOf(p)) {
              if (seen.contains(e.key)) continue;
              yield MapEntry(e.key, e.value * sc.gasPhase);
            }
          },
        );
        print('\n=== BLENDED CALIBRATION (real + shadow) ===');
        print('  manifest↔lockfile  ${blended.manifestLockfile.toStringAsFixed(3)}  (real-only: ${calibrated.manifestLockfile.toStringAsFixed(3)})');
        print('  source↔generated   ${blended.sourceGenerated.toStringAsFixed(3)}  (real-only: ${calibrated.sourceGenerated.toStringAsFixed(3)})');
        print('  source↔test        ${blended.sourceTest.toStringAsFixed(3)}  (real-only: ${calibrated.sourceTest.toStringAsFixed(3)})');
        print('  source↔doc         ${blended.sourceDoc.toStringAsFixed(3)}  (real-only: ${calibrated.sourceDoc.toStringAsFixed(3)})');
      }
    }

    // --- regression assertions: pin derived constants ---
    // These verify the physics-derived constants haven't drifted.
    expect(sc.phi, closeTo(1.618, 0.001));
    expect(sc.gasPhase, closeTo(1.0 / 2.71828, 0.001));
    expect(sc.phiDecay1, closeTo(0.618, 0.001));
    expect(sc.phiDecay2, closeTo(0.382, 0.001));
    expect(sc.phiDecay3, closeTo(0.236, 0.001));
    expect(sc.kCcEvidenceSquare, equals(16.0));

    // Pin integrity engine constants derived from spectral_constants.
    // knee = phiDecay2 ≈ 0.382, rate = -ln(1-0.85)/(1-0.382) ≈ 3.069
    expect(kNeutralIntegrity, equals(0.85));
    final expectedKnee = sc.phiDecay2;
    final expectedRate =
        -math.log(1.0 - kNeutralIntegrity) / (1.0 - expectedKnee);
    expect(expectedKnee, closeTo(0.382, 0.001));
    expect(expectedRate, closeTo(3.069, 0.01));
    // Full-disparity ritual cap: exp(-rate * (1 - knee)) ≈ 0.15
    final fullDisparityCap =
        math.exp(-expectedRate * (1.0 - expectedKnee));
    expect(fullDisparityCap, closeTo(0.15, 0.01));
    // Prior weight = kCcEvidenceSquare = 16 → 50/50 at 16 samples
    expect(sc.kCcEvidenceSquare, equals(16.0));

    // Pin calibrated constants: verify they're within [0, 1] and
    // the prior-dominated values haven't collapsed to zero.
    expect(calibrated.sourceTest, greaterThan(0.1));
    expect(calibrated.sourceTest, lessThanOrEqualTo(1.0));
    expect(calibrated.sourceDoc, greaterThan(0.1));
    expect(calibrated.sourceDoc, lessThanOrEqualTo(1.0));
    expect(calibrated.manifestLockfile, greaterThan(0.5));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

String _roleLabel(TransportRoles r) {
  if (r.isManifest) return 'manifest';
  if (r.isLockfile) return 'lockfile';
  if (r.isGenerated) return 'generated';
  if (r.isTest) return 'test';
  if (r.isDoc) return 'doc';
  if (r.isMigration) return 'migration';
  if (r.isFixture) return 'fixture';
  if (r.isCiConfig) return 'ci-config';
  if (r.isSource) return 'source';
  return 'other';
}

String? _classifyPair(TransportRoles a, TransportRoles b) {
  if ((a.isManifest && b.isLockfile) || (b.isManifest && a.isLockfile)) {
    if (a.seedKey != null && a.seedKey == b.seedKey) {
      return 'manifest↔lockfile';
    }
  }
  if ((a.isSource && b.isTest) || (b.isSource && a.isTest)) return 'source↔test';
  if ((a.isSource && b.isGenerated) || (b.isSource && a.isGenerated)) return 'source↔generated';
  if ((a.isSource && b.isDoc) || (b.isSource && a.isDoc)) return 'source↔doc';
  if ((a.isSource && b.isMigration) || (b.isSource && a.isMigration)) return 'source↔migration';
  if ((a.isFixture && b.isSource) || (b.isFixture && a.isSource)) return 'fixture↔source';
  if ((a.isCiConfig && b.isSource) || (b.isCiConfig && a.isSource)) return 'ci-config↔source';
  return null;
}

double _pct(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final idx = (p * (sorted.length - 1)).clamp(0, sorted.length - 1);
  final lo = idx.floor();
  final hi = math.min(lo + 1, sorted.length - 1);
  final frac = idx - lo;
  return sorted[lo] * (1 - frac) + sorted[hi] * frac;
}
