import { onCleanup } from "solid-js";
import {
  SIDEBAR_WIDTH_MAX_PX,
  SIDEBAR_WIDTH_MIN_PX,
  useLayoutPreferences
} from "@/app/layout/LayoutPreferencesContext";

const KEYBOARD_STEP_PX = 16;
const SNAP_STEP_PX = 8;

function snapToGrid(value: number): number {
  return Math.round(value / SNAP_STEP_PX) * SNAP_STEP_PX;
}

export function PanelResizer() {
  const layout = useLayoutPreferences();
  let detachDragHandlers: (() => void) | undefined;

  const stopDragging = () => {
    if (!detachDragHandlers) {
      return;
    }

    detachDragHandlers();
    detachDragHandlers = undefined;
  };

  const onPointerDown = (event: PointerEvent & { currentTarget: HTMLDivElement }) => {
    if (event.button !== 0) {
      return;
    }

    event.preventDefault();
    const startX = event.clientX;
    const startWidth = layout.sidebarWidthPx();
    const startPosition = layout.sidebarPosition();

    const onPointerMove = (moveEvent: PointerEvent) => {
      const delta = moveEvent.clientX - startX;
      const nextWidth = startPosition === "left" ? startWidth + delta : startWidth - delta;
      layout.setSidebarWidthPx(snapToGrid(nextWidth));
    };

    const onPointerUp = () => {
      stopDragging();
      void layout.persistLayoutPreferences();
    };

    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerup", onPointerUp);

    detachDragHandlers = () => {
      window.removeEventListener("pointermove", onPointerMove);
      window.removeEventListener("pointerup", onPointerUp);
    };

    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") {
      return;
    }

    event.preventDefault();
    const step = event.key === "ArrowRight" ? KEYBOARD_STEP_PX : -KEYBOARD_STEP_PX;
    const signedStep = layout.sidebarPosition() === "left" ? step : -step;
    layout.setSidebarWidthPx(snapToGrid(layout.sidebarWidthPx() + signedStep));
    void layout.persistLayoutPreferences();
  };

  onCleanup(() => {
    stopDragging();
  });

  return (
    <div
      class="panel-resizer"
      role="separator"
      aria-orientation="vertical"
      aria-label="Resize sidebar panel"
      aria-valuemin={SIDEBAR_WIDTH_MIN_PX}
      aria-valuemax={SIDEBAR_WIDTH_MAX_PX}
      aria-valuenow={layout.sidebarWidthPx()}
      tabIndex={0}
      onPointerDown={onPointerDown}
      onKeyDown={onKeyDown}
    />
  );
}
