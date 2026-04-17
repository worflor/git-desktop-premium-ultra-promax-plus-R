import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_git.dart';
import 'package:git_desktop/backend/logos_hunks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('packHunksUnderBudget emits parent file witnesses once per file', () {
    final hunk = DiffHunk(
      filePath: 'lib/foo.dart',
      hunkIndex: 0,
      header: '@@ -1,1 +1,2 @@',
      body: '@@ -1,1 +1,2 @@\n-old\n+new\n',
      oldStart: 1,
      newStart: 1,
      additions: 1,
      deletions: 1,
    );
    final packed = packHunksUnderBudget(
      rankings: [
        HunkRanking(
          hunk: hunk,
          phi: 0.9,
          rank: 0,
          fileEvidenceWitnesses: const [
            LogosEvidenceWitness(
              kind: LogosWitnessKind.transport,
              label: 'source->generated',
              strength: 0.8,
              sourcePaths: ['lib/foo.dart'],
              directional: true,
              sourceRole: 'source',
              targetRole: 'generated',
            ),
          ],
          fileWitnesses: const ['generated->source', 'pairwise-loss'],
        ),
      ],
      budgetChars: 1000,
    );

    expect(
      packed.body,
      contains('<!-- file-evidence-witnesses source->generated@lib/foo.dart -->'),
    );
    expect(
      packed.body,
      contains('<!-- file-witnesses generated->source | pairwise-loss -->'),
    );
    expect(packed.body, contains('diff --git a/lib/foo.dart b/lib/foo.dart'));
  });

  test('packHunksUnderBudget chooses file witness header from strongest hunk', () {
    final first = DiffHunk(
      filePath: 'lib/foo.dart',
      hunkIndex: 0,
      header: '@@ -1,1 +1,2 @@',
      body: '@@ -1,1 +1,2 @@\n-old\n+new\n',
      oldStart: 1,
      newStart: 1,
      additions: 1,
      deletions: 1,
    );
    final second = DiffHunk(
      filePath: 'lib/foo.dart',
      hunkIndex: 1,
      header: '@@ -10,1 +10,2 @@',
      body: '@@ -10,1 +10,2 @@\n-old2\n+new2\n',
      oldStart: 10,
      newStart: 10,
      additions: 1,
      deletions: 1,
    );
    final packed = packHunksUnderBudget(
      rankings: [
        HunkRanking(
          hunk: first,
          phi: 0.2,
          rank: 1,
          fileWitnesses: const ['weak-first'],
        ),
        HunkRanking(
          hunk: second,
          phi: 0.9,
          rank: 0,
          fileWitnesses: const ['strong-second'],
        ),
      ],
      budgetChars: 2000,
    );

    expect(packed.body, contains('<!-- file-witnesses strong-second -->'));
    expect(packed.body, isNot(contains('<!-- file-witnesses weak-first -->')));
  });

  test('rankHunksByPhiAsync preserves file witness labels across isolate hop', () async {
    final engine = LogosGit.buildFromStats(
      LogosGitStats(
        touches: const {
          'lib/foo.dart': 12,
          'lib/generated/foo.g.dart': 12,
        },
        totalCommits: 20,
        volatility: const {
          'lib/foo.dart': 2.0,
          'lib/generated/foo.g.dart': 2.0,
        },
        volMean: 2.0,
        volStddev: 0.1,
        coupling: FileCouplingMatrix(
          jaccard: const {
            'lib/foo.dart': {'lib/generated/foo.g.dart': 0.9},
            'lib/generated/foo.g.dart': {'lib/foo.dart': 0.9},
          },
          headHash: 'hunk-async-witnesses',
          commitsAnalyzed: 20,
        ),
        perFileCommitIndices: const {},
      ),
    );
    final rankings = await rankHunksByPhiAsync(
      hunks: [
        DiffHunk(
          filePath: 'lib/foo.dart',
          hunkIndex: 0,
          header: '@@ -1,1 +1,2 @@',
          body: '@@ -1,1 +1,2 @@\n-old\n+new\n',
          oldStart: 1,
          newStart: 1,
          additions: 1,
          deletions: 1,
        ),
        DiffHunk(
          filePath: 'lib/generated/foo.g.dart',
          hunkIndex: 0,
          header: '@@ -1,1 +1,2 @@',
          body: '@@ -1,1 +1,2 @@\n-oldGen\n+newGen\n',
          oldStart: 1,
          newStart: 1,
          additions: 1,
          deletions: 1,
        ),
      ],
      logosEngine: engine,
    );

    expect(rankings.rankings, hasLength(2));
    expect(
      rankings.rankings.expand((r) => r.fileWitnesses).any(
            (w) => w.startsWith('source-generated@'),
          ),
      isTrue,
    );
    expect(
      rankings.rankings.expand((r) => r.fileEvidenceWitnesses).any(
            (w) => w.label == 'source->generated',
          ),
      isTrue,
    );
  });
}
