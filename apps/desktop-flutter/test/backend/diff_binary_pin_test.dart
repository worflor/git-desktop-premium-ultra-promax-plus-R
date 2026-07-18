// Config-immunity pin for `diff.binary` (see _kDiffCmd/_kShowCmd in
// lib/backend/git.dart).
//
// A user's `[diff] binary = true` makes every binary change emit its full
// base85 `GIT binary patch` payload inline — a multi-GB blob becomes a
// multi-GB stdout String, and the churn-based spool gates in the History UI
// cannot see it coming because `--numstat` reports `-` (parsed as 0) for
// binary files. The pin forces the canonical one-line
// `Binary files a/x and b/x differ` form on every textual-diff path, so the
// binary case is tiny on the String path regardless of hostile config.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';

import '../support/scratch_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScratchRepo repo;

  Future<void> writeBytes(String relPath, List<int> bytes) => File(
    '${repo.dir.path}${Platform.pathSeparator}$relPath',
  ).writeAsBytes(bytes, flush: true);

  setUp(() async {
    repo = await ScratchRepo.create(name: 'diff_binary_pin');
    // The hostile direction: user config that inlines binary payloads.
    await repo.gitOk(['config', 'diff.binary', 'true']);
    await writeBytes('blob.bin', List<int>.generate(4096, (i) => i % 251));
    await repo.commitAll('binary base');
    await writeBytes(
      'blob.bin',
      List<int>.generate(4096, (i) => (i * 7 + 3) % 251),
    );
  });

  tearDown(() => repo.dispose());

  test(
    'spoolCommitDiff never inlines a binary payload under diff.binary=true',
    () async {
      await repo.commitAll('binary change');
      final head = (await repo.head())!;
      final r = await spoolCommitDiff(repo.dir.path, head);
      expect(r.ok, isTrue, reason: r.error);
      final spool = r.data!;
      addTearDown(spool.dispose);
      final text = await readSpoolStringLenient(spool.path);
      expect(
        text,
        contains('Binary files'),
        reason: 'the canonical one-line marker must survive',
      );
      expect(
        text,
        isNot(contains('GIT binary patch')),
        reason:
            'diff.binary=true leaked a full base85 payload through the '
            'pin — a huge blob would materialize as a huge spool file here',
      );
    },
  );

  test('getFileDiffAtRevision never inlines a binary payload under '
      'diff.binary=true', () async {
    await repo.commitAll('binary change');
    final head = (await repo.head())!;
    final r = await getFileDiffAtRevision(repo.dir.path, 'blob.bin', head);
    expect(r.ok, isTrue, reason: r.error);
    expect(r.data, contains('Binary files'));
    expect(r.data, isNot(contains('GIT binary patch')));
  });

  test(
    'stashShow never inlines a binary payload under diff.binary=true',
    () async {
      final st = await repo.git(['stash', 'push', '-m', 'bin stash']);
      expect(st.exitCode, 0, reason: st.stderr.toString());
      final r = await stashShow(repo.dir.path);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data, isNot(contains('GIT binary patch')));
    },
  );
}
