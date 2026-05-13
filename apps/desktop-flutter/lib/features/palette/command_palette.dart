import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/repository_state.dart';
import '../../ui/design_primitives.dart';
import '../../ui/form_controls.dart';
import '../../ui/motion.dart';
import '../../ui/status_view.dart';
import '../../ui/tokens.dart';
import '../../backend/wick.dart' show WickPosture, WickUnit;
import 'palette_entry.dart';
import 'palette_state.dart';

class CommandPalette extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String hash) onCommitSelected;
  final void Function(int mode) onModeChanged;
  final void Function(String branchName) onBranchCheckout;
  final void Function(String filePath) onFileSelected;
  final void Function() onOpenXray;
  final void Function() onOpenSettings;
  final void Function() onRefresh;
  final void Function() onUndo;
  final void Function(String path) onRepoSwitch;
  final void Function(String path) onDeskSwitch;
  final void Function(String url) onOpenBrowser;
  final int currentMode;
  final bool elevated;

  const CommandPalette({
    super.key,
    required this.onClose,
    required this.onCommitSelected,
    required this.onModeChanged,
    required this.onBranchCheckout,
    required this.onFileSelected,
    required this.onOpenXray,
    required this.onOpenSettings,
    required this.onRefresh,
    required this.onUndo,
    required this.onRepoSwitch,
    required this.onDeskSwitch,
    required this.onOpenBrowser,
    required this.currentMode,
    this.elevated = false,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _itemKeys = <int, GlobalKey>{};
  late final PaletteState _palette;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _palette = context.read<PaletteState>();
    _palette.elevated = widget.elevated;
    _palette.open(
      context,
      (
        onModeChanged: widget.onModeChanged,
        onOpenXray: widget.onOpenXray,
        onOpenSettings: widget.onOpenSettings,
        onRefresh: widget.onRefresh,
        onUndo: widget.onUndo,
        onRepoSwitch: widget.onRepoSwitch,
        onDeskSwitch: widget.onDeskSwitch,
        onOpenBrowser: widget.onOpenBrowser,
      ),
    );
    _palette.updateMode(widget.currentMode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant CommandPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMode != widget.currentMode) {
      _palette.updateMode(widget.currentMode);
    }
  }

  @override
  void dispose() {
    _palette.close();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _closeAndRun([VoidCallback? after]) {
    if (_closed) return;
    _closed = true;
    widget.onClose();
    after?.call();
  }

  void _onChanged(String value) {
    final repo = context.read<RepositoryState>();
    _palette.setQuery(value, repoPath: repo.activePath);
  }

  void _activate(PaletteEntry entry) {
    if (_palette.needsWarm(entry)) return;
    if (_palette.needsConfirm(entry)) return;

    _palette.recordUsage(entry.id);

    if (entry.actionType == PaletteActionType.toggle) {
      if (entry.readBool != null && entry.writeBool != null) {
        entry.writeBool!(!entry.readBool!());
        setState(() {});
      }
      return;
    }

    if (entry.category == PaletteCategory.commit) {
      final hash = entry.refPath ?? entry.id.split('.').last;
      _closeAndRun(() => widget.onCommitSelected(hash));
      return;
    }

    if (entry.category == PaletteCategory.branch) {
      final name = entry.refPath ?? entry.id.split('.').last;
      _closeAndRun(() => widget.onBranchCheckout(name));
      return;
    }

    if (entry.category == PaletteCategory.file) {
      final path = entry.refPath ?? entry.id.split('.').last;
      _closeAndRun(() => widget.onFileSelected(path));
      return;
    }

    final exec = entry.onExecute;
    _closeAndRun(exec);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;

    // Arrows repeat (scrubbing), activation keys don't.
    if (key == LogicalKeyboardKey.arrowDown) {
      _palette.moveSelection(1);
      _ensureVisible(_palette.selectedIndex);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _palette.moveSelection(-1);
      _ensureVisible(_palette.selectedIndex);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) &&
        !isRepeat) {
      final selected = _palette.selected;
      if (selected != null) _activate(selected);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && !isRepeat) {
      _closeAndRun();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildResultList(PaletteState palette) {
    final results = palette.results;
    final maxScore =
        results.isNotEmpty ? results.first.score : 1.0;
    final confirmId =
        palette.hasPendingConfirm ? palette.selected?.id : null;
    final warmingId = palette.warmingEntryId;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final key = _itemKeys.putIfAbsent(index, () => GlobalKey());
        final entry = results[index];
        return _PaletteResultRow(
          key: key,
          entry: entry,
          isSelected: index == palette.selectedIndex,
          scoreRatio: maxScore > 0 ? entry.score / maxScore : 0,
          isConfirming: entry.id == confirmId,
          isWarming: entry.id == warmingId,
          onTap: () => _activate(entry),
        );
      },
    );
  }

  void _ensureVisible(int index) {
    final key = _itemKeys[index];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.3,
        duration: const Duration(milliseconds: 40),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final palette = context.watch<PaletteState>();

    return Focus(
      onKeyEvent: _onKeyEvent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.elevated)
            Container(
              height: 2,
              color: t.danger.withValues(alpha: 0.5),
            ),
          _PaletteInput(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            hintText: widget.elevated
                ? 'elevated — all actions'
                : 'search everything...',
          ),
          AnimatedOpacity(
            opacity: palette.isLoading ? 1 : 0,
            duration: context.motion(AppMotion.snap),
            child: TopProgressLine(color: t.accentBright),
          ),
          if (palette.hasWickResults)
            _WickSummarySection(
              entries: palette.wickEntries,
              posture: palette.wickPosture,
              onFileSelected: widget.onFileSelected,
              onClose: widget.onClose,
            ),
          Expanded(
            child: palette.results.isEmpty && !palette.hasWickResults
                ? _EmptyState(query: palette.query)
                : _buildResultList(palette),
          ),
        ],
      ),
    );
  }
}

class _PaletteInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String hintText;

  const _PaletteInput({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.hintText = 'search everything...',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: AppTextField(
        controller: controller,
        focusNode: focusNode,
        hintText: hintText,
        height: 36,
        fontSize: 13,
        autofocus: true,
        onChanged: onChanged,
      ),
    );
  }
}

class _PaletteResultRow extends StatefulWidget {
  final PaletteEntry entry;
  final bool isSelected;
  final double scoreRatio;
  final bool isConfirming;
  final bool isWarming;
  final VoidCallback onTap;

  const _PaletteResultRow({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.onTap,
    this.scoreRatio = 1.0,
    this.isConfirming = false,
    this.isWarming = false,
  });

  @override
  State<_PaletteResultRow> createState() => _PaletteResultRowState();
}

class _PaletteResultRowState extends State<_PaletteResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final entry = widget.entry;
    final isHighlighted = widget.isSelected || _hovered;
    final vPad = 3.0 + 3.0 * widget.scoreRatio;
    final bgColor = widget.isWarming
        ? t.stateModified.withValues(alpha: 0.12)
        : widget.isConfirming
            ? t.danger.withValues(alpha: 0.15)
            : isHighlighted
                ? t.surface1
                : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: vPad),
          decoration: BoxDecoration(color: bgColor),
          child: Row(
            children: [
              if (entry.chipStack.isNotEmpty)
                _ChipStack(
                  chips: entry.chipStack,
                  category: entry.category,
                  tone: entry.chipTone,
                )
              else
                _CategoryChip(
                  category: entry.category,
                  chipLabel: _resolveChipLabel(entry),
                  chipTone: entry.chipTone,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HighlightedLabel(
                      text: entry.label,
                      ranges: entry.matchRanges,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: t.textNormal,
                        height: 1.3,
                      ),
                      highlightColor: t.accentBright,
                    ),
                    if (entry.subtitle != null || entry.provenance.isNotEmpty)
                      Text.rich(
                        TextSpan(children: [
                          if (entry.subtitle != null)
                            TextSpan(text: entry.subtitle),
                          if (entry.subtitle != null &&
                              entry.provenance.isNotEmpty)
                            const TextSpan(text: ' · '),
                          if (entry.provenance.isNotEmpty)
                            TextSpan(
                              text: entry.provenance.join(' · '),
                              style: TextStyle(color: t.textFaint),
                            ),
                        ]),
                        style: TextStyle(
                          fontSize: 10,
                          color: t.textMuted,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (entry.actionType == PaletteActionType.toggle &&
                  entry.readBool != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: AppCheckbox(
                    value: entry.readBool!(),
                    onChanged: (v) {
                      entry.writeBool?.call(v);
                      setState(() {});
                    },
                  ),
                ),
              if (entry.shortcutLabel != null &&
                  entry.actionType != PaletteActionType.toggle)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    entry.shortcutLabel!,
                    style: TextStyle(
                      fontSize: 10,
                      color: t.textFaint,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipStack extends StatelessWidget {
  final List<String> chips;
  final PaletteCategory category;
  final ChipTone? tone;

  const _ChipStack({
    required this.chips,
    required this.category,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          _CategoryChip(
            category: category,
            chipLabel: chips[i],
            chipTone: i == 0 ? tone : null,
          ),
        ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final PaletteCategory category;
  final String? chipLabel;
  final ChipTone? chipTone;

  const _CategoryChip({
    required this.category,
    this.chipLabel,
    this.chipTone,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final (defaultLabel, defaultColor) = switch (category) {
      PaletteCategory.repo => ('REPO', t.hyperChromatic1),
      PaletteCategory.action => ('ACT', t.hyperChromatic2),
      PaletteCategory.command => ('CMD', t.hyperCore),
      PaletteCategory.navigation => ('NAV', t.textMuted),
      PaletteCategory.setting => ('SET', t.chromeAccent),
      PaletteCategory.branch => ('REF', t.hypercubePositive),
      PaletteCategory.commit => ('LOG', t.hyperChromatic1),
      PaletteCategory.file => ('FILE', t.stateModified),
      PaletteCategory.stash => ('STH', t.hyperChromatic2),
      PaletteCategory.tag => ('TAG', t.eventStartTone),
    };

    final label = chipLabel ?? defaultLabel;

    final color = chipTone != null
        ? _toneToColor(chipTone!, t)
        : _inferColorFromLabel(label, t) ?? defaultColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: color.withValues(alpha: 0.7),
          height: 1.4,
        ),
      ),
    );
  }
}

Color _toneToColor(ChipTone tone, AppTokens t) => switch (tone) {
      ChipTone.accent => t.accentBright,
      ChipTone.positive => t.hypercubePositive,
      ChipTone.negative => t.hypercubeNegative,
      ChipTone.chromatic1 => t.hyperChromatic1,
      ChipTone.chromatic2 => t.hyperChromatic2,
      ChipTone.core => t.hyperCore,
      ChipTone.muted => t.textMuted,
      ChipTone.faint => t.textFaint,
      ChipTone.staged => t.stateStaged,
      ChipTone.modified => t.stateModified,
      ChipTone.deleted => t.stateDeleted,
      ChipTone.conflicted => t.stateConflicted,
    };

Color? _inferColorFromLabel(String label, AppTokens t) => switch (label) {
      'ON' => t.hypercubePositive,
      'OFF' => t.textFaint,
      'HEAD' => t.accentBright,
      'GONE' => t.stateDeleted,
      'LOCAL' => t.textMuted,
      'REMOTE' => t.hyperChromatic1,
      'MAIN' => t.accentBright,
      'DET' => t.stateConflicted,
      'UNDO' => t.hypercubeNegative,
      'FORCE' => t.stateDeleted,
      'SYNC' => t.hyperCore,
      'PR' => t.hyperChromatic2,
      'DRAFT' => t.stateModified,
      'AI' => t.hyperChromatic1,
      'CLIP' => t.chromeAccent,
      'SYS' => t.chromeAccent,
      'TERM' => t.hyperCore,
      'GUI' => t.hyperChromatic2,
      'VER' => t.textMuted,
      'THM' => t.eventStartTone,
      'AN' => t.hyperChromatic1,
      'LW' => t.textMuted,
      'U' => t.stateConflicted,
      '?' => t.textFaint,
      'M' => t.stateModified,
      'A' => t.stateAdded,
      'D' => t.stateDeleted,
      'R' => t.stateModified,
      'TODAY' => t.accentBright,
      _ when label.endsWith('↑') => t.hypercubePositive,
      _ when label.endsWith('↓') => t.hypercubeNegative,
      _ when label.startsWith('#') => t.hyperChromatic2,
      _ when _isTimeChip(label) => t.textMuted,
      _ => null,
    };

bool _isTimeChip(String s) {
  if (s.length < 2) return false;
  final unit = s[s.length - 1];
  return (unit == 'd' || unit == 'w' || unit == 'm' || unit == 'y') &&
      int.tryParse(s.substring(0, s.length - 1)) != null;
}

class _HighlightedLabel extends StatelessWidget {
  final String text;
  final List<(int, int)>? ranges;
  final TextStyle style;
  final Color highlightColor;

  const _HighlightedLabel({
    required this.text,
    required this.ranges,
    required this.style,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    if (ranges == null || ranges!.isEmpty) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final spans = <TextSpan>[];
    int cursor = 0;
    for (final (start, end) in ranges!) {
      final s = start.clamp(0, text.length);
      final e = end.clamp(s, text.length);
      if (cursor < s) {
        spans.add(TextSpan(text: text.substring(cursor, s)));
      }
      if (s < e) {
        spans.add(TextSpan(
          text: text.substring(s, e),
          style: TextStyle(color: highlightColor, fontWeight: FontWeight.w700),
        ));
      }
      cursor = e;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

String? _resolveChipLabel(PaletteEntry entry) {
  if (entry.chipLabel != null) return entry.chipLabel;
  if (entry.actionType == PaletteActionType.toggle && entry.readBool != null) {
    return entry.readBool!() ? 'ON' : 'OFF';
  }
  return null;
}

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          query.isEmpty ? 'type to search' : 'no results',
          style: TextStyle(fontSize: 12, color: t.textFaint),
        ),
      ),
    );
  }
}

class _WickSummarySection extends StatefulWidget {
  final List<WickUnit> entries;
  final WickPosture? posture;
  final void Function(String filePath) onFileSelected;
  final VoidCallback onClose;

  const _WickSummarySection({
    required this.entries,
    required this.posture,
    required this.onFileSelected,
    required this.onClose,
  });

  @override
  State<_WickSummarySection> createState() => _WickSummarySectionState();
}

class _WickSummarySectionState extends State<_WickSummarySection> {
  bool _expanded = false;
  int _selectedIndex = -1;

  double get _postureOpacity => switch (widget.posture) {
        WickPosture.decisive => 1.0,
        WickPosture.exploring => 0.7,
        WickPosture.reaching => 0.45,
        _ => 0.3,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final units = widget.entries;
    if (units.isEmpty) return const SizedBox.shrink();

    final borderColor = t.accentBright.withValues(alpha: _postureOpacity * 0.4);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 1),
          borderRadius: BorderRadius.circular(6),
          color: t.surface0.withValues(alpha: 0.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(t, units),
            if (_expanded) ..._buildExpandedResults(t, units),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppTokens t, List<WickUnit> units) {
    final fileNames = units
        .take(4)
        .map((u) => u.fileName)
        .toSet()
        .join(' · ');
    final suffix = units.length > 4 ? ' · …' : '';
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Text(
              '${units.length} match${units.length == 1 ? '' : 'es'} in files',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: t.accentBright.withValues(alpha: _postureOpacity),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$fileNames$suffix',
                style: TextStyle(fontSize: 11, color: t.textFaint),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 14,
              color: t.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildExpandedResults(AppTokens t, List<WickUnit> units) {
    final isDecisive = widget.posture == WickPosture.decisive;
    final staggerMs = switch (widget.posture) {
      WickPosture.decisive => 0,
      WickPosture.exploring => 40,
      WickPosture.reaching => 80,
      _ => 60,
    };
    return [
      for (var i = 0; i < units.length && i < 8; i++)
        isDecisive
            ? _buildResultRow(t, units[i], i)
            : TweenAnimationBuilder<double>(
                key: ValueKey('wick-$i-${units[i].id}'),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 200 + staggerMs * i),
                curve: Curves.easeOut,
                builder: (_, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: _buildResultRow(t, units[i], i),
              ),
    ];
  }

  Widget _buildResultRow(AppTokens t, WickUnit unit, int index) {
    final isSelected = index == _selectedIndex;
    var snippet = unit.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Strip Wick's [path: ...] prefix — the filename is already shown.
    snippet = snippet.replaceFirst(RegExp(r'^\[path:[^\]]*\]\s*'), '');
    if (snippet.length > 80) snippet = '${snippet.substring(0, 80)}…';
    final isGhost = unit.reason.kind == 'neighborhood' ||
        unit.reason.kind == 'transport';
    final ghostAlpha = isGhost ? 0.45 : 1.0;
    final reasonLabel = isGhost ? 'coupled' : unit.reason.kind;
    return InkWell(
      onTap: () {
        widget.onFileSelected(unit.filePath);
        widget.onClose();
      },
      onHover: (hovering) {
        if (hovering) setState(() => _selectedIndex = index);
      },
      child: Container(
        color: isSelected ? t.surface1 : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Opacity(
          opacity: ghostAlpha,
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      unit.fileName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isGhost ? FontWeight.w400 : FontWeight.w600,
                        color: t.textNormal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        snippet,
                        style: TextStyle(fontSize: 10, color: t.textFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: isGhost
                      ? Border.all(
                          color: t.accentBright.withValues(alpha: 0.15))
                      : null,
                  color: isGhost
                      ? Colors.transparent
                      : t.accentBright.withValues(
                          alpha:
                              unit.reason.kind == 'direct' ? 0.15 : 0.07),
                ),
                child: Text(
                  reasonLabel,
                  style: TextStyle(
                    fontSize: 8,
                  color: t.accentBright.withValues(
                    alpha: unit.reason.kind == 'direct' ? 0.9 : 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
