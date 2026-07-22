// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// change_id_test.dart — laws for stable change identity.
//
// CONTRACTS pinned here (every claim asserted against independent git
// plumbing as the oracle, per the house LAW — see history_surgery_test.dart):
//
//  C1  Reverse-hex algebra: alphabet is exactly "zyxwvutsrqponmlk"
//      (nibble 0 → 'z', 15 → 'k'); encode∘decode is the identity on all
//      16-byte inputs; parse rejects anything not 32 chars of k–z.
//  C2  generateChangeId always yields a valid id; seeded RNG makes it
//      deterministic; distinct draws are distinct.
//  C3  syntheticChangeIdForCommit is jj's derivation byte-for-byte: last
//      16 bytes of the object name, byte-order reversed, each byte
//      bit-reversed — for SHA-1 (40-hex) and SHA-256 (64-hex) names.
//  C4  parseCommitHeaders reads real commit objects: finds the declared
//      change-id, flags gpgsig/gpgsig-sha256 (including continuation
//      lines), returns null for non-commit buffers, and treats malformed
//      id values as absent.
//  C5  stampChangeId is byte-exact: deleting the inserted header line
//      from its output reproduces the input EXACTLY; it refuses signed
//      and already-stamped commits.
//  C6  createCommit(stampChangeId: true) stamps: the new HEAD carries a
//      valid change-id header, `git fsck` stays clean, the worktree/index
//      stay clean (same tree), and the reported commitHash IS the stamped
//      sha. Stamping is OPT-IN: the default (C6b) writes NO header,
//      rewrites nothing, and leaves exactly one reflog entry — byte-
//      identical behavior to the pre-identity era.
//  C7  Amend preserves identity: createCommit(amend) keeps the SAME
//      change-id on a new sha. Amending a foreign (unstamped) commit
//      mints a fresh durable id.
//  C8  Signed commits are skipped, never rewritten: stampHeadChangeId
//      returns the original sha, no warning, object bytes untouched.
//  C9  Byte fidelity under hostile payload: a commit whose message is
//      invalid UTF-8 round-trips through the stamp with every non-header
//      byte identical.
//  C10 changeIdOfCommit: declared header wins; foreign commits resolve
//      to the synthetic fallback; unresolvable revs resolve to null.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/change_id.dart';
import 'package:git_desktop/backend/git.dart';

import '../support/prop.dart';
import '../support/scratch_repo.dart';

/// Raw bytes of a commit object — oracle-side read, independent of the
/// production `_catFileCommitBytes` under test.
Future<Uint8List> _rawCommit(ScratchRepo repo, String rev) async {
  final r = await Process.run(
    'git',
    ['cat-file', 'commit', rev],
    workingDirectory: repo.dir.path,
    stdoutEncoding: null,
    stderrEncoding: null,
  );
  expect(r.exitCode, 0, reason: 'oracle cat-file failed: ${r.stderr}');
  return Uint8List.fromList(r.stdout as List<int>);
}

/// Writes [bytes] as a commit object via plumbing and returns the sha —
/// oracle-side forge for commits the production API refuses to make
/// (signed, non-UTF-8 message).
Future<String> _forgeCommit(ScratchRepo repo, List<int> bytes) async {
  final proc = await Process.start(
    'git',
    ['hash-object', '-t', 'commit', '-w', '--stdin'],
    workingDirectory: repo.dir.path,
  );
  proc.stdin.add(bytes);
  await proc.stdin.close();
  final sha = (await proc.stdout.transform(utf8.decoder).join()).trim();
  await proc.stderr.drain<void>();
  expect(await proc.exitCode, 0, reason: 'oracle hash-object failed');
  expect(sha, isNotEmpty);
  return sha;
}

/// The header block lines of a raw commit (up to the blank separator),
/// decoded leniently for assertions that only touch ASCII header keys.
List<String> _headerLines(Uint8List raw) {
  final sep = _blankLineOffset(raw);
  return const LineSplitter()
      .convert(String.fromCharCodes(raw.sublist(0, sep)));
}

int _blankLineOffset(Uint8List raw) {
  var lineStart = 0;
  while (lineStart < raw.length) {
    if (raw[lineStart] == 0x0a) return lineStart;
    while (lineStart < raw.length && raw[lineStart] != 0x0a) {
      lineStart++;
    }
    lineStart++;
  }
  fail('no header/message separator in commit bytes');
}

void main() {
  group('C1 reverse-hex algebra', () {
    test('alphabet anchors', () {
      expect(ChangeId.fromBytes(List.filled(16, 0x00)).value, 'z' * 32);
      expect(ChangeId.fromBytes(List.filled(16, 0xff)).value, 'k' * 32);
      // 0x01 → nibbles (0,1) → 'z','y'; 0xf0 → (15,0) → 'k','z';
      // 0x4a → (4,10) → 'v','p'.
      expect(
        ChangeId.fromBytes([0x01, 0xf0, 0x4a, ...List.filled(13, 0)])
            .value
            .substring(0, 6),
        'zykzvp',
      );
    });

    test('encode∘decode is the identity (property)', () {
      final rng = Random(20260722);
      for (var i = 0; i < 500 * fuzzScale(); i++) {
        final bytes =
            Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
        final id = ChangeId.fromBytes(bytes);
        expect(id.toBytes(), bytes);
        expect(ChangeId.tryParse(id.value), isNotNull);
      }
    });

    test('parse rejects the wrong shapes', () {
      expect(ChangeId.tryParse(''), isNull);
      expect(ChangeId.tryParse('z' * 31), isNull);
      expect(ChangeId.tryParse('z' * 33), isNull);
      // 'j' is one below the alphabet floor; '0'/'a'/'A' are hex-world.
      expect(ChangeId.tryParse('j${'z' * 31}'), isNull);
      expect(ChangeId.tryParse('0${'z' * 31}'), isNull);
      expect(ChangeId.tryParse('a${'z' * 31}'), isNull);
      expect(ChangeId.tryParse('A${'z' * 31}'), isNull);
      expect(ChangeId.tryParse('mlqnqnkrxpuvuuxzlzoltostwlwyskpx'), isNotNull);
      expect(() => ChangeId.parse('nope'), throwsFormatException);
    });

    test('uppercase reads (jj decoder parity), canonicalized to lowercase',
        () {
      // jj's hex_util decoder accepts K-Z alongside k-z; its writer and
      // validators are lowercase-only. Match: read both, store lowercase.
      final upper = ChangeId.tryParse('MLQNQNKRXPUVUUXZLZOLTOSTWLWYSKPX');
      expect(upper, isNotNull);
      expect(upper!.value, 'mlqnqnkrxpuvuuxzlzoltostwlwyskpx');
      final mixed = ChangeId.tryParse('MlqnqnkrxpuvuuxzlzoltostwlwyskpX');
      expect(mixed!.value, 'mlqnqnkrxpuvuuxzlzoltostwlwyskpx');
      // 'J'/'A' stay invalid in either case.
      expect(ChangeId.tryParse('J${'z' * 31}'), isNull);
    });

    test('fromBytes rejects wrong lengths', () {
      expect(() => ChangeId.fromBytes(List.filled(15, 0)), throwsArgumentError);
      expect(() => ChangeId.fromBytes(List.filled(17, 0)), throwsArgumentError);
    });
  });

  group('C2 generation', () {
    test('seeded generation is deterministic and valid', () {
      final a = generateChangeId(rng: Random(7));
      final b = generateChangeId(rng: Random(7));
      expect(a.value, b.value);
      expect(ChangeId.tryParse(a.value), isNotNull);
    });

    test('draws are distinct', () {
      final seen = <String>{};
      for (var i = 0; i < 256; i++) {
        expect(seen.add(generateChangeId().value), isTrue);
      }
    });
  });

  group('C3 synthetic derivation (jj-compatible)', () {
    test('anchors', () {
      expect(syntheticChangeIdForCommit('0' * 40).value, 'z' * 32);
      expect(syntheticChangeIdForCommit('f' * 40).value, 'k' * 32);
      // sha whose LAST byte is 0x01: after byte-order reversal it leads;
      // bit-reversed 0x01 = 0x80 → nibbles (8,0) → 'r','z'.
      final sha = '${'0' * 38}01';
      expect(syntheticChangeIdForCommit(sha).value, 'rz${'z' * 30}');
    });

    test('sha256 names use the last 16 bytes too', () {
      // 64-hex name: bytes 16..31 are the tail. Make byte 31 = 0x03
      // (bit-reversed 0xc0 → 'nz' leads) and byte 16 = 0xff (→ 'kk'
      // trails after reversal).
      final name = '${'0' * 32}ff${'0' * 28}03';
      final id = syntheticChangeIdForCommit(name).value;
      expect(id.substring(0, 2), 'nz');
      expect(id.substring(30), 'kk');
    });

    test('rejects non-hex and short names', () {
      expect(() => syntheticChangeIdForCommit('xyz'), throwsArgumentError);
      expect(
        () => syntheticChangeIdForCommit('g' * 40),
        throwsArgumentError,
      );
    });
  });

  group('C4/C5 header scan + stamp (pure bytes)', () {
    Uint8List commitBytes({
      List<String> extraHeaders = const [],
      List<int>? message,
    }) {
      final head = [
        'tree 2e81171448eb9f2ee3821e3d447aa6b2fe3ddba1',
        'parent a0e6d0b4de8d38f1e4ed0e94307b6d475df68e13',
        'author A U Thor <a@t> 1750000000 +0000',
        'committer A U Thor <a@t> 1750000000 +0000',
        ...extraHeaders,
      ].join('\n');
      return Uint8List.fromList([
        ...utf8.encode(head),
        0x0a,
        0x0a,
        ...(message ?? utf8.encode('subject\n\nbody\n')),
      ]);
    }

    test('scan finds a declared id and the separator', () {
      final id = generateChangeId(rng: Random(1));
      final raw = commitBytes(extraHeaders: ['change-id ${id.value}']);
      final scan = parseCommitHeaders(raw)!;
      expect(scan.changeId?.value, id.value);
      expect(scan.hasSignature, isFalse);
      expect(raw[scan.headerEndOffset], 0x0a);
    });

    test('malformed declared ids read as absent', () {
      final raw = commitBytes(extraHeaders: ['change-id not-an-id']);
      expect(parseCommitHeaders(raw)!.changeId, isNull);
    });

    test('gpgsig with continuation lines is a signature', () {
      final raw = commitBytes(extraHeaders: [
        'gpgsig -----BEGIN PGP SIGNATURE-----',
        ' aGVsbG8=',
        ' -----END PGP SIGNATURE-----',
      ]);
      final scan = parseCommitHeaders(raw)!;
      expect(scan.hasSignature, isTrue);
      // Continuation lines must not be misread as keys.
      expect(scan.changeId, isNull);
      expect(parseCommitHeaders(commitBytes(
              extraHeaders: ['gpgsig-sha256 xxxx']))!
          .hasSignature,
          isTrue);
    });

    test('non-commit buffers scan to null', () {
      expect(parseCommitHeaders(utf8.encode('no separator anywhere')), isNull);
      expect(parseCommitHeaders(const []), isNull);
    });

    test('stamp is byte-exact removal-invertible (property)', () {
      final rng = Random(20260723);
      for (var i = 0; i < 200 * fuzzScale(); i++) {
        // Hostile message bytes: arbitrary, including invalid UTF-8.
        final msg = List.generate(rng.nextInt(200), (_) => rng.nextInt(256));
        final raw = commitBytes(message: msg);
        final id = generateChangeId(rng: rng);
        final stamped = stampChangeId(raw, id);
        // The inserted line is exactly one header line before the blank.
        final line = utf8.encode('change-id ${id.value}\n');
        final at = _blankLineOffset(raw);
        expect(stamped.sublist(0, at), raw.sublist(0, at));
        expect(stamped.sublist(at, at + line.length), line);
        expect(stamped.sublist(at + line.length), raw.sublist(at));
        // And it round-trips through the scanner.
        expect(parseCommitHeaders(stamped)!.changeId?.value, id.value);
      }
    });

    test('stamp refuses signed and already-stamped commits', () {
      final id = generateChangeId(rng: Random(2));
      expect(
        () => stampChangeId(
            commitBytes(extraHeaders: ['change-id ${id.value}']), id),
        throwsStateError,
      );
      expect(
        () => stampChangeId(commitBytes(extraHeaders: ['gpgsig xx']), id),
        throwsStateError,
      );
      expect(() => stampChangeId(utf8.encode('garbage'), id),
          throwsStateError);
    });

    test('duplicate change-id keys: FIRST wins, matching gix/jj readers',
        () {
      final a = generateChangeId(rng: Random(3));
      final b = generateChangeId(rng: Random(4));
      final scan = parseCommitHeaders(commitBytes(extraHeaders: [
        'change-id ${a.value}',
        'change-id ${b.value}',
      ]))!;
      expect(scan.changeId?.value, a.value);
      expect(scan.hasChangeIdKey, isTrue);
      // First-wins holds even when the FIRST is malformed: readers that
      // take the first key resolve nothing, and so must we.
      final malformedFirst = parseCommitHeaders(commitBytes(extraHeaders: [
        'change-id not-valid',
        'change-id ${b.value}',
      ]))!;
      expect(malformedFirst.changeId, isNull);
      expect(malformedFirst.hasChangeIdKey, isTrue);
    });

    test('stamp refuses a commit whose change-id key is malformed', () {
      // Adding a second key next to a malformed one would make
      // first-wins readers resolve garbage while we resolve ours.
      final id = generateChangeId(rng: Random(5));
      expect(
        () => stampChangeId(
            commitBytes(extraHeaders: ['change-id definitely-wrong']), id),
        throwsStateError,
      );
      // Valueless key (bare `change-id` line) is still a key.
      expect(
        () => stampChangeId(commitBytes(extraHeaders: ['change-id x']), id),
        throwsStateError,
      );
    });
  });

  group('C6–C10 against a real repository', () {
    late ScratchRepo repo;

    setUp(() async {
      repo = await ScratchRepo.create(name: 'change_id');
    });

    tearDown(() async {
      await repo.dispose();
    });

    test('C6 createCommit stamps a valid header, fsck-clean, tree-clean',
        () async {
      await repo.writeFile('a.txt', 'hello\n');
      await repo.stageAll();
      final res =
          await createCommit(repo.dir.path, 'first', stampChangeId: true);
      expect(res.ok, isTrue, reason: res.error);
      expect(res.changeIdWarning, isNull);

      final head = (await repo.head())!;
      // The reported hash IS the stamped sha, full-length.
      expect(res.data!.commitHash, head);
      final raw = await _rawCommit(repo, 'HEAD');
      final scan = parseCommitHeaders(raw)!;
      expect(scan.changeId, isNotNull);
      // Oracle: the header is exactly one line, well-formed.
      final headerLines = _headerLines(raw)
          .where((l) => l.startsWith('change-id '))
          .toList();
      expect(headerLines, hasLength(1));
      expect(
          ChangeId.tryParse(headerLines.single.substring('change-id '.length)),
          isNotNull);
      // Oracle: object store integrity + clean status (same tree).
      final fsck = await repo.git(['fsck', '--full', '--strict']);
      expect(fsck.exitCode, 0, reason: fsck.stderr.toString());
      final status = await repo.gitOk(['status', '--porcelain']);
      expect(status.trim(), isEmpty);
      // Message and author survive verbatim.
      expect(utf8.decode(raw.sublist(_blankLineOffset(raw) + 1)), 'first\n');
    });

    test('C6b default is OFF: no header, no rewrite, one reflog entry',
        () async {
      await repo.writeFile('plain.txt', 'x\n');
      await repo.stageAll();
      final reflogBefore =
          (await repo.gitOk(['reflog'])).trim().split('\n').length;
      final res = await createCommit(repo.dir.path, 'plain');
      expect(res.ok, isTrue, reason: res.error);
      expect(res.changeIdWarning, isNull);
      // No header written.
      final scan = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!;
      expect(scan.changeId, isNull,
          reason: 'stamping must be strictly opt-in');
      // Exactly ONE new reflog entry — the commit itself, no stamp move.
      final reflogAfter =
          (await repo.gitOk(['reflog'])).trim().split('\n').length;
      expect(reflogAfter, reflogBefore + 1,
          reason: 'default path must not rewrite the fresh commit');
      // Identity still resolves (synthetic fallback).
      final syn = await changeIdOfCommit(repo.dir.path, 'HEAD');
      expect(syn!.value,
          syntheticChangeIdForCommit((await repo.head())!).value);
    });

    test('C7 amend keeps the change-id on a new sha', () async {
      await repo.writeFile('a.txt', 'v1\n');
      await repo.stageAll();
      final first =
          await createCommit(repo.dir.path, 'subject', stampChangeId: true);
      expect(first.ok, isTrue, reason: first.error);
      final idBefore = (await changeIdOfCommit(repo.dir.path, 'HEAD'))!;
      final shaBefore = (await repo.head())!;

      await repo.writeFile('a.txt', 'v2\n');
      await repo.stageAll();
      final amended = await createCommit(repo.dir.path, 'better subject',
          amend: true, stampChangeId: true);
      expect(amended.ok, isTrue, reason: amended.error);

      final shaAfter = (await repo.head())!;
      expect(shaAfter, isNot(shaBefore));
      final scan = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!;
      expect(scan.changeId?.value, idBefore.value,
          reason: 'amend must carry the SAME change identity');
    });

    test('C7 amending a foreign commit mints a fresh durable id', () async {
      // A commit made by bare git (the root commit) has no header.
      final rootScan = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!;
      expect(rootScan.changeId, isNull);

      await repo.writeFile('b.txt', 'x\n');
      await repo.stageAll();
      final amended = await createCommit(repo.dir.path, 'adopted',
          amend: true, stampChangeId: true);
      expect(amended.ok, isTrue, reason: amended.error);
      final scan = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!;
      expect(scan.changeId, isNotNull);
    });

    test('C8 signed commits are skipped untouched', () async {
      // Forge a "signed" commit: real tree/parent, fake-but-shaped gpgsig.
      final tree = (await repo.gitOk(['rev-parse', 'HEAD^{tree}'])).trim();
      final parent = (await repo.head())!;
      final raw = utf8.encode([
        'tree $tree',
        'parent $parent',
        'author T <t@t> 1750000000 +0000',
        'committer T <t@t> 1750000000 +0000',
        'gpgsig -----BEGIN PGP SIGNATURE-----',
        ' aGVsbG8=',
        ' -----END PGP SIGNATURE-----',
        '',
        'signed subject\n',
      ].join('\n'));
      final sha = await _forgeCommit(repo, raw);
      await repo.gitOk(['update-ref', 'HEAD', sha]);

      final out = (await stampHeadChangeId(repo.dir.path))!;
      expect(out.sha, sha, reason: 'signed commit must not be rewritten');
      expect(out.changeId, isNull);
      expect(out.warning, isNull, reason: 'a deliberate skip is not a warning');
      expect(await _rawCommit(repo, 'HEAD'), raw,
          reason: 'object bytes untouched');
    });

    test('C9 invalid-UTF-8 message survives the stamp byte-for-byte',
        () async {
      final tree = (await repo.gitOk(['rev-parse', 'HEAD^{tree}'])).trim();
      final parent = (await repo.head())!;
      final hostileMessage = [
        0xC3, 0x28, // invalid 2-byte sequence
        0xF5, 0x90, // out-of-range lead
        0x80, // bare continuation
        ...utf8.encode(' latin-ish tail'),
        0x0a,
      ];
      final raw = [
        ...utf8.encode([
          'tree $tree',
          'parent $parent',
          'author T <t@t> 1750000000 +0000',
          'committer T <t@t> 1750000000 +0000',
        ].join('\n')),
        0x0a, 0x0a,
        ...hostileMessage,
      ];
      final sha = await _forgeCommit(repo, raw);
      await repo.gitOk(['update-ref', 'HEAD', sha]);

      final out = (await stampHeadChangeId(repo.dir.path))!;
      expect(out.changeId, isNotNull);
      expect(out.warning, isNull);
      expect(out.sha, isNot(sha));
      final stamped = await _rawCommit(repo, 'HEAD');
      final sep = _blankLineOffset(Uint8List.fromList(stamped));
      expect(stamped.sublist(sep + 1), hostileMessage,
          reason: 'message bytes must be verbatim');
      final fsck = await repo.git(['fsck', '--full']);
      expect(fsck.exitCode, 0, reason: fsck.stderr.toString());
    });

    test('bare `git commit --amend` preserves the header; stamp stays no-op',
        () async {
      // git itself copies extra headers forward on amend (verified on
      // git 2.52, matching jj's git-compatibility.md), so identity
      // survives even amends made OUTSIDE Manifold — and our post-amend
      // stamp must recognize that and not rewrite again.
      await repo.writeFile('n.txt', 'v1\n');
      await repo.stageAll();
      final res =
          await createCommit(repo.dir.path, 'native', stampChangeId: true);
      expect(res.ok, isTrue, reason: res.error);
      final born = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!
          .changeId!;
      await repo.writeFile('n.txt', 'v2\n');
      await repo.stageAll();
      await repo.gitOk(['commit', '--amend', '-m', 'bare amend']);
      final after = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!;
      expect(after.changeId?.value, born.value,
          reason: 'git carries the header through amend by itself');
      final shaAfter = (await repo.head())!;
      final stamp = (await stampHeadChangeId(repo.dir.path))!;
      expect(stamp.sha, shaAfter, reason: 'already stamped → no rewrite');
      expect(stamp.changeId?.value, born.value);
    });

    test('stampHeadChangeId is idempotent: second call is a no-op', () async {
      await repo.writeFile('i.txt', 'x\n');
      await repo.stageAll();
      final res =
          await createCommit(repo.dir.path, 'once', stampChangeId: true);
      expect(res.ok, isTrue, reason: res.error);
      final sha = (await repo.head())!;
      final again = (await stampHeadChangeId(repo.dir.path))!;
      expect(again.sha, sha, reason: 'no rewrite on an already-stamped HEAD');
      expect(again.changeId, isNotNull);
      expect(again.warning, isNull);
      expect((await repo.head())!, sha);
    });

    test('malformed foreign change-id key: skipped, never doubled', () async {
      final tree = (await repo.gitOk(['rev-parse', 'HEAD^{tree}'])).trim();
      final parent = (await repo.head())!;
      final raw = utf8.encode([
        'tree $tree',
        'parent $parent',
        'author T <t@t> 1750000000 +0000',
        'committer T <t@t> 1750000000 +0000',
        'change-id NOT-A-VALID-ID',
        '',
        'foreign subject\n',
      ].join('\n'));
      final sha = await _forgeCommit(repo, raw);
      await repo.gitOk(['update-ref', 'HEAD', sha]);
      final out = (await stampHeadChangeId(repo.dir.path))!;
      expect(out.sha, sha, reason: 'must not rewrite');
      expect(out.changeId, isNull);
      expect(out.warning, isNull, reason: 'deliberate skip, not a warning');
      expect(await _rawCommit(repo, 'HEAD'), raw);
      // Identity resolves via synthetic, and never to the garbage value.
      final resolved = await changeIdOfCommit(repo.dir.path, 'HEAD');
      expect(resolved!.value, syntheticChangeIdForCommit(sha).value);
    });

    test('update-ref failure degrades to a warning, HEAD intact', () async {
      await repo.writeFile('w.txt', 'x\n');
      await repo.stageAll();
      await repo.gitOk(['commit', '-m', 'unstamped']);
      final sha = (await repo.head())!;
      // Fail exactly the CAS update-ref; pass everything else through.
      final realRun = GitSpawn.runOverride;
      GitSpawn.runOverride = (args, {workingDirectory, environment}) async {
        if (args.isNotEmpty && args.first == 'update-ref') {
          return ProcessResult(0, 1, <int>[], utf8.encode('injected refusal'));
        }
        return (realRun ??
            (List<String> a,
                    {String? workingDirectory, Map<String, String>? environment}) =>
                Process.run('git', a,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    stdoutEncoding: null,
                    stderrEncoding: null))(args,
            workingDirectory: workingDirectory, environment: environment);
      };
      try {
        final out = (await stampHeadChangeId(repo.dir.path))!;
        expect(out.warning, isNotNull);
        expect(out.sha, sha, reason: 'reported sha stays the real HEAD');
      } finally {
        GitSpawn.reset();
      }
      expect((await repo.head())!, sha, reason: 'HEAD untouched');
      final scan = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!;
      expect(scan.changeId, isNull);
      final fsck = await repo.git(['fsck', '--full']);
      expect(fsck.exitCode, 0, reason: fsck.stderr.toString());
    });

    test('detached HEAD: stamp lands on HEAD itself, no branch moved',
        () async {
      final base = (await repo.head())!;
      await repo.gitOk(['checkout', '--detach', base]);
      await repo.writeFile('d.txt', 'x\n');
      await repo.stageAll();
      final res =
          await createCommit(repo.dir.path, 'detached', stampChangeId: true);
      expect(res.ok, isTrue, reason: res.error);
      expect(res.changeIdWarning, isNull);
      final scan = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!;
      expect(scan.changeId, isNotNull);
      // main never moved.
      expect((await repo.gitOk(['rev-parse', 'refs/heads/main'])).trim(),
          base);
    });

    test('C10 changeIdOfCommit: declared wins, synthetic covers the rest',
        () async {
      // Root commit: foreign, so synthetic.
      final rootSha = (await repo.head())!;
      final syn = await changeIdOfCommit(repo.dir.path, 'HEAD');
      expect(syn!.value, syntheticChangeIdForCommit(rootSha).value);

      await repo.writeFile('a.txt', 'x\n');
      await repo.stageAll();
      final res =
          await createCommit(repo.dir.path, 'stamped', stampChangeId: true);
      expect(res.ok, isTrue, reason: res.error);
      final declared = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!
          .changeId!;
      expect((await changeIdOfCommit(repo.dir.path, 'HEAD'))!.value,
          declared.value);

      expect(await changeIdOfCommit(repo.dir.path, 'no-such-rev'), isNull);
    });

    test('fuzz: identity is stable across randomized commit/amend chains',
        () async {
      final rng = Random(97);
      for (var round = 0; round < 3 * fuzzScale(); round++) {
        await repo.writeFile('f$round.txt', 'r$round\n');
        await repo.stageAll();
        final made = await createCommit(repo.dir.path, 'round $round',
            stampChangeId: true);
        expect(made.ok, isTrue, reason: made.error);
        final born = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!
            .changeId!;
        // A random number of amends; identity must never drift.
        final amends = rng.nextInt(3);
        for (var a = 0; a < amends; a++) {
          await repo.writeFile('f$round.txt', 'r$round-a$a\n');
          await repo.stageAll();
          final am = await createCommit(
              repo.dir.path, rng.nextBool() ? 'reword $a' : '',
              amend: true, stampChangeId: true);
          expect(am.ok, isTrue, reason: am.error);
          final now = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!
              .changeId!;
          expect(now.value, born.value);
        }
      }
      final fsck = await repo.git(['fsck', '--full']);
      expect(fsck.exitCode, 0, reason: fsck.stderr.toString());
    });
  });

  group('SHA-256 repositories', () {
    test('stamp + inherit + synthetic all hold under 64-hex oids', () async {
      final repo =
          await ScratchRepo.create(name: 'cid_sha256', objectFormat: 'sha256');
      try {
        await repo.writeFile('a.txt', 'v1\n');
        await repo.stageAll();
        final res =
            await createCommit(repo.dir.path, 'first', stampChangeId: true);
        expect(res.ok, isTrue, reason: res.error);
        final sha = (await repo.head())!;
        expect(sha.length, 64);
        final scan = parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!;
        final born = scan.changeId!;
        // Amend inherits across the bigger oid space too.
        await repo.writeFile('a.txt', 'v2\n');
        await repo.stageAll();
        final am = await createCommit(repo.dir.path, 'second',
            amend: true, stampChangeId: true);
        expect(am.ok, isTrue, reason: am.error);
        expect(parseCommitHeaders(await _rawCommit(repo, 'HEAD'))!
            .changeId!.value,
            born.value);
        // Synthetic fallback derives from the LAST 16 of 32 bytes.
        final rootSha =
            (await repo.gitOk(['rev-list', '--max-parents=0', 'HEAD']))
                .trim();
        final syn = await changeIdOfCommit(repo.dir.path, rootSha);
        expect(syn!.value, syntheticChangeIdForCommit(rootSha).value);
        final fsck = await repo.git(['fsck', '--full', '--strict']);
        expect(fsck.exitCode, 0, reason: fsck.stderr.toString());
      } finally {
        await repo.dispose();
      }
    });
  });
}
