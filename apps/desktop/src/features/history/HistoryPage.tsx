import { createEffect, createResource, createSignal, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { getCommitDetail, listCommitHistory, openRepository } from "@/lib/backend/commands";

interface HistoryPageProps {
  embedded?: boolean;
}

export function HistoryPage(props: HistoryPageProps = {}) {
  const repository = useRepositoryContext();
  const [repositoryPath, setRepositoryPath] = createSignal(repository.activeRepositoryPath() ?? "");
  const [activeRepo, setActiveRepo] = createSignal<string | null>(repository.activeRepositoryPath());
  const [historyLimitInput, setHistoryLimitInput] = createSignal("50");
  const [selectedCommitHash, setSelectedCommitHash] = createSignal<string | null>(null);
  const [openError, setOpenError] = createSignal<string | null>(null);

  createEffect(() => {
    const sharedPath = repository.activeRepositoryPath();
    if (!sharedPath || sharedPath === activeRepo()) {
      return;
    }

    setActiveRepo(sharedPath);
    setRepositoryPath(sharedPath);
  });

  const parsedLimit = () => {
    const parsed = Number.parseInt(historyLimitInput().trim(), 10);
    if (Number.isNaN(parsed)) {
      return 50;
    }
    return Math.min(Math.max(parsed, 1), 500);
  };

  const [historyResult, { refetch: refetchHistory }] = createResource(
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

  const onOpenRepository = async () => {
    const path = repositoryPath().trim();
    setOpenError(null);

    if (!path) {
      setOpenError("Repository path is required.");
      return;
    }

    const result = await openRepository(path);
    if (!result.ok) {
      setOpenError(result.error.message);
      return;
    }

    setActiveRepo(result.data.repositoryPath);
    repository.setActiveRepositoryPath(result.data.repositoryPath);
    setSelectedCommitHash(null);
    void refetchHistory();
  };

  return (
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`}>
      <Show when={!props.embedded}>
        <>
          <header class="feature-header">
            <div class="feature-header-main">
              <h1 class="feature-title">History</h1>
            </div>
            <div class="feature-header-meta">
              <span class="feature-meta-pill">{activeRepo() ? "Repository connected" : "No repository"}</span>
              <span class="feature-meta-pill">Limit {parsedLimit()}</span>
            </div>
          </header>

          <section class="feature-toolbar">
            <input
              class="path-input"
              placeholder="C:/dev/your-repository"
              value={repositoryPath()}
              onInput={(event) => setRepositoryPath(event.currentTarget.value)}
            />
            <input
              class="path-input history-limit-input"
              value={historyLimitInput()}
              placeholder="History limit"
              onInput={(event) => setHistoryLimitInput(event.currentTarget.value)}
              aria-label="History limit"
            />
            <button class="primary-btn" onClick={() => void onOpenRepository()}>
              Open Repository
            </button>
            <button class="primary-btn" disabled={!activeRepo()} onClick={() => void refetchHistory()}>
              Refresh
            </button>
          </section>
        </>
      </Show>

      <Show when={!activeRepo()}>
        <EmptyStateCard
          title="Open a repository"
          body="Select a local path."
        />
      </Show>

      <Show when={openError()}>
        {(message) => <ErrorStateCard title="Cannot open repository" body={message()} />}
      </Show>

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
        <section class="history-layout">
          <article class="state-card timeline-pane">
            <h3>Commit Timeline</h3>
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
                <p>
                  {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.shortHash : ""} by{" "}
                  {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.authorName : ""} on{" "}
                  {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.authoredAt : ""}
                </p>
                <p>
                  Files changed: {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.filesChanged : 0} |
                  Additions: {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.additions : 0} |
                  Deletions: {commitDetailResult.latest?.ok ? commitDetailResult.latest.data.deletions : 0}
                </p>

                <Show when={commitDetailResult.latest?.ok && commitDetailResult.latest.data.body.length > 0}>
                  <pre class="sync-output">{commitDetailResult.latest?.ok ? commitDetailResult.latest.data.body : ""}</pre>
                </Show>

                <div class="commit-file-stats">
                  {commitDetailResult.latest?.ok &&
                    commitDetailResult.latest.data.files.map((file) => (
                      <div class="commit-file-row">
                        <span class="file-path">{file.path}</span>
                        <span>+{file.additions}</span>
                        <span>-{file.deletions}</span>
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
