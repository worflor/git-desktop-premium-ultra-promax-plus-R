// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// The timeline's marker-band contract: the band is an EVENT index. Only
// commit-anchored findings earn a tick — position and trend findings anchor
// to the head as a jump target, not a moment, and a tick would assert "this
// happened here" (the false claim the rail's active-state semantics guard
// against). These laws pin the derivation the band is built from.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/orrery/orrery_findings.dart';
import 'package:git_desktop/features/orrery/orrery_model.dart';
import 'package:git_desktop/features/orrery/orrery_page.dart';
import 'package:git_desktop/features/orrery/orrery_timeline.dart';
import 'package:git_desktop/ui/tokens.dart';

import 'orrery_test_harness.dart';

OrreryFinding _f(OrreryFindingKind kind, int step, String anchor,
        {int? nodeId}) =>
    OrreryFinding(
      kind: kind,
      stepIndex: step,
      headline: 'x',
      anchor: anchor,
      nodeId: nodeId,
    );

void main() {
  test('only commit-anchored findings earn a marker', () {
    final findings = [
      _f(OrreryFindingKind.hub, 25, 'core', nodeId: 3),
      _f(OrreryFindingKind.regime, 13, '13 · a1b2c3d'),
      _f(OrreryFindingKind.driftOut, 25, 'drift', nodeId: 4),
      _f(OrreryFindingKind.reshuffle, 7, '7 · 9f9f9f9'),
      _f(OrreryFindingKind.forecast, 25, 'trend'),
      _f(OrreryFindingKind.thrash, 25, 'thrash', nodeId: 5),
    ];
    final markers = timelineEventMarkers(findings);
    expect(markers.map((m) => m.finding).toList(), [1, 3]);
  });

  test('marker indices point into the shared findings list', () {
    final findings = [
      _f(OrreryFindingKind.hub, 25, 'core', nodeId: 3),
      _f(OrreryFindingKind.regime, 13, '13 · a1b2c3d'),
    ];
    final markers = timelineEventMarkers(findings);
    expect(markers.single.finding, 1);
    expect(findings[markers.single.finding].kind, OrreryFindingKind.regime);
  });

  test('co-located events fan symmetrically; lone events sit centred', () {
    final findings = [
      _f(OrreryFindingKind.regime, 13, '13 · aaaaaaa'),
      _f(OrreryFindingKind.reshuffle, 13, '13 · aaaaaaa'),
      _f(OrreryFindingKind.regime, 20, '20 · bbbbbbb'),
    ];
    final markers = timelineEventMarkers(findings, pitch: 5.0);
    final at13 = markers.where((m) => m.finding != 2).toList();
    expect(at13.map((m) => m.fan).toList(), [-2.5, 2.5]);
    expect(markers.firstWhere((m) => m.finding == 2).fan, 0);
  });

  test('no events, no markers', () {
    final findings = [
      _f(OrreryFindingKind.hub, 25, 'core', nodeId: 3),
      _f(OrreryFindingKind.tangle, 25, 'trend'),
    ];
    expect(timelineEventMarkers(findings), isEmpty);
  });

  // The index-space seam the pure-function tests can't see: a band tap must
  // report the finding's index in the SHARED findings list, not its position
  // in the marker list. The fixture makes the two diverge — computeFindings
  // orders the hub first, so the lone regime event is markers[0] but
  // findings[1]. A swapped index would select the hub (jump to head + pin);
  // the correct one scrubs to the regime commit with nothing pinned.
  testWidgets('tapping a band marker selects by findings-index', (t) async {
    const int steps = 7;
    const int regimeAt = 3;
    final model = OrreryModel(
      steps: <OrreryStep>[
        for (int s = 0; s < steps; s++)
          OrreryStep(
            revision: s,
            sha: 'sha$s',
            date: DateTime.utc(2026, 1, 1 + s),
            gap: 0.5,
            rigidity: 0.5,
            vonNeumann: 1.0,
            archetype: 'modular',
            canonicality: 0.5,
            regimeChange: s == regimeAt,
          ),
      ],
      nodes: <OrreryNode>[
        // Still files, one central: yields exactly a hub finding + the regime
        // event, and no drift/thrash noise.
        OrreryNode(
          id: 0,
          path: 'lib/core.dart',
          churn: 0.5,
          positions: List<Offset?>.filled(steps, const Offset(0.1, 0)),
        ),
        OrreryNode(
          id: 1,
          path: 'lib/leaf.dart',
          churn: 0.5,
          positions: List<Offset?>.filled(steps, const Offset(0.6, 0)),
        ),
      ],
    );

    t.view.physicalSize = const Size(1280, 860);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(orreryTestApp(
      theme: AppThemeId.aether,
      home: Scaffold(body: OrreryView(model: model)),
    ));
    await t.pumpAndSettle();

    final laneRect = t.getRect(find.descendant(
      of: find.byType(OrreryTimeline),
      matching: find.byType(CustomPaint),
    ));
    final tapX = laneRect.left + regimeAt / (steps - 1) * laneRect.width;
    await t.tapAt(Offset(tapX, laneRect.top + 7));
    await t.pumpAndSettle();

    // Scrubbed to the regime commit, nothing pinned.
    expect(find.text('${regimeAt + 1} / $steps', findRichText: true),
        findsOneWidget);
    expect(find.text('SELECTED'), findsNothing);
  });
}
