import { recordCommandLifecycleEvent } from "@/lib/telemetry/commandLifecycle";

export type UiTimingPhase = "mount" | "interaction" | "layout" | string;

export interface UiTimingSample {
  event: string;
  phase: UiTimingPhase;
  ok: boolean;
  errorCode?: string;
  durationMs: number;
  recordedAt: string;
}

export interface UiTimingSummary {
  event: string;
  phase: UiTimingPhase;
  count: number;
  failureCount: number;
  p50Ms: number;
  p95Ms: number;
  avgMs: number;
  minMs: number;
  maxMs: number;
  lastMs: number;
}

export interface UiTimingReport {
  generatedAt: string;
  totalSamples: number;
  eventCount: number;
  summaries: UiTimingSummary[];
  recentSamples: UiTimingSample[];
}

interface UiTimingRetentionPolicy {
  retentionDays: number;
  retentionMb: number;
}

interface UiTimingInput {
  event: string;
  phase?: UiTimingPhase;
  durationMs: number;
  ok?: boolean;
  errorCode?: string;
}

const STORAGE_KEY = "gdpu.ui-timing.samples.v1";
const MAX_RETAINED_SAMPLES = 800;
const MAX_RECENT_SAMPLES = 40;
const DEFAULT_RETENTION_POLICY: UiTimingRetentionPolicy = {
  retentionDays: 30,
  retentionMb: 128
};
const MIN_RETENTION_DAYS = 1;
const MAX_RETENTION_DAYS = 365;
const MIN_RETENTION_MB = 16;
const MAX_RETENTION_MB = 4096;

const samples: UiTimingSample[] = [];
const listeners = new Set<(report: UiTimingReport) => void>();
let retentionPolicy = { ...DEFAULT_RETENTION_POLICY };

hydrateStoredSamples();

export function recordUiTiming(input: UiTimingInput): void {
  const event = normalizeEvent(input.event);
  if (!event) {
    return;
  }

  const phase = normalizePhase(input.phase ?? "interaction");
  const durationMs = roundToHundredths(clampDuration(input.durationMs));
  const ok = input.ok ?? true;
  const errorCode = typeof input.errorCode === "string" ? input.errorCode.trim() : undefined;

  const sample: UiTimingSample = {
    event,
    phase,
    ok,
    errorCode: errorCode && errorCode.length > 0 ? errorCode : undefined,
    durationMs,
    recordedAt: new Date().toISOString()
  };

  samples.push(sample);
  enforceRetentionAndPersist();

  recordCommandLifecycleEvent({
    type: sample.ok ? "success" : "failure",
    command: `ui.${sample.phase}.${sample.event}`,
    durationMs: sample.durationMs,
    errorCode: sample.errorCode
  });

  emitReport();
}

export function getUiTimingReport(): UiTimingReport {
  const grouped = new Map<string, UiTimingSample[]>();

  for (const sample of samples) {
    const key = `${sample.phase}:${sample.event}`;
    const existing = grouped.get(key);
    if (existing) {
      existing.push(sample);
    } else {
      grouped.set(key, [sample]);
    }
  }

  const summaries: UiTimingSummary[] = Array.from(grouped.entries())
    .map(([key, group]) => summarizeGroup(key, group))
    .sort((left, right) => {
      if (right.p95Ms !== left.p95Ms) {
        return right.p95Ms - left.p95Ms;
      }
      return left.event.localeCompare(right.event);
    });

  return {
    generatedAt: new Date().toISOString(),
    totalSamples: samples.length,
    eventCount: summaries.length,
    summaries,
    recentSamples: samples.slice(-MAX_RECENT_SAMPLES).reverse()
  };
}

export function setUiTimingRetentionPolicy(retentionDays: number, retentionMb: number): void {
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

export function clearUiTimingReport(): void {
  if (samples.length === 0) {
    return;
  }

  samples.length = 0;
  persistSamples();
  emitReport();
}

export function subscribeUiTimingReport(listener: (report: UiTimingReport) => void): () => void {
  listeners.add(listener);
  listener(getUiTimingReport());

  return () => {
    listeners.delete(listener);
  };
}

function summarizeGroup(key: string, group: UiTimingSample[]): UiTimingSummary {
  const [phase = "interaction", event = "unknown"] = key.split(":");
  const durations = group.map((sample) => sample.durationMs).sort((left, right) => left - right);
  const failureCount = group.filter((sample) => !sample.ok).length;
  const total = durations.reduce((sum, value) => sum + value, 0);

  return {
    event,
    phase,
    count: group.length,
    failureCount,
    p50Ms: roundToHundredths(percentile(durations, 50)),
    p95Ms: roundToHundredths(percentile(durations, 95)),
    avgMs: roundToHundredths(total / Math.max(group.length, 1)),
    minMs: roundToHundredths(durations[0] ?? 0),
    maxMs: roundToHundredths(durations[durations.length - 1] ?? 0),
    lastMs: roundToHundredths(group[group.length - 1]?.durationMs ?? 0)
  };
}

function normalizeEvent(value: string): string {
  const trimmed = value.trim().toLowerCase();
  if (trimmed.length === 0) {
    return "";
  }

  return trimmed.replace(/[^a-z0-9._-]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
}

function normalizePhase(value: string): UiTimingPhase {
  const normalized = value.trim().toLowerCase();
  if (normalized.length === 0) {
    return "interaction";
  }

  return normalized;
}

function clampDuration(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }

  return Math.max(value, 0);
}

function roundToHundredths(value: number): number {
  return Number(value.toFixed(2));
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

function normalizeRetentionPolicy(retentionDays: number, retentionMb: number): UiTimingRetentionPolicy {
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
  if (samples.length > MAX_RETAINED_SAMPLES) {
    samples.splice(0, samples.length - MAX_RETAINED_SAMPLES);
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

  const report = getUiTimingReport();
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
    // Ignore malformed telemetry cache and rebuild from fresh samples.
  }
}

function normalizeStoredSample(raw: unknown): UiTimingSample | null {
  if (!raw || typeof raw !== "object") {
    return null;
  }

  const entry = raw as Partial<UiTimingSample>;
  if (typeof entry.event !== "string" || typeof entry.phase !== "string") {
    return null;
  }
  if (typeof entry.ok !== "boolean") {
    return null;
  }
  if (typeof entry.durationMs !== "number") {
    return null;
  }
  if (typeof entry.recordedAt !== "string") {
    return null;
  }

  return {
    event: normalizeEvent(entry.event),
    phase: normalizePhase(entry.phase),
    ok: entry.ok,
    errorCode: typeof entry.errorCode === "string" ? entry.errorCode.trim() || undefined : undefined,
    durationMs: roundToHundredths(clampDuration(entry.durationMs)),
    recordedAt: entry.recordedAt
  };
}

function persistSamples(): void {
  if (typeof window === "undefined") {
    return;
  }

  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(samples));
  } catch {
    // Ignore persistence failures.
  }
}

function readStoredPayload(): string | null {
  if (typeof window === "undefined") {
    return null;
  }

  try {
    return window.localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}
