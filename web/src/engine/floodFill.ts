import type { CanvasShape, Point, Rect, Stroke } from '../types/model';
import {
  isLineLikeShape,
  pointSegmentDistanceSquared,
  rectContainsPoint,
  rectInset,
  rectsIntersect,
  rectUnion,
  rotatePoint,
  shapeCenter,
  shapeRect,
  shapeRotatedBoundingBox,
  simplifyRDP,
  smoothCatmullRom,
  strokeBounds,
} from './geometry';

const MAX_GRID_DIMENSION = 1024;

/**
 * Fast local-region scanline flood fill with contour vectorization
 * (1:1 port of FloodFillEngine.swift).
 * - Rasterizes only nearby strokes into a bounded 1-byte-per-pixel mask.
 * - Aborts cleanly if fill reaches outer margin (zero bleeding on open shapes).
 * - Separable dilation expands slightly under stroke centerline (zero anti-alias halo).
 * - Traces closed outer + hole contours, smooths with distance-capped Chaikin, simplifies via RDP.
 */
export function computeFillContours(
  tapPoint: Point,
  strokes: Stroke[],
  gapTolerance = 2.5,
  shapes: CanvasShape[] = []
): Point[][] | null {
  const barrierStrokes = strokes.filter((s) => !s.isEraser && s.points.length >= 2);
  if (barrierStrokes.length === 0 && shapes.length === 0) return null;

  const initialRadius = 600;
  let searchRect: Rect = {
    x: tapPoint.x - initialRadius,
    y: tapPoint.y - initialRadius,
    width: initialRadius * 2,
    height: initialRadius * 2,
  };

  let localStrokes: Stroke[] = [];
  let localShapes: CanvasShape[] = [];
  let unionBounds: Rect | null = null;

  for (const s of barrierStrokes) {
    const b = strokeBounds(s);
    if (b && rectsIntersect(b, searchRect)) {
      localStrokes.push(s);
      unionBounds = unionBounds ? rectUnion(unionBounds, b) : b;
    }
  }
  for (const sh of shapes) {
    const b = shapeRotatedBoundingBox(sh);
    if (rectsIntersect(b, searchRect)) {
      localShapes.push(sh);
      unionBounds = unionBounds ? rectUnion(unionBounds, b) : b;
    }
  }
  if ((localStrokes.length === 0 && localShapes.length === 0) || !unionBounds) return null;

  // Pull in neighbors once more if any extended outside initial searchRect
  if (
    unionBounds.x < searchRect.x ||
    unionBounds.y < searchRect.y ||
    unionBounds.x + unionBounds.width > searchRect.x + searchRect.width ||
    unionBounds.y + unionBounds.height > searchRect.y + searchRect.height
  ) {
    searchRect = rectInset(unionBounds, -20, -20);
    localStrokes = [];
    localShapes = [];
    unionBounds = null;
    for (const s of barrierStrokes) {
      const b = strokeBounds(s);
      if (b && rectsIntersect(b, searchRect)) {
        localStrokes.push(s);
        unionBounds = unionBounds ? rectUnion(unionBounds, b) : b;
      }
    }
    for (const sh of shapes) {
      const b = shapeRotatedBoundingBox(sh);
      if (rectsIntersect(b, searchRect)) {
        localShapes.push(sh);
        unionBounds = unionBounds ? rectUnion(unionBounds, b) : b;
      }
    }
  }

  if (!unionBounds || !rectContainsPoint(unionBounds, tapPoint)) return null;

  const margin = Math.max(12, gapTolerance * 2 + 6);
  const region = rectInset(unionBounds, -margin, -margin);
  if (region.width <= 2 || region.height <= 2) return null;

  const maxDim = Math.max(region.width, region.height);
  const gridScale = Math.min(2.0, MAX_GRID_DIMENSION / maxDim);
  const w = Math.ceil(region.width * gridScale);
  const h = Math.ceil(region.height * gridScale);
  if (w < 4 || h < 4) return null;

  // 1. Rasterize barrier strokes and shapes into a 1-byte-per-pixel mask
  const barrier = rasterizeBarriers(localStrokes, localShapes, region, gridScale, w, h, gapTolerance);
  if (!barrier) return null;

  // 2. Locate open seed pixel (nudging slightly if tap landed directly on a stroke)
  const rawSeedX = Math.round((tapPoint.x - region.x) * gridScale);
  const rawSeedY = Math.round((tapPoint.y - region.y) * gridScale);
  const seed = findOpenSeed(rawSeedX, rawSeedY, barrier, w, h);
  if (!seed) return null;

  // 3. Scanline flood fill with bleed guard
  const filled = new Uint8Array(w * h);
  let minFX = seed[0];
  let maxFX = seed[0];
  let minFY = seed[1];
  let maxFY = seed[1];

  const stackX: number[] = [seed[0]];
  const stackY: number[] = [seed[1]];

  const isOpen = (x: number, y: number): boolean => {
    const idx = y * w + x;
    return filled[idx] === 0 && barrier[idx] < 64;
  };

  while (stackX.length > 0) {
    const sx = stackX.pop()!;
    const sy = stackY.pop()!;
    if (!isOpen(sx, sy)) continue;

    let lx = sx;
    while (lx > 0 && isOpen(lx - 1, sy)) lx -= 1;
    let rx = sx;
    while (rx < w - 1 && isOpen(rx + 1, sy)) rx += 1;

    // Bleed check: touching edge of raster region means shape is open -> abort
    if (lx === 0 || rx === w - 1 || sy === 0 || sy === h - 1) {
      return null;
    }

    const rowOffset = sy * w;
    for (let x = lx; x <= rx; x++) {
      filled[rowOffset + x] = 1;
    }
    if (lx < minFX) minFX = lx;
    if (rx > maxFX) maxFX = rx;
    if (sy < minFY) minFY = sy;
    if (sy > maxFY) maxFY = sy;

    for (const ny of [sy - 1, sy + 1]) {
      let inSpan = false;
      for (let x = lx; x <= rx; x++) {
        if (isOpen(x, ny)) {
          if (!inSpan) {
            stackX.push(x);
            stackY.push(ny);
            inSpan = true;
          }
        } else {
          inSpan = false;
        }
      }
    }
  }

  // 4. Expand filled mask slightly under stroke centerline so there is zero halo
  const expandRadius = Math.min(Math.max(Math.ceil((gapTolerance + 1.0) * gridScale), 1), 24);
  const cropMinX = Math.max(0, minFX - expandRadius - 1);
  const cropMaxX = Math.min(w - 1, maxFX + expandRadius + 1);
  const cropMinY = Math.max(0, minFY - expandRadius - 1);
  const cropMaxY = Math.min(h - 1, maxFY + expandRadius + 1);
  const cw = cropMaxX - cropMinX + 1;
  const ch = cropMaxY - cropMinY + 1;
  if (cw < 3 || ch < 3) return null;

  const pw = cw + 2;
  const ph = ch + 2;
  let mask: Uint8Array = new Uint8Array(pw * ph);
  for (let y = 0; y < ch; y++) {
    const srcRow = (cropMinY + y) * w + cropMinX;
    const dstRow = (y + 1) * pw + 1;
    for (let x = 0; x < cw; x++) {
      mask[dstRow + x] = filled[srcRow + x];
    }
  }

  if (expandRadius > 0) {
    mask = dilateSeparable(mask, pw, ph, expandRadius);
  }

  // 5. Trace closed vector contours (outer boundary + interior holes)
  const gridLoops = traceContours(mask, pw, ph);
  if (gridLoops.length === 0) return null;

  // 6. Map back to canvas space, lightly smooth staircases, simplify via RDP
  const originX = region.x + (cropMinX - 1) / gridScale;
  const originY = region.y + (cropMinY - 1) / gridScale;
  const invScale = 1.0 / gridScale;

  const contours: Point[][] = [];
  for (const loop of gridLoops) {
    let pts: Point[] = loop.map(([gx, gy]) => ({
      x: originX + gx * invScale,
      y: originY + gy * invScale,
    }));
    if (pts.length >= 4) {
      pts = chaikinClosed(pts, 0.5 * invScale);
    }
    if (pts.length > 4) {
      const closed = [...pts, pts[0]];
      const simplified = simplifyRDP(closed, Math.max(0.45, 0.7 * invScale));
      if (
        simplified.length > 1 &&
        simplified[simplified.length - 1].x === simplified[0].x &&
        simplified[simplified.length - 1].y === simplified[0].y
      ) {
        simplified.pop();
      }
      pts = simplified;
    }
    if (pts.length >= 3) {
      contours.push(pts);
    }
  }

  return contours.length === 0 ? null : contours;
}

function shapeBarrierPolylines(shape: CanvasShape): Point[][] {
  if (isLineLikeShape(shape.kind)) {
    return [[shape.start, shape.end]];
  }
  const r = shapeRect(shape);
  const midX = r.x + r.width / 2;
  const midY = r.y + r.height / 2;
  let pts: Point[] = [];
  if (shape.kind === 'rectangle') {
    pts = [
      { x: r.x, y: r.y },
      { x: r.x + r.width, y: r.y },
      { x: r.x + r.width, y: r.y + r.height },
      { x: r.x, y: r.y + r.height },
      { x: r.x, y: r.y },
    ];
  } else if (shape.kind === 'triangle') {
    pts = [
      { x: midX, y: r.y },
      { x: r.x + r.width, y: r.y + r.height },
      { x: r.x, y: r.y + r.height },
      { x: midX, y: r.y },
    ];
  } else if (shape.kind === 'diamond') {
    pts = [
      { x: midX, y: r.y },
      { x: r.x + r.width, y: midY },
      { x: midX, y: r.y + r.height },
      { x: r.x, y: midY },
      { x: midX, y: r.y },
    ];
  } else {
    const segs = 48;
    for (let i = 0; i <= segs; i++) {
      const a = (i / segs) * Math.PI * 2;
      pts.push({ x: midX + Math.cos(a) * (r.width / 2), y: midY + Math.sin(a) * (r.height / 2) });
    }
  }
  if (shape.rotation) {
    const c = shapeCenter(shape);
    pts = pts.map((p) => rotatePoint(p, c, shape.rotation));
  }
  return [pts];
}

function rasterizeBarriers(
  strokes: Stroke[],
  shapes: CanvasShape[],
  region: Rect,
  gridScale: number,
  w: number,
  h: number,
  gapTolerance: number
): Uint8Array | null {
  const extraWidth = Math.max(0, gapTolerance) * 2;

  // Fast browser Canvas2D path
  if (typeof document !== 'undefined') {
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    if (ctx) {
      ctx.clearRect(0, 0, w, h);
      ctx.save();
      ctx.scale(gridScale, gridScale);
      ctx.translate(-region.x, -region.y);
      ctx.strokeStyle = '#ffffff';
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';

      for (const s of strokes) {
        ctx.lineWidth = Math.max(s.lineWidth + extraWidth, 1.5 / gridScale);
        ctx.beginPath();
        traceStrokeToContext(ctx, s);
        ctx.stroke();
      }
      for (const sh of shapes) {
        ctx.lineWidth = Math.max(sh.lineWidth + extraWidth, 1.5 / gridScale);
        for (const poly of shapeBarrierPolylines(sh)) {
          if (poly.length < 2) continue;
          ctx.beginPath();
          ctx.moveTo(poly[0].x, poly[0].y);
          for (let i = 1; i < poly.length; i++) ctx.lineTo(poly[i].x, poly[i].y);
          ctx.stroke();
        }
      }
      ctx.restore();

      const img = ctx.getImageData(0, 0, w, h).data;
      const out = new Uint8Array(w * h);
      for (let i = 0; i < w * h; i++) {
        out[i] = img[i * 4 + 3];
      }
      return out;
    }
  }

  // Pure software rasterizer fallback (used in Vitest / headless Node environments)
  const out = new Uint8Array(w * h);
  const rasterPolyline = (pts: Point[], baseWidth: number) => {
    const lineW = Math.max(baseWidth + extraWidth, 1.5 / gridScale);
    const radiusPx = Math.max(0.75, (lineW * gridScale) / 2);
    const rCeil = Math.ceil(radiusPx);
    const rSq = radiusPx * radiusPx;
    for (let i = 0; i < pts.length - 1; i++) {
      const ax = (pts[i].x - region.x) * gridScale;
      const ay = (pts[i].y - region.y) * gridScale;
      const bx = (pts[i + 1].x - region.x) * gridScale;
      const by = (pts[i + 1].y - region.y) * gridScale;
      const minX = Math.max(0, Math.floor(Math.min(ax, bx)) - rCeil);
      const maxX = Math.min(w - 1, Math.ceil(Math.max(ax, bx)) + rCeil);
      const minY = Math.max(0, Math.floor(Math.min(ay, by)) - rCeil);
      const maxY = Math.min(h - 1, Math.ceil(Math.max(ay, by)) + rCeil);
      const a = { x: ax, y: ay };
      const b = { x: bx, y: by };
      for (let py = minY; py <= maxY; py++) {
        const row = py * w;
        for (let px = minX; px <= maxX; px++) {
          if (out[row + px] === 255) continue;
          if (pointSegmentDistanceSquared({ x: px + 0.5, y: py + 0.5 }, a, b) <= rSq) {
            out[row + px] = 255;
          }
        }
      }
    }
  };

  for (const s of strokes) rasterPolyline(s.points, s.lineWidth);
  for (const sh of shapes) {
    for (const poly of shapeBarrierPolylines(sh)) rasterPolyline(poly, sh.lineWidth);
  }
  return out;
}

export function traceStrokeToContext(ctx: CanvasRenderingContext2D, stroke: Stroke): void {
  const pts = stroke.points;
  if (pts.length < 2) return;

  if (stroke.isCatmullRom) {
    const smoothed = smoothCatmullRom(pts);
    if (smoothed.length >= 4) {
      ctx.moveTo(smoothed[0].x, smoothed[0].y);
      let i = 1;
      while (i + 2 < smoothed.length) {
        ctx.bezierCurveTo(
          smoothed[i].x,
          smoothed[i].y,
          smoothed[i + 1].x,
          smoothed[i + 1].y,
          smoothed[i + 2].x,
          smoothed[i + 2].y
        );
        i += 3;
      }
      while (i < smoothed.length) {
        ctx.lineTo(smoothed[i].x, smoothed[i].y);
        i += 1;
      }
      return;
    }
  }

  ctx.moveTo(pts[0].x, pts[0].y);
  let prev = pts[0];
  for (let i = 1; i < pts.length; i++) {
    const pt = pts[i];
    const midX = (prev.x + pt.x) * 0.5;
    const midY = (prev.y + pt.y) * 0.5;
    ctx.quadraticCurveTo(prev.x, prev.y, midX, midY);
    prev = pt;
  }
  const last = pts[pts.length - 1];
  ctx.lineTo(last.x, last.y);
}

function findOpenSeed(
  sx: number,
  sy: number,
  barrier: Uint8Array,
  w: number,
  h: number
): [number, number] | null {
  if (sx > 0 && sx < w - 1 && sy > 0 && sy < h - 1 && barrier[sy * w + sx] < 64) {
    return [sx, sy];
  }
  for (let r = 1; r <= 4; r++) {
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        if (Math.abs(dx) !== r && Math.abs(dy) !== r) continue;
        const nx = sx + dx;
        const ny = sy + dy;
        if (nx > 0 && nx < w - 1 && ny > 0 && ny < h - 1 && barrier[ny * w + nx] < 64) {
          return [nx, ny];
        }
      }
    }
  }
  return null;
}

function dilateSeparable(src: Uint8Array, w: number, h: number, r: number): Uint8Array {
  const horiz = new Uint8Array(w * h);
  for (let y = 1; y < h - 1; y++) {
    const row = y * w;
    let count = 0;
    const initEnd = Math.min(w - 1, 1 + r);
    for (let x = 1; x < initEnd; x++) count += src[row + x];
    for (let x = 1; x < w - 1; x++) {
      const addX = x + r;
      if (addX < w - 1) count += src[row + addX];
      const remX = x - r - 1;
      if (remX >= 1) count -= src[row + remX];
      if (count > 0) horiz[row + x] = 1;
    }
  }

  const dst = new Uint8Array(w * h);
  for (let x = 1; x < w - 1; x++) {
    let count = 0;
    const initEnd = Math.min(h - 1, 1 + r);
    for (let y = 1; y < initEnd; y++) count += horiz[y * w + x];
    for (let y = 1; y < h - 1; y++) {
      const addY = y + r;
      if (addY < h - 1) count += horiz[addY * w + x];
      const remY = y - r - 1;
      if (remY >= 1) count -= horiz[remY * w + x];
      if (count > 0) dst[y * w + x] = 1;
    }
  }
  return dst;
}

type GridPt = [number, number];

function traceContours(mask: Uint8Array, w: number, h: number): GridPt[][] {
  const outgoing = new Map<number, GridPt[]>();
  const stride = w + 2;
  const encode = (x: number, y: number) => y * stride + x;

  const pushEdge = (x0: number, y0: number, x1: number, y1: number) => {
    const k = encode(x0, y0);
    let list = outgoing.get(k);
    if (!list) {
      list = [];
      outgoing.set(k, list);
    }
    list.push([x1, y1]);
  };

  for (let y = 1; y < h - 1; y++) {
    const row = y * w;
    for (let x = 1; x < w - 1; x++) {
      if (mask[row + x] === 0) continue;
      if (mask[(y - 1) * w + x] === 0) pushEdge(x, y, x + 1, y);
      if (mask[row + (x + 1)] === 0) pushEdge(x + 1, y, x + 1, y + 1);
      if (mask[(y + 1) * w + x] === 0) pushEdge(x + 1, y + 1, x, y + 1);
      if (mask[row + (x - 1)] === 0) pushEdge(x, y + 1, x, y);
    }
  }

  const loops: GridPt[][] = [];
  while (outgoing.size > 0) {
    const firstEntry = outgoing.entries().next().value as [number, GridPt[]] | undefined;
    if (!firstEntry) break;
    const [startKey, nextList] = firstEntry;
    if (nextList.length === 0) {
      outgoing.delete(startKey);
      continue;
    }

    const startX = startKey % stride;
    const startY = Math.floor(startKey / stride);
    const start: GridPt = [startX, startY];
    const loop: GridPt[] = [start];
    let currX = startX;
    let currY = startY;
    let prevDX = 0;
    let prevDY = 0;

    while (true) {
      const ck = encode(currX, currY);
      const candidates = outgoing.get(ck);
      if (!candidates || candidates.length === 0) break;

      let chosenIdx = 0;
      if (candidates.length > 1 && (prevDX !== 0 || prevDY !== 0)) {
        const rightDX = -prevDY;
        const rightDY = prevDX;
        const found = candidates.findIndex(
          ([nx, ny]) => nx - currX === rightDX && ny - currY === rightDY
        );
        if (found >= 0) chosenIdx = found;
      }

      const [nextX, nextY] = candidates.splice(chosenIdx, 1)[0];
      if (candidates.length === 0) outgoing.delete(ck);

      prevDX = nextX - currX;
      prevDY = nextY - currY;
      if (nextX === startX && nextY === startY) break;

      if (loop.length >= 2) {
        const a = loop[loop.length - 2];
        const b = loop[loop.length - 1];
        if ((b[0] - a[0]) * (nextY - b[1]) === (b[1] - a[1]) * (nextX - b[0])) {
          loop[loop.length - 1] = [nextX, nextY];
        } else {
          loop.push([nextX, nextY]);
        }
      } else {
        loop.push([nextX, nextY]);
      }

      currX = nextX;
      currY = nextY;
    }

    if (loop.length >= 3) {
      loops.push(loop);
    }
  }
  return loops;
}

function chaikinClosed(pts: Point[], maxInset: number): Point[] {
  const n = pts.length;
  if (n < 3) return pts;
  const out: Point[] = [];
  for (let i = 0; i < n; i++) {
    const p0 = pts[i];
    const p1 = pts[(i + 1) % n];
    const dx = p1.x - p0.x;
    const dy = p1.y - p0.y;
    const len = Math.hypot(dx, dy);
    if (len <= 1e-6) {
      out.push(p0);
      continue;
    }
    const t = Math.min(0.25, maxInset / len);
    out.push({ x: p0.x + dx * t, y: p0.y + dy * t });
    out.push({ x: p1.x - dx * t, y: p1.y - dy * t });
  }
  return out;
}
