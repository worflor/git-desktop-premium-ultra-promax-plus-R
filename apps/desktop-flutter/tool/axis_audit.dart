// tool/axis_audit.dart — dump the REAL eigenAddress-histogram axis for a repo.
//
// Part of the coupling-axis audit: the temporal-holdout jury needs the axis's
// actual outputs (not a python proxy) to judge whether the char-level spectral
// histogram earns its place in the overlay. This harness replicates, faithfully:
//   * the gyat bootstrap's CharCoupling corpus (all tracked files, cap 800,
//     binary-probed, ≤256KB — mirrors lib/backend/gyat.dart _bootstrapInIsolate
//     + repo_blob_walk defaults), and
//   * computeSpectralCoupling's per-file histogram construction (per line
//     eigenAddress → 256-bin normalized histogram, files ≤256KB).
// It deliberately avoids git.dart/repo_blob_walk.dart (they pull in Flutter via
// diagnostics); the tiny walk is inlined so `dart run tool/axis_audit.dart`
// works headless.
//
// Usage: dart run tool/axis_audit.dart <repoPath> <out.json> <prefix|-> <ext[,ext...]>

import 'dart:convert';
import 'dart:io';

import 'package:git_desktop/backend/logos_core.dart'
    show CharCoupling, eigenAddress;

const int _maxBytes = 256 * 1024;
const int _couplingFileCap = 800;
const int _auditFileCap = 1500;

List<String> _tracked(String repo) {
  final r = Process.runSync('git', ['-C', repo, 'ls-files']);
  if (r.exitCode != 0) return const [];
  return [
    for (final l in const LineSplitter().convert(r.stdout as String))
      if (l.trim().isNotEmpty) l.trim(),
  ];
}

String? _readText(String repo, String rel) {
  final f = File('$repo${Platform.pathSeparator}'
      '${rel.split('/').join(Platform.pathSeparator)}');
  if (!f.existsSync()) return null;
  RandomAccessFile raf;
  try {
    raf = f.openSync();
  } catch (_) {
    return null;
  }
  try {
    final len = raf.lengthSync();
    if (len > _maxBytes) return null;
    final bytes = raf.readSync(len);
    final probe = len < 8192 ? len : 8192;
    for (var i = 0; i < probe; i++) {
      if (bytes[i] == 0) return null; // binary
    }
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  } finally {
    raf.closeSync();
  }
}

void main(List<String> args) {
  if (args.length < 4) {
    stderr.writeln(
        'usage: dart run tool/axis_audit.dart <repo> <out.json> <prefix|-> <ext[,ext]>');
    exit(2);
  }
  final repo = args[0];
  final outPath = args[1];
  final prefix = args[2] == '-' ? null : args[2];
  final exts = args[3].split(',');

  final tracked = _tracked(repo);
  if (tracked.isEmpty) {
    stderr.writeln('no tracked files in $repo');
    exit(1);
  }

  // 1) CharCoupling corpus — all tracked text files, capped like the app.
  final sources = <String>[];
  for (final rel in tracked) {
    if (sources.length >= _couplingFileCap) break;
    final text = _readText(repo, rel);
    if (text != null && text.isNotEmpty) sources.add(text);
  }
  final coupling = CharCoupling.fromSources(sources);
  stderr.writeln('coupling built from ${sources.length} sources');

  // 2) Per-file eigenAddress histograms over the audited language subset.
  final out = <String, List<double>>{};
  var audited = 0;
  for (final rel in tracked) {
    if (audited >= _auditFileCap) break;
    if (prefix != null && !rel.startsWith(prefix)) continue;
    if (!exts.any(rel.endsWith)) continue;
    audited++;
    final text = _readText(repo, rel);
    if (text == null) continue;
    final hist = List<double>.filled(256, 0.0);
    var total = 0;
    for (final line in text.split('\n')) {
      final addr = eigenAddress(line, coupling);
      if (addr >= 0) {
        hist[addr] += 1.0;
        total++;
      }
    }
    if (total < 2) continue;
    for (var i = 0; i < 256; i++) {
      hist[i] /= total;
    }
    out[rel] = hist;
  }
  File(outPath).writeAsStringSync(jsonEncode(out));
  stderr.writeln('wrote ${out.length} histograms -> $outPath');
}
