import '../../app/preferences_state.dart';
import '../../backend/file_coupling.dart' show FileSortGuide;

/// Immutable view of the preferences the changes page reads during
/// build. context.select on this class gives compile-time safety:
/// adding a new field here auto-updates == and .from(), so forgetting
/// the tuple can't happen. Fields only read in callbacks (aiReadOnly,
/// commitStructure, etc.) stay on PreferencesState — access them via
/// context.read<PreferencesState>() at the callback site.
class ChangesPagePreferences {
  final FileSortGuide fileSortGuide;
  final bool fileSortInverted;
  final double logosPadX;
  final double logosPadY;
  final int guardrailStage;
  final bool hideAiFeatures;
  final bool stashCabinetDefaultExpanded;

  const ChangesPagePreferences({
    required this.fileSortGuide,
    required this.fileSortInverted,
    required this.logosPadX,
    required this.logosPadY,
    required this.guardrailStage,
    required this.hideAiFeatures,
    required this.stashCabinetDefaultExpanded,
  });

  factory ChangesPagePreferences.from(PreferencesState s) =>
      ChangesPagePreferences(
        fileSortGuide: s.fileSortGuide,
        fileSortInverted: s.fileSortInverted,
        logosPadX: s.logosPadX,
        logosPadY: s.logosPadY,
        guardrailStage: s.guardrailStage,
        hideAiFeatures: s.hideAiFeatures,
        stashCabinetDefaultExpanded: s.stashCabinetDefaultExpanded,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangesPagePreferences &&
          fileSortGuide == other.fileSortGuide &&
          fileSortInverted == other.fileSortInverted &&
          logosPadX == other.logosPadX &&
          logosPadY == other.logosPadY &&
          guardrailStage == other.guardrailStage &&
          hideAiFeatures == other.hideAiFeatures &&
          stashCabinetDefaultExpanded == other.stashCabinetDefaultExpanded;

  @override
  int get hashCode => Object.hash(
        fileSortGuide,
        fileSortInverted,
        logosPadX,
        logosPadY,
        guardrailStage,
        hideAiFeatures,
        stashCabinetDefaultExpanded,
      );
}
