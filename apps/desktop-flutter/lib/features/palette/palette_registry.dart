import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/ai_activity_state.dart';
import '../../app/build_info.dart';
import '../../app/desk_pr_state.dart';
import '../../app/external_tools_state.dart';
import '../../app/logos_git_state.dart';
import '../../app/preferences_state.dart';
import '../../app/repository_state.dart';
import '../../app/repository_xray_state.dart';
import '../../app/theme_state.dart';
import '../../app/worktree_state.dart';
import '../../backend/dtos.dart';
import '../../backend/external_tools.dart';
import '../../backend/git.dart' as git;
import '../changes/merge_conflict_editor.dart';
import '../history_surgery/history_surgery_page.dart';
import '../../backend/logos_git.dart';
import '../../backend/repo_web_url.dart';
import '../../backend/system_paths.dart';
import '../../backend/undo_controller.dart';
import '../../components/icons/app_icons.dart';
import '../../ui/design_primitives.dart';
import '../../ui/tokens.dart';
import 'palette_entry.dart';

typedef PaletteCallbacks = ({
  void Function(int mode) onModeChanged,
  void Function() onOpenXray,
  void Function() onOpenSettings,
  void Function() onRefresh,
  void Function() onUndo,
  void Function(String path) onRepoSwitch,
  void Function(String path) onDeskSwitch,
  void Function(String url) onOpenBrowser,
});

List<PaletteEntry> buildStaticEntries(
  BuildContext context,
  PaletteCallbacks callbacks, {
  Map<String, String> forgeByPath = const {},
}) {
  final prefs = context.read<PreferencesState>();
  final theme = context.read<ThemeState>();
  final repo = context.read<RepositoryState>();
  final worktrees = context.read<WorktreeState>();
  final tools = context.read<ExternalToolsState>();
  final undo = context.read<UndoCoordinator>();
  final aiActivity = context.read<AiActivityState>();
  final deskPr = context.read<DeskPrState>();
  final logosState = context.read<LogosGitState>();
  final xrayState = context.read<RepositoryXrayState>();
  final repoPath = repo.activePath;
  final status = repo.status;
  final engine = repoPath != null ? logosState.engineFor(repoPath) : null;

  return [
    if (engine != null) ..._predictiveEntries(engine),
    if (engine != null) ..._topTouchedEntries(engine),
    if (engine != null && status != null) ..._coherenceEntry(engine, status),
    if (repoPath != null) ..._keystoneEntries(xrayState, repoPath),
    ..._repoEntries(repo, callbacks, forgeByPath),
    ..._repoSubEntries(repo, aiActivity, prefs.hideAiFeatures, callbacks),
    ..._deskEntries(worktrees, repo, callbacks),
    if (repoPath != null)
      ..._actionEntries(repoPath, status, callbacks),
    if (repoPath != null) ..._externalToolEntries(tools, repoPath),
    if (repoPath != null) ..._gitCommandEntries(repoPath, status, callbacks),
    if (repoPath != null)
      ..._prEntries(deskPr, status?.branch, callbacks),
    if (repoPath != null)
      ..._aiEntries(aiActivity, repoPath, prefs.hideAiFeatures, callbacks),
    ..._undoEntry(undo, callbacks),
    ..._navigationEntries(callbacks),
    ..._settingToggleEntries(prefs),
    ..._themeEntries(theme),
    ..._infoEntries(),
    if (repoPath != null)
      PaletteEntry(
        id: 'dev.test-merge-editor',
        label: 'Test Merge Editor',
        keywords: const ['conflict', 'merge', 'resolve', 'debug', 'dev'],
        chipLabel: 'DEV',
        chipTone: ChipTone.chromatic2,
        category: PaletteCategory.command,
        actionType: PaletteActionType.execute,
        onExecute: () {
          final rp = repoPath!;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (ctx) => _TestMergeEditorLoader(
              repoPath: rp,
            ),
          ));
        },
      ),
    PaletteEntry(
      id: 'debug.theme-specimen',
      label: 'Theme Specimen',
      subtitle: 'All colors, icons, text tiers, and geometry',
      keywords: const ['debug', 'theme', 'specimen', 'colors', 'icons', 'tokens', 'palette'],
      chipLabel: 'DEBUG',
      chipTone: ChipTone.muted,
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      onExecute: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const _ThemeSpecimenPage(),
        ));
      },
    ),
    if (repoPath != null)
      PaletteEntry(
        id: 'dev.test-history-surgery',
        label: 'Test History Surgery',
        keywords: const ['test', 'surgery', 'rewrite', 'history', 'dry', 'dev'],
        chipLabel: 'DEV',
        chipTone: ChipTone.chromatic2,
        category: PaletteCategory.command,
        actionType: PaletteActionType.execute,
        onExecute: () {
          final rp = repoPath!;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HistorySurgeryLoader(
              repoPath: rp,
              dryRun: true,
            ),
          ));
        },
      ),
    if (repoPath != null)
      PaletteEntry(
        id: 'cmd.history-surgery',
        label: 'History Surgery',
        subtitle: 'Rewrite history to permanently remove files',
        keywords: const [
          'rewrite', 'history', 'purge', 'remove', 'filter',
          'clean', 'sensitive', 'surgery',
        ],
        chipLabel: 'ALPHA',
        chipTone: ChipTone.muted,
        category: PaletteCategory.command,
        actionType: PaletteActionType.execute,
        onExecute: () {
          final rp = repoPath!;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HistorySurgeryLoader(repoPath: rp),
          ));
        },
      ),
    if (engine != null)
      PaletteEntry(
        id: 'debug.engine',
        label: 'Engine Status',
        subtitle: 'LogosGit spectral engine diagnostics',
        keywords: const ['debug', 'engine', 'logos', 'spectral', 'coupling', 'diagnostics'],
        chipLabel: 'DEBUG',
        chipTone: ChipTone.muted,
        category: PaletteCategory.command,
        actionType: PaletteActionType.execute,
        onExecute: () => _showEngineStatus(context, engine!),
      ),
    if (engine != null && status != null)
      PaletteEntry(
        id: 'debug.coupling',
        label: 'File Coupling',
        subtitle: 'Nearest co-change neighbors for staged files',
        keywords: const ['debug', 'coupling', 'jaccard', 'neighbors', 'co-change'],
        chipLabel: 'DEBUG',
        chipTone: ChipTone.muted,
        category: PaletteCategory.command,
        actionType: PaletteActionType.execute,
        onExecute: () => _showCouplingInspector(context, engine!, status!),
      ),
  ];
}

void _showEngineStatus(BuildContext context, LogosGit engine) {
  final t = context.read<AppTokens>();
  final s = engine.stats;
  final coupling = s.coupling;
  final fileCount = coupling.paths.length;

  var nnz = 0;
  for (final p in coupling.paths) {
    for (final _ in coupling.jaccardEntriesOf(p)) {
      nnz++;
    }
  }
  nnz ~/= 2;
  final maxPossible = fileCount * (fileCount - 1) ~/ 2;
  final density = maxPossible > 0 ? nnz / maxPossible : 0.0;

  final volCount = s.volatility.length;
  final volEntries = s.volatility.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topVol = volEntries.take(5);

  final lines = StringBuffer()
    ..writeln('commits        ${s.totalCommits}')
    ..writeln('files tracked  $fileCount')
    ..writeln('coupling edges $nnz / $maxPossible  (${(density * 100).toStringAsFixed(1)}%)')
    ..writeln('volatility     $volCount files  μ=${s.volMean.toStringAsFixed(3)}  σ=${s.volStddev.toStringAsFixed(3)}')
    ..writeln('forge          ${s.forge}')
    ..writeln('')
    ..writeln('── most volatile ──');
  for (final e in topVol) {
    final name = e.key.split('/').last;
    lines.writeln('  ${e.value.toStringAsFixed(3)}  $name');
  }

  final reviewedCount = s.reviewedCommits.length;
  final reviewerCount = <String>{};
  for (final rs in s.reviewersByPath.values) {
    reviewerCount.addAll(rs);
  }
  lines
    ..writeln('')
    ..writeln('── review coverage ──')
    ..writeln('  reviewed merges  $reviewedCount')
    ..writeln('  unique reviewers ${reviewerCount.length}');

  showDialog(
    context: context,
    builder: (ctx) => _DebugPanel(
      title: 'Engine Status',
      body: lines.toString(),
      tokens: t,
    ),
  );
}

void _showCouplingInspector(
    BuildContext context, LogosGit engine, RepositoryStatus status) {
  final t = context.read<AppTokens>();
  final coupling = engine.stats.coupling;
  final files = status.files.map((f) => f.path).toList();

  final lines = StringBuffer();
  var shown = 0;
  for (final filePath in files) {
    final basename = filePath.split('/').last;
    final entries = coupling.jaccardEntriesOf(filePath).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    if (top.isEmpty) {
      lines.writeln('$basename  —  no coupling data');
    } else {
      lines.writeln(basename);
      for (final e in top) {
        final neighbor = e.key.split('/').last;
        final bar = '█' * (e.value * 20).round().clamp(1, 20);
        lines.writeln('  ${e.value.toStringAsFixed(2)}  $bar  $neighbor');
      }
    }
    lines.writeln('');
    shown++;
    if (shown >= 12) {
      final remaining = files.length - shown;
      if (remaining > 0) lines.writeln('  +$remaining more files…');
      break;
    }
  }

  if (files.isEmpty) {
    lines.writeln('No staged files.');
  }

  showDialog(
    context: context,
    builder: (ctx) => _DebugPanel(
      title: 'File Coupling',
      body: lines.toString(),
      tokens: t,
    ),
  );
}

class _DebugPanel extends StatelessWidget {
  final String title;
  final String body;
  final AppTokens tokens;
  const _DebugPanel({
    required this.title,
    required this.body,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Material(
          color: tokens.bg1,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  title,
                  style: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                  ),
                ),
              ),
              Container(
                height: 1,
                color: tokens.chromeBorder.withValues(alpha: 0.2),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    body,
                    style: TextStyle(
                      color: tokens.textNormal,
                      fontSize: 11,
                      fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                      height: 1.6,
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

class _TestMergeEditorLoader extends StatefulWidget {
  final String repoPath;
  const _TestMergeEditorLoader({required this.repoPath});
  @override
  State<_TestMergeEditorLoader> createState() =>
      _TestMergeEditorLoaderState();
}

class _TestMergeEditorLoaderState extends State<_TestMergeEditorLoader> {
  List<ConflictFile>? _files;
  List<ConflictFile>? _filesWithoutLogos;
  String? _error;
  bool _building = false;

  late final LogosGitState _logosState;

  @override
  void initState() {
    super.initState();
    _logosState = context.read<LogosGitState>();
    _logosState.addListener(_onLogosChanged);
    _build();
  }

  @override
  void dispose() {
    _logosState.removeListener(_onLogosChanged);
    super.dispose();
  }

  void _onLogosChanged() {
    if (_files != null) return;
    if (_filesWithoutLogos == null) return;
    final engine = _logosState.engineFor(widget.repoPath);
    if (engine == null) return;
    _enrichAll(_filesWithoutLogos!, engine);
    setState(() => _files = _filesWithoutLogos);
  }

  Future<void> _build() async {
    if (_building) return;
    _building = true;
    try {
      _logosState.loadForRepo(widget.repoPath);
      final files = await _buildConflictsFromHistory(
          widget.repoPath, null);
      if (!mounted) return;
      _filesWithoutLogos = files;
      final engine = _logosState.engineFor(widget.repoPath);
      if (engine != null) {
        _enrichAll(files, engine);
        setState(() => _files = files);
      } else {
        // Show immediately without Logos; will re-enrich when engine
        // arrives via the listener.
        setState(() => _files = files);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      _building = false;
    }
  }

  void _enrichAll(List<ConflictFile> files, LogosGit engine) {
    final changedPaths = files.map((f) => f.path).toSet();
    for (final cf in files) {
      enrichConflictFileWithLogos(cf, engine, changedPaths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (_error != null) {
      return Scaffold(
        backgroundColor: t.bg1,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  style: TextStyle(color: t.stateConflicted, fontSize: 12)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('back',
                    style: TextStyle(color: t.textMuted, fontSize: 11)),
              ),
            ],
          ),
        ),
      );
    }
    if (_files == null) {
      return Scaffold(
        backgroundColor: t.bg1,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('building test conflicts from history…',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 11,
                    fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                  )),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('cancel',
                    style: TextStyle(color: t.textFaint, fontSize: 11)),
              ),
            ],
          ),
        ),
      );
    }
    return MergeEditorPage(repoPath: widget.repoPath, files: _files!);
  }
}

Future<List<ConflictFile>> _buildConflictsFromHistory(
    String repoPath, LogosGit? engine) async {
  // Try decreasing depth until we find a valid base ref.
  List<String> changedPaths = [];
  String baseRef = 'HEAD~5';
  for (final depth in [5, 3, 2, 1]) {
    final ref = 'HEAD~$depth';
    final nameResult = await Process.run(
      'git', ['diff', '--name-only', ref, 'HEAD'],
      workingDirectory: repoPath,
    );
    if (nameResult.exitCode != 0) continue;
    final paths = (nameResult.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.contains(' '))
        .toList();
    if (paths.isNotEmpty) {
      changedPaths = paths;
      baseRef = ref;
      break;
    }
  }

  if (changedPaths.isEmpty) throw Exception('no changed files in recent commits');

  final files = <ConflictFile>[];
  final changedSet = changedPaths.toSet();
  for (final path in changedPaths) {
    if (files.length >= 3) break;
    final headResult = await Process.run(
      'git', ['show', 'HEAD:$path'],
      workingDirectory: repoPath,
    );
    if (headResult.exitCode != 0) continue;
    final oldResult = await Process.run(
      'git', ['show', '$baseRef:$path'],
      workingDirectory: repoPath,
    );
    if (oldResult.exitCode != 0) continue;

    final headContent = headResult.stdout as String;
    final oldContent = oldResult.stdout as String;
    final headLines = headContent.split('\n');
    final oldLines = oldContent.split('\n');
    if (headLines.length < 3 || oldLines.length < 3) continue;

    final conflictText =
        _buildSyntheticConflict(path, headLines, oldLines,
            baseRef: baseRef);
    if (conflictText == null) continue;

    final cf = parseConflictFile(path, conflictText,
        oursBranch: 'HEAD', theirsBranch: baseRef);

    if (engine != null) {
      enrichConflictFileWithLogos(cf, engine, changedSet);
    }
    files.add(cf);
  }

  if (files.isEmpty) {
    throw Exception(
        'could not build conflicts — ${changedPaths.length} files '
        'changed but none produced a valid synthetic conflict '
        '(baseRef=$baseRef)');
  }
  return files;
}

String? _buildSyntheticConflict(
    String path, List<String> headLines, List<String> oldLines,
    {String baseRef = 'HEAD~5'}) {
  final buf = StringBuffer();
  var hi = 0;
  var oi = 0;
  var conflictCount = 0;

  while (hi < headLines.length && oi < oldLines.length) {
    if (headLines[hi] == oldLines[oi]) {
      buf.writeln(headLines[hi]);
      hi++;
      oi++;
      continue;
    }
    final headBlock = <String>[];
    final oldBlock = <String>[];
    // Consume differing lines from both sides in lockstep, capped.
    while (hi < headLines.length && oi < oldLines.length &&
        headLines[hi] != oldLines[oi] && headBlock.length < 15) {
      headBlock.add(headLines[hi++]);
      oldBlock.add(oldLines[oi++]);
    }
    // If still mismatched, try to resync: look ahead in each side
    // for the other's current line.
    if (hi < headLines.length && oi < oldLines.length &&
        headLines[hi] != oldLines[oi]) {
      for (var j = hi; j < (hi + 10).clamp(0, headLines.length); j++) {
        if (headLines[j] == oldLines[oi]) {
          while (hi < j) headBlock.add(headLines[hi++]);
          break;
        }
      }
      for (var j = oi; j < (oi + 10).clamp(0, oldLines.length); j++) {
        if (oldLines[j] == headLines[hi]) {
          while (oi < j) oldBlock.add(oldLines[oi++]);
          break;
        }
      }
    }
    if (headBlock.isNotEmpty || oldBlock.isNotEmpty) {
      buf.writeln('<<<<<<< HEAD');
      for (final l in headBlock) buf.writeln(l);
      buf.writeln('=======');
      for (final l in oldBlock) buf.writeln(l);
      buf.writeln('>>>>>>> $baseRef');
      conflictCount++;
    } else {
      // Can't resync — skip one line from each to avoid infinite loop.
      buf.writeln(headLines[hi++]);
      oi++;
    }
    if (conflictCount >= 4) break;
  }
  while (hi < headLines.length) {
    buf.writeln(headLines[hi++]);
  }

  if (conflictCount == 0) return null;
  return buf.toString();
}


// ── Predictive (hot files from spectral momentum) ──────────────────

List<PaletteEntry> _predictiveEntries(LogosGit engine) {
  final scored = <(String, double)>[];
  var maxVol = 0.0;
  for (final v in engine.stats.volatility.values) {
    if (v > maxVol) maxVol = v;
  }
  if (maxVol <= 0) return [];

  for (final path in engine.nodePaths) {
    final vol = engine.stats.volatility[path];
    if (vol == null || vol <= 0) continue;
    final curv = engine.curvature(path);
    final ritual = engine.stats.ritualnessByPath[path] ?? 0.0;
    final meaning = 1.0 - ritual.clamp(0.0, 1.0);
    final momentum = curv * (vol / maxVol) * meaning;
    if (momentum > 0) scored.add((path, momentum));
  }

  if (scored.isEmpty) return [];
  scored.sort((a, b) => b.$2.compareTo(a.$2));

  // Derive cutoff from the distribution: mean + 1σ.
  final n = scored.length;
  final mean = scored.fold(0.0, (s, e) => s + e.$2) / n;
  final variance = scored.fold(0.0, (s, e) {
        final d = e.$2 - mean;
        return s + d * d;
      }) /
      math.max(1, n);
  final sigma = math.sqrt(variance);
  final cutoff = mean + sigma;

  scored.removeWhere((e) => e.$2 < cutoff);

  return scored.take(5).map((e) {
    final path = e.$1;
    final momentum = e.$2;
    final name = path.split('/').last;
    final community = engine.wellOf(path);
    return PaletteEntry(
      id: 'predict.$path',
      label: name,
      subtitle: [
        path,
        if (community != null) community,
        '${(momentum * 100).round()}% momentum',
      ].join(' · '),
      category: PaletteCategory.file,
      actionType: PaletteActionType.execute,
      chipLabel: '↗',
      chipTone: ChipTone.positive,
      tags: const {EntryTag.predicted},
      refPath: path,
    );
  }).toList();
}

// ── Top touched files (from Logos stats) ───────────────────────────

List<PaletteEntry> _topTouchedEntries(LogosGit engine) {
  final touches = engine.stats.touches;
  if (touches.isEmpty) return [];
  final sorted = touches.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(5).map((e) {
    final name = e.key.split('/').last;
    return PaletteEntry(
      id: 'hot.${e.key}',
      label: name,
      subtitle: '${e.value} touches · ${e.key}',
      category: PaletteCategory.file,
      actionType: PaletteActionType.execute,
      chipLabel: 'HOT',
      chipTone: ChipTone.chromatic2,
      refPath: e.key,
    );
  }).toList();
}

// ── Staged coherence (Born-mixed set coherence) ────────────────────

List<PaletteEntry> _coherenceEntry(LogosGit engine, RepositoryStatus status) {
  final staged = status.files
      .where((f) => f.hasStagedChange)
      .map((f) => f.path)
      .toList();
  if (staged.length < 2) return [];
  final score = engine.coherence(staged);
  final pct = (score * 100).round();
  return [
    PaletteEntry(
      id: 'info.coherence',
      label: 'Staged coherence: $pct%',
      subtitle: '${staged.length} files',
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: '$pct%',
      chipTone: pct > 70
          ? ChipTone.positive
          : pct > 40
              ? ChipTone.muted
              : ChipTone.negative,
    ),
  ];
}

// ── Keystone files (from xray snapshot) ────────────────────────────

List<PaletteEntry> _keystoneEntries(
  RepositoryXrayState xray,
  String repoPath,
) {
  final snapshot = xray.snapshotFor(repoPath);
  if (snapshot == null) return [];
  final keystones = snapshot.hotspots
      .where((h) => h.isKeystone && h.keystoneScore != null)
      .toList()
    ..sort((a, b) => (b.keystoneScore ?? 0).compareTo(a.keystoneScore ?? 0));
  if (keystones.isEmpty) return [];
  return keystones.take(3).map((k) {
    final name = k.path.split('/').last;
    final ks = k.keystoneScore ?? 0;
    return PaletteEntry(
      id: 'keystone.${k.path}',
      label: name,
      subtitle: '${k.path} · keystone ${(ks * 100).round()}',
      category: PaletteCategory.file,
      actionType: PaletteActionType.execute,
      chipLabel: 'KEY',
      chipTone: ChipTone.chromatic1,
      refPath: k.path,
    );
  }).toList();
}

// ── Repos ──────────────────────────────────────────────────────────

List<PaletteEntry> _repoEntries(
  RepositoryState repo,
  PaletteCallbacks cb,
  Map<String, String> forgeByPath,
) {
  final active = repo.activePath;
  return repo.recentPaths.map((path) {
    final name = path.split(Platform.pathSeparator).last;
    final isActive = active != null && _normPath(active) == _normPath(path);
    final forge = forgeByPath[path]?.toUpperCase();
    return PaletteEntry(
      id: 'repo.$path',
      label: name,
      subtitle: isActive ? 'active' : path,
      category: PaletteCategory.repo,
      actionType: PaletteActionType.execute,
      chipLabel: forge,
      tags: const {EntryTag.repoEntry},
      refPath: path,
      onExecute: () => cb.onRepoSwitch(path),
    );
  }).toList();
}

List<PaletteEntry> _repoSubEntries(
  RepositoryState repo,
  AiActivityState aiActivity,
  bool hideAi,
  PaletteCallbacks cb,
) {
  final active = repo.activePath;
  final entries = <PaletteEntry>[];
  for (final path in repo.recentPaths) {
    if (active != null && _normPath(active) == _normPath(path)) continue;
    final name = path.split(Platform.pathSeparator).last;
    entries.addAll([
      PaletteEntry(
        id: 'repo.sub.changes.$path',
        label: 'Changes in $name',
        subtitle: path,
        category: PaletteCategory.navigation,
        actionType: PaletteActionType.execute,
        chipLabel: '→',
        chipTone: ChipTone.accent,
        tags: const {EntryTag.repoChild},
        onExecute: () {
          cb.onRepoSwitch(path);
          cb.onModeChanged(0);
        },
      ),
      PaletteEntry(
        id: 'repo.sub.history.$path',
        label: 'History in $name',
        subtitle: path,
        category: PaletteCategory.navigation,
        actionType: PaletteActionType.execute,
        chipLabel: '→',
        chipTone: ChipTone.accent,
        tags: const {EntryTag.repoChild},
        onExecute: () {
          cb.onRepoSwitch(path);
          cb.onModeChanged(1);
        },
      ),
      PaletteEntry(
        id: 'repo.sub.branches.$path',
        label: 'Branches in $name',
        subtitle: path,
        category: PaletteCategory.navigation,
        actionType: PaletteActionType.execute,
        chipLabel: '→',
        chipTone: ChipTone.accent,
        tags: const {EntryTag.repoChild},
        onExecute: () {
          cb.onRepoSwitch(path);
          cb.onModeChanged(2);
        },
      ),
      PaletteEntry(
        id: 'repo.sub.terminal.$path',
        label: 'Terminal in $name',
        subtitle: path,
        category: PaletteCategory.action,
        actionType: PaletteActionType.execute,
        chipLabel: 'TERM',
        tags: const {EntryTag.repoChild},
        onExecute: () => openTerminalAt(path),
      ),
      if (!hideAi) ...[
        PaletteEntry(
          id: 'repo.sub.generate.$path',
          label: 'Generate Commit · $name',
          subtitle: path,
          category: PaletteCategory.action,
          actionType: PaletteActionType.execute,
          chipLabel: 'AI',
          chipTone: ChipTone.chromatic1,
          tags: const {EntryTag.repoChild, EntryTag.needsEngine},
          refPath: path,
          onExecute: () {
            cb.onRepoSwitch(path);
            aiActivity.requestDrawerOpen(path, AiActivityKind.generate);
            cb.onModeChanged(0);
          },
        ),
        PaletteEntry(
          id: 'repo.sub.review.$path',
          label: 'Review Changes in $name',
          subtitle: path,
          category: PaletteCategory.action,
          actionType: PaletteActionType.execute,
          chipLabel: 'AI',
          chipTone: ChipTone.chromatic1,
          tags: const {EntryTag.repoChild, EntryTag.needsEngine},
          refPath: path,
          onExecute: () {
            cb.onRepoSwitch(path);
            aiActivity.requestDrawerOpen(path, AiActivityKind.review);
            cb.onModeChanged(0);
          },
        ),
        PaletteEntry(
          id: 'repo.sub.muse.$path',
          label: 'Muse in $name',
          subtitle: path,
          category: PaletteCategory.action,
          actionType: PaletteActionType.execute,
          chipLabel: 'AI',
          chipTone: ChipTone.chromatic1,
          tags: const {EntryTag.repoChild, EntryTag.needsEngine},
          refPath: path,
          onExecute: () {
            cb.onRepoSwitch(path);
            aiActivity.requestDrawerOpen(path, AiActivityKind.muse);
            cb.onModeChanged(0);
          },
        ),
      ],
    ]);
  }

  return entries;
}

// ── Desks ──────────────────────────────────────────────────────────

List<PaletteEntry> _deskEntries(
  WorktreeState worktrees,
  RepositoryState repo,
  PaletteCallbacks cb,
) {
  final activePath = repo.activePath;
  return worktrees.desks.map((d) {
    final branchLabel = d.branch ?? (d.isMain ? 'main worktree' : 'detached');
    final isActive =
        activePath != null && _normPath(activePath) == _normPath(d.path);
    final activity = worktrees.activityFor(d.path);
    final parts = <String>[];
    if (isActive) parts.add('active');
    if (d.dirtyFileCount > 0) parts.add('${d.dirtyFileCount} dirty');
    if (activity != null) {
      if (activity.ahead > 0) parts.add('${activity.ahead}↑');
      if (activity.behind > 0) parts.add('${activity.behind}↓');
    }
    final (chip, tone) = d.isMain
        ? ('MAIN', ChipTone.accent)
        : d.isDetached
            ? ('DET', ChipTone.conflicted)
            : activity != null && activity.ahead > 0
                ? ('${activity.ahead}↑', ChipTone.positive)
                : ('DESK', ChipTone.muted);
    return PaletteEntry(
      id: 'desk.${d.path}',
      label: branchLabel,
      subtitle: parts.isEmpty ? null : parts.join(' · '),
      category: PaletteCategory.repo,
      actionType: PaletteActionType.execute,
      chipLabel: chip,
      chipTone: tone,
      tags: const {EntryTag.deskEntry},
      refPath: d.path,
      onExecute: () => cb.onDeskSwitch(d.path),
    );
  }).toList();
}

// ── Actions ────────────────────────────────────────────────────────

List<PaletteEntry> _actionEntries(
  String repoPath,
  RepositoryStatus? status,
  PaletteCallbacks cb,
) {
  final branch = status?.branch ?? '';
  return [
    PaletteEntry(
      id: 'act.open-browser',
      label: 'Open in Browser',
      keywords: const ['github', 'gitlab', 'web', 'remote'],
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: 'WEB',
      chipTone: ChipTone.chromatic2,
      onExecute: () async {
        try {
          final info = await resolveRepoWebInfo(repoPath);
          if (info != null) {
            cb.onOpenBrowser(info.webUrl);
          } else {
            revealInFileManager(repoPath);
          }
        } catch (_) {
          revealInFileManager(repoPath);
        }
      },
    ),
    PaletteEntry(
      id: 'act.terminal',
      label: 'Terminal',
      keywords: const ['shell', 'console', 'cmd', 'bash', 'powershell'],
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: 'SYS',
      onExecute: () => openTerminalAt(repoPath),
    ),
    PaletteEntry(
      id: 'act.reveal',
      label: 'Reveal in Files',
      keywords: const ['explorer', 'finder', 'folder', 'open'],
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: 'SYS',
      onExecute: () => revealInFileManager(repoPath),
    ),
    PaletteEntry(
      id: 'act.copy-path',
      label: 'Copy Path',
      subtitle: repoPath,
      keywords: const ['clipboard', 'repo'],
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: 'CLIP',
      refPath: repoPath,
      onExecute: () => Clipboard.setData(ClipboardData(text: repoPath)),
    ),
    if (branch.isNotEmpty)
      PaletteEntry(
        id: 'act.copy-branch',
        label: 'Copy Branch',
        subtitle: branch,
        keywords: const ['clipboard', 'ref'],
        category: PaletteCategory.action,
        actionType: PaletteActionType.execute,
        chipLabel: 'CLIP',
        onExecute: () => Clipboard.setData(ClipboardData(text: branch)),
      ),
  ];
}

// ── External Tools ─────────────────────────────────────────────────

List<PaletteEntry> _externalToolEntries(
  ExternalToolsState toolsState,
  String repoPath,
) {
  if (!toolsState.isLoaded || toolsState.isEmpty) return [];
  return toolsState.tools.map((tool) {
    final chip =
        tool.mode == ToolLaunchMode.newTerminal ? 'TERM' : 'GUI';
    return PaletteEntry(
      id: 'tool.${tool.id}',
      label: 'Launch ${tool.displayLabel}',
      subtitle: tool.executable,
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: chip,
      onExecute: () async {
        final args = tool.resolveArgs(repoPath);
        try {
          switch (tool.mode) {
            case ToolLaunchMode.newTerminal:
              await runInTerminal(
                executable: tool.executable,
                args: args,
                workingDirectory: repoPath,
              );
            case ToolLaunchMode.detached:
              await runDetached(
                executable: tool.executable,
                args: args,
                workingDirectory: repoPath,
              );
          }
        } catch (_) {}
      },
    );
  }).toList();
}

// ── Git Commands ───────────────────────────────────────────────────

List<PaletteEntry> _gitCommandEntries(
  String repoPath,
  RepositoryStatus? status,
  PaletteCallbacks cb,
) {
  final ahead = status?.ahead ?? 0;
  final behind = status?.behind ?? 0;
  final upstream = status?.upstream;
  final allPaths =
      status?.files.map((f) => f.path).toList() ?? const <String>[];
  final stagedPaths =
      status?.files.where((f) => f.hasStagedChange).map((f) => f.path).toList() ?? const <String>[];

  return [
    PaletteEntry(
      id: 'cmd.fetch',
      label: 'Fetch',
      keywords: const ['sync', 'download', 'update'],
      chipLabel: 'SYNC',
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.syncFetch},
      onExecute: () => git.fetchRemote(repoPath),
    ),
    PaletteEntry(
      id: 'cmd.pull',
      label: 'Pull',
      subtitle: behind > 0
          ? '$behind behind${upstream != null ? ' $upstream' : ''}'
          : null,
      keywords: const ['sync', 'download', 'merge', 'update'],
      chipLabel: behind > 0 ? '${behind}↓' : null,
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.syncPull},
      onExecute: () => git.pullRemote(repoPath),
    ),
    PaletteEntry(
      id: 'cmd.push',
      label: 'Push',
      subtitle: ahead > 0
          ? '$ahead commit${ahead > 1 ? 's' : ''}${upstream != null ? ' to $upstream' : ''}'
          : null,
      keywords: const ['sync', 'upload', 'publish'],
      chipLabel: ahead > 0 ? '${ahead}↑' : null,
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.syncPush},
      onExecute: () => git.pushRemote(repoPath),
    ),
    PaletteEntry(
      id: 'cmd.force-push',
      label: 'Force Push',
      keywords: const ['overwrite', 'push force'],
      chipLabel: 'FORCE',
      chipTone: ChipTone.negative,
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.syncForcePush},
      onExecute: () => git.pushRemote(repoPath, forceWithLease: true),
    ),
    PaletteEntry(
      id: 'cmd.commit',
      label: 'Commit',
      keywords: const ['save', 'snapshot'],
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.doCommit},
      shortcutLabel: 'Ctrl+S',
      onExecute: () => cb.onModeChanged(0),
    ),
    PaletteEntry(
      id: 'cmd.stage-all',
      label: 'Stage All',
      keywords: const ['add all', 'track'],
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.stageAll},
      onExecute: () => git.stagePaths(repoPath, allPaths),
    ),
    PaletteEntry(
      id: 'cmd.unstage-all',
      label: 'Unstage All',
      keywords: const ['reset', 'remove staged'],
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.unstageAll},
      onExecute: () => git.unstagePaths(repoPath, stagedPaths),
    ),
    PaletteEntry(
      id: 'cmd.discard-all',
      label: 'Discard All',
      keywords: const ['clean', 'reset', 'undo changes'],
      chipTone: ChipTone.negative,
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.discardAll},
      onExecute: () => cb.onModeChanged(0),
    ),
    PaletteEntry(
      id: 'cmd.create-branch',
      label: 'Create Branch',
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.branchCreate},
      onExecute: () => cb.onModeChanged(2),
    ),
    PaletteEntry(
      id: 'cmd.delete-branch',
      label: 'Delete Branch',
      chipTone: ChipTone.negative,
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.branchDelete},
      onExecute: () => cb.onModeChanged(2),
    ),
    PaletteEntry(
      id: 'cmd.rename-branch',
      label: 'Rename Branch',
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.branchRename},
      onExecute: () => cb.onModeChanged(2),
    ),
    PaletteEntry(
      id: 'cmd.stash-push',
      label: 'Stash',
      keywords: const ['shelve', 'park', 'save state'],
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.stashPush},
      onExecute: () => git.stashPush(repoPath, includeUntracked: true),
    ),
    PaletteEntry(
      id: 'cmd.stash-pop',
      label: 'Stash Pop',
      keywords: const ['unshelve', 'restore'],
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.stashPop},
      onExecute: () => git.stashPop(repoPath),
    ),
    PaletteEntry(
      id: 'cmd.stash-apply',
      label: 'Stash Apply',
      keywords: const ['restore', 'unshelve'],
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.stashApply},
      onExecute: () => git.stashApply(repoPath),
    ),
    PaletteEntry(
      id: 'cmd.stash-drop',
      label: 'Stash Drop',
      keywords: const ['delete stash', 'remove stash'],
      chipTone: ChipTone.negative,
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.stashDrop},
      onExecute: () => git.stashDrop(repoPath),
    ),
    PaletteEntry(
      id: 'cmd.create-tag',
      label: 'Create Tag',
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.tagCreate},
      onExecute: () => cb.onModeChanged(1),
    ),
    PaletteEntry(
      id: 'cmd.cherry-pick',
      label: 'Cherry-pick',
      keywords: const ['pick commit', 'graft'],
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.cherryPick},
      onExecute: () => cb.onModeChanged(1),
    ),
    PaletteEntry(
      id: 'cmd.revert',
      label: 'Revert',
      keywords: const ['undo commit', 'rollback'],
      chipTone: ChipTone.negative,
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      tags: const {EntryTag.revertCommit},
      onExecute: () => cb.onModeChanged(1),
    ),
  ];
}

// ── PR Actions ─────────────────────────────────────────────────────

List<PaletteEntry> _prEntries(
  DeskPrState deskPr,
  String? branch,
  PaletteCallbacks cb,
) {
  if (branch == null || branch.isEmpty) return [];
  final pr = deskPr.prFor(branch);
  if (pr == null) {
    return [
      PaletteEntry(
        id: 'pr.create',
        label: 'Create PR',
        subtitle: branch,
        category: PaletteCategory.command,
        actionType: PaletteActionType.execute,
        chipLabel: 'PR',
        tags: const {EntryTag.prAction},
        onExecute: () => cb.onModeChanged(2),
      ),
    ];
  }
  final entries = <PaletteEntry>[];
  if (pr.state == 'OPEN') {
    entries.add(PaletteEntry(
      id: 'pr.merge',
      label: 'Merge PR',
      subtitle: pr.title,
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      chipLabel: 'PR',
      tags: const {EntryTag.prAction},
      onExecute: () => cb.onModeChanged(2),
    ));
    if (pr.isDraft) {
      entries.add(PaletteEntry(
        id: 'pr.ready',
        label: 'Mark PR Ready',
        category: PaletteCategory.command,
        actionType: PaletteActionType.execute,
        chipLabel: 'DRAFT',
        tags: const {EntryTag.prAction},
        onExecute: () => cb.onModeChanged(2),
      ));
    }
  }
  return entries;
}

// ── AI Activity ────────────────────────────────────────────────────

List<PaletteEntry> _aiEntries(
  AiActivityState aiActivity,
  String repoPath,
  bool hideAi,
  PaletteCallbacks cb,
) {
  if (hideAi) return [];
  final active = aiActivity.activeFor(repoPath);
  final entries = <PaletteEntry>[];

  // Trigger entries — always available when AI is enabled.
  entries.addAll([
    PaletteEntry(
      id: 'ai.trigger.generate',
      label: 'Generate Commit',
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: 'AI',
      chipTone: ChipTone.chromatic1,
      onExecute: () {
        aiActivity.requestDrawerOpen(repoPath, AiActivityKind.generate);
        cb.onModeChanged(0);
      },
    ),
    PaletteEntry(
      id: 'ai.trigger.review',
      label: 'Review Changes',
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: 'AI',
      chipTone: ChipTone.chromatic1,
      onExecute: () {
        aiActivity.requestDrawerOpen(repoPath, AiActivityKind.review);
        cb.onModeChanged(0);
      },
    ),
    PaletteEntry(
      id: 'ai.trigger.muse',
      label: 'Run Muse',
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: 'AI',
      chipTone: ChipTone.chromatic1,
      onExecute: () {
        aiActivity.requestDrawerOpen(repoPath, AiActivityKind.muse);
        cb.onModeChanged(0);
      },
    ),
    PaletteEntry(
      id: 'ai.trigger.debug',
      label: 'Debug ${repoPath.split('/').last.split('\\').last}',
      subtitle: 'describe a symptom',
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: 'AI',
      chipTone: ChipTone.chromatic1,
      onExecute: () {
        aiActivity.requestDrawerOpen(repoPath, AiActivityKind.debug);
        cb.onModeChanged(0);
      },
    ),
  ]);

  // Unseen results and running indicators.
  for (final r in active) {
    if (r.isTerminal && !r.seen) {
      final kindLabel = switch (r.kind) {
        AiActivityKind.generate => 'Commit Message',
        AiActivityKind.review => 'Code Review',
        AiActivityKind.muse => 'Muse Result',
        AiActivityKind.present => 'Presentation',
        AiActivityKind.debug => 'Debug Result',
      };
      entries.add(PaletteEntry(
        id: 'ai.view.${r.kind.name}',
        label: 'View $kindLabel',
        subtitle: 'unseen result',
        category: PaletteCategory.action,
        actionType: PaletteActionType.execute,
        chipLabel: 'AI',
        chipTone: ChipTone.positive,
        onExecute: () {
          aiActivity.requestDrawerOpen(repoPath, r.kind);
          cb.onModeChanged(0);
        },
      ));
    } else if (r.isRunning) {
      entries.add(PaletteEntry(
        id: 'ai.running.${r.kind.name}',
        label: 'AI: ${r.kind.name}…',
        subtitle: 'running',
        category: PaletteCategory.action,
        actionType: PaletteActionType.execute,
        chipLabel: 'AI',
        chipTone: ChipTone.muted,
      ));
    }
  }
  return entries;
}

// ── Undo ───────────────────────────────────────────────────────────

List<PaletteEntry> _undoEntry(UndoCoordinator undo, PaletteCallbacks cb) {
  if (!undo.hasPending) return [];
  final pending = undo.pending!;
  return [
    PaletteEntry(
      id: 'undo.cancel',
      label: 'Cancel: ${pending.label}',
      category: PaletteCategory.command,
      actionType: PaletteActionType.execute,
      chipLabel: 'UNDO',
      onExecute: cb.onUndo,
    ),
  ];
}

// ── Navigation ─────────────────────────────────────────────────────

List<PaletteEntry> _navigationEntries(PaletteCallbacks cb) => [
      PaletteEntry(
        id: 'nav.changes',
        label: 'Changes',
        keywords: const ['diff', 'modified', 'staged', 'status'],
        category: PaletteCategory.navigation,
        actionType: PaletteActionType.execute,
        tags: const {EntryTag.navWithShortcut},
        shortcutLabel: 'Ctrl+1',
        onExecute: () => cb.onModeChanged(0),
      ),
      PaletteEntry(
        id: 'nav.history',
        label: 'History',
        keywords: const ['log', 'commits', 'timeline'],
        category: PaletteCategory.navigation,
        actionType: PaletteActionType.execute,
        tags: const {EntryTag.navWithShortcut},
        shortcutLabel: 'Ctrl+2',
        onExecute: () => cb.onModeChanged(1),
      ),
      PaletteEntry(
        id: 'nav.branches',
        label: 'Branches',
        keywords: const ['refs', 'checkout', 'switch'],
        category: PaletteCategory.navigation,
        actionType: PaletteActionType.execute,
        tags: const {EntryTag.navWithShortcut},
        shortcutLabel: 'Ctrl+3',
        onExecute: () => cb.onModeChanged(2),
      ),
      PaletteEntry(
        id: 'nav.xray',
        label: 'X-Ray',
        keywords: const ['analysis', 'hotspots', 'insights'],
        category: PaletteCategory.navigation,
        actionType: PaletteActionType.execute,
        onExecute: cb.onOpenXray,
      ),
      PaletteEntry(
        id: 'nav.settings',
        label: 'Settings',
        keywords: const ['preferences', 'config', 'options'],
        category: PaletteCategory.navigation,
        actionType: PaletteActionType.execute,
        onExecute: cb.onOpenSettings,
      ),
      PaletteEntry(
        id: 'nav.refresh',
        label: 'Refresh',
        keywords: const ['reload', 'rescan'],
        category: PaletteCategory.navigation,
        actionType: PaletteActionType.execute,
        shortcutLabel: 'F5',
        onExecute: cb.onRefresh,
      ),
    ];

// ── Settings ───────────────────────────────────────────────────────

List<PaletteEntry> _settingToggleEntries(PreferencesState prefs) => [
      PaletteEntry(
        id: 'setting.reduce-motion',
        label: 'Reduce Motion',
        keywords: const ['animation', 'accessibility'],
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.reduceMotion,
        writeBool: (v) => prefs.setReduceMotion(v),
      ),
      PaletteEntry(
        id: 'setting.logo-animates-unfocused',
        label: 'Animate Logo Unfocused',
        keywords: const ['background', 'idle'],
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.logoAnimatesWhenUnfocused,
        writeBool: (v) => prefs.setLogoAnimatesWhenUnfocused(v),
      ),
      PaletteEntry(
        id: 'setting.instant-blame',
        label: 'Instant Blame Hover',
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.instantBlameHover,
        writeBool: (v) => prefs.setInstantBlameHover(v),
      ),
      PaletteEntry(
        id: 'setting.auto-select-changes',
        label: 'Auto-select Changes',
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.autoSelectNewChanges,
        writeBool: (v) => prefs.setAutoSelectNewChanges(v),
      ),
      PaletteEntry(
        id: 'setting.fetch-online-issues',
        label: 'Fetch Online Issues',
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.fetchOnlineIssuesOnBranchLoad,
        writeBool: (v) => prefs.setFetchOnlineIssuesOnBranchLoad(v),
      ),
      PaletteEntry(
        id: 'setting.remember-wip',
        label: 'Remember Work in Progress',
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.rememberWorkInProgress,
        writeBool: (v) => prefs.setRememberWorkInProgress(v),
      ),
      PaletteEntry(
        id: 'setting.hide-ai',
        label: 'Hide AI Features',
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.hideAiFeatures,
        writeBool: (v) => prefs.setHideAiFeatures(v),
      ),
      PaletteEntry(
        id: 'setting.crash-reporting',
        label: 'Crash Reporting',
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.crashReportingEnabled,
        writeBool: (v) => prefs.setCrashReportingEnabled(v),
      ),
      if (!prefs.hideAiFeatures)
        PaletteEntry(
          id: 'setting.ai-read-only',
          label: 'AI Read-only',
          category: PaletteCategory.setting,
          actionType: PaletteActionType.toggle,
          readBool: () => prefs.aiReadOnlyDefault,
          writeBool: (v) => prefs.setAiReadOnlyDefault(v),
        ),
      PaletteEntry(
        id: 'setting.stash-cabinet',
        label: 'Stash Cabinet Expanded',
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.stashCabinetDefaultExpanded,
        writeBool: (v) => prefs.setStashCabinetDefaultExpanded(v),
      ),
      PaletteEntry(
        id: 'setting.file-sort-inverted',
        label: 'File Sort Inverted',
        category: PaletteCategory.setting,
        actionType: PaletteActionType.toggle,
        readBool: () => prefs.fileSortInverted,
        writeBool: (v) => prefs.setFileSortInverted(v),
      ),
    ];

// ── Themes ─────────────────────────────────────────────────────────

List<PaletteEntry> _themeEntries(ThemeState theme) => AppThemeId.values.map(
      (id) {
        final current = theme.themeId == id;
        return PaletteEntry(
          id: 'theme.${id.name}',
          label: _themeLabel(id),
          subtitle: current ? 'active' : null,
          keywords: const ['theme'],
          category: PaletteCategory.setting,
          actionType: PaletteActionType.execute,
          chipLabel: 'THM',
          onExecute: () => theme.setTheme(id),
        );
      },
    ).toList();

// ── Info ───────────────────────────────────────────────────────────

List<PaletteEntry> _infoEntries() => [
      PaletteEntry(
        id: 'info.version',
        label: 'Manifold ${BuildInfo.versionDisplay}',
        keywords: const ['version', 'about'],
        category: PaletteCategory.action,
        actionType: PaletteActionType.execute,
        chipLabel: 'VER',
        onExecute: () => Clipboard.setData(
          ClipboardData(text: BuildInfo.versionDisplay),
        ),
      ),
    ];

// ── Helpers ────────────────────────────────────────────────────────

String _themeLabel(AppThemeId id) => switch (id) {
      AppThemeId.halo => 'Halo',
      AppThemeId.nightwalker => 'Nightwalker',
      AppThemeId.petrichor => 'Petrichor',
      AppThemeId.helix => 'Helix',
      AppThemeId.nacre => 'Nacre',
      AppThemeId.loverboy => 'Loverboy',
      AppThemeId.aether => 'Aether',
      AppThemeId.quanta => 'Quanta',
      AppThemeId.phosphor => 'Phosphor',
      AppThemeId.redshift => 'Redshift',
      AppThemeId.kirby => 'Kirby',
      AppThemeId.blackboard => 'Blackboard',
      AppThemeId.crafty => 'Crafty',
      AppThemeId.barbie => 'Barbie',
      AppThemeId.entropy => 'Lady Entropy',
    };

String _normPath(String p) => p.replaceAll('\\', '/').toLowerCase();

// ── Theme Specimen Page ──────────────────────────────────────────
// Self-documenting reference sheet. Every element prints its own name
// so a screenshot communicates the full design system to an LLM
// without hover tooltips.

class _ThemeSpecimenPage extends StatelessWidget {
  const _ThemeSpecimenPage();

  static const _iconNames = [
    'app-logo', 'changes', 'history', 'branches', 'xray', 'settings',
    'plus', 'x', 'search', 'tag', 'sync', 'commit',
    'chevron-right', 'chevron-left', 'chevron-down',
    'trash', 'fetch', 'push', 'pull', 'git-branch',
    'status-conflict', 'sort', 'clear', 'check', 'repo-summary',
    'drift-focused', 'drift-spread', 'drift-divergent',
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final geo = context.surfaceShader.geometry;
    final shader = context.surfaceShader;
    final s = TextStyle(color: t.textFaint, fontSize: 7.5,
        fontFamily: AppFonts.mono, height: 1.0);

    return Scaffold(
      backgroundColor: t.bg0,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(children: [
              Text('${t.id.name}', style: TextStyle(color: t.textStrong,
                  fontSize: 14, fontWeight: FontWeight.w700,
                  fontFamily: AppFonts.mono)),
              const SizedBox(width: 6),
              Text(t.isDark ? 'dark' : 'light', style: TextStyle(
                  color: t.textFaint, fontSize: 10, fontFamily: AppFonts.mono)),
              const SizedBox(width: 6),
              Text('r:${geo.radius} blur:${t.backdropBlur} '
                  'sat:${t.backdropSaturate} ${shader.duration.inMilliseconds}ms',
                  style: TextStyle(color: t.textFaint, fontSize: 8,
                      fontFamily: AppFonts.mono)),
              const Spacer(),
              Text('${AppFonts.mono} + ${AppFonts.monoFallback.first}',
                  style: TextStyle(color: t.textFaint, fontSize: 8,
                      fontFamily: AppFonts.mono)),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: MouseRegion(cursor: SystemMouseCursors.click,
                    child: Icon(Icons.close, size: 14, color: t.textMuted)),
              ),
            ]),
            const SizedBox(height: 10),

            // ── Backgrounds + Surfaces ──
            _Section('backgrounds · surfaces', t),
            Row(children: [
              for (final c in [
                ('bg0', t.bg0), ('bg1', t.bg1), ('bg2', t.bg2), ('bg3', t.bg3),
                ('srf0', t.surface0), ('srf1', t.surface1), ('srf2', t.surface2),
              ]) _Swatch(c.$1, c.$2, t, geo),
            ]),
            const SizedBox(height: 8),

            // ── Text colors ──
            _Section('text', t),
            Row(children: [
              for (final c in [
                ('textStrong', t.textStrong), ('textNormal', t.textNormal),
                ('textMuted', t.textMuted), ('textFaint', t.textFaint),
              ]) _Swatch(c.$1, c.$2, t, geo),
            ]),
            const SizedBox(height: 2),
            Text('Strong 13px w700', style: TextStyle(color: t.textStrong,
                fontSize: 13, fontWeight: FontWeight.w700,
                fontFamily: AppFonts.mono)),
            Text('Normal 12px', style: TextStyle(color: t.textNormal,
                fontSize: 12, fontFamily: AppFonts.mono)),
            Text('Muted 11px', style: TextStyle(color: t.textMuted,
                fontSize: 11, fontFamily: AppFonts.mono)),
            Text('Faint 10px', style: TextStyle(color: t.textFaint,
                fontSize: 10, fontFamily: AppFonts.mono)),
            const SizedBox(height: 8),

            // ── State + Accent ──
            _Section('state · accent', t),
            Row(children: [
              for (final c in [
                ('stateAdded', t.stateAdded),
                ('stateModified', t.stateModified),
                ('stateDeleted', t.stateDeleted),
                ('stateConflicted', t.stateConflicted),
                ('stateStaged', t.stateStaged),
                ('accentBright', t.accentBright),
                ('eventStartTone', t.eventStartTone),
              ]) _Swatch(c.$1, c.$2, t, geo),
            ]),
            const SizedBox(height: 8),

            // ── Chrome + Interactive ──
            _Section('chrome · interactive', t),
            Row(children: [
              for (final c in [
                ('chromeBorder', t.chromeBorder),
                ('chromeAccent', t.chromeAccent),
                ('btnBg', t.btnBg), ('btnText', t.btnText),
                ('inputBg', t.inputBg), ('inputBorder', t.inputBorder),
                ('itemHoverBg', t.itemHoverBg),
                ('itemActiveBg', t.itemActiveBg),
                ('rowBg', t.rowBg),
              ]) _Swatch(c.$1, c.$2, t, geo),
            ]),
            const SizedBox(height: 8),

            // ── Hypercube + Overlays ──
            _Section('hypercube · overlays', t),
            Row(children: [
              for (final c in [
                ('hyperCore', t.hyperCore),
                ('hyperC1', t.hyperChromatic1),
                ('hyperC2', t.hyperChromatic2),
                ('hyperPos', t.hypercubePositive),
                ('hyperNeg', t.hypercubeNegative),
                ('panelOvl', t.panelOverlay),
                ('dangerOvl', t.dangerOverlay),
                ('diffOvl', t.diffOverlay),
              ]) _Swatch(c.$1, c.$2, t, geo),
            ]),
            const SizedBox(height: 10),

            // ── Icons — each labeled ──
            _Section('icons (${_iconNames.length})', t),
            Wrap(spacing: 2, runSpacing: 1, children: [
              for (final name in _iconNames)
                SizedBox(
                  width: 100, height: 22,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon(name: name, size: 12, color: t.textNormal),
                    const SizedBox(width: 3),
                    Flexible(child: Text(name, style: s,
                        maxLines: 1, overflow: TextOverflow.clip)),
                  ]),
                ),
            ]),
            const SizedBox(height: 10),

            // ── Geometry radii ──
            _Section('geometry', t),
            Row(children: [
              for (final tier in [
                ('card', geo.cardRadius),
                ('pill', geo.pillRadius),
                ('badge', geo.badgeRadius),
                ('tiny', geo.tinyRadius),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 56, height: 24,
                    decoration: BoxDecoration(
                      color: t.accentBright.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(tier.$2),
                      border: Border.all(
                        color: t.accentBright.withValues(alpha: 0.35),
                        width: 0.8),
                    ),
                    alignment: Alignment.center,
                    child: Text('${tier.$1} ${tier.$2.toStringAsFixed(1)}',
                        style: TextStyle(color: t.accentBright, fontSize: 7.5,
                            fontFamily: AppFonts.mono,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
            const SizedBox(height: 10),

            // ── Motion tiers ──
            _Section('motion', t),
            Row(children: [
              for (final m in [
                ('snap', AppMotion.snap),
                ('fade', AppMotion.fade),
                ('fluid', AppMotion.fluid),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${m.$1} ${m.$2.inMilliseconds}ms',
                      style: TextStyle(color: t.textMuted, fontSize: 9,
                          fontFamily: AppFonts.mono)),
                ),
            ]),
            const SizedBox(height: 10),

            // ── Gradient ──
            if (t.appGradientColors.isNotEmpty) ...[
              _Section('gradient (${t.appGradientColors.length} stops)', t),
              Container(
                height: 16, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: t.appGradientColors),
                  borderRadius: BorderRadius.circular(geo.badgeRadius),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // ── State pills (as rendered) ──
            _Section('state pills (as rendered)', t),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final st in [
                ('added', t.stateAdded), ('modified', t.stateModified),
                ('deleted', t.stateDeleted), ('conflicted', t.stateConflicted),
                ('staged', t.stateStaged), ('accent', t.accentBright),
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: st.$2.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(geo.pillRadius),
                    border: Border.all(
                        color: st.$2.withValues(alpha: 0.35), width: 0.8),
                  ),
                  child: Text(st.$1, style: TextStyle(color: st.$2,
                      fontSize: 9, fontFamily: AppFonts.mono,
                      fontWeight: FontWeight.w600)),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final AppTokens t;
  const _Section(this.label, this.t);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(label, style: TextStyle(color: t.textMuted, fontSize: 9,
        fontWeight: FontWeight.w700, fontFamily: AppFonts.mono)),
  );
}

class _Swatch extends StatelessWidget {
  final String name;
  final Color color;
  final AppTokens t;
  final SurfaceMaterialGeometry geo;
  const _Swatch(this.name, this.color, this.t, this.geo);
  @override
  Widget build(BuildContext context) {
    final textColor = color.computeLuminance() > 0.45
        ? Colors.black54 : Colors.white60;
    return Padding(
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        constraints: const BoxConstraints(minWidth: 44),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(geo.badgeRadius),
          border: Border.all(
              color: t.chromeBorder.withValues(alpha: 0.25), width: 0.5),
        ),
        alignment: Alignment.centerLeft,
        child: Text(name, style: TextStyle(color: textColor, fontSize: 7,
            fontFamily: AppFonts.mono, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
