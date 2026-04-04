import { For, createEffect, createMemo, createSignal, onCleanup, onMount, Show } from "solid-js";
import { createStore } from "solid-js/store";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import type { CommitDetailData, CommitHistoryData, CommitHistoryEntry } from "@/lib/backend/dtos";
import { getCommitDetail, listCommitHistory, primeCommitDetails } from "@/lib/backend/commands";
import { scheduleBackgroundTask } from "@/lib/perf/background";
import { recordUiTiming } from "@/lib/telemetry/uiTiming";
import { formatCommitDate, formatFullDate, useDateFormatPreference } from "@/lib/ui/date";

interface HistoryPageProps {
  embedded?: boolean;
}

interface GraphNode extends CommitHistoryEntry {
  row: number;
  lane: number;
  visibleParents: string[];
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
}

interface LensNodeMetric {
  centerPercent: number;
  shiftPx: number;
  scale: number;
}

const historyCache = new Map<string, CommitHistoryData>();
const [commitDetailStore, setCommitDetailStore] = createStore<Record<string, CommitDetailData>>({});
const pendingHistoryRequests = new Map<string, Promise<void>>();
const pendingCommitDetailRequests = new Map<string, Promise<void>>();

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
        
        // Logarithmic intensity scaling for the 'bloom' effect
        const intensity = Math.min(1, Math.log10(total + 1) / 3);
        const glowColor = addRatio > 0.6 ? "var(--state-added-rgb)" : addRatio < 0.4 ? "var(--state-deleted-rgb)" : "var(--chrome-accent-rgb)";

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
              style={`display: flex; gap: 1.5px; padding: 1px; border-radius: 2px; background: rgba(var(--chrome-border-rgb), 0.05); border: 0.5px solid rgba(var(--chrome-border-rgb), 0.1); box-shadow: ${intensity > 0.7 ? `0 0 8px rgba(${glowColor}, ${intensity * 0.3})` : "none"}`}
            >
              {[...Array(blocks)].map((_, i) => {
                const isAdd = i < addBlocks;
                return (
                  <div 
                    style={`width: 6px; height: 3px; border-radius: 0.5px; background: ${isAdd ? "var(--state-added)" : "var(--state-deleted)"}; opacity: ${0.4 + intensity * 0.6}; transition: all 0.3s ease;`} 
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
  const nodes: GraphNode[] = [];
  const hashToLane = new Map<string, number>();
  const hashToRow = new Map<string, number>();
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

  entries.forEach((entry, row) => {
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
    nodes.push({
      ...entry,
      row,
      lane,
      visibleParents
    });
  });

  const edges: GraphEdge[] = [];
  nodes.forEach((node) => {
    node.visibleParents.forEach((parentHash) => {
      const parentRow = hashToRow.get(parentHash);
      const parentLane = hashToLane.get(parentHash);
      if (typeof parentRow !== "number" || typeof parentLane !== "number") {
        return;
      }

      edges.push({
        fromHash: node.commitHash,
        toHash: parentHash,
        fromRow: node.row,
        toRow: parentRow,
        fromLane: node.lane,
        toLane: parentLane
      });
    });
  });

  return { nodes, edges, laneCount };
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
  const [overviewWidth, setOverviewWidth] = createSignal(0);
  const [hoverLensX, setHoverLensX] = createSignal<number | null>(null);
  const [isScrubbing, setIsScrubbing] = createSignal(false);
  const [hoveredCommitHash, setHoveredCommitHash] = createSignal<string | null>(null);
  let overviewContainer: HTMLDivElement | undefined;

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
    return history ? history.entries : [];
  });

  const overviewGraph = createMemo(() => buildGraphLayout(overviewEntries()));
  const overviewHeight = createMemo(() => Math.max(36, overviewGraph().laneCount * 12 + 18));
  const overviewLaneStep = createMemo(() => (overviewHeight() - 16) / Math.max(overviewGraph().laneCount, 1));
  const effectiveOverviewWidth = createMemo(() => Math.max(overviewWidth(), overviewContainer?.clientWidth ?? 0, 1));
  const selectedIndex = createMemo(() => {
    const nodes = overviewGraph().nodes;
    const selectedHash = selectedCommitHash();
    if (!selectedHash) {
      return nodes.length > 0 ? 0 : null;
    }
    const index = nodes.findIndex((node) => node.commitHash === selectedHash);
    return index >= 0 ? index : nodes.length > 0 ? 0 : null;
  });

  const timelineBasePercents = createMemo(() => {
    const entries = overviewEntries();
    const count = entries.length;
    if (count === 0) {
      return [] as number[];
    }
    if (count === 1) {
      return [50];
    }

    const insetPercent = 1.8;
    const usablePercent = 100 - insetPercent * 2;
    const evenPercents = entries.map((_, index) =>
      insetPercent + (index / (count - 1)) * usablePercent
    );

    const timestamps = entries.map((entry) => {
      const parsed = Date.parse(entry.authoredAt);
      return Number.isFinite(parsed) ? parsed : Number.NaN;
    });
    const rawGaps = timestamps.slice(0, -1).map((value, index) => {
      const nextValue = timestamps[index + 1] ?? Number.NaN;
      if (!Number.isFinite(value) || !Number.isFinite(nextValue)) {
        return 1;
      }
      return Math.max(1, Math.abs(value - nextValue));
    });

    const sortedGaps = [...rawGaps].sort((a, b) => a - b);
    const medianGap =
      sortedGaps.length > 0
        ? sortedGaps[Math.floor(sortedGaps.length / 2)] ?? 1
        : 1;
    const baselineGap = Math.max(medianGap, 60_000);
    const weightedGaps = rawGaps.map((gap) => {
      const normalized = Math.log1p(gap / baselineGap);
      return Math.max(0.82, Math.min(1.4, 1 + normalized * 0.22));
    });
    const totalWeight = weightedGaps.reduce((sum, weight) => sum + weight, 0);

    const weightedPercents: number[] = [insetPercent];
    let cursor = insetPercent;
    for (let index = 0; index < weightedGaps.length; index += 1) {
      cursor += (weightedGaps[index]! / Math.max(totalWeight, 1)) * usablePercent;
      weightedPercents.push(cursor);
    }

    const subtleBlend = 0.2;
    return evenPercents.map(
      (evenPercent, index) =>
        evenPercent * (1 - subtleBlend) + (weightedPercents[index] ?? evenPercent) * subtleBlend
    );
  });

  const baseCenterPercent = (index: number, count: number) =>
    timelineBasePercents()[index] ?? (count <= 1 ? 50 : 1.8 + (index / (count - 1)) * (100 - 3.6));

  const selectedBaseCenterPx = createMemo(() => {
    const count = overviewGraph().nodes.length;
    const index = selectedIndex();
    const width = effectiveOverviewWidth();
    if (index === null || count === 0) {
      return width * 0.5;
    }
    return (baseCenterPercent(index, count) / 100) * width;
  });

  const lensFocusPx = createMemo(() => hoverLensX() ?? selectedBaseCenterPx());

  const lensMetrics = createMemo<LensNodeMetric[]>(() => {
    const nodes = overviewGraph().nodes;
    const width = effectiveOverviewWidth();
    const focusPx = lensFocusPx();
    if (nodes.length === 0) {
      return [];
    }

    if (nodes.length === 1) {
      const node = nodes[0]!;
      const isSelected = selectedCommitHash() === node.commitHash;
      const isHovered = hoveredCommitHash() === node.commitHash;
      return [{
        centerPercent: 50,
        shiftPx: 0,
        scale: 1 + (isSelected ? 0.22 : 0) + (isHovered ? 0.08 : 0) + (node.isMerge ? 0.05 : 0)
      }];
    }

    const spacingPx = width / Math.max(nodes.length - 1, 1);
    const lensRadiusPx = Math.max(28, Math.min(96, spacingPx * 3.5));
    const maxShiftPx = Math.max(2, Math.min(8, spacingPx * 0.45));
    const maxScaleGain = 0.55;
    const influenceAt = (distancePx: number) => {
      const normalized = Math.min(distancePx / lensRadiusPx, 1);
      return Math.cos(normalized * Math.PI * 0.5) ** 2;
    };

    return nodes.map((node, index) => {
      const centerPercent = baseCenterPercent(index, nodes.length);
      const baseCenterPx = (centerPercent / 100) * width;
      const deltaPx = baseCenterPx - focusPx;
      const focusGain = influenceAt(Math.abs(deltaPx));
      const direction = Math.abs(deltaPx) < 0.5 ? 0 : deltaPx < 0 ? -1 : 1;
      const shiftPx = direction * focusGain * maxShiftPx;
      const isSelected = selectedCommitHash() === node.commitHash;
      const isHovered = hoveredCommitHash() === node.commitHash;
      const scale =
        1 +
        focusGain * maxScaleGain +
        (isSelected ? 0.18 : 0) +
        (isHovered ? 0.06 : 0) +
        (node.isMerge ? 0.04 : 0);
      return {
        centerPercent,
        shiftPx,
        scale
      };
    });
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

    const rect = container.getBoundingClientRect();
    let nearestIndex = 0;
    let nearestDistance = Number.POSITIVE_INFINITY;
    metrics.forEach((metric, index) => {
      const centerX = (metric.centerPercent / 100) * rect.width + metric.shiftPx;
      const distance = Math.abs(centerX - offsetX);
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
    const cached = historyCache.get(cacheKey);
    if (cached) {
      setHistoryData(cached);
      setHistoryError(null);
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

      historyCache.set(cacheKey, result.data);
      if (activeRepo() === repositoryPath && parsedLimit() === limit) {
        setHistoryData(result.data);
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
    const limit = parsedLimit();
    if (!repositoryPath) {
      setHistoryData(null);
      setHistoryError(null);
      setCommitDetailData(null);
      setCommitDetailError(null);
      return;
    }

    const cached = historyCache.get(`${repositoryPath}::${limit}`);
    if (cached) {
      setHistoryData(cached);
      setHistoryError(null);
    }

    void loadHistory(repositoryPath, limit);
  });

  createEffect(() => {
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

  createEffect(() => {
    const repositoryPath = activeRepo();
    const history = historyData();
    if (!repositoryPath || !history) {
      return;
    }

    const visibleCommitHashes = history.entries.slice(0, 12).map((entry) => entry.commitHash);
    if (visibleCommitHashes.length === 0) {
      return;
    }

    const cancel = scheduleBackgroundTask(() => {
      void primeCommitDetails(repositoryPath, visibleCommitHashes).then((result) => {
        if (!result.ok) {
          return;
        }

        const updates: Record<string, CommitDetailData> = {};
        for (const entry of result.data.entries) {
          updates[commitDetailCacheKey(repositoryPath, entry.commitHash)] = entry;
        }
        setCommitDetailStore(updates);

        const selected = selectedCommitHash();
        if (!selected) {
          return;
        }

        const selectedEntry = result.data.entries.find((entry) => entry.commitHash === selected);
        if (selectedEntry && activeRepo() === repositoryPath) {
          setCommitDetailData(selectedEntry);
          setCommitDetailError(null);
        }
      });
    });

    onCleanup(cancel);
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
          ref={overviewContainer}
          class="topology-canvas"
          style="margin: 0; padding: 8px 12px 10px; border: none; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.1); background: var(--surface-0); flex-shrink: 0; border-radius: 0;"
        >
          <div
            class="history-topology-strip"
            style={`height: ${overviewHeight()}px;`}
            onPointerEnter={(event) => {
              updateScrubTarget(event.clientX, false);
            }}
            onPointerDown={(event) => {
              event.currentTarget.setPointerCapture(event.pointerId);
              setIsScrubbing(true);
              updateScrubTarget(event.clientX, true);
            }}
            onPointerMove={(event) => {
              updateScrubTarget(event.clientX, isScrubbing());
            }}
            onMouseMove={(event) => {
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
            <div class="history-topology-rail" />
            <For each={overviewGraph().edges}>
              {(edge) => {
                const metrics = lensMetrics();
                const fromMetric = metrics[edge.fromRow];
                const toMetric = metrics[edge.toRow];
                if (!fromMetric || !toMetric) {
                  return null;
                }

                const x1 = (fromMetric.centerPercent / 100) * effectiveOverviewWidth() + fromMetric.shiftPx;
                const x2 = (toMetric.centerPercent / 100) * effectiveOverviewWidth() + toMetric.shiftPx;
                const y1 = 8 + edge.fromLane * overviewLaneStep();
                const y2 = 8 + edge.toLane * overviewLaneStep();
                const dx = x2 - x1;
                const dy = y2 - y1;
                const length = Math.sqrt(dx * dx + dy * dy);
                const angle = Math.atan2(dy, dx) * (180 / Math.PI);
                return (
                  <div
                    class={`history-topology-edge ${edge.fromLane !== edge.toLane ? "is-branch" : ""}`}
                    style={`left: ${x1}px; top: ${y1}px; width: ${length}px; transform: rotate(${angle}deg);`}
                  />
                );
              }}
            </For>
            <For each={overviewGraph().nodes}>
              {(node, index) => {
                const metric = lensMetrics()[index()];
                if (!metric) {
                  return null;
                }

                const isSelected = selectedCommitHash() === node.commitHash;
                const isHovered = hoveredCommitHash() === node.commitHash;
                return (
                  <button
                    type="button"
                    class={`history-topology-node ${isSelected ? "is-active" : ""} ${isHovered ? "is-hovered" : ""} ${node.isMerge ? "is-merge" : ""}`}
                    style={`left: calc(${metric.centerPercent}% - 3px); top: ${8 + node.lane * overviewLaneStep() - 3}px; width: 6px; height: 6px; transform: translateX(${metric.shiftPx}px) scale(${metric.scale}); z-index: ${isHovered ? 5 : isSelected ? 4 : 2};`}
                    onClick={() => {
                      setSelectedCommitHash(node.commitHash);
                      const clickedCenter = (metric.centerPercent / 100) * effectiveOverviewWidth() + metric.shiftPx;
                      setHoverLensX(clickedCenter);
                    }}
                    onPointerEnter={() => setHoveredCommitHash(node.commitHash)}
                    title={`${node.shortHash}: ${node.subject}`}
                    aria-label={`Select commit ${node.shortHash}`}
                  />
                );
              }}
            </For>
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
                        style={`width: 100%; text-align: left; padding: 10px 12px; background: ${isSelected ? "rgba(var(--accent-rgb), 0.1)" : "transparent"}; border: none; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.08); border-left: 2px solid ${isSelected ? "var(--accent-bright)" : "transparent"}; cursor: pointer; display: flex; flex-direction: column; gap: 4px;`}
                        onClick={() => setSelectedCommitHash(entry.commitHash)}
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
