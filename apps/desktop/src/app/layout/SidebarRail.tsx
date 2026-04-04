import { createEffect, createMemo, createResource, createSignal, For, onMount, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { BrandLockup } from "@/components/composite/BrandLockup";
import { Icon } from "@/components/icons/Icon";
import { listRecentRepositories, openRepository } from "@/lib/backend/commands";

function normalizePath(value: string): string {
  return value.replace(/\\/g, "/").toLowerCase();
}

function toProjectName(value: string): string {
  const parts = value.replace(/\\/g, "/").split("/").filter(Boolean);
  return parts[parts.length - 1] ?? value;
}

export function SidebarRail() {
  const repository = useRepositoryContext();
  const [pathInput, setPathInput] = createSignal("");
  const [repositoryError, setRepositoryError] = createSignal<string | null>(null);
  const [openRunning, setOpenRunning] = createSignal(false);
  const [showPathEntry, setShowPathEntry] = createSignal(false);
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

  createEffect(() => {
    const active = repository.activeRepositoryPath();
    if (!active) return;
    setPathInput((current) => (current === active ? current : active));
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

  const onOpenRepository = async (rawPath?: string) => {
    const path = (rawPath ?? pathInput()).trim();
    if (!path) {
      setRepositoryError("Path required.");
      return;
    }
    setRepositoryError(null);
    setOpenRunning(true);
    const result = await openRepository(path);
    setOpenRunning(false);
    if (!result.ok) {
      setRepositoryError(result.error.message);
      return;
    }
    setPathInput(result.data.repositoryPath);
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
              onClick={() => setShowPathEntry((c) => !c)}
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
              placeholder="/path/to/project"
              value={pathInput()}
              onInput={(e) => setPathInput(e.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key !== "Enter") return;
                e.preventDefault();
                void onOpenRepository();
              }}
            />
            <button
              class="sidebar-project-add-btn"
              type="button"
              disabled={openRunning()}
              onClick={() => void onOpenRepository()}
            >
              {openRunning() ? "…" : "Open"}
            </button>
          </div>
        </Show>

        <Show when={repositoryError()}>
          {(msg) => <p class="sidebar-error-text">{msg()}</p>}
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