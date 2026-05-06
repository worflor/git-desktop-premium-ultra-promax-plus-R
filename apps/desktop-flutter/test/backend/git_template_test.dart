import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProcessResult> git(Directory dir, List<String> args) {
    return Process.run(
      'git',
      args,
      workingDirectory: dir.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  test('templateFromRepository reports initial commit failures', () async {
    final root = await Directory.systemTemp.createTemp('gdpu_template_');
    try {
      final source = Directory('${root.path}${Platform.pathSeparator}source');
      await source.create();
      expect((await git(source, ['init', '-q', '-b', 'main'])).exitCode, 0);
      expect((await git(source, ['config', 'user.name', 'test'])).exitCode, 0);
      expect(
        (await git(source, ['config', 'user.email', 'test@local'])).exitCode,
        0,
      );
      expect(
        (await git(source, ['commit', '--allow-empty', '-m', 'empty']))
            .exitCode,
        0,
      );

      final target =
          '${root.path}${Platform.pathSeparator}empty-template-target';
      final result = await templateFromRepository(source.path, target);

      expect(result.ok, isFalse);
      expect(result.error, contains('Failed to commit template repository'));

      final head = await Process.run(
        'git',
        ['rev-parse', '--verify', 'HEAD'],
        workingDirectory: target,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(head.exitCode, isNot(0));
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
