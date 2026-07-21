// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// `canonicalGiteaHostKey` owns the key shape that `resolveGiteaToken`
// looks up in the per-host token map. Whatever a user pastes into the
// settings token card — a bare host, a full clone URL, an scp remote —
// must collapse to that exact shape, or the saved token silently never
// matches at resolve time. These cases pin the collapse.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/gitea_api.dart';

void main() {
  group('canonicalGiteaHostKey', () {
    test('bare host', () {
      expect(canonicalGiteaHostKey('codeberg.org'), 'codeberg.org');
    });

    test('uppercase host is lowercased', () {
      expect(canonicalGiteaHostKey('Codeberg.ORG'), 'codeberg.org');
    });

    test('host:port kept', () {
      expect(canonicalGiteaHostKey('host:3000'), 'host:3000');
    });

    test('https url — host only when no explicit port', () {
      expect(canonicalGiteaHostKey('https://codeberg.org'), 'codeberg.org');
    });

    test('https url with port and path', () {
      expect(
        canonicalGiteaHostKey('https://host:3000/owner/repo'),
        'host:3000',
      );
    });

    test('http url with port', () {
      expect(canonicalGiteaHostKey('http://host:3000'), 'host:3000');
    });

    test('explicit default ports are dropped — the apiBase side never '
        'carries them, so a :443/:80 key could never match at resolve time',
        () {
      expect(canonicalGiteaHostKey('https://host:443'), 'host');
      expect(canonicalGiteaHostKey('http://host:80'), 'host');
      expect(canonicalGiteaHostKey('host:443'), 'host');
      expect(canonicalGiteaHostKey('host:80/owner/repo'), 'host');
    });

    test('signed port forms are garbage, not ports', () {
      expect(canonicalGiteaHostKey('host:+3000'), 'host');
    });

    test('ssh url drops the ssh port (not the HTTP API port)', () {
      expect(canonicalGiteaHostKey('ssh://git@host:2222/o/r'), 'host');
    });

    test('scp-style remote — host only, colon is a path', () {
      expect(canonicalGiteaHostKey('git@host:o/r.git'), 'host');
    });

    test('bare host with path strips the path', () {
      expect(canonicalGiteaHostKey('host/owner/repo'), 'host');
    });

    test('empty input', () {
      expect(canonicalGiteaHostKey(''), '');
      expect(canonicalGiteaHostKey('   '), '');
    });

    test('garbage is rejected as empty', () {
      expect(canonicalGiteaHostKey('not a host!!'), '');
    });
  });
}
