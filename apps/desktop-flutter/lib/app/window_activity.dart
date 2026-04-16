import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Single source of truth for "is the app window actually visible and
/// focused right now." Observes the Flutter engine's [AppLifecycleState]
/// **and** the platform `window_manager` focus / minimize events, because
/// on Windows a merely-unfocused visible window stays at
/// [AppLifecycleState.resumed] — the framework's lifecycle signal alone
/// misses "user alt-tabbed to Chrome but our window is still on screen."
/// Purpose: lets decorative continuous animations (particle backdrop,
/// liquid-glass pulse, hypercube logo) stop their tickers the moment the
/// window loses focus or gets minimized, then resume instantly when it
/// comes back. The app is snappy when interacted with and consumes
/// near-zero CPU while idle in the background.
/// Global singleton because the signal is inherently per-process and the
/// consumers are scattered across the widget tree — threading a
/// `ChangeNotifier` through provider for a global concept just adds
/// ceremony without separating concerns.
class WindowActivity extends ChangeNotifier
    with WindowListener, WidgetsBindingObserver {
  WindowActivity._() {
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
  }

  static final WindowActivity instance = WindowActivity._();

  bool _windowFocused = true;
  bool _windowMinimized = false;
  bool _lifecycleActive = true;

  /// True when the window is visible and focused. Consumers that tick
  /// every vsync should gate on this and `stop()` their controllers
  /// whenever it flips to false.
  bool get awake =>
      _windowFocused && !_windowMinimized && _lifecycleActive;


  @override
  void onWindowFocus() {
    if (_windowFocused) return;
    _windowFocused = true;
    notifyListeners();
  }

  @override
  void onWindowBlur() {
    if (!_windowFocused) return;
    _windowFocused = false;
    notifyListeners();
  }

  @override
  void onWindowMinimize() {
    if (_windowMinimized) return;
    _windowMinimized = true;
    notifyListeners();
  }

  @override
  void onWindowRestore() {
    if (!_windowMinimized) return;
    _windowMinimized = false;
    notifyListeners();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == _lifecycleActive) return;
    _lifecycleActive = active;
    notifyListeners();
  }
}
