import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ── SVG icon strings (ported from iconRegistry.tsx) ─────────────────────────

const _icons = <String, String>{
  'app-logo':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M4 4h8v8h-8z" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" opacity="0.4"/><path d="M6 6h4v4h-4z" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 4l2 2M12 4l-2 2M4 12l2-2M12 12l-2-2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 2v12M2 8h12" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="0.5 1.5" stroke-opacity="0.3"/></svg>',
  'changes':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M3 4h10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 8h10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 12h6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 10v4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M10 12h4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  'history':
      '<svg viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="4.8" stroke="currentColor" stroke-width="1.5"/><path d="M8 8L5.9 6.8M8 8L11.1 6.2" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="8" cy="8" r="0.8" fill="currentColor"/><path d="M3.54 3.54A6.3 6.3 0 0 0 3.54 12.46" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-opacity="0.55"/><path d="M3.54 12.46L4.9 11.3M3.54 12.46L2.4 10.9" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-opacity="0.55"/></svg>',
  'branches':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M8 13L8 7.5M8 7.5L3.2 2.8M8 7.5L12.8 2.8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><circle cx="8" cy="13" r="1.35" stroke="currentColor" stroke-width="1.5"/><circle cx="8" cy="7.5" r="1.35" stroke="currentColor" stroke-width="1.5"/><circle cx="3.2" cy="2.8" r="1.35" stroke="currentColor" stroke-width="1.5"/><circle cx="12.8" cy="2.8" r="1.35" stroke="currentColor" stroke-width="1.5"/></svg>',
  'xray':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M1.7 8Q8 4.6 14.3 8Q8 11.4 1.7 8Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><circle cx="8" cy="8" r="2.3" stroke="currentColor" stroke-width="1.3"/><circle cx="8" cy="8" r="0.7" fill="currentColor"/><path d="M4 6.15h8M4 9.85h8" stroke="currentColor" stroke-width="0.9" stroke-linecap="round" stroke-opacity="0.35"/></svg>',
  'settings':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M8 3.8L8 2.2M11.64 5.9L13.02 5.1M11.64 10.1L13.02 10.9M8 12.2L8 13.8M4.36 10.1L2.98 10.9M4.36 5.9L2.98 5.1" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="8" cy="8" r="4.2" stroke="currentColor" stroke-width="1.5"/><circle cx="8" cy="8" r="2" stroke="currentColor" stroke-width="1.3"/></svg>',
  'bond':
      '<svg viewBox="0 0 16 16" fill="none"><circle cx="4" cy="4" r="1.8" stroke="currentColor" stroke-width="1.5"/><circle cx="12" cy="4" r="1.8" stroke="currentColor" stroke-width="1.5"/><circle cx="8" cy="12" r="1.8" stroke="currentColor" stroke-width="1.5"/><path d="M5.4 5.4L6.9 10.5M10.6 5.4L9.1 10.5M5.8 4h4.4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>',
  'plus':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M8 3v10M3 8h10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  'x':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  'search':
      '<svg viewBox="0 0 16 16" fill="none"><circle cx="7" cy="7" r="4.5" stroke="currentColor" stroke-width="1.5"/><path d="M10.5 10.5L13.5 13.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  'tag':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M2 2h6l6 6-6 6-6-6V2z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><circle cx="5.5" cy="5.5" r="1" fill="currentColor"/></svg>',
  'sync':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M12.5 5.5l2-2-2-2v2h-9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M3.5 10.5l-2 2 2 2v-2h9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  'commit':
      '<svg viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="2.5" stroke="currentColor" stroke-width="1.5"/><path d="M8 1.5V5.5M8 10.5V14.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  'chevron-right':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M6 4l4 4-4 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  'chevron-down':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M4 6l4 4 4-4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  'trash':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M3 4h10M6 4V3a1 1 0 011-1h2a1 1 0 011 1v1M5 4l.5 9h5L11 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  'fetch':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M8 2v9M5 8l3 3 3-3" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 13h10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  'push':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M8 14V5M5 8L8 5l3 3" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 3h10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  'pull':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M8 2v9M5 8l3 3 3-3" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 13h10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  'git-branch':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M4 3.5v9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><circle cx="4" cy="3.5" r="1.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><circle cx="4" cy="12.5" r="1.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M5.5 4h4a2 2 0 012 2v1.2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><circle cx="11.5" cy="8.8" r="1.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  'status-conflict':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M8 2.5l5.2 9H2.8z" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 6v2.8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 11.2h.01" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  'sort':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M5 3.5v9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M3.7 4.8L5 3.5l1.3 1.3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M3.7 11.2L5 12.5l1.3-1.3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 4h4.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 8h3.2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M8 12h4.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  'clear':
      '<svg viewBox="0 0 16 16" fill="none"><path d="M5 4h6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M6.5 4v-1h3v1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M5.5 4v8c0 .8.7 1.5 1.5 1.5h2c.8 0 1.5-.7 1.5-1.5V4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M7 7v4M9 7v4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  'check':
      '<svg viewBox="0 0 24 24" fill="none"><polyline points="20 6 9 17 4 12" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
};

class AppIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final String? tone;

  const AppIcon(
      {super.key, required this.name, this.size = 16, this.color, this.tone});

  @override
  Widget build(BuildContext context) {
    final svgString = _icons[name] ?? _icons['x']!;
    final resolvedColor = color ?? _toneColor(context, tone);
    return SvgPicture.string(
      svgString,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
    );
  }

  static Color _toneColor(BuildContext context, String? tone) {
    final textNormal = Theme.of(context).colorScheme.onSurface;
    final textMuted = textNormal.withValues(alpha: 0.55);
    switch (tone) {
      case 'muted':
        return textMuted;
      case 'strong':
        return textNormal;
      default:
        return textNormal;
    }
  }
}
