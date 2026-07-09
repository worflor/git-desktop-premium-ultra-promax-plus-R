// Verifies the ScratchRepo/RepoOp harness itself against real git:
//   • basic write→commit→clean-tree flow,
//   • branch/checkout/merge keeps HEAD resolvable and refs/heads/main intact,
//   • the core safety oracle — running genRepoOpSequence for several seeds
//     through applyOp must never leave HEAD unresolvable or the object
//     database corrupt (`git fsck`), regardless of how many individual ops
//     in the sequence themselves failed (conflicts, bogus refs, etc.),
//   • dispose() actually removes the temp dir.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scratch_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScratchRepo basics', () {
    test('write + commit two files leaves a resolvable HEAD and clean tree',
        () async {
      final repo = await ScratchRepo.create(name: 'basics');
      try {
        await repo.writeFile('a.txt', 'hello\n');
        await repo.writeFile('dir/b.txt', 'world\r\nwith CRLF\r\n');
        final sha = await repo.commitAll('add a.txt and dir/b.txt');

        expect(sha, isNotEmpty);
        expect(await repo.head(), equals(sha));
        expect(await repo.isClean(), isTrue);
        expect(await repo.currentBranch(), equals('main'));
      } finally {
        await repo.dispose();
      }
    });
  });

  group('branch + checkout + merge', () {
    test('diverge on a branch and merge back into main', () async {
      final repo = await ScratchRepo.create(name: 'branch_merge');
      try {
        await repo.writeFile('base.txt', 'base\n');
        await repo.commitAll('base commit');

        await repo.gitOk(['checkout', '-b', 'feature']);
        await repo.writeFile('feature.txt', 'feature work\n');
        await repo.commitAll('feature commit');
        expect(await repo.currentBranch(), equals('feature'));

        await repo.gitOk(['checkout', 'main']);
        expect(await repo.currentBranch(), equals('main'));
        expect(await repo.head(), isNotNull);

        final mergeResult = await repo.git(['merge', '--no-edit', 'feature']);
        expect(mergeResult.exitCode, 0, reason: mergeResult.stderr.toString());

        expect(await repo.head(), isNotNull);
        expect(await File('${repo.dir.path}/feature.txt').exists(), isTrue);

        final refs = await repo.allRefs();
        expect(refs, contains('refs/heads/main'));
        expect(refs, contains('refs/heads/feature'));
      } finally {
        await repo.dispose();
      }
    });
  });

  group('fuzz safety oracle', () {
    // A handful of fixed seeds — enough to exercise branch/checkout/merge/
    // stash interplay and file collisions without an unbounded runtime.
    for (final seed in [1, 2, 7, 42, 12345, 999999]) {
      test('seed $seed: HEAD resolvable and no fsck corruption after a '
          'generated op sequence', () async {
        final repo = await ScratchRepo.create(name: 'fuzz_$seed');
        try {
          final ops = genRepoOpSequence(seed, maxOps: 30);
          final results = <RepoOpResult>[];
          for (final op in ops) {
            results.add(await applyOp(repo, op));
          }

          // Core safety oracle: regardless of how many individual ops
          // failed (conflicts, bogus refs, "nothing to commit", ...), HEAD
          // must still resolve to a real commit — never corrupt, never
          // unborn once history exists (create() seeds a root commit
          // before any fuzzed op runs) — and the object database must not
          // be corrupt.
          final head = await repo.head();
          expect(head, isNotNull,
              reason: 'HEAD did not resolve after seed $seed.\n'
                  'ops: ${ops.join('\n')}\n'
                  'results: ${results.join('\n')}');
          expect(RegExp(r'^[0-9a-f]{40}$').hasMatch(head ?? ''), isTrue,
              reason: 'HEAD did not look like a real sha for seed $seed: '
                  '$head');

          final fsck = await repo.git(['fsck', '--full', '--no-dangling']);
          expect(fsck.exitCode, 0,
              reason: 'git fsck reported corruption for seed $seed:\n'
                  'stdout: ${fsck.stdout}\nstderr: ${fsck.stderr}\n'
                  'ops: ${ops.join('\n')}');
        } finally {
          await repo.dispose();
        }
      });
    }

    test('genRepoOpSequence is deterministic for a fixed seed', () {
      final a = genRepoOpSequence(2026, maxOps: 20).map((op) => op.toString());
      final b = genRepoOpSequence(2026, maxOps: 20).map((op) => op.toString());
      expect(a.toList(), equals(b.toList()));
    });
  });

  group('dispose', () {
    test('recursively removes the temp dir', () async {
      final repo = await ScratchRepo.create(name: 'dispose');
      final path = repo.dir.path;
      expect(await Directory(path).exists(), isTrue);

      await repo.dispose();

      expect(await Directory(path).exists(), isFalse);
    });
  });
}
