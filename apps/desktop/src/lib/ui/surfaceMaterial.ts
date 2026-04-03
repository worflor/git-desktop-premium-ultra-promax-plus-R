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
    radius?: number; // base border radius scale
    pixelated?: boolean; // toggle nearest-neighbor and disable anti-aliasing
    typography?: string; // inject a custom font family
    fontScale?: number; // scaling factor for fonts that naturally render small
    letterSpacing?: string; // custom kerning for high-end feel
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

function generateProceduralTexture(shader: SurfaceMaterialShader, ambient: RgbaColor | null): string {
  const intensity = clamp(shader.textureOpacity ?? 0, 0, 1);
  if (intensity === 0 || !shader.texture || shader.texture === "none") return "none";

  // We construct mathematical SVG matrices directly in string memory to avoid loading payload assets.
  // Circle XIX insists on eliminating I/O bottleneck; Base64 generative matrices execute inside the layout layer.
  let svg = "";
  const baseFill = ambient ? `rgba(${ambient.r},${ambient.g},${ambient.b},1)` : "black";
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
  } else if (shader.texture === "pixels") {
    // A 16x16 mosaic block generation mimicking Minecraft dirt/stone patterns using actual color arrays
    svg = `<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'>`;
    const darkLuma = ambient ? `rgba(${ambient.r > 20 ? ambient.r - 20 : 0}, ${ambient.g > 20 ? ambient.g - 20 : 0}, ${ambient.b > 20 ? ambient.b - 20 : 0}, 1)` : "black";
    // First, fill base
    svg += `<rect width='16' height='16' fill='${baseFill}' opacity='${(intensity * 0.5).toFixed(2)}'/>`;
    for (let x = 0; x < 16; x += 4) {
      for (let y = 0; y < 16; y += 4) {
        const noiseType = Math.abs(Math.sin(x * 12.3 + y * 4.5));
        if (noiseType > 0.5) {
          svg += `<rect x='${x}' y='${y}' width='4' height='4' fill='${darkLuma}' opacity='${intensity.toFixed(2)}'/>`;
        }
      }
    }
    svg += `</svg>`;
  }

  // Btoa executes in highly-optimized engine C++ code, transforming raw markup to a CSS background payload.
  return `url(data:image/svg+xml;base64,${btoa(svg)})`;
}

export type ParticlePayload = string | { near: string; mid: string; far: string; bg: string; };

function generateProceduralParticles(shader: SurfaceMaterialShader, ambient: RgbaColor | null): ParticlePayload {
  if (!shader.particles || shader.particles === "none") return "none";

  // Base physical dimensions. A large matrix repeats natively over the CSS viewport infinitely.
  let svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1000 1000' preserveAspectRatio='none'>`;
  const baseFill = ambient ? toRgbaString({...ambient, a: 0.1}) : "rgba(255,255,255,0.1)";

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
    // Relativistic EM Wave Simulator v3: Performance-Optimized Silky Oscillation
    // Specialized wave-path generator (Simplified for FPS)
    const generateWave = (i: number, freq: number, amplitude: number, color: string, dur: number) => {
      const w = (Math.abs(Math.cos(i * 44)) * 1.5 + 1).toFixed(1);
      let d = `M 0 0 `;
      // Fewer points (80px steps instead of 40px) for better performance
      for (let x_pos = 0; x_pos <= 1200; x_pos += 80) {
        const y_off = Math.sin(x_pos * freq + i) * amplitude;
        d += `L ${y_off.toFixed(1)} ${x_pos} `;
      }
      return `<path d='${d}' fill='none' stroke='${color}' stroke-width='${w}' stroke-linecap='round' stroke-opacity='0' style='animation: waveFall ${dur}s linear infinite; animation-delay: ${(Math.sin(i*77)*-15).toFixed(1)}s; will-change: transform;' />`;
    };

    const style = `<style>
      @keyframes waveFall { 
        0% { transform: translateY(-400px) scaleY(1) translateZ(0); opacity: 0; }
        15% { opacity: 0.5; }
        100% { transform: translateY(1200px) scaleY(1.5) translateZ(0); opacity: 0; }
      }
    </style>`;

    // Render 3 distinct spectral layers with reduced particle counts
    const buildLayer = (count: number, freq: number, amp: number, color: string, speedBase: number) => {
      let lSvg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1000 1000' preserveAspectRatio='none'>${style}`;
      for (let i = 0; i < count; i++) {
        lSvg += generateWave(i, freq, amp, color, speedBase + Math.random() * 2);
      }
      lSvg += `</svg>`;
      return typeof window !== 'undefined' ? `url(data:image/svg+xml;base64,${window.btoa(lSvg)})` : "";
    };

    const near = buildLayer(12, 0.05, 12, "#ff0044", 2.0);
    const mid = buildLayer(8, 0.03, 8, "#880022", 4.0);
    const far = buildLayer(6, 0.015, 4, "#3a0510", 7.0);
    
    // We Return the layered stack for CSS interpretation (Removed bg/noise/ugly grain)
    return { near, mid, far, bg: "none" };
  } else if (shader.particles === "voxels") {
    // Large, rigid rotating cubes falling computationally
    svg += `<style>
      .voxel { animation: drop linear infinite; fill: ${baseFill}; transform-origin: center; }
      @keyframes drop { 0% { transform: translateY(-100px) rotate(0deg); opacity: 0;} 10% {opacity: 0.3;} 90% {opacity: 0.3;} 100% { transform: translateY(1100px) rotate(360deg); opacity: 0; } }
    </style>`;
    for (let i = 0; i < 15; i++) {
      const x = (Math.sin(i * 444) * 500 + 500).toFixed(1);
      const s = (Math.abs(Math.sin(i * 33)) * 20 + 10).toFixed(1);
      const dur = (Math.abs(Math.sin(i * 22)) * 15 + 10).toFixed(1);
      const del = (Math.abs(Math.sin(i * 11)) * 15).toFixed(1);
      svg += `<rect x='${x}' y='0' width='${s}' height='${s}' class='voxel' style='animation-duration:${dur}s;animation-delay:${del}s' />`;
    }
  } else if (shader.particles === "chalkdust") {
    // Augmented Eldritch Geometry: Lissajous Harmonic Resonance with Physical Variability
    const chalkColors = [baseFill, baseFill, "rgba(255, 130, 140, 0.6)", "rgba(150, 210, 255, 0.6)", "rgba(255, 220, 120, 0.6)"];
    
    svg += `<style>
      .chalk-line { fill: none; stroke-linecap: round; stroke-linejoin: round; opacity: 0; animation: mathplot linear infinite backwards; }
      @keyframes mathplot {
        0% { stroke-dashoffset: 200; opacity: 0; }
        5% { opacity: 0.4; }
        90% { opacity: 0.4; }
        100% { stroke-dashoffset: 0; opacity: 0; }
      }
      .chalk-filter { filter: url(#rough); }
    </style>
    <filter id="rough"><feTurbulence type="fractalNoise" baseFrequency="0.5" numOctaves="3" result="noise"/><feDisplacementMap in="SourceGraphic" in2="noise" scale="2.5" xChannelSelector="R" yChannelSelector="G"/></filter>`;
    
    // Generate 8-Layer Spectral Harmonic Synthesis
    for (let i = 1; i <= 8; i++) {
      const cx = (Math.sin(i * 1.5) * 450 + 500).toFixed(1);
      const cy = (Math.cos(i * 2.5) * 400 + 500).toFixed(1);
      
      const a = Math.round(Math.abs(Math.sin(i * 3)) * 4 + 1); // Harmonic X
      const b = Math.round(Math.abs(Math.cos(i * 4)) * 3 + 2); // Harmonic Y
      const delta = (Math.PI / i) * 1.5;
      const radius = (Math.abs(Math.sin(i * 5)) * 120 + 80).toFixed(1);
      
      let d = "";
      const steps = 140;
      for (let t = 0; t <= Math.PI * 2.1; t += (Math.PI * 2 / steps)) {
        // Amplitude Modulation: Subtle high-frequency jitter (Smart Math)
        const jitter = (Math.sin(t * 40 + i) * 2.5);
        const x = (Math.sin(a * t + delta) * (+radius + jitter) + +cx).toFixed(1);
        const y = (Math.sin(b * t) * (+radius + jitter) + +cy).toFixed(1);
        d += t === 0 ? `M ${x} ${y} ` : `L ${x} ${y} `;
      }
      
      const dur = (Math.abs(Math.sin(i * 88)) * 40 + 50).toFixed(1);
      const del = (Math.abs(Math.sin(i * 55)) * -60).toFixed(1); 
      const strokeW = (i <= 4) ? (Math.random() * 1 + 0.8).toFixed(1) : (Math.random() * 0.5 + 0.3).toFixed(1);
      const color = chalkColors[i % chalkColors.length];
      const skip = (i % 3 === 0) ? `${Math.random()*40+10} ${Math.random()*20+5}` : "none";

      svg += `<path d="${d}" class="chalk-line chalk-filter" stroke="${color}" stroke-width="${strokeW}" pathLength="200" stroke-dasharray="200" style="animation-duration:${dur}s;animation-delay:${del}s;stroke-dasharray:${skip === 'none' ? '200' : skip}" />`;
    }
  } else if (shader.particles === "void") {
    // Abyssal Void Engine: Fast-falling Digital Rain + Glitch Fragments
    svg += `<style>
      .rain { animation: drop linear infinite; fill: #00f0ff; opacity: 0; }
      .glitch { animation: glitchStroke steps(2) infinite; stroke: #cccccc; opacity: 0; }
      @keyframes drop { 0% { transform: translateY(-100px) scaleY(0.5); opacity: 0; } 10% { opacity: 0.8; } 90% { opacity: 0.8; } 100% { transform: translateY(1100px) scaleY(2); opacity: 0; } }
      @keyframes glitchStroke { 0% { transform: translate(0, 0); opacity: 0; } 5% { opacity: 1; transform: translate(20px, 0); } 10% { opacity: 0; transform: translate(-20px, 10px); } 100% { opacity: 0; } }
    </style>`;
    
    // Falling digital drops (Vertical 1px lines)
    for (let i = 0; i < 60; i++) {
      const x = (Math.random() * 1000).toFixed(1);
      const w = 1;
      const h = (Math.random() * 40 + 20).toFixed(1);
      const dur = (Math.random() * 0.8 + 0.6).toFixed(1); // Fast 0.6s - 1.4s
      const del = (Math.random() * -3).toFixed(1);
      svg += `<rect x='${x}' y='0' width='${w}' height='${h}' class='rain' style='animation-duration:${dur}s;animation-delay:${del}s' />`;
    }

    // Digital Guttering: Rain intensity is spatially aware via CSS masks.
    // Floating Signal fragments removed to focus on atmospheric rain density.
  } else if (shader.particles === "quantum") {
    // Subatomic Quantum Engine: Luminous Orbs with 'Subatomic Shimmer' (Smooth breathing)
    svg += `<style>
      .quantum-orb { animation: breathe ease-in-out infinite alternate, quantumDrift linear infinite; fill: #00ff88; }
      @keyframes breathe { 0% { transform: scale(0.6); opacity: 0.3; filter: brightness(1); } 100% { transform: scale(1.4); opacity: 0.8; filter: brightness(1.6); } }
      @keyframes quantumDrift { 0% { transform: translate(0, 0); } 100% { transform: translate(40px, -40px); } }
    </style>
    <filter id='orbGlow'><feGaussianBlur in='SourceGraphic' stdDeviation='1'/></filter>`;
    
    // Smoothly pulsing subatomic orbs
    for (let i = 0; i < 45; i++) {
      const x = (Math.sin(i * 123) * 500 + 500).toFixed(1);
      const y = (Math.cos(i * 456) * 500 + 500).toFixed(1);
      const r = (Math.abs(Math.sin(i * 789)) * 1.5 + 0.5).toFixed(1); // Slightly larger for better visibility
      const breathDur = (Math.abs(Math.sin(i * 11)) * 3 + 2).toFixed(1); // 2s - 5s slow breathe
      const driftDur = (Math.abs(Math.cos(i * 22)) * 40 + 40).toFixed(1); // 40s - 80s slow drift
      const del = (Math.abs(Math.sin(i * 33)) * -20).toFixed(1);
      svg += `<circle cx='${x}' cy='${y}' r='${r}' filter='url(#orbGlow)' class='quantum-orb' style='animation-duration:${breathDur}s, ${driftDur}s;animation-delay:${del}s, ${del}s' />`;
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
  root.style.setProperty("--runtime-material-texture", generateProceduralTexture(shader, ambientColor));
  
  const particles = generateProceduralParticles(shader, ambientColor);
  if (typeof particles === "string") {
    root.style.setProperty("--runtime-material-particles", particles);
    root.style.removeProperty("--runtime-material-particles-near");
    root.style.removeProperty("--runtime-material-particles-mid");
    root.style.removeProperty("--runtime-material-particles-far");
    root.style.removeProperty("--runtime-material-particles-bg");
  } else {
    // Narrowing for multi-layer particles
    const layered = particles as { near: string; mid: string; far: string; bg: string; };
    root.style.setProperty("--runtime-material-particles", "none");
    root.style.setProperty("--runtime-material-particles-near", layered.near);
    root.style.setProperty("--runtime-material-particles-mid", layered.mid);
    root.style.setProperty("--runtime-material-particles-far", layered.far);
    root.style.setProperty("--runtime-material-particles-bg", layered.bg);
  }
  
  // Interaction Logic: The Math of Tactile Feedback
  const interaction = shader.interaction ?? "none";
  root.style.setProperty("--runtime-interaction-signature", interaction);
  document.documentElement.setAttribute("data-interaction", interaction);
  
  if (interaction === "vibration") {
    // High-frequency interference pattern speed (DPR balanced)
    root.style.setProperty("--runtime-vibration-speed", "0.2s");
  } else if (interaction === "caustic") {
    // Rotational speed of the prismatic caustic leak
    root.style.setProperty("--runtime-caustic-speed", "3s");
  } else if (interaction === "etch") {
    // Mechanical shift offset
    root.style.setProperty("--runtime-etch-offset", "1px");
  } else if (interaction === "warp") {
    // Scale and distortion intensity
    root.style.setProperty("--runtime-warp-scale", "1.05");
  } else if (interaction === "chalk") {
    // Jitter frequency for blackboard
    root.style.setProperty("--runtime-chalk-jitter", "8ms");
  }

  // Determine physical kinematic (motion) variables
  let ease = "cubic-bezier(0.2, 0, 0, 1)";
  let duration = "120ms";
  if (shader.motion === "snappy") { ease = "cubic-bezier(0.3, 0.0, 0.1, 1)"; duration = "80ms"; }
  if (shader.motion === "fluid") { ease = "cubic-bezier(0.4, 0, 0.2, 1)"; duration = "180ms"; }
  if (shader.motion === "elastic") { ease = "cubic-bezier(0.68, -0.55, 0.26, 1.55)"; duration = "250ms"; }
  root.style.setProperty("--runtime-ease", ease);
  root.style.setProperty("--runtime-duration", duration);
  root.style.setProperty("--runtime-parallax-strength", (shader.parallaxStrength ?? 0.5).toString());

  // Geometric Parameters Mapping
  const radiusBase = shader.geometry?.radius ?? 8;
  root.style.setProperty("--runtime-radius", `${radiusBase}px`);

  if (shader.geometry?.pixelated) {
    root.style.setProperty("--runtime-image-render", "pixelated");
    root.style.setProperty("--runtime-font-smooth", "none");
  } else {
    root.style.setProperty("--runtime-image-render", "auto");
    root.style.setProperty("--runtime-font-smooth", "antialiased");
  }

  if (shader.geometry?.typography) {
    root.style.setProperty("--runtime-font-family", shader.geometry.typography);
  } else {
    root.style.removeProperty("--runtime-font-family");
  }

  if (shader.geometry?.fontScale) {
    root.style.setProperty("--runtime-font-scale", shader.geometry.fontScale.toString());
  } else {
    root.style.removeProperty("--runtime-font-scale");
  }

  if (shader.geometry?.letterSpacing) {
    root.style.setProperty("--runtime-letter-spacing", shader.geometry.letterSpacing);
  } else {
    root.style.removeProperty("--runtime-letter-spacing");
  }

  if (ambientColor) {
    // Generate unified cell-shading artifacts using bitshift halving for the hard shadow
    const shadowR = ambientColor.r >> 1;
    const shadowG = ambientColor.g >> 1;
    const shadowB = ambientColor.b >> 1;
    root.style.setProperty("--runtime-cell-shadow", `rgba(${shadowR}, ${shadowG}, ${shadowB}, 0.45)`);
    
    // Clean Rim Light: Restoring pure, high-transparency edge definition
    const rimAlpha = clamp(runtime.alphaScale * 0.35, 0.05, 0.8);
    root.style.setProperty("--runtime-rim-light", `rgba(${ambientColor.r}, ${ambientColor.g}, ${ambientColor.b}, ${rimAlpha.toFixed(2)})`);

    // Scale the luminescence multiplier through algorithmic box-shadow interpolation
    const lum = clamp(shader.luminescence ?? 1.0, 0, 3.0);
    const glowRadius = 12 * Math.max(1, lum);
    const glowAlpha = clamp((ambientColor.a ?? 1) * 0.2 * lum, 0, 0.8);
    const hardAlpha = clamp(0.15 * lum, 0, 1.0);
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
