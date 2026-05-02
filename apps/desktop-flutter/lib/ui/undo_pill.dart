import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/preferences_state.dart';
import '../backend/undo_controller.dart';
import 'design_primitives.dart';
import 'morph_text.dart';
import 'motion.dart';
import 'tokens.dart';

/// Global "action-pending" pill. Lives in an app-shell overlay slot
/// so a destructive action scheduled on any page shows its cancel
/// affordance in a consistent place regardless of navigation.
///
/// Renders nothing when [UndoCoordinator.pending] is null. When a
/// pending action exists, fades in, ticks a per-second countdown,
/// and exposes a Cancel button. Pill itself is not tappable — the
/// button is the only cancel affordance so clicks don't ambiguate
/// with e.g. dismiss-on-outside-tap.
class UndoPill extends StatefulWidget {
  const UndoPill({super.key});

  @override
  State<UndoPill> createState() => _UndoPillState();
}

class _UndoPillState extends State<UndoPill>
    with SingleTickerProviderStateMixin {
  static const Duration _authoredIntro = Duration(milliseconds: 140);
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _authoredIntro,
  );
  Timer? _tick;
  bool _hasPending = false;
  bool _goHovered = false;
  bool _goPressed = false;
  PreferencesState? _prefs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = context.read<PreferencesState>();
    if (!identical(_prefs, prefs)) {
      _prefs?.removeListener(_onPrefsChanged);
      _prefs = prefs;
      prefs.addListener(_onPrefsChanged);
    }
    _applyMotionDuration();
  }

  void _onPrefsChanged() {
    if (mounted) _applyMotionDuration();
  }

  /// Apply the motion-scaled intro duration. Only reassigns when the
  /// controller is AT REST — mutating an active AnimationController's
  /// duration retroactively shifts its `.value` (position = elapsed /
  /// duration), which would produce a visible jump in the fade if
  /// motionRate changed mid-transition. Fade-ins/outs are short (140ms
  /// authored, ≤280ms even at half-rate) so waiting for rest is a
  /// negligible delay in practice.
  void _applyMotionDuration() {
    if (_intro.isAnimating) return;
    final scaled = _prefs == null
        ? _authoredIntro
        : context.motionRead(_authoredIntro);
    if (_intro.duration != scaled) {
      _intro.duration = scaled;
    }
  }

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    _tick?.cancel();
    _intro.dispose();
    super.dispose();
  }

  void _syncTick(bool hasPending) {
    if (hasPending && _tick == null) {
      // 100ms cadence gives a smooth countdown without burning cycles;
      // remaining text only changes once per second so most rebuilds
      // produce identical frames (cheap).
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
    } else if (!hasPending && _tick != null) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final coord = context.watch<UndoCoordinator>();
    final pending = coord.pending;
    final hasPending = pending != null;
    if (hasPending != _hasPending) {
      _hasPending = hasPending;
      _goHovered = false;
      _goPressed = false;
      _applyMotionDuration();
      if (hasPending) {
        _intro.forward(from: 0);
      } else {
        _intro.reverse();
      }
    }
    _syncTick(hasPending);
    if (!hasPending && _intro.value == 0) return const SizedBox.shrink();

    final tokens = context.tokens;
    final remainingSec = (coord.remainingMs / 1000).ceil();
    return FadeTransition(
      opacity: CurvedAnimation(parent: _intro, curve: Curves.easeOut),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: tokens.surface1.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: tokens.chromeBorder.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconFor(pending?.kind ?? UndoActionKind.other),
                size: 14,
                color: tokens.textMuted,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  pending?.label ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textNormal,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (hasPending) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '·',
                    style: TextStyle(
                      color: tokens.textMuted.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _goHovered = true),
                  onExit: (_) => setState(() {
                    _goHovered = false;
                    _goPressed = false;
                  }),
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => _goPressed = true),
                    onTapCancel: () => setState(() => _goPressed = false),
                    onTapUp: (_) {
                      setState(() => _goPressed = false);
                      coord.flushNow();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _goHovered
                            ? tokens.accentBright.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 80),
                        scale: _goPressed ? 0.92 : 1.0,
                        child: _GoCountdown(
                          hovered: _goHovered,
                          remainingSec: remainingSec,
                          tokens: tokens,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              TextButton(
                onPressed: hasPending ? coord.cancel : null,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: tokens.accentBright,
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(UndoActionKind kind) {
    switch (kind) {
      case UndoActionKind.commit:
      case UndoActionKind.commitAndPush:
        return Icons.check_circle_outline;
      case UndoActionKind.discard:
      case UndoActionKind.branchDelete:
      case UndoActionKind.tagDelete:
        return Icons.delete_outline;
      case UndoActionKind.stashDrop:
        return Icons.inventory_2_outlined;
      case UndoActionKind.revert:
        return Icons.undo;
      case UndoActionKind.other:
        return Icons.schedule;
    }
  }
}

class _GoCountdown extends StatefulWidget {
  final bool hovered;
  final int remainingSec;
  final AppTokens tokens;

  const _GoCountdown({
    required this.hovered,
    required this.remainingSec,
    required this.tokens,
  });

  @override
  State<_GoCountdown> createState() => _GoCountdownState();
}

class _GoCountdownState extends State<_GoCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final text = widget.hovered ? 'go' : '${widget.remainingSec}s';
    if (widget.hovered) {
      return ThemeMorphText(
        text,
        style: TextStyle(
          color: t.accentBright,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final v = _pulse.value;
        final alpha = 0.45 + 0.55 * v;
        return ThemeMorphText(
          text,
          style: TextStyle(
            color: t.textMuted.withValues(alpha: alpha),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: AppFonts.mono,
          ),
        );
      },
    );
  }
}
