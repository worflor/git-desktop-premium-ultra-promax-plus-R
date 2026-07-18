// A ByteStore is the diff viewer's single source of truth: the raw bytes of a
// unified diff, addressed by opaque offsets. The predictive index and the lazy
// row list read the diff ONLY through this interface, so the storage medium —
// an in-RAM string, or a spooled temp file for machine-scale diffs — is an
// implementation detail, not a fork in the pipeline. One parser, one document
// model, two backings.
//
// The interface is deliberately SYNCHRONOUS: Flutter's virtualized list builds
// rows synchronously during paint, so a store must answer `substring` without an
// await. [FileByteStore] honours that with `readSync` over a just-written spool
// file (OS-cached, memory-speed) plus a bounded page cache — never async I/O on
// the UI isolate.
//
// Offsets are in the store's own unit and are only ever compared within one
// store: [StringByteStore] uses UTF-16 code-unit offsets (what `String` indexes
// by); [FileByteStore] uses byte offsets. The index never mixes them.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The newline byte/char the diff scanner splits on.
const int kNewlineByte = 0x0A; // '\n'

abstract class ByteStore {
  /// Total length, in this store's offset unit.
  int get length;

  /// Offset of the next [kNewlineByte] at or after [from], or -1 if none.
  int indexOfNewline(int from);

  /// The unit (code unit / byte) at [i]. Used for cheap line-prefix checks
  /// (`+`, `-`, space, `\`, `@`) without materializing the line.
  int unitAt(int i);

  /// Decode `[start, end)` into a display String. Bounded to a single line /
  /// region by the caller, so the cost is O(region), never O(length).
  String substring(int start, int end);

  /// Release any held resources (file handles). Idempotent.
  void dispose() {}
}

/// In-RAM backing over a Dart `String` — the Phase-1 representation, unchanged.
/// For ASCII diffs the VM already stores this as a 1-byte `OneByteString`, so it
/// is as compact as a byte array while keeping decode free. Used for small and
/// medium diffs that comfortably fit in memory.
class StringByteStore implements ByteStore {
  final String _raw;
  const StringByteStore(this._raw);

  @override
  int get length => _raw.length;

  @override
  int indexOfNewline(int from) => _raw.indexOf('\n', from);

  @override
  int unitAt(int i) => _raw.codeUnitAt(i);

  @override
  String substring(int start, int end) => _raw.substring(start, end);

  @override
  void dispose() {}
}

/// Disk-backed backing over a spool file, for machine-scale diffs whose bytes
/// should NOT all reside in RAM. Reads are synchronous `readSync`s served from a
/// bounded LRU page cache; the just-written spool sits in the OS file cache, so
/// hits are memory-speed and the Dart heap stays flat regardless of diff size.
///
/// This is the structure that makes resident RAM independent of diff size:
/// index (KB) + viewport rows + page cache (bounded) — never the whole diff.
class FileByteStore implements ByteStore {
  final RandomAccessFile _file;
  @override
  final int length;
  final int _pageSize;
  final int _maxPages;
  final Encoding _encoding;

  // LRU page cache: page index -> bytes. Insertion order = recency (re-inserted
  // on hit); evict from the front when over [_maxPages].
  final Map<int, Uint8List> _pages = <int, Uint8List>{};
  bool _disposed = false;

  FileByteStore._(this._file, this.length, this._pageSize, this._maxPages,
      this._encoding);

  /// Open [path] for reading. [pageSize] is the granularity of disk reads and
  /// cache entries (256 KiB–1 MiB is the sweet spot — big enough that a scroll
  /// touches few pages, small enough that the cache stays bounded). [maxPages]
  /// bounds resident cache bytes to `pageSize * maxPages`.
  factory FileByteStore.open(
    String path, {
    int pageSize = 512 * 1024,
    int maxPages = 48,
    Encoding encoding = utf8,
  }) {
    final f = File(path);
    final raf = f.openSync();
    final len = raf.lengthSync();
    return FileByteStore._(raf, len, pageSize, maxPages, encoding);
  }

  Uint8List _page(int pageIndex) {
    final cached = _pages.remove(pageIndex);
    if (cached != null) {
      _pages[pageIndex] = cached; // move to MRU
      return cached;
    }
    final start = pageIndex * _pageSize;
    final count = (start + _pageSize <= length) ? _pageSize : (length - start);
    _file.setPositionSync(start);
    final bytes = _file.readSync(count < 0 ? 0 : count);
    _pages[pageIndex] = bytes;
    if (_pages.length > _maxPages) {
      _pages.remove(_pages.keys.first); // evict LRU
    }
    return bytes;
  }

  @override
  int unitAt(int i) {
    if (i < 0 || i >= length) return -1; // out of range → "no unit"
    final page = _page(i ~/ _pageSize);
    final off = i % _pageSize;
    return off < page.length ? page[off] : -1;
  }

  @override
  int indexOfNewline(int from) {
    var i = from < 0 ? 0 : from;
    while (i < length) {
      final pageIndex = i ~/ _pageSize;
      final page = _page(pageIndex);
      final base = pageIndex * _pageSize;
      final off = i - base;
      final nl = page.indexOf(kNewlineByte, off);
      if (nl >= 0) return base + nl;
      i = base + page.length; // next page
    }
    return -1;
  }

  @override
  String substring(int start, int end) {
    // Clamp defensively so an out-of-range request can never RangeError.
    if (start < 0) start = 0;
    if (end > length) end = length;
    if (end <= start) return '';
    // Fast path: wholly within one page (the common case — a single line).
    final startPage = start ~/ _pageSize;
    final endPage = (end - 1) ~/ _pageSize;
    if (startPage == endPage) {
      final page = _page(startPage);
      final base = startPage * _pageSize;
      return _decode(
          Uint8List.sublistView(page, start - base, end - base));
    }
    // Slow path: spans pages (a long line). Gather bytes across pages.
    final out = BytesBuilder(copy: false);
    var i = start;
    while (i < end) {
      final pageIndex = i ~/ _pageSize;
      final page = _page(pageIndex);
      final base = pageIndex * _pageSize;
      final from = i - base;
      final to = (end - base < page.length) ? end - base : page.length;
      out.add(Uint8List.sublistView(page, from, to));
      i = base + to;
    }
    return _decode(out.takeBytes());
  }

  String _decode(Uint8List bytes) {
    if (_encoding == utf8) {
      // Match display semantics: never throw on a malformed patch byte.
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
    return _encoding.decode(bytes);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pages.clear();
    try {
      _file.closeSync();
    } catch (_) {}
  }
}
