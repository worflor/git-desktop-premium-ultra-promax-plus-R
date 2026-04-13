import 'package:flutter/foundation.dart';
import '../backend/settings_store.dart';
import '../ui/tokens.dart';

enum KeybindingProfile { classic, compact }

class ThemeState extends ChangeNotifier {
  AppThemeId _themeId = defaultThemeId;
  AppTokens _tokens = AppTokens.fromId(defaultThemeId);
  double _sidebarWidth = 188;
  KeybindingProfile _keybindingProfile = KeybindingProfile.classic;

  AppThemeId get themeId => _themeId;
  AppTokens get tokens => _tokens;
  double get sidebarWidth => _sidebarWidth;
  KeybindingProfile get keybindingProfile => _keybindingProfile;

  Future<void> load() async {
    final settings = await SettingsStore.load();
    _setThemeInMemory(normalizeThemeId(settings.themeId));
    _sidebarWidth = settings.sidebarWidthPx.toDouble();
    _keybindingProfile = settings.keybindingProfile == 'compact'
        ? KeybindingProfile.compact
        : KeybindingProfile.classic;
    notifyListeners();
  }

  Future<void> setTheme(AppThemeId id) async {
    if (_themeId == id) return;
    _setThemeInMemory(id);
    final settings = await SettingsStore.load();
    await SettingsStore.persist(
      AppSettingsSnapshot(
        guardrailValue: settings.guardrailValue,
        aiReadOnlyDefault: settings.aiReadOnlyDefault,
        logoAnimatesWhenUnfocused: settings.logoAnimatesWhenUnfocused,
        telemetryRetentionDays: settings.telemetryRetentionDays,
        telemetryRetentionMb: settings.telemetryRetentionMb,
        updateChannel: settings.updateChannel,
        crashReportingEnabled: settings.crashReportingEnabled,
        themeId: id.name,
        keybindingProfile: settings.keybindingProfile,
        sidebarWidthPx: settings.sidebarWidthPx,
        sidebarPosition: settings.sidebarPosition,
        utilityDrawerDefaultExpanded: settings.utilityDrawerDefaultExpanded,
        utilityDrawerHeightPx: settings.utilityDrawerHeightPx,
        reduceMotion: settings.reduceMotion,
        reduceMotionPhase: settings.reduceMotionPhase,
        stashCabinetDefaultExpanded: settings.stashCabinetDefaultExpanded,
        instantBlameHover: settings.instantBlameHover,
        fileSortGuide: settings.fileSortGuide,
        fileSortInverted: settings.fileSortInverted,
        commitStructure: settings.commitStructure,
        commitVoice: settings.commitVoice,
        commitCoverage: settings.commitCoverage,
      ),
    );
    notifyListeners();
  }

  void _setThemeInMemory(AppThemeId id) {
    _themeId = id;
    _tokens = AppTokens.fromId(id);
  }

  Future<void> setSidebarWidth(double w) async {
    _sidebarWidth = w.clamp(140, 380);
    final settings = await SettingsStore.load();
    await SettingsStore.persist(
      AppSettingsSnapshot(
        guardrailValue: settings.guardrailValue,
        aiReadOnlyDefault: settings.aiReadOnlyDefault,
        logoAnimatesWhenUnfocused: settings.logoAnimatesWhenUnfocused,
        telemetryRetentionDays: settings.telemetryRetentionDays,
        telemetryRetentionMb: settings.telemetryRetentionMb,
        updateChannel: settings.updateChannel,
        crashReportingEnabled: settings.crashReportingEnabled,
        themeId: settings.themeId,
        keybindingProfile: settings.keybindingProfile,
        sidebarWidthPx: _sidebarWidth.round(),
        sidebarPosition: settings.sidebarPosition,
        utilityDrawerDefaultExpanded: settings.utilityDrawerDefaultExpanded,
        utilityDrawerHeightPx: settings.utilityDrawerHeightPx,
        reduceMotion: settings.reduceMotion,
        reduceMotionPhase: settings.reduceMotionPhase,
        stashCabinetDefaultExpanded: settings.stashCabinetDefaultExpanded,
        instantBlameHover: settings.instantBlameHover,
        fileSortGuide: settings.fileSortGuide,
        fileSortInverted: settings.fileSortInverted,
        commitStructure: settings.commitStructure,
        commitVoice: settings.commitVoice,
        commitCoverage: settings.commitCoverage,
      ),
    );
    notifyListeners();
  }

  Future<void> setKeybindingProfile(KeybindingProfile profile) async {
    _keybindingProfile = profile;
    final settings = await SettingsStore.load();
    await SettingsStore.persist(
      AppSettingsSnapshot(
        guardrailValue: settings.guardrailValue,
        aiReadOnlyDefault: settings.aiReadOnlyDefault,
        logoAnimatesWhenUnfocused: settings.logoAnimatesWhenUnfocused,
        telemetryRetentionDays: settings.telemetryRetentionDays,
        telemetryRetentionMb: settings.telemetryRetentionMb,
        updateChannel: settings.updateChannel,
        crashReportingEnabled: settings.crashReportingEnabled,
        themeId: settings.themeId,
        keybindingProfile: profile.name,
        sidebarWidthPx: settings.sidebarWidthPx,
        sidebarPosition: settings.sidebarPosition,
        utilityDrawerDefaultExpanded: settings.utilityDrawerDefaultExpanded,
        utilityDrawerHeightPx: settings.utilityDrawerHeightPx,
        reduceMotion: settings.reduceMotion,
        reduceMotionPhase: settings.reduceMotionPhase,
        stashCabinetDefaultExpanded: settings.stashCabinetDefaultExpanded,
        instantBlameHover: settings.instantBlameHover,
        fileSortGuide: settings.fileSortGuide,
        fileSortInverted: settings.fileSortInverted,
        commitStructure: settings.commitStructure,
        commitVoice: settings.commitVoice,
        commitCoverage: settings.commitCoverage,
      ),
    );
    notifyListeners();
  }
}
