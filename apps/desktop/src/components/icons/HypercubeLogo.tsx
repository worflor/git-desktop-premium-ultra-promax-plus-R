import { createSignal, onMount, onCleanup, For, createMemo } from "solid-js";

/**
 * HypercubeLogo - An ultra-high-fidelity, 4D Tesseract projection logo.
 * Refined for Organic Unpredictability:
 * - Stochastic speed variance (natural tempo drift).
 * - Multi-dimensional jitter and axis-drift.
 * - Non-linear superposition (hypnotic ghosting).
 * - Harmonic Breathing & Bioluminescence.
 */

// Vertices of a Tesseract (4D Hypercube)
const VERTICES: [number, number, number, number][] = Array.from({ length: 16 }, (_, i) => [
  (i & 1) ? 1 : -1,
  (i & 2) ? 1 : -1,
  (i & 4) ? 1 : -1,
  (i & 8) ? 1 : -1
]);

// Edges of a Tesseract (32 edges)
const EDGES: [number, number][] = [];
for (let i = 0; i < 16; i++) {
  for (let j = i + 1; j < 16; j++) {
    const diff = i ^ j;
    if (diff && (diff & (diff - 1)) === 0) {
      EDGES.push([i, j]);
    }
  }
}

// 16 Geometric "States"
const STATES: [number, number, number, number, number, number][] = [
  [0, 0, 0, 0, 0, 0], [0.3, 0.2, 0.4, 0.1, 0.2, 0.1], [0.8, 0.4, 0.9, 0.3, 0.5, 0.2],
  [1.2, 0.8, 1.4, 0.6, 0.9, 0.4], [Math.PI/2, Math.PI/4, Math.PI/2, 0.5, 1.2, 0.8],
  [2.1, 1.2, 2.5, 0.9, 1.8, 1.1], [2.8, 1.8, 3.2, 1.4, 2.4, 1.6], [Math.PI, 2.1, 3.8, 2.0, 3.0, 2.2],
  [3.8, Math.PI, 4.5, 2.6, 3.8, 2.9], [4.5, 3.8, 5.2, 3.2, 4.5, 3.6], [5.2, 4.5, 6.0, 4.0, 5.2, 4.4],
  [Math.PI*1.8, 5.2, 6.8, 4.8, 6.0, 5.2], [Math.PI*2, Math.PI*2, Math.PI*2, 0, 0, 0],
  [0.5, 1.2, 2.4, 4.1, 0.8, 1.9], [1.8, 0.4, 3.2, 0.9, 5.1, 2.4], [Math.PI/3, Math.PI/3, Math.PI/3, Math.PI/3, Math.PI/3, Math.PI/3]
];

interface ProjectPoint { x: number; y: number; z: number; w: number; }
interface HypercubeLogoProps { size?: number; class?: string; themeColor?: string; speed?: number; }

export function HypercubeLogo(props: HypercubeLogoProps) {
  const [time, setTime] = createSignal(0);
  const [currentIdx, setCurrentIdx] = createSignal(0);
  const [targetIdx, setTargetIdx] = createSignal(Math.floor(Math.random() * 16));
  const [transition, setTransition] = createSignal(0);
  const [tSpeed, setTSpeed] = createSignal(0.08 + Math.random() * 0.1); // Randomized transition speed

  let lastTime = 0;
  let frameReq: number;

  const animate = (timestamp: number) => {
    if (!lastTime) lastTime = timestamp;
    const deltaTime = (timestamp - lastTime) / 1000;
    lastTime = timestamp;

    // Organic speed variance: uses a superposition of sines to simulate natural drift
    const drift = 1 + Math.sin(timestamp * 0.0005) * 0.05 + Math.cos(timestamp * 0.0008) * 0.03;
    const globalDelta = (props.speed ?? 0.85) * drift;
    setTime(t => t + deltaTime * globalDelta);

    // Transition with non-linear stochastic pacing
    const nextTransition = transition() + (tSpeed() * deltaTime * globalDelta);
    if (nextTransition >= 1) {
      setCurrentIdx(targetIdx());
      setTargetIdx(Math.floor(Math.random() * STATES.length));
      setTransition(0);
      setTSpeed(0.06 + Math.random() * 0.15); // Pick a new speed for the next journey
    } else {
      setTransition(nextTransition);
    }

    frameReq = requestAnimationFrame(animate);
  };

  onMount(() => { frameReq = requestAnimationFrame(animate); });
  onCleanup(() => { cancelAnimationFrame(frameReq); });

  const size = () => props.size ?? 24;

  const projectVertices = (scaleFactor: number, timeOffset: number, stateInterp: number, breathing: boolean = false) => {
    const startState = STATES[currentIdx()]!;
    const endState = STATES[targetIdx()]!;
    
    // Cubic hermite spline for organic transition curve
    const s = stateInterp * stateInterp * (3 - 2 * stateInterp);
    const angles = startState.map((a, i) => a + (endState[i]! - a) * s);

    const t = time() + timeOffset;
    // Breathing with phase noise
    const breath = breathing ? (1 + Math.sin(t * 0.4 + Math.sin(t * 0.1) * 0.5) * 0.06) : 1;

    return VERTICES.map(v => {
      let [x, y, z, w] = v;
      const [xy, xz, xw, yz, yw, zw] = angles as [number, number, number, number, number, number];

      // Add fluid axis-drift that prevents perfect repetition
      const qxy = xy + Math.sin(t * 0.25) * 0.1;
      const qxz = xz + Math.cos(t * 0.15) * 0.05;
      const qxw = xw + Math.sin(t * 0.12) * 0.08;
      const qzw = zw + Math.cos(t * 0.35) * 0.1;

      let tx, ty, tz, tw;
      tx = x * Math.cos(qxy) - y * Math.sin(qxy); ty = x * Math.sin(qxy) + y * Math.cos(qxy); [x, y] = [tx, ty];
      tx = x * Math.cos(qxz) - z * Math.sin(qxz); tz = x * Math.sin(qxz) + z * Math.cos(qxz); [x, z] = [tx, tz];
      tx = x * Math.cos(qxw) - w * Math.sin(qxw); tw = x * Math.sin(qxw) + w * Math.cos(qxw); [x, w] = [tx, tw];
      ty = y * Math.cos(yz) - z * Math.sin(yz); tz = y * Math.sin(yz) + z * Math.cos(yz); [y, z] = [ty, tz];
      ty = y * Math.cos(yw) - w * Math.sin(yw); tw = y * Math.sin(yw) + w * Math.cos(yw); [y, w] = [ty, tw];
      tz = z * Math.cos(qzw) - w * Math.sin(qzw); tw = z * Math.sin(qzw) + w * Math.cos(qzw); [z, w] = [tz, tw];

      const distance4D = 2.45 + Math.sin(t * 0.15) * 0.12; 
      const fov4D = 1 / (distance4D - w);
      x *= fov4D; y *= fov4D; z *= fov4D;

      const distance3D = 3.6;
      const fov3D = 1 / (distance3D - z);
      x *= fov3D; y *= fov3D;

      const sVal = size();
      const scale = sVal * 1.55 * scaleFactor * breath;
      return { x: (x * scale) + sVal / 2, y: (y * scale) + sVal / 2, z, w };
    });
  };

  const layer0 = createMemo(() => projectVertices(1.0, 0, transition(), true));
  const layer1 = createMemo(() => projectVertices(1.0, -0.45, transition(), true)); // Lagged ghost
  const layer2 = createMemo(() => projectVertices(0.58, 20, transition(), false)); // Deep core

  return (
    <svg width={size()} height={size()} viewBox={`0 0 ${size()} ${size()}`} class={`hypercube-logo ${props.class ?? ""}`} xmlns="http://www.w3.org/2000/svg" shape-rendering="geometricPrecision" style={{ overflow: "visible" }}>
      <defs>
        <filter id="hyper-glow" x="-150%" y="-150%" width="400%" height="400%">
          <feGaussianBlur in="SourceGraphic" stdDeviation="0.8" result="blur" />
          <feColorMatrix in="blur" type="saturate" values="1.6" result="bright" />
          <feComposite in="SourceGraphic" in2="bright" operator="over" />
        </filter>
      </defs>
      
      <g stroke={props.themeColor ?? "currentColor"} stroke-linecap="round" stroke-linejoin="round" opacity="0.2">
        <For each={EDGES}>{([i, j]) => {
          const p1 = () => layer1()[i]; const p2 = () => layer1()[j];
          return ( <line x1={p1()?.x ?? 0} y1={p1()?.y ?? 0} x2={p2()?.x ?? 0} y2={p2()?.y ?? 0} stroke-width="0.4" /> );
        }}</For>
      </g>

      <g fill="none" stroke={props.themeColor ?? "currentColor"} stroke-linecap="round" stroke-linejoin="round" filter="url(#hyper-glow)">
        <For each={EDGES}>{([i, j]) => {
          const p1 = () => layer0()[i]; const p2 = () => layer0()[j];
          const depth = () => { const pt1 = p1(); const pt2 = p2(); return pt1 && pt2 ? (pt1.z + pt2.z + pt1.w + pt2.w) / 4 : 0; };
          const opacity = () => 0.18 + (0.82 * (depth() + 2) / 4);
          const sW = () => 0.4 + (1.3 * opacity()) + Math.sin(time() * 2 + i) * 0.05; // Organic line jitter
          return ( <line x1={p1()?.x ?? 0} y1={p1()?.y ?? 0} x2={p2()?.x ?? 0} y2={p2()?.y ?? 0} stroke-opacity={opacity()} stroke-width={sW()} /> );
        }}</For>
      </g>

      <g fill="none" stroke={props.themeColor ?? "currentColor"} stroke-linecap="round" stroke-linejoin="round" stroke-opacity="0.25">
        <For each={EDGES}>{([i, j]) => {
          const p1 = () => layer2()[i]; const p2 = () => layer2()[j];
          return ( <line x1={p1()?.x ?? 0} y1={p1()?.y ?? 0} x2={p2()?.x ?? 0} y2={p2()?.y ?? 0} stroke-width="0.3" stroke-dasharray="0.6 6">
              <animate attributeName="stroke-dashoffset" values="0;12" dur="10s" repeatCount="indefinite" />
          </line> );
        }}</For>
      </g>
    </svg>
  );
}
