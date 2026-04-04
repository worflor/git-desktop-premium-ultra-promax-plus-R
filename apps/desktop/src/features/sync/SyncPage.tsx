import { createSignal, createResource, onMount, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { getRepositoryStatus, pullRemote } from "@/lib/backend/commands";
import { recordUiTiming } from "@/lib/telemetry/uiTiming";

interface SyncPageProps {
  embedded?: boolean;
}

export function SyncPage(props: SyncPageProps = {}) {
  const mountedAt = performance.now();
  const repository = useRepositoryContext();
  const [syncRunning, setSyncRunning] = createSignal(false);
  const [syncError, setSyncError] = createSignal<string | null>(null);

  const activeRepo = () => repository.activeRepositoryPath();

  const [statusResult, { refetch }] = createResource(activeRepo, async (path) => {
    if (!path) {
      return null;
    }
    return getRepositoryStatus(path);
  });

  const onSync = async () => {
    const repo = activeRepo();
    if (!repo) return;

    setSyncRunning(true);
    setSyncError(null);
    const result = await pullRemote(repo);
    setSyncRunning(false);

    if (!result.ok) {
      setSyncError(result.error.message);
    }
    void refetch();
  };

  onMount(() => {
    requestAnimationFrame(() => {
      recordUiTiming({
        event: "sync.page.first-paint",
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
            body="Add or open a repository from Projects to sync with remotes."
          />
        </div>
      </Show>

      <Show when={statusResult.loading}>
        <div style="padding: 16px;"><LoadingStateSkeleton /></div>
      </Show>

      <Show when={statusResult.latest && !statusResult.latest.ok}>
        <div style="padding: 16px;">
          <ErrorStateCard
            title="Status lookup failed"
            body={statusResult.latest && !statusResult.latest.ok ? statusResult.latest.error.message : "Unknown error"}
          />
        </div>
      </Show>

      <Show when={statusResult.latest?.ok}>
        <div style="padding: 12px 16px; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.15); background: var(--surface-1); display: flex; align-items: center; justify-content: space-between; flex-shrink: 0;">
          <h2 style="margin: 0; font-size: 14px; font-weight: 600; display: flex; align-items: center; gap: 8px;">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.59-9.21l-5.69-5.69m-8.79 3A10 10 0 0 1 12 2a10 10 0 0 1 8.35 4.63l3.6-2.58A13.9 13.9 0 0 0 12 0 14 14 0 0 0 0 15a13.96 13.96 0 0 0 4.14 9.17l4.08-4.08A9.95 9.95 0 0 1 6.3 12z"></path><path d="M21.5 2v6h-6"></path><path d="M2.5 22v-6h6"></path><path d="M2.66 8.43a10 10 0 1 1 .59 9.21l5.69 5.69"></path></svg>
            Sync
          </h2>
          <span style="font-size: 11px; color: var(--text-muted); background: rgba(var(--chrome-border-rgb), 0.1); padding: 2px 8px; border-radius: 12px;">{statusResult.latest?.ok ? statusResult.latest.data.branch || "HEAD" : "HEAD"}</span>
        </div>

        <div style="flex: 1; overflow-y: auto; padding: 24px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 24px;">
          <div style="max-width: 400px; width: 100%; border: 1px solid rgba(var(--chrome-border-rgb), 0.15); border-radius: 8px; background: var(--surface-1); overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">
            <div style="padding: 16px; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.1);">
              <h3 style="margin: 0 0 4px 0; font-size: 14px; color: var(--text-strong);">Remote Status</h3>
              <p style="margin: 0; font-size: 12px; color: var(--text-muted);">Compare local commits with tracking branch</p>
            </div>
            <div style="display: flex; padding: 16px; gap: 16px; text-align: center;">
               <div style="flex: 1; padding: 16px; border-radius: 6px; background: rgba(var(--chrome-border-rgb), 0.05); border: 1px solid rgba(var(--chrome-border-rgb), 0.1);">
                 <div style="font-size: 24px; font-weight: 700; color: var(--text-strong); font-family: var(--font-mono); line-height: 1;">
                   {statusResult.latest?.ok ? statusResult.latest.data.ahead : 0}
                 </div>
                 <div style="margin-top: 8px; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: var(--state-added, #2ea043); display: flex; align-items: center; justify-content: center; gap: 4px;">
                   <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon"><line x1="12" y1="19" x2="12" y2="5"></line><polyline points="5 12 12 5 19 12"></polyline></svg>
                   Ahead
                 </div>
               </div>
               <div style="flex: 1; padding: 16px; border-radius: 6px; background: rgba(var(--chrome-border-rgb), 0.05); border: 1px solid rgba(var(--chrome-border-rgb), 0.1);">
                 <div style="font-size: 24px; font-weight: 700; color: var(--text-strong); font-family: var(--font-mono); line-height: 1;">
                   {statusResult.latest?.ok ? statusResult.latest.data.behind : 0}
                 </div>
                 <div style="margin-top: 8px; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: var(--state-deleted, #f85149); display: flex; align-items: center; justify-content: center; gap: 4px;">
                   <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon"><line x1="12" y1="5" x2="12" y2="19"></line><polyline points="19 12 12 19 5 12"></polyline></svg>
                   Behind
                 </div>
               </div>
            </div>
            <div style="padding: 16px; border-top: 1px solid rgba(var(--chrome-border-rgb), 0.1); background: var(--surface-0);">
               <Show when={syncError()}>
                 {(message) => <div style="margin-bottom: 12px; font-size: 12px; color: var(--state-conflicted); padding: 8px 12px; border-radius: 6px; background: rgba(var(--state-conflicted-rgb, 248,81,73), 0.1); border: 1px solid rgba(var(--state-conflicted-rgb, 248,81,73), 0.2);">{message()}</div>}
               </Show>
               <button
                class="primary-btn"
                style="width: 100%; justify-content: center; font-size: 13px; font-weight: 600; padding: 8px; min-height: 32px;"
                onClick={() => void onSync()}
                disabled={syncRunning() || !(statusResult.latest?.ok && statusResult.latest.data.branch)}
               >
                 <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon" style={`margin-right: 6px; ${syncRunning() ? 'animation: settings-inline-spin 1s linear infinite;' : ''}`}><polyline points="1 4 1 10 7 10"></polyline><polyline points="23 20 23 14 17 14"></polyline><path d="M20.49 9A9 9 0 0 0 5.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 0 1 3.51 15"></path></svg>
                 {syncRunning() ? "Synchronizing with remote..." : "Pull & Push"}
               </button>
               <div style="text-align: center; margin-top: 12px; font-size: 11px; color: var(--text-muted); font-family: var(--font-mono);">
                 Tracking: {statusResult.latest?.ok ? statusResult.latest.data.branch || "None" : "Unknown"} 
               </div>
            </div>
          </div>
        </div>
      </Show>
    </div>
  );
}
