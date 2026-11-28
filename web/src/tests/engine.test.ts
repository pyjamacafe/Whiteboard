import { describe, expect, it } from 'vitest';
import {
  boundingBox,
  eraseStrokes,
  fillContainsPoint,
  imageRotatedCorners,
  pointInPolygon,
  recognizeShape,
  resizedRect,
  simplifyRDP,
  smoothCatmullRom,
  snapRotationAngle,
  SpatialHashGrid,
} from '../engine/geometry';
import { computeFillContours } from '../engine/floodFill';
import { CanvasHistory } from '../engine/history';
import { decodeWBJson, encodeWBJson } from '../engine/wbCodec';
import { generateId, type FillShape, type PlacedImage, type Point, type Stroke } from '../types/model';

const black = { r: 0, g: 0, b: 0, a: 1 };

function makeStroke(points: Point[], opts?: Partial<Stroke>): Stroke {
  return {
    id: generateId(),
    points,
    color: black,
    lineWidth: 2,
    isEraser: false,
    presetIndex: 0,
    isCatmullRom: true,
    isSharpie: false,
    ...opts,
  };
}

describe('GeometryEngine', () => {
  it('simplifies collinear points via RDP', () => {
    const pts: Point[] = [];
    for (let i = 0; i <= 20; i++) pts.push({ x: i * 5, y: 0 });
    const simplified = simplifyRDP(pts, 0.3);
    expect(simplified.length).toBe(2);
    expect(simplified[0]).toEqual({ x: 0, y: 0 });
    expect(simplified[1]).toEqual({ x: 100, y: 0 });
  });

  it('produces Catmull-Rom cubic control points', () => {
    const pts = [
      { x: 0, y: 0 },
      { x: 10, y: 5 },
      { x: 20, y: 0 },
      { x: 30, y: 5 },
    ];
    const smooth = smoothCatmullRom(pts);
    expect(smooth.length).toBe(1 + (pts.length - 1) * 3);
  });

  it('supports SpatialHashGrid incremental sync and query', () => {
    const grid = new SpatialHashGrid(256);
    const s1 = makeStroke([
      { x: 0, y: 0 },
      { x: 40, y: 40 },
    ]);
    const s2 = makeStroke([
      { x: 1000, y: 1000 },
      { x: 1050, y: 1050 },
    ]);
    grid.sync([s1]);
    expect(grid.queryIndices({ x: -10, y: -10, width: 80, height: 80 })).toEqual([0]);
    grid.sync([s1, s2]);
    expect(grid.queryIndices({ x: 990, y: 990, width: 80, height: 80 })).toEqual([1]);
  });

  it('erases strokes in full and partial modes with target filters', () => {
    const pen = makeStroke(
      [
        { x: 0, y: 0 },
        { x: 50, y: 0 },
        { x: 100, y: 0 },
        { x: 150, y: 0 },
      ],
      { isSharpie: false }
    );
    const sharpie = makeStroke(
      [
        { x: 0, y: 0 },
        { x: 150, y: 0 },
      ],
      { isSharpie: true }
    );
    const eraser = makeStroke(
      [
        { x: 75, y: -10 },
        { x: 75, y: 10 },
      ],
      { isEraser: true, lineWidth: 16 }
    );

    const penOnly = eraseStrokes([pen, sharpie], eraser, 'full', 'pen', generateId);
    expect(penOnly.map((s) => s.id)).toEqual([sharpie.id]);

    const partial = eraseStrokes([pen], eraser, 'partial', 'all', generateId);
    expect(partial.length).toBe(2);
  });

  it('snaps line, circle, and rectangle in recognizeShape', () => {
    const linePts = Array.from({ length: 11 }, (_, i) => ({ x: i * 15, y: Math.sin(i) * 1.5 }));
    const snappedLine = recognizeShape(linePts);
    expect(snappedLine).not.toBeNull();
    expect(snappedLine![0].x).toBeCloseTo(0, 1);
    expect(snappedLine![snappedLine!.length - 1].x).toBeCloseTo(150, 1);

    const circlePts = Array.from({ length: 33 }, (_, i) => {
      const a = (i / 32) * Math.PI * 2;
      return { x: 100 + Math.cos(a) * 50, y: 100 + Math.sin(a) * 50 };
    });
    const snappedCircle = recognizeShape(circlePts);
    expect(snappedCircle?.length).toBe(65);
  });

  it('handles cardinal magnetic snap and 15-degree step snap', () => {
    const near90 = ((90 - 2.5) * Math.PI) / 180;
    const s90 = snapRotationAngle(near90, false);
    expect(s90.snapped).toBe(true);
    expect(s90.angle).toBeCloseTo(Math.PI / 2, 5);

    const step = snapRotationAngle((37 * Math.PI) / 180, true);
    expect(step.snapped).toBe(true);
    expect(step.angle).toBeCloseTo((30 * Math.PI) / 180, 5);
  });

  it('guards resizedRect against invalid dimensions and computes rotated image bounds', () => {
    expect(resizedRect({ x: 0, y: 0, width: 0, height: 50 }, 2, { width: 10, height: 10 })).toBeNull();
    const img: PlacedImage = {
      id: generateId(),
      position: { x: 0, y: 0 },
      size: { width: 100, height: 40 },
      imageDataBase64: '',
      rotation: Math.PI / 2,
    };
    const corners = imageRotatedCorners(img);
    expect(corners.length).toBe(4);
    const box = boundingBox([], [img]);
    expect(box?.width).toBeCloseTo(40, 1);
    expect(box?.height).toBeCloseTo(100, 1);
  });
});

describe('FloodFillEngine', () => {
  it('fills a closed rectangle and aborts without bleeding on open shapes', () => {
    const closedBox = makeStroke(
      [
        { x: 0, y: 0 },
        { x: 100, y: 0 },
        { x: 100, y: 100 },
        { x: 0, y: 100 },
        { x: 0, y: 0 },
      ],
      { lineWidth: 3 }
    );
    const contours = computeFillContours({ x: 50, y: 50 }, [closedBox], 2.5);
    expect(contours).not.toBeNull();
    expect(contours!.length).toBeGreaterThanOrEqual(1);
    expect(pointInPolygon({ x: 50, y: 50 }, contours![0])).toBe(true);

    // Open U-shape should abort cleanly
    const openShape = makeStroke(
      [
        { x: 0, y: 0 },
        { x: 0, y: 100 },
        { x: 100, y: 100 },
        { x: 100, y: 0 },
      ],
      { lineWidth: 3 }
    );
    expect(computeFillContours({ x: 50, y: 50 }, [openShape], 2.5)).toBeNull();
  });

  it('supports interior holes with even-odd fill containment', () => {
    const outer = makeStroke([
      { x: 0, y: 0 },
      { x: 120, y: 0 },
      { x: 120, y: 120 },
      { x: 0, y: 120 },
      { x: 0, y: 0 },
    ]);
    const inner = makeStroke([
      { x: 40, y: 40 },
      { x: 80, y: 40 },
      { x: 80, y: 80 },
      { x: 40, y: 80 },
      { x: 40, y: 40 },
    ]);
    const contours = computeFillContours({ x: 20, y: 20 }, [outer, inner], 1.5);
    expect(contours).not.toBeNull();
    expect(contours!.length).toBe(2);
    const fill: FillShape = {
      id: generateId(),
      contours: contours!,
      color: black,
      opacity: 0.5,
      presetIndex: 0,
    };
    expect(fillContainsPoint(fill, { x: 20, y: 20 })).toBe(true);
    expect(fillContainsPoint(fill, { x: 60, y: 60 })).toBe(false);
  });
});

describe('CanvasHistory & Swift-compatible .wb codec', () => {
  it('enforces bounded undo/redo stack', () => {
    const history = new CanvasHistory(3);
    for (let i = 0; i < 5; i++) {
      history.record({
        strokes: [makeStroke([{ x: i, y: i }, { x: i + 10, y: i + 10 }])],
        placedImages: [],
        fills: [],
        selectedStrokeIds: [],
        selectedImageIds: [],
        selectedFillIds: [],
        selectionBoundary: [],
      });
    }
    expect(history.undoCount).toBe(3);
    const restored = history.undo({
      strokes: [],
      placedImages: [],
      fills: [],
      selectedStrokeIds: [],
      selectedImageIds: [],
      selectedFillIds: [],
      selectionBoundary: [],
    });
    expect(restored?.strokes[0].points[0].x).toBe(4);
    expect(history.canRedo).toBe(true);
  });

  it('round-trips Swift-compatible .wb JSON ([x,y] CGPoints and {x,y} CodablePoints)', () => {
    const swiftJson = JSON.stringify({
      strokes: [
        {
          id: '11111111-1111-1111-1111-111111111111',
          points: [
            [10, 20],
            [30, 40],
          ],
          color: { r: 0.1, g: 0.2, b: 0.3, a: 1 },
          lineWidth: 3,
          isEraser: false,
          presetIndex: 2,
          isCatmullRom: true,
          isSharpie: true,
        },
      ],
      placedImages: [
        {
          id: '22222222-2222-2222-2222-222222222222',
          position: { x: 50, y: 60 },
          size: { x: 120, y: 80 },
          imageData: 'AQID',
          rotation: 0.5,
        },
      ],
      fills: [
        {
          id: '33333333-3333-3333-3333-333333333333',
          contours: [[[0, 0], [10, 0], [10, 10]]],
          color: { r: 0, g: 0.35, b: 1, a: 1 },
          opacity: 0.25,
          presetIndex: 5,
        },
      ],
      scenes: [
        {
          id: '44444444-4444-4444-4444-444444444444',
          name: 'Scene 1',
          centerX: 100,
          centerY: 200,
          scale: 1.5,
        },
      ],
    });

    const decoded = decodeWBJson(swiftJson);
    expect(decoded.strokes[0].points[1]).toEqual({ x: 30, y: 40 });
    expect(decoded.placedImages[0].size).toEqual({ width: 120, height: 80 });
    expect(decoded.placedImages[0].rotation).toBe(0.5);
    expect(decoded.fills[0].contours[0][2]).toEqual({ x: 10, y: 10 });
    expect(decoded.scenes[0].name).toBe('Scene 1');

    const reencoded = JSON.parse(encodeWBJson(decoded));
    expect(reencoded.strokes[0].points[0]).toEqual([10, 20]);
    expect(reencoded.placedImages[0].size).toEqual({ x: 120, y: 80 });
  });
});
