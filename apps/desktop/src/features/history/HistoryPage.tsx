import { createEffect, createResource, createSignal, onMount, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { getCommitDetail, listCommitHistory } from "@/lib/backend/commands";
import { recordUiTiming } from "@/lib/telemetry/uiTiming";

interface HistoryPageProps {
  embedded?: boolean;
}

export function HistoryPage(props: HistoryPageProps = {}) {
  const mountedAt = performance.now();
  const repository = useRepositoryContext();
  const [historyLimitInput, setHistoryLimitInput] = createSignal("50");
  const [selectedCommitHash, setSelectedCommitHash] = createSignal<string | null>(null);

  const activeRepo = () => repository.activeRepositoryPath();

  const parsedLimit = () => {
    const parsed = Number.parseInt(historyLimitInput().trim(), 10);
    if (Number.isNaN(parsed)) {
      return 50;
    }
    return Math.min(Math.max(parsed, 1), 500);
  };

  const [historyResult] = createResource(
    () => {
      const repositoryPath = activeRepo();
      if (!repositoryPath) {
        return null;
      }
      return { repositoryPath, limit: parsedLimit() };
    },
    async (input) => listCommitHistory(input.repositoryPath, input.limit)
  );

  const [commitDetailResult] = createResource(
    () => {
      const repositoryPath = activeRepo();
      const commitHash = selectedCommitHash();
      if (!repositoryPath || !commitHash) {
        return null;
      }
      return { repositoryPath, commitHash };
    },
    async (input) => getCommitDetail(input.repositoryPath, input.commitHash)
  );

  createEffect(() => {
    const history = historyResult.latest;
    if (!history || !history.ok || history.data.entries.length === 0) {
      return;
    }

    const firstEntry = history.data.entries[0];
    if (!firstEntry) {
      return;
    }

    const selected = selectedCommitHash();
    if (!selected) {
      setSelectedCommitHash(firstEntry.commitHash);
      return;
    }

    const stillExists = history.data.entries.some((entry) => entry.commitHash === selected);
    if (!stillExists) {
      setSelectedCommitHash(firstEntry.commitHash);
    }
  });

  onMount(() => {
    requestAnimationFrame(() => {
      recordUiTiming({
        event: "history.page.first-paint",
        phase: "mount",
        durationMs: performance.now() - mountedAt
      });
    });
  });

  return (
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`}>
      <span class="section-summary">
        Viewing last {parsedLimit()} commits.
      </span>

      <Show when={historyResult.loading}>
        <LoadingStateSkeleton />
      </Show>

      <Show when={historyResult.latest && !historyResult.latest.ok}>
        <ErrorStateCard
          title="History lookup failed"
          body={historyResult.latest && !historyResult.latest.ok ? historyResult.latest.error.message : "Unknown error"}
        />
      </Show>

      <Show when={historyResult.latest?.ok && historyResult.latest.data.entries.length === 0}>
        <EmptyStateCard title="No commits found" body="The selected repository has no visible commits in this range." />
      </Show>

      <Show when={historyResult.latest?.ok && historyResult.latest.data.entries.length > 0}>
        {/* We can use topology visualization natively for the timeline */}
        <section class="topology-canvas" style="margin-bottom: 8px;">
          <svg class="topology-svg" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="none">
             {/* Dummy spatial representation */}
             <path d="M 10,30 L 1000,30" class="topology-link" />
             {historyResult.latest?.ok &&
                historyResult.latest.data.entries.map((entry, index, arr) => {
                  if (index > 10) return null; // cap at 10 items for the spatial representation
                  const spacing = 1000 / Math.min(10, arr.length);
                  const x = 20 + index * spacing;
                  const isActive = selectedCommitHash() === entry.commitHash;
                  return (
                    <circle 
                      cx={x} cy={30} r={isActive ? 5 : 3.5} 
                      class={`topology-node ${isActive ? "is-active" : ""}`}
                      onClick={() => setSelectedCommitHash(entry.commitHash)}
                    >
                      <title>{entry.shortHash}: {entry.subject}</title>
                    </circle>
                  )
                })}
          </svg>
        </section>

        <section class="history-layout">
          <article class="state-card timeline-pane">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
              <h3>Commit Timeline</h3>
              <input
                class="path-input history-limit-input"
                style="max-width: 80px; padding: 2px 6px; font-size: 10px;"
                value={historyLimitInput()}
                placeholder="Limit"
                onInput={(event) => setHistoryLimitInput(event.currentTarget.value)}
                aria-label="History limit"
              />
            </div>
            
            <ul class="timeline-list">
              {historyResult.latest?.ok &&
                historyResult.latest.data.entries.map((entry) => (
                  <li>
                    <button
                      class={`timeline-item ${selectedCommitHash() === entry.commitHash ? "is-selected" : ""}`}
                      onClick={() => setSelectedCommitHash(entry.commitHash)}
                    >
                      <div class="timeline-item-top">
                        <span class="file-path">{entry.shortHash}</span>
                        <span>{entry.authoredAt}</span>
                      </div>
                      <div class="timeline-subject">{entry.subject}</div>
                      <div class="timeline-author">{entry.authorName} &lt;{entry.authorEmail}&gt;</div>
                    </button>
                  </li>
                ))}
            </ul>
          </article>

          <article class="state-card detail-pane">
            <Show when={commitDetailResult.loading}>
              <LoadingStateSkeleton />
            </Show>

            <Show when={commitDetailResult.latest && !commitDetailResult.latest.ok}>
              <ErrorStateCard
                title="Commit detail failed"
                body={
                  commitDetailResult.latest && !commitDetailResult.latest.ok
                    ? commitDetailResult.latest.error.message
                    : "Unknown error"
                }
              />
            </Show>

            <Show when={commitDetailResult.latest?.ok}>
              <>
                <h3>{commitDetailResult.latest?.ok ? commitDetailResult.latest.data.subject : ""}</h3>
                <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 12px;">
                  <span class="file-path">{commitDetailResult.latest?.ok ? commitDetailResult.latest.data.shortHash : ""}</span> by{" "}
                  {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.authorName : ""} on{" "}
                  {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.authoredAt : ""}
                </p>

                <Show when={commitDetailResult.latest?.ok && commitDetailResult.latest.data.body.length > 0}>
                  <pre class="sync-output">{commitDetailResult.latest?.ok ? commitDetailResult.latest.data.body : ""}</pre>
                </Show>

                <div class="commit-file-stats" style="margin-top: 12px;">
                  {commitDetailResult.latest?.ok &&
                    commitDetailResult.latest.data.files.map((file) => (
                      <div class="commit-file-row">
                        <span class="file-path">{file.path}</span>
                        <span style="color: var(--state-added)">+{file.additions}</span>
                        <span style="color: var(--state-deleted)">-{file.deletions}</span>
                      </div>
                    ))}
                </div>
              </>
            </Show>
          </article>
        </section>
      </Show>
    </div>
  );
}
