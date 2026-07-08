// manifold_refs.dart — git plumbing for Manifold metadata refs
//
// "Local PRs" (and local issues, etc.) live as orphan commit histories
// at refs/manifold/<kind>/<name>. Each commit on that history is one
// mutation to the metadata; the latest tree's blobs are the current
// state. Audit log = git log on the ref.
//
// This module is the only place that shells out to git's plumbing
// commands (hash-object, mktree, commit-tree, update-ref, cat-file,
// for-each-ref, ls-tree). Everything above it (DeskPrStore,
// DeskIssueStore) speaks ManifoldRefs and never touches git directly.
// Keeps the I/O surface small and testable.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'git.dart' as git;
import 'git_result.dart';

/// Verdict of [ManifoldRefs._counterCoverage]: how the staged (last-seen
/// remote) counter tip relates to the reservation an allocation attempt
/// just minted locally.
enum _CounterCoverage {
  /// Staged value below the reservation (or unreadable) — push normally.
  below,

  /// Staged tip's value is at/above the reservation AND descends from the
  /// commit this attempt minted — the reservation is already on the
  /// remote's history; settle as success without pushing.
  coveredByOwnChain,

  /// Staged tip's value is at/above the reservation but on a foreign
  /// chain — a peer reserved past us; retry with a refreshed floor.
  foreignHigher,
}

class ManifoldRefs {
  /// The whole Manifold metadata namespace. Every issue, desk, and the
  /// shared id-counter lives under here.
  static const String manifoldPrefix = 'refs/manifold/';

  // The LEGACY fetch refspec `+refs/manifold/*:refs/manifold/*` mapped
  // remote `refs/manifold/*` directly onto our live refs with a leading
  // `+` (force), so a plain `git fetch` — or any sync — could force-rewind
  // a local ref that was AHEAD of the remote, silently reverting unpushed
  // comments/edits and then propagating the loss on the next push. It is
  // never written again; [ensureFetchRefspec] migrates it away and
  // installs the per-remote staging namespace below so remote tips can
  // never land on our live refs unreconciled.

  /// Null-object SHA — the "expected value" that a `--force-with-lease`
  /// uses to assert "this ref does NOT yet exist on the remote". If it
  /// does exist (a peer created it since our fetch), the lease fails
  /// rather than clobbering their creation.
  static const String _zeroSha = '0000000000000000000000000000000000000000';

  /// Prefixes scanned when computing the highest already-allocated id
  /// (see [allocSequentialId]'s regression guard). Kept here because
  /// this module already owns the `refs/manifold/*` namespace layout.
  static const String _issuesPrefix = 'refs/manifold/issues/';
  static const String _desksPrefix = 'refs/manifold/desks/';
  static const String _deskMetaFilename = 'meta.json';

  /// The shared id-counter ref. Reconciled by MAX of the two integer
  /// values rather than by content merge (see [_reconcileRef]).
  static const String _idCounterRef = 'refs/manifold/_id-counter';

  /// Per-remote staging namespace that fetched Manifold refs land in.
  /// A fetch into `refs/manifold-remote/<remote>/*` can never disturb a
  /// live `refs/manifold/*` ref, so `git fetch` is permanently safe and
  /// the only path onto a live ref is the explicit reconcile in
  /// [syncWithRemote].
  static String stagingPrefixFor(String remote) =>
      'refs/manifold-remote/$remote/';

  /// The fetch refspec written into `remote.<name>.fetch`. Force (`+`)
  /// is harmless here because the *destination* is the disposable
  /// staging namespace, not a live ref.
  static String fetchRefspecFor(String remote) =>
      '+refs/manifold/*:${stagingPrefixFor(remote)}*';

  /// Working directory passed to every git command. Should be a path
  /// inside the target repo (any worktree of it works — git resolves
  /// to the common .git via rev-parse internally).
  final String repoPath;
  /// Author/committer name baked into every metadata commit. Comes
  /// from AppIdentityState.shortName so the repo's own user.name
  /// config never leaks into Manifold metadata.
  final String authorName;
  /// Synthetic email so git's commit machinery accepts the author.
  /// Form: "<short>@manifold.local". Not user-facing; the JSON's
  /// `authorIdentity` carries the readable name.
  final String authorEmail;

  const ManifoldRefs({
    required this.repoPath,
    required this.authorName,
    required this.authorEmail,
  });

  /// Per-repo in-process allocation queue. [allocSequentialId] chains onto
  /// whatever's already running for the same repo IDENTITY so two
  /// concurrent callers IN THIS PROCESS never interleave their
  /// fetch/CAS/push sequence — the same-process race that used to let one
  /// allocator's push carry a DIFFERENT commit than the id it returned
  /// (see the fix notes on [allocSequentialId]).
  ///
  /// Keyed by the resolved git-common-dir, NOT [repoPath]: this app
  /// routinely addresses one repository through multiple worktree paths
  /// (desks) — `DeskPrState`/`DeskIssueState` build a `ManifoldRefs` from
  /// `RepositoryState.activePath`, which is worktree-specific. Two open
  /// desks of the SAME repo would then key this queue differently, bypass
  /// it entirely, and interleave CAS/push on the same refs in the shared
  /// common git dir — exactly the race this queue exists to prevent.
  /// [_commonGitDir] resolves and memoizes that identity per [repoPath];
  /// see its doc for the empirical verification that sibling worktrees of
  /// one repo resolve to the identical string on this machine.
  static final Map<String, Future<void>> _allocChains = {};

  /// Memoized `repoPath -> resolved common-git-dir` future, so the
  /// `git rev-parse --git-common-dir` round trip is paid at most once per
  /// distinct [repoPath] for the lifetime of the process — every
  /// allocation after the first for a given path reuses the cached
  /// future. Exposed for tests to assert the memoization (one entry per
  /// path, shared value across sibling worktree paths of one repo).
  @visibleForTesting
  static final Map<String, Future<String>> commonGitDirMemo = {};

  /// Resolve this instance's repo IDENTITY — the absolute common git dir
  /// — for use as the allocation-queue key. Two worktrees of the same
  /// repository resolve to the same string (verified empirically on this
  /// machine: `git worktree add` a second checkout of a temp repo, then
  /// `git -C <path> rev-parse --path-format=absolute --git-common-dir`
  /// from each worktree returns byte-identical output — forward slashes,
  /// no trailing slash, same casing — pointing at the shared `.git`).
  ///
  /// Falls back to the raw [repoPath] when resolution fails (e.g. the
  /// path isn't a git repo at all, such as a stale/removed worktree) —
  /// degraded (no longer worktree-safe) but never broken: allocation
  /// still proceeds keyed on its own path rather than throwing.
  Future<String> _commonGitDir() => commonGitDirMemo.putIfAbsent(repoPath,
      () async {
        try {
          final r = await git.runGit(repoPath,
              ['rev-parse', '--path-format=absolute', '--git-common-dir']);
          if (r.exitCode != 0) return repoPath;
          final out = (r.stdout as String).trim();
          return out.isEmpty ? repoPath : out;
        } catch (_) {
          return repoPath;
        }
      });

  /// Resolve THE metadata remote: the one remote name every Manifold
  /// surface — [allocSequentialId]'s reservation, [syncWithRemote]'s
  /// fetch/reconcile/push, [ensureFetchRefspec]'s persisted config, the
  /// staging-prefix namespace — defaults to when a caller doesn't
  /// explicitly override. These all have to agree: if create() reserved
  /// an id against 'origin' while sync() reconciled against 'upstream',
  /// the two forge remotes would each grow their own id-counter history
  /// and the "PR-ids and issue-ids never collide across clones" guarantee
  /// the counter exists for would silently break the moment a repo's only
  /// remote wasn't named 'origin' (the common fork shape: `upstream`).
  ///
  /// Delegates to [git.primaryRemoteName] — 'origin' wins when present,
  /// else the sole/first configured remote — falling back to the literal
  /// 'origin' when resolution errors or the repo has no remotes at all
  /// (a fresh or offline-only repo; every method's pre-existing behaviour
  /// in that case is unaffected, since there's nothing to resolve to).
  ///
  /// Deliberately NOT memoized, unlike [_commonGitDir]: a path's git dir
  /// is immutable, but the remote list is runtime-mutable config — a user
  /// can add `origin` to an upstream-only repo mid-session and resolution
  /// must follow. The `git remote` listing is one cheap local call at
  /// user-action rate (alloc/sync), and agreement WITHIN an operation
  /// comes from resolve-once-per-operation threading in the stores, not
  /// from a cache.
  Future<String> resolveMetadataRemote() async {
    try {
      final r = await git.primaryRemoteName(repoPath);
      if (r.ok && r.data != null) return r.data!;
    } catch (_) {
      // Fall through to the 'origin' default below.
    }
    return 'origin';
  }

  /// Run [body] after any allocation already queued for this repo's
  /// resolved identity (see [_commonGitDir]) has finished, and queue any
  /// allocation that arrives while [body] is running behind it. A failure
  /// in [body] does not wedge the queue — the chain always resolves
  /// (value discarded) so the next caller can proceed regardless of
  /// whether this one succeeded.
  Future<T> _serialized<T>(Future<T> Function() body) async {
    final key = await _commonGitDir();
    // The stored chain always resolves cleanly (errors are swallowed just
    // below before being stored), so plain `.then` here — no `onError` —
    // is enough to wait for it.
    final prior = _allocChains[key] ?? Future<void>.value();
    final gated = prior.then((_) => body());
    _allocChains[key] = gated.then((_) {}, onError: (_) {});
    return gated;
  }

  Map<String, String> get _gitEnv => {
        'GIT_AUTHOR_NAME': authorName,
        'GIT_AUTHOR_EMAIL': authorEmail,
        'GIT_COMMITTER_NAME': authorName,
        'GIT_COMMITTER_EMAIL': authorEmail,
      };

  /// Hash + write a blob, return its SHA. Content goes through stdin
  /// to handle arbitrary bytes safely.
  ///
  /// Stays on a direct [Process.start] rather than [git.runGit]: the
  /// shared runner's surface is request/response (spawn, wait for exit),
  /// it has no stdin-piping support, and `hash-object --stdin` needs to
  /// write content to the child's stdin before waiting on its exit code.
  /// Retrofitting stdin support onto a runner built for request/response
  /// calls isn't worth forcing — instead this overlays
  /// [git.kNonInteractiveGitEnv] directly (the same non-interactive env
  /// the shared runner applies) so this spawn still gets
  /// `GIT_TERMINAL_PROMPT=0` / `GIT_OPTIONAL_LOCKS=0` / `LC_ALL=C` even
  /// though it bypasses the runner's semaphore + dedup machinery.
  Future<GitResult<String>> writeBlob(String content) async {
    try {
      final p = await Process.start(
        'git',
        ['hash-object', '-w', '--stdin'],
        workingDirectory: repoPath,
        environment: git.kNonInteractiveGitEnv,
      );
      p.stdin.write(content);
      await p.stdin.flush();
      await p.stdin.close();
      final outFut = p.stdout.transform(utf8.decoder).join();
      final errFut = p.stderr.transform(utf8.decoder).join();
      final exit = await p.exitCode;
      final out = await outFut;
      final err = await errFut;
      if (exit != 0) return GitResult.err(err.trim());
      return GitResult.ok(out.trim());
    } catch (e) {
      return GitResult.err('writeBlob: $e');
    }
  }

  /// Build a tree from `{filename → blobSha}` entries. All entries are
  /// regular files (mode 100644).
  ///
  /// Same stdin rationale as [writeBlob]: kept on a direct [Process.start]
  /// (mktree reads its entries from stdin), overlaid with
  /// [git.kNonInteractiveGitEnv] rather than routed through [git.runGit],
  /// which has no stdin support.
  Future<GitResult<String>> mkTree(Map<String, String> entries) async {
    try {
      // mktree wants entries sorted by name on stdin.
      final names = entries.keys.toList()..sort();
      final buf = StringBuffer();
      for (final n in names) {
        buf.writeln('100644 blob ${entries[n]}\t$n');
      }
      final p = await Process.start(
        'git',
        ['mktree'],
        workingDirectory: repoPath,
        environment: git.kNonInteractiveGitEnv,
      );
      p.stdin.write(buf.toString());
      await p.stdin.flush();
      await p.stdin.close();
      final outFut = p.stdout.transform(utf8.decoder).join();
      final errFut = p.stderr.transform(utf8.decoder).join();
      final exit = await p.exitCode;
      final out = await outFut;
      final err = await errFut;
      if (exit != 0) return GitResult.err(err.trim());
      return GitResult.ok(out.trim());
    } catch (e) {
      return GitResult.err('mkTree: $e');
    }
  }

  /// Create a commit pointing at [treeSha], optionally chained to a
  /// parent. Author/committer come from this instance's identity.
  Future<GitResult<String>> commitTree({
    required String treeSha,
    String? parentSha,
    required String message,
  }) async {
    try {
      final args = <String>['commit-tree', treeSha];
      if (parentSha != null) args.addAll(['-p', parentSha]);
      args.addAll(['-m', message]);
      final r = await git.runGit(repoPath, args, extraEnv: _gitEnv);
      if (r.exitCode != 0) {
        return GitResult.err((r.stderr as String).trim());
      }
      return GitResult.ok((r.stdout as String).trim());
    } catch (e) {
      return GitResult.err('commitTree: $e');
    }
  }

  /// Set [ref] to [newSha]. When [oldSha] is non-null, this is CAS:
  /// fails if the ref currently points elsewhere. Pass null to create
  /// or unconditionally overwrite.
  Future<GitResult<void>> updateRef({
    required String ref,
    required String newSha,
    String? oldSha,
  }) async {
    try {
      final args = <String>['update-ref', ref, newSha];
      if (oldSha != null) args.add(oldSha);
      final r = await git.runGit(repoPath, args);
      if (r.exitCode != 0) {
        return GitResult.err((r.stderr as String).trim());
      }
      return const GitResult.ok(null);
    } catch (e) {
      return GitResult.err('updateRef: $e');
    }
  }

  /// Delete [ref]. Idempotent — succeeds if the ref doesn't exist.
  Future<GitResult<void>> deleteRef(String ref) async {
    try {
      final r = await git.runGit(repoPath, ['update-ref', '-d', ref]);
      if (r.exitCode != 0) {
        final err = (r.stderr as String).trim();
        if (err.contains('does not exist') || err.isEmpty) {
          return const GitResult.ok(null);
        }
        return GitResult.err(err);
      }
      return const GitResult.ok(null);
    } catch (e) {
      return GitResult.err('deleteRef: $e');
    }
  }

  /// Resolve [ref] to its current SHA. Returns ok(null) when missing
  /// (not an error — distinguish via the data field).
  Future<GitResult<String?>> resolveRef(String ref) async {
    try {
      final r =
          await git.runGit(repoPath, ['rev-parse', '--verify', '--quiet', ref]);
      if (r.exitCode == 0) {
        final sha = (r.stdout as String).trim();
        return GitResult.ok(sha.isEmpty ? null : sha);
      }
      // `rev-parse --verify --quiet` returns exit 1 with an empty stderr
      // for a ref that simply doesn't resolve — missing, or a malformed
      // name. That's the "genuinely absent" case → ok(null). A higher
      // exit (128 = not a git repository, damaged object store) is a
      // real failure we must surface rather than paper over as "no such
      // ref", which would silently read a broken repo as having no
      // issues / no desks.
      if (r.exitCode == 1) return const GitResult.ok(null);
      return GitResult.err((r.stderr as String).trim());
    } catch (e) {
      return GitResult.err('resolveRef: $e');
    }
  }

  /// Enumerate refs under [pattern] (e.g. `refs/manifold/desks/`).
  /// Returns refname → SHA pairs. Empty map when pattern matches
  /// nothing (not an error).
  Future<GitResult<Map<String, String>>> listRefs(String pattern) async {
    try {
      final r = await git.runGit(repoPath,
          ['for-each-ref', '--format=%(refname) %(objectname)', pattern]);
      if (r.exitCode != 0) {
        return GitResult.err((r.stderr as String).trim());
      }
      final out = <String, String>{};
      for (final line in (r.stdout as String).split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final sp = t.indexOf(' ');
        if (sp < 0) continue;
        out[t.substring(0, sp)] = t.substring(sp + 1);
      }
      return GitResult.ok(out);
    } catch (e) {
      return GitResult.err('listRefs: $e');
    }
  }

  /// Read a `<ref>:<filename>` blob in one shot — the common
  /// "give me this PR's meta.json" path. Returns ok(null) when the
  /// ref or path doesn't exist.
  Future<GitResult<String?>> readRefBlob(String ref, String filename) async {
    try {
      final r =
          await git.runGit(repoPath, ['cat-file', 'blob', '$ref:$filename']);
      if (r.exitCode == 0) return GitResult.ok(r.stdout as String);
      // cat-file exits 128 both when the object is genuinely absent
      // (missing ref, or a missing path inside a valid tree) and when
      // the object store itself is damaged. Only the "absent" phrasings
      // map to ok(null); anything else is real corruption we surface so
      // a broken repo doesn't masquerade as an empty one.
      final err = (r.stderr as String).trim();
      if (_isMissingObject(err)) return const GitResult.ok(null);
      return GitResult.err(err.isEmpty ? 'readRefBlob: exit ${r.exitCode}' : err);
    } catch (e) {
      return GitResult.err('readRefBlob: $e');
    }
  }

  /// Classify a cat-file failure as "object simply isn't there" versus a
  /// real error. The absent case shows up empirically as either
  /// `path '…' does not exist in '<ref>'` (missing file in a valid tree)
  /// or `invalid object name '<ref>'.` (missing ref / unknown object).
  /// Everything else — unreadable objects, "not a git repository" —
  /// falls through as a genuine error.
  static bool _isMissingObject(String stderr) {
    final e = stderr.toLowerCase();
    return e.contains('does not exist') ||
        e.contains('invalid object name') ||
        e.contains('not a valid object name');
  }

  /// Allocate the next sequential integer from the shared counter ref.
  /// The counter lives as a single-blob tree at [ref] containing the
  /// integer plus a newline under [filename]. CAS on the ref handles
  /// concurrent allocations on the same machine: if another allocation
  /// landed between our resolveRef and updateRef, update-ref rejects
  /// and the caller gets a failure they can retry from. Starts at 1
  /// when the ref doesn't yet exist.
  /// DeskPrStore and DeskIssueStore both allocate from the same ref
  /// so PR-ids and issue-ids never collide. [commitLabel] is the
  /// caller-visible flavour ("desk-id" vs "id") baked into the commit
  /// message, so the audit log remains legible without coupling the
  /// stores to each other.
  ///
  /// Same-process calls against the same [repoPath] are serialized via
  /// [_serialized] — see that method's doc for why. Without it, two
  /// allocations racing in this process could each win their own local
  /// CAS and then interleave with each other's remote push in a way the
  /// per-call retry loop below was never designed to detect (it only
  /// watches for a REMOTE peer moving the ref, not a sibling call in the
  /// same process moving the LOCAL ref between this call's CAS and its
  /// push). Cross-process/cross-machine races still go through the CAS +
  /// lease dance in [_allocSequentialIdImpl] unchanged.
  ///
  /// [remote] defaults to null — resolved via [resolveMetadataRemote] at
  /// the top of the (now-serialized) call, not baked in as a literal
  /// 'origin', so a repo whose only remote is named something else (e.g.
  /// `upstream` after a fork) reserves against ITS remote rather than a
  /// namespace nothing ever syncs. Callers that already know the remote
  /// (a store mid-operation that also needs it for its own sync) should
  /// pass it explicitly so it isn't resolved twice.
  Future<GitResult<int>> allocSequentialId({
    required String ref,
    required String filename,
    String commitLabel = 'id',
    int maxAttempts = 5,
    String? remote,
  }) =>
      _serialized(() async {
        final resolvedRemote = remote ?? await resolveMetadataRemote();
        return _allocSequentialIdImpl(
          ref: ref,
          filename: filename,
          commitLabel: commitLabel,
          maxAttempts: maxAttempts,
          remote: resolvedRemote,
        );
      });

  Future<GitResult<int>> _allocSequentialIdImpl({
    required String ref,
    required String filename,
    required String commitLabel,
    required int maxAttempts,
    required String remote,
  }) async {
    // Counter-regression guard. A stale clone, a hand-edited ref, or a
    // losing divergence resolution could leave a local counter reading
    // BELOW ids we've already handed out (e.g. a peer allocated up to 7
    // and we somehow hold a counter that still reads 3). Allocating 4
    // would then collide with a live #4..#7, so `next` is floored at one
    // past the highest id actually present across issues and desks —
    // LOCAL and staged, see [_highestManifoldId]. Recomputed on every
    // attempt (not just once) because a remote-reservation retry (below)
    // re-fetches staging with fresh information the floor must reflect;
    // the cost is a couple of ref scans per attempt, and retries are rare.
    //
    // REGRESSION #1 (found by the randomized convergence fuzzer — see
    // manifold_sync_convergence_test.dart's "counter properties" and
    // "randomized anti-entropy convergence" groups): the floor used to
    // scan LOCAL refs only, so a clone that had never synced was blind to
    // ids the remote already published, and its very first allocation
    // could collide with one a peer had already pushed. Fixed by having
    // [_highestManifoldId] also scan the staging namespace.
    //
    // REGRESSION #2 (same fuzzer, after fixing #1): fetch-before-allocate
    // only protects against ids a peer has already PUSHED. Two peers that
    // each allocate locally between syncs — the routine "haven't synced
    // *this* allocation yet" case, not a contrived zero-contact scenario —
    // can still both win their own LOCAL update-ref CAS and hand out the
    // same number, because neither's local ref ever saw the other's
    // pending commit. A local CAS win only proves "first on this
    // machine"; it says nothing about a peer machine racing on the same
    // remote. The shared counter's whole purpose ("PR-ids and issue-ids
    // never collide") requires a reservation that's atomic across
    // machines, which only the remote's ref-update can provide. Fixed
    // below: once the local CAS wins, the same commit is pushed to the
    // remote counter ref with `--force-with-lease` against whatever we
    // last saw staged there. Git's receive-pack serializes concurrent ref
    // updates, so if a peer's reservation lands first, our lease fails —
    // retryable, exactly like [ManifoldRefs.syncWithRemote] — and we loop:
    // re-fetch staging, recompute the floor (now past the peer's
    // reservation), and try again. When there's no remote configured, no
    // reservation is possible or needed — allocation degrades to exactly
    // the local-only behaviour this method always had, so a genuinely
    // offline repo is unaffected.
    final hasRemote = await readConfig('remote.$remote.url') != null;
    final stagedRef =
        '${stagingPrefixFor(remote)}${ref.substring(manifoldPrefix.length)}';

    var attempt = 0;
    String? lastError;
    while (attempt < maxAttempts) {
      attempt++;
      if (hasRemote) await fetchToStaging(remote: remote);
      var highest = await _highestManifoldId(remote: remote);

      // REGRESSION #3 (same fuzzer): the floor above only reflects
      // entity refs (issues/desks) actually pushed — but create() never
      // pushes the entity ref itself, only this counter reservation (see
      // REGRESSION #2). So a peer's already-reserved counter VALUE can be
      // visible via fetch while their entity ref (and thus their id) is
      // still invisible to `highest`, and a naive `next` computed only
      // from our own local counter blob would land on that same value.
      // Folding the staged counter's numeric value into the floor closes
      // that gap without waiting for the peer's entity ref to arrive.
      if (hasRemote) {
        final stagedTip = await resolveRef(stagedRef);
        if (stagedTip.ok && stagedTip.data != null) {
          final stagedBlob = await readRefBlob(stagedTip.data!, filename);
          if (stagedBlob.ok && stagedBlob.data != null) {
            final n = int.tryParse(stagedBlob.data!.trim());
            if (n != null && n > highest) highest = n;
          }
        }
      }

      final cur = await resolveRef(ref);
      if (!cur.ok) return GitResult.err(cur.error ?? 'resolveRef failed');
      var next = 1;
      if (cur.data != null) {
        final blob = await readRefBlob(ref, filename);
        if (blob.ok && blob.data != null) {
          final n = int.tryParse(blob.data!.trim());
          if (n != null) next = n + 1;
        }
      }
      // Apply the regression floor computed above.
      if (highest + 1 > next) next = highest + 1;
      final blobR = await writeBlob('$next\n');
      if (!blobR.ok) {
        return GitResult.err(blobR.error ?? 'writeBlob failed');
      }
      final treeR = await mkTree({filename: blobR.data!});
      if (!treeR.ok) {
        return GitResult.err(treeR.error ?? 'mkTree failed');
      }
      final commitR = await commitTree(
        treeSha: treeR.data!,
        parentSha: cur.data,
        message: 'allocate $commitLabel $next',
      );
      if (!commitR.ok) {
        return GitResult.err(commitR.error ?? 'commitTree failed');
      }
      final updR = await updateRef(
        ref: ref,
        newSha: commitR.data!,
        oldSha: cur.data,
      );
      if (!updR.ok) {
        lastError = updR.error;
        // Randomised 5–25ms backoff keeps two clients from lockstepping
        // into the same collision on the next attempt.
        await Future<void>.delayed(
            Duration(milliseconds: 5 + (attempt * 5)));
        continue;
      }
      if (!hasRemote) return GitResult.ok(next);

      // Reserve `next` on the remote too (see REGRESSION #2 above). The
      // lease is the counter sha we last saw staged for this ref (or the
      // zero-sha when the remote lacks it entirely) — the same lease
      // discipline [_leasePush] uses for the general sync path.
      //
      // REGRESSION #4 (found by review, not the fuzzer — the interleaving
      // is narrow enough it never came up randomly, but is real): pushing
      // plain `<ref>:<ref>` sends whatever the LOCAL ref points to AT PUSH
      // TIME, not the commit this attempt just created. In-process callers
      // can no longer race here ([allocSequentialId] serializes them via
      // [_serialized]), but nothing stops another local mutation of `ref`
      // between our `updateRef` above and this push from a source outside
      // the counter path (e.g. a concurrent [syncWithRemote] reconciling
      // the same ref) — that would silently push a commit that is not
      // `commitR.data!`, desynchronizing "the id this call returns" from
      // "what got reserved on the remote". Pinning the source side of the
      // refspec to `commitR.data!` (an explicit sha source, standard
      // refspec syntax — verified empirically against a scratch bare+clone
      // that `--force-with-lease=<ref>:<lease> <remote> <sha>:<ref>` pushes
      // exactly that sha even when it isn't the local ref's current tip)
      // means the remote receives precisely the commit this call minted,
      // no matter what the local ref does afterwards.
      //
      // COVERAGE GUARD (both before the push and after a lease rejection).
      // The staging ref is NOT a pure fetch snapshot: git updates
      // remote-tracking refs on PUSH too (any push of `refs/manifold/*`
      // from this clone maps through `remote.<name>.fetch` onto staging —
      // observed empirically when a mid-allocation push from the same
      // clone silently refreshed the lease and let a LOWER counter value
      // overwrite a higher remote one). So by the time we resolve the
      // lease, staging can already be AHEAD of the snapshot `next` was
      // computed from. Before pushing, classify the staged tip:
      //  * its counter value < `next` → normal case, push the pinned sha.
      //  * value >= `next` AND our own commit is an ANCESTOR of that tip →
      //    our reservation is already ON the remote's history (something —
      //    a concurrent same-process [syncWithRemote], or a peer relaying
      //    our local ref — pushed a descendant of the commit this call
      //    minted). `next` is permanently reserved; settle as SUCCESS
      //    without pushing. Reserving N under a remote already at N+1 must
      //    be a success, not a retry storm — and pushing here would
      //    actively REGRESS the remote counter.
      //  * value >= `next` but a FOREIGN chain (not descended from our
      //    commit) → a peer reserved values at-or-past `next`, and we
      //    cannot know whether `next` itself is among the ids their
      //    machine handed out. Returning `next` could collide; pushing
      //    would regress their counter. Retry: the refreshed floor sees
      //    their value, so the next attempt allocates strictly above it.
      final stagedTip = await resolveRef(stagedRef);
      if (stagedTip.data != null) {
        final cover = await _counterCoverage(
          stagedTipSha: stagedTip.data!,
          filename: filename,
          next: next,
          ownCommitSha: commitR.data!,
        );
        if (cover == _CounterCoverage.coveredByOwnChain) {
          return GitResult.ok(next);
        }
        if (cover == _CounterCoverage.foreignHigher) {
          lastError = 'counter reservation raced: remote already past $next';
          await Future<void>.delayed(
              Duration(milliseconds: 5 + (attempt * 5)));
          continue;
        }
      }
      final lease = stagedTip.data ?? _zeroSha;
      final push = await _leasePush(remote: remote, pushes: [
        (ref: ref, lease: lease, sha: commitR.data!),
      ]);
      if (push.ok) return GitResult.ok(next);
      final err = push.error ?? '';
      if (err.startsWith(retryablePrefix)) {
        // The remote moved between our lease resolve and our pinned push.
        // Nothing was clobbered (the lease refused rather than
        // overwriting). Re-fetch staging and apply the same coverage
        // classification as above: covered-by-own-chain settles as
        // success; foreign-higher (or a still-stale view) loops with a
        // refreshed floor.
        await fetchToStaging(remote: remote);
        final coverTip = await resolveRef(stagedRef);
        if (coverTip.ok && coverTip.data != null) {
          final cover = await _counterCoverage(
            stagedTipSha: coverTip.data!,
            filename: filename,
            next: next,
            ownCommitSha: commitR.data!,
          );
          if (cover == _CounterCoverage.coveredByOwnChain) {
            return GitResult.ok(next);
          }
        }
        lastError = err;
        await Future<void>.delayed(
            Duration(milliseconds: 5 + (attempt * 5)));
        continue;
      }
      // Any other failure (remote unreachable, auth, offline) — the
      // remote simply isn't reachable right now, indistinguishable from
      // there being no live peer to race from here. Degrade to the local
      // allocation rather than blocking offline use; the residual
      // exposure is a genuine network outage coinciding with a concurrent
      // peer creation, not the routine case this fix targets.
      return GitResult.ok(next);
    }
    return GitResult.err(
        lastError ?? 'updateRef failed after $maxAttempts attempts');
  }

  /// Classify the staged counter tip against the reservation this
  /// allocation attempt just minted ([ownCommitSha], carrying the value
  /// [next]). See the coverage-guard comment inside
  /// [_allocSequentialIdImpl] for the semantics of each verdict.
  Future<_CounterCoverage> _counterCoverage({
    required String stagedTipSha,
    required String filename,
    required int next,
    required String ownCommitSha,
  }) async {
    final blob = await readRefBlob(stagedTipSha, filename);
    if (!blob.ok || blob.data == null) return _CounterCoverage.below;
    final v = int.tryParse(blob.data!.trim());
    if (v == null || v < next) return _CounterCoverage.below;
    if (await isAncestor(ownCommitSha, stagedTipSha)) {
      return _CounterCoverage.coveredByOwnChain;
    }
    return _CounterCoverage.foreignHigher;
  }

  /// Highest id already committed to any Manifold ref, LOCAL or staged
  /// for [remote]. Issue ids ARE the ref tail
  /// (`refs/manifold/issues/<id>` / `refs/manifold-remote/<remote>/issues/<id>`)
  /// so they read straight off the ref list; desk ids live inside each
  /// `meta.json` and cost one blob read apiece. Returns 0 when nothing is
  /// allocated yet. Used only by [allocSequentialId]'s regression guard —
  /// never on a hot path.
  ///
  /// Scans the staging namespace as well as the live one: a clone that
  /// has never synced (or whose last sync predates a peer's push) has an
  /// empty or stale LIVE view, but [allocSequentialId] opportunistically
  /// refreshes staging first, so this still sees ids the remote already
  /// holds even on this clone's very first allocation. Without this, two
  /// fresh clones each creating their first record before ever syncing
  /// with each other could allocate the same id into two different kinds
  /// (an issue and a desk PR) — a real collision the shared counter
  /// exists specifically to prevent.
  Future<int> _highestManifoldId({required String remote}) async {
    var hi = 0;
    Future<void> scanIssues(String prefix) async {
      final issues = await listRefs(prefix);
      if (!issues.ok) return;
      for (final ref in issues.data!.keys) {
        final tail = ref.substring(ref.lastIndexOf('/') + 1);
        final n = int.tryParse(tail);
        if (n != null && n > hi) hi = n;
      }
    }

    Future<void> scanDesks(String prefix) async {
      final desks = await listRefs(prefix);
      if (!desks.ok) return;
      for (final ref in desks.data!.keys) {
        final blob = await readRefBlob(ref, _deskMetaFilename);
        if (!blob.ok || blob.data == null) continue;
        try {
          final j = jsonDecode(blob.data!) as Map<String, dynamic>;
          final n = (j['deskId'] as num?)?.toInt();
          if (n != null && n > hi) hi = n;
        } catch (_) {
          // Corrupt meta.json — skip it, exactly as listAll does. A
          // record we can't parse can't be contributing a live id we
          // need to avoid.
        }
      }
    }

    await scanIssues(_issuesPrefix);
    await scanDesks(_desksPrefix);
    final stagePrefix = stagingPrefixFor(remote);
    await scanIssues(
        '$stagePrefix${_issuesPrefix.substring(manifoldPrefix.length)}');
    await scanDesks(
        '$stagePrefix${_desksPrefix.substring(manifoldPrefix.length)}');
    return hi;
  }

  /// Ensure [remote] fetches Manifold metadata into the safe per-remote
  /// staging namespace, and MIGRATE away the dangerous legacy refspec.
  /// Idempotent; a no-op when the remote is unconfigured (a fresh repo or
  /// a test fixture is a valid state). Only ever touches
  /// `remote.<name>.fetch` — never `.push`, so the user's plain
  /// `git push` default behaviour is left untouched. Both stores call
  /// this from their create/sync path so an issues-only or desks-only
  /// user still auto-pulls Manifold metadata on `git fetch` — now onto
  /// staging, so that plain fetch can never rewind a live ref.
  /// [remote] defaults to null — resolved via [resolveMetadataRemote]
  /// rather than a hardcoded 'origin' — so this migrates/installs the
  /// refspec on whichever remote is actually this repo's forge remote.
  Future<void> ensureFetchRefspec({String? remote}) async {
    final resolvedRemote = remote ?? await resolveMetadataRemote();
    // Skip when there's no remote to attach to. Without this guard
    // `git config --add` would still succeed (writing a key under a
    // non-existent remote section), leaving misleading config behind.
    final url = await readConfig('remote.$resolvedRemote.url');
    if (url == null) return;
    // Remove any previously-configured `+refs/manifold/*:refs/manifold/*`
    // entry. The value passed to `--unset-all` is a POSIX regex, so the
    // refspec's `+` and `*` (quantifier metacharacters) are escaped and
    // the whole thing anchored, matching ONLY the legacy value and
    // leaving the user's other fetch refspecs (heads, tags, …) intact.
    // A no-match exits 5; that is expected on a clean repo and ignored.
    await unsetConfigMatching(
      'remote.$resolvedRemote.fetch',
      r'^\+refs/manifold/\*:refs/manifold/\*$',
    );
    await addConfigOnce(
        'remote.$resolvedRemote.fetch', fetchRefspecFor(resolvedRemote));
  }

  /// Fetch every `refs/manifold/*` from [remote] into the disposable
  /// staging namespace `refs/manifold-remote/<remote>/*`. Works even
  /// before [ensureFetchRefspec] has persisted the config refspec, so the
  /// very first sync in a fresh clone still pulls peers' metadata. Force
  /// (`+`) is safe: the destination is staging, never a live ref.
  /// [remote] defaults to null — resolved via [resolveMetadataRemote]
  /// rather than a hardcoded 'origin'.
  Future<GitResult<void>> fetchToStaging({String? remote}) async {
    try {
      final resolvedRemote = remote ?? await resolveMetadataRemote();
      final r = await git.runGit(repoPath,
          ['fetch', resolvedRemote, fetchRefspecFor(resolvedRemote)]);
      if (r.exitCode != 0) {
        return GitResult.err((r.stderr as String).trim());
      }
      return const GitResult.ok(null);
    } catch (e) {
      return GitResult.err('fetchToStaging: $e');
    }
  }

  /// True when [maybeAncestor] is an ancestor of [descendant] (or equal
  /// to it — `git merge-base --is-ancestor X X` exits 0). Used by
  /// [syncWithRemote] to classify a local/staged pair as fast-forwardable
  /// versus genuinely diverged. Returns false on any git error, which
  /// (conservatively) routes the pair into the divergence merge rather
  /// than a lossy fast-forward.
  Future<bool> isAncestor(String maybeAncestor, String descendant) async {
    try {
      final r = await git.runGit(
          repoPath, ['merge-base', '--is-ancestor', maybeAncestor, descendant]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Create a merge commit for [treeSha] with two-or-more [parents]
  /// (`commit-tree TREE -p A -p B`). The tree is the reconciled record;
  /// the parents preserve BOTH lineages so the audit history shows the
  /// merge and the counterpart's tip becomes reachable (which lets the
  /// other side fast-forward on its next sync instead of re-merging).
  Future<GitResult<String>> commitMergeTree({
    required String treeSha,
    required List<String> parents,
    required String message,
  }) async {
    try {
      final args = <String>['commit-tree', treeSha];
      for (final p in parents) {
        args.addAll(['-p', p]);
      }
      args.addAll(['-m', message]);
      final r = await git.runGit(repoPath, args, extraEnv: _gitEnv);
      if (r.exitCode != 0) {
        return GitResult.err((r.stderr as String).trim());
      }
      return GitResult.ok((r.stdout as String).trim());
    } catch (e) {
      return GitResult.err('commitMergeTree: $e');
    }
  }

  /// Read the single blob of a Manifold tree (`<commit>` → its lone
  /// `{filename → content}`). Every Manifold ref stores exactly one blob
  /// (issue.json / meta.json / counter.txt), so this is unambiguous and
  /// filename-agnostic — the reconcile engine reuses whatever name it
  /// finds when writing a merged tree. Returns ok(null) for an empty
  /// tree.
  Future<GitResult<({String filename, String content})?>> readSingleTreeBlob(
      String commitish) async {
    try {
      final ls = await git.runGit(
          repoPath, ['ls-tree', '--name-only', commitish]);
      if (ls.exitCode != 0) {
        return GitResult.err((ls.stderr as String).trim());
      }
      final names = (ls.stdout as String)
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.isEmpty) return const GitResult.ok(null);
      final name = names.first;
      final blob = await readRefBlob(commitish, name);
      if (!blob.ok) return GitResult.err(blob.error ?? 'readRefBlob failed');
      if (blob.data == null) return const GitResult.ok(null);
      return GitResult.ok((filename: name, content: blob.data!));
    } catch (e) {
      return GitResult.err('readSingleTreeBlob: $e');
    }
  }

  /// Remove every value of [configKey] matching the POSIX regex
  /// [valueRegex]. Tolerates git's exit 5 ("no such option / nothing
  /// matched") as a benign no-op so a clean repo isn't reported as an
  /// error. Used to migrate away the legacy fetch refspec.
  Future<GitResult<void>> unsetConfigMatching(
      String configKey, String valueRegex) async {
    try {
      final r = await git.runGit(
          repoPath, ['config', '--unset-all', configKey, valueRegex]);
      // 0 = removed something; 5 = nothing matched (clean repo). Both fine.
      if (r.exitCode == 0 || r.exitCode == 5) return const GitResult.ok(null);
      return GitResult.err((r.stderr as String).trim());
    } catch (e) {
      return GitResult.err('unsetConfigMatching: $e');
    }
  }

  // ─── Sync / reconcile ────────────────────────────────────────────────

  /// Marker prefix on the error string when a sync could not complete
  /// because the remote moved between our fetch and our push (a lease
  /// failure). The caller can treat it as retryable — nothing was
  /// clobbered; re-running the sync re-fetches and re-reconciles.
  static const String retryablePrefix = 'retryable: ';

  /// Fetch peers' Manifold metadata into staging, RECONCILE it into the
  /// live `refs/manifold/*` refs without ever losing a local mutation,
  /// then push the reconciled refs back with per-ref `--force-with-lease`
  /// so a concurrent peer push can't be clobbered. This is the whole
  /// data-loss fix for the sync path; both stores delegate here.
  ///
  /// Reconcile is done over the ENTIRE `refs/manifold/*` namespace in one
  /// pass (issues, desks, and the shared counter) because a single sync
  /// is a whole-namespace operation. Records are merged generically over
  /// their JSON (see [_mergeJsonRecords]); the counter is merged by MAX.
  /// [remote] defaults to null — resolved ONCE here via
  /// [resolveMetadataRemote] (rather than a hardcoded 'origin', and
  /// rather than letting [fetchToStaging]/[_leasePush] each resolve it
  /// again independently) so the fetch, the staging-prefix reads, and the
  /// push all agree on the identical remote name for this one sync
  /// operation even if a rename raced between them.
  Future<GitResult<void>> syncWithRemote({String? remote}) async {
    final resolvedRemote = remote ?? await resolveMetadataRemote();
    final fetched = await fetchToStaging(remote: resolvedRemote);
    if (!fetched.ok) return GitResult.err(fetched.error ?? 'fetch failed');

    final localR = await listRefs(manifoldPrefix);
    if (!localR.ok) return GitResult.err(localR.error ?? 'listRefs failed');
    final stagedR = await listRefs(stagingPrefixFor(resolvedRemote));
    if (!stagedR.ok) return GitResult.err(stagedR.error ?? 'listRefs failed');

    // Fold both sides onto a common "live ref" key. Staged refs live at
    // refs/manifold-remote/<remote>/<tail>; their live counterpart is
    // refs/manifold/<tail>.
    final stagePrefix = stagingPrefixFor(resolvedRemote);
    final local = localR.data!; // live ref -> sha
    final staged = <String, String>{}; // live ref -> staged sha
    stagedR.data!.forEach((ref, sha) {
      staged['$manifoldPrefix${ref.substring(stagePrefix.length)}'] = sha;
    });

    final liveRefs = <String>{...local.keys, ...staged.keys};

    // Push entries accumulated during reconcile: each is a live ref whose
    // local tip we want on the remote, leased against the sha we last saw
    // there (staged sha, or the zero-sha when the remote lacked it).
    final pushes = <({String ref, String lease})>[];

    for (final ref in liveRefs) {
      final res = await _reconcileRef(
        ref: ref,
        localSha: local[ref],
        stagedSha: staged[ref],
      );
      if (!res.ok) return GitResult.err(res.error ?? 'reconcile failed');
      final push = res.data;
      if (push != null) pushes.add(push);
    }

    if (pushes.isEmpty) return const GitResult.ok(null);
    // Reconcile pushes want the ambient "whatever the local ref says now"
    // behaviour — the local ref IS the reconciled tip at this point — so
    // no explicit sha is pinned here (see [_leasePush]'s doc).
    return _leasePush(
      remote: resolvedRemote,
      pushes: pushes
          .map<({String ref, String lease, String? sha})>(
              (p) => (ref: p.ref, lease: p.lease, sha: null))
          .toList(),
    );
  }

  /// Reconcile one live ref from its local and staged tips. Returns the
  /// push entry the caller should send (or null when nothing needs to go
  /// to the remote — either the ref is already in sync or we merely
  /// fast-forwarded local onto a tip the remote already has). All local
  /// ref movement is applied here via CAS update-ref.
  Future<GitResult<({String ref, String lease})?>> _reconcileRef({
    required String ref,
    required String? localSha,
    required String? stagedSha,
  }) async {
    // Remote lacks it entirely → our local ref is new to the remote.
    // Push it, leasing against absence so a peer who created the same ref
    // since our fetch wins instead of being clobbered.
    if (stagedSha == null) {
      return GitResult.ok((ref: ref, lease: _zeroSha));
    }
    // We lack it → adopt the remote's tip verbatim (fast-forward create).
    // Nothing to push; the remote already has it.
    if (localSha == null) {
      final upd = await updateRef(ref: ref, newSha: stagedSha);
      if (!upd.ok) return GitResult.err(upd.error ?? 'updateRef failed');
      return const GitResult.ok(null);
    }
    // Identical tips → already in sync.
    if (localSha == stagedSha) return const GitResult.ok(null);

    // The shared counter is not a mergeable record: reconcile by MAX of
    // the two integer values so it never moves backwards.
    if (ref == _idCounterRef) {
      return _reconcileCounter(
          ref: ref, localSha: localSha, stagedSha: stagedSha);
    }

    // local already contains staged → keep local, push it (lease=staged).
    if (await isAncestor(stagedSha, localSha)) {
      return GitResult.ok((ref: ref, lease: stagedSha));
    }
    // staged already contains local → fast-forward local to staged.
    // Remote already has staged, so nothing to push.
    if (await isAncestor(localSha, stagedSha)) {
      final upd =
          await updateRef(ref: ref, newSha: stagedSha, oldSha: localSha);
      if (!upd.ok) return GitResult.err(upd.error ?? 'updateRef failed');
      return const GitResult.ok(null);
    }

    // ─── Genuine divergence ──────────────────────────────────────────
    final localBlob = await readSingleTreeBlob(localSha);
    if (!localBlob.ok) return GitResult.err(localBlob.error ?? 'read failed');
    final stagedBlob = await readSingleTreeBlob(stagedSha);
    if (!stagedBlob.ok) return GitResult.err(stagedBlob.error ?? 'read failed');
    if (localBlob.data == null || stagedBlob.data == null) {
      return GitResult.err('divergent ref $ref has an empty tree');
    }
    final lc = localBlob.data!;
    final sc = stagedBlob.data!;

    // Convergence / anti-ping-pong rule. When both machines run the same
    // reconcile they produce the same MERGED CONTENT but different merge-
    // commit shas; those two commits are then themselves "diverged". If
    // we minted a fresh merge commit every time, the two sides would
    // ping-pong forever, each re-merging the other's merge. So whenever
    // the two tips already carry byte-identical records (canonicalised so
    // key ordering can't cause a false mismatch), we do NOT mint a new
    // commit: we deterministically pick the tip with the lexicographically
    // larger sha as the survivor. Both sides pick the SAME survivor, so
    // they converge to one sha and the next sync is a no-op.
    if (_canonicalJson(lc.content) == _canonicalJson(sc.content)) {
      return _adoptLargerSha(ref: ref, localSha: localSha, stagedSha: stagedSha);
    }

    // Records genuinely differ → deterministic field-wise union merge.
    // Tie-breaks (equal updatedAt) resolve toward the lexicographically
    // larger tip sha so BOTH machines choose the same winner and the two
    // independent merges produce identical content.
    final String merged;
    try {
      merged = _mergeJsonRecords(lc.content, sc.content, localSha, stagedSha);
    } catch (e) {
      return GitResult.err('merge of $ref failed: $e');
    }
    final blobR = await writeBlob(merged);
    if (!blobR.ok) return GitResult.err(blobR.error ?? 'writeBlob failed');
    final treeR = await mkTree({lc.filename: blobR.data!});
    if (!treeR.ok) return GitResult.err(treeR.error ?? 'mkTree failed');
    final commitR = await commitMergeTree(
      treeSha: treeR.data!,
      parents: [localSha, stagedSha],
      message: 'reconcile $ref',
    );
    if (!commitR.ok) return GitResult.err(commitR.error ?? 'commit failed');
    final upd =
        await updateRef(ref: ref, newSha: commitR.data!, oldSha: localSha);
    if (!upd.ok) return GitResult.err(upd.error ?? 'updateRef failed');
    // Push the merge, leasing against the staged sha we merged in.
    return GitResult.ok((ref: ref, lease: stagedSha));
  }

  /// Reconcile the shared id-counter by MAX of the two integer values.
  /// The higher-valued tip already exists as a commit on one side, so we
  /// never mint a new one: we point local at whichever tip holds the
  /// larger count (ties resolve to the larger sha for cross-machine
  /// determinism). Never moves the counter backwards.
  Future<GitResult<({String ref, String lease})?>> _reconcileCounter({
    required String ref,
    required String localSha,
    required String stagedSha,
  }) async {
    final localBlob = await readSingleTreeBlob(localSha);
    final stagedBlob = await readSingleTreeBlob(stagedSha);
    if (!localBlob.ok || !stagedBlob.ok) {
      return const GitResult.err('counter read failed');
    }
    final localVal =
        int.tryParse((localBlob.data?.content ?? '').trim()) ?? 0;
    final stagedVal =
        int.tryParse((stagedBlob.data?.content ?? '').trim()) ?? 0;
    if (localVal > stagedVal) {
      // Keep our higher local counter; push it (lease against staged).
      return GitResult.ok((ref: ref, lease: stagedSha));
    }
    if (stagedVal > localVal) {
      // Adopt the remote's higher counter. Remote already has it → no push.
      final upd =
          await updateRef(ref: ref, newSha: stagedSha, oldSha: localSha);
      if (!upd.ok) return GitResult.err(upd.error ?? 'updateRef failed');
      return const GitResult.ok(null);
    }
    // Equal value, different tips → converge on one sha deterministically.
    return _adoptLargerSha(ref: ref, localSha: localSha, stagedSha: stagedSha);
  }

  /// Converge two content-identical-but-distinct tips onto the
  /// lexicographically larger sha (a deterministic choice both machines
  /// make identically). When local is already the survivor we push it
  /// (leased against staged); otherwise we fast-forward local to the
  /// staged survivor, which the remote already holds, so nothing pushes.
  Future<GitResult<({String ref, String lease})?>> _adoptLargerSha({
    required String ref,
    required String localSha,
    required String stagedSha,
  }) async {
    if (localSha.compareTo(stagedSha) > 0) {
      return GitResult.ok((ref: ref, lease: stagedSha));
    }
    final upd = await updateRef(ref: ref, newSha: stagedSha, oldSha: localSha);
    if (!upd.ok) return GitResult.err(upd.error ?? 'updateRef failed');
    return const GitResult.ok(null);
  }

  /// Push the reconciled [pushes] to [remote] in ONE invocation, each
  /// with a per-ref `--force-with-lease=<ref>:<lease>`. The lease is the
  /// sha we last observed on the remote (from staging), so if a peer
  /// pushed that ref between our fetch and now, the lease fails and we
  /// return a [retryablePrefix] error rather than clobbering their work.
  ///
  /// [pushes] entries may optionally pin an explicit source [sha] —
  /// `<sha>:<ref>` instead of the default `<ref>:<ref>` — so the push
  /// sends exactly that commit regardless of whatever the local ref
  /// happens to point at when this call actually runs. Ordinary
  /// [syncWithRemote] reconcile pushes want the ambient "whatever local
  /// says now" behaviour (the local ref IS the reconciled result at that
  /// point), so they leave `sha` null; [allocSequentialId] pins it to the
  /// commit its own CAS just won (see REGRESSION #4 there) so a sibling
  /// mutation of the same ref between its CAS and its push can't cause it
  /// to push someone else's commit while reporting its own id.
  Future<GitResult<void>> _leasePush({
    required String remote,
    required List<({String ref, String lease, String? sha})> pushes,
  }) async {
    try {
      final args = <String>['push', remote];
      for (final p in pushes) {
        args.add('--force-with-lease=${p.ref}:${p.lease}');
      }
      for (final p in pushes) {
        args.add('${p.sha ?? p.ref}:${p.ref}');
      }
      final r = await git.runGit(repoPath, args);
      if (r.exitCode == 0) return const GitResult.ok(null);
      final err = (r.stderr as String).trim();
      final lower = err.toLowerCase();
      if (lower.contains('stale info') ||
          lower.contains('rejected') ||
          lower.contains('force-with-lease')) {
        return GitResult.err(
            '${retryablePrefix}remote moved during sync; nothing was '
            'clobbered — retry the sync. ($err)');
      }
      return GitResult.err(err.isEmpty ? 'push failed' : err);
    } catch (e) {
      return GitResult.err('leasePush: $e');
    }
  }

  // ─── Deterministic record merge ──────────────────────────────────────

  /// Field-wise union merge of two Manifold JSON records into a single
  /// canonical blob. Both machines running this over the same pair of
  /// records produce byte-identical output, which is what makes the sync
  /// converge.
  ///
  /// Rules:
  ///  * `updatedAt` → the MAX of the two timestamps.
  ///  * "comment-like" arrays — a list whose every element is an object
  ///    carrying `author` + `at` + `body` (issue comments, PR thread
  ///    entries) — are UNIONED, deduped by the exact (author, at, body)
  ///    tuple, and sorted by (at, author, body). A fully deterministic
  ///    total order is required (not merely "at, then original position",
  ///    which isn't well-defined once entries come from two machines) so
  ///    both sides land on the same ordering.
  ///  * every other field (scalars and non-comment lists: title, body,
  ///    state, labels, assignees, linked lists, reviewers, remoteNumber,
  ///    diff stats, …) is last-writer-wins: taken wholesale from the
  ///    record with the larger `updatedAt`; a tie resolves to the
  ///    lexicographically larger tip [localSha]/[stagedSha] so both
  ///    machines pick the same winner.
  static String _mergeJsonRecords(
    String localBlob,
    String stagedBlob,
    String localSha,
    String stagedSha,
  ) {
    final local = jsonDecode(localBlob) as Map<String, dynamic>;
    final staged = jsonDecode(stagedBlob) as Map<String, dynamic>;
    final localT = _parseTs(local['updatedAt']);
    final stagedT = _parseTs(staged['updatedAt']);

    final int cmp = localT.compareTo(stagedT);
    final bool localWins =
        cmp > 0 || (cmp == 0 && localSha.compareTo(stagedSha) >= 0);
    final winner = localWins ? local : staged;
    final loser = localWins ? staged : local;

    final merged = <String, dynamic>{};
    final keys = <String>{...local.keys, ...staged.keys};
    for (final k in keys) {
      final lv = local[k];
      final sv = staged[k];
      if (_isCommentList(lv) || _isCommentList(sv)) {
        merged[k] = _unionComments(lv, sv);
      } else {
        merged[k] = winner.containsKey(k) ? winner[k] : loser[k];
      }
    }
    // updatedAt is always the max, regardless of which record "won".
    merged['updatedAt'] =
        (localT.isAfter(stagedT) ? localT : stagedT).toIso8601String();
    return _canonicalJson(jsonEncode(merged));
  }

  static DateTime _parseTs(Object? v) =>
      DateTime.tryParse(v is String ? v : '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// A value is "comment-like" when it is a non-empty list whose every
  /// element is a JSON object carrying author/at/body. That distinguishes
  /// issue comments / PR thread entries (unioned) from string lists like
  /// labels and object lists like reviewers ({login,state}) which are
  /// last-writer-wins.
  static bool _isCommentList(Object? v) {
    if (v is! List || v.isEmpty) return false;
    for (final e in v) {
      if (e is! Map) return false;
      if (!e.containsKey('author') ||
          !e.containsKey('at') ||
          !e.containsKey('body')) {
        return false;
      }
    }
    return true;
  }

  static List<Map<String, dynamic>> _unionComments(Object? lv, Object? sv) {
    final all = <Map<String, dynamic>>[];
    if (lv is List) all.addAll(lv.whereType<Map<String, dynamic>>());
    if (sv is List) all.addAll(sv.whereType<Map<String, dynamic>>());
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final e in all) {
      final key =
          '${e['author']}\u0000${e['at']}\u0000${e['body']}';
      if (seen.add(key)) out.add(e);
    }
    out.sort((a, b) {
      int c = _s(a['at']).compareTo(_s(b['at']));
      if (c != 0) return c;
      c = _s(a['author']).compareTo(_s(b['author']));
      if (c != 0) return c;
      return _s(a['body']).compareTo(_s(b['body']));
    });
    return out;
  }

  static String _s(Object? v) => v is String ? v : (v?.toString() ?? '');

  /// Canonical JSON: every map's keys recursively sorted, re-serialised
  /// with the same two-space indent the records use. Order-independent,
  /// so two records that differ only in field order compare equal — the
  /// linchpin of the anti-ping-pong convergence check.
  static String _canonicalJson(String rawJson) =>
      const JsonEncoder.withIndent('  ')
          .convert(_canonicalize(jsonDecode(rawJson)));

  static Object? _canonicalize(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return LinkedHashMap<String, Object?>.fromEntries(
          keys.map((k) => MapEntry(k, _canonicalize(v[k]))));
    }
    if (v is List) return v.map(_canonicalize).toList();
    return v;
  }

  /// Probe whether [headRef] would merge cleanly into [baseRef]. Uses
  /// `git merge-tree --write-tree` (git ≥ 2.38) which produces a tree
  /// in the object store and reports conflicts on stderr without
  /// touching the working tree or index.
  /// Returns 'MERGEABLE', 'CONFLICTING', or 'UNKNOWN' (when either ref
  /// doesn't resolve or merge-tree itself errors for reasons other
  /// than conflicts).
  Future<String> probeMergeable(String baseRef, String headRef) async {
    try {
      final r = await git.runGit(repoPath,
          ['merge-tree', '--write-tree', '--name-only', baseRef, headRef]);
      // Exit 0 = clean merge, tree SHA on stdout.
      // Exit 1 = conflicts, tree SHA + conflicting paths on stdout.
      // Other = couldn't even attempt (unreachable refs, etc.).
      if (r.exitCode == 0) return 'MERGEABLE';
      if (r.exitCode == 1) return 'CONFLICTING';
      return 'UNKNOWN';
    } catch (_) {
      return 'UNKNOWN';
    }
  }

  /// Read the value of [configKey] from the repo's git config. Returns
  /// null when unset (not an error). Used to detect whether the
  /// fetch.refspec for refs/manifold/* is already configured.
  Future<String?> readConfig(String configKey) async {
    try {
      final r = await git.runGit(repoPath, ['config', '--get-all', configKey]);
      if (r.exitCode != 0) return null;
      final v = (r.stdout as String).trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// Append [value] to [configKey] if not already present. Used to
  /// add the manifold fetch refspec without clobbering existing
  /// refspecs the user may have configured.
  Future<GitResult<void>> addConfigOnce(String configKey, String value) async {
    try {
      final existing = await readConfig(configKey);
      if (existing != null && existing.split('\n').contains(value)) {
        return const GitResult.ok(null);
      }
      final r =
          await git.runGit(repoPath, ['config', '--add', configKey, value]);
      if (r.exitCode != 0) {
        return GitResult.err((r.stderr as String).trim());
      }
      return const GitResult.ok(null);
    } catch (e) {
      return GitResult.err('addConfigOnce: $e');
    }
  }
}
