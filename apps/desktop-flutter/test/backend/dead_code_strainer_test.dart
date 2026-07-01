import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dead_code_strainer.dart';

void main() {
  DeadCodeReport run(Map<String, String> files, {String pkg = 'x'}) {
    final inputs = [
      for (final e in files.entries) DeadCodeInput(e.key, e.value),
    ];
    return DeadCodeStrainer(packageName: pkg).analyze(inputs);
  }

  test('reaches the app closure via package: and relative imports', () {
    final r = run({
      'app/lib/main.dart': "import 'package:x/feature.dart';\nimport 'dart:io';",
      'app/lib/feature.dart': "import 'sub/helper.dart';",
      'app/lib/sub/helper.dart': '// leaf',
    });
    expect(r.fullyDead, isEmpty);
    expect(r.testZombies, isEmpty);
    expect(r.aliveLibFiles, 3);
  });

  test('flags a file imported only by a test as a test-zombie', () {
    final r = run({
      'app/lib/main.dart': '// nothing wired',
      'app/lib/zombie.dart': '// a widget nobody wired in',
      'app/test/widget_test.dart': "import 'package:x/zombie.dart';",
    });
    expect(r.testZombies.map((z) => z.path), contains('app/lib/zombie.dart'));
    expect(r.fullyDead, isEmpty);
    expect(r.testZombies.single.category, DeadCodeCategory.testZombie);
  });

  test('flags a file referenced by nothing as fully dead', () {
    final r = run({
      'app/lib/main.dart': "import 'used.dart';",
      'app/lib/used.dart': '// used',
      'app/lib/dead.dart': '// referenced by nobody',
    });
    expect(r.fullyDead.map((d) => d.path), contains('app/lib/dead.dart'));
    expect(r.testZombies, isEmpty);
  });

  test('part files ride on their parent and are never flagged or counted', () {
    final r = run({
      'app/lib/main.dart': "import 'core.dart';",
      'app/lib/core.dart': "part 'core_extra.dart';",
      'app/lib/core_extra.dart': "part of 'core.dart';\n// generated-ish body",
    });
    expect(r.fullyDead, isEmpty);
    expect(r.testZombies, isEmpty);
    expect(r.totalLibFiles, 2); // main + core; the part is excluded entirely
  });

  test('external packages and dart: imports are ignored, not crashes', () {
    final r = run({
      'app/lib/main.dart':
          "import 'package:flutter/material.dart';\nimport 'dart:async';\nimport 'real.dart';",
      'app/lib/real.dart': '// real',
    });
    expect(r.fullyDead, isEmpty);
    expect(r.aliveLibFiles, 2);
  });

  test('bin entries count as an app surface', () {
    final r = run({
      'app/lib/main.dart': '// app main imports nothing',
      'app/bin/cli.dart': "import 'package:x/cli_helper.dart';",
      'app/lib/cli_helper.dart': '// used by the CLI only',
    });
    expect(r.fullyDead, isEmpty);
    expect(r.testZombies, isEmpty); // reached from bin = alive, not zombie
    expect(r.aliveLibFiles, 2); // main + cli_helper
  });

  test('a whole dead cluster (files importing each other) is still dead', () {
    // dead_a <-> dead_b reference each other but nothing live reaches them.
    final r = run({
      'app/lib/main.dart': "import 'live.dart';",
      'app/lib/live.dart': '// live',
      'app/lib/dead_a.dart': "import 'dead_b.dart';",
      'app/lib/dead_b.dart': "import 'dead_a.dart';",
    });
    final dead = r.fullyDead.map((d) => d.path).toSet();
    expect(dead, containsAll(['app/lib/dead_a.dart', 'app/lib/dead_b.dart']));
  });

  test('windows-style separators in input paths are normalised', () {
    final r = run({
      r'app\lib\main.dart': "import 'feature.dart';",
      r'app\lib\feature.dart': '// leaf',
    });
    expect(r.fullyDead, isEmpty);
    expect(r.aliveLibFiles, 2);
  });

  test('a library package with no app entry is never flagged dead', () {
    final r = run({
      'pkg/lib/api.dart': "export 'internal.dart';",
      'pkg/lib/internal.dart': '// used by the public api',
      'pkg/lib/lonely.dart': '// referenced by nothing, but no main to judge from',
    });
    expect(r.hasAppEntry, isFalse);
    expect(r.fullyDead, isEmpty);
    expect(r.testZombies, isEmpty);
  });

  test('conditional-import fallbacks all count as edges, not dead', () {
    final r = run({
      'app/lib/main.dart':
          "import 'io_stub.dart' if (dart.library.io) 'io_real.dart';",
      'app/lib/io_stub.dart': '// web fallback',
      'app/lib/io_real.dart': '// native impl, reached only via the conditional',
    });
    expect(r.fullyDead, isEmpty);
    expect(r.aliveLibFiles, 3); // main + both conditional targets
  });

  test('flavored mains (main_dev.dart) count as app entries', () {
    final r = run({
      'app/lib/main_dev.dart': "import 'dev_only.dart';",
      'app/lib/dev_only.dart': '// reached only from the flavored main',
    });
    expect(r.fullyDead, isEmpty);
    expect(r.aliveLibFiles, 2);
  });

  test('root-package lib files (lib/ at repo root) are classified', () {
    final r = run({
      'lib/main.dart': "import 'used.dart';",
      'lib/used.dart': '// used',
      'lib/dead.dart': '// nothing references it',
    });
    expect(r.fullyDead.map((d) => d.path), contains('lib/dead.dart'));
    expect(r.aliveLibFiles, 2);
  });

  test('a directive wrapped across lines is captured whole', () {
    final r = run({
      'app/lib/main.dart': "import\n    'wrapped.dart';",
      'app/lib/wrapped.dart': '// reached via a line-wrapped import',
    });
    expect(r.fullyDead, isEmpty);
    expect(r.aliveLibFiles, 2);
  });

  test('a block-commented import does not forge a live edge', () {
    final r = run({
      'app/lib/main.dart': "import 'real.dart';\n/* import 'ghost.dart'; */",
      'app/lib/real.dart': '// real',
      'app/lib/ghost.dart': '// only referenced from inside a block comment',
    });
    expect(r.fullyDead.map((d) => d.path), contains('app/lib/ghost.dart'));
    expect(r.aliveLibFiles, 2); // main + real
  });
}
