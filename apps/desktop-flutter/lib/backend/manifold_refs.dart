// ═════════════════════════════════════════════════════════════════════════
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
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'git_result.dart';

class ManifoldRefs {
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

  Map<String, String> get _gitEnv => {
        'GIT_AUTHOR_NAME': authorName,
        'GIT_AUTHOR_EMAIL': authorEmail,
        'GIT_COMMITTER_NAME': authorName,
        'GIT_COMMITTER_EMAIL': authorEmail,
      };

  /// Hash + write a blob, return its SHA. Content goes through stdin
  /// to handle arbitrary bytes safely.
  Future<GitResult<String>> writeBlob(String content) async {
    try {
      final p = await Process.start(
        'git',
        ['hash-object', '-w', '--stdin'],
        workingDirectory: repoPath,
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
      final r = await Process.run(
        'git',
        args,
        workingDirectory: repoPath,
        environment: _gitEnv,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
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
      final r = await Process.run(
        'git',
        args,
        workingDirectory: repoPath,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
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
      final r = await Process.run(
        'git',
        ['update-ref', '-d', ref],
        workingDirectory: repoPath,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
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
      final r = await Process.run(
        'git',
        ['rev-parse', '--verify', '--quiet', ref],
        workingDirectory: repoPath,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (r.exitCode != 0) return const GitResult.ok(null);
      final sha = (r.stdout as String).trim();
      return GitResult.ok(sha.isEmpty ? null : sha);
    } catch (e) {
      return GitResult.err('resolveRef: $e');
    }
  }

  /// Enumerate refs under [pattern] (e.g. `refs/manifold/desks/`).
  /// Returns refname → SHA pairs. Empty map when pattern matches
  /// nothing (not an error).
  Future<GitResult<Map<String, String>>> listRefs(String pattern) async {
    try {
      final r = await Process.run(
        'git',
        ['for-each-ref', '--format=%(refname) %(objectname)', pattern],
        workingDirectory: repoPath,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
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
      final r = await Process.run(
        'git',
        ['cat-file', 'blob', '$ref:$filename'],
        workingDirectory: repoPath,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (r.exitCode != 0) return const GitResult.ok(null);
      return GitResult.ok(r.stdout as String);
    } catch (e) {
      return GitResult.err('readRefBlob: $e');
    }
  }

  /// Allocate the next sequential integer from the shared counter ref.
  ///
  /// The counter lives as a single-blob tree at [ref] containing the
  /// integer plus a newline under [filename]. CAS on the ref handles
  /// concurrent allocations on the same machine: if another allocation
  /// landed between our resolveRef and updateRef, update-ref rejects
  /// and the caller gets a failure they can retry from. Starts at 1
  /// when the ref doesn't yet exist.
  ///
  /// DeskPrStore and DeskIssueStore both allocate from the same ref
  /// so PR-ids and issue-ids never collide. [commitLabel] is the
  /// caller-visible flavour ("desk-id" vs "id") baked into the commit
  /// message, so the audit log remains legible without coupling the
  /// stores to each other.
  Future<GitResult<int>> allocSequentialId({
    required String ref,
    required String filename,
    String commitLabel = 'id',
    int maxAttempts = 5,
  }) async {
    // CAS retry loop: a concurrent allocation (two windows, rapid
    // double-tap) can land between our resolveRef and updateRef and
    // cause update-ref to reject. Loop a handful of times with a tiny
    // randomised backoff so independent clients converge on distinct
    // ids. Other failures (writeBlob / mkTree / commitTree) aren't
    // caused by CAS so they bail immediately.
    var attempt = 0;
    String? lastError;
    while (attempt < maxAttempts) {
      attempt++;
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
      if (updR.ok) return GitResult.ok(next);
      lastError = updR.error;
      // Randomised 5–25ms backoff keeps two clients from lockstepping
      // into the same collision on the next attempt.
      await Future<void>.delayed(
          Duration(milliseconds: 5 + (attempt * 5)));
    }
    return GitResult.err(
        lastError ?? 'updateRef failed after $maxAttempts attempts');
  }

  /// Probe whether [headRef] would merge cleanly into [baseRef]. Uses
  /// `git merge-tree --write-tree` (git ≥ 2.38) which produces a tree
  /// in the object store and reports conflicts on stderr without
  /// touching the working tree or index.
  ///
  /// Returns 'MERGEABLE', 'CONFLICTING', or 'UNKNOWN' (when either ref
  /// doesn't resolve or merge-tree itself errors for reasons other
  /// than conflicts).
  Future<String> probeMergeable(String baseRef, String headRef) async {
    try {
      final r = await Process.run(
        'git',
        ['merge-tree', '--write-tree', '--name-only', baseRef, headRef],
        workingDirectory: repoPath,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
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
      final r = await Process.run(
        'git',
        ['config', '--get-all', configKey],
        workingDirectory: repoPath,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
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
      final r = await Process.run(
        'git',
        ['config', '--add', configKey, value],
        workingDirectory: repoPath,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (r.exitCode != 0) {
        return GitResult.err((r.stderr as String).trim());
      }
      return const GitResult.ok(null);
    } catch (e) {
      return GitResult.err('addConfigOnce: $e');
    }
  }
}
