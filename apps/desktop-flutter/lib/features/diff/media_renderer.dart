import 'package:flutter/material.dart';

import '../../backend/blob_loader.dart';
import '../../backend/magic_bytes.dart';
import '../../ui/tokens.dart';

enum MediaDiffState { added, deleted, modified }

class MediaRendererRegistry {
  static Widget build({
    required ContentClass cls,
    required BlobData? oldBlob,
    required BlobData? newBlob,
    required MediaDiffState state,
    required AppTokens tokens,
    double? viewportWidth,
  }) {
    switch (cls) {
      case ContentClass.image:
        return ImageMediaRenderer(
          oldBlob: oldBlob,
          newBlob: newBlob,
          state: state,
          tokens: tokens,
          viewportWidth: viewportWidth,
        );
      default:
        return MetadataOnlyRenderer(
          oldBlob: oldBlob,
          newBlob: newBlob,
          state: state,
          tokens: tokens,
        );
    }
  }
}

class ImageMediaRenderer extends StatelessWidget {
  final BlobData? oldBlob;
  final BlobData? newBlob;
  final MediaDiffState state;
  final AppTokens tokens;
  final double? viewportWidth;

  const ImageMediaRenderer({
    super.key,
    required this.oldBlob,
    required this.newBlob,
    required this.state,
    required this.tokens,
    this.viewportWidth,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      MediaDiffState.added => newBlob != null
          ? _singleImage(newBlob!, tokens.stateAdded, 1.0)
          : _fallbackMeta(),
      MediaDiffState.deleted => oldBlob != null
          ? _singleImage(oldBlob!, tokens.stateDeleted, 0.5)
          : _fallbackMeta(),
      MediaDiffState.modified => _sideBySide(),
    };
  }

  Widget _fallbackMeta() => MetadataOnlyRenderer(
        oldBlob: oldBlob,
        newBlob: newBlob,
        state: state,
        tokens: tokens,
      );

  static const _contentPadding =
      EdgeInsets.only(left: 20, right: 16, top: 12, bottom: 12);

  Widget _singleImage(BlobData blob, Color tint, double opacity) {
    return Padding(
      padding: _contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: tint.withValues(alpha: 0.4), width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Opacity(
                opacity: opacity,
                child: _imageWithCheckerboard(blob),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _sizeLabel(blob, tint),
        ],
      ),
    );
  }

  Widget _sideBySide() {
    return Padding(
      padding: _contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (oldBlob != null)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: tokens.stateDeleted.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Opacity(
                            opacity: 0.7,
                            child: _imageWithCheckerboard(oldBlob!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _sizeLabel(oldBlob!, tokens.stateDeleted),
                    ],
                  ),
                ),
              if (oldBlob != null && newBlob != null) const SizedBox(width: 12),
              if (newBlob != null)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: tokens.stateAdded.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: _imageWithCheckerboard(newBlob!),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _sizeLabel(newBlob!, tokens.stateAdded),
                    ],
                  ),
                ),
            ],
          ),
          if (oldBlob != null && newBlob != null) ...[
            const SizedBox(height: 8),
            Text(
              _sizeDelta(oldBlob!.sizeBytes, newBlob!.sizeBytes),
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _imageWithCheckerboard(BlobData blob) {
    final maxW = viewportWidth != null ? viewportWidth! - 34 : 600.0;
    return CustomPaint(
      painter: CheckerboardPainter(
        color1: tokens.surface0,
        color2: tokens.surface1,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Image.memory(
          blob.bytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _errorPlaceholder(),
        ),
      ),
    );
  }

  Widget _errorPlaceholder() {
    return Container(
      height: 80,
      alignment: Alignment.center,
      child: Text(
        'Unable to decode image',
        style: TextStyle(color: tokens.textMuted, fontSize: 11),
      ),
    );
  }

  Widget _sizeLabel(BlobData blob, Color tint) {
    return Text(
      '${blob.contentClass.formatName}  ${_fmtSize(blob.sizeBytes)}',
      style: TextStyle(
        color: tint.withValues(alpha: 0.8),
        fontSize: 11,
        fontFamily: 'JetBrains Mono',
      ),
    );
  }

  static String _sizeDelta(int oldSize, int newSize) {
    final delta = newSize - oldSize;
    final sign = delta >= 0 ? '+' : '−';
    return '${_fmtSize(oldSize)} → ${_fmtSize(newSize)}  ($sign${_fmtSize(delta.abs())})';
  }
}

class MetadataOnlyRenderer extends StatelessWidget {
  final BlobData? oldBlob;
  final BlobData? newBlob;
  final MediaDiffState state;
  final AppTokens tokens;
  final String? sizeOverride;

  const MetadataOnlyRenderer({
    super.key,
    required this.oldBlob,
    required this.newBlob,
    required this.state,
    required this.tokens,
    this.sizeOverride,
  });

  @override
  Widget build(BuildContext context) {
    final blob = newBlob ?? oldBlob;
    final formatName = blob?.contentClass.formatName ?? 'Binary';
    final size = sizeOverride ?? (blob != null ? _fmtSize(blob.sizeBytes) : '');

    final (String label, Color color) = switch (state) {
      MediaDiffState.added => ('added', tokens.stateAdded),
      MediaDiffState.deleted => ('deleted', tokens.stateDeleted),
      MediaDiffState.modified => ('modified', tokens.textMuted),
    };

    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 16, top: 12, bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: tokens.surface0.withValues(alpha: 0.3),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForClass(blob?.contentClass.cls ?? ContentClass.unknown),
              size: 20,
              color: tokens.textMuted,
            ),
            const SizedBox(width: 10),
            Text(
              formatName,
              style: TextStyle(
                color: tokens.textNormal,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (size.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                size,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ],
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForClass(ContentClass cls) {
    return switch (cls) {
      ContentClass.image => Icons.image_outlined,
      ContentClass.video => Icons.videocam_outlined,
      ContentClass.audio => Icons.audiotrack_outlined,
      ContentClass.font => Icons.font_download_outlined,
      ContentClass.document => Icons.description_outlined,
      ContentClass.archive => Icons.folder_zip_outlined,
      ContentClass.unknown => Icons.insert_drive_file_outlined,
    };
  }
}

class CheckerboardPainter extends CustomPainter {
  final Color color1;
  final Color color2;

  CheckerboardPainter({required this.color1, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    const tileSize = 8.0;
    final paint1 = Paint()..color = color1;
    final paint2 = Paint()..color = color2;
    final cols = (size.width / tileSize).ceil();
    final rows = (size.height / tileSize).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final paint = (r + c).isEven ? paint1 : paint2;
        canvas.drawRect(
          Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter old) =>
      old.color1 != color1 || old.color2 != color2;
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
