// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// THE BACKING EQUIVALENCE LAW.
//
// A DiffDocument's observable surface — rows, sections, topology, per-file
// slices, stats, new-file classification — must be a function of the DIFF
// CONTENT alone, never of which backing happens to hold it (in-RAM lazy
// index vs disk spool) nor of which code path produced it (canonical eager
// parser). This is the property that the pile of example-based regression
// pins in diff_document_test each witness one corner of; here it is stated
// once over GENERATED diffs, so shapes nobody thought to pin (odd file-kind
// interleavings, hunkless runs, empty bodies) are covered by construction.
//
// Oracle: parseUnifiedDiff — the canonical eager parser, itself pinned
// against real git by the parser/oracle law suites. Fuzz: seeded, shrinking,
// corpus-backed via forAllAsync.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';

import '../../support/prop.dart';

/// One generated file section: a realistic unified-diff shape drawn from
/// the kinds git actually emits (modified / new / deleted / binary /
/// mode-only), with generated body content.
String _fileSection(Rng rng, int fileIndex) {
  final path = 'dir$fileIndex/file_$fileIndex.txt';
  final kind = rng.intBetween(0, 4);
  final b = StringBuffer();
  switch (kind) {
    case 0: // modified
      b.writeln('diff --git a/$path b/$path');
      b.writeln('index 1111111..2222222 100644');
      b.writeln('--- a/$path');
      b.writeln('+++ b/$path');
      final hunks = rng.intBetween(1, 3);
      var old = 1, neu = 1;
      for (var h = 0; h < hunks; h++) {
        final dels = rng.intBetween(0, 3);
        final adds = rng.intBetween(dels == 0 ? 1 : 0, 3);
        final ctx = rng.intBetween(0, 2);
        b.writeln('@@ -$old,${dels + ctx} +$neu,${adds + ctx} @@');
        for (var i = 0; i < ctx; i++) {
          b.writeln(' ctx f$fileIndex h$h l$i');
        }
        for (var i = 0; i < dels; i++) {
          b.writeln('-old f$fileIndex h$h l$i');
        }
        for (var i = 0; i < adds; i++) {
          b.writeln('+new f$fileIndex h$h l$i');
        }
        old += dels + ctx + 10;
        neu += adds + ctx + 10;
      }
    case 1: // brand-new file
      b.writeln('diff --git a/$path b/$path');
      b.writeln('new file mode 100644');
      b.writeln('index 0000000..2222222');
      b.writeln('--- /dev/null');
      b.writeln('+++ b/$path');
      final adds = rng.intBetween(1, 4);
      b.writeln('@@ -0,0 +1,$adds @@');
      for (var i = 0; i < adds; i++) {
        b.writeln('+fresh f$fileIndex l$i');
      }
    case 2: // deleted file
      b.writeln('diff --git a/$path b/$path');
      b.writeln('deleted file mode 100644');
      b.writeln('index 2222222..0000000');
      b.writeln('--- a/$path');
      b.writeln('+++ /dev/null');
      final dels = rng.intBetween(1, 4);
      b.writeln('@@ -1,$dels +0,0 @@');
      for (var i = 0; i < dels; i++) {
        b.writeln('-gone f$fileIndex l$i');
      }
    case 3: // binary (header-only section — git's canonical form)
      b.writeln('diff --git a/$path b/$path');
      b.writeln('index 1111111..2222222 100644');
      b.writeln('Binary files a/$path and b/$path differ');
    case 4: // mode-only change (hunkless, non-binary)
      b.writeln('diff --git a/$path b/$path');
      b.writeln('old mode 100644');
      b.writeln('new mode 100755');
  }
  return b.toString();
}

/// A combined multi-file diff: 1..5 sections with distinct paths (the app's
/// producers guarantee one section per path — see getSelectionDiff).
String _combinedDiff(Rng rng) {
  final n = rng.intBetween(1, 5);
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    b.write(_fileSection(rng, i));
  }
  return b.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('backing_law'));
  tearDownAll(() => tmp?.delete(recursive: true));

  test(
    'LAW: the document surface is invariant across backings',
    () async {
      var spoolCase = 0;
      await forAllAsync<String>(
        _combinedDiff,
        count: 60 * fuzzScale(),
        seed: 0xD1FF,
        describe: 'combined diff',
        check: (raw) async {
          final canonical = parseUnifiedDiff(raw);
          final inRam = DiffDocument.lazy(rawContent: raw);
          final spoolFile = File(
            '${tmp!.path}${Platform.pathSeparator}case_${spoolCase++}.diff',
          );
          await spoolFile.writeAsString(raw);
          final onDisk = await DiffDocument.lazyFromSpool(spoolFile.path);
          try {
            // 1. ROWS: both lazy backings hydrate byte-identically to the
            // canonical parser's visible rows (parseUnifiedDiff emits exactly
            // the rows the classifiers emit; the parser-laws suites pin that
            // against real git).
            expect(inRam.lines.length, canonical.length, reason: 'in-RAM rows');
            expect(onDisk.lines.length, canonical.length, reason: 'spool rows');
            for (var i = 0; i < canonical.length; i++) {
              expect(inRam.lines[i].text, canonical[i].text, reason: 'row $i');
              expect(inRam.lines[i].kind, canonical[i].kind, reason: 'kind $i');
              expect(
                onDisk.lines[i].text,
                canonical[i].text,
                reason: 'spool row $i',
              );
              expect(
                onDisk.lines[i].kind,
                canonical[i].kind,
                reason: 'spool kind $i',
              );
            }

            // 2. TOPOLOGY: sections, order, and anchors agree between
            // backings (including hunkless binary/mode-only sections).
            expect(
              onDisk.sections.map((s) => (s.path, s.startLine)).toList(),
              inRam.sections.map((s) => (s.path, s.startLine)).toList(),
              reason: 'sections',
            );
            expect(onDisk.orderedPaths, inRam.orderedPaths, reason: 'order');

            // 3. CLASSIFICATION: new-file detection (the blame gate's input)
            // is backing-invariant.
            expect(onDisk.newFilePaths, inRam.newFilePaths, reason: 'newFiles');

            // 4. STATS: adds/dels/hunks agree.
            expect(onDisk.stats.adds, inRam.stats.adds, reason: 'adds');
            expect(onDisk.stats.dels, inRam.stats.dels, reason: 'dels');
            expect(onDisk.stats.hunks, inRam.stats.hunks, reason: 'hunks');

            // 5. SLICES: per-file raw slices are byte-identical across
            // backings AND to the canonical string slicer, for every path.
            final canonicalSlices = sliceDiffByFile(raw);
            for (final path in inRam.orderedPaths) {
              final ram = inRam.rawSliceForPath(path);
              final disk = onDisk.rawSliceForPath(path);
              expect(disk, ram, reason: 'slice($path) across backings');
              final oracle = canonicalSlices[path];
              if (oracle != null && ram != null) {
                expect(
                  ram.trimRight(),
                  oracle.trimRight(),
                  reason: 'slice($path) vs canonical slicer',
                );
              }
            }
          } finally {
            onDisk.dispose();
            try {
              spoolFile.deleteSync();
            } catch (_) {}
          }
        },
      );
    },
    timeout: fuzzTimeout(),
  );
}
