// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// shake_plan.dart — deciding what to audit next, and proving what was missed.
//
// THE MISTAKE THIS FILE EXISTS TO AVOID
//
// The obvious way to sweep a repository is to walk its history: review every
// commit, and you have reviewed everything. That is false, and the way it is
// false is the whole point. A history sweep covers code that CHANGED. Code
// written once and never touched again is invisible to it — and that code is
// both the least examined and, for exactly that reason, a good place for bugs
// to have survived.
//
// So the coverage domain here is `git ls-tree` at a revision: the files that
// EXIST. Never the engine's file graph, which is built from the same
// `git log` walk and therefore carries the identical blind spot — plus a
// second one, since the stats walk drops changesets above a mass-edit
// threshold, and a repository's initial import is exactly such a changeset.
// Partitioning by the graph would have reproduced the hole it was meant to
// close, silently, while reporting full coverage.
//
// THE SHAPE
//
//   domain    every blob at the revision, minus a DECLARED exclusion set
//   partition spectral community where the engine has one, directory
//             locality where it does not
//   size      by measured bytes, against the admission budget — a physical
//             bound, not a chosen number
//   order     lexicographic, not a weighted sum: unexamined before examined,
//             then by churn accumulated since examination. A weighted sum of
//             incommensurable signals is a knob farm wearing a formula.
//   finish    a fixpoint across runs (see shake_ledger.dart), never a cap.
//             Whatever a run does not reach is REPORTED as pending, with its
//             position, rather than dropped.

import 'admitted_git.dart' show kDiffTextResidentExpansion;
import 'ai.dart' show kDiffBudgetChars;
import 'analysis_admission.dart';
import 'git.dart' show gitBlobSizesBatch, runGit;
import 'git_diff_paths.dart' show unCQuoteGitPath;
import 'git_result.dart';
import 'logos_git.dart';
import 'review_target.dart';
import 'shake_ledger.dart';

/// One file in the coverage domain.
class ShakeFile {
  final String path;
  final String blobOid;
  final int bytes;
  const ShakeFile({
    required this.path,
    required this.blobOid,
    required this.bytes,
  });
}

/// Why a file is not in the domain. Every exclusion is named and counted —
/// an audit that silently skips things reports a coverage it does not have.
enum ShakeExclusion {
  /// Machine-written: generated sources, lock files, vendored trees. Auditing
  /// them spends model calls on code no human will fix in place.
  generated,

  /// Not a source file this audit reads — documentation, data, images,
  /// fonts. Named `notSource` rather than `binary` because most of them are
  /// perfectly good text; they are simply not code, and an auditor handed a
  /// changelog has been misaimed.
  notSource,

  /// Larger on its own than the analysis budget can admit. Reported rather
  /// than silently dropped, because "too big to audit" is a fact about the
  /// repository worth knowing.
  tooLarge,
}

/// A unit of work: some files, audited together.
class ShakeRegion {
  final String label;
  final List<ShakeFile> files;

  /// True when no file in it has ever been examined at its current content.
  final bool unexamined;

  /// Churn accumulated by this region's files, summed. Only used to order
  /// regions relative to each other.
  final double staleChurn;

  /// Files here that no reviewed pull request ever covered.
  final int neverHumanReviewed;

  const ShakeRegion({
    required this.label,
    required this.files,
    required this.unexamined,
    required this.staleChurn,
    required this.neverHumanReviewed,
  });

  int get bytes => files.fold(0, (sum, f) => sum + f.bytes);

  RegionTarget toTarget({String revision = 'HEAD'}) => RegionTarget(
        paths: [for (final f in files) f.path],
        label: '$label (${files.length} '
            'file${files.length == 1 ? '' : 's'})',
        revision: revision,
      );
}

/// What a sweep would do, and what it deliberately would not.
class ShakePlan {
  /// Regions still needing examination, in the order they should be taken.
  final List<ShakeRegion> pending;

  /// Files already examined at their current content.
  final int freshFiles;

  /// Total files in the domain (excludes [excluded]).
  final int domainFiles;

  /// Named, counted exclusions.
  final Map<ShakeExclusion, List<String>> excluded;

  /// The directory every domain file sits under, stripped from region
  /// labels and stated once by the reporter.
  final String commonPrefix;

  /// Every path in the domain, examined or not. What the ledger prunes
  /// against — a record for a path not in here belongs to a file that has
  /// been deleted or renamed, and must stop claiming coverage.
  final Set<String> livePaths;

  const ShakePlan({
    required this.pending,
    required this.freshFiles,
    required this.domainFiles,
    required this.excluded,
    required this.livePaths,
    this.commonPrefix = '',
  });

  bool get isComplete => pending.isEmpty;

  int get pendingFiles =>
      pending.fold(0, (sum, r) => sum + r.files.length);
}

/// Paths that are machine-written rather than authored.
///
/// A repository-measured signal would be better and the engine has one —
/// `integrityByPath` scores how ritual a file reads — but it is derived from
/// history, so it says nothing about the never-touched files this sweep
/// exists to reach. These are structural markers instead: a `.g.dart` is
/// generated because its generator says so, not because of how it churned.
bool isGeneratedPath(String path) {
  final p = path.replaceAll('\\', '/').toLowerCase();
  if (p.endsWith('.g.dart') ||
      p.endsWith('.freezed.dart') ||
      p.endsWith('.pb.dart') ||
      p.endsWith('.mocks.dart') ||
      p.endsWith('.lock') ||
      p.endsWith('.min.js') ||
      p.endsWith('.map')) {
    return true;
  }
  // Leading slash so a TOP-LEVEL directory matches too: `build/out.dart` has
  // no slash before `build`, so a bare `/build/` marker would sail past the
  // most common case of all.
  final anchored = '/$p';
  for (final marker in const [
    '/generated/',
    '/gen/',
    '/vendor/',
    '/third_party/',
    '/node_modules/',
    '/build/',
    '/.dart_tool/',
  ]) {
    if (anchored.contains(marker)) return true;
  }
  return false;
}

/// Extensions worth auditing. A sweep that hands a model a PNG or a font has
/// misunderstood what it is for.
bool isAuditableSource(String path) {
  final p = path.toLowerCase();
  for (final ext in const [
    '.dart', '.ts', '.tsx', '.js', '.jsx', '.rs', '.go', '.py', '.java',
    '.kt', '.swift', '.c', '.h', '.cc', '.cpp', '.hpp', '.cs', '.rb',
    '.php', '.scala', '.sh', '.ps1', '.sql',
  ]) {
    if (p.endsWith(ext)) return true;
  }
  return false;
}

/// Largest region a single audit can carry.
///
/// TWO bounds, and the tighter one wins, because they are different limits:
///
///   * what can be READ — the analysis budget divided by the diff pipeline's
///     resident expansion. Exceed it and `admitGitPatchText` declines at the
///     door, and the region can never be examined at all.
///   * what can be SEEN — the review prompt's diff budget. Exceed it and the
///     hunk packer quietly drops whatever does not fit, so the model reads
///     part of the region while the ledger marks ALL of it examined. That is
///     worse than declining: the sweep would retire files the auditor never
///     read and report coverage it does not have.
///
/// Both are properties of machinery that already exists, measured rather than
/// picked. A first cut used only the first bound and planned 171-file
/// regions — comfortably inside memory, far past anything a model could
/// actually audit, and silently truncated.
int maxRegionBytes() {
  final readable =
      AnalysisAdmission.instance.totalBudget ~/ kDiffTextResidentExpansion;
  // Each rendered line costs its content plus a `+` and a newline, and each
  // file adds four header lines; the patch is therefore somewhat larger than
  // the bytes it covers. Sizing the SOURCE bytes against the prompt budget
  // leaves that headroom without inventing a factor.
  return readable < kDiffBudgetChars ? readable : kDiffBudgetChars;
}

/// Build the sweep plan for [repositoryPath] at [revision].
Future<GitResult<ShakePlan>> planShake({
  required String repositoryPath,
  required ShakeLedger ledger,
  LogosGit? engine,
  String revision = 'HEAD',
}) async {
  // THE DOMAIN: what exists, from the tree.
  final listed = await runGit(
      repositoryPath, ['ls-tree', '-r', '--full-name', revision]);
  if (listed.exitCode != 0) {
    return GitResult.err(
      'Could not list $revision: ${(listed.stderr as String).trim()}',
    );
  }

  final excluded = <ShakeExclusion, List<String>>{
    for (final e in ShakeExclusion.values) e: <String>[],
  };
  final candidates = <String, String>{}; // path -> oid
  for (final line in (listed.stdout as String).split('\n')) {
    final tab = line.indexOf('\t');
    if (tab < 0) continue;
    final meta = line.substring(0, tab).split(RegExp(r'\s+'));
    if (meta.length < 3 || meta[1] != 'blob') continue;
    final path = unCQuoteGitPath(line.substring(tab + 1).trim());
    if (path.isEmpty) continue;
    if (isGeneratedPath(path)) {
      excluded[ShakeExclusion.generated]!.add(path);
      continue;
    }
    if (!isAuditableSource(path)) {
      excluded[ShakeExclusion.notSource]!.add(path);
      continue;
    }
    candidates[path] = meta[2];
  }

  final sizes = await gitBlobSizesBatch(repositoryPath, candidates.values);
  if (sizes == null) {
    return const GitResult.err(
      'Could not size the repository\'s blobs, so no honest plan can be '
      'made. A plan built on a partial measurement would under-report what '
      'it cannot reach.',
    );
  }

  final budget = maxRegionBytes();
  final domain = <ShakeFile>[];
  for (final entry in candidates.entries) {
    final size = sizes[entry.value] ?? 0;
    if (size > budget) {
      excluded[ShakeExclusion.tooLarge]!.add(entry.key);
      continue;
    }
    domain.add(ShakeFile(
      path: entry.key,
      blobOid: entry.value,
      bytes: size,
    ));
  }

  // Only what has moved since it was examined.
  final stale = [
    for (final f in domain)
      if (!ledger.isFresh(f.path, f.blobOid)) f,
  ];
  final freshCount = domain.length - stale.length;

  final prefix = commonPrefixOf([for (final f in domain) f.path]);

  // THE PARTITION: spectral community where the engine has one, directory
  // locality where it does not — which is every never-touched file, the ones
  // this sweep exists to reach.
  final groups = <String, List<ShakeFile>>{};
  for (final f in stale) {
    (groups[_groupKeyFor(f.path, engine)] ??= <ShakeFile>[]).add(f);
  }

  final regions = <ShakeRegion>[];
  for (final entry in groups.entries) {
    final files = entry.value..sort((a, b) => a.path.compareTo(b.path));
    // Split to fit what a single audit can carry. Not a cap on coverage:
    // every part is still planned, just as separate units.
    var chunk = <ShakeFile>[];
    var chunkBytes = 0;
    void flush() {
      if (chunk.isEmpty) return;
      regions.add(_regionOf(
        label: _labelFor(chunk, stripPrefix: prefix),
        files: chunk,
        engine: engine,
        ledger: ledger,
      ));
      chunk = <ShakeFile>[];
      chunkBytes = 0;
    }

    for (final f in files) {
      if (chunk.isNotEmpty && chunkBytes + f.bytes > budget) flush();
      chunk.add(f);
      chunkBytes += f.bytes;
    }
    flush();
  }

  // A directory too big for one audit yields several regions that would
  // otherwise share a name. Number them ONLY when that happens, so the common
  // case stays clean and the ambiguous case stays unambiguous.
  final labelCounts = <String, int>{};
  for (final r in regions) {
    labelCounts[r.label] = (labelCounts[r.label] ?? 0) + 1;
  }
  final seenSoFar = <String, int>{};
  for (var i = 0; i < regions.length; i++) {
    final r = regions[i];
    if ((labelCounts[r.label] ?? 0) < 2) continue;
    final n = (seenSoFar[r.label] ?? 0) + 1;
    seenSoFar[r.label] = n;
    regions[i] = ShakeRegion(
      label: '${r.label} · $n of ${labelCounts[r.label]}',
      files: r.files,
      unexamined: r.unexamined,
      staleChurn: r.staleChurn,
      neverHumanReviewed: r.neverHumanReviewed,
    );
  }

  // THE ORDER, lexicographic. Never a weighted sum of incommensurable
  // signals — that is a pile of tuning constants pretending to be physics.
  //
  //  1. Regions nothing has ever examined come first. This is the only
  //     signal that measures absence of examination directly rather than
  //     standing in for it.
  //  2. Then by churn since: code that kept being rewritten while nobody
  //     checked it.
  //  3. Then by how much of it no human review ever covered.
  //  4. Then by path, so a plan is reproducible run to run.
  regions.sort((a, b) {
    if (a.unexamined != b.unexamined) return a.unexamined ? -1 : 1;
    final churn = b.staleChurn.compareTo(a.staleChurn);
    if (churn != 0) return churn;
    final unseen = b.neverHumanReviewed.compareTo(a.neverHumanReviewed);
    if (unseen != 0) return unseen;
    return a.label.compareTo(b.label);
  });

  return GitResult.ok(ShakePlan(
    pending: regions,
    freshFiles: freshCount,
    domainFiles: domain.length,
    excluded: excluded,
    livePaths: {for (final f in domain) f.path},
    commonPrefix: prefix,
  ));
}

ShakeRegion _regionOf({
  required String label,
  required List<ShakeFile> files,
  required LogosGit? engine,
  required ShakeLedger ledger,
}) {
  final stats = engine?.stats;
  var churn = 0.0;
  var unseen = 0;
  var everExamined = false;
  for (final f in files) {
    churn += stats?.volatility[f.path] ?? 0.0;
    final reviewers = stats?.reviewersByPath[f.path];
    if (reviewers == null || reviewers.isEmpty) unseen++;
    if (ledger.recordFor(f.path) != null) everExamined = true;
  }
  return ShakeRegion(
    label: label,
    files: List.unmodifiable(files),
    unexamined: !everExamined,
    staleChurn: churn,
    neverHumanReviewed: unseen,
  );
}

/// Name a region after WHAT IS IN IT.
///
/// The grouping key is a spectral cluster number, and `cluster 2 · part 1`
/// tells a reader nothing they can act on — not which code is being audited,
/// not whether they care, not where to look when a finding lands. The files
/// themselves already say it: their deepest shared directory is the name a
/// person would have given the group anyway.
///
/// Falls back to naming the span when a cluster is genuinely scattered, which
/// is honest — a spectral community CAN group code that lives apart, and
/// pretending otherwise would be a prettier lie.
String _labelFor(List<ShakeFile> files, {String stripPrefix = ''}) {
  if (files.isEmpty) return '(empty)';

  String relative(String path) {
    final norm = path.replaceAll('\\', '/');
    if (stripPrefix.isEmpty || !norm.startsWith('$stripPrefix/')) return norm;
    return norm.substring(stripPrefix.length + 1);
  }

  if (files.length == 1) return relative(files.first.path);

  List<String> dirOf(String path) {
    final parts = relative(path).split('/');
    return parts.length <= 1 ? const [] : parts.sublist(0, parts.length - 1);
  }

  var shared = dirOf(files.first.path);
  final distinctDirs = <String>{shared.join('/')};
  for (final f in files.skip(1)) {
    final d = dirOf(f.path);
    distinctDirs.add(d.join('/'));
    var i = 0;
    while (i < shared.length && i < d.length && shared[i] == d[i]) {
      i++;
    }
    shared = shared.sublist(0, i);
  }

  final prefix = shared.isEmpty ? '.' : shared.join('/');
  if (distinctDirs.length == 1) return prefix;
  return '$prefix · ${distinctDirs.length} dirs';
}

/// The directory every file in the domain sits under.
///
/// In a monorepo this is something like `apps/desktop-flutter`, and repeating
/// it on all sixty-eight region names carries exactly zero information while
/// pushing the part that matters off to the right. Stated once by the caller,
/// stripped from every label.
String commonPrefixOf(Iterable<String> paths) {
  List<String>? shared;
  for (final p in paths) {
    final parts = p.replaceAll('\\', '/').split('/');
    final dir = parts.length <= 1 ? <String>[] : parts.sublist(0, parts.length - 1);
    if (shared == null) {
      shared = dir;
      continue;
    }
    var i = 0;
    while (i < shared.length && i < dir.length && shared[i] == dir[i]) {
      i++;
    }
    shared = shared.sublist(0, i);
    if (shared.isEmpty) break;
  }
  return (shared ?? const <String>[]).join('/');
}

/// Which region a file belongs to.
///
/// The engine's spectral community when it has an opinion — those are
/// minimum-coupling groupings, so a region tends to be code that genuinely
/// belongs together. Directory otherwise, which is the author's own statement
/// about what belongs together and the only thing available for a file the
/// history never saw.
String _groupKeyFor(String path, LogosGit? engine) {
  final community = engine?.communityOf(path);
  if (community != null) return 'cluster $community';
  final norm = path.replaceAll('\\', '/');
  final slash = norm.lastIndexOf('/');
  return slash <= 0 ? '(root)' : norm.substring(0, slash);
}
