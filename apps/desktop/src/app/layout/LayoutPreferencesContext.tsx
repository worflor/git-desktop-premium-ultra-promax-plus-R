import { createContext, createSignal, onMount, useContext, type Accessor, type ParentProps } from "solid-js";
import { getAppSettings, updateLayoutPreferences, updateUiPreferences } from "@/lib/backend/commands";
import { applyTheme, DEFAULT_THEME_ID, normalizeThemeId, type ThemeId } from "@/lib/ui/theme";
import { normalizeKeybindingProfile, type KeybindingProfile } from "@/lib/ui/keybindings";

export const SIDEBAR_WIDTH_MIN_PX = 140;
export const SIDEBAR_WIDTH_MAX_PX = 380;
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

function clampSidebarWidthPx(value: number): number {
  return clampInteger(value, SIDEBAR_WIDTH_MIN_PX, SIDEBAR_WIDTH_MAX_PX, 188);
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

export function LayoutPreferencesProvider(props: ParentProps) {
  const [initialized, setInitialized] = createSignal(false);
  const [loading, setLoading] = createSignal(true);
  const [saving, setSaving] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  const [themeId, setThemeIdSignal] = createSignal<ThemeId>(DEFAULT_THEME_ID);
  const [keybindingProfile, setKeybindingProfileSignal] = createSignal<KeybindingProfile>("classic");
  const [sidebarWidthPx, setSidebarWidthPxSignal] = createSignal(188);
  const [sidebarPosition, setSidebarPositionSignal] = createSignal<SidebarPosition>("left");
  const [utilityDrawerExpanded, setUtilityDrawerExpandedSignal] = createSignal(false);
  const [utilityDrawerHeightPx, setUtilityDrawerHeightPxSignal] = createSignal(144);

  const applySettingsData = (data: {
    themeId: string;
    keybindingProfile: string;
    sidebarWidthPx: number;
    sidebarPosition: string;
    utilityDrawerDefaultExpanded: boolean;
    utilityDrawerHeightPx: number;
  }) => {
    const normalizedThemeId = normalizeThemeId(data.themeId);
    setThemeIdSignal(normalizedThemeId);
    applyTheme(normalizedThemeId);
    setKeybindingProfileSignal(normalizeKeybindingProfile(data.keybindingProfile));
    setSidebarWidthPxSignal(clampSidebarWidthPx(data.sidebarWidthPx));
    setSidebarPositionSignal(normalizeSidebarPosition(data.sidebarPosition));
    setUtilityDrawerExpandedSignal(data.utilityDrawerDefaultExpanded);
    setUtilityDrawerHeightPxSignal(clampUtilityDrawerHeightPx(data.utilityDrawerHeightPx));
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