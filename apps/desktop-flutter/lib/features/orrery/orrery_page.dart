import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/spectral_trajectory_builder.dart';
import '../../i18n/gen/strings.g.dart';
import '../../ui/control_chrome.dart';
import '../../ui/design_primitives.dart';
import '../../ui/interaction_feedback.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import 'orrery_findings.dart';
import 'orrery_model.dart';
import 'orrery_painter.dart';
import 'orrery_rail.dart';
import 'orrery_timeline.dart';

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
              message: context.t.orrery.status.loading,
              onClose: () => Navigator.of(context).pop(),
            );
          }
          if (snap.hasError) {
            return _OrreryStatus(
              message: context.t.orrery.status.loadError,
              detail: '${snap.error}',
              onClose: () => Navigator.of(context).pop(),
            );
          }
          final model = snap.data ?? OrreryModel.emptyModel;
          if (model.stepCount < 2) {
            return _OrreryStatus(
              message: context.t.orrery.status.notEnoughHistory,
              detail: context.t.orrery.status.notEnoughHistoryDetail,
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

/// The observatory console over a ready [OrreryModel]: the Poincaré disk holds
/// the centre, the [OrreryRail] instrument column reads out structure and
/// findings on the right, and the [OrreryTimeline] spine along the bottom
/// carries the scrub, the commit readout, and event markers. This class owns
/// only the state orchestration (scrub/play, level of detail, mode, pin/hover)
/// and the disk; the spine and column are their own widgets.
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

  /// Module label to open drilled-in (forces module LOD). For deep-links/tests.
  final String? initialExpand;

  const OrreryView({
    super.key,
    required this.model,
    this.repoLabel = '',
    this.onClose,
    this.initialHead,
    this.initialPinned,
    this.initialLod,
    this.initialMode,
    this.initialExpand,
  });

  @override
  State<OrreryView> createState() => _OrreryViewState();
}

class _OrreryViewState extends State<OrreryView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _play;
  final ValueNotifier<double> _head = ValueNotifier<double>(0);
  final ValueNotifier<int?> _hover = ValueNotifier<int?>(null);
  final ValueNotifier<_HoverInfo?> _hoverInfo =
      ValueNotifier<_HoverInfo?>(null);
  final ValueNotifier<int?> _pinned = ValueNotifier<int?>(null);

  /// Shared cross-highlight channel: a finding index that both the rail rows and
  /// the timeline markers light up on, so hovering one echoes on the other.
  final ValueNotifier<int?> _hoveredFinding = ValueNotifier<int?>(null);
  late List<OrreryFinding> _findings;
  StreamSubscription<AppLocale>? _findingsLocaleSub;
  bool _playing = false;

  // Level of detail. The disk swaps between files and module super-nodes; the
  // module model is derived once on demand. Steps (and thus the timeline and
  // findings) are level-independent, so only the disk + its hit-testing read
  // [_activeModel].
  OrreryLod _lod = OrreryLod.files;
  String? _expandedModule; // the drilled-in module (modules LOD only)
  OrreryModel? _modulesCache;
  String? _expandedKey;
  OrreryModel? _expandedCache;

  OrreryModel get _activeModel {
    if (_lod != OrreryLod.modules) return widget.model;
    final ex = _expandedModule;
    if (ex == null) return _modules;
    if (_expandedKey != ex) {
      _expandedKey = ex;
      _expandedCache = OrreryModel.aggregateByModule(widget.model, expand: ex);
    }
    return _expandedCache!;
  }

  OrreryModel get _modules =>
      _modulesCache ??= OrreryModel.aggregateByModule(widget.model);
  bool get _canAggregate =>
      widget.model.nodes.length > OrreryModel.aggregationThreshold;

  // Scrub vs compare. The compare grid's milestones (genesis, regime/archetype
  // boundaries, head) are derived once — they're a property of history.
  OrreryMode _mode = OrreryMode.scrub;
  late final List<int> _milestones = _computeMilestones();

  // Compare-mode frame selection (milestone steps, selection order, max two).
  // Two selected frames open the A/B bench. A task posture, never persisted —
  // cleared on any route out of compare.
  final List<int> _compareSel = <int>[];

  double get _maxHead => widget.model.headPosition;

  @override
  void initState() {
    super.initState();
    _findings = computeFindings(widget.model);
    // The findings ledger (rail) and timeline markers bake translated strings,
    // so re-derive them on a live locale switch. The surrounding chrome is
    // already reactive via context.t; only this cached list needs the nudge.
    _findingsLocaleSub = LocaleSettings.getLocaleStream().listen((_) {
      if (mounted) {
        setState(() => _findings = computeFindings(widget.model));
      }
    });
    // Lead with the aggregated view on large repos — a handful of modules reads
    // where thousands of file-dots fog out. An explicit initialLod overrides.
    _lod = widget.initialLod ??
        (_canAggregate ? OrreryLod.modules : OrreryLod.files);
    _mode = widget.initialMode ?? OrreryMode.scrub;
    if (widget.initialExpand != null) {
      _expandedModule = widget.initialExpand;
      _lod = OrreryLod.modules; // drill-in only means anything aggregated
    }
    _play = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    _head.value = (widget.initialHead ?? _maxHead)
        .clamp(0.0, _maxHead); // open at present
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
    _findingsLocaleSub?.cancel();
    _play.dispose();
    _head.dispose();
    _hover.dispose();
    _hoverInfo.dispose();
    _pinned.dispose();
    _hoveredFinding.dispose();
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
    final from =
        (_head.value >= _maxHead - 1e-3) ? 0.0 : _head.value / _maxHead;
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
  /// pin/hover is cleared on the way across, and any drill-in is collapsed.
  void _setLod(OrreryLod lod) {
    if (_lod == lod) return;
    setState(() {
      _lod = lod;
      _expandedModule = null;
    });
    _pinned.value = null;
    _clearHover();
  }

  /// A finding was tapped: jump to its moment and pin the file it's about, so
  /// the disk lights up where that file is and traces where it's been. Findings
  /// point at real files, so drop to file level if we're aggregated.
  void _select(int step, int? nodeId) {
    setState(() {
      if (_lod != OrreryLod.files) _lod = OrreryLod.files;
      _expandedModule = null;
      _mode = OrreryMode.scrub; // findings drill into the live disk
      _compareSel.clear();
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
      _compareSel.clear();
    });
    // The page owns the cross-highlight channel, so the page resets it when a
    // surface leaves: switching modes unmounts the timeline, and a hover it
    // set must not strand a lit rail row (a widget clearing shared state from
    // its own dispose would notify mid-teardown instead).
    _hoveredFinding.value = null;
  }

  /// Tapping a bench disk opens that moment in the live disk.
  void _openMilestone(int step) {
    setState(() {
      _mode = OrreryMode.scrub;
      _compareSel.clear();
    });
    _scrubTo(step.toDouble());
  }

  /// Toggle a compare frame in/out of the A/B pair. A third pick starts a
  /// fresh pair — the intent is clearly "compare something else now".
  void _toggleCompareFrame(int step) {
    setState(() {
      if (_compareSel.contains(step)) {
        _compareSel.remove(step);
      } else {
        if (_compareSel.length == 2) _compareSel.clear();
        _compareSel.add(step);
      }
    });
  }

  void _clearCompareSel() {
    if (_compareSel.isEmpty) return;
    setState(_compareSel.clear);
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
    if (i == 0) return context.t.orrery.milestone.genesis;
    if (i == steps.length - 1) return context.t.orrery.milestone.now;
    final s = steps[i];
    if (s.regimeChange) return context.t.orrery.milestone.reorganized;
    if (s.archetypeShift) {
      return context.t.orrery.milestone.becameArchetype(archetype: s.archetype);
    }
    return s.archetype.isEmpty ? context.t.orrery.milestone.snapshot : s.archetype;
  }

  /// A tap on the disk: drill into the nearest module, pin the nearest file, or
  /// — on empty space — collapse a drill-in / clear the pin.
  void _tapDisk(Offset local, double side) {
    final double r = OrreryPainter.radiusFor(side);
    final Offset center = Offset(side / 2, side / 2);
    final double head = _head.value;
    OrreryNode? best;
    double bestD = 13.0;
    for (final node in _activeModel.nodes) {
      final pos = OrreryModel.sampleNode(node, head);
      if (pos == null) continue;
      final screen = Offset(center.dx + pos.dx * r, center.dy + pos.dy * r);
      final d = (screen - local).distance;
      if (d < bestD) {
        bestD = d;
        best = node;
      }
    }
    if (best == null) {
      if (_expandedModule != null) setState(() => _expandedModule = null);
      _pinned.value = null;
      return;
    }
    if (best.isModule) {
      _pinned.value = null;
      _clearHover();
      setState(() => _expandedModule = best!.path);
      return;
    }
    _pinned.value = best.id;
  }

  void _collapseModule() {
    _pinned.value = null;
    _clearHover();
    setState(() => _expandedModule = null);
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
          ? context.t.orrery.node.moduleWithCount(
              path: bestNode.path ?? context.t.orrery.node.module,
              n: bestNode.memberCount)
          : (bestNode.path ??
              context.t.orrery.node.fileFallback(id: bestNode.id));
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
      path: node.path ?? context.t.orrery.node.nodeFallback(id: node.id),
      story: _positionStory(node, head),
    );
  }

  String _positionStory(OrreryNode node, double head) {
    final pos = OrreryModel.sampleNode(node, head);
    if (pos == null) return context.t.orrery.selection.notPresent;
    final double r = pos.distance.clamp(0.0, 1.0);

    double? birthR;
    for (final p in node.positions) {
      if (p != null) {
        birthR = p.distance.clamp(0.0, 1.0);
        break;
      }
    }

    final String role;
    if (r < 0.45) {
      role = context.t.orrery.selection.roleCentral;
    } else if (r > 0.72) {
      role = context.t.orrery.selection.rolePeripheral;
    } else {
      role = context.t.orrery.selection.roleMid;
    }

    String drift = '';
    if (birthR != null) {
      final d = r - birthR;
      if (d > 0.15) {
        drift = context.t.orrery.selection.driftOutward;
      } else if (d < -0.15) {
        drift = context.t.orrery.selection.driftInward;
      } else {
        drift = context.t.orrery.selection.driftHolding;
      }
    }
    return '$role$drift';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = OrreryColors.fromTokens(t);
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Column(
        children: [
          _OrreryHeader(
            repoLabel: widget.repoLabel,
            mode: _mode,
            onMode: _setMode,
            lod: _lod,
            onLod: _setLod,
            showLodToggle: _canAggregate,
            onClose: widget.onClose,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // Animate the explore↔analyze swap so it reads as one surface
                  // changing, not a hard cut. Motion honours the user's rate.
                  child: AnimatedSwitcher(
                    duration: context.motion(AppMotion.fade),
                    child: _mode == OrreryMode.scrub
                        ? KeyedSubtree(
                            key: const ValueKey('scrub'),
                            child: _buildDisk(colors))
                        : KeyedSubtree(
                            key: const ValueKey('compare'),
                            child: _buildCompare(colors)),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _head,
                  builder: (_, head, __) => ValueListenableBuilder<int?>(
                    valueListenable: _pinned,
                    builder: (_, pinned, __) => OrreryRail(
                      model: widget.model,
                      head: head,
                      findings: _findings,
                      onSelect: _select,
                      hoveredFinding: _hoveredFinding,
                      pinnedNodeId: pinned,
                      selection: _selectionInfo(pinned, head),
                      onClearSelection: () => _pinned.value = null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The compare grid carries its own milestone filmstrip, so the
          // timeline spine belongs to scrub mode.
          if (_mode == OrreryMode.scrub)
            OrreryTimeline(
              model: widget.model,
              head: _head,
              playing: _playing,
              onTogglePlay: _togglePlay,
              onScrub: _scrubTo,
              findings: _findings,
              hoveredFinding: _hoveredFinding,
              onSelectFinding: (i) {
                final f = _findings[i];
                _select(f.stepIndex, f.nodeId);
              },
            ),
        ],
      ),
    );
  }

  /// Keyboard: Esc closes, ←/→ step the scrub, Home/End jump to genesis/head,
  /// Space toggles play. Mirrors the reflexes a desktop user brings to a
  /// timeline.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      // Esc unwinds one layer at a time: an open A/B bench (or half-picked
      // pair) collapses back to the grid before Esc means "leave the Orrery".
      if (_mode == OrreryMode.compare && _compareSel.isNotEmpty) {
        _clearCompareSel();
        return KeyEventResult.handled;
      }
      if (widget.onClose != null) {
        widget.onClose!();
        return KeyEventResult.handled;
      }
    }
    if (_mode == OrreryMode.scrub) {
      if (key == LogicalKeyboardKey.arrowRight) {
        _scrubTo(
            (_head.value.round() + 1).clamp(0, _maxHead.round()).toDouble());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _scrubTo(
            (_head.value.round() - 1).clamp(0, _maxHead.round()).toDouble());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.home) {
        _scrubTo(0);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.end) {
        _scrubTo(_maxHead);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.space) {
        _togglePlay();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Compare mode: static small-multiples of the structure at each milestone.
  /// Picking two frames opens the A/B bench — the two moments large, with the
  /// scalar deltas and the files that moved most between them.
  Widget _buildCompare(OrreryColors colors) {
    return _OrreryCompare(
      model: _activeModel,
      fileModel: widget.model,
      milestones: _milestones,
      colors: colors,
      labelOf: _milestoneLabel,
      stepOf: (i) => widget.model.steps[i],
      selected: _compareSel,
      onToggle: _toggleCompareFrame,
      onClearSelection: _clearCompareSel,
      onOpen: _openMilestone,
      onPinMover: _select,
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
              // Cursor turns to a pointer over a node (a file to pin, or a
              // module to drill into), so the disk reads as interactive.
              return ValueListenableBuilder<int?>(
                valueListenable: _hover,
                builder: (_, hoverId, child) => MouseRegion(
                  cursor: hoverId != null
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  onHover: (e) => _updateHover(e.localPosition, side),
                  onExit: (_) => _clearHover(),
                  child: child,
                ),
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
                      if (_lod == OrreryLod.modules && _expandedModule != null)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: _ExpandBreadcrumb(
                            label: _shortPath(_expandedModule!),
                            onTap: _collapseModule,
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The slim console header: identity (title + repo) and the two mode switches
/// (explore↔analyze, modules↔files), nothing more. The commit readout now lives
/// on the timeline spine, so the header is static per mode/lod change.
class _OrreryHeader extends StatelessWidget {
  final String repoLabel;
  final OrreryMode mode;
  final ValueChanged<OrreryMode> onMode;
  final OrreryLod lod;
  final ValueChanged<OrreryLod> onLod;
  final bool showLodToggle;
  final VoidCallback? onClose;
  const _OrreryHeader({
    required this.repoLabel,
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
      child: LayoutBuilder(
        builder: (context, c) {
          // With the readout gone the header rarely crowds; a long repo name
          // ellipsises rather than pushing the toggles off-edge, and it drops
          // out entirely only on the narrowest windows.
          final bool showRepo = repoLabel.isNotEmpty && c.maxWidth > 560;
          return Row(
            children: [
              Text(context.t.orrery.header.title,
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  )),
              if (showRepo) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(repoLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textFaint, fontSize: 12)),
                ),
              ],
              const SizedBox(width: 14),
              _SegToggle<OrreryMode>(
                value: mode,
                options: [
                  (context.t.orrery.header.modeScrub, OrreryMode.scrub),
                  (context.t.orrery.header.modeCompare, OrreryMode.compare),
                ],
                onChanged: onMode,
              ),
              if (showLodToggle) ...[
                const SizedBox(width: 8),
                _SegToggle<OrreryLod>(
                  value: lod,
                  options: [
                    (context.t.orrery.header.lodModules, OrreryLod.modules),
                    (context.t.orrery.header.lodFiles, OrreryLod.files),
                  ],
                  onChanged: onLod,
                ),
              ],
              const Spacer(),
              if (onClose != null) _CloseChip(onTap: onClose!),
            ],
          );
        },
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
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.surface1.withValues(alpha: 0.5),
        borderRadius: AppRadii.smAll,
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

  // Each segment is a house ChromeButton in mode-button chrome: it owns the
  // active fill, the hover highlight, the click cursor, the per-theme tap
  // feedback, and snap-tier motion — so the toggle matches every other control.
  Widget _seg(BuildContext context, String label, T v) {
    final t = context.tokens;
    final bool on = value == v;
    return ChromeButton(
      onTap: () => onChanged(v),
      borderRadius: AppRadii.xsAll,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      chromeBuilder: ({required bool hovered, required bool pressed}) =>
          modeButtonChrome(t, hovered: hovered, pressed: pressed, active: on),
      child: Text(
        label,
        style: TextStyle(
          color: on ? t.textStrong : t.textMuted,
          fontSize: 11,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
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
    return ChromeButton(
      onTap: onTap,
      borderRadius: AppRadii.smAll,
      padding: const EdgeInsets.all(5),
      chromeBuilder: ({required bool hovered, required bool pressed}) =>
          ghostButtonChrome(t,
              hovered: hovered,
              pressed: pressed,
              enabled: true,
              baseBorderColor: Colors.transparent),
      child:
          Icon(Icons.close_rounded, size: AppIconSize.md, color: t.textMuted),
    );
  }
}

/// Shown while a module is drilled in: the focused module's name with a back
/// chevron. Tapping it (or empty space) collapses back to the full map. Floats
/// over the disk, so it keeps a resting fill for legibility and brightens on
/// hover (with the house cursor + per-theme tap feedback via HoverableTap).
class _ExpandBreadcrumb extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ExpandBreadcrumb({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return HoverableTap(
      onTap: onTap,
      borderRadius: AppRadii.smAll,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
        decoration: BoxDecoration(
          color: t.surface1.withValues(alpha: hovered ? 0.88 : 0.7),
          borderRadius: AppRadii.smAll,
          border: Border.all(
              color: t.chromeBorder.withValues(alpha: hovered ? 0.95 : 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chevron_left_rounded,
                size: AppIconSize.md,
                color: hovered ? t.textNormal : t.textMuted),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(color: t.textNormal, fontSize: 11.5)),
          ],
        ),
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
          row(filled: true, label: context.t.orrery.legend.central),
          const SizedBox(height: 5),
          row(filled: false, label: context.t.orrery.legend.peripheral),
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

/// The compare surface. A grid of static disk snapshots at each milestone for
/// triage; picking two frames (A, then B) opens the bench — both moments
/// large, the scalar deltas between them, and the files that moved most, each
/// drilling into the live disk pinned. Small multiples find the interesting
/// pair; the bench answers what changed.
class _OrreryCompare extends StatelessWidget {
  final OrreryModel model; // active LOD — what the disks draw
  final OrreryModel fileModel; // file-level — what the movers rank
  final List<int> milestones;
  final OrreryColors colors;
  final String Function(int) labelOf;
  final OrreryStep Function(int) stepOf;
  final List<int> selected; // 0–2 milestone steps, selection order
  final ValueChanged<int> onToggle;
  final VoidCallback onClearSelection;
  final ValueChanged<int> onOpen;
  final void Function(int step, int? nodeId) onPinMover;
  const _OrreryCompare({
    required this.model,
    required this.fileModel,
    required this.milestones,
    required this.colors,
    required this.labelOf,
    required this.stepOf,
    required this.selected,
    required this.onToggle,
    required this.onClearSelection,
    required this.onOpen,
    required this.onPinMover,
  });

  @override
  Widget build(BuildContext context) {
    if (milestones.isEmpty) return const SizedBox.shrink();
    final Widget surface;
    if (selected.length == 2) {
      // Chronological bench regardless of pick order — A is always earlier.
      final int a = math.min(selected[0], selected[1]);
      final int b = math.max(selected[0], selected[1]);
      surface = KeyedSubtree(
        key: const ValueKey('compare-bench'),
        child: _CompareBench(
          model: model,
          fileModel: fileModel,
          a: a,
          b: b,
          colors: colors,
          labelOf: labelOf,
          stepOf: stepOf,
          onClose: onClearSelection,
          onOpen: onOpen,
          onPinMover: onPinMover,
        ),
      );
    } else {
      surface = KeyedSubtree(
        key: const ValueKey('compare-grid'),
        child: _buildGrid(context),
      );
    }
    return AnimatedSwitcher(
      duration: context.motion(AppMotion.fade),
      child: surface,
    );
  }

  Widget _buildGrid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
      child: LayoutBuilder(
        builder: (context, c) {
          // Never fewer than two columns — a single-file compare grid can't
          // compare anything. Cards shrink before side-by-side gives way.
          final cols = math.min(
              (c.maxWidth / 240).floor().clamp(2, 4), milestones.length);
          return GridView.count(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.84,
            children: <Widget>[
              for (int k = 0; k < milestones.length; k++)
                _CompareCard(
                  key: ValueKey('compare-card-${milestones[k]}'),
                  model: model,
                  step: milestones[k],
                  stepData: stepOf(milestones[k]),
                  label: labelOf(milestones[k]),
                  colors: colors,
                  // Connectivity change since the previous milestone — the
                  // one-number orientation for "did anything happen here".
                  deltaGap: k == 0
                      ? null
                      : stepOf(milestones[k]).gap -
                          stepOf(milestones[k - 1]).gap,
                  badge: !selected.contains(milestones[k])
                      ? null
                      : (selected.indexOf(milestones[k]) == 0
                          ? context.t.orrery.compare.badgeA
                          : context.t.orrery.compare.badgeB),
                  onTap: () => onToggle(milestones[k]),
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
  final double? deltaGap;
  final String? badge; // 'A' / 'B' when part of the bench pair
  final VoidCallback onTap;
  const _CompareCard({
    super.key,
    required this.model,
    required this.step,
    required this.stepData,
    required this.label,
    required this.colors,
    required this.deltaGap,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bool picked = badge != null;
    return HoverableTap(
      onTap: onTap,
      borderRadius: AppRadii.baseAll,
      builder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: AppRadii.baseAll,
                color: hovered ? t.surface1.withValues(alpha: 0.25) : null,
                border: Border.all(
                  color: picked
                      ? t.accentBright.withValues(alpha: 0.8)
                      : t.chromeBorder.withValues(alpha: hovered ? 0.85 : 0.5),
                  width: picked ? AppBorderWidth.thin : AppBorderWidth.hairline,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
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
                  if (badge != null)
                    Positioned(
                      left: 7,
                      top: 7,
                      child: _BenchBadge(letter: badge!),
                    ),
                  if (deltaGap != null && deltaGap!.isFinite)
                    Positioned(
                      right: 8,
                      top: 7,
                      child: IgnorePointer(
                        child: Text(
                          _signedFixed(deltaGap!, 3),
                          style: TextStyle(
                            color: t.textFaint,
                            fontSize: 9.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                ],
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
                    style: TextStyle(
                        color: hovered ? t.textStrong : t.textNormal,
                        fontSize: 11.5)),
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

/// The A/B marker on a picked frame and on the bench captions.
class _BenchBadge extends StatelessWidget {
  final String letter;
  const _BenchBadge({required this.letter});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.accentBright.withValues(alpha: 0.9),
        borderRadius: AppRadii.xsAll,
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: t.bg0,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Two moments, large, and what changed between them: the scalar deltas and
/// the files that travelled furthest through the manifold. Tapping a disk
/// opens that moment in scrub; tapping a mover opens scrub at B with the file
/// pinned — the receipt behind the claim.
class _CompareBench extends StatelessWidget {
  final OrreryModel model;
  final OrreryModel fileModel;
  final int a;
  final int b;
  final OrreryColors colors;
  final String Function(int) labelOf;
  final OrreryStep Function(int) stepOf;
  final VoidCallback onClose;
  final ValueChanged<int> onOpen;
  final void Function(int step, int? nodeId) onPinMover;
  const _CompareBench({
    required this.model,
    required this.fileModel,
    required this.a,
    required this.b,
    required this.colors,
    required this.labelOf,
    required this.stepOf,
    required this.onClose,
    required this.onOpen,
    required this.onPinMover,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Source files first; when none survived both moments (a genesis→now
    // bench mostly compares against files born in between), docs/config
    // movers still beat an empty panel.
    var movers =
        OrreryModel.topMovers(fileModel, a, b, include: isCodeFilePath);
    if (movers.isEmpty) {
      movers = OrreryModel.topMovers(fileModel, a, b);
    }
    // Population delta: how many files exist at each moment. Movement is
    // only defined for files alive at both ends, so this row is what makes
    // a sparse movers list read as "the codebase grew", not "nothing moved".
    int aliveAt(int s) {
      int c = 0;
      for (final node in fileModel.nodes) {
        if (s < node.positions.length && node.positions[s] != null) c++;
      }
      return c;
    }

    final int filesDelta = aliveAt(b) - aliveAt(a);
    final sa = stepOf(a);
    final sb = stepOf(b);
    final diskA = _BenchDisk(
      model: model,
      step: a,
      stepData: sa,
      label: labelOf(a),
      badge: context.t.orrery.compare.badgeA,
      colors: colors,
      onTap: () => onOpen(a),
    );
    final diskB = _BenchDisk(
      model: model,
      step: b,
      stepData: sb,
      label: labelOf(b),
      badge: context.t.orrery.compare.badgeB,
      colors: colors,
      onTap: () => onOpen(b),
    );
    final header = Row(
      children: [
        _CompareLabel(context.t.orrery.compare.header),
        const Spacer(),
        ChromeButton(
          onTap: onClose,
          borderRadius: AppRadii.xsAll,
          padding: const EdgeInsets.all(3),
          chromeBuilder: ({required bool hovered, required bool pressed}) =>
              ghostButtonChrome(t,
                  hovered: hovered,
                  pressed: pressed,
                  enabled: true,
                  baseBorderColor: Colors.transparent),
          child: Icon(Icons.close_rounded,
              size: AppIconSize.xs, color: t.textMuted),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
      // Two shapes for the same content: a wide window earns the analysis
      // panel beside the disks; a narrow one stacks it underneath so the
      // disks — the point of the bench — never starve below legibility.
      child: LayoutBuilder(
        builder: (context, c) {
          final bool wide = c.maxWidth >= 760;
          if (wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: diskA),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 250,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ..._changeRows(context, t, sa, sb, filesDelta),
                            const SizedBox(height: 12),
                            _moversHeader(context, t, movers),
                            const SizedBox(height: 6),
                            Expanded(child: _moversList(context, t, movers)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: diskB),
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: diskA),
                    const SizedBox(width: 12),
                    Expanded(child: diskB),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 180,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _changeRows(context, t, sa, sb, filesDelta),
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _moversHeader(context, t, movers),
                          const SizedBox(height: 6),
                          Expanded(child: _moversList(context, t, movers)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _changeRows(BuildContext context, AppTokens t, OrreryStep sa,
      OrreryStep sb, int filesDelta) {
    Widget deltaRow(String label, String value) => Row(
          children: [
            Text(label, style: TextStyle(color: t.textMuted, fontSize: 11)),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
    String fixed(double d, int digits) =>
        d.isFinite ? _signedFixed(d, digits) : '—';
    final compare = context.t.orrery.compare;
    return [
      _CompareLabel(compare.change),
      const SizedBox(height: 6),
      deltaRow(
          compare.deltaFiles, filesDelta >= 0 ? '+$filesDelta' : '$filesDelta'),
      const SizedBox(height: 4),
      deltaRow(compare.deltaConnectivity, fixed(sb.gap - sa.gap, 3)),
      const SizedBox(height: 4),
      deltaRow(compare.deltaRigidity, fixed(sb.rigidity - sa.rigidity, 3)),
      const SizedBox(height: 4),
      deltaRow(compare.deltaEntropy, fixed(sb.vonNeumann - sa.vonNeumann, 2)),
    ];
  }

  Widget _moversHeader(
      BuildContext context, AppTokens t, List<OrreryMover> movers) {
    return Row(
      children: [
        _CompareLabel(context.t.orrery.compare.movers),
        if (movers.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text('${movers.length}',
              style: TextStyle(
                color: t.textFaint,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      ],
    );
  }

  Widget _moversList(
      BuildContext context, AppTokens t, List<OrreryMover> movers) {
    if (movers.isEmpty) {
      return Text(context.t.orrery.compare.noMovers,
          style: TextStyle(color: t.textFaint, fontSize: 11.5, height: 1.3));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int k = 0; k < movers.length; k++) ...[
            if (k > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Container(
                  height: 1,
                  color: t.chromeBorder.withValues(alpha: 0.25),
                ),
              ),
            _MoverRow(
              key: ValueKey('mover-${movers[k].id}'),
              mover: movers[k],
              onTap: () => onPinMover(b, movers[k].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _BenchDisk extends StatelessWidget {
  final OrreryModel model;
  final int step;
  final OrreryStep stepData;
  final String label;
  final String badge;
  final OrreryColors colors;
  final VoidCallback onTap;
  const _BenchDisk({
    required this.model,
    required this.step,
    required this.stepData,
    required this.label,
    required this.badge,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return HoverableTap(
      onTap: onTap,
      borderRadius: AppRadii.baseAll,
      builder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            // A square panel wherever the cell's proportions land — the disk
            // is a circle, and letting it float in a tall slab reads as lost.
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.baseAll,
                    border: Border.all(
                        color: t.chromeBorder
                            .withValues(alpha: hovered ? 0.85 : 0.5)),
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
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _BenchBadge(letter: badge),
              const SizedBox(width: 7),
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
                    style: TextStyle(
                        color: hovered ? t.textStrong : t.textNormal,
                        fontSize: 11.5)),
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

/// One mover in the bench ledger — flat, like the findings rail: the file that
/// travelled, how far, and which way. Click = scrub at B with it pinned.
class _MoverRow extends StatelessWidget {
  final OrreryMover mover;
  final VoidCallback onTap;
  const _MoverRow({super.key, required this.mover, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final path =
        mover.path ?? context.t.orrery.node.nodeFallback(id: mover.id);
    final segs = path.split('/');
    final filename = segs.isEmpty ? path : segs.last;
    final dir =
        segs.length > 1 ? segs.sublist(0, segs.length - 1).join('/') : '';
    final compare = context.t.orrery.compare;
    final String way = mover.radialDelta > 0.08
        ? compare.wayOutward
        : (mover.radialDelta < -0.08 ? compare.wayInward : compare.wayShifted);
    return HoverableTap(
      onTap: onTap,
      borderRadius: AppRadii.xsAll,
      builder: (context, hovered) => Container(
        decoration: BoxDecoration(
          color: hovered ? t.itemHoverBg : null,
          borderRadius: AppRadii.xsAll,
        ),
        padding: const EdgeInsets.fromLTRB(8, 5, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hovered ? t.textStrong : t.textNormal,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      )),
                ),
                const SizedBox(width: 6),
                Text(way, style: TextStyle(color: t.textMuted, fontSize: 10)),
                const SizedBox(width: 5),
                Text(mover.dist.toStringAsFixed(2),
                    style: TextStyle(
                      color: t.textFaint,
                      fontSize: 10,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ],
            ),
            if (dir.isNotEmpty)
              Text(dir,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: t.textFaint, fontSize: 9.5, height: 1.3)),
          ],
        ),
      ),
    );
  }
}

/// Section heading for the bench — same voice as the rail's labels.
class _CompareLabel extends StatelessWidget {
  final String text;
  const _CompareLabel(this.text);
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

/// Signed fixed-point ("+0.012" / "−0.034") so deltas read as changes, not
/// values. Zero keeps the plus — direction is what the column is about.
String _signedFixed(double v, int digits) =>
    v >= 0 ? '+${v.toStringAsFixed(digits)}' : v.toStringAsFixed(digits);

/// Last two path segments — enough to identify a file/module without the full
/// prefix. '(root)' and other bare labels pass through unchanged.
String _shortPath(String path) {
  final segs = path.split('/');
  if (segs.length <= 2) return path;
  return segs.sublist(segs.length - 2).join('/');
}

String _fmtDate(DateTime? d) {
  if (d == null) return '—';
  final m = t.common.time.monthAbbrevs;
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}
