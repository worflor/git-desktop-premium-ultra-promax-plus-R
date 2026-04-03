import {
  createMemo,
  For,
  Match,
  Show,
  Switch
} from "solid-js";
import { useLocation, useNavigate } from "@solidjs/router";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { BranchesPage } from "@/features/branches/BranchesPage";
import { ChangesPage } from "@/features/changes/ChangesPage";
import { HistoryPage } from "@/features/history/HistoryPage";
import { SettingsPage } from "@/features/settings/SettingsPage";
import { SyncPage } from "@/features/sync/SyncPage";

type WorkspaceMenuId = "changes" | "history" | "branches" | "sync";

interface WorkspaceMenu {
  id: WorkspaceMenuId;
  label: string;
  route: `/${WorkspaceMenuId}`;
}

const WORKSPACE_MENUS: readonly WorkspaceMenu[] = [
  { id: "changes", label: "Changes", route: "/changes" },
  { id: "history", label: "History", route: "/history" },
  { id: "branches", label: "Branches", route: "/branches" },
  { id: "sync", label: "Sync", route: "/sync" }
];

function resolvePanelFromPath(pathname: string): WorkspaceMenuId {
  if (pathname.startsWith("/history")) {
    return "history";
  }

  if (pathname.startsWith("/branches")) {
    return "branches";
  }

  if (pathname.startsWith("/sync")) {
    return "sync";
  }

  return "changes";
}

export function WorkspacePage() {
  const repository = useRepositoryContext();
  const location = useLocation();
  const navigate = useNavigate();

  const repositoryLabel = createMemo(() => {
    const path = repository.activeRepositoryPath();
    if (!path) {
      return "No repo";
    }

    const segments = path.replace(/\\/g, "/").split("/").filter(Boolean);
    return segments[segments.length - 1] ?? path;
  });

  const activePanel = createMemo(() => resolvePanelFromPath(location.pathname));

  const onSelectPanel = (menu: WorkspaceMenu) => {
    if (location.pathname === menu.route) {
      return;
    }

    void navigate(menu.route);
  };

  const isSettingsOpen = createMemo(() => {
    const searchParams = new URLSearchParams(location.search);
    return searchParams.get("panel") === "settings";
  });

  const setSettingsPanel = (open: boolean) => {
    const searchParams = new URLSearchParams(location.search);

    if (open) {
      searchParams.set("panel", "settings");
    } else {
      searchParams.delete("panel");
    }

    const nextQuery = searchParams.toString();
    const nextHref = nextQuery.length > 0 ? `${location.pathname}?${nextQuery}` : location.pathname;
    const currentHref = `${location.pathname}${location.search}`;

    if (nextHref === currentHref) {
      return;
    }

    void navigate(nextHref);
  };

  const activePanelLabel = createMemo(() => {
    const current = activePanel();
    const match = WORKSPACE_MENUS.find((menu) => menu.id === current);
    return match?.label ?? "Changes";
  });

  return (
    <div class="feature-page workspace-shell">
      <header class="workspace-topbar state-card">
        <div class="workspace-topbar-copy">
          <p class="workspace-kicker">Repository Workspace</p>
          <h1 class="workspace-repo-name" title={repository.activeRepositoryPath() ?? ""}>
            {repositoryLabel()}
          </h1>
          <p class="workspace-repo-path">{repository.activeRepositoryPath() ?? "Open a repository from the left rail."}</p>
        </div>

        <nav class="workspace-view-tabs" aria-label="Workspace views">
          <For each={WORKSPACE_MENUS}>
            {(menu) => (
              <button
                type="button"
                class={`workspace-view-tab ${activePanel() === menu.id ? "is-active" : ""}`}
                aria-current={activePanel() === menu.id ? "page" : undefined}
                onClick={() => onSelectPanel(menu)}
              >
                {menu.label}
              </button>
            )}
          </For>
          <button
            type="button"
            class={`workspace-view-tab ${isSettingsOpen() ? "is-active" : ""}`}
            aria-current={isSettingsOpen() ? "page" : undefined}
            onClick={() => setSettingsPanel(!isSettingsOpen())}
          >
            Settings
          </button>
        </nav>
      </header>

      <section class="workspace-content state-card">
        <p class="workspace-active-view-label">{activePanelLabel()}</p>
        <div class="workspace-content-panel">
          <Show when={!repository.activeRepositoryPath()}>
            <p class="workspace-empty-inline-hint">No repository selected yet. Use the left sidebar to open one.</p>
          </Show>
          <Switch>
            <Match when={activePanel() === "changes"}>
              <ChangesPage embedded />
            </Match>
            <Match when={activePanel() === "history"}>
              <HistoryPage embedded />
            </Match>
            <Match when={activePanel() === "branches"}>
              <BranchesPage embedded />
            </Match>
            <Match when={activePanel() === "sync"}>
              <SyncPage embedded />
            </Match>
          </Switch>
        </div>
      </section>

      <div class={`settings-slide-layer ${isSettingsOpen() ? "is-open" : ""}`} aria-hidden={!isSettingsOpen()}>
        <button
          type="button"
          class="settings-slide-backdrop"
          aria-label="Close settings panel"
          onClick={() => setSettingsPanel(false)}
        />

        <section class="settings-slide-panel" role="dialog" aria-modal="true" aria-labelledby="settings-panel-title">
          <header class="settings-slide-header">
            <h2 id="settings-panel-title">Settings</h2>
            <button type="button" class="settings-slide-close" onClick={() => setSettingsPanel(false)}>
              Close
            </button>
          </header>

          <div class="settings-slide-body">
            <SettingsPage />
          </div>
        </section>
      </div>
    </div>
  );
}