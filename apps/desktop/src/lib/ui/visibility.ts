/**
 * visibility.ts — Page Visibility Gate
 *
 * Single source of truth for whether the app window is actually visible.
 * When the window is hidden (minimized, tabbed away, occluded), all continuous
 * animation loops and timers should pause to eliminate idle GPU load.
 *
 * Exposes both a reactive Solid signal and a raw DOM attribute on <html>
 * so CSS can gate animations via [data-app-visible="false"].
 */

import { createSignal } from "solid-js";

const [pageVisible, setPageVisible] = createSignal(!document.hidden);

function syncAttribute(): void {
  document.documentElement.setAttribute(
    "data-app-visible",
    document.hidden ? "false" : "true"
  );
}

syncAttribute();

document.addEventListener("visibilitychange", () => {
  const visible = !document.hidden;
  setPageVisible(visible);
  syncAttribute();
});

/**
 * Reactive signal: true when the page is visible, false when hidden.
 * Use in rAF loops, setInterval guards, and any continuous work.
 */
export { pageVisible };
