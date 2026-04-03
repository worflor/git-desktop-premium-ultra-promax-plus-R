export interface DiffRenderMetricSample {
  diffId: string;
  path: string;
  rendererMode: "dom" | "canvas" | string;
  changedLines: number;
  payloadBytes: number;
  firstPaintMs: number;
  sustainedScrollFps: number;
  memoryEstimateMb: number;
  fallbackActivated: boolean;
  recordedAt: string;
}

export interface DiffRenderModeSummary {
  rendererMode: string;
  sessionCount: number;
  fallbackCount: number;
  fallbackRate: number;
  firstPaintP50Ms: number;
  firstPaintP95Ms: number;
  scrollFpsP50: number;
  scrollFpsP95: number;
  memoryP50Mb: number;
  memoryP95Mb: number;
}

export interface DiffRenderMetricsReport {
  generatedAt: string;
  totalSessions: number;
  fallbackCount: number;
  fallbackRate: number;
  firstPaintP95Ms: number;
  scrollFpsP50: number;
  memoryP95Mb: number;
  modeSummaries: DiffRenderModeSummary[];
  recentSamples: DiffRenderMetricSample[];
}

interface DiffRenderRetentionPolicy {
  retentionDays: number;
  retentionMb: number;
}

interface DiffRenderMetricInput {
  diffId: string;
  path: string;
  rendererMode: string;
  changedLines: number;
  payloadBytes: number;
  firstPaintMs: number;
  sustainedScrollFps: number;
  memoryEstimateMb: number;
  fallbackActivated: boolean;
}

const STORAGE_KEY = "gdpu.diff-render-metrics.v1";
const MAX_RETAINED_SESSIONS = 600;
const MAX_RECENT_SESSIONS = 20;
const DEFAULT_RETENTION_POLICY: DiffRenderRetentionPolicy = {
  retentionDays: 30,
  retentionMb: 128
};
const MIN_RETENTION_DAYS = 1;
const MAX_RETENTION_DAYS = 365;
const MIN_RETENTION_MB = 16;
const MAX_RETENTION_MB = 4096;

const samples: DiffRenderMetricSample[] = [];
const listeners = new Set<(report: DiffRenderMetricsReport) => void>();
let retentionPolicy = { ...DEFAULT_RETENTION_POLICY };

hydrateStoredSamples();

export function recordDiffRenderMetrics(input: DiffRenderMetricInput): void {
  const sample: DiffRenderMetricSample = {
    diffId: input.diffId,
    path: input.path,
    rendererMode: normalizeMode(input.rendererMode),
    changedLines: clampNumber(input.changedLines),
    payloadBytes: clampNumber(input.payloadBytes),
    firstPaintMs: roundToHundredths(clampNumber(input.firstPaintMs)),
    sustainedScrollFps: roundToHundredths(clampNumber(input.sustainedScrollFps)),
    memoryEstimateMb: roundToHundredths(clampNumber(input.memoryEstimateMb)),
    fallbackActivated: Boolean(input.fallbackActivated),
    recordedAt: new Date().toISOString()
  };

  samples.push(sample);
  enforceRetentionAndPersist();
  emitReport();
}

export function setDiffRenderMetricsRetentionPolicy(retentionDays: number, retentionMb: number): void {
  const normalized = normalizeRetentionPolicy(retentionDays, retentionMb);
  const unchanged =
    normalized.retentionDays === retentionPolicy.retentionDays &&
    normalized.retentionMb === retentionPolicy.retentionMb;
  if (unchanged) {
    return;
  }

  retentionPolicy = normalized;
  enforceRetentionAndPersist();
  emitReport();
}

export function getDiffRenderMetricsReport(): DiffRenderMetricsReport {
  const fallbackCount = samples.filter((sample) => sample.fallbackActivated).length;

  const firstPaintValues = samples
    .map((sample) => sample.firstPaintMs)
    .filter((value) => value > 0)
    .sort((left, right) => left - right);
  const scrollFpsValues = samples
    .map((sample) => sample.sustainedScrollFps)
    .filter((value) => value > 0)
    .sort((left, right) => left - right);
  const memoryValues = samples
    .map((sample) => sample.memoryEstimateMb)
    .filter((value) => value > 0)
    .sort((left, right) => left - right);

  const grouped = new Map<string, DiffRenderMetricSample[]>();
  for (const sample of samples) {
    const existing = grouped.get(sample.rendererMode);
    if (existing) {
      existing.push(sample);
    } else {
      grouped.set(sample.rendererMode, [sample]);
    }
  }

  const modeSummaries = Array.from(grouped.entries())
    .map(([rendererMode, modeSamples]) => summarizeMode(rendererMode, modeSamples))
    .sort((left, right) => {
      if (right.sessionCount !== left.sessionCount) {
        return right.sessionCount - left.sessionCount;
      }
      return left.rendererMode.localeCompare(right.rendererMode);
    });

  return {
    generatedAt: new Date().toISOString(),
    totalSessions: samples.length,
    fallbackCount,
    fallbackRate: samples.length === 0 ? 0 : fallbackCount / samples.length,
    firstPaintP95Ms: roundToHundredths(percentile(firstPaintValues, 95)),
    scrollFpsP50: roundToHundredths(percentile(scrollFpsValues, 50)),
    memoryP95Mb: roundToHundredths(percentile(memoryValues, 95)),
    modeSummaries,
    recentSamples: samples.slice(-MAX_RECENT_SESSIONS).reverse()
  };
}

export function clearDiffRenderMetricsReport(): void {
  if (samples.length === 0) {
    return;
  }

  samples.length = 0;
  persistSamples();
  emitReport();
}

export function subscribeDiffRenderMetricsReport(
  listener: (report: DiffRenderMetricsReport) => void
): () => void {
  listeners.add(listener);
  listener(getDiffRenderMetricsReport());

  return () => {
    listeners.delete(listener);
  };
}

function summarizeMode(
  rendererMode: string,
  modeSamples: DiffRenderMetricSample[]
): DiffRenderModeSummary {
  const fallbackCount = modeSamples.filter((sample) => sample.fallbackActivated).length;
  const firstPaintValues = modeSamples
    .map((sample) => sample.firstPaintMs)
    .filter((value) => value > 0)
    .sort((left, right) => left - right);
  const scrollValues = modeSamples
    .map((sample) => sample.sustainedScrollFps)
    .filter((value) => value > 0)
    .sort((left, right) => left - right);
  const memoryValues = modeSamples
    .map((sample) => sample.memoryEstimateMb)
    .filter((value) => value > 0)
    .sort((left, right) => left - right);

  return {
    rendererMode,
    sessionCount: modeSamples.length,
    fallbackCount,
    fallbackRate: modeSamples.length === 0 ? 0 : fallbackCount / modeSamples.length,
    firstPaintP50Ms: roundToHundredths(percentile(firstPaintValues, 50)),
    firstPaintP95Ms: roundToHundredths(percentile(firstPaintValues, 95)),
    scrollFpsP50: roundToHundredths(percentile(scrollValues, 50)),
    scrollFpsP95: roundToHundredths(percentile(scrollValues, 95)),
    memoryP50Mb: roundToHundredths(percentile(memoryValues, 50)),
    memoryP95Mb: roundToHundredths(percentile(memoryValues, 95))
  };
}

function percentile(sortedValues: number[], percentileValue: number): number {
  if (sortedValues.length === 0) {
    return 0;
  }

  const index = (percentileValue / 100) * (sortedValues.length - 1);
  const lowerIndex = Math.floor(index);
  const upperIndex = Math.ceil(index);
  const lowerValue = sortedValues[lowerIndex] ?? 0;
  const upperValue = sortedValues[upperIndex] ?? lowerValue;

  if (lowerIndex === upperIndex) {
    return lowerValue;
  }

  const weight = index - lowerIndex;
  return lowerValue + (upperValue - lowerValue) * weight;
}

function normalizeMode(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (normalized === "canvas" || normalized === "dom" || normalized === "fallback") {
    return normalized;
  }

  return "dom";
}

function clampNumber(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }

  return Math.max(value, 0);
}

function roundToHundredths(value: number): number {
  return Number(value.toFixed(2));
}

function normalizeRetentionPolicy(
  retentionDays: number,
  retentionMb: number
): DiffRenderRetentionPolicy {
  const normalizedDays = Number.isFinite(retentionDays)
    ? Math.min(Math.max(Math.floor(retentionDays), MIN_RETENTION_DAYS), MAX_RETENTION_DAYS)
    : DEFAULT_RETENTION_POLICY.retentionDays;
  const normalizedMb = Number.isFinite(retentionMb)
    ? Math.min(Math.max(Math.floor(retentionMb), MIN_RETENTION_MB), MAX_RETENTION_MB)
    : DEFAULT_RETENTION_POLICY.retentionMb;

  return {
    retentionDays: normalizedDays,
    retentionMb: normalizedMb
  };
}

function enforceRetentionAndPersist(): void {
  trimByTime();
  trimByCount();
  trimBySize();
  persistSamples();
}

function trimByTime(): void {
  const cutoffTime = Date.now() - retentionPolicy.retentionDays * 24 * 60 * 60 * 1000;
  let firstKeptIndex = 0;

  while (firstKeptIndex < samples.length) {
    const sampleTime = Date.parse(samples[firstKeptIndex]?.recordedAt ?? "");
    if (Number.isFinite(sampleTime) && sampleTime >= cutoffTime) {
      break;
    }
    firstKeptIndex += 1;
  }

  if (firstKeptIndex > 0) {
    samples.splice(0, firstKeptIndex);
  }
}

function trimByCount(): void {
  if (samples.length > MAX_RETAINED_SESSIONS) {
    samples.splice(0, samples.length - MAX_RETAINED_SESSIONS);
  }
}

function trimBySize(): void {
  const maxBytes = retentionPolicy.retentionMb * 1024 * 1024;
  while (samples.length > 0 && estimateSerializedSamplesBytes() > maxBytes) {
    samples.shift();
  }
}

function estimateSerializedSamplesBytes(): number {
  const encoded = new TextEncoder().encode(JSON.stringify(samples));
  return encoded.length;
}

function emitReport(): void {
  if (listeners.size === 0) {
    return;
  }

  const report = getDiffRenderMetricsReport();
  for (const listener of listeners) {
    listener(report);
  }
}

function hydrateStoredSamples(): void {
  const rawPayload = readStoredPayload();
  if (!rawPayload) {
    return;
  }

  try {
    const parsed = JSON.parse(rawPayload);
    if (!Array.isArray(parsed)) {
      return;
    }

    for (const entry of parsed) {
      const normalized = normalizeStoredSample(entry);
      if (normalized) {
        samples.push(normalized);
      }
    }

    enforceRetentionAndPersist();
  } catch {
    // Ignore malformed cache and rebuild from fresh sessions.
  }
}

function normalizeStoredSample(raw: unknown): DiffRenderMetricSample | null {
  if (!raw || typeof raw !== "object") {
    return null;
  }

  const entry = raw as Partial<DiffRenderMetricSample>;
  if (typeof entry.diffId !== "string" || typeof entry.path !== "string") {
    return null;
  }
  if (typeof entry.rendererMode !== "string") {
    return null;
  }
  if (typeof entry.recordedAt !== "string") {
    return null;
  }

  return {
    diffId: entry.diffId,
    path: entry.path,
    rendererMode: normalizeMode(entry.rendererMode),
    changedLines: clampNumber(Number(entry.changedLines ?? 0)),
    payloadBytes: clampNumber(Number(entry.payloadBytes ?? 0)),
    firstPaintMs: roundToHundredths(clampNumber(Number(entry.firstPaintMs ?? 0))),
    sustainedScrollFps: roundToHundredths(clampNumber(Number(entry.sustainedScrollFps ?? 0))),
    memoryEstimateMb: roundToHundredths(clampNumber(Number(entry.memoryEstimateMb ?? 0))),
    fallbackActivated: Boolean(entry.fallbackActivated),
    recordedAt: entry.recordedAt
  };
}

function persistSamples(): void {
  if (!storageAvailable()) {
    return;
  }

  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(samples));
  } catch {
    while (samples.length > 0) {
      samples.shift();
      try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(samples));
        break;
      } catch {
        // Keep trimming until persistence succeeds.
      }
    }
  }
}

function readStoredPayload(): string | null {
  if (!storageAvailable()) {
    return null;
  }

  try {
    return window.localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

function storageAvailable(): boolean {
  return typeof window !== "undefined" && typeof window.localStorage !== "undefined";
}
