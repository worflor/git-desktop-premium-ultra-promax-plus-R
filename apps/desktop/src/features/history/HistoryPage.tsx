import { For, createEffect, createMemo, createSignal, onCleanup, onMount, Show } from "solid-js";
import { createStore } from "solid-js/store";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import type { CommitDetailData, CommitHistoryData, CommitHistoryEntry } from "@/lib/backend/dtos";
import { getCommitDetail, listCommitHistory } from "@/lib/backend/commands";
import { recordUiTiming } from "@/lib/telemetry/uiTiming";
import { formatCommitDate, formatFullDate, useDateFormatPreference } from "@/lib/ui/date";

interface HistoryPageProps {
  embedded?: boolean;
}

interface GraphNode extends CommitHistoryEntry {
  row: number;
  lane: number;
  visibleParents: string[];
  visibleChildren: string[];
}

interface GraphEdge {
  fromHash: string;
  toHash: string;
  fromRow: number;
  toRow: number;
  fromLane: number;
  toLane: number;
}

interface GraphLayout {
  nodes: GraphNode[];
  edges: GraphEdge[];
  laneCount: number;
  hashToNode: Map<string, GraphNode>;
}

interface LensNodeMetric {
  centerPercent: number;
  shiftPx: number;
  scale: number;
  x: number;
  y: number;
}

const HISTORY_CACHE_TTL_MS = 1500;

interface HistoryCacheEntry {
  capturedAt: number;
  data: CommitHistoryData;
}

const historyCache = new Map<string, HistoryCacheEntry>();
const [commitDetailStore, setCommitDetailStore] = createStore<Record<string, CommitDetailData>>({});
const pendingHistoryRequests = new Map<string, Promise<void>>();
const pendingCommitDetailRequests = new Map<string, Promise<void>>();

function getCachedHistoryEntry(cacheKey: string): HistoryCacheEntry | null {
  const cached = historyCache.get(cacheKey);
  if (!cached) {
    return null;
  }

  if (Date.now() - cached.capturedAt > HISTORY_CACHE_TTL_MS) {
    historyCache.delete(cacheKey);
    return null;
  }

  return cached;
}

function CommitTime(props: { isoString: string; style?: string; class?: string; readOnly?: boolean }) {
  const [globalFormat, setGlobalFormat] = useDateFormatPreference();

  const toggle = (e: MouseEvent) => {
    if (props.readOnly) return;
    e.preventDefault();
    e.stopPropagation();
    setGlobalFormat(globalFormat() === "relative" ? "absolute" : "relative");
  };

  return (
    <span
      style={`${props.readOnly ? "" : "cursor: pointer;"} user-select: none; ${props.style || ""}`}
      class={props.class}
      onClick={toggle}
      title={formatFullDate(props.isoString)}
    >
      {formatCommitDate(props.isoString, globalFormat())}
    </span>
  );
}

function CommitImpact(props: { hash: string; repoPath: string | null }) {
  const cacheKey = () => props.repoPath ? `${props.repoPath}::${props.hash}` : null;
  const detail = createMemo(() => {
    const key = cacheKey();
    return key ? commitDetailStore[key] : undefined;
  });

  return (
    <Show
      when={detail()}
      fallback={
        <div style="display: flex; gap: 2px; opacity: 0.2; align-items: center;">
          {[...Array(5)].map(() => (
            <div style="width: 6px; height: 3px; background: var(--text-muted); border-radius: 1px;" />
          ))}
        </div>
      }
    >
      {(data) => {
        const additions = data().additions;
        const deletions = data().deletions;
        const total = additions + deletions;
        if (total === 0) return null;

        const addRatio = additions / total;
        const blocks = 5;
        const addBlocks = Math.round(addRatio * blocks);


        return (
          <div
            style="display: flex; align-items: center; gap: 6px;"
            title={`${data().filesChanged} files: +${additions} -${deletions}`}
          >
            <div style="display: flex; gap: 2px; align-items: center; font-size: 9px; font-family: var(--font-mono); font-weight: 700;">
              <span style="color: var(--state-added); opacity: 0.9;">{additions}</span>
              <span style="opacity: 0.3;">/</span>
              <span style="color: var(--state-deleted); opacity: 0.9;">{deletions}</span>
            </div>
            <div
              style={`display: flex; gap: 1.5px; padding: 1px; border-radius: 2px; background: rgba(var(--chrome-border-rgb), 0.05); border: 0.5px solid rgba(var(--chrome-border-rgb), 0.1);`}
            >
              {[...Array(blocks)].map((_, i) => {
                const isAdd = i < addBlocks;
                return (
                  <div
                    style={`width: 6px; height: 3px; border-radius: 0.5px; background: ${isAdd ? "var(--state-added)" : "var(--state-deleted)"}; opacity: 0.75; transition: all 0.3s ease;`}
                  />
                );
              })}
            </div>
          </div>
        );
      }}
    </Show>
  );
}

function buildGraphLayout(entries: CommitHistoryEntry[]): GraphLayout {
  const visibleHashes = new Set(entries.map((entry) => entry.commitHash));
  const activeLanes: Array<string | null> = [];
  const hashToNode = new Map<string, GraphNode>();
  const hashToLane = new Map<string, number>();
  const hashToRow = new Map<string, number>();
  const childrenMap = new Map<string, string[]>();
  let laneCount = 1;

  const reserveLaneForHash = (hash: string, preferredLane?: number) => {
    const existingLane = activeLanes.findIndex((laneHash) => laneHash === hash);
    if (existingLane >= 0) {
      return existingLane;
    }

    if (typeof preferredLane === "number" && activeLanes[preferredLane] == null) {
      activeLanes[preferredLane] = hash;
      return preferredLane;
    }

    const emptyLane = activeLanes.findIndex((laneHash) => laneHash == null);
    if (emptyLane >= 0) {
      activeLanes[emptyLane] = hash;
      return emptyLane;
    }

    activeLanes.push(hash);
    return activeLanes.length - 1;
  };

  const nodes: GraphNode[] = entries.map((entry, row) => {
    let lane = activeLanes.findIndex((laneHash) => laneHash === entry.commitHash);
    if (lane < 0) {
      lane = reserveLaneForHash(entry.commitHash);
    }

    activeLanes[lane] = null;

    const visibleParents = entry.parentHashes.filter((hash) => visibleHashes.has(hash));
    const [primaryParent, ...secondaryParents] = visibleParents;

    if (primaryParent) {
      reserveLaneForHash(primaryParent, lane);
    }

    secondaryParents.forEach((parentHash) => {
      reserveLaneForHash(parentHash);
    });

    while (activeLanes.length > 0 && activeLanes[activeLanes.length - 1] == null) {
      activeLanes.pop();
    }

    laneCount = Math.max(laneCount, lane + 1, activeLanes.length);
    hashToLane.set(entry.commitHash, lane);
    hashToRow.set(entry.commitHash, row);

    const node: GraphNode = {
      ...entry,
      row,
      lane,
      visibleParents,
      visibleChildren: [] // Will be populated in the next pass
    };

    hashToNode.set(entry.commitHash, node);
    return node;
  });

  // Second pass: Populate visibleChildren and edges
  const edges: GraphEdge[] = [];
  nodes.forEach((node) => {
    node.visibleParents.forEach((parentHash) => {
      // Connect neighbors in the child map
      const children = childrenMap.get(parentHash) || [];
      if (!children.includes(node.commitHash)) {
        children.push(node.commitHash);
        childrenMap.set(parentHash, children);
      }

      const parentNode = hashToNode.get(parentHash);
      if (parentNode) {
        edges.push({
          fromHash: node.commitHash,
          toHash: parentHash,
          fromRow: node.row,
          toRow: parentNode.row,
          fromLane: node.lane,
          toLane: parentNode.lane
        });
      }
    });
  });

  // Final pass: Back-hydrate nodes with their children
  nodes.forEach((node) => {
    node.visibleChildren = childrenMap.get(node.commitHash) || [];
  });

  return { nodes, edges, laneCount, hashToNode };
}

function computeTimelineBasePercents(
  entries: CommitHistoryEntry[],
  timelineConfig: { GAP_LOG_FACTOR: number; TEMPORAL_BLEND: number }
): number[] {
  const count = entries.length;
  if (count === 0) return [];
  if (count === 1) return [50];

  const evenPercents = entries.map((_, index) => (index / (count - 1)) * 100);
  const timestampValues = entries.map((entry) => {
    const parsed = Date.parse(entry.authoredAt || "");
    return Number.isNaN(parsed) ? Date.now() : parsed;
  });

  const rawGaps = timestampValues.slice(0, -1).map((value, index) => {
    const nextValue = timestampValues[index + 1] ?? Number.NaN;
    if (!Number.isFinite(value) || !Number.isFinite(nextValue)) return 1;
    return Math.max(1, Math.abs(value - nextValue));
  });

  const medianGap = [...rawGaps].sort((a, b) => a - b)[Math.floor(rawGaps.length / 2)] || 60000;
  const weightedGaps = rawGaps.map((gap) => {
    return Math.max(0.4, Math.min(12, 1 + Math.log1p(gap / medianGap) * timelineConfig.GAP_LOG_FACTOR));
  });

  const totalWeight = weightedGaps.reduce((acc, weight) => acc + weight, 0);
  const timePercents: number[] = [0];
  let cursor = 0;
  for (const weight of weightedGaps) {
    cursor += (weight / (totalWeight || 1)) * 100;
    timePercents.push(cursor);
  }

  const finalPercents = evenPercents.map((even, index) => {
    const timed = timePercents[index] ?? even;
    return even * (1 - timelineConfig.TEMPORAL_BLEND) + timed * timelineConfig.TEMPORAL_BLEND;
  });

  const min = Math.min(...finalPercents);
  const max = Math.max(...finalPercents);
  const range = max - min;
  return finalPercents.map((percent) => (range > 0 ? ((percent - min) / range) * 100 : percent));
}

export function HistoryPage(props: HistoryPageProps = {}) {
  const mountedAt = performance.now();
  const repository = useRepositoryContext();
  const [historyLimitInput, setHistoryLimitInput] = createSignal("50");
  const [selectedCommitHash, setSelectedCommitHash] = createSignal<string | null>(null);
  const [historyData, setHistoryData] = createSignal<CommitHistoryData | null>(null);
  const [historyError, setHistoryError] = createSignal<string | null>(null);
  const [commitDetailData, setCommitDetailData] = createSignal<CommitDetailData | null>(null);
  const [commitDetailError, setCommitDetailError] = createSignal<string | null>(null);
  const [historyRepositoryPath, setHistoryRepositoryPath] = createSignal<string | null>(null);
  const [overviewWidth, setOverviewWidth] = createSignal(0);
  const [hoverLensX, setHoverLensX] = createSignal<number | null>(null);
  const [isScrubbing, setIsScrubbing] = createSignal(false);
  const [hoveredCommitHash, setHoveredCommitHash] = createSignal<string | null>(null);
  let overviewContainer: HTMLDivElement | undefined;
  let previousRepositoryPath: string | null | undefined;

  const activeRepo = () => repository.activeRepositoryPath();
  const commitDetailCacheKey = (repositoryPath: string, commitHash: string) =>
    `${repositoryPath}::${commitHash}`;

  const parsedLimit = () => {
    const parsed = Number.parseInt(historyLimitInput().trim(), 10);
    if (Number.isNaN(parsed)) {
      return 50;
    }
    return Math.min(Math.max(parsed, 1), 500);
  };

  const overviewEntries = createMemo(() => {
    const history = historyData();
    return history && historyRepositoryPath() === activeRepo() ? history.entries : [];
  });

  const overviewGraph = createMemo(() => buildGraphLayout(overviewEntries()));
  const overviewHeight = createMemo(() => Math.max(42, overviewGraph().laneCount * 14 + 18));
  const overviewLaneStep = createMemo(() => (overviewHeight() - 16) / Math.max(overviewGraph().laneCount, 1));
  const effectiveOverviewWidth = createMemo(() => {
    const w = overviewWidth();
    return w > 1 ? w : (overviewContainer?.getBoundingClientRect().width ?? 600);
  });
  // ─── Timeline Architecture Standards ──────────────────────────────
  const TIMELINE_CONFIG = {
    INSET_PX: 4,             // Node-box inset so endpoints sit flush with the rail
    LENS_RADIUS_MIN: 32,    // Minimum influence radius
    LENS_RADIUS_MAX: 64,    // Maximum influence radius
    MAX_SHIFT_PX: 10,       // Maximum displacement at lens boundary
    TEMPORAL_BLEND: 0.32,    // Ratio of time-linear vs even-distribution (lower = more visually balanced)
    SCALE_FOCUS: 0.45,      // Magnification power at dead center
    SCALE_SELECTED: 1.25,   // Multiplier for active commit
    SCALE_HOVER: 1.1,       // Multiplier for mouse hover
    GAP_LOG_FACTOR: 1.1,    // Exponential expansion of long time-gaps
    MIN_LANE_HEIGHT: 42     // Vertical spacing for branch topology
  } as const;
  const timelineBasePercents = createMemo<number[]>(() => computeTimelineBasePercents(overviewEntries(), TIMELINE_CONFIG));
  const projectedTimelineBaseXs = createMemo<number[]>(() => {
    const nodes = overviewGraph().nodes;
    const width = effectiveOverviewWidth();
    if (nodes.length === 0) return [];
    if (nodes.length === 1) return [width * 0.5];

    const { INSET_PX } = TIMELINE_CONFIG;
    const percents = timelineBasePercents();
    const usableWidth = Math.max(0, width - INSET_PX * 2);
    const rawBasePositions = nodes.map((_, index) => {
      const centerPercent = percents[index] ?? 50;
      return (centerPercent / 100) * usableWidth;
    });
    const minBaseX = Math.min(...rawBasePositions);
    const maxBaseX = Math.max(...rawBasePositions);
    const baseRange = Math.max(maxBaseX - minBaseX, 1);

    return rawBasePositions.map((rawBaseX) => INSET_PX + ((rawBaseX - minBaseX) / baseRange) * usableWidth);
  });

  const hoveredNodeCenterPx = createMemo(() => {
    const hash = hoveredCommitHash();
    if (!hash) return null;
    const nodes = overviewGraph().nodes;
    const index = nodes.findIndex((n) => n.commitHash === hash);
    if (index === -1) return null;
    return projectedTimelineBaseXs()[index] ?? null;
  });

  const lensFocusPx = createMemo(() => {
    const x = hoverLensX();
    if (x !== null) return x;
    const hovered = hoveredNodeCenterPx();
    if (hovered !== null) return hovered;
    return effectiveOverviewWidth() * 0.5;
  });


  /**
   * Final projection stage: Maps normalized percents to physical pixel coordinates.
   * Incorporates the kinetic magnification lens and boundary damping.
   */
  const lensMetrics = createMemo<LensNodeMetric[]>(() => {
    const nodes = overviewGraph().nodes;
    const width = effectiveOverviewWidth();
    const focusPx = lensFocusPx();
    if (nodes.length === 0) return [];

    const { SCALE_FOCUS, SCALE_SELECTED, SCALE_HOVER } = TIMELINE_CONFIG;
    const laneStep = overviewLaneStep();
    const laneCenterOffset = laneStep / 2;

    if (nodes.length === 1) {
      return [{
        centerPercent: 50, shiftPx: 0,
        scale: (selectedCommitHash() === nodes[0]!.commitHash ? SCALE_SELECTED : 1),
        x: width * 0.5, y: 8 + laneCenterOffset
      }];
    }

    const spacingPx = width / Math.max(nodes.length - 1, 1);
    const lensRadiusPx = Math.max(TIMELINE_CONFIG.LENS_RADIUS_MIN, Math.min(TIMELINE_CONFIG.LENS_RADIUS_MAX, spacingPx * 2.8));

    const influenceAt = (distancePx: number) => {
      // Gaussian distribution for luxury magnification feel
      const normalized = Math.min(distancePx / lensRadiusPx, 1);
      return Math.exp(-4 * normalized * normalized) * (1 - normalized * normalized);
    };

    const baseXs = projectedTimelineBaseXs();
    const percents = timelineBasePercents();

    return nodes.map((node, index) => {
      const centerPercent = percents[index] ?? 50;
      const baseCenterPx = baseXs[index] ?? width * 0.5;
      const deltaPx = baseCenterPx - focusPx;
      const focusGain = influenceAt(Math.abs(deltaPx));

      const isSelected = selectedCommitHash() === node.commitHash;
      const isHovered = hoveredCommitHash() === node.commitHash;

      let scale = 1 + focusGain * SCALE_FOCUS;
      if (isSelected) scale *= SCALE_SELECTED;
      if (isHovered) scale *= SCALE_HOVER;
      if (node.isMerge) scale *= 1.05;

      return {
        centerPercent,
        shiftPx: 0,
        scale,
        x: baseCenterPx,
        y: 8 + node.lane * laneStep + laneCenterOffset
      };
    });
  });

  const lensMetricsMap = createMemo(() => {
    const metrics = lensMetrics();
    const map = new Map<string, LensNodeMetric>();
    const entries = overviewEntries();
    // High-performance mapping pass
    for (let i = 0; i < entries.length; i++) {
      const m = metrics[i];
      if (m) map.set(entries[i]!.commitHash, m);
    }
    return map;
  });

  const resolveOverviewOffsetX = (clientX: number) => {
    const container = overviewContainer;
    if (!container) {
      return null;
    }

    const rect = container.getBoundingClientRect();
    return Math.min(Math.max(clientX - rect.left, 0), rect.width);
  };

  const resolveNearestOverviewNode = (offsetX: number) => {
    const container = overviewContainer;
    const nodes = overviewGraph().nodes;
    const metrics = lensMetrics();
    if (!container || nodes.length === 0 || metrics.length === 0) {
      return null;
    }

    let nearestIndex = 0;
    let nearestDistance = Number.POSITIVE_INFINITY;
    metrics.forEach((metric, index) => {
      const distance = Math.abs(metric.x - offsetX);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    });
    return {
      node: nodes[Math.min(nodes.length - 1, Math.max(0, nearestIndex))],
      offsetX
    };
  };

  const updateScrubTarget = (clientX: number, commitOnScrub: boolean) => {
    const offsetX = resolveOverviewOffsetX(clientX);
    if (offsetX === null) {
      return;
    }

    setHoverLensX(offsetX);
    const resolved = resolveNearestOverviewNode(offsetX);
    if (resolved?.node) {
      setHoveredCommitHash(resolved.node.commitHash);
      if (commitOnScrub) {
        setSelectedCommitHash(resolved.node.commitHash);
      }
    }
  };

  const loadHistory = async (repositoryPath: string, limit: number) => {
    const cacheKey = `${repositoryPath}::${limit}`;
    const cached = getCachedHistoryEntry(cacheKey);
    if (cached) {
      setHistoryData(cached.data);
      setHistoryRepositoryPath(repositoryPath);
      setHistoryError(null);
      return;
    }

    const pending = pendingHistoryRequests.get(cacheKey);
    if (pending) {
      await pending;
      return;
    }

    const request = (async () => {
      const result = await listCommitHistory(repositoryPath, limit);
      if (!result.ok) {
        if (!cached) {
          setHistoryError(result.error.message);
          setHistoryData(null);
        }
        return;
      }

      historyCache.set(cacheKey, {
        capturedAt: Date.now(),
        data: result.data
      });
      if (activeRepo() === repositoryPath && parsedLimit() === limit) {
        setHistoryData(result.data);
        setHistoryRepositoryPath(repositoryPath);
        setHistoryError(null);
      }
    })();

    pendingHistoryRequests.set(cacheKey, request);
    try {
      await request;
    } finally {
      pendingHistoryRequests.delete(cacheKey);
    }
  };

  const loadCommitDetail = async (repositoryPath: string, commitHash: string, retainCurrent = true) => {
    const cacheKey = commitDetailCacheKey(repositoryPath, commitHash);
    const cached = commitDetailStore[cacheKey];
    if (cached) {
      setCommitDetailData(cached);
      setCommitDetailError(null);
      return;
    }

    if (!retainCurrent) {
      setCommitDetailData(null);
    }

    setCommitDetailError(null);
    const pending = pendingCommitDetailRequests.get(cacheKey);
    if (pending) {
      await pending;
      return;
    }

    const request = (async () => {
      const result = await getCommitDetail(repositoryPath, commitHash);
      if (!result.ok) {
        if (!commitDetailData() || !retainCurrent) {
          setCommitDetailError(result.error.message);
        }
        return;
      }

      setCommitDetailStore(cacheKey, result.data);
      if (activeRepo() === repositoryPath && selectedCommitHash() === commitHash) {
        setCommitDetailData(result.data);
        setCommitDetailError(null);
      }
    })();

    pendingCommitDetailRequests.set(cacheKey, request);
    try {
      await request;
    } finally {
      pendingCommitDetailRequests.delete(cacheKey);
    }
  };

  createEffect(() => {
    const container = overviewContainer;
    if (!container || typeof ResizeObserver === "undefined") {
      return;
    }

    const observer = new ResizeObserver((entries) => {
      const width = entries[0]?.contentRect.width ?? container.clientWidth;
      setOverviewWidth(width);
    });
    observer.observe(container);
    setOverviewWidth(container.clientWidth);
    onCleanup(() => observer.disconnect());
  });

  createEffect(() => {
    const repositoryPath = activeRepo();
    if (previousRepositoryPath !== repositoryPath) {
      previousRepositoryPath = repositoryPath;
      setSelectedCommitHash(null);
      setHoveredCommitHash(null);
      setHistoryData(null);
      setHistoryRepositoryPath(null);
      setHistoryError(null);
      setCommitDetailData(null);
      setCommitDetailError(null);
    }

    const limit = parsedLimit();
    if (!repositoryPath) {
      return;
    }

    const cached = getCachedHistoryEntry(`${repositoryPath}::${limit}`);
    if (cached) {
      setHistoryData(cached.data);
      setHistoryRepositoryPath(repositoryPath);
      setHistoryError(null);
      return;
    }

    void loadHistory(repositoryPath, limit);
  });

  createEffect(() => {
    if (historyRepositoryPath() !== activeRepo()) {
      return;
    }

    const history = historyData();
    if (!history || history.entries.length === 0) {
      return;
    }

    const firstEntry = history.entries[0];
    if (!firstEntry) {
      return;
    }

    const selected = selectedCommitHash();
    if (!selected) {
      setSelectedCommitHash(firstEntry.commitHash);
      return;
    }

    const stillExists = history.entries.some((entry) => entry.commitHash === selected);
    if (!stillExists) {
      setSelectedCommitHash(firstEntry.commitHash);
    }
  });

  createEffect(() => {
    const repositoryPath = activeRepo();
    const commitHash = selectedCommitHash();
    if (!repositoryPath || !commitHash) {
      return;
    }

    void loadCommitDetail(repositoryPath, commitHash);
  });

  onMount(() => {
    const handlePointerUp = () => {
      setIsScrubbing(false);
    };

    window.addEventListener("pointerup", handlePointerUp);
    requestAnimationFrame(() => {
      recordUiTiming({
        event: "history.page.first-paint",
        phase: "mount",
        durationMs: performance.now() - mountedAt
      });
    });
    onCleanup(() => window.removeEventListener("pointerup", handlePointerUp));
  });

  return (
    <div
      class={`feature-page ${props.embedded ? "is-embedded" : ""}`}
      style="display: flex; flex-direction: column; height: 100%; overflow: hidden; gap: 0;"
    >
      <Show when={!activeRepo()}>
        <div style="padding: 16px; width: 100%; display: flex; align-items: center; justify-content: center;">
          <EmptyStateCard
            title="No repository selected"
            body="Add or open a repository from Projects to browse commit history."
          />
        </div>
      </Show>

      <Show when={historyError()}>
        <div style="padding: 16px;">
          <ErrorStateCard title="History lookup failed" body={historyError() ?? "Unknown error"} />
        </div>
      </Show>

      <Show when={historyData() && historyData()!.entries.length === 0}>
        <div style="padding: 16px; display: flex; justify-content: center;">
          <EmptyStateCard
            title="No commits found"
            body="The selected repository has no visible commits in this range."
          />
        </div>
      </Show>

      <Show when={historyData() && historyData()!.entries.length > 0}>
        <div
          style="padding: 8px 12px; background: var(--surface-1); border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.15); display: flex; align-items: center; gap: 10px; flex-shrink: 0;"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="12"
            height="12"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="icon"
            style="color: var(--text-muted);"
          >
            <circle cx="12" cy="12" r="10"></circle>
            <polyline points="12 6 12 12 16 14"></polyline>
          </svg>
          <label
            style="display: inline-flex; align-items: center; gap: 6px; font-size: 11px; color: var(--text-muted);"
          >
            <span>Viewing last</span>
            <input
              class="path-input history-limit-input"
              style="width: 56px; padding: 2px 8px; font-size: 11px; min-height: 22px; border-radius: 6px; text-align: center;"
              value={historyLimitInput()}
              onInput={(event) => setHistoryLimitInput(event.currentTarget.value)}
              aria-label="History limit"
              inputMode="numeric"
            />
            <span>commits</span>
          </label>
        </div>

        <section
          class="topology-canvas"
          style="margin: 0; padding: 0; border: none; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.1); background: var(--surface-0); flex-shrink: 0; border-radius: 0; overflow: hidden;"
        >
          <div
            class="history-topology-strip"
            style={`height: ${overviewHeight() + 16}px; padding: 8px 16px; box-sizing: border-box;`}
          >
            <div
              ref={overviewContainer}
              class="history-topology-track"
              onPointerEnter={(event) => {
                updateScrubTarget(event.clientX, false);
              }}
              onPointerDown={(event) => {
                event.currentTarget.setPointerCapture(event.pointerId);
                setIsScrubbing(true);
                updateScrubTarget(event.clientX, true);
              }}
              onMouseMove={(event) => {
                // Mousemove is used for fine-grained coordinate scrubbing
                updateScrubTarget(event.clientX, isScrubbing());
              }}
              onPointerUp={(event) => {
                event.currentTarget.releasePointerCapture(event.pointerId);
                setIsScrubbing(false);
              }}
              onPointerLeave={() => {
                if (!isScrubbing()) {
                  setHoverLensX(null);
                  setHoveredCommitHash(null);
                }
              }}
            >
              <div
                class="history-topology-rail"
                style={{
                  top: `${8 + overviewLaneStep() / 2}px`
                }}
              />
              <svg
                class="history-topology-svg"
                width={effectiveOverviewWidth()}
                height={overviewHeight()}
                viewBox={`0 0 ${effectiveOverviewWidth()} ${overviewHeight()}`}
                preserveAspectRatio="none"
                style="pointer-events: none; overflow: visible;"
              >
                <For each={overviewGraph().edges}>
                  {(edge) => {
                    const nodeRadius = 3;
                    const pathData = createMemo(() => {
                      const from = lensMetricsMap().get(edge.fromHash);
                      const to = lensMetricsMap().get(edge.toHash);
                      if (!from || !to) return "";

                      const dx = to.x - from.x;
                      const dy = to.y - from.y;
                      const dist = Math.sqrt(dx * dx + dy * dy);
                      if (dist < 0.1) return "";

                      const startX = from.x + (dx / dist) * (nodeRadius * from.scale);
                      const startY = from.y + (dy / dist) * (nodeRadius * from.scale);
                      const endX = to.x - (dx / dist) * (nodeRadius * to.scale);
                      const endY = to.y - (dy / dist) * (nodeRadius * to.scale);

                      if (edge.fromLane === edge.toLane) {
                        return `M ${startX} ${startY} L ${endX} ${endY}`;
                      } else {
                        const ctrlX = startX + (endX - startX) * 0.48;
                        return `M ${startX} ${startY} C ${ctrlX} ${startY}, ${ctrlX} ${endY}, ${endX} ${endY}`;
                      }
                    });

                    const isMainline = edge.fromLane === 0 && edge.toLane === 0;
                    const isSameLane = edge.fromLane === edge.toLane;

                    return (
                      <path
                        class={`history-topology-path ${isMainline ? "is-active-rail" : isSameLane ? "is-lane" : "is-branch"}`}
                        d={pathData()}
                        fill="none"
                        stroke={isMainline ? "var(--chrome-accent)" : "currentColor"}
                        stroke-width={isMainline ? 2 : 1.4}
                        stroke-opacity={isMainline ? 0.45 : 0.28}
                      />
                    );
                  }}
                </For>
              </svg>
              <For each={overviewGraph().nodes}>
                {(node, index) => {
                  const metric = () => lensMetrics()[index()];
                  return (
                    <button
                      type="button"
                      class={`history-topology-node ${selectedCommitHash() === node.commitHash ? "is-active" : ""} ${hoveredCommitHash() === node.commitHash ? "is-hovered" : ""} ${node.isMerge ? "is-merge" : ""}`}
                      style={{
                        left: `${metric()?.x ?? 0}px`,
                        top: `${metric()?.y ?? 0}px`,
                        transform: `translate(-50%, -50%) scale(${metric()?.scale ?? 1})`,
                        "z-index": selectedCommitHash() === node.commitHash ? 12 : hoveredCommitHash() === node.commitHash ? 8 : 2
                      }}
                      onClick={() => {
                        setSelectedCommitHash(node.commitHash);
                        const m = metric();
                        if (m) setHoverLensX(m.x);
                      }}
                      onPointerEnter={() => setHoveredCommitHash(node.commitHash)}
                      title={`${node.shortHash}: ${node.subject}`}
                      aria-label={`Select commit ${node.shortHash}`}
                    />
                  );
                }}
              </For>
            </div>
          </div>
        </section>

        <section style="display: flex; flex: 1; overflow: hidden;">
          <article
            style="width: 280px; flex-shrink: 0; border-right: 1px solid rgba(var(--chrome-border-rgb), 0.15); background: var(--surface-1); display: flex; flex-direction: column; overflow: hidden;"
          >
            <ul style="flex: 1; overflow-y: auto; margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column;">
              <For each={historyData() ? historyData()!.entries : []}>
                {(entry) => {
                  const isSelected = selectedCommitHash() === entry.commitHash;
                  return (
                    <li>
                      <button
                        style={{
                          width: "100%",
                          "text-align": "left",
                          padding: "10px 12px",
                          background: selectedCommitHash() === entry.commitHash ? "rgba(var(--accent-rgb), 0.12)" : "transparent",
                          border: "none",
                          "border-bottom": "1px solid rgba(var(--chrome-border-rgb), 0.08)",
                          "border-left": `2px solid ${selectedCommitHash() === entry.commitHash ? "var(--accent-bright)" : "transparent"}`,
                          cursor: "pointer",
                          display: "flex",
                          "flex-direction": "column",
                          gap: "4px",
                          transition: "all 0.16s ease"
                        }}
                        onClick={() => setSelectedCommitHash(entry.commitHash)}
                        onPointerEnter={() => setHoveredCommitHash(entry.commitHash)}
                        onPointerLeave={() => setHoveredCommitHash(null)}
                      >
                        <div style="display: flex; justify-content: space-between; align-items: baseline; font-size: 10px;">
                          <span style={`font-family: var(--font-mono); font-weight: ${isSelected ? "700" : "600"}; color: ${isSelected ? "var(--text-strong)" : "var(--text-muted)"};`}>
                            {entry.shortHash}
                          </span>
                          <CommitTime isoString={entry.authoredAt} style="color: var(--text-muted); opacity: 0.8;" readOnly={true} />
                        </div>
                        <div style={`font-size: 13px; font-weight: ${isSelected ? "600" : "500"}; color: ${isSelected ? "var(--text-strong)" : "var(--text-normal)"}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;`}>
                          {entry.subject}
                        </div>
                        <div style="font-size: 11px; color: var(--text-muted); display: flex; justify-content: space-between; align-items: center;">
                          <div style="display: flex; gap: 4px; align-items: center;">
                            <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon">
                              <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
                              <circle cx="12" cy="7" r="4"></circle>
                            </svg>
                            {entry.authorName}
                          </div>
                          <CommitImpact hash={entry.commitHash} repoPath={activeRepo()} />
                        </div>
                      </button>
                    </li>
                  );
                }}
              </For>
            </ul>
          </article>

          <article style="flex: 1; min-width: 0; background: var(--surface-0); display: flex; flex-direction: column; overflow: hidden;">
            <Show when={commitDetailError() && !commitDetailData()}>
              <div style="padding: 16px;">
                <ErrorStateCard
                  title="Commit detail failed"
                  body={commitDetailError() ?? "Unknown error"}
                />
              </div>
            </Show>

            <Show when={commitDetailData()}>
              <div style="flex: 1; overflow-y: auto; padding: 24px; display: flex; flex-direction: column;">
                <div style="margin-bottom: 24px; display: flex; align-items: flex-start; justify-content: space-between; gap: 16px;">
                  <div style="min-width: 0;">
                    <h3 style="margin: 0 0 8px 0; font-size: 1.25rem; line-height: 1.4; color: var(--text-strong); word-wrap: break-word;">
                      {commitDetailData() ? commitDetailData()!.subject : ""}
                    </h3>
                    <div style="display: flex; flex-wrap: wrap; gap: 12px; font-size: 12px; color: var(--text-muted); align-items: center;">
                      <div class="user-chip" style="display: flex; align-items: center; gap: 6px;">
                        <div style="width: 24px; height: 24px; border-radius: 12px; background: rgba(var(--chrome-border-rgb), 0.1); display: flex; align-items: center; justify-content: center; font-size: 10px; font-weight: bold; color: var(--text-strong);">
                          {commitDetailData() ? commitDetailData()!.authorName.charAt(0).toUpperCase() : ""}
                        </div>
                        <span style="color: var(--text-normal); font-weight: 500;">
                          {commitDetailData() ? commitDetailData()!.authorName : ""}
                        </span>
                      </div>
                      <span style="opacity: 0.5;">|</span>
                      <CommitTime isoString={commitDetailData() ? commitDetailData()!.authoredAt : ""} />
                      <span style="opacity: 0.5;">|</span>
                      <span style="font-family: var(--font-mono); background: rgba(var(--chrome-border-rgb), 0.1); padding: 2px 6px; border-radius: 4px;">
                        {commitDetailData() ? commitDetailData()!.shortHash : ""}
                      </span>
                    </div>
                  </div>
                </div>

                <Show when={commitDetailData() && commitDetailData()!.body.length > 0}>
                  <div style="margin-bottom: 24px; font-size: 13px; line-height: 1.6; color: var(--text-normal); white-space: pre-wrap; font-family: var(--font-sans); background: rgba(var(--chrome-border-rgb), 0.03); padding: 12px 16px; border-radius: 8px; border: 1px solid rgba(var(--chrome-border-rgb), 0.08);">
                    {commitDetailData() ? commitDetailData()!.body : ""}
                  </div>
                </Show>

                <div style="margin-top: auto; padding-top: 24px; border-top: 1px solid rgba(var(--chrome-border-rgb), 0.1);">
                  <h4 style="margin: 0 0 12px 0; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-muted); display: flex; gap: 6px; align-items: center;">
                    <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon">
                      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path>
                      <polyline points="14 2 14 8 20 8"></polyline>
                      <line x1="16" y1="13" x2="8" y2="13"></line>
                      <line x1="16" y1="17" x2="8" y2="17"></line>
                      <polyline points="10 9 9 9 8 9"></polyline>
                    </svg>
                    Changed Files ({commitDetailData() ? commitDetailData()!.files.length : 0})
                  </h4>
                  <ul style="margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 4px;">
                    <For each={commitDetailData() ? commitDetailData()!.files : []}>
                      {(file) => (
                        <li style="display: flex; align-items: center; justify-content: space-between; padding: 6px 10px; background: rgba(var(--chrome-border-rgb), 0.04); border-radius: 6px; font-size: 12px; border: 1px solid rgba(var(--chrome-border-rgb), 0.06);">
                          <div style="display: flex; align-items: center; min-width: 0; gap: 8px;">
                            <span style="font-family: var(--font-sans); color: var(--text-normal); overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                              {file.path.split("/").pop()}
                            </span>
                            <span style="font-family: var(--font-mono); font-size: 10px; color: var(--text-muted); opacity: 0.6; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                              {file.path.includes("/") ? file.path.substring(0, file.path.lastIndexOf("/")) : ""}
                            </span>
                          </div>
                          <div style="display: flex; gap: 8px; flex-shrink: 0; font-family: var(--font-mono); font-size: 10px; font-weight: 600;">
                            <Show when={file.additions > 0}>
                              <span style="color: var(--state-added); background: rgba(var(--state-added-rgb, 46,160,67), 0.1); padding: 2px 6px; border-radius: 10px;">
                                +{file.additions}
                              </span>
                            </Show>
                            <Show when={file.deletions > 0}>
                              <span style="color: var(--state-deleted); background: rgba(var(--state-deleted-rgb, 248,81,73), 0.1); padding: 2px 6px; border-radius: 10px;">
                                -{file.deletions}
                              </span>
                            </Show>
                          </div>
                        </li>
                      )}
                    </For>
                  </ul>
                </div>
              </div>
            </Show>
          </article>
        </section>
      </Show>
    </div>
  );
}
