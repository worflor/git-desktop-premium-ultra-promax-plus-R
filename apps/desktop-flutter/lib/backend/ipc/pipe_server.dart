import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../storage_paths.dart';
import 'bridge_context.dart';
import 'pipe_commands.dart';
import 'pipe_protocol.dart';

class ManifoldPipeServer {
  final ManifoldBridgeContext ctx;
  ServerSocket? _server;
  File? _lockFile;
  final List<Socket> _connections = [];

  ManifoldPipeServer(this.ctx);

  Future<void> start() async {
    final ipcDir = await _ipcDir();
    await ipcDir.create(recursive: true);
    await _cleanStaleLocks(ipcDir);

    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = _server!.port;
    final myPid = pid;

    _lockFile = File(p.join(ipcDir.path, 'manifold-$myPid.lock'));
    await _lockFile!.writeAsString(jsonEncode({
      'pid': myPid,
      'port': port,
      'workspace': ctx.repoState.activePath ?? '',
      'startedAt': DateTime.now().toIso8601String(),
    }));

    debugPrint('[IPC] listening on 127.0.0.1:$port (lock: ${_lockFile!.path})');
    _server!.listen(_handleConnection);
  }

  Future<void> dispose() async {
    for (final c in _connections) {
      c.destroy();
    }
    _connections.clear();
    await _server?.close();
    _server = null;
    try {
      await _lockFile?.delete();
    } catch (_) {}
  }

  void _handleConnection(Socket socket) {
    _connections.add(socket);
    final buffer = <int>[];
    socket.listen(
      (data) {
        buffer.addAll(data);
        _processBuffer(socket, buffer);
      },
      onError: (_) => _cleanup(socket),
      onDone: () => _cleanup(socket),
    );
  }

  void _cleanup(Socket socket) {
    _connections.remove(socket);
    try {
      socket.destroy();
    } catch (_) {}
  }

  void _processBuffer(Socket socket, List<int> buffer) {
    while (true) {
      final total = frameTotalLength(buffer);
      if (total < 0 || buffer.length < total) break;
      final json = extractFrame(buffer);
      buffer.removeRange(0, total);
      if (json == null) {
        _send(socket, encodeError(0, kParseError, 'malformed frame'));
        continue;
      }
      _dispatch(socket, json);
    }
  }

  Future<void> _dispatch(Socket socket, String json) async {
    final request = JsonRpcRequest.tryParse(json);
    if (request == null) {
      _send(socket, encodeError(0, kInvalidRequest, 'invalid JSON-RPC'));
      return;
    }

    final handler = commands[request.method];
    if (handler == null) {
      _send(socket, encodeError(
        request.id, kMethodNotFound, 'unknown method: ${request.method}',
      ));
      return;
    }

    final sw = Stopwatch()..start();
    try {
      final result = await handler(request.params, ctx);
      sw.stop();
      debugPrint('[IPC] ${request.method} → ${sw.elapsedMilliseconds}ms');
      _send(socket, encodeResult(request.id, result));
    } on ArgumentError catch (e) {
      sw.stop();
      debugPrint('[IPC] ${request.method} → error (${sw.elapsedMilliseconds}ms): ${e.message}');
      _send(socket, encodeError(request.id, kInvalidParams, e.message));
    } on StateError catch (e) {
      sw.stop();
      debugPrint('[IPC] ${request.method} → error (${sw.elapsedMilliseconds}ms): ${e.message}');
      _send(socket, encodeError(request.id, kInternalError, e.message));
    } catch (e, st) {
      sw.stop();
      debugPrint('[IPC] ${request.method} → crash (${sw.elapsedMilliseconds}ms): $e\n$st');
      _send(socket, encodeError(request.id, kInternalError, '$e'));
    }
  }

  void _send(Socket socket, String response) {
    try {
      socket.add(frameMessage(response));
    } catch (_) {}
  }

  static Future<Directory> _ipcDir() async {
    final base = await StoragePaths.gdpuDataDir();
    return Directory(p.join(base.path, 'ipc'));
  }

  static Future<void> _cleanStaleLocks(Directory ipcDir) async {
    try {
      await for (final entity in ipcDir.list()) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.lock')) continue;
        try {
          final content = await entity.readAsString();
          final data = jsonDecode(content);
          if (data is Map && data['pid'] is int) {
            final lockPid = data['pid'] as int;
            if (!await _isProcessAlive(lockPid)) {
              await entity.delete();
            }
          }
        } catch (_) {
          try { await entity.delete(); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<bool> _isProcessAlive(int targetPid) async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $targetPid', '/NH', '/FO', 'CSV'],
        );
        return r.stdout.toString().contains('$targetPid');
      } else {
        final r = await Process.run('kill', ['-0', '$targetPid']);
        return r.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }
}
