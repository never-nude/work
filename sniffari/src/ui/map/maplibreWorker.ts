// MapLibre v6 locates its worker with `new URL('./maplibre-gl-worker.mjs', import.meta.url)`
// at runtime, which bundlers can't see. Bundle it explicitly and hand MapLibre the URL.
import { setWorkerUrl } from 'maplibre-gl';
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';

setWorkerUrl(workerUrl);
