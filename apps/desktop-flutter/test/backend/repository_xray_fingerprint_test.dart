// Tests that the xray fingerprint includes staging state so the cache
// invalidates when the user stages/unstages without changing HEAD.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/repository_xray.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Repository xray fingerprint — staging awareness', () {
    test('same HEAD + file list but different staging yields different '
        'fingerprint', () async {
      // Status A: 3 files, 1 staged, 2 unstaged
      final statusA = const RepositoryStatus(
        branch: 'main',
        ahead: 0,
        behind: 0,
        files: [
          RepositoryStatusFile(path: 'a.dart', staged: 'M', unstaged: ' '),
          RepositoryStatusFile(path: 'b.dart', staged: ' ', unstaged: 'M'),
          RepositoryStatusFile(path: 'c.dart', staged: ' ', unstaged: 'M'),
        ],
      );
      // Status B: same files, but 2 staged, 1 unstaged (staging drift)
      final statusB = const RepositoryStatus(
        branch: 'main',
        ahead: 0,
        behind: 0,
        files: [
          RepositoryStatusFile(path: 'a.dart', staged: 'M', unstaged: ' '),
          RepositoryStatusFile(path: 'b.dart', staged: 'M', unstaged: ' '),
          RepositoryStatusFile(path: 'c.dart', staged: ' ', unstaged: 'M'),
        ],
      );
      final fingerprintA = await computeRepositoryXrayFingerprint(
        r'C:\repo',
        (_) async => GitResult.ok(statusA),
        _fakeHeadProbe,
      );
      final fingerprintB = await computeRepositoryXrayFingerprint(
        r'C:\repo',
        (_) async => GitResult.ok(statusB),
        _fakeHeadProbe,
      );
      expect(fingerprintA.ok, isTrue);
      expect(fingerprintB.ok, isTrue);
      expect(fingerprintA.data, isNot(fingerprintB.data),
          reason: 'fingerprint must differ when staging changes');
    });

    test('identical staging produces identical fingerprint', () async {
      final status = const RepositoryStatus(
        branch: 'main',
        ahead: 0,
        behind: 0,
        files: [
          RepositoryStatusFile(path: 'a.dart', staged: 'M', unstaged: ' '),
        ],
      );
      final f1 = await computeRepositoryXrayFingerprint(
        r'C:\repo',
        (_) async => GitResult.ok(status),
        _fakeHeadProbe,
      );
      final f2 = await computeRepositoryXrayFingerprint(
        r'C:\repo',
        (_) async => GitResult.ok(status),
        _fakeHeadProbe,
      );
      expect(f1.data, f2.data);
    });
  });
}

Future<ProcessResult> _fakeHeadProbe(String repo, List<String> args) async {
  return ProcessResult(0, 0, 'abc123\n', '');
}
