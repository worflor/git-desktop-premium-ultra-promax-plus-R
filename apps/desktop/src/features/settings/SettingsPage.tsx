import { Match, Switch, createEffect, createMemo, createResource, createSignal, onCleanup, onMount, startTransition, Show } from "solid-js";
import {
  useLayoutPreferences
} from "@/app/layout/LayoutPreferencesContext";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import {
  checkForAppUpdate,
  getAppSettings,
  installAppUpdate,
  listAiModelOptions,
  listAiProviders,
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
  clearUiTimingReport,
  getUiTimingReport,
  recordUiTiming,
  setUiTimingRetentionPolicy,
  subscribeUiTimingReport
} from "@/lib/telemetry/uiTiming";
import {
  getNavigationBindings,
  KEYBINDING_PROFILE_OPTIONS
} from "@/lib/ui/keybindings";
import { THEME_OPTIONS } from "@/lib/ui/theme";
import { Select, type SelectOption } from "@/components/primitives/Select";

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

const MODEL_CATEGORY_STORAGE_PREFIX = "gdpu.ai.category.";
const MODEL_CATEGORY_LABEL_STORAGE_PREFIX = "gdpu.ai.category-label.";
const AI_PROVIDER_PLACEHOLDERS = [
  { id: "codex", binary: "codex" },
  { id: "claude", binary: "claude" },
  { id: "gemini", binary: "npx" },
  { id: "opencode", binary: "opencode" }
] as const;
const MODEL_CATEGORY_PLACEHOLDERS = [
  { id: "quality", label: "Quality model" },
  { id: "fast", label: "Fast model" }
] as const;

function modelCategoryStorageKey(categoryId: string): string {
  return `${MODEL_CATEGORY_STORAGE_PREFIX}${categoryId}`;
}

function modelCategoryLabelStorageKey(categoryId: string): string {
  return `${MODEL_CATEGORY_LABEL_STORAGE_PREFIX}${categoryId}`;
}

function buildEmptyCategoryMessage(categoryLabel: string): string {
  return `No ${categoryLabel.toLowerCase()} models from detected providers.`;
}

type DiagnosticsFocus = "command" | "diff" | "ui";

interface DiagnosticsOffender {
  focus: DiagnosticsFocus;
  streamLabel: string;
  name: string;
  score: number;
  metricLabel: string;
}

interface AiProviderDisplayCard {
  id: string;
  binary: string;
  available: boolean;
  planName?: string;
  placeholder: boolean;
}

export function SettingsPage() {
  const mountedAt = performance.now();
  const layout = useLayoutPreferences();
  const [aiDiagnosticsBootstrapped, setAiDiagnosticsBootstrapped] = createSignal(false);
  const [settingsResult] = createResource(() => getAppSettings());
  const [aiProvidersResult, { refetch: refetchAiProviders }] = createResource(
    aiDiagnosticsBootstrapped,
    async (enabled) => {
      if (!enabled) {
        return null;
      }

      return listAiProviders();
    }
  );
  const [aiModelOptionsResult, { refetch: refetchAiModelOptions }] = createResource(
    aiDiagnosticsBootstrapped,
    async (enabled) => {
      if (!enabled) {
        return null;
      }

      return listAiModelOptions();
    }
  );
  const [aiProvidersSnapshot, setAiProvidersSnapshot] = createSignal<ReturnType<typeof aiProvidersResult> | null>(
    null
  );
  const [aiModelOptionsSnapshot, setAiModelOptionsSnapshot] = createSignal<
    ReturnType<typeof aiModelOptionsResult> | null
  >(null);
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
  const [modelSelections, setModelSelections] = createSignal<Record<string, string>>({});
  const [modelLabelOverrides, setModelLabelOverrides] = createSignal<Record<string, string>>({});
  const [editingModelCategoryId, setEditingModelCategoryId] = createSignal<string | null>(null);
  const [editingModelCategoryLabel, setEditingModelCategoryLabel] = createSignal("");
  const [modelSelectionInitialized, setModelSelectionInitialized] = createSignal(false);
  const [latencyReport, setLatencyReport] = createSignal(getCommandLatencyReport());
  const [diffRenderReport, setDiffRenderReport] = createSignal(getDiffRenderMetricsReport());
  const [uiTimingReport, setUiTimingReport] = createSignal(getUiTimingReport());
  const [diagnosticsFocus, setDiagnosticsFocus] = createSignal<DiagnosticsFocus>("command");
  const [topCardsCompact, setTopCardsCompact] = createSignal(false);
  const [topCardsUltraCompact, setTopCardsUltraCompact] = createSignal(false);

  let topCardsRowRef: HTMLDivElement | undefined;
  let guardrailsCardRef: HTMLElement | undefined;
  let calibrationCardRef: HTMLElement | undefined;
  let editingModelCategoryInputRef: HTMLInputElement | undefined;

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
    setModelSelectionInitialized(true);
  });

  onMount(() => {
    let aiDiagnosticsDelayId: number | undefined;

    requestAnimationFrame(() => {
      recordUiTiming({
        event: "settings.page.first-paint",
        phase: "mount",
        durationMs: performance.now() - mountedAt
      });

      aiDiagnosticsDelayId = window.setTimeout(() => {
        void startTransition(() => {
          setAiDiagnosticsBootstrapped(true);
        });
        aiDiagnosticsDelayId = undefined;
      }, 180);
    });

    const unsubscribeCommandLatency = subscribeCommandLatencyReport((report) => {
      setLatencyReport(report);
    });
    const unsubscribeDiffRender = subscribeDiffRenderMetricsReport((report) => {
      setDiffRenderReport(report);
    });
    const unsubscribeUiTiming = subscribeUiTimingReport((report) => {
      setUiTimingReport(report);
    });

    onCleanup(() => {
      if (aiDiagnosticsDelayId !== undefined) {
        window.clearTimeout(aiDiagnosticsDelayId);
      }
      unsubscribeCommandLatency();
      unsubscribeDiffRender();
      unsubscribeUiTiming();
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
    const latest = aiProvidersResult.latest;
    if (!latest?.ok) {
      return;
    }

    void startTransition(() => {
      setAiProvidersSnapshot(latest);
    });
  });

  createEffect(() => {
    const latest = aiModelOptionsResult.latest;
    if (!latest?.ok) {
      return;
    }

    void startTransition(() => {
      setAiModelOptionsSnapshot(latest);
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
    setUiTimingRetentionPolicy(settings.data.telemetryRetentionDays, settings.data.telemetryRetentionMb);
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

  const modelCategoryFields = createMemo(() => {
    const modelOptions = aiModelOptionsSnapshot();
    if (!modelOptions?.ok) {
      return [];
    }

    return modelOptions.data.categories.map((category) => ({
      id: category.id,
      label: category.label,
      options: category.models.map<SelectOption>((model) => ({
        id: model.value,
        label: model.label,
        description: model.description
      }))
    }));
  });

  const aiProviderStatuses = createMemo(() => {
    const providerSnapshot = aiProvidersSnapshot();
    if (!providerSnapshot?.ok) {
      return [];
    }

    return providerSnapshot.data.providers;
  });

  const aiProvidersLoading = createMemo(
    () => aiDiagnosticsBootstrapped() && aiProvidersResult.loading && !aiProvidersSnapshot()
  );

  const aiModelOptionsLoading = createMemo(
    () => aiDiagnosticsBootstrapped() && aiModelOptionsResult.loading && !aiModelOptionsSnapshot()
  );

  const aiProviderCards = createMemo<AiProviderDisplayCard[]>(() => {
    const statuses = aiProviderStatuses();
    if (statuses.length > 0) {
      return statuses.map((provider) => ({
        id: provider.id,
        binary: provider.binary,
        available: provider.available,
        planName: provider.planName,
        placeholder: false
      }));
    }

    const statusLabel = aiDiagnosticsBootstrapped() ? "Detecting..." : "Queued";
    return AI_PROVIDER_PLACEHOLDERS.map((provider) => ({
      id: provider.id,
      binary: provider.binary,
      available: false,
      planName: statusLabel,
      placeholder: true
    }));
  });

  const aiModelPlaceholderLabel = createMemo(() => {
    if (!aiDiagnosticsBootstrapped()) {
      return "Queued";
    }

    if (aiModelOptionsLoading()) {
      return "Loading models...";
    }

    return "Awaiting model diagnostics...";
  });

  const topCommandOffender = createMemo<DiagnosticsOffender | null>(() => {
    const summaries = latencyReport().summaries;
    if (summaries.length === 0) {
      return null;
    }

    const ranked = summaries
      .map((summary) => {
        const failureRate = summary.count === 0 ? 0 : summary.failureCount / summary.count;
        const score = summary.p95Ms * (1 + failureRate * 3);

        return {
          summary,
          score,
          failureRate
        };
      })
      .sort((left, right) => right.score - left.score);

    const offender = ranked[0];
    if (!offender) {
      return null;
    }

    return {
      focus: "command",
      streamLabel: "Command",
      name: offender.summary.command,
      score: offender.score,
      metricLabel: `${offender.summary.p95Ms.toFixed(0)}ms p95 · ${(offender.failureRate * 100).toFixed(0)}% fail`
    };
  });

  const topDiffOffender = createMemo<DiagnosticsOffender | null>(() => {
    const summaries = diffRenderReport().modeSummaries;
    if (summaries.length === 0) {
      return null;
    }

    const ranked = summaries
      .map((summary) => {
        const fpsPenalty = Math.max(0, 60 - summary.scrollFpsP50);
        const score =
          summary.firstPaintP95Ms + summary.memoryP95Mb * 4 + summary.fallbackRate * 600 + fpsPenalty * 6;

        return {
          summary,
          score
        };
      })
      .sort((left, right) => right.score - left.score);

    const offender = ranked[0];
    if (!offender) {
      return null;
    }

    return {
      focus: "diff",
      streamLabel: "Diff Render",
      name: `${offender.summary.rendererMode} renderer`,
      score: offender.score,
      metricLabel: `${(offender.summary.fallbackRate * 100).toFixed(0)}% fallback · ${offender.summary.firstPaintP95Ms.toFixed(0)}ms p95`
    };
  });

  const topUiOffender = createMemo<DiagnosticsOffender | null>(() => {
    const summaries = uiTimingReport().summaries;
    if (summaries.length === 0) {
      return null;
    }

    const ranked = summaries
      .map((summary) => {
        const failureRate = summary.count === 0 ? 0 : summary.failureCount / summary.count;
        const score = summary.p95Ms * (1 + failureRate * 3);

        return {
          summary,
          score,
          failureRate
        };
      })
      .sort((left, right) => right.score - left.score);

    const offender = ranked[0];
    if (!offender) {
      return null;
    }

    return {
      focus: "ui",
      streamLabel: "UI Timing",
      name: `${offender.summary.phase}:${offender.summary.event}`,
      score: offender.score,
      metricLabel: `${offender.summary.p95Ms.toFixed(0)}ms p95 · ${(offender.failureRate * 100).toFixed(0)}% fail`
    };
  });

  const diagnosticsTopOffenders = createMemo(() => {
    return [topCommandOffender(), topDiffOffender(), topUiOffender()]
      .filter((offender): offender is DiagnosticsOffender => offender !== null)
      .sort((left, right) => right.score - left.score)
      .slice(0, 3);
  });

  const copyTextWithFallback = (value: string): boolean => {
    if (typeof document === "undefined") {
      return false;
    }

    const textarea = document.createElement("textarea");
    textarea.value = value;
    textarea.setAttribute("readonly", "true");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    textarea.style.pointerEvents = "none";
    document.body.appendChild(textarea);
    textarea.select();

    let copied = false;
    try {
      copied = document.execCommand("copy");
    } catch {
      copied = false;
    }

    document.body.removeChild(textarea);
    return copied;
  };

  const onCopyAllDiagnostics = async () => {
    setActionError(null);

    const snapshot = {
      copiedAt: new Date().toISOString(),
      focusedStream: diagnosticsFocus(),
      topOffenders: diagnosticsTopOffenders().map((offender) => ({
        stream: offender.streamLabel,
        name: offender.name,
        metric: offender.metricLabel,
        score: Number(offender.score.toFixed(2))
      })),
      command: latencyReport(),
      diffRender: diffRenderReport(),
      uiTiming: uiTimingReport()
    };
    const serialized = JSON.stringify(snapshot, null, 2);

    try {
      if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(serialized);
        setActionMessage("Copied diagnostics snapshot to clipboard.");
        return;
      }

      if (copyTextWithFallback(serialized)) {
        setActionMessage("Copied diagnostics snapshot to clipboard.");
        return;
      }

      setActionError("Clipboard access is unavailable.");
    } catch {
      if (copyTextWithFallback(serialized)) {
        setActionMessage("Copied diagnostics snapshot to clipboard.");
        return;
      }

      setActionError("Failed to copy diagnostics snapshot.");
    }
  };

  const loadOrRefreshAiDiagnostics = () => {
    if (!aiDiagnosticsBootstrapped()) {
      void startTransition(() => {
        setAiDiagnosticsBootstrapped(true);
      });
      return;
    }

    void Promise.all([refetchAiProviders(), refetchAiModelOptions()]);
  };

  const modelValueByCategory = (categoryId: string) => modelSelections()[categoryId] ?? "";

  const setModelValueByCategory = (categoryId: string, value: string) => {
    setModelSelections((current) => ({
      ...current,
      [categoryId]: value
    }));
  };

  const modelLabelByCategory = (categoryId: string, fallbackLabel: string) => {
    const override = modelLabelOverrides()[categoryId] ?? "";
    return override.trim() || fallbackLabel;
  };

  const beginModelCategoryRename = (categoryId: string, fallbackLabel: string) => {
    const activeCategoryId = editingModelCategoryId();
    if (activeCategoryId && activeCategoryId !== categoryId) {
      const normalizedActiveValue = editingModelCategoryLabel().trim();
      setModelLabelOverrides((current) => {
        const next = { ...current };
        if (normalizedActiveValue) {
          next[activeCategoryId] = normalizedActiveValue;
        } else {
          delete next[activeCategoryId];
        }
        return next;
      });
    }

    setEditingModelCategoryId(categoryId);
    setEditingModelCategoryLabel(modelLabelByCategory(categoryId, fallbackLabel));
  };

  const commitModelCategoryRename = (categoryId: string) => {
    const normalizedValue = editingModelCategoryLabel().trim();
    setModelLabelOverrides((current) => {
      const next = { ...current };
      if (normalizedValue) {
        next[categoryId] = normalizedValue;
      } else {
        delete next[categoryId];
      }
      return next;
    });

    setEditingModelCategoryId((active) => (active === categoryId ? null : active));
    setEditingModelCategoryLabel("");
  };

  const cancelModelCategoryRename = (categoryId: string) => {
    setEditingModelCategoryId((active) => (active === categoryId ? null : active));
    setEditingModelCategoryLabel("");
  };

  createEffect(() => {
    const activeCategoryId = editingModelCategoryId();
    if (!activeCategoryId) {
      return;
    }

    setTimeout(() => {
      editingModelCategoryInputRef?.focus();
      editingModelCategoryInputRef?.select();
    }, 0);
  });

  createEffect(() => {
    if (!aiModelOptionsSnapshot()?.ok) {
      return;
    }

    const categories = modelCategoryFields();
    if (categories.length === 0) {
      setModelSelections({});
      return;
    }

    setModelSelections((current) => {
      const next: Record<string, string> = {};

      for (const category of categories) {
        const allowedValues = new Set(category.options.map((option) => option.id));
        const currentValue = current[category.id] ?? "";
        const storedValue =
          typeof window === "undefined"
            ? ""
            : (window.localStorage.getItem(modelCategoryStorageKey(category.id)) ?? "");

        let resolvedValue = currentValue || storedValue;
        if (!resolvedValue || !allowedValues.has(resolvedValue)) {
          resolvedValue = category.options.at(0)?.id ?? "";
        }

        next[category.id] = resolvedValue;
      }

      const currentKeys = Object.keys(current);
      const nextKeys = Object.keys(next);
      const changed =
        currentKeys.length !== nextKeys.length ||
        nextKeys.some((key) => (current[key] ?? "") !== (next[key] ?? ""));

      return changed ? next : current;
    });
  });

  createEffect(() => {
    if (!modelSelectionInitialized() || typeof window === "undefined" || !aiModelOptionsSnapshot()?.ok) {
      return;
    }

    const categories = modelCategoryFields();
    const selections = modelSelections();
    const activeCategoryIds = new Set(categories.map((category) => category.id));

    for (const category of categories) {
      const value = selections[category.id] ?? "";
      const storageKey = modelCategoryStorageKey(category.id);

      if (value) {
        window.localStorage.setItem(storageKey, value);
      } else {
        window.localStorage.removeItem(storageKey);
      }
    }

    for (let index = window.localStorage.length - 1; index >= 0; index -= 1) {
      const storageKey = window.localStorage.key(index);
      if (!storageKey || !storageKey.startsWith(MODEL_CATEGORY_STORAGE_PREFIX)) {
        continue;
      }

      const categoryId = storageKey.slice(MODEL_CATEGORY_STORAGE_PREFIX.length);
      if (!activeCategoryIds.has(categoryId)) {
        window.localStorage.removeItem(storageKey);
      }
    }
  });

  createEffect(() => {
    if (!aiModelOptionsSnapshot()?.ok || typeof window === "undefined") {
      return;
    }

    const categories = modelCategoryFields();
    if (categories.length === 0) {
      setModelLabelOverrides({});
      return;
    }

    setModelLabelOverrides((current) => {
      const next: Record<string, string> = {};

      for (const category of categories) {
        const currentValue = current[category.id] ?? "";
        const storedValue = window.localStorage.getItem(modelCategoryLabelStorageKey(category.id)) ?? "";
        next[category.id] = currentValue || storedValue;
      }

      const currentKeys = Object.keys(current);
      const nextKeys = Object.keys(next);
      const changed =
        currentKeys.length !== nextKeys.length ||
        nextKeys.some((key) => (current[key] ?? "") !== (next[key] ?? ""));

      return changed ? next : current;
    });
  });

  createEffect(() => {
    if (!modelSelectionInitialized() || typeof window === "undefined" || !aiModelOptionsSnapshot()?.ok) {
      return;
    }

    const categories = modelCategoryFields();
    const labels = modelLabelOverrides();
    const activeCategoryIds = new Set(categories.map((category) => category.id));

    for (const category of categories) {
      const value = (labels[category.id] ?? "").trim();
      const storageKey = modelCategoryLabelStorageKey(category.id);

      if (value) {
        window.localStorage.setItem(storageKey, value);
      } else {
        window.localStorage.removeItem(storageKey);
      }
    }

    for (let index = window.localStorage.length - 1; index >= 0; index -= 1) {
      const storageKey = window.localStorage.key(index);
      if (!storageKey || !storageKey.startsWith(MODEL_CATEGORY_LABEL_STORAGE_PREFIX)) {
        continue;
      }

      const categoryId = storageKey.slice(MODEL_CATEGORY_LABEL_STORAGE_PREFIX.length);
      if (!activeCategoryIds.has(categoryId)) {
        window.localStorage.removeItem(storageKey);
      }
    }
  });

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
              <p class="settings-fit-line">{guardrailModePhrase()}</p>
              <p class="settings-fit-line">
                Read-only: {settingsResult.latest?.ok && settingsResult.latest.data.aiReadOnlyDefault ? "Enabled" : "Disabled"}
              </p>
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

            <p class="section-summary settings-shortcuts-summary">Core shortcuts for the active profile.</p>
            <div class="keybinding-preview-card" style="margin-bottom: 24px;">
              <ul class="keybinding-preview-list settings-keybinding-grid">
                {getNavigationBindings(layout.keybindingProfile()).map((binding) => (
                  <li class="keybinding-preview-row">
                    <span>{binding.label}</span>
                    <span class="shortcut-hint">{binding.keys}</span>
                  </li>
                ))}
              </ul>
            </div>

            <h4 class="settings-nav-subtitle">Behavioural Dynamics</h4>
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

            <div class="settings-model-pair-grid">
              <Show
                when={modelCategoryFields().length > 0}
                fallback={MODEL_CATEGORY_PLACEHOLDERS.map((field) => (
                  <div class="layout-control-field settings-model-field settings-model-field-placeholder">
                    <div class="settings-sub-header">
                      <span class="settings-model-label-placeholder">{field.label}</span>
                    </div>
                    <div class="settings-model-select-placeholder">
                      <span class="settings-inline-spinner" aria-hidden="true" />
                      <span>{aiModelPlaceholderLabel()}</span>
                    </div>
                  </div>
                ))}
              >
                {modelCategoryFields().map((field) => (
                  <div class="layout-control-field settings-model-field">
                    <div class="settings-sub-header">
                      <Show
                        when={editingModelCategoryId() === field.id}
                        fallback={
                          <button
                            type="button"
                            class="settings-model-label-trigger"
                            onClick={() => {
                              beginModelCategoryRename(field.id, field.label);
                            }}
                            title="Click to rename"
                          >
                            {modelLabelByCategory(field.id, field.label)}
                          </button>
                        }
                      >
                        <input
                          ref={editingModelCategoryInputRef}
                          class="path-input settings-model-label-input"
                          value={editingModelCategoryLabel()}
                          onInput={(event) => {
                            setEditingModelCategoryLabel(event.currentTarget.value);
                          }}
                          onBlur={() => {
                            if (editingModelCategoryId() === field.id) {
                              commitModelCategoryRename(field.id);
                            }
                          }}
                          onKeyDown={(event) => {
                            if (event.key === "Enter") {
                              event.preventDefault();
                              commitModelCategoryRename(field.id);
                            }

                            if (event.key === "Escape") {
                              event.preventDefault();
                              cancelModelCategoryRename(field.id);
                            }
                          }}
                          aria-label="Rename model category"
                        />
                      </Show>
                    </div>
                    <Show
                      when={field.options.length > 0}
                      fallback={
                        <p class="settings-model-empty">
                          {buildEmptyCategoryMessage(modelLabelByCategory(field.id, field.label))}
                        </p>
                      }
                    >
                      <Select
                        value={modelValueByCategory(field.id)}
                        options={field.options}
                        onChange={(value) => {
                          setModelValueByCategory(field.id, value);
                        }}
                        ariaLabel={modelLabelByCategory(field.id, field.label)}
                      />
                    </Show>
                  </div>
                ))}
              </Show>
            </div>

            <div class="settings-sub-header">
              <h4 class="settings-nav-subtitle">AI CLIs</h4>
              <button
                class="ghost-btn"
                style="font-size: 0.72rem; padding: 4px 10px; min-height: 24px; border-radius: 4px;"
                disabled={aiProvidersResult.loading || aiModelOptionsResult.loading}
                onClick={() => {
                  loadOrRefreshAiDiagnostics();
                }}
              >
                Refresh Providers
              </button>
            </div>
            <p class="section-summary">Routing and piping interface messages directly to local provider binaries.</p>

            <Show when={aiProvidersResult.latest && !aiProvidersResult.latest.ok && !aiProvidersSnapshot()}>
              <p class="section-summary settings-ai-provider-error">
                {aiProvidersResult.latest && !aiProvidersResult.latest.ok
                  ? aiProvidersResult.latest.error.message
                  : "Provider detection failed."}
              </p>
            </Show>

            <div class="settings-ai-loading-row">
              <Show when={!aiDiagnosticsBootstrapped() || aiProvidersLoading() || aiModelOptionsLoading()}>
                <span class="settings-inline-spinner" aria-hidden="true" />
                <span>
                  {!aiDiagnosticsBootstrapped()
                    ? "Preparing provider diagnostics..."
                    : "Loading providers and model options..."}
                </span>
              </Show>
            </div>

            <div class="settings-ai-models-grid">
              {aiProviderCards().map((provider) => (
                <div class={`settings-ai-model-node ${provider.placeholder ? "is-placeholder" : ""}`}>
                  <div class="settings-ai-model-id">{provider.id}</div>
                  <div class="settings-ai-model-meta">
                    <span
                      class={`settings-ai-model-status ${provider.available ? "is-ready" : "is-missing"} ${provider.placeholder ? "is-loading" : ""}`}
                    >
                      {provider.placeholder
                        ? provider.planName ?? "Detecting..."
                        : provider.available
                          ? provider.planName ?? "Ready"
                          : "Not detected"}
                    </span>
                    <span class="settings-ai-model-binary">{provider.binary}</span>
                  </div>
                </div>
              ))}
            </div>

          </article>

            <article class="state-card state-card-wide settings-diagnostics-card">
              <div class="settings-diagnostics-heading">
                <h3>Diagnostics</h3>
                <button class="ghost-btn settings-diagnostics-copy-btn" type="button" onClick={() => void onCopyAllDiagnostics()}>
                  Copy All
                </button>
              </div>
              <p class="section-summary">Comparative overview with focused drill-down for each diagnostic stream.</p>

              <div class="settings-diagnostics-overview-grid">
                <button
                  class={`settings-diagnostics-overview ${diagnosticsFocus() === "command" ? "is-active" : ""}`}
                  onClick={() => setDiagnosticsFocus("command")}
                  aria-pressed={diagnosticsFocus() === "command"}
                  type="button"
                >
                  <span class="settings-diagnostics-overview-title">Command</span>
                  <span class="settings-diagnostics-overview-meta">
                    {latencyReport().totalSamples} samples · {latencyReport().commandCount} commands
                  </span>
                </button>

                <button
                  class={`settings-diagnostics-overview ${diagnosticsFocus() === "diff" ? "is-active" : ""}`}
                  onClick={() => setDiagnosticsFocus("diff")}
                  aria-pressed={diagnosticsFocus() === "diff"}
                  type="button"
                >
                  <span class="settings-diagnostics-overview-title">Diff Render</span>
                  <span class="settings-diagnostics-overview-meta">
                    {diffRenderReport().totalSessions} sessions · {((1 - diffRenderReport().fallbackRate) * 100).toFixed(0)}% stability
                  </span>
                </button>

                <button
                  class={`settings-diagnostics-overview ${diagnosticsFocus() === "ui" ? "is-active" : ""}`}
                  onClick={() => setDiagnosticsFocus("ui")}
                  aria-pressed={diagnosticsFocus() === "ui"}
                  type="button"
                >
                  <span class="settings-diagnostics-overview-title">UI Timing</span>
                  <span class="settings-diagnostics-overview-meta">
                    {uiTimingReport().totalSamples} samples · {uiTimingReport().eventCount} events
                  </span>
                </button>
              </div>

              <div class="settings-diagnostics-offenders">
                <div class="settings-diagnostics-offenders-header">
                  <h4 class="settings-nav-subtitle">Top Offenders</h4>
                  <p class="section-summary">Highest pressure points across latency, stability, and failure rate.</p>
                </div>

                <Show
                  when={diagnosticsTopOffenders().length > 0}
                  fallback={<p class="section-summary">No offender ranking yet. Capture diagnostic activity to populate this list.</p>}
                >
                  <div class="settings-diagnostics-offender-list">
                    {diagnosticsTopOffenders().map((offender, index) => (
                      <button
                        class="settings-diagnostics-offender"
                        type="button"
                        onClick={() => setDiagnosticsFocus(offender.focus)}
                        aria-label={`Focus ${offender.streamLabel} diagnostics`}
                      >
                        <span class="settings-diagnostics-offender-rank">#{index + 1}</span>
                        <span class="settings-diagnostics-offender-main">
                          <span class="settings-diagnostics-offender-stream">{offender.streamLabel}</span>
                          <span class="settings-diagnostics-offender-name">{offender.name}</span>
                        </span>
                        <span class="settings-diagnostics-offender-metric">{offender.metricLabel}</span>
                      </button>
                    ))}
                  </div>
                </Show>
              </div>

              <div class="settings-diagnostics-section settings-diagnostics-focus-panel">
                <Switch>
                  <Match when={diagnosticsFocus() === "command"}>
                    <h4 class="settings-nav-subtitle">Command Diagnostics</h4>
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
                  </Match>

                  <Match when={diagnosticsFocus() === "diff"}>
                    <h4 class="settings-nav-subtitle">Diff Render Diagnostics</h4>
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
                  </Match>

                  <Match when={diagnosticsFocus() === "ui"}>
                    <h4 class="settings-nav-subtitle">UI Timing Diagnostics</h4>
                    <p class="section-summary" style="margin-bottom: 12px;">
                      {uiTimingReport().totalSamples} samples · {uiTimingReport().eventCount} instrumented events
                    </p>

                    <div class="inline-actions">
                      <button class="ghost-btn" onClick={() => setUiTimingReport(getUiTimingReport())}>
                        Refresh UI Timings
                      </button>
                      <button
                        class="ghost-btn"
                        disabled={uiTimingReport().totalSamples === 0}
                        onClick={() => clearUiTimingReport()}
                      >
                        Clear UI Timings
                      </button>
                    </div>

                    <Show
                      when={uiTimingReport().summaries.length > 0}
                      fallback={<p>No UI timing sessions captured yet. Open panels and navigate routes to populate this panel.</p>}
                    >
                      <div class="telemetry-summary-list">
                        {uiTimingReport().summaries.slice(0, 10).map((summary) => (
                          <div class="telemetry-summary-row">
                            <div class="telemetry-summary-command">{summary.phase}: {summary.event}</div>
                            <div class="telemetry-grid">
                              <div class="telemetry-grid-item">
                                <span class="telemetry-label">p50</span>
                                <span class="telemetry-value">{summary.p50Ms.toFixed(1)}ms</span>
                              </div>
                              <div class="telemetry-grid-item">
                                <span class="telemetry-label">Failures</span>
                                <span class="telemetry-value">{summary.failureCount}</span>
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

                    <Show when={uiTimingReport().recentSamples.length > 0}>
                      <details class="telemetry-recent-details">
                        <summary>Recent UI Timings</summary>
                        <ul class="telemetry-recent-list">
                          {uiTimingReport().recentSamples.map((sample) => (
                            <li>
                              {formatSampleTime(sample.recordedAt)} | {sample.phase}:{sample.event} | {sample.durationMs.toFixed(2)} ms | {sample.ok ? "ok" : sample.errorCode}
                            </li>
                          ))}
                        </ul>
                      </details>
                    </Show>
                  </Match>
                </Switch>
              </div>
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
