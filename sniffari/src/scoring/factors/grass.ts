import type { EdgeFactor, FactorResult } from '../../types';
import { clamp01, metres, pct } from './util';

/**
 * Factor 3 — somewhere to sniff and do business. Rewards streets that border
 * green and streets with a green patch a short walk away (a potty stop doesn't
 * have to be on the route itself). Dog parks are neutral unless ctx.dogParks is on.
 */
export const grass: EdgeFactor = (f, ctx) => {
  const candidates: FactorResult[] = [];
  // Dog parks count only when the walker opts in (preference toggle).
  const useDogParks = ctx.dogParks === true;
  const dogParkWins = useDogParks && f.dogParkFraction > f.grassFraction;
  const fraction = dogParkWins ? f.dogParkFraction : f.grassFraction;

  if (fraction >= 0.05) {
    candidates.push({
      score: clamp01(0.35 + fraction * 0.65),
      reason: `${pct(fraction)} of this stretch borders ${dogParkWins ? 'a dog park' : 'grass or park'}`,
    });
  }

  // Distance-decay to the nearest green patch: 0.7 within 50 m, 0.45 at 150 m, 0 at 400 m.
  const dogParkNearer = useDogParks && f.nearDogParkM < f.nearGrassM;
  const d = dogParkNearer ? f.nearDogParkM : f.nearGrassM;
  let near = 0;
  if (d <= 50) near = 0.7;
  else if (d <= 150) near = 0.7 - (0.25 * (d - 50)) / 100;
  else if (d <= 400) near = 0.45 - (0.45 * (d - 150)) / 250;
  if (near > 0) candidates.push({ score: near, reason: `${dogParkNearer ? 'Dog park' : 'Green patch'} ${metres(d)} away` });

  // OSM rarely maps front lawns; quiet residential streets usually have some.
  if (f.roadClass === 'residential' || f.roadClass === 'living_street') {
    candidates.push({ score: 0.2, reason: 'Probably some lawns (not mapped)' });
  }

  if (candidates.length === 0) return { score: 0, reason: 'No green nearby' };
  return candidates.reduce((a, b) => (b.score > a.score ? b : a));
};
