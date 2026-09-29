import { EXCLUDED_COLOR, HEAT_STOPS } from '../map/heatColors';

export function Legend() {
  const gradient = `linear-gradient(90deg, ${HEAT_STOPS.map(([q, c]) => `${c} ${q * 100}%`).join(', ')})`;
  return (
    <div className="legend">
      <div className="legend__ramp" style={{ background: gradient }} />
      <div className="legend__labels">
        <span>Avoid</span>
        <span>OK</span>
        <span>Great</span>
      </div>
      <div className="legend__keys">
        <span className="legend__key">
          <i style={{ borderColor: EXCLUDED_COLOR }} className="legend__dash" /> Excluded
        </span>
        <span className="legend__key">
          <i className="legend__dot" style={{ background: '#22e3a0' }} /> Signals
        </span>
        <span className="legend__key">
          <i className="legend__dot" style={{ background: '#ffd23f' }} /> Marked
        </span>
        <span className="legend__key">
          <i className="legend__dot" style={{ background: '#ff3b5c' }} /> Unmarked crossing
        </span>
      </div>
    </div>
  );
}
