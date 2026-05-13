// COMMIT ATLAS, candidate commits, not a file list
//
// The conventional Git UI asks *which files?*, a mechanical checkbox.
// That's the wrong question. A commit is a *claim of intent*: "these
// changes form one coherent thought." The Atlas asks the right question
// first: *what distinct intents are in this diff, and how do I carve
// them cleanly?*
//
// For every cluster the coupling engine found, the Atlas proposes a
// candidate commit, a provisional thought, auto-named from the files'
// shared path, measured by coherence. One decisive action per candidate:
// **carve**. Carving replaces the current selection with exactly that
// candidate's files.
//
// The user's job stops being "don't forget any related files" and
// starts being "critique the candidates." That's the fear-killer ,
// you react to a proposal rather than authoring from a blank slate.
//
// Aesthetic: apothecary. Not dashboard. Hairline borders, letterspaced
// small caps, tabular numerals, phosphor-ink accents lifted from the
// existing cluster palette. Each card reads as a specimen tray, not a
// tile.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../backend/dtos.dart';
import '../../backend/file_coupling.dart';
import '../../ui/tokens.dart';

// Candidate, a provisional commit the Atlas proposes

class _Candidate {
  final int id; // cluster id (-1 for "leftovers" bench)
  final String title;
  final String? subtitle;
  final List<String> members;
  final double coherence; // 0..1
  final List<CouplingNudge> orbits;

  /// Dominant bond — why these files group. Drives the axis pill on
  /// the card so the user sees the geometry, not just "they cluster."
  /// Null for leftovers (by definition unclustered).
  final RelatednessAxis? axis;

  _Candidate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.members,
    required this.coherence,
    required this.orbits,
    required this.axis,
  });

  bool get isLeftovers => id == FileClusters.clusterIdIsolated;
}

/// Short label for the axis pill. Chosen to be semantically dense in
/// 6–12 characters so the pill stays compact. Paired with a glyph
/// that hints at the axis's flavour (◈ history, ◇ vocabulary, ▣
/// structure, ⌂ path).
({String glyph, String label}) _axisPill(RelatednessAxis axis) {
  switch (axis) {
    case RelatednessAxis.transport:
      return (glyph: '▣', label: 'STRUCTURE');
    case RelatednessAxis.coChange:
      return (glyph: '◈', label: 'CO-CHANGE');
    case RelatednessAxis.symbol:
      return (glyph: '◇', label: 'SHARED SYMBOLS');
    case RelatednessAxis.pathAffinity:
      return (glyph: '⌂', label: 'PATH SIBLINGS');
  }
}

// Public widget, kept named FileConstellation for import stability; the
// design has been fully rethought beneath the name.

class FileConstellation extends StatefulWidget {
  final List<RepositoryStatusFile> files;
  final FileClusters clusters;
  final FileCouplingMatrix? matrix;
  final Map<String, FileChangeWeight> changeWeights;
  final Set<String> includedPaths;
  final AppTokens tokens;
  /// Per-path reviewer count from the forge constellation. Null or
  /// absent = no observation data available. 0 = file exists in the
  /// engine but has never been reviewed. >0 = number of distinct
  /// reviewers who have observed this path through forge reviews.
  final Map<String, int> observerCounts;

  /// Toggle a single file in or out of the current selection.
  final void Function(String path, bool value) onToggleIncluded;

  /// Replace the current selection with exactly [paths]. The Atlas calls
  /// this when a candidate is carved, stages *only* that candidate.
  final void Function(List<String> paths) onCarve;

  /// Open a file's diff in the inspector.
  final void Function(String path) onSelectDiff;

  /// Batch-remove [paths] from the current selection. Used by the
  /// untie gesture so we don't fire N individual toggle setStates.
  final void Function(List<String> paths) onUntieCluster;

  const FileConstellation({
    super.key,
    required this.files,
    required this.clusters,
    required this.matrix,
    this.changeWeights = const {},
    required this.includedPaths,
    required this.tokens,
    this.observerCounts = const {},
    required this.onToggleIncluded,
    required this.onCarve,
    required this.onSelectDiff,
    required this.onUntieCluster,
  });

  @override
  State<FileConstellation> createState() => _FileConstellationState();
}

class _FileConstellationState extends State<FileConstellation> {
  // Which candidate the cursor is over. Other cards dim their chips so
  // the user reads "carve replaces selection" from motion, not text.
  int? _hoveredCandidateId;

  // Cached `_buildCandidates` / `_leftovers` results. Hovering a
  // candidate card calls `setState(_hoveredCandidateId = …)` which
  // rebuilds this widget, and previously each rebuild redid the full
  // cluster scan + `suggestMissingPeers` walk + sort even though the
  // inputs hadn't moved. Keying the cache on the clusters instance
  // is sufficient because clusters is itself derived upstream from
  // `widget.files` and `widget.matrix`: whenever either of those
  // changes, the clusters reference changes and the cache invalidates.
  List<_Candidate>? _candidatesCache;
  List<String>? _leftoversCache;
  Object? _cacheClusters;
  Object? _cacheMatrix;

  List<_Candidate> _buildCandidates() {
    if (identical(_cacheClusters, widget.clusters) &&
        identical(_cacheMatrix, widget.matrix) &&
        _candidatesCache != null) {
      return _candidatesCache!;
    }
    final byCluster = <int, List<String>>{};
    for (final f in widget.files) {
      final cid =
          widget.clusters.byPath[f.path] ?? FileClusters.clusterIdIsolated;
      byCluster.putIfAbsent(cid, () => <String>[]).add(f.path);
    }
    final candidates = <_Candidate>[];
    byCluster.forEach((cid, members) {
      if (cid == FileClusters.clusterIdIsolated) return;
      members.sort();
      final coherence = widget.matrix?.coherenceFor(members) ?? 0.5;
      final orbits = widget.matrix == null
          ? const <CouplingNudge>[]
          : suggestMissingPeers(
              selected: members,
              allChanged: widget.files.map((f) => f.path),
              matrix: widget.matrix!,
              threshold: 0.3,
              limit: 3,
            );
      final name = _autoName(members);
      candidates.add(_Candidate(
        id: cid,
        title: name.$1,
        subtitle: name.$2,
        members: members,
        coherence: coherence,
        orbits: orbits,
        axis: widget.clusters.dominantAxisByCluster[cid],
      ));
    });
    candidates.sort((a, b) {
      final c = b.members.length.compareTo(a.members.length);
      if (c != 0) return c;
      return a.title.compareTo(b.title);
    });
    _candidatesCache = candidates;
    // Invalidate the paired leftovers cache when candidates recompute —
    // they're derived from the same inputs, so their cache should
    // evict together to avoid presenting stale orbit-vs-member splits.
    _leftoversCache = null;
    _cacheClusters = widget.clusters;
    _cacheMatrix = widget.matrix;
    return candidates;
  }

  List<String> _leftovers() {
    if (identical(_cacheClusters, widget.clusters) &&
        _leftoversCache != null) {
      return _leftoversCache!;
    }
    final out = <String>[];
    for (final f in widget.files) {
      final cid =
          widget.clusters.byPath[f.path] ?? FileClusters.clusterIdIsolated;
      if (cid == FileClusters.clusterIdIsolated) out.add(f.path);
    }
    out.sort();
    _leftoversCache = out;
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final candidates = _buildCandidates();
    final leftovers = _leftovers();

    if (widget.files.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasHover = _hoveredCandidateId != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
      children: [
        if (candidates.isEmpty)
          _EmptyCandidates(tokens: t)
        else
          for (final c in candidates) ...[
            _CandidateCard(
              // Stable key. Without this, reordering candidates after a
              // bind (member counts change the sort) makes Flutter pair
              // the wrong State with the wrong Widget, so the bind
              // animation plays on the wrong card.
              key: ValueKey<int>(c.id),
              tokens: t,
              candidate: c,
              matrix: widget.matrix,
              changeWeights: widget.changeWeights,
              includedPaths: widget.includedPaths,
              observerCounts: widget.observerCounts,
              dimmed: hasHover && _hoveredCandidateId != c.id,
              onHoverChanged: (hovered) {
                if (!mounted) return;
                if (hovered) {
                  if (_hoveredCandidateId != c.id) {
                    setState(() => _hoveredCandidateId = c.id);
                  }
                } else if (_hoveredCandidateId == c.id) {
                  setState(() => _hoveredCandidateId = null);
                }
              },
              onCarve: () => widget.onCarve(c.members),
              onToggleFile: widget.onToggleIncluded,
              onAddOrbit: (path) => widget.onToggleIncluded(path, true),
              onSelectDiff: widget.onSelectDiff,
              onUntie: widget.onUntieCluster,
            ),
            const SizedBox(height: 10),
          ],
        if (leftovers.isNotEmpty) ...[
          const SizedBox(height: 6),
          _Hairline(tokens: t),
          const SizedBox(height: 10),
          _LeftoversBench(
            tokens: t,
            paths: leftovers,
            includedPaths: widget.includedPaths,
            dimmed: hasHover,
            onToggle: widget.onToggleIncluded,
            onSelectDiff: widget.onSelectDiff,
          ),
        ],
      ],
    );
  }
}

// Thin centered hairline used wherever sectioning is needed without text.
class _Hairline extends StatelessWidget {
  final AppTokens tokens;
  const _Hairline({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      color: tokens.chromeBorder.withValues(alpha: 0.18),
    );
  }
}

// Auto-namer, cluster → (TITLE, subtitle)

/// Given a set of paths, invent a two-part title:
///   • TITLE: uppercase letterspaced, the *where* (deepest shared dir)
///   • subtitle: the *what* (shared basename stem, or null)
/// Normalises separators, skips leaf filenames when computing directory
/// prefix, handles the common dart-project shape `lib/<domain>/<area>`
/// by preferring 1–2 meaningful segments over the full path.
(String, String?) _autoName(List<String> paths) {
  if (paths.isEmpty) return ('UNSORTED', null);
  final norm = paths.map((p) => p.replaceAll('\\', '/')).toList();

  // --- Shared directory segments (exclude basename).
  final split = norm.map((p) {
    final segs = p.split('/');
    return segs.sublist(0, segs.length - 1);
  }).toList();
  var prefix = <String>[];
  if (split.isNotEmpty) {
    final first = split.first;
    final maxK = split.fold<int>(
        first.length, (acc, s) => math.min(acc, s.length));
    for (var k = 0; k < maxK; k++) {
      final v = first[k];
      if (split.every((s) => s[k] == v)) {
        prefix.add(v);
      } else {
        break;
      }
    }
  }

  // Drop boilerplate top-level segments so titles read about the code,
  // not the repo layout.
  const boilerplate = {
    'lib', 'src', 'apps', 'app', 'packages', 'pkg', 'cmd', 'internal',
  };
  final meaningful = <String>[
    for (final seg in prefix) if (!boilerplate.contains(seg)) seg,
  ];
  final locus = meaningful.isEmpty
      ? (prefix.isNotEmpty ? prefix.last : null)
      : meaningful.last;

  // --- Shared basename stem (before last '.').
  final stems = norm.map((p) {
    final base = p.split('/').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }).toList();
  String? sharedStem;
  if (stems.length > 1) {
    final a = stems.first;
    var k = a.length;
    for (final s in stems.skip(1)) {
      k = math.min(k, s.length);
      for (var i = 0; i < k; i++) {
        if (a.codeUnitAt(i) != s.codeUnitAt(i)) {
          k = i;
          break;
        }
      }
      if (k == 0) break;
    }
    final candidate = a.substring(0, k).replaceAll(RegExp(r'[_\-.]+$'), '');
    if (candidate.length >= 3) sharedStem = candidate;
  } else {
    sharedStem = stems.first;
  }

  final title = (locus ?? (paths.length == 1 ? 'SINGLETON' : 'MIXED'))
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .toUpperCase();
  String? subtitle;
  if (sharedStem != null && sharedStem.isNotEmpty) {
    // Only use the stem if it isn't already implied by the locus.
    final stemHuman =
        sharedStem.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    if (stemHuman.length >= 3 &&
        stemHuman.toLowerCase() != locus?.toLowerCase()) {
      subtitle = stemHuman;
    }
  }
  return (title, subtitle);
}

// Candidate card, one proposed commit

class _CandidateCard extends StatefulWidget {
  final AppTokens tokens;
  final _Candidate candidate;
  final FileCouplingMatrix? matrix;
  final Map<String, FileChangeWeight> changeWeights;
  final Set<String> includedPaths;
  final Map<String, int> observerCounts;
  final bool dimmed;
  final void Function(bool hovered) onHoverChanged;
  final VoidCallback onCarve;
  final void Function(String path, bool value) onToggleFile;
  final void Function(String path) onAddOrbit;
  final void Function(String path) onSelectDiff;
  final void Function(List<String> paths) onUntie;

  const _CandidateCard({
    super.key,
    required this.tokens,
    required this.candidate,
    required this.matrix,
    required this.changeWeights,
    required this.includedPaths,
    this.observerCounts = const {},
    required this.dimmed,
    required this.onHoverChanged,
    required this.onCarve,
    required this.onToggleFile,
    required this.onAddOrbit,
    required this.onSelectDiff,
    required this.onUntie,
  });

  @override
  State<_CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends State<_CandidateCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  bool _glyphHovered = false;
  late final AnimationController _bindCtrl;

  // Each card hosts an animated binding ribbon. Progress 0 = loose
  // (no ribbon); 1 = bound (ribbon traces around the file chips with
  // four geometric knots set at the corners). The glyph tap toggles
  // between the two, with the same backing op as the old CARVE
  // button so the rest of the page is unaffected.
  @override
  void initState() {
    super.initState();
    _bindCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
      reverseDuration: const Duration(milliseconds: 380),
      value: _isCarvedFromProps() ? 1.0 : 0.0,
    );
  }

  bool _isCarvedFromProps() {
    final c = widget.candidate;
    final inc = widget.includedPaths;
    if (c.members.isEmpty) return false;
    return c.members.every(inc.contains);
  }

  @override
  void didUpdateWidget(covariant _CandidateCard old) {
    super.didUpdateWidget(old);
    final shouldBeBound = _isCarvedFromProps();
    final currentlyBound = _bindCtrl.value > 0.5;
    if (shouldBeBound != currentlyBound) {
      if (shouldBeBound) {
        _bindCtrl.forward();
      } else {
        _bindCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _bindCtrl.dispose();
    super.dispose();
  }

  void _setHover(bool v) {
    if (_hovered == v) return;
    setState(() => _hovered = v);
    widget.onHoverChanged(v);
  }

  void _onGlyphTap() {
    // The glyph IS the bind action. The animation is driven entirely
    // by the props change in didUpdateWidget; here we just dispatch
    // the staging op upstream. Tapping while bound clears selection
    // (releases the binding); tapping while loose binds it. Untie
    // goes through a batch callback so we don't fire N setStates
    // through N individual toggle calls.
    if (_isCarvedFromProps()) {
      widget.onUntie(widget.candidate.members);
    } else {
      widget.onCarve();
    }
  }

  // Resonance tint: cluster's theme colour is the identity; coherence
  // (how tightly the files actually hang together) saturates it. Low
  // coherence reads as muted chrome; a tight cluster reads as a
  // confident accent. Hue stays inside the theme family — only a
  // tiny shift from cluster id so related cards feel related.
  Color _tintedAccent(Color base, double coherence, int clusterId) {
    final hsl = HSLColor.fromColor(base);
    final k = coherence.clamp(0.0, 1.0);
    final hueShift = ((clusterId.hashCode % 31) - 15) * 0.6;
    return hsl
        .withHue((hsl.hue + hueShift) % 360)
        .withSaturation((hsl.saturation * (0.55 + 0.45 * k)).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * (0.92 + 0.12 * k)).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final c = widget.candidate;
    final baseAccent = t.clusterStripeColor(c.id) ?? t.textMuted;
    final accent = _tintedAccent(baseAccent, c.coherence, c.id);

    final dimAlpha = widget.dimmed ? 0.45 : 1.0;
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: AnimatedOpacity(
        opacity: dimAlpha,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: _hovered
                ? t.surface1.withValues(alpha: 0.45)
                : t.surface0.withValues(alpha: 0.30),
            border: Border.all(
              color: _hovered
                  ? accent.withValues(alpha: 0.55)
                  : t.chromeBorder.withValues(alpha: 0.22),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Tooltip(
                      message: _isCarvedFromProps() ? 'untie' : 'bind',
                      waitDuration: const Duration(milliseconds: 350),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) =>
                            setState(() => _glyphHovered = true),
                        onExit: (_) =>
                            setState(() => _glyphHovered = false),
                        child: GestureDetector(
                          onTap: _onGlyphTap,
                          child: AnimatedScale(
                            scale: _glyphHovered ? 1.06 : 1.0,
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOut,
                            child: _CandidateGlyph(
                              tokens: t,
                              paths: c.members,
                              matrix: widget.matrix,
                              changeWeights: widget.changeWeights,
                              clusterId: c.id,
                              includedPaths: widget.includedPaths,
                              accent: accent,
                              observerCounts: widget.observerCounts,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  c.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: t.textNormal,
                                    fontSize: 12.5,
                                    letterSpacing: 2.0,
                                    fontWeight: FontWeight.w600,
                                    height: 1.05,
                                  ),
                                ),
                              ),
                              if (c.axis != null) ...[
                                const SizedBox(width: 8),
                                _AxisPill(axis: c.axis!, tokens: t, accent: accent),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: AnimatedBuilder(
                  animation: _bindCtrl,
                  builder: (ctx, child) => CustomPaint(
                    foregroundPainter: _BindingPainter(
                      progress: _bindCtrl.value,
                      color: accent,
                    ),
                    child: child,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final path in c.members)
                          _FileChip(
                            tokens: t,
                            accent: accent,
                            path: path,
                            included: widget.includedPaths.contains(path),
                            onToggle: () => widget.onToggleFile(
                                path, !widget.includedPaths.contains(path)),
                            onOpen: () => widget.onSelectDiff(path),
                          ),
                        for (final orbit in c.orbits)
                          _OrbitChip(
                            tokens: t,
                            accent: accent,
                            path: orbit.path,
                            onAdd: () => widget.onAddOrbit(orbit.path),
                          ),
                      ],
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

// Binding ribbon, the action visualised as geometry
//
// At progress 0 nothing is drawn. The path traces clockwise from the
// top-left corner around the chips area. As progress climbs, the line
// extends along the perimeter; once it returns to its origin (>= 0.95)
// four small diamond knots fade in at the corners. Untie reverses the
// whole thing in 380ms (snappier than tying so it doesn't feel like
// undoing fights you).

class _BindingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _BindingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001) return;
    if (size.width < 8 || size.height < 8) return;

    const r = 4.0;
    // Build the perimeter path explicitly, starting at the top-left
    // corner and travelling clockwise. `addRRect` would start at an
    // implementation-defined point; pinning the origin here keeps the
    // ribbon consistent across repaints.
    final w = size.width - 1;
    final h = size.height - 1;
    const o = 0.5; // half-pixel inset so the 1.1px stroke lands crisp
    final path = Path()
      ..moveTo(o + r, o)
      ..lineTo(o + w - r, o)
      ..arcToPoint(
        Offset(o + w, o + r),
        radius: const Radius.circular(r),
      )
      ..lineTo(o + w, o + h - r)
      ..arcToPoint(
        Offset(o + w - r, o + h),
        radius: const Radius.circular(r),
      )
      ..lineTo(o + r, o + h)
      ..arcToPoint(
        Offset(o, o + h - r),
        radius: const Radius.circular(r),
      )
      ..lineTo(o, o + r)
      ..arcToPoint(
        Offset(o + r, o),
        radius: const Radius.circular(r),
      );

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final total = metric.length;
    final tieProgress = progress.clamp(0.0, 1.0);
    // Reserve the last 8% of the animation for the corner knots fading
    // in. The ribbon itself reaches full length at 0.92.
    final lineProgress = (tieProgress / 0.92).clamp(0.0, 1.0);
    final visible = total * lineProgress;
    final partial = metric.extractPath(0, visible);

    final stroke = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(partial, stroke);

    // The cursor on the leading edge: a tiny dot riding the ribbon as
    // it lays itself down. Reads as "actively binding" rather than a
    // static stroke.
    if (lineProgress > 0 && lineProgress < 1) {
      final tan = metric.getTangentForOffset(visible);
      if (tan != null) {
        final tip = Paint()..color = color;
        canvas.drawCircle(tan.position, 1.6, tip);
      }
    }

    // Knots at the four corners. Fade in over the last 8% of progress.
    final knotAlpha = ((tieProgress - 0.92) / 0.08).clamp(0.0, 1.0);
    if (knotAlpha > 0) {
      final corners = <Offset>[
        const Offset(r, r),
        Offset(size.width - r, r),
        Offset(size.width - r, size.height - r),
        Offset(r, size.height - r),
      ];
      // Explicit const is fine for the first entry; the rest need
      // the runtime size, so they stay as non-const Offsets.
      final knotPaint = Paint()
        ..color = color.withValues(alpha: knotAlpha)
        ..style = PaintingStyle.fill;
      for (final c in corners) {
        _drawDiamond(canvas, c, 2.0, knotPaint);
      }
    }
  }

  void _drawDiamond(Canvas canvas, Offset c, double r, Paint paint) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant _BindingPainter old) =>
      old.progress != progress || old.color != color;
}


// File chip, tiny, clickable

class _FileChip extends StatefulWidget {
  final AppTokens tokens;
  final Color accent;
  final String path;
  final bool included;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  const _FileChip({
    required this.tokens,
    required this.accent,
    required this.path,
    required this.included,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  State<_FileChip> createState() => _FileChipState();
}

class _FileChipState extends State<_FileChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final base = widget.path.replaceAll('\\', '/').split('/').last;
    final border = widget.included
        ? widget.accent.withValues(alpha: _hovered ? 0.9 : 0.7)
        : t.chromeBorder.withValues(alpha: _hovered ? 0.5 : 0.3);
    final bg = widget.included
        ? widget.accent.withValues(alpha: _hovered ? 0.25 : 0.16)
        : (_hovered
            ? t.surface1.withValues(alpha: 0.4)
            : Colors.transparent);
    final textColor = widget.included
        ? t.textNormal
        : t.textMuted.withValues(alpha: 0.9);
    return Tooltip(
      message: widget.path,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onToggle,
          onDoubleTap: widget.onOpen,
          onSecondaryTap: widget.onOpen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 3,
                  height: 3,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.included
                        ? widget.accent
                        : t.textMuted.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  base,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10.5,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

// Orbit chip, a coupled neighbor the user didn't include

class _OrbitChip extends StatefulWidget {
  final AppTokens tokens;
  final Color accent;
  final String path;
  final VoidCallback onAdd;

  const _OrbitChip({
    required this.tokens,
    required this.accent,
    required this.path,
    required this.onAdd,
  });

  @override
  State<_OrbitChip> createState() => _OrbitChipState();
}

class _OrbitChipState extends State<_OrbitChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final base = widget.path.replaceAll('\\', '/').split('/').last;
    return Tooltip(
      message: widget.path,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onAdd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              border: Border.all(
                color: widget.accent.withValues(alpha: _hovered ? 0.7 : 0.35),
                width: 0.8,
                style: _hovered ? BorderStyle.solid : BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '+',
                  style: TextStyle(
                    color: widget.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  base,
                  style: TextStyle(
                    color: t.textMuted.withValues(alpha: _hovered ? 1.0 : 0.8),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Candidate glyph, 44px sigil of the cluster.
//
//   • One central hub.
//   • One spoke per file, angles evenly divided around the hub.
//   • Spoke LENGTH encodes correlatedness — tightly coupled files sit
//     close to the hub, loosely coupled files drift outward.
//   • Tip NODE brightness/size encodes diff impact (adds + dels), so a
//     tiny typo fix shows as a small dim dot and a heavy rewrite glows.
//   • Included files fill; excluded files ring. Cluster identity
//     (cluster id) phase-shifts the starting angle so sibling cards
//     don't all line up the same.

// Axis pill: a compact pill-shaped badge showing the dominant
// relatedness axis for a cluster. Honours the card accent so the pill
// reads as part of the same specimen tray, not a separate tag. The
// glyph carries the axis flavour at a glance; the letterspaced text
// carries the name for anyone reading carefully.
class _AxisPill extends StatelessWidget {
  const _AxisPill({
    required this.axis,
    required this.tokens,
    required this.accent,
  });
  final RelatednessAxis axis;
  final AppTokens tokens;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final pill = _axisPill(axis);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pill.glyph,
            style: TextStyle(
              color: accent.withValues(alpha: 0.85),
              fontSize: 10,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            pill.label,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 8.5,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateGlyph extends StatelessWidget {
  final AppTokens tokens;
  final List<String> paths;
  final FileCouplingMatrix? matrix;
  final Map<String, FileChangeWeight> changeWeights;
  final int clusterId;
  final Set<String> includedPaths;
  final Color accent;
  final Map<String, int> observerCounts;

  const _CandidateGlyph({
    required this.tokens,
    required this.paths,
    required this.matrix,
    required this.changeWeights,
    required this.clusterId,
    required this.includedPaths,
    required this.accent,
    this.observerCounts = const {},
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: CustomPaint(
        painter: _GlyphPainter(
          paths: paths,
          matrix: matrix,
          changeWeights: changeWeights,
          clusterId: clusterId,
          includedPaths: includedPaths,
          accent: accent,
          faint: tokens.chromeBorder.withValues(alpha: 0.35),
          observerCounts: observerCounts,
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final List<String> paths;
  final FileCouplingMatrix? matrix;
  final Map<String, FileChangeWeight> changeWeights;
  final int clusterId;
  final Set<String> includedPaths;
  final Color accent;
  final Color faint;

  final Map<String, int> observerCounts;

  _GlyphPainter({
    required this.paths,
    required this.matrix,
    required this.changeWeights,
    required this.clusterId,
    required this.includedPaths,
    required this.accent,
    required this.faint,
    this.observerCounts = const {},
  });

  // Mean coupling of [path] to the rest of the cluster. 1.0 = twin of
  // every sibling; 0.0 = connected to them in the graph but no shared
  // signal. Used to drive spoke length.
  double _meanCouplingToOthers(String path) {
    final m = matrix;
    if (m == null || paths.length < 2) return 0.5;
    double sum = 0.0;
    int n = 0;
    for (final other in paths) {
      if (other == path) continue;
      sum += m.score(path, other);
      n++;
    }
    return n == 0 ? 0.5 : sum / n;
  }

  // Diff impact normalised into 0..1 via a gentle log curve. Binary
  // files land mid-scale so they don't read as "nothing changed".
  double _impactFor(String path) {
    final w = changeWeights[path];
    if (w == null) return 0.3;
    if (w.binary) return 0.6;
    final raw = w.adds + w.dels;
    if (raw <= 0) return 0.15;
    // log2(1+raw) / log2(1+200) clamp → ~0 at 0 lines, ~1 at 200+ lines.
    final k = math.log(1 + raw) / math.log(201);
    return k.clamp(0.05, 1.0).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (paths.isEmpty) return;
    final cx = size.width / 2;
    final cy = size.height / 2;

    const inset = 4.5;
    // Hub-to-rim: shortest span so the sigil never clips.
    final rim = math.min(size.width, size.height) / 2 - inset;
    // Minimum spoke length, keeps the busiest cluster legible.
    const rMin = 7.0;

    // Start angle phase-shifts per cluster id so sibling cards don't
    // all orient their first spoke due-north.
    final phase = (clusterId.hashCode % 360) * math.pi / 180.0;
    final n = paths.length;

    final tips = <(String, Offset, double, double)>[]; // path, pos, coupling, impact

    // Spokes first, so tip nodes paint over them.
    final spokePaint = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < n; i++) {
      final path = paths[i];
      final angle = phase + (i / n) * 2 * math.pi;
      final coupling = _meanCouplingToOthers(path).clamp(0.0, 1.0);
      // High coupling → short spoke (tip sits close to hub).
      final r = rMin + (rim - rMin) * (1.0 - coupling);
      final tip = Offset(cx + math.cos(angle) * r, cy + math.sin(angle) * r);
      canvas.drawLine(Offset(cx, cy), tip, spokePaint);
      tips.add((path, tip, coupling, _impactFor(path)));
    }

    // Central hub: faint filled disc + ring, reads as "the thought".
    final hubFill = Paint()
      ..color = accent.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 2.4, hubFill);
    final hubRing = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), 2.4, hubRing);

    // Tip nodes: size + alpha scale with diff impact, modulated by
    // observation coverage. Unobserved files are less certain — their
    // tips are dimmer and halos are smaller, expressing "we know it
    // changed, but no human has reviewed it through the forge."
    final hasObsData = observerCounts.isNotEmpty;
    for (final (path, tip, _, impact) in tips) {
      final included = includedPaths.contains(path);
      final radius = 1.4 + impact * 1.8;
      final baseAlpha = 0.55 + impact * 0.45;
      final coverageFactor = hasObsData
          ? ((observerCounts[path] ?? 0) > 0 ? 1.0 : 0.6)
          : 1.0;
      final alpha = baseAlpha * coverageFactor;
      final haloScale = coverageFactor;

      if (included && haloScale > 0.5) {
        final haloR = (radius + 3.5) * haloScale;
        final halo = Paint()
          ..shader = ui.Gradient.radial(
            tip,
            haloR,
            [
              accent.withValues(alpha: 0.35 * alpha),
              accent.withValues(alpha: 0),
            ],
          );
        canvas.drawCircle(tip, haloR, halo);
      }

      final body = Paint()
        ..color = included
            ? accent.withValues(alpha: alpha)
            : faint.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(tip, radius, body);

      if (!included) {
        final border = Paint()
          ..color = accent.withValues(alpha: 0.55 * alpha)
          ..strokeWidth = 0.7
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(tip, radius, border);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.paths != paths ||
      old.matrix != matrix ||
      old.changeWeights != changeWeights ||
      old.includedPaths != includedPaths ||
      old.clusterId != clusterId ||
      old.accent != accent ||
      old.observerCounts != observerCounts;
}

// Leftovers bench, isolated files, displayed quietly

class _LeftoversBench extends StatelessWidget {
  final AppTokens tokens;
  final List<String> paths;
  final Set<String> includedPaths;
  final bool dimmed;
  final void Function(String path, bool value) onToggle;
  final void Function(String path) onSelectDiff;

  const _LeftoversBench({
    required this.tokens,
    required this.paths,
    required this.includedPaths,
    required this.dimmed,
    required this.onToggle,
    required this.onSelectDiff,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return AnimatedOpacity(
      opacity: dimmed ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final p in paths)
            _FileChip(
              tokens: t,
              accent: t.textMuted,
              path: p,
              included: includedPaths.contains(p),
              onToggle: () => onToggle(p, !includedPaths.contains(p)),
              onOpen: () => onSelectDiff(p),
            ),
        ],
      ),
    );
  }
}

// Empty state: a single quiet line. No paragraph, no header.
class _EmptyCandidates extends StatelessWidget {
  final AppTokens tokens;

  const _EmptyCandidates({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Text(
          'no clusters yet',
          style: TextStyle(
            color: tokens.textMuted.withValues(alpha: 0.55),
            fontSize: 10.5,
            letterSpacing: 2.2,
          ),
        ),
      ),
    );
  }
}
