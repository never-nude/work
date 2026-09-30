import { useState } from 'react';
import { useStore } from '../../state/store';
import { PROFILES } from '../../scoring/profiles';
import { heatColor } from '../map/heatColors';
import { FACTOR_LABEL, FACTOR_ORDER } from '../components/labels';
import { ScoreBar } from '../components/ScoreBar';

const HIGHLIGHT_TAGS = ['highway', 'name', 'sidewalk', 'sidewalk:both', 'sidewalk:left', 'sidewalk:right', 'footway', 'maxspeed', 'lanes', 'surface', 'lit', 'access', 'foot', 'dog', 'service'];

export function EdgeInspector() {
  const d = useStore((s) => s.selected);
  const profileId = useStore((s) => s.profileId);
  const inspect = useStore((s) => s.inspect);
  const [copied, setCopied] = useState(false);
  const [showTags, setShowTags] = useState(false);
  if (!d) return null;

  const q = d.score.q;
  const f = d.features;

  async function copyStub() {
    if (!d) return;
    const stub = {
      street: `${d.name ?? friendlyType(f.highway)} (way ${d.wayId})`,
      wayIds: [d.wayId],
      at: { lat: +d.mid.lat.toFixed(6), lon: +d.mid.lon.toFixed(6) },
      rating: null,
      notes: '',
      model: { q: +q.toFixed(3), profile: profileId },
    };
    await navigator.clipboard.writeText(JSON.stringify(stub, null, 2) + ',');
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  return (
    <section className="inspector" aria-label="Street details">
      <header className="inspector__head">
        <div className="inspector__score" style={{ color: d.score.excluded ? undefined : heatColor(q) }}>
          {d.score.excluded ? '—' : Math.round(q * 100)}
        </div>
        <div className="inspector__title">
          <h2>{d.name ?? friendlyType(f.highway)}</h2>
          <p className="hint">
            {f.highway} · {Math.round(d.lengthM)} m · {PROFILES[profileId].name}
          </p>
        </div>
        <button className="btn btn--icon" onClick={() => inspect(null)} aria-label="Close">
          ✕
        </button>
      </header>

      {d.score.excluded && <p className="excluded">Not routed: {d.score.excluded}</p>}
      {!d.score.excluded && d.score.veto < 0.99 && (
        <p className="excluded">
          Traffic penalty ×{d.score.veto.toFixed(2)}: busy streets can't score well, whatever else they have
        </p>
      )}

      <ul className="factors">
        {FACTOR_ORDER.map((k) => {
          const r = d.score.factors[k];
          if (!r) return null;
          const w = d.weights[k];
          return (
            <li key={k} className={w ? '' : 'factors__off'}>
              <div className="factors__row">
                <span className="factors__name">{FACTOR_LABEL[k]}</span>
                <span className="factors__weight">{w ? `${Math.round(w * 100)}%` : 'not weighted'}</span>
                <span className="factors__val">{Math.round(r.score * 100)}</span>
              </div>
              <ScoreBar value={r.score} muted={!w} />
              <p className="factors__why">{r.reason}</p>
            </li>
          );
        })}
        <li className={d.score.amenities.score ? '' : 'factors__off'}>
          <div className="factors__row">
            <span className="factors__name">Amenities</span>
            <span className="factors__weight">bonus</span>
            <span className="factors__val">{Math.round(d.score.amenities.score * 100)}</span>
          </div>
          <p className="factors__why">{d.score.amenities.reason}</p>
        </li>
      </ul>

      <div className="inspector__actions">
        <button className="btn" onClick={copyStub}>
          {copied ? 'Copied' : 'Copy ground-truth stub'}
        </button>
        <a className="btn" href={`https://www.openstreetmap.org/way/${d.wayId}`} target="_blank" rel="noreferrer">
          Open in OSM
        </a>
        <button className="btn" onClick={() => setShowTags((v) => !v)}>
          {showTags ? 'Hide data' : 'Raw data'}
        </button>
      </div>

      {showTags && (
        <div className="raw">
          <table>
            <tbody>
              {Object.entries(d.tags)
                .sort(([a], [b]) => (HIGHLIGHT_TAGS.indexOf(a) + 1 || 99) - (HIGHLIGHT_TAGS.indexOf(b) + 1 || 99))
                .map(([k, v]) => (
                  <tr key={k}>
                    <th>{k}</th>
                    <td>{v}</td>
                  </tr>
                ))}
            </tbody>
          </table>
          <table>
            <tbody>
              {Object.entries(f)
                .filter(([, v]) => typeof v !== 'object' || v === null)
                .map(([k, v]) => (
                  <tr key={k}>
                    <th>{k}</th>
                    <td>{typeof v === 'number' ? Math.round(v * 100) / 100 : String(v)}</td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function friendlyType(highway: string): string {
  const map: Record<string, string> = {
    footway: 'Footpath', path: 'Path', residential: 'Residential street', service: 'Service road',
    tertiary: 'Local road', secondary: 'Main road', primary: 'Major road', steps: 'Steps', cycleway: 'Bike path',
  };
  return map[highway] ?? highway.charAt(0).toUpperCase() + highway.slice(1).replace(/_/g, ' ');
}
