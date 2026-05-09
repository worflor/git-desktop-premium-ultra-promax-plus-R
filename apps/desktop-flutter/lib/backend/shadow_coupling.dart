import 'file_coupling.dart';
import 'shadow_history.dart';

FileCouplingMatrix? computeShadowCoupling(ShadowHistoryResult shadows) {
  if (shadows.commits.isEmpty) return null;

  final fileCommits = <String, double>{};
  final pairCount = <String, Map<String, double>>{};

  for (final commit in shadows.commits) {
    final w = commit.confidence;
    final files = commit.files;
    for (final f in files) {
      fileCommits[f] = (fileCommits[f] ?? 0) + w;
    }
    for (var i = 0; i < files.length; i++) {
      final a = files[i];
      for (var j = i + 1; j < files.length; j++) {
        final b = files[j];
        final lo = a.compareTo(b) <= 0 ? a : b;
        final hi = a.compareTo(b) <= 0 ? b : a;
        pairCount.putIfAbsent(lo, () => {})[hi] =
            (pairCount[lo]?[hi] ?? 0) + w;
      }
    }
  }

  if (pairCount.isEmpty) return null;

  final jaccard = <String, Map<String, double>>{};
  for (final loEntry in pairCount.entries) {
    final lo = loEntry.key;
    for (final hiEntry in loEntry.value.entries) {
      final hi = hiEntry.key;
      final co = hiEntry.value;
      final na = fileCommits[lo] ?? 0;
      final nb = fileCommits[hi] ?? 0;
      final denom = na + nb - co;
      if (denom <= 0) continue;
      final j = co / denom;
      if (j <= 0) continue;
      jaccard.putIfAbsent(lo, () => {})[hi] = j;
    }
  }

  if (jaccard.isEmpty) return null;

  return FileCouplingMatrix(
    jaccard: jaccard,
    headHash: 'shadow:${shadows.headHash}',
    commitsAnalyzed: shadows.commits.length,
  );
}
