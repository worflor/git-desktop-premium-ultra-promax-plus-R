// Durability + correctness coverage for the atomic-write primitive
// (lib/backend/atomic_write.dart). Two axes:
//
//  1. The tmp+rename choreography round-trips bytes EXACTLY (the property
//     every consumer store relies on), and an overwrite atomically replaces
//     the prior target.
//  2. The best-effort parent-directory fsync added for rename durability
//     RUNS without throwing on the host OS — a real fsync on POSIX, a
//     documented no-op on Windows — and stays best-effort (a bogus path
//     never throws). The full torn-write crash-consistency suite
//     (test/fuzz/torn_write_crash_consistency_test.dart) is the regression
//     guard that the durability change did not weaken crash-atomicity.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/atomic_write.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('atomic_write_test_');
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {/* best-effort temp cleanup */}
  });

  group('round-trip fidelity', () {
    test('writeFileAtomic writes the exact bytes given', () async {
      final target = File(p.join(root.path, 'sub', 'blob.bin'));
      final bytes = Uint8List.fromList(
          List<int>.generate(512, (i) => (i * 37 + 11) & 0xFF));
      await writeFileAtomic(target, bytes);
      expect(await target.exists(), isTrue);
      expect(await target.readAsBytes(), bytes);
      // No temp leftovers under the parent.
      final leftovers = target.parent
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty, reason: 'temp file must be renamed away');
    });

    test('writeFileAtomicString round-trips text byte-identically', () async {
      final target = File(p.join(root.path, 'text.json'));
      const contents = '{"k":"café ☃ 日本語","n":42}\n';
      await writeFileAtomicString(target, contents);
      expect(await target.readAsString(), contents);
    });

    test('a second write atomically replaces the prior target', () async {
      final target = File(p.join(root.path, 'snap.txt'));
      await writeFileAtomicString(target, 'OLD');
      await writeFileAtomicString(target, 'NEW-and-longer');
      expect(await target.readAsString(), 'NEW-and-longer');
    });
  });

  group('best-effort parent-directory fsync', () {
    test('runs without throwing on the host OS for a real directory', () {
      // POSIX: a real open+fsync+close. Windows: a documented no-op. Either
      // way it must never throw.
      expect(() => fsyncParentDirBestEffort(root.path), returnsNormally);
    });

    test('is best-effort: a nonexistent path never throws', () {
      final bogus = p.join(root.path, 'does', 'not', 'exist');
      expect(() => fsyncParentDirBestEffort(bogus), returnsNormally);
    });

    test('writeFileAtomic (which invokes the dir fsync) never throws for it',
        () async {
      // The dir fsync runs as the last step of every writeFileAtomic. Drive a
      // few writes and confirm the whole primitive completes cleanly on this
      // OS — a fsync failure must be swallowed, not surfaced.
      for (var i = 0; i < 3; i++) {
        final target = File(p.join(root.path, 'd$i', 'f.bin'));
        await expectLater(
            writeFileAtomic(target, List<int>.filled(64, i)), completes);
        expect(await target.readAsBytes(), List<int>.filled(64, i));
      }
    });
  });
}
