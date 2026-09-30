import type { Graph, LngLat, Maneuver, ManeuverKind } from '../types';
import type { Step } from './astar';

/** Compass-ish bearing in radians, x = east, y = north (local flat approximation). */
function heading(a: LngLat, b: LngLat): number {
  const k = Math.cos((a[1] * Math.PI) / 180);
  return Math.atan2(b[1] - a[1], (b[0] - a[0]) * k);
}

/** Signed turn in degrees: positive = left (counter-clockwise), negative = right. */
export function turnDegrees(inA: LngLat, via: LngLat, outB: LngLat): number {
  let d = ((heading(via, outB) - heading(inA, via)) * 180) / Math.PI;
  while (d > 180) d -= 360;
  while (d < -180) d += 360;
  return d;
}

export function kindFor(deg: number): ManeuverKind {
  const a = Math.abs(deg);
  if (a < 25) return 'straight';
  if (a > 160) return 'u-turn';
  const side = deg > 0 ? 'left' : 'right';
  if (a < 55) return `slight-${side}` as ManeuverKind;
  if (a > 125) return `sharp-${side}` as ManeuverKind;
  return side;
}

const VERB: Record<ManeuverKind, string> = {
  start: 'Head out',
  left: 'Turn left',
  right: 'Turn right',
  'slight-left': 'Bear left',
  'slight-right': 'Bear right',
  'sharp-left': 'Sharp left',
  'sharp-right': 'Sharp right',
  straight: 'Continue',
  'u-turn': 'Turn around',
  arrive: 'Arrive',
};

/**
 * Turn-by-turn from the route's edges: an instruction wherever the street
 * name changes or the walk turns noticeably (≥ 35°) between streets.
 * Consecutive edges of the same street merge into one "leg".
 */
export function buildManeuvers(graph: Graph, steps: Step[], isLoop: boolean): Maneuver[] {
  if (!steps.length) return [];
  const out: Maneuver[] = [];
  let along = 0;
  const pts = (st: Step) => {
    const c = graph.edges[st.edgeId]!.coords;
    return st.forward ? c : [...c].reverse();
  };
  const first = graph.edges[steps[0]!.edgeId]!;
  out.push({ kind: 'start', atM: 0, lngLat: pts(steps[0]!)[0]!, text: `Head out on ${first.name ?? 'the path'}` });

  for (let i = 0; i < steps.length; i++) {
    const e = graph.edges[steps[i]!.edgeId]!;
    along += e.lengthM;
    const next = steps[i + 1];
    if (!next) break;
    const n = graph.edges[next.edgeId]!;
    const a = pts(steps[i]!);
    const b = pts(next);
    const via = a[a.length - 1]!;
    const deg = turnDegrees(a[a.length - 2] ?? a[0]!, via, b[1] ?? b[0]!);
    const kind = kindFor(deg);
    const renamed = (n.name ?? '') !== (e.name ?? '');
    if (!renamed && Math.abs(deg) < 35) continue;
    if (renamed && kind === 'straight' && !n.name) continue;
    const onto = n.name ? ` onto ${n.name}` : '';
    out.push({ kind, atM: along, lngLat: via, text: kind === 'straight' ? `Continue${onto}` : `${VERB[kind]}${onto}` });
  }
  const last = pts(steps[steps.length - 1]!);
  out.push({ kind: 'arrive', atM: along, lngLat: last[last.length - 1]!, text: isLoop ? "You're back where you started" : "You've arrived" });
  return out;
}
