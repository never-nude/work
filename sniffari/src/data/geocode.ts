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

/** Approximate street address for a point: Nominatim reverse, Photon reverse as fallback. */
export async function reverseGeocode(p: LatLon, signal?: AbortSignal): Promise<string | null> {
  try {
    await throttle();
    const url = `https://nominatim.openstreetmap.org/reverse?${new URLSearchParams({ lat: String(p.lat), lon: String(p.lon), format: 'jsonv2', zoom: '18', addressdetails: '1' })}`;
    const res = await fetch(url, { signal, headers: { Accept: 'application/json' } });
    if (res.ok) {
      const j = (await res.json()) as { display_name?: string; address?: Record<string, string> };
      const a = j.address ?? {};
      const street = [a.house_number, a.road ?? a.pedestrian ?? a.footway ?? a.path].filter(Boolean).join(' ');
      const town = a.city ?? a.town ?? a.village ?? a.suburb;
      const short = [street || a.park || a.amenity, town].filter(Boolean).join(', ');
      if (short) return short;
      if (j.display_name) return j.display_name.split(',').slice(0, 2).join(',');
    }
  } catch (e) {
    if ((e as Error).name === 'AbortError') throw e;
  }
  try {
    const res = await fetch(`https://photon.komoot.io/reverse?lat=${p.lat}&lon=${p.lon}`, { signal });
    const j = (await res.json()) as { features: { properties: Record<string, string | undefined> }[] };
    const pr = j.features[0]?.properties;
    if (!pr) return null;
    return [[pr.housenumber, pr.street].filter(Boolean).join(' ') || pr.name, pr.city].filter(Boolean).join(', ');
  } catch {
    return null;
  }
}

/** Coarse place name for sharing — neighbourhood and town only, never a street. */
export async function reverseArea(p: LatLon): Promise<string | null> {
  try {
    await throttle();
    const url = `https://nominatim.openstreetmap.org/reverse?${new URLSearchParams({ lat: String(p.lat), lon: String(p.lon), format: 'jsonv2', zoom: '14', addressdetails: '1' })}`;
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) return null;
    const a = ((await res.json()) as { address?: Record<string, string> }).address ?? {};
    const hood = a.neighbourhood ?? a.suburb ?? a.quarter;
    const town = a.city ?? a.town ?? a.village ?? a.hamlet;
    return [hood, town].filter(Boolean).join(', ') || null;
  } catch {
    return null;
  }
}
