import { createEffect, createResource, createSignal, onCleanup, onMount, Show } from "solid-js";
import {
  useLayoutPreferences
} from "@/app/layout/LayoutPreferencesContext";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import {
  checkForAppUpdate,
  getAppSettings,
  installAppUpdate,
  updateAiGuardrail,
  updateCrashReporting,
  updateTelemetryRetention,
  updateUpdateChannel
} from "@/lib/backend/commands";
import type { AppUpdateCheckData } from "@/lib/backend/dtos";
import {
  clearCommandLatencyReport,
  getCommandLatencyReport,
  setCommandLatencyRetentionPolicy,
  subscribeCommandLatencyReport
} from "@/lib/telemetry/commandLatency";
import {
  clearDiffRenderMetricsReport,
  getDiffRenderMetricsReport,
  setDiffRenderMetricsRetentionPolicy,
  subscribeDiffRenderMetricsReport
} from "@/lib/telemetry/diffRenderMetrics";
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
  const [updateChannel, setUpdateChannel] = createSignal<"stable" | "beta">("stable");
  const [crashReportingEnabled, setCrashReportingEnabled] = createSignal(false);
  const [updateCheckResult, setUpdateCheckResult] = createSignal<AppUpdateCheckData | null>(null);
  const [updateActionBusy, setUpdateActionBusy] = createSignal(false);
  const [actionMessage, setActionMessage] = createSignal<string | null>(null);
  const [actionError, setActionError] = createSignal<string | null>(null);
  const [latencyReport, setLatencyReport] = createSignal(getCommandLatencyReport());
  const [diffRenderReport, setDiffRenderReport] = createSignal(getDiffRenderMetricsReport());

  onMount(() => {
    const unsubscribeCommandLatency = subscribeCommandLatencyReport((report) => {
      setLatencyReport(report);
    });
    const unsubscribeDiffRender = subscribeDiffRenderMetricsReport((report) => {
      setDiffRenderReport(report);
    });

    onCleanup(() => {
      unsubscribeCommandLatency();
      unsubscribeDiffRender();
    });
  });

  createEffect(() => {
    const settings = settingsResult.latest;
    if (!settings || !settings.ok) {
      return;
    }

    setGuardrailValue(settings.data.guardrailValue);
    setRetentionDays(settings.data.telemetryRetentionDays);
    setRetentionMb(settings.data.telemetryRetentionMb);
    setUpdateChannel(settings.data.updateChannel === "beta" ? "beta" : "stable");
    setCrashReportingEnabled(settings.data.crashReportingEnabled);
    setCommandLatencyRetentionPolicy(settings.data.telemetryRetentionDays, settings.data.telemetryRetentionMb);
    setDiffRenderMetricsRetentionPolicy(settings.data.telemetryRetentionDays, settings.data.telemetryRetentionMb);
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

  const onSaveUpdateChannel = async (channel: "stable" | "beta") => {
    setActionError(null);
    setActionMessage(null);

    const result = await updateUpdateChannel(channel);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setUpdateChannel(result.data.updateChannel === "beta" ? "beta" : "stable");
    setUpdateCheckResult(null);
    setActionMessage(`Saved update channel: ${result.data.updateChannel}.`);
    void refetch();
  };

  const onSaveCrashReporting = async (enabled: boolean) => {
    setActionError(null);
    setActionMessage(null);

    const result = await updateCrashReporting(enabled);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setCrashReportingEnabled(result.data.crashReportingEnabled);
    setActionMessage(
      `Crash reporting ${result.data.crashReportingEnabled ? "enabled" : "disabled"}.`
    );
    void refetch();
  };

  const onCheckForUpdates = async () => {
    setActionError(null);
    setActionMessage(null);
    setUpdateActionBusy(true);

    try {
      const result = await checkForAppUpdate();

      if (!result.ok) {
        setActionError(result.error.message);
        return;
      }

      setUpdateCheckResult(result.data);
      if (result.data.updateAvailable) {
        setActionMessage(
          `Update ${result.data.latestVersion ?? ""} is available on ${result.data.channel}.`
        );
      } else {
        setActionMessage(`No updates found on ${result.data.channel}.`);
      }
    } finally {
      setUpdateActionBusy(false);
    }
  };

  const onInstallUpdate = async () => {
    setActionError(null);
    setActionMessage(null);
    setUpdateActionBusy(true);

    try {
      const result = await installAppUpdate();

      if (!result.ok) {
        setActionError(result.error.message);
        return;
      }

      setActionMessage(result.data.message);
      if (result.data.installed) {
        setUpdateCheckResult((current) =>
          current
            ? {
                ...current,
                updateAvailable: false,
                latestVersion: result.data.targetVersion,
                checkedAt: result.data.checkedAt
              }
            : null
        );
      }
    } finally {
      setUpdateActionBusy(false);
    }
  };

  const formatSampleTime = (value: string) => {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      return value;
    }

    return parsed.toLocaleTimeString();
  };

  const formatTimestamp = (value: string) => {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      return value;
    }

    return parsed.toLocaleString();
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
            <p class="section-summary">Theme and aesthetic architecture.</p>
            <div class="layout-control-field">
              <span>Primary Engine</span>
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
            
            <p class="theme-description-yappery" style="margin-top: 12px; font-size: 11px; color: var(--text-muted); font-style: italic; border-left: 2px solid rgba(var(--chrome-border-rgb), 0.2); padding-left: 8px;">
              {THEME_OPTIONS.find(t => t.id === layout.themeId())?.description}
            </p>
          </article>

          <article class="state-card state-card-wide">
            <h3>Navigation & Surface Guide</h3>
            <p class="section-summary">Keyboard architecture and interface behavior.</p>
            
            <div class="layout-control-field" style="margin-bottom: 24px;">
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

            <h4 style="margin-bottom: 8px; font-size: 10px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--text-muted); opacity: 0.8;">Behavioral Dynamics</h4>
            <label class="layout-checkbox-field" style="display: flex; align-items: center; gap: 8px; margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px solid rgba(var(--chrome-border-rgb), 0.1);">
              <input
                type="checkbox"
                checked={layout.utilityDrawerExpanded()}
                onChange={(event) => {
                  layout.setUtilityDrawerExpanded(event.currentTarget.checked);
                  void layout.persistLayoutPreferences();
                }}
              />
              <span>Auto-expand operation logs</span>
            </label>
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

          <article class="state-card state-card-wide">
            <h3>Diff Render Diagnostics</h3>
            <p class="section-summary">First-paint, sustained scroll FPS, memory, and fallback-rate telemetry.</p>
            <p>
              Sessions: {diffRenderReport().totalSessions} | Fallbacks: {diffRenderReport().fallbackCount} | Fallback rate: {(diffRenderReport().fallbackRate * 100).toFixed(2)}%
            </p>
            <p>
              First paint p95: {diffRenderReport().firstPaintP95Ms.toFixed(2)} ms | Scroll FPS p50: {diffRenderReport().scrollFpsP50.toFixed(2)} | Memory p95: {diffRenderReport().memoryP95Mb.toFixed(2)} MB
            </p>

            <div class="inline-actions">
              <button class="primary-btn" onClick={() => setDiffRenderReport(getDiffRenderMetricsReport())}>
                Refresh Diff Metrics
              </button>
              <button
                class="primary-btn"
                disabled={diffRenderReport().totalSessions === 0}
                onClick={() => clearDiffRenderMetricsReport()}
              >
                Clear Diff Metrics
              </button>
            </div>

            <Show
              when={diffRenderReport().modeSummaries.length > 0}
              fallback={<p>No diff render sessions captured yet. Open and scroll file diffs to populate this panel.</p>}
            >
              <div class="telemetry-summary-list">
                {diffRenderReport().modeSummaries.map((summary) => (
                  <div class="telemetry-summary-row">
                    <div class="telemetry-summary-command">mode {summary.rendererMode}</div>
                    <div class="telemetry-summary-metrics">
                      first-paint p50/p95 {summary.firstPaintP50Ms.toFixed(2)}/{summary.firstPaintP95Ms.toFixed(2)} ms | scroll p50/p95 {summary.scrollFpsP50.toFixed(2)}/{summary.scrollFpsP95.toFixed(2)} fps
                    </div>
                    <div class="telemetry-summary-meta">
                      sessions {summary.sessionCount} | fallback rate {(summary.fallbackRate * 100).toFixed(2)}% | memory p50/p95 {summary.memoryP50Mb.toFixed(2)}/{summary.memoryP95Mb.toFixed(2)} MB
                    </div>
                  </div>
                ))}
              </div>
            </Show>
          </article>

          <article class="state-card state-card-wide">
            <h3>Release Channel</h3>
            <p class="section-summary">Update feed and crash diagnostics policy.</p>
            <div class="layout-control-field">
              <span>Channel</span>
              <select
                class="path-input"
                value={updateChannel()}
                onChange={(event) => {
                  const next = event.currentTarget.value === "beta" ? "beta" : "stable";
                  setUpdateChannel(next);
                  void onSaveUpdateChannel(next);
                }}
                aria-label="Update channel"
              >
                <option value="stable">Stable</option>
                <option value="beta">Beta</option>
              </select>
            </div>

            <label class="layout-checkbox-field" style="display: flex; align-items: center; gap: 8px; margin-top: 12px;">
              <input
                type="checkbox"
                checked={crashReportingEnabled()}
                onChange={(event) => {
                  const enabled = event.currentTarget.checked;
                  setCrashReportingEnabled(enabled);
                  void onSaveCrashReporting(enabled);
                }}
              />
              <span>Enable local crash-report artifacts</span>
            </label>

            <div class="inline-actions" style="margin-top: 12px;">
              <button
                class="primary-btn"
                disabled={updateActionBusy()}
                onClick={() => {
                  void onCheckForUpdates();
                }}
              >
                {updateActionBusy() ? "Working..." : "Check for Updates"}
              </button>
              <button
                class="primary-btn"
                disabled={updateActionBusy() || !updateCheckResult()?.updateAvailable}
                onClick={() => {
                  void onInstallUpdate();
                }}
              >
                Install Available Update
              </button>
            </div>

            <Show when={updateCheckResult()}>
              {(status) => (
                <div style="margin-top: 12px; font-size: 12px; color: var(--text-muted); border-top: 1px solid rgba(var(--chrome-border-rgb), 0.2); padding-top: 10px;">
                  <p>Last checked: {formatTimestamp(status().checkedAt)}</p>
                  <p>Current version: {status().currentVersion}</p>
                  <Show when={status().updateAvailable} fallback={<p>No update available for the selected channel.</p>}>
                    <p>Available version: {status().latestVersion ?? "unknown"}</p>
                    <Show when={status().endpoint}>
                      {(endpoint) => <p>Endpoint: {endpoint()}</p>}
                    </Show>
                  </Show>
                </div>
              )}
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
