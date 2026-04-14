// ═════════════════════════════════════════════════════════════════════════
// features/bond/bond_dock.dart — the bottom-of-sidebar bond surface
//
// IMMERSIVE not disruptive. Every bond interaction happens *inside*
// the sidebar — identity unlock, bind, peer roster, proposals, policy
// editor. Nothing routes to a separate page; nothing slides over the
// workspace. The dock IS the bond product. The aesthetic is a codex
// on parchment: section sigils, hairline dividers, small-caps
// headings, ghost-inlined inputs.
//
// State machine of `_mode`:
//
//   collapsed  →  one-row strip with state verb + chevron-up
//   overview   →  identity + bond + lattice + peers + proposals + policy
//   start      →  inline form for a fresh bond
//   join       →  inline form for an invite-blob join
//   compose    →  inline form for a new proposal
//   policy     →  inline form for editing policy rules
//
// Every transition is local to the dock — chevron flips, content
// fades through. Drawer scrolls vertically. No surfaces nested deeper
// than one parchment panel. No raw Material primitives — InkWell for
// tap, ghost dividers, MorphText where motion adds value.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/preferences_state.dart';
import '../../app/repository_state.dart';
import '../../backend/bond/bond_backend.dart';
import '../../backend/bond/objects.dart';
import '../../backend/bond/transport.dart';
import '../../backend/bond_service.dart';
import '../../backend/dtos.dart' show CommitHistoryEntry;
import '../../backend/git.dart' show listCommitHistory;
import '../../ui/material_surface.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import 'creatures/creature.dart';
import 'creatures/fox.dart';

/// The active creature for the bond pen. Modular hand-off: swap this
/// const for any other [BondCreature] (cat, owl, snake) and the
/// strip + drawer pick it up everywhere. Stateless instance so it's
/// safe as a single shared singleton.
const BondCreature _kPenCreature = FoxCreature();

/// Pen contents — discovery hint when the user has never opened the
/// dock ("bond" lowercase text), morphing into the creature once
/// they have. Crossfades on the prefs flag flip; both children are
/// always laid out so the morph swaps without a layout jump.
///
/// Stateful because it derives [BondCreatureSignals] from the active
/// repo's history + working tree — those signals drive every
/// reactive thing the creature does (drift speed, head-turn,
/// hyperfold flourish on commit).
///
/// [interestKey] is an optional GlobalKey on the widget the host
/// wants the creature to drift toward (e.g. the chevron). When non-
/// null the pen continually computes that widget's centre in
/// pen-local normalised coords and passes it as a goal — the
/// creature glides toward it via the runtime's eased pursuit. No
/// magic numbers; goal tracks layout automatically.
class _PenContent extends StatefulWidget {
  const _PenContent({
    required this.mood,
    required this.height,
    this.interestKey,
  });
  final BondCreatureMood mood;
  final double height;
  final GlobalKey? interestKey;

  @override
  State<_PenContent> createState() => _PenContentState();
}

class _PenContentState extends State<_PenContent>
    with WidgetsBindingObserver {
  List<CommitHistoryEntry>? _commits;
  String? _lastHeadHash;
  int? _lastEventMs;
  String? _lastRepoPath;
  // Self-key on the pen's outer SizedBox — used together with
  // widget.interestKey to compute the interest target's position
  // in our local coordinate space.
  final GlobalKey _penKey = GlobalKey();
  Offset? _interestGoal;
  // Pen-normalised cursor position while the pointer is inside the
  // pen region (null = pointer elsewhere). Drives the creature's
  // eye gaze. Narrow tracking region on purpose — we don't want the
  // fox to follow the mouse across the whole window, that would
  // feel needy; it notices when you approach its pen.
  Offset? _cursor;
  // OS-level window focus — tracked via the WidgetsBindingObserver
  // lifecycle, not MouseRegion. True = our window is the foreground
  // app; false = user has alt-tabbed. Creature curls when false.
  bool _windowFocused = true;
  // Global-app idle detector. Any pointer event anywhere in the
  // window refreshes [_lastActivityMs]; every second a Timer
  // re-evaluates `_userIdle = (now - last) > _idleThresholdMs`.
  // Meta beats (look-around, notice-you) fire only when idle so
  // they don't pull focus during active work.
  static const int _idleThresholdMs = 20000;
  int _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
  bool _userIdle = false;
  Timer? _idleTimer;
  // Pet gesture state.
  int? _petFiredMs;
  Timer? _petTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _windowFocused =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    // Capture every pointer event in the app — not for input, just
    // to know whether the user is doing *anything* right now. Cheap
    // (O(1) per event) and doesn't interfere with hit-testing.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onAnyPointer);
    _idleTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _evaluateIdle(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onAnyPointer);
    _idleTimer?.cancel();
    _petTimer?.cancel();
    super.dispose();
  }

  void _onAnyPointer(PointerEvent e) {
    // Only "real" input counts — filter out hover-moves with no
    // buttons so a cursor that sits still and jitters due to OS
    // noise doesn't hold us awake. Moves + down/up + scroll count.
    if (e is PointerHoverEvent || e is PointerMoveEvent ||
        e is PointerDownEvent || e is PointerUpEvent ||
        e is PointerScrollEvent) {
      _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
      if (_userIdle) {
        // Flip back to active immediately — don't wait for the
        // 1-sec timer. Creature's meta beats go quiet right away.
        if (mounted) setState(() => _userIdle = false);
      }
    }
  }

  void _evaluateIdle() {
    final idle = (DateTime.now().millisecondsSinceEpoch - _lastActivityMs) >
        _idleThresholdMs;
    if (idle != _userIdle && mounted) {
      setState(() => _userIdle = idle);
    }
  }

  /// Fires the "pet" response. Host calls this on a long-press or
  /// deliberate pointer dwell on the pen. Records a timestamp the
  /// creature's painter decays from; starts a short timer to clear
  /// it once the animation budget is exhausted (so idle-settle can
  /// stop the ticker).
  void _firePet() {
    setState(() => _petFiredMs = DateTime.now().millisecondsSinceEpoch);
    _petTimer?.cancel();
    _petTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _petFiredMs = null);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final focused = state == AppLifecycleState.resumed;
    if (focused != _windowFocused && mounted) {
      setState(() => _windowFocused = focused);
    }
  }

  void _handlePointer(PointerEvent e) {
    // Gaze tracking only matters when the drawer is actually open —
    // watching the mouse while the fox is asleep in the strip is
    // cycles-for-nobody and (per users) mildly distracting.
    if (widget.mood != BondCreatureMood.awake) {
      if (_cursor != null) setState(() => _cursor = null);
      return;
    }
    final penBox = _penKey.currentContext?.findRenderObject() as RenderBox?;
    if (penBox == null || !penBox.hasSize) return;
    final local = penBox.globalToLocal(e.position);
    final size = penBox.size;
    // Expand the tracking band slightly outside the pen — the fox
    // should see your cursor approach from just above/below the row
    // (the sidebar's narrow, so strict containment would mean eyes
    // never get to track). Still bounded so a cursor on the other
    // side of the screen is ignored.
    const slack = 24.0;
    final inside = local.dx >= -slack &&
        local.dx <= size.width + slack &&
        local.dy >= -slack &&
        local.dy <= size.height + slack;
    if (!inside) {
      if (_cursor != null) setState(() => _cursor = null);
      return;
    }
    final nx = (local.dx / size.width).clamp(-0.2, 1.2);
    final ny = (local.dy / size.height).clamp(-0.2, 1.2);
    final newCursor = Offset(nx.toDouble(), ny.toDouble());
    if (_cursor != newCursor) setState(() => _cursor = newCursor);
  }

  void _handleExit(PointerEvent _) {
    if (_cursor != null) setState(() => _cursor = null);
  }

  /// Reads the interest widget's render box (when present) and
  /// translates its centre into pen-local (0..1, 0..1) coordinates.
  /// Returns null if either render object isn't laid out yet.
  void _recomputeGoal() {
    final iKey = widget.interestKey;
    if (iKey == null) {
      if (_interestGoal != null) {
        setState(() => _interestGoal = null);
      }
      return;
    }
    final penBox = _penKey.currentContext?.findRenderObject() as RenderBox?;
    final iBox = iKey.currentContext?.findRenderObject() as RenderBox?;
    if (penBox == null || iBox == null || !penBox.hasSize || !iBox.hasSize) {
      return;
    }
    final iCentreGlobal = iBox.localToGlobal(
      Offset(iBox.size.width / 2, iBox.size.height / 2),
    );
    final iCentreLocal = penBox.globalToLocal(iCentreGlobal);
    final size = penBox.size;
    if (size.width <= 0 || size.height <= 0) return;
    // Clamp to a comfortable inner band so the creature never tries
    // to walk off the pen edge — the interest point may be just
    // outside the pen's rect (e.g. the chevron sits past the right
    // edge), which is fine; we read its direction, not its precise
    // location.
    final nx = (iCentreLocal.dx / size.width).clamp(0.0, 1.0);
    final ny = (iCentreLocal.dy / size.height).clamp(0.0, 1.0);
    // Goal anchor — pull near the interest, not literally onto it,
    // so the creature reads as "approaching" rather than "stuck on."
    final goalNx = (0.65 + nx * 0.25).clamp(0.05, 0.95);
    final goalNy = ny;
    final newGoal = Offset(goalNx, goalNy);
    if (_interestGoal != newGoal) {
      setState(() => _interestGoal = newGoal);
    }
  }

  Future<void> _loadCommits(String repoPath) async {
    final r = await listCommitHistory(repoPath, limit: 32);
    if (!mounted) return;
    final commits = r.ok ? r.data : null;
    final newHead = (commits?.isNotEmpty ?? false) ? commits!.first.commitHash : null;
    setState(() {
      _commits = commits;
      // First load on this repo: just record the HEAD without
      // firing an event. Subsequent changes fire a hyperfold.
      if (_lastHeadHash != null && newHead != null && newHead != _lastHeadHash) {
        _lastEventMs = DateTime.now().millisecondsSinceEpoch;
      }
      _lastHeadHash = newHead;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final opened = context.watch<PreferencesState>().bondDockOpenedOnce;
    final repoPath = context.watch<RepositoryState>().activePath;
    // Reload commits on repo switch (and on first build for this
    // repo). Cheap — git log -n 32.
    if (repoPath != null && repoPath != _lastRepoPath) {
      _lastRepoPath = repoPath;
      _commits = null;
      _lastHeadHash = null;
      _loadCommits(repoPath);
    }
    final dirtyCount =
        context.watch<RepositoryState>().status?.files.length ?? 0;
    // Re-evaluate the interest goal each frame the parent rebuilds —
    // catches chevron movement from drawer open/close/resize without
    // needing every parent to call us.
    if (widget.interestKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recomputeGoal();
      });
    }
    final signals = _computeSignals(dirtyCount);
    return MouseRegion(
      opaque: false,
      onHover: _handlePointer,
      onEnter: _handlePointer,
      onExit: _handleExit,
      // Long-press on the pen = "pet". Only wires in drawer-open
      // mode so it doesn't interfere with the collapsed strip's
      // tap-to-expand gesture.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: widget.mood == BondCreatureMood.awake
            ? _firePet
            : null,
        child: SizedBox(
      key: _penKey,
      height: widget.height,
      child: AnimatedSwitcher(
        duration: context.motion(const Duration(milliseconds: 320)),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: opened
            ? KeyedSubtree(
                key: const ValueKey('creature'),
                child: BondCreatureWidget(
                  creature: _kPenCreature,
                  mood: widget.mood,
                  signals: signals,
                  stroke: t.textNormal,
                  accent: t.accentBright,
                  muted: t.textMuted,
                  height: widget.height,
                ),
              )
            : Align(
                key: const ValueKey('label'),
                alignment: Alignment.centerLeft,
                child: _DiscoveryWordmark(color: t.textNormal),
              ),
      ),
      ),
      ),
    );
  }

  /// Maps live repo state to creature signals. All numbers derived,
  /// none hard-coded to time-of-day or hand-tuned thresholds beyond
  /// natural normalisation bounds.
  BondCreatureSignals _computeSignals(int dirtyCount) {
    final commits = _commits ?? const <CommitHistoryEntry>[];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Excitement: how many commits in the last hour.
    var recentCount = 0;
    int? lastCommitMs;
    for (final c in commits) {
      try {
        final ms = DateTime.parse(c.authoredAt).millisecondsSinceEpoch;
        lastCommitMs ??= ms;
        if (nowMs - ms < 3600000) recentCount++;
      } catch (_) {}
    }
    // 5 commits/hour saturates; relaxed creature for slower work.
    final excitement = (recentCount / 5).clamp(0.0, 1.0);
    // Attention: dirty file count, capped. Same scale the HEAD
    // halo uses on the constellation, kept consistent on purpose.
    final attention = (dirtyCount / 12).clamp(0.0, 1.0);
    // Restlessness: hours since last activity, capped at a day.
    var restlessness = 0.0;
    if (lastCommitMs != null) {
      final hours = (nowMs - lastCommitMs) / 3600000;
      restlessness = (hours / 24).clamp(0.0, 1.0);
    }
    return BondCreatureSignals(
      excitement: excitement,
      attention: attention,
      restlessness: restlessness,
      lastEventMs: _lastEventMs,
      lastPetMs: _petFiredMs,
      goal: _interestGoal,
      cursor: _cursor,
      windowFocused: _windowFocused,
      userIdle: _userIdle,
    );
  }
}

enum _DockMode { collapsed, overview, start, join, compose, policy }

class BondDock extends StatefulWidget {
  const BondDock({super.key});

  @override
  State<BondDock> createState() => _BondDockState();
}

class _BondDockState extends State<BondDock> {
  _DockMode _mode = _DockMode.collapsed;

  @override
  Widget build(BuildContext context) {
    final repoPath = context.watch<RepositoryState>().activePath;
    final service = context.watch<BondService>();
    final membership = repoPath == null
        ? null
        : service.membershipFor(repoPath);
    final listenable = (repoPath != null && membership != null)
        ? service.backend.runtimeListenable(repoPath)
        : null;

    return ValueListenableBuilder<bool>(
      valueListenable: service.online,
      builder: (context, online, _) => ListenableBuilder(
        listenable: listenable ?? const _IdleListenable(),
        builder: (context, _) {
          final snap = (repoPath != null && membership != null)
              ? service.backend.snapshot(repoPath)
              : null;
          return SizedBox(
            width: double.infinity,
            child: _DockChrome(
              child: AnimatedSize(
                duration: context.motion(const Duration(milliseconds: 220)),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: _buildBody(
                  context: context,
                  service: service,
                  repoPath: repoPath,
                  membership: membership,
                  snapshot: snap,
                  online: online,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required BondService service,
    required String? repoPath,
    required BondMembership? membership,
    required BondUiSnapshot? snapshot,
    required bool online,
  }) {
    if (_mode == _DockMode.collapsed) {
      return _CollapsedStrip(
        service: service,
        membership: membership,
        snapshot: snapshot,
        online: online,
        onTap: () {
          // First click flips the discovery hint off forever — the
          // text "bond" morphs to the creature on next paint via the
          // PreferencesState rebuild.
          context.read<PreferencesState>().markBondDockOpened();
          setState(() => _mode = _DockMode.overview);
        },
      );
    }
    return _DrawerColumn(
      mode: _mode,
      service: service,
      repoPath: repoPath,
      membership: membership,
      snapshot: snapshot,
      online: online,
      onModeChanged: (m) => setState(() => _mode = m),
      onCollapse: () => setState(() => _mode = _DockMode.collapsed),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Chrome — the parchment surface this whole thing lives on

class _DockChrome extends StatelessWidget {
  const _DockChrome({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ink-line divider — the dock IS the bottom of the sidebar.
        // Slightly stronger than a hairline so the eye snaps to the
        // boundary between projects list and bond surface.
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: t.chromeBorderSubtle,
        ),
        child,
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Collapsed strip — the always-on one-row footer

class _CollapsedStrip extends StatefulWidget {
  const _CollapsedStrip({
    required this.service,
    required this.membership,
    required this.snapshot,
    required this.online,
    required this.onTap,
  });
  final BondService service;
  final BondMembership? membership;
  final BondUiSnapshot? snapshot;
  final bool online;
  final VoidCallback onTap;

  @override
  State<_CollapsedStrip> createState() => _CollapsedStripState();
}

class _CollapsedStripState extends State<_CollapsedStrip> {
  bool _hover = false;
  // Stable key that travels with the chevron icon. Lives on state so
  // it survives rebuilds — the pen reads its render box each frame
  // to steer the creature toward it without hard-coded coordinates.
  final GlobalKey _chevronKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = _resolveState(
      widget.service, widget.membership, widget.snapshot, widget.online);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        // Listener catches the down-event before any scroll handler
        // can claim it; reliable across the whole sidebar tree.
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => widget.onTap(),
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 120)),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 13),
          color: _hover
              ? t.chromeBorderFaint
              : Colors.transparent,
          child: Row(
            children: [
              _StateDot(state: state),
              const SizedBox(width: 10),
              // Pen — text "bond" until first interaction, morphs
              // into the creature (asleep here, awake in the drawer
              // header) thereafter.
              Expanded(
                child: _PenContent(
                  mood: BondCreatureMood.asleep,
                  height: 18,
                  interestKey: _chevronKey,
                ),
              ),
              KeyedSubtree(
                key: _chevronKey,
                child: Icon(
                  Icons.keyboard_arrow_up,
                  size: 16,
                  color: _hover ? t.textNormal : t.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Drawer — the inline immersive surface

class _DrawerColumn extends StatelessWidget {
  const _DrawerColumn({
    required this.mode,
    required this.service,
    required this.repoPath,
    required this.membership,
    required this.snapshot,
    required this.online,
    required this.onModeChanged,
    required this.onCollapse,
  });

  final _DockMode mode;
  final BondService service;
  final String? repoPath;
  final BondMembership? membership;
  final BondUiSnapshot? snapshot;
  final bool online;
  final ValueChanged<_DockMode> onModeChanged;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      // Cap drawer height so it overlays politely instead of pushing
      // the project list off-screen on short windows.
      constraints: const BoxConstraints(maxHeight: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DrawerHeader(
            mode: mode,
            membership: membership,
            online: online,
            isUnlocked: service.isUnlocked,
            snapshot: snapshot,
            onCollapse: onCollapse,
            onBack: mode == _DockMode.overview
                ? null
                : () => onModeChanged(_DockMode.overview),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: _drawerContent(context, t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerContent(BuildContext context, AppTokens t) {
    if (repoPath == null) {
      return const _Murmur('open a repo first.');
    }
    if (!service.isUnlocked) {
      return _IdentityField(repoPath: repoPath!);
    }
    if (membership == null) {
      switch (mode) {
        case _DockMode.start:
          return _StartForm(
            repoPath: repoPath!,
            onDone: () {},
          );
        case _DockMode.join:
          return _JoinForm(
            repoPath: repoPath!,
            onDone: () {},
          );
        default:
          return _SetupChoices(
            onStart: () => (context.findAncestorStateOfType<_BondDockState>())
                ?.setState(() => (context
                    .findAncestorStateOfType<_BondDockState>()!
                    ._mode = _DockMode.start)),
            onJoin: () => (context.findAncestorStateOfType<_BondDockState>())
                ?.setState(() => (context
                    .findAncestorStateOfType<_BondDockState>()!
                    ._mode = _DockMode.join)),
          );
      }
    }
    // Bonded — overview or one of the form modes.
    switch (mode) {
      case _DockMode.compose:
        return _ComposeForm(
          repoPath: repoPath!,
          onDone: () => _back(context),
        );
      case _DockMode.policy:
        return _PolicyForm(
          repoPath: repoPath!,
          snapshot: snapshot,
          onDone: () => _back(context),
        );
      default:
        return _OverviewBody(
          repoPath: repoPath!,
          membership: membership!,
          snapshot: snapshot,
          onCompose: () => _navigate(context, _DockMode.compose),
          onPolicy: () => _navigate(context, _DockMode.policy),
        );
    }
  }

  void _back(BuildContext context) {
    final state = context.findAncestorStateOfType<_BondDockState>();
    state?.setState(() => state._mode = _DockMode.overview);
  }

  void _navigate(BuildContext context, _DockMode m) {
    final state = context.findAncestorStateOfType<_BondDockState>();
    state?.setState(() => state._mode = m);
  }
}

class _DrawerHeader extends StatefulWidget {
  const _DrawerHeader({
    required this.mode,
    required this.membership,
    required this.online,
    required this.isUnlocked,
    required this.snapshot,
    required this.onCollapse,
    required this.onBack,
  });
  final _DockMode mode;
  final BondMembership? membership;
  final bool online;
  final bool isUnlocked;
  final BondUiSnapshot? snapshot;
  final VoidCallback onCollapse;
  final VoidCallback? onBack;

  @override
  State<_DrawerHeader> createState() => _DrawerHeaderState();
}

class _DrawerHeaderState extends State<_DrawerHeader> {
  // Stable across rebuilds — the pen reads this render box to pull
  // the creature toward the chevron regardless of layout.
  final GlobalKey _chevronKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
      child: Row(
        children: [
          if (widget.onBack != null)
            _GhostIconButton(
              icon: Icons.arrow_back,
              tooltip: 'back',
              onTap: widget.onBack!,
            )
          else
            _StateDot(state: _resolveState(
                Provider.of<BondService>(context, listen: false),
                widget.membership,
                widget.snapshot,
                widget.online), small: true),
          const SizedBox(width: 8),
          Expanded(
            child: _PenContent(
              mood: BondCreatureMood.awake,
              height: 16,
              interestKey: _chevronKey,
            ),
          ),
          if (widget.membership != null &&
              widget.mode != _DockMode.overview)
            _GhostIconButton(
              icon: Icons.close,
              tooltip: 'cancel',
              onTap: () {
                final state = context
                    .findAncestorStateOfType<_BondDockState>();
                state?.setState(() => state._mode = _DockMode.overview);
              },
            ),
          KeyedSubtree(
            key: _chevronKey,
            child: _GhostIconButton(
              icon: Icons.keyboard_arrow_down,
              onTap: widget.onCollapse,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Setup choices when unlocked but unbonded

class _SetupChoices extends StatelessWidget {
  const _SetupChoices({required this.onStart, required this.onJoin});
  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Two glyph-led tiles, no explanatory paragraph. The state-dot
        // in the strip already says "no membership" — the drawer
        // shouldn't repeat that.
        _CodexAction(
          label: 'start',
          subtitle: 'a new bond',
          glyph: '✦',
          onTap: onStart,
        ),
        _CodexAction(
          label: 'join',
          subtitle: 'an invite',
          glyph: '⌁',
          onTap: onJoin,
        ),
      ],
    );
  }
}

class _CodexAction extends StatefulWidget {
  const _CodexAction({
    required this.label,
    required this.subtitle,
    required this.glyph,
    required this.onTap,
  });
  final String label;
  final String subtitle;
  final String glyph;
  final VoidCallback onTap;

  @override
  State<_CodexAction> createState() => _CodexActionState();
}

class _CodexActionState extends State<_CodexAction> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => widget.onTap(),
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 140)),
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: _hover
                ? t.accentBright.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: _hover ? t.accentBright : t.chromeBorderSubtle,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  widget.glyph,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _hover ? t.accentBright : t.textNormal,
                    fontSize: 18,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: t.textNormal,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Identity unlock — visual sigil + minimal phrase field

class _IdentityField extends StatefulWidget {
  const _IdentityField({required this.repoPath});
  final String repoPath;
  @override
  State<_IdentityField> createState() => _IdentityFieldState();
}

class _IdentityFieldState extends State<_IdentityField> {
  final _phrase = TextEditingController();
  bool _persist = true;
  bool _busy = false;
  Object? _errSignal;
  _BondErrKind _errKind = _BondErrKind.fail;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _errSignal = null;
    });
    try {
      await context.read<BondService>().unlock(
            _phrase.text,
            persistToKeychain: _persist,
          );
      _phrase.clear();
    } catch (e) {
      setState(() {
        _errSignal = Object();
        _errKind = _classifyErr(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Same constellation as the bonded overview — the repo's
        // git DAG. Lets the user see what they're about to bond
        // into before they unlock. Compact height on the locked
        // surface so the unlock affordance dominates.
        _RepoConstellation(repoPath: widget.repoPath, height: 56),
        const SizedBox(height: 6),
        _GhostInput(
          controller: _phrase,
          obscure: true,
          hint: 'phrase',
          enabled: !_busy,
          onSubmit: _unlock,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _GhostKeepUnlockedToggle(
              value: _persist,
              onChanged: (v) => setState(() => _persist = v),
            ),
            const Spacer(),
            _GhostButton(
              label: 'unlock',
              onTap: _unlock,
              busy: _busy,
              accent: true,
              errorToken: _errSignal,
              errorKind: _errKind,
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact "12h" pill that toggles like a checkbox but reads as a
/// duration chip — much narrower than a labelled checkbox + sentence.
class _GhostKeepUnlockedToggle extends StatefulWidget {
  const _GhostKeepUnlockedToggle({
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  State<_GhostKeepUnlockedToggle> createState() =>
      _GhostKeepUnlockedToggleState();
}

class _GhostKeepUnlockedToggleState extends State<_GhostKeepUnlockedToggle> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = widget.value;
    // Icon-only toggle. The lock-clock glyph itself already reads
    // as "stay unlocked over time" — adding the "12h" text on the
    // button was redundant chrome. The tooltip carries the exact
    // duration for users who need it.
    return Tooltip(
      message: 'stay unlocked 12h',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerUp: (_) => widget.onChanged(!on),
          child: AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 100)),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: on
                  ? t.accentBright.withValues(alpha: 0.10)
                  : (_hover ? t.chromeBorderFaint : Colors.transparent),
              border: Border.all(
                color: on ? t.accentBright : t.chromeBorderSubtle,
                width: 1,
              ),
            ),
            child: Icon(
              on ? Icons.lock_clock : Icons.lock_clock_outlined,
              size: 14,
              color: on ? t.accentBright : t.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Start form

class _StartForm extends StatefulWidget {
  const _StartForm({required this.repoPath, required this.onDone});
  final String repoPath;
  final VoidCallback onDone;
  @override
  State<_StartForm> createState() => _StartFormState();
}

class _StartFormState extends State<_StartForm> {
  final _name = TextEditingController();
  final _bootstrap = TextEditingController();
  final _swarm = TextEditingController();
  bool _busy = false;
  Object? _errSignal;
  _BondErrKind _errKind = _BondErrKind.fail;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // .bond.yml prefill if present
      final cfg = await context
          .read<BondService>()
          .readBondRepoConfig(widget.repoPath);
      if (!mounted) return;
      if (cfg.bootstrapCommit != null) _bootstrap.text = cfg.bootstrapCommit!;
      if (cfg.displayName != null) _name.text = cfg.displayName!;
      if (_bootstrap.text.isEmpty) {
        await _autofillRoot();
      }
    });
  }

  Future<void> _autofillRoot() async {
    try {
      final res = await Process.run(
        'git',
        ['rev-list', '--max-parents=0', 'HEAD'],
        workingDirectory: widget.repoPath,
        runInShell: false,
      );
      if (res.exitCode == 0 && mounted) {
        final hex = (res.stdout as String).split('\n').first.trim();
        if (hex.isNotEmpty && _bootstrap.text.isEmpty) {
          _bootstrap.text = hex;
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _bootstrap.dispose();
    _swarm.dispose();
    super.dispose();
  }

  Future<void> _bind() async {
    setState(() {
      _busy = true;
      _errSignal = null;
    });
    try {
      await context.read<BondService>().bindBond(
            repoPath: widget.repoPath,
            bootstrapCommit: _bootstrap.text.trim(),
            swarmPhrase: _swarm.text,
            displayName: _name.text.trim().isEmpty ? 'Bond' : _name.text.trim(),
          );
      widget.onDone();
    } catch (e) {
      setState(() {
        _errSignal = Object();
        _errKind = _classifyErr(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GhostInput(controller: _name, hint: 'name', enabled: !_busy),
        const SizedBox(height: 6),
        _GhostInput(
          controller: _bootstrap,
          hint: 'bootstrap commit',
          enabled: !_busy,
          mono: true,
        ),
        const SizedBox(height: 6),
        _GhostInput(
          controller: _swarm,
          hint: 'swarm phrase',
          obscure: true,
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _GhostButton(
              label: 'create',
              onTap: _bind,
              busy: _busy,
              accent: true,
              errorToken: _errSignal,
              errorKind: _errKind,
            ),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Join form

class _JoinForm extends StatefulWidget {
  const _JoinForm({required this.repoPath, required this.onDone});
  final String repoPath;
  final VoidCallback onDone;
  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  final _invite = TextEditingController();
  final _swarm = TextEditingController();
  bool _busy = false;
  Object? _errSignal;
  _BondErrKind _errKind = _BondErrKind.fail;

  @override
  void dispose() {
    _invite.dispose();
    _swarm.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _invite.text = text;
      setState(() {});
    }
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _errSignal = null;
    });
    try {
      await context.read<BondService>().bindFromInvite(
            repoPath: widget.repoPath,
            inviteBlob: _invite.text,
            swarmPhrase: _swarm.text,
          );
      widget.onDone();
    } catch (e) {
      setState(() {
        _errSignal = Object();
        _errKind = _classifyErr(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _GhostInput(
                controller: _invite,
                hint: 'bond1:…',
                enabled: !_busy,
                mono: true,
              ),
            ),
            const SizedBox(width: 6),
            _GhostButton(label: 'paste', onTap: _busy ? null : _paste),
          ],
        ),
        const SizedBox(height: 6),
        _GhostInput(
          controller: _swarm,
          hint: 'swarm phrase',
          obscure: true,
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _GhostButton(
              label: 'join',
              onTap: _join,
              busy: _busy,
              accent: true,
              errorToken: _errSignal,
              errorKind: _errKind,
            ),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Overview — the bonded landing surface

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({
    required this.repoPath,
    required this.membership,
    required this.snapshot,
    required this.onCompose,
    required this.onPolicy,
  });
  final String repoPath;
  final BondMembership membership;
  final BondUiSnapshot? snapshot;
  final VoidCallback onCompose;
  final VoidCallback onPolicy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final peers = snapshot?.peers ?? const <BondPeerView>[];
    final proposals = snapshot?.proposals ?? const <BondProposalView>[];
    final policy = snapshot?.currentPolicy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bond identity rune.
        Row(
          children: [
            Text(
              membership.bondId.shortHex,
              style: TextStyle(
                color: t.textMuted,
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            _GhostButton(
              label: 'invite',
              onTap: () => _copyInvite(context),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Constellation = the repo's actual git DAG. Stars are real
        // commits from listCommitHistory; positions encode (recency,
        // author bucket); edges are real parent-child links from
        // each commit's parentHashes; HEAD is the pulsing "you are
        // here." No peer/bond data here — that's the strip's job.
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _RepoConstellation(repoPath: repoPath, height: 76),
        ),
        // Section: peers
        _SectionLabel('peers · ${peers.length}'),
        if (peers.isEmpty)
          const _Murmur('no peers yet — share the invite.')
        else
          // ValueKey on the peer's pubkey — when a peer joins /
          // leaves / reorders, Flutter matches by identity instead
          // of list position, so surviving peer rows don't get
          // unmounted and remounted (which reads as pop-in-pop-out).
          for (final p in peers)
            _PeerLine(
              key: ValueKey(p.pubkeyHex),
              repoPath: repoPath,
              peer: p,
            ),
        const _Hairline(),
        // Section: proposals
        Row(
          children: [
            Expanded(child: _SectionLabel('proposals · ${proposals.length}')),
            _GhostMicroAction(label: '+ new', onTap: onCompose),
          ],
        ),
        if (proposals.isEmpty)
          const _Murmur('nothing pending.')
        else
          for (final pr in proposals.take(3))
            _ProposalLine(
              key: ValueKey(pr.proposalId),
              repoPath: repoPath,
              proposal: pr,
            ),
        const _Hairline(),
        // Section: policy
        Row(
          children: [
            Expanded(child: _SectionLabel('policy')),
            _GhostMicroAction(
              label: policy == null ? '+ create' : 'edit',
              onTap: onPolicy,
            ),
          ],
        ),
        if (policy == null)
          const _Murmur('open — any peer\'s refs adoptable.')
        else
          for (final r in policy.rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${r.refPattern}  ✓${r.minApprovals}',
                style: TextStyle(
                  color: t.textNormal,
                  fontSize: 11,
                  fontFamily: 'JetBrainsMono',
                  height: 1.5,
                ),
              ),
            ),
        const _Hairline(),
        // Footer — local lock + leave
        Row(
          children: [
            _GhostButton(
              label: 'lock',
              onTap: () => context.read<BondService>().lock(),
            ),
            const Spacer(),
            _GhostButton(
              label: 'leave',
              onTap: () => _confirmLeave(context),
              danger: true,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _copyInvite(BuildContext context) async {
    final blob = context.read<BondService>().buildInvite(repoPath);
    await Clipboard.setData(ClipboardData(text: blob));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('invite copied — send the swarm phrase separately.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('leave this bond?'),
        content: Text(
          'wipes local bond state for "${membership.displayName}". '
          'identity key + other bonds untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('leave'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<BondService>().unbind(repoPath);
    }
  }
}

class _PeerLine extends StatelessWidget {
  const _PeerLine({super.key, required this.repoPath, required this.peer});
  final String repoPath;
  final BondPeerView peer;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = context.watch<BondService>().cachedLabelFor(
          repoPath: repoPath,
          pubkeyHex: peer.pubkeyHex,
        );
    final dotColor = peer.isRevoked
        ? t.stateDeleted
        : peer.attached
            ? t.accentBright
            : t.chromeBorderStrong;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label?.isNotEmpty == true ? label! : peer.shortHex,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: peer.isRevoked ? t.textMuted : t.textNormal,
                fontSize: 11,
                fontFamily: label?.isNotEmpty == true ? null : 'JetBrainsMono',
                decoration:
                    peer.isRevoked ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (peer.coordinate != null)
            Text(
              peer.coordinate!.toHex(),
              style: TextStyle(
                color: t.textMuted,
                fontSize: 9,
                fontFamily: 'JetBrainsMono',
              ),
            ),
        ],
      ),
    );
  }
}

class _ProposalLine extends StatelessWidget {
  const _ProposalLine(
      {super.key, required this.repoPath, required this.proposal});
  final String repoPath;
  final BondProposalView proposal;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final approvals = proposal.approvals;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '✓$approvals',
              style: TextStyle(
                color: approvals > 0 ? t.accentBright : t.textMuted,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proposal.title.isEmpty ? '(untitled)' : proposal.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${proposal.proposerHex.substring(0, 6)} → ${proposal.targetRef}',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ],
            ),
          ),
          _GhostMicroAction(
            label: 'approve',
            onTap: () => _approve(context),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context) async {
    final svc = context.read<BondService>();
    final err = await svc.publishAttestation(
      repoPath: repoPath,
      proposalId: _unhex(proposal.proposalId),
      verdict: AttestationVerdict.approve,
      body: '',
      targetCommit: _unhex(proposal.sourceCommitHex),
    );
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Compose form (inline)

class _ComposeForm extends StatefulWidget {
  const _ComposeForm({required this.repoPath, required this.onDone});
  final String repoPath;
  final VoidCallback onDone;
  @override
  State<_ComposeForm> createState() => _ComposeFormState();
}

class _ComposeFormState extends State<_ComposeForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _target = TextEditingController(text: 'refs/heads/main');
  String? _commitHex;
  String _sourceRef = '';
  bool _busy = false;
  Object? _errSignal;
  _BondErrKind _errKind = _BondErrKind.fail;

  @override
  void initState() {
    super.initState();
    _autofill();
  }

  Future<void> _autofill() async {
    try {
      final ref = await Process.run(
        'git',
        ['symbolic-ref', '--short', 'HEAD'],
        workingDirectory: widget.repoPath,
        runInShell: false,
      );
      if (ref.exitCode == 0 && mounted) {
        _sourceRef =
            'refs/heads/${(ref.stdout as String).trim()}';
      }
      final head = await Process.run(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: widget.repoPath,
        runInShell: false,
      );
      if (head.exitCode == 0 && mounted) {
        setState(() => _commitHex = (head.stdout as String).trim());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_commitHex == null) {
      setState(() {
        _errSignal = Object();
        _errKind = _BondErrKind.fail;
      });
      return;
    }
    setState(() {
      _busy = true;
      _errSignal = null;
    });
    try {
      final r = await context.read<BondService>().publishProposal(
            repoPath: widget.repoPath,
            recipientPubkey: Uint8List(32),
            sourceRef: _sourceRef,
            sourceCommit: _unhex(_commitHex!),
            targetRef: _target.text.trim(),
            title: _title.text.trim(),
            body: _body.text.trim(),
          );
      if (r.error != null) {
        setState(() {
        _errSignal = Object();
        _errKind = _BondErrKind.fail;
      });
      } else {
        widget.onDone();
      }
    } catch (e) {
      setState(() {
        _errSignal = Object();
        _errKind = _classifyErr(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GhostInput(controller: _title, hint: 'title', enabled: !_busy),
        const SizedBox(height: 8),
        _GhostInput(
          controller: _target,
          hint: 'target ref',
          mono: true,
          enabled: !_busy,
        ),
        const SizedBox(height: 6),
        Text(
          _commitHex == null
              ? 'detecting HEAD…'
              : 'HEAD ${_commitHex!.substring(0, 12)}  ·  $_sourceRef',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 10,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(height: 8),
        _GhostInput(
          controller: _body,
          hint: 'body (optional)',
          enabled: !_busy,
          minLines: 3,
          maxLines: 5,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _GhostButton(
              label: 'publish',
              onTap: _publish,
              busy: _busy,
              accent: true,
              errorToken: _errSignal,
              errorKind: _errKind,
            ),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Policy form (inline; one rule for now — refPattern + minApprovals)

class _PolicyForm extends StatefulWidget {
  const _PolicyForm({
    required this.repoPath,
    required this.snapshot,
    required this.onDone,
  });
  final String repoPath;
  final BondUiSnapshot? snapshot;
  final VoidCallback onDone;
  @override
  State<_PolicyForm> createState() => _PolicyFormState();
}

class _PolicyFormState extends State<_PolicyForm> {
  final _ref = TextEditingController(text: 'refs/heads/main');
  final _min = TextEditingController(text: '1');
  bool _busy = false;
  Object? _errSignal;
  _BondErrKind _errKind = _BondErrKind.fail;

  @override
  void initState() {
    super.initState();
    final p = widget.snapshot?.currentPolicy;
    if (p != null && p.rules.isNotEmpty) {
      _ref.text = p.rules.first.refPattern;
      _min.text = p.rules.first.minApprovals.toString();
    }
  }

  @override
  void dispose() {
    _ref.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final n = int.tryParse(_min.text.trim());
    if (n == null || n < 0 || _ref.text.trim().isEmpty) {
      setState(() {
        _errSignal = Object();
        _errKind = _BondErrKind.fail;
      });
      return;
    }
    setState(() {
      _busy = true;
      _errSignal = null;
    });
    try {
      final err = await context.read<BondService>().publishPolicy(
        repoPath: widget.repoPath,
        rules: [
          PolicyRule(refPattern: _ref.text.trim(), minApprovals: n),
        ],
      );
      if (err != null) {
        setState(() {
        _errSignal = Object();
        _errKind = _BondErrKind.fail;
      });
      } else {
        widget.onDone();
      }
    } catch (e) {
      setState(() {
        _errSignal = Object();
        _errKind = _classifyErr(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GhostInput(
          controller: _ref,
          hint: 'ref pattern',
          mono: true,
          enabled: !_busy,
        ),
        const SizedBox(height: 6),
        _GhostInput(
          controller: _min,
          hint: 'min ✓',
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _GhostButton(
              label: 'publish',
              onTap: _publish,
              busy: _busy,
              accent: true,
              errorToken: _errSignal,
              errorKind: _errKind,
            ),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Repo-DAG constellation — the actual git history rendered as stars
//
// Stars come from `listCommitHistory(repoPath)` — every dot is a real
// commit. Position:
//   x = recency (newest right, oldest left)
//   y = deterministic author bucket (FNV1a(authorEmail) → row)
// Edges are real parent-child relationships from CommitHistoryEntry's
// `parentHashes`. HEAD (the newest commit) gets the pulsing self
// marker. Branch tips (entries with non-empty `refNames`) render as
// larger circles. Merges (`isMerge`) get a hairline outer ring.
//
// Nothing faked. Nothing decorative. Every visual element maps to
// data the user could verify with `git log --graph` if they wanted.

class _RepoConstellation extends StatefulWidget {
  const _RepoConstellation({required this.repoPath, this.height = 96});
  final String repoPath;
  final double height;

  @override
  State<_RepoConstellation> createState() => _RepoConstellationState();
}

class _RepoConstellationState extends State<_RepoConstellation>
    with SingleTickerProviderStateMixin {
  // Pulse controller — only ticks when there's a real reason
  // (dirty tree, fresh HEAD commit, or sync in flight). Idle repos
  // freeze at the midpoint phase so HEAD reads as stable, not as
  // breathing-for-no-reason.
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));
  List<CommitHistoryEntry>? _commits;
  bool _loading = true;
  static const _kCommitWindow = 96;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_RepoConstellation old) {
    super.didUpdateWidget(old);
    if (old.repoPath != widget.repoPath) {
      _commits = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final r = await listCommitHistory(widget.repoPath, limit: _kCommitWindow);
    if (!mounted) return;
    setState(() {
      _commits = r.ok ? r.data : null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final commits = _commits;
    if (commits == null || commits.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            _loading ? '' : 'no commits yet',
            style: TextStyle(color: t.textMuted, fontSize: 10),
          ),
        ),
      );
    }
    // Working-tree state — drives the HEAD-halo "warm" tint when the
    // repo is dirty AND gates whether the pulse animates at all.
    final repoState = context.watch<RepositoryState>();
    final dirtyCount = repoState.status?.files.length ?? 0;
    final headAgeMs = _ageOfHead(commits);
    final shouldAnimate =
        dirtyCount > 0 || (headAgeMs != null && headAgeMs < 60000);
    _syncPulse(shouldAnimate);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => SizedBox(
        width: double.infinity,
        height: widget.height,
        child: CustomPaint(
          painter: _RepoConstellationPainter(
            commits: commits,
            phase: _pulse.value,
            animating: shouldAnimate,
            accent: t.accentBright,
            text: t.textMuted,
            border: t.chromeBorderSubtle,
            dirtyFileCount: dirtyCount,
          ),
        ),
      ),
    );
  }

  /// Switches the pulse on iff [active] is true; if it's false,
  /// stops the animator at a stable midpoint phase so HEAD reads
  /// as a steady halo rather than freezing mid-breath.
  void _syncPulse(bool active) {
    if (active) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      if (_pulse.isAnimating) {
        _pulse.stop();
        // Park the phase at 0.5 — the halo's "neutral" radius. Any
        // other value would freeze mid-pulse and look glitched.
        _pulse.value = 0.5;
      }
    }
  }

  /// Milliseconds since the newest commit was authored, or null if
  /// the timestamp didn't parse.
  int? _ageOfHead(List<CommitHistoryEntry> commits) {
    if (commits.isEmpty) return null;
    final ts = commits.first.authoredAt;
    if (ts.isEmpty) return null;
    try {
      return DateTime.now().millisecondsSinceEpoch -
          DateTime.parse(ts).millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }
}

class _RepoConstellationPainter extends CustomPainter {
  _RepoConstellationPainter({
    required this.commits,
    required this.phase,
    required this.animating,
    required this.accent,
    required this.text,
    required this.border,
    required this.dirtyFileCount,
  });

  /// Real commit log — newest first, as `listCommitHistory` returns.
  final List<CommitHistoryEntry> commits;

  /// Pulse phase 0..1. Only meaningful when [animating] is true;
  /// when false the painter ignores it and draws the static halo.
  final double phase;

  /// True when the HEAD halo should pulse — set by the state when
  /// the working tree is dirty or HEAD is fresh. False = halo
  /// renders at a stable mid-radius; no animation.
  final bool animating;

  final Color accent;
  final Color text;
  final Color border;

  /// Working-tree dirtiness — drives the warm tint on HEAD's halo.
  /// Maps file count → 0..1 intensity, capped at 12 files.
  final int dirtyFileCount;

  static const double _padX = 10;
  // Vertical pad — leaves enough room for the HEAD halo (max
  // ~11 px) AND for the lane-jitter to spread vertically without
  // clipping. Tightening this beyond ~10 collapses linear-history
  // repos to a flat band; loosening past ~14 leaves the stars
  // marooned in empty parchment.
  static const double _padY = 10;

  /// FNV-1a 32 over a string. Stable across launches; used for
  /// per-commit y-jitter so single-author / linear repos still get
  /// vertical spread instead of collapsing to a line.
  int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final cu in s.codeUnits) {
      h ^= cu;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// Topological lane assignment — the same idea `git log --graph`
  /// uses. Walking newest-to-oldest, each commit takes a lane:
  /// - if a previously-seen child claimed a lane "waiting for" this
  ///   parent, the parent inherits it (DAG continuation)
  /// - otherwise it opens a fresh lane (branch divergence in display
  ///   space, even if linear in commit history)
  /// First parent wins the inherited lane on a merge; the second
  /// parent of a merge spawns its own lane (so merges visibly
  /// converge two tracks into one).
  Map<String, int> _assignLanes() {
    final lanes = <String, int>{};
    // For each commit, the lane index it was placed into.
    // `waiting` maps "I am a parent expected by this lane" → lane idx.
    final waiting = <String, int>{};
    final reusable = <int>[]; // lanes whose last consumer used them
    var nextLane = 0;
    for (final c in commits) {
      int lane;
      if (waiting.containsKey(c.commitHash)) {
        lane = waiting.remove(c.commitHash)!;
      } else if (reusable.isNotEmpty) {
        // Recycle a lane vacated by an earlier merge — keeps the
        // canvas dense rather than ever-growing.
        lane = reusable.removeAt(0);
      } else {
        lane = nextLane++;
      }
      lanes[c.commitHash] = lane;
      // Reserve the lane for this commit's first parent (DAG
      // continuation). Later parents — i.e., merges — open new lanes.
      for (var pi = 0; pi < c.parentHashes.length; pi++) {
        final ph = c.parentHashes[pi];
        if (pi == 0) {
          waiting[ph] = lane;
        } else {
          // Merge side parent — give it a fresh lane and remember
          // the original lane is free once this commit is past.
          if (!waiting.containsKey(ph)) {
            waiting[ph] = nextLane++;
          }
        }
      }
    }
    return lanes;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = commits.length;
    if (n == 0) return;
    final usableW = size.width - 2 * _padX;
    final usableH = size.height - 2 * _padY;

    // Real DAG-derived lanes. Single-lane repos (linear history,
    // solo author) still get spread via per-commit hash jitter so
    // the canvas isn't a single horizontal line.
    final lanes = _assignLanes();
    final laneCount = (lanes.values.isEmpty
            ? 1
            : (lanes.values.reduce((a, b) => a > b ? a : b) + 1))
        .clamp(1, 8);

    // Project each commit. x = recency (commits[0] newest → right);
    // y = lane index normalised to canvas height, plus a small
    // hash-derived jitter so densely-shared lanes don't overlap.
    final positions = <String, Offset>{};
    for (var i = 0; i < n; i++) {
      final c = commits[i];
      final fx = n == 1 ? 1.0 : 1.0 - (i / (n - 1));
      final lane = lanes[c.commitHash] ?? 0;
      final laneFy = laneCount == 1 ? 0.5 : lane / (laneCount - 1);
      // ±0.18 of usableH band per lane, so commits in the same lane
      // separate vertically by their hash but never bleed into the
      // adjacent lane's band.
      final jitter =
          ((_fnv1a(c.commitHash) & 0xffff) / 0xffff - 0.5) * 0.36;
      final laneBand = laneCount == 1 ? 1.0 : 1.0 / laneCount;
      final fy = (laneFy + jitter * laneBand).clamp(0.05, 0.95);
      positions[c.commitHash] = Offset(
        _padX + fx * usableW,
        _padY + fy * usableH,
      );
    }

    // Real DAG edges — parent → child. Skip parents that fell off
    // the loaded window (we only fetched 96 commits; older parents
    // simply aren't drawn rather than faked in).
    final edgePaint = Paint()
      ..color = text.withValues(alpha: 0.35)
      ..strokeWidth = 0.7;
    for (final c in commits) {
      final childPos = positions[c.commitHash];
      if (childPos == null) continue;
      for (final ph in c.parentHashes) {
        final parentPos = positions[ph];
        if (parentPos == null) continue;
        canvas.drawLine(parentPos, childPos, edgePaint);
      }
    }

    // Stars. Each author gets a deterministic hue rotation around
    // the theme accent; recency drives alpha; today's commits get
    // an extra small glow; HEAD is the pulsing "you are here";
    // dirty working tree adds a warm tint to HEAD's halo.
    final accentHsv = HSVColor.fromColor(accent);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const dayMs = 24 * 60 * 60 * 1000;
    for (var i = 0; i < n; i++) {
      final c = commits[i];
      final pos = positions[c.commitHash];
      if (pos == null) continue;
      final isHead = i == 0;
      final isTip = c.refNames.isNotEmpty;
      final tFade = n == 1 ? 1.0 : 1.0 - (i / (n - 1));
      final baseAlpha = 0.32 + 0.58 * tFade;

      // Per-author hue — rotate ±30° around the theme accent. Same
      // author = same colour across launches; visually distinct
      // contributors without ever leaving the palette family.
      final authorKey = (c.authorEmail.isNotEmpty
              ? c.authorEmail
              : c.authorName)
          .toLowerCase();
      final shift = ((_fnv1a(authorKey) & 0xff) / 255.0 - 0.5) * 60.0;
      final hue = (accentHsv.hue + shift) % 360;
      final starHsv = accentHsv.withHue(hue < 0 ? hue + 360 : hue);
      // Saturation droops with age so old commits look like ash.
      final sat = (starHsv.saturation * (0.45 + 0.55 * tFade)).clamp(0.0, 1.0);
      final val = (starHsv.value * (0.55 + 0.45 * tFade)).clamp(0.0, 1.0);
      final starColor = isHead
          ? accent
          : starHsv.withSaturation(sat).withValue(val).toColor()
              .withValues(alpha: baseAlpha);

      // Today's commits — subtle outer halo so recent activity
      // visibly glows even before HEAD.
      final ageMs = _parseAuthoredAt(c.authoredAt);
      if (!isHead && ageMs != null && nowMs - ageMs < dayMs) {
        final freshness =
            1.0 - ((nowMs - ageMs) / dayMs).clamp(0.0, 1.0);
        canvas.drawCircle(
          pos,
          (isTip ? 2.8 : 2.0) + 3 * freshness,
          Paint()
            ..color = starHsv
                .withSaturation(sat)
                .withValue(val)
                .toColor()
                .withValues(alpha: 0.18 * freshness)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
        );
      }

      final radius = isHead ? 3.2 : (isTip ? 2.6 : 1.8);
      if (isHead) {
        // Halo radius: animated only when there's a real reason
        // (dirty tree or fresh commit). Otherwise static at the
        // midpoint — same visual weight, no breathing.
        final pulseT = animating ? (1 - (phase * 2 - 1).abs()) : 0.5;
        final pulseR = 7 + 4 * pulseT;
        final fillAlpha = animating
            ? (0.10 + 0.12 * (1 - phase))
            : 0.16;
        // Dirty working tree warms the HEAD halo. 0 files = pure
        // accent; >=12 files = full warmth (rotate hue 30° toward
        // amber/orange).
        final dirtyT =
            (dirtyFileCount / 12).clamp(0.0, 1.0).toDouble();
        final haloHue = (accentHsv.hue + 30 * dirtyT) % 360;
        final haloColor =
            accentHsv.withHue(haloHue < 0 ? haloHue + 360 : haloHue).toColor();
        canvas.drawCircle(
          pos,
          pulseR,
          Paint()
            ..color = haloColor.withValues(alpha: fillAlpha)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          pos,
          pulseR,
          Paint()
            ..color = haloColor.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      canvas.drawCircle(pos, radius, Paint()..color = starColor);
      if (c.isMerge) {
        canvas.drawCircle(
          pos,
          radius + 1.6,
          Paint()
            ..color = starColor.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }

  }

  /// Parses git's ISO-8601-ish timestamps. Returns epoch ms or null
  /// on any parse hiccup — the today-glow falls back to "no glow"
  /// rather than guessing.
  int? _parseAuthoredAt(String s) {
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s).millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  @override
  bool shouldRepaint(_RepoConstellationPainter old) =>
      // Only repaint on phase delta when actually animating; otherwise
      // a non-animating painter shouldn't churn frames.
      (animating && old.phase != phase) ||
      old.animating != animating ||
      !identical(old.commits, commits) ||
      old.dirtyFileCount != dirtyFileCount;
}

// ═════════════════════════════════════════════════════════════════════════
// Discovery wordmark — shown in the pen before the user's first dock
// click. A slow opacity breath (0.65 ↔ 1.0 over ~2.6s) invites the
// click without adding UI chrome or tooltip copy. Once the user
// interacts, this widget is never mounted again for that install.

class _DiscoveryWordmark extends StatefulWidget {
  const _DiscoveryWordmark({required this.color});
  final Color color;

  @override
  State<_DiscoveryWordmark> createState() => _DiscoveryWordmarkState();
}

class _DiscoveryWordmarkState extends State<_DiscoveryWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        // Eased triangle: dwell at low end slightly longer than the
        // high end so the word reads as "inhaling attention."
        final p = _pulse.value;
        final eased = Curves.easeInOutSine.transform(p);
        final alpha = 0.65 + 0.35 * eased;
        return Text(
          'bond',
          style: TextStyle(
            color: widget.color.withValues(alpha: alpha),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Error glyph vocabulary — manga-style particle pops above a ghost
// button when its errorToken changes. Each kind is a small vector
// glyph that matches the wireframe-fox stroke aesthetic. No text.

/// Classifies an arbitrary error into one of the three [_BondErrKind]
/// glyph vocabularies at the catch site — this is the only place in
/// the app where an error's text form is inspected. After this point
/// the UI carries only the symbolic kind, not the string.
_BondErrKind _classifyErr(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('socket') ||
      s.contains('timeout') ||
      s.contains('network') ||
      s.contains('connection') ||
      s.contains('dns') ||
      s.contains('unreachable')) {
    return _BondErrKind.offline;
  }
  if (s.contains('exists') ||
      s.contains('taken') ||
      s.contains('conflict') ||
      s.contains('already') ||
      s.contains('in use')) {
    return _BondErrKind.busy;
  }
  return _BondErrKind.fail;
}

enum _BondErrKind {
  /// Rejected input (wrong passphrase, bad credential) — drawn as
  /// a struck-through cross. Snappy entry, slight settle.
  fail,

  /// Network / connection failure — drawn as three dots drifting
  /// apart on the horizontal. Communicates "something far away."
  offline,

  /// Already-taken / conflict — drawn as a double-bang glyph ‼.
  /// Communicates "tried something that's already spoken for."
  busy,
}

class _ErrorGlyph extends StatelessWidget {
  const _ErrorGlyph({
    required this.kind,
    required this.progress,
    required this.color,
  });

  final _BondErrKind kind;
  /// 0..1 animation progress (same controller as the button shake).
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        size: const Size(18, 14),
        painter: _ErrorGlyphPainter(
          kind: kind,
          progress: progress,
          color: color,
        ),
      ),
    );
  }
}

class _ErrorGlyphPainter extends CustomPainter {
  _ErrorGlyphPainter({
    required this.kind,
    required this.progress,
    required this.color,
  });
  final _BondErrKind kind;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Common particle lifecycle — rise ~4px and fade out over the
    // second half of the animation. The ascent is eased-out so the
    // glyph pops up fast and lingers.
    final rise = Curves.easeOutCubic.transform(progress) * 4.0;
    final alpha = progress < 0.15
        ? (progress / 0.15)
        : math.max(0.0, 1.0 - (progress - 0.4) / 0.55);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
    final cx = size.width / 2;
    final cy = size.height / 2 - rise;

    switch (kind) {
      case _BondErrKind.fail:
        // Cross "×" — two diagonal strokes. Snappy read = rejected.
        const r = 4.0;
        canvas.drawLine(
          Offset(cx - r, cy - r),
          Offset(cx + r, cy + r),
          paint,
        );
        canvas.drawLine(
          Offset(cx + r, cy - r),
          Offset(cx - r, cy + r),
          paint,
        );
        break;

      case _BondErrKind.offline:
        // Three dots drifting apart. Spread scales with progress
        // so the reading is: ". . ." → "...    ...    ..." — it
        // *goes* far away, matching the concept.
        final spread = 3.0 + 4.0 * progress;
        for (var i = -1; i <= 1; i++) {
          canvas.drawCircle(
            Offset(cx + i * spread, cy),
            1.3,
            Paint()
              ..color =
                  color.withValues(alpha: alpha.clamp(0.0, 1.0)),
          );
        }
        break;

      case _BondErrKind.busy:
        // Double-bang "‼" — two short verticals + two dots below.
        // Reads as "already! already!" (conflict).
        const bars = 3.0;
        const gap = 2.8;
        canvas.drawLine(
          Offset(cx - gap / 2, cy - bars),
          Offset(cx - gap / 2, cy + bars * 0.3),
          paint,
        );
        canvas.drawLine(
          Offset(cx + gap / 2, cy - bars),
          Offset(cx + gap / 2, cy + bars * 0.3),
          paint,
        );
        final dotPaint = Paint()
          ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
        canvas.drawCircle(Offset(cx - gap / 2, cy + bars), 1.1, dotPaint);
        canvas.drawCircle(Offset(cx + gap / 2, cy + bars), 1.1, dotPaint);
        break;
    }
  }

  @override
  bool shouldRepaint(_ErrorGlyphPainter old) =>
      old.progress != progress ||
      old.kind != kind ||
      old.color != color;
}

// ═════════════════════════════════════════════════════════════════════════
// Atoms — section label, hairline, ghost input/button/check, murmur

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: t.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(height: 1, color: context.tokens.chromeBorderFaint),
    );
  }
}

class _Murmur extends StatelessWidget {
  const _Murmur(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(color: t.textMuted, fontSize: 11, height: 1.45),
      ),
    );
  }
}

class _GhostInput extends StatelessWidget {
  const _GhostInput({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.enabled = true,
    this.mono = false,
    this.minLines,
    this.maxLines = 1,
    this.onSubmit,
  });
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool enabled;
  final bool mono;
  final int? minLines;
  final int? maxLines;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.chromeBorderSubtle, width: 1),
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        enabled: enabled,
        minLines: minLines,
        maxLines: obscure ? 1 : maxLines,
        onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
        style: TextStyle(
          color: t.textNormal,
          fontSize: 12,
          fontFamily: mono ? 'JetBrainsMono' : null,
        ),
        cursorColor: t.accentBright,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(
            color: t.textMuted,
            fontSize: 12,
            fontFamily: mono ? 'JetBrainsMono' : null,
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  const _GhostButton({
    required this.label,
    required this.onTap,
    this.accent = false,
    this.danger = false,
    this.busy = false,
    this.errorToken,
    this.errorKind = _BondErrKind.fail,
  });
  /// Label text — stays stable across busy transitions. Do NOT
  /// swap this to '…' or a spinner character on busy; use the
  /// [busy] flag instead so the button's widget identity never
  /// changes shape. Changing the text causes visible pop-in.
  final String label;
  /// `null` disables taps (disabled look). Can coexist with [busy]
  /// but [busy] alone also internally disables taps.
  final VoidCallback? onTap;
  final bool accent;
  final bool danger;

  /// True while the action is in flight. Renders a subtle inline
  /// pulse next to the label and suppresses taps internally — the
  /// label itself stays put so the button doesn't visually jump.
  final bool busy;

  /// Opaque token — when it changes to a new non-null value the
  /// button plays a red-flash + shake animation AND pops an error
  /// glyph above it. Each distinct failure produces a distinct
  /// token and re-triggers the anim.
  final Object? errorToken;

  /// Which glyph to pop above the button when [errorToken] fires.
  /// See [_BondErrKind] — callers classify the error into a kind
  /// (wrong input / offline / conflict) at the catch site.
  final _BondErrKind errorKind;
  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton>
    with TickerProviderStateMixin {
  bool _hover = false;
  // Shake + flash controller. 420 ms total: horizontal damped
  // sinusoid kicked into a bounded translation + border colour
  // lerp toward stateDeleted. Stays off at rest (no leak cycles).
  late final AnimationController _errorCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  // Busy pulse controller. Repeats while [widget.busy] is true —
  // a slow heartbeat drives a faint inline dot next to the label.
  // Never changes the button's label text or size, so the widget
  // tree stays identical across busy transitions.
  late final AnimationController _busyCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _busyCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_GhostButton old) {
    super.didUpdateWidget(old);
    final tok = widget.errorToken;
    if (tok != null && tok != old.errorToken) {
      _errorCtrl.forward(from: 0);
    }
    if (widget.busy != old.busy) {
      if (widget.busy) {
        _busyCtrl.repeat(reverse: true);
      } else {
        _busyCtrl.stop();
        _busyCtrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _errorCtrl.dispose();
    _busyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final disabled = widget.onTap == null;
    final Color base = widget.danger
        ? t.stateDeleted
        : widget.accent
            ? t.accentBright
            : t.textNormal;
    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        // Busy internally suppresses taps (in addition to onTap being
        // null). Callers don't have to double-gate — passing busy:true
        // is enough.
        onPointerUp: (_) {
          if (!widget.busy) widget.onTap?.call();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_errorCtrl, _busyCtrl]),
          builder: (context, _) {
            // Damped sinusoid: 4 cycles over the animation, amplitude
            // decays linearly from 3 px to 0.
            final p = _errorCtrl.value;
            final shake = p > 0
                ? math.sin(p * math.pi * 8) * 3.0 * (1 - p)
                : 0.0;
            // Red flash: rises to peak near p=0.15 then ebbs. A quick
            // tap of colour, not a held state — the button is back to
            // normal by the time the user re-reads it.
            final flash = p > 0
                ? math.max(0.0, 1 - (p / 0.6)) *
                    math.min(1.0, p / 0.08)
                : 0.0;
            final borderColor = Color.lerp(
              _hover && !disabled ? base : t.chromeBorderSubtle,
              t.stateDeleted,
              flash,
            )!;
            final textColor = Color.lerp(
              disabled ? t.textMuted : base,
              t.stateDeleted,
              flash,
            )!;
            final bgColor = _hover && !disabled
                ? Color.lerp(
                    base.withValues(alpha: 0.10),
                    t.stateDeleted.withValues(alpha: 0.16),
                    flash,
                  )!
                : Color.lerp(
                    Colors.transparent,
                    t.stateDeleted.withValues(alpha: 0.10),
                    flash,
                  )!;
            // Busy indicator — eased triangle wave driving opacity of
            // a small dot rendered next to the label. Space for it is
            // *always* reserved (SizedBox width 10) so the button
            // width doesn't jump when busy toggles. Dot is invisible
            // at rest, pulses while busy.
            final busyPhase = Curves.easeInOutSine
                .transform(_busyCtrl.value);
            final dotAlpha = widget.busy ? (0.35 + 0.55 * busyPhase) : 0.0;
            final button = Transform.translate(
              offset: Offset(shake, 0),
              child: AnimatedContainer(
                duration:
                    context.motion(const Duration(milliseconds: 100)),
                // Horizontal padding tightened from 10 → 8. The
                // narrow-sidebar use-case (unlock row: 12h pill +
                // unlock button + 1px borders) was overflowing by
                // ~14px; trimming 2px per side per button closes
                // the gap without needing to wrap the row.
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    // Always reserve the slot; only the dot fades.
                    // Keeps button width stable between idle and busy.
                    // Gap + dot tightened (6+4 → 4+3) for the same
                    // overflow reason as above.
                    const SizedBox(width: 4),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: textColor.withValues(alpha: dotAlpha),
                      ),
                    ),
                  ],
                ),
              ),
            );
            // Error glyph pops above the button — rises ~4px, fades
            // in the first 15% then out across the remainder. The
            // Stack always includes both children (no collection-if)
            // so the children list length never changes; the glyph
            // widget itself renders an empty box when idle. This
            // keeps the widget tree identity stable across rebuilds.
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                button,
                Positioned(
                  top: -16,
                  child: _ErrorGlyph(
                    kind: widget.errorKind,
                    progress: p,
                    color: t.stateDeleted,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GhostMicroAction extends StatefulWidget {
  const _GhostMicroAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  State<_GhostMicroAction> createState() => _GhostMicroActionState();
}

class _GhostMicroActionState extends State<_GhostMicroAction> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => widget.onTap(),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _hover ? t.accentBright : t.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              decoration: _hover ? TextDecoration.underline : null,
              decorationColor: t.accentBright,
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostCheck extends StatelessWidget {
  const _GhostCheck({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => onChanged(!value),
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: value ? t.accentBright : Colors.transparent,
            border: Border.all(
              color: value ? t.accentBright : t.chromeBorderStrong,
              width: 1,
            ),
          ),
          child: value
              ? Icon(Icons.check, size: 10, color: t.chromeTone == AppMaterialTone.surface0
                  ? t.textNormal
                  : t.textNormal)
              : null,
        ),
      ),
    );
  }
}

class _GhostIconButton extends StatefulWidget {
  const _GhostIconButton({
    required this.icon,
    this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;
  @override
  State<_GhostIconButton> createState() => _GhostIconButtonState();
}

class _GhostIconButtonState extends State<_GhostIconButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final core = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => widget.onTap(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            widget.icon,
            size: 16,
            color: _hover ? t.textNormal : t.textMuted,
          ),
        ),
      ),
    );
    final tip = widget.tooltip;
    if (tip == null || tip.isEmpty) return core;
    return Tooltip(message: tip, child: core);
  }
}

// ═════════════════════════════════════════════════════════════════════════
// State dot + state resolver

class _StateDot extends StatelessWidget {
  const _StateDot({required this.state, this.small = false});
  final _DockState state;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = switch (state.dot) {
      _DotKind.live => t.accentBright,
      _DotKind.locked => t.textMuted,
      _DotKind.offline => t.chromeBorderStrong,
      _DotKind.idle => t.textMuted.withValues(alpha: 0.5),
    };
    final filled =
        state.dot == _DotKind.live || state.dot == _DotKind.offline;
    final size = small ? 6.0 : 8.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : null,
        border: filled ? null : Border.all(color: color, width: 1.2),
      ),
    );
  }
}

class _DockState {
  const _DockState(this.label, this.dot, {this.urgent = false});
  final String label;
  final _DotKind dot;
  final bool urgent;
}

enum _DotKind { idle, live, locked, offline }

_DockState _resolveState(
  BondService service,
  BondMembership? m,
  BondUiSnapshot? snap,
  bool online,
) {
  if (!online) return const _DockState('bond · offline', _DotKind.offline);
  if (m == null) return const _DockState('bond', _DotKind.idle);
  if (!service.isUnlocked) {
    return const _DockState('bond · locked', _DotKind.locked);
  }
  if (snap == null) return const _DockState('bond · waiting', _DotKind.idle);
  final live = snap.peers.where((p) => p.attached).length;
  final pending = snap.proposals.length;
  String s(int n) => n == 1 ? '' : 's';
  if (pending > 0) {
    final pp = pending == 1 ? '1 proposal' : '$pending proposals';
    return _DockState('$live peer${s(live)} · $pp',
        _DotKind.live, urgent: true);
  }
  if (live == 0 && snap.peers.isEmpty) {
    return const _DockState('bond · waiting', _DotKind.idle);
  }
  if (live == 0) {
    return _DockState(
      '${snap.peers.length} peer${s(snap.peers.length)} · offline',
      _DotKind.offline,
    );
  }
  return _DockState('$live peer${s(live)} · clean', _DotKind.live);
}

// ═════════════════════════════════════════════════════════════════════════

/// No-op listenable fallback for when there's no runtime to subscribe to.
class _IdleListenable implements Listenable {
  const _IdleListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

Uint8List _unhex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
