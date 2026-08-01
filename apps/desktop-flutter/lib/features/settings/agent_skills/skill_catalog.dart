// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One agent-skill document the Settings skills panel can surface, copy, and
/// save. Content lives as a bundled markdown asset (see `assets/skills/`, which
/// mirrors `docs/agentic-skills/`); this record is just the display metadata
/// plus the asset key. Loading the text is deferred to [loadMarkdown] so the
/// panel opens instantly and only reads the file when a skill is acted on.
@immutable
class AgentSkill {
  /// Stable id, used for keys and (eventually) the install-to-client wiring.
  final String id;

  /// Short display name, e.g. "Code review".
  final String title;

  /// The one-line question the skill answers, e.g. "Is this change right?".
  final String question;

  /// Leading glyph. A Material icon so it inherits theme color like any other.
  final IconData glyph;

  /// Bundled asset path, and the default file name on save (its basename).
  final String asset;

  const AgentSkill({
    required this.id,
    required this.title,
    required this.question,
    required this.glyph,
    required this.asset,
  });

  /// The basename used as the default "save as" file name.
  String get fileName => asset.split('/').last;

  /// Reads the skill's markdown from the bundle.
  Future<String> loadMarkdown() => rootBundle.loadString(asset);
}

/// The shipped skill set. Order is the display order in the bloom: the overview
/// first as the entry point, then the four skills. Kept in sync with
/// `docs/agentic-skills/` and the `assets/skills/` bundle.
const List<AgentSkill> kAgentSkills = [
  AgentSkill(
    id: 'overview',
    title: 'Overview',
    question: 'How the skills fit together',
    glyph: Icons.auto_awesome_mosaic_outlined,
    asset: 'assets/skills/agentic-skills.md',
  ),
  AgentSkill(
    id: 'code-review',
    title: 'Code review',
    question: 'Is this change right?',
    glyph: Icons.rate_review_outlined,
    asset: 'assets/skills/manifold-code-review.md',
  ),
  AgentSkill(
    id: 'muse',
    title: 'Muse',
    question: 'What could this change become?',
    glyph: Icons.lightbulb_outline,
    asset: 'assets/skills/manifold-muse.md',
  ),
  AgentSkill(
    id: 'bug-shaker',
    title: 'Bug shaker',
    question: 'What is wrong with settled code?',
    glyph: Icons.pest_control_outlined,
    asset: 'assets/skills/manifold-bug-shaker.md',
  ),
  AgentSkill(
    id: 'repo-intel',
    title: 'Repo intel',
    question: 'What does this file connect to?',
    glyph: Icons.hub_outlined,
    asset: 'assets/skills/manifold-repo-intel.md',
  ),
];
