import 'package:flutter/material.dart';

import 'tokens.dart';

/// Per-theme button-chrome quirks. Lets the chrome builders stay declarative
/// (just consume getters) instead of scattering `t.id == AppThemeId.X`
/// branches across every paint path. Single source of truth per quirk.
///
/// Null-returning getters mean "no override — caller uses its fallback."
extension AppTokenButtonChrome on AppTokens {
  /// Nightwalker shifts its button content up-and-left on hover as part of
  /// the etch/obsidian-stamp aesthetic. Other themes return null (no shift).
  Offset? get buttonHoverShift => id == AppThemeId.nightwalker
      ? const Offset(-1.25, -1.25)
      : null;

  /// Blackboard overrides the hover background to translucent white — the
  /// "chalk mark" on the slate. Others fall through to the normal hover bg.
  Color? get buttonHoverBgOverride => id == AppThemeId.blackboard
      ? Colors.white.withValues(alpha: 0.05)
      : null;

  /// Blackboard also brightens the border on hover/active to read as a
  /// chalk underline. Other themes return null.
  Color? get buttonHoverBorderOverride => id == AppThemeId.blackboard
      ? Colors.white.withValues(alpha: 0.6)
      : null;

  /// Alpha for the glow shadow behind active mode buttons. Blackboard opts
  /// out (slate doesn't glow); everyone else uses 0.25.
  double get activeButtonGlowAlpha =>
      id == AppThemeId.blackboard ? 0 : 0.25;
}

class ControlChromeState {
  final double scale;
  final Offset offset;
  final Gradient? gradient;
  final List<BoxShadow> shadows;
  final Color background;
  final Color borderColor;

  const ControlChromeState({
    required this.scale,
    required this.offset,
    required this.gradient,
    required this.shadows,
    required this.background,
    required this.borderColor,
  });
}

ControlChromeState primaryButtonChrome(
  AppTokens t, {
  required bool hovered,
  required bool pressed,
  required bool enabled,
}) {
  final baseBackground = hovered && enabled ? t.btnHoverBg : t.btnBg;
  final borderColor = hovered && enabled ? t.inputFocusBorder : t.btnBorder;
  return ControlChromeState(
    scale:
        _buttonScale(t, hovered: hovered, pressed: pressed, enabled: enabled),
    offset:
        _buttonOffset(t, hovered: hovered, pressed: pressed, enabled: enabled),
    gradient: _buttonGradient(t, hovered: hovered, pressed: pressed),
    shadows: _primaryButtonShadows(
      t,
      hovered: hovered,
      pressed: pressed,
      enabled: enabled,
    ),
    background: _buttonBackgroundOverride(
      t,
      baseBackground,
      hovered: hovered,
      pressed: pressed,
      enabled: enabled,
    ),
    borderColor: _buttonBorderOverride(
      t,
      borderColor,
      hovered: hovered,
      enabled: enabled,
    ),
  );
}

ControlChromeState modeButtonChrome(
  AppTokens t, {
  required bool hovered,
  required bool pressed,
  required bool active,
}) {
  // Animated lerp endpoints share RGB; only alpha changes. `Colors.transparent`
  // is fully-transparent BLACK — animating to a colored hover state runs the
  // lerp through translucent-black midpoints (visible as a gray flash).
  final baseBackground = active
      ? t.itemActiveBg
      : (hovered ? t.secondaryBtnHoverBg : t.secondaryBtnHoverBg.withValues(alpha: 0));
  final borderColor = active
      ? t.itemActiveBorder
      : (hovered ? t.secondaryBtnBorder : t.secondaryBtnBorder.withValues(alpha: 0));
  return ControlChromeState(
    scale: _buttonScale(t, hovered: hovered, pressed: pressed, enabled: true),
    offset: _buttonOffset(t, hovered: hovered, pressed: pressed, enabled: true),
    gradient: _buttonGradient(t, hovered: hovered || active, pressed: pressed),
    shadows: _modeButtonShadows(
      t,
      hovered: hovered,
      pressed: pressed,
      active: active,
    ),
    background: _buttonBackgroundOverride(
      t,
      baseBackground,
      hovered: hovered || active,
      pressed: pressed,
      enabled: true,
    ),
    borderColor: _buttonBorderOverride(
      t,
      borderColor,
      hovered: hovered || active,
      enabled: true,
      active: active,
    ),
  );
}

ControlChromeState ghostButtonChrome(
  AppTokens t, {
  required bool hovered,
  required bool pressed,
  required bool enabled,
  required Color baseBorderColor,
}) {
  final baseBackground = hovered && enabled
      ? t.secondaryBtnHoverBg
      : t.secondaryBtnHoverBg.withValues(alpha: 0);
  final borderColor = hovered && enabled ? t.inputFocusBorder : baseBorderColor;
  return ControlChromeState(
    scale: 1,
    offset: hovered && enabled && !pressed ? const Offset(0, -1) : Offset.zero,
    gradient: null,
    shadows: _ghostButtonShadows(t, hovered: hovered, enabled: enabled),
    background: _buttonBackgroundOverride(
      t,
      baseBackground,
      hovered: hovered,
      pressed: pressed,
      enabled: enabled,
    ),
    borderColor: _buttonBorderOverride(
      t,
      borderColor,
      hovered: hovered,
      enabled: enabled,
    ),
  );
}

double _buttonScale(
  AppTokens t, {
  required bool hovered,
  required bool pressed,
  required bool enabled,
}) {
  if (!enabled) return 1;
  if (pressed) {
    return switch (t.id) {
      AppThemeId.blackboard => 0.97,
      AppThemeId.nightwalker => 0.99,
      AppThemeId.loverboy => 1,
      _ => 1,
    };
  }
  if (!hovered) return 1;
  return switch (t.id) {
    AppThemeId.aether => 1.05,
    AppThemeId.blackboard
        || AppThemeId.nightwalker
        || AppThemeId.loverboy => 1,
    _ => 1.02,
  };
}

Offset _buttonOffset(
  AppTokens t, {
  required bool hovered,
  required bool pressed,
  required bool enabled,
}) {
  if (!enabled) return Offset.zero;
  if (pressed) {
    return switch (t.id) {
      AppThemeId.crafty => const Offset(0, 4),
      AppThemeId.halo || AppThemeId.nightwalker => const Offset(0, 1),
      AppThemeId.blackboard => Offset.zero,
      AppThemeId.loverboy => Offset.zero,
      _ => const Offset(1, 1),
    };
  }
  if (hovered) {
    final shift = t.buttonHoverShift;
    if (shift != null) return shift;
  }
  return Offset.zero;
}

Gradient? _buttonGradient(AppTokens t,
    {required bool hovered, required bool pressed}) {
  if (!hovered || pressed || t.id != AppThemeId.redshift) {
    return null;
  }
  final ambient =
      (t.themeAmbient ?? t.chromeAccent).withValues(alpha: 0.10);
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Colors.transparent, ambient, Colors.transparent],
  );
}

Color _buttonBackgroundOverride(
  AppTokens t,
  Color fallback, {
  required bool hovered,
  required bool pressed,
  required bool enabled,
}) {
  if (!enabled) return fallback;
  if (hovered) {
    final override = t.buttonHoverBgOverride;
    if (override != null) return override;
  }
  return fallback;
}

Color _buttonBorderOverride(
  AppTokens t,
  Color fallback, {
  required bool hovered,
  required bool enabled,
  bool active = false,
}) {
  if (!enabled) return fallback;
  if (hovered || active) {
    final override = t.buttonHoverBorderOverride;
    if (override != null) return override;
  }
  return fallback;
}

List<BoxShadow> _primaryButtonShadows(
  AppTokens t, {
  required bool hovered,
  required bool pressed,
  required bool enabled,
}) {
  // ALL returns produce a non-empty list of the same length (1) so
  // `AnimatedContainer.boxShadow.lerp` interpolates between two real
  // shadows (alpha + offset only) instead of injecting a phantom
  // shadow toward `Colors.transparent` (= transparent BLACK), which
  // is what produced the gray-flash on hover-enter and hover-exit
  // for every primary button. Theme-color shadow base (`t.shadowElev`)
  // also keeps the shadow in-theme instead of hard-black.
  final base = t.shadowElev;
  if (!enabled || pressed) {
    return [
      BoxShadow(
        color: base.withValues(alpha: 0),
        offset: const Offset(1, 1),
      ),
    ];
  }
  if (!hovered) {
    return switch (t.id) {
      AppThemeId.redshift || AppThemeId.nightwalker => [
          BoxShadow(
            color: base.withValues(alpha: 0),
            offset: const Offset(1, 1),
          ),
        ],
      // Hard 2px pink drop, no blur. Always visible.
      AppThemeId.loverboy => [
          BoxShadow(
            color: t.accentBright.withValues(alpha: 0.35),
            offset: const Offset(2, 2),
          ),
        ],
      _ => [
          BoxShadow(
            color: base.withValues(alpha: t.isDark ? 0.22 : 0.10),
            offset: const Offset(1, 1),
          ),
        ],
    };
  }
  return switch (t.id) {
    AppThemeId.nightwalker => _nightwalkerAccentShadow(t),
    AppThemeId.blackboard => [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.2),
          blurRadius: 1,
          spreadRadius: 0.5,
        ),
      ],
    // Same direction as the base shadow, longer and more opaque on hover.
    AppThemeId.loverboy => [
        BoxShadow(
          color: t.accentBright.withValues(alpha: 0.65),
          offset: const Offset(3, 3),
        ),
      ],
    _ => [
        BoxShadow(
          color: base.withValues(alpha: 0),
          offset: const Offset(1, 1),
        ),
      ],
  };
}

/// Nightwalker's signature offset accent drop — used for primary button
/// hover and mode-button hover. Extracted so the two call-sites stay in
/// sync; the offset and alpha are a deliberate theme identity choice.
List<BoxShadow> _nightwalkerAccentShadow(AppTokens t) => [
      BoxShadow(
        color: t.chromeAccent.withValues(alpha: 0.1),
        offset: const Offset(2.5, 2.5),
        blurRadius: 0,
      ),
    ];

List<BoxShadow> _modeButtonShadows(
  AppTokens t, {
  required bool hovered,
  required bool pressed,
  required bool active,
}) {
  // Same-shape lists across all states so the lerp animates alpha/
  // offset only — never inserts a transparent-BLACK phantom that
  // would gray-flash on the (1,1) offset during hover transitions.
  final phantom = BoxShadow(
    color: t.accentBright.withValues(alpha: 0),
    blurRadius: 1,
    spreadRadius: 0.5,
  );
  if (pressed) return [phantom];
  if (active) {
    return [
      BoxShadow(
        color: t.accentBright.withValues(alpha: t.activeButtonGlowAlpha),
        blurRadius: 1,
        spreadRadius: 0.5,
      ),
    ];
  }
  if (!hovered) return [phantom];
  return switch (t.id) {
    AppThemeId.nightwalker => _nightwalkerAccentShadow(t),
    _ => [phantom],
  };
}

List<BoxShadow> _ghostButtonShadows(
  AppTokens t, {
  required bool hovered,
  required bool enabled,
}) {
  return const [];
}
