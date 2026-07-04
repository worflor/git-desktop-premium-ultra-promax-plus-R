import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/logos_git_state.dart';
import '../../app/repository_state.dart';
import '../../backend/dtos.dart';
import '../../backend/git.dart';
import '../../backend/git_result.dart';
import '../../backend/merge_session.dart';
import 'conflict_resolution.dart';
import 'merge_conflict_editor.dart';

/// The single conflict-resolution path shared by pull, branch-merge and the
/// patch-apply preview. Before this, the "read the conflicted files → parse
/// → enrich with Logos → push [MergeEditorPage] → refresh status" sequence
/// was copy-pasted in three places and pull had none of it at all. Everything
/// now funnels through here.
///
/// The design follows the patch-apply baseline: `git merge` is the only
/// dirty-INTOLERANT primitive, so a pull into a dirty working tree is
/// reconciled with `git merge-file` (blob-level 3-way) instead of stashing,
/// and the reconcile is non-mutating until the user commits — cancelling the
/// editor leaves the tree exactly as it was.

/// Reads each conflicted path from the working tree and parses its markers
/// into a [ConflictFile]. Paths without markers (or missing) are skipped.
/// BINARY-SAFE: reads bytes and skips non-text files instead of letting a
/// strict-UTF-8 `readAsString` throw — a binary UU entry (two branches both
/// changed an asset, a modify/delete) must be skipped here, not crash the
/// whole conflict flow. Skipped UU then trips the conclusion gate, leaving
/// the operation cleanly in progress.
Future<List<ConflictFile>> gatherConflictFiles(
    String repoPath, Iterable<String> paths) async {
  final files = <ConflictFile>[];
  for (final path in paths) {
    final abs = '$repoPath/$path'.replaceAll('/', Platform.pathSeparator);
    final f = File(abs);
    if (!await f.exists()) continue;
    final bytes = await f.readAsBytes();
    if (_looksBinary(bytes)) continue; // NUL byte ⇒ not a text conflict
    final String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      continue; // non-UTF-8 ⇒ can't show in the text editor
    }
    if (!content.contains('<<<<<<<')) continue;
    files.add(parseConflictFile(path, content));
  }
  return files;
}

/// NUL byte in the first 8000 bytes ⇒ binary (git's own heuristic).
bool _looksBinary(List<int> bytes) {
  final n = bytes.length < 8000 ? bytes.length : 8000;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// The unified conflict window. ANY operation that hits a conflict shows this
/// intermediate surface — the user picks AI resolve, the 3-way merge editor,
/// or defer — instead of being marched straight into the editor. For the
/// on-disk (native) flows where conflicts are already UU markers in the tree.
/// Returns true when the conflicts were resolved.
Future<bool> presentConflicts(
  BuildContext context,
  String repoPath, {
  required List<ConflictFile> files,
  required String opLabel,
  bool canDefer = true,
}) async {
  final paths = files.map((f) => f.path).toList();
  final blocks = files.fold<int>(0, (n, f) => n + f.blocks.length);
  final choice = await showConflictWindow(context,
      opLabel: opLabel, paths: paths, blockCount: blocks, canDefer: canDefer);
  if (choice == null || !context.mounted) return false;
  switch (choice.action) {
    case ConflictAction.manual:
      return openConflictEditor(context, repoPath, files);
    case ConflictAction.ai:
      await resolveConflictsWithAi(
          context, repoPath, choice.aiCategory ?? 'fast', paths);
      if (!context.mounted) return false;
      await context.read<RepositoryState>().refreshStatus();
      if (!context.mounted) return false;
      // Resolved when no conflicted (UU) files remain.
      final status = context.read<RepositoryState>().status;
      final remaining =
          status?.files.where((f) => f.isConflicted).length ?? 0;
      return remaining == 0;
    case ConflictAction.defer:
      return false;
  }
}

String _opLabel(SequencerKind kind) => switch (kind) {
      SequencerKind.merge => 'merge',
      SequencerKind.cherryPick => 'cherry-pick',
      SequencerKind.revert => 'revert',
      SequencerKind.plain => 'resolve',
    };

/// Enriches [files] with Logos signal (best-effort), pushes the shared
/// [MergeEditorPage], and refreshes status on return. Returns true when the
/// user completed the resolution (the editor wrote + staged the files),
/// false when they cancelled.
Future<bool> openConflictEditor(
    BuildContext context, String repoPath, List<ConflictFile> files) async {
  if (files.isEmpty) return false;
  final logosState = context.read<LogosGitState>();
  var engine = logosState.engineFor(repoPath);
  if (engine == null) {
    await logosState.loadForRepo(repoPath);
    if (!context.mounted) return false;
    engine = logosState.engineFor(repoPath);
  }
  if (engine != null) {
    final paths = files.map((f) => f.path).toSet();
    for (final cf in files) {
      enrichConflictFileWithLogos(cf, engine, paths);
    }
  }
  if (!context.mounted) return false;
  final navigator = Navigator.of(context);
  final repoState = context.read<RepositoryState>();
  final result = await navigator.push<String>(
    MaterialPageRoute(
      builder: (_) => MergeEditorPage(files: files, repoPath: repoPath),
    ),
  );
  await repoState.refreshStatus();
  return result == 'done';
}

/// The git operation whose conflicts are being resolved — selects how the
/// resolution is concluded once the editor finishes.
enum SequencerKind {
  /// `git merge` / branch-merge — conclude with a commit (`MERGE_HEAD` set).
  merge,

  /// `git cherry-pick` — conclude with `cherry-pick --continue`.
  cherryPick,

  /// `git revert` — conclude with `revert --continue`.
  revert,

  /// `git stash pop`, `checkout -m`, or any op that leaves markers but needs
  /// no commit/continue — the resolved content simply stays in the tree.
  plain,
}

/// The universal conflict sink. ANY operation that leaves UU markers in the
/// working tree — merge, cherry-pick, revert, stash pop, `checkout -m` —
/// gathers them into the one shared editor and concludes per [kind]. Returns
/// false when there were no conflicts (a genuine error the caller surfaces)
/// or the user cancelled.
Future<bool> resolveSequencerConflicts(
    BuildContext context, String repoPath, SequencerKind kind) async {
  await context.read<RepositoryState>().refreshStatus();
  if (!context.mounted) return false;
  final status = context.read<RepositoryState>().status;
  final uu = <String>[
    for (final f in status?.files ?? const <RepositoryStatusFile>[])
      if (f.isConflicted) f.path,
  ];
  if (uu.isEmpty) return false;
  final files = await gatherConflictFiles(repoPath, uu);
  if (files.isEmpty || !context.mounted) return false;
  final resolved = await presentConflicts(context, repoPath,
      files: files, opLabel: _opLabel(kind));
  if (!resolved || !context.mounted) return false;
  // The editor only resolves TEXT conflicts; non-text UU (binary, rename,
  // modify/delete) are skipped by gatherConflictFiles. Concluding now would
  // make git reject the commit/continue with a cryptic "unmerged files"
  // error and leave a half-concluded state — so bail with the operation
  // still cleanly in progress for the user to finish by hand.
  if (await _hasRemainingConflicts(context, repoPath)) return false;
  final fin = switch (kind) {
    SequencerKind.merge => await commitResolvedMerge(repoPath),
    SequencerKind.cherryPick => await continueCherryPick(repoPath),
    SequencerKind.revert => await continueRevert(repoPath),
    SequencerKind.plain => const GitResult<void>.ok(null),
  };
  if (context.mounted) {
    await context.read<RepositoryState>().refreshStatus();
  }
  return fin.ok;
}

/// True when conflicted (UU) paths still remain — used to gate a sequencer
/// conclusion so a binary/non-text conflict the text editor can't resolve
/// doesn't get committed over with a cryptic git error.
Future<bool> _hasRemainingConflicts(
    BuildContext context, String repoPath) async {
  if (!context.mounted) return false;
  await context.read<RepositoryState>().refreshStatus();
  if (!context.mounted) return false;
  return (context.read<RepositoryState>().status?.files ??
          const <RepositoryStatusFile>[])
      .any((f) => f.isConflicted);
}

/// Back-compat alias for the merge case (branch-merge / native pull).
Future<bool> resolveNativeMergeConflicts(
        BuildContext context, String repoPath) =>
    resolveSequencerConflicts(context, repoPath, SequencerKind.merge);

/// Resumes whatever conflict the repo was left in — the recovery entry point
/// after a deferred/cancelled resolution. Critically it detects a PAUSED
/// REBASE (which needs `rebase --continue`, not a commit) and drives its
/// loop; otherwise it concludes the in-progress sequencer (merge /
/// cherry-pick / revert) or a bare working-tree conflict. Without this, a
/// cancelled rebase-sync stranded the user in a detached, paused rebase that
/// no recovery surface could conclude.
Future<MergeOutcome> resumeConflicts(BuildContext context, String repoPath,
    {bool pushAfterRebase = false}) async {
  if (await isRebaseInProgress(repoPath)) {
    if (!context.mounted) return const MergeConflicted([]);
    final outcome = await _resolveRebaseLoop(context, repoPath, const []);
    // The rebase COMPLETED iff the loop returned clean (it still paused →
    // MergeConflicted, or errored → MergeFailed). A completed rebase owes a
    // push ONLY when the caller knows this resume belongs to a sync — gating
    // on [pushAfterRebase] rather than an internal assumption means a future
    // non-sync rebase recovery can't publish commits the user never shared.
    if (pushAfterRebase && outcome is MergeClean) {
      final remote = await trackingRemote(repoPath);
      final push = await pushRemote(repoPath, remote: remote);
      if (!push.ok) return MergeFailed(push.error ?? 'Push failed');
      return MergeClean(SyncData(
          operation: 'sync',
          remote: remote,
          output: 'Rebased and pushed.'));
    }
    return outcome;
  }
  if (!context.mounted) return const MergeConflicted([]);
  final op = await inProgressOperation(repoPath);
  final kind = switch (op) {
    'cherry-pick' => SequencerKind.cherryPick,
    'revert' => SequencerKind.revert,
    'merge' => SequencerKind.merge,
    _ => SequencerKind.plain,
  };
  if (!context.mounted) return const MergeConflicted([]);
  final resolved = await resolveSequencerConflicts(context, repoPath, kind);
  final remaining = <String>[
    if (context.mounted)
      for (final f in context.read<RepositoryState>().status?.files ??
          const <RepositoryStatusFile>[])
        if (f.isConflicted) f.path,
  ];
  return MergeConflicted(remaining, resolved: resolved);
}

/// Switch to [name], carrying uncommitted edits across. A plain switch works
/// (and carries non-overlapping edits) unless an edit would be overwritten;
/// in that case we use `git checkout -m` (a 3-way carry that leaves markers
/// on overlap) and route any markers into the shared editor. No stash.
Future<MergeOutcome> resolveCheckout(
    BuildContext context, String repoPath, String name) async {
  final r = await checkoutBranch(repoPath, name);
  if (r.ok) {
    return MergeClean(
        SyncData(operation: 'checkout', remote: '', output: 'Switched to $name.'));
  }
  // A plain switch only fails when an edit would be overwritten (the dirty
  // overlap), or for a structural reason (no such branch, detached issues).
  // Rather than match git's English abort message — which breaks on non-en
  // locales — just retry with the 3-way carry: on overlap it carries the
  // edits across (markers on conflict); on a structural failure it fails the
  // same way, and we surface the ORIGINAL error (more specific than `-m`'s).
  final m = await checkoutMerge(repoPath, name);
  if (!m.ok) {
    final err = r.error ?? m.error ?? 'Switch failed.';
    return MergeFailed(err.isEmpty ? 'Switch failed.' : err);
  }
  if (!context.mounted) return const MergeConflicted([]);
  await context.read<RepositoryState>().refreshStatus();
  if (!context.mounted) return const MergeConflicted([]);
  final status = context.read<RepositoryState>().status;
  final uu = <String>[
    for (final f in status?.files ?? const <RepositoryStatusFile>[])
      if (f.isConflicted) f.path,
  ];
  if (uu.isEmpty) {
    return MergeClean(SyncData(
        operation: 'checkout',
        remote: '',
        output: 'Switched to $name (changes carried over).'));
  }
  final files = await gatherConflictFiles(repoPath, uu);
  if (files.isEmpty || !context.mounted) return MergeConflicted(uu);
  final resolved = await presentConflicts(context, repoPath,
      files: files, opLabel: 'switch');
  if (!resolved) return MergeConflicted(uu, resolved: false);
  if (!context.mounted) return MergeConflicted(uu, resolved: true);
  // Same gate the sequencer/rebase paths use: gatherConflictFiles skips
  // binary/rename UU the editor can't show, so resolving the text files
  // doesn't mean the switch is clean. Only claim resolved when no UU remain —
  // otherwise the callers would suppress the "unresolved conflicts" warning.
  if (await _hasRemainingConflicts(context, repoPath)) {
    return MergeConflicted(uu, resolved: false);
  }
  return MergeConflicted(uu, resolved: true);
}

/// The unified pull. Fetches, classifies (via [prepareMergePull]), and routes:
///   • clean working tree → native `git merge`; conflicts go to the editor,
///     then a commit concludes the merge.
///   • dirty working tree → blob-level `git merge-file` reconcile (no stash);
///     conflicts go to the same editor, then finalize records the right
///     topology (fast-forward reset, or a two-parent merge commit).
/// Returns a [MergeOutcome] the caller renders directly.
Future<MergeOutcome> resolvePull(BuildContext context, String repoPath,
    {bool rebase = false}) async {
  final prep = await prepareMergePull(repoPath, rebase: rebase);
  if (prep.error != null) return MergeFailed(prep.error!);
  if (prep.upToDate) {
    return MergeClean(SyncData(
        operation: 'pull',
        remote: await trackingRemote(repoPath),
        output: 'Already up to date.'));
  }

  // ── Clean working tree: native merge is robust (renames, modes, binary).
  if (!prep.dirty) {
    final outcome = await runNativeMerge(repoPath, prep);
    if (outcome is! MergeConflicted) return outcome;
    if (!context.mounted) return outcome;
    if (prep.topology == MergeTopology.rebase) {
      // oursLabel = local branch, theirsLabel = upstream ref — the exact
      // "replay <local> onto <upstream>" the header needs.
      return _resolveRebaseLoop(context, repoPath, outcome.paths,
          replayLabel: 'rebase ${prep.oursLabel} onto ${prep.theirsLabel}');
    }
    final files = await gatherConflictFiles(repoPath, outcome.paths);
    if (!context.mounted) return outcome;
    final resolved = files.isNotEmpty &&
        await presentConflicts(context, repoPath, files: files, opLabel: 'pull');
    if (!resolved) return MergeConflicted(outcome.paths);
    // Non-text UU left unresolved would make the merge commit fail — leave
    // the merge in progress rather than half-concluding it.
    if (!context.mounted) return MergeConflicted(outcome.paths);
    if (await _hasRemainingConflicts(context, repoPath)) {
      return MergeConflicted(outcome.paths);
    }
    final commit = await commitResolvedMerge(repoPath);
    if (!commit.ok) return MergeFailed(commit.error!);
    return MergeConflicted(outcome.paths, resolved: true);
  }

  // ── Dirty working tree (the "would be overwritten" case).
  if (prep.topology == MergeTopology.rebase) {
    // The one irreducible corner: a rebase needs a clean surface. Surface it
    // as actionable rather than reconciling incorrectly.
    return MergeBlockedByLocalChanges(prep.blockingPaths);
  }
  final reconciled = await reconcileDirtyMerge(repoPath, prep);
  // A binary that changed on BOTH sides can't be 3-way merged or shown in the
  // text editor. Don't mutate — block so the user commits/stashes and
  // resolves it with git (native merge handles binary conflicts).
  final binaryConflicts = reconciled
      .where((f) => f.binary && f.conflicted)
      .map((f) => f.path)
      .toList();
  if (binaryConflicts.isNotEmpty) {
    return MergeBlockedByLocalChanges(binaryConflicts);
  }
  // Only text conflicts reach the editor; clean binaries (take-theirs) are
  // written as raw bytes at finalize.
  final conflicted = reconciled.where((f) => f.conflicted).toList();
  final conflictPaths = conflicted.map((f) => f.path).toList();
  if (conflicted.isNotEmpty) {
    final files = [
      for (final f in conflicted)
        parseConflictFile(f.path, f.mergedText,
            oursBranch: prep.oursLabel, theirsBranch: prep.theirsLabel),
    ];
    if (!context.mounted) return MergeConflicted(conflictPaths);
    // Dirty-pull conflicts live in memory until resolved (the tree is still
    // the user's uncommitted work). The window can't "defer" them — there's
    // no persisted merge to come back to — so it offers discard instead.
    final resolved = await _resolveDirtyConflicts(context, repoPath, files);
    // Discard / cancel always restores the tree to the user's pristine edits
    // (the editor wrote nothing, or the AI attempt was rolled back). So there
    // is nothing to resolve — report it as a cancel with NO paths, not a
    // pending conflict, or the recovery notice would point at files that have
    // no markers.
    if (!resolved) return const MergeConflicted([], resolved: false);
  }
  final fin = await finalizeReconciledMerge(repoPath, prep, reconciled);
  if (!fin.ok) return MergeFailed(fin.error!);
  if (context.mounted) {
    await context.read<RepositoryState>().refreshStatus();
  }
  return conflictPaths.isEmpty
      ? MergeClean(SyncData(
          operation: 'pull',
          remote: prep.remote,
          output:
              'Merged ${prep.upstream} (${prep.incomingPaths.length} files).'))
      : MergeConflicted(conflictPaths, resolved: true);
}

/// Drives a paused `pull --rebase` to completion: resolve each conflicting
/// step in the editor, `git rebase --continue`, repeat until the rebase ends.
/// [replayLabel] names the operation in the conflict window's header so the
/// user sees WHAT is being replayed ONTO WHAT mid-rebase (e.g.
/// `rebase main onto origin/main`) instead of a bare "rebase".
Future<MergeOutcome> _resolveRebaseLoop(
    BuildContext context, String repoPath, List<String> firstPaths,
    {String replayLabel = 'rebase'}) async {
  // Accumulate every path resolved across all rebase steps so the reported
  // count reflects reality — the resume entry point hands in an empty
  // firstPaths, so without this the UI would always say "0 conflicts".
  final touched = <String>{...firstPaths};
  var guard = 0;
  while (await isRebaseInProgress(repoPath)) {
    if (guard++ > 256) {
      return const MergeFailed('Rebase did not converge — resolve manually.');
    }
    if (!context.mounted) return MergeConflicted(touched.toList());
    await context.read<RepositoryState>().refreshStatus();
    if (!context.mounted) return MergeConflicted(touched.toList());
    final status = context.read<RepositoryState>().status;
    final uu = <String>[
      for (final f in status?.files ?? const <RepositoryStatusFile>[])
        if (f.isConflicted) f.path,
    ];
    if (uu.isEmpty) {
      // No conflicts at this step — advance the rebase.
      final cont = await continueRebase(repoPath);
      // A non-zero `--continue` that left FRESH conflicts just means git
      // halted at the NEXT conflicting commit — keep looping to present it.
      // Only fail when no conflicts remain (a genuine, stuck abort).
      if (!cont.ok &&
          await isRebaseInProgress(repoPath) &&
          !await hasUnmergedPaths(repoPath)) {
        return MergeFailed(cont.error!);
      }
      continue;
    }
    touched.addAll(uu);
    final files = await gatherConflictFiles(repoPath, uu);
    if (files.isEmpty || !context.mounted) {
      return MergeConflicted(touched.toList());
    }
    // Route through the unified window so a rebase step offers the same
    // AI / merge-editor / defer choice as pull/merge/cherry-pick — defer
    // leaves the rebase cleanly paused. (Was openConflictEditor directly,
    // which marched the user straight into the editor.)
    final resolved = await presentConflicts(context, repoPath,
        files: files, opLabel: replayLabel);
    if (!resolved) return MergeConflicted(touched.toList());
    if (!context.mounted) return MergeConflicted(touched.toList());
    // Same gate the sequencer/checkout paths use: gatherConflictFiles skips
    // binary/non-text UU the editor can't show, so concluding with
    // `rebase --continue` while those remain fails with a cryptic "unmerged
    // paths" error. Leave the rebase cleanly in progress for the user instead.
    if (await _hasRemainingConflicts(context, repoPath)) {
      return MergeConflicted(touched.toList());
    }
    final cont = await continueRebase(repoPath);
    // As above: a non-zero `--continue` that halted at the next conflict
    // (fresh UU, still in progress) is not a failure — loop on to present it.
    if (!cont.ok &&
        await isRebaseInProgress(repoPath) &&
        !await hasUnmergedPaths(repoPath)) {
      return MergeFailed(cont.error!);
    }
  }
  if (context.mounted) {
    await context.read<RepositoryState>().refreshStatus();
  }
  // The loop only exits when the rebase is no longer in progress — it
  // COMPLETED. Return clean (the count rides in the message) so the sync push
  // gate keys on "rebase finished", not "the editor happened to open this
  // round" — a resume that only needed `rebase --continue` still owes the push.
  final remote = await trackingRemote(repoPath);
  return MergeClean(SyncData(
      operation: 'pull',
      remote: remote,
      output: touched.isEmpty
          ? 'Rebased.'
          : 'Rebased (resolved ${touched.length} '
              'file${touched.length == 1 ? '' : 's'}).'));
}

/// Smart sync mirroring the legacy smart-sync decision tree (publish / pull /
/// push / pull-then-push / fetch), but routing the pull leg through
/// [resolvePull] so conflicts land in the unified editor instead of a raw
/// error.
Future<MergeOutcome> resolveSync(
    BuildContext context, String repoPath, RepositoryStatus status) async {
  final branch = status.branch;
  if (branch == 'HEAD' || branch.startsWith('(')) {
    return const MergeFailed(
        'Cannot sync: detached HEAD state. Check out a branch first.');
  }
  if (status.upstream == null) {
    // Publish leg: resolve the ACTUAL remote first. A bare pushRemote
    // defaults to 'origin', which errors on a repo whose only remote has
    // another name and produces a raw fatal on a repo with none — the
    // fresh-`git init` case deserves a sentence, not a stack of git noise.
    final remote = await primaryRemoteName(repoPath);
    if (!remote.ok) return MergeFailed(remote.error ?? 'Publish failed.');
    final remoteName = remote.data;
    if (remoteName == null) {
      return const MergeFailed(
          'No remote configured. Add one to publish this branch.');
    }
    return _wrapPush(
        await pushRemote(repoPath, remote: remoteName, setUpstream: true));
  }
  if (status.ahead > 0 && status.behind > 0) {
    final pull = await resolvePull(context, repoPath, rebase: true);
    // Push only when the rebase leg COMPLETED (MergeClean). A paused/cancelled
    // rebase (MergeConflicted), a dirty-tree block, or a failure surfaces
    // as-is — the rebased commits aren't ready to publish yet, and the
    // deferred-recovery button (resumeConflicts) owns the eventual push.
    if (pull is! MergeClean) return pull;
    final remote = await trackingRemote(repoPath);
    final push = await pushRemote(repoPath, remote: remote);
    if (!push.ok) return MergeFailed(push.error ?? 'Push failed');
    return MergeClean(SyncData(
        operation: 'sync', remote: remote, output: 'Rebased and pushed.'));
  }
  if (status.ahead > 0) {
    return _wrapPush(
        await pushRemote(repoPath, remote: await trackingRemote(repoPath)));
  }
  if (status.behind > 0) return resolvePull(context, repoPath);
  return _wrapPush(
      await fetchRemote(repoPath, remote: await trackingRemote(repoPath)));
}

MergeOutcome _wrapPush(GitResult<SyncData> r) =>
    r.ok ? MergeClean(r.data!) : MergeFailed(r.error ?? 'failed');

/// Conflict window for a dirty pull, whose markers live in [files] (in
/// memory) rather than as UU entries. The merge editor consumes them
/// directly; the AI path needs them on disk, so it materialises the markers
/// (capturing the user's pristine edits first) and restores them if the AI
/// resolution doesn't land. Either way the working tree ends up resolved or
/// exactly as it was.
Future<bool> _resolveDirtyConflicts(
    BuildContext context, String repoPath, List<ConflictFile> files) async {
  final paths = files.map((f) => f.path).toList();
  final blocks = files.fold<int>(0, (n, f) => n + f.blocks.length);
  final choice = await showConflictWindow(context,
      opLabel: 'pull', paths: paths, blockCount: blocks, canDefer: false);
  if (choice == null || !context.mounted) return false;
  switch (choice.action) {
    case ConflictAction.manual:
      final done = await openConflictEditor(context, repoPath, files);
      if (!done) return false;
      // Post-condition guard, matching the AI branch: the editor's 'done'
      // should mean fully resolved, but the dirty path has no UU in the index
      // for `_hasRemainingConflicts` to re-scan (markers are in-memory). So
      // re-read the files — if any marker slipped through, don't let finalize
      // commit it.
      for (final f in files) {
        final abs = File(_absPath(repoPath, f.path));
        if (await abs.exists() &&
            (await abs.readAsString()).contains('<<<<<<<')) {
          return false;
        }
      }
      return true;
    case ConflictAction.defer:
      return false;
    case ConflictAction.ai:
      // Snapshot BOTH the working tree AND the index before writing markers.
      // resolveConflictsWithAi stages the files its patch applies, so a
      // restore that touched only the working tree would leave a staged /
      // worktree desync — the contract is "exactly as it was", index too.
      final originals = <String, String?>{};
      for (final f in files) {
        final abs = File(_absPath(repoPath, f.path));
        originals[f.path] = await abs.exists() ? await abs.readAsString() : null;
        await abs.writeAsString(f.fullText);
      }
      final indexSnapshot = await snapshotIndexEntries(repoPath, paths);
      if (!context.mounted) {
        await _rollbackDirty(repoPath, originals, indexSnapshot);
        return false;
      }
      await resolveConflictsWithAi(
          context, repoPath, choice.aiCategory ?? 'fast', paths);
      // Resolved only if no markers remain in any of the files.
      var stillConflicted = false;
      for (final f in files) {
        final abs = File(_absPath(repoPath, f.path));
        if (await abs.exists() &&
            (await abs.readAsString()).contains('<<<<<<<')) {
          stillConflicted = true;
          break;
        }
      }
      if (stillConflicted) {
        await _rollbackDirty(repoPath, originals, indexSnapshot);
        return false;
      }
      return true;
  }
}

String _absPath(String repoPath, String path) =>
    '$repoPath/$path'.replaceAll('/', Platform.pathSeparator);

/// Rolls a dirty-pull AI attempt back to the user's pristine state — index
/// first (undo any staging the AI patch did / restore the original staged
/// blob), then the working tree — so neither is left out of sync.
Future<void> _rollbackDirty(String repoPath, Map<String, String?> wt,
    Map<String, String?> index) async {
  await restoreIndexEntries(repoPath, index);
  await _restoreOriginals(repoPath, wt);
}

Future<void> _restoreOriginals(
    String repoPath, Map<String, String?> originals) async {
  for (final entry in originals.entries) {
    final abs = File(_absPath(repoPath, entry.key));
    try {
      if (entry.value == null) {
        if (await abs.exists()) await abs.delete();
      } else {
        await abs.writeAsString(entry.value!);
      }
    } catch (_) {}
  }
}
