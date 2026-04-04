import { createEffect, onCleanup, onMount, type JSX } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { CommandRecoveryBanner } from "@/app/layout/CommandRecoveryBanner";
import { useLayoutPreferences } from "@/app/layout/LayoutPreferencesContext";
import { SidebarRail } from "@/app/layout/SidebarRail";
import { PanelResizer } from "@/app/layout/PanelResizer";
import { UtilityDrawer } from "@/app/layout/UtilityDrawer";
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
  const layout = useLayoutPreferences();
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
        void navigate(outcome.route);
      }
    };

    let tickerId: number;
    let lastX = 0, lastY = 0;

    const runTicker = () => {
      // High-performance polling of window coordinates for realtime pinning
      // Using a unified ticker ensures window and mouse stay in sync at monitor refresh rate
      const root = document.documentElement;
      
      // Update window position (Crucial for smooth window dragging)
      root.style.setProperty("--window-screen-x", window.screenX.toString());
      root.style.setProperty("--window-screen-y", window.screenY.toString());

      tickerId = requestAnimationFrame(runTicker);
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
    
    // Start the realtime pinning engine
    tickerId = requestAnimationFrame(runTicker);
    
    onCleanup(() => {
      clearPrefixTimer();
      cancelAnimationFrame(tickerId);
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
