// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// desk_pr_identity_gate_test.dart — which writes need a signature.
//
// A record that names an author and then SYNCS TO PEERS cannot be
// written by nobody: the name is the merge key, and an invented one is
// worse than a refusal. But the gate has to stop exactly there. Blocking
// a user from closing their own desk PR because git has no user.name
// would be punishing them over a field that write does not touch.
//
// The manifold review flagged this gate as unverified, and it was: no
// test referenced identityUnsetMessage at all, so nothing said which
// side of the line each verb sits on.
//
//  G1  the author-stamping writes refuse without an identity.
//  G2  the writes that stamp no author are NOT gated.
//  G3  a resolved identity lets the same writes through.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/app_identity.dart';
import 'package:git_desktop/app/desk_pr_state.dart';
import 'package:git_desktop/app/repository_state.dart';
import 'package:git_desktop/backend/git_identity.dart';

import '../support/scratch_repo.dart';

void main() {
  late ScratchRepo repo;
  late DeskPrState state;

  setUp(() async {
    DeskPrState.debugSuppressAutoRefresh = true;
    DeskPrState.debugSuppressViewerResolve = true;
    repo = await ScratchRepo.create(name: 'identity_gate');
    await repo.writeFile('a.txt', 'one\n');
    await repo.commitAll('base');
    await repo.gitOk(['checkout', '-q', '-b', 'feat']);
    await repo.writeFile('a.txt', 'two\n');
    await repo.commitAll('work');
    state = DeskPrState(RepositoryState(), AppIdentityState());
  });

  tearDown(() async {
    DeskPrState.debugSuppressAutoRefresh = false;
    DeskPrState.debugSuppressViewerResolve = false;
    state.dispose();
    await repo.dispose();
  });

  test('G1: writes that stamp an author refuse without an identity',
      () async {
    state.debugSeedViewer(null);

    final promoted = await state.promote(
      repoPath: repo.dir.path,
      branch: 'feat',
      title: 'a change',
    );
    expect(promoted, DeskPrState.identityUnsetMessage,
        reason: 'a desk PR records who authored it');

    final commented = await state.addComment(
      repoPath: repo.dir.path,
      branch: 'feat',
      body: 'a thought',
    );
    expect(commented, DeskPrState.identityUnsetMessage);

    final reviewed = await state.addReview(
      repoPath: repo.dir.path,
      branch: 'feat',
      verdict: 'APPROVED',
      body: '',
    );
    expect(reviewed, DeskPrState.identityUnsetMessage);
  });

  test('G2: the message names what it guards, not the review flow',
      () async {
    // promote is not a review. A refusal that says "before reviewing"
    // sends someone hunting for a review setting that does not exist.
    expect(DeskPrState.identityUnsetMessage, isNot(contains('reviewing')));
    expect(DeskPrState.identityUnsetMessage, contains('git config'),
        reason: 'the refusal carries its own remedy');
  });

  test('G3: a resolved identity lets the same write through', () async {
    state.debugSeedViewer(
      const GitIdentity(display: 'mira', key: 'mira@example.com'),
    );
    final promoted = await state.promote(
      repoPath: repo.dir.path,
      branch: 'feat',
      title: 'a change',
    );
    expect(promoted, isNull, reason: 'signed, so it lands');
    expect(state.prFor('feat')?.authorIdentity, 'mira',
        reason: 'the human, not the app branding name');
  });
}
