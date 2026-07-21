// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// License-boundary laws.
//
// The repository is mixed-licensed: GPL-3.0-or-later by default, with the
// Woflo research components under WLCSL-1.0. The boundary is FILE-level and
// is declared twice: in the root LICENSE.md Work Notice (the legal source of
// truth) and in per-file SPDX headers. Anything declared in two places can
// drift, and the failure mode is silent: a new engine file whose name falls
// outside the protected patterns ships GPL, irrevocably for that release.
// These laws make that drift a test failure instead of a discovery.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mirror of the WLCSL path patterns in the root LICENSE.md. If you change
/// one, change both — L-LIC3 holds them in sync.
const _wlcslPrefixes = ['logos_', 'spectral_', 'engram_'];
const _wlcslNamed = [
  'aperture_sweep.dart',
  'bond_protocol.dart',
  'file_coupling.dart',
  'geometric_tokenizer.dart',
  'gyat.dart',
  'lrg_rings.dart',
  'shadow_coupling.dart',
  'shadow_coupling_cache.dart',
  'trajectory_echoes.dart',
  'uase.dart',
  'wick.dart',
];

const _gplId = 'SPDX-License-Identifier: GPL-3.0-or-later';
const _wlcslId = 'SPDX-License-Identifier: LicenseRef-WLCSL-1.0';

bool _isProtected(String relPath) {
  if (!relPath.startsWith('lib/backend/')) return false;
  final base = relPath.substring(relPath.lastIndexOf('/') + 1);
  return _wlcslPrefixes.any(base.startsWith) || _wlcslNamed.contains(base);
}

String _head(File f) {
  final lines = f.readAsLinesSync();
  return lines.take(5).join('\n');
}

Iterable<File> _dartFiles(String root) sync* {
  for (final e in Directory(root).listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final rel = e.path.replaceAll('\\', '/');
    if (rel.contains('lib/i18n/gen/')) continue; // generated, headerless
    yield e;
  }
}

String _rel(File f) {
  // listSync roots are package-relative ('lib' / 'test'), so the path is
  // already package-relative once separators are normalized.
  return f.path.replaceAll('\\', '/');
}

void main() {
  test('L-LIC1: every lib file declares exactly one license', () {
    final missing = <String>[];
    final both = <String>[];
    for (final f in _dartFiles('lib')) {
      final head = _head(f);
      final gpl = head.contains(_gplId);
      final wlcsl = head.contains(_wlcslId);
      if (!gpl && !wlcsl) missing.add(_rel(f));
      if (gpl && wlcsl) both.add(_rel(f));
    }
    expect(missing, isEmpty,
        reason: 'Files with no SPDX header. Every new file forces a '
            'conscious license choice: GPL header for app code, WLCSL header '
            'for research components — and a WLCSL file must ALSO be listed '
            'in the root LICENSE.md Work Notice.');
    expect(both, isEmpty, reason: 'Files claiming both licenses.');
  });

  test('L-LIC2: protected paths and WLCSL headers coincide exactly', () {
    final unprotectedHeader = <String>[];
    final unheaderedProtected = <String>[];
    for (final f in _dartFiles('lib')) {
      final rel = _rel(f);
      final wlcsl = _head(f).contains(_wlcslId);
      final protected = _isProtected(rel);
      if (wlcsl && !protected) unprotectedHeader.add(rel);
      if (!wlcsl && protected) unheaderedProtected.add(rel);
    }
    expect(unprotectedHeader, isEmpty,
        reason: 'WLCSL header on a path the Work Notice does not list. '
            'Either add the path to LICENSE.md (and this law\'s mirror) or '
            'use the GPL header.');
    expect(unheaderedProtected, isEmpty,
        reason: 'Work-Notice-protected path without a WLCSL header.');
  });

  test('L-LIC3: the law mirror matches the Work Notice text', () {
    final notice = File('../../LICENSE.md').readAsStringSync();
    for (final p in _wlcslPrefixes) {
      expect(notice, contains('lib/backend/$p*.dart'),
          reason: 'Prefix $p is enforced here but absent from LICENSE.md.');
    }
    for (final n in _wlcslNamed) {
      expect(notice, contains('lib/backend/$n'),
          reason: 'Named file $n is enforced here but absent from '
              'LICENSE.md.');
    }
  });

  test('L-LIC4: tests never carry the WLCSL header', () {
    final offenders = <String>[
      for (final f in _dartFiles('test'))
        if (_head(f).contains(_wlcslId)) _rel(f),
    ];
    expect(offenders, isEmpty,
        reason: 'Test code exercising a protected component stays GPL '
            '(LICENSE.md: "code that calls, displays, tests, or integrates '
            'a protected research component remains GPL-covered").');
  });
}
