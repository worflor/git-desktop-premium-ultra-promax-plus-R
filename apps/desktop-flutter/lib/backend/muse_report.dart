import 'dtos.dart';
import 'report_attribution.dart';

/// One renderable block of muse output.
///
/// The muse panel and the clipboard export are two views of the *same*
/// output. This sealed hierarchy is the single definition of what that
/// output contains, and [composeMuseSections] is the only place its
/// shape is decided. Every renderer switches over these variants
/// exhaustively — so adding a section kind is a compile error in each
/// renderer until it's handled, rather than a block that shows on
/// screen but silently goes missing from a copy.
sealed class MuseSection {
  const MuseSection();
}

/// One strand's proposals, grouped under that strand. Emitted in strand
/// order, once per strand that produced at least one proposal.
final class MuseProposalsSection extends MuseSection {
  final MuseStrandKind strand;
  final List<AiMuseProposal> proposals;
  const MuseProposalsSection({required this.strand, required this.proposals});
}

/// The raw phase-1 brainstorm spew, shown beneath the proposals.
final class MuseBrainstormSection extends MuseSection {
  final List<AiMuseIdea> ideas;
  const MuseBrainstormSection(this.ideas);
}

/// Parse warnings raised during synthesis — malformed tags, invented
/// strands, missing footholds. A muted footnote, not an error wall.
final class MuseNotesSection extends MuseSection {
  final List<String> warnings;
  const MuseNotesSection(this.warnings);
}

/// Decide the muse output's section structure: the single source of
/// truth shared by the on-screen panel, the header jump-strip, and the
/// clipboard export.
///
/// Proposal sections come first, one per strand in [order], skipping
/// strands with no proposals. The full report then appends the
/// brainstorm spew and parse notes when present.
///
/// When [selection] is non-null the result is a focused export of just
/// those proposals: each strand keeps only its selected proposals (in
/// emission order), empty strands drop out, and the brainstorm/notes
/// context is omitted — a copy of the chosen cards, nothing else.
List<MuseSection> composeMuseSections(
  AiMuseData data,
  List<MuseStrandKind> order, {
  Set<AiMuseProposal>? selection,
}) {
  final sections = <MuseSection>[];
  for (final strand in order) {
    var proposals = data.proposalsForStrand(strand);
    if (selection != null) {
      proposals = proposals.where(selection.contains).toList(growable: false);
    }
    if (proposals.isNotEmpty) {
      sections.add(MuseProposalsSection(strand: strand, proposals: proposals));
    }
  }
  if (selection == null) {
    if (data.brainstormIdeas.isNotEmpty) {
      sections.add(MuseBrainstormSection(data.brainstormIdeas));
    }
    if (data.parseWarnings.isNotEmpty) {
      sections.add(MuseNotesSection(data.parseWarnings));
    }
  }
  return sections;
}

/// Render the muse output as plain text for the clipboard. Pure — no
/// Clipboard, no BuildContext — so it's unit-testable and stays in
/// lockstep with the panel by walking the same [composeMuseSections].
String renderMuseReport(
  AiMuseData data,
  List<MuseStrandKind> order, {
  Set<AiMuseProposal>? selection,
}) {
  final buf = StringBuffer();
  buf.writeln('Muse · ${data.scopeLabel}');
  // Two-model pipeline: name the brainstorm and synthesis models
  // separately. Collapse to one line when both phases ran the same
  // model (or when brainstorm identity wasn't recorded).
  final synth = modelDescriptor(data.providerId, data.modelId);
  final brain = data.brainstormModelId.isEmpty
      ? ''
      : modelDescriptor(data.brainstormProviderId, data.brainstormModelId);
  if (brain.isEmpty || brain == synth) {
    buf.writeln('Model: $synth');
  } else {
    buf.writeln('Brainstorm: $brain');
    buf.writeln('Synthesis: $synth');
  }
  buf.writeln();
  for (final section
      in composeMuseSections(data, order, selection: selection)) {
    switch (section) {
      case MuseProposalsSection(:final strand, :final proposals):
        buf.writeln(museStrandLabel(strand).toUpperCase());
        for (final p in proposals) {
          buf.writeln('- ${p.title}');
          buf.writeln('    ${p.vision}');
          buf.writeln('    foothold: ${p.foothold}');
          if (p.citations.isNotEmpty) {
            buf.writeln('    cite: ${p.citations.join(", ")}');
          }
        }
        buf.writeln();
      case MuseBrainstormSection(:final ideas):
        buf.writeln('BRAINSTORM SPEW');
        for (final idea in ideas) {
          buf.writeln('- ${idea.text}');
        }
        buf.writeln();
      case MuseNotesSection(:final warnings):
        buf.writeln('NOTES');
        for (final warning in warnings) {
          buf.writeln('- $warning');
        }
        buf.writeln();
    }
  }
  return buf.toString().trim();
}
