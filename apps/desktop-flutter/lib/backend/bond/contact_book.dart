// ═════════════════════════════════════════════════════════════════════════
// bond/contact_book.dart — local address book, Signal-style
//
// The Bond protocol is name-blind: wire carries pubkeys, never human
// strings. Display names are a purely local concern — each peer's
// Manifold keeps its own contacts.jsonl mapping pubkeys to labels.
//
// No name is ever transmitted, reconciled, or negotiated between
// peers. "worflor" on Alice's machine can be the same pubkey as
// "wolf" on Bob's. Both are correct; they're just Alice and Bob's
// respective local views of the same cryptographic identity.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:typed_data';

import 'bond_id.dart';
import 'storage.dart';

/// One entry in a local contact book. Exists only on the machine that
/// wrote it; never transmitted.
class BondContact {
  BondContact({
    required this.pubkeyHex,
    this.label = '',
    this.notes = '',
    this.firstSeenMs,
    this.userVerified = false,
  });

  /// Hex-encoded Ed25519 public key. Lowercase, no prefix, 64 chars.
  final String pubkeyHex;

  /// Display name the local user chose. Empty string = unlabelled;
  /// UI falls back to fingerprint + identicon in that case.
  final String label;

  /// Free-form local notes (e.g. "laptop", "work email:…"). Purely
  /// UX; never transmitted.
  final String notes;

  /// First time this pubkey was observed in this bond, epoch ms.
  final int? firstSeenMs;

  /// True when the local user explicitly confirmed the label out-of-
  /// band (phone, Signal, video). Surfaces in the UI as a subtle
  /// trust marker; unverified labels render with a softer tone.
  final bool userVerified;

  Map<String, dynamic> toJson() => {
        'p': pubkeyHex,
        if (label.isNotEmpty) 'l': label,
        if (notes.isNotEmpty) 'n': notes,
        if (firstSeenMs != null) 'fs': firstSeenMs,
        if (userVerified) 'v': true,
      };

  static BondContact fromJson(Map<String, dynamic> json) => BondContact(
        pubkeyHex: (json['p'] as String? ?? '').toLowerCase(),
        label: json['l'] as String? ?? '',
        notes: json['n'] as String? ?? '',
        firstSeenMs: json['fs'] as int?,
        userVerified: json['v'] as bool? ?? false,
      );
}

/// In-memory + on-disk view of one bond's contact book. Load once
/// on bond open; mutate via methods; persist through the same
/// instance (JSONL append-only, so writes are cheap).
class ContactBook {
  ContactBook._(this._store, this._bondId, this._byPubkey);

  final BondStore _store;
  final BondId _bondId;
  final Map<String, BondContact> _byPubkey;

  /// Read the contact book for [bondId] off disk. Creates an empty
  /// book if the file doesn't exist.
  static Future<ContactBook> open(BondStore store, BondId bondId) async {
    final path = store.contactsPathFor(bondId);
    final rows = await readJsonl(path);
    final map = <String, BondContact>{};
    // Last-wins semantics: later entries for the same pubkey
    // override earlier ones. Lets us amend a contact by appending a
    // new line instead of rewriting the file.
    for (final row in rows) {
      final c = BondContact.fromJson(row);
      if (c.pubkeyHex.isEmpty) continue;
      map[c.pubkeyHex] = c;
    }
    return ContactBook._(store, bondId, map);
  }

  /// Returns the label assigned locally to [pubkeyHex], or null if
  /// the pubkey is unknown or explicitly unlabelled.
  String? labelFor(String pubkeyHex) {
    final c = _byPubkey[pubkeyHex.toLowerCase()];
    if (c == null || c.label.isEmpty) return null;
    return c.label;
  }

  /// Full contact record for [pubkeyHex], or null when unknown.
  BondContact? contactFor(String pubkeyHex) =>
      _byPubkey[pubkeyHex.toLowerCase()];

  /// All contacts, sorted by label (empty labels last). Suitable for
  /// rendering directly in a peer list view.
  List<BondContact> all() {
    final list = _byPubkey.values.toList();
    list.sort((a, b) {
      if (a.label.isEmpty && b.label.isEmpty) {
        return a.pubkeyHex.compareTo(b.pubkeyHex);
      }
      if (a.label.isEmpty) return 1;
      if (b.label.isEmpty) return -1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return list;
  }

  /// Record the first sighting of a pubkey. Idempotent; later calls
  /// for a pubkey already present are no-ops (use [setLabel] to
  /// update metadata).
  Future<void> recordFirstSeen(String pubkeyHex) async {
    final key = pubkeyHex.toLowerCase();
    if (_byPubkey.containsKey(key)) return;
    final contact = BondContact(
      pubkeyHex: key,
      firstSeenMs: DateTime.now().millisecondsSinceEpoch,
    );
    _byPubkey[key] = contact;
    await appendJsonl(
        _store.contactsPathFor(_bondId), contact.toJson());
  }

  /// Set or update the label for a pubkey. Appends a new JSONL
  /// record; on next load the last-writer-wins rule applies.
  Future<void> setLabel(
    String pubkeyHex, {
    String? label,
    String? notes,
    bool? userVerified,
  }) async {
    final key = pubkeyHex.toLowerCase();
    final existing = _byPubkey[key];
    final updated = BondContact(
      pubkeyHex: key,
      label: label ?? existing?.label ?? '',
      notes: notes ?? existing?.notes ?? '',
      firstSeenMs: existing?.firstSeenMs ??
          DateTime.now().millisecondsSinceEpoch,
      userVerified: userVerified ?? existing?.userVerified ?? false,
    );
    _byPubkey[key] = updated;
    await appendJsonl(
        _store.contactsPathFor(_bondId), updated.toJson());
  }
}

/// Fingerprint display: 8 hex chars with a separator, for UI strings
/// that render unlabelled peers. The full 64-char pubkey is too long
/// for inline rendering; the short form is the same order of
/// specificity git uses for short commit hashes.
String formatPubkeyFingerprint(Uint8List pubkey) {
  final hex = pubkey
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  // `ed25519:abc…def` — prefix makes the type explicit so future
  // algorithms don't collide in the UI.
  return 'ed25519:${hex.substring(0, 8)}…${hex.substring(hex.length - 4)}';
}

/// For tests / diagnostics: assert the contacts.jsonl file exists
/// and is readable.
Future<bool> contactsFileExists(BondStore store, BondId bondId) =>
    File(store.contactsPathFor(bondId)).exists();
