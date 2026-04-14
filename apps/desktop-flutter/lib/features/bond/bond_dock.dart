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

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/repository_state.dart';
import '../../backend/bond/bond_backend.dart';
import '../../backend/bond/objects.dart';
import '../../backend/bond/transport.dart';
import '../../backend/bond_service.dart';
import '../../ui/material_surface.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';

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
        onTap: () => setState(() => _mode = _DockMode.overview),
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
              Expanded(
                child: Text(
                  state.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: state.urgent ? t.accentBright : t.textNormal,
                    fontSize: 12,
                    fontWeight: state.urgent
                        ? FontWeight.w600
                        : FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_up,
                size: 16,
                color: _hover ? t.textNormal : t.textMuted,
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
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
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

class _DrawerHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = switch (mode) {
      _DockMode.start => 'start a bond',
      _DockMode.join => 'join a bond',
      _DockMode.compose => 'propose',
      _DockMode.policy => 'policy',
      _ => membership?.displayName ?? 'bond',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          if (onBack != null)
            _GhostIconButton(
              icon: Icons.arrow_back,
              tooltip: 'back',
              onTap: onBack!,
            )
          else
            _StateDot(state: _resolveState(
                Provider.of<BondService>(context, listen: false),
                membership, snapshot, online), small: true),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ),
          if (membership != null && mode != _DockMode.overview)
            _GhostIconButton(
              icon: Icons.close,
              tooltip: 'cancel',
              onTap: () {
                final state = context
                    .findAncestorStateOfType<_BondDockState>();
                state?.setState(() => state._mode = _DockMode.overview);
              },
            ),
          _GhostIconButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: 'collapse',
            onTap: onCollapse,
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
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'this repo isn’t bonded.',
          style: TextStyle(color: t.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 12),
        _CodexAction(label: 'Start a new bond', glyph: '+', onTap: onStart),
        const _Hairline(),
        _CodexAction(label: 'Join with an invite', glyph: '⌁', onTap: onJoin),
      ],
    );
  }
}

class _CodexAction extends StatefulWidget {
  const _CodexAction({
    required this.label,
    required this.glyph,
    required this.onTap,
  });
  final String label;
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
          duration: context.motion(const Duration(milliseconds: 120)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          color: _hover ? t.chromeBorderFaint : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  widget.glyph,
                  style: TextStyle(
                    color: _hover ? t.accentBright : t.textMuted,
                    fontSize: 14,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: t.textNormal,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: _hover ? t.textNormal : t.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Identity unlock — inline phrase + checkbox

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
  String? _err;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await context.read<BondService>().unlock(
            _phrase.text,
            persistToKeychain: _persist,
          );
      _phrase.clear();
    } catch (e) {
      setState(() => _err = '$e');
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
        Text(
          'enter your phrase to derive your bond identity. it never leaves this device.',
          style: TextStyle(color: t.textMuted, fontSize: 11, height: 1.45),
        ),
        const SizedBox(height: 14),
        _GhostInput(
          controller: _phrase,
          obscure: true,
          hint: 'identity phrase',
          enabled: !_busy,
          onSubmit: _unlock,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _GhostCheck(
              value: _persist,
              onChanged: (v) => setState(() => _persist = v),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _persist = !_persist),
                child: Text(
                  'stay unlocked 12h',
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                ),
              ),
            ),
            _GhostButton(
              label: _busy ? '…' : 'unlock',
              onTap: _busy ? null : _unlock,
              accent: true,
            ),
          ],
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          _ErrorMurmur(_err!),
        ],
      ],
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
  String? _err;

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
      _err = null;
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
      setState(() => _err = '$e');
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
        Text(
          'pick a commit every peer already has — usually the root. paired with the swarm phrase, that derives the bond id.',
          style: TextStyle(color: t.textMuted, fontSize: 11, height: 1.45),
        ),
        const SizedBox(height: 12),
        _GhostInput(controller: _name, hint: 'local label', enabled: !_busy),
        const SizedBox(height: 8),
        _GhostInput(
          controller: _bootstrap,
          hint: 'bootstrap commit hash',
          enabled: !_busy,
          mono: true,
        ),
        const SizedBox(height: 8),
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
              label: _busy ? '…' : 'create',
              onTap: _busy ? null : _bind,
              accent: true,
            ),
          ],
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          _ErrorMurmur(_err!),
        ],
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
  String? _err;

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
      _err = null;
    });
    try {
      await context.read<BondService>().bindFromInvite(
            repoPath: widget.repoPath,
            inviteBlob: _invite.text,
            swarmPhrase: _swarm.text,
          );
      widget.onDone();
    } catch (e) {
      setState(() => _err = '$e');
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
        Text(
          'paste the bond1: invite your teammate sent. the swarm phrase comes separately — that\'s deliberate.',
          style: TextStyle(color: t.textMuted, fontSize: 11, height: 1.45),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 8),
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
              label: _busy ? '…' : 'join',
              onTap: _busy ? null : _join,
              accent: true,
            ),
          ],
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          _ErrorMurmur(_err!),
        ],
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
        if (snapshot != null && peers.any((p) => p.coordinate != null))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LatticeGlyph(snapshot: snapshot!),
          ),
        // Section: peers
        _SectionLabel('peers · ${peers.length}'),
        if (peers.isEmpty)
          const _Murmur('no peers yet — share the invite.')
        else
          for (final p in peers) _PeerLine(repoPath: repoPath, peer: p),
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
            _ProposalLine(repoPath: repoPath, proposal: pr),
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
  const _PeerLine({required this.repoPath, required this.peer});
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
  const _ProposalLine({required this.repoPath, required this.proposal});
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
  String? _err;

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
      setState(() => _err = 'no HEAD detected.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
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
        setState(() => _err = r.error);
      } else {
        widget.onDone();
      }
    } catch (e) {
      setState(() => _err = '$e');
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
              label: _busy ? '…' : 'publish',
              onTap: _busy ? null : _publish,
              accent: true,
            ),
          ],
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          _ErrorMurmur(_err!),
        ],
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
  String? _err;

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
      setState(() => _err = 'invalid rule.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final err = await context.read<BondService>().publishPolicy(
        repoPath: widget.repoPath,
        rules: [
          PolicyRule(refPattern: _ref.text.trim(), minApprovals: n),
        ],
      );
      if (err != null) {
        setState(() => _err = err);
      } else {
        widget.onDone();
      }
    } catch (e) {
      setState(() => _err = '$e');
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
        Text(
          'gate one ref pattern by N approvals from any non-revoked signer.',
          style: TextStyle(color: t.textMuted, fontSize: 11, height: 1.45),
        ),
        const SizedBox(height: 12),
        _GhostInput(
          controller: _ref,
          hint: 'ref pattern',
          mono: true,
          enabled: !_busy,
        ),
        const SizedBox(height: 8),
        _GhostInput(
          controller: _min,
          hint: 'min approvals',
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _GhostButton(
              label: _busy ? '…' : 'publish',
              onTap: _busy ? null : _publish,
              accent: true,
            ),
          ],
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          _ErrorMurmur(_err!),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Lattice braille glyph

class _LatticeGlyph extends StatelessWidget {
  const _LatticeGlyph({required this.snapshot});
  final BondUiSnapshot snapshot;
  static const int _rows = 3;
  static const int _cols = 12;
  static const int _dotsX = _cols * 2;
  static const int _dotsY = _rows * 4;

  String _layer(bool attachedOnly) {
    final grid = List.generate(_rows, (_) => List<int>.filled(_cols, 0));
    for (final p in snapshot.peers) {
      final c = p.coordinate;
      if (c == null) continue;
      if (attachedOnly && !p.attached) continue;
      final dx = (c.value >> 8) * (_dotsX - 1) ~/ 255;
      final dy = (c.value & 0xFF) * (_dotsY - 1) ~/ 255;
      final cx = dx ~/ 2;
      final cy = dy ~/ 4;
      grid[cy][cx] |= _bit(dx % 2, dy % 4);
    }
    return grid
        .map((row) =>
            row.map((b) => String.fromCharCode(0x2800 + b)).join())
        .join('\n');
  }

  static int _bit(int x, int y) {
    const m = [
      [0x01, 0x02, 0x04, 0x40],
      [0x08, 0x10, 0x20, 0x80],
    ];
    return m[x][y];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Text(_layer(false),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textMuted.withValues(alpha: 0.32),
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.05,
              )),
          Text(_layer(true),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.accentBright,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.05,
              )),
        ],
      ),
    );
  }
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

class _ErrorMurmur extends StatelessWidget {
  const _ErrorMurmur(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: TextStyle(color: t.stateDeleted, fontSize: 11),
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
  });
  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final bool danger;
  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hover = false;
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
        onPointerUp: (_) => widget.onTap?.call(),
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 100)),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hover && !disabled
                ? base.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(
              color: _hover && !disabled
                  ? base
                  : t.chromeBorderSubtle,
              width: 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: disabled ? t.textMuted : base,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
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
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  State<_GhostIconButton> createState() => _GhostIconButtonState();
}

class _GhostIconButtonState extends State<_GhostIconButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
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
      ),
    );
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
