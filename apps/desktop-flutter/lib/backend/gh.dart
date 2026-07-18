import 'dart:convert';
import 'dart:io';

import 'git.dart' as git;
import 'git_result.dart';
import 'remote_types.dart';
import '../diagnostics/diagnostics_state.dart';
import '../features/diff/diff_models.dart';

export 'remote_types.dart'
    show
        PrReviewer,
        PullRequestSummary,
        PullRequestDetail,
        PrFile,
        RemoteComment,
        IssueSummary,
        IssueDetail,
        CheckSummary,
        TailEvent;

/// Thin wrapper around the GitHub CLI (`gh`). Mirrors the patterns in
/// `git.dart`: shell out, parse JSON, wrap in [GitResult]. We rely on
/// `gh` rather than rolling our own GitHub API client because it
/// already solves auth, refresh, and rate-limit handling — every user
/// that has `gh auth login` finished gets PR/issue support for free.

class GhStatus {
  final bool installed;
  final bool authenticated;
  final String? authError;

  const GhStatus({
    required this.installed,
    required this.authenticated,
    this.authError,
  });

  bool get usable => installed && authenticated;
}

Future<GhStatus> ghStatus() async {
  late ProcessResult v;
  late ProcessResult a;
  try {
    final results = await Future.wait([
      Process.run(
        'gh',
        ['--version'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ),
      Process.run(
        'gh',
        ['auth', 'status'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ),
    ]);
    v = results[0];
    a = results[1];
  } catch (_) {
    return const GhStatus(installed: false, authenticated: false);
  }
  if (v.exitCode != 0) {
    return const GhStatus(installed: false, authenticated: false);
  }
  if (a.exitCode != 0) {
    return GhStatus(
      installed: true,
      authenticated: false,
      authError: (a.stderr is String ? a.stderr as String : '').trim(),
    );
  }
  return const GhStatus(installed: true, authenticated: true);
}

Future<GitResult<List<PullRequestSummary>>> listPullRequests(
  String repoPath, {
  String state = 'open',
  int limit = 50,
}) async {
  final r = await _gh(repoPath, [
    'pr',
    'list',
    '--state',
    state,
    '--limit',
    '$limit',
    '--json',
    'number,title,headRefName,baseRefName,state,isDraft,author,comments,'
        'updatedAt,additions,deletions,changedFiles,mergeable,'
        'reviewDecision,reviewRequests,reviews,labels,assignees',
  ]);
  if (r.exitCode != 0) {
    return GitResult.err(r.stderr.toString().trim());
  }
  try {
    final parsed = jsonDecode(r.stdout.toString()) as List;
    final prs = parsed
        .whereType<Map<String, dynamic>>()
        .map(PullRequestSummary.fromJson)
        // Drop rows with no usable identity (unreadable `number`) rather than
        // surface a fabricated, actionable PR #0. See fromJson.
        .whereType<PullRequestSummary>()
        .toList();
    return GitResult.ok(prs);
  } catch (e) {
    return GitResult.err('Failed to parse gh pr list: $e');
  }
}

Future<GitResult<List<IssueSummary>>> listIssues(
  String repoPath, {
  String state = 'open',
  int limit = 50,
}) async {
  final r = await _gh(repoPath, [
    'issue',
    'list',
    '--state',
    state,
    '--limit',
    '$limit',
    '--json',
    'number,title,state,author,labels,comments,updatedAt,assignees',
  ]);
  if (r.exitCode != 0) {
    return GitResult.err(r.stderr.toString().trim());
  }
  try {
    final parsed = jsonDecode(r.stdout.toString()) as List;
    final issues = parsed
        .whereType<Map<String, dynamic>>()
        .map(IssueSummary.fromJson)
        // Drop identity-less rows rather than fabricate issue #0. See fromJson.
        .whereType<IssueSummary>()
        .toList();
    return GitResult.ok(issues);
  } catch (e) {
    return GitResult.err('Failed to parse gh issue list: $e');
  }
}

Future<GitResult<int>> createGhPr(
  String repoPath, {
  required String title,
  String body = '',
  required String headRef,
  required String baseRef,
  bool draft = false,
  List<String> labels = const [],
  List<String> assignees = const [],
  List<String> reviewers = const [],
}) async {
  final args = [
    'pr',
    'create',
    '--title',
    title,
    '--body',
    body,
    '--base',
    baseRef,
    '--head',
    headRef,
  ];
  if (draft) args.add('--draft');
  for (final l in labels) {
    args.addAll(['--label', l]);
  }
  for (final a in assignees) {
    args.addAll(['--assignee', a]);
  }
  for (final r in reviewers) {
    args.addAll(['--reviewer', r]);
  }
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final out = r.stdout.toString().trim();
  final match = RegExp(r'/pull/(\d+)').firstMatch(out);
  if (match == null) return GitResult.err('unexpected output: $out');
  return GitResult.ok(int.parse(match.group(1)!));
}

Future<GitResult<PullRequestSummary>> getPullRequestSummary(
  String repoPath,
  int number,
) async {
  final r = await _gh(repoPath, [
    'pr',
    'view',
    '$number',
    '--json',
    'number,title,headRefName,baseRefName,state,isDraft,author,comments,'
        'updatedAt,additions,deletions,changedFiles,mergeable,'
        'reviewDecision,reviewRequests,reviews,labels,assignees',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    final pr = PullRequestSummary.fromJson(j);
    if (pr == null) {
      return const GitResult.err(
        'gh pr view returned a row with no usable number',
      );
    }
    return GitResult.ok(pr);
  } catch (e) {
    return GitResult.err('Failed to parse gh pr view: $e');
  }
}

Future<GitResult<IssueSummary>> getIssueSummary(
  String repoPath,
  int number,
) async {
  final r = await _gh(repoPath, [
    'issue',
    'view',
    '$number',
    '--json',
    'number,title,state,author,labels,comments,updatedAt,assignees',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    final issue = IssueSummary.fromJson(j);
    if (issue == null) {
      return const GitResult.err(
        'gh issue view returned a row with no usable number',
      );
    }
    return GitResult.ok(issue);
  } catch (e) {
    return GitResult.err('Failed to parse gh issue view: $e');
  }
}

Future<String> whoami() async {
  try {
    final r = await Process.run(
      'gh',
      ['api', 'user', '--jq', '.login'],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) return '';
    return r.stdout.toString().trim();
  } catch (_) {
    return '';
  }
}

Future<GitResult<PullRequestDetail>> pullRequestDetail(
  String repoPath,
  int number, {
  bool includeDiff = true,
}) async {
  final viewFut = _gh(repoPath, [
    'pr',
    'view',
    '$number',
    '--json',
    'body,files,comments,reviews',
  ]);
  // The diff STREAMS to a spool during transport — a machine-scale PR's
  // patch never exists as a full in-memory String, even transiently. The
  // spill-after-fetch shape this replaced only bounded RETAINED memory;
  // peak memory still hit the OOM class during the buffered fetch itself.
  final diffFut = includeDiff
      ? spoolForgeCliStdout('gh', repoPath, ['pr', 'diff', '$number'])
      : Future<GitResult<git.SpooledDiff>?>.value(null);
  final view = await viewFut;
  final diffRes = await diffFut;
  if (view.exitCode != 0) {
    await diffRes?.data?.dispose(); // don't leak the parallel fetch's spool
    return GitResult.err(view.stderr.toString().trim());
  }
  // A requested-but-failed patch fetch (auth, rate limit, gh error) must not
  // masquerade as "this PR has an empty diff" — the metadata would render
  // while the actual changes silently disappear from the review surface.
  if (diffRes != null && !diffRes.ok) {
    final err = (diffRes.error ?? '').trim();
    return GitResult.err(err.isEmpty ? 'gh pr diff failed' : err);
  }
  try {
    final j = jsonDecode(view.stdout.toString()) as Map<String, dynamic>;
    final files = (j['files'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (f) => PrFile(
            path: (f['path'] as String? ?? '').trim(),
            additions: (f['additions'] as num? ?? 0).toInt(),
            deletions: (f['deletions'] as num? ?? 0).toInt(),
          ),
        )
        .toList();
    final comments = (j['comments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RemoteComment.fromJson)
        .toList();
    final reviews = (j['reviews'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((r) {
          final author = r['author'];
          final login = author is Map<String, dynamic>
              ? (author['login'] as String? ?? '')
              : '';
          final body = (r['body'] as String? ?? '').trim();
          final state = (r['state'] as String? ?? '').toUpperCase();
          if (body.isEmpty) return null;
          final tag = switch (state) {
            'APPROVED' => '[approved]',
            'CHANGES_REQUESTED' => '[requested changes]',
            'COMMENTED' => '[commented]',
            'DISMISSED' => '[dismissed]',
            _ => '',
          };
          return RemoteComment(
            authorLogin: login,
            body: tag.isEmpty ? body : '$tag\n\n$body',
            createdAt: parseRemoteDate(r['submittedAt']),
          );
        })
        .whereType<RemoteComment>()
        .toList();
    final mergedComments = [...comments, ...reviews]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // No eager ParsedLine parse: the diff renders lazily downstream, and the
    // one field that used it (`diffByFile`) was never read — parsing a large
    // PR into one object per row was pure OOM risk. Small spools materialize
    // into the String form; large ones stay on disk as the detail's spool.
    final resolved = diffRes?.data == null
        ? (rawDiff: '', spill: null as git.SpooledDiff?)
        : await resolveDetailDiffSpool(diffRes!.data!);
    return GitResult.ok(
      PullRequestDetail(
        body: (j['body'] as String? ?? '').trim(),
        files: files,
        comments: mergedComments,
        diff: resolved.rawDiff,
        rawDiffByFile: resolved.spill == null
            ? sliceDiffByFileForDetail(resolved.rawDiff)
            : const {},
        diffSpool: resolved.spill,
        diffLoaded: includeDiff,
      ),
    );
  } catch (e) {
    // Parse failure after a successful diff fetch: release the spool the
    // detail object never got to own.
    await diffRes?.data?.dispose();
    return GitResult.err('Failed to parse gh pr view: $e');
  }
}

Future<GitResult<IssueDetail>> issueDetail(String repoPath, int number) async {
  final r = await _gh(repoPath, [
    'issue',
    'view',
    '$number',
    '--json',
    'body,comments,assignees,labels',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  try {
    final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
    return GitResult.ok(
      IssueDetail(
        body: (j['body'] as String? ?? '').trim(),
        comments: (j['comments'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RemoteComment.fromJson)
            .toList(),
        assignees: parseAssigneeLogins(j['assignees']),
        labels: parseLabelStrings(j['labels']),
      ),
    );
  } catch (e) {
    return GitResult.err('Failed to parse gh issue view: $e');
  }
}

Future<GitResult<void>> submitPrReview(
  String repoPath,
  int number, {
  required String event,
  String body = '',
}) async {
  final flag = switch (event) {
    'approve' => '--approve',
    'request-changes' => '--request-changes',
    'comment' => '--comment',
    _ => '--comment',
  };
  final args = ['pr', 'review', '$number', flag, '--body', body];
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> mergePullRequest(
  String repoPath,
  int number, {
  required String method,
  bool deleteBranch = false,
}) async {
  final flag = switch (method) {
    'squash' => '--squash',
    'rebase' => '--rebase',
    _ => '--merge',
  };
  final args = [
    'pr',
    'merge',
    '$number',
    flag,
    if (deleteBranch) '--delete-branch',
  ];
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> checkoutPullRequest(String repoPath, int number) async {
  final r = await _gh(repoPath, ['pr', 'checkout', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> closePullRequest(String repoPath, int number) async {
  final r = await _gh(repoPath, ['pr', 'close', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> assignSelfToIssue(String repoPath, int number) async {
  final r = await _gh(repoPath, [
    'issue',
    'edit',
    '$number',
    '--add-assignee',
    '@me',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> addIssueLabel(
  String repoPath,
  int number,
  String label,
) async {
  final r = await _gh(repoPath, [
    'issue',
    'edit',
    '$number',
    '--add-label',
    label,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> closeIssue(String repoPath, int number) async {
  final r = await _gh(repoPath, ['issue', 'close', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> commentOnIssue(
  String repoPath,
  int number,
  String body,
) async {
  if (body.trim().isEmpty) return const GitResult.ok(null);
  final r = await _gh(repoPath, [
    'issue',
    'comment',
    '$number',
    '--body',
    body,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<int>> createGhIssue(
  String repoPath, {
  required String title,
  String body = '',
  List<String> labels = const [],
  List<String> assignees = const [],
}) async {
  final args = ['issue', 'create', '--title', title, '--body', body];
  for (final l in labels) {
    args.addAll(['--label', l]);
  }
  for (final a in assignees) {
    args.addAll(['--assignee', a]);
  }
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final out = r.stdout.toString().trim();
  final match = RegExp(r'/issues/(\d+)').firstMatch(out);
  if (match == null) return GitResult.err('unexpected output: $out');
  return GitResult.ok(int.parse(match.group(1)!));
}

Future<GitResult<void>> editGhIssue(
  String repoPath,
  int number, {
  String? title,
  String? body,
  List<String> addLabels = const [],
  List<String> removeLabels = const [],
}) async {
  final args = ['issue', 'edit', '$number'];
  if (title != null) args.addAll(['--title', title]);
  if (body != null) args.addAll(['--body', body]);
  for (final l in addLabels) {
    args.addAll(['--add-label', l]);
  }
  for (final l in removeLabels) {
    args.addAll(['--remove-label', l]);
  }
  if (args.length == 3) return const GitResult.ok(null);
  final r = await _gh(repoPath, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> reopenGhIssue(String repoPath, int number) async {
  final r = await _gh(repoPath, ['issue', 'reopen', '$number']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> commentOnPullRequest(
  String repoPath,
  int number,
  String body,
) async {
  if (body.trim().isEmpty) return const GitResult.ok(null);
  final r = await _gh(repoPath, ['pr', 'comment', '$number', '--body', body]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<List<CheckSummary>>> listChecks(
  String repoPath,
  int prNumber,
) async {
  final r = await _gh(repoPath, [
    'pr',
    'checks',
    '$prNumber',
    '--json',
    'name,bucket,state,startedAt,completedAt',
  ]);
  final stdout = r.stdout.toString();
  if (stdout.trim().isEmpty) {
    return GitResult.err(r.stderr.toString().trim());
  }
  try {
    final parsed = jsonDecode(stdout) as List;
    final checks = parsed
        .whereType<Map<String, dynamic>>()
        .map(CheckSummary.fromJson)
        .toList();
    return GitResult.ok(checks);
  } catch (e) {
    return GitResult.err('Failed to parse gh pr checks: $e');
  }
}

Future<ProcessResult> _gh(String repo, List<String> args) =>
    runForgeCli('gh', repo, args);

/// Spawns a forge CLI (`gh`, `glab`, …) and returns its [ProcessResult].
/// The binary name is a parameter so both wrappers — and the tests —
/// share one spawn path.
///
/// If the binary vanishes from PATH mid-session (or was never installed)
/// [Process.run] throws a [ProcessException], which would otherwise tear
/// straight through the GitResult-returning call sites — none of them
/// catch it. We contain the spawn failure here and hand back a synthetic
/// non-zero result whose stderr reads like any other CLI error, so those
/// callers funnel it into a clean `GitResult.err` via their existing
/// exit-code check instead of surfacing a raw exception. The status
/// probes (`ghStatus` / `glabStatus`) run their own guarded spawns and
/// are unaffected.
Future<ProcessResult> runForgeCli(
  String bin,
  String repo,
  List<String> args,
) async {
  final lifecycle = _ForgeCliLifecycle(bin, args);
  try {
    final result = await Process.run(
      bin,
      args,
      workingDirectory: repo,
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    lifecycle.end(
      errorCode: result.exitCode == 0 ? null : 'exit.${result.exitCode}',
    );
    return result;
  } on ProcessException catch (e) {
    lifecycle.end(errorCode: 'process.exception');
    // 127 is the conventional "command not found" exit code. The message
    // mirrors a normal stderr line so the call site treats it uniformly.
    return ProcessResult(0, 127, '', _forgeSpawnFailureMessage(bin, e));
  }
}

/// One lifecycle bracket shared by BOTH forge CLI execution paths —
/// [runForgeCli] (buffered) and [spoolForgeCliStdout] (streamed to a spool).
/// The two deliberately differ ONLY in transport; the label shape, the
/// diagnostics events, and the spawn-failure wording live here so the pair
/// cannot drift apart as they evolve.
class _ForgeCliLifecycle {
  _ForgeCliLifecycle(String bin, List<String> args)
    : label = '$bin.${args.isNotEmpty ? args.first : 'unknown'}' {
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'start',
      command: label,
    );
  }

  final String label;
  final Stopwatch _stopwatch = Stopwatch()..start();

  void end({String? errorCode}) {
    _stopwatch.stop();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'end',
      command: label,
      durationMs: _stopwatch.elapsedMicroseconds / 1000,
      errorCode: errorCode,
    );
  }
}

/// The user-facing wording for a forge CLI that failed to SPAWN, shared by
/// both execution paths. A [ProcessException] almost always means the binary
/// is missing from PATH; anything else keeps the raw error.
String _forgeSpawnFailureMessage(String bin, Object e) => e is ProcessException
    ? '$bin not found on PATH (${e.message.trim()}) — is it installed?'
    : '$bin spawn failed: $e';

/// [runForgeCli], but stdout STREAMS to a temp spool file instead of being
/// buffered into a String. This is what makes the machine-scale contract
/// hold at the fetch itself: a huge `gh pr diff` / `glab mr diff` previously
/// materialized fully in memory BEFORE any spill decision, so peak memory
/// still hit the OOM class the spool exists to prevent. stderr stays small
/// (bounded human messages) and is collected for the error path. Nonzero
/// exit or spawn failure returns err and cleans up the partial spool.
Future<GitResult<git.SpooledDiff>> spoolForgeCliStdout(
  String bin,
  String repo,
  List<String> args,
) async {
  final lifecycle = _ForgeCliLifecycle(bin, args);
  Directory? dir;
  try {
    dir = await Directory.systemTemp.createTemp('manifold_diff');
    final spool = File('${dir.path}${Platform.pathSeparator}forge.diff');
    final proc = await Process.start(
      bin,
      args,
      workingDirectory: repo,
      runInShell: false,
    );
    final sink = spool.openWrite();
    // Lenient stderr decode: a forge CLI can emit non-UTF-8 bytes in error
    // text, and a strict decoder would turn the REAL failure message into a
    // FormatException.
    final stderrFut = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    try {
      await proc.stdout.pipe(sink); // pipe closes the sink on completion
    } catch (_) {
      // The child must never outlive this request: a temp-file write
      // failure mid-stream would otherwise orphan a live gh/glab process
      // (and its dangling stderr reader) outside any lifecycle. Kill it,
      // then drain BOTH futures to completion so nothing throws unobserved.
      proc.kill();
      try {
        await sink.close();
      } catch (_) {}
      try {
        await stderrFut;
      } catch (_) {}
      try {
        await proc.exitCode;
      } catch (_) {}
      rethrow;
    }
    final exitCode = await proc.exitCode;
    final stderrText = (await stderrFut).trim();
    lifecycle.end(errorCode: exitCode == 0 ? null : 'exit.$exitCode');
    if (exitCode != 0) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      return GitResult.err(
        stderrText.isEmpty ? '$bin exited $exitCode' : stderrText,
      );
    }
    final len = await spool.length();
    return GitResult.ok(git.SpooledDiff(spool.path, dir.path, len));
  } catch (e) {
    lifecycle.end(errorCode: 'process.exception');
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    return GitResult.err(_forgeSpawnFailureMessage(bin, e));
  }
}

/// Resolve a fetched diff spool into the detail representation: small spools
/// materialize (leniently) into the String form and are released; large ones
/// are RETAINED as the detail's [git.SpooledDiff]. One implementation for
/// gh/glab/gitea so "large" and the decode policy can never drift between
/// providers.
Future<({String rawDiff, git.SpooledDiff? spill})> resolveDetailDiffSpool(
  git.SpooledDiff spool, {
  int spillBytes = git.kDetailDiffSpillBytes,
}) async {
  if (spool.byteLength > spillBytes) {
    return (rawDiff: '', spill: spool);
  }
  try {
    final rawDiff = spool.byteLength == 0
        ? ''
        : await git.readSpoolStringLenient(spool.path);
    return (rawDiff: rawDiff, spill: null);
  } finally {
    await spool.dispose();
  }
}
