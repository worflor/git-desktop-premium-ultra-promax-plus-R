// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// anchor_survival_survey_test.dart — how long does a review comment
// keep pointing at the right line?
//
// NOT a pass/fail test. A MEASUREMENT, opt-in behind MANIFOLD_ANCHOR_SURVEY=1,
// against this repository's real history rather than a synthetic fixture.
// It exists because a UI decision depends on the number: the margin-native
// redesign puts every thread inline at its anchored line, and threads that
// no longer resolve have to go on an "unanchored shelf" instead. If the
// off-anchor rate is high, that shelf becomes the de facto review pane and
// the whole thesis collapses — so measure before building.
//
// The population is chosen to match where comments actually land. A reviewer
// comments on lines the author just CHANGED, not on random lines of the file,
// and changed lines are exactly the ones most likely to churn again. Sampling
// whole files would flatter the resolver by loading it with untouched context.
//
// Horizons are measured in commits-to-the-file, not wall clock: "my comment
// survived 5 more edits to this file" is the question a reviewer has.

@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart' as git;
import 'package:git_desktop/backend/review_anchor.dart';
import 'package:git_desktop/features/review/review_pane_controller.dart'
    show splitBlobLines;
import 'package:path/path.dart' as p;

/// Repo root: the test runs from apps/desktop-flutter.
String get _repoRoot => p.normalize(p.join(Directory.current.path, '..', '..'));

/// How many file-touching commits back to sample from.
const int _kCommitsToScan = 400;

/// Cap on sampled (commit, file) pairs, so the survey stays an afternoon
/// rather than an evening.
const int _kMaxSamples = 220;

/// Horizons, in later commits TO THAT FILE.
const List<int> _kHorizons = [1, 3, 10, 40];

/// Only source-ish files: a survey over lockfiles and generated i18n
/// would measure churn we would never review.
bool _reviewable(String path) {
  if (!path.endsWith('.dart')) return false;
  if (path.contains('/i18n/gen/')) return false;
  if (path.endsWith('.g.dart')) return false;
  return true;
}

Future<List<String>> _lines(String spec) async {
  final bytes = await git.gitBlobBytes(_repoRoot, spec);
  if (bytes == null) return const [];
  return splitBlobLines(utf8.decode(bytes, allowMalformed: true));
}

Future<String> _git(List<String> args) async {
  final r = await git.runGit(_repoRoot, args);
  return r.exitCode == 0 ? (r.stdout as String) : '';
}

/// New-side line numbers a commit touched in one file, from -U0 hunks.
List<int> _changedNewLines(String patch) {
  final out = <int>[];
  final re = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@');
  for (final line in const LineSplitter().convert(patch)) {
    final m = re.firstMatch(line);
    if (m == null) continue;
    final start = int.parse(m.group(1)!);
    final count = int.tryParse(m.group(2) ?? '1') ?? 1;
    for (var i = 0; i < count; i++) {
      out.add(start + i);
    }
  }
  return out;
}

void main() {
  final enabled = Platform.environment['MANIFOLD_ANCHOR_SURVEY'] == '1';

  test('anchor survival across real history', () async {
    if (!enabled) {
      markTestSkipped('set MANIFOLD_ANCHOR_SURVEY=1 to run the survey');
      return;
    }

    // Commits that touched reviewable files, newest first.
    final log = await _git(['log', '--format=%H', '-n', '$_kCommitsToScan']);
    final commits = const LineSplitter()
        .convert(log)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(commits, isNotEmpty, reason: 'no history to survey');

    // Per file, the commits that touched it, newest first. The horizon
    // walk needs this ordering to answer "N more edits to THIS file".
    final touchedBy = <String, List<String>>{};
    for (final c in commits) {
      final names = await _git(
          ['show', '--pretty=format:', '--name-only', '--no-renames', c]);
      for (final f in const LineSplitter().convert(names)) {
        final path = f.trim();
        if (path.isEmpty || !_reviewable(path)) continue;
        (touchedBy[path] ??= <String>[]).add(c);
      }
    }

    // Sample the files with the richest history: those are the ones a
    // long-lived review would actually sit across.
    final files = touchedBy.entries
        .where((e) => e.value.length > _kHorizons.first)
        .toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    var samples = 0;
    final total = <int, int>{for (final h in _kHorizons) h: 0};
    final anchored = <int, int>{for (final h in _kHorizons) h: 0};
    final reanchored = <int, int>{for (final h in _kHorizons) h: 0};
    final outdated = <int, int>{for (final h in _kHorizons) h: 0};
    var fileGone = 0;
    // "Moved" counts as survival, but the resolver takes the content
    // match NEAREST the recorded position — so a line with duplicate
    // content in the file (a bare `});`, a repeated guard) can
    // re-anchor onto the wrong occurrence and report success. Counting
    // how often the match was ambiguous is what keeps the headline
    // honest: an ambiguous re-anchor is a candidate silent mis-anchor.
    final ambiguous = <int, int>{for (final h in _kHorizons) h: 0};

    outer:
    for (final entry in files) {
      final path = entry.key;
      final history = entry.value; // newest first
      // Walk from the OLDEST end so there are later commits to resolve
      // against, and stride so one hot file cannot dominate the sample.
      for (var i = history.length - 1; i >= 1; i -= 3) {
        if (samples >= _kMaxSamples) break outer;
        final at = history[i];
        final patch = await _git(
            ['diff', '-U0', '$at~1', at, '--', path]);
        if (patch.isEmpty) continue;
        final changed = _changedNewLines(patch);
        if (changed.isEmpty) continue;

        final base = await _lines('$at:$path');
        if (base.isEmpty) continue;

        // One anchor per sampled commit-file: the FIRST changed line
        // that exists in the blob. One comment per changed hunk is the
        // realistic density, and it keeps the survey unweighted by how
        // large a commit happened to be.
        final lineNo = changed.firstWhere(
            (n) => n >= 1 && n <= base.length,
            orElse: () => -1);
        if (lineNo < 0) continue;
        // A blank or trivially-short line is not something anyone
        // comments on, and it would resolve by colliding with every
        // other blank line in the file.
        if (base[lineNo - 1].trim().length < 8) continue;

        final anchor = captureAnchor(
          lines: base,
          lineIndex: lineNo - 1,
          round: 1,
          commit: at,
          path: path,
        );
        samples++;

        for (final h in _kHorizons) {
          final j = i - h; // h later commits to this file
          if (j < 0) continue;
          final later = history[j];
          final now = await _lines('$later:$path');
          total[h] = total[h]! + 1;
          if (now.isEmpty) {
            fileGone++;
            outdated[h] = outdated[h]! + 1;
            continue;
          }
          final res = resolveAnchor(anchor, now);
          if (res.status == AnchorStatus.reanchored) {
            var candidates = 0;
            for (final l in now) {
              if (hex64(lineContentHash(l)) == anchor.lineHash) candidates++;
            }
            if (candidates > 1) ambiguous[h] = ambiguous[h]! + 1;
          }
          switch (res.status) {
            case AnchorStatus.anchored:
              anchored[h] = anchored[h]! + 1;
            case AnchorStatus.reanchored:
              reanchored[h] = reanchored[h]! + 1;
            case AnchorStatus.outdated:
              outdated[h] = outdated[h]! + 1;
          }
        }
      }
    }

    final buf = StringBuffer()
      ..writeln('')
      ..writeln('ANCHOR SURVIVAL — ${files.length} files, $samples anchors')
      ..writeln('(anchor on a line the commit changed; resolved N later '
          'commits to that same file)')
      ..writeln('')
      ..writeln('  horizon    n   exact  moved   lost   survives  ambig');
    for (final h in _kHorizons) {
      final n = total[h]!;
      if (n == 0) continue;
      String pct(int v) => (100 * v / n).toStringAsFixed(1).padLeft(5);
      final survives = anchored[h]! + reanchored[h]!;
      buf.writeln('  +${h.toString().padRight(3)} ${n.toString().padLeft(6)}'
          '  ${pct(anchored[h]!)}% ${pct(reanchored[h]!)}%'
          ' ${pct(outdated[h]!)}%   ${pct(survives)}% ${pct(ambiguous[h]!)}%');
    }
    buf.writeln('');
    buf.writeln('  file deleted at horizon: $fileGone');
    buf.writeln('');
    buf.writeln('READ THIS AS: "survives" is the share of comments that would '
        'still sit on their line. The rest land on the unanchored shelf.');
    buf.writeln('"ambig" is the share whose content matched MORE THAN ONE '
        'line, so the nearest-wins rule could have picked wrong. Treat it '
        'as the upper bound on silent mis-anchoring, not as its rate.');
    // ignore: avoid_print
    print(buf.toString());

    expect(samples, greaterThan(0), reason: 'survey collected nothing');
  });
}
