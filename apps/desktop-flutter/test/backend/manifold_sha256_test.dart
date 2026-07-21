// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// End-to-end proof that the Manifold ref plumbing works in a git repository
// using the SHA-256 object format (`git init --object-format=sha256`), whose
// object IDs are 64 lowercase-hex chars instead of SHA-1's 40 — and whose
// null-object OID (git's CAS-on-non-existence sentinel) is 64 zeros, not 40.
//
// A full DeskPrStore.create → read round-trip exercises the whole plumbing
// with genuine 64-char OIDs: writeBlob → mkTree → commitTree →
// createRef (the zero-OID CAS) → resolveRef. The zero-OID CAS is the subtle
// part: git rejects a 40-zero expected-old value in a SHA-256 repo as "not a
// valid old SHA1", so create() only succeeds if the sentinel is sized to the
// repo's format. A direct createRef/createRef pair then proves the CAS also
// REJECTS a second create at 64-char width (not merely that writes succeed).
//
// Guarded: skips cleanly if the installed git lacks sha256 support; on a git
// that has it (git >= 2.29-ish) the test runs for real.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr_store.dart';
import 'package:git_desktop/backend/manifold_refs.dart';

import '../support/scratch_repo.dart';

/// Probes whether the installed git can create a SHA-256 repository. Uses a
/// throwaway temp dir so a git without the feature just reports unsupported
/// rather than failing the suite.
Future<bool> _sha256Supported() async {
  final dir = await Directory.systemTemp.createTemp('sha256_probe_');
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

ManifoldRefs _refs(ScratchRepo repo) => ManifoldRefs(
      repoPath: repo.dir.path,
      authorName: 'tester',
      authorEmail: 'tester@manifold.local',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DeskPrStore create/read round-trips in a SHA-256 repo (64-char OIDs '
      '+ zero-OID CAS)', () async {
    if (!await _sha256Supported()) {
      markTestSkipped('installed git lacks --object-format=sha256 support');
      return;
    }

    final repo =
        await ScratchRepo.create(name: 'sha256', objectFormat: 'sha256');
    try {
      final refs = _refs(repo);
      final store = DeskPrStore(refs);

      // ── create: the whole plumbing, driven with real 64-char OIDs ──────
      final created = await store.create(
        branch: 'feat/x',
        title: 'Feature X',
        body: 'Adds X',
        baseRef: 'main',
        authorIdentity: 'tester',
      );
      expect(created.ok, isTrue,
          reason: 'create must succeed in a sha256 repo — a wrong-width '
              'zero-OID CAS would fail here with "not a valid old SHA1": '
              '${created.error}');
      expect(created.data!.deskId, 1);

      // The repo really is sha256: the desk ref and the id-counter ref both
      // resolve to 64-hex tips.
      final deskTip = await repo.gitOk(['rev-parse', DeskPrStore.refFor('feat/x')]);
      expect(deskTip.length, 64, reason: 'desk ref tip should be a sha256 OID');
      final counterTip =
          await repo.gitOk(['rev-parse', 'refs/manifold/_id-counter']);
      expect(counterTip.length, 64,
          reason: 'the zero-OID CAS minted the counter ref at sha256 width');

      // ── read: the record round-trips through the 64-char object store ──
      final read = await store.read('feat/x');
      expect(read.ok, isTrue, reason: read.error);
      expect(read.data, isNotNull);
      expect(read.data!.title, 'Feature X');
      expect(read.data!.body, 'Adds X');
      expect(read.data!.deskId, 1);

      // ── the DeskPrStore-level duplicate guard still holds ──────────────
      final dup = await store.create(
        branch: 'feat/x',
        title: 'again',
        body: '',
        baseRef: 'main',
        authorIdentity: 'tester',
      );
      expect(dup.ok, isFalse, reason: 'a duplicate PR must be refused');

      // ── the zero-OID CAS itself, at 64-char width ──────────────────────
      // A real 64-char CommitOid to point a fresh ref at.
      final tip = (await refs.resolveRef(DeskPrStore.refFor('feat/x'))).data!;
      expect(tip.toString().length, 64);
      final fresh = LiveManifoldRef.issue(90001); // an otherwise-unused ref

      final firstCreate = await refs.createRef(ref: fresh, newSha: tip);
      expect(firstCreate.ok, isTrue,
          reason: 'createRef on an absent ref must pass its zero-OID CAS '
              '(a 40-zero sentinel would be rejected here): '
              '${firstCreate.error}');

      final secondCreate = await refs.createRef(ref: fresh, newSha: tip);
      expect(secondCreate.ok, isFalse,
          reason: 'the zero-OID CAS must REJECT a second create — this proves '
              'the 64-zero sentinel is a VALID old-value that git compares '
              'against, not merely that writes succeed');

      // ── the individual plumbing primitives all emit 64-char OIDs ───────
      final blob = await refs.writeBlob('sha256 blob\n');
      expect(blob.ok, isTrue, reason: blob.error);
      expect(blob.data!.toString().length, 64);
      final tree = await refs.mkTree({'f.txt': blob.data!});
      expect(tree.ok, isTrue, reason: tree.error);
      expect(tree.data!.toString().length, 64);
      final commit = await refs.commitTree(
          treeSha: tree.data!, message: 'sha256 commit');
      expect(commit.ok, isTrue, reason: commit.error);
      expect(commit.data!.toString().length, 64);
    } finally {
      await repo.dispose();
    }
  });
}
