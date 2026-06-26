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
    final marker = _spliceConflictMarkers(ours, entry.value);
    if (marker == null) return null; // misalignment → caller falls back
    final cf = parseConflictFile(path, marker);
    if (cf.blocks.isEmpty) continue; // nothing actually changed
    for (final b in cf.blocks) {
      b.resolution = ConflictSide.theirs;
    }
    out.add(cf);
  }
  if (out.isEmpty) return null;
  return out;
}

/// Splices `<<<<<<< ours / ======= / >>>>>>> theirs` markers into
/// [oursText] at the positions the [diffLines] (a single file's parsed
/// context/added/deleted lines, in order) describe. Returns standard
/// conflict-file text that [parseConflictFile] round-trips exactly, or null
/// if a context/deleted line doesn't match the current content at its line
/// number (the patch doesn't align here).
String? _spliceConflictMarkers(String oursText, List<ParsedLine> diffLines) {
  // split('\n') round-trips join('\n') exactly, including the trailing ''
  // element a file-final newline produces.
  final ours = oursText.isEmpty ? <String>[] : oursText.split('\n');
  final out = <String>[];
  var idx = 0; // next unread line in `ours`
  final oursRun = <String>[];
  final theirsRun = <String>[];

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
  flush();
  while (idx < ours.length) {
    out.add(ours[idx]);
    idx++;
  }
  return out.join('\n');
}
