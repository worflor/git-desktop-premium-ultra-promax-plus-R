import 'package:flutter/material.dart';

import 'tokens.dart';

class AppInputShell extends StatelessWidget {
  final Widget child;
  final double height;
  final EdgeInsetsGeometry padding;
  final bool focused;
  final bool enabled;
  final Color? fillColor;
  final Color? borderColor;

  const AppInputShell({
    super.key,
    required this.child,
    this.height = 34,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.focused = false,
    this.enabled = true,
    this.fillColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius =
        themeDefinitionFor(t.id).shader.geometry.radius.clamp(0, 18).toDouble();
    final effectiveRadius = (radius * 0.75).clamp(0.0, 14.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      height: height,
      decoration: BoxDecoration(
        color: fillColor ?? t.inputBg,
        borderRadius: BorderRadius.circular(effectiveRadius),
        border: Border.all(
          color: (borderColor ?? (focused ? t.inputFocusBorder : t.inputBorder))
              .withValues(alpha: enabled ? 1 : 0.45),
        ),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? hintText;
  final double height;
  final double fontSize;
  final bool autofocus;
  final bool enabled;
  final bool mono;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TapRegionCallback? onTapOutside;
  final EdgeInsetsGeometry padding;
  final FocusNode? focusNode;

  const AppTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.height = 34,
    this.fontSize = 12,
    this.autofocus = false,
    this.enabled = true,
    this.mono = false,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.focusNode,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) {
      return;
    }
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppInputShell(
      height: widget.height,
      padding: widget.padding,
      focused: _focusNode.hasFocus,
      enabled: widget.enabled,
      child: Center(
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          textAlign: widget.textAlign,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          onTapOutside: widget.onTapOutside,
          cursorColor: t.accentBright,
          style: TextStyle(
            color: t.textStrong,
            fontSize: widget.fontSize,
            fontFamily: widget.mono ? 'JetBrains Mono' : null,
          ),
          decoration: InputDecoration.collapsed(
            hintText: widget.hintText,
            hintStyle: TextStyle(
              color: t.textMuted.withValues(alpha: 0.5),
              fontSize: widget.fontSize,
            ),
          ),
        ),
      ),
    );
  }
}

class AppDropdownField<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double height;
  final double fontSize;
  final bool isExpanded;
  final bool enabled;
  final FontWeight? fontWeight;
  final EdgeInsetsGeometry padding;
  final Color? menuColor;

  const AppDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.height = 34,
    this.fontSize = 12,
    this.isExpanded = true,
    this.enabled = true,
    this.fontWeight,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.menuColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppInputShell(
      height: height,
      padding: padding,
      enabled: enabled,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: menuColor ?? t.bg1,
          iconEnabledColor: t.textMuted,
          style: TextStyle(
            color: enabled ? t.textNormal : t.textMuted,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
          isExpanded: isExpanded,
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

class AppMultilineTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? hintText;
  final double minHeight;
  final double maxHeight;
  final double fontSize;
  final bool autofocus;
  final bool enabled;
  final bool mono;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry padding;

  const AppMultilineTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.minHeight = 96,
    this.maxHeight = 220,
    this.fontSize = 12,
    this.autofocus = false,
    this.enabled = true,
    this.mono = false,
    this.onChanged,
    this.focusNode,
    this.padding = const EdgeInsets.fromLTRB(10, 10, 10, 10),
  });

  @override
  State<AppMultilineTextField> createState() => _AppMultilineTextFieldState();
}

class _AppMultilineTextFieldState extends State<AppMultilineTextField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AppMultilineTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) {
      return;
    }
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppInputShell(
      height: widget.minHeight,
      padding: widget.padding,
      focused: _focusNode.hasFocus,
      enabled: widget.enabled,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: widget.minHeight - 20,
          maxHeight: widget.maxHeight,
        ),
        child: Scrollbar(
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            minLines: null,
            maxLines: null,
            expands: true,
            onChanged: widget.onChanged,
            cursorColor: t.accentBright,
            style: TextStyle(
              color: t.textStrong,
              fontSize: widget.fontSize,
              fontFamily: widget.mono ? 'JetBrains Mono' : null,
            ),
            decoration: InputDecoration.collapsed(
              hintText: widget.hintText,
              hintStyle: TextStyle(
                color: t.textMuted.withValues(alpha: 0.5),
                fontSize: widget.fontSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
