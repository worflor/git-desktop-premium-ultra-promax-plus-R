// Hostile-gitconfig differential suite.
//
// Production NEVER neutralizes the user's git config (no `GIT_CONFIG_*` env,
// no `-c` overrides, no format-pinning beyond what each call already passes —
// verified against lib/backend/git.dart). A user's `~/.gitconfig` or a repo's
// `.git/config` can therefore silently reshape `git` stdout and break the
// app's line-oriented parsers. This suite proves output-invariance under
// hostile config across every affected surface — or pins each divergence as a
// genuine finding via a skip-marked, root-cause-documented cell.
//
// Three techniques:
//   A. BEHAVIORAL DIFFERENTIAL (the core). One seeded repo; for each surface
//      × config-axis, run the SAME production function with a baseline config
//      and with a hostile config, then deep-compare the parsed output. One
//      repo config-swapped (not two repos) because two repos commit at
//      different times ⇒ different SHAs ⇒ false divergence on every
//      hash-bearing surface (see test/support/hostile_config.dart header).
//   B. ARGV-PINNING LINT (deterministic, real subprocesses via the GitSpawn
//      recorder). Drive each function, record every git argv, and lint for the
//      missing `--no-color` / `--no-ext-diff` / `--no-show-signature` that lets
//      config reshape output in the first place. These laws make the whole
//      bug class unrepresentable once the flags are added.
//   C. SYNTHETIC HOSTILE-OUTPUT INJECTION. For axes unproducible portably
//      (gpg signatures, non-UTF-8 encodings) feed byte-exact synthetic stdout
//      to the REAL production parse path.
//
// LAWS
//   A1 getRepositoryStatus  — status file lists invariant under every axis.
//   A2 diff-content parse   — getFileDiff→parseUnifiedDiff hunks/paths invariant.
//   A3 history + bulk       — listCommitHistory + bulkGetCommitDetails invariant.
//   A4 file coupling        — computeFileCoupling path/edge set invariant.
//   A5 stash file stats     — stashFiles path/churn invariant.
//   A6 safe controls        — getFileBlame/listBranches/listReflog invariant
//                             under ALL axes (proves the harness itself works).
//   B  argv pinning         — color/ext-diff/signature flags present where the
//                             stdout feeds a line-prefix-sensitive parser.
//   C  parser robustness    — real parser survives signature-line injection
//                             and non-UTF-8 fields (graceful degrade).
//
// Every cell is now ARMED: the findings this suite once pinned (G1..G10 +
// reflog/search %09→%x09) were fixed at root 2026-07-10 (dossier docs/
// architecture/test-hardening-crash-chaos-config.md). A future regression is
// caught by the armed assertion itself; a genuinely new divergence would be
// skip-marked with its root cause rather than papered over. Never modifies lib/.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/features/diff/diff_models.dart';

import '../support/git_faults.dart';
import '../support/hostile_config.dart';
import '../support/scratch_repo.dart';

late ScratchRepo _repo;
late HostileConfigFixture _fixture;
late String _gitVersion;

// ---------------------------------------------------------------------------
// Projections — JSON-encodable views capturing the SEMANTIC content the UI
// relies on. `shortHash` (%h) is excluded everywhere: it is explicitly
// controlled by core.abbrev and purely cosmetic, so folding it in would flag
// the harmless `abbrev` control as a false divergence. Diff meta lines
// (index/---/+++) are excluded for the same reason (they carry blob SHAs the
// abbrev axis perturbs; filePath is already propagated onto body+hunk lines).
// ---------------------------------------------------------------------------

Future<Object?> _statusProjection(ScratchRepo repo) async {
  final r = await getRepositoryStatus(repo.dir.path);
  expect(r.ok, isTrue, reason: 'status failed: ${r.error}');
  final s = r.data!;
  final files = s.files.map((f) => [f.path, f.staged, f.unstaged]).toList()
    ..sort((a, b) => a[0].compareTo(b[0]));
  return {
    'branch': s.branch,
    'upstream': s.upstream,
    'ahead': s.ahead,
    'behind': s.behind,
    'hasHeadCommit': s.hasHeadCommit,
    'files': files,
  };
}

Future<Object?> _diffProjection(ScratchRepo repo) async {
  final out = <Object?>[];
  for (final path in [nonAsciiFileName, spaceFileName]) {
    final r = await getFileDiff(repo.dir.path, path);
    expect(r.ok, isTrue, reason: 'diff failed for $path: ${r.error}');
    for (final line in parseUnifiedDiff(r.data ?? '')) {
      if (line.kind == LineKind.meta) continue;
      out.add([line.kind.name, line.filePath, line.text]);
    }
  }
  return out;
}

Future<Object?> _historyProjection(ScratchRepo repo) async {
  final hist = await listCommitHistory(repo.dir.path, limit: 50);
  expect(hist.ok, isTrue, reason: 'listCommitHistory failed: ${hist.error}');
  final commits = hist.data ?? const <CommitHistoryEntry>[];
  final meta = commits
      .map((c) => [
            c.commitHash,
            c.parentHashes,
            c.refNames,
            c.subject,
            c.authorName,
            c.authorEmail,
            c.authoredAt,
            c.isMerge,
          ])
      .toList();

  final bulk = await bulkGetCommitDetails(repo.dir.path, commits, limit: 50);
  expect(bulk.ok, isTrue, reason: 'bulkGetCommitDetails failed: ${bulk.error}');
  final byHash = bulk.data ?? const <String, CommitDetailData>{};
  final details = <Object?>[];
  for (final hash in byHash.keys.toList()..sort()) {
    final d = byHash[hash]!;
    final files = d.files
        .map((f) => [f.path, f.additions, f.deletions, f.changeType])
        .toList()
      ..sort((a, b) => (a[0] as String).compareTo(b[0] as String));
    details.add([hash, d.filesChanged, d.additions, d.deletions, files]);
  }
  return {'meta': meta, 'bulk': details};
}

Future<Object?> _couplingProjection(ScratchRepo repo) async {
  // halfLifeCommits: 0 pins pure count-based Jaccard (no AR(2) derivation), so
  // the matrix is a deterministic function of the (identical) history.
  final r = await computeFileCoupling(repo.dir.path, halfLifeCommits: 0);
  expect(r.ok, isTrue, reason: 'computeFileCoupling failed: ${r.error}');
  final m = r.data!;
  final paths = List<String>.of(m.paths)..sort();
  final edges = <Object?>[];
  final jac = m.jaccard;
  for (final a in jac.keys.toList()..sort()) {
    final inner = jac[a]!;
    for (final b in inner.keys.toList()..sort()) {
      edges.add([a, b, inner[b]!.toStringAsFixed(6)]);
    }
  }
  return {'paths': paths, 'edges': edges};
}

Future<Object?> _stashProjection(ScratchRepo repo) async {
  final r = await stashFiles(repo.dir.path);
  expect(r.ok, isTrue, reason: 'stashFiles failed: ${r.error}');
  return (r.data ?? const <StashFileStat>[])
      .map((s) => [s.path, s.adds, s.dels, s.binary])
      .toList()
    ..sort((a, b) => (a[0] as String).compareTo(b[0] as String));
}

Future<Object?> _blameProjection(ScratchRepo repo) async {
  final r = await getFileBlame(repo.dir.path, 'blamefile.txt');
  expect(r.ok, isTrue, reason: 'getFileBlame failed: ${r.error}');
  return (r.data ?? const <BlameLineData>[])
      .map((b) =>
          [b.lineNumber, b.commitHash, b.authorName, b.authoredAt, b.lineContent])
      .toList();
}

Future<Object?> _branchesProjection(ScratchRepo repo) async {
  final r = await listBranches(repo.dir.path);
  expect(r.ok, isTrue, reason: 'listBranches failed: ${r.error}');
  return (r.data ?? const <BranchInfo>[])
      .map((b) => [
            b.name,
            b.current,
            b.upstream,
            b.ahead,
            b.behind,
            b.gone,
            b.lastCommitAt?.toIso8601String(),
          ])
      .toList()
    ..sort((a, b) => '${a[0]}'.compareTo('${b[0]}'));
}

Future<Object?> _reflogProjection(ScratchRepo repo) async {
  final r = await listReflog(repo.dir.path, limit: 50);
  expect(r.ok, isTrue, reason: 'listReflog failed: ${r.error}');
  return (r.data ?? const <ReflogEntryData>[])
      .map((e) =>
          [e.commitHash, e.refSelector, e.actionSummary, e.authorName, e.authoredAt])
      .toList();
}

/// Emits one armed-or-skip-pinned differential cell per axis for [surface].
/// [findings] maps an axis name to its root-cause string; a present entry
/// skip-pins that cell as a genuine finding, an absent one leaves it armed.
void _differentialGroup(
  String surface,
  Future<Object?> Function(ScratchRepo repo) probe, {
  Map<String, String> findings = const {},
}) {
  for (final axis in hostileConfigAxes) {
    final finding = findings[axis.name];
    test('$surface × ${axis.name}', () async {
      await _fixture.applyArm(baselineArm());
      final baseline = await probe(_repo);
      await _fixture.applyArm(hostileArm(axis));
      final hostile = await probe(_repo);
      expect(
        canonicalJson(hostile),
        canonicalJson(baseline),
        reason: 'OUTPUT-INVARIANCE VIOLATED: $surface changed under '
            'hostile config axis "${axis.name}" (${axis.settings}).\n'
            'baseline: ${canonicalJson(baseline)}\n'
            'hostile:  ${canonicalJson(hostile)}',
      );
    }, skip: finding);
  }
}

// ---------------------------------------------------------------------------
// Technique B — argv lint helpers (inspect recorded argv; no line numbers).
// ---------------------------------------------------------------------------

/// Records the argv of every git subprocess spawned while [body] runs,
/// delegating each to the REAL git binary. Reuses GitFaultScript's recorder
/// (a never-matching predicate ⇒ every call is delegated AND recorded).
Future<List<List<String>>> _recordArgv(Future<void> Function() body) async {
  final script =
      GitFaultScript.failWhile((_) => false, times: 0, result: gitOk);
  await withGitFaults(script, body);
  return script.invocations.map((i) => i.args).toList();
}

String _sub(List<String> args) =>
    args.firstWhere((a) => !a.startsWith('-'), orElse: () => '');

/// A `diff` invocation whose stdout is a unified-diff BODY fed to
/// parseUnifiedDiff (has `-U<n>`, is not the numstat size probe).
bool _isDiffContent(List<String> args) =>
    _sub(args) == 'diff' &&
    args.any((a) => a.startsWith('-U')) &&
    !args.contains('--numstat');

/// A `log` invocation carrying the commit-log format fed to
/// `_parseCommitLogLines` (its fixed-8-line record shape).
bool _isCommitLogFormat(List<String> args) =>
    _sub(args) == 'log' && args.any((a) => a.startsWith('--format=%H'));

bool _hasNoColor(List<String> args) => args.contains('--no-color');
bool _hasNoExtDiff(List<String> args) => args.contains('--no-ext-diff');
bool _hasNoShowSignature(List<String> args) =>
    args.contains('--no-show-signature');

/// True when config-driven ANSI can never reach the parser: an explicit
/// `--no-color`, or a machine format (`--porcelain`, `-z`, `--format=`) git
/// does not colorize.
bool _isColorImmune(List<String> args) =>
    _hasNoColor(args) ||
    args.contains('-z') ||
    args.any((a) => a.startsWith('--porcelain')) ||
    args.any((a) => a.startsWith('--format='));

// ---------------------------------------------------------------------------
// Technique C — run the real parse path against synthetic stdout.
// ---------------------------------------------------------------------------

Future<List<CommitHistoryEntry>> _historyFromStdout(
    String repoPath, List<int> stdoutBytes) async {
  late final List<CommitHistoryEntry> entries;
  await withGitFaults(
    GitFaultScript.always((_) => rawStdoutResult(stdoutBytes)),
    () async {
      final r = await listCommitHistory(repoPath, limit: 50);
      entries = r.data ?? const <CommitHistoryEntry>[];
    },
  );
  return entries;
}

// ---------------------------------------------------------------------------
// Regression breadcrumbs — every finding this suite once pinned is now FIXED
// at root (2026-07-10, dossier docs/architecture/test-hardening-crash-chaos-
// config.md), so every differential cell, anchor, argv-lint, and parser law
// below is ARMED. What was fixed:
//   G1 (status) / G4 (history) / G5 (coupling): the C-quoted porcelain/raw
//     path is now un-C-quoted (unCQuoteGitPath), so a non-ASCII filename no
//     longer arrives as `"caf\303\251.txt"` / a phantom coupling node.
//   G2 (diff mnemonicPrefix) / G3,G7,G8 (diff color/ext-diff): the diff family
//     pins `--no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/`
//     (_kDiffContentPins, git.dart:359), making the reshape class
//     unrepresentable.
//   G6 (stash renames): stashFiles pins `--no-renames`, so a renamed entry
//     splits into clean delete+add rows instead of an `{old => new}` arrow.
//   G9,G10 (commit-log signature): the log family pins `--no-show-signature`,
//     AND _parseCommitLogLines screens record-start `gpg:` lines so an
//     interleaved signature can never shift the fixed-8-line window.
//   reflog + search %09→%x09: listReflog and searchCommits build their pretty
//     formats with `%x09` (a real TAB), so reflog no longer always returns [].
// The consts are gone; a regression is caught by the armed assertion itself.
// ---------------------------------------------------------------------------
// Ground-truth anchors — absolute parsed-content assertions.
//
// The differential proves the baseline and hostile arms AGREE; it is blind to
// a bug that corrupts BOTH arms identically (e.g. a parser that drops a real
// file in every config). These anchors close that hole: each pins the LITERAL
// content the seed guarantees. Run under two arms:
//   • BASELINE (cleanBaselineConfig) — every anchor armed; pins correctness.
//   • GIT-DEFAULT (gitDefaultConfig) — a second witness under git's OWN
//     defaults. Where a default is the hostile direction (quotePath=true,
//     renames=true) the SAME finding the differential pins recurs as an
//     absolute failure, so the anchor is skip-pinned under that finding's
//     const — one finding, two witnesses. Where the default is harmless (diff
//     un-C-quotes; blame/branches/reflog are axis-immune) the anchor stays
//     armed under BOTH arms.
//
// Bodies are shared functions so the two arms assert byte-identical
// expectations; only the `skip` differs. Each reads the seed defined in
// test/support/hostile_config.dart (seedHostileRepo).
// ---------------------------------------------------------------------------

Future<void> _anchorStatus() async {
  final r = await getRepositoryStatus(_repo.dir.path);
  expect(r.ok, isTrue, reason: 'status failed: ${r.error}');
  final s = r.data!;
  expect(s.branch, 'main');
  expect(s.hasHeadCommit, isTrue);
  expect(s.upstream, isNull);
  expect(s.ahead, 0);
  expect(s.behind, 0);
  final byPath = {
    for (final f in s.files) f.path: [f.staged, f.unstaged]
  };
  expect(byPath, {
    'a.txt': ['M', ''], // staged modify
    nonAsciiFileName: ['', 'M'], // café.txt — unstaged modify, REAL name
    spaceFileName: ['', 'M'], // has space.txt — unstaged modify
    'untracked.txt': ['', '?'],
  });
  // The non-ASCII path arrives decoded, never as the C-quoted octal literal.
  expect(byPath.keys.any((k) => k.contains('\\303')), isFalse,
      reason: 'a C-quoted path leaked into the status file list: '
          '${byPath.keys.toList()}');
}

Future<void> _anchorDiff() async {
  // café.txt: committed `x\nY\nz\n`, working tree `x\nY\nZZ\n`.
  final rCafe = await getFileDiff(_repo.dir.path, nonAsciiFileName);
  expect(rCafe.ok, isTrue, reason: 'café diff failed: ${rCafe.error}');
  final cafe = parseUnifiedDiff(rCafe.data ?? '');
  expect(
    cafe.where((l) => l.kind == LineKind.added).map((l) => l.text).toList(),
    ['+ZZ'],
  );
  expect(
    cafe.where((l) => l.kind == LineKind.deleted).map((l) => l.text).toList(),
    ['-z'],
  );
  expect(
    cafe
        .where((l) => l.kind != LineKind.meta)
        .every((l) => l.filePath == nonAsciiFileName),
    isTrue,
    reason: 'café diff filePath not the real name: '
        '${cafe.map((l) => l.filePath).toSet()}',
  );

  // has space.txt: committed `p\nq\nr\n`, working tree `p\nQ\nr\n`.
  final rSpace = await getFileDiff(_repo.dir.path, spaceFileName);
  expect(rSpace.ok, isTrue, reason: 'space diff failed: ${rSpace.error}');
  final space = parseUnifiedDiff(rSpace.data ?? '');
  expect(
    space.where((l) => l.kind == LineKind.added).map((l) => l.text).toList(),
    ['+Q'],
  );
  expect(
    space.where((l) => l.kind == LineKind.deleted).map((l) => l.text).toList(),
    ['-q'],
  );
  expect(
    space
        .where((l) => l.kind != LineKind.meta)
        .every((l) => l.filePath == spaceFileName),
    isTrue,
    reason: 'space diff filePath not the real name: '
        '${space.map((l) => l.filePath).toSet()}',
  );
}

Future<void> _anchorHistory() async {
  final hist = await listCommitHistory(_repo.dir.path, limit: 50);
  expect(hist.ok, isTrue, reason: 'history failed: ${hist.error}');
  final commits = hist.data!;
  expect(commits.map((c) => c.subject).toList(), ['seed two', 'seed one', 'root']);
  expect(commits.every((c) => c.authorName == 'Scratch Repo'), isTrue);
  expect(
      commits.every((c) => c.authorEmail == 'scratch@example.invalid'), isTrue);
  expect(commits.first.refNames, contains('HEAD -> main'));

  final bulk = await bulkGetCommitDetails(_repo.dir.path, commits, limit: 50);
  expect(bulk.ok, isTrue, reason: 'bulk failed: ${bulk.error}');
  final bySubject = {
    for (final c in commits) c.subject: bulk.data![c.commitHash]!
  };
  final seedTwo = {
    for (final f in bySubject['seed two']!.files)
      f.path: [f.changeType, f.additions, f.deletions]
  };
  expect(seedTwo, {
    'a.txt': ['M', 1, 1],
    nonAsciiFileName: ['M', 1, 1], // café.txt co-changed with a.txt
  });
  final seedOne = {
    for (final f in bySubject['seed one']!.files)
      f.path: [f.changeType, f.additions, f.deletions]
  };
  expect(seedOne, {
    'a.txt': ['A', 3, 0],
    'blamefile.txt': ['A', 3, 0],
    nonAsciiFileName: ['A', 3, 0], // café.txt as a REAL name in the file list
    spaceFileName: ['A', 3, 0],
    'stashme.txt': ['A', 4, 0],
  });
}

Future<void> _anchorCoupling() async {
  // halfLifeCommits: 0 → pure count-based Jaccard (deterministic on history).
  final r = await computeFileCoupling(_repo.dir.path, halfLifeCommits: 0);
  expect(r.ok, isTrue, reason: 'coupling failed: ${r.error}');
  final paths = List<String>.of(r.data!.paths)..sort();
  expect(paths, [
    'a.txt',
    'blamefile.txt',
    nonAsciiFileName, // café.txt — a real node, NOT `"caf/303/251.txt"`
    spaceFileName,
    'stashme.txt',
  ]..sort());
  // No phantom node from an un-decoded C-quoted raw path.
  expect(paths.any((pth) => pth.contains('303') || pth.contains('\\')), isFalse,
      reason: 'phantom coupling node from a C-quoted path: $paths');
}

Future<void> _anchorStash() async {
  final r = await stashFiles(_repo.dir.path);
  expect(r.ok, isTrue, reason: 'stash failed: ${r.error}');
  final byPath = {
    for (final s in r.data!) s.path: [s.adds, s.dels, s.binary]
  };
  // Under pinned no-renames the rename+edit shows as a delete of the old path
  // and an add of the new — two clean rows, no `{old => new}` arrow smuggled
  // in as a single bogus path.
  expect(byPath, {
    'stashme.txt': [0, 4, false],
    'stashme_renamed.txt': [4, 0, false],
  });
}

Future<void> _anchorBlame() async {
  final r = await getFileBlame(_repo.dir.path, 'blamefile.txt');
  expect(r.ok, isTrue, reason: 'blame failed: ${r.error}');
  final lines = r.data!;
  expect(lines.map((b) => [b.lineNumber, b.lineContent]).toList(), [
    [1, 'alpha'],
    [2, 'beta'],
    [3, 'gamma'],
  ]);
  expect(lines.every((b) => b.authorName == 'Scratch Repo'), isTrue);
}

Future<void> _anchorBranches() async {
  final r = await listBranches(_repo.dir.path);
  expect(r.ok, isTrue, reason: 'branches failed: ${r.error}');
  final branches = r.data!;
  expect(branches.map((b) => b.name).toList(), ['main']);
  expect(branches.single.current, isTrue);
  expect(branches.single.upstream, isNull);
}

Future<void> _anchorReflog() async {
  final head = await _repo.head();
  final r = await listReflog(_repo.dir.path, limit: 50);
  expect(r.ok, isTrue, reason: 'reflog failed: ${r.error}');
  final entries = r.data!;
  expect(entries, isNotEmpty);
  // Newest reflog entry resolves to the current HEAD commit.
  expect(entries.first.commitHash, head);
  expect(entries.every((e) => e.authorName == 'Scratch Repo'), isTrue);
  expect(entries.any((e) => e.actionSummary.contains('seed two')), isTrue,
      reason: 'no reflog entry recorded the "seed two" commit');
}

Future<void> _anchorSearch() async {
  // searchCommits builds its pretty format with `%x09` (a real TAB) — the same
  // class the reflog anchor pins. A subject-word search must find the seeded
  // commits and split their fields correctly.
  final r = await searchCommits(_repo.dir.path, 'seed');
  expect(r.ok, isTrue, reason: 'searchCommits failed: ${r.error}');
  final results = r.data!;
  expect(results, isNotEmpty,
      reason: 'searchCommits returned nothing for a seeded subject word — the '
          'pretty-format %x09 field split has regressed to %09');
  expect(results.map((c) => c.subject).toSet(),
      containsAll(<String>['seed one', 'seed two']),
      reason: 'searchCommits must return correctly-parsed subjects');
  expect(results.every((c) => c.authorName == 'Scratch Repo'), isTrue,
      reason: 'author field mis-split (tab separator wrong)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _repo = await ScratchRepo.create(name: 'hostile_cfg');
    await seedHostileRepo(_repo);
    _fixture = await HostileConfigFixture.create(_repo);
    final v = await _repo.git(['--version']);
    _gitVersion = v.stdout.toString().trim();
  });

  tearDownAll(() async {
    await _repo.dispose();
  });

  group('environment', () {
    test('git version is recorded (behavior notes are version-relevant)', () {
      // Not a gate: the axes are pure-gitconfig and portable, but the exact
      // C-quote / prefix shapes were validated against git 2.52. A wildly
      // older git could shift a sample; the differential still holds because
      // both arms run the same binary.
      expect(_gitVersion, contains('git version'),
          reason: 'could not resolve git --version: "$_gitVersion"');
    });
  });

  // -------------------------------------------------------- ground-truth
  // Absolute parsed-content anchors under the clean baseline: every surface
  // armed, pinning the LITERAL seed content. Catches a shared-mode bug the
  // differential (arm-vs-arm) cannot see.
  group('anchors — BASELINE arm (absolute correctness)', () {
    setUp(() => _fixture.applyArm(baselineArm()));
    test('status file list + café.txt markers', _anchorStatus);
    test('diff real filePath + exact +/- texts', _anchorDiff);
    test('history subjects/authors + bulk file lists', _anchorHistory);
    test('coupling node set (no phantoms)', _anchorCoupling);
    test('stash rename split (no-renames)', _anchorStash);
    test('blame line contents + author', _anchorBlame);
    test('branches — main is sole current', _anchorBranches);
    // Was finding: listReflog always returned [] (the %09-vs-%x09 pretty-format
    // bug the differential's reflog control — empty==empty — couldn't see).
    // Fixed 2026-07-10 (git.dart:4068 uses %x09); now armed.
    test('reflog newest == HEAD', _anchorReflog);
    // Pins the same fixed %x09 class for searchCommits (reflog AND search).
    test('searchCommits finds a seeded subject', _anchorSearch);
  });

  // The SAME anchors under git's OWN defaults. quotePath=true and renames=true
  // are the hostile direction by default, so status/history/coupling/stash are
  // a SECOND witness that the un-C-quote + --no-renames fixes hold even under
  // git's real defaults (they once reproduced findings G1/G4/G5/G6 here as
  // absolute failures). diff survives (parseUnifiedDiff un-C-quotes), and
  // blame/branches/reflog are axis-immune — all armed.
  group('anchors — GIT-DEFAULT arm (git real defaults; second witness)', () {
    setUp(() => _fixture.applyArm(gitDefaultArm()));
    test('status file list + café.txt markers', _anchorStatus);
    test('diff real filePath + exact +/- texts', _anchorDiff);
    test('history subjects/authors + bulk file lists', _anchorHistory);
    test('coupling node set (no phantoms)', _anchorCoupling);
    test('stash rename split (no-renames)', _anchorStash);
    test('blame line contents + author', _anchorBlame);
    test('branches — main is sole current', _anchorBranches);
    test('reflog newest == HEAD', _anchorReflog);
  });

  // ------------------------------------------------------------------ A1..A5
  group('law A1 — getRepositoryStatus output-invariance', () {
    // quotePath was finding G1; fixed 2026-07-10 (un-C-quoted path). Armed.
    _differentialGroup('status', _statusProjection);
  });

  group('law A2 — diff-content parse output-invariance', () {
    // ALL axes armed. diff.noprefix always self-repaired (the `+++` line runs
    // through patchSidePath, recovering the unprefixed path before any body
    // line is emitted). mnemonicPrefix was finding G2 and color.diff was
    // finding G3/G7/G8 — both fixed 2026-07-10 by pinning
    // `--no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/`
    // (_kDiffContentPins), so the mnemonic prefix and ANSI escapes can no
    // longer reach the parser.
    _differentialGroup('diff', _diffProjection);
  });

  group('law A3 — commit history + bulk details invariance', () {
    // quotePath was finding G4; fixed 2026-07-10 (un-C-quoted raw path). Armed.
    _differentialGroup('history', _historyProjection);
  });

  group('law A4 — file coupling invariance', () {
    // quotePath was finding G5 (phantom `caf/303/251.txt` node); fixed
    // 2026-07-10 (un-C-quote before backslash-normalize). Armed.
    _differentialGroup('coupling', _couplingProjection);
  });

  group('law A5 — stash file stats invariance', () {
    // renames was finding G6; fixed 2026-07-10 (stashFiles pins --no-renames).
    _differentialGroup('stash', _stashProjection);
  });

  // --------------------------------------------------------------------- A6
  group('law A6 — safe controls (armed under EVERY axis; harness validity)',
      () {
    _differentialGroup('blame', _blameProjection);
    _differentialGroup('branches', _branchesProjection);
    _differentialGroup('reflog', _reflogProjection);
  });

  // ---------------------------------------------------------------------- B
  group('law B — argv-pinning lint', () {
    // Controls: these carry a color-immune format, so config-driven ANSI can
    // never reach their parser. ARMED — must pass.
    test('argv-color: getFileBlame is color-immune (--porcelain)', () async {
      await _fixture.restoreBase();
      final argv = await _recordArgv(
          () => getFileBlame(_repo.dir.path, 'blamefile.txt'));
      final blame = argv.where((a) => _sub(a) == 'blame').toList();
      expect(blame, isNotEmpty, reason: 'no blame invocation recorded: $argv');
      for (final a in blame) {
        expect(_isColorImmune(a), isTrue,
            reason: 'blame invocation not color-immune: $a');
      }
    });

    test('argv-color: listBranches is color-immune (--format)', () async {
      await _fixture.restoreBase();
      final argv = await _recordArgv(() => listBranches(_repo.dir.path));
      final branch = argv.where((a) => _sub(a) == 'branch').toList();
      expect(branch, isNotEmpty, reason: 'no branch invocation: $argv');
      for (final a in branch) {
        expect(_isColorImmune(a), isTrue,
            reason: 'branch invocation not color-immune: $a');
      }
    });

    // These pins make the whole reshape class unrepresentable. Were findings
    // G7 (--no-color), G8 (--no-ext-diff), G9 (--no-show-signature); all pinned
    // in lib 2026-07-10, so the lint now passes — a future unpinned invocation
    // fails it.
    test('argv-color: content diff carries --no-color', () async {
      await _fixture.restoreBase();
      final argv =
          await _recordArgv(() => getFileDiff(_repo.dir.path, nonAsciiFileName));
      final content = argv.where(_isDiffContent).toList();
      expect(content, isNotEmpty, reason: 'no content-diff invocation: $argv');
      for (final a in content) {
        expect(_hasNoColor(a), isTrue,
            reason: 'content diff lacks --no-color: $a');
      }
    });

    test('argv-extdiff: content diff carries --no-ext-diff', () async {
      await _fixture.restoreBase();
      final argv =
          await _recordArgv(() => getFileDiff(_repo.dir.path, nonAsciiFileName));
      final content = argv.where(_isDiffContent).toList();
      expect(content, isNotEmpty, reason: 'no content-diff invocation: $argv');
      for (final a in content) {
        expect(_hasNoExtDiff(a), isTrue,
            reason: 'content diff lacks --no-ext-diff: $a');
      }
    });

    test('argv-signature: commit log carries --no-show-signature', () async {
      await _fixture.restoreBase();
      final argv =
          await _recordArgv(() => listCommitHistory(_repo.dir.path, limit: 5));
      final logs = argv.where(_isCommitLogFormat).toList();
      expect(logs, isNotEmpty, reason: 'no commit-log invocation: $argv');
      for (final a in logs) {
        expect(_hasNoShowSignature(a), isTrue,
            reason: 'commit log lacks --no-show-signature: $a');
      }
    });
  });

  // ---------------------------------------------------------------------- C
  group('law C — synthetic hostile-output injection', () {
    final commits = <SyntheticCommit>[
      const SyntheticCommit(
        hash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        shortHash: 'aaaaaaa',
        refs: 'HEAD -> main',
        subject: 'second commit',
        authorName: 'Ada Lovelace',
        authorEmail: 'ada@example.invalid',
        authoredAt: '2026-01-02T00:00:00+00:00',
      ),
      const SyntheticCommit(
        hash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        shortHash: 'bbbbbbb',
        subject: 'first commit',
        authorName: 'Grace Hopper',
        authorEmail: 'grace@example.invalid',
        authoredAt: '2026-01-01T00:00:00+00:00',
      ),
    ];

    test('parser survives log.showSignature gpg-line injection', () async {
      // Sanity: without signature lines the parser recovers the commits, so a
      // failure below is attributable to the injected gpg lines, not the fixture.
      final clean =
          await _historyFromStdout(_repo.dir.path, syntheticCommitLog(commits));
      expect(clean.map((c) => c.commitHash).toList(),
          equals([commits[0].hash, commits[1].hash]));

      final injected = await _historyFromStdout(
          _repo.dir.path, syntheticCommitLog(commits, signature: true));
      expect(injected.map((c) => c.commitHash).toList(),
          equals([commits[0].hash, commits[1].hash]),
          reason: 'gpg: signature lines shifted the fixed-8-line windows');
      // Was finding G10; fixed 2026-07-10 — _parseCommitLogLines screens
      // record-start `gpg:` lines, so an interleaved signature no longer
      // shifts the window. Armed.
    });

    test('parser degrades (no throw) on non-UTF-8 author/subject fields',
        () async {
      // A mismatched i18n.logOutputEncoding yields raw Latin-1 / invalid UTF-8
      // bytes in text fields. `log` decodes leniently (git.dart:718), so the
      // parser must return entries rather than throw. ARMED.
      final hostile = <SyntheticCommit>[
        SyntheticCommit(
          hash: commits[0].hash,
          shortHash: commits[0].shortHash,
          // 0xE9 = Latin-1 'é', an invalid standalone UTF-8 lead byte; 0xC3
          // with no continuation is a truncated sequence.
          authorNameRawBytes: const [0x41, 0xE9, 0x6C, 0x69, 0x65],
          subjectRawBytes: const [0x66, 0x69, 0x78, 0x20, 0xC3, 0x28],
          authoredAt: commits[0].authoredAt,
        ),
        commits[1],
      ];
      final bytes = syntheticCommitLog(hostile);

      // Must COMPLETE (not throw) — lenient decode substitutes U+FFFD.
      final future = _historyFromStdout(_repo.dir.path, bytes);
      await expectLater(future, completes);
      final entries = await future;
      expect(entries.length, 2,
          reason: 'non-UTF-8 fields must degrade to U+FFFD, not drop commits');
      expect(entries.map((c) => c.commitHash).toList(),
          equals([hostile[0].hash, hostile[1].hash]));
    });
  });
}
