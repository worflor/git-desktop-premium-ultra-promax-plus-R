import type { CommandResult } from "@/lib/contracts/command";

export interface CommandLatencySample {
  command: string;
  ok: boolean;
  errorCode?: string;
  requestId?: string;
  roundTripMs: number;
  backendDurationMs?: number;
  recordedAt: string;
}

export interface CommandLatencySummary {
  command: string;
  count: number;
  successCount: number;
  failureCount: number;
  p50Ms: number;
  p95Ms: number;
  avgMs: number;
  minMs: number;
  maxMs: number;
  lastMs: number;
}

export interface CommandLatencyReport {
  generatedAt: string;
  totalSamples: number;
  commandCount: number;
  summaries: CommandLatencySummary[];
  recentSamples: CommandLatencySample[];
}

interface CommandLatencyRetentionPolicy {
  retentionDays: number;
  retentionMb: number;
}

const MAX_RETAINED_SAMPLES = 600;
const MAX_RECENT_SAMPLES = 20;
const STORAGE_KEY = "gdpu.command-latency.samples.v1";
const DEFAULT_RETENTION_POLICY: CommandLatencyRetentionPolicy = {
  retentionDays: 30,
  retentionMb: 128
};
const MIN_RETENTION_DAYS = 1;
const MAX_RETENTION_DAYS = 365;
const MIN_RETENTION_MB = 16;
const MAX_RETENTION_MB = 4096;

const samples: CommandLatencySample[] = [];
const listeners = new Set<(report: CommandLatencyReport) => void>();
let retentionPolicy = { ...DEFAULT_RETENTION_POLICY };

hydrateStoredSamples();

export function recordCommandLatency<T>(
  command: string,
  result: CommandResult<T>,
  roundTripMs: number
): void {
  const normalizedRoundTripMs = sanitizeDuration(roundTripMs);
  const normalizedBackendDurationMs =
    typeof result.meta?.durationMs === "number" ? sanitizeDuration(result.meta.durationMs) : undefined;

  const sample: CommandLatencySample = {
    command,
    ok: result.ok,
    errorCode: result.ok ? undefined : result.error.code,
    requestId: result.meta?.requestId,
    roundTripMs: roundToHundredths(normalizedRoundTripMs),
    backendDurationMs:
      normalizedBackendDurationMs === undefined
        ? undefined
        : roundToHundredths(normalizedBackendDurationMs),
    recordedAt: new Date().toISOString()
  };

  samples.push(sample);
  enforceRetentionAndPersist();

  emitReport();
}

export function setCommandLatencyRetentionPolicy(retentionDays: number, retentionMb: number): void {
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

export function getCommandLatencyReport(): CommandLatencyReport {
  const grouped = new Map<string, CommandLatencySample[]>();
  for (const sample of samples) {
    const existing = grouped.get(sample.command);
    if (existing) {
      existing.push(sample);
    } else {
      grouped.set(sample.command, [sample]);
    }
  }

  const summaries: CommandLatencySummary[] = Array.from(grouped.entries())
    .map(([command, commandSamples]) => summarizeCommand(command, commandSamples))
    .sort((left, right) => {
      if (right.p95Ms !== left.p95Ms) {
        return right.p95Ms - left.p95Ms;
      }
      return left.command.localeCompare(right.command);
    });

  return {
    generatedAt: new Date().toISOString(),
    totalSamples: samples.length,
    commandCount: summaries.length,
    summaries,
    recentSamples: samples.slice(-MAX_RECENT_SAMPLES).reverse()
  };
}

export function clearCommandLatencyReport(): void {
  if (samples.length === 0) {
    return;
  }

  samples.length = 0;
  persistSamples();
  emitReport();
}

export function subscribeCommandLatencyReport(
  listener: (report: CommandLatencyReport) => void
): () => void {
  listeners.add(listener);
  listener(getCommandLatencyReport());

  return () => {
    listeners.delete(listener);
  };
}

function summarizeCommand(
  command: string,
  commandSamples: CommandLatencySample[]
): CommandLatencySummary {
  const durations = commandSamples.map(effectiveDurationMs).sort((left, right) => left - right);
  const count = durations.length;
  const successCount = commandSamples.filter((sample) => sample.ok).length;
  const failureCount = count - successCount;
  const total = durations.reduce((sum, value) => sum + value, 0);
  const latestSample = commandSamples[commandSamples.length - 1];
  const lastDuration = latestSample ? effectiveDurationMs(latestSample) : 0;

  return {
    command,
    count,
    successCount,
    failureCount,
    p50Ms: roundToHundredths(percentile(durations, 50)),
    p95Ms: roundToHundredths(percentile(durations, 95)),
    avgMs: roundToHundredths(total / count),
    minMs: roundToHundredths(durations[0] ?? 0),
    maxMs: roundToHundredths(durations[count - 1] ?? 0),
    lastMs: roundToHundredths(lastDuration)
  };
}

function effectiveDurationMs(sample: CommandLatencySample): number {
  return sample.backendDurationMs ?? sample.roundTripMs;
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

function sanitizeDuration(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }

  return Math.max(value, 0);
}

function roundToHundredths(value: number): number {
  return Number(value.toFixed(2));
}

function emitReport(): void {
  if (listeners.size === 0) {
    return;
  }

  const report = getCommandLatencyReport();
  for (const listener of listeners) {
    listener(report);
  }
}

function normalizeRetentionPolicy(
  retentionDays: number,
  retentionMb: number
): CommandLatencyRetentionPolicy {
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
    // Ignore malformed telemetry cache; fresh samples will overwrite storage.
  }
}

function normalizeStoredSample(raw: unknown): CommandLatencySample | null {
  if (!raw || typeof raw !== "object") {
    return null;
  }

  const entry = raw as Partial<CommandLatencySample>;
  if (typeof entry.command !== "string") {
    return null;
  }
  if (typeof entry.ok !== "boolean") {
    return null;
  }
  if (typeof entry.roundTripMs !== "number") {
    return null;
  }
  if (typeof entry.recordedAt !== "string") {
    return null;
  }

  return {
    command: entry.command,
    ok: entry.ok,
    errorCode: typeof entry.errorCode === "string" ? entry.errorCode : undefined,
    requestId: typeof entry.requestId === "string" ? entry.requestId : undefined,
    roundTripMs: roundToHundredths(sanitizeDuration(entry.roundTripMs)),
    backendDurationMs:
      typeof entry.backendDurationMs === "number"
        ? roundToHundredths(sanitizeDuration(entry.backendDurationMs))
        : undefined,
    recordedAt: entry.recordedAt
  };
}

function persistSamples(): void {
  if (!storageAvailable()) {
    return;
  }

  const payload = JSON.stringify(samples);
  try {
    window.localStorage.setItem(STORAGE_KEY, payload);
  } catch {
    // If localStorage quota is lower than configured retention, drop oldest samples until it fits.
    while (samples.length > 0) {
      samples.shift();
      try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(samples));
        break;
      } catch {
        // Keep trimming until write succeeds or collection is empty.
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
