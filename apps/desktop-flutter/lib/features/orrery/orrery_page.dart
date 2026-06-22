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

class OrreryView extends StatefulWidget {
  final OrreryModel model;
  final String repoLabel;
  final VoidCallback? onClose;

  /// Scrub position to open on; defaults to the present (head of history).
  final double? initialHead;

  const OrreryView({
    super.key,
    required this.model,
    this.repoLabel = '',
    this.onClose,
    this.initialHead,
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
  late final _Ranges _ranges;
  late final List<OrreryFinding> _findings;
  bool _playing = false;

  double get _maxHead => widget.model.headPosition;
  OrreryStep _stepAt(double head) =>
      widget.model.steps[head.round().clamp(0, widget.model.stepCount - 1)];

  @override
  void initState() {
    super.initState();
    _ranges = _Ranges.of(widget.model);
    _findings = computeFindings(widget.model);
    _play = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    _head.value =
        (widget.initialHead ?? _maxHead).clamp(0.0, _maxHead); // open at present
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

  void _updateHover(Offset local, double side) {
    final double r = OrreryPainter.radiusFor(side);
    final Offset center = Offset(side / 2, side / 2);
    final double head = _head.value;
    int? best;
    Offset? bestScreen;
    double bestD = 13.0; // px pick radius
    for (final node in widget.model.nodes) {
      final pos = OrreryModel.sampleNode(node, head);
      if (pos == null) continue;
      final screen = Offset(center.dx + pos.dx * r, center.dy + pos.dy * r);
      final d = (screen - local).distance;
      if (d < bestD) {
        bestD = d;
        best = node.id;
        bestScreen = screen;
      }
    }
    _hover.value = best;
    if (best == null || bestScreen == null) {
      _hoverInfo.value = null;
    } else {
      final node = widget.model.nodes[best];
      _hoverInfo.value = _HoverInfo(bestScreen, node.path ?? 'file #${node.id}');
    }
  }

  void _clearHover() {
    _hover.value = null;
    _hoverInfo.value = null;
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
            onClose: widget.onClose,
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildDisk(colors)),
              ValueListenableBuilder<double>(
                valueListenable: _head,
                builder: (_, head, __) => _OrreryRail(
                  model: widget.model,
                  step: _stepAt(head),
                  index: head.round(),
                  ranges: _ranges,
                  findings: _findings,
                  onJump: (i) => _scrubTo(i.toDouble()),
                ),
              ),
            ],
          ),
        ),
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
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_head, _hover]),
                        builder: (_, __) => CustomPaint(
                          painter: OrreryPainter(
                            model: widget.model,
                            head: _head.value,
                            colors: colors,
                            highlightId: _hover.value,
                          ),
                          size: Size.infinite,
                        ),
                      ),
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
  final VoidCallback? onClose;
  const _OrreryHeader({
    required this.repoLabel,
    required this.step,
    required this.index,
    required this.total,
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
  final ValueChanged<int> onJump;
  const _OrreryRail({
    required this.model,
    required this.step,
    required this.index,
    required this.ranges,
    required this.findings,
    required this.onJump,
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
                        onTap: () => onJump(f.stepIndex),
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
      OrreryFindingKind.identity => t.accentBright,
    };
    final IconData icon = switch (finding.kind) {
      OrreryFindingKind.hub => Icons.adjust_rounded,
      OrreryFindingKind.driftOut => Icons.call_made_rounded,
      OrreryFindingKind.driftIn => Icons.call_received_rounded,
      OrreryFindingKind.tangle => Icons.warning_amber_rounded,
      OrreryFindingKind.clarify => Icons.auto_awesome_rounded,
      OrreryFindingKind.regime => Icons.bolt_rounded,
      OrreryFindingKind.identity => Icons.change_history_rounded,
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

String _fmtDate(DateTime? d) {
  if (d == null) return '—';
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}
