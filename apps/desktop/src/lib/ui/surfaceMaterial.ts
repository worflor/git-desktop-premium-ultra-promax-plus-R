export type SurfaceMaterialMode = "solid" | "glass";

export interface SurfaceMaterialShader {
  mode: SurfaceMaterialMode;
  blurPx: number;
  saturatePct: number;
  opacityScale: number;
  edgeIntensity: number;
}

interface RgbaColor {
  r: number;
  g: number;
  b: number;
  a: number;
}

interface OverlayBinding {
  source: string;
  target: string;
}

interface StateTintBinding {
  source: string;
  target: string;
  alpha: number;
}

interface SurfaceRuntime {
  filter: string;
  alphaScale: number;
  tintLift: number;
}

const CHANNEL_MAX = 255;
const OVERLAY_BINDINGS: readonly OverlayBinding[] = [
  { source: "--panel-overlay", target: "--runtime-panel-overlay" },
  { source: "--panel-overlay-strong", target: "--runtime-panel-overlay-strong" },
  { source: "--input-overlay", target: "--runtime-input-overlay" },
  { source: "--diff-overlay", target: "--runtime-diff-overlay" },
  { source: "--danger-overlay", target: "--runtime-danger-overlay" }
];

const STATE_TINT_BINDINGS: readonly StateTintBinding[] = [
  { source: "--state-added", target: "--runtime-state-added-bg-soft", alpha: 0.2 },
  { source: "--state-modified", target: "--runtime-state-modified-bg-soft", alpha: 0.18 },
  { source: "--state-conflicted", target: "--runtime-state-conflicted-bg-soft", alpha: 0.18 },
  { source: "--state-staged", target: "--runtime-state-staged-bg-soft", alpha: 0.18 },
  { source: "--state-unstaged", target: "--runtime-state-unstaged-bg-soft", alpha: 0.18 },
  { source: "--state-added", target: "--runtime-state-added-bg-subtle", alpha: 0.12 }
];

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) {
    return min;
  }
  return Math.min(max, Math.max(min, value));
}

function parseAlpha(value: string): number {
  const trimmed = value.trim();
  if (trimmed.endsWith("%")) {
    return clamp(Number.parseFloat(trimmed.slice(0, -1)) / 100, 0, 1);
  }
  return clamp(Number.parseFloat(trimmed), 0, 1);
}

function parseRgbaColor(value: string): RgbaColor | null {
  const match = value.match(/rgba?\(([^)]+)\)/i);
  if (!match || !match[1]) {
    return null;
  }

  const channelText = match[1].replace(/\//g, ",");
  const segments = channelText
    .split(",")
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0);

  if (segments.length < 3) {
    return null;
  }

  const r = clamp(Number.parseFloat(segments[0] ?? "0"), 0, CHANNEL_MAX);
  const g = clamp(Number.parseFloat(segments[1] ?? "0"), 0, CHANNEL_MAX);
  const b = clamp(Number.parseFloat(segments[2] ?? "0"), 0, CHANNEL_MAX);
  const a = segments[3] ? parseAlpha(segments[3]) : 1;

  return { r, g, b, a };
}

function parseHexColor(value: string): RgbaColor | null {
  const raw = value.trim();
  if (!raw.startsWith("#")) {
    return null;
  }

  let hex = raw.slice(1);
  if (hex.length === 3 || hex.length === 4) {
    hex = hex
      .split("")
      .map((segment) => segment + segment)
      .join("");
  }

  if (hex.length !== 6 && hex.length !== 8) {
    return null;
  }

  const r = Number.parseInt(hex.slice(0, 2), 16);
  const g = Number.parseInt(hex.slice(2, 4), 16);
  const b = Number.parseInt(hex.slice(4, 6), 16);
  const a = hex.length === 8 ? Number.parseInt(hex.slice(6, 8), 16) / CHANNEL_MAX : 1;

  if (![r, g, b, a].every((segment) => Number.isFinite(segment))) {
    return null;
  }

  return {
    r: clamp(r, 0, CHANNEL_MAX),
    g: clamp(g, 0, CHANNEL_MAX),
    b: clamp(b, 0, CHANNEL_MAX),
    a: clamp(a, 0, 1)
  };
}

function parseCssColor(value: string): RgbaColor | null {
  return parseRgbaColor(value) ?? parseHexColor(value);
}

function toRgbaString(color: RgbaColor): string {
  return `rgba(${Math.round(color.r)}, ${Math.round(color.g)}, ${Math.round(color.b)}, ${color.a.toFixed(3)})`;
}

function computeRuntime(shader: SurfaceMaterialShader, devicePixelRatio: number): SurfaceRuntime {
  const dpr = clamp(devicePixelRatio, 1, 2.5);
  const materialMix = shader.mode === "glass" ? 1 : 0;

  const blurPx = clamp(Math.sqrt(dpr) * shader.blurPx * materialMix, 0, 28);
  const saturatePct = clamp(100 + (shader.saturatePct - 100) * materialMix, 90, 220);

  // A tiny optical model: stronger edge intensity increases perceived refraction,
  // which means we compensate by lifting opacity to preserve readability.
  const refractionGain = clamp(1 + shader.edgeIntensity * 0.22 * materialMix, 1, 1.26);
  const alphaScale = clamp((shader.opacityScale / refractionGain) * (materialMix > 0 ? 1 : 1.12), 0.68, 1.55);
  const tintLift = clamp(shader.edgeIntensity * 6 * materialMix, 0, 14);

  if (materialMix < 0.5 || blurPx < 0.25) {
    return {
      filter: "none",
      alphaScale,
      tintLift: 0
    };
  }

  return {
    filter: `blur(${blurPx.toFixed(2)}px) saturate(${saturatePct.toFixed(1)}%)`,
    alphaScale,
    tintLift
  };
}

function applyOverlayRuntime(
  root: HTMLElement,
  computedStyles: CSSStyleDeclaration,
  sourceVariable: string,
  targetVariable: string,
  alphaScale: number,
  tintLift: number
): void {
  const parsed = parseCssColor(computedStyles.getPropertyValue(sourceVariable));
  if (!parsed) {
    root.style.removeProperty(targetVariable);
    return;
  }

  const tinted: RgbaColor = {
    r: clamp(parsed.r + tintLift, 0, CHANNEL_MAX),
    g: clamp(parsed.g + tintLift, 0, CHANNEL_MAX),
    b: clamp(parsed.b + tintLift, 0, CHANNEL_MAX),
    a: clamp(parsed.a * alphaScale, 0, 0.985)
  };

  root.style.setProperty(targetVariable, toRgbaString(tinted));
}

function applyStateTintRuntime(
  root: HTMLElement,
  computedStyles: CSSStyleDeclaration,
  sourceVariable: string,
  targetVariable: string,
  alpha: number
): void {
  const parsed = parseCssColor(computedStyles.getPropertyValue(sourceVariable));
  if (!parsed) {
    root.style.removeProperty(targetVariable);
    return;
  }

  root.style.setProperty(
    targetVariable,
    toRgbaString({
      r: parsed.r,
      g: parsed.g,
      b: parsed.b,
      a: clamp(alpha, 0, 0.985)
    })
  );
}

export function applySurfaceMaterial(shader: SurfaceMaterialShader, root: HTMLElement): void {
  if (typeof window === "undefined") {
    return;
  }

  const runtime = computeRuntime(shader, window.devicePixelRatio || 1);

  root.style.setProperty("--runtime-glass-filter", runtime.filter);

  const computedStyles = window.getComputedStyle(root);
  for (const binding of OVERLAY_BINDINGS) {
    applyOverlayRuntime(
      root,
      computedStyles,
      binding.source,
      binding.target,
      runtime.alphaScale,
      runtime.tintLift
    );
  }

  for (const binding of STATE_TINT_BINDINGS) {
    applyStateTintRuntime(
      root,
      computedStyles,
      binding.source,
      binding.target,
      binding.alpha
    );
  }
}
