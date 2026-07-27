// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// git_identity.dart — who git says the person at this keyboard is.
//
// Distinct from AppIdentityState, which is the APP's branding name (what
// the user called Manifold during onboarding). Conflating the two is not
// a cosmetic slip: review records carry the identity as their merge key,
// so an app-branding name means every reviewer on every machine writes
// under the same string. One attention key, no hand-off candidates, and
// `viewer == author` always true. Review identity has to be the human.
//
// The source is git's own config cascade (local -> global -> system) via
// `git config --get`, which is the same resolution the commits under
// review were authored with. That agreement is the point: the name on a
// review comment matches the name on the commits, with no second place
// to keep it in sync.
//
// EXPLICIT CONFIG ONLY. `git var GIT_AUTHOR_IDENT` would always answer,
// fabricating `user@hostname` from the OS when nothing is configured —
// git's implicit identity, the one it warns about. A fabricated name
// written into a ref that SYNCS TO PEERS is worse than no name, so an
// unconfigured repo resolves to null here and callers refuse the write
// rather than invent a person. Git itself refuses to commit in exactly
// this state; matching that contract keeps the two consistent.

import 'package:meta/meta.dart';

import 'git.dart' as git;

/// The remedy, spelled once. Shown verbatim wherever an unconfigured
/// identity blocks something, so the string a user copies is the string
/// this file actually reads back. Not localized: it is a command.
const String kGitIdentityCommand =
    'git config --global user.name "Your Name"';

/// The human at this keyboard, as git resolves them for one repo.
///
/// Held only when git actually has an identity: [display] is never empty
/// and never invented.
class GitIdentity {
  /// `user.name`, or the local part of `user.email` when only the email
  /// is configured. Never empty, always a single line.
  final String display;

  /// `user.email`, lower-cased, or null when unconfigured. Carried into
  /// records as the identity's stable key — the handle the review format
  /// promises and the merge engine does not interpret yet.
  final String? key;

  const GitIdentity({required this.display, this.key});

  @override
  bool operator ==(Object other) =>
      other is GitIdentity && other.display == display && other.key == key;

  @override
  int get hashCode => Object.hash(display, key);

  @override
  String toString() => key == null ? display : '$display <$key>';
}

/// Collapse a config value to one line of single-spaced text, or null
/// when nothing is left.
///
/// Not paranoia: git's config format accepts an escaped `\n` inside a
/// value and `--get` faithfully un-escapes it back to a real newline, so
/// `user.name` genuinely can arrive here multi-line (verified against
/// the binary, not the docs). A trim only fixes the ends. Every consumer
/// treats a display as one line — a list row, a chip, a commit-message
/// subject — so the collapse happens once, here.
///
/// git itself sanitizes the same way when it writes an ident line into a
/// commit object (it silently strips `<`, `>` and newlines), so this
/// keeps our stored display equal to what git would have recorded rather
/// than letting the two drift apart. A whitespace-only name collapses to
/// nothing and is therefore read as unconfigured, which is honest.
String? _oneLine(String? raw) {
  if (raw == null) return null;
  final v = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return v.isEmpty ? null : v;
}

/// The pure half: turn whatever git said into an identity, or nothing.
///
/// Split from the spawn so every branch is reachable in a test. The IO
/// half cannot be exercised hermetically for the "no identity anywhere"
/// case: the scratch-repo harness isolates global config for the
/// commands IT runs, not for the app's own reads, so a developer's real
/// `~/.gitconfig` would answer and the test would pass or fail by
/// accident of the machine.
@visibleForTesting
GitIdentity? identityFrom({String? name, String? email}) {
  final cleanName = _oneLine(name);
  final cleanEmail = _oneLine(email);
  // Lower-cased because the part of an address that identifies a person
  // is case-insensitive in practice, and this is the field the format
  // promises as a stable key.
  final key = cleanEmail?.toLowerCase();

  if (cleanName != null) return GitIdentity(display: cleanName, key: key);

  // Email without a name is a real configuration, and its local part is
  // the name the person already sees on their own commits in most
  // tooling. Prefer it over refusing.
  if (cleanEmail != null) {
    final at = cleanEmail.indexOf('@');
    // Three cases, and the middle one is the trap: no `@` means the
    // whole value is the handle the user chose, an `@` in the middle
    // means take the local part, and an `@` at position zero means
    // there IS no local part — "@example.com" names a domain, not a
    // person, so it is no more usable as a display than a blank.
    final local = at < 0 ? cleanEmail : cleanEmail.substring(0, at);
    final display = _oneLine(local);
    if (display != null) return GitIdentity(display: display, key: key);
  }

  return null;
}

/// Read one config key through git's full cascade. Null when unset:
/// `git config --get` exits 1 for a missing key, which is not an error
/// condition, just an answer.
///
/// `--get` (not `--get-all`) is deliberate: a multivalued key returns
/// the last value at the most local scope with no ambiguity error, which
/// is exactly git's own precedence for the identity it would use.
Future<String?> _config(String repoPath, String key) async {
  try {
    final r = await git.runGit(repoPath, ['config', '--get', key]);
    if (r.exitCode != 0) return null;
    return r.stdout as String;
  } catch (_) {
    return null;
  }
}

/// Resolve who git says you are in [repoPath], or null when git has no
/// configured identity to give.
///
/// Two spawns rather than one `--get-regexp`: the regexp form's output
/// needs parsing that a name containing whitespace (every name) makes
/// ambiguous, and both reads are coalesced and throttled by the shared
/// git path anyway.
Future<GitIdentity?> resolveGitIdentity(String repoPath) async {
  final name = await _config(repoPath, 'user.name');
  final email = await _config(repoPath, 'user.email');
  return identityFrom(name: name, email: email);
}
