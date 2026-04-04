import { createSignal, onCleanup, onMount, type Accessor } from "solid-js";

export const COMPACT_LAYOUT_BREAKPOINT_PX = 694;

const COMPACT_LAYOUT_QUERY = `(max-width: ${COMPACT_LAYOUT_BREAKPOINT_PX}px)`;

function readCompactLayoutMatch(): boolean {
  if (typeof window === "undefined") {
    return false;
  }
  return window.matchMedia(COMPACT_LAYOUT_QUERY).matches;
}

export function useCompactLayoutMode(): Accessor<boolean> {
  const [isCompactLayout, setIsCompactLayout] = createSignal(readCompactLayoutMatch());

  onMount(() => {
    if (typeof window === "undefined") {
      return;
    }

    const mediaQuery = window.matchMedia(COMPACT_LAYOUT_QUERY);
    const update = (next: boolean) => setIsCompactLayout(next);

    update(mediaQuery.matches);

    const onChange = (event: MediaQueryListEvent) => {
      update(event.matches);
    };

    if (typeof mediaQuery.addEventListener === "function") {
      mediaQuery.addEventListener("change", onChange);
      onCleanup(() => {
        mediaQuery.removeEventListener("change", onChange);
      });
      return;
    }

    mediaQuery.addListener(onChange);
    onCleanup(() => {
      mediaQuery.removeListener(onChange);
    });
  });

  return isCompactLayout;
}
