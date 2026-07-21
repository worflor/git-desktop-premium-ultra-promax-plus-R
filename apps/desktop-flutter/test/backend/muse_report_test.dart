// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// The muse panel and the clipboard export are two renderings of the
// same output. composeMuseSections is the single source of truth they
// both walk; these tests pin its inclusion/ordering rules and verify
// the pure text serializer (renderMuseReport) tracks it — so the two
// surfaces can't silently drift the way they did before the refactor.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/muse_report.dart';

AiMuseProposal _prop(
  MuseStrandKind strand,
  String title, {
  String vision = 'a vision',
  String foothold = 'a foothold',
  List<String> citations = const [],
}) =>
    AiMuseProposal(
      strand: strand,
      title: title,
      vision: vision,
      foothold: foothold,
      citations: citations,
    );

AiMuseData _data({
  List<AiMuseProposal> proposals = const [],
  List<AiMuseIdea> brainstormIdeas = const [],
  List<String> parseWarnings = const [],
  String providerId = 'anthropic',
  String modelId = 'claude',
  String brainstormProviderId = '',
  String brainstormModelId = '',
}) =>
    AiMuseData(
      providerId: providerId,
      modelId: modelId,
      brainstormProviderId: brainstormProviderId,
      brainstormModelId: brainstormModelId,
      scopeLabel: 'all changes',
      proposals: proposals,
      brainstormIdeas: brainstormIdeas,
      parseWarnings: parseWarnings,
      promptCharacters: 0,
      diffCharacters: 0,
    );

void main() {
  group('composeMuseSections', () {
    test('proposal sections follow the given order, skipping empties', () {
      final data = _data(proposals: [
        _prop(MuseStrandKind.fever, 'F1'),
        _prop(MuseStrandKind.spark, 'S1'),
        _prop(MuseStrandKind.spark, 'S2'),
      ]);
      // Order lists ghost (no proposals) before spark before fever.
      final sections = composeMuseSections(
        data,
        const [
          MuseStrandKind.ghost,
          MuseStrandKind.spark,
          MuseStrandKind.fever,
        ],
      );
      // ghost is skipped (no proposals); spark then fever survive.
      expect(sections, hasLength(2));
      expect(sections[0], isA<MuseProposalsSection>());
      final first = sections[0] as MuseProposalsSection;
      expect(first.strand, MuseStrandKind.spark);
      // Emission order preserved within a strand.
      expect(first.proposals.map((p) => p.title), ['S1', 'S2']);
      final second = sections[1] as MuseProposalsSection;
      expect(second.strand, MuseStrandKind.fever);
    });

    test('reordering the order argument reorders the sections', () {
      final data = _data(proposals: [
        _prop(MuseStrandKind.spark, 'S'),
        _prop(MuseStrandKind.fever, 'F'),
      ]);
      final feverFirst = composeMuseSections(
        data,
        const [MuseStrandKind.fever, MuseStrandKind.spark],
      ).cast<MuseProposalsSection>().map((s) => s.strand).toList();
      expect(feverFirst, [MuseStrandKind.fever, MuseStrandKind.spark]);
    });

    test('brainstorm and notes append after proposals, only when present',
        () {
      final data = _data(
        proposals: [_prop(MuseStrandKind.spark, 'S')],
        brainstormIdeas: const [AiMuseIdea(index: 0, text: 'seed')],
        parseWarnings: const ['a warning'],
      );
      final sections = composeMuseSections(data, kMuseStrandDisplayOrder);
      expect(sections, hasLength(3));
      expect(sections[0], isA<MuseProposalsSection>());
      expect(sections[1], isA<MuseBrainstormSection>());
      expect(sections[2], isA<MuseNotesSection>());
    });

    test('no brainstorm section when ideas empty; no notes when clean', () {
      final data = _data(proposals: [_prop(MuseStrandKind.spark, 'S')]);
      final sections = composeMuseSections(data, kMuseStrandDisplayOrder);
      expect(sections.whereType<MuseBrainstormSection>(), isEmpty);
      expect(sections.whereType<MuseNotesSection>(), isEmpty);
    });

    test('empty data yields no sections', () {
      expect(composeMuseSections(_data(), kMuseStrandDisplayOrder), isEmpty);
    });

    group('with selection', () {
      test('keeps only selected proposals, drops emptied strands', () {
        final s1 = _prop(MuseStrandKind.spark, 'S1');
        final s2 = _prop(MuseStrandKind.spark, 'S2');
        final f1 = _prop(MuseStrandKind.fever, 'F1');
        final data = _data(proposals: [s1, s2, f1]);
        final sections = composeMuseSections(
          data,
          const [MuseStrandKind.spark, MuseStrandKind.fever],
          selection: {s2}, // only one spark proposal selected
        );
        // fever drops entirely; spark keeps just the selected one.
        expect(sections, hasLength(1));
        final only = sections.single as MuseProposalsSection;
        expect(only.strand, MuseStrandKind.spark);
        expect(only.proposals.map((p) => p.title), ['S2']);
      });

      test('omits brainstorm and notes even when present', () {
        final s = _prop(MuseStrandKind.spark, 'S');
        final data = _data(
          proposals: [s],
          brainstormIdeas: const [AiMuseIdea(index: 0, text: 'seed')],
          parseWarnings: const ['warn'],
        );
        final sections = composeMuseSections(
          data,
          kMuseStrandDisplayOrder,
          selection: {s},
        );
        expect(sections.whereType<MuseBrainstormSection>(), isEmpty);
        expect(sections.whereType<MuseNotesSection>(), isEmpty);
      });
    });
  });

  group('renderMuseReport', () {
    test('full report carries header, strands, brainstorm, and notes', () {
      final data = _data(
        proposals: [
          _prop(MuseStrandKind.spark, 'Spark idea',
              vision: 'It glimmers', foothold: 'near lib/x.dart',
              citations: ['lib/x.dart', 'lib/y.dart']),
          _prop(MuseStrandKind.fever, 'Wild idea',
              vision: 'It burns', foothold: 'attic'),
        ],
        brainstormIdeas: const [AiMuseIdea(index: 0, text: 'a raw seed')],
        parseWarnings: const ['invented strand dropped'],
      );
      final text = renderMuseReport(
        data,
        const [MuseStrandKind.spark, MuseStrandKind.fever],
      );
      expect(text, '''
Muse · all changes
Model: anthropic / claude

SPARK
- Spark idea
    It glimmers
    foothold: near lib/x.dart
    cite: lib/x.dart, lib/y.dart

FEVER
- Wild idea
    It burns
    foothold: attic

BRAINSTORM SPEW
- a raw seed

NOTES
- invented strand dropped''');
    });

    test('cite line only appears when a proposal has citations', () {
      final text = renderMuseReport(
        _data(proposals: [_prop(MuseStrandKind.spark, 'No cites')]),
        const [MuseStrandKind.spark],
      );
      expect(text.contains('cite:'), isFalse);
    });

    test('selection export omits brainstorm and notes', () {
      final keep = _prop(MuseStrandKind.spark, 'Keep');
      final drop = _prop(MuseStrandKind.fever, 'Drop');
      final data = _data(
        proposals: [keep, drop],
        brainstormIdeas: const [AiMuseIdea(index: 0, text: 'seed')],
        parseWarnings: const ['warn'],
      );
      final text = renderMuseReport(
        data,
        const [MuseStrandKind.spark, MuseStrandKind.fever],
        selection: {keep},
      );
      expect(text.contains('Keep'), isTrue);
      expect(text.contains('Drop'), isFalse);
      expect(text.contains('BRAINSTORM SPEW'), isFalse);
      expect(text.contains('NOTES'), isFalse);
    });

    test('names both models when brainstorm and synthesis differ', () {
      final text = renderMuseReport(
        _data(
          proposals: [_prop(MuseStrandKind.spark, 'S')],
          brainstormProviderId: 'claude',
          brainstormModelId: 'claude-haiku-4-5',
          providerId: 'claude',
          modelId: 'claude-opus-4-8',
        ),
        const [MuseStrandKind.spark],
      );
      expect(text, contains('Brainstorm: claude / claude-haiku-4-5'));
      expect(text, contains('Synthesis: claude / claude-opus-4-8'));
      expect(text.contains('Model:'), isFalse);
    });

    test('collapses to one Model line when both phases share a model', () {
      final text = renderMuseReport(
        _data(
          proposals: [_prop(MuseStrandKind.spark, 'S')],
          brainstormProviderId: 'claude',
          brainstormModelId: 'claude-opus-4-8',
          providerId: 'claude',
          modelId: 'claude-opus-4-8',
        ),
        const [MuseStrandKind.spark],
      );
      expect(text, contains('Model: claude / claude-opus-4-8'));
      expect(text.contains('Brainstorm:'), isFalse);
      expect(text.contains('Synthesis:'), isFalse);
    });

    test('collapses to one Model line when brainstorm identity is absent', () {
      final text = renderMuseReport(
        _data(proposals: [_prop(MuseStrandKind.spark, 'S')]),
        const [MuseStrandKind.spark],
      );
      expect(text, contains('Model: anthropic / claude'));
      expect(text.contains('Brainstorm:'), isFalse);
    });

    test('output is trimmed — no trailing blank line', () {
      final text = renderMuseReport(
        _data(proposals: [_prop(MuseStrandKind.spark, 'S')]),
        const [MuseStrandKind.spark],
      );
      expect(text, isNot(endsWith('\n')));
    });

    test('synth line drops the dangling slash when a half is blank', () {
      // The switch to modelDescriptor() only changes behavior when one half
      // is missing: the old inline `provider / model` rendered `Model:  / X`.
      final text = renderMuseReport(
        _data(
          proposals: [_prop(MuseStrandKind.spark, 'S')],
          providerId: '',
          modelId: 'claude-opus-4-8',
        ),
        const [MuseStrandKind.spark],
      );
      expect(text, contains('Model: claude-opus-4-8'));
      expect(text.contains(' / '), isFalse);
    });
  });
}
