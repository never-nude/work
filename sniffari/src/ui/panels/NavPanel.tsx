import { useStore } from '../../state/store';
import { nextManeuver } from '../../routing/progress';
import type { ManeuverKind } from '../../types';

const ARROW: Record<ManeuverKind, string> = {
  start: '↑', straight: '↑', left: '←', right: '→', 'slight-left': '↖', 'slight-right': '↗',
  'sharp-left': '↙', 'sharp-right': '↘', 'u-turn': '↶', arrive: '●',
};

/** US units: feet up to a tenth of a mile, then miles. */
const dist = (m: number) => {
  const ft = m * 3.28084;
  if (ft < 528) return `${Math.max(10, Math.round(ft / 10) * 10)} ft`;
  return `${(m / 1609.344).toFixed(1)} mi`;
};

/** In-app turn-by-turn for the selected route. */
export function NavPanel() {
  const nav = useStore((s) => s.nav);
  const route = useStore((s) => s.routes[s.routeIndex]);
  const pace = useStore((s) => s.routes[s.routeIndex] ? s.routes[s.routeIndex]!.lengthM / s.routes[s.routeIndex]!.durationMin : 60);
  const me = useStore((s) => s.me);
  const stopNav = useStore((s) => s.stopNav);
  const flyTo = useStore((s) => s.flyTo);
  if (!nav || !route) return null;

  const next = nextManeuver(route.maneuvers, nav.alongM);
  const left = Math.max(0, route.lengthM - nav.alongM);
  const off = me && nav.offM > 35;

  return (
    <>
      <section className="nav-card" aria-live="polite">
        {nav.arrived ? (
          <div className="nav-card__main">
            <span className="nav-card__arrow">●</span>
            <div>
              <p className="nav-card__text">{route.maneuvers.at(-1)?.text ?? "You've arrived"}</p>
              <p className="hint">Good walk. {dist(route.lengthM)} total.</p>
            </div>
          </div>
        ) : !me ? (
          <div className="nav-card__main">
            <span className="nav-card__arrow">…</span>
            <p className="nav-card__text">Waiting for GPS…</p>
          </div>
        ) : next ? (
          <div className="nav-card__main">
            <span className="nav-card__arrow">{ARROW[next.m.kind]}</span>
            <div>
              <p className="nav-card__dist">{next.inM < 10 ? 'Now' : `In ${dist(next.inM)}`}</p>
              <p className="nav-card__text">{next.m.text}</p>
            </div>
          </div>
        ) : null}
        {off && !nav.arrived && <p className="nav-card__off">Off route by {dist(nav.offM)} — head back to the purple line</p>}
      </section>
      <section className="nav-bar">
        <div className="nav-bar__stats">
          <span>
            <strong>{dist(left)}</strong> left
          </span>
          <span>
            <strong>{Math.max(0, Math.round(left / pace))} min</strong>
          </span>
        </div>
        <button className="btn" onClick={() => me && flyTo?.(me, 17.5)} disabled={!me}>
          Recenter
        </button>
        <button className="btn btn--primary nav-bar__end" onClick={stopNav}>
          {nav.arrived ? 'Done' : 'End'}
        </button>
      </section>
    </>
  );
}
