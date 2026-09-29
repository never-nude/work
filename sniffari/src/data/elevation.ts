import type { LatLon } from '../types';
import type { BBox } from './overpass';

/**
 * Elevation from Mapzen/Tilezen "Terrarium" tiles on AWS Open Data — keyless,
 * CORS-enabled, ~5–10 m resolution in the US at z14. A 1.5-mile walk area is
 * ~12–20 tiles of ~100 KB. Decoded tiles are cached like Overpass tiles.
 */
export const TERRARIUM_URL = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png';
export const ELEVATION_ZOOM = 14;
const TILE = 256;

export interface DecodedTile {
  z: number;
  x: number;
  y: number;
  /** Row-major metres, TILE × TILE. */
  heights: Float32Array;
}

/** Terrarium encoding: (R × 256 + G + B / 256) − 32768 metres. */
export function decodeTerrarium(r: number, g: number, b: number): number {
  return r * 256 + g + b / 256 - 32768;
}

export function decodeRGBA(rgba: Uint8ClampedArray | Uint8Array): Float32Array {
  const out = new Float32Array(rgba.length / 4);
  for (let i = 0; i < out.length; i++) out[i] = decodeTerrarium(rgba[i * 4]!, rgba[i * 4 + 1]!, rgba[i * 4 + 2]!);
  return out;
}

/** Fractional Web-Mercator tile coordinates. */
export function lonLatToTileXY(lat: number, lon: number, z: number): [number, number] {
  const n = 2 ** z;
  const x = ((lon + 180) / 360) * n;
  const latR = (lat * Math.PI) / 180;
  const y = ((1 - Math.log(Math.tan(latR) + 1 / Math.cos(latR)) / Math.PI) / 2) * n;
  return [x, y];
}

export function tilesForElevation([s, w, n, e]: BBox, z = ELEVATION_ZOOM): { z: number; x: number; y: number }[] {
  const [x0, y0] = lonLatToTileXY(n, w, z);
  const [x1, y1] = lonLatToTileXY(s, e, z);
  const out = [];
  for (let x = Math.floor(x0); x <= Math.floor(x1); x++) {
    for (let y = Math.floor(y0); y <= Math.floor(y1); y++) out.push({ z, x, y });
  }
  return out;
}

export type ElevationAt = (p: LatLon) => number | null;

/** Bilinear lookup across a set of decoded tiles. Returns null outside them. */
export function makeElevationLookup(tiles: DecodedTile[]): ElevationAt {
  const byKey = new Map(tiles.map((t) => [`${t.z}/${t.x}/${t.y}`, t]));
  const z = tiles[0]?.z ?? ELEVATION_ZOOM;
  const px = (tx: number, ty: number): number | null => {
    const X = Math.floor(tx / TILE);
    const Y = Math.floor(ty / TILE);
    const t = byKey.get(`${z}/${X}/${Y}`);
    if (!t) return null;
    const v = t.heights[(ty - Y * TILE) * TILE + (tx - X * TILE)];
    return v === undefined ? null : v;
  };
  return ({ lat, lon }) => {
    const [fx, fy] = lonLatToTileXY(lat, lon, z);
    const gx = fx * TILE - 0.5;
    const gy = fy * TILE - 0.5;
    const x0 = Math.floor(gx);
    const y0 = Math.floor(gy);
    const dx = gx - x0;
    const dy = gy - y0;
    const a = px(x0, y0), b = px(x0 + 1, y0), c = px(x0, y0 + 1), d = px(x0 + 1, y0 + 1);
    if (a === null || b === null || c === null || d === null) return a ?? b ?? c ?? d;
    return a * (1 - dx) * (1 - dy) + b * dx * (1 - dy) + c * (1 - dx) * dy + d * dx * dy;
  };
}

export function terrariumUrl(z: number, x: number, y: number): string {
  return TERRARIUM_URL.replace('{z}', String(z)).replace('{x}', String(x)).replace('{y}', String(y));
}

/** Browser / worker fetch + decode (needs createImageBitmap + OffscreenCanvas). `url` overrides the source (fixtures). */
export async function fetchTerrariumTile(
  z: number,
  x: number,
  y: number,
  signal?: AbortSignal,
  url = terrariumUrl(z, x, y),
): Promise<DecodedTile> {
  const res = await fetch(url, { signal });
  if (!res.ok) throw new Error(`Elevation tile ${z}/${x}/${y}: ${res.status}`);
  const bmp = await createImageBitmap(await res.blob(), { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
  const canvas = new OffscreenCanvas(TILE, TILE);
  const ctx = canvas.getContext('2d', { willReadFrequently: true })!;
  ctx.drawImage(bmp, 0, 0);
  return { z, x, y, heights: decodeRGBA(ctx.getImageData(0, 0, TILE, TILE).data) };
}
