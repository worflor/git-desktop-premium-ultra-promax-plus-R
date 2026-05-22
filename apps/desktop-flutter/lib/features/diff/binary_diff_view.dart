import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../backend/blob_loader.dart';
import '../../ui/tokens.dart';
import 'media_renderer.dart';

class BinaryDiffView extends StatefulWidget {
  final String repoPath;
  final String filePath;
  final String? oldBlobHash;
  final String? newBlobHash;
  final double? viewportWidth;
  final AppTokens tokens;

  const BinaryDiffView({
    super.key,
    required this.repoPath,
    required this.filePath,
    this.oldBlobHash,
    this.newBlobHash,
    this.viewportWidth,
    required this.tokens,
  });

  @override
  State<BinaryDiffView> createState() => _BinaryDiffViewState();
}

enum _LoadPhase { idle, loading, done }

class _BinaryDiffViewState extends State<BinaryDiffView> {
  _LoadPhase _phase = _LoadPhase.idle;
  BlobLoadResult? _oldResult;
  BlobLoadResult? _newResult;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BinaryDiffView old) {
    super.didUpdateWidget(old);
    if (old.oldBlobHash != widget.oldBlobHash ||
        old.newBlobHash != widget.newBlobHash ||
        old.filePath != widget.filePath) {
      _load();
    }
  }

  Future<void> _load() async {
    final gen = ++_loadGeneration;
    setState(() => _phase = _LoadPhase.loading);

    final loader = BlobLoader.instance;
    final futures = <Future<BlobLoadResult?>>[];

    final hasOld = widget.oldBlobHash != null &&
        widget.oldBlobHash!.isNotEmpty &&
        !_isNullHash(widget.oldBlobHash!);
    final hasNew = widget.newBlobHash != null &&
        widget.newBlobHash!.isNotEmpty &&
        !_isNullHash(widget.newBlobHash!);

    if (hasOld) {
      futures.add(loader.load(BlobRef(
        repoPath: widget.repoPath,
        objectHash: widget.oldBlobHash,
      )));
    } else {
      futures.add(Future.value(null));
    }

    if (hasNew) {
      final absPath = p.join(widget.repoPath, widget.filePath);
      futures.add(loader.load(BlobRef(
        repoPath: widget.repoPath,
        objectHash: widget.newBlobHash,
      )).then((r) async {
        if (r is! BlobFailed) return r;
        if (await File(absPath).exists()) {
          return loader.load(BlobRef(
            repoPath: widget.repoPath,
            workingTreePath: absPath,
          ));
        }
        return r;
      }));
    } else {
      final absPath = p.join(widget.repoPath, widget.filePath);
      if (await File(absPath).exists()) {
        futures.add(loader.load(BlobRef(
          repoPath: widget.repoPath,
          workingTreePath: absPath,
        )));
      } else {
        futures.add(Future.value(null));
      }
    }

    final results = await Future.wait(futures);
    if (!mounted || gen != _loadGeneration) return;
    setState(() {
      _oldResult = results[0];
      _newResult = results[1];
      _phase = _LoadPhase.done;
    });
  }

  static bool _isNullHash(String hash) => hash.replaceAll('0', '').isEmpty;

  MediaDiffState _detectState() {
    final oldNull = widget.oldBlobHash == null ||
        widget.oldBlobHash!.isEmpty ||
        _isNullHash(widget.oldBlobHash!);
    final newNull = widget.newBlobHash == null ||
        widget.newBlobHash!.isEmpty ||
        _isNullHash(widget.newBlobHash!);
    if (oldNull && !newNull) return MediaDiffState.added;
    if (!oldNull && newNull) return MediaDiffState.deleted;
    if (oldNull && newNull) return MediaDiffState.added;
    return MediaDiffState.modified;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;

    if (_phase == _LoadPhase.loading || _phase == _LoadPhase.idle) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          heightFactor: 1,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: t.textMuted.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    final state = _detectState();

    final oldTooLarge = _oldResult is BlobTooLarge;
    final newTooLarge = _newResult is BlobTooLarge;
    if (oldTooLarge || newTooLarge) {
      final tl = (oldTooLarge ? _oldResult : _newResult) as BlobTooLarge;
      return MetadataOnlyRenderer(
        oldBlob: null,
        newBlob: null,
        state: state,
        tokens: t,
        sizeOverride: '${(tl.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB (too large to preview)',
      );
    }

    final oldFailed = _oldResult is BlobFailed;
    final newFailed = _newResult is BlobFailed;
    if ((oldFailed && _oldResult != null) || (newFailed && _newResult != null)) {
      return MetadataOnlyRenderer(
        oldBlob: null,
        newBlob: null,
        state: state,
        tokens: t,
        sizeOverride: 'Unable to load blob',
      );
    }

    final oldBlob = _oldResult is BlobLoaded ? (_oldResult as BlobLoaded).data : null;
    final newBlob = _newResult is BlobLoaded ? (_newResult as BlobLoaded).data : null;

    if (oldBlob == null && newBlob == null) {
      return MetadataOnlyRenderer(
        oldBlob: null,
        newBlob: null,
        state: state,
        tokens: t,
      );
    }

    // Derive state from what actually loaded, not from hash presence.
    // A hash can exist but the blob load can fail (pruned pack, shallow
    // clone, transient git error).
    final effectiveState = oldBlob != null && newBlob != null
        ? MediaDiffState.modified
        : newBlob != null
            ? MediaDiffState.added
            : MediaDiffState.deleted;

    final cls = (newBlob ?? oldBlob)!.contentClass.cls;

    return MediaRendererRegistry.build(
      cls: cls,
      oldBlob: oldBlob,
      newBlob: newBlob,
      state: effectiveState,
      tokens: t,
      viewportWidth: widget.viewportWidth,
    );
  }
}
