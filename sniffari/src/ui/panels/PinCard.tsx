import { useStore } from '../../state/store';

/** Actions for a dropped pin: its approximate address, start here, finish here. */
export function PinCard() {
  const pin = useStore((s) => s.pin);
  const pinAsStart = useStore((s) => s.pinAsStart);
  const pinAsFinish = useStore((s) => s.pinAsFinish);
  const clearPin = useStore((s) => s.clearPin);
  if (!pin) return null;
  return (
    <section className="pincard" role="dialog" aria-label="Dropped pin">
      <div className="pincard__head">
        <div>
          <p className="pincard__addr">{pin.resolving ? 'Looking up address…' : pin.address ?? 'Unknown address'}</p>
          <p className="hint">
            {pin.lat.toFixed(5)}, {pin.lon.toFixed(5)}
          </p>
        </div>
        <button className="btn btn--icon" onClick={clearPin} aria-label="Remove pin">
          ✕
        </button>
      </div>
      <div className="picker__actions">
        <button className="btn btn--primary" onClick={pinAsStart}>
          Start here
        </button>
        <button className="btn btn--primary" onClick={pinAsFinish}>
          Finish here
        </button>
      </div>
    </section>
  );
}
