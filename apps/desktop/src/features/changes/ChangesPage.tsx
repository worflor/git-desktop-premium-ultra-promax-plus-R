import { createResource, createSignal, onMount, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { DiffShell } from "@/features/diff/DiffShell";
import { recordUiTiming } from "@/lib/telemetry/uiTiming";
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
  const mountedAt = performance.now();
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

  onMount(() => {
    requestAnimationFrame(() => {
      recordUiTiming({
        event: "changes.page.first-paint",
        phase: "mount",
        durationMs: performance.now() - mountedAt
      });
    });
  });

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
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`} style="display: flex; height: 100%; overflow: hidden; gap: 0;">
      <Show when={!activeRepo()}>
        <div style="padding: 16px; width: 100%; display: flex; align-items: center; justify-content: center;">
          <EmptyStateCard
            title="No repository selected"
            body="Add or open a repository from Projects to view and manage file changes."
          />
        </div>
      </Show>

      <Show when={statusResult.loading}>
        <div style="padding: 16px; width: 100%;">
          <LoadingStateSkeleton />
        </div>
      </Show>

      <Show when={statusResult.latest?.ok && statusResult.latest.data.files.length === 0}>
        <div style="padding: 16px; width: 100%; display: flex; align-items: center; justify-content: center;">
          <EmptyStateCard title="Working tree is clean" body="No unstaged or staged changes detected." />
        </div>
      </Show>

      <Show when={statusResult.latest?.ok && statusResult.latest.data.files.length > 0}>
        <div style="width: 280px; flex-shrink: 0; display: flex; flex-direction: column; border-right: 1px solid rgba(var(--chrome-border-rgb), 0.15); background: var(--surface-1);">
          <section class="status-list" style="flex: 1; overflow-y: auto; padding: 12px; display: flex; flex-direction: column; gap: 8px;">
            <div class="status-list-head" style="margin-bottom: 4px;">
              <div>
                <h2 style="font-size: 13px; margin: 0;">Changes</h2>
              </div>
              <div class="status-chip-stack" style="gap: 4px;">
                <span class="feature-meta-pill" style="font-size: 10px; padding: 0 4px;">{stagedFileCount()} S</span>
                <span class="feature-meta-pill" style="font-size: 10px; padding: 0 4px;">{unstagedFileCount()} U</span>
              </div>
            </div>
            
            <div class="inline-actions" style="gap: 4px; margin-bottom: 8px;">
              <button
                class="primary-btn"
                style="flex: 1; min-height: 24px; font-size: 11px;"
                onClick={() => void runPathOperation("stage")}
                disabled={selectedCount() === 0 || actionRunning()}
              >
                Stage
              </button>
              <button
                class="primary-btn"
                style="flex: 1; min-height: 24px; font-size: 11px;"
                onClick={() => void runPathOperation("unstage")}
                disabled={selectedCount() === 0 || actionRunning()}
              >
                Unstage
              </button>
            </div>
            
            <ul style="margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 2px;">
              {statusResult.latest?.ok &&
                statusResult.latest.data.files.map((file) => (
                  <li class={`status-row ${selectedDiffPath() === file.path ? 'is-selected' : ''}`} style={`padding: 4px 6px; border-radius: 4px; background: ${selectedDiffPath() === file.path ? 'rgba(var(--chrome-border-rgb), 0.1)' : 'transparent'}; display: flex; align-items: center; gap: 6px;`}>
                    <input
                      type="checkbox"
                      class="custom-checkbox"
                      style="width: 14px; height: 14px; margin: 0; flex-shrink: 0;"
                      checked={selectedPaths().includes(file.path)}
                      onChange={(event) => togglePathSelection(file.path, event.currentTarget.checked)}
                    />
                    <button class="file-link-btn" style="flex: 1; text-align: left; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 12px; padding: 0; background: transparent; border: none; cursor: pointer; color: var(--text-normal);" onClick={() => setSelectedDiffPath(file.path)}>
                       <span class="file-path" style="font-family: var(--font-sans);">{file.path.split('/').pop()}</span>
                       <span style="opacity: 0.5; font-size: 10px; margin-left: 4px; font-family: var(--font-mono);">{file.path.substring(0, file.path.lastIndexOf('/'))}</span>
                    </button>
                    <div class="status-tags" style="gap: 2px; display: flex; flex-shrink: 0;">
                      <Show when={file.staged.trim().length > 0}><span style="color: var(--state-added); font-size: 10px; font-weight: bold; width: 12px; text-align: center;">S</span></Show>
                      <Show when={file.unstaged.trim().length > 0}><span style="color: var(--state-modified); font-size: 10px; font-weight: bold; width: 12px; text-align: center;">U</span></Show>
                    </div>
                  </li>
                ))}
            </ul>
          </section>

          <div style="padding: 12px; border-top: 1px solid rgba(var(--chrome-border-rgb), 0.15); background: var(--surface-0); display: flex; flex-direction: column; gap: 8px;">
            <input
              class="path-input"
              placeholder="Commit message..."
              style="width: 100%; font-size: 12px; padding: 6px 8px;"
              value={commitMessage()}
              onInput={(event) => setCommitMessage(event.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
                  void onCommit();
                }
              }}
            />
            <button class="primary-btn" style="width: 100%; min-height: 28px; font-size: 12px; font-weight: 600;" onClick={() => void onCommit()}>
              {actionRunning()
                ? "Committing..."
                : "Commit to " + (statusResult.latest?.ok ? statusResult.latest.data.branch || "HEAD" : "HEAD")}
            </button>
            <Show when={actionMessage()}>
              {(message) => <div style="font-size: 11px; color: var(--state-added);">{message()}</div>}
            </Show>
            <Show when={actionError()}>
              {(message) => <div style="font-size: 11px; color: var(--state-conflicted);">{message()}</div>}
            </Show>
          </div>
        </div>
        
        <div style="flex: 1; display: flex; flex-direction: column; overflow: hidden; background: var(--surface-0);">
          <Show when={!selectedDiffPath()}>
            <div style="flex: 1; display: flex; align-items: center; justify-content: center; color: var(--text-muted); font-size: 13px;">
              Select a file to view its diff
            </div>
          </Show>
          <Show when={selectedDiffPath()}>
            <Show when={diffManifestResult.loading}>
              <div style="padding: 16px;"><LoadingStateSkeleton /></div>
            </Show>
            <Show when={diffManifestResult.latest && !diffManifestResult.latest.ok}>
              <div style="padding: 16px;">
                <ErrorStateCard
                  title="Diff load failed"
                  body={diffManifestResult.latest && !diffManifestResult.latest.ok ? diffManifestResult.latest.error.message : "Unknown error"}
                />
              </div>
            </Show>
            <div style="flex: 1; overflow-y: auto;">
              <DiffShell
                filePath={selectedDiffPath() ?? undefined}
                manifest={diffManifestResult.latest?.ok ? diffManifestResult.latest.data : undefined}
                loading={diffManifestResult.loading}
                error={diffManifestResult.latest && !diffManifestResult.latest.ok ? diffManifestResult.latest.error.message : null}
              />
            </div>
          </Show>
        </div>
      </Show>
    </div>
  );
}
