// Topology-canvas fragment-shader loaders.
//
// Separate from ThemeShaders because these are engine-visualisation
// programs with per-paint data flow (node counts, fade envelopes,
// center/radius). Same lazy-load + single-compile pattern: the
// FragmentProgram compiles once on first access and stays in memory
// for the session; per-paint cost is creating a FragmentShader handle
// from the program (cheap — it's just a uniform-state buffer) plus
// the setFloat calls.
//
// Each shader lives in `shaders/topology_*.frag`. Registered in
// pubspec.yaml's `shaders:` list so Flutter compiles + ships them.

import 'dart:ui' as ui;
import 'dart:ui' show FragmentProgram;

class TopologyShaders {
  TopologyShaders._();

  static FragmentProgram? _starfield;
  static Future<FragmentProgram>? _starfieldFuture;

  /// Kicks off loading the starfield program if it hasn't been loaded
  /// yet. Safe to call repeatedly — only the first call triggers
  /// asset I/O. Returns null synchronously until the program is ready;
  /// callers should fall back to a CPU painter path during warm-up
  /// and transparently switch over once this starts returning non-null.
  static FragmentProgram? starfield() {
    if (_starfield != null) return _starfield;
    // Fresh kickoff when no inflight future exists yet. `.catchError`
    // clears the cache entry on failure so a transient load error
    // doesn't poison subsequent attempts — the next `starfield()` call
    // after a reload can try again instead of forever returning a
    // failed future.
    _starfieldFuture ??=
        FragmentProgram.fromAsset('shaders/topology_starfield.frag').then(
      (p) {
        _starfield = p;
        return p;
      },
      onError: (Object e, StackTrace s) {
        _starfieldFuture = null;
        throw e;
      },
    );
    return null;
  }

  /// Returns a future that completes when the starfield program is
  /// loaded (already-loaded → immediate completion). Used by callers
  /// that need to schedule a repaint as soon as the GPU path is
  /// available — fire-and-forget `starfield()` alone isn't enough
  /// because if the canvas is idle (no motion ticker running), no
  /// setState fires to pick up the newly-ready program.
  static Future<void> whenStarfieldReady() {
    if (_starfield != null) return Future.value();
    // Trigger the load if it hasn't started yet.
    starfield();
    final f = _starfieldFuture;
    if (f == null) return Future.value();
    return f.then<void>((_) {}, onError: (Object _, StackTrace __) {
      // Swallow errors here — the load-side handler already cleared
      // the cache. Callers just want to know "I can try rendering now";
      // a failed compile means "keep using the CPU fallback," not
      // "throw at the UI."
    });
  }

  /// Build a configured starfield shader. Uniform order matches the
  /// `.frag` declaration sequence:
  ///   0..1   uSize        (vec2)
  ///   2..3   uCenter      (vec2)
  ///   4      uMaxRadius
  ///   5      uBaseCount
  ///   6      uExtraCount
  ///   7      uBaseEnv
  ///   8      uDenseEnv
  ///   9..12  uColor       (vec4 rgba)
  static ui.FragmentShader? starfieldShader({
    required double width,
    required double height,
    required double centerX,
    required double centerY,
    required double maxRadius,
    required double baseCount,
    required double extraCount,
    required double baseEnv,
    required double denseEnv,
    required ui.Color color,
  }) {
    final program = starfield();
    if (program == null) return null;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, centerX)
      ..setFloat(3, centerY)
      ..setFloat(4, maxRadius)
      ..setFloat(5, baseCount)
      ..setFloat(6, extraCount)
      ..setFloat(7, baseEnv)
      ..setFloat(8, denseEnv)
      ..setFloat(9, color.r)
      ..setFloat(10, color.g)
      ..setFloat(11, color.b)
      ..setFloat(12, color.a);
    return s;
  }
}
