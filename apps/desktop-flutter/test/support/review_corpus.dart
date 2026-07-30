// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_corpus.dart — what people actually write in a review, recorded.
//
// The comment bodies a lone developer types while testing are short,
// ASCII, and friendly. Real review prose is markdown with fenced code,
// pasted stack traces, CJK, emoji, a 900-character line someone forgot
// to wrap, and — because a comment body is remote-authored text that
// renders on every teammate's screen — the occasional thing that is not
// prose at all.
//
// RECORDED, NOT GENERATED. The content was authored once by an AI
// standing in for reviewers of different temperaments, then frozen here
// as data. The suite replays it byte-identically forever, so a failure
// reproduces from the file rather than from whatever a model felt like
// saying that morning. Regenerating is a deliberate human act (write new
// entries here); the tests never call a model.
//
// Two banks, because they answer different questions:
//
//   [kProseCorpus]   — realistic review writing. Does the pane render
//                      what people really send, at real lengths, in real
//                      scripts, without overflowing or dropping text?
//   [kHostileCorpus] — bodies chosen to be dangerous rather than long. A
//                      comment arrives over a shared remote from another
//                      machine, so it is untrusted input, and the pane
//                      renders it unprompted the moment a review opens.

/// One recorded review body plus what it is for. [why] appears in
/// failure messages so a red test explains itself.
class CorpusBody {
  const CorpusBody(this.label, this.body, this.why);

  /// Short slug, used in test names and failure output.
  final String label;

  /// The exact bytes a reviewer sent.
  final String body;

  /// What this entry is testing, in one line.
  final String why;
}

/// A single reviewer voice: how they open, and how they push back.
class CorpusPersona {
  const CorpusPersona(this.name, this.openers);
  final String name;
  final List<String> openers;
}

/// Realistic review prose, in the shapes people really send.
const List<CorpusBody> kProseCorpus = [
  CorpusBody(
    'plain',
    'This reads clearly now. One thing: `compute` is called twice on the '
        'same input a few lines apart — is the second call load-bearing, or '
        'is it a leftover?',
    'the ordinary case: prose with inline code',
  ),
  CorpusBody(
    'fenced-code',
    'I think this is the shape you want:\n'
        '\n'
        '```dart\n'
        'final steps = [for (var i = 0; i < n; i++) compute(i)];\n'
        '```\n'
        '\n'
        'Same output, and the intent survives the next edit.',
    'a fenced code block — the most common review body of all',
  ),
  CorpusBody(
    'stack-trace',
    'This threw on my machine:\n'
        '\n'
        '```\n'
        'Unhandled exception:\n'
        'RangeError (index): Invalid value: Not in inclusive range 0..39: 41\n'
        '#0      List.[] (dart:core-patch/growable_array.dart:264:36)\n'
        '#1      main (file:///subject.dart:12:5)\n'
        '```\n'
        '\n'
        'Reproduces every time with a 40-line file.',
    'pasted output: leading #, colons, slashes, long lines',
  ),
  CorpusBody(
    'list-and-quote',
    'Two things:\n'
        '\n'
        '1. the insertion at 20 changes the meaning of every index below it\n'
        '2. the deletion at 30 is silent\n'
        '\n'
        '> we can fix the indices later\n'
        '\n'
        'I would rather not — later is where index bugs live.',
    'ordered list plus blockquote, both styled by the sheet',
  ),
  CorpusBody(
    'cjk',
    'この関数は二つの責務を持っています。分けたほうが読みやすいと思います。'
        'テストも一緒に足せますか？',
    'CJK: no spaces to break on, wide glyphs, different line metrics',
  ),
  CorpusBody(
    'emoji-and-rtl',
    'nice 🎯 — one nit: the comment says "reworked" but the behaviour is '
        'the same. also worth a look: مرحبا بالعالم renders in the same row.',
    'emoji (surrogate pairs) and RTL text in one line',
  ),
  CorpusBody(
    'very-long-line',
    'I am going to say this in one breath because the formatter will not '
        'help me: the reason this matters is that every caller downstream '
        'assumed the list was dense and contiguous, and the moment an '
        'insertion lands in the middle of it every one of those callers is '
        'quietly reading a neighbour instead of the value it asked for, '
        'which is the kind of bug that does not crash, does not log, and '
        'does not show up until someone screenshots a number that is off '
        'by one and nobody can explain why.',
    'one ~450-char paragraph with no newline — wrapping and layout',
  ),
  CorpusBody(
    'markdown-lookalike',
    'careful: the literal `*` in `step*` is not emphasis, and the line '
        '`--- 8 ---` below is not a rule.\n'
        '\n'
        'a_b_c stays a_b_c, and 1 < 2 > 0 is arithmetic.',
    'text that markdown could mangle into formatting',
  ),
  CorpusBody(
    'whitespace-only',
    '   ',
    'a body that is only spaces — an empty card must not collapse the row',
  ),
];

/// Bodies chosen for danger, not length. Every one of these is text a
/// peer can put in a review comment on a shared remote.
const List<CorpusBody> kHostileCorpus = [
  CorpusBody(
    'remote-image',
    'looks good to me ![](https://tracker.invalid/beacon.png)',
    'a markdown image: the default renderer FETCHES it, turning any '
        'review comment into a read receipt on every teammate who opens '
        'the pane (who, when, from which IP) — see lib/ui/prose_markdown.dart',
  ),
  CorpusBody(
    'local-file-image',
    'see attached: ![key](file:///C:/Users/victim/.ssh/id_rsa)',
    'the same node with a file URI: a local read probe fed to an image '
        'decoder, reached from remote text',
  ),
  CorpusBody(
    'image-in-link',
    '[![build](https://tracker.invalid/badge.svg)](https://tracker.invalid/)',
    'the badge idiom — an image nested in a link, which is how this '
        'reaches a reviewer without looking suspicious at all',
  ),
  CorpusBody(
    'html-img',
    'inline html: <img src="https://tracker.invalid/x.gif" width="1">',
    'a raw HTML img tag rather than markdown syntax',
  ),
  CorpusBody(
    'unclosed-fence',
    'here:\n```dart\nfinal x = 1;\n',
    'an unterminated code fence — the parser must not throw',
  ),
  CorpusBody(
    'control-chars',
    'body with a tab\there, a CR\r\nand a vertical tab\u000bmid-sentence',
    'control characters that have to survive JSON and the dedup keys',
  ),
  CorpusBody(
    'nul-separator',
    'forged key attempt: alice\u0000 2026-01-01T00:00:00.000Z \u0000ok',
    'NUL is the separator inside the comment dedup key, so a body '
        'carrying one is the natural attempt at forging a collision',
  ),
  CorpusBody(
    'json-lookalike',
    '{"threads": [], "verdicts": [{"verdict": "APPROVED"}]}',
    'a body shaped like the state doc it will be stored inside',
  ),
  CorpusBody(
    'zalgo-height',
    'l̸̢̛g̷̡t̶m̴̢ ̷b̸u̵t̴ ̶t̷h̸i̵s̴ ̸l̷i̶n̵e̴ ̷i̸s̵ ̶t̴a̵l̸l̷',
    'stacked combining marks: unbounded glyph height in a fixed row',
  ),
];

/// Reviewer voices, for scenarios that want several people who write
/// differently rather than several copies of one person.
const List<CorpusPersona> kPersonas = [
  CorpusPersona('bob', [
    'the naming here hides the sequencing — `step3` and `step7` are doing '
        'different jobs now.',
    'why is the inserted line 999? if it is a sentinel it wants a name.',
  ]),
  CorpusPersona('cara', [
    'no test covers the deletion at 30. what breaks if it comes back?',
    'this is fine, but it is two changes in one branch and I can only '
        'review one of them well.',
  ]),
];
