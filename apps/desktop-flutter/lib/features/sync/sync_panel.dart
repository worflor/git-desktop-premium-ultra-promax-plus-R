// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../ui/control_chrome.dart';
import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../backend/merge_session.dart';
import '../../app/repository_state.dart';
import '../changes/merge_conflict_flow.dart';
import '../../components/icons/app_icons.dart';
import 'force_push_guard.dart';
import 'sync_actions.dart';
import '../../i18n/gen/strings.g.dart' as i18n;

/// The sync flyout — the detail surface the topbar sync control opens. Slimmed
/// from the original standalone panel into an anchored overlay body: a counts
/// hero, the canonical describe-action label, a one-click sync + fetch-only,
/// and the recent-activity log. Every sync/pull it fires routes through the
/// one shared path ([resolveSync] / [resumeConflicts] / [pushRemote]) so it and
/// the clean-tree pill can't diverge, and its force-push recovery goes through
/// the shared [confirmForcePush] guard (lease-only).
class SyncPanel extends StatefulWidget {
  final VoidCallback onClose;
  const SyncPanel({super.key, required this.onClose});
  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<SyncPanel> {
  bool _syncRunning = false;
  bool _fetchRunning = false;
  // True while the force-push-with-lease recovery is in flight. Used to
  // disable the recovery button + show "Working…" so a double-tap can't fire
  // the destructive op twice.
  bool _forceRunning = false;
  String? _actionError;
  SyncData? _lastResult;
  // Conflicts the user left unresolved (cancelled the editor). Surfaced with a
  // "Resolve conflicts" recovery that re-enters the unified merge flow.
  List<String>? _pendingConflicts;

  // Force-push counts: while the destructive recovery is mutating the
  // remote, the primary sync/fetch buttons must not launch a concurrent
  // pull/push against the same branch.
  bool get _busy => _syncRunning || _fetchRunning || _forceRunning;

  void _applyOutcome(MergeOutcome outcome) {
    switch (outcome) {
      case MergeClean(:final data):
        _lastResult = data;
      case MergeConflicted(:final paths, :final resolved):
        if (resolved) {
          _lastResult = SyncData(
            operation: 'merge',
            remote: 'origin',
            output: i18n.t.sync.panel.resolvedConflicts(
              count: i18n.t.common.conflictedFileCount(n: paths.length),
            ),
          );
        } else if (paths.isEmpty) {
          // Cancelled / discarded dirty pull — nothing changed. Neutral
          // confirmation instead of a phantom "N conflicts" recovery.
          _lastResult = SyncData(
            operation: 'sync',
            remote: 'origin',
            output: i18n.t.sync.panel.cancelledUnchanged,
          );
        } else {
          _pendingConflicts = paths;
        }
      case MergeBlockedByLocalChanges(:final paths):
        _actionError = i18n.t.sync.panel.uncommittedEditsBlocked(
          count: i18n.t.common.fileCount(n: paths.length),
          list: '${paths.take(3).join(', ')}${paths.length > 3 ? '…' : ''}',
        );
      case MergeNeedsCheckout(:final message):
        // Sync never produces this (it always operates on the checked-out
        // branch); handled for exhaustiveness — surface the guidance if it
        // ever reaches here rather than silently swallowing it.
        _actionError = message;
      case MergeFailed(:final message):
        _actionError = message;
    }
  }

  Future<void> _runSync(String repo, RepositoryStatus status) async {
    setState(() {
      _syncRunning = true;
      _actionError = null;
      _pendingConflicts = null;
    });
    final outcome = await resolveSync(context, repo, status);
    if (!mounted) return;
    setState(() {
      _syncRunning = false;
      _applyOutcome(outcome);
    });
    // Keyed to the repo this flow actually mutated — a bare refreshStatus()
    // follows activePath, so a repo switch while the dialog/git op was in
    // flight would refresh the wrong repo and leave this one stale.
    await context.read<RepositoryState>().refreshStatusIfActive(repo);
  }

  /// Re-enters the unified flow to finish conflicts the user cancelled. Uses
  /// [resumeConflicts] (not a fresh pull) so a paused REBASE is driven with
  /// `rebase --continue` rather than mis-resolved as a new merge.
  Future<void> _resolvePendingConflicts(String repo) async {
    setState(() {
      _syncRunning = true;
      _actionError = null;
    });
    // The sync flyout always means "sync", so a recovered rebase owes its push.
    final outcome = await resumeConflicts(context, repo, pushAfterRebase: true);
    if (!mounted) return;
    setState(() {
      _syncRunning = false;
      _pendingConflicts = null;
      _applyOutcome(outcome);
    });
    // Keyed to the repo this flow actually mutated — a bare refreshStatus()
    // follows activePath, so a repo switch while the dialog/git op was in
    // flight would refresh the wrong repo and leave this one stale.
    await context.read<RepositoryState>().refreshStatusIfActive(repo);
  }

  /// Force-push-with-lease recovery. Surfaced only when the prior sync failed
  /// non-fast-forward. Targets the branch's ACTUAL upstream remote (not blindly
  /// `origin`) and routes the confirm through the shared [confirmForcePush]
  /// guard — lease-only, never bare force.
  Future<void> _runForcePushRecovery(
    String repo,
    RepositoryStatus status,
  ) async {
    final target = resolveUpstream(status);
    if (target == null) {
      setState(() {
        _actionError =
            i18n.t.sync.panel.noUpstreamForForcePush(branch: status.branch);
      });
      return;
    }
    final confirmed = await confirmForcePush(
      context,
      remote: target.remote,
      branch: target.branch,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _forceRunning = true;
      _actionError = null;
    });
    final r = await pushRemote(
      repo,
      remote: target.remote,
      // Explicit local:upstream refspec so the force-push lands on the ref
      // the confirm named, not a remote branch matching the local name
      // (they differ when the branch tracks a differently-named upstream).
      branch: '${status.branch}:${target.branch}',
      forceWithLease: true,
    );
    if (!mounted) return;
    setState(() {
      _forceRunning = false;
      _actionError = r.ok ? null : r.error;
    });
    // Keyed to the repo this flow actually mutated — a bare refreshStatus()
    // follows activePath, so a repo switch while the dialog/git op was in
    // flight would refresh the wrong repo and leave this one stale.
    await context.read<RepositoryState>().refreshStatusIfActive(repo);
  }

  Future<void> _runFetch(String repo) async {
    setState(() {
      _fetchRunning = true;
      _actionError = null;
    });
    final r = await fetchRemote(repo, prune: true);
    if (!mounted) return;
    setState(() {
      _fetchRunning = false;
      if (r.ok) {
        _lastResult = r.data;
      } else {
        _actionError = r.error;
      }
    });
    // Keyed to the repo this flow actually mutated — a bare refreshStatus()
    // follows activePath, so a repo switch while the dialog/git op was in
    // flight would refresh the wrong repo and leave this one stale.
    await context.read<RepositoryState>().refreshStatusIfActive(repo);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Narrow the RepositoryState subscription to the fields the flyout rebuilds
    // against. `repo` below is a `context.read` view for mutating methods.
    final repoSnapshot = context.select<
        RepositoryState,
        ({String? path, RepositoryStatus? status, bool loading, String? error})>(
      (s) => (
        path: s.activePath,
        status: s.status,
        loading: s.statusLoading,
        error: s.statusError,
      ),
    );
    final repoPath = repoSnapshot.path;
    final status = repoSnapshot.status;
    final action = describeSyncAction(status);

    return MaterialSurface(
      tone: AppMaterialTone.panelStrong,
      borderAlpha: 0.22,
      elevated: true,
      innerHighlight: true,
      glaze: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: _buildBody(
          t: t,
          repoPath: repoPath,
          status: status,
          loading: repoSnapshot.loading,
          error: repoSnapshot.error,
          action: action,
        ),
      ),
    );
  }

  Widget _buildBody({
    required AppTokens t,
    required String? repoPath,
    required RepositoryStatus? status,
    required bool loading,
    required String? error,
    required SyncActionDescriptor action,
  }) {
    if (repoPath == null) {
      return const AppStatusView.noRepository(compact: true);
    }
    if (status == null && loading) {
      return AppStatusView.loading(
        title: i18n.t.sync.panel.loadingTitle,
        message: i18n.t.sync.panel.loadingMessage,
        compact: true,
      );
    }
    if (status == null && error != null) {
      return AppStatusView.error(
        title: i18n.t.sync.panel.remoteStatusUnavailable,
        message: error,
        compact: true,
      );
    }
    if (status == null) {
      return AppStatusView.loading(
        title: i18n.t.sync.panel.loadingTitle,
        message: i18n.t.sync.panel.loadingMessage,
        compact: true,
      );
    }

    return _SyncBody(
      t: t,
      status: status,
      action: action,
      busy: _busy,
      syncRunning: _syncRunning,
      fetchRunning: _fetchRunning,
      actionError: _actionError,
      lastResult: _lastResult,
      pendingConflicts: _pendingConflicts,
      forceRunning: _forceRunning,
      onClose: widget.onClose,
      onResolveConflicts: () => _resolvePendingConflicts(repoPath),
      onSync: () => _runSync(repoPath, status),
      onFetch: () => _runFetch(repoPath),
      onForcePushRecovery: () => _runForcePushRecovery(repoPath, status),
    );
  }
}

class _SyncBody extends StatelessWidget {
  final AppTokens t;
  final RepositoryStatus status;
  final SyncActionDescriptor action;
  final bool busy;
  final bool syncRunning;
  final bool fetchRunning;
  final String? actionError;
  final SyncData? lastResult;
  final List<String>? pendingConflicts;
  final bool forceRunning;
  final VoidCallback onClose;
  final VoidCallback? onResolveConflicts;
  final VoidCallback onSync;
  final VoidCallback onFetch;
  final VoidCallback? onForcePushRecovery;

  const _SyncBody({
    required this.t,
    required this.status,
    required this.action,
    required this.busy,
    required this.syncRunning,
    required this.fetchRunning,
    required this.actionError,
    required this.lastResult,
    required this.pendingConflicts,
    required this.forceRunning,
    required this.onClose,
    required this.onResolveConflicts,
    required this.onSync,
    required this.onFetch,
    required this.onForcePushRecovery,
  });

  @override
  Widget build(BuildContext context) {
    final showLog = lastResult != null &&
        lastResult!.operation != 'fetch' &&
        lastResult!.output.isNotEmpty;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(14),
      children: [
        // Compact header: branch → upstream, close.
        Row(children: [
          MaterialSurface(
            tone: AppMaterialTone.surface0,
            radius: 6,
            elevated: false,
            borderColor: t.itemActiveBorder,
            borderAlpha: 1,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(name: 'git-branch', size: 12, color: t.accentBright),
              const SizedBox(width: 5),
              Text(status.branch,
                  style: TextStyle(
                      color: t.textStrong,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(width: 7),
          Text('⇢',
              style: TextStyle(
                  color: t.textFaint,
                  fontSize: 11,
                  fontFamily: AppFonts.mono)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              status.upstream ?? i18n.t.sync.panel.noUpstream,
              style: TextStyle(
                  color: status.upstream != null ? t.textMuted : t.textFaint,
                  fontSize: 11,
                  fontFamily: AppFonts.mono),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _CloseGlyph(t: t, onTap: onClose),
        ]),
        const SizedBox(height: 12),

        // Counts hero — git-status coloured (ahead = added, behind = modified).
        Row(children: [
          _SummaryPill(
              label: i18n.t.sync.panel.aheadLabel,
              value: '${status.ahead}',
              color: status.ahead > 0 ? t.stateAdded : t.textMuted,
              t: t),
          const SizedBox(width: 6),
          _SummaryPill(
              label: i18n.t.sync.panel.behindLabel,
              value: '${status.behind}',
              color: status.behind > 0 ? t.stateModified : t.textMuted,
              t: t),
          const SizedBox(width: 6),
          _SummaryPill(
              label: i18n.t.sync.panel.treeLabel,
              value: '${status.files.length}',
              color: t.textMuted,
              t: t),
        ]),
        const SizedBox(height: 14),

        // Action block: the detail sentence (spells out the rebase when the
        // branch has diverged) + primary sync / fetch-only. No heading — the
        // button already carries the verb; saying "Sync" twice was noise.
        Text(action.detail,
            style:
                TextStyle(color: t.textMuted, fontSize: 11.5, height: 1.45)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _PrimaryBtn(
              label: syncRunning
                  ? i18n.t.sync.panel.runningSync
                  : action.buttonLabel,
              t: t,
              enabled: !busy && !action.disabled,
              onTap: onSync,
            ),
          ),
          const SizedBox(width: 8),
          _GhostBtn(
            label: fetchRunning
                ? i18n.t.sync.panel.fetching
                : i18n.t.sync.panel.fetchOnly,
            t: t,
            enabled: !busy,
            onTap: onFetch,
          ),
        ]),

        // Error — with force-push-with-lease recovery when the failure looks
        // like a non-fast-forward. The recovery is the only place force-push is
        // surfaced, and only in the exact context where it's the right answer.
        if (actionError != null) ...[
          const SizedBox(height: 12),
          _InlineSyncError(
            t: t,
            title: i18n.t.sync.panel.syncFailed,
            body: actionError!,
            recoveryLabel:
                isNonFastForwardError(actionError) && onForcePushRecovery != null
                    ? i18n.t.sync.panel.forcePushRecoveryLabel
                    : null,
            onRecovery:
                isNonFastForwardError(actionError) ? onForcePushRecovery : null,
            recoveryRunning: forceRunning,
          ),
        ],

        // Unresolved conflicts — one click re-enters the same merge flow.
        if (pendingConflicts != null && pendingConflicts!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InlineSyncError(
            t: t,
            title: i18n.t.sync.panel.conflictsToResolveTitle,
            body: i18n.t.sync.panel.conflictsToResolveBody(
              count: i18n.t.common.fileCount(n: pendingConflicts!.length),
              list: '${pendingConflicts!.take(3).join(', ')}'
                  '${pendingConflicts!.length > 3 ? '…' : ''}',
            ),
            recoveryLabel:
                onResolveConflicts != null
                    ? i18n.t.sync.panel.resolveConflicts
                    : null,
            onRecovery: onResolveConflicts,
            recoveryRunning: syncRunning,
          ),
        ],

        // Activity log.
        if (showLog) ...[
          const SizedBox(height: 12),
          _ActivityLog(t: t, result: lastResult!),
        ],
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final AppTokens t;
  const _SummaryPill(
      {required this.label,
      required this.value,
      required this.color,
      required this.t});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MaterialSurface(
        tone: AppMaterialTone.surface0,
        radius: context.surfaceShader.geometry.badgeRadius,
        elevated: false,
        borderColor: color.withValues(alpha: 0.14),
        borderAlpha: 1,
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(children: [
          Text(label.toLowerCase(),
              style: TextStyle(
                  color: color.withValues(alpha: 0.65),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontFamily: AppFonts.mono,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Quiet ✕ in the panel corner — glyph, not a labeled button; brightens
/// on hover like every dismiss affordance in the app's overlays.
class _CloseGlyph extends StatefulWidget {
  final AppTokens t;
  final VoidCallback onTap;
  const _CloseGlyph({required this.t, required this.onTap});

  @override
  State<_CloseGlyph> createState() => _CloseGlyphState();
}

class _CloseGlyphState extends State<_CloseGlyph> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AppIcon(
            name: 'x',
            size: 12,
            color: _hov ? t.textNormal : t.textMuted,
          ),
        ),
      ),
    );
  }
}

class _InlineSyncError extends StatelessWidget {
  final AppTokens t;
  final String title;
  final String body;
  final String? recoveryLabel;
  final VoidCallback? onRecovery;
  final bool recoveryRunning;

  const _InlineSyncError({
    required this.t,
    required this.title,
    required this.body,
    this.recoveryLabel,
    this.onRecovery,
    this.recoveryRunning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.stateConflicted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.stateConflicted.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: TextStyle(
                  color: t.stateConflicted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body,
              style: TextStyle(
                  color: t.stateConflicted, fontSize: 12, height: 1.45)),
          if (recoveryLabel != null && onRecovery != null) ...[
            const SizedBox(height: 10),
            _RecoveryButton(
              tokens: t,
              label: recoveryLabel!,
              running: recoveryRunning,
              onTap: onRecovery!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Thin recovery-action button that lives inside [_InlineSyncError] — same
/// chrome register as the primary sync button but smaller and error-tinted.
class _RecoveryButton extends StatefulWidget {
  final AppTokens tokens;
  final String label;
  final VoidCallback onTap;
  final bool running;
  const _RecoveryButton({
    required this.tokens,
    required this.label,
    required this.onTap,
    required this.running,
  });

  @override
  State<_RecoveryButton> createState() => _RecoveryButtonState();
}

class _RecoveryButtonState extends State<_RecoveryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor:
          widget.running ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.running ? null : widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.snap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered
                ? t.stateConflicted.withValues(alpha: 0.16)
                : t.stateConflicted.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(
              context.surfaceShader.geometry.pillRadius,
            ),
            border: Border.all(
              color: t.stateConflicted.withValues(alpha: 0.45),
              width: 0.8,
            ),
          ),
          child: Text(
            widget.running ? i18n.t.sync.panel.workingEllipsis : widget.label,
            style: TextStyle(
              color: t.stateConflicted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityLog extends StatelessWidget {
  final AppTokens t;
  final SyncData result;
  const _ActivityLog({required this.t, required this.result});

  @override
  Widget build(BuildContext context) {
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      elevated: false,
      borderAlpha: 0.15,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Text(
            i18n.t.sync.panel.lastActivity(operation: result.operation),
            style: TextStyle(
                color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        Divider(height: 1, color: t.chromeBorder.withValues(alpha: 0.1)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            result.output.isEmpty ? i18n.t.sync.panel.noOutput : result.output,
            style: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                fontFamily: AppFonts.mono,
                height: 1.6),
          ),
        ),
      ]),
    );
  }
}

class _PrimaryBtn extends StatefulWidget {
  final String label;
  final AppTokens t;
  final bool enabled;
  final VoidCallback onTap;
  const _PrimaryBtn(
      {required this.label,
      required this.t,
      required this.enabled,
      required this.onTap});
  @override
  State<_PrimaryBtn> createState() => _PrimaryBtnState();
}

class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _hov = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final chrome = primaryButtonChrome(
      t,
      hovered: _hov,
      pressed: _pressed,
      enabled: widget.enabled,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: context.motion(const Duration(milliseconds: 80)),
          scale: chrome.scale,
          child: AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 100)),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: chrome.background,
              gradient: chrome.gradient,
              borderRadius: BorderRadius.circular(
                  context.surfaceShader.geometry.radius),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows,
            ),
            child: Transform.translate(
              offset: chrome.offset,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AppIcon(
                    name: 'sync',
                    size: 13,
                    color: widget.enabled ? t.accentBright : t.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: widget.enabled ? t.btnText : t.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostBtn extends StatefulWidget {
  final String label;
  final AppTokens t;
  final bool enabled;
  final VoidCallback onTap;
  const _GhostBtn(
      {required this.label,
      required this.t,
      this.enabled = true,
      required this.onTap});
  @override
  State<_GhostBtn> createState() => _GhostBtnState();
}

class _GhostBtnState extends State<_GhostBtn> {
  bool _hov = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final chrome = ghostButtonChrome(
      t,
      hovered: _hov,
      pressed: _pressed,
      enabled: widget.enabled,
      baseBorderColor: t.secondaryBtnBorder,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 100)),
          // Matches the primary button's height so the action row reads as
          // one register, not a big button with a satellite.
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: chrome.background,
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.radius),
            border: Border.all(color: chrome.borderColor),
            boxShadow: chrome.shadows,
          ),
          child: Transform.translate(
            offset: chrome.offset,
            child: Center(
              child: Text(widget.label,
                  style: TextStyle(
                      color: widget.enabled ? t.textNormal : t.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ),
    );
  }
}
