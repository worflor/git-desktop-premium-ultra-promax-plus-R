import { createEffect, onCleanup, onMount, type JSX } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { CommandRecoveryBanner } from "@/app/layout/CommandRecoveryBanner";
import { useLayoutPreferences } from "@/app/layout/LayoutPreferencesContext";
import { SidebarRail } from "@/app/layout/SidebarRail";
import { PanelResizer } from "@/app/layout/PanelResizer";
import { UtilityDrawer } from "@/app/layout/UtilityDrawer";
import { resolveNavigationHotkey } from "@/lib/ui/keybindings";

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

  const shellGridStyle = () => `--sidebar-width: ${layout.sidebarWidthPx()}px;`;

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

    let animationFrameId: number;
    const onWindowMouseMove = (event: MouseEvent) => {
      if (animationFrameId) cancelAnimationFrame(animationFrameId);
      animationFrameId = requestAnimationFrame(() => {
        // Map cursor coordinates gracefully from [-1.0, 1.0] across the total monitor viewport
        const x = ((event.clientX / window.innerWidth) - 0.5) * 2;
        const y = ((event.clientY / window.innerHeight) - 0.5) * 2;
        document.documentElement.style.setProperty("--cursor-x", x.toFixed(3));
        document.documentElement.style.setProperty("--cursor-y", y.toFixed(3));
      });
    };

    window.addEventListener("keydown", onWindowKeyDown);
    window.addEventListener("mousemove", onWindowMouseMove, { passive: true });
    
    onCleanup(() => {
      clearPrefixTimer();
      window.removeEventListener("keydown", onWindowKeyDown);
      window.removeEventListener("mousemove", onWindowMouseMove);
      if (animationFrameId) cancelAnimationFrame(animationFrameId);
    });
  });

  return (
    <div class="app-shell-root">
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
