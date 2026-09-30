import { useState } from 'react';
import { useStore } from '../../state/store';
import { SearchBox } from '../components/SearchBox';

/** Floating map buttons: return to my location, and go to an address. */
export function MapButtons() {
  const locateMe = useStore((s) => s.locateMe);
  const locating = useStore((s) => s.locating);
  const goTo = useStore((s) => s.goTo);
  const [searching, setSearching] = useState(false);

  return (
    <>
      <div className="mapbtns">
        <button className="mapbtn" onClick={() => void locateMe()} aria-label="Go to my location" title="Go to my location" disabled={locating}>
          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden className={locating ? 'spin' : ''}>
            <path d="M12 2 L20 20 L12 16 L4 20 Z" fill="currentColor" transform="rotate(45 12 12)" />
          </svg>
        </button>
        <button className="mapbtn" onClick={() => setSearching((v) => !v)} aria-label="Go to an address" title="Go to an address" aria-expanded={searching}>
          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden>
            <circle cx="10.5" cy="10.5" r="6.5" fill="none" stroke="currentColor" strokeWidth="2.4" />
            <path d="M15.5 15.5 L21 21" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" />
          </svg>
        </button>
      </div>
      {searching && (
        <div className="searchpanel">
          <SearchBox
            placeholder="Go to an address"
            autoFocus
            onPick={(p) => {
              setSearching(false);
              goTo(p);
            }}
          />
        </div>
      )}
    </>
  );
}
