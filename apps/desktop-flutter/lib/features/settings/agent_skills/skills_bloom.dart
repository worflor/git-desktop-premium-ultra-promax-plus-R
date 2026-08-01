// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:git_desktop/ui/control_chrome.dart';
import 'package:git_desktop/ui/design_primitives.dart';
import 'package:git_desktop/ui/material_surface.dart';
import 'package:git_desktop/i18n/gen/strings.g.dart';
import 'package:git_desktop/ui/mosaic_seam.dart';
import 'package:git_desktop/ui/tokens.dart';

import 'skill_catalog.dart';

/// The localized one-line question for a skill, keyed by its stable id.
String _questionFor(BuildContext context, AgentSkill skill) {
  final q = context.t.agentSkills.question;
  switch (skill.id) {
    case 'overview':
      return q.overview;
    case 'code-review':
      return q.codeReview;
    case 'muse':
      return q.muse;
    case 'bug-shaker':
      return q.bugShaker;
    case 'repo-intel':
      return q.repoIntel;
    default:
      return skill.question;
  }
}

/// Visuals for the Settings "agent skills" affordance: a square glass toggle
/// that morphs a plus into an X, and a glass slab that blooms the skill list
/// above it. Both are pure functions of a `reveal` value (0 collapsed, 1 open),
/// so the host owns a single AnimationController and the render harness can pump
/// any frame. Everything sources color / radius / surface / shadow from the
/// theme engine — no local constants.

const double kSkillsPanelWidth = 340;

/// Inline size for the toggle: it lives in a settings section header next to a
/// 12px subtitle, so it matches that row's weight rather than a page-scale FAB.
const double kSkillsToggleSize = 30;

/// How far the toggle protrudes above the panel's top edge when open. The rest
/// of it reaches down into the slab, fusing the two into one piece.
const double kSkillsToggleStickOut = 15;

/// Deterministic cracks for the row seams: generated from a fixed seed per
/// divider so they stay stable across the many rebuilds a running animation
/// causes (a fresh RNG each build would make the cracks shimmer). Mirrors the
/// [generateMosaicSeam] contract used by the split-pill and context menu.
List<MosaicSeam> _dividerSeams(int count) => [
      for (var i = 0; i < count; i++) generateMosaicSeam(math.Random(0x5C111 + i)),
    ];

/// The open affordance: the bloom slab with the square toggle fused into its
/// bottom-right corner, so the panel reads as growing out of the button rather
/// than floating above a detached one. The host positions this so the toggle
/// sits exactly where the collapsed button was.
class SkillsBloomOverlay extends StatelessWidget {
  final double reveal;
  final List<AgentSkill> skills;
  final void Function(AgentSkill) onCopy;
  final void Function(AgentSkill) onSave;
  final VoidCallback onToggle;

  const SkillsBloomOverlay({
    super.key,
    required this.reveal,
    required this.skills,
    required this.onCopy,
    required this.onSave,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Anchored inline in a section header, so the slab hangs BELOW the toggle.
    // The toggle sits at the stack's top-right: it protrudes [stickOut] above
    // the panel's top edge and reaches [interior] down into it, fusing the two.
    // The panel takes [interior] of top clearance so no row sits behind it.
    const stickOut = kSkillsToggleStickOut;
    const interior = kSkillsToggleSize - stickOut;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topRight,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: stickOut),
          child: SkillsBloomPanel(
            reveal: reveal,
            skills: skills,
            onCopy: onCopy,
            onSave: onSave,
            topInset: interior,
          ),
        ),
        Positioned(
          right: 10,
          top: 0,
          child: SkillsToggleButton(reveal: reveal, onTap: onToggle),
        ),
      ],
    );
  }
}

/// The bloom slab: a glass panel carrying a header and one row per skill, each
/// row separated from the next by a shattered-mosaic crack so the list reads as
/// one fused surface rather than stacked chips.
class SkillsBloomPanel extends StatelessWidget {
  final double reveal;
  final List<AgentSkill> skills;
  final void Function(AgentSkill) onCopy;
  final void Function(AgentSkill) onSave;

  /// Extra top padding so the fused corner toggle never overlaps a row.
  final double topInset;

  const SkillsBloomPanel({
    super.key,
    required this.reveal,
    required this.skills,
    required this.onCopy,
    required this.onSave,
    this.topInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final geo = context.surfaceShader.geometry;
    final seams = _dividerSeams(skills.length);

    final rows = <Widget>[];
    for (var i = 0; i < skills.length; i++) {
      final rt = _rowReveal(i, skills.length, reveal);
      final ease = Curves.easeOut.transform(rt);
      final back = Curves.easeOutBack.transform(rt);
      rows.add(Opacity(
        opacity: ease,
        child: Transform.translate(
          // Rows unfurl downward out of the toggle, so they arrive from
          // slightly above and settle into place.
          offset: Offset(0, (back - 1) * 12),
          child: Transform.scale(
            scale: 0.97 + 0.03 * back,
            alignment: Alignment.topRight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i > 0)
                  SizedBox(
                    height: 11,
                    child: CustomPaint(
                      size: const Size(double.infinity, 11),
                      painter: _RowSeamPainter(
                        seam: seams[i],
                        color: t.chromeBorder.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                _SkillRow(
                  skill: skills[i],
                  onCopy: () => onCopy(skills[i]),
                  onSave: () => onSave(skills[i]),
                ),
              ],
            ),
          ),
        ),
      ));
    }

    // The whole slab grows and fades in from the toggle corner (top-right),
    // ahead of the row stagger, so it reads as blooming out of the button
    // rather than popping in fully-formed. `safeCurve` keeps the growth free of
    // the overshoot that would clip the glass edge on elastic themes.
    final appear = context.surfaceShader.safeCurve
        .transform((reveal * 1.5).clamp(0.0, 1.0));
    return Opacity(
      opacity: appear,
      child: Transform.scale(
        scale: 0.9 + 0.1 * appear,
        alignment: Alignment.topRight,
        child: SizedBox(
          width: kSkillsPanelWidth,
          child: MaterialSurface(
            tone: AppMaterialTone.panelStrong,
            elevated: true,
            innerHighlight: true,
            radius: geo.cardRadius,
            padding: EdgeInsets.fromLTRB(12, 11 + topInset, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(reveal: reveal),
                const SizedBox(height: AppSpacing.xs),
                _Blurb(reveal: reveal),
                const SizedBox(height: AppSpacing.sm6),
                ...rows,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Staggered per-row progress: earlier rows lead, all land by `reveal == 1`.
  static double _rowReveal(int i, int n, double reveal) {
    const step = 0.12;
    final start = step * i;
    final span = 1.0 - step * (n - 1);
    return ((reveal - start) / (span <= 0 ? 1 : span)).clamp(0.0, 1.0);
  }
}

class _Header extends StatelessWidget {
  final double reveal;
  const _Header({required this.reveal});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: Curves.easeOut.transform((reveal * 2).clamp(0.0, 1.0)),
      child: Row(
        children: [
          Container(
            width: AppBorderWidth.thick,
            height: 13,
            decoration: BoxDecoration(
              color: t.accentBright,
              borderRadius: AppRadii.xxsAll,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            context.t.agentSkills.heading.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: t.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// One line saying what this panel IS. The skill titles below answer "which";
/// nothing else answers "why an agent would want them", and a list of five
/// documents with no framing is a menu with no menu header.
class _Blurb extends StatelessWidget {
  final double reveal;
  const _Blurb({required this.reveal});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: Curves.easeOut.transform((reveal * 1.8).clamp(0.0, 1.0)),
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm10),
        child: Text(
          context.t.agentSkills.blurb,
          style: TextStyle(fontSize: 11, height: 1.35, color: t.textMuted),
        ),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  final AgentSkill skill;
  final VoidCallback onCopy;
  final VoidCallback onSave;

  const _SkillRow({
    required this.skill,
    required this.onCopy,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(skill.glyph, size: AppIconSize.lg, color: t.accentBright),
          const SizedBox(width: AppSpacing.sm10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.textStrong,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _questionFor(context, skill),
                  style: TextStyle(fontSize: 11, color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _ActionIcon(icon: Icons.copy_all_outlined, onTap: onCopy),
          const SizedBox(width: AppSpacing.xs),
          _ActionIcon(icon: Icons.save_alt_outlined, onTap: onSave),
          const SizedBox(width: AppSpacing.xs),
          // Eventual "install to client / provider" slot: present so the shape
          // is built to grow into it, disabled until the wiring lands.
          _ActionIcon(
            icon: Icons.add_link_outlined,
            onTap: null,
            tooltip: context.t.agentSkills.installSoon,
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const _ActionIcon({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final geo = context.surfaceShader.geometry;
    final enabled = onTap != null;
    final button = ChromeButton(
      onTap: onTap,
      enabled: enabled,
      chromeBuilder: ({required hovered, required pressed}) => ghostButtonChrome(
        t,
        hovered: hovered,
        pressed: pressed,
        enabled: enabled,
        // Quiet at rest (no boxed border), chrome only on hover.
        baseBorderColor: Colors.transparent,
      ),
      padding: const EdgeInsets.all(6),
      borderRadius: BorderRadius.circular(geo.badgeRadius.clamp(4, 10).toDouble()),
      child: Icon(
        icon,
        size: AppIconSize.md,
        color: enabled ? t.textMuted : t.textFaint,
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// The square glass toggle. Its glyph is a plus that rotates into an X as
/// `reveal` runs 0 -> 1.
class SkillsToggleButton extends StatefulWidget {
  final double reveal;
  final VoidCallback onTap;
  final double size;

  const SkillsToggleButton({
    super.key,
    required this.reveal,
    required this.onTap,
    this.size = kSkillsToggleSize,
  });

  @override
  State<SkillsToggleButton> createState() => _SkillsToggleButtonState();
}

class _SkillsToggleButtonState extends State<SkillsToggleButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final geo = context.surfaceShader.geometry;
    // Accent glyph at rest and open: it reads as an affordance (not a generic
    // "add"), stays visible on pale themes where a dark plus would vanish, and
    // matches the accent glyphs inside the opened panel.
    final glyph = t.accentBright;
    // The label carries the meaning; the mark alone cannot. "Agent skills" is
    // not a concept a 15px glyph conveys, and in a GIT client a branching mark
    // reads as branch/merge before it reads as capability. It collapses away as
    // the panel opens, since the panel's own header then says it.
    final labelFactor = (1 - widget.reveal * 1.6).clamp(0.0, 1.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: Transform.scale(
          scale: _pressed ? 0.94 : (_hovered ? 1.04 : 1.0),
          child: SizedBox(
            height: widget.size,
            child: MaterialSurface(
              tone: AppMaterialTone.panelStrong,
              elevated: true,
              innerHighlight: true,
              radius: geo.cardRadius,
              borderColor: _hovered ? t.inputFocusBorder : null,
              padding: EdgeInsets.symmetric(
                horizontal: (widget.size - widget.size * 0.52) / 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: Size(widget.size * 0.58, widget.size * 0.58),
                    painter: _SkillSprigPainter(
                      reveal: widget.reveal,
                      color: glyph,
                      strokeWidth: AppBorderWidth.medium,
                    ),
                  ),
                  if (labelFactor > 0.01)
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: labelFactor,
                        child: Opacity(
                          // Fades faster than it clips, so the collapse never
                          // parks on a solid half-word.
                          opacity: labelFactor * labelFactor,
                          child: Padding(
                            padding: const EdgeInsets.only(left: AppSpacing.sm6),
                            child: Text(
                              context.t.agentSkills.heading,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: t.textNormal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The agent-skills mark: a tesseract with a lit core, resolving into an X.
///
/// A hypercube's flat projection — a square inside a square, corners joined —
/// which is the geometry this app is named for, and abstract enough to be a
/// MARK rather than a stock symbol. The inner square is filled, so the struts
/// read as rays leaving a lit core: the shimmer is built into the structure
/// instead of stuck on as a star. Two earlier attempts were discarded on
/// sight: anything forked reads as "merge" in a git client, and a literal
/// sparkle is the most over-used glyph in software.
///
/// The morph is structural, not a cross-fade. A tesseract's corner struts ARE
/// diagonals, so opening simply pulls them inward to the centre — where they
/// become the X — while the two squares fade. One geometry, two states.
class _SkillSprigPainter extends CustomPainter {
  final double reveal;
  final Color color;
  final double strokeWidth;

  _SkillSprigPainter({
    required this.reveal,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.5;
    // Half-side of the outer cell. Chosen so its corners are exactly where the
    // X's arms end: the two states share one set of extremes.
    final outer = r * 0.78;
    final inner = outer * 0.34;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    // Closed, the cell stands on its corner: a diamond with axial spokes,
    // which is a MARK. Left square it would already read as an X in a box —
    // the open state, showing early. Unrotating is what turns it into the X.
    canvas.rotate((1 - reveal) * math.pi / 4);

    // The cells fade ahead of the X so the mark never reads as a busy overlap
    // mid-morph.
    final cells = (1 - reveal * 1.6).clamp(0.0, 1.0);
    if (cells > 0.02) {
      final line = Paint()
        ..color = color.withValues(alpha: cells)
        ..strokeWidth = strokeWidth * 0.8
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawRect(
          Rect.fromCircle(center: Offset.zero, radius: outer), line);
      // The lit core: filled, so the struts leaving it read as rays rather
      // than as mere edges of a wireframe.
      canvas.drawRect(
        Rect.fromCircle(center: Offset.zero, radius: inner),
        Paint()
          ..color = color.withValues(alpha: cells)
          ..style = PaintingStyle.fill,
      );
    }

    // The struts: inner corner to outer corner when closed, pulled all the way
    // to the centre when open, at which point they ARE the X.
    final start = inner * (1 - reveal);
    final strut = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final s in const [
      Offset(1, 1),
      Offset(1, -1),
      Offset(-1, 1),
      Offset(-1, -1),
    ]) {
      canvas.drawLine(
        Offset(start * s.dx, start * s.dy),
        Offset(outer * s.dx, outer * s.dy),
        strut,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkillSprigPainter old) =>
      old.reveal != reveal ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// One horizontal shattered-mosaic crack, drawn across a row boundary. Reuses
/// the [MosaicSeam] vertex model axis-swapped: the seam's sorted y becomes the
/// left-to-right run, its dx jitter becomes the small vertical wander.
class _RowSeamPainter extends CustomPainter {
  final MosaicSeam seam;
  final Color color;

  _RowSeamPainter({required this.seam, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final jitter = size.height * 0.42;
    final pts = <Offset>[
      for (final v in seam.vertices)
        Offset(v.dy * size.width, midY + v.dx * jitter),
    ];
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var k = 0; k < pts.length - 1; k++) {
      paint.strokeWidth =
          AppBorderWidth.thin * seam.widthScale * seam.segmentWidthScales[k];
      canvas.drawLine(pts[k], pts[k + 1], paint);
    }
  }

  @override
  bool shouldRepaint(_RowSeamPainter old) =>
      !identical(old.seam, seam) || old.color != color;
}
