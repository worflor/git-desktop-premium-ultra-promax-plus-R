import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/build_info.dart';
import '../../ui/design_primitives.dart';
import '../../ui/morph_text.dart';
import '../../ui/tokens.dart';

class ReleaseNotesPanel extends StatelessWidget {
  const ReleaseNotesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        _VersionHeader(tokens: t),
        const SizedBox(height: 24),
        for (final entry in _changelog) ...[
          _ReleaseEntry(entry: entry, tokens: t),
          const SizedBox(height: 20),
        ],
        const SizedBox(height: 16),
        _SectionDivider(tokens: t),
        const SizedBox(height: 24),
        for (final entry in _aboutDevelopment) ...[
          _AboutBlock(entry: entry, tokens: t),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _VersionHeader extends StatelessWidget {
  final AppTokens tokens;
  const _VersionHeader({required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final version = BuildInfo.version.isNotEmpty ? BuildInfo.version : 'dev';
    final channel = BuildInfo.channel.name.toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: t.chromeAccent.withValues(alpha: 0.10),
                border: Border.all(
                    color: t.chromeAccent.withValues(alpha: 0.30)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                channel,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10,
                  fontFamily: AppFonts.mono,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              version,
              style: TextStyle(
                color: t.textStrong,
                fontSize: 14,
                fontFamily: AppFonts.mono,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (BuildInfo.gitSha != null) ...[
              const SizedBox(width: 6),
              Text(
                BuildInfo.gitSha!,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ReleaseEntry extends StatelessWidget {
  final _ReleaseNote entry;
  final AppTokens tokens;
  const _ReleaseEntry({
    required this.entry,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              entry.version.toUpperCase(),
              style: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                fontFamily: AppFonts.mono,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              entry.date,
              style: TextStyle(
                color: t.textFaint,
                fontSize: 10,
                fontFamily: AppFonts.mono,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final bullet in entry.bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 8),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.textFaint,
                    ),
                  ),
                ),
                Expanded(
                  child: _ReactiveText(
                    text: bullet,
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                    accentColor: t.accentBright,
                    bgColor: t.bg0,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final AppTokens tokens;
  const _SectionDivider({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: tokens.textFaint.withValues(alpha: 0.15),
    );
  }
}

class _AboutBlock extends StatelessWidget {
  final _AboutEntry entry;
  final AppTokens tokens;
  const _AboutBlock({
    required this.entry,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReactiveText(
          text: entry.question,
          style: TextStyle(
            color: t.textNormal,
            fontSize: 11,
            fontFamily: AppFonts.mono,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
          accentColor: t.accentBright,
          bgColor: t.bg0,
        ),
        const SizedBox(height: 8),
        _ReactiveText(
          text: entry.body,
          style: TextStyle(
            color: t.textMuted,
            fontSize: 12,
            height: 1.6,
          ),
          accentColor: t.accentBright,
          bgColor: t.bg0,
        ),
      ],
    );
  }
}

class _ReactiveText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color accentColor;
  final Color bgColor;

  const _ReactiveText({
    required this.text,
    required this.style,
    required this.accentColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    final spaceW = _measureSpace(resolved, context);
    final paragraphs = text.split('\n\n');
    if (paragraphs.length == 1) {
      return _buildParagraph(paragraphs[0], resolved, spaceW);
    }
    final gap = (resolved.fontSize ?? 14) * (resolved.height ?? 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          _buildParagraph(paragraphs[i], resolved, spaceW),
        ],
      ],
    );
  }

  static Widget _buildParagraph(
      String para, TextStyle resolved, double spaceW) {
    final words = para.split(' ').where((w) => w.isNotEmpty).toList();
    return Wrap(
      spacing: spaceW,
      children: [
        for (final word in words)
          _ReactiveWord(word: word, style: resolved),
      ],
    );
  }

  static double _measureSpace(TextStyle style, BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }
}

class _ReactiveWord extends StatefulWidget {
  final String word;
  final TextStyle style;

  const _ReactiveWord({required this.word, required this.style});

  @override
  State<_ReactiveWord> createState() => _ReactiveWordState();
}

class _ReactiveWordState extends State<_ReactiveWord> {
  String _display = '';
  bool _inside = false;
  bool _morphing = false;

  @override
  void initState() {
    super.initState();
    _display = widget.word;
  }

  @override
  void didUpdateWidget(_ReactiveWord old) {
    super.didUpdateWidget(old);
    if (old.word != widget.word) {
      _display = widget.word;
      _inside = false;
      _morphing = false;
    }
  }

  void _onEnter() {
    _inside = true;
    _kick();
  }

  void _kick() {
    if (!_inside || _morphing) return;
    _morphing = true;
    setState(() => _display = _perturb(widget.word));
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      setState(() => _display = widget.word);
      final pause = 500 + _rng.nextInt(400);
      Future.delayed(Duration(milliseconds: pause), () {
        if (!mounted) return;
        _morphing = false;
        if (_inside) _kick();
      });
    });
  }

  void _onExit() {
    _inside = false;
  }

  static final _rng = math.Random();

  static String _perturb(String text) {
    if (text.length < 3) return text;
    final chars = text.split('');
    final swaps = (chars.length / 6).ceil().clamp(1, 3);
    for (var i = 0; i < swaps; i++) {
      final idx = _rng.nextInt(chars.length - 1);
      final tmp = chars[idx];
      chars[idx] = chars[idx + 1];
      chars[idx + 1] = tmp;
    }
    return chars.join();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      child: ThemeMorphText(_display, style: widget.style),
    );
  }
}

class _AboutEntry {
  final String question;
  final String body;
  const _AboutEntry({required this.question, required this.body});
}

class _ReleaseNote {
  final String version;
  final String date;
  final List<String> bullets;
  const _ReleaseNote({
    required this.version,
    required this.date,
    required this.bullets,
  });
}

const _aboutDevelopment = <_AboutEntry>[
  _AboutEntry(
    question: 'WHY FLUTTER?',
    body: 'The first version of this was a Tauri app (Rust + TypeScript). '
        'I already knew it felt slow. Caught a streamer saying the same '
        'thing on a live stream I don\'t usually watch to '
        'finally to swap. He didn\'t suggest Flutter; far from it. I found Dart '
        'on my own, threw together a prototype, and app startup went from about '
        '15 seconds to under a second. Night and day. '
        'farewell Tauri era.\n\n'
        'Flutter\'s rendering pipeline is closer to a game engine than a '
        'DOM, and for a desktop app where the UI is the product that\'s '
        'everything. Dart turned out to be a genuinely good language too. '
        'The math behind the spectral engine was prototyped in Rust first, '
        'so that work carried over fine.\n\n'
        'Flutter is cross-platform by default, which is great, but it\'s '
        'Googley in nature so there are quirks. I think I\'ll make do tho.',
  ),
  _AboutEntry(
    question: 'WHAT IS THE SPECTRAL ENGINE?',
    body: 'Every time you commit, the files you change together form '
        'patterns over time. The spectral engine reads your commit graph '
        'and decomposes those co-change patterns into signals: which files '
        'are coupled, how tightly, and what structural role they play in '
        'the repo. Basically spectral analysis on your development '
        'history. In a git client. On purpose.\n\n'
        'The math is new, so I\'m treating it like game feel: tune it, '
        'test it, adjust it, and keep going until the signals feel '
        'correct.\n\n'
        'Those signals feed into everything. The seismograph in history, '
        'the painted bars under commit subjects, the review system, Muse, '
        'the file constellation. The whole app reasons from this layer '
        'down, not the other way around.',
  ),
  _AboutEntry(
    question: 'WHERE IS THIS GOING?',
    body: 'The first milestone is full parity with GitHub Desktop, '
        'SourceTree, and GitKraken. A cross-platform git client that '
        'feels fast and handles the fundamentals better than anything '
        'else. That\'s mostly here. The spectral engine already gives '
        'us an advantage for operations that other clients make you think '
        'through manually.\n\n'
        'Past that, the goal is to surpass every other git client in '
        'speed, accessibility, intelligence, and overall UX. There\'s more in the pipeline '
        'than what\'s announced here.',
  ),
];

const _changelog = <_ReleaseNote>[
  _ReleaseNote(
    version: 'v0.1.1',
    date: '2026-05-14',
    bullets: [
      'Welcome to the first non-internal release. We have:',
      'Beep beep, Wick.exe alpha integration is here for those who have the binary. It is unreleased, extremely alpha, and already causing a suspiciously low amount of trouble.',
      'Inline interactive re-order for commits. (allegedly)',
      'I spent an afternoon designing how Manifold should present a 3-way merge and settled on a unified fullscreen per-file experience. Built in Logos magic to assist, but designed for The Manual Way™.',
      'Command palette got smarter mostly by getting smaller. Some options were removed, some were merged, and the end result is fewer ways to ask for the same thing badly.',
      'OpenRouter API support is new in this build, with provider settings and model selection wired into the same AI setup as the other backends.',
      'Ask has been reworked into more of a debug engine. Very alpha.',
      'Settings got shorter to scroll through. The three AI feature blocks are collapsed into one stage, Diagnostics now defaults to the UI section because it is usually the least dramatic one, and the scrollbar has a little breadcrumb bubble that follows along so you know where you are.',
      'The commit message field still grows normally while you type, but once it starts needing real room, an expand button appears for opening a dedicated composer panel. Long commit messages get an actual writing surface now.',
      'Claude model-list extraction got some outside-the-app binary surgery. Not a visible app feature, but it keeps the provider/model wiring honest.',
      'glass.frag got another material pass: gloopier, thiccer, and globier.',
      'Adjusted Loverboy\'s background algorithm. I still can\'t tell if it\'s ugly good or ugly ugly; the line between "oh!" and "oh..." is thin.',
      'Adjusted Petrichor to keep the same rainy feel, but with shaders and more vibesss.',
      'New Lady Entropy theme with bot-eye freeze tag, per-surface tint variation, and dataScrawl text effect.',
      'Theme knobs now get tiny per-theme animations overall, giving each skin a little more motion language. The exact shapes may keep shifting, but the direction is there: Petrichor droplets lean, Aether/Nacre/Loverboy move their glass caustics, Helix turns like a valve, Quanta snaps orientation, Redshift tightens its sight, Halo/Bibble radiate, Nightwalker opens into a blurrier void, Crafty depresses, Blackboard tilts, Kirby pops, Phosphor blinks, and Lady Entropy\'s thumb looks where you drag: iris and pupil track the value, the highlight stays loyal to the light, the pupil dilates on press, and the iris boots open on theme switch.',
      'More of the motion system is being taught where things came from: etch, gloss, and vibration feedback can originate from the clicked pixel; text morphs ripple in reading direction so insertions push rightward and deletions close leftward; DataScrawl leans by spatial side instead of arbitrary character parity; and tiled particles scale density with the window across stardust, quantum, embers, glitter, voxels, void rain, chalk, and inkblots.',
      'Reduced motion and accessability passes too.',
    ],
  ),
  _ReleaseNote(
    version: 'v0.1.0',
    date: '2026-05-08',
    bullets: [
      'Built from scratch in Flutter over about five weeks. The whole git surface is here: staging, branches, history, stash, blame, file history, parallel worktrees, and sync.',
      'Command palette handles navigation, git commands, branch operations, stash actions, settings toggles, and search across repos, branches, commits, tags, and changed files.',
      'PRs and issues work locally by default, stored as orphan git refs in the repo itself. No remote needed. When you do have a remote, they sync bidirectionally with GitHub, GitLab, or Gitea; Git and GitHub are the deepest integrations right now.',
      'PR conflict hints go past plain file overlap. Each PR gets an orbital shape from Logos diffusion; WILL FIGHT combines shared files with cross-orbit similarity, so related branches can surface as merge-order risk even when they are not editing the exact same paths.',
      'Patches are a first-class workflow. Import from file or clipboard, preview with conflict detection, apply, or reverse. For when you\'re not down to big git.',
      'A spectral analysis engine runs underneath the app. In plain terms: it turns your repo history into a weighted map of which files tend to matter together, then runs the current diff through that map. The useful part is the receipts: when Logos surfaces a related file, it can point at the signal that pulled it in: co-change, path structure, transport lanes like source->test, integrity gates, residual surprise, or shadow history. Practically, that means better review context, better commit grouping, better Muse suggestions, and UI that reacts to the actual shape of the change instead of just the file list.',
      'Logos has counterfactual memory too. Reverts, reset-away commits, and abandoned branches are mined into a discounted shadow-coupling graph, so discarded timelines can corroborate real co-change signals or flag a current diff as deja-vu.',
      'The interactive starfield during commit review and Muse is a live readout of that process: files, evidence, and diffusion energy moving around while the engine decides what matters.',
      'History renders each commit as a drillable seismograph. The painted bar under each subject encodes importance, add/del ratio, coherence, and working-tree overlap without labels.',
      'Commit review gives you grounded observations with four guardrail stages: Loose, Balanced, Strict, and Paranoid.',
      'Muse is a three-phase pipeline (diverge, reshape, synthesize) that brainstorms around what your staged changes could lead to. Results come back in four tiers: Spark, Current, Horizon, and Fever. You can drag file spokes while it runs to steer where it looks.',
      'Atlas, the File Constellation beta, groups staged files by correlatedness into candidate commits. Still early but the direction is there.',
      'Repo X-Ray gives a structural snapshot across map, time, signals, and summary views.',
      'Known rough edges: CPU usage on Windows runs hotter than expected, so if your fans spin up, that\'s me. The Linux AppImage ships but is untested as of this build. Some UI elements still have minor visual bugs, mostly in newer or weirder corners of the app. Most flows already surface diagnostics, and the heavier paths show profiling data, but a few very new commit-timeline anomaly paths may still be under-instrumented, so some niche failures there might not explain themselves properly yet. macOS is planned, but shipping it properly means dealing with the Apple developer license and signing/notarization ritual. I know. Extremely glamorous. Windows and Linux are more forgiving of lazily signed software, so they come first.',
    ],
  ),
];
