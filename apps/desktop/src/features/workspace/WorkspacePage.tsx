import {
  createSignal,
  createMemo,
  lazy,
  Match,
  onCleanup,
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

type WorkspaceMode = "changes" | "history" | "branches" | "sync";

interface ModeEntry {
  id: WorkspaceMode;
  icon: "changes" | "history" | "branches" | "sync";
  route: `/${WorkspaceMode}`;
}

const MODES: readonly ModeEntry[] = [
  { id: "changes", icon: "changes", route: "/changes" },
  { id: "history", icon: "history", route: "/history" },
  { id: "branches", icon: "branches", route: "/branches" },
  { id: "sync", icon: "sync", route: "/sync" },
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

const SyncPage = lazy(async () => {
  const module = await import("@/features/sync/SyncPage");
  return { default: module.SyncPage };
});

const SettingsPage = lazy(async () => {
  const module = await import("@/features/settings/SettingsPage");
  return { default: module.SettingsPage };
});

const COMPACT_BREAKPOINT_PX = 960;

function resolveModeFromPath(pathname: string): WorkspaceMode {
  if (pathname.startsWith("/history")) return "history";
  if (pathname.startsWith("/branches")) return "branches";
  if (pathname.startsWith("/sync")) return "sync";
  return "changes";
}

export function WorkspacePage() {
  const repository = useRepositoryContext();
  const location = useLocation();
  const navigate = useNavigate();
  const [isCompactLayout, setIsCompactLayout] = createSignal(
    typeof window !== "undefined" ? window.innerWidth <= COMPACT_BREAKPOINT_PX : false
  );

  onMount(() => {
    const syncCompactMode = () => {
      setIsCompactLayout(window.innerWidth <= COMPACT_BREAKPOINT_PX);
    };

    syncCompactMode();
    window.addEventListener("resize", syncCompactMode, { passive: true });
    onCleanup(() => {
      window.removeEventListener("resize", syncCompactMode);
    });
  });

  const activeMode = createMemo(() => resolveModeFromPath(location.pathname));

  const onSelectMode = (entry: ModeEntry) => {
    if (location.pathname === entry.route) return;
    void navigate(entry.route);
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
    if (nextHref === currentHref) return;
    void navigate(nextHref);
  };

  return (
    <div class="workspace-shell">
      {/* ── Topbar: mode icons + repo context ── */}
      <div class="workspace-topbar">
        <div class="workspace-topbar-copy">
          <Show when={isCompactLayout()}>
            <BrandLockup class="workspace-topbar-brand" />
          </Show>
          <Show when={repository.activeRepositoryPath()} fallback={
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
              class={`workspace-mode-btn ${activeMode() === entry.id ? "is-active" : ""}`}
              onClick={() => onSelectMode(entry)}
              title={entry.id}
              aria-current={activeMode() === entry.id ? "page" : undefined}
            >
              <Icon name={entry.icon} size={16} />
            </button>
          ))}
          <button
            class={`workspace-mode-btn workspace-settings-btn ${isSettingsOpen() ? "is-active" : ""}`}
            type="button"
            title="settings"
            aria-label={isSettingsOpen() ? "Close settings" : "Open settings"}
            aria-pressed={isSettingsOpen()}
            onClick={() => setSettingsPanel(!isSettingsOpen())}
          >
            <Icon name="settings" size={16} />
          </button>
        </div>
      </div>

      {/* ── Content surface ── */}
      <div class="workspace-content">
        <div class="workspace-content-panel">
          <Show when={!repository.activeRepositoryPath()}>
            <div class="workspace-empty-inline-hint">
              Open a project from the sidebar to get started.
            </div>
          </Show>
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
              <Match when={activeMode() === "sync"}>
                <SyncPage embedded />
              </Match>
            </Switch>
          </Suspense>
        </div>
      </div>

      {/* ── Settings slide overlay ── */}
      <div class={`settings-slide-layer ${isSettingsOpen() ? "is-open" : ""}`} aria-hidden={!isSettingsOpen()}>
        <button
          type="button"
          class="settings-slide-backdrop"
          aria-label="Close settings"
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