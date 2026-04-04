import { createEffect, createResource, createSignal, onMount, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { Icon } from "@/components/icons/Icon";
import { createBranch, listBranches, checkoutBranch } from "@/lib/backend/commands";
import { recordUiTiming } from "@/lib/telemetry/uiTiming";

interface BranchesPageProps {
  embedded?: boolean;
}

export function BranchesPage(props: BranchesPageProps = {}) {
  const mountedAt = performance.now();
  const repository = useRepositoryContext();
  const [newBranchName, setNewBranchName] = createSignal("");
  const [actionError, setActionError] = createSignal<string | null>(null);
  const [actionRunning, setActionRunning] = createSignal(false);
  let previousRepositoryPath: string | null | undefined;

  const activeRepo = () => repository.activeRepositoryPath();

  const [branchesResult, { refetch }] = createResource(activeRepo, async (path) => {
    if (!path) {
      return null;
    }
    return listBranches(path);
  });

  createEffect(() => {
    const repositoryPath = activeRepo();
    if (previousRepositoryPath !== repositoryPath) {
      previousRepositoryPath = repositoryPath;
      setNewBranchName("");
      setActionError(null);
      setActionRunning(false);
    }
  });

  const onCreateBranch = async () => {
    const repo = activeRepo();
    const branchName = newBranchName().trim();
    if (!repo || !branchName) return;

    setActionError(null);
    setActionRunning(true);
    try {
      const result = await createBranch(repo, branchName, "HEAD");
      if (activeRepo() !== repo) {
        return;
      }

      if (!result.ok) {
        setActionError(result.error.message);
        return;
      }

      setNewBranchName("");
      void refetch();
    } finally {
      setActionRunning(false);
    }
  };

  const onCheckoutBranch = async (branchName: string) => {
    const repo = activeRepo();
    if (!repo) return;

    setActionError(null);
    setActionRunning(true);
    try {
      const result = await checkoutBranch(repo, branchName);
      if (activeRepo() !== repo) {
        return;
      }

      if (!result.ok) {
        setActionError(result.error.message);
        return;
      }

      void refetch();
    } finally {
      setActionRunning(false);
    }
  };

  onMount(() => {
    requestAnimationFrame(() => {
      recordUiTiming({
        event: "branches.page.first-paint",
        phase: "mount",
        durationMs: performance.now() - mountedAt
      });
    });
  });

  return (
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`} style="display: flex; flex-direction: column; height: 100%; overflow: hidden; background: var(--surface-0);">
      <Show when={!activeRepo()}>
        <div style="padding: 16px; width: 100%; display: flex; align-items: center; justify-content: center;">
          <EmptyStateCard
            title="No repository selected"
            body="Add or open a repository from Projects to manage branches."
          />
        </div>
      </Show>

      <Show when={branchesResult.loading}>
        <div style="padding: 16px;"><LoadingStateSkeleton /></div>
      </Show>

      <Show when={branchesResult.latest && !branchesResult.latest.ok}>
        <div style="padding: 16px;">
          <ErrorStateCard
            title="Branch lookup failed"
            body={branchesResult.latest && !branchesResult.latest.ok ? branchesResult.latest.error.message : "Unknown error"}
          />
        </div>
      </Show>

      <Show when={branchesResult.latest?.ok}>
        <div style="padding: 12px 16px; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.15); background: var(--surface-1); display: flex; align-items: center; justify-content: space-between; flex-shrink: 0;">
          <h2 style="margin: 0; font-size: 14px; font-weight: 600; display: flex; align-items: center; gap: 8px;">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon"><line x1="6" y1="3" x2="6" y2="15"></line><circle cx="18" cy="6" r="3"></circle><circle cx="6" cy="18" r="3"></circle><path d="M18 9a9 9 0 0 1-9 9"></path></svg>
            Branches
          </h2>
          <span style="font-size: 11px; color: var(--text-muted); background: rgba(var(--chrome-border-rgb), 0.1); padding: 2px 8px; border-radius: 12px;">{branchesResult.latest?.ok ? branchesResult.latest.data.branches.length : 0} Local</span>
        </div>

        <div style="flex: 1; display: flex; overflow: hidden;">
          {/* Main Branches List */}
          <div style="flex: 1; overflow-y: auto; padding: 16px; display: flex; flex-direction: column; gap: 8px; border-right: 1px solid rgba(var(--chrome-border-rgb), 0.15);">
            <div style="margin-bottom: 8px; font-size: 10px; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-muted); font-weight: 600;">Repository Branches</div>
            
            <ul style="margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 4px;">
              {branchesResult.latest?.ok &&
                branchesResult.latest.data.branches.map((branch) => (
                  <li style={`display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; border-radius: 6px; background: ${branch.current ? 'rgba(var(--accent-rgb), 0.06)' : 'var(--surface-1)'}; border: 1px solid ${branch.current ? 'rgba(var(--accent-rgb), 0.2)' : 'rgba(var(--chrome-border-rgb), 0.08)'};`}>
                    <div style="display: flex; flex-direction: column; gap: 4px; min-width: 0;">
                      <div style="display: flex; align-items: center; gap: 8px;">
                        <Show when={branch.current}>
                          <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: var(--accent-bright);"><polyline points="20 6 9 17 4 12"></polyline></svg>
                        </Show>
                        <Show when={!branch.current}>
                           <Icon name="git-branch" size={12} tone="muted" />
                        </Show>
                        <strong style={`font-size: 13px; font-family: var(--font-sans); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; ${branch.current ? "color: var(--text-strong)" : "color: var(--text-normal)"}`}>
                          {branch.name}
                        </strong>
                        <Show when={branch.current}>
                           <span style="font-size: 10px; background: var(--accent-bright); color: var(--surface-0); padding: 1px 6px; border-radius: 10px; font-weight: bold; letter-spacing: 0.02em;">HEAD</span>
                        </Show>
                      </div>
                      <Show when={branch.upstream}>
                        <div style="font-size: 11px; color: var(--text-muted); margin-left: 20px; font-family: var(--font-mono); opacity: 0.8;">
                          → tracking: {branch.upstream}
                        </div>
                      </Show>
                    </div>
                    <button
                      class={`primary-btn ${branch.current ? 'is-active' : ''}`}
                      style={`min-width: 80px; font-size: 11px; padding: 4px 12px; min-height: 24px; visibility: ${branch.current ? 'hidden' : 'visible'}`}
                      disabled={branch.current || actionRunning()}
                      onClick={() => void onCheckoutBranch(branch.name)}
                    >
                      Checkout
                    </button>
                  </li>
                ))}
            </ul>
          </div>

          {/* Sidebar Action Panel */}
          <div style="width: 240px; flex-shrink: 0; background: var(--surface-1); display: flex; flex-direction: column;">
             <div style="padding: 16px; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.1);">
                <div style="font-size: 11px; font-weight: 600; color: var(--text-strong); margin-bottom: 12px;">Create New Branch</div>
                <div style="display: flex; flex-direction: column; gap: 8px;">
                  <input
                    class="path-input"
                    placeholder="Branch name (e.g. feature/auth)"
                    style="width: 100%; font-size: 12px; padding: 6px 8px; font-family: var(--font-mono);"
                    value={newBranchName()}
                    onInput={(event) => setNewBranchName(event.currentTarget.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        void onCreateBranch();
                      }
                    }}
                  />
                  <button
                    class="primary-btn"
                    style="width: 100%; justify-content: center; font-size: 11px; font-weight: 600; padding: 6px; min-height: 26px;"
                    disabled={!newBranchName() || actionRunning()}
                    onClick={() => void onCreateBranch()}
                    title="Create branch"
                  >
                    Create branch from HEAD
                  </button>
                </div>
                <Show when={actionError()}>
                  {(message) => <div style="margin-top: 12px; font-size: 11px; color: var(--state-conflicted); padding: 8px; border-radius: 4px; background: rgba(var(--state-conflicted-rgb, 248,81,73), 0.1); border: 1px solid rgba(var(--state-conflicted-rgb, 248,81,73), 0.2);">{message()}</div>}
                </Show>
             </div>
          </div>
        </div>
      </Show>
    </div>
  );
}
