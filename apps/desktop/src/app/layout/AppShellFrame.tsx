import { createEffect, onCleanup, onMount, type JSX } from "solid-js";
import { useLocation, useNavigate } from "@solidjs/router";
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

function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  const tagName = target.tagName.toLowerCase();
  if (tagName === "input" || tagName === "textarea" || tagName === "select") return true;
  return target.isContentEditable;
}

export function AppShellFrame(props: AppShellFrameProps) {
  const mountedAt = performance.now();
  const layout = useLayoutPreferences();
  const location = useLocation();
  const navigate = useNavigate();
  const isCompactLayout = useCompactLayoutMode();

  const shellGridStyle = () => `--sidebar-width: ${layout.sidebarWidthPx()}px;`;
  const shellRootClass = () =>
    isCompactLayout() ? "app-shell-root is-compact" : "app-shell-root is-full";

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
          const searchParams = new URLSearchParams(location.search);
          searchParams.set("panel", outcome.route === "/sync" ? "sync" : "settings");
          const nextQuery = searchParams.toString();
          const nextHref = nextQuery.length > 0 ? `${location.pathname}?${nextQuery}` : location.pathname;
          void navigate(nextHref);
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
      sampleWindowPosition();
      windowSampleIntervalId = window.setInterval(sampleWindowPosition, 66);
      startupDelayId = undefined;
    }, 120);
    
    onCleanup(() => {
      clearPrefixTimer();
      if (startupDelayId !== undefined) {
        window.clearTimeout(startupDelayId);
      }
      if (windowSampleIntervalId !== undefined) {
        window.clearInterval(windowSampleIntervalId);
      }
      window.removeEventListener("keydown", onWindowKeyDown);
      window.removeEventListener("mousemove", onWindowMouseMove);
    });
  });

  return (
    <div class={shellRootClass()}>
      {/* GPU-Accelerated Celestial Backdrop */}
      <div class="parallax-backdrop">
        <div class="parallax-layer layer-bg" />
        <div class="parallax-layer layer-far" />
        <div class="parallax-layer layer-mid" />
        <div class="parallax-layer layer-near" />
        <div class="parallax-layer layer-theme" />
      </div>

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
