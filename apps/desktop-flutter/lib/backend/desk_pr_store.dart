// desk_pr_store.dart — read/write DeskPr through git plumbing
//
// Each desk PR lives at refs/manifold/desks/<encoded-branch>. The ref
// points to a commit history; the latest commit's tree contains a
// single meta.json blob with the full current state.
//
// Sequential desk-IDs allocated via refs/manifold/_id-counter
// (single-blob tree containing `counter.txt`). One commit per
// allocation, CAS-protected so concurrent allocations on the same
// machine don't collide.
//
// All mutations are CAS via update-ref's three-arg form: `update-ref
// <ref> <new> <old>` rejects when the ref has moved since we read
// it. Caller retries on failure (refresh from disk, re-apply mutation).

import 'dart:async';
import 'dart:convert';

import 'desk_pr.dart';
import 'git_result.dart';
import 'manifold_refs.dart';

class DeskPrStore {
  static const String refPrefix = 'refs/manifold/desks/';
  static const String _metaFilename = 'meta.json';
  static const String _idCounterRef = 'refs/manifold/_id-counter';
  static const String _counterFilename = 'counter.txt';

  final ManifoldRefs refs;

  DeskPrStore(this.refs);

  /// Ref name for a desk PR keyed by its head branch.
  static String refFor(String branch) =>
      '$refPrefix${encodeBranch(branch)}';

  /// Bijective branch encoding for ref names. The naive approach (drop
  /// or substitute each illegal character) collides — `feat/~x` and
  /// `feat-x` would both encode to `feat-x` and silently overwrite
  /// each other. Percent-encoding is reversible: every illegal char
  /// becomes `%XX` and `%` itself is escaped first so the encoding is
  /// injective.
  /// Slash is preserved — multi-segment refs are valid and we want
  /// `feat/x` to render as `refs/manifold/desks/feat/x`, not flattened.
  /// Trailing `.`, leading `/`, and `..` sequences are rejected by git
  /// itself; we encode `.` only when it would create those, and reject
  /// empty input outright.
  static String encodeBranch(String branch) {
    final src = branch.trim();
    if (src.isEmpty) return '_empty';
    final buf = StringBuffer();
    for (var i = 0; i < src.length; i++) {
      final c = src[i];
      // Escape `%` first so the encoding is reversible.
      if (c == '%') {
        buf.write('%25');
        continue;
      }
      // Slash is kept literal — multi-segment refs are valid git refs.
      if (c == '/') {
        buf.write('/');
        continue;
      }
      // Letters, digits, `-`, `_` pass through untouched.
      final code = c.codeUnitAt(0);
      final isLetter =
          (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
      final isDigit = code >= 0x30 && code <= 0x39;
      if (isLetter || isDigit || c == '-' || c == '_') {
        buf.write(c);
        continue;
      }
      // Everything else (including `.`, `~`, `^`, `:`, `?`, `*`, `[`,
      // backslash, whitespace, unicode) → %XX. UTF-8-encode then hex
      // each byte so non-ASCII branch names roundtrip cleanly.
      final bytes = utf8.encode(c);
      for (final b in bytes) {
        buf.write('%');
        buf.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
    }
    var encoded = buf.toString();
    // Normalize edge sequences git rejects in refnames.
    while (encoded.startsWith('/')) {
      encoded = encoded.substring(1);
    }
    while (encoded.endsWith('/')) {
      encoded = encoded.substring(0, encoded.length - 1);
    }
    return encoded;
  }

  /// Inverse of [encodeBranch] — restores the original branch name
  /// from an encoded ref tail. Used by [listAll] so the rendered list
  /// shows the user's actual branch names, not the ref-encoded forms.
  static String decodeBranch(String encoded) {
    final buf = StringBuffer();
    var i = 0;
    while (i < encoded.length) {
      final c = encoded[i];
      if (c == '%' && i + 2 < encoded.length) {
        final hex = encoded.substring(i + 1, i + 3);
        final byte = int.tryParse(hex, radix: 16);
        if (byte != null) {
          // Collect a contiguous run of percent-escaped bytes so multi-
          // byte UTF-8 sequences decode as one character.
          final bytes = <int>[byte];
          var j = i + 3;
          while (j + 2 < encoded.length && encoded[j] == '%') {
            final h = encoded.substring(j + 1, j + 3);
            final b = int.tryParse(h, radix: 16);
            if (b == null) break;
            bytes.add(b);
            j += 3;
          }
          buf.write(utf8.decode(bytes, allowMalformed: true));
          i = j;
          continue;
        }
      }
      buf.write(c);
      i++;
    }
    return buf.toString();
  }

  /// List every desk PR under the prefix, newest-updated first.
  Future<GitResult<List<DeskPr>>> listAll() async {
    final r = await refs.listRefs(refPrefix);
    if (!r.ok) return GitResult.err(r.error ?? 'listRefs failed');
    final out = <DeskPr>[];
    for (final ref in r.data!.keys) {
      final blob = await refs.readRefBlob(ref, _metaFilename);
      if (!blob.ok || blob.data == null) continue;
      try {
        out.add(DeskPr.fromBlob(blob.data!));
      } catch (_) {
        // Corrupt meta.json on this ref — skip rather than fail the
        // whole list. The orphan history is still inspectable via git
        // for forensic purposes.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return GitResult.ok(out);
  }

  /// Read a single PR by its branch name.
  Future<GitResult<DeskPr?>> read(String branch) async {
    final ref = refFor(branch);
    final blob = await refs.readRefBlob(ref, _metaFilename);
    if (!blob.ok) return GitResult.err(blob.error ?? 'readRefBlob failed');
    if (blob.data == null) return const GitResult.ok(null);
    try {
      return GitResult.ok(DeskPr.fromBlob(blob.data!));
    } catch (e) {
      return GitResult.err('corrupt meta.json: $e');
    }
  }

  /// Internal: write [pr] as a new commit on its ref. [message]
  /// becomes the commit subject (the audit-trail entry).
  Future<GitResult<void>> _commit(DeskPr pr, {required String message}) async {
    final ref = refFor(pr.headRef);
    final blobR = await refs.writeBlob(pr.toBlob());
    if (!blobR.ok) return GitResult.err(blobR.error ?? 'writeBlob failed');
    final treeR = await refs.mkTree({_metaFilename: blobR.data!});
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

  /// Allocate the next sequential desk-id from the shared
  /// [_idCounterRef] counter. CAS-protected — concurrent allocations
  /// on the same machine see an update-ref conflict on the loser and
  /// the caller can retry. PR-ids and issue-ids share the counter so
  /// they never collide.
  Future<GitResult<int>> _allocId() => refs.allocSequentialId(
        ref: _idCounterRef,
        filename: _counterFilename,
        commitLabel: 'desk-id',
      );

  /// Promote a branch to a desk PR. Refuses if the branch already has
  /// one (caller should check first via [read]).
  /// On first promotion in a repo, also configures the manifold fetch
  /// refspec on the active remote so `git fetch origin` auto-pulls
  /// manifold metadata. Without this, a clone-and-recover loses every
  /// desk PR's metadata silently — a real data-loss vector.
  Future<GitResult<DeskPr>> create({
    required String branch,
    required String title,
    required String body,
    required String baseRef,
    required String authorIdentity,
    bool isDraft = true,
  }) async {
    final existing = await read(branch);
    if (existing.ok && existing.data != null) {
      return GitResult.err('a desk PR already exists for $branch');
    }
    final idR = await _allocId();
    if (!idR.ok) return GitResult.err(idR.error ?? 'allocId failed');
    final now = DateTime.now();
    // Probe mergeability against the configured base. UNKNOWN when the
    // base is unreachable — this is honest signal, not a lie.
    final mergeable = await refs.probeMergeable(baseRef, branch);
    final pr = DeskPr(
      deskId: idR.data!,
      title: title,
      body: body,
      headRef: branch,
      baseRef: baseRef,
      state: 'OPEN',
      isDraft: isDraft,
      authorIdentity: authorIdentity,
      createdAt: now,
      updatedAt: now,
      mergeable: mergeable,
    );
    final w = await _commit(pr, message: 'create pr');
    if (!w.ok) return GitResult.err(w.error ?? 'create commit failed');
    // Sync wiring — awaited so we know it completed (cheap, single
    // git-config call when origin exists; no-op when it doesn't). The
    // user can also configure this manually:
    //   git config --add remote.origin.fetch +refs/manifold/*:refs/manifold/*
    await _ensureFetchRefspec();
    return GitResult.ok(pr);
  }

  /// Add `+refs/manifold/*:refs/manifold/*` to `origin`'s fetch
  /// refspec when origin exists and the refspec isn't already there.
  /// Idempotent and safe: respects existing user refspecs; skips
  /// silently when no `origin` is configured (a brand-new repo or a
  /// test fixture is a valid state). Awaits the underlying git
  /// config call so callers (typically `create()`) finish their
  /// promotion deterministically.
  Future<void> _ensureFetchRefspec() async {
    const refspec = '+refs/manifold/*:refs/manifold/*';
    // Skip when there's no `origin` to attach to. Without this guard,
    // `git config --add` would still succeed (writing the key with no
    // matching remote section) but the resulting config is misleading
    // and the fire-and-forget would race with test teardown.
    final originUrl = await refs.readConfig('remote.origin.url');
    if (originUrl == null) return;
    await refs.addConfigOnce('remote.origin.fetch', refspec);
  }

  Future<GitResult<DeskPr>> addComment({
    required String branch,
    required String author,
    required String body,
  }) async {
    final cur = await read(branch);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return GitResult.err('no desk PR for $branch');
    final next = cur.data!.copyWith(
      thread: [
        ...cur.data!.thread,
        DeskThreadEntry(author: author, body: body, at: DateTime.now()),
      ],
      updatedAt: DateTime.now(),
    );
    final w = await _commit(next, message: 'comment by $author');
    if (!w.ok) return GitResult.err(w.error ?? 'addComment commit failed');
    return GitResult.ok(next);
  }

  Future<GitResult<DeskPr>> addReview({
    required String branch,
    required String author,
    required String verdict,
    required String body,
  }) async {
    final cur = await read(branch);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return GitResult.err('no desk PR for $branch');
    final next = cur.data!.copyWith(
      thread: [
        ...cur.data!.thread,
        DeskThreadEntry(
          author: author,
          body: body,
          at: DateTime.now(),
          verdict: verdict.toUpperCase(),
        ),
      ],
      updatedAt: DateTime.now(),
    );
    final w = await _commit(next,
        message: '${verdict.toLowerCase()} by $author');
    if (!w.ok) return GitResult.err(w.error ?? 'addReview commit failed');
    return GitResult.ok(next);
  }

  /// Mutate state ('OPEN' / 'MERGED' / 'CLOSED'). The actual git
  /// merge/close is the caller's responsibility — this method only
  /// records the metadata transition.
  Future<GitResult<DeskPr>> setState({
    required String branch,
    required String state,
  }) async {
    final cur = await read(branch);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return GitResult.err('no desk PR for $branch');
    final next = cur.data!.copyWith(
      state: state.toUpperCase(),
      updatedAt: DateTime.now(),
    );
    final w = await _commit(next, message: 'state -> ${state.toLowerCase()}');
    if (!w.ok) return GitResult.err(w.error ?? 'setState commit failed');
    return GitResult.ok(next);
  }

  Future<GitResult<DeskPr>> editMeta({
    required String branch,
    String? title,
    String? body,
    bool? isDraft,
    List<String>? labels,
  }) async {
    final cur = await read(branch);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return GitResult.err('no desk PR for $branch');
    final next = cur.data!.copyWith(
      title: title,
      body: body,
      isDraft: isDraft,
      labels: labels,
      updatedAt: DateTime.now(),
    );
    final w = await _commit(next, message: 'edit pr meta');
    if (!w.ok) return GitResult.err(w.error ?? 'editMeta commit failed');
    return GitResult.ok(next);
  }

  /// Refresh the persisted diff metrics + mergeable flag for [branch]
  /// from the supplied [files] list and a fresh probe. Called after
  /// the local-diff fetch resolves so the row's metric line and
  /// conflict strip reflect reality without waiting for the next
  /// promotion-style mutation. Quiet — does not write a commit if the
  /// values are unchanged (no audit-trail noise on every refresh).
  Future<GitResult<DeskPr?>> refreshDiffStats({
    required String branch,
    required int additions,
    required int deletions,
    required int changedFiles,
  }) async {
    final cur = await read(branch);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return const GitResult.ok(null);
    final mergeable = await refs.probeMergeable(cur.data!.baseRef, branch);
    final unchanged = cur.data!.additions == additions &&
        cur.data!.deletions == deletions &&
        cur.data!.changedFiles == changedFiles &&
        cur.data!.mergeable == mergeable;
    if (unchanged) return GitResult.ok(cur.data);
    final next = cur.data!.copyWith(
      additions: additions,
      deletions: deletions,
      changedFiles: changedFiles,
      mergeable: mergeable,
      // Don't bump updatedAt — diff stats aren't user activity.
    );
    final w = await _commit(next, message: 'refresh diff stats');
    if (!w.ok) return GitResult.err(w.error ?? 'refresh commit failed');
    return GitResult.ok(next);
  }

  /// Drop the metadata ref entirely. Orphan history becomes
  /// unreachable and will be pruned by `git gc`.
  Future<GitResult<void>> abandon(String branch) async {
    return refs.deleteRef(refFor(branch));
  }

  /// Toggle an issue's presence in this PR's linked-issues list. The
  /// caller distinguishes [isRemote] so the link lands in the
  /// appropriate list — [DeskPr.linkedIssues] for local issues,
  /// [DeskPr.linkedRemoteIssues] for forge-hosted issues. Symmetric
  /// `addressedBy` write on a local issue is the caller's
  /// responsibility (DeskIssueStore.toggleAddressedBy).
  Future<GitResult<DeskPr>> toggleLinkedIssue({
    required String branch,
    required int issueId,
    required bool isRemote,
  }) async {
    final cur = await read(branch);
    if (!cur.ok) return GitResult.err(cur.error ?? 'read failed');
    if (cur.data == null) return GitResult.err('no desk PR for $branch');
    final list = isRemote ? cur.data!.linkedRemoteIssues : cur.data!.linkedIssues;
    final next = [...list];
    final added = !next.contains(issueId);
    if (added) {
      next.add(issueId);
    } else {
      next.remove(issueId);
    }
    final updated = isRemote
        ? cur.data!.copyWith(
            linkedRemoteIssues: next,
            updatedAt: DateTime.now(),
          )
        : cur.data!.copyWith(
            linkedIssues: next,
            updatedAt: DateTime.now(),
          );
    final w = await _commit(updated,
        message: added
            ? 'link ${isRemote ? 'remote ' : ''}issue #$issueId'
            : 'unlink ${isRemote ? 'remote ' : ''}issue #$issueId');
    if (!w.ok) {
      return GitResult.err(w.error ?? 'toggleLinkedIssue commit failed');
    }
    return GitResult.ok(updated);
  }
}
