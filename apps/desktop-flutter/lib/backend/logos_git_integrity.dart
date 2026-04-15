// logos_git_integrity.dart — semantic/ritual weighting + path integrity
//
// Keeps the heuristics that shape Logos's semantic-history stream and
// path transmissibility in one place so they do not get duplicated
// across stats collection, graph build, and downstream renderers.

import 'dart:math' as math;

class LogosIntegrityProfile {
  final Map<String, double> integrityByPath;
  final Map<String, double> ritualnessByPath;
  final Map<String, List<String>> reasonsByPath;

  const LogosIntegrityProfile({
    required this.integrityByPath,
    required this.ritualnessByPath,
    required this.reasonsByPath,
  });
}

class LogosCommitMeaningfulness {
  final double weight;
  final List<String> reasons;

  const LogosCommitMeaningfulness(this.weight, this.reasons);
}

const double kNeutralIntegrity = 0.85;

LogosCommitMeaningfulness inferCommitMeaningfulness({
  required String author,
  required String subject,
  required Iterable<String> paths,
}) {
  final reasons = <String>[];
  var weight = 1.0;

  final authorLower = author.toLowerCase();
  final subjectLower = subject.toLowerCase();
  final pathList = paths.map((p) => p.replaceAll('\\', '/')).toList(growable: false);
  if (pathList.isEmpty) {
    return const LogosCommitMeaningfulness(1.0, <String>[]);
  }

  final machineAuthor = authorLower.contains('bot') ||
      authorLower.contains('machine') ||
      authorLower.contains('dependabot') ||
      authorLower.contains('renovate') ||
      authorLower.contains('github-actions') ||
      authorLower.contains('[bot]');
  if (machineAuthor) {
    weight *= 0.45;
    reasons.add('machine-author');
  }

  final checkpointSubject = subjectLower.contains('checkpoint') ||
      subjectLower.contains('session') ||
      subjectLower.contains('synthetic sweep');
  if (checkpointSubject) {
    weight *= 0.2;
    reasons.add('checkpoint-subject');
  }

  final clericalSubject = subjectLower.contains('format') ||
      subjectLower.contains('reformat') ||
      subjectLower.contains('prettier') ||
      subjectLower.contains('rustfmt') ||
      subjectLower.contains('clang-format') ||
      subjectLower.contains('lint fix') ||
      subjectLower.contains('bump ') ||
      subjectLower.contains('version bump') ||
      subjectLower.contains('deps') ||
      subjectLower.contains('dependency') ||
      subjectLower.contains('lockfile');
  if (clericalSubject) {
    weight *= 0.6;
    reasons.add('clerical-subject');
  }

  var ritualPaths = 0;
  var sourceLikePaths = 0;
  for (final path in pathList) {
    if (_looksSourceLike(path)) sourceLikePaths++;
    if (_looksRitualPath(path)) ritualPaths++;
  }
  final ritualShare = ritualPaths / pathList.length;
  if (ritualShare >= 0.99) {
    weight *= 0.2;
    reasons.add('ritual-path-sweep');
  } else if (ritualShare >= 0.6) {
    weight *= 0.55;
    reasons.add('ritual-heavy');
  }

  if (sourceLikePaths > 0 && ritualShare < 1.0) {
    weight = math.max(weight, 0.55);
  }

  if (!weight.isFinite) weight = 1.0;
  weight = weight.clamp(0.0, 1.0);
  return LogosCommitMeaningfulness(weight, reasons);
}

LogosIntegrityProfile buildLogosIntegrityProfile({
  required Map<String, int> rawTouches,
  required Map<String, double> semanticTouchMass,
  required Map<String, double> ritualMassByPath,
}) {
  final integrity = <String, double>{};
  final ritualness = <String, double>{};
  final reasons = <String, List<String>>{};

  final allPaths = <String>{...rawTouches.keys, ...semanticTouchMass.keys, ...ritualMassByPath.keys};
  for (final path in allPaths) {
    final pathReasons = <String>[];
    final raw = (rawTouches[path] ?? 0).toDouble();
    final semantic = semanticTouchMass[path] ?? 0.0;
    final ritual = ritualMassByPath[path] ?? 0.0;
    final ratio = raw <= 0 ? 0.0 : (ritual / raw).clamp(0.0, 1.0);
    ritualness[path] = ratio;

    var estimate = 1.0;
    final cue = _pathCueIntegrity(path, pathReasons);
    estimate = math.min(estimate, cue);

    // History-based ritualness pull-down. Keep conservative; this is a
    // transmissibility estimate, not an exclusion oracle.
    estimate = math.min(estimate, 1.0 - 0.65 * ratio);

    final disparity = raw <= 0 ? 0.0 : ((raw - semantic).clamp(0.0, raw)) / raw;
    if (disparity >= 0.6) {
      estimate = math.min(estimate, 0.45);
      pathReasons.add('raw-semantic-disparity');
    }

    // Confidence / shrinkage: sparse evidence stays near neutral.
    final evidence = raw + semantic;
    final confidence = (1.0 - math.exp(-evidence / 6.0)).clamp(0.0, 1.0);
    final shrunk = kNeutralIntegrity + (estimate - kNeutralIntegrity) * confidence;
    integrity[path] = shrunk.clamp(0.1, 1.0);
    if (ratio >= 0.5) pathReasons.add('ritual-history');
    reasons[path] = pathReasons;
  }

  return LogosIntegrityProfile(
    integrityByPath: integrity,
    ritualnessByPath: ritualness,
    reasonsByPath: reasons,
  );
}

double logosPairPenalty(String a, String b) {
  final an = a.replaceAll('\\', '/').toLowerCase();
  final bn = b.replaceAll('\\', '/').toLowerCase();
  if (_isManifestLike(an) && _isLockfileLike(bn)) return 0.45;
  if (_isManifestLike(bn) && _isLockfileLike(an)) return 0.45;
  if (_looksGenerated(an) && _looksSourceLike(bn)) return 0.55;
  if (_looksGenerated(bn) && _looksSourceLike(an)) return 0.55;
  if (_looksGenerated(an) && _looksGenerated(bn)) return 0.35;
  if (_looksFixtureLike(an) && _looksFixtureLike(bn)) return 0.6;
  return 1.0;
}

double logosWitnessPrivilege(String a, String b) {
  final an = a.replaceAll('\\', '/').toLowerCase();
  final bn = b.replaceAll('\\', '/').toLowerCase();
  if ((_isManifestLike(an) && _isLockfileLike(bn)) ||
      (_isManifestLike(bn) && _isLockfileLike(an))) {
    return 0.35;
  }
  if ((_looksGenerated(an) && _looksSourceLike(bn)) ||
      (_looksGenerated(bn) && _looksSourceLike(an))) {
    return 0.30;
  }
  return 0.0;
}

bool _looksSourceLike(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.dart') ||
      lower.endsWith('.ts') ||
      lower.endsWith('.tsx') ||
      lower.endsWith('.js') ||
      lower.endsWith('.jsx') ||
      lower.endsWith('.rs') ||
      lower.endsWith('.py') ||
      lower.endsWith('.go') ||
      lower.endsWith('.java') ||
      lower.endsWith('.kt') ||
      lower.endsWith('.swift') ||
      lower.endsWith('.c') ||
      lower.endsWith('.cc') ||
      lower.endsWith('.cpp') ||
      lower.endsWith('.h');
}

bool _looksRitualPath(String path) =>
    _looksGenerated(path) ||
    _looksVendor(path) ||
    _isLockfileLike(path) ||
    path.contains('/build/') ||
    path.contains('/dist/') ||
    path.contains('/coverage/') ||
    path.contains('/.dart_tool/') ||
    path.contains('/target/');

bool _looksGenerated(String path) =>
    path.contains('/generated/') ||
    path.contains('/gen/') ||
    path.endsWith('.g.dart') ||
    path.endsWith('.pb.dart') ||
    path.endsWith('.gr.dart') ||
    path.endsWith('.designer.cs') ||
    path.endsWith('.generated.ts') ||
    path.endsWith('.generated.js') ||
    path.endsWith('.min.js');

bool _looksVendor(String path) =>
    path.contains('/vendor/') ||
    path.contains('/third_party/') ||
    path.contains('/node_modules/');

bool _isManifestLike(String path) =>
    path.endsWith('package.json') ||
    path.endsWith('pubspec.yaml') ||
    path.endsWith('pubspec.yml') ||
    path.endsWith('cargo.toml') ||
    path.endsWith('package.swift') ||
    path.endsWith('requirements.txt') ||
    path.endsWith('pyproject.toml');

bool _isLockfileLike(String path) =>
    path.endsWith('package-lock.json') ||
    path.endsWith('pnpm-lock.yaml') ||
    path.endsWith('yarn.lock') ||
    path.endsWith('cargo.lock') ||
    path.endsWith('pubspec.lock') ||
    path.endsWith('poetry.lock') ||
    path.endsWith('composer.lock') ||
    path.endsWith('gemfile.lock') ||
    path.endsWith('.lock');

bool _looksFixtureLike(String path) =>
    path.contains('/fixtures/') ||
    path.contains('/fixture/') ||
    path.contains('/mocks/') ||
    path.contains('/mock/') ||
    path.contains('/examples/') ||
    path.contains('/example/') ||
    path.contains('/snapshots/') ||
    path.contains('/snapshot/');

double _pathCueIntegrity(String path, List<String> reasons) {
  final lower = path.toLowerCase();
  if (_looksGenerated(lower)) {
    reasons.add('generated');
    return 0.22;
  }
  if (_looksVendor(lower)) {
    reasons.add('vendor');
    return 0.18;
  }
  if (_isLockfileLike(lower)) {
    reasons.add('lockfile');
    return 0.18;
  }
  if (_looksFixtureLike(lower)) {
    reasons.add('fixture-like');
    return 0.58;
  }
  if (lower.contains('/deprecated/') || lower.contains('/legacy/')) {
    reasons.add('legacy');
    return 0.72;
  }
  if (lower.contains('/build/') ||
      lower.contains('/dist/') ||
      lower.contains('/coverage/') ||
      lower.contains('/.dart_tool/') ||
      lower.contains('/target/')) {
    reasons.add('build-output');
    return 0.2;
  }
  return 1.0;
}
