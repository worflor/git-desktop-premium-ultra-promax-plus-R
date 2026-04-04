import { createSignal, onCleanup, onMount, Show } from "solid-js";
import { Icon } from "@/components/icons/Icon";
import {
  UTILITY_DRAWER_HEIGHT_MAX_PX,
  UTILITY_DRAWER_HEIGHT_MIN_PX,
  useLayoutPreferences
} from "@/app/layout/LayoutPreferencesContext";
import {
  clearCommandLifecycleEvents,
  getCommandLifecycleEvents,
  subscribeCommandLifecycleEvents,
  type CommandLifecycleEvent
} from "@/lib/telemetry/commandLifecycle";

const DISPLAY_LIMIT = 24;
const KEYBOARD_STEP_PX = 16;
const SNAP_STEP_PX = 8;
const DRAWER_HEADER_HEIGHT_PX = 32;
const DRAWER_ROW_HEIGHT_PX = 24;

function snapToGrid(value: number): number {
  return Math.round(value / SNAP_STEP_PX) * SNAP_STEP_PX;
}

export function UtilityDrawer() {
  const layout = useLayoutPreferences();
  const [events, setEvents] = createSignal<CommandLifecycleEvent[]>(
    getCommandLifecycleEvents(DISPLAY_LIMIT)
  );
  let detachResizeHandlers: (() => void) | undefined;

  onMount(() => {
    const unsubscribe = subscribeCommandLifecycleEvents((allEvents) => {
      setEvents(allEvents.slice(0, DISPLAY_LIMIT));
    });

    onCleanup(unsubscribe);
  });

  const formatEventTime = (timestamp: string) => {
    const parsed = new Date(timestamp);
    if (Number.isNaN(parsed.getTime())) {
      return timestamp;
    }

    return parsed.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  };

  const isExpanded = () => layout.utilityDrawerExpanded();

  const toggleExpanded = () => {
    layout.setUtilityDrawerExpanded(!isExpanded());
    void layout.persistLayoutPreferences();
  };

  const stopResizing = () => {
    if (!detachResizeHandlers) {
      return;
    }

    detachResizeHandlers();
    detachResizeHandlers = undefined;
  };

  const onResizePointerDown = (event: PointerEvent & { currentTarget: HTMLDivElement }) => {
    if (event.button !== 0) {
      return;
    }

    event.preventDefault();
    const startY = event.clientY;
    const startHeight = layout.utilityDrawerHeightPx();

    const onPointerMove = (moveEvent: PointerEvent) => {
      const delta = moveEvent.clientY - startY;
      layout.setUtilityDrawerHeightPx(snapToGrid(startHeight - delta));
    };

    const onPointerUp = () => {
      stopResizing();
      void layout.persistLayoutPreferences();
    };

    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerup", onPointerUp);

    detachResizeHandlers = () => {
      window.removeEventListener("pointermove", onPointerMove);
      window.removeEventListener("pointerup", onPointerUp);
    };

    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const onResizeKeyDown = (event: KeyboardEvent) => {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") {
      return;
    }

    event.preventDefault();
    const delta = event.key === "ArrowUp" ? KEYBOARD_STEP_PX : -KEYBOARD_STEP_PX;
    layout.setUtilityDrawerHeightPx(snapToGrid(layout.utilityDrawerHeightPx() + delta));
    void layout.persistLayoutPreferences();
  };

  const effectiveDrawerHeightPx = () => {
    const preferredHeight = layout.utilityDrawerHeightPx();
    const visibleRowCount = Math.min(events().length, DISPLAY_LIMIT);
    const contentHeight = DRAWER_HEADER_HEIGHT_PX + 12 + (visibleRowCount > 0 ? visibleRowCount * DRAWER_ROW_HEIGHT_PX : 30);

    if (visibleRowCount <= 4) {
      return Math.max(
        UTILITY_DRAWER_HEIGHT_MIN_PX,
        Math.min(preferredHeight, snapToGrid(contentHeight))
      );
    }
    return Math.max(UTILITY_DRAWER_HEIGHT_MIN_PX, preferredHeight);
  };

  const drawerStyle = () => (isExpanded() ? `height: ${effectiveDrawerHeightPx()}px;` : undefined);

  onCleanup(() => {
    stopResizing();
  });

  return (
    <footer class={`utility-drawer ${isExpanded() ? "is-expanded" : "is-collapsed"}`} style={drawerStyle()}>
      <Show when={isExpanded()}>
        <div
          class="utility-drawer-resizer"
          role="separator"
          aria-orientation="horizontal"
          aria-label="Resize utility drawer"
          aria-valuemin={UTILITY_DRAWER_HEIGHT_MIN_PX}
          aria-valuemax={UTILITY_DRAWER_HEIGHT_MAX_PX}
          aria-valuenow={layout.utilityDrawerHeightPx()}
          tabIndex={0}
          onPointerDown={onResizePointerDown}
          onKeyDown={onResizeKeyDown}
        />
      </Show>
      <div class="utility-drawer-header">
        <div class="hybrid-log-button">
          <button
            class="hybrid-log-toggle"
            onClick={toggleExpanded}
            aria-expanded={isExpanded()}
            aria-controls="utility-drawer-events"
          >
            Logs
          </button>
          <div class="hybrid-log-divider" />
          <button
            class="hybrid-log-clear"
            onClick={() => clearCommandLifecycleEvents()}
            disabled={events().length === 0}
            title="Clear Logs"
            aria-label="Clear Logs"
          >
            <Icon name="clear" size={12} class="clear-icon-svg" />
          </button>
        </div>
        <span class="hybrid-log-count">({events().length})</span>
      </div>

      <Show when={isExpanded()}>
        <div class="utility-drawer-body" id="utility-drawer-events">
          <Show when={events().length > 0} fallback={<p class="utility-drawer-empty">No command events yet.</p>}>
            <ul class="utility-event-list">
              {events().map((event) => (
                <li class={`utility-event-row event-${event.type}`}>
                  <span class="utility-event-time">{formatEventTime(event.at)}</span>
                  <span class="utility-event-type">{event.type.toUpperCase()}</span>
                  <span class="utility-event-command" title={event.command}>{event.command}</span>
                  <Show when={event.errorCode}>
                    {(errorCode) => <span class="utility-event-error">{errorCode()}</span>}
                  </Show>
                </li>
              ))}
            </ul>
          </Show>
        </div>
      </Show>
    </footer>
  );
}
