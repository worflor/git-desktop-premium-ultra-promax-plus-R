import { createMemo, createResource, createSignal, For, onMount, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { BrandLockup } from "@/components/composite/BrandLockup";
import { Icon } from "@/components/icons/Icon";
import { listRecentRepositories, openRepository, pickRepositoryDirectory, cloneRepository, initRepository } from "@/lib/backend/commands";

function normalizePath(value: string): string {
  return value.replace(/\\/g, "/").toLowerCase();
}

function toProjectName(value: string): string {
  const parts = value.replace(/\\/g, "/").split("/").filter(Boolean);
  return parts[parts.length - 1] ?? value;
}

function isGitUrl(value: string): boolean {
  const trimmed = value.trim();
  return (
    trimmed.startsWith("https://") ||
    trimmed.startsWith("http://") ||
    trimmed.startsWith("git@") ||
    trimmed.startsWith("ssh://") ||
    trimmed.endsWith(".git")
  );
}

function extractRepoNameFromUrl(url: string): string {
  const cleaned = url.trim().replace(/\.git$/, "").replace(/\/$/, "");
  const parts = cleaned.split(/[/:]/).filter(Boolean);
  return parts[parts.length - 1] ?? "repo";
}

export function SidebarRail() {
  const repository = useRepositoryContext();
  const [pathInput, setPathInput] = createSignal("");
  const [cloneTargetPath, setCloneTargetPath] = createSignal("");
  const [repositoryError, setRepositoryError] = createSignal<string | null>(null);
  const [openRunning, setOpenRunning] = createSignal(false);
  const [showPathEntry, setShowPathEntry] = createSignal(false);
  const [cloningEntry, setCloningEntry] = createSignal<string | null>(null);

  const inputMode = createMemo<"open" | "clone" | "init">(() => {
    const value = pathInput().trim();
    if (!value) return "open";
    if (isGitUrl(value)) return "clone";
    return "open";
  });

  const buttonLabel = createMemo(() => {
    if (openRunning()) return "…";
    switch (inputMode()) {
      case "clone": return "Clone";
      default: return "Open";
    }
  });
  const [shouldLoadRecents, setShouldLoadRecents] = createSignal(false);
  const [recentRepositories, { refetch: refetchRecents }] = createResource(
    shouldLoadRecents,
    async (enabled) => {
      if (!enabled) {
        return null;
      }

      return listRecentRepositories();
    }
  );

  onMount(() => {
    const schedule =
      typeof window.requestIdleCallback === "function"
        ? (callback: () => void) =>
            window.requestIdleCallback(() => {
              callback();
            }, { timeout: 250 })
        : (callback: () => void) => window.setTimeout(callback, 0);

    schedule(() => {
      setShouldLoadRecents(true);
    });
  });

  const sortedProjects = createMemo(() => {
    if (!recentRepositories.latest?.ok) return [] as string[];
    return recentRepositories.latest.data.repositories.slice(0, 20);
  });

  const isActivePath = (path: string) => {
    const active = repository.activeRepositoryPath();
    if (!active) return false;
    return normalizePath(path) === normalizePath(active);
  };

  const togglePathEntry = () => {
    const next = !showPathEntry();
    setShowPathEntry(next);

    if (next && !repositoryError()) {
      setPathInput("");
    }
  };

  const tryPickRepositoryDirectory = async (): Promise<string | null> => {
    const picked = await pickRepositoryDirectory();
    if (!picked.ok) {
      setRepositoryError(picked.error.message);
      return null;
    }

    return picked.data.repositoryPath;
  };

  const isPathFallbackError = (code: string) => code === "repo.not_found" || code === "repo.open_failed";

  const onCloneRepository = async () => {
    const url = pathInput().trim();
    const target = cloneTargetPath().trim();
    if (!url || !target) {
      setRepositoryError("URL and target path required.");
      return;
    }

    setRepositoryError(null);
    setOpenRunning(true);
    setCloningEntry(target);

    const result = await cloneRepository(url, target);

    setOpenRunning(false);
    setCloningEntry(null);

    if (!result.ok) {
      setRepositoryError(result.error.message);
      return;
    }

    setPathInput("");
    setCloneTargetPath("");
    repository.setActiveRepositoryPath(result.data.repositoryPath);
    setShowPathEntry(false);
    void refetchRecents();
  };

  const onInitRepository = async (path: string) => {
    setRepositoryError(null);
    setOpenRunning(true);

    const result = await initRepository(path);

    if (!result.ok) {
      setOpenRunning(false);
      setRepositoryError(result.error.message);
      return;
    }

    const openResult = await openRepository(result.data.repositoryPath);
    setOpenRunning(false);

    if (!openResult.ok) {
      setRepositoryError(openResult.error.message);
      return;
    }

    setPathInput("");
    repository.setActiveRepositoryPath(openResult.data.repositoryPath);
    setShowPathEntry(false);
    void refetchRecents();
  };

  const onOpenRepository = async (rawPath?: string) => {
    const isManualOpen = typeof rawPath !== "string";

    if (isManualOpen && inputMode() === "clone") {
      return onCloneRepository();
    }

    let path = (rawPath ?? pathInput()).trim();

    if (!path && isManualOpen) {
      const selected = await tryPickRepositoryDirectory();
      if (!selected) {
        return;
      }
      path = selected;
      setPathInput(selected);
    }

    if (!path) {
      setRepositoryError("Path required.");
      return;
    }

    setRepositoryError(null);
    setOpenRunning(true);
    let result = await openRepository(path);

    if (!result.ok && isManualOpen && isPathFallbackError(result.error.code)) {
      const selected = await tryPickRepositoryDirectory();
      if (selected) {
        path = selected;
        setPathInput(selected);
        result = await openRepository(selected);
      }
    }

    if (!result.ok && result.error.code === "repo.not_found") {
      setOpenRunning(false);
      setRepositoryError(`Not a git repository. Initialize one here?`);
      return;
    }

    setOpenRunning(false);

    if (!result.ok) {
      setRepositoryError(result.error.message);
      return;
    }
    setPathInput("");
    repository.setActiveRepositoryPath(result.data.repositoryPath);
    setShowPathEntry(false);
    void refetchRecents();
  };

  return (
    <aside class="sidebar-rail" aria-label="Projects">
      <div class="sidebar-header">
        <BrandLockup />
      </div>

      <section class="sidebar-repository-panel">
        <div class="sidebar-projects-head">
          <span class="sidebar-section-title">Projects</span>
          <div class="sidebar-projects-actions">
            <button
              class={`workspace-mode-btn sidebar-project-head-btn hyper-reactive ${showPathEntry() ? "is-active active" : ""}`}
              type="button"
              aria-label={showPathEntry() ? "Cancel" : "Add project"}
              onClick={togglePathEntry}
              title={showPathEntry() ? "Cancel" : "Add project"}
            >
              <Icon name="plus" size={16} tone="muted" />
            </button>
          </div>
        </div>

        <Show when={showPathEntry()}>
          <div class="sidebar-project-create">
            <input
              id="sidebar-repo-input"
              class="path-input"
              placeholder={inputMode() === "clone" ? "Repository URL" : "/path/to/project or URL"}
              value={pathInput()}
              onInput={(e) => {
                setPathInput(e.currentTarget.value);
                setRepositoryError(null);
                if (isGitUrl(e.currentTarget.value.trim()) && !cloneTargetPath()) {
                  const name = extractRepoNameFromUrl(e.currentTarget.value.trim());
                  setCloneTargetPath(name);
                }
              }}
              onKeyDown={(e) => {
                if (e.key !== "Enter") return;
                e.preventDefault();
                void onOpenRepository();
              }}
            />
            <Show when={inputMode() === "clone"}>
              <input
                class="path-input"
                placeholder="Clone to path"
                style="margin-top: 4px; font-size: 11px;"
                value={cloneTargetPath()}
                onInput={(e) => setCloneTargetPath(e.currentTarget.value)}
                onKeyDown={(e) => {
                  if (e.key !== "Enter") return;
                  e.preventDefault();
                  void onOpenRepository();
                }}
              />
            </Show>
            <button
              class="sidebar-project-add-btn"
              type="button"
              disabled={openRunning()}
              onClick={() => void onOpenRepository()}
            >
              {buttonLabel()}
            </button>
          </div>
        </Show>

        <Show when={repositoryError()}>
          {(msg) => (
            <div class="sidebar-error-text" style="display: flex; flex-direction: column; gap: 4px;">
              <p style="margin: 0;">{msg()}</p>
              <Show when={msg()?.includes("Initialize one here")}>
                <button
                  class="ghost-btn"
                  style="font-size: 10px; padding: 2px 6px; align-self: flex-start; color: var(--accent-bright);"
                  onClick={() => void onInitRepository(pathInput().trim())}
                  disabled={openRunning()}
                >
                  Initialize repository
                </button>
              </Show>
            </div>
          )}
        </Show>

        <Show when={cloningEntry()}>
          <div class="sidebar-cloning-entry" style="padding: 4px 12px; font-size: 11px; color: var(--text-muted); display: flex; align-items: center; gap: 6px;">
            <span class="sidebar-cloning-pulse" />
            <span>Cloning...</span>
          </div>
        </Show>

        <ul class="sidebar-project-list">
          <For each={sortedProjects()}>
            {(path) => (
              <li>
                <button
                  class={`sidebar-project-item ${isActivePath(path) ? "is-active" : ""}`}
                  title={path}
                  onClick={() => void onOpenRepository(path)}
                >
                  <span class="sidebar-project-main">
                    <span class="sidebar-project-item-name">{toProjectName(path)}</span>
                  </span>
                </button>
              </li>
            )}
          </For>
        </ul>

        <Show when={sortedProjects().length === 0}>
          <p class="sidebar-empty-projects">No projects yet</p>
        </Show>
      </section>
    </aside>
  );
}
