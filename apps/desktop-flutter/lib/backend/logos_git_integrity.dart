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
  // Smooth exponential decay: 1.0 at ritualShare ≤ 0.4, 0.2 at 1.0.
  // -ln(0.2) / 0.6 ≈ 2.682 — derived, not tuned.
  final ritualMul =
      math.exp(-2.6823623981 * math.max(0.0, ritualShare - 0.4));
  weight *= ritualMul;
  if (ritualMul < 0.35) {
    reasons.add('ritual-path-sweep');
  } else if (ritualMul < 0.85) {
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

  // Derive shrinkage tau from the repo's evidence density: the 25th
  // percentile of per-file touch counts. Repos where even the
  // least-touched files have 20 commits need a higher tau than
  // repos where most files have 2 commits.
  final touchCounts = rawTouches.values.toList()..sort();
  final shrinkageTau = touchCounts.isEmpty
      ? 6.0
      : math.max(3.0, touchCounts[touchCounts.length ~/ 4].toDouble());

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
    final confidence = (1.0 - math.exp(-evidence / shrinkageTau)).clamp(0.0, 1.0);
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

class LogosTransportLane {
  final String label;
  final double strength;
  final String note;
  final String? sourceRole;
  final String? targetRole;
  final bool directional;

  const LogosTransportLane({
    required this.label,
    required this.strength,
    required this.note,
    this.sourceRole,
    this.targetRole,
    this.directional = true,
  });
}

class LogosRelationDescriptor {
  final String label;
  final double strength;
  final String? note;
  final String? sourceRole;
  final String? targetRole;
  final bool directional;

  const LogosRelationDescriptor({
    required this.label,
    required this.strength,
    this.note,
    this.sourceRole,
    this.targetRole,
    this.directional = false,
  });
}

/// Fast variant of [logosPairPenalty] on precomputed roles. Callers
/// building an n² candidate loop should build one [TransportRoles] per
/// unique path once and reuse across every pairing — otherwise the
/// string normalisation + seed-key + 8 pattern-match sweep fires 2×
/// per pair inside every call below. Byte-identical to the raw-string
/// variant for the same inputs.
double logosPairPenaltyOfRoles(TransportRoles a, TransportRoles b) {
  if (a._sharesManifestRoot(b) &&
      ((a.isManifest && b.isLockfile) ||
          (b.isManifest && a.isLockfile))) {
    return 0.45;
  }
  final sharesConcept = a._sharesTransportConcept(b);
  if (sharesConcept &&
      ((a.isGenerated && b.isSource) || (b.isGenerated && a.isSource))) {
    return 0.55;
  }
  if (sharesConcept &&
      ((!a.isTest && a.isSource && b.isTest) ||
          (!b.isTest && b.isSource && a.isTest))) {
    return 0.62;
  }
  if (sharesConcept &&
      ((!a.isDoc && a.isSource && b.isDoc) ||
          (!b.isDoc && b.isSource && a.isDoc))) {
    return 0.74;
  }
  if (sharesConcept &&
      ((!a.isMigration && a.isSource && b.isMigration) ||
          (!b.isMigration && b.isSource && a.isMigration))) {
    return 0.60;
  }
  if (a.isGenerated && b.isGenerated) return 0.35;
  if (a.isFixture && b.isFixture) return 0.6;
  if ((a.isFixture && !b.isFixture) || (b.isFixture && !a.isFixture)) {
    return 0.82;
  }
  // Vendor check isn't cached on TransportRoles yet — fall back to the
  // raw-path predicate on the already-normalised string field.
  if (_looksVendor(a.normalized) || _looksVendor(b.normalized)) return 0.9;
  return 1.0;
}

double logosPairPenalty(String a, String b) {
  final an = a.replaceAll('\\', '/').toLowerCase();
  final bn = b.replaceAll('\\', '/').toLowerCase();
  if (_sharesManifestRoot(an, bn) &&
      ((_isManifestLike(an) && _isLockfileLike(bn)) ||
          (_isManifestLike(bn) && _isLockfileLike(an)))) {
    return 0.45;
  }
  if (_sharesTransportConcept(an, bn) &&
      ((_looksGenerated(an) && _looksSourceLike(bn)) ||
          (_looksGenerated(bn) && _looksSourceLike(an)))) {
    return 0.55;
  }
  if (_sharesTransportConcept(an, bn) &&
      (((!_looksTestLike(an) && _looksSourceLike(an) && _looksTestLike(bn))) ||
          ((!_looksTestLike(bn) &&
              _looksSourceLike(bn) &&
              _looksTestLike(an))))) {
    return 0.62;
  }
  if (_sharesTransportConcept(an, bn) &&
      (((!_looksDocLike(an) && _looksSourceLike(an) && _looksDocLike(bn))) ||
          ((!_looksDocLike(bn) && _looksSourceLike(bn) && _looksDocLike(an))))) {
    return 0.74;
  }
  if (_sharesTransportConcept(an, bn) &&
      (((!_looksMigrationLike(an) &&
                  _looksSourceLike(an) &&
                  _looksMigrationLike(bn))) ||
              ((!_looksMigrationLike(bn) &&
                  _looksSourceLike(bn) &&
                  _looksMigrationLike(an))))) {
    return 0.60;
  }
  if (_looksGenerated(an) && _looksGenerated(bn)) return 0.35;
  if (_looksFixtureLike(an) && _looksFixtureLike(bn)) return 0.6;
  if ((_looksFixtureLike(an) && !_looksFixtureLike(bn)) ||
      (_looksFixtureLike(bn) && !_looksFixtureLike(an))) {
    return 0.82;
  }
  if (_looksVendor(an) || _looksVendor(bn)) return 0.9;
  return 1.0;
}

double logosWitnessPrivilege(String a, String b) {
  final an = a.replaceAll('\\', '/').toLowerCase();
  final bn = b.replaceAll('\\', '/').toLowerCase();
  if (_sharesManifestRoot(an, bn) &&
      ((_isManifestLike(an) && _isLockfileLike(bn)) ||
          (_isManifestLike(bn) && _isLockfileLike(an)))) {
    return 0.35;
  }
  if (_sharesTransportConcept(an, bn) &&
      ((_looksGenerated(an) && _looksSourceLike(bn)) ||
          (_looksGenerated(bn) && _looksSourceLike(an)))) {
    return 0.30;
  }
  if (_sharesTransportConcept(an, bn) &&
      (((!_looksTestLike(an) && _looksSourceLike(an) && _looksTestLike(bn))) ||
          ((!_looksTestLike(bn) &&
              _looksSourceLike(bn) &&
              _looksTestLike(an))))) {
    return 0.28;
  }
  if (_sharesTransportConcept(an, bn) &&
      (((!_looksDocLike(an) && _looksSourceLike(an) && _looksDocLike(bn))) ||
          ((!_looksDocLike(bn) && _looksSourceLike(bn) && _looksDocLike(an))))) {
    return 0.16;
  }
  if (_sharesTransportConcept(an, bn) &&
      (((!_looksMigrationLike(an) &&
                  _looksSourceLike(an) &&
                  _looksMigrationLike(bn))) ||
              ((!_looksMigrationLike(bn) &&
                  _looksSourceLike(bn) &&
                  _looksMigrationLike(an))))) {
    return 0.24;
  }
  return 0.0;
}

double logosRelationStrength(String a, String b) {
  return logosRelationDescriptor(a, b)?.strength ?? 0.0;
}

String? logosRelationLabel(String a, String b) {
  return logosRelationDescriptor(a, b)?.label;
}

LogosRelationDescriptor? logosRelationDescriptor(String source, String candidate) {
  final an = source.replaceAll('\\', '/').toLowerCase();
  final bn = candidate.replaceAll('\\', '/').toLowerCase();
  final strength = math.max(
    logosWitnessPrivilege(source, candidate),
    1.0 - logosPairPenalty(source, candidate),
  ).clamp(0.0, 1.0).toDouble();
  if (_sharesManifestRoot(an, bn) &&
      ((_isManifestLike(an) && _isLockfileLike(bn)) ||
          (_isManifestLike(bn) && _isLockfileLike(an)))) {
    return LogosRelationDescriptor(
      label: 'manifest-lockfile',
      strength: strength,
      note: _isManifestLike(an) ? 'lockfile witness' : 'manifest witness',
      sourceRole: _isManifestLike(an) ? 'manifest' : 'lockfile',
      targetRole: _isManifestLike(an) ? 'lockfile' : 'manifest',
      directional: true,
    );
  }
  if (_sharesTransportConcept(an, bn) &&
      ((_looksGenerated(an) && _looksSourceLike(bn)) ||
          (_looksGenerated(bn) && _looksSourceLike(an)))) {
    return LogosRelationDescriptor(
      label: 'source-generated',
      strength: strength,
      note: _looksGenerated(an)
          ? 'source-of-truth witness'
          : 'generated companion witness',
      sourceRole: _looksGenerated(an) ? 'generated' : 'source',
      targetRole: _looksGenerated(an) ? 'source' : 'generated',
      directional: true,
    );
  }
  if (_sharesTransportConcept(an, bn) &&
      (((!_looksTestLike(an) && _looksSourceLike(an) && _looksTestLike(bn))) ||
          ((!_looksTestLike(bn) &&
              _looksSourceLike(bn) &&
              _looksTestLike(an))))) {
    final sourceToTest =
        !_looksTestLike(an) && _looksSourceLike(an) && _looksTestLike(bn);
    return LogosRelationDescriptor(
      label: 'source-test',
      strength: strength,
      note: sourceToTest ? 'test witness' : 'behavior/source witness',
      sourceRole: sourceToTest ? 'source' : 'test',
      targetRole: sourceToTest ? 'test' : 'source',
      directional: true,
    );
  }
  if (_sharesTransportConcept(an, bn) &&
      (((!_looksDocLike(an) && _looksSourceLike(an) && _looksDocLike(bn))) ||
          ((!_looksDocLike(bn) && _looksSourceLike(bn) && _looksDocLike(an))))) {
    final sourceToDoc =
        !_looksDocLike(an) && _looksSourceLike(an) && _looksDocLike(bn);
    return LogosRelationDescriptor(
      label: 'source-doc',
      strength: strength,
      note: sourceToDoc ? 'documentation witness' : 'behavior/source witness',
      sourceRole: sourceToDoc ? 'source' : 'doc',
      targetRole: sourceToDoc ? 'doc' : 'source',
      directional: true,
    );
  }
  if (_sharesTransportConcept(an, bn) &&
      (((!_looksMigrationLike(an) &&
                  _looksSourceLike(an) &&
                  _looksMigrationLike(bn))) ||
              ((!_looksMigrationLike(bn) &&
                  _looksSourceLike(bn) &&
                  _looksMigrationLike(an))))) {
    final sourceToMigration = !_looksMigrationLike(an) &&
        _looksSourceLike(an) &&
        _looksMigrationLike(bn);
    return LogosRelationDescriptor(
      label: 'source-migration',
      strength: strength,
      note: sourceToMigration ? 'migration witness' : 'source-of-truth witness',
      sourceRole: sourceToMigration ? 'source' : 'migration',
      targetRole: sourceToMigration ? 'migration' : 'source',
      directional: true,
    );
  }
  if ((_looksFixtureLike(an) && !_looksFixtureLike(bn)) ||
      (_looksFixtureLike(bn) && !_looksFixtureLike(an))) {
    return LogosRelationDescriptor(
      label: 'test-fixture',
      strength: strength,
      note: _looksFixtureLike(an) ? 'test witness' : 'fixture witness',
      sourceRole: _looksFixtureLike(an) ? 'fixture' : 'source',
      targetRole: _looksFixtureLike(an) ? 'source' : 'fixture',
      directional: true,
    );
  }
  if (_looksVendor(an) || _looksVendor(bn)) {
    return LogosRelationDescriptor(
      label: 'vendor-boundary',
      strength: strength,
      note: 'vendor boundary',
      sourceRole: _looksVendor(an) ? 'vendor' : 'code',
      targetRole: _looksVendor(an) ? 'code' : 'vendor',
      directional: false,
    );
  }
  if ((_looksGenerated(an) && _looksGenerated(bn))) {
    return LogosRelationDescriptor(
      label: 'generated-generated',
      strength: strength,
      note: 'generated cluster',
      sourceRole: 'generated',
      targetRole: 'generated',
      directional: false,
    );
  }
  return null;
}

/// Precomputed role-of-path cache. `logosTransportLane` called in a
/// tight loop (ranked-list construction inside `gatherEvidence`, once
/// per focus × candidate pair) spent 95%+ of its cost re-running the
/// same path-normalization + role-classification + seed-key token
/// extraction on the same strings. Build one of these per unique
/// path, reuse across every pairing.
class TransportRoles {
  TransportRoles._(
    this.normalized,
    this.seedKey,
    this.isManifest,
    this.isLockfile,
    this.isSource,
    this.isTest,
    this.isDoc,
    this.isMigration,
    this.isGenerated,
    this.isFixture,
    this.isCiConfig,
  );

  factory TransportRoles.of(String path) {
    final n = path.replaceAll('\\', '/').toLowerCase();
    return TransportRoles._(
      n,
      logosTransportSeedKey(n),
      _isManifestLike(n),
      _isLockfileLike(n),
      _looksSourceLikeNorm(n),
      _looksTestLike(n),
      _looksDocLike(n),
      _looksMigrationLike(n),
      _looksGenerated(n),
      _looksFixtureLike(n),
      _looksCiConfig(n),
    );
  }

  final String normalized;
  final String? seedKey;
  final bool isManifest;
  final bool isLockfile;
  final bool isSource;
  final bool isTest;
  final bool isDoc;
  final bool isMigration;
  final bool isGenerated;
  final bool isFixture;
  final bool isCiConfig;

  bool _sharesManifestRoot(TransportRoles other) =>
      seedKey != null &&
      seedKey == other.seedKey &&
      seedKey!.startsWith('manifest:');

  bool _sharesTransportConcept(TransportRoles other) =>
      seedKey != null &&
      seedKey == other.seedKey &&
      seedKey!.startsWith('concept:');
}

/// Fast transport-lane lookup on pre-computed roles. Intended for hot
/// loops that make N×M lookups across two path sets — build one
/// [TransportRoles] per unique path once, reuse here. The returned
/// value is byte-identical to [logosTransportLane] called with the
/// same raw strings.
LogosTransportLane? logosTransportLaneOfRoles(
    TransportRoles src, TransportRoles cand) {
  final sharesManifest = src._sharesManifestRoot(cand);
  if (sharesManifest && src.isManifest && cand.isLockfile) {
    return const LogosTransportLane(
      label: 'manifest->lockfile',
      strength: 0.34,
      note: 'receive-heavy witness',
      sourceRole: 'manifest',
      targetRole: 'lockfile',
    );
  }
  if (sharesManifest && src.isLockfile && cand.isManifest) {
    return const LogosTransportLane(
      label: 'lockfile->manifest',
      strength: 0.46,
      note: 'receive-heavy witness',
      sourceRole: 'lockfile',
      targetRole: 'manifest',
    );
  }
  final sharesConcept = src._sharesTransportConcept(cand);
  if (sharesConcept && src.isSource && cand.isGenerated) {
    return const LogosTransportLane(
      label: 'source->generated',
      strength: 0.28,
      note: 'generated companion witness',
      sourceRole: 'source',
      targetRole: 'generated',
    );
  }
  if (sharesConcept && src.isGenerated && cand.isSource) {
    return const LogosTransportLane(
      label: 'generated->source',
      strength: 0.44,
      note: 'source-of-truth witness',
      sourceRole: 'generated',
      targetRole: 'source',
    );
  }
  if (sharesConcept && !src.isTest && src.isSource && cand.isTest) {
    return const LogosTransportLane(
      label: 'source->test',
      strength: 0.18,
      note: 'test witness',
      sourceRole: 'source',
      targetRole: 'test',
    );
  }
  if (sharesConcept && src.isTest && cand.isSource && !cand.isTest) {
    return const LogosTransportLane(
      label: 'test->source',
      strength: 0.24,
      note: 'behavior/source witness',
      sourceRole: 'test',
      targetRole: 'source',
    );
  }
  if (sharesConcept && !src.isDoc && src.isSource && cand.isDoc) {
    return const LogosTransportLane(
      label: 'source->doc',
      strength: 0.12,
      note: 'documentation witness',
      sourceRole: 'source',
      targetRole: 'doc',
    );
  }
  if (sharesConcept && src.isDoc && cand.isSource && !cand.isDoc) {
    return const LogosTransportLane(
      label: 'doc->source',
      strength: 0.18,
      note: 'behavior/source witness',
      sourceRole: 'doc',
      targetRole: 'source',
    );
  }
  if (sharesConcept &&
      !src.isMigration &&
      src.isSource &&
      cand.isMigration) {
    return const LogosTransportLane(
      label: 'source->migration',
      strength: 0.20,
      note: 'migration witness',
      sourceRole: 'source',
      targetRole: 'migration',
    );
  }
  if (sharesConcept &&
      src.isMigration &&
      cand.isSource &&
      !cand.isMigration) {
    return const LogosTransportLane(
      label: 'migration->source',
      strength: 0.28,
      note: 'source-of-truth witness',
      sourceRole: 'migration',
      targetRole: 'source',
    );
  }
  if (src.isFixture && !cand.isFixture) {
    return const LogosTransportLane(
      label: 'fixture->source',
      strength: 0.20,
      note: 'test witness',
      sourceRole: 'fixture',
      targetRole: 'source',
    );
  }
  if (!src.isFixture && cand.isFixture) {
    return const LogosTransportLane(
      label: 'source->fixture',
      strength: 0.16,
      note: 'fixture witness',
      sourceRole: 'source',
      targetRole: 'fixture',
    );
  }
  if (src.isSource && cand.isCiConfig) {
    return const LogosTransportLane(
      label: 'source->ci-config',
      strength: 0.14,
      note: 'CI configuration witness',
      sourceRole: 'source',
      targetRole: 'ci-config',
    );
  }
  if (src.isCiConfig && cand.isSource) {
    return const LogosTransportLane(
      label: 'ci-config->source',
      strength: 0.22,
      note: 'CI-driven source witness',
      sourceRole: 'ci-config',
      targetRole: 'source',
    );
  }
  return null;
}

LogosTransportLane? logosTransportLane(String source, String candidate) {
  final src = TransportRoles.of(source);
  final cand = TransportRoles.of(candidate);
  return logosTransportLaneOfRoles(src, cand);
}

String? logosTransportSeedKey(String path) {
  final lower = path.replaceAll('\\', '/').toLowerCase();
  if (_isManifestLike(lower) || _isLockfileLike(lower)) {
    return 'manifest:${_parentDirKey(lower)}';
  }
  if (_looksSourceLike(lower) ||
      _looksGenerated(lower) ||
      _looksTestLike(lower) ||
      _looksDocLike(lower) ||
      _looksMigrationLike(lower)) {
    final tokens = _transportConceptTokens(lower);
    if (tokens.isEmpty) return null;
    return 'concept:${tokens.join("-")}';
  }
  return null;
}

bool _looksSourceLike(String path) => _looksSourceLikeNorm(path.toLowerCase());

/// Norm variant — caller guarantees [path] is already lowercase. Used
/// by [TransportRoles.of] to avoid a per-role lowercase allocation.
bool _looksSourceLikeNorm(String path) =>
    path.endsWith('.dart') ||
    path.endsWith('.ts') ||
    path.endsWith('.tsx') ||
    path.endsWith('.js') ||
    path.endsWith('.jsx') ||
    path.endsWith('.rs') ||
    path.endsWith('.py') ||
    path.endsWith('.go') ||
    path.endsWith('.java') ||
    path.endsWith('.kt') ||
    path.endsWith('.swift') ||
    path.endsWith('.c') ||
    path.endsWith('.cc') ||
    path.endsWith('.cpp') ||
    path.endsWith('.h');

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

bool _looksTestLike(String path) =>
    path.contains('/test/') ||
    path.contains('/tests/') ||
    path.endsWith('_test.dart') ||
    path.endsWith('.test.ts') ||
    path.endsWith('.test.tsx') ||
    path.endsWith('.spec.ts') ||
    path.endsWith('.spec.tsx') ||
    path.endsWith('.test.js') ||
    path.endsWith('.spec.js');

bool _looksDocLike(String path) =>
    path.contains('/docs/') ||
    path.contains('/doc/') ||
    path.endsWith('/readme.md') ||
    path.endsWith('/readme.mdx') ||
    path.endsWith('.md') ||
    path.endsWith('.mdx') ||
    path.endsWith('.rst');

bool _looksMigrationLike(String path) =>
    path.contains('/migration/') ||
    path.contains('/migrations/') ||
    path.contains('/db/migrate/') ||
    path.contains('/db/migrations/') ||
    path.contains('/schema/') ||
    path.endsWith('.sql');

String _parentDirKey(String path) {
  final slash = path.lastIndexOf('/');
  // Top-level files have no slash; use a sentinel so sibling
  // top-level files (e.g. `pubspec.yaml` ↔ `pubspec.lock` in a
  // single-project repo root) still share a seed key. Empty string
  // would've caused the seed-key nullability check to reject them.
  if (slash < 0) return '.';
  if (slash == 0) return '/';
  return path.substring(0, slash);
}

bool _sharesManifestRoot(String a, String b) {
  final ak = logosTransportSeedKey(a);
  final bk = logosTransportSeedKey(b);
  return ak != null && ak == bk && ak.startsWith('manifest:');
}

bool _sharesTransportConcept(String a, String b) {
  final ak = logosTransportSeedKey(a);
  final bk = logosTransportSeedKey(b);
  return ak != null && ak == bk && ak.startsWith('concept:');
}

final _transportNoise = <String>{
  'test',
  'tests',
  'spec',
  'specs',
  'doc',
  'docs',
  'readme',
  'generated',
  'generate',
  'gen',
  'migration',
  'migrations',
  'schema',
  'sql',
  'index',
  'main',
  'lib',
  'src',
  'add',
  'update',
  'create',
  'delete',
};

final _transportNonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _transportCamelBoundary =
    RegExp(r'(?<=[\p{Ll}\p{N}])(?=[\p{Lu}])', unicode: true);
/// Strip the rightmost `.<ext>` suffix from a stem. Hoisted because
/// [_transportConceptTokens] runs for every file in the repo during an
/// integrity profile build and was previously building a fresh `RegExp`
/// per stem — O(n) throw-away NFA compilations per call.
final _transportExtension = RegExp(r'\.[^.]+$');
/// Reject all-digit tokens (line numbers, version fragments). Hoisted
/// for the same reason — [_normalizeTransportToken] is called for
/// every sub-token of every path and was rebuilding this NFA per hit.
final _transportAllDigits = RegExp(r'^\d+$');

List<String> _transportConceptTokens(String path) {
  final parts = path.split('/');
  final raw = <String>[];
  if (parts.isNotEmpty) raw.add(parts.last);
  if ((_looksDocLike(path) || _looksMigrationLike(path)) && parts.length > 1) {
    raw.add(parts[parts.length - 2]);
  }
  final tokens = <String>{};
  for (final piece in raw) {
    final stem = piece.replaceAll(_transportExtension, '');
    for (final word in stem.split(_transportNonWord)) {
      if (word.isEmpty) continue;
      for (final sub in word.split(_transportCamelBoundary)) {
        final token = _normalizeTransportToken(sub);
        if (token == null) continue;
        tokens.add(token);
      }
    }
  }
  final ordered = tokens.toList()..sort();
  return ordered;
}

String? _normalizeTransportToken(String token) {
  var lower = token.toLowerCase();
  if (lower.length < 3) return null;
  if (_transportNoise.contains(lower)) return null;
  if (_transportAllDigits.hasMatch(lower)) return null;
  if (lower.endsWith('ies') && lower.length > 4) {
    lower = '${lower.substring(0, lower.length - 3)}y';
  } else if (lower.endsWith('s') && lower.length > 4) {
    lower = lower.substring(0, lower.length - 1);
  }
  if (_transportNoise.contains(lower) || lower.length < 3) return null;
  return lower;
}

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

bool _looksCiConfig(String path) =>
    path.contains('/.github/workflows/') ||
    path.endsWith('.gitlab-ci.yml') ||
    path.contains('/.gitlab/ci/') ||
    path.endsWith('.woodpecker.yml') ||
    path.contains('/.woodpecker/') ||
    path.endsWith('.drone.yml') ||
    path.contains('/.forgejo/workflows/');

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
