import { useStore } from '../../state/store';
import { heatColor } from '../map/heatColors';
import { FACTOR_LABEL } from '../components/labels';
import { ScoreBar } from '../components/ScoreBar';
import type { EdgeFactorKey, FactorKey } from '../../types';
import { appleMapsUrl, googleMapsUrl } from '../../routing/export';
import { useSocial, type ShareMode } from '../../social/store';

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
  const startNav = useStore((s) => s.startNav);
  const social = useSocial();

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
      {routes[idx] && (
        <div className="export">
          {social.signedIn && social.dog && (
            <div className="field">
              <span className="field__label">Share this walk live</span>
              <div className="segmented segmented--3" role="radiogroup">
                {(['off', 'friends', 'fof'] as ShareMode[]).map((m) => (
                  <button key={m} role="radio" aria-checked={social.shareMode === m} className={social.shareMode === m ? 'on' : ''} onClick={() => social.setShareMode(m)}>
                    {m === 'off' ? 'Private' : m === 'friends' ? 'Pack' : 'Pack + their friends'}
                  </button>
                ))}
              </div>
              {social.shareMode !== 'off' && (
                <p className="hint">
                  They'll get “🐕 {social.dog.dog_name} is walking”. Your start and finish stay hidden; sharing ends when you finish.
                </p>
              )}
            </div>
          )}
          <button className="btn btn--primary" onClick={startNav}>
            ▶ Start walk (navigate in Sniffari)
          </button>
          <span className="field__label">Or open route {idx + 1} in</span>
          <div className="export__row">
            <a className="btn btn--export" href={googleMapsUrl(routes[idx]!)} target="_blank" rel="noreferrer">
              Google Maps
            </a>
            {endMode === 'elsewhere' && (
              <a className="btn btn--export" href={appleMapsUrl(routes[idx]!)} target="_blank" rel="noreferrer">
                Apple Maps
              </a>
            )}
          </div>
          <p className="hint">
            {endMode === 'elsewhere'
              ? 'Google follows this route via stops at its turns. Apple Maps only gets directions to the finish and picks its own streets.'
              : "Google follows this loop via stops at its turns (close, not exact). Apple Maps can't open loops."}
          </p>
        </div>
      )}
      <button className="btn" disabled={planning} onClick={() => void optimize()}>
        {planning ? 'Planning…' : 'Re-plan for this view'}
      </button>
    </section>
  );
}
