import { useEffect, useState } from 'react';
import { useStore } from '../state/store';
import { MapView } from './map/MapView';
import { ControlSheet } from './panels/ControlSheet';
import { EdgeInspector } from './panels/EdgeInspector';

export function App() {
  const sheetOpen = useStore((s) => s.sheetOpen);
  const setSheetOpen = useStore((s) => s.setSheetOpen);
  const selected = useStore((s) => s.selected);
  const load = useStore((s) => s.load);

  // Fixture URLs (?fixture=…) load straight away — handy for calibration and screenshots.
  useEffect(() => {
    if (useStore.getState().source.kind === 'fixture') load();
  }, [load]);

  return (
    <div className="app">
      <MapView />
      <header className="topbar">
        <span className="brand">
          <BrandIcon />
          Sniffari
        </span>
        <span className="topbar__tag">street quality · debug</span>
      </header>
      <aside className={`sheet${sheetOpen ? ' sheet--open' : ''}${selected ? ' sheet--hidden' : ''}`}>
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
