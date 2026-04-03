import { applySurfaceMaterial, type SurfaceMaterialShader } from "@/lib/ui/surfaceMaterial";

const THEME_IDS = [
  "halo",
  "petrichor",
  "nightwalker",
  "aether",
  "helix",
  "quanta",
  "redshift",
  "blackboard",
  "crafty"
] as const;

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
    id: "halo",
    label: "Halo",
    description: "Angelic white gold with ethereal clouds and divine radiance.",
    shader: {
      mode: "glass",
      blurPx: 32,
      saturatePct: 125,
      opacityScale: 0.75,
      edgeIntensity: 1.2,
      texture: "none",
      motion: "fluid",
      luminescence: 1.5,
      particles: "ethereal",
      parallaxStrength: 0.4,
      geometry: {
        radius: 12,
        typography: "'Playfair Display', serif",
        fontScale: 1.12,
        letterSpacing: "0.035em"
      }
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
    id: "nightwalker",
    label: "Nightwalker",
    description: "Abyssal obsidian brutalism. The silent, technical shadow of the Halo.",
    shader: {
      mode: "glass",
      blurPx: 8,
      saturatePct: 200,
      opacityScale: 0.85,
      edgeIntensity: 1.5,
      texture: "none",
      motion: "snappy",
      luminescence: 0.2,
      particles: "void",
      parallaxStrength: 0.4,
      geometry: {
        radius: 0,
        typography: "'JetBrains Mono', monospace",
        fontScale: 0.95,
        letterSpacing: "-0.01em"
      }
    }
  },
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
    description: "Deep emerald obsidian with technical subatomic jitter and high-refraction glass.",
    shader: {
      mode: "glass",
      blurPx: 22,
      saturatePct: 160,
      opacityScale: 0.88,
      edgeIntensity: 0.8,
      texture: "scanlines",
      textureOpacity: 0.06,
      motion: "fluid",
      luminescence: 0.5,
      particles: "quantum",
      parallaxStrength: 0.6,
      geometry: {
        letterSpacing: "0.02em"
      }
    }
  },
  {
    id: "redshift",
    label: "Redshift",
    description: "Deep cosmic garnet with Relativistic EM Wave oscillation and CMB background radiation.",
    shader: {
      mode: "glass",
      blurPx: 24,
      saturatePct: 150,
      opacityScale: 0.9,
      edgeIntensity: 0.8,
      texture: "scanlines",
      textureOpacity: 0.08,
      motion: "fluid",
      luminescence: 0.45,
      particles: "embers",
      parallaxStrength: 0.7,
      geometry: {
        typography: "'JetBrains Mono', monospace",
        letterSpacing: "normal",
        radius: 0,
        fontScale: 1
      }
    }
  },
  {
    id: "blackboard",
    label: "Blackboard",
    description: "Raw slate geometry with physical chalk typographical rendering.",
    shader: {
      mode: "solid",
      blurPx: 0,
      saturatePct: 100,
      opacityScale: 1.0,
      edgeIntensity: 1.0,
      texture: "grain",
      textureOpacity: 0.15,
      motion: "snappy",
      luminescence: 0.1,
      particles: "chalkdust",
      parallaxStrength: 0.1,
      geometry: {
        radius: 2,
        typography: "'Lora', serif",
        fontScale: 1.05
      }
    }
  },
  {
    id: "crafty",
    label: "Crafty",
    description: "Voxel-based rendering with sharp geometry and pixel-perfect textures.",
    shader: {
      mode: "solid",
      blurPx: 0,
      saturatePct: 150,
      opacityScale: 1.0,
      edgeIntensity: 0.8,
      texture: "pixels",
      textureOpacity: 0.15,
      motion: "snappy",
      luminescence: 0.4,
      particles: "voxels",
      parallaxStrength: 0.2,
      geometry: {
        radius: 0,
        pixelated: true,
        typography: "'VT323', monospace"
      }
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
