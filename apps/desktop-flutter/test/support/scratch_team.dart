// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// scratch_team.dart — a synthetic team: one bare origin, N member clones.
//
// The two-machine lab the review primitives develop against: each
// member is a full ScratchRepo (own sandbox, own identity, config
// isolation) whose `origin` points at a shared bare repo, so
// fetch/push/reconcile flows exercise the exact multi-clone topology a
// real team has — including the manifold-ref staging namespace dance —
// with zero network. Every commit a member makes is authored as that
// member by default; `commitAllAs` still overrides per commit.

import 'dart:io';

import 'package:git_desktop/backend/git.dart';
import 'package:path/path.dart' as p;

import 'scratch_repo.dart';

class ScratchTeam {
  /// Private sandbox holding only the bare origin.
  final Directory _sandbox;

  /// Filesystem path of the shared bare origin repository.
  final String originPath;

  /// Member clones by name, in creation order.
  final Map<String, ScratchRepo> members;

  ScratchTeam._(this._sandbox, this.originPath, this.members);

  ScratchRepo operator [](String name) {
    final repo = members[name];
    if (repo == null) {
      throw ArgumentError.value(name, 'name',
          'no such team member (have: ${members.keys.join(', ')})');
    }
    return repo;
  }

  static String emailFor(String member) => '$member@example.invalid';

  /// Build a team: a bare `origin.git` seeded with a root commit on
  /// `main`, plus one clone per entry in [memberNames], each configured
  /// with that member's identity. The first member seeds the origin (its
  /// root commit is authored by the scratch default identity, matching
  /// [ScratchRepo.create]'s bootstrap commit); every member ends up a
  /// clone-equivalent with `origin` wired and `main` tracking.
  static Future<ScratchTeam> create({
    List<String> memberNames = const ['alice', 'bob'],
  }) async {
    if (memberNames.isEmpty) {
      throw ArgumentError.value(
          memberNames, 'memberNames', 'a team needs at least one member');
    }
    final sandbox = await Directory.systemTemp.createTemp('scratch_team_');
    final originPath = p.join(sandbox.path, 'origin.git');
    final isolation = {
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': p.join(sandbox.path, '.scratch-no-global'),
      'GIT_CONFIG_SYSTEM': p.join(sandbox.path, '.scratch-no-system'),
    };
    final init = await runGit(
        sandbox.path, ['init', '--bare', '-q', '-b', 'main', 'origin.git'],
        extraEnv: isolation);
    if (init.exitCode != 0) {
      throw StateError('bare init failed: ${init.stderr}');
    }

    final members = <String, ScratchRepo>{};
    // First member bootstraps the origin: init, identity, push main.
    final first = memberNames.first;
    final seed = await ScratchRepo.create(name: 'team_$first');
    await seed.setIdentity(name: first, email: emailFor(first));
    await seed.gitOk(['remote', 'add', 'origin', originPath]);
    await seed.gitOk(['push', '-q', '-u', 'origin', 'main']);
    members[first] = seed;

    for (final name in memberNames.skip(1)) {
      members[name] = await ScratchRepo.cloneLocal(
        sourceUrl: originPath,
        name: 'team_$name',
        userName: name,
        userEmail: emailFor(name),
      );
    }
    return ScratchTeam._(sandbox, originPath, members);
  }

  /// Dispose every member and the origin sandbox. Best-effort, like
  /// [ScratchRepo.dispose].
  Future<void> dispose() async {
    for (final m in members.values) {
      await m.dispose();
    }
    try {
      await _sandbox.delete(recursive: true);
    } catch (_) {
      // Windows can hold handles briefly after a git process exits.
    }
  }
}
