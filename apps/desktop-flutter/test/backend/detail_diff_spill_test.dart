// The remote-detail streaming/spool contract and its export invariants.
//
// Every PR-detail diff STREAMS to a disk spool during transport (gh/glab CLI
// stdout via spoolForgeCliStdout, Gitea's `.diff` response, the local desk
// range diff) — a machine-scale patch never fully materializes in memory,
// even transiently. resolveDetailDiffSpool then reads the spool's REAL
// on-disk byte count: small → lenient String materialization + release;
// large → the spool is RETAINED as the detail's diffSpool.
//
// formatPrAsPatch is a data-integrity contract: on a spooled detail it must
// throw (in release mode too), never silently emit a header-only patch.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/gh.dart'
    show spoolForgeCliStdout, resolveDetailDiffSpool;
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/backend/remote_types.dart';

PullRequestSummary _summary() => PullRequestSummary(
  number: 7,
  title: 'spill contract',
  headRef: 'feature',
  baseRef: 'main',
  state: 'OPEN',
  isDraft: false,
  authorLogin: 'tester',
  conversationCount: 0,
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveDetailDiffSpool', () {
    test('the threshold reads REAL on-disk bytes — Unicode-heavy diffs '
        'cannot bypass it', () async {
      // CJK content: UTF-16 code units are ~1/3 of the UTF-8 bytes. A
      // String-length proxy would misjudge this; the spool's byteLength is
      // the encoded truth by construction.
      final rawDiff = '差' * 512;
      final spool = await spoolStringToTempFile(rawDiff);
      expect(
        spool.byteLength,
        utf8.encode(rawDiff).length,
        reason: 'byteLength IS the UTF-8 on-disk size',
      );

      // Below an injected threshold: materializes + releases the spool.
      final small = await resolveDetailDiffSpool(
        spool,
        spillBytes: spool.byteLength + 1,
      );
      expect(small.spill, isNull);
      expect(
        small.rawDiff,
        rawDiff,
        reason: 'small spools round-trip byte-exactly into the String form',
      );
      expect(
        File(spool.path).existsSync(),
        isFalse,
        reason: 'the materialized spool is released',
      );

      // Above the threshold: the spool is RETAINED, no String exists.
      final spool2 = await spoolStringToTempFile(rawDiff);
      final large = await resolveDetailDiffSpool(
        spool2,
        spillBytes: spool2.byteLength - 1,
      );
      expect(large.spill, isNotNull);
      expect(large.rawDiff, isEmpty);
      expect(File(spool2.path).existsSync(), isTrue);
      await spool2.dispose();
    });
  });

  group('spoolForgeCliStdout', () {
    test(
      'streams a real CLI stdout to a spool; nonzero exit is an error',
      () async {
        // `git` is the one CLI guaranteed present in this environment — the
        // helper is exe-agnostic (gh/glab share it).
        final ok = await spoolForgeCliStdout('git', '.', ['version']);
        expect(ok.ok, isTrue, reason: ok.error);
        final spool = ok.data!;
        expect(spool.byteLength, greaterThan(0));
        expect(
          await readSpoolStringLenient(spool.path),
          contains('git version'),
        );
        await spool.dispose();

        final bad = await spoolForgeCliStdout('git', '.', [
          'definitely-not-a-verb',
        ]);
        expect(
          bad.ok,
          isFalse,
          reason: 'a failed fetch must be an error, never an empty spool',
        );

        final missing = await spoolForgeCliStdout(
          'no-such-binary-manifold',
          '.',
          ['x'],
        );
        expect(missing.ok, isFalse);
      },
    );
  });

  group('PullRequestDetail.hasDiff', () {
    test(
      'a spooled detail IS fully loaded (never re-fetch the largest PRs)',
      () async {
        final spool = await spoolStringToTempFile('diff --git a/a b/a\n+x\n');
        try {
          final spooled = PullRequestDetail(
            body: '',
            files: const [],
            comments: const [],
            diff: '',
            rawDiffByFile: const {},
            diffSpool: spool,
          );
          expect(
            spooled.hasDiff,
            isTrue,
            reason:
                'diff: "" + spool is the machine-scale FULL detail — '
                'a diff.isNotEmpty check misreads it as metadata-only and '
                'respools on every expand',
          );
        } finally {
          await spool.dispose();
        }

        const stringDetail = PullRequestDetail(
          body: '',
          files: [],
          comments: [],
          diff: 'diff --git a/a b/a\n+x\n',
          rawDiffByFile: {},
        );
        expect(stringDetail.hasDiff, isTrue);

        const metadataOnly = PullRequestDetail(
          body: '',
          files: [],
          comments: [],
          diff: '',
          rawDiffByFile: {},
        );
        expect(metadataOnly.hasDiff, isFalse);
      },
    );

    test('a legitimately EMPTY patch is LOADED — hasDiff and diffLoaded '
        'answer different questions', () {
      const loadedEmpty = PullRequestDetail(
        body: '',
        files: [],
        comments: [],
        diff: '',
        rawDiffByFile: {},
        diffLoaded: true,
      );
      expect(
        loadedEmpty.hasDiff,
        isFalse,
        reason: 'no content to act on (export/apply stay gated)',
      );
      expect(
        loadedEmpty.diffLoaded,
        isTrue,
        reason:
            'but loading is COMPLETE — a refetch guard keyed on '
            'hasDiff would re-fetch this detail on every expand, making '
            'the loaded-empty state unreachable',
      );

      const metadataOnly = PullRequestDetail(
        body: '',
        files: [],
        comments: [],
        diff: '',
        rawDiffByFile: {},
      );
      expect(
        metadataOnly.diffLoaded,
        isFalse,
        reason: 'an includeDiff:false fetch still wants a full load later',
      );
    });
  });

  group('readSpoolStringLenient', () {
    test('non-UTF-8 spool bytes degrade to U+FFFD, never throw', () async {
      // Latin-1 bytes (0xE9 = é) are invalid UTF-8 — exactly the shape a
      // repo with legacy-encoded content streams into a spool. A strict
      // readAsString() throws here; the small-diff rematerialization must
      // match the exec layer's lenient stdout decode instead.
      final dir = await Directory.systemTemp.createTemp('lenient_spool');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}${Platform.pathSeparator}latin1.diff');
      await f.writeAsBytes([
        ...utf8.encode('diff --git a/caf'),
        0xE9, // lone Latin-1 é — malformed in UTF-8
        ...utf8.encode('.txt b/x\n+line\n'),
      ]);

      await expectLater(
        f.readAsString(),
        throwsA(isA<FileSystemException>()),
        reason: 'premise: strict decoding really does throw on these bytes',
      );

      final lenient = await readSpoolStringLenient(f.path);
      expect(lenient, contains('diff --git a/caf'));
      expect(
        lenient,
        contains('\u{FFFD}'),
        reason:
            'malformed bytes degrade to the replacement character, '
            'matching what the String-fetch path always rendered',
      );
      expect(lenient, contains('+line'));
    });
  });

  group('spool identity', () {
    test('every fetch mints a unique spool path — the per-fetch component '
        'documentIds rely on', () async {
      // Same content, same byte length: byte length is a coincidence-prone
      // identity (a force-pushed PR can weigh exactly the same), so the
      // spool-backed documentIds embed spool.path, whose uniqueness per
      // fetch is pinned here.
      final a = await spoolStringToTempFile('identical content\n');
      final b = await spoolStringToTempFile('identical content\n');
      try {
        expect(a.byteLength, b.byteLength);
        expect(a.path, isNot(b.path));
      } finally {
        await a.dispose();
        await b.dispose();
      }
    });
  });

  group('formatPrAsPatch', () {
    test(
      'throws on a spooled detail instead of emitting a body-less patch',
      () async {
        final spool = await spoolStringToTempFile('diff --git a/a b/a\n+x\n');
        final detail = PullRequestDetail(
          body: 'body',
          files: const [],
          comments: const [],
          diff: '',
          rawDiffByFile: const {},
          diffSpool: spool,
        );
        try {
          expect(
            () => formatPrAsPatch(_summary(), detail),
            throwsArgumentError,
            reason:
                'a forgotten spool branch must fail loudly in release '
                'mode, never ship a truncated patch',
          );
        } finally {
          await spool.dispose();
        }
      },
    );

    test('composes header + diff for String details, byte-identical', () {
      const detail = PullRequestDetail(
        body: 'a body',
        files: [],
        comments: [],
        diff: 'diff --git a/a b/a\n+x\n',
        rawDiffByFile: {},
      );
      final s = _summary();
      expect(
        formatPrAsPatch(s, detail),
        '${prPatchHeader(s, detail)}${detail.diff}',
      );
      expect(
        formatPrAsPatch(s, detail),
        contains('---\n\ndiff --git'),
        reason: 'the header/body seam is exactly ---\\n\\n',
      );
    });
  });
}
