import 'dart:io';
import 'dart:typed_data';

import 'git.dart';
import 'lru_cache.dart';
import 'magic_bytes.dart';

class BlobRef {
  final String repoPath;
  final String? objectHash;
  final String? workingTreePath;

  const BlobRef({required this.repoPath, this.objectHash, this.workingTreePath});

  String cacheKeyWithStat(FileStat? stat) {
    if (objectHash != null) return objectHash!;
    final mtime = stat?.modified.microsecondsSinceEpoch ?? 0;
    return 'wt:$workingTreePath:$mtime';
  }
}

class BlobData {
  final Uint8List bytes;
  final ContentClassInfo contentClass;
  final int sizeBytes;

  const BlobData({
    required this.bytes,
    required this.contentClass,
    required this.sizeBytes,
  });
}

sealed class BlobLoadResult {}

class BlobLoaded extends BlobLoadResult {
  final BlobData data;
  BlobLoaded(this.data);
}

class BlobTooLarge extends BlobLoadResult {
  final int sizeBytes;
  final ContentClassInfo? contentClass;
  BlobTooLarge(this.sizeBytes, this.contentClass);
}

class BlobFailed extends BlobLoadResult {
  final String message;
  BlobFailed(this.message);
}

const int _maxBlobSize = 20 * 1024 * 1024; // 20 MB

class BlobLoader {
  BlobLoader._();
  static final instance = BlobLoader._();

  final _cache = LruCache<String, BlobData>(maxSize: 50);

  Future<BlobLoadResult> load(BlobRef ref) async {
    final FileStat? stat;
    if (ref.objectHash == null && ref.workingTreePath != null) {
      stat = await FileStat.stat(ref.workingTreePath!);
    } else {
      stat = null;
    }
    final key = ref.cacheKeyWithStat(stat);
    final cached = _cache.get(key);
    if (cached != null) return BlobLoaded(cached);

    try {
      final BlobLoadResult result;
      if (ref.objectHash != null) {
        result = await _loadFromGit(ref);
      } else if (ref.workingTreePath != null) {
        result = await _loadFromFile(ref);
      } else {
        return BlobFailed('No object hash or working tree path');
      }
      if (result is BlobLoaded) {
        _cache.put(key, result.data);
      }
      return result;
    } catch (e) {
      return BlobFailed(e.toString());
    }
  }

  Future<BlobLoadResult> _loadFromGit(BlobRef ref) async {
    final size = await gitBlobSize(ref.repoPath, ref.objectHash!);
    if (size == null) return BlobFailed('Unable to read blob size');
    if (size > _maxBlobSize) {
      final header = await gitBlobHeader(ref.repoPath, ref.objectHash!);
      final cls = header != null ? probeContentClass(header) : null;
      return BlobTooLarge(size, cls);
    }

    final bytes = await gitBlobBytes(ref.repoPath, ref.objectHash!);
    if (bytes == null) return BlobFailed('Unable to read blob');

    final header = bytes.length >= 32 ? bytes.sublist(0, 32) : bytes;
    final contentClass = probeContentClass(header);
    final data = BlobData(
      bytes: bytes,
      contentClass: contentClass,
      sizeBytes: bytes.length,
    );
    return BlobLoaded(data);
  }

  Future<BlobLoadResult> _loadFromFile(BlobRef ref) async {
    final file = File(ref.workingTreePath!);
    if (!await file.exists()) return BlobFailed('File not found');

    final size = await file.length();
    if (size > _maxBlobSize) {
      final raf = await file.open();
      try {
        final header = await raf.read(32);
        return BlobTooLarge(size, probeContentClass(header));
      } finally {
        await raf.close();
      }
    }

    final bytes = await file.readAsBytes();
    final header = bytes.length >= 32
        ? Uint8List.sublistView(bytes, 0, 32)
        : bytes;
    final contentClass = probeContentClass(header);
    final data = BlobData(
      bytes: bytes,
      contentClass: contentClass,
      sizeBytes: bytes.length,
    );
    return BlobLoaded(data);
  }
}
