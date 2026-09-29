// Generates fixtures/synthetic.overpass.json — a small, hand-designed
// neighbourhood in Overpass JSON format that exercises every tag path the
// graph builder and factors care about. Deterministic; safe to regenerate.
//
//            y=400 ─────────────────────────────────────────
//   Broadway │  PARK (leisure=park)   │ Cottage Pl        │ Hamilton Ave
//   tertiary │  footway (gravel) ─────┤ residential       │ secondary, sidewalk=no
//            │  path dog=no  │        │                   │
//   y=200 ───┼── Oak Ave (residential, sidewalks, lit, street trees) ─┼── construction
//            │                        │                   │
//   y=0   ───┼── Main St (primary, 4 lanes, shops, bus stop) ─────────┼──
//   y=-12    ├── Main St sidewalk (footway=sidewalk) ─┤    │
//   y=-200 ──┼── Elm St (residential, untagged) ── grass verge area ──┼──
//            │                        └─ private service road
//   y=-350 ═══════════════ railway ════ station ═══════════════
//                                                     x=450 motorway
import { writeFileSync, mkdirSync } from 'node:fs';

const CENTER = { lat: 41.0335, lon: -73.763 };
const KX = 111320 * Math.cos((CENTER.lat * Math.PI) / 180);
const KY = 110574;
const ll = (x, y) => ({ lat: +(CENTER.lat + y / KY).toFixed(7), lon: +(CENTER.lon + x / KX).toFixed(7) });

const elements = [];
const nodeAt = new Map();
let nextNode = 1000;
let nextWay = 100;

function node(x, y, tags) {
  const k = `${x},${y}`;
  if (nodeAt.has(k)) {
    const id = nodeAt.get(k);
    if (tags) {
      const el = elements.find((e) => e.type === 'node' && e.id === id);
      el.tags = { ...el.tags, ...tags };
    }
    return id;
  }
  const id = nextNode++;
  nodeAt.set(k, id);
  elements.push({ type: 'node', id, ...ll(x, y), ...(tags ? { tags } : {}) });
  return id;
}

function way(points, tags) {
  const id = nextWay++;
  elements.push({ type: 'way', id, nodes: points.map(([x, y]) => node(x, y)), tags });
  return id;
}

function area(points, tags) {
  const ring = [...points, points[0]];
  const id = nextWay++;
  elements.push({ type: 'way', id, geometry: ring.map(([x, y]) => ll(x, y)), tags });
  return id;
}

function line(points, tags) {
  const id = nextWay++;
  elements.push({ type: 'way', id, geometry: points.map(([x, y]) => ll(x, y)), tags });
  return id;
}

function poi(x, y, tags) {
  elements.push({ type: 'node', id: nextNode++, ...ll(x, y), tags });
}

// Pre-create shared intersection nodes with tags.
node(0, 0, { highway: 'traffic_signals' }); // Main × Cottage
node(-300, 0, { highway: 'crossing', crossing: 'unmarked' }); // Main × Broadway

// East–west streets
way([[-400, 0], [-300, 0], [-150, 0], [0, 0], [150, 0], [300, 0], [400, 0]], {
  highway: 'primary', name: 'Main Street', lanes: '4', maxspeed: '30 mph', sidewalk: 'both', lit: 'yes',
});
way([[-400, 200], [-300, 200], [-150, 200], [0, 200], [150, 200], [300, 200]], {
  highway: 'residential', name: 'Oak Avenue', sidewalk: 'both', lit: 'yes', maxspeed: '25 mph',
});
way([[-400, -200], [-300, -200], [-150, -200], [0, -200], [150, -200], [300, -200], [400, -200]], {
  highway: 'residential', name: 'Elm Street',
});
way([[-300, -12], [-150, -12], [0, -12]], { highway: 'footway', footway: 'sidewalk', name: 'Main Street sidewalk' });

// North–south streets
way([[-300, -300], [-300, -200], [-300, -12], [-300, 0], [-300, 200], [-300, 300], [-300, 400]], {
  highway: 'tertiary', name: 'Broadway', sidewalk: 'both',
});
way([[0, -300], [0, -200], [0, -12], [0, 0], [0, 200], [0, 300], [0, 400]], {
  highway: 'residential', name: 'Cottage Place', sidewalk: 'both',
});
way([[300, -300], [300, -200], [300, 0], [300, 200], [300, 400]], {
  highway: 'secondary', name: 'Hamilton Avenue', sidewalk: 'no', lanes: '2',
});

// Park + its paths
area([[-260, 220], [-40, 220], [-40, 380], [-260, 380]], { leisure: 'park', name: 'Cottage Green' });
way([[-300, 300], [-150, 300], [0, 300]], { highway: 'footway', surface: 'gravel', name: 'Green Walk' });
way([[-150, 220], [-150, 300], [-150, 380]], { highway: 'path', dog: 'no', name: 'Garden Path' });
poi(-100, 305, { amenity: 'waste_basket' });
poi(-110, 305, { vending: 'excrement_bags', amenity: 'vending_machine' });
poi(-120, 296, { amenity: 'bench' });

// Street trees along Oak Ave east of Cottage
for (let x = 10; x <= 290; x += 15) poi(x, 208, { natural: 'tree' });

// Woodland multipolygon relation (SW corner)
const woodRing = [[-400, -300], [-306, -300], [-306, -220], [-400, -220], [-400, -300]];
elements.push({
  type: 'relation',
  id: 9001,
  tags: { type: 'multipolygon', natural: 'wood' },
  members: [{ type: 'way', ref: 9101, role: 'outer', geometry: woodRing.map(([x, y]) => ll(x, y)) }],
});

// Grass verge strip along Elm St east
area([[100, -230], [260, -230], [260, -210], [100, -210]], { landuse: 'grass' });

// Downtown shops along Main St
const shops = ['clothes', 'bakery', 'convenience', 'hairdresser', 'mobile_phone', 'shoes'];
for (let i = 0; i < 12; i++) {
  const x = -200 + i * 35;
  if (i % 2 === 0) poi(x, 18, { shop: shops[i % shops.length] });
  else poi(x, -24, { amenity: i % 3 === 0 ? 'cafe' : 'restaurant', name: `Eatery ${i}` });
}
// A restaurant mapped as a building (out center)
elements.push({ type: 'way', id: nextWay++, center: ll(120, 25), tags: { amenity: 'restaurant', building: 'yes' } });
poi(100, 8, { highway: 'bus_stop' });
poi(40, -18, { shop: 'pet', dog: 'yes' });

// Excluded ways
way([[0, -200], [60, -250], [100, -280]], { highway: 'service', access: 'private' });
way([[300, 200], [400, 200]], { highway: 'construction', construction: 'residential' });
way([[450, -400], [450, 0], [450, 400]], { highway: 'motorway', name: 'I-287' });
way([[150, -200], [150, -170]], { highway: 'service', service: 'driveway' });

// Rail + station
line([[-450, -350], [450, -350]], { railway: 'rail', name: 'Harlem Line' });
poi(0, -340, { railway: 'station', public_transport: 'station', name: 'Synthetic Station' });

mkdirSync('fixtures', { recursive: true });
writeFileSync('fixtures/synthetic.overpass.json', JSON.stringify({ elements }, null, 0) + '\n');
writeFileSync(
  'fixtures/synthetic.meta.json',
  JSON.stringify({ name: 'synthetic', label: 'Synthetic test grid', center: CENTER, radiusM: 700 }, null, 2) + '\n',
);
console.log(`wrote ${elements.length} elements`);
