import 'package:flutter/foundation.dart';
import '../backend/settings_store.dart';
import '../ui/tokens.dart';

enum KeybindingProfile { classic, compact }

/// Single source of truth for how each [KeybindingProfile] is labelled in
/// the UI. The settings page dropdown, the onboarding picker, and anything
/// else that needs to name a profile all read from here so a rename or a
/// new profile only has to be updated in one place.
extension KeybindingProfileLabels on KeybindingProfile {
  String get label => switch (this) {
        KeybindingProfile.classic => 'Porcelain',
        KeybindingProfile.compact => 'Numeric',
      };

  String get description => switch (this) {
        KeybindingProfile.classic => 'Chorded shortcuts (G then C, H, B…).',
        KeybindingProfile.compact => 'Single-key numeric shortcuts (1, 2, 3…).',
      };
}

class ThemeState extends ChangeNotifier {
  // Two concepts: what's *displayed* (tokens feed the UI) and what's
  // *committed* (the persisted choice). Preview paints without persist so
  // the onboarding picker can reskin live on hover without saving every
  // mouse-move, and without leaving the user stuck on the last-hovered
  // theme if they drift away from the list.
  AppThemeId _themeId = defaultThemeId;
  AppThemeId _committedThemeId = defaultThemeId;
  AppTokens _tokens = AppTokens.fromId(defaultThemeId);
  double _sidebarWidth = 188;
  KeybindingProfile _keybindingProfile = KeybindingProfile.classic;

  AppThemeId get themeId => _themeId;
  AppThemeId get committedThemeId => _committedThemeId;
  AppTokens get tokens => _tokens;
  double get sidebarWidth => _sidebarWidth;
  KeybindingProfile get keybindingProfile => _keybindingProfile;

  Future<void> load() async {
    final settings = await SettingsStore.load();
    final id = normalizeThemeId(settings.themeId);
    _committedThemeId = id;
    _setThemeInMemory(id);
    _sidebarWidth = settings.sidebarWidthPx.toDouble();
    _keybindingProfile = settings.keybindingProfile == 'compact'
        ? KeybindingProfile.compact
        : KeybindingProfile.classic;
    notifyListeners();
  }

  Future<void> setTheme(AppThemeId id) async {
    final changed = _committedThemeId != id || _themeId != id;
    _committedThemeId = id;
    _setThemeInMemory(id);
    if (!changed) return;
    final settings = await SettingsStore.load();
    await SettingsStore.persist(settings.copyWith(themeId: id.name));
    notifyListeners();
  }

  /// Preview a theme without persisting. Swap the displayed tokens so the
  /// UI reskins live, but keep [committedThemeId] pinned to the last real
  /// selection so [clearPreview] can undo the preview cleanly.
  void previewTheme(AppThemeId id) {
    if (_themeId == id) return;
    _setThemeInMemory(id);
    notifyListeners();
  }

  /// Revert any active preview to the committed theme. No-op if nothing
  /// was previewed (or the preview matched the commit).
  void clearPreview() {
    if (_themeId == _committedThemeId) return;
    _setThemeInMemory(_committedThemeId);
    notifyListeners();
  }

  void _setThemeInMemory(AppThemeId id) {
    _themeId = id;
    _tokens = AppTokens.fromId(id);
  }

  Future<void> setSidebarWidth(double w) async {
    // The frame measures the brand lockup each frame and drives the
    // min / max / default from that width, so the callers already
    // pass a clamped value. Keep a sane positive floor here as a
    // belt-and-suspenders against a caller sending NaN or a
    // negative drag value.
    _sidebarWidth = w.isFinite && w > 0 ? w : _sidebarWidth;
    final settings = await SettingsStore.load();
    await SettingsStore.persist(
      settings.copyWith(sidebarWidthPx: _sidebarWidth.round()),
    );
    notifyListeners();
  }

  Future<void> setKeybindingProfile(KeybindingProfile profile) async {
    _keybindingProfile = profile;
    final settings = await SettingsStore.load();
    await SettingsStore.persist(
      settings.copyWith(keybindingProfile: profile.name),
    );
    notifyListeners();
  }
}
