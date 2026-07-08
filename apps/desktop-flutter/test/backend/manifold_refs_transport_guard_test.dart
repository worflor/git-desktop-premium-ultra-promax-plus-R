import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Architectural tripwire, not a behavior test — deliberately unusual for
/// this suite, which otherwise exercises real git plumbing rather than
/// grepping source text.
///
/// `manifold_refs.dart` was just migrated onto [git.runGit] for every git
/// invocation EXCEPT two documented, deliberate holdouts (`writeBlob` /
/// `mkTree`): both need to pipe content to the child's stdin
/// (`hash-object --stdin`, `mktree`), and the shared runner's surface is
/// pure request/response with no stdin support (see the doc comments on
/// those two functions). Every other call goes through `git.runGit`,
/// which is the ONLY place `GIT_TERMINAL_PROMPT=0` / `GIT_OPTIONAL_LOCKS=0`
/// / `LC_ALL=C`, the subprocess semaphore throttle, and the transient
/// `index.lock` retry are applied. A casually reintroduced direct
/// `Process.run`/`Process.start` call in this file — e.g. someone adding a
/// third git invocation by copy-pasting a nearby line instead of reaching
/// for `git.runGit` — would silently lose every one of those guarantees:
/// no interactive-auth guard, no throttle, no lock-contention retry.
///
/// There is no compiler or lint rule that catches "a new direct subprocess
/// spawn appeared in this specific file" — the type signatures of
/// `Process.run`/`Process.start` and `git.runGit` don't differ in a way an
/// analyzer could flag as wrong. A source-grep test is an unusual shape for
/// this codebase (which strongly prefers exercising real behavior over
/// asserting on text), but it is the only mechanism that catches this
/// specific regression class before it lands — matching this repo's
/// make-the-bug-class-unrepresentable culture. If this test fails because
/// someone added a THIRD legitimate stdin-piping call, that's fine: raise
/// the constant below, add the same "why not git.runGit" doc comment as
/// [writeBlob]/[mkTree] carry, and move on. If it fails because a call was
/// added WITHOUT such a comment, that's the bug this test exists to catch.
void main() {
  test(
      'manifold_refs.dart has exactly the two documented direct '
      'Process.run/Process.start call sites (writeBlob, mkTree) — a third '
      'must not appear without becoming a third documented holdout',
      () {
    final file = File(p.join(
        Directory.current.path, 'lib', 'backend', 'manifold_refs.dart'));
    expect(file.existsSync(), isTrue,
        reason: 'expected to find lib/backend/manifold_refs.dart relative '
            'to the test runner\'s working directory (repo root)');
    final source = file.readAsStringSync();

    // Match the call syntax, not just the token, so an unrelated comment
    // mentioning "Process.run" in prose doesn't skew the count.
    final directSpawnPattern = RegExp(r'Process\.(run|start)\s*\(');
    final matches = directSpawnPattern.allMatches(source).toList();

    const documentedAllowlist = 2; // writeBlob + mkTree, both Process.start
    expect(matches.length, documentedAllowlist,
        reason: 'manifold_refs.dart should have exactly '
            '$documentedAllowlist direct Process.run/Process.start call '
            '(s) — the documented writeBlob/mkTree stdin-piping holdouts. '
            'Found ${matches.length}. Every other git invocation in this '
            'file MUST go through git.runGit so it inherits the shared '
            'non-interactive environment, subprocess throttle, and '
            'index.lock retry; a new direct call needs the same '
            '"why not git.runGit" justification writeBlob/mkTree carry, '
            'and this constant raised to match.');
  });
}
