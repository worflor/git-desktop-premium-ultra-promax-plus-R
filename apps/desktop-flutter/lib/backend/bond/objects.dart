// ═════════════════════════════════════════════════════════════════════════
// bond/objects.dart — signed object bodies
//
// All six Bond primitives that flow inside a [SignedEnvelope] with a
// kind tag matching the corresponding [BondPacketType]:
//
//   RefAdvert     — "I, signer, assert my refs point at these commits
//                    as of this Lamport clock"
//   Proposal      — "I, proposer, ask recipient to adopt target_ref
//                    from source_commit (bundled with title + body)"
//   Attestation   — "I, reviewer, attest this verdict on a proposal"
//   Anchor        — "I, author, tie this comment to this git object
//                    (or byte range within one)"
//   Target        — "I, author, declare an unfulfilled intent a
//                    future proposal can consume"
//   Policy        — "I, signer, declare consensus rules for this
//                    bond (which refs need how many attestations
//                    from which signers)"
//
// Bodies are CBOR maps with short string keys (`'b'` for bond_id,
// `'c'` for commit, etc.) — compact on the wire and deterministic
// under canonical CBOR ordering. Field reuse is intentional where
// semantics align.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:cbor/cbor.dart';

// ═════════════════════════════════════════════════════════════════════════
// RefAdvert
// ═════════════════════════════════════════════════════════════════════════

/// One peer's public claim about where their refs point. Gossiped on
/// change and periodically; adopted into `refs/bond/<signer>/...`
/// namespaces on receiving peers, subject to policy enforcement.
class RefAdvert {
  RefAdvert({
    required this.bondId,
    required this.lamportClock,
    required this.refs,
    required this.createdMs,
  });

  /// The bond this advertisement is scoped to. Receivers drop
  /// mismatched bond_ids before signature verification.
  final Uint8List bondId;

  /// Signer's monotonic clock. Receivers reject any advert with a
  /// clock ≤ the last-seen clock from this signer — basic replay
  /// protection. Not a global clock; per-signer, per-bond.
  final int lamportClock;

  /// Ref name → commit hash (20-byte SHA-1 or 32-byte SHA-256). Only
  /// refs the signer is willing to advertise appear; unmentioned
  /// refs stay at their previous advertised value (or unknown, if
  /// never advertised).
  final Map<String, Uint8List> refs;

  /// Wallclock timestamp at sign time, epoch ms. Informational
  /// (UI rendering, staleness warnings). Not used for ordering —
  /// Lamport clock is authoritative there.
  final int createdMs;

  Uint8List toCborBody() {
    final refsMap = <CborString, CborBytes>{};
    refs.forEach((name, hash) {
      refsMap[CborString(name)] = CborBytes(hash);
    });
    final map = CborMap({
      CborString('b'): CborBytes(bondId),
      CborString('l'): CborSmallInt(lamportClock),
      CborString('r'): CborMap(refsMap),
      CborString('t'): CborSmallInt(createdMs),
    });
    return Uint8List.fromList(cbor.encode(map));
  }

  static RefAdvert? tryDecode(Uint8List body) {
    try {
      final decoded = cbor.decode(body);
      if (decoded is! CborMap) return null;
      final b = decoded[CborString('b')];
      final l = decoded[CborString('l')];
      final r = decoded[CborString('r')];
      final t = decoded[CborString('t')];
      if (b is! CborBytes || l is! CborSmallInt || r is! CborMap ||
          t is! CborSmallInt) {
        return null;
      }
      final refs = <String, Uint8List>{};
      r.forEach((key, value) {
        if (key is CborString && value is CborBytes) {
          refs[key.toString()] = Uint8List.fromList(value.bytes);
        }
      });
      return RefAdvert(
        bondId: Uint8List.fromList(b.bytes),
        lamportClock: l.value,
        refs: refs,
        createdMs: t.value,
      );
    } catch (_) {
      return null;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Proposal
// ═════════════════════════════════════════════════════════════════════════

/// A recipient-directed ask to adopt a ref at a specific commit.
/// Closest analogue to a GitHub PR, but peer-to-peer and signed.
class Proposal {
  Proposal({
    required this.bondId,
    required this.proposerPubkey,
    required this.recipientPubkey,
    required this.sourceRef,
    required this.sourceCommit,
    required this.targetRef,
    required this.title,
    required this.body,
    required this.createdMs,
    this.fulfills = const [],
    this.worktreeHint = '',
  });

  final Uint8List bondId;
  final Uint8List proposerPubkey;
  final Uint8List recipientPubkey;

  /// Ref on the proposer's side that carries the proposed commits.
  /// Local to them; useful metadata, not load-bearing.
  final String sourceRef;

  /// Commit the recipient is asked to adopt. The content-addressed
  /// pointer.
  final Uint8List sourceCommit;

  /// Ref the recipient is asked to move (or create) at source_commit.
  /// E.g. `refs/heads/main` for a proposed merge into main.
  final String targetRef;

  final String title;
  final String body;

  /// Epoch ms.
  final int createdMs;

  /// Target ids this proposal consumes when accepted. Each target's
  /// author signature is verified separately before consumption is
  /// honoured.
  final List<Uint8List> fulfills;

  /// Optional path-slug suggestion for the recipient's worktree when
  /// the proposal is auto-materialised for review. Recipient ignores
  /// if empty.
  final String worktreeHint;

  Uint8List toCborBody() {
    final map = <CborString, CborValue>{
      CborString('b'): CborBytes(bondId),
      CborString('p'): CborBytes(proposerPubkey),
      CborString('r'): CborBytes(recipientPubkey),
      CborString('sr'): CborString(sourceRef),
      CborString('sc'): CborBytes(sourceCommit),
      CborString('tr'): CborString(targetRef),
      CborString('ti'): CborString(title),
      CborString('bd'): CborString(body),
      CborString('t'): CborSmallInt(createdMs),
    };
    if (fulfills.isNotEmpty) {
      map[CborString('f')] =
          CborList(fulfills.map((id) => CborBytes(id)).toList());
    }
    if (worktreeHint.isNotEmpty) {
      map[CborString('w')] = CborString(worktreeHint);
    }
    return Uint8List.fromList(cbor.encode(CborMap(map)));
  }

  static Proposal? tryDecode(Uint8List body) {
    try {
      final decoded = cbor.decode(body);
      if (decoded is! CborMap) return null;
      Uint8List? bytesAt(String k) {
        final v = decoded[CborString(k)];
        if (v is CborBytes) return Uint8List.fromList(v.bytes);
        return null;
      }
      String? stringAt(String k) {
        final v = decoded[CborString(k)];
        if (v is CborString) return v.toString();
        return null;
      }
      int? intAt(String k) {
        final v = decoded[CborString(k)];
        if (v is CborSmallInt) return v.value;
        return null;
      }
      List<Uint8List> listAt(String k) {
        final v = decoded[CborString(k)];
        if (v is CborList) {
          return v
              .whereType<CborBytes>()
              .map((b) => Uint8List.fromList(b.bytes))
              .toList();
        }
        return const [];
      }
      final b = bytesAt('b');
      final p = bytesAt('p');
      final r = bytesAt('r');
      final sr = stringAt('sr');
      final sc = bytesAt('sc');
      final tr = stringAt('tr');
      final ti = stringAt('ti');
      final bd = stringAt('bd');
      final t = intAt('t');
      if (b == null || p == null || r == null || sr == null ||
          sc == null || tr == null || ti == null || bd == null ||
          t == null) {
        return null;
      }
      return Proposal(
        bondId: b,
        proposerPubkey: p,
        recipientPubkey: r,
        sourceRef: sr,
        sourceCommit: sc,
        targetRef: tr,
        title: ti,
        body: bd,
        createdMs: t,
        fulfills: listAt('f'),
        worktreeHint: stringAt('w') ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Attestation
// ═════════════════════════════════════════════════════════════════════════

enum AttestationVerdict {
  approve,
  changesRequested,
  comment,
  withdraw,
}

/// A signed review verdict on a specific proposal. Multiple
/// attestations from the same reviewer are allowed (typical flow:
/// `comment` while reviewing, `approve` when done); the latest one
/// by Lamport clock wins for gossip-boundary accounting.
class Attestation {
  Attestation({
    required this.bondId,
    required this.proposalId,
    required this.verdict,
    required this.body,
    required this.createdMs,
    required this.targetCommit,
  });

  final Uint8List bondId;

  /// Hash of the serialised Proposal envelope this attestation
  /// verdicts against. Uniquely identifies the proposal across
  /// amendments (amending = new Proposal = new id).
  final Uint8List proposalId;

  final AttestationVerdict verdict;
  final String body;
  final int createdMs;

  /// Snapshot of the proposal's target_commit at attestation time.
  /// Attestations are pinned to a specific commit so they don't
  /// silently apply to post-review force-pushes.
  final Uint8List targetCommit;

  Uint8List toCborBody() {
    final map = CborMap({
      CborString('b'): CborBytes(bondId),
      CborString('pid'): CborBytes(proposalId),
      CborString('v'): CborSmallInt(verdict.index),
      CborString('bd'): CborString(body),
      CborString('t'): CborSmallInt(createdMs),
      CborString('tc'): CborBytes(targetCommit),
    });
    return Uint8List.fromList(cbor.encode(map));
  }

  static Attestation? tryDecode(Uint8List body) {
    try {
      final decoded = cbor.decode(body);
      if (decoded is! CborMap) return null;
      final b = decoded[CborString('b')];
      final pid = decoded[CborString('pid')];
      final v = decoded[CborString('v')];
      final bd = decoded[CborString('bd')];
      final t = decoded[CborString('t')];
      final tc = decoded[CborString('tc')];
      if (b is! CborBytes || pid is! CborBytes || v is! CborSmallInt ||
          bd is! CborString || t is! CborSmallInt || tc is! CborBytes) {
        return null;
      }
      if (v.value < 0 || v.value >= AttestationVerdict.values.length) {
        return null;
      }
      return Attestation(
        bondId: Uint8List.fromList(b.bytes),
        proposalId: Uint8List.fromList(pid.bytes),
        verdict: AttestationVerdict.values[v.value],
        body: bd.toString(),
        createdMs: t.value,
        targetCommit: Uint8List.fromList(tc.bytes),
      );
    } catch (_) {
      return null;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Anchor
// ═════════════════════════════════════════════════════════════════════════

enum AnchorTargetKind { commit, tree, blob, lineRange }

/// A signed comment tied to a git object. Stored as a git note; also
/// faster-path delivered over the wire for live-session comments.
class Anchor {
  Anchor({
    required this.bondId,
    required this.targetKind,
    required this.targetHash,
    required this.body,
    required this.createdMs,
    this.byteRangeStart,
    this.byteRangeEnd,
  });

  final Uint8List bondId;
  final AnchorTargetKind targetKind;

  /// Content-addressed target. Commit / tree / blob hash, or blob
  /// hash when [targetKind] is [AnchorTargetKind.lineRange] (the
  /// range then picks a byte region of that blob).
  final Uint8List targetHash;

  final String body;
  final int createdMs;

  /// Byte offsets into the blob. Null unless kind == lineRange.
  final int? byteRangeStart;
  final int? byteRangeEnd;

  Uint8List toCborBody() {
    final map = <CborString, CborValue>{
      CborString('b'): CborBytes(bondId),
      CborString('k'): CborSmallInt(targetKind.index),
      CborString('h'): CborBytes(targetHash),
      CborString('bd'): CborString(body),
      CborString('t'): CborSmallInt(createdMs),
    };
    if (byteRangeStart != null) {
      map[CborString('rs')] = CborSmallInt(byteRangeStart!);
    }
    if (byteRangeEnd != null) {
      map[CborString('re')] = CborSmallInt(byteRangeEnd!);
    }
    return Uint8List.fromList(cbor.encode(CborMap(map)));
  }

  static Anchor? tryDecode(Uint8List body) {
    try {
      final decoded = cbor.decode(body);
      if (decoded is! CborMap) return null;
      final b = decoded[CborString('b')];
      final k = decoded[CborString('k')];
      final h = decoded[CborString('h')];
      final bd = decoded[CborString('bd')];
      final t = decoded[CborString('t')];
      if (b is! CborBytes || k is! CborSmallInt || h is! CborBytes ||
          bd is! CborString || t is! CborSmallInt) {
        return null;
      }
      if (k.value < 0 || k.value >= AnchorTargetKind.values.length) {
        return null;
      }
      final rsRaw = decoded[CborString('rs')];
      final reRaw = decoded[CborString('re')];
      int? start;
      int? end;
      if (rsRaw is CborSmallInt) start = rsRaw.value;
      if (reRaw is CborSmallInt) end = reRaw.value;
      final hasStart = start != null;
      final hasEnd = end != null;
      // Both-or-neither: a one-sided range is a malformed anchor.
      // Reject rather than silently leaving one side null.
      if (hasStart != hasEnd) return null;
      final kind = AnchorTargetKind.values[k.value];
      // Range only makes sense for lineRange targets.
      if (hasStart && kind != AnchorTargetKind.lineRange) return null;
      if (hasStart && (start < 0 || end! < start)) return null;
      return Anchor(
        bondId: Uint8List.fromList(b.bytes),
        targetKind: kind,
        targetHash: Uint8List.fromList(h.bytes),
        body: bd.toString(),
        createdMs: t.value,
        byteRangeStart: start,
        byteRangeEnd: end,
      );
    } catch (_) {
      return null;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Target
// ═════════════════════════════════════════════════════════════════════════

/// An unfulfilled intent. A proposal can consume it by including its
/// id in Proposal.fulfills. Bond's replacement for GitHub issues.
class Target {
  Target({
    required this.bondId,
    required this.title,
    required this.body,
    required this.acceptanceCriteria,
    required this.createdMs,
  });

  final Uint8List bondId;
  final String title;
  final String body;

  /// Free-form text describing what "done" looks like. Not machine-
  /// interpretable; the UI surfaces it alongside the body.
  final String acceptanceCriteria;

  final int createdMs;

  Uint8List toCborBody() {
    final map = CborMap({
      CborString('b'): CborBytes(bondId),
      CborString('ti'): CborString(title),
      CborString('bd'): CborString(body),
      CborString('ac'): CborString(acceptanceCriteria),
      CborString('t'): CborSmallInt(createdMs),
    });
    return Uint8List.fromList(cbor.encode(map));
  }

  static Target? tryDecode(Uint8List body) {
    try {
      final decoded = cbor.decode(body);
      if (decoded is! CborMap) return null;
      final b = decoded[CborString('b')];
      final ti = decoded[CborString('ti')];
      final bd = decoded[CborString('bd')];
      final ac = decoded[CborString('ac')];
      final t = decoded[CborString('t')];
      if (b is! CborBytes || ti is! CborString || bd is! CborString ||
          ac is! CborString || t is! CborSmallInt) {
        return null;
      }
      return Target(
        bondId: Uint8List.fromList(b.bytes),
        title: ti.toString(),
        body: bd.toString(),
        acceptanceCriteria: ac.toString(),
        createdMs: t.value,
      );
    } catch (_) {
      return null;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Policy
// ═════════════════════════════════════════════════════════════════════════

/// A single rule within a Policy. Each rule applies to refs matching
/// [refPattern] (git-style glob), requires [minApprovals] approvals
/// from members of [approverSet], and is enforced at each peer's
/// gossip boundary when adopting incoming ref advertisements.
class PolicyRule {
  PolicyRule({
    required this.refPattern,
    required this.minApprovals,
    this.approverSet = const [],
  });

  final String refPattern;
  final int minApprovals;
  final List<Uint8List> approverSet;

  CborMap toCbor() {
    return CborMap({
      CborString('p'): CborString(refPattern),
      CborString('m'): CborSmallInt(minApprovals),
      if (approverSet.isNotEmpty)
        CborString('a'):
            CborList(approverSet.map((k) => CborBytes(k)).toList()),
    });
  }

  static PolicyRule? tryDecode(CborMap m) {
    final p = m[CborString('p')];
    final min = m[CborString('m')];
    if (p is! CborString || min is! CborSmallInt) return null;
    final a = m[CborString('a')];
    final approvers = <Uint8List>[];
    if (a is CborList) {
      for (final item in a) {
        if (item is CborBytes) {
          approvers.add(Uint8List.fromList(item.bytes));
        }
      }
    }
    return PolicyRule(
      refPattern: p.toString(),
      minApprovals: min.value,
      approverSet: approvers,
    );
  }
}

/// Bond consensus policy. Signed, gossiped, enforced at the ref-adopt
/// boundary on every peer. Superseding a policy requires the new
/// policy to be signed by members meeting the current policy's
/// approver requirements (bootstrap: first policy is signed by the
/// bond initialiser and accepted on first-join trust).
class Policy {
  Policy({
    required this.bondId,
    required this.effectiveAtMs,
    required this.rules,
    this.supersedes,
  });

  final Uint8List bondId;

  /// When this policy takes effect, epoch ms. Peers receiving a
  /// policy with [effectiveAtMs] in the future hold it as pending
  /// and switch at the scheduled time.
  final int effectiveAtMs;

  final List<PolicyRule> rules;

  /// Policy id (hash of the serialised envelope) this policy replaces.
  /// Null when this is the bond's first policy.
  final Uint8List? supersedes;

  Uint8List toCborBody() {
    final map = <CborString, CborValue>{
      CborString('b'): CborBytes(bondId),
      CborString('e'): CborSmallInt(effectiveAtMs),
      CborString('r'): CborList(rules.map((r) => r.toCbor()).toList()),
    };
    if (supersedes != null) {
      map[CborString('s')] = CborBytes(supersedes!);
    }
    return Uint8List.fromList(cbor.encode(CborMap(map)));
  }

  static Policy? tryDecode(Uint8List body) {
    try {
      final decoded = cbor.decode(body);
      if (decoded is! CborMap) return null;
      final b = decoded[CborString('b')];
      final e = decoded[CborString('e')];
      final r = decoded[CborString('r')];
      if (b is! CborBytes || e is! CborSmallInt || r is! CborList) {
        return null;
      }
      // Strict rule decoding: any malformed rule fails the whole
      // policy. Silent-skip would let a crafted sender weaken the
      // effective rule set by embedding an unparseable rule — peers
      // would then operate under a looser policy than the signer
      // ever authorised. Better to drop the policy entirely and
      // surface the decode failure.
      final rules = <PolicyRule>[];
      for (final item in r) {
        if (item is! CborMap) return null;
        final rule = PolicyRule.tryDecode(item);
        if (rule == null) return null;
        rules.add(rule);
      }
      final s = decoded[CborString('s')];
      return Policy(
        bondId: Uint8List.fromList(b.bytes),
        effectiveAtMs: e.value,
        rules: rules,
        supersedes: s is CborBytes ? Uint8List.fromList(s.bytes) : null,
      );
    } catch (_) {
      return null;
    }
  }
}
