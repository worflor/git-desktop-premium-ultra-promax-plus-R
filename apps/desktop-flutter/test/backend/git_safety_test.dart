// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/features/diff/diff_document.dart';

/// Witnesses for the delayed-destruction and undo safety contracts, run
/// against real temp-dir git repos and asserted through git plumbing only:
///
///   * undoLastCommit — soft-reset semantics, HEAD-guard refusal, root
///     commit refusal (branch-ref deletion is unrepresentable).
///   * deleteBranchIfAt / deleteTagIfAt — identity-pinned deletes verify
///     the arm-time tip at fire time, refuse a moved ref, treat a gone
///     ref as intent-satisfied, and preserve git's merged-check.
///   * stashDropByHash — drops the captured entry even after the stash
///     list shifts underneath it (the index-shift incident class).
///   * prepareCommitStaging — conflicted (unmerged) paths are left
///     entirely alone by the staging walk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String repo;

  Future<ProcessResult> git(List<String> args) => Process.run(
        'git',
        args,
        workingDirectory: repo,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  File wf(String path) => File('$repo${Platform.pathSeparator}$path');

  Future<String> head() async =>
      ((await git(['rev-parse', 'HEAD'])).stdout as String).trim();

  Future<void> commitFile(String path, String content, String msg) async {
    await wf(path).writeAsString(content);
    await git(['add', '--', path]);
    await git(['commit', '-qm', msg]);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gdpu_safety_');
    repo = root.path;
    await git(['init', '-q', '-b', 'main']);
    await git(['config', 'user.email', 'a@b.c']);
    await git(['config', 'user.name', 'test']);
    await git(['config', 'core.autocrlf', 'false']);
    await git(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  group('undoLastCommit', () {
    test('soft-undo moves HEAD back one and keeps index AND worktree',
        () async {
      await commitFile('f.txt', 'v1\n', 'base');
      final base = await head();
      await commitFile('f.txt', 'v2\n', 'second');
      final second = await head();

      final r = await undoLastCommit(repo, expectHead: second);
      expect(r.ok, isTrue, reason: r.error ?? '');
      expect(await head(), base);
      // Soft semantics: the committed change is back in the INDEX
      // (staged, ready to re-commit) and untouched on disk.
      expect((await git(['show', ':f.txt'])).stdout as String, 'v2\n');
      expect(await wf('f.txt').readAsString(), 'v2\n');
      final staged =
          (await git(['diff', '--cached', '--name-only'])).stdout as String;
      expect(staged.trim(), 'f.txt');
    });

    test('refuses when HEAD is not the expected commit', () async {
      await commitFile('f.txt', 'v1\n', 'base');
      await commitFile('f.txt', 'v2\n', 'second');
      final second = await head();
      await commitFile('f.txt', 'v3\n', 'third — the repo moved on');
      final third = await head();

      final r = await undoLastCommit(repo, expectHead: second);
      expect(r.ok, isFalse);
      expect(await head(), third, reason: 'a refused undo must not mutate');
    });

    test('refuses a root commit; the branch ref survives', () async {
      await commitFile('f.txt', 'v1\n', 'root');
      final rootHash = await head();

      final r = await undoLastCommit(repo, expectHead: rootHash);
      expect(r.ok, isFalse);
      expect(await head(), rootHash);
      // The branch ref itself must still exist — deleting it as "undo"
      // is the incident class this guard makes unrepresentable.
      final refCheck =
          await git(['rev-parse', '--verify', 'refs/heads/main']);
      expect(refCheck.exitCode, 0);
    });
  });

  group('identity-pinned ref deletes', () {
    test('deleteBranchIfAt deletes when the tip still matches', () async {
      await commitFile('f.txt', 'v1\n', 'base');
      await git(['branch', 'victim']);
      final tip = await refTip(repo, 'refs/heads/victim');
      expect(tip, isNotNull);

      final r = await deleteBranchIfAt(repo, 'victim', tip!);
      expect(r.ok, isTrue, reason: r.error ?? '');
      expect(await refTip(repo, 'refs/heads/victim'), isNull);
    });

    test('deleteBranchIfAt refuses when the branch moved after arming',
        () async {
      await commitFile('f.txt', 'v1\n', 'base');
      await git(['branch', 'victim']);
      final armedTip = await refTip(repo, 'refs/heads/victim');

      // The window elapses; meanwhile the branch is re-pointed at new work.
      await commitFile('f.txt', 'v2\n', 'newer');
      await git(['branch', '-f', 'victim', 'HEAD']);
      final movedTip = await refTip(repo, 'refs/heads/victim');
      expect(movedTip, isNot(armedTip));

      final r = await deleteBranchIfAt(repo, 'victim', armedTip!);
      expect(r.ok, isFalse);
      expect(r.error, contains('moved'));
      expect(await refTip(repo, 'refs/heads/victim'), movedTip,
          reason: 'the moved branch must survive');
    });

    test('deleteBranchIfAt treats an already-gone branch as success',
        () async {
      await commitFile('f.txt', 'v1\n', 'base');
      await git(['branch', 'victim']);
      final tip = await refTip(repo, 'refs/heads/victim');
      await git(['branch', '-D', 'victim']);

      final r = await deleteBranchIfAt(repo, 'victim', tip!);
      expect(r.ok, isTrue);
    });

    test('non-force delete still runs git\'s merged-check at fire time',
        () async {
      await commitFile('f.txt', 'v1\n', 'base');
      await git(['checkout', '-qb', 'victim']);
      await commitFile('g.txt', 'unmerged\n', 'unmerged work');
      final tip = await refTip(repo, 'refs/heads/victim');
      await git(['checkout', '-q', 'main']);

      final safe = await deleteBranchIfAt(repo, 'victim', tip!);
      expect(safe.ok, isFalse);
      expect(safe.error!.toLowerCase(), contains('not fully merged'),
          reason: 'the needsForce arming contract keys off this stderr');
      expect(await refTip(repo, 'refs/heads/victim'), tip);

      final forced =
          await deleteBranchIfAt(repo, 'victim', tip, force: true);
      expect(forced.ok, isTrue, reason: forced.error ?? '');
      expect(await refTip(repo, 'refs/heads/victim'), isNull);
    });

    test('deleteTagIfAt refuses a re-pointed tag, deletes a matching one',
        () async {
      await commitFile('f.txt', 'v1\n', 'base');
      await git(['tag', 'v1']);
      final armed = await refTip(repo, 'refs/tags/v1');
      await commitFile('f.txt', 'v2\n', 'newer');
      await git(['tag', '-f', 'v1', 'HEAD']);

      final refused = await deleteTagIfAt(repo, 'v1', armed!);
      expect(refused.ok, isFalse);
      expect(await refTip(repo, 'refs/tags/v1'), isNotNull);

      final current = await refTip(repo, 'refs/tags/v1');
      final r = await deleteTagIfAt(repo, 'v1', current!);
      expect(r.ok, isTrue, reason: r.error ?? '');
      expect(await refTip(repo, 'refs/tags/v1'), isNull);
    });
  });

  group('stash identity under list shift', () {
    test('stashDropByHash drops the captured entry, not the position',
        () async {
      await commitFile('f.txt', 'v1\n', 'base');

      // Stash ALPHA (becomes stash@{1} after the next push).
      await wf('f.txt').writeAsString('alpha\n');
      await stashPush(repo, message: 'ALPHA', includeUntracked: true);
      // Capture ALPHA's identity while it sits at position 0.
      final alphaHash = await stashHashAt(repo, 0);
      expect(alphaHash, isNotNull);

      // The list shifts: BETA lands at 0, ALPHA slides to 1.
      await wf('f.txt').writeAsString('beta\n');
      await stashPush(repo, message: 'BETA', includeUntracked: true);

      final r = await stashDropByHash(repo, alphaHash!);
      expect(r.ok, isTrue, reason: r.error ?? '');

      // Survivor is BETA — a positional stash@{0} drop would have
      // deleted it instead.
      final list = await listStashes(repo);
      expect(list.ok, isTrue);
      expect(list.data, hasLength(1));
      expect(list.data!.single.message, contains('BETA'));
    });

    test('stashDropByHash is a no-op success when the entry is already gone',
        () async {
      await commitFile('f.txt', 'v1\n', 'base');
      await wf('f.txt').writeAsString('alpha\n');
      await stashPush(repo, message: 'ALPHA', includeUntracked: true);
      final hash = await stashHashAt(repo, 0);
      await git(['stash', 'drop', '-q', 'stash@{0}']);

      final r = await stashDropByHash(repo, hash!);
      expect(r.ok, isTrue);
    });
  });

  group('getCommitIdentity', () {
    test('resolves the configured identity git will actually stamp',
        () async {
      await commitFile('f.txt', 'v1\n', 'base');
      final id = await getCommitIdentity(repo);
      expect(id, isNotNull);
      expect(id!.name, 'test');
      expect(id.email, 'a@b.c');
    });

    test('local config override wins — the incident scenario is visible',
        () async {
      // The planted-identity attack: a tool writes user.* into LOCAL
      // config, silently outranking the user's global identity. The
      // probe must surface the local value, because that IS what the
      // next commit would stamp.
      await commitFile('f.txt', 'v1\n', 'base');
      await git(['config', 'user.name', 'hijacked']);
      await git(['config', 'user.email', 'evil@example.com']);
      final id = await getCommitIdentity(repo);
      expect(id, isNotNull);
      expect(id!.name, 'hijacked');
      expect(id.email, 'evil@example.com');
    });
  });

  group('large diffs', () {
    test('a huge text diff renders its real content, no line-count cap',
        () async {
      // There is deliberately NO changed-line ceiling: the diff viewer is
      // virtualized and a large-but-textual change (a big refactor, a
      // regenerated lockfile) must show its actual content. The only thing
      // the app declines to materialize is binary/non-text blobs, which
      // numstat reports as `-` and the binary path owns separately.
      final big = StringBuffer();
      for (var i = 0; i < 120000; i++) {
        big.writeln('data row $i');
      }
      await wf('data.txt').writeAsString(big.toString());
      await git(['add', '-A']);
      await git(['commit', '-qm', 'base']);
      // Rewrite every line → ~240k changed lines.
      final changed = StringBuffer();
      for (var i = 0; i < 120000; i++) {
        changed.writeln('data row $i CHANGED');
      }
      await wf('data.txt').writeAsString(changed.toString());

      final r = await getFileDiff(repo, 'data.txt');
      expect(r.ok, isTrue);
      expect(r.data, isNot(contains('too large')),
          reason: 'no placeholder stub — the real diff is materialized');
      expect(r.data, contains('+data row 0 CHANGED'));
      expect(r.data, contains('-data row 0'));

      // Small diffs render as always.
      await wf('small.txt').writeAsString('one\n');
      await git(['add', '-A']);
      await git(['commit', '-qm', 'small']);
      await wf('small.txt').writeAsString('two\n');
      final small = await getFileDiff(repo, 'small.txt');
      expect(small.ok, isTrue);
      expect(small.data, contains('-one'));
      expect(small.data, contains('+two'));
    });

    test('a large refactor diff materializes real content through the model',
        () async {
      // The removed ceiling short-circuited *before any model was built*.
      // Asserting getFileDiff returns a string (above) does not exercise the
      // path the reviewer flagged: the diff the backend now hands back is fed
      // to DiffDocument.fromRawContent on the UI, which parses, indexes and
      // builds an edit unit for every changed line. Drive that construction
      // here on a realistically-shaped large change — a big refactor that
      // edits thousands of lines interleaved with untouched context — and
      // assert it materializes the actual change, every line, both sides,
      // with no line-count truncation. This is the integration contract the
      // cap once side-stepped and now must hold openly.
      const pairs = 20000; // 20k edited lines interleaved with 20k of context
      final base = StringBuffer();
      for (var i = 0; i < pairs; i++) {
        base.writeln('context $i'); // untouched anchor
        base.writeln('value $i'); // will be rewritten
      }
      await wf('refactor.dart').writeAsString(base.toString());
      await git(['add', '-A']);
      await git(['commit', '-qm', 'refactor base']);

      final after = StringBuffer();
      for (var i = 0; i < pairs; i++) {
        after.writeln('context $i');
        after.writeln('value $i renamed');
      }
      await wf('refactor.dart').writeAsString(after.toString());

      final r = await getFileDiff(repo, 'refactor.dart');
      expect(r.ok, isTrue);
      expect(r.data, isNot(contains('too large')));

      final doc = DiffDocument.fromRawContent(
        rawContent: r.data!,
        pathHint: 'refactor.dart',
        documentId: 'test:refactor',
      );
      expect(doc.files, hasLength(1));
      final file = doc.files.first;
      expect(file.isBinary, isFalse, reason: 'a text diff is never binary');
      // Every edited line survives the parse — no count is capped or dropped.
      expect(doc.stats.adds, pairs);
      expect(doc.stats.dels, pairs);
      expect(doc.changedLines, pairs * 2);
      expect(file.lines.any((l) => l.text == '-value 0'), isTrue);
      expect(file.lines.any((l) => l.text == '+value 0 renamed'), isTrue);
      expect(file.lines.any((l) => l.text == '-value ${pairs - 1}'), isTrue);
    });
  });

  group('identity familiarity grading', () {
    test('probe collects historical authors; grader ranks against them',
        () async {
      await commitFile('f.txt', 'v1\n', 'base');
      final authors = await getHistoricalAuthors(repo);
      expect(authors.emails, contains('a@b.c'));
      expect(authors.names, contains('test'));

      // Resident: the email that already authored here.
      expect(gradeIdentity((name: 'test', email: 'a@b.c'), authors),
          IdentityFamiliarity.resident);
      // Email is the strong key — case-insensitive.
      expect(gradeIdentity((name: 'Whoever', email: 'A@B.C'), authors),
          IdentityFamiliarity.resident);
      // Known name, never-seen email: the new-machine shape.
      expect(gradeIdentity((name: 'Test', email: 'new@laptop.dev'), authors),
          IdentityFamiliarity.newEmail);
      // Neither: the planted-config incident shape.
      expect(
          gradeIdentity(
              (name: 'hijacked', email: 'evil@example.com'), authors),
          IdentityFamiliarity.stranger);
    });

    test('workspace authors soften a local stranger into a greeting', () {
      final local = (emails: {'other@dev.io'}, names: {'other'});
      final workspace = (emails: {'me@home.dev'}, names: {'worflor'});
      // First commit in a freshly-cloned repo: unseen locally, but an
      // author of the user's other open repos — greeting, not caution.
      expect(
          gradeIdentity((name: 'worflor', email: 'me@home.dev'), local,
              workspace: workspace),
          IdentityFamiliarity.knownElsewhere);
      // Name known only in the workspace, email known nowhere.
      expect(
          gradeIdentity((name: 'worflor', email: 'typo@wrong.dev'), local,
              workspace: workspace),
          IdentityFamiliarity.newEmail);
      // Unseen across the entire workspace: the full stranger claim.
      expect(
          gradeIdentity(
              (name: 'hijacked', email: 'evil@example.com'), local,
              workspace: workspace),
          IdentityFamiliarity.stranger);
    });

    test('empty history grades everyone resident — fresh repos scold no one',
        () async {
      // No commits at all: nothing to compare against.
      final authors = await getHistoricalAuthors(repo);
      expect(authors.emails, isEmpty);
      expect(
          gradeIdentity((name: 'anyone', email: 'any@where.io'), authors),
          IdentityFamiliarity.resident);
    });
  });

  group('prepareCommitStaging with unmerged paths', () {
    test('conflicted files are left alone by the staging walk', () async {
      // Real UU conflict: two branches editing the same line.
      await commitFile('c.txt', 'base\n', 'base');
      await wf('clean.txt').writeAsString('clean1\n');
      await git(['add', '--', 'clean.txt']);
      await git(['commit', '-qm', 'add clean']);
      await git(['checkout', '-qb', 'side']);
      await commitFile('c.txt', 'side\n', 'side edit');
      await git(['checkout', '-q', 'main']);
      await commitFile('c.txt', 'main\n', 'main edit');
      final merge = await git(['merge', 'side']);
      expect(merge.exitCode, isNot(0), reason: 'fixture needs a conflict');
      expect(await hasUnmergedPaths(repo), isTrue);

      // Include a clean modification; the conflicted path is neither
      // included nor excluded — the walk must skip it entirely.
      await wf('clean.txt').writeAsString('clean2\n');
      final plan = await prepareCommitStaging(repo, ['clean.txt']);
      expect(plan.ok, isTrue, reason: plan.error ?? '');
      expect(
          plan.data!.excludedEntries.map((e) => e.path), isNot(contains('c.txt')));

      // The unmerged stages survive untouched.
      expect(await hasUnmergedPaths(repo), isTrue);
      final stages = (await git(['ls-files', '-u'])).stdout as String;
      expect(stages, contains('c.txt'));
    });
  });
}
