import 'package:flutter/foundation.dart';

import '../../backend/settings_store.dart';

/// One screen in the onboarding flow. Subclass to add a step — the flow
/// iterates [OnboardingState.steps] and dispatches on the concrete type,
/// so neither the chrome nor the state class cares how many there are.
sealed class OnboardingStep {
  const OnboardingStep();
}

class NamingStep extends OnboardingStep {
  const NamingStep();
}

class ThemeStep extends OnboardingStep {
  const ThemeStep();
}

class RepoStep extends OnboardingStep {
  const RepoStep();
}

/// Default step ordering. The list, not the length, is the source of truth.
const List<OnboardingStep> defaultOnboardingSteps = <OnboardingStep>[
  NamingStep(),
  ThemeStep(),
  RepoStep(),
];

class OnboardingState extends ChangeNotifier {
  OnboardingState({
    List<OnboardingStep>? steps,
    bool isComplete = false,
  })  : steps = List.unmodifiable(steps ?? defaultOnboardingSteps),
        _isComplete = isComplete;

  final List<OnboardingStep> steps;

  bool _isComplete;
  int _currentStep = 0;
  int _direction = 1; // +1 forward, -1 back — drives transition directions.

  bool get isComplete => _isComplete;
  int get currentStep => _currentStep;
  int get totalSteps => steps.length;
  int get direction => _direction;
  bool get canGoBack => _currentStep > 0;
  bool get isLastStep => _currentStep == steps.length - 1;
  OnboardingStep get activeStep => steps[_currentStep];

  /// Seed from a loaded settings snapshot. Call once at startup before
  /// registering the provider so the gate decides correctly on first paint.
  void hydrateFromSettings(AppSettingsSnapshot settings) {
    _isComplete = settings.onboardingComplete;
    _currentStep = 0;
    _direction = 1;
  }

  void next() {
    if (_currentStep >= steps.length - 1) return;
    _direction = 1;
    _currentStep += 1;
    notifyListeners();
  }

  void back() {
    if (_currentStep <= 0) return;
    _direction = -1;
    _currentStep -= 1;
    notifyListeners();
  }

  /// Finalize the flow: persist the flag and flip the gate. Any UI
  /// transition (cross-fade to the workspace) keys off [isComplete].
  Future<void> complete() async {
    if (_isComplete) return;
    _isComplete = true;
    notifyListeners();
    final settings = await SettingsStore.load();
    if (!settings.onboardingComplete) {
      await SettingsStore.persist(
        settings.copyWith(onboardingComplete: true),
      );
    }
  }

  /// Re-open the onboarding flow from step 0. The active repo, theme, and
  /// name are untouched — this is a replay, not a reset. The persisted
  /// flag flips back to false so the gate renders the flow again.
  Future<void> replay() async {
    _currentStep = 0;
    _direction = 1;
    _isComplete = false;
    notifyListeners();
    final settings = await SettingsStore.load();
    if (settings.onboardingComplete) {
      await SettingsStore.persist(
        settings.copyWith(onboardingComplete: false),
      );
    }
  }
}
