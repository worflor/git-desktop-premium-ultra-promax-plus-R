import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/storage_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  group('StoragePaths.deleteIfExists', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('manifold-purge-test-');
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('removes a non-empty directory tree', () async {
      final nested = Directory(p.join(sandbox.path, 'a', 'b', 'c'));
      await nested.create(recursive: true);
      await File(p.join(nested.path, 'leaf.txt')).writeAsString('hi');
      await File(p.join(sandbox.path, 'top.json')).writeAsString('{}');

      await StoragePaths.deleteIfExists(sandbox);

      expect(await sandbox.exists(), isFalse);
    });

    test('is a no-op on a missing directory', () async {
      final ghost = Directory(p.join(sandbox.path, 'never-existed'));
      // Sanity-check the precondition.
      expect(await ghost.exists(), isFalse);
      // Must not throw.
      await StoragePaths.deleteIfExists(ghost);
    });

    test('is idempotent', () async {
      await File(p.join(sandbox.path, 'data.json')).writeAsString('{}');
      await StoragePaths.deleteIfExists(sandbox);
      // Second call after the dir is already gone — also a no-op.
      await StoragePaths.deleteIfExists(sandbox);
      expect(await sandbox.exists(), isFalse);
    });
  });
}
