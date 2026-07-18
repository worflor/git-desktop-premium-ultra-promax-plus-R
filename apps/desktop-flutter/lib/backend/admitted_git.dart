// admitted_git.dart — the front door for pulling git DIFF TEXT into memory.
//
// WHY THIS EXISTS. `runGit(repo, ['diff', ...])` hands back the whole patch as
// a Dart String. On a working tree carrying large files that is hundreds of MB
// of resident memory, and it is the ingestion vector the file-read gate (source
// law L12) is structurally blind to — no filesystem read happens.
//
// The first fix for this gated two call sites BY HAND. Hand-auditing is what
// let the class survive: `_computeCommitDream` got a gate while its twin
// `_computeBranchNameDream` — same probe, but UNSCOPED and fired automatically
// — did not, and stayed a live OOM path. So the policy lives here, once:
// callers say WHICH PATHS they are about to diff and hand over the work; the
// size estimate, the expansion factor, the budget, and the repo-switch scope
// are not theirs to re-decide.
//
// The declared cost is resident cost, not input size (the rule
// AnalysisAdmission documents): on-disk bytes of the changed paths × the
// diff pipeline's expansion.

import 'dart:io';

import 'analysis_admission.dart';
import 'git.dart' show gitBlobSize;

/// Resident expansion of diff TEXT over the on-disk bytes it covers: git
/// prints both sides of a modification (~2×), plus per-line sigils and
/// context, and Dart holds the result as UTF-16 (~2× again for ASCII source).
/// 4 is the planning factor; the memory lab's lifecycle gates
/// (test/memory/ingestion_lifecycle_test.dart) hold the whole pipeline to its
/// measured peak, so a drift past this shows up there rather than in a crash.
const int kDiffTextResidentExpansion = 4;

/// Sum of [relPaths]' on-disk sizes under [repo], stopping once past [cap]
/// (no point stat-ing more). A cheap upper-ish bound on what a diff over
/// those paths can print — never a second git call. Paths that no longer
/// exist (a deletion) contribute nothing they can be measured for; the
/// caller's cap is what keeps those honest.
int estimateDiffBytes(
  String repo,
  Iterable<String> relPaths, {
  required int cap,
}) {
  var total = 0;
  for (final path in relPaths) {
    try {
      final abs =
          '$repo${Platform.pathSeparator}'
          '${path.replaceAll('/', Platform.pathSeparator)}';
      final stat = File(abs).statSync();
      if (stat.type == FileSystemEntityType.file) total += stat.size;
    } catch (_) {}
    if (total > cap) break;
  }
  return total;
}

/// Run [work] — a git invocation that materializes diff text for [relPaths] —
/// under the process-wide analysis budget, scoped to the active repo so a
/// switch drops it while queued.
///
/// [relPaths] must ENUMERATE the paths the diff will cover. An empty iterable
/// declares a diff that covers nothing, and is admitted free — so it is a
/// trap for the "no `-- <paths>` argument means the whole working tree" idiom:
/// passing the caller's empty scope list would declare 0 bytes for the
/// LARGEST possible diff. When a diff is unscoped, pass the changed paths
/// from `git status` (a bounded probe) instead. If you cannot enumerate the
/// paths you cannot size the work, and must not call this.
///
/// Returns [AdmissionDecision.declined] when the estimated resident cost
/// alone can never fit: the caller MUST have a degraded path (skip the
/// feature, use a bounded surface, or spool the diff to disk instead). It is
/// never correct to "just run it anyway" — that is the bug this closes.
Future<Admitted<T>> admitGitDiffText<T>(
  String repo,
  Iterable<String> relPaths,
  Future<T> Function() work,
) {
  final budget = AnalysisAdmission.instance.totalBudget;
  // Cap the stat sweep one byte past what could ever be admitted: beyond
  // that the exact total is irrelevant, the answer is already "declined".
  final onDisk = estimateDiffBytes(
    repo,
    relPaths,
    cap: budget ~/ kDiffTextResidentExpansion + 1,
  );
  return AnalysisAdmission.instance.run(
    onDisk * kDiffTextResidentExpansion,
    work,
    scope: repoAnalysisScope,
  );
}

/// Resident expansion of whole-file TEXT: Dart holds a String as UTF-16, so
/// ASCII source doubles on decode. No both-sides multiplier — unlike a diff,
/// the content is printed once.
const int kFileTextResidentExpansion = 2;

/// Exact byte size of the object [revSpec] names (`HEAD:path`, a blob hash,
/// `rev:path`), via `cat-file -s`. Null when the object doesn't resolve.
/// `cat-file -s` takes any object spec, and its output is a number — this is
/// a measurement, not an estimate, so a `show` can be admitted at its true
/// cost rather than a guess.
Future<int?> gitObjectSize(String repo, String revSpec) =>
    gitBlobSize(repo, revSpec);

/// Run [work] — which materializes [bytes] of file text as a String — under
/// the analysis budget, scoped to the active repo.
///
/// [bytes] must be MEASURED by the caller (`stat` for a working file,
/// [gitObjectSize] for a revision), never guessed. Declined ⇒ the caller
/// does without that content; it is never correct to read it anyway.
Future<Admitted<T>> admitFileText<T>(int bytes, Future<T> Function() work) =>
    AnalysisAdmission.instance.run(
      bytes * kFileTextResidentExpansion,
      work,
      scope: repoAnalysisScope,
    );
