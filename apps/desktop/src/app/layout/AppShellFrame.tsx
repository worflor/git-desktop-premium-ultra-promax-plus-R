import { createEffect, onCleanup, onMount, Show, type JSX } from "solid-js";
import { useNavigate, useSearchParams } from "@solidjs/router";
import { CommandRecoveryBanner } from "@/app/layout/CommandRecoveryBanner";
import { useLayoutPreferences } from "@/app/layout/LayoutPreferencesContext";
import { SidebarRail } from "@/app/layout/SidebarRail";
import { PanelResizer } from "@/app/layout/PanelResizer";
import { UtilityDrawer } from "@/app/layout/UtilityDrawer";
import { recordUiTiming } from "@/lib/telemetry/uiTiming";
import { resolveNavigationHotkey } from "@/lib/ui/keybindings";
import { useCompactLayoutMode } from "@/lib/ui/layoutMode";

interface AppShellFrameProps {
  children?: JSX.Element;
}

type WorkspacePanel = "settings" | "sync";

function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  const tagName = target.tagName.toLowerCase();
  if (tagName === "input" || tagName === "textarea" || tagName === "select") return true;
  return target.isContentEditable;
}

function resolveWorkspacePanel(panel: string | string[] | null | undefined): WorkspacePanel | null {
  const value = Array.isArray(panel) ? panel[0] : panel;
  return value === "settings" || value === "sync" ? value : null;
}

/**
 * Themes with multi-layer parallax particles (stardust, quantum) need
 * near/mid/far/bg layers. Single-layer themes only need layer-theme.
 * Themes with zero parallaxStrength need no layers at all.
 */
const MULTI_LAYER_THEMES = new Set(["aether", "quanta"]);
const NO_PARALLAX_THEMES = new Set(["petrichor", "helix"]);

export function AppShellFrame(props: AppShellFrameProps) {
  const mountedAt = performance.now();
  const layout = useLayoutPreferences();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const isCompactLayout = useCompactLayoutMode();

  const shellGridStyle = () => `--sidebar-width: ${layout.sidebarWidthPx()}px;`;
  const shellRootClass = () =>
    isCompactLayout() ? "app-shell-root is-compact" : "app-shell-root is-full";

  const hasParallax = () => !NO_PARALLAX_THEMES.has(layout.themeId());
  const hasMultiLayer = () => MULTI_LAYER_THEMES.has(layout.themeId());

  createEffect(() => {
    if (layout.sidebarPosition() !== "left") {
      layout.setSidebarPosition("left");
    }
  });

  onMount(() => {
    requestAnimationFrame(() => {
      recordUiTiming({
        event: "shell.frame.first-paint",
        phase: "mount",
        durationMs: performance.now() - mountedAt
      });
    });

    let awaitingPrefix = false;
    let prefixTimerId: number | undefined;

    const clearPrefixTimer = () => {
      if (prefixTimerId !== undefined) {
        window.clearTimeout(prefixTimerId);
        prefixTimerId = undefined;
      }
    };

    const armPrefixTimer = () => {
      clearPrefixTimer();
      prefixTimerId = window.setTimeout(() => {
        awaitingPrefix = false;
        prefixTimerId = undefined;
      }, 1400);
    };

    const onWindowKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey) return;
      if (isEditableTarget(event.target)) return;

      if (event.key === "Escape") {
        if (resolveWorkspacePanel(searchParams.panel)) {
          event.preventDefault();
          void setSearchParams({ panel: null }, { replace: true });
        }
        return;
      }

      const outcome = resolveNavigationHotkey(
        layout.keybindingProfile(),
        event.key,
        awaitingPrefix
      );

      awaitingPrefix = outcome.awaitingPrefix;
      if (awaitingPrefix) {
        armPrefixTimer();
      } else {
        clearPrefixTimer();
      }

      if (!outcome.consumed) return;
      event.preventDefault();
      if (outcome.route) {
        if (outcome.route === "/sync" || outcome.route === "/settings") {
          void setSearchParams({ panel: outcome.route === "/sync" ? "sync" : "settings" }, { replace: true });
          return;
        }

        void navigate(outcome.route);
      }
    };

    let windowSampleIntervalId: number | undefined;
    let startupDelayId: number | undefined;
    let lastX = 0, lastY = 0;
    let lastWindowX: number | null = null;
    let lastWindowY: number | null = null;

    const sampleWindowPosition = () => {
      // Avoid rewriting CSS variables when the window is stationary.
      const root = document.documentElement;

      const screenX = window.screenX;
      const screenY = window.screenY;
      if (screenX !== lastWindowX) {
        root.style.setProperty("--window-screen-x", screenX.toString());
        lastWindowX = screenX;
      }
      if (screenY !== lastWindowY) {
        root.style.setProperty("--window-screen-y", screenY.toString());
        lastWindowY = screenY;
      }
    };

    const startWindowSampling = () => {
      if (windowSampleIntervalId !== undefined) return;
      sampleWindowPosition();
      windowSampleIntervalId = window.setInterval(sampleWindowPosition, 66);
    };

    const stopWindowSampling = () => {
      if (windowSampleIntervalId === undefined) return;
      window.clearInterval(windowSampleIntervalId);
      windowSampleIntervalId = undefined;
    };

    const onWindowMouseMove = (event: MouseEvent) => {
      // Only inject mouse variables on change to reduce CSS-OM overhead
      if (event.screenX === lastX && event.screenY === lastY) return;
      lastX = event.screenX;
      lastY = event.screenY;

      const root = document.documentElement;
      root.style.setProperty("--monitor-mouse-x", lastX.toString());
      root.style.setProperty("--monitor-mouse-y", lastY.toString());
    };

    window.addEventListener("keydown", onWindowKeyDown);
    window.addEventListener("mousemove", onWindowMouseMove, { passive: true });

    // Let first content paint complete before starting low-frequency window position sampling.
    startupDelayId = window.setTimeout(() => {
      startWindowSampling();
      startupDelayId = undefined;
    }, 120);

    // Gate the window position polling interval on page visibility.
    // When the window is hidden, the interval is pure waste — screenX/Y cannot
    // change while the window is not visible, and the CSS variables drive nothing.
    const onVisibilityChange = () => {
      if (document.hidden) {
        stopWindowSampling();
      } else if (startupDelayId === undefined) {
        startWindowSampling();
      }
    };
    document.addEventListener("visibilitychange", onVisibilityChange);

    onCleanup(() => {
      clearPrefixTimer();
      if (startupDelayId !== undefined) {
        window.clearTimeout(startupDelayId);
      }
      stopWindowSampling();
      document.removeEventListener("visibilitychange", onVisibilityChange);
      window.removeEventListener("keydown", onWindowKeyDown);
      window.removeEventListener("mousemove", onWindowMouseMove);
    });
  });

  return (
    <div class={shellRootClass()}>
      {/* GPU-Accelerated Celestial Backdrop — conditionally mounted by theme.
          Themes with zero parallax (petrichor, helix) skip all layers.
          Themes with single-layer particles skip the near/mid/far/bg layers.
          This avoids reserving GPU texture memory for invisible compositor layers. */}
      <Show when={hasParallax()}>
        <div class="parallax-backdrop">
          <Show when={hasMultiLayer()}>
            <div class="parallax-layer layer-bg" />
            <div class="parallax-layer layer-far" />
            <div class="parallax-layer layer-mid" />
            <div class="parallax-layer layer-near" />
          </Show>
          <div class="parallax-layer layer-theme" />
        </div>
      </Show>

      <CommandRecoveryBanner />
      <div class="app-shell-grid sidebar-left" style={shellGridStyle()}>
        <SidebarRail />
        <PanelResizer />
        <main class="main-panel">{props.children}</main>
      </div>
      <UtilityDrawer />
    </div>
  );
}
