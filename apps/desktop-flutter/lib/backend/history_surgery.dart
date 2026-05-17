import 'dart:convert';
import 'dart:io';

import 'dtos.dart';
import 'git.dart' as git;
import 'git_result.dart';
import 'logos_git.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class TreeEntry {
  final String mode;
  final String type;
  final String hash;
  final String name;
  const TreeEntry(this.mode, this.type, this.hash, this.name);
}

class SurgeryImpact {
  final Set<String> allPaths;
  final int affectedCommits;
  final int totalCommits;
  final List<MapEntry<String, double>> couplingNeighbors;
  final List<String> affectedWorktrees;
  final List<String> affectedStashIndices;
  final List<String> affectedBranches;
  final Map<String, int> authorImpact;

  const SurgeryImpact({
    required this.allPaths,
    required this.affectedCommits,
    required this.totalCommits,
    this.couplingNeighbors = const [],
    this.affectedWorktrees = const [],
    this.affectedStashIndices = const [],
    this.affectedBranches = const [],
    this.authorImpact = const {},
  });

  double get affectedRatio =>
      totalCommits > 0 ? affectedCommits / totalCommits : 0;
}

class SurgeryProgress {
  final int processed;
  final int total;
  final String phase;
  final String? currentHash;
  const SurgeryProgress({
    required this.processed,
    required this.total,
    required this.phase,
    this.currentHash,
  });
}

class SurgeryResult {
  final bool success;
  final String? error;
  final int commitsRewritten;
  final int refsUpdated;
  final Set<String> displacedWorktrees;
  final String backupPrefix;
  final String oldHead;
  final String newHead;

  const SurgeryResult({
    required this.success,
    this.error,
    this.commitsRewritten = 0,
    this.refsUpdated = 0,
    this.displacedWorktrees = const {},
    this.backupPrefix = '',
    this.oldHead = '',
    this.newHead = '',
  });
}

// ---------------------------------------------------------------------------
// Git plumbing helpers
// ---------------------------------------------------------------------------

Future<GitResult<List<TreeEntry>>> readTree(
    String repo, String treeHash) async {
  final r = await Process.run(
    'git', ['cat-file', '-p', treeHash],
    workingDirectory: repo,
  );
  if (r.exitCode != 0) {
    return GitResult.err('cat-file failed: ${r.stderr.toString().trim()}');
  }
  final entries = <TreeEntry>[];
  for (final line in r.stdout.toString().split('\n')) {
    if (line.trim().isEmpty) continue;
    // Format: <mode> <type> <hash>\t<name>
    final tabIdx = line.indexOf('\t');
    if (tabIdx < 0) continue;
    final meta = line.substring(0, tabIdx).split(RegExp(r'\s+'));
    if (meta.length < 3) continue;
    entries.add(TreeEntry(meta[0], meta[1], meta[2], line.substring(tabIdx + 1)));
  }
  return GitResult.ok(entries);
}

Future<GitResult<String>> writeTree(
    String repo, List<TreeEntry> entries) async {
  final input = entries
      .map((e) => '${e.mode} ${e.type} ${e.hash}\t${e.name}')
      .join('\n');
  final r = await Process.start(
    'git', ['mktree'],
    workingDirectory: repo,
  );
  r.stdin.write(input);
  await r.stdin.close();
  final results = await Future.wait([
    r.stdout.transform(utf8.decoder).join(),
    r.stderr.transform(utf8.decoder).join(),
  ]);
  final exitCode = await r.exitCode;
  if (exitCode != 0) {
    return GitResult.err('mktree failed: ${results[1]}');
  }
  return GitResult.ok(results[0].trim());
}

Future<GitResult<String>> commitTree(
  String repo, {
  required String treeHash,
  required List<String> parentHashes,
  required String message,
  required String authorName,
  required String authorEmail,
  required String authorDate,
  required String committerName,
  required String committerEmail,
  required String committerDate,
}) async {
  final args = ['commit-tree', treeHash];
  for (final p in parentHashes) {
    args.addAll(['-p', p]);
  }
  final r = await Process.start(
    'git', args,
    workingDirectory: repo,
    environment: {
      ...Platform.environment,
      'GIT_AUTHOR_NAME': authorName,
      'GIT_AUTHOR_EMAIL': authorEmail,
      'GIT_AUTHOR_DATE': authorDate,
      'GIT_COMMITTER_NAME': committerName,
      'GIT_COMMITTER_EMAIL': committerEmail,
      'GIT_COMMITTER_DATE': committerDate,
    },
  );
  r.stdin.write(message);
  await r.stdin.close();
  final results = await Future.wait([
    r.stdout.transform(utf8.decoder).join(),
    r.stderr.transform(utf8.decoder).join(),
  ]);
  final exitCode = await r.exitCode;
  if (exitCode != 0) {
    return GitResult.err('commit-tree failed: ${results[1]}');
  }
  return GitResult.ok(results[0].trim());
}

Future<GitResult<void>> updateRef(
    String repo, String ref, String newHash) async {
  final r = await Process.run(
    'git', ['update-ref', ref, newHash],
    workingDirectory: repo,
  );
  if (r.exitCode != 0) {
    return GitResult.err('update-ref failed: ${r.stderr.toString().trim()}');
  }
  return const GitResult.ok(null);
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class HistorySurgeryEngine {
  final String repoPath;
  bool _cancelled = false;
  String lastBackupPrefix = '';
  HistorySurgeryEngine(this.repoPath);

  void cancel() => _cancelled = true;

  /// Chase renames across history and return all paths the file ever had.
  Future<Set<String>> discoverAllPaths(String currentPath) async {
    final paths = <String>{currentPath};
    final r = await Process.run(
      'git',
      ['log', '--all', '--follow', '--name-status', '--diff-filter=R',
       '--format=', '--', currentPath],
      workingDirectory: repoPath,
    );
    if (r.exitCode == 0) {
      for (final line in r.stdout.toString().split('\n')) {
        final parts = line.split('\t');
        if (parts.length >= 3 && parts[0].startsWith('R')) {
          paths.add(parts[1]);
          paths.add(parts[2]);
        }
      }
    }
    return paths;
  }

  /// Compute the full impact of removing the given paths from history.
  Future<SurgeryImpact> analyzeImpact(
    Set<String> allPaths, {
    LogosGit? engine,
  }) async {
    // Affected commits
    final affectedResult = await Process.run(
      'git',
      ['rev-list', '--all', '--count', '--', ...allPaths],
      workingDirectory: repoPath,
    );
    final affected = int.tryParse(
        affectedResult.stdout.toString().trim()) ?? 0;

    final totalResult = await Process.run(
      'git', ['rev-list', '--all', '--count'],
      workingDirectory: repoPath,
    );
    final total = int.tryParse(
        totalResult.stdout.toString().trim()) ?? 0;

    // Coupling neighbors from engine
    final neighbors = <MapEntry<String, double>>[];
    if (engine != null) {
      final coupling = engine.stats.coupling;
      for (final path in allPaths) {
        for (final entry in coupling.jaccardEntriesOf(path)) {
          if (!allPaths.contains(entry.key)) {
            neighbors.add(entry);
          }
        }
      }
      neighbors.sort((a, b) => b.value.compareTo(a.value));
    }

    // Worktrees
    final wtResult = await git.listWorktrees(repoPath);
    final affectedWt = <String>[];
    if (wtResult.ok && wtResult.data != null) {
      for (final wt in wtResult.data!) {
        if (!wt.isMain) affectedWt.add(wt.path);
      }
    }

    // Stashes
    final stashResult = await Process.run(
      'git', ['stash', 'list', '--format=%gd'],
      workingDirectory: repoPath,
    );
    final stashIndices = <String>[];
    if (stashResult.exitCode == 0) {
      for (final idx in stashResult.stdout.toString().trim().split('\n')) {
        if (idx.trim().isEmpty) continue;
        final showResult = await Process.run(
          'git', ['stash', 'show', '--name-only', idx.trim()],
          workingDirectory: repoPath,
        );
        if (showResult.exitCode == 0) {
          final files = showResult.stdout.toString().trim().split('\n');
          if (files.any((f) => allPaths.contains(f.trim()))) {
            stashIndices.add(idx.trim());
          }
        }
      }
    }

    // Branches — check all in parallel
    final branchResult = await git.listBranches(repoPath);
    final affectedBranches = <String>[];
    if (branchResult.ok && branchResult.data != null) {
      final checks = await Future.wait([
        for (final branch in branchResult.data!)
          Process.run(
            'git',
            ['log', '--oneline', '-1', branch.name, '--', ...allPaths],
            workingDirectory: repoPath,
          ).then((r) => (branch.name, r)),
      ]);
      for (final (name, r) in checks) {
        if (r.exitCode == 0 && r.stdout.toString().trim().isNotEmpty) {
          affectedBranches.add(name);
        }
      }
    }

    // Author impact
    final authorResult = await Process.run(
      'git',
      ['log', '--all', '--format=%aN', '--', ...allPaths],
      workingDirectory: repoPath,
    );
    final authorImpact = <String, int>{};
    if (authorResult.exitCode == 0) {
      for (final name in authorResult.stdout.toString().trim().split('\n')) {
        if (name.trim().isEmpty) continue;
        authorImpact[name.trim()] = (authorImpact[name.trim()] ?? 0) + 1;
      }
    }

    return SurgeryImpact(
      allPaths: allPaths,
      affectedCommits: affected,
      totalCommits: total,
      couplingNeighbors: neighbors.take(10).toList(),
      affectedWorktrees: affectedWt,
      affectedStashIndices: stashIndices,
      affectedBranches: affectedBranches,
      authorImpact: authorImpact,
    );
  }

  /// Create backup refs before rewriting.
  Future<String> createBackupRefs() async {
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final prefix = 'refs/manifold-surgery-backup/$ts';
    final r = await Process.run(
      'git',
      ['for-each-ref', '--format=%(refname) %(objectname)',
       'refs/heads/', 'refs/tags/'],
      workingDirectory: repoPath,
    );
    if (r.exitCode != 0) return prefix;
    for (final line in r.stdout.toString().trim().split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.trim().split(' ');
      if (parts.length < 2) continue;
      final refName = parts[0];
      final hash = parts[1];
      final backupRef = '$prefix/${refName.replaceAll('refs/', '')}';
      await updateRef(repoPath, backupRef, hash);
    }
    return prefix;
  }

  /// The core rewrite: walk all commits, prune target paths from trees,
  /// create new commits, update refs.
  Future<SurgeryResult> execute(
    Set<String> targetPaths,
    void Function(SurgeryProgress) onProgress,
  ) async {
    _treeCache.clear();
    try {
    return await _executeInner(targetPaths, onProgress);
    } finally {
      _treeCache.clear();
    }
  }

  Future<SurgeryResult> _executeInner(
    Set<String> targetPaths,
    void Function(SurgeryProgress) onProgress,
  ) async {
    // Pre-flight: reject dirty working tree
    final statusR = await Process.run(
      'git', ['status', '--porcelain'],
      workingDirectory: repoPath,
    );
    if (statusR.exitCode == 0 &&
        statusR.stdout.toString().trim().isNotEmpty) {
      return const SurgeryResult(
        success: false,
        error: 'Working tree has uncommitted changes. '
            'Commit or stash them before rewriting history.',
        oldHead: '',
        newHead: '',
      );
    }

    // Pre-flight: save old HEAD
    final oldHeadR = await Process.run(
      'git', ['rev-parse', 'HEAD'],
      workingDirectory: repoPath,
    );
    final oldHead = oldHeadR.stdout.toString().trim();

    // Backup refs
    onProgress(const SurgeryProgress(
      processed: 0, total: 0, phase: 'Backing up refs...',
    ));
    final backupPrefix = await createBackupRefs();
    lastBackupPrefix = backupPrefix;

    // Get all commits in topo order (oldest first)
    final revListR = await Process.run(
      'git', ['rev-list', '--topo-order', '--reverse',
             '--glob=refs/heads/*', '--glob=refs/tags/*'],
      workingDirectory: repoPath,
    );
    if (revListR.exitCode != 0) {
      return SurgeryResult(
        success: false,
        error: 'rev-list failed: ${revListR.stderr}',
        backupPrefix: backupPrefix,
        oldHead: oldHead,
        newHead: oldHead,
      );
    }
    final allCommits = revListR.stdout
        .toString()
        .trim()
        .split('\n')
        .where((s) => s.isNotEmpty)
        .toList();
    final total = allCommits.length;
    final oldToNew = <String, String>{};
    var rewrittenCount = 0;

    // Rewrite each commit
    _cancelled = false;
    for (var i = 0; i < allCommits.length; i++) {
      if (_cancelled) {
        return SurgeryResult(
          success: false,
          error: 'Cancelled after $i of $total commits. '
              'Backup refs are intact at $backupPrefix — '
              'rollback is available.',
          backupPrefix: backupPrefix,
          oldHead: oldHead,
          newHead: oldHead,
        );
      }
      final oldHash = allCommits[i];
      onProgress(SurgeryProgress(
        processed: i,
        total: total,
        phase: 'Rewriting commits...',
        currentHash: oldHash.substring(0, 7),
      ));

      SurgeryResult? _cancelResult() => _cancelled
          ? SurgeryResult(
              success: false,
              error: 'Cancelled at commit $i of $total. '
                  'Backup refs intact at $backupPrefix.',
              backupPrefix: backupPrefix,
              oldHead: oldHead,
              newHead: oldHead,
            )
          : null;

      // Read commit metadata
      final metaR = await Process.run(
        'git',
        ['cat-file', 'commit', oldHash],
        workingDirectory: repoPath,
      );
      final cr1 = _cancelResult();
      if (cr1 != null) return cr1;
      if (metaR.exitCode != 0) {
        return SurgeryResult(
          success: false,
          error: 'Failed to read commit $oldHash: ${metaR.stderr}',
          backupPrefix: backupPrefix,
          oldHead: oldHead,
          newHead: oldHead,
        );
      }
      final commitRaw = metaR.stdout.toString();
      final parsed = _parseCommitObject(commitRaw);

      // Read and prune tree
      final newTreeHash = await _pruneTree(parsed.treeHash, targetPaths);
      final cr2 = _cancelResult();
      if (cr2 != null) return cr2;

      // Map parent hashes to their rewritten versions
      final newParents = parsed.parentHashes
          .map((p) => oldToNew[p] ?? p)
          .toList();

      // Tree fully pruned — every file in this commit was a target.
      // Graft descendants onto the first parent. For parentless root
      // commits, create an empty-tree commit so the target files don't
      // survive in the reachable graph.
      if (newTreeHash.isEmpty) {
        if (newParents.isNotEmpty) {
          oldToNew[oldHash] = newParents.first;
        } else {
          final emptyR = await commitTree(
            repoPath,
            treeHash: '4b825dc642cb6eb9a060e54bf899d15006578022',
            parentHashes: const [],
            message: parsed.message,
            authorName: parsed.authorName,
            authorEmail: parsed.authorEmail,
            authorDate: parsed.authorDate,
            committerName: parsed.committerName,
            committerEmail: parsed.committerEmail,
            committerDate: parsed.committerDate,
          );
          oldToNew[oldHash] = emptyR.ok ? emptyR.data! : oldHash;
        }
        continue;
      }

      // Passthrough: if tree unchanged and all parents map to themselves,
      // this commit is untouched — skip the expensive commit-tree call.
      final treeUnchanged = newTreeHash == parsed.treeHash;
      final parentsUnchanged = newParents.length == parsed.parentHashes.length &&
          List.generate(newParents.length,
              (j) => newParents[j] == parsed.parentHashes[j])
              .every((same) => same);
      if (treeUnchanged && parentsUnchanged) {
        oldToNew[oldHash] = oldHash;
        continue;
      }

      // Create new commit
      final newCommitR = await commitTree(
        repoPath,
        treeHash: newTreeHash,
        parentHashes: newParents,
        message: parsed.message,
        authorName: parsed.authorName,
        authorEmail: parsed.authorEmail,
        authorDate: parsed.authorDate,
        committerName: parsed.committerName,
        committerEmail: parsed.committerEmail,
        committerDate: parsed.committerDate,
      );
      if (!newCommitR.ok) {
        return SurgeryResult(
          success: false,
          error: 'Failed to create commit for $oldHash: ${newCommitR.error}',
          backupPrefix: backupPrefix,
          oldHead: oldHead,
          newHead: oldHead,
        );
      }
      oldToNew[oldHash] = newCommitR.data!;
      rewrittenCount++;
    }

    // Update all refs
    onProgress(SurgeryProgress(
      processed: total,
      total: total,
      phase: 'Updating refs...',
    ));

    final refsR = await Process.run(
      'git',
      ['for-each-ref', '--format=%(refname) %(objectname) %(*objectname)',
       'refs/heads/', 'refs/tags/'],
      workingDirectory: repoPath,
    );
    var refsUpdated = 0;
    if (refsR.exitCode == 0) {
      for (final line in refsR.stdout.toString().trim().split('\n')) {
        if (line.trim().isEmpty) continue;
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final ref = parts[0];
        final objectHash = parts[1];
        final derefHash = parts.length > 2 && parts[2].isNotEmpty
            ? parts[2]
            : null;
        if (ref.contains('manifold-surgery-backup')) continue;
        // For annotated tags, look up the dereferenced commit hash.
        // For branches/lightweight tags, use the object hash directly.
        final commitHash = derefHash ?? objectHash;
        final newRefHash = oldToNew[commitHash];
        if (newRefHash != null && newRefHash != commitHash) {
          if (derefHash != null) {
            final tagName = ref.replaceFirst('refs/tags/', '');
            final tagMeta = await Process.run(
                'git', ['cat-file', 'tag', objectHash],
                workingDirectory: repoPath);
            final tagMsg = _extractTagMessage(tagMeta.stdout.toString());
            final taggerLine = _extractTaggerLine(tagMeta.stdout.toString());
            final delR = await Process.run('git', ['tag', '-d', tagName],
                workingDirectory: repoPath);
            if (delR.exitCode != 0) {
              // Tag locked or packed — fall back to ref update which
              // works for lightweight but at least doesn't silently
              // leave the old annotated tag in place.
              await updateRef(repoPath, ref, newRefHash);
            } else {
              final tagArgs = [
                'tag', '-a', tagName, '-m', tagMsg, newRefHash,
              ];
              final env = <String, String>{...Platform.environment};
              if (taggerLine != null) {
                env['GIT_COMMITTER_NAME'] = taggerLine.name;
                env['GIT_COMMITTER_EMAIL'] = taggerLine.email;
                env['GIT_COMMITTER_DATE'] = taggerLine.date;
              }
              final createR = await Process.run('git', tagArgs,
                  workingDirectory: repoPath, environment: env);
              if (createR.exitCode != 0) {
                await updateRef(repoPath, ref, newRefHash);
              }
            }
          } else {
            await updateRef(repoPath, ref, newRefHash);
          }
          refsUpdated++;
        }
      }
    }

    // Update HEAD if detached
    final headR = await Process.run(
      'git', ['symbolic-ref', 'HEAD'],
      workingDirectory: repoPath,
    );
    if (headR.exitCode != 0) {
      // Detached HEAD
      final mapped = oldToNew[oldHead];
      if (mapped != null) {
        await updateRef(repoPath, 'HEAD', mapped);
      }
    }

    final newHead = oldToNew[oldHead] ?? oldHead;

    // Checkout the new HEAD so working tree matches
    await Process.run(
      'git', ['checkout', '-f', 'HEAD'],
      workingDirectory: repoPath,
    );

    // Collect displaced worktrees
    final displaced = <String>{};
    final wtR = await git.listWorktrees(repoPath);
    if (wtR.ok && wtR.data != null) {
      for (final wt in wtR.data!) {
        if (!wt.isMain) displaced.add(wt.path);
      }
    }

    onProgress(SurgeryProgress(
      processed: total,
      total: total,
      phase: 'Complete',
    ));

    return SurgeryResult(
      success: true,
      commitsRewritten: rewrittenCount,
      refsUpdated: refsUpdated,
      displacedWorktrees: displaced,
      backupPrefix: backupPrefix,
      oldHead: oldHead,
      newHead: newHead,
    );
  }

  /// Verify no trace of target paths remains in history.
  Future<bool> verifyPurge(Set<String> targetPaths) async {
    final r = await Process.run(
      'git',
      ['log', '--all', '--oneline', '--diff-filter=ACDMR', '--',
       ...targetPaths],
      workingDirectory: repoPath,
    );
    return r.exitCode == 0 && r.stdout.toString().trim().isEmpty;
  }

  /// Restore refs from backup.
  Future<void> rollback(String backupPrefix) async {
    final r = await Process.run(
      'git',
      ['for-each-ref', '--format=%(refname) %(objectname)', backupPrefix],
      workingDirectory: repoPath,
    );
    if (r.exitCode != 0) return;
    for (final line in r.stdout.toString().trim().split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.trim().split(' ');
      if (parts.length < 2) continue;
      final backupRef = parts[0];
      final hash = parts[1];
      // refs/manifold-surgery-backup/<ts>/heads/main → refs/heads/main
      final originalRef = backupRef
          .replaceFirst(RegExp(r'^refs/manifold-surgery-backup/[^/]+/'), 'refs/');
      await updateRef(repoPath, originalRef, hash);
    }
    await Process.run(
      'git', ['checkout', '-f', 'HEAD'],
      workingDirectory: repoPath,
    );
  }

  // ── Internals ──

  static String _extractTagMessage(String catFileOutput) {
    final lines = catFileOutput.split('\n');
    var inBody = false;
    final body = <String>[];
    for (final line in lines) {
      if (inBody) {
        body.add(line);
      } else if (line.isEmpty) {
        inBody = true;
      }
    }
    final msg = body.join('\n').trim();
    return msg.isEmpty ? 'tag' : msg;
  }

  static ({String name, String email, String date})? _extractTaggerLine(
      String catFileOutput) {
    for (final line in catFileOutput.split('\n')) {
      if (!line.startsWith('tagger ')) continue;
      final rest = line.substring(7);
      final emailStart = rest.lastIndexOf('<');
      final emailEnd = rest.lastIndexOf('>');
      if (emailStart < 0 || emailEnd < 0) continue;
      final name = rest.substring(0, emailStart).trim();
      final email = rest.substring(emailStart + 1, emailEnd);
      final afterEmail = rest.substring(emailEnd + 1).trim();
      return (name: name, email: email, date: afterEmail);
    }
    return null;
  }

  final _treeCache = <String, String>{};

  Future<String> _pruneTree(
      String treeHash, Set<String> targets, [String prefix = '']) async {
    final cacheKey = '$treeHash:$prefix';
    final cached = _treeCache[cacheKey];
    if (cached != null) return cached;

    if (_cancelled) return treeHash;
    final treeR = await readTree(repoPath, treeHash);
    if (!treeR.ok || _cancelled) return treeHash;

    final kept = <TreeEntry>[];
    var changed = false;
    for (final entry in treeR.data!) {
      if (_cancelled) return treeHash;
      final fullPath = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (targets.contains(fullPath)) {
        changed = true;
        continue;
      }
      if (entry.type == 'tree') {
        final prunedHash = await _pruneTree(entry.hash, targets, fullPath);
        if (prunedHash.isEmpty) {
          changed = true;
        } else if (prunedHash != entry.hash) {
          kept.add(TreeEntry(entry.mode, entry.type, prunedHash, entry.name));
          changed = true;
        } else {
          kept.add(entry);
        }
      } else {
        kept.add(entry);
      }
    }

    if (!changed) {
      _treeCache[cacheKey] = treeHash;
      return treeHash;
    }
    if (kept.isEmpty) {
      _treeCache[cacheKey] = '';
      return '';
    }

    final newTreeR = await writeTree(repoPath, kept);
    final result = newTreeR.ok ? newTreeR.data! : treeHash;
    _treeCache[cacheKey] = result;
    return result;
  }

  _ParsedCommit _parseCommitObject(String raw) {
    final lines = raw.split('\n');
    var treeHash = '';
    final parents = <String>[];
    var authorName = '';
    var authorEmail = '';
    var authorDate = '';
    var committerName = '';
    var committerEmail = '';
    var committerDate = '';
    var i = 0;

    for (; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) {
        i++;
        break;
      }
      if (line.startsWith('tree ')) {
        treeHash = line.substring(5);
      } else if (line.startsWith('parent ')) {
        parents.add(line.substring(7));
      } else if (line.startsWith('author ')) {
        final m = _authorRe.firstMatch(line.substring(7));
        if (m != null) {
          authorName = m.group(1)!;
          authorEmail = m.group(2)!;
          authorDate = '${m.group(3)!} ${m.group(4)!}';
        }
      } else if (line.startsWith('committer ')) {
        final m = _authorRe.firstMatch(line.substring(10));
        if (m != null) {
          committerName = m.group(1)!;
          committerEmail = m.group(2)!;
          committerDate = '${m.group(3)!} ${m.group(4)!}';
        }
      }
    }

    final message = lines.sublist(i).join('\n');
    return _ParsedCommit(
      treeHash: treeHash,
      parentHashes: parents,
      message: message,
      authorName: authorName,
      authorEmail: authorEmail,
      authorDate: authorDate,
      committerName: committerName,
      committerEmail: committerEmail,
      committerDate: committerDate,
    );
  }

  static final _authorRe =
      RegExp(r'^(.+?) <(.+?)> (\d+) ([+-]\d{4})$');
}

class _ParsedCommit {
  final String treeHash;
  final List<String> parentHashes;
  final String message;
  final String authorName;
  final String authorEmail;
  final String authorDate;
  final String committerName;
  final String committerEmail;
  final String committerDate;

  const _ParsedCommit({
    required this.treeHash,
    required this.parentHashes,
    required this.message,
    required this.authorName,
    required this.authorEmail,
    required this.authorDate,
    required this.committerName,
    required this.committerEmail,
    required this.committerDate,
  });
}
