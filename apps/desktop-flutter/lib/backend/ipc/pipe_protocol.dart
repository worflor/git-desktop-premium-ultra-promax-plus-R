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

String? extractFrame(List<int> buffer) {
  if (buffer.length < 4) return null;
  final len = ByteData.sublistView(Uint8List.fromList(buffer.sublist(0, 4)))
      .getUint32(0, Endian.big);
  if (len > 10 * 1024 * 1024) return null;
  if (buffer.length < 4 + len) return null;
  return utf8.decode(buffer.sublist(4, 4 + len), allowMalformed: true);
}

int frameTotalLength(List<int> buffer) {
  if (buffer.length < 4) return -1;
  final len = ByteData.sublistView(Uint8List.fromList(buffer.sublist(0, 4)))
      .getUint32(0, Endian.big);
  return 4 + len;
}
