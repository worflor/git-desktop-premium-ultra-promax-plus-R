import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../backend/spectral_trajectory_builder.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import 'orrery_findings.dart';
import 'orrery_model.dart';
import 'orrery_painter.dart';

/// The Orrery — scrub through the repo's structural history and watch its
/// files drift through the Poincaré disk as the codebase reorganises. Reached
/// from the command palette. [OrreryPage] loads + maps the trajectory;
/// [OrreryView] is the pure UI over a ready [OrreryModel].
class OrreryPage extends StatefulWidget {
  final String repoPath;
  const OrreryPage({super.key, required this.repoPath});

  @override
  State<OrreryPage> createState() => _OrreryPageState();
}

class _OrreryPageState extends State<OrreryPage> {
  late Future<OrreryModel> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<OrreryModel> _load() async {
    final traj = await trajectoryForRepo(widget.repoPath);
    return OrreryModel.fromTrajectory(traj);
  }

  String get _repoLabel {
    final parts =
        widget.repoPath.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
    return parts.isEmpty ? widget.repoPath : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg0,
      body: FutureBuilder<OrreryModel>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _OrreryStatus(
              message: 'Tracing the manifold through history…',
              onClose: () => Navigator.of(context).pop(),
            );
          }
          if (snap.hasError) {
            return _OrreryStatus(
              message: 'Could not read this repo’s history.',
              detail: '${snap.error}',
              onClose: () => Navigator.of(context).pop(),
            );
          }
          final model = snap.data ?? OrreryModel.emptyModel;
          if (model.stepCount < 2) {
            return _OrreryStatus(
              message: 'Not enough history yet to plot a trajectory.',
              detail: 'The Orrery needs a few commits to chart.',
              onClose: () => Navigator.of(context).pop(),
            );
          }
          return OrreryView(
            model: model,
            repoLabel: _repoLabel,
            onClose: () => Navigator.of(context).pop(),
          );
        },
      ),
    );
  }
}

class _OrreryStatus extends StatelessWidget {
  final String message;
  final String? detail;
  final VoidCallback onClose;
  const _OrreryStatus({
    required this.message,
    required this.onClose,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      children: [
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _CloseChip(onTap: onClose),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message,
                  style: TextStyle(color: t.textNormal, fontSize: 14)),
              if (detail != null) ...[
                const SizedBox(height: 6),
                Text(detail!,
                    style: TextStyle(color: t.textFaint, fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Per-scalar [lo, hi] across the whole trajectory, so each rail bar shows
/// where the current step sits within the repo's own range.
class _Ranges {
  final double gapLo, gapHi, rigLo, rigHi, vnLo, vnHi;
  const _Ranges(this.gapLo, this.gapHi, this.rigLo, this.rigHi, this.vnLo,
      this.vnHi);

  factory _Ranges.of(OrreryModel model) {
    double gl = double.infinity, gh = -double.infinity;
    double rl = double.infinity, rh = -double.infinity;
    double vl = double.infinity, vh = -double.infinity;
    for (final s in model.steps) {
      gl = math.min(gl, s.gap);
      gh = math.max(gh, s.gap);
      rl = math.min(rl, s.rigidity);
      rh = math.max(rh, s.rigidity);
      vl = math.min(vl, s.vonNeumann);
      vh = math.max(vh, s.vonNeumann);
    }
    return _Ranges(gl, gh, rl, rh, vl, vh);
  }

  static double norm(double v, double lo, double hi) =>
      (hi - lo).abs() < 1e-9 ? 0.5 : ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
}

class _HoverInfo {
  final Offset pos;
  final String label;
  const _HoverInfo(this.pos, this.label);
}

/// How the central canvas reads history: [scrub] animates one disk through time
/// to *explore*; [compare] lays the structure out as static small-multiples at
/// the regime boundaries to *analyze* (animation is weak for comparison tasks —
/// Robertson et al., Tversky — so the two are separate surfaces).
enum OrreryMode { scrub, compare }

class OrreryView extends StatefulWidget {
  final OrreryModel model;
  final String repoLabel;
  final VoidCallback? onClose;

  /// Scrub position to open on; defaults to the present (head of history).
  final double? initialHead;

  /// Node id to pin on open (highlight + full journey). For deep-links/tests.
  final int? initialPinned;

  /// Level of detail to open in. Null = auto (modules on large repos, files on
  /// small). Force a level for deep-links/previews.
  final OrreryLod? initialLod;

  /// View mode to open in. Defaults to scrub. For deep-links/previews.
  final OrreryMode? initialMode;

  const OrreryView({
    super.key,
    required this.model,
    this.repoLabel = '',
    this.onClose,
    this.initialHead,
    this.initialPinned,
    this.initialLod,
    this.initialMode,
  });

  @override
  State<OrreryView> createState() => _OrreryViewState();
}

class _OrreryViewState extends State<OrreryView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _play;
  final ValueNotifier<double> _head = ValueNotifier<double>(0);
  final ValueNotifier<int?> _hover = ValueNotifier<int?>(null);
  final ValueNotifier<_HoverInfo?> _hoverInfo = ValueNotifier<_HoverInfo?>(null);
  final ValueNotifier<int?> _pinned = ValueNotifier<int?>(null);
  late final _Ranges _ranges;
  late final List<OrreryFinding> _findings;
  bool _playing = false;

  // Level of detail. The disk swaps between files and module super-nodes; the
  // module model is derived once on demand. Steps (and thus the scrubber,
  // meters, and findings) are level-independent, so only the disk + its
  // hit-testing read [_activeModel].
  OrreryLod _lod = OrreryLod.files;
  OrreryModel? _modulesCache;

  OrreryModel get _activeModel =>
      _lod == OrreryLod.modules ? _modules : widget.model;
  OrreryModel get _modules =>
      _modulesCache ??= OrreryModel.aggregateByModule(widget.model);
  bool get _canAggregate =>
      widget.model.nodes.length > OrreryModel.aggregationThreshold;

  // Scrub vs compare. The compare grid's milestones (genesis, regime/archetype
  // boundaries, head) are derived once — they're a property of history.
  OrreryMode _mode = OrreryMode.scrub;
  late final List<int> _milestones = _computeMilestones();

  double get _maxHead => widget.model.headPosition;
  OrreryStep _stepAt(double head) =>
      widget.model.steps[head.round().clamp(0, widget.model.stepCount - 1)];

  @override
  void initState() {
    super.initState();
    _ranges = _Ranges.of(widget.model);
    _findings = computeFindings(widget.model);
    // Lead with the aggregated view on large repos — a handful of modules reads
    // where thousands of file-dots fog out. An explicit initialLod overrides.
    _lod = widget.initialLod ??
        (_canAggregate ? OrreryLod.modules : OrreryLod.files);
    _mode = widget.initialMode ?? OrreryMode.scrub;
    _play = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    _head.value =
        (widget.initialHead ?? _maxHead).clamp(0.0, _maxHead); // open at present
    _pinned.value = widget.initialPinned;
    _play.addListener(() {
      _head.value = _play.value * _maxHead;
      if (_play.isCompleted && _playing) {
        setState(() => _playing = false);
      }
    });
  }

  @override
  void dispose() {
    _play.dispose();
    _head.dispose();
    _hover.dispose();
    _hoverInfo.dispose();
    _pinned.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_playing) {
      _play.stop();
      setState(() => _playing = false);
      return;
    }
    if (context.reduceMotionRead) {
      _head.value = _maxHead; // honour reduce-motion: jump, don't sweep
      return;
    }
    final from = (_head.value >= _maxHead - 1e-3) ? 0.0 : _head.value / _maxHead;
    _play.value = from;
    _play.duration = context.motionRead(const Duration(seconds: 9));
    _play.forward();
    setState(() => _playing = true);
  }

  void _scrubTo(double head) {
    if (_playing) {
      _play.stop();
      setState(() => _playing = false);
    }
    _head.value = head.clamp(0.0, _maxHead);
  }

  /// Switch level of detail. Node ids live in different spaces per level, so any
  /// pin/hover is cleared on the way across.
  void _setLod(OrreryLod lod) {
    if (_lod == lod) return;
    setState(() => _lod = lod);
    _pinned.value = null;
    _clearHover();
  }

  /// A finding was tapped: jump to its moment and pin the file it's about, so
  /// the disk lights up where that file is and traces where it's been. Findings
  /// point at real files, so drop to file level if we're aggregated.
  void _select(int step, int? nodeId) {
    setState(() {
      if (_lod != OrreryLod.files) _lod = OrreryLod.files;
      _mode = OrreryMode.scrub; // findings drill into the live disk
    });
    _scrubTo(step.toDouble());
    _pinned.value = nodeId;
  }

  void _setMode(OrreryMode mode) {
    if (_mode == mode) return;
    if (_playing) _play.stop();
    setState(() {
      _mode = mode;
      _playing = false;
    });
  }

  /// Tapping a compare-grid frame opens that moment in the live disk.
  void _openMilestone(int step) {
    setState(() => _mode = OrreryMode.scrub);
    _scrubTo(step.toDouble());
  }

  /// The moments worth comparing side-by-side: genesis, every regime change and
  /// archetype shift, and head — capped so the grid stays readable, with regime
  /// changes kept ahead of archetype shifts when trimming.
  List<int> _computeMilestones() {
    final steps = widget.model.steps;
    final n = steps.length;
    if (n == 0) return const <int>[];
    final last = n - 1;
    final regime = <int>[];
    final shift = <int>[];
    for (int i = 1; i < last; i++) {
      if (steps[i].regimeChange) {
        regime.add(i);
      } else if (steps[i].archetypeShift) {
        shift.add(i);
      }
    }
    const cap = 9; // genesis + head + up to 7 boundaries
    final mid = <int>[...regime];
    for (final s in shift) {
      if (mid.length >= cap - 2) break;
      mid.add(s);
    }
    final set = <int>{0, last, ...mid};
    // If history has few structural inflections, pad with evenly-spaced frames
    // so compare is still a useful filmstrip rather than just then-vs-now.
    const minFrames = 5;
    if (set.length < minFrames && last >= minFrames - 1) {
      for (int k = 1; k < minFrames - 1; k++) {
        set.add((last * k / (minFrames - 1)).round());
      }
    }
    return set.toList()..sort();
  }

  /// Short caption for a milestone — what changed at that step.
  String _milestoneLabel(int i) {
    final steps = widget.model.steps;
    if (i == 0) return 'genesis';
    if (i == steps.length - 1) return 'now';
    final s = steps[i];
    if (s.regimeChange) return 'reorganized';
    if (s.archetypeShift) return 'became ${s.archetype}';
    return s.archetype.isEmpty ? 'snapshot' : s.archetype;
  }

  /// A tap on the disk pins the nearest file, or clears the pin on empty space.
  void _tapDisk(Offset local, double side) {
    final double r = OrreryPainter.radiusFor(side);
    final Offset center = Offset(side / 2, side / 2);
    final double head = _head.value;
    int? best;
    double bestD = 13.0;
    for (final node in _activeModel.nodes) {
      final pos = OrreryModel.sampleNode(node, head);
      if (pos == null) continue;
      final screen = Offset(center.dx + pos.dx * r, center.dy + pos.dy * r);
      final d = (screen - local).distance;
      if (d < bestD) {
        bestD = d;
        best = node.id;
      }
    }
    _pinned.value = best;
  }

  void _updateHover(Offset local, double side) {
    final double r = OrreryPainter.radiusFor(side);
    final Offset center = Offset(side / 2, side / 2);
    final double head = _head.value;
    int? best;
    Offset? bestScreen;
    OrreryNode? bestNode;
    double bestD = 13.0; // px pick radius
    for (final node in _activeModel.nodes) {
      final pos = OrreryModel.sampleNode(node, head);
      if (pos == null) continue;
      final screen = Offset(center.dx + pos.dx * r, center.dy + pos.dy * r);
      final d = (screen - local).distance;
      if (d < bestD) {
        bestD = d;
        best = node.id;
        bestScreen = screen;
        bestNode = node;
      }
    }
    _hover.value = best;
    if (bestNode == null || bestScreen == null) {
      _hoverInfo.value = null;
    } else {
      final label = bestNode.memberCount > 1
          ? '${bestNode.path ?? 'module'} · ${bestNode.memberCount} files'
          : (bestNode.path ?? 'file #${bestNode.id}');
      _hoverInfo.value = _HoverInfo(bestScreen, label);
    }
  }

  void _clearHover() {
    _hover.value = null;
    _hoverInfo.value = null;
  }

  /// The pinned node's path + a plain-language account of *why it sits where it
  /// sits* — coupling-central vs peripheral, and which way it has drifted. No
  /// eigen-anything reaches the surface; this is the answer to "why is this
  /// file here?". Null when nothing is pinned / the pin is off-model.
  ({String path, String story})? _selectionInfo(int? pinned, double head) {
    if (pinned == null) return null;
    final nodes = _activeModel.nodes;
    if (pinned < 0 || pinned >= nodes.length) return null;
    final node = nodes[pinned];
    return (
      path: node.path ?? 'node #${node.id}',
      story: _positionStory(node, head),
    );
  }

  String _positionStory(OrreryNode node, double head) {
    final pos = OrreryModel.sampleNode(node, head);
    if (pos == null) return 'Not present at this point in history.';
    final double r = pos.distance.clamp(0.0, 1.0);

    double? birthR;
    for (final p in node.positions) {
      if (p != null) {
        birthR = p.distance.clamp(0.0, 1.0);
        break;
      }
    }

    final String role, coupling;
    if (r < 0.45) {
      role = 'Structurally central';
      coupling = 'co-changes with much of the system — high blast-radius';
    } else if (r > 0.72) {
      role = 'Peripheral';
      coupling = 'loosely coupled, mostly changes on its own';
    } else {
      role = 'Mid-structure';
      coupling = 'moderately coupled to the rest of the system';
    }

    String drift = '';
    if (birthR != null) {
      final d = r - birthR;
      if (d > 0.15) {
        drift = ' Drifted outward over its history — decoupling.';
      } else if (d < -0.15) {
        drift = ' Moved inward over its history — integrating.';
      } else {
        drift = ' Held its position through history.';
      }
    }
    return '$role — $coupling.$drift';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = OrreryColors.fromTokens(t);
    return Column(
      children: [
        ValueListenableBuilder<double>(
          valueListenable: _head,
          builder: (_, head, __) => _OrreryHeader(
            repoLabel: widget.repoLabel,
            step: _stepAt(head),
            index: head.round(),
            total: widget.model.stepCount,
            mode: _mode,
            onMode: _setMode,
            lod: _lod,
            onLod: _setLod,
            showLodToggle: _canAggregate,
            onClose: widget.onClose,
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _mode == OrreryMode.scrub
                    ? _buildDisk(colors)
                    : _buildCompare(colors),
              ),
              ValueListenableBuilder<double>(
                valueListenable: _head,
                builder: (_, head, __) => ValueListenableBuilder<int?>(
                  valueListenable: _pinned,
                  builder: (_, pinned, __) => _OrreryRail(
                    model: widget.model,
                    step: _stepAt(head),
                    index: head.round(),
                    ranges: _ranges,
                    findings: _findings,
                    onSelect: _select,
                    selection: _selectionInfo(pinned, head),
                    onClearSelection: () => _pinned.value = null,
                  ),
                ),
              ),
            ],
          ),
        ),
        // The compare grid is its own timeline, so the scrubber belongs to scrub.
        if (_mode == OrreryMode.scrub)
          _OrreryScrubber(
            model: widget.model,
            head: _head,
            playing: _playing,
            onTogglePlay: _togglePlay,
            onScrub: _scrubTo,
          ),
      ],
    );
  }

  /// Compare mode: static small-multiples of the structure at each milestone,
  /// for side-by-side analysis (what animation can't do well). Tapping a frame
  /// opens that moment in the live disk.
  Widget _buildCompare(OrreryColors colors) {
    return _OrreryCompare(
      model: _activeModel,
      milestones: _milestones,
      colors: colors,
      labelOf: _milestoneLabel,
      stepOf: (i) => widget.model.steps[i],
      onOpen: _openMilestone,
    );
  }

  Widget _buildDisk(OrreryColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 10),
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, c) {
              final side = math.min(c.maxWidth, c.maxHeight);
              return MouseRegion(
                onHover: (e) => _updateHover(e.localPosition, side),
                onExit: (_) => _clearHover(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (e) => _tapDisk(e.localPosition, side),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_head, _hover, _pinned]),
                          builder: (_, __) => CustomPaint(
                            painter: OrreryPainter(
                              model: _activeModel,
                              head: _head.value,
                              colors: colors,
                              highlightId: _hover.value,
                              pinnedId: _pinned.value,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 10,
                        bottom: 8,
                        child: _DiskLegend(),
                      ),
                      ValueListenableBuilder<_HoverInfo?>(
                        valueListenable: _hoverInfo,
                        builder: (_, info, __) {
                          if (info == null) return const SizedBox.shrink();
                          return Positioned(
                            left: math.min(info.pos.dx + 12, side - 140),
                            top: math.max(info.pos.dy - 10, 0),
                            child: _NodeTooltip(label: info.label),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OrreryHeader extends StatelessWidget {
  final String repoLabel;
  final OrreryStep step;
  final int index;
  final int total;
  final OrreryMode mode;
  final ValueChanged<OrreryMode> onMode;
  final OrreryLod lod;
  final ValueChanged<OrreryLod> onLod;
  final bool showLodToggle;
  final VoidCallback? onClose;
  const _OrreryHeader({
    required this.repoLabel,
    required this.step,
    required this.index,
    required this.total,
    required this.mode,
    required this.onMode,
    required this.lod,
    required this.onLod,
    required this.showLodToggle,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Text('Orrery',
              style: TextStyle(
                color: t.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              )),
          const SizedBox(width: 10),
          if (repoLabel.isNotEmpty)
            Text(repoLabel,
                style: TextStyle(color: t.textFaint, fontSize: 12)),
          const SizedBox(width: 14),
          _SegToggle<OrreryMode>(
            value: mode,
            options: const [
              ('Scrub', OrreryMode.scrub),
              ('Compare', OrreryMode.compare),
            ],
            onChanged: onMode,
          ),
          if (showLodToggle) ...[
            const SizedBox(width: 8),
            _SegToggle<OrreryLod>(
              value: lod,
              options: const [
                ('Modules', OrreryLod.modules),
                ('Files', OrreryLod.files),
              ],
              onChanged: onLod,
            ),
          ],
          const Spacer(),
          // Where you are in history.
          Text('${index + 1}',
              style: TextStyle(
                  color: t.textStrong,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text(' / $total',
              style: TextStyle(color: t.textFaint, fontSize: 12)),
          const SizedBox(width: 12),
          Text(step.shortSha,
              style: TextStyle(
                color: t.textMuted,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(width: 8),
          Text(_fmtDate(step.date),
              style: TextStyle(color: t.textFaint, fontSize: 12)),
          const SizedBox(width: 12),
          if (onClose != null) _CloseChip(onTap: onClose!),
        ],
      ),
    );
  }
}

/// A compact two-or-more-state segmented switch. Used for the level-of-detail
/// (Modules/Files) and view-mode (Scrub/Compare) toggles.
class _SegToggle<T> extends StatelessWidget {
  final T value;
  final List<(String, T)> options;
  final ValueChanged<T> onChanged;
  const _SegToggle({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 24,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.surface1.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, v) in options) _seg(context, label, v),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, T v) {
    final t = context.tokens;
    final bool on = value == v;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? t.itemActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? t.textStrong : t.textMuted,
            fontSize: 11,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _CloseChip extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(Icons.close_rounded, size: 16, color: t.textMuted),
      ),
    );
  }
}

/// A whisper-faint key for the radial axis: centre = coupling-central, edge =
/// peripheral. The only persistent annotation on the disk — the rest of the
/// "why is it here" answer is on-demand in the selection card.
class _DiskLegend extends StatelessWidget {
  const _DiskLegend();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget row({required bool filled, required String label}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? t.hyperCore.withValues(alpha: 0.85)
                    : Colors.transparent,
                border: filled
                    ? null
                    : Border.all(color: t.textFaint.withValues(alpha: 0.7)),
              ),
            ),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(color: t.textFaint, fontSize: 10)),
          ],
        );
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(filled: true, label: 'central'),
          const SizedBox(height: 5),
          row(filled: false, label: 'peripheral'),
        ],
      ),
    );
  }
}

class _NodeTooltip extends StatelessWidget {
  final String label;
  const _NodeTooltip({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: t.bg2.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: t.chromeBorder.withValues(alpha: 0.7)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.textNormal,
            fontSize: 11,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _OrreryRail extends StatelessWidget {
  final OrreryModel model;
  final OrreryStep step;
  final int index;
  final _Ranges ranges;
  final List<OrreryFinding> findings;
  final void Function(int step, int? nodeId) onSelect;
  final ({String path, String story})? selection;
  final VoidCallback onClearSelection;
  const _OrreryRail({
    required this.model,
    required this.step,
    required this.index,
    required this.ranges,
    required this.findings,
    required this.onSelect,
    required this.selection,
    required this.onClearSelection,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 250,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: t.chromeBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selection != null) ...[
            _SelectionCard(
              path: selection!.path,
              story: selection!.story,
              onClear: onClearSelection,
            ),
            const SizedBox(height: 20),
          ],
          const _RailLabel('STRUCTURE'),
          const SizedBox(height: 7),
          Text(
            step.archetype.isEmpty ? 'forming…' : step.archetype,
            style: TextStyle(
              color: t.accentBright,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 9),
          _Meter(
            label: 'canonical',
            value: step.canonicality,
            color: t.accentBright,
          ),
          const SizedBox(height: 20),
          const _RailLabel('FIELD'),
          const SizedBox(height: 9),
          _Meter(
            label: 'connectivity',
            value: _Ranges.norm(step.gap, ranges.gapLo, ranges.gapHi),
            trailing: step.gap.toStringAsFixed(3),
            color: t.textNormal,
          ),
          const SizedBox(height: 8),
          _Meter(
            label: 'rigidity',
            value: _Ranges.norm(step.rigidity, ranges.rigLo, ranges.rigHi),
            trailing: step.rigidity.toStringAsFixed(3),
            color: t.textNormal,
          ),
          const SizedBox(height: 8),
          _Meter(
            label: 'entropy',
            value: _Ranges.norm(step.vonNeumann, ranges.vnLo, ranges.vnHi),
            trailing: step.vonNeumann.toStringAsFixed(2),
            color: t.textNormal,
          ),
          const SizedBox(height: 20),
          const _RailLabel('FINDINGS'),
          const SizedBox(height: 8),
          Expanded(
            child: findings.isEmpty
                ? Text('No structural events detected in this history.',
                    style: TextStyle(
                        color: t.textFaint, fontSize: 11.5, height: 1.3))
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: findings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, k) {
                      final f = findings[k];
                      return _FindingCard(
                        finding: f,
                        active: f.stepIndex == index,
                        onTap: () => onSelect(f.stepIndex, f.nodeId),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FindingCard extends StatelessWidget {
  final OrreryFinding finding;
  final bool active;
  final VoidCallback onTap;
  const _FindingCard({
    required this.finding,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final Color accent = switch (finding.kind) {
      OrreryFindingKind.hub => t.accentBright,
      OrreryFindingKind.driftOut => t.stateModified,
      OrreryFindingKind.driftIn => t.stateAdded,
      OrreryFindingKind.tangle => t.stateModified,
      OrreryFindingKind.clarify => t.stateAdded,
      OrreryFindingKind.regime => t.accentBright,
      OrreryFindingKind.thrash => t.stateModified,
      OrreryFindingKind.reshuffle => t.accentBright,
      OrreryFindingKind.forecast => t.stateModified,
    };
    final IconData icon = switch (finding.kind) {
      OrreryFindingKind.hub => Icons.adjust_rounded,
      OrreryFindingKind.driftOut => Icons.call_made_rounded,
      OrreryFindingKind.driftIn => Icons.call_received_rounded,
      OrreryFindingKind.tangle => Icons.warning_amber_rounded,
      OrreryFindingKind.clarify => Icons.auto_awesome_rounded,
      OrreryFindingKind.regime => Icons.bolt_rounded,
      OrreryFindingKind.thrash => Icons.sync_problem_rounded,
      OrreryFindingKind.reshuffle => Icons.shuffle_rounded,
      OrreryFindingKind.forecast => Icons.trending_down_rounded,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        decoration: BoxDecoration(
          color: active
              ? t.itemActiveBg.withValues(alpha: 0.55)
              : t.surface1.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? accent.withValues(alpha: 0.5)
                : t.chromeBorder.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: accent.withValues(alpha: 0.95)),
                const SizedBox(width: 6),
                Text(finding.anchor,
                    style: TextStyle(
                      color: t.textFaint,
                      fontSize: 10.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ],
            ),
            const SizedBox(height: 6),
            Text(finding.headline,
                style: TextStyle(
                  color: active ? t.textStrong : t.textNormal,
                  fontSize: 12,
                  height: 1.32,
                )),
          ],
        ),
      ),
    );
  }
}

/// The inspector for a pinned file/module: its name and a plain-language
/// account of where it sits and how it has drifted (P1 #9 — "why is it here?").
class _SelectionCard extends StatelessWidget {
  final String path;
  final String story;
  final VoidCallback onClear;
  const _SelectionCard({
    required this.path,
    required this.story,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 9, 9, 11),
      decoration: BoxDecoration(
        color: t.itemActiveBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.accentBright.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _RailLabel('SELECTED'),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Icon(Icons.close_rounded, size: 14, color: t.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            _shortPath(path),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            story,
            style: TextStyle(color: t.textNormal, fontSize: 11.5, height: 1.34),
          ),
        ],
      ),
    );
  }
}

class _RailLabel extends StatelessWidget {
  final String text;
  const _RailLabel(this.text);
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: TextStyle(
        color: t.textFaint,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final String label;
  final double value; // 0..1
  final String? trailing;
  final Color color;
  const _Meter({
    required this.label,
    required this.value,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(color: t.textMuted, fontSize: 11.5)),
            ),
            if (trailing != null)
              Text(trailing!,
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                Positioned.fill(
                  child:
                      ColoredBox(color: t.chromeBorder.withValues(alpha: 0.45)),
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(0.0, 1.0),
                  child: ColoredBox(color: color.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The compare surface: a grid of static disk snapshots at each milestone, for
/// side-by-side structural comparison. Each frame opens that moment on tap.
class _OrreryCompare extends StatelessWidget {
  final OrreryModel model;
  final List<int> milestones;
  final OrreryColors colors;
  final String Function(int) labelOf;
  final OrreryStep Function(int) stepOf;
  final ValueChanged<int> onOpen;
  const _OrreryCompare({
    required this.model,
    required this.milestones,
    required this.colors,
    required this.labelOf,
    required this.stepOf,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (milestones.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols =
              math.min((c.maxWidth / 290).floor().clamp(1, 4), milestones.length);
          return GridView.count(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.84,
            children: <Widget>[
              for (final i in milestones)
                _CompareCard(
                  model: model,
                  step: i,
                  stepData: stepOf(i),
                  label: labelOf(i),
                  colors: colors,
                  onTap: () => onOpen(i),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  final OrreryModel model;
  final int step;
  final OrreryStep stepData;
  final String label;
  final OrreryColors colors;
  final VoidCallback onTap;
  const _CompareCard({
    required this.model,
    required this.step,
    required this.stepData,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: t.chromeBorder.withValues(alpha: 0.5)),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                painter: OrreryPainter(
                  model: model,
                  head: step.toDouble(),
                  colors: colors,
                  trailSteps: 2,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text('${step + 1}',
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const SizedBox(width: 7),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textNormal, fontSize: 11.5)),
              ),
              const SizedBox(width: 6),
              Text(_fmtDate(stepData.date),
                  style: TextStyle(color: t.textFaint, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrreryScrubber extends StatelessWidget {
  final OrreryModel model;
  final ValueNotifier<double> head;
  final bool playing;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onScrub;
  const _OrreryScrubber({
    required this.model,
    required this.head,
    required this.playing,
    required this.onTogglePlay,
    required this.onScrub,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = _ScrubberColors.fromTokens(t);
    final genesis = _fmtDate(model.steps.first.date);
    final present = _fmtDate(model.steps.last.date);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _PlayButton(playing: playing, onTap: onTogglePlay),
              const SizedBox(width: 14),
              SizedBox(
                width: 78,
                child: Text('connectivity',
                    style: TextStyle(color: t.textFaint, fontSize: 10.5)),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final maxHead = model.headPosition;
                    void handle(double dx) {
                      if (maxHead <= 0 || w <= 0) return;
                      onScrub((dx / w) * maxHead);
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => handle(d.localPosition.dx),
                      onHorizontalDragStart: (d) => handle(d.localPosition.dx),
                      onHorizontalDragUpdate: (d) => handle(d.localPosition.dx),
                      child: SizedBox(
                        height: 44,
                        child: ValueListenableBuilder<double>(
                          valueListenable: head,
                          builder: (_, h, __) => CustomPaint(
                            painter: _ScrubberPainter(
                              model: model,
                              head: h,
                              colors: colors,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 138),
            child: Row(
              children: [
                Text(genesis,
                    style: TextStyle(color: t.textFaint, fontSize: 10)),
                const Spacer(),
                Text(present,
                    style: TextStyle(color: t.textFaint, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.surface1.withValues(alpha: 0.6),
          border: Border.all(color: t.chromeBorder.withValues(alpha: 0.7)),
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 19,
          color: t.textNormal,
        ),
      ),
    );
  }
}

class _ScrubberColors {
  final Color track;
  final Color spark;
  final Color sparkFill;
  final Color regime;
  final Color archetype;
  final Color playhead;
  const _ScrubberColors({
    required this.track,
    required this.spark,
    required this.sparkFill,
    required this.regime,
    required this.archetype,
    required this.playhead,
  });

  factory _ScrubberColors.fromTokens(AppTokens t) => _ScrubberColors(
        track: t.chromeBorder,
        spark: t.textNormal,
        sparkFill: t.accentBright,
        regime: t.stateModified,
        archetype: t.accentBright,
        playhead: t.textStrong,
      );
}

/// The timeline: a sparkline of the spectral gap across history (the repo's
/// connectivity terrain), with regime changes and archetype shifts flagged,
/// and the scrub playhead.
class _ScrubberPainter extends CustomPainter {
  final OrreryModel model;
  final double head;
  final _ScrubberColors colors;

  _ScrubberPainter({
    required this.model,
    required this.head,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || model.stepCount < 2) return;
    final int n = model.stepCount;
    final double w = size.width;
    final double h = size.height;

    double xOf(int i) => n == 1 ? 0 : i / (n - 1) * w;

    double lo = double.infinity, hi = -double.infinity;
    for (final s in model.steps) {
      lo = math.min(lo, s.gap);
      hi = math.max(hi, s.gap);
    }
    final double span = (hi - lo).abs() < 1e-9 ? 1.0 : (hi - lo);
    double yOf(double gap) => h * 0.86 - ((gap - lo) / span) * (h * 0.64);

    // Sparkline + soft fill underneath.
    final Path line = Path();
    final Path fill = Path()..moveTo(0, h);
    for (int i = 0; i < n; i++) {
      final p = Offset(xOf(i), yOf(model.steps[i].gap));
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
      }
      fill.lineTo(p.dx, p.dy);
    }
    fill
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = colors.sparkFill.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = colors.spark.withValues(alpha: 0.85),
    );

    // Regime changes (notches w/ a top dot) and archetype shifts (diamonds).
    for (int i = 0; i < n; i++) {
      final s = model.steps[i];
      final x = xOf(i);
      if (s.regimeChange) {
        canvas.drawLine(
          Offset(x, h * 0.12),
          Offset(x, h * 0.9),
          Paint()
            ..color = colors.regime.withValues(alpha: 0.6)
            ..strokeWidth = 1.4,
        );
        canvas.drawCircle(Offset(x, h * 0.12), 2.2,
            Paint()..color = colors.regime.withValues(alpha: 0.9));
      }
      if (s.archetypeShift) {
        _diamond(canvas, Offset(x, yOf(s.gap)), 3.2,
            Paint()..color = colors.archetype.withValues(alpha: 0.95));
      }
    }

    // Playhead.
    final double px = (head / model.headPosition).clamp(0.0, 1.0) * w;
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, h),
      Paint()
        ..color = colors.playhead.withValues(alpha: 0.9)
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(
      Offset(px, yOf(model.steps[head.round().clamp(0, n - 1)].gap)),
      3.6,
      Paint()..color = colors.playhead,
    );
  }

  void _diamond(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.head != head || old.model != model;
}

/// Last two path segments — enough to identify a file/module without the full
/// prefix. '(root)' and other bare labels pass through unchanged.
String _shortPath(String path) {
  final segs = path.split('/');
  if (segs.length <= 2) return path;
  return segs.sublist(segs.length - 2).join('/');
}

String _fmtDate(DateTime? d) {
  if (d == null) return '—';
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}
