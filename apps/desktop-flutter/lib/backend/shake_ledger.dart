// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// shake_ledger.dart — what has already been examined, and at what content.
//
// A whole-repository audit cannot finish in one run, and the wrong way to
// admit that is a cap: "the top 20 regions" reports success while quietly
// leaving the rest unexamined forever. The right way is the way `make`
// handles the same problem — remember what was done and against WHAT, and let
// repeated runs converge on a fixpoint. A quiet repository eventually has
// nothing pending; a busy one has exactly the work its churn created.
//
// KEYED BY BLOB OID, NOT BY TIME OR BY REGION.
//
//   * Not by time. A modification timestamp on Windows has one-second
//     granularity and this codebase has already been bitten by treating it as
//     an identity. Content addressing has no such problem: git computed the
//     name from the bytes.
//   * Not by region. Regions come out of a spectral partition whose labels
//     are unstable across rebuilds (k-means over eigenrows, sign flips, near
//     degenerate eigenvalues). Keyed by region, a re-partition would silently
//     invalidate or double-count coverage. Keyed by file, an unstable
//     partition costs a little planning churn and cannot corrupt the record.
//
// So "has this been examined?" is `ledger[path] == currentBlobOid`, which is
// exact, cheap, and survives renames the only honest way — as a new path with
// no record, because a renamed file genuinely has not been examined under
// its new name and its content may have moved with it.

import 'dart:convert';
import 'dart:io';

import 'admitted_git.dart' show admitFileText;
import 'atomic_write.dart';
import 'storage_paths.dart';

/// One examined file, as of one content.
class ShakeRecord {
  /// Blob OID the file had when it was last examined.
  final String blobOid;

  /// ISO-8601 UTC of the examination. Informational only — never the
  /// staleness key. Reporting "audited three weeks ago" is useful; deciding
  /// with it is not.
  final String at;

  /// Findings the audit reported against this file, for reporting how much a
  /// region has historically yielded.
  final int findings;

  const ShakeRecord({
    required this.blobOid,
    required this.at,
    this.findings = 0,
  });

  Map<String, dynamic> toJson() => {
        'oid': blobOid,
        'at': at,
        if (findings > 0) 'findings': findings,
      };

  static ShakeRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final oid = raw['oid'];
    if (oid is! String || oid.isEmpty) return null;
    return ShakeRecord(
      blobOid: oid,
      at: raw['at'] is String ? raw['at'] as String : '',
      findings: raw['findings'] is int ? raw['findings'] as int : 0,
    );
  }
}

/// The examined frontier for one repository.
class ShakeLedger {
  final Map<String, ShakeRecord> _byPath;

  ShakeLedger(Map<String, ShakeRecord> byPath) : _byPath = byPath;

  ShakeLedger.empty() : _byPath = {};

  int get examinedCount => _byPath.length;

  ShakeRecord? recordFor(String path) => _byPath[path];

  /// Whether [path] has been examined AT [blobOid].
  ///
  /// False for a file never examined and for one whose content has moved
  /// since — which are different situations to a reporter and the same
  /// situation to a planner.
  bool isFresh(String path, String blobOid) =>
      _byPath[path]?.blobOid == blobOid;

  /// Record an examination. Replaces any prior record for the path: the
  /// ledger holds a frontier, not a history.
  void mark(String path, String blobOid, String at, {int findings = 0}) {
    _byPath[path] =
        ShakeRecord(blobOid: blobOid, at: at, findings: findings);
  }

  /// Drop records for paths that no longer exist, so a deleted file cannot
  /// keep claiming coverage. Returns how many went.
  int prune(Set<String> livePaths) {
    final gone = _byPath.keys.where((p) => !livePaths.contains(p)).toList();
    for (final p in gone) {
      _byPath.remove(p);
    }
    return gone.length;
  }

  Map<String, dynamic> toJson() => {
        for (final e in _byPath.entries) e.key: e.value.toJson(),
      };

  static ShakeLedger fromJson(Object? raw) {
    if (raw is! Map) return ShakeLedger.empty();
    final out = <String, ShakeRecord>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final rec = ShakeRecord.fromJson(entry.value);
      if (key is String && rec != null) out[key] = rec;
    }
    return ShakeLedger(out);
  }
}

/// Where ledgers live: ONE DOCUMENT PER REPOSITORY.
///
/// The first cut kept every repository in a single JSON file keyed by path,
/// and that shape carried a data-loss bug that no amount of care at the call
/// site would have fixed. Reading tolerates failure — a corrupt or
/// budget-declined read yields an empty map, so a sweep can still run — and
/// writing then merged into that empty map and replaced the file. One
/// unreadable moment, and every OTHER repository's record was gone.
///
/// The guard ("refuse to save when the read failed") would have worked and
/// would have been the wrong fix: it leaves a shared mutable document where a
/// single fault has repository-wide blast radius, and relies on remembering
/// the rule forever. Per-repository files remove the shared document, so
/// there is no cross-repository loss to guard against. The read also stops
/// being unbounded-by-construction: it is now one repository's frontier
/// rather than every repository ever swept.
class ShakeLedgerStore {
  static Future<Directory> _dir() async {
    final data = await StoragePaths.gdpuDataDir();
    return Directory('${data.path}${Platform.pathSeparator}shake');
  }

  /// A filename that is stable for a repository, legal on every platform,
  /// and still recognisable to a human poking around the data directory.
  ///
  /// A repository path contains separators, colons and spaces, so it cannot
  /// be a filename. The digest carries identity; the readable prefix is
  /// courtesy, and never identity — two repositories with the same folder
  /// name stay distinct because the digest covers the whole path.
  static String fileNameFor(String repoPath) {
    final normalized = repoPath.replaceAll('\\', '/').toLowerCase();
    var hash = 0xcbf29ce484222325; // FNV-1a 64, matching the codebase's habit
    for (final unit in normalized.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final digest = hash.toRadixString(16).padLeft(16, '0');
    final leaf = normalized.split('/').where((s) => s.isNotEmpty).lastOrNull;
    final readable = (leaf ?? 'repo').replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
    final trimmed =
        readable.length > 40 ? readable.substring(0, 40) : readable;
    return '$trimmed.$digest.json';
  }

  static Future<File> _fileFor(String repoPath) async =>
      File('${(await _dir()).path}${Platform.pathSeparator}'
          '${fileNameFor(repoPath)}');

  static Future<ShakeLedger> load(String repoPath) async {
    try {
      final f = await _fileFor(repoPath);
      if (!await f.exists()) return ShakeLedger.empty();
      // Gated: a ledger grows with the repository it describes, so it is
      // still a read whose size is a property of somebody else's project.
      // Size MEASURED off the stat, as that seam requires.
      final admitted = await admitFileText(
        (await f.stat()).size,
        () => f.readAsString(),
      );
      if (!admitted.ran) return ShakeLedger.empty();
      return ShakeLedger.fromJson(jsonDecode(admitted.value!));
    } catch (_) {
      // A ledger that cannot be read costs re-examination, never
      // correctness — every conclusion is re-derived from the repository.
      // Now that the document is per-repository, this can only ever cost
      // THIS repository's memory.
      return ShakeLedger.empty();
    }
  }

  static Future<void> save(String repoPath, ShakeLedger ledger) async {
    await (await _dir()).create(recursive: true);
    await writeFileAtomicString(
      await _fileFor(repoPath),
      const JsonEncoder.withIndent('  ').convert(ledger.toJson()),
    );
  }

  /// Forget everything known about [repoPath] — the "start the sweep over"
  /// action.
  static Future<void> forget(String repoPath) async {
    try {
      final f = await _fileFor(repoPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
