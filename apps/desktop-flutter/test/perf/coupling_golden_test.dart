// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

@Tags(['manual'])
library;

// coupling_golden_test.dart — bit-identity golden for the git-log dedup. Dumps
// an exact checksum of computeFileCoupling's output on real repos so a refactor
// of the git-log walk / parser can be proven byte-identical (run before + after).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';

const _projects = r'C:\Users\mini server\Documents\Projects';
final _repos = <(String, String)>[
  ('worflor.io', '$_projects\\worflor.github.io'),
  ('wdym-mod', '$_projects\\Fabric Modding\\what-do-you-mean-mod-1.21'),
  ('git-desktop', '$_projects\\git-desktop-premium-ultra-promax-plus-R'),
];

String _dbits(double v) {
  final b = ByteData(8)..setFloat64(0, v);
  return b.getUint64(0).toRadixString(16);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('coupling golden', () async {
    for (final (label, path) in _repos) {
      if (!Directory(path).existsSync()) {
        print('GOLDEN $label SKIP');
        continue;
      }
      final res = await computeFileCoupling(path);
      final cc = res.data;
      if (cc == null) {
        print('GOLDEN $label FAIL ${res.error}');
        continue;
      }
      // exact order-independent checksum of every jaccard value + structure
      final paths = cc.paths.toList()..sort();
      var entries = 0;
      var xorAcc = 0;
      for (final p in paths) {
        for (final e in cc.jaccardEntriesOf(p)) {
          entries++;
          // mix path+neighbour+exact-bits so any value/structure change shows
          final h = (p.hashCode ^ (e.key.hashCode * 31) ^ _dbits(e.value).hashCode);
          xorAcc ^= (h & 0x7fffffff);
        }
      }
      print('GOLDEN $label  nodes=${cc.paths.length}  entries=$entries  checksum=$xorAcc  commitsAnalyzed=${cc.commitsAnalyzed}');
    }
    expect(true, isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
