// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// pipe_protocol_test.dart — the IPC wire framing.
//
// Found by pointing Manifold's own history review at the commit that
// introduced the IPC rig. The framing was split across two functions: one
// computed `4 + declaredLength` with no limit, the other enforced a 10 MiB
// limit. The server consulted the UNBOUNDED one to decide whether to keep
// buffering, so the guard was unreachable in exactly the case it existed
// for — a peer declaring an enormous frame made the server buffer forever.
//
// These drive the framing directly, including a frame that claims to be 4 GiB.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ipc/pipe_protocol.dart';

/// A wire frame: 4-byte big-endian length, then the payload.
List<int> frame(String json) => frameMessage(json).toList();

/// A header that CLAIMS [declared] bytes, followed by [actual] bytes of body.
/// The shape a hostile or broken peer produces.
List<int> lyingFrame(int declared, {int actual = 0}) {
  final header = ByteData(4)..setUint32(0, declared, Endian.big);
  return [...header.buffer.asUint8List(), ...List.filled(actual, 0x20)];
}

void main() {
  test('P1: a complete frame reads back exactly, header included in the '
      'consumed length', () {
    const payload = '{"jsonrpc":"2.0","method":"ping","id":1}';
    final buffer = frame(payload);
    final read = readFrame(buffer);

    expect(read, isA<FrameReady>());
    final ready = read as FrameReady;
    expect(ready.json, payload);
    expect(ready.totalBytes, buffer.length);
    expect(ready.totalBytes, 4 + utf8.encode(payload).length,
        reason: 'the consumed length must cover the header, or the next '
            'frame starts mid-stream');
  });

  test('P2: a partial frame asks for more rather than guessing', () {
    final full = frame('{"a":1}');
    for (var cut = 0; cut < full.length; cut++) {
      expect(readFrame(full.sublist(0, cut)), isA<FrameIncomplete>(),
          reason: 'truncated at $cut of ${full.length} bytes');
    }
    expect(readFrame(full), isA<FrameReady>());
  });

  test('P3: a header alone is incomplete, not a zero-length frame', () {
    expect(readFrame(lyingFrame(50)), isA<FrameIncomplete>());
    // ...but a genuinely empty payload IS a complete frame.
    final empty = readFrame(lyingFrame(0));
    expect(empty, isA<FrameReady>());
    expect((empty as FrameReady).json, isEmpty);
    expect(empty.totalBytes, 4);
  });

  test('P4: an over-limit frame is REFUSED, never buffered toward', () {
    // The bug: this case used to be indistinguishable from "keep waiting".
    // 4 GiB - 1, the largest a uint32 length can express.
    const huge = 0xFFFFFFFF;
    final read = readFrame(lyingFrame(huge, actual: 16));

    expect(read, isA<FrameTooLarge>(),
        reason: 'a declared length past the cap must be its own answer; '
            'reported as "incomplete" the server waits for 4 GiB that will '
            'never come, growing its buffer with every chunk');
    expect((read as FrameTooLarge).declaredBytes, huge);
  });

  test('P5: the limit is enforced at the boundary, not near it', () {
    // One byte over is refused even though nothing about the buffer changed.
    expect(readFrame(lyingFrame(kMaxFrameBytes + 1)), isA<FrameTooLarge>());
    // Exactly at the limit is legal, and still incomplete until the body
    // arrives — the size check must not swallow the completeness check.
    expect(readFrame(lyingFrame(kMaxFrameBytes)), isA<FrameIncomplete>());
  });

  test('P6: the refusal does not depend on how much body arrived', () {
    // Whether the peer sends nothing or a megabyte after the lying header,
    // the answer is the same. Anything else would let a slow trickle keep
    // the connection alive while the buffer grows.
    for (final actual in const [0, 1, 4096, 100000]) {
      expect(readFrame(lyingFrame(kMaxFrameBytes * 4, actual: actual)),
          isA<FrameTooLarge>(),
          reason: 'with $actual bytes of body');
    }
  });

  test('P7: back-to-back frames consume exactly their own bytes', () {
    // The consumed-length contract, which is what keeps a stream aligned.
    final a = frame('{"id":1}');
    final b = frame('{"id":2}');
    final stream = [...a, ...b];

    final first = readFrame(stream) as FrameReady;
    expect(first.json, '{"id":1}');
    expect(first.totalBytes, a.length);

    final rest = stream.sublist(first.totalBytes);
    final second = readFrame(rest) as FrameReady;
    expect(second.json, '{"id":2}');
    expect(second.totalBytes, b.length);
    expect(rest.sublist(second.totalBytes), isEmpty);
  });

  test('P8: a malformed UTF-8 body is decoded leniently, not thrown on', () {
    // A parse error belongs to the JSON-RPC layer, which answers it. Throwing
    // here would take the connection down for a recoverable request.
    final header = ByteData(4)..setUint32(0, 3, Endian.big);
    final read = readFrame([
      ...header.buffer.asUint8List(),
      0xFF, 0xFE, 0xFD,
    ]);
    expect(read, isA<FrameReady>());
    expect((read as FrameReady).totalBytes, 7);
  });
}
