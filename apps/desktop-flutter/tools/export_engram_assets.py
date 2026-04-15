#!/usr/bin/env python3
"""Export Alexandria engram + filtered GloVe to compact Dart-loadable assets.

Alexandria's original `.engram` file is a ZIP containing wells.bin + dream.bin
+ manifest.json + annotations.json. For the Flutter app we only need the
reference pairing and per-well K-space centroids, so we re-serialise into
a flat `.endb` (Engram Dart Brain) binary:

    magic[4]  = "ENDB"
    version   u32 = 1
    dim       u32
    pairs     u32
    n_wells   u32
    pairing   int16[dim]
    per well:
        name_len u16
        name     utf-8[name_len]
        count    u32
        sum_K    complex128[pairs]  (re f64 + im f64 interleaved)

(We drop the `sum_raw` float64[256] that Alexandria carries per well —
nearest-well in K-space only needs sum_K; skipping sum_raw cuts the asset
~2KB per well, ~0.5MB total for 225 wells.)

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


def export_alexandria():
    out_bin = os.path.join(ASSETS_DIR, 'alexandria.endb')
    out_meta = os.path.join(ASSETS_DIR, 'alexandria.manifest.json')

    with zipfile.ZipFile(ALEXANDRIA_SRC) as z:
        manifest = json.loads(z.read('manifest.json'))
        wells_data = z.read('wells.bin')

    dim = manifest['physics']['dim']
    P = dim // 2
    assert dim % 2 == 0, f'dim must be even, got {dim}'

    # Parse source wells.bin
    #   [pairing int16[dim]][n_wells u32][per well: name_len u16, name,
    #    sum_K complex128[P], sum_raw float64[256], count u32]
    off = 0
    pairing = wells_data[off:off + dim * 2]; off += dim * 2
    n_wells, = struct.unpack_from('<I', wells_data, off); off += 4

    out = bytearray()
    out += b'ENDB'
    out += struct.pack('<I', 1)
    out += struct.pack('<I', dim)
    out += struct.pack('<I', P)
    out += struct.pack('<I', n_wells)
    out += pairing

    for _ in range(n_wells):
        name_len, = struct.unpack_from('<H', wells_data, off); off += 2
        name = wells_data[off:off + name_len]; off += name_len
        sum_k_bytes = wells_data[off:off + P * 16]; off += P * 16
        off += 256 * 8  # skip sum_raw
        count, = struct.unpack_from('<I', wells_data, off); off += 4

        out += struct.pack('<H', name_len)
        out += name
        out += struct.pack('<I', count)
        out += sum_k_bytes

    assert off == len(wells_data), f'bad parse: {off} != {len(wells_data)}'

    os.makedirs(ASSETS_DIR, exist_ok=True)
    with open(out_bin, 'wb') as f:
        f.write(bytes(out))

    slim_manifest = {
        'format': 'endb',
        'version': 1,
        'dim': dim,
        'pairs': P,
        'n_wells': n_wells,
        'source_manifest': manifest,
    }
    with open(out_meta, 'w') as f:
        json.dump(slim_manifest, f, indent=2)

    size_mb = os.path.getsize(out_bin) / 1024 / 1024
    print(f'engram: {n_wells} wells, dim={dim} pairs={P} → {out_bin} ({size_mb:.2f} MB)')


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
    print(f'glove: {len(sorted_keys)} tokens → {out} ({size_mb:.2f} MB)')


if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if target in ('all', 'engram'):
        export_alexandria()
    if target in ('all', 'glove'):
        export_glove()
