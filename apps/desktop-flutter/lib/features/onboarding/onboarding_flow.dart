import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/brand_lockup.dart';
import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import 'onboarding_state.dart';
import 'steps/step_naming.dart';
import 'steps/step_repo.dart';
import 'steps/step_theme.dart';
import 'widgets/step_indicator.dart';

/// Root of the onboarding flow. Shares the MaterialApp, theme, and
/// providers with the workspace — themes changed mid-flow apply
/// instantly and survive the handoff into the app.
class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gradient = t.appGradientColors.length <= 2
        ? LinearGradient(
            begin: t.appGradientAlignments.first as Alignment,
            end: t.appGradientAlignments.last as Alignment,
            colors: t.appGradientColors,
          )
        : RadialGradient(
            center: Alignment.topLeft,
            radius: 1.4,
            colors: t.appGradientColors,
            stops: const [0.14, 0.44, 1.0],
          );

    return Scaffold(
      backgroundColor: t.bg0,
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: const SafeArea(child: _OnboardingChrome()),
      ),
    );
  }
}

class _OnboardingChrome extends StatelessWidget {
  const _OnboardingChrome();

  @override
  Widget build(BuildContext context) {
    final onboarding = context.watch<OnboardingState>();
    final transitionDuration = context.motion(AppMotion.fluid);

    return Stack(
      children: [
        const Positioned(
          left: 12,
          top: 12,
          child: BrandLockup(),
        ),
        Positioned.fill(
          child: Column(
            children: [
              const SizedBox(height: 56),
              StepIndicator(
                total: onboarding.totalSteps,
                current: onboarding.currentStep,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: transitionDuration,
                  switchInCurve: AppMotion.fluidCurve,
                  switchOutCurve: AppMotion.fluidCurve,
                  transitionBuilder: (child, animation) {
                    final dir = onboarding.direction;
                    final slide = Tween<Offset>(
                      begin: Offset(0.04 * dir, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(onboarding.currentStep),
                    child: _stepBody(onboarding.activeStep),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepBody(OnboardingStep step) {
    return switch (step) {
      NamingStep() => const NamingStepPage(),
      ThemeStep() => const ThemeStepPage(),
      RepoStep() => const RepoStepPage(),
    };
  }
}

// Each step renders its own Back/Primary row so it can gate enablement on
// step-local state without coordinating with a shared footer.

class OnboardingNavRow extends StatelessWidget {
  final VoidCallback? onPrimary;
  final String? primaryLabelOverride;
  final Widget? middle;
  /// Hide the primary button entirely. Step 3 uses this because its three
  /// "doors" are the primary action — a disabled "Let's go" in the corner
  /// would just be a dead trap tempting clicks.
  final bool showPrimary;

  const OnboardingNavRow({
    super.key,
    required this.onPrimary,
    this.primaryLabelOverride,
    this.middle,
    this.showPrimary = true,
  });

  @override
  Widget build(BuildContext context) {
    final onboarding = context.watch<OnboardingState>();
    return Row(
      children: [
        _BackButton(
          visible: onboarding.canGoBack,
          onTap: onboarding.back,
        ),
        const Spacer(),
        if (middle != null && showPrimary) ...[middle!, const SizedBox(width: 12)],
        if (middle != null && !showPrimary) middle!,
        if (showPrimary)
          OnboardingPrimaryButton(
            onTap: onPrimary,
            labelOverride: primaryLabelOverride,
          ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;

  const _BackButton({required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedOpacity(
      duration: context.motion(AppMotion.fade),
      opacity: visible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded,
                      size: 14, color: t.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    'Back',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingPrimaryButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String? labelOverride;

  const OnboardingPrimaryButton({
    super.key,
    required this.onTap,
    this.labelOverride,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onboarding = context.watch<OnboardingState>();
    final label =
        labelOverride ?? (onboarding.isLastStep ? "Let's go" : 'Continue');
    final enabled = onTap != null;
    final radius = _primaryButtonRadius(t);
    return MouseRegion(
      cursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: enabled
                ? t.accentBright.withValues(alpha: 0.14)
                : t.panelOverlay.withValues(alpha: 0.4),
            border: Border.all(
              color: enabled ? t.accentBright.withValues(alpha: 0.55) : t.chromeBorderSubtle,
            ),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: enabled ? t.textStrong : t.textFaint,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: enabled ? t.textStrong : t.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Matches the radius language the rest of the chrome uses — the theme's
/// declared geometry radius, soft-clamped so loud themes (halo at 12,
/// kirby at 0) still read as a real button.
double _primaryButtonRadius(AppTokens t) {
  final raw = themeDefinitionFor(t.id).shader.geometry.radius;
  return raw.clamp(4.0, 12.0).toDouble();
}

/// Tiny underlined "tertiary" link — e.g., "use defaults", "i'll do this later".
class OnboardingQuietLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const OnboardingQuietLink({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  State<OnboardingQuietLink> createState() => _OnboardingQuietLinkState();
}

class _OnboardingQuietLinkState extends State<OnboardingQuietLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = _hover ? t.textMuted : t.textFaint;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(
            widget.label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              decoration: TextDecoration.underline,
              decorationColor: color.withValues(alpha: 0.4),
              decorationThickness: 1,
            ),
          ),
        ),
      ),
    );
  }
}
