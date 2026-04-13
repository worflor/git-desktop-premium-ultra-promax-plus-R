import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_identity.dart';
import '../../../app/repository_state.dart';
import '../../../backend/file_picker.dart';
import '../../../backend/git.dart';
import '../../../ui/design_primitives.dart';
import '../../../ui/form_controls.dart';
import '../../../ui/material_surface.dart';
import '../../../ui/motion.dart';
import '../../../ui/tokens.dart';
import '../onboarding_flow.dart';
import '../onboarding_state.dart';

/// Step 3 — the three "doors" (Open / Clone / Create). Each door calls
/// the same backend functions the sidebar uses, then fires
/// [OnboardingState.complete] on success so the workspace cross-fades in
/// already populated with the user's repo.
class RepoStepPage extends StatefulWidget {
  const RepoStepPage({super.key});

  @override
  State<RepoStepPage> createState() => _RepoStepPageState();
}

enum _DoorId { open, clone, create }

class _RepoStepPageState extends State<RepoStepPage> {
  _DoorId? _expanded;
  bool _busy = false;
  String? _error;

  final _cloneUrlController = TextEditingController();
  final _cloneTargetController = TextEditingController();

  @override
  void dispose() {
    _cloneUrlController.dispose();
    _cloneTargetController.dispose();
    super.dispose();
  }

  Future<void> _finish(String path) async {
    final repo = context.read<RepositoryState>();
    final err = await repo.setActivePath(path);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    await context.read<OnboardingState>().complete();
  }

  Future<void> _onOpen() async {
    setState(() => _error = null);
    final picked = await pickDirectory('Open Repository');
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    await _finish(picked);
  }

  Future<void> _onCreate() async {
    setState(() => _error = null);
    final picked = await pickDirectory('Create Repository');
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    final result = await initRepository(picked);
    if (!mounted) return;
    if (!result.ok || result.data == null) {
      setState(() {
        _busy = false;
        _error = result.error ?? 'Failed to create repository.';
      });
      return;
    }
    await _finish(result.data!);
  }

  Future<void> _onClone() async {
    final url = _cloneUrlController.text.trim();
    final target = _cloneTargetController.text.trim();
    if (url.isEmpty || target.isEmpty) {
      setState(() => _error = 'URL and target path required.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final result = await cloneRepository(url, target);
    if (!mounted) return;
    if (!result.ok || result.data == null) {
      setState(() {
        _busy = false;
        _error = result.error ?? 'Failed to clone repository.';
      });
      return;
    }
    await _finish(result.data!);
  }

  Future<void> _pickCloneTarget() async {
    final picked = await pickDirectory('Clone Target');
    if (picked == null || !mounted) return;
    setState(() => _cloneTargetController.text = picked);
  }

  Future<void> _later() async {
    await context.read<OnboardingState>().complete();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final identity = context.watch<AppIdentityState>().identity;

    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 8, 48, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              '${identity.shortName} needs something to look at.',
              style: TextStyle(
                color: t.textStrong,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Door(
                  id: _DoorId.open,
                  icon: Icons.folder_outlined,
                  title: 'Open',
                  subtitle: 'existing',
                  hint: 'one you already have',
                  expanded: _expanded == _DoorId.open,
                  compressed: _expanded != null && _expanded != _DoorId.open,
                  onTap: _busy ? null : _onOpen,
                  tokens: t,
                ),
                const SizedBox(width: 14),
                _Door(
                  id: _DoorId.clone,
                  icon: Icons.cloud_download_outlined,
                  title: 'Clone',
                  subtitle: 'from URL',
                  hint: 'paste a GitHub link',
                  expanded: _expanded == _DoorId.clone,
                  compressed: _expanded != null && _expanded != _DoorId.clone,
                  onTap: _busy
                      ? null
                      : () {
                          setState(() {
                            _expanded = _expanded == _DoorId.clone
                                ? null
                                : _DoorId.clone;
                            _error = null;
                          });
                        },
                  tokens: t,
                  expandedContent: _CloneForm(
                    urlController: _cloneUrlController,
                    targetController: _cloneTargetController,
                    onPickTarget: _pickCloneTarget,
                    onCancel: () => setState(() {
                      _expanded = null;
                      _error = null;
                    }),
                    onClone: _busy ? null : _onClone,
                    busy: _busy,
                  ),
                ),
                const SizedBox(width: 14),
                _Door(
                  id: _DoorId.create,
                  icon: Icons.auto_awesome_outlined,
                  title: 'Create',
                  subtitle: 'new',
                  hint: 'start something fresh',
                  expanded: _expanded == _DoorId.create,
                  compressed: _expanded != null && _expanded != _DoorId.create,
                  onTap: _busy ? null : _onCreate,
                  tokens: t,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                _error!,
                style: TextStyle(color: t.danger, fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: OnboardingQuietLink(
              label: "i'll do this later",
              onTap: _later,
            ),
          ),
          const SizedBox(height: 6),
          // No primary here — the three doors ARE the primary action.
          // Rendering a disabled "Let's go" would be a dead button in the
          // corner tempting people to click it.
          const OnboardingNavRow(onPrimary: null, showPrimary: false),
        ],
      ),
    );
  }
}

class _Door extends StatefulWidget {
  final _DoorId id;
  final IconData icon;
  final String title;
  final String subtitle;
  final String hint;
  final bool expanded;
  final bool compressed;
  final VoidCallback? onTap;
  final AppTokens tokens;
  final Widget? expandedContent;

  const _Door({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.expanded,
    required this.compressed,
    required this.onTap,
    required this.tokens,
    this.expandedContent,
  });

  @override
  State<_Door> createState() => _DoorState();
}

class _DoorState extends State<_Door> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final enabled = widget.onTap != null;
    final flex = widget.expanded ? 3 : (widget.compressed ? 1 : 2);
    final radius = themeDefinitionFor(t.id)
        .shader
        .geometry
        .radius
        .clamp(6.0, 14.0)
        .toDouble();

    return Expanded(
      flex: flex,
      child: AnimatedContainer(
        duration: context.motion(AppMotion.fluid),
        curve: AppMotion.fluidCurve,
        child: MouseRegion(
          cursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: context.motion(AppMotion.fade),
              decoration: BoxDecoration(
                color: widget.expanded
                    ? t.panelOverlayStrong
                    : _hover
                        ? t.itemHoverBg
                        : t.panelOverlay.withValues(alpha: 0.45),
                border: Border.all(
                  color: widget.expanded
                      ? t.accentBright.withValues(alpha: 0.55)
                      : t.chromeBorderSubtle,
                ),
                borderRadius: BorderRadius.circular(radius),
              ),
              padding: const EdgeInsets.all(18),
              child: widget.expanded && widget.expandedContent != null
                  ? widget.expandedContent!
                  : _DoorCollapsed(
                      icon: widget.icon,
                      title: widget.title,
                      subtitle: widget.subtitle,
                      hint: widget.hint,
                      compressed: widget.compressed,
                      tokens: t,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DoorCollapsed extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String hint;
  final bool compressed;
  final AppTokens tokens;

  const _DoorCollapsed({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.compressed,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: compressed ? 28 : 40,
          color: tokens.accentBright,
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: TextStyle(
            color: tokens.textStrong,
            fontSize: compressed ? 14 : 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: compressed ? 11 : 12.5,
          ),
        ),
        if (!compressed) ...[
          const SizedBox(height: 12),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.textFaint,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _CloneForm extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController targetController;
  final VoidCallback onPickTarget;
  final VoidCallback onCancel;
  final VoidCallback? onClone;
  final bool busy;

  const _CloneForm({
    required this.urlController,
    required this.targetController,
    required this.onPickTarget,
    required this.onCancel,
    required this.onClone,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_download_outlined,
                color: t.accentBright, size: 20),
            const SizedBox(width: 8),
            Text(
              'Clone from URL',
              style: TextStyle(
                color: t.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'Repository URL',
          child: AppTextField(
            controller: urlController,
            hintText: 'git@github.com:you/repo.git',
            enabled: !busy,
            height: 32,
            fontSize: 11.5,
            mono: true,
          ),
        ),
        const SizedBox(height: 10),
        _LabeledField(
          label: 'Target folder',
          child: Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: targetController,
                  hintText: '/path/to/clone',
                  enabled: !busy,
                  height: 32,
                  fontSize: 11.5,
                  mono: true,
                ),
              ),
              const SizedBox(width: 6),
              _SmallButton(
                label: 'Browse…',
                onTap: busy ? null : onPickTarget,
              ),
            ],
          ),
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _SmallButton(label: 'Cancel', onTap: busy ? null : onCancel),
            const SizedBox(width: 8),
            _SmallButton(
              label: busy ? 'Cloning…' : 'Clone',
              onTap: onClone,
              primary: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.textFaint,
            fontSize: 9.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  const _SmallButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onTap != null;
    final radius = themeDefinitionFor(t.id)
        .shader
        .geometry
        .radius
        .clamp(3.0, 8.0)
        .toDouble();
    return MouseRegion(
      cursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: primary
                ? t.accentBright.withValues(alpha: enabled ? 0.18 : 0.08)
                : t.btnBg,
            border: Border.all(
              color: primary
                  ? t.accentBright.withValues(alpha: enabled ? 0.6 : 0.3)
                  : t.btnBorder,
            ),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: enabled
                  ? (primary ? t.textStrong : t.btnText)
                  : t.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
