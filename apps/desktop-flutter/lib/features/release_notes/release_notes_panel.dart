import 'package:flutter/material.dart';

import '../../app/build_info.dart';
import '../../ui/design_primitives.dart';
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
  const _ReleaseEntry({required this.entry, required this.tokens});

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
                  child: Text(
                    bullet,
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 12,
                      height: 1.5,
                    ),
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
  const _AboutBlock({required this.entry, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.question,
          style: TextStyle(
            color: t.textNormal,
            fontSize: 11,
            fontFamily: AppFonts.mono,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          entry.body,
          style: TextStyle(
            color: t.textMuted,
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ],
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
        'thing on a live stream I don\'t usually watch, and that was '
        'finally enough to swap. He didn\'t suggest Flutter. I found Dart '
        'on my own, threw together a prototype, and it went from about '
        '15 seconds to under a second. Night and day. That was the end '
        'of the Tauri era.\n\n'
        'Flutter\'s rendering pipeline is closer to a game engine than a '
        'DOM, and for a desktop app where the UI is the product that\'s '
        'everything. Dart turned out to be a genuinely good language too. '
        'The math behind the spectral engine was prototyped in Rust first, '
        'so that work carried over.\n\n'
        'Flutter is cross-platform by default, which is great, but it\'s '
        'Googley in nature so there are quirks. I don\'t care about platform '
        'nativeness though. I\'ll work around whatever needs working around.',
  ),
  _AboutEntry(
    question: 'WHAT IS THE SPECTRAL ENGINE?',
    body: 'Every time you commit, the files you change together form '
        'patterns over time. The spectral engine reads your commit graph '
        'and decomposes those co-change patterns into signals: which files '
        'are coupled, how tightly, and what structural role they play in '
        'the repo. Basically spectral analysis on your development '
        'history. In a git client. On purpose.\n\n'
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
        'speed, feel, intelligence, and UX. There\'s more in the pipeline '
        'than what\'s announced here.',
  ),
];

const _changelog = <_ReleaseNote>[
  _ReleaseNote(
    version: 'v0.1.0',
    date: '2026-05-07',
    bullets: [
      'Built from scratch in Flutter over about five weeks. The whole git surface is here: staging, branches, history, stash, blame, file history, parallel worktrees, and sync.',
      'PRs and issues work locally by default, stored as orphan git refs in the repo itself. No remote needed. When you do have a remote, they sync bidirectionally with GitHub, GitLab, or Gitea.',
      'Patches are a first-class workflow. Import from file or clipboard, preview with conflict detection, apply with 3-way merge fallback or reverse. For when you\'re not down to big git.',
      'A spectral analysis engine runs on your commit graph underneath all of this. It picks up file coupling, coherence, and structural patterns, and those signals drive the intelligent features and the general UI alike.',
      'The interactive starfield you see during commit review and Muse is a live view of the engine working. It shows what the spectral analysis is doing while it processes your changes.',
      'History renders each commit as a drillable seismograph. The painted bar under each subject encodes importance, add/del ratio, coherence, and working-tree overlap without labels.',
      'Muse is a three-phase pipeline (diverge, reshape, synthesize) that brainstorms around what your staged changes could lead to. Results come back in four tiers: Spark, Current, Horizon, and Fever. You can drag file spokes while it runs to steer where it looks.',
      'Commit review gives you grounded observations with four guardrail stages: Loose, Balanced, Strict, and Paranoid.',
      'File Constellation (beta) groups staged files by correlatedness into candidate commits. Still early but the direction is there.',
      'Repo X-Ray gives a structural snapshot across map, time, signals, and summary views.',
      'Command palette handles navigation, git commands, branch operations, stash actions, settings toggles, and search across repos, branches, commits, tags, and changed files.',
      'Known issue: CPU usage on Windows runs hotter than expected. If your fans spin up, that\'s me. Linux AppImage ships but is untested as of this build.',
    ],
  ),
];
