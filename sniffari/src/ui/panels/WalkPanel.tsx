import { PACES, WALK_MINUTES, useStore, type PaceId } from '../../state/store';

/** Walk length, pace and where to finish — the inputs to "Optimize route". */
export function WalkPanel() {
  const s = useStore();
  return (
    <section className="walk" aria-label="Plan a walk">
      <div className="field">
        <span className="field__label">Walk</span>
        <div className="chips">
          {WALK_MINUTES.map((m) => (
            <button key={m} className={`chip${s.minutes === m ? ' chip--on' : ''}`} onClick={() => s.setMinutes(m)}>
              {m} min
            </button>
          ))}
        </div>
        <div className="chips">
          {(Object.keys(PACES) as PaceId[]).map((p) => (
            <button key={p} className={`chip${s.pace === p ? ' chip--on' : ''}`} onClick={() => s.setPace(p)}>
              {PACES[p].label}
            </button>
          ))}
        </div>
      </div>
      <div className="field">
        <span className="field__label">Finish</span>
        <div className="segmented" role="radiogroup">
          <button role="radio" aria-checked={s.endMode === 'loop'} className={s.endMode === 'loop' ? 'on' : ''} onClick={() => s.setEndMode('loop')}>
            Back to start
          </button>
          <button role="radio" aria-checked={s.endMode === 'elsewhere'} className={s.endMode === 'elsewhere' ? 'on' : ''} onClick={() => s.setEndMode('elsewhere')}>
            Somewhere else
          </button>
        </div>
        {s.endMode === 'elsewhere' && (
          <p className="hint">{s.endPoint ? 'End point set — tap Optimize to re-plan, or tap the map again to move it.' : "You'll tap the map to choose where to finish."}</p>
        )}
      </div>
      <button className="btn btn--primary" disabled={s.planning} onClick={() => void s.optimize()}>
        {s.planning ? 'Planning…' : 'Optimize route in this view'}
      </button>
      <p className="hint">Starts from your location and stays inside what's on screen — zoom the map to the area you want to walk.</p>
    </section>
  );
}
