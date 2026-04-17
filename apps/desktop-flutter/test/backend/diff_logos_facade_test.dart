import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:git_desktop/backend/diff_logos_facade.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/features/diff/diff_models.dart';

Future<ProcessResult> _git(Directory dir, List<String> args) {
  return Process.run(
    'git',
    args,
    workingDirectory: dir.path,
    stdoutEncoding: const SystemEncoding(),
    stderrEncoding: const SystemEncoding(),
  );
}

Future<String> _gitStdout(Directory dir, List<String> args) async {
  final result = await _git(dir, args);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return result.stdout.toString();
}

Future<Directory> _initRepo() async {
  final dir = await Directory.systemTemp.createTemp('diff_logos_facade_test_');
  await _gitStdout(dir, ['init']);
  await _gitStdout(dir, ['config', 'user.email', 'codex@example.com']);
  await _gitStdout(dir, ['config', 'user.name', 'Codex Test']);

  final libDir = Directory('${dir.path}${Platform.pathSeparator}lib');
  final testDir = Directory('${dir.path}${Platform.pathSeparator}test');
  await libDir.create(recursive: true);
  await testDir.create(recursive: true);

  await File('${libDir.path}${Platform.pathSeparator}foo.dart')
      .writeAsString('''
int computeValue(int n) {
  if (n > 0) {
    return n;
  }
  return 0;
}
''');
  await File('${libDir.path}${Platform.pathSeparator}bar.dart')
      .writeAsString('''
String describeValue(int n) {
  return 'value: \$n';
}
''');
  await File('${testDir.path}${Platform.pathSeparator}foo_test.dart')
      .writeAsString('''
void main() {
  // placeholder
}
''');

  await _gitStdout(dir, ['add', '.']);
  await _gitStdout(dir, ['commit', '-m', 'base']);

  await File('${libDir.path}${Platform.pathSeparator}foo.dart')
      .writeAsString('''
int computeValue(int n) {
  if (n >= 10) {
    return n * 2;
  }
  if (n > 0) {
    return n;
  }
  return -1;
}
''');
  return dir;
}

LogosGit _warmEngine() {
  final matrix = FileCouplingMatrix(
    jaccard: const {
      'lib/foo.dart': {
        'test/foo_test.dart': 0.72,
        'lib/bar.dart': 0.28,
      },
      'test/foo_test.dart': {
        'lib/foo.dart': 0.72,
      },
      'lib/bar.dart': {
        'lib/foo.dart': 0.28,
      },
    },
    headHash: 'test-head',
    commitsAnalyzed: 12,
  );
  final stats = LogosGitStats(
    touches: const {
      'lib/foo.dart': 12,
      'test/foo_test.dart': 8,
      'lib/bar.dart': 6,
    },
    totalCommits: 12,
    rawTouches: const {
      'lib/foo.dart': 12,
      'test/foo_test.dart': 8,
      'lib/bar.dart': 6,
    },
    rawTotalCommits: 12,
    touchMass: const {
      'lib/foo.dart': 12,
      'test/foo_test.dart': 8,
      'lib/bar.dart': 6,
    },
    semanticCommitMass: 26,
    volatility: const {
      'lib/foo.dart': 1.0,
      'test/foo_test.dart': 0.8,
      'lib/bar.dart': 0.6,
    },
    volMean: 0.8,
    volStddev: 0.15,
    coupling: matrix,
    perFileCommitIndices: const {},
    integrityByPath: const {
      'lib/foo.dart': 0.95,
      'test/foo_test.dart': 0.88,
    },
    integrityReasonsByPath: const {
      'lib/foo.dart': ['hot path is mirrored by tests'],
    },
  );
  return LogosGit.buildFromStats(stats);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiffLogosFacade', () {
    test('analyzeDiff produces hunk and file signals for a real repo diff',
        () async {
      final repo = await _initRepo();
      addTearDown(() => repo.delete(recursive: true));
      final engine = _warmEngine();

      final diffText = await _gitStdout(repo, ['diff', '--', 'lib/foo.dart']);
      final session = await DiffLogosFacade.instance.openSession(
        DiffLogosRequest(
          repositoryPath: repo.path,
          diffText: diffText,
          warmEngine: engine,
        ),
      );

      expect(session.shape.primaryCount, 1);
      final fileSignal = session.filesByPath['lib/foo.dart'];
      expect(fileSignal?.isPrimary, isTrue);
      final relatedSignal = session.filesByPath['test/foo_test.dart'];
      expect(relatedSignal, isNotNull);
      expect(relatedSignal?.transportedSupport, isNotNull);
      expect(relatedSignal?.witnessResidual, isNotNull);
      final hunk =
          session.hunksByKey[DiffLogosSession.hunkKey('lib/foo.dart', 0)];
      expect(hunk, isNotNull);
      expect(hunk!.tag, 'flow');
      expect(hunk.importance, greaterThanOrEqualTo(0.0));
      expect(hunk.transportedSupport, isNotNull);
      expect(hunk.innovationResidual, isNotNull);
      expect(hunk.witnessResidual, isNotNull);
    });

    test('analyzeFileContext tags flow hunks and keeps nearby context visible',
        () async {
      const diffText = '''
diff --git a/lib/foo.dart b/lib/foo.dart
index 1111111..2222222 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,7 +1,9 @@
 int computeValue(int n) {
-  if (n > 0) {
+  if (n >= 10) {
+    return n * 2;
+  }
+  if (n > 0) {
     return n;
   }
-  return 0;
+  return -1;
 }
''';
      final parsed = parseUnifiedDiff(diffText);
      final session = DiffLogosFacade.instance.createSession(
        DiffLogosRequest(
          repositoryPath: Directory.systemTemp.path,
          diffText: diffText,
          parsedLines: parsed,
        ),
      );
      await session.refresh(
        DiffLogosRequest(
          repositoryPath: Directory.systemTemp.path,
          diffText: diffText,
          parsedLines: parsed,
        ),
      );
      final plan = await session.ensureFileContext(
        'lib/foo.dart',
        workingTreeContent: '''
int computeValue(int n) {
  if (n >= 10) {
    return n * 2;
  }
  if (n > 0) {
    return n;
  }
  return -1;
}
''',
      );
      expect(plan, isNotNull);
      final resolvedPlan = plan!;
      expect(resolvedPlan.semanticTags.values, contains('flow'));
      expect(resolvedPlan.headerHints.values, contains('branch'));
      expect(
        resolvedPlan.bandByFastKey.values
            .where((band) => band == DiffContextBand.near),
        isNotEmpty,
      );
    });

    test('session reuses unchanged file context across wider diff refreshes',
        () async {
      const fooDiff = '''
diff --git a/lib/foo.dart b/lib/foo.dart
index 1111111..2222222 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,7 +1,9 @@
 int computeValue(int n) {
-  if (n > 0) {
+  if (n >= 10) {
+    return n * 2;
+  }
+  if (n > 0) {
     return n;
   }
-  return 0;
+  return -1;
 }
''';
      const widerDiff = '''
diff --git a/lib/foo.dart b/lib/foo.dart
index 1111111..2222222 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,7 +1,9 @@
 int computeValue(int n) {
-  if (n > 0) {
+  if (n >= 10) {
+    return n * 2;
+  }
+  if (n > 0) {
     return n;
   }
-  return 0;
+  return -1;
 }
diff --git a/lib/bar.dart b/lib/bar.dart
index 3333333..4444444 100644
--- a/lib/bar.dart
+++ b/lib/bar.dart
@@ -1,3 +1,4 @@
 String describeValue(int n) {
+  final label = 'value';
-  return 'value: \$n';
+  return '\$label: \$n';
 }
''';
      const workingTreeContent = '''
int computeValue(int n) {
  if (n >= 10) {
    return n * 2;
  }
  if (n > 0) {
    return n;
  }
  return -1;
}
''';

      final session = DiffLogosFacade.instance.createSession(
        DiffLogosRequest(
          repositoryPath: Directory.systemTemp.path,
          diffText: fooDiff,
          parsedLines: parseUnifiedDiff(fooDiff),
        ),
      );
      await session.refresh(
        DiffLogosRequest(
          repositoryPath: Directory.systemTemp.path,
          diffText: fooDiff,
          parsedLines: parseUnifiedDiff(fooDiff),
        ),
      );
      final firstPlan = await session.ensureFileContext(
        'lib/foo.dart',
        workingTreeContent: workingTreeContent,
      );
      expect(firstPlan, isNotNull);

      await session.refresh(
        DiffLogosRequest(
          repositoryPath: Directory.systemTemp.path,
          diffText: widerDiff,
          parsedLines: parseUnifiedDiff(widerDiff),
        ),
      );
      final secondPlan = await session.ensureFileContext(
        'lib/foo.dart',
        workingTreeContent: workingTreeContent,
      );
      expect(secondPlan, isNotNull);
      expect(identical(firstPlan, secondPlan), isTrue);
    });

    test('analyzePinnedLine merges related files and provenance signals',
        () async {
      final engine = _warmEngine();
      const diffText = '''
diff --git a/lib/foo.dart b/lib/foo.dart
index 1111111..2222222 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,5 +1,5 @@
 int computeValue(int n) {
-  if (n > 0) {
+  if (n >= 10) {
     return n;
   }
   return 0;
''';
      final parsed = parseUnifiedDiff(diffText);
      final line = parsed.firstWhere((entry) => entry.kind == LineKind.added);
      final model = await DiffLogosFacade.instance.analyzePinnedLine(
        DiffPinnedLineRequest(
          repositoryPath: Directory.systemTemp.path,
          filePath: 'lib/foo.dart',
          line: line,
          displayLines: parsed,
          displayIndex: parsed.indexOf(line),
          couplingMatrix: engine.stats.coupling,
          warmEngine: engine,
        ),
      );

      expect(model.relatedFiles, isNotEmpty);
      expect(
        model.relatedFiles.any((file) => file.path == 'test/foo_test.dart'),
        isTrue,
      );
      expect(model.integrityReasons, isNotEmpty);
    });

    test('analyzePinnedLine de-clusters nearby echoes in one local pocket',
        () async {
      const diffText = '''
diff --git a/lib/foo.dart b/lib/foo.dart
index 1111111..2222222 100644
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -1,0 +1,6 @@
+if (flag) return value;
+if (flag) return value;
+if (flag) return value;
+if (flag) return value;
+if (flag) return value;
+if (flag) return value;
@@ -20,0 +27,3 @@
+if (flag) return value;
+if (flag) return value;
+if (flag) return value;
''';
      final parsed = parseUnifiedDiff(diffText);
      final line = parsed.firstWhere((entry) => entry.kind == LineKind.added);
      final model = await DiffLogosFacade.instance.analyzePinnedLine(
        DiffPinnedLineRequest(
          repositoryPath: null,
          filePath: 'lib/foo.dart',
          line: line,
          displayLines: parsed,
          displayIndex: parsed.indexOf(line),
        ),
      );

      expect(model.rhymePreviews, hasLength(2));
      expect(
        (model.rhymePreviews[1].displayIndex -
                model.rhymePreviews[0].displayIndex)
            .abs(),
        greaterThan(6),
      );
    });
  });
}
