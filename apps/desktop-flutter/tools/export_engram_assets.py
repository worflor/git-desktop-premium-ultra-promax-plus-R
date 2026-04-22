#!/usr/bin/env python3
"""Export Alexandria engram + filtered GloVe to compact Dart-loadable assets.

Alexandria's original `.engram` file is a ZIP containing wells.bin + dream.bin
+ manifest.json + annotations.json. The `.endb` asset is a faithful flat-binary
re-serialisation of *everything* the ZIP carries — not a slim projection.

.endb layout (little-endian, version 2):

    magic[4]  = "ENDB"
    version   u32 = 2
    dim       u32
    pairs     u32                (= dim // 2)
    n_wells   u32
    flags     u32
        bit 0: has_sum_raw       (per-well sum_raw float64[L] follows each sum_K)
        bit 1: has_dream         (dream buffer present)
        bit 2: has_annotations   (annotations JSON present)
        bit 3: has_manifest      (full source manifest JSON present)
    pairing   int16[dim]

    per well:
        name_len u16
        name     utf-8[name_len]
        count    u32
        sum_K    complex128[pairs]  (re f64 + im f64 interleaved)
        [if has_sum_raw]:
            sum_raw_len u32          (byte length)
            sum_raw     float64[sum_raw_len / 8]

    [if has_dream]:
        n_dream u32
        per entry (complex64 K/G to match alexandria's v0 dream.bin):
            K  float32[pairs * 2]    (re,im interleaved)
            G  float32[pairs * 2]    (re,im interleaved)
            S  float32[pairs]

    [if has_annotations]:
        annot_len u32
        annot     utf-8[annot_len]

    [if has_manifest]:
        manifest_len u32
        manifest     utf-8[manifest_len]

Version 1 is still accepted by the Dart reader for backward compatibility;
v2 supersedes it and carries the full `.engram` payload so downstream
consumers (dream introspection, annotation voice, raw sum audit) can read
directly from the bundled asset without needing the original ZIP.

The GloVe export filters the 20k mini vocab to lowercase alpha tokens and
supplements missing programming-specific terms from the full 6B vocab,
int16-quantises with a global scale = 6.0 (max abs err ~1e-4), and writes
a "GLV1" binary:

    magic[4]   = "GLV1"
    version    u32 = 1
    n_tokens   u32
    dim        u32
    scale      f32
    vocab: [u8 len][utf8 bytes] per token (row-index order)
    vectors: int16[n_tokens][dim] row-major

Run this from the repo root after a new alexandria.engram is trained. The
outputs land in `apps/desktop-flutter/assets/engram/`.
"""

import pickle
import struct
import os
import sys
import json
import zipfile

import numpy as np

# ─────────────────────────────────────────────────────────────────────────
# Paths — adjust if the engram project moves.
# ─────────────────────────────────────────────────────────────────────────

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
ASSETS_DIR = os.path.join(REPO_ROOT, 'assets', 'engram')

ALEXANDRIA_SRC = os.environ.get(
    'ALEXANDRIA_ENGRAM',
    'C:/Users/mini server/Downloads/alexandria.engram',
)
GLOVE_MINI = os.environ.get(
    'GLOVE_MINI_PKL',
    'C:/Users/mini server/Documents/Projects/worflor.github.io/rag_tests/engram/cache/_glove_cache/glove_mini_20k.pkl',
)
GLOVE_FULL = os.environ.get(
    'GLOVE_FULL_PKL',
    'C:/Users/mini server/Documents/Projects/worflor.github.io/rag_tests/engram/cache/_glove_cache/glove.6B.300d.txt.pkl',
)


# .endb flags.
FLAG_HAS_SUM_RAW     = 1 << 0
FLAG_HAS_DREAM       = 1 << 1
FLAG_HAS_ANNOTATIONS = 1 << 2
FLAG_HAS_MANIFEST    = 1 << 3

# sum_raw length per well in the alexandria v0 wells.bin. Stored so we can
# round-trip it verbatim.
V0_SUM_RAW_LEN_F64 = 256
V0_SUM_RAW_BYTES   = V0_SUM_RAW_LEN_F64 * 8


def _parse_v0_wells(wells_data: bytes, dim: int, pairs: int):
    """Parse the v0 alexandria wells.bin. Returns (pairing_bytes, wells_list).

    Each well in the returned list is a dict with keys: name_bytes (bytes),
    count (int), sum_k_bytes (bytes, len == pairs*16), sum_raw_bytes (bytes,
    len == 2048). The layout matches the exporter's original parse logic
    but preserves sum_raw instead of discarding it.
    """
    off = 0
    pairing = wells_data[off:off + dim * 2]; off += dim * 2
    (n_wells,) = struct.unpack_from('<I', wells_data, off); off += 4

    wells = []
    for _ in range(n_wells):
        (name_len,) = struct.unpack_from('<H', wells_data, off); off += 2
        name_bytes = wells_data[off:off + name_len]; off += name_len
        sum_k_bytes = wells_data[off:off + pairs * 16]; off += pairs * 16
        sum_raw_bytes = wells_data[off:off + V0_SUM_RAW_BYTES]
        off += V0_SUM_RAW_BYTES
        (count,) = struct.unpack_from('<I', wells_data, off); off += 4
        wells.append({
            'name_bytes': name_bytes,
            'count': count,
            'sum_k_bytes': sum_k_bytes,
            'sum_raw_bytes': sum_raw_bytes,
        })

    assert off == len(wells_data), f'bad wells parse: {off} != {len(wells_data)}'
    return pairing, wells


def _parse_v0_dream(dream_data: bytes, pairs: int):
    """Parse the v0 alexandria dream.bin.

    Layout: [n_entries u32] + per entry: [K complex64[pairs]][G
    complex64[pairs]][S float32[pairs]]. Returns the raw bytes re-emitted
    as a tight blob (n_entries u32 + entries). Entry bytes are passed
    through verbatim — the consumer parses on demand.
    """
    if len(dream_data) < 4:
        return 0, b''
    (n_entries,) = struct.unpack_from('<I', dream_data, 0)
    entry_bytes = pairs * 8 + pairs * 8 + pairs * 4  # K + G + S
    expected = 4 + n_entries * entry_bytes
    if len(dream_data) != expected:
        # Unknown dream.bin variant — skip rather than embed broken data.
        print(f'  warn: dream.bin size mismatch '
              f'(got {len(dream_data)}, expected {expected} for '
              f'n_entries={n_entries} pairs={pairs}); skipping')
        return 0, b''
    # Re-emit verbatim: 4-byte count + rest.
    return n_entries, dream_data[4:]


def export_alexandria():
    out_bin = os.path.join(ASSETS_DIR, 'alexandria.endb')
    out_meta = os.path.join(ASSETS_DIR, 'alexandria.manifest.json')

    with zipfile.ZipFile(ALEXANDRIA_SRC) as z:
        names = set(z.namelist())
        manifest_bytes = z.read('manifest.json')
        manifest = json.loads(manifest_bytes)
        wells_data = z.read('wells.bin')
        dream_data = z.read('dream.bin') if 'dream.bin' in names else b''
        annot_bytes = z.read('annotations.json') if 'annotations.json' in names else b''

    dim = manifest['physics']['dim']
    pairs = dim // 2
    assert dim % 2 == 0, f'dim must be even, got {dim}'

    pairing_bytes, wells = _parse_v0_wells(wells_data, dim, pairs)

    # Build flags and optional payloads.
    flags = FLAG_HAS_SUM_RAW | FLAG_HAS_MANIFEST
    if annot_bytes:
        flags |= FLAG_HAS_ANNOTATIONS

    n_dream = 0
    dream_blob = b''
    if dream_data:
        n_dream, dream_blob = _parse_v0_dream(dream_data, pairs)
        if n_dream > 0:
            flags |= FLAG_HAS_DREAM

    out = bytearray()
    out += b'ENDB'
    out += struct.pack('<I', 2)              # version
    out += struct.pack('<I', dim)
    out += struct.pack('<I', pairs)
    out += struct.pack('<I', len(wells))
    out += struct.pack('<I', flags)
    out += pairing_bytes

    for w in wells:
        out += struct.pack('<H', len(w['name_bytes']))
        out += w['name_bytes']
        out += struct.pack('<I', w['count'])
        out += w['sum_k_bytes']
        # sum_raw is stored length-prefixed so future versions can vary it.
        out += struct.pack('<I', len(w['sum_raw_bytes']))
        out += w['sum_raw_bytes']

    if flags & FLAG_HAS_DREAM:
        out += struct.pack('<I', n_dream)
        out += dream_blob

    if flags & FLAG_HAS_ANNOTATIONS:
        out += struct.pack('<I', len(annot_bytes))
        out += annot_bytes

    if flags & FLAG_HAS_MANIFEST:
        out += struct.pack('<I', len(manifest_bytes))
        out += manifest_bytes

    os.makedirs(ASSETS_DIR, exist_ok=True)
    with open(out_bin, 'wb') as f:
        f.write(bytes(out))

    slim_manifest = {
        'format': 'endb',
        'version': 2,
        'dim': dim,
        'pairs': pairs,
        'n_wells': len(wells),
        'flags': flags,
        'has_sum_raw': bool(flags & FLAG_HAS_SUM_RAW),
        'has_dream': bool(flags & FLAG_HAS_DREAM),
        'n_dream': n_dream,
        'has_annotations': bool(flags & FLAG_HAS_ANNOTATIONS),
        'has_manifest': bool(flags & FLAG_HAS_MANIFEST),
        'source_manifest': manifest,
    }
    with open(out_meta, 'w') as f:
        json.dump(slim_manifest, f, indent=2)

    size_mb = os.path.getsize(out_bin) / 1024 / 1024
    flag_desc = []
    if flags & FLAG_HAS_SUM_RAW:     flag_desc.append('sum_raw')
    if flags & FLAG_HAS_DREAM:       flag_desc.append(f'dream({n_dream})')
    if flags & FLAG_HAS_ANNOTATIONS: flag_desc.append('annotations')
    if flags & FLAG_HAS_MANIFEST:    flag_desc.append('manifest')
    print(f'engram: {len(wells)} wells, dim={dim} pairs={pairs} '
          f'[{", ".join(flag_desc)}] -> {out_bin} ({size_mb:.2f} MB)')


def export_glove():
    out = os.path.join(ASSETS_DIR, 'glove300.bin')

    with open(GLOVE_MINI, 'rb') as f:
        mini = pickle.load(f)

    keep = {}
    for k, v in mini.items():
        if len(k) < 2 or len(k) > 32:
            continue
        if not k.isalpha() or not k.isascii() or not k.islower():
            continue
        keep[k] = v

    # Programming-specific supplementals. Most common code sub-tokens that
    # aren't in the top 20k general English frequency list.
    code_words = [
        'delete', 'parse', 'init', 'validate', 'emit', 'config', 'query',
        'deserialize', 'serialize', 'migrate', 'transpile', 'compile', 'bundle',
        'normalize', 'sanitize', 'stringify', 'flatten', 'aggregate', 'pipe',
        'hydrate', 'dehydrate', 'route', 'dispatch', 'trigger', 'listen',
        'subscribe', 'publish', 'bind', 'unbind', 'observe', 'invoke',
        'resolve', 'reject', 'pending', 'retry', 'debounce', 'throttle',
        'mount', 'unmount', 'detach', 'attach', 'lifecycle', 'reducer',
        'traverse', 'visit', 'walk', 'iterate', 'enumerate',
        'auth', 'oauth', 'hash', 'crypto', 'cipher', 'encrypt', 'decrypt',
        'digest', 'nonce', 'payload', 'header', 'body', 'footer',
        'diff', 'patch', 'hunk', 'chunk', 'blob', 'tree', 'ref',
        'rebase', 'merge', 'squash', 'cherry', 'stash', 'worktree',
        'repo', 'fork', 'clone', 'branch', 'tag', 'remote', 'upstream',
        'docker', 'kubernetes', 'kubectl', 'helm', 'terraform', 'ansible',
        'lambda', 'api', 'rest', 'graphql', 'grpc', 'websocket',
        'json', 'yaml', 'toml', 'xml', 'csv', 'parquet', 'protobuf',
        'sql', 'nosql', 'redis', 'postgres', 'sqlite', 'mongodb',
        'component', 'widget', 'render', 'reflow', 'repaint', 'viewport',
        'dpi', 'pixel', 'layout', 'flex', 'grid', 'sprite', 'shader',
        'flutter', 'dart', 'pubspec', 'riverpod', 'provider', 'bloc',
        'fetch', 'poll', 'sync', 'async', 'await', 'yield', 'spawn',
        'engram', 'centroid', 'eigenvalue', 'cosine', 'jaccard', 'laplacian',
        'diffusion', 'kernel', 'manifold', 'embedding', 'vector', 'tensor',
    ]
    short_tokens = ['id', 'io', 'os', 'ip', 'ui', 'ux', 'ok', 'db']

    print(f'mini filter: {len(keep)}')
    print('loading full glove 6B...')
    with open(GLOVE_FULL, 'rb') as f:
        full = pickle.load(f)
    print(f'full vocab: {len(full)}')
    added = 0
    for w in code_words + short_tokens:
        if w in full and w not in keep:
            keep[w] = full[w]
            added += 1
    print(f'added {added} programming words; total: {len(keep)}')

    sorted_keys = sorted(keep.keys())
    scale = 6.0
    M = np.stack([keep[k] for k in sorted_keys]).astype(np.float32)
    q = np.clip(np.round(M / scale * 32767), -32768, 32767).astype(np.int16)

    os.makedirs(ASSETS_DIR, exist_ok=True)
    with open(out, 'wb') as f:
        f.write(b'GLV1')
        f.write(struct.pack('<I', 1))
        f.write(struct.pack('<I', len(sorted_keys)))
        f.write(struct.pack('<I', 300))
        f.write(struct.pack('<f', scale))
        for tok in sorted_keys:
            b = tok.encode('utf-8')
            assert len(b) < 256
            f.write(struct.pack('<B', len(b)))
            f.write(b)
        f.write(q.tobytes())

    size_mb = os.path.getsize(out) / 1024 / 1024
    print(f'glove: {len(sorted_keys)} tokens -> {out} ({size_mb:.2f} MB)')


if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if target in ('all', 'engram'):
        export_alexandria()
    if target in ('all', 'glove'):
        export_glove()
