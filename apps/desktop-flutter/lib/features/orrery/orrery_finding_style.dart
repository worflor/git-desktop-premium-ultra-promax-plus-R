import 'package:flutter/material.dart';

import '../../ui/tokens.dart';
import 'orrery_findings.dart';

/// The one visual identity for each finding kind — glyph, accent, and label —
/// shared by every surface that renders findings (the rail ledger and the
/// timeline's event markers), so a kind reads the same everywhere.
Color findingAccent(AppTokens t, OrreryFindingKind kind) => switch (kind) {
      OrreryFindingKind.hub => t.accentBright,
      OrreryFindingKind.driftOut => t.stateModified,
      OrreryFindingKind.driftIn => t.stateAdded,
      OrreryFindingKind.tangle => t.stateModified,
      OrreryFindingKind.clarify => t.stateAdded,
      OrreryFindingKind.regime => t.accentBright,
      OrreryFindingKind.thrash => t.stateModified,
      OrreryFindingKind.reshuffle => t.accentBright,
      OrreryFindingKind.forecast => t.stateModified,
    };

IconData findingIcon(OrreryFindingKind kind) => switch (kind) {
      OrreryFindingKind.hub => Icons.adjust_rounded,
      OrreryFindingKind.driftOut => Icons.call_made_rounded,
      OrreryFindingKind.driftIn => Icons.call_received_rounded,
      OrreryFindingKind.tangle => Icons.warning_amber_rounded,
      OrreryFindingKind.clarify => Icons.auto_awesome_rounded,
      OrreryFindingKind.regime => Icons.bolt_rounded,
      OrreryFindingKind.thrash => Icons.sync_problem_rounded,
      OrreryFindingKind.reshuffle => Icons.shuffle_rounded,
      OrreryFindingKind.forecast => Icons.trending_down_rounded,
    };

String findingLabel(OrreryFindingKind kind) => switch (kind) {
      OrreryFindingKind.hub => 'HUB',
      OrreryFindingKind.driftOut => 'DRIFTING OUT',
      OrreryFindingKind.driftIn => 'DRIFTING IN',
      OrreryFindingKind.tangle => 'TANGLING',
      OrreryFindingKind.clarify => 'CLARIFYING',
      OrreryFindingKind.regime => 'REORG',
      OrreryFindingKind.thrash => 'THRASHING',
      OrreryFindingKind.reshuffle => 'RESHUFFLE',
      OrreryFindingKind.forecast => 'FORECAST',
    };
