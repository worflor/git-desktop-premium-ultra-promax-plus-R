import { createEffect, createSignal, onCleanup, onMount, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { DiffShell } from "@/features/diff/DiffShell";
import type { FileDiffManifestData, RepositoryStatus } from "@/lib/backend/dtos";
import type { CommandResult } from "@/lib/contracts/command";
import { scheduleBackgroundTask } from "@/lib/perf/background";
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

const DIFF_PRETEXT_FONT_PROFILE = '12px "JetBrains Mono", "Consolas", monospace';
const statusCache = new Map<string, RepositoryStatus>();
const diffManifestCache = new Map<string, CommandResult<FileDiffManifestData>>();
const pendingStatusRequests = new Map<string, Promise<void>>();
const pendingDiffManifestRequests = new Map<string, Promise<void>>();

export function ChangesPage(props: ChangesPageProps = {}) {
  const mountedAt = performance.now();
  const repository = useRepositoryContext();
  const [selectedPaths, setSelectedPaths] = createSignal<string[]>([]);
  const [commitMessage, setCommitMessage] = createSignal("");
  const [actionMessage, setActionMessage] = createSignal<string | null>(null);
  const [actionError, setActionError] = createSignal<string | null>(null);
  const [selectedDiffPath, setSelectedDiffPath] = createSignal<string | null>(null);
  const [actionRunning, setActionRunning] = createSignal(false);
  const [statusData, setStatusData] = createSignal<RepositoryStatus | null>(null);
  const [statusError, setStatusError] = createSignal<string | null>(null);
  const [displayedDiffManifest, setDisplayedDiffManifest] = createSignal<FileDiffManifestData | null>(null);
  const [displayedDiffPath, setDisplayedDiffPath] = createSignal<string | null>(null);
  const [diffError, setDiffError] = createSignal<string | null>(null);
  const [isDraggingSelection, setIsDraggingSelection] = createSignal(false);
  let previousRepositoryPath: string | null | undefined;
  let dragCandidatePath: string | null = null;
  let dragCandidatePoint: { x: number; y: number } | null = null;
  let dragSelectionMode: "select" | "deselect" | null = null;
  let dragVisitedPaths = new Set<string>();
  let suppressNextClick = false;

  const activeRepo = () => repository.activeRepositoryPath();
  const diffCacheKey = (repo: string, path: string) => `${repo}::${path}`;

  const loadStatus = async (repositoryPath: string) => {
    const cached = statusCache.get(repositoryPath);
    if (cached) {
      setStatusData(cached);
      setStatusError(null);
    }

    const pending = pendingStatusRequests.get(repositoryPath);
    if (pending) {
      await pending;
      return;
    }

    const request = (async () => {
      const result = await getRepositoryStatus(repositoryPath);
      if (!result.ok) {
        if (!cached) {
          setStatusData(null);
          setStatusError(result.error.message);
        }
        return;
      }

      statusCache.set(repositoryPath, result.data);
      if (activeRepo() === repositoryPath) {
        setStatusData(result.data);
        setStatusError(null);
      }
    })();

    pendingStatusRequests.set(repositoryPath, request);
    try {
      await request;
    } finally {
      pendingStatusRequests.delete(repositoryPath);
    }
  };

  const loadDiffManifest = async (repositoryPath: string, path: string, retainCurrent = true) => {
    const cacheKey = diffCacheKey(repositoryPath, path);
    const cached = diffManifestCache.get(cacheKey);
    if (cached?.ok) {
      setDisplayedDiffManifest(cached.data);
      setDisplayedDiffPath(cached.data.path);
      setDiffError(null);
      return;
    }

    if (!retainCurrent) {
      setDisplayedDiffManifest(null);
      setDisplayedDiffPath(path);
    }

    setDiffError(null);
    const pending = pendingDiffManifestRequests.get(cacheKey);
    if (pending) {
      await pending;
      return;
    }

    const request = (async () => {
      const result = await prepareFileDiffChunks(repositoryPath, path, {
        staged: false,
        contextLines: 3,
        chunkSizeBytes: 256 * 1024,
        layoutWidthPx: 1080,
        fontProfile: DIFF_PRETEXT_FONT_PROFILE,
        lineHeightPx: 18
      });

      if (result.ok) {
        diffManifestCache.set(cacheKey, result);
        if (activeRepo() === repositoryPath && selectedDiffPath() === path) {
          setDisplayedDiffManifest(result.data);
          setDisplayedDiffPath(result.data.path);
          setDiffError(null);
        }
        return;
      }

      if (!displayedDiffManifest() || !retainCurrent) {
        setDiffError(result.error.message);
      }
    })();

    pendingDiffManifestRequests.set(cacheKey, request);
    try {
      await request;
    } finally {
      pendingDiffManifestRequests.delete(cacheKey);
    }
  };

  const prefetchDiffManifest = (repositoryPath: string, path: string) => {
    const cacheKey = diffCacheKey(repositoryPath, path);
    if (diffManifestCache.has(cacheKey) || pendingDiffManifestRequests.has(cacheKey)) {
      return;
    }

    void loadDiffManifest(repositoryPath, path);
  };

  createEffect(() => {
    const repositoryPath = activeRepo();
    if (previousRepositoryPath !== repositoryPath) {
      previousRepositoryPath = repositoryPath;
      setSelectedPaths([]);
      setSelectedDiffPath(null);
      setStatusData(null);
      setStatusError(null);
      setDisplayedDiffManifest(null);
      setDisplayedDiffPath(null);
      setDiffError(null);
      setActionMessage(null);
      setActionError(null);
      setActionRunning(false);
    }

    if (!repositoryPath) {
      return;
    }

    const cached = statusCache.get(repositoryPath);
    if (cached) {
      setStatusData(cached);
      setStatusError(null);
    }

    void loadStatus(repositoryPath);
  });

  createEffect(() => {
    const repositoryPath = activeRepo();
    if (!repositoryPath) {
      return;
    }

    setSelectedDiffPath(null);
    setDisplayedDiffManifest(null);
    setDisplayedDiffPath(null);
    setDiffError(null);
  });

  createEffect(() => {
    const latestStatus = statusData();
    if (!latestStatus) {
      return;
    }

    const currentPath = selectedDiffPath();
    if (!currentPath) {
      return;
    }

    if (!latestStatus.files.some((file) => file.path === currentPath)) {
      setSelectedDiffPath(null);
      setDisplayedDiffManifest(null);
      setDisplayedDiffPath(null);
      setDiffError(null);
    }
  });

  createEffect(() => {
    const repositoryPath = activeRepo();
    const path = selectedDiffPath();
    if (!repositoryPath || !path) {
      return;
    }

    const cached = diffManifestCache.get(diffCacheKey(repositoryPath, path));
    if (cached?.ok) {
      setDisplayedDiffManifest(cached.data);
      setDisplayedDiffPath(cached.data.path);
      setDiffError(null);
      return;
    }

    void loadDiffManifest(repositoryPath, path);
  });

  createEffect(() => {
    const repositoryPath = activeRepo();
    const latestStatus = statusData();
    if (!repositoryPath || !latestStatus) {
      return;
    }

    const cancel = scheduleBackgroundTask(() => {
      for (const file of latestStatus.files.slice(0, 4)) {
        prefetchDiffManifest(repositoryPath, file.path);
      }
    });

    onCleanup(cancel);
  });

  onMount(() => {
    const applyDragSelection = (path: string, mode: "select" | "deselect") => {
      setSelectedPaths((current) => {
        const isSelected = current.includes(path);
        if (mode === "select") {
          return isSelected ? current : [...current, path];
        }
        return isSelected ? current.filter((value) => value !== path) : current;
      });
    };

    const handlePointerMove = (event: PointerEvent) => {
      if (event.buttons !== 1 || !dragCandidatePath || !dragCandidatePoint) {
        return;
      }

      const distance = Math.max(
        Math.abs(event.clientX - dragCandidatePoint.x),
        Math.abs(event.clientY - dragCandidatePoint.y)
      );

      if (!isDraggingSelection() && distance >= 4) {
        dragSelectionMode = selectedPaths().includes(dragCandidatePath) ? "deselect" : "select";
        dragVisitedPaths.clear();
        setIsDraggingSelection(true);
        suppressNextClick = true;
        if (dragSelectionMode) {
          applyDragSelection(dragCandidatePath, dragSelectionMode);
          dragVisitedPaths.add(dragCandidatePath);
        }
      }

      if (!isDraggingSelection()) {
        return;
      }

      const element = document.elementFromPoint(event.clientX, event.clientY);
      const row = element instanceof Element ? element.closest("[data-status-path]") : null;
      const path = row?.getAttribute("data-status-path");
      if (path && dragSelectionMode && !dragVisitedPaths.has(path)) {
        applyDragSelection(path, dragSelectionMode);
        dragVisitedPaths.add(path);
      }
    };

    const handlePointerUp = () => {
      dragCandidatePath = null;
      dragCandidatePoint = null;
      dragSelectionMode = null;
      dragVisitedPaths.clear();
      setIsDraggingSelection(false);
    };

    const handleClickCapture = (event: MouseEvent) => {
      if (!suppressNextClick) {
        return;
      }

      suppressNextClick = false;
      event.preventDefault();
      event.stopPropagation();
    };

    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", handlePointerUp);
    window.addEventListener("pointercancel", handlePointerUp);
    window.addEventListener("click", handleClickCapture, true);
    requestAnimationFrame(() => {
      recordUiTiming({
        event: "changes.page.first-paint",
        phase: "mount",
        durationMs: performance.now() - mountedAt
      });
    });
    onCleanup(() => {
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", handlePointerUp);
      window.removeEventListener("pointercancel", handlePointerUp);
      window.removeEventListener("click", handleClickCapture, true);
    });
  });

  const selectedCount = () => selectedPaths().length;
  const isDirtyStatus = (status: string) => status !== "clean" && status.trim().length > 0;
  const stagedFileCount = () =>
    statusData()
      ? statusData()!.files.filter((file) => isDirtyStatus(file.staged)).length
      : 0;
  const unstagedFileCount = () =>
    statusData()
      ? statusData()!.files.filter((file) => isDirtyStatus(file.unstaged)).length
      : 0;

  const togglePathSelection = (path: string, checked: boolean) => {
    setSelectedPaths((current) => {
      if (checked) {
        return current.includes(path) ? current : [...current, path];
      }
      return current.filter((value) => value !== path);
    });
  };

  const beginRowSelection = (event: PointerEvent, path: string) => {
    if (event.button !== 0) {
      return;
    }

    dragCandidatePath = path;
    dragCandidatePoint = { x: event.clientX, y: event.clientY };
    dragSelectionMode = null;
    dragVisitedPaths.clear();
    setIsDraggingSelection(false);
  };

  const runPathOperation = async (operation: "stage" | "unstage") => {
    const repo = activeRepo();
    if (!repo || selectedCount() === 0) {
      return;
    }

    setActionError(null);
    setActionMessage(null);
    setActionRunning(true);

    try {
      const result =
        operation === "stage"
          ? await stagePaths(repo, selectedPaths())
          : await unstagePaths(repo, selectedPaths());

      if (activeRepo() !== repo) {
        return;
      }

      if (!result.ok) {
        setActionError(result.error.message);
        return;
      }

      setActionMessage(`${operation === "stage" ? "Staged" : "Unstaged"} ${result.data.affectedPaths.length} path(s).`);
      setSelectedPaths([]);
      diffManifestCache.clear();
      statusCache.delete(repo);
      void loadStatus(repo);
    } finally {
      setActionRunning(false);
    }
  };

  const onCommit = async () => {
    const repo = activeRepo();
    if (!repo) {
      return;
    }

    setActionError(null);
    setActionMessage(null);
    setActionRunning(true);
    try {
      const result = await createCommit(repo, commitMessage(), false, false);

      if (activeRepo() !== repo) {
        return;
      }

      if (!result.ok) {
        setActionError(result.error.message);
        return;
      }

      setActionMessage(`${result.data.summary} (${result.data.commitHash.slice(0, 8)})`);
      setCommitMessage("");
      diffManifestCache.clear();
      statusCache.delete(repo);
      void loadStatus(repo);
    } finally {
      setActionRunning(false);
    }
  };

  const activeDiffManifest = () => displayedDiffManifest() ?? undefined;
  const activeDiffPath = () => displayedDiffPath() ?? selectedDiffPath() ?? undefined;

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

      <Show when={statusError()}>
        <div style="padding: 16px; width: 100%; display: flex; align-items: center; justify-content: center; color: var(--state-conflicted);">
          {statusError()}
        </div>
      </Show>

      <Show when={statusData() && statusData()!.files.length === 0}>
        <div style="padding: 16px; width: 100%; display: flex; align-items: center; justify-content: center;">
          <EmptyStateCard title="Working tree is clean" body="No unstaged or staged changes detected." />
        </div>
      </Show>

      <Show when={statusData() && statusData()!.files.length > 0}>
        <div style="width: 280px; flex-shrink: 0; display: flex; flex-direction: column; border-right: 1px solid rgba(var(--chrome-border-rgb), 0.15); background: var(--surface-1);">
          <section class="status-list" style="flex: 1; overflow-y: auto; padding: 12px; display: flex; flex-direction: column; gap: 8px;">
            <div class="status-list-head" style="margin-bottom: 10px; display: flex; align-items: center; gap: 8px;">
              <div>
                <h2 style="font-size: 12px; margin: 0; font-weight: 700; color: var(--text-strong); text-transform: uppercase; letter-spacing: 0.04em; opacity: 0.85;">Changes</h2>
              </div>
              <div class="status-chip-stack" style="display: flex; gap: 4px;">
                <span class="status-badge-count is-positive">{stagedFileCount()} S</span>
                <span class="status-badge-count is-negative">{unstagedFileCount()} U</span>
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
              {statusData() &&
                statusData()!.files.map((file) => (
                  <li
                    class={`status-row ${selectedDiffPath() === file.path ? 'is-selected' : ''}`}
                    data-status-path={file.path}
                    style={`padding: 4px 6px; border-radius: 4px; background: ${selectedDiffPath() === file.path ? 'rgba(var(--chrome-border-rgb), 0.1)' : 'transparent'}; display: flex; align-items: center; gap: 6px; user-select: none;`}
                    onPointerDown={(event) => beginRowSelection(event, file.path)}
                  >
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
                    <div class="status-tags" style="gap: 5px; display: flex; flex-shrink: 0;">
                      <Show when={isDirtyStatus(file.staged)}><span class="status-badge is-positive">S</span></Show>
                      <Show when={isDirtyStatus(file.unstaged)}><span class="status-badge is-negative">U</span></Show>
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
                : "Commit to " + (statusData() ? statusData()!.branch || "HEAD" : "HEAD")}
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
            <div style="flex: 1; overflow-y: auto;">
              <DiffShell
                filePath={activeDiffPath()}
                manifest={activeDiffManifest()}
                error={diffError()}
                repositoryPath={activeRepo() ?? undefined}
              />
            </div>
          </Show>
        </div>
      </Show>
    </div>
  );
}
