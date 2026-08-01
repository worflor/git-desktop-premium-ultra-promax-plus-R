// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:git_desktop/backend/atomic_write.dart';
import 'package:git_desktop/i18n/gen/strings.g.dart';
import 'package:git_desktop/ui/design_primitives.dart';
import 'package:git_desktop/ui/motion.dart';

import 'skill_catalog.dart';
import 'skills_bloom.dart';

/// The floating skills affordance for the Settings page: a square glass toggle
/// that blooms the skill list into an overlay and, per skill, copies the
/// markdown to the clipboard or saves it to a file. Drop it into the settings
/// root Stack as a bottom-right `Positioned` child.
///
/// The collapsed toggle lives here; the open bloom is an [OverlayEntry] so it
/// floats above the scroll content and dismisses on an outside tap. A single
/// controller drives both the panel's staggered reveal and the plus->X morph,
/// so the button appears to open into the panel and back.
class SkillsFab extends StatefulWidget {
  const SkillsFab({super.key});

  @override
  State<SkillsFab> createState() => _SkillsFabState();
}

class _SkillsFabState extends State<SkillsFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AppMotion.fluid,
  );
  // Links the overlay to the inline toggle so the panel is positioned by the
  // compositor rather than by screen coordinates captured at open time. That
  // is what makes it TRACK the anchor when the settings list scrolls; a panel
  // computed from a one-time RenderBox read hovers where the section used to
  // be the moment the page moves.
  final LayerLink _link = LayerLink();
  // Explicitly focused on open. `autofocus` alone does not reliably take
  // inside an OverlayEntry — the page keeps focus and Escape goes nowhere.
  final FocusNode _keys = FocusNode(debugLabel: 'agent-skills-overlay');
  OverlayEntry? _entry;

  bool get _open => _entry != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honor the user's motion-rate / reduce-motion setting for the bloom.
    _ctrl.duration = context.motionRead(AppMotion.fluid);
  }

  @override
  void dispose() {
    // An OverlayEntry owns internal listenables; removing it is not enough,
    // it has to be disposed or its notifier outlives the widget.
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _keys.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _openBloom() {
    if (_open) return;

    _entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            // Outside-tap scrim. Transparent — the panel carries its own
            // depth, so no dimming is needed to read it. Focused so Escape
            // dismisses, which is the reflex for any overlay.
            Positioned.fill(
              child: Focus(
                focusNode: _keys,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _closeBloom();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                // Pointer-DOWN, not tap: someone reaching past the panel is
                // usually trying to scroll the page, and a scrim that swallows
                // the drag and does nothing reads as a frozen window. Dismiss
                // on the first touch outside instead.
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _closeBloom(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // Follows the inline toggle: the overlay's own fused toggle is
            // inset 10 from the stack's right edge, so nudging the follower
            // 10px right lands it exactly on the anchor, and it stays there
            // while the page scrolls.
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(10, 0),
              // An OverlayEntry sits ABOVE the page's Scaffold, so nothing in
              // it has a Material ancestor — and text without one renders with
              // Flutter's yellow debug underlines. Transparent, so the panel's
              // own glass is still what you see.
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => SkillsBloomOverlay(
                    reveal: _ctrl.value,
                    skills: kAgentSkills,
                    onCopy: _copy,
                    onSave: _save,
                    onToggle: _closeBloom,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_entry!);
    _keys.requestFocus();
    _ctrl.forward();
    setState(() {}); // hide the collapsed toggle behind the overlay's own
  }

  void _closeBloom() {
    if (!_open) return;
    _ctrl.reverse().whenComplete(() {
      _entry?.remove();
      _entry?.dispose();
      _entry = null;
      if (mounted) setState(() {});
    });
  }

  Future<void> _copy(AgentSkill skill) async {
    final message = context.t.agentSkills.copied(title: skill.title);
    try {
      final md = await skill.loadMarkdown();
      await Clipboard.setData(ClipboardData(text: md));
      if (!mounted) return;
      _flash(message);
    } on Object catch (e) {
      if (!mounted) return;
      _flash(context.t.agentSkills.saveFailed(error: '$e'));
    }
  }

  Future<void> _save(AgentSkill skill) async {
    final t = context.t.agentSkills;
    final dialogTitle = t.saveDialog(title: skill.title);
    final md = await skill.loadMarkdown();
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: skill.fileName,
        type: FileType.custom,
        allowedExtensions: const ['md'],
      );
      if (path == null) return; // cancelled
      await writeFileAtomicString(File(path), md);
      if (!mounted) return;
      _flash(context.t.agentSkills.savedTo(path: path));
    } on Object catch (e) {
      if (!mounted) return;
      _flash(context.t.agentSkills.saveFailed(error: '$e'));
    }
  }

  void _flash(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The collapsed toggle. While the bloom is open it is hidden — the overlay
    // renders its own fused-corner toggle at the same spot, so the morph is
    // continuous.
    return CompositedTransformTarget(
      link: _link,
      child: Opacity(
        opacity: _open ? 0 : 1,
        child: IgnorePointer(
          ignoring: _open,
          child: SkillsToggleButton(reveal: 0, onTap: _openBloom),
        ),
      ),
    );
  }
}
