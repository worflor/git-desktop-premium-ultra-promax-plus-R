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
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`} style="display: flex; flex-direction: column; height: 100%; overflow: hidden; gap: 0;">
      <Show when={!activeRepo()}>
        <div style="padding: 16px; width: 100%; display: flex; align-items: center; justify-content: center;">
          <EmptyStateCard
            title="No repository selected"
            body="Add or open a repository from Projects to browse commit history."
          />
        </div>
      </Show>

      <Show when={historyResult.loading}>
        <div style="padding: 16px;"><LoadingStateSkeleton /></div>
      </Show>

      <Show when={historyResult.latest && !historyResult.latest.ok}>
        <div style="padding: 16px;">
          <ErrorStateCard
            title="History lookup failed"
            body={historyResult.latest && !historyResult.latest.ok ? historyResult.latest.error.message : "Unknown error"}
          />
        </div>
      </Show>

      <Show when={historyResult.latest?.ok && historyResult.latest.data.entries.length === 0}>
        <div style="padding: 16px; display: flex; justify-content: center;">
          <EmptyStateCard title="No commits found" body="The selected repository has no visible commits in this range." />
        </div>
      </Show>

      <Show when={historyResult.latest?.ok && historyResult.latest.data.entries.length > 0}>
        <div style="padding: 8px 12px; background: var(--surface-1); border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.15); display: flex; align-items: center; justify-content: space-between; flex-shrink: 0;">
          <div style="font-size: 11px; color: var(--text-muted); display: flex; gap: 8px; align-items: center;">
            <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon"><circle cx="12" cy="12" r="10"></circle><polyline points="12 6 12 12 16 14"></polyline></svg>
            Viewing last {parsedLimit()} commits
          </div>
          <div style="display: flex; align-items: center; gap: 8px;">
             <span style="font-size: 10px; color: var(--text-muted);">Limit:</span>
             <input
              class="path-input history-limit-input"
              style="width: 50px; padding: 2px 6px; font-size: 11px; min-height: 20px; border-radius: 4px; text-align: center;"
              value={historyLimitInput()}
              onInput={(event) => setHistoryLimitInput(event.currentTarget.value)}
              aria-label="History limit"
            />
          </div>
        </div>

        {/* Minimal topology canvas incorporated right under the header */}
        <section class="topology-canvas" style="margin: 0; padding: 0; border: none; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.1); background: var(--surface-0); flex-shrink: 0; height: 36px; border-radius: 0;">
          <svg class="topology-svg" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="none" style="height: 100%; width: 100%;">
             <path d="M 10,18 L 2000,18" class="topology-link" stroke="rgba(var(--chrome-border-rgb), 0.2)" />
             {historyResult.latest?.ok &&
                historyResult.latest.data.entries.map((entry, index, arr) => {
                  if (index > 20) return null; // Increased to 20 for density
                  const spacing = 1000 / Math.min(20, arr.length);
                  const x = 20 + index * spacing;
                  const isActive = selectedCommitHash() === entry.commitHash;
                  return (
                    <circle 
                      cx={x} cy={18} r={isActive ? 6 : 4} 
                      class={`topology-node ${isActive ? "is-active" : ""}`}
                      onClick={() => setSelectedCommitHash(entry.commitHash)}
                    >
                      <title>{entry.shortHash}: {entry.subject}</title>
                    </circle>
                  )
                })}
          </svg>
        </section>

        <section style="display: flex; flex: 1; overflow: hidden;">
          {/* Timeline Pane */}
          <article style="width: 280px; flex-shrink: 0; border-right: 1px solid rgba(var(--chrome-border-rgb), 0.15); background: var(--surface-1); display: flex; flex-direction: column; overflow: hidden;">
            <ul style="flex: 1; overflow-y: auto; margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column;">
              {historyResult.latest?.ok &&
                historyResult.latest.data.entries.map((entry) => {
                  const isSelected = selectedCommitHash() === entry.commitHash;
                  return (
                    <li>
                      <button
                        style={`width: 100%; text-align: left; padding: 10px 12px; background: ${isSelected ? 'rgba(var(--accent-rgb), 0.1)' : 'transparent'}; border: none; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.08); border-left: 2px solid ${isSelected ? 'var(--accent-bright)' : 'transparent'}; cursor: pointer; display: flex; flex-direction: column; gap: 4px;`}
                        onClick={() => setSelectedCommitHash(entry.commitHash)}
                      >
                        <div style="display: flex; justify-content: space-between; align-items: baseline; font-size: 10px;">
                          <span style={`font-family: var(--font-mono); font-weight: ${isSelected ? '700' : '600'}; color: ${isSelected ? 'var(--text-strong)' : 'var(--text-muted)'};`}>{entry.shortHash}</span>
                          <span style="color: var(--text-muted); opacity: 0.8;">{entry.authoredAt}</span>
                        </div>
                        <div style={`font-size: 13px; font-weight: ${isSelected ? '600' : '500'}; color: ${isSelected ? 'var(--text-strong)' : 'var(--text-normal)'}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;`}>
                          {entry.subject}
                        </div>
                        <div style="font-size: 11px; color: var(--text-muted); display: flex; gap: 4px; align-items: center;">
                           <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle></svg>
                           {entry.authorName}
                        </div>
                      </button>
                    </li>
                  )
                })}
            </ul>
          </article>

          {/* Detail Pane */}
          <article style="flex: 1; min-width: 0; background: var(--surface-0); display: flex; flex-direction: column; overflow: hidden;">
            <Show when={commitDetailResult.loading}>
              <div style="padding: 16px;"><LoadingStateSkeleton /></div>
            </Show>

            <Show when={commitDetailResult.latest && !commitDetailResult.latest.ok}>
              <div style="padding: 16px;">
                <ErrorStateCard
                  title="Commit detail failed"
                  body={commitDetailResult.latest && !commitDetailResult.latest.ok ? commitDetailResult.latest.error.message : "Unknown error"}
                />
              </div>
            </Show>

            <Show when={commitDetailResult.latest?.ok}>
              <div style="flex: 1; overflow-y: auto; padding: 24px; display: flex; flex-direction: column;">
                <div style="margin-bottom: 24px; display: flex; align-items: flex-start; justify-content: space-between; gap: 16px;">
                  <div style="min-width: 0;">
                    <h3 style="margin: 0 0 8px 0; font-size: 1.25rem; line-height: 1.4; color: var(--text-strong); word-wrap: break-word;">{commitDetailResult.latest?.ok ? commitDetailResult.latest.data.subject : ""}</h3>
                    <div style="display: flex; flex-wrap: wrap; gap: 12px; font-size: 12px; color: var(--text-muted); align-items: center;">
                      <div class="user-chip" style="display: flex; align-items: center; gap: 6px;">
                        <div style="width: 24px; height: 24px; border-radius: 12px; background: rgba(var(--chrome-border-rgb), 0.1); display: flex; align-items: center; justify-content: center; font-size: 10px; font-weight: bold; color: var(--text-strong);">
                           {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.authorName.charAt(0).toUpperCase() : ""}
                        </div>
                        <span style="color: var(--text-normal); font-weight: 500;">{commitDetailResult.latest?.ok ? commitDetailResult.latest.data.authorName : ""}</span>
                      </div>
                      <span style="opacity: 0.5;">|</span>
                      <span>{commitDetailResult.latest?.ok ? commitDetailResult.latest.data.authoredAt : ""}</span>
                      <span style="opacity: 0.5;">|</span>
                      <span style="font-family: var(--font-mono); background: rgba(var(--chrome-border-rgb), 0.1); padding: 2px 6px; border-radius: 4px;">{commitDetailResult.latest?.ok ? commitDetailResult.latest.data.shortHash : ""}</span>
                    </div>
                  </div>
                </div>

                <Show when={commitDetailResult.latest?.ok && commitDetailResult.latest.data.body.length > 0}>
                  <div style="margin-bottom: 24px; font-size: 13px; line-height: 1.6; color: var(--text-normal); white-space: pre-wrap; font-family: var(--font-sans); background: rgba(var(--chrome-border-rgb), 0.03); padding: 12px 16px; border-radius: 8px; border: 1px solid rgba(var(--chrome-border-rgb), 0.08);">
                    {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.body : ""}
                  </div>
                </Show>

                <div style="margin-top: auto; padding-top: 24px; border-top: 1px solid rgba(var(--chrome-border-rgb), 0.1);">
                  <h4 style="margin: 0 0 12px 0; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-muted); display: flex; gap: 6px; align-items: center;">
                    <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>
                    Changed Files ({commitDetailResult.latest?.ok ? commitDetailResult.latest.data.files.length : 0})
                  </h4>
                  <ul style="margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 4px;">
                    {commitDetailResult.latest?.ok &&
                      commitDetailResult.latest.data.files.map((file) => (
                        <li style="display: flex; align-items: center; justify-content: space-between; padding: 6px 10px; background: rgba(var(--chrome-border-rgb), 0.04); border-radius: 6px; font-size: 12px; border: 1px solid rgba(var(--chrome-border-rgb), 0.06);">
                          <div style="display: flex; align-items: center; min-width: 0; gap: 8px;">
                             <span style="font-family: var(--font-sans); color: var(--text-normal); overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">{file.path.split('/').pop()}</span>
                             <span style="font-family: var(--font-mono); font-size: 10px; color: var(--text-muted); opacity: 0.6; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">{file.path.includes('/') ? file.path.substring(0, file.path.lastIndexOf('/')) : ''}</span>
                          </div>
                          <div style="display: flex; gap: 8px; flex-shrink: 0; font-family: var(--font-mono); font-size: 10px; font-weight: 600;">
                            <Show when={file.additions > 0}>
                              <span style="color: var(--state-added); background: rgba(var(--state-added-rgb, 46,160,67), 0.1); padding: 2px 6px; border-radius: 10px;">+{file.additions}</span>
                            </Show>
                            <Show when={file.deletions > 0}>
                              <span style="color: var(--state-deleted); background: rgba(var(--state-deleted-rgb, 248,81,73), 0.1); padding: 2px 6px; border-radius: 10px;">-{file.deletions}</span>
                            </Show>
                          </div>
                        </li>
                      ))}
                  </ul>
                </div>
              </div>
            </Show>
          </article>
        </section>
      </Show>
    </div>
  );
}
