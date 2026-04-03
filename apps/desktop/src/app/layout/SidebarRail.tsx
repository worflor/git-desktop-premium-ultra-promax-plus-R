import { createEffect, createMemo, createResource, createSignal, For, Show } from "solid-js";
import { useLocation, useNavigate } from "@solidjs/router";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { Icon } from "@/components/icons/Icon";
import { listRecentRepositories, openRepository } from "@/lib/backend/commands";

type ProjectSortOrder = "updated" | "name";

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
  const [projectSortOrder, setProjectSortOrder] = createSignal<ProjectSortOrder>("updated");
  const [sortMenuOpen, setSortMenuOpen] = createSignal(false);
  const [showPathEntry, setShowPathEntry] = createSignal(false);
  const [recentRepositories, { refetch: refetchRecents }] = createResource(() =>
    listRecentRepositories()
  );

  createEffect(() => {
    const active = repository.activeRepositoryPath();
    if (!active) {
      return;
    }

    setPathInput((current) => (current === active ? current : active));
  });

  const sortedProjects = createMemo(() => {
    if (!recentRepositories.latest?.ok) {
      return [] as string[];
    }

    const items = recentRepositories.latest.data.repositories.slice(0, 24);
    if (projectSortOrder() === "updated") {
      return items;
    }

    return [...items].sort((left, right) => {
      const byName = toProjectName(left).localeCompare(toProjectName(right));
      return byName || left.localeCompare(right);
    });
  });

  const isActivePath = (path: string) => {
    const active = repository.activeRepositoryPath();
    if (!active) {
      return false;
    }

    return normalizePath(path) === normalizePath(active);
  };

  const onOpenRepository = async (rawPath?: string) => {
    const path = (rawPath ?? pathInput()).trim();
    if (!path) {
      setRepositoryError("Repository path is required.");
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
    setSortMenuOpen(false);
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

    if (nextHref === `${location.pathname}${location.search}`) {
      return;
    }

    void navigate(nextHref);
  };

  return (
    <aside class="sidebar-rail" aria-label="Projects">
      <div class="sidebar-header">
        <div class="sidebar-brand-lockup">
          <Icon name="app-logo" size={20} title="Application" />
          <div class="sidebar-wordmark">
            <span class="sidebar-wordmark-main">Code</span>
            <span class="sidebar-wordmark-stage">Beta</span>
          </div>
        </div>
      </div>

      <section class="sidebar-repository-panel">
        <div class="sidebar-projects-head">
          <span class="sidebar-section-title">Projects</span>
          <div class="sidebar-projects-actions">
            <button
              class="sidebar-project-head-btn"
              type="button"
              aria-haspopup="menu"
              aria-expanded={sortMenuOpen()}
              aria-label="Sort projects"
              onClick={() => setSortMenuOpen((current) => !current)}
              title="Sort projects"
            >
              <Icon name="sort" size={16} tone="muted" title="Sort projects" />
            </button>
            <button
              class={`sidebar-project-head-btn ${showPathEntry() ? "is-active" : ""}`}
              type="button"
              aria-pressed={showPathEntry()}
              aria-label={showPathEntry() ? "Cancel adding project" : "Add project"}
              onClick={() => setShowPathEntry((current) => !current)}
              title={showPathEntry() ? "Cancel add project" : "Add project"}
            >
              <Icon name="plus" size={16} tone="muted" title={showPathEntry() ? "Cancel add project" : "Add project"} />
            </button>
          </div>
        </div>

        <Show when={sortMenuOpen()}>
          <div class="sidebar-sort-menu" role="menu" aria-label="Project sort order">
            <button
              class={`sidebar-sort-item ${projectSortOrder() === "updated" ? "is-active" : ""}`}
              type="button"
              role="menuitemradio"
              aria-checked={projectSortOrder() === "updated"}
              onClick={() => {
                setProjectSortOrder("updated");
                setSortMenuOpen(false);
              }}
            >
              Last opened
            </button>
            <button
              class={`sidebar-sort-item ${projectSortOrder() === "name" ? "is-active" : ""}`}
              type="button"
              role="menuitemradio"
              aria-checked={projectSortOrder() === "name"}
              onClick={() => {
                setProjectSortOrder("name");
                setSortMenuOpen(false);
              }}
            >
              Name
            </button>
          </div>
        </Show>

        <Show when={showPathEntry()}>
          <div class="sidebar-project-create">
            <input
              id="sidebar-repo-input"
              class="path-input"
              placeholder="/path/to/project"
              value={pathInput()}
              onInput={(event) => setPathInput(event.currentTarget.value)}
              onKeyDown={(event) => {
                if (event.key !== "Enter") {
                  return;
                }

                event.preventDefault();
                void onOpenRepository();
              }}
            />
            <button
              class="sidebar-project-add-btn"
              type="button"
              disabled={openRunning()}
              onClick={() => void onOpenRepository()}
              title="Open project"
            >
              {openRunning() ? "..." : "Add"}
            </button>
          </div>
        </Show>

        <Show when={repository.activeRepositoryPath()}>
          {(path) => <p class="sidebar-active-repo" title={path()}>{toProjectName(path())}</p>}
        </Show>

        <Show when={repositoryError()}>
          {(message) => <p class="sidebar-error-text">{message()}</p>}
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
                    <span class="sidebar-project-chevron" aria-hidden="true">
                      <Icon name="chevron-right" size={12} tone="muted" />
                    </span>
                    <span class="sidebar-project-item-name">{toProjectName(path)}</span>
                  </span>
                  <span class="sidebar-project-meta">
                    <small class="sidebar-project-item-path">{path.replace(/\\/g, "/")}</small>
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
        <Icon name="settings" size={16} tone="muted" title="Settings" />
        <span>Settings</span>
      </button>
    </aside>
  );
}