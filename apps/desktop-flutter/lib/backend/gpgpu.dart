// GPGPU via fragment shader.
//
// Flutter exposes FragmentProgram (GLSL-ES subset, no compute shader
// features) but that's enough to borrow the classic "fragment-as-
// coprocessor" trick: pack arbitrary data into pixel channels, render
// a shader across an offscreen quad, read back the pixel buffer. The
// fragment pipeline runs one thread per output pixel in parallel —
// effectively a SIMD-wide kernel invocation for the cost of one
// drawRect call plus one GPU→CPU sync.
//
// This module is the generic harness. Subclass [GpgpuKernel] per
// operation:
//
//   class MyKernel extends GpgpuKernel<InType, OutType> {
//     @override String get asset => 'shaders/gpgpu_my_kernel.frag';
//     @override (int, int) outputSize(InType input) => (input.n, 1);
//     @override void packInputs(InType input, Object shader) { ... }
//     @override OutType decodeOutput(ByteData bytes, int w, int h) { ... }
//   }
//
//   final out = await runGpgpuKernel(MyKernel(), input);
//
// Three rules the harness enforces for bit-accurate output:
//
//   1. `BlendMode.src` on the paint. The default `srcOver` composites
//      with alpha; we want raw shader output byte-for-byte.
//   2. Output is read via `ImageByteFormat.rawRgba` — no sRGB
//      conversion, no premultiplication dance.
//   3. Shader encodes floats via `floatBitsToUint` → 4 bytes per
//      pixel, decoded on the Dart side by reinterpreting the same
//      4 bytes as a Float32.
//
// Cost model: one kernel call is ~0.5-3ms of GPU work + 1-5ms readback
// sync. Only beats CPU when the kernel's work is large enough to
// amortise that sync — rule of thumb, >10k float ops per call.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Abstract base for a GPGPU kernel. Implementors describe:
///   * which shader asset drives the computation
///   * what the output texture size is for a given input
///   * how to pack inputs into uniform slots or sampler textures
///   * how to decode the output pixel bytes into the result type
///
/// The harness (see [runGpgpuKernel]) takes care of program
/// compilation, shader handle creation, rendering the quad, GPU→CPU
/// readback, and the boilerplate around picture recording and image
/// decoding.
abstract class GpgpuKernel<TIn, TOut> {
  /// Path (relative to the `pubspec.yaml` shaders: list) of the
  /// compiled fragment program this kernel drives.
  String get asset;

  /// The offscreen render-target dimensions for a given input. The
  /// fragment pipeline runs one thread per pixel, so this is literally
  /// the parallelism width × height.
  (int width, int height) outputSize(TIn input);

  /// Populate uniform slots and sampler bindings from [input].
  /// [shader] is a `ui.FragmentShader` (dynamic-typed here so
  /// implementors don't need a `dart:ui` import).
  void packInputs(TIn input, ui.FragmentShader shader);

  /// Decode the raw RGBA8 pixel buffer (4 bytes per pixel, row-major,
  /// width × height) back into the result type.
  TOut decodeOutput(ByteData bytes, int width, int height);
}

/// Lazy cache of compiled FragmentPrograms. Each asset compiles
/// exactly once per process — recompilation would be unusually
/// expensive (millisecond-scale JIT), so keeping the programs alive
/// for the session is always the right call.
final Map<String, ui.FragmentProgram> _programCache = {};
final Map<String, Future<ui.FragmentProgram>> _programLoading = {};

Future<ui.FragmentProgram> _loadProgram(String asset) {
  final cached = _programCache[asset];
  if (cached != null) return Future.value(cached);
  final inflight = _programLoading[asset];
  if (inflight != null) return inflight;
  // Wire both success and failure paths to evict the inflight entry.
  // Without the error branch, a failed compile pins the cache to a
  // perpetually-failing future — every subsequent caller would get
  // the same failure with no recovery path. Clearing on error lets
  // the next caller retry from scratch (useful for transient
  // platform-level compile errors).
  final future = ui.FragmentProgram.fromAsset(asset).then(
    (program) {
      _programCache[asset] = program;
      _programLoading.remove(asset);
      return program;
    },
    onError: (Object e, StackTrace s) {
      _programLoading.remove(asset);
      throw e;
    },
  );
  _programLoading[asset] = future;
  return future;
}

/// Run [kernel] with the given [input]. Returns the decoded output.
///
/// The harness renders into an offscreen picture, flushes to a
/// [ui.Image], and reads back the raw pixel buffer. Callers pay one
/// GPU→CPU sync per invocation; batch work into a single kernel call
/// rather than many small ones.
Future<TOut> runGpgpuKernel<TIn, TOut>(
    GpgpuKernel<TIn, TOut> kernel, TIn input) async {
  final program = await _loadProgram(kernel.asset);
  final shader = program.fragmentShader();
  kernel.packInputs(input, shader);

  final (width, height) = kernel.outputSize(input);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // BlendMode.src is the non-negotiable bit here. The default
  // srcOver composites alpha, which mangles bit-packed float outputs
  // in the alpha channel. `src` writes raw shader RGBA verbatim.
  final paint = ui.Paint()
    ..shader = shader
    ..blendMode = ui.BlendMode.src;
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final byteData =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (byteData == null) {
    throw StateError('GPGPU kernel ${kernel.asset} returned null pixel data');
  }
  return kernel.decodeOutput(byteData, width, height);
}

/// Build a [ui.Image] suitable for passing to a kernel as a sampler
/// input. Each float in [values] occupies one RGBA pixel (4 bytes);
/// the float's IEEE-754 bit pattern is laid out byte-for-byte so the
/// shader can reconstruct it via `uintBitsToFloat(packedBytes)`.
///
/// [width] defaults to `values.length` (one-row input). For larger
/// inputs supply a width/height that multiplies to `values.length`
/// — the kernel's shader reads `texture(uInput, vec2(...))` and
/// decodes.
Future<ui.Image> encodeFloat32Texture(Float32List values,
    {int? width, int? height}) async {
  final w = width ?? values.length;
  final h = height ?? 1;
  if (w * h != values.length) {
    throw ArgumentError(
        'width × height (${w * h}) must equal values.length (${values.length})');
  }
  // Raw RGBA8 — each float splattered across 4 bytes. Byte order
  // matches what `uintBitsToFloat` expects after the shader
  // reassembles the RGBA components via bit-shifts (R=MSB, A=LSB
  // by convention).
  final bytes = Uint8List(w * h * 4);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < values.length; i++) {
    bd.setFloat32(i * 4, values[i], Endian.big);
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Decode a ByteData buffer of bit-packed 32-bit floats (as emitted
/// by a kernel whose shader calls `floatBitsToRgba8` at each pixel)
/// back into a [Float32List]. Output length = width × height.
Float32List decodeFloat32Output(ByteData bytes, int width, int height) {
  final n = width * height;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bytes.getFloat32(i * 4, Endian.big);
  }
  return out;
}
