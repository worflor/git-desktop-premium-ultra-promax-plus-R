import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/dtos.dart';
import '../../backend/file_lifecycle.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import 'commit_seismograph_layout.dart';

/// Replaces the long flat list of files in the commit-detail panel with
/// a recursively-zoomable strip: tracks per directory, segments per file
/// inside, sized by churn share. Drill into any subdir or overflow tile
/// to recompose the same view at a deeper focus. No diff opening
/// happens here — this view is purely the commit's *shape*.
class CommitSeismograph extends StatefulWidget {
  final CommitDetailData detail;
  final AppTokens tokens;
  final Set<String> dirtyPaths;
  final String repoPath;

  /// Open the diff for a single file in the parent panel — the
  /// seismograph itself doesn't host the diff (that would cramp it
  /// inside the strip's chrome). Bubbles up to the history page,
  /// which swaps the entire detail pane for the existing DiffShell.
  final ValueChanged<String> onOpenFile;

  /// Open the entire commit's multi-file diff in the parent pane.
  /// Wired to the "all" breadcrumb crumb (when at root focus) and
  /// to the file-count / +/- chips above the seismograph.
  final VoidCallback onOpenAllFiles;

  /// Per-file lifecycle classification (promotion × decay) derived
  /// from the engine's whole-repo touch history. When provided, the
  /// seismograph paints subtle accents on leaf segments — a top
  /// underline whose color encodes promotion (canonical = bright
  /// accent, reinforced = muted accent) and a thin baseline marker
  /// for stale files. The two channels are independent; a file can
  /// be canonical AND stale (deep infrastructure that hasn't moved).
  final Map<String, FileLifecycle>? lifecycles;

  const CommitSeismograph({
    super.key,
    required this.detail,
    required this.tokens,
    required this.dirtyPaths,
    required this.repoPath,
    required this.onOpenFile,
    required this.onOpenAllFiles,
    this.lifecycles,
  });

  @override
  State<CommitSeismograph> createState() => _CommitSeismographState();
}

/// Snapshot of what the cursor is currently over. Lifted out of the
/// segment widgets so the inspector strip can render it in a fixed
/// location instead of as a floating tooltip — tooltips that overlap
/// the bars themselves fight the user's hover gestures.
class _HoverInfo {
  final String label;
  final int additions;
  final int deletions;
  final int fileCount;
  final bool isDrillable;
  final bool isLeaf;
  const _HoverInfo({
    required this.label,
    required this.additions,
    required this.deletions,
    required this.fileCount,
    required this.isDrillable,
    required this.isLeaf,
  });
}

class _CommitSeismographState extends State<CommitSeismograph>
    with SingleTickerProviderStateMixin {
  List<String> _focus = const [];
  late SeismographNode _root;
  late FocusNode _focusNode;
  _HoverInfo? _hover;

  // Wake-up animation: bars rise from baseline, staggered left-to-right.
  // Restarts on hash change and on focus drill so each "view" wakes.
  late AnimationController _wakeCtrl;

  // Path filter (toggled by `/`). Non-matching segments dim in place;
  // no relayout, so geometry stays stable while you type.
  bool _filterVisible = false;
  String _filterText = '';
  late TextEditingController _filterCtrl;
  late FocusNode _filterFocus;

  @override
  void initState() {
    super.initState();
    _root = buildSeismographTree(widget.detail.files);
    _focusNode = FocusNode(debugLabel: 'CommitSeismograph');
    _wakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..forward();
    _filterCtrl = TextEditingController();
    _filterFocus = FocusNode(debugLabel: 'CommitSeismographFilter');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _wakeCtrl.dispose();
    _filterCtrl.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CommitSeismograph oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hashChanged =
        oldWidget.detail.commitHash != widget.detail.commitHash;
    if (hashChanged) {
      _root = buildSeismographTree(widget.detail.files);
      _focus = const [];
      _filterText = '';
      _filterCtrl.clear();
      _filterVisible = false;
      // Scan-mode gate: if the user is arrow-keying through commits
      // faster than the wake animation completes, snap straight to the
      // settled state instead of restarting. Lets the panel feel
      // cinematic on deliberate clicks AND instant during a bisect
      // hunt — self-tuning, no thresholds.
      if (_wakeCtrl.isAnimating) {
        _wakeCtrl.value = 1.0;
      } else {
        _wakeCtrl.forward(from: 0);
      }
    } else if (!identical(oldWidget.detail.files, widget.detail.files)) {
      _root = buildSeismographTree(widget.detail.files);
    }
  }

  void _setFocus(List<String> path) {
    if (listEquals(path, _focus)) return;
    setState(() {
      _focus = List.unmodifiable(path);
      _hover = null;
    });
    _wakeCtrl.forward(from: 0);
  }

  void _setHover(_HoverInfo? info) {
    if (info == null && _hover == null) return;
    setState(() => _hover = info);
  }

  void _drillUp() {
    if (_filterVisible) {
      _toggleFilter(false);
      return;
    }
    if (_focus.isEmpty) return;
    _setFocus(_focus.sublist(0, _focus.length - 1));
  }

  void _toggleFilter(bool show) {
    setState(() {
      _filterVisible = show;
      if (!show) {
        _filterText = '';
        _filterCtrl.clear();
      }
    });
    if (show) {
      _filterFocus.requestFocus();
    }
  }

  void _openLeaf(List<String> path) {
    widget.onOpenFile(path.join('/'));
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape ||
        e.logicalKey == LogicalKeyboardKey.backspace) {
      if (!_filterVisible && _focus.isEmpty) {
        return KeyEventResult.ignored;
      }
      _drillUp();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.slash && !_filterVisible) {
      _toggleFilter(true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return LayoutBuilder(builder: (context, cons) {
      final width = cons.maxWidth;
      // Panel height grows with width (responsive aspect), bounded so it
      // never dominates the scroll view.
      final height = (width * 0.52).clamp(220.0, 460.0);

      // Sizes below derive from text metrics measured at these styles.
      final trackLabelStyle = TextStyle(
        color: t.textNormal, fontSize: 11, fontFamily: 'JetBrainsMono',
        fontWeight: FontWeight.w600, height: 1.15,
      );
      final segLabelStyle = TextStyle(
        color: t.textNormal, fontSize: 10, fontFamily: 'JetBrainsMono',
        height: 1.1,
      );
      final segLabelHeight = _measureHeight('Mg', segLabelStyle);
      final trackLabelHeight = _measureHeight('Mg', trackLabelStyle);
      final glyphW = _measureWidth('M', segLabelStyle);

      // A track must fit its header (label + sub-line) plus the segment
      // label band plus a ridgeline area at least one label-height tall.
      final minTrackPx = trackLabelHeight * 2 + segLabelHeight * 2 + 6;
      // A segment must be wide enough to show a counter like "+12".
      final minSegmentPx = glyphW * 3;
      // A segment can show a real label only when it fits a meaningful
      // chunk of one — derived from a representative basename width.
      final minLabelSegmentPx = _measureWidth('module.dart', segLabelStyle);

      // Header column: wide enough for a typical hoisted label, capped.
      final headerWidth = _measureWidth(
              'apps/desktop-flutter/lib/', trackLabelStyle)
          .clamp(120.0, width * 0.32);
      final stripWidth = width - headerWidth - 12;

      final layout = layoutSeismograph(
        root: _root,
        c: SeismographConstraints(
          width: stripWidth, height: height,
          minTrackPx: minTrackPx, minSegmentPx: minSegmentPx,
        ),
        focusPath: _focus,
      );

      // The single largest-churn segment in the entire visible layout
      // gets a sharp accent — the "one signal" the panel commits to.
      SeismographSegment? hero;
      for (final tr in layout.tracks) {
        for (final s in tr.segments) {
          if (s.isLeaf && (hero == null || s.churn > hero.churn)) hero = s;
        }
      }

      // Idle inspector content — what the focus subtree looks like as a
      // whole, so the strip is informative when nothing's hovered.
      final focusNode = _resolveFocusNode(_root, _focus);
      final focusSummary = _FocusSummary(
        fileCount: focusNode.leafCount,
        directSubdirs:
            focusNode.children.values.where((n) => !n.isLeaf).length,
        additions: focusNode.additions,
        deletions: focusNode.deletions,
      );

      return Focus(
        focusNode: _focusNode,
        autofocus: false,
        onKeyEvent: _onKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Breadcrumb(
              focusPath: layout.focusPath,
              tokens: t,
              onTap: _setFocus,
            ),
            const SizedBox(height: 6),
            _InspectorStrip(
              tokens: t,
              hover: _hover,
              style: segLabelStyle,
              idleSummary: focusSummary,
            ),
            const SizedBox(height: 6),
            if (_filterVisible)
              _FilterBar(
                tokens: t,
                style: segLabelStyle,
                controller: _filterCtrl,
                focusNode: _filterFocus,
                onChanged: (s) => setState(() => _filterText = s),
                onClose: () => _toggleFilter(false),
              ),
            if (_filterVisible) const SizedBox(height: 6),
            if (layout.singleFile != null)
              _SingleFileRow(
                segment: layout.singleFile!,
                tokens: t,
                isDirty: widget.dirtyPaths.contains(
                    layout.singleFile!.path.join('/')),
                onTap: () => _openLeaf(layout.singleFile!.path),
              )
            else
              AnimatedBuilder(
                animation: _focusNode,
                builder: (context, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.chromeAccent.withValues(alpha: 0.025),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? t.focusRing
                          : t.chromeBorder.withValues(alpha: 0.35),
                      width: _focusNode.hasFocus ? 1 : 0.5,
                    ),
                  ),
                  child: child,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 6),
                  child: SizedBox(
                    width: width - 12,
                    height: height,
                    child: AnimatedSwitcher(
                      duration: context.motion(
                          const Duration(milliseconds: 120)),
                      reverseDuration: context.motion(
                          const Duration(milliseconds: 80)),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: KeyedSubtree(
                        key: ValueKey(layout.focusPath.join('/')),
                        child: _SeismographBody(
                          tokens: t,
                          tracks: layout.tracks,
                          heroPath: hero?.path,
                          headerWidth: headerWidth,
                          stripWidth: stripWidth - 12,
                          trackLabelStyle: trackLabelStyle,
                          segLabelStyle: segLabelStyle,
                          segLabelHeight: segLabelHeight,
                          minLabelSegmentPx: minLabelSegmentPx,
                          dirtyPaths: widget.dirtyPaths,
                          lifecycles: widget.lifecycles,
                          wake: _wakeCtrl,
                          filterText: _filterText.toLowerCase(),
                          onDrillTo: (p) {
                            _focusNode.requestFocus();
                            _setFocus(p);
                          },
                          onOpenLeaf: _openLeaf,
                          onHover: _setHover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// Walks the dir tree to the focused node so the inspector idle summary
/// can describe the subtree as a whole.
SeismographNode _resolveFocusNode(SeismographNode root, List<String> path) {
  var cur = root;
  for (final seg in path) {
    final next = cur.children[seg];
    if (next == null) break;
    cur = next;
  }
  return cur;
}

class _FocusSummary {
  final int fileCount;
  final int directSubdirs;
  final int additions;
  final int deletions;
  const _FocusSummary({
    required this.fileCount,
    required this.directSubdirs,
    required this.additions,
    required this.deletions,
  });
}

// ── Text-measurement cache ──────────────────────────────────────
//
// [_measureWidth] / [_measureHeight] are called five times per
// CommitSeismograph build from inside a LayoutBuilder. Every hover,
// filter keystroke, or drill triggers another build, and each call
// previously allocated a fresh TextPainter + ran `.layout()`. The
// probe strings and the layout-affecting TextStyle fields
// (fontSize / fontFamily / height) are all stable across rebuilds
// — so cache the result per (text, style-layout-signature).
//
// Colour and weight can affect rendering but not text metrics, so
// they stay out of the key. On a theme change the fontFamily or
// fontSize may change, which moves the key and invalidates the
// prior entry implicitly without explicit invalidation.
final Map<String, double> _measureWidthCache = <String, double>{};
final Map<String, double> _measureHeightCache = <String, double>{};

String _measureKey(String text, TextStyle s) =>
    '$text|${s.fontSize}|${s.fontFamily}|${s.fontWeight?.value}|'
    '${s.fontStyle?.index}|${s.height}|${s.letterSpacing}';

double _measureWidth(String text, TextStyle s) {
  final key = _measureKey(text, s);
  final hit = _measureWidthCache[key];
  if (hit != null) return hit;
  final tp = TextPainter(
    text: TextSpan(text: text, style: s),
    textDirection: TextDirection.ltr,
  )..layout();
  return _measureWidthCache[key] = tp.width;
}

double _measureHeight(String text, TextStyle s) {
  final key = _measureKey(text, s);
  final hit = _measureHeightCache[key];
  if (hit != null) return hit;
  final tp = TextPainter(
    text: TextSpan(text: text, style: s),
    textDirection: TextDirection.ltr,
  )..layout();
  return _measureHeightCache[key] = tp.height;
}


class _Breadcrumb extends StatelessWidget {
  final List<String> focusPath;
  final AppTokens tokens;
  final ValueChanged<List<String>> onTap;

  const _Breadcrumb({
    required this.focusPath,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final crumbs = <Widget>[
      _crumb('all', () => onTap(const []), isLast: focusPath.isEmpty, t: t),
    ];
    for (var i = 0; i < focusPath.length; i++) {
      crumbs.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text('›',
            style: TextStyle(
                color: t.textFaint, fontSize: 11, fontFamily: 'JetBrainsMono')),
      ));
      final upto = focusPath.sublist(0, i + 1);
      crumbs.add(_crumb(focusPath[i], () => onTap(upto),
          isLast: i == focusPath.length - 1, t: t));
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: crumbs);
  }

  Widget _crumb(String label, VoidCallback onTap,
      {required bool isLast,
      required AppTokens t,
      bool accentWhenAction = false}) {
    return Semantics(
      button: !isLast,
      label: isLast
          ? 'Current focus: $label'
          : (accentWhenAction
              ? 'View all changes in this commit'
              : 'Drill up to $label'),
      child: MouseRegion(
        cursor: isLast ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: isLast ? null : onTap,
          child: Text(
            label,
            style: TextStyle(
              color: isLast
                  ? t.textStrong
                  : (accentWhenAction ? t.accentBright : t.textMuted),
              fontSize: 11,
              fontFamily: 'JetBrainsMono',
              fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}


class _SeismographBody extends StatelessWidget {
  final AppTokens tokens;
  final List<SeismographTrack> tracks;
  final List<String>? heroPath;
  final double headerWidth;
  final double stripWidth;
  final TextStyle trackLabelStyle;
  final TextStyle segLabelStyle;
  final double segLabelHeight;
  final double minLabelSegmentPx;
  final Set<String> dirtyPaths;
  final Map<String, FileLifecycle>? lifecycles;
  final ValueChanged<List<String>> onDrillTo;
  final ValueChanged<List<String>> onOpenLeaf;
  final ValueChanged<_HoverInfo?> onHover;
  final Animation<double> wake;
  final String filterText;

  const _SeismographBody({
    required this.tokens,
    required this.tracks,
    required this.heroPath,
    required this.headerWidth,
    required this.stripWidth,
    required this.trackLabelStyle,
    required this.segLabelStyle,
    required this.segLabelHeight,
    required this.minLabelSegmentPx,
    required this.dirtyPaths,
    required this.lifecycles,
    required this.onDrillTo,
    required this.onOpenLeaf,
    required this.onHover,
    required this.wake,
    required this.filterText,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Stack(children: [
      // Zebra-stripe each track band so the eye can scan rows easily;
      // also paints a hairline at every track's bottom edge.
      Positioned.fill(
        child: CustomPaint(
          painter: _GridPainter(
            tracks: tracks,
            stripeColor: t.chromeAccent.withValues(alpha: 0.04),
            lineColor: t.chromeBorder,
            headerWidth: headerWidth,
          ),
        ),
      ),
      for (final track in tracks)
        Positioned(
          left: 0, top: track.top, width: headerWidth, height: track.height,
          child: _TrackHeader(
            track: track, tokens: t, style: trackLabelStyle,
            onTap: () => onDrillTo(track.path),
          ),
        ),
      for (var i = 0; i < tracks.length; i++)
        Positioned(
          left: headerWidth + 12, top: tracks[i].top,
          width: stripWidth, height: tracks[i].height,
          child: _Track(
            track: tracks[i],
            trackIndex: i,
            trackCount: tracks.length,
            tokens: t,
            segLabelStyle: segLabelStyle,
            segLabelHeight: segLabelHeight,
            minLabelSegmentPx: minLabelSegmentPx,
            heroPath: heroPath,
            dirtyPaths: dirtyPaths,
            lifecycles: lifecycles,
            onDrillTo: onDrillTo,
            onOpenLeaf: onOpenLeaf,
            onHover: onHover,
            wake: wake,
            filterText: filterText,
          ),
        ),
    ]);
  }
}

class _GridPainter extends CustomPainter {
  final List<SeismographTrack> tracks;
  final Color stripeColor;
  final Color lineColor;
  final double headerWidth;

  _GridPainter({
    required this.tracks,
    required this.stripeColor,
    required this.lineColor,
    required this.headerWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stripe = Paint()..color = stripeColor;
    final line = Paint()
      ..color = lineColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      if (i.isOdd) {
        canvas.drawRect(Rect.fromLTWH(0, t.top, size.width, t.height), stripe);
      }
      final y = t.top + t.height;
      // Hairline only spans the strip region (not the header column).
      canvas.drawLine(Offset(headerWidth, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.tracks != tracks ||
      old.stripeColor != stripeColor ||
      old.lineColor != lineColor ||
      old.headerWidth != headerWidth;
}


class _TrackHeader extends StatefulWidget {
  final SeismographTrack track;
  final AppTokens tokens;
  final TextStyle style;
  final VoidCallback onTap;

  const _TrackHeader({
    required this.track,
    required this.tokens,
    required this.style,
    required this.onTap,
  });

  @override
  State<_TrackHeader> createState() => _TrackHeaderState();
}

class _TrackHeaderState extends State<_TrackHeader> {
  bool _hovered = false;

  // Aggregates are pure functions of `widget.track` but the track
  // only changes when the layout actually reassigns it. Hover
  // toggles churn build() repeatedly without touching the track,
  // so memoise the three folds and refresh only when the track
  // reference changes. Cheap initialisers; identity-compared.
  SeismographTrack? _aggFor;
  int _fileCount = 0;
  int _adds = 0;
  int _dels = 0;

  void _ensureAggregates(SeismographTrack track) {
    if (identical(_aggFor, track)) return;
    var files = 0;
    var adds = 0;
    var dels = 0;
    for (final s in track.segments) {
      files += s.containedFileCount;
      adds += s.additions;
      dels += s.deletions;
    }
    _fileCount = files;
    _adds = adds;
    _dels = dels;
    _aggFor = track;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final track = widget.track;
    _ensureAggregates(track);
    final fileCount = _fileCount;
    final adds = _adds;
    final dels = _dels;
    final isOverflow = track.isOverflowBucket;
    final canDrill = !isOverflow && track.path.isNotEmpty;
    return MouseRegion(
      cursor: canDrill ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: canDrill ? widget.onTap : null,
        child: Padding(
          // Anchor near the top so the label sits above the ridgeline
          // bars rather than floating in dead space for tall tracks.
          padding: const EdgeInsets.only(right: 6, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Right-aligned: chevron + label, so the eye reads
              // "›" (drill-in cue) just before the dir name. The
              // chevron only appears for drillable tracks; track
              // headers without it read as informational.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canDrill)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '›',
                        style: widget.style.copyWith(
                          color: _hovered
                              ? t.accentBright
                              : t.textFaint.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      track.label,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: widget.style.copyWith(
                        color: isOverflow
                            ? t.textFaint
                            : (_hovered && canDrill
                                ? t.accentBright
                                : t.textNormal),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$fileCount file${fileCount == 1 ? "" : "s"}  '
                '+$adds  -$dels',
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 9,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _Track extends StatelessWidget {
  final SeismographTrack track;
  final int trackIndex;
  final int trackCount;
  final AppTokens tokens;
  final TextStyle segLabelStyle;
  final double segLabelHeight;
  final double minLabelSegmentPx;
  final List<String>? heroPath;
  final Set<String> dirtyPaths;
  final Map<String, FileLifecycle>? lifecycles;
  final ValueChanged<List<String>> onDrillTo;
  final ValueChanged<List<String>> onOpenLeaf;
  final ValueChanged<_HoverInfo?> onHover;
  final Animation<double> wake;
  final String filterText;

  const _Track({
    required this.track,
    required this.trackIndex,
    required this.trackCount,
    required this.tokens,
    required this.segLabelStyle,
    required this.segLabelHeight,
    required this.minLabelSegmentPx,
    required this.heroPath,
    required this.dirtyPaths,
    required this.lifecycles,
    required this.onDrillTo,
    required this.onOpenLeaf,
    required this.onHover,
    required this.wake,
    required this.filterText,
  });

  bool _matchesFilter(SeismographSegment s) {
    if (filterText.isEmpty) return true;
    return s.pathKeyLower.contains(filterText) ||
        s.label.toLowerCase().contains(filterText);
  }

  @override
  Widget build(BuildContext context) {
    if (track.segments.isEmpty) return const SizedBox.shrink();
    // Direct loop — previous `.map().fold()` chain allocated a
    // MappedIterable wrapper + two closure objects per build, which
    // fires on every `wake` tick, hover, and filter keystroke. The
    // loop stays within SMI integer range for realistic churn
    // values, so the whole thing runs without heap traffic.
    var maxChurn = 1;
    for (final s in track.segments) {
      if (s.churn > maxChurn) maxChurn = s.churn;
    }
    if (maxChurn > 1 << 30) maxChurn = 1 << 30;

    final labelBandPx = segLabelHeight + 2;
    return ClipRect(
      child: Stack(children: [
        // Continuous ridgeline polyline across segment peaks. The
        // metaphor finally seen, not just named — Catmull-Rom smoothed
        // so it reads as a needle's trace, not a bar-chart staircase.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: wake,
            builder: (_, __) => CustomPaint(
              painter: _RidgelinePainter(
                segments: track.segments,
                maxChurn: maxChurn,
                trackHeight: track.height,
                labelBandPx: labelBandPx,
                color: tokens.textNormal,
                wakeProgress: _trackWakeProgress(wake.value),
              ),
            ),
          ),
        ),
        for (final seg in track.segments)
          Positioned(
            left: seg.left, top: 0,
            width: seg.width, height: track.height,
            child: _Segment(
              track: track,
              segment: seg,
              tokens: tokens,
              labelStyle: segLabelStyle,
              labelBandPx: labelBandPx,
              showLabel: seg.width >= minLabelSegmentPx,
              maxChurn: maxChurn,
              isDirty: seg.isLeaf && dirtyPaths.contains(seg.pathKey),
              isHero: seg.isLeaf &&
                  heroPath != null &&
                  listEquals(seg.path, heroPath),
              lifecycle: (seg.isLeaf && lifecycles != null)
                  ? lifecycles![seg.pathKey]
                  : null,
              dimmed: !_matchesFilter(seg),
              wake: wake,
              wakeProgressFor: _trackWakeProgress,
              onTap: seg.isLeaf
                  // Click a leaf → open its diff inline.
                  ? () => onOpenLeaf(seg.path)
                  // Non-leaf, drillable → drill in.
                  : (seg.isDrillable ? () => onDrillTo(seg.path) : null),
              onHover: (entered) {
                if (!entered) {
                  onHover(null);
                  return;
                }
                onHover(_HoverInfo(
                  label: seg.isLeaf
                      ? seg.pathKey
                      : (seg.isDrillable
                          ? '${seg.containedFileCount} files in '
                              '${seg.pathKey}/'
                          : '${seg.containedFileCount} more files'),
                  additions: seg.additions,
                  deletions: seg.deletions,
                  fileCount: seg.containedFileCount,
                  isDrillable: seg.isDrillable,
                  isLeaf: seg.isLeaf,
                ));
              },
            ),
          ),
      ]),
    );
  }

  /// Each track wakes a touch later than the one above so the panel
  /// "rolls in" — like a seismograph drum starting up. Track i's local
  /// progress maps the global wake [0,1] through a per-track window.
  double _trackWakeProgress(double global) {
    if (trackCount <= 1) return global.clamp(0.0, 1.0);
    final start = (trackIndex / trackCount) * 0.4;
    final end = start + 0.6;
    return ((global - start) / (end - start)).clamp(0.0, 1.0);
  }
}

/// Draws a single smoothed polyline across the *peaks* of every segment
/// in a track. The bars do the quantitative work; this line gives the
/// row a continuous "trace" — the visual metaphor that makes the panel
/// a seismograph rather than a bar chart.
class _RidgelinePainter extends CustomPainter {
  final List<SeismographSegment> segments;
  final int maxChurn;
  final double trackHeight;
  final double labelBandPx;
  final Color color;
  final double wakeProgress;

  _RidgelinePainter({
    required this.segments,
    required this.maxChurn,
    required this.trackHeight,
    required this.labelBandPx,
    required this.color,
    required this.wakeProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.length < 2 || wakeProgress <= 0.001) return;
    final ridgeArea = (size.height - labelBandPx).clamp(0.0, double.infinity);
    final pts = <Offset>[];
    for (final s in segments) {
      final ratio = s.churn / maxChurn;
      final barH = ridgeArea * ratio * wakeProgress;
      final y = (size.height - barH).clamp(0.0, size.height);
      final x = s.left + s.width / 2;
      pts.add(Offset(x, y));
    }
    final path = _catmullRom(pts);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.35 * wakeProgress);
    canvas.drawPath(path, paint);
  }

  /// Centripetal Catmull-Rom approximated as a sequence of cubic
  /// Béziers. For n points, generates n-1 curves; tangents at endpoints
  /// are reflected so the trace doesn't snap.
  Path _catmullRom(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    if (p.length == 2) {
      path.lineTo(p.last.dx, p.last.dy);
      return path;
    }
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = i == 0 ? p[0] : p[i - 1];
      final p1 = p[i];
      final p2 = p[i + 1];
      final p3 = i + 2 < p.length ? p[i + 2] : p[i + 1];
      final c1 = Offset(
          p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(
          p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_RidgelinePainter old) =>
      old.segments != segments ||
      old.maxChurn != maxChurn ||
      old.trackHeight != trackHeight ||
      old.color != color ||
      old.wakeProgress != wakeProgress;
}


class _Segment extends StatefulWidget {
  final SeismographTrack track;
  final SeismographSegment segment;
  final AppTokens tokens;
  final TextStyle labelStyle;
  final double labelBandPx;
  final bool showLabel;
  final int maxChurn;
  final bool isDirty;
  final bool isHero;
  final bool dimmed;
  final FileLifecycle? lifecycle;
  final VoidCallback? onTap;
  final ValueChanged<bool> onHover;
  final Animation<double> wake;
  final double Function(double) wakeProgressFor;

  const _Segment({
    required this.track,
    required this.segment,
    required this.tokens,
    required this.labelStyle,
    required this.labelBandPx,
    required this.showLabel,
    required this.maxChurn,
    required this.isDirty,
    required this.isHero,
    required this.dimmed,
    required this.lifecycle,
    required this.onTap,
    required this.onHover,
    required this.wake,
    required this.wakeProgressFor,
  });

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  /// What the bar's add/del split tells the eye:
  ///   all-`stateAdded`   → fresh code (A, or M heavy with additions)
  ///   all-`stateDeleted` → demolition (D, or M heavy with deletions)
  ///   mixed              → reshape — the ratio narrates the character
  ///   hairline           → pure rename / mode-only / typechange
  /// All colors come from theme tokens; nothing is hard-coded.
  ({double addShare, double delShare}) _splitShares() {
    final f = widget.segment.file;
    if (f != null) {
      final total = f.additions + f.deletions;
      if (total == 0) return (addShare: 0, delShare: 0);
      return (
        addShare: f.additions / total,
        delShare: f.deletions / total,
      );
    }
    // Container/fold segment: aggregate across what it represents.
    final seg = widget.segment;
    final total = seg.additions + seg.deletions;
    if (total == 0) return (addShare: 0, delShare: 0);
    return (
      addShare: seg.additions / total,
      delShare: seg.deletions / total,
    );
  }

  /// Optional corner glyph for change types that have no add/del story
  /// (renames, copies, typechanges, conflicts). Returns null for the
  /// usual A/M/D where the bar split already speaks.
  ({Color color, String label})? _typeNotch() {
    final t = widget.tokens;
    final f = widget.segment.file;
    if (f == null) return null;
    switch (f.changeType) {
      case 'R':
        return (color: t.accentBright, label: 'R');
      case 'C':
        return (color: t.accentBright, label: 'C');
      case 'T':
        return (color: t.stateModified, label: 'T');
      case 'U':
        return (color: t.stateConflicted, label: 'U');
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final seg = widget.segment;
    final ratio = seg.churn / widget.maxChurn;
    final labelBandPx = widget.showLabel ? widget.labelBandPx : 0.0;
    final shares = _splitShares();
    final notch = _typeNotch();
    final hoverWash =
        widget.isHero ? t.accentBright : t.textNormal;

    final cursor = widget.onTap != null
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic;

    final dimAlpha = widget.dimmed ? 0.18 : 1.0;

    // Build a screen-reader narration that doesn't rely on color.
    final semanticLabel = seg.isLeaf
        ? '${seg.pathKey}, '
            '${seg.additions} added, ${seg.deletions} deleted'
            '${widget.isHero ? ', largest change in this view' : ''}'
            '${notch?.label == 'U' ? ', conflicted' : ''}'
            '${widget.isDirty ? ', dirty' : ''}'
        : '${seg.containedFileCount} files, '
            '${seg.additions} added, ${seg.deletions} deleted'
            '${seg.isDrillable ? ', drill in' : ''}';

    return Semantics(
      label: semanticLabel,
      button: widget.onTap != null,
      child: MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover(true);
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onHover(false);
      },
      cursor: cursor,
      child: GestureDetector(
        onTap: widget.onTap,
        child: DecoratedBox(
          // Hover wash is instant — no AnimatedContainer. Pro reviewer
          // flagged the per-segment 120ms duration as a flicker source
          // when the mouse scans laterally across many segments.
          decoration: BoxDecoration(
            color: _hovered
                ? hoverWash.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: LayoutBuilder(builder: (context, cons) {
              final innerH = cons.maxHeight;
              final ridgeAreaPx =
                  (innerH - labelBandPx).clamp(0.0, double.infinity);
              return AnimatedBuilder(
                animation: widget.wake,
                builder: (context, _) {
                  final wp = widget.wakeProgressFor(widget.wake.value);
                  final barHeight = ridgeAreaPx * ratio * wp;
                  return Opacity(
                    opacity: dimAlpha,
                    child: Stack(children: [
                if (widget.showLabel)
                  Positioned(
                    left: 0, right: 0, top: 0, height: labelBandPx,
                    child: ClipRect(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (widget.isDirty)
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: Container(
                                width: 4, height: 4,
                                decoration: BoxDecoration(
                                  color: t.accentBright,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              seg.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: widget.labelStyle.copyWith(
                                color: _hovered
                                    ? t.textStrong
                                    : (seg.isLeaf
                                        ? t.textNormal
                                        : t.textMuted),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Bar body. Add/del split tells the story at a glance.
                // For zero-churn (rename / mode-only / typechange) the
                // ratio is 0/0 — render a thin neutral hairline so the
                // file is still visible and selectable.
                if (barHeight > 0)
                  Positioned(
                    left: 0, right: 1, bottom: 0, height: barHeight,
                    child: _SplitBar(
                      addShare: shares.addShare,
                      delShare: shares.delShare,
                      addColor: t.stateAdded,
                      delColor: t.stateDeleted,
                      neutralColor: t.textFaint,
                      isLeaf: seg.isLeaf,
                      hovered: _hovered,
                    ),
                  )
                else
                  // Pure-rename / 0-churn / fold with no churn: thin
                  // neutral baseline so the segment still has presence.
                  Positioned(
                    left: 0, right: 1, bottom: 0, height: 1.5,
                    child: ColoredBox(
                      color: t.textFaint.withValues(
                          alpha: _hovered ? 0.7 : 0.5),
                    ),
                  ),
                // Hero rim — sharp accent at bar top, the panel's one
                // committed signal for "look at this file first".
                if (widget.isHero && barHeight > 1.5)
                  Positioned(
                    left: 0, right: 1,
                    bottom: barHeight - 1.5, height: 1.5,
                    child: ColoredBox(color: t.accentBright),
                  ),
                // Lifecycle promotion rim — canonical files (top
                // 10 % of touch counts) get a thin top accent line;
                // reinforced files get a fainter one. Read as "this
                // file is structurally important to the repo." Only
                // rendered for leaf segments, never for folds.
                if (!widget.isHero &&
                    seg.isLeaf &&
                    widget.lifecycle != null &&
                    widget.lifecycle!.promotion != FilePromotion.candidate &&
                    barHeight > 1.5)
                  Positioned(
                    left: 0, right: 1,
                    bottom: barHeight - 1.0, height: 1.0,
                    child: ColoredBox(
                      color: t.accentBright.withValues(
                        alpha: widget.lifecycle!.promotion ==
                                FilePromotion.canonical
                            ? 0.6
                            : 0.3,
                      ),
                    ),
                  ),
                // Lifecycle decay marker — stale files get a single
                // dot in the top-right, like a weathering mark. The
                // file is remembered structurally but hasn't moved
                // recently. Subtle; reads as patina, not warning.
                if (seg.isLeaf &&
                    widget.lifecycle != null &&
                    widget.lifecycle!.decay == FileDecay.stale &&
                    barHeight > 4)
                  Positioned(
                    right: 2, top: labelBandPx + 1,
                    child: Container(
                      width: 2.5, height: 2.5,
                      decoration: BoxDecoration(
                        color: t.textFaint.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // Conflict surfaces around the bar's edge as a rim.
                if (notch != null && notch.label == 'U' && barHeight > 0)
                  Positioned(
                    left: 0, right: 1, bottom: 0, height: barHeight,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: notch.color, width: 1),
                        ),
                      ),
                    ),
                  ),
                // Type glyph for R / C / T — corner letter, theme color.
                // Renames / copies / typechanges have no add/del story
                // so the bar alone can't say what they are.
                if (notch != null &&
                    notch.label != 'U' &&
                    seg.width > widget.labelStyle.fontSize! * 1.6)
                  Positioned(
                    left: 1, top: labelBandPx + 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 0),
                      decoration: BoxDecoration(
                        color: notch.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        notch.label,
                        style: widget.labelStyle.copyWith(
                          color: notch.color,
                          fontSize: widget.labelStyle.fontSize! - 1,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                    ]),
                  );
                },
              );
            }),
          ),
        ),
      ),
      ),
    );
  }
}

/// Persistent one-line inspector that renders whatever the cursor is
/// hovering. Sits in the chrome above the strip so it never overlaps
/// the bars themselves — the user can read details without fighting
/// their own pointer. When nothing is hovered, shows a quiet hint.
class _InspectorStrip extends StatelessWidget {
  final AppTokens tokens;
  final _HoverInfo? hover;
  final TextStyle style;
  final _FocusSummary idleSummary;

  const _InspectorStrip({
    required this.tokens,
    required this.hover,
    required this.style,
    required this.idleSummary,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final hasHover = hover != null;
    return Semantics(
      liveRegion: true,
      container: true,
      child: AnimatedSwitcher(
      duration: context.motion(const Duration(milliseconds: 120)),
      switchInCurve: Curves.easeOut,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: hasHover
          ? Row(
              key: const ValueKey('hover'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    hover!.label,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(
                      color: t.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('+${hover!.additions}',
                    style: style.copyWith(color: t.stateAdded)),
                const SizedBox(width: 6),
                Text('-${hover!.deletions}',
                    style: style.copyWith(color: t.stateDeleted)),
              ],
            )
          // Idle: show what the focused subtree looks like as a whole.
          // Same line height as the hover state so the chrome doesn't
          // jump as the cursor enters/leaves the strip.
          : Row(
              key: const ValueKey('idle'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${idleSummary.fileCount} '
                  'file${idleSummary.fileCount == 1 ? '' : 's'}',
                  style: style.copyWith(color: t.textMuted),
                ),
                if (idleSummary.directSubdirs > 0) ...[
                  Text(' · ', style: style.copyWith(color: t.textFaint)),
                  Text(
                    '${idleSummary.directSubdirs} '
                    'subdir${idleSummary.directSubdirs == 1 ? '' : 's'}',
                    style: style.copyWith(color: t.textMuted),
                  ),
                ],
                Text(' · ', style: style.copyWith(color: t.textFaint)),
                Text('+${idleSummary.additions}',
                    style: style.copyWith(color: t.stateAdded)),
                const SizedBox(width: 6),
                Text('-${idleSummary.deletions}',
                    style: style.copyWith(color: t.stateDeleted)),
              ],
            ),
    ),
    );
  }
}

/// Two flat regions stacked to encode additions (top) over deletions
/// (bottom), each proportional to its share of churn. All colors are
/// theme tokens passed in by the caller — this widget owns no palette.
class _SplitBar extends StatelessWidget {
  final double addShare;
  final double delShare;
  final Color addColor;
  final Color delColor;
  final Color neutralColor;
  final bool isLeaf;
  final bool hovered;

  const _SplitBar({
    required this.addShare,
    required this.delShare,
    required this.addColor,
    required this.delColor,
    required this.neutralColor,
    required this.isLeaf,
    required this.hovered,
  });

  @override
  Widget build(BuildContext context) {
    // Container/fold segments aren't files — render as one neutral
    // block so they read as "more content here" rather than mimicking
    // a real file's add/del story.
    if (!isLeaf) {
      return ColoredBox(
        color: neutralColor.withValues(alpha: hovered ? 0.55 : 0.32),
      );
    }
    final addAlpha = hovered ? 0.92 : 0.78;
    final delAlpha = hovered ? 0.92 : 0.78;
    return LayoutBuilder(builder: (context, cons) {
      final h = cons.maxHeight;
      final w = cons.maxWidth;
      final delH = h * delShare;
      final addH = h * addShare;
      // Sign glyphs (`+` / `−`) inside each region — non-color
      // encoding for the add/del split. Renders only when both width
      // and region height clear a glyph budget so we never crowd a
      // tiny bar. Helps deuteranopic and protanopic readers, and
      // doubles as a redundant cue for everyone in low light.
      const glyphBudget = 11.0;
      final canShowGlyph = w >= glyphBudget * 1.4;
      final glyphStyle = TextStyle(
        color: neutralColor.withValues(alpha: 0.55),
        fontSize: 9,
        fontFamily: 'JetBrainsMono',
        fontWeight: FontWeight.w700,
        height: 1.0,
      );
      return Stack(children: [
        if (delH > 0)
          Positioned(
            left: 0, right: 0, bottom: 0, height: delH,
            child: ColoredBox(color: delColor.withValues(alpha: delAlpha)),
          ),
        if (addH > 0)
          Positioned(
            left: 0, right: 0, bottom: delH, height: addH,
            child: ColoredBox(color: addColor.withValues(alpha: addAlpha)),
          ),
        if (canShowGlyph && addH >= glyphBudget)
          Positioned(
            left: 2, top: (h - delH - addH) + 1,
            child: Text('+', style: glyphStyle),
          ),
        if (canShowGlyph && delH >= glyphBudget)
          Positioned(
            left: 2, bottom: 1,
            child: Text('−', style: glyphStyle),
          ),
      ]);
    });
  }
}


class _SingleFileRow extends StatelessWidget {
  final SeismographSegment segment;
  final AppTokens tokens;
  final bool isDirty;
  final VoidCallback onTap;

  const _SingleFileRow({
    required this.segment,
    required this.tokens,
    required this.isDirty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.chromeAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        if (isDirty)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: t.accentBright,
                shape: BoxShape.circle,
              ),
            ),
          ),
        Expanded(
          child: Text(
            segment.label,
            style: TextStyle(
              color: t.textStrong, fontSize: 12,
              fontFamily: 'JetBrainsMono',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text('+${segment.additions}',
            style: TextStyle(color: t.stateAdded, fontSize: 11)),
        const SizedBox(width: 6),
        Text('-${segment.deletions}',
            style: TextStyle(color: t.stateDeleted, fontSize: 11)),
      ]),
        ),
      ),
    );
  }
}


/// Compact horizontal seismograph used as a navigator while the user is
/// viewing a diff. One bar per file in the commit, height ∝ churn share,
/// the currently-open file glowing with the hero accent. Clicking any
/// bar swaps the diff to that file. The rail IS the back-affordance:
/// the user never has to return to the overview to switch files.
class CommitSeismographRail extends StatefulWidget {
  final CommitDetailData detail;
  final String currentFile;
  final AppTokens tokens;
  final ValueChanged<String> onOpenFile;
  final double height;

  const CommitSeismographRail({
    super.key,
    required this.detail,
    required this.currentFile,
    required this.tokens,
    required this.onOpenFile,
    this.height = 38,
  });

  @override
  State<CommitSeismographRail> createState() => _CommitSeismographRailState();
}

class _CommitSeismographRailState extends State<CommitSeismographRail>
    with SingleTickerProviderStateMixin {
  late AnimationController _wake;
  // Index of the bar the user is hovering with a drag (scrub gesture).
  // Distinct from the per-bar mouse hover so bars far from the cursor
  // can highlight if the user is dragging across the rail.
  int? _scrubIndex;

  @override
  void initState() {
    super.initState();
    _wake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant CommitSeismographRail old) {
    super.didUpdateWidget(old);
    // New commit selected mid-diff (from elsewhere) → re-wake.
    if (old.detail.commitHash != widget.detail.commitHash) {
      _wake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _wake.dispose();
    super.dispose();
  }

  /// Map a drag dx (0..railWidth) to a file index using the cumulative
  /// churn-weighted bar widths. Mirrors the Flexible(flex: churn) layout
  /// without needing render-object measurement.
  int _indexAt(double dx, double railWidth, List<int> flexes) {
    if (flexes.isEmpty || railWidth <= 0) return 0;
    final total = flexes.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 0;
    final ratio = (dx / railWidth).clamp(0.0, 1.0);
    var cumulative = 0;
    for (var i = 0; i < flexes.length; i++) {
      cumulative += flexes[i];
      if (ratio < cumulative / total) return i;
    }
    return flexes.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final detail = widget.detail;
    if (detail.files.isEmpty) return SizedBox(height: widget.height);

    // Sort by directory then churn so adjacent bars are usually
    // related — the rail reads as the commit's spatial layout, not a
    // pure histogram.
    final files = [...detail.files]..sort((a, b) {
      final pa = a.path.replaceAll('\\', '/');
      final pb = b.path.replaceAll('\\', '/');
      final dirA = pa.contains('/') ? pa.substring(0, pa.lastIndexOf('/')) : '';
      final dirB = pb.contains('/') ? pb.substring(0, pb.lastIndexOf('/')) : '';
      final c = dirA.compareTo(dirB);
      if (c != 0) return c;
      return pa.compareTo(pb);
    });

    final maxChurn = files
        .map((f) => f.additions + f.deletions)
        .fold<int>(1, (a, b) => a > b ? a : b);

    final flexes = [
      for (final f in files) (f.additions + f.deletions).clamp(1, 1 << 30),
    ];

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, cons) {
        final railW = cons.maxWidth;
        void scrub(double dx) {
          final i = _indexAt(dx, railW, flexes);
          if (i != _scrubIndex) {
            setState(() => _scrubIndex = i);
          }
        }
        return GestureDetector(
          // Scrub the rail like a tape head — drag to preview, release
          // to commit. Click is unchanged (handled by individual bars).
          onPanStart: (d) => scrub(d.localPosition.dx),
          onPanUpdate: (d) => scrub(d.localPosition.dx),
          onPanEnd: (_) {
            final i = _scrubIndex;
            setState(() => _scrubIndex = null);
            if (i != null && i >= 0 && i < files.length) {
              widget.onOpenFile(files[i].path.replaceAll('\\', '/'));
            }
          },
          onPanCancel: () => setState(() => _scrubIndex = null),
          child: Row(children: [
            for (var i = 0; i < files.length; i++)
              Flexible(
                flex: flexes[i],
                child: _RailBar(
                  file: files[i],
                  tokens: t,
                  maxChurn: maxChurn,
                  isCurrent: _samePath(files[i].path, widget.currentFile),
                  isScrubTarget: _scrubIndex == i,
                  wake: _wake,
                  wakeOffset: files.isEmpty ? 0 : (i / files.length) * 0.5,
                  onTap: () =>
                      widget.onOpenFile(files[i].path.replaceAll('\\', '/')),
                ),
              ),
          ]),
        );
      }),
    );
  }

  static bool _samePath(String a, String b) =>
      a.replaceAll('\\', '/') == b.replaceAll('\\', '/');
}

class _RailBar extends StatefulWidget {
  final CommitFileStatData file;
  final AppTokens tokens;
  final int maxChurn;
  final bool isCurrent;
  final bool isScrubTarget;
  final VoidCallback onTap;
  final Animation<double> wake;
  final double wakeOffset;

  const _RailBar({
    required this.file,
    required this.tokens,
    required this.maxChurn,
    required this.isCurrent,
    required this.isScrubTarget,
    required this.wake,
    required this.wakeOffset,
    required this.onTap,
  });

  @override
  State<_RailBar> createState() => _RailBarState();
}

class _RailBarState extends State<_RailBar> {
  bool _hovered = false;

  double _wakeForBar(double global) {
    // Bars near the start wake first; near the end, last. Fits in the
    // controller's [0,1] without spilling over.
    final start = widget.wakeOffset;
    final end = (start + 0.5).clamp(0.0, 1.0);
    return ((global - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final f = widget.file;
    final churn = f.additions + f.deletions;
    final ratio = churn / widget.maxChurn;
    final isLive = widget.isCurrent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: f.path.replaceAll('\\', '/'),
          waitDuration: const Duration(milliseconds: 250),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            color: widget.isScrubTarget
                ? t.accentBright.withValues(alpha: 0.18)
                : isLive
                    ? t.accentBright.withValues(alpha: 0.10)
                    : (_hovered
                        ? t.textNormal.withValues(alpha: 0.08)
                        : Colors.transparent),
            child: LayoutBuilder(builder: (context, cons) {
              final h = cons.maxHeight;
              final ridgeArea = (h - 2).clamp(0.0, double.infinity);
              final addShare = churn == 0 ? 0.0 : f.additions / churn;
              final delShare = churn == 0 ? 0.0 : f.deletions / churn;
              return AnimatedBuilder(
                animation: widget.wake,
                builder: (context, _) {
                  final wp = _wakeForBar(widget.wake.value);
                  final barH = ridgeArea * ratio * wp;
                  final delH = barH * delShare;
                  final addH = barH * addShare;
                  return Stack(children: [
                if (delH > 0)
                  Positioned(
                    left: 0, right: 0, bottom: 0, height: delH,
                    child: ColoredBox(
                      color: t.stateDeleted.withValues(
                          alpha: isLive ? 0.95 : (_hovered ? 0.85 : 0.7)),
                    ),
                  ),
                if (addH > 0)
                  Positioned(
                    left: 0, right: 0, bottom: delH, height: addH,
                    child: ColoredBox(
                      color: t.stateAdded.withValues(
                          alpha: isLive ? 0.95 : (_hovered ? 0.85 : 0.7)),
                    ),
                  ),
                // Zero-churn (rename / mode-only): a thin neutral
                // baseline so the file is still visible in the rail.
                if (churn == 0)
                  Positioned(
                    left: 0, right: 0, bottom: 0, height: 1.5,
                    child: ColoredBox(
                      color: t.textFaint.withValues(
                          alpha: isLive ? 0.9 : 0.5),
                    ),
                  ),
                // Current-file rim on top of the bar.
                if (isLive && barH > 1.5)
                  Positioned(
                    left: 0, right: 0,
                    bottom: barH - 1.5, height: 1.5,
                    child: ColoredBox(color: t.accentBright),
                  ),
                // Current-file under-baseline rim (anchors the eye
                // even when the bar is microscopic).
                if (isLive)
                  Positioned(
                    left: 0, right: 0, bottom: 0, height: 2,
                    child: ColoredBox(color: t.accentBright),
                  ),
                  ]);
                },
              );
            }),
          ),
        ),
      ),
    );
  }
}


class _FilterBar extends StatelessWidget {
  final AppTokens tokens;
  final TextStyle style;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _FilterBar({
    required this.tokens,
    required this.style,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.chromeAccent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Text('/', style: style.copyWith(color: t.accentBright)),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            cursorColor: t.accentBright,
            cursorWidth: 1,
            style: style.copyWith(color: t.textStrong),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'filter path',
              hintStyle: style.copyWith(color: t.textFaint),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        GestureDetector(
          onTap: onClose,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text('esc',
                style: style.copyWith(color: t.textFaint)),
          ),
        ),
      ]),
    );
  }
}


