import 'dart:convert';
import 'dart:io';

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

  bool get isFresh =>
      DateTime.now().difference(discoveredAt).inMinutes < 60;

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
      headHash: (json['headHash'] as String?) ?? '',
      discoveredAt: DateTime.tryParse(
              (json['discoveredAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      shadowCommitCount: (json['shadowCommitCount'] as int?) ?? 0,
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

  static Future<void> save(
      String repoPath, ShadowCouplingCacheData data) async {
    try {
      final file = await _cacheFile(repoPath);
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data.toJson()),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (_) {}
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
