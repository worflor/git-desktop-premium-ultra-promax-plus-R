// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// desk_issue_store.dart — read/write DeskIssue through git plumbing
//
// Each desk issue lives at refs/manifold/issues/<id>. Same orphan-
// history pattern as desk PRs (refs/manifold/desks/*) but keyed by
// the integer id rather than a branch name (issues aren't branch-
// scoped). Single id-counter shared between PRs and issues so users
// can write `#42` without ambiguity about which kind it is — fed by
// the existing refs/manifold/_id-counter ref.

import 'dart:async';

import 'package:meta/meta.dart';

import 'desk_issue.dart';
import 'git_result.dart';
import 'manifold_refs.dart';

class DeskIssueStore {
  static const String refPrefix = ManifoldNs.issuesPrefix;
  static const String _issueFilename = 'issue.json';
  static const String _counterFilename = 'counter.txt';

  final ManifoldRefs refs;

  DeskIssueStore(this.refs);

  static LiveManifoldRef refFor(int id) => LiveManifoldRef.issue(id);

  /// List every desk issue under the prefix, newest-updated first.
  @useResult
  Future<GitResult<List<DeskIssue>>> listAll() async {
    final r = await refs.listRefs(refPrefix);
    if (!r.ok) return GitResult.err(r.error ?? 'listRefs failed');
    final out = <DeskIssue>[];
    for (final sha in r.data!.values) {
      final blob = await refs.readRefBlob(sha, _issueFilename);
      if (!blob.ok || blob.data == null) continue;
      try {
        out.add(DeskIssue.fromBlob(blob.data!));
      } catch (_) {
        // Corrupt issue.json — skip rather than fail the whole list.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return GitResult.ok(out);
  }

  @useResult
  Future<GitResult<DeskIssue?>> read(int id) async {
    final ref = refFor(id);
    final blob = await refs.readRefBlob(ref, _issueFilename);
    if (!blob.ok) return GitResult.err(blob.error ?? 'readRefBlob failed');
    if (blob.data == null) return const GitResult.ok(null);
    try {
      return GitResult.ok(DeskIssue.fromBlob(blob.data!));
    } catch (e) {
      return GitResult.err('corrupt issue.json: $e');
    }
  }

  /// Write [issue] as the first commit on a fresh ref. Only the
  /// `create` path uses this: the id was just allocated so the ref
  /// can't already exist, and there is no prior state to transform, so
  /// the CAS-retry loop [_mutate] runs would be pointless here.
  Future<GitResult<void>> _commitNew(DeskIssue issue,
      {required String message}) async {
    final ref = refFor(issue.issueId);
    final blobR = await refs.writeBlob(issue.toBlob());
    if (!blobR.ok) return GitResult.err(blobR.error ?? 'writeBlob failed');
    final treeR = await refs.mkTree({_issueFilename: blobR.data!});
    if (!treeR.ok) return GitResult.err(treeR.error ?? 'mkTree failed');
    // First commit on a fresh orphan history — no parent.
    final commitR = await refs.commitTree(
      treeSha: treeR.data!,
      message: message,
    );
    if (!commitR.ok) {
      return GitResult.err(commitR.error ?? 'commitTree failed');
    }
    // CAS on non-existence (zero-OID) — the same fix as DeskPrStore._commit.
    // Resolving the absent ref to null and passing it to updateRef was an
    // unconditional write that let a raced-in create be silently clobbered
    // with both reporting ok; createRef rejects the late writer instead.
    final updR = await refs.createRef(ref: ref, newSha: commitR.data!);
    if (!updR.ok) return GitResult.err(updR.error ?? 'updateRef failed');
    return const GitResult.ok(null);
  }

  /// Read-transform-commit with CAS retry. Every attempt re-resolves the
  /// ref tip and reads the issue blob AT THAT EXACT TIP (`<sha>:file`),
  /// so [transform] always runs over a self-consistent snapshot; the
  /// three-arg update-ref then CAS-commits against the same tip. When a
  /// concurrent writer landed first, update-ref rejects and we loop:
  /// re-read the winner's fresh state, re-apply [transform], retry. This
  /// is what lets two conflicting comments both survive instead of the
  /// loser's write being dropped. [message] is computed from the
  /// transformed record so subjects that depend on the outcome (link vs
  /// unlink) stay correct. Bounded retries with jittered backoff mirror
  /// [ManifoldRefs.allocSequentialId].
  Future<GitResult<DeskIssue>> _mutate(
    int id, {
    required DeskIssue Function(DeskIssue current) transform,
    required String Function(DeskIssue next) message,
    int maxAttempts = 5,
  }) async {
    final ref = refFor(id);
    var attempt = 0;
    String? lastError;
    while (attempt < maxAttempts) {
      attempt++;
      final tip = await refs.resolveRef(ref);
      if (!tip.ok) return GitResult.err(tip.error ?? 'resolveRef failed');
      if (tip.data == null) return GitResult.err('no desk issue $id');
      // Read the blob at the resolved tip specifically, so the state we
      // transform and the parent we commit onto are the same revision.
      final blob = await refs.readRefBlob(tip.data!, _issueFilename);
      if (!blob.ok) return GitResult.err(blob.error ?? 'readRefBlob failed');
      if (blob.data == null) return GitResult.err('no desk issue $id');
      final DeskIssue current;
      try {
        current = DeskIssue.fromBlob(blob.data!);
      } catch (e) {
        return GitResult.err('corrupt issue.json: $e');
      }
      final next = transform(current);
      final blobR = await refs.writeBlob(next.toBlob());
      if (!blobR.ok) return GitResult.err(blobR.error ?? 'writeBlob failed');
      final treeR = await refs.mkTree({_issueFilename: blobR.data!});
      if (!treeR.ok) return GitResult.err(treeR.error ?? 'mkTree failed');
      final commitR = await refs.commitTree(
        treeSha: treeR.data!,
        parentSha: tip.data,
        message: message(next),
      );
      if (!commitR.ok) {
        return GitResult.err(commitR.error ?? 'commitTree failed');
      }
      final updR = await refs.updateRef(
        ref: ref,
        newSha: commitR.data!,
        oldSha: tip.data,
      );
      if (updR.ok) return GitResult.ok(next);
      lastError = updR.error;
      await Future<void>.delayed(Duration(milliseconds: 5 + (attempt * 5)));
    }
    return GitResult.err(
        lastError ?? 'updateRef failed after $maxAttempts attempts');
  }

  /// Allocate the next sequential id from the shared
  /// [ManifoldNs.idCounter] counter. See [DeskPrStore._allocId] — both
  /// stores delegate to the same plumbing and share the counter so ids
  /// never collide.
  ///
  /// [remote] is threaded in by the caller rather than resolved here: an
  /// operation that also calls [ManifoldRefs.ensureFetchRefspec] (like
  /// [create]) must use the SAME resolved remote for both, or a rename
  /// racing between the two resolutions could point the reservation and
  /// the refspec at different remotes.
  Future<GitResult<int>> _allocId({required MetadataRemote remote}) =>
      refs.allocSequentialId(
        // Shared counter ref with DeskPrStore so PR/issue numbers don't
        // collide. Same allocation logic, same ref.
        ref: ManifoldNs.idCounter,
        filename: _counterFilename,
        remote: remote,
      );

  @useResult
  Future<GitResult<DeskIssue>> create({
    required String title,
    required String body,
    required String authorIdentity,
    List<String> labels = const [],
    List<String> assignees = const [],
    /// Initial state — defaults to OPEN. Pass 'CLOSED' for issues
    /// imported from already-closed remotes (avoids a 2-commit round-trip).
    String state = 'OPEN',
    /// Pre-link to a remote issue number — used by importFromRemote so
    /// the issue is born already-linked, with no window where a concurrent
    /// reader could see an unlinked imported issue.
    int? remoteNumber,
  }) async {
    // Resolved ONCE for this whole operation (not once per call below) so
    // the id reservation and the refspec config land on the same remote
    // even if a rename races between them — see [_allocId]'s doc.
    final remote = await refs.resolveMetadataRemote();
    final idR = await _allocId(remote: remote);
    if (!idR.ok) return GitResult.err(idR.error ?? 'allocId failed');
    final now = DateTime.now();
    final issue = DeskIssue(
      issueId: idR.data!,
      title: title,
      body: body,
      state: state.toUpperCase(),
      authorIdentity: authorIdentity,
      createdAt: now,
      updatedAt: now,
      labels: labels,
      assignees: assignees,
      remoteNumber: remoteNumber,
    );
    final w = await _commitNew(issue, message: 'create issue');
    if (!w.ok) return GitResult.err(w.error ?? 'create commit failed');
    // Configure the manifold fetch refspec on first issue creation, the
    // same as DeskPrStore.create does on first promotion. Without this
    // an issues-only user (who never opens a desk PR) never auto-pulls
    // Manifold metadata on `git fetch` — a silent no-sync trap. No-op
    // when there's no remote configured. The user can also configure it
    // manually (the STAGING form — never the legacy live-ref refspec,
    // which lets a plain fetch force-rewind live refs):
    //   git config --add remote.origin.fetch '+refs/manifold/*:refs/manifold-remote/origin/*'
    await refs.ensureFetchRefspec(remote: remote);
    return GitResult.ok(issue);
  }

  @useResult
  Future<GitResult<DeskIssue>> addComment({
    required int id,
    required String author,
    required String body,
  }) async {
    // The comment is expressed as a transform over the freshly-read
    // record, so a concurrent commenter who wins the CAS race doesn't
    // erase this comment — we re-read their state and append onto it.
    return _mutate(
      id,
      transform: (current) => current.copyWith(
        comments: [
          ...current.comments,
          DeskIssueComment(author: author, body: body, at: DateTime.now()),
        ],
        updatedAt: DateTime.now(),
      ),
      message: (_) => 'comment by $author',
    );
  }

  @useResult
  Future<GitResult<DeskIssue>> setState({
    required int id,
    required String state,
  }) async {
    return _mutate(
      id,
      transform: (current) => current.copyWith(
        state: state.toUpperCase(),
        updatedAt: DateTime.now(),
      ),
      message: (_) => 'state -> ${state.toLowerCase()}',
    );
  }

  @useResult
  Future<GitResult<DeskIssue>> editMeta({
    required int id,
    String? title,
    String? body,
    List<String>? labels,
  }) async {
    return _mutate(
      id,
      transform: (current) => current.copyWith(
        title: title,
        body: body,
        labels: labels,
        updatedAt: DateTime.now(),
      ),
      message: (_) => 'edit issue meta',
    );
  }

  /// Toggle a desk-PR branch in this issue's `addressedBy` list.
  /// Used to maintain the symmetric cross-reference with desk PRs'
  /// `linkedIssues` field.
  @useResult
  Future<GitResult<DeskIssue>> toggleAddressedBy({
    required int id,
    required String branch,
  }) async {
    return _mutate(
      id,
      transform: (current) {
        final addressed = [...current.addressedBy];
        if (addressed.contains(branch)) {
          addressed.remove(branch);
        } else {
          addressed.add(branch);
        }
        return current.copyWith(
          addressedBy: addressed,
          updatedAt: DateTime.now(),
        );
      },
      // Subject derived from the transformed record so it stays truthful
      // even after a retry re-applied the toggle onto fresh state.
      message: (next) =>
          next.addressedBy.contains(branch) ? 'link desk $branch' : 'unlink desk $branch',
    );
  }

  @useResult
  Future<GitResult<void>> abandon(int id) async {
    return refs.deleteRef(refFor(id));
  }

  /// Set (or clear) the remote issue number this local issue is linked to.
  /// Calling with null unlinks the remote association.
  @useResult
  Future<GitResult<DeskIssue>> setRemoteNumber(
    int id,
    int? remoteNumber,
  ) async {
    return _mutate(
      id,
      transform: (current) => current.copyWith(
        remoteNumber: remoteNumber,
        updatedAt: DateTime.now(),
      ),
      message: (_) => remoteNumber != null
          ? 'link remote #$remoteNumber'
          : 'unlink remote',
    );
  }

  /// Overwrite local metadata from freshly-fetched remote values.
  /// Preserves: issueId, authorIdentity, createdAt, addressedBy, comments,
  /// remoteNumber (keeps existing link). Everything else comes from remote.
  /// `updatedAt` is set to [DateTime.now()] — it tracks when this LOCAL copy
  /// was last touched, which is what `listAll()` uses for sort order.
  /// Using the remote's timestamp would make recently-synced issues sort
  /// to the bottom whenever the remote was older than local activity.
  @useResult
  Future<GitResult<DeskIssue>> applyRemoteSnapshot({
    required int id,
    required String title,
    required String body,
    required String state,
    required List<String> labels,
    required List<String> assignees,
  }) async {
    return _mutate(
      id,
      transform: (current) => current.copyWith(
        title: title,
        body: body,
        state: state,
        labels: labels,
        assignees: assignees,
        updatedAt: DateTime.now(),
      ),
      message: (_) => 'sync from remote',
    );
  }

  /// Share local issues over [remote]: fetch peers' Manifold refs into
  /// staging, reconcile them into the live refs WITHOUT dropping any
  /// unpushed local mutation, then push back with per-ref
  /// force-with-lease. All the data-loss-safe logic lives in
  /// [ManifoldRefs.syncWithRemote]; it operates over the whole
  /// `refs/manifold/*` namespace, so an issues sync also carries desks and
  /// the shared counter (and vice-versa) in one round-trip. Also ensures
  /// (and migrates) the persistent staging fetch refspec so ordinary
  /// `git fetch` stays safe afterwards.
  ///
  /// [remote] defaults to null — resolved ONCE here (rather than a
  /// hardcoded 'origin', and rather than letting [ensureFetchRefspec] and
  /// [ManifoldRefs.syncWithRemote] each resolve it independently) so both
  /// calls in this one operation agree even if a remote rename races
  /// between them.
  @useResult
  Future<GitResult<void>> syncWithRemote({MetadataRemote? remote}) async {
    final resolvedRemote = remote ?? await refs.resolveMetadataRemote();
    await refs.ensureFetchRefspec(remote: resolvedRemote);
    return refs.syncWithRemote(remote: resolvedRemote);
  }
}
