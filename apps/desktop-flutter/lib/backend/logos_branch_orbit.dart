import 'dart:async';
import 'dart:convert';

import 'engram_fit.dart' show BranchOrbit, computeBranchOrbit;
import 'file_coupling.dart' show logCommitSeparator;
import 'git.dart' show runGitProbe;
import 'lru_cache.dart';

final LruCache<String, _BranchOrbitCacheEntry> _branchOrbitCache =
    LruCache<String, _BranchOrbitCacheEntry>(maxSize: 8);
final Map<String, Future<BranchOrbit?>> _branchOrbitInflight = {};
const Duration _kBranchOrbitCacheTtl = Duration(seconds: 5);

class _BranchOrbitCacheEntry {
  final DateTime fetchedAt;
  final BranchOrbit? orbit;

  const _BranchOrbitCacheEntry({
    required this.fetchedAt,
    required this.orbit,
  });
}

Future<BranchOrbit?> probeLogosBranchOrbit(String repositoryPath) {
  final now = DateTime.now();
  final cached = _branchOrbitCache.get(repositoryPath);
  if (cached != null &&
      now.difference(cached.fetchedAt) <= _kBranchOrbitCacheTtl) {
    return Future.value(cached.orbit);
  }
  final inflight = _branchOrbitInflight[repositoryPath];
  if (inflight != null) return inflight;

  final future = _probeBranchOrbitImpl(repositoryPath, now);
  _branchOrbitInflight[repositoryPath] = future;
  future.whenComplete(() => _branchOrbitInflight.remove(repositoryPath));
  return future;
}

Future<BranchOrbit?> _probeBranchOrbitImpl(
  String repositoryPath,
  DateTime now,
) async {
  try {
    final logResult = await runGitProbe(repositoryPath, [
      'log',
      '-n',
      '30',
      '--no-merges',
      '--name-only',
      '--format=$logCommitSeparator%H',
    ]);
    if (logResult.exitCode != 0) {
      _cacheBranchOrbit(repositoryPath, now, null);
      return null;
    }
    final commitSets = <Set<String>>[];
    Set<String>? current;
    for (final line
        in const LineSplitter().convert(logResult.stdout.toString())) {
      if (line.startsWith(logCommitSeparator)) {
        if (current != null && current.isNotEmpty) {
          commitSets.add(current);
        }
        current = <String>{};
        continue;
      }
      final trimmed = line.trim();
      if (trimmed.isEmpty || current == null) continue;
      current.add(trimmed.replaceAll('\\', '/'));
    }
    if (current != null && current.isNotEmpty) {
      commitSets.add(current);
    }
    final orbit = commitSets.isEmpty
        ? null
        : computeBranchOrbit(commitSets.reversed.toList());
    _cacheBranchOrbit(repositoryPath, now, orbit);
    return orbit;
  } catch (_) {
    _cacheBranchOrbit(repositoryPath, now, null);
    return null;
  }
}

void _cacheBranchOrbit(
  String repositoryPath,
  DateTime now,
  BranchOrbit? orbit,
) {
  _branchOrbitCache.put(
    repositoryPath,
    _BranchOrbitCacheEntry(fetchedAt: now, orbit: orbit),
  );
}

double logosTemperatureMultiplierFromOrbit(BranchOrbit? orbit) {
  if (orbit == null || !orbit.hasSignal) return 1.0;
  final magnitude = orbit.trendSlope.abs().clamp(0.0, 0.25);
  if (orbit.isConverging) {
    return (1.0 - magnitude).clamp(0.75, 1.0);
  }
  if (orbit.isDiverging) {
    return (1.0 + magnitude).clamp(1.0, 1.25);
  }
  return 1.0;
}
