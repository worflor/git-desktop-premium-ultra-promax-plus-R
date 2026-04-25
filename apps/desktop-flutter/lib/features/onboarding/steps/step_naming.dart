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
    // Two-phase fade: question lands first, sentence follows. Total
    // budget honors the snappy default — 1100ms had the user looking
    // at static screens before the field appeared, which read as
    // "loading" rather than "presenting." 480ms total, scaled by the
    // motion preference (Duration.zero at rate=0 collapses to instant).
    _introController = AnimationController(
      vsync: this,
      duration: context.motionRead(const Duration(milliseconds: 480)),
    );
    _questionFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
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
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    height: 1.2,
                  ),
                  children: const [
                    TextSpan(text: 'what is '),
                    TextSpan(
                      text: 'this',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                    TextSpan(text: ' to you?'),
                  ],
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
            '\u2009, your personal Git Client.',
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

  // Measure with a trailing space so the cursor at end-of-text never
  // clips onto its own pixel column — this is the failure mode the
  // previous attempt had: last glyph rendered partially behind the
  // right edge even though raw text "fit".
  double _measure(BuildContext context, String text) {
    final ambient = DefaultTextStyle.of(context).style;
    final merged = ambient.merge(widget.style);
    final tp = TextPainter(
      text: TextSpan(text: '$text ', style: merged),
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

    // Total width = measured text (with trailing-space slack for cursor)
    //             + horizontal contentPadding (10 each side = 20)
    //             + cursor width (1.4)
    //             + a generous end-margin so wide monospace glyph cells
    //               don't visually kiss the border.
    // The end-margin was the bug — 28px was not enough for bold
    // monospace at fontSize 20; bumping to 44 covers every theme we
    // ship with headroom to spare.
    final width = (_measure(context, shown) + 44).clamp(110.0, 520.0);

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
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          border: InputBorder.none,
          counterText: '',
          hintText: 'Manifold',
        ),
      ),
    );
  }
}
