import type {
  EraserMode,
  EraseTarget,
  FillShape,
  PlacedImage,
  Point,
  Rect,
  Stroke,
} from '../types/model';

export function rectsIntersect(a: Rect, b: Rect): boolean {
  return !(
    a.x + a.width < b.x ||
    b.x + b.width < a.x ||
    a.y + a.height < b.y ||
    b.y + b.height < a.y
  );
}

export function rectContainsPoint(r: Rect, p: Point): boolean {
  return p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height;
}

export function rectUnion(a: Rect, b: Rect): Rect {
  const minX = Math.min(a.x, b.x);
  const minY = Math.min(a.y, b.y);
  const maxX = Math.max(a.x + a.width, b.x + b.width);
  const maxY = Math.max(a.y + a.height, b.y + b.height);
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

export function rectInset(r: Rect, dx: number, dy: number): Rect {
  return {
    x: r.x + dx,
    y: r.y + dy,
    width: Math.max(0, r.width - dx * 2),
    height: Math.max(0, r.height - dy * 2),
  };
}

export function imageCenter(img: PlacedImage): Point {
  return {
    x: img.position.x + img.size.width / 2,
    y: img.position.y + img.size.height / 2,
  };
}

export function imageRotatedCorners(img: PlacedImage): Point[] {
  const { x, y } = img.position;
  const { width, height } = img.size;
  const raw: Point[] = [
    { x, y },
    { x: x + width, y },
    { x: x + width, y: y + height },
    { x, y: y + height },
  ];
  if (!img.rotation) return raw;
  const center = imageCenter(img);
  const cosA = Math.cos(img.rotation);
  const sinA = Math.sin(img.rotation);
  return raw.map((p) => {
    const dx = p.x - center.x;
    const dy = p.y - center.y;
    return {
      x: center.x + dx * cosA - dy * sinA,
      y: center.y + dx * sinA + dy * cosA,
    };
  });
}

export function imageRotatedBoundingBox(img: PlacedImage): Rect {
  if (!img.rotation) {
    return { x: img.position.x, y: img.position.y, width: img.size.width, height: img.size.height };
  }
  const corners = imageRotatedCorners(img);
  let minX = corners[0].x;
  let maxX = corners[0].x;
  let minY = corners[0].y;
  let maxY = corners[0].y;
  for (let i = 1; i < corners.length; i++) {
    const c = corners[i];
    if (c.x < minX) minX = c.x;
    if (c.x > maxX) maxX = c.x;
    if (c.y < minY) minY = c.y;
    if (c.y > maxY) maxY = c.y;
  }
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

export function imageContainsPoint(img: PlacedImage, point: Point): boolean {
  if (!img.rotation) {
    return rectContainsPoint(
      { x: img.position.x, y: img.position.y, width: img.size.width, height: img.size.height },
      point
    );
  }
  const center = imageCenter(img);
  const dx = point.x - center.x;
  const dy = point.y - center.y;
  const cosA = Math.cos(-img.rotation);
  const sinA = Math.sin(-img.rotation);
  const lx = dx * cosA - dy * sinA;
  const ly = dx * sinA + dy * cosA;
  return Math.abs(lx) <= img.size.width / 2 && Math.abs(ly) <= img.size.height / 2;
}

export function fillBoundingBox(fill: FillShape): Rect | null {
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  let found = false;
  for (const loop of fill.contours) {
    for (const p of loop) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      found = true;
    }
  }
  if (!found) return null;
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

export function fillContainsPoint(fill: FillShape, point: Point): boolean {
  const box = fillBoundingBox(fill);
  if (!box || !rectContainsPoint(box, point)) return false;
  // Even-odd rule across all contour loops (outer + holes)
  let inside = false;
  for (const loop of fill.contours) {
    if (loop.length >= 3 && pointInPolygon(point, loop)) {
      inside = !inside;
    }
  }
  return inside;
}

/** 2D uniform-grid spatial hash for O(1)-bucket queries over dense boards. */
export class SpatialHashGrid {
  readonly cellSize: number;
  private buckets = new Map<string, number[]>();
  private boundsByIndex: (Rect | null)[] = [];
  private indexedCount = 0;
  private firstId: string | null = null;
  private lastId: string | null = null;

  constructor(cellSize = 256) {
    this.cellSize = Math.max(cellSize, 32);
  }

  private key(x: number, y: number): string {
    return `${x},${y}`;
  }

  sync(strokes: Stroke[]): void {
    const first = strokes[0]?.id ?? null;
    const last = strokes[strokes.length - 1]?.id ?? null;
    if (strokes.length === this.indexedCount && first === this.firstId && last === this.lastId) {
      return;
    }

    if (
      strokes.length === this.indexedCount + 1 &&
      this.indexedCount > 0 &&
      first === this.firstId &&
      strokes[this.indexedCount - 1].id === this.lastId
    ) {
      const idx = this.indexedCount;
      const b = strokeBounds(strokes[idx]);
      this.boundsByIndex.push(b);
      if (b) this.insert(idx, b);
      this.indexedCount = strokes.length;
      this.lastId = last;
      return;
    }

    this.rebuild(strokes);
  }

  rebuild(strokes: Stroke[]): void {
    this.buckets.clear();
    this.boundsByIndex = new Array(strokes.length);
    for (let idx = 0; idx < strokes.length; idx++) {
      const b = strokeBounds(strokes[idx]);
      this.boundsByIndex[idx] = b;
      if (b) this.insert(idx, b);
    }
    this.indexedCount = strokes.length;
    this.firstId = strokes[0]?.id ?? null;
    this.lastId = strokes[strokes.length - 1]?.id ?? null;
  }

  invalidate(): void {
    this.buckets.clear();
    this.boundsByIndex = [];
    this.indexedCount = 0;
    this.firstId = null;
    this.lastId = null;
  }

  queryIndices(rect: Rect): number[] {
    if (
      rect.width <= 0 ||
      rect.height <= 0 ||
      !Number.isFinite(rect.x) ||
      !Number.isFinite(rect.y) ||
      this.indexedCount === 0
    ) {
      return [];
    }
    const minCX = Math.floor(rect.x / this.cellSize);
    const maxCX = Math.floor((rect.x + rect.width) / this.cellSize);
    const minCY = Math.floor(rect.y / this.cellSize);
    const maxCY = Math.floor((rect.y + rect.height) / this.cellSize);
    if (minCX > maxCX || minCY > maxCY) return [];

    const spanX = maxCX - minCX + 1;
    const spanY = maxCY - minCY + 1;
    if (spanX > 64 || spanY > 64 || spanX * spanY > 2048) {
      const result: number[] = [];
      for (let i = 0; i < this.boundsByIndex.length; i++) {
        const b = this.boundsByIndex[i];
        if (b && rectsIntersect(b, rect)) result.push(i);
      }
      return result;
    }

    const seen = new Set<number>();
    const result: number[] = [];
    for (let cx = minCX; cx <= maxCX; cx++) {
      for (let cy = minCY; cy <= maxCY; cy++) {
        const list = this.buckets.get(this.key(cx, cy));
        if (!list) continue;
        for (const idx of list) {
          if (!seen.has(idx)) {
            seen.add(idx);
            const b = this.boundsByIndex[idx];
            if (b && rectsIntersect(b, rect)) result.push(idx);
          }
        }
      }
    }
    result.sort((a, b) => a - b);
    return result;
  }

  private insert(index: number, bounds: Rect): void {
    if (bounds.width <= 0 || bounds.height <= 0) return;
    const minCX = Math.floor(bounds.x / this.cellSize);
    const maxCX = Math.floor((bounds.x + bounds.width) / this.cellSize);
    const minCY = Math.floor(bounds.y / this.cellSize);
    const maxCY = Math.floor((bounds.y + bounds.height) / this.cellSize);
    if (minCX > maxCX || minCY > maxCY) return;

    const clampedMaxCX = Math.min(maxCX, minCX + 64);
    const clampedMaxCY = Math.min(maxCY, minCY + 64);
    for (let cx = minCX; cx <= clampedMaxCX; cx++) {
      for (let cy = minCY; cy <= clampedMaxCY; cy++) {
        const k = this.key(cx, cy);
        let arr = this.buckets.get(k);
        if (!arr) {
          arr = [];
          this.buckets.set(k, arr);
        }
        arr.push(index);
      }
    }
  }
}

export function simplifyRDP(points: Point[], tolerance = 0.3): Point[] {
  if (points.length <= 2 || tolerance <= 0) return points;
  const tolSq = tolerance * tolerance;
  const keep = new Uint8Array(points.length);
  keep[0] = 1;
  keep[points.length - 1] = 1;

  const stack: [number, number][] = [[0, points.length - 1]];
  while (stack.length > 0) {
    const [start, end] = stack.pop()!;
    if (end - start <= 1) continue;
    const a = points[start];
    const b = points[end];
    let maxDistSq = 0;
    let maxIdx = start;
    for (let i = start + 1; i < end; i++) {
      const dSq = pointSegmentDistanceSquared(points[i], a, b);
      if (dSq > maxDistSq) {
        maxDistSq = dSq;
        maxIdx = i;
      }
    }
    if (maxDistSq > tolSq) {
      keep[maxIdx] = 1;
      stack.push([start, maxIdx], [maxIdx, end]);
    }
  }

  const result: Point[] = [];
  for (let i = 0; i < points.length; i++) {
    if (keep[i]) result.push(points[i]);
  }
  return result;
}

export function smoothCatmullRom(points: Point[]): Point[] {
  if (points.length < 3) return points;
  const gaussWeights = [0.061, 0.242, 0.394, 0.242, 0.061];
  const smoothed: Point[] = new Array(points.length);
  for (let i = 0; i < points.length; i++) {
    let sx = 0;
    let sy = 0;
    let sw = 0;
    for (let w = -2; w <= 2; w++) {
      const idx = i + w;
      if (idx < 0 || idx >= points.length) continue;
      const weight = gaussWeights[w + 2];
      sx += points[idx].x * weight;
      sy += points[idx].y * weight;
      sw += weight;
    }
    smoothed[i] = sw > 0 ? { x: sx / sw, y: sy / sw } : points[i];
  }

  const result: Point[] = [smoothed[0]];
  for (let i = 0; i < smoothed.length - 1; i++) {
    const p0 = i > 0 ? smoothed[i - 1] : smoothed[i];
    const p1 = smoothed[i];
    const p2 = smoothed[i + 1];
    const p3 = i + 2 < smoothed.length ? smoothed[i + 2] : smoothed[i + 1];
    result.push(
      { x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6 },
      { x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6 },
      p2
    );
  }
  return result;
}

export function strokeBounds(stroke: Stroke): Rect | null {
  if (stroke.points.length === 0) return null;
  let minX = stroke.points[0].x;
  let maxX = minX;
  let minY = stroke.points[0].y;
  let maxY = minY;
  for (let i = 1; i < stroke.points.length; i++) {
    const p = stroke.points[i];
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  const margin = (stroke.isSharpie ? stroke.lineWidth + 3 : stroke.lineWidth) / 2 + 2;
  return {
    x: minX - margin,
    y: minY - margin,
    width: maxX - minX + margin * 2,
    height: maxY - minY + margin * 2,
  };
}

export function boundingBox(
  strokes: Stroke[],
  images: PlacedImage[],
  fills: FillShape[] = [],
  padding = 0
): Rect | null {
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  let hasContent = false;

  for (const s of strokes) {
    if (s.isEraser || s.points.length === 0) continue;
    const halfWidth = (s.isSharpie ? s.lineWidth + 3 : s.lineWidth) / 2;
    for (const p of s.points) {
      if (p.x - halfWidth < minX) minX = p.x - halfWidth;
      if (p.x + halfWidth > maxX) maxX = p.x + halfWidth;
      if (p.y - halfWidth < minY) minY = p.y - halfWidth;
      if (p.y + halfWidth > maxY) maxY = p.y + halfWidth;
      hasContent = true;
    }
  }

  for (const img of images) {
    const r = imageRotatedBoundingBox(img);
    if (r.width <= 0 || r.height <= 0) continue;
    minX = Math.min(minX, r.x);
    maxX = Math.max(maxX, r.x + r.width);
    minY = Math.min(minY, r.y);
    maxY = Math.max(maxY, r.y + r.height);
    hasContent = true;
  }

  for (const fill of fills) {
    const r = fillBoundingBox(fill);
    if (!r) continue;
    minX = Math.min(minX, r.x);
    maxX = Math.max(maxX, r.x + r.width);
    minY = Math.min(minY, r.y);
    maxY = Math.max(maxY, r.y + r.height);
    hasContent = true;
  }

  if (!hasContent || maxX < minX || maxY < minY) return null;
  return {
    x: minX - padding,
    y: minY - padding,
    width: Math.max(1, maxX - minX) + padding * 2,
    height: Math.max(1, maxY - minY) + padding * 2,
  };
}

export function distance(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export function distanceSquared(a: Point, b: Point): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return dx * dx + dy * dy;
}

export function pointInPolygon(point: Point, polygon: Point[]): boolean {
  if (polygon.length < 3) return false;
  let inside = false;
  let j = polygon.length - 1;
  for (let i = 0; i < polygon.length; i++) {
    const pi = polygon[i];
    const pj = polygon[j];
    if (
      pi.y > point.y !== pj.y > point.y &&
      point.x < ((pj.x - pi.x) * (point.y - pi.y)) / (pj.y - pi.y) + pi.x
    ) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

export function pointSegmentDistanceSquared(p: Point, a: Point, b: Point): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lenSq = dx * dx + dy * dy;
  if (lenSq <= 0) {
    const px = p.x - a.x;
    const py = p.y - a.y;
    return px * px + py * py;
  }
  const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq));
  const projX = a.x + t * dx;
  const projY = a.y + t * dy;
  const rx = p.x - projX;
  const ry = p.y - projY;
  return rx * rx + ry * ry;
}

function segmentsIntersect(a: Point, b: Point, c: Point, d: Point): boolean {
  const cross = (o: Point, u: Point, v: Point) =>
    (u.x - o.x) * (v.y - o.y) - (u.y - o.y) * (v.x - o.x);
  const d1 = cross(a, b, c);
  const d2 = cross(a, b, d);
  const d3 = cross(c, d, a);
  const d4 = cross(c, d, b);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

export function segmentSegmentDistanceSquared(a: Point, b: Point, c: Point, d: Point): number {
  if (segmentsIntersect(a, b, c, d)) return 0;
  return Math.min(
    pointSegmentDistanceSquared(a, c, d),
    pointSegmentDistanceSquared(b, c, d),
    pointSegmentDistanceSquared(c, a, b),
    pointSegmentDistanceSquared(d, a, b)
  );
}

export function eraseStrokes(
  strokes: Stroke[],
  eraser: Stroke,
  mode: EraserMode,
  target: EraseTarget,
  generateNewId: () => string,
  spatialGrid?: SpatialHashGrid
): Stroke[] {
  if (eraser.points.length === 0 || target === 'fill') return strokes;
  const radius = Math.max(eraser.lineWidth / 2, 0.5);
  const radiusSq = radius * radius;
  const eb = strokeBounds(eraser);
  if (!eb) return strokes;
  const eraserBounds = rectInset(eb, -radius, -radius);

  let candidates: Set<number> | null = null;
  if (spatialGrid) {
    spatialGrid.sync(strokes);
    candidates = new Set(spatialGrid.queryIndices(eraserBounds));
  }

  const isTargeted = (s: Stroke) => {
    if (target === 'all') return true;
    if (target === 'pen') return !s.isSharpie;
    if (target === 'sharpie') return s.isSharpie;
    return false;
  };

  const eraserSegments: [Point, Point][] =
    eraser.points.length >= 2
      ? eraser.points.slice(0, -1).map((pt, i) => [pt, eraser.points[i + 1]])
      : [[eraser.points[0], eraser.points[0]]];

  const pointHit = (p: Point): boolean => {
    for (const [ea, ebPt] of eraserSegments) {
      if (pointSegmentDistanceSquared(p, ea, ebPt) < radiusSq) return true;
    }
    return false;
  };

  const strokeHit = (pen: Stroke): boolean => {
    const sb = strokeBounds(pen);
    if (!sb || !rectsIntersect(sb, eraserBounds)) return false;
    if (pen.points.length === 1) return pointHit(pen.points[0]);
    for (let i = 0; i < pen.points.length - 1; i++) {
      const pa = pen.points[i];
      const pb = pen.points[i + 1];
      for (const [ea, ebPt] of eraserSegments) {
        if (segmentSegmentDistanceSquared(pa, pb, ea, ebPt) < radiusSq) return true;
      }
    }
    return false;
  };

  if (mode === 'full') {
    const kept: Stroke[] = [];
    for (let idx = 0; idx < strokes.length; idx++) {
      const pen = strokes[idx];
      if (candidates && !candidates.has(idx)) {
        kept.push(pen);
        continue;
      }
      if (pen.isEraser || !isTargeted(pen) || !strokeHit(pen)) {
        kept.push(pen);
      }
    }
    return kept;
  }

  const result: Stroke[] = [];
  for (let idx = 0; idx < strokes.length; idx++) {
    const pen = strokes[idx];
    if (candidates && !candidates.has(idx)) {
      result.push(pen);
      continue;
    }
    const sb = strokeBounds(pen);
    if (pen.isEraser || !isTargeted(pen) || !sb || !rectsIntersect(sb, eraserBounds)) {
      result.push(pen);
      continue;
    }

    let segment: Point[] = [];
    for (let i = 0; i < pen.points.length; i++) {
      const pp = pen.points[i];
      const erasedPoint = pointHit(pp);
      let erasedEdge = false;
      if (i > 0 && !erasedPoint && segment.length > 0) {
        const prev = pen.points[i - 1];
        for (const [ea, ebPt] of eraserSegments) {
          if (segmentSegmentDistanceSquared(prev, pp, ea, ebPt) < radiusSq) {
            erasedEdge = true;
            break;
          }
        }
      }
      if (erasedPoint || erasedEdge) {
        if (segment.length >= 2) {
          result.push({ ...pen, id: generateNewId(), points: segment, isEraser: false });
        }
        segment = erasedPoint ? [] : [pp];
      } else {
        segment.push(pp);
      }
    }
    if (segment.length >= 2) {
      result.push({ ...pen, id: generateNewId(), points: segment, isEraser: false });
    }
  }
  return result;
}

export function eraseFills(
  fills: FillShape[],
  eraser: Stroke,
  target: EraseTarget
): FillShape[] {
  if (eraser.points.length === 0 || (target !== 'all' && target !== 'fill')) return fills;
  const radius = Math.max(eraser.lineWidth / 2, 0.5);
  const radiusSq = radius * radius;
  const eb = strokeBounds(eraser);
  if (!eb) return fills;
  const eraserBounds = rectInset(eb, -radius, -radius);

  return fills.filter((fill) => {
    const fb = fillBoundingBox(fill);
    if (!fb || !rectsIntersect(fb, eraserBounds)) return true;
    // Hit if any eraser point falls inside the fill or near any contour edge
    for (const ep of eraser.points) {
      if (fillContainsPoint(fill, ep)) return false;
      for (const loop of fill.contours) {
        for (let i = 0; i < loop.length; i++) {
          const a = loop[i];
          const b = loop[(i + 1) % loop.length];
          if (pointSegmentDistanceSquared(ep, a, b) < radiusSq) return false;
        }
      }
    }
    return true;
  });
}

export function resizedRect(
  start: Rect,
  corner: number,
  offset: { width: number; height: number },
  minSize = 10
): Rect | null {
  if (
    start.width <= 0 ||
    start.height <= 0 ||
    !Number.isFinite(start.width) ||
    !Number.isFinite(start.height) ||
    !Number.isFinite(offset.width) ||
    !Number.isFinite(offset.height)
  ) {
    return null;
  }
  const aspect = start.width / start.height;
  const dragX = Math.abs(offset.width) >= Math.abs(offset.height);
  const maxX = start.x + start.width;
  const maxY = start.y + start.height;
  let newRect = start;

  switch (corner) {
    case 0:
      if (dragX) {
        const newW = Math.max(minSize, start.width - offset.width);
        const newH = newW / aspect;
        newRect = { x: maxX - newW, y: maxY - newH, width: newW, height: newH };
      } else {
        const newH = Math.max(minSize, start.height - offset.height);
        const newW = newH * aspect;
        newRect = { x: maxX - newW, y: maxY - newH, width: newW, height: newH };
      }
      break;
    case 1:
      if (dragX) {
        const newW = Math.max(minSize, start.width + offset.width);
        const newH = newW / aspect;
        newRect = { x: start.x, y: maxY - newH, width: newW, height: newH };
      } else {
        const newH = Math.max(minSize, start.height - offset.height);
        const newW = newH * aspect;
        newRect = { x: start.x, y: maxY - newH, width: newW, height: newH };
      }
      break;
    case 2:
      if (dragX) {
        const newW = Math.max(minSize, start.width + offset.width);
        const newH = newW / aspect;
        newRect = { x: start.x, y: start.y, width: newW, height: newH };
      } else {
        const newH = Math.max(minSize, start.height + offset.height);
        const newW = newH * aspect;
        newRect = { x: start.x, y: start.y, width: newW, height: newH };
      }
      break;
    case 3:
      if (dragX) {
        const newW = Math.max(minSize, start.width - offset.width);
        const newH = newW / aspect;
        newRect = { x: maxX - newW, y: start.y, width: newW, height: newH };
      } else {
        const newH = Math.max(minSize, start.height + offset.height);
        const newW = newH * aspect;
        newRect = { x: maxX - newW, y: start.y, width: newW, height: newH };
      }
      break;
    default:
      return null;
  }

  if (
    newRect.width < minSize ||
    newRect.height < minSize ||
    !Number.isFinite(newRect.x) ||
    !Number.isFinite(newRect.y)
  ) {
    return null;
  }
  return newRect;
}

export function normalizeAngle(radians: number): number {
  let a = radians % (2 * Math.PI);
  if (a <= -Math.PI) a += 2 * Math.PI;
  if (a > Math.PI) a -= 2 * Math.PI;
  if (Math.abs(a) < 1e-6) return 0;
  return a;
}

export function rotatePoint(point: Point, pivot: Point, radians: number): Point {
  if (radians === 0) return point;
  const dx = point.x - pivot.x;
  const dy = point.y - pivot.y;
  const cosA = Math.cos(radians);
  const sinA = Math.sin(radians);
  return {
    x: pivot.x + dx * cosA - dy * sinA,
    y: pivot.y + dx * sinA + dy * cosA,
  };
}

export function snapRotationAngle(
  radians: number,
  snapToStep: boolean,
  stepRadians = Math.PI / 12,
  cardinalThreshold = (4 * Math.PI) / 180
): { angle: number; snapped: boolean } {
  const normalized = normalizeAngle(radians);
  if (snapToStep && stepRadians > 0) {
    const stepped = Math.round(normalized / stepRadians) * stepRadians;
    return { angle: normalizeAngle(stepped), snapped: true };
  }
  const cardinals = [-Math.PI, -Math.PI / 2, 0, Math.PI / 2, Math.PI];
  for (const c of cardinals) {
    if (Math.abs(normalized - c) <= cardinalThreshold) {
      return { angle: normalizeAngle(c), snapped: true };
    }
  }
  return { angle: normalized, snapped: false };
}

export function recognizeShape(points: Point[]): Point[] | null {
  if (points.length < 6) return null;
  const first = points[0];
  const last = points[points.length - 1];

  let minX = first.x;
  let maxX = first.x;
  let minY = first.y;
  let maxY = first.y;
  let totalLength = 0;

  for (let i = 1; i < points.length; i++) {
    const p = points[i];
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
    totalLength += Math.hypot(p.x - points[i - 1].x, p.y - points[i - 1].y);
  }

  const width = maxX - minX;
  const height = maxY - minY;
  const diag = Math.hypot(width, height);
  if (diag < 28 || totalLength < 28) return null;

  const endDist = Math.hypot(last.x - first.x, last.y - first.y);

  // 1. Straight line check
  if (endDist >= 28 && totalLength <= endDist * 1.18) {
    const ldx = last.x - first.x;
    const ldy = last.y - first.y;
    const lenSq = Math.max(ldx * ldx + ldy * ldy, 1e-6);
    let maxDev = 0;
    for (const p of points) {
      const t = Math.min(Math.max(((p.x - first.x) * ldx + (p.y - first.y) * ldy) / lenSq, 0), 1);
      const projX = first.x + t * ldx;
      const projY = first.y + t * ldy;
      const d = Math.hypot(p.x - projX, p.y - projY);
      if (d > maxDev) maxDev = d;
    }
    if (maxDev / endDist < 0.085) {
      const steps = 16;
      const out: Point[] = [];
      for (let i = 0; i <= steps; i++) {
        const t = i / steps;
        out.push({ x: first.x + (last.x - first.x) * t, y: first.y + (last.y - first.y) * t });
      }
      return out;
    }
  }

  // Closed shape threshold
  const isClosed = endDist <= Math.max(36, diag * 0.28);
  if (!isClosed || width < 18 || height < 18) return null;

  // 2. Circle / Ellipse check
  const cx = (minX + maxX) / 2;
  const cy = (minY + maxY) / 2;
  const rx = width / 2;
  const ry = height / 2;
  let radialErrSum = 0;
  for (const p of points) {
    const nx = (p.x - cx) / rx;
    const ny = (p.y - cy) / ry;
    radialErrSum += Math.abs(Math.hypot(nx, ny) - 1.0);
  }
  if (radialErrSum / points.length < 0.14) {
    const aspect = rx / ry;
    const finalRx = aspect > 0.85 && aspect < 1.18 ? (rx + ry) / 2 : rx;
    const finalRy = aspect > 0.85 && aspect < 1.18 ? (rx + ry) / 2 : ry;
    const segments = 64;
    const out: Point[] = [];
    for (let i = 0; i <= segments; i++) {
      const angle = (i / segments) * Math.PI * 2;
      out.push({ x: cx + Math.cos(angle) * finalRx, y: cy + Math.sin(angle) * finalRy });
    }
    return out;
  }

  // 3. Axis-aligned Rectangle check
  let edgeErrSum = 0;
  for (const p of points) {
    const dMin = Math.min(
      Math.abs(p.x - minX),
      Math.abs(p.x - maxX),
      Math.abs(p.y - minY),
      Math.abs(p.y - maxY)
    );
    edgeErrSum += dMin;
  }
  const perimeter = 2 * (width + height);
  if (
    edgeErrSum / points.length / diag < 0.085 &&
    totalLength >= perimeter * 0.78 &&
    totalLength <= perimeter * 1.35
  ) {
    const corners: Point[] = [
      { x: minX, y: minY },
      { x: maxX, y: minY },
      { x: maxX, y: maxY },
      { x: minX, y: maxY },
      { x: minX, y: minY },
    ];
    const dense: Point[] = [];
    const stepsPerEdge = 8;
    for (let e = 0; e < 4; e++) {
      const a = corners[e];
      const b = corners[e + 1];
      for (let s = 0; s < stepsPerEdge; s++) {
        const t = s / stepsPerEdge;
        dense.push({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
      }
    }
    dense.push(corners[0]);
    return dense;
  }

  return null;
}

export function paddedBoundingPolygon(rect: Rect): Point[] {
  if (rect.width <= 0 || rect.height <= 0) return [];
  const r = Math.min(8, rect.width * 0.25, rect.height * 0.25);
  const minX = rect.x;
  const minY = rect.y;
  const maxX = rect.x + rect.width;
  const maxY = rect.y + rect.height;
  return [
    { x: minX + r, y: minY },
    { x: maxX - r, y: minY },
    { x: maxX, y: minY + r },
    { x: maxX, y: maxY - r },
    { x: maxX - r, y: maxY },
    { x: minX + r, y: maxY },
    { x: minX, y: maxY - r },
    { x: minX, y: minY + r },
    { x: minX + r, y: minY },
  ];
}
