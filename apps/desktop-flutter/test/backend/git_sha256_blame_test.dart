// getFileBlame across the SHA-1 / SHA-256 object-format boundary.
//
// git's blame porcelain header is `<oid> <orig-line> <final-line> [group]`,
// where <oid> is 40 hex in a SHA-1 repo and 64 hex in a SHA-256 one. The
// parser regex used to hardcode `[0-9a-f]{40}`, so in a sha256 repo NO header
// line matched and getFileBlame silently returned an empty list — a blank
// blame gutter with no error. This pins the widened `{40,64}` parse against a
// real repo of each format.
//
// Guarded: skips cleanly if the installed git lacks sha256 support.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';

import '../support/scratch_repo.dart';

Future<bool> _sha256Supported() async {
  final dir = await Directory.systemTemp.createTemp('sha256_blame_probe_');
  try {
    final r =
        await Process.run('git', ['init', '--object-format=sha256', dir.path]);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {/* best-effort */}
  }
}

Future<void> _blameRoundTrips(ScratchRepo repo, {required int oidWidth}) async {
  await repo.writeFile('poem.txt', 'first line\nsecond line\nthird line\n');
  await repo.stageAll();
  final head = await repo.commitAll('add poem');
  expect(head.length, oidWidth,
      reason: 'precondition: this repo really uses $oidWidth-char OIDs');

  final blame = await getFileBlame(repo.dir.path, 'poem.txt');
  expect(blame.ok, isTrue, reason: 'blame failed: ${blame.error}');
  final lines = blame.data!;
  expect(lines, hasLength(3),
      reason: 'every line must be attributed — an empty result is the '
          'hardcoded-{40} regression at $oidWidth-char width');
  expect(lines.map((b) => b.lineContent).toList(),
      ['first line', 'second line', 'third line']);
  expect(lines.map((b) => b.lineNumber).toList(), [1, 2, 3]);
  for (final b in lines) {
    expect(b.commitHash.length, oidWidth,
        reason: 'the parsed commit hash must be the full object name');
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(b.commitHash), isTrue);
  }
}

void main() {
  test('getFileBlame attributes every line in a SHA-1 repo (control)',
      () async {
    final repo = await ScratchRepo.create(name: 'blame_sha1');
    try {
      await _blameRoundTrips(repo, oidWidth: 40);
    } finally {
      await repo.dispose();
    }
  });

  test('getFileBlame attributes every line in a SHA-256 repo', () async {
    if (!await _sha256Supported()) {
      markTestSkipped('installed git lacks --object-format=sha256 support');
      return;
    }
    final repo =
        await ScratchRepo.create(name: 'blame_sha256', objectFormat: 'sha256');
    try {
      await _blameRoundTrips(repo, oidWidth: 64);
    } finally {
      await repo.dispose();
    }
  });
}
