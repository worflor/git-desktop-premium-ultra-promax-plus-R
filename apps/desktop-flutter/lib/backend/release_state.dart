// RELEASE STATE — git's read on what kind of project this is.
//
// A snapshot of the repo's release landscape derived from `git
// describe`, the tag list, and the distance from HEAD to the latest
// tag. Surfaces into AI prompts (muse, review, commit message) as a
// `<release_state>` block so the model contextualises stakes:
// pre-release solo work vs. tagged production codebase shapes the
// register of every claim downstream.
//
// Pure git observables — no heuristics. Every field is the
// straightforward parsing of a single subprocess output.

import 'dart:io';

import 'peek_warm_cache.dart';

final PeekWarmCache<ReleaseState> _releaseCache = PeekWarmCache<ReleaseState>(
  bootstrap: collectReleaseState,
  // Any cached result for the active repo key is valid — empty included.
  // peek()/loadOrAwait() already gate on the repo key, so a commitless or
  // inaccessible repo's empty ReleaseState is a real answer worth keeping;
  // rejecting it on `!isEmpty` re-spawned describe + tag-list on every load.
  matchesKey: (cached, key) => true,
  label: 'release_state',
);

ReleaseState? peekReleaseState(String repoPath) =>
    _releaseCache.peek(repoPath);

void warmReleaseState(String repoPath) => _releaseCache.warm(repoPath);

Future<ReleaseState> loadReleaseState(String repoPath) =>
    _releaseCache.loadOrAwait(repoPath);

/// Snapshot of a repo's release landscape, derived from real git
/// observables. Every field is null/empty when git couldn't surface
/// the corresponding observable (no tags exist, no HEAD, repo
/// inaccessible) so callers can degrade gracefully.
class ReleaseState {
  /// Output of `git describe --tags --always`. One of three shapes:
  ///   * bare 7-char sha — repo has no tags
  ///   * exact tag name — HEAD itself is tagged
  ///   * `<tag>-<N>-g<sha>` — HEAD is N commits past the named tag
  /// The shape is itself a release-state signal.
  final String describe;

  /// Total number of tags reachable from HEAD. Zero = no releases ever.
  final int tagCount;

  /// Most-recent tag's name (by version-sort), or null when no tags.
  final String? latestTag;

  /// Wall-clock age of [latestTag] as reported by `git log -1 --format=%cr`
  /// — e.g. "3 weeks ago". Null when no tags exist.
  final String? latestTagAge;

  /// Number of commits between [latestTag] and HEAD. Zero = HEAD is
  /// the tagged commit; null = no latestTag.
  final int? commitsSinceLatestTag;

  /// Up to [_kTagSampleSize] most-recent tags by version sort, oldest
  /// first within the sample. Lets the synthesis layer surface release
  /// cadence ("every ~10 days for the last six releases").
  final List<String> recentTags;

  const ReleaseState({
    required this.describe,
    required this.tagCount,
    required this.latestTag,
    required this.latestTagAge,
    required this.commitsSinceLatestTag,
    required this.recentTags,
  });

  static const ReleaseState empty = ReleaseState(
    describe: '',
    tagCount: 0,
    latestTag: null,
    latestTagAge: null,
    commitsSinceLatestTag: null,
    recentTags: <String>[],
  );

  bool get isEmpty => describe.isEmpty && tagCount == 0;
  bool get hasReleases => tagCount > 0;
  bool get headIsTagged =>
      latestTag != null && (commitsSinceLatestTag ?? -1) == 0;
}

const int _kTagSampleSize = 6;

/// Collect the release-state snapshot. Two git subprocesses run
/// concurrently (`describe` + `tag --list`); then, only when a latest
/// tag exists, two more run sequentially after the tag list resolves
/// (`log -1 --format=%cr` for the tag's age, `rev-list --count` for
/// commits-since-tag). The whole call takes well under 100ms on a warm
/// disk and never throws — git failures collapse to [ReleaseState.empty].
/// Safe to call from any phase that wants the release context (muse
/// brainstorm, muse synthesis, review prompts, commit composer).
Future<ReleaseState> collectReleaseState(String repoPath) async {
  if (repoPath.trim().isEmpty) return ReleaseState.empty;
  try {
    final results = await Future.wait([
      _runGit(repoPath, ['describe', '--tags', '--always']),
      _runGit(repoPath, [
        'tag',
        '--list',
        '--sort=-version:refname',
      ]),
    ]);
    final describe = (results[0] ?? '').trim();
    final tagListRaw = (results[1] ?? '').trim();
    if (describe.isEmpty && tagListRaw.isEmpty) return ReleaseState.empty;

    final tagLines = tagListRaw
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.trim())
        .toList(growable: false);
    final tagCount = tagLines.length;
    final latestTag = tagLines.isEmpty ? null : tagLines.first;

    // Sample list is oldest-first within the top-N so cadence reads
    // chronologically when the synthesis prompt surfaces them.
    final recentSlice = tagLines.take(_kTagSampleSize).toList().reversed.toList(
        growable: false);

    String? latestTagAge;
    int? commitsSinceLatestTag;
    if (latestTag != null) {
      final ageOut = await _runGit(
        repoPath,
        ['log', '-1', '--format=%cr', latestTag],
      );
      latestTagAge = ageOut?.trim();
      if (latestTagAge != null && latestTagAge.isEmpty) latestTagAge = null;

      final countOut = await _runGit(
        repoPath,
        ['rev-list', '--count', '$latestTag..HEAD'],
      );
      final parsed = int.tryParse((countOut ?? '').trim());
      commitsSinceLatestTag = parsed;
    }

    return ReleaseState(
      describe: describe,
      tagCount: tagCount,
      latestTag: latestTag,
      latestTagAge: latestTagAge,
      commitsSinceLatestTag: commitsSinceLatestTag,
      recentTags: recentSlice,
    );
  } catch (_) {
    return ReleaseState.empty;
  }
}

/// Format a release-state block for AI prompts. Empty when the snapshot
/// is empty so callers can omit the block cleanly. Lines are stable
/// `key=value` pairs the model can cite verbatim ("the repo has 0
/// tags") without paraphrasing into invention.
String formatReleaseStateBlock(ReleaseState state) {
  if (state.isEmpty) return '';
  final buf = StringBuffer();
  buf.writeln('describe=${state.describe}');
  buf.writeln('tag_count=${state.tagCount}');
  if (!state.hasReleases) {
    buf.writeln('release_history=none — no tags exist on HEAD');
    return buf.toString().trimRight();
  }
  if (state.latestTag != null) {
    buf.writeln('latest_tag=${state.latestTag}');
  }
  if (state.latestTagAge != null) {
    buf.writeln('latest_tag_age=${state.latestTagAge}');
  }
  if (state.commitsSinceLatestTag != null) {
    buf.writeln('commits_since_latest_tag=${state.commitsSinceLatestTag}');
  }
  if (state.headIsTagged) {
    buf.writeln('head_is_tagged=true');
  }
  if (state.recentTags.length >= 2) {
    buf.writeln('recent_tags=${state.recentTags.join(", ")}');
  }
  return buf.toString().trimRight();
}

Future<String?> _runGit(String repoPath, List<String> args) async {
  try {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: repoPath,
    );
    if (result.exitCode != 0) return null;
    return result.stdout?.toString();
  } catch (_) {
    return null;
  }
}
