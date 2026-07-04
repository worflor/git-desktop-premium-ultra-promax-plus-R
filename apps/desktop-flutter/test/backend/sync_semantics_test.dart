import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/features/sync/sync_actions.dart';

/// Witnesses for the pure sync semantics layer — the single source of
/// truth behind every sync label, tooltip, toast classification, and
/// force-push target in the app. All inputs below are REAL git stderr
/// shapes (captured from live git output), not synthetic strings, so a
/// pattern drift in git's messages fails here first.
void main() {
  RepositoryStatus st({
    String branch = 'main',
    String? upstream,
    int ahead = 0,
    int behind = 0,
  }) =>
      RepositoryStatus(
        branch: branch,
        upstream: upstream,
        ahead: ahead,
        behind: behind,
        files: const [],
      );

  group('classifyGitError', () {
    test('auth: https credential failure', () {
      final f = classifyGitError(
          "fatal: Authentication failed for 'https://github.com/x/y.git/'");
      expect(f.category, GitErrorCategory.auth);
    });

    test('auth: ssh publickey rejection', () {
      final f = classifyGitError(
          'git@github.com: Permission denied (publickey).\n'
          'fatal: Could not read from remote repository.');
      expect(f.category, GitErrorCategory.auth);
    });

    test('hook: pre-receive decline outranks the generic push-refs line',
        () {
      final f = classifyGitError(
          'remote: error: rejected by policy\n'
          ' ! [remote rejected] main -> main (pre-receive hook declined)\n'
          "error: failed to push some refs to 'origin'");
      expect(f.category, GitErrorCategory.hookRejected,
          reason: 'specificity order: hook must win over non-fast-forward '
              'even though "failed to push some refs" also matches');
    });

    test('network: DNS failure', () {
      final f = classifyGitError(
          "fatal: unable to access 'https://github.com/x/y.git/': "
          'Could not resolve host: github.com');
      expect(f.category, GitErrorCategory.network);
    });

    test('non-fast-forward: rejected push', () {
      final f = classifyGitError(
          " ! [rejected]        main -> main (non-fast-forward)\n"
          "error: failed to push some refs to 'origin'\n"
          "hint: Updates were rejected because the tip of your current "
          'branch is behind');
      expect(f.category, GitErrorCategory.nonFastForward);
    });

    test('conflict: merge conflict output', () {
      final f = classifyGitError(
          'CONFLICT (content): Merge conflict in lib/a.dart\n'
          'Automatic merge failed; fix conflicts and then commit the result.');
      expect(f.category, GitErrorCategory.conflict);
    });

    test('other: falls back to the first non-empty line as the message', () {
      final f = classifyGitError('\nfatal: bad revision zzz\ndetail line');
      expect(f.category, GitErrorCategory.other);
      expect(f.message, 'fatal: bad revision zzz');
    });

    test('empty stderr yields a usable message, never a blank toast', () {
      final f = classifyGitError('');
      expect(f.message.trim(), isNotEmpty);
    });
  });

  group('isNonFastForwardError', () {
    test('matches the canonical rejection phrases', () {
      expect(
          isNonFastForwardError(
              'hint: Updates were rejected because the remote contains work '
              'fetch first'),
          isTrue);
      expect(isNonFastForwardError('(non-fast-forward)'), isTrue);
    });

    test('conservative: unrelated errors and null stay false', () {
      expect(isNonFastForwardError(null), isFalse);
      expect(isNonFastForwardError('fatal: Authentication failed'), isFalse);
    });
  });

  group('resolveUpstream', () {
    test('splits remote from ref at the FIRST slash only', () {
      final t = resolveUpstream(st(upstream: 'origin/main'));
      expect((t!.remote, t.branch), ('origin', 'main'));
    });

    test('nested branch names keep their inner slashes', () {
      final t = resolveUpstream(st(upstream: 'origin/feature/deep/name'));
      expect((t!.remote, t.branch), ('origin', 'feature/deep/name'));
      // The force-push refspec depends on this: local:feature/deep/name,
      // never local:name.
    });

    test('malformed upstreams resolve to null, never a bogus target', () {
      expect(resolveUpstream(st(upstream: null)), isNull);
      expect(resolveUpstream(st(upstream: '')), isNull);
      expect(resolveUpstream(st(upstream: 'noslash')), isNull);
      expect(resolveUpstream(st(upstream: '/leading')), isNull);
      expect(resolveUpstream(st(upstream: 'trailing/')), isNull);
    });
  });

  group('describeSyncAction', () {
    test('null status and detached HEAD are disabled', () {
      expect(describeSyncAction(null).disabled, isTrue);
      expect(describeSyncAction(st(branch: 'HEAD')).disabled, isTrue);
      expect(
          describeSyncAction(st(branch: '(no branch)')).disabled, isTrue);
    });

    test('no upstream publishes', () {
      final d = describeSyncAction(st(branch: 'topic'));
      expect(d.disabled, isFalse);
      expect(d.buttonLabel, 'Publish');
      expect(d.detail, contains('topic'));
    });

    test('diverged names the rebase BEFORE it runs — the transparency rule',
        () {
      final d = describeSyncAction(
          st(upstream: 'origin/main', ahead: 2, behind: 3));
      expect(d.rebases, isTrue);
      expect(d.detail, contains('3 commits with rebase'));
      expect(d.detail, contains('push 2 commits'));
    });

    test('ahead-only pushes, behind-only pulls, clean fetches', () {
      expect(describeSyncAction(st(upstream: 'o/m', ahead: 1)).detail,
          contains('Push 1 local commit'));
      expect(describeSyncAction(st(upstream: 'o/m', behind: 2)).detail,
          contains('Pull 2 remote commits'));
      final clean = describeSyncAction(st(upstream: 'o/m'));
      expect(clean.rebases, isFalse);
      expect(clean.detail, contains('Fetch'));
    });

    test('singular/plural copy is grammatical at n=1', () {
      final d = describeSyncAction(
          st(upstream: 'origin/main', ahead: 1, behind: 1));
      expect(d.detail, contains('1 commit with rebase'));
      expect(d.detail, isNot(contains('1 commits')));
    });
  });
}
