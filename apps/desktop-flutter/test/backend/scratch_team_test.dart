// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// scratch_team_test.dart — contracts for the multi-author/multi-clone lab.
//
// The review primitives will develop against ScratchTeam; these pin the
// harness itself so a lab failure is never mistaken for a feature bug:
//  T1  commitAllAs stamps the overridden author AND committer without
//      touching the repo's configured identity.
//  T2  A team round-trips content: alice pushes, bob pulls, and each
//      member's commits carry that member's identity by default.
//  T3  The manifold-ref topology works across the team: a live ref
//      pushed by one member lands in another's staging namespace via
//      the exact staging refspec production sync uses.

import 'package:flutter_test/flutter_test.dart';

import '../support/scratch_repo.dart';
import '../support/scratch_team.dart';

void main() {
  test('T1: commitAllAs overrides author+committer per commit', () async {
    final repo = await ScratchRepo.create(name: 'multi_author');
    try {
      await repo.writeFile('a.txt', 'one\n');
      await repo.commitAllAs(
          name: 'mira', email: 'mira@example.invalid', message: 'by mira');
      await repo.writeFile('a.txt', 'two\n');
      await repo.commitAllAs(
          name: 'jun', email: 'jun@example.invalid', message: 'by jun');
      await repo.writeFile('a.txt', 'three\n');
      await repo.commitAll('by default identity');

      final log = await repo.gitOk(
          ['log', '--format=%an|%ae|%cn|%ce', '-n', '3']);
      final lines = log.split('\n');
      expect(lines[0], 'Scratch Repo|scratch@example.invalid|'
          'Scratch Repo|scratch@example.invalid',
          reason: 'configured identity must be untouched by the overrides');
      expect(lines[1], 'jun|jun@example.invalid|jun|jun@example.invalid',
          reason: 'author AND committer must both carry the override');
      expect(lines[2], 'mira|mira@example.invalid|mira|mira@example.invalid');
    } finally {
      await repo.dispose();
    }
  });

  test('T2: team round-trips content with per-member identity', () async {
    final team = await ScratchTeam.create();
    try {
      final alice = team['alice'];
      final bob = team['bob'];

      await alice.writeFile('feature.dart', 'void main() {}\n');
      await alice.commitAll('alice ships');
      await alice.gitOk(['push', '-q', 'origin', 'main']);

      await bob.gitOk(['pull', '-q']);
      final authors = await bob.gitOk(['log', '--format=%an|%ae', '-n', '1']);
      expect(authors, 'alice|alice@example.invalid',
          reason: "alice's commit must arrive authored as alice");

      await bob.writeFile('feature.dart', 'void main() { run(); }\n');
      await bob.commitAll('bob follows up');
      final bobAuthor =
          await bob.gitOk(['log', '--format=%an|%ae', '-n', '1']);
      expect(bobAuthor, 'bob|bob@example.invalid',
          reason: "bob's default identity must be bob, not the scratch one");
    } finally {
      await team.dispose();
    }
  });

  test('T3: a pushed manifold ref reaches a peer via staging', () async {
    final team = await ScratchTeam.create();
    try {
      final alice = team['alice'];
      final bob = team['bob'];

      final sha = (await alice.head())!;
      await alice.gitOk(['update-ref', 'refs/manifold/desks/demo', sha]);
      await alice.gitOk([
        'push', '-q', 'origin',
        'refs/manifold/desks/demo:refs/manifold/desks/demo',
      ]);

      // The exact staging refspec ManifoldRefs.fetchToStaging uses:
      // force-fetch into the disposable per-remote namespace, never a
      // live ref.
      await bob.gitOk([
        'fetch', '-q', 'origin',
        '+refs/manifold/*:refs/manifold-remote/origin/*',
      ]);
      final refs = await bob.allRefs();
      expect(refs, contains('refs/manifold-remote/origin/desks/demo'),
          reason: 'the peer must see the ref in staging');
      expect(refs, isNot(contains('refs/manifold/desks/demo')),
          reason: 'a fetch must never create a live ref on the peer');
      final staged = await bob
          .gitOk(['rev-parse', 'refs/manifold-remote/origin/desks/demo']);
      expect(staged, sha);
    } finally {
      await team.dispose();
    }
  });
}
