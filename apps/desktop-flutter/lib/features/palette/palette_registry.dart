import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'dart:math' as math;

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
import '../../backend/logos_git.dart';
import '../../backend/repo_web_url.dart';
import '../../backend/system_paths.dart';
import '../../backend/undo_controller.dart';
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
  ];
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
      id: 'ai.trigger.ask',
      label: 'Ask ${repoPath.split('/').last.split('\\').last}',
      subtitle: 'ask: [question]',
      category: PaletteCategory.action,
      actionType: PaletteActionType.execute,
      chipLabel: 'AI',
      chipTone: ChipTone.chromatic1,
      onExecute: () {
        aiActivity.requestDrawerOpen(repoPath, AiActivityKind.ask);
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
        AiActivityKind.ask => 'AI Answer',
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
      AppThemeId.entrapta => 'Entrapta',
    };

String _normPath(String p) => p.replaceAll('\\', '/').toLowerCase();
