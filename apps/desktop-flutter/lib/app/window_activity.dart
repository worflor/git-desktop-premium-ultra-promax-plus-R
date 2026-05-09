import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

// Idle-GPU diagnostic flag. Mirrors main.dart's `_kFpsProbe` so the
// focus/minimize trace lines match the FPS probe's gating — both on in
// debug builds or when built with `--dart-define=FPS_PROBE=true`, both
// off in default release builds.
const bool _kFpsProbeTrace =
    kDebugMode || bool.fromEnvironment('FPS_PROBE', defaultValue: false);

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

  /// True when the window is on screen (not minimized). Does not require
  /// focus or active lifecycle — use this to keep animations running when
  /// the user can still see the window behind another app.
  bool get visible => !_windowMinimized;


  @override
  void onWindowFocus() {
    if (_windowFocused) return;
    _windowFocused = true;
    if (_kFpsProbeTrace) {
      // ignore: avoid_print
      print('FPS-PROBE: awake->TRUE (focus)');
    }
    notifyListeners();
  }

  @override
  void onWindowBlur() {
    if (!_windowFocused) return;
    _windowFocused = false;
    if (_kFpsProbeTrace) {
      // ignore: avoid_print
      print('FPS-PROBE: awake->FALSE (blur)');
    }
    notifyListeners();
  }

  @override
  void onWindowMinimize() {
    if (_windowMinimized) return;
    _windowMinimized = true;
    if (_kFpsProbeTrace) {
      // ignore: avoid_print
      print('FPS-PROBE: awake->FALSE (minimize)');
    }
    notifyListeners();
  }

  @override
  void onWindowRestore() {
    if (!_windowMinimized) return;
    _windowMinimized = false;
    if (_kFpsProbeTrace) {
      // ignore: avoid_print
      print('FPS-PROBE: awake->TRUE (restore)');
    }
    notifyListeners();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == _lifecycleActive) return;
    _lifecycleActive = active;
    if (_kFpsProbeTrace) {
      // ignore: avoid_print
      print('FPS-PROBE: lifecycle=${state.name} active=$active');
    }
    notifyListeners();
  }
}

/// Mixin that wires a State to [WindowActivity]'s change-notifier. Use
/// for widgets whose listener lifecycle is purely initState/dispose —
/// the common case where nothing in the callback depends on a
/// [BuildContext] lookup.
///
/// Implementers override [onWindowAwakeChanged] with whatever the
/// widget does when the window focus/minimize/lifecycle signal flips.
/// The same method is (un)registered using Dart's stable instance
/// tear-off equality, so add/remove pair up correctly.
mixin WindowAwakeMixin<T extends StatefulWidget> on State<T> {
  @protected
  void onWindowAwakeChanged();

  @override
  @mustCallSuper
  void initState() {
    super.initState();
    WindowActivity.instance.addListener(onWindowAwakeChanged);
  }

  @override
  @mustCallSuper
  void dispose() {
    WindowActivity.instance.removeListener(onWindowAwakeChanged);
    super.dispose();
  }
}

/// As [WindowAwakeMixin] but attaches lazily in [didChangeDependencies]
/// rather than [initState]. Use when the callback consults an
/// InheritedWidget (e.g. `context.read<PreferencesState>()`) — those
/// aren't safe to touch in initState. A `_attached` flag guards
/// against the repeated didChangeDependencies calls Flutter makes
/// when ancestors rebuild.
mixin WindowAwakeGuardedMixin<T extends StatefulWidget> on State<T> {
  bool _windowAwakeAttached = false;

  @protected
  void onWindowAwakeChanged();

  @override
  @mustCallSuper
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_windowAwakeAttached) {
      WindowActivity.instance.addListener(onWindowAwakeChanged);
      _windowAwakeAttached = true;
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    if (_windowAwakeAttached) {
      WindowActivity.instance.removeListener(onWindowAwakeChanged);
    }
    super.dispose();
  }
}
