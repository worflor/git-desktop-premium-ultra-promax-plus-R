import {
  createEffect,
  createMemo,
  createSignal,
  onCleanup,
  onMount,
  Show
} from "solid-js";

import type { FileDiffManifestData } from "@/lib/backend/dtos";
import { getFileDiffChunk } from "@/lib/backend/commands";
import { recordDiffRenderMetrics } from "@/lib/telemetry/diffRenderMetrics";

type RenderMode = "dom" | "canvas";
type LineKind = "added" | "deleted" | "hunk" | "meta" | "context";

interface DiffShellProps {
  filePath?: string;
  manifest?: FileDiffManifestData;
  loading?: boolean;
  error?: string | null;
}

interface ParsedDiffLine {
  line: string;
  kind: LineKind;
  number: number;
}

const LINE_HEIGHT_PX = 18;
const CANVAS_OVERSCAN_LINES = 12;
const CANVAS_LINE_NUMBER_GUTTER_PX = 56;

function detectLineKind(line: string): LineKind {
  if (line.startsWith("@@")) {
    return "hunk";
  }
  if (line.startsWith("+") && !line.startsWith("+++")) {
    return "added";
  }
  if (line.startsWith("-") && !line.startsWith("---")) {
    return "deleted";
  }
  if (
    line.startsWith("diff --git") ||
    line.startsWith("index ") ||
    line.startsWith("---") ||
    line.startsWith("+++")
  ) {
    return "meta";
  }

  return "context";
}

function resolveInitialMode(manifest: FileDiffManifestData | undefined): RenderMode {
  return manifest?.rendererMode === "canvas" ? "canvas" : "dom";
}

function estimateMemoryMb(value: string): number {
  const bytes = new TextEncoder().encode(value).length;
  return bytes / (1024 * 1024);
}

function percentile(values: number[], percentileValue: number): number {
  if (values.length === 0) {
    return 0;
  }

  const sorted = [...values].sort((left, right) => left - right);
  const rank = Math.ceil((sorted.length * percentileValue) / 100);
  const index = Math.max(0, Math.min(sorted.length - 1, rank - 1));
  return sorted[index] ?? 0;
}

export function DiffShell(props: DiffShellProps) {
  const [mode, setMode] = createSignal<RenderMode>(resolveInitialMode(props.manifest));
  const [searchTerm, setSearchTerm] = createSignal("");
  const [loadedChunks, setLoadedChunks] = createSignal<string[]>([]);
  const [loadingChunk, setLoadingChunk] = createSignal(false);
  const [chunkError, setChunkError] = createSignal<string | null>(null);
  const [copyMessage, setCopyMessage] = createSignal<string | null>(null);
  const [selectedHunkIndex, setSelectedHunkIndex] = createSignal<number>(-1);

  let viewportElement: HTMLDivElement | undefined;
  let canvasElement: HTMLCanvasElement | undefined;
  let sessionManifest: FileDiffManifestData | null = null;
  let sessionStartedAt = 0;
  let sessionFirstPaintMs: number | null = null;
  let sessionFlushed = false;
  let lastScrollAt = 0;
  let scrollFpsSamples: number[] = [];

  const manifest = createMemo(() => props.manifest);
  const hasManifest = createMemo(() => Boolean(manifest()));
  const isIdleEmpty = createMemo(
    () => !props.filePath && !props.loading && !props.error && !chunkError() && !hasManifest()
  );
  const hasMoreChunks = createMemo(() => {
    const currentManifest = manifest();
    if (!currentManifest) {
      return false;
    }
    return loadedChunks().length < currentManifest.chunkCount;
  });

  const loadedDiffText = createMemo(() => loadedChunks().join(""));

  const parsedLines = createMemo<ParsedDiffLine[]>(() => {
    const diffText = loadedDiffText();
    if (diffText.length === 0) {
      return [];
    }

    return diffText.split("\n").map((line, index) => ({
      line,
      kind: detectLineKind(line),
      number: index + 1
    }));
  });

  const visibleLines = createMemo(() => {
    const needle = searchTerm().trim().toLowerCase();
    if (!needle) {
      return parsedLines();
    }

    return parsedLines().filter((entry) => entry.line.toLowerCase().includes(needle));
  });

  const hunkJumpTargets = createMemo(() => {
    const currentManifest = manifest();
    if (!currentManifest) {
      return [];
    }

    const headerToLine = new Map<string, number>();
    for (const entry of parsedLines()) {
      if (entry.kind === "hunk" && !headerToLine.has(entry.line)) {
        headerToLine.set(entry.line, entry.number);
      }
    }

    return currentManifest.hunks.map((hunk, index) => ({
      index,
      label: `Hunk ${index + 1}: ${hunk.header}`,
      lineNumber: headerToLine.get(hunk.header) ?? hunk.newStart
    }));
  });

  const canvasVirtualHeight = createMemo(() => {
    return Math.max(visibleLines().length * LINE_HEIGHT_PX, LINE_HEIGHT_PX);
  });

  async function loadNextChunk(): Promise<void> {
    const currentManifest = manifest();
    if (!currentManifest || loadingChunk()) {
      return;
    }

    const nextChunkIndex = loadedChunks().length;
    if (nextChunkIndex >= currentManifest.chunkCount) {
      return;
    }

    setLoadingChunk(true);
    const expectedDiffId = currentManifest.diffId;
    const result = await getFileDiffChunk(expectedDiffId, nextChunkIndex);
    setLoadingChunk(false);

    if (manifest()?.diffId !== expectedDiffId) {
      return;
    }

    if (!result.ok) {
      setChunkError(result.error.message);
      return;
    }

    setLoadedChunks((current) => [...current, result.data.chunkText]);
  }

  function flushRenderMetrics(currentManifest: FileDiffManifestData | null): void {
    if (!currentManifest || sessionFlushed) {
      return;
    }

    const firstPaintMs =
      sessionFirstPaintMs ?? Math.max(performance.now() - sessionStartedAt, 0);
    const sustainedScrollFps = percentile(scrollFpsSamples, 50);
    const memoryEstimateMb = estimateMemoryMb(loadedDiffText());

    recordDiffRenderMetrics({
      diffId: currentManifest.diffId,
      path: currentManifest.path,
      rendererMode: mode(),
      changedLines: currentManifest.changedLines,
      payloadBytes: currentManifest.totalBytes,
      firstPaintMs,
      sustainedScrollFps,
      memoryEstimateMb,
      fallbackActivated: currentManifest.fallbackActivated
    });

    sessionFlushed = true;
  }

  function jumpToLine(lineNumber: number): void {
    if (!viewportElement) {
      return;
    }

    const targetScrollTop = Math.max((lineNumber - 1) * LINE_HEIGHT_PX - LINE_HEIGHT_PX * 2, 0);
    viewportElement.scrollTop = targetScrollTop;
    requestAnimationFrame(() => drawCanvasViewport());
  }

  async function copyVisibleCanvasLines(): Promise<void> {
    if (typeof navigator === "undefined" || !navigator.clipboard || !viewportElement) {
      setCopyMessage("Clipboard API is unavailable in this environment.");
      return;
    }

    const startIndex = Math.max(
      Math.floor(viewportElement.scrollTop / LINE_HEIGHT_PX),
      0
    );
    const visibleCount = Math.max(
      Math.ceil(viewportElement.clientHeight / LINE_HEIGHT_PX),
      1
    );

    const content = visibleLines()
      .slice(startIndex, startIndex + visibleCount)
      .map((entry) => entry.line)
      .join("\n");

    if (content.trim().length === 0) {
      setCopyMessage("No visible canvas lines available to copy.");
      return;
    }

    try {
      await navigator.clipboard.writeText(content);
      setCopyMessage(`Copied ${visibleCount} visible lines.`);
    } catch {
      setCopyMessage("Failed to copy visible canvas lines.");
    }
  }

  function drawCanvasViewport(): void {
    if (mode() !== "canvas" || !canvasElement || !viewportElement) {
      return;
    }

    const lines = visibleLines();
    if (lines.length === 0) {
      return;
    }

    const startLine = Math.max(
      Math.floor(viewportElement.scrollTop / LINE_HEIGHT_PX) - CANVAS_OVERSCAN_LINES,
      0
    );
    const visibleCount =
      Math.ceil(viewportElement.clientHeight / LINE_HEIGHT_PX) +
      CANVAS_OVERSCAN_LINES * 2;
    const endLine = Math.min(startLine + visibleCount, lines.length);
    const slice = lines.slice(startLine, endLine);

    const pixelRatio = typeof window !== "undefined" ? window.devicePixelRatio || 1 : 1;
    const width = Math.max(viewportElement.clientWidth - 16, 320);
    const height = Math.max(slice.length * LINE_HEIGHT_PX, LINE_HEIGHT_PX);

    canvasElement.width = Math.floor(width * pixelRatio);
    canvasElement.height = Math.floor(height * pixelRatio);
    canvasElement.style.width = `${width}px`;
    canvasElement.style.height = `${height}px`;
    canvasElement.style.top = `${startLine * LINE_HEIGHT_PX}px`;

    const context = canvasElement.getContext("2d");
    if (!context) {
      return;
    }

    context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    context.clearRect(0, 0, width, height);
    context.font = "12px var(--font-mono)";
    context.textBaseline = "middle";

    for (let index = 0; index < slice.length; index += 1) {
      const entry = slice[index];
      if (!entry) {
        continue;
      }
      const y = index * LINE_HEIGHT_PX;

      if (entry.kind === "added") {
        context.fillStyle = "rgba(77, 153, 77, 0.12)";
        context.fillRect(0, y, width, LINE_HEIGHT_PX);
      } else if (entry.kind === "deleted") {
        context.fillStyle = "rgba(194, 77, 77, 0.12)";
        context.fillRect(0, y, width, LINE_HEIGHT_PX);
      } else if (entry.kind === "hunk") {
        context.fillStyle = "rgba(97, 126, 255, 0.14)";
        context.fillRect(0, y, width, LINE_HEIGHT_PX);
      }

      context.fillStyle = "rgba(255, 255, 255, 0.42)";
      context.fillText(String(entry.number), 6, y + LINE_HEIGHT_PX / 2);

      context.fillStyle = "rgba(255, 255, 255, 0.88)";
      context.fillText(entry.line || " ", CANVAS_LINE_NUMBER_GUTTER_PX, y + LINE_HEIGHT_PX / 2);
    }
  }

  function onViewportScroll(): void {
    if (!viewportElement) {
      return;
    }

    const now = performance.now();
    if (lastScrollAt > 0) {
      const delta = now - lastScrollAt;
      if (delta >= 8 && delta <= 250) {
        scrollFpsSamples.push(1000 / delta);
      }
    }
    lastScrollAt = now;

    if (
      hasMoreChunks() &&
      !loadingChunk() &&
      viewportElement.scrollHeight - (viewportElement.scrollTop + viewportElement.clientHeight) < 240
    ) {
      void loadNextChunk();
    }

    drawCanvasViewport();
  }

  createEffect(() => {
    const currentManifest = manifest();
    if (sessionManifest && sessionManifest.diffId !== currentManifest?.diffId) {
      flushRenderMetrics(sessionManifest);
    }

    sessionManifest = currentManifest ?? null;
    sessionStartedAt = performance.now();
    sessionFirstPaintMs = null;
    sessionFlushed = false;
    lastScrollAt = 0;
    scrollFpsSamples = [];
    setLoadedChunks([]);
    setChunkError(null);
    setCopyMessage(null);
    setSelectedHunkIndex(-1);

    if (!currentManifest) {
      return;
    }

    setMode(resolveInitialMode(currentManifest));
    if (viewportElement) {
      viewportElement.scrollTop = 0;
    }
    void loadNextChunk();
  });

  createEffect(() => {
    const lineCount = parsedLines().length;
    if (!manifest() || lineCount === 0 || sessionFirstPaintMs !== null) {
      return;
    }

    requestAnimationFrame(() => {
      if (!manifest() || parsedLines().length === 0 || sessionFirstPaintMs !== null) {
        return;
      }
      sessionFirstPaintMs = Math.max(performance.now() - sessionStartedAt, 0);
    });
  });

  createEffect(() => {
    mode();
    visibleLines();
    requestAnimationFrame(() => drawCanvasViewport());
  });

  onMount(() => {
    if (!viewportElement || typeof ResizeObserver === "undefined") {
      return;
    }

    const resizeObserver = new ResizeObserver(() => {
      requestAnimationFrame(() => drawCanvasViewport());
    });
    resizeObserver.observe(viewportElement);

    onCleanup(() => {
      resizeObserver.disconnect();
    });
  });

  onCleanup(() => {
    flushRenderMetrics(sessionManifest);
  });

  return (
    <section class="diff-shell" classList={{ "is-empty": isIdleEmpty() }} data-render-mode={mode()}>
      <header class="diff-header">
        <h2>{props.filePath ? props.filePath : "No file selected"}</h2>
        <div class="diff-controls">
          <button
            class={`mode-toggle ${mode() === "dom" ? "is-active" : ""}`}
            onClick={() => setMode("dom")}
            disabled={!hasManifest()}
          >
            DOM
          </button>
          <button
            class={`mode-toggle ${mode() === "canvas" ? "is-active" : ""}`}
            onClick={() => setMode("canvas")}
            disabled={!hasManifest()}
          >
            Canvas
          </button>

          <Show when={mode() === "canvas" && parsedLines().length > 0}>
            <button class="mode-toggle" onClick={() => void copyVisibleCanvasLines()}>
              Copy Visible
            </button>
          </Show>

          <Show when={hunkJumpTargets().length > 0}>
            <select
              class="diff-hunk-select"
              value={String(selectedHunkIndex())}
              onChange={(event) => {
                const index = Number.parseInt(event.currentTarget.value, 10);
                setSelectedHunkIndex(index);
                const target = hunkJumpTargets().find((item) => item.index === index);
                if (target) {
                  jumpToLine(target.lineNumber);
                }
              }}
            >
              <option value="-1">Jump to hunk</option>
              {hunkJumpTargets().map((target) => (
                <option value={target.index}>{target.label}</option>
              ))}
            </select>
          </Show>

          <input
            class="diff-search"
            placeholder="Search diff..."
            aria-label="Search in diff"
            value={searchTerm()}
            onInput={(event) => setSearchTerm(event.currentTarget.value)}
          />
        </div>
      </header>

      <Show when={manifest()}>
        {(currentManifest) => (
          <div class="diff-shell-meta">
            <span>Mode {currentManifest().rendererMode}</span>
            <span>Chunks {loadedChunks().length}/{currentManifest().chunkCount}</span>
            <span>Lines {currentManifest().totalLines}</span>
            <span>Pretext prepare/layout {currentManifest().pretextPrepareMs}ms/{currentManifest().pretextLayoutMs}ms</span>
          </div>
        )}
      </Show>

      <Show when={manifest()?.fallbackActivated}>
        <div class="diff-fallback-warning">
          Fallback layout active: {manifest()?.fallbackReason ?? "runtime fallback activated"}
        </div>
      </Show>

      <div
        class="diff-viewport"
        ref={(element) => {
          viewportElement = element;
        }}
        onScroll={onViewportScroll}
      >
        <Show when={props.loading}>
          <div class="diff-viewport-dom">Preparing diff chunks...</div>
        </Show>

        <Show when={!props.loading && props.error}>
          <div class="diff-viewport-dom">{props.error}</div>
        </Show>

        <Show when={!props.loading && !props.error && chunkError()}>
          {(errorMessage) => <div class="diff-viewport-dom">{errorMessage()}</div>}
        </Show>

        <Show when={!props.loading && !props.error && !chunkError() && !manifest()}>
          <div class="diff-viewport-dom">Select a changed file to view its diff.</div>
        </Show>

        <Show when={!props.loading && !props.error && !chunkError() && manifest()}>
          <Show
            when={parsedLines().length > 0 || hasMoreChunks()}
            fallback={<div class="diff-viewport-dom">No line-level changes detected for this file.</div>}
          >
            <Show
              when={mode() === "dom"}
              fallback={
                <div class="diff-viewport-canvas" style={{ height: `${canvasVirtualHeight()}px` }}>
                  <canvas
                    ref={(element) => {
                      canvasElement = element;
                    }}
                    class="diff-canvas-layer"
                  />
                </div>
              }
            >
              <div class="diff-viewport-dom">
                {visibleLines().map((entry) => (
                  <div class={`diff-line diff-line-${entry.kind}`}>
                    <span class="diff-line-number">{entry.number}</span>
                    <span class="diff-line-text">{entry.line || " "}</span>
                  </div>
                ))}
              </div>
            </Show>

            <Show when={hasMoreChunks()}>
              <div class="diff-chunk-controls">
                <button class="primary-btn" onClick={() => void loadNextChunk()} disabled={loadingChunk()}>
                  {loadingChunk() ? "Loading..." : "Load More"}
                </button>
              </div>
            </Show>
          </Show>
        </Show>
      </div>

      <Show when={copyMessage()}>
        {(message) => <p class="diff-copy-status">{message()}</p>}
      </Show>
    </section>
  );
}
