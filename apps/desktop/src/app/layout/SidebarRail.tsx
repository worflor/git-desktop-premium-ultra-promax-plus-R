import { createEffect, createMemo, createResource, createSignal, For, Show } from "solid-js";
import { useLocation, useNavigate } from "@solidjs/router";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
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
  const location = useLocation();
  const navigate = useNavigate();
  const repository = useRepositoryContext();
  const [pathInput, setPathInput] = createSignal("");
  const [repositoryError, setRepositoryError] = createSignal<string | null>(null);
  const [openRunning, setOpenRunning] = createSignal(false);
  const [showPathEntry, setShowPathEntry] = createSignal(false);
  const [recentRepositories, { refetch: refetchRecents }] = createResource(() =>
    listRecentRepositories()
  );

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

  const openSettingsPanel = () => {
    const searchParams = new URLSearchParams(location.search);
    if (searchParams.get("panel") === "settings") {
      searchParams.delete("panel");
    } else {
      searchParams.set("panel", "settings");
    }
    const nextQuery = searchParams.toString();
    const nextHref = nextQuery.length > 0 ? `${location.pathname}?${nextQuery}` : location.pathname;
    if (nextHref === `${location.pathname}${location.search}`) return;
    void navigate(nextHref);
  };

  return (
    <aside class="sidebar-rail" aria-label="Projects">
      <div class="sidebar-header">
        <div class="sidebar-brand-lockup">
          <Icon name="app-logo" size={20} title="Application" />
          <div class="sidebar-wordmark">
            <span class="sidebar-wordmark-main">Git</span>
            <span class="sidebar-wordmark-stage">Dev</span>
          </div>
        </div>
      </div>

      <section class="sidebar-repository-panel">
        <div class="sidebar-projects-head">
          <span class="sidebar-section-title">Projects</span>
          <div class="sidebar-projects-actions">
            <button
              class={`sidebar-project-head-btn ${showPathEntry() ? "is-active" : ""}`}
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

      <button class="sidebar-settings-btn" type="button" onClick={openSettingsPanel}>
        <Icon name="settings" size={16} tone="muted" />
        <span>Settings</span>
      </button>
    </aside>
  );
}