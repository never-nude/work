import { useEffect, useState } from 'react';
import { useStore } from '../state/store';
import { MapView } from './map/MapView';
import { ControlSheet } from './panels/ControlSheet';
import { EdgeInspector } from './panels/EdgeInspector';
import { FinishPicker } from './panels/FinishPicker';
import { MapButtons } from './map/MapButtons';
import { PinCard } from './panels/PinCard';
import { NavPanel } from './panels/NavPanel';

export function App() {
  const sheetOpen = useStore((s) => s.sheetOpen);
  const setSheetOpen = useStore((s) => s.setSheetOpen);
  const selected = useStore((s) => s.selected);
  const load = useStore((s) => s.load);
  const pickingEnd = useStore((s) => s.pickingEnd);
  const planning = useStore((s) => s.planning);
  const routes = useStore((s) => s.routes);
  const optimize = useStore((s) => s.optimize);
  const viewTooBig = useStore((s) => s.viewTooBig);
  const pin = useStore((s) => s.pin);
  const nav = useStore((s) => s.nav);

  // Fixture URLs (?fixture=…) load straight away — handy for calibration and screenshots.
  // On live data, start where the walker is (asks for location permission once).
  useEffect(() => {
    const st = useStore.getState();
    if (st.source.kind === 'fixture') load();
    else if (!new URLSearchParams(location.search).has('lat')) void st.locateMe();
  }, [load]);

  return (
    <div className="app">
      <MapView />
      <header className="topbar">
        <span className="brand">
          <BrandIcon />
          Sniffari
        </span>
        <span className="topbar__tag">dog walks</span>
      </header>
      {nav && <NavPanel />}
      {!nav && <MapButtons />}
      {viewTooBig && !pickingEnd && <div className="toast">Zoom in to see street scores and plan a walk</div>}
      {pickingEnd && <FinishPicker />}
      <PinCard />
      {!selected && !pickingEnd && !pin && !nav && routes.length === 0 && (
        <button className={`fab${sheetOpen ? ' fab--sheet-open' : ''}`} disabled={planning} onClick={() => void optimize()}>
          <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden>
            <path d="M5 19c3-1 3-6 7-7s4-6 7-7" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
            <circle cx="5" cy="19" r="2.4" fill="currentColor" />
            <circle cx="19" cy="5" r="2.4" fill="currentColor" />
          </svg>
          {planning ? 'Planning…' : 'Optimize route'}
        </button>
      )}
      <aside className={`sheet${sheetOpen ? ' sheet--open' : ''}${routes.length ? ' sheet--half' : ''}${selected || pickingEnd || pin || nav ? ' sheet--hidden' : ''}`}>
        <button className="sheet__handle" onClick={() => setSheetOpen(!sheetOpen)} aria-expanded={sheetOpen} aria-label="Toggle controls">
          <span />
        </button>
        <ControlSheet />
      </aside>
      {selected && (
        <aside className="sheet sheet--open sheet--inspector">
          <EdgeInspector />
        </aside>
      )}
    </div>
  );
}

/** public/brand/app-icon.png when present; a purple dot until the artwork is added. */
function BrandIcon() {
  const [failed, setFailed] = useState(false);
  if (failed) return <span className="brand__dot" aria-hidden />;
  return <img className="brand__icon" src="brand/app-icon.png" alt="" onError={() => setFailed(true)} />;
}
