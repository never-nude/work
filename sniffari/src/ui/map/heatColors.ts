/** q → colour ramp for the debug layer. Red (avoid) → amber → green (great). Readable on a dark basemap. */
export const HEAT_STOPS: [number, string][] = [
  [0, '#ff3b5c'],
  [0.35, '#ff8a3d'],
  [0.55, '#ffd23f'],
  [0.75, '#8be36b'],
  [1, '#22e3a0'],
];

export const EXCLUDED_COLOR = '#6b6b80';

export function heatColor(q: number): string {
  if (q < 0) return EXCLUDED_COLOR;
  for (let i = 1; i < HEAT_STOPS.length; i++) {
    const [q1, c1] = HEAT_STOPS[i]!;
    if (q <= q1) {
      const [q0, c0] = HEAT_STOPS[i - 1]!;
      const t = (q - q0) / (q1 - q0);
      const mix = (a: string, b: string, k: number) =>
        Math.round(parseInt(a, 16) + (parseInt(b, 16) - parseInt(a, 16)) * k)
          .toString(16)
          .padStart(2, '0');
      return `#${mix(c0.slice(1, 3), c1.slice(1, 3), t)}${mix(c0.slice(3, 5), c1.slice(3, 5), t)}${mix(c0.slice(5, 7), c1.slice(5, 7), t)}`;
    }
  }
  return HEAT_STOPS[HEAT_STOPS.length - 1]![1];
}
