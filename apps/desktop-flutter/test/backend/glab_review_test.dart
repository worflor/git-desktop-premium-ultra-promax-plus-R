// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// glab_review_test.dart — a review that cannot be expressed must not report
// success.
//
// Found by the shaker auditing never-reviewed backend code. GitLab has no
// request-changes review action, so Manifold posts one as a comment. With an
// empty body there was nothing to post, and the function returned ok having
// run no command at all: the UI reported a submitted review that GitLab never
// heard about.
//
// No `glab` binary is involved — the refusal happens before any subprocess,
// which is precisely the property being pinned.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/glab.dart' as glab;

void main() {
  test('G1: request-changes with no message is REFUSED, not silently '
      'swallowed', () async {
    final r = await glab.submitMrReview(
      '/no/such/repo',
      42,
      event: 'request-changes',
      body: '',
    );
    expect(r.ok, isFalse,
        reason: 'the caller was told a review was submitted while nothing '
            'reached GitLab');
    expect(r.error, contains('message'));
  });

  test('G2: whitespace is not a message', () async {
    // The original guard was `body.isNotEmpty`, which a stray space passes —
    // and an all-whitespace comment is not a change request either.
    final r = await glab.submitMrReview(
      '/no/such/repo',
      42,
      event: 'request-changes',
      body: '   \n\t ',
    );
    expect(r.ok, isFalse);
  });

  test('G3: the refusal names what to do instead', () async {
    // A dead end with no exit is a worse failure than the silent success it
    // replaced.
    final r = await glab.submitMrReview(
      '/no/such/repo',
      42,
      event: 'request-changes',
      body: '',
    );
    expect(r.error, contains('approve'));
  });
}
