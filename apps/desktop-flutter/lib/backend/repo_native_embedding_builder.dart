// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// repo_native_embedding_builder.dart — build a RepoNativeEmbedding for a whole
// repository, off the UI isolate.
//
// The embedding must see the ENTIRE repo's identifier co-occurrence to learn
// which identifiers mean alike — training on a handful of changed files would
// yield noise. So it's a repo-level artifact, built once and cached by HEAD
// (see RepoEmbeddingState), exactly like the co-change matrix.
//
// Split of work: the git probes (rev-parse, ls-files) run on the caller so they
// pass through the app's git concurrency controller; the heavy part — reading
// every indexable file and running the Lanczos — runs inside `Isolate.run` so
// the ~5–15s repo walk never touches the UI isolate. Inputs and the returned
// embedding are plain data (strings, maps, typed lists), so they cross the
// isolate boundary cheaply.

import 'dart:convert' show LineSplitter;
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'engram_file_index.dart' show isEngramIndexablePath;
import 'git.dart' show runGit;
import 'repo_native_embedding.dart';

/// A built embedding tagged with the HEAD it was trained at, so the per-repo
/// cache can tell when it's stale. [embedding] is null when the repo is too
/// small to yield one — a valid, cacheable outcome (callers just skip the
/// signal) rather than an error.
class RepoEmbeddingResult {
  final RepoNativeEmbedding? embedding;
  final String headHash;
  const RepoEmbeddingResult(this.embedding, this.headHash);
}

/// Same identifier-run shape used everywhere else in the content path.
final RegExp _identRun = RegExp(r'[A-Za-z_][A-Za-z0-9_]{2,40}');

/// Read cap per file — the top 16KB carries the imports + public surface, which
/// is where identifier density lives (matches engram_file_index's cap).
const int _kMaxFileBytes = 16 * 1024;

/// Identifier-run cap per file so one giant generated file can't dominate the
/// co-occurrence counts.
const int _kMaxTokensPerFile = 600;

/// Build the repo-native embedding for [repoPath]. Never throws for the normal
/// "no signal" cases — a repo with no HEAD, no tracked files, or too small a
/// vocabulary returns a result with a null embedding.
Future<RepoEmbeddingResult> computeRepoEmbedding(String repoPath) async {
  final headProbe = await runGit(repoPath, ['rev-parse', 'HEAD']);
  final headHash =
      headProbe.exitCode == 0 ? headProbe.stdout.toString().trim() : '';

  final lsProbe = await runGit(repoPath, ['ls-files']);
  if (lsProbe.exitCode != 0) return RepoEmbeddingResult(null, headHash);

  final relPaths = <String>[];
  for (final line in const LineSplitter().convert(lsProbe.stdout.toString())) {
    final rel = line.trim();
    if (rel.isEmpty || !isEngramIndexablePath(rel)) continue;
    relPaths.add(rel);
  }
  if (relPaths.length < 3) return RepoEmbeddingResult(null, headHash);

  final embedding =
      await Isolate.run(() => _buildFromDisk(repoPath, relPaths));
  return RepoEmbeddingResult(embedding, headHash);
}

/// Isolate body: read each file's identifier runs and build the embedding.
/// Top-level so it captures only the sendable [repoPath] / [relPaths].
RepoNativeEmbedding? _buildFromDisk(String repoPath, List<String> relPaths) {
  final fileTokens = <String, List<String>>{};
  for (final relPath in relPaths) {
    final abs = p.join(repoPath, p.joinAll(relPath.split('/')));
    final f = File(abs);
    if (!f.existsSync()) continue;
    String content;
    try {
      final raf = f.openSync();
      try {
        final length = raf.lengthSync();
        final readN = length < _kMaxFileBytes ? length : _kMaxFileBytes;
        content = String.fromCharCodes(raf.readSync(readN));
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      continue;
    }
    final toks = <String>[];
    for (final m in _identRun.allMatches(content)) {
      toks.add(m.group(0)!);
      if (toks.length >= _kMaxTokensPerFile) break;
    }
    if (toks.length >= 3) fileTokens[relPath] = toks;
  }
  return RepoNativeEmbedding.build(fileTokens);
}
