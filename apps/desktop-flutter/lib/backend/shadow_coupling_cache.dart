// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: LicenseRef-WLCSL-1.0
// See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

import 'dart:convert';
import 'dart:io';

import 'atomic_write.dart';
import 'clock.dart';
import 'json_safety.dart';
import 'storage_paths.dart';

class ShadowCouplingCacheData {
  final String headHash;
  final DateTime discoveredAt;
  final int shadowCommitCount;
  final Map<String, Map<String, double>> jaccardEdges;
  final Map<String, int> edgeTypeCounts;

  const ShadowCouplingCacheData({
    required this.headHash,
    required this.discoveredAt,
    required this.shadowCommitCount,
    required this.jaccardEdges,
    this.edgeTypeCounts = const {},
  });

  bool get isFresh => isFreshAt(const SystemClock());

  /// Testable form of [isFresh]: the cache is fresh while fewer than 60
  /// whole minutes have elapsed between [discoveredAt] and [clock]'s now.
  /// [isFresh] delegates here with the real clock, so production behaviour
  /// is bit-identical to the old `DateTime.now()` check; a test injects a
  /// `FakeClock` to pin the 60-minute boundary.
  bool isFreshAt(Clock clock) =>
      clock.now().difference(discoveredAt).inMinutes < 60;

  Map<String, dynamic> toJson() => {
        'headHash': headHash,
        'discoveredAt': discoveredAt.toIso8601String(),
        'shadowCommitCount': shadowCommitCount,
        'edgeTypeCounts': edgeTypeCounts,
        'edges': {
          for (final e in jaccardEdges.entries)
            e.key: {
              for (final inner in e.value.entries)
                inner.key: inner.value,
            },
        },
      };

  factory ShadowCouplingCacheData.fromJson(Map<String, dynamic> json) {
    final edges = <String, Map<String, double>>{};
    final rawEdges = json['edges'];
    if (rawEdges is Map) {
      for (final e in rawEdges.entries) {
        if (e.key is! String || e.value is! Map) continue;
        final inner = <String, double>{};
        for (final ie in (e.value as Map).entries) {
          if (ie.key is! String || ie.value is! num) continue;
          inner[ie.key as String] = (ie.value as num).toDouble();
        }
        if (inner.isNotEmpty) edges[e.key as String] = inner;
      }
    }

    final typeCounts = <String, int>{};
    final rawTypes = json['edgeTypeCounts'];
    if (rawTypes is Map) {
      for (final e in rawTypes.entries) {
        if (e.key is String && e.value is int) {
          typeCounts[e.key as String] = e.value as int;
        }
      }
    }

    return ShadowCouplingCacheData(
      headHash: asStringOr(json['headHash'], ''),
      discoveredAt: DateTime.tryParse(asStringOr(json['discoveredAt'], '')) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      shadowCommitCount: asIntOr(json['shadowCommitCount'], 0),
      jaccardEdges: edges,
      edgeTypeCounts: typeCounts,
    );
  }

  ShadowCouplingCacheData mergeWith(ShadowCouplingCacheData newer) {
    final merged = <String, Map<String, double>>{};
    for (final e in jaccardEdges.entries) {
      merged[e.key] = Map.of(e.value);
    }
    for (final e in newer.jaccardEdges.entries) {
      final existing = merged.putIfAbsent(e.key, () => {});
      for (final ie in e.value.entries) {
        final prev = existing[ie.key] ?? 0;
        existing[ie.key] = prev > ie.value ? prev : ie.value;
      }
    }
    final mergedTypes = <String, int>{...edgeTypeCounts};
    for (final e in newer.edgeTypeCounts.entries) {
      final prev = mergedTypes[e.key] ?? 0;
      mergedTypes[e.key] = prev > e.value ? prev : e.value;
    }
    return ShadowCouplingCacheData(
      headHash: newer.headHash,
      discoveredAt: newer.discoveredAt,
      shadowCommitCount: shadowCommitCount > newer.shadowCommitCount
          ? shadowCommitCount
          : newer.shadowCommitCount,
      jaccardEdges: merged,
      edgeTypeCounts: mergedTypes,
    );
  }
}

class ShadowCouplingCache {
  /// Per-cache-file async mutex. Two callers that run the classic
  /// load→mergeWith→save cycle concurrently would otherwise both observe the
  /// pre-merge state and the second [save] would clobber the first's edges
  /// (a lost update). Serialising [save] per key — and RE-LOADING + folding
  /// inside the lock (see [_saveLocked]) — makes the read-modify-write
  /// convergent for ALL callers, so the caller's own pre-merge is belt-and-
  /// suspenders rather than load-bearing. Mirrors NudgeLedger's `_writeLock`,
  /// keyed by the cache-file hash so unrelated repos still save in parallel.
  static final Map<String, Future<void>> _saveLocks = {};

  static Future<ShadowCouplingCacheData?> load(String repoPath) async {
    try {
      final file = await _cacheFile(repoPath);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return ShadowCouplingCacheData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String repoPath, ShadowCouplingCacheData data) {
    final key = _fnv1a(repoPath);
    final prev = _saveLocks[key] ?? Future<void>.value();
    // Best-effort like the original: swallow write errors (the shadow cache
    // is a bonus signal, never load-bearing) and never let one save's failure
    // break the chain for the next.
    final next = prev.then((_) => _saveLocked(repoPath, data)).catchError((_) {});
    _saveLocks[key] = next;
    // Prune the tail once drained so the map stays bounded by live repos.
    next.whenComplete(() {
      if (identical(_saveLocks[key], next)) _saveLocks.remove(key);
    });
    return next;
  }

  /// The serialised body of [save]: under the per-key lock, re-load the
  /// current on-disk state and fold [data] into it before writing, so a save
  /// that raced another's write still keeps BOTH contributors' edges.
  ///
  /// mergeWith's freshness semantics (:74-100) are what make save-as-merge
  /// correct: within one generation (same [headHash]) it is a pure max-union
  /// on edges/counts — monotone, so re-applying on a reloaded state never
  /// regresses an edge — and it adopts the newer headHash/discoveredAt. A
  /// DIFFERENT headHash means a new generation (HEAD moved); the incoming save
  /// supersedes rather than unioning stale edges from a prior HEAD, matching
  /// both mergeWith's newer-wins head policy and the resolver's refusal to
  /// reuse coupling across a checkout/reset.
  static Future<void> _saveLocked(
      String repoPath, ShadowCouplingCacheData data) async {
    final current = await load(repoPath);
    final toWrite = (current == null || current.headHash != data.headHash)
        ? data
        : current.mergeWith(data);
    final file = await _cacheFile(repoPath);
    await writeFileAtomicString(
      file,
      const JsonEncoder.withIndent('  ').convert(toWrite.toJson()),
    );
  }

  static Future<File> _cacheFile(String repoPath) async {
    final dataDir = await StoragePaths.gdpuDataDir();
    final hash = _fnv1a(repoPath);
    return File(
      '${dataDir.path}${Platform.pathSeparator}'
      'shadow_cache${Platform.pathSeparator}$hash.json',
    );
  }

  static String _fnv1a(String input) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final bytes = utf8.encode(input.toLowerCase());
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    for (final b in bytes) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }
}
