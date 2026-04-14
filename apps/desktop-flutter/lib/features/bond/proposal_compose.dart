// ═════════════════════════════════════════════════════════════════════════
// features/bond/proposal_compose.dart — author + publish a Proposal
//
// Modal sheet launched from the Bond panel. Pre-fills source from the
// repo's HEAD + current branch; defaults target to refs/heads/main;
// recipient is a chip picker over current bond peers ("any" = broadcast
// to the swarm). Markdown body field, draft autosave to ephemeral
// state. Publish calls BondService.publishProposal which signs +
// broadcasts and returns the proposalId.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/bond/bond_backend.dart';
import '../../backend/bond_service.dart';
import '../../ui/material_surface.dart';
import '../../ui/tokens.dart';

/// Opens the proposal compose sheet over [context]. Returns the
/// 32-byte proposalId on successful publish, null on cancel/failure.
Future<Uint8List?> showProposalCompose(
  BuildContext context, {
  required String repoPath,
}) {
  return showModalBottomSheet<Uint8List?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ProposalComposeSheet(repoPath: repoPath),
  );
}

class _ProposalComposeSheet extends StatefulWidget {
  const _ProposalComposeSheet({required this.repoPath});
  final String repoPath;

  @override
  State<_ProposalComposeSheet> createState() => _ProposalComposeSheetState();
}

class _ProposalComposeSheetState extends State<_ProposalComposeSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _sourceRef = TextEditingController();
  final _targetRef = TextEditingController(text: 'refs/heads/main');

  String? _sourceCommitHex;
  Uint8List? _recipient; // null = broadcast
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _autofillFromRepo();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _sourceRef.dispose();
    _targetRef.dispose();
    super.dispose();
  }

  Future<void> _autofillFromRepo() async {
    try {
      // HEAD ref name → fills sourceRef as the branch the user is on.
      final ref = await Process.run(
        'git',
        ['symbolic-ref', '--short', 'HEAD'],
        workingDirectory: widget.repoPath,
        runInShell: false,
      );
      if (ref.exitCode == 0) {
        final name = (ref.stdout as String).trim();
        if (name.isNotEmpty) {
          _sourceRef.text = 'refs/heads/$name';
        }
      }
      // HEAD commit hash → fills sourceCommit (not user-editable; the
      // hash is the content-addressed thing we're proposing).
      final head = await Process.run(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: widget.repoPath,
        runInShell: false,
      );
      if (head.exitCode == 0) {
        final hex = (head.stdout as String).trim();
        if (hex.length == 40 || hex.length == 64) {
          if (mounted) setState(() => _sourceCommitHex = hex);
        }
      }
    } catch (_) {
      // Autofill is best-effort; user can type the refs by hand.
    }
  }

  Future<void> _submit() async {
    final commitHex = _sourceCommitHex;
    if (commitHex == null) {
      setState(() => _error = 'No HEAD commit detected. Open a repo first.');
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.read<BondService>().publishProposal(
            repoPath: widget.repoPath,
            recipientPubkey: _recipient ?? Uint8List(32), // 32-zero = broadcast
            sourceRef: _sourceRef.text.trim(),
            sourceCommit: _unhex(commitHex),
            targetRef: _targetRef.text.trim(),
            title: _title.text.trim(),
            body: _body.text.trim(),
          );
      if (!mounted) return;
      if (result.error != null) {
        setState(() => _error = result.error);
      } else {
        Navigator.of(context).pop(result.proposalId);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bondService = context.watch<BondService>();
    final m = bondService.membershipFor(widget.repoPath);
    final peers =
        bondService.backend.snapshot(widget.repoPath)?.peers ?? const [];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: MaterialSurface(
        tone: AppMaterialTone.panelStrong,
        radius: 12,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: AbsorbPointer(
          absorbing: _busy,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.forum_outlined, size: 18, color: t.textNormal),
                    const SizedBox(width: 8),
                    Text('Propose a change',
                        style: TextStyle(
                          color: t.textNormal,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        )),
                    const Spacer(),
                    if (m != null)
                      Text(
                        m.displayName,
                        style: TextStyle(color: t.textMuted, fontSize: 11),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sourceRef,
                        decoration: const InputDecoration(
                          labelText: 'Source ref',
                          helperText: 'Your branch carrying the change',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _targetRef,
                        decoration: const InputDecoration(
                          labelText: 'Target ref',
                          helperText: 'Where to land it',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _sourceCommitHex == null
                      ? 'Detecting HEAD commit…'
                      : 'HEAD: ${_sourceCommitHex!.substring(0, 12)}…',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 11,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
                const SizedBox(height: 12),
                _RecipientPicker(
                  peers: peers,
                  selected: _recipient,
                  onChanged: (v) => setState(() => _recipient = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  decoration: const InputDecoration(
                    labelText: 'Body (markdown, optional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  minLines: 5,
                  maxLines: 10,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: t.stateDeleted, fontSize: 11)),
                ],
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Publish proposal'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipientPicker extends StatelessWidget {
  const _RecipientPicker({
    required this.peers,
    required this.selected,
    required this.onChanged,
  });
  final List<BondPeerView> peers;
  final Uint8List? selected;
  final ValueChanged<Uint8List?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recipient',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _RecipientChip(
              label: 'Any (broadcast)',
              active: selected == null,
              onTap: () => onChanged(null),
            ),
            for (final p in peers)
              _RecipientChip(
                label: p.shortHex,
                active: selected != null && _bytesEq(selected!, _unhex(p.pubkeyHex)),
                onTap: () => onChanged(_unhex(p.pubkeyHex)),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecipientChip extends StatelessWidget {
  const _RecipientChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: active
                ? t.accentBright.withValues(alpha: 0.18)
                : t.chromeBorderFaint,
            border: Border.all(
              color: active ? t.accentBright : t.chromeBorderSubtle,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? t.accentBright : t.textNormal,
              fontSize: 11,
              fontFamily: 'JetBrainsMono',
            ),
          ),
        ),
      ),
    );
  }
}

bool _bytesEq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _unhex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
