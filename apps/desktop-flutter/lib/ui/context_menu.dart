import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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
          Positioned(
            left: globalPos.dx,
            top: globalPos.dy,
            child: AppContextMenu(
              tokens: t,
              sections: sections,
              onDismiss: dismiss,
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
  return completer.future;
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
      // previous section was a [TileChipMenuSection]. The chip rail
      // already paints its own bottom hairline, AND the surface tone
      // shifts from surface2 (rail) to surface1 (next section); two
      // close-spaced horizontal lines on top of that material change
      // reads as a busy double-rule. Letting the surface shift do
      // the delineation keeps the menu feeling architectural rather
      // than ruled-off.
      if (s > 0 && sections[s - 1] is! TileChipMenuSection) {
        children.add(
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
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
        case TileChipMenuSection(:final tiles, :final chips):
          children.add(_TileChipMenuSection(
            tokens: tokens,
            tiles: tiles,
            chips: chips,
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
class TileChipMenuSection extends MenuSection {
  final List<AppContextMenuItem> tiles;
  final List<AppContextMenuItem> chips;
  const TileChipMenuSection({required this.tiles, this.chips = const []});
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
        return Positioned(
          left: anchor.left,
          top: anchor.top,
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
    return (left: left, top: topLeft.dy - 4);
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
    final row = AnimatedContainer(
      duration: context.motion(const Duration(milliseconds: 90)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg),
      child: widget.item.custom != null
          ? widget.item.custom!
          : Row(
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
        hoverEnterRespectingSubmenu();
        // Rows open their submenu on HOVER (vs chips which open on
        // click) — fits the cascading-list-row mental model and lets
        // commit-configuration submenus surface without an extra click.
        if (hasSubmenu) openSubmenu();
      },
      onExit: (_) => hoverExitRespectingSubmenu(),
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
  final VoidCallback onDismiss;
  final VoidCallback? onChanged;

  // Tile geometry — kept in sync with [_ContextMenuTile]'s width and
  // the tile strip's inter-tile spacing so the rail-width cap matches
  // the strip exactly.
  static const double _kTileWidth = 64;
  static const double _kTileSpacing = 4;

  const _TileChipMenuSection({
    required this.tokens,
    required this.tiles,
    required this.chips,
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
              // Cap to tile-strip-plus-horizontal-padding so the menu
              // sizes to (tile strip + 24 horizontal margin) and the
              // rail then fills that width edge-to-edge. Without the
              // cap, the rail's intrinsic max would dominate the
              // menu's IntrinsicWidth solver. With it, menu width =
              // tile strip width + 24 = 224 px for a 3-tile strip,
              // and the rail visually flows to the menu's edges.
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

/// The chip rail rendered as a real mosaic — equal-width cells laid
/// back-to-back inside one continuous inset surface, with jagged
/// per-open seams between adjacent cells. The inset uses
/// [AppTokens.surface2] (one tone deeper than the menu's `surface1`)
/// so the rail reads as recessed into the menu chrome rather than
/// floating above it. Cells are pure rectangles in their own layout
/// (so hover wash, hit-testing, and submenu anchors stay predictable);
/// the irregular tile-edge feel comes from a [_JaggedSeamPainter]
/// drawn on top, with each seam jittered ±10 % of its cell's width
/// from the nominal split. Seams are seeded once at [initState] so
/// they're stable while the menu is open and fresh on the next.
///
/// Width is capped to the tile strip's width via [maxWidth] (the
/// caller knows it). Without the cap, [Row]'s child sum would
/// dominate the menu's IntrinsicWidth solver and push it past the
/// tile strip.
class _ChipRailMosaic extends StatefulWidget {
  final AppTokens tokens;
  final List<AppContextMenuItem> chips;
  final double maxWidth;
  final VoidCallback onDismiss;
  final VoidCallback? onChanged;

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

/// One crack between two cells of the mosaic. Geometry is pre-rolled
/// in normalized space so paint stays cheap; the painter scales it to
/// the rail's actual size at draw time.
///
/// Each seam carries its own width and alpha multiplier so individual
/// cracks read as having different "violence" — a real shattered
/// surface has dominant fractures and quieter satellites, not a
/// uniform set of identical lines. [segmentWidthScales] lengths is
/// `vertices.length - 1`, and each entry scales the base stroke width
/// for that segment so a single crack thickens and thins along its
/// length the way a real fracture does.
class _MosaicSeam {
  /// Vertices in normalized space: dx in [-1..1] (sign + magnitude of
  /// the bleed beyond the nominal cell boundary), dy in [0..1] (top
  /// to bottom of the rail).
  final List<Offset> vertices;
  /// Per-seam stroke-width multiplier: 0.6..1.4 of the base.
  final double widthScale;
  /// Per-seam alpha multiplier: 0.7..1.3 of the base.
  final double alphaScale;
  /// Per-segment stroke-width multiplier (length = vertices - 1).
  /// Lets a single crack thicken in the middle, thin at the ends, etc.
  final List<double> segmentWidthScales;

  const _MosaicSeam({
    required this.vertices,
    required this.widthScale,
    required this.alphaScale,
    required this.segmentWidthScales,
  });
}

class _ChipRailMosaicState extends State<_ChipRailMosaic> {
  /// Pre-rolled cracks between each adjacent pair of cells, seeded
  /// once at [initState] so they stay still while the menu's open and
  /// reroll fresh on the next open (every menu open builds a fresh
  /// State).
  late final List<_MosaicSeam> _seams;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    final boundaryCount = math.max(0, widget.chips.length - 1);
    _seams = List.generate(boundaryCount, (_) => _generateSeam(rng));
  }

  /// Builds one shattered crack. Variation everywhere — segment
  /// count, vertex spacing, jitter amplitude, occasional big-lurch
  /// vertices — so no two seams look the same and the rail reads as
  /// shattered rather than patterned.
  static _MosaicSeam _generateSeam(math.Random rng) {
    // 4..8 segments → 5..9 vertices. Variable count is half the
    // anti-pattern signal (the other half is non-uniform spacing).
    final segments = 4 + rng.nextInt(5);

    // Build vertex y positions — non-uniform: random in [0..1] then
    // sorted top-to-bottom, with the first/last forced to the rail
    // edges so the crack actually divides cells edge-to-edge.
    final ys = <double>[0.0];
    for (var i = 1; i < segments; i++) {
      ys.add(rng.nextDouble());
    }
    ys.add(1.0);
    ys.sort();

    // Per-vertex jitter — most stay within ±0.6 (= 6 % of cell width
    // when the painter scales by 0.10), occasional ~25 % of vertices
    // lurch out to ±1.0 (= 10 %, the user-specified ceiling). The
    // mix creates dominant kinks alongside smaller wobbles.
    final vertices = <Offset>[
      for (final y in ys)
        Offset(
          (rng.nextDouble() * 2.0 - 1.0) *
              (rng.nextDouble() < 0.25 ? 1.0 : 0.6),
          y,
        ),
    ];

    final widthScale = 0.6 + rng.nextDouble() * 0.8; // 0.6..1.4
    final alphaScale = 0.7 + rng.nextDouble() * 0.6; // 0.7..1.3

    // Per-segment width: each segment gets its own thickness
    // multiplier so a single crack varies along its length. Range
    // tightened (0.7..1.3) so a single seam still reads as continuous
    // — too much per-segment variance and the line looks broken into
    // disjoint pieces.
    final segmentWidthScales = List<double>.generate(
      vertices.length - 1,
      (_) => 0.7 + rng.nextDouble() * 0.6,
    );

    return _MosaicSeam(
      vertices: vertices,
      widthScale: widthScale,
      alphaScale: alphaScale,
      segmentWidthScales: segmentWidthScales,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // surface2: one depth below the menu's surface1. Reads as
          // recessed into the menu chrome rather than floating above
          // it. Glassy themes get the live shader's surface2;
          // pixelated themes get a flat fill — material character
          // carries through automatically.
          color: widget.tokens.surface2,
          // Top + bottom hairlines mark the rail as a band carved
          // into the menu chrome — left/right are dropped because the
          // rail goes edge-to-edge of the menu (no side seams). 0.10
          // alpha keeps it ambient on light themes without becoming a
          // hard frame on dark / pixelated.
          border: Border(
            top: BorderSide(
              color: widget.tokens.chromeBorder.withValues(alpha: 0.12),
              width: 0.5,
            ),
            bottom: BorderSide(
              color: widget.tokens.chromeBorder.withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
        ),
        // IntrinsicHeight so all cells share the tallest one's
        // height — Stack needs a definite height for Positioned.fill,
        // and we want seam strokes that reach top to bottom of the
        // rail.
        child: IntrinsicHeight(
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < widget.chips.length; i++)
                    Expanded(
                      child: _MosaicChipCell(
                        tokens: widget.tokens,
                        item: widget.chips[i],
                        onDismiss: widget.onDismiss,
                        onChanged: widget.onChanged,
                      ),
                    ),
                ],
              ),
              if (_seams.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ShatteredSeamPainter(
                        cellCount: widget.chips.length,
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
    final jitterCeiling = cellWidth * 0.10;
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
              Icon(widget.item.icon, size: 12, color: fg),
              const SizedBox(width: 5),
              // Flexible + ellipsis so a cramped rail still renders
              // the icon and a partial label rather than overflowing.
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
              Icon(widget.item.icon, size: 18, color: fg),
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

