// ═════════════════════════════════════════════════════════════════════════
// features/bond/policy_editor.dart — author + publish a Policy
//
// Modal sheet launched from the Policy card in BondPage. Lists the
// currently-active rules (if any) so the author can amend rather than
// rewrite, then publishes a fresh Policy that supersedes the
// incumbent (the backend auto-fills supersedes from currentPolicyHash).
//
// Each rule row: refPattern (git glob), minApprovals (int), and an
// optional approver multi-select picked from current bond peers. An
// empty approver set means "any non-revoked signer counts."
// ═════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/bond/bond_backend.dart';
import '../../backend/bond/objects.dart';
import '../../backend/bond_service.dart';
import '../../ui/material_surface.dart';
import '../../ui/tokens.dart';

/// Opens the policy editor over [context]. Returns true on successful
/// publish, false on cancel / failure.
Future<bool> showPolicyEditor(
  BuildContext context, {
  required String repoPath,
}) async {
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _PolicyEditorSheet(repoPath: repoPath),
      ) ??
      false;
}

class _PolicyEditorSheet extends StatefulWidget {
  const _PolicyEditorSheet({required this.repoPath});
  final String repoPath;

  @override
  State<_PolicyEditorSheet> createState() => _PolicyEditorSheetState();
}

class _PolicyEditorSheetState extends State<_PolicyEditorSheet> {
  final List<_RuleDraft> _rules = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final snap = context.read<BondService>().backend.snapshot(widget.repoPath);
    final current = snap?.currentPolicy;
    if (current != null) {
      for (final r in current.rules) {
        _rules.add(_RuleDraft.fromRule(r));
      }
    }
    if (_rules.isEmpty) {
      _rules.add(_RuleDraft.empty());
    }
  }

  Future<void> _publish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rules = <PolicyRule>[];
      for (final d in _rules) {
        final rule = d.build();
        if (rule == null) {
          setState(() => _error = 'Invalid rule: ${d.refPattern.text}');
          return;
        }
        rules.add(rule);
      }
      final err = await context.read<BondService>().publishPolicy(
            repoPath: widget.repoPath,
            rules: rules,
          );
      if (!mounted) return;
      if (err != null) {
        setState(() => _error = err);
      } else {
        Navigator.of(context).pop(true);
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
    final peers =
        bondService.backend.snapshot(widget.repoPath)?.peers ?? const [];
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                    Icon(Icons.rule, size: 18, color: t.textNormal),
                    const SizedBox(width: 8),
                    Text(
                      'Policy editor',
                      style: TextStyle(
                        color: t.textNormal,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(
                          () => _rules.add(_RuleDraft.empty())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add rule'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Rules gate every pull() into a matching ref. They\'re '
                  'broadcast as a signed Policy that supersedes the '
                  'current one — peers must accept the chain.',
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _rules.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _RuleEditor(
                      draft: _rules[i],
                      peers: peers,
                      onRemove: _rules.length == 1
                          ? null
                          : () => setState(() => _rules.removeAt(i)),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(color: t.stateDeleted, fontSize: 11)),
                ],
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: _busy ? null : _publish,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Publish policy'),
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

class _RuleDraft {
  _RuleDraft.empty()
      : refPattern = TextEditingController(text: 'refs/heads/main'),
        minApprovals = TextEditingController(text: '1'),
        approvers = <String>{};

  _RuleDraft.fromRule(PolicyRule r)
      : refPattern = TextEditingController(text: r.refPattern),
        minApprovals = TextEditingController(text: r.minApprovals.toString()),
        approvers = r.approverSet
            .map((k) =>
                k.map((b) => b.toRadixString(16).padLeft(2, '0')).join())
            .toSet();

  final TextEditingController refPattern;
  final TextEditingController minApprovals;
  final Set<String> approvers; // pubkey hex set

  PolicyRule? build() {
    final pat = refPattern.text.trim();
    if (pat.isEmpty) return null;
    final n = int.tryParse(minApprovals.text.trim());
    if (n == null || n < 0) return null;
    return PolicyRule(
      refPattern: pat,
      minApprovals: n,
      approverSet: approvers
          .map((h) => Uint8List.fromList(_unhex(h)))
          .toList(growable: false),
    );
  }
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({
    required this.draft,
    required this.peers,
    required this.onRemove,
  });
  final _RuleDraft draft;
  final List<BondPeerView> peers;
  final VoidCallback? onRemove;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MaterialSurface(
      tone: AppMaterialTone.panel,
      radius: 8,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: widget.draft.refPattern,
                  decoration: const InputDecoration(
                    labelText: 'Ref pattern',
                    helperText: 'e.g. refs/heads/main, refs/heads/release/*',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: widget.draft.minApprovals,
                  decoration: const InputDecoration(
                    labelText: 'Min ✓',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              if (widget.onRemove != null)
                IconButton(
                  onPressed: widget.onRemove,
                  icon: Icon(Icons.close, color: t.textMuted, size: 18),
                  tooltip: 'Remove rule',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Approvers (empty = any non-revoked signer counts)',
            style: TextStyle(color: t.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final p in widget.peers)
                _ApproverChip(
                  peer: p,
                  selected: widget.draft.approvers.contains(p.pubkeyHex),
                  onToggle: () {
                    setState(() {
                      if (widget.draft.approvers.contains(p.pubkeyHex)) {
                        widget.draft.approvers.remove(p.pubkeyHex);
                      } else {
                        widget.draft.approvers.add(p.pubkeyHex);
                      }
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApproverChip extends StatelessWidget {
  const _ApproverChip({
    required this.peer,
    required this.selected,
    required this.onToggle,
  });
  final BondPeerView peer;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? t.accentBright.withValues(alpha: 0.18)
              : t.chromeBorderFaint,
          border: Border.all(
            color: selected ? t.accentBright : t.chromeBorderSubtle,
          ),
        ),
        child: Text(
          peer.shortHex,
          style: TextStyle(
            color: selected ? t.accentBright : t.textNormal,
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

List<int> _unhex(String hex) {
  final out = List<int>.filled(hex.length ~/ 2, 0);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
