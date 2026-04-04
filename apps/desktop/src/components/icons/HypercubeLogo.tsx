import { createSignal, onMount, onCleanup, For, createMemo, batch } from "solid-js";

/**
 * HypercubeLogo - The Ultimate High-Fidelity 4D Brand Identity.
 * "Locked Scale" Edition:
 * - Restored Scale (1.55): Re-anchored to the user-preferred large-format projection.
 * - Resolved Accessor-as-index TypeErrors by calling index signals i().
 * - Static Size Preservation: Scale is now locked at 1.55x.
 * - Precise Tendrils & 1:1 Physics.
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
      const nearVal = isNear();
      const dragVal = isDragging();
      const boost = 1 + nearVal * 1.5 + (dragVal ? 3.5 : 0);
      setTime(t => t + dt * (props.speed ?? 0.85) * boost);

      const nextT = transition() + (0.07 * dt * boost);
      if (nextT >= 1) {
        setCurrentIdx(targetIdx());
        setTargetIdx(Math.floor(Math.random() * STATES.length));
        setTransition(0);
      } else {
        setTransition(nextT);
      }

      if (!dragVal) {
        const w = warp();
        const spring = 800; 
        const damp = 0.7;
        const ax = -spring * w.x; const ay = -spring * w.y;
        const nVX = (w.vx + ax * dt) * damp; const nVY = (w.vy + ay * dt) * damp;
        setWarp({ x: w.x + nVX * dt, y: w.y + nVY * dt, vx: nVX, vy: nVY });
      }
    });

    frameReq = requestAnimationFrame(animate);
  };

  onMount(() => { frameReq = requestAnimationFrame(animate); });
  onCleanup(() => {
    cancelAnimationFrame(frameReq);
    const root = document.documentElement;
    root.setAttribute("data-hyper-active", "false");
    root.style.setProperty("--hyper-drag-intensity", "0");
  });

  const projectedData = createMemo(() => {
    const tVal = time();
    const trans = transition();
    const tlt = tilt();
    const wrp = warp();
    const near = isNear();
    const sVal = size();
    const start = STATES[currentIdx()] || STATES[0];
    const end = STATES[targetIdx()] || STATES[1];
    const interp = trans * trans * (3 - 2 * trans);
    const angles = start!.map((a, i) => a + (end![i]! - a) * interp);

    const solve = (tOff: number, fovOff: number, useWarp: boolean) => {
      const t = tVal + tOff;
      const breath = 1 + Math.sin(t * 0.4) * 0.05 * near;
      const scale = sVal * 1.55 * breath; // RESTORED USER SCALE: 1.55
      const rot = angles.map((a, i) => {
        let ang = a;
        if (i === 0) ang += tlt.x * 0.5 + (useWarp ? wrp.x / sVal * 0.8 : 0);
        if (i === 1) ang += tlt.y * 0.5 + (useWarp ? wrp.y / sVal * 0.8 : 0);
        if (i > 1) ang += Math.sin(t * 0.1) * 0.05 + (useWarp ? (wrp.x + wrp.y) / sVal * 0.2 : 0);
        return { c: Math.cos(ang), s: Math.sin(ang) };
      });

      return VERTICES.map((v) => {
        let [x, y, z, w] = v;
        const [rXY, rXZ, rXW, rYZ, rYW, rZW] = rot;
        let tx, ty, tz, tw;
        tx = x*rXY!.c - y*rXY!.s; ty = x*rXY!.s + y*rXY!.c; [x, y] = [tx, ty];
        tx = x*rXZ!.c - z*rXZ!.s; tz = x*rXZ!.s + z*rXZ!.c; [x, z] = [tx, tz];
        tx = x*rXW!.c - w*rXW!.s; tw = x*rXW!.s + w*rXW!.c; [x, w] = [tx, tw];
        ty = y*rYZ!.c - z*rYZ!.s; tz = y*rYZ!.s + z*rYZ!.c; [y, z] = [ty, tz];
        ty = y*rYW!.c - w*rYW!.s; tw = y*rYW!.s + w*rYW!.c; [y, w] = [ty, tw];
        tz = z*rZW!.c - w*rZW!.s; tw = z*rZW!.s + w*rZW!.c; [z, w] = [tz, tw];
        const fov4D = 1 / (2.4 - (near * 0.3) + fovOff - w);
        x *= fov4D; y *= fov4D; z *= fov4D;
        const fov3D = 1 / (3.6 - z);
        x *= fov3D; y *= fov3D;

        // GEOMETRIC MELD: Vertices reach out to warp center
        const meldStrength = useWarp ? (near * 0.45) : 0;
        let px = (x * scale) + sVal/2 + (useWarp ? wrp.x : 0);
        let py = (y * scale) + sVal/2 + (useWarp ? wrp.y : 0);
        
        if (useWarp && near > 0.5) {
           px += (wrp.x * meldStrength);
           py += (wrp.y * meldStrength);
        }

        return { x: px, y: py, z, w };
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
    batch(() => {
      setTilt({ x: dx/size(), y: dy/size() });
      const near = Math.max(0, 1 - d/(size()*3));
      setIsNear(near);

      if (isDragging()) {
        const threshold = size() * 2.2; 
        const sigmaFactor = size() * 0.3;
        const sigma = 1 / (1 + Math.exp(-(d - threshold) / sigmaFactor)); 
        const f = 0.01 + sigma * 0.99;
        setWarp({ x: dx * f, y: dy * f, vx: 0, vy: 0 });

        // Global Broadcast for Hyper-Interaction
        const root = document.documentElement;
        root.setAttribute("data-hyper-active", "true");
        root.style.setProperty("--hyper-drag-x", `${e.clientX}px`);
        root.style.setProperty("--hyper-drag-y", `${e.clientY}px`);
        root.style.setProperty("--hyper-drag-intensity", (near + (d > threshold ? 1 : 0)).toFixed(2));
      }
    });
  };

  const handleRelease = (e: PointerEvent) => {
    setIsDragging(false);
    svgRef?.releasePointerCapture(e.pointerId);

    const root = document.documentElement;
    root.setAttribute("data-hyper-active", "false");
    root.style.setProperty("--hyper-drag-intensity", "0");
  };

  const mainP = () => projectedData().main;
  const homeP = () => projectedData().home;

  return (
    <svg 
      ref={svgRef} width={size()} height={size()} viewBox={`0 0 ${size()} ${size()}`} 
      class={`hypercube-logo ${props.class ?? ""}`} 
      xmlns="http://www.w3.org/2000/svg" 
      shape-rendering="geometricPrecision" 
      style={{ overflow: "visible", cursor: isDragging() ? "grabbing" : "pointer", "touch-action": "none", "user-select": "none", "-webkit-user-select": "none" }}
      onPointerMove={handlePointer}
      onPointerDown={(e) => {
        e.preventDefault();
        setIsDragging(true);
        document.documentElement.setAttribute("data-hyper-active", "true");
        svgRef?.setPointerCapture(e.pointerId);
      }}
      onPointerUp={handleRelease}
      onPointerCancel={handleRelease}
      onPointerLeave={() => { 
        setIsNear(0); 
        if (!isDragging()) {
          setTilt({ x: 0, y: 0 });
          const root = document.documentElement;
          root.style.setProperty("--hyper-drag-intensity", "0");
          root.setAttribute("data-hyper-active", "false");
        }
      }}
    >
      <rect width="100%" height="100%" fill="transparent" />
      <defs>
        <filter id="hyper-glow" x="-500%" y="-500%" width="1200%" height="1200%">
          <feGaussianBlur in="SourceGraphic" stdDeviation={0.6 + isNear() * 0.5} result="blur" />
          <feColorMatrix in="blur" type="saturate" values={`${1.8 + isNear() * 1.5}`} result="bright" />
          <feComposite in="SourceGraphic" in2="bright" operator="over" />
        </filter>
        <filter id="chromatic-aberration" x="-100%" y="-100%" width="300%" height="300%">
          <feOffset in="SourceGraphic" dx="-0.4" dy="0" result="offset1" />
          <feFlood flood-color="var(--hyper-chromatic-1)" result="color1" />
          <feComposite in="color1" in2="offset1" operator="in" result="spectral1" />
          
          <feOffset in="SourceGraphic" dx="0.4" dy="0" result="offset2" />
          <feFlood flood-color="var(--hyper-chromatic-2)" result="color2" />
          <feComposite in="color2" in2="offset2" operator="in" result="spectral2" />
          
          <feMerge>
            <feMergeNode in="spectral1" />
            <feMergeNode in="spectral2" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>

      {/* Residual Anchor: Themed 'Ghost' Origin (Optimized for Visibility) */}
      <g stroke="var(--hyper-chromatic-2)" stroke-width="0.32" opacity={isNear() * 0.35 + (isDragging() ? 0.3 : 0)}>
        <For each={EDGES}>{([i, j]) => (
           <line x1={homeP()[i]?.x ?? 0} y1={homeP()[i]?.y ?? 0} x2={homeP()[j]?.x ?? 0} y2={homeP()[j]?.y ?? 0} /> 
        )}</For>
      </g>

      {/* Tendrils: Theme Spectral Filament */}
      <g stroke="var(--hyper-chromatic-1)" stroke-width="0.12" opacity={isDragging() ? 0.45 : 0} stroke-dasharray="0.4 3">
        <For each={mainP()}>{(p, i) => (
           <line x1={p.x} y1={p.y} x2={homeP()[i()]?.x ?? 0} y2={homeP()[i()]?.y ?? 0} /> 
        )}</For>
      </g>

      {/* Main Body: Dynamic Core for Universal Readability */}
      <g fill="none" stroke="var(--hyper-core-color, #fff)" stroke-linecap="round" stroke-linejoin="round" filter="url(#chromatic-aberration) url(#hyper-glow)">
        <For each={EDGES}>{([i, j]) => {
          const depth = () => ((mainP()[i]?.z ?? 0) + (mainP()[j]?.z ?? 0)) / 2;
          const op = () => 0.25 + isNear() * 0.25 + (depth() * 0.1); 
          return ( 
            <line 
              x1={mainP()[i]?.x ?? 0} y1={mainP()[i]?.y ?? 0} 
              x2={mainP()[j]?.x ?? 0} y2={mainP()[j]?.y ?? 0} 
              stroke-opacity={op()} stroke-width={0.45 + (op() * 1.5) + (isDragging() ? 0.8 : 0)} 
            /> 
          );
        }}</For>
      </g>
    </svg>
  );
}
