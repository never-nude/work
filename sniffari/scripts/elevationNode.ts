// Node-side decoding of fixture elevation PNGs (the app decodes them in the worker).
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { PNG } from 'pngjs';
import { decodeRGBA, makeElevationLookup, type DecodedTile, type ElevationAt } from '../src/data/elevation';

export function loadFixtureElevation(name: string): ElevationAt | undefined {
  const dir = `fixtures/${name}.elevation`;
  if (!existsSync(dir)) return undefined;
  const tiles: DecodedTile[] = readdirSync(dir)
    .filter((f) => f.endsWith('.png'))
    .map((f) => {
      const [z, x, y] = f.slice(0, -4).split('-').map(Number) as [number, number, number];
      return { z, x, y, heights: decodeRGBA(PNG.sync.read(readFileSync(`${dir}/${f}`)).data) };
    });
  return tiles.length ? makeElevationLookup(tiles) : undefined;
}
