import { createResource, createSignal, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { StatusPill } from "@/components/primitives/StatusPill";
import { DiffShell } from "@/features/diff/DiffShell";
import {
  createCommit,
  prepareFileDiffChunks,
  getRepositoryStatus,
  stagePaths,
  unstagePaths
} from "@/lib/backend/commands";

interface ChangesPageProps {
  embedded?: boolean;
}

export function ChangesPage(props: ChangesPageProps = {}) {
  const repository = useRepositoryContext();
  const [selectedPaths, setSelectedPaths] = createSignal<string[]>([]);
  const [commitMessage, setCommitMessage] = createSignal("");
  const [actionMessage, setActionMessage] = createSignal<string | null>(null);
  const [actionError, setActionError] = createSignal<string | null>(null);
  const [selectedDiffPath, setSelectedDiffPath] = createSignal<string | null>(null);
  const [actionRunning, setActionRunning] = createSignal(false);

  const activeRepo = () => repository.activeRepositoryPath();

  const [statusResult, { refetch }] = createResource(activeRepo, async (path) => {
    if (!path) {
      return null;
    }
    return getRepositoryStatus(path);
  });

  const [diffManifestResult] = createResource(
    () => {
      const repo = activeRepo();
      const path = selectedDiffPath();
      if (!repo || !path) {
        return null;
      }

      return { repo, path };
    },
    async (input) =>
      prepareFileDiffChunks(input.repo, input.path, {
        staged: false,
        contextLines: 3,
        chunkSizeBytes: 64 * 1024,
        layoutWidthPx: 1080,
        fontProfile: "ui-mono-13",
        lineHeightPx: 18
      })
  );

  const selectedCount = () => selectedPaths().length;
  const stagedFileCount = () =>
    statusResult.latest?.ok
      ? statusResult.latest.data.files.filter((file) => file.staged.trim().length > 0).length
      : 0;
  const unstagedFileCount = () =>
    statusResult.latest?.ok
      ? statusResult.latest.data.files.filter((file) => file.unstaged.trim().length > 0).length
      : 0;

  const togglePathSelection = (path: string, checked: boolean) => {
    setSelectedPaths((current) => {
      if (checked) {
        return current.includes(path) ? current : [...current, path];
      }
      return current.filter((value) => value !== path);
    });
  };

  const runPathOperation = async (operation: "stage" | "unstage") => {
    const repo = activeRepo();
    if (!repo || selectedCount() === 0) {
      return;
    }

    setActionError(null);
    setActionMessage(null);
    setActionRunning(true);

    const result =
      operation === "stage"
        ? await stagePaths(repo, selectedPaths())
        : await unstagePaths(repo, selectedPaths());

    setActionRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setActionMessage(`${operation === "stage" ? "Staged" : "Unstaged"} ${result.data.affectedPaths.length} path(s).`);
    setSelectedPaths([]);
    void refetch();
  };

  const onCommit = async () => {
    const repo = activeRepo();
    if (!repo) {
      return;
    }

    setActionError(null);
    setActionMessage(null);
    setActionRunning(true);
    const result = await createCommit(repo, commitMessage(), false, false);
    setActionRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setActionMessage(`${result.data.summary} (${result.data.commitHash.slice(0, 8)})`);
    setCommitMessage("");
    void refetch();
  };

  return (
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`}>
      <Show when={statusResult.loading}>
        <LoadingStateSkeleton />
      </Show>

      <Show when={statusResult.latest?.ok && statusResult.latest.data.files.length === 0}>
        <EmptyStateCard title="Working tree is clean" body="No unstaged or staged changes detected." />
      </Show>

      <Show when={statusResult.latest?.ok && statusResult.latest.data.files.length > 0}>
        <section class="status-list">
          <div class="status-list-head">
            <div>
              <h2>Changed Files</h2>
            </div>
            <div class="status-chip-stack">
              <span class="feature-meta-pill">Staged {stagedFileCount()}</span>
              <span class="feature-meta-pill">Unstaged {unstagedFileCount()}</span>
            </div>
          </div>
          <div class="inline-actions">
            <button
              class="primary-btn"
              onClick={() => void runPathOperation("stage")}
              disabled={selectedCount() === 0 || actionRunning()}
            >
              Stage
            </button>
            <button
              class="primary-btn"
              onClick={() => void runPathOperation("unstage")}
              disabled={selectedCount() === 0 || actionRunning()}
            >
              Unstage
            </button>
            <span>{actionRunning() ? "Running..." : `${selectedCount()} selected`}</span>
          </div>
          <ul>
            {statusResult.latest?.ok &&
              statusResult.latest.data.files.map((file) => (
                <li class="status-row">
                  <label class="file-toggle">
                    <input
                      type="checkbox"
                      checked={selectedPaths().includes(file.path)}
                      onChange={(event) => togglePathSelection(file.path, event.currentTarget.checked)}
                    />
                    <button class="file-link-btn" onClick={() => setSelectedDiffPath(file.path)}>
                      <span class="file-path">{file.path}</span>
                    </button>
                  </label>
                  <div class="status-tags">
                    <StatusPill label={`Staged: ${file.staged}`} state="staged" />
                    <StatusPill label={`Unstaged: ${file.unstaged}`} state="unstaged" />
                  </div>
                </li>
              ))}
          </ul>

          <div class="inline-actions commit-bar">
            <input
              class="path-input"
              placeholder="Commit message"
              value={commitMessage()}
              onInput={(event) => setCommitMessage(event.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
                  void onCommit();
                }
              }}
            />
            <button class="primary-btn" onClick={() => void onCommit()}>
              {actionRunning() ? "Committing..." : "Commit"}
            </button>
          </div>

          <Show when={actionMessage()}>
            {(message) => <section class="state-card"><p>{message()}</p></section>}
          </Show>

          <Show when={actionError()}>
            {(message) => <ErrorStateCard title="Changes action failed" body={message()} />}
          </Show>
        </section>
      </Show>

      <Show when={diffManifestResult.loading}>
        <LoadingStateSkeleton />
      </Show>

      <Show when={diffManifestResult.latest && !diffManifestResult.latest.ok}>
        <ErrorStateCard
          title="Diff load failed"
          body={
            diffManifestResult.latest && !diffManifestResult.latest.ok
              ? diffManifestResult.latest.error.message
              : "Unknown error"
          }
        />
      </Show>

      <DiffShell
        filePath={selectedDiffPath() ?? undefined}
        manifest={diffManifestResult.latest?.ok ? diffManifestResult.latest.data : undefined}
        loading={diffManifestResult.loading}
        error={
          diffManifestResult.latest && !diffManifestResult.latest.ok
            ? diffManifestResult.latest.error.message
            : null
        }
      />
    </div>
  );
}
