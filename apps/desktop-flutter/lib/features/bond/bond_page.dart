// ═════════════════════════════════════════════════════════════════════════
// features/bond/bond_page.dart — minimal Bond control surface
//
// Three stacked sections:
//   • Identity: unlock / lock via phrase
//   • Bond binding: register this repo against a bond_id (bootstrap
//     commit + swarm phrase)
//   • Peer status: show known bonds, live peer sessions, last-seen
//
// Styling is deliberately plain: this is an experimental surface
// gated behind a feature flag. When Bond graduates to shipping, it
// gets a pass over the Manifold design system to match other pages.
// ═════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/bond_service.dart';

class BondPage extends StatefulWidget {
  const BondPage({super.key, required this.repoPath});

  /// The repo the page is scoped to. Bond memberships are per-repo.
  final String repoPath;

  @override
  State<BondPage> createState() => _BondPageState();
}

class _BondPageState extends State<BondPage> {
  final TextEditingController _phrase = TextEditingController();
  final TextEditingController _bootstrapCommit = TextEditingController();
  final TextEditingController _swarmPhrase = TextEditingController();
  final TextEditingController _displayName = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget disk load; notifyListeners updates the UI.
    Future.microtask(() {
      context.read<BondService>().loadFromDisk(widget.repoPath);
    });
  }

  @override
  void dispose() {
    _phrase.dispose();
    _bootstrapCommit.dispose();
    _swarmPhrase.dispose();
    _displayName.dispose();
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
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onBind() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<BondService>().bindBond(
        repoPath: widget.repoPath,
        bootstrapCommit: _bootstrapCommit.text.trim(),
        swarmPhrase: _swarmPhrase.text,
        displayName: _displayName.text.trim().isEmpty
            ? 'Bond'
            : _displayName.text.trim(),
      );
      _bootstrapCommit.clear();
      _swarmPhrase.clear();
      _displayName.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BondService>();
    final membership = service.membershipFor(widget.repoPath);

    return Scaffold(
      appBar: AppBar(title: const Text('Bond')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _IdentityCard(
              isUnlocked: service.isUnlocked,
              phrase: _phrase,
              onUnlock: _onUnlock,
              onLock: service.lock,
            ),
            const SizedBox(height: 16),
            _BindCard(
              enabled: service.isUnlocked && membership == null,
              bootstrapCommit: _bootstrapCommit,
              swarmPhrase: _swarmPhrase,
              displayName: _displayName,
              onBind: _onBind,
              existing: membership,
            ),
            const SizedBox(height: 16),
            if (membership != null) _PeersCard(membership: membership),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
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
  final VoidCallback onUnlock;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Identity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              isUnlocked
                  ? 'Unlocked. Same phrase on any device = same you.'
                  : 'Enter your phrase to derive your Bond identity. '
                      'The phrase never leaves this device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (!isUnlocked) ...[
              TextField(
                controller: phrase,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Identity phrase',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onUnlock(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onUnlock,
                  child: const Text('Unlock'),
                ),
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: onLock,
                  child: const Text('Lock'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BindCard extends StatelessWidget {
  const _BindCard({
    required this.enabled,
    required this.bootstrapCommit,
    required this.swarmPhrase,
    required this.displayName,
    required this.onBind,
    required this.existing,
  });

  final bool enabled;
  final TextEditingController bootstrapCommit;
  final TextEditingController swarmPhrase;
  final TextEditingController displayName;
  final VoidCallback onBind;
  final BondMembership? existing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              existing == null ? 'Join or create a bond' : 'Bonded',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (existing != null) ...[
              _KV('Name', existing!.displayName),
              _KV('Bond ID', existing!.bondId.shortHex),
              _KV(
                'Bootstrap',
                existing!.bootstrapCommit.length > 12
                    ? '${existing!.bootstrapCommit.substring(0, 12)}…'
                    : existing!.bootstrapCommit,
              ),
            ] else ...[
              Text(
                'Both peers need the same bootstrap commit and the same '
                'swarm phrase. The bond_id derived from them is the '
                'rendezvous topic — a cryptographic convergence.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: displayName,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Display name (local only)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: bootstrapCommit,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Bootstrap commit hash',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: swarmPhrase,
                enabled: enabled,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Swarm phrase',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => enabled ? onBind() : null,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: enabled ? onBind : null,
                  child: const Text('Bind'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeersCard extends StatelessWidget {
  const _PeersCard({required this.membership});
  final BondMembership membership;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BondService>();
    final backend = service.backend;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Peers', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // Backend state is not a ChangeNotifier — UI shows a
            // snapshot. The full integration will surface live counts
            // via a dedicated stream, but "how many peers right now"
            // is good enough for the control surface.
            Text(
              'Backend id: ${backend.id}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Bond: ${membership.bondId.shortHex} (${membership.displayName})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Transport integration (Whisper) wires peers into this '
              'list. Before that lands, a peer pair only appears when '
              'tests inject a loopback session.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

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
            width: 96,
            child: Text(k, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: Text(v, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

