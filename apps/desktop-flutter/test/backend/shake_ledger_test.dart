// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// shake_ledger_test.dart — the sweep's memory, and its blast radius.
//
// The bug these defend against was structural, not careless: reading a ledger
// TOLERATES failure (so a sweep can still run when the file is corrupt or the
// budget declines), and the first design then merged that tolerated-empty
// result back into a SHARED document. One unreadable moment erased every
// other repository's record. Per-repository documents make the cross-repo
// loss unrepresentable; these tests hold that line.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/shake_ledger.dart';
import 'package:git_desktop/backend/storage_paths.dart';

void main() {
  late Directory dataDir;

  setUp(() async {
    // Point the whole storage layer at a throwaway directory so these never
    // touch the developer's real ledgers.
    dataDir = Directory.systemTemp.createTempSync('shake_ledger_');
    StoragePaths.debugOverrideDir = dataDir;
  });

  tearDown(() async {
    StoragePaths.debugOverrideDir = null;
    try {
      dataDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('L1: a saved ledger reads back exactly', () async {
    final l = ShakeLedger.empty();
    l.mark('lib/a.dart', 'oid-a', '2026-01-01T00:00:00Z', findings: 2);
    l.mark('lib/b.dart', 'oid-b', '2026-01-02T00:00:00Z');
    await ShakeLedgerStore.save('/repo/one', l);

    final back = await ShakeLedgerStore.load('/repo/one');
    expect(back.examinedCount, 2);
    expect(back.recordFor('lib/a.dart')!.blobOid, 'oid-a');
    expect(back.recordFor('lib/a.dart')!.findings, 2);
    expect(back.recordFor('lib/b.dart')!.at, '2026-01-02T00:00:00Z');
    expect(back.isFresh('lib/a.dart', 'oid-a'), isTrue);
    expect(back.isFresh('lib/a.dart', 'oid-different'), isFalse);
  });

  test('L2: an unreadable ledger cannot harm ANOTHER repository', () async {
    // THE bug. Repo one is swept; repo two's ledger is then corrupted; a
    // sweep of repo two must degrade to "nothing examined here" WITHOUT
    // touching repo one's memory.
    final one = ShakeLedger.empty()
      ..mark('lib/keep.dart', 'oid-keep', '2026-01-01T00:00:00Z');
    await ShakeLedgerStore.save('/repo/one', one);

    final two = ShakeLedger.empty()
      ..mark('lib/other.dart', 'oid-other', '2026-01-01T00:00:00Z');
    await ShakeLedgerStore.save('/repo/two', two);

    // Corrupt ONLY repo two's document.
    final twoFile = File('${dataDir.path}${Platform.pathSeparator}shake'
        '${Platform.pathSeparator}${ShakeLedgerStore.fileNameFor('/repo/two')}');
    expect(twoFile.existsSync(), isTrue, reason: 'guard: found the document');
    await twoFile.writeAsString('{ this is not json');

    final reloadedTwo = await ShakeLedgerStore.load('/repo/two');
    expect(reloadedTwo.examinedCount, 0,
        reason: 'a corrupt ledger degrades to empty, which costs '
            're-examination and never a false claim of coverage');

    // Now sweep repo two and save — the step that used to rewrite the shared
    // document from an empty map.
    reloadedTwo.mark('lib/fresh.dart', 'oid-fresh', '2026-02-01T00:00:00Z');
    await ShakeLedgerStore.save('/repo/two', reloadedTwo);

    final reloadedOne = await ShakeLedgerStore.load('/repo/one');
    expect(reloadedOne.examinedCount, 1,
        reason: 'repo one was never involved and must be untouched');
    expect(reloadedOne.isFresh('lib/keep.dart', 'oid-keep'), isTrue);
  });

  test('L3: repositories get distinct documents, even with the same folder '
      'name', () {
    // The digest covers the whole path; the readable prefix is courtesy.
    final a = ShakeLedgerStore.fileNameFor('/home/me/projects/manifold');
    final b = ShakeLedgerStore.fileNameFor('/work/clients/manifold');
    expect(a, isNot(b));
    expect(a, contains('manifold'));
    expect(b, contains('manifold'));
  });

  test('L4: the name is stable across separator and case spellings', () {
    // The same repository reaches this spelled both ways — the picker's
    // native separators and git's forward slashes — and must not end up with
    // two ledgers.
    expect(
      ShakeLedgerStore.fileNameFor(r'C:\Users\me\Projects\Thing'),
      ShakeLedgerStore.fileNameFor('c:/users/me/projects/thing'),
    );
  });

  test('L5: the filename is legal on every platform', () {
    final name = ShakeLedgerStore.fileNameFor(r'C:\Users\mini server\A Repo!');
    for (final illegal in const ['/', r'\', ':', '*', '?', '"', '<', '>', '|', ' ']) {
      expect(name.contains(illegal), isFalse, reason: 'contains $illegal');
    }
    expect(name.endsWith('.json'), isTrue);
  });

  test('L6: forgetting one repository leaves the others alone', () async {
    await ShakeLedgerStore.save(
        '/repo/one', ShakeLedger.empty()..mark('a', 'oid', 'now'));
    await ShakeLedgerStore.save(
        '/repo/two', ShakeLedger.empty()..mark('b', 'oid', 'now'));

    await ShakeLedgerStore.forget('/repo/one');

    expect((await ShakeLedgerStore.load('/repo/one')).examinedCount, 0);
    expect((await ShakeLedgerStore.load('/repo/two')).examinedCount, 1);
  });

  test('L7: a never-swept repository loads empty rather than failing',
      () async {
    final l = await ShakeLedgerStore.load('/repo/never/seen');
    expect(l.examinedCount, 0);
    expect(l.isFresh('anything', 'anything'), isFalse);
  });

  test('L8: garbage records are skipped without losing the good ones', () {
    // Hand-edited or half-written documents must not take the whole ledger
    // down with them.
    final l = ShakeLedger.fromJson({
      'lib/good.dart': {'oid': 'oid-good', 'at': 'now', 'findings': 1},
      'lib/no_oid.dart': {'at': 'now'},
      'lib/empty_oid.dart': {'oid': ''},
      'lib/not_a_map.dart': 'nonsense',
      'lib/null.dart': null,
    });
    expect(l.examinedCount, 1);
    expect(l.recordFor('lib/good.dart')!.blobOid, 'oid-good');
    expect(l.recordFor('lib/no_oid.dart'), isNull);
  });
}
