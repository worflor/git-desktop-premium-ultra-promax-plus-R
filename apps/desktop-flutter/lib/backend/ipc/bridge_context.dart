import '../../app/ai_settings_state.dart';
import '../../app/file_coupling_state.dart';
import '../../app/logos_git_state.dart';
import '../../app/preferences_state.dart';
import '../../app/repository_state.dart';
import '../../app/symbol_frequency_state.dart';
import '../undo_controller.dart';

class ManifoldBridgeContext {
  final RepositoryState repoState;
  final AiSettingsState aiSettingsState;
  final PreferencesState preferencesState;
  final LogosGitState logosGitState;
  final UndoCoordinator undoCoordinator;
  final FileCouplingState fileCouplingState;
  final SymbolFrequencyState symbolFrequencyState;

  const ManifoldBridgeContext({
    required this.repoState,
    required this.aiSettingsState,
    required this.preferencesState,
    required this.logosGitState,
    required this.undoCoordinator,
    required this.fileCouplingState,
    required this.symbolFrequencyState,
  });
}
