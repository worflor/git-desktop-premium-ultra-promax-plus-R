import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/logos_git.dart';
import '../../ui/control_chrome.dart';
import '../../ui/design_primitives.dart';
import '../../ui/interaction_feedback.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

enum ConflictSide { ours, theirs, both, bothReversed, custom, unresolved }

class ConflictBlock {
  final int index;
  final String oursText;
  final String theirsText;
  final String? baseText;
  ConflictSide resolution;
  String? customText;

  // Logos coherence signal: positive favors ours, negative favors theirs.
  // Null when no engine is available.
  double? coherenceBias;

  ConflictBlock({
    required this.index,
    required this.oursText,
    required this.theirsText,
    this.baseText,
    this.resolution = ConflictSide.unresolved,
    this.customText,
  });

  bool get isResolved => resolution != ConflictSide.unresolved;

  /// Ambiguity heat [0..1]. 0 = engine is confident (cool), 1 = uncertain (hot).
  /// Derived from coherence bias strength and textual similarity.
  double get heat {
    if (oursText == theirsText) return 0;
    // Textual similarity — identical lines / max lines
    final oLines = oursText.split('\n');
    final tLines = theirsText.split('\n');
    final shared = oLines.toSet().intersection(tLines.toSet()).length;
    final maxLen = math.max(oLines.length, tLines.length);
    final similarity = maxLen > 0 ? shared / maxLen : 0.0;
    // Bias strength — strong bias = low heat
    final biasStrength = (coherenceBias ?? 0).abs().clamp(0.0, 0.3) / 0.3;
    // Combine: high similarity + strong bias = cool, low similarity + no bias = hot
    return ((1.0 - similarity) * 0.6 + (1.0 - biasStrength) * 0.4)
        .clamp(0.0, 1.0);
  }

  String get resolvedText {
    return switch (resolution) {
      ConflictSide.ours => oursText,
      ConflictSide.theirs => theirsText,
      ConflictSide.both => '$oursText\n$theirsText',
      ConflictSide.bothReversed => '$theirsText\n$oursText',
      ConflictSide.custom => customText ?? '',
      ConflictSide.unresolved => '',
    };
  }

  String get resolutionLabel {
    return switch (resolution) {
      ConflictSide.ours => 'yours',
      ConflictSide.theirs => 'theirs',
      ConflictSide.both => 'keep both',
      ConflictSide.bothReversed => 'keep both',
      ConflictSide.custom => 'custom',
      ConflictSide.unresolved => '',
    };
  }
}

class ConflictFile {
  final String path;
  final String fullText;
  final List<ConflictBlock> blocks;
  final List<String> segments;
  final String oursBranch;
  final String theirsBranch;

  // Logos enrichment
  String? lastReviewer;
  bool isRoutine;
  double? volatility;
  double? integrity;
  int? spectralCommunity;
  int? changedNeighborCount;
  int? totalNeighborCount;
  double? blastRadius;

  ConflictFile({
    required this.path,
    required this.fullText,
    required this.blocks,
    required this.segments,
    this.oursBranch = 'ours',
    this.theirsBranch = 'theirs',
    this.lastReviewer,
    this.isRoutine = false,
    this.volatility,
    this.integrity,
    this.spectralCommunity,
    this.changedNeighborCount,
    this.totalNeighborCount,
    this.blastRadius,
  });

  int get resolvedCount => blocks.where((b) => b.isResolved).length;
  bool get allResolved => blocks.every((b) => b.isResolved);

  String buildResult() {
    final buf = StringBuffer();
    for (var i = 0; i < segments.length; i++) {
      buf.write(segments[i]);
      if (i < blocks.length) {
        final resolved = blocks[i].resolvedText;
        buf.write(resolved);
        // The original conflict markers occupied their own lines, so
        // the resolved text needs a trailing newline to rejoin with the
        // next segment — unless the resolved text is empty or already
        // ends with a newline.
        if (resolved.isNotEmpty && !resolved.endsWith('\n')) {
          buf.write('\n');
        }
      }
    }
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// Conflict parser
// ---------------------------------------------------------------------------

ConflictFile parseConflictFile(
  String path,
  String content, {
  String oursBranch = 'ours',
  String theirsBranch = 'theirs',
}) {
  var detectedOurs = oursBranch;
  var detectedTheirs = theirsBranch;
  final lines = content.split('\n');
  final segments = <String>[];
  final blocks = <ConflictBlock>[];
  final clean = StringBuffer();
  final oursLines = <String>[];
  final theirsLines = <String>[];
  final baseLines = <String>[];
  var inOurs = false;
  var inTheirs = false;
  var inBase = false;
  var blockIdx = 0;
  var cleanNeedsSep = false;

  for (final line in lines) {
    if (line.startsWith('<<<<<<<')) {
      final seg = clean.toString();
      segments.add(seg.isNotEmpty && cleanNeedsSep ? '$seg\n' : seg);
      clean.clear();
      cleanNeedsSep = false;
      oursLines.clear();
      theirsLines.clear();
      baseLines.clear();
      inOurs = true;
      inBase = false;
      inTheirs = false;
      final marker = line.substring(7).trim();
      if (marker.isNotEmpty) detectedOurs = marker;
      continue;
    }
    if (line.startsWith('|||||||') && inOurs) {
      inOurs = false;
      inBase = true;
      continue;
    }
    if (line.startsWith('=======') && (inOurs || inBase)) {
      inOurs = false;
      inBase = false;
      inTheirs = true;
      continue;
    }
    if (line.startsWith('>>>>>>>') && inTheirs) {
      final marker = line.substring(7).trim();
      if (marker.isNotEmpty) detectedTheirs = marker;
      blocks.add(ConflictBlock(
        index: blockIdx++,
        oursText: oursLines.join('\n'),
        theirsText: theirsLines.join('\n'),
        baseText: baseLines.isEmpty ? null : baseLines.join('\n'),
      ));
      inTheirs = false;
      continue;
    }

    if (inOurs) {
      oursLines.add(line);
    } else if (inBase) {
      baseLines.add(line);
    } else if (inTheirs) {
      theirsLines.add(line);
    } else {
      if (cleanNeedsSep) clean.write('\n');
      clean.write(line);
      cleanNeedsSep = true;
    }
  }
  // If the file ended mid-conflict (truncated/corrupt marker), flush
  // the partial block so it's visible rather than silently dropped.
  if (inOurs || inBase || inTheirs) {
    blocks.add(ConflictBlock(
      index: blockIdx++,
      oursText: oursLines.join('\n'),
      theirsText: theirsLines.join('\n'),
      baseText: baseLines.isEmpty ? null : baseLines.join('\n'),
    ));
  }
  segments.add(clean.toString());

  return ConflictFile(
    path: path,
    fullText: content,
    blocks: blocks,
    segments: segments,
    oursBranch: detectedOurs,
    theirsBranch: detectedTheirs,
  );
}

// ---------------------------------------------------------------------------
// Logos enrichment — canonical, used by both production and test paths
// ---------------------------------------------------------------------------

void enrichConflictFileWithLogos(
    ConflictFile cf, LogosGit engine, Set<String> allChangedPaths) {
  final path = cf.path;
  final coupling = engine.stats.coupling;
  final stats = engine.stats;

  cf.lastReviewer = stats.reviewersByPath[path]?.firstOrNull;
  cf.isRoutine = (stats.ritualnessByPath[path] ?? 0.0) > 0.7;

  final vol = stats.volatility[path];
  if (vol != null && stats.volStddev > 0) {
    cf.volatility = ((vol - stats.volMean) / stats.volStddev).clamp(-2, 2);
  }
  cf.integrity = stats.integrityByPath[path];

  if (!coupling.hasJaccardRow(path)) return;

  final neighbors = coupling.topJaccardNeighbours(path, limit: 10);
  if (neighbors.isEmpty) return;
  cf.totalNeighborCount = neighbors.length;

  final changedNeighborPaths = neighbors
      .where((e) => allChangedPaths.contains(e.key))
      .map((e) => e.key)
      .toList();
  cf.changedNeighborCount = changedNeighborPaths.length;

  final pathId = engine.pathToId[path];
  if (pathId != null) {
    final basis = engine.spectralBasis();
    if (basis != null) {
      final labels =
          basis.spectralCommunityLabels(math.min(8, basis.k));
      if (pathId < labels.length) {
        cf.spectralCommunity = labels[pathId];
      }
      try {
        final field = basis.diffuse(
          Float64List(basis.n)..[pathId] = 1.0,
          1.0,
        );
        var reachSum = 0.0;
        for (var i = 0; i < field.length; i++) {
          if (i != pathId) reachSum += field[i];
        }
        cf.blastRadius = reachSum;
      } catch (_) {}
    }
  }

  if (changedNeighborPaths.isEmpty) return;

  final setCoherence =
      coupling.coherenceFor([path, ...changedNeighborPaths]);
  final baseCoherence = coupling.coherenceFor(
      [path, ...neighbors.take(5).map((e) => e.key)]);
  final coherenceDelta = setCoherence - baseCoherence;

  var hyperedgeHits = 0;
  var hyperedgeTotal = 0;
  final hypers = stats.hyperedgesByPath[path] ?? const [];
  for (final he in hypers) {
    hyperedgeTotal++;
    final otherPaths = he.paths.where((p) => p != path);
    if (otherPaths.any((p) => allChangedPaths.contains(p))) {
      hyperedgeHits++;
    }
  }
  final hyperedgeBoost = hyperedgeTotal > 0
      ? (hyperedgeHits / hyperedgeTotal) * 0.1
      : 0.0;

  final centralityMap = coupling.jaccardCentralityMap();
  final centrality = centralityMap[path] ?? 0.0;
  final maxCentrality =
      centralityMap.values.fold<double>(0, (m, v) => v > m ? v : m);
  final centralityWeight =
      maxCentrality > 0 ? centrality / maxCentrality : 0.0;

  final volDampen = vol != null && stats.volStddev > 0
      ? 1.0 -
          ((vol - stats.volMean) / stats.volStddev).clamp(0.0, 1.0) * 0.3
      : 1.0;

  final rawBias = (coherenceDelta + hyperedgeBoost) *
      2.5 *
      (0.3 + 0.7 * centralityWeight) *
      volDampen;

  for (final block in cf.blocks) {
    block.coherenceBias = rawBias;
  }
}

// ---------------------------------------------------------------------------
// Line diff — marks which lines are unique to each side
// ---------------------------------------------------------------------------

Set<int> _uniqueLines(List<String> mine, List<String> other) {
  final otherSet = other.toSet();
  final unique = <int>{};
  for (var i = 0; i < mine.length; i++) {
    if (!otherSet.contains(mine[i])) unique.add(i);
  }
  return unique;
}

// ---------------------------------------------------------------------------
// Merge conflict editor
// ---------------------------------------------------------------------------

class MergeConflictEditor extends StatefulWidget {
  final ConflictFile file;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback? onResolutionChanged;
  final bool allFilesResolved;
  final double extraTopPadding;

  const MergeConflictEditor({
    super.key,
    required this.file,
    required this.onComplete,
    required this.onCancel,
    this.onResolutionChanged,
    this.allFilesResolved = false,
    this.extraTopPadding = 0,
  });

  @override
  State<MergeConflictEditor> createState() => _MergeConflictEditorState();
}

class _MergeConflictEditorState extends State<MergeConflictEditor> {
  late int _focusIndex;
  late List<TextEditingController> _customControllers;
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  bool _showBase = false;
  final _itemKeys = <int, GlobalKey>{};
  int? _editingIndex;
  int _trustLevel = 1;

  ConflictFile get _file => widget.file;
  List<ConflictBlock> get _blocks => _file.blocks;

  static const _trustLabels = ['manual', 'safe', 'guided', 'assisted', 'full'];

  @override
  void initState() {
    super.initState();
    _focusIndex = _blocks.indexWhere((b) => !b.isResolved);
    if (_focusIndex < 0) _focusIndex = 0;
    _customControllers = _blocks
        .map((b) => TextEditingController(text: b.customText ?? b.oursText))
        .toList();
    for (var i = 0; i < _blocks.length; i++) {
      _itemKeys[i] = GlobalKey();
    }
    _applyTrust();
  }

  void _applyTrust() {
    for (final block in _blocks) {
      if (block.isResolved) continue;
      final autoSide = _trustDecision(block);
      if (autoSide != null) {
        block.resolution = autoSide;
        block.customText = '__auto__';
      }
    }
  }

  void _setTrust(int level) {
    setState(() {
      for (final block in _blocks) {
        if (block.isResolved && block.customText == '__auto__') {
          block.resolution = ConflictSide.unresolved;
          block.customText = null;
        }
      }
      _trustLevel = level;
      _applyTrustTagged();
    });
    widget.onResolutionChanged?.call();
  }

  void _applyTrustTagged() {
    for (final block in _blocks) {
      if (block.isResolved) continue;
      final autoSide = _trustDecision(block);
      if (autoSide != null) {
        block.resolution = autoSide;
        block.customText = '__auto__';
      }
    }
  }

  ConflictSide? _trustDecision(ConflictBlock block) {
    // Level 0: manual — never auto-resolve
    if (_trustLevel <= 0) return null;
    // Level 1: safe — byte-identical only
    if (block.oursText == block.theirsText) return ConflictSide.ours;
    if (_trustLevel <= 1) return null;
    // Level 2: guided — also whitespace-identical
    if (block.oursText.trim() == block.theirsText.trim()) {
      return ConflictSide.ours;
    }
    if (_trustLevel <= 2) return null;
    // Level 3: assisted — one side empty (pure add), or strict superset
    if (block.theirsText.trim().isEmpty) return ConflictSide.ours;
    if (block.oursText.trim().isEmpty) return ConflictSide.theirs;
    if (block.oursText.contains(block.theirsText)) return ConflictSide.ours;
    if (block.theirsText.contains(block.oursText)) return ConflictSide.theirs;
    if (_trustLevel <= 3) return null;
    // Level 4: full — Logos coherence makes the call on small diffs
    final bias = block.coherenceBias;
    if (bias != null && bias.abs() > 0.08) {
      final oursLines = block.oursText.split('\n').length;
      final theirsLines = block.theirsText.split('\n').length;
      if (oursLines <= 8 && theirsLines <= 8) {
        return bias > 0 ? ConflictSide.ours : ConflictSide.theirs;
      }
    }
    return null;
  }

  void _startEditing(int i) {
    final block = _blocks[i];
    final bias = block.coherenceBias ?? 0;
    _customControllers[i].text =
        bias < -0.05 ? block.theirsText : block.oursText;
    setState(() => _editingIndex = i);
  }

  void _saveEditing(int i) {
    _blocks[i].customText = _customControllers[i].text;
    setState(() {
      _blocks[i].resolution = ConflictSide.custom;
      _editingIndex = null;
    });
    _advanceFocus();
    widget.onResolutionChanged?.call();
  }

  void _cancelEditing() {
    setState(() => _editingIndex = null);
  }

  @override
  void dispose() {
    for (final c in _customControllers) {
      c.dispose();
    }
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToFocused() {
    final key = _itemKeys[_focusIndex];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: 0.15);
    }
  }

  void _resolve(int i, ConflictSide side) {
    setState(() {
      _blocks[i].resolution = side;
      if (side == ConflictSide.custom) {
        _blocks[i].customText = _customControllers[i].text;
      }
    });
    widget.onResolutionChanged?.call();
  }

  void _unresolve(int i) {
    setState(() => _blocks[i].resolution = ConflictSide.unresolved);
    widget.onResolutionChanged?.call();
  }

  void _navigateTo(int i, {bool scroll = true}) {
    setState(() => _focusIndex = i);
    if (scroll) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToFocused());
    }
  }

  void _advanceFocus() {
    for (var i = _focusIndex + 1; i < _blocks.length; i++) {
      if (!_blocks[i].isResolved) {
        setState(() => _focusIndex = i);
        return;
      }
    }
    for (var i = 0; i < _focusIndex; i++) {
      if (!_blocks[i].isResolved) {
        setState(() => _focusIndex = i);
        return;
      }
    }
    setState(() {});
  }

  void _resolveEasy() {
    setState(() {
      for (final block in _blocks) {
        if (block.isResolved) continue;
        if (block.heat < 0.3) {
          final bias = block.coherenceBias ?? 0;
          block.resolution =
              bias < -0.05 ? ConflictSide.theirs : ConflictSide.ours;
          block.customText = '__easy__';
        }
      }
    });
    widget.onResolutionChanged?.call();
  }

  void _nextUnresolved() {
    for (var i = _focusIndex + 1; i < _blocks.length; i++) {
      if (!_blocks[i].isResolved) return _navigateTo(i);
    }
    for (var i = 0; i < _focusIndex; i++) {
      if (!_blocks[i].isResolved) return _navigateTo(i);
    }
  }

  void _prevUnresolved() {
    for (var i = _focusIndex - 1; i >= 0; i--) {
      if (!_blocks[i].isResolved) return _navigateTo(i);
    }
    for (var i = _blocks.length - 1; i > _focusIndex; i--) {
      if (!_blocks[i].isResolved) return _navigateTo(i);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_editingIndex != null) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (event is KeyDownEvent &&
          !shift &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
           event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
        _saveEditing(_editingIndex!);
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEditing();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Navigation: arrow down/right or N = next, arrow up/left or P = prev
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyN) {
      _nextUnresolved();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyP) {
      _prevUnresolved();
      return KeyEventResult.handled;
    }
    // Accept: Enter/Space = accept the Logos-favored side (or yours if neutral)
    // Shift flips to the other side.
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      final bias = _blocks[_focusIndex].coherenceBias ?? 0;
      final defaultSide =
          bias < -0.05 ? ConflictSide.theirs : ConflictSide.ours;
      final flipped = defaultSide == ConflictSide.ours
          ? ConflictSide.theirs
          : ConflictSide.ours;
      _resolve(_focusIndex, shift ? flipped : defaultSide);
      _advanceFocus();
      return KeyEventResult.handled;
    }
    // Letter shortcuts
    if (key == LogicalKeyboardKey.keyT) {
      _resolve(_focusIndex, ConflictSide.theirs);
      _advanceFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyY) {
      _resolve(_focusIndex, ConflictSide.ours);
      _advanceFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      _resolve(_focusIndex, ConflictSide.both);
      _advanceFocus();
      return KeyEventResult.handled;
    }
    // Undo: Escape or Ctrl+Z
    if (key == LogicalKeyboardKey.escape ||
        (ctrl && key == LogicalKeyboardKey.keyZ)) {
      _unresolve(_focusIndex);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final resolved = _file.resolvedCount;
    final total = _blocks.length;
    final allDone = _file.allResolved;
    final oursColor = t.stateAdded;
    final theirsColor = t.accentBright;
    final canComplete = widget.allFilesResolved && allDone;
    final nextFileLabel = allDone && !widget.allFilesResolved;

    // Build the interleaved file view: segment, conflict, segment, ...
    // Continuous line numbers track through the whole file from the
    // "ours" perspective so the user can reference real positions.
    var lineNum = 1;
    final fileChildren = <Widget>[];
    final contextStyle = TextStyle(
      color: t.textMuted.withValues(alpha: 0.6),
      fontSize: 11,
      fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
      height: 1.55,
    );
    final gutterStyle = TextStyle(
      color: t.textFaint.withValues(alpha: 0.25),
      fontSize: 10,
      fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
      height: 1.55,
    );

    for (var i = 0; i < _file.segments.length; i++) {
      // Context segment
      final seg = _file.segments[i];
      if (seg.isNotEmpty) {
        final segLines = seg.split('\n');
        // Trim trailing empty line from writeln
        final trimmed = segLines.last.isEmpty && segLines.length > 1
            ? segLines.sublist(0, segLines.length - 1)
            : segLines;
        for (final line in trimmed) {
          final ln = lineNum++;
          fileChildren.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text('$ln', textAlign: TextAlign.right,
                    style: gutterStyle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(line.isEmpty ? ' ' : line,
                    style: contextStyle),
              ),
            ],
          ));
        }
      }

      // Conflict block (if there is one after this segment)
      if (i < _blocks.length) {
        final block = _blocks[i];
        final isFocused = i == _focusIndex;
        final oursLines = block.oursText.split('\n');
        // Count ours lines for line numbering
        final blockStartLine = lineNum;
        lineNum += oursLines.length;

        fileChildren.add(
          _InlineConflictRegion(
            key: _itemKeys[i],
            block: block,
            index: i,
            total: total,
            focused: isFocused,
            showBase: _showBase,
            oursColor: oursColor,
            theirsColor: theirsColor,
            startLine: blockStartLine,
            customController: _customControllers[i],
            editing: _editingIndex == i,
            autoResolved: block.customText == '__auto__',
            onTap: () => _navigateTo(i, scroll: false),
            onResolve: (side) {
              _resolve(i, side);
              _advanceFocus();
            },
            onUnresolve: () => _unresolve(i),
            onStartEdit: () => _startEditing(i),
            onSaveEdit: () => _saveEditing(i),
            onCancelEdit: _cancelEditing,
          ),
        );
      }
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Column(children: [
        Expanded(
          child: Stack(children: [
            ListView(
              controller: _scrollCtrl,
              padding: EdgeInsets.fromLTRB(
                  0, 52 + widget.extraTopPadding, 0, 40),
              children: fileChildren,
            ),
            Positioned(
              left: 10,
              right: 10,
              top: 6 + widget.extraTopPadding,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: t.bg1.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(context.surfaceShader.geometry.cardRadius),
                  border: Border.all(
                      color: t.chromeBorder.withValues(alpha: 0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(children: [
                  _BranchPill(
                      label: _file.oursBranch, color: oursColor),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.compare_arrows,
                        size: 10, color: t.textFaint),
                  ),
                  _BranchPill(
                      label: _file.theirsBranch, color: theirsColor),
                  const SizedBox(width: 8),
                  // Inline minimap
                  Expanded(
                    child: _ConflictMinimap(
                      blocks: _blocks,
                      focusIndex: _focusIndex,
                      oursColor: oursColor,
                      theirsColor: theirsColor,
                      onTap: _navigateTo,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: allDone ? null : _resolveEasy,
                    child: MouseRegion(
                      cursor: allDone
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: Tooltip(
                        message: allDone
                            ? 'all resolved'
                            : 'resolve easy conflicts',
                        waitDuration:
                            const Duration(milliseconds: 400),
                        child: Text(
                          '$resolved/$total',
                          style: TextStyle(
                            color: allDone
                                ? oursColor
                                : t.stateConflicted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                            decoration: allDone
                                ? TextDecoration.none
                                : TextDecoration.underline,
                            decorationColor: t.stateConflicted
                                .withValues(alpha: 0.3),
                            decorationStyle:
                                TextDecorationStyle.dotted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _HeaderChip(
                    label: 'base',
                    active: _showBase,
                    onTap: () =>
                        setState(() => _showBase = !_showBase),
                  ),
                  const SizedBox(width: 3),
                  _TrustChip(
                    level: _trustLevel,
                    labels: _trustLabels,
                    onChanged: _setTrust,
                  ),
                  const SizedBox(width: 3),
                  ChromeButton(
                    onTap: widget.onCancel,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    borderRadius: BorderRadius.circular(context.surfaceShader.geometry.pillRadius),
                    chromeBuilder:
                        ({required hovered, required pressed}) =>
                            ghostButtonChrome(t,
                                hovered: hovered,
                                pressed: pressed,
                                enabled: true,
                                baseBorderColor: t.chromeBorder
                                    .withValues(alpha: 0.2)),
                    child: Text('cancel',
                        style: TextStyle(
                            color: t.textMuted,
                            fontSize: 9.5,
                            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
                  ),
                  const SizedBox(width: 3),
                  ChromeButton(
                    onTap: canComplete
                        ? widget.onComplete
                        : nextFileLabel
                            ? widget.onComplete
                            : null,
                    enabled: canComplete || nextFileLabel,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    borderRadius: BorderRadius.circular(context.surfaceShader.geometry.pillRadius),
                    chromeBuilder:
                        ({required hovered, required pressed}) =>
                            ghostButtonChrome(t,
                                hovered: hovered,
                                pressed: pressed,
                                enabled:
                                    canComplete || nextFileLabel,
                                baseBorderColor: canComplete
                                    ? oursColor
                                    : nextFileLabel
                                        ? t.accentBright
                                        : t.chromeBorder.withValues(
                                            alpha: 0.1)),
                    child: Text(
                      canComplete
                          ? 'complete'
                          : nextFileLabel
                              ? 'next file'
                              : '…',
                      style: TextStyle(
                        color: canComplete
                            ? oursColor
                            : nextFileLabel
                                ? t.accentBright
                                : t.textFaint,
                        fontSize: 9.5,
                        fontWeight:
                            (canComplete || nextFileLabel)
                                ? FontWeight.w600
                                : FontWeight.w400,
                        fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        // Keyboard hints
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            _KeyHint('Enter', 'accept', oursColor),
            _KeyHint('⇧Enter', 'other', theirsColor),
            _KeyHint('B', 'both', t.textMuted),
            const SizedBox(width: 6),
            Container(width: 1, height: 10,
                color: t.chromeBorder.withValues(alpha: 0.15)),
            const SizedBox(width: 6),
            _KeyHint('↑↓', 'navigate', t.textMuted),
            _KeyHint('⌘Z', 'undo', t.textMuted),
          ]),
        ),
      ]),
    );
  }
}

class _KeyHint extends StatelessWidget {
  final String shortcut;
  final String label;
  final Color accent;
  const _KeyHint(this.shortcut, this.label, this.accent);
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final geo = context.surfaceShader.geometry;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(geo.tinyRadius),
            border: Border.all(
                color: t.chromeBorder.withValues(alpha: 0.25)),
          ),
          child: Text(shortcut,
              style: TextStyle(
                color: accent,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
              )),
      ),
      const SizedBox(width: 3),
      Text(label,
          style: TextStyle(
            color: t.textFaint,
            fontSize: 9,
            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
          )),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Conflict minimap — shows all blocks as small ticks
// ---------------------------------------------------------------------------

class _ConflictMinimap extends StatelessWidget {
  final List<ConflictBlock> blocks;
  final int focusIndex;
  final Color oursColor;
  final Color theirsColor;
  final ValueChanged<int> onTap;

  const _ConflictMinimap({
    required this.blocks,
    required this.focusIndex,
    required this.oursColor,
    required this.theirsColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: 8,
      child: Row(
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(context.surfaceShader.geometry.tinyRadius),
                      color: blocks[i].isResolved
                          ? oursColor.withValues(alpha: 0.35)
                          : Color.lerp(t.chromeAccent, t.stateConflicted,
                                  blocks[i].heat)!
                              .withValues(
                                  alpha: i == focusIndex
                                      ? 0.6
                                      : 0.15 + blocks[i].heat * 0.2),
                      border: i == focusIndex
                          ? Border.all(
                              color: t.accentBright.withValues(alpha: 0.5),
                              width: 1.5)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conflict card — the main per-block UI
// ---------------------------------------------------------------------------

class _InlineConflictRegion extends StatelessWidget {
  final ConflictBlock block;
  final int index;
  final int total;
  final bool focused;
  final bool showBase;
  final Color oursColor;
  final Color theirsColor;
  final int startLine;
  final TextEditingController customController;
  final bool editing;
  final bool autoResolved;
  final VoidCallback onTap;
  final ValueChanged<ConflictSide> onResolve;
  final VoidCallback onUnresolve;
  final VoidCallback onStartEdit;
  final VoidCallback onSaveEdit;
  final VoidCallback onCancelEdit;

  const _InlineConflictRegion({
    super.key,
    required this.block,
    required this.index,
    required this.total,
    required this.focused,
    required this.showBase,
    required this.oursColor,
    required this.theirsColor,
    required this.startLine,
    required this.customController,
    this.editing = false,
    this.autoResolved = false,
    required this.onTap,
    required this.onResolve,
    required this.onUnresolve,
    required this.onStartEdit,
    required this.onSaveEdit,
    required this.onCancelEdit,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final resolved = block.isResolved;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: focused
                  ? t.accentBright.withValues(alpha: 0.6)
                  : resolved
                      ? oursColor.withValues(alpha: 0.3)
                      : Color.lerp(t.chromeAccent, t.stateConflicted,
                              block.heat)!
                          .withValues(alpha: 0.3 + block.heat * 0.25),
              width: 3,
            ),
          ),
          color: resolved
              ? oursColor.withValues(alpha: 0.02)
              : focused
                  ? Color.lerp(t.chromeAccent, t.stateConflicted,
                          block.heat)!
                      .withValues(alpha: 0.02 + block.heat * 0.02)
                  : null,
        ),
        child: editing
            ? _editingInline(context, t)
            : resolved && !focused
                ? _resolvedInline(t)
                : _unresolvedInline(t),
      ),
    );
  }

  Widget _editingInline(BuildContext context, AppTokens t) {
    final geo = context.surfaceShader.geometry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(44, 4, 8, 4),
          child: TextField(
            controller: customController,
            maxLines: null,
            autofocus: true,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 11,
              fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
              height: 1.55,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.all(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(geo.badgeRadius),
                borderSide: BorderSide(
                    color: t.accentBright.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(geo.badgeRadius),
                borderSide: BorderSide(
                    color: t.accentBright.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 0, 8, 4),
          child: Row(children: [
            _ActionChip(
              label: 'save',
              color: oursColor,
              onTap: onSaveEdit,
            ),
            const SizedBox(width: 4),
            _ActionChip(
              label: 'cancel',
              color: t.textMuted,
              onTap: onCancelEdit,
            ),
          ]),
        ),
      ],
    );
  }

  Widget _resolvedInline(AppTokens t) {
    final lines = block.resolvedText.split('\n');
    final label = autoResolved ? 'auto' : 'undo';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                    i == 0 ? '✓' : '${startLine + i}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: i == 0
                          ? oursColor.withValues(alpha: 0.5)
                          : oursColor.withValues(alpha: 0.25),
                      fontSize: 10,
                      fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                      height: 1.55,
                    )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(lines[i].isEmpty ? ' ' : lines[i],
                    style: TextStyle(
                      color: t.textNormal,
                      fontSize: 11,
                      fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                      height: 1.55,
                    )),
              ),
              if (i == 0)
                GestureDetector(
                  onTap: onUnresolve,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(label,
                          style: TextStyle(
                            color: autoResolved
                                ? t.chromeAccent.withValues(alpha: 0.5)
                                : t.textFaint.withValues(alpha: 0.4),
                            fontSize: 9,
                            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                          )),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _unresolvedInline(AppTokens t) {
    final oursLinesRaw = block.oursText.split('\n');
    final theirsLinesRaw = block.theirsText.split('\n');
    final maxLen = math.max(oursLinesRaw.length, theirsLinesRaw.length);
    final oursLines = [
      ...oursLinesRaw,
      for (var i = oursLinesRaw.length; i < maxLen; i++) '',
    ];
    final theirsLines = [
      ...theirsLinesRaw,
      for (var i = theirsLinesRaw.length; i < maxLen; i++) '',
    ];
    final oursUnique = _uniqueLines(oursLinesRaw, theirsLinesRaw);
    final theirsUnique = _uniqueLines(theirsLinesRaw, oursLinesRaw);
    final hasBias = block.coherenceBias != null &&
        block.coherenceBias!.abs() > 0.05;
    final biasOurs = (block.coherenceBias ?? 0) > 0.05;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _InlineSide(
                  color: oursColor,
                  lines: oursLines,
                  startLine: startLine,
                  showLineNumbers: true,
                  highlightedLines: oursUnique,
                  active: block.resolution == ConflictSide.ours,
                  favored: hasBias && biasOurs,
                  onAccept: () => onResolve(ConflictSide.ours),
                ),
              ),
              Container(width: 1,
                  color: t.chromeBorder.withValues(alpha: 0.08)),
              Expanded(
                child: _InlineSide(
                  color: theirsColor,
                  lines: theirsLines,
                  startLine: 0,
                  showLineNumbers: false,
                  highlightedLines: theirsUnique,
                  active: block.resolution == ConflictSide.theirs,
                  favored: hasBias && !biasOurs,
                  onAccept: () => onResolve(ConflictSide.theirs),
                ),
              ),
            ],
          ),
        ),
        if (showBase && block.baseText != null)
          _BasePanel(text: block.baseText!),
        if (!block.isResolved)
          _InlineActionPill(
            focused: focused,
            onBoth: () => onResolve(ConflictSide.both),
            onBothReversed: () => onResolve(ConflictSide.bothReversed),
            onEdit: onStartEdit,
          ),
        if (block.isResolved)
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 2, 8, 2),
            child: Row(children: [
              Icon(Icons.check, size: 10,
                  color: oursColor.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text(block.resolutionLabel,
                  style: TextStyle(
                    color: oursColor.withValues(alpha: 0.5),
                    fontSize: 9,
                    fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                  )),
              const Spacer(),
              GestureDetector(
                onTap: onUnresolve,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text('undo',
                      style: TextStyle(
                        color: t.textFaint.withValues(alpha: 0.4),
                        fontSize: 9,
                        fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                      )),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

class _InlineActionPill extends StatefulWidget {
  final bool focused;
  final VoidCallback onBoth;
  final VoidCallback onBothReversed;
  final VoidCallback onEdit;

  const _InlineActionPill({
    required this.focused,
    required this.onBoth,
    required this.onBothReversed,
    required this.onEdit,
  });

  @override
  State<_InlineActionPill> createState() => _InlineActionPillState();
}

class _InlineActionPillState extends State<_InlineActionPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final visible = _hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: visible ? 1.0 : 0.25,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionChip(
                    label: 'keep both',
                    color: t.textMuted,
                    onTap: widget.onBoth),
                const SizedBox(width: 3),
                _ActionChip(
                    label: 'edit',
                    color: t.chromeAccent,
                    onTap: widget.onEdit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineSide extends StatelessWidget {
  final Color color;
  final List<String> lines;
  final int startLine;
  final bool showLineNumbers;
  final Set<int> highlightedLines;
  final bool active;
  final bool favored;
  final VoidCallback onAccept;

  const _InlineSide({
    required this.color,
    required this.lines,
    required this.startLine,
    this.showLineNumbers = true,
    required this.highlightedLines,
    required this.active,
    this.favored = false,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InteractionFeedback(
      onTap: onAccept,
      borderRadius: BorderRadius.zero,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
                color: color.withValues(alpha: active ? 0.5 : 0.15),
                width: 2),
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
            for (var i = 0; i < lines.length; i++)
              Container(
                color: highlightedLines.contains(i)
                    ? color.withValues(alpha: 0.05)
                    : active
                        ? color.withValues(alpha: 0.02)
                        : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showLineNumbers)
                      SizedBox(
                        width: 30,
                        child: Text('${startLine + i}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: highlightedLines.contains(i)
                                  ? color.withValues(alpha: 0.3)
                                  : t.textFaint.withValues(alpha: 0.2),
                              fontSize: 10,
                              fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                              height: 1.55,
                            )),
                      )
                    else
                      const SizedBox(width: 8),
                    SizedBox(width: showLineNumbers ? 6 : 0),
                    Expanded(
                      child: Text(
                        lines[i].isEmpty ? ' ' : lines[i],
                        style: TextStyle(
                          color: t.textNormal,
                          fontSize: 11,
                          fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ],
            ),
            if (favored && !active)
              Positioned(
                top: 2,
                right: 4,
                child: Tooltip(
                  message: 'structurally favored by coupling analysis',
                  child: Icon(Icons.auto_awesome,
                      size: 10,
                      color: AppTokens.contrastGlyph(t.surface1)
                          .withValues(alpha: 0.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Base panel
// ---------------------------------------------------------------------------

class _BasePanel extends StatelessWidget {
  final String text;
  const _BasePanel({required this.text});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.textFaint.withValues(alpha: 0.03),
        border: Border(
          top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
            child: Text('base',
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                )),
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: SelectableText(
                text.isEmpty ? '(new on both sides)' : text,
                style: TextStyle(
                  color: text.isEmpty ? t.textFaint : t.textMuted,
                  fontSize: 10.5,
                  fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                  height: 1.5,
                  fontStyle:
                      text.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action bar
// ---------------------------------------------------------------------------

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip(
      {required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ChromeButton(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      borderRadius: BorderRadius.circular(context.surfaceShader.geometry.badgeRadius),
      chromeBuilder: ({required hovered, required pressed}) =>
          ghostButtonChrome(t,
              hovered: hovered,
              pressed: pressed,
              enabled: true,
              baseBorderColor: color.withValues(alpha: 0.25)),
      child: Text(label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
          )),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _BranchPill extends StatelessWidget {
  final String label;
  final Color color;
  const _BranchPill({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.surfaceShader.geometry.badgeRadius),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
          )),
    );
  }
}

class _TrustChip extends StatefulWidget {
  final int level;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  const _TrustChip({
    required this.level,
    required this.labels,
    required this.onChanged,
  });
  @override
  State<_TrustChip> createState() => _TrustChipState();
}

class _TrustChipState extends State<_TrustChip> {
  final _chipKey = GlobalKey();
  OverlayEntry? _overlay;

  void _toggle() {
    if (_overlay != null) {
      _overlay!.remove();
      _overlay = null;
      return;
    }
    final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final t = context.tokens;
    _overlay = OverlayEntry(builder: (ctx) {
      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _overlay?.remove();
              _overlay = null;
            },
          ),
        ),
        Positioned(
          top: pos.dy + box.size.height + 4,
          right: MediaQuery.of(context).size.width - pos.dx - box.size.width,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: t.bg1.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(context.surfaceShader.geometry.pillRadius),
              border: Border.all(
                  color: t.chromeBorder.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  GestureDetector(
                    onTap: () {
                      widget.onChanged(i);
                      _overlay?.remove();
                      _overlay = null;
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(context.surfaceShader.geometry.badgeRadius),
                          color: i == widget.level
                              ? t.chromeAccent
                                  .withValues(alpha: 0.12)
                              : null,
                        ),
                        child: Text(widget.labels[i],
                            style: TextStyle(
                              color: i == widget.level
                                  ? t.chromeAccent
                                  : t.textFaint,
                              fontSize: 9,
                              fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                              fontWeight: i == widget.level
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              decoration: TextDecoration.none,
                            )),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ]);
    });
    Overlay.of(context).insert(_overlay!);
  }

  @override
  void didUpdateWidget(_TrustChip old) {
    super.didUpdateWidget(old);
    if (_overlay != null) {
      _overlay!.remove();
      _overlay = null;
    }
  }

  @override
  void dispose() {
    _overlay?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = widget.labels[widget.level];
    return ChromeButton(
      key: _chipKey,
      onTap: _toggle,
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: BorderRadius.circular(context.surfaceShader.geometry.pillRadius),
      chromeBuilder: ({required hovered, required pressed}) =>
          ghostButtonChrome(t,
              hovered: hovered,
              pressed: pressed,
              enabled: true,
              baseBorderColor: widget.level > 1
                  ? t.chromeAccent.withValues(alpha: 0.3)
                  : t.chromeBorder.withValues(alpha: 0.25)),
      child: Text('trust: $label',
          style: TextStyle(
            color: widget.level > 1 ? t.chromeAccent : t.textMuted,
            fontSize: 9.5,
            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
          )),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _HeaderChip(
      {required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ChromeButton(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: BorderRadius.circular(context.surfaceShader.geometry.pillRadius),
      chromeBuilder: ({required hovered, required pressed}) =>
          ghostButtonChrome(t,
              hovered: hovered,
              pressed: pressed,
              enabled: true,
              baseBorderColor: active
                  ? t.accentBright.withValues(alpha: 0.3)
                  : t.chromeBorder.withValues(alpha: 0.25)),
      child: Text(label,
          style: TextStyle(
            color: active ? t.accentBright : t.textMuted,
            fontSize: 10,
            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
          )),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen merge editor page
// ---------------------------------------------------------------------------

class MergeEditorPage extends StatefulWidget {
  final List<ConflictFile> files;
  final String repoPath;
  const MergeEditorPage({
    super.key,
    required this.files,
    required this.repoPath,
  });
  @override
  State<MergeEditorPage> createState() => _MergeEditorPageState();
}

class _MergeEditorPageState extends State<MergeEditorPage> {
  int _activeIndex = 0;

  bool get _allFilesResolved => widget.files.every((f) => f.allResolved);

  Future<void> _writeAndComplete() async {
    // Stage to temp files first, then rename atomically so a failure
    // mid-loop doesn't leave a mixed state on disk.
    final staged = <(File tmp, File target)>[];
    try {
      for (final file in widget.files) {
        if (!file.allResolved) continue;
        final absPath = '${widget.repoPath}/${file.path}'
            .replaceAll('/', Platform.pathSeparator);
        final target = File(absPath);
        final tmp = File('$absPath.manifold-resolve');
        await tmp.writeAsString(file.buildResult());
        staged.add((tmp, target));
      }
      for (final (tmp, target) in staged) {
        await tmp.rename(target.path);
      }
      final addResult = await Process.run(
        'git', ['add', '--', ...widget.files.map((f) => f.path)],
        workingDirectory: widget.repoPath,
      );
      if (addResult.exitCode != 0) {
        throw Exception(
            'git add failed: ${addResult.stderr.toString().trim()}');
      }
    } catch (e) {
      // Clean up any temp files that didn't get renamed
      for (final (tmp, _) in staged) {
        try { await tmp.delete(); } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to write resolved files: $e')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop('done');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final file = widget.files[_activeIndex];
    final multiFile = widget.files.length > 1;
    return Scaffold(
      backgroundColor: t.bg1,
      body: Stack(children: [
        Positioned.fill(
          child: MergeConflictEditor(
            key: ValueKey(file.path),
            file: file,
            allFilesResolved: _allFilesResolved,
            onComplete: _allFilesResolved
                ? _writeAndComplete
                : () {
                    for (var i = 0; i < widget.files.length; i++) {
                      final next =
                          (i + _activeIndex + 1) % widget.files.length;
                      if (!widget.files[next].allResolved) {
                        setState(() => _activeIndex = next);
                        return;
                      }
                    }
                    setState(() {});
                  },
            onCancel: () => Navigator.of(context).pop(),
            onResolutionChanged: () => setState(() {}),
            extraTopPadding: multiFile ? 36 : 0,
          ),
        ),
        if (multiFile)
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: t.bg1.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(context.surfaceShader.geometry.cardRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                      color: t.chromeBorder.withValues(alpha: 0.12)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.files.length; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      _FileTab(
                        file: widget.files[i],
                        active: i == _activeIndex,
                        onTap: () => setState(() => _activeIndex = i),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _FileTab extends StatelessWidget {
  final ConflictFile file;
  final bool active;
  final VoidCallback onTap;
  const _FileTab(
      {required this.file, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final resolved = file.allResolved;
    final tipParts = [file.path];
    if (file.changedNeighborCount != null) {
      tipParts.add(
          '${file.changedNeighborCount}/${file.totalNeighborCount} neighbors co-changed');
    }
    if (file.integrity != null) {
      tipParts.add('integrity ${(file.integrity! * 100).round()}%');
    }
    if (file.lastReviewer != null) {
      tipParts.add('reviewer: ${file.lastReviewer}');
    }
    return Tooltip(
      message: tipParts.join('\n'),
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: context.motion(AppMotion.snap),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.surfaceShader.geometry.badgeRadius),
              color: active
                  ? t.accentBright.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border.all(
                color: active
                    ? t.accentBright.withValues(alpha: 0.3)
                    : resolved
                        ? t.stateAdded.withValues(alpha: 0.3)
                        : t.chromeBorder.withValues(alpha: 0.2),
              ),
            ),
            child:
                Row(mainAxisSize: MainAxisSize.min, children: [
              if (resolved)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Icon(Icons.check_circle,
                      size: 10, color: t.stateAdded),
                ),
              Text(
                file.path.split('/').last,
                style: TextStyle(
                  color: active ? t.textStrong : t.textMuted,
                  fontSize: 10.5,
                  fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${file.resolvedCount}/${file.blocks.length}',
                style: TextStyle(
                  color: resolved ? t.stateAdded : t.textFaint,
                  fontSize: 9,
                  fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
