// review_shadow.dart — "this was reverted before" footgun evidence.
//
// Git remembers what was undone. discoverShadowHistory mines reverts,
// hard resets, and abandoned branches — work that was written and then
// taken back. When the current diff touches a file that lives in that
// shadow, recurrence is a reason to look twice: the area has resisted a
// change before. This channel surfaces the flag and nothing more — it
// never claims the new change repeats the old mistake, only that the
// ground here has shifted before.
//
// discoverShadowHistory is a cold, multi-call git scan (revert grep +
// reflog walk + abandoned-branch diff). We cache its per-path inversion
// in-memory per repo so only the first review in a window pays it, and
// wrap the call in a timeout so a slow/huge history degrades to "no
// shadow evidence" rather than stalling the review.

import 'shadow_history.dart'
    show ShadowCommit, ShadowHistoryResult, ShadowType, discoverShadowHistory;

class _ShadowCacheEntry {
  _ShadowCacheEntry(this.byPath, this.at);
  final Map<String, Set<ShadowType>> byPath;
  final DateTime at;
}

final Map<String, _ShadowCacheEntry> _shadowCache = {};

/// In-memory freshness window. HEAD rarely moves within an active
/// review session; staleness only affects a bonus warning channel.
const Duration _shadowTtl = Duration(minutes: 10);

/// Visible for testing — clears the per-repo memo.
void resetShadowFlagCache() => _shadowCache.clear();

/// Map each of [paths] that appears in the repo's shadow history to the
/// set of ways it was undone. Paths with no shadow are omitted.
Future<Map<String, Set<ShadowType>>> shadowFlagsForPaths(
  String repoPath,
  Set<String> paths, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (paths.isEmpty) return const {};

  final cached = _shadowCache[repoPath];
  Map<String, Set<ShadowType>> all;
  if (cached != null && DateTime.now().difference(cached.at) < _shadowTtl) {
    all = cached.byPath;
  } else {
    final result = await discoverShadowHistory(repoPath).timeout(
      timeout,
      onTimeout: () => ShadowHistoryResult(
        commits: const <ShadowCommit>[],
        discoveredAt: DateTime.now(),
        headHash: '',
      ),
    );
    all = <String, Set<ShadowType>>{};
    for (final c in result.commits) {
      for (final f in c.files) {
        (all[f] ??= <ShadowType>{}).add(c.type);
      }
    }
    _shadowCache[repoPath] = _ShadowCacheEntry(all, DateTime.now());
  }

  final out = <String, Set<ShadowType>>{};
  for (final p in paths) {
    final flags = all[p];
    if (flags != null && flags.isNotEmpty) out[p] = flags;
  }
  return out;
}

/// Severity rank for ordering: a revert is harder evidence than a
/// reset, which is harder than an abandoned branch.
int shadowRank(Set<ShadowType> flags) {
  var r = 0;
  if (flags.contains(ShadowType.revert)) r += 4;
  if (flags.contains(ShadowType.reset)) r += 2;
  if (flags.contains(ShadowType.abandonedBranch)) r += 1;
  return r;
}

/// Render the `<shadow_history>` body (no wrapper tag). '' when empty.
String formatShadowBlock(Map<String, Set<ShadowType>> flags) {
  if (flags.isEmpty) return '';
  final n = flags.length;
  final buf = StringBuffer();
  buf.writeln(
    'status: populated · $n changed file${n == 1 ? '' : 's'} carry prior '
    'instability — git has reverted, reset, or abandoned work here before. '
    'The ground has shifted at these paths once already; that is a reason '
    'to read closely, not a verdict on this change.',
  );
  final ordered = flags.entries.toList()
    ..sort((a, b) => shadowRank(b.value).compareTo(shadowRank(a.value)));
  for (final e in ordered) {
    final labels = <String>[];
    if (e.value.contains(ShadowType.revert)) labels.add('reverted before');
    if (e.value.contains(ShadowType.reset)) labels.add('reset before');
    if (e.value.contains(ShadowType.abandonedBranch)) {
      labels.add('abandoned in a dropped branch');
    }
    buf.writeln('${e.key} — ${labels.join(' · ')}');
  }
  return buf.toString();
}
