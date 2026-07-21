// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Behavior coverage for the command palette's headless core:
//
//   * PaletteScorer.scoreAll — the pure ranking function PaletteState._reScore
//     delegates to. Tested directly (no providers) for text-match ordering and
//     for the usage/prefix boosts that make a previously-run command rank
//     higher on the next matching query (recordUsage's SCORING effect).
//   * PaletteState.setQuery / moveSelection / hoverSelect / recordUsage — the
//     "type a query, arrow through results, hit enter" interaction loop. These
//     need a live provider tree (open() reads five app-state providers plus the
//     WorktreeState/DeskPrState that buildStaticEntries pulls), so they run
//     through the widget harness exactly like palette_registry_test.dart — but
//     every assertion is on PaletteState's public getters (results,
//     selectedIndex, selected), never on rendered widgets.
//
// Not covered here: PaletteState._dedup only collapses entries that share a
// (category, refPath) key — a shape only file/commit entries carry, which in
// turn requires a real LogosGit engine or a live async git/commit search. That
// is the same integration-level fixture (ScratchRepo + a built engine) the
// filament-scan and jank tests both defer, so dedup belongs with them, not in
// this headless suite. On-disk usage persistence crash-safety is covered by the
// parsePaletteUsage franken-load tests; here we cover only usage's in-memory
// ranking effect.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:git_desktop/app/app_identity.dart';
import 'package:git_desktop/app/desk_pr_state.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/app/worktree_state.dart';
import 'package:git_desktop/features/palette/palette_entry.dart';
import 'package:git_desktop/features/palette/palette_registry.dart';
import 'package:git_desktop/features/palette/palette_scorer.dart';
import 'package:git_desktop/features/palette/palette_state.dart';
import 'package:git_desktop/backend/storage_paths.dart';

import '../../support/widget_harness.dart';

PaletteEntry _entry(String id, String label,
        {PaletteCategory category = PaletteCategory.command}) =>
    PaletteEntry(
      id: id,
      label: label,
      category: category,
      actionType: PaletteActionType.execute,
    );

PaletteCallbacks _noopCallbacks() => (
      onModeChanged: (int mode) {},
      onOpenXray: () {},
      onOpenSettings: () {},
      onRefresh: () {},
      onUndo: () {},
      onRepoSwitch: (String path) {},
      onDeskSwitch: (String path) {},
      onOpenBrowser: (String url) {},
    );

/// buildStaticEntries (invoked inside PaletteState.open) reads WorktreeState and
/// DeskPrState — both excluded from the harness base providers because their
/// constructors need a RepositoryState. Wire them above the Navigator, matching
/// palette_registry_test.dart.
Widget _wireWorktreeAndDeskPr(BuildContext context, Widget app) => MultiProvider(
      providers: [
        ChangeNotifierProvider<WorktreeState>(
          create: (c) => WorktreeState(c.read<RepositoryState>()),
        ),
        ChangeNotifierProvider<DeskPrState>(
          create: (c) =>
              DeskPrState(c.read<RepositoryState>(), c.read<AppIdentityState>()),
        ),
      ],
      child: app,
    );

/// Mounts the harness, opens a fresh PaletteState against a no-active-repo
/// context (so open() builds only the repo-independent static entries and
/// schedules no git subprocess / debounce timer), and returns the state.
Future<PaletteState> _openPalette(WidgetTester tester) async {
  late BuildContext ctx;
  await pumpHarness(
    tester,
    Builder(builder: (context) {
      ctx = context;
      return const Scaffold(body: SizedBox());
    }),
    wrapAboveNavigator: _wireWorktreeAndDeskPr,
  );
  final palette = ctx.read<PaletteState>();
  palette.open(ctx, _noopCallbacks());
  await tester.pump();
  // recordUsage schedules a debounced-persist Timer; dispose cancels it (and
  // the query/hover debounces) so it isn't left pending at teardown. dispose
  // is idempotent, so this is safe even though the provider also owns it.
  addTearDown(palette.dispose);
  return palette;
}

double _scoreOf(PaletteState palette, String id) =>
    palette.results.firstWhere((e) => e.id == id).score;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });
  setUp(installHermeticStorageSeams);

  group('PaletteScorer.scoreAll — ranking (pure, headless)', () {
    test('a tight prefix match outranks a gapped subsequence match, and a '
        'non-match scores zero', () {
      final settings = _entry('a', 'Settings');
      final reset = _entry('b', 'Reset');
      final branches = _entry('c', 'Branches');
      final scorer = PaletteScorer();

      scorer.scoreAll(
        [settings, reset, branches],
        'set',
        const PaletteContext(),
      );

      // 'Settings' leads with the query at a word boundary and consecutive
      // characters; 'Reset' still matches 's','e','t' as a subsequence but
      // with a weaker (non-boundary, less-consecutive) score.
      expect(settings.score, greaterThan(reset.score));
      expect(reset.score, greaterThan(0));
      // 'Branches' has no 's-e-t' subsequence -> not a candidate at all.
      expect(branches.score, 0);
    });

    test('a used command scores higher than an unused one on the same query',
        () {
      // Two independent copies of the same entry so scoreAll's per-entry
      // mutation of `score` doesn't cross-contaminate.
      final cold = _entry('cmd.fetch', 'Fetch');
      final warm = _entry('cmd.fetch', 'Fetch');
      final scorer = PaletteScorer();

      scorer.scoreAll([cold], 'fetch', const PaletteContext());
      scorer.scoreAll(
        [warm],
        'fetch',
        const PaletteContext(usageFrequency: {'cmd.fetch': 5}),
      );

      expect(warm.score, greaterThan(cold.score),
          reason: 'usage frequency must lift the context prior, and the text '
              'match is identical, so the used entry must rank strictly higher');
    });

    test('query-prefix frequency lifts an entry for THAT query specifically',
        () {
      final plain = _entry('cmd.fetch', 'Fetch');
      final learned = _entry('cmd.fetch', 'Fetch');
      final scorer = PaletteScorer();

      scorer.scoreAll([plain], 'fetch', const PaletteContext());
      scorer.scoreAll(
        [learned],
        'fetch',
        // The bucket recordUsage writes when a command is run under a 2+ char
        // query: queryFrequency[queryPrefix][id].
        const PaletteContext(queryFrequency: {
          'fe': {'cmd.fetch': 4}
        }),
      );

      expect(learned.score, greaterThan(plain.score),
          reason: 'a hit in the per-query-prefix bucket must lift the score for '
              'that query, just as the generic frequency bucket does');
    });
  });

  group('PaletteState.moveSelection — empty results (pure)', () {
    test('is a no-op and never throws when there are no results', () {
      final palette = PaletteState();
      addTearDown(palette.dispose);

      expect(palette.results, isEmpty);
      expect(palette.selectedIndex, 0);
      expect(palette.selected, isNull);

      // Neither direction moves off 0, and nothing throws on the empty list.
      palette.moveSelection(1);
      palette.moveSelection(-1);
      expect(palette.selectedIndex, 0);
    });
  });

  group('PaletteState — query + selection flow (mounted)', () {
    testWidgets('open() surfaces the repo-independent static entries, '
        'selected tracks index 0', (tester) async {
      final palette = await _openPalette(tester);

      expect(palette.results, isNotEmpty);
      expect(palette.selectedIndex, 0);
      expect(palette.selected, same(palette.results.first));
      // A known always-present static entry.
      expect(palette.results.any((e) => e.id == 'nav.settings'), isTrue);
    });

    testWidgets('setQuery narrows to matches; a gibberish query empties the list',
        (tester) async {
      final palette = await _openPalette(tester);
      final total = palette.results.length;

      palette.setQuery('settings');
      await tester.pump();
      expect(palette.results.length, lessThan(total),
          reason: 'a specific query must filter the full static set');
      expect(palette.results.any((e) => e.id == 'nav.settings'), isTrue);

      palette.setQuery('zzqxqzzz');
      await tester.pump();
      expect(palette.results, isEmpty,
          reason: 'a query matching nothing must drop every entry (score<=0 is '
              'pruned in _reScore)');
      // Selection stays valid on an empty list.
      expect(palette.selectedIndex, 0);
      expect(palette.selected, isNull);
    });

    testWidgets('moveSelection clamps at both ends (no wrap, no overflow)',
        (tester) async {
      final palette = await _openPalette(tester);
      final last = palette.results.length - 1;
      expect(last, greaterThan(1), reason: 'need a few entries to move through');

      palette.moveSelection(1);
      expect(palette.selectedIndex, 1);

      // Overshoot the bottom -> pinned to the last index, not wrapped to 0.
      palette.moveSelection(1000);
      expect(palette.selectedIndex, last);

      // Overshoot the top -> pinned to 0, not wrapped to the end.
      palette.moveSelection(-1000);
      expect(palette.selectedIndex, 0);
    });

    testWidgets('hoverSelect moves selection to the hovered index after its '
        'debounce; same-index and out-of-range hovers are no-ops',
        (tester) async {
      final palette = await _openPalette(tester);
      expect(palette.results.length, greaterThan(3));

      palette.hoverSelect(3);
      // hoverSelect debounces ~35ms; before it fires, selection is unchanged.
      expect(palette.selectedIndex, 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(palette.selectedIndex, 3);

      // Hovering the already-selected index does nothing (and schedules no
      // timer that could fire later).
      palette.hoverSelect(3);
      await tester.pump(const Duration(milliseconds: 50));
      expect(palette.selectedIndex, 3);

      // Out-of-range hover is ignored outright.
      palette.hoverSelect(9999);
      await tester.pump(const Duration(milliseconds: 50));
      expect(palette.selectedIndex, 3);
    });

    testWidgets('recordUsage lifts the used entry on the next matching query',
        (tester) async {
      final palette = await _openPalette(tester);

      palette.setQuery('history');
      await tester.pump();
      final before = _scoreOf(palette, 'nav.history');

      // Simulate running History a few times FROM this query (records both the
      // generic frequency map and the query-prefix bucket, plus recency).
      for (var i = 0; i < 3; i++) {
        palette.recordUsage('nav.history');
      }

      // Re-score the same query — the in-memory usage maps feed straight back
      // into the context the scorer reads.
      palette.setQuery('history');
      await tester.pump();
      final after = _scoreOf(palette, 'nav.history');

      expect(after, greaterThan(before),
          reason: 'a command that was just run must rank strictly higher the '
              'next time the same query is typed');
    });
  });

  group('PaletteState usage persistence (atomic + coalesced)', () {
    testWidgets('recorded usage persists atomically and round-trips',
        (tester) async {
      final palette = await _openPalette(tester);
      for (var i = 0; i < 3; i++) {
        palette.recordUsage('nav.history');
      }
      // The flush + verification touch the real filesystem, so they must run
      // in runAsync (real async zone) rather than the fake-async test zone.
      // debugFlushUsage drains the debounced write deterministically (no 1s
      // wait); the three executions coalesce to one atomic write of the latest
      // state.
      await tester.runAsync(() async {
        await palette.debugFlushUsage();

        // The write went through writeFileAtomic: the file is present,
        // complete, valid JSON, and carries the recorded usage — and no temp
        // file leaked (atomicity: the temp was renamed onto the target).
        final dir = await StoragePaths.gdpuDataDir();
        final file =
            File('${dir.path}${Platform.pathSeparator}palette_usage.json');
        expect(file.existsSync(), isTrue, reason: 'usage file must be written');
        final decoded =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(decoded['lastExecutedId'], 'nav.history');
        final repos = decoded['repos'] as Map<String, dynamic>;
        final freq =
            (repos.values.first as Map)['frequency'] as Map<String, dynamic>;
        expect(freq['nav.history'], 3,
            reason: 'three executions must persist as frequency 3 (coalesced '
                'into one atomic write of the latest state)');
        final tmps =
            dir.listSync().where((e) => e.path.endsWith('.tmp')).toList();
        expect(tmps, isEmpty,
            reason: 'atomic write must leave no temp file behind');
      });
    });
  });
}
