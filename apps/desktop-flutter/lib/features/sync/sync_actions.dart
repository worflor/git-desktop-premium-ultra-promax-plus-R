import '../../backend/dtos.dart';
import '../../i18n/gen/strings.g.dart';

/// Shared, headless sync semantics — the single source of truth for the
/// labels/tooltips every sync surface shows (the topbar control, the clean-
/// tree split pill, and the sync flyout). Keeping the wording here means the
/// three surfaces can't drift, and the diverged-branch case always spells out
/// the rebase before it runs.

/// What the primary sync action will do for the current [RepositoryStatus],
/// resolved once and shared across surfaces. [detail] is the human sentence
/// (also used as the tooltip); [buttonLabel] the terse action word.
class SyncActionDescriptor {
  final String label;
  final String detail;
  final String buttonLabel;
  final bool disabled;

  /// True when the primary action rebases local commits onto the upstream
  /// before pushing (ahead AND behind). Surfaces key their "with rebase"
  /// wording off this so the user knows history will be replayed.
  final bool rebases;

  const SyncActionDescriptor({
    required this.label,
    required this.detail,
    required this.buttonLabel,
    this.disabled = false,
    this.rebases = false,
  });
}

SyncActionDescriptor describeSyncAction(RepositoryStatus? status) {
  if (status == null) {
    return SyncActionDescriptor(
      label: t.sync.actions.syncLabel,
      detail: t.sync.actions.syncOpenRepoDetail,
      buttonLabel: t.sync.actions.syncLabel,
      disabled: true,
    );
  }

  final branch = status.branch;
  if (branch == 'HEAD' || branch.startsWith('(')) {
    return SyncActionDescriptor(
      label: t.sync.actions.detachedHeadLabel,
      detail: t.sync.actions.detachedHeadDetail,
      buttonLabel: t.sync.actions.detachedHeadLabel,
      disabled: true,
    );
  }

  if (status.upstream == null) {
    return SyncActionDescriptor(
      label: t.sync.actions.publishBranchLabel,
      detail: t.sync.actions.publishBranchDetail(branch: branch),
      buttonLabel: t.sync.actions.publishButtonLabel,
    );
  }

  if (status.ahead > 0 && status.behind > 0) {
    return SyncActionDescriptor(
      label: t.sync.actions.syncBranchLabel,
      detail: t.sync.actions.syncBranchDetail(
        behindCount: t.common.commitCount(n: status.behind),
        aheadCount: t.common.commitCount(n: status.ahead),
      ),
      buttonLabel: t.sync.actions.syncBranchButtonLabel,
      rebases: true,
    );
  }

  if (status.ahead > 0) {
    return SyncActionDescriptor(
      label: t.sync.actions.pushBranchLabel,
      detail: t.sync.actions.pushBranchDetail(
        count: t.common.localCommitCount(n: status.ahead),
        upstream: status.upstream!,
      ),
      buttonLabel: t.sync.actions.pushBranchButtonLabel,
    );
  }

  if (status.behind > 0) {
    return SyncActionDescriptor(
      label: t.sync.actions.pullUpdatesLabel,
      detail: t.sync.actions.pullUpdatesDetail(
        count: t.common.remoteCommitCount(n: status.behind),
        upstream: status.upstream!,
      ),
      buttonLabel: t.sync.actions.pullUpdatesLabel,
    );
  }

  return SyncActionDescriptor(
    label: t.sync.actions.syncLabel,
    detail: t.sync.actions.syncUpToDateDetail(upstream: status.upstream!),
    buttonLabel: t.sync.actions.syncLabel,
  );
}

/// True when [stderr] looks like git rejected the push for being
/// non-fast-forward. Matches the canonical phrases git emits across its
/// localised messages and the older "Updates were rejected" form.
/// Conservative: false negatives are fine (no recovery offered), false
/// positives would be worse (offering force-push for the wrong error).
bool isNonFastForwardError(String? stderr) {
  if (stderr == null) return false;
  final s = stderr.toLowerCase();
  return s.contains('non-fast-forward') ||
      (s.contains('rejected') && s.contains('fetch first')) ||
      (s.contains('rejected') && s.contains('non-fast'));
}

/// Resolved push target — the remote name plus the remote-branch ref the
/// user's local branch tracks. Threaded through the force-push confirm so
/// the user sees exactly which destination is about to be overwritten.
class UpstreamTarget {
  final String remote;
  final String branch;
  const UpstreamTarget({required this.remote, required this.branch});
}

/// Parse `status.upstream` (shape: `<remote>/<remote-branch-ref>`, where the
/// ref may itself contain slashes for nested branch names like `feature/foo`)
/// into its components. Returns null when no upstream is configured or the
/// value is malformed. The `remote` is everything before the FIRST slash;
/// the rest is the remote ref.
UpstreamTarget? resolveUpstream(RepositoryStatus status) {
  final upstream = status.upstream;
  if (upstream == null || upstream.isEmpty) return null;
  final slash = upstream.indexOf('/');
  if (slash <= 0 || slash >= upstream.length - 1) return null;
  return UpstreamTarget(
    remote: upstream.substring(0, slash),
    branch: upstream.substring(slash + 1),
  );
}
