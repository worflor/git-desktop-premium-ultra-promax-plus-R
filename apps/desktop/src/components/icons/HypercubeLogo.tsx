import { createSignal, onMount, onCleanup, For, createMemo, batch } from "solid-js";

/**
 * HypercubeLogo - The Ultimate High-Fidelity 4D Brand Identity.
 * "Hard-Magnetic Breakaway" Edition:
 * - Mechanical Stiction: High-density magnetic capture (0.01x drag).
 * - Kinetic Threshold: Instant snap breakaway when pulled past the horizon.
 * - Reactive Tendrils: High-tension filaments connecting Home to Cube.
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

const STATES: number[][] = [
  [0, 0, 0, 0, 0, 0], [0.5, 0.8, 0.2, 1.2, 0.5, 0.1], [1.5, 0.3, 2.1, 0.1, 0.9, 0.6],
  [2.1, 1.5, 0.8, 3.1, 0.4, 1.2], [3.14, 2.1, 1.5, 0.8, 0.1, 3.14]
];

export function HypercubeLogo(props: { size?: number; class?: string; themeColor?: string; speed?: number; }) {
  const [time, setTime] = createSignal(0);
  const [currentIdx, setCurrentIdx] = createSignal(0);
  const [targetIdx, setTargetIdx] = createSignal(1);
  const [transition, setTransition] = createSignal(0);
  const [isNear, setIsNear] = createSignal(0);
  const [isDragging, setIsDragging] = createSignal(false);
  const [tilt, setTilt] = createSignal({ x: 0, y: 0 });
  const [warp, setWarp] = createSignal({ x: 0, y: 0, vx: 0, vy: 0 });
  
  let frameReq: number;
  let lastT = 0;
  let svgRef: SVGSVGElement | undefined;

  const size = () => props.size ?? 24;

  const animate = (timestamp: number) => {
    if (!lastT) lastT = timestamp;
    const dt = Math.min((timestamp - lastT) / 1000, 0.033);
    lastT = timestamp;

    batch(() => {
      const n = isNear();
      const d = isDragging();
      const boost = 1 + n * 1.5 + (d ? 3.5 : 0);
      const s = (props.speed ?? 0.85) * boost;

      setTime(t => t + dt * s);

      const nextT = transition() + (0.07 * dt * boost);
      if (nextT >= 1) {
        setCurrentIdx(targetIdx());
        setTargetIdx(Math.floor(Math.random() * STATES.length));
        setTransition(0);
      } else {
        setTransition(nextT);
      }

      if (!d) {
        const w = warp();
        const spring = 350; // Ultra snappy homing
        const damp = 0.75;
        const ax = -spring * w.x; const ay = -spring * w.y;
        const nVX = (w.vx + ax * dt) * damp; const nVY = (w.vy + ay * dt) * damp;
        setWarp({ x: w.x + nVX * dt, y: w.y + nVY * dt, vx: nVX, vy: nVY });
      }
    });

    frameReq = requestAnimationFrame(animate);
  };

  onMount(() => { frameReq = requestAnimationFrame(animate); });
  onCleanup(() => { cancelAnimationFrame(frameReq); });

  const getProjection = createMemo(() => {
    const tVal = time();
    const trans = transition();
    const tlt = tilt();
    const wrp = warp();
    const near = isNear();
    
    const start = STATES[currentIdx()]!;
    const end = STATES[targetIdx()]!;
    const interp = trans * trans * (3 - 2 * trans);
    const angles = start.map((a, i) => a + (end[i]! - a) * interp);
    const sVal = size();

    const solve = (tOff: number, fovOff: number, useWarp: boolean) => {
      const t = tVal + tOff;
      const scale = sVal * 1.55 * (1 + Math.sin(t * 0.4) * 0.05 * near);
      return VERTICES.map((v) => {
        let [x, y, z, w] = v;
        const [xy, xz, xw, yz, yw, zw] = angles.map((a, i) => {
          if (i === 0) return a + tlt.x * 0.5;
          if (i === 1) return a + tlt.y * 0.5;
          return a + (Math.sin(t * 0.1) * 0.05);
        });
        let tx, ty, tz, tw;
        tx = x*Math.cos(xy) - y*Math.sin(xy); ty = x*Math.sin(xy) + y*Math.cos(xy); [x, y] = [tx, ty];
        tx = x*Math.cos(xz) - z*Math.sin(xz); tz = x*Math.sin(xz) + z*Math.cos(xz); [x, z] = [tx, tz];
        tx = x*Math.cos(xw) - w*Math.sin(xw); tw = x*Math.sin(xw) + w * Math.cos(xw); [x, w] = [tx, tw];
        ty = y*Math.cos(yz) - z*Math.sin(yz); tz = y*Math.sin(yz) + z*Math.cos(yz); [y, z] = [ty, tz];
        ty = y*Math.cos(yw) - w*Math.sin(yw); tw = y*Math.sin(yw) + w*Math.cos(yw); [y, w] = [ty, tw];
        tz = z*Math.cos(zw) - w*Math.sin(zw); tw = z*Math.sin(zw) + w*Math.cos(zw); [z, w] = [tz, tw];
        const fov4D = 1 / (2.4 - (near * 0.3) + fovOff - w);
        x *= fov4D; y *= fov4D; z *= fov4D;
        const fov3D = 1 / (3.6 - z);
        x *= fov3D; y *= fov3D;
        return { x: (x * scale) + sVal/2 + (useWarp ? wrp.x : 0), y: (y * scale) + sVal/2 + (useWarp ? wrp.y : 0) };
      });
    };
    return { main: solve(0, 0, true), home: solve(-0.2, 0.04, false) };
  });

  const handlePointer = (e: PointerEvent) => {
    if (!svgRef) return;
    const rect = svgRef.getBoundingClientRect();
    const dx = e.clientX - rect.left - size()/2;
    const dy = e.clientY - rect.top - size()/2;
    const d = Math.sqrt(dx*dx + dy*dy);
    
    setTilt({ x: dx/size(), y: dy/size() });
    setIsNear(Math.max(0, 1 - d/(size()*3)));
    
    if (isDragging()) {
      // Hard Mechanical Magnetism
      const threshold = size() * 1.4; // Breakaway horizon
      let factor;
      if (d < threshold) {
        // High-density attraction logic
        factor = 0.02 + Math.pow(d / threshold, 4) * 0.3; // Hard stictional curves
      } else {
        // Sudden breakthrough snapping to cursor
        factor = 1.0; 
      }
      setWarp({ x: dx * factor, y: dy * factor, vx: 0, vy: 0 });
    }
  };

  return (
    <svg 
      ref={svgRef} width={size()} height={size()} viewBox={`0 0 ${size()} ${size()}`} 
      class={`hypercube-logo ${props.class ?? ""}`} 
      xmlns="http://www.w3.org/2000/svg" 
      shape-rendering="geometricPrecision" 
      style={{ overflow: "visible", cursor: isDragging() ? "grabbing" : "pointer", "touch-action": "none", "user-select": "none", "-webkit-user-select": "none" }}
      onPointerMove={handlePointer}
      onPointerDown={(e) => { e.preventDefault(); setIsDragging(true); svgRef?.setPointerCapture(e.pointerId); }}
      onPointerUp={(e) => { setIsDragging(false); svgRef?.releasePointerCapture(e.pointerId); }}
      onPointerLeave={() => { setIsNear(0); if (!isDragging()) setTilt({ x: 0, y: 0 }); }}
    >
      <rect width="100%" height="100%" fill="transparent" />
      <defs>
        <filter id="hyper-glow" x="-500%" y="-500%" width="1200%" height="1200%">
          <feGaussianBlur in="SourceGraphic" stdDeviation={0.6 + isNear() * 0.5} result="blur" />
          <feColorMatrix in="blur" type="saturate" values={1.8 + isNear() * 1.5} result="bright" />
          <feComposite in="SourceGraphic" in2="bright" operator="over" />
        </filter>
      </defs>

      {/* Origin Residuals */}
      <g stroke="#00ffff" stroke-width="0.32" opacity={isNear() * 0.35 + (isDragging() ? 0.3 : 0)}>
        <For each={EDGES}>{([i, j]) => {
          const m = getProjection();
          return ( <line x1={m.home[i]!.x} y1={m.home[i]!.y} x2={m.home[j]!.x} y2={m.home[j]!.y} /> );
        }}</For>
      </g>

      {/* Tendrils */}
      <g stroke={props.themeColor ?? "currentColor"} stroke-width="0.14" opacity={isDragging() ? 0.45 : 0} stroke-dasharray="0.5 4">
        <For each={getProjection().main}>{(p, i) => {
           const h = getProjection().home[i]!;
           return ( <line x1={p.x} y1={p.y} x2={h.x} y2={h.y} /> );
        }}</For>
      </g>

      {/* Main Struct */}
      <g fill="none" stroke={props.themeColor ?? "currentColor"} stroke-linecap="round" stroke-linejoin="round" filter="url(#hyper-glow)">
        <For each={EDGES}>{([i, j]) => {
          const m = getProjection();
          const depth = (m.main[i]!.z + m.main[j]!.z) / 2;
          const op = 0.25 + isNear() * 0.25;
          return ( <line x1={m.main[i]!.x} y1={m.main[i]!.y} x2={m.main[j]!.x} y2={m.main[j]!.y} stroke-opacity={op} stroke-width={0.45 + (op * 1.5) + (isDragging() ? 0.7 : 0)} /> );
        }}</For>
      </g>
    </svg>
  );
}
