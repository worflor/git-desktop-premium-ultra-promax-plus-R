import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_identity.dart';
import '../../../app/theme_state.dart';
import '../../../ui/design_primitives.dart';
import '../../../ui/material_surface.dart';
import '../../../ui/motion.dart';
import '../../../ui/tokens.dart';
import '../onboarding_flow.dart';
import '../onboarding_state.dart';
import '../widgets/workspace_preview.dart';

//
// The picker pins these so that switching themes never reflows the list.
// Without pinning, each theme's typography (fontFamily + fontScale +
// letterSpacingEm) would remeasure every row on hover; row heights and
// widths would shift; and a user scrolled near the bottom would get
// tossed back to the top just by clicking.
//
// The text itself still uses the theme's typography (the picker should
// LOOK like each theme) — we just reserve enough space for the worst
// case so no row can reflow.

const double _kThemeLabelFontSize = 12;
const double _kThemeRowHeight = 34;
const double _kThemeRadioWidth = 12;
const double _kThemeRadioGap = 8;
const double _kThemePreviewSlotWidth = 58; // 'preview' badge at worst
const double _kThemeRowHorizontalPadding = 8;
const double _kThemePickerOuterPadding = 14;
/// Per-side overhead that isn't the row's content:
///   • 1px row border (Border.all(width: 1) subtracts from child area)
///   • scrollbar reserve (Flutter's desktop scrollbar is 4px, bump to 6
///     so a hairline doesn't poke into the "preview" slot when the list
///     is tall enough to scroll)
const double _kThemeRowBorderAllowance = 2; // left + right
const double _kThemeScrollbarAllowance = 6;
const double _kThemePickerInnerExtras = _kThemeRadioWidth +
    _kThemeRadioGap +
    _kThemePreviewSlotWidth +
    _kThemeRowHorizontalPadding * 2 +
    _kThemePickerOuterPadding * 2 +
    _kThemeRowBorderAllowance +
    _kThemeScrollbarAllowance;

/// Measures the theme label rendered at each theme's own typography and
/// returns the widest result. Memoized — the theme registry is const and
/// fonts are baked in at build time, so one measurement per app lifetime
/// is enough.
double? _maxThemeLabelWidth;
double _computeMaxThemeLabelWidth() {
  if (_maxThemeLabelWidth != null) return _maxThemeLabelWidth!;
  double widest = 0;
  for (final option in themeOptions) {
    final geom = themeDefinitionFor(option.id).shader.geometry;
    final fontSize = _kThemeLabelFontSize * geom.fontScale;
    final style = TextStyle(
      fontFamily: geom.typography,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: fontSize * geom.letterSpacingEm,
    );
    final painter = TextPainter(
      text: TextSpan(text: option.label, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    if (painter.width > widest) widest = painter.width;
  }
  // Small safety cushion so that fonts which render slightly wider than
  // TextPainter's advance width (kerning, hinting) don't clip.
  _maxThemeLabelWidth = (widest + 4).ceilToDouble();
  return _maxThemeLabelWidth!;
}

double _pickerColumnWidth() {
  return _computeMaxThemeLabelWidth() + _kThemePickerInnerExtras;
}

/// Step 2 — theme + keybinding. The theme list is derived from
/// [themeOptions] (which in turn iterates the [AppThemeId] enum), so
/// adding a theme elsewhere in the codebase auto-populates this picker.
class ThemeStepPage extends StatefulWidget {
  const ThemeStepPage({super.key});

  @override
  State<ThemeStepPage> createState() => _ThemeStepPageState();
}

class _ThemeStepPageState extends State<ThemeStepPage> {
  void _onContinue() {
    context.read<OnboardingState>().next();
  }

  void _useDefaults() {
    final themeState = context.read<ThemeState>();
    themeState.setTheme(defaultThemeId);
    themeState.setKeybindingProfile(KeybindingProfile.classic);
    context.read<OnboardingState>().next();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final identity = context.watch<AppIdentityState>().identity;

    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 8, 48, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Center(
            child: Text(
              'dress ${identity.shortName} up.',
              style: TextStyle(
                color: t.textStrong,
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  // Size the picker to accommodate the widest theme name
                  // at *its own* typography (so e.g. halo's serif at
                  // fontScale 1.12 still fits without wrap). Preserves
                  // the picker's character-per-theme while guaranteeing
                  // the column never reflows.
                  width: _pickerColumnWidth(),
                  child: const _PickerColumn(),
                ),
                const SizedBox(width: 18),
                const Expanded(child: WorkspacePreview()),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const _ActiveThemeDescription(),
          const SizedBox(height: 14),
          OnboardingNavRow(
            onPrimary: _onContinue,
            middle: OnboardingQuietLink(
              label: 'use defaults',
              onTap: _useDefaults,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerColumn extends StatefulWidget {
  const _PickerColumn();

  @override
  State<_PickerColumn> createState() => _PickerColumnState();
}

class _PickerColumnState extends State<_PickerColumn> {
  // Owned ScrollController — preserves offset across the frequent
  // rebuilds triggered by hover-preview theme switches. Without this the
  // SingleChildScrollView allocated a fresh controller each rebuild and
  // the list snapped back to the top on every hover.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final themeState = context.watch<ThemeState>();

    return MaterialSurface(
      tone: t.innerPanelTone,
      borderAlpha: 0.18,
      innerHighlight: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(text: 'THEMES', tokens: t),
          const SizedBox(height: 6),
          // The preview/commit split lives here: moving the mouse inside
          // the theme list previews on hover; leaving the list restores
          // the committed pick so the user can't accidentally walk away
          // with whatever their cursor last happened to cross.
          Expanded(
            child: MouseRegion(
              onExit: (_) => themeState.clearPreview(),
              child: SingleChildScrollView(
                // PageStorageKey survives widget-tree restructures.
                // When the user hovers a theme, the active theme
                // switches, which flips MaterialSurface between
                // `glass` and `solid` shape — the Scrollable's State
                // gets recreated and a fresh ScrollPosition is
                // installed. The owned controller alone can't restore
                // the offset across that recreation; PageStorage can.
                key: const PageStorageKey('onboarding.themePicker'),
                controller: _scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final option in themeOptions)
                      _ThemeRow(
                        option: option,
                        committed:
                            themeState.committedThemeId == option.id,
                        previewing: themeState.themeId == option.id &&
                            themeState.committedThemeId != option.id,
                        onHover: () => themeState.previewTheme(option.id),
                        onTap: () => themeState.setTheme(option.id),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: t.chromeBorder.withValues(alpha: 0.5), height: 1),
          const SizedBox(height: 10),
          _SectionLabel(text: 'KEYBINDINGS', tokens: t),
          const SizedBox(height: 6),
          for (final profile in KeybindingProfile.values)
            _ProfileRow(
              profile: profile,
              selected: themeState.keybindingProfile == profile,
              onTap: () => themeState.setKeybindingProfile(profile),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final AppTokens tokens;
  const _SectionLabel({required this.text, required this.tokens});

  @override
  Widget build(BuildContext context) {
    // Pinned height so the surrounding Column never resizes the
    // Expanded viewport below it when a theme's typography makes this
    // header marginally taller. Any such drift would change
    // maxScrollExtent mid-hover and silently clamp the scroll offset
    // down — indistinguishable from a "reset" to the user.
    return SizedBox(
      height: 14,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: tokens.textFaint,
            fontSize: 9.5,
            height: 1,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ThemeRow extends StatefulWidget {
  final ThemeOption option;
  final bool committed;
  final bool previewing;
  final VoidCallback onHover;
  final VoidCallback onTap;

  const _ThemeRow({
    required this.option,
    required this.committed,
    required this.previewing,
    required this.onHover,
    required this.onTap,
  });

  @override
  State<_ThemeRow> createState() => _ThemeRowState();
}

class _ThemeRowState extends State<_ThemeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final labelCellWidth = _computeMaxThemeLabelWidth();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hover = true);
        widget.onHover();
      },
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          margin: const EdgeInsets.symmetric(vertical: 1),
          // Height pinned so taller fontScales can't resize the row and
          // scroll-jump the list. The label itself still renders at the
          // theme's natural metrics — it just paints inside a fixed
          // frame with ellipsis fallback if somehow ever wider.
          height: _kThemeRowHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: _kThemeRowHorizontalPadding,
          ),
          decoration: BoxDecoration(
            color: widget.committed
                ? t.itemActiveBg
                : _hover
                    ? t.itemHoverBg
                    : t.itemHoverBg.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.committed
                  ? t.itemActiveBorder
                  : widget.previewing
                      ? t.accentBright.withValues(alpha: 0.35)
                      : t.accentBright.withValues(alpha: 0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RadioDot(selected: widget.committed, tokens: t),
              const SizedBox(width: _kThemeRadioGap),
              SizedBox(
                // Label cell is pinned to the widest possible theme name
                // across all themes at their own typography. No theme
                // can force this row to reflow.
                width: labelCellWidth,
                child: Text(
                  widget.option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: _kThemeLabelFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Fixed-width slot whether or not the badge is visible —
              // opacity toggles but the layout stays put. "you're
              // looking at this right now, but haven't locked it in yet."
              SizedBox(
                width: _kThemePreviewSlotWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    duration: context.motion(AppMotion.snap),
                    opacity: widget.previewing ? 1 : 0,
                    child: Text(
                      'preview',
                      style: TextStyle(
                        color: t.accentBright,
                        fontSize: 9,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final KeybindingProfile profile;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileRow({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          // Fixed height — same reason as the theme rows above: keeps
          // the section's total height stable across theme switches.
          height: 40,
          padding: const EdgeInsets.symmetric(
            vertical: 4,
            horizontal: 6,
          ),
          child: Row(
            children: [
              _RadioDot(selected: selected, tokens: t),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textStrong,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      profile.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textMuted, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;
  final AppTokens tokens;
  const _RadioDot({required this.selected, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? tokens.accentBright.withValues(alpha: 0.2)
            : tokens.accentBright.withValues(alpha: 0),
        border: Border.all(
          color:
              selected ? tokens.accentBright : tokens.textFaint,
          width: 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.accentBright,
              ),
            )
          : null,
    );
  }
}

/// Single-line description of the currently-selected theme. Pinned to
/// the left edge (under the picker panel) so it reads as an extension
/// of the name list rather than a caption for the preview.
class _ActiveThemeDescription extends StatelessWidget {
  const _ActiveThemeDescription();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Track the *displayed* theme (so hovering previews updates the
    // description), but the radio dot and the "preview" badge in the
    // picker still reflect the committed choice. Reading both lets the
    // user explore confidently — hover to learn, click to keep.
    final activeId = context.watch<ThemeState>().themeId;
    final description = themeOptions
        .firstWhere(
          (option) => option.id == activeId,
          orElse: () => themeOptions.first,
        )
        .description;

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: context.motion(AppMotion.fade),
        child: Text(
          description,
          key: ValueKey(activeId),
          textAlign: TextAlign.left,
          style: TextStyle(
            color: t.textMuted,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
