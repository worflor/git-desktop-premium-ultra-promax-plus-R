import { createSignal, createResource, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { getRepositoryStatus, pullRemote } from "@/lib/backend/commands";

interface SyncPageProps {
  embedded?: boolean;
}

export function SyncPage(props: SyncPageProps = {}) {
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

  return (
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`}>
      <span class="section-summary">Synchronize with remote</span>

      <Show when={statusResult.loading}>
        <LoadingStateSkeleton />
      </Show>

      <Show when={statusResult.latest && !statusResult.latest.ok}>
        <ErrorStateCard
          title="Status lookup failed"
          body={statusResult.latest && !statusResult.latest.ok ? statusResult.latest.error.message : "Unknown error"}
        />
      </Show>

      <Show when={statusResult.latest?.ok}>
        <section class="state-card">
          <div class="sync-card-header">
            <h3>Remote Status</h3>
            <button
              class="primary-btn"
              onClick={() => void onSync()}
              disabled={syncRunning()}
            >
               {syncRunning() ? "Syncing..." : "Sync Now"}
            </button>
          </div>

          <Show when={syncError()}>
            {(message) => <div style="margin-bottom: 8px;"><ErrorStateCard title="Sync failed" body={message()} /></div>}
          </Show>

          <div class="info-grid">
            <div class="state-card">
              <span class="section-summary">Tracking</span>
              <p style="margin: 4px 0 0; font-family: var(--font-mono); font-size: 13px; color: var(--text-strong);">
                {statusResult.latest?.ok ? statusResult.latest.data.branch || "None (local only)" : "Unknown"}
              </p>
            </div>
            <div class="state-card">
              <span class="section-summary">Ahead / Behind</span>
              <p style="margin: 4px 0 0; font-size: 13px; color: var(--text-strong);">
                ↑ {statusResult.latest?.ok ? statusResult.latest.data.ahead : 0} 
                {" / "}
                ↓ {statusResult.latest?.ok ? statusResult.latest.data.behind : 0}
              </p>
            </div>
          </div>
        </section>
      </Show>
    </div>
  );
}
