import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Lightweight inline rich text renderer for AI-generated output.
///
/// Parses markdown formatting (`**bold**`, `*italic*`, `` `code` ``),
/// detects technical terms (PascalCase, CONSTANTS, file paths), and
/// applies theme-aware accent styling. Drop-in replacement for [Text].
///
/// All colors derive from [AppTokens] — zero hardcoded values.
Widget resonanceText(
  String text,
  AppTokens tokens, {
  TextStyle? baseStyle,
}) {
  final base = baseStyle ??
      TextStyle(
        color: tokens.textNormal,
        fontSize: 11.2,
        height: 1.45,
      );

  // If the text contains fenced code blocks (```), render as a Column
  // with alternating prose and code block widgets.
  if (text.contains('```')) {
    return _buildWithCodeBlocks(text, base, tokens);
  }

  return RichText(
    text: TextSpan(style: base, children: _scry(text, base, tokens)),
    softWrap: true,
  );
}

// ── Code block handling ────────────────────────────────────────────────

final _codeBlockRe = RegExp(r'```\w*\n?([\s\S]*?)```', multiLine: true);

Widget _buildWithCodeBlocks(String text, TextStyle base, AppTokens t) {
  final children = <Widget>[];
  var pos = 0;

  for (final m in _codeBlockRe.allMatches(text)) {
    // Prose before the code block.
    if (m.start > pos) {
      final prose = text.substring(pos, m.start).trim();
      if (prose.isNotEmpty) {
        children.add(RichText(
          text: TextSpan(style: base, children: _scry(prose, base, t)),
          softWrap: true,
        ));
        children.add(const SizedBox(height: 6));
      }
    }

    // The code block itself — collapsible when tall.
    final code = (m.group(1) ?? '').trimRight();
    if (code.isNotEmpty) {
      children.add(_CollapsibleCodeBlock(
        code: code,
        tokens: t,
        fontSize: (base.fontSize ?? 11.2) - 0.8,
      ));
      children.add(const SizedBox(height: 6));
    }

    pos = m.end;
  }

  // Trailing prose after last code block.
  if (pos < text.length) {
    final trailing = text.substring(pos).trim();
    if (trailing.isNotEmpty) {
      children.add(RichText(
        text: TextSpan(style: base, children: _scry(trailing, base, t)),
        softWrap: true,
      ));
    }
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}

// ── Pattern definitions (ordered by priority) ──────────────────────────

enum _Cat { bold, italic, code, quoted, tech, camel, constant, filePath, entity, punct }

final _patterns = <(_Cat, RegExp)>[
  // Markdown (highest priority — explicit author intent)
  (_Cat.bold, RegExp(r'\*\*(.+?)\*\*')),
  (_Cat.italic, RegExp(r'(?<!\*)\*([^*]+?)\*(?!\*)')),
  (_Cat.code, RegExp(r'`([^`]+)`')),

  // Single-quoted identifiers in prose: 'baseStyle', 'tokens', etc.
  // Requires the content to look like a code identifier (no spaces, ≤40 chars).
  (_Cat.quoted, RegExp(r"'([a-zA-Z_]\w{0,39})'")),

  // Technical resonance
  (_Cat.constant, RegExp(r'\b[A-Z]{3,}(?:_[A-Z0-9]+)+\b')),
  (_Cat.tech, RegExp(r'\b[A-Z][a-z]+(?:[A-Z][a-z]+)+\b')),

  // camelCase: function/variable names like resonanceText, buildCommit, etc.
  // Requires 2+ segments (lowercase start + at least one uppercase transition).
  (_Cat.camel, RegExp(r'\b[a-z][a-z0-9]*(?:[A-Z][a-z0-9]*)+(?:\(\))?')),

  // File paths: require at least one dot-extension OR start-of-path indicators.
  // This avoids matching concept lists like "summary/reasoning/evidence".
  (_Cat.filePath, RegExp(r'(?:[\w-]+/){2,}[\w-]+\.\w+|[\w-]+(?:\.\w+){2,}')),

  // Title Case entities: multi-word proper names and compound terms.
  // Allows short capitalized segments (X-Ray, AI Review) and hyphens.
  (_Cat.entity, RegExp(r'\b[A-Z][\w-]*(?:\s+[A-Z][\w-]*)+')),
];

// Punctuation matched separately (single chars, very low priority).
final _punctRe = RegExp(r'[—–:;|]');

// ── Span builder ───────────────────────────────────────────────────────

List<TextSpan> _scry(String text, TextStyle base, AppTokens t) {
  final hits = <_Hit>[];
  for (final (cat, re) in _patterns) {
    for (final m in re.allMatches(text)) {
      final isMarkdown =
          cat == _Cat.bold || cat == _Cat.italic || cat == _Cat.code || cat == _Cat.quoted;
      hits.add(_Hit(
        start: m.start,
        end: m.end,
        display: isMarkdown ? (m.group(1) ?? m.group(0)!) : m.group(0)!,
        cat: cat,
      ));
    }
  }

  // Sort by start; discard overlaps (first match wins at any position).
  hits.sort((a, b) => a.start.compareTo(b.start));
  final accepted = <_Hit>[];
  var cursor = 0;
  for (final h in hits) {
    if (h.start >= cursor) {
      accepted.add(h);
      cursor = h.end;
    }
  }

  // Build TextSpan list.
  final spans = <TextSpan>[];
  var pos = 0;

  for (final h in accepted) {
    if (h.start > pos) {
      _emitGap(spans, text.substring(pos, h.start), base, t);
    }
    spans.add(TextSpan(text: h.display, style: _styleFor(h.cat, base, t)));
    pos = h.end;
  }

  if (pos < text.length) {
    _emitGap(spans, text.substring(pos), base, t);
  }

  return spans;
}

/// Emit a plain text region, subtly muting standalone punctuation.
void _emitGap(List<TextSpan> out, String gap, TextStyle base, AppTokens t) {
  if (gap.isEmpty) return;

  final punctStyle = base.copyWith(color: t.textFaint);
  var last = 0;

  for (final m in _punctRe.allMatches(gap)) {
    if (m.start > last) {
      out.add(TextSpan(text: gap.substring(last, m.start)));
    }
    out.add(TextSpan(text: m.group(0), style: punctStyle));
    last = m.end;
  }

  if (last < gap.length) {
    out.add(TextSpan(text: gap.substring(last)));
  }
}

/// Map a category to its themed TextStyle.
TextStyle _styleFor(_Cat cat, TextStyle base, AppTokens t) {
  final codeFontSize = (base.fontSize ?? 11.2) - 0.5;
  return switch (cat) {
    _Cat.bold => base.copyWith(
        color: t.textStrong,
        fontWeight: FontWeight.w700,
      ),
    _Cat.italic => base.copyWith(
        fontStyle: FontStyle.italic,
      ),
    _Cat.code || _Cat.quoted => base.copyWith(
        color: t.chromeAccent,
        fontFamily: 'JetBrainsMono',
        fontSize: codeFontSize,
        backgroundColor: t.bg0.withValues(alpha: 0.4),
      ),
    _Cat.tech => base.copyWith(
        color: t.accentBright.withValues(alpha: 0.85),
        fontWeight: FontWeight.w600,
      ),
    _Cat.camel => base.copyWith(
        color: t.chromeAccent.withValues(alpha: 0.75),
        fontFamily: 'JetBrainsMono',
        fontSize: codeFontSize,
      ),
    _Cat.constant => base.copyWith(
        color: t.accentBright.withValues(alpha: 0.7),
        fontWeight: FontWeight.w600,
        fontFamily: 'JetBrainsMono',
        fontSize: codeFontSize,
      ),
    _Cat.filePath => base.copyWith(
        color: t.chromeAccent.withValues(alpha: 0.8),
        fontFamily: 'JetBrainsMono',
        fontSize: codeFontSize,
      ),
    _Cat.entity => base.copyWith(
        color: t.textStrong.withValues(alpha: 0.9),
      ),
    _Cat.punct => base.copyWith(
        color: t.textFaint,
      ),
  };
}

// ── Collapsible code block ─────────────────────────────────────────────

/// Code blocks collapse when taller than ~8 lines. Tap to expand.
class _CollapsibleCodeBlock extends StatefulWidget {
  final String code;
  final AppTokens tokens;
  final double fontSize;

  const _CollapsibleCodeBlock({
    required this.code,
    required this.tokens,
    required this.fontSize,
  });

  @override
  State<_CollapsibleCodeBlock> createState() => _CollapsibleCodeBlockState();
}

class _CollapsibleCodeBlockState extends State<_CollapsibleCodeBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final lineCount = '\n'.allMatches(widget.code).length + 1;
    final isLong = lineCount > 8;
    final codeStyle = TextStyle(
      color: t.chromeAccent,
      fontFamily: 'JetBrainsMono',
      fontSize: widget.fontSize,
      height: 1.5,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.bg0.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLong && !_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ClipRect(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text(widget.code, style: codeStyle),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(widget.code, style: codeStyle),
            ),
          if (isLong)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.1)),
                  ),
                ),
                child: Center(
                  child: Text(
                    _expanded ? '▲ collapse' : '▼ ${lineCount - 8} more lines',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Internal types ─────────────────────────────────────────────────────

class _Hit {
  final int start;
  final int end;
  final String display;
  final _Cat cat;
  const _Hit({
    required this.start,
    required this.end,
    required this.display,
    required this.cat,
  });
}
