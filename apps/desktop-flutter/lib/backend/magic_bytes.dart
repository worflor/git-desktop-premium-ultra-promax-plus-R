import 'dart:typed_data';

enum ContentClass { image, video, audio, font, document, archive, unknown }

typedef ContentClassInfo = ({ContentClass cls, String formatName});

class _Sig {
  final int offset;
  final List<int> bytes;
  final ContentClass cls;
  final String name;
  const _Sig(this.offset, this.bytes, this.cls, this.name);
}

const _signatures = <_Sig>[
  // image
  _Sig(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], ContentClass.image, 'PNG'),
  _Sig(0, [0xFF, 0xD8, 0xFF], ContentClass.image, 'JPEG'),
  _Sig(0, [0x47, 0x49, 0x46, 0x38], ContentClass.image, 'GIF'),
  _Sig(0, [0x42, 0x4D], ContentClass.image, 'BMP'),
  _Sig(0, [0x49, 0x49, 0x2A, 0x00], ContentClass.image, 'TIFF'),
  _Sig(0, [0x4D, 0x4D, 0x00, 0x2A], ContentClass.image, 'TIFF'),
  _Sig(0, [0x00, 0x00, 0x01, 0x00], ContentClass.image, 'ICO'),
  _Sig(0, [0x00, 0x00, 0x02, 0x00], ContentClass.image, 'CUR'),

  // audio
  _Sig(0, [0x49, 0x44, 0x33], ContentClass.audio, 'MP3'),           // ID3 tag
  _Sig(0, [0xFF, 0xFB], ContentClass.audio, 'MP3'),                  // MPEG sync
  _Sig(0, [0xFF, 0xF3], ContentClass.audio, 'MP3'),
  _Sig(0, [0xFF, 0xF2], ContentClass.audio, 'MP3'),
  _Sig(0, [0x66, 0x4C, 0x61, 0x43], ContentClass.audio, 'FLAC'),    // fLaC
  _Sig(0, [0x4F, 0x67, 0x67, 0x53], ContentClass.audio, 'OGG'),     // OggS

  // document
  _Sig(0, [0x25, 0x50, 0x44, 0x46], ContentClass.document, 'PDF'),   // %PDF

  // archive
  _Sig(0, [0x50, 0x4B, 0x03, 0x04], ContentClass.archive, 'ZIP'),
  _Sig(0, [0x1F, 0x8B], ContentClass.archive, 'GZIP'),
  _Sig(0, [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], ContentClass.archive, '7z'),
  _Sig(0, [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00], ContentClass.archive, 'XZ'),
  _Sig(0, [0x42, 0x5A, 0x68], ContentClass.archive, 'BZ2'),          // BZh
  _Sig(0, [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07], ContentClass.archive, 'RAR'),

  // font
  _Sig(0, [0x4F, 0x54, 0x54, 0x4F], ContentClass.font, 'OTF'),      // OTTO
  _Sig(0, [0x00, 0x01, 0x00, 0x00], ContentClass.font, 'TTF'),
  _Sig(0, [0x77, 0x4F, 0x46, 0x46], ContentClass.font, 'WOFF'),
  _Sig(0, [0x77, 0x4F, 0x46, 0x32], ContentClass.font, 'WOFF2'),

  // video (offset-based)
  _Sig(4, [0x66, 0x74, 0x79, 0x70], ContentClass.video, 'MP4'),      // ftyp
];

// RIFF container: WebP, AVI, WAV share the same outer framing.
const _riffSubtypes = <String, (ContentClass, String)>{
  'WEBP': (ContentClass.image, 'WebP'),
  'AVI ': (ContentClass.video, 'AVI'),
  'WAVE': (ContentClass.audio, 'WAV'),
};

const _unknown = (cls: ContentClass.unknown, formatName: 'Unknown');

ContentClassInfo probeContentClass(Uint8List header) {
  final len = header.length;
  if (len < 2) return _unknown;

  // RIFF container probe — bytes 0-3 are "RIFF", 8-11 are the subtype.
  if (len >= 12 &&
      header[0] == 0x52 && header[1] == 0x49 &&
      header[2] == 0x46 && header[3] == 0x46) {
    final sub = String.fromCharCodes(header, 8, 12);
    final match = _riffSubtypes[sub];
    if (match != null) return (cls: match.$1, formatName: match.$2);
  }

  // Table-driven signature scan.
  for (final sig in _signatures) {
    final end = sig.offset + sig.bytes.length;
    if (len < end) continue;
    var matched = true;
    for (var i = 0; i < sig.bytes.length; i++) {
      final expected = sig.bytes[i];
      final actual = header[sig.offset + i];
      if (actual != expected) { matched = false; break; }
    }
    if (matched) return (cls: sig.cls, formatName: sig.name);
  }

  return _unknown;
}
