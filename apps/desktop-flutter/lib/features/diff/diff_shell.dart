import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app/preferences_state.dart';
import '../../ui/motion.dart';
import '../../ui/material_surface.dart';
import '../../ui/morph_text.dart';
import '../../ui/form_controls.dart';
import '../../ui/status_view.dart';
import '../../ui/tokens.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../components/icons/app_icons.dart';
import '../../diagnostics/diagnostics_state.dart';
import 'diff_models.dart';
import 'patch_engine.dart';

// ── Data types (Moved to diff_models.dart) ────────────────────────────────────

class _AgeRange {
  final DateTime min;
  final DateTime max;
  const _AgeRange({required this.min, required this.max});
}

class _HunkHeader {
  final int lineIndex;
  final String label;
  const _HunkHeader(this.lineIndex, this.label);
}

// ── Parser ────────────────────────────────────────────────────────────────────

List<ParsedLine> _parseDiff(String diff) {
  final rawLines = diff.split('\n');
  final result = <ParsedLine>[];
  int oldLine = 0, newLine = 0, hunkIdx = -1;
  String? currentFile;

  final diffHeaderRe = RegExp(r'^diff --git a/(.+) b/(.+)$');
  for (final line in rawLines) {
    if (line.startsWith('diff --git')) {
      final m = diffHeaderRe.firstMatch(line);
      if (m != null) currentFile = m.group(2) ?? m.group(1);
      continue;
    }
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
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.hunk,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else if (line.startsWith('+') && !line.startsWith('+++')) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.added,
          lineNumNew: newLine++,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.deleted,
          lineNumOld: oldLine++,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else if (line.startsWith('\\')) {
      // Git's "\ No newline at end of file" marker. It's not a line of
      // content — it annotates the *previous* line (which is the final
      // line on its side of the diff and has no trailing newline). Pop
      // and re-push that line with the flag set so the patch engine can
      // reconstruct the marker on regeneration. Crucially, do NOT emit
      // a ParsedLine of our own: a prior version fell into the context
      // branch below and bumped `oldLine` / `newLine` for a line that
      // isn't real content, corrupting every subsequent hunk position.
      if (result.isNotEmpty) {
        final prev = result.removeLast();
        result.add(prev.copyWith(noNewlineAtEof: true));
      }
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
      result.add(ParsedLine(
          text: line, lowerText: line.toLowerCase(), kind: LineKind.meta,
          filePath: currentFile));
    } else if (line.isNotEmpty) {
      result.add(ParsedLine(
          text: line,
          lowerText: line.toLowerCase(),
          kind: LineKind.context,
          lineNumOld: oldLine++,
          lineNumNew: newLine++,
          hunkIndex: hunkIdx,
          filePath: currentFile));
    } else {
      result.add(ParsedLine(
          text: line,
          lowerText: '',
          kind: LineKind.context,
          hunkIndex: hunkIdx));
    }
  }

  return result;
}

List<_HunkHeader> _extractHunks(List<ParsedLine> lines) {
  final result = <_HunkHeader>[];
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].kind == LineKind.hunk) {
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

class _DiffFileHeader extends StatefulWidget {
  final String filePath;
  final String diffContent;
  final int hunkCount;
  final AppTokens tokens;
  final VoidCallback? onTapFilePath;
  final bool trailActive;

  const _DiffFileHeader({
    required this.filePath,
    required this.diffContent,
    required this.hunkCount,
    required this.tokens,
    this.onTapFilePath,
    this.trailActive = false,
  });

  @override
  State<_DiffFileHeader> createState() => _DiffFileHeaderState();
}

class _DiffFileHeaderState extends State<_DiffFileHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final directory = _diffDisplayDirectory(widget.filePath);
    final statusLabel = _diffStatusLabel(widget.diffContent);
    final hunkLabel = _changeBlockLabel(widget.hunkCount);
    final canTap = widget.onTapFilePath != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: t.chromeBorder.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onEnter: canTap ? (_) => setState(() => _hovered = true) : null,
            onExit: canTap ? (_) => setState(() => _hovered = false) : null,
            child: GestureDetector(
              onTap: widget.onTapFilePath,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Tooltip(
                      message: directory != null ? widget.filePath : '',
                      child: Text(
                        _diffDisplayName(widget.filePath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.trailActive
                              ? t.accentBright
                              : (_hovered ? t.accentBright : t.textStrong),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          decoration: _hovered ? TextDecoration.underline : null,
                          decorationColor: t.accentBright.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                  if (widget.trailActive) ...[
                    const SizedBox(width: 6),
                    Text(
                      '· trail',
                      style: TextStyle(
                        color: t.accentBright.withValues(alpha: 0.6),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.accentBright,
                ),
              ),
              const SizedBox(width: 8),
              ThemeMorphText(
                statusLabel,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 1,
                height: 9,
                color: t.chromeBorder.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 6),
              ThemeMorphText(
                hunkLabel,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
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

  /// When true, line-level staging gestures are enabled. Toggles are applied
  /// live to the index via `git apply --cached`. The parent is notified via
  /// [onStagingApplied] after a successful apply so it can refresh its diff
  /// and working-tree status.
  final bool enableStaging;

  /// Called after each successful live apply so the host can refresh its
  /// diff view and status. Not called on failure.
  final VoidCallback? onStagingApplied;

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
    this.enableStaging = false,
    this.onStagingApplied,
  });

  @override
  State<DiffShell> createState() => _DiffShellState();
}

class _DiffShellState extends State<DiffShell> {
  static const int _kAnimatedDiffMaxChangedLines = 24;
  static const int _kAnimatedDiffMaxPayloadBytes = 4 * 1024;
  static const Duration _kInitialFrameCaptureWindow = Duration(milliseconds: 1500);
  static const Duration _kBlameHoverDelay = Duration(milliseconds: 180);
  static const int _kModeAMaxChangedLines = 15000;
  static const int _kModeAMaxPayloadBytes = 3 * 1024 * 1024;
  static const Duration _kScrollFrameCaptureQuietWindow =
      Duration(milliseconds: 280);

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
  // Blame cache keyed by file path → line number → entry.
  // Supports multi-file diffs where each file has its own blame.
  final Map<String, Map<int, BlameLineData>> _blameByFile = {};
  final Set<String> _blameFetchedFiles = {};
  final Set<String> _blameFetchingFiles = {};
  bool _sessionFlushed = false;
  double? _sessionFirstPaintMs;
  DateTime? _lastScrollEventAt;
  String? _sessionDiffId;
  bool _sessionSearchActivated = false;
  bool _useAnimatedTextMode = false;
  int _sessionChangedLines = 0;
  int _sessionPayloadBytes = 0;
  List<ParsedLine> _displayLines = const [];
  Timer? _blameHoverTimer;
  Timer? _sessionFlushTimer;
  late final TimingsCallback _frameTimingsCallback;

  // Wear map (blame heatmap)
  bool _wearMapVisible = false;

  // Paper Trail (file history)
  bool _trailVisible = false;
  List<FileHistoryEntry> _trailHistory = const [];
  bool _trailLoading = false;
  String? _trailSelectedHash;
  String? _originalDiffContent;
  // Resolved file path AT the currently-selected trail commit. Tracks the
  // file's pre-rename name when viewing historical stops so diff/blame
  // queries use the correct path for that point in time.
  String? _trailSelectedPath;
  int? _hoveredLine; // the lineNumNew being hovered

  // Hunk navigation
  List<_HunkHeader> _hunks = [];
  List<ParsedLine> _lines = [];

  // Preference snapshots, refreshed every build so async callbacks
  // (blame hover timer) can read them without a BuildContext.
  bool _reduceMotion = false;
  bool _instantBlameHover = false;

  // ── Staging ────────────────────────────────────────────────────────────
  static const Duration _kApplyDebounce = Duration(milliseconds: 250);
  final FocusNode _stagingFocus = FocusNode(debugLabel: 'DiffShellStaging');
  Timer? _applyDebounce;
  bool _applying = false;
  String? _stagingError;
  int? _keyboardLineIndex; // index into _lines
  int? _lastToggledLineIndex; // for shift-range anchor (into _lines)

  // Paint-drag (press-and-drag over the stage column to paint multiple lines)
  bool _paintActive = false;
  bool _paintTargetStaged = false;
  final Set<String> _paintedKeys = {};

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
      _blameFetchedFiles.clear();
      _blameFetchingFiles.clear();
      _blameByFile.clear();
      _hoveredLine = null;
      // Reset trail state — the underlying diff changed, so any active
      // historical view is no longer meaningful.
      _trailVisible = false;
      _trailHistory = const [];
      _trailLoading = false;
      _trailSelectedHash = null;
      _trailSelectedPath = null;
      _originalDiffContent = null;
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
      // Capture existing stage state to re-hydrate after parse
      final stagedKeys =
          _lines.where((l) => l.isStaged).map((l) => l.stagingKey).toSet();

      final parsedLines = _parseDiff(widget.diffContent!);
      var newLines = widget.showFileHeader
          ? _trimLeadingMetaLines(parsedLines)
          : parsedLines;

      // Re-hydrate isStaged state
      if (stagedKeys.isNotEmpty) {
        newLines = newLines.map((l) {
          if (stagedKeys.contains(l.stagingKey)) {
            return l.copyWith(isStaged: true);
          }
          return l;
        }).toList();
      }

      _lines = newLines;
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
            line.kind == LineKind.added || line.kind == LineKind.deleted)
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
    _applyDebounce?.cancel();
    _stagingFocus.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_frameTimingsCallback);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _hScrollCtrl.dispose();
    super.dispose();
  }

  /// Build a cache key that includes the revision — blame at HEAD and blame
  /// at a historical commit are different data sets, and both can be viewed
  /// during a single DiffShell session when the Paper Trail is active.
  String _blameKey(String filePath, String? revision) =>
      revision == null ? filePath : '$filePath@$revision';

  Future<void> _loadBlame(String filePath, int lineNum) async {
    final repo = widget.repositoryPath;
    if (repo == null) return;
    // When viewing a historical stop via the Paper Trail, blame must be
    // computed AS OF that commit — otherwise hovering a line shows the
    // current-HEAD author instead of who last touched it at that point.
    // For renamed files, also use the path AT that commit (pre-rename).
    final revision = _trailSelectedHash;
    final queryPath = (revision != null && _trailSelectedPath != null)
        ? _trailSelectedPath!
        : filePath;
    final key = _blameKey(filePath, revision);
    if (_blameFetchedFiles.contains(key) ||
        _blameFetchingFiles.contains(key)) return;

    setState(() {
      _blameFetchingFiles.add(key);
      _hoveredLine = lineNum;
    });
    final r = await getFileBlame(repo, queryPath, commitRef: revision);
    if (!mounted) return;
    setState(() {
      _blameFetchingFiles.remove(key);
      _blameFetchedFiles.add(key);
      if (r.ok) {
        final map = <int, BlameLineData>{};
        for (final entry in r.data!) {
          map[entry.lineNumber] = entry;
        }
        _blameByFile[key] = map;
      }
    });
  }

  BlameLineData? _blameFor(String? filePath, int lineNum) {
    if (filePath == null) return null;
    return _blameByFile[_blameKey(filePath, _trailSelectedHash)]?[lineNum];
  }

  // ── Wear map ────────────────────────────────────────────────────────────

  Set<String> _uniqueFilePathsInDiff() {
    final paths = <String>{};
    for (final line in _lines) {
      final p = line.filePath;
      if (p != null && p.isNotEmpty) paths.add(p);
    }
    // Fallback for single-file diffs where parser didn't see a diff --git header.
    if (paths.isEmpty) paths.add(widget.filePath);
    return paths;
  }

  void _toggleWearMap() {
    if (widget.repositoryPath == null) return;
    setState(() => _wearMapVisible = !_wearMapVisible);
    if (_wearMapVisible) {
      _batchLoadWearBlame();
    }
  }

  /// Load blame for every file in the diff AS OF the current trail revision.
  /// Sequential (not concurrent) to avoid spawning a storm of `git blame`
  /// processes on large multi-file diffs. Bails if wear map is toggled off
  /// mid-load, or if the trail selection changes.
  Future<void> _batchLoadWearBlame() async {
    final revisionAtStart = _trailSelectedHash;
    for (final path in _uniqueFilePathsInDiff()) {
      if (!mounted) return;
      if (!_wearMapVisible) return;
      // If the user navigated the trail to a different revision while we
      // were loading, let the next scheduler handle it.
      if (_trailSelectedHash != revisionAtStart) return;
      final key = _blameKey(path, revisionAtStart);
      if (_blameFetchedFiles.contains(key) ||
          _blameFetchingFiles.contains(key)) continue;
      await _loadBlame(path, 0);
    }
  }

  // Cached per-file age range: oldest and newest authoredAt per file.
  // Invalidated whenever blame changes; recomputed lazily on access.
  Map<String, _AgeRange>? _ageRangesCache;
  int _ageRangesCacheKey = 0;

  Map<String, _AgeRange> _ageRangesByFile() {
    // Invalidate when the blame cache shape changes.
    final key = _blameByFile.length * 10000 +
        _blameByFile.values.fold<int>(0, (acc, m) => acc + m.length);
    if (_ageRangesCache != null && _ageRangesCacheKey == key) {
      return _ageRangesCache!;
    }
    final result = <String, _AgeRange>{};
    _blameByFile.forEach((path, lineMap) {
      DateTime? min;
      DateTime? max;
      for (final entry in lineMap.values) {
        try {
          final d = DateTime.parse(entry.authoredAt);
          if (min == null || d.isBefore(min)) min = d;
          if (max == null || d.isAfter(max)) max = d;
        } catch (_) {}
      }
      if (min != null && max != null) {
        result[path] = _AgeRange(min: min, max: max);
      }
    });
    _ageRangesCache = result;
    _ageRangesCacheKey = key;
    return result;
  }

  /// Returns 0 (newest) to 1 (oldest) for a line's wear intensity,
  /// or null if we can't resolve an age for it.
  double? _wearIntensityFor(String? filePath, int lineNum) {
    if (filePath == null) return null;
    final entry = _blameFor(filePath, lineNum);
    if (entry == null) return null;
    // Age ranges are cached by the same (file, revision) key as blame.
    final range = _ageRangesByFile()[_blameKey(filePath, _trailSelectedHash)];
    if (range == null) return null;
    try {
      final d = DateTime.parse(entry.authoredAt);
      final span = range.max.difference(range.min).inSeconds;
      if (span <= 0) return 0.0;
      final from = range.max.difference(d).inSeconds;
      return (from / span).clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  // Blame is loaded lazily per-file on hover, so the session caps
  // (intended to protect the diff renderer) don't need to gate it.
  // Only disable in animated text mode (where the diff is tiny and blame
  // hover would be weird) or when no repo path is available.
  bool get _canShowInlineBlame =>
      !_useAnimatedTextMode && widget.repositoryPath != null;

  void _scheduleBlameLoad(String filePath, int lineNum) {
    if (!_canShowInlineBlame) {
      return;
    }
    _blameHoverTimer?.cancel();
    final delay =
        _instantBlameHover ? Duration.zero : _kBlameHoverDelay;
    _blameHoverTimer = Timer(delay, () {
      if (!mounted || _hoveredLine != lineNum) {
        return;
      }
      _loadBlame(filePath, lineNum);
    });
  }

  // ── Staging orchestration ─────────────────────────────────────────────

  bool get _stagingEnabled =>
      widget.enableStaging && widget.repositoryPath != null;

  /// The staging cell (click target) is to the LEFT of the gutter.
  /// Width chosen to feel like a comfortable target without crowding
  /// the line number.
  static const double _stageCellWidth = 16.0;

  /// Height of every diff row. Used for paint-drag hit-testing.
  static const double _lineItemExtent = 18.0;

  /// Toggle staging on a single line (by its index in [_lines]). Optionally
  /// pair-aware: if [autoPair] is true and the line is part of a -/+
  /// replacement, the partner is toggled coherently to the same target
  /// state. Does NOT apply on its own — callers should schedule apply.
  void _setLineStaged(int index, bool staged, {bool autoPair = true}) {
    if (index < 0 || index >= _lines.length) return;
    final line = _lines[index];
    if (line.kind != LineKind.added && line.kind != LineKind.deleted) return;
    if (line.isStaged == staged) return;
    _lines[index] = line.copyWith(isStaged: staged);
    if (autoPair) {
      final pair = findReplacementPair(_lines, index);
      if (pair != null && _lines[pair].isStaged != staged) {
        _lines[pair] = _lines[pair].copyWith(isStaged: staged);
      }
    }
  }

  /// Click on the sigil of a single line. Supports shift-extend (range from
  /// the last toggled line) and alt (disable auto-pairing).
  void _handleSigilTap(
    ParsedLine line, {
    required bool shift,
    required bool alt,
  }) {
    final idx = _lines.indexWhere((l) => identical(l, line));
    if (idx < 0) return;
    final target = !_lines[idx].isStaged;

    setState(() {
      if (shift && _lastToggledLineIndex != null) {
        final anchor = _lastToggledLineIndex!;
        final a = math.min(anchor, idx);
        final b = math.max(anchor, idx);
        for (int i = a; i <= b; i++) {
          _setLineStaged(i, target, autoPair: !alt);
        }
      } else {
        _setLineStaged(idx, target, autoPair: !alt);
      }
      _lastToggledLineIndex = idx;
      _keyboardLineIndex = idx;
      _refreshDisplayLines();
    });
    _scheduleApply();
  }

  /// Double-click on a hunk header toggles every +/- line in that hunk.
  /// Target state = "stage all if any are unstaged, otherwise unstage all."
  void _handleHunkDoubleTap(int hunkIndex) {
    final inHunk = <int>[];
    for (int i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (l.hunkIndex != hunkIndex) continue;
      if (l.kind == LineKind.added || l.kind == LineKind.deleted) {
        inHunk.add(i);
      }
    }
    if (inHunk.isEmpty) return;
    final anyUnstaged = inHunk.any((i) => !_lines[i].isStaged);
    setState(() {
      for (final i in inHunk) {
        _setLineStaged(i, anyUnstaged, autoPair: false);
      }
      _refreshDisplayLines();
    });
    _scheduleApply();
  }

  /// Toggle every +/- line across the diff. Bound to F key.
  void _handleFileStageToggle() {
    final targetables = <int>[];
    for (int i = 0; i < _lines.length; i++) {
      final k = _lines[i].kind;
      if (k == LineKind.added || k == LineKind.deleted) targetables.add(i);
    }
    if (targetables.isEmpty) return;
    final anyUnstaged = targetables.any((i) => !_lines[i].isStaged);
    setState(() {
      for (final i in targetables) {
        _setLineStaged(i, anyUnstaged, autoPair: false);
      }
      _refreshDisplayLines();
    });
    _scheduleApply();
  }

  // ── Paint-drag ────────────────────────────────────────────────────────

  void _beginPaint(ParsedLine line) {
    final idx = _lines.indexWhere((l) => identical(l, line));
    if (idx < 0) return;
    _paintActive = true;
    _paintTargetStaged = !_lines[idx].isStaged;
    _paintedKeys
      ..clear()
      ..add(line.stagingKey);
    setState(() {
      _setLineStaged(idx, _paintTargetStaged);
      _lastToggledLineIndex = idx;
      _keyboardLineIndex = idx;
      _refreshDisplayLines();
    });
  }

  /// Paint-drag continues: hit-test against the display list using the
  /// pointer's global Y position. Only fires when [_paintActive].
  void _paintUpdate(Offset globalPosition) {
    if (!_paintActive) return;
    final box = _listViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    if (local.dy < 0 || local.dy > box.size.height) return;
    final scroll = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    final displayIndex = ((local.dy + scroll) / _lineItemExtent).floor();
    if (displayIndex < 0 || displayIndex >= _displayLines.length) return;
    final line = _displayLines[displayIndex];
    if (_paintedKeys.contains(line.stagingKey)) return;
    if (line.kind != LineKind.added && line.kind != LineKind.deleted) return;
    _paintedKeys.add(line.stagingKey);
    final idx = _lines.indexWhere((l) => identical(l, line));
    if (idx < 0) return;
    setState(() {
      _setLineStaged(idx, _paintTargetStaged);
      _lastToggledLineIndex = idx;
      _keyboardLineIndex = idx;
      _refreshDisplayLines();
    });
  }

  void _endPaint() {
    if (!_paintActive) return;
    _paintActive = false;
    _paintedKeys.clear();
    _scheduleApply();
  }

  final GlobalKey _listViewKey = GlobalKey();

  // ── Keyboard navigation ───────────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (!_stagingEnabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isShift =
        HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
            HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftRight);

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyJ) {
      _moveKeyboardCursor(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.keyK) {
      _moveKeyboardCursor(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space && _keyboardLineIndex != null) {
      final line = _lines[_keyboardLineIndex!];
      _handleSigilTap(line, shift: isShift, alt: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH && _keyboardLineIndex != null) {
      _handleHunkDoubleTap(_lines[_keyboardLineIndex!].hunkIndex);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _handleFileStageToggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveKeyboardCursor(int delta) {
    if (_lines.isEmpty) return;
    int start = _keyboardLineIndex ?? -1;
    int cur = start;
    for (int step = 0; step < _lines.length; step++) {
      cur += delta;
      if (cur < 0 || cur >= _lines.length) return;
      final k = _lines[cur].kind;
      if (k == LineKind.added || k == LineKind.deleted) {
        setState(() => _keyboardLineIndex = cur);
        _scrollToLine(_lines[cur]);
        return;
      }
    }
  }

  void _scrollToLine(ParsedLine line) {
    if (!_scrollCtrl.hasClients) return;
    final displayIdx = _displayLines.indexWhere(
      (l) => l.stagingKey == line.stagingKey,
    );
    if (displayIdx < 0) return;
    final targetY = displayIdx * _lineItemExtent;
    final viewH = _scrollCtrl.position.viewportDimension;
    final offset = _scrollCtrl.offset;
    if (targetY < offset) {
      _scrollCtrl.motionAnimateTo(targetY,
          context: context,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut);
    } else if (targetY > offset + viewH - _lineItemExtent) {
      _scrollCtrl.motionAnimateTo(targetY - viewH + _lineItemExtent * 2,
          context: context,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut);
    }
  }

  // ── Live apply ────────────────────────────────────────────────────────

  void _scheduleApply() {
    if (!_stagingEnabled) return;
    _applyDebounce?.cancel();
    _applyDebounce = Timer(_kApplyDebounce, _runApply);
  }

  Future<void> _runApply() async {
    if (!_stagingEnabled || _applying) {
      if (_applying) _scheduleApply();
      return;
    }
    final repo = widget.repositoryPath!;
    // Group lines by file path so multi-file diffs apply per-file.
    final byFile = <String, List<ParsedLine>>{};
    for (final line in _lines) {
      final path = line.filePath ?? widget.filePath;
      byFile.putIfAbsent(path, () => []).add(line);
    }

    // Snapshot for rollback on failure.
    final snapshot = _lines.map((l) => l.isStaged).toList(growable: false);

    _applying = true;
    String? firstError;
    for (final entry in byFile.entries) {
      final patch = PatchEngine.buildStagedPatch(entry.key, entry.value);
      final r = await applyFileStaging(repo, entry.key, patch);
      if (!r.ok) {
        firstError = r.error ?? 'git apply failed';
        break;
      }
    }
    _applying = false;
    if (!mounted) return;

    if (firstError != null) {
      // Rollback optimistic toggles.
      setState(() {
        for (int i = 0; i < _lines.length && i < snapshot.length; i++) {
          if (_lines[i].isStaged != snapshot[i]) {
            _lines[i] = _lines[i].copyWith(isStaged: snapshot[i]);
          }
        }
        _stagingError = firstError;
        _refreshDisplayLines();
      });
      return;
    }

    if (_stagingError != null) {
      setState(() => _stagingError = null);
    }
    widget.onStagingApplied?.call();
  }

  void _refreshDisplayLines() {
    final sourceLines =
        widget.showFileHeader ? _trimLeadingMetaLines(_lines) : _lines;
    
    // Un-staged lines are no longer filtered out completely. They remain in the UI
    // and visually dim, allowing users to tap/drag them again to un-stage.
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

  List<ParsedLine> _trimLeadingMetaLines(List<ParsedLine> lines) {
    var firstContentIndex = 0;
    while (firstContentIndex < lines.length &&
        lines[firstContentIndex].kind == LineKind.meta) {
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
      _scrollCtrl.motionAnimateTo(
        targetOffset,
        context: context,
        duration: context.surfaceShader.duration,
        curve: context.surfaceShader.safeCurve,
      );
    });
  }

  // ── Paper Trail ────────────────────────────────────────────────────────

  // Regex matches our own synthetic multi-file label: "N selected files".
  static final RegExp _multiFileLabelRe = RegExp(r'^\d+ selected files?$');

  /// Returns the single file path the trail should operate on, or null
  /// if this DiffShell is showing a multi-file diff, a synthetic label
  /// (like a stash peek), or otherwise can't unambiguously identify one file.
  String? _resolvedTrailFilePath() {
    final paths = _uniqueFilePathsInDiff();
    if (paths.length != 1) return null;
    final only = paths.first;
    // Reject known synthetic labels the app produces when there's no real
    // single file to point at. Real paths with spaces (e.g. "My Docs/file.md")
    // are valid and pass through.
    if (_multiFileLabelRe.hasMatch(only)) return null;
    if (only.startsWith('filed:')) return null;
    return only;
  }

  void _toggleTrail() {
    if (_trailVisible) {
      // Collapse trail, restore the original (working) diff content
      // by re-parsing it back into the visible lines.
      final original = _originalDiffContent;
      setState(() {
        _trailVisible = false;
        _trailHistory = const [];
        _trailSelectedHash = null;
        _trailSelectedPath = null;
        _originalDiffContent = null;
        if (original != null) {
          _reparse(original);
        }
      });
      return;
    }
    final repo = widget.repositoryPath;
    if (repo == null) return;
    final trailPath = _resolvedTrailFilePath();
    if (trailPath == null) return;
    setState(() {
      _trailVisible = true;
      _trailLoading = true;
      _originalDiffContent = widget.diffContent;
    });
    listFileHistoryWithPaths(repo, trailPath).then((result) {
      if (!mounted) return;
      setState(() {
        _trailLoading = false;
        _trailHistory = result.ok ? result.data! : const [];
      });
    });
  }

  void _selectTrailStop(String commitHash) {
    final repo = widget.repositoryPath;
    if (repo == null) return;
    // Resolve the path AT this historical commit — critical for renames:
    // a commit from before the rename must be queried with the old name.
    final historyEntry = _trailHistory.firstWhere(
      (e) => e.commit.commitHash == commitHash,
      orElse: () => FileHistoryEntry(
        commit: CommitHistoryEntry(
          commitHash: '', shortHash: '', parentHashes: const [],
          refNames: const [], isMerge: false, subject: '',
          authorName: '', authorEmail: '', authoredAt: '',
        ),
        pathAtRevision: _resolvedTrailFilePath() ?? widget.filePath,
      ),
    );
    final pathAt = historyEntry.pathAtRevision;
    // Snapshot the previous selection so we can roll back on failure —
    // avoids the UI showing a selected hash whose diff never loaded.
    final previousHash = _trailSelectedHash;
    final previousPath = _trailSelectedPath;
    setState(() {
      _trailSelectedHash = commitHash;
      _trailSelectedPath = pathAt;
    });
    getFileDiffAtRevision(repo, pathAt, commitHash).then((result) {
      if (!mounted || _trailSelectedHash != commitHash) return;
      if (result.ok) {
        setState(() {
          _reparse(result.data!);
        });
        // Wear map is keyed by revision — if it's active, kick off a
        // blame load for the new revision so the heatmap stays populated
        // instead of blanking out until the user hovers each line.
        if (_wearMapVisible) {
          _batchLoadWearBlame();
        }
      } else {
        // Fetch failed — revert the selection so the strip and diff stay
        // in sync. The diff content remains whatever was last visible.
        setState(() {
          _trailSelectedHash = previousHash;
          _trailSelectedPath = previousPath;
        });
      }
    });
  }

  void _selectTrailNow() {
    setState(() {
      _trailSelectedHash = null;
      _trailSelectedPath = null;
      if (_originalDiffContent != null) {
        _reparse(_originalDiffContent!);
      }
    });
    // Re-populate wear map against HEAD (key null) when returning to "now".
    if (_wearMapVisible) {
      _batchLoadWearBlame();
    }
  }

  void _reparse(String content) {
    final parsed = _parseDiff(content);
    _lines = widget.showFileHeader ? _trimLeadingMetaLines(parsed) : parsed;
    _hunks = _extractHunks(_lines);
    _refreshDisplayLines();
    _computeMaxLineWidth();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final prefs = context.watch<PreferencesState>();
    // Cache prefs so async methods (blame hover timer) can read them without
    // needing a BuildContext. Overwrite on every build so pref changes
    // propagate immediately.
    _reduceMotion = prefs.reduceMotion;
    _instantBlameHover = prefs.instantBlameHover;
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
            // Trail only works when we can unambiguously resolve a single
            // real file path — disables itself for multi-file diffs, stash
            // peeks, and other synthetic filePath views.
            onTapFilePath:
                (widget.repositoryPath != null && _resolvedTrailFilePath() != null)
                    ? _toggleTrail
                    : null,
            trailActive: _trailVisible,
          ),
        // ── Paper trail strip ───────────────────────────────────────────
        if (_trailVisible)
          _TrailStrip(
            tokens: t,
            history: _trailHistory,
            loading: _trailLoading,
            selectedHash: _trailSelectedHash,
            onSelectStop: _selectTrailStop,
            onSelectNow: _selectTrailNow,
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

            // Blame / wear map indicator (click toggles wear map)
            if (_blameFetchingFiles.isNotEmpty)
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
            if (_canShowInlineBlame && _blameFetchingFiles.isEmpty)
              Tooltip(
                message: _wearMapVisible
                    ? 'wear map on — click to hide'
                    : 'show wear map (activity heatmap)',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _toggleWearMap,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        _wearMapVisible ? 'wear · on' : 'blame',
                        style: TextStyle(
                          color: _wearMapVisible
                              ? t.hyperChromatic1
                              : (_blameByFile.isNotEmpty
                                  ? t.hyperChromatic1.withValues(alpha: 0.7)
                                  : t.textMuted),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),

        // ── Diff lines ────────────────────────────────────────────────────
        Expanded(
          child: Focus(
            focusNode: _stagingFocus,
            onKeyEvent: _handleKey,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _stagingEnabled ? () => _stagingFocus.requestFocus() : null,
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: true),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Content is at least as wide as the viewport so there's
                    // no unnecessary horizontal scroll when lines are short.
                    final contentWidth = _maxLineWidth > constraints.maxWidth
                        ? _maxLineWidth
                        : constraints.maxWidth;
                    return SingleChildScrollView(
                      controller: _hScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: contentWidth,
                        child: ListView.builder(
                          key: _listViewKey,
                          controller: _searchVisible ? null : _scrollCtrl,
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: displayLines.length,
                          itemExtent: _lineItemExtent,
                          itemBuilder: (ctx, i) {
                            final line = displayLines[i];
                            final lineFile = line.filePath ?? widget.filePath;
                            final kbFocused = _stagingEnabled &&
                                _keyboardLineIndex != null &&
                                _keyboardLineIndex! >= 0 &&
                                _keyboardLineIndex! < _lines.length &&
                                identical(_lines[_keyboardLineIndex!], line);
                            return _DiffLine(
                              key: ValueKey(line),
                              line: line,
                              tokens: t,
                              blameEntry: line.lineNumNew != null
                                  ? _blameFor(lineFile, line.lineNumNew!)
                                  : null,
                              hovered: _hoveredLine == line.lineNumNew &&
                                  line.lineNumNew != null,
                              onGutterEnter: _canShowInlineBlame &&
                                      line.lineNumNew != null
                                  ? () {
                                      setState(() =>
                                          _hoveredLine = line.lineNumNew!);
                                      _scheduleBlameLoad(
                                          lineFile, line.lineNumNew!);
                                    }
                                  : null,
                              onGutterExit: () {
                                _blameHoverTimer?.cancel();
                                setState(() => _hoveredLine = null);
                              },
                              searchTerm: _searchTerm,
                              useAnimatedTextMode:
                                  _useAnimatedTextMode && !_reduceMotion,
                              wearIntensity: _wearMapVisible &&
                                      line.lineNumNew != null
                                  ? _wearIntensityFor(
                                      lineFile, line.lineNumNew!)
                                  : null,
                              stageCellWidth: _stageCellWidth,
                              stagingEnabled: _stagingEnabled,
                              keyboardFocused: kbFocused,
                              onSigilTap: _stagingEnabled
                                  ? (shift, alt) {
                                      _stagingFocus.requestFocus();
                                      _handleSigilTap(line,
                                          shift: shift, alt: alt);
                                    }
                                  : null,
                              onPaintStart: _stagingEnabled
                                  ? () {
                                      _stagingFocus.requestFocus();
                                      _beginPaint(line);
                                    }
                                  : null,
                              onPaintMove:
                                  _stagingEnabled ? _paintUpdate : null,
                              onPaintEnd: _stagingEnabled ? _endPaint : null,
                              onHunkDoubleTap: _stagingEnabled
                                  ? () {
                                      _stagingFocus.requestFocus();
                                      _handleHunkDoubleTap(line.hunkIndex);
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (_stagingError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: t.stateDeleted.withValues(alpha: 0.12),
            child: Text(
              'Partial stage failed: $_stagingError',
              style: TextStyle(
                color: t.stateDeleted,
                fontSize: 10.5,
                fontFamily: 'JetBrainsMono',
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

class _DiffLine extends StatefulWidget {
  final ParsedLine line;
  final AppTokens tokens;
  final BlameLineData? blameEntry;
  final bool hovered;
  final VoidCallback? onGutterEnter;
  final VoidCallback onGutterExit;
  final String searchTerm;
  final bool useAnimatedTextMode;
  final double? wearIntensity;

  // Staging
  final double stageCellWidth;
  final bool stagingEnabled;
  final bool keyboardFocused;

  /// Tap on the stage sigil. Booleans carry shift/alt modifier state.
  final void Function(bool shift, bool alt)? onSigilTap;

  /// Vertical drag started on the stage sigil of this line — paint mode.
  final VoidCallback? onPaintStart;
  final void Function(Offset globalPosition)? onPaintMove;
  final VoidCallback? onPaintEnd;

  /// Double-click on the hunk header row — toggles the whole hunk.
  final VoidCallback? onHunkDoubleTap;

  const _DiffLine({
    Key? key,
    required this.line,
    required this.tokens,
    required this.blameEntry,
    required this.hovered,
    required this.onGutterEnter,
    required this.onGutterExit,
    required this.searchTerm,
    required this.useAnimatedTextMode,
    this.wearIntensity,
    this.stageCellWidth = 16.0,
    this.stagingEnabled = false,
    this.keyboardFocused = false,
    this.onSigilTap,
    this.onPaintStart,
    this.onPaintMove,
    this.onPaintEnd,
    this.onHunkDoubleTap,
  }) : super(key: key);

  @override
  State<_DiffLine> createState() => _DiffLineState();
}

class _DiffLineState extends State<_DiffLine> {
  /// Hover anywhere across the left click zone (ribbon + sigil + gutter).
  /// Drives the sigil's hover-border affordance so the whole margin reads
  /// as clickable.
  bool _lineHover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final l = widget.line;
    final isMeta = l.kind == LineKind.meta;
    final isAdded = l.kind == LineKind.added;
    final isDeleted = l.kind == LineKind.deleted;
    final isHunk = l.kind == LineKind.hunk;
    final isStageable = isAdded || isDeleted;

    // Tint strength: staged lines get a slightly stronger wash so their
    // membership is unmistakable without dimming text contrast.
    final double tintAlpha = l.isStaged ? 0.18 : 0.10;

    Color? lineBg;
    Color textColor;
    Color sigilColor = t.textMuted;

    switch (l.kind) {
      case LineKind.added:
        lineBg = t.stateAdded.withValues(alpha: tintAlpha);
        textColor = t.stateAdded;
        sigilColor = t.stateAdded;
        break;
      case LineKind.deleted:
        lineBg = t.stateDeleted.withValues(alpha: tintAlpha);
        textColor = t.stateDeleted;
        sigilColor = t.stateDeleted;
        break;
      case LineKind.hunk:
        lineBg = t.chromeAccent.withValues(alpha: 0.07);
        textColor = t.accentBright;
        break;
      case LineKind.meta:
        lineBg = t.surface0.withValues(alpha: 0.18);
        textColor = t.textMuted.withValues(alpha: 0.72);
        break;
      case LineKind.context:
        lineBg = null;
        textColor = t.textNormal;
        break;
    }

    // Build gutter text (old | new line numbers or hunk marker)
    String gutterText = '';
    if (isHunk) {
      gutterText = '···';
    } else if (isAdded) {
      gutterText = l.lineNumNew != null ? '${l.lineNumNew}' : '';
    } else if (isDeleted) {
      gutterText = l.lineNumOld != null ? '${l.lineNumOld}' : '';
    } else if (l.kind == LineKind.context) {
      gutterText = l.lineNumNew != null ? '${l.lineNumNew}' : '';
    }

    // Wear map: theme-chromatic gradient from hypercubePositive (newest)
    // toward hypercubeNegative (oldest). Alpha scales by intensity so ancient
    // lines fade out while recent ones glow in the theme's warm tone.
    Color? wearBg;
    if (widget.wearIntensity != null && !isMeta && !isHunk) {
      wearBg = Color.lerp(
        t.hypercubePositive.withValues(alpha: 0.32),
        t.hypercubeNegative.withValues(alpha: 0.08),
        widget.wearIntensity!,
      );
    }

    final Color gutterBg = widget.hovered
        ? t.accentBright.withValues(alpha: 0.06)
        : isMeta
            ? Colors.transparent
            : (wearBg ??
                (lineBg?.withValues(alpha: 0.6) ??
                    t.surface1.withValues(alpha: 0.5)));

    final gutterCell = Container(
      width: isMeta ? 40 : 56,
      padding: const EdgeInsets.only(right: 8),
      alignment: Alignment.centerRight,
      color: gutterBg,
      child: Text(
        gutterText,
        style: TextStyle(
          color: widget.hovered
              ? (widget.blameEntry != null
                  ? t.hyperChromatic1.withValues(alpha: 0.9)
                  : t.textMuted)
              : t.textMuted.withValues(alpha: 0.5),
          fontSize: 10,
          fontFamily: 'JetBrainsMono',
        ),
      ),
    );
    final gutterContent = widget.onGutterEnter == null && !widget.hovered
        ? gutterCell
        : MouseRegion(
            onEnter: widget.onGutterEnter != null
                ? (_) => widget.onGutterEnter!()
                : null,
            onExit: (_) => widget.onGutterExit(),
            cursor: widget.onGutterEnter != null
                ? SystemMouseCursors.cell
                : MouseCursor.defer,
            child: gutterCell,
          );

    final useAnimatedText = widget.useAnimatedTextMode &&
        widget.searchTerm.isEmpty &&
        l.text.length <= 160 &&
        (isAdded || isDeleted || isHunk);
    final textChild = useAnimatedText
        ? _DiffMeltText(
            text: l.text,
            color: textColor,
          )
        : _buildPlainDiffText(
            l.text.isEmpty ? ' ' : l.text,
            textColor,
            t,
            widget.searchTerm,
            fontSize: isMeta ? 11 : 12,
            height: isMeta ? 1.3 : 1.5,
          );

    // ── Stage sigil column ────────────────────────────────────────────
    // The sigil itself is drag-only (paint mode). Click is handled by the
    // outer zone below so the whole left margin is one generous hit target.
    final Widget stageCell = widget.stagingEnabled
        ? SizedBox(
            width: widget.stageCellWidth,
            child: isStageable
                ? _StageSigil(
                    tokens: t,
                    kind: l.kind,
                    staged: l.isStaged,
                    hovered: _lineHover,
                    color: sigilColor,
                    onPaintStart: () => widget.onPaintStart?.call(),
                    onPaintMove: (g) => widget.onPaintMove?.call(g),
                    onPaintEnd: () => widget.onPaintEnd?.call(),
                  )
                : const SizedBox.shrink(),
          )
        : const SizedBox.shrink();

    Widget lineContent = Expanded(
      child: Container(
        color: lineBg,
        padding: EdgeInsets.symmetric(horizontal: isMeta ? 12 : 8),
        alignment: Alignment.centerLeft,
        child: textChild,
      ),
    );

    // Left ribbon: a solid 2px stripe at the very edge marking staged lines.
    // Keeps staged lines legible at full contrast — no opacity dimming.
    final bool showStageChrome = widget.stagingEnabled;
    final Color ribbonColor = l.isStaged
        ? (isAdded ? t.stateAdded : t.stateDeleted)
        : Colors.transparent;
    final Widget ribbon = showStageChrome
        ? (widget.keyboardFocused
            ? Container(
                width: 2,
                decoration: BoxDecoration(
                  color: t.accentBright,
                  boxShadow: [
                    BoxShadow(
                      color: t.accentBright.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              )
            : Container(width: 2, color: ribbonColor))
        : const SizedBox.shrink();

    // Left margin — ribbon + sigil + line number — is one generous click
    // zone for stageable lines. Clicking anywhere toggles stage with
    // shift/alt modifier awareness. Paint-drag is still owned by the
    // sigil cell itself so vertical scroll keeps working when you grab
    // the gutter on non-stageable lines.
    final leftCells = [
      SizedBox(height: 18, child: ribbon),
      stageCell,
      gutterContent,
    ];
    final bool leftInteractive =
        widget.stagingEnabled && isStageable && widget.onSigilTap != null;
    final Widget leftZone = leftInteractive
        ? MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _lineHover = true),
            onExit: (_) => setState(() => _lineHover = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (_) {
                final isShift = HardwareKeyboard.instance
                        .isLogicalKeyPressed(
                            LogicalKeyboardKey.shiftLeft) ||
                    HardwareKeyboard.instance.isLogicalKeyPressed(
                        LogicalKeyboardKey.shiftRight);
                final isAlt = HardwareKeyboard.instance
                        .isLogicalKeyPressed(LogicalKeyboardKey.altLeft) ||
                    HardwareKeyboard.instance
                        .isLogicalKeyPressed(LogicalKeyboardKey.altRight);
                widget.onSigilTap!(isShift, isAlt);
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: leftCells,
              ),
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: leftCells,
          );

    final baseRow = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [leftZone, lineContent],
    );

    // Double-click on hunk header toggles the hunk.
    final Widget interactiveRow = isHunk && widget.onHunkDoubleTap != null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.onHunkDoubleTap,
            child: baseRow,
          )
        : baseRow;

    // Blame annotation overlay — shown inline left of gutter on hover.
    final showBlame = widget.hovered && widget.blameEntry != null;
    if (!showBlame) return interactiveRow;

    final b = widget.blameEntry!;
    final initial =
        b.authorName.isNotEmpty ? b.authorName[0].toUpperCase() : '?';
    final timeStr = _formatBlameTime(b.authoredAt);
    final hue = (b.authorName.codeUnits.fold(0, (a, c) => a + c) * 37) % 360;
    final authorColor =
        HSLColor.fromAHSL(1.0, hue.toDouble(), 0.55, 0.55).toColor();

    return Stack(clipBehavior: Clip.none, children: [
      interactiveRow,
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: IgnorePointer(
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
                      color: t.hyperChromatic1.withValues(alpha: 0.4),
                      width: 2),
                ),
              ),
              child: Row(children: [
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
                    child: Text(
                  '${b.shortHash} · $timeStr',
                  style: TextStyle(
                    color: t.hyperChromatic1,
                    fontSize: 9,
                    fontFamily: 'JetBrainsMono',
                  ),
                  overflow: TextOverflow.ellipsis,
                )),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ── Stage sigil ──────────────────────────────────────────────────────────────
//
// The only staging affordance: a click target on the left of every +/- line.
// Shows a filled glyph when staged, outlined when not. Tap = toggle. Vertical
// drag = paint across multiple lines. Shift+tap = extend range from the last
// toggled line; Alt+tap = disable auto-pairing of replacement -/+ lines.

class _StageSigil extends StatelessWidget {
  final AppTokens tokens;
  final LineKind kind;
  final bool staged;
  final bool hovered;
  final Color color;
  final VoidCallback onPaintStart;
  final void Function(Offset globalPosition) onPaintMove;
  final VoidCallback onPaintEnd;

  const _StageSigil({
    required this.tokens,
    required this.kind,
    required this.staged,
    required this.hovered,
    required this.color,
    required this.onPaintStart,
    required this.onPaintMove,
    required this.onPaintEnd,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = kind == LineKind.added ? '+' : '−';
    final Color effective = hovered || staged
        ? color
        : color.withValues(alpha: 0.55);

    // Hover border — crisp 1px ring around the sigil glyph that says
    // "this is a button." Only when the left zone is hovered AND the line
    // isn't already staged (filled dot already carries its own weight).
    final Border? hoverBorder = (hovered && !staged)
        ? Border.all(color: color.withValues(alpha: 0.75), width: 1)
        : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => onPaintStart(),
      onVerticalDragUpdate: (d) => onPaintMove(d.globalPosition),
      onVerticalDragEnd: (_) => onPaintEnd(),
      onVerticalDragCancel: () => onPaintEnd(),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: staged ? color.withValues(alpha: 0.10) : Colors.transparent,
            border: hoverBorder,
            borderRadius: BorderRadius.circular(3),
          ),
          child: staged
              // Filled dot: unmistakable "this is in."
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: effective,
                  ),
                )
              : Text(
                  glyph,
                  style: TextStyle(
                    color: effective,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'JetBrainsMono',
                    height: 1.0,
                  ),
                ),
        ),
      ),
    );
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

// ── Paper Trail strip ─────────────────────────────────────────────────────

/// A horizontal node-style rail for the file's commit history.
/// Mirrors the visual language of `_MultiDiffProgressRail` in changes_page —
/// a baseline with evenly-spaced dots, a halo marker on the selected stop.
/// Index 0 is "now" (current working state), then each commit newest → oldest.
class _TrailStrip extends StatelessWidget {
  final AppTokens tokens;
  final List<FileHistoryEntry> history;
  final bool loading;
  final String? selectedHash;
  final ValueChanged<String> onSelectStop;
  final VoidCallback onSelectNow;

  const _TrailStrip({
    required this.tokens,
    required this.history,
    required this.loading,
    required this.selectedHash,
    required this.onSelectStop,
    required this.onSelectNow,
  });

  String _relativeDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().difference(date);
      if (diff.inDays > 365) return '${diff.inDays ~/ 365}y';
      if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo';
      if (diff.inDays > 0) return '${diff.inDays}d';
      if (diff.inHours > 0) return '${diff.inHours}h';
      return '${diff.inMinutes}m';
    } catch (_) {
      return '';
    }
  }

  int get _currentIndex {
    if (selectedHash == null) return 0; // "now"
    final idx =
        history.indexWhere((e) => e.commit.commitHash == selectedHash);
    return idx < 0 ? 0 : idx + 1;
  }

  String? _currentLabel() {
    if (loading) return 'loading trail...';
    if (history.isEmpty) return 'no history found';
    if (selectedHash == null) return 'now · working copy';
    final entry = history.firstWhere(
      (e) => e.commit.commitHash == selectedHash,
      orElse: () => history.first,
    );
    final c = entry.commit;
    final rel = _relativeDate(c.authoredAt);
    return '${c.shortHash} · ${c.authorName} · $rel · ${c.subject}';
  }

  void _selectByIndex(int index) {
    if (index == 0) {
      onSelectNow();
    } else {
      final i = (index - 1).clamp(0, history.length - 1);
      onSelectStop(history[i].commit.commitHash);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final total = history.length + 1; // +1 for "now"

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      decoration: BoxDecoration(
        color: t.bg0.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currentLabel() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!loading && history.isNotEmpty) ...[
            const SizedBox(height: 4),
            _TrailRail(
              tokens: t,
              total: total,
              currentIndex: _currentIndex,
              onSelectIndex: _selectByIndex,
            ),
          ],
        ],
      ),
    );
  }
}

class _TrailRail extends StatelessWidget {
  final AppTokens tokens;
  final int total;
  final int currentIndex;
  final ValueChanged<int> onSelectIndex;

  const _TrailRail({
    required this.tokens,
    required this.total,
    required this.currentIndex,
    required this.onSelectIndex,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _selectFromOffset(d.localPosition.dx, width),
            onHorizontalDragStart: (d) =>
                _selectFromOffset(d.localPosition.dx, width),
            onHorizontalDragUpdate: (d) =>
                _selectFromOffset(d.localPosition.dx, width),
            child: SizedBox(
              width: width,
              height: 22,
              child: CustomPaint(
                size: Size(width, 22),
                painter: _TrailRailPainter(
                  tokens: tokens,
                  total: total,
                  currentIndex: currentIndex,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectFromOffset(double localDx, double width) {
    if (total <= 0) return;
    const horizontalInset = 6.0;
    final usable = (width - horizontalInset * 2).clamp(1.0, double.infinity);
    final ratio = ((localDx - horizontalInset) / usable).clamp(0.0, 1.0);
    final index = total == 1 ? 0 : (ratio * (total - 1)).round();
    onSelectIndex(index);
  }
}

class _TrailRailPainter extends CustomPainter {
  final AppTokens tokens;
  final int total;
  final int currentIndex;

  const _TrailRailPainter({
    required this.tokens,
    required this.total,
    required this.currentIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;

    const horizontalInset = 6.0;
    final left = horizontalInset;
    final right = size.width - horizontalInset;
    final centerY = size.height / 2;
    final usableWidth = right - left;
    final progress = total == 1 ? 0.0 : currentIndex / (total - 1);
    final markerX = left + usableWidth * progress.clamp(0.0, 1.0);

    final baseRail = Paint()
      ..color = tokens.chromeBorderStrong
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, centerY), Offset(right, centerY), baseRail);

    // Cap the visible dot count so huge histories don't clutter the rail.
    final sampleCount = total < 2
        ? 1
        : total > 44
            ? 44
            : total;

    for (var i = 0; i < sampleCount; i++) {
      final ratio = sampleCount == 1 ? 0.0 : i / (sampleCount - 1);
      final representedIndex =
          sampleCount == 1 ? currentIndex : (ratio * (total - 1)).round();
      final x = left + usableWidth * ratio;
      final isCurrent = representedIndex == currentIndex;
      // "now" (index 0) gets a slightly brighter base color to distinguish it.
      final isNow = representedIndex == 0;
      final radius = isCurrent ? 4.5 : (isNow ? 3.2 : 2.4);
      final fill = Paint()
        ..color = isCurrent
            ? tokens.accentBright
            : (isNow
                ? tokens.accentBright.withValues(alpha: 0.55)
                : tokens.textMuted.withValues(alpha: 0.24));
      canvas.drawCircle(Offset(x, centerY), radius, fill);
    }

    final halo = Paint()
      ..color = tokens.accentBright.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final ring = Paint()
      ..color = tokens.accentBright.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(markerX, centerY), 7.5, halo);
    canvas.drawCircle(Offset(markerX, centerY), 6.2, ring);
  }

  @override
  bool shouldRepaint(covariant _TrailRailPainter old) {
    return old.total != total ||
        old.currentIndex != currentIndex ||
        old.tokens != tokens;
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
