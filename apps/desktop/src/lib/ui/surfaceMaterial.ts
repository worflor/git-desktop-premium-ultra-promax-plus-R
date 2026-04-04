export type SurfaceMaterialMode = "solid" | "glass";

export interface SurfaceMaterialShader {
  mode: SurfaceMaterialMode;
  blurPx: number;
  saturatePct: number;
  opacityScale: number;
  edgeIntensity: number;
  texture?: "none" | "grain" | "scanlines" | "pixels" | "chalkdust";
  textureOpacity?: number;
  motion?: "snappy" | "fluid" | "elastic";
  luminescence?: number;
  particles?: "none" | "stardust" | "embers" | "voxels" | "chalkdust" | "ethereal" | "void" | "quantum";
  parallaxStrength?: number;
  interaction?: "none" | "vibration" | "caustic" | "etch" | "warp" | "chalk";
  geometry?: {
    radius?: number; 
    pixelated?: boolean; 
    typography?: string; 
    fontScale?: number; 
    letterSpacing?: string; 
  };
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

interface MotionRuntime {
  ease: string;
  duration: string;
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

const DEFAULT_MOTION_RUNTIME: MotionRuntime = {
  ease: "cubic-bezier(0.2, 0, 0, 1)",
  duration: "120ms"
};

const MOTION_RUNTIME_BY_KIND: Readonly<Record<NonNullable<SurfaceMaterialShader["motion"]>, MotionRuntime>> = {
  snappy: { ease: "cubic-bezier(0.3, 0, 0.1, 1)", duration: "80ms" },
  fluid: { ease: "cubic-bezier(0.4, 0, 0.2, 1)", duration: "180ms" },
  elastic: { ease: "cubic-bezier(0.68, -0.55, 0.26, 1.55)", duration: "250ms" }
};

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.min(max, Math.max(min, value));
}

function parseAlpha(value: string): number {
  const trimmed = value.trim();
  if (trimmed.endsWith("%")) return clamp(Number.parseFloat(trimmed.slice(0, -1)) / 100, 0, 1);
  return clamp(Number.parseFloat(trimmed), 0, 1);
}

function parseRgbaColor(value: string): RgbaColor | null {
  const match = value.match(/rgba?\(([^)]+)\)/i);
  if (!match || !match[1]) return null;
  const channelText = match[1].replace(/\//g, ",");
  const segments = channelText.split(",").map((s) => s.trim()).filter((s) => s.length > 0);
  if (segments.length < 3) return null;
  const r = clamp(Number.parseFloat(segments[0] ?? "0"), 0, CHANNEL_MAX);
  const g = clamp(Number.parseFloat(segments[1] ?? "0"), 0, CHANNEL_MAX);
  const b = clamp(Number.parseFloat(segments[2] ?? "0"), 0, CHANNEL_MAX);
  const a = segments[3] ? parseAlpha(segments[3]) : 1;
  return { r, g, b, a };
}

function parseHexColor(value: string): RgbaColor | null {
  const raw = value.trim();
  if (!raw.startsWith("#")) return null;
  let hex = raw.slice(1);
  if (hex.length === 3 || hex.length === 4) hex = hex.split("").map((s) => s + s).join("");
  if (hex.length !== 6 && hex.length !== 8) return null;
  const r = Number.parseInt(hex.slice(0, 2), 16);
  const g = Number.parseInt(hex.slice(2, 4), 16);
  const b = Number.parseInt(hex.slice(4, 6), 16);
  const a = hex.length === 8 ? Number.parseInt(hex.slice(6, 8), 16) / CHANNEL_MAX : 1;
  if (![r, g, b, a].every((s) => Number.isFinite(s))) return null;
  return { r: clamp(r, 0, CHANNEL_MAX), g: clamp(g, 0, CHANNEL_MAX), b: clamp(b, 0, CHANNEL_MAX), a: clamp(a, 0, 1) };
}

function parseCssColor(value: string): RgbaColor | null {
  return parseRgbaColor(value) ?? parseHexColor(value);
}

function toRgbaString(color: RgbaColor): string {
  return `rgba(${Math.round(color.r)}, ${Math.round(color.g)}, ${Math.round(color.b)}, ${color.a.toFixed(3)})`;
}

function generateProceduralTexture(shader: SurfaceMaterialShader, ambient: RgbaColor | null): string {
  const intensity = clamp(shader.textureOpacity ?? 0, 0, 1);
  if (intensity === 0 || !shader.texture || shader.texture === "none") return "none";

  let svg = "";
  const baseFill = ambient ? `rgba(${ambient.r},${ambient.g},${ambient.b},1)` : "black";
  if (shader.texture === "grain") {
    svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400'><filter id='noiseFilter'><feTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3' stitchTiles='stitch'/></filter><rect width='100%' height='100%' filter='url(#noiseFilter)' opacity='${intensity.toFixed(2)}'/></svg>`;
  } else if (shader.texture === "scanlines") {
    svg = `<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><rect width='4' height='2' fill='black' opacity='${intensity.toFixed(2)}'/></svg>`;
  } else if (shader.texture === "pixels") {
    svg = `<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'>`;
    const darkLuma = ambient ? `rgba(${ambient.r > 20 ? ambient.r - 20 : 0}, ${ambient.g > 20 ? ambient.g - 20 : 0}, ${ambient.b > 20 ? ambient.b - 20 : 0}, 1)` : "black";
    svg += `<rect width='16' height='16' fill='${baseFill}' opacity='${(intensity * 0.5).toFixed(2)}'/>`;
    for (let x = 0; x < 16; x += 4) {
      for (let y = 0; y < 16; y += 4) {
        if (Math.abs(Math.sin(x * 12.3 + y * 4.5)) > 0.5) {
          svg += `<rect x='${x}' y='${y}' width='4' height='4' fill='${darkLuma}' opacity='${intensity.toFixed(2)}'/>`;
        }
      }
    }
    svg += `</svg>`;
  }

  return `url(data:image/svg+xml;base64,${btoa(svg)})`;
}

export type ParticlePayload = string | { near: string; mid: string; far: string; bg: string; };

function generateProceduralParticles(shader: SurfaceMaterialShader, ambient: RgbaColor | null): ParticlePayload {
  if (!shader.particles || shader.particles === "none") return "none";

  let svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1000 1000' preserveAspectRatio='none'>`;
  const baseFill = ambient ? toRgbaString({...ambient, a: 0.1}) : "rgba(255,255,255,0.1)";

  if (shader.particles === "stardust") {
    svg += `<style>.star { animation: pulse linear infinite; fill: ${baseFill}; } @keyframes pulse { 0%, 100% { opacity: 0; } 50% { opacity: 0.8; } }</style>`;
    for (let i = 0; i < 40; i++) {
      const x = (Math.sin(i * 123) * 500 + 500).toFixed(1);
      const y = (Math.cos(i * 321) * 500 + 500).toFixed(1);
      const r = (Math.abs(Math.sin(i * 21)) * 1.5 + 0.5).toFixed(1);
      const dur = (Math.abs(Math.sin(i * 44)) * 3 + 2).toFixed(1);
      const del = (Math.abs(Math.sin(i * 55)) * 4).toFixed(1);
      svg += `<circle cx='${x}' cy='${y}' r='${r}' class='star' style='animation-duration:${dur}s;animation-delay:${del}s' />`;
    }
  } else if (shader.particles === "embers") {
    svg += `<style>.near-wave { stroke: rgba(0, 240, 255, 0.4); animation: propagate 6s linear infinite; stroke-width: 1.2; } .mid-wave { stroke: rgba(255, 20, 50, 0.3); animation: propagate 12s linear infinite; stroke-width: 0.8; } .far-wave { stroke: rgba(100, 10, 20, 0.2); animation: propagate 24s linear infinite; stroke-width: 0.5; } @keyframes propagate { 0% { transform: translateX(-100%) scaleY(1); opacity: 0; } 15% { opacity: 1; } 85% { opacity: 1; } 100% { transform: translateX(100%) scaleY(1.2); opacity: 0; } } .cmb-scintilla { fill: rgba(255, 255, 255, 0.3); opacity: 0; animation: flicker 5s ease-in-out infinite; } @keyframes flicker { 0%, 100% { opacity: 0; transform: scale(0.8); } 50% { opacity: 0.5; transform: scale(1.1); } }</style>`;
    for (let i = 0; i < 40; i++) {
      const x = (Math.random() * 1000).toFixed(1);
      const y = (Math.random() * 1000).toFixed(1);
      const del = (Math.random() * -10).toFixed(1);
      svg += `<circle cx="${x}" cy="${y}" r="1" class="cmb-scintilla" style="animation-delay: ${del}s" />`;
    }
    const renderWaveLayer = (count: number, className: string, freqMod: number, amp: number) => {
      let res = "";
      for (let i = 0; i < count; i++) {
        const y_b = Math.random() * 1000;
        const del = (Math.random() * -30).toFixed(1);
        const freq = (Math.random() * 0.05 + 0.01) * freqMod;
        let d = `M 0 ${y_b.toFixed(1)} `;
        for (let x = 0; x <= 1000; x += 100) d += `L ${x} ${(y_b + Math.sin(x * freq + i) * amp).toFixed(1)} `;
        res += `<path d="${d}" fill="none" class="${className}" style="animation-delay:${del}s" />`;
      }
      return res;
    };
    svg += renderWaveLayer(6, "near-wave", 2.0, 15);
    svg += renderWaveLayer(5, "mid-wave", 1.0, 30);
    svg += renderWaveLayer(4, "far-wave", 0.5, 60);
  } else if (shader.particles === "voxels") {
    svg += `<style>.voxel { animation: drop linear infinite; fill: ${baseFill}; transform-origin: center; } @keyframes drop { 0% { transform: translateY(-100px) rotate(0deg); opacity: 0;} 10% {opacity: 0.3;} 90% {opacity: 0.3;} 100% { transform: translateY(1100px) rotate(360deg); opacity: 0; } }</style>`;
    for (let i = 0; i < 15; i++) {
      const x = (Math.sin(i * 444) * 500 + 500).toFixed(1);
      const s = (Math.abs(Math.sin(i * 33)) * 20 + 10).toFixed(1);
      const dur = (Math.abs(Math.sin(i * 22)) * 15 + 10).toFixed(1);
      const del = (Math.abs(Math.sin(i * 11)) * 15).toFixed(1);
      svg += `<rect x='${x}' y='0' width='${s}' height='${s}' class='voxel' style='animation-duration:${dur}s;animation-delay:${del}s' />`;
    }
  } else if (shader.particles === "chalkdust") {
    const chalkColors = [baseFill, baseFill, "rgba(255, 130, 140, 0.6)", "rgba(150, 210, 255, 0.6)", "rgba(255, 220, 120, 0.6)"];
    svg += `<style>.chalk-line { fill: none; stroke-linecap: round; stroke-linejoin: round; opacity: 0; animation: mathplot cubic-bezier(0.2, 0, 0.2, 1) infinite; will-change: stroke-dashoffset, opacity; } @keyframes mathplot { 0% { stroke-dashoffset: 600; opacity: 0; } 10% { opacity: 0.4; } 30% { stroke-dashoffset: 0; opacity: 0.4; } 90% { opacity: 0.4; } 100% { opacity: 0; } }</style>`;
    // Generate 8-Layer Balanced Spatial Harmony
    for (let i = 1; i <= 8; i++) {
      // Grid Distribution: 3x3 Cells to prevent clustering (doubling)
      const col = (i - 1) % 3;
      const row = Math.floor((i - 1) / 3);
      const cx = (col * 300 + 200 + (Math.random() - 0.5) * 150).toFixed(1);
      const cy = (row * 300 + 200 + (Math.random() - 0.5) * 150).toFixed(1);
      
      const a = Math.floor(Math.random() * 4 + 2);
      const b = Math.floor(Math.random() * 4 + 2);
      const absA = (a === b) ? a + 1 : a; // Ensure non-uniformity
      const delta = Math.random() * Math.PI * 2;
      const radius = (Math.random() * 80 + 60).toFixed(1);
      const rot = (Math.random() * 360).toFixed(1);
      
      let d = "";
      const steps = 400; // Quadrupled precision for buttery smooth curves
      for (let t = 0; t <= Math.PI * 2.1; t += (Math.PI * 2 / steps)) {
        const jitter = (Math.sin(t * 30 + i) * 1.2);
        const x = (Math.sin(absA * t + delta) * (+radius + jitter) + +cx).toFixed(1);
        const y = (Math.sin(b * t) * (+radius + jitter) + +cy).toFixed(1);
        d += t === 0 ? `M ${x} ${y} ` : `L ${x} ${y} `;
      }
      
      const dur = (Math.random() * 60 + 120).toFixed(1);
      const del = (i * 2.0 - 5).toFixed(1);
      const strokeW = (Math.random() * 0.5 + 0.2).toFixed(1);
      const color = chalkColors[i % chalkColors.length];
      
      svg += `<path d="${d}" class="chalk-line" stroke="${color}" stroke-width="${strokeW}" pathLength="600" stroke-dasharray="600 600" style="animation-duration:${dur}s;animation-delay:${del}s;transform-origin:${cx}px ${cy}px;transform:rotate(${rot}deg)" />`;
    }
  } else if (shader.particles === "void") {
    svg += `<style>.rain { animation: drop linear infinite; fill: #00f0ff; opacity: 0; } @keyframes drop { 0% { transform: translateY(-100px) scaleY(0.5); opacity: 0; } 10% { opacity: 0.8; } 90% { opacity: 0.8; } 100% { transform: translateY(1100px) scaleY(2); opacity: 0; } }</style>`;
    for (let i = 0; i < 60; i++) {
      const x = (Math.random() * 1000).toFixed(1), h = (Math.random() * 40 + 20).toFixed(1), dur = (Math.random() * 0.8 + 0.6).toFixed(1), del = (Math.random() * -3).toFixed(1);
      svg += `<rect x='${x}' y='0' width='1' height='${h}' class='rain' style='animation-duration:${dur}s;animation-delay:${del}s' />`;
    }
  } else if (shader.particles === "quantum") {
    svg += `<style>.q-orb { animation: breathe ease-in-out infinite alternate, q-drift linear infinite; fill: #00ff88; } @keyframes breathe { 0% { transform: scale(0.6); opacity: 0.3; filter: brightness(1); } 100% { transform: scale(1.4); opacity: 0.8; filter: brightness(1.6); } } @keyframes q-drift { 0% { transform: translate(0, 0); } 100% { transform: translate(40px, -40px); } }</style><filter id='orbGlow'><feGaussianBlur in='SourceGraphic' stdDeviation='1'/></filter>`;
    for (let i = 0; i < 45; i++) {
      const x = (Math.sin(i * 123) * 500 + 500).toFixed(1), y = (Math.cos(i * 456) * 500 + 500).toFixed(1), r = (Math.abs(Math.sin(i * 789)) * 1.5 + 0.5).toFixed(1);
      const bD = (Math.abs(Math.sin(i * 11)) * 3 + 2).toFixed(1), dD = (Math.abs(Math.cos(i * 22)) * 40 + 40).toFixed(1), del = (Math.abs(Math.sin(i * 33)) * -20).toFixed(1);
      svg += `<circle cx='${x}' cy='${y}' r='${r}' filter='url(#orbGlow)' class='q-orb' style='animation-duration:${bD}s, ${dD}s;animation-delay:${del}s, ${del}s' />`;
    }
  }

  svg += `</svg>`;
  return `url(data:image/svg+xml;base64,${btoa(svg)})`;
}

function computeRuntime(shader: SurfaceMaterialShader, devicePixelRatio: number): SurfaceRuntime {
  const dpr = clamp(devicePixelRatio, 1, 2.5);
  const mX = shader.mode === "glass" ? 1 : 0;
  const bPx = clamp(Math.sqrt(dpr) * shader.blurPx * mX, 0, 28);
  const sPct = clamp(100 + (shader.saturatePct - 100) * mX, 90, 220);
  const rG = clamp(1 + shader.edgeIntensity * 0.22 * mX, 1, 1.26);
  const aS = clamp((shader.opacityScale / rG) * (mX > 0 ? 1 : 1.12), 0.68, 1.55);
  const aW = clamp(Math.round(shader.edgeIntensity * 40 * mX), 0, 256);
  if (mX < 0.5 || bPx < 0.25) return { filter: "none", alphaScale: aS, ambientWeight: 0 };
  return { filter: `blur(${bPx.toFixed(2)}px) saturate(${sPct.toFixed(1)}%)`, alphaScale: aS, ambientWeight: aW };
}

function resolveMotionRuntime(motion: SurfaceMaterialShader["motion"]): MotionRuntime {
  if (!motion) {
    return DEFAULT_MOTION_RUNTIME;
  }
  return MOTION_RUNTIME_BY_KIND[motion] ?? DEFAULT_MOTION_RUNTIME;
}

function applyOverlayRuntime(root: HTMLElement, p: RgbaColor | null, ambient: RgbaColor | null, tgt: string, aS: number, aW: number): void {
  if (!p) { root.style.removeProperty(tgt); return; }
  let r = p.r, g = p.g, b = p.b;
  if (ambient && aW > 0) { r += ((ambient.r - r) * aW) >> 8; g += ((ambient.g - g) * aW) >> 8; b += ((ambient.b - b) * aW) >> 8; }
  root.style.setProperty(tgt, toRgbaString({ r: clamp(r, 0, CHANNEL_MAX), g: clamp(g, 0, CHANNEL_MAX), b: clamp(b, 0, CHANNEL_MAX), a: clamp(p.a * aS, 0, 0.985) }));
}

function applyStateTintRuntime(root: HTMLElement, p: RgbaColor | null, tgt: string, alpha: number): void {
  if (!p) { root.style.removeProperty(tgt); return; }
  root.style.setProperty(tgt, toRgbaString({ r: p.r, g: p.g, b: p.b, a: clamp(alpha, 0, 0.985) }));
}

export function applySurfaceMaterial(shader: SurfaceMaterialShader, root: HTMLElement): void {
  if (typeof window === "undefined") return;
  const runtime = computeRuntime(shader, window.devicePixelRatio || 1);
  root.style.setProperty("--runtime-glass-filter", runtime.filter);
  const cS = window.getComputedStyle(root);
  const parsedColorCache = new Map<string, RgbaColor | null>();
  const getParsedColor = (source: string): RgbaColor | null => {
    if (parsedColorCache.has(source)) {
      return parsedColorCache.get(source) ?? null;
    }
    const parsed = parseCssColor(cS.getPropertyValue(source));
    parsedColorCache.set(source, parsed);
    return parsed;
  };
  const rA = cS.getPropertyValue("--theme-ambient-rgb").trim();
  const ambient = rA ? parseCssColor(`rgb(${rA})`) : null;
  root.style.setProperty("--runtime-material-texture", generateProceduralTexture(shader, ambient));
  const particles = generateProceduralParticles(shader, ambient);
  if (typeof particles === "string") {
    root.style.setProperty("--runtime-material-particles", particles);
    ["near", "mid", "far", "bg"].forEach(l => root.style.removeProperty(`--runtime-material-particles-${l}`));
  } else {
    root.style.setProperty("--runtime-material-particles", "none");
    Object.entries(particles).forEach(([k, v]) => root.style.setProperty(`--runtime-material-particles-${k}`, v));
  }
  const interaction = shader.interaction ?? "none";
  root.style.setProperty("--runtime-interaction-signature", interaction);
  document.documentElement.setAttribute("data-interaction", interaction);
  if (interaction === "vibration") root.style.setProperty("--runtime-vibration-speed", "0.2s");
  else if (interaction === "caustic") root.style.setProperty("--runtime-caustic-speed", "3s");
  else if (interaction === "etch") root.style.setProperty("--runtime-etch-offset", "1px");
  else if (interaction === "warp") root.style.setProperty("--runtime-warp-scale", "1.05");
  else if (interaction === "chalk") root.style.setProperty("--runtime-chalk-jitter", "8ms");

  const motionRuntime = resolveMotionRuntime(shader.motion);
  root.style.setProperty("--runtime-ease", motionRuntime.ease);
  root.style.setProperty("--runtime-duration", motionRuntime.duration);
  root.style.setProperty("--runtime-parallax-strength", (shader.parallaxStrength ?? 0.5).toString());
  root.style.setProperty("--runtime-radius", `${shader.geometry?.radius ?? 8}px`);
  if (shader.geometry?.pixelated) { root.style.setProperty("--runtime-image-render", "pixelated"); root.style.setProperty("--runtime-font-smooth", "none"); }
  else { root.style.setProperty("--runtime-image-render", "auto"); root.style.setProperty("--runtime-font-smooth", "antialiased"); }
  if (shader.geometry?.typography) root.style.setProperty("--runtime-font-family", shader.geometry.typography); else root.style.removeProperty("--runtime-font-family");
  if (shader.geometry?.fontScale) root.style.setProperty("--runtime-font-scale", shader.geometry.fontScale.toString()); else root.style.removeProperty("--runtime-font-scale");
  if (shader.geometry?.letterSpacing) root.style.setProperty("--runtime-letter-spacing", shader.geometry.letterSpacing); else root.style.removeProperty("--runtime-letter-spacing");

  if (ambient) {
    root.style.setProperty("--runtime-cell-shadow", `rgba(${ambient.r >> 1}, ${ambient.g >> 1}, ${ambient.b >> 1}, 0.45)`);
    root.style.setProperty("--runtime-rim-light", `rgba(${ambient.r}, ${ambient.g}, ${ambient.b}, ${clamp(runtime.alphaScale * 0.35, 0.05, 0.8).toFixed(2)})`);
    const lum = clamp(shader.luminescence ?? 1, 0, 3), gR = 12 * Math.max(1, lum);
    root.style.setProperty("--runtime-glow-shadow", `0 0 ${gR.toFixed(1)}px rgba(${ambient.r}, ${ambient.g}, ${ambient.b}, ${clamp(0.2 * lum, 0, 0.8).toFixed(2)}), 0 0 2px rgba(${ambient.r}, ${ambient.g}, ${ambient.b}, ${clamp(0.15 * lum, 0, 1).toFixed(2)})`);
  } else {
    root.style.setProperty("--runtime-cell-shadow", "rgba(0,0,0,0.5)"); root.style.setProperty("--runtime-rim-light", "rgba(255,255,255,0.1)"); root.style.setProperty("--runtime-glow-shadow", "0 0 8px rgba(255,255,255,0.15)");
  }
  for (const b of OVERLAY_BINDINGS) applyOverlayRuntime(root, getParsedColor(b.source), ambient, b.target, runtime.alphaScale, runtime.ambientWeight);
  for (const b of STATE_TINT_BINDINGS) applyStateTintRuntime(root, getParsedColor(b.source), b.target, b.alpha);
}
