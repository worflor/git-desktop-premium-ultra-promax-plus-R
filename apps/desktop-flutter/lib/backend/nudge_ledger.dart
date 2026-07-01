// nudge_ledger.dart — closing the coupling-nudge loop through the user.
//
// The coupling-nudge surface ("you probably meant to stage X too") is the
// engine's PREDICTION. Whether the user accepts it is ground truth the
// engine can't otherwise observe. This ledger records both sides — the
// nudge shown, and the user's accept — durably and per-repo, so a future
// session can jury the engine against realized behaviour instead of its
// own confidence.
//
// Append-only JSONL under the app data dir. Per-repo keying mirrors
// ReviewRatchetStore (stable FNV-1a of the repo path); the single-writer
// append chain mirrors CommandTelemetryStore. One line per event:
// {ts, kind, path, anchor, score, receipts}. Writes are fire-and-forget
// and best-effort — a nudge is a bonus signal, never load-bearing, so IO
// errors are swallowed and the UI is never blocked.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart' show visibleForTesting;

import 'storage_paths.dart' show StoragePaths;

/// A single recorded nudge event. [kind] is `shown` (the engine surfaced
/// the nudge) or `accepted` (the user staged the nudged file).
class NudgeEvent {
  /// UTC ISO-8601 timestamp of the event.
  final String ts;

  /// `shown` | `accepted`.
  final String kind;

  /// The unselected file the nudge was about.
  final String path;

  /// The selected peer that anchored the coupling.
  final String anchor;

  /// The engine's coupling score for the pair at the moment of the event.
  final double score;

  /// Whether the nudge carried charge receipts (shared-token evidence).
  final bool receipts;

  const NudgeEvent({
    required this.ts,
    required this.kind,
    required this.path,
    required this.anchor,
    required this.score,
    required this.receipts,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'kind': kind,
        'path': path,
        'anchor': anchor,
        'score': score,
        'receipts': receipts,
      };

  /// Parse one JSONL entry. Returns null for a malformed / partial line so
  /// [NudgeLedger.readAll] can skip it rather than throwing.
  static NudgeEvent? tryFromJson(Map<String, dynamic> json) {
    final ts = json['ts'];
    final kind = json['kind'];
    final path = json['path'];
    final anchor = json['anchor'];
    final score = json['score'];
    final receipts = json['receipts'];
    if (ts is! String ||
        kind is! String ||
        path is! String ||
        anchor is! String ||
        score is! num ||
        receipts is! bool) {
      return null;
    }
    return NudgeEvent(
      ts: ts,
      kind: kind,
      path: path,
      anchor: anchor,
      score: score.toDouble(),
      receipts: receipts,
    );
  }
}

/// Per-repo append-only outcome ledger for coupling nudges.
///
/// Construct one per repo (the changes page holds it for the active repo).
/// `shown` events are debounced per (path, anchor) for the ledger's
/// lifetime via an in-memory seen-set, so scroll-driven chip rebuilds don't
/// spam the file; `accepted` events are never debounced — every accept is
/// ground truth.
class NudgeLedger {
  NudgeLedger(this.repoPath, {@visibleForTesting Directory? storageDirOverride})
      : _storageDirOverride = storageDirOverride;

  final String repoPath;
  final Directory? _storageDirOverride;

  /// Debounce set for `shown` events — one per (path, anchor) per ledger
  /// lifetime. In-memory only: a fresh session re-emits `shown`, which is
  /// intentional (each session is a distinct exposure of the prediction).
  final Set<String> _shownThisSession = <String>{};

  /// Serialises appends so concurrent fire-and-forget writes can't
  /// interleave a torn line. Static: one chain across every ledger.
  static Future<void> _writeLock = Future<void>.value();

  /// Record that a nudge chip was surfaced. Debounced per (path, anchor)
  /// for this ledger's lifetime; fire-and-forget, never blocks the caller.
  void recordShown({
    required String path,
    required String anchor,
    required double score,
    required bool receipts,
  }) {
    final key = '$path\u001f$anchor';
    if (!_shownThisSession.add(key)) return;
    _append('shown',
        path: path, anchor: anchor, score: score, receipts: receipts);
  }

  /// Record that the user accepted a nudge (staged the file). Fire-and-
  /// forget, never blocks the caller.
  void recordAccepted({
    required String path,
    required String anchor,
    required double score,
    required bool receipts,
  }) {
    _append('accepted',
        path: path, anchor: anchor, score: score, receipts: receipts);
  }

  void _append(
    String kind, {
    required String path,
    required String anchor,
    required double score,
    required bool receipts,
  }) {
    final line = jsonEncode(NudgeEvent(
      ts: DateTime.now().toUtc().toIso8601String(),
      kind: kind,
      path: path,
      anchor: anchor,
      score: score,
      receipts: receipts,
    ).toJson());
    _writeLock = _writeLock.then((_) async {
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        await file.writeAsString('$line\n',
            mode: FileMode.append, flush: true);
      } catch (_) {
        // best-effort; a nudge is never load-bearing
      }
    });
  }

  /// Every event recorded for this repo, in insertion order. Malformed or
  /// partial lines are skipped; a missing / unreadable file yields an empty
  /// list. For future analysis — jurying the engine against realized
  /// behaviour.
  Future<List<NudgeEvent>> readAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const <NudgeEvent>[];
      final events = <NudgeEvent>[];
      for (final line in await file.readAsLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is Map<String, dynamic>) {
            final event = NudgeEvent.tryFromJson(parsed);
            if (event != null) events.add(event);
          }
        } catch (_) {}
      }
      return events;
    } catch (_) {
      return const <NudgeEvent>[];
    }
  }

  Future<File> _file() async {
    final dir = _storageDirOverride ??
        Directory(
            '${(await StoragePaths.gdpuDataDir()).path}${Platform.pathSeparator}nudge_ledger');
    return File('${dir.path}${Platform.pathSeparator}${_key(repoPath)}.jsonl');
  }

  /// FNV-1a (32-bit) of the repo path — a stable, filesystem-safe key so
  /// two repos never collide and the filename survives restarts (unlike
  /// String.hashCode, which isn't guaranteed stable). Mirrors
  /// ReviewRatchetStore._key.
  static String _key(String repoPath) {
    var hash = 0x811c9dc5;
    for (final c in repoPath.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
