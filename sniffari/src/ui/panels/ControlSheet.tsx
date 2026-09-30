import { PROFILE_ORDER, PROFILES } from '../../scoring/profiles';
import { FIXTURES } from '../../state/fixtures';
import { TIME_PRESETS, useStore, type TimePreset } from '../../state/store';
import { Legend } from '../components/Legend';
import { RoutesPanel } from './RoutesPanel';
import { WalkPanel } from './WalkPanel';

export function ControlSheet() {
  const s = useStore();
  const sourceValue = s.source.kind === 'live' ? 'live' : `fixture:${s.source.name}`;

  const dog = (
    <div className="field">
      <span className="field__label">Dog</span>
      <div className="chips">
        {PROFILE_ORDER.map((id) => (
          <button key={id} className={`chip${s.profileId === id ? ' chip--on' : ''}`} onClick={() => s.setProfile(id)}>
            {PROFILES[id].name}
          </button>
        ))}
      </div>
      <p className="hint">{PROFILES[s.profileId].blurb}</p>
      <div className="chips">
        <button className={`chip${s.dogParks ? ' chip--on' : ''}`} aria-pressed={s.dogParks} onClick={() => s.setDogParks(!s.dogParks)}>
          {s.dogParks ? '✓ ' : ''}Count dog parks as green
        </button>
      </div>
    </div>
  );

  const when = (
    <div className="field">
      <span className="field__label">When</span>
      <div className="chips">
        {(Object.keys(TIME_PRESETS) as TimePreset[]).map((t) => (
          <button key={t} className={`chip${s.timePreset === t ? ' chip--on' : ''}`} onClick={() => s.setTime(t)}>
            {TIME_PRESETS[t].label}
          </button>
        ))}
      </div>
    </div>
  );

  const progress = s.progress && (
    <div className="progress" aria-live="polite">
      <div className="progress__track">
        <div className="progress__fill" style={{ width: `${s.progress.total ? Math.round((s.progress.done / s.progress.total) * 100) : 0}%` }} />
      </div>
      <span className="hint">{s.progress.message}</span>
    </div>
  );

  return (
    <div className="sheet__body">
      {s.routes.length > 0 ? <RoutesPanel /> : <WalkPanel />}
      {progress}
      {s.planMessage && <p className="hint hint--notice">{s.planMessage}</p>}
      {s.error && <p className="hint hint--error">{s.error}</p>}
      {dog}
      {when}

      <details className="more">
        <summary>Street-quality map legend &amp; data</summary>
        <div className="sheet__body more__body">
          <p className="hint">
            Street scores load automatically for the area on screen.{' '}
            {s.status === 'loading' ? 'Loading…' : s.heatmap ? `Showing ${s.heatmap.stats.edges.toLocaleString()} street segments.` : ''}
          </p>
          <Legend />
          {s.heatmap && (
            <dl className="stats">
              <div><dt>Streets</dt><dd>{s.heatmap.stats.edges.toLocaleString()}</dd></div>
              <div><dt>Walkable</dt><dd>{s.heatmap.stats.walkableKm.toFixed(1)} km</dd></div>
              <div><dt>Avg quality</dt><dd>{Math.round(s.heatmap.stats.meanQ * 100)}</dd></div>
              <div><dt>Excluded</dt><dd>{s.heatmap.stats.excludedEdges}</dd></div>
              <div><dt>Busy crossings</dt><dd>{s.heatmap.stats.crossings}</dd></div>
              <div><dt>Elevation</dt><dd>{s.heatmap.stats.elevationTiles ? 'on' : 'off'}</dd></div>
            </dl>
          )}
          <div className="field">
            <label className="field__label" htmlFor="source">Data (dev)</label>
            <select
              id="source"
              className="input"
              value={sourceValue}
              onChange={(e) => {
                const v = e.target.value;
                s.setSource(v === 'live' ? { kind: 'live' } : { kind: 'fixture', name: v.slice('fixture:'.length) });
              }}
            >
              <option value="live">Live OpenStreetMap</option>
              {FIXTURES.map((f) => (
                <option key={f.name} value={`fixture:${f.name}`}>Fixture: {f.label}</option>
              ))}
            </select>
          </div>
        </div>
      </details>
    </div>
  );
}
