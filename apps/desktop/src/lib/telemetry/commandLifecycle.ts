export type CommandLifecycleEventType = "start" | "success" | "failure" | "retry";

export interface CommandLifecycleEvent {
  id: number;
  type: CommandLifecycleEventType;
  command: string;
  at: string;
  durationMs?: number;
  requestId?: string;
  errorCode?: string;
  message?: string;
  attempt?: number;
}

const MAX_RETAINED_EVENTS = 240;
const lifecycleEvents: CommandLifecycleEvent[] = [];
const listeners = new Set<(events: CommandLifecycleEvent[]) => void>();
let nextEventId = 1;

export function recordCommandLifecycleEvent(
  event: Omit<CommandLifecycleEvent, "id" | "at"> & { at?: string }
): void {
  const lifecycleEvent: CommandLifecycleEvent = {
    id: nextEventId++,
    at: event.at ?? new Date().toISOString(),
    ...event
  };

  lifecycleEvents.push(lifecycleEvent);
  if (lifecycleEvents.length > MAX_RETAINED_EVENTS) {
    lifecycleEvents.splice(0, lifecycleEvents.length - MAX_RETAINED_EVENTS);
  }

  emitLifecycleEvents();
}

export function getCommandLifecycleEvents(limit = MAX_RETAINED_EVENTS): CommandLifecycleEvent[] {
  const normalizedLimit = Math.max(1, Math.floor(limit));
  const recent = lifecycleEvents.slice(-normalizedLimit);
  return recent.reverse();
}

export function clearCommandLifecycleEvents(): void {
  if (lifecycleEvents.length === 0) {
    return;
  }

  lifecycleEvents.length = 0;
  emitLifecycleEvents();
}

export function subscribeCommandLifecycleEvents(
  listener: (events: CommandLifecycleEvent[]) => void
): () => void {
  listeners.add(listener);
  listener(getCommandLifecycleEvents());

  return () => {
    listeners.delete(listener);
  };
}

function emitLifecycleEvents(): void {
  if (listeners.size === 0) {
    return;
  }

  const snapshot = getCommandLifecycleEvents();
  for (const listener of listeners) {
    listener(snapshot);
  }
}
