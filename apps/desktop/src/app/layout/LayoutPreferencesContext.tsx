import { createContext, createSignal, onCleanup, onMount, useContext, type Accessor, type ParentProps } from "solid-js";
import { getAppSettings, updateLayoutPreferences, updateUiPreferences } from "@/lib/backend/commands";
import { applyTheme, DEFAULT_THEME_ID, normalizeThemeId, type ThemeId } from "@/lib/ui/theme";
import { normalizeKeybindingProfile, type KeybindingProfile } from "@/lib/ui/keybindings";

export const SIDEBAR_WIDTH_MIN_PX = 140;
export const SIDEBAR_WIDTH_MAX_PX = 380;
export const SIDEBAR_WIDTH_DEFAULT_PX = 188;
export const UTILITY_DRAWER_HEIGHT_MIN_PX = 120;
export const UTILITY_DRAWER_HEIGHT_MAX_PX = 280;

type SidebarPosition = "left" | "right";

interface LayoutPreferencesContextValue {
  initialized: Accessor<boolean>;
  loading: Accessor<boolean>;
  saving: Accessor<boolean>;
  error: Accessor<string | null>;
  themeId: Accessor<ThemeId>;
  keybindingProfile: Accessor<KeybindingProfile>;
  sidebarWidthPx: Accessor<number>;
  sidebarPosition: Accessor<SidebarPosition>;
  utilityDrawerExpanded: Accessor<boolean>;
  utilityDrawerHeightPx: Accessor<number>;
  setThemeId: (value: ThemeId | string) => void;
  setKeybindingProfile: (value: KeybindingProfile | string) => void;
  setSidebarWidthPx: (value: number) => void;
  setSidebarPosition: (value: SidebarPosition) => void;
  setUtilityDrawerExpanded: (value: boolean) => void;
  setUtilityDrawerHeightPx: (value: number) => void;
  persistUiPreferences: () => Promise<boolean>;
  persistLayoutPreferences: () => Promise<boolean>;
  reloadLayoutPreferences: () => Promise<void>;
}

const LayoutPreferencesContext = createContext<LayoutPreferencesContextValue>();

function clampInteger(value: number, min: number, max: number, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback;
  }

  return Math.min(max, Math.max(min, Math.round(value)));
}

function getSidebarWidthRuntimeMaxPx(): number {
  if (typeof window === "undefined") {
    return SIDEBAR_WIDTH_MAX_PX;
  }

  return Math.min(SIDEBAR_WIDTH_MAX_PX, Math.floor(window.innerWidth * 0.5));
}

function clampSidebarWidthPx(value: number): number {
  const runtimeMax = getSidebarWidthRuntimeMaxPx();
  const fallback = Math.min(SIDEBAR_WIDTH_DEFAULT_PX, runtimeMax);

  if (!Number.isFinite(value)) {
    return fallback;
  }

  return Math.min(runtimeMax, Math.max(SIDEBAR_WIDTH_MIN_PX, Math.round(value)));
}

function clampUtilityDrawerHeightPx(value: number): number {
  return clampInteger(value, UTILITY_DRAWER_HEIGHT_MIN_PX, UTILITY_DRAWER_HEIGHT_MAX_PX, 144);
}

function normalizeSidebarPosition(value: string): SidebarPosition {
  if (value.trim().toLowerCase() === "right") {
    return "right";
  }

  return "left";
}

const LAYOUT_PREFERENCES_CACHE_KEY = "gdpu.layout.preferences.v1";

interface LayoutSettingsData {
  themeId: string;
  keybindingProfile: string;
  sidebarWidthPx: number;
  sidebarPosition: string;
  utilityDrawerDefaultExpanded: boolean;
  utilityDrawerHeightPx: number;
}

interface CachedLayoutPreferences {
  themeId?: string;
  keybindingProfile?: string;
  sidebarWidthPx?: number;
  sidebarPosition?: string;
  utilityDrawerDefaultExpanded?: boolean;
  utilityDrawerHeightPx?: number;
}

function loadCachedLayoutPreferences(): CachedLayoutPreferences | null {
  if (typeof window === "undefined") {
    return null;
  }

  try {
    const payload = window.localStorage.getItem(LAYOUT_PREFERENCES_CACHE_KEY);
    if (!payload) {
      return null;
    }

    const parsed: unknown = JSON.parse(payload);
    if (!parsed || typeof parsed !== "object") {
      return null;
    }

    return parsed as CachedLayoutPreferences;
  } catch {
    return null;
  }
}

function persistCachedLayoutPreferences(data: LayoutSettingsData): void {
  if (typeof window === "undefined") {
    return;
  }

  try {
    window.localStorage.setItem(LAYOUT_PREFERENCES_CACHE_KEY, JSON.stringify(data));
  } catch {
    // Ignore storage failures: preferences still round-trip through backend settings.
  }
}

function resolveInitialThemeId(cached: CachedLayoutPreferences | null): ThemeId {
  const bootstrapTheme =
    typeof document !== "undefined" ? document.documentElement.getAttribute("data-theme") : null;
  return normalizeThemeId(cached?.themeId ?? bootstrapTheme ?? DEFAULT_THEME_ID);
}

export function LayoutPreferencesProvider(props: ParentProps) {
  const cachedSettings = loadCachedLayoutPreferences();
  const [initialized, setInitialized] = createSignal(false);
  const [loading, setLoading] = createSignal(true);
  const [saving, setSaving] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const [themeId, setThemeIdSignal] = createSignal<ThemeId>(resolveInitialThemeId(cachedSettings));
  const [keybindingProfile, setKeybindingProfileSignal] = createSignal<KeybindingProfile>(
    normalizeKeybindingProfile(cachedSettings?.keybindingProfile ?? "classic")
  );
  const [sidebarWidthPx, setSidebarWidthPxSignal] = createSignal(
    clampSidebarWidthPx(cachedSettings?.sidebarWidthPx ?? SIDEBAR_WIDTH_DEFAULT_PX)
  );
  const [sidebarPosition, setSidebarPositionSignal] = createSignal<SidebarPosition>(
    normalizeSidebarPosition(cachedSettings?.sidebarPosition ?? "left")
  );
  const [utilityDrawerExpanded, setUtilityDrawerExpandedSignal] = createSignal(
    Boolean(cachedSettings?.utilityDrawerDefaultExpanded)
  );
  const [utilityDrawerHeightPx, setUtilityDrawerHeightPxSignal] = createSignal(
    clampUtilityDrawerHeightPx(cachedSettings?.utilityDrawerHeightPx ?? 144)
  );

  const applySettingsData = (data: LayoutSettingsData) => {
    const normalized: LayoutSettingsData = {
      themeId: normalizeThemeId(data.themeId),
      keybindingProfile: normalizeKeybindingProfile(data.keybindingProfile),
      sidebarWidthPx: clampSidebarWidthPx(data.sidebarWidthPx),
      sidebarPosition: normalizeSidebarPosition(data.sidebarPosition),
      utilityDrawerDefaultExpanded: Boolean(data.utilityDrawerDefaultExpanded),
      utilityDrawerHeightPx: clampUtilityDrawerHeightPx(data.utilityDrawerHeightPx)
    };

    setThemeIdSignal(normalized.themeId as ThemeId);
    applyTheme(normalized.themeId);
    setKeybindingProfileSignal(normalized.keybindingProfile as KeybindingProfile);
    setSidebarWidthPxSignal(normalized.sidebarWidthPx);
    setSidebarPositionSignal(normalized.sidebarPosition as SidebarPosition);
    setUtilityDrawerExpandedSignal(normalized.utilityDrawerDefaultExpanded);
    setUtilityDrawerHeightPxSignal(normalized.utilityDrawerHeightPx);
    persistCachedLayoutPreferences(normalized);
  };

  const loadSettings = async () => {
    setLoading(true);
    setError(null);

    const result = await getAppSettings();

    if (!result.ok) {
      setLoading(false);
      setInitialized(true);
      setError(result.error.message);
      return;
    }

    applySettingsData(result.data);
    setLoading(false);
    setInitialized(true);
  };

  const setSidebarWidthPx = (value: number) => {
    setSidebarWidthPxSignal(clampSidebarWidthPx(value));
  };

  const setThemeId = (value: ThemeId | string) => {
    const normalizedThemeId = normalizeThemeId(value);
    setThemeIdSignal(normalizedThemeId);
    applyTheme(normalizedThemeId);
  };

  const setKeybindingProfile = (value: KeybindingProfile | string) => {
    setKeybindingProfileSignal(normalizeKeybindingProfile(value));
  };

  const setSidebarPosition = (value: SidebarPosition) => {
    setSidebarPositionSignal(value === "right" ? "right" : "left");
  };

  const setUtilityDrawerExpanded = (value: boolean) => {
    setUtilityDrawerExpandedSignal(Boolean(value));
  };

  const setUtilityDrawerHeightPx = (value: number) => {
    setUtilityDrawerHeightPxSignal(clampUtilityDrawerHeightPx(value));
  };

  const persistLayoutPreferences = async (): Promise<boolean> => {
    setSaving(true);
    setError(null);

    const result = await updateLayoutPreferences(
      sidebarWidthPx(),
      sidebarPosition(),
      utilityDrawerExpanded(),
      utilityDrawerHeightPx()
    );

    setSaving(false);

    if (!result.ok) {
      setError(result.error.message);
      return false;
    }

    applySettingsData(result.data);
    return true;
  };

  const persistUiPreferences = async (): Promise<boolean> => {
    setSaving(true);
    setError(null);

    const result = await updateUiPreferences(themeId(), keybindingProfile());
    setSaving(false);

    if (!result.ok) {
      setError(result.error.message);
      return false;
    }

    applySettingsData(result.data);
    return true;
  };

  const reloadLayoutPreferences = async () => {
    await loadSettings();
  };

  onMount(() => {
    const onWindowResize = () => {
      setSidebarWidthPxSignal((current) => clampSidebarWidthPx(current));
    };

    window.addEventListener("resize", onWindowResize, { passive: true });
    onCleanup(() => {
      window.removeEventListener("resize", onWindowResize);
    });

    void loadSettings();
  });

  return (
    <LayoutPreferencesContext.Provider
      value={{
        initialized,
        loading,
        saving,
        error,
        themeId,
        keybindingProfile,
        sidebarWidthPx,
        sidebarPosition,
        utilityDrawerExpanded,
        utilityDrawerHeightPx,
        setThemeId,
        setKeybindingProfile,
        setSidebarWidthPx,
        setSidebarPosition,
        setUtilityDrawerExpanded,
        setUtilityDrawerHeightPx,
        persistUiPreferences,
        persistLayoutPreferences,
        reloadLayoutPreferences
      }}
    >
      {props.children}
    </LayoutPreferencesContext.Provider>
  );
}

export function useLayoutPreferences(): LayoutPreferencesContextValue {
  const context = useContext(LayoutPreferencesContext);
  if (!context) {
    throw new Error("Layout preferences context is unavailable.");
  }
  return context;
}