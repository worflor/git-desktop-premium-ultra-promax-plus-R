// logos_diffusion_canvas.dart
//
// Visualisation of the relevance engine, driven by LogosVisBus events.
// Every element has a birth timestamp; intensity at time t is
// smoothstep((t - birth) / fadeMs). Layers persist once faded in.
//
// Node angles come from a deterministic FNV-1a hash of the path so the
// same file lands at the same θ every run — no force-directed solver.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../backend/logos_vis_events.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';

/// The review-loading visualisation. Replaces the old text block.
class LogosDiffusionCanvas extends StatefulWidget {
  final AppTokens tokens;

  final VoidCallback? onCancel;

  const LogosDiffusionCanvas({
    super.key,
    required this.tokens,
    this.onCancel,
  });

  @override
  State<LogosDiffusionCanvas> createState() => _LogosDiffusionCanvasState();
}

class _LogosDiffusionCanvasState extends State<LogosDiffusionCanvas>
    with SingleTickerProviderStateMixin, MotionLoopSync {
  late final AnimationController _ticker;

  @override
  List<AnimationController> get motionLoops => [_ticker];
  StreamSubscription<LogosVisEvent>? _sub;

  // Per-element birth timestamps in ms. -1 means unborn (envelope = 0).
  final Map<_Element, double> _birth = {
    for (final e in _Element.values) e: -1.0,
  };

  int? _sessionId;
  _Phase _phase = _Phase.resolving;
  int _nodeCount = 0;
  bool _cached = false;
  Map<String, double> _sourceWeights = const {};
  int _churn = 0;
  int _reseedIdeaCount = 0;
  int _reseedSemanticHits = 0;
  int _reseedWellExpansion = 0;
  // Muse-only: brainstorm-reshaped seed map stats. Non-zero counters
  // mean phase-2 fired a reseed wavefront.
  Map<String, double> _phi = const {};
  Map<String, String> _wellByPath = const {};
  // Derived from _phi + _wellByPath on LogosVisDiffusionComplete.
  // Precomputed here so the painter never sorts at 60fps.
  List<MapEntry<String, double>> _phiSortedDesc = const [];
  List<double> _phiValuesSortedAsc = const [];
  Map<String, ({double start, double span})> _wellLayout = const {};
  List<double> _hunkRankings = const [];
  int _hunksAdmitted = 0;
  int _hunksSkipped = 0;
  double _budgetFraction = 0.0;
  late final Stopwatch _clock;

  // Draggable beam tip — spring-damped return on release. Only the
  // tip moves; the rest of the scene stays fixed.
  Offset _tipDragOffset = Offset.zero;
  Offset _tipVelocity = Offset.zero;
  bool _tipDragging = false;
  double _lastTickMs = 0.0;
  // Set from the inner LayoutBuilder; read by Listener callbacks to
  // match hit-test coordinates against what the painter draws.
  Size _canvasSize = Size.zero;

  // Verlet rope between center and tip. Interior nodes lag under
  // motion and straighten under the restoring force in _stepRope.
  static const int _kRopeSegments = 14;
  List<Offset>? _ropePos;
  List<Offset>? _ropePrev;

  // Per-source-spoke drag state. Each source file in `_sourceWeights`
  // can be independently grabbed by the user and pulled; the spring
  // pulls it home on release. The max magnitude of each pull is
  // published to the bus as a "user seed boost" that muse's reseed
  // pipeline reads before the second diffusion — so yanking a file
  // during dreaming actually biases the synthesis context.
  final Map<String, Offset> _spokeDrag = {};
  final Map<String, Offset> _spokeVel = {};
  String? _activeSpokeDrag;

  // Attention concentration derived from the φ distribution after
  // diffusion — 0 = perfectly flat, 1 = one node dominates. Feeds
  // the tip spring (concentrated → stiff, broad → soft) and the
  // pull clamp (concentrated → tight arc, broad → wide arc). 0.5
  // is the neutral default while φ hasn't landed yet.
  double _attentionConcentration = 0.5;

  @override
  void initState() {
    super.initState();
    _clock = Stopwatch()..start();
    // Starfield fades in immediately so the canvas is never empty
    // while waiting for the resolver event.
    _birth[_Element.starfield] = 0.0;
    // Ticker drives setState; all motion is clocked off _clock.
    // MotionLoopSync starts `.repeat()` in didChangeDependencies and
    // stops it when reduce-motion is on / the window loses focus.
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )
      ..addListener(() {
        final now = _clock.elapsedMilliseconds.toDouble();
        // dt clamped on BOTH ends:
        //   • lower bound guards a negative dt (clock rewind during
        //     rebuilds, unlikely but not impossible on DST transitions).
        //   • upper bound caps long gaps — a theme rebuild can pause
        //     the ticker for 100+ms; an uncapped dt spike would whip
        //     the tip spring into oscillation or drive the rope
        //     constraints into NaN territory.
        double dt;
        if (_lastTickMs == 0 || !_lastTickMs.isFinite) {
          dt = 0.016;
        } else {
          dt = (now - _lastTickMs) / 1000.0;
          if (!dt.isFinite || dt < 0) dt = 0.016;
          if (dt > 1 / 30.0) dt = 1 / 30.0;
        }
        _lastTickMs = now;
        _stepTipPhysics(dt);
        _stepSpokePhysics(dt);
        _stepRopeFromLayout(dt);
        if (mounted) setState(() {});
      });
    _sub = LogosVisBus.instance.stream.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onEvent(LogosVisEvent event) {
    // A newer session id means the previous review was superseded.
    // Drop accumulated state and restart birth times.
    if (_sessionId == null || event.sessionId > _sessionId!) {
      _sessionId = event.sessionId;
      _sourceWeights = const {};
      _phi = const {};
      _wellByPath = const {};
      _phiSortedDesc = const [];
      _phiValuesSortedAsc = const [];
      _wellLayout = const {};
      _attentionConcentration = 0.5;
      _hunkRankings = const [];
      // Starfield keeps its existing birth — no reason to re-fade it.
      for (final e in _Element.values) {
        if (e != _Element.starfield) _birth[e] = -1.0;
      }
    } else if (event.sessionId < _sessionId!) {
      return; // stale, ignore.
    }

    final now = _clock.elapsedMilliseconds.toDouble();
    bool wantSetState = false;

    if (event is LogosVisEngineResolving) {
      // _phase only feeds the caption; visuals are envelope-driven.
      _phase = _Phase.resolving;
      wantSetState = true;
    } else if (event is LogosVisEngineReady) {
      _nodeCount = event.nodeCount;
      _cached = event.cached;
      if (_birth[_Element.topologyDense]! < 0) {
        _birth[_Element.topologyDense] = now;
      }
      _phase = _Phase.ready;
      wantSetState = true;
    } else if (event is LogosVisDiffSources) {
      _sourceWeights = event.weights;
      _churn = event.churn;
      if (_birth[_Element.sourceIgnition]! < 0) {
        _birth[_Element.sourceIgnition] = now;
      }
      if (_birth[_Element.heatRings]! < 0) {
        _birth[_Element.heatRings] = now + 220;
      }
      _phase = _Phase.ignited;
      wantSetState = true;
    } else if (event is LogosVisReseedSources) {
      // Brainstorm landed; the seed map is now a blend of the original
      // diff anchors and the K-space / well-expansion paths. Update
      // the canvas' sourceWeights so the source starburst shows the
      // wider field, and kick off a second wavefront that rides on
      // top of the first.
      _sourceWeights = event.weights;
      _reseedIdeaCount = event.brainstormIdeas;
      _reseedSemanticHits = event.semanticHits;
      _reseedWellExpansion = event.wellExpansionFiles;
      _birth[_Element.reseedWavefront] = now;
      _phase = _Phase.reseeded;
      wantSetState = true;
    } else if (event is LogosVisDiffusionComplete) {
      _phi = event.phi;
      _wellByPath = event.wellByPath;
      // Precompute sorts once per event so paint() stays O(1).
      _phiSortedDesc = _phi.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _phiValuesSortedAsc = _phi.values.where((v) => v > 0.02).toList()
        ..sort();
      _wellLayout = _buildWellLayout(_wellByPath);
      _attentionConcentration = _computeConcentration(_phiValuesSortedAsc);
      // Wells fade in first, then neighbours cascade.
      if (_birth[_Element.wellSectors]! < 0) {
        _birth[_Element.wellSectors] = now;
      }
      if (_birth[_Element.neighbourNodes]! < 0) {
        _birth[_Element.neighbourNodes] = now + 200;
      }
      _phase = _Phase.diffused;
      wantSetState = true;
    } else if (event is LogosVisHunksRanked) {
      _hunkRankings = event.rankings;
      _hunksAdmitted = event.admitted;
      _hunksSkipped = event.skipped;
      _budgetFraction = event.budgetFraction;
      if (_birth[_Element.footer]! < 0) {
        _birth[_Element.footer] = now;
      }
      if (_birth[_Element.budgetMeter]! < 0) {
        _birth[_Element.budgetMeter] = now + 350;
      }
      _phase = _Phase.ranked;
      wantSetState = true;
    } else if (event is LogosVisTransmit) {
      if (_birth[_Element.transmitBeam]! < 0) {
        _birth[_Element.transmitBeam] = now;
      }
      _phase = _Phase.transmit;
      wantSetState = true;
    } else if (event is LogosVisComplete) {
      _phase = _Phase.complete;
      wantSetState = true;
    }

    if (wantSetState && mounted) setState(() {});
  }

  // Mirror of the painter's tip-placement math. Duplicated because
  // the Listener callbacks fire outside the paint phase; drift here
  // will misalign the hit-test against what's on screen.
  Offset _tipRestFor(Size size) {
    final footerEnv = _footerEnv();
    final footerH = 64.0 * footerEnv;
    final topH = size.height - footerH;
    final cx = size.width / 2.0;
    final cy = topH / 2.0;
    final maxR = math.min(size.width, topH) * 0.36;
    return Offset(cx + maxR * 1.18, cy);
  }

  double _footerEnv() {
    final b = _birth[_Element.footer]!;
    if (b < 0) return 0.0;
    final nowMs = _clock.elapsedMilliseconds.toDouble();
    final t = ((nowMs - b) / 700.0).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  // Spring + exponential velocity damping, matching hypercube_logo.
  //   damping = exp(-λ · dt)
  //   v ← (v + a · dt) · damping
  //   x ← x + v · dt
  // Spring stiffness is modulated by attention concentration: focused
  // distributions snap back harder (the system "knows its answer"),
  // diffuse distributions feel loose.
  static const double _tipDampingPerSec = 21.4;
  double get _tipSpring => 500.0 + 500.0 * _attentionConcentration;

  void _stepTipPhysics(double dt) {
    if (_tipDragging) return;
    // Sanitise any state that may have slipped to NaN/Infinity during
    // a pathological rebuild (theme change, window resize storm, etc.).
    // One free fix-up pass beats carrying a corrupt spring forever.
    if (!_tipDragOffset.isFinite || !_tipVelocity.isFinite) {
      _tipDragOffset = Offset.zero;
      _tipVelocity = Offset.zero;
      return;
    }
    if (_tipDragOffset.distance < 0.15 && _tipVelocity.distance < 1.5) {
      _tipDragOffset = Offset.zero;
      _tipVelocity = Offset.zero;
      return;
    }
    final damping = math.exp(-_tipDampingPerSec * dt);
    final k = _tipSpring;
    final ax = -k * _tipDragOffset.dx;
    final ay = -k * _tipDragOffset.dy;
    final vx = (_tipVelocity.dx + ax * dt) * damping;
    final vy = (_tipVelocity.dy + ay * dt) * damping;
    final nx = _tipDragOffset.dx + vx * dt;
    final ny = _tipDragOffset.dy + vy * dt;
    // Final non-finite guard: if a catastrophic dt got through the
    // clamp and produced NaN, snap everything back to rest.
    if (!vx.isFinite || !vy.isFinite || !nx.isFinite || !ny.isFinite) {
      _tipDragOffset = Offset.zero;
      _tipVelocity = Offset.zero;
      return;
    }
    _tipVelocity = Offset(vx, vy);
    _tipDragOffset = Offset(nx, ny);
  }

  /// Derives head/tail from the current layout and steps the rope.
  /// Tail is scaled by the transmit envelope so the rope extends out
  /// of the centre during beam fade-in rather than snapping to length.
  void _stepRopeFromLayout(double dt) {
    final size = _canvasSize;
    // Skip when the layout hasn't reported a real size yet or has
    // reported a degenerate one (can happen for a single frame during
    // a parent rebuild — e.g. theme change re-measuring the pane).
    if (size.width <= 0 || size.height <= 0 ||
        !size.width.isFinite || !size.height.isFinite) {
      return;
    }
    final footerEnv = _footerEnv();
    final footerH = 64.0 * footerEnv;
    final topH = size.height - footerH;
    if (topH <= 0) return;
    final cx = size.width / 2.0;
    final cy = topH / 2.0;
    final maxR = math.min(size.width, topH) * 0.36;
    if (maxR <= 0) return;
    final head = Offset(cx, cy);
    final restEnd = Offset(cx + maxR * 1.18, cy);
    final fullTip = restEnd + _tipDragOffset;
    // Before transmit, envT = 0 → tail collapses onto head.
    final b = _birth[_Element.transmitBeam]!;
    double envT = 0.0;
    if (b >= 0) {
      final now = _clock.elapsedMilliseconds.toDouble();
      envT = ((now - b) / 800.0).clamp(0.0, 1.0);
      envT = envT * envT * (3 - 2 * envT);
    }
    final tail = Offset.lerp(head, fullTip, envT)!;
    _stepRope(head, tail, dt);
  }

  /// One Verlet step over the rope chain. Head and tail are pinned
  /// each call; interior nodes integrate + relax under 3 constraint
  /// passes. ~42 ops per frame.
  void _stepRope(Offset head, Offset tail, double dt) {
    const n = _kRopeSegments;
    final existingPos = _ropePos;
    final existingPrev = _ropePrev;

    // Reseed the rope on first frame OR when any node has slipped to
    // NaN/Infinity (rare, but a single corrupt frame would taint the
    // whole chain forever without this self-heal).
    var needsReseed = existingPos == null || existingPrev == null;
    if (!needsReseed) {
      for (var i = 0; i <= n; i++) {
        if (!existingPos![i].isFinite || !existingPrev![i].isFinite) {
          needsReseed = true;
          break;
        }
      }
    }
    if (needsReseed) {
      final freshPos = List<Offset>.filled(n + 1, Offset.zero, growable: false);
      final freshPrev = List<Offset>.filled(n + 1, Offset.zero, growable: false);
      for (var i = 0; i <= n; i++) {
        final p = Offset.lerp(head, tail, i / n)!;
        freshPos[i] = p;
        freshPrev[i] = p;
      }
      _ropePos = freshPos;
      _ropePrev = freshPrev;
      return;
    }

    // Non-null past the reseed branch (the early return above handles
    // the null case). Locals avoid the analyzer losing promotion
    // across the following loop.
    final pos = existingPos!;
    final prev = existingPrev!;

    // Setting prev = pos on the anchors keeps implicit velocity at
    // zero so the pin doesn't inject a phantom frame-delta into
    // neighbouring segments when head or tail teleports.
    pos[0] = head;
    prev[0] = head;
    pos[n] = tail;
    prev[n] = tail;

    // Verlet: implicit velocity = pos - prev. velDecay < 1 gives the
    // laggy feel during motion; restoreK pulls each node toward its
    // linear-interp position so the rope straightens at rest.
    const velDecay = 0.94;
    const restoreK = 0.045;
    for (var i = 1; i < n; i++) {
      final vx = pos[i].dx - prev[i].dx;
      final vy = pos[i].dy - prev[i].dy;
      final ideal = Offset.lerp(head, tail, i / n)!;
      final rx = (ideal.dx - pos[i].dx) * restoreK;
      final ry = (ideal.dy - pos[i].dy) * restoreK;
      final nx = pos[i].dx + vx * velDecay + rx;
      final ny = pos[i].dy + vy * velDecay + ry;
      prev[i] = pos[i];
      pos[i] = Offset(nx, ny);
    }

    // Constraint relaxation. targetSeg is the current chord / N, so
    // when the tip is pulled the rope tautens, and when it returns
    // the reduced target cooperates with restoreK to straighten out.
    final targetSeg = (tail - head).distance / n;
    for (var iter = 0; iter < 3; iter++) {
      for (var i = 0; i < n; i++) {
        final dx = pos[i + 1].dx - pos[i].dx;
        final dy = pos[i + 1].dy - pos[i].dy;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < 1e-6) continue;
        final diff = (d - targetSeg) / d;
        final movable0 = i > 0;
        final movable1 = i + 1 < n;
        final total = (movable0 ? 1 : 0) + (movable1 ? 1 : 0);
        if (total == 0) continue;
        final share = diff / total;
        if (movable0) {
          pos[i] = Offset(
            pos[i].dx + dx * share,
            pos[i].dy + dy * share,
          );
        }
        if (movable1) {
          pos[i + 1] = Offset(
            pos[i + 1].dx - dx * share,
            pos[i + 1].dy - dy * share,
          );
        }
      }
    }
  }

  void _onTipPointerDown(PointerDownEvent e) {
    if (_canvasSize == Size.zero) return;
    // Beam tip wins if both are within grab range (it's the more
    // obvious target and usually further from the cluster).
    final tipRest = _tipRestFor(_canvasSize);
    final tipCurrent = tipRest + _tipDragOffset;
    if ((e.localPosition - tipCurrent).distance <= 24.0) {
      _tipDragging = true;
      _tipVelocity = Offset.zero;
      return;
    }
    // Fall through to spoke grab. Grab radius is tighter than the
    // beam tip's because spokes cluster near the centre — generous
    // radii would make them steal each other's events.
    final path = _spokeAtPosition(e.localPosition, grabRadius: 16.0);
    if (path != null) {
      _activeSpokeDrag = path;
      _spokeVel[path] = Offset.zero;
      _spokeDrag[path] ??= Offset.zero;
    }
  }

  void _onTipPointerMove(PointerMoveEvent e) {
    if (_tipDragging) {
      final rest = _tipRestFor(_canvasSize);
      var target = e.localPosition - rest;
      // Pull arc derived from attention concentration: focused
      // diffusion → tight arc, broad → wide arc.
      final freedom = 0.22 + 0.33 * (1.0 - _attentionConcentration);
      final maxPull = _canvasSize.shortestSide * freedom;
      if (target.distance > maxPull) {
        target = target / target.distance * maxPull;
      }
      setState(() => _tipDragOffset = target);
      return;
    }
    final path = _activeSpokeDrag;
    if (path != null) {
      final rest = _spokeTipRestFor(path);
      if (rest == null) return;
      var target = e.localPosition - rest;
      // Spokes get a smaller pull radius than the beam — they sit
      // inside the ring structure and pulling them too far would
      // collide with neighbour nodes.
      final maxPull = _canvasSize.shortestSide * 0.28;
      if (target.distance > maxPull) {
        target = target / target.distance * maxPull;
      }
      setState(() => _spokeDrag[path] = target);
    }
  }

  void _onTipPointerUp(PointerUpEvent e) {
    if (_tipDragging) {
      _tipDragging = false;
      _tipVelocity = Offset.zero;
      return;
    }
    final path = _activeSpokeDrag;
    if (path != null) {
      // Peak magnitude of the pull becomes a normalised user-intent
      // signal for muse. Shortest side is the natural scale — same
      // denominator used everywhere in this layout.
      final off = _spokeDrag[path] ?? Offset.zero;
      final magnitude = _canvasSize.shortestSide <= 0
          ? 0.0
          : (off.distance / _canvasSize.shortestSide).clamp(0.0, 1.0);
      if (magnitude > 0.05) {
        LogosVisBus.instance.recordUserSpokeBoost(path, magnitude);
      }
      _spokeVel[path] = Offset.zero;
      _activeSpokeDrag = null;
    }
  }

  void _onTipPointerCancel(PointerCancelEvent e) {
    _tipDragging = false;
    _activeSpokeDrag = null;
  }

  /// FNV-1a mirror of the painter's per-path hash (same output as
  /// `_TopoPainter._unitHash` — duplicated here because the Listener
  /// runs outside the paint phase).
  double _unitHashLocal(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h / 0xffffffff;
  }

  /// Compute the rest-position tip of a source spoke for [path].
  /// Mirrors the painter's math exactly so hit-testing lines up with
  /// what's drawn. Returns null when we don't have a canvas size yet
  /// or the path isn't in the current source set.
  Offset? _spokeTipRestFor(String path) {
    final size = _canvasSize;
    if (size.width <= 0 || size.height <= 0) return null;
    final weight = _sourceWeights[path];
    if (weight == null) return null;
    var maxWeight = 0.0;
    for (final v in _sourceWeights.values) {
      if (v > maxWeight) maxWeight = v;
    }
    if (maxWeight <= 0) return null;

    final footerEnv = _footerEnv();
    final footerH = 64.0 * footerEnv;
    final topH = size.height - footerH;
    if (topH <= 0) return null;
    final cx = size.width / 2.0;
    final cy = topH / 2.0;
    final maxR = math.min(size.width, topH) * 0.36;
    if (maxR <= 0) return null;
    final spokeInner = maxR * 0.055;
    final spokeMax = maxR * 0.155;
    final norm = (weight / maxWeight).clamp(0.0, 1.0);
    final len = spokeInner + (spokeMax - spokeInner) * (0.35 + 0.65 * norm);
    final theta = _sourceWeights.length == 1
        ? -math.pi / 2
        : _unitHashLocal(path) * 2 * math.pi - math.pi / 2;
    return Offset(cx + len * math.cos(theta), cy + len * math.sin(theta));
  }

  /// Return the path whose tip is closest to [localPos] and within
  /// [grabRadius] pixels. Null when none are grabbable.
  String? _spokeAtPosition(Offset localPos, {double grabRadius = 18.0}) {
    String? best;
    var bestD = grabRadius;
    for (final path in _sourceWeights.keys) {
      final rest = _spokeTipRestFor(path);
      if (rest == null) continue;
      final current = rest + (_spokeDrag[path] ?? Offset.zero);
      final d = (localPos - current).distance;
      if (d < bestD) {
        bestD = d;
        best = path;
      }
    }
    return best;
  }

  /// Spring step for every non-active spoke drag. Reuses the tip-
  /// spring constants for a consistent feel. Once a spoke is close
  /// enough to rest it's dropped from the maps so the hot path
  /// stays clean.
  void _stepSpokePhysics(double dt) {
    if (_spokeDrag.isEmpty) return;
    final damping = math.exp(-_tipDampingPerSec * dt);
    final k = _tipSpring;
    final settle = <String>[];
    for (final path in _spokeDrag.keys) {
      if (path == _activeSpokeDrag) continue;
      final off = _spokeDrag[path]!;
      final vel = _spokeVel[path] ?? Offset.zero;
      if (!off.isFinite || !vel.isFinite) {
        settle.add(path);
        continue;
      }
      if (off.distance < 0.15 && vel.distance < 1.5) {
        settle.add(path);
        continue;
      }
      final ax = -k * off.dx;
      final ay = -k * off.dy;
      final vx = (vel.dx + ax * dt) * damping;
      final vy = (vel.dy + ay * dt) * damping;
      final nx = off.dx + vx * dt;
      final ny = off.dy + vy * dt;
      if (!vx.isFinite || !vy.isFinite || !nx.isFinite || !ny.isFinite) {
        settle.add(path);
        continue;
      }
      _spokeVel[path] = Offset(vx, vy);
      _spokeDrag[path] = Offset(nx, ny);
    }
    for (final path in settle) {
      _spokeDrag.remove(path);
      _spokeVel.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, innerConstraints) {
              // Inner constraints give the Listener's real bounds —
              // the outer column's max includes the caption row below.
              _canvasSize = Size(
                innerConstraints.maxWidth,
                innerConstraints.maxHeight,
              );
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onTipPointerDown,
                onPointerMove: _onTipPointerMove,
                onPointerUp: _onTipPointerUp,
                onPointerCancel: _onTipPointerCancel,
                child: MouseRegion(
                  cursor: _tipDragging
                      ? SystemMouseCursors.grabbing
                      : SystemMouseCursors.basic,
                  child: CustomPaint(
                size: _canvasSize,
                painter: _LogosDiffusionPainter(
                  tokens: tokens,
                  nowMs: _clock.elapsedMilliseconds.toDouble(),
                  tipDragOffset: _tipDragOffset,
                  ropePoints: _ropePos,
                  spokeDrag: _spokeDrag,
                  birth: _birth,
                  nodeCount: _nodeCount,
                  cached: _cached,
                  sourceWeights: _sourceWeights,
                  churn: _churn,
                  phi: _phi,
                  phiSortedDesc: _phiSortedDesc,
                  phiValuesSortedAsc: _phiValuesSortedAsc,
                  wellByPath: _wellByPath,
                  wellLayout: _wellLayout,
                  hunkRankings: _hunkRankings,
                  hunksAdmitted: _hunksAdmitted,
                  hunksSkipped: _hunksSkipped,
                  budgetFraction: _budgetFraction,
                  phase: _phase,
                ),
              ),
                ),
              );
            },
          ),
        ),
        if (widget.onCancel != null) ...[
          const SizedBox(height: 16),
          _cancelChip(tokens),
        ],
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _cancelChip(AppTokens tokens) {
    return GestureDetector(
      onTap: widget.onCancel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: tokens.chromeBorder.withValues(alpha: 0.35),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'Cancel',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Concentration in [0, 1] derived from the top third vs. max of an
/// ascending-sorted φ value list. Flat → 0, peaked → 1.
double _computeConcentration(List<double> phiValuesSortedAsc) {
  final n = phiValuesSortedAsc.length;
  if (n < 3) return 0.5;
  final phiMax = phiValuesSortedAsc.last;
  if (phiMax <= 0) return 0.5;
  // 67th-percentile φ: the threshold above which the top third sit.
  final idx = ((0.67) * (n - 1)).round();
  final phiMid = phiValuesSortedAsc[idx];
  return (1.0 - phiMid / phiMax).clamp(0.0, 1.0);
}

/// Partition the circle into per-well sectors by count. Built once
/// on LogosVisDiffusionComplete and shared between sector shading
/// and neighbour placement so they agree on where each well lives.
Map<String, ({double start, double span})> _buildWellLayout(
    Map<String, String> wellByPath) {
  if (wellByPath.isEmpty) return const {};
  final counts = <String, int>{};
  for (final name in wellByPath.values) {
    counts[name] = (counts[name] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topN = entries.take(6).toList();
  final total = topN.fold<int>(0, (a, e) => a + e.value);
  if (total == 0) return const {};
  final out = <String, ({double start, double span})>{};
  var a = -math.pi / 2;
  for (final e in topN) {
    final span = (e.value / total) * 2 * math.pi;
    out[e.key] = (start: a, span: span);
    a += span;
  }
  return out;
}

/// Feeds caption copy only. Visuals are envelope-driven.
enum _Phase {
  resolving,
  ready,
  ignited,
  reseeded,
  diffused,
  ranked,
  transmit,
  complete,
}

/// Keys into _birth.
enum _Element {
  starfield,
  topologyDense,
  sourceIgnition,
  heatRings,
  wellSectors,
  neighbourNodes,
  footer,
  budgetMeter,
  transmitBeam,
  /// Second ignition pulse fired when muse's brainstorm-reshaped seed
  /// map lands. Plays on top of the first wavefront so the two phases
  /// flow together rather than cutting.
  reseedWavefront,
}

/// Observatory-chart painter.
/// Each element animates on entrance then holds — no infinite
/// oscillators. The only post-settle motion is the transmit beam
/// (which represents data actually moving). Polar coordinates
/// throughout: rings for diffusion distance, sectors for wells,
/// nodes pinned at (θ, r).
class _LogosDiffusionPainter extends CustomPainter {
  final AppTokens tokens;
  final double nowMs;
  final Map<_Element, double> birth;
  final int nodeCount;
  final bool cached;
  final Map<String, double> sourceWeights;
  final int churn;
  final Map<String, double> phi;
  final List<MapEntry<String, double>> phiSortedDesc;
  final List<double> phiValuesSortedAsc;
  final Map<String, String> wellByPath;
  final Map<String, ({double start, double span})> wellLayout;
  final List<double> hunkRankings;
  final int hunksAdmitted;
  final int hunksSkipped;
  final double budgetFraction;
  final _Phase phase;
  final Offset tipDragOffset;
  /// Rope chain positions (head → tail). Null before first layout.
  final List<Offset>? ropePoints;
  /// Per-source-path drag offsets. Empty when no spoke is being
  /// pulled or springing back. Each spoke renders at its rest
  /// position + its entry here.
  final Map<String, Offset> spokeDrag;

  _LogosDiffusionPainter({
    required this.tokens,
    required this.nowMs,
    required this.tipDragOffset,
    required this.ropePoints,
    required this.spokeDrag,
    required this.birth,
    required this.nodeCount,
    required this.cached,
    required this.sourceWeights,
    required this.churn,
    required this.phi,
    required this.phiSortedDesc,
    required this.phiValuesSortedAsc,
    required this.wellByPath,
    required this.wellLayout,
    required this.hunkRankings,
    required this.hunksAdmitted,
    required this.hunksSkipped,
    required this.budgetFraction,
    required this.phase,
  });

  /// Smoothstep envelope since birth, clamped to [0, 1]. Holds at 1.
  double _env(_Element element, {double fadeMs = 600}) {
    final b = birth[element]!;
    if (b < 0) return 0.0;
    final t = ((nowMs - b) / fadeMs).clamp(0.0, 1.0);
    return _smoothstep(t);
  }

  static double _smoothstep(double x) {
    final c = x.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Footer height follows its envelope so the top region reclaims
    // space smoothly as the footer slides in.
    final footerEnv = _env(_Element.footer, fadeMs: 700);
    final footerH = 64.0 * footerEnv;
    final topRect = Rect.fromLTWH(0, 0, size.width, size.height - footerH);
    final footerRect = Rect.fromLTWH(
      0,
      size.height - footerH,
      size.width,
      footerH,
    );

    _paintTop(canvas, topRect);
    if (footerH > 1.0) {
      _paintFooter(canvas, footerRect);
    }
  }

  /// The main diffusion diagram.
  void _paintTop(Canvas canvas, Rect rect) {
    final center = rect.center;
    final radius = math.min(rect.width, rect.height) * 0.36;
    final p = _TopoPainter(
      canvas: canvas,
      center: center,
      maxRadius: radius,
      tokens: tokens,
      nowMs: nowMs,
      birth: birth,
      envFor: _env,
      nodeCount: nodeCount,
      cached: cached,
      sourceWeights: sourceWeights,
      churn: churn,
      phi: phi,
      phiSortedDesc: phiSortedDesc,
      phiValuesSortedAsc: phiValuesSortedAsc,
      wellByPath: wellByPath,
      wellLayout: wellLayout,
      tipDragOffset: tipDragOffset,
      ropePoints: ropePoints,
      spokeDrag: spokeDrag,
    );
    p.paint();
  }

  /// The hunk φ bars + budget meter that animate up from the bottom.
  void _paintFooter(Canvas canvas, Rect rect) {
    final p = _FooterPainter(
      canvas: canvas,
      rect: rect,
      tokens: tokens,
      nowMs: nowMs,
      birth: birth,
      envFor: _env,
      hunkRankings: hunkRankings,
      hunksAdmitted: hunksAdmitted,
      hunksSkipped: hunksSkipped,
      budgetFraction: budgetFraction,
    );
    p.paint();
  }

  @override
  bool shouldRepaint(covariant _LogosDiffusionPainter old) {
    return old.nowMs != nowMs ||
        old.phase != phase ||
        !identical(old.sourceWeights, sourceWeights) ||
        !identical(old.phi, phi) ||
        !identical(old.wellByPath, wellByPath) ||
        !identical(old.hunkRankings, hunkRankings) ||
        old.budgetFraction != budgetFraction;
  }
}

/// Top-half diffusion diagram.
class _TopoPainter {
  final Canvas canvas;
  final Offset center;
  final double maxRadius;
  final AppTokens tokens;
  final double nowMs;
  final Map<_Element, double> birth;
  final double Function(_Element, {double fadeMs}) envFor;
  final int nodeCount;
  final bool cached;
  final Map<String, double> sourceWeights;
  final int churn;
  final Map<String, double> phi;
  /// φ entries, descending. Precomputed — see `_onEvent`.
  final List<MapEntry<String, double>> phiSortedDesc;
  /// φ values ≥ 0.02, ascending. Used for O(1) quantile lookup.
  final List<double> phiValuesSortedAsc;
  final Map<String, String> wellByPath;
  /// Shared with sector shading.
  final Map<String, ({double start, double span})> wellLayout;
  /// Tip displacement in pixels (drag + spring decay).
  final Offset tipDragOffset;
  /// Rope chain, head → tail. Null before first layout.
  final List<Offset>? ropePoints;
  /// Per-path spoke drag offsets. Empty = everything at rest.
  final Map<String, Offset> spokeDrag;

  _TopoPainter({
    required this.canvas,
    required this.center,
    required this.maxRadius,
    required this.tokens,
    required this.nowMs,
    required this.birth,
    required this.envFor,
    required this.nodeCount,
    required this.cached,
    required this.sourceWeights,
    required this.churn,
    required this.phi,
    required this.phiSortedDesc,
    required this.phiValuesSortedAsc,
    required this.wellByPath,
    required this.wellLayout,
    required this.tipDragOffset,
    required this.ropePoints,
    required this.spokeDrag,
  });

  void paint() {
    // Back-to-front so brighter elements sit on top.
    _paintStarfield();
    _paintWellSectors();
    _paintAttentionArcs();
    _paintNeighbourNodes();
    _paintHeatRings();
    _paintIgnitionWavefront();
    _paintReseedWavefront();
    _paintSourceFiles();
    _paintTransmitBeam();
  }

  // Thin line from anchor to each of the top-K φ neighbours. Alpha
  // scales with φ so the distribution shape is visible: flat φ →
  // uniform lines, peaked φ → a few bright rays.
  void _paintAttentionArcs() {
    final env = envFor(_Element.neighbourNodes, fadeMs: 900);
    if (env <= 0 || phiSortedDesc.isEmpty) return;
    final maxPhi = phiSortedDesc.first.value;
    if (maxPhi <= 0) return;

    // 16 is the visual budget — past that it becomes a hairball.
    final k = math.min(16, phiSortedDesc.length);
    final inner = maxRadius * 0.075; // clear the aura
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < k; i++) {
      final e = phiSortedDesc[i];
      final phiNorm = (e.value / maxPhi).clamp(0.0, 1.0);
      if (phiNorm < 0.05) continue;

      // Rank-staggered fade-in: strongest arcs appear first.
      final rankT = ((env - (i / k) * 0.5) / 0.5).clamp(0.0, 1.0);
      if (rankT <= 0) continue;

      // Must match _paintNeighbourNodes so the arc ends at the node.
      final settleR = maxRadius * (0.34 + (1.0 - phiNorm) * 0.55);
      final well = wellByPath[e.key];
      final sector = well != null ? wellLayout[well] : null;
      final double theta;
      if (sector != null) {
        final frac = 0.08 + 0.84 * _unitHash(e.key);
        theta = sector.start + sector.span * frac;
      } else {
        theta = _angleForPath(e.key);
      }
      final sx = center.dx + inner * math.cos(theta);
      final sy = center.dy + inner * math.sin(theta);
      final tx = center.dx + settleR * math.cos(theta);
      final ty = center.dy + settleR * math.sin(theta);

      final baseColour = well != null ? _wellColour(well) : tokens.accentBright;
      final alpha = (0.10 + 0.28 * phiNorm) * _smoothstep(rankT);
      paint.color = baseColour.withValues(alpha: alpha);
      canvas.drawLine(Offset(sx, sy), Offset(tx, ty), paint);
    }
  }

  // Single expanding ring that sweeps outward once on ignition and
  // stops at the outer radius. Fires once per session.
  void _paintIgnitionWavefront() {
    final b = birth[_Element.sourceIgnition]!;
    if (b < 0) return;
    const durationMs = 1100.0;
    final t = ((nowMs - b) / durationMs).clamp(0.0, 1.0);
    if (t >= 1.0) return;
    final eased = _smoothstep(t);
    final r = maxRadius * 0.95 * eased;
    // (1 - t) envelope × half-sine gives an impulse-response shape.
    final alpha = (1.0 - t) * 0.40 * math.sin(math.pi * math.min(1, t * 1.4));
    if (alpha <= 0) return;
    final paint = Paint()
      ..color = tokens.accentBright.withValues(alpha: alpha.clamp(0, 1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
    canvas.drawCircle(center, r, paint);
  }

  // Second wavefront — fires when muse emits `LogosVisReseedSources`
  // (brainstorm has landed and the seed map was reshaped). Same
  // impulse-response shape as the first wavefront but slightly longer
  // and heavier, reading as "the field is reconfiguring". The two
  // wavefronts share the canvas for ~600ms in the middle: the first
  // is still dying off as the second begins, so the eye sees them as
  // one continuous animation rather than two discrete pulses.
  void _paintReseedWavefront() {
    final b = birth[_Element.reseedWavefront]!;
    if (b < 0) return;
    const durationMs = 1400.0;
    final t = ((nowMs - b) / durationMs).clamp(0.0, 1.0);
    if (t >= 1.0) return;
    final eased = _smoothstep(t);
    // Slightly bigger radius than the first wavefront — the reshape
    // has wider reach by definition (brainstorm can pull in files
    // well past the diff's immediate neighbourhood).
    final r = maxRadius * 1.05 * eased;
    final alpha =
        (1.0 - t) * 0.48 * math.sin(math.pi * math.min(1, t * 1.3));
    if (alpha <= 0) return;
    final paint = Paint()
      ..color = tokens.accentBright.withValues(alpha: alpha.clamp(0, 1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);
    canvas.drawCircle(center, r, paint);
  }

  void _paintStarfield() {
    // Base layer fades in on mount; a denser layer fades in once the
    // engine reports its node count. Both persist for the session.
    final baseEnv = envFor(_Element.starfield, fadeMs: 700);
    final denseEnv = envFor(_Element.topologyDense, fadeMs: 900);
    if (baseEnv <= 0) return;

    // Golden-angle spiral — fixed positions, no time-based motion.
    final baseCount = 48;
    final baseAlpha = 0.24 * baseEnv;
    final basePaint = Paint()
      ..color = tokens.chromeBorder.withValues(alpha: baseAlpha);
    for (var i = 0; i < baseCount; i++) {
      final t = i / baseCount;
      final r = maxRadius * (0.18 + 0.95 * math.sqrt(t));
      final theta = i * 2.3998; // golden angle, frozen
      final dx = center.dx + r * math.cos(theta);
      final dy = center.dy + r * math.sin(theta);
      final size_ = 0.9 + 0.5 * math.sin(i * 1.7);
      canvas.drawCircle(Offset(dx, dy), size_, basePaint);
    }

    // Cap extra dots at 110; more reads as visual noise.
    if (denseEnv > 0 && nodeCount > 0) {
      final extra = math.min(nodeCount - baseCount, 110);
      if (extra > 0) {
        final paint = Paint()
          ..color = tokens.chromeBorder.withValues(alpha: 0.28 * denseEnv);
        for (var i = 0; i < extra; i++) {
          final t = (i + baseCount) / (baseCount + extra);
          final r = maxRadius * (0.22 + 0.92 * math.sqrt(t));
          final theta = (i + baseCount) * 2.3998;
          final dx = center.dx + r * math.cos(theta);
          final dy = center.dy + r * math.sin(theta);
          final size_ = 0.9 + 0.4 * math.sin(i * 2.1);
          canvas.drawCircle(Offset(dx, dy), size_, paint);
        }
      }
    }
  }

  void _paintWellSectors() {
    final env = envFor(_Element.wellSectors, fadeMs: 1100);
    if (env <= 0 || wellLayout.isEmpty) return;
    for (final entry in wellLayout.entries) {
      final colour = _wellColour(entry.key).withValues(alpha: 0.11 * env);
      final paint = Paint()
        ..color = colour
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: maxRadius),
          entry.value.start,
          entry.value.span,
          false,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _paintNeighbourNodes() {
    final env = envFor(_Element.neighbourNodes, fadeMs: 900);
    if (env <= 0 || phiSortedDesc.isEmpty) return;
    final sorted = phiSortedDesc;
    final maxPhi = sorted.first.value;
    if (maxPhi <= 0) return;

    final n = sorted.length;
    // Each node's fade is shifted by its rank so the wave reads
    // strongest-first. The 0.35 tail is each individual fade's width.
    final cascadeWindow = math.max(0.0001, 1.0 - 0.35);
    int idx = 0;
    for (final e in sorted) {
      final phiNorm = (e.value / maxPhi).clamp(0.0, 1.0);
      if (phiNorm < 0.02) {
        idx++;
        continue;
      }
      final rankProgress = idx / n;
      final localT = ((env - rankProgress * cascadeWindow) / 0.35)
          .clamp(0.0, 1.0);
      if (localT <= 0) {
        idx++;
        continue;
      }
      final localIntensity = _smoothstep(localT);

      // High φ → inner, low φ → outer.
      final settleR = maxRadius *
          (0.34 + (1.0 - phiNorm) * 0.55) *
          (0.92 + 0.08 * localIntensity);
      // θ lives inside the node's well sector. Hash-derived frac
      // picks a stable sub-angle; the 8% inset keeps nodes off the
      // seam between adjacent sectors. Nodes outside the top-6
      // wells fall back to a global hash angle.
      final well = wellByPath[e.key];
      final sector = well != null ? wellLayout[well] : null;
      final double theta;
      if (sector != null) {
        final frac = 0.08 + 0.84 * _unitHash(e.key);
        theta = sector.start + sector.span * frac;
      } else {
        theta = _angleForPath(e.key);
      }
      final dx = center.dx + settleR * math.cos(theta);
      final dy = center.dy + settleR * math.sin(theta);

      final baseColour = well != null ? _wellColour(well) : tokens.accentBright;
      final alpha = (0.30 + 0.60 * phiNorm) * localIntensity;
      final paint = Paint()
        ..color = baseColour.withValues(alpha: alpha.clamp(0.0, 1.0));
      final radius = (1.4 + 2.4 * phiNorm) * (0.7 + 0.3 * localIntensity);
      if (phiNorm > 0.6) {
        final halo = Paint()
          ..color = baseColour.withValues(alpha: 0.18 * localIntensity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(Offset(dx, dy), radius * 2.2, halo);
      }
      canvas.drawCircle(Offset(dx, dy), radius, paint);
      idx++;
    }
  }

  // φ-quantile contour rings. Ring K's radius is the radius at which
  // fraction q[K] of reached mass is enclosed — tight neighbourhoods
  // draw tight rings, broad ones draw wide rings. Before φ lands,
  // falls back to evenly-spaced radii.
  void _paintHeatRings() {
    final env = envFor(_Element.heatRings, fadeMs: 1100);
    if (env <= 0 || sourceWeights.isEmpty) return;

    const quantiles = [0.33, 0.66, 0.95];

    // Same radius formula as _paintNeighbourNodes — rings land where
    // the nodes they enclose actually are.
    double radiusForPhiNorm(double phiNorm) =>
        maxRadius * (0.34 + (1.0 - phiNorm) * 0.55);

    List<double> ringRadii;
    final values = phiValuesSortedAsc;
    if (values.isNotEmpty) {
      {
        final maxPhi = values.last;
        // Ascending sort → index (1-q)*(N-1) is the φ above which q
        // of the mass lives; that φ maps to the ring's radius.
        ringRadii = [
          for (final q in quantiles)
            () {
              final idx = ((1.0 - q) * (values.length - 1)).round();
              final phiAtRing = values[idx];
              final phiNorm = (phiAtRing / maxPhi).clamp(0.0, 1.0);
              return radiusForPhiNorm(phiNorm);
            }(),
        ];
      }
    } else {
      ringRadii = [
        for (final q in quantiles) maxRadius * (0.26 + 0.24 * q),
      ];
    }

    for (var k = 0; k < ringRadii.length; k++) {
      final localT = ((env - k * 0.18) / 0.6).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      final eased = _smoothstep(localT);
      final r = ringRadii[k] * eased;
      if (r <= 0) continue;
      final ringAlpha = 0.22 + 0.10 * (1.0 - localT);
      final paint = Paint()
        ..color = tokens.accentBright.withValues(alpha: ringAlpha.clamp(0, 1))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + 0.4 * (1.0 - k / ringRadii.length);
      canvas.drawCircle(center, r, paint);
    }
  }

  // Source files rendered as a starburst: one central aura + anchor
  // diamond, plus one radial spoke per file with length and tip size
  // scaled to the file's weight. N files never overlap into a blob.
  void _paintSourceFiles() {
    final env = envFor(_Element.sourceIgnition, fadeMs: 550);
    if (env <= 0 || sourceWeights.isEmpty) return;

    final entries = sourceWeights.entries.toList();
    final maxWeight = entries.fold<double>(
        0, (a, e) => e.value > a ? e.value : a);
    if (maxWeight <= 0) return;

    final auraAlpha = 0.30 * env;
    final auraR = maxRadius * 0.065;
    final aura = Paint()
      ..color = tokens.accentBright.withValues(alpha: auraAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, auraR * 0.8);
    canvas.drawCircle(center, auraR, aura);

    // Diamond half-extent encodes churn via log1p/log(1000): ~2.2px
    // at a tiny change, saturating near 5.6px beyond 1000 lines.
    final anchorAlpha = 0.92 * env;
    final anchor = Paint()
      ..color = tokens.accentBright.withValues(alpha: anchorAlpha);
    final churnT =
        (math.log(1 + churn.clamp(0, 100000)) / math.log(1000)).clamp(0.0, 1.0);
    final d0 = 2.2 + 3.4 * churnT;
    final anchorPath = Path()
      ..moveTo(center.dx, center.dy - d0)
      ..lineTo(center.dx + d0, center.dy)
      ..lineTo(center.dx, center.dy + d0)
      ..lineTo(center.dx - d0, center.dy)
      ..close();
    canvas.drawPath(anchorPath, anchor);

    final spokeInner = maxRadius * 0.055;
    final spokeMax = maxRadius * 0.155;
    final spokeStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2;

    final tipPaint = Paint();

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      // Deterministic per-path angle. Index-based distribution would
      // re-shuffle every spoke when the source map grows (e.g. muse
      // reseeding the diff anchors with brainstorm-surfaced paths);
      // hashing the path locks each spoke to a fixed position so the
      // existing ones stay put and new ones slot in between them.
      // Single-file case still points straight up so a small change
      // reads clean.
      final theta = entries.length == 1
          ? -math.pi / 2
          : _unitHash(e.key) * 2 * math.pi - math.pi / 2;
      final norm = (e.value / maxWeight).clamp(0.0, 1.0);
      final len = spokeInner + (spokeMax - spokeInner) * (0.35 + 0.65 * norm);
      final sx = center.dx + spokeInner * math.cos(theta);
      final sy = center.dy + spokeInner * math.sin(theta);
      final restTx = center.dx + len * math.cos(theta);
      final restTy = center.dy + len * math.sin(theta);
      // Per-spoke drag offset — user grabbed this tip and pulled it.
      final drag = spokeDrag[e.key] ?? Offset.zero;
      final tx = restTx + drag.dx;
      final ty = restTy + drag.dy;

      spokeStroke.color = tokens.accentBright
          .withValues(alpha: (0.35 + 0.45 * norm) * env);
      canvas.drawLine(Offset(sx, sy), Offset(tx, ty), spokeStroke);

      final tipR = 1.4 + 1.8 * norm;
      tipPaint.color =
          tokens.accentBright.withValues(alpha: (0.70 + 0.25 * norm) * env);
      canvas.drawCircle(Offset(tx, ty), tipR, tipPaint);
    }
  }

  void _paintTransmitBeam() {
    final env = envFor(_Element.transmitBeam, fadeMs: 800);
    if (env <= 0) return;
    final start = center;
    final restEnd = Offset(center.dx + maxRadius * 1.18, center.dy);
    final end = restEnd + tipDragOffset;
    // Tail position for ancillary glyphs (arrival mark). Matches what
    // the rope step ends up at.
    final head = Offset.lerp(start, end, _smoothstep(env))!;

    // Smoothed polyline through rope positions. Midpoint-to-midpoint
    // quadratic Béziers give a C1-continuous curve at every joint.
    final rope = ropePoints;
    final path = Path();
    if (rope != null && rope.length >= 2) {
      path.moveTo(rope[0].dx, rope[0].dy);
      for (var i = 1; i < rope.length - 1; i++) {
        final mid = Offset(
          (rope[i].dx + rope[i + 1].dx) * 0.5,
          (rope[i].dy + rope[i + 1].dy) * 0.5,
        );
        path.quadraticBezierTo(rope[i].dx, rope[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(rope.last.dx, rope.last.dy);
    } else {
      path.moveTo(start.dx, start.dy);
      path.lineTo(head.dx, head.dy);
    }

    // Brighter at origin, fading toward tip.
    final beamShader = ui.Gradient.linear(
      start,
      end,
      [
        tokens.accentBright.withValues(alpha: 0.85 * env),
        tokens.accentBright.withValues(alpha: 0.25 * env),
      ],
      const [0.0, 1.0],
    );
    final paint = Paint()
      ..shader = beamShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);

    // Destination glyph — fades in once the beam head has arrived.
    final arrivalT = ((env - 0.8) / 0.2).clamp(0.0, 1.0);
    if (arrivalT > 0) {
      final glyphAlpha = _smoothstep(arrivalT);
      final glyphPaint = Paint()
        ..color = tokens.accentBright.withValues(alpha: glyphAlpha);
      const d = 6.0;
      final path = Path()
        ..moveTo(end.dx, end.dy - d)
        ..lineTo(end.dx + d, end.dy)
        ..lineTo(end.dx, end.dy + d)
        ..lineTo(end.dx - d, end.dy)
        ..close();
      canvas.drawPath(path, glyphPaint);
    }
  }

  double _angleForPath(String path) {
    return _unitHash(path) * 2 * math.pi;
  }

  /// FNV-1a of [s] mapped to [0, 1). Same path → same value run to run.
  double _unitHash(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h / 0xffffffff;
  }

  Color _wellColour(String wellName) {
    var h = 0x811c9dc5;
    for (var i = 0; i < wellName.length; i++) {
      h ^= wellName.codeUnitAt(i);
      h = (h * 0x01000193) & 0xffffffff;
    }
    final hue = (h % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.32, 0.68).toColor();
  }

  static double _smoothstep(double x) {
    final c = x.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }
}

/// Hunk φ bars + budget meter. Footer height is controlled by the
/// parent painter via its envelope so the region slides in smoothly.
class _FooterPainter {
  final Canvas canvas;
  final Rect rect;
  final AppTokens tokens;
  final double nowMs;
  final Map<_Element, double> birth;
  final double Function(_Element, {double fadeMs}) envFor;
  final List<double> hunkRankings;
  final int hunksAdmitted;
  final int hunksSkipped;
  final double budgetFraction;

  _FooterPainter({
    required this.canvas,
    required this.rect,
    required this.tokens,
    required this.nowMs,
    required this.birth,
    required this.envFor,
    required this.hunkRankings,
    required this.hunksAdmitted,
    required this.hunksSkipped,
    required this.budgetFraction,
  });

  void paint() {
    if (hunkRankings.isEmpty) return;
    final footerEnv = envFor(_Element.footer, fadeMs: 700);
    if (footerEnv <= 0) return;
    final padding = const EdgeInsets.fromLTRB(28, 8, 28, 12);
    final inner = Rect.fromLTWH(
      rect.left + padding.left,
      rect.top + padding.top,
      rect.width - padding.horizontal,
      rect.height - padding.vertical,
    );
    if (inner.height < 4) return;

    final shownCount = math.min(10, hunkRankings.length);
    if (shownCount == 0) return;
    // Reserve ~70% of the footer for bars; the rest is the budget meter.
    final barSpace = inner.height * 0.70;
    final barH = math.max(
      2.0,
      (barSpace / shownCount).clamp(2.0, 5.0),
    );
    final gapDenom = math.max(1, shownCount - 1);
    final gap = math.max(1.0, (barSpace - barH * shownCount) / gapDenom);
    final maxPhi = hunkRankings.first;
    if (maxPhi <= 0) return;

    var y = inner.top;
    final birthFooter = birth[_Element.footer]!;
    // On transmit, each admitted bar gets a highlight centred at
    // birthTransmit + i*cascadeStep. Skipped bars don't participate
    // so the difference between admitted and skipped is legible.
    final birthTransmit = birth[_Element.transmitBeam]!;
    const cascadeStep = 90.0;
    const pulseWidth = 520.0;
    for (var i = 0; i < shownCount; i++) {
      final perBarBirth = birthFooter + i * 70;
      final perBarT = ((nowMs - perBarBirth) / 600.0).clamp(0.0, 1.0);
      final perBarEase = perBarT * perBarT * (3 - 2 * perBarT);
      final phi = hunkRankings[i];
      final norm = (phi / maxPhi).clamp(0.0, 1.0);
      final animatedWidth = inner.width * norm * perBarEase;
      final admitted = i < hunksAdmitted;

      // Half-cosine bump centred on this bar's pulse time.
      var highlight = 0.0;
      if (admitted && birthTransmit >= 0) {
        final pulseCenter = birthTransmit + i * cascadeStep;
        final dt = (nowMs - pulseCenter).abs();
        if (dt < pulseWidth) {
          highlight = math.cos(dt / pulseWidth * math.pi / 2);
        }
      }

      final baseAlpha = admitted ? 0.75 : 0.35;
      final alpha = (baseAlpha + 0.22 * highlight).clamp(0.0, 1.0);
      final colour = admitted
          ? tokens.accentBright.withValues(alpha: alpha)
          : tokens.chromeBorder.withValues(alpha: 0.35);
      final paint = Paint()..color = colour;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inner.left, y, animatedWidth, barH),
          Radius.circular(barH / 2),
        ),
        paint,
      );
      y += barH + gap;
    }

    // Budget meter fades in after the bars.
    final meterEnv = envFor(_Element.budgetMeter, fadeMs: 600);
    if (meterEnv > 0) {
      final meterTop = inner.top + barSpace + 6;
      final meterH = 3.5;
      if (meterTop + meterH < inner.bottom) {
        final meterRect =
            Rect.fromLTWH(inner.left, meterTop, inner.width, meterH);
        final trackPaint = Paint()
          ..color = tokens.chromeBorder.withValues(alpha: 0.20 + 0.05 * meterEnv);
        canvas.drawRRect(
          RRect.fromRectAndRadius(meterRect, Radius.circular(meterH / 2)),
          trackPaint,
        );
        final fill = Rect.fromLTWH(
          meterRect.left,
          meterRect.top,
          meterRect.width *
              budgetFraction.clamp(0.0, 1.0) *
              meterEnv,
          meterH,
        );
        final fillPaint = Paint()
          ..color = tokens.accentBright.withValues(alpha: 0.85);
        canvas.drawRRect(
          RRect.fromRectAndRadius(fill, Radius.circular(meterH / 2)),
          fillPaint,
        );
      }
    }
  }
}
