import { useStore } from '../../state/store';
import { SearchBox } from '../components/SearchBox';

/**
 * Choosing where a one-way walk ends: tap the map, search an address,
 * or line the crosshair up and press "Finish here".
 */
export function FinishPicker() {
  const setEndPoint = useStore((s) => s.setEndPoint);
  const getViewBounds = useStore((s) => s.getViewBounds);

  const useCenter = () => {
    const b = getViewBounds?.();
    if (!b) return;
    setEndPoint({ lat: (b[0] + b[2]) / 2, lon: (b[1] + b[3]) / 2, label: 'Chosen finish' });
  };
  const cancel = () => useStore.setState({ pickingEnd: false, sheetOpen: true, planMessage: null, ...(useStore.getState().endPoint ? {} : { endMode: 'loop' }) });

  return (
    <>
      <div className="crosshair" aria-hidden>
        <span />
      </div>
      <section className="picker" role="dialog" aria-label="Choose where to finish">
        <p className="picker__title">Where do you want to finish?</p>
        <p className="hint">Tap or long-press the map, search, or center the crosshair.</p>
        <SearchBox placeholder="Finish at an address" onPick={setEndPoint} />
        <div className="picker__actions">
          <button className="btn btn--primary" onClick={useCenter}>
            Finish here
          </button>
          <button className="btn" onClick={cancel}>
            Cancel
          </button>
        </div>
      </section>
    </>
  );
}
