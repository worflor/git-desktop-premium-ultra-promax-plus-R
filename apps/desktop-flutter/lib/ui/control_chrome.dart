import 'package:flutter/material.dart';

import 'tokens.dart';

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
  final baseBackground = active
      ? t.itemActiveBg
      : (hovered ? t.secondaryBtnHoverBg : Colors.transparent);
  final borderColor = active
      ? t.itemActiveBorder
      : (hovered ? t.secondaryBtnBorder : Colors.transparent);
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
  final baseBackground =
      hovered && enabled ? t.secondaryBtnHoverBg : Colors.transparent;
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
      _ => 1,
    };
  }
  if (!hovered) return 1;
  return switch (t.id) {
    AppThemeId.aether => 1.05,
    AppThemeId.blackboard || AppThemeId.nightwalker => 1,
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
      _ => const Offset(1, 1),
    };
  }
  if (hovered && t.id == AppThemeId.nightwalker) {
    return const Offset(-1.25, -1.25);
  }
  return Offset.zero;
}

Gradient? _buttonGradient(AppTokens t,
    {required bool hovered, required bool pressed}) {
  if (!hovered || pressed || t.id != AppThemeId.redshift) {
    return null;
  }
  return const LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Colors.transparent,
      Color(0x1AFF0044),
      Colors.transparent,
    ],
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
  if (t.id == AppThemeId.blackboard && hovered) {
    return Colors.white.withValues(alpha: 0.05);
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
  if (t.id == AppThemeId.blackboard && (hovered || active)) {
    return Colors.white.withValues(alpha: 0.6);
  }
  return fallback;
}

List<BoxShadow> _primaryButtonShadows(
  AppTokens t, {
  required bool hovered,
  required bool pressed,
  required bool enabled,
}) {
  if (!enabled || pressed) return const [];
  if (!hovered) {
    return switch (t.id) {
      AppThemeId.redshift => const [],
      AppThemeId.nightwalker => const [],
      _ => [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.22 : 0.10),
            offset: const Offset(1, 1),
            blurRadius: 0,
          ),
        ],
    };
  }
  return switch (t.id) {
    AppThemeId.nightwalker => [
        BoxShadow(
          color: t.chromeAccent.withValues(alpha: 0.1),
          offset: const Offset(2.5, 2.5),
          blurRadius: 0,
        ),
      ],
    AppThemeId.blackboard => [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.2),
          blurRadius: 1,
          spreadRadius: 0.5,
        ),
      ],
    _ => const [],
  };
}

List<BoxShadow> _modeButtonShadows(
  AppTokens t, {
  required bool hovered,
  required bool pressed,
  required bool active,
}) {
  if (pressed) return const [];
  if (active) {
    return [
      BoxShadow(
        color: t.accentBright
            .withValues(alpha: t.id == AppThemeId.blackboard ? 0 : 0.25),
        blurRadius: 1,
        spreadRadius: 0.5,
      ),
    ];
  }
  if (!hovered) return const [];
  return switch (t.id) {
    AppThemeId.nightwalker => [
        BoxShadow(
          color: t.chromeAccent.withValues(alpha: 0.1),
          offset: const Offset(2.5, 2.5),
          blurRadius: 0,
        ),
      ],
    _ => const [],
  };
}

List<BoxShadow> _ghostButtonShadows(
  AppTokens t, {
  required bool hovered,
  required bool enabled,
}) {
  return const [];
}
