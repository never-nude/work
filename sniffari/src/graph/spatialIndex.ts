import Flatbush from 'flatbush';
import { pointInRing, pointSegmentDist } from './geo';

/** Points in local metres, queryable by radius. */
export class PointIndex<T> {
  private index: Flatbush | null;
  constructor(
    private readonly pts: { x: number; y: number; item: T }[],
  ) {
    if (pts.length === 0) {
      this.index = null;
      return;
    }
    const idx = new Flatbush(pts.length);
    for (const p of pts) idx.add(p.x, p.y, p.x, p.y);
    idx.finish();
    this.index = idx;
  }

  get size(): number {
    return this.pts.length;
  }

  item(i: number): T {
    return this.pts[i]!.item;
  }

  /** Indices of points within r metres. */
  withinIdx(x: number, y: number, r: number): number[] {
    if (!this.index) return [];
    return this.index
      .search(x - r, y - r, x + r, y + r)
      .filter((i) => {
        const p = this.pts[i]!;
        return Math.hypot(p.x - x, p.y - y) <= r;
      });
  }

  within(x: number, y: number, r: number): T[] {
    return this.withinIdx(x, y, r).map((i) => this.pts[i]!.item);
  }

  nearestDist(x: number, y: number, maxDist = Infinity): number {
    if (!this.index) return Infinity;
    const [i] = this.index.neighbors(x, y, 1, maxDist);
    if (i === undefined) return Infinity;
    const p = this.pts[i]!;
    return Math.hypot(p.x - x, p.y - y);
  }
}

interface Segment {
  ax: number;
  ay: number;
  bx: number;
  by: number;
  ownerId: number;
}

/** Polyline segments, queryable for exact nearest distance. */
export class SegmentIndex {
  private readonly segs: Segment[] = [];
  private index: Flatbush | null = null;

  addLine(pts: [number, number][], ownerId: number): void {
    for (let i = 1; i < pts.length; i++) {
      const a = pts[i - 1]!;
      const b = pts[i]!;
      this.segs.push({ ax: a[0], ay: a[1], bx: b[0], by: b[1], ownerId });
    }
  }

  finish(): this {
    if (this.segs.length === 0) return this;
    const idx = new Flatbush(this.segs.length);
    for (const s of this.segs) {
      idx.add(Math.min(s.ax, s.bx), Math.min(s.ay, s.by), Math.max(s.ax, s.bx), Math.max(s.ay, s.by));
    }
    idx.finish();
    this.index = idx;
    return this;
  }

  /** Nearest segment's owner and distance within maxDist, or null. */
  nearestOwner(x: number, y: number, maxDist: number): { ownerId: number; dist: number } | null {
    if (!this.index) return null;
    let best: { ownerId: number; dist: number } | null = null;
    for (const i of this.index.search(x - maxDist, y - maxDist, x + maxDist, y + maxDist)) {
      const s = this.segs[i]!;
      const d = pointSegmentDist(x, y, s.ax, s.ay, s.bx, s.by);
      if (d <= maxDist && (!best || d < best.dist)) best = { ownerId: s.ownerId, dist: d };
    }
    return best;
  }

  /**
   * Exact distance to the nearest segment within maxDist (Infinity if none).
   * `exclude` skips segments belonging to a given owner (e.g. the road itself).
   */
  nearestDist(x: number, y: number, maxDist: number, exclude?: (ownerId: number) => boolean): number {
    if (!this.index) return Infinity;
    let best = Infinity;
    for (const i of this.index.search(x - maxDist, y - maxDist, x + maxDist, y + maxDist)) {
      const s = this.segs[i]!;
      if (exclude?.(s.ownerId)) continue;
      const d = pointSegmentDist(x, y, s.ax, s.ay, s.bx, s.by);
      if (d < best) best = d;
    }
    return best <= maxDist ? best : Infinity;
  }
}

interface Ring {
  pts: [number, number][];
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

/**
 * Areas (parks, grass, woods) for "inside or near" queries. Rings are treated
 * individually with even-odd containment; inner rings (holes) are ignored —
 * a courtyard inside a park still counts as park, which is fine for dogs.
 */
export class AreaIndex {
  private readonly rings: Ring[] = [];
  private readonly edges = new SegmentIndex();
  private index: Flatbush | null = null;

  /** Add a closed ring (containment + boundary) or an open line (boundary only, e.g. tree_row). */
  add(pts: [number, number][], closed: boolean): void {
    if (pts.length < 2) return;
    this.edges.addLine(pts, this.rings.length);
    if (closed && pts.length >= 4) {
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (const [x, y] of pts) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
      this.rings.push({ pts, minX, minY, maxX, maxY });
    }
  }

  finish(): this {
    this.edges.finish();
    if (this.rings.length > 0) {
      const idx = new Flatbush(this.rings.length);
      for (const r of this.rings) idx.add(r.minX, r.minY, r.maxX, r.maxY);
      idx.finish();
      this.index = idx;
    }
    return this;
  }

  contains(x: number, y: number): boolean {
    if (!this.index) return false;
    return this.index.search(x, y, x, y).some((i) => pointInRing(x, y, this.rings[i]!.pts));
  }

  /** 0 if inside, else distance to the nearest boundary (Infinity beyond maxDist). */
  distance(x: number, y: number, maxDist: number): number {
    if (this.contains(x, y)) return 0;
    return this.edges.nearestDist(x, y, maxDist);
  }
}
