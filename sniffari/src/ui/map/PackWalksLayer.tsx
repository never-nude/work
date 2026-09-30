import { useEffect, useRef } from 'react';
import { Marker } from 'maplibre-gl';
import { useSocial } from '../../social/store';
import { useStore } from '../../state/store';

/**
 * Friends' live walks: a green dot labelled with the dog's name at their last
 * shared position. (Positions are withheld near their start/finish on their phone.)
 */
export function PackWalksLayer() {
  const walks = useSocial((s) => s.packWalks);
  const focusId = useSocial((s) => s.focusWalkId);
  const flyTo = useStore((s) => s.flyTo);
  const markers = useRef(new Map<string, Marker>());

  useEffect(() => {
    const map = (globalThis as unknown as { __sniffariMap?: import('maplibre-gl').Map }).__sniffariMap;
    if (!map) return;
    const live = new Set<string>();
    for (const w of walks) {
      if (w.last_lat == null || w.last_lon == null) continue;
      live.add(w.id);
      let m = markers.current.get(w.id);
      if (!m) {
        const el = document.createElement('div');
        el.className = 'pack-marker';
        el.innerHTML = '<span class="pack-marker__dot"></span><span class="pack-marker__name"></span>';
        el.querySelector('.pack-marker__name')!.textContent = w.profiles?.dog_name ?? 'Pack dog';
        el.addEventListener('click', (e) => {
          e.stopPropagation();
          useSocial.getState().focus(w.id);
        });
        m = new Marker({ element: el, anchor: 'top' }).setLngLat([w.last_lon, w.last_lat]).addTo(map);
        markers.current.set(w.id, m);
      } else m.setLngLat([w.last_lon, w.last_lat]);
    }
    for (const [id, m] of markers.current) {
      if (!live.has(id)) {
        m.remove();
        markers.current.delete(id);
      }
    }
  }, [walks]);

  useEffect(() => {
    const w = walks.find((x) => x.id === focusId);
    if (w && w.last_lat != null && w.last_lon != null) flyTo?.({ lat: w.last_lat, lon: w.last_lon }, 15.5);
  }, [focusId, walks, flyTo]);

  return null;
}
