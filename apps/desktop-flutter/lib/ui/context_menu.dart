import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'motion.dart';
import 'tokens.dart';

/// Shared right-click / contextual menu used across the app (changes
/// page, PR list, etc). Call [showAppContextMenu] at the screen-space
/// position of the pointer-down event; the menu inserts an OverlayEntry
/// with a full-screen tap-catcher behind it so any pointer-down outside
/// the menu dismisses it.
///
/// Returns a [Future] that resolves when the menu closes (item picked
/// or outside-tap). Lets the caller pre-highlight the row that opened
/// the menu and clear the highlight when this future completes — the
/// row visually owns the menu while it's open, matching the changes
/// panel pattern.
///
/// `sections` is a list of [MenuSection] — most callers want
/// [ListMenuSection] (the classic icon+label rows). The project menu
/// uses [TileChipMenuSection] (locked tile strip on top, chip rail
/// below) when the action set splits cleanly into "always-three
/// primaries + situational extras". Sections are separated by hairline
/// dividers in render order.
Future<void> showAppContextMenu(
  BuildContext context,
  Offset globalPos,
  List<MenuSection> sections,
) {
  final overlay = Overlay.of(context);
  final t = context.tokens;
  final completer = Completer<void>();
  late OverlayEntry entry;
  void dismiss() {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      return Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => dismiss(),
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: ViewportClampDelegate(desired: globalPos),
              child: AppContextMenu(
                tokens: t,
                sections: sections,
                onDismiss: dismiss,
              ),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
  return completer.future;
}

class ViewportClampDelegate extends SingleChildLayoutDelegate {
  final Offset desired;
  final double margin;
  final Alignment anchor;
  ViewportClampDelegate({
    required this.desired,
    this.margin = 8.0,
    this.anchor = Alignment.topLeft,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final ax = childSize.width * (anchor.x + 1) / 2;
    final ay = childSize.height * (anchor.y + 1) / 2;
    final dx = desired.dx - ax;
    final dy = desired.dy - ay;
    final maxX = math.max(margin, size.width - childSize.width - margin);
    final maxY = math.max(margin, size.height - childSize.height - margin);
    return Offset(dx.clamp(margin, maxX), dy.clamp(margin, maxY));
  }

  @override
  bool shouldRelayout(ViewportClampDelegate old) =>
      old.desired != desired || old.margin != margin || old.anchor != anchor;
}

class AppContextMenu extends StatelessWidget {
  final AppTokens tokens;
  final List<MenuSection> sections;
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
      // Hairline divider between adjacent sections — except when the
      // previous section was a surface-owning section (TileChip or
      // Status). Those paint their own edge treatment, and the
      // surface tone shift is enough delineation without a hairline.
      if (s > 0 &&
          sections[s - 1] is! TileChipMenuSection &&
          sections[s - 1] is! StatusMenuSection) {
        children.add(
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 3),
            color: tokens.chromeBorder.withValues(alpha: 0.25),
          ),
        );
      }
      final section = sections[s];
      switch (section) {
        case ListMenuSection(:final items):
          for (final item in items) {
            children.add(AppContextMenuRow(
              item: item,
              onDismiss: onDismiss,
              onChanged: onItemChanged,
            ));
          }
        case StatusMenuSection(:final child):
          children.add(_IntrinsicPassive(child: child));
        case TileChipMenuSection(
              :final tiles, :final chips, :final toolChips):
          children.add(_TileChipMenuSection(
            tokens: tokens,
            tiles: tiles,
            chips: chips,
            toolChips: toolChips,
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
            // Card-level radius: the menu IS a small popover surface,
            // so it inherits the theme's full radius. Pixelated themes
            // get sharp corners that match their grid; rounded themes
            // get the gentle radius the rest of the chrome shares.
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.cardRadius),
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

/// One section of a context menu. Sections render in the order given,
/// separated by hairline dividers. The two shapes today:
///   * [ListMenuSection] — vertical icon+label rows, the classic shape.
///   * [TileChipMenuSection] — locked tile strip (always-actions, never
///     reorder) + chip rail (situational actions, ambient secondary
///     register so a flow-laid position doesn't read as a slot
///     violation). See the project menu for the canonical use.
sealed class MenuSection {
  const MenuSection();
}

class ListMenuSection extends MenuSection {
  final List<AppContextMenuItem> items;
  const ListMenuSection(this.items);
}

/// Two-language section: [tiles] are square primaries (locked
/// positions, drawn first), [chips] are pill-shaped secondaries (drawn
/// in canonical order, may wrap). Both lists may carry conditional
/// items — callers filter before passing — so the section can render
/// just tiles, just chips, or both. An empty section is a no-op (the
/// caller is responsible for not constructing one when nothing's left).
/// Full-bleed inert section — renders [child] directly with no row
/// chrome, no padding, no hover state. Used for status strips and
/// other ambient information surfaces that own their full width.
class StatusMenuSection extends MenuSection {
  final Widget child;
  const StatusMenuSection(this.child);
}

class TileChipMenuSection extends MenuSection {
  final List<AppContextMenuItem> tiles;
  final List<AppContextMenuItem> chips;
  /// External-tool chips — rendered as their own mosaic row(s) below
  /// the main chips rail. Max 3 per row; 4+ wraps. Each tool gets
  /// its own direct-click cell (no submenu).
  final List<AppContextMenuItem> toolChips;
  const TileChipMenuSection({
    required this.tiles,
    this.chips = const [],
    this.toolChips = const [],
  });
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
  /// When non-null, the row renders this widget *instead of* the
  /// standard icon+label+trailing layout. Used for full-width visual
  /// status strips (glyph rows, sparklines, mini-dashboards) where
  /// the informational content doesn't fit the "icon · text" pattern.
  /// Typically pairs with `inert: true`.
  final Widget? custom;
  final Color? iconColor;
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
    this.custom,
    this.iconColor,
  });
}

/// Anchor for a submenu overlay, in global screen coordinates.
typedef _SubmenuAnchor = ({double left, double top});

/// Shared submenu lifecycle: hover-debounced close, overlay
/// insert/remove, dispose cleanup. Both [AppContextMenuRow] (cascades
/// to the right of a list row) and [_ContextMenuChip] (drops below an
/// inline chip) layer on top with their own anchor strategy.
///
/// Host responsibilities:
///   * call [hoverEnterRespectingSubmenu] / [hoverExitRespectingSubmenu]
///     from the host's MouseRegion so the close-timer pairs with the
///     hover state. The mixin's onEnter cancels any pending close —
///     so re-entering the host within the 90 ms debounce window keeps
///     a freshly-opened submenu alive.
///   * call [openSubmenu] from the host's interaction trigger (hover
///     for rows, click for chips). The mixin no-ops if no submenu is
///     configured or one is already open.
///   * implement [submenuItems] (nullable — null = no submenu) and
///     [computeSubmenuAnchor] (where to position the overlay relative
///     to the host's RenderBox in global coords).
///   * implement [bubbleDismiss] to propagate a submenu-item's
///     dismiss request up to the outermost menu.
mixin _SubmenuController<W extends StatefulWidget> on State<W> {
  bool _hovered = false;
  OverlayEntry? _submenuEntry;
  Timer? _submenuCloseTimer;
  // Tracks whether the cursor is inside the submenu overlay so the
  // host's close-timer doesn't fire mid-cascade. Kept in sync by the
  // overlay's MouseRegion below.
  bool _submenuHovered = false;

  // ── Host hooks ─────────────────────────────────────────────────────
  List<AppContextMenuItem>? get submenuItems;
  _SubmenuAnchor computeSubmenuAnchor(RenderBox box, BuildContext ctx);
  void bubbleDismiss();

  bool get hasSubmenu => submenuItems != null;
  bool get hovered => _hovered;

  // ── Hover handlers (host wires these into its MouseRegion) ────────
  void hoverEnterRespectingSubmenu() {
    setState(() => _hovered = true);
    if (hasSubmenu) {
      // Re-entering the host inside the close debounce should KEEP the
      // submenu alive. Without this cancel a quick mouse leave →
      // re-enter sequence (cursor jitter, narrow gutter) would tear
      // down a submenu that should have stayed open.
      _submenuCloseTimer?.cancel();
    }
  }

  void hoverExitRespectingSubmenu() {
    setState(() => _hovered = false);
    if (hasSubmenu) _scheduleSubmenuClose();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────
  void openSubmenu() {
    if (_submenuEntry != null) return;
    final items = submenuItems;
    if (items == null || items.isEmpty) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchor = computeSubmenuAnchor(renderBox, context);
    final t = context.tokens;
    _submenuEntry = OverlayEntry(
      builder: (ctx) {
        // Re-resolve items each rebuild so keepOpen toggles re-read
        // mutated state (checkmarks, counts).
        final freshItems = submenuItems ?? const <AppContextMenuItem>[];
        return Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: ViewportClampDelegate(
              desired: Offset(anchor.left, anchor.top),
            ),
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
                sections: [ListMenuSection(freshItems)],
                onDismiss: () {
                  closeSubmenu();
                  bubbleDismiss();
                },
                onItemChanged: () => _submenuEntry?.markNeedsBuild(),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_submenuEntry!);
  }

  void closeSubmenu() {
    _submenuCloseTimer?.cancel();
    _submenuEntry?.remove();
    _submenuEntry = null;
  }

  void _scheduleSubmenuClose() {
    _submenuCloseTimer?.cancel();
    // 90 ms is the minimum gap a cursor traversal needs to cross the
    // 4 px gutter between host and submenu without firing mid-cross.
    _submenuCloseTimer = Timer(const Duration(milliseconds: 90), () {
      if (!_hovered && !_submenuHovered) closeSubmenu();
    });
  }

  @override
  void dispose() {
    _submenuCloseTimer?.cancel();
    _submenuEntry?.remove();
    super.dispose();
  }
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

class _AppContextMenuRowState extends State<AppContextMenuRow>
    with _SubmenuController<AppContextMenuRow> {
  // Estimated submenu width used for the "flip to left side" room
  // check. Real submenus typically render 220–280 px wide; 240 is a
  // safe lower bound — under-estimating widens the right-room check,
  // which is the safer error (a small overlap reads as a cascade,
  // a clip reads as a bug).
  static const double _kEstimatedSubmenuWidth = 240.0;

  @override
  List<AppContextMenuItem>? get submenuItems {
    final builder = widget.item.submenuBuilder;
    return builder?.call();
  }

  @override
  void bubbleDismiss() => widget.onDismiss();

  @override
  _SubmenuAnchor computeSubmenuAnchor(RenderBox box, BuildContext ctx) {
    // Cascade right of the parent row by default; flip to the left
    // if the right edge would push the submenu off-screen and the
    // left has room. -4 / +4 keeps a tiny visual gutter so the
    // submenu reads as a child rather than a continuation of the
    // parent row.
    final topLeft = box.localToGlobal(Offset.zero);
    final right = box.localToGlobal(Offset(box.size.width, 0));
    final screen = MediaQuery.of(ctx).size;
    final roomRight = screen.width - right.dx;
    final roomLeft = topLeft.dx;
    final flip = roomRight < _kEstimatedSubmenuWidth &&
        roomLeft > _kEstimatedSubmenuWidth;
    final left = flip
        ? (topLeft.dx - _kEstimatedSubmenuWidth - 4)
        : (right.dx + 4);
    return (left: left, top: topLeft.dy);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final destructive = widget.item.destructive;
    final inert = widget.item.inert;
    final fg = destructive
        ? (hovered ? t.stateDeleted : t.stateDeleted.withValues(alpha: 0.85))
        : (inert
            ? t.textMuted
            : (hovered ? t.textStrong : t.textNormal));
    final bg = inert
        ? Colors.transparent
        : (hovered
            ? (destructive
                ? t.stateDeleted.withValues(alpha: 0.08)
                : t.accentBright.withValues(alpha: 0.08))
            : (destructive
                ? t.stateDeleted.withValues(alpha: 0)
                : t.accentBright.withValues(alpha: 0)));
    final hasTrailing = widget.item.trailing != null;
    final rowContent = widget.item.custom != null
        ? widget.item.custom!
        : Row(
            children: [
              if (widget.item.leading != null)
                widget.item.leading!
              else
                Icon(widget.item.icon, size: 14,
                    color: widget.item.iconColor ?? fg),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.item.label,
                  style: TextStyle(color: fg, fontSize: 12),
                ),
              ),
              if (hasSubmenu) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 14, color: t.textFaint),
              ],
            ],
          );
    final row = AnimatedContainer(
      duration: context.motion(const Duration(milliseconds: 90)),
      padding: EdgeInsets.only(
        left: 12, top: 6, bottom: 6,
        right: hasTrailing ? 0 : 12,
      ),
      decoration: BoxDecoration(color: bg),
      child: rowContent,
    );
    if (inert) return row;
    Widget main = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        hoverEnterRespectingSubmenu();
        if (hasSubmenu) openSubmenu();
      },
      onExit: (_) => hoverExitRespectingSubmenu(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
    if (!hasTrailing) return main;
    return Row(
      children: [
        Expanded(child: main),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: widget.item.trailing!,
        ),
      ],
    );
  }
}

/// Tile strip on top, chip rail below — see [TileChipMenuSection]. The
/// strip is a `Row` because the locked-3 tiles must never wrap (Wrap's
/// reported min-intrinsic-width is one child, which let the menu's
/// IntrinsicWidth solver pick a width that broke the strip across two
/// lines). The rail uses `Wrap` — chips are flow elements by design,
/// a wrap doesn't read as a slot violation.
class _TileChipMenuSection extends StatelessWidget {
  final AppTokens tokens;
  final List<AppContextMenuItem> tiles;
  final List<AppContextMenuItem> chips;
  final List<AppContextMenuItem> toolChips;
  final VoidCallback onDismiss;
  final VoidCallback? onChanged;

  static const double _kTileWidth = 64;
  static const double _kTileSpacing = 4;
  static const int _kMaxToolsPerRow = 3;

  const _TileChipMenuSection({
    required this.tokens,
    required this.tiles,
    required this.chips,
    this.toolChips = const [],
    required this.onDismiss,
    this.onChanged,
  });

  /// Width of the tile strip on a single line. The chip rail is
  /// constrained to this width so it wraps inside the strip's
  /// footprint instead of pushing the menu wider than the tiles need
  /// — the menu sizes to the tiles, chips fit underneath.
  double get _tileStripWidth {
    if (tiles.isEmpty) return 0;
    return tiles.length * _kTileWidth +
        (tiles.length - 1) * _kTileSpacing;
  }

  @override
  Widget build(BuildContext context) {
    // Section is vertical-padding only — the chip rail goes
    // edge-to-edge of the menu, like a row's hover background does.
    // The tile strip carries its own horizontal padding to stay
    // aligned with the list rows' label start.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // Row, not Wrap: the locked-3 tiles must never break to
              // a second line. Wrap reports its min-intrinsic-width as
              // one child wide, so the enclosing IntrinsicWidth solver
              // was happy to size the menu narrow enough to wrap the
              // tiles. Row pins its intrinsic width to the sum of
              // children, forcing the menu wide enough to hold the
              // strip on a single line.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: _kTileSpacing),
                    _ContextMenuTile(
                      tokens: tokens,
                      item: tiles[i],
                      onDismiss: onDismiss,
                    ),
                  ],
                ],
              ),
            ),
          if (tiles.isNotEmpty && chips.isNotEmpty)
            const SizedBox(height: 4),
          if (chips.isNotEmpty)
            _ChipRailMosaic(
              tokens: tokens,
              chips: chips,
              maxWidth: tiles.isEmpty
                  ? double.infinity
                  : _tileStripWidth + 24,
              onDismiss: onDismiss,
              onChanged: onChanged,
            ),
          // ── Tool rows — own mosaic row(s) below the chips ────
          // Each row is its own _ChipRailMosaic with fresh seams.
          // Max 3 per row; 4+ wraps. Visually connected: same
          // surface2 tone, no gap, just stacked.
          if (toolChips.isNotEmpty)
            for (var start = 0;
                start < toolChips.length;
                start += _kMaxToolsPerRow)
              _ChipRailMosaic(
                tokens: tokens,
                chips: toolChips.sublist(
                  start,
                  (start + _kMaxToolsPerRow).clamp(0, toolChips.length),
                ),
                maxWidth: tiles.isEmpty
                    ? double.infinity
                    : _tileStripWidth + 24,
                onDismiss: onDismiss,
                onChanged: onChanged,
              ),
        ],
      ),
    );
  }
}

/// Shattered mosaic chip rail — equal-width cells inside one inset
/// surface, with jagged per-open seams between adjacent cells. Hover
/// wash and hit-testing follow the seam polygons 1:1 via per-cell
/// [ClipPath] clipping. Layout uses a three-layer [Stack]:
///   1. Invisible sizing child (`Visibility(maintainSize)`) — gives
///      [IntrinsicHeight] a height to query without painting.
///   2. [Positioned] cells — each extends ±[_kJitterFrac] of its
///      nominal width into both neighbours so the clip can follow
///      seam jitter without clamping at the cell edge.
///   3. Decorative seam painter on top (`IgnorePointer`).
class _ChipRailMosaic extends StatefulWidget {
  final AppTokens tokens;
  final List<AppContextMenuItem> chips;
  final double maxWidth;
  final VoidCallback onDismiss;
  final VoidCallback? onChanged;

  /// Fraction of nominal cell width a seam vertex can bleed into
  /// either neighbour. Shared by the painter, the clipper, and the
  /// positioning math. 0.10 = ±10 %.
  static const double _kJitterFrac = 0.10;

  const _ChipRailMosaic({
    required this.tokens,
    required this.chips,
    required this.maxWidth,
    required this.onDismiss,
    this.onChanged,
  });

  @override
  State<_ChipRailMosaic> createState() => _ChipRailMosaicState();
}

/// One crack between two mosaic cells. Vertices in normalised space
/// (dx [-1..1], dy [0..1]); painter + clipper scale identically.
class _MosaicSeam {
  final List<Offset> vertices;
  final double widthScale; // 0.6..1.4
  final double alphaScale; // 0.7..1.3
  final List<double> segmentWidthScales; // per-segment, length = vertices - 1
  const _MosaicSeam({
    required this.vertices,
    required this.widthScale,
    required this.alphaScale,
    required this.segmentWidthScales,
  });
}

class _ChipRailMosaicState extends State<_ChipRailMosaic> {
  late final List<_MosaicSeam> _seams;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _seams = List.generate(
      math.max(0, widget.chips.length - 1),
      (_) => _generateSeam(rng),
    );
  }

  static _MosaicSeam _generateSeam(math.Random rng) {
    final segments = 4 + rng.nextInt(5);
    final ys = <double>[0.0];
    for (var i = 1; i < segments; i++) ys.add(rng.nextDouble());
    ys.add(1.0);
    ys.sort();
    final vertices = <Offset>[
      for (final y in ys)
        Offset(
          (rng.nextDouble() * 2.0 - 1.0) *
              (rng.nextDouble() < 0.25 ? 1.0 : 0.6),
          y,
        ),
    ];
    return _MosaicSeam(
      vertices: vertices,
      widthScale: 0.6 + rng.nextDouble() * 0.8,
      alphaScale: 0.7 + rng.nextDouble() * 0.6,
      segmentWidthScales: List.generate(
        vertices.length - 1,
        (_) => 0.7 + rng.nextDouble() * 0.6,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.chips.length;
    if (n == 0) return const SizedBox.shrink();
    final railW = widget.maxWidth.isFinite ? widget.maxWidth : 200.0;
    final cellW = railW / n;
    final jitter = cellW * _ChipRailMosaic._kJitterFrac;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.tokens.surface2,
          border: Border.symmetric(
            horizontal: BorderSide(
              color:
                  widget.tokens.chromeBorder.withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
        ),
        child: IntrinsicHeight(
          child: Stack(
            children: [
              // Layer 1 — invisible sizing reference.
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: false,
                maintainState: false,
                child: Row(children: [
                  Expanded(
                    child: _MosaicChipCell(
                      tokens: widget.tokens,
                      item: widget.chips.first,
                      onDismiss: widget.onDismiss,
                    ),
                  ),
                ]),
              ),
              // Layer 2 — real cells (overlapping Positioned).
              for (var i = 0; i < n; i++)
                _cell(i, n, cellW, jitter, railW),
              // Layer 3 — decorative seam strokes.
              if (_seams.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ShatteredSeamPainter(
                        cellCount: n,
                        seams: _seams,
                        baseColor: widget.tokens.chromeBorder,
                        baseAlpha: 0.34,
                        baseWidth: 0.7,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(
      int i, int n, double cellW, double jitter, double railW) {
    final isFirst = i == 0;
    final isLast = i == n - 1;
    final left = isFirst ? 0.0 : i * cellW - jitter;
    final right = isLast ? railW : (i + 1) * cellW + jitter;
    final leftNom = isFirst ? 0.0 : jitter;
    final rightNom = isFirst ? cellW : jitter + cellW;
    return Positioned(
      left: left,
      width: right - left,
      top: 0,
      bottom: 0,
      child: ClipPath(
        clipper: _MosaicCellClipper(
          leftNominal: leftNom,
          rightNominal: rightNom,
          jitter: jitter,
          leftSeam: i > 0 ? _seams[i - 1] : null,
          rightSeam: i < n - 1 ? _seams[i] : null,
        ),
        child: _MosaicChipCell(
          tokens: widget.tokens,
          item: widget.chips[i],
          onDismiss: widget.onDismiss,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

/// Clips a mosaic cell to its polygon between adjacent seams.
/// [leftNominal] / [rightNominal] are the nominal seam x in cell-
/// local coords. Vertices jitter ±[jitter] from those nominals using
/// the same formula [_ShatteredSeamPainter] uses — pixel-aligned.
class _MosaicCellClipper extends CustomClipper<Path> {
  final double leftNominal;
  final double rightNominal;
  final double jitter;
  final _MosaicSeam? leftSeam;
  final _MosaicSeam? rightSeam;

  _MosaicCellClipper({
    required this.leftNominal,
    required this.rightNominal,
    required this.jitter,
    required this.leftSeam,
    required this.rightSeam,
  });

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    // Top-left.
    path.moveTo(
      leftSeam != null
          ? leftNominal + leftSeam!.vertices.first.dx * jitter
          : 0,
      0,
    );
    // Top-right.
    path.lineTo(
      rightSeam != null
          ? rightNominal + rightSeam!.vertices.first.dx * jitter
          : w,
      0,
    );
    // Right edge (seam top → bottom, or straight down).
    if (rightSeam != null) {
      for (var k = 1; k < rightSeam!.vertices.length; k++) {
        final v = rightSeam!.vertices[k];
        path.lineTo(rightNominal + v.dx * jitter, v.dy * h);
      }
    } else {
      path.lineTo(w, h);
    }
    // Bottom-left.
    if (leftSeam != null) {
      final v = leftSeam!.vertices.last;
      path.lineTo(leftNominal + v.dx * jitter, h);
    } else {
      path.lineTo(0, h);
    }
    // Left edge (seam bottom → top, reversed).
    if (leftSeam != null) {
      for (var k = leftSeam!.vertices.length - 2; k >= 0; k--) {
        final v = leftSeam!.vertices[k];
        path.lineTo(leftNominal + v.dx * jitter, v.dy * h);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_MosaicCellClipper old) =>
      old.leftNominal != leftNominal ||
      old.rightNominal != rightNominal ||
      old.jitter != jitter ||
      !identical(old.leftSeam, leftSeam) ||
      !identical(old.rightSeam, rightSeam);
}

/// Draws each [_MosaicSeam] as a piecewise-stroked polyline so per-
/// segment width variation carries through (a single `Path` would lock
/// the whole crack to one stroke width). Vertex `dx` is scaled by
/// 10 % of the cell width — the user-specified bleed leeway — so a
/// crack can intrude that far into either neighbour but no further.
class _ShatteredSeamPainter extends CustomPainter {
  final int cellCount;
  final List<_MosaicSeam> seams;
  final Color baseColor;
  final double baseAlpha;
  final double baseWidth;

  _ShatteredSeamPainter({
    required this.cellCount,
    required this.seams,
    required this.baseColor,
    required this.baseAlpha,
    required this.baseWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cellCount < 2 || seams.isEmpty) return;
    final cellWidth = size.width / cellCount;
    // The user-specified ceiling: a vertex can bleed up to 10 % of a
    // cell width into either neighbour. Per-vertex jitter in the
    // [-1..1] dx is multiplied by this to give the actual offset.
    final jitterCeiling = cellWidth * _ChipRailMosaic._kJitterFrac;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < seams.length && i < cellCount - 1; i++) {
      final nominalX = cellWidth * (i + 1);
      final seam = seams[i];
      paint.color = baseColor.withValues(
        alpha: (baseAlpha * seam.alphaScale).clamp(0.0, 1.0),
      );
      // Pre-resolve every vertex to canvas coords once so the per-
      // segment loop just reads them.
      final pts = <Offset>[
        for (final v in seam.vertices)
          Offset(nominalX + v.dx * jitterCeiling, v.dy * size.height),
      ];
      for (var k = 0; k < pts.length - 1; k++) {
        paint.strokeWidth =
            baseWidth * seam.widthScale * seam.segmentWidthScales[k];
        canvas.drawLine(pts[k], pts[k + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShatteredSeamPainter old) =>
      old.cellCount != cellCount ||
      old.baseColor != baseColor ||
      old.baseAlpha != baseAlpha ||
      old.baseWidth != baseWidth ||
      !identical(old.seams, seams);
}

/// One cell of the mosaic rail. Layout-wise just an [Expanded] child
/// of a [Row] — the cell takes its share of the rail width, content
/// (icon + label) centers within it, and hover paints the standard
/// accentBright @ 0.08 wash filling the cell's full rectangle. The
/// jagged seams drawn on top by [_JaggedSeamPainter] are the visual
/// dividers; cells stay simple rectangles for predictable hover and
/// submenu anchoring.
class _MosaicChipCell extends StatefulWidget {
  final AppTokens tokens;
  final AppContextMenuItem item;
  final VoidCallback onDismiss;
  final VoidCallback? onChanged;
  const _MosaicChipCell({
    required this.tokens,
    required this.item,
    required this.onDismiss,
    this.onChanged,
  });

  @override
  State<_MosaicChipCell> createState() => _MosaicChipCellState();
}

class _MosaicChipCellState extends State<_MosaicChipCell>
    with _SubmenuController<_MosaicChipCell> {
  @override
  List<AppContextMenuItem>? get submenuItems {
    final builder = widget.item.submenuBuilder;
    return builder?.call();
  }

  @override
  void bubbleDismiss() => widget.onDismiss();

  @override
  _SubmenuAnchor computeSubmenuAnchor(RenderBox box, BuildContext ctx) {
    // Drop the submenu directly below the cell. Cells don't shift
    // after the menu opens (Row layout is stable), so a click-anchored
    // submenu stays aligned for its lifetime.
    final bottomLeft = box.localToGlobal(Offset(0, box.size.height));
    return (left: bottomLeft.dx, top: bottomLeft.dy + 4);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    // Foreground stays `textMuted → textStrong` on hover — the chip
    // rail sits beneath the primary tile strip, so it reads as the
    // section's secondary register. Hover bg fills the full cell
    // rectangle (no own border-radius) so a hovered cell visually
    // "lights up" inside the rail; the jagged seams on top still
    // delineate which cell is which.
    final fg = hovered ? t.textStrong : t.textMuted;
    final bg = hovered
        ? t.accentBright.withValues(alpha: 0.08)
        : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => hoverEnterRespectingSubmenu(),
      onExit: (_) => hoverExitRespectingSubmenu(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (hasSubmenu) {
            // Click-toggle: tapping an open submenu closes it. Without
            // this the only dismiss paths are "click an item" or
            // "leave the cell" — neither obvious for a cell whose
            // body doesn't visually change after open.
            if (_submenuEntry != null) {
              closeSubmenu();
            } else {
              openSubmenu();
            }
            return;
          }
          if (widget.item.keepOpen) {
            widget.item.onTap();
            widget.onChanged?.call();
          } else {
            widget.onDismiss();
            widget.item.onTap();
          }
        },
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 90)),
          // Vertical padding pushes the cell's hover footprint and the
          // rail's overall height closer to the menu's top/bottom
          // edges — the rail reads as a substantial band rather than
          // a pinched strip. Horizontal stays tight so labels claim
          // most of the cell width.
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          color: bg,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.item.icon, size: 12,
                  color: widget.item.iconColor ?? fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 11),
                ),
              ),
              if (hasSubmenu) ...[
                const SizedBox(width: 3),
                Icon(Icons.chevron_right, size: 12, color: t.textFaint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Square-ish primary tile: icon top, single-line label below. Locked
/// position inside the strip — order in [TileChipMenuSection.tiles] is
/// the order on screen. Hover wash uses the same accentBright @ 0.08
/// tint [AppContextMenuRow] uses (and the chip mirrors), so all three
/// interactive surfaces in a tile/chip menu share one hover grammar.
///
/// Tiles intentionally do NOT support submenus — the strip is the
/// primary register and a cascade off a tile would either fight the
/// chip rail below it for vertical room or open over the surrounding
/// always-context. Submenu actions belong on chips. The constructor
/// asserts this so a caller setting [AppContextMenuItem.submenuBuilder]
/// on a tile gets a debug-time failure instead of a silent no-op.
class _ContextMenuTile extends StatefulWidget {
  final AppTokens tokens;
  final AppContextMenuItem item;
  final VoidCallback onDismiss;
  _ContextMenuTile({
    required this.tokens,
    required this.item,
    required this.onDismiss,
  }) : assert(
          item.submenuBuilder == null,
          'Tile items in TileChipMenuSection.tiles cannot carry a '
          'submenuBuilder — submenu actions belong on the chip rail. '
          'Move "${item.label}" to TileChipMenuSection.chips.',
        );

  @override
  State<_ContextMenuTile> createState() => _ContextMenuTileState();
}

class _ContextMenuTileState extends State<_ContextMenuTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final fg = _hovered ? t.textStrong : t.textNormal;
    final bg = _hovered
        ? t.accentBright.withValues(alpha: 0.08)
        : t.accentBright.withValues(alpha: 0);
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
          width: 64,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            // Theme-derived corner — same `geometry.radius` every
            // other interactive surface in the app uses (file rows,
            // buttons, hover backgrounds, popovers). Tiles read as
            // continuous with the rest of the chrome instead of
            // adopting a tighter sub-element radius the user has to
            // mentally bucket separately.
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.radius),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.item.icon, size: 18,
                  color: widget.item.iconColor ?? fg),
              const SizedBox(height: 4),
              Text(
                widget.item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: fg, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntrinsicPassive extends SingleChildRenderObjectWidget {
  const _IntrinsicPassive({required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderIntrinsicPassive();
}

class _RenderIntrinsicPassive extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;
}

