// LogosDream — the end-to-end generative pipeline.
//
// Takes a diff (+ the engine that indexed the repo) and produces a
// human-readable string describing what the diff is *about*, drawn
// entirely from the repo's own spectral physics and commit history
// vocabulary. No external LLM, no embedding service.
//
// Pipeline:
//
//   1. Diff text       → DiffProbe (buildDiffProbe, existing)
//   2. DiffProbe       → MindQuery.weighted (.sourceWeights)
//   3. MindQuery       → MindResponse (LogosMind.ask)
//   4. Commit subjects → verb templates (_VerbHarvester)
//   5. Node paths      → friendly phrases (phraseForPath)
//   6. Compose         → "$verb $phrase" — optional prefix for muse
//
// Returns `null` when the diff is too small to dream about (no
// meaningful sources, empty probe, disconnected graph).
//
// All helpers are pure and deterministic (given the same inputs +
// rng seed where applicable). Test `logos_dream_test.dart` covers each
// piece and the end-to-end compose.

import 'dart:math' as math;

import 'logos_field.dart';
import 'logos_git.dart';
import 'logos_git_probe.dart';
import 'logos_mind.dart';

/// Phrase-friendly rendering of a path or identifier. Strips the
/// extension, replaces underscores / dashes with spaces, splits
/// camelCase at boundaries, filters out hex-like noise, and returns a
/// trimmed lower-case phrase.
///
///     phraseForPath('lib/backend/spectral_ricci.dart')   // "spectral ricci"
///     phraseForPath('src/AuthToken.ts')                  // "auth token"
///     phraseForPath('a/b/c.go')                          // "c"
///     phraseForPath('tmp/abc123def456')                  // ""  (hex noise)
///     phraseForPath('')                                  // ""
String phraseForPath(String path) {
  if (path.isEmpty) return '';
  final last = path.replaceAll('\\', '/').split('/').last;
  if (last.isEmpty) return '';
  // Strip extension.
  final dot = last.lastIndexOf('.');
  final stem = dot > 0 ? last.substring(0, dot) : last;
  if (stem.isEmpty) return '';
  // Reject hex-only fragments (long commit-hash-like or UUID tails).
  if (_looksLikeHex(stem)) return '';
  // camelCase / PascalCase split.
  final camelSplit = stem.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  // snake_case and kebab-case → spaces.
  final spaced = camelSplit.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  // Collapse whitespace + lowercase.
  final parts = spaced.toLowerCase().split(RegExp(r'\s+')).where((p) =>
      p.isNotEmpty && !_looksLikeHex(p) && p.length >= 2).toList();
  return parts.join(' ');
}

bool _looksLikeHex(String s) {
  if (s.length < 8) return false;
  var hex = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final isDigit = c >= 0x30 && c <= 0x39;
    final isHexLo = c >= 0x61 && c <= 0x66;
    final isHexHi = c >= 0x41 && c <= 0x46;
    if (isDigit || isHexLo || isHexHi) hex++;
  }
  return hex >= s.length - 1;
}

/// Extract the verb from a commit subject. Common Conventional Commits
/// prefixes (`feat:`, `fix:`, etc.) are stripped; the first significant
/// word is returned in lowercase. Returns `null` when nothing usable
/// is found.
String? verbFromCommitSubject(String subject) {
  if (subject.isEmpty) return null;
  // Strip Conventional-Commits prefix: `fix(auth): foo` → `foo`.
  var trimmed = subject.trim();
  final conv = RegExp(r'^(\w+)(\([^)]*\))?\s*:\s*');
  final match = conv.firstMatch(trimmed);
  if (match != null) {
    trimmed = trimmed.substring(match.end);
  }
  // Drop leading emoji / punctuation.
  trimmed = trimmed.replaceAll(RegExp(r'^[^\w]+'), '').trim();
  if (trimmed.isEmpty) return null;
  final words = trimmed.split(RegExp(r'\s+'));
  if (words.isEmpty) return null;
  final head = words.first.toLowerCase();
  // Filter noise: single letter, numbers, hex.
  if (head.length < 2 || _looksLikeHex(head)) return null;
  if (RegExp(r'^\d+$').hasMatch(head)) return null;
  return head;
}

/// Harvest the most common "action verbs" from a list of commit
/// subjects. Returns a frequency-ordered list of unique lowercase
/// verbs. Capped at [maxVerbs].
///
/// The goal is to let the repo *learn its own voice*: if this repo's
/// commits tend to start with "refactor", "tighten", "fix" — those are
/// the verbs the dream composer will prefer over generic ones.
List<String> harvestVerbTemplates(
  List<String> commitSubjects, {
  int maxVerbs = 16,
}) {
  final counts = harvestVerbCounts(commitSubjects);
  final ranked = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [for (var i = 0; i < ranked.length && i < maxVerbs; i++) ranked[i].key];
}

/// Raw verb frequency map from commit subjects. Preserved as a map
/// (not a ranked list) so downstream samplers can do weighted picks
/// without re-counting.
Map<String, int> harvestVerbCounts(List<String> commitSubjects) {
  final counts = <String, int>{};
  for (final s in commitSubjects) {
    final v = verbFromCommitSubject(s);
    if (v == null) continue;
    counts[v] = (counts[v] ?? 0) + 1;
  }
  return counts;
}

/// Weighted verb pick. Blends raw frequency with inverse frequency so
/// low-count verbs still surface. Drops verbs with count=1 (those are
/// usually nouns that sneak in as the first word — "gemini api …",
/// "history page now …") unless the whole pool would collapse.
///
/// [rarePreference] in [0, 1]: 0 = always top verb, 1 = inverse
/// frequency (rarer wins). 0.15 default is the sweet spot — variety
/// without weird one-offs.
///
/// [rng] makes the pick deterministic when seeded — pass a diff-hashed
/// Random so the same diff dreams the same phrase.
String pickWeightedVerb(
  Map<String, int> counts, {
  required math.Random rng,
  double rarePreference = 0.15,
  String fallback = 'update',
}) {
  if (counts.isEmpty) return fallback;
  var items = counts.entries
      .where((e) => e.value >= 2)
      .toList();
  if (items.isEmpty) items = counts.entries.toList();
  items.sort((a, b) => b.value.compareTo(a.value));
  final total = items.fold<int>(0, (a, e) => a + e.value);
  final top = items.first.value;
  var accum = 0.0;
  final weights = <double>[];
  for (final e in items) {
    final freqW = e.value / total;
    final invW = (top - e.value + 1) / (top + 1);
    final w = (1 - rarePreference) * freqW + rarePreference * invW;
    final clamped = w < 1e-6 ? 1e-6 : w;
    weights.add(clamped);
    accum += clamped;
  }
  final r = rng.nextDouble() * accum;
  var walk = 0.0;
  for (var i = 0; i < items.length; i++) {
    walk += weights[i];
    if (r <= walk) return items[i].key;
  }
  return items.first.key;
}

/// Small set of vowels used for a/an agreement at render time.
final _vowelSoundRegex = RegExp(r'^[aeiouAEIOU]');

/// Post-process rendered parts to fix `a engram` → `an engram`. Not a
/// full pronunciation dictionary — a trivial first-letter check that
/// covers the 95% case for filename-derived phrases.
void _fixArticles(List<String> parts) {
  for (var i = 0; i < parts.length - 1; i++) {
    if (parts[i] == 'a' && _vowelSoundRegex.hasMatch(parts[i + 1])) {
      parts[i] = 'an';
    }
  }
}

/// Lightweight sync capstone — composes a DiffProbe + LogosMind +
/// harvested verbs into a candidate commit-message phrase. Returns
/// `null` when inputs are too thin to dream (no primary paths,
/// no candidates after ask).
///
/// Deterministic given the same inputs; no rng, no I/O.
///
/// - [recentSubjects] is any length; the verb harvester caps to
///   [maxVerbsConsidered] most recent for cheap parsing.
/// - [defaultVerb] is used when the repo hasn't produced a verb
///   template yet (new repo, no commits).
/// - [minSources] skips trivially-small diffs that shouldn't
///   trigger a dream at all.
String? dreamCommitPhrase({
  required DiffProbe probe,
  required LogosMind mind,
  List<String> recentSubjects = const [],
  int maxVerbsConsidered = 40,
  String defaultVerb = 'update',
  int minSources = 1,
  bool includeDreamedModifier = true,
}) {
  if (probe.sourceWeights.length < minSources) return null;
  // Rank source files by weight and gather the top phrases from the
  // actual diff — not from the mind's speculative neighborhood. The
  // strongest file is the subject; the next distinct phrases become
  // modifiers. This keeps the dream grounded in what the user actually
  // touched rather than what the engine imagines.
  final ranked = probe.sourceWeights.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (ranked.isEmpty) return null;

  final subjectPhrase = phraseForPath(ranked.first.key);
  if (subjectPhrase.isEmpty) return null;

  final trimmedSubjects =
      recentSubjects.take(maxVerbsConsidered).toList(growable: false);
  final verbCounts = harvestVerbCounts(trimmedSubjects);
  final verbRng = math.Random(_diffHash(probe.sourceWeights).abs());
  final verb = verbCounts.isEmpty
      ? defaultVerb
      : pickWeightedVerb(
          verbCounts,
          rng: verbRng,
          rarePreference: 0.15,
          fallback: defaultVerb,
        );

  // Modifiers from the OTHER files in the actual diff, not from
  // speculative mind queries. Keeps the phrase honest about what
  // changed while still reading naturally.
  final modifiers = <String>[];
  void addModifier(String phrase) {
    if (phrase.isEmpty) return;
    if (phrase == subjectPhrase) return;
    if (modifiers.contains(phrase)) return;
    modifiers.add(phrase);
  }
  for (var i = 1; i < ranked.length && modifiers.length < 2; i++) {
    addModifier(phraseForPath(ranked[i].key));
  }

  // Only reach into the mind's neighborhood when the diff itself
  // didn't produce enough modifier phrases (single-file diffs).
  if (includeDreamedModifier && modifiers.length < 2) {
    final response = mind.ask(MindQuery.weighted(probe.sourceWeights));
    for (final c in response.candidates) {
      if (modifiers.length >= 2) break;
      addModifier(phraseForPath(c.path));
    }
  }

  // Pick a structural skeleton from the repo's own commits. If none
  // harvested, fall back to a simple "verb subject" (+ "with modifier"
  // when available). The diff-hash pick means the same diff always
  // gets the same structure, but different diffs cycle through the
  // repo's template catalog rather than always picking the top one.
  final structures = _harvestPhraseStructures(trimmedSubjects);
  final matching = structures
      .where((s) => s.modifierCount <= modifiers.length)
      .toList();

  final List<String> skeleton;
  if (matching.isEmpty) {
    skeleton = modifiers.isNotEmpty
        ? const [r'$S', 'with', r'$M1']
        : const [r'$S'];
  } else {
    final h = _diffHash(probe.sourceWeights).abs();
    skeleton = matching[h % matching.length].slots;
  }

  // Render verb + skeleton into a token list, then a/an-correct
  // adjacent articles before joining. Slots substitute the gathered
  // phrases; literals ("the", "with", "and", …) pass through as-is.
  final parts = <String>[verb];
  var modIdx = 0;
  for (final token in skeleton) {
    switch (token) {
      case r'$S':
        parts.add(subjectPhrase);
        break;
      case r'$M1':
      case r'$M2':
        if (modIdx >= modifiers.length) {
          return '${verb.trim()} ${subjectPhrase.trim()}';
        }
        parts.add(modifiers[modIdx]);
        modIdx++;
        break;
      default:
        parts.add(token);
    }
  }
  _fixArticles(parts);
  return parts.join(' ');
}

/// Structural skeleton harvested from a commit subject — a slot
/// sequence that preserves the original's connector/article words as
/// literals and replaces the noun phrases with `$S` / `$M1` / `$M2`
/// placeholders. Reused when composing the dream phrase so the output
/// reads in the same voice as the repo's own log.
class _PhraseStructure {
  final List<String> slots;
  const _PhraseStructure(this.slots);
  int get modifierCount =>
      slots.where((s) => s == r'$M1' || s == r'$M2').length;
}

/// Unicode-aware word tokenizer. `\p{L}` = any letter (Latin, Cyrillic,
/// Greek, Arabic, Hebrew, etc.), `\p{N}` = any number. Internal
/// hyphens/underscores/apostrophes preserved so `state-of-the-art`,
/// `can't`, `snake_case` stay single tokens. Bounded to 48 code points.
/// Requires the `unicode: true` flag — without it Dart's RegExp is
/// ECMAScript-shape and `\p{…}` isn't recognized.
final _kWordRegex = RegExp(
  r'[\p{L}][\p{L}\p{N}_\-]{0,47}',
  unicode: true,
);

/// Conventional Commits prefix, Unicode-aware: the prefix can be in
/// any script (a Russian repo might write `фикс:` or `добавить:`).
final _kConventionalPrefix = RegExp(
  r'^[\p{L}]{1,12}(?:\([^)]{1,64}\))?\s*:\s*',
  unicode: true,
);

/// Leading non-letter noise (emoji, punctuation, whitespace, ZWJ)
/// before the first real word. Bounded so a pathological subject
/// can't run the regex forever.
final _kLeadingNoise = RegExp(r'^[^\p{L}]{0,20}', unicode: true);

/// Words to use as slot delimiters. Derived from the commit corpus
/// itself — no hardcoded language lists. See
/// [discoverStructuralWords] for the three-signal heuristic (frequent
/// + short + non-initial).

bool _isSlotPlaceholder(String s) =>
    s == r'$S' || s == r'$M1' || s == r'$M2';

/// Keyboard-mash detector — same Unicode letter repeated 4+ times.
/// `\1` backreference enforces "same char"; bounded {3,} for the
/// repeat tail so a mash of arbitrary length still matches in O(n).
final _kKeyboardMash = RegExp(
  r'^([\p{L}])\1{3,}$',
  unicode: true,
);

/// Filename-only update: `Update HistoryPage.tsx`. English-anchored
/// case-insensitively. Repos in other languages simply won't match
/// this, which is fine — their filename-only commits pass through to
/// normal parsing.
final _kFilenameUpdate = RegExp(
  r'^update\s+[\w\-./]{1,80}\.[\w]{1,8}$',
  caseSensitive: false,
);

/// Strip the Conventional Commits prefix and any leading non-letter
/// noise (emoji, punctuation). Returns a trimmed view suitable for
/// tokenization.
String _stripCommitPrefix(String subject) {
  var s = subject.trim();
  final conv = _kConventionalPrefix.firstMatch(s);
  if (conv != null) s = s.substring(conv.end);
  s = s.replaceFirst(_kLeadingNoise, '').trim();
  return s;
}

/// Extract Unicode word tokens in order. Caller lowercases as needed.
List<String> _extractWords(String s) =>
    _kWordRegex.allMatches(s).map((m) => m.group(0)!).toList();

/// Decide whether a commit subject is pure noise (keyboard mash,
/// single-word, or filename-only) and should be excluded from the
/// grammar. Matches the Python lab's `should_skip` 1:1.
bool _shouldSkipSubject(String subject) {
  final stripped = _stripCommitPrefix(subject);
  if (stripped.isEmpty) return true;
  final words = _extractWords(stripped);
  if (words.length < 2) return true;
  // Mash check: letters-only flattened form.
  final flat = stripped
      .toLowerCase()
      .split('')
      .where((c) => RegExp(r'[\p{L}]', unicode: true).hasMatch(c))
      .join();
  if (_kKeyboardMash.hasMatch(flat)) return true;
  if (_kFilenameUpdate.hasMatch(stripped)) return true;
  final lowered = words.map((w) => w.toLowerCase()).toSet();
  if (lowered.length == 1) return true;
  return false;
}

/// Discover structural words from the commit corpus itself. Four
/// signals stacked — ALL must fire before a word qualifies:
///
///   A. FREQUENCY — appears in ≥ [minSubjectRatio] of clean subjects.
///   B. SHORTNESS — ≤ [maxWordLen] characters. Articles and
///      prepositions are 1–4 chars across every space-separated
///      script (a/the/for/of · el/la/de/con · der/die/mit · в/с/и).
///   C. NON-INITIAL — appears as the first word of a subject in
///      under [firstPositionCeiling] of its occurrences. Verbs lead;
///      structural words almost never do.
///   D. LOWERCASE-DOMINANT — uppercase-in-original under
///      [uppercaseCeiling] of occurrences. Without this, short
///      acronyms (`UI`, `API`, `PR`, `OS`) pass all prior signals
///      and pollute the grammar with literal noise.
///
/// Works for any space-separated script. CJK/Thai/Khmer need a
/// morphological segmenter — returned set will be small or empty and
/// generation falls back to `$S` (no slot literals).
Set<String> discoverStructuralWords(
  List<String> subjects, {
  double minSubjectRatio = 0.10,
  int maxWordLen = 4,
  double firstPositionCeiling = 0.25,
  double uppercaseCeiling = 0.35,
  int minCorpus = 3,
}) {
  final clean = <String>[];
  for (final s in subjects) {
    if (!_shouldSkipSubject(s)) clean.add(s);
  }
  if (clean.length < minCorpus) return const {};
  final subjCount = clean.length;
  final inSubject = <String, int>{};
  final firstWord = <String, int>{};
  final upperTotal = <String, int>{};
  final seenTotal = <String, int>{};
  for (final s in clean) {
    final stripped = _stripCommitPrefix(s);
    final wordsOriginal = _extractWords(stripped);
    if (wordsOriginal.isEmpty) continue;
    final wordsLower = wordsOriginal.map((w) => w.toLowerCase()).toList();
    for (final w in wordsLower.toSet()) {
      inSubject[w] = (inSubject[w] ?? 0) + 1;
    }
    firstWord[wordsLower[0]] = (firstWord[wordsLower[0]] ?? 0) + 1;
    for (var i = 0; i < wordsOriginal.length; i++) {
      final orig = wordsOriginal[i];
      final lower = wordsLower[i];
      seenTotal[lower] = (seenTotal[lower] ?? 0) + 1;
      if (orig.length >= 2 &&
          orig == orig.toUpperCase() &&
          orig != orig.toLowerCase()) {
        upperTotal[lower] = (upperTotal[lower] ?? 0) + 1;
      }
    }
  }
  final structural = <String>{};
  final threshold = math.max(2, (minSubjectRatio * subjCount).toInt());
  inSubject.forEach((word, count) {
    if (count < threshold) return;
    if (word.length > maxWordLen) return;
    final firstRatio = count > 0 ? (firstWord[word] ?? 0) / count : 0.0;
    if (firstRatio > firstPositionCeiling) return;
    final total = seenTotal[word] ?? 1;
    final upperRatio = (upperTotal[word] ?? 0) / total;
    if (upperRatio > uppercaseCeiling) return;
    structural.add(word);
  });
  return structural;
}

/// Parse a single commit subject into a slot structure, given the
/// corpus-derived [structural] set. Returns null when the subject
/// fails the noise filter or yields no slots.
_PhraseStructure? _parsePhraseStructure(
  String subject,
  Set<String> structural,
) {
  if (_shouldSkipSubject(subject)) return null;
  final stripped = _stripCommitPrefix(subject);
  if (stripped.isEmpty) return null;
  final words = _extractWords(stripped).map((w) => w.toLowerCase()).toList();
  if (words.length < 2) return null;
  final rest = words.sublist(1); // drop the verb
  final out = <String>[];
  var slotIndex = 0;
  var inContent = false;
  for (final w in rest) {
    final isStruct = structural.contains(w);
    if (isStruct) {
      if (inContent) {
        out.add(slotIndex == 0
            ? r'$S'
            : (slotIndex == 1 ? r'$M1' : r'$M2'));
        slotIndex++;
        inContent = false;
        if (slotIndex >= 3) break;
      }
      // Adjacent-literal collapse. Two structurals in a row (e.g.
      // `in and` from "stuff it all in and ship it") render as junk;
      // keep the latter — it's closest to the next slot.
      if (out.isNotEmpty && !_isSlotPlaceholder(out.last)) {
        out[out.length - 1] = w;
      } else {
        out.add(w);
      }
    } else {
      inContent = true;
    }
  }
  if (inContent && slotIndex < 3) {
    out.add(slotIndex == 0
        ? r'$S'
        : (slotIndex == 1 ? r'$M1' : r'$M2'));
    slotIndex++;
  }
  if (slotIndex == 0) return null;
  while (out.isNotEmpty && !_isSlotPlaceholder(out.last)) {
    out.removeLast();
  }
  if (out.isEmpty) return null;
  return _PhraseStructure(out);
}

List<_PhraseStructure> _harvestPhraseStructures(
  List<String> subjects, {
  int maxStructures = 12,
}) {
  final structural = discoverStructuralWords(subjects);
  final counts = <String, int>{};
  final stored = <String, _PhraseStructure>{};
  for (final s in subjects) {
    final parsed = _parsePhraseStructure(s, structural);
    if (parsed == null) continue;
    final key = parsed.slots.join(' ');
    counts[key] = (counts[key] ?? 0) + 1;
    stored[key] ??= parsed;
  }
  final ranked = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (var i = 0; i < ranked.length && i < maxStructures; i++)
      stored[ranked[i].key]!,
  ];
}

/// Deterministic integer derived from the diff's source-weights map.
/// Same diff → same hash → stable template / dream selections across
/// repeated runs. Different diffs → different hashes → structures
/// rotate naturally without explicit state.
int _diffHash(Map<String, double> weights) {
  var h = 0x811c9dc5; // fnv-1a offset basis; arbitrary, just a seed
  final keys = weights.keys.toList()..sort();
  for (final k in keys) {
    h = (h ^ k.hashCode) * 0x01000193;
    h &= 0x7fffffff;
  }
  return h;
}

/// Async wrapper: builds a DiffProbe from a live repo + diff, then
/// runs [dreamCommitPhrase]. Returns `null` on trivial inputs.
Future<String?> dreamFromDiff({
  required String repoPath,
  required String diffText,
  required LogosGit engine,
  List<String> recentSubjects = const [],
}) async {
  if (diffText.isEmpty) return null;
  final probe = await buildDiffProbe(
    repoPath: repoPath,
    diffText: diffText,
    engine: engine,
  );
  if (probe.sourceWeights.isEmpty) return null;
  final mind = LogosMind(engine: engine);
  return dreamCommitPhrase(
    probe: probe,
    mind: mind,
    recentSubjects: recentSubjects,
  );
}

/// Combined helper: build the probe once, then derive both the dreamed
/// phrase AND the field's character classification.
///
/// Either field can be null independently — thin diffs yield null
/// phrases; disconnected graphs yield null characters. The UI can
/// surface whichever is available.
Future<({String? phrase, LogosFieldCharacter? character})>
    dreamAndCharacterizeFromDiff({
  required String repoPath,
  required String diffText,
  required LogosGit engine,
  List<String> recentSubjects = const [],
}) async {
  if (diffText.isEmpty) return (phrase: null, character: null);
  final probe = await buildDiffProbe(
    repoPath: repoPath,
    diffText: diffText,
    engine: engine,
  );
  if (probe.sourceWeights.isEmpty) return (phrase: null, character: null);
  final mind = LogosMind(engine: engine);
  final phrase = dreamCommitPhrase(
    probe: probe,
    mind: mind,
    recentSubjects: recentSubjects,
  );
  LogosFieldCharacter? character;
  try {
    character =
        LogosField.fromDiffProbe(engine: engine, probe: probe).character;
  } catch (_) {
    // Engine has no spectral basis yet (tiny repo) — degrade gracefully.
    character = null;
  }
  return (phrase: phrase, character: character);
}

/// Slugify a dreamed phrase for use as a branch name, git ref, or
/// identifier. Lowercases, strips anything that isn't a word char or
/// a hyphen, collapses whitespace to single hyphens, trims stray
/// leading/trailing hyphens, and caps the length so the result fits
/// in sane git ref budgets.
///
///     slugifyForBranch('thread auth through router')  // "thread-auth-through-router"
///     slugifyForBranch('Supercharge Logos — engine')  // "supercharge-logos-engine"
///     slugifyForBranch('')                            // ""
String slugifyForBranch(String phrase, {int maxLen = 48}) {
  if (phrase.isEmpty) return '';
  var out = phrase.toLowerCase();
  // Replace any run of non-[a-z0-9-] with a single space, then
  // squeeze spaces into hyphens.
  out = out.replaceAll(RegExp(r'[^a-z0-9-]+'), ' ');
  out = out.replaceAll(RegExp(r'\s+'), '-');
  out = out.replaceAll(RegExp(r'-+'), '-');
  out = out.replaceAll(RegExp(r'^-+|-+$'), '');
  if (out.length > maxLen) {
    out = out.substring(0, maxLen).replaceAll(RegExp(r'-+$'), '');
  }
  return out;
}

