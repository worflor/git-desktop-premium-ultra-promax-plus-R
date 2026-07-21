// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Guards the machine-scale diff-load contract that the marble OOM taught us:
// the combined/multi-file path must build a LAZY, bounded-hydration document —
// it must never eagerly materialize one ParsedLine per line (the ~5.7x-input
// object graph that OOMs). Two tiers:
//
//   * fast structural + bounded-hydration laws (always run) — deterministic,
//     no RSS measurement: prove the lazy document exists and stays windowed.
//   * a manual growth-law guard (@Tags(['manual'])) that shells out to
//     tool/diff_load_profiler.dart at two sizes and asserts eager mints ~5.7x
//     the input in objects while lazy mints ~0 — the measured OOM term. Tagged
//     manual because it spawns heavy child processes; run explicitly with
//     `flutter test --tags manual test/features/diff/diff_load_growth_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/predictive_diff_index.dart';

/// A valid multi-file unified diff of [files] files × [linesPerFile] changed
/// line-pairs each (full rewrite). Deterministic; large enough to exceed the
/// lazy + windowing thresholds.
String _combinedDiff(int files, int linesPerFile) {
  final sb = StringBuffer();
  for (var f = 0; f < files; f++) {
    final name = 'graph_$f.gr';
    sb.write('diff --git a/$name b/$name\n');
    sb.write('index 0000000..1111111 100644\n');
    sb.write('--- a/$name\n');
    sb.write('+++ b/$name\n');
    sb.write('@@ -1,$linesPerFile +1,$linesPerFile @@\n');
    for (var i = 0; i < linesPerFile; i++) {
      sb.write('-a ${1000000 + i} ${2000000 + i} ${100 + (i % 900)}\n');
      sb.write('+a ${1000000 + i} ${2000000 + i} ${101 + (i % 900)}\n');
    }
  }
  return sb.toString();
}

void main() {
  group('machine-scale diff load stays lazy + bounded', () {
    test('a large combined multi-file diff builds a LAZY document', () {
      // 4 files × 5k pairs = ~40k rows, ~1MB; force lazy by size regardless.
      final raw = _combinedDiff(4, 5000);
      expect(
        raw.length,
        greaterThan(kLazyDiffLengthThreshold ~/ 8),
        reason: 'sanity: fixture is substantial',
      );

      final doc = DiffDocument.lazy(rawContent: raw);
      // The document rows are the lazy list, never an eager List<ParsedLine>.
      expect(doc.lines, isA<LazyDiffLines>());
      // Per-file structure is preserved (not flattened to one file).
      expect(doc.sections.length, 4);
      expect(doc.filesByPath.length, 4);
      // Every per-file entry is metadata-only and refuses eager materialization.
      for (final e in doc.filesByPath.values) {
        expect(e.isLazyMeta, isTrue);
        expect(e.isLazy, isTrue);
        expect(e.lines, isEmpty);
      }
    });

    test(
      'size-lazy source diff below row budget remains mutable for staging',
      () {
        // Cross the byte threshold without crossing the 200k-row resident
        // budget. Storage choice alone must not remove staging behavior.
      final raw = _combinedDiff(1, 92000);
        expect(raw.length, greaterThan(kLazyDiffLengthThreshold));

        final doc = DiffDocument.fromRawContent(rawContent: raw);
        final lines = doc.lines as LazyDiffLines;
        expect(lines.isFullyResident, isTrue);

        final changed = lines.indexWhere(
          (line) => line.kind == LineKind.deleted,
        );
        expect(changed, greaterThanOrEqualTo(0));
        lines[changed] = lines[changed].copyWith(isStaged: true);
        expect(lines[changed].isStaged, isTrue);
      },
    );

    test('above the windowing threshold, touching rows hydrates only a bounded '
        'window — never the whole file', () {
      // Exceed kLeanDiffLineThreshold (200k) so LazyDiffLines runs WINDOWED,
      // not fully-resident. 1 file × 130k pairs = 260k+ rows.
      final raw = _combinedDiff(1, 130000);
      final doc = DiffDocument.lazy(rawContent: raw);
      final lines = doc.lines as LazyDiffLines;
      expect(
        lines.isFullyResident,
        isFalse,
        reason: 'this many rows must run windowed',
      );
      expect(lines.length, greaterThan(kLeanDiffLineThreshold));

      // Cold: nothing hydrated yet.
      expect(lines.residentRowCount, 0);

      // Touch a scattered handful of rows across the whole file.
      for (final i in [0, 5, 60, 100000, 200000, lines.length - 1]) {
        final row = lines[i];
        expect(row, isA<ParsedLine>());
      }

      // Resident set stays a tiny bounded fraction of the file — the OOM guard.
      // (max 8 windows × 512 rows = 4096; assert generously under total.)
      expect(lines.residentRowCount, lessThanOrEqualTo(8 * 512));
      expect(
        lines.residentRowCount,
        lessThan(lines.length ~/ 10),
        reason: 'must never approach full materialization',
      );
    });

    test('small combined diff is unchanged — eager, fully resident', () {
      final raw = _combinedDiff(2, 20); // tiny
      final doc = DiffDocument.fromRawContent(rawContent: raw);
      // Below the lazy threshold: ordinary eager document, real lines.
      expect(doc.lines, isNot(isA<LazyDiffLines>()));
      expect(doc.lines, isNotEmpty);
    });
  });

  group('growth law (measured)', () {
    // flutter test runs under flutter_tester.exe (not dart), so resolve the
    // Dart SDK that ships in the flutter cache beside it.
    String dartExecutable() {
      final resolved = Platform.resolvedExecutable;
      final sep = Platform.pathSeparator;
      final exe = Platform.isWindows ? 'dart.exe' : 'dart';
      final marker = '${sep}cache$sep';
      final idx = resolved.indexOf(marker);
      if (idx >= 0) {
        final cacheDir = resolved.substring(0, idx + marker.length - 1);
        final c = '$cacheDir${sep}dart-sdk${sep}bin$sep$exe';
        if (File(c).existsSync()) return c;
      }
      final root = Platform.environment['FLUTTER_ROOT'];
      if (root != null) {
        final c = '$root${sep}bin${sep}cache${sep}dart-sdk${sep}bin$sep$exe';
        if (File(c).existsSync()) return c;
      }
      return 'dart';
    }

    test(
      'eager mints ~5.7x the input in objects; lazy mints ~0',
      () async {
        final dart = dartExecutable();
        Future<Map<String, Object?>> profile(String stage, int bytes) async {
          final r = await Process.run(dart, [
            'run',
            'tool/diff_load_profiler.dart',
            '--stage=$stage',
            '--bytes=$bytes',
            '--files=4',
          ], workingDirectory: Directory.current.path);
          expect(r.exitCode, 0, reason: 'profiler failed: ${r.stderr}');
          final line = (r.stdout as String)
              .split('\n')
              .lastWhere((l) => l.trim().startsWith('{'));
          return jsonDecode(line) as Map<String, Object?>;
        }

        const bytes = 32 * 1024 * 1024; // past VM warm-up, safely under budget
        final eager = await profile('eager', bytes);
        final lazy = await profile('lazy', bytes);

        final eagerPerByte = (eager['stageDeltaPerByte']! as num).toDouble();
        final lazyPerByte = (lazy['stageDeltaPerByte']! as num).toDouble();

        // Eager is the OOM term: it mints multiple bytes of objects per input
        // byte. Lazy is bounded: it mints essentially nothing beyond the buffer.
        expect(
          eagerPerByte,
          greaterThan(3.0),
          reason: 'eager should mint >3x input in objects (baseline ~5.7x)',
        );
        expect(
          lazyPerByte,
          lessThan(1.0),
          reason: 'lazy must stay bounded (~0x); regression if it climbs',
        );
        expect(
          eagerPerByte,
          greaterThan(lazyPerByte * 4),
          reason: 'eager must cost multiples of lazy',
        );
      },
      tags: ['manual'],
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
