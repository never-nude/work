import { heatColor } from '../map/heatColors';

export function ScoreBar({ value, muted = false }: { value: number; muted?: boolean }) {
  return (
    <div className={`bar${muted ? ' bar--muted' : ''}`} role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(value * 100)}>
      <div className="bar__fill" style={{ width: `${Math.max(2, value * 100)}%`, background: muted ? undefined : heatColor(value) }} />
    </div>
  );
}
