import { useStore } from '../../state/store';

/** Always-visible status: what's loading, what failed, with Retry / Cancel. */
export function StatusPill() {
  const status = useStore((s) => s.status);
  const progress = useStore((s) => s.progress);
  const error = useStore((s) => s.error);
  const planning = useStore((s) => s.planning);
  const locating = useStore((s) => s.locating);
  const viewTooBig = useStore((s) => s.viewTooBig);
  const pickingEnd = useStore((s) => s.pickingEnd);
  const nav = useStore((s) => s.nav);
  const retryLoad = useStore((s) => s.retryLoad);
  const cancelPlan = useStore((s) => s.cancelPlan);
  if (nav || pickingEnd) return null;

  let text: string | null = null;
  let action: { label: string; run: () => void } | null = null;
  let tone: 'busy' | 'error' | 'info' = 'busy';

  if (error) {
    text = error;
    tone = 'error';
    action = { label: 'Retry', run: retryLoad };
  } else if (locating) text = 'Finding you…';
  else if (status === 'loading') text = progress?.message || 'Loading streets…';
  else if (planning) {
    text = progress?.stage === 'route' ? 'Planning your walk…' : 'Planning your walk…';
    action = { label: 'Cancel', run: cancelPlan };
  } else if (viewTooBig) {
    text = 'Zoom in to see street scores and plan a walk';
    tone = 'info';
  }
  if (!text) return null;

  const pct = status === 'loading' && progress?.total ? Math.round((progress.done / progress.total) * 100) : null;
  return (
    <div className={`pill pill--${tone}`} role="status" aria-live="polite">
      {tone === 'busy' && <span className="pill__spinner" aria-hidden />}
      <span className="pill__text">{text}</span>
      {pct !== null && <span className="pill__pct">{pct}%</span>}
      {action && (
        <button className="pill__btn" onClick={action.run}>
          {action.label}
        </button>
      )}
    </div>
  );
}
