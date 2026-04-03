import { createEffect, createResource, createSignal, onCleanup, onMount, Show } from "solid-js";
import {
  useLayoutPreferences
} from "@/app/layout/LayoutPreferencesContext";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { getAppSettings, updateAiGuardrail, updateTelemetryRetention } from "@/lib/backend/commands";
import {
  clearCommandLatencyReport,
  getCommandLatencyReport,
  setCommandLatencyRetentionPolicy,
  subscribeCommandLatencyReport
} from "@/lib/telemetry/commandLatency";
import {
  getNavigationBindings,
  KEYBINDING_PROFILE_OPTIONS
} from "@/lib/ui/keybindings";
import { THEME_OPTIONS } from "@/lib/ui/theme";

export function SettingsPage() {
  const layout = useLayoutPreferences();
  const [settingsResult, { refetch }] = createResource(() => getAppSettings());
  const [guardrailValue, setGuardrailValue] = createSignal(0.5);
  const [retentionDays, setRetentionDays] = createSignal(30);
  const [retentionMb, setRetentionMb] = createSignal(128);
  const [actionMessage, setActionMessage] = createSignal<string | null>(null);
  const [actionError, setActionError] = createSignal<string | null>(null);
  const [latencyReport, setLatencyReport] = createSignal(getCommandLatencyReport());

  onMount(() => {
    const unsubscribe = subscribeCommandLatencyReport((report) => {
      setLatencyReport(report);
    });

    onCleanup(unsubscribe);
  });

  createEffect(() => {
    const settings = settingsResult.latest;
    if (!settings || !settings.ok) {
      return;
    }

    setGuardrailValue(settings.data.guardrailValue);
    setRetentionDays(settings.data.telemetryRetentionDays);
    setRetentionMb(settings.data.telemetryRetentionMb);
    setCommandLatencyRetentionPolicy(settings.data.telemetryRetentionDays, settings.data.telemetryRetentionMb);
  });

  const activeThemeLabel = () =>
    THEME_OPTIONS.find((option) => option.id === layout.themeId())?.label ?? layout.themeId();

  const activeKeybindingLabel = () =>
    KEYBINDING_PROFILE_OPTIONS.find((option) => option.id === layout.keybindingProfile())?.label ??
    layout.keybindingProfile();

  const onSaveGuardrail = async () => {
    setActionError(null);
    setActionMessage(null);

    const result = await updateAiGuardrail(guardrailValue());

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setGuardrailValue(result.data.guardrailValue);
    setActionMessage(`Saved guardrail profile: ${result.data.guardrailProfile}.`);
    void refetch();
  };

  const onSaveRetention = async () => {
    setActionError(null);
    setActionMessage(null);

    const result = await updateTelemetryRetention(retentionDays(), retentionMb());

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setRetentionDays(result.data.telemetryRetentionDays);
    setRetentionMb(result.data.telemetryRetentionMb);
    setActionMessage(
      `Saved retention policy: ${result.data.telemetryRetentionDays} days / ${result.data.telemetryRetentionMb} MB.`
    );
    void refetch();
  };

  const formatSampleTime = (value: string) => {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      return value;
    }

    return parsed.toLocaleTimeString();
  };

  return (
    <div class="feature-page">
      <header class="feature-header">
        <div class="feature-header-main">
          <p class="feature-kicker">Workspace Preferences</p>
          <h1 class="feature-title">Settings</h1>
          <p class="feature-summary">
            Interface behavior, safety protocols, and local diagnostics.
          </p>
        </div>
        <div class="feature-header-meta">
          <span class="feature-meta-pill">{activeThemeLabel()}</span>
          <span class="feature-meta-pill">{activeKeybindingLabel()}</span>
        </div>
      </header>

      <Show when={settingsResult.loading}>
        <LoadingStateSkeleton />
      </Show>

      <Show when={settingsResult.latest && !settingsResult.latest.ok}>
        <ErrorStateCard
          title="Settings load failed"
          body={settingsResult.latest && !settingsResult.latest.ok ? settingsResult.latest.error.message : "Unknown error"}
        />
      </Show>

      <Show when={settingsResult.latest?.ok}>
        <section class="info-grid settings-grid">
          <article class="state-card">
            <h3>Guardrails</h3>
            <p class="section-summary">Automated action assertion and safety thresholds.</p>
            <p>
              Active profile: {settingsResult.latest?.ok ? settingsResult.latest.data.guardrailProfile : "Balanced"} |
              Read-only: {String(settingsResult.latest?.ok ? settingsResult.latest.data.aiReadOnlyDefault : true)}
            </p>
            <input
              type="range"
              class="theme-slider"
              min="0"
              max="1"
              step="0.01"
              value={guardrailValue()}
              onInput={(event) => {
                setGuardrailValue(Number.parseFloat(event.currentTarget.value));
              }}
              onChange={() => {
                void onSaveGuardrail();
              }}
            />
          </article>

          <article class="state-card">
            <h3>Local Telemetry</h3>
            <p class="section-summary">Diagnostic retention and performance logs.</p>
            <p>Data remains local-only.</p>
            <div class="sync-grid">
              <input
                class="path-input"
                type="number"
                min="1"
                max="365"
                value={retentionDays()}
                onInput={(event) => {
                  setRetentionDays(Number.parseInt(event.currentTarget.value, 10) || 1);
                }}
                onBlur={() => {
                  void onSaveRetention();
                }}
                aria-label="Retention days"
              />
              <input
                class="path-input"
                type="number"
                min="16"
                max="4096"
                value={retentionMb()}
                onInput={(event) => {
                  setRetentionMb(Number.parseInt(event.currentTarget.value, 10) || 16);
                }}
                onBlur={() => {
                  void onSaveRetention();
                }}
                aria-label="Retention max MB"
              />
            </div>
          </article>

          <article class="state-card">
            <h3>Interface Calibration</h3>
            <p class="section-summary">Theme and shortcut architecture.</p>
            <div class="layout-control-field">
              <span>Theme</span>
              <select
                class="path-input"
                value={layout.themeId()}
                onChange={(event) => {
                  layout.setThemeId(event.currentTarget.value);
                  void layout.persistUiPreferences();
                }}
                aria-label="Theme"
              >
                {THEME_OPTIONS.map((option) => (
                  <option value={option.id}>{option.label}</option>
                ))}
              </select>
            </div>

            <div class="layout-control-field" style="margin-top: 8px;">
              <span>Keybinding profile</span>
              <select
                class="path-input"
                value={layout.keybindingProfile()}
                onChange={(event) => {
                  layout.setKeybindingProfile(event.currentTarget.value);
                  void layout.persistUiPreferences();
                }}
                aria-label="Keybinding profile"
              >
                {KEYBINDING_PROFILE_OPTIONS.map((option) => (
                  <option value={option.id}>{option.label}</option>
                ))}
              </select>
            </div>

            <label class="layout-checkbox-field" style="margin-top: 8px;">
              <input
                type="checkbox"
                checked={layout.utilityDrawerExpanded()}
                onChange={(event) => {
                  layout.setUtilityDrawerExpanded(event.currentTarget.checked);
                  void layout.persistLayoutPreferences();
                }}
              />
              <span>Auto-expand logs</span>
            </label>
          </article>

          <article class="state-card state-card-wide">
            <h3>Navigation Guide</h3>
            <p class="section-summary">Core shortcuts for the active profile.</p>
            <div class="keybinding-preview-card">
              <ul class="keybinding-preview-list" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px;">
                {getNavigationBindings(layout.keybindingProfile()).map((binding) => (
                  <li class="keybinding-preview-row">
                    <span>{binding.label}</span>
                    <span class="shortcut-hint">{binding.keys}</span>
                  </li>
                ))}
              </ul>
            </div>
          </article>

          <article class="state-card state-card-wide">
            <h3>Command Diagnostics</h3>
            <p class="section-summary">Latency trends and operation logs.</p>
            <p>
              Captured samples: {latencyReport().totalSamples} across {latencyReport().commandCount} command(s).
            </p>
            <div class="inline-actions">
              <button class="primary-btn" onClick={() => setLatencyReport(getCommandLatencyReport())}>
                Refresh Snapshot
              </button>
              <button
                class="primary-btn"
                disabled={latencyReport().totalSamples === 0}
                onClick={() => clearCommandLatencyReport()}
              >
                Clear Samples
              </button>
            </div>

            <Show
              when={latencyReport().summaries.length > 0}
              fallback={<p>No command timings captured yet. Run normal actions to populate diagnostics.</p>}
            >
              <div class="telemetry-summary-list">
                {latencyReport().summaries.slice(0, 10).map((summary) => (
                  <div class="telemetry-summary-row">
                    <div class="telemetry-summary-command">{summary.command}</div>
                    <div class="telemetry-summary-metrics">
                      p50 {summary.p50Ms.toFixed(2)} ms | p95 {summary.p95Ms.toFixed(2)} ms | avg {summary.avgMs.toFixed(2)} ms
                    </div>
                    <div class="telemetry-summary-meta">
                      success {summary.successCount}/{summary.count} | range {summary.minMs.toFixed(2)}-{summary.maxMs.toFixed(2)} ms
                    </div>
                  </div>
                ))}
              </div>
            </Show>

            <Show when={latencyReport().recentSamples.length > 0}>
              <details class="telemetry-recent-details">
                <summary>Recent Operations</summary>
                <ul class="telemetry-recent-list">
                  {latencyReport().recentSamples.map((sample) => (
                    <li>
                      {formatSampleTime(sample.recordedAt)} | {sample.command} |{" "}
                      {(sample.backendDurationMs ?? sample.roundTripMs).toFixed(2)} ms | {sample.ok ? "ok" : sample.errorCode}
                    </li>
                  ))}
                </ul>
              </details>
            </Show>
          </article>
        </section>
      </Show>

      <Show when={actionMessage()}>
        {(message) => (
          <section class="state-card">
            <p>{message()}</p>
          </section>
        )}
      </Show>

      <Show when={actionError()}>
        {(message) => <ErrorStateCard title="Settings update failed" body={message()} />}
      </Show>
    </div>
  );
}
