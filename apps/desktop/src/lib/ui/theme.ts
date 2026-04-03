import { applySurfaceMaterial, type SurfaceMaterialShader } from "@/lib/ui/surfaceMaterial";

const THEME_IDS = ["aether", "helix", "quanta", "petrichor", "redshift", "halo"] as const;

export type ThemeId = (typeof THEME_IDS)[number];

export interface ThemeOption {
  id: ThemeId;
  label: string;
  description: string;
}

interface ThemeDefinition extends ThemeOption {
  shader: SurfaceMaterialShader;
}

const THEME_DEFINITIONS = [
  {
    id: "aether",
    label: "Aether",
    description: "Deep cosmic glass with cool contrast for long review sessions.",
    shader: {
      mode: "glass",
      blurPx: 14,
      saturatePct: 132,
      opacityScale: 0.98,
      edgeIntensity: 0.62,
      texture: "scanlines",
      textureOpacity: 0.03,
      motion: "fluid",
      luminescence: 0.4,
      particles: "stardust",
      parallaxStrength: 0.5
    }
  },
  {
    id: "helix",
    label: "Helix",
    description: "Warm daylight surfaces with soft amber chrome.",
    shader: {
      mode: "solid",
      blurPx: 0,
      saturatePct: 100,
      opacityScale: 1.14,
      edgeIntensity: 0,
      texture: "grain",
      textureOpacity: 0.15,
      motion: "snappy",
      luminescence: 0.1,
      parallaxStrength: 0.1
    }
  },
  {
    id: "quanta",
    label: "Quanta",
    description: "Balanced dark green-black palette with restrained glow.",
    shader: {
      mode: "glass",
      blurPx: 11,
      saturatePct: 126,
      opacityScale: 1.04,
      edgeIntensity: 0.4,
      texture: "grain",
      textureOpacity: 0.05,
      motion: "snappy",
      luminescence: 0.2,
      parallaxStrength: 0.8
    }
  },
  {
    id: "petrichor",
    label: "Petrichor",
    description: "Misty cool light mode tuned for daytime readability.",
    shader: {
      mode: "solid",
      blurPx: 0,
      saturatePct: 100,
      opacityScale: 1.1,
      edgeIntensity: 0,
      texture: "none",
      motion: "elastic",
      luminescence: 0.1,
      parallaxStrength: 0.3
    }
  },
  {
    id: "redshift",
    label: "Redshift",
    description: "Crimson dusk glass for high-contrast focus work.",
    shader: {
      mode: "glass",
      blurPx: 12,
      saturatePct: 136,
      opacityScale: 1.06,
      edgeIntensity: 0.55,
      texture: "scanlines",
      textureOpacity: 0.08,
      motion: "fluid",
      luminescence: 0.6,
      particles: "embers",
      parallaxStrength: 0.5
    }
  },
  {
    id: "halo",
    label: "Halo",
    description: "Ultra-glass dark mode with highly luminous mint-cyan edges.",
    shader: {
      mode: "glass",
      blurPx: 24,
      saturatePct: 160,
      opacityScale: 0.82,
      edgeIntensity: 0.95,
      texture: "grain",
      textureOpacity: 0.06,
      motion: "elastic",
      luminescence: 0.8,
      particles: "stardust",
      parallaxStrength: 0.6
    }
  }
] as const satisfies readonly ThemeDefinition[];

export const DEFAULT_THEME_ID: ThemeId = THEME_DEFINITIONS[0].id;

const THEME_DEFINITION_BY_ID: ReadonlyMap<ThemeId, ThemeDefinition> = new Map(
  THEME_DEFINITIONS.map((definition) => [definition.id, definition])
);

export const THEME_OPTIONS: ThemeOption[] = THEME_DEFINITIONS.map((definition) => ({
  id: definition.id,
  label: definition.label,
  description: definition.description
}));

function findThemeDefinition(themeId: ThemeId): ThemeDefinition {
  return THEME_DEFINITION_BY_ID.get(themeId) ?? THEME_DEFINITIONS[0];
}

export function normalizeThemeId(value: string): ThemeId {
  const normalized = value.trim().toLowerCase();
  const match = THEME_OPTIONS.find((option) => option.id === normalized);
  if (match) {
    return match.id;
  }
  return DEFAULT_THEME_ID;
}

export function applyTheme(themeIdInput: ThemeId | string): void {
  if (typeof document === "undefined") {
    return;
  }

  const themeId = normalizeThemeId(themeIdInput);
  const root = document.documentElement;
  root.setAttribute("data-theme", themeId);
  applySurfaceMaterial(findThemeDefinition(themeId).shader, root);
}
