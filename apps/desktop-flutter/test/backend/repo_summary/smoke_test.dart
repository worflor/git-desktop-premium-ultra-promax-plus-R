// Smoke test: generate a real RepoDoc on this repo.
//
// Asserts that the orchestrator produces a non-empty doc without
// throwing, and prints a concise inspection dump so changes to the
// emergent output can be reviewed at a glance.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/repo_summary/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generateRepoSummary on the desktop-flutter repo', () async {
    final doc = await generateRepoSummary('.');
    expect(doc.repoName, isNotEmpty);
    expect(doc.glance.activeFileCount, greaterThan(0));
    expect(doc.regions, isNotEmpty,
        reason: 'a real codebase should spectrally cluster into regions');
    final md = repoDocToMarkdown(doc);
    expect(md, contains('# '));
    expect(md, contains('## At a glance'));

    // Headlines for quick human inspection.
    final lines = <String>[
      '== ACTIVE: ${doc.glance.activeFileCount}/${doc.totalHarvested}',
      '== LINES: ${doc.glance.activeLines}',
      '== ROLES: ${doc.glance.roles.map((e) => "${e.key}:${e.value}").join(", ")}',
      '== SHAPE: ${doc.shape.isEmpty ? "(none)" : doc.shape}',
      '== REGIONS: ${doc.regions.length}',
      for (final r in doc.regions)
        '   -> ${r.name} (${r.fileCount} files)',
      '== CORE: ${doc.backbone.length}',
      for (final b in doc.backbone)
        '   -> ${b.path}  [${b.regionName}] ${b.purpose.isEmpty ? "" : "· ${b.purpose}"}',
    ].join('\n');
    // ignore: avoid_print
    print('\n$lines\n');
    // ignore: avoid_print
    print('======== BEGIN RENDERED MARKDOWN ========\n$md'
        '\n======== END RENDERED MARKDOWN ========');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
