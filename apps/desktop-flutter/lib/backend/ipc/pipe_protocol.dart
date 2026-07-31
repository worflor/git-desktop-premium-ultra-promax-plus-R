// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:typed_data';

class JsonRpcRequest {
  final String method;
  final Map<String, dynamic> params;
  final dynamic id;

  const JsonRpcRequest({
    required this.method,
    required this.params,
    required this.id,
  });

  static JsonRpcRequest? tryParse(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      final method = decoded['method'];
      if (method is! String || method.isEmpty) return null;
      final params = decoded['params'];
      return JsonRpcRequest(
        method: method,
        params: params is Map<String, dynamic> ? params : const {},
        id: decoded['id'] ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

String encodeResult(dynamic id, Map<String, dynamic> result) {
  return jsonEncode({
    'jsonrpc': '2.0',
    'result': result,
    'id': id,
  });
}

String encodeError(dynamic id, int code, String message) {
  return jsonEncode({
    'jsonrpc': '2.0',
    'error': {'code': code, 'message': message},
    'id': id,
  });
}

const int kParseError = -32700;
const int kInvalidRequest = -32600;
const int kMethodNotFound = -32601;
const int kInvalidParams = -32602;
const int kInternalError = -32603;

Uint8List frameMessage(String json) {
  final bytes = utf8.encode(json);
  final frame = ByteData(4 + bytes.length);
  frame.setUint32(0, bytes.length, Endian.big);
  final out = frame.buffer.asUint8List();
  out.setRange(4, 4 + bytes.length, bytes);
  return out;
}

/// Largest frame the server will ever buffer. A request is a JSON-RPC call;
/// 10 MiB is far past any legitimate one.
const int kMaxFrameBytes = 10 * 1024 * 1024;

/// The result of trying to read one frame off the head of a buffer.
///
/// Sealed, and replacing a PAIR of functions — one that computed `4 + len`
/// with no limit, and one that enforced a limit the first had already
/// ignored. The caller consulted the unbounded one to decide whether to keep
/// buffering, so a peer that declared a 4 GiB frame made the server wait for
/// bytes that would never fit, growing its buffer without bound. The 10 MiB
/// guard was unreachable in precisely the case it existed for.
///
/// One read, one decision, exhaustively switched: a limit that the length
/// calculation cannot disagree with, because there is no second calculation.
sealed class FrameRead {
  const FrameRead();
}

/// Not all here yet — keep buffering.
final class FrameIncomplete extends FrameRead {
  const FrameIncomplete();
}

/// A complete frame. [totalBytes] includes the 4-byte header.
final class FrameReady extends FrameRead {
  final String json;
  final int totalBytes;
  const FrameReady(this.json, this.totalBytes);
}

/// The peer declared a frame larger than [kMaxFrameBytes].
///
/// Not recoverable by skipping: the declared length is the only thing that
/// says where the next frame starts, so a stream that lies about it can no
/// longer be resynchronized. The connection has to go.
final class FrameTooLarge extends FrameRead {
  final int declaredBytes;
  const FrameTooLarge(this.declaredBytes);
}

FrameRead readFrame(List<int> buffer) {
  if (buffer.length < 4) return const FrameIncomplete();
  final len = ByteData.sublistView(Uint8List.fromList(buffer.sublist(0, 4)))
      .getUint32(0, Endian.big);
  if (len > kMaxFrameBytes) return FrameTooLarge(len);
  if (buffer.length < 4 + len) return const FrameIncomplete();
  return FrameReady(
    utf8.decode(buffer.sublist(4, 4 + len), allowMalformed: true),
    4 + len,
  );
}
