export function scheduleBackgroundTask(task: () => void): () => void {
  if (typeof window === "undefined") {
    task();
    return () => {};
  }

  const browserWindow: Window & typeof globalThis = window;

  if ("requestIdleCallback" in browserWindow) {
    const handle = window.requestIdleCallback(() => task(), { timeout: 150 });
    return () => window.cancelIdleCallback(handle);
  }

  const handle = globalThis.setTimeout(task, 0);
  return () => globalThis.clearTimeout(handle);
}
