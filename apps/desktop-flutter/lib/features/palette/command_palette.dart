import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/repository_state.dart';
import '../../ui/design_primitives.dart';
import '../../ui/form_controls.dart';
import '../../ui/motion.dart';
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
          onHover: () => palette.hoverSelect(index),
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
        duration: context.motionRead(AppMotion.snap),
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
            loading: palette.isLoading,
            hintText: widget.elevated
                ? 'elevated — all actions'
                : 'search everything...',
          ),
          Expanded(
            child: palette.results.isEmpty && !palette.wickActive
                ? _EmptyState(query: palette.query)
                : _buildResultList(palette),
          ),
          if (palette.wickActive)
            _WickShelf(
              entries: palette.wickEntries,
              posture: palette.wickPosture,
              searching: palette.wickSearching,
              onFileSelected: widget.onFileSelected,
              onClose: widget.onClose,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

class _PaletteInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool loading;

  const _PaletteInput({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.hintText = 'search everything...',
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            onChanged: onChanged,
            cursorColor: t.accentBright,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              hintText: hintText,
              hintStyle: TextStyle(
                color: t.textMuted.withValues(alpha: 0.4),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        AnimatedContainer(
          duration: context.motion(AppMotion.fade),
          height: 0.5,
          color: loading
              ? t.accentBright.withValues(alpha: 0.5)
              : t.chromeBorder.withValues(alpha: 0.15),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Result row — heat-stripe design
// ---------------------------------------------------------------------------

class _PaletteResultRow extends StatefulWidget {
  final PaletteEntry entry;
  final bool isSelected;
  final double scoreRatio;
  final bool isConfirming;
  final bool isWarming;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _PaletteResultRow({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onHover,
    this.scoreRatio = 1.0,
    this.isConfirming = false,
    this.isWarming = false,
  });

  @override
  State<_PaletteResultRow> createState() => _PaletteResultRowState();
}

class _PaletteResultRowState extends State<_PaletteResultRow> {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final entry = widget.entry;
    final ratio = widget.scoreRatio;

    final stripeColor = _categoryColor(entry, t);
    final stripeAlpha = (0.15 + 0.85 * ratio).clamp(0.0, 1.0);
    final stripeWidth = ratio > 0.5 ? 2.5 : ratio > 0.2 ? 1.5 : 0.75;

    final hasUsageSheen = entry.provenance.any(
        (p) => p == 'freq' || p == 'recent' || p == 'prefix' || p == 'flow');
    final sheenAlpha = hasUsageSheen ? 0.035 : 0.0;

    final bgColor = widget.isWarming
        ? t.stateModified.withValues(alpha: 0.1)
        : widget.isConfirming
            ? t.danger.withValues(alpha: 0.12)
            : widget.isSelected
                ? t.surface1
                : sheenAlpha > 0
                    ? t.accentBright.withValues(alpha: sheenAlpha)
                    : Colors.transparent;

    final rightContext = entry.shortcutLabel;
    final sub = _subtitle(entry);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => widget.onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: bgColor,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: stripeWidth,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: stripeColor.withValues(alpha: stripeAlpha),
                    borderRadius: BorderRadius.circular(
                        context.surfaceShader.geometry.tinyRadius),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: _HighlightedLabel(
                                text: entry.label,
                                ranges: entry.matchRanges,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: t.textNormal,
                                  height: 1.25,
                                ),
                                highlightColor: t.accentBright,
                              ),
                            ),
                            if (entry.provenance.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  entry.provenance.join(' · '),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: t.textFaint.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (sub != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              sub,
                              style: TextStyle(
                                fontSize: 10,
                                color: t.textMuted,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (entry.actionType == PaletteActionType.toggle &&
                    entry.readBool != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 12),
                    child: Center(
                      child: AppCheckbox(
                        value: entry.readBool!(),
                        onChanged: (v) {
                          entry.writeBool?.call(v);
                          setState(() {});
                        },
                      ),
                    ),
                  )
                else if (rightContext != null &&
                    entry.actionType != PaletteActionType.toggle)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 12),
                    child: Center(
                      child: Text(
                        rightContext,
                        style: TextStyle(
                          fontSize: 10,
                          color: t.textFaint,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _categoryColor(PaletteEntry entry, AppTokens t) {
  if (entry.chipTone != null) {
    return switch (entry.chipTone!) {
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
  }
  return switch (entry.category) {
    PaletteCategory.command => t.hyperCore,
    PaletteCategory.action => t.hyperChromatic2,
    PaletteCategory.branch => t.accentBright,
    PaletteCategory.repo => t.hyperChromatic1,
    PaletteCategory.commit => t.hyperChromatic1,
    PaletteCategory.navigation => t.textMuted,
    PaletteCategory.setting => t.chromeAccent,
    PaletteCategory.file => t.stateModified,
    PaletteCategory.stash => t.hyperChromatic2,
    PaletteCategory.tag => t.eventStartTone,
  };
}

String? _subtitle(PaletteEntry entry) {
  final sub = entry.subtitle;
  if (sub == null || sub.isEmpty) return null;
  if (sub.contains(r'\') || sub.contains('/')) {
    final segments = sub.replaceAll(r'\', '/').split('/');
    if (segments.length > 3) {
      return '.../${segments.sublist(segments.length - 2).join('/')}';
    }
  }
  return sub;
}

// ---------------------------------------------------------------------------
// Highlighted label (match ranges)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Wick shelf (docked bottom)
// ---------------------------------------------------------------------------

class _WickShelf extends StatefulWidget {
  final List<WickUnit> entries;
  final WickPosture? posture;
  final bool searching;
  final void Function(String filePath) onFileSelected;
  final VoidCallback onClose;

  const _WickShelf({
    required this.entries,
    required this.posture,
    required this.searching,
    required this.onFileSelected,
    required this.onClose,
  });

  @override
  State<_WickShelf> createState() => _WickShelfState();
}

class _WickShelfState extends State<_WickShelf> {
  static const _prefKey = 'wick_shelf_expanded';
  static bool _cachedExpanded = false;
  static bool _prefLoaded = false;

  bool _expanded = _cachedExpanded;
  int _hoveredIndex = -1;

  double get _postureOpacity => switch (widget.posture) {
        WickPosture.decisive => 1.0,
        WickPosture.exploring => 0.7,
        WickPosture.reaching => 0.45,
        _ => 0.3,
      };

  @override
  void initState() {
    super.initState();
    if (!_prefLoaded) {
      _prefLoaded = true;
      SharedPreferences.getInstance().then((prefs) {
        final val = prefs.getBool(_prefKey) ?? false;
        _cachedExpanded = val;
        if (mounted && val != _expanded) setState(() => _expanded = val);
      });
    }
  }

  void _toggleExpanded() {
    if (widget.entries.isEmpty) return;
    setState(() => _expanded = !_expanded);
    _cachedExpanded = _expanded;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_prefKey, _expanded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final geo = context.surfaceShader.geometry;
    final units = widget.entries;
    final hasResults = units.isNotEmpty;
    final searching = widget.searching && !hasResults;
    final idle = !hasResults && !searching;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: idle
                ? t.chromeBorder.withValues(alpha: 0.3)
                : t.accentBright.withValues(alpha: _postureOpacity * 0.15),
            width: 0.5,
          ),
        ),
        color: t.surface0.withValues(alpha: idle ? 0.5 : 0.85),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildShelfHeader(t, units, idle: idle, searching: searching),
          AnimatedSize(
            duration: context.motion(AppMotion.fade),
            curve: AppMotion.fadeCurve,
            alignment: Alignment.topCenter,
            child: _expanded && hasResults
                ? _buildExpandedBody(t, units, geo)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfHeader(
    AppTokens t,
    List<WickUnit> units, {
    required bool idle,
    required bool searching,
  }) {
    if (idle) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          'wick',
          style: TextStyle(
            fontSize: 10,
            color: t.textFaint.withValues(alpha: 0.4),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    if (searching) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(
                strokeWidth: 1.2,
                color: t.accentBright.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'wick',
              style: TextStyle(
                fontSize: 10,
                color: t.textFaint,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final fileNames = units
        .take(4)
        .map((u) => u.fileName)
        .toSet()
        .join(' · ');
    final suffix = units.length > 4 ? ' …' : '';

    return InkWell(
      onTap: _toggleExpanded,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            Text(
              'wick',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: t.accentBright.withValues(alpha: _postureOpacity * 0.7),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${units.length}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: t.accentBright.withValues(alpha: _postureOpacity),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$fileNames$suffix',
                style: TextStyle(fontSize: 10, color: t.textFaint),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: context.motion(AppMotion.snap),
              curve: AppMotion.snapCurve,
              child: Icon(
                Icons.expand_more,
                size: 13,
                color: t.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedBody(
      AppTokens t, List<WickUnit> units, SurfaceMaterialGeometry geo) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < units.length && i < 8; i++)
          _buildResultRow(t, units[i], i, geo),
      ],
    );
  }

  Widget _buildResultRow(
      AppTokens t, WickUnit unit, int index, SurfaceMaterialGeometry geo) {
    final isHovered = index == _hoveredIndex;
    var snippet = unit.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    snippet = snippet.replaceFirst(RegExp(r'^\[path:[^\]]*\]\s*'), '');
    if (snippet.length > 80) snippet = '${snippet.substring(0, 80)}…';
    final isGhost = unit.reason.kind == 'neighborhood' ||
        unit.reason.kind == 'transport';
    final ghostAlpha = isGhost ? 0.45 : 1.0;
    final reasonLabel = isGhost ? 'coupled' : unit.reason.kind;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = -1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.onFileSelected(unit.filePath);
          widget.onClose();
        },
        child: Container(
          color: isHovered
              ? t.accentBright.withValues(alpha: 0.06)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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
                          fontWeight:
                              isGhost ? FontWeight.w400 : FontWeight.w600,
                          color: t.textNormal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          snippet,
                          style:
                              TextStyle(fontSize: 10, color: t.textFaint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(geo.badgeRadius),
                    border: isGhost
                        ? Border.all(
                            color:
                                t.accentBright.withValues(alpha: 0.15))
                        : null,
                    color: isGhost
                        ? Colors.transparent
                        : t.accentBright.withValues(
                            alpha: unit.reason.kind == 'direct'
                                ? 0.15
                                : 0.07),
                  ),
                  child: Text(
                    reasonLabel,
                    style: TextStyle(
                      fontSize: 8,
                      color: t.accentBright.withValues(
                        alpha:
                            unit.reason.kind == 'direct' ? 0.9 : 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
