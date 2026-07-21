// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_primitives.dart';
import 'motion.dart';
import 'mosaic_seam.dart';

/// One tappable cell of a [MosaicShardBar]. A shard renders an arbitrary
/// [child] inside a mosaic cell whose nominal width is known *before* layout —
/// either measured from text (so a label shard flexes to its content, clamped)
/// or fixed (glyph cells). Keeping widths deterministic lets the bar place the
/// crack seams at their exact weighted fractions rather than an equal grid.
class MosaicShard {
  final Widget child;

  /// Null makes the shard inert (no hover, no cursor, no tap).
  final VoidCallback? onTap;
  final String? tooltip;

  /// Wash colour painted (and crack-clipped) while the shard is hovered or
  /// [active]. Null = no wash. Caller owns the alpha.
  final Color? hoverFill;

  /// Forces the hover wash on regardless of pointer — e.g. while this shard's
  /// flyout/overlay is open.
  final bool active;

  // ---- width spec (exactly one branch is taken by [nominalSize]) ----
  final String? _measureText;
  final TextStyle? _measureStyle;
  final double _chrome;
  final double _minWidth;
  final double _maxWidth;
  final double? _fixedWidth;

  const MosaicShard._({
    required this.child,
    this.onTap,
    this.tooltip,
    this.hoverFill,
    this.active = false,
    String? measureText,
    TextStyle? measureStyle,
    double chrome = 0,
    double minWidth = 0,
    double maxWidth = double.infinity,
    double? fixedWidth,
  })  : _measureText = measureText,
        _measureStyle = measureStyle,
        _chrome = chrome,
        _minWidth = minWidth,
        _maxWidth = maxWidth,
        _fixedWidth = fixedWidth;

  /// A fixed-width shard (glyph / icon cells).
  const MosaicShard.fixed({
    required double width,
    required Widget child,
    VoidCallback? onTap,
    String? tooltip,
    Color? hoverFill,
    bool active = false,
  }) : this._(
          child: child,
          onTap: onTap,
          tooltip: tooltip,
          hoverFill: hoverFill,
          active: active,
          fixedWidth: width,
        );

  /// A text shard whose width is [text] measured in [style] plus [chrome]
  /// (leading icon + inter-gaps + horizontal padding the [child] draws),
  /// clamped to [minWidth]..[maxWidth]. The [child] is the real widget — the
  /// measured text just drives the cell width, exactly how the branch pill
  /// clamps its own width today.
  const MosaicShard.text({
    required String text,
    required TextStyle style,
    required Widget child,
    double chrome = 0,
    double minWidth = 0,
    double maxWidth = double.infinity,
    VoidCallback? onTap,
    String? tooltip,
    Color? hoverFill,
    bool active = false,
  }) : this._(
          child: child,
          onTap: onTap,
          tooltip: tooltip,
          hoverFill: hoverFill,
          active: active,
          measureText: text,
          measureStyle: style,
          chrome: chrome,
          minWidth: minWidth,
          maxWidth: maxWidth,
        );

  /// Nominal content size: `.width` drives the cell layout, `.height` the bar
  /// height. Fixed shards report height 0 and lean on the bar's content floor.
  Size nominalSize(TextScaler scaler) {
    final fw = _fixedWidth;
    if (fw != null) return Size(fw, 0);
    final tp = TextPainter(
      text: TextSpan(text: _measureText, style: _measureStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final size =
        Size((tp.width + _chrome).clamp(_minWidth, _maxWidth), tp.height);
    tp.dispose();
    return size;
  }
}

/// A single pill surface split into weighted [MosaicShard] cells by the app's
/// shattered-mosaic cracks. Built from the shared primitives in
/// `mosaic_seam.dart` (never a fork): one [ShatteredSeamPainter] draws the
/// cracks at the computed seam fractions, and each cell clips its hover wash
/// with a [MosaicCellClipper] so the wash lights up right to the jagged seam.
/// Seams are generated once at mount and held in state — they never reshuffle
/// on rebuild (only when the shard *count* changes).
class MosaicShardBar extends StatefulWidget {
  final List<MosaicShard> shards;

  /// Base fill / border / seam / radius — pass the surrounding control's own
  /// tokens so the bar reads as that control (no bespoke chrome here).
  final Color surfaceColor;
  final Color borderColor;
  final Color seamColor;
  final double borderRadius;

  /// Padding above+below the tallest shard (per side). Height =
  /// max(content, [minContentHeight]) + 2 * [verticalPadding].
  final double verticalPadding;
  final double minContentHeight;

  /// Optional per-shard keys, length == shards.length, attached to each shard's
  /// nominal-width content box so a caller can anchor an overlay under that one
  /// shard (not the whole bar). Index-aligned with [shards].
  final List<Key>? shardKeys;

  const MosaicShardBar({
    super.key,
    required this.shards,
    required this.surfaceColor,
    required this.borderColor,
    required this.seamColor,
    required this.borderRadius,
    this.verticalPadding = 4,
    this.minContentHeight = 0,
    this.shardKeys,
  });

  @override
  State<MosaicShardBar> createState() => _MosaicShardBarState();
}

class _MosaicShardBarState extends State<MosaicShardBar> {
  late List<MosaicSeam> _seams;

  @override
  void initState() {
    super.initState();
    _seams = _buildSeams(widget.shards.length);
  }

  @override
  void didUpdateWidget(MosaicShardBar old) {
    super.didUpdateWidget(old);
    // Only reshuffle cracks when the number of shards changes (a label/count
    // swap must not make the seams shimmer).
    if (old.shards.length != widget.shards.length) {
      _seams = _buildSeams(widget.shards.length);
    }
  }

  List<MosaicSeam> _buildSeams(int n) {
    final rng = math.Random();
    return List.generate(math.max(0, n - 1), (_) => generateMosaicSeam(rng));
  }

  /// Symmetric per-cell jitter, bounded by the narrowest of this cell and its
  /// neighbours, so a hover wash never bleeds across a small neighbour — the
  /// clip-side mirror of the painter's per-seam ceiling rule.
  double _cellJitter(int i, int n, List<double> widths) {
    var m = widths[i];
    if (i > 0) m = math.min(m, widths[i - 1]);
    if (i < n - 1) m = math.min(m, widths[i + 1]);
    return m * kMosaicJitterFrac;
  }

  @override
  Widget build(BuildContext context) {
    final shards = widget.shards;
    final n = shards.length;
    if (n == 0) return const SizedBox.shrink();

    final scaler = MediaQuery.textScalerOf(context);
    final widths = <double>[];
    var contentH = widget.minContentHeight;
    for (final s in shards) {
      final sz = s.nominalSize(scaler);
      widths.add(sz.width);
      if (sz.height > contentH) contentH = sz.height;
    }
    final railH = contentH + widget.verticalPadding * 2;

    final edges = <double>[0];
    for (final w in widths) {
      edges.add(edges.last + w);
    }
    final railW = edges.last;
    final seamFractions = <double>[
      for (var i = 1; i < n; i++) edges[i] / railW,
    ];

    final radius = widget.borderRadius;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.surfaceColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      // Border rides above the clipped cells (matching [SplitPillButton]) so a
      // hovered wash meets the rounded edge with no hairline showing through.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: widget.borderColor),
      ),
      child: SizedBox(
        width: railW,
        height: railH,
        child: Stack(
          children: [
            for (var i = 0; i < n; i++)
              _cell(i, n, widths, edges, railW),
            if (_seams.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: ShatteredSeamPainter(
                      cellCount: n,
                      seams: _seams,
                      baseColor: widget.seamColor,
                      baseAlpha: 0.34,
                      baseWidth: 0.7,
                      seamFractions: seamFractions,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    int i,
    int n,
    List<double> widths,
    List<double> edges,
    double railW,
  ) {
    final isFirst = i == 0;
    final isLast = i == n - 1;
    final j = _cellJitter(i, n, widths);
    final left = isFirst ? 0.0 : edges[i] - j;
    final right = isLast ? railW : edges[i + 1] + j;
    final leftNom = isFirst ? 0.0 : j;
    final rightNom = leftNom + widths[i];
    final boxW = right - left;
    return Positioned(
      left: left,
      width: boxW,
      top: 0,
      bottom: 0,
      child: ClipPath(
        clipper: MosaicCellClipper(
          leftNominal: leftNom,
          rightNominal: rightNom,
          jitter: j,
          leftSeam: i > 0 ? _seams[i - 1] : null,
          rightSeam: i < n - 1 ? _seams[i] : null,
        ),
        child: _ShardCell(
          shard: widget.shards[i],
          nominalWidth: widths[i],
          // Centre content in the NOMINAL cell (not the ±jitter-extended box)
          // so a first/last label never drifts toward the seam.
          padLeft: leftNom,
          padRight: boxW - rightNom,
          contentKey: widget.shardKeys != null ? widget.shardKeys![i] : null,
        ),
      ),
    );
  }
}

class _ShardCell extends StatefulWidget {
  final MosaicShard shard;
  final double nominalWidth;
  final double padLeft;
  final double padRight;
  final Key? contentKey;

  const _ShardCell({
    required this.shard,
    required this.nominalWidth,
    required this.padLeft,
    required this.padRight,
    this.contentKey,
  });

  @override
  State<_ShardCell> createState() => _ShardCellState();
}

class _ShardCellState extends State<_ShardCell> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.shard;
    final interactive = s.onTap != null;
    final active = s.active || (_hov && interactive);
    final wash =
        (active && s.hoverFill != null) ? s.hoverFill! : const Color(0x00000000);

    Widget content = AnimatedContainer(
      duration: context.motion(AppMotion.snap),
      curve: AppMotion.snapCurve,
      color: wash,
      child: Padding(
        padding: EdgeInsets.only(left: widget.padLeft, right: widget.padRight),
        child: Center(
          child: SizedBox(
            width: widget.nominalWidth,
            child: KeyedSubtree(key: widget.contentKey, child: s.child),
          ),
        ),
      ),
    );

    if (s.tooltip != null && s.tooltip!.isNotEmpty) {
      content = Tooltip(message: s.tooltip!, child: content);
    }

    return MouseRegion(
      cursor:
          interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: interactive ? (_) => setState(() => _hov = true) : null,
      onExit: interactive ? (_) => setState(() => _hov = false) : null,
      child: GestureDetector(
        onTap: s.onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }
}
