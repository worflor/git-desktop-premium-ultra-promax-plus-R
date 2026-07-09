// Coverage for lib/features/changes/conflict_resolution.dart — the
// AI-assisted conflict resolution flow and the shared "conflict window"
// dialog. Almost every pure helper in this file (_extractConflictExcerpts,
// _buildMergeResolutionPrompt) is a private implementation detail of
// resolveConflictsWithAi and is only reachable once a real AI model is
// configured — which, past that point, would require a live network call
// to a provider. So this suite exercises the file's REAL observable
// contract instead of a strawman "ours/theirs/union" resolver (this file
// has no such switch — that logic lives in merge_conflict_editor.dart,
// already covered by test/features/merge_conflict_parser_test.dart):
//   - defaultResolveCategory: pure category-selection logic.
//   - resolveConflictsWithAi: the early-return branches reachable without
//     any network call (empty input, unconfigured category).
//   - showConflictWindow / the conflict dialog: the actual ~240 LOC of
//     deterministic widget logic in this file (header pluralization,
//     file listing, AI-availability gating, defer-vs-discard labeling,
//     every button's returned ConflictChoice).
//
// Tests that need a *configured* AI model (to reach the secret-detection /
// file-reading branches of resolveConflictsWithAi) would have to call
// AiSettingsState.setModelSelection, which persists through
// AiSettingsStore to a real dart:io File under StoragePaths.gdpuDataDir()
// — a single fixed, non-per-test-unique location. Per the convention
// already established in test/app/state_model_test.dart, those cases are
// gated behind GDPU_DATA_DIR so a default `flutter test` run can never
// read/write a developer's real settings.json:
//   GDPU_DATA_DIR=/tmp/gdpu-conflict-resolution-test flutter test \
//     test/features/changes/conflict_resolution_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:git_desktop/app/ai_settings_state.dart';
import 'package:git_desktop/features/changes/conflict_resolution.dart';

import '../../support/gen.dart';
import '../../support/prop.dart';
import '../../support/widget_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    installSharedPreferencesMock();
    await loadTestFonts();
  });

  final gdpuOverride = Platform.environment['GDPU_DATA_DIR'];
  final hasGdpuOverride = gdpuOverride != null && gdpuOverride.trim().isNotEmpty;
  const gdpuSkipReason =
      'GDPU_DATA_DIR unset — AiSettingsState.setModelSelection persists '
      'through AiSettingsStore (plain dart:io File under '
      'StoragePaths.gdpuDataDir()), a single fixed location with no '
      'per-test uniquification (same convention as '
      'test/app/state_model_test.dart). Set GDPU_DATA_DIR to a scratch dir '
      'to run this group.';

  group('defaultResolveCategory — pure, no persistence', () {
    test('an untouched AiSettingsState has no model selections at all', () {
      final ai = AiSettingsState();
      addTearDown(ai.dispose);
      expect(ai.modelSelections, isEmpty);
      expect(defaultResolveCategory(ai), '');
    });
  });

  group('defaultResolveCategory — with persisted selections', () {
    test('prefers "fast" whenever it is configured, even alongside others', () async {
      final ai = AiSettingsState();
      addTearDown(ai.dispose);
      await ai.setModelSelection('quality', 'quality-model');
      await ai.setModelSelection('fast', 'fast-model');
      expect(defaultResolveCategory(ai), 'fast');
    }, skip: hasGdpuOverride ? null : gdpuSkipReason);

    test('falls back to the first category carrying a non-empty model', () async {
      final ai = AiSettingsState();
      addTearDown(ai.dispose);
      await ai.setModelSelection('quality', 'quality-model');
      expect(defaultResolveCategory(ai), 'quality');
    }, skip: hasGdpuOverride ? null : gdpuSkipReason);
  });

  group('resolveConflictsWithAi — early-return branches (no disk / network)', () {
    testWidgets('an empty conflictedPaths list is a pure no-op', (tester) async {
      late BuildContext ctx;
      await pumpHarness(
        tester,
        Builder(builder: (context) {
          ctx = context;
          return const Scaffold(body: SizedBox());
        }),
      );
      await resolveConflictsWithAi(ctx, '/does/not/matter', 'fast', const []);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an unconfigured category shows the "No model configured" snackbar',
        (tester) async {
      late BuildContext ctx;
      await pumpHarness(
        tester,
        Builder(builder: (context) {
          ctx = context;
          return const Scaffold(body: SizedBox());
        }),
      );
      await resolveConflictsWithAi(ctx, '/does/not/matter', 'fast', const ['a.dart']);
      await tester.pump(); // let the SnackBar animate in
      expect(find.byType(SnackBar), findsOneWidget);
      // 'fast' resolves via AiSettingsState's built-in default category
      // label map ({'quality': 'Quality', 'fast': 'Fast'}) without needing
      // load() or any persisted state.
      expect(find.textContaining('No model configured for "Fast"'), findsOneWidget);
    });

    testWidgets(
        'property: an unconfigured category never crashes, for hostile category ids',
        (tester) async {
      await forAllAsync<(String categoryId, List<String> paths)>(
        (rng) => (
          genUnicodeHostile(maxLen: 10)(rng),
          genList(genRelPath(), maxLen: 4)(rng),
        ),
        check: (value) async {
          final (categoryId, paths) = value;
          if (paths.isEmpty) return; // conflictedPaths.isEmpty is its own case above
          late BuildContext ctx;
          await pumpHarness(
            tester,
            Builder(builder: (context) {
              ctx = context;
              return const Scaffold(body: SizedBox());
            }),
          );
          await resolveConflictsWithAi(ctx, '/does/not/matter', categoryId, paths);
          await tester.pump();
          expect(find.byType(SnackBar), findsOneWidget,
              reason: 'categoryId=$categoryId paths=$paths');
        },
        count: 6,
        describe: 'resolveConflictsWithAi unconfigured-category snackbar property',
      );
    });
  });

  group('showConflictWindow — dialog contract, no AI model configured', () {
    testWidgets(
        'renders the pluralized header + full file list, and "merge editor" pops manual',
        (tester) async {
      Future<ConflictChoice?>? result;
      await pumpHarness(
        tester,
        Builder(builder: (context) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => result = showConflictWindow(
                context,
                opLabel: 'pull',
                paths: const ['a.dart', 'lib/b.dart'],
                blockCount: 3,
                canDefer: true,
              ),
              child: const Text('open'),
            ),
          );
        }),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('pull · 3 conflicts across 2 files'), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
      expect(find.text('lib/b.dart'), findsOneWidget);
      // No model is configured anywhere in the harness's default
      // AiSettingsState, so the AI resolve button must be absent.
      expect(find.text('no AI model'), findsOneWidget);
      expect(find.text('◇ resolve with AI'), findsNothing);
      expect(find.text('⇋ merge editor'), findsOneWidget);
      expect(find.text('later'), findsOneWidget);

      await tester.tap(find.text('⇋ merge editor'));
      await tester.pumpAndSettle();
      final choice = await result;
      expect(choice, isNotNull);
      expect(choice!.action, ConflictAction.manual);
      expect(choice.aiCategory, isNull);
    });

    testWidgets('singular counts render without a trailing "s"', (tester) async {
      Future<ConflictChoice?>? result;
      await pumpHarness(
        tester,
        Builder(builder: (context) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => result = showConflictWindow(
                context,
                opLabel: 'stash pop',
                paths: const ['x.dart'],
                blockCount: 1,
                canDefer: false,
              ),
              child: const Text('open'),
            ),
          );
        }),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('stash pop · 1 conflict across 1 file'), findsOneWidget);
      // canDefer:false swaps the same action slot's label from "later" to
      // "discard" — but the popped ConflictAction must still be `defer`,
      // never a distinct action, per the "same slot" contract documented
      // in the source.
      expect(find.text('discard'), findsOneWidget);
      expect(find.text('later'), findsNothing);

      await tester.tap(find.text('discard'));
      await tester.pumpAndSettle();
      final choice = await result;
      expect(choice, isNotNull);
      expect(choice!.action, ConflictAction.defer);
    });

    testWidgets(
        'property: header pluralization + full file listing holds for randomized inputs',
        (tester) async {
      await forAllAsync<(List<String> paths, int blockCount, bool canDefer)>(
        (rng) => (
          genList(genRelPath(), maxLen: 5)(rng),
          rng.intBetween(0, 9),
          rng.nextBool(),
        ),
        check: (value) async {
          final (paths, blockCount, canDefer) = value;
          Future<ConflictChoice?>? result;
          await pumpHarness(
            tester,
            Builder(builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => result = showConflictWindow(
                    context,
                    opLabel: 'merge',
                    paths: paths,
                    blockCount: blockCount,
                    canDefer: canDefer,
                  ),
                  child: const Text('open'),
                ),
              );
            }),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          final fileCount = paths.length;
          final header = 'merge · $blockCount '
              'conflict${blockCount == 1 ? '' : 's'} across $fileCount '
              'file${fileCount == 1 ? '' : 's'}';
          expect(find.text(header), findsOneWidget,
              reason: 'paths=$paths blockCount=$blockCount canDefer=$canDefer');
          for (final p in paths.toSet()) {
            expect(find.text(p), findsWidgets, reason: 'missing path "$p" in dialog');
          }

          await tester.tap(find.text(canDefer ? 'later' : 'discard'));
          await tester.pumpAndSettle();
          final choice = await result;
          expect(choice, isNotNull);
          expect(choice!.action, ConflictAction.defer);
        },
        count: 6,
        describe: 'showConflictWindow header + file list property',
      );
    });
  });
}
