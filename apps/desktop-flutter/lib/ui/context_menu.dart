import 'dart:async';

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
  /// Called after a keepOpen item fires its onTap. Lets the enclosing
  /// overlay rebuild so the item's visual state reflects the mutation
  /// (e.g. checkbox flip). Null for top-level menus.
  final VoidCallback? onItemChanged;

  const AppContextMenu({
    super.key,
    required this.tokens,
    required this.sections,
    required this.onDismiss,
    this.onItemChanged,
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
        children.add(AppContextMenuRow(
          item: item,
          onDismiss: onDismiss,
          onChanged: onItemChanged,
        ));
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
  /// Optional custom leading widget that overrides [icon]. Used when
  /// the row wants to render something that isn't a static glyph —
  /// a themed Checkbox, an avatar, a progress pip. Falls back to
  /// Icon([icon]) when null.
  final Widget? leading;
  final String label;
  final bool destructive;
  final VoidCallback onTap;
  /// Inline visualisation rendered to the right of the label. Lets a
  /// row carry microdata (sparkline, pill, count) at the glance level
  /// without the user needing to open anything.
  final Widget? trailing;
  /// When non-null, the row opens a nested menu on hover. Click still
  /// fires [onTap] when one is provided (for commit-configuration
  /// patterns: submenu lets you tweak, row click confirms).
  final List<AppContextMenuItem> Function()? submenuBuilder;
  /// True for pure-diagnostic rows (no click, no hover expansion —
  /// the row IS the information). Cursor stays default, no hover
  /// background, tap does nothing. Used for sparklines, status
  /// pills, read-only glyphs.
  final bool inert;
  /// When true, tapping this row runs [onTap] but does NOT dismiss
  /// the menu. Used for checkbox-style toggles where the reader
  /// wants to make several changes before clicking the confirming
  /// parent row. The enclosing submenu, if any, rebuilds so the
  /// row's visual state (checkmark, label suffix) reflects the new
  /// data.
  final bool keepOpen;
  const AppContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.leading,
    this.trailing,
    this.submenuBuilder,
    this.inert = false,
    this.keepOpen = false,
  });
}

class AppContextMenuRow extends StatefulWidget {
  final AppContextMenuItem item;
  final VoidCallback onDismiss;
  /// Invoked after a [AppContextMenuItem.keepOpen] row fires its
  /// onTap. Gives the enclosing overlay a chance to rebuild itself
  /// so any data-bound visuals (checkmarks, counts) re-read the
  /// mutated state. Null for rows whose menu has no listener.
  final VoidCallback? onChanged;
  const AppContextMenuRow({
    super.key,
    required this.item,
    required this.onDismiss,
    this.onChanged,
  });

  @override
  State<AppContextMenuRow> createState() => _AppContextMenuRowState();
}

class _AppContextMenuRowState extends State<AppContextMenuRow> {
  bool _hovered = false;
  OverlayEntry? _submenuEntry;
  // Submenu rows need to survive the cursor briefly leaving the parent
  // row on its way across the narrow gap to the submenu itself. Debounce
  // the close so a quick traversal doesn't tear the menu down.
  Timer? _submenuCloseTimer;
  // Track when the cursor is inside the nested overlay so the parent's
  // onExit doesn't fire an immediate close during normal cascade use.
  bool _submenuHovered = false;

  @override
  void dispose() {
    _submenuCloseTimer?.cancel();
    _submenuEntry?.remove();
    super.dispose();
  }

  void _openSubmenu() {
    if (_submenuEntry != null) return;
    final builder = widget.item.submenuBuilder;
    if (builder == null) return;
    final items = builder();
    if (items.isEmpty) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    // Compute both candidate anchors: right of the parent row (the
    // default), and left of the parent row (the flipped variant).
    // Final choice depends on how much room each side has — we want
    // the submenu to fit on screen rather than clip or scroll off.
    final parentTopLeft = renderBox.localToGlobal(Offset.zero);
    final parentRight =
        renderBox.localToGlobal(Offset(renderBox.size.width, 0));
    final screenSize = MediaQuery.of(context).size;
    // Heuristic: submenus are typically ~220–280px. Reserve 240 as a
    // conservative estimate so the flip decision errs toward safety.
    const estimatedSubmenuWidth = 240.0;
    final roomRight = screenSize.width - parentRight.dx;
    final roomLeft = parentTopLeft.dx;
    final flip =
        roomRight < estimatedSubmenuWidth && roomLeft > estimatedSubmenuWidth;
    final t = context.tokens;
    _submenuEntry = OverlayEntry(
      builder: (ctx) {
        // Re-run the builder on each rebuild so any keepOpen toggles
        // re-read mutated state (checkmarks, counts). The builder
        // is cheap; it reads from the host's closure-captured set.
        final freshItems = builder();
        // Anchor to the parent row's edge on whichever side has room.
        // For the flipped case, we still use a left offset but slide
        // the submenu off the parent's left edge by its estimated
        // width — the IntrinsicWidth sizing might undershoot a few
        // pixels, which is OK (a small right overlap reads as a
        // cascade, not a clip).
        final left = flip
            ? (parentTopLeft.dx - estimatedSubmenuWidth - 4)
            : (parentRight.dx + 4);
        return Positioned(
          left: left,
          top: parentTopLeft.dy - 4,
          child: MouseRegion(
            onEnter: (_) {
              _submenuHovered = true;
              _submenuCloseTimer?.cancel();
            },
            onExit: (_) {
              _submenuHovered = false;
              _scheduleSubmenuClose();
            },
            child: AppContextMenu(
              tokens: t,
              sections: [freshItems],
              // A click inside the submenu closes the whole stack
              // UNLESS the row is keepOpen (handled at row level;
              // keepOpen rows never call onDismiss).
              onDismiss: () {
                _closeSubmenu();
                widget.onDismiss();
              },
              // keepOpen items trigger a submenu rebuild so the
              // checkbox flip / count update shows on screen.
              onItemChanged: () => _submenuEntry?.markNeedsBuild(),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_submenuEntry!);
  }

  void _closeSubmenu() {
    _submenuCloseTimer?.cancel();
    _submenuEntry?.remove();
    _submenuEntry = null;
  }

  void _scheduleSubmenuClose() {
    _submenuCloseTimer?.cancel();
    _submenuCloseTimer = Timer(const Duration(milliseconds: 140), () {
      if (!_hovered && !_submenuHovered) _closeSubmenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final destructive = widget.item.destructive;
    final hasSubmenu = widget.item.submenuBuilder != null;
    final inert = widget.item.inert;
    final fg = destructive
        ? (_hovered ? t.stateDeleted : t.stateDeleted.withValues(alpha: 0.85))
        : (inert
            ? t.textMuted
            : (_hovered ? t.textStrong : t.textNormal));
    final bg = inert
        ? Colors.transparent
        : (_hovered
            ? (destructive
                ? t.stateDeleted.withValues(alpha: 0.08)
                : t.accentBright.withValues(alpha: 0.08))
            : (destructive
                ? t.stateDeleted.withValues(alpha: 0)
                : t.accentBright.withValues(alpha: 0)));
    final row = AnimatedContainer(
      duration: context.motion(const Duration(milliseconds: 90)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg),
      child: Row(
        children: [
          if (widget.item.leading != null)
            widget.item.leading!
          else
            Icon(widget.item.icon, size: 14, color: fg),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.item.label,
              style: TextStyle(color: fg, fontSize: 12),
            ),
          ),
          if (widget.item.trailing != null) ...[
            const SizedBox(width: 10),
            widget.item.trailing!,
          ],
          if (hasSubmenu) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 14, color: t.textFaint),
          ],
        ],
      ),
    );
    // Inert rows short-circuit: no mouse region, no gesture, no hover
    // state. The row renders flat and is pointer-transparent to clicks.
    if (inert) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        if (hasSubmenu) {
          _submenuCloseTimer?.cancel();
          _openSubmenu();
        }
      },
      onExit: (_) {
        setState(() => _hovered = false);
        if (hasSubmenu) _scheduleSubmenuClose();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Submenu + action can coexist: hovering opens the submenu
        // (for tweaking), clicking fires onTap (to confirm). When
        // only a submenu is present, the row still opens on hover
        // but a tap is a no-op — harmless either way.
        // keepOpen rows fire onTap + onChanged WITHOUT tearing down
        // the menu — checkbox-style rows rely on this to accept
        // multiple toggles before the user clicks the confirming
        // parent row.
        onTap: () {
          if (widget.item.keepOpen) {
            widget.item.onTap();
            widget.onChanged?.call();
          } else {
            widget.onDismiss();
            widget.item.onTap();
          }
        },
        child: row,
      ),
    );
  }
}
