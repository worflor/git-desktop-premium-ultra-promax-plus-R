import {
  createEffect,
  createMemo,
  createResource,
  createSignal,
  lazy,
  Match,
  onMount,
  Show,
  Suspense,
  Switch
} from "solid-js";
import { useLocation, useNavigate } from "@solidjs/router";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { BrandLockup } from "@/components/composite/BrandLockup";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { Icon } from "@/components/icons/Icon";
import { SyncPanel } from "@/features/sync/SyncPanel";
import { getRepositoryStatus } from "@/lib/backend/commands";
import { recordUiTiming } from "@/lib/telemetry/uiTiming";
import { useCompactLayoutMode } from "@/lib/ui/layoutMode";

type WorkspaceMode = "changes" | "history" | "branches";
type WorkspacePanel = "settings" | "sync";

interface ModeEntry {
  id: WorkspaceMode;
  icon: "changes" | "history" | "branches";
  route: `/${WorkspaceMode}`;
}

const MODES: readonly ModeEntry[] = [
  { id: "changes", icon: "changes", route: "/changes" },
  { id: "history", icon: "history", route: "/history" },
  { id: "branches", icon: "branches", route: "/branches" }
];

const ChangesPage = lazy(async () => {
  const module = await import("@/features/changes/ChangesPage");
  return { default: module.ChangesPage };
});

const HistoryPage = lazy(async () => {
  const module = await import("@/features/history/HistoryPage");
  return { default: module.HistoryPage };
});

const BranchesPage = lazy(async () => {
  const module = await import("@/features/branches/BranchesPage");
  return { default: module.BranchesPage };
});

const SettingsPage = lazy(async () => {
  const module = await import("@/features/settings/SettingsPage");
  return { default: module.SettingsPage };
});

function resolveModeFromPath(pathname: string): WorkspaceMode {
  if (pathname.startsWith("/history")) return "history";
  if (pathname.startsWith("/branches")) return "branches";
  return "changes";
}

export function WorkspacePage() {
  const mountedAt = performance.now();
  const repository = useRepositoryContext();
  const location = useLocation();
  const navigate = useNavigate();
  const isCompactLayout = useCompactLayoutMode();
  const [panelOpenStartedAt, setPanelOpenStartedAt] = createSignal<number | null>(null);
  const activeRepositoryPath = createMemo(() => repository.activeRepositoryPath());
  const hasActiveRepository = createMemo(() => Boolean(activeRepositoryPath()));
  const [syncStatus, { refetch: refetchSyncStatus }] = createResource(activeRepositoryPath, async (path) => {
    if (!path) {
      return null;
    }
    return getRepositoryStatus(path);
  });

  const activeMode = createMemo(() => resolveModeFromPath(location.pathname));

  const onSelectMode = (entry: ModeEntry) => {
    if (location.pathname === entry.route && !location.search) return;
    void navigate(entry.route);
  };

  const activePanel = createMemo<WorkspacePanel | null>(() => {
    const searchParams = new URLSearchParams(location.search);
    const panel = searchParams.get("panel");
    return panel === "settings" || panel === "sync" ? panel : null;
  });

  const isSettingsOpen = createMemo(() => activePanel() === "settings");
  const isSyncOpen = createMemo(() => activePanel() === "sync");
  const syncStatusData = createMemo(() => {
    const latest = syncStatus.latest;
    return latest?.ok ? latest.data : null;
  });
  const shouldShowSyncSummary = createMemo(() => {
    const status = syncStatusData();
    if (!status) {
      return false;
    }
    return status.ahead > 0 || status.behind > 0;
  });

  const setActivePanel = (panel: WorkspacePanel | null) => {
    const searchParams = new URLSearchParams(location.search);
    if (panel) {
      searchParams.set("panel", panel);
    } else {
      searchParams.delete("panel");
    }

    const nextQuery = searchParams.toString();
    const nextHref = nextQuery.length > 0 ? `${location.pathname}?${nextQuery}` : location.pathname;
    const currentHref = `${location.pathname}${location.search}`;
    if (nextHref === currentHref) return;

    if (panel) {
      setPanelOpenStartedAt(performance.now());
    } else {
      setPanelOpenStartedAt(null);
    }

    void navigate(nextHref);
  };

  onMount(() => {
    requestAnimationFrame(() => {
      recordUiTiming({
        event: "workspace.page.first-paint",
        phase: "mount",
        durationMs: performance.now() - mountedAt
      });
    });
  });

  createEffect(() => {
    const panel = activePanel();
    if (!panel) {
      return;
    }

    const startedAt = panelOpenStartedAt();
    if (startedAt === null) {
      return;
    }

    requestAnimationFrame(() => {
      recordUiTiming({
        event: `${panel}.panel.open`,
        phase: "interaction",
        durationMs: performance.now() - startedAt
      });
      setPanelOpenStartedAt(null);
    });
  });

  return (
    <div class="workspace-shell">
      <div class="workspace-topbar">
        <div class="workspace-topbar-copy">
          <Show when={isCompactLayout()}>
            <BrandLockup class="workspace-topbar-brand" />
          </Show>
          <Show when={activeRepositoryPath()} fallback={
            <span class="workspace-repo-name" style="opacity:0.5">No project open</span>
          }>
            {(path) => {
              const segments = path().replace(/\\/g, "/").split("/").filter(Boolean);
              const name = segments[segments.length - 1] ?? path();
              return <span class="workspace-repo-name" title={path()}>{name}</span>;
            }}
          </Show>
        </div>

        <div class="workspace-mode-nav">
          {MODES.map((entry) => (
            <button
              class={`workspace-mode-btn hyper-reactive ${activeMode() === entry.id ? "is-active active" : ""}`}
              onClick={() => onSelectMode(entry)}
              title={entry.id}
              aria-current={activeMode() === entry.id ? "page" : undefined}
            >
              <Icon name={entry.icon} size={16} />
            </button>
          ))}

          <button
            class={`workspace-mode-btn workspace-sync-btn hyper-reactive ${isSyncOpen() ? "is-open" : ""}`}
            type="button"
            title="sync"
            aria-label={isSyncOpen() ? "Close sync" : "Open sync"}
            aria-pressed={isSyncOpen()}
            aria-expanded={isSyncOpen()}
            onClick={() => setActivePanel(isSyncOpen() ? null : "sync")}
          >
            <span class="workspace-sync-icon-slot">
              <Icon name="sync" size={16} class={`workspace-sync-icon ${isSyncOpen() ? "is-active" : ""}`.trim()} />
            </span>
            <Show when={shouldShowSyncSummary() && syncStatusData()}>
              {(resolvedStatus) => (
                <span class="workspace-sync-summary">
                  <Show when={resolvedStatus().ahead > 0}>
                    <span class="workspace-sync-chip is-ahead">{resolvedStatus().ahead}↑</span>
                  </Show>
                  <Show when={resolvedStatus().behind > 0}>
                    <span class="workspace-sync-chip is-behind">{resolvedStatus().behind}↓</span>
                  </Show>
                </span>
              )}
            </Show>
          </button>

          <button
            class={`workspace-mode-btn workspace-settings-btn hyper-reactive ${isSettingsOpen() ? "is-open" : ""}`}
            type="button"
            title="settings"
            aria-label={isSettingsOpen() ? "Close settings" : "Open settings"}
            aria-pressed={isSettingsOpen()}
            aria-expanded={isSettingsOpen()}
            onClick={() => setActivePanel(isSettingsOpen() ? null : "settings")}
          >
            <Icon name="settings" size={16} />
          </button>
        </div>
      </div>

      <div class="workspace-content">
        <div class="workspace-content-panel" classList={{ "is-empty": !hasActiveRepository() }}>
          <Suspense fallback={<LoadingStateSkeleton />}>
            <Switch>
              <Match when={activeMode() === "changes"}>
                <ChangesPage embedded />
              </Match>
              <Match when={activeMode() === "history"}>
                <HistoryPage embedded />
              </Match>
              <Match when={activeMode() === "branches"}>
                <BranchesPage embedded />
              </Match>
            </Switch>
          </Suspense>
        </div>
      </div>

      <Show when={isSyncOpen()}>
        <SyncPanel
          onClose={() => setActivePanel(null)}
          onStatusChanged={() => {
            void refetchSyncStatus();
          }}
        />
      </Show>

      <div class={`settings-slide-layer ${isSettingsOpen() ? "is-open" : ""}`} aria-hidden={!isSettingsOpen()}>
        <button
          type="button"
          class="settings-slide-backdrop"
          aria-label="Close settings"
          onClick={() => setActivePanel(null)}
        />
        <section class="settings-slide-panel" role="dialog" aria-modal="true" aria-labelledby="settings-panel-title">
          <header class="settings-slide-header">
            <h2 id="settings-panel-title">Settings</h2>
            <button type="button" class="settings-slide-close hyper-reactive" onClick={() => setActivePanel(null)}>
              Close
            </button>
          </header>
          <div class="settings-slide-body">
            <Show when={isSettingsOpen()}>
              <Suspense fallback={<LoadingStateSkeleton />}>
                <SettingsPage />
              </Suspense>
            </Show>
          </div>
        </section>
      </div>
    </div>
  );
}
