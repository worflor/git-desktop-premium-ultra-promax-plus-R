// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_parse_failure_test.dart — a rejected review says WHY.
//
// Hit while dogfooding: a draft parse failure cost a full provider call
// and reported only "could not be parsed", which gives the operator
// nothing to change before spending another one. These pin the
// diagnosis, so the message can't silently regress to a shrug.
//
//  D1  absent tags are named, in the order the parser needs them.
//  D2  a well-shaped reply whose score carries no digits reads
//      differently from a missing tag — different cause, different fix.
//  D3  the diagnosis never claims a tag is missing when it is present.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';

void main() {
  test('D1: names the tags that are absent', () {
    expect(describeDraftParseFailure(''),
        'missing verdict, score, summary');
    expect(
      describeDraftParseFailure('<verdict>ready</verdict>'),
      'missing score, summary',
    );
    expect(
      describeDraftParseFailure(
        '<verdict>ready</verdict><score>88</score>',
      ),
      'missing summary',
    );
  });

  test('D2: a numberless score is its own failure', () {
    expect(
      describeDraftParseFailure(
        '<verdict>ready</verdict>'
        '<score>excellent</score>'
        '<summary>looks fine</summary>',
      ),
      'the score carried no number',
    );
  });

  test('D3: present tags are never reported missing', () {
    // Prose around the score is tolerated by the parser, so it must not
    // be diagnosed as a failure shape either.
    final msg = describeDraftParseFailure(
      '<verdict>ready</verdict>'
      '<score>**72**/100 (high confidence)</score>'
      '<summary>fine</summary>',
    );
    expect(msg, isNot(contains('missing')));
    expect(msg, isNot(contains('no number')));
  });
}
