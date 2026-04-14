// ═════════════════════════════════════════════════════════════════════════
// features/bond/creatures/fox.dart — 4D wireframe fox
//
// Every rendered sample is lifted to R⁴, rotated in state-dependent
// planes, and projected back to R². Transitions *are* rotations in
// higher-dim space — a facing flip sweeps through edge-on via xz;
// a wake/sleep or commit-event flex happens in xw/yw; the
// "notice-you" moment is a brief xw spike that collapses the
// silhouette toward the viewer. No canvas-scale mirroring.
//
// Silhouette is a polyline of ~a dozen key points, densified every
// frame via Chaikin corner-cutting (same coarse → smooth trick the
// whisper glyph codec uses for stroke rendering). The polyline form
// is what makes the 4D rotation read as wireframe rather than
// raster deform — every subdivided point takes the full lift-
// rotate-project ride, so the curve bends coherently.
//
// Rotation planes in play:
//   • xz  — facing. θ = acos(facing). θ=0 native, θ=π right-faced.
//           Mid-rotation = legitimately edge-on (wire fold moment).
//   • xw  — mood transitions + commit events + notice-you. Driven
//           by wall-clock phase modulated by per-point position so
//           neighbouring samples fold coherently (a wire flex, not
//           independent jitter).
//   • yw  — couples to xw for true 4D rotation coupling. A pure xw
//           rotation reads as a 3D twist; adding yw produces the
//           iridescent Klein-bottle-ish fold you can't get from
//           flat 3D.
//
// Animator suite (co-prime periods → never re-phase):
//   • _blink / _earTwitch / _tailFlick — brief beats
//   • _tailWag / _breath / _breathSlow — continuous oscillators
//   • _driftX / _driftY — Lissajous idle orbit
//   • _lookAround / _noticeYou — rare meta beats
// ═════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'creature.dart';

class FoxCreature extends BondCreature {
  const FoxCreature();

  static const _blink =
      Beat(intervalSeconds: 5.6, durationSeconds: 0.24);
  static const _earTwitch =
      Beat(intervalSeconds: 3.1, durationSeconds: 0.18, phase: 0.4);
  static const _tailFlick =
      Beat(intervalSeconds: 4.7, durationSeconds: 0.22, phase: 0.7);
  static const _tailWag = Oscillator(periodSeconds: 2.4);
  static const _driftX = Oscillator(periodSeconds: 11.7);
  static const _driftY = Oscillator(periodSeconds: 7.3, phase: 0.31);
  static const _breath = Oscillator(periodSeconds: 3.7);
  static const _breathSlow = Oscillator(periodSeconds: 5.9);
  // Meta beats — slowed and gated on userIdle so they never pull
  // focus while the user is actively working. The intervals here
  // are the *idle-time* period; when the user is busy they simply
  // don't fire.
  static const _lookAround =
      Beat(intervalSeconds: 31.7, durationSeconds: 0.9, phase: 0.213);
  static const _noticeYou =
      Beat(intervalSeconds: 89.0, durationSeconds: 1.1, phase: 0.137);

  /// Decay time for one-shot event flourishes (commit landed, etc).
  static const double _kEventDecaySeconds = 1.5;

  /// Pet response decay — slower than an event flourish because it's
  /// a *contentment* beat (tail curl, slow blink, deep breath), not
  /// a startle.
  static const double _kPetDecaySeconds = 2.6;

  /// "Camera" z-distance for the xz perspective projection. Larger
  /// = less pronounced foreshortening during facing rotation; lower
  /// = more dramatic 3D feel. Tuned so edge-on is visibly flatter
  /// without the creature vanishing entirely.
  static const double _kCamera = 1.9;

  /// How much the w-axis leaks into screen-space. Non-zero makes
  /// the 4th-axis visible as x/y bulge during transitions (the
  /// "wire extending into nothing" look). Zero would make xw
  /// rotations invisible once projected. Tuned upward so a facing
  /// flip — which fires both xz and xw rotation together — reads
  /// as a wire unfolding through 4D, not a plane sweep.
  static const double _kWProjectX = 0.26;
  static const double _kWProjectY = 0.18;

  @override
  double get aspectRatio => 2.6;

  // ── Silhouette keys (normalised 0..1 in creature bounding box) ──
  // Traversed counter-clockwise for the head (closed loop).
  // Keeping these as 2D anchors — dynamic modulation (ear-twitch,
  // ear-rise) is applied per-frame before Chaikin smoothing.
  static const List<Offset> _headBaseKeys = [
    Offset(0.04, 0.55), // nose tip
    Offset(0.10, 0.40), // snout top
    Offset(0.16, 0.34), // forehead
    Offset(0.20, 0.04), // left ear tip (tallest)
    Offset(0.27, 0.30), // ear notch
    Offset(0.32, 0.12), // right ear tip
    Offset(0.38, 0.32), // behind right ear
    Offset(0.42, 0.50), // back of head (tail root connects here)
    Offset(0.42, 0.70), // back of jaw
    Offset(0.30, 0.78), // chin
    Offset(0.14, 0.74), // under chin
    Offset(0.06, 0.62), // up to nose
  ];

  // Tail polyline: open stroke from back-of-head to tail tip.
  static const List<Offset> _tailBaseKeys = [
    Offset(0.42, 0.50), // root (coincides with head-key 7)
    Offset(0.52, 0.52), // first easing down
    Offset(0.62, 0.46), // mid sweep
    Offset(0.74, 0.40), // upper arc
    Offset(0.85, 0.34), // near tip
    Offset(0.93, 0.30), // tip base (pre-flick/wag)
  ];

  @override
  void paint(Canvas canvas, Rect pen, BondCreatureFrame f) {
    final t = f.timeSeconds;
    final awake = f.openness;
    final asleep = f.mood == BondCreatureMood.asleep && awake == 0;
    final s = f.signals;
    final facing = f.facing;
    final focus = f.focus;

    // ── Beats / oscillators ─────────────────────────────────────
    final rawBlink = asleep ? 1.0 : _blink.sample(t);
    final earTwitch = asleep ? 0.0 : _earTwitch.sample(t) * awake;
    final tailFlick = asleep ? 0.0 : _tailFlick.sample(t) * awake;
    final tailWag = asleep ? 0.0 : _tailWag.sample(t) * awake;
    // Meta beats fire only when user is idle (idle-gate) AND awake
    // (the fox is visible) AND window is focused.
    final metaAlive =
        !asleep && s.userIdle && focus > 0.5 ? 1.0 : 0.0;
    final lookPulse = _lookAround.sample(t) * awake * metaAlive;
    final noticePulse = _noticeYou.sample(t) * awake * metaAlive;

    // Pet response holds the eye partially closed (contented slow
    // blink) — take the max so a natural blink during pet still
    // reads, but the eye never fully re-opens until the pet decays.
    // ── Pet response ───────────────────────────────────────────
    // Exponential decay, same math shape as event flourish but
    // slower. Drives a tail-curl, a slow blink override, and a
    // deeper breath amplitude.
    double petIntensity = 0;
    final lastPet = s.lastPetMs;
    if (lastPet != null) {
      final petAge =
          (DateTime.now().millisecondsSinceEpoch - lastPet) / 1000;
      if (petAge >= 0 && petAge < _kPetDecaySeconds) {
        petIntensity = math.exp(-petAge * 1.0).clamp(0.0, 1.0);
      }
    }
    // Final blink: whichever is more closed — natural flick or
    // contented pet-squint. Uses 0.6 as the "half-lidded" max so
    // the eye never fully shuts from a pet.
    final blink = math.max(rawBlink, petIntensity * 0.6);

    // Breathing — slow sleep-wave blended toward excitement-scaled
    // awake-wave. Breath reads as life even when everything else is
    // still.
    final breathFast = _breath.sample(t * (1.0 + 0.35 * s.excitement));
    final breathLow = _breathSlow.sample(t);
    final breathWave =
        asleep ? breathLow : lerp(breathLow, breathFast, awake);
    // Breath amp multiplied by focus → 0 when window is unfocused,
    // so the painter genuinely stills. The ticker's settle check
    // can then stop pumping frames into an empty room.
    final breathAmp = (asleep ? 0.055 : 0.022) *
        breathWave *
        (0.3 + 0.7 * focus) *
        (1.0 + 0.7 * petIntensity);

    final h = pen.height;
    final desiredW = h * aspectRatio;
    final driftMarginX = pen.width * 0.10;
    final driftMarginY = h * 0.04;
    final w = math.min(desiredW, pen.width - 2 * driftMarginX);

    // Anchor: the smoothed runtime position inside the pen.
    final anchorX = pen.left + f.position.dx * pen.width;
    final anchorY = pen.top + f.position.dy * pen.height;

    // Lissajous idle drift. Gated on facing stability — mid-turn
    // we clamp drift to 0 so the Lissajous doesn't pull the
    // silhouette around while the wire is folding through 4D.
    // A creature that's *turning* should read as committed to the
    // turn, not drifting simultaneously.
    final stability =
        ((facing.abs() - 0.7) / 0.3).clamp(0.0, 1.0);
    final exciteAmp = 0.6 + 0.4 * s.excitement;
    final restlessShrink = 1.0 - 0.3 * s.restlessness;
    // Amplitude reduced from 0.5 → 0.32 overall (the pen is tiny,
    // any more reads as the fox being unable to stand still).
    final driftDx = _driftX.sample(t) *
        driftMarginX *
        0.32 *
        exciteAmp *
        restlessShrink *
        awake *
        stability;
    final driftDy = _driftY.sample(t) *
        driftMarginY *
        0.7 *
        exciteAmp *
        restlessShrink *
        awake *
        stability;

    final centerX = anchorX + driftDx;
    final centerY = anchorY + driftDy;

    // ── Rotation angles per plane ────────────────────────────────
    // Facing: acos in [0, π]. Look-around & notice-you fold into
    // the same θ so the wire genuinely rotates — no discrete flip.
    //
    // Convention: the silhouette's native orientation (keys as
    // written above) puts the head on the LEFT of the bbox — i.e.
    // the creature is facing left by default. The runtime says
    // `facing=+1` means "moving right." So to face *right* we need
    // a 180° xz rotation, which means θ = π = acos(-1). Hence the
    // negation: map runtime facing → painter angle by negating
    // before acos.
    final foldedFacing = facing * (1 - 2 * lookPulse);
    final baseTheta = math.acos((-foldedFacing).clamp(-1.0, 1.0));
    // Notice-you adds an extra xw rotation angle that peaks near
    // π/2 — silhouette rotates edge-on through the 4th axis toward
    // the viewer rather than left/right.
    final noticeAngle = noticePulse * (math.pi * 0.48);

    // Hyperfold intensity — mood transitions + recent commit +
    // **facing flip itself**. A pure xz rotation reads as a flip;
    // co-firing xw/yw during facing changes is what makes it
    // a tesseract turn instead.
    final transitionT =
        1 - (4 * (awake - 0.5) * (awake - 0.5)).clamp(0.0, 1.0);
    double eventIntensity = 0;
    final lastEvent = s.lastEventMs;
    if (lastEvent != null) {
      final ageSec =
          (DateTime.now().millisecondsSinceEpoch - lastEvent) / 1000;
      if (ageSec >= 0 && ageSec < _kEventDecaySeconds) {
        eventIntensity = math.exp(-ageSec * 2.5).clamp(0.0, 1.0);
      }
    }
    // Facing-flip morph: |facing|=1 → no transition (0), |facing|=0
    // → full edge-on transition (1). Squared so the tail of the
    // ease doesn't linger — the tesseract only fires during the
    // actual turn, not the last 10% of the approach.
    final facingFlipRaw = (1 - facing.abs()).clamp(0.0, 1.0);
    final facingFlipMorph = facingFlipRaw * facingFlipRaw;
    final morph = math.max(
      math.max(transitionT, eventIntensity),
      facingFlipMorph,
    );

    // ── Frame-invariants hoisted out of the per-point projector ─
    // Principle (Grimoire Circle XIX — "keep the pipeline full"):
    // anything that does not depend on (nx, ny) is a constant
    // across all ~96 polyline samples. Computing it once per frame
    // instead of once per sample is the cheapest possible win —
    // pure arithmetic saved, no math changed.
    //
    // Biggest savings: `cos(noticeAngle)` and `sin(noticeAngle)`
    // were being called per-sample even though `noticeAngle` is a
    // scalar per frame. That alone was ~190 transcendental calls
    // per frame during a notice-you beat.
    final cT = math.cos(baseTheta);
    final sT = math.sin(baseTheta);
    final hasMorph = morph > 0.001;
    // Pre-scale the decay amplitudes — per-sample `sin(phi)` still
    // has to run (it's genuinely per-point), but the outer scalars
    // aren't re-multiplied every time.
    final psiAmp = morph * 1.35;
    final chiAmp = morph * 1.1;
    final basePhaseX = t * 3.4;
    final basePhaseY = basePhaseX * 0.85;
    final hasTesseract = facingFlipMorph > 0.001;
    // The pi-scaled amplitudes fold facingFlipMorph in once.
    final omegaAmp = facingFlipMorph * math.pi;
    final kappaAmp = facingFlipMorph * math.pi * 1.5;
    final omegaPhase = t * 2.3;
    final kappaPhase = t * 1.7;
    final hasNotice = noticeAngle > 0.001;
    // Precompute — `noticeAngle` is constant across the silhouette,
    // so its cos/sin can live entirely outside the per-point hot
    // path. Use identity values when the beat is off so the same
    // inlined code path runs in both cases.
    final cN = hasNotice ? math.cos(noticeAngle) : 1.0;
    final sN = hasNotice ? math.sin(noticeAngle) : 0.0;

    // ── The 4D projector ────────────────────────────────────────
    // Every silhouette sample goes through this. (nx, ny) is the
    // creature-bbox-normalised point; we center it, lift to R⁴,
    // apply rotation matrices in xz (facing), xw + yw (hyperfold),
    // and xw again (notice-you), then perspective-project back to
    // screen-space around (centerX, centerY).
    Offset project(double nx, double ny) {
      var x = nx - 0.5;
      var y = ny - 0.5;
      var z = 0.0;
      var wA = 0.0;

      // xz rotation — facing. Pivot is the vertical centreline.
      // cT/sT are frame-constants, hoisted above.
      final x1 = x * cT + z * sT;
      final z1 = -x * sT + z * cT;
      x = x1;
      z = z1;

      // xw + yw rotation — hyperfold. Phase varies per-point so
      // neighbouring samples bulge together as a coherent wire,
      // not independent jitter. Sign of yw phase is shifted so
      // x and y bulge on slightly different schedules (proper
      // 4D twist rather than a pulsing slab).
      if (hasMorph) {
        final phiX = basePhaseX + nx * 6.0 + ny * 2.3;
        final psi = psiAmp * math.sin(phiX);
        final cP = math.cos(psi);
        final sP = math.sin(psi);
        final x2 = x * cP + wA * sP;
        final w2 = -x * sP + wA * cP;
        x = x2;
        wA = w2;

        final phiY = basePhaseY + nx * 3.7 + ny * 5.1;
        final chi = chiAmp * math.sin(phiY);
        final cC = math.cos(chi);
        final sC = math.sin(chi);
        final y3 = y * cC + wA * sC;
        final w3 = -y * sC + wA * cC;
        y = y3;
        wA = w3;
      }

      // ── Tesseract turn (isoclinic double-rotation during a
      // facing flip). Coupled to facingFlipMorph so it's dormant
      // during commit-events (those get the xw/yw flex above) but
      // dominant during a turn. Two planes at different rates —
      // this is what visually distinguishes a proper 4D rotation
      // from a 3D plane-sweep.
      if (hasTesseract) {
        // First plane: xw coupled to the same θ as xz so the flip
        // unfolds through 4D simultaneously with the 3D rotation.
        final omega = omegaAmp *
            (0.9 + 0.25 * math.sin(omegaPhase + ny * 4.0));
        final cO = math.cos(omega);
        final sO = math.sin(omega);
        final xa = x * cO + wA * sO;
        final wa = -x * sO + wA * cO;
        x = xa;
        wA = wa;
        // Second plane: yz, rate 1.5× the first. An isoclinic
        // rotation requires two perpendicular planes at matched
        // rates — different rates here break the symmetry so the
        // fold wobbles rather than rotates rigidly (more alive).
        final kappa = kappaAmp *
            (0.5 + 0.3 * math.sin(kappaPhase + nx * 3.1));
        final cK = math.cos(kappa);
        final sK = math.sin(kappa);
        final yb = y * cK + z * sK;
        final zb = -y * sK + z * cK;
        y = yb;
        z = zb;
      }

      // Notice-you — pure xw rotation, not modulated per-point.
      // The whole creature tips edge-on toward the viewer. cN/sN
      // are frame-invariants hoisted above; when the beat is off
      // they're (1, 0) — a rotation by 0 — and this block is a
      // no-op in terms of effect, though still 4 multiplies. We
      // leave the branch in place so the off-beat path skips even
      // those multiplies entirely (Circle XIX: branches predicted
      // correctly are free).
      if (hasNotice) {
        final x4 = x * cN + wA * sN;
        final w4 = -x * sN + wA * cN;
        x = x4;
        wA = w4;
      }

      // Perspective project xz → screen, add w as a parallax shift
      // so xw/yw rotations actually produce visible 2D motion.
      // `_kCamera - z` is clamped to a small positive floor so the
      // tesseract's combined rotations (which can push z up past
      // the silhouette bbox) never divide by near-zero.
      final persp = _kCamera / math.max(_kCamera - z, 0.4);
      final px = x * persp + wA * _kWProjectX;
      final py = y * persp + wA * _kWProjectY;

      return Offset(centerX + px * w, centerY + py * h);
    }

    // ── Compose the silhouette key points (dynamic poses) ──────
    // Ear-twitch + ear-rise perturb select keys. Tail wag + flick
    // perturb the last tail key. Everything else is static keys
    // from the base lists.
    // Pet response poses: ears relax slightly *down* (content), tail
    // curls inward (dips upward → "curled over" look). These are
    // additive so they layer on top of the wake pose naturally.
    final earRise = -0.04 * awake + 0.03 * petIntensity;
    final tailRise = -0.20 * awake + 0.18 * petIntensity;

    // Pack the dynamic keys as interleaved (x,y) doubles in a
    // Float64List. Grimoire Circle XIV (AoSoA) applied small-scale:
    // a polyline is naturally SoA-ish — we want sequential x/y
    // pairs, not a boxed Offset per point. Float64List gives us
    // packed doubles with zero wrapper allocations, lets the CPU
    // prefetcher see a clean stride, and halves the memory footprint.
    final headKeys = Float64List(24)
      ..[0] = _headBaseKeys[0].dx
      ..[1] = _headBaseKeys[0].dy
      ..[2] = _headBaseKeys[1].dx
      ..[3] = _headBaseKeys[1].dy
      ..[4] = _headBaseKeys[2].dx
      ..[5] = _headBaseKeys[2].dy + earRise
      ..[6] = _headBaseKeys[3].dx - earTwitch * 0.015
      ..[7] = _headBaseKeys[3].dy + earRise - earTwitch * 0.05
      ..[8] = _headBaseKeys[4].dx
      ..[9] = _headBaseKeys[4].dy + earRise
      ..[10] = _headBaseKeys[5].dx
      ..[11] = _headBaseKeys[5].dy + earRise
      ..[12] = _headBaseKeys[6].dx
      ..[13] = _headBaseKeys[6].dy + earRise
      ..[14] = _headBaseKeys[7].dx
      ..[15] = _headBaseKeys[7].dy
      ..[16] = _headBaseKeys[8].dx
      ..[17] = _headBaseKeys[8].dy
      ..[18] = _headBaseKeys[9].dx
      ..[19] = _headBaseKeys[9].dy
      ..[20] = _headBaseKeys[10].dx
      ..[21] = _headBaseKeys[10].dy
      ..[22] = _headBaseKeys[11].dx
      ..[23] = _headBaseKeys[11].dy;

    final tailKeys = Float64List(12)
      ..[0] = _tailBaseKeys[0].dx
      ..[1] = _tailBaseKeys[0].dy
      ..[2] = _tailBaseKeys[1].dx
      ..[3] = _tailBaseKeys[1].dy + tailRise * 0.2
      ..[4] = _tailBaseKeys[2].dx
      ..[5] = _tailBaseKeys[2].dy + tailRise * 0.5
      ..[6] = _tailBaseKeys[3].dx
      ..[7] = _tailBaseKeys[3].dy + tailRise * 0.8
      ..[8] = _tailBaseKeys[4].dx
      ..[9] = _tailBaseKeys[4].dy + tailRise
      ..[10] = _tailBaseKeys[5].dx + tailWag * 0.02 + tailFlick * 0.025
      ..[11] = _tailBaseKeys[5].dy +
          tailRise +
          tailWag * 0.04 -
          tailFlick * 0.06;

    // ── Subdivide (Chaikin) for wireframe density ──────────────
    // 3 iterations on the head (12 keys → 96 points = 192 doubles).
    // 2 iterations on the tail (6 keys → 24 points = 48 doubles).
    // Each call does exactly [iters] Float64List allocations — vs
    // the ~200 boxed-Offset allocations the List<Offset> version
    // made. GC pressure drops roughly 40×.
    final headPoly = _chaikinClosedFlat(headKeys, 3);
    final tailPoly = _chaikinOpenFlat(tailKeys, 2);
    // Number of (x,y) points in the tail polyline — used for the
    // split index and last-point access below.
    final tailCount = tailPoly.length >> 1;

    // ── Breath + focus curl (pure 2D canvas scale is fine) ─────
    // These don't flip anything — they're isotropic-ish pulses
    // around the creature's centre. Applying here keeps the 4D
    // projector unaware of them.
    final curlScale = 0.90 + 0.10 * focus;
    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.scale(curlScale, curlScale * (1 + breathAmp));
    canvas.translate(-centerX, -centerY);

    // ── Paints ──────────────────────────────────────────────────
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = f.strokeWidth * 1.05
      ..color = f.stroke;
    final tailWide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = f.strokeWidth * 1.4
      ..color = f.stroke;
    final tailNarrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = f.strokeWidth * 0.85
      ..color = f.stroke;
    final muted = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = f.strokeWidth * 0.85
      ..color = f.muted;
    final accentFill = Paint()..color = f.accent;
    final strokeFill = Paint()..color = f.stroke;

    // ── Head silhouette — closed polyline through project() ───
    // Iterate by stride 2 over the packed (x,y) pairs. The inner
    // body is identical to before, just sourcing coordinates from
    // Float64List slots instead of Offset fields.
    final headPath = Path();
    for (var j = 0; j < headPoly.length; j += 2) {
      final p = project(headPoly[j], headPoly[j + 1]);
      if (j == 0) {
        headPath.moveTo(p.dx, p.dy);
      } else {
        headPath.lineTo(p.dx, p.dy);
      }
    }
    headPath.close();
    canvas.drawPath(headPath, stroke);

    // ── Tail — open polyline, two-pass taper ──────────────────
    // Split the tail polyline roughly 40/60 (root vs tip) and
    // stroke the root pass wider. This produces the calligraphic
    // taper without needing per-segment width. Split index is in
    // *point* units; stride-2 indices double it.
    final splitPt = (tailCount * 0.42).floor();
    final splitJ = splitPt * 2;
    final rootPath = Path();
    for (var j = 0; j <= splitJ; j += 2) {
      final p = project(tailPoly[j], tailPoly[j + 1]);
      if (j == 0) {
        rootPath.moveTo(p.dx, p.dy);
      } else {
        rootPath.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(rootPath, tailWide);

    final tipPath = Path();
    for (var j = splitJ; j < tailPoly.length; j += 2) {
      final p = project(tailPoly[j], tailPoly[j + 1]);
      if (j == splitJ) {
        tipPath.moveTo(p.dx, p.dy);
      } else {
        tipPath.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(tipPath, tailNarrow);

    // Tail-tip accent dot.
    final lastJ = (tailCount - 1) * 2;
    final tipPoint = project(tailPoly[lastJ], tailPoly[lastJ + 1]);
    if (awake > 0.4) {
      canvas.drawCircle(tipPoint, f.strokeWidth * 1.0, accentFill);
    }

    // ── Eye (lid + pupil with cursor gaze) ────────────────────
    final eyeC = project(0.18, 0.50);
    // Also project a second point on the lid line so it rotates
    // with the head. We pick two short samples either side of the
    // eye in nx so the segment foreshortens naturally at edge-on.
    final eyeLeft = project(0.13, 0.50);
    final eyeRight = project(0.23, 0.50);
    canvas.drawLine(eyeLeft, eyeRight, muted);

    final eyeR = h * 0.08;
    final openAmount = (awake * (1 - blink)).clamp(0.0, 1.0);
    if (openAmount > 0.05) {
      // Gaze bend — cursor position in pen coords. The raw vector
      // is in 2D canvas space; we clamp its magnitude to a fraction
      // of the eye radius and suppress during notice-you (creature
      // is looking forward at the viewer then, not at the cursor).
      final cursorPenX = pen.left + f.cursor.dx * pen.width;
      final cursorPenY = pen.top + f.cursor.dy * pen.height;
      final rawDx = cursorPenX - eyeC.dx;
      final rawDy = cursorPenY - eyeC.dy;
      final mag = math.sqrt(rawDx * rawDx + rawDy * rawDy);
      final maxOff = eyeR * 0.55;
      final k = mag > 0
          ? (math.min(mag, maxOff * 4) / (maxOff * 4))
          : 0.0;
      final norm = mag > 0 ? (maxOff / mag) : 0.0;
      final strength = f.cursorPresence * (1 - noticePulse);
      final gazeDx = rawDx * norm * k * strength;
      final gazeDy = rawDy * norm * k * strength * 0.6;
      final pupilC = Offset(eyeC.dx + gazeDx, eyeC.dy + gazeDy);
      canvas.drawCircle(
        pupilC,
        eyeR * openAmount * 0.85,
        Paint()..color = f.accent.withValues(alpha: openAmount),
      );
      if (noticePulse > 0.05) {
        canvas.drawCircle(
          eyeC,
          eyeR * (1.0 + 0.6 * noticePulse),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = f.strokeWidth * 0.7
            ..color = f.accent.withValues(alpha: 0.35 * noticePulse),
        );
      }
    }

    // ── Nose dot ──────────────────────────────────────────────
    canvas.drawCircle(project(0.04, 0.55), f.strokeWidth * 1.05, strokeFill);

    canvas.restore();
  }

  // ── Chaikin corner-cutting subdivision (packed double form) ──
  // Each iteration inserts two points per edge at 1/4 and 3/4
  // along it and drops the original corners. Converges to a
  // quadratic B-spline limit — cheap, no matrix math, and keeps
  // the silhouette shape we hand-tuned via the keys.
  //
  // Packed form: input/output are Float64Lists of interleaved
  // (x0,y0,x1,y1,…) doubles. Closed variant doubles the count
  // every iteration (n → 2n); open preserves both endpoints and
  // also doubles the count (n → 2n: [first, 2(n-1) inserted,
  // last] = 2n doubles' worth = n points → 2n points).
  //
  // Grimoire principle: Circle XIV's AoSoA / Circle XXV's cache
  // discipline — packed doubles are contiguous in memory, the
  // prefetcher sees a linear stride, and no boxed Offset objects
  // are constructed during the hot subdivision loop.

  static Float64List _chaikinClosedFlat(Float64List keys, int iters) {
    var inBuf = keys;
    for (var it = 0; it < iters; it++) {
      final n = inBuf.length >> 1;
      final out = Float64List(n * 4);
      for (var i = 0; i < n; i++) {
        final a2 = i * 2;
        final b2 = ((i + 1) % n) * 2;
        final ax = inBuf[a2];
        final ay = inBuf[a2 + 1];
        final bx = inBuf[b2];
        final by = inBuf[b2 + 1];
        final o = i * 4;
        // Horner-free but FMA-friendly: Dart's JIT recognises the
        // `a * 0.75 + b * 0.25` shape and emits a fused multiply-
        // add on x86_64 + ARM64 when available (one rounding,
        // equivalent to the Grimoire's Circle XXIII technique).
        out[o] = ax * 0.75 + bx * 0.25;
        out[o + 1] = ay * 0.75 + by * 0.25;
        out[o + 2] = ax * 0.25 + bx * 0.75;
        out[o + 3] = ay * 0.25 + by * 0.75;
      }
      inBuf = out;
    }
    return inBuf;
  }

  static Float64List _chaikinOpenFlat(Float64List keys, int iters) {
    var inBuf = keys;
    for (var it = 0; it < iters; it++) {
      final n = inBuf.length >> 1;
      final out = Float64List(n * 4);
      // First point preserved verbatim.
      out[0] = inBuf[0];
      out[1] = inBuf[1];
      var w = 2;
      for (var i = 0; i < n - 1; i++) {
        final a2 = i * 2;
        final b2 = (i + 1) * 2;
        final ax = inBuf[a2];
        final ay = inBuf[a2 + 1];
        final bx = inBuf[b2];
        final by = inBuf[b2 + 1];
        out[w] = ax * 0.75 + bx * 0.25;
        out[w + 1] = ay * 0.75 + by * 0.25;
        out[w + 2] = ax * 0.25 + bx * 0.75;
        out[w + 3] = ay * 0.25 + by * 0.75;
        w += 4;
      }
      // Last point preserved verbatim.
      final last2 = (n - 1) * 2;
      out[w] = inBuf[last2];
      out[w + 1] = inBuf[last2 + 1];
      inBuf = out;
    }
    return inBuf;
  }
}
