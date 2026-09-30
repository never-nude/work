export const clamp01 = (v: number): number => (v < 0 ? 0 : v > 1 ? 1 : v);

export const pct = (v: number): string => `${Math.round(v * 100)}%`;

export const metres = (m: number): string => (m >= 1000 ? 'over 1 km' : `${Math.round(m)} m`);
