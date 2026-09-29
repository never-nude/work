import { useState } from 'react';
import { geocode, type GeocodeResult } from '../../data/geocode';
import { PROFILE_ORDER, PROFILES } from '../../scoring/profiles';
import { FIXTURES } from '../../state/fixtures';
import { TIME_PRESETS, useStore, type TimePreset } from '../../state/store';
import { Legend } from '../components/Legend';
import { RoutesPanel } from './RoutesPanel';
import { WalkPanel } from './WalkPanel';

const RADII = [
  { m: 805, label: '½ mi' },
  { m: 1609, label: '1 mi' },
  { m: 2414, label: '1½ mi' },
];

export function ControlSheet() {
  const s = useStore();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<GeocodeResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);

  const busy = s.status === 'loading';
  const sourceValue = s.source.kind === 'live' ? 'live' : `fixture:${s.source.name}`;

  async function search(e: React.FormEvent) {
    e.preventDefault();
    if (!query.trim()) return;
    setSearching(true);
    setSearchError(null);
    try {
      const r = await geocode(query.trim());
      setResults(r);
      if (r.length === 0) setSearchError('No matches');
    } catch (err) {
      setSearchError(err instanceof Error ? err.message : 'Search failed');
    } finally {
      setSearching(false);
    }
  }

  function pick(r: GeocodeResult) {
    s.setSource({ kind: 'live' });
    s.setStart({ lat: r.lat, lon: r.lon, label: r.label });
    setResults([]);
    setQuery('');
  }

  function locate() {
    navigator.geolocation?.getCurrentPosition(
      (pos) => {
        s.setSource({ kind: 'live' });
        s.setStart({ lat: pos.coords.latitude, lon: pos.coords.longitude, label: 'My location' });
      },
      (err) => setSearchError(err.message),
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  }

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
        <summary>Street-quality map &amp; start pin</summary>
        <div className="sheet__body more__body">
          <form className="search" onSubmit={search}>
            <input
              className="input"
              type="search"
              inputMode="search"
              placeholder="Search an address"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label="Search an address"
            />
            <button className="btn btn--icon" type="button" onClick={locate} aria-label="Use my location" title="Use my location">
              <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden>
                <circle cx="12" cy="12" r="4" fill="currentColor" />
                <path d="M12 2v3M12 19v3M2 12h3M19 12h3" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
                <circle cx="12" cy="12" r="7.5" fill="none" stroke="currentColor" strokeWidth="2" />
              </svg>
            </button>
          </form>
          {searching && <p className="hint">Searching…</p>}
          {searchError && <p className="hint hint--error">{searchError}</p>}
          {results.length > 0 && (
            <ul className="results">
              {results.map((r) => (
                <li key={`${r.lat},${r.lon}`}>
                  <button className="results__item" onClick={() => pick(r)}>
                    {r.label}
                  </button>
                </li>
              ))}
            </ul>
          )}
          <div className="start-row">
            <span className="start-row__label">Start</span>
            <span className="start-row__value">{s.start.label}</span>
          </div>
          <div className="field">
            <span className="field__label">Area</span>
            <div className="chips">
              {RADII.map((r) => (
                <button key={r.m} className={`chip${Math.abs(s.radiusM - r.m) < 5 ? ' chip--on' : ''}`} onClick={() => s.setRadius(r.m)}>
                  {r.label}
                </button>
              ))}
            </div>
          </div>
          <button className="btn" disabled={busy} onClick={() => s.load()}>
            {busy ? 'Working…' : s.heatmap ? 'Reload streets around start' : 'Score streets around start'}
          </button>
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
