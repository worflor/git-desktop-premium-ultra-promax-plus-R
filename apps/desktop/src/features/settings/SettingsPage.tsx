import { createEffect, createResource, createSignal, onCleanup, onMount, Show } from "solid-js";
import {
  SIDEBAR_WIDTH_MAX_PX,
  SIDEBAR_WIDTH_MIN_PX,
  UTILITY_DRAWER_HEIGHT_MAX_PX,
  UTILITY_DRAWER_HEIGHT_MIN_PX,
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
  const [actionRunning, setActionRunning] = createSignal(false);
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
    setActionRunning(true);
    setActionError(null);
    setActionMessage(null);

    const result = await updateAiGuardrail(guardrailValue());
    setActionRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setGuardrailValue(result.data.guardrailValue);
    setActionMessage(`Saved guardrail profile: ${result.data.guardrailProfile}.`);
    void refetch();
  };

  const onSaveRetention = async () => {
    setActionRunning(true);
    setActionError(null);
    setActionMessage(null);

    const result = await updateTelemetryRetention(retentionDays(), retentionMb());
    setActionRunning(false);

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

  const onSaveCustomization = async () => {
    setActionRunning(true);
    setActionError(null);
    setActionMessage(null);

    const uiSaved = await layout.persistUiPreferences();
    const uiError = uiSaved ? null : layout.error();
    const layoutSaved = await layout.persistLayoutPreferences();
    const layoutError = layoutSaved ? null : layout.error();
    setActionRunning(false);

    if (!uiSaved || !layoutSaved) {
      setActionError(uiError ?? layoutError ?? "Failed to save customization preferences.");
      return;
    }

    setActionMessage(
      `Saved customization: ${activeThemeLabel()} theme, ${activeKeybindingLabel()} shortcuts, ${layout.sidebarPosition()} sidebar (${layout.sidebarWidthPx()} px), and ${layout.utilityDrawerHeightPx()} px drawer.`
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
            Configure interface behavior, safety defaults, and diagnostics with concise, local-first controls.
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
            <h3>Guardrail Slider</h3>
            <p class="section-summary">Control how assertive automated actions can be while keeping repository safety intact.</p>
            <p>
              Active profile: {settingsResult.latest?.ok ? settingsResult.latest.data.guardrailProfile : "Balanced"} |
              Read-only default: {String(settingsResult.latest?.ok ? settingsResult.latest.data.aiReadOnlyDefault : true)}
            </p>
            <input
              type="range"
              class="theme-slider"
              min="0"
              max="1"
              step="0.01"
              value={guardrailValue()}
              onInput={(event) => setGuardrailValue(Number.parseFloat(event.currentTarget.value))}
            />
            <p>Value: {guardrailValue().toFixed(2)}</p>
            <button class="primary-btn" disabled={actionRunning()} onClick={() => void onSaveGuardrail()}>
              {actionRunning() ? "Saving..." : "Save Guardrail"}
            </button>
          </article>

          <article class="state-card">
            <h3>Telemetry Retention</h3>
            <p class="section-summary">Keep only the local diagnostics you still need for performance troubleshooting.</p>
            <p>Telemetry is local-only by default.</p>
            <div class="sync-grid">
              <input
                class="path-input"
                type="number"
                min="1"
                max="365"
                value={retentionDays()}
                onInput={(event) => setRetentionDays(Number.parseInt(event.currentTarget.value, 10) || 1)}
                aria-label="Retention days"
              />
              <input
                class="path-input"
                type="number"
                min="16"
                max="4096"
                value={retentionMb()}
                onInput={(event) => setRetentionMb(Number.parseInt(event.currentTarget.value, 10) || 16)}
                aria-label="Retention max MB"
              />
            </div>
            <button class="primary-btn" disabled={actionRunning()} onClick={() => void onSaveRetention()}>
              {actionRunning() ? "Saving..." : "Save Retention"}
            </button>
          </article>

          <article class="state-card state-card-wide">
            <h3>Layout and Keybindings</h3>
            <p class="section-summary">Theme, shortcuts, and panel behavior apply instantly while preserving one compact workspace layout.</p>
            <p>Compact density is enforced by product policy.</p>
            <div class="sync-grid">
              <label class="layout-control-field">
                <span>Theme</span>
                <select
                  class="path-input"
                  value={layout.themeId()}
                  onChange={(event) => layout.setThemeId(event.currentTarget.value)}
                  aria-label="Theme"
                >
                  {THEME_OPTIONS.map((option) => (
                    <option value={option.id}>{option.label}</option>
                  ))}
                </select>
                <small class="layout-control-help">
                  {THEME_OPTIONS.find((option) => option.id === layout.themeId())?.description}
                </small>
              </label>

              <label class="layout-control-field">
                <span>Keybinding profile</span>
                <select
                  class="path-input"
                  value={layout.keybindingProfile()}
                  onChange={(event) => layout.setKeybindingProfile(event.currentTarget.value)}
                  aria-label="Keybinding profile"
                >
                  {KEYBINDING_PROFILE_OPTIONS.map((option) => (
                    <option value={option.id}>{option.label}</option>
                  ))}
                </select>
                <small class="layout-control-help">
                  {
                    KEYBINDING_PROFILE_OPTIONS.find(
                      (option) => option.id === layout.keybindingProfile()
                    )?.description
                  }
                </small>
              </label>

              <label class="layout-control-field">
                <span>Sidebar width (px)</span>
                <input
                  class="path-input"
                  type="number"
                  min={SIDEBAR_WIDTH_MIN_PX}
                  max={SIDEBAR_WIDTH_MAX_PX}
                  value={layout.sidebarWidthPx()}
                  onInput={(event) => {
                    const value = Number.parseInt(event.currentTarget.value, 10);
                    if (!Number.isNaN(value)) {
                      layout.setSidebarWidthPx(value);
                    }
                  }}
                  aria-label="Sidebar width"
                />
              </label>

              <label class="layout-control-field">
                <span>Sidebar position</span>
                <select
                  class="path-input"
                  value={layout.sidebarPosition()}
                  onChange={(event) => layout.setSidebarPosition(event.currentTarget.value === "right" ? "right" : "left")}
                  aria-label="Sidebar position"
                >
                  <option value="left">Left</option>
                  <option value="right">Right</option>
                </select>
              </label>

              <label class="layout-checkbox-field">
                <input
                  type="checkbox"
                  checked={layout.utilityDrawerExpanded()}
                  onChange={(event) => layout.setUtilityDrawerExpanded(event.currentTarget.checked)}
                />
                <span>Open command drawer by default</span>
              </label>

              <label class="layout-control-field">
                <span>Utility drawer height (px)</span>
                <input
                  class="path-input"
                  type="number"
                  min={UTILITY_DRAWER_HEIGHT_MIN_PX}
                  max={UTILITY_DRAWER_HEIGHT_MAX_PX}
                  value={layout.utilityDrawerHeightPx()}
                  onInput={(event) => {
                    const value = Number.parseInt(event.currentTarget.value, 10);
                    if (!Number.isNaN(value)) {
                      layout.setUtilityDrawerHeightPx(value);
                    }
                  }}
                  aria-label="Utility drawer height"
                />
              </label>

              <div class="keybinding-preview-card">
                <span class="layout-control-help">Navigation shortcuts</span>
                <ul class="keybinding-preview-list">
                  {getNavigationBindings(layout.keybindingProfile()).map((binding) => (
                    <li class="keybinding-preview-row">
                      <span>{binding.label}</span>
                      <span class="shortcut-hint">{binding.keys}</span>
                    </li>
                  ))}
                </ul>
              </div>
            </div>
            <button
              class="primary-btn"
              disabled={actionRunning() || layout.loading() || layout.saving()}
              onClick={() => void onSaveCustomization()}
            >
              {actionRunning() || layout.saving() ? "Saving..." : "Save Customization"}
            </button>

            <Show when={layout.error() && !actionError()}>
              {(message) => <p class="inline-error">{message()}</p>}
            </Show>
          </article>

          <article class="state-card state-card-wide">
            <h3>Command Diagnostics</h3>
            <p class="section-summary">Inspect command latency trends and recent operations without leaving the settings flow.</p>
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
