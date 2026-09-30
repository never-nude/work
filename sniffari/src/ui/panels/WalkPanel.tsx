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
          <div className="finish-row">
            <span className="hint">{s.endPoint ? `Finish: ${s.endPoint.label}` : 'No finish chosen yet'}</span>
            <button className="btn" onClick={s.startPicking}>
              {s.endPoint ? 'Change' : 'Choose finish'}
            </button>
          </div>
        )}
      </div>
      <button className="btn btn--primary" disabled={s.planning} onClick={() => void s.optimize()}>
        {s.planning ? 'Planning…' : 'Optimize route in this view'}
      </button>
      <p className="hint">
        Starting from <strong>{s.startMode === 'gps' && s.source.kind === 'live' ? 'your location' : s.start.label}</strong>. Stays inside
        the purple circle — drag the map to move it, pinch to resize. Long-press or right-click to drop a pin.
      </p>
    </section>
  );
}
