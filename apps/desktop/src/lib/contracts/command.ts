export type CommandResult<T> =
  | {
      ok: true;
      data: T;
      meta?: ResponseMeta;
    }
  | {
      ok: false;
      error: CommandError;
      meta?: ResponseMeta;
    };

export interface ResponseMeta {
  requestId: string;
  durationMs: number;
  version: string;
}

export interface CommandError {
  code: string;
  message: string;
  details?: Record<string, unknown>;
  retryable?: boolean;
}

export const CONTRACT_VERSION = "v0";
