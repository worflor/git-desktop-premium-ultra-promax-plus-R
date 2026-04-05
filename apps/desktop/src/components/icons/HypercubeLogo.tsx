import { createSignal, onMount, onCleanup, For, createMemo, batch } from "solid-js";

/**
 * hypercube-kinetic.ts — The Tesseract Signature
 * 
 * 4D manifold rendering via raw Givens rotations.
 * SolidJS signals + snapper-damped Euler integration.
 * 
 * Part of the 'logos' engine — the seed of the 4D workspace.
 */

// 1/-1 unit cell for the 16-vertex hypercube.
const VERTICES: [number, number, number, number][] = Array.from({ length: 16 }, (_, i) => [
  ((i & 1) << 1) - 1, ((i & 2)) - 1, ((i & 4) >> 1) - 1, ((i & 8) >> 2) - 1
]);

const EDGES: [number, number][] = [];
for (let i = 0; i < 16; i++) {
  for (let j = i + 1; j < 16; j++) {
    const diff = i ^ j;
    // Hamming distance = 1.
    if (diff && (diff & (diff - 1)) === 0) EDGES.push([i, j]);
  }
}

const STATES: number[][] = [
  [0.35, 0.35, 0.1, 0.35, 0.1, 0.1], [0.5, 0.8, 0.2, 1.2, 0.5, 0.1], [1.5, 0.3, 2.1, 0.1, 0.9, 0.6],
  [2.1, 1.5, 0.8, 3.1, 0.4, 1.2], [3.14, 2.1, 1.5, 0.8, 0.1, 3.14],
  [0.8, 1.6, 3.2, 0.4, 4.0, 1.2],
  [1.57, 0, 1.57, 0, 1.57, 0],
  [0, 0.785, 0, 0, 0.785, 0],
  [0.4, 0.2, 3.142, 3.142, 0.2, 0.4],
  [0.1, 0.1, 2.356, 0.1, 2.356, 2.356],
  [0, 0.4, 3.142, 0, 3.142, 0],
  [0.785, 0, 0, 0, 0, 0.785],
  [0, 0, 1.57, 0, 1.57, 0]
];

// 6-plane Givens chain.
const rotate4D = (coords: number[], rot: { c: number; s: number }[]) => {
  let [x, y, z, w] = coords;
  const [rXY, rXZ, rXW, rYZ, rYW, rZW] = rot;
  let tx, ty, tz, tw;
  tx = x! * rXY!.c - y! * rXY!.s; ty = x! * rXY!.s + y! * rXY!.c; [x, y] = [tx, ty];
  tx = x! * rXZ!.c - z! * rXZ!.s; tz = x! * rXZ!.s + z! * rXZ!.c; [x, z] = [tx, tz];
  tx = x! * rXW!.c - w! * rXW!.s; tw = x! * rXW!.s + w! * rXW!.c; [x, w] = [tx, tw];
  ty = y! * rYZ!.c - z! * rYZ!.s; tz = y! * rYZ!.s + z! * rYZ!.c; [y, z] = [ty, tz];
  ty = y! * rYW!.c - w! * rYW!.s; tw = y! * rYW!.s + w! * rYW!.c; [y, w] = [ty, tw];
  tz = z! * rZW!.c - w! * rZW!.s; tw = z! * rZW!.s + w! * rZW!.c; [z, w] = [tz, tw];
  return [x, y, z, w];
};

const getVerticesForState = (state: number[]) => {
  const rot = state.map(a => ({ c: Math.cos(a), s: Math.sin(a) }));
  return VERTICES.map(v => rotate4D(v, rot));
};

// Pre-rotated vertex cache.
const STATE_VERTICES = STATES.map(getVerticesForState);

export function HypercubeLogo(props: { size?: number; class?: string; themeColor?: string; speed?: number; }) {
  const [time, setTime] = createSignal(0);
  const [smoothBoost, setSmoothBoost] = createSignal(1);
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
  const history: number[] = [0, 1];

  let rngState = BigInt(Date.now());
  const xorshift64 = () => {
    rngState ^= (rngState << 13n) & 0xFFFFFFFFFFFFFFFFn;
    rngState ^= (rngState >> 7n);
    rngState ^= (rngState << 17n) & 0xFFFFFFFFFFFFFFFFn;
    return Number(rngState & 0xFFFFFFFFn) / 0xFFFFFFFF;
  };

  const pickNextIdx = () => {
    const sIdx = targetIdx();
    const currentVerts = STATE_VERTICES[sIdx]!;
    const distData = STATE_VERTICES.map((otherVerts, i) => {
      if (i === sIdx) return { id: i, d: 0 };
      // Kahan summation for manifold stability.
      const totalDist = currentVerts.reduce((acc, v1, j) => {
        const v2 = otherVerts[j]!;
        const dx = v1[0]! - v2[0]!, dy = v1[1]! - v2[1]!, dz = v1[2]! - v2[2]!, dw = v1[3]! - v2[3]!;
        const y = Math.sqrt(dx*dx + dy*dy + dz*dz + dw*dw) - acc.c;
        const t = acc.s + y;
        acc.c = (t - acc.s) - y;
        acc.s = t;
        return acc;
      }, { s: 0, c: 0 }).s;
      return { id: i, d: totalDist };
    });

    const tooClose = distData
      .filter(x => x.id !== sIdx)
      .sort((a, b) => a.d - b.d)
      .slice(0, 2)
      .map(x => x.id);

    const available = Array.from({ length: STATES.length }, (_, i) => i)
      .filter(i => !history.includes(i) && !tooClose.includes(i) && i !== sIdx);

    const rand = xorshift64();
    const next = available[Math.floor(rand * available.length)] ?? (sIdx + 2) % STATES.length;
    
    history.push(next);
    if (history.length > 4) history.shift();
    return next;
  };

  const animate = (timestamp: number) => {
    if (!lastT) lastT = timestamp;
    const dt = Math.min((timestamp - lastT) / 1000, 0.033);
    lastT = timestamp;

    batch(() => {
      const nearVal = isNear();
      const dragVal = isDragging();
      const targetB = 1 + nearVal * 1.2 + (dragVal ? 2.3 : 0);
      
      setSmoothBoost(sb => sb + (targetB - sb) * dt * 12);
      const currentB = smoothBoost();
      setTime(t => t + dt * (props.speed ?? 0.85) * currentB);

      const startS = STATES[currentIdx()] || STATES[0];
      const endS = STATES[targetIdx()] || STATES[1];
      const dist = Math.sqrt(startS!.reduce((s, v, i) => {
        const d = v - endS![i]!;
        return s + d * d;
      }, 0));
      const distMult = 0.9 + Math.min(dist * 0.1, 0.1);

      const nextT = transition() + (0.095 * dt * currentB * distMult);
      if (nextT >= 1) {
        setCurrentIdx(targetIdx());
        setTargetIdx(pickNextIdx());
        setTransition(0);
      } else {
        setTransition(nextT);
      }

      if (!dragVal) {
        const w = warp();
        const spring = 800;
        const damp = 0.7; // original snappiness
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

    const t = trans;
    const interp = t * t * (3 - 2 * t);
    const angles = start!.map((a, i) => a + (end![i]! - a) * interp);

    const solve = (tOff: number, fovOff: number, useWarp: boolean) => {
      const scale = sVal * 1.55 * (1 + Math.sin((tVal + tOff) * 0.4) * 0.05 * near);
      const rot = angles.map((a, i) => {
        let ang = a;
        if (i === 0) ang += tlt.x * 0.5 + (useWarp ? wrp.x / sVal * 0.8 : 0);
        if (i === 1) ang += tlt.y * 0.5 + (useWarp ? wrp.y / sVal * 0.8 : 0);
        if (i > 1) ang += Math.sin((tVal + tOff) * 0.1) * 0.05 + (useWarp ? (wrp.x + wrp.y) / sVal * 0.2 : 0);
        return { c: Math.cos(ang), s: Math.sin(ang) };
      });

      return VERTICES.map((v) => {
        const [x, y, z, w] = rotate4D(v, rot);
        const fov4D = 1 / Math.max(0.01, 2.4 - (near * 0.3) + fovOff - w!);
        const fov3D = 1 / Math.max(0.01, 3.6 - z!);
        const combinedFov = fov4D * fov3D;
        const sx = x! * combinedFov, sy = y! * combinedFov;
        const meldStrength = useWarp ? (near * 0.45) : 0;
        let px = (sx * scale) + sVal / 2 + (useWarp ? wrp.x : 0);
        let py = (sy * scale) + sVal / 2 + (useWarp ? wrp.y : 0);
        if (useWarp && near > 0.5) {
          px += (wrp.x * meldStrength);
          py += (wrp.y * meldStrength);
        }
        return { x: px, y: py, z, w };
      });
    };

    return { 
      main: solve(0, 0, true), 
      home: solve(-0.2, 0.04, false),
      ghost: solve(-0.4, 0.08, false) 
    };
  });

  const handlePointer = (e: PointerEvent) => {
    if (!svgRef) return;
    const rect = svgRef.getBoundingClientRect();
    const midX = rect.left + rect.width / 2;
    const midY = rect.top + rect.height / 2;
    const dx = e.clientX - midX;
    const dy = e.clientY - midY;
    const d = Math.sqrt(dx * dx + dy * dy);

    batch(() => {
      setTilt({ x: dx / size(), y: dy / size() });
      const near = Math.max(0, 1 - d / (size() * 3));
      setIsNear(near);

      if (isDragging()) {
        setWarp({ x: dx, y: dy, vx: 0, vy: 0 });
        const root = document.documentElement;
        root.setAttribute("data-hyper-active", "true");
        root.style.setProperty("--hyper-drag-x", `${e.clientX}px`);
        root.style.setProperty("--hyper-drag-y", `${e.clientY}px`);
        root.style.setProperty("--hyper-drag-intensity", (near + 1).toFixed(2));
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

  return (
    <svg
      ref={svgRef!} width={size()} height={size()} viewBox={`0 0 ${size()} ${size()}`}
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
        if (!isDragging()) setTilt({ x: 0, y: 0 });
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

      <g stroke="var(--hyper-chromatic-2)" stroke-width="0.32" opacity={isNear() * 0.35 + (isDragging() ? 0.3 : 0)}>
        <For each={EDGES}>{([i, j]) => {
          const ghost = () => projectedData().home;
          return <line x1={ghost()[i]?.x ?? 0} y1={ghost()[i]?.y ?? 0} x2={ghost()[j]?.x ?? 0} y2={ghost()[j]?.y ?? 0} />
        }}</For>
      </g>

      <g stroke="var(--hyper-chromatic-1)" stroke-width="0.12" opacity={isDragging() ? 0.45 : 0} stroke-dasharray="0.4 3">
        <For each={projectedData().main}>{(p, i) => (
          <line x1={p.x} y1={p.y} x2={projectedData().home[i()]?.x ?? 0} y2={projectedData().home[i()]?.y ?? 0} />
        )}</For>
      </g>

      <g fill="none" stroke="var(--hyper-core-color, #fff)" stroke-linecap="round" stroke-linejoin="round" filter="url(#chromatic-aberration) url(#hyper-glow)">
        <For each={EDGES}>{([i, j]) => {
          const p1 = () => projectedData().main[i]!;
          const p2 = () => projectedData().main[j]!;
          const torsion = () => Math.abs(p1().w! - p2().w!) + Math.abs(p1().z! - p2().z!) * 0.5;
          const stress = () => Math.min(1.5, torsion() * (1.2 + isNear() * 0.8));
          const depth = () => ((p1().z! + p2().z!) * 0.5 + (p1().w! + p2().w!) * 0.5);
          const op = () => Math.max(0.05, 0.25 + isNear() * 0.25 + (depth() * 0.08));
          const dash = () => stress() > 1.1 ? "0.2 1.8" : "none";

          return (
            <line
              x1={p1().x} y1={p1().y}
              x2={p2().x} y2={p2().y}
              stroke-opacity={op() + (stress() * 0.15)}
              stroke-width={0.45 + (op() * 1.5) + (isDragging() ? 0.8 : 0) + (stress() * 0.4)}
              stroke-dasharray={dash()}
            />
          );
        }}</For>
      </g>

      <g stroke="var(--hyper-chromatic-2)" stroke-width="0.1" opacity={isNear() * 0.15} stroke-dasharray="1 5">
        <For each={EDGES}>{([i, j]) => {
          const p1 = () => projectedData().ghost[i]!;
          const p2 = () => projectedData().ghost[j]!;
          return <line x1={p1().x} y1={p1().y} x2={p2().x} y2={p2().y} />
        }}</For>
      </g>
    </svg>
  );
}
