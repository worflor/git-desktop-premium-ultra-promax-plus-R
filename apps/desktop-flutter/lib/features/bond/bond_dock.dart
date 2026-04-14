// ═════════════════════════════════════════════════════════════════════════
// features/bond/bond_dock.dart — bottom-of-sidebar Bond surface
//
// Three nested states sharing the same fixed bottom slot of the sidebar
// rail. All state transitions animate inside that slot — the projects
// list above stays put.
//
//   State A (strip)     — one row, ambient. Always present when the
//                         feature flag is on. Shows "bond · <verb>".
//   State B (lattice)   — strip + braille mini-map of peer coordinates.
//                         Appears automatically the first time a peer
//                         is placed on the bond's lattice.
//   State C (drawer)    — strip + lattice + scrollable peer roster +
//                         pending-proposals affordance + "open full →"
//                         that pushes the full BondPage as a route.
//
// Every colour, surface, font, and motion duration reads from
// `context.tokens` / `context.surfaceShader`. No `Colors.x` literals,
// no raw `Duration(...)` — themes assert their own cadence and the
// dock follows.
// ═════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/repository_state.dart';
import '../../backend/bond/bond_backend.dart';
import '../../backend/bond_service.dart';
import '../../ui/material_surface.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import 'bond_page.dart';

/// The bottom-of-sidebar Bond surface. Drop into the sidebar rail
/// below the projects list; renders nothing when the feature flag is
/// off so the rail looks identical to the no-bond state.
class BondDock extends StatefulWidget {
  const BondDock({super.key});

  @override
  State<BondDock> createState() => _BondDockState();
}

class _BondDockState extends State<BondDock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    // The bond worktree always shows the dock — it's the *point* of
    // the worktree. On main, the experiment flag still gates whether
    // the workspace_shell topbar exposes the deeper panel.
    final repoPath = context.watch<RepositoryState>().activePath;
    final service = context.watch<BondService>();
    final membership = repoPath == null
        ? null
        : service.membershipFor(repoPath);

    // Listenable for backend state — nullable when no membership
    // resolved yet (no runtime, no listenable). Use a null-listenable
    // fallback so ListenableBuilder is unconditional.
    final listenable = repoPath != null && membership != null
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
        final hasPlacedPeers = snap != null &&
            snap.peers.any((p) => p.coordinate != null);
        final showLattice = membership != null && hasPlacedPeers;

        return _DockSurface(
          child: AnimatedSize(
            duration: context.motion(const Duration(milliseconds: 220)),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_open && membership != null)
                  _DockDrawer(
                    repoPath: repoPath!,
                    membership: membership,
                    snapshot: snap,
                  ),
                if (!_open && showLattice && snap != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: _LatticeGlyph(snapshot: snap),
                  ),
                _DockStrip(
                  service: service,
                  membership: membership,
                  snapshot: snap,
                  open: _open,
                  online: online,
                  onTap: membership == null
                      ? () => _openFullPage(context, repoPath)
                      : () => setState(() => _open = !_open),
                ),
              ],
            ),
          ),
        );
        },
      ),
    );
  }

  void _openFullPage(BuildContext context, String? repoPath) {
    if (repoPath == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BondPage(repoPath: repoPath),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Surface chrome — the rectangle the dock lives inside

class _DockSurface extends StatelessWidget {
  const _DockSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // A hairline divider above the dock distinguishes it from the
    // project list without forcing a visible card edge — the dock
    // *is* the bottom of the sidebar, not pasted on top of it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Subtle (not faint) divider — the dock IS the bottom of the
        // sidebar; the line tells the eye where the projects list
        // ends and bond chrome begins.
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: t.chromeBorderSubtle,
        ),
        child,
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Strip — always-visible single row at the very bottom

class _DockStrip extends StatelessWidget {
  const _DockStrip({
    required this.service,
    required this.membership,
    required this.snapshot,
    required this.open,
    required this.online,
    required this.onTap,
  });

  final BondService service;
  final BondMembership? membership;
  final BondUiSnapshot? snapshot;
  final bool open;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = _resolveState(service, membership, snapshot);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // Slightly taller than its raw children so the strip reads
          // as a deliberate footer rather than collapsed chrome.
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Row(
            children: [
              _StateDot(state: state),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // Use the normal text colour for non-urgent
                    // states so the strip is legible against the
                    // sidebar's parchment surface — the prior muted
                    // tone was almost the same value as the
                    // background.
                    color: state.urgent ? t.accentBright : t.textNormal,
                    fontSize: 12,
                    fontWeight: state.urgent
                        ? FontWeight.w600
                        : FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (membership != null)
                Icon(
                  open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  size: 16,
                  color: t.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  _DockState _resolveState(
    BondService service,
    BondMembership? m,
    BondUiSnapshot? snap,
  ) {
    if (!online) return const _DockState('bond · offline', _DotKind.offline);
    if (m == null) return const _DockState('bond', _DotKind.idle);
    if (!service.isUnlocked) {
      return const _DockState('bond · locked', _DotKind.locked);
    }
    if (snap == null) return const _DockState('bond · waiting', _DotKind.idle);
    final live = snap.peers.where((p) => p.attached).length;
    final pending = snap.proposals.length;
    if (pending > 0) {
      final pp = pending == 1 ? '1 proposal' : '$pending proposals';
      return _DockState('$live peer${_plural(live)} · $pp',
          _DotKind.live, urgent: true);
    }
    if (live == 0 && snap.peers.isEmpty) {
      return const _DockState('bond · waiting', _DotKind.idle);
    }
    if (live == 0) {
      return _DockState(
        '${snap.peers.length} peer${_plural(snap.peers.length)} · offline',
        _DotKind.offline,
      );
    }
    return _DockState('$live peer${_plural(live)} · clean', _DotKind.live);
  }

  String _plural(int n) => n == 1 ? '' : 's';
}

class _DockState {
  const _DockState(this.label, this.dot, {this.urgent = false});
  final String label;
  final _DotKind dot;
  final bool urgent;
}

enum _DotKind { idle, live, locked, offline }

class _StateDot extends StatelessWidget {
  const _StateDot({required this.state});
  final _DockState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = switch (state.dot) {
      _DotKind.live => t.accentBright,
      _DotKind.locked => t.textMuted,
      _DotKind.offline => t.chromeBorderStrong,
      _DotKind.idle => t.textMuted.withValues(alpha: 0.4),
    };
    final filled = state.dot == _DotKind.live || state.dot == _DotKind.offline;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : null,
        border: filled ? null : Border.all(color: color, width: 1.2),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Lattice mini-map — braille glyph of placed peer coordinates

class _LatticeGlyph extends StatelessWidget {
  const _LatticeGlyph({required this.snapshot});
  final BondUiSnapshot snapshot;

  static const int _rows = 3;
  static const int _cols = 10;
  static const int _dotsX = _cols * 2; // braille = 2 dot cols per char
  static const int _dotsY = _rows * 4; // braille = 4 dot rows per char

  /// Renders the placed-peer grid as a multi-line braille string.
  /// Pass `attachedOnly=true` to get the live-peer overlay; pass false
  /// for the dimmer "everyone we've ever seen here" base layer.
  String _renderLayer(bool attachedOnly) {
    final grid = List.generate(_rows, (_) => List<int>.filled(_cols, 0));
    for (final p in snapshot.peers) {
      final coord = p.coordinate;
      if (coord == null) continue;
      if (attachedOnly && !p.attached) continue;
      // 8D⊗8D factorisation: high byte = row of the lattice, low
      // byte = column. Scale each axis into the braille dot grid so
      // a coordinate's neighbourhood in the lattice maps to a
      // neighbourhood on the glyph — same peers always land in the
      // same dot, different peers spread out coherently.
      final dx = (coord.value >> 8) * (_dotsX - 1) ~/ 255;
      final dy = (coord.value & 0xFF) * (_dotsY - 1) ~/ 255;
      final cx = dx ~/ 2;
      final cy = dy ~/ 4;
      grid[cy][cx] |= _brailleBit(dx % 2, dy % 4);
    }
    return grid
        .map((row) =>
            row.map((bits) => String.fromCharCode(0x2800 + bits)).join())
        .join('\n');
  }

  /// Braille dot bit positions per Unicode U+2800 layout:
  ///   col 0: 0x01, 0x02, 0x04, 0x40
  ///   col 1: 0x08, 0x10, 0x20, 0x80
  static int _brailleBit(int x, int y) {
    const map = [
      [0x01, 0x02, 0x04, 0x40],
      [0x08, 0x10, 0x20, 0x80],
    ];
    return map[x][y];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final base = _renderLayer(false);
    final live = _renderLayer(true);
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Text(
            base,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.35),
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.05,
              letterSpacing: 0,
            ),
          ),
          Text(
            live,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.accentBright,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.05,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Drawer — expanded peer roster + proposals shortcut + open-full link

class _DockDrawer extends StatelessWidget {
  const _DockDrawer({
    required this.repoPath,
    required this.membership,
    required this.snapshot,
  });

  final String repoPath;
  final BondMembership membership;
  final BondUiSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final peers = snapshot?.peers ?? const <BondPeerView>[];
    final pending = snapshot?.proposals.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: MaterialSurface(
        tone: AppMaterialTone.panel,
        radius: 6,
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  membership.displayName,
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  membership.bondId.shortHex,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (snapshot != null)
              _LatticeGlyph(snapshot: snapshot!),
            const SizedBox(height: 6),
            if (peers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'no peers yet — share an invite',
                  style: TextStyle(color: t.textMuted, fontSize: 10),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: peers.length,
                  itemBuilder: (context, i) => _PeerRow(peer: peers[i]),
                ),
              ),
            if (pending > 0) ...[
              const SizedBox(height: 6),
              _DrawerLink(
                label:
                    '$pending pending proposal${pending == 1 ? "" : "s"} →',
                accent: true,
                onTap: () => _openFull(context),
              ),
            ],
            const SizedBox(height: 4),
            _DrawerLink(
              label: 'open full →',
              accent: false,
              onTap: () => _openFull(context),
            ),
          ],
        ),
      ),
    );
  }

  void _openFull(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BondPage(repoPath: repoPath),
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.peer});
  final BondPeerView peer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dotColor = peer.isRevoked
        ? t.stateDeleted
        : peer.attached
            ? t.accentBright
            : t.chromeBorderStrong;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              peer.shortHex,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: peer.isRevoked
                    ? t.textMuted
                    : t.textNormal,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
                decoration: peer.isRevoked
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
          if (peer.coordinate != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                peer.coordinate!.toHex(),
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 9,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DrawerLink extends StatelessWidget {
  const _DrawerLink({
    required this.label,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: Text(
            label,
            style: TextStyle(
              color: accent ? t.accentBright : t.textMuted,
              fontSize: 10,
              fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Helpers

/// No-op [Listenable] fallback — keeps [ListenableBuilder] happy when
/// the dock has no runtime to subscribe to (no membership for the
/// active repo, or no active repo at all).
class _IdleListenable implements Listenable {
  const _IdleListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
