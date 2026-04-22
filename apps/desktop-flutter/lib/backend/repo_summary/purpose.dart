// purpose.dart — one-line purpose extraction from a file's head.
//
// Engram's file-index caps per-file reads at 16 KB because "the top
// carries the import list and public surface" — the semantically
// densest part of any source file. We exploit that: the first small
// prefix of a file contains either a leading doc comment block or a
// top-level declaration (class / function / const) whose name reads
// as a purpose. Pull that and flatten to one sentence.
//
// No language detection, no per-language parsers. We walk lines
// looking for:
//   1. The first contiguous run of `///` or `//!` or `/**...*/` doc
//      comments, stripped to a single line.
//   2. Failing that, the first `class X` / `interface X` / `fn X` /
//      `def X` / `const X` / `function X` declaration; take the name
//      as the purpose.
// Lines are truncated; nothing is parsed semantically.

import 'types.dart';

final RegExp _dartDocLine = RegExp(r'^\s*///\s?(.*)$');
final RegExp _slashSlashLine = RegExp(r'^\s*//\s?(.*)$');
final RegExp _hashLine = RegExp(r'^\s*#\s?(.*)$');
final RegExp _blockStart = RegExp(r'^\s*/\*{1,2}\s?(.*)$');
final RegExp _blockEnd = RegExp(r'^(.*?)\*/\s*$');

/// Capture the name of a top-level declaration that introduces a
/// SEMANTIC unit — a class, function, enum, module, and so on.
/// `const`, `final`, `var`, `let` are deliberately excluded because
/// a line like `final String _name = …` would otherwise capture the
/// TYPE (`String`) as the "declaration name," which is nonsense.
final RegExp _declName = RegExp(
  r'^\s*(?:pub\s+|public\s+|export\s+|export default\s+|abstract\s+)*'
  r'(?:class|interface|struct|enum|trait|typedef|mixin|extension|'
  r'function|func|fn|def|module|namespace)\s+'
  r'([A-Za-z_][A-Za-z0-9_]*)',
  caseSensitive: false,
);

/// Extract a short one-line purpose string from the head of [file].
/// Returns empty when nothing useful was found in the first few KB.
String extractPurpose(HarvestedFile file, {int maxChars = 120}) {
  final head = file.text.length > 4096 ? file.text.substring(0, 4096) : file.text;
  // Normalise line endings: CRLF files leave a trailing `\r` on every
  // line after `split('\n')`, which interacts badly with several of
  // the regexes below (e.g. `^\s*//\s?$` sometimes matches lines that
  // aren't really empty comment bodies). Stripping `\r` up front keeps
  // the rest of the extractor blissfully line-ending-agnostic.
  final lines = head.replaceAll('\r', '').split('\n');

  // Phase 1: leading doc-comment block (Dart, Rust, JS/TS, Python, etc.)
  final doc = _leadingDocComment(lines);
  if (doc.isNotEmpty) {
    return _truncateSentence(doc, maxChars);
  }

  // Phase 2: first top-level declaration name.
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('//')) continue;
    if (trimmed.startsWith('#')) continue;
    if (trimmed.startsWith('import')) continue;
    if (trimmed.startsWith('use ')) continue;
    if (trimmed.startsWith('package ')) continue;
    if (trimmed.startsWith('from ')) continue;
    final match = _declName.firstMatch(trimmed);
    if (match != null) {
      final name = match.group(1);
      if (name != null && name.length >= 2) {
        return _truncateSentence(name, maxChars);
      }
    }
  }

  return '';
}

/// Scan [lines] for the first contiguous run of doc-comment lines,
/// skipping over boilerplate that typically precedes it (shebangs,
/// blank lines, package / import / use / export statements). The
/// first real comment block — whether at the top of the file or just
/// above the primary declaration — is what describes the file.
///
/// Supports:
///   * `/// ...` (Dart, Rust outer doc)
///   * `/* ... */` (block comments, single- or multi-line)
///   * `// ...`  (plain C-style)
///   * `# ...`   (Python, Ruby, shell)
String _leadingDocComment(List<String> lines) {
  var idx = 0;
  while (idx < lines.length) {
    final raw = lines[idx];
    final trimmed = raw.trim();

    // Boilerplate we walk past silently.
    if (trimmed.isEmpty) { idx++; continue; }
    if (trimmed.startsWith('#!')) { idx++; continue; }
    if (_isImportLike(trimmed)) { idx++; continue; }
    if (trimmed.startsWith('@')) { idx++; continue; } // decorators/annotations

    // If we hit a comment marker, collect the run.
    if (_dartDocLine.hasMatch(raw)) {
      final collected = <String>[];
      while (idx < lines.length) {
        final m = _dartDocLine.firstMatch(lines[idx]);
        if (m == null) break;
        final text = m.group(1)?.trim() ?? '';
        if (text.isNotEmpty) collected.add(text);
        idx++;
      }
      if (collected.isNotEmpty) return _joinComment(collected);
      // Doc run had only empty bodies — keep scanning.
      continue;
    }

    if (_blockStart.hasMatch(raw)) {
      final collected = <String>[];
      final startMatch = _blockStart.firstMatch(raw)!;
      final startText = startMatch.group(1)?.trim() ?? '';
      if (_blockEnd.hasMatch(raw)) {
        // Single-line block comment /* foo */
        final endM = _blockEnd.firstMatch(raw)!;
        final body = endM.group(1)
            ?.replaceFirst(RegExp(r'^\s*/\*+\s?'), '')
            .trim();
        if (body != null && body.isNotEmpty) collected.add(body);
        idx++;
      } else {
        if (startText.isNotEmpty) collected.add(_stripLeadingStar(startText));
        idx++;
        while (idx < lines.length) {
          final ln = lines[idx];
          if (_blockEnd.hasMatch(ln)) {
            final m = _blockEnd.firstMatch(ln)!;
            final tail = _stripLeadingStar(m.group(1)?.trim() ?? '');
            if (tail.isNotEmpty) collected.add(tail);
            idx++;
            break;
          }
          final cleaned = _stripLeadingStar(ln.trim());
          if (cleaned.isNotEmpty) collected.add(cleaned);
          idx++;
        }
      }
      if (collected.isNotEmpty) return _joinComment(collected);
      continue;
    }

    if (_slashSlashLine.hasMatch(raw)) {
      final collected = <String>[];
      while (idx < lines.length) {
        final m = _slashSlashLine.firstMatch(lines[idx]);
        if (m == null) break;
        final text = m.group(1)?.trim() ?? '';
        if (text.isNotEmpty) collected.add(text);
        idx++;
      }
      if (collected.isNotEmpty) return _joinComment(collected);
      continue;
    }

    if (_hashLine.hasMatch(raw)) {
      final collected = <String>[];
      while (idx < lines.length) {
        final m = _hashLine.firstMatch(lines[idx]);
        if (m == null) break;
        final text = m.group(1)?.trim() ?? '';
        if (text.isNotEmpty) collected.add(text);
        idx++;
      }
      if (collected.isNotEmpty) return _joinComment(collected);
      continue;
    }

    // Hit a declaration or code — give up.
    return '';
  }
  return '';
}

/// Is [trimmed] a language-boilerplate line (import, package, use, etc)?
/// These are skipped so the extractor can reach the actual doc comment
/// that sits above the first real declaration.
bool _isImportLike(String trimmed) {
  if (trimmed.startsWith('import ')) return true;
  if (trimmed.startsWith('import\t')) return true;
  if (trimmed.startsWith('import ')) return true;
  if (trimmed.startsWith('from ')) return true;
  if (trimmed.startsWith('use ')) return true;
  if (trimmed.startsWith('package ')) return true;
  if (trimmed.startsWith('export ')) return true;
  if (trimmed.startsWith('require ')) return true;
  if (trimmed.startsWith("require(")) return true;
  if (trimmed.startsWith('library ')) return true;
  if (trimmed.startsWith('part ')) return true;
  if (trimmed.startsWith('namespace ')) return true;
  if (trimmed.startsWith('using ')) return true;
  // Strict mode pragmas, file-level markers
  if (trimmed == "'use strict';" || trimmed == '"use strict";') return true;
  return false;
}

String _stripLeadingStar(String s) {
  var out = s;
  while (out.startsWith('*')) {
    out = out.substring(1).trimLeft();
  }
  return out;
}

/// Join a comment run into a single sentence. Drops filename headers
/// ("file.dart — ...") and copyright boilerplate.
String _joinComment(List<String> lines) {
  final cleaned = <String>[];
  for (final raw in lines) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    cleaned.add(l);
  }
  if (cleaned.isEmpty) return '';
  // First line often has the format "filename — short description".
  // Strip the leading filename up to the em-dash / dash.
  var first = cleaned.first;
  final dashIdx = _findSeparator(first);
  if (dashIdx >= 0 && dashIdx < first.length - 2) {
    first = first.substring(dashIdx + 1).trim();
  }
  // Join only up to the first blank-separated paragraph boundary.
  final out = StringBuffer(first);
  for (var i = 1; i < cleaned.length; i++) {
    final line = cleaned[i];
    if (line.startsWith('-') || line.startsWith('*')) break;
    out.write(' ');
    out.write(line);
    if (line.endsWith('.')) break;
  }
  return out.toString();
}

int _findSeparator(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    // em dash U+2014, en dash U+2013, ordinary hyphen after a filename
    if (c == 0x2014 || c == 0x2013) return i;
  }
  return -1;
}

String _truncateSentence(String s, int maxChars) {
  final trimmed = _sanitizeForMarkdown(s.trim());
  if (trimmed.length <= maxChars) return trimmed;
  final cut = trimmed.substring(0, maxChars);
  final lastPeriod = cut.lastIndexOf('.');
  if (lastPeriod > maxChars ~/ 2) {
    return cut.substring(0, lastPeriod + 1);
  }
  return '${cut.trimRight()}…';
}

/// Strip markdown-active characters from an extracted purpose. Doc
/// comments commonly contain `[ClassName]`, `*emphasis*`, or
/// backticks that, when embedded in a bulleted list item, become
/// broken links or inline-code spans that clash with the paths we
/// wrap in backticks ourselves. The sanitiser walks the string and
/// either drops or replaces the unsafe characters — preserving the
/// prose without preserving the markdown syntax.
String _sanitizeForMarkdown(String s) {
  if (s.isEmpty) return s;
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    switch (c) {
      case 0x60: // `
        // Drop backticks; they'd nest inside the assembler's own
        // inline-code wrapping and break rendering on some renderers.
        break;
      case 0x5B: // [
      case 0x5D: // ]
        // Square brackets form markdown link syntax. Replace with
        // parens so `[SpectralBasis]` reads as `(SpectralBasis)`
        // instead of an unresolved link.
        buf.writeCharCode(c == 0x5B ? 0x28 : 0x29);
        break;
      case 0x2A: // *
      case 0x5F: // _
        // Emphasis markers — drop when they'd form a pair around
        // real content. Conservatively just strip; the semantic
        // loss (italic/bold in a doc comment) doesn't affect the
        // purpose-line legibility.
        break;
      default:
        buf.writeCharCode(c);
    }
  }
  return buf.toString();
}
