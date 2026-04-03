export type SurfaceMaterialMode = "solid" | "glass";

export interface SurfaceMaterialShader {
  mode: SurfaceMaterialMode;
  blurPx: number;
  saturatePct: number;
  opacityScale: number;
  edgeIntensity: number;
  texture?: "none" | "grain" | "scanlines";
  textureOpacity?: number;
  motion?: "snappy" | "fluid" | "elastic";
  luminescence?: number;
  particles?: "none" | "stardust" | "embers";
  parallaxStrength?: number;
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
  ambientWeight: number;
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

function generateProceduralTexture(shader: SurfaceMaterialShader): string {
  const intensity = clamp(shader.textureOpacity ?? 0, 0, 1);
  if (intensity === 0 || !shader.texture || shader.texture === "none") return "none";

  // We construct mathematical SVG matrices directly in string memory to avoid loading payload assets.
  // Circle XIX insists on eliminating I/O bottleneck; Base64 generative matrices execute inside the layout layer.
  let svg = "";
  if (shader.texture === "grain") {
    // High-frequency fractional noise produces a tactile, matte paper/film grain surface
    svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400'>
      <filter id='noiseFilter'>
        <feTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3' stitchTiles='stitch'/>
      </filter>
      <rect width='100%' height='100%' filter='url(#noiseFilter)' opacity='${intensity.toFixed(2)}'/>
    </svg>`;
  } else if (shader.texture === "scanlines") {
    // 1-pixel alternating matrix simulates CRT interlacing without arbitrary image textures
    svg = `<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'>
      <rect width='4' height='2' fill='black' opacity='${intensity.toFixed(2)}'/>
    </svg>`;
  }

  // Btoa executes in highly-optimized engine C++ code, transforming raw markup to a CSS background payload.
  return `url(data:image/svg+xml;base64,${btoa(svg)})`;
}

function generateProceduralParticles(shader: SurfaceMaterialShader, ambient: RgbaColor | null): string {
  if (!shader.particles || shader.particles === "none") return "none";
  
  // Base physical dimensions. A large matrix repeats natively over the CSS viewport infinitely.
  let svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1000 1000'>`;
  const baseFill = ambient ? `rgba(${ambient.r},${ambient.g},${ambient.b},1)` : "white";

  if (shader.particles === "stardust") {
    // Generate isolated geometric points pulsing slowly using embedded un-executed CSS rules
    svg += `<style>
      .star { animation: pulse linear infinite; fill: ${baseFill}; }
      @keyframes pulse { 0%, 100% { opacity: 0; } 50% { opacity: 0.8; } }
    </style>`;
    // Deterministic random generation for physical stars
    for (let i = 0; i < 40; i++) {
        const x = (Math.sin(i * 123) * 500 + 500).toFixed(1);
        const y = (Math.cos(i * 321) * 500 + 500).toFixed(1);
        const r = (Math.abs(Math.sin(i * 21)) * 1.5 + 0.5).toFixed(1);
        const dur = (Math.abs(Math.sin(i * 44)) * 3 + 2).toFixed(1);
        const del = (Math.abs(Math.sin(i * 55)) * 4).toFixed(1);
        svg += `<circle cx='${x}' cy='${y}' r='${r}' class='star' style='animation-duration:${dur}s;animation-delay:${del}s' />`;
    }
  } else if (shader.particles === "embers") {
    // Emit vertically translating shards that fade mathematically over space
    svg += `<style>
      .ember { animation: float linear infinite; fill: ${baseFill}; }
      @keyframes float { 0% { transform: translateY(1050px); opacity: 0;} 20% {opacity: 0.6;} 100% { transform: translateY(-50px); opacity: 0; } }
    </style>`;
    // Deterministic spawn vectors
    for (let i = 0; i < 20; i++) {
        const x = (Math.sin(i * 678) * 500 + 500).toFixed(1);
        const w = (Math.abs(Math.sin(i * 12)) * 3 + 1).toFixed(1);
        const dur = (Math.abs(Math.sin(i * 88)) * 8 + 4).toFixed(1);
        const del = (Math.abs(Math.sin(i * 99)) * 10).toFixed(1);
        svg += `<rect x='${x}' y='0' width='${w}' height='${(parseFloat(w)*3).toFixed(1)}' rx='1' class='ember' style='animation-duration:${dur}s;animation-delay:${del}s' />`;
    }
  }
  svg += `</svg>`;
  return `url(data:image/svg+xml;base64,${btoa(svg)})`;
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
  // The ambient weight calculates environmental chroma reflection intensity.
  // Mapped into a [0, 256] fixed-point scale for hardware-efficient bitshifting.
  const ambientWeight = clamp(Math.round(shader.edgeIntensity * 40 * materialMix), 0, 256);

  if (materialMix < 0.5 || blurPx < 0.25) {
    return {
      filter: "none",
      alphaScale,
      ambientWeight: 0
    };
  }

  return {
    filter: `blur(${blurPx.toFixed(2)}px) saturate(${saturatePct.toFixed(1)}%)`,
    alphaScale,
    ambientWeight
  };
}

function applyOverlayRuntime(
  root: HTMLElement,
  computedStyles: CSSStyleDeclaration,
  ambientColor: RgbaColor | null,
  sourceVariable: string,
  targetVariable: string,
  alphaScale: number,
  ambientWeight: number
): void {
  const parsed = parseCssColor(computedStyles.getPropertyValue(sourceVariable));
  if (!parsed) {
    root.style.removeProperty(targetVariable);
    return;
  }

  let r = parsed.r;
  let g = parsed.g;
  let b = parsed.b;

  // Circle XXVI: Fixed-point scaling interpolates the ambient chroma
  // into the shadow layers using mathematically-pure shifts over floating-point fractions.
  if (ambientColor && ambientWeight > 0) {
    r = r + (((ambientColor.r - r) * ambientWeight) >> 8);
    g = g + (((ambientColor.g - g) * ambientWeight) >> 8);
    b = b + (((ambientColor.b - b) * ambientWeight) >> 8);
  }

  const tinted: RgbaColor = {
    r: clamp(r, 0, CHANNEL_MAX),
    g: clamp(g, 0, CHANNEL_MAX),
    b: clamp(b, 0, CHANNEL_MAX),
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
  const rawAmbient = computedStyles.getPropertyValue("--theme-ambient-rgb").trim();
  const ambientColor = rawAmbient ? parseCssColor(`rgb(${rawAmbient})`) : null;

  // Render mathematical procedural textures directly over the CSS boundaries
  root.style.setProperty("--runtime-material-texture", generateProceduralTexture(shader));
  root.style.setProperty("--runtime-material-particles", generateProceduralParticles(shader, ambientColor));

  // Determine physical kinematic (motion) variables
  let ease = "cubic-bezier(0.2, 0, 0, 1)";
  let duration = "120ms";
  if (shader.motion === "snappy") { ease = "cubic-bezier(0.3, 0.0, 0.1, 1)"; duration = "80ms"; }
  if (shader.motion === "fluid") { ease = "cubic-bezier(0.4, 0, 0.2, 1)"; duration = "180ms"; }
  if (shader.motion === "elastic") { ease = "cubic-bezier(0.68, -0.55, 0.26, 1.55)"; duration = "250ms"; }
  root.style.setProperty("--runtime-ease", ease);
  root.style.setProperty("--runtime-duration", duration);
  root.style.setProperty("--runtime-parallax-strength", (shader.parallaxStrength ?? 0.5).toString());

  if (ambientColor) {
    // Generate unified cell-shading artifacts using bitshift halving for the hard shadow
    const shadowR = ambientColor.r >> 1;
    const shadowG = ambientColor.g >> 1;
    const shadowB = ambientColor.b >> 1;
    root.style.setProperty("--runtime-cell-shadow", `rgba(${shadowR}, ${shadowG}, ${shadowB}, 0.45)`);
    root.style.setProperty("--runtime-rim-light", `rgba(${ambientColor.r}, ${ambientColor.g}, ${ambientColor.b}, ${clamp(runtime.alphaScale * 0.35, 0.05, 0.8)})`);
    
    // Scale the luminescence multiplier through algorithmic box-shadow interpolation
    const lum = clamp(shader.luminescence ?? 1.0, 0, 3.0);
    const glowRadius = 12 * Math.max(1, lum);
    const glowAlpha  = clamp((ambientColor.a ?? 1) * 0.2 * lum, 0, 0.8);
    const hardAlpha  = clamp(0.15 * lum, 0, 1.0);
    // Combine an expanded blurred aura with a sharp inner halo (Circle XIX dictates rendering multiple scales iteratively)
    root.style.setProperty("--runtime-glow-shadow", `0 0 ${glowRadius.toFixed(1)}px rgba(${ambientColor.r}, ${ambientColor.g}, ${ambientColor.b}, ${glowAlpha.toFixed(2)}), 0 0 2px rgba(${ambientColor.r}, ${ambientColor.g}, ${ambientColor.b}, ${hardAlpha.toFixed(2)})`);
  } else {
    root.style.setProperty("--runtime-cell-shadow", "rgba(0, 0, 0, 0.5)");
    root.style.setProperty("--runtime-rim-light", "rgba(255, 255, 255, 0.1)");
    root.style.setProperty("--runtime-glow-shadow", "0 0 8px rgba(255, 255, 255, 0.15)");
  }

  for (const binding of OVERLAY_BINDINGS) {
    applyOverlayRuntime(
      root,
      computedStyles,
      ambientColor,
      binding.source,
      binding.target,
      runtime.alphaScale,
      runtime.ambientWeight
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
