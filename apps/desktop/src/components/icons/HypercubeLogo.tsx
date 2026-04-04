import { createSignal, onMount, onCleanup, For, createMemo } from "solid-js";

/**
 * HypercubeLogo - An ultra-high-fidelity, 4D Tesseract projection logo.
 * Structural Interactivity Edition:
 * - Whole-Structure 4D Tilting (Structural reaction).
 * - Kinetic Structural Dragging (The entire shape resists and warps).
 * - Zero Text Selection / Interference.
 * - Reactive "Gravitational" Lensing.
 */

const VERTICES: [number, number, number, number][] = Array.from({ length: 16 }, (_, i) => [
  (i & 1) ? 1 : -1, (i & 2) ? 1 : -1, (i & 4) ? 1 : -1, (i & 8) ? 1 : -1
]);

const EDGES: [number, number][] = [];
for (let i = 0; i < 16; i++) {
  for (let j = i + 1; j < 16; j++) {
    const diff = i ^ j;
    if (diff && (diff & (diff - 1)) === 0) EDGES.push([i, j]);
  }
}

const STATES: [number, number, number, number, number, number][] = [
  [0, 0, 0, 0, 0, 0], [0.3, 0.2, 0.4, 0.1, 0.2, 0.1], [0.8, 0.4, 0.9, 0.3, 0.5, 0.2],
  [1.2, 0.8, 1.4, 0.6, 0.9, 0.4], [Math.PI/2, Math.PI/4, Math.PI/2, 0.5, 1.2, 0.8],
  [2.1, 1.2, 2.5, 0.9, 1.8, 1.1], [2.8, 1.8, 3.2, 1.4, 2.4, 1.6], [Math.PI, 2.1, 3.8, 2.0, 3.0, 2.2],
  [3.8, Math.PI, 4.5, 2.6, 3.8, 2.9], [4.5, 3.8, 5.2, 3.2, 4.5, 3.6], [5.2, 4.5, 6.0, 4.0, 5.2, 4.4],
  [Math.PI*1.8, 5.2, 6.8, 4.8, 6.0, 5.2], [Math.PI*2, Math.PI*2, Math.PI*2, 0, 0, 0],
  [0.2, 0.3, 0.5, 0.8, 1.2, 1.5], [1.5, 1.2, 0.8, 0.5, 0.3, 0.2]
];

export function HypercubeLogo(props: { size?: number; class?: string; themeColor?: string; speed?: number; }) {
  const [time, setTime] = createSignal(0);
  const [currentIdx, setCurrentIdx] = createSignal(0);
  const [targetIdx, setTargetIdx] = createSignal(Math.floor(Math.random() * STATES.length));
  const [transition, setTransition] = createSignal(0);
  const [isNear, setIsNear] = createSignal(0);
  const [isDragging, setIsDragging] = createSignal(false);
  
  // Interaction states
  const [tilt, setTilt] = createSignal({ x: 0, y: 0 }); // Structural tilt
  const [warp, setWarp] = createSignal({ x: 0, y: 0, vx: 0, vy: 0 }); // Global structural warp
  
  let lastTime = 0;
  let frameReq: number;
  let svgRef: SVGSVGElement | undefined;

  const animate = (timestamp: number) => {
    if (!lastTime) lastTime = timestamp;
    const dt = Math.min((timestamp - lastTime) / 1000, 0.033);
    lastTime = timestamp;

    const nearness = isNear();
    const dragging = isDragging();
    
    // Tempo
    const speedBoost = 1 + nearness * 1.5 + (dragging ? 2.5 : 0);
    const globalDelta = (props.speed ?? 0.8) * speedBoost;
    setTime(t => t + dt * globalDelta);

    // Transitions
    const nextTransition = transition() + (0.08 * dt * globalDelta);
    if (nextTransition >= 1) {
      setCurrentIdx(targetIdx());
      setTargetIdx(Math.floor(Math.random() * STATES.length));
      setTransition(0);
    } else {
      setTransition(nextTransition);
    }

    // Physics: Global warping return-to-rest
    if (!dragging) {
      const currentWarp = warp();
      const ax = -150 * currentWarp.x;
      const ay = -150 * currentWarp.y;
      const nVX = (currentWarp.vx + ax * dt) * 0.85;
      const nVY = (currentWarp.vy + ay * dt) * 0.85;
      setWarp({ x: currentWarp.x + nVX * dt, y: currentWarp.y + nVY * dt, vx: nVX, vy: nVY });
    }

    frameReq = requestAnimationFrame(animate);
  };

  onMount(() => { frameReq = requestAnimationFrame(animate); });
  onCleanup(() => { cancelAnimationFrame(frameReq); });

  const size = () => props.size ?? 24;

  const projectVertices = (scaleFactor: number, timeOffset: number, stateInterp: number, breathing: boolean = false) => {
    const startState = STATES[currentIdx()]!;
    const endState = STATES[targetIdx()]!;
    const s = stateInterp * stateInterp * (3 - 2 * stateInterp);
    const angles = startState.map((a, i) => a + (endState[i]! - a) * s);
    const t = time() + timeOffset;
    
    const { x: tX, y: tY } = tilt();
    const { x: wX, y: wY } = warp();

    return VERTICES.map((v) => {
      let [x, y, z, w] = v;
      // Add tilt-based 4D perturbation
      const [xy, xz, xw, yz, yw, zw] = angles.map((a, i) => {
         if (i === 0) return a + tX * 0.5; // XY
         if (i === 1) return a + tY * 0.5; // XZ
         return a;
      });

      // 4D Rotations
      let tx, ty, tz, tw;
      tx = x * Math.cos(xy) - y * Math.sin(xy); ty = x * Math.sin(xy) + y * Math.cos(xy); [x, y] = [tx, ty];
      tx = x * Math.cos(xz) - z * Math.sin(xz); tz = x * Math.sin(xz) + z * Math.cos(xz); [x, z] = [tx, tz];
      tx = x * Math.cos(xw) - w * Math.sin(xw); tw = x * Math.sin(xw) + w * Math.cos(xw); [x, w] = [tx, tw];
      ty = y * Math.cos(yz) - z * Math.sin(yz); tz = y * Math.sin(yz) + z * Math.cos(yz); [y, z] = [ty, tz];
      ty = y * Math.cos(yw) - w * Math.sin(yw); tw = y * Math.sin(yw) + w * Math.cos(yw); [y, w] = [ty, tw];
      tz = z * Math.cos(zw) - w * Math.sin(zw); tw = z * Math.sin(zw) + w * Math.cos(zw); [z, w] = [tz, tw];

      const distance4D = 2.5 + Math.sin(t * 0.2) * 0.05 + Math.abs(tX + tY) * 0.1;
      const fov4D = 1 / (distance4D - w);
      x *= fov4D; y *= fov4D; z *= fov4D;

      const distance3D = 3.5;
      const fov3D = 1 / (distance3D - z);
      x *= fov3D; y *= fov3D;

      const sVal = size();
      const breath = breathing ? (1 + Math.sin(t * 0.5) * 0.04) : 1;
      const scale = sVal * 1.55 * scaleFactor * breath;
      
      // Apply structural warp offset
      return { x: (x * scale) + sVal / 2 + wX, y: (y * scale) + sVal / 2 + wY, z, w };
    });
  };

  const layer0 = createMemo(() => projectVertices(1.0, 0, transition(), true));
  const layer1 = createMemo(() => projectVertices(1.0, -0.4, transition(), true)); 
  const layer2 = createMemo(() => projectVertices(0.6, 10, transition(), false));

  const handlePointerMove = (e: PointerEvent) => {
    if (!svgRef) return;
    const rect = svgRef.getBoundingClientRect();
    const x = (e.clientX - rect.left) / size();
    const y = (e.clientY - rect.top) / size();
    
    // Update Tilt (Structural Reactivity)
    setTilt({ x: (x - 0.5) * 2, y: (y - 0.5) * 2 });

    // Update Nearness
    const dist = Math.sqrt((x - 0.5)**2 + (y - 0.5)**2);
    setIsNear(Math.max(0, 1 - dist * 0.8));

    if (isDragging()) {
      const currentWarp = warp();
      // Whole-structure dragging
      setWarp({ x: (e.clientX - rect.left - size()/2), y: (e.clientY - rect.top - size()/2), vx: 0, vy: 0 });
    }
  };

  const handlePointerDown = (e: PointerEvent) => {
    e.preventDefault(); // BLOCK TEXT SELECTION
    setIsDragging(true);
    (e.target as Element).setPointerCapture(e.pointerId);
  };

  return (
    <svg 
      ref={svgRef}
      width={size()} height={size()} 
      viewBox={`0 0 ${size()} ${size()}`} 
      class={`hypercube-logo ${props.class ?? ""}`} 
      xmlns="http://www.w3.org/2000/svg" 
      shape-rendering="geometricPrecision" 
      style={{ 
        overflow: "visible", 
        cursor: isDragging() ? "grabbing" : "pointer", 
        "touch-action": "none",
        "user-select": "none",
        "-webkit-user-select": "none"
      }}
      onPointerMove={handlePointerMove}
      onPointerDown={handlePointerDown}
      onPointerUp={() => setIsDragging(false)}
      onPointerLeave={() => { setIsNear(0); setTilt({ x: 0, y: 0 }); }}
    >
      <defs>
        <filter id="hyper-glow" x="-200%" y="-200%" width="500%" height="500%">
          <feGaussianBlur in="SourceGraphic" stdDeviation={0.6 + isNear() * 0.5} result="blur" />
          <feColorMatrix in="blur" type="saturate" values={1.5 + isNear() * 1.5} result="bright" />
          <feComposite in="SourceGraphic" in2="bright" operator="over" />
        </filter>
      </defs>
      
      {/* Ghost Superposition */}
      <g stroke={props.themeColor ?? "currentColor"} stroke-linecap="round" stroke-linejoin="round" opacity={0.15 + isNear() * 0.1}>
        <For each={EDGES}>{([i, j]) => {
          const p1 = () => layer1()[i]; const p2 = () => layer1()[j];
          return ( <line x1={p1()?.x ?? 0} y1={p1()?.y ?? 0} x2={p2()?.x ?? 0} y2={p2()?.y ?? 0} stroke-width="0.35" /> );
        }}</For>
      </g>

      {/* Primary Structural Layer */}
      <g fill="none" stroke={props.themeColor ?? "currentColor"} stroke-linecap="round" stroke-linejoin="round" filter="url(#hyper-glow)">
        <For each={EDGES}>{([i, j]) => {
          const p1 = () => layer0()[i]; const p2 = () => layer0()[j];
          const depth = () => { const pt1 = p1(); const pt2 = p2(); return pt1 && pt2 ? (pt1.z + pt2.z + pt1.w + pt2.w) / 4 : 0; };
          const opacity = () => 0.18 + (0.82 * (depth() + 2) / 4) + isNear() * 0.2;
          const sW = () => 0.4 + (1.4 * opacity()) + (isDragging() ? 0.3 : 0);
          return ( <line x1={p1()?.x ?? 0} y1={p1()?.y ?? 0} x2={p2()?.x ?? 0} y2={p2()?.y ?? 0} stroke-opacity={opacity()} stroke-width={sW()} /> );
        }}</For>
      </g>

      {/* Spectral Core */}
      <g fill="none" stroke={props.themeColor ?? "currentColor"} stroke-linecap="round" stroke-linejoin="round" stroke-opacity={0.25 + isNear() * 0.2}>
        <For each={EDGES}>{([i, j]) => {
          const p1 = () => layer2()[i]; const p2 = () => layer2()[j];
          return ( <line x1={p1()?.x ?? 0} y1={p1()?.y ?? 0} x2={p2()?.x ?? 0} y2={p2()?.y ?? 0} stroke-width="0.25" stroke-dasharray="0.5 4">
              <animate attributeName="stroke-dashoffset" values="0;8" dur={`${8 - isNear() * 5}s`} repeatCount="indefinite" />
          </line> );
        }}</For>
      </g>
    </svg>
  );
}
