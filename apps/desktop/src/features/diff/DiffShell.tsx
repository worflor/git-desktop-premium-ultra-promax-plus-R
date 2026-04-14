import {
  createEffect,
  createMemo,
  createSignal,
  onCleanup,
  onMount,
  Show
} from "solid-js";
import {
  layoutNextLine,
  layoutWithLines,
  prepareWithSegments,
  walkLineRanges,
  type LayoutCursor,
  type LayoutLineRange,
  type PreparedTextWithSegments
} from "@chenglou/pretext";

import type { FileDiffManifestData, BlameLineData } from "@/lib/backend/dtos";
import { getFileDiffChunk, getFileBlame } from "@/lib/backend/commands";
import { recordDiffRenderMetrics } from "@/lib/telemetry/diffRenderMetrics";

type RenderMode = "dom" | "canvas";
type LineKind = "added" | "deleted" | "hunk" | "meta" | "context";

const RENDER_MODE_STORAGE_KEY = "agentbox-diff-render-mode";

function getPersistedRenderMode(): RenderMode | null {
  if (typeof window === "undefined") return null;
  const val = localStorage.getItem(RENDER_MODE_STORAGE_KEY);
  if (val === "dom" || val === "canvas") return val;
  return null;
}

function persistRenderMode(mode: RenderMode) {
  if (typeof window === "undefined") return;
  localStorage.setItem(RENDER_MODE_STORAGE_KEY, mode);
}

interface DiffShellProps {
  filePath?: string;
  manifest?: FileDiffManifestData;
  error?: string | null;
  repositoryPath?: string;
}

interface ParsedDiffLine {
  line: string;
  kind: LineKind;
  number: number;
}

interface IndexedPretextLine {
  number: number;
  start: LayoutCursor;
  end: LayoutCursor;
}

interface VirtualizedDomWindow {
  items: ParsedDiffLine[];
  offsetTopPx: number;
  totalHeightPx: number;
}

const LINE_HEIGHT_PX = 18;
const CANVAS_OVERSCAN_LINES = 12;
const DOM_OVERSCAN_LINES = 24;
const CANVAS_LINE_NUMBER_GUTTER_PX = 56;
const PRETEXT_FONT_PROFILE_FALLBACK = '12px "JetBrains Mono", "Consolas", monospace';
const PRETEXT_TEXT_PADDING_PX = 16;

interface RgbColor {
  r: number;
  g: number;
  b: number;
}

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

function clampChannel(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.min(255, Math.round(value)));
}

function parseCssRgbColor(value: string): RgbColor | null {
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  if (trimmed.startsWith("#")) {
    let hex = trimmed.slice(1);
    if (hex.length === 3 || hex.length === 4) {
      hex = hex
        .split("")
        .map((segment) => segment + segment)
        .join("");
    }
    if (hex.length !== 6 && hex.length !== 8) {
      return null;
    }

    const r = Number.parseInt(hex.slice(0, 2), 16);
    const g = Number.parseInt(hex.slice(2, 4), 16);
    const b = Number.parseInt(hex.slice(4, 6), 16);
    if (![r, g, b].every((segment) => Number.isFinite(segment))) {
      return null;
    }

    return {
      r: clampChannel(r),
      g: clampChannel(g),
      b: clampChannel(b)
    };
  }

  const rgbMatch = trimmed.match(/^rgba?\(([^)]+)\)$/i);
  if (!rgbMatch || !rgbMatch[1]) {
    return null;
  }

  const channels = rgbMatch[1]
    .replace(/\//g, ",")
    .split(",")
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0);

  if (channels.length < 3) {
    return null;
  }

  const r = Number.parseFloat(channels[0] ?? "0");
  const g = Number.parseFloat(channels[1] ?? "0");
  const b = Number.parseFloat(channels[2] ?? "0");
  if (![r, g, b].every((segment) => Number.isFinite(segment))) {
    return null;
  }

  return {
    r: clampChannel(r),
    g: clampChannel(g),
    b: clampChannel(b)
  };
}

function withAlpha(sourceColor: string, alpha: number, fallback = "rgba(0, 0, 0, 0)"): string {
  const parsed = parseCssRgbColor(sourceColor);
  if (!parsed) {
    return fallback;
  }

  const safeAlpha = Math.max(0, Math.min(1, alpha));
  return `rgba(${parsed.r}, ${parsed.g}, ${parsed.b}, ${safeAlpha.toFixed(3)})`;
}

function resolvePretextFontProfile(element: HTMLElement | undefined): string {
  if (!element || typeof window === "undefined") {
    return PRETEXT_FONT_PROFILE_FALLBACK;
  }

  const style = getComputedStyle(element);
  const family = style.fontFamily.trim();
  const size = style.fontSize.trim();
  const weight = style.fontWeight.trim();

  const resolvedSize = size.length > 0 ? size : "12px";
  const resolvedFamily =
    family.length > 0 ? family : '"JetBrains Mono", "Consolas", monospace';
  const resolvedWeight =
    weight.length > 0 && weight !== "normal" && weight !== "400" ? `${weight} ` : "";

  return `${resolvedWeight}${resolvedSize} ${resolvedFamily}`;
}

function parseDiffLinesWithPretext(
  prepared: PreparedTextWithSegments,
  layoutWidthPx: number
): ParsedDiffLine[] {
  const wrappedWidth = Math.max(
    layoutWidthPx - CANVAS_LINE_NUMBER_GUTTER_PX - PRETEXT_TEXT_PADDING_PX,
    64
  );

  const layoutResult = layoutWithLines(prepared, wrappedWidth, LINE_HEIGHT_PX) as {
    lines?: Array<{
      text?: string;
      start?: {
        graphemeIndex?: number;
      };
    }>;
  };

  const layoutLines = Array.isArray(layoutResult.lines) ? layoutResult.lines : [];
  const parsed: ParsedDiffLine[] = [];
  let previousKind: LineKind = "context";

  for (let index = 0; index < layoutLines.length; index += 1) {
    const currentLine = layoutLines[index];
    if (!currentLine) {
      continue;
    }

    const text = typeof currentLine.text === "string" ? currentLine.text : "";
    const graphemeIndex =
      typeof currentLine.start?.graphemeIndex === "number"
        ? currentLine.start.graphemeIndex
        : 0;
    const isContinuation = graphemeIndex > 0;
    const kind: LineKind = isContinuation ? previousKind : detectLineKind(text);

    parsed.push({
      line: text,
      kind,
      number: index + 1
    });

    previousKind = kind;
  }

  return parsed;
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
  const [mode, setMode] = createSignal<RenderMode>(getPersistedRenderMode() ?? resolveInitialMode(props.manifest));
  const [searchTerm, setSearchTerm] = createSignal("");
  const [loadedChunks, setLoadedChunks] = createSignal<string[]>([]);
  const [loadingChunk, setLoadingChunk] = createSignal(false);
  const [chunkError, setChunkError] = createSignal<string | null>(null);
  const [copyMessage, setCopyMessage] = createSignal<string | null>(null);
  const [layoutWidthPx, setLayoutWidthPx] = createSignal(1080);
  const [pretextFontProfile, setPretextFontProfile] = createSignal(PRETEXT_FONT_PROFILE_FALLBACK);
  const [viewportScrollTop, setViewportScrollTop] = createSignal(0);
  const [viewportHeightPx, setViewportHeightPx] = createSignal(0);

  const [blameData, setBlameData] = createSignal<BlameLineData[] | null>(null);
  const [blameHoveredLine, setBlameHoveredLine] = createSignal<number | null>(null);
  const [blameFetchState, setBlameFetchState] = createSignal<"idle" | "loading" | "loaded" | "error">("idle");
  let blameCacheKey = "";

  const blameForLine = (lineNum: number): BlameLineData | undefined => {
    const data = blameData();
    if (!data) return undefined;
    return data.find((entry) => entry.lineNumber === lineNum);
  };

  const onGutterPointerEnter = async (lineNum: number) => {
    setBlameHoveredLine(lineNum);

    if (blameFetchState() === "loaded" || blameFetchState() === "loading") return;

    const filePath = props.filePath;
    if (!filePath) return;

    const repoPath = props.repositoryPath;
    if (!repoPath) return;

    const cacheKey = `${repoPath}::${filePath}`;
    if (cacheKey === blameCacheKey && blameFetchState() !== "idle") return;

    blameCacheKey = cacheKey;
    setBlameFetchState("loading");

    const result = await getFileBlame(repoPath, filePath);
    if (!result.ok) {
      setBlameFetchState("error");
      return;
    }

    setBlameData(result.data.lines);
    setBlameFetchState("loaded");
  };

  const formatBlameTime = (timestamp: string): string => {
    const seconds = parseInt(timestamp, 10);
    if (isNaN(seconds)) return "";
    const date = new Date(seconds * 1000);
    const now = Date.now();
    const diffMs = now - date.getTime();
    const days = Math.floor(diffMs / 86400000);
    if (days < 1) return "today";
    if (days < 30) return `${days}d`;
    if (days < 365) return `${Math.floor(days / 30)}mo`;
    return `${Math.floor(days / 365)}y`;
  };

  let viewportElement: HTMLDivElement | undefined;
  let canvasElement: HTMLCanvasElement | undefined;
  let sessionManifest: FileDiffManifestData | null = null;
  let sessionDiffId: string | null = null;
  let sessionStartedAt = 0;
  let sessionFirstPaintMs: number | null = null;
  let sessionFlushed = false;
  let lastScrollAt = 0;
  let scrollFpsSamples: number[] = [];
  let scheduledDrawFrameId: number | null = null;
  let canvasLineCache = new Map<number, ParsedDiffLine>();

  // Cached canvas theme palette. Resolved once from getComputedStyle and reused
  // across all draw frames. Invalidated by the MutationObserver on data-theme/style
  // changes — avoids forcing a synchronous style recalc on every scroll frame.
  let canvasPalette: {
    addedFill: string; deletedFill: string; hunkFill: string;
    lineNumberFill: string; lineTextFill: string;
  } | null = null;

  // Previous canvas geometry — skip redundant style writes that trigger reflow.
  let prevCanvasW = 0;
  let prevCanvasH = 0;
  let prevCanvasTop = 0;

  const manifest = createMemo(() => props.manifest);
  const hasManifest = createMemo(() => Boolean(manifest()));
  const isIdleEmpty = createMemo(
    () => !props.filePath && !props.error && !chunkError() && !hasManifest()
  );
  const hasMoreChunks = createMemo(() => {
    const currentManifest = manifest();
    if (!currentManifest) {
      return false;
    }
    return loadedChunks().length < currentManifest.chunkCount;
  });

  const loadedDiffText = createMemo(() => loadedChunks().join(""));
  const isSearchActive = createMemo(() => searchTerm().trim().length > 0);
  const wrappedLayoutWidthPx = createMemo(() =>
    Math.max(layoutWidthPx() - CANVAS_LINE_NUMBER_GUTTER_PX - PRETEXT_TEXT_PADDING_PX, 64)
  );

  const preparedDiffText = createMemo<PreparedTextWithSegments | null>(() => {
    const diffText = loadedDiffText();
    if (diffText.length === 0) {
      return null;
    }

    return prepareWithSegments(diffText, pretextFontProfile(), {
      whiteSpace: "pre-wrap"
    });
  });

  const indexedPretextLines = createMemo<IndexedPretextLine[]>(() => {
    const prepared = preparedDiffText();
    if (!prepared) {
      return [];
    }

    const indexedLines: IndexedPretextLine[] = [];
    walkLineRanges(prepared, wrappedLayoutWidthPx(), (line: LayoutLineRange) => {
      indexedLines.push({
        number: indexedLines.length + 1,
        start: { ...line.start },
        end: { ...line.end }
      });
    });

    return indexedLines;
  });

  const shouldMaterializeAllLines = createMemo(() => mode() === "dom" || isSearchActive());

  const parsedLines = createMemo<ParsedDiffLine[]>(() => {
    const prepared = preparedDiffText();
    if (!prepared || !shouldMaterializeAllLines()) {
      return [];
    }

    return parseDiffLinesWithPretext(prepared, layoutWidthPx());
  });

  const visibleLines = createMemo(() => {
    const needle = searchTerm().trim().toLowerCase();
    if (!needle) {
      return parsedLines();
    }

    return parsedLines().filter((entry) => entry.line.toLowerCase().includes(needle));
  });

  const domVirtualWindow = createMemo<VirtualizedDomWindow>(() => {
    const lines = visibleLines();
    const totalLineCount = lines.length;
    const totalHeightPx = Math.max(totalLineCount * LINE_HEIGHT_PX, LINE_HEIGHT_PX);
    if (totalLineCount === 0) {
      return {
        items: [],
        offsetTopPx: 0,
        totalHeightPx
      };
    }

    const startIndex = Math.max(
      Math.floor(viewportScrollTop() / LINE_HEIGHT_PX) - DOM_OVERSCAN_LINES,
      0
    );
    const visibleCount =
      Math.ceil(Math.max(viewportHeightPx(), LINE_HEIGHT_PX) / LINE_HEIGHT_PX) +
      DOM_OVERSCAN_LINES * 2;
    const endIndex = Math.min(startIndex + visibleCount, totalLineCount);

    return {
      items: lines.slice(startIndex, endIndex),
      offsetTopPx: startIndex * LINE_HEIGHT_PX,
      totalHeightPx
    };
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
    const totalLineCount = isSearchActive() ? visibleLines().length : indexedPretextLines().length;
    return Math.max(totalLineCount * LINE_HEIGHT_PX, LINE_HEIGHT_PX);
  });

  function resolveIndexedCanvasLine(lineIndex: number): ParsedDiffLine | null {
    if (lineIndex < 0) {
      return null;
    }

    const cached = canvasLineCache.get(lineIndex);
    if (cached) {
      return cached;
    }

    const prepared = preparedDiffText();
    const indexedLine = indexedPretextLines()[lineIndex];
    if (!prepared || !indexedLine) {
      return null;
    }

    const materialized = layoutNextLine(prepared, indexedLine.start, wrappedLayoutWidthPx());
    if (!materialized) {
      return null;
    }

    const lineText = typeof materialized.text === "string" ? materialized.text : "";
    let lineKind: LineKind;
    if (indexedLine.start.graphemeIndex > 0) {
      lineKind = resolveIndexedCanvasLine(lineIndex - 1)?.kind ?? detectLineKind(lineText);
    } else {
      lineKind = detectLineKind(lineText);
    }

    const parsedLine: ParsedDiffLine = {
      line: lineText,
      kind: lineKind,
      number: indexedLine.number
    };
    canvasLineCache.set(lineIndex, parsedLine);
    return parsedLine;
  }

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
    requestCanvasDraw();
  }

  function requestCanvasDraw(): void {
    if (scheduledDrawFrameId !== null) {
      return;
    }

    scheduledDrawFrameId = requestAnimationFrame(() => {
      scheduledDrawFrameId = null;
      drawCanvasViewport();
    });
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

    let content = "";
    if (isSearchActive()) {
      content = visibleLines()
        .slice(startIndex, startIndex + visibleCount)
        .map((entry) => entry.line)
        .join("\n");
    } else {
      const entries: string[] = [];
      const maxLine = Math.min(startIndex + visibleCount, indexedPretextLines().length);
      for (let lineIndex = startIndex; lineIndex < maxLine; lineIndex += 1) {
        const entry = resolveIndexedCanvasLine(lineIndex);
        if (entry) {
          entries.push(entry.line);
        }
      }
      content = entries.join("\n");
    }

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

    const searchMode = isSearchActive();
    const indexedLines = indexedPretextLines();
    const searchLines = visibleLines();
    const totalLineCount = searchMode ? searchLines.length : indexedLines.length;
    if (totalLineCount === 0) {
      return;
    }

    const startLine = Math.max(
      Math.floor(viewportElement.scrollTop / LINE_HEIGHT_PX) - CANVAS_OVERSCAN_LINES,
      0
    );
    const visibleCount =
      Math.ceil(viewportElement.clientHeight / LINE_HEIGHT_PX) +
      CANVAS_OVERSCAN_LINES * 2;
    const endLine = Math.min(startLine + visibleCount, totalLineCount);
    const sliceSize = Math.max(endLine - startLine, 1);

    const pixelRatio = typeof window !== "undefined" ? window.devicePixelRatio || 1 : 1;
    const width = Math.max(viewportElement.clientWidth - 16, 320);
    const height = Math.max(sliceSize * LINE_HEIGHT_PX, LINE_HEIGHT_PX);

    const canvasW = Math.floor(width * pixelRatio);
    const canvasH = Math.floor(height * pixelRatio);
    const canvasTop = startLine * LINE_HEIGHT_PX;

    // Only write canvas dimensions/position when they actually change.
    // Each write triggers a reflow; during smooth scrolling the width rarely changes.
    if (canvasW !== prevCanvasW || canvasH !== prevCanvasH) {
      canvasElement.width = canvasW;
      canvasElement.height = canvasH;
      canvasElement.style.width = `${width}px`;
      canvasElement.style.height = `${height}px`;
      prevCanvasW = canvasW;
      prevCanvasH = canvasH;
    }
    if (canvasTop !== prevCanvasTop) {
      canvasElement.style.top = `${canvasTop}px`;
      prevCanvasTop = canvasTop;
    }

    const context = canvasElement.getContext("2d");
    if (!context) {
      return;
    }

    context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    context.clearRect(0, 0, width, height);
    context.font = pretextFontProfile();
    context.textBaseline = "middle";

    // Resolve theme palette from cache. Only call getComputedStyle when the
    // cache is cold (first draw or after a theme/style change via MutationObserver).
    if (!canvasPalette) {
      const rootStyles = getComputedStyle(document.documentElement);
      const hypercubePositive = rootStyles.getPropertyValue("--hypercube-positive");
      const hypercubeNegative = rootStyles.getPropertyValue("--hypercube-negative");
      canvasPalette = {
        addedFill: withAlpha(hypercubePositive, 0.16),
        deletedFill: withAlpha(hypercubeNegative, 0.16),
        hunkFill: withAlpha(hypercubePositive, 0.1),
        lineNumberFill: withAlpha(rootStyles.getPropertyValue("--text-muted"), 0.76),
        lineTextFill: withAlpha(rootStyles.getPropertyValue("--text-strong"), 0.94),
      };
    }
    const { addedFill, deletedFill, hunkFill, lineNumberFill, lineTextFill } = canvasPalette;

    for (let index = 0; index < sliceSize; index += 1) {
      const lineIndex = startLine + index;
      const entry = searchMode
        ? searchLines[lineIndex]
        : resolveIndexedCanvasLine(lineIndex);
      if (!entry) {
        continue;
      }
      const y = index * LINE_HEIGHT_PX;

      if (entry.kind === "added") {
        context.fillStyle = addedFill;
        context.fillRect(0, y, width, LINE_HEIGHT_PX);
      } else if (entry.kind === "deleted") {
        context.fillStyle = deletedFill;
        context.fillRect(0, y, width, LINE_HEIGHT_PX);
      } else if (entry.kind === "hunk") {
        context.fillStyle = hunkFill;
        context.fillRect(0, y, width, LINE_HEIGHT_PX);
      }

      context.fillStyle = lineNumberFill;
      context.fillText(String(entry.number), 6, y + LINE_HEIGHT_PX / 2);

      context.fillStyle = lineTextFill;
      context.fillText(entry.line || " ", CANVAS_LINE_NUMBER_GUTTER_PX, y + LINE_HEIGHT_PX / 2);
    }
  }

  function onViewportScroll(): void {
    if (!viewportElement) {
      return;
    }

    setViewportScrollTop(viewportElement.scrollTop);

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

    requestCanvasDraw();
  }

  createEffect(() => {
    const currentManifest = manifest();
    const currentDiffId = currentManifest?.diffId ?? null;

    if (sessionDiffId === currentDiffId) {
      return;
    }

    if (sessionManifest && sessionManifest.diffId !== currentDiffId) {
      flushRenderMetrics(sessionManifest);
    }

    sessionDiffId = currentDiffId;
    sessionManifest = currentManifest ?? null;
    sessionStartedAt = performance.now();
    sessionFirstPaintMs = null;
    sessionFlushed = false;
    lastScrollAt = 0;
    scrollFpsSamples = [];
    setViewportScrollTop(0);
    setSearchTerm("");
    setChunkError(null);
    setCopyMessage(null);
    setBlameData(null);
    setBlameFetchState("idle");
    blameCacheKey = "";

    if (!currentManifest) {
      setLoadedChunks([]);
      return;
    }

    setLoadedChunks([currentManifest.initialChunkText]);

    // Persist user's manual mode choice across diffs if present, otherwise follow manifest recommendation
    const userPref = getPersistedRenderMode();
    if (!userPref) {
      setMode(resolveInitialMode(currentManifest));
    }

    if (viewportElement) {
      viewportElement.scrollTop = 0;
    }
  });

  createEffect(() => {
    preparedDiffText();
    wrappedLayoutWidthPx();
    indexedPretextLines();
    canvasLineCache.clear();
  });

  createEffect(() => {
    const lineCount = parsedLines().length;
    const pretextLineCount = indexedPretextLines().length;
    const measuredLineCount = shouldMaterializeAllLines() ? lineCount : pretextLineCount;
    if (!manifest() || measuredLineCount === 0 || sessionFirstPaintMs !== null) {
      return;
    }

    requestAnimationFrame(() => {
      const currentLineCount = shouldMaterializeAllLines()
        ? parsedLines().length
        : indexedPretextLines().length;
      if (!manifest() || currentLineCount === 0 || sessionFirstPaintMs !== null) {
        return;
      }
      sessionFirstPaintMs = Math.max(performance.now() - sessionStartedAt, 0);
    });
  });

  createEffect(() => {
    mode();
    visibleLines();
    indexedPretextLines();
    requestCanvasDraw();
  });

  onMount(() => {
    if (!viewportElement) {
      return;
    }

    setPretextFontProfile(resolvePretextFontProfile(viewportElement));
    setLayoutWidthPx(Math.max(viewportElement.clientWidth, 320));
    setViewportHeightPx(Math.max(viewportElement.clientHeight, LINE_HEIGHT_PX));

    let resizeObserver: ResizeObserver | undefined;
    if (typeof ResizeObserver !== "undefined") {
      resizeObserver = new ResizeObserver(() => {
        if (viewportElement) {
          setPretextFontProfile(resolvePretextFontProfile(viewportElement));
          setLayoutWidthPx(Math.max(viewportElement.clientWidth, 320));
          setViewportHeightPx(Math.max(viewportElement.clientHeight, LINE_HEIGHT_PX));
        }
        requestCanvasDraw();
      });
      resizeObserver.observe(viewportElement);
    }

    let themeObserver: MutationObserver | undefined;
    if (typeof MutationObserver !== "undefined") {
      themeObserver = new MutationObserver(() => {
        // Invalidate cached theme colors so the next draw frame re-resolves them.
        canvasPalette = null;
        if (viewportElement) {
          setPretextFontProfile(resolvePretextFontProfile(viewportElement));
        }
        requestCanvasDraw();
      });
      themeObserver.observe(document.documentElement, {
        attributes: true,
        attributeFilter: ["data-theme", "style"]
      });
    }

    onCleanup(() => {
      resizeObserver?.disconnect();
      themeObserver?.disconnect();
      if (scheduledDrawFrameId !== null) {
        cancelAnimationFrame(scheduledDrawFrameId);
        scheduledDrawFrameId = null;
      }
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
            onClick={() => {
              setMode("dom");
              persistRenderMode("dom");
            }}
            disabled={!hasManifest()}
          >
            DOM
          </button>
          <button
            class={`mode-toggle ${mode() === "canvas" ? "is-active" : ""}`}
            onClick={() => {
              setMode("canvas");
              persistRenderMode("canvas");
            }}
            disabled={!hasManifest()}
          >
            Canvas
          </button>

          <Show when={mode() === "canvas" && (isSearchActive() ? visibleLines().length : indexedPretextLines().length) > 0}>
            <button class="mode-toggle" onClick={() => void copyVisibleCanvasLines()}>
              Copy Visible
            </button>
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

      <div class="diff-viewport-container">
        <Show when={hunkJumpTargets().length > 0}>
          <div class="diff-hunk-rail-container">
            <div class="diff-hunk-rail">
              {hunkJumpTargets().map((target) => {
                const totalHeight = mode() === "canvas" ? canvasVirtualHeight() : domVirtualWindow().totalHeightPx;
                const relativeY = ((target.lineNumber - 1) * LINE_HEIGHT_PX) / Math.max(totalHeight, 1);
                
                // Active/Lens Influence Logic
                // We use the viewport scroll position to determine which nodes are high-intensity
                const viewportCenterY = (viewportScrollTop() + viewportHeightPx() / 2) / Math.max(totalHeight, 1);
                const distance = Math.abs(relativeY - viewportCenterY);
                const lensRadius = 0.15; // Influence radius in percent of total height
                const influence = Math.exp(-8 * Math.pow(distance / lensRadius, 2));

                return (
                  <button
                    class="hunk-node"
                    style={{
                      top: `${relativeY * 100}%`,
                      transform: `translate(-50%, -50%) scale(${1 + influence * 1.2})`,
                      opacity: 0.2 + influence * 0.8
                    }}
                    onClick={() => jumpToLine(target.lineNumber)}
                    title={target.label}
                  >
                    <div class="hunk-node-pulse" style={{ opacity: influence }} />
                  </button>
                );
              })}
              <div 
                class="diff-hunk-rail-active-marker" 
                style={{ 
                  top: `${(viewportScrollTop() / Math.max(mode() === "canvas" ? canvasVirtualHeight() : domVirtualWindow().totalHeightPx, 1)) * 100}%`,
                  height: `${(viewportHeightPx() / Math.max(mode() === "canvas" ? canvasVirtualHeight() : domVirtualWindow().totalHeightPx, 1)) * 100}%`
                }} 
              />
            </div>
          </div>
        </Show>

        <div
          class="diff-viewport"
          ref={(element) => {
            viewportElement = element;
          }}
          onScroll={onViewportScroll}
        >
        <Show when={props.error}>
          <div class="diff-viewport-dom">{props.error}</div>
        </Show>

        <Show when={!props.error && chunkError()}>
          {(errorMessage) => <div class="diff-viewport-dom">{errorMessage()}</div>}
        </Show>

        <Show when={!props.error && !chunkError() && !manifest()}>
          <div class="diff-viewport-dom">Select a changed file to view its diff.</div>
        </Show>

        <Show when={!props.error && !chunkError() && manifest()}>
          <Show
            when={
              (mode() === "canvas"
                ? (isSearchActive() ? visibleLines().length : indexedPretextLines().length)
                : parsedLines().length) > 0 || hasMoreChunks()
            }
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
                <div class="diff-viewport-virtual" style={{ height: `${domVirtualWindow().totalHeightPx}px` }}>
                  <div
                    class="diff-viewport-virtual-slice"
                    style={{ transform: `translateY(${domVirtualWindow().offsetTopPx}px)` }}
                  >
                    {domVirtualWindow().items.map((entry) => {
                      const blame = () => blameHoveredLine() === entry.number ? blameForLine(entry.number) : undefined;
                      return (
                        <div class={`diff-line diff-line-${entry.kind}`}>
                          <span
                            class="diff-line-number"
                            onPointerEnter={() => void onGutterPointerEnter(entry.number)}
                            onPointerLeave={() => setBlameHoveredLine(null)}
                          >
                            {entry.number}
                          </span>
                          <Show when={blame()}>
                            {(b) => (
                              <span class="blame-annotation" style="position: absolute; left: 0; top: 0; height: 18px; display: flex; align-items: center; gap: 4px; padding: 0 6px; font-size: 10px; color: var(--text-muted); background: var(--surface-1); border-right: 1px solid rgba(var(--chrome-border-rgb), 0.15); z-index: 5; white-space: nowrap; animation: blame-fade-in 150ms ease; pointer-events: auto;">
                                <span style="width: 16px; height: 16px; border-radius: 50%; background: rgba(var(--accent-rgb), 0.12); display: flex; align-items: center; justify-content: center; font-size: 8px; font-weight: 700; color: var(--accent-bright); flex-shrink: 0;">
                                  {b().authorName.charAt(0).toUpperCase()}
                                </span>
                                <span style="font-family: var(--font-mono); opacity: 0.7; cursor: pointer;" title={`View commit ${b().commitHash}`}>
                                  {b().shortHash}
                                </span>
                                <span style="opacity: 0.5;">{formatBlameTime(b().authoredAt)}</span>
                              </span>
                            )}
                          </Show>
                          <span class="diff-line-text">{entry.line || " "}</span>
                        </div>
                      );
                    })}
                  </div>
                </div>
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
      </div>

      <Show when={copyMessage()}>
        {(message) => <p class="diff-copy-status">{message()}</p>}
      </Show>
    </section>
  );
}
