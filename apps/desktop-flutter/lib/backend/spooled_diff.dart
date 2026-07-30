// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// spooled_diff.dart — a diff that lives on disk, as a value.
//
// This is `dart:io` and nothing else, ON PURPOSE. It used to live in
// git.dart, and because `diff_document.dart` needs exactly this one type
// (`import '../../backend/git.dart' show SpooledDiff;`) the entire
// machine-scale diff-load path inherited git.dart's transitive graph:
// repository_xray -> diagnostics_state -> package:flutter/foundation.
// A pure data holder was dragging the Flutter runtime behind it.
//
// The cost was not theoretical. Headless tools cannot run against a
// Flutter-importing graph at all — `dart run` tries to compile
// flutter/src/gestures/velocity_tracker.dart, which needs dart:ui, and
// dies. tool/diff_load_profiler.dart (the growth-law guard behind the
// marble OOM) was broken by exactly that, and tool/axis_audit.dart
// carries a comment saying it "deliberately avoids git.dart" for the
// same reason. Keep this file Flutter-free and those tools keep working.

import 'dart:io';

/// A combined diff streamed straight to a temp spool file — its bytes
/// never all resided in RAM. Feed [path] to
/// `DiffDocument.lazyFromSpool` for a disk-backed document whose
/// resident memory is independent of diff size.
///
/// Owns the temp DIRECTORY, not just the file: the owner MUST call
/// [dispose] when done, which removes the whole thing, so there is
/// exactly one owner and one deletion. Hand [dir] to
/// `DiffDocument.lazyFromSpool`'s `ownedTempDir` to transfer that
/// ownership to the document instead.
class SpooledDiff {
  final String path;
  final String _dir;
  final int byteLength;
  const SpooledDiff(this.path, this._dir, this.byteLength);

  /// The owning temp directory — hand to `DiffDocument.lazyFromSpool`'s
  /// `ownedTempDir` so the document deletes it on dispose (single owner).
  String get dir => _dir;

  Future<void> dispose() async {
    try {
      await Directory(_dir).delete(recursive: true);
    } catch (_) {}
  }
}
