import { createSignal, onCleanup, onMount, Show } from "solid-js";
import {
  dismissCommandRecoveryState,
  getCommandRecoveryState,
  retryLastFailedCommand,
  subscribeCommandRecoveryState,
  type CommandRecoveryState
} from "@/lib/backend/client";

export function CommandRecoveryBanner() {
  const [recoveryState, setRecoveryState] = createSignal<CommandRecoveryState | null>(
    getCommandRecoveryState()
  );

  onMount(() => {
    const unsubscribe = subscribeCommandRecoveryState((state) => {
      setRecoveryState(state);
    });

    onCleanup(unsubscribe);
  });

  const onRetry = async () => {
    await retryLastFailedCommand();
  };

  return (
    <Show when={recoveryState()}>
      {(state) => (
        <section class="command-recovery-banner" role="status" aria-live="polite">
          <div class="command-recovery-copy">
            <strong>Recoverable command failure</strong>
            <span>
              {state().command} failed with {state().errorCode}.
            </span>
            <span>{state().errorMessage}</span>
            <span>
              Attempts: {state().attempts}. {state().retryRecommended ? "Retry is recommended." : "Retry is available."}
            </span>
          </div>
          <div class="command-recovery-actions">
            <button class="primary-btn" disabled={state().inProgress} onClick={() => void onRetry()}>
              {state().inProgress ? "Retrying..." : "Retry Last Command"}
            </button>
            <button class="primary-btn" onClick={() => dismissCommandRecoveryState()}>
              Dismiss
            </button>
          </div>
        </section>
      )}
    </Show>
  );
}
