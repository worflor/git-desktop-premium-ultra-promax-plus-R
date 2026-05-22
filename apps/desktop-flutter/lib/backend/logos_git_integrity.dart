// logos_git_integrity.dart — semantic/ritual weighting + path integrity
//
// Keeps the heuristics that shape Logos's semantic-history stream and
// path transmissibility in one place so they do not get duplicated
// across stats collection, graph build, and downstream renderers.

import 'dart:math' as math;

import 'spectral_constants.dart' as sc;

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

// Ritual decay knee: 1/φ² ≈ 0.382
final double _kRitualDecayKnee = sc.phiDecay2;

// Decay rate: -ln(1 - kNeutralIntegrity) / (1 - knee).
final double _kRitualDecayRate =
    -math.log(1.0 - kNeutralIntegrity) / (1.0 - _kRitualDecayKnee);

LogosCommitMeaningfulness inferCommitMeaningfulness({
  required String author,
  required String subject,
  required Iterable<String> paths,
  int? totalLinesChanged,
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
  final ritualMul =
      math.exp(-_kRitualDecayRate * math.max(0.0, ritualShare - _kRitualDecayKnee));
  weight *= ritualMul;
  if (ritualMul < 0.35) {
    reasons.add('ritual-path-sweep');
  } else if (ritualMul < 0.85) {
    reasons.add('ritual-heavy');
  }

  if (sourceLikePaths > 0 && ritualShare < 1.0) {
    weight = math.max(weight, kNeutralIntegrity - 0.30);
  }

  if (totalLinesChanged != null && pathList.length >= 8) {
    final density = totalLinesChanged / pathList.length;
    if (density < sc.phi * sc.phi) {
      weight *= _kRitualDecayKnee;
      reasons.add('low-edit-density');
    }
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

    // History-based ritualness pull-down: same exponential form as the
    // Commit-level ritual decay — same knee and rate as the disparity
    // pulldown below. One thermodynamic rule, two applications.
    final ritualCap = math.exp(-_kRitualDecayRate * math.max(0.0, ratio - _kRitualDecayKnee));
    estimate = math.min(estimate, ritualCap);

    // Raw-semantic disparity: same exponential family, same knee.
    final disparity = raw <= 0 ? 0.0 : ((raw - semantic).clamp(0.0, raw)) / raw;
    if (disparity > _kRitualDecayKnee) {
      final disparityMul = sc.gasPhase +
          (1.0 - sc.gasPhase) *
              math.exp(-_kRitualDecayRate * (disparity - _kRitualDecayKnee));
      estimate = math.min(estimate, disparityMul);
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

/// Per-role signal transmissivity: how much structural information a
/// file of this role carries. Source code = 1.0 (pure signal); vendor
/// = near-zero (noise). The pair penalty between two files is the
/// geometric mean of their transmissivities — one number per role
/// replaces 9 scattered per-pair magic numbers.
double _roleTransmissivity(TransportRoles r) {
  if (r.isGenerated) return 0.30;
  if (_looksVendor(r.normalized)) return 0.20;
  if (r.isLockfile) return 0.20;
  if (r.isFixture) return 0.60;
  if (r.isMigration) return 0.36;
  if (r.isTest) return 0.38;
  if (r.isDoc) return 0.55;
  if (r.isManifest) return 0.68;
  if (r.isCiConfig) return 0.26;
  return 1.0; // source, unknown
}

/// Fast variant of [logosPairPenalty] on precomputed roles. The pair
/// penalty is the geometric mean of the two roles' transmissivities
/// when a transport concept or manifest root links them. Without a
/// structural link, co-occurrence is taken at face value (1.0).
double logosPairPenaltyOfRoles(TransportRoles a, TransportRoles b) {
  final linked = a._sharesManifestRoot(b) || a._sharesTransportConcept(b);
  if (!linked) {
    // Unlinked roles: only penalise if one endpoint is inherently low-
    // signal (vendor, generated×generated). Geometric mean still
    // applies — it just uses both roles raw.
    final ta = _roleTransmissivity(a);
    final tb = _roleTransmissivity(b);
    final lower = math.min(ta, tb);
    if (lower >= 0.9) return 1.0;
    return math.sqrt(ta * tb);
  }
  return math.sqrt(_roleTransmissivity(a) * _roleTransmissivity(b));
}

double logosPairPenalty(String a, String b) {
  return logosPairPenaltyOfRoles(TransportRoles.of(a), TransportRoles.of(b));
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
  final strength =
      (1.0 - logosPairPenalty(source, candidate)).clamp(0.0, 1.0);
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

const double _kDirectionalBias = 0.15;

// Prior coupling constants — cold-start defaults that get blended
// out as the repo's own co-change fossil record accumulates evidence.
// Shrinkage strength: the prior carries the weight of k² effective
// samples, where k=4 is the number of distinguishable co-change regimes
// on the CC axis (same information-theoretic basis as the Born mixer's
// evidence cap ln(4) = 2·ln(2)). At n=16 empirical samples, the
// calibrated value is 50/50 prior/empirical.
const double _kPriorWeight = sc.kCcEvidenceSquare;
const double _kPriorManifestLockfile = 0.80;
const double _kPriorSourceGenerated = 0.72;
const double _kPriorSourceMigration = 0.48;
const double _kPriorSourceTest = 0.42;
const double _kPriorFixture = 0.36;
const double _kPriorCiConfig = 0.36;
const double _kPriorSourceDoc = 0.30;

class CouplingConstants {
  final double manifestLockfile;
  final double sourceGenerated;
  final double sourceMigration;
  final double sourceTest;
  final double fixture;
  final double ciConfig;
  final double sourceDoc;

  const CouplingConstants({
    this.manifestLockfile = _kPriorManifestLockfile,
    this.sourceGenerated = _kPriorSourceGenerated,
    this.sourceMigration = _kPriorSourceMigration,
    this.sourceTest = _kPriorSourceTest,
    this.fixture = _kPriorFixture,
    this.ciConfig = _kPriorCiConfig,
    this.sourceDoc = _kPriorSourceDoc,
  });

  static const prior = CouplingConstants();
}

CouplingConstants calibrateCouplingConstants(
  List<String> paths,
  double Function(String a, String b) jaccardScore, {
  Iterable<MapEntry<String, double>> Function(String path)? jaccardEdges,
}) {
  final roles = <String, TransportRoles>{};
  for (final p in paths) {
    roles[p] = TransportRoles.of(p);
  }

  final sums = <String, double>{};
  final counts = <String, int>{};

  if (jaccardEdges != null) {
    for (final a in paths) {
      final ra = roles[a]!;
      for (final entry in jaccardEdges(a)) {
        final b = entry.key;
        final rb = roles[b];
        if (rb == null) continue;
        final bucket = _classifyRolePair(ra, rb);
        if (bucket == null) continue;
        final score = entry.value;
        if (score <= 0) continue;
        sums[bucket] = (sums[bucket] ?? 0) + score;
        counts[bucket] = (counts[bucket] ?? 0) + 1;
      }
    }
  } else {
    for (var i = 0; i < paths.length; i++) {
      final a = paths[i];
      final ra = roles[a]!;
      for (var j = i + 1; j < paths.length; j++) {
        final b = paths[j];
        final rb = roles[b]!;
        final bucket = _classifyRolePair(ra, rb);
        if (bucket == null) continue;
        final score = jaccardScore(a, b);
        if (score <= 0) continue;
        sums[bucket] = (sums[bucket] ?? 0) + score;
        counts[bucket] = (counts[bucket] ?? 0) + 1;
      }
    }
  }

  double shrink(String key, double prior) {
    final n = counts[key] ?? 0;
    if (n == 0) return prior;
    final empirical = sums[key]! / n;
    return (prior * _kPriorWeight + empirical * n) / (_kPriorWeight + n);
  }

  return CouplingConstants(
    manifestLockfile: shrink('manifest_lockfile', _kPriorManifestLockfile),
    sourceGenerated: shrink('source_generated', _kPriorSourceGenerated),
    sourceMigration: shrink('source_migration', _kPriorSourceMigration),
    sourceTest: shrink('source_test', _kPriorSourceTest),
    fixture: shrink('fixture', _kPriorFixture),
    ciConfig: shrink('ci_config', _kPriorCiConfig),
    sourceDoc: shrink('source_doc', _kPriorSourceDoc),
  );
}

String? _classifyRolePair(TransportRoles a, TransportRoles b) {
  if ((a.isManifest && b.isLockfile) || (b.isManifest && a.isLockfile)) {
    if (a._sharesManifestRoot(b)) return 'manifest_lockfile';
  }
  // Concept-sharing gate: lanes for these role pairs only fire when both
  // paths share a transport concept, so the calibration must match.
  final sharesConcept = a._sharesTransportConcept(b);
  if (sharesConcept &&
      ((a.isSource && b.isTest) || (b.isSource && a.isTest))) {
    return 'source_test';
  }
  if (sharesConcept &&
      ((a.isSource && b.isGenerated) || (b.isSource && a.isGenerated))) {
    return 'source_generated';
  }
  if (sharesConcept &&
      ((a.isSource && b.isDoc) || (b.isSource && a.isDoc))) {
    return 'source_doc';
  }
  if (sharesConcept &&
      ((a.isSource && b.isMigration) || (b.isSource && a.isMigration))) {
    return 'source_migration';
  }
  if ((a.isFixture && b.isSource) || (b.isFixture && a.isSource)) {
    return 'fixture';
  }
  if ((a.isCiConfig && b.isSource) || (b.isCiConfig && a.isSource)) {
    return 'ci_config';
  }
  return null;
}

double _laneStrength(double tSrc, double tCand, double totalCoupling) =>
    totalCoupling * (0.5 + _kDirectionalBias * (tCand - tSrc));

/// Fast transport-lane lookup on pre-computed roles. Intended for hot
/// loops that make N×M lookups across two path sets — build one
/// [TransportRoles] per unique path once, reuse here. The returned
/// value is byte-identical to [logosTransportLane] called with the
/// same raw strings.
LogosTransportLane? logosTransportLaneOfRoles(
    TransportRoles src, TransportRoles cand,
    [CouplingConstants cc = CouplingConstants.prior]) {
  final sharesManifest = src._sharesManifestRoot(cand);
  if (sharesManifest && src.isManifest && cand.isLockfile) {
    return LogosTransportLane(
      label: 'manifest->lockfile',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.manifestLockfile),
      note: 'receive-heavy witness',
      sourceRole: 'manifest',
      targetRole: 'lockfile',
    );
  }
  if (sharesManifest && src.isLockfile && cand.isManifest) {
    return LogosTransportLane(
      label: 'lockfile->manifest',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.manifestLockfile),
      note: 'receive-heavy witness',
      sourceRole: 'lockfile',
      targetRole: 'manifest',
    );
  }
  final sharesConcept = src._sharesTransportConcept(cand);
  if (sharesConcept && src.isSource && cand.isGenerated) {
    return LogosTransportLane(
      label: 'source->generated',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.sourceGenerated),
      note: 'generated companion witness',
      sourceRole: 'source',
      targetRole: 'generated',
    );
  }
  if (sharesConcept && src.isGenerated && cand.isSource) {
    return LogosTransportLane(
      label: 'generated->source',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.sourceGenerated),
      note: 'source-of-truth witness',
      sourceRole: 'generated',
      targetRole: 'source',
    );
  }
  if (sharesConcept && !src.isTest && src.isSource && cand.isTest) {
    return LogosTransportLane(
      label: 'source->test',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.sourceTest),
      note: 'test witness',
      sourceRole: 'source',
      targetRole: 'test',
    );
  }
  if (sharesConcept && src.isTest && cand.isSource && !cand.isTest) {
    return LogosTransportLane(
      label: 'test->source',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.sourceTest),
      note: 'behavior/source witness',
      sourceRole: 'test',
      targetRole: 'source',
    );
  }
  if (sharesConcept && !src.isDoc && src.isSource && cand.isDoc) {
    return LogosTransportLane(
      label: 'source->doc',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.sourceDoc),
      note: 'documentation witness',
      sourceRole: 'source',
      targetRole: 'doc',
    );
  }
  if (sharesConcept && src.isDoc && cand.isSource && !cand.isDoc) {
    return LogosTransportLane(
      label: 'doc->source',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.sourceDoc),
      note: 'behavior/source witness',
      sourceRole: 'doc',
      targetRole: 'source',
    );
  }
  if (sharesConcept &&
      !src.isMigration &&
      src.isSource &&
      cand.isMigration) {
    return LogosTransportLane(
      label: 'source->migration',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.sourceMigration),
      note: 'migration witness',
      sourceRole: 'source',
      targetRole: 'migration',
    );
  }
  if (sharesConcept &&
      src.isMigration &&
      cand.isSource &&
      !cand.isMigration) {
    return LogosTransportLane(
      label: 'migration->source',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.sourceMigration),
      note: 'source-of-truth witness',
      sourceRole: 'migration',
      targetRole: 'source',
    );
  }
  if (src.isFixture && !cand.isFixture) {
    return LogosTransportLane(
      label: 'fixture->source',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.fixture),
      note: 'test witness',
      sourceRole: 'fixture',
      targetRole: 'source',
    );
  }
  if (!src.isFixture && cand.isFixture) {
    return LogosTransportLane(
      label: 'source->fixture',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.fixture),
      note: 'fixture witness',
      sourceRole: 'source',
      targetRole: 'fixture',
    );
  }
  if (src.isSource && cand.isCiConfig) {
    return LogosTransportLane(
      label: 'source->ci-config',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.ciConfig),
      note: 'CI configuration witness',
      sourceRole: 'source',
      targetRole: 'ci-config',
    );
  }
  if (src.isCiConfig && cand.isSource) {
    return LogosTransportLane(
      label: 'ci-config->source',
      strength: _laneStrength(
          _roleTransmissivity(src), _roleTransmissivity(cand),
          cc.ciConfig),
      note: 'CI-driven source witness',
      sourceRole: 'ci-config',
      targetRole: 'source',
    );
  }
  return null;
}

LogosTransportLane? logosTransportLane(String source, String candidate,
    [CouplingConstants cc = CouplingConstants.prior]) {
  final src = TransportRoles.of(source);
  final cand = TransportRoles.of(candidate);
  return logosTransportLaneOfRoles(src, cand, cc);
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
  final lower = path.replaceAll('\\', '/').toLowerCase();
  final roles = TransportRoles.of(path);
  final t = _roleTransmissivity(roles);
  if (t < 1.0) {
    if (roles.isGenerated) {
      reasons.add('generated');
    } else if (_looksVendor(lower)) {
      reasons.add('vendor');
    } else if (roles.isLockfile) {
      reasons.add('lockfile');
    } else if (roles.isFixture) {
      reasons.add('fixture-like');
    } else if (roles.isMigration) {
      reasons.add('migration');
    } else if (roles.isTest) {
      reasons.add('test');
    } else if (roles.isDoc) {
      reasons.add('doc');
    }
  }
  // Build-output and legacy paths don't have roles yet — detect inline.
  if (lower.contains('/deprecated/') || lower.contains('/legacy/')) {
    reasons.add('legacy');
    return math.min(t, 0.72);
  }
  if (lower.contains('/build/') ||
      lower.contains('/dist/') ||
      lower.contains('/coverage/') ||
      lower.contains('/.dart_tool/') ||
      lower.contains('/target/')) {
    reasons.add('build-output');
    return math.min(t, 0.20);
  }
  return t;
}
