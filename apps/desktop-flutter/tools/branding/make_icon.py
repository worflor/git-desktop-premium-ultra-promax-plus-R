#!/usr/bin/env python3
"""Rasterize the Manifold `:]` smiley mark into a multi-resolution Windows ICO.

Source of truth is the hand-tuned geometry in this file (mirrored in
manifold-icon.svg for documentation). Each ICO frame is rendered at 4x
its target size and filtered down with LANCZOS, so even the 16px frame
keeps clean diagonals.

Usage:
    python apps/desktop-flutter/tools/branding/make_icon.py

Output:
    apps/desktop-flutter/windows/runner/resources/app_icon.ico
"""

from __future__ import annotations

import io
import struct
from pathlib import Path

from PIL import Image, ImageDraw

ICO_SIZES = [16, 32, 48, 64, 128, 256]
ACCENT = (0, 229, 255, 255)  # #00E5FF — brand cyan, readable on light + dark

# Geometry expressed in the 256 viewBox; scaled to each frame.
VIEWBOX = 256
EYE_R = 14                        # filled-disc eye radius
LEFT_EYE = (96, 96)               # (cx, cy)
RIGHT_EYE = (160, 96)
# Angular bracket-smile — corners high, base flat. Matches the `]`
# register vs a curved `:)` smile. Path read as polyline.
SMILE = [(80, 156), (100, 184), (156, 184), (176, 156)]
STROKE_AT_256 = 10                 # px at the 256 viewBox

# Render super-sample factor. 4x is the sweet spot — enough to clean
# antialias pixel-aligned diagonals without quadrupling render time.
SUPERSAMPLE = 4


def _scale(coord: float, size: int) -> float:
    return coord * size / VIEWBOX


def _render(size: int) -> Image.Image:
    """Larger frames render at 4x supersample + LANCZOS for clean
    diagonals. Tiny frames (≤ 32) bypass supersampling entirely:
    sub-pixel anti-aliasing on a 16-px canvas dissolves into greys
    that read as noise. At those sizes we render at native size with
    pixel-aligned strokes — slightly crunchier diagonals, hugely
    better legibility.
    """
    if size <= 32:
        return _render_crisp(size)
    return _render_smooth(size)


def _render_smooth(size: int) -> Image.Image:
    canvas_size = size * SUPERSAMPLE
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    stroke = max(SUPERSAMPLE, round(_scale(STROKE_AT_256, canvas_size)))

    def s(c: float) -> float:
        return _scale(c, canvas_size)

    # Eyes — filled discs.
    eye_r = s(EYE_R)
    for cx, cy in (LEFT_EYE, RIGHT_EYE):
        draw.ellipse(
            (s(cx) - eye_r, s(cy) - eye_r, s(cx) + eye_r, s(cy) + eye_r),
            fill=ACCENT,
        )

    # Smile — polyline with rounded joins (drawn as connected line
    # segments; PIL's `line` caps each end with a round dot at this
    # scale, so the corners read as smoothly joined after LANCZOS).
    pts = [(s(x), s(y)) for x, y in SMILE]
    for a, b in zip(pts, pts[1:]):
        draw.line([a, b], fill=ACCENT, width=stroke)
    # Round dots at every joint to hide the polyline corners.
    half = stroke / 2
    for x, y in pts:
        draw.ellipse((x - half, y - half, x + half, y + half), fill=ACCENT)

    return img.resize((size, size), Image.LANCZOS)


def _render_crisp(size: int) -> Image.Image:
    """Native-size render for tiny frames. Snaps geometry to pixel
    boundaries so the smiley stays readable at 16- and 32-px taskbar
    sizes. Eyes shrink to 1-2 px discs and the smile collapses to a
    thin polyline — barely-there but still parseable as a face.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def s(c: float) -> int:
        # Snap to integer pixels — sub-pixel features smear at this scale.
        return round(c * size / VIEWBOX)

    # Eye radius scales with frame; floor at 1 so 16-px doesn't lose them.
    eye_r = max(1, round(EYE_R * size / VIEWBOX))
    for cx, cy in (LEFT_EYE, RIGHT_EYE):
        x, y = s(cx), s(cy)
        draw.ellipse((x - eye_r, y - eye_r, x + eye_r, y + eye_r), fill=ACCENT)

    pts = [(s(x), s(y)) for x, y in SMILE]
    for a, b in zip(pts, pts[1:]):
        draw.line([a, b], fill=ACCENT, width=1)

    return img


def _png_bytes(image: Image.Image) -> bytes:
    """Encode `image` as PNG and return the raw bytes. Modern ICO
    readers (Vista+) accept embedded PNG payloads — smaller files than
    the legacy DIB encoding, and 1:1 pixels with what the renderer
    produced (no second-pass downsampling)."""
    buf = io.BytesIO()
    image.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def _write_ico(path: Path, frames: list[tuple[int, bytes]]) -> None:
    """Hand-roll a multi-size ICO so each frame can be rendered
    independently with our supersample + LANCZOS pipeline. Pillow's
    own ICO saver downsamples a single source for every requested
    size, which makes the 16- and 32-px frames look mushy.

    Layout (little-endian):
        header       : reserved(2)=0, type(2)=1, count(2)
        directory[N] : 16 bytes per frame (size, color-info, offset)
        body         : concatenated PNG payloads in directory order
    """
    count = len(frames)
    header = struct.pack("<HHH", 0, 1, count)

    directory_bytes = 6 + 16 * count
    offset = directory_bytes
    entries = b""
    for size, png in frames:
        # ICO encodes 256 as 0 in the size byte.
        encoded = 0 if size == 256 else size
        entries += struct.pack(
            "<BBBBHHII",
            encoded,           # width
            encoded,           # height
            0,                 # color count (0 = >=256)
            0,                 # reserved
            1,                 # color planes
            32,                # bits per pixel (RGBA)
            len(png),          # bytes in payload
            offset,            # offset from file start
        )
        offset += len(png)

    body = b"".join(png for _, png in frames)
    path.write_bytes(header + entries + body)


def main() -> None:
    here = Path(__file__).resolve().parent
    out = (
        here.parent.parent
        / "windows"
        / "runner"
        / "resources"
        / "app_icon.ico"
    )
    out.parent.mkdir(parents=True, exist_ok=True)

    frames = [(s, _png_bytes(_render(s))) for s in ICO_SIZES]
    _write_ico(out, frames)
    print(f"wrote {out} ({', '.join(str(s) for s in ICO_SIZES)})")


if __name__ == "__main__":
    main()
