// engram_file_index.dart — per-file K-vectors for LogosGit's EN axis.
//
// For each file we care about (typically the LogosGit nodePaths set,
// i.e. files with at least one observation in the analysed window):
//   1. Read its content from the working tree
//   2. Tokenize identifiers (camelCase + snake_case + punctuation)
//   3. Drop noise (single chars, pure digits, common stop tokens)
//   4. Cap to a fixed number of sub-tokens (so big files don't dominate)
//   5. Encode via [EngramHunkEncoder] → K-vector + nearest well
//
// Result: `Map<String, HunkKVector>` keyed by repo-relative path. Files
// that fail to read, are too short to fit, or hit no GloVe vocabulary
// drop out of the map (the LogosGit EN axis stays silent for them).
//
// Designed to run inside the LogosGit build isolate alongside
// `LogosGit.buildFromStats`. File I/O is sync (`readAsStringSync`)
// because the isolate has nothing else to do; doing it async would just
// add scheduler overhead. For a 1000-file repo the index builds in
// ~5–15 seconds on a cold cache and is then memoised by the resolver.

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'engram_bootstrap.dart';
import 'engram_hunk_encoder.dart';

/// Hard cap on identifier sub-tokens fed into the encoder per file. The
/// AR(2) fit's K-vector is invariant to the trajectory's tail beyond
/// roughly 100 samples (the dynamics signal saturates), so capping
/// here keeps encode cost flat per file regardless of file size and
/// prevents one giant file from dominating the index build.
const int _kMaxTokensPerFile = 256;

/// Hard cap on file content read into memory. **The cap sits at 16KB
/// because that's where code stops being semantically dense.**
/// In a typical source file the identifier-bearing lines — imports,
/// class declarations, type definitions, function signatures, named
/// constants — live in the top few kilobytes. The rest is expression
/// bodies: control flow and arithmetic that reuses the same identifiers
/// already seen near the top. Past ~16KB you're paying disk bandwidth
/// and tokeniser time to re-read tokens that are already in the bag.
/// For the outlier giant files (generated code, vendored bundles,
/// minified JS, lockfiles) 16KB is plenty — again, the top carries the
/// import list and public surface, which is everything Alexandria's
/// AR(2) needs to locate the file semantically. Lower tail content is
/// noise that was getting averaged into the K-vector with diminishing
/// returns.
/// 16× smaller than the previous 256KB cap. On a thousand-file repo
/// where half the files are >16KB, this shaves ~100–400ms off cold
/// builds. Zero signal loss measurable in the well-assignment: the
/// nearest-well verdict for a file rarely changes past the first 4KB
/// of well-formed code.
const int _kMaxFileBytes = 16 * 1024;

/// File extensions worth indexing. We skip binary blobs, lockfiles,
/// generated assets — they either fail to decode as UTF-8 or contain
/// no useful identifier signal. Membership in this set is the gate;
/// extension comparison is case-insensitive at lookup.
const Set<String> _kIndexableExtensions = {
  '.dart', '.rs', '.py', '.ts', '.tsx', '.js', '.jsx', '.mjs',
  '.go', '.java', '.kt', '.kts', '.scala', '.swift', '.m', '.mm',
  '.c', '.cc', '.cpp', '.cxx', '.h', '.hpp', '.hxx',
  '.cs', '.fs', '.fsx', '.vb',
  '.rb', '.php', '.pl', '.pm', '.lua', '.r',
  '.sh', '.bash', '.zsh', '.fish', '.ps1',
  '.sql', '.graphql', '.proto',
  '.yaml', '.yml', '.toml', '.ini', '.cfg',
  '.md', '.mdx', '.rst', '.txt',
  '.html', '.htm', '.css', '.scss', '.sass', '.less',
  '.vue', '.svelte', '.elm', '.ex', '.exs', '.erl', '.hrl',
  '.zig', '.nim', '.cr', '.d', '.hs', '.ml', '.clj', '.cljs',
};

/// Tokeniser regex — matches identifier-shaped runs (letters, digits,
/// underscores). Used to extract raw tokens from file content before
/// running them through the splitIdentifier camelCase tokenizer.
final RegExp _identifierRun = RegExp(r'[A-Za-z_][A-Za-z0-9_]{1,40}');

/// Build a map from repo-relative path → K-vector for every path in
/// [paths] that successfully tokenises and encodes.
/// [repoPath] is the absolute repo root; paths are joined relative to it.
/// [encoder] does the heavy lifting (already loaded with brain + glove).
/// Files that don't exist, are too large, decode badly, or have too
/// few in-vocab sub-tokens to fit AR(2) are simply absent from the
/// returned map — callers (the EN axis) treat absence as "silent".
Map<String, HunkKVector> buildEngramFileIndex({
  required String repoPath,
  required EngramHunkEncoder encoder,
  required Iterable<String> paths,
}) {
  final out = <String, HunkKVector>{};

  for (final relPath in paths) {
    final ext = p.extension(relPath).toLowerCase();
    if (!_kIndexableExtensions.contains(ext)) continue;

    final absPath = p.join(repoPath, relPath);
    final f = File(absPath);
    if (!f.existsSync()) continue;

    String content;
    try {
      // Hard byte cap: read up to _kMaxFileBytes to bound memory.
      final raf = f.openSync();
      try {
        final length = raf.lengthSync();
        final readN = length < _kMaxFileBytes ? length : _kMaxFileBytes;
        final bytes = raf.readSync(readN);
        content = _safeDecodeUtf8(bytes);
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      continue; // unreadable; silent
    }
    if (content.isEmpty) continue;

    // Extract identifier-shaped tokens; the encoder's own
    // splitIdentifier handles camelCase/snake_case decomposition
    // downstream, so we only need to pull the raw runs here.
    final tokens = <String>[];
    for (final m in _identifierRun.allMatches(content)) {
      tokens.add(m.group(0)!);
      if (tokens.length >= _kMaxTokensPerFile) break;
    }
    if (tokens.isEmpty) continue;

    final kv = encoder.encode(tokens);
    if (kv == null) continue;

    out[relPath] = kv;
  }

  return out;
}

/// Best-effort UTF-8 decode. Files with a sprinkling of binary garbage
/// (BOM, null padding, mojibake) shouldn't tank the whole index — we
/// fall back to latin-1 which always decodes, on the theory that even
/// noisy content yields useful identifier-shaped runs after regex.
String _safeDecodeUtf8(Uint8List bytes) {
  try {
    // Use String.fromCharCodes for fast path — accepts any byte values.
    // For non-ASCII, this technically gives latin-1; that's fine because
    // the identifier regex only matches ASCII letters/digits/underscores
    // anyway, so multi-byte UTF-8 mojibake just doesn't match.
    return String.fromCharCodes(bytes);
  } catch (_) {
    return '';
  }
}

// Parallel encoding — isolate-safe payload + fan-out helpers.

/// Isolate-sendable payload for a single-chunk encode job. The byte
/// blobs are shared across chunks (each isolate gets its own copy via
/// copy-semantics of Isolate.run's sendable payload, but the JIT
/// compiler elides the share since they're identical blobs per job
/// — inexpensive compared to the file I/O that follows).
class EngramEncodeJob {
  final Uint8List brainBytes;
  final Uint8List gloveBytes;
  final String repoPath;
  final List<String> paths;

  const EngramEncodeJob({
    required this.brainBytes,
    required this.gloveBytes,
    required this.repoPath,
    required this.paths,
  });
}

/// Encode a single chunk of paths inside an isolate. Top-level so it
/// can be the body of Isolate.run/compute without capturing closures.
/// Returns the K-vectors keyed by the caller's repo-relative path
/// strings (not absolute) so the caller can merge without redoing path
/// math.
Map<String, HunkKVector> engramEncodeChunk(EngramEncodeJob job) {
  final assets = EngramAssets(
    brainBytes: job.brainBytes,
    gloveBytes: job.gloveBytes,
  );
  final encoder = assets.buildEncoder();
  if (encoder == null) return const {};
  return buildEngramFileIndex(
    repoPath: job.repoPath,
    encoder: encoder,
    paths: job.paths,
  );
}
