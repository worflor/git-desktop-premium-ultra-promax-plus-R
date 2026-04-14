// ═════════════════════════════════════════════════════════════════════════
// bond/invite.dart — sharable invite blob for "send this to your peer"
//
// An invite is NOT a credential. It carries the *public* inputs needed
// to re-derive the bond_id: bootstrap commit hash + optional display
// name. The swarm phrase is explicitly NOT in the invite — peers still
// have to exchange it out-of-band (voice, Signal, in person). That
// split preserves the property that a leaked invite link can't let
// anyone join the swarm by itself.
//
// Wire format, version 1:
//
//   magic    "bond1" (5 bytes ASCII)
//   version  u8      (0x01)
//   bondId   32 bytes
//   bootLen  u8      (20 for SHA-1, 32 for SHA-256)
//   bootstr  boot_len bytes
//   nameLen  u8      (0..64)
//   name     name_len bytes utf-8
//   crc16    u16 big-endian over everything above
//
// Encoded with URL-safe base64 (no padding), prefixed `bond1:`.
// Example: `bond1:AQIDBAUGB...`
// ═════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';

import 'bond_id.dart';

/// Decoded invite payload. Construct via [BondInvite.decode] or via
/// [BondInvite.build] when a user creates an invite to share.
class BondInvite {
  BondInvite({
    required this.bondId,
    required this.bootstrapCommit,
    required this.displayName,
  });

  final BondId bondId;

  /// Hex commit hash. Always lowercase.
  final String bootstrapCommit;

  /// Optional human label. Empty string when the author didn't set one.
  final String displayName;

  /// Encodes this invite to the `bond1:...` shareable form.
  String encode() {
    final bootBytes = _unhex(bootstrapCommit);
    if (bootBytes.length != 20 && bootBytes.length != 32) {
      throw ArgumentError(
        'bootstrap commit must be SHA-1 (20B) or SHA-256 (32B) hex',
      );
    }
    final nameBytes = utf8.encode(displayName);
    if (nameBytes.length > 64) {
      throw ArgumentError('display name exceeds 64 bytes utf-8');
    }
    final body = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_version)
      ..add(bondId.bytes)
      ..addByte(bootBytes.length)
      ..add(bootBytes)
      ..addByte(nameBytes.length)
      ..add(nameBytes);
    final raw = body.toBytes();
    final crc = _crc16(raw);
    final full = Uint8List(raw.length + 2);
    full.setRange(0, raw.length, raw);
    full[raw.length] = (crc >> 8) & 0xff;
    full[raw.length + 1] = crc & 0xff;
    return '$_prefix${base64UrlEncode(full).replaceAll('=', '')}';
  }

  /// Parses a `bond1:...` string. Throws [FormatException] with a
  /// user-friendly message on any shape / checksum failure.
  static BondInvite decode(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith(_prefix)) {
      throw const FormatException('not a bond invite (missing bond1: prefix)');
    }
    final encoded = trimmed.substring(_prefix.length);
    // Base64 decoder requires padding; restore it.
    final padded = encoded + '=' * ((4 - encoded.length % 4) % 4);
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(padded);
    } catch (_) {
      throw const FormatException('invite body is not valid base64url');
    }
    if (bytes.length < _magic.length + 1 + 32 + 1 + 20 + 1 + 2) {
      throw const FormatException('invite body too short');
    }
    // Checksum first — fast reject on corruption.
    final crcGiven = (bytes[bytes.length - 2] << 8) | bytes[bytes.length - 1];
    final crcCalc = _crc16(
      Uint8List.sublistView(bytes, 0, bytes.length - 2),
    );
    if (crcGiven != crcCalc) {
      throw const FormatException('invite checksum mismatch (copy truncated?)');
    }
    var cursor = 0;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[cursor++] != _magic[i]) {
        throw const FormatException('wrong magic bytes');
      }
    }
    final version = bytes[cursor++];
    if (version != _version) {
      throw FormatException('unsupported invite version $version');
    }
    final bondBytes = Uint8List.fromList(
      Uint8List.sublistView(bytes, cursor, cursor + 32),
    );
    cursor += 32;
    final bootLen = bytes[cursor++];
    if (bootLen != 20 && bootLen != 32) {
      throw const FormatException('bootstrap hash length must be 20 or 32');
    }
    final bootBytes = Uint8List.sublistView(bytes, cursor, cursor + bootLen);
    cursor += bootLen;
    final nameLen = bytes[cursor++];
    if (nameLen > 64) {
      throw const FormatException('display name length > 64');
    }
    if (cursor + nameLen + 2 != bytes.length) {
      throw const FormatException('trailing bytes mismatch');
    }
    final name = utf8.decode(
      Uint8List.sublistView(bytes, cursor, cursor + nameLen),
      allowMalformed: false,
    );
    return BondInvite(
      bondId: BondId.fromBytes(bondBytes),
      bootstrapCommit: _hex(bootBytes),
      displayName: name,
    );
  }
}

const String _prefix = 'bond1:';
const List<int> _magic = [98, 111, 110, 100, 49]; // "bond1"
const int _version = 1;

String _hex(Uint8List b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String hex) {
  final norm = hex.trim().toLowerCase();
  if (norm.length % 2 != 0) {
    throw ArgumentError('hex length must be even');
  }
  final out = Uint8List(norm.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(norm.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// CRC-16/CCITT-FALSE. Standard short checksum for copy-paste
/// integrity; detects single-bit flips and most truncations. Not
/// crypto — Ed25519 on the envelope is the security layer.
int _crc16(Uint8List data) {
  var crc = 0xFFFF;
  for (final b in data) {
    crc ^= b << 8;
    for (var i = 0; i < 8; i++) {
      if ((crc & 0x8000) != 0) {
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
      } else {
        crc = (crc << 1) & 0xFFFF;
      }
    }
  }
  return crc;
}
