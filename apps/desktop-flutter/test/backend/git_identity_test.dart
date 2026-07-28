// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// git_identity_test.dart — the human behind a review record.
//
// Two halves, tested where each is honest:
//  * identityFrom(): every fallback branch, hermetically. This is where
//    "no identity" is provable — the IO half reads the developer's real
//    ~/.gitconfig (ScratchRepo isolates config for the commands IT runs,
//    not for the app's own reads), so a "returns null when unset" test
//    against a real repo would pass or fail by accident of the machine.
//  * resolveGitIdentity(): against a real repo, only for the cases a
//    LOCAL config value decides outright — local beats global, so those
//    stay deterministic on any machine.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git_identity.dart';

import '../support/scratch_repo.dart';

void main() {
  group('identityFrom — the pure half', () {
    test('I1: no config at all is nobody, never a placeholder', () {
      expect(identityFrom(), isNull);
      expect(identityFrom(name: null, email: null), isNull);
      // The one that matters: an invented name here would be written
      // into a ref and SYNCED to peers as if a person said it.
      expect(identityFrom(name: '', email: ''), isNull);
      expect(identityFrom(name: '   ', email: '  '), isNull);
    });

    test('I2: name wins, email rides along as the stable key', () {
      final id = identityFrom(name: 'Mira Okafor', email: 'Mira@Example.COM');
      expect(id!.display, 'Mira Okafor');
      // Lower-cased: the key is meant to survive a peer typing their own
      // address with different capitalisation.
      expect(id.key, 'mira@example.com');
    });

    test('I3: email alone yields its local part as the display', () {
      final id = identityFrom(email: 'jun.park@example.com');
      expect(id!.display, 'jun.park');
      expect(id.key, 'jun.park@example.com');
    });

    test('I4: an email with no local part is not a person', () {
      expect(identityFrom(email: '@example.com'), isNull);
      // No `@` at all: not an address, but it is still SOMETHING the
      // user configured, so it names them rather than being discarded.
      expect(identityFrom(email: 'jun')!.display, 'jun');
    });

    test('I5: name without an email is a person with no stable key', () {
      final id = identityFrom(name: 'Mira');
      expect(id!.display, 'Mira');
      expect(id.key, isNull, reason: 'a key is not invented from a name');
    });

    test('I6: an embedded newline collapses to one line', () {
      // git config genuinely round-trips this: the file stores an
      // escaped \n and `--get` un-escapes it back to a real newline
      // (verified against the binary). A trim only fixes the ends, and
      // every consumer renders a display as a single line.
      final id = identityFrom(name: 'Line1\nLine2', email: 'a@b.c');
      expect(id!.display, 'Line1 Line2');
      expect(id.display, isNot(contains('\n')));
    });

    test('I7: surrounding and interior whitespace normalises', () {
      expect(identityFrom(name: '  Spacey   Name  ')!.display, 'Spacey Name');
      expect(identityFrom(name: 'Tab\tSeparated')!.display, 'Tab Separated');
      // Trailing newline is what a real `git config --get` always
      // returns, so this is the ordinary case rather than an edge one.
      expect(identityFrom(name: 'Mira\n')!.display, 'Mira');
    });

    test('I8: a whitespace-only name falls through to the email', () {
      // git config accepts "   " as a value and reports exit 0 for it,
      // so this arrives as a configured-but-empty name rather than as
      // an unset key.
      final id = identityFrom(name: '   ', email: 'mira@example.com');
      expect(id!.display, 'mira');
    });

    test('I9: characters git strips from an ident line survive here', () {
      // git silently drops < and > when it writes a commit's ident. The
      // RECORD is not a commit ident, and dropping them would make the
      // display disagree with what the user configured for no benefit.
      final id = identityFrom(name: 'Weird <Angle> Name');
      expect(id!.display, 'Weird <Angle> Name');
    });

    test('I10: display and key are independent fields', () {
      // Asserted field by field rather than through operator==, which
      // this type deliberately does not have: two people can share a
      // display and be told apart only by the key, and the records that
      // merge them compare those fields directly.
      const named = GitIdentity(display: 'mira', key: 'mira@example.com');
      const anonymous = GitIdentity(display: 'mira');
      expect(named.display, anonymous.display);
      expect(named.key, 'mira@example.com');
      expect(anonymous.key, isNull, reason: 'same name, no account');
    });
  });

  group('resolveGitIdentity — against a real repo', () {
    late ScratchRepo repo;

    setUp(() async => repo = await ScratchRepo.create(name: 'identity'));
    tearDown(() => repo.dispose());

    test('I11: a local user.name is the answer', () async {
      await repo.gitOk(['config', '--local', 'user.name', 'Mira Okafor']);
      await repo.gitOk(
          ['config', '--local', 'user.email', 'mira@example.com']);
      final id = await resolveGitIdentity(repo.dir.path);
      expect(id!.display, 'Mira Okafor');
      expect(id.key, 'mira@example.com');
    });

    test('I12: a multivalued key resolves to the last value', () async {
      // `--get` takes the last value at the most local scope with no
      // ambiguity error — confirmed against the binary. This pins that
      // we read the same identity git would sign a commit with.
      await repo.gitOk(['config', '--local', 'user.email', 'first@e.com']);
      await repo.gitOk(
          ['config', '--local', '--add', 'user.email', 'second@e.com']);
      await repo.gitOk(['config', '--local', 'user.name', 'Mira']);
      final id = await resolveGitIdentity(repo.dir.path);
      expect(id!.key, 'second@e.com');
    });

    test('I13: a name set through git config arrives as one line',
        () async {
      // The end-to-end version of I6: written through git's own config
      // writer, read back through our resolver.
      await repo.gitOk(['config', '--local', 'user.name', 'Line1\nLine2']);
      final id = await resolveGitIdentity(repo.dir.path);
      expect(id!.display, 'Line1 Line2');
    });

    test('I14: a locally-blank name shadows any global one', () async {
      // Local scope wins the cascade, so this is deterministic even on a
      // machine with a real global identity: the blank local value is
      // what `--get` returns, and a blank name is not a person.
      await repo.gitOk(['config', '--local', 'user.name', '   ']);
      await repo.gitOk(['config', '--local', 'user.email', 'jun@e.com']);
      final id = await resolveGitIdentity(repo.dir.path);
      expect(id!.display, 'jun',
          reason: 'falls through to the email rather than a blank person');
    });
  });
}
