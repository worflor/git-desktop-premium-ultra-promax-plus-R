// Minimal pure-Dart stub of package:flutter/services.dart for the logos
// benchmark harness. Provides `rootBundle` (the only flutter symbol the
// engine's buildFromStats import-closure pulls directly, via
// engram_bootstrap.dart) plus MethodChannel and friends, which the
// transitive shared_preferences dep references at compile time.
//
// Every platform-channel method THROWS if invoked — but the
// buildFromStats hot path never invokes them, so this is purely a
// link-time satisfier. NOT shipped; does not alter engine behaviour.

import 'dart:typed_data';

export 'foundation.dart';

// ---- asset bundle ------------------------------------------------------
class _StubAssetBundle {
  const _StubAssetBundle();
  Future<ByteData> load(String key) async => throw UnsupportedError(
      'rootBundle.load is stubbed in logos_bench ($key)');
  Future<String> loadString(String key, {bool cache = true}) async =>
      throw UnsupportedError(
          'rootBundle.loadString is stubbed in logos_bench ($key)');
  void evict(String key) {}
}

const _StubAssetBundle rootBundle = _StubAssetBundle();

// ---- message codecs ----------------------------------------------------
abstract class MessageCodec<T> {
  const MessageCodec();
}

abstract class MethodCodec {
  const MethodCodec();
}

class StandardMessageCodec implements MessageCodec<Object?> {
  const StandardMessageCodec();
}

class StandardMethodCodec implements MethodCodec {
  const StandardMethodCodec(
      [this.messageCodec = const StandardMessageCodec()]);
  final MessageCodec<Object?> messageCodec;
}

class JSONMessageCodec implements MessageCodec<Object?> {
  const JSONMessageCodec();
}

class JSONMethodCodec implements MethodCodec {
  const JSONMethodCodec();
}

// ---- method channel ----------------------------------------------------
class MethodCall {
  const MethodCall(this.method, [this.arguments]);
  final String method;
  final dynamic arguments;
}

class MethodChannel {
  const MethodChannel(this.name,
      [this.codec = const StandardMethodCodec(), this.binaryMessenger]);
  final String name;
  final MethodCodec codec;
  final Object? binaryMessenger;

  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async =>
      throw UnsupportedError(
          'MethodChannel($name).invokeMethod is stubbed in logos_bench');

  Future<List<T>?> invokeListMethod<T>(String method,
          [dynamic arguments]) async =>
      throw UnsupportedError('MethodChannel.invokeListMethod stubbed');

  Future<Map<K, V>?> invokeMapMethod<K, V>(String method,
          [dynamic arguments]) async =>
      throw UnsupportedError('MethodChannel.invokeMapMethod stubbed');

  void setMethodCallHandler(
      Future<dynamic> Function(MethodCall call)? handler) {}
}

class OptionalMethodChannel extends MethodChannel {
  const OptionalMethodChannel(super.name, [super.codec]);
}

class EventChannel {
  const EventChannel(this.name,
      [this.codec = const StandardMethodCodec(), this.binaryMessenger]);
  final String name;
  final MethodCodec codec;
  final Object? binaryMessenger;
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) =>
      const Stream<dynamic>.empty();
}

class BasicMessageChannel<T> {
  const BasicMessageChannel(this.name, this.codec, {this.binaryMessenger});
  final String name;
  final MessageCodec<T> codec;
  final Object? binaryMessenger;
}

class PlatformException implements Exception {
  PlatformException(
      {required this.code, this.message, this.details, this.stacktrace});
  final String code;
  final String? message;
  final dynamic details;
  final String? stacktrace;
}

class MissingPluginException implements Exception {
  MissingPluginException([this.message]);
  final String? message;
}

class SystemChannels {
  SystemChannels._();
}
