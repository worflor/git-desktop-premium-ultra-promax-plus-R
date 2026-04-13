import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

/// Shared right-click / contextual menu used across the app (changes
/// page, PR list, etc). Call [showAppContextMenu] at the screen-space
/// position of the pointer-down event; the menu inserts an OverlayEntry
/// with a full-screen tap-catcher behind it so any pointer-down outside
/// the menu dismisses it.
void showAppContextMenu(
  BuildContext context,
  Offset globalPos,
  List<List<AppContextMenuItem>> sections,
) {
  final overlay = Overlay.of(context);
  final t = context.tokens;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      return Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => entry.remove(),
            ),
          ),
          Positioned(
            left: globalPos.dx,
            top: globalPos.dy,
            child: AppContextMenu(
              tokens: t,
              sections: sections,
              onDismiss: () => entry.remove(),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
}

class AppContextMenu extends StatelessWidget {
  final AppTokens tokens;
  final List<List<AppContextMenuItem>> sections;
  final VoidCallback onDismiss;

  const AppContextMenu({
    super.key,
    required this.tokens,
    required this.sections,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var s = 0; s < sections.length; s++) {
      if (s > 0) {
        children.add(
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: tokens.chromeBorder.withValues(alpha: 0.25),
          ),
        );
      }
      for (final item in sections[s]) {
        children.add(AppContextMenuRow(item: item, onDismiss: onDismiss));
      }
    }
    // IntrinsicWidth wraps the Column so it sizes to its widest item,
    // giving the rows a bounded width to stretch into. Without this the
    // surrounding Positioned (left/top only, no width) would feed the
    // Column unbounded width AND the stretch alignment would assert
    // "BoxConstraints forces an infinite width" — locking the pipeline
    // on first right-click.
    return Material(
      color: Colors.transparent,
      child: IntrinsicWidth(
        child: Container(
          constraints: const BoxConstraints(minWidth: 200),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: tokens.surface1,
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: tokens.chromeBorder.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: tokens.shadowElev.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class AppContextMenuItem {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;
  const AppContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

class AppContextMenuRow extends StatefulWidget {
  final AppContextMenuItem item;
  final VoidCallback onDismiss;
  const AppContextMenuRow({
    super.key,
    required this.item,
    required this.onDismiss,
  });

  @override
  State<AppContextMenuRow> createState() => _AppContextMenuRowState();
}

class _AppContextMenuRowState extends State<AppContextMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final destructive = widget.item.destructive;
    final fg = destructive
        ? (_hovered ? t.stateDeleted : t.stateDeleted.withValues(alpha: 0.85))
        : (_hovered ? t.textStrong : t.textNormal);
    final bg = _hovered
        ? (destructive
            ? t.stateDeleted.withValues(alpha: 0.08)
            : t.accentBright.withValues(alpha: 0.08))
        : (destructive
            ? t.stateDeleted.withValues(alpha: 0)
            : t.accentBright.withValues(alpha: 0));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.onDismiss();
          widget.item.onTap();
        },
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 90)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg),
          child: Row(
            children: [
              Icon(widget.item.icon, size: 14, color: fg),
              const SizedBox(width: 10),
              Text(
                widget.item.label,
                style: TextStyle(color: fg, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
