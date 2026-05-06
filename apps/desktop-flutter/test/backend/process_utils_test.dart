import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/process_utils.dart';

void main() {
  test('killProcessTree waits for the target process to exit', () async {
    final process = Platform.isWindows
        ? await Process.start(
            'cmd',
            ['/c', 'ping', '-n', '30', '127.0.0.1'],
            runInShell: false,
          )
        : await Process.start(
            'sh',
            ['-c', 'sleep 30'],
            runInShell: false,
          );

    try {
      expect(await isProcessAlive(process.pid), isTrue);

      final killed = await killProcessTree(
        process,
        timeout: const Duration(seconds: 5),
      );

      expect(killed, isTrue);
      await process.exitCode.timeout(const Duration(seconds: 1));
      expect(await isProcessAlive(process.pid), isFalse);
    } finally {
      if (await isProcessAlive(process.pid)) {
        process.kill();
      }
    }
  });
}
