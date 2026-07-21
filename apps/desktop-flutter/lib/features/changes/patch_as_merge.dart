// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import '../diff/diff_models.dart';
import 'merge_conflict_editor.dart';

/// Presents a unified [patch] as a reviewable merge so the built-in
/// [MergeEditorPage] can open on ANY patch — not just ones git reports as
/// conflicting. Each changed run becomes an ours/theirs [ConflictBlock]
/// (ours = the current content in [oursByPath], theirs = the patched
/// content). Blocks default to [ConflictSide.theirs] (accept the incoming
/// change); the user flips any hunk to `ours` to drop it. Accept-all
/// reproduces the patched file; reject-all reproduces the current file.
///
/// This is non-mutating: it reads nothing from git and writes nothing. It
/// only works when the patch's pre-image (its context + deleted lines)
/// matches the supplied current content — i.e. the patch would apply
/// cleanly. If ANY file fails to align, returns null so the caller can fall
/// back to a real `git apply --3way`. New files (no current content, pure
/// additions) are presented as a single block with an empty `ours` side.
List<ConflictFile>? reviewMergeFromPatch(
  String patch,
  Map<String, String> oursByPath,
) {
  final lines = parseUnifiedDiff(patch);
  final byFile = <String, List<ParsedLine>>{};
  for (final l in lines) {
    final f = l.filePath;
    if (f == null) continue;
    if (l.kind != LineKind.context &&
        l.kind != LineKind.added &&
        l.kind != LineKind.deleted) {
      continue;
    }
    // Trailing split artifacts: empty context lines carry no real position.
    if (l.kind == LineKind.context && l.lineNumOld == null) continue;
    (byFile[f] ??= <ParsedLine>[]).add(l);
  }
  if (byFile.isEmpty) return null;

  final out = <ConflictFile>[];
  for (final entry in byFile.entries) {
    final path = entry.key;
    // A new file the patch creates has no current content — treat as empty.
    final ours = oursByPath[path] ?? '';
    final spliced = _spliceConflictMarkers(ours, entry.value);
    if (spliced == null) return null; // misalignment → caller falls back
    final cf = parseConflictFile(path, spliced.text);
    if (cf.blocks.isEmpty) continue; // nothing actually changed
    for (final b in cf.blocks) {
      b.resolution = ConflictSide.theirs;
    }
    // The marker-splice document is invariant to trailing-newline status
    // (parseConflictFile/buildResult can't distinguish "block is the
    // file's genuine final content, no trailing newline" from "block
    // happens to sit at the end of THIS document" purely from the text —
    // both shapes produce identical bytes). Thread the real flag through
    // explicitly onto whichever block ends up last, so buildResult() can
    // suppress the newline it otherwise unconditionally re-adds to rejoin
    // a block with its (empty) trailing segment.
    if (cf.blocks.isNotEmpty) {
      final last = cf.blocks.last;
      last.oursNoTrailingNewline = spliced.oursNoTrailingNewline;
      last.theirsNoTrailingNewline = spliced.theirsNoTrailingNewline;
    }
    out.add(cf);
  }
  if (out.isEmpty) return null;
  return out;
}

/// Result of [_spliceConflictMarkers]: the marker-embedded document plus
/// whether the file's genuine final content (ours-side / theirs-side,
/// independently — either can lack a trailing newline while the other has
/// one) has no trailing newline. Both flags are only ever meaningful when
/// the differing region reaches the file's true end-of-content (no
/// unchanged tail lines follow it) — see [_spliceConflictMarkers]'s
/// `idx >= ours.length` check.
typedef _SplicedConflict = ({
  String text,
  bool oursNoTrailingNewline,
  bool theirsNoTrailingNewline,
});

/// Splices `<<<<<<< ours / ======= / >>>>>>> theirs` markers into
/// [oursText] at the positions the [diffLines] (a single file's parsed
/// context/added/deleted lines, in order) describe. Returns standard
/// conflict-file text that [parseConflictFile] round-trips exactly, or null
/// if a context/deleted line doesn't match the current content at its line
/// number (the patch doesn't align here).
_SplicedConflict? _spliceConflictMarkers(
    String oursText, List<ParsedLine> diffLines) {
  // split('\n') round-trips join('\n') exactly, including the trailing ''
  // element a file-final newline produces.
  final ours = oursText.isEmpty ? <String>[] : oursText.split('\n');
  final out = <String>[];
  var idx = 0; // next unread line in `ours`
  final oursRun = <String>[];
  final theirsRun = <String>[];
  // Tracks noNewlineAtEof from the most recently seen line touching each
  // side. Only the LAST update of each survives to the end of the loop —
  // exactly the line git considers that side's true final line, if any.
  var theirsNoNewlineAtEof = false;

  void flush() {
    if (oursRun.isEmpty && theirsRun.isEmpty) return;
    out.add('<<<<<<< ours');
    out.addAll(oursRun);
    out.add('=======');
    out.addAll(theirsRun);
    out.add('>>>>>>> theirs');
    oursRun.clear();
    theirsRun.clear();
  }

  for (final pl in diffLines) {
    if (pl.kind == LineKind.added) {
      theirsRun.add(pl.text.isEmpty ? '' : pl.text.substring(1));
      theirsNoNewlineAtEof = pl.noNewlineAtEof;
      continue;
    }
    // context or deleted — both occupy a position in `ours`.
    final ln = pl.lineNumOld;
    if (ln == null) return null;
    final target = ln - 1;
    final expected = pl.text.isEmpty ? '' : pl.text.substring(1);
    if (pl.kind == LineKind.context) {
      flush();
      while (idx < target && idx < ours.length) {
        out.add(ours[idx]);
        idx++;
      }
      if (idx != target || idx >= ours.length || ours[idx] != expected) {
        return null;
      }
      out.add(ours[idx]);
      idx++;
      theirsNoNewlineAtEof = pl.noNewlineAtEof;
    } else {
      // deleted
      while (idx < target && idx < ours.length) {
        out.add(ours[idx]);
        idx++;
      }
      if (idx != target || idx >= ours.length || ours[idx] != expected) {
        return null;
      }
      oursRun.add(ours[idx]);
      idx++;
    }
  }
  // `ours` carries a trailing '' sentinel element whenever oursText itself
  // ends with '\n' (split('\n') convention) — that sentinel isn't a real
  // unconsumed line, just the split-artifact representing the file's own
  // trailing newline. Excluding it from the "is there real trailing
  // content" check is required: otherwise a full-file replacement whose
  // OLD content happened to end with a newline always looks like it has a
  // trailing tail (idx never "reaches" the sentinel, since no diff line
  // corresponds to it), permanently defeating the no-newline handling below.
  final oursEndsWithNewline = oursText.isNotEmpty && oursText.endsWith('\n');
  final effectiveOursLength =
      oursEndsWithNewline ? ours.length - 1 : ours.length;
  final hasTrailingTail = idx < effectiveOursLength;
  if (!hasTrailingTail && oursEndsWithNewline && oursRun.isNotEmpty) {
    // The diffed region reaches ours's true end, and `oursText` itself
    // ends with a newline — a fact git's diff never represents as an
    // explicit "-" line (only real content lines are shown; a file's own
    // trailing newline is implicit). We already have the FULL original
    // `oursText` in hand, so encode it directly here: one more (empty)
    // element makes the eventual `oursLines.join('\n')` in
    // parseConflictFile reconstruct that trailing newline exactly,
    // instead of depending on ConflictFile.buildResult's generic
    // "add a newline unless one is already there" default (which can't
    // tell "add one" from "one is already present" on its own). Guarded
    // on oursRun.isNotEmpty: a pure-addition hunk (nothing deleted) has no
    // "ours" replacement content here at all — appending would fabricate
    // a phantom blank line reject-all never had.
    oursRun.add('');
  }
  // The mirror of the ours sentinel, for the theirs side. `theirsRun` holds
  // the added lines verbatim; `theirsRun.join('\n')` therefore represents
  // "N-1 terminated lines plus an unterminated last one". That is correct
  // UNLESS theirs genuinely ends on a *terminated empty line* — an added
  // line whose content is '' with no `\ No newline` marker after it. Then
  // the join collapses that final empty terminated line into a bare trailing
  // '\n' that buildResult reads as "already terminated, nothing to add", and
  // the file loses its true final newline (accept-all drops a byte). One
  // more empty element encodes that terminator explicitly, exactly as the
  // ours branch above does. Guarded identically: only at true EOF, only when
  // theirs actually has a trailing newline, and only when its last line is
  // the empty one that makes the representation ambiguous.
  if (!hasTrailingTail &&
      !theirsNoNewlineAtEof &&
      theirsRun.isNotEmpty &&
      theirsRun.last.isEmpty) {
    theirsRun.add('');
  }
  flush();
  while (idx < ours.length) {
    out.add(ours[idx]);
    idx++;
  }
  // theirsNoNewlineAtEof is only trustworthy when nothing unchanged trails
  // the diffed region — otherwise the tail (plain `ours` content,
  // reproduced verbatim above) is the file's real final content and
  // theirs doesn't actually end where the diff's last touched line does.
  // oursNoTrailingNewline needs no such flag at all: since we hold the
  // full original `oursText`, "does the block's own text end with a
  // newline" is decidable directly from it (and is exactly what the
  // sentinel-append above already encodes when true).
  return (
    text: out.join('\n'),
    oursNoTrailingNewline: !hasTrailingTail && !oursEndsWithNewline,
    theirsNoTrailingNewline: !hasTrailingTail && theirsNoNewlineAtEof,
  );
}
