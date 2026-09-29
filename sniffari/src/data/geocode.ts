import type { LatLon } from '../types';

export interface GeocodeResult extends LatLon {
  label: string;
  source: 'nominatim' | 'photon';
}

const NOMINATIM = 'https://nominatim.openstreetmap.org/search';
const PHOTON = 'https://photon.komoot.io/api/';

// Nominatim policy: max 1 request/second. Browsers send Referer automatically;
// User-Agent can't be set from a page, which the policy accepts for web apps.
let lastNominatim = 0;
async function throttle(): Promise<void> {
  const wait = lastNominatim + 1100 - Date.now();
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  lastNominatim = Date.now();
}

async function nominatim(q: string, signal?: AbortSignal): Promise<GeocodeResult[]> {
  await throttle();
  const url = `${NOMINATIM}?${new URLSearchParams({ q, format: 'jsonv2', limit: '5', addressdetails: '0' })}`;
  const res = await fetch(url, { signal, headers: { Accept: 'application/json' } });
  if (!res.ok) throw new Error(`Nominatim ${res.status}`);
  const rows = (await res.json()) as { lat: string; lon: string; display_name: string }[];
  return rows.map((r) => ({ lat: +r.lat, lon: +r.lon, label: r.display_name, source: 'nominatim' }));
}

async function photon(q: string, signal?: AbortSignal): Promise<GeocodeResult[]> {
  const res = await fetch(`${PHOTON}?${new URLSearchParams({ q, limit: '5' })}`, { signal });
  if (!res.ok) throw new Error(`Photon ${res.status}`);
  const json = (await res.json()) as {
    features: { geometry: { coordinates: [number, number] }; properties: Record<string, string | undefined> }[];
  };
  return json.features.map((f) => {
    const p = f.properties;
    const label = [p.name, [p.housenumber, p.street].filter(Boolean).join(' '), p.city, p.state]
      .filter((s) => s && s.length > 0)
      .join(', ');
    return { lon: f.geometry.coordinates[0], lat: f.geometry.coordinates[1], label, source: 'photon' };
  });
}

/** Nominatim first, Photon if it fails or finds nothing. */
export async function geocode(q: string, signal?: AbortSignal): Promise<GeocodeResult[]> {
  try {
    const r = await nominatim(q, signal);
    if (r.length > 0) return r;
  } catch (e) {
    if ((e as Error).name === 'AbortError') throw e;
  }
  return photon(q, signal);
}
