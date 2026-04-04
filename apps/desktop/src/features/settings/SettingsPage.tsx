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
import { Select } from "@/components/primitives/Select";

const GUARDRAIL_STAGE_VALUES = [0.125, 0.375, 0.625, 0.875] as const;
const GUARDRAIL_STAGE_META = [
  { label: "Loose", phrase: "Permissive review mode", color: "#4ad399" },
  { label: "Balanced", phrase: "Practical everyday protections", color: "#7ab8ff" },
  { label: "Strict", phrase: "Tighter safety checks", color: "#ef7c75" },
  { label: "Paranoid", phrase: "Maximum lock-down safeguards", color: "#b280ff" }
] as const;

function clampGuardrailStage(stage: number): number {
  return Math.max(0, Math.min(GUARDRAIL_STAGE_VALUES.length - 1, stage));
}

function guardrailStageFromValue(value: number): number {
  if (value < 0.25) {
    return 0;
  }
  if (value <= 0.5) {
    return 1;
  }
  if (value < 0.75) {
    return 2;
  }
  return 3;
}

function guardrailDisplayLabelFromProfile(profile: string): string {
  return profile;
}

export function SettingsPage() {
  const layout = useLayoutPreferences();
  const [settingsResult] = createResource(() => getAppSettings());
  const [settingsInitialized, setSettingsInitialized] = createSignal(false);
  const [guardrailValue, setGuardrailValue] = createSignal(0.5);
  const [guardrailStage, setGuardrailStage] = createSignal(guardrailStageFromValue(0.5));
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
  const [topCardsCompact, setTopCardsCompact] = createSignal(false);
  const [topCardsUltraCompact, setTopCardsUltraCompact] = createSignal(false);

  let topCardsRowRef: HTMLDivElement | undefined;
  let guardrailsCardRef: HTMLElement | undefined;
  let calibrationCardRef: HTMLElement | undefined;

  const measureTextWidth = (context: CanvasRenderingContext2D, font: string, value: string) => {
    context.font = font;
    return Math.ceil(context.measureText(value).width);
  };

  const recalculateTopCardDensity = () => {
    if (!topCardsRowRef || typeof document === "undefined") {
      return;
    }

    const context = document.createElement("canvas").getContext("2d");
    if (!context) {
      return;
    }

    const sampleCard = guardrailsCardRef ?? calibrationCardRef;
    if (!sampleCard) {
      return;
    }

    const cardStyle = getComputedStyle(sampleCard);
    const headingStyle = getComputedStyle(sampleCard.querySelector("h3") ?? sampleCard);
    const controlSource = calibrationCardRef?.querySelector(".path-input") ?? sampleCard;
    const controlStyle = getComputedStyle(controlSource);

    const bodyFont = cardStyle.font;
    const headingFont = headingStyle.font;
    const controlFont = controlStyle.font;
    const guardrailStatusSamples = GUARDRAIL_STAGE_META.map(
      (stage) => `${stage.phrase} | Read-only: Disabled`
    );
    const maxGuardrailStatusWidth = Math.max(
      ...guardrailStatusSamples.map((sample) => measureTextWidth(context, bodyFont, sample))
    );
    const maxThemeLabelWidth = THEME_OPTIONS.reduce(
      (maxWidth, option) => Math.max(maxWidth, measureTextWidth(context, controlFont, option.label)),
      0
    );

    const measureScenario = (shrinkFactor: number, sidePadding: number) => {
      const guardrailTextWidth = Math.max(
        measureTextWidth(context, headingFont, "Guardrails"),
        measureTextWidth(context, bodyFont, "Automated action assertion and safety thresholds."),
        maxGuardrailStatusWidth
      );

      const telemetryTextWidth = Math.max(
        measureTextWidth(context, headingFont, "Local Telemetry"),
        measureTextWidth(context, bodyFont, "Diagnostic retention and performance logs."),
        measureTextWidth(context, bodyFont, "Data remains local-only.")
      );

      const interfaceTextWidth = Math.max(
        measureTextWidth(context, headingFont, "Theme"),
        measureTextWidth(context, bodyFont, "Theme and aesthetic architecture.")
      );

      const guardrailRequired = Math.max(Math.ceil(guardrailTextWidth * shrinkFactor + sidePadding), 146);
      const telemetryRequired = Math.max(Math.ceil(telemetryTextWidth * shrinkFactor + sidePadding), 168);
      const interfaceRequired = Math.max(
        Math.ceil(interfaceTextWidth * shrinkFactor + sidePadding),
        Math.ceil(maxThemeLabelWidth * shrinkFactor + (sidePadding + 30))
      );

      return Math.max(guardrailRequired, telemetryRequired, interfaceRequired);
    };

    const normalRequired = measureScenario(1, 22);
    const compactRequired = measureScenario(0.93, 18);

    const rowStyle = getComputedStyle(topCardsRowRef);
    const gapSource = rowStyle.columnGap === "normal" ? rowStyle.gap : rowStyle.columnGap;
    const gap = Number.parseFloat(gapSource) || 10;
    const availablePerCard = (topCardsRowRef.clientWidth - gap * 2) / 3;

    if (availablePerCard >= normalRequired) {
      setTopCardsCompact(false);
      setTopCardsUltraCompact(false);
      return;
    }

    if (availablePerCard >= compactRequired) {
      setTopCardsCompact(true);
      setTopCardsUltraCompact(false);
      return;
    }

    setTopCardsCompact(true);
    setTopCardsUltraCompact(true);
  };

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

  onMount(() => {
    recalculateTopCardDensity();

    if (!topCardsRowRef) {
      return;
    }

    if (typeof ResizeObserver !== "undefined") {
      const resizeObserver = new ResizeObserver(() => {
        recalculateTopCardDensity();
      });

      resizeObserver.observe(topCardsRowRef);

      onCleanup(() => {
        resizeObserver.disconnect();
      });

      return;
    }

    const onResize = () => {
      recalculateTopCardDensity();
    };

    window.addEventListener("resize", onResize);
    onCleanup(() => {
      window.removeEventListener("resize", onResize);
    });
  });

  createEffect(() => {
    const latest = settingsResult.latest;
    if (latest) {
      setSettingsInitialized(true);
    }

    layout.themeId();

    setTimeout(() => {
      recalculateTopCardDensity();
    }, 0);
  });

  createEffect(() => {
    const settings = settingsResult.latest;
    if (!settings || !settings.ok) {
      return;
    }

    setGuardrailValue(settings.data.guardrailValue);
    setGuardrailStage(guardrailStageFromValue(settings.data.guardrailValue));
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

  const guardrailModePhrase = () => GUARDRAIL_STAGE_META[guardrailStage()]?.phrase ?? "Practical everyday protections";

  const guardrailSliderFillPercent = () => {
    const normalized = guardrailStage() / (GUARDRAIL_STAGE_VALUES.length - 1);
    return `${Math.max(0, Math.min(100, normalized * 100))}%`;
  };

  const guardrailSliderColor = () => GUARDRAIL_STAGE_META[guardrailStage()]?.color ?? "#7ab8ff";

  const guardrailSliderStyle = () =>
    `--guardrail-fill-percent: ${guardrailSliderFillPercent()}; --guardrail-stage-color: ${guardrailSliderColor()};`;

  const onSaveGuardrail = async () => {
    setActionError(null);

    const result = await updateAiGuardrail(guardrailValue());

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setGuardrailValue(result.data.guardrailValue);
    setGuardrailStage(guardrailStageFromValue(result.data.guardrailValue));
    setActionMessage(`Saved guardrail profile: ${guardrailDisplayLabelFromProfile(result.data.guardrailProfile)}.`);
  };

  const onSaveRetention = async () => {
    setActionError(null);

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
  };

  const onSaveUpdateChannel = async (channel: "stable" | "beta") => {
    setActionError(null);

    const result = await updateUpdateChannel(channel);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setUpdateChannel(result.data.updateChannel === "beta" ? "beta" : "stable");
    setUpdateCheckResult(null);
    setActionMessage(`Saved update channel: ${result.data.updateChannel}.`);
  };

  const onSaveCrashReporting = async (enabled: boolean) => {
    setActionError(null);

    const result = await updateCrashReporting(enabled);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setCrashReportingEnabled(result.data.crashReportingEnabled);
    setActionMessage(
      `Crash reporting ${result.data.crashReportingEnabled ? "enabled" : "disabled"}.`
    );
  };

  const onCheckForUpdates = async () => {
    setActionError(null);
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
    <div class="feature-page settings-page">
      <header class="feature-header">
        <div class="feature-header-main">
          <p class="feature-kicker">Workspace Preferences</p>
          <p class="feature-summary">
            Configure global aesthetics, interface dynamics, and core operational safeguards for the entire workspace.
          </p>
        </div>
        <div class="feature-header-meta">
          <span class="feature-meta-pill">{activeThemeLabel()}</span>
          <span class="feature-meta-pill">{activeKeybindingLabel()}</span>
        </div>
      </header>

      <Show when={settingsResult.loading && !settingsInitialized()}>
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
          <div
            ref={topCardsRowRef}
            class="settings-top-row"
            classList={{
              "is-compact": topCardsCompact(),
              "is-ultra-compact": topCardsUltraCompact()
            }}
          >
            <article ref={guardrailsCardRef} class="state-card settings-top-card">
              <h3>Guardrails</h3>
              <p class="section-summary">Automated action assertion and safety thresholds.</p>
              <p class="settings-fit-line">
                {guardrailModePhrase()} |
                Read-only: {settingsResult.latest?.ok && settingsResult.latest.data.aiReadOnlyDefault ? "Enabled" : "Disabled"}
              </p>
              <input
                type="range"
                class="theme-slider guardrail-slider"
                min="0"
                max={GUARDRAIL_STAGE_VALUES.length - 1}
                step="1"
                list="guardrail-stage-ticks"
                style={guardrailSliderStyle()}
                value={guardrailStage()}
                onInput={(event) => {
                  const parsed = Number.parseInt(event.currentTarget.value, 10);
                  const stage = clampGuardrailStage(Number.isNaN(parsed) ? 0 : parsed);
                  setGuardrailStage(stage);
                  setGuardrailValue(GUARDRAIL_STAGE_VALUES[stage] ?? 0.5);
                }}
                onChange={() => {
                  void onSaveGuardrail();
                }}
              />
              <datalist id="guardrail-stage-ticks">
                {GUARDRAIL_STAGE_META.map((_, index) => (
                  <option value={String(index)} />
                ))}
              </datalist>
              <div class="guardrail-stage-labels" aria-hidden="true">
                {GUARDRAIL_STAGE_META.map((stage, index) => (
                  <span class={`guardrail-stage-label ${guardrailStage() === index ? "is-active" : ""}`}>
                    {stage.label}
                  </span>
                ))}
              </div>
            </article>

            <article ref={calibrationCardRef} class="state-card settings-top-card">
              <h3>Theme</h3>
              <p class="section-summary">Theme and aesthetic architecture.</p>
              <div class="layout-control-field">
                <Select
                  value={layout.themeId()}
                  options={THEME_OPTIONS}
                  onChange={(id) => {
                    layout.setThemeId(id);
                    void layout.persistUiPreferences();
                  }}
                  ariaLabel="Theme"
                />
              </div>

              <p class="theme-description-yappery">{THEME_OPTIONS.find((t) => t.id === layout.themeId())?.description}</p>
            </article>

            <article class="state-card settings-top-card">
              <h3>Local Telemetry</h3>
              <p class="section-summary">Diagnostic retention and performance logs.</p>
              <div class="sync-grid settings-retention-grid">
                <div class="input-with-unit">
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
                  <span class="unit">days</span>
                </div>
                <div class="input-with-unit">
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
                  <span class="unit">MB</span>
                </div>
              </div>
              <p class="settings-fit-line">Data remains local-only.</p>
            </article>
          </div>

          <article class="state-card state-card-wide settings-nav-dynamics-card">
            <h3>Navigation and Dynamics</h3>
            <p class="section-summary">Keyboard architecture and interface behavior.</p>
            
            <div class="layout-control-field settings-nav-profile-field">
              <span class="settings-nav-profile-label">Keybinding profile</span>
              <Select
                class="settings-keybinding-select"
                value={layout.keybindingProfile()}
                options={KEYBINDING_PROFILE_OPTIONS}
                onChange={(id) => {
                  layout.setKeybindingProfile(id);
                  void layout.persistUiPreferences();
                }}
                ariaLabel="Keybinding profile"
              />
            </div>

            <h4 class="settings-nav-subtitle">Behavioral Dynamics</h4>
            <label class="layout-checkbox-field settings-nav-checkbox">
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
            <p class="section-summary settings-shortcuts-summary">Core shortcuts for the active profile.</p>
            <div class="keybinding-preview-card">
              <ul class="keybinding-preview-list settings-keybinding-grid">
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
              <p class="section-summary" style="margin-bottom: 12px;">
                {latencyReport().totalSamples} samples · {latencyReport().commandCount} unique commands
              </p>
              <div class="inline-actions">
                <button class="ghost-btn" onClick={() => setLatencyReport(getCommandLatencyReport())}>
                  Refresh Snapshot
                </button>
                <button
                  class="ghost-btn"
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
                    <div class="telemetry-grid">
                      <div class="telemetry-grid-item">
                        <span class="telemetry-label">p50</span>
                        <span class="telemetry-value">{summary.p50Ms.toFixed(1)}ms</span>
                      </div>
                      <div class="telemetry-grid-item">
                        <span class="telemetry-label">Reliability</span>
                        <span class="telemetry-value">{Math.round((summary.successCount / summary.count) * 100)}%</span>
                      </div>
                      <div class="telemetry-grid-item">
                        <span class="telemetry-label">Range</span>
                        <span class="telemetry-value">{Math.round(summary.minMs)}–{Math.round(summary.maxMs)}ms</span>
                      </div>
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
              <p class="section-summary" style="margin-bottom: 12px;">
                {diffRenderReport().totalSessions} sessions · stability {((1 - diffRenderReport().fallbackRate) * 100).toFixed(0)}%
              </p>

              <div class="inline-actions">
                <button class="ghost-btn" onClick={() => setDiffRenderReport(getDiffRenderMetricsReport())}>
                  Refresh Diff Metrics
                </button>
                <button
                  class="ghost-btn"
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
                    <div class="telemetry-summary-command">Renderer: {summary.rendererMode}</div>
                    <div class="telemetry-grid">
                      <div class="telemetry-grid-item">
                        <span class="telemetry-label">First Paint</span>
                        <span class="telemetry-value">{summary.firstPaintP50Ms.toFixed(0)}ms</span>
                      </div>
                      <div class="telemetry-grid-item">
                        <span class="telemetry-label">Scroll p50</span>
                        <span class="telemetry-value">{summary.scrollFpsP50.toFixed(0)}fps</span>
                      </div>
                      <div class="telemetry-grid-item">
                        <span class="telemetry-label">Memory p95</span>
                        <span class="telemetry-value">{summary.memoryP95Mb.toFixed(0)}MB</span>
                      </div>
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
              <Select
                value={updateChannel()}
                options={[
                  { id: "stable", label: "Stable" },
                  { id: "beta", label: "Beta" }
                ]}
                onChange={(id) => {
                  const next = id === "beta" ? "beta" : "stable";
                  setUpdateChannel(next);
                  void onSaveUpdateChannel(next);
                }}
                ariaLabel="Update channel"
              />
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
              <span>Capture local crash diagnostics</span>
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
                <div class="settings-meta-row">
                  <div class="settings-meta-item">
                    <span class="settings-meta-label">Last Checked</span>
                    <span class="settings-meta-value">{formatTimestamp(status().checkedAt)}</span>
                  </div>
                  <div class="settings-meta-item">
                    <span class="settings-meta-label">Current Version</span>
                    <span class="settings-meta-value">{status().currentVersion}</span>
                  </div>
                  <Show when={status().updateAvailable}>
                    <div class="settings-meta-item">
                      <span class="settings-meta-label">Available</span>
                      <span class="settings-meta-value">{status().latestVersion ?? "unknown"}</span>
                    </div>
                  </Show>
                </div>
              )}
            </Show>
          </article>
        </section>
      </Show>

      <section class="settings-feedback-slot" aria-live="polite">
        <Show
          when={actionError()}
          fallback={
            <Show when={actionMessage()}>
              {(message) => <p class="settings-feedback-text" title={message()}>{message()}</p>}
            </Show>
          }
        >
          {(message) => <p class="settings-feedback-text is-error" title={message()}>{message()}</p>}
        </Show>
      </section>
    </div>
  );
}
