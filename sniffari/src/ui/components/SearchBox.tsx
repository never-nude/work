import { useState } from 'react';
import { geocode, type GeocodeResult } from '../../data/geocode';
import type { Place } from '../../state/store';

/** Address search with a result list. Used for "go to address" and "finish at address". */
export function SearchBox({ placeholder, onPick, autoFocus }: { placeholder: string; onPick: (p: Place) => void; autoFocus?: boolean }) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<GeocodeResult[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!query.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const r = await geocode(query.trim());
      setResults(r);
      if (!r.length) setError('No matches');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Search failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="searchbox">
      <form className="search" onSubmit={submit}>
        <input
          className="input"
          type="search"
          inputMode="search"
          enterKeyHint="search"
          autoFocus={autoFocus}
          placeholder={placeholder}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          aria-label={placeholder}
        />
        <button className="btn" type="submit" disabled={busy}>
          {busy ? '…' : 'Go'}
        </button>
      </form>
      {error && <p className="hint hint--error">{error}</p>}
      {results.length > 0 && (
        <ul className="results">
          {results.map((r) => (
            <li key={`${r.lat},${r.lon}`}>
              <button
                className="results__item"
                onClick={() => {
                  setResults([]);
                  setQuery('');
                  onPick({ lat: r.lat, lon: r.lon, label: r.label.split(',').slice(0, 2).join(',') });
                }}
              >
                {r.label}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
