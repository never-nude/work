import { useStore } from '../../state/store';
import { heatColor } from '../map/heatColors';
import { FACTOR_LABEL } from '../components/labels';
import { ScoreBar } from '../components/ScoreBar';
import type { EdgeFactorKey, FactorKey } from '../../types';

const BREAKDOWN: FactorKey[] = ['quiet', 'sidewalk', 'grass', 'terrain', 'crossings', 'crowds', 'shade'];
const label = (k: FactorKey) => (k === 'crossings' ? 'Safe crossings' : FACTOR_LABEL[k as EdgeFactorKey]);

const miles = (m: number) => (m / 1609.344).toFixed(m < 1609 ? 2 : 1);

export function RoutesPanel() {
  const routes = useStore((s) => s.routes);
  const idx = useStore((s) => s.routeIndex);
  const select = useStore((s) => s.selectRoute);
  const clear = useStore((s) => s.clearRoutes);
  const endMode = useStore((s) => s.endMode);
  const optimize = useStore((s) => s.optimize);
  const planning = useStore((s) => s.planning);

  return (
    <section className="routes" aria-label="Suggested routes">
      <header className="routes__head">
        <h2>{endMode === 'loop' ? 'Best loops' : 'Best ways there'}</h2>
        <button className="btn" onClick={clear}>
          Done
        </button>
      </header>
      <ol className="routes__list">
        {routes.map((r, i) => {
          const on = i === idx;
          return (
            <li key={r.id}>
              <button className={`route${on ? ' route--on' : ''}`} onClick={() => select(i)} aria-pressed={on}>
                <div className="route__top">
                  <span className="route__rank">{i + 1}</span>
                  <span className="route__score" style={{ color: heatColor(r.score / 100) }}>
                    {r.score}
                  </span>
                  <span className="route__meta">
                    {miles(r.lengthM)} mi · {Math.round(r.durationMin)} min
                  </span>
                </div>
                <p className="route__why">{r.why}</p>
                {r.warnings.length > 0 && (
                  <ul className="route__warn">
                    {r.warnings.map((w) => (
                      <li key={w.kind}>⚠ {w.message}</li>
                    ))}
                  </ul>
                )}
                {on && (
                  <ul className="route__bars">
                    {BREAKDOWN.filter((k) => r.breakdown[k] !== undefined).map((k) => (
                      <li key={k}>
                        <span>{label(k)}</span>
                        <ScoreBar value={r.breakdown[k]!} />
                        <span className="route__val">{Math.round(r.breakdown[k]! * 100)}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </button>
            </li>
          );
        })}
      </ol>
      <button className="btn" disabled={planning} onClick={() => void optimize()}>
        {planning ? 'Planning…' : 'Re-plan for this view'}
      </button>
    </section>
  );
}
