import { createSignal, onMount, onCleanup, For, createMemo } from "solid-js";

/**
 * HypercubeLogo - An ultra-high-fidelity, 4D Tesseract projection logo.
 * Features:
 * - 16-state non-linear transition matrix.
 * - Dual-layer hyper-dimensional wireframes.
 * - Dynamic edge lensing and data-pulse animation.
 * - SVG spectral glow and geometric precision.
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

// 16 Geometric "States" (Rotation angles in radians for 6 planes)
const STATES: [number, number, number, number, number, number][] = [
  [0, 0, 0, 0, 0, 0],                                      // 0: Identity
  [0.3, 0.2, 0.4, 0.1, 0.2, 0.1],                          // 1
  [0.8, 0.4, 0.9, 0.3, 0.5, 0.2],                          // 2
  [1.2, 0.8, 1.4, 0.6, 0.9, 0.4],                          // 3
  [Math.PI/2, Math.PI/4, Math.PI/2, 0.5, 1.2, 0.8],        // 4
  [2.1, 1.2, 2.5, 0.9, 1.8, 1.1],                          // 5
  [2.8, 1.8, 3.2, 1.4, 2.4, 1.6],                          // 6
  [Math.PI, 2.1, 3.8, 2.0, 3.0, 2.2],                      // 7: Deep Inversion
  [3.8, Math.PI, 4.5, 2.6, 3.8, 2.9],                      // 8
  [4.5, 3.8, 5.2, 3.2, 4.5, 3.6],                          // 9
  [5.2, 4.5, 6.0, 4.0, 5.2, 4.4],                          // 10
  [Math.PI*1.8, 5.2, 6.8, 4.8, 6.0, 5.2],                  // 11
  [Math.PI*2, Math.PI*2, Math.PI*2, 0, 0, 0],               // 12: Loop Point
  [0.5, 1.2, 2.4, 4.1, 0.8, 1.9],                          // 13: High Shear
  [1.8, 0.4, 3.2, 0.9, 5.1, 2.4],                          // 14: Complex Projection
  [Math.PI/3, Math.PI/3, Math.PI/3, Math.PI/3, Math.PI/3, Math.PI/3], // 15: Symmetrical
];

interface ProjectPoint {
  x: number;
  y: number;
  z: number;
  w: number;
}

interface HypercubeLogoProps {
  size?: number;
  class?: string;
  themeColor?: string;
  speed?: number; // Animation speed multiplier
}

export function HypercubeLogo(props: HypercubeLogoProps) {
  const [time, setTime] = createSignal(0);
  const [currentIdx, setCurrentIdx] = createSignal(0);
  const [targetIdx, setTargetIdx] = createSignal(1);
  const [transition, setTransition] = createSignal(0);
  
  let lastTime = 0;
  let frameReq: number;

  const animate = (timestamp: number) => {
    if (!lastTime) lastTime = timestamp;
    const deltaTime = (timestamp - lastTime) / 1000;
    lastTime = timestamp;

    const delta = props.speed ?? 1;
    setTime(t => t + deltaTime * delta);

    // Transition logic: move through states randomly but smoothly
    const nextTransition = transition() + (0.3 * deltaTime * delta);
    if (nextTransition >= 1) {
      setCurrentIdx(targetIdx());
      setTargetIdx(Math.floor(Math.random() * STATES.length));
      setTransition(0);
    } else {
      setTransition(nextTransition);
    }

    frameReq = requestAnimationFrame(animate);
  };

  onMount(() => {
    frameReq = requestAnimationFrame(animate);
  });

  onCleanup(() => {
    cancelAnimationFrame(frameReq);
  });

  const size = () => props.size ?? 24;

  // Projection Logic Wrapper
  const projectVertices = (scaleFactor: number, timeOffset: number, stateInterp: number) => {
    const startState = STATES[currentIdx()]!;
    const endState = STATES[targetIdx()]!;
    
    // Smoothstep for state transition
    const s = stateInterp * stateInterp * (3 - 2 * stateInterp);
    const angles = startState.map((a, i) => a + (endState[i]! - a) * s);

    return VERTICES.map(v => {
      let [x, y, z, w] = v;
      const [xy, xz, xw, yz, yw, zw] = angles as [number, number, number, number, number, number];

      const t = time() + timeOffset;
      
      // Add subtle micro-rotation for "floaty" feel
      const qxy = xy + Math.sin(t * 0.4) * 0.1;
      const qzw = zw + Math.cos(t * 0.3) * 0.1;

      // 4D Rotation in 6 planes
      let tx, ty, tz, tw;
      // XY
      tx = x * Math.cos(qxy) - y * Math.sin(qxy);
      ty = x * Math.sin(qxy) + y * Math.cos(qxy);
      [x, y] = [tx, ty];
      // XZ
      tx = x * Math.cos(xz) - z * Math.sin(xz);
      tz = x * Math.sin(xz) + z * Math.cos(xz);
      [x, z] = [tx, tz];
      // XW
      tx = x * Math.cos(xw) - w * Math.sin(xw);
      tw = x * Math.sin(xw) + w * Math.cos(xw);
      [x, w] = [tx, tw];
      // YZ
      ty = y * Math.cos(yz) - z * Math.sin(yz);
      tz = y * Math.sin(yz) + z * Math.cos(yz);
      [y, z] = [ty, tz];
      // YW
      ty = y * Math.cos(yw) - w * Math.sin(yw);
      tw = y * Math.sin(yw) + w * Math.cos(yw);
      [y, w] = [ty, tw];
      // ZW
      tz = z * Math.cos(qzw) - w * Math.sin(qzw);
      tw = z * Math.sin(qzw) + w * Math.cos(qzw);
      [z, w] = [tz, tw];

      // Perspective 4D -> 3D
      const distance4D = 2.4;
      const fov4D = 1 / (distance4D - w);
      x *= fov4D; y *= fov4D; z *= fov4D;

      // Perspective 3D -> 2D
      const distance3D = 3.2;
      const fov3D = 1 / (distance3D - z);
      x *= fov3D; y *= fov3D;

      const sVal = size();
      const scale = sVal * 1.5 * scaleFactor;
      return {
        x: (x * scale) + sVal / 2,
        y: (y * scale) + sVal / 2,
        z, w
      };
    });
  };

  const outerPoints = createMemo(() => projectVertices(1.0, 0, transition()));
  const innerPoints = createMemo(() => projectVertices(0.55, 10, transition()));

  return (
    <svg
      width={size()}
      height={size()}
      viewBox={`0 0 ${size()} ${size()}`}
      class={`hypercube-logo ${props.class ?? ""}`}
      xmlns="http://www.w3.org/2000/svg"
      shape-rendering="geometricPrecision"
      style={{ overflow: "visible" }}
    >
      <defs>
        <filter id="hyper-glow" x="-100%" y="-100%" width="300%" height="300%">
          <feGaussianBlur in="SourceGraphic" stdDeviation="0.6" result="blur" />
          <feColorMatrix in="blur" type="saturate" values="2" result="bright" />
          <feComposite in="SourceGraphic" in2="bright" operator="over" />
        </filter>
        <linearGradient id="edge-grad" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="currentColor" stop-opacity="0.2" />
          <stop offset="50%" stop-color="currentColor" stop-opacity="1" />
          <stop offset="100%" stop-color="currentColor" stop-opacity="0.2" />
        </linearGradient>
      </defs>
      
      {/* Outer Shell */}
      <g 
        fill="none" 
        stroke={props.themeColor ?? "currentColor"} 
        stroke-linecap="round" 
        stroke-linejoin="round"
        filter="url(#hyper-glow)"
      >
        <For each={EDGES}>
          {([i, j]) => {
            const p1 = () => outerPoints()[i];
            const p2 = () => outerPoints()[j];
            
            const depth = () => {
              const pt1 = p1(); const pt2 = p2();
              if (!pt1 || !pt2) return 0;
              return (pt1.z + pt2.z + pt1.w + pt2.w) / 4;
            };

            const opacity = () => 0.1 + (0.9 * (depth() + 2) / 4);
            const strokeWidth = () => 0.3 + (1.3 * opacity());

            return (
              <line
                x1={p1()?.x ?? 0} y1={p1()?.y ?? 0}
                x2={p2()?.x ?? 0} y2={p2()?.y ?? 0}
                stroke-opacity={opacity()}
                stroke-width={strokeWidth()}
                class="hyper-edge"
              />
            );
          }}
        </For>
      </g>

      {/* Inner Core (Spectral Layer) */}
      <g 
        fill="none" 
        stroke={props.themeColor ?? "currentColor"} 
        stroke-linecap="round" 
        stroke-linejoin="round"
        stroke-opacity="0.4"
      >
        <For each={EDGES}>
          {([i, j]) => {
            const p1 = () => innerPoints()[i];
            const p2 = () => innerPoints()[j];
            
            return (
              <line
                x1={p1()?.x ?? 0} y1={p1()?.y ?? 0}
                x2={p2()?.x ?? 0} y2={p2()?.y ?? 0}
                stroke-width="0.5"
                stroke-dasharray="1 3"
              >
                <animate 
                   attributeName="stroke-dashoffset" 
                   values="0;4" 
                   dur="2s" 
                   repeatCount="indefinite" 
                />
              </line>
            );
          }}
        </For>
      </g>
    </svg>
  );
}
