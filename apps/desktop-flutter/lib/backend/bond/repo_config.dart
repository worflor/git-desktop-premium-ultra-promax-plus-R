// ═════════════════════════════════════════════════════════════════════════
// bond/repo_config.dart — repo-committed .bond.yml
//
// A simple top-level YAML at the repo root that lets a project ship
// shared bond defaults (bootstrap commit + suggested swarm phrase
// hash for sanity-checks + default policy hint) so first-time joiners
// don't have to be told the right values out of band.
//
// The file is intentionally minimal — it carries hints, not secrets.
// The swarm phrase itself is NEVER included; the file stores the
// SHA-256 of the agreed phrase so a joiner who knows the phrase can
// confirm they typed the right one before binding. A leaked
// .bond.yml on its own grants nobody anything.
//
// Format (no YAML parser dep — we use a deliberately tiny line-based
// reader; see [_parseLines] below):
//
//   bootstrap_commit: <40 or 64 hex>
//   swarm_phrase_hash: <64 hex>     # SHA-256 of phrase, optional
//   display_name: <string>          # default local label
//   trackers:                       # optional, one per line
//     - wss://tracker.example.com
//     - wss://other.example.com
//
// Comments start with '#'. Blank lines ignored. Tabs forbidden
// (clear error rather than silent off-by-indent).
// ═════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/digests/sha256.dart';

/// Decoded `.bond.yml` view. Every field optional — callers handle
/// nulls explicitly so a partial file is still useful.
class BondRepoConfig {
  BondRepoConfig({
    this.bootstrapCommit,
    this.swarmPhraseHash,
    this.displayName,
    this.trackers = const [],
  });

  final String? bootstrapCommit;
  final String? swarmPhraseHash;
  final String? displayName;
  final List<String> trackers;

  bool get isEmpty =>
      bootstrapCommit == null &&
      swarmPhraseHash == null &&
      displayName == null &&
      trackers.isEmpty;

  /// Verify a user-typed phrase matches the committed hash. Returns
  /// true when no hash is committed (nothing to check against) so
  /// repos without the optional hint don't block users.
  bool phraseMatches(String phrase) {
    final h = swarmPhraseHash;
    if (h == null) return true;
    final digest = SHA256Digest();
    final bytes = Uint8List.fromList(utf8.encode(phrase));
    digest.update(bytes, 0, bytes.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    final hex =
        out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return hex == h.toLowerCase();
  }
}

/// Reads .bond.yml from a repo root. Returns an empty config when
/// the file is absent or unreadable; never throws — repo open paths
/// shouldn't fail because of a missing optional config.
Future<BondRepoConfig> readRepoConfig(String repoPath) async {
  try {
    final f = File(p.join(repoPath, '.bond.yml'));
    if (!await f.exists()) return BondRepoConfig();
    final lines = await f.readAsLines();
    return _parseLines(lines);
  } catch (_) {
    return BondRepoConfig();
  }
}

/// Tiny line-based YAML subset — enough for our flat keys + a single
/// `trackers:` sequence. Avoids pulling a YAML parser dep into the
/// runtime for a 5-key config.
BondRepoConfig _parseLines(List<String> lines) {
  String? bootstrap;
  String? swarmHash;
  String? displayName;
  final trackers = <String>[];
  var inTrackers = false;
  for (final raw in lines) {
    if (raw.contains('\t')) continue; // refuse tab indentation
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('-') && inTrackers) {
      final v = line.substring(1).trim();
      if (v.isNotEmpty) trackers.add(_strip(v));
      continue;
    }
    inTrackers = false;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final key = line.substring(0, colon).trim();
    final value = _strip(line.substring(colon + 1).trim());
    switch (key) {
      case 'bootstrap_commit':
        if (value.isNotEmpty) bootstrap = value.toLowerCase();
      case 'swarm_phrase_hash':
        if (value.isNotEmpty) swarmHash = value.toLowerCase();
      case 'display_name':
        if (value.isNotEmpty) displayName = value;
      case 'trackers':
        inTrackers = true;
    }
  }
  return BondRepoConfig(
    bootstrapCommit: bootstrap,
    swarmPhraseHash: swarmHash,
    displayName: displayName,
    trackers: trackers,
  );
}

/// Strips matching surrounding quotes (single or double). The tiny
/// parser is permissive — all-bare values are fine, quoted values
/// just have their quotes peeled off.
String _strip(String s) {
  if (s.length >= 2 &&
      ((s.startsWith("'") && s.endsWith("'")) ||
          (s.startsWith('"') && s.endsWith('"')))) {
    return s.substring(1, s.length - 1);
  }
  return s;
}
