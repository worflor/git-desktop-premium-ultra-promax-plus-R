// ═════════════════════════════════════════════════════════════════════════
// desk_issue_store.dart — read/write DeskIssue through git plumbing
//
// Each desk issue lives at refs/manifold/issues/<id>. Same orphan-
// history pattern as desk PRs (refs/manifold/desks/*) but keyed by
// the integer id rather than a branch name (issues aren't branch-
// scoped). Single id-counter shared between PRs and issues so users
// can write `#42` without ambiguity about which kind it is — fed by
// the existing refs/manifold/_id-counter ref.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'desk_issue.dart';
import 'git_result.dart';
import 'manifold_refs.dart';

class DeskIssueStore {
  static const String refPrefix = 'refs/manifold/issues/';
  static const String _issueFilename = 'issue.json';
  // Shared counter ref with DeskPrStore so PR/issue numbers don't
  // collide. Same allocation logic, same ref name.
  static const String _idCounterRef = 'refs/manifold/_id-counter';
  static const String _counterFilename = 'counter.txt';

  final ManifoldRefs refs;

  DeskIssueStore(this.refs);

  static String refFor(int id) => '$refPrefix$id';

  /// List every desk issue under the prefix, newest-updated first.
  Future<GitResult<List<DeskIssue>>> listAll() async {
    final r = await refs.listRefs(refPrefix);
    if (!r.ok) return GitResult.err(r.error ?? 'listRefs failed');
    final out = <DeskIssue>[];
    for (final ref in r.data!.keys) {
      final blob = await refs.readRefBlob(ref, _issueFilename);
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

  Future<GitResult<void>> _commit(DeskIssue issue,
      {required String message}) async {
    final ref = refFor(issue.issueId);
    final blobR = await refs.writeBlob(issue.toBlob());
    if (!blobR.ok) return GitResult.err(blobR.error ?? 'writeBlob failed');
    final treeR = await refs.mkTree({_issueFilename: blobR.data!});
    if (!treeR.ok) return GitResult.err(treeR.error ?? 'mkTree failed');
    final cur = await refs.resolveRef(ref);
    if (!cur.ok) return GitResult.err(cur.error ?? 'resolveRef failed');
    final commitR = await refs.commitTree(
      treeSha: treeR.data!,
      parentSha: cur.data,
      message: message,
    );
    if (!commitR.ok) {
      return GitResult.err(commitR.error ?? 'commitTree failed');
    }
    final updR = await refs.updateRef(
      ref: ref,
      newSha: commitR.data!,
      oldSha: cur.data,
    );
    if (!updR.ok) return GitResult.err(updR.error ?? 'updateRef failed');
    return const GitResult.ok(null);
  }

  /// Allocate the next sequential id from the shared [_idCounterRef]
  /// counter. See [DeskPrStore._allocId] — both stores delegate to the
  /// same plumbing and share the counter so ids never collide.
  Future<GitResult<int>> _allocId() => refs.allocSequentialId(
        ref: _idCounterRef,
        filename: _counterFilename,
      );

  Future<GitResult<DeskIssue>> create({
    required String title,
    required String body,
    required String authorIdentity,
    List<String> labels = const [],
  }) async {
    final idR = await _allocId();
    if (!idR.ok) return GitResult.err(idR.error ?? 'allocId failed');
    final now = DateTime.now();
    final issue = DeskIssue(
      issueId: idR.data!,
      title: title,
      body: body,
      state: 'OPEN',
      authorIdentity: authorIdentity,
      createdAt: now,
      updatedAt: now,
      labels: labels,
    );
    final w = await _commit(issue, message: 'create issue');
    if (!w.ok) return GitResult.err(w.error ?? 'create commit failed');
    return GitResult.ok(issue);
  }

  Future<GitResult<DeskIssue>> addComment({
    required int id,
    required String author,
    required String body,
  }) async {
    final cur = await read(id);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return GitResult.err('no desk issue $id');
    final next = cur.data!.copyWith(
      comments: [
        ...cur.data!.comments,
        DeskIssueComment(author: author, body: body, at: DateTime.now()),
      ],
      updatedAt: DateTime.now(),
    );
    final w = await _commit(next, message: 'comment by $author');
    if (!w.ok) return GitResult.err(w.error ?? 'addComment commit failed');
    return GitResult.ok(next);
  }

  Future<GitResult<DeskIssue>> setState({
    required int id,
    required String state,
  }) async {
    final cur = await read(id);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return GitResult.err('no desk issue $id');
    final next = cur.data!.copyWith(
      state: state.toUpperCase(),
      updatedAt: DateTime.now(),
    );
    final w = await _commit(next, message: 'state -> ${state.toLowerCase()}');
    if (!w.ok) return GitResult.err(w.error ?? 'setState commit failed');
    return GitResult.ok(next);
  }

  Future<GitResult<DeskIssue>> editMeta({
    required int id,
    String? title,
    String? body,
    List<String>? labels,
  }) async {
    final cur = await read(id);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return GitResult.err('no desk issue $id');
    final next = cur.data!.copyWith(
      title: title,
      body: body,
      labels: labels,
      updatedAt: DateTime.now(),
    );
    final w = await _commit(next, message: 'edit issue meta');
    if (!w.ok) return GitResult.err(w.error ?? 'editMeta commit failed');
    return GitResult.ok(next);
  }

  /// Toggle a desk-PR branch in this issue's `addressedBy` list.
  /// Used to maintain the symmetric cross-reference with desk PRs'
  /// `linkedIssues` field.
  Future<GitResult<DeskIssue>> toggleAddressedBy({
    required int id,
    required String branch,
  }) async {
    final cur = await read(id);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return GitResult.err('no desk issue $id');
    final addressed = [...cur.data!.addressedBy];
    if (addressed.contains(branch)) {
      addressed.remove(branch);
    } else {
      addressed.add(branch);
    }
    final next = cur.data!.copyWith(
      addressedBy: addressed,
      updatedAt: DateTime.now(),
    );
    final w = await _commit(next,
        message: addressed.contains(branch)
            ? 'link desk $branch'
            : 'unlink desk $branch');
    if (!w.ok) return GitResult.err(w.error ?? 'toggleAddressedBy failed');
    return GitResult.ok(next);
  }

  Future<GitResult<void>> abandon(int id) async {
    return refs.deleteRef(refFor(id));
  }
}
