import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_chunks.dart';
import 'package:git_desktop/backend/logos_git.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('packRelevantChunks', () {
    const content = '''
int alpha() {
  final x = 1;
  final y = x + 1;
  final z = y + 1;
  final q = z + 1;
  final r = q + 1;
  final s = r + 1;
  return y;
}

int beta() {
  final x = 2;
  final y = x + 2;
  final z = y + 2;
  final q = z + 2;
  final r = q + 2;
  final s = r + 2;
  return y;
}

int gamma() {
  final x = 3;
  final y = x + 3;
  final z = y + 3;
  final q = z + 3;
  final r = q + 3;
  final s = r + 3;
  return y;
}

int delta() {
  final x = 4;
  final y = x + 4;
  final z = y + 4;
  final q = z + 4;
  final r = q + 4;
  final s = r + 4;
  return y;
}
''';

    test('emits file-evidence annotation when tags are provided', () {
      final pack = packRelevantChunks(
        filePath: 'lib/sample.dart',
        content: content,
        touchedRanges: const [TouchedLineRange(1, 4)],
        budgetChars: 320,
        fileEvidenceTags: const [
          'lf=0.320',
          'hf=0.080',
          'wit=transport|spectrum',
        ],
      );

      expect(pack.body, contains('<!-- file-evidence'));
      expect(pack.body, contains('lf=0.320'));
      expect(pack.body, contains('hf=0.080'));
      expect(pack.body, contains('wit=transport|spectrum'));
    });

    test('stays quiet when no file-evidence tags are provided', () {
      final pack = packRelevantChunks(
        filePath: 'lib/sample.dart',
        content: content,
        touchedRanges: const [TouchedLineRange(1, 4)],
        budgetChars: 320,
      );

      expect(pack.body, isNot(contains('<!-- file-evidence')));
    });

    test('whole-file fast path still carries file-evidence annotation', () {
      final pack = packRelevantChunks(
        filePath: 'lib/sample.dart',
        content: 'int alpha() => 1;\n',
        touchedRanges: const [TouchedLineRange(1, 1)],
        budgetChars: 400,
        fileEvidenceTags: const ['lf=0.100', 'wit=transport'],
      );

      expect(pack.body, contains('--- lib/sample.dart (2 lines, full) ---'));
      expect(pack.body, contains('<!-- file-evidence lf=0.100 wit=transport -->'));
    });

    test('typed witnesses survive into file-level chunk headers', () {
      final pack = packRelevantChunks(
        filePath: 'lib/sample.dart',
        content: 'int alpha() => 1;\n',
        touchedRanges: const [TouchedLineRange(1, 1)],
        budgetChars: 400,
        fileEvidenceWitnesses: const [
          LogosEvidenceWitness(
            kind: LogosWitnessKind.transport,
            label: 'generated->source',
            strength: 0.44,
            sourcePath: 'lib/generated/sample.g.dart',
            targetPath: 'lib/sample.dart',
            sourceRole: 'generated',
            targetRole: 'source',
            directional: true,
            note: 'source-of-truth witness',
          ),
        ],
      );

      expect(
        pack.body,
        contains(
          '<!-- file-witnesses generated->source@generated/sample.g.dart:source-of-truth witness -->',
        ),
      );
    });

    test('async pack serializes witness headers without custom isolate types', () async {
      final pack = await packRelevantChunksAsync(
        filePath: 'lib/sample.dart',
        content: ('int alpha() => 1;\n' * 600),
        touchedRanges: const [TouchedLineRange(1, 8)],
        budgetChars: 14000,
        fileEvidenceWitnesses: const [
          LogosEvidenceWitness(
            kind: LogosWitnessKind.transport,
            label: 'generated->source',
            strength: 0.44,
            sourcePath: 'lib/generated/sample.g.dart',
            targetPath: 'lib/sample.dart',
            sourceRole: 'generated',
            targetRole: 'source',
            directional: true,
            note: 'source-of-truth witness',
          ),
        ],
      );

      expect(pack.body, contains('<!-- file-witnesses'));
      expect(pack.body, contains('generated->source@generated/sample.g.dart'));
    });

    test('residual-aware ranking prefers touched chunks while transport admits more context', () {
      final transportPack = packRelevantChunks(
        filePath: 'lib/sample.dart',
        content: content,
        touchedRanges: const [TouchedLineRange(1, 8)],
        budgetChars: 520,
        fileTransportedSupport: 0.9,
      );
      final residualPack = packRelevantChunks(
        filePath: 'lib/sample.dart',
        content: content,
        touchedRanges: const [TouchedLineRange(1, 8)],
        budgetChars: 520,
        fileInnovationResidual: 0.8,
        fileWitnessResidual: 0.6,
      );

      expect(transportPack.body, contains('int beta()'));
      expect(residualPack.body, isNot(contains('int beta()')));
      expect(transportPack.admittedCount, greaterThan(residualPack.admittedCount));
    });
  });
}
