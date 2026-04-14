// ═════════════════════════════════════════════════════════════════════════
// features/bond/bond_page.dart — the Bond control surface
//
// Layered, progressive-disclosure UI for the peer-to-peer collaboration
// feature. The cards surface *only* what the user can act on at each
// step: locked users see Unlock; unlocked unbonded users see a
// Start/Join fork; bonded users see peers + invite + leave.
//
// Transport readiness is surfaced as a persistent banner at the top —
// the protocol layer can be perfectly healthy while the network layer
// isn't wired; users should not be left guessing.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../backend/bond/bond_backend.dart';
import '../../backend/bond/bond_id.dart';
import '../../backend/bond/invite.dart';
import '../../backend/bond/objects.dart';
import '../../backend/bond/transport.dart';
import '../../backend/bond_service.dart';
import '../../ui/material_surface.dart';
import '../../ui/tokens.dart';

class BondPage extends StatefulWidget {
  const BondPage({super.key, required this.repoPath});

  final String repoPath;

  @override
  State<BondPage> createState() => _BondPageState();
}

class _BondPageState extends State<BondPage> {
  final TextEditingController _phrase = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final service = context.read<BondService>();
    Future.microtask(() => service.loadFromDisk(widget.repoPath));
  }

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _onUnlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<BondService>().unlock(_phrase.text);
      _phrase.clear();
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmLeave(BondMembership m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this bond?'),
        content: Text(
          'Wipes local bond state for "${m.displayName}" — peers, refs, '
          'policies, cached adverts. Your identity key and other bonds '
          "aren't touched.\n\n"
          'If you want remote peers to stop trusting this device, '
          'publish a self-revocation first (Peers card ▸ Revoke self).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await context.read<BondService>().unbind(widget.repoPath);
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BondService>();
    final membership = service.membershipFor(widget.repoPath);
    final transportReady = service.transport is! NullBondTransport;

    return Scaffold(
      appBar: AppBar(title: const Text('Bond')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                if (!transportReady) const _TransportBanner(),
                const SizedBox(height: 12),
                _IdentityCard(
                  isUnlocked: service.isUnlocked,
                  phrase: _phrase,
                  onUnlock: _onUnlock,
                  onLock: service.lock,
                ),
                const SizedBox(height: 16),
                if (service.isUnlocked && membership == null)
                  _StartOrJoinCard(repoPath: widget.repoPath),
                if (membership != null)
                  _BondedCard(
                    repoPath: widget.repoPath,
                    membership: membership,
                    onLeave: () => _confirmLeave(membership),
                  ),
                if (membership != null) ...[
                  const SizedBox(height: 16),
                  _ProposalsCard(repoPath: widget.repoPath),
                  const SizedBox(height: 16),
                  _PeersCard(repoPath: widget.repoPath, membership: membership),
                  const SizedBox(height: 16),
                  _PolicyCard(repoPath: widget.repoPath),
                  const SizedBox(height: 16),
                  _DiagnosticsCard(repoPath: widget.repoPath),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorStrip(message: _error!),
                ],
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════

class _TransportBanner extends StatelessWidget {
  const _TransportBanner();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.tertiary.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Network transport not wired. You can set up bonds locally, '
              'but peers cannot actually reach each other until the '
              'Whisper transport ships.',
              style: TextStyle(color: c.onTertiaryContainer),
            ),
          ),
        ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.isUnlocked,
    required this.phrase,
    required this.onUnlock,
    required this.onLock,
  });

  final bool isUnlocked;
  final TextEditingController phrase;
  final Future<void> Function() onUnlock;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUnlocked ? Icons.lock_open : Icons.lock_outline,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Your identity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isUnlocked
                  ? 'Unlocked. The same phrase on any device re-derives this identity — no cloud account, no recovery email.'
                  : 'Enter your identity phrase. The phrase never leaves this device; we derive a keypair from it on the fly.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (!isUnlocked) ...[
              TextField(
                controller: phrase,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Identity phrase',
                  helperText:
                      'Personal. Memorable. Don’t reuse the bond’s swarm phrase.',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onUnlock(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock'),
                ),
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: onLock,
                  icon: const Icon(Icons.lock),
                  label: const Text('Lock'),
                ),
              ),
          ],
        ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Start vs Join

class _StartOrJoinCard extends StatefulWidget {
  const _StartOrJoinCard({required this.repoPath});
  final String repoPath;

  @override
  State<_StartOrJoinCard> createState() => _StartOrJoinCardState();
}

enum _Mode { picker, start, join }

class _StartOrJoinCardState extends State<_StartOrJoinCard> {
  _Mode _mode = _Mode.picker;

  @override
  Widget build(BuildContext context) {
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      padding: const EdgeInsets.all(16),
        child: switch (_mode) {
          _Mode.picker => _picker(),
          _Mode.start => _StartForm(
              repoPath: widget.repoPath,
              onBack: () => setState(() => _mode = _Mode.picker),
            ),
          _Mode.join => _JoinForm(
              repoPath: widget.repoPath,
              onBack: () => setState(() => _mode = _Mode.picker),
            ),
        },
    );
  }

  Widget _picker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Set up this repo',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Are you starting a new bond with teammates, or joining one they already made?',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _BigOptionTile(
          icon: Icons.add_circle_outline,
          title: 'Start a new bond',
          subtitle: 'Pick a bootstrap commit + a swarm phrase. Share the invite with your peers.',
          onTap: () => setState(() => _mode = _Mode.start),
        ),
        const SizedBox(height: 8),
        _BigOptionTile(
          icon: Icons.link,
          title: 'Join an existing bond',
          subtitle: 'Paste the invite your teammate sent, then type the swarm phrase they told you.',
          onTap: () => setState(() => _mode = _Mode.join),
        ),
      ],
    );
  }
}

class _BigOptionTile extends StatelessWidget {
  const _BigOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════

class _StartForm extends StatefulWidget {
  const _StartForm({required this.repoPath, required this.onBack});
  final String repoPath;
  final VoidCallback onBack;

  @override
  State<_StartForm> createState() => _StartFormState();
}

class _StartFormState extends State<_StartForm> {
  final _display = TextEditingController();
  final _bootstrap = TextEditingController();
  final _swarm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _display.dispose();
    _bootstrap.dispose();
    _swarm.dispose();
    super.dispose();
  }

  Future<void> _autofillBootstrap() async {
    // Ask git for the root commit. If the repo has multiple root
    // commits (octopus / orphan branches) we show the most recent of
    // them, but let the user override.
    try {
      final result = await Process.run(
        'git',
        ['rev-list', '--max-parents=0', 'HEAD'],
        workingDirectory: widget.repoPath,
        runInShell: false,
      );
      if (result.exitCode == 0) {
        final first = (result.stdout as String)
            .split('\n')
            .map((s) => s.trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty) {
          _bootstrap.text = first;
        }
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<BondService>().bindBond(
            repoPath: widget.repoPath,
            bootstrapCommit: _bootstrap.text.trim(),
            swarmPhrase: _swarm.text,
            displayName: _display.text.trim().isEmpty
                ? 'Bond'
                : _display.text.trim(),
          );
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
            ),
            Text('Start a new bond',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Pick a commit that every peer already has locally (usually the root commit). '
          'The bond ID is derived deterministically from this commit + the swarm phrase, '
          'so the same pair on every device converges on the same identifier — no server.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _display,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Bond name (local label)',
            helperText: 'Just for your UI — peers see their own label.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _bootstrap,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Bootstrap commit hash',
                  helperText:
                      'Full SHA-1 (40 hex chars) or SHA-256 (64 hex chars).',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : _autofillBootstrap,
              child: const Text('Use root commit'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _swarm,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Swarm phrase',
            helperText:
                'Shared secret for this bond. Send it to peers over a trusted channel.',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorStrip(message: _error!),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Create bond'),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════

class _JoinForm extends StatefulWidget {
  const _JoinForm({required this.repoPath, required this.onBack});
  final String repoPath;
  final VoidCallback onBack;

  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  final _invite = TextEditingController();
  final _swarm = TextEditingController();
  final _displayOverride = TextEditingController();
  String? _error;
  bool _busy = false;
  BondInvite? _parsed;

  @override
  void dispose() {
    _invite.dispose();
    _swarm.dispose();
    _displayOverride.dispose();
    super.dispose();
  }

  void _onInviteChanged() {
    try {
      final parsed = BondInvite.decode(_invite.text);
      setState(() {
        _parsed = parsed;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _parsed = null;
        // Only surface parse errors when there's enough content to
        // have meant something — avoids flashing red while typing.
        _error = _invite.text.trim().length > 8 ? e.message : null;
      });
    }
  }

  Future<void> _pasteInvite() async {
    final data = await Clipboard.getData(Clipboard.kMimeText);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _invite.text = text;
      _onInviteChanged();
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<BondService>().bindFromInvite(
            repoPath: widget.repoPath,
            inviteBlob: _invite.text,
            swarmPhrase: _swarm.text,
            overrideDisplayName: _displayOverride.text,
          );
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
            ),
            Text('Join an existing bond',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Your teammate should have sent you a `bond1:` invite and, separately, a swarm phrase '
          '(the invite alone is not enough to join — that\'s intentional).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _invite,
                enabled: !_busy,
                onChanged: (_) => _onInviteChanged(),
                decoration: const InputDecoration(
                  labelText: 'Invite (bond1:...)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pasteInvite,
              icon: const Icon(Icons.paste),
              label: const Text('Paste'),
            ),
          ],
        ),
        if (_parsed != null) ...[
          const SizedBox(height: 8),
          _InvitePreview(invite: _parsed!),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _swarm,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Swarm phrase',
            helperText: 'Sent to you separately. Both peers must have the same value.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _displayOverride,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: 'Local name (optional)',
            helperText:
                'Falls back to "${_parsed?.displayName ?? "Bond"}" from the invite.',
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorStrip(message: _error!),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: (_busy || _parsed == null) ? null : _submit,
            child: const Text('Join'),
          ),
        ),
      ],
    );
  }
}

class _InvitePreview extends StatelessWidget {
  const _InvitePreview({required this.invite});
  final BondInvite invite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invite.displayName.isEmpty
                ? 'Unnamed bond'
                : 'Joining: ${invite.displayName}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text('Bond ID: ${invite.bondId.shortHex}…',
              style: Theme.of(context).textTheme.bodySmall),
          Text(
            'Bootstrap: ${invite.bootstrapCommit.substring(0, 12)}…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Bonded state

class _BondedCard extends StatefulWidget {
  const _BondedCard({
    required this.repoPath,
    required this.membership,
    required this.onLeave,
  });

  final String repoPath;
  final BondMembership membership;
  final VoidCallback onLeave;

  @override
  State<_BondedCard> createState() => _BondedCardState();
}

class _BondedCardState extends State<_BondedCard> {
  String? _fingerprint;

  @override
  void initState() {
    super.initState();
    _refreshFingerprint();
  }

  Future<void> _refreshFingerprint() async {
    final fp = await context
        .read<BondService>()
        .fingerprintFor(widget.membership.bondId);
    if (mounted) setState(() => _fingerprint = fp);
  }

  Future<void> _copyInvite() async {
    final blob = context.read<BondService>().buildInvite(widget.repoPath);
    await Clipboard.setData(ClipboardData(text: blob));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite copied. Send the swarm phrase separately.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.membership;
    // Refresh fingerprint when identity unlock state changes.
    final service = context.watch<BondService>();
    if (service.isUnlocked && _fingerprint == null) {
      Future.microtask(_refreshFingerprint);
    }
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_outlined, size: 18),
                const SizedBox(width: 8),
                Text('Bonded', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _copyInvite,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Copy invite'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _KV('Name', m.displayName),
            _KV('Bond ID', '${m.bondId.shortHex}…  (${m.bondId.hex.length ~/ 2} bytes)'),
            _KV(
              'Bootstrap',
              m.bootstrapCommit.length > 12
                  ? '${m.bootstrapCommit.substring(0, 12)}…'
                  : m.bootstrapCommit,
            ),
            if (_fingerprint != null)
              _KV('Your fingerprint', _fingerprint!),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onLeave,
                icon: const Icon(Icons.exit_to_app, size: 18),
                label: const Text('Leave bond'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Proposals — the inbox + per-proposal attestation surface

class _ProposalsCard extends StatelessWidget {
  const _ProposalsCard({required this.repoPath});
  final String repoPath;

  @override
  Widget build(BuildContext context) {
    final backend = context.read<BondService>().backend;
    final listenable = backend.runtimeListenable(repoPath);
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      padding: const EdgeInsets.all(16),
      child: ListenableBuilder(
        listenable: listenable ?? const _NullListenable(),
        builder: (context, _) {
          final snap = backend.snapshot(repoPath);
          final proposals = snap?.proposals ?? const <BondProposalView>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.forum_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('Proposals (${proposals.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              if (proposals.isEmpty)
                Text(
                  'No proposals yet. When a peer publishes one, it appears here with its attestation roster.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                for (final p in proposals)
                  _ProposalTile(repoPath: repoPath, proposal: p),
            ],
          );
        },
      ),
    );
  }
}

class _ProposalTile extends StatelessWidget {
  const _ProposalTile({required this.repoPath, required this.proposal});
  final String repoPath;
  final BondProposalView proposal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Count approvals vs the current policy's relevant rule (if any).
    // Reads the same snapshot the tile is inside — cheap because
    // backend.snapshot returns a fresh view each call.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  proposal.title.isEmpty
                      ? '(untitled)'
                      : proposal.title,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                _humanAgo(proposal.receivedMs),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'from ${proposal.proposerHex.substring(0, 8)} · '
            'target ${proposal.targetRef} · '
            '${proposal.approvals}/${proposal.attestations.length} approve',
            style: theme.textTheme.bodySmall,
          ),
          if (proposal.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              proposal.body,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final a in proposal.attestations)
                _VerdictChip(
                  signerHex: a.signerHex,
                  verdict: a.verdict,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: () => _attest(
                  context,
                  AttestationVerdict.changesRequested,
                ),
                child: const Text('Changes'),
              ),
              const SizedBox(width: 4),
              FilledButton.tonal(
                onPressed: () =>
                    _attest(context, AttestationVerdict.approve),
                child: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _attest(
    BuildContext context,
    AttestationVerdict verdict,
  ) async {
    final service = context.read<BondService>();
    final err = await service.publishAttestation(
      repoPath: repoPath,
      proposalId: _unhex(proposal.proposalId),
      verdict: verdict,
      body: '',
      targetCommit: _unhex(proposal.sourceCommitHex),
    );
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.signerHex, required this.verdict});
  final String signerHex;
  final AttestationVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (label, color) = switch (verdict) {
      AttestationVerdict.approve => ('✓', c.primary),
      AttestationVerdict.changesRequested => ('!', c.error),
      AttestationVerdict.comment => ('…', c.outline),
      AttestationVerdict.withdraw => ('×', c.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
        color: color.withOpacity(0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text(
            signerHex.substring(0, 6),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Peers

class _PeersCard extends StatelessWidget {
  const _PeersCard({required this.repoPath, required this.membership});
  final String repoPath;
  final BondMembership membership;

  @override
  Widget build(BuildContext context) {
    final backend = context.read<BondService>().backend;
    final listenable = backend.runtimeListenable(repoPath);
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: listenable ?? const _NullListenable(),
          builder: (context, _) {
            final snap = backend.snapshot(repoPath);
            final peers = snap?.peers ?? const <BondPeerView>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_alt_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text('Peers (${peers.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                if (peers.isEmpty)
                  Text(
                    'No peers yet. Share the invite (and the swarm phrase via a separate channel) to bring someone in.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (final p in peers) _PeerTile(
                    repoPath: repoPath,
                    bondId: membership.bondId,
                    peer: p,
                  ),
              ],
            );
          },
        ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.repoPath,
    required this.bondId,
    required this.peer,
  });
  final String repoPath;
  final BondId bondId;
  final BondPeerView peer;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: peer.isRevoked
                  ? c.error
                  : peer.attached
                      ? Colors.green
                      : c.outline,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.shortHex,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    decoration:
                        peer.isRevoked ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  _peerSubtitle(peer),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _verify(context),
            child: const Text('Verify'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _handleMenu(context, v),
            itemBuilder: (_) => [
              if (!peer.isRevoked)
                const PopupMenuItem(
                  value: 'revoke',
                  child: Text('Revoke this key'),
                ),
              const PopupMenuItem(
                value: 'copy_pubkey',
                child: Text('Copy full pubkey'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _peerSubtitle(BondPeerView p) {
    final parts = <String>[];
    parts.add(p.attached ? 'connected' : 'offline');
    if (p.coordinate != null) {
      parts.add('lattice ${p.coordinate!.toHex()}');
    }
    if (p.lastSeenMs != null) {
      parts.add('seen ${_humanAgo(p.lastSeenMs!)}');
    }
    if (p.advertLamport != null) {
      parts.add('clock ${p.advertLamport}');
    }
    if (p.refCount > 0) parts.add('${p.refCount} ref${p.refCount == 1 ? "" : "s"}');
    if (p.isRevoked) parts.add('REVOKED');
    return parts.join(' · ');
  }

  Future<void> _verify(BuildContext context) async {
    final service = context.read<BondService>();
    final pubBytes = _unhex(peer.pubkeyHex);
    // Fast path computes immediately; the kizuna witness expansion
    // takes longer (one Möbius residual over 65 KiB) so it streams
    // into the dialog when ready.
    final fast = await service.safetyNumberWith(
      bondId: bondId,
      peerPubkey: pubBytes,
    );
    if (!context.mounted) return;
    final kizunaFuture = service.kizunaSafetyNumberWith(
      bondId: bondId,
      peerPubkey: pubBytes,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify this peer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Read both numbers to the peer over a trusted channel '
              '(phone, in person). Equal numbers on both sides = no '
              'one-in-the-middle.',
            ),
            const SizedBox(height: 14),
            const Text('Pair-pubkey number',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(
              fast ?? '(identity locked — unlock to compute)',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            const Text('Kizuna witness',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 4),
            FutureBuilder<String?>(
              future: kizunaFuture,
              builder: (context, snap) {
                final value = snap.connectionState == ConnectionState.done
                    ? (snap.data ?? '(identity locked)')
                    : 'computing 16D Möbius residual…';
                return SelectableText(
                  value,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    height: 1.4,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenu(BuildContext context, String value) async {
    final service = context.read<BondService>();
    switch (value) {
      case 'copy_pubkey':
        await Clipboard.setData(ClipboardData(text: peer.pubkeyHex));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pubkey copied')),
          );
        }
      case 'revoke':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Revoke this key?'),
            content: Text(
              'Broadcasts a revocation for ${peer.shortHex}. Peers who '
              'honor revocations will stop counting their attestations '
              'and drop new signed work from this key. This cannot be '
              'undone for that specific key (they\'d need to rotate).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Revoke'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final err = await service.publishRevocation(
          repoPath: repoPath,
          revokedPubkey: _unhex(peer.pubkeyHex),
          reason: RevokeReason.offboard,
          detail: 'Revoked via UI',
        );
        if (context.mounted && err != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err)),
          );
        }
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Policy summary

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.repoPath});
  final String repoPath;

  @override
  Widget build(BuildContext context) {
    final backend = context.read<BondService>().backend;
    final listenable = backend.runtimeListenable(repoPath);
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: listenable ?? const _NullListenable(),
          builder: (context, _) {
            final snap = backend.snapshot(repoPath);
            final policy = snap?.currentPolicy;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.rule, size: 18),
                    const SizedBox(width: 8),
                    Text('Policy',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                if (policy == null)
                  Text(
                    'No policy set. Any peer\'s refs can be adopted without approvals.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else ...[
                  Text(
                    '${policy.rules.length} rule${policy.rules.length == 1 ? "" : "s"} active',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final rule in policy.rules)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${rule.refPattern} → needs ${rule.minApprovals} approval${rule.minApprovals == 1 ? "" : "s"}'
                        '${rule.approverSet.isEmpty ? "" : " from ${rule.approverSet.length} keys"}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Diagnostics — collapsed, drop counters + error buckets

class _DiagnosticsCard extends StatefulWidget {
  const _DiagnosticsCard({required this.repoPath});
  final String repoPath;

  @override
  State<_DiagnosticsCard> createState() => _DiagnosticsCardState();
}

class _DiagnosticsCardState extends State<_DiagnosticsCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final backend = context.read<BondService>().backend;
    final listenable = backend.runtimeListenable(widget.repoPath);
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      child: ListenableBuilder(
        listenable: listenable ?? const _NullListenable(),
        builder: (context, _) {
          final snap = backend.snapshot(widget.repoPath);
          final counters = snap?.dropCounters ?? const {};
          final interesting = counters.entries.where((e) => e.value > 0).toList();
          return Column(
            children: [
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('Diagnostics'),
                subtitle: Text(
                  interesting.isEmpty
                      ? 'Nothing dropped or errored'
                      : '${interesting.length} bucket${interesting.length == 1 ? "" : "s"} with events',
                ),
                trailing: Icon(_open
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down),
                onTap: () => setState(() => _open = !_open),
              ),
              if (_open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in counters.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${e.key}: ${e.value}',
                            style: const TextStyle(fontFamily: 'monospace'),
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
}

// ═════════════════════════════════════════════════════════════════════════
// Small shared pieces

class _KV extends StatelessWidget {
  const _KV(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: c.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: c.onErrorContainer)),
          ),
        ],
    );
  }
}

/// Listenable that never fires — used as a fallback when there's no
/// runtime yet (pre-bind state). Keeps ListenableBuilder happy.
class _NullListenable implements Listenable {
  const _NullListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// Maps raw exceptions to UI-friendly copy. Strips the "Exception: "
/// prefix Dart's default toString adds; rewrites the common failure
/// modes users hit.
String _friendly(Object e) {
  final raw = e.toString();
  if (raw.startsWith('StateError: ')) {
    return raw.substring('StateError: '.length);
  }
  if (raw.startsWith('ArgumentError: ')) {
    return raw.substring('ArgumentError: '.length);
  }
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }
  if (raw.startsWith('FormatException: ')) {
    return 'Invite format error — ${raw.substring("FormatException: ".length)}';
  }
  return raw;
}

/// Humanised duration since an epoch-ms timestamp. Matches common
/// "X ago" phrasings: "just now", "3 min ago", "2 h ago", "yesterday",
/// "3 d ago".
String _humanAgo(int epochMs) {
  final delta = DateTime.now().millisecondsSinceEpoch - epochMs;
  if (delta < 0) return 'soon';
  final sec = delta ~/ 1000;
  if (sec < 30) return 'just now';
  if (sec < 60) return '${sec}s ago';
  final min = sec ~/ 60;
  if (min < 60) return '${min}m ago';
  final hr = min ~/ 60;
  if (hr < 24) return '${hr}h ago';
  final days = hr ~/ 24;
  if (days == 1) return 'yesterday';
  return '${days}d ago';
}

/// Utility: hex → bytes. Duplicated from bond_service to keep UI
/// free of deep imports; the UI only ever encounters validated hex.
Uint8List _unhex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
