// ═════════════════════════════════════════════════════════════════════════
// bond/identicon.dart — deterministic visual fingerprint for a pubkey
//
// Unlabelled peers in the UI render with a fingerprint string + a
// small geometric sprite derived from their pubkey. The sprite makes
// two pubkeys visually distinguishable at a glance (hex fingerprints
// all look alike at peripheral vision) without any network call or
// user-provided avatar.
//
// Algorithm: 5×5 symmetric grid, first 15 bytes of the pubkey hash
// drive the cell fills; the remaining hash bytes choose the hue.
// Symmetric left-right so the shape reads as an intentional glyph
// rather than noise. Same algorithm GitHub uses for account
// identicons; no novelty here, just a well-understood primitive.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pointycastle/digests/sha256.dart';

/// Deterministic identicon. Pure function of the pubkey bytes;
/// no state. Cache the rendered image at call sites if performance
/// matters — this recomputes on every paint otherwise.
class BondIdenticon extends StatelessWidget {
  const BondIdenticon({
    super.key,
    required this.pubkey,
    this.size = 24,
    this.background,
  });

  /// The 32-byte Ed25519 public key to visualise. Any length works
  /// — only the first 16 bytes of its SHA-256 are used — but 32 is
  /// the canonical case.
  final Uint8List pubkey;

  /// Side length in logical pixels.
  final double size;

  /// Optional background tint. Defaults to transparent so the sprite
  /// can overlay the ambient theme.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _IdenticonPainter(
        pubkey: pubkey,
        background: background ?? const Color(0x00000000),
      ),
    );
  }
}

class _IdenticonPainter extends CustomPainter {
  _IdenticonPainter({required this.pubkey, required this.background});

  final Uint8List pubkey;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final hash = _syncSha256(pubkey);
    // Hue from bytes 15,16 (the tail of the 16-byte window used for
    // cells). Saturation + lightness fixed so every identicon has
    // comparable visual weight; only hue varies.
    final hue = ((hash[15] << 8) | hash[16]) % 360;
    final fill = _hslToRgb(hue.toDouble(), 0.60, 0.55);

    if (background.a > 0) {
      final bg = Paint()..color = background;
      canvas.drawRect(Offset.zero & size, bg);
    }
    final cell = size.width / 5.0;
    final paint = Paint()..color = fill;

    // 5 columns × 5 rows, but we only decide the 3 leftmost columns
    // and mirror into the right two. 15 cells → 15 bits from the
    // first 15 hash bytes (take the high bit of each).
    for (var col = 0; col < 3; col++) {
      for (var row = 0; row < 5; row++) {
        final idx = col * 5 + row;
        final on = (hash[idx] & 0x80) != 0;
        if (!on) continue;
        // Left cell.
        canvas.drawRect(
          Rect.fromLTWH(col * cell, row * cell, cell + 0.5, cell + 0.5),
          paint,
        );
        // Mirror into the right-hand side. Column 2 is the axis; 1↔3,
        // 0↔4.
        if (col < 2) {
          canvas.drawRect(
            Rect.fromLTWH((4 - col) * cell, row * cell,
                cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_IdenticonPainter old) {
    if (old.pubkey.length != pubkey.length) return true;
    for (var i = 0; i < pubkey.length; i++) {
      if (old.pubkey[i] != pubkey[i]) return true;
    }
    return old.background.toARGB32() != background.toARGB32();
  }
}

/// HSL → RGB conversion. Input hue in degrees [0, 360), s + l in
/// [0, 1]. Standard formula; avoids pulling in a color library for
/// this one conversion.
Color _hslToRgb(double h, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - c / 2;
  double r, g, b;
  if (h < 60) {
    r = c;
    g = x;
    b = 0;
  } else if (h < 120) {
    r = x;
    g = c;
    b = 0;
  } else if (h < 180) {
    r = 0;
    g = c;
    b = x;
  } else if (h < 240) {
    r = 0;
    g = x;
    b = c;
  } else if (h < 300) {
    r = x;
    g = 0;
    b = c;
  } else {
    r = c;
    g = 0;
    b = x;
  }
  return Color.fromARGB(
    0xff,
    ((r + m) * 255).round().clamp(0, 255),
    ((g + m) * 255).round().clamp(0, 255),
    ((b + m) * 255).round().clamp(0, 255),
  );
}

/// Synchronous SHA-256 via `pointycastle`. The paint cycle can't
/// await, and the `cryptography` package's async-only API is a
/// mismatch here. PointyCastle's `SHA256Digest` is pure Dart and
/// cheap; identicon input is ≤32 bytes so hashing is sub-microsecond.
Uint8List _syncSha256(Uint8List data) {
  final digest = SHA256Digest();
  final out = Uint8List(digest.digestSize);
  digest.update(data, 0, data.length);
  digest.doFinal(out, 0);
  return out;
}
