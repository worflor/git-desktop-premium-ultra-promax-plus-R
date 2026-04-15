// engram_bootstrap.dart — singleton provider + isolate-safe snapshot.
//
// The brain + glove assets are loaded once per app launch (via
// rootBundle). The encoder is fairly expensive to construct because of
// the ~12MB GloVe vector table, so we memoise behind a future and hand
// out the same [EngramHunkEncoder] everywhere.
//
// Heat-kernel diffusion runs in an isolate (`rankHunksByPhiAsync`), so
// the encoder must be buildable from plain byte blobs that cross the
// isolate boundary. [EngramAssets] is that payload — small wrappers
// around the loaded Uint8Lists — and [EngramHunkEncoder.fromAssets]
// rebuilds the in-isolate encoder from them. Reusing the byte buffers
// (not re-downloading/parsing from disk) means isolate spawn cost is
// roughly the cost of parsing the vocab Map, which is milliseconds.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'engram_brain.dart';
import 'engram_glove.dart';
import 'engram_hunk_encoder.dart';

/// Asset paths bundled via pubspec.yaml.
const String kEngramBrainAsset = 'assets/engram/alexandria.endb';
const String kEngramGloveAsset = 'assets/engram/glove300.bin';

/// Raw byte snapshot of the engram assets. Cheap to pass across isolate
/// boundaries (only the two Uint8List blobs are copied). Construct an
/// encoder from it via [EngramAssets.buildEncoder].
class EngramAssets {
  EngramAssets({required this.brainBytes, required this.gloveBytes});

  final Uint8List brainBytes;
  final Uint8List gloveBytes;

  /// Parse the bytes into a ready-to-use [EngramHunkEncoder]. Safe to
  /// call inside an isolate. Returns null if the assets don't parse.
  EngramHunkEncoder? buildEncoder() {
    try {
      final brain = EngramBrain.loadBytes(brainBytes);
      final glove = EngramGlove.loadBytes(gloveBytes);
      return EngramHunkEncoder(brain: brain, glove: glove);
    } on FormatException {
      return null;
    }
  }
}

/// App-wide singleton. Call [EngramRuntime.instance.assets] from the
/// main isolate once (usually at init time — the first hunk ranking
/// will await it if not already loaded). Subsequent calls return the
/// cached future.
/// The runtime stores byte blobs, not the encoder — construction of
/// the encoder (building the vocab HashMap) is re-done in worker
/// isolates because Maps don't cross isolate boundaries cheaply.
class EngramRuntime {
  EngramRuntime._();
  static final EngramRuntime instance = EngramRuntime._();

  Future<EngramAssets?>? _assetsFuture;
  EngramHunkEncoder? _mainIsolateEncoder;
  bool _encoderBuilt = false;

  /// Load the engram assets from rootBundle. Returns null on any failure
  /// (missing asset, bad magic, wrong version) — callers must cope.
  Future<EngramAssets?> assets() {
    return _assetsFuture ??= _loadAssets();
  }

  /// Convenience: build (and memoise) a main-isolate encoder for code
  /// paths that can't cross an isolate boundary. Returns null if assets
  /// aren't available or fail to parse.
  Future<EngramHunkEncoder?> mainEncoder() async {
    if (_encoderBuilt) return _mainIsolateEncoder;
    final a = await assets();
    _mainIsolateEncoder = a?.buildEncoder();
    _encoderBuilt = true;
    return _mainIsolateEncoder;
  }

  Future<EngramAssets?> _loadAssets() async {
    try {
      final brain = await rootBundle.load(kEngramBrainAsset);
      final glove = await rootBundle.load(kEngramGloveAsset);
      return EngramAssets(
        brainBytes: brain.buffer.asUint8List(
          brain.offsetInBytes,
          brain.lengthInBytes,
        ),
        gloveBytes: glove.buffer.asUint8List(
          glove.offsetInBytes,
          glove.lengthInBytes,
        ),
      );
    } on Object {
      // rootBundle.load throws FlutterError / FileSystemException
      // depending on platform. We don't want engram unavailability to
      // break the app — ranking will degrade to the old Jaccard-only
      // H_sym signal, which is still good.
      return null;
    }
  }

  /// Test hook: inject a pre-loaded assets object. Bypasses rootBundle
  /// so unit tests can feed synthetic .endb / .glv1 blobs.
  void debugSetAssets(EngramAssets? assets) {
    _assetsFuture = Future<EngramAssets?>.value(assets);
    _mainIsolateEncoder = assets?.buildEncoder();
    _encoderBuilt = true;
  }
}
