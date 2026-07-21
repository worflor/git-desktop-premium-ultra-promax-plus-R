// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// must.dart — await-and-assert for arrange-phase store calls.
//
// A test that drops a GitResult in its arrange phase can silently run its
// assertions against state that never materialised (the create failed,
// the comment never landed) and pass or fail for the wrong reason.
// `expectOk` pins every such call: the operation must succeed or the test
// fails HERE, naming the failed step. The @useResult sweep (analyzer
// error `unused_result`) is what routes arrange calls through this.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git_result.dart';

Future<GitResult<T>> expectOk<T>(Future<GitResult<T>> op) async {
  final r = await op;
  expect(r.ok, isTrue, reason: 'arrange-phase op failed: ${r.error}');
  return r;
}
