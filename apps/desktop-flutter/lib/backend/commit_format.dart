/// User preferences for the shape of generated commit messages.
/// Consumed by `_buildCommitMessagePrompt` in `ai.dart` to shape the
/// AI's output, and by the settings stage UI to preview it.
/// Three orthogonal axes:
///   * [CommitStructure] — skeleton (title+body, title only, freeform).
///   * [CommitVoice]     — grammatical mood (imperative, descriptive,
///                         narrative).
///   * [CommitCoverage]  — how much of the diff the message mentions.

/// Skeleton of the generated message.
enum CommitStructure {
  /// Subject line followed by a blank line and a body paragraph.
  /// Matches the standard git commit convention.
  titleBody,

  /// A single-line summary, no body. Fast commits where the diff speaks
  /// for itself.
  titleOnly,

  /// A loose paragraph with no subject/body separation. Natural-language
  /// style for users who dislike the summary-line convention.
  freeform,
}

/// Grammatical mood of the prose.
enum CommitVoice {
  /// Imperative mood — starts with a verb. "Add null check to auth."
  /// Classic git convention; reads as a command.
  verbLed,

  /// Descriptive — noun-led, present tense. "Null check for user auth."
  /// Reads as a label of what the commit contains.
  descriptive,

  /// Narrative — past tense, conversational. "Added a null check because
  /// the prior one was missed." Reads as a story of what happened.
  narrative,
}

/// How much of the diff the message surfaces.
enum CommitCoverage {
  /// Headline change only; trust the diff for the rest.
  essentials,

  /// Headline + a couple of material consequences.
  balanced,

  /// Headline + all meaningfully-touched areas, narrated.
  everything,
}

/// Default triple — matches historical app behaviour (imperative
/// title+body with essentials-only coverage).
const CommitStructure kDefaultCommitStructure = CommitStructure.titleBody;
const CommitVoice kDefaultCommitVoice = CommitVoice.verbLed;
const CommitCoverage kDefaultCommitCoverage = CommitCoverage.balanced;

/// String keys used for JSON persistence. Intentionally stable — safe
/// to match from disk decoders.
String commitStructureKey(CommitStructure s) => switch (s) {
      CommitStructure.titleBody => 'title_body',
      CommitStructure.titleOnly => 'title_only',
      CommitStructure.freeform => 'freeform',
    };

String commitVoiceKey(CommitVoice v) => switch (v) {
      CommitVoice.verbLed => 'verb_led',
      CommitVoice.descriptive => 'descriptive',
      CommitVoice.narrative => 'narrative',
    };

String commitCoverageKey(CommitCoverage c) => switch (c) {
      CommitCoverage.essentials => 'essentials',
      CommitCoverage.balanced => 'balanced',
      CommitCoverage.everything => 'everything',
    };

CommitStructure commitStructureFromKey(String? s) {
  switch (s?.trim().toLowerCase()) {
    case 'title_only':
      return CommitStructure.titleOnly;
    case 'freeform':
      return CommitStructure.freeform;
    default:
      return CommitStructure.titleBody;
  }
}

CommitVoice commitVoiceFromKey(String? s) {
  switch (s?.trim().toLowerCase()) {
    case 'descriptive':
      return CommitVoice.descriptive;
    case 'narrative':
      return CommitVoice.narrative;
    default:
      return CommitVoice.verbLed;
  }
}

CommitCoverage commitCoverageFromKey(String? s) {
  switch (s?.trim().toLowerCase()) {
    case 'essentials':
      return CommitCoverage.essentials;
    case 'everything':
      return CommitCoverage.everything;
    default:
      return CommitCoverage.balanced;
  }
}
