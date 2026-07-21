// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// tool/en_audit.dart — dump the REAL EN-axis content signal for a repo.
//
// Final trial of the coupling-axis audit: LogosGit's EN axis compares per-file
// engram K-vectors (identifier runs → GloVe(300) → complex pairing → AR(2) fit
// → K cosine). This harness replicates buildEngramFileIndex's construction
// exactly (16KB read cap, identifier runs, 256-token cap, same encoder) but
// loads the brain/glove assets straight from disk instead of rootBundle so it
// runs headless. Output: {loPath: {hiPath: kCosine}} for the audited subset.
//
// Usage: dart run tool/en_audit.dart <repoPath> <out.json> <prefix|-> <ext[,ext...]>

import 'dart:convert';
import 'dart:io';

import 'package:git_desktop/backend/engram_brain.dart' show EngramBrain;
import 'package:git_desktop/backend/engram_glove.dart' show EngramGlove;
import 'package:git_desktop/backend/engram_hunk_encoder.dart'
    show EngramHunkEncoder, HunkKVector;

const int _maxFileBytes = 16 * 1024;
const int _maxTokensPerFile = 256;
const int _auditFileCap = 400;
final RegExp _identifierRun = RegExp(r'[A-Za-z_][A-Za-z0-9_]{1,40}');

List<String> _tracked(String repo) {
  final r = Process.runSync('git', ['-C', repo, 'ls-files']);
  if (r.exitCode != 0) return const [];
  return [
    for (final l in const LineSplitter().convert(r.stdout as String))
      if (l.trim().isNotEmpty) l.trim(),
  ];
}

Future<void> main(List<String> args) async {
  if (args.length < 4) {
    stderr.writeln(
        'usage: dart run tool/en_audit.dart <repo> <out.json> <prefix|-> <ext[,ext]>');
    exit(2);
  }
  final repo = args[0];
  final outPath = args[1];
  final prefix = args[2] == '-' ? null : args[2];
  final exts = args[3].split(',');

  // Assets read from disk (cwd = package root when `dart run` here).
  final brain = EngramBrain.loadBytes(
      File('assets/engram/alexandria.endb').readAsBytesSync());
  final glove = EngramGlove.loadBytes(
      File('assets/engram/glove300.bin').readAsBytesSync());
  final encoder = EngramHunkEncoder(brain: brain, glove: glove);

  final kv = <String, HunkKVector>{};
  var audited = 0;
  for (final rel in _tracked(repo)) {
    if (audited >= _auditFileCap) break;
    if (prefix != null && !rel.startsWith(prefix)) continue;
    if (!exts.any(rel.endsWith)) continue;
    audited++;
    final f = File('$repo${Platform.pathSeparator}'
        '${rel.split('/').join(Platform.pathSeparator)}');
    if (!f.existsSync()) continue;
    String content;
    try {
      final raf = f.openSync();
      try {
        final len = raf.lengthSync();
        final readN = len < _maxFileBytes ? len : _maxFileBytes;
        content = String.fromCharCodes(raf.readSync(readN));
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      continue;
    }
    final tokens = <String>[];
    for (final m in _identifierRun.allMatches(content)) {
      tokens.add(m.group(0)!);
      if (tokens.length >= _maxTokensPerFile) break;
    }
    if (tokens.isEmpty) continue;
    final v = encoder.encode(tokens);
    if (v != null) kv[rel] = v;
  }
  stderr.writeln('K-vectors for ${kv.length}/$audited files');

  final out = <String, Map<String, double>>{};
  final files = kv.keys.toList()..sort();
  for (var i = 0; i < files.length; i++) {
    for (var j = i + 1; j < files.length; j++) {
      final c = EngramHunkEncoder.cosine(kv[files[i]], kv[files[j]]);
      (out[files[i]] ??= {})[files[j]] = c;
    }
  }
  File(outPath).writeAsStringSync(jsonEncode(out));
  stderr.writeln('wrote ${files.length} files pairwise -> $outPath');
}
