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
        'I already knew it felt slow. Then I caught a streamer saying the '
        'same thing on a stream I don\'t usually watch, and that was the '
        'nudge to finally swap. He didn\'t suggest Flutter; far from it. I '
        'found Dart on my own, threw together a prototype, and startup went '
        'from about 15 seconds to under a second. Night and day. '
        'Farewell Tauri era.\n\n'
        'Flutter\'s rendering pipeline is closer to a game engine than a '
        'DOM, and for a desktop app where the UI is the product that\'s '
        'everything. Dart turned out to be a genuinely good language too. '
        'The math behind the spectral engine was prototyped in Rust first, '
        'so that work carried over fine.\n\n'
        'Flutter is cross-platform by default, which is great, but it\'s '
        'Googley in nature so there are a few quirks.',
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
        'down, not the other way around.',  ),
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
    version: 'v0.1.6',
    date: '2026-07-08',
    bullets: [
      'Staging a file that lives under an unstaged directory no longer gets left behind at commit. This is the real reason 0.1.6 exists. And since it had to ship early, the features below are early-access cooking, served a little raw.',
      'The history DAG can expand into a worldline view now, your whole history stretched out along one thread.',
      'The branches and PR page got its first real love since launch: a full backend overhaul of how branches are processed and understood, so absorbed vs squashed vs merged finally get told apart. And the page itself looks far better for it.',
      'API models (OpenRouter, OpenAI, xAI) can piggyback the Codex CLI now for full read-only agentic capability. Basically codex, but with your API models slotted in automatically.',
      'One new equation entered the chat: a participation ratio for diffs, N_eff = (Σφ)² / Σφ². the engine keeps eating math.',
      'The test suite got a serious upgrade. it asserts laws and invariants, and fuzzes them until something gives. Plus a WSL2 harness.',
      'Sooo it found a lot of bugs... aaand they\'re all fixed ;p',
    ],
  ),
  _ReleaseNote(
    version: 'v0.1.5',
    date: '2026-07-04',
    bullets: [
      'happy late Canada Day!',
      'Staging by line no longer silently merges into the greater file when commiting... kind of like it shouldn\'t have from the start.',
      'Check (now exists) and got platonically entangled with Sync. When you have local commits waiting to push, the two sit side by side as separate one-tap options instead of one button pulling double duty.',
      'History DAG got minor improvements.',
      'wait. undo that, it\'s actually a major overhaul. (undo got upgraded too)',
      'Most to, if not all destructive git operations can also be undone now and use the same undo stack.',
      'Changes page now tells you who you\'re committing as in each repo. And if it\'s a new or different identity, it\'ll tell you. Based on the repos included in Manifold.',
      'Cursor CLI is fully integrated now.',
      'Dropped the old Google CLI for Antigravity, and its off by default. It\'s headless mode requires a sign in through a window first, a bold interpretation of the word "Headless", so it\'s off until Google fixes their known bug.',
      'GitHub Copilot\'s CLI is wired in too, though it\'s also mostly vibe slop. And due to enegineering outside of my own, its disabled by default.',
      'As a remedy, Opencode integration got upgraded. But it also lies about what Github Copilot models it serves so we literally can\'t have nice things.',
      'The review verdict looks cooler now. No deeper meaning beyond, "fable make it pretty," and a few (too many) back and fourths.',
      'More under-the-hood math work. The engine keeps getting quietly sharper.',
      'Another theme pass. A pile of hardcoded corners around the app finally route through the theme engine.',
    ],
  ),
  _ReleaseNote(
    version: 'v0.1.4',
    date: '2026-06-30',
    bullets: [
      'Orrery lands in preview. Scrub the repo\'s full history and watch its structure drift, files orbiting in a Poincaré disk. Early, like Atlas, but the shape is already there.',
      'X-Ray\'s Time view runs on the same structural trajectory as Orrery now. The old aperture sweep is retired, so the two views share one backend.',
      'Conflict handling is now one unified system. pull, sync, branch merge, anywhere a conflict can happen routes through the same resolver. thank u, next.',
      'Logos evidence gathering got its first real relevance pass. It respects neighbourhood relevance now: more signal, less noise. Every LLM feature built on it (review, Muse, commit messages) works from sharper context.',
      'Code review lost its confirm button. You tune by dismissing now; the yes was implied anyway.',
      'Big refreshes should lag far less. The heavy recompute behind those freezes moved off the hot path, with a heap of redundant compute and duplicate git I/O cleared out underneath. Zero lag is the dream and it\'s being monitored to get there. So far it\'s held up against "working trees" averaging 20k LoC changed in active repos (don\'t ask).',
    ],
  ),
  _ReleaseNote(
    version: 'v0.1.3',
    date: '2026-06-21',
    bullets: [
      'Review grew two new senses. Blast radius surfaces the files that usually move with a change but sat this one out. Shadow history flags paths git has reverted, reset, or walked away from before.',
      'Review learns your repo now. Every confirm and dismiss tunes the scorer, so it sharpens the longer you live somewhere.',
      'Two things that stick now: your Muse strand order, and commit mode per repo.',
      'Relatedness got richer. The old symbol-frequency index is gone; spectral coupling does the job everywhere now.',
      'Filament\'s walkers went quantum. YAA* now carries a density matrix per walker, Born-mixed across its anomaly, structure, and certainty strategies.',
      'Snappier review and changes views. The spectral matrix and engine overlays stopped rebuilding on every widget pass.',
      'Mostly an engine-room stretch: piles of low-level tests and bug fixes galore. Some of the math is still placeholder while the real version settles in, but everything runs clean.',
    ],
  ),
  _ReleaseNote(
    version: 'v0.1.2',
    date: '2026-05-24',
    bullets: [
      'Filament got Yassified: the math underneath got a Logos-flavored facelift and the search core ditched DFS for YAA*, a walker-based attention search over the double-helix strands. Properly re-overengineered.',
      'Added tabs for diffs.',
      'Binary files are diffable now. Images, video, and audio render side by side, sorted out by magic bytes, with per-type toggles for what you want shown.',
      'Clone dialog, tag management, PR toolbar, and file coupling all got polish passes.',
    ],
  ),
  _ReleaseNote(
    version: 'v0.1.1',
    date: '2026-05-18',
    bullets: [
      'First build to leave the lab.',
      'Filament, an experimental execution-flow engine, makes its debut.',
      'Wick.exe alpha lands in the command palette: real-time semantic search, if you have the binary.',
      'Inline interactive commit reorder.',
      'Spent an afternoon designing how Manifold should present a 3-way merge and settled on a unified fullscreen per-file view. Logos assists, but it is designed for The Manual Way™.',
      'Command palette got smarter mostly by getting smaller. Some options removed, some merged. Fewer ways to ask for the same thing badly.',
      'OpenRouter API support.',
      'Ask got reworked into more of a debug tool.',
      'Settings got shorter to scroll, and the scrollbar grew a little breadcrumb bubble that follows along so you always know where you are.',
      'Essays written in the commit field now pop an expanded composer. Yap unbothered.',
      'glass.frag got another material pass: gloopier, thiccer, and globier.',
      'Tweaked Loverboy\'s background algorithm. I still can\'t tell if it\'s ugly good or ugly ugly; the line between "oh!" and "oh..." is thin.',
      'Petrichor keeps its rainy feel, now with shaders and more vibes.',
      'New Lady Entropy theme: bot-eye freeze tag, per-surface tint variation, and a dataScrawl text effect.',
      'Theme, motion, reduced-motion, and accessibility all got system-wide passes.',
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
      'A spectral analysis engine runs underneath the app. In plain terms: it turns your repo history into a weighted map of which files tend to matter together, then runs the current diff through that map. The useful part is the receipts: when Logos surfaces a related file, it can point at the exact signal that pulled it in, whether co-change, path structure, source->test transport lanes, integrity gates, residual surprise, or shadow history. Practically, that means better review context, better commit grouping, better Muse suggestions, and UI that reacts to the actual shape of the change instead of just the file list.',
      'Logos has counterfactual memory too. Reverts, reset-away commits, and abandoned branches are mined into a discounted shadow-coupling graph, so discarded timelines can corroborate real co-change signals or flag a current diff as deja-vu.',
      'The interactive starfield during commit review and Muse is a live readout of that process: files, evidence, and diffusion energy moving around while the engine decides what matters.',
      'History renders each commit as a drillable seismograph. The painted bar under each subject encodes importance, add/del ratio, coherence, and working-tree overlap without labels.',
      'Commit review gives you grounded observations with four guardrail stages: Loose, Balanced, Strict, and Paranoid.',
      'Muse is a three-phase pipeline (diverge, reshape, synthesize) that brainstorms around what your staged changes could lead to. Results come back in four tiers: Spark, Current, Horizon, and Fever. You can drag file spokes while it runs to steer where it looks.',
      'Atlas, the File Constellation beta, groups staged files by correlatedness into candidate commits. Still early but the direction is there.',
      'Repo X-Ray gives a structural snapshot across map, time, signals, and summary views.',
      'Known rough edges: CPU on Windows runs hotter than it should, so if your fans spin up, that\'s me. The Linux AppImage ships but is untested this build. A few newer corners still have minor visual bugs. macOS is planned, but shipping it properly means the Apple developer license and the signing/notarization ritual. I know. Extremely glamorous. Windows and Linux are more forgiving of lazily signed software, so they come first.',
    ],
  ),
];
