import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_identity.dart';
import '../../../ui/motion.dart';
import '../../../ui/tokens.dart';
import '../onboarding_flow.dart';
import '../onboarding_state.dart';

/// Step 1 — asks "what is this to you?" and reveals the inline sentence
/// "I am [___], your personal Git Client." with the bracketed name as an
/// editable field. Typing updates [AppIdentityState] live, so the window
/// title (and any other identity-consuming UI) tracks per keystroke.
class NamingStepPage extends StatefulWidget {
  const NamingStepPage({super.key});

  @override
  State<NamingStepPage> createState() => _NamingStepPageState();
}

class _NamingStepPageState extends State<NamingStepPage>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final Animation<double> _questionFade;
  late final Animation<double> _sentenceFade;
  late final TextEditingController _nameController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final reduceMotion = context.reduceMotionRead;
    _introController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: reduceMotion ? 0 : 1100),
    );
    _questionFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0, 0.45, curve: Curves.easeOutCubic),
    );
    _sentenceFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOutCubic),
    );

    final initialName = context.read<AppIdentityState>().identity.shortName;
    _nameController = TextEditingController(text: initialName);
    _focusNode = FocusNode();

    _introController.forward().then((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    context.read<AppIdentityState>().setShortName(value);
    setState(() {});
  }

  void _onContinue() {
    // Empty is fine — the identity layer normalises it back to "Manifold"
    // so Continue never blocks the user. The intent is a frictionless
    // floor, not a wrong-answer quiz.
    final raw = _nameController.text.trim();
    context.read<AppIdentityState>().setShortName(raw);
    context.read<OnboardingState>().next();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 24, 48, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          FadeTransition(
            opacity: _questionFade,
            child: Center(
              child: Text(
                'what is this to you?',
                style: TextStyle(
                  color: t.textStrong,
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  height: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 44),
          FadeTransition(
            opacity: _sentenceFade,
            child: Center(
              child: _InlineSentence(
                controller: _nameController,
                focusNode: _focusNode,
                onChanged: _onChanged,
                onSubmitted: (_) => _onContinue(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          FadeTransition(
            opacity: _sentenceFade,
            child: Center(
              child: Text(
                "this is what i'll go by. change it anytime.",
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 11.5,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          const Spacer(flex: 2),
          OnboardingNavRow(onPrimary: _onContinue),
        ],
      ),
    );
  }
}

class _InlineSentence extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _InlineSentence({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const sentenceStyle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
      height: 1.35,
    );

    return DefaultTextStyle(
      style: sentenceStyle.copyWith(color: t.textNormal),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.center,
        children: [
          Text('I am ', style: sentenceStyle.copyWith(color: t.textNormal)),
          _NameField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: sentenceStyle.copyWith(
              color: t.accentBright,
              fontWeight: FontWeight.w600,
            ),
            underlineColor: t.accentBright.withValues(alpha: 0.55),
          ),
          Text(
            ', your personal Git Client.',
            style: sentenceStyle.copyWith(color: t.textNormal),
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final TextStyle style;
  final Color underlineColor;

  const _NameField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.style,
    required this.underlineColor,
  });

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  double _measure(BuildContext context, String text) {
    // Merge the ambient DefaultTextStyle so the measurement picks up the
    // theme's font family (e.g. monospace themes like nightwalker/phosphor).
    // Without this the measured width is off by ~1 char and the field clips.
    final ambient = DefaultTextStyle.of(context).style;
    final merged = ambient.merge(widget.style);
    final tp = TextPainter(
      text: TextSpan(text: text, style: merged),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.controller.text;
    final shown = raw.isEmpty ? 'Manifold' : raw;
    // Width = measured text + horizontal contentPadding (8 each side) +
    // cursorWidth + sub-pixel rounding slack. Monospace fonts report
    // slightly tighter widths than they render, so the slack is a hair
    // generous on purpose.
    final width = (_measure(context, shown) + 28).clamp(80.0, 420.0);

    // AnimatedContainer tweens the width as the user types so the
    // sentence around the field reflows smoothly instead of snapping
    // per keystroke. Curve matches the rest of the onboarding motion.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: widget.underlineColor, width: 1.4),
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textAlign: TextAlign.center,
        cursorColor: widget.style.color,
        cursorWidth: 1.4,
        maxLength: 24,
        inputFormatters: [
          LengthLimitingTextInputFormatter(24),
          FilteringTextInputFormatter.deny(RegExp(r'[\n\r\t]')),
        ],
        style: widget.style,
        decoration: const InputDecoration(
          isDense: true,
          // Horizontal breathing room so the last glyph never visually
          // touches the border (especially on monospace themes where
          // the glyph cell is wider than the measured text width).
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          border: InputBorder.none,
          counterText: '',
          hintText: 'Manifold',
        ),
      ),
    );
  }
}
