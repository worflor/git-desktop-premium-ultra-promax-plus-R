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
import 'utf8_exact.dart';

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

  /// Injective encoding of any non-empty Dart string into a legal git
  /// ref tail under `refs/manifold/desks/`.
  ///
  /// Laws:
  ///  * Injective over all non-empty strings —
  ///    `decodeBranch(encodeBranch(s)) == s` for every non-empty `s`, no
  ///    carve-outs. No trim, no normalization: leading/trailing
  ///    whitespace (including a BOM) is payload and survives like any
  ///    other character.
  ///
  /// This is byte-identical to the pre-redesign scheme for every tail
  /// the old encoder could actually store (its trims/strips and lossy
  /// astral collapses are all fixed points of decode-then-re-encode), so
  /// existing `refs/manifold/desks/*` refs need no migration.
  ///  * Iterates by RUNE (`src.runes`), not UTF-16 code unit, so a
  ///    surrogate pair (astral character — most emoji) is one unit and
  ///    UTF-8-encodes to its real bytes instead of shredding into two
  ///    lone-surrogate replacement characters.
  ///  * `%` always escapes first (`%25`) so the percent-encoding itself
  ///    stays reversible.
  ///  * Letters, digits, `-`, `_` pass through literally.
  ///  * Empty input throws [ArgumentError]: git itself rejects an empty
  ///    branch name, so no caller can legitimately produce one — failing
  ///    loudly beats inventing a sentinel tail (a sentinel would need a
  ///    leading-`_` escape to stay unforgeable, which would change the
  ///    encoding of every real `_`-prefixed branch for nothing).
  ///  * `/` passes through literally only when it is not the first rune,
  ///    not the last rune, and the immediately preceding source rune is
  ///    not itself `/` — otherwise it's escaped to `%2F`. This makes
  ///    leading slash, trailing slash, and doubled-slash (empty ref
  ///    components — the exact shapes git's own `check-ref-format`
  ///    rejects) unrepresentable rather than merely discouraged.
  ///  * `.` is always encoded (falls through to the general case below),
  ///    so `..`, a leading `.`, ` .lock`, or a trailing `.` — all
  ///    git-illegal ref-name shapes — can never appear literally.
  ///  * Everything else: UTF-8-encode the single rune and emit uppercase
  ///    `%XX` per byte.
  static String encodeBranch(String branch) {
    if (branch.isEmpty) {
      throw ArgumentError.value(
          branch, 'branch', 'branch name must be non-empty');
    }
    final buf = StringBuffer();
    final runes = branch.runes.toList(growable: false);
    int? prevRune;
    for (var idx = 0; idx < runes.length; idx++) {
      final rune = runes[idx];
      final c = String.fromCharCode(rune);
      // Escape `%` first so the encoding is reversible.
      if (c == '%') {
        buf.write('%25');
        prevRune = rune;
        continue;
      }
      // Letters, digits, `-`, `_` pass through untouched.
      final isLetter =
          (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);
      final isDigit = rune >= 0x30 && rune <= 0x39;
      if (isLetter || isDigit || c == '-' || c == '_') {
        buf.write(c);
        prevRune = rune;
        continue;
      }
      // Slash is kept literal only when it can't produce an empty ref
      // component: not first, not last, and not immediately following
      // another slash in the SOURCE.
      if (c == '/') {
        final isFirst = idx == 0;
        final isLast = idx == runes.length - 1;
        final afterSlash = prevRune == 0x2F;
        if (!isFirst && !isLast && !afterSlash) {
          buf.write('/');
        } else {
          buf.write('%2F');
        }
        prevRune = rune;
        continue;
      }
      // Everything else (including `.`, `~`, `^`, `:`, `?`, `*`, `[`,
      // backslash, whitespace/BOM, unicode) → %XX. UTF-8-encode the
      // single rune then hex each byte, so astral characters (one rune,
      // encoded as their real multi-byte UTF-8 sequence) roundtrip
      // cleanly instead of shredding through UTF-16 code units.
      final bytes = utf8.encode(c);
      for (final b in bytes) {
        buf.write('%');
        buf.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
      prevRune = rune;
    }
    return buf.toString();
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
          // utf8DecodeExact (not plain utf8.decode) so a byte run that IS
          // a BOM (EF BB BF) round-trips instead of being silently
          // stripped — a mid-string BOM is payload, not noise.
          buf.write(utf8DecodeExact(bytes, allowMalformed: true));
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

  /// Internal: write [pr] as the FIRST commit on a fresh ref with a
  /// single no-retry CAS. Only the `create` path uses this — the ref
  /// can't already exist (create pre-checks via [read]), so there is no
  /// prior state to preserve and nothing to retry.
  ///
  /// Deliberately NOT a retry loop. The old version built blob+tree ONCE
  /// outside a CAS-retry loop, so a retry after losing a race committed
  /// the STALE full record on top of the winner and erased the winner's
  /// change (verified data loss). Read-modify-write callers now go
  /// through [_mutate], which re-reads and re-applies per attempt; the
  /// create path, having no prior state, needs no retry at all. If the
  /// CAS is lost here (a genuine create-vs-create race), we surface the
  /// error rather than clobbering the other create.
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

  /// Read-transform-commit with CAS retry. Every attempt re-resolves the
  /// ref tip and reads meta.json AT THAT EXACT TIP (`<sha>:meta.json`),
  /// so [transform] runs over a self-consistent snapshot and the
  /// three-arg update-ref CAS-commits against the same revision. On a
  /// lost race update-ref rejects and we loop — re-reading the winner's
  /// state and re-applying [transform] — so two conflicting comments (or
  /// a comment racing a state change) both survive instead of the loser
  /// being dropped. [transform] may be async: [refreshDiffStats] probes
  /// mergeability inside it against the freshly-read baseRef. [message]
  /// is computed from the transformed record so outcome-dependent
  /// subjects (link vs unlink) stay honest across retries.
  Future<GitResult<DeskPr>> _mutate(
    String branch, {
    required FutureOr<DeskPr> Function(DeskPr current) transform,
    required String Function(DeskPr next) message,
    int maxAttempts = 5,
  }) async {
    final ref = refFor(branch);
    var attempt = 0;
    String? lastError;
    while (attempt < maxAttempts) {
      attempt++;
      final tip = await refs.resolveRef(ref);
      if (!tip.ok) return GitResult.err(tip.error ?? 'resolveRef failed');
      if (tip.data == null) return GitResult.err('no desk PR for $branch');
      final blob = await refs.readRefBlob(tip.data!, _metaFilename);
      if (!blob.ok) return GitResult.err(blob.error ?? 'readRefBlob failed');
      if (blob.data == null) return GitResult.err('no desk PR for $branch');
      final DeskPr current;
      try {
        current = DeskPr.fromBlob(blob.data!);
      } catch (e) {
        return GitResult.err('corrupt meta.json: $e');
      }
      final next = await transform(current);
      final blobR = await refs.writeBlob(next.toBlob());
      if (!blobR.ok) return GitResult.err(blobR.error ?? 'writeBlob failed');
      final treeR = await refs.mkTree({_metaFilename: blobR.data!});
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

  /// Allocate the next sequential desk-id from the shared
  /// [_idCounterRef] counter. CAS-protected — concurrent allocations
  /// on the same machine see an update-ref conflict on the loser and
  /// the caller can retry. PR-ids and issue-ids share the counter so
  /// they never collide.
  ///
  /// [remote] is threaded in by the caller rather than resolved here: an
  /// operation that also calls [ManifoldRefs.ensureFetchRefspec] (like
  /// [create]) must use the SAME resolved remote for both, or a rename
  /// racing between the two resolutions could point the reservation and
  /// the refspec at different remotes.
  Future<GitResult<int>> _allocId({required String remote}) =>
      refs.allocSequentialId(
        ref: _idCounterRef,
        filename: _counterFilename,
        commitLabel: 'desk-id',
        remote: remote,
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
    // Resolved ONCE for this whole operation (not once per call below) so
    // the id reservation and the refspec config land on the same remote
    // even if a rename races between them — see [_allocId]'s doc.
    final remote = await refs.resolveMetadataRemote();
    final idR = await _allocId(remote: remote);
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
    // git-config call when the remote exists; no-op when it doesn't). The
    // user can also configure this manually:
    //   git config --add remote.origin.fetch +refs/manifold/*:refs/manifold/*
    await refs.ensureFetchRefspec(remote: remote);
    return GitResult.ok(pr);
  }

  Future<GitResult<DeskPr>> addComment({
    required String branch,
    required String author,
    required String body,
  }) async {
    // Append as a transform over the freshly-read thread so a concurrent
    // comment or review that wins the CAS isn't overwritten — we re-read
    // and append onto the winner's thread.
    return _mutate(
      branch,
      transform: (current) => current.copyWith(
        thread: [
          ...current.thread,
          DeskThreadEntry(author: author, body: body, at: DateTime.now()),
        ],
        updatedAt: DateTime.now(),
      ),
      message: (_) => 'comment by $author',
    );
  }

  Future<GitResult<DeskPr>> addReview({
    required String branch,
    required String author,
    required String verdict,
    required String body,
  }) async {
    return _mutate(
      branch,
      transform: (current) => current.copyWith(
        thread: [
          ...current.thread,
          DeskThreadEntry(
            author: author,
            body: body,
            at: DateTime.now(),
            verdict: verdict.toUpperCase(),
          ),
        ],
        updatedAt: DateTime.now(),
      ),
      message: (_) => '${verdict.toLowerCase()} by $author',
    );
  }

  /// Mutate state ('OPEN' / 'MERGED' / 'CLOSED'). The actual git
  /// merge/close is the caller's responsibility — this method only
  /// records the metadata transition.
  Future<GitResult<DeskPr>> setState({
    required String branch,
    required String state,
  }) async {
    return _mutate(
      branch,
      transform: (current) => current.copyWith(
        state: state.toUpperCase(),
        updatedAt: DateTime.now(),
      ),
      message: (_) => 'state -> ${state.toLowerCase()}',
    );
  }

  Future<GitResult<DeskPr>> editMeta({
    required String branch,
    String? title,
    String? body,
    bool? isDraft,
    List<String>? labels,
  }) async {
    return _mutate(
      branch,
      transform: (current) => current.copyWith(
        title: title,
        body: body,
        isDraft: isDraft,
        labels: labels,
        updatedAt: DateTime.now(),
      ),
      message: (_) => 'edit pr meta',
    );
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
    // Quiet — skip the commit entirely when nothing moved, so a refresh
    // doesn't spam the audit history with identical-value commits.
    if (unchanged) return GitResult.ok(cur.data);
    // Re-probe inside the transform so a retry against a concurrently
    // updated tip reflects that tip's baseRef, not the stale snapshot.
    final r = await _mutate(
      branch,
      transform: (current) async {
        final m = await refs.probeMergeable(current.baseRef, branch);
        return current.copyWith(
          additions: additions,
          deletions: deletions,
          changedFiles: changedFiles,
          mergeable: m,
          // Don't bump updatedAt — diff stats aren't user activity.
        );
      },
      message: (_) => 'refresh diff stats',
    );
    if (!r.ok) return GitResult.err(r.error ?? 'refresh commit failed');
    return GitResult.ok(r.data);
  }

  Future<GitResult<DeskPr>> setRemoteNumber(
      String branch, int remoteNumber) async {
    return _mutate(
      branch,
      transform: (current) => current.copyWith(remoteNumber: remoteNumber),
      message: (_) => 'link remote #$remoteNumber',
    );
  }

  /// Overwrite the remote-authoritative fields of an existing desk PR from
  /// freshly-fetched values in [pr], WITHOUT clobbering locally-accruing
  /// state. Routed through [_mutate] so every attempt re-reads the current
  /// tip and applies the remote fields onto THAT record: the local thread
  /// (comments/reviews), local issue links, timestamps, and identity are
  /// preserved from the fresh read, never from the possibly-stale [pr]
  /// snapshot the caller assembled. This is the Defect-2 fix — the old
  /// wholesale `_commit(pr)` could, on a lost race, resurrect the stale
  /// snapshot on top of the winner and erase a comment that landed
  /// meanwhile.
  Future<GitResult<void>> updateFull(DeskPr pr, {String? message}) async {
    final r = await _mutate(
      pr.headRef,
      transform: (current) => current.copyWith(
        // Remote-authoritative fields, taken from the incoming snapshot.
        title: pr.title,
        body: pr.body,
        state: pr.state,
        isDraft: pr.isDraft,
        labels: pr.labels,
        assignees: pr.assignees,
        reviewers: pr.reviewers,
        linkedRemoteIssues: pr.linkedRemoteIssues,
        additions: pr.additions,
        deletions: pr.deletions,
        changedFiles: pr.changedFiles,
        mergeable: pr.mergeable,
        remoteNumber: pr.remoteNumber,
        // Intentionally NOT copied from `pr` (preserved from the fresh
        // read): thread, linkedIssues, updatedAt, createdAt, deskId,
        // headRef, baseRef, authorIdentity.
      ),
      message: (_) => message ?? 'update from remote',
    );
    if (!r.ok) return GitResult.err(r.error ?? 'updateFull failed');
    return const GitResult.ok(null);
  }

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
    return _mutate(
      branch,
      transform: (current) {
        final list =
            isRemote ? current.linkedRemoteIssues : current.linkedIssues;
        final updatedList = [...list];
        if (updatedList.contains(issueId)) {
          updatedList.remove(issueId);
        } else {
          updatedList.add(issueId);
        }
        return isRemote
            ? current.copyWith(
                linkedRemoteIssues: updatedList,
                updatedAt: DateTime.now(),
              )
            : current.copyWith(
                linkedIssues: updatedList,
                updatedAt: DateTime.now(),
              );
      },
      // Subject reflects the resulting membership, computed from the
      // transformed record so it survives a retry onto fresh state.
      message: (next) {
        final present = isRemote
            ? next.linkedRemoteIssues.contains(issueId)
            : next.linkedIssues.contains(issueId);
        final kind = isRemote ? 'remote ' : '';
        return present
            ? 'link ${kind}issue #$issueId'
            : 'unlink ${kind}issue #$issueId';
      },
    );
  }

  /// Share desk PRs over [remote]: fetch peers' Manifold refs into
  /// staging, reconcile them into the live refs WITHOUT dropping any
  /// unpushed local mutation, then push back with per-ref
  /// force-with-lease. All the data-loss-safe logic lives in
  /// [ManifoldRefs.syncWithRemote]; it operates over the whole
  /// `refs/manifold/*` namespace, so a desks sync also carries issues and
  /// the shared counter in one round-trip. Also ensures (and migrates)
  /// the persistent staging fetch refspec so ordinary `git fetch` stays
  /// safe afterwards.
  ///
  /// [remote] defaults to null — resolved ONCE here (rather than a
  /// hardcoded 'origin', and rather than letting [ensureFetchRefspec] and
  /// [ManifoldRefs.syncWithRemote] each resolve it independently) so both
  /// calls in this one operation agree even if a remote rename races
  /// between them.
  Future<GitResult<void>> syncWithRemote({String? remote}) async {
    final resolvedRemote = remote ?? await refs.resolveMetadataRemote();
    await refs.ensureFetchRefspec(remote: resolvedRemote);
    return refs.syncWithRemote(remote: resolvedRemote);
  }
}
