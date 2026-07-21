// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Law-based coverage for BlobLoader + BlobRef (lib/backend/blob_loader.dart)
// and its magic_bytes.dart content-class probe, both previously untested.
//
// Uses real ScratchRepo working trees (never a fake FS) so
// `BlobLoader.instance.load` exercises the exact `File`/`FileStat` and
// `git cat-file` paths production code uses.
//
// `BlobLoader.instance` is a process-wide singleton with its own internal
// LRU cache. Every test below gives it a distinct working-tree path or
// object hash (a fresh ScratchRepo temp dir per test), so no test can read
// another test's cached entry.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/blob_loader.dart';
import 'package:git_desktop/backend/magic_bytes.dart';

import '../support/scratch_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlobRef.cacheKeyWithStat', () {
    test('objectHash-based key is the hash itself, independent of repoPath',
        () {
      const refA = BlobRef(repoPath: '/repo/a', objectHash: 'deadbeef');
      const refB = BlobRef(repoPath: '/repo/completely/different/b',
          objectHash: 'deadbeef');
      expect(refA.cacheKeyWithStat(null), 'deadbeef');
      expect(refA.cacheKeyWithStat(null), refB.cacheKeyWithStat(null),
          reason: 'the hash-keyed cache key must not depend on repoPath');
    });

    test('working-tree key embeds mtime AND size; a null stat is total',
        () async {
      final repo = await ScratchRepo.create(name: 'blob_key');
      addTearDown(repo.dispose);
      final path = '${repo.dir.path}${Platform.pathSeparator}k.txt';
      await File(path).writeAsBytes(utf8.encode('x'));
      final stat = await FileStat.stat(path);

      final ref = BlobRef(repoPath: repo.dir.path, workingTreePath: path);
      // Size is part of the key, not just mtime — coarse filesystem
      // timestamp granularity means two writes in one tick share an mtime,
      // and folding in size makes them collide only if they also share a
      // byte length (see the cache-staleness law below).
      expect(ref.cacheKeyWithStat(stat),
          'wt:$path:${stat.modified.microsecondsSinceEpoch}:${stat.size}');
      expect(ref.cacheKeyWithStat(null), 'wt:$path:0:-1',
          reason: 'a null FileStat must be total (mtime 0, size -1), not throw');
    });
  });

  group('BlobLoader.load — working tree', () {
    test('returns BlobLoaded with correct size and a content class matching '
        'probeContentClass of the first 32 bytes', () async {
      final repo = await ScratchRepo.create(name: 'blob_load_file');
      addTearDown(repo.dispose);
      final path = '${repo.dir.path}${Platform.pathSeparator}text.txt';
      const content =
          'hello world, this is plain ascii content for a blob-loader test.\n';
      await File(path).writeAsBytes(utf8.encode(content));

      final ref = BlobRef(repoPath: repo.dir.path, workingTreePath: path);
      final result = await BlobLoader.instance.load(ref);

      expect(result, isA<BlobLoaded>());
      final data = (result as BlobLoaded).data;
      final onDisk = await File(path).readAsBytes();
      expect(data.sizeBytes, onDisk.length);
      final header = onDisk.length >= 32
          ? Uint8List.sublistView(onDisk, 0, 32)
          : onDisk;
      expect(data.contentClass, probeContentClass(header));
    });

    test('nonexistent working-tree path -> BlobFailed', () async {
      final repo = await ScratchRepo.create(name: 'blob_missing');
      addTearDown(repo.dispose);
      final ref = BlobRef(
        repoPath: repo.dir.path,
        workingTreePath:
            '${repo.dir.path}${Platform.pathSeparator}does-not-exist.txt',
      );
      final result = await BlobLoader.instance.load(ref);
      expect(result, isA<BlobFailed>());
    });
  });

  group('BlobLoader.load — via git object hash', () {
    test('reads identical bytes to the working-tree copy', () async {
      final repo = await ScratchRepo.create(name: 'blob_load_hash');
      addTearDown(repo.dispose);
      const relPath = 'hashed.txt';
      const content =
          'content that must round-trip byte-for-byte through git cat-file.\n';
      await repo.writeFile(relPath, content);
      final hash = await repo.gitOk(['hash-object', '-w', relPath]);

      final ref = BlobRef(repoPath: repo.dir.path, objectHash: hash);
      final result = await BlobLoader.instance.load(ref);

      expect(result, isA<BlobLoaded>());
      final data = (result as BlobLoaded).data;
      expect(utf8.decode(data.bytes), content);
    });
  });

  group('BlobLoader.load — degenerate ref', () {
    test('neither objectHash nor workingTreePath -> BlobFailed', () async {
      const ref = BlobRef(repoPath: '/anything');
      final result = await BlobLoader.instance.load(ref);
      expect(result, isA<BlobFailed>());
    });
  });

  group('content-class classification via BlobLoader', () {
    test('a real PNG signature in the first 32 bytes classifies as '
        'image/PNG', () async {
      final repo = await ScratchRepo.create(name: 'blob_png');
      addTearDown(repo.dispose);
      final path = '${repo.dir.path}${Platform.pathSeparator}fake.png';
      final bytes = Uint8List(40);
      const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      for (var i = 0; i < sig.length; i++) {
        bytes[i] = sig[i];
      }
      await File(path).writeAsBytes(bytes);

      final ref = BlobRef(repoPath: repo.dir.path, workingTreePath: path);
      final result = await BlobLoader.instance.load(ref);
      expect(result, isA<BlobLoaded>());
      final data = (result as BlobLoaded).data;
      expect(data.contentClass.cls, ContentClass.image);
      expect(data.contentClass.formatName, 'PNG');
    });

    test('plain ascii text classifies as unknown', () async {
      final repo = await ScratchRepo.create(name: 'blob_text_unknown');
      addTearDown(repo.dispose);
      final path = '${repo.dir.path}${Platform.pathSeparator}plain.txt';
      await File(path).writeAsBytes(
          utf8.encode('just some ordinary source code, not a magic blob.\n'));

      final ref = BlobRef(repoPath: repo.dir.path, workingTreePath: path);
      final result = await BlobLoader.instance.load(ref);
      expect(result, isA<BlobLoaded>());
      final data = (result as BlobLoaded).data;
      expect(data.contentClass.cls, ContentClass.unknown);
    });
  });

  group('cache-staleness law', () {
    test(
      'a rewrite with different content must never be served from a stale '
      'cache entry — a same-key collision would be a real correctness bug',
      () async {
        final repo = await ScratchRepo.create(name: 'blob_staleness');
        addTearDown(repo.dispose);
        final path = '${repo.dir.path}${Platform.pathSeparator}stale.txt';

        await File(path).writeAsBytes(utf8.encode('first version of file\n'));
        final ref = BlobRef(repoPath: repo.dir.path, workingTreePath: path);
        final first = await BlobLoader.instance.load(ref);
        expect(first, isA<BlobLoaded>());

        // Overwrite with materially different content (different length,
        // different bytes). cacheKeyWithStat is keyed on mtime — if this
        // filesystem's mtime resolution lets both writes land on the same
        // recorded timestamp, `load` will return the FIRST write's bytes
        // here, which is stale-cache data corruption, not a cache hit.
        await File(path)
            .writeAsBytes(utf8.encode('second version — totally different '
                'content and length\n'));
        final second = await BlobLoader.instance.load(ref);
        expect(second, isA<BlobLoaded>());
        final secondBytes = (second as BlobLoaded).data.bytes;

        expect(
          utf8.decode(secondBytes),
          'second version — totally different content and length\n',
          reason: 'BlobLoader served stale cached bytes after the file was '
              'rewritten — its mtime-based cache key collided across two '
              'different writes to the same path.',
        );
      },
    );
  });
}
