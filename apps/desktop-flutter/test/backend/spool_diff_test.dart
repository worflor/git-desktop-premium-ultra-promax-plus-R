// spoolSelectionDiff streams the combined diff to disk instead of building one
// String. This oracle test proves — on REAL git — that the spooled bytes, read
// back through DiffDocument.lazyFromSpool, reconstruct exactly the same document
// as the in-RAM getSelectionDiff path: same rows, same text, across staged,
// unstaged, and untracked changes in one selection.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/features/diff/byte_store.dart';
import 'package:git_desktop/features/diff/diff_document.dart';

import '../support/scratch_repo.dart';

void main() {
  test(
    'tracked deletions select the streaming transport before diff output',
    () async {
      final repo = await ScratchRepo.create(name: 'spool_deleted');
      addTearDown(repo.dispose);
      await repo.writeFile('deleted.txt', List.filled(4096, 'old').join('\n'));
      await repo.stageAll();
      await repo.commitAll('base');
      await File(
        '${repo.dir.path}${Platform.pathSeparator}deleted.txt',
      ).delete();

      const files = [
        RepositoryStatusFile(path: 'deleted.txt', staged: '', unstaged: 'D'),
      ];
      expect(selectionContainsTrackedDeletion(files), isTrue);

      // This is the route ChangesPage now chooses without calling
      // getSelectionDiff, so the deletion patch never first becomes a String.
      final streamed = await spoolSelectionDiff(repo.dir.path, files);
      expect(streamed.ok, isTrue, reason: streamed.error);
      final spool = streamed.data!;
      addTearDown(spool.dispose);
      expect(spool.byteLength, greaterThan(4096));
    },
  );

  test(
    'spoolSelectionDiff == getSelectionDiff (staged+unstaged+untracked)',
    () async {
      final repo = await ScratchRepo.create(name: 'spool');
      addTearDown(repo.dispose);

      // Base commit with two tracked files.
      await repo.writeFile('a.txt', 'a1\na2\na3\na4\n');
      await repo.writeFile('b.txt', 'b1\nb2\nb3\nb4\n');
      await repo.stageAll();
      await repo.commitAll('base');

      // a.txt: unstaged modification. b.txt: staged modification, THEN a
      // second unstaged modification on a different line — the `MM` shape.
      // c.txt: new, untracked. This exercises the tracked pass, the
      // untracked pass, the join, AND the one-section-per-path contract.
      await repo.writeFile('a.txt', 'a1\naX\na3\na4\n');
      await repo.writeFile('b.txt', 'b1\nb2\nbX\nb4\n');
      await repo.stage(['b.txt']);
      await repo.writeFile('b.txt', 'bY\nb2\nbX\nb4\n'); // unstaged on top
      await repo.writeFile('c.txt', 'brand new\nuntracked file\n');

      const files = [
        RepositoryStatusFile(path: 'a.txt', staged: '', unstaged: 'M'),
        RepositoryStatusFile(path: 'b.txt', staged: 'M', unstaged: 'M'),
        RepositoryStatusFile(path: 'c.txt', staged: '?', unstaged: '?'),
      ];

      final stringResult = await getSelectionDiff(repo.dir.path, files);
      expect(stringResult.ok, isTrue, reason: stringResult.error);
      final inRam = DiffDocument.lazy(rawContent: stringResult.data!);

      final spoolResult = await spoolSelectionDiff(repo.dir.path, files);
      expect(spoolResult.ok, isTrue, reason: spoolResult.error);
      final spool = spoolResult.data!;
      addTearDown(spool.dispose);
      expect(spool.byteLength, greaterThan(0));

      final onDisk = await DiffDocument.lazyFromSpool(spool.path);
      addTearDown(onDisk.dispose);

      // Same number of rows, same content — the streamed concatenation matches
      // the String join exactly.
      expect(
        onDisk.lines.length,
        inRam.lines.length,
        reason: 'row count: spool != string',
      );
      for (var i = 0; i < inRam.lines.length; i++) {
        expect(
          onDisk.lines[i].text,
          inRam.lines[i].text,
          reason: 'row $i text',
        );
        expect(
          onDisk.lines[i].kind,
          inRam.lines[i].kind,
          reason: 'row $i kind',
        );
      }
      // All three files are present in the on-disk document's sections.
      expect(
        onDisk.sections.map((s) => s.path).toSet(),
        containsAll(<String>['a.txt', 'b.txt', 'c.txt']),
      );
      // ONE section per path — the whole document model (sections, slices,
      // navigation) keys by path. The old --cached + unstaged pass pair
      // emitted b.txt TWICE for the MM shape: the eager slicer silently
      // dropped the staged section (last-wins) and the lazy index kept an
      // unreachable duplicate. The single HEAD-to-worktree pass makes the
      // duplicate structurally impossible...
      expect(
        onDisk.sections.where((s) => s.path == 'b.txt').length,
        1,
        reason: 'an MM file must yield exactly one section',
      );
      // ...while carrying BOTH deltas: the staged edit (bX) and the
      // unstaged edit on top (bY) are each visible exactly once.
      final bSlice = onDisk.rawSliceForPath('b.txt')!;
      expect(
        bSlice,
        contains('+bX'),
        reason: 'the staged delta must not be dropped (old eager bug)',
      );
      expect(
        bSlice,
        contains('+bY'),
        reason: 'the unstaged delta must be present',
      );
      expect(
        '+bX'.allMatches(bSlice).length,
        1,
        reason: 'no duplicated sections (old lazy bug)',
      );
      // File-backed: nothing materialized.
      expect(onDisk.isFileBacked, isTrue);
      expect(onDisk.rawContent, isEmpty);
    },
  );

  test('spoolStringToTempFile: surrogate-safe chunking, byte-identical', () async {
    // Emoji-dense content so surrogate pairs (astral chars) land ON tiny chunk
    // boundaries. A naive substring chunker would split a pair and corrupt it.
    final sb = StringBuffer();
    for (var i = 0; i < 500; i++) {
      sb.write('text line $i 🎉🔥💯🚀✨🌍𝕏𝕐𝕑 中文 café\n');
    }
    final content = sb.toString();

    // Chunk size 7 bytes = adversarial: boundaries fall mid-emoji constantly.
    final spool = await spoolStringToTempFile(content, chunkSize: 7);
    addTearDown(spool.dispose);

    // Read it back through FileByteStore and confirm byte-identical to source.
    final store = FileByteStore.open(spool.path);
    final rebuilt = store.substring(0, store.length);
    expect(rebuilt, content, reason: 'surrogate pairs survived chunked write');
    store.dispose();

    // And the whole doc reconstructs (the emoji lines are context/garbage but
    // must round-trip exactly).
    final doc = await DiffDocument.lazyFromSpool(spool.path);
    addTearDown(doc.dispose);
    expect(doc.lines.first.text, startsWith('text line 0 🎉'));
  });

  test('spoolFileDiff == getFileDiff for a tracked modification', () async {
    final repo = await ScratchRepo.create(name: 'filespool');
    addTearDown(repo.dispose);
    await repo.writeFile('t.txt', 'l1\nl2\nl3\nl4\nl5\n');
    await repo.stageAll();
    await repo.commitAll('base');
    await repo.writeFile('t.txt', 'l1\nCHANGED\nl3\nl4\nl5\n'); // unstaged mod

    final stringResult = await getFileDiff(repo.dir.path, 't.txt');
    expect(stringResult.ok, isTrue, reason: stringResult.error);
    final inRam = DiffDocument.lazy(rawContent: stringResult.data!);

    final spoolResult = await spoolFileDiff(repo.dir.path, 't.txt');
    expect(spoolResult.ok, isTrue, reason: spoolResult.error);
    final spool = spoolResult.data!;
    addTearDown(spool.dispose);
    expect(spool.byteLength, greaterThan(0));
    final onDisk = await DiffDocument.lazyFromSpool(spool.path);
    addTearDown(onDisk.dispose);

    expect(onDisk.lines.length, inRam.lines.length, reason: 'row count');
    for (var i = 0; i < inRam.lines.length; i++) {
      expect(onDisk.lines[i].text, inRam.lines[i].text, reason: 'row $i');
      expect(onDisk.lines[i].kind, inRam.lines[i].kind, reason: 'row $i kind');
    }
    expect(onDisk.isFileBacked, isTrue);
  });

  test(
    'spoolFileDiff is empty for an untracked path (caller falls through)',
    () async {
      final repo = await ScratchRepo.create(name: 'filespool_untracked');
      addTearDown(repo.dispose);
      await repo.writeFile('u.txt', 'untracked\n');
      final res = await spoolFileDiff(repo.dir.path, 'u.txt');
      expect(res.ok, isTrue, reason: res.error);
      addTearDown(res.data!.dispose);
      expect(res.data!.byteLength, 0); // untracked → no `git diff` output
    },
  );

  test('getCommitHunks (streamed) reports per-file hunks', () async {
    final repo = await ScratchRepo.create(name: 'commithunks');
    addTearDown(repo.dispose);
    await repo.writeFile('a.txt', 'a1\na2\na3\na4\na5\na6\n');
    await repo.stageAll();
    await repo.commitAll('base');
    // Two separated edits → two hunks in a.txt.
    await repo.writeFile('a.txt', 'a1\nEDIT2\na3\na4\nEDIT5\na6\n');
    await repo.stageAll();
    await repo.commitAll('edit');
    final head = (await repo.git([
      'rev-parse',
      'HEAD',
    ])).stdout.toString().trim();

    final res = await getCommitHunks(repo.dir.path, head);
    expect(res.ok, isTrue, reason: res.error);
    final hunks = res.data!['a.txt'];
    expect(hunks, isNotNull, reason: 'a.txt should have hunks');
    // Two edits, one line each → 2 hunks, each 1 add + 1 del.
    expect(hunks!.length, 2);
    for (final h in hunks) {
      expect(h.additions, 1);
      expect(h.deletions, 1);
      expect(h.newStart, greaterThan(0));
    }
  });

  test('spoolCommitDiff == raw git diff (non-root commit)', () async {
    final repo = await ScratchRepo.create(name: 'commitspool');
    addTearDown(repo.dispose);
    await repo.writeFile('c.txt', 'v1a\nv1b\nv1c\n');
    await repo.stageAll();
    await repo.commitAll('first');
    await repo.writeFile('c.txt', 'v1a\nCHANGED\nv1c\n');
    await repo.writeFile('d.txt', 'new file\ncontents\n');
    await repo.stageAll();
    await repo.commitAll('second');
    final head = (await repo.git([
      'rev-parse',
      'HEAD',
    ])).stdout.toString().trim();

    // Oracle is REAL git invoked directly (same argv `spoolCommitDiff`
    // spreads: _kDiffCmd/_kDiffContentPins in lib/backend/git.dart), not our
    // own other function — stronger than the old self-oracle this replaced.
    final oracle = await repo.git([
      '-c',
      'diff.binary=false',
      'diff',
      '--no-color',
      '--no-ext-diff',
      '--src-prefix=a/',
      '--dst-prefix=b/',
      '--full-index',
      '$head~1..$head',
    ]);
    expect(oracle.exitCode, 0, reason: oracle.stderr.toString());
    final inRam = DiffDocument.lazy(rawContent: oracle.stdout.toString());

    final res = await spoolCommitDiff(repo.dir.path, head);
    expect(res.ok, isTrue, reason: res.error);
    final spool = res.data!;
    final onDisk = await DiffDocument.lazyFromSpool(
      spool.path,
      ownedTempDir: spool.dir,
    ); // doc owns the temp dir now
    addTearDown(onDisk.dispose);
    expect(onDisk.lines.length, inRam.lines.length);
    for (var i = 0; i < inRam.lines.length; i++) {
      expect(onDisk.lines[i].text, inRam.lines[i].text, reason: 'row $i');
    }
  });

  test(
    'spoolCommitDiff falls back to `git show` for a REAL root commit',
    () async {
      // ScratchRepo always seeds an initial commit, so its first user commit has
      // a parent and never exercises the fallback. Build a raw repo whose FIRST
      // commit is the root, so `root~1..root` fails and the `git show` fallback
      // must produce the diff.
      final dir = Directory.systemTemp.createTempSync('rawroot');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      Future<void> g(List<String> a) async {
        final r = await Process.run('git', a, workingDirectory: dir.path);
        expect(r.exitCode, 0, reason: 'git ${a.join(' ')}: ${r.stderr}');
      }

      await g(['init', '-q', '-b', 'main']);
      await g(['config', 'user.email', 't@t.co']);
      await g(['config', 'user.name', 't']);
      await g(['config', 'commit.gpgsign', 'false']);
      File(
        '${dir.path}/root.txt',
      ).writeAsBytesSync(utf8.encode('line one\nline two\n'));
      await g(['add', '-A']);
      await g(['commit', '-q', '-m', 'root']);
      final root = (await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: dir.path)).stdout.toString().trim();

      final res = await spoolCommitDiff(dir.path, root);
      expect(res.ok, isTrue, reason: res.error);
      final spool = res.data!;
      expect(
        spool.byteLength,
        greaterThan(0),
        reason: 'fallback produced empty',
      );
      final doc = await DiffDocument.lazyFromSpool(
        spool.path,
        ownedTempDir: spool.dir,
      );
      addTearDown(doc.dispose);
      expect(doc.lines.any((l) => l.text.contains('root.txt')), isTrue);
      expect(doc.lines.any((l) => l.text.contains('line one')), isTrue);
    },
  );

  test('lazyFromSpool(ownedTempDir) dispose deletes the temp dir', () async {
    final repo = await ScratchRepo.create(name: 'owneddir');
    addTearDown(repo.dispose);
    await repo.writeFile('f.txt', 'a\nb\n');
    await repo.stageAll();
    await repo.commitAll('base');
    await repo.writeFile('f.txt', 'a\nB\n');
    final res = await spoolFileDiff(repo.dir.path, 'f.txt');
    expect(res.ok, isTrue);
    final spool = res.data!;
    final doc = await DiffDocument.lazyFromSpool(
      spool.path,
      ownedTempDir: spool.dir,
    );
    expect(await _exists(spool.dir), isTrue);
    doc.dispose(); // closes handle AND deletes the owned temp dir
    expect(await _exists(spool.dir), isFalse);
  });

  test(
    'adoptSpool owns: dispose deletes the dir; viewSpool never does',
    () async {
      // The typed ownership pair (the only lib-facing entries — law L15).
      final repo = await ScratchRepo.create(name: 'adopt_view');
      addTearDown(repo.dispose);
      await repo.writeFile('f.txt', 'a\nb\n');
      await repo.stageAll();
      await repo.commitAll('base');
      await repo.writeFile('f.txt', 'a\nB\n');

      // adopt: doc.dispose() is the whole cleanup.
      final adopted = (await spoolFileDiff(repo.dir.path, 'f.txt')).data!;
      final owner = await DiffDocument.adoptSpool(adopted);
      expect(owner.lines, isNotEmpty);
      owner.dispose();
      expect(await _exists(adopted.dir), isFalse);

      // view: doc.dispose() releases only the handle; the spool survives for
      // its other readers until the owner disposes it.
      final viewed = (await spoolFileDiff(repo.dir.path, 'f.txt')).data!;
      final viewer = await DiffDocument.viewSpool(viewed);
      expect(viewer.lines, isNotEmpty);
      viewer.dispose();
      expect(await _exists(viewed.path), isTrue);
      await viewed.dispose();
      expect(await _exists(viewed.path), isFalse);
    },
  );

  test('spoolSelectionDiff dispose deletes the spool', () async {
    final repo = await ScratchRepo.create(name: 'spool_dispose');
    addTearDown(repo.dispose);
    await repo.writeFile('f.txt', 'one\ntwo\n');
    await repo.stageAll();
    await repo.commitAll('base');
    await repo.writeFile('f.txt', 'one\nTWO\n');

    const files = [
      RepositoryStatusFile(path: 'f.txt', staged: '', unstaged: 'M'),
    ];
    final result = await spoolSelectionDiff(repo.dir.path, files);
    expect(result.ok, isTrue);
    final spool = result.data!;
    final doc = await DiffDocument.lazyFromSpool(spool.path);
    expect(doc.lines, isNotEmpty);
    doc.dispose();
    await spool.dispose();
    // The spool file is gone after dispose.
    expect(await _exists(spool.path), isFalse);
  });
}

Future<bool> _exists(String path) async {
  // ignore: avoid_slow_async_io
  return (await FileSystemEntity.type(path)) != FileSystemEntityType.notFound;
}
