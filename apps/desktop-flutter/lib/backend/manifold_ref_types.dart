// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// manifold_ref_types.dart — the typed algebra of the Manifold ref namespace.
//
// Zero-cost extension types (erased to String at runtime) that make the
// string-kind confusions of the metadata-ref plumbing UNREPRESENTABLE at
// compile time instead of caught-by-fuzzer at runtime:
//
//   * a live ref where a staged ref belongs (and vice versa) — the
//     live/staged conversion used to be substring surgery repeated at
//     three call sites; here it is two audited methods on [MetadataRemote];
//   * a blob/tree/commit SHA in the wrong `commit-tree` slot — the object
//     kinds are distinct types, so `commitTree(treeSha: someCommit)` no
//     longer compiles;
//   * a raw user string flowing into `update-ref` — ref names only come
//     out of validating factories that enforce git's refname rules;
//   * the "which fetch refspecs are legal" question — the ONLY
//     constructible Manifold fetch refspec is [MetadataRemote.fetchRefspec],
//     whose destination is the disposable staging namespace. The legacy
//     `+refs/manifold/*:refs/manifold/*` (which let a plain fetch
//     force-rewind live refs) cannot be expressed with these types.
//
// Everything `implements String`, so typed values still flow into argv
// lists, interpolation, and comparisons unchanged — adopting a type costs
// nothing at the call sites that were already correct. The reverse
// direction is the point: a String is NOT assignable to any of these, so
// raw strings die at the module boundary, parsed exactly once.
//
// Validation THROWS (ArgumentError) rather than asserting: these checks
// run at git-call rate (cheap), and a malformed ref name reaching
// `update-ref` is exactly the kind of corruption that must fail loudly in
// release builds too.

/// Anything git can resolve to an object: an [Oid] or a ref name. The
/// parameter type for "commitish" slots (`cat-file`, `rev-parse`,
/// `merge-base`) — callers must hold a typed value; raw strings are not
/// accepted.
extension type const Commitish._(String value) implements String {}

/// A validated 40- or 64-hex object id (SHA-1 or SHA-256) of unknown
/// kind. Prefer the kinded subtypes ([BlobOid]/[TreeOid]/[CommitOid])
/// wherever the kind is known. Git supports both object formats
/// (`git init --object-format=sha256` yields 64-hex OIDs); the validating
/// factories accept either width so a SHA-256 repository is first-class.
extension type const Oid._(String value) implements Commitish {
  factory Oid(String raw) {
    _checkOid(raw);
    return Oid._(raw);
  }

  /// The null-object OID sentinel — "this ref does not exist". Two roles:
  /// as a `--force-with-lease` expected value it asserts absence on the
  /// remote; as `update-ref`'s expected-old value it is git's native
  /// CAS-on-non-existence.
  ///
  /// Spelled at SHA-1 width (40 zeros) as a format-agnostic MARKER only.
  /// Git rejects a wrong-width zero at the CAS/lease boundary ("not a
  /// valid old SHA1" / "cannot parse expected object name"), so a SHA-256
  /// repository needs a 64-zero sentinel. This raw constant must therefore
  /// never be handed to git for a CAS/lease directly: size it to the
  /// operation's companion OID via [zeroFor] (or let a call site normalize
  /// it against the real `newSha`). [isZero] recognises a null OID at
  /// EITHER width.
  static const Oid zero = Oid._('0000000000000000000000000000000000000000');

  /// A null-object OID sized to [sample]'s object format — 40 hex zeros
  /// for a SHA-1 repository, 64 for SHA-256. Git rejects a wrong-width
  /// zero as a CAS/lease expected value, and [sample] (always a real OID
  /// of the same repository) reveals the correct width. The only way to
  /// mint a null-object sentinel that is correct on BOTH object formats.
  static Oid zeroFor(Oid sample) => Oid._('0' * sample.value.length);

  /// True when this is a null-object OID (all-zero hex) at EITHER object
  /// format — a 40- or 64-zero string. Recognises the CAS/lease absence
  /// sentinel regardless of hash algorithm.
  bool get isZero {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      if (value.codeUnitAt(i) != 0x30) return false; // '0'
    }
    return true;
  }
}

/// The id of a blob object — what `hash-object` returns and the only
/// thing a tree entry's content slot accepts.
extension type const BlobOid._(String value) implements Oid {
  factory BlobOid(String raw) {
    _checkOid(raw);
    return BlobOid._(raw);
  }
}

/// The id of a tree object — what `mktree`/`merge-tree --write-tree`
/// return and the only thing `commit-tree`'s tree slot accepts.
extension type const TreeOid._(String value) implements Oid {
  factory TreeOid(String raw) {
    _checkOid(raw);
    return TreeOid._(raw);
  }
}

/// The id of a commit object — ref tips, commit parents, lease values.
extension type const CommitOid._(String value) implements Oid {
  factory CommitOid(String raw) {
    _checkOid(raw);
    return CommitOid._(raw);
  }

  static CommitOid? tryParse(String raw) =>
      _isOid(raw) ? CommitOid._(raw) : null;
}

/// Any ref this app may write with `update-ref`: a live shared ref
/// under `refs/manifold/` or a local-only ref under
/// `refs/manifold-local/`. The supertype exists so the plumbing's
/// write methods accept both while the SYNC machinery stays typed to
/// [LiveManifoldRef] alone — local refs are unrepresentable there.
extension type const WritableManifoldRef._(String value)
    implements Commitish {}

/// A local-only ref under `refs/manifold-local/` — private state
/// (draft comments, unpublished reviews) that must NEVER enter the
/// shared object graph. The namespace is excluded by construction:
/// the only constructible fetch refspec maps `refs/manifold/*`, and
/// [ManifoldNs.localRoot] is not under it (a `manifold-local` path
/// component does not match the `manifold/` prefix), so no sync,
/// fetch, or push ever carries these refs. Publishing is the only
/// crossing point, and it is an explicit read-here/write-there.
extension type const ManifoldLocalRef._(String value)
    implements WritableManifoldRef {
  factory ManifoldLocalRef.parse(String raw) {
    if (!raw.startsWith(ManifoldNs.localRoot)) {
      throw ArgumentError.value(raw, 'raw', 'not under ${ManifoldNs.localRoot}');
    }
    _checkRefWellFormed(raw);
    return ManifoldLocalRef._(raw);
  }

  /// The draft store for the review of desk PR [deskId]:
  /// `refs/manifold-local/review/<deskId>/drafts`.
  factory ManifoldLocalRef.reviewDrafts(int deskId) {
    if (deskId <= 0) {
      throw ArgumentError.value(deskId, 'deskId', 'desk ids start at 1');
    }
    return ManifoldLocalRef._('${ManifoldNs.localRoot}review/$deskId/drafts');
  }
}

/// A live metadata ref under `refs/manifold/` — the only refs the app
/// ever syncs, and the only kind the reconcile engine moves.
/// Constructed via the grammar factories ([issue]/[desk]/[parse]) so a
/// malformed or out-of-namespace name can never reach git.
extension type const LiveManifoldRef._(String value)
    implements WritableManifoldRef {
  /// Wrap a refname already known to be live-namespace (e.g. read back
  /// from `for-each-ref refs/manifold/`). Validates namespace + git
  /// refname well-formedness.
  factory LiveManifoldRef.parse(String raw) {
    if (!raw.startsWith(ManifoldNs.prefix)) {
      throw ArgumentError.value(
          raw, 'raw', 'not under ${ManifoldNs.prefix}');
    }
    _checkRefWellFormed(raw);
    return LiveManifoldRef._(raw);
  }

  /// The ref of local issue [id]: `refs/manifold/issues/<id>`.
  factory LiveManifoldRef.issue(int id) {
    if (id <= 0) throw ArgumentError.value(id, 'id', 'issue ids start at 1');
    return LiveManifoldRef._('${ManifoldNs.issuesPrefix}$id');
  }

  /// The ref of the desk PR for [encodedBranchTail] (the INJECTIVELY
  /// ENCODED branch name — see desk_pr_store's encodeBranch — never the
  /// raw branch name): `refs/manifold/desks/<encoded>`.
  factory LiveManifoldRef.desk(String encodedBranchTail) {
    final ref = '${ManifoldNs.desksPrefix}$encodedBranchTail';
    _checkRefWellFormed(ref);
    return LiveManifoldRef._(ref);
  }

  /// The mutable review-state doc of desk PR [deskId]:
  /// `refs/manifold/review/<deskId>/state`.
  factory LiveManifoldRef.reviewState(int deskId) {
    if (deskId <= 0) {
      throw ArgumentError.value(deskId, 'deskId', 'desk ids start at 1');
    }
    return LiveManifoldRef._('${ManifoldNs.reviewPrefix}$deskId/state');
  }

  /// Round [n] of desk PR [deskId]'s review:
  /// `refs/manifold/review/<deskId>/round/<n>`. Points at a REAL
  /// commit of the reviewed branch (the pinned snapshot), not an
  /// orphan metadata commit — the ref's whole job is keeping that
  /// snapshot reachable and transferable, force-push-proof.
  factory LiveManifoldRef.reviewRound(int deskId, int n) {
    if (deskId <= 0) {
      throw ArgumentError.value(deskId, 'deskId', 'desk ids start at 1');
    }
    if (n <= 0) {
      throw ArgumentError.value(n, 'n', 'rounds start at 1');
    }
    return LiveManifoldRef._('${ManifoldNs.reviewPrefix}$deskId/round/$n');
  }

  /// The namespace-relative tail (`issues/7`, `desks/<encoded>`,
  /// `_id-counter`).
  String get tail => value.substring(ManifoldNs.prefix.length);
}

/// A staged ref under `refs/manifold-remote/<remote>/` — where fetches
/// land. Disposable by design; never mutated except by fetch. Convert to
/// its live counterpart via [MetadataRemote.unstage].
extension type const StagedManifoldRef._(String value) implements Commitish {
  factory StagedManifoldRef.parse(String raw) {
    if (!raw.startsWith(ManifoldNs.stagingRoot)) {
      throw ArgumentError.value(
          raw, 'raw', 'not under ${ManifoldNs.stagingRoot}');
    }
    _checkRefWellFormed(raw);
    return StagedManifoldRef._(raw);
  }
}

/// The one remote every Manifold surface agrees on for a given operation
/// (see ManifoldRefs.resolveMetadataRemote). Owns the ONLY live↔staged
/// conversions and the ONLY constructible fetch refspec — whose
/// destination is always the staging namespace, so the legacy live-ref
/// refspec (`+refs/manifold/*:refs/manifold/*`) is unrepresentable.
extension type const MetadataRemote(String name) implements String {
  /// `refs/manifold-remote/<remote>/` — this remote's staging namespace.
  String get stagingPrefix => '${ManifoldNs.stagingRoot}$name/';

  /// The fetch refspec written into `remote.<name>.fetch`. Force (`+`)
  /// is harmless because the destination is the disposable staging
  /// namespace, never a live ref.
  String get fetchRefspec => '+${ManifoldNs.prefix}*:$stagingPrefix*';

  /// Where [ref] lands when fetched from this remote.
  StagedManifoldRef stage(LiveManifoldRef ref) =>
      StagedManifoldRef._('$stagingPrefix${ref.tail}');

  /// The live counterpart of a ref staged FOR THIS REMOTE. Throws when
  /// [staged] belongs to a different remote's staging namespace — using
  /// remote A's snapshot to reconcile remote B is a data-loss bug, not a
  /// conversion.
  LiveManifoldRef unstage(StagedManifoldRef staged) {
    if (!staged.value.startsWith(stagingPrefix)) {
      throw ArgumentError.value(staged.value, 'staged',
          'not staged for remote "$name" (expected $stagingPrefix*)');
    }
    return LiveManifoldRef._(
        '${ManifoldNs.prefix}${staged.value.substring(stagingPrefix.length)}');
  }

  /// The staging-side prefix corresponding to a LIVE namespace prefix —
  /// the one audited home for the substring arithmetic previously
  /// duplicated at every staged-scan call site.
  String stagedPrefixOf(String livePrefix) {
    if (!livePrefix.startsWith(ManifoldNs.prefix)) {
      throw ArgumentError.value(
          livePrefix, 'livePrefix', 'not under ${ManifoldNs.prefix}');
    }
    return '$stagingPrefix${livePrefix.substring(ManifoldNs.prefix.length)}';
  }
}

/// The Manifold namespace layout — every prefix and well-known ref in one
/// place. String constants (not types) because they are for-each-ref
/// PATTERNS; whole refs are typed.
abstract final class ManifoldNs {
  /// The whole live metadata namespace.
  static const String prefix = 'refs/manifold/';

  /// Root of all per-remote staging namespaces.
  static const String stagingRoot = 'refs/manifold-remote/';

  /// Root of the local-only namespace. NOT under [prefix] (the path
  /// component is `manifold-local`, not `manifold`), so the fetch
  /// refspec and the whole-namespace sync can never see it.
  static const String localRoot = 'refs/manifold-local/';

  static const String issuesPrefix = '${prefix}issues/';
  static const String desksPrefix = '${prefix}desks/';

  /// Review namespace: `refs/manifold/review/<deskId>/state` (mutable
  /// doc) and `refs/manifold/review/<deskId>/round/<n>` (immutable
  /// pins).
  static const String reviewPrefix = '${prefix}review/';

  static final RegExp _reviewStateRe =
      RegExp(r'^refs/manifold/review/[1-9][0-9]*/state$');
  static final RegExp _reviewRoundRe =
      RegExp(r'^refs/manifold/review/[1-9][0-9]*/round/[1-9][0-9]*$');

  /// True for a review-state doc ref — the record kind whose
  /// divergence merge uses the DECLARED review schema instead of the
  /// legacy shape-sniffing merge. EXACT shape, not substring sniffing:
  /// with third-party writers a design goal, a foreign ref like
  /// `review/x/state/extra` must fall to the generic path, never be
  /// schema-merged by accident.
  static bool isReviewStateRef(String ref) => _reviewStateRe.hasMatch(ref);

  /// True for an immutable review-round pin. These point at real
  /// branch commits, so the reconcile engine must never tree-merge or
  /// fast-forward them: same-name divergence converges by
  /// deterministic sha choice, nothing else. Exact shape for the same
  /// interop reason as [isReviewStateRef].
  static bool isReviewRoundRef(String ref) => _reviewRoundRe.hasMatch(ref);

  /// The shared id-counter ref — DeskPrStore and DeskIssueStore both
  /// allocate from it so PR-ids and issue-ids never collide.
  static const LiveManifoldRef idCounter =
      LiveManifoldRef._('${prefix}_id-counter');
}

bool _isOid(String s) {
  // Both git object formats: SHA-1 is 40 hex chars, SHA-256 is 64. Anything
  // else (39/41/63/65, uppercase, non-hex) is rejected.
  if (s.length != 40 && s.length != 64) return false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final hex = (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66);
    if (!hex) return false; // lowercase hex only — git's canonical output
  }
  return true;
}

void _checkOid(String s) {
  if (!_isOid(s)) {
    throw ArgumentError.value(
        s, 'oid', 'not a 40- or 64-char lowercase-hex oid (SHA-1 or SHA-256)');
  }
}

/// git check-ref-format, the subset that matters for refs this app mints:
/// printable ASCII, no components starting with '.' or ending in '.lock',
/// none of git's forbidden characters or sequences. Mirrors the rules
/// enforced by `git check-ref-format` (verified against git 2.x docs and
/// behaviour); anything rejected here would also be rejected — or worse,
/// misparsed — by git itself.
void _checkRefWellFormed(String ref) {
  void bad(String why) =>
      throw ArgumentError.value(ref, 'ref', 'malformed refname: $why');
  if (ref.isEmpty) bad('empty');
  if (ref.endsWith('/')) bad('trailing slash');
  if (ref.endsWith('.')) bad('trailing dot');
  if (ref.contains('..')) bad("contains '..'");
  if (ref.contains('//')) bad("contains '//'");
  if (ref.contains('@{')) bad("contains '@{'");
  for (final c in ref.codeUnits) {
    if (c <= 0x20 || c == 0x7f) bad('control byte or space (0x${c.toRadixString(16)})');
    const forbidden = [0x7e, 0x5e, 0x3a, 0x3f, 0x2a, 0x5b, 0x5c]; // ~^:?*[\
    if (forbidden.contains(c)) {
      bad("forbidden character '${String.fromCharCode(c)}'");
    }
  }
  for (final component in ref.split('/')) {
    if (component.isEmpty) bad('empty path component');
    if (component.startsWith('.')) bad("component starts with '.'");
    if (component.endsWith('.lock')) bad("component ends with '.lock'");
  }
}
