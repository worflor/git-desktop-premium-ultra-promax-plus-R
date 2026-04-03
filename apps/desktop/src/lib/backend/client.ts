import { invoke } from "@tauri-apps/api/core";
import type { CommandResult } from "@/lib/contracts/command";
import { recordCommandLatency } from "@/lib/telemetry/commandLatency";
import { recordCommandLifecycleEvent } from "@/lib/telemetry/commandLifecycle";

export interface CommandRecoveryState {
  command: string;
  payload: Record<string, unknown>;
  errorCode: string;
  errorMessage: string;
  retryRecommended: boolean;
  occurredAt: string;
  attempts: number;
  inProgress: boolean;
}

interface InternalCommandRecoveryState extends CommandRecoveryState {
  signature: string;
}

const recoveryListeners = new Set<(state: CommandRecoveryState | null) => void>();
let recoveryState: InternalCommandRecoveryState | null = null;

function ensureResult<T>(response: unknown): CommandResult<T> {
  if (typeof response === "object" && response !== null && "ok" in response) {
    return response as CommandResult<T>;
  }

  return {
    ok: false,
    error: {
      code: "command.invalid_response",
      message: "Backend response did not match command envelope."
    }
  };
}

export function subscribeCommandRecoveryState(
  listener: (state: CommandRecoveryState | null) => void
): () => void {
  recoveryListeners.add(listener);
  listener(toPublicRecoveryState(recoveryState));

  return () => {
    recoveryListeners.delete(listener);
  };
}

export function getCommandRecoveryState(): CommandRecoveryState | null {
  return toPublicRecoveryState(recoveryState);
}

export function dismissCommandRecoveryState(): void {
  if (!recoveryState) {
    return;
  }

  recoveryState = null;
  emitRecoveryState();
}

export async function retryLastFailedCommand(): Promise<CommandResult<unknown> | null> {
  if (!recoveryState) {
    return null;
  }

  const snapshot = recoveryState;
  recoveryState = {
    ...snapshot,
    inProgress: true
  };
  emitRecoveryState();

  recordCommandLifecycleEvent({
    type: "retry",
    command: snapshot.command,
    errorCode: snapshot.errorCode,
    message: snapshot.errorMessage,
    attempt: snapshot.attempts + 1
  });

  try {
    return await invokeCommand<unknown, Record<string, unknown>>(snapshot.command, snapshot.payload);
  } finally {
    if (recoveryState && recoveryState.signature === snapshot.signature && recoveryState.inProgress) {
      recoveryState = {
        ...recoveryState,
        inProgress: false
      };
      emitRecoveryState();
    }
  }
}

export async function invokeCommand<TData, TPayload extends Record<string, unknown>>(
  command: string,
  payload: TPayload
): Promise<CommandResult<TData>> {
  const payloadSnapshot = clonePayload(payload);
  const startedAt = performance.now();
  recordCommandLifecycleEvent({
    type: "start",
    command
  });

  try {
    const response = await invoke<unknown>(command, payload);
    const result = ensureResult<TData>(response);
    handleCommandOutcome(command, payloadSnapshot, result);
    recordCommandLifecycleEvent({
      type: result.ok ? "success" : "failure",
      command,
      durationMs: roundDuration(performance.now() - startedAt),
      requestId: result.meta?.requestId,
      errorCode: result.ok ? undefined : result.error.code,
      message: result.ok ? undefined : result.error.message,
      attempt: resolveAttempt(command, payloadSnapshot, result)
    });
    recordCommandLatency(command, result, performance.now() - startedAt);
    return result;
  } catch (error) {
    const result: CommandResult<TData> = {
      ok: false,
      error: {
        code: "command.invoke_failed",
        message: "Failed to invoke backend command.",
        details: {
          command,
          reason: String(error)
        },
        retryable: true
      }
    };

    handleCommandOutcome(command, payloadSnapshot, result);
    recordCommandLifecycleEvent({
      type: "failure",
      command,
      durationMs: roundDuration(performance.now() - startedAt),
      errorCode: result.error.code,
      message: result.error.message,
      attempt: resolveAttempt(command, payloadSnapshot, result)
    });
    recordCommandLatency(command, result, performance.now() - startedAt);
    return result;
  }
}

function handleCommandOutcome<T>(
  command: string,
  payload: Record<string, unknown>,
  result: CommandResult<T>
): void {
  const signature = buildRecoverySignature(command, payload);

  if (result.ok) {
    if (recoveryState && recoveryState.signature === signature) {
      recoveryState = null;
      emitRecoveryState();
    }
    return;
  }

  if (!shouldTrackFailure(result.error.code)) {
    return;
  }

  const attempts = recoveryState && recoveryState.signature === signature ? recoveryState.attempts + 1 : 1;
  recoveryState = {
    signature,
    command,
    payload: clonePayload(payload),
    errorCode: result.error.code,
    errorMessage: result.error.message,
    retryRecommended: result.error.retryable ?? false,
    occurredAt: new Date().toISOString(),
    attempts,
    inProgress: false
  };

  emitRecoveryState();
}

function resolveAttempt<T>(
  command: string,
  payload: Record<string, unknown>,
  result: CommandResult<T>
): number | undefined {
  if (result.ok || !recoveryState) {
    return undefined;
  }

  const signature = buildRecoverySignature(command, payload);
  if (recoveryState.signature !== signature) {
    return undefined;
  }

  return recoveryState.attempts;
}

function shouldTrackFailure(errorCode: string): boolean {
  return !errorCode.startsWith("validation.");
}

function emitRecoveryState(): void {
  if (recoveryListeners.size === 0) {
    return;
  }

  const snapshot = toPublicRecoveryState(recoveryState);
  for (const listener of recoveryListeners) {
    listener(snapshot);
  }
}

function toPublicRecoveryState(state: InternalCommandRecoveryState | null): CommandRecoveryState | null {
  if (!state) {
    return null;
  }

  return {
    command: state.command,
    payload: clonePayload(state.payload),
    errorCode: state.errorCode,
    errorMessage: state.errorMessage,
    retryRecommended: state.retryRecommended,
    occurredAt: state.occurredAt,
    attempts: state.attempts,
    inProgress: state.inProgress
  };
}

function buildRecoverySignature(command: string, payload: Record<string, unknown>): string {
  return `${command}:${stableStringify(payload)}`;
}

function stableStringify(value: unknown): string {
  try {
    return JSON.stringify(stabilizeValue(value));
  } catch {
    return String(value);
  }
}

function stabilizeValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(stabilizeValue);
  }

  if (value && typeof value === "object") {
    const source = value as Record<string, unknown>;
    const sortedKeys = Object.keys(source).sort();
    const output: Record<string, unknown> = {};
    for (const key of sortedKeys) {
      output[key] = stabilizeValue(source[key]);
    }
    return output;
  }

  return value;
}

function clonePayload(payload: Record<string, unknown>): Record<string, unknown> {
  try {
    return JSON.parse(JSON.stringify(payload)) as Record<string, unknown>;
  } catch {
    return { ...payload };
  }
}

function roundDuration(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }

  return Number(Math.max(value, 0).toFixed(2));
}
