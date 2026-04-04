import { createMemo, createResource, createSignal, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { Icon } from "@/components/icons/Icon";
import { fetchRemote, getRepositoryStatus, syncRemote } from "@/lib/backend/commands";
import type { CommandResult } from "@/lib/contracts/command";
import type { SyncData } from "@/lib/backend/dtos";

interface SyncPanelProps {
  onClose: () => void;
  onStatusChanged?: () => void;
}

interface SyncActionDescriptor {
  label: string;
  detail: string;
  buttonLabel: string;
  disabled?: boolean;
}

interface SyncMetricDescriptor {
  label: string;
  shortLabel: string;
  symbol: "push" | "pull" | "tree";
  value: string;
  tone?: "ahead" | "behind";
}

function pluralize(value: number, noun: string): string {
  return `${value} ${noun}${value === 1 ? "" : "s"}`;
}

function describePrimaryAction(
  status: {
    branch: string;
    upstream?: string;
    ahead: number;
    behind: number;
  } | null
): SyncActionDescriptor {
  if (!status) {
    return {
      label: "Sync",
      detail: "Open a repository to manage push and pull operations.",
      buttonLabel: "Sync",
      disabled: true
    };
  }

  if (status.branch === "detached" || status.branch === "(detached)") {
    return {
      label: "Detached HEAD",
      detail: "Check out a branch before pushing or pulling.",
      buttonLabel: "Detached HEAD",
      disabled: true
    };
  }

  if (!status.upstream) {
    return {
      label: "Publish branch",
      detail: `Push ${status.branch} and set its upstream tracking branch.`,
      buttonLabel: "Publish branch"
    };
  }

  if (status.ahead > 0 && status.behind > 0) {
    return {
      label: "Sync branch",
      detail: `Pull ${pluralize(status.behind, "commit")} with rebase, then push ${pluralize(status.ahead, "commit")}.`,
      buttonLabel: "Pull then push"
    };
  }

  if (status.ahead > 0) {
    return {
      label: "Push branch",
      detail: `Push ${pluralize(status.ahead, "local commit")} to ${status.upstream}.`,
      buttonLabel: "Push commits"
    };
  }

  if (status.behind > 0) {
    return {
      label: "Pull updates",
      detail: `Pull ${pluralize(status.behind, "remote commit")} from ${status.upstream}.`,
      buttonLabel: "Pull updates"
    };
  }

  return {
    label: "Check remote",
    detail: `Fetch from ${status.upstream} and refresh upstream status.`,
    buttonLabel: "Check remote"
  };
}

function formatDuration(durationMs?: number): string | null {
  if (!durationMs || durationMs <= 0) {
    return null;
  }

  if (durationMs < 1000) {
    return `${durationMs} ms`;
  }

  return `${(durationMs / 1000).toFixed(1)} s`;
}

function describeTreeState(changes: number): string {
  return changes === 0 ? "Clean working tree" : `${pluralize(changes, "changed file")} ready to review`;
}

function describeAheadMetric(ahead: number): SyncMetricDescriptor {
  return {
    label: "Ahead",
    shortLabel: "Push",
    symbol: "push",
    value: ahead === 0 ? "Nothing to push" : pluralize(ahead, "commit"),
    tone: "ahead"
  };
}

function describeBehindMetric(behind: number): SyncMetricDescriptor {
  return {
    label: "Behind",
    shortLabel: "Pull",
    symbol: "pull",
    value: behind === 0 ? "Already caught up" : pluralize(behind, "commit"),
    tone: "behind"
  };
}

function describeTreeMetric(changes: number): SyncMetricDescriptor {
  return {
    label: "Working tree",
    shortLabel: "Files",
    symbol: "tree",
    value: changes === 0 ? "Clean working tree" : pluralize(changes, "changed file")
  };
}

function SyncMetricSymbol(props: { type: SyncMetricDescriptor["symbol"] }) {
  return (
    <svg class={`sync-popover-metric-symbol is-${props.type}`} width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
      <Show when={props.type === "push"}>
        <path d="M7 11V3M7 3l-3 3M7 3l3 3" />
      </Show>
      <Show when={props.type === "pull"}>
        <path d="M7 3v8M7 11l-3-3M7 11l3-3" />
      </Show>
      <Show when={props.type === "tree"}>
        <path d="M3 3h8M3 7h8M3 11h8" />
      </Show>
    </svg>
  );
}

export function SyncPanel(props: SyncPanelProps) {
  const repository = useRepositoryContext();
  const [syncRunning, setSyncRunning] = createSignal(false);
  const [refreshRunning, setRefreshRunning] = createSignal(false);
  const [actionError, setActionError] = createSignal<string | null>(null);
  const [lastResult, setLastResult] = createSignal<CommandResult<SyncData> | null>(null);

  const activeRepo = () => repository.activeRepositoryPath();

  const [statusResult, { refetch }] = createResource(activeRepo, async (path) => {
    if (!path) {
      return null;
    }
    return getRepositoryStatus(path);
  });

  const status = createMemo(() => {
    const latest = statusResult.latest;
    if (!latest?.ok) {
      return null;
    }

    return latest.data;
  });

  const primaryAction = createMemo(() => describePrimaryAction(status()));
  const treeSummary = createMemo(() => describeTreeState(status()?.files.length ?? 0));
  const fetchStatusText = createMemo(() => {
    if (refreshRunning()) {
      return "Checking remote for new commits...";
    }

    const result = lastResult();
    if (result?.ok && result.data.operation === "fetch") {
      return "Remote status refreshed";
    }

    return treeSummary();
  });
  const metrics = createMemo(() => {
    const resolvedStatus = status();
    if (!resolvedStatus) {
      return [];
    }

    return [
      describeAheadMetric(resolvedStatus.ahead),
      describeBehindMetric(resolvedStatus.behind),
      describeTreeMetric(resolvedStatus.files.length)
    ];
  });

  const refreshStatus = async () => {
    const repo = activeRepo();
    if (!repo) return;

    setActionError(null);
    setRefreshRunning(true);
    const result = await fetchRemote(repo, undefined, true);
    setRefreshRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setLastResult(result);
    await refetch();
    props.onStatusChanged?.();
  };

  const runPrimarySync = async () => {
    const repo = activeRepo();
    if (!repo || primaryAction().disabled) return;

    setActionError(null);
    setSyncRunning(true);
    const result = await syncRemote(repo);
    setSyncRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setLastResult(result);
    await refetch();
    props.onStatusChanged?.();
  };

  const lastDuration = createMemo(() => formatDuration(lastResult()?.meta?.durationMs));
  const successfulLastResult = createMemo(() => {
    const result = lastResult();
    return result?.ok ? result : null;
  });
  const shouldShowActivityLog = createMemo(() => {
    const result = successfulLastResult();
    if (!result) {
      return false;
    }

    if (result.data.operation !== "fetch") {
      return true;
    }

    const output = result.data.output.trim().toLowerCase();
    if (!output) {
      return false;
    }

    return !output.includes("no local commits needed syncing");
  });

  return (
    <div class="sync-popover-layer is-open" aria-hidden="false">
      <button
        type="button"
        class="sync-popover-backdrop"
        aria-label="Close sync panel"
        onClick={props.onClose}
      />
      <section class="sync-popover-panel" role="dialog" aria-modal="true" aria-labelledby="sync-panel-title">
        <header class="sync-popover-header">
          <div class="sync-popover-heading">
            <span class="sync-popover-kicker">Remote</span>
            <h2 id="sync-panel-title">Sync</h2>
          </div>
          <button type="button" class="ghost-btn sync-popover-close" onClick={props.onClose}>
            Close
          </button>
        </header>

        <div class="sync-popover-body">
          <Show
            when={activeRepo()}
            fallback={
              <div class="sync-popover-empty">
                <EmptyStateCard
                  title="No repository selected"
                  body="Open a repository from Projects before pushing or pulling."
                />
              </div>
            }
          >
            <Show when={statusResult.loading}>
              <LoadingStateSkeleton />
            </Show>

            <Show when={statusResult.latest && !statusResult.latest.ok}>
              <ErrorStateCard
                title="Status lookup failed"
                body={statusResult.latest && !statusResult.latest.ok ? statusResult.latest.error.message : "Unknown error"}
              />
            </Show>

            <Show when={status()}>
              {(resolvedStatus) => (
                <>
                  <div class="sync-popover-shell">
                    <div class="sync-popover-hero">
                      <div class="sync-popover-branch-block">
                        <span class="sync-popover-branch-kicker">Current branch</span>
                        <div class="sync-popover-branch-line">
                          <div class="sync-popover-branch">
                            <Icon name="git-branch" size={12} />
                            <span>{resolvedStatus().branch}</span>
                          </div>
                          <span class="sync-popover-chip">
                            {resolvedStatus().upstream ?? "No upstream"}
                          </span>
                        </div>
                      </div>
                      <div class="sync-popover-summary-pills" aria-label="Repository sync summary">
                        <span class="sync-popover-summary-pill is-ahead">
                          <span class="sync-popover-summary-pill-label">Ahead</span>
                          <strong class="sync-popover-summary-pill-value is-ahead">{resolvedStatus().ahead}</strong>
                        </span>
                        <span class="sync-popover-summary-pill is-behind">
                          <span class="sync-popover-summary-pill-label">Behind</span>
                          <strong class="sync-popover-summary-pill-value is-behind">{resolvedStatus().behind}</strong>
                        </span>
                        <span class="sync-popover-summary-pill is-tree">
                          <span class="sync-popover-summary-pill-label">Tree</span>
                          <strong class="sync-popover-summary-pill-value">{resolvedStatus().files.length}</strong>
                        </span>
                      </div>
                    </div>

                    <div class="sync-popover-action-block">
                      <div class="sync-popover-action-copy">
                        <div class="sync-popover-action-title-row">
                          <h3>{primaryAction().label}</h3>
                          <span class={`sync-popover-action-state ${refreshRunning() ? "is-busy" : ""}`.trim()}>
                            {fetchStatusText()}
                          </span>
                        </div>
                        <p class="sync-popover-summary-text">{primaryAction().detail}</p>
                      </div>
                      <div class="sync-popover-actions">
                        <button
                          type="button"
                          class="primary-btn sync-popover-primary"
                          disabled={syncRunning() || refreshRunning() || primaryAction().disabled}
                          onClick={() => void runPrimarySync()}
                        >
                          <span class="sync-popover-primary-content">
                            <Icon name="sync" size={12} />
                            <span>{syncRunning() ? "Running sync..." : primaryAction().buttonLabel}</span>
                          </span>
                        </button>
                        <button
                          type="button"
                          class="ghost-btn sync-popover-secondary sync-popover-fetch-only"
                          disabled={syncRunning() || refreshRunning()}
                          onClick={() => void refreshStatus()}
                          title="Fetch remote refs only"
                        >
                          <span class="sync-popover-secondary-kicker">Utility</span>
                          <span>{refreshRunning() ? "Fetching..." : "Fetch only"}</span>
                        </button>
                      </div>
                    </div>

                    <div class="sync-popover-metrics" aria-label="Detailed sync metrics">
                      {metrics().map((metric) => (
                        <div class={`sync-popover-metric ${metric.tone ? `is-${metric.tone}` : ""}`.trim()}>
                          <div class="sync-popover-metric-copy">
                            <span class="sync-popover-metric-label">
                              <SyncMetricSymbol type={metric.symbol} />
                              <span>{metric.label}</span>
                            </span>
                            <span class="sync-popover-metric-short">{metric.shortLabel}</span>
                          </div>
                          <strong class={`sync-popover-metric-value ${metric.tone ? `is-${metric.tone}` : ""}`.trim()}>
                            {metric.value}
                          </strong>
                        </div>
                      ))}
                    </div>
                  </div>

                  <Show when={actionError()}>
                    {(message) => (
                      <div class="sync-popover-error" role="alert">
                        {message()}
                      </div>
                    )}
                  </Show>

                  <Show when={shouldShowActivityLog() && successfulLastResult()}>
                    {(result) => (
                      <div class="sync-popover-log">
                        <div class="sync-popover-log-header">
                          <span>
                            Last sync activity: {result().data.operation}
                            <Show when={lastDuration()}>
                              {(duration) => <span class="sync-popover-log-meta">{duration()}</span>}
                            </Show>
                          </span>
                        </div>
                        <pre class="sync-output">{result().data.output}</pre>
                      </div>
                    )}
                  </Show>
                </>
              )}
            </Show>
          </Show>
        </div>
      </section>
    </div>
  );
}
