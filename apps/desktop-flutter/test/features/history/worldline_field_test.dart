// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Witnesses for the Worldline field's degenerate and contract-bearing
// paths, exercised against REAL scratch git repos (Directory.systemTemp +
// git init — the repo fixture pattern from test/backend). Each witness
// pins a bug class the implementation explicitly designed against:
//
//   * key round-trip / rejection   — a cache key that can't reproduce its
//                                    request can serve a lying field.
//   * tip pinning                  — the cache-race regression: a field
//                                    describing different history than
//                                    its key claims.
//   * binary churn floor           — asset-swap commits silently falling
//                                    to the horizon as "absent".
//   * merge alignment              — the strip's window and the field's
//                                    window drifting out of count-lockstep.
//   * failure vs data              — transient git faults cached as
//                                    authoritative empty fields.
//   * winsorized scaling           — one outlier owning the sky's ruler.
//
// NOTE on the key separator: it is a private NUL constant. The rejection
// test derives it from a probe key instead of hardcoding it — writing a
// raw NUL into this source would repeat the logos_flow incident (file
// turns binary to grep, invisible to diff review).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/history/worldline_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Run git in [repo], asserting success.
  Future<void> git(Directory repo, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: repo.path);
    expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
  }

  Future<String> gitOut(Directory repo, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: repo.path);
    expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
    return (r.stdout as String).trim();
  }

  Future<Directory> makeRepo(String prefix) async {
    final repo = await Directory.systemTemp.createTemp(prefix);
    await git(repo, ['init', '-q', '-b', 'main']);
    await git(repo, ['config', 'user.name', 'test']);
    await git(repo, ['config', 'user.email', 'test@local']);
    return repo;
  }

  /// Write [files] (path → String content or List&lt;int&gt; bytes), stage
  /// everything, commit, return the new HEAD hash.
  Future<String> commit(
      Directory repo, String message, Map<String, Object> files) async {
    for (final e in files.entries) {
      final f = File('${repo.path}${Platform.pathSeparator}${e.key}');
      await f.parent.create(recursive: true);
      final v = e.value;
      if (v is List<int>) {
        await f.writeAsBytes(v);
      } else {
        await f.writeAsString(v as String);
      }
    }
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-q', '-m', message]);
    return gitOut(repo, ['rev-parse', 'HEAD']);
  }

  Future<void> deleteRepo(Directory repo) async {
    if (await repo.exists()) {
      try {
        await repo.delete(recursive: true);
      } on FileSystemException {
        // Windows can hold transient locks on .git files; a leaked temp
        // dir must not fail the witness itself.
      }
    }
  }

  group('WorldlineFieldRequest key contract', () {
    test('key → fromKey is a total round-trip of all three fields', () {
      const req = WorldlineFieldRequest(
          repoPath: r'C:\some repo\path', window: 137, tip: 'abc123def');
      final back = WorldlineFieldRequest.fromKey(req.key);
      expect(back, isNotNull);
      expect(back!.repoPath, req.repoPath);
      expect(back.window, req.window);
      expect(back.tip, req.tip);
      // And the reconstructed request names the same cache slot.
      expect(back.key, req.key);
    });

    test('fromKey rejects malformed keys instead of guessing', () {
      // Derive the real separator from a probe key (it's a private
      // constant; hardcoding a guess would let this test pass vacuously
      // if the separator ever changed).
      final probe =
          const WorldlineFieldRequest(repoPath: 'a', window: 5, tip: 't')
              .key;
      expect(probe.length, 5, reason: 'expected a<sep>5<sep>t');
      final sep = probe[1];

      expect(WorldlineFieldRequest.fromKey(''), isNull);
      expect(WorldlineFieldRequest.fromKey('no-separators'), isNull);
      expect(WorldlineFieldRequest.fromKey('a${sep}5'), isNull,
          reason: 'two-part key');
      expect(WorldlineFieldRequest.fromKey('a${sep}5$sep'), isNull,
          reason: 'empty tip');
      expect(WorldlineFieldRequest.fromKey('${sep}5${sep}tip'), isNull,
          reason: 'empty repo');
      expect(WorldlineFieldRequest.fromKey('a${sep}NaN${sep}tip'), isNull,
          reason: 'non-integer window');
      expect(
          WorldlineFieldRequest.fromKey('a${sep}5${sep}tip${sep}extra'),
          isNull,
          reason: 'four-part key');
    });

    test('a request must pin its tip (assert contract)', () {
      expect(
        () => WorldlineFieldRequest(repoPath: 'r', window: 5, tip: ''),
        throwsAssertionError,
      );
    });
  });

  group('worldlineWindowLog against a scratch repo', () {
    test('tip pinning: walking tip=C never sees D or E', () async {
      final repo = await makeRepo('gdpu_worldline_tip_');
      try {
        final a = await commit(repo, 'A', {'f.txt': 'a\n'});
        final b = await commit(repo, 'B', {'f.txt': 'a\nb\n'});
        final c = await commit(repo, 'C', {'f.txt': 'a\nb\nc\n'});
        final d = await commit(repo, 'D', {'f.txt': 'a\nb\nc\nd\n'});
        final e = await commit(repo, 'E', {'f.txt': 'a\nb\nc\nd\ne\n'});

        final walk = worldlineWindowLog(WorldlineFieldRequest(
            repoPath: repo.path, window: 10, tip: c));
        final hashes = walk.map((w) => w.hash).toList();
        // Exactly C's ancestry window, newest first — the cache key's
        // promise. D/E exist in the repo but are outside tip=C's history.
        expect(hashes, [c, b, a]);
        expect(hashes, isNot(contains(d)));
        expect(hashes, isNot(contains(e)));
      } finally {
        await deleteRepo(repo);
      }
    });

    test(
        'binary floor: a binary-only commit carries churn >= 1 and a '
        'covered coordinate', () async {
      final repo = await makeRepo('gdpu_worldline_bin_');
      try {
        // NUL bytes force git to classify the file as binary (numstat
        // emits "-<TAB>-<TAB>path").
        final bin1 = [0x00, 0x01, 0x02, 0xFF, 0x00, 0x10];
        final bin2 = [0x00, 0xAA, 0xBB, 0x00, 0xCC, 0x00, 0x00];
        // Weave img.bin into the co-change graph so it has degree > 0,
        // then land the witness: a commit touching ONLY the binary.
        await commit(repo, 'c1', {'a.txt': 'a\n', 'b.txt': 'b\n'});
        await commit(repo, 'c2', {'a.txt': 'a2\n', 'img.bin': bin1});
        await commit(repo, 'c3', {'b.txt': 'b2\n', 'c.txt': 'c\n'});
        await commit(repo, 'c4', {'a.txt': 'a3\n', 'c.txt': 'c2\n'});
        final binOnly = await commit(repo, 'c5', {'img.bin': bin2});
        final tip =
            await commit(repo, 'c6', {'b.txt': 'b3\n', 'img.bin': bin1});

        final req = WorldlineFieldRequest(
            repoPath: repo.path, window: 10, tip: tip);

        // Walk level: the binary touch is real history, floored to 1.
        final walk = worldlineWindowLog(req);
        final binCommit = walk.firstWhere((w) => w.hash == binOnly);
        expect(binCommit.churn['img.bin'], isNotNull);
        expect(binCommit.churn['img.bin'], greaterThanOrEqualTo(1));

        // Field level: the graph resolves (4 files, connected), so the
        // binary-only commit must be covered — never silently absent.
        final field = await loadWorldlineField(repo.path, 10, tip);
        expect(field.hasSky, isTrue,
            reason: 'fixture graph should resolve excited modes');
        expect(field.coordFor(binOnly).covered, isTrue,
            reason: 'an asset-swap commit is a structural event');
      } finally {
        await deleteRepo(repo);
      }
    });

    test(
        'merge alignment: merge commits appear in the walk with empty '
        'churn, count-aligned with plain git log', () async {
      final repo = await makeRepo('gdpu_worldline_merge_');
      try {
        await commit(repo, 'base', {'base.txt': 'base\n'});
        await git(repo, ['checkout', '-q', '-b', 'feat']);
        await commit(repo, 'feat', {'feat.txt': 'feat\n'});
        await git(repo, ['checkout', '-q', 'main']);
        await commit(repo, 'main2', {'main.txt': 'main\n'});
        await git(
            repo, ['merge', '-q', '--no-ff', '-m', 'merge feat', 'feat']);
        final tip = await gitOut(repo, ['rev-parse', 'HEAD']);

        final walk = worldlineWindowLog(WorldlineFieldRequest(
            repoPath: repo.path, window: 10, tip: tip));

        // Window counts align commit-for-commit with the strip's list.
        final plain =
            (await gitOut(repo, ['log', '--format=%H', '-n', '10', tip]))
                .split('\n');
        expect(walk.length, plain.length);
        expect(walk.map((w) => w.hash).toList(), plain);

        // The merge commit itself: present, no numstat → empty churn.
        expect(walk.first.hash, tip);
        expect(walk.first.churn, isEmpty);
      } finally {
        await deleteRepo(repo);
      }
    });

    test(
        'failure semantics: bad tip and nonexistent repo THROW; a tiny '
        'window returns data', () async {
      final repo = await makeRepo('gdpu_worldline_fail_');
      try {
        final only = await commit(repo, 'only', {'f.txt': 'f\n'});

        // Bad tip in a real repo: git exits nonzero → StateError, never
        // an empty return (an empty return would be cached as truth).
        expect(
          () => worldlineWindowLog(WorldlineFieldRequest(
              repoPath: repo.path,
              window: 10,
              tip: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef')),
          throwsStateError,
        );

        // Nonexistent repo path: same law.
        final gone = '${repo.path}${Platform.pathSeparator}does-not-exist';
        expect(
          () => worldlineWindowLog(WorldlineFieldRequest(
              repoPath: gone, window: 10, tip: only)),
          throwsStateError,
        );

        // A genuinely tiny window (exit 0) is honest data, not a failure.
        final walk = worldlineWindowLog(WorldlineFieldRequest(
            repoPath: repo.path, window: 100, tip: only));
        expect(walk.length, 1);
        expect(walk.single.hash, only);
      } finally {
        await deleteRepo(repo);
      }
    });

    test('degenerate field: <4 commits returns the empty field as DATA',
        () async {
      final repo = await makeRepo('gdpu_worldline_tiny_');
      try {
        await commit(repo, 'c1', {'a.txt': 'a\n'});
        await commit(repo, 'c2', {'a.txt': 'a2\n', 'b.txt': 'b\n'});
        final tip = await commit(repo, 'c3', {'b.txt': 'b2\n'});

        // Through the real load path (isolate + cache): the observation
        // "too few commits to test the premise" is cacheable data — it
        // must complete normally with the empty-equivalent field.
        final field = await loadWorldlineField(repo.path, 10, tip);
        expect(field.byHash, isEmpty);
        expect(field.hasSky, isFalse);
        expect(field.fileCount, WorldlineField.empty.fileCount);
        expect(field.components, WorldlineField.empty.components);
      } finally {
        await deleteRepo(repo);
      }
    });
  });

  group('worldlineRobustAxis (winsorized scaling law)', () {
    test('a single extreme outlier does not own the scale', () {
      // 20 well-behaved samples spread over [-1, 1] plus one at 1000.
      final xs = <double>[
        for (var i = 0; i < 20; i++) -1.0 + i * (2.0 / 19.0),
        1000.0,
      ];
      final axis = worldlineRobustAxis(xs);

      double norm(double x) => (x - axis.center) / axis.halfRange;

      // The bulk maps strictly inside the rim — the era body keeps the
      // plane instead of being flattened into a band by the outlier.
      for (var i = 0; i < 20; i++) {
        expect(norm(xs[i]).abs(), lessThan(1.0),
            reason: 'bulk sample ${xs[i]} must stay inside the rim');
      }
      // The outlier lands far beyond the rim and (in field use) clamps
      // to +/-1 — still reads as extreme, no longer holds the ruler.
      expect(norm(1000.0), greaterThan(1.0));
    });

    test('constant input divides by the floor, never by zero', () {
      final axis = worldlineRobustAxis([5.0, 5.0, 5.0, 5.0]);
      expect(axis.halfRange, greaterThan(0.0));
      final n = (5.0 - axis.center) / axis.halfRange;
      expect(n.isNaN, isFalse);
      expect(n, 0.0);
    });
  });
}
