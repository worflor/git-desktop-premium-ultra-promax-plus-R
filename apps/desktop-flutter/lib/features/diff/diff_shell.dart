import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../ui/material_surface.dart';
import '../../ui/form_controls.dart';
import '../../ui/status_view.dart';
import '../../ui/tokens.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../components/icons/app_icons.dart';
import '../../diagnostics/diagnostics_state.dart';

// ── Data types ────────────────────────────────────────────────────────────────

enum _LineKind { added, deleted, hunk, meta, context }

const int _kModeAMaxChangedLines = 15000;
const int _kModeAMaxPayloadBytes = 3 * 1024 * 1024;
const int _kAnimatedDiffMaxChangedLines = 24;
const int _kAnimatedDiffMaxPayloadBytes = 4 * 1024;
const Duration _kBlameHoverDelay = Duration(milliseconds: 180);
const Duration _kInitialFrameCaptureWindow = Duration(milliseconds: 900);
const Duration _kScrollFrameCaptureQuietWindow = Duration(milliseconds: 280);

class _ParsedLine {
  final String text;
  final String lowerText;
  final _LineKind kind;
  final int? lineNumOld;
  final int? lineNumNew;
  final int hunkIndex; // which hunk this belongs to (-1 for meta)
  const _ParsedLine({
    required this.text,
    required this.lowerText,
    required this.kind,
    this.lineNumOld,
    this.lineNumNew,
    this.hunkIndex = -1,
  });
}

class _HunkHeader {
  final int lineIndex;
  final String label;
  const _HunkHeader(this.lineIndex, this.label);
}

// ── Parser ────────────────────────────────────────────────────────────────────

List<_ParsedLine> _parseDiff(String diff) {
  final rawLines = diff.split('\n');
  final result = <_ParsedLine>[];
  int oldLine = 0, newLine = 0, hunkIdx = -1;

  for (final line in rawLines) {
    if (line.startsWith('diff ') || line.startsWith('index ')) {
      continue;
    }
    if (line.startsWith('@@')) {
      final m =
          RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(line);
      if (m != null) {
        oldLine = int.tryParse(m.group(1)!) ?? 0;
        newLine = int.tryParse(m.group(2)!) ?? 0;
      }
      hunkIdx++;
      result.add(_ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: _LineKind.hunk,
          hunkIndex: hunkIdx));
    } else if (line.startsWith('+') && !line.startsWith('+++')) {
      result.add(_ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: _LineKind.added,
          lineNumNew: newLine++,
          hunkIndex: hunkIdx));
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      result.add(_ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: _LineKind.deleted,
          lineNumOld: oldLine++,
          hunkIndex: hunkIdx));
    } else if (line.startsWith('new file mode ') ||
        line.startsWith('deleted file mode ') ||
        line.startsWith('old mode ') ||
        line.startsWith('new mode ') ||
        line.startsWith('similarity index ') ||
        line.startsWith('rename from ') ||
        line.startsWith('rename to ') ||
        line.startsWith('Binary files ') ||
        line.startsWith('GIT binary patch') ||
        line.startsWith('--- ') ||
        line.startsWith('+++ ')) {
      result.add(_ParsedLine(
          text: line, lowerText: line.toLowerCase(), kind: _LineKind.meta));
    } else if (line.isNotEmpty) {
      result.add(_ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: _LineKind.context,
          lineNumOld: oldLine++,
          lineNumNew: newLine++,
          hunkIndex: hunkIdx));
    } else {
      result.add(_ParsedLine(
          text: line,
          lowerText: '',
          kind: _LineKind.context,
          hunkIndex: hunkIdx));
    }
  }

  return result;
}

List<_HunkHeader> _extractHunks(List<_ParsedLine> lines) {
  final result = <_HunkHeader>[];
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].kind == _LineKind.hunk) {
      final text = lines[i].text;
      // Extract just the @@ ... @@ portion as label
      final m = RegExp(r'^(@@ [^ ]+ [^ ]+ @@)(.*)$').firstMatch(text);
      final label =
          m != null ? (m.group(1)! + (m.group(2)?.trimRight() ?? '')) : text;
      result.add(_HunkHeader(
          i, label.length > 60 ? '${label.substring(0, 57)}...' : label));
    }
  }
  return result;
}

String _formatBlameTime(String timestamp) {
  final seconds = int.tryParse(timestamp);
  if (seconds == null) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final now = DateTime.now();
  final days = now.difference(date).inDays;
  if (days < 1) return 'today';
  if (days < 30) return '${days}d';
  if (days < 365) return '${(days / 30).floor()}mo';
  return '${(days / 365).floor()}y';
}

String _diffDisplayName(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? filePath : parts.last;
}

String? _diffDisplayDirectory(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length <= 1) {
    return null;
  }
  return parts.sublist(0, parts.length - 1).join('/');
}

String _diffStatusLabel(String diffContent) {
  if (diffContent.contains('rename from ') ||
      diffContent.contains('rename to ')) {
    return 'Renamed file';
  }
  if (diffContent.contains('deleted file mode') ||
      diffContent.contains('+++ /dev/null')) {
    return 'Deleted file';
  }
  if (diffContent.contains('new file mode') ||
      diffContent.contains('--- /dev/null')) {
    return 'New file';
  }
  if (diffContent.contains('Binary files ') ||
      diffContent.contains('GIT binary patch') ||
      diffContent.contains('[binary content omitted]')) {
    return 'Binary file';
  }
  return 'Edited file';
}

String _changeBlockLabel(int hunkCount) {
  if (hunkCount <= 1) {
    return '1 change block';
  }
  return '$hunkCount change blocks';
}

class _DiffFileHeader extends StatelessWidget {
  final String filePath;
  final String diffContent;
  final int hunkCount;
  final AppTokens tokens;

  const _DiffFileHeader({
    required this.filePath,
    required this.diffContent,
    required this.hunkCount,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final directory = _diffDisplayDirectory(filePath);
    final summaryParts = <String>[
      _diffStatusLabel(diffContent),
      _changeBlockLabel(hunkCount),
      if (directory != null) directory,
    ];
    return MaterialSurface(
      tone: AppMaterialTone.surface1,
      radius: 0,
      border: Border(
        bottom: BorderSide(color: tokens.chromeBorder.withValues(alpha: 0.12)),
      ),
      elevated: false,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _diffDisplayName(filePath),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textStrong,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            summaryParts.join(' | '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ── DiffShell ─────────────────────────────────────────────────────────────────

class DiffShell extends StatefulWidget {
  final String filePath;
  final String? diffContent;
  final bool loading;
  final String? error;
  final AppTokens tokens;
  final String? repositoryPath;
  final int? jumpToLineIndex;
  final int jumpToLineRequestId;
  final bool showFileHeader;

  const DiffShell({
    super.key,
    required this.filePath,
    required this.tokens,
    this.diffContent,
    this.loading = false,
    this.error,
    this.repositoryPath,
    this.jumpToLineIndex,
    this.jumpToLineRequestId = 0,
    this.showFileHeader = true,
  });

  @override
  State<DiffShell> createState() => _DiffShellState();
}

class _DiffShellState extends State<DiffShell> {
  final _searchCtrl = TextEditingController();
  String _searchTerm = '';
  bool _searchVisible = false;
  final _scrollCtrl = ScrollController();
  final _hScrollCtrl = ScrollController();
  double _maxLineWidth = 800.0;
  final Stopwatch _sessionStopwatch = Stopwatch();
  final List<double> _scrollFpsSamples = [];
  final List<double> _frameTotalSamples = [];
  final List<double> _frameBuildSamples = [];
  final List<double> _frameRasterSamples = [];
  final Map<int, BlameLineData> _blameByLine = {};
  bool _sessionFlushed = false;
  double? _sessionFirstPaintMs;
  DateTime? _lastScrollEventAt;
  String? _sessionDiffId;
  bool _sessionSearchActivated = false;
  bool _useAnimatedTextMode = false;
  int _sessionChangedLines = 0;
  int _sessionPayloadBytes = 0;
  List<_ParsedLine> _displayLines = const [];
  Timer? _blameHoverTimer;
  Timer? _sessionFlushTimer;
  late final TimingsCallback _frameTimingsCallback;

  // Blame
  List<BlameLineData>? _blameData;
  bool _blameFetched = false;
  bool _blameFetching = false;
  int? _hoveredLine; // the lineNumNew being hovered

  // Hunk navigation
  List<_HunkHeader> _hunks = [];
  List<_ParsedLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _frameTimingsCallback = _handleFrameTimings;
    SchedulerBinding.instance.addTimingsCallback(_frameTimingsCallback);
    _scrollCtrl.addListener(_handleScrollTelemetry);
    _rebuild();
  }

  @override
  void didUpdateWidget(DiffShell old) {
    super.didUpdateWidget(old);
    if (old.diffContent != widget.diffContent ||
        old.filePath != widget.filePath) {
      _blameFetched = false;
      _blameFetching = false;
      _blameData = null;
      _blameByLine.clear();
      _hoveredLine = null;
      _rebuild();
      if (old.filePath != widget.filePath) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(0);
          }
        });
      }
    }
    if (old.jumpToLineRequestId != widget.jumpToLineRequestId &&
        widget.jumpToLineIndex != null) {
      _jumpToLineIndex(widget.jumpToLineIndex!);
    }
  }

  void _rebuild() {
    if (widget.diffContent != null && widget.diffContent!.isNotEmpty) {
      final parsedLines = _parseDiff(widget.diffContent!);
      _lines = widget.showFileHeader
          ? _trimLeadingMetaLines(parsedLines)
          : parsedLines;
      _hunks = _extractHunks(_lines);
      _refreshDisplayLines();
      _computeMaxLineWidth();
      _beginTelemetrySession();
    } else {
      _flushRenderMetrics();
      _lines = [];
      _hunks = [];
      _displayLines = const [];
      _useAnimatedTextMode = false;
      _sessionChangedLines = 0;
      _sessionPayloadBytes = 0;
      _maxLineWidth = 800.0;
    }
  }

  void _beginTelemetrySession() {
    _sessionDiffId = '${widget.filePath}:${widget.diffContent.hashCode}';
    _sessionStopwatch
      ..reset()
      ..start();
    _scrollFpsSamples.clear();
    _frameTotalSamples.clear();
    _frameBuildSamples.clear();
    _frameRasterSamples.clear();
    _sessionFirstPaintMs = null;
    _lastScrollEventAt = null;
    _sessionFlushed = false;
    _sessionSearchActivated = _searchTerm.isNotEmpty;
    _sessionPayloadBytes = widget.diffContent == null
        ? 0
        : utf8.encode(widget.diffContent!).length;
    _sessionChangedLines = _lines
        .where((line) =>
            line.kind == _LineKind.added || line.kind == _LineKind.deleted)
        .length;
    _useAnimatedTextMode = !_sessionSearchActivated &&
        _sessionChangedLines <= _kAnimatedDiffMaxChangedLines &&
        _sessionPayloadBytes <= _kAnimatedDiffMaxPayloadBytes;
    _armRenderMetricsFlush(_kInitialFrameCaptureWindow);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.diffContent == null ||
          widget.diffContent!.isEmpty ||
          _sessionFirstPaintMs != null) {
        return;
      }
      _sessionFirstPaintMs = _sessionStopwatch.elapsedMicroseconds / 1000;
    });
  }

  void _handleScrollTelemetry() {
    if (!_sessionStopwatch.isRunning) {
      return;
    }
    final now = DateTime.now();
    final previous = _lastScrollEventAt;
    _lastScrollEventAt = now;
    if (previous == null) {
      return;
    }
    final deltaMs = now.difference(previous).inMicroseconds.abs() / 1000;
    if (deltaMs <= 0) {
      return;
    }
    final fps = 1000 / deltaMs;
    if (fps.isFinite && fps > 0) {
      _scrollFpsSamples.add(fps.clamp(0, 240));
    }
    _armRenderMetricsFlush(_kScrollFrameCaptureQuietWindow);
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    if (!_sessionStopwatch.isRunning) {
      return;
    }
    for (final timing in timings) {
      final totalMs = timing.totalSpan.inMicroseconds / 1000;
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      if (totalMs.isFinite && totalMs > 0) {
        _frameTotalSamples.add(totalMs);
      }
      if (buildMs.isFinite && buildMs > 0) {
        _frameBuildSamples.add(buildMs);
      }
      if (rasterMs.isFinite && rasterMs > 0) {
        _frameRasterSamples.add(rasterMs);
      }
    }
  }

  void _armRenderMetricsFlush(Duration delay) {
    _sessionFlushTimer?.cancel();
    _sessionFlushTimer = Timer(delay, _flushRenderMetrics);
  }

  void _flushRenderMetrics() {
    if (_sessionFlushed ||
        _sessionDiffId == null ||
        widget.diffContent == null ||
        widget.diffContent!.isEmpty) {
      return;
    }
    _sessionFlushTimer?.cancel();
    _sessionFlushTimer = null;
    final firstPaintMs =
        _sessionFirstPaintMs ?? (_sessionStopwatch.elapsedMicroseconds / 1000);
    final sustainedScrollFps = _sessionPercentile(_scrollFpsSamples, 50);
    final rendererMode = _useAnimatedTextMode
        ? 'dom-animated'
        : (_sessionSearchActivated
            ? 'dom-search'
            : _selectRendererMode(
                _sessionChangedLines,
                _sessionPayloadBytes,
                false,
              ));
    final frameTimeP95Ms = _sessionPercentile(_frameTotalSamples, 95);
    final buildTimeP95Ms = _sessionPercentile(_frameBuildSamples, 95);
    final rasterTimeP95Ms = _sessionPercentile(_frameRasterSamples, 95);
    final jankyFrameCount =
        _frameTotalSamples.where((value) => value > 16.7).length;

    _sessionFlushed = true;
    _sessionStopwatch.stop();
    DiagnosticsState.instance.recordDiffRenderMetrics(
      diffId: _sessionDiffId!,
      path: widget.filePath,
      rendererMode: rendererMode,
      changedLines: _sessionChangedLines,
      payloadBytes: _sessionPayloadBytes,
      firstPaintMs: firstPaintMs,
      sustainedScrollFps: sustainedScrollFps,
      memoryEstimateMb: _sessionPayloadBytes / (1024 * 1024),
      frameTimeP95Ms: frameTimeP95Ms,
      buildTimeP95Ms: buildTimeP95Ms,
      rasterTimeP95Ms: rasterTimeP95Ms,
      frameCount: _frameTotalSamples.length,
      jankyFrameCount: jankyFrameCount,
      fallbackActivated: false,
    );
  }

  double _sessionPercentile(List<double> values, int percentile) {
    if (values.isEmpty) {
      return 0;
    }
    final sorted = [...values]..sort();
    final rank = ((sorted.length * percentile) / 100).ceil();
    final index = rank <= 0 ? 0 : (rank - 1).clamp(0, sorted.length - 1);
    return sorted[index];
  }

  String _selectRendererMode(
    int changedLines,
    int payloadBytes,
    bool fallbackActivated,
  ) {
    if (fallbackActivated) {
      return 'fallback';
    }
    if (changedLines < _kModeAMaxChangedLines &&
        payloadBytes < _kModeAMaxPayloadBytes) {
      return 'dom';
    }
    return 'canvas';
  }

  @override
  void dispose() {
    _flushRenderMetrics();
    _blameHoverTimer?.cancel();
    _sessionFlushTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_frameTimingsCallback);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _hScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBlame(int lineNum) async {
    if (_blameFetched || _blameFetching) return;
    final repo = widget.repositoryPath;
    if (repo == null) return;

    setState(() {
      _blameFetching = true;
      _hoveredLine = lineNum;
    });
    final r = await getFileBlame(repo, widget.filePath);
    if (!mounted) return;
    setState(() {
      _blameFetching = false;
      _blameFetched = true;
      if (r.ok) {
        _blameData = r.data;
        _blameByLine
          ..clear()
          ..addEntries(
              r.data!.map((entry) => MapEntry(entry.lineNumber, entry)));
      }
    });
  }

  BlameLineData? _blameFor(int lineNum) {
    return _blameByLine[lineNum];
  }

  bool get _canShowInlineBlame =>
      !_useAnimatedTextMode &&
      _sessionChangedLines <= 400 &&
      _sessionPayloadBytes <= 96 * 1024;

  void _scheduleBlameLoad(int lineNum) {
    if (!_canShowInlineBlame) {
      return;
    }
    _blameHoverTimer?.cancel();
    _blameHoverTimer = Timer(_kBlameHoverDelay, () {
      if (!mounted || _hoveredLine != lineNum) {
        return;
      }
      _loadBlame(lineNum);
    });
  }

  void _refreshDisplayLines() {
    final sourceLines =
        widget.showFileHeader ? _trimLeadingMetaLines(_lines) : _lines;
    final term = _searchTerm.toLowerCase();
    if (term.isEmpty) {
      _displayLines = sourceLines;
      return;
    }
    _displayLines =
        sourceLines.where((line) => line.lowerText.contains(term)).toList();
  }

  void _computeMaxLineWidth() {
    // Gutter is 56px wide; horizontal padding inside lineContent is 8px each side.
    // JetBrains Mono at 12px — measure real char width via TextPainter so this
    // stays accurate if the font size or family ever changes.
    final painter = TextPainter(
      text: const TextSpan(
        text: 'M',
        style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final charWidth = painter.width > 0 ? painter.width : 7.5;

    const gutterW = 56.0;
    const sidePad = 16.0; // 8px × 2
    const minW = 400.0;
    const maxW = 12000.0;

    // Compute from _lines (all lines) so the scroll range doesn't jump
    // when the user filters with search.
    int maxChars = 0;
    for (final line in _lines) {
      if (line.text.length > maxChars) maxChars = line.text.length;
    }
    _maxLineWidth = (gutterW + sidePad + maxChars * charWidth).clamp(minW, maxW);
  }

  List<_ParsedLine> _trimLeadingMetaLines(List<_ParsedLine> lines) {
    var firstContentIndex = 0;
    while (firstContentIndex < lines.length &&
        lines[firstContentIndex].kind == _LineKind.meta) {
      firstContentIndex++;
    }
    return firstContentIndex == 0 ? lines : lines.sublist(firstContentIndex);
  }

  void _jumpToHunkIndex(int hunkIdx) {
    if (hunkIdx < 0 || hunkIdx >= _hunks.length) return;
    final lineIdx = _hunks[hunkIdx].lineIndex;
    _jumpToLineIndex(lineIdx);
  }

  void _jumpToLineIndex(int lineIdx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) {
        return;
      }
      const lineH = 18.0;
      final targetOffset = (lineIdx * lineH).clamp(
        0.0,
        _scrollCtrl.position.maxScrollExtent,
      );
      _scrollCtrl.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final hasContent =
        widget.diffContent != null && widget.diffContent!.isNotEmpty;

    if (widget.loading && !hasContent) {
      return const AppStatusView.loading(
        title: 'Loading diff',
        message: 'Reading file changes.',
        compact: true,
      );
    }
    if (widget.error != null && !hasContent) {
      return AppStatusView.error(
        title: 'Diff unavailable',
        message: widget.error!,
        compact: true,
      );
    }
    if (!hasContent) {
      return const AppStatusView(
        title: 'No changes',
        message: 'This file has no diff content to display.',
        compact: true,
      );
    }

    final displayLines = _displayLines;

    return Stack(children: [
      Column(children: [
        if (widget.showFileHeader)
          _DiffFileHeader(
            filePath: widget.filePath,
            diffContent: widget.diffContent ?? '',
            hunkCount: _hunks.length,
            tokens: t,
          ),
        // ── Toolbar: search + hunk nav ─────────────────────────────────────
        MaterialSurface(
          tone: AppMaterialTone.surface1,
          radius: 0,
          border: Border(
            bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.12)),
          ),
          elevated: false,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            // Search toggle
            _ToolbarBtn(
              icon: 'search',
              active: _searchVisible,
              t: t,
              onTap: () => setState(() {
                _searchVisible = !_searchVisible;
                _sessionSearchActivated =
                    _sessionSearchActivated || _searchVisible;
                if (!_searchVisible) {
                  _searchTerm = '';
                  _searchCtrl.clear();
                  _refreshDisplayLines();
                }
              }),
            ),
            // Search input
            if (_searchVisible) ...[
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  height: 24,
                  fontSize: 12,
                  hintText: 'Search diff...',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  onChanged: (v) => setState(() {
                    _searchTerm = v;
                    _sessionSearchActivated =
                        _sessionSearchActivated || v.isNotEmpty;
                    _refreshDisplayLines();
                  }),
                ),
              ),
              if (_searchTerm.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  '${displayLines.length} line${displayLines.length == 1 ? "" : "s"}',
                  style: TextStyle(color: t.textMuted, fontSize: 10),
                ),
              ],
            ],

            if (!_searchVisible) const Spacer(),

            // Hunk navigation
            if (_hunks.isNotEmpty && !_searchVisible) ...[
              const SizedBox(width: 6),
              _HunkDropdown(hunks: _hunks, t: t, onJump: _jumpToHunkIndex),
            ],

            // Blame indicator
            if (_blameFetching)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'blame...',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_blameFetched && _blameData != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('blame',
                    style: TextStyle(
                        color: t.accentBright.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
        ),

        // ── Diff lines ────────────────────────────────────────────────────
        Expanded(
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: true),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Content is at least as wide as the viewport so there's no
                // unnecessary horizontal scroll when lines are short.
                final contentWidth =
                    _maxLineWidth > constraints.maxWidth
                        ? _maxLineWidth
                        : constraints.maxWidth;
                return SingleChildScrollView(
                  controller: _hScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: contentWidth,
                    child: ListView.builder(
                      controller: _searchVisible ? null : _scrollCtrl,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: displayLines.length,
                      itemExtent: 18,
                      itemBuilder: (ctx, i) {
                        final line = displayLines[i];
                        return _DiffLine(
                          line: line,
                          tokens: t,
                          blameEntry: line.lineNumNew != null
                              ? _blameFor(line.lineNumNew!)
                              : null,
                          hovered: _hoveredLine == line.lineNumNew &&
                              line.lineNumNew != null,
                          onGutterEnter:
                              _canShowInlineBlame && line.lineNumNew != null
                                  ? () {
                                      setState(
                                          () => _hoveredLine = line.lineNumNew!);
                                      _scheduleBlameLoad(line.lineNumNew!);
                                    }
                                  : null,
                          onGutterExit: () {
                            _blameHoverTimer?.cancel();
                            setState(() => _hoveredLine = null);
                          },
                          searchTerm: _searchTerm,
                          useAnimatedTextMode: _useAnimatedTextMode,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ]),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AnimatedOpacity(
          opacity: widget.loading ? 1 : 0,
          duration: const Duration(milliseconds: 80),
          child: LinearProgressIndicator(
            minHeight: 2,
            color: t.accentBright.withValues(alpha: 0.7),
            backgroundColor: Colors.transparent,
          ),
        ),
      ),
    ]);
  }
}

// ── Diff line ─────────────────────────────────────────────────────────────────

class _DiffLine extends StatelessWidget {
  final _ParsedLine line;
  final AppTokens tokens;
  final BlameLineData? blameEntry;
  final bool hovered;
  final VoidCallback? onGutterEnter;
  final VoidCallback onGutterExit;
  final String searchTerm;
  final bool useAnimatedTextMode;

  const _DiffLine({
    required this.line,
    required this.tokens,
    required this.blameEntry,
    required this.hovered,
    required this.onGutterEnter,
    required this.onGutterExit,
    required this.searchTerm,
    required this.useAnimatedTextMode,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final l = line;
    final isMeta = l.kind == _LineKind.meta;

    Color? lineBg;
    Color textColor;

    switch (l.kind) {
      case _LineKind.added:
        lineBg = t.stateAdded.withValues(alpha: 0.1);
        textColor = t.stateAdded;
        break;
      case _LineKind.deleted:
        lineBg = t.stateDeleted.withValues(alpha: 0.1);
        textColor = t.stateDeleted;
        break;
      case _LineKind.hunk:
        lineBg = t.chromeAccent.withValues(alpha: 0.07);
        textColor = t.accentBright;
        break;
      case _LineKind.meta:
        lineBg = t.surface0.withValues(alpha: 0.18);
        textColor = t.textMuted.withValues(alpha: 0.72);
        break;
      case _LineKind.context:
        lineBg = null;
        textColor = t.textNormal;
        break;
    }

    // Build gutter text (old | new line numbers or hunk marker)
    String gutterText = '';
    if (l.kind == _LineKind.hunk) {
      gutterText = '···';
    } else if (l.kind == _LineKind.added) {
      gutterText = l.lineNumNew != null ? '${l.lineNumNew}' : '';
    } else if (l.kind == _LineKind.deleted) {
      gutterText = l.lineNumOld != null ? '${l.lineNumOld}' : '';
    } else if (l.kind == _LineKind.context) {
      gutterText = l.lineNumNew != null ? '${l.lineNumNew}' : '';
    }

    final gutterCell = Container(
      width: isMeta ? 40 : 56,
      padding: const EdgeInsets.only(right: 8),
      alignment: Alignment.centerRight,
      color: hovered
          ? t.accentBright.withValues(alpha: 0.06)
          : isMeta
              ? Colors.transparent
              : (lineBg?.withValues(alpha: 0.6) ??
                  t.surface1.withValues(alpha: 0.5)),
      child: Text(
        gutterText,
        style: TextStyle(
          color: hovered
              ? (blameEntry != null
                  ? t.accentBright.withValues(alpha: 0.9)
                  : t.textMuted)
              : t.textMuted.withValues(alpha: 0.5),
          fontSize: 10,
          fontFamily: 'JetBrainsMono',
        ),
      ),
    );
    final gutterContent = onGutterEnter == null && !hovered
        ? gutterCell
        : MouseRegion(
            onEnter: onGutterEnter != null ? (_) => onGutterEnter!() : null,
            onExit: (_) => onGutterExit(),
            cursor: onGutterEnter != null
                ? SystemMouseCursors.cell
                : MouseCursor.defer,
            child: gutterCell,
          );

    final useAnimatedText = useAnimatedTextMode &&
        searchTerm.isEmpty &&
        l.text.length <= 160 &&
        (l.kind == _LineKind.added ||
            l.kind == _LineKind.deleted ||
            l.kind == _LineKind.hunk);
    final textChild = useAnimatedText
        ? _DiffMeltText(
            text: l.text,
            color: textColor,
          )
        : _buildPlainDiffText(
            l.text.isEmpty ? ' ' : l.text,
            textColor,
            t,
            searchTerm,
            fontSize: isMeta ? 11 : 12,
            height: isMeta ? 1.3 : 1.5,
          );

    Widget lineContent = Expanded(
      child: Container(
        color: lineBg,
        padding: EdgeInsets.symmetric(horizontal: isMeta ? 12 : 8),
        alignment: Alignment.centerLeft,
        child: textChild,
      ),
    );

    final baseRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [gutterContent, lineContent],
    );

    // Blame annotation overlay — shown inline left of gutter on hover (matches original)
    final showBlame = hovered && blameEntry != null;
    if (!showBlame) return baseRow;

    final b = blameEntry!;
    final initial =
        b.authorName.isNotEmpty ? b.authorName[0].toUpperCase() : '?';
    final timeStr = _formatBlameTime(b.authoredAt);
    // Deterministic author color from name hash
    final hue = (b.authorName.codeUnits.fold(0, (a, c) => a + c) * 37) % 360;
    final authorColor =
        HSLColor.fromAHSL(1.0, hue.toDouble(), 0.55, 0.55).toColor();

    return Stack(clipBehavior: Clip.none, children: [
      baseRow,
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: t.surface1,
              border: Border(
                right: BorderSide(
                    color: t.accentBright.withValues(alpha: 0.3), width: 2),
              ),
            ),
            child: Row(children: [
              // Author initial circle
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: authorColor.withValues(alpha: 0.2)),
                child: Center(
                  child: Text(initial,
                      style: TextStyle(
                          color: authorColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(b.shortHash,
                        style: TextStyle(
                            color: t.accentBright,
                            fontSize: 9,
                            fontFamily: 'JetBrainsMono'),
                        overflow: TextOverflow.ellipsis),
                    Text(timeStr,
                        style: TextStyle(color: t.textMuted, fontSize: 9),
                        overflow: TextOverflow.ellipsis),
                  ])),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ── Toolbar button ────────────────────────────────────────────────────────────

class _DiffMeltText extends StatefulWidget {
  final String text;
  final Color color;

  const _DiffMeltText({
    required this.text,
    required this.color,
  });

  @override
  State<_DiffMeltText> createState() => _DiffMeltTextState();
}

class _DiffMeltTextState extends State<_DiffMeltText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late String _fromText;
  late String _toText;
  late Color _fromColor;
  late Color _toColor;

  String get _displayText => widget.text.isEmpty ? ' ' : widget.text;

  @override
  void initState() {
    super.initState();
    _fromText = _displayText;
    _toText = _fromText;
    _fromColor = widget.color;
    _toColor = widget.color;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _DiffMeltText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _displayText;
    if (nextText != _toText || widget.color != _toColor) {
      _fromText = _toText;
      _fromColor = _toColor;
      _toText = nextText;
      _toColor = widget.color;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _DiffMeltTextPainter(
                fromText: _fromText,
                toText: _toText,
                fromColor: _fromColor,
                toColor: _toColor,
                progress: _controller.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

Widget _buildPlainDiffText(
  String displayText,
  Color baseColor,
  AppTokens t,
  String searchTerm, {
  double fontSize = 12,
  double height = 1.5,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
}) {
  if (searchTerm.isNotEmpty) {
    return _buildSearchText(
      displayText,
      baseColor,
      t,
      searchTerm,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );
  }
  return Text(
    displayText,
    maxLines: 1,
    overflow: TextOverflow.clip,
    style: TextStyle(
      color: baseColor,
      fontSize: fontSize,
      fontFamily: 'JetBrainsMono',
      height: height,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    ),
  );
}

Widget _buildSearchText(
  String displayText,
  Color baseColor,
  AppTokens t,
  String searchTerm, {
  double fontSize = 12,
  double height = 1.5,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
}) {
  final lower = displayText.toLowerCase();
  final termLower = searchTerm.toLowerCase();
  final spans = <TextSpan>[];
  int start = 0;
  int idx = lower.indexOf(termLower);
  while (idx != -1) {
    if (idx > start) {
      spans.add(TextSpan(
          text: displayText.substring(start, idx),
          style: TextStyle(
            color: baseColor,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
          )));
    }
    spans.add(TextSpan(
      text: displayText.substring(idx, idx + termLower.length),
      style: TextStyle(
        color: t.bg0,
        backgroundColor: t.accentBright.withValues(alpha: 0.8),
        fontWeight: fontWeight,
        fontStyle: fontStyle,
      ),
    ));
    start = idx + termLower.length;
    idx = lower.indexOf(termLower, start);
  }
  if (start < displayText.length) {
    spans.add(TextSpan(
        text: displayText.substring(start),
        style: TextStyle(
          color: baseColor,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
        )));
  }

  return RichText(
    text: TextSpan(
      style: TextStyle(
        fontSize: fontSize,
        fontFamily: 'JetBrainsMono',
        height: height,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
      ),
      children: spans,
    ),
    overflow: TextOverflow.clip,
    maxLines: 1,
  );
}

class _DiffMeltTextPainter extends CustomPainter {
  static const _fontSize = 12.0;
  static const _fontFamily = 'JetBrainsMono';
  static const _lineHeight = 1.5;
  static const _maxMeltGlyphs = 180;
  static double? _cachedCharWidth;

  final String fromText;
  final String toText;
  final Color fromColor;
  final Color toColor;
  final double progress;

  const _DiffMeltTextPainter({
    required this.fromText,
    required this.toText,
    required this.fromColor,
    required this.toColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final textHeight = _fontSize * _lineHeight;
    final baselineY = (size.height - textHeight) / 2;
    final charWidth = _measureCharWidth();

    if (progress >= 0.999) {
      _paintRun(canvas, toText, toColor, Offset(0, baselineY));
      canvas.restore();
      return;
    }

    final t = progress.clamp(0.0, 1.0);
    final newArrived = _smoothStep(0.08, 0.62, t);
    final relatedRows = _rowAffinity(fromText, toText) >= 0.52;
    final newAlphaFloor = relatedRows ? 0.55 : 0.78;
    final newAlpha = newAlphaFloor +
        Curves.easeOutCubic.transform(newArrived) * (1 - newAlphaFloor);
    final maxByWidth = math.max(1, (size.width / charWidth).ceil() + 2);
    final meltLimit = math.min(
      math.min(math.max(fromText.length, toText.length), maxByWidth),
      _maxMeltGlyphs,
    );

    if (relatedRows && toText.trim().isNotEmpty) {
      _paintMeltTrails(
        canvas: canvas,
        text: fromText,
        otherText: toText,
        color: fromColor,
        baselineY: baselineY,
        charWidth: charWidth,
        limit: meltLimit,
        incoming: false,
        amount: t,
        opacityScale: 1,
      );
    }

    if (relatedRows) {
      _paintMeltTrails(
        canvas: canvas,
        text: toText,
        otherText: fromText,
        color: toColor,
        baselineY: baselineY,
        charWidth: charWidth,
        limit: meltLimit,
        incoming: true,
        amount: t,
        opacityScale: 1,
      );
    }
    _paintRun(
      canvas,
      toText,
      toColor.withValues(alpha: toColor.a * newAlpha),
      Offset(0, baselineY),
    );

    canvas.restore();
  }

  double _measureCharWidth() {
    final cached = _cachedCharWidth;
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: _style(Colors.white)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return _cachedCharWidth = painter.width;
  }

  void _paintMeltTrails({
    required Canvas canvas,
    required String text,
    required String otherText,
    required Color color,
    required double baselineY,
    required double charWidth,
    required int limit,
    required bool incoming,
    required double amount,
    required double opacityScale,
  }) {
    if (text.isEmpty) return;
    for (var i = 0; i < limit; i++) {
      if (i >= text.length) break;
      final char = text[i];
      if (char.trim().isEmpty) continue;

      final otherChar = i < otherText.length ? otherText[i] : '';
      final changed =
          char != otherChar || color != (incoming ? fromColor : toColor);
      if (!changed) continue;
      if (!incoming && otherChar.trim().isEmpty) continue;

      final seed = _unitHash(i, text.length, otherText.length);
      final delay = seed * 0.18;
      final phase = ((amount - delay) / (1 - delay)).clamp(0.0, 1.0);
      final pulse = math.sin(math.pi * phase).clamp(0.0, 1.0);
      if (pulse <= 0) continue;

      final x = (i * charWidth).roundToDouble();
      final depth = 1.2 + 3.2 * seed;
      final y = incoming
          ? baselineY + depth * (1 - phase)
          : baselineY + 0.7 + depth * phase;
      final scaleY = incoming ? 1.1 - 0.08 * phase : 1 + 0.22 * phase;
      final alpha = color.a * pulse * (incoming ? 0.14 : 0.18) * opacityScale;

      _paintRunTransformed(
        canvas,
        char,
        color.withValues(alpha: alpha),
        Offset(x, y),
        scaleY,
      );
    }
  }

  double _unitHash(int index, int a, int b) {
    final value =
        math.sin((index + 1) * 12.9898 + a * 78.233 + b * 37.719) * 43758.5453;
    return value - value.floorToDouble();
  }

  double _rowAffinity(String a, String b) {
    final aTrim = a.trim();
    final bTrim = b.trim();
    if (aTrim.isEmpty || bTrim.isEmpty) return 0;
    if (aTrim == bTrim) return 1;

    final limit = math.min(a.length, b.length);
    var comparable = 0;
    var matches = 0;
    for (var i = 0; i < limit; i++) {
      final ca = a[i];
      final cb = b[i];
      if (ca.trim().isEmpty && cb.trim().isEmpty) continue;
      comparable++;
      if (ca == cb) matches++;
    }
    if (comparable == 0) return 0;

    final lengthPenalty = math.min(aTrim.length, bTrim.length) /
        math.max(aTrim.length, bTrim.length);
    return (matches / comparable) * lengthPenalty;
  }

  double _smoothStep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  void _paintRunTransformed(
    Canvas canvas,
    String text,
    Color color,
    Offset offset,
    double scaleY,
  ) {
    if (text.isEmpty || color.a <= 0) return;
    canvas.save();
    canvas.translate(offset.dx, offset.dy + (_fontSize * 0.42 * (1 - scaleY)));
    canvas.scale(1, scaleY.clamp(0.2, 2.2));
    _paintRun(canvas, text, color, Offset.zero);
    canvas.restore();
  }

  void _paintRun(Canvas canvas, String text, Color color, Offset offset) {
    if (text.isEmpty || color.a <= 0) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _style(color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  TextStyle _style(Color color) {
    return TextStyle(
      color: color,
      fontSize: _fontSize,
      fontFamily: _fontFamily,
      height: _lineHeight,
    );
  }

  @override
  bool shouldRepaint(covariant _DiffMeltTextPainter oldDelegate) {
    return oldDelegate.fromText != fromText ||
        oldDelegate.toText != toText ||
        oldDelegate.fromColor != fromColor ||
        oldDelegate.toColor != toColor ||
        oldDelegate.progress != progress;
  }
}

class _ToolbarBtn extends StatefulWidget {
  final String icon;
  final bool active;
  final AppTokens t;
  final VoidCallback onTap;
  const _ToolbarBtn(
      {required this.icon,
      required this.active,
      required this.t,
      required this.onTap});
  @override
  State<_ToolbarBtn> createState() => _ToolbarBtnState();
}

class _ToolbarBtnState extends State<_ToolbarBtn> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: widget.active
                ? t.itemActiveBg
                : (_hov ? t.itemHoverBg : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
            border:
                widget.active ? Border.all(color: t.itemActiveBorder) : null,
          ),
          child: Center(
              child: AppIcon(
                  name: widget.icon,
                  size: 13,
                  color: widget.active ? t.accentBright : t.textMuted)),
        ),
      ),
    );
  }
}

// ── Hunk dropdown ─────────────────────────────────────────────────────────────

class _HunkDropdown extends StatelessWidget {
  final List<_HunkHeader> hunks;
  final AppTokens t;
  final ValueChanged<int> onJump;
  const _HunkDropdown(
      {required this.hunks, required this.t, required this.onJump});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Jump to change block. Git calls these hunks.',
      offset: const Offset(0, 28),
      color: t.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: t.chromeBorder.withValues(alpha: 0.3)),
      ),
      onSelected: onJump,
      itemBuilder: (_) => hunks
          .asMap()
          .entries
          .map((e) => PopupMenuItem<int>(
                value: e.key,
                height: 28,
                child: Text(
                  e.value.label,
                  style: TextStyle(
                      color: t.accentBright,
                      fontSize: 11,
                      fontFamily: 'JetBrainsMono'),
                ),
              ))
          .toList(),
      child: Container(
        child: AppInputShell(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          fillColor: t.itemHoverBg,
          borderColor: t.secondaryBtnBorder,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${hunks.length} change${hunks.length == 1 ? "" : "s"}',
                style: TextStyle(color: t.textMuted, fontSize: 10)),
            const SizedBox(width: 4),
            AppIcon(name: 'chevron-down', size: 10, color: t.textMuted),
          ]),
        ),
      ),
    );
  }
}
